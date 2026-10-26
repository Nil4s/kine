## godot --headless --path . -s tests/gait_band_test.gd     (round 43, GATES YY7)
## REAL WALKERS' BAND in the curve editor (scripts/gait_band.gd, refs/gait_band.json from tools/make_gait_band.py:
## Fukuchi, Fukuchi & Duarte 2018, 42 adults, overground, comfortable speed). Bars:
##   1 the table: 42 people, 101 points per joint; its landmarks are the people's (knee peak 55-70 deg in 65-80 % of the
##     cycle, hip most flexed near heel strike 25-40, ankle most dorsiflexed 8-20 in 35-55 %).
##   2 the band drawn = the table: the curve editor's outline at 7 points of the cycle is mean +- k SD on its own axes
##     (0.01 px), upper edge left to right then the lower edge back; the body's line is the body's angles.
##   3 the measure: at rest every angle is 0 (1e-4); a thigh turned 30 deg forward reads hip +30, a knee bent 40 reads
##     knee +40, toes 15 up read ankle +15 (within 1 deg; signs as the people's).
##   4 the listing rule: the people's own mean is inside (0 %); outside 2 SD on 11 points of 101 is LISTED, on 10 is not.
##   5 walk_bat: one cycle per leg found from its landings, all six joints measured (printed); the curve editor on
##     calf_r shows the band and fits the cycle into view.
##   6 a CHANGED walk is caught: walk_bat with both knees keyed straight (the step's leg reach still bends them at the
##     plants, so the knees move at other times: printed) lists both knees, and more joints than walk_bat lists.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func open(path: String) -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
	return S


