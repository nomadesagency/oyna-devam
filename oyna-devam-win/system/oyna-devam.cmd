@echo off
rem Shortcut: oyna-devam.cmd prompt "task..." ^| on ^| off ^| status ^| watch ^| doctor ^| reset
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0oyna-devam.ps1" %*
