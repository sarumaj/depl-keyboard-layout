# Builds the Windows installer from dist/depl.klc (scripts/build.py): MSKLC's
# kbdutool compiles the layout's DLL for each architecture, Inno Setup packs them
# with the installer (windows/depl.iss) into dist/depl-setup.exe.
#
# MSKLC itself is not installed: its MSI is only unpacked (msiexec /a), as its
# GUI cannot run in CI and only kbdutool is needed. Needs 7-Zip and Inno Setup
# (both on GitHub's Windows runners; Inno Setup is installed with Chocolatey
# where it is missing).
#
# Usage: scripts/build-windows.ps1 [-Dist dist]
param([string]$Dist = "dist")

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Dist = Resolve-Path (Join-Path $Root $Dist)
$Version = (Get-Content (Join-Path $Dist "VERSION")).Trim()
$Work = Join-Path ([System.IO.Path]::GetTempPath()) "depl-windows"
Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
New-Item -ItemType Directory $Work | Out-Null

# MSKLC 1.4, the last version (2010); its checksum guards against a changed download.
$MsklcUrl = "https://download.microsoft.com/download/6/f/5/6f5ce43a-e892-4fd1-b9a6-1a0cbb64e6e2/MSKLC.exe"
$MsklcSha256 = "cd12a6b08066133dc4ad71bdcaccf1492e3d9a1de93cf84b7b2824309f0d7255"

$exe = Join-Path $Work "MSKLC.exe"
Invoke-WebRequest $MsklcUrl -OutFile $exe
$hash = (Get-FileHash $exe -Algorithm SHA256).Hash.ToLower()
if ($hash -ne $MsklcSha256) { throw "MSKLC.exe has the checksum $hash, not $MsklcSha256" }
& 7z x -y "-o$Work\msklc-setup" $exe | Out-Null
if ($LASTEXITCODE -ne 0) { throw "7z could not unpack MSKLC.exe" }
$msi = Get-ChildItem -Recurse "$Work\msklc-setup" -Filter MSKLC.msi | Select-Object -First 1
$admin = Start-Process msiexec -Wait -PassThru -ArgumentList `
    "/a", "`"$($msi.FullName)`"", "/qn", "TARGETDIR=`"$Work\msklc`""
if ($admin.ExitCode -ne 0) { throw "msiexec /a MSKLC.msi failed: $($admin.ExitCode)" }
$kbdutool = (Get-ChildItem -Recurse "$Work\msklc" -Filter kbdutool.exe | Select-Object -First 1).FullName
if (-not $kbdutool) { throw "kbdutool.exe is not in MSKLC.msi" }

# One DLL per architecture: i386 for 32-bit Windows, amd64 for 64-bit Windows
# and wow64 for its 32-bit programs. kbdutool cannot build one for ARM64.
$Windows = Join-Path $Dist "windows"
Remove-Item -Recurse -Force $Windows -ErrorAction SilentlyContinue
$build = Join-Path $Work "build"
New-Item -ItemType Directory $build | Out-Null
Copy-Item (Join-Path $Dist "depl.klc") $build
Push-Location $build
try {
    foreach ($arch in @(@("-x", "i386"), @("-m", "amd64"), @("-o", "wow64"))) {
        & $kbdutool -u $arch[0] depl.klc
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path depl.dll)) {
            throw "kbdutool could not build the $($arch[1]) DLL"
        }
        New-Item -ItemType Directory (Join-Path $Windows $arch[1]) | Out-Null
        Move-Item depl.dll (Join-Path $Windows $arch[1])
    }
} finally {
    Pop-Location
}

$iscc = (Get-Command iscc -ErrorAction SilentlyContinue).Source
if (-not $iscc) { $iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" }
if (-not (Test-Path $iscc)) {
    choco install innosetup -y --no-progress | Out-Null
    $iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
}
& $iscc /Q "/DVersion=$Version" "/DDist=$Dist" (Join-Path $Root "windows\depl.iss")
if ($LASTEXITCODE -ne 0) { throw "Inno Setup could not build the installer" }
Write-Output "Built $Dist\depl-setup.exe ($Version)"
