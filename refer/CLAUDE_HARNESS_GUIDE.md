# Claude 하네스(Harness) 설계 가이드 — 극한 효율 버전

> **목적**: Claude를 "반응하는 챗봇"이 아니라 "구조화된 실행기"로 사용하기 위한 설정 전체 지도.
> **전제**: 효율의 본질은 "Claude가 매 세션 처음부터 고민하지 않도록, 구조·규칙·도구·게이트를 하네스에 박아두는 것"이다.

---

## 0. 하네스(Harness)란 무엇인가

하네스는 모델 주변을 감싸는 **모든 비(非)모델 구성요소의 총합**이다:

- **메모리**: CLAUDE.md, 인용 문서
- **도구**: 내장 도구, MCP 서버
- **제어 흐름**: Agent 위임, Hook 차단, 권한 경계
- **상태**: TODO, 세션 간 전달되는 파일
- **피드백**: Eval, lessons-learned

모델 성능은 고정값이지만 **하네스 품질은 사용자가 만드는 변수**다. 동일 모델에서 나쁜 하네스와 좋은 하네스의 출력 차이는 체감 2~3배.

---

## 1. 설계 철학 5원칙

### 원칙 1 — 컨텍스트는 예산이다

Claude의 컨텍스트 창은 희소 자원이다. 모든 토큰이 비용이고, **노이즈 토큰은 품질을 깎는다**. 따라서:

- CLAUDE.md에 "있으면 좋은 것"을 넣지 말고, **"없으면 매번 틀리는 것"만** 넣는다.
- 긴 참조 문서는 CLAUDE.md 본문이 아니라 별도 파일로 두고 **링크만 걸어둔다** (모델이 필요할 때만 읽도록).
- Skill은 lazy load된다 — 표시만 되고 본문은 호출 시 확장. **깊은 전문 지식은 skill로 옮겨라**.

### 원칙 2 — 메인 세션은 오케스트레이션, 실행은 Sub Agent

탐색·리서치·대량 파일 읽기는 **무조건 Sub Agent에 위임**한다. 메인 세션은 의사결정·통합·사용자 커뮤니케이션만 담당.

이유: Sub Agent가 1만 토큰을 읽어도 메인에 돌아오는 것은 200~500 토큰의 요약뿐. 메인 컨텍스트가 오염되지 않는다.

### 원칙 3 — 게이트는 프롬프트로 쓰고 Hook으로 강제한다

"여기서 멈춰라"는 프롬프트만으로는 확률적으로 실패한다. **진짜 중요한 게이트는 Hook으로 물리적 차단**.

- 프롬프트 게이트: 계획 승인, 범위 확인 (부드럽게)
- Hook 게이트: main 직접 커밋, 대량 파일 삭제, production 관련 작업 (단단하게)

### 원칙 4 — 모든 반복은 추출하라

같은 지시를 3번째 하고 있다면 **즉시 하네스에 박아라**. 선택지는 셋:

1. CLAUDE.md에 한 줄 규칙 (항상 적용)
2. Skill로 추출 (특정 트리거에서만)
3. Command로 추출 (사용자가 명시적으로 호출)

판단: "항상 지켜야 하나?" → CLAUDE.md / "특정 작업에서만?" → Skill / "내가 수동 호출할 것?" → Command

### 원칙 5 — 출력은 관측 가능해야 한다

하네스의 품질은 **측정 가능할 때만 개선된다**. 스킬에는 Eval을, 에이전트에는 기대 출력 형식을, 커맨드에는 종료 조건을 정의한다. 측정이 없는 하네스는 관성으로 굳어 나빠진다.

---

## 2. 계층 구조 — 글로벌 vs 프로젝트

### 글로벌 `~/.claude/` (모든 세션에 적용)

