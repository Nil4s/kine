# Installer, update check, crash upload (L16)

Kine is not public. Nothing here talks to a real server: every address is empty by default and both features are OFF.

## Opt-in settings (`user://online.cfg`, `scripts/online_opt.gd`)
- `[update] enabled=false feed_url=""`. Palette: "Setting: update check on/off", "File: check for updates now". Feed JSON:
  `{"latest":"0.5.0","notes":"..","url":".."}` or `{"releases":[{"version":..}]}`. A newer semver gives a status-line note, never a dialog.
- `[crash] enabled=false endpoint=""`. Palette: "File > Send crash report...". The dialog shows the exact redacted payload
  (paths, user name, e-mail removed); it sends only after Send, only when enabled and an endpoint is set.

## Clean-machine install test
`bash tools/build_installer.sh` then either
- `powershell -File tools\installer\sandbox\run_in_sandbox.ps1` (Windows Sandbox, no network), or
- `powershell -File tools\installer\sandbox\kine_install_test.ps1 -InstallDir <scratch folder>` (any Windows box; NOT a clean machine).
It installs silently, checks the files and that the notices name every DLL, launches `Kine.console.exe --headless -- --install-smoke`
(exit 0 + `INSTALL_SMOKE OK`), uninstalls silently and checks the files are gone.

## Notices
`tools/installer/dll_licence.py` maps every shipped DLL to a licence; `make_notices.py` stops on an unknown DLL; `check_notices.py`
(run by `build_installer.sh`, and by `tests/install_test.gd`) fails when a staged DLL is not listed with its licence.

## Code signing (not done: no certificate exists)
Needs: an Authenticode code-signing certificate (OV, or EV to skip the SmartScreen warm-up) held in an HSM or cloud signer;
`signtool sign /fd SHA256 /tr <timestamp server> /td SHA256` on `Kine.exe`, `Kine.console.exe`, the staged DLLs we build
(`kine_native`, `kine_cad`) and the Inno `Kine-Setup-*.exe` (Inno `SignTool=` directive plus `SignedUninstaller=yes`).
Then re-run the clean-machine test on the signed build and check `Get-AuthenticodeSignature`.
