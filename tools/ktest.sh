#!/usr/bin/env bash
# ktest: a direct single-suite run with terse output (CH16 cost analysis, item 3).
# Usage from the worktree:  bash tools/ktest.sh ch16 [--window]
# Prints only FAIL bars, script errors and the suite summary; the full log is in C:/Temp/claude/direct/.
s=$1
G=/c/Users/Nick/Tools/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe
L=/c/Temp/claude/direct; mkdir -p "$L"
opts="--headless"
[ "$2" = "--window" ] && opts="--position -30000,-30000 --audio-driver Dummy"
# a fresh worktree has no class cache: import once or every class_name is "not declared"
[ -f .godot/global_script_class_cache.cfg ] || "$G" --headless --path . --import > "$L/_import.log" 2>&1
"$G" $opts --path . -s "tests/${s}_test.gd" > "$L/$s.log" 2>&1
e=$?
grep -E "^FAIL |SCRIPT ERROR|^[A-Za-z0-9_]+: (.*, )?[0-9]+ (ok|fail)" "$L/$s.log" | cut -c1-220 | head -30
echo "ktest $s exit $e (full log $L/$s.log)"
exit $e
