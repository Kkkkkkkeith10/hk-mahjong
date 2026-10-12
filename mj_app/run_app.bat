@echo off
rem One-click dev run: kill any running instance, then flutter run.
cd /d "%~dp0"
taskkill /IM mj_app.exe /F >nul 2>&1
rem Refresh tile art natively (fixes any corrupt/truncated PNGs)
xcopy /Y "%~dp0..\assets\tiles\*.png" "%~dp0..\mj_app\assets\tiles\" >nul
if exist env.json (flutter run -d windows --dart-define-from-file=env.json) else (echo Online play disabled: copy env.example.json to env.json & flutter run -d windows)
pause
