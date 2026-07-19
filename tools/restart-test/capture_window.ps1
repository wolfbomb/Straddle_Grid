# Capture the MT5 terminal main window to a PNG (PrintWindow — works even
# when the window is unfocused/behind others; window must exist and not be
# minimized for reliable pixels). Usage: capture_window.ps1 <out.png>
param([Parameter(Mandatory=$true)][string]$OutPath)

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Capture {
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int cmd);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

# Filter by exact install path, not bare process name: other unrelated MT5
# installs on this machine (e.g. D:\MT5_Live_Demo, D:\MT5_NAS100_v2) also run
# as "terminal64.exe" - a name-only match can silently screenshot a
# sibling project's window instead of ours (found 2026-07-19: captured a
# different EA's dashboard on NAS100 while 3 terminals were running at once).
$ourPath = "C:\Program Files\MetaTrader 5\terminal64.exe"
$ourPids = Get-CimInstance Win32_Process -Filter "Name='terminal64.exe'" |
           Where-Object { $_.ExecutablePath -eq $ourPath } |
           Select-Object -ExpandProperty ProcessId
$p = Get-Process -Id $ourPids -ErrorAction SilentlyContinue |
     Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if (-not $p) { Write-Error "no window found for our terminal64.exe ($ourPath)"; exit 1 }
$hwnd = $p.MainWindowHandle
[Win32Capture]::ShowWindow($hwnd, 9) | Out-Null   # SW_RESTORE in case minimized
Start-Sleep -Milliseconds 500

$rect = New-Object Win32Capture+RECT
[Win32Capture]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
$w = $rect.Right - $rect.Left; $h = $rect.Bottom - $rect.Top
if ($w -le 0 -or $h -le 0) { Write-Error "degenerate window rect ${w}x${h}"; exit 1 }

$bmp = New-Object System.Drawing.Bitmap $w, $h
$gfx = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $gfx.GetHdc()
$ok = [Win32Capture]::PrintWindow($hwnd, $hdc, 2)   # 2 = PW_RENDERFULLCONTENT
$gfx.ReleaseHdc($hdc)
$gfx.Dispose()
if (-not $ok) { Write-Error "PrintWindow failed"; $bmp.Dispose(); exit 1 }
$bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "saved ${w}x${h} -> $OutPath"
