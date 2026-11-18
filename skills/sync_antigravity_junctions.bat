@echo off
rem Junction deployment is retired. Reconcile ordinary verified copies instead.
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0..\scripts\sync-skills.ps1" -Mode Apply
exit /b %errorlevel%
