#!/usr/bin/env bash
# C78 INSTALLER TEST.   bash tests/c78_test.sh      (SKIP_BUILD=1 reuses exports/installer/Kine-Setup-*.exe)
# Bars (written and committed before any number was read):
#   B1 BUILD      tools/build_installer.sh exits 0 and Kine-Setup-<project version>.exe exists
#   B2 INSTALL    Setup /VERYSILENT /CURRENTUSER /DIR=<temp> exits 0; Kine.exe, Kine.console.exe, unins000.exe, libTKBRep.dll and
#                 kine_cad.windows.template_release.x86_64.dll are in <temp>
#   B3 SMOKE      the installed Kine.console.exe --headless -- --c78-smoke (temp APPDATA, never Nick's) exits 0 in < 60 s,
#                 prints C78_SMOKE_OK (Part opened, box built through KineCAD, volume 2, meshed), and prints no "Can't open dynamic library",
#                 no "Failed to load extension", no "No such file" / "missing extension" line
#   B4 PATH       the same run with PATH = System32 only still passes (the DLLs are bundled, not found on PATH)
#   B5 CONTROL    a COPY of the install with libTKBRep.dll deleted: the same smoke run must FAIL (non-zero exit or no C78_SMOKE_OK)
#   B6 GATE       the installed build says the video add-on sentence for the Python features (C78_GATE contains "video add-on")
#   B7 UNINSTALL  unins000.exe /VERYSILENT removes Kine.exe and the program dir; the temp APPDATA tree (marker file + what the runs wrote) is untouched
#   B8 ORIGIN     Kine.exe is under 400 MB and its install under 600 MB (sanity: nothing unexpected got bundled)
set -u
cd "$(dirname "$0")/.."
REPO="$PWD"
W=/c/Temp/claude/c78_$$
mkdir -p "$W/appdata/Godot/app_userdata/Kine" "$W/inst"
echo keep > "$W/appdata/Godot/app_userdata/Kine/marker.txt"
FAILS=0
ok() { if [ "$1" = 0 ]; then echo "ok   $2"; else echo "FAIL $2"; FAILS=$((FAILS+1)); fi; }
VER="$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)"
SETUP="$REPO/exports/installer/Kine-Setup-$VER.exe"
WIN() { cygpath -w "$1"; }

# B1
if [ -z "${SKIP_BUILD:-}" ]; then
  /usr/bin/timeout 1500 bash tools/build_installer.sh > "$W/build.log" 2>&1; rc=$?
else rc=0; fi
[ $rc = 0 ] && [ -f "$SETUP" ]; ok $? "B1 installer builds ($SETUP, $(stat -c %s "$SETUP" 2>/dev/null) bytes)"

# B2
MSYS_NO_PATHCONV=1 /usr/bin/timeout 300 "$SETUP" /VERYSILENT /CURRENTUSER /SUPPRESSMSGBOXES /NORESTART "/DIR=$(WIN "$W/inst")" "/LOG=$(WIN "$W/setup.log")"; rc=$?
[ $rc = 0 ] && [ -f "$W/inst/Kine.exe" ] && [ -f "$W/inst/Kine.console.exe" ] && [ -f "$W/inst/unins000.exe" ] && [ -f "$W/inst/libTKBRep.dll" ] && [ -f "$W/inst/kine_cad.windows.template_release.x86_64.dll" ]
ok $? "B2 silent install into a temp dir (exit $rc)"

smoke() {  # $1 = install dir, $2 = PATH value, $3 = out file ; prints exit code and ms
  local t0=$(date +%s%N)
  APPDATA="$(WIN "$W/appdata")" LOCALAPPDATA="$(WIN "$W/appdata")" /usr/bin/env PATH="$2" /usr/bin/timeout 60 "$1/Kine.console.exe" --headless -- --c78-smoke > "$3" 2>&1
  local rc=$?
  SMOKE_MS=$(( ($(date +%s%N) - t0) / 1000000 ))
  return $rc
}
# B3
smoke "$W/inst" "$PATH" "$W/s1.txt"; rc=$?
[ $rc = 0 ] && [ "$SMOKE_MS" -lt 60000 ] && grep -q "C78_SMOKE_OK" "$W/s1.txt" && ! grep -qiE "Can't open dynamic library|Failed to load extension|No such file|missing extension" "$W/s1.txt"
ok $? "B3 installed smoke boots, Part + box + mesh (exit $rc, ${SMOKE_MS} ms, $(grep C78_SMOKE_OK "$W/s1.txt"))"
# B4
smoke "$W/inst" "/c/Windows/System32" "$W/s2.txt"; rc=$?
[ $rc = 0 ] && grep -q "C78_SMOKE_OK" "$W/s2.txt" && ! grep -qiE "Can't open dynamic library|Failed to load extension|No such file|missing extension" "$W/s2.txt"
ok $? "B4 smoke with PATH=System32 only (exit $rc, ${SMOKE_MS} ms)"
# B5
cp -r "$W/inst" "$W/inst_broken"; rm -f "$W/inst_broken/libTKBRep.dll"
smoke "$W/inst_broken" "/c/Windows/System32" "$W/s3.txt"; rc=$?
if [ $rc != 0 ] || ! grep -q "C78_SMOKE_OK" "$W/s3.txt"; then r=0; else r=1; fi
ok $r "B5 CONTROL: smoke FAILS without libTKBRep.dll (exit $rc)"
# B6
grep -q "C78_GATE=.*video add-on" "$W/s1.txt"; ok $? "B6 Python features say the video add-on sentence"
# B8 (before uninstall)
SZ=$(du -sm "$W/inst" | cut -f1); EX=$(( $(stat -c %s "$W/inst/Kine.exe") / 1048576 ))
[ "$EX" -lt 400 ] && [ "$SZ" -lt 600 ]; ok $? "B8 sizes: Kine.exe ${EX} MB, install ${SZ} MB"
# a run that timed out (the B5 control) may still be shutting down: wait until no process runs from under $W (read-only query, nothing is killed)
for i in $(seq 1 40); do
  n=$(powershell -NoProfile -Command "@(Get-CimInstance Win32_Process | Where-Object { \$_.ExecutablePath -like '$(cygpath -w "$W")*' }).Count" | tr -d '')
  [ "${n:-0}" = 0 ] && break; sleep 5
done
(cd "$W/appdata" && find . -type f | sort | xargs md5sum) > "$W/before.md5"
BEFORE=$(md5sum < "$W/before.md5")
# B7
MSYS_NO_PATHCONV=1 /usr/bin/timeout 300 "$W/inst/unins000.exe" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART; rc=$?
for i in 1 2 3 4 5 6 7 8 9 10; do [ ! -f "$W/inst/Kine.exe" ] && break; sleep 1; done   # the uninstaller finishes in a helper process
(cd "$W/appdata" && find . -type f | sort | xargs md5sum) > "$W/after.md5"
AFTER=$(md5sum < "$W/after.md5")
diff "$W/before.md5" "$W/after.md5" | head -5
[ ! -f "$W/inst/Kine.exe" ] && [ ! -f "$W/inst/libTKBRep.dll" ] && [ ! -d "$W/inst" -o -z "$(ls -A "$W/inst" 2>/dev/null)" ] && [ "$BEFORE" = "$AFTER" ] && [ -f "$W/appdata/Godot/app_userdata/Kine/marker.txt" ]
ok $? "B7 silent uninstall removes the program dir, APPDATA untouched (exit $rc)"
echo "work dir: $W"
[ $FAILS = 0 ] && echo "C78 PASS" || echo "C78 FAIL ($FAILS)"
exit $FAILS
