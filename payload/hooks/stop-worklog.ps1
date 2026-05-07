# Stop hook — work-log 자동 기록
#
# Claude Code 가 응답 한 턴을 마칠 때 호출된다.
# stdin: { session_id, transcript_path, cwd, stop_hook_active, ... }
#
# 의도: Claude 가 그 턴에 "수행한 작업" 을 기록한다 (대화 Q/A 가 아니라 행위/변경).
#
# 동작:
#  1. transcript 의 최근 assistant turn 들을 모두 모음
#     (Claude Code 는 한 응답을 여러 turn 으로 split — 각 turn 이 하나의 content block)
#  2. 모든 텍스트 합쳐서 가장 마지막 worklog 메타블록 추출
#  3. 메타블록 없으면 도구 호출에서 변경 파일 자동 추출 (fallback)
#  4. <cwd>/.claude/work-log/YYYY-MM-DD.md 에 append
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

    # 최근 800 줄 (한 응답에 도구 호출이 많아도 여유)
    $lines = Get-Content -LiteralPath $transcript -Tail 800 -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $lines) { exit 0 }

    # 모든 assistant turn 의 text 합치기 + tool_use 의 변경 파일 수집
    $allText     = New-Object System.Text.StringBuilder
    $editedFiles = New-Object System.Collections.ArrayList
    foreach ($l in $lines) {
        if ([string]::IsNullOrWhiteSpace($l)) { continue }
        try {
            $m = $l | ConvertFrom-Json
            if ($m.type -ne 'assistant') { continue }
            if (-not $m.message -or -not $m.message.content) { continue }
            foreach ($c in $m.message.content) {
                if ($c.type -eq 'text' -and $c.text) {
                    [void]$allText.AppendLine($c.text)
                }
                elseif ($c.type -eq 'tool_use' -and $c.name -in @('Write','Edit','MultiEdit','NotebookEdit')) {
                    if ($c.input -and $c.input.file_path) {
                        $marker = if ($c.name -eq 'Write') { '+' } else { 'M' }
                        [void]$editedFiles.Add("$marker  $($c.input.file_path)")
                    }
                }
            }
        } catch {}
    }

    $assistantText = $allText.ToString()

    # 가장 마지막 worklog 메타블록 찾기 (현재 응답에서 박은 것)
    $Action = $null; $Files = $null; $Notes = $null
    $rx     = [regex]'<!--\s*worklog:\s*(.+?)\s*-->'
    $hits   = $rx.Matches($assistantText)
    if ($hits.Count -gt 0) {
        $body = $hits[$hits.Count - 1].Groups[1].Value
        foreach ($kv in $body -split '\|') {
            $kv = $kv.Trim()
            if ($kv -match '^(?i)action\s*=\s*(.+)$') { $Action = $matches[1].Trim() }
            if ($kv -match '^(?i)files\s*=\s*(.+)$')  { $Files  = $matches[1].Trim() }
            if ($kv -match '^(?i)notes\s*=\s*(.+)$')  { $Notes  = $matches[1].Trim() }
        }
    }

    # files=- 는 명시적 "변경 없음" — fallback 안 함
    $explicitNoFiles = ($Files -eq '-')
    if ($explicitNoFiles) { $Files = $null }

    # files 가 비었고 explicit "-" 도 아니면 도구 호출에서 자동 추출 (마지막 30개만)
    if (-not $Files -and -not $explicitNoFiles -and $editedFiles.Count -gt 0) {
        $tail = $editedFiles | Select-Object -Last 30
        $Files = ($tail) -join ', '
    }

    # action 도 메타블록도 없고 변경 파일도 없으면 skip
    if (-not $Action -and -not $Files) { exit 0 }

    if (-not $Action) {
        $Action = "(action 누락) — 자동 추출 파일 $((($Files -split ',') | Measure-Object).Count)개"
    }

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
    $logDir = Join-Path $cwd '.claude\work-log'
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
    $logFile = Join-Path $logDir ("$(Get-Date -Format 'yyyy-MM-dd').md")
    $ts      = Get-Date -Format 'HH:mm'

    $out = New-Object System.Collections.ArrayList
    [void]$out.Add("## $ts")
    [void]$out.Add("- 작업: $Action")
    if ($Files) {
        [void]$out.Add('- 변경:')
        foreach ($f in ($Files -split ',')) {
            $f = $f.Trim()
            if ($f) { [void]$out.Add("  - $f") }
        }
    }
    if ($Notes) { [void]$out.Add("- 비고: $Notes") }
    [void]$out.Add('')

    Add-Content -LiteralPath $logFile -Value ($out -join "`n") -Encoding utf8
} catch {
    [Console]::Error.WriteLine("[stop-worklog] $($_.Exception.Message)")
}

exit 0
