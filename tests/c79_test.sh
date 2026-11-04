#!/usr/bin/env bash
# C79 SHUTDOWN TEST.   bash tests/c79_test.sh     (SKIP_EXPORT=1 reuses exports/c79/Kine.exe)
# Bars (written and committed before any number was read):
#   S1 EXPORTED  Kine.console.exe --headless -- --c78-smoke prints C78_SMOKE_OK, then quit() -> process exit takes < 5000 ms
#                (wall clock, from the line "quit() called"), exit code 0, and nothing kills the process (the smoke has no OS.kill)
#   S2 SOURCE    the same through the editor binary on the project folder (control: source run), same bar
#   S3 CONTROL   the clock can fail: a 6000 ms bar is never < the measured time of a run with a planted 6 s sleep in the harness
#                (checked on the timing function itself: elapsed of "sleep 6" is >= 5000)
#   S4 PHASES    every run prints each phase line (quit() called, main tree_exiting, root_exits_first/last exit_tree) so a miss can be split
# Every run uses its own temp APPDATA (never Nick's) and a 200 s watchdog (timeout on the PID this test started).
set -u
cd "$(dirname "$0")/.."
REPO="$PWD"
G=/c/Users/Nick/Tools/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe
W=/c/Temp/claude/c79_$$; mkdir -p "$W/appdata"
FAILS=0
ok() { if [ "$1" = 0 ]; then echo "ok   $2"; else echo "FAIL $2"; FAILS=$((FAILS+1)); fi; }
WIN() { cygpath -w "$1"; }
now() { date +%s%N; }

run() {   # $1 = label, rest = command ; stamps each output line with the wall clock; sets RC, EXIT_MS (quit() called -> process exit)
  local lab=$1; shift
  local out="$W/$lab.txt"; : > "$out"
  ( APPDATA="$(WIN "$W/appdata")" LOCALAPPDATA="$(WIN "$W/appdata")" /usr/bin/timeout 200 "$@" 2>&1; echo "RC=$?" ) |
    while IFS= read -r l; do echo "$(now) $l" >> "$out"; done
  local end=$(now)
  RC=$(sed -n 's/^[0-9]* RC=//p' "$out" | tail -1)
  local q=$(grep " C79_PHASE quit() called" "$out" | head -1 | cut -d' ' -f1)
  if [ -n "$q" ]; then EXIT_MS=$(( ($(grep " RC=" "$out" | cut -d' ' -f1) - q) / 1000000 )); else EXIT_MS=-1; fi
}
phases() {   # print the phase table of one run: wall ms from quit() called
  local out="$W/$1.txt"; local q=$(grep " C79_PHASE quit() called" "$out" | head -1 | cut -d' ' -f1)
  [ -n "$q" ] || return
  grep -E " C79_PHASE | RC=" "$out" | while read -r t rest; do printf "   +%6d ms  %s\n" $(( (t - q) / 1000000 )) "$rest"; done
}
check() {  # $1 label  $2 text
  local out="$W/$1.txt"
  [ "$RC" = 0 ] && [ "$EXIT_MS" -ge 0 ] && [ "$EXIT_MS" -lt 5000 ] && grep -q "C78_SMOKE_OK" "$out" && ! grep -q "OS.kill" "tools/c78_smoke.gd"
  ok $? "$2 (exit $RC, quit() to exit ${EXIT_MS} ms, bar < 5000)"
  phases "$1"
}

# S1 exported
EXP="$REPO/exports/c79"
if [ -z "${SKIP_EXPORT:-}" ]; then
  rm -rf "$EXP"; mkdir -p "$EXP"
  /usr/bin/timeout 900 "$G" --headless --path . --export-release "Windows Installer" "$EXP/Kine.exe" > "$W/export.log" 2>&1
  cp native/bin/*.dll "$EXP/"
fi
run exported "$EXP/Kine.console.exe" --headless -- --c78-smoke
check exported "S1 exported smoke quits by itself"
# S2 source
run source "$G" --headless --path . -- --c78-smoke
check source "S2 source run (control run)"
# S3 control: the clock really measures
t0=$(now); sleep 6; el=$(( ($(now) - t0) / 1000000 ))
[ "$el" -ge 5000 ]; ok $? "S3 control: a 6 s wait reads $el ms and would fail the 5000 ms bar"
# S4 phases
n=0; for l in exported source; do for p in "quit() called" "main tree_exiting" "root_exits_first exit_tree" "root_exits_last exit_tree"; do grep -q "C79_PHASE $p" "$W/$l.txt" || n=$((n+1)); done; done
[ $n = 0 ]; ok $? "S4 all phase lines present in both runs (missing $n)"
echo "work dir: $W"
[ $FAILS = 0 ] && echo "C79 PASS" || echo "C79 FAIL ($FAILS)"
exit $FAILS
