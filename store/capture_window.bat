@echo off
cd /d "%~dp0"
echo === wincap start === > wincap.log
powershell -NoProfile -ExecutionPolicy Bypass -File capture_window.ps1 >> wincap.log 2>&1
echo === done === >> wincap.log
exit
