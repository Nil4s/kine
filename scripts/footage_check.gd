## FOOTAGE PRE-CHECK (C14, complaint #560: "phone footage has to be clean, or the result is poor"). Before a video is tracked, the first
## seconds of the FILE are read (tools/footage_precheck.py: brightness, the height of what moves, camera jitter) and judged here in words,
## with a short filming guide. It reads a video file only and never opens a camera. Advice only: the video is tracked either way.
class_name FootageCheck
extends RefCounted

const DARK := 70.0        # mean grey (0..255) under this: too dark
const BRIGHT := 200.0     # over this: washed out
const SUBJECT_MIN := 0.35 # what moves is under this share of the frame height: the person is too small
const SHAKE_MAX := 0.5    # camera jitter, percent of the frame width per frame, over this: shaky
const GUIDE := "Filming guide: good light on the person, one person in the shot, the whole body in frame filling most of the height, the phone propped or on a tripod, 3 to 10 seconds."


## stats = the script's JSON ({"ok", "why", "brightness", "subject", "shake"}). {"ok": nothing to warn about, "findings": [words], "text": status line}
static func judge(stats: Dictionary) -> Dictionary:
	if not bool(stats.get("ok", false)):
		return {"ok": true, "findings": [], "text": "", "unread": true}
	var f := []
	var b := float(stats.get("brightness", 128.0))
	if b < DARK:
		f.append("too dark (brightness %d of 255): film in more light" % roundi(b))
	elif b > BRIGHT:
		f.append("washed out (brightness %d of 255): avoid direct sun on the lens" % roundi(b))
	var s := float(stats.get("subject", 1.0))
	if s < SUBJECT_MIN:
		f.append("the person fills only %d%% of the frame height: stand closer or zoom in" % roundi(s * 100.0))
	var sh := float(stats.get("shake", 0.0))
	if sh > SHAKE_MAX:
		f.append("the camera shakes (%.1f%% of the width per frame): prop the phone or use a tripod" % sh)
	if f.is_empty():
		return {"ok": true, "findings": f, "text": ""}
	return {"ok": false, "findings": f, "text": "Footage check: " + "; ".join(f) + ". " + GUIDE}


## reads the first seconds of a video FILE through the script. {} when it could not run
static func stats_of(path: String, python := "python", secs := 3.0) -> Dictionary:
	var out := []
	var tool := ProjectSettings.globalize_path("res://tools/footage_precheck.py")
	var code := OS.execute(python, PackedStringArray([tool, path, str(secs)]), out, false)
	if code != 0 or out.is_empty():
		return {}
	var v: Variant = JSON.parse_string(String(out[0]).strip_edges().get_slice("\n", 0))
	return v if v is Dictionary else {}


## the whole thing for a file
static func check(path: String, python := "python") -> Dictionary:
	return judge(stats_of(path, python))
