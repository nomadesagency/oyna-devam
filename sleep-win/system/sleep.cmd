@echo off
rem Shortcut: sleep.cmd prompt "task..." ^| on ^| off ^| status ^| watch ^| doctor ^| reset
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sleep.ps1" %*