```
~/.claude/
├── CLAUDE.md                 # 개인 선호·스타일·금지사항 (짧고 단호하게)
├── settings.json             # 기본 permissions, hooks
├── agents/                   # 도메인 중립 에이전트
│   ├── code-reviewer.md
│   ├── researcher.md
│   └── test-writer.md
├── commands/                 # 어디서나 쓰는 슬래시 명령
│   ├── commit.md
│   ├── review.md
│   └── scaffold.md
├── skills/                   # 범용 스킬
│   └── ... (기본 제공: docx, pdf, pptx, xlsx, ...)
├── output-styles/            # 응답 톤 프리셋
│   ├── concise.md
│   └── deep.md
└── hooks/                    # 훅 스크립트
    ├── pre-commit-guard.sh
    └── format-on-save.sh
```

### 프로젝트 `./.claude/` (특정 리포에만 적용)

```
./
├── CLAUDE.md                 # 프로젝트 규칙 (아키텍처, 도메인 용어, 기술 스택)
└── .claude/
    ├── settings.local.json   # 해당 프로젝트 전용 권한 (gitignore)
    ├── settings.json         # 팀 공용 권한/훅 (커밋됨)
    ├── agents/               # 프로젝트 특화 에이전트 (be-agent, fe-agent 등)
    ├── commands/             # 프로젝트 운영 명령 (release, db-check 등)
    └── skills/               # 프로젝트 워크플로우 (dev, blueprint-scaffold 등)
```

### 우선순위

동일 이름이 겹치면 **프로젝트 > 글로벌**. 이게 옳은 순서다. 개인 기본값 위에 프로젝트가 덮어쓴다.

### 역할 경계의 단단한 규칙

| 종류 | 글로벌에 둠 | 프로젝트에 둠 |
|------|-----------|-------------|
| 스타일·말투 | ○ | 드물게 |
| Git 안전 규칙 | ○ | ○ (main 보호 등) |
| 언어 특화 린트 | ○ (공용) | ○ (프로젝트 린터 명령) |
| 도메인 용어 | × | ○ |
| 기술 스택 결정 | × | ○ |
| 배포 절차 | × | ○ |
| 리뷰·리서치 에이전트 | ○ | × |
| 프로젝트 개발 에이전트 | × | ○ |

---

## 3. 컨텍스트 예산 관리 (가장 저평가된 레버)

### 3-1. CLAUDE.md 다이어트

나쁜 CLAUDE.md는 200줄짜리 자기계발서다. 좋은 CLAUDE.md는 **헌법처럼 짧고 단호하다**.

**넣을 것**:
- 금지 사항 (절대 하지 말 것)
- 의사결정 표 (조건 → 액션)
- 참조 문서 링크 (본문 아님)

**빼야 할 것**:
- 설명·교양·배경지식
- "상황에 따라 판단하라"류의 모호한 지침
- 한 번도 지켜지지 않는 선언적 비전

### 3-2. 파일 임포트 활용

Claude Code는 CLAUDE.md에서 `@path/to/file.md` 구문으로 다른 파일을 끌어올 수 있다. 활용법:

```markdown
# CLAUDE.md (항상 로드됨 — 핵심 규칙만)

## 참조
- 코딩 스타일: @.claude/style.md
- Git 규칙: @.claude/git-rules.md
- 트러블슈팅: @docs/troubleshooting/INDEX.md
```

링크만 걸어두고 본문은 분리 → 매 세션 로드량 감소. 모델이 필요하면 읽는다.

### 3-3. Skill을 "대형 참조 문서의 수납장"으로 활용

스킬 본문은 **트리거 시에만** 확장된다. 예를 들어 "Tailwind v4 마이그레이션 가이드" 같은 2천 줄짜리 문서를 CLAUDE.md에 넣으면 재앙이지만, Skill로 만들어두면 관련 작업에서만 로드된다.

---

## 4. CLAUDE.md 설계 — 헌법 수준의 압축

### 4-1. 최소 골격 (글로벌)

