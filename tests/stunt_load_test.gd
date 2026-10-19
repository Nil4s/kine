## godot --headless --path . -s tests/stunt_load_test.gd     (ROADMAP 24, "stunt load report": scripts/stunt_load.gd)
## 1. a synthetic drop from 0.5 m (free fall at 60 fps, then a constant stop over d): the impact speed is sqrt(2 g h), and
##    the landing load is the expected h / d in g (v^2 / 2 d, from the same v and d). Stiff knees (d 3 cm) are ABOVE the
##    3-7 BW drop-landing bar; soft bent knees (d 10 cm) are inside it. Series, not a posed body (a card cannot make a
##    free fall; the same report() reads the scene's sampled track).
## 2. a known valgus pose (the left knee 3.9 cm toward the midline, hip and ankle fixed) reads about 11 deg and is flagged
##    as over the bar in the touchdown window.
## 3. Nick's scenes (READ ONLY, res://scenes/*.json): each runs without errors, every note is a NOTE (never MUST FIX),
##    and the report prints (combo3 in full).
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## a drop: fall from rest for k frames (the touch is frame k), then a constant deceleration over d metres to rest
func drop_series(k: int, d: float) -> Dictionary:
	var g := StuntLoad.GRAV
	var fps := StuntLoad.FPS
	var top := 1.0
	var h := []
	var t := []
	var down := []
	for i in k + 1:
		h.append(top - 0.5 * g * pow(i / fps, 2.0))
	var v := g * (k / fps)              # the speed at the touch
	var tstop := 2.0 * d / v            # a constant stop: v -> 0 over d
	var a := v * v / (2.0 * d)
	var hk: float = h[k]
	for j in range(1, 60):
		var tj := minf(j / fps, tstop)
		h.append(hk - (v * tj - 0.5 * a * tj * tj))
	for i in h.size():
		t.append(i / fps)
		down.append(i >= k)
	return {"t": t, "h": h, "down": down}


