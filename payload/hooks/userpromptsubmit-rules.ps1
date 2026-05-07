# UserPromptSubmit hook — 핵심 규칙 재주입
#
# 사용자 메시지가 제출될 때마다 발화.
# stdout 출력은 Claude 의 컨텍스트에 추가 컨텍스트로 주입된다 (사용자에게는 안 보임).
# CLAUDE.md 가 시스템 프롬프트에 한 번 박히는 것과 별개로, 매 턴마다 가까이 박아 어텐션을 끌어올리는 역할.

$ErrorActionPreference = 'Continue'

# Claude Code 가 stdout 을 UTF-8 로 받을 수 있도록 명시 (한국어 Windows 의 CP949 mojibake 회피)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding           = [System.Text.UTF8Encoding]::new($false)

try {
    [void][Console]::In.ReadToEnd()  # stdin 비움 (사용 안 함)

    @"
[harness rules — 매 턴 재확인]
- 한국어, 짧게 결과 위주.
- 영어 기술 용어 처음 등장 시 * 표시 + 응답 끝 각주. (API/git/commit/merge 등 일반 용어 제외)
- 위험 작업(삭제, commit/push/rebase/reset/force, DB drop·truncate, 외부 API 호출, 결제, 배포) 사전 [확인] 양식 필수:
    [확인] 작업: <무엇> / 영향: <어디까지> / 롤백: <어떻게> — 진행할까요?
- 사용자 컨펌 없이 자동 git commit / push / rebase / reset --hard / 파일 강제삭제 금지.
- 응답 끝에 다음 한 줄을 반드시 포함 (대화가 아니라 "수행한 작업"을 기록):
    <!--worklog: action=<수행한 작업 한 줄> | files=<+/M/- path 콤마구분 또는 -> | notes=<선택, 의사결정·왜>-->
  변경이 전혀 없는 응답(조회·답변만)이라도 메타블록 자체는 박되 files=- 로 둔다 (hook 이 알아서 무시).
"@ | Write-Output
} catch {
    [Console]::Error.WriteLine("[userpromptsubmit-rules] $($_.Exception.Message)")
}

exit 0
