# claude-harness updater
# git pull 후 install.ps1 재실행

[CmdletBinding()]
param(
    [string]$Branch = 'main'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Step($msg) { Write-Host "[update] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[update] $msg" -ForegroundColor Green }

if (-not (Test-Path (Join-Path $RepoRoot '.git'))) {
    throw "$RepoRoot is not a git repo. run bootstrap.ps1 first."
}

Write-Step 'fetching...'
git -C $RepoRoot fetch --quiet

$local  = (git -C $RepoRoot rev-parse HEAD).Trim()
$remote = (git -C $RepoRoot rev-parse "origin/$Branch").Trim()

if ($local -eq $remote) {
    Write-Ok 'already up to date.'
} else {
    Write-Step "pulling $local -> $remote"
    git -C $RepoRoot checkout --quiet $Branch
    git -C $RepoRoot pull --ff-only --quiet
}

Write-Step 'running install.ps1...'
& (Join-Path $RepoRoot 'install.ps1')
Write-Ok 'update complete.'