```markdown
# 개인 운영 규칙

## 응답 스타일
- 한국어로 응답. 격식체 최소화, 간결체 선호.
- 불필요한 서두("좋은 질문입니다") 금지.
- 불릿·헤더는 정보가 다층일 때만. 평문이 기본.
- emoji는 사용자가 쓸 때만.

## 코드 작업
- 기존 파일 편집 > 신규 파일 생성.
- 문서(*.md, README) 자동 생성 금지. 명시적 요청 시에만.
- 모든 커밋은 새 커밋으로. amend 금지(사용자 지시 제외).
- 커밋 메시지: Conventional Commits. 본문은 "왜"에 집중.

## Git 안전
- `--force` 계열, `reset --hard`, `clean -fd`: 사용자 명시 요청 시에만.
- main/master 직접 푸시 금지.
- 훅 건너뛰기(`--no-verify`) 금지.

## 도구 사용
- 파일 탐색: Grep/Glob 우선. `bash find/grep` 금지.
- 파일 읽기: Read. `cat/head/tail` 금지.
- 외부 라이브러리 호출 전 공식 문서 확인.

## 작업 흐름
- 3단계 이상 작업은 먼저 계획을 한 문단으로 제시.
- 사용자 확인 없이 파괴적 작업 수행 금지.
- 작업 완료 후 결과·한계·후속 질문 1줄씩.
```

**50줄 이내로 유지**. 이걸 넘으면 덜 중요한 항목이 섞이기 시작한 것이다.

### 4-2. 프로젝트 CLAUDE.md 골격

```markdown
# {프로젝트명}

## 1줄 요약
{무엇을 하는 프로젝트인가}

## 참조 문서 (링크만)
| 문서 | 위치 | 용도 |
|------|------|------|
| 아키텍처 | docs/ARCHITECTURE.md | 전체 구조 |
| API | docs/API.md | 엔드포인트 명세 |
| 도메인 용어 | docs/GLOSSARY.md | 비즈니스 용어 |

## 기술 스택 결정표
| 상황 | 스택 |
|------|------|
| 신규 화면 | {stack} |
| 기존 수정 | 유지 |
| 배치 작업 | {stack} |

## 절대 규칙 (위반 시 작업 중단)
1. ...
2. ...
3. ...

## 자주 쓰는 명령
- 개발: `...`
- 테스트: `...`
- 빌드: `...`

## 트러블슈팅 인덱스
- 증상 A → docs/troubleshooting/A.md
- 증상 B → docs/troubleshooting/B.md
```

vmsworks의 CLAUDE.md가 참고할 만하지만 **절반 분량이 이상적**이다.

---

## 5. Agent 설계 — Sub Agent 패턴

### 5-1. 언제 Agent를 만드는가

판단 기준 한 줄: **"이 작업이 메인 컨텍스트를 오염시킬 만큼 탐색이 크거나, 독립적 2차 의견이 필요한가?"**

- ✅ 맞는 경우: 코드베이스 전체 탐색, 10개 이상 파일 리딩, 독립 리뷰, 대량 웹 리서치
- ❌ 아닌 경우: 1~2 파일 수정, 단일 함수 작성, 간단한 질문 응답

### 5-2. Agent 파일 구조

```markdown
---
name: code-reviewer
description: 완성된 코드에 대한 독립적 2차 리뷰. 수정 권한 없음. 리뷰 리포트만 반환.
model: sonnet
tools: Read, Grep, Glob, Bash(git diff:*, git log:*)
---

# Code Reviewer Agent

## 역할
메인 세션에서 이미 작성한 코드를 **제3자 관점**에서 검증한다. 코드 수정·실행 권한이 없으며, 리뷰 리포트만 작성한다.

## 입력
- 리뷰 대상 파일 경로 또는 git diff 범위
- 관심 영역 (보안/성능/가독성/API 설계 중 택)

## 체크리스트
1. **정합성**: 변경이 주변 코드 규약과 일치하는가
2. **보안**: 입력 검증, 권한 체크, 민감 정보 노출
3. **성능**: N+1, 불필요한 루프, 메모이제이션 누락
4. **테스트 가능성**: 순수 함수 분리, 부작용 경계
5. **에러 처리**: 예외 경로, 롤백, 로깅

## 출력 형식 (반드시 이 형식)
### 심각도 요약
- Critical: {개수}
- Major: {개수}
- Minor: {개수}

### 상세 (Critical부터)
- **[Critical] {파일:줄번호}** {문제}
  - 근거: ...
  - 제안: ...

## 금지
- 코드 수정 (Edit/Write 호출 금지)
- 일반론·교과서 조언 (반드시 대상 코드 인용)
- "LGTM" — 문제 없으면 "문제 없음" + 근거 3줄
```

