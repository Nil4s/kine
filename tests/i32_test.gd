## godot --path . -s tests/i32_test.gd     (ROADMAP I32: My camera, scripts/my_camera.gd + my_camera_ui.gd; needs a window)
## Bars, written before measuring. Synthetic scenes live in user://i32_<pid>/ (a temp folder); res://scenes is only read.
##  (1) FINGERPRINT: 3 synthetic two-fighter scenes, 9 shots whose lens / distance / angle / height / cut offsets are KNOWN (built with
##      this file's own reading of the bodies): the medians of f, dist, theta, h, cut match the known medians within 2 %; the screen
##      position (sx, sy) within 0.01 of a frame; counts 9 keys, 9 shots, 3 scenes
##  (2) cache: a second compute() is cached with the same stats; a changed scene list recomputes (cached false), same stats
##  (3) FRAME IT MY WAY, 2-fighter scene whose first shot is on the + side: one new shot, ONE undo step, on the frame (contact - median
##      cut offset); its key, measured here: lens, distance, angle, height within 5 % of the fingerprint's medians, sx / sy within
##      0.02; the camera stays on the + side of the line at the cut, at the contact and at the end of the scene
##  (4) the same with the first shot on the - side: the new camera is on the - side (the shot before it decides)
##  (5) no shots in the scene: the key is the scene's first shot at 0 s, one undo step
##  (6) the status line names the habits ("35 mm", "2.0 body heights", "30 deg off the line", "2 f before contact")
##  (7) undo gives the scene JSON back exactly (each case); the source scenes (temp + res://scenes) are byte-identical (md5)
##  (8) no shots in the folder: nothing written, no undo step, Auto camera opens instead
##  (9) PLACEMENT (screenshot tmp/i32.png): looking through the new shot, the hero's head and pelvis are inside the shot frame, his pelvis
##      is at the fingerprint's thirds position within 0.03 of the frame width, the panel is inside the window and lists 7 habits
extends SceneTree

var fails := 0
var m: Node
const TMP := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/"
const FRM := Rect2i(0, 0, 1280, 720)
var dir_t := "user://i32_%d" % OS.get_process_id()
var cache_t := "user://i32_%d_cache.json" % OS.get_process_id()


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func rd(S: Scene, t: float) -> Array:
	var out := []
	for k in 1 + S.actors.size():
		var B := Body.new()
		B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		var sc: Scene = S if k == 0 else S.actors[k - 1]["scene"]
		var X := Transform3D.IDENTITY
		if k > 0:
			var xf: Dictionary = S.actors[k - 1]["xf"]
			X = Transform3D(Basis(Vector3.UP, deg_to_rad(float(xf["yaw"]))), Vector3(float(xf["pos"][0]), 0, float(xf["pos"][1])))
		sc.apply(B, t)
		B.fk()
		var lo := 1e9
		for j in Body.ORDER.slice(0, 22):
			lo = minf(lo, (X * (B.P[j] as Vector3)).y)
		for sd in ["l", "r"]:
			lo = minf(lo, (X * (B.P["ball_" + sd] as Vector3)).y - 0.03)
			lo = minf(lo, (X * (B.P["foot_" + sd] as Vector3)).y - 0.07)
		var f: Vector3 = X.basis * ((B.P["thigh_l"] as Vector3) - (B.P["thigh_r"] as Vector3)).cross(Vector3.UP)
		out.append({"pel": X * (B.P["pelvis"] as Vector3), "top": X * (B.P["head"] as Vector3) + Vector3(0, 0.13, 0), "lo": lo,
			"face": Vector3(f.x, 0, f.z).normalized()})
	return out


func line_of(fs: Array) -> Vector3:
	var d: Vector3 = (fs[1]["pel"] as Vector3) - (fs[0]["pel"] as Vector3)
	return Vector3(d.x, 0, d.z).normalized()


## a camera key built from KNOWN habits at time t: lens f, distance dist (body heights), angle theta from behind the hero along the
## line, side (+1 / -1 of the line), height hr (x eye height); aimed at the pelvis moved `off` m along the camera's right
func build(S: Scene, t: float, f: float, dist: float, theta: float, side: float, hr: float, off: float) -> Dictionary:
	var fs := rd(S, t)
	var dir := line_of(fs)
	var H: float = (fs[0]["top"] as Vector3).y - float(fs[0]["lo"])
	var eye := H - 0.12
	var A: Vector3 = fs[0]["pel"]
	A.y = 0
	var v := Basis(Vector3.UP, -side * deg_to_rad(theta)) * (-dir)
	var pos := A + v * dist * H
	pos.y = float(fs[0]["lo"]) + hr * eye
	var pel: Vector3 = fs[0]["pel"]
	var right := (-v).cross(Vector3.UP).normalized()
	return {"t": t, "pos": pos, "aim": pel + right * off, "f": f}


