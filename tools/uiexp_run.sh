#!/bin/bash
# uiexp_run.sh <script> : run a tools/ or tests/ script with its own APPDATA (never Nick's)
G=/c/Users/Nick/Tools/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe
AD=/c/Temp/claude/wt_appdata/uiexp.run.$$; rm -rf "$AD"; mkdir -p "$AD"
APPDATA=$(cygpath -w "$AD") timeout 900 $G --position -30000,-30000 --audio-driver Dummy --path . -s "$1" > /tmp/uiexp_run.log 2>&1
rm -rf "$AD"
