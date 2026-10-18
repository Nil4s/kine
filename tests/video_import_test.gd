## godot --headless --path . -s tests/video_import_test.gd     (round 45, GATES AA0)
## VIDEO TO ANIMATION, ON A KNOWN ANSWER. walk_bat's 33 landmarks written exactly as tools/export_landmarks.gd writes
## them (MediaPipe's layout and axes, the hips at 0: no travel), read back by VideoImport and fitted:
##   1 the pose: every landmark of the fitted body within 1.5 cm of the original on average, 4 cm at worst
##   2 the knees and elbows: the hinge bend within 2 deg of the original on average
##   3 the travel: MediaPipe's hips never move; the rebuilt walk travels within 5 % of walk_bat's own distance
##   4 the floor: the lower sole within 1 cm of the floor in every frame
##   5 the scene: one card per frame plays the fitted angles back (0.01 deg) at the frame times
##   6 a bad file is refused with a sentence, never a crash
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/walk_bat.json")))
	var fps := 30.0
	var orig := []
	var frames := []
	for i in int(S.length() * fps) + 1:
		var t := minf(i / fps, S.length())
		S.apply(B, t)
		B.fk()
		var w := VideoImport.landmarks_of(B)
		var ang := {}
		for j in Body.BODY:
			ang[j] = B.ang[j]
		orig.append({"w": w, "pel": B.P["pelvis"], "ang": ang, "knee": [B.ang["calf_l"], B.ang["calf_r"], B.ang["lowerarm_l"], B.ang["lowerarm_r"]]})
		frames.append({"t": snappedf(t, 0.001), "world": w.map(func(p): return [p.x, -p.y, -p.z])})
	var P := VideoImport.parse(JSON.stringify({"fps": fps, "frames": frames}))
	ok(P["ok"] and P["frames"].size() == frames.size(), "0 the pose file reads: %d frames" % P.get("frames", []).size())
	var fitted := VideoImport.solve(B, P["frames"])
	# 1, 2 the pose
	var sum := 0.0
	var n := 0
	var worst := 0.0
	var worst_at := ""
	var hsum := 0.0
	var hn := 0
	for i in fitted.size():
		for j in fitted[i]["ang"]:
			B.ang[j] = fitted[i]["ang"][j]
		B.offset = fitted[i]["offset"]
		B.fk()
		var w := VideoImport.landmarks_of(B)
		for k in VideoImport.MAP:
			var d: float = (w[k] as Vector3).distance_to(orig[i]["w"][k])
			sum += d
			n += 1
			if d > worst:
				worst = d
				worst_at = "frame %d landmark %d (%s)" % [i, k, VideoImport.MAP[k][0]]
		for m in 4:
			var jn: String = ["calf_l", "calf_r", "lowerarm_l", "lowerarm_r"][m]
			hsum += absf(absf((B.ang[jn] as Vector3).x) - absf((orig[i]["knee"][m] as Vector3).x))
			hn += 1
	var mean := sum / maxf(1, n)
	ok(mean <= 0.015 and worst <= 0.04, "1 the fitted body's landmarks %.2f cm from the original on average, %.2f at worst (%s) (bar 1.5, 4)" % [mean * 100.0, worst * 100.0, worst_at])
	ok(hsum / maxf(1, hn) <= 2.0, "2 the knees' and elbows' bend %.2f deg from the original on average (bar 2)" % (hsum / maxf(1, hn)))
	# 3 the travel
	var o0: Vector3 = orig[0]["pel"]
	var o1: Vector3 = orig[-1]["pel"]
	var dist := Vector2(o1.x - o0.x, o1.z - o0.z).length()
	var f0: Vector3 = fitted[0]["offset"]
	var f1: Vector3 = fitted[-1]["offset"]
	var got := Vector2(f1.x - f0.x, f1.z - f0.z).length()
	ok(dist > 1.0 and absf(got - dist) <= 0.05 * dist, "3 the rebuilt walk travels %.3f m, walk_bat %.3f m (bar within 5 %%; the pose file's hips never move)" % [got, dist])
	# 4 the floor
	var fl := 0.0
	for i in fitted.size():
		for j in fitted[i]["ang"]:
			B.ang[j] = fitted[i]["ang"][j]
		B.offset = fitted[i]["offset"]
		B.fk()
		fl = maxf(fl, absf(B.sole_low()))
	ok(fl <= 0.01, "4 the lower sole's worst distance from the floor %.4f m (bar 0.01)" % fl)
	# 5 the scene
	var V := VideoImport.to_scene(B, fitted, fps)
	var sw := 0.0
	var sw_at := ""
	var vt := V.times()
	for i in fitted.size():
		V.apply(B, float(vt[i][1]))   # the card's own time (the frame times summed as moves)
		for j in fitted[i]["ang"]:
			# the angle numbers themselves (Quaternion.angle_to is acos of a dot near 1: float32 floors it at ~0.07 deg for
			# the SAME rotation, measured here on identical angles, the round 41 finding)
			var dv: Vector3 = (B.ang[j] as Vector3) - (fitted[i]["ang"][j] as Vector3)
			var dd := maxf(absf(dv.x), maxf(absf(dv.y), absf(dv.z)))
			if dd > sw:
				sw = dd
				sw_at = "card %d %s %s vs %s" % [i, j, B.ang[j], fitted[i]["ang"][j]]
	ok(V.cards.size() == fitted.size() and sw <= 0.01, "5 one card per frame (%d) plays the fit back: worst %.4f deg (bar 0.01) %s" % [V.cards.size(), sw, sw_at])
	# 6 refusals
	var r1 := VideoImport.parse("{}")
	var r2 := VideoImport.parse("not json")
	var r3 := VideoImport.parse(JSON.stringify({"frames": [frames[0]]}))
	ok(not r1["ok"] and not r2["ok"] and not r3["ok"] and String(r3["why"]).length() > 10, "6 bad files refused: %s | %s | %s" % [r1["why"], r2["why"], r3["why"]])
	print("VIDEO IMPORT TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
