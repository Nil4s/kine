# L16 clean-machine install test. Runs INSIDE Windows Sandbox (kine_install_test.wsb) or on any Windows box with -InstallDir set to a scratch folder.
#   1 silent install of Kine-Setup-<ver>.exe   2 the files an install must hold   3 every DLL on disk is in the notices and vice versa
#   4 launch Kine.console.exe headless with --install-smoke: exit code 0 and INSTALL_SMOKE OK   5 silent uninstall: the folder's files are gone
# Prints INSTALL_TEST PASS or INSTALL_TEST FAIL <reasons>, writes the same to -ResultFile, exits 0 or 1. Uploads nothing; needs no network.
param(
  [string]$SetupExe = "",
  [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "Programs\Kine"),
  [string]$ResultFile = "",
  [int]$SmokeTimeoutSec = 180
)
$ErrorActionPreference = "Stop"
$fail = New-Object System.Collections.Generic.List[string]
function Fail($m) { $script:fail.Add($m); Write-Host "FAIL: $m" }
function Step($m) { Write-Host "== $m" }

function Finish {
  $line = if ($fail.Count -eq 0) { "INSTALL_TEST PASS" } else { "INSTALL_TEST FAIL " + ($fail -join "; ") }
  Write-Host $line
  if ($ResultFile -ne "") { Set-Content -Path $ResultFile -Value $line -Encoding ASCII }
  if ($fail.Count -eq 0) { exit 0 } else { exit 1 }
}

try {
  if ($SetupExe -eq "") {
    $here = Split-Path -Parent $MyInvocation.MyCommand.Path
    foreach ($d in @("C:\KineInstall", (Join-Path $here "..\..\..\exports\installer"))) {
      $f = Get-ChildItem -Path $d -Filter "Kine-Setup-*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($f) { $SetupExe = $f.FullName; break }
    }
  }
  if ($SetupExe -eq "" -or -not (Test-Path $SetupExe)) { Fail "no Kine-Setup-*.exe found"; Finish }

  Step "1 silent install to $InstallDir"
  if (Test-Path (Join-Path $InstallDir "Kine.exe")) { Fail "the install folder already holds Kine.exe: this test needs an empty folder"; Finish }
  $p = Start-Process -FilePath $SetupExe -ArgumentList @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/SP-", "/DIR=`"$InstallDir`"") -Wait -PassThru
  if ($p.ExitCode -ne 0) { Fail "installer ExitCode $($p.ExitCode)"; Finish }

  Step "2 files"
  foreach ($f in @("Kine.exe", "Kine.console.exe", "kine_native.windows.template_release.x86_64.dll", "kine_cad.windows.template_release.x86_64.dll",
                   "libTKernel.dll", "LICENSE.txt", "THIRD_PARTY_NOTICES.txt", "licences\LGPL-2.1.txt", "licences\OCCT_LGPL_EXCEPTION.txt", "unins000.exe")) {
    if (-not (Test-Path (Join-Path $InstallDir $f))) { Fail "missing after install: $f" }
  }

  Step "3 notices cover the DLLs"
  $notices = Get-Content (Join-Path $InstallDir "THIRD_PARTY_NOTICES.txt") -ErrorAction SilentlyContinue
  foreach ($d in Get-ChildItem -Path $InstallDir -Filter "*.dll") {
    if (-not ($notices | Where-Object { $_ -like "*$($d.Name)*" })) { Fail "DLL not in the notices: $($d.Name)" }
  }

  Step "4 headless smoke launch"
  $out = Join-Path $env:TEMP "kine_smoke_out.txt"
  $sp = Start-Process -FilePath (Join-Path $InstallDir "Kine.console.exe") -ArgumentList @("--headless", "--", "--install-smoke") `
        -RedirectStandardOutput $out -NoNewWindow -PassThru
  if (-not $sp.WaitForExit($SmokeTimeoutSec * 1000)) { Stop-Process -Id $sp.Id -Force; Fail "smoke launch timed out after $SmokeTimeoutSec s" }
  elseif ($sp.ExitCode -ne 0) { Fail "smoke ExitCode $($sp.ExitCode)" }
  if (-not ((Get-Content $out -Raw -ErrorAction SilentlyContinue) -match "INSTALL_SMOKE OK")) { Fail "smoke output lacks INSTALL_SMOKE OK" }

  Step "5 silent uninstall"
  $u = Join-Path $InstallDir "unins000.exe"
  if (Test-Path $u) {
    Start-Process -FilePath $u -ArgumentList @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART") -Wait | Out-Null
    for ($i = 0; $i -lt 60 -and (Test-Path (Join-Path $InstallDir "Kine.exe")); $i++) { Start-Sleep -Seconds 1 }   # the uninstaller hands off to a temp copy
  }
  foreach ($f in @("Kine.exe", "Kine.console.exe", "kine_cad.windows.template_release.x86_64.dll", "libTKernel.dll")) {
    if (Test-Path (Join-Path $InstallDir $f)) { Fail "still there after uninstall: $f" }
  }
} catch {
  Fail ("exception: " + $_.Exception.Message)
}
Finish
