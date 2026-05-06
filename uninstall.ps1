# claude-harness uninstaller
# payload 가 설치한 흔적 중 "이 repo가 책임지는" 항목만 제거.
# 사용자가 직접 만든 메모리/에이전트/스킬은 건드리지 않는다 — payload 내부에 같은 이름 파일이 있을 때만 제거.

[CmdletBinding()]
param(
    [string]$ClaudeHome = (Join-Path $env:USERPROFILE '.claude'),
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Payload  = Join-Path $RepoRoot 'payload'

function Write-Step($msg) { Write-Host "[uninstall] $msg" -ForegroundColor Cyan }

if (-not (Test-Path $Payload))   { throw "payload not found at $Payload" }
if (-not (Test-Path $ClaudeHome)) { Write-Step 'no ~/.claude/, nothing to do'; return }

function Remove-PayloadMirror {
    param([string]$Sub)
    $src = Join-Path $Payload $Sub
    $dst = Join-Path $ClaudeHome $Sub
    if (-not (Test-Path $src)) { return }
    if (-not (Test-Path $dst)) { return }
    Get-ChildItem $src -Recurse -File | ForEach-Object {
        $rel    = $_.FullName.Substring($src.Length).TrimStart('\','/')
        $target = Join-Path $dst $rel
        if (Test-Path $target) {
            Write-Step "remove $target"
            if (-not $DryRun) { Remove-Item $target -Force }
        }
    }
}

Remove-PayloadMirror 'memory'
Remove-PayloadMirror 'agents'
Remove-PayloadMirror 'skills'
Remove-PayloadMirror 'hooks'

# CLAUDE.md
if (Test-Path (Join-Path $Payload 'CLAUDE.md')) {
    $t = Join-Path $ClaudeHome 'CLAUDE.md'
    if (Test-Path $t) {
        Write-Step "remove $t"
        if (-not $DryRun) { Remove-Item $t -Force }
    }
}

# 버전 마커
$verFile = Join-Path $ClaudeHome '.harness-version'
if (Test-Path $verFile) {
    Write-Step "remove $verFile"
    if (-not $DryRun) { Remove-Item $verFile -Force }
}

Write-Host '[uninstall] done. (settings.json은 머지된 값이라 자동 롤백 안 함 — .harness-backups 에서 수동 복원)' -ForegroundColor Yellow
