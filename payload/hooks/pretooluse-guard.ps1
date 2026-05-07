# PreToolUse hook — 위험 명령 가드
#
# Bash / PowerShell 도구 호출 직전에 명령어를 검사.
# 위험 패턴이면 stderr 로 안내 + exit 2 (Claude Code 가 차단으로 해석)
#
# stdin: { tool_name, tool_input: { command, ... }, ... }
# 정상: exit 0
# 차단: exit 2 + stderr 메시지

$ErrorActionPreference = 'Continue'

# UTF-8 명시 (stderr 의 한국어 메시지 mojibake 회피)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding           = [System.Text.UTF8Encoding]::new($false)

try {
    $raw = [Console]::In.ReadToEnd()
    if (-not $raw) { exit 0 }
    $event = $raw | ConvertFrom-Json

    $tool = $event.tool_name
    if ($tool -notin @('Bash','PowerShell')) { exit 0 }

    $cmd = ''
    if ($event.tool_input -and $event.tool_input.command) {
        $cmd = [string]$event.tool_input.command
    }
    if (-not $cmd) { exit 0 }

    $patterns = @(
        @{ name='rm -rf';                pat='\brm\s+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r)\b' },
        @{ name='Remove-Item -R -F';     pat='Remove-Item.+-Recurse.+-Force|Remove-Item.+-Force.+-Recurse' },
        @{ name='git push --force';      pat='\bgit\s+push\s+(-f\b|--force\b|--force-with-lease\b)' },
        @{ name='git reset --hard';      pat='\bgit\s+reset\s+(--hard|--keep)\b' },
        @{ name='git clean -fd';         pat='\bgit\s+clean\s+-[a-zA-Z]*f[a-zA-Z]*' },
        @{ name='git rebase';            pat='\bgit\s+rebase\b' },
        @{ name='git checkout --';       pat='\bgit\s+checkout\s+--\s' },
        @{ name='git restore (path)';    pat='\bgit\s+restore\s+(\.|--source|--worktree)' },
        @{ name='git branch -D';         pat='\bgit\s+branch\s+-D\b' },
        @{ name='DROP TABLE';            pat='(?i)\bDROP\s+(TABLE|DATABASE|SCHEMA)\b' },
        @{ name='TRUNCATE';              pat='(?i)\bTRUNCATE\s+TABLE\b' },
        @{ name='DELETE without WHERE';  pat='(?i)\bDELETE\s+FROM\s+\w+(\s*;|\s*$)' }
    )

    foreach ($p in $patterns) {
        if ($cmd -match $p.pat) {
            $msg = @"
[harness/guard] 위험 명령 감지: $($p.name)
명령: $cmd

work_style.md / CLAUDE.md 의 사전 확인 정책에 따라 차단되었습니다.
사용자 컨펌 양식으로 다시 요청하세요:

  [확인] 작업: <무엇> / 영향: <어디까지> / 롤백: <어떻게> — 진행할까요?

사용자 승인을 받은 후 같은 명령을 다시 호출하면 통과합니다 (자동 우회 시도 금지).
"@
            [Console]::Error.WriteLine($msg)
            exit 2
        }
    }
} catch {
    [Console]::Error.WriteLine("[pretooluse-guard] $($_.Exception.Message)")
}

exit 0
