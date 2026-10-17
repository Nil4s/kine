#!/bin/sh
# Poser on Linux / macOS (GATES PP1): finds Godot 4.7, in order: $POSER_GODOT; a godot/ folder beside this file
# (Godot_v4.7*, or Godot.app on macOS); Godot_v4.7* or godot on PATH; a godot.path file beside this file (one line).
# Arguments pass through. POSER_DRY=1: print the launch line only.
HERE=$(cd "$(dirname "$0")" && pwd)
GODOT=""
[ -n "$POSER_GODOT" ] && [ -e "$POSER_GODOT" ] && GODOT="$POSER_GODOT"
if [ -z "$GODOT" ]; then
	for f in "$HERE"/godot/Godot_v4.7* "$HERE"/godot/Godot.app/Contents/MacOS/Godot; do
		[ -e "$f" ] && [ ! -d "$f" ] && { GODOT="$f"; break; }
	done
fi
if [ -z "$GODOT" ]; then
	for d in $(echo "$PATH" | tr ':' ' '); do
		for f in "$d"/Godot_v4.7* "$d"/godot; do
			[ -e "$f" ] && [ ! -d "$f" ] && { GODOT="$f"; break 2; }
		done
	done
fi
if [ -z "$GODOT" ] && [ -f "$HERE/godot.path" ]; then
	p=$(head -n 1 "$HERE/godot.path" | tr -d '\r')
	[ -e "$p" ] && GODOT="$p"
fi
if [ -z "$GODOT" ]; then
	echo
	echo " Poser needs Godot 4.7, and it was not found."
	echo
	echo " Get it free from https://godotengine.org/download (the \"Godot Engine\" download, version 4.7), then either:"
	echo "   - put it in a folder named godot beside this file: $HERE/godot/"
	echo "   - or set POSER_GODOT to its full path"
	echo "   - or write that path on one line in: $HERE/godot.path"
	echo
	[ "$POSER_DRY" = "1" ] || { printf " Press Enter to close. "; read -r _; }
	exit 1
fi
if [ "$POSER_DRY" = "1" ]; then
	echo "LAUNCH \"$GODOT\" --path \"$HERE\" $*"
	exit 0
fi
exec "$GODOT" --path "$HERE" "$@"