func _init() -> void:
	# 1. the synthetic drop from 0.5 m (k = 19 frames at 60 fps = 0.317 s, so the realised drop is 0.492 m)
	var k := 19
	var h_real := 0.5 * StuntLoad.GRAV * pow(k / StuntLoad.FPS, 2.0)
	var v_exp := sqrt(2.0 * StuntLoad.GRAV * h_real)
	var mass := 75.0
	var soft := drop_series(k, 0.10)
	var stiff := drop_series(k, 0.03)
	var rs := StuntLoad.landing_rows(soft["t"], soft["h"], soft["down"])
	var rk := StuntLoad.landing_rows(stiff["t"], stiff["h"], stiff["down"])
	ok(rs.size() == 1 and rk.size() == 1, "1a one touchdown in each drop (soft %d, stiff %d)" % [rs.size(), rk.size()])
	if rs.size() == 1 and rk.size() == 1:
		var vs: float = rs[0]["v"]
		var vk: float = rk[0]["v"]
		print("     drop from %.3f m: expected impact sqrt(2 g h) %.3f m/s; measured soft %.3f, stiff %.3f" % [h_real, v_exp, vs, vk])
		ok(absf(vs - v_exp) / v_exp < 0.01 and absf(vk - v_exp) / v_exp < 0.01, "1b impact speed within 1%% of sqrt(2 g h) (%.3f m/s)" % v_exp)
		var g_exp_stiff := h_real / 0.03   # expected load in g from the same v and d: v^2 / (2 d g) = h / d
		var g_exp_soft := h_real / 0.10
		var g_st: float = float(rk[0]["a"]) / StuntLoad.GRAV
		var g_so: float = float(rs[0]["a"]) / StuntLoad.GRAV
		print("     load: stiff %.2f g (expected h/d = %.2f g, BW %.1f), soft %.2f g (expected %.2f g, BW %.1f)" % [
			g_st, g_exp_stiff, float(rk[0]["bw"]), g_so, g_exp_soft, float(rs[0]["bw"])])
		ok(absf(g_st - g_exp_stiff) / g_exp_stiff < 0.05, "1c stiff knees: %.2f g within 5%% of the expected %.2f g" % [g_st, g_exp_stiff])
		ok(absf(g_so - g_exp_soft) / g_exp_soft < 0.05, "1d soft knees: %.2f g within 5%% of the expected %.2f g" % [g_so, g_exp_soft])
		var bw_s: float = rs[0]["bw"]
		var bw_k: float = rk[0]["bw"]
		ok(bw_s >= 3.0 and bw_s <= 7.0, "1e soft bent-knee landing %.1f BW is inside the 3-7 BW drop-landing bar" % bw_s)
		ok(bw_k > 7.0, "1f stiff-knee landing %.1f BW is ABOVE the 3-7 BW bar" % bw_k)
		ok(bw_k > bw_s, "1g stiff knees load more than soft knees (%.1f > %.1f BW)" % [bw_k, bw_s])
		var sm_s := {"t": soft["t"], "h": soft["h"], "down": soft["down"], "flex": [], "twist": [], "vgl": [], "vgr": [], "hf": [], "ub": [], "mass": mass}
		for i in soft["t"].size():
			sm_s["flex"].append(0.0)
			sm_s["twist"].append(0.0)
			sm_s["vgl"].append(0.0)
			sm_s["vgr"].append(0.0)
			sm_s["hf"].append(0.0)
			sm_s["ub"].append(Vector3(0, 0.4, 0))
		var notes := StuntLoad.report(sm_s)
		var land := notes.filter(func(f): return f["rule"] == "LANDING LOAD" and "within" in f["msg"])
		ok(land.size() == 1, "1h the report lists the soft landing as within the bar (%d)" % land.size())

	# 2. the valgus pose: left knee 3.9 cm toward the midline, hip and ankle fixed
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	B.P["thigh_l"] = Vector3(0.089, 0.93, 0.0)
	B.P["calf_l"] = Vector3(0.050, 0.53, 0.0)
	B.P["foot_l"] = Vector3(0.089, 0.10, 0.0)
	var vg := StuntLoad.valgus(B, "_l")
	print("     valgus pose: left knee %.1f deg (expected about 10.8)" % vg)
	ok(absf(vg - 10.8) < 0.5, "2a the known valgus pose reads %.1f deg (about 10.8 by hand)" % vg)
	var vs_straight := StuntLoad.valgus(B, "_r")
	ok(absf(vs_straight) < 1.0, "2b the untouched right leg reads %.2f deg (straight: about 0)" % vs_straight)
	var sm_v := {"t": soft["t"], "h": soft["h"], "down": soft["down"], "flex": [], "twist": [], "vgl": [], "vgr": [], "hf": [], "ub": [], "mass": mass}
	for i in soft["t"].size():
		var on: bool = i >= 19 and i <= 25   # the touchdown window
		sm_v["flex"].append(0.0)
		sm_v["twist"].append(0.0)
		sm_v["vgl"].append(vg if on else 0.0)
		sm_v["vgr"].append(0.0)
		sm_v["hf"].append(0.0)
		sm_v["ub"].append(Vector3(0, 0.4, 0))
	var vn := StuntLoad.report(sm_v).filter(func(f): return f["rule"] == "KNEE VALGUS" and "over" in f["msg"] and "left" in f["msg"])
	ok(vn.size() == 1, "2c the valgus landing is flagged over the 10 deg bar as a NOTE (%d)" % vn.size())
	if vn.size() > 0:
		print("     %s" % vn[0]["msg"])

	# 3. Nick's scenes (read only): every scene runs; every note is a NOTE; the report prints
	var dir := DirAccess.open("res://scenes")
	var files := dir.get_files() if dir != null else PackedStringArray()
	var total := 0
	var bad_sev := 0
	var scenes_run := 0
	for f in files:
		if not f.ends_with(".json"):
			continue
		var S := Scene.new()
		S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/" + f)))
		var fs := StuntLoad.findings(S, B)
		scenes_run += 1
		total += fs.size()
		for x in fs:
			if x["sev"] != "NOTE":
				bad_sev += 1
		var n_land := fs.filter(func(x): return x["rule"] == "LANDING LOAD").size()
		print("     %-18s %3d notes, %d landing(s)" % [f, fs.size(), n_land])
		if f == "combo3.json":
			for x in fs:
				print("       %5.2f s  %-15s %s" % [x["t"], x["rule"], x["msg"]])
	ok(scenes_run >= 10, "3a Nick's scenes ran (%d files)" % scenes_run)
	ok(bad_sev == 0, "3b every note is a NOTE, none MUST FIX (%d notes over %d scenes)" % [total, scenes_run])

	print("STUNT LOAD TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(1 if fails > 0 else 0)