**핵심 규약**:
- `model` 지정으로 비용 통제 (리뷰는 sonnet, 창작은 opus)
- `tools` 제한으로 수정 방지 — 이게 Agent 안전성의 90%
- 출력 형식 고정 → 메인에서 파싱·재사용 가능

### 5-3. 위임 프롬프트 쓰는 법

Agent 호출 시 지시문은 **자기완결적**이어야 한다. Agent는 지금까지 대화를 모른다.

```
(나쁨) "방금 내가 쓴 파일 리뷰해줘"

(좋음) "app/services/chat_service.py의 _send_to_openclaw 함수(line 340-420)를 보안 관점에서 리뷰. 이 함수는 외부 LLM Gateway에 유저 입력을 전송함. 관심사: (1) API 키 노출, (2) 프롬프트 인젝션 방어, (3) 에러 메시지에 내부 경로 유출. 출력은 agent 정의의 출력 형식에 따라."
```

### 5-4. 추천 개인용 Agent 5종

| 이름 | 역할 | 도구 제한 |
|------|------|---------|
| `code-reviewer` | 독립 리뷰 | 읽기만 |
| `researcher` | 웹·문서 리서치 | WebFetch/WebSearch + Read |
| `test-writer` | 테스트 추가 | Read/Edit/Write/Bash(test 실행) |
| `refactor-planner` | 리팩터링 계획 (실행 없음) | Read/Grep만 |
| `explainer` | 코드베이스 설명 | Read/Grep/Glob만 |

---

## 6. Command 설계

### 6-1. Agent vs Command 구분

- **Agent**: 메인이 필요에 따라 "위임"하는 서브 프로세스
- **Command**: 사용자가 명시적으로 호출하는 슬래시 명령

같은 기능이어도 호출 방식이 다르다. 리뷰는 메인이 자동으로 agent 호출할 수도 있고, `/review`로 사용자가 강제할 수도 있다.

### 6-2. Command 파일 구조

```markdown
---
name: commit
description: 스테이징된 변경을 분석해 커밋 메시지 생성 후 커밋 제안
---

# /commit

## 실행 순서
1. `git status --short` + `git diff --staged` 실행
2. 변경 성격 판단 (feat/fix/refactor/docs/style/test/chore)
3. 영향 범위 식별 (scope)
4. 제목 50자 이내, 본문 72자 wrap, "왜"에 집중
5. 사용자에게 제안, 승인 시 커밋

## 금지
- `git add .` 자동 실행 (이미 스테이징된 것만 대상)
- amend 제안 (새 커밋만)
- Co-Authored-By 자동 삽입 (명시 요청 시에만)
```

### 6-3. 추천 개인용 Command 5종

| 명령 | 기능 |
|------|------|
| `/commit` | 스마트 커밋 메시지 |
| `/review` | 현 브랜치 diff 자체 리뷰 (code-reviewer agent 호출) |
| `/plan` | 작업 시작 전 계획 수립 (실행 없음) |
| `/status` | 현재 작업 상태·남은 TODO 요약 |
| `/wrap` | 세션 마무리: 요약·다음 단계·학습 기록 |

---

## 7. Skill 설계

### 7-1. Skill의 본질

Skill = **트리거되면 확장되는 지식 패키지**. 평상시에는 이름+설명만 노출되고 호출 시에만 본문이 읽힌다. 따라서:

