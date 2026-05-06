---
name: 작업 로그 정책
description: 응답 종료 시점에 자동 기록되는 work-log 의 위치, 내용, 형식 — Stop hook 구현의 사양서
type: feedback
---

## 의도

이 로그는 **대화 내용(Q/A)이 아니라 그 턴에 수행한 행위/작업**을 기록한다.
무엇을 바꾸었는가, 어떤 결정을 내렸는가를 시간 순으로 추적하기 위한 용도.

## 위치
- 프로젝트 단위로 기록한다: `<project-root>/.claude/work-log/YYYY-MM-DD.md`
- 디렉토리가 없으면 hook 이 생성한다.

## 시점
- **Stop hook** — 응답 한 턴이 끝나는 시점에 append.

## 입력 — 메타블록 (필수)

매 응답의 마지막에 보이지 않는 한 줄 메타블록을 박는다 — Stop hook 이 이걸 우선 사용한다:

```
<!--worklog: action=<수행한 작업 한 줄> | files=<+/M/- path, ... 또는 -> | notes=<선택>-->
```

- `action`: **무엇을 했는가** 한 줄 (사용자 질문 인용 금지, 행위 위주로)
- `files`: `+`  생성, `M`  수정, `-`  삭제. 변경 없으면 `files=-`.
- `notes`: 선택 — 결정·의도·트레이드오프가 있을 때만

## fallback

메타블록 누락 시:
- `files` 는 hook 이 도구 호출(`Write`/`Edit`/`MultiEdit`/`NotebookEdit`) 에서 자동 추출
- `action` 은 `(action 누락)` 표기 — 가능한 한 메타블록 포함

## 변경 없는 응답

조회·질문에 답만 한 턴은 기록 가치가 낮다.
- 메타블록 자체는 박되 `files=-` 로 두면 hook 이 자동으로 스킵 (로그 파일에 안 남음).
- 무리해서 채우지 말 것.

## 형식 (Markdown, append-only)

```md
## HH:MM
- 작업: hooks 3종 작성 — Stop/PreToolUse/UserPromptSubmit
- 변경:
  - +  payload/hooks/stop-worklog.ps1
  - +  payload/hooks/pretooluse-guard.ps1
  - M  payload/CLAUDE.md
- 비고: 메타블록 사양 추가, 위험 명령 12종 가드
```

## 제외 항목
- 도구 호출 raw 로그 (transcript 가 별도로 남음)
- 사용자 발화 인용
- 민감 정보 (API 키, credential, .env 내용) — hook 이 redact 하지만 사전에 넣지 말 것

**Why:** 응답 본문은 짧게 가져가되, "오늘 무엇을 작업했는가" 를 나중에 추적할 수 있어야 함.
**How to apply:** Stop hook 스크립트가 transcript 의 마지막 assistant turn 의 메타블록을 읽어 위 형식으로 압축 기록.
