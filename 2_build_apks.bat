@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ========================================================
echo Tamreedy - Build Android APKs (Patient + Nurse)
echo ========================================================
echo.
echo Building Patient and Nurse APKs (Pilot and Release)...
echo Please wait, this may take a few minutes...
echo.
powershell -ExecutionPolicy Bypass -File scripts\build-apks.ps1 -Target all
echo.
echo Done! APK files are located in:
echo %~dp0deploy\apk\
echo.
pause
