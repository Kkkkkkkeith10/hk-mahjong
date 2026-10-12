Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinCap {
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern IntPtr FindWindow(string cls, string title);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
$proc = Get-Process | Where-Object { $_.MainWindowTitle -like '*mj_app*' } | Select-Object -First 1
if (-not $proc) {
  Get-Process | Where-Object { $_.MainWindowTitle } | ForEach-Object { Write-Output ("title: [" + $_.ProcessName + "] " + $_.MainWindowTitle) }
  Write-Output "window not found"; exit 1
}
$h = $proc.MainWindowHandle
Write-Output ("proc " + $proc.ProcessName)
Write-Output ("hwnd " + $h)
for ($i = 1; $i -le 6; $i++) {
  Start-Sleep -Seconds 15
  $r = New-Object WinCap+RECT
  [WinCap]::GetClientRect($h, [ref]$r) | Out-Null
  $w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
  Write-Output ("client " + $w + "x" + $ht)
  $bmp = New-Object System.Drawing.Bitmap($w, $ht)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $hdc = $g.GetHdc()
  $ok = [WinCap]::PrintWindow($h, $hdc, 3)  # PW_CLIENTONLY | PW_RENDERFULLCONTENT
  $g.ReleaseHdc($hdc)
  $file = ('win-shot-{0}.png' -f $i)
  $bmp.Save($file)
  $g.Dispose(); $bmp.Dispose()
  Write-Output ("saved " + $file + " ok=" + $ok)
}
