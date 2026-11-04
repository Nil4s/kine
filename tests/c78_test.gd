extends SceneTree
## godot --headless --path . -s tests/c78_test.gd     (C78 unit bars; the installer itself is tests/c78_test.sh)
## Bars, written before the numbers:
##   1 SOURCE UNCHANGED  run from source, VideoAddon.gate() is "" for every feature and installed() is true
##   2 GATE SENTENCE     with force_missing the gate says "<feature> needs the video add-on ..." (control: bar 1 fails if the gate ignored force_missing)
##   3 GATED FEATURES    with force_missing: QrShare, HitPhysics.simulate and MakePhysical.begin refuse with that sentence and start no process
##   4 TIPS IMAGE        PckImage.load_res gives the same size as the disk read for a tips sheet; a missing path gives an empty image or null, not a crash
##   5 NATIVE LOOKUP     NativeExt.ensure still answers for a missing class with false and does not throw
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func _init() -> void:
	ok(VideoAddon.gate("tracking a video") == "" and VideoAddon.installed(), "1 from source the gate is open")
	VideoAddon.force_missing = true
	var g := VideoAddon.gate("tracking a video")
	ok(g.begins_with("tracking a video") and g.contains("video add-on") and not VideoAddon.installed(), "2 forced: the gate says the video add-on sentence: " + g.left(60))
	var r := QrShare._run("python", PackedStringArray(["x"]))
	ok(not bool(r.get("ok", true)) and String(r.get("why", "")).contains("video add-on"), "3a QrShare refuses with the sentence")
	var h := HitPhysics.simulate({}, "c78")
	ok(not bool(h.get("ok", true)) and String(h.get("why", "")).contains("video add-on"), "3b HitPhysics.simulate refuses with the sentence")
	var mp := MakePhysical.new()
	var msg := mp.begin(null, null)
	ok(msg.contains("video add-on") and mp.pid < 0, "3c MakePhysical.begin refuses and starts nothing")
	VideoAddon.force_missing = false
	var p := "res://assets/tips/easy/blend.png"
	var a := PckImage.load_res(p)
	var b := Image.load_from_file(ProjectSettings.globalize_path(p))
	ok(a != null and not a.is_empty() and a.get_size() == b.get_size(), "4 PckImage reads the sheet: %s vs disk %s" % [a.get_size() if a != null else "null", b.get_size()])
	ok(not NativeExt.ensure("no_such_cfg", "NoSuchClass"), "5 NativeExt.ensure(missing) is false")
	print("c78: %d fail" % fails)
	quit(1 if fails > 0 else 0)
