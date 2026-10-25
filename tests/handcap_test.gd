## godot --headless --path . -s tests/handcap_test.gd     (ROADMAP 90, HAND CAPTURE FROM VIDEO)
## Bars, stated before the numbers:
##   1 SYNTHETIC HANDS: random finger poses inside the limits, both hands, the app's own hand by forward kinematics, the 21
##     points seen through a pinhole camera (f 1000 px, 0.5 m) with 2 px Gaussian noise and back-projected: the recovered
##     flexion (every knuckle, middle and tip joint, bend) within 8 deg on average, 15 deg at worst
##   2 A FIST: the app's fist pose (Body.hand_pose "fist"), both hands, seen the same way: every finger's middle joint over 60 deg
##   3 A GAP: a hand missing for 40 frames (1.3 s) holds its last angles for LOST_HOLD (0.5 s, exact), is relaxed 1 s after
##     the gap starts (within 0.5 deg), comes back to the measured angles within EASE of its return (0.5 deg by 1 s after
##     the return), and no joint moves more than 8 deg in any frame (ours: 63 deg of knuckle over 15 frames is 6.3 a frame)
##   4 LIMITS: every recovered angle is what Body.clamp_ang gives back (inside its joint's limits)
##   5 THE IMPORT PATH: a pose file with hands (a fist, both hands) through VideoImport.parse and solve: the fitted fingers'
##     middle joints over 60 deg in every frame after the first 10
##   6 WITHOUT HANDS: a pose file with no "hands" key gives the same body as before: no finger joint in any frame's pose
##   7 THE CLEAN PATH: One Euro smoothing (VideoCleanup) leaves a held pose exact (0.01 deg) and keeps a fist over 60 deg
extends SceneTree

var fails := 0
var rng := RandomNumberGenerator.new()


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## the 21 points of one hand on the app's body, world metres: MediaPipe's numbering over the app's joints
func hand_points(B: Body, side: String) -> Array:
	var lm := []
	for k in 21:
		lm.append(Vector3.ZERO)
	lm[0] = B.P["hand_" + side]
	for f in ["thumb"] + HandImport.FING:
		var js := HandImport.joints(f, side)
		var pts := [B.P[js[0]], B.P[js[1]], B.P[js[2]], B.E[js[2]]]
		for k in 4:
			lm[HandImport.CHAIN[f][k]] = pts[k]
	return lm


## what a camera sees of those points: a random turn, f 1000 px at 0.5 m, 2 px of noise on each image point, then the
## points back in metres at their own depth (as MediaPipe's world points are). The hand's place does not matter to the fit
func observe(lm: Array) -> Array:
	var c := Vector3.ZERO
	for p in lm:
		c += p
	c /= float(lm.size())
	var Q := Quaternion.from_euler(Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(-3.1, 3.1), rng.randf_range(-1.2, 1.2)))
	var F := 1000.0
	var out := []
	for p in lm:
		var X: Vector3 = Q * ((p as Vector3) - c)
		var Z := 0.5 + X.z
		var u := F * X.x / Z + rng.randfn(0.0, 2.0)
		var v := F * X.y / Z + rng.randfn(0.0, 2.0)
		out.append(Vector3(u * Z / F, v * Z / F, Z))
	return out


## a random pose inside the limits (the bends and sides of the 20 finger joints), set on B
func random_fingers(B: Body, side: String) -> Dictionary:
	var truth := {}
	for f in ["thumb"] + HandImport.FING:
		var js := HandImport.joints(f, side)
		for k in 3:
			var j: String = js[k]
			var lo: float = (B.lim[j]["bend"] as Vector2).x
			var hi: float = (B.lim[j]["bend"] as Vector2).y
			var side_v := 0.0
			if k == 0:
				var sr: Vector2 = B.lim[j]["side"]
				side_v = rng.randf_range(sr.x * 0.5, sr.y * 0.5)
			truth[j] = Vector3(rng.randf_range(lo + 0.05 * (hi - lo), hi - 0.05 * (hi - lo)), side_v, 0.0)
			B.ang[j] = truth[j]
	B.fk()
	return truth


