# pick 기본 매핑

처음 실행할 때 `~/.claude/skill-archive/mapping.md`로 복사되어 개인 표가 된다. 레포 업데이트는 개인 표를 덮어쓰지 않는다.

| 작업 | 스킬 |
|---|---|
| 피그마 화면·와이어프레임·디자인 제작/수정 | figma:figma-use + figma:figma-generate-design |
| 피그마 컴포넌트·토큰·디자인시스템 | figma:figma-use + figma:figma-generate-library |
| FigJam·플로우차트·다이어그램 | figma:figma-use-figjam / figma:figma-generate-diagram |
| 기획→화면 목록·IA·플로우 정리 | wireframe-plan |
| 디자인 리뷰·피드백 | design-review |
| 구현물 vs 시안 QA | design-qa |
| 기획서·PRD·기능명세 | product-management:write-spec |
| 아이디어 발산 | product-management:product-brainstorming |
| 일정·스프린트 | product-management:sprint-planning |
| 노션 문서 작성/수정 | (노션 MCP 직접) + docs 필요 시 anthropic-skills:docs |
| PDF 읽기/편집 | anthropic-skills:pdf (보기·주석은 pdf-viewer:view-pdf) |
| 엑셀/워드/PPT | anthropic-skills:xlsx / docx / pptx |
| 이력서·포트폴리오 | resume-portfolio |
| 코드 작성·수정 | ponytail (+ 버그면 superpowers:systematic-debugging) |
| 코드 리뷰 | code-review |
| 리서치 | anthropic-skills:deep-research |
| 차트·대시보드 | dataviz |
| 코드베이스/문서 지식그래프 | graphify |
| 새 스킬 만들기 | anthropic-skills:skill-creator |
| 안 쓰는 스킬 정리·제거·복구 | prune |