- 본문이 길어도 비용 없음 (호출 안 하면)
- description 품질이 **트리거 정확도**를 결정
- 반복 참조하는 대량 규칙에 이상적

### 7-2. Skill 파일 구조

```markdown
---
name: api-design
description: REST API 엔드포인트 신규 설계/리뷰 시 사용. URI 규칙, 상태 코드, 에러 응답, 페이지네이션, 버전 관리 표준 제공. `POST /api/`, `GET /api/`, `DELETE /api/` 같은 신규 경로 등장 시 트리거.
---

# API 설계 표준

## URI 규칙
- 리소스: 복수 명사 (`/users`, `/orders`)
- 동사 금지. 상태 변경은 하위 리소스로 (`/orders/123/cancel` 대신 `POST /orders/123/cancellation`)
- 버전: `/v1/...` 경로 prefix

## 상태 코드
... (표)

## 에러 응답 표준
```json
{
  "error": {
    "code": "RESOURCE_NOT_FOUND",
    "message": "사용자를 찾을 수 없습니다",
    "details": {}
  }
}
```

## 체크리스트
- [ ] 멱등성 (GET/PUT/DELETE)
- [ ] 페이지네이션 (기본 20, max 100)
- [ ] 필드 필터 (`?fields=id,name`)
- [ ] Rate limit 헤더
```

### 7-3. description 작성 규칙 (가장 중요)

description은 **모델이 스킬을 언제 불러야 할지 판단하는 유일한 단서**. 따라서:

1. **구체적인 트리거 예시 포함** ("`POST /api/` 같은 신규 경로 등장 시")
2. **"사용하지 말 것" 조건도 명시** 가능
3. **키워드 많이 포함** — API, REST, 엔드포인트, URI, 상태코드 등
4. **한 줄 요약 + 트리거 예시**

vmsworks의 스킬 description이 이 점에서 우수하다 (예: `pptx` 스킬의 "`.pptx`가 언급되면 무조건 트리거").

### 7-4. Skill에 Eval 붙이기

```
skills/api-design/
├── skill.md
└── evals/
    └── evals.json
```

`evals.json` 예시:

```json
{
  "cases": [
    {
      "input": "POST /api/v1/users 엔드포인트 만들어줘",
      "should_trigger": true,
      "expected_checks": ["URI 복수 명사", "상태 코드 201", "에러 응답 표준"]
    },
    {
      "input": "파이썬 리스트 정렬 방법",
      "should_trigger": false
    }
  ]
}
```

수동이어도 좋으니 스킬 수정할 때마다 돌려보는 습관이 회귀를 막는다.

---

## 8. Hooks — 물리적 강제의 레이어

### 8-1. Hook 설치 방식

`~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "command": "~/.claude/hooks/guard-destructive.sh"
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "command": "~/.claude/hooks/format-on-save.sh"
      }
    ],
    "UserPromptSubmit": [
      {
        "command": "~/.claude/hooks/warn-production.sh"
      }
    ]
  }
}
```

### 8-2. 필수 Hook 3종

**(1) 파괴적 명령 차단** (`guard-destructive.sh`):

```bash
#!/usr/bin/env bash
# stdin으로 도구 호출 JSON을 받음
input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // ""')

# 차단 패턴
if echo "$cmd" | grep -qE 'rm -rf (/|~|\$HOME)|git push.*--force.*main|git reset --hard'; then
  echo '{"permissionDecision": "deny", "reason": "파괴적 명령 차단"}' 
  exit 0
fi
echo '{"permissionDecision": "allow"}'
```

**(2) 저장 시 자동 포맷** (`format-on-save.sh`):

파일 확장자별로 prettier/ruff/gofmt 자동 실행. Claude가 포맷 규칙을 매번 지키는 데 토큰 쓰지 않도록.

**(3) 세션 종료 시 요약 유도** (`Stop` hook):

