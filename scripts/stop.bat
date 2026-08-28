@echo off

echo ========================================
echo   Slowlight Stop
echo ========================================

tasklist /FI "IMAGENAME eq slowlight-server.exe" 2>nul | find /I "slowlight-server.exe" >nul
if errorlevel 1 (
    echo No Slowlight Server process running
) else (
    echo Stopping slowlight-server.exe ...
    taskkill /F /IM slowlight-server.exe >nul 2>&1
    echo Done
)

echo.
pause
