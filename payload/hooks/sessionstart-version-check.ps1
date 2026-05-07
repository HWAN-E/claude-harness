# SessionStart hook — claude-harness 업데이트 알림
#
# 새 세션 시작 시 발화. GitHub raw URL 에서 main 브랜치의 version.txt 를 가져와
# 로컬 ~/.claude/.harness-version 과 비교. 새 버전 있으면 stdout 으로 알림.
# stdout 은 Claude 의 컨텍스트로 주입되어, 적절한 시점에 사용자에게 안내된다.
#
# stdin: { session_id, source: "startup"|"resume"|"clear", cwd, ... }
#
# 모든 예외는 삼킨다 — Claude 동작 방해 방지.

$ErrorActionPreference = 'Continue'

# UTF-8 명시 (한국어 Windows mojibake 회피)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding           = [System.Text.UTF8Encoding]::new($false)

try {
    [void][Console]::In.ReadToEnd()

    $localVerFile = Join-Path $env:USERPROFILE '.claude\.harness-version'
    if (-not (Test-Path $localVerFile)) { exit 0 }  # harness 미설치
    $local = (Get-Content $localVerFile -Raw -ErrorAction SilentlyContinue).Trim()
    if (-not $local) { exit 0 }

    $remoteUrl = 'https://raw.githubusercontent.com/HWAN-E/claude-harness/main/version.txt'
    $remote = $null
    try {
        $resp = Invoke-WebRequest -Uri $remoteUrl -UseBasicParsing -TimeoutSec 5
        if ($resp -and $resp.Content) { $remote = ([string]$resp.Content).Trim() }
    } catch {
        exit 0  # 네트워크 실패 시 조용히 종료
    }
    if (-not $remote) { exit 0 }

    if ($local -ne $remote) {
        $repoFile = Join-Path $env:USERPROFILE '.claude\.harness-repo'
        $repoPath = if (Test-Path $repoFile) {
            (Get-Content $repoFile -Raw).Trim()
        } else {
            'D:\workspace\claude-harness'
        }
        $updateCmd = Join-Path $repoPath 'update.cmd'

        @"
[claude-harness] 새 버전 사용 가능 — v$remote (현재 v$local).
업데이트하려면 다음을 실행하세요:
    $updateCmd
"@ | Write-Output
    }
} catch {
    [Console]::Error.WriteLine("[sessionstart-version-check] $($_.Exception.Message)")
}

exit 0
