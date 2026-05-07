# claude-harness installer
# payload/* 의 내용을 ~/.claude/ 로 배치한다.
# - memory/, agents/, skills/, hooks/  : 파일 단위 복사 (기존 같은 이름 파일은 덮어씀, 그 외는 보존)
# - CLAUDE.md                          : 덮어씀 (백업 후)
# - settings.partial.json              : settings.json 에 머지 (배열은 union, 객체는 deep merge)

[CmdletBinding()]
param(
    [string]$ClaudeHome = (Join-Path $env:USERPROFILE '.claude'),
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Payload  = Join-Path $RepoRoot 'payload'

function Write-Step($msg) { Write-Host "[install] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[install] $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host "[install] $msg" -ForegroundColor Yellow }

if (-not (Test-Path $Payload)) { throw "payload not found at $Payload" }
if (-not (Test-Path $ClaudeHome)) {
    Write-Step "creating $ClaudeHome"
    if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $ClaudeHome | Out-Null }
}

# === 백업 ===
$Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupDir = Join-Path $ClaudeHome ".harness-backups\$Stamp"
Write-Step "backup -> $BackupDir"
if (-not $DryRun) {
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    foreach ($name in @('settings.json','CLAUDE.md')) {
        $src = Join-Path $ClaudeHome $name
        if (Test-Path $src) { Copy-Item $src (Join-Path $BackupDir $name) -Force }
    }
}

# === payload 디렉토리 복사 헬퍼 ===
function Copy-PayloadDir {
    param([string]$Sub)
    $src = Join-Path $Payload $Sub
    $dst = Join-Path $ClaudeHome $Sub
    if (-not (Test-Path $src)) { return }
    Write-Step "copy payload/$Sub -> ~/.claude/$Sub"
    if ($DryRun) { return }
    if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Force -Path $dst | Out-Null }
    # 파일 단위 복사 — 기존 디렉토리 통째 삭제하지 않음 (다른 도구가 둔 파일 보호)
    Get-ChildItem $src -Recurse -File | ForEach-Object {
        $rel    = $_.FullName.Substring($src.Length).TrimStart('\','/')
        $target = Join-Path $dst $rel
        $tdir   = Split-Path -Parent $target
        if (-not (Test-Path $tdir)) { New-Item -ItemType Directory -Force -Path $tdir | Out-Null }
        Copy-Item $_.FullName $target -Force
    }
}

Copy-PayloadDir 'memory'
Copy-PayloadDir 'agents'
Copy-PayloadDir 'skills'
Copy-PayloadDir 'hooks'

# === CLAUDE.md ===
$claudeMdSrc = Join-Path $Payload 'CLAUDE.md'
if (Test-Path $claudeMdSrc) {
    Write-Step 'copy payload/CLAUDE.md -> ~/.claude/CLAUDE.md'
    if (-not $DryRun) { Copy-Item $claudeMdSrc (Join-Path $ClaudeHome 'CLAUDE.md') -Force }
}

# === settings.partial.json 머지 ===

# 우리가 등록할 hook 들을 식별자(스크립트 파일명)로 미리 제거 — 멱등성 보장
# install 을 여러 번 돌려도 같은 hook 이 settings.json 의 hooks 배열에 중복 추가되지 않도록.
function Remove-OurHooks {
    param($Settings)
    if (-not $Settings -or -not $Settings.hooks) { return $Settings }
    $ourMarkers = @(
        'sessionstart-version-check.ps1',
        'stop-worklog.ps1',
        'pretooluse-guard.ps1',
        'userpromptsubmit-rules.ps1'
    )
    $eventNames = @($Settings.hooks.PSObject.Properties.Name)
    foreach ($evtName in $eventNames) {
        $arr    = @($Settings.hooks.$evtName)
        $newArr = @()
        foreach ($entry in $arr) {
            $hasOurs = $false
            if ($entry -and $entry.hooks) {
                foreach ($h in $entry.hooks) {
                    if ($h -and $h.command) {
                        foreach ($m in $ourMarkers) {
                            if ($h.command -like "*$m*") { $hasOurs = $true; break }
                        }
                    }
                    if ($hasOurs) { break }
                }
            }
            if (-not $hasOurs) { $newArr += $entry }
        }
        if ($newArr.Count -gt 0) {
            $Settings.hooks.$evtName = $newArr
        } else {
            $Settings.hooks.PSObject.Properties.Remove($evtName)
        }
    }
    return $Settings
}

function Merge-Json {
    param($Base, $Patch)
    if ($null -eq $Base)  { return $Patch }
    if ($null -eq $Patch) { return $Base }
    if ($Patch -is [pscustomobject]) {
        if ($Base -isnot [pscustomobject]) { return $Patch }
        # 깊은 복사
        $result = $Base | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        foreach ($p in $Patch.PSObject.Properties) {
            $k = $p.Name; $v = $p.Value
            if ($result.PSObject.Properties[$k]) {
                $result.$k = Merge-Json $result.$k $v
            } else {
                $result | Add-Member -NotePropertyName $k -NotePropertyValue $v -Force
            }
        }
        return $result
    }
    if ($Patch -is [System.Collections.IEnumerable] -and $Patch -isnot [string]) {
        if ($Base -is [System.Collections.IEnumerable] -and $Base -isnot [string]) {
            return @(@($Base) + @($Patch) | Select-Object -Unique)
        }
        return $Patch
    }
    return $Patch
}

$partial = Join-Path $Payload 'settings.partial.json'
if (Test-Path $partial) {
    Write-Step 'merge settings.partial.json -> ~/.claude/settings.json'
    $existingPath = Join-Path $ClaudeHome 'settings.json'
    $existing = if (Test-Path $existingPath) {
        Get-Content $existingPath -Raw | ConvertFrom-Json
    } else { New-Object psobject }

    # placeholder 치환 — {{USERPROFILE}} 를 사용자별 홈 경로 (forward slash) 로
    $partialText  = Get-Content $partial -Raw
    $userHomeFwd  = $env:USERPROFILE.Replace('\','/')
    $partialText  = $partialText.Replace('{{USERPROFILE}}', $userHomeFwd)

    $patch    = $partialText | ConvertFrom-Json
    $existing = Remove-OurHooks $existing   # 멱등성 — 우리 hook 중복 등록 방지
    $merged   = Merge-Json $existing $patch
    if (-not $DryRun) {
        $merged | ConvertTo-Json -Depth 30 | Out-File $existingPath -Encoding utf8
    }
}

# === 버전 기록 ===
$verSrc = Join-Path $RepoRoot 'version.txt'
if (Test-Path $verSrc) {
    $ver = (Get-Content $verSrc -Raw).Trim()
    Write-Step "stamp version $ver -> ~/.claude/.harness-version"
    if (-not $DryRun) { Set-Content (Join-Path $ClaudeHome '.harness-version') $ver -Encoding utf8 }
}

# === harness repo 경로 기록 (SessionStart hook 이 update.cmd 안내에 사용) ===
Write-Step "stamp repo path -> ~/.claude/.harness-repo"
if (-not $DryRun) { Set-Content (Join-Path $ClaudeHome '.harness-repo') $RepoRoot -Encoding utf8 }

Write-Ok 'install complete.'
if (-not $DryRun) { Write-Ok "backup: $BackupDir" }