## my own measure of a key (this file's reading of the bodies)
func meas(S: Scene, key: Dictionary) -> Dictionary:
	var fs := rd(S, float(key["t"]))
	var dir := line_of(fs)
	var H: float = (fs[0]["top"] as Vector3).y - float(fs[0]["lo"])
	var eye := H - 0.12
	var A: Vector3 = fs[0]["pel"]
	A.y = 0
	var pos: Vector3 = key["pos"]
	var rel := Vector3(pos.x - A.x, 0, pos.z - A.z)
	var sp := ShotCam.project(pos, key["aim"], key["f"], FRM, fs[0]["pel"])
	var rt: Vector3 = ShotCam.xf(pos, key["aim"]).basis.x
	return {"f": key["f"], "dist": rel.length() / H, "theta": rad_to_deg(acos((-dir).dot(rel.normalized()))), "h": (pos.y - float(fs[0]["lo"])) / eye,
		"side": signf(dir.z * rel.x - dir.x * rel.z), "sx": (sp.x - 640.0) / 1280.0 * signf(dir.dot(rt)), "sy": (sp.y - 360.0) / 720.0}


func med(a: Array) -> float:
	var s := a.duplicate()
	s.sort()
	var n := s.size()
	return float(s[n / 2]) if n % 2 == 1 else (float(s[n / 2 - 1]) + float(s[n / 2])) * 0.5


func within(a: float, b: float, rel: float, absn := 0.0) -> bool:
	return absf(a - b) <= maxf(rel * absf(b), absn)


func write_json(path: String, d: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))


func md5s(paths: Array) -> Array:
	return paths.map(func(p): return FileAccess.get_md5(String(p)))


