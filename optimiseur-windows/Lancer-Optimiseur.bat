@echo off
title Optimiseur PC
echo.
echo   Lancement de l'Optimiseur PC...  /  Starting PC Optimizer...  /  PC-Optimierer wird gestartet...
echo.
echo   FR : Windows va demander l'autorisation administrateur : repondez "Oui".
echo   EN : Windows will ask for administrator permission: answer "Yes".
echo   DE : Windows fragt nach Administratorrechten: antworten Sie mit "Ja".
echo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0OptimiseurPC.ps1"
if errorlevel 1 pause
