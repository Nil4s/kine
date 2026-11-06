## godot --headless --path . -s tests/n081_test.gd     (INNOVATIONS N081: cancel windows from the body, scripts/cancel_windows.gd)
## The question: on which frames of a clip is the body balanced and slow enough to start another move?
## A frame is CANCELABLE when all three hold: (1) balance margin >= MARGIN_MIN (Balance.read: the COM's floor point inside the feet),
## (2) |COM velocity| <= V_MAX and whole-body angular momentum about the COM (per unit mass) <= H_MAX, (3) neither foot is mid-swing (a foot
## off the floor: Balance.footprint empty). A WINDOW is a maximal run of cancelable frames at least MIN_RUN long.
## REGISTERED BEFORE ANY MEASURING (the implementation must carry exactly these; a test line below fails if it does not):
##   V_MAX      0.25 m/s     |COM velocity|. Quiet stance sways the COM at ~0.01-0.03 m/s (Winter 1995, Gait & Posture 3:193); gait initiation
##                           reaches ~0.3-0.4 m/s of forward COM speed by the first toe-off (Breniere, Do & Bouisset 1987; Lyon & Day 1997).
##                           0.25 is about ten times quiet sway and below a body that is already stepping. My estimate from those ranges, not a read-off.
##   H_MAX      0.045 m^2/s  whole-body angular momentum about the COM per unit mass. Herr & Popovic 2008 (J Exp Biol 211:467) find H/(M h v) stays
##                           within about +-0.02 through the whole walking cycle (the body regulates it low); 0.02 * 1.75 m * 1.3 m/s = 0.0455.
##                           A punch is not walking: its arm alone carries ~0.1 m^2/s (hand 10 m/s, ~0.45 m from the COM, 5% of mass).
##   MARGIN_MIN 0.0 m        spec: COM margin >= 0 (balanced).
##   MIN_RUN    3 frames     50 ms at 60 fps: a one- or two-frame gap cannot be used by a player (input buffer is a few frames).
##   OPEN_TOL   6 frames     after a jab's retracting card arrives, its window must have opened within 6 frames (100 ms).
## Sources are quoted from memory of the papers, not re-read this session: the numbers are the registration, the citations are the reason.
## Mass distribution and COM: de Leva 1996 via balance.gd. Angular momentum is the point-mass sum  sum m_i (r_i - c) x (v_i - vbar)  over the
## 17 body parts at their capsule midpoints (each part's own spin about its midpoint is left out: stated).
## Bars (60 fps; fixtures built here from joint angles):
##  1 IDLE: two stand cards held 1 s: ONE window, covering every frame (f0 0, f1 n).
##  2 JAB (guard hold 10 f, extend 3 f, hold 3, retract 12 f, hold 30): no frame of [first active, last active] is in a window; frame 0 is
##    (the guard is idle); a window opens at or after last_active + 1 and by retract_arrive + OPEN_TOL.
##  3 KICK (right thigh forward, foot off the floor): no window frame while the right foot is airborne (own scan). Then with v, h and margin
##    all let go (inf, inf, -inf) only the foot rule binds: still no window frame while airborne; with the foot rule off (th.feet = false)
##    the airborne frames ARE inside a window (the foot rule is what excludes them).
##  4 EXACT: the windows (and each frame's v, h, margin) equal the test's own recompute from B.cap and Balance.read, on the jab, the kick,
##    the idle clip and scenes/combo3.json: windows exactly, v and h within 1e-6, margin within 1e-9. Every window is >= MIN_RUN long and maximal.
##  5 MONOTONE: scaling v_max and h_max by 1, 1.5, 2, 4, 1000 never shrinks a window: the frame set grows, and each earlier window lies
##    inside a later one (jab, kick, combo3).
##  6 JSON: FrameData.to_json carries "cancel" after attach (thresholds + windows); through stringify/parse and through write_json to a file
##    the windows equal the module's; a frame data without attach has no "cancel" key (the old export is unchanged).
##  7 COST: measure() + the run scan < 1 ms per frame (mean over 300 calls, the posed jab mid-strike; S.apply's pose solve is not in it).
##  8 REGISTERED: the module's V_MAX, H_MAX, MARGIN_MIN, MIN_RUN equal the registered numbers above.
##  9 RUNS: runs([0,1,1,0,1,1,1,0], 3) is the single window [4,7); a run of exactly MIN_RUN is kept, MIN_RUN-1 is dropped.
## PLANTED CONTROLS (each is a WRONG claim the analysis must NOT satisfy):
##  C1 the idle clip has no window; C2 the jab's active frames are inside a window; C3 the kick's airborne frames are inside a window at
##  the registered thresholds; C4 with the foot rule off the airborne frames are NOT in a window; C5 a window list shifted by one frame
##  equals the recompute; C6 lowering the thresholds x0.01 gives a superset of the registered jab windows; C7 a tampered JSON window
##  equals the module's; C8 the idle clip's window count is 2.
extends SceneTree

