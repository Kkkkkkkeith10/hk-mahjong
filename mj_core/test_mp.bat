@echo off
rem End-to-end smoke test of the deployed `mj` edge function (see bin\test_mp.dart).
rem Output lands in test_mp.log; last line "SMOKE OK" = pass.
cd /d "%~dp0"
echo === test_mp start === > test_mp.log
dart bin\test_mp.dart >> test_mp.log 2>&1
echo exit code %ERRORLEVEL% >> test_mp.log
exit
