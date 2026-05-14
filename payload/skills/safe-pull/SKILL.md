---
name: safe-pull
description: git pull 시 skip-worktree 플래그가 있는 파일(예: CLAUDE.local.md)이 원격 변경분과 충돌해 "Unable to pull when changes are present on your branch" 에러로 막힐 때 자동 처리. 로컬 파일을 백업한 뒤 stash → pull → 충돌 처리(원격/로컬/머지 전략) → skip-worktree 재설정까지 한 흐름으로 수행한다. 사용자가 "safe-pull", "git pull 충돌 해결", "skip-worktree 충돌", "pull 막혔어" 같은 요청을 할 때 트리거.
---

# safe-pull

`skip-worktree` 플래그가 걸린 파일이 원격 변경분과 충돌해 `git pull`이 막힐 때 자동 처리하는 스킬.

## 트리거

- `/safe-pull` 또는 `/safe-pull <repo-path>`
- "git pull 충돌 해결"
- "skip-worktree 충돌"
- "CLAUDE.local.md pull 막힘"
- IDE 에러 메시지: "Unable to pull when changes are present on your branch. The following files would be overwritten"

## 입력

- `<repo>` : 대상 저장소 경로. 생략 시 현재 작업 디렉토리에서 가장 가까운 git 저장소 root 자동 탐지 (`git rev-parse --show-toplevel`).
- `<strategy>` : 충돌 처리 전략 (기본 `remote`)
  - `remote` — 원격 버전 채택, 로컬은 백업 파일(`<file>.bak`)에만 보존
  - `local` — 로컬 백업으로 덮어쓰기, 원격 변경 폐기
  - `manual` — 충돌 마커 남기고 중단, 사용자가 수동 머지

전략을 명시 안 하면 사용자에게 한 줄로 물어본다. CLAUDE.local.md 같은 user-private 파일이면 보통 `remote` (백업만 보존하면 됨).

## 절차

### 1. 사전 점검
```bash
git -C <repo> fetch
git -C <repo> status --porcelain
git -C <repo> log HEAD..@{u} --oneline
git -C <repo> ls-files -v | grep '^S' || echo "no skip-worktree files"
```
- skip-worktree 파일 없고 status clean이면 `git pull --ff-only` 하고 종료
- fast-forward 불가능하면 중단 + 사용자 보고

### 2. 백업
각 skip-worktree 파일에 대해:
```bash
cp <repo>/<file> <repo>/<file>.bak
```
- 크기 검증. 실패 시 즉시 중단

### 3. skip-worktree 해제 + stash
```bash
git -C <repo> update-index --no-skip-worktree <file>  # 파일별
git -C <repo> stash push -m "safe-pull-backup-<timestamp>" -- <files...>
```

### 4. Pull
```bash
git -C <repo> pull --ff-only
```
- 실패 시 stash 보존한 채 즉시 중단

### 5. Stash pop + 충돌 처리
```bash
git -C <repo> stash pop
```
충돌 발생 시 전략에 따라:
- **remote**: `git -C <repo> checkout HEAD -- <file>` (원격 채택)
- **local**: 백업으로 덮어쓰기 (`cp <file>.bak <file>`) → `git add`
- **manual**: 충돌 마커 남기고 중단 (skip-worktree 재설정 안 함)

### 6. 마무리
```bash
git -C <repo> add <files...>
git -C <repo> stash drop  # 충돌 해결 완료한 경우만
git -C <repo> update-index --skip-worktree <file>  # 파일별
```

### 7. 최종 검증
- `git status` → clean
- skip-worktree 플래그 재설정 확인 (`ls-files -v` 첫 글자 `S`)
- 백업파일 보존 확인

## 보고 형식

```
처리 완료
- 저장소: <repo>
- 전략: <remote|local|manual>
- 처리 파일: <file1>, <file2>, ...
- 백업: <file>.bak 보존 (사용자 검토 후 직접 삭제)
- 최종 HEAD: <hash>
- skip-worktree 재설정: OK
```

## 실패 정책 (중요)

- **자동 롤백 없음.** 각 단계에서 실패하면 즉시 중단하고 사용자에게 상태 + 복구 명령 보고
- 백업 파일은 사용자가 명시 지시할 때까지 절대 삭제 안 함
- `git reset --hard`, `git push --force` 등 파괴적 명령 절대 사용 안 함
- `--ff-only` 강제 (merge commit 자동 생성 방지)
- stash는 충돌 해결 완료 확인 전까지 drop 안 함

## 안전 가드

- 위험 작업(stash, pull, checkout, update-index) 진행 전 [확인] 양식으로 사용자 컨펌 받기
  - 단 사용자가 명시적으로 자동 진행 지시한 경우(`/safe-pull --yes`) 생략
- skip-worktree 해제 시점부터 재설정 시점까지의 윈도우를 최소화
- 백업 → 해제 → stash → pull → pop → 재설정 순서 엄수 (순서 바꾸면 데이터 손실 위험)

## 트러블슈팅

| 증상 | 원인 | 대응 |
|---|---|---|
| pull 실패: non-ff | 로컬에 push 안 한 커밋 존재 | 사용자에게 보고. rebase는 사용자 결정 |
| stash pop 충돌 마커 잔존 | 자동 머지 실패 | 전략에 따라 처리 |
| skip-worktree 재설정 후에도 IDE가 dirty 표시 | IDE 캐시 | IDE 재시작 권고 |
| 백업 파일 이미 존재 | 이전 실행 흔적 | 타임스탬프 suffix 붙여서 새로 생성 |