var fails := 0
const FPS := 60
const REG_V := 0.25
const REG_H := 0.045
const REG_M := 0.0
const REG_RUN := 3
const OPEN_TOL := 6
const TOUCH := 0.01
const JAB_ARRIVE := 28   # 10 + 3 + 3 + 12: the retracting card arrives


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func control(claim: bool, what: String) -> void:
	print(("ok   control caught: " if not claim else "FAIL control NOT caught: ") + what)
	if claim:
		fails += 1


func stand() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	return b


func posed(j: String, v: Vector3) -> Dictionary:
	var b := stand()
	b.ang[j] = v
	b.fk()
	return b.to_dict()


func f(n: float) -> float:
	return n / float(FPS)


func plain(cards: Array) -> Scene:
	var s := Scene.new()
	s.from_dict({"scene": "zz_n081", "fps": 30, "natural": false, "on_floor": false, "pin": false, "cards": cards})
	return s


func idle() -> Scene:
	var st := stand().to_dict()
	return plain([{"name": "a", "pose": st, "move": -1.0, "hold": f(30)}, {"name": "b", "pose": st, "move": f(5), "hold": f(25)}])


func jab() -> Scene:
	var B := stand()
	var a0: Vector3 = B.ang["upperarm_r"]
	var guard := posed("upperarm_r", Vector3(10.0, a0.y, a0.z))
	var hit := posed("upperarm_r", Vector3(70.0, a0.y, a0.z))
	return plain([{"name": "guard", "pose": guard, "move": -1.0, "hold": f(10)}, {"name": "extend", "pose": hit, "move": f(3), "hold": f(3)},
		{"name": "retract", "pose": guard, "move": f(12), "hold": f(30)}])


func kick() -> Scene:
	var st := stand().to_dict()
	var k := posed("thigh_r", Vector3(60.0, 0.0, 0.0))
	return plain([{"name": "stand", "pose": st, "move": -1.0, "hold": f(10)}, {"name": "chamber", "pose": k, "move": f(8), "hold": f(6)},
		{"name": "back", "pose": st, "move": f(8), "hold": f(25)}])


func combo3() -> Scene:
	var s := Scene.new()
	s.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	return s


# ---------------------------------------------------------------- the test's own recompute

## the test's own sample of the body as posed now: part midpoints, COM, margin, feet in the air (own 9-point scan of the foot capsules)
func own_sample(B: Body) -> Dictionary:
	var pos := {}
	var sw := Vector3.ZERO
	var w := 0.0
	for j in Balance.MASS:
		var c: Array = B.cap(j)
		var mid: Vector3 = ((c[0] as Vector3) + (c[1] as Vector3)) * 0.5
		pos[j] = mid
		sw += mid * float(Balance.MASS[j])
		w += float(Balance.MASS[j])
	var air := {}
	for side in ["_l", "_r"]:
		var touching := false
		for part in ["foot" + side, "ball" + side]:
			var c: Array = B.cap(part)
			var r: float = B.rad[part]
			for k in 9:
				var p: Vector3 = (c[0] as Vector3).lerp(c[1], k / 8.0)
				if p.y - r <= TOUCH:
					touching = true
		air[side] = not touching
	return {"pos": pos, "com": sw / w, "margin": float(Balance.read(B)["margin"]), "air": air}


func own_series(S: Scene, B: Body) -> Array:
	var n := int(round(S.length() * FPS))
	var out := []
	for i in n:
		S.apply(B, float(i) / FPS)
		out.append(own_sample(B))
	return out


