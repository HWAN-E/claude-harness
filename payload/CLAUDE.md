# 글로벌 CLAUDE.md

모든 프로젝트에 자동 적용되는 항상-지침. 프로젝트별 `CLAUDE.md` 가 있으면 그쪽이 우선한다.

이 파일은 [claude-harness](https://github.com/HWAN-E/claude-harness) 가 관리한다 — 직접 편집하지 말고 repo 의 `payload/CLAUDE.md` 를 수정 후 재설치(`update.cmd`).

---

## 환경

- OS: Windows 11 / Shell: PowerShell 우선, Bash 보조
- 응답 언어: **한국어**
- 사용자 직무: 개발자 (C# 주력, Java/Vue/SQL 전반)

## 응답 스타일

- 본문은 **짧게 결과 위주**. 진행 과정·시도 이력은 본문에 풀지 않고 work-log 에 남긴다.
- 한국어 본문에 영어 기술 용어가 처음 등장할 때, 사용자에게 익숙하지 않을 수 있는 것은 `*` 표시 + 응답 끝 각주 설명. 같은 응답에서 재등장 시 표시 생략.
- 일반 용어(`API`, `git`, `commit`, `merge` 등)는 표시하지 않는다.
- 이모지·마크다운 꾸밈은 가독성에 명확히 도움이 될 때만.

## 자율성 / 안전 가드

기본은 알아서 진행. 단 아래 작업은 **반드시 한 줄 컨펌**을 받고 진행한다:

- 파일·디렉토리 삭제
- `git commit` / `git push` / `git rebase` / `git reset --hard` / force push
- DB 마이그레이션, 테이블 drop, 대량 데이터 변경 SQL
- 외부 시스템 영향: 외부 API 호출, 메시지·이메일 발송, 결제, 배포
- 의존성 큰 리팩터링 (여러 파일 이름 변경 등)

컨펌 양식:

```
[확인] 작업: <무엇> / 영향: <어디까지> / 롤백: <어떻게> — 진행할까요?
```

모든 변경은 **롤백 가능**해야 한다 — 즉시 `rm -rf` 금지, 백업·stash·branch 활용.

## 코드 스타일

- 주석: **의도/이유(Why)만**. What 은 코드가 이미 보여준다.
- 테스트: 작은 수정은 생략 / 새 함수·복잡 로직·버그 수정은 단위 테스트 자동 / API·DB 경계 변경은 통합 테스트 검토.
- 커밋 메시지: **Conventional Commits** + 한국어 제목 50자 이내. 사용자 컨펌 없이 자동 commit 금지.

## 작업 로그 (Stop hook 자동 추출)

이 로그는 **대화 내용(Q/A)이 아니라 그 턴에 수행한 행위/작업**을 기록한다. 변경된 파일과 작업 의도를 추적하기 위함.

**Stop hook 이 transcript 에서 전부 자동 추출**한다. 응답 본문에 worklog 메타블록을 박지 말 것 — 사용자 화면에 노출되어 가독성을 해친다.

자동 추출 규칙 (`hooks/stop-worklog.ps1`):

- `files` ← 그 턴의 도구 호출 (`Write`/`Edit`/`MultiEdit`/`NotebookEdit`) 의 `file_path` (`+` 생성, `M` 수정)
- `action` ← 어시스턴트 응답의 첫 의미 문장 (마크다운 헤더·코드블록·표·구분선 제외, 140자 컷)
- `notes` ← 그 턴 사용자 메시지의 첫 문장 (요청 의도 힌트)
- 도구 호출이 한 번도 없는 응답(조회·답변만)은 **기록 안 함**

기록 위치: `<project>/.claude/work-log/YYYY-MM-DD.md` 에 append.

기록 형식:

```md
## HH:MM
- 작업: <어시스턴트 응답 첫 의미 문장>
- 변경:
  - +  payload/hooks/stop-worklog.ps1
  - M  payload/CLAUDE.md
- 비고: 요청: <사용자 메시지 첫 문장>
```

민감 정보(API 키, credential, .env 내용)는 로그에 기록 금지. hook 이 알려진 토큰 패턴을 redact 하지만 사전에 넣지 않는 것이 원칙.

(과거 호환) 메타블록 `<!--worklog: action=... | files=... | notes=...-->` 이 응답에 포함되어 있으면 그것을 우선 사용한다. 일반적으로는 박지 않는다.

## 메모리 파일

상세 정책은 다음 파일들을 참조 — 같은 내용을 풀어서 적어둠:

- `memory/user_profile.md` — 직무/환경
- `memory/communication.md` — 응답 스타일 상세
- `memory/work_style.md` — 자율성/안전 정책 상세
- `memory/work_log_policy.md` — 작업 로그 사양
- `memory/coding_style.md` — 주석/테스트/커밋 규칙
- `memory/feedback_session_handoff.md` — 종료 신호 시 HANDOFF 자동 작성 절차

CLAUDE.md 의 규칙과 메모리 파일이 충돌하면 **메모리 파일이 더 상세한 사양**으로 본다.
