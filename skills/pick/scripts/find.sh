#!/bin/bash
# 외부 스킬 후보를 한 번의 호출로 찾는다. 출력은 짧게 잘라 토큰을 아낀다.
# 사용: bash find.sh [--all] [--refresh] <영어 키워드> [키워드2 ...]
#       bash find.sh --top [개수]     # 지금 인기·트렌드 스킬 레포 목록
#   --all      로컬 카탈로그에서 찾아도 깃헙 실시간 검색까지
#   --refresh  카탈로그 두 개를 강제로 새로 받음
#   --local    네트워크 0: 캐시가 오래돼도 갱신 안 함, 실시간 검색 안 함 (/pick 이 매번 가볍게 훑을 때)
# 순서: 제거 기록 -> 공식 카탈로그(30일 캐시) -> 인기·트렌드 카탈로그(7일 캐시) -> 깃헙 실시간(필요할 때만)
# macOS 와 윈도우(Git Bash) 모두에서 돈다. 필요: gh(로그인), jq.

ARCHIVE="$HOME/.claude/skill-archive"
CATALOG="$ARCHIVE/catalog.tsv"   # tier \t 위치 \t 설명            (공식·Anthropic)
POPULAR="$ARCHIVE/popular.tsv"   # tier \t 위치 \t 스타 \t 설명     (인기·트렌드)
REMOVED="$ARCHIVE/removed.md"
ALL=0; REFRESH=0; TOP=0; LOCAL=0; KW=()
for a in "$@"; do
  case "$a" in
    --all) ALL=1 ;;
    --refresh) REFRESH=1 ;;
    --local) LOCAL=1 ;;
    --top) TOP=15 ;;
    *) if [ $TOP -gt 0 ] && [[ "$a" =~ ^[0-9]+$ ]]; then TOP=$a; else KW+=("$a"); fi ;;
  esac
