# claude-skill-manager

Claude Code에서 **어떤 스킬을 쓸지 고르고, 없으면 찾아 설치하고, 안 쓰는 스킬은 정리하는** 개인 스킬 2개.

| 스킬 | 하는 일 |
|---|---|
| `스킬추천` | 요청에 맞는 스킬 후보를 골라 한 줄씩 보여 주고, 추천대로 / 변경 / 추가 중 하나를 한 번 확인한 뒤 실행. 맞는 게 없으면 외부 스킬을 찾거나 프로젝트 맞춤 스킬을 만든다. |
| `스킬제거` | 호출 0회 + 현재 프로젝트에 안 맞음 + 설치 14일 초과인 스킬만 골라, 허락받고 보관 폴더로 옮기고 기록을 남긴다. 나중에 바로 복구 가능. |

## 빠른 시작

필요한 것: [Claude Code](https://claude.com/claude-code), `gh`(GitHub CLI, `gh auth login` 완료), `jq`. macOS와 윈도우 모두 지원.

| | 도구 설치 |
|---|---|
| macOS | `brew install gh jq` |
| 윈도우 | `winget install GitHub.cli jqlang.jq` (Git Bash는 Claude Code 설치 때 함께 필요) |

설치(macOS 터미널 / 윈도우 **Git Bash**에서 같은 명령):
```bash
git clone https://github.com/jinjwon/claude-skill-manager.git ~/claude-skill-manager
mkdir -p ~/.claude/skills && cp -R ~/claude-skill-manager/skills/* ~/.claude/skills/
```
윈도우에서 `~`는 `C:\Users\<이름>`이다. 스크립트는 모두 bash라서 Claude Code가 윈도우에서 쓰는 Git Bash로 그대로 돈다.

새 Claude Code 세션을 열면 바로 쓸 수 있다.

```
/스킬추천 이 피그마 시안 개발 넘기기 전에 봐줘 <링크>
/스킬제거
```

업데이트: `git pull` 후 위 `cp` 명령을 다시 실행.

### 자동 동기화 (선택)
`~/.claude/skills`에서 스킬을 고치면 이 레포에 자동으로 커밋·푸시되게 할 수 있다. `sync.sh`가 두 스킬을 레포로 복사하고, 바뀐 게 있을 때만 커밋하고 백그라운드로 푸시한다.

`~/.claude/settings.json`의 `hooks`에 추가:
```json
"PostToolUse": [{
  "matcher": "Edit|Write|MultiEdit|Bash",
  "hooks": [{ "type": "command", "command": "grep -q -E 'skills|스킬' && bash ~/claude-skill-manager/sync.sh || true" }]
}],
"SessionStart": [{
  "hooks": [{ "type": "command", "command": "bash ~/claude-skill-manager/sync.sh >/dev/null 2>&1 || true" }]
}]
```
- PostToolUse: Claude가 두 스킬 파일을 고치면 바로 동기화.
- SessionStart: 직접 편집기로 고친 것도 다음 세션 시작 때 올라감.
- 푸시 실패 기록: `~/claude-skill-manager/.sync.log`. 수동 실행: `bash ~/claude-skill-manager/sync.sh`.

## 스킬추천

### 흐름
1. 요청을 한 줄로 요약한다.
2. 매핑 표 **와** 세션의 전체 스킬 목록을 같이 보고 후보를 고른다(추천 최대 3개 + 대안 1~2개).
3. 한 번 확인한다. 질문 창에 `이름 — 무슨 스킬 — 왜 쓰는지`가 한 줄씩 뜬다.
   - 추천대로 진행 / 대안으로 변경 / 추천 + 추가 / 맞춤 스킬 제작(조건 맞을 때만) / 직접 입력
4. 고른 스킬로 실행. 작업 중에는 다시 묻지 않는다.
5. 대안·추가·직접 입력을 골랐으면 매핑 표를 그 선택으로 고친다. 쓸수록 첫 추천이 맞아진다.

이럴 때도 불린다: "이거 하는 스킬 있어?", "스킬 찾아줘", 있는 스킬로 두 번 해도 막혔을 때(외부 탐색을 한 줄로 제안).

요청에 스킬 이름을 직접 적었거나, 같은 대화에서 같은 종류 작업을 이미 확인했다면 질문을 건너뛴다.

### 스킬이 없을 때
설치된 스킬로 핵심 작업이 안 될 때만 외부를 찾는다. 검색은 스크립트 한 줄로 끝낸다.

```bash
bash ~/.claude/skills/스킬추천/scripts/find.sh <영어 키워드> [키워드2]
bash ~/.claude/skills/스킬추천/scripts/find.sh --all <키워드>   # 제3자까지 강제로 비교
bash ~/.claude/skills/스킬추천/scripts/find.sh --refresh <키워드> # 공식 카탈로그 새로 받기
```

싼 곳부터 보고, 찾으면 멈춘다.

| 순서 | 출처 | 비용 |
|---|---|---|
| 1 | 제거 기록 `~/.claude/skill-archive/removed.md` | 로컬 |
| 2 | 공식 스킬 + Anthropic 레포 플러그인 (로컬 카탈로그, 30일마다 자동 갱신) | 로컬 |
| 3 | 그 외 깃헙 (`claude-skills` 토픽 스타 20+, "skill" 검색 스타 50+) | 네트워크 |

- 이름에 키워드가 맞는 공식 후보가 있으면 3번은 건너뛴다. 설명만 겹치는 약한 후보면 3번까지 본다.
- 이미 설치된 스킬은 `[설치됨]`으로 표시해 중복 설치를 막는다.
- 신뢰 순서: 공식 > Anthropic 레포 > 그 제품을 만든 회사 레포(vercel-labs, microsoft 등) > 개인. 스타 100 미만, 6개월 넘게 커밋 없는 레포는 의심한다.
- 제3자 스킬은 추천 전에 SKILL.md와 스크립트를 끝까지 읽고, 외부 전송·자격증명 접근·파괴적 명령이 있으면 뺀다.
- 설치 질문에는 무슨 스킬인지, 출처, 스타 수, 크기, 설치될 위치가 함께 뜬다.

설치는 **반드시 묻는다**. 거부하면 다른 후보로 한 번 더 묻고(2차), 또 거부하면 설치 없이 있는 스킬로 진행한다.

### 맞춤 스킬 제작
있는 스킬이 일반론만 알고 프로젝트 규칙을 모르거나, 같은 프로젝트에서 비슷한 요청이 반복되면 후보로 뜬다. 고르면 `skill-creator`로 `<프로젝트>/.claude/skills/<이름>/`에 가볍게 만들고 바로 그 요청에 적용한다.

### 매핑 표 고치기
`skills/스킬추천/SKILL.md`의 `## 매핑` 표에 `| 작업 | 스킬 |` 줄을 추가·수정한다. 표는 출발점일 뿐이고, 목록에 더 맞는 스킬이 있으면 그쪽을 고른다.

## 스킬제거

```bash
bash ~/.claude/skills/스킬제거/scripts/usage.sh   # 스킬별 호출 수 확인
```

출력: `이름  전체 호출  이 프로젝트 호출  설치 후 일수  설명`. 실제 호출만 센다(Claude가 Skill 도구로 부른 것 + 사용자가 입력한 `/명령`).

- 후보 조건 3개를 **모두** 만족해야 한다: 호출 0회, 현재 프로젝트에 안 맞음(이유 한 줄), 설치 14일 초과.
- 후보마다 이름·쉬운 설명·호출 수·이유를 보여 주고 허락받는다.
- 지우지 않고 `~/.claude/skill-archive/<이름>`으로 옮긴다. "완전히 지워"라고 할 때만 삭제.
- 기록 형식(`removed.md`):
  ```
  - <이름> | <날짜> | 키워드: ... | 설명: ... | 출처: ... | 이유: ... | 보관: ~/.claude/skill-archive/<이름>
  ```
- 복구: `/스킬제거 <이름> 복구` 또는 `/스킬추천`이 탐색 때 제거 기록을 먼저 찾아 복구를 제안한다.
- 제외: `스킬추천`·`스킬제거` 자신, 플러그인 스킬(`figma:` 등. `/plugin`에서 끄라고 안내만), 호출 1회 이상.

## 한계
- 호출 수는 Claude Code가 남긴 대화 기록 범위(보통 약 30일)만 센다.
- 홈 폴더처럼 특정 프로젝트가 아닌 곳에서는 "프로젝트에 안 맞음"을 판단하기 어려워 후보가 거의 안 나온다. 프로젝트 폴더에서 돌릴 것.
- 윈도우 경로(GNU `stat`, `pwd -W`)는 코드로 대응했지만 실제 윈도우 PC에서는 아직 돌려 보지 않았다. 문제가 있으면 이슈로 남길 것.

## 파일 구조
```
skills/
  스킬추천/
    SKILL.md
    scripts/find.sh      # 외부 스킬 탐색
  스킬제거/
    SKILL.md
    scripts/usage.sh     # 호출 수 집계
```
런타임 데이터(`~/.claude/skill-archive/`: 카탈로그 캐시, 제거 기록, 보관 스킬)는 레포에 넣지 않는다.