미완료 TODO가 있으면 알림. 잊고 세션 끝내는 것 방지.

### 8-3. Hook 설계 철학

- **차단보다 수정 우선**: 막기보다 고치는 훅이 생산적 (예: 포맷터)
- **에러 메시지에 해결책 포함**: "main에 커밋 금지 — `git checkout -b feature/XXX` 후 재시도"
- **과다 사용 금지**: 훅이 많으면 디버깅 지옥. 5개 이하로 유지

---

## 9. Permissions 전략

### 9-1. 3계층 설정

```
~/.claude/settings.json           # 글로벌 기본 (보수적)
  └── project/.claude/settings.json       # 프로젝트 공용 (중간)
      └── project/.claude/settings.local.json  # 로컬 사용자 (관대, gitignore)
```

### 9-2. Allow/Deny 설계

**글로벌 allow (최소한)**:
```json
{
  "permissions": {
    "allow": [
      "Read", "Grep", "Glob",
      "Bash(ls:*)", "Bash(pwd)", "Bash(git status:*)", "Bash(git diff:*)", "Bash(git log:*)"
    ],
    "deny": [
      "Bash(rm -rf ~*)",
      "Bash(rm -rf /*)",
      "Bash(git push --force:*)",
      "Bash(git reset --hard:*)",
      "Bash(sudo:*)",
      "Bash(curl * | sh*)",
      "Bash(curl * | bash*)"
    ],
    "ask": [
      "Write", "Edit",
      "Bash(git commit:*)",
      "Bash(git push:*)"
    ]
  }
}
```

### 9-3. vmsworks가 놓친 것

- `deny` 비어 있음 → 치명적 명령도 모두 ask/allow로 넘어갈 수 있음
- `allow`에 파괴적 와일드카드(`Bash(git push:*)`) — 최소한 첫 푸시는 ask로
- 특정 커밋 메시지 전체가 allow에 통째로 박힘 → 설정 오염. ask로 처리해야 함

**규칙**: allow는 손으로 한 땀씩, deny는 와일드카드로 과감하게, ask는 위험-편익 경계에.

---

## 10. 하네스 조립 — 모든 조각을 엮는 패턴

### 10-1. 전형적 작업 흐름

```
사용자 입력
    │
    ▼
[Hook: UserPromptSubmit]  ← "production", "배포" 등 감지 시 경고 삽입
    │
    ▼
[메인 세션]
    ├─ CLAUDE.md 로드 (글로벌 + 프로젝트)
    ├─ 관련 Skill 자동 매칭 (description으로 판단)
    └─ 계획 수립
    │
    ▼
탐색 필요? ──── Yes ────► [Sub Agent: explainer / researcher]
    │                              │
    No                             ▼
    │                         요약 반환 (500 토큰)
    ▼◄────────────────────────────┘
    │
작업 실행
    ├─ Edit/Write  ──► [Hook: PostToolUse] 포맷터 실행
    ├─ Bash        ──► [Hook: PreToolUse] 파괴 명령 차단
    │
    ▼
완료 전 리뷰 필요? ──── Yes ────► [Sub Agent: code-reviewer]
    │                                    │
    No                                   ▼
    │                              리뷰 리포트
    ▼◄───────────────────────────────────┘
    │
커밋 ──► /commit command (사용자 승인)
    │
    ▼
[Hook: Stop] 세션 종료 시 미완 TODO 확인
```

### 10-2. 세션 경제학

**세션당 토큰을 낭비하는 TOP 5 원인과 해결**:

| 낭비 원인 | 해결 |
|---------|------|
| 1. 매번 같은 규칙 설명 | CLAUDE.md로 이동 |
| 2. 대량 파일 탐색을 메인이 직접 | Agent 위임 |
| 3. 쓸데없이 긴 설명·서두 | 스타일 규칙에 "서두 금지" |
| 4. 매 작업마다 환경 파악(`ls`, `cat`) | CLAUDE.md에 "자주 쓰는 경로" 박아두기 |
| 5. 같은 파일 반복 읽기 | 한 번 읽고 요약을 TODO/메모에 유지 |

