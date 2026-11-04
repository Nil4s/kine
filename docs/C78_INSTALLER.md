# C78: installing Kine like a real app (Windows)

Nick's question: can Kine be a real app with a setup wizard, or does only the repo with `pose.bat` / `pose.sh` work? Answer: it can. Kine is local only (not public); nothing here uploads anything.

## Build a new installer: one command

```
bash tools/build_installer.sh
```

Result: `exports/installer/Kine-Setup-<version>.exe` (version = `config/version` in `project.godot`; `exports/` is git-ignored).
Needs: Godot 4.7.2 with its export templates (`%APPDATA%/Godot/export_templates/4.7.2.stable`), Inno Setup 6 (`winget install JRSoftware.InnoSetup`), MinGW `objdump` (`C:/msys64/ucrt64/bin`), and the built DLLs in `native/bin` (see `native/CAD_BUILD.md`; Kine builds with `native_build.sh`).
Check it with `bash tests/c78_test.sh` (builds, silent-installs into a temp dir, boots, strips PATH, plants a missing DLL, uninstalls).

What the script does: (1) exports preset **Windows Installer** (binary tokens, embedded pck, icon, `Kine.exe` + `Kine.console.exe`); (2) `tools/installer/stage_dist.py` walks the imports of `kine_native` and `kine_cad` with `objdump -p` (transitively) and copies exactly those DLLs beside the exe, failing the build if an import is neither found nor a Windows system DLL; (3) copies `licences/` and writes `THIRD_PARTY_NOTICES.txt` from the notice list plus the DLLs actually staged; (4) `tools/installer/kine.iss` builds the wizard.

## What the installer does
- Per-user by default (no admin): `%LOCALAPPDATA%\Programs\Kine`; the standard Inno dialog offers "all users".
- Wizard pages: licence (`LICENSE`), third-party notices, folder, Start-menu group, optional desktop shortcut, install, "Start Kine".
- Start-menu entries: Kine, Uninstall Kine. Uninstaller from Add/Remove Programs.
- **User data is never touched.** Kine's scenes, settings and autosaves are in Godot's user folder (`%APPDATA%/Godot/app_userdata/...`). The `.iss` has no `[UninstallDelete]`, and the test checks the APPDATA tree is byte-identical across uninstall.
- Silent: `Kine-Setup-0.4.0.exe /VERYSILENT /CURRENTUSER /DIR=C:\somewhere` and `unins000.exe /VERYSILENT`.
- **No file association.** Kine has no "open a file given on the command line" path (its pack files are opened from inside the app), so an association would launch Kine and then ignore the file. Not adding a lie; revisit when Kine opens `argv[1]`.

## How the exported exe finds its native code
The `.gdext` configs are deliberately not `.gdextension` (see `scripts/native_ext.gd`), so Godot's exporter does not see them as extensions. The preset therefore (a) includes `native/*.gdext` in the pck and (b) the DLLs are staged flat beside `Kine.exe`. `NativeExt.ensure` (small additive change) accepts a DLL that is not on disk at `res://native/bin/` when the same file name sits beside the exe in an exported build, and Godot's loader does the same lookup. Windows then resolves the OpenCASCADE and MinGW runtime DLLs from the application folder. Nothing relies on PATH (the test runs with PATH = System32).

## OpenCASCADE licensing (LGPL 2.1 + exception)
The `libTK*.dll` files stay separate, unmodified, replaceable DLLs in the install folder; the licence texts ship in `licences/` and `THIRD_PARTY_NOTICES.txt` says how to swap them and where the source is (tag V8_0_1). Details: `THIRD_PARTY_NOTICES.md` section 2.

## Python features: gated, not bundled (decision)
Every place Kine shells out to Python: video import (`main.gd` `_import_video`), several cameras (`_multicam_start`), webcam puppet (`live_puppet.gd`), reference image match (`ref_image_ui.gd`), Make it physical (`make_physical.gd`), hit simulation (`hit_physics.gd`), QR pictures (`qr_share.gd`), footage check (only after a video import), AI move maker (`gen_move.gd`, needs a local ComfyUI, already reports "not set up").
**Choice: the base installer does not bundle Python. Each feature says "<feature> needs the video add-on ..." (`scripts/video_addon.gd`, `VideoAddon.gate`) and does nothing else.** Run from source (editor or `pose.bat`) nothing changes: `gate()` is always empty there.
Reasons: (1) size and risk: embeddable Python + mediapipe + opencv + numpy + protobuf + their transitive wheels is several hundred MB, more than the whole app, for features most users do not use on day one; (2) the tools themselves (`tools/*.py`) are read through `res://` paths that point into the pck in an exported build, so they would need shipping loose as well, with the paths changed in about ten call sites; (3) mediapipe/numpy/opencv licences (Apache-2.0, BSD-3, Apache-2.0/MIT) allow bundling, so this is a size/maintenance decision, not a legal one; (4) a clear message is honest, a half-working bundled interpreter is not.
The add-on layout the gate already looks for: `addon/python/python.exe` beside `Kine.exe` (with `tools/*.py` beside it). When the add-on is built, the interpreter fields (`video_python` etc.) need pointing at it; that is the follow-up.

## Numbers (11-04, Windows 11, a loaded machine: 13 Godot processes from other lanes ran during every measurement)
- Installer: `Kine-Setup-0.4.0.exe` 77.6 MB (LZMA2 max). Installed: 213 MB (`Kine.exe` 145 MB with the pck inside, 32 DLLs 65.7 MB: kine_native, kine_cad, 29 OpenCASCADE `libTK*`, 3 MinGW runtime).
- First window of the installed app: 3.2 s. Headless smoke (boot, open Part, build a box through KineCAD, mesh it): 15.5 s to 31.9 s in the engine clock across runs depending on the load of the other lanes; the whole process under `timeout 60` exits 0 in 20 to 56 s (once 60 s was hit on a heavily loaded run and the bar failed, then passed on rerun; the bar was not moved).
- A clean `quit()` of the headless build takes about 90 s (unloading the whole script graph), so `tools/c78_smoke.gd` ends the process with `OS.kill` right after printing its verdict. Worth a separate look: it is the same cost whenever the app is closed.
- Dependency walk (`stage_dist.py`) found 32 DLLs; the build fails if an import is neither staged nor in System32.

## Things the export taught us (kept, not hidden)
- Exported builds ignore `-s`; the smoke test starts through the user arg `--c78-smoke` handled in `main.gd` (5 lines) and `tools/c78_smoke.gd`.
- Imported PNGs are not in the pck as raw files, so `Image.load_from_file(res://...)` fails in an exported build (the Easy tip clips did this at every boot). `scripts/pck_image.gd` (`PckImage.load_res`) reads the imported lossless texture instead; the two tip loaders use it.
- The release export needs `debug/export_console_wrapper=2` to produce `Kine.console.exe` (the preset's `1` is debug only).
- Under Git Bash, Inno's `/D...` and `/VERYSILENT` switches are mangled as paths unless `MSYS_NO_PATHCONV=1` is set (the scripts do).
- Not done: the video add-on itself, a file association (see above), code signing (Windows SmartScreen will warn on an unsigned installer), Godot's own About / Licences screen text for the notices.