## v (m/s) and h (m^2/s per unit mass) at frame i, forward difference, the last frame backward
func own_vh(ser: Array, i: int) -> Vector2:
	var n := ser.size()
	var a := i if i < n - 1 else i - 1
	var s0: Dictionary = ser[a]
	var s1: Dictionary = ser[a + 1]
	var vc := ((s1["com"] as Vector3) - (s0["com"] as Vector3)) * FPS
	var wsum := 0.0
	var vbar := Vector3.ZERO
	var vel := {}
	for j in Balance.MASS:
		var v: Vector3 = ((s1["pos"][j] as Vector3) - (s0["pos"][j] as Vector3)) * FPS
		vel[j] = v
		vbar += v * float(Balance.MASS[j])
		wsum += float(Balance.MASS[j])
	vbar /= wsum
	var h := Vector3.ZERO
	for j in Balance.MASS:
		h += ((s0["pos"][j] as Vector3) - (s0["com"] as Vector3)).cross((vel[j] as Vector3) - vbar) * (float(Balance.MASS[j]) / wsum)
	return Vector2(vc.length(), h.length())


func own_flags(ser: Array, vmax: float, hmax: float, mmin: float, feet := true) -> Array:
	var fl := []
	for i in ser.size():
		var vh := own_vh(ser, i)
		var s: Dictionary = ser[i]
		var good: bool = float(s["margin"]) >= mmin and vh.x <= vmax and vh.y <= hmax
		if feet and (s["air"]["_l"] or s["air"]["_r"]):
			good = false
		fl.append(good)
	return fl


func own_runs(fl: Array, min_run: int) -> Array:
	var out := []
	var i := 0
	while i < fl.size():
		if fl[i]:
			var j := i
			while j < fl.size() and fl[j]:
				j += 1
			if j - i >= min_run:
				out.append([i, j])
			i = j
		else:
			i += 1
	return out


func wins(c: Dictionary) -> Array:
	var out := []
	for w in c["windows"]:
		out.append([int(w["f0"]), int(w["f1"])])
	return out


func in_win(w: Array, fr: int) -> bool:
	for x in w:
		if fr >= int(x[0]) and fr < int(x[1]):
			return true
	return false


func covered(a: Array, b: Array) -> bool:   # every frame of window set a lies in window set b
	for x in a:
		for fr in range(int(x[0]), int(x[1])):
			if not in_win(b, fr):
				return false
	return true


func th(s := 1.0) -> Dictionary:
	return {"v_max": REG_V * s, "h_max": REG_H * s}


