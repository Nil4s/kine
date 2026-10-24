## godot --headless --path . -s tools/trunk_measure.gd [-- out.txt]     (dev: the TRUNK LEAN measurement, Nick 10-23)
## Per frame (60 fps) of each clip: the trunk's pitch / roll (pelvis -> neck_01 against vertical, in the hips' frame: + =
## forward / toward his left) and the spine's summed bend / side (spine_01..03). The per-frame table goes to the file named
## after "--" (default user://trunk_measure.txt); stdout gets one summary line per clip (max back, max forward, max roll).
## Clips: TextBlocking.build for the typed kicks and punches, templates/*.json, scenes/combo3.json and walk_bat.json.
extends SceneTree

const FPS := 60.0
const TYPED := ["front kick", "roundhouse", "side kick", "jab", "cross", "hook"]


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	var out_path := "user://trunk_measure.txt"
	var ua := OS.get_cmdline_user_args()
	if ua.size() > 0:
		out_path = ua[0]
	var fo := FileAccess.open(out_path, FileAccess.WRITE)
	var a0 := TrunkLean.angles(B)
	print("rest pose: pitch %.1f roll %.1f bend %.1f side %.1f" % [a0["pitch"], a0["roll"], a0["bend"], a0["side"]])
	var clips := []
	for ph in TYPED:
		var t0 := Time.get_ticks_msec()
		var bb := TextBlocking.build(ph, B)
		if not bb.get("ok", false):
			print("%s: not built (%s)" % [ph, bb.get("error", "?")])
			continue
		clips.append(["typed '%s'" % ph, bb["scene"]])
		print("  (built '%s' in %.0f s)" % [ph, (Time.get_ticks_msec() - t0) / 1000.0])
	var files := []
	for f in DirAccess.get_files_at("res://templates"):
		if String(f).ends_with(".json"):
			files.append("res://templates/" + f)
	files += ["res://scenes/combo3.json", "res://scenes/walk_bat.json"]
	for p in files:
		var S := Scene.new()
		S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(p)))
		clips.append([p.get_file(), S])
	for c in clips:
		var S: Scene = c[1]
		var n := int(ceil(S.length() * FPS)) + 1
		var mx := {"back": 0.0, "back_t": 0.0, "fwd": -INF, "fwd_t": 0.0, "roll": 0.0, "roll_t": 0.0, "bend_lo": INF, "bend_hi": -INF, "side": 0.0}
		var mn_pitch := INF
		fo.store_line("# %s  (%d frames)  t  pitch  roll  bend  side" % [c[0], n])
		for f in n:
			var t := f / FPS
			S.apply(B, t)
			var a := TrunkLean.angles(B)
			fo.store_line("%.3f %.1f %.1f %.1f %.1f" % [t, a["pitch"], a["roll"], a["bend"], a["side"]])
			if a["pitch"] < mn_pitch:
				mn_pitch = a["pitch"]
				mx["back_t"] = t
			if a["pitch"] > mx["fwd"]:
				mx["fwd"] = a["pitch"]
				mx["fwd_t"] = t
			if absf(a["roll"]) > absf(mx["roll"]):
				mx["roll"] = a["roll"]
				mx["roll_t"] = t
			mx["bend_lo"] = minf(mx["bend_lo"], a["bend"])
			mx["bend_hi"] = maxf(mx["bend_hi"], a["bend"])
			if absf(a["side"]) > absf(mx["side"]):
				mx["side"] = a["side"]
		var r := MoveRecognizer.of_scene(S, B)
		print("%-24s %-14s pitch %6.1f (%.2fs) .. %6.1f (%.2fs)  roll %6.1f (%.2fs)  spine bend %5.1f..%5.1f side %5.1f" % [
			c[0], r.get("class", "?"), mn_pitch, mx["back_t"], mx["fwd"], mx["fwd_t"], mx["roll"], mx["roll_t"], mx["bend_lo"], mx["bend_hi"], mx["side"]])
	fo.close()
	quit(0)
