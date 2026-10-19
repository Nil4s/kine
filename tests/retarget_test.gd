## godot --headless --path . -s tests/retarget_test.gd     (VideoRetarget: GMR's two-stage IK, arXiv:2510.02252, on a known answer)
## walk_bat and combo3 (READ ONLY) sampled at 30 fps as MediaPipe's 33 landmarks (hips at 0), then made a DIFFERENT PERSON:
## arms 1.1x and legs 0.95x (chained from the shoulder / hip), plus 1.5 cm gaussian noise on every axis of every landmark.
## The truth is our own skeleton's joints on that scene. OLD = VideoCleanup.smooth + VideoImport.solve (the import today),
## NEW = VideoRetarget.solve. BARS (stated before measuring), NEW only; OLD is printed beside it:
##   1 mean joint position error (22 joints, hips' midpoint to hips' midpoint) < 3 cm
##   2 end effectors (wrists, ankles, toe tips) mean error < 2 cm
##   3 frames with a joint angle outside the body's limits: 0
##   4 frames with a joint turning faster than VideoRetarget.vel_cap: 0
##   5 foot slide inside a TRUE contact (truth: sole < 2 cm up and its world speed < 0.05 m/s): mean over runs of the run's
##     largest drift of the foot's middle (horizontal) < 1 cm
##   6 a clip with hands goes to the old path unchanged (same angles)
extends SceneTree

var fails := 0
var NOISE := 0.015 if OS.get_environment("RT_NOISE") == "" else float(OS.get_environment("RT_NOISE"))


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _chain(w: Array, a: int, b: int, c: int, s: float, extra: Array) -> void:
	var nb: Vector3 = (w[a] as Vector3) + ((w[b] as Vector3) - (w[a] as Vector3)) * s
	var nc: Vector3 = nb + ((w[c] as Vector3) - (w[b] as Vector3)) * s
	var dc: Vector3 = nc - (w[c] as Vector3)
	for k in extra:
		w[k] = (w[k] as Vector3) + dc
	w[b] = nb
	w[c] = nc


func _truth(B: Body, name: String, fps: float) -> Dictionary:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/%s.json" % name)))
	var n := int(S.length() * fps) + 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261019
	var frames := []
	var pos := []
	var world := []
	for i in n:
		var t := minf(i / fps, S.length())
		S.apply(B, t)
		B.fk()
		var w := VideoImport.landmarks_of(B)
		var hm: Vector3 = ((B.P["thigh_l"] as Vector3) + (B.P["thigh_r"] as Vector3)) * 0.5
		var pj := {}
		for j in Body.BODY:
			pj[j] = (B.P[j] as Vector3) - hm
		pj["toe_l"] = (B.E["ball_l"] as Vector3) - hm
		pj["toe_r"] = (B.E["ball_r"] as Vector3) - hm
		pos.append(pj)
		var wm := {}
		for sd in ["_l", "_r"]:
			wm[sd] = (VideoImport.heel(B, sd) + (B.E["ball" + sd] as Vector3)) * 0.5
			wm["h" + sd] = B.foot_sole_low(sd)
		world.append(wm)
		for sd in ["_l", "_r"]:   # a different person
			_chain(w, VideoImport.SH[sd], VideoImport.EL[sd], VideoImport.WR[sd], 1.1, [])
			_chain(w, VideoImport.HIP[sd], VideoImport.KN[sd], VideoImport.AN[sd], 0.95, [VideoImport.TOE[sd], VideoImport.HEEL[sd]])
		var nz := []
		for p in w:
			nz.append((p as Vector3) + Vector3(rng.randfn(0.0, NOISE), rng.randfn(0.0, NOISE), rng.randfn(0.0, NOISE)))
		frames.append({"t": snappedf(t, 0.001), "w": nz})
	# the TRUE contacts, from the truth's own world: sole under 2 cm and the foot's middle slower than 0.05 m/s
	var runs := []
	for sd in ["_l", "_r"]:
		var down := []
		for k in n:
			var ok_k := false
			if k > 0 and k < n - 1:
				var v: float = ((world[k + 1][sd] as Vector3) - (world[k - 1][sd] as Vector3)).length() * fps / 2.0
				ok_k = float(world[k]["h" + sd]) < 0.02 and v < 0.05
			down.append(ok_k)
		var i := 0
		while i < n:
			if not down[i]:
				i += 1
				continue
			var a := i
			while i < n and down[i]:
				i += 1
			if i - a >= 4:
				runs.append([sd, a, i - 1])
	return {"frames": frames, "pos": pos, "runs": runs, "fps": fps, "world": world}


