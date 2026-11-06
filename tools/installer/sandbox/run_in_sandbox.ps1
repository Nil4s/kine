# L16: run the clean-machine install test in Windows Sandbox (Windows 10/11 Pro, feature "Windows Sandbox" enabled, then a reboot).
#   powershell -File tools\installer\sandbox\run_in_sandbox.ps1      (after bash tools/build_installer.sh made exports\installer\Kine-Setup-*.exe)
# Exit 0 = INSTALL_TEST PASS, 1 = FAIL, 2 = Windows Sandbox is not available here.
$repo = Resolve-Path (Join-Path $PSScriptRoot "..\..\..")
$sb = Join-Path $env:SystemRoot "System32\WindowsSandbox.exe"
if (-not (Test-Path $sb)) { Write-Host "Windows Sandbox is not enabled on this machine (enable it: Turn Windows features on or off > Windows Sandbox, then reboot)."; exit 2 }
$inst = Join-Path $repo "exports\installer"
if (-not (Get-ChildItem $inst -Filter "Kine-Setup-*.exe" -ErrorAction SilentlyContinue)) { Write-Host "no installer in $inst: run bash tools/build_installer.sh first"; exit 1 }
$res = Join-Path $env:TEMP ("kine_install_result_" + [guid]::NewGuid().ToString("N")); New-Item -ItemType Directory -Path $res | Out-Null
$wsb = (Get-Content (Join-Path $PSScriptRoot "kine_install_test.wsb") -Raw).Replace("__INSTALLER_DIR__", $inst).Replace("__SCRIPT_DIR__", $PSScriptRoot).Replace("__RESULT_DIR__", $res)
$file = Join-Path $res "run.wsb"; Set-Content -Path $file -Value $wsb -Encoding UTF8
Start-Process -FilePath $sb -ArgumentList "`"$file`""
$r = Join-Path $res "result.txt"
for ($i = 0; $i -lt 1800 -and -not (Test-Path $r); $i++) { Start-Sleep -Seconds 1 }
if (-not (Test-Path $r)) { Write-Host "no result after 30 minutes"; exit 1 }
$line = Get-Content $r -Raw; Write-Host $line
Get-Process -Name WindowsSandbox* -ErrorAction SilentlyContinue | Out-Null
if ($line -match "INSTALL_TEST PASS") { exit 0 } else { exit 1 }
