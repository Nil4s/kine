#!/bin/bash
# uiexp_audit.sh [tag]: the Expert-screen audit with its own APPDATA (never Nick's)
G=/c/Users/Nick/Tools/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe
AD=/c/Temp/claude/wt_appdata/uiexp.audit.$$; rm -rf "$AD"; mkdir -p "$AD"
UE_TAG=${1:-run} APPDATA=$(cygpath -w "$AD") timeout 900 $G --position -30000,-30000 --audio-driver Dummy --path . -s tools/uiexp_audit.gd 2>&1 | grep -v "^$"
rm -rf "$AD"
