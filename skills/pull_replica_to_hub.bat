@echo off
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0scripts\rescue_local_edits.ps1"
exit /b %errorlevel%
