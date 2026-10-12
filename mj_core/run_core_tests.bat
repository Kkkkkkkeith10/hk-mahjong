@echo off
rem One-click mj_core test run; full output lands in test_output.log so the
rem result can be read back without touching the console window.
cd /d "%~dp0"
echo === dart pub get === > test_output.log
call dart pub get >> test_output.log 2>&1
echo === dart test === >> test_output.log
call dart test -r expanded >> test_output.log 2>&1
echo === exit %ERRORLEVEL% === >> test_output.log
exit
