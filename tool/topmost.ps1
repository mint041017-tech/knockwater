Start-Sleep -Seconds 9
$p = Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like '*叩水*' } | Select-Object -First 1
if ($p) {
  Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Win32Top {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
}
"@
  [Win32Top]::SetWindowPos($p.MainWindowHandle, [IntPtr]::new(-1), 30, 30, 430, 900, 0x0040) | Out-Null
  [Win32Top]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
}