func _init() -> void:
	rng.seed = 90
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()

	# 1 synthetic hands, both sides, random poses
	var errs := []
	var worst := 0.0
	var limit_bad := 0
	var n_hands := 0
	for trial in 40:
		for side in ["l", "r"]:
			var truth := random_fingers(B, side)
			var seen := observe(hand_points(B, side))
			var res := HandImport.fit_hand(B, side, seen)
			if res.is_empty():
				errs.append(99.0)
				worst = 99.0
				continue
			n_hands += 1
			var fit: Dictionary = res["ang"]
			for j in truth:
				var e := absf((fit[j] as Vector3).x - (truth[j] as Vector3).x)
				errs.append(e)
				worst = maxf(worst, e)
				if (fit[j] as Vector3) != B.clamp_ang(j, fit[j]):
					limit_bad += 1
	var mean := 0.0
	for e in errs:
		mean += float(e)
	mean /= maxf(float(errs.size()), 1.0)
	ok(mean <= 8.0 and worst <= 15.0, "1 synthetic hands (40 poses x 2 hands, %d fitted, 2 px noise): flexion %.2f deg on average (bar 8), %.2f at worst (bar 15)" % [n_hands, mean, worst])
	# 4 limits
	ok(limit_bad == 0, "4 limits: %d recovered angles outside their joint's limits (bar 0)" % limit_bad)

	# 2 a fist, both hands
	var fist_ok := true
	var pip_min := 999.0
	for side in ["l", "r"]:
		B.hand_pose(side, "fist")
		var res := HandImport.fit_hand(B, side, observe(hand_points(B, side)))
		if res.is_empty():
			fist_ok = false
			continue
		for f in HandImport.FING:
			var pip: float = (res["ang"][HandImport.joints(f, side)[1]] as Vector3).x
			pip_min = minf(pip_min, pip)
	ok(fist_ok and pip_min > 60.0, "2 a fist, both hands: the weakest finger's middle joint %.1f deg (bar over 60)" % pip_min)

	# 3 a gap: 40 frames at 30 fps, frames 40..79 unseen
	var fps := 30.0
	var n := 120
	var A := {}
	var Bp := {}
	B.hand_pose("r", "fist")
	for j in HandImport.rest_pose("r"):
		A[j] = (B.ang[j] as Vector3)
	B.hand_pose("r", "open")
	for j in HandImport.rest_pose("r"):
		Bp[j] = (B.ang[j] as Vector3)
	var raw := []
	for i in n:
		if i >= 40 and i < 80:
			raw.append(null)
		else:
			raw.append((A if i < 40 else Bp).duplicate())
	var filled := HandImport.fill(raw, fps, "r")
	var hold_n := roundi(HandImport.LOST_HOLD * fps)
	var hold_exact := 0.0
	for k in range(40, 40 + hold_n):
		for j in A:
			hold_exact = maxf(hold_exact, ((filled[k][j] as Vector3) - (A[j] as Vector3)).length())
	var rest := HandImport.rest_pose("r")
	var relaxed_at := 0.0
	for j in rest:
		relaxed_at = maxf(relaxed_at, ((filled[70][j] as Vector3) - (rest[j] as Vector3)).length())
	var back := 0.0
	for j in Bp:
		back = maxf(back, ((filled[100][j] as Vector3) - (Bp[j] as Vector3)).length())
	var step := 0.0
	for k in range(1, n):
		for j in A:
			step = maxf(step, ((filled[k][j] as Vector3) - (filled[k - 1][j] as Vector3)).length())
	ok(hold_exact <= 0.01 and relaxed_at <= 0.5 and back <= 0.5 and step <= 8.0,
		"3 a gap of 40 frames: held exactly for %d frames (worst %.3f deg, bar 0.01), relaxed by frame 70 (%.2f deg off, bar 0.5), measured again by frame 100 (%.2f deg off, bar 0.5), largest step %.2f deg a frame (bar 8)" % [hold_n, hold_exact, relaxed_at, back, step])

	# 5 the import path: a file with a fist in both hands, 40 frames, through parse and solve
	B.hand_pose("l", "fist")
	B.hand_pose("r", "fist")
	var body_w := VideoImport.landmarks_of(B)
	var hand_l := hand_points(B, "l")
	var hand_r := hand_points(B, "r")
	var frames := []
	for i in 40:
		var hl := observe(hand_l)
		var hr := observe(hand_r)
		frames.append({"t": snappedf(i / fps, 0.001), "world": body_w.map(func(p): return [p.x, -p.y, -p.z]),
			"hands": {"l": {"world": hl.map(func(p): return [p.x, -p.y, -p.z])}, "r": {"world": hr.map(func(p): return [p.x, -p.y, -p.z])}}})
	var P := VideoImport.parse(JSON.stringify({"fps": fps, "frames": frames}))
	var fitted := VideoImport.solve(B, P["frames"], "", fps)
	var pip_all := 999.0
	for i in fitted.size():
		if i < 10:
			continue
		for sd in ["l", "r"]:
			for f in HandImport.FING:
				pip_all = minf(pip_all, (fitted[i]["ang"][HandImport.joints(f, sd)[1]] as Vector3).x)
	ok(P["ok"] and fitted.size() == 40 and pip_all > 60.0, "5 the import path, a fist in both hands over 40 frames: the weakest middle joint from frame 10 on %.1f deg (bar over 60)" % pip_all)

	# 6 without hands: the same frames with no "hands" key fit the body only
	var plain := []
	for f in frames:
		plain.append({"t": f["t"], "world": f["world"]})
	var P0 := VideoImport.parse(JSON.stringify({"fps": fps, "frames": plain}))
	var fit0 := VideoImport.solve(B, P0["frames"], "", fps)
	var fingers_key := false
	for fr in fit0:
		for j in fr["ang"]:
			if Body.FINGERS.has(j):
				fingers_key = true
	ok(P0["ok"] and fit0.size() == 40 and not fingers_key, "6 no hands in the file: %d frames, no finger joint in any pose (bar none)" % fit0.size())

	# 7 the clean path: One Euro on a held pose keeps it, on a fist keeps the curl
	var held := []
	for i in 60:
		held.append(A.duplicate())
	var sm := HandImport.smooth(held, fps)
	var drift := 0.0
	for i in sm.size():
		for j in A:
			drift = maxf(drift, ((sm[i][j] as Vector3) - (A[j] as Vector3)).length())
	var fist_sm := HandImport.smooth(fitted.map(func(fr): return fr["ang"]), fps)
	var pip_sm := 999.0
	for i in range(10, fist_sm.size()):
		pip_sm = minf(pip_sm, (fist_sm[i]["index_02_r"] as Vector3).x)
	ok(drift <= 0.01 and pip_sm > 60.0, "7 clean path (One Euro): a held pose moves %.4f deg (bar 0.01), the fist's middle joint stays over 60 deg (%.1f)" % [drift, pip_sm])

	print("HAND CAPTURE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