func _init() -> void:
	# 8 registered numbers
	ok(is_equal_approx(CancelWindows.V_MAX, REG_V) and is_equal_approx(CancelWindows.H_MAX, REG_H) and is_equal_approx(CancelWindows.MARGIN_MIN, REG_M) and CancelWindows.MIN_RUN == REG_RUN,
		"8 registered: V_MAX %s, H_MAX %s, MARGIN_MIN %s, MIN_RUN %s" % [CancelWindows.V_MAX, CancelWindows.H_MAX, CancelWindows.MARGIN_MIN, CancelWindows.MIN_RUN])
	var B := stand()
	var scenes := {"idle": idle(), "jab": jab(), "kick": kick(), "combo3": combo3()}
	var res := {}
	var ser := {}
	for k in scenes:
		res[k] = CancelWindows.analyze(scenes[k], B, FPS)
		ser[k] = own_series(scenes[k], B)
	# 1 idle
	var ci: Dictionary = res["idle"]
	var n_i := int(ci["n"])
	var wi := wins(ci)
	ok(wi.size() == 1 and wi[0][0] == 0 and wi[0][1] == n_i and n_i == 60, "1 idle: one window, %s of %d frames" % [wi, n_i])
	# 2 jab
	var cj: Dictionary = res["jab"]
	var wj := wins(cj)
	var fdj := FrameData.analyze(scenes["jab"], B, FPS)
	var fa := int(fdj["first"])
	var la := int(fdj["last"])
	print("     jab: %d frames, active %d..%d, windows %s" % [cj["n"], fa, la, wj])
	ok(fa >= 0 and la >= fa, "2 jab: it has active frames (%d..%d)" % [fa, la])
	var bad_act := -1
	for fr in range(fa, la + 1):
		if in_win(wj, fr):
			bad_act = fr
			break
	ok(bad_act < 0, "2 jab: no active frame is in a window (first offender %d)" % bad_act)
	ok(in_win(wj, 0), "2 jab: frame 0 (the idle guard) is in a window")
	var after := -1
	for x in wj:
		if int(x[0]) > la:
			after = int(x[0])
			break
	ok(after >= la + 1 and after <= JAB_ARRIVE + OPEN_TOL, "2 jab: a window opens at f %d (after last active %d, by arrival %d + %d = %d)" % [after, la, JAB_ARRIVE, OPEN_TOL, JAB_ARRIVE + OPEN_TOL])
	# 3 kick
	var ck: Dictionary = res["kick"]
	var wk := wins(ck)
	var air_r := []
	for i in (ser["kick"] as Array).size():
		if ser["kick"][i]["air"]["_r"]:
			air_r.append(i)
	print("     kick: %d frames, right foot airborne on %d frames (%s..%s), windows %s" % [ck["n"], air_r.size(), air_r[0] if air_r.size() else -1, air_r[-1] if air_r.size() else -1, wk])
	var leak := -1
	for i in air_r:
		if in_win(wk, i):
			leak = i
			break
	ok(air_r.size() >= 8 and leak < 0, "3 kick: %d airborne frames, none in a window (first offender %d)" % [air_r.size(), leak])
	var free := {"v_max": INF, "h_max": INF, "margin_min": -INF}
	var wk_free := wins(CancelWindows.analyze(scenes["kick"], B, FPS, free))
	var leak2 := -1
	for i in air_r:
		if in_win(wk_free, i):
			leak2 = i
			break
	ok(leak2 < 0 and not wk_free.is_empty(), "3 kick, v/h/margin let go: only the foot rule binds, still none of the %d airborne frames in a window: %s" % [air_r.size(), wk_free])
	var nofeet := free.duplicate()
	nofeet["feet"] = false
	var wk_nf := wins(CancelWindows.analyze(scenes["kick"], B, FPS, nofeet))
	var in_nf := 0
	for i in air_r:
		if in_win(wk_nf, i):
			in_nf += 1
	ok(in_nf == air_r.size(), "3 kick, foot rule off: all %d airborne frames are inside a window (%d)" % [air_r.size(), in_nf])
	# 4 exact
	for k in scenes:
		var s: Array = ser[k]
		var fl := own_flags(s, REG_V, REG_H, REG_M)
		var ow := own_runs(fl, REG_RUN)
		var mw := wins(res[k])
		var worst_v := 0.0
		var worst_h := 0.0
		var worst_m := 0.0
		var frames: Array = res[k]["frames"]
		for i in s.size():
			var vh := own_vh(s, i)
			worst_v = maxf(worst_v, absf(vh.x - float(frames[i]["v"])))
			worst_h = maxf(worst_h, absf(vh.y - float(frames[i]["h"])))
			worst_m = maxf(worst_m, absf(float(s[i]["margin"]) - float(frames[i]["margin"])))
		var maximal := true
		var longenough := true
		for x in mw:
			longenough = longenough and int(x[1]) - int(x[0]) >= REG_RUN
			maximal = maximal and (int(x[0]) == 0 or not fl[int(x[0]) - 1]) and (int(x[1]) == fl.size() or not fl[int(x[1])])
		ok(mw == ow and worst_v < 1e-6 and worst_h < 1e-6 and worst_m < 1e-9 and maximal and longenough,
			"4 %s: %d windows %s equal the recompute; worst dv %.1e dh %.1e dmargin %.1e; maximal %s, all >= %d f" % [k, mw.size(), mw if mw.size() <= 4 else str(mw.slice(0, 4)) + "...", worst_v, worst_h, worst_m, maximal, REG_RUN])
	# 5 monotone
	for k in ["jab", "kick", "combo3"]:
		var prev: Array = []
		var prev_n := -1
		var good := true
		var note := ""
		for sc in [1.0, 1.5, 2.0, 4.0, 1000.0]:
			var w := wins(CancelWindows.analyze(scenes[k], B, FPS, th(sc)))
			var cnt := 0
			for x in w:
				cnt += int(x[1]) - int(x[0])
			if cnt < prev_n or not covered(prev, w):
				good = false
				note += " (x%s shrank)" % sc
			prev = w
			prev_n = cnt
			note += " x%s:%d" % [sc, cnt]
		ok(good, "5 monotone %s: window frames by threshold scale:%s" % [k, note])
	# 6 json
	var fdc := FrameData.analyze(scenes["jab"], B, FPS)
	ok(not FrameData.to_json(fdc).has("cancel"), "6 json: without attach there is no cancel key")
	CancelWindows.attach(fdc, scenes["jab"], B)
	var js := FrameData.to_json(fdc)
	var back: Dictionary = JSON.parse_string(JSON.stringify(js))
	var bw := wins(back.get("cancel", {"windows": []}))
	ok(js.has("cancel") and bw == wj and back["cancel"]["thresholds"]["v_max"] == REG_V and int(back["cancel"]["min_run"]) == REG_RUN,
		"6 json: round-trips (windows %s, thresholds %s)" % [bw, back.get("cancel", {}).get("thresholds")])
	var path := ProjectSettings.globalize_path("user://n081_fd.json")
	FrameData.write_json(fdc, path)
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	ok(wins(disk.get("cancel", {"windows": []})) == wj, "6 json: write_json to a file and back gives the same windows")
	# 7 cost
	var Bp := stand()
	scenes["jab"].apply(Bp, float(fa + 1) / FPS)
	var t0 := Time.get_ticks_usec()
	for i in 300:
		CancelWindows.measure(Bp)
	var us_measure := float(Time.get_ticks_usec() - t0) / 300.0
	var fl600 := []
	for i in 600:
		fl600.append(i % 7 != 0)
	var t1 := Time.get_ticks_usec()
	for i in 20:
		CancelWindows.runs(fl600, REG_RUN)
	var us_runs := float(Time.get_ticks_usec() - t1) / 20.0 / 600.0
	ok(us_measure + us_runs < 1000.0, "7 cost: measure %.0f us + run scan %.2f us per frame = %.0f us (< 1000)" % [us_measure, us_runs, us_measure + us_runs])
	# 9 runs
	var r9 := CancelWindows.runs([false, true, true, false, true, true, true, false], 3)
	var r9b := CancelWindows.runs([true, true, false, true, true, true], 3)
	var r9c := CancelWindows.runs([true, true], 3)
	ok(r9.size() == 1 and int(r9[0]["f0"]) == 4 and int(r9[0]["f1"]) == 7 and r9b.size() == 1 and int(r9b[0]["f0"]) == 3 and r9c.is_empty(), "9 runs: [4,7) kept, a run of 3 at the end kept, runs of 2 dropped")
	# controls
	control(wi.is_empty(), "C1 the idle clip has no window")
	control(in_win(wj, fa), "C2 the jab's first active frame is inside a window")
	control(air_r.size() > 0 and in_win(wk, air_r[0]), "C3 the kick's first airborne frame is inside a window at the registered thresholds")
	control(in_nf == 0, "C4 with the foot rule off, none of the airborne frames is in a window")
	var shifted := []
	for x in wj:
		shifted.append([int(x[0]) + 1, int(x[1])])
	control(shifted == own_runs(own_flags(ser["jab"], REG_V, REG_H, REG_M), REG_RUN), "C5 a window list with every start moved one frame equals the recompute")
	var w_low := wins(CancelWindows.analyze(scenes["jab"], B, FPS, th(0.01)))
	control(covered(w_low, wj) == false and covered(wj, w_low) and not wj.is_empty() and w_low != wj, "C6 lowering the thresholds x0.01 gives a SUPERSET of the registered jab windows")
	var tam: Dictionary = JSON.parse_string(JSON.stringify(js))
	tam["cancel"]["windows"][0]["f1"] = int(tam["cancel"]["windows"][0]["f1"]) + 1
	control(wins(tam["cancel"]) == wj, "C7 a tampered JSON window equals the module's")
	control(wi.size() == 2, "C8 the idle clip's window count is 2")
	print("N081 TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
