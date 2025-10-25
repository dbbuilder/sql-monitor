@echo off
REM Deploy SQL Server Monitor to Test Environment
REM Run this from Windows Command Prompt or PowerShell

cd /d %~dp0
powershell.exe -ExecutionPolicy Bypass -File "deploy-test-environment-simple.ps1"
pause