### 10-3. 컴포지션 패턴 3종

**(A) Fan-out / Fan-in** (vmsworks의 feature-dev 패턴):
- 메인이 독립 작업 N개를 N개 agent에 병렬 위임
- 결과 취합 후 통합
- 사례: BE + FE 동시 개발, 여러 파일 동시 리뷰

**(B) Pipeline** (단계별 위임):
- researcher → planner → executor → reviewer 순차
- 각 단계 결과를 다음에 입력으로
- 사례: 새 라이브러리 도입 (조사 → 설계 → 구현 → 검증)

**(C) Two-model Dialogue** (의견 대립):
- executor agent와 critic agent를 교차 호출
- 수렴할 때까지 반복
- 사례: 보안 설계 리뷰, 아키텍처 의사결정

대부분 (A)로 충분하다. (B)는 큰 기능, (C)는 고위험 결정에서.

---

## 11. 안티패턴 — 피해야 할 설계

### 11-1. CLAUDE.md 비대증

200줄을 넘어가면 모델이 "어디에 뭐가 있는지" 자체를 놓친다. vmsworks도 이 경계에 가까움. **150줄 초과 시 분할**.

### 11-2. Skill 과다 생성

스킬은 description 기반으로 매칭되는데, 유사한 스킬이 여러 개면 오매칭이 늘어난다. **스킬이 15개 넘으면 통합 검토**.

### 11-3. Hook 체인

"훅 A가 훅 B를 트리거"하는 구조는 디버깅 불가능. 훅은 **독립적·멱등**이어야 한다.

### 11-4. 과도한 Sub Agent 중첩

메인 → agent → sub-agent → sub-sub-agent: 비용 폭발. **중첩은 2단계까지**.

### 11-5. 규칙 인플레이션

"모든 수정은 PRD 필수" 같은 규칙은 형식적 준수로 변질된다. **규칙은 위반 시 진짜로 문제 생기는 것만**.

### 11-6. 도구 제한 없는 Agent

agent에 tools 제한이 없으면 의도 밖 행동을 한다. **리뷰 agent가 Edit 도구를 가지고 있으면 반드시 수정한다**. 명시적으로 막아라.

### 11-7. Settings에 장문 명령 통째로 포함

vmsworks의 `settings.local.json`이 이 패턴이다. 과거 승인한 긴 명령들이 allow 리스트를 오염시킨다. **정기적으로 정리**.

---

## 12. 시작 체크리스트 (1주일 플랜)

### Day 1 — 글로벌 CLAUDE.md (1~2시간)
- [ ] `~/.claude/CLAUDE.md` 작성 (이 가이드 4-1 골격 사용)
- [ ] 50줄 이내로 제한
- [ ] 한 번 세션 돌려보며 어색한 규칙 제거

### Day 2 — Permissions & Hooks (1~2시간)
- [ ] `~/.claude/settings.json` 작성 (9-2 템플릿)
- [ ] `guard-destructive.sh` 설치
- [ ] 포맷터 훅 설치 (사용 언어에 맞게)

### Day 3 — Core Agents (2~3시간)
- [ ] `code-reviewer.md` 작성 (5-2 템플릿)
- [ ] `researcher.md` 작성
- [ ] 실제 작업에서 1번씩 호출해 튜닝

### Day 4 — Core Commands (1~2시간)
- [ ] `/commit`, `/review`, `/plan` 작성
- [ ] 1주일간 매 작업에서 써보기

### Day 5 — Output Styles (30분)
- [ ] `concise` (짧은 응답 프리셋)
- [ ] `deep` (심층 분석 프리셋)

### Day 6 — 본인 반복 워크플로우 1개 → Skill 추출 (2~3시간)
- [ ] 최근 3번 이상 반복한 작업 식별
- [ ] `skill-creator`로 스킬화
- [ ] description 튜닝

