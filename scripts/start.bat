@echo off

set SCRIPT_DIR=%~dp0
set SERVER_DIR=%SCRIPT_DIR%..\server

cd /d "%SERVER_DIR%"
if errorlevel 1 (
    echo [ERROR] Cannot find server directory
    pause
    exit /b 1
)

if not exist "slowlight-server.exe" (
    echo [ERROR] slowlight-server.exe not found, run build.bat first
    pause
    exit /b 1
)

REM Load .env file
if exist ".env" (
    for /f "usebackq tokens=1,* delims==" %%a in (".env") do (
        set "%%a=%%b"
    )
    echo [OK] Loaded .env
)

echo Starting Slowlight Server... (Ctrl+C to stop)
slowlight-server.exe
pause
