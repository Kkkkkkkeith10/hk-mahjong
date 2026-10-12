@echo off
cd /d "%~dp0"
echo === font copy === > fontcopy.log
copy /y C:\Windows\Fonts\msjh.ttc msjh.ttc >> fontcopy.log 2>&1
copy /y C:\Windows\Fonts\msjhbd.ttc msjhbd.ttc >> fontcopy.log 2>&1
dir *.ttc >> fontcopy.log 2>&1
exit
