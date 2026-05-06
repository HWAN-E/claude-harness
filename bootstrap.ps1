# claude-harness bootstrap
# 새 PC에서 처음 실행하는 진입점.
# 한 줄 부트스트랩:
#   iwr -useb https://raw.githubusercontent.com/<USER>/claude-harness/main/bootstrap.ps1 | iex

[CmdletBinding()]
param(
    [string]$RepoUrl  = 'https://github.com/HWAN-E/claude-harness.git',
    [string]$CloneTo  = 'D:\workspace\claude-harness',
    [string]$Branch   = 'main'
)

$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "[bootstrap] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[bootstrap] $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host "[bootstrap] $msg" -ForegroundColor Yellow }

# 1) git 확인 / 설치
Write-Step 'checking git...'
$git = Get-Command git -ErrorAction SilentlyContinue
if (-not $git) {
    Write-Warn2 'git not found, attempting winget install...'
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw 'winget not available. install Git manually: https://git-scm.com/download/win'
    }
    winget install --id Git.Git -e --silent --accept-package-agreements --accept-source-agreements
    # PATH 갱신
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'git installation seems to have failed. open a new shell and re-run this script.'
    }
}
Write-Ok 'git ok.'

# 2) clone or pull
$parent = Split-Path -Parent $CloneTo
if (-not (Test-Path $parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
}

if (Test-Path (Join-Path $CloneTo '.git')) {
    Write-Step "repo already cloned at $CloneTo, pulling..."
    git -C $CloneTo fetch --quiet
    git -C $CloneTo checkout --quiet $Branch
    git -C $CloneTo pull --ff-only --quiet
} else {
    if (Test-Path $CloneTo) {
        throw "$CloneTo exists but is not a git repo. remove or move it first."
    }
    Write-Step "cloning $RepoUrl -> $CloneTo"
    git clone --branch $Branch --quiet $RepoUrl $CloneTo
}
Write-Ok 'repo ready.'

# 3) install
Write-Step 'running install.ps1...'
& (Join-Path $CloneTo 'install.ps1')
Write-Ok 'bootstrap complete.'