func js(S: Scene) -> String:
	return JSON.stringify(S.to_dict(m.B, false))


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m._actor_add()
	await idle()
	var S: Scene = m._hero_scene()
	var fps: int = S.fps
	var base: Dictionary = S.to_dict(m.B, false)
	base.erase("camera")
	base.erase("shots")
	var bt := AutoCam.beats(S, AutoCam.bodies_for(S))
	var tcf := float(roundi(float(bt["tc"]) * fps)) / float(fps)
	var tcfr := roundi(float(bt["tc"]) * fps)
	DirAccess.make_dir_absolute(dir_t)
	MyCam.dirs = [dir_t]
	MyCam.cache_path = cache_t
	var res_scenes: Array = []
	for fn in DirAccess.get_files_at("res://scenes"):
		if fn.ends_with(".json"):
			res_scenes.append("res://scenes/" + fn)
	var res_md5 := md5s(res_scenes)
	# ---- the synthetic scenes: [f, dist, theta, h, off] per shot, cut offsets (frames before the contact) per later shot
	var specs := [
		{"shots": [[35, 1.8, 25, 0.9, 0.25], [35, 2.0, 30, 1.0, -0.25], [50, 2.2, 35, 1.1, 0.25]], "off": [2, 3]},
		{"shots": [[35, 1.9, 28, 1.0, -0.25], [28, 2.0, 30, 1.0, 0.25], [35, 2.1, 40, 1.05, -0.25]], "off": [2, 1]},
		{"shots": [[35, 2.0, 30, 0.95, 0.25], [50, 2.0, 32, 1.0, -0.25], [35, 2.3, 30, 1.1, 0.25]], "off": [2, 2]}]
	var want := {"f": [], "dist": [], "theta": [], "h": [], "cut": [], "sx": [], "sy": []}
	for si in specs.size():
		var sp: Dictionary = specs[si]
		var shots := []
		for k in 3:
			var q: Array = sp["shots"][k]
			var t := 0.0 if k == 0 else float(tcfr - int(sp["off"][k - 1])) / float(fps)
			var key := build(S, t, q[0], q[1], q[2], 1.0, q[3], q[4])
			shots.append({"t": t, "name": "Shot %d" % (k + 1), "keys": [key]})
			var mm := meas(S, key)
			for h in ["f", "dist", "theta", "h", "sx", "sy"]:
				want[h].append(float(mm[h]))
			if k > 0:
				want["cut"].append(float(sp["off"][k - 1]))
		var d := base.duplicate(true)
		d["shots"] = ShotCam.shots_to_file(shots)
		d["markers"] = [{"t": tcf, "name": "hit", "kind": "hit"}]
		write_json(dir_t + "/syn%d.json" % (si + 1), d)
	var t0 := Time.get_ticks_usec()
	var fp := MyCam.compute()
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var st: Dictionary = fp["stats"]
	var line := []
	var okm := true
	for h in ["f", "dist", "theta", "h", "cut"]:
		var w := med(want[h])
		var g := float(st[h]["med"])
		line.append("%s %.3f vs %.3f (n %d)" % [h, g, w, int(st[h]["n"])])
		okm = okm and within(g, w, 0.02) and int(st[h]["n"]) == (6 if h == "cut" else 9)
	ok(okm, "(1) medians within 2%% of the known ones: %s [%.0f ms]" % [" | ".join(line), ms])
	ok(within(float(st["sx"]["med"]), med(want["sx"]), 0, 0.01) and within(float(st["sy"]["med"]), med(want["sy"]), 0, 0.01),
		"(1) screen position sx %.3f (known %.3f), sy %.3f (known %.3f)" % [st["sx"]["med"], med(want["sx"]), st["sy"]["med"], med(want["sy"])])
	ok(int(fp["keys"]) == 9 and int(fp["shots"]) == 9 and int(fp["scenes"]) == 3 and float(st["f"]["q1"]) <= 35.0 and float(st["f"]["q3"]) >= 35.0,
		"(1) counts: %d keys, %d shots, %d scenes; lens middle half %.0f - %.0f mm" % [fp["keys"], fp["shots"], fp["scenes"], st["f"]["q1"], st["f"]["q3"]])
	var fp2 := MyCam.compute()
	ok(bool(fp2.get("cached", false)) and ["f", "dist", "theta", "h", "sx", "sy", "cut"].all(func(h): return absf(float(fp2["stats"][h]["med"]) - float(st[h]["med"])) < 1e-9 and int(fp2["stats"][h]["n"]) == int(st[h]["n"])), "(2) second compute is cached, same stats")
	write_json(dir_t + "/zz_noshots.json", base)
	var fp3 := MyCam.compute()
	ok(not bool(fp3.get("cached", false)) and JSON.stringify(fp3["stats"]) == JSON.stringify(MyCam.compute(true)["stats"]) and absf(float(fp3["stats"]["dist"]["med"]) - float(st["dist"]["med"])) < 1e-9 and int(fp3["read"]) == 4, "(2) a new scene in the folder recomputes (read %d), same stats" % int(fp3["read"]))
	var tmp_files := []
	for fn in DirAccess.get_files_at(dir_t):
		tmp_files.append(dir_t + "/" + fn)
	var tmp_md5 := md5s(tmp_files)
	# ---- Frame it my way
	var stt: Dictionary = MyCam.compute()["stats"]
	var expect_fr := tcfr - int(roundf(float(stt["cut"]["med"])))
	for sd in [1.0, -1.0]:
		S.shots = [{"t": 0.0, "name": "Shot 1", "keys": [build(S, 0.0, 28, 2.5, 60, sd, 1.0, 0.0)]}]
		var jb := js(S)
		var u0: int = m.undo.size()
		m.mc_ui.frame_it()
		await idle()
		var tag := "first shot on the %s side" % ("+" if sd > 0 else "-")
		var no := "3" if sd > 0 else "4"
		ok(m.undo.size() == u0 + 1 and S.shots.size() == 2, "(%s) %s: ONE undo step (%d -> %d), %d shots" % [no, tag, u0, m.undo.size(), S.shots.size()])
		if S.shots.size() == 2:
			var sh: Dictionary = S.shots[1]
			ok(roundi(float(sh["t"]) * fps) == expect_fr, "(%s) the cut is on frame %d = contact %d - %d" % [no, roundi(float(sh["t"]) * fps), tcfr, tcfr - expect_fr])
			var key: Dictionary = sh["keys"][0]
			var mm := meas(S, key)
			var good := within(mm["f"], stt["f"]["med"], 0.05) and within(mm["dist"], stt["dist"]["med"], 0.05) and within(mm["theta"], stt["theta"]["med"], 0.05) \
				and within(mm["h"], stt["h"]["med"], 0.05) and within(mm["sx"], stt["sx"]["med"], 0, 0.02) and within(mm["sy"], stt["sy"]["med"], 0, 0.02)
			ok(good, "(%s) measured key: %.1f mm, %.2f body heights, %.1f deg, %.2f eye, sx %+.3f, sy %+.3f  vs  fingerprint %.1f, %.2f, %.1f, %.2f, %+.3f, %+.3f" % [
				no, mm["f"], mm["dist"], mm["theta"], mm["h"], mm["sx"], mm["sy"], stt["f"]["med"], stt["dist"]["med"], stt["theta"]["med"], stt["h"]["med"], stt["sx"]["med"], stt["sy"]["med"]])
			var sides := []
			for t in [float(sh["t"]), tcf, S.length()]:
				var kk: Dictionary = key.duplicate()
				kk["t"] = t
				sides.append(meas(S, kk)["side"])
			ok(sides.all(func(v): return v == sd), "(%s) the camera stays on the %s side of the line at the cut, the contact and the end: %s" % [no, "+" if sd > 0 else "-", sides])
		m._undo()
		await idle()
		ok(js(S) == jb, "(7) undo: the scene JSON is exact again (%s)" % tag)
	# (5) a scene without shots
	S.shots = []
	var jn := js(S)
	var u1: int = m.undo.size()
	m.mc_ui.frame_it()
	await idle()
	ok(m.undo.size() == u1 + 1 and S.shots.size() == 1 and absf(float(S.shots[0]["t"])) < 1e-6, "(5) no shots: one undo step, the first shot starts at 0 s")
	if S.shots.size() == 1:
		var m5 := meas(S, S.shots[0]["keys"][0])
		ok(within(m5["dist"], stt["dist"]["med"], 0.05) and within(m5["f"], stt["f"]["med"], 0.05), "(5) key: side %+d, %.2f body heights, %.0f mm" % [m5["side"], m5["dist"], m5["f"]])
	m._undo()
	await idle()
	ok(js(S) == jn, "(7) undo: the scene JSON is exact again (no shots)")
	# (6) the status line
	S.shots = [{"t": 0.0, "name": "Shot 1", "keys": [build(S, 0.0, 28, 2.5, 60, 1.0, 1.0, 0.0)]}]
	m.mc_ui.frame_it()
	await idle()
	var txt := String(m.mc_ui.last_plan.get("text", ""))
	print("     status: ", txt)
	ok(txt.contains("35 mm") and txt.contains("2.0 body heights") and txt.contains("30 deg off the line") and txt.contains("2 f before contact"), "(6) the status names the habits")
	# (9) placement: through the new shot
	m.playhead = tcf
	m._refresh()
	await idle()
	m._shot_toggle()
	await idle(4)
	var rect: Rect2i = m.shot_rect()
	var fc := rd(S, m.playhead)
	var hp: Vector2 = m.cam.unproject_position(fc[0]["top"])
	var pp: Vector2 = m.cam.unproject_position(fc[0]["pel"])
	var sl := signf(line_of(fc).dot(m.cam.global_transform.basis.x))
	var sxs := (pp.x - (rect.position.x + rect.size.x * 0.5)) / rect.size.x * sl
	ok(m.shot_through and Rect2(rect).has_point(hp) and Rect2(rect).has_point(pp), "(9) through the new shot: the hero's head %s and pelvis %s are inside the frame %s" % [hp.round(), pp.round(), rect])
	ok(absf(sxs - float(stt["sx"]["med"])) < 0.03, "(9) the pelvis sits %+.3f of the frame width from the centre (the fingerprint's thirds: %+.3f)" % [sxs, stt["sx"]["med"]])
	m.mc_ui.show()
	await idle(3)
	var vp := m.get_viewport().get_visible_rect()
	var grid = m.mc_ui.panel.find_child("mycam_grid", true, false)
	ok(vp.encloses(m.mc_ui.panel.get_global_rect()) and grid != null and grid.get_child_count() == 32, "(9) the panel is inside the window (%s) and lists 7 habits + header" % m.mc_ui.panel.get_global_rect())
	await idle(2)
	root.get_texture().get_image().save_png(TMP + "i32.png")
	m._shot_toggle()
	m._undo()
	await idle()
	# (8) no shots in the folder
	MyCam.dirs = [dir_t + "_empty"]
	DirAccess.make_dir_absolute(dir_t + "_empty")
	S.shots = []
	var j8 := js(S)
	var u8: int = m.undo.size()
	m.mc_ui.frame_it()
	await idle()
	ok(m.undo.size() == u8 and js(S) == j8 and S.shots.is_empty(), "(8) no shots in the folder: nothing written, no undo step")
	ok(m.ac_ui != null and m.ac_ui.panel != null and is_instance_valid(m.ac_ui.panel) and m.ac_ui.panel.visible, "(8) Auto camera opened instead")
	# (7) sources
	var tmp_files2 := []
	for fn in DirAccess.get_files_at(dir_t):
		tmp_files2.append(dir_t + "/" + fn)
	ok(md5s(tmp_files2) == tmp_md5 and md5s(res_scenes) == res_md5, "(7) source scenes byte-identical: %d temp, %d in res://scenes" % [tmp_files.size(), res_scenes.size()])
	for p in tmp_files2:
		DirAccess.remove_absolute(String(p))
	DirAccess.remove_absolute(dir_t)
	DirAccess.remove_absolute(dir_t + "_empty")
	DirAccess.remove_absolute(cache_t)
	print("I32 MY CAMERA %s" % ("FAIL" if fails > 0 else "PASS") + (" (%d failed)" % fails if fails > 0 else ""))
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
