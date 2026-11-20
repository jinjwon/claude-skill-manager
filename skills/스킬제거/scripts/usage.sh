#!/bin/bash
# 설치된 개인 스킬별 호출 횟수를 센다 (전체 / 현재 프로젝트).
# 사용: bash usage.sh
# 출력: 이름 <tab> 전체 호출 <tab> 이 프로젝트 호출 <tab> 설치 후 일수 <tab> 설명(80자)
# 호출 = Skill 도구 호출 + 슬래시 명령(/이름). 기록은 ~/.claude/projects 의 대화 로그.

SK="$HOME/.claude/skills"
PJ="$HOME/.claude/projects"
# 윈도우(Git Bash)는 pwd -W 가 C:/Users/.. 형태를 준다. Claude Code 프로젝트 폴더 이름 규칙과 맞추기 위해 사용.
CUR="$PJ/$( (pwd -W 2>/dev/null || pwd) | sed 's/[^A-Za-z0-9]/-/g')"
# stat 은 macOS(BSD)와 윈도우·리눅스(GNU) 옵션이 다르다.
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }
btime() { b=$(stat -c %W "$1" 2>/dev/null); case "$b" in ''|0|-|*[!0-9]*) b=$(stat -f %B "$1" 2>/dev/null || mtime "$1");; esac; echo "$b"; }
TMP=$(mktemp)

# 대화 로그에서 "파일경로:스킬이름" 목록을 만든다.
# 실제 호출만 센다: assistant 메시지의 Skill 도구 호출 + user가 입력한 /명령.
# (api-request-blob 같은 사본 줄은 빼야 두 배로 세지 않는다)
find "$PJ" -name '*.jsonl' | while read -r f; do
  grep -h -E '"name":"Skill"|<command-name>' "$f" 2>/dev/null | jq -r --arg f "$f" '
    if .type=="assistant" then (.message.content[]? | select(.type=="tool_use" and .name=="Skill") | .input.skill)
    elif .type=="user" then ((.message.content | if type=="string" then . else (map(.text? // "")|join(" ")) end)
                             | scan("<command-name>/([^<]*)</command-name>")[0])
    else empty end | "\($f):\(.)"' 2>/dev/null | tr -d '\r'
done > "$TMP"

OLDF=$(find "$PJ" -name '*.jsonl' -print0 2>/dev/null | xargs -0 ls -tr 2>/dev/null | head -1)
OLDEST=$([ -n "$OLDF" ] && mtime "$OLDF")
[ -n "$OLDEST" ] && echo "# 기록 범위: 최근 $(( ( $(date +%s) - OLDEST ) / 86400 ))일 (그 이전 호출은 셀 수 없음)"
echo "# 현재 프로젝트: $(pwd)"

for d in "$SK"/*/; do
  n=$(basename "$d")
  [ -f "$d/SKILL.md" ] || continue
  total=$(grep -c -E ":$n\$" "$TMP")
  here=$(grep -E ":$n\$" "$TMP" | grep -c -F "$CUR/")
  age=$(( ( $(date +%s) - $(btime "$d") ) / 86400 ))
  desc=$(awk '/^description:/{sub(/^description: */,""); if($0 ~ /^[>|][-+]?$/){getline; sub(/^ +/,"")} print; exit}' "$d/SKILL.md" | cut -c1-80)
  printf '%s\t%s\t%s\t%s일\t%s\n' "$n" "$total" "$here" "$age" "$desc"
done | sort -t$'\t' -k2,2n
rm -f "$TMP"