func _init() -> void:
	var T := GaitBand.table()
	var J: Dictionary = T["joints"]
	var k: Array = J["knee"]["mean"]
	var h: Array = J["hip"]["mean"]
	var a: Array = J["ankle"]["mean"]
	var kmax: float = k.max()
	var hmax: float = h.max()
	var amax: float = a.max()
	var shapes := true
	for j in J:
		shapes = shapes and (J[j]["mean"] as Array).size() == 101 and (J[j]["sd"] as Array).size() == 101
	ok(int(T["n"]) == 42 and shapes and kmax > 55 and kmax < 70 and k.find(kmax) >= 65 and k.find(kmax) <= 80
		and hmax > 25 and hmax < 40 and amax > 8 and amax < 20 and a.find(amax) >= 35 and a.find(amax) <= 55,
		"1 the table: %d people, 101 points; knee peak %.1f at %d %%, hip max %.1f at %d %%, ankle max %.1f at %d %%" % [T["n"], kmax, k.find(kmax), hmax, h.find(hmax), amax, a.find(amax)])

	var C := CurveEditor.new()
	C.size = Vector2(800, 200)
	var you := []
	for i in 101:
		you.append(float(k[i]) + 1.0)
	C.band = GaitBand.judge({"ok": true, "joint": "knee", "side": "_r", "t0": 1.0, "t1": 2.2, "mean": k, "sd": J["knee"]["sd"], "you": you})
	C.t0 = 0.9
	C.t1 = 2.3
	C.v0 = -20.0
	C.v1 = 80.0
	var worst := 0.0
	for kk in [1.0, 2.0]:
		var poly := C.band_poly(kk)
		for i in [0, 10, 37, 50, 73, 88, 100]:
			var x := C.t_to_x(lerpf(1.0, 2.2, i / 100.0))
			var up := Vector2(x, C.v_to_y(float(k[i]) + kk * float(J["knee"]["sd"][i])))
			var dn := Vector2(x, C.v_to_y(float(k[i]) - kk * float(J["knee"]["sd"][i])))
			worst = maxf(worst, maxf(poly[i].distance_to(up), poly[201 - i].distance_to(dn)))
	var line := C.band_poly(NAN)
	worst = maxf(worst, line[50].distance_to(Vector2(C.t_to_x(1.6), C.v_to_y(float(k[50]) + 1.0))))
	ok(worst < 0.01 and C.band_poly(1.0).size() == 202 and line.size() == 101, "2 the band drawn = the table: 7 points x 2 widths x 2 edges + the body's line, worst %.4f px" % worst)
	C.free()

	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	var r0 := GaitBand.flex(B, "_r")
	var l0 := GaitBand.flex(B, "_l")
	var got := []
	for spec in [["thigh_r", 30.0, 0, "calf_r", 1.0], ["calf_r", 40.0, 1, "foot_r", -1.0], ["foot_r", 15.0, 2, "ball_r", 0.0]]:
		var best := 0.0
		for sg in [1.0, -1.0]:
			B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
			B.ang[spec[0]] = Vector3(sg * float(spec[1]), 0, 0)
			B.fk()
			var f := GaitBand.flex(B, "_r")[spec[2]]
			if absf(f) > absf(best):
				best = f
			# the direction the people call + : thigh forward (knee ahead), shank back (foot behind), toes up
			var dz: float = ((B.P[spec[3]] as Vector3) - (B.P[spec[0]] as Vector3)).z
			var dy: float = ((B.P[spec[3]] as Vector3) - (B.P[spec[0]] as Vector3)).y
			var plus: bool = (dz > 0.0) if spec[4] > 0.0 else ((dz < 0.0) if spec[4] < 0.0 else dy > -0.05)
			if plus:
				got.append([spec[0], spec[1], f])
	var meas := true
	for g in got:
		meas = meas and absf(float(g[2]) - float(g[1])) < 1.0
	ok(r0.length() < 1e-4 and l0.length() < 1e-4 and got.size() == 3 and meas,
		"3 the measure: rest %s / %s; turned the people's + way: %s" % [r0, l0, got.map(func(g): return "%s %.0f -> %.2f" % g)])

	var m: Array = J["ankle"]["mean"]
	var s: Array = J["ankle"]["sd"]
	var y0 := m.duplicate()
	var y11 := m.duplicate()
	var y10 := m.duplicate()
	for i in 11:
		y11[i * 9] = float(m[i * 9]) + 2.01 * float(s[i * 9])
		if i < 10:
			y10[i * 9] = float(m[i * 9]) + 2.01 * float(s[i * 9])
	var b0 := GaitBand.judge({"you": y0, "mean": m, "sd": s})
	var b11 := GaitBand.judge({"you": y11, "mean": m, "sd": s})
	var b10 := GaitBand.judge({"you": y10, "mean": m, "sd": s})
	ok(b0["out"] == 0.0 and not b0["listed"] and b11["listed"] and not b10["listed"],
		"4 the listing rule: the mean %.0f %% (not listed), 11 points out %.1f %% listed %s, 10 points %.1f %% listed %s" % [b0["out"] * 100, b11["out"] * 100, b11["listed"], b10["out"] * 100, b10["listed"]])

	var W := open("res://scenes/walk_bat.json")
	var rw := GaitBand.report(W)
	var cr := GaitBand.for_part(W, "calf_r")
	var cl := GaitBand.for_part(W, "calf_l")
	var C2 := CurveEditor.new()
	C2.size = Vector2(800, 200)
	C2.scene = W
	C2.joint = "calf_r"
	C2.band = cr
	C2.frame_all()
	var fits := true
	if cr.get("ok", false):
		fits = C2.t0 <= cr["t0"] and C2.t1 >= cr["t1"]
		for i in 101:
			fits = fits and C2.v0 <= float(cr["you"][i]) and C2.v1 >= float(cr["you"][i]) and C2.v0 <= float(k[i]) - 2.0 * float(J["knee"]["sd"][i]) and C2.v1 >= float(k[i]) + 2.0 * float(J["knee"]["sd"][i])
	C2.free()
	ok(rw.get("ok", false) and cr.get("ok", false) and cl.get("ok", false) and cr["t1"] > cr["t0"] and fits,
		"5 walk_bat: right cycle %s, left %s; each joint's share outside 2 SD %s; listed %s; the editor fits the cycle %s" % [
			[cr.get("t0"), cr.get("t1")] if cr.get("ok", false) else cr.get("why"), [cl.get("t0"), cl.get("t1")] if cl.get("ok", false) else cl.get("why"),
			rw.get("all", []).map(func(x): return "%s %d%%" % [x["part"], int(round(x["out"] * 100))]), rw.get("listed", []).map(func(x): return x["part"]), fits])

	var stiff := open("res://scenes/walk_bat.json")
	for sd in ["_r", "_l"]:
		PartKeys.put(stiff.part_keys, "calf" + sd, 0.0, Vector3.ZERO)
		PartKeys.put(stiff.part_keys, "calf" + sd, stiff.length(), Vector3.ZERO)
	var rs := GaitBand.report(stiff)
	var names: Array = rs.get("listed", []).map(func(x): return x["part"])
	ok(rs.get("ok", false) and "calf_r" in names and "calf_l" in names and names.size() > rw.get("listed", []).size(),
		"6 walk_bat with knees keyed straight lists %s (walk_bat lists %d); its shares %s" % [names, rw.get("listed", []).size(),
			rs.get("all", []).map(func(x): return "%s %d%%" % [x["part"], int(round(x["out"] * 100))])])
	print("GAIT BAND TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
