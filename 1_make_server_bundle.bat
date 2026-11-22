@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo Preparing the server bundle, please wait...
powershell -ExecutionPolicy Bypass -File scripts\make-deploy-bundle.ps1
echo.
echo Done. Upload this file to the server:
echo %~dp0deploy\tamreedy-server.tar.gz
echo.
pause
