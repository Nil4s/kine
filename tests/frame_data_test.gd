## godot --headless --path . -s tests/frame_data_test.gd     (ROADMAP 12: frame data, scripts/frame_data.gd)
## Bars, written before measuring, on scenes/combo3.json (read only; the export goes to user://):
##  (1) startup + active + recovery = the frame count (60 fps), and there is an active part.
##  (2) every active frame's tip speed is above FrameData.TIP_SPEED and its direction is toward the target (+Z).
##  (3) every active frame has two hitbox capsules, and the weapon's axis (knob to tip, every 2 cm) lies inside them.
##  (4) the export round-trips: write JSON, read it back, the counts and every hitbox's ends match (1e-5 m).
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	B.ground()
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	var fd := FrameData.analyze(S, B, 60)
	var n := int(fd["n"])
	var sa := int(fd["startup"]) + int(fd["active"]) + int(fd["recovery"])
	print("combo3: %d frames at 60 fps, startup %d, active %d, recovery %d, gaps %d, striker %s" % [n, fd["startup"], fd["active"], fd["recovery"], fd["gaps"], fd["striker"]])
	ok(n > 0 and sa == n, "(1) startup + active + recovery = %d frames (%d)" % [n, sa])
	ok(int(fd["active"]) > 0, "(1) the scene has an active part (first frame %d, last %d)" % [fd["first"], fd["last"]])

	# (2) every active frame: tip speed above the threshold, moving toward +Z
	var fast := 0
	var toward := 0
	var nact := 0
	for fr in fd["frames"]:
		if not fr["active"]:
			continue
		nact += 1
		if float(fr["speed"]) > FrameData.TIP_SPEED:
			fast += 1
	toward = 1 if (fd["dir"] as Vector3).z > 0.99 else 0
	ok(nact > 0 and fast == nact and toward == 1, "(2) %d of %d active frames over %.1f m/s, toward +Z" % [fast, nact, FrameData.TIP_SPEED])

	# (3) the weapon's axis inside the hitbox capsules at every active frame
	var inside := 0
	var worst := 0.0
	var seen := 0
	for fr in fd["frames"]:
		if not fr["active"]:
			continue
		seen += 1
		S.apply(B, float(fr["f"]) / 60.0)
		var hb: Array = fr["hitboxes"]
		var all_in := hb.size() == 2
		var u := 0.0
		while u <= B.wep_len + 1e-6:
			var p := B.wep_point(u)
			var best := INF
			for c in hb:
				best = minf(best, Body.seg_seg(p, p, c["a"], c["b"]) - float(c["r"]))
			worst = maxf(worst, best)
			if best > 1e-5:
				all_in = false
			u += 0.02
		if all_in:
			inside += 1
	ok(seen > 0 and inside == seen, "(3) hitboxes (2 per frame) contain the weapon axis at %d of %d active frames (worst %.6f m outside)" % [inside, seen, worst])

	# (4) export round-trip through a JSON file in user://
	var path := "user://frame_data_test.json"
	ok(FrameData.write_json(fd, path) == OK, "(4) JSON written to user://")
	var back: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var same := int(back["startup"]) == int(fd["startup"]) and int(back["active"]) == int(fd["active"]) and int(back["recovery"]) == int(fd["recovery"]) and int(back["fps"]) == 60
	ok(same and (back["frames"] as Array).size() == n, "(4) counts round-trip: startup %d, active %d, recovery %d, %d frames" % [back["startup"], back["active"], back["recovery"], n])
	var err := 0.0
	var hb_total := 0
	for i in n:
		var fr: Dictionary = fd["frames"][i]
		var bf: Dictionary = back["frames"][i]
		var a_hb: Array = fr["hitboxes"]
		var b_hb: Array = bf["hitboxes"]
		if a_hb.size() != b_hb.size():
			err = INF
		for k in mini(a_hb.size(), b_hb.size()):
			hb_total += 1
			var ca: Dictionary = a_hb[k]
			var cb: Dictionary = b_hb[k]
			err = maxf(err, (ca["a"] as Vector3).distance_to(Vector3(cb["a"][0], cb["a"][1], cb["a"][2])))
			err = maxf(err, (ca["b"] as Vector3).distance_to(Vector3(cb["b"][0], cb["b"][1], cb["b"][2])))
			err = maxf(err, absf(float(ca["r"]) - float(cb["r"])))
	ok(hb_total > 0 and err < 1e-5, "(4) %d hitbox capsules read back within 1e-5 m (worst %.6f m)" % [hb_total, err])
	var wire := FrameData.wire([[(fd["frames"][int(fd["first"])]["hitboxes"]), Color(1, 0, 0)]])
	ok(wire.get_surface_count() == 1, "wire mesh built for the first active frame")
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
