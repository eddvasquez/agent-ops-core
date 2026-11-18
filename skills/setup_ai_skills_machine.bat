@echo off
setlocal
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0..\scripts\sync-skills.ps1" -Mode Apply
set "SYNC_CODE=%errorlevel%"
if "%SYNC_CODE%"=="1" exit /b 1
if "%SYNC_CODE%"=="3" exit /b 3
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0..\scripts\manage-skills-watcher.ps1" -Action Enable
if errorlevel 1 exit /b 1
exit /b %SYNC_CODE%
