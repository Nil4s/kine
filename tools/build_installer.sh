#!/usr/bin/env bash
# C78: build the Kine installer, ONE command, local only (nothing is uploaded).   bash tools/build_installer.sh
# -> exports/installer/Kine-Setup-<version>.exe   (version = config/version in project.godot)
# Needs: Godot 4.7.2 + its export templates, Inno Setup 6, MinGW objdump (C:/msys64/ucrt64/bin), the built DLLs in native/bin.
# Env: GODOT, ISCC, KINE_NATIVE_BIN (default native/bin), KINE_MINGW_BIN, KINE_OCCT.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="$PWD"
GODOT="${GODOT:-/c/Users/Nick/Tools/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe}"
ISCC="${ISCC:-/c/Users/Nick/AppData/Local/Programs/Inno Setup 6/ISCC.exe}"
NATIVE="${KINE_NATIVE_BIN:-$REPO/native/bin}"
VER="$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)"
[ -n "$VER" ] || { echo "no config/version in project.godot"; exit 1; }
DIST="$REPO/exports/installer/dist"
rm -rf "$DIST"; mkdir -p "$DIST"
echo "== 1/4 export Kine.exe ($VER)"
[ -d .godot ] || "$GODOT" --headless --path . --editor --quit >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Windows Installer" "$DIST/Kine.exe" 2>&1 | tail -5
[ -f "$DIST/Kine.exe" ] && [ -f "$DIST/Kine.console.exe" ] || { echo "export failed: Kine.exe / Kine.console.exe missing"; exit 1; }
echo "== 2/4 stage native DLLs (dependency walk)"
python tools/installer/stage_dist.py "$NATIVE" "$DIST" --manifest "$DIST/dlls.tsv"
echo "== 3/4 licences and notices"
cp LICENSE "$DIST/LICENSE.txt"; mkdir -p "$DIST/licences"; cp licences/* "$DIST/licences/"
python tools/installer/make_notices.py "$REPO" "$DIST/dlls.tsv" "$DIST/THIRD_PARTY_NOTICES.txt"
rm -f "$DIST/dlls.tsv"
echo "== 4/4 Inno Setup"
"$ISCC" /Qp "/DAppVersion=$VER" "/DDistDir=$(cygpath -w "$DIST")" "/DRepoDir=$(cygpath -w "$REPO")" "/DOutDir=$(cygpath -w "$REPO/exports/installer")" tools/installer/kine.iss
ls -l "exports/installer/Kine-Setup-$VER.exe"