done
[ $TOP -eq 0 ] && [ ${#KW[@]} -eq 0 ] && { echo "키워드 필요 (또는 --top)"; exit 1; }
mkdir -p "$ARCHIVE"
stale() { [ $LOCAL -eq 0 ] || return 1; [ $REFRESH -eq 1 ] || [ ! -s "$1" ] || [ -n "$(find "$1" -mtime +"$2" 2>/dev/null)" ]; }
# N일 전 날짜: macOS(BSD date) 와 Git Bash(GNU date) 옵션이 다르다.
days_ago() { date -v-"$1"d +%F 2>/dev/null || date -d "$1 days ago" +%F; }
desc_of() { awk '/^description:/{sub(/^description: */,""); if($0 ~ /^[>|][-+]?$/){getline; sub(/^ +/,"")} print; exit}' | cut -c1-180 | tr '\t\r' '  '; }

# ---------- 카탈로그 만들기 ----------
build_official() {
  : > "$CATALOG.tmp"
  for n in $(gh api repos/anthropics/skills/contents/skills --jq '.[]|select(.type=="dir")|.name' 2>/dev/null); do
    d=$(gh api "repos/anthropics/skills/contents/skills/$n/SKILL.md" -H "Accept: application/vnd.github.raw" 2>/dev/null | desc_of)
    printf '1-official\tanthropics/skills/skills/%s\t%s\n' "$n" "$d" >> "$CATALOG.tmp"
  done
  for spec in "1-official:claude-plugins-official" "2-anthropic:knowledge-work-plugins" "2-anthropic:claude-code" "2-anthropic:financial-services"; do
    tier=${spec%%:*}; repo=${spec##*:}
    gh api "repos/anthropics/$repo/contents/.claude-plugin/marketplace.json" -H "Accept: application/vnd.github.raw" 2>/dev/null \
      | jq -r --arg t "$tier" --arg r "$repo" '.plugins[]? | [$t, "anthropics/\($r) plugin:\(.name)", ((.description // "")[0:180] | gsub("[\t\n]";" "))] | @tsv' \
      2>/dev/null | tr -d '\r' >> "$CATALOG.tmp"
  done
  if [ -s "$CATALOG.tmp" ]; then mv "$CATALOG.tmp" "$CATALOG"; else rm -f "$CATALOG.tmp"; echo "공식 카탈로그 받기 실패 (gh 로그인/네트워크 확인)"; fi
}

# 인기(스킬 토픽 스타 상위) + 트렌드(최근 90일 새로 생겨 스타가 빨리 붙은 레포).
# 레포마다 트리 1번만 받아 SKILL.md 가 든 폴더 이름을 스킬 이름으로 쓴다. 설명은 레포 설명.
build_popular() {
  echo "(인기·트렌드 카탈로그 갱신 중: 1분 안팎)" >&2
  since=$(days_ago 90); fresh=$(days_ago 180)
  Q='.[]|[.fullName, .stargazersCount, .pushedAt[0:10], ((.description // "")[0:140] | gsub("[\t\n\r]";" "))]|@tsv'
  { for t in claude-skills agent-skills claude-code-skills claude-code-plugin; do
      gh search repos --topic "$t" --stars ">=300" --sort stars --limit 30 --json fullName,stargazersCount,pushedAt,description --jq "$Q" 2>/dev/null
      gh search repos --topic "$t" --created ">=$since" --stars ">=100" --sort stars --limit 10 --json fullName,stargazersCount,pushedAt,description --jq "$Q" 2>/dev/null
    done
    gh search repos "skills in:name,description,topics" --created ">=$since" --stars ">=200" --sort stars --limit 30 \
      --json fullName,stargazersCount,pushedAt,description --jq "$Q" 2>/dev/null
  } | awk -F'\t' -v f="$fresh" '$3>=f && $1 !~ /^anthropics\//' | LC_ALL=C sort -u -t$'\t' -k1,1 | LC_ALL=C sort -t$'\t' -k2,2nr | head -50 > "$POPULAR.repos"
  : > "$POPULAR.tmp"
  while IFS=$'\t' read -r repo stars pushed desc; do
    created_recent=$(gh api "repos/$repo" --jq ".created_at[0:10] >= \"$since\"" 2>/dev/null)
    tier=3-popular; [ "$created_recent" = "true" ] && tier=3-trending
    printf '%s\t%s\t%s\t%s\n' "$tier" "$repo" "$stars" "$desc" >> "$POPULAR.tmp"
    gh api "repos/$repo/git/trees/HEAD?recursive=1" --jq '.tree[].path | select(. == "SKILL.md" or endswith("/SKILL.md"))' 2>/dev/null \
      | sed 's#/*SKILL.md$##' | head -80 | while read -r p; do
        [ -z "$p" ] && continue   # 루트 SKILL.md 단일 스킬 레포: 위의 레포 줄이 이미 대표한다
        printf '%s\t%s/%s\t%s\t%s\n' "$tier" "$repo" "$p" "$stars" "$desc"
      done >> "$POPULAR.tmp"
  done < "$POPULAR.repos"
  rm -f "$POPULAR.repos"
  if [ -s "$POPULAR.tmp" ]; then tr -d '\r' < "$POPULAR.tmp" > "$POPULAR"; fi; rm -f "$POPULAR.tmp"
}
stale "$CATALOG" 30 && build_official
stale "$POPULAR" 7 && build_popular

# ---------- --top: 지금 좋은 스킬 레포 목록 ----------
if [ $TOP -gt 0 ]; then
  echo "== 인기·트렌드 스킬 레포 상위 $TOP (tier, 레포, 스타, 스킬 수, 설명) =="
  awk -F'\t' '{split($2,a,"/"); r=a[1]"/"a[2]; if($2==r){row[r]=$0} else cnt[r]++}
    END{for(r in row){split(row[r],f,"\t"); print f[1]"\t"f[2]"\t"f[3]"\t"(cnt[r]+0)"\t"substr(f[4],1,90)}}' "$POPULAR" \
    | LC_ALL=C sort -t$'\t' -k3,3nr | head -"$TOP"
  exit 0
fi

PATTERN=$(IFS='|'; echo "${KW[*]}")
# ---------- 0. 제거 기록 ----------
if [ -f "$REMOVED" ]; then
  HIT=$(grep -i -E "$PATTERN" "$REMOVED" | head -5)
  if [ -n "$HIT" ]; then
    echo "== 제거 기록에 있음 (복구가 가장 빠름) =="
    echo "$HIT"
    [ $ALL -eq 0 ] && exit 0
  fi
fi

# 설치된 스킬 이름(개인 + 동기화 + 플러그인). 겹치면 [설치됨] 표시해 중복 설치를 막는다.
INSTALLED=$( { ls "$HOME/.claude/skills" 2>/dev/null; ls "$HOME"/.claude/skills/synced/*/ 2>/dev/null; find "$HOME/.claude/plugins/cache" -name SKILL.md 2>/dev/null | awk -F/ '{print $(NF-1)}'; } | LC_ALL=C sort -u)
mark() { while IFS= read -r line; do
  n=$(echo "$line" | cut -f3 | sed -E 's#.*(plugin:|/)##')
  # 이름만 비교하므로 다른 레포의 같은 이름 스킬도 걸린다. 확인용 표시.
  if echo "$INSTALLED" | grep -qx "$n"; then echo "[같은 이름 설치됨] $line"; else echo "$line"; fi
done; }

# ---------- 1. 로컬 카탈로그 두 개를 함께 점수 매김 ----------
# 점수: 이름에 키워드 +3, 설명에만 +1. 같은 점수면 tier(공식 우선) -> 스타 순.
# 출력 열: 점수 \t tier \t 위치 \t 스타 \t 설명
KWS="$(IFS=' '; echo "${KW[*]}")"
{ [ -s "$CATALOG" ] && awk -F'\t' '{print $1"\t"$2"\t-\t"$3}' "$CATALOG"; [ -s "$POPULAR" ] && cat "$POPULAR"; } \
  | awk -F'\t' -v kw="$KWS" 'BEGIN{n=split(tolower(kw),k," ")}
      {l=tolower($0); m=split(tolower($2),pp,"/"); nm=pp[m]; s=0
       for(i=1;i<=n;i++){ if(index(nm,k[i])) s+=3; else if(index(l,k[i])) s++ }
       if(s>0) print s"\t"$0}' \
  | LC_ALL=C sort -t$'\t' -k1,1nr -k2,2 -k4,4nr | head -8 > "$ARCHIVE/.hits"
if [ -s "$ARCHIVE/.hits" ]; then
  echo "== 로컬 카탈로그 후보 (점수, tier, 위치, 스타, 설명) =="
  cut -c1-230 "$ARCHIVE/.hits" | mark
  STRONG=$(awk -F'\t' '$1>=3' "$ARCHIVE/.hits" | head -1)
  if [ -n "$STRONG" ] && [ $ALL -eq 0 ]; then echo "(이름이 맞는 후보 있음: 실시간 검색 생략. 더 보려면 --all)"; exit 0; fi
  [ $LOCAL -eq 1 ] && exit 0
  echo "(설명만 겹치는 약한 후보: 실시간 검색도 함께)"
else
  echo "== 로컬 카탈로그 후보 없음 =="
  [ $LOCAL -eq 1 ] && exit 0
fi

# ---------- 2. 깃헙 실시간 ----------
echo "== 깃헙 실시간 후보 (레포, 스타, 최근 push, 라이선스, 설명) =="
J='.[]|[.fullName, .stargazersCount, .pushedAt[0:10], (.license.key // "none"), ((.description // "")[0:100])]|@tsv'
{ gh search repos "${KW[0]}" --topic claude-skills --stars ">=20" --sort stars --limit 5 --json fullName,stargazersCount,pushedAt,license,description --jq "$J" 2>/dev/null
  gh search repos "${KW[0]} skill" --stars ">=50" --sort stars --limit 5 --json fullName,stargazersCount,pushedAt,license,description --jq "$J" 2>/dev/null
} | LC_ALL=C sort -u -t$'\t' -k1,1 | LC_ALL=C sort -t$'\t' -k2,2nr | head -5
