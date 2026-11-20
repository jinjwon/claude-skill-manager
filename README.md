# claude-skill-manager

Claude Code에서 **어떤 스킬을 쓸지 고르고, 없으면 좋은 스킬을 찾아 설치하고, 안 쓰는 스킬은 정리하는** 스킬 2개.

| 호출 | 하는 일 |
|---|---|
| `/pick` | 요청에 맞는 스킬 후보를 한 줄씩 보여 주고, 추천대로 / 변경 / 추가 중 하나를 한 번 확인한 뒤 실행. 맞는 게 없으면 공식·인기·트렌드 스킬에서 상위 3개를 골라 설치를 묻거나, 프로젝트 맞춤 스킬을 만든다. |
| `/prune` | 호출 0회 + 현재 프로젝트에 안 맞음 + 설치 14일 초과인 스킬만 골라, 허락받고 보관 폴더로 옮기고 기록을 남긴다. 나중에 바로 복구 가능. |

"스킬추천", "스킬 찾아줘", "안 쓰는 스킬 지워줘"처럼 한국어로 말해도 불린다.

## 빠른 시작

필요한 것: [Claude Code](https://claude.com/claude-code), `gh`(GitHub CLI, `gh auth login` 완료), `jq`. macOS와 윈도우 모두 지원.

| | 도구 설치 |
|---|---|
| macOS | `brew install gh jq` |
| 윈도우 | `winget install GitHub.cli jqlang.jq` (Git Bash는 Claude Code 설치 때 함께 필요) |

### 설치
macOS 터미널 / 윈도우 **Git Bash**에서 같은 명령:
```bash
git clone https://github.com/jinjwon/claude-skill-manager.git ~/claude-skill-manager
bash ~/claude-skill-manager/install.sh
```
윈도우에서 `~`는 `C:\Users\<이름>`이다. 스크립트는 모두 bash라서 Claude Code가 윈도우에서 쓰는 Git Bash로 그대로 돈다.

새 세션에서:
```
/pick 이 피그마 시안 개발 넘기기 전에 봐줘 <링크>
/pick 요즘 뜨는 디자인 스킬 뭐 있어?
/prune
```

### 업데이트
```bash
bash ~/claude-skill-manager/install.sh
```
같은 명령이 최신 코드를 받고(`git pull`) 스킬을 다시 복사한다. 새 Claude Code 세션부터 적용된다.

업데이트해도 **개인 데이터는 그대로** 남는다. 모두 `~/.claude/skill-archive/`에 있고 레포에는 올라가지 않는다.

| 파일 | 내용 |
|---|---|
| `mapping.md` | 내 매핑 표. 처음 설치 때 `skills/pick/mapping.default.md`에서 만들어지고, 이후 `/pick`이 학습한 내용이 쌓인다 |
| `pick-history.tsv` | 추천 기록(반복 업무·쏠림 판단에 씀) |
| `removed.md` + 보관 폴더 | `/prune`으로 치운 스킬과 기록 |
| `catalog.tsv`, `popular.tsv` | 공식·인기 스킬 목록 캐시(30일·7일마다 자동 갱신) |

## /pick

### 왜 있는가
스킬을 쓰는 목적은 **반복 업무를 줄이고 토큰을 아끼는 것**이다. 그런데 스킬을 하나하나 찾기 어렵고, 직접 만들기 어렵고, 요즘 뜨는 스킬이 뭔지 모를 때 쓴다. 그래서 매번 **설치된 스킬 · 요즘 뜨는 새 스킬 · 새로 만들기**를 한 화면에 나란히 보여 준다.

### 흐름
1. 요청을 요약하고, 필요한 **능력** 키워드 2~3개를 뽑는다(예: 키오스크 리디자인 → `design ui ux`).
2. 매번 로컬 인기·공식 카탈로그를 훑는다(`find.sh --local`, 네트워크 0, 1초 미만).
3. 후보를 세 칸으로 채운다.
   - **설치됨** 최대 2개: "요청의 어떤 말 ↔ 스킬 설명의 어떤 말"로 근거를 댄다. "표에 있어서"는 근거가 아니다.
   - **새 스킬** 최대 2개: 설치 안 된 공식 또는 ★1,000+ 스킬. 진짜 SKILL.md 설명을 확인한 뒤 올린다.
   - **만들기** 1개: "스킬 만들어줘"라고 했거나, 프로젝트 맞춤이 필요하거나, 위 두 칸이 약할 때.
   - 후보마다 **하는 일 · 근거 · 토큰(약 N) · 반복 절감**을 채운다. 설치된 스킬의 토큰과 설명은 `find.sh --size`로 한 번에 확인.
4. **반복 감지**: 같은 종류 요청이 3번 이상(기록) 또는 "또/매번"이라고 하면 반복 업무로 보고, 그 절차를 맞춤 스킬(스크립트 포함)로 고정하는 **만들기**를 1순위로 올린다.
5. **쏠림 점검**: 서로 다른 요청에 같은 스킬이 3번 이상 1순위였다면, 근거가 더 분명할 때만 다시 1순위.
6. 고르기: 근거 있는 후보가 1개뿐이면 묻지 않고 한 줄로 알리고 진행한다. 2개 이상이면 한 질문에 `[설치됨]` `[새 스킬]` `[만들기]` 선택지로 나누고, 각 선택지 미리보기에 하는 일·근거·토큰·반복 절감/설치 위치 4줄을 보여 준다. 근거가 가장 강한 하나에만 (Recommended).
7. 기록: `~/.claude/skill-archive/pick-history.tsv`에 날짜·요약·1순위·선택. 1순위가 아닌 걸 고르면 매핑 표에 `(학습 날짜, N회)`로 남긴다. 학습 줄은 가설일 뿐 근거로 쓰지 않는다.

요청에 스킬 이름을 직접 적었거나, 같은 대화에서 같은 종류 작업을 이미 확인했다면 질문을 건너뛴다. "요즘 뜨는 스킬 뭐 있어?"처럼 목록만 원하면 순위표만 보여 준다.

### 스킬이 없을 때: 좋은 스킬 찾기
설치된 스킬로 핵심 작업이 안 될 때만 외부를 찾는다. 검색은 스크립트 한 줄.

```bash
bash ~/.claude/skills/pick/scripts/find.sh <영어 키워드> [키워드2]
bash ~/.claude/skills/pick/scripts/find.sh --top 15      # 지금 인기·트렌드 스킬 레포 순위
bash ~/.claude/skills/pick/scripts/find.sh --all <키워드> # 실시간 깃헙 검색까지
bash ~/.claude/skills/pick/scripts/find.sh --refresh ...  # 카탈로그 강제 갱신
bash ~/.claude/skills/pick/scripts/find.sh --local <키워드>   # 네트워크 없이 캐시만
bash ~/.claude/skills/pick/scripts/find.sh --desc <owner/repo/경로>  # 그 스킬의 진짜 설명
bash ~/.claude/skills/pick/scripts/find.sh --size <스킬이름...>     # 설치된 스킬의 토큰 대략치 + 설명
```

| 순서 | 출처 | 갱신 | 비용 |
|---|---|---|---|
| 1 | 제거 기록 `~/.claude/skill-archive/removed.md` | - | 로컬 |
| 2 | 공식(`anthropics/skills`, 공식 마켓플레이스) + Anthropic 레포 플러그인 | 30일 | 로컬 |
| 3 | 인기·트렌드: 스킬 토픽(`claude-skills`, `agent-skills` 등) 스타 300+ 레포, 최근 90일에 생겨 빠르게 뜬 레포. 레포 안 스킬까지 펼쳐 저장(약 1,500개) | 7일 | 로컬 |
| 4 | 깃헙 실시간 검색 | 매번 | 네트워크 |

- 2·3번을 함께 점수 매긴다(이름에 키워드 +3, 설명 +1. 단어 첫머리만 인정해 `ui`가 `build`에 걸리지 않음, 같은 점수면 공식 → 스타 순). 이름이 맞는 후보가 있으면 4번은 건너뛴다.
- 6개월 넘게 커밋 없는 레포는 카탈로그에서 빠진다. 이미 설치된 것과 이름이 같으면 `[같은 이름 설치됨]`으로 표시한다(이름만 같은 다른 스킬일 수 있음).
- 신뢰도·**프로젝트 적합도**·토큰·의존성으로 **상위 3개**를 추려 한 질문에 나열한다. 고르면 설치, "설치 안 함"이면 다른 후보로 한 번 더(2차), 또 거부하면 설치 없이 있는 스킬로 진행.
- 제3자 스킬은 설치 직전에 SKILL.md와 스크립트를 끝까지 읽고, 외부 전송·자격증명 접근·파괴적 명령이 있으면 뺀다.

### 맞춤 스킬 제작
있는 스킬이 일반론만 알고 프로젝트 규칙을 모르거나, 같은 프로젝트에서 비슷한 요청이 반복되면 후보로 뜬다. 고르면:
1. 카탈로그에서 비슷한 인기 스킬 1~2개를 읽고 구조·좋은 규칙을 참고한다(출처를 `참고:`로 남김).
2. `skill-creator`로 `<프로젝트>/.claude/skills/<이름>/`에 가볍게 만들고 바로 그 요청에 적용한다.
3. 토큰을 아끼게: 매번 같은 단계는 `scripts/`로 빼고 SKILL.md에는 실행 한 줄만. SKILL.md는 150줄 이하.

### 매핑 표 고치기
`~/.claude/skill-archive/mapping.md`에 `| 작업 | 스킬 |` 줄을 추가·수정한다. 표는 출발점일 뿐이고, 목록에 더 맞는 스킬이 있으면 그쪽을 고른다. 모두에게 기본으로 줄 줄은 레포의 `skills/pick/mapping.default.md`에 넣는다.

## /prune

```bash
bash ~/.claude/skills/prune/scripts/usage.sh   # 스킬별 호출 수 확인
```

출력: `이름  전체 호출  이 프로젝트 호출  설치 후 일수  설명`. 실제 호출만 센다(Claude가 Skill 도구로 부른 것 + 사용자가 입력한 `/명령`).

- 후보 조건 3개를 **모두** 만족해야 한다: 호출 0회, 현재 프로젝트에 안 맞음(이유 한 줄), 설치 14일 초과.
- 후보마다 이름·쉬운 설명·호출 수·이유를 보여 주고 허락받는다.
- 지우지 않고 `~/.claude/skill-archive/<이름>`으로 옮긴다. "완전히 지워"라고 할 때만 삭제.
- 기록 형식(`removed.md`):
  ```
  - <이름> | <날짜> | 키워드: ... | 설명: ... | 출처: ... | 이유: ... | 보관: ~/.claude/skill-archive/<이름>
  ```
- 복구: `/prune <이름> 복구`. `/pick`도 탐색할 때 제거 기록을 먼저 찾아 복구를 제안한다.
- 제외: `pick`·`prune` 자신, 플러그인 스킬(`figma:` 등. `/plugin`에서 끄라고 안내만), 호출 1회 이상.

## 자동 동기화 (선택, 이 레포를 고쳐 쓰는 사람용)
`~/.claude/skills`에서 스킬을 고치면 자기 레포에 자동으로 커밋·푸시되게 할 수 있다. `sync.sh`가 두 스킬을 레포로 복사하고, 바뀐 게 있을 때만 커밋하고 백그라운드로 푸시한다. 포크한 레포에서 쓸 것.

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
- PostToolUse: Claude가 스킬 파일을 고치면 바로 동기화.
- SessionStart: 직접 편집기로 고친 것도 다음 세션 시작 때 올라감.
- 푸시 실패 기록: `~/claude-skill-manager/.sync.log`.

## 한계
- 호출 수는 Claude Code가 남긴 대화 기록 범위(보통 약 30일)만 센다.
- 홈 폴더처럼 특정 프로젝트가 아닌 곳에서는 "프로젝트에 안 맞음"을 판단하기 어려워 `/prune` 후보가 거의 안 나온다. 프로젝트 폴더에서 돌릴 것.
- 인기·트렌드 카탈로그는 깃헙 스타 기준이다. 깃헙에는 공식 "트렌딩" API가 없어서, 최근 생긴 레포 중 스타가 빨리 붙은 것을 트렌드로 본다. 첫 갱신은 1분 안팎 걸린다.
- 윈도우 경로(GNU `stat`·`date`, `pwd -W`)는 코드로 대응했지만 실제 윈도우 PC 검증은 아직이다. 문제가 있으면 이슈로 남겨 주세요.

## 파일 구조
```
skills/
  pick/
    SKILL.md
    scripts/find.sh      # 스킬 탐색 + 인기·트렌드 카탈로그
  prune/
    SKILL.md
    scripts/usage.sh     # 호출 수 집계
    mapping.default.md   # 기본 매핑 표(처음 설치 때 개인 표로 복사)
install.sh               # 설치·업데이트
sync.sh                  # 자동 동기화(선택, 레포 관리자용)
```
개인 데이터(`~/.claude/skill-archive/`)는 레포에 넣지 않는다.
