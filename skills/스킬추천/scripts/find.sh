#!/bin/bash
# 외부 스킬 후보를 한 번의 호출로 찾는다. 출력은 짧게 잘라 토큰을 아낀다.
# 사용: bash find.sh [--all] [--refresh] <영어 키워드> [키워드2 ...]
#   --all      공식에서 찾아도 제3자 깃헙까지 검색
#   --refresh  공식 카탈로그 캐시를 강제로 새로 받음
# 순서: 제거 기록 -> 공식 카탈로그(로컬 캐시) -> 제3자 깃헙(실시간, 필요할 때만)

ARCHIVE="$HOME/.claude/skill-archive"
CATALOG="$ARCHIVE/catalog.tsv"
REMOVED="$ARCHIVE/removed.md"
ALL=0; REFRESH=0; KW=()
for a in "$@"; do
  case "$a" in
    --all) ALL=1 ;;
    --refresh) REFRESH=1 ;;
    *) KW+=("$a") ;;
  esac
done
[ ${#KW[@]} -eq 0 ] && { echo "키워드 필요"; exit 1; }
PATTERN=$(IFS='|'; echo "${KW[*]}")
mkdir -p "$ARCHIVE"

# 0. 예전에 제거한 스킬이면 바로 복구할 수 있다.
if [ -f "$REMOVED" ]; then
  HIT=$(grep -i -E "$PATTERN" "$REMOVED" | head -5)
  if [ -n "$HIT" ]; then
    echo "== 제거 기록에 있음 (복구가 가장 빠름) =="
    echo "$HIT"
    [ $ALL -eq 0 ] && exit 0
  fi
fi

# 1. 공식 카탈로그: 30일에 한 번만 받아 로컬에 둔다.
build_catalog() {
  : > "$CATALOG.tmp"
  # anthropics/skills: 스킬별 SKILL.md의 description 한 줄
  for n in $(gh api repos/anthropics/skills/contents/skills --jq '.[]|select(.type=="dir")|.name' 2>/dev/null); do
    d=$(gh api "repos/anthropics/skills/contents/skills/$n/SKILL.md" -H "Accept: application/vnd.github.raw" 2>/dev/null \
        | awk '/^description:/{sub(/^description: */,""); if($0 ~ /^[>|][-+]?$/){getline; sub(/^ +/,"")} print; exit}' | cut -c1-180 | tr '\t' ' ')
    printf '1-official\tanthropics/skills/skills/%s\t%s\n' "$n" "$d" >> "$CATALOG.tmp"
  done
  # 공식 마켓플레이스와 Anthropic 스타 상위 레포의 플러그인 목록
  for spec in "1-official:claude-plugins-official" "2-anthropic:knowledge-work-plugins" "2-anthropic:claude-code" "2-anthropic:financial-services"; do
    tier=${spec%%:*}; repo=${spec##*:}
    gh api "repos/anthropics/$repo/contents/.claude-plugin/marketplace.json" -H "Accept: application/vnd.github.raw" 2>/dev/null \
      | jq -r --arg t "$tier" --arg r "$repo" '.plugins[]? | [$t, "anthropics/\($r) plugin:\(.name)", ((.description // "")[0:180] | gsub("[\t\n]";" "))] | @tsv' \
      >> "$CATALOG.tmp" 2>/dev/null
  done
  if [ -s "$CATALOG.tmp" ]; then mv "$CATALOG.tmp" "$CATALOG"; else rm -f "$CATALOG.tmp"; echo "카탈로그 받기 실패 (gh 로그인/네트워크 확인)"; fi
}
if [ $REFRESH -eq 1 ] || [ ! -s "$CATALOG" ] || [ -n "$(find "$CATALOG" -mtime +30 2>/dev/null)" ]; then
  build_catalog
fi

# 설치된 스킬 이름(개인 + 플러그인). 겹치면 [설치됨] 표시해 중복 설치를 막는다.
INSTALLED=$( { ls "$HOME/.claude/skills" 2>/dev/null; ls "$HOME"/.claude/skills/synced/*/ 2>/dev/null; find "$HOME/.claude/plugins/cache" -name SKILL.md 2>/dev/null | awk -F/ '{print $(NF-1)}'; } | sort -u)
mark() { while IFS= read -r line; do
  n=$(echo "$line" | cut -f2 | sed -E 's/.*(plugin:|skills\/)//')
  if echo "$INSTALLED" | grep -qx "$n"; then echo "[설치됨] $line"; else echo "$line"; fi
done; }
# 키워드가 많이 맞는 줄을 위로. 키워드 하나라도 맞아야 후보.
OFFICIAL=""
if [ -s "$CATALOG" ]; then
  awk -F'\t' -v kw="$(IFS=' '; echo "${KW[*]}")" 'BEGIN{n=split(tolower(kw),k," ")}
    {l=tolower($0); nm=tolower($2); s=0; for(i=1;i<=n;i++){ if(index(nm,k[i])) s+=3; else if(index(l,k[i])) s++ } if(s>0) print s"\t"$0}' "$CATALOG" \
    | sort -t$'\t' -k1,1nr -k2,2 | head -6 > "$ARCHIVE/.hits"
  OFFICIAL=$(cut -f2- "$ARCHIVE/.hits" | mark)
  # 이름에 키워드가 들어간 후보(점수 3 이상)가 있을 때만 "공식에서 찾음"으로 본다.
  STRONG=$(awk -F'\t' '$1>=3' "$ARCHIVE/.hits" | head -1)
fi
if [ -n "$OFFICIAL" ]; then
  echo "== 공식/Anthropic 후보 (tier, 위치, 설명) =="
  echo "$OFFICIAL"
  if [ -n "$STRONG" ] && [ $ALL -eq 0 ]; then echo "(이름이 맞는 공식 후보 있음: 제3자 검색 생략. 더 보려면 --all)"; exit 0; fi
  echo "(설명만 겹치는 약한 후보: 제3자도 함께 확인)"
else
  echo "== 공식/Anthropic 후보 없음 =="
fi

# 2. 제3자 깃헙: 공식에 없을 때만. 스타 50 이상, 5개, 설명 100자.
echo "== 제3자 깃헙 후보 (레포, 스타, 최근 push, 라이선스, 설명) =="
Q="${KW[*]}"
{ gh search repos "${KW[0]}" --topic claude-skills --stars ">=20" --sort stars --limit 5 \
    --json fullName,stargazersCount,pushedAt,license,description \
    --jq '.[]|[.fullName, .stargazersCount, .pushedAt[0:10], (.license.key // "none"), ((.description // "")[0:100])]|@tsv' 2>/dev/null
  gh search repos "${KW[0]} skill" --stars ">=50" --sort stars --limit 5 \
    --json fullName,stargazersCount,pushedAt,license,description \
    --jq '.[]|[.fullName, .stargazersCount, .pushedAt[0:10], (.license.key // "none"), ((.description // "")[0:100])]|@tsv' 2>/dev/null
} | sort -u -t$'\t' -k1,1 | sort -t$'\t' -k2,2nr | head -5
