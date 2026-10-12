@echo off
cd /d "%~dp0"
echo === platform_gen start === > platform_gen.log
call flutter create --platforms=android,ios --org com.keithlau --project-name mj_app . >> platform_gen.log 2>&1
echo --- flutter create exit %ERRORLEVEL% --- >> platform_gen.log
call flutter doctor -v >> platform_gen.log 2>&1
echo --- doctor exit %ERRORLEVEL% --- >> platform_gen.log
where keytool >> platform_gen.log 2>&1
if exist "%LOCALAPPDATA%\Android\Sdk" echo SDK at %LOCALAPPDATA%\Android\Sdk >> platform_gen.log
dir /b "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" >> platform_gen.log 2>&1
echo === done === >> platform_gen.log
exit
