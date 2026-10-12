@echo off
cd /d "%~dp0"
echo === build start === > build_release.log
if not exist env.json (echo Missing env.json - copy env.example.json and fill it in & exit /b 1)
call flutter build appbundle --release --dart-define-from-file=env.json >> build_release.log 2>&1
echo --- appbundle exit %ERRORLEVEL% --- >> build_release.log
dir build\app\outputs\bundle\release >> build_release.log 2>&1
echo === done === >> build_release.log
exit
