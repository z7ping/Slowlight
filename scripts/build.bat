@echo off

echo ========================================
echo   Slowlight Build
echo ========================================

set SCRIPT_DIR=%~dp0
set SERVER_DIR=%SCRIPT_DIR%..\server

cd /d "%SERVER_DIR%"
if errorlevel 1 (
    echo [ERROR] Cannot find server directory
    pause
    exit /b 1
)

echo Building slowlight-server.exe...
go build -o slowlight-server.exe ./cmd/

if errorlevel 1 (
    echo.
    echo Build FAILED
    pause
    exit /b 1
)

echo.
echo Build OK: server\slowlight-server.exe

echo.
pause
