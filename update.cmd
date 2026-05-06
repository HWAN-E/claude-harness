@echo off
REM claude-harness 업데이트 — 더블클릭 진입점
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0update.ps1" %*
echo.
echo ==== update.cmd 종료 ====
pause
