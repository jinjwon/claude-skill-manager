#!/bin/bash
# ~/.claude/skills 의 스킬추천·스킬제거를 이 레포로 복사하고, 바뀐 게 있으면 커밋·푸시한다.
# Claude Code 훅에서 자동 실행된다. 직접 실행해도 된다: bash ~/claude-skill-manager/sync.sh
REPO="$(cd "$(dirname "$0")" && pwd)"
SRC="$HOME/.claude/skills"
for s in 스킬추천 스킬제거; do
  [ -d "$SRC/$s" ] && rsync -a --delete --exclude '.DS_Store' "$SRC/$s/" "$REPO/skills/$s/"
done
cd "$REPO" || exit 0
git add -A skills
git diff --cached --quiet && exit 0
CHANGED=$(git diff --cached --name-only | sed 's#skills/##' | cut -d/ -f1 | sort -u | tr '\n' ' ')
git commit -q -m "Auto-sync: ${CHANGED% }" || exit 0
# 푸시는 백그라운드로: 훅이 Claude를 기다리게 하지 않는다. 실패하면 다음 동기화 때 같이 올라간다.
( git push -q origin main >> "$REPO/.sync.log" 2>&1 & )
echo "{\"systemMessage\": \"스킬 레포 동기화: ${CHANGED% }\"}"
