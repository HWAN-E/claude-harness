# Session Handoff Hook (멀티 HANDOFF 구조)
#
# 저장 구조:
#  - <cwd>/.claude/HANDOFF/<yyyy-MM-dd_HHmm>-<slug>.md  (토픽별 인계 파일들)
#  - <cwd>/.claude/HANDOFF.archive/                      (로드 후 이동된 파일들)
#  - <cwd>/.claude/HANDOFF.md                            (구버전 fallback, 발견 시 단일 처리)
#
# 이벤트:
#  - UserPromptSubmit: "종료/이월" 표현 감지 시 새 HANDOFF 파일 작성 지시 주입
#  - SessionStart:
#       * HANDOFF/*.md 중 mtime 가장 최근 1개 → 전체 주입 + archive 이동
#       * 나머지 HANDOFF/*.md → 목록만 표시 (자동 로드 안 함)
#       * HANDOFF.md (단일, 구버전)도 fallback 처리
#
# 모드 분기: -Mode UserPrompt | SessionStart
# 실패해도 Claude 동작에 영향이 없도록 모든 예외는 삼킨다 (exit 0).

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('UserPrompt','SessionStart')]
    [string]$Mode
)

$ErrorActionPreference = 'Continue'
[Console]::InputEncoding  = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding           = [System.Text.UTF8Encoding]::new($false)

try {
    $raw = [Console]::In.ReadToEnd()
    if (-not $raw) { exit 0 }
    $payload = $raw | ConvertFrom-Json -ErrorAction Stop

    $cwd = if ($payload.cwd) { $payload.cwd } else { (Get-Location).Path }

    $handoffDir   = Join-Path $cwd '.claude\HANDOFF'
    $archiveDir   = Join-Path $cwd '.claude\HANDOFF.archive'
    $legacyFile   = Join-Path $cwd '.claude\HANDOFF.md'

    if ($Mode -eq 'UserPrompt') {
        $prompt = [string]$payload.prompt
        if (-not $prompt) { exit 0 }

        $pattern = '여기까지|퇴근|일단\s*여기|마무리할게|이어가고\s*싶|다음\s*세션|오늘.*(마무리|끝|마칠|일과)|내일.*(이어|계속|다시)|이어서.*(진행|해줘|할게)|새\s*세션'

        if ($prompt -notmatch $pattern) { exit 0 }

        $stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
        $instruction = @"
[세션 인계 트리거 — 멀티 HANDOFF 구조]
사용자가 종료/이월을 시사했습니다. 이번 응답을 마무리하기 전에 반드시 다음을 수행하세요:

1. 파일 작성 위치: ``$handoffDir\$stamp-<slug>.md``
   - ``<slug>``는 작업 토픽을 식별 가능한 짧은 영문 슬러그 (예: ``doc-generation``, ``isu-pegging-fix``, ``handoff-multi-refactor``).
   - 폴더가 없으면 Write 도구로 파일을 만들면 자동 생성됩니다.
2. 파일 내용 (마크다운):
   - **현재 작업 목적과 맥락** (무엇을, 왜)
   - **지금까지의 진행 상황** (완료된 단계)
   - **다음에 즉시 해야 할 액션** (구체적으로)
   - **관련 파일 경로** (상대/절대 경로 명시)
   - **주의사항·미해결 결정** (있다면)
3. 여러 토픽을 병렬로 진행 중이라면 각 토픽별로 별도 파일을 만들어도 됩니다.
4. 다음 세션은 SessionStart 훅이 **가장 최근 1개만** 자동 로드하고, 나머지는 목록만 표시합니다. 다른 토픽을 이어가려면 사용자가 파일명을 지정해 요청하면 됩니다.

이 파일을 작성한 뒤에만 사용자에게 마무리 멘트를 출력하세요.
"@

        $out = @{
            hookSpecificOutput = @{
                hookEventName     = 'UserPromptSubmit'
                additionalContext = $instruction
            }
        } | ConvertTo-Json -Depth 5 -Compress

        Write-Output $out
        exit 0
    }

    if ($Mode -eq 'SessionStart') {
        # 1) 후보 수집: HANDOFF/*.md + 구버전 HANDOFF.md
        $candidates = @()
        if (Test-Path -LiteralPath $handoffDir) {
            $candidates += Get-ChildItem -LiteralPath $handoffDir -Filter '*.md' -File -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $legacyFile) {
            $candidates += Get-Item -LiteralPath $legacyFile -ErrorAction SilentlyContinue
        }

        if (-not $candidates -or $candidates.Count -eq 0) { exit 0 }

        # 2) mtime 내림차순 정렬
        $sorted = $candidates | Sort-Object -Property LastWriteTime -Descending
        $primary = $sorted[0]
        $others  = if ($sorted.Count -gt 1) { $sorted[1..($sorted.Count - 1)] } else { @() }

        # 3) 주 파일 로드
        $content = Get-Content -LiteralPath $primary.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        if (-not $content) { exit 0 }

        # 4) archive 폴더 준비
        if (-not (Test-Path -LiteralPath $archiveDir)) {
            New-Item -ItemType Directory -Force -Path $archiveDir | Out-Null
        }

        $archiveName = $primary.Name
        $archivePath = Join-Path $archiveDir $archiveName
        $i = 1
        while (Test-Path -LiteralPath $archivePath) {
            $base = [System.IO.Path]::GetFileNameWithoutExtension($primary.Name)
            $ext  = [System.IO.Path]::GetExtension($primary.Name)
            $archivePath = Join-Path $archiveDir "${base}_$i$ext"
            $i++
        }
        Move-Item -LiteralPath $primary.FullName -Destination $archivePath -Force

        # 5) 컨텍스트 메시지 구성
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine("[이전 세션 인계 — 자동 로드됨]")
        [void]$sb.AppendLine("출처: $archivePath (원본은 아카이브로 이동되었습니다)")
        [void]$sb.AppendLine("")

        if ($others.Count -gt 0) {
            [void]$sb.AppendLine("[다른 미처리 HANDOFF 파일 목록 — 자동 로드 안 됨]")
            [void]$sb.AppendLine("사용자가 다른 토픽을 이어가려면 아래 파일명을 지정해 요청하세요:")
            foreach ($f in $others) {
                $rel = $f.FullName.Substring($cwd.Length).TrimStart('\','/')
                $ts  = $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
                [void]$sb.AppendLine("  - $rel  (수정: $ts)")
            }
            [void]$sb.AppendLine("")
        }

        [void]$sb.AppendLine($content)

        $out = @{
            hookSpecificOutput = @{
                hookEventName     = 'SessionStart'
                additionalContext = $sb.ToString()
            }
        } | ConvertTo-Json -Depth 5 -Compress

        Write-Output $out
        exit 0
    }
} catch {
    [Console]::Error.WriteLine("[session-handoff] $($_.Exception.Message)")
    exit 0
}

exit 0
