@echo off
title Optimiseur PC
echo.
echo   Lancement de l'Optimiseur PC...
echo   Windows va demander l'autorisation administrateur : repondez "Oui".
echo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0OptimiseurPC.ps1"
if errorlevel 1 pause
