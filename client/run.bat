@echo off
REM Run Flutter client with local dart-defines (SERVER_URL etc.) by default.
REM Usage: run.bat -d emulator-5554 [extra flutter run args...]
cd /d "%~dp0"

if not exist ".dart_defines.json" (
    copy /Y ".dart_defines.json.example" ".dart_defines.json" >nul
    echo [OK] Created .dart_defines.json from example. Edit SERVER_URL if needed.
)

flutter run --dart-define-from-file=.dart_defines.json %*
