@echo off
rem Lime Image file association. Keep this file pure ASCII:
rem cmd misparses non-ASCII lines under chcp 65001, the menu lives in assoc\setup.ps1.
setlocal
cd /d "%~dp0"
if not exist "%~dp0assoc\setup.ps1" (
    echo [ERROR] missing %~dp0assoc\setup.ps1
    pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0assoc\setup.ps1" %*
exit /b %ERRORLEVEL%