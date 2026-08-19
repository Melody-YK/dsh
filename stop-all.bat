@echo off
title DSH Shutdown
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0stop-all.ps1"
echo.
echo DSH and forwarder stopped. The GUI page will disconnect (normal).
pause