func _measure(B: Body, fitted: Array, T: Dictionary) -> Dictionary:
	var jsum := 0.0
	var jn := 0
	var esum := 0.0
	var en := 0
	var outl := 0
	var fast := 0
	var mids := []
	var prev := {}
	for i in fitted.size():
		var bad := false
		for j in fitted[i]["ang"]:
			var a: Vector3 = fitted[i]["ang"][j]
			B.ang[j] = a
			var L: Dictionary = B.lim[j]
			for k in [["bend", a.x], ["side", a.y], ["twist", a.z]]:
				var r: Vector2 = L[k[0]]
				if float(k[1]) < r.x - 1e-3 or float(k[1]) > r.y + 1e-3:
					bad = true
		if bad:
			outl += 1
		var sp := false
		if i > 0:
			var dt := float(fitted[i]["t"]) - float(fitted[i - 1]["t"])
			for j in Body.BODY:
				var q0 := B.compose(j, prev[j])
				var q1 := B.compose(j, fitted[i]["ang"][j])
				if rad_to_deg(q0.angle_to(q1)) / dt > VideoRetarget.vel_cap(j):
					sp = true
		if sp:
			fast += 1
		prev = fitted[i]["ang"]
		B.offset = fitted[i]["offset"]
		B.fk()
		var hm: Vector3 = ((B.P["thigh_l"] as Vector3) + (B.P["thigh_r"] as Vector3)) * 0.5
		var tp: Dictionary = T["pos"][i]
		for j in Body.BODY:
			var d := ((B.P[j] as Vector3) - hm).distance_to(tp[j])
			jsum += d
			jn += 1
			if j in ["hand_l", "hand_r", "foot_l", "foot_r"]:
				esum += d
				en += 1
		for sd in ["_l", "_r"]:
			esum += ((B.E["ball" + sd] as Vector3) - hm).distance_to(tp["toe" + sd])
			en += 1
		var m := {}
		for sd in ["_l", "_r"]:
			m[sd] = (VideoImport.heel(B, sd) + (B.E["ball" + sd] as Vector3)) * 0.5
		mids.append(m)
	var sl := slide(mids, T["runs"])
	var tl: Vector3 = (mids[-1]["_l"] as Vector3) - (mids[0]["_l"] as Vector3)
	return {"joint": jsum / jn, "ee": esum / en, "limits": outl, "vel": fast, "slide": sl[0], "slide_worst": sl[1], "runs": T["runs"].size(), "travel": Vector2(tl.x, tl.z).length()}


func slide(mids: Array, runs: Array) -> Array:
	var ss := 0.0
	var sw := 0.0
	for r in runs:
		var sd: String = r[0]
		var p0: Vector3 = mids[r[1]][sd]
		var worst := 0.0
		for k in range(r[1], r[2] + 1):
			var d: Vector3 = (mids[k][sd] as Vector3) - p0
			worst = maxf(worst, Vector2(d.x, d.z).length())
		ss += worst
		sw = maxf(sw, worst)
	return [ss / maxf(1, runs.size()), sw]


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	for name in ["walk_bat", "combo3"]:
		var T := _truth(B, name, 30.0)
		var smooth := VideoCleanup.smooth(T["frames"], 30.0)
		var t0 := Time.get_ticks_msec()
		var old := VideoImport.solve(B, smooth)
		var t1 := Time.get_ticks_msec()
		var rep := {}
		var nw := VideoRetarget.solve(T["frames"], B, {"fps": 30.0, "report": rep})
		var t2 := Time.get_ticks_msec()
		var mo := _measure(B, old, T)
		var mn := _measure(B, nw, T)
		var ts := slide(T["world"], T["runs"])
		var tl: Vector3 = (T["world"][-1]["_l"] as Vector3) - (T["world"][0]["_l"] as Vector3)
		print("    control: the TRUTH's own slide in these runs %.2f cm mean, %.2f worst; truth travel %.2f m, old %.2f, new %.2f" % [ts[0] * 100.0, ts[1] * 100.0, Vector2(tl.x, tl.z).length(), mo["travel"], mn["travel"]])
		print("--- %s: %d frames, %d true contact runs; old %d ms, new %d ms; reseeds %d, velocity-limited joints %d" % [name, nw.size(), mn["runs"], t1 - t0, t2 - t1, rep["reseeds"], rep["vel_hits"]])
		print("    metric                      old        new")
		print("    joint error (cm)         %7.2f    %7.2f   bar < 3" % [mo["joint"] * 100.0, mn["joint"] * 100.0])
		print("    end effectors (cm)       %7.2f    %7.2f   bar < 2" % [mo["ee"] * 100.0, mn["ee"] * 100.0])
		print("    frames outside limits    %7d    %7d   bar 0" % [mo["limits"], mn["limits"]])
		print("    frames over vel limit    %7d    %7d   bar 0" % [mo["vel"], mn["vel"]])
		print("    foot slide mean (cm)     %7.2f    %7.2f   bar < 1   (worst run old %.2f new %.2f)" % [mo["slide"] * 100.0, mn["slide"] * 100.0, mo["slide_worst"] * 100.0, mn["slide_worst"] * 100.0])
		ok(mn["joint"] < 0.03, "%s 1 mean joint error %.2f cm (old %.2f; bar 3)" % [name, mn["joint"] * 100.0, mo["joint"] * 100.0])
		ok(mn["ee"] < 0.02, "%s 2 end effectors %.2f cm (old %.2f; bar 2)" % [name, mn["ee"] * 100.0, mo["ee"] * 100.0])
		ok(mn["limits"] == 0, "%s 3 frames outside the joint limits: %d (old %d)" % [name, mn["limits"], mo["limits"]])
		ok(mn["vel"] == 0, "%s 4 frames over the velocity limit: %d (old %d)" % [name, mn["vel"], mo["vel"]])
		ok(mn["slide"] < 0.01, "%s 5 foot slide in contact %.2f cm mean, %.2f worst (old %.2f; bar 1)" % [name, mn["slide"] * 100.0, mn["slide_worst"] * 100.0, mo["slide"] * 100.0])
	# 6 hands go to the old path
	var fr := [{"t": 0.0, "w": VideoImport.landmarks_of(B), "hands": {}}, {"t": 0.033, "w": VideoImport.landmarks_of(B), "hands": {}}]
	var a := VideoRetarget.solve(fr, B, {})
	var b := VideoImport.solve(B, fr, "", 30.0)
	ok(a.size() == b.size() and (a[0]["ang"]["thigh_l"] as Vector3).is_equal_approx(b[0]["ang"]["thigh_l"]), "6 a clip with hands is the old path")
	print("RETARGET TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
