@echo off
rem Static analysis for the app (log read back by the agent).
cd /d "%~dp0"
echo === analyze start === > analyze.log
call flutter analyze --no-pub >> analyze.log 2>&1
echo exit code %ERRORLEVEL% >> analyze.log
exit
