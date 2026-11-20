#!/bin/bash
# 설치와 업데이트를 한 번에: 최신 코드를 받고 ~/.claude/skills 에 복사한다.
# 사용: bash ~/claude-skill-manager/install.sh   (macOS 터미널 / 윈도우 Git Bash)
# 개인 데이터(~/.claude/skill-archive: 매핑 표, 추천 기록, 제거 기록, 카탈로그)는 건드리지 않는다.
set -e
REPO="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO"
if [ -d .git ]; then git pull --ff-only -q || echo "git pull 실패: 로컬 수정이 있으면 정리 후 다시 실행"; fi
mkdir -p "$HOME/.claude/skills" "$HOME/.claude/skill-archive"
for d in skills/*/; do
  n=$(basename "$d")
  rm -rf "$HOME/.claude/skills/$n"
  cp -R "$d" "$HOME/.claude/skills/$n"
  echo "설치: $n"
done
# 매핑 표는 처음 한 번만 기본값으로 만든다. 이미 있으면 개인 학습 내용을 지키기 위해 그대로 둔다.
[ -f "$HOME/.claude/skill-archive/mapping.md" ] || cp skills/pick/mapping.default.md "$HOME/.claude/skill-archive/mapping.md"
command -v gh >/dev/null || echo "주의: gh 가 없음 (macOS: brew install gh / 윈도우: winget install GitHub.cli)"
command -v jq >/dev/null || echo "주의: jq 가 없음 (macOS: brew install jq / 윈도우: winget install jqlang.jq)"
echo "완료 ($(git rev-parse --short HEAD 2>/dev/null || echo 버전 모름)). 새 Claude Code 세션부터 적용."
