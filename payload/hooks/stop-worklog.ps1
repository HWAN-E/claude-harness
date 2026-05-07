# Stop hook — work-log 자동 기록
#
# Claude Code 가 응답 한 턴을 마칠 때 호출된다.
# stdin: { session_id, transcript_path, cwd, stop_hook_active, ... }
#
# 의도: Claude 가 그 턴에 "수행한 작업" 을 기록한다 (대화 Q/A 가 아니라 행위/변경).
#
# 동작:
#  1. transcript 의 마지막 assistant turn 에서 <!--worklog: action=... | files=... | notes=...--> 추출
#  2. 메타블록 누락 시 fallback: 도구 호출에서 변경 파일 자동 추출, action 은 "(누락)" 표기
#  3. <cwd>/.claude/work-log/YYYY-MM-DD.md 에 append
#
# 실패해도 Claude 동작에 영향이 없도록 모든 예외는 삼킨다 (exit 0).

$ErrorActionPreference = 'Continue'

# UTF-8 명시 (work-log 파일의 한글 정상 기록 보장)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding           = [System.Text.UTF8Encoding]::new($false)

try {
    $raw = [Console]::In.ReadToEnd()
    if (-not $raw) { exit 0 }
    $event = $raw | ConvertFrom-Json

    $transcript = $event.transcript_path
    $cwd        = if ($event.cwd) { $event.cwd } else { $PWD.Path }

    if (-not $transcript -or -not (Test-Path $transcript)) { exit 0 }

    $lines = Get-Content -LiteralPath $transcript -Tail 200 -ErrorAction SilentlyContinue
    if (-not $lines) { exit 0 }

    $msgs = New-Object System.Collections.ArrayList
    foreach ($l in $lines) {
        if ([string]::IsNullOrWhiteSpace($l)) { continue }
        try { [void]$msgs.Add(($l | ConvertFrom-Json)) } catch {}
    }

    # 마지막 assistant 추출 (user 는 사용 안 함 — 의도상 행위만 기록)
    $lastAssistant = $null
    for ($i = $msgs.Count - 1; $i -ge 0; $i--) {
        if ($msgs[$i].type -eq 'assistant') { $lastAssistant = $msgs[$i]; break }
    }
    if (-not $lastAssistant) { exit 0 }

    function Get-Text($m) {
        if ($null -eq $m) { return '' }
        if ($m.message -and $m.message.content) {
            $parts = @()
            foreach ($c in $m.message.content) {
                if ($c.type -eq 'text' -and $c.text) { $parts += $c.text }
            }
            return ($parts -join "`n")
        }
        return ''
    }

    $assistantText = Get-Text $lastAssistant

    # 메타블록 추출
    $Action = $null; $Files = $null; $Notes = $null
    $pat = '<!--\s*worklog:\s*(.+?)\s*-->'
    $mm  = [regex]::Match($assistantText, $pat, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($mm.Success) {
        $body = $mm.Groups[1].Value
        foreach ($kv in $body -split '\|') {
            $kv = $kv.Trim()
            if ($kv -match '^(?i)action\s*=\s*(.+)$') { $Action = $matches[1].Trim() }
            if ($kv -match '^(?i)files\s*=\s*(.+)$')  { $Files  = $matches[1].Trim() }
            if ($kv -match '^(?i)notes\s*=\s*(.+)$')  { $Notes  = $matches[1].Trim() }
        }
    }

    # files 가 비었으면 도구 호출에서 자동 추출
    if (-not $Files) {
        $editedFiles = New-Object System.Collections.ArrayList
        if ($lastAssistant.message -and $lastAssistant.message.content) {
            foreach ($c in $lastAssistant.message.content) {
                if ($c.type -eq 'tool_use' -and $c.name -in @('Write','Edit','MultiEdit','NotebookEdit')) {
                    if ($c.input -and $c.input.file_path) {
                        $marker = if ($c.name -eq 'Write') { '+' } else { 'M' }
                        [void]$editedFiles.Add("$marker  $($c.input.file_path)")
                    }
                }
            }
        }
        if ($editedFiles.Count -gt 0) {
            $Files = ($editedFiles -join ', ')
        }
    }

    if (-not $Action) {
        if ($Files) {
            $Action = "(action 누락) — 자동 추출 파일 $((($Files -split ',') | Measure-Object).Count)개"
        } else {
            $Action = '(action 누락 + 변경 파일 없음)'
        }
    }

    # 변경이 전혀 없는 turn 은 기록하지 않음 (탐색/조회만 한 응답)
    if (-not $Files -and $Action -like '(action 누락*') { exit 0 }

    # 민감 정보 redact
    $badPats = @(
        'AKIA[0-9A-Z]{16}',
        'ghp_[A-Za-z0-9]{20,}',
        'xox[baprs]-[0-9A-Za-z\-]+',
        'sk-[A-Za-z0-9]{20,}',
        'AIza[0-9A-Za-z\-_]{30,}'
    )
    foreach ($p in $badPats) {
        if ($Action -and ($Action -match $p)) { $Action = '[redacted by guard]' }
        if ($Notes  -and ($Notes  -match $p)) { $Notes  = '[redacted by guard]' }
        if ($Files  -and ($Files  -match $p)) { $Files  = '[redacted by guard]' }
    }

    # 파일 append
    $logDir  = Join-Path $cwd '.claude\work-log'
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
    $logFile = Join-Path $logDir ("$(Get-Date -Format 'yyyy-MM-dd').md")
    $ts      = Get-Date -Format 'HH:mm'

    $out = New-Object System.Collections.ArrayList
    [void]$out.Add("## $ts")
    [void]$out.Add("- 작업: $Action")
    if ($Files -and $Files -ne '-') {
        [void]$out.Add('- 변경:')
        foreach ($f in ($Files -split ',')) {
            $f = $f.Trim()
            if ($f) { [void]$out.Add("  - $f") }
        }
    }
    if ($Notes) {
        [void]$out.Add("- 비고: $Notes")
    }
    [void]$out.Add('')

    Add-Content -LiteralPath $logFile -Value ($out -join "`n") -Encoding utf8
} catch {
    [Console]::Error.WriteLine("[stop-worklog] $($_.Exception.Message)")
}

exit 0
