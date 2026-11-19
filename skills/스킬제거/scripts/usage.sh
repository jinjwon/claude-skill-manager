#!/bin/bash
# 설치된 개인 스킬별 호출 횟수를 센다 (전체 / 현재 프로젝트).
# 사용: bash usage.sh
# 출력: 이름 <tab> 전체 호출 <tab> 이 프로젝트 호출 <tab> 설치 후 일수 <tab> 설명(80자)
# 호출 = Skill 도구 호출 + 슬래시 명령(/이름). 기록은 ~/.claude/projects 의 대화 로그.

SK="$HOME/.claude/skills"
PJ="$HOME/.claude/projects"
CUR="$PJ/$(pwd | sed 's/[^A-Za-z0-9]/-/g')"
TMP=$(mktemp)

# 대화 로그에서 "파일경로:스킬이름" 목록을 만든다.
# 실제 호출만 센다: assistant 메시지의 Skill 도구 호출 + user가 입력한 /명령.
# (api-request-blob 같은 사본 줄은 빼야 두 배로 세지 않는다)
find "$PJ" -name '*.jsonl' | while read -r f; do
  grep -h -E '"name":"Skill"|<command-name>' "$f" 2>/dev/null | jq -r --arg f "$f" '
    if .type=="assistant" then (.message.content[]? | select(.type=="tool_use" and .name=="Skill") | .input.skill)
    elif .type=="user" then ((.message.content | if type=="string" then . else (map(.text? // "")|join(" ")) end)
                             | scan("<command-name>/([^<]*)</command-name>")[0])
    else empty end | "\($f):\(.)"' 2>/dev/null
done > "$TMP"

OLDEST=$(find "$PJ" -name '*.jsonl' -exec stat -f '%m' {} + 2>/dev/null | sort -n | head -1)
[ -n "$OLDEST" ] && echo "# 기록 범위: 최근 $(( ( $(date +%s) - OLDEST ) / 86400 ))일 (그 이전 호출은 셀 수 없음)"
echo "# 현재 프로젝트: $(pwd)"

for d in "$SK"/*/; do
  n=$(basename "$d")
  [ -f "$d/SKILL.md" ] || continue
  total=$(grep -c -E ":$n\$" "$TMP")
  here=$(grep -E ":$n\$" "$TMP" | grep -c -F "$CUR/")
  age=$(( ( $(date +%s) - $(stat -f '%B' "$d") ) / 86400 ))
  desc=$(awk '/^description:/{sub(/^description: */,""); if($0 ~ /^[>|][-+]?$/){getline; sub(/^ +/,"")} print; exit}' "$d/SKILL.md" | cut -c1-80)
  printf '%s\t%s\t%s\t%s일\t%s\n' "$n" "$total" "$here" "$age" "$desc"
done | sort -t$'\t' -k2,2n
rm -f "$TMP"