### Day 7 — Eval & 정리 (1시간)
- [ ] 만든 스킬에 evals 3~5개
- [ ] 불필요한 권한 리스트 정리
- [ ] README 한 장 작성 (무엇을 넣었고 왜)

---

## 13. 운영 체크리스트 (월간)

매월 1회:

- [ ] CLAUDE.md를 처음 보는 눈으로 다시 읽기. 쓸모없는 규칙 제거
- [ ] Skill 사용 빈도 확인. 3개월간 미사용 스킬 아카이브
- [ ] Hooks 로그 검토. 오탐 훅 튜닝
- [ ] Permissions allow 리스트에서 의심스러운 항목 삭제
- [ ] lessons-learned 정리 → 반복 패턴 CLAUDE.md로 승격

---

## 14. 요약 — 5가지만 기억한다면

1. **CLAUDE.md는 헌법이다**. 50줄, 단호하게, 금지사항 위주로.
2. **탐색은 Agent에 위임**. 메인 세션 컨텍스트를 지켜라.
3. **게이트는 Hook으로 강제**. 프롬프트 게이트는 보조.
4. **스킬은 대형 지식의 수납장**. description이 트리거 품질을 결정.
5. **측정 없는 하네스는 썩는다**. Eval·월간 정리로 신선도 유지.

---

## 부록 A — vmsworks에서 배울 점과 버릴 점

### 배울 점

- CLAUDE.md 상단 "참조 문서" 테이블 — 방대한 규칙을 깔끔히 분할
- 기술 스택 결정표 — 애매함 제거
- 2개 게이트(PRD 승인, 검증 승인) — 안전장치
- 메인 세션은 오케스트레이션만 — 역할 분리
- `chub` CLI 같은 외부 문서 참조 규칙 — 최신성 확보
- `skills/dev/evals/` — 스킬 품질 관리
- lessons-learned 피드백 루프

### 버릴 점

- "모든 변경에 PRD 필수" — 개인용에는 과함
- Sub Agent 2단계 중첩 — 비용 대비 이득 낮음
- `settings.local.json`에 긴 커밋 메시지 통째로 — 설정 오염
- `deny` 리스트 공란 — 안전 공백
- `skills/dev.zip` 방치 — 관리 오염
- TASKBOARD를 `.docx` + `.md` 중복 유지 — 낭비

---

## 부록 B — 파일 템플릿 빠른 복사

### B-1. 최소 글로벌 CLAUDE.md

위 4-1 참조.

### B-2. 최소 글로벌 settings.json

```json
{
  "permissions": {
    "allow": [
      "Read", "Grep", "Glob",
      "Bash(ls:*)", "Bash(pwd)",
      "Bash(git status:*)", "Bash(git diff:*)", "Bash(git log:*)",
      "Bash(git branch:*)", "Bash(git checkout:*)"
    ],
    "deny": [
      "Bash(rm -rf ~*)",
      "Bash(rm -rf /*)",
      "Bash(git push --force:*)",
      "Bash(git reset --hard:*)",
      "Bash(sudo:*)",
      "Bash(*| sh)",
      "Bash(*| bash)"
    ],
    "ask": [
      "Write", "Edit",
      "Bash(git commit:*)",
      "Bash(git push)",
      "Bash(npm publish:*)",
      "Bash(pip install:*)",
      "WebFetch", "WebSearch"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "command": "~/.claude/hooks/guard-destructive.sh"}
    ],
    "PostToolUse": [
      {"matcher": "Edit|Write", "command": "~/.claude/hooks/format-on-save.sh"}
    ]
  }
}
```

### B-3. Code Reviewer Agent

위 5-2 참조.

### B-4. /commit Command

위 6-2 참조.

---

_끝._
_이 문서 자체도 본인에 맞게 다이어트할 것. 남이 쓴 가이드 그대로 따르는 건 본질적으로 "Claude를 남의 하네스로 쓰는 것"이다._
