# claude-harness

Claude Code 글로벌 환경(`~/.claude/`)을 한 줄로 동기화하기 위한 개인용 하네스.
어느 PC에서도 동일한 메모리 / hooks / agents / skills / settings 를 갖게 한다.

## 설치 (새 PC, 최초 1회)

PowerShell 에서:

```powershell
iwr -useb https://raw.githubusercontent.com/HWAN-E/claude-harness/main/bootstrap.ps1 | iex
```

> git 이 없으면 winget 으로 자동 설치한다. PowerShell 실행 정책 차단 시:
> `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`

기본 클론 위치는 `D:\workspace\claude-harness`. 다른 위치로 받으려면:

```powershell
& ([scriptblock]::Create((iwr -useb https://raw.githubusercontent.com/HWAN-E/claude-harness/main/bootstrap.ps1))) -CloneTo 'C:\tools\claude-harness'
```

## 업데이트

```powershell
# 클론된 폴더에서 (또는 update.cmd 더블클릭)
.\update.ps1
```

## 제거

```powershell
.\uninstall.ps1
```

> `settings.json` 은 머지로 들어간 값이라 자동 롤백되지 않는다. `~/.claude/.harness-backups/` 의 가장 최근 백업에서 수동 복원.

## 구조

```
claude-harness/
├── bootstrap.ps1              # 새 PC 진입점 (git 확인 → clone → install)
├── install.ps1                # payload → ~/.claude 배치
├── update.ps1                 # git pull → install
├── uninstall.ps1
├── install.cmd / update.cmd   # 더블클릭 런처
├── version.txt                # SemVer
└── payload/
    ├── memory/                # → ~/.claude/memory/
    ├── CLAUDE.md              # → ~/.claude/CLAUDE.md
    ├── hooks/                 # → ~/.claude/hooks/
    ├── agents/                # → ~/.claude/agents/   (커스텀 에이전트)
    ├── skills/                # → ~/.claude/skills/   (커스텀 스킬)
    └── settings.partial.json  # → ~/.claude/settings.json (머지)
```

## 동작 원칙

- **머지 우선** — 디렉토리는 통째 삭제하지 않고 파일 단위로 복사한다. `settings.json` 은 deep merge (배열은 union).
- **백업** — 매 install 마다 `~/.claude/.harness-backups/<timestamp>/` 에 `settings.json`, `CLAUDE.md` 백업.
- **민감 정보 비포함** — 회사 컨텍스트 / API 키 / 식별 정보는 repo 에 들어오지 않는다. 프로젝트별 `CLAUDE.md` 또는 별도 비공개 채널로 분리.

## 버전

- `version.txt` 가 SemVer.
- 설치 시 `~/.claude/.harness-version` 에 기록 — 새 세션에서 비교해 업데이트 알림 가능 (hook 로 별도 구현).
