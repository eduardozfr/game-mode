@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Manage.ps1" -Action Validate
if errorlevel 1 echo Operacao nao concluida. Verifique a mensagem de erro.
pause
