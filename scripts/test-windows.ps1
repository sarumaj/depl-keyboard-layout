# Tests the Windows installer on a throwaway Windows (the CI's runner): installs
# dist/depl-setup.exe silently, checks that Windows loads the layout and types
# the Polish letters with it, then uninstalls it and checks that nothing is left.
#
# Usage: scripts/test-windows.ps1 [-Dist dist]
param([string]$Dist = "dist")

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Dist = Resolve-Path (Join-Path $Root $Dist)
$Layouts = "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layouts"

function Find-Layout {
    Get-ChildItem $Layouts | Where-Object { $_.GetValue("Layout File") -eq "depl.dll" }
}

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class Keyboard {
    [DllImport("user32.dll")] static extern IntPtr LoadKeyboardLayout(string id, uint flags);
    [DllImport("user32.dll")] static extern bool UnloadKeyboardLayout(IntPtr hkl);
    [DllImport("user32.dll")] static extern int ToUnicodeEx(uint vk, uint scan, byte[] state,
        StringBuilder buf, int size, uint flags, IntPtr hkl);
    [DllImport("user32.dll")] static extern uint MapVirtualKeyEx(uint code, uint type, IntPtr hkl);
    // What the key of this scan code types with Shift and AltGr (Ctrl+Alt) as given.
    public static string Type(string klid, uint scan, bool shift, bool altGr) {
        IntPtr hkl = LoadKeyboardLayout(klid, 0);
        if (hkl == IntPtr.Zero) throw new Exception("Windows does not load " + klid);
        uint vk = MapVirtualKeyEx(scan, 1, hkl);  // MAPVK_VSC_TO_VK
        byte[] state = new byte[256];
        if (shift) { state[0x10] = 0x80; }
        if (altGr) { state[0x11] = 0x80; state[0x12] = 0x80; }
        StringBuilder buf = new StringBuilder(8);
        int n = ToUnicodeEx(vk, scan, state, buf, buf.Capacity, 4, hkl);  // 4: no state change
        return n > 0 ? buf.ToString(0, n) : "";
    }
}
"@

$setup = Start-Process (Join-Path $Dist "depl-setup.exe") -Wait -PassThru -ArgumentList `
    "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/LOG=$Dist\install.log"
if ($setup.ExitCode -ne 0) { throw "The installer failed: $($setup.ExitCode) (install.log)" }
$key = Find-Layout
if (-not $key) { throw "The installer registered no layout with depl.dll" }
$klid = $key.PSChildName
Write-Output "Registered as $klid, Layout Id $($key.GetValue('Layout Id'))"
foreach ($dir in @("$env:WINDIR\System32", "$env:WINDIR\SysWOW64")) {
    if (-not (Test-Path "$dir\depl.dll")) { throw "depl.dll is not in $dir" }
}

# Scan codes of the letters' keys; the Polish letter is AltGr's, its capital AltGr+Shift's.
$cases = @(
    @(0x1e, "a", "ą", "Ą"), @(0x2e, "c", "ć", "Ć"), @(0x12, "e", "ę", "Ę"),
    @(0x26, "l", "ł", "Ł"), @(0x31, "n", "ń", "Ń"), @(0x18, "o", "ó", "Ó"),
    @(0x1f, "s", "ś", "Ś"), @(0x2d, "x", "ź", "Ź"), @(0x15, "z", "ż", "Ż"),
    @(0x2c, "y", "»", "›"), @(0x10, "q", "@", "Ω"), @(0x05, "4", "€", "¤")
)
$errors = @()
foreach ($c in $cases) {
    $typed = @(
        [Keyboard]::Type($klid, $c[0], $false, $false),
        [Keyboard]::Type($klid, $c[0], $false, $true),
        [Keyboard]::Type($klid, $c[0], $true, $true)
    )
    if (($typed -join " ") -ne ($c[1..3] -join " ")) {
        $errors += "scan code $('{0:x2}' -f $c[0]): $($typed -join ' ') instead of $($c[1..3] -join ' ')"
    }
}
if ($errors) { throw "The layout types wrongly:`n$($errors -join "`n")" }
Write-Output "The layout types $($cases.Count) keys as it should."

$tips = (Get-WinUserLanguageList | ForEach-Object { $_.InputMethodTips }) -join ", "
if ($tips -notmatch "0407:$klid") { throw "The layout is not among the keyboards: $tips" }

$uninstaller = Get-ChildItem "${env:ProgramFiles}\depl-keyboard-layout", "${env:ProgramFiles(x86)}\depl-keyboard-layout" `
    -Filter "unins*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $uninstaller) { throw "No uninstaller was installed" }
$uninstall = Start-Process $uninstaller.FullName -Wait -PassThru -ArgumentList "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART"
if ($uninstall.ExitCode -ne 0) { throw "The uninstaller failed: $($uninstall.ExitCode)" }
if (Find-Layout) { throw "The uninstaller left the layout registered" }
$tips = (Get-WinUserLanguageList | ForEach-Object { $_.InputMethodTips }) -join ", "
if ($tips -match "0407:$klid") { throw "The uninstaller left the layout among the keyboards: $tips" }
Write-Output "Installed, typed with and uninstalled."
