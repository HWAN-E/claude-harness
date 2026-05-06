@echo off
REM claude-harness 설치 — 더블클릭 진입점
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0install.ps1" %*
echo.
echo ==== install.cmd 종료 ====
pause
