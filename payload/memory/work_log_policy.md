---
name: 작업 로그 정책
description: 응답 종료 시점에 자동 기록되는 work-log 의 위치, 내용, 추출 규칙 — Stop hook 구현의 사양서
type: feedback
---

## 의도

이 로그는 **대화 내용(Q/A)이 아니라 그 턴에 수행한 행위/작업**을 기록한다.
무엇을 바꾸었는가, 어떤 결정을 내렸는가를 시간 순으로 추적하기 위한 용도.

## 핵심 원칙

**응답 본문에 worklog 메타블록을 박지 말 것.**
Stop hook 이 transcript 에서 전부 자동 추출한다.
메타블록은 가끔 사용자 화면에 노출되어 가독성을 해치므로 박지 않는다.

(과거 호환) `<!--worklog: action=... | files=... | notes=...-->` 형태가 응답에 들어있으면 hook 이 우선 파싱하지만, 새로 박을 필요 없음.

## 시점

**Stop hook** — 응답 한 턴이 끝나는 시점에 transcript 를 읽어 자동 기록.

## 자동 추출 규칙

`hooks/stop-worklog.ps1` 이 다음을 추출한다:

- **files** ← 그 턴의 도구 호출 (`Write`/`Edit`/`MultiEdit`/`NotebookEdit`) 의 `file_path`
  - `Write` → `+` (생성)
  - `Edit`/`MultiEdit`/`NotebookEdit` → `M` (수정)
- **action** ← 어시스턴트 응답의 **첫 의미 문장**
  - 마크다운 헤더(`#`), 코드블록(\`\`\`), 표(`|`), 구분선(`---`), HTML 주석, 인용(`>`) 은 건너뜀
  - 마크다운 강조(`**`, `*`, `` ` ``)·링크는 제거
  - 140자 컷, 초과 시 `…`
- **notes** ← 그 턴 **사용자 메시지의 첫 문장** (요청 의도 힌트)
  - `[harness rules`·`<system-reminder>` 로 시작하면 제외
  - 120자 컷, `요청: <내용>` 형태로 기록

## 기록 안 함 (skip 조건)

- 도구 호출이 한 번도 없고 메타블록도 없는 응답 (조회·답변만)
- 무리해서 채우지 않는다.

## 위치 (글로벌 work-log, anchor 기반 분기)

`hooks/stop-worklog.ps1` 내부의 `$AnchorRoots` 배열에 등록된 디렉토리 기준으로 분기.

- **anchor 안에서 작업한 경우** — `~/.claude/work-log/<anchor 기준 상대경로>/YYYY-MM-DD.md`
  - 예: anchor 가 `D:\Aleatorik` 이고 cwd 가 `D:\Aleatorik\proj-a` 면 → `~/.claude/work-log/proj-a/2026-05-14.md`
  - cwd 가 anchor 루트 자체면 `_root/`
- **anchor 밖에서 작업한 경우** — `~/.claude/work-log/_etc/YYYY-MM-DD_<cwd-tail>.md`
  - `<cwd-tail>` = cwd 의 마지막 2 segments (안전한 문자만), 파일명만 봐도 어디서 한 작업인지 식별 가능
  - 예: `D:\workspace\claude-harness` → `_etc/2026-05-14_workspace-claude-harness.md`

anchor 등록은 hook 스크립트 직접 수정.

## 형식 (Markdown, append-only)

```md
## HH:MM
- 작업: <action 한 줄>
- cwd: <경로>   (anchor 밖에서 작업한 경우만)
- 변경:
  - +  payload/hooks/stop-worklog.ps1
  - M  payload/CLAUDE.md
- 비고: 요청: <사용자 메시지 첫 문장>
```

## 제외 / 금지

- 도구 호출 raw 로그 (transcript 가 별도로 남음)
- 민감 정보 (API 키, credential, .env 내용) — hook 이 알려진 토큰 패턴(`AKIA...`, `ghp_...`, `xox[baprs]-...`, `sk-...`, `AIza...`)을 redact 하지만 사전에 넣지 않는 것이 원칙
- 응답 본문에 메타블록 박지 말 것 (Stop hook 이 자동 추출하므로 불필요, 노출 시 가독성 저해)

**Why:** 응답 본문은 짧게 가져가되, "오늘 무엇을 작업했는가" 를 나중에 추적할 수 있어야 함. 추출은 어시스턴트 책임이 아니라 hook 책임으로 옮겨 응답 화면을 깨끗하게 유지.
**How to apply:** 응답 작성 시 worklog 메타블록 작성하지 않는다. Stop hook 이 응답 + 도구 호출 + 사용자 메시지를 transcript 에서 읽어 위 형식으로 압축 기록.
