## godot --headless --path . -s tests/video_pixels_test.gd     (round 45, GATES AA1)
## REAL PIXELS. walk_bat as the app renders it (yaw -40, 30 fps), tracked by MediaPipe PoseLandmarker (heavy), kept as
## refs/video/walk_bat_track.json, imported by VideoImport. Against walk_bat itself (the truth), per knee over the clip:
##   1 the knee's bend: mean absolute error <= 8.2 deg (2 x people's 4.10, Russo et al. 2026, PMID 41977932: one phone +
##     MediaPipe against a sensor system, 27 adults), and its range of motion within 9.1 deg (2 x their 4.55)
##   REPORTED: the ankle (their ankle agreement was poor), the walk's travel (no published bar)
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
	var P := VideoImport.load_file("res://refs/video/walk_bat_track.json")
	ok(P["ok"], "0 the track reads: %d frames" % P.get("frames", []).size())
	var fitted := VideoImport.solve(B, P["frames"])
	for sd in ["_l", "_r"]:
		var c: String = "calf" + sd
		var err := 0.0
		var lo := [INF, INF]
		var hi := [-INF, -INF]
		var aerr := 0.0
		for i in fitted.size():
			var t: float = fitted[i]["t"]
			S.apply(B, minf(t, S.length()))
			var truth: float = absf((B.ang[c] as Vector3).x)
			var tf: float = (B.ang["foot" + sd] as Vector3).x
			var got: float = absf((fitted[i]["ang"][c] as Vector3).x)
			err += absf(got - truth)
			aerr += absf((fitted[i]["ang"]["foot" + sd] as Vector3).x - tf)
			lo = [minf(lo[0], truth), minf(lo[1], got)]
			hi = [maxf(hi[0], truth), maxf(hi[1], got)]
		var n := float(fitted.size())
		var rom_t: float = hi[0] - lo[0]
		var rom_g: float = hi[1] - lo[1]
		ok(err / n <= 8.2 and absf(rom_g - rom_t) <= 9.1, "1%s knee %s: mean abs error %.1f deg (bar 8.2); range of motion %.1f vs %.1f (bar within 9.1)" % [sd, sd, err / n, rom_g, rom_t])
		print("   REPORTED ankle%s mean abs error %.1f deg" % [sd, aerr / n])
	var o0: Vector3 = fitted[0]["offset"]
	var o1: Vector3 = fitted[-1]["offset"]
	S.apply(B, 0.0)
	var p0: Vector3 = B.P["pelvis"]
	S.apply(B, S.length())
	var p1: Vector3 = B.P["pelvis"]
	print("   REPORTED travel: video %.2f m, walk_bat %.2f m" % [Vector2(o1.x - o0.x, o1.z - o0.z).length(), Vector2(p1.x - p0.x, p1.z - p0.z).length()])
	print("VIDEO PIXELS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
