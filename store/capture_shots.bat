@echo off
cd /d "%~dp0"
echo === capture start === > capshot.log
powershell -NoProfile -ExecutionPolicy Bypass -Command "Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing; for($i=1;$i -le 8;$i++){ Start-Sleep -Seconds 15; $b=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds; $bmp=New-Object System.Drawing.Bitmap($b.Width,$b.Height); $g=[System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen(0,0,0,0,$bmp.Size); $file=('raw-shot-{0}.png' -f $i); $bmp.Save($file); $g.Dispose(); $bmp.Dispose(); Write-Output ('saved ' + $file) }" >> capshot.log 2>&1
echo === done === >> capshot.log
exit
