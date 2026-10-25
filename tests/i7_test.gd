## godot --path . -s tests/i7_test.gd     (ROADMAP I7: auto camera, scripts/auto_camera.gd + auto_camera_ui.gd; needs a window)
## Bars, written before measuring (a 1280x720 frame; fighters' joints + head top + soles are the "body points"):
##  (1) combo3 (one fighter): 3 suggestions in beat order wind-up, contact, recover, each with a rule label, cut times rising
##  (2) 180-DEGREE RULE: the action line is computed here from the bodies (one fighter: his facing from the hip line; two: the
##      line between the pelvises), at the contact time; the side of every suggested camera, y of line x (cam - hero pelvis), has
##      ONE sign and magnitude over 0.1 m, on the combo3 scene and on the two-fighter scene
##  (3) CLOSER ON CONTACT: the hero's head-to-sole height on screen at the contact shot >= 1.2 x the wind-up shot's (the code aims
##      for 1.25), on both scenes
##  (4) LEAD ROOM: the hero's pelvis screen x is offset from the frame centre OPPOSITE to the strike's screen direction (the strike
##      hand's travel dotted with the camera's right), by at least 0.08 of the frame width, in every shot of both scenes
##  (5) TWO FIGHTERS: in the wind-up and recover (wide) shots both fighters' body points are inside the frame at the beat time and
##      at 5 other times of the shot
##  (6) the scene JSON is byte-identical after the strip is shown and its thumbnails are drawn (nothing changes until a click)
##  (7) Keep (one suggestion): one more undo step, the scene has that shot (an empty list: cut 0), undo gives the JSON back exactly;
##      Keep all: one undo step, 3 shots at the 3 cuts, undo exact; the camera keys are the suggested ones
##  (8) PLACEMENT: the strip is inside the window, one thumbnail + rule label + Keep per suggestion, every thumbnail a drawn picture
##      (not one flat colour); looking through the kept contact camera, the hero's head and striking hand land inside the shot frame
##      of the viewport. Screenshot: tmp/i7.png
##  (9) compute on combo3 under 600 ms
extends SceneTree

var fails := 0
var m: Node
const TMP := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/"
const FRM := Rect2i(0, 0, 1280, 720)


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## my own reading of a scene at time t: [{"pel", "face", "all", "hl", "hr"}] per fighter
func read(S: Scene, t: float) -> Array:
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
		var all := []
		for j in Body.ORDER.slice(0, 22):
			all.append(X * (B.P[j] as Vector3))
		all.append(X * (B.P["head"] as Vector3) + Vector3(0, 0.13, 0))
		all.append(X * (B.P["ball_l"] as Vector3) + Vector3(0, -0.03, 0))
		all.append(X * (B.P["ball_r"] as Vector3) + Vector3(0, -0.03, 0))
		var f: Vector3 = X.basis * ((B.P["thigh_l"] as Vector3) - (B.P["thigh_r"] as Vector3)).cross(Vector3.UP)
		out.append({"pel": X * (B.P["pelvis"] as Vector3), "face": Vector3(f.x, 0, f.z).normalized(), "all": all,
			"hl": X * (B.P["hand_l"] as Vector3), "hr": X * (B.P["hand_r"] as Vector3), "top": X * (B.P["head"] as Vector3) + Vector3(0, 0.13, 0)})
	return out


func check_scene(tag: String, S: Scene, res: Dictionary, two: bool) -> void:
	var sugs: Array = res["sugs"]
	ok(sugs.size() == 3 and sugs[0]["beat"] == "windup" and sugs[1]["beat"] == "contact" and sugs[2]["beat"] == "recover", "(1) %s: 3 suggestions wind-up, contact, recover" % tag)
	var labels := true
	for s in sugs:
		labels = labels and String(s["rule"]) != "" and (s["rules"] as Array).size() >= 2
	ok(labels, "(1) %s: every suggestion names its rule: %s" % [tag, " | ".join(sugs.map(func(s): return String(s["rule"])))])
	ok(float(sugs[0]["cut"]) < float(sugs[1]["cut"]) and float(sugs[1]["cut"]) < float(sugs[2]["cut"]), "(1) %s: cuts rise %.2f < %.2f < %.2f s" % [tag, sugs[0]["cut"], sugs[1]["cut"], sugs[2]["cut"]])
	var bt: Dictionary = res["beats"]
	var tc := float(bt["tc"])
	var fc := read(S, tc)
	var A: Vector3 = fc[0]["pel"]
	A.y = 0
	var dir: Vector3 = fc[0]["face"]
	if two:
		var d: Vector3 = fc[1]["pel"] - fc[0]["pel"]
		dir = Vector3(d.x, 0, d.z).normalized()
	var signs := []
	var mins := 1e9
	for s in sugs:
		var p: Vector3 = s["key"]["pos"]
		var cr := dir.z * (p.x - A.x) - dir.x * (p.z - A.z)
		signs.append(signf(cr))
		mins = minf(mins, absf(cr))
	var same: bool = signs.all(func(v): return v == signs[0])
	ok(same and mins > 0.1, "(2) %s: cross-product signs %s, smallest |cross| %.2f m (%s)" % [tag, signs, mins, "line between the fighters" if two else "his facing"])
	# motion: the striking hand's flat travel over the contact card
	var ts := S.times()
	var c: int = bt["c"]
	var h0: Dictionary = read(S, float(ts[c][0]))[0]
	var h1: Dictionary = read(S, float(ts[c][1]))[0]
	var sd: String = bt["strike"]["hand"]
	var mv: Vector3 = (h1["h" + sd] as Vector3) - (h0["h" + sd] as Vector3)
	mv.y = 0
	# heights, lead room, frame
	var hs := []
	var lead_ok := true
	var lead_txt := []
	for s in sugs:
		var key: Dictionary = s["key"]
		var tb: float = s["t"]
		var fr := read(S, tb)
		var lo := 1e9
		for p in fr[0]["all"]:
			lo = minf(lo, (p as Vector3).y)
		var top: Vector3 = fr[0]["top"]
		var a := ShotCam.project(key["pos"], key["aim"], key["f"], FRM, top)
		var b := ShotCam.project(key["pos"], key["aim"], key["f"], FRM, Vector3(top.x, lo, top.z))
		hs.append(absf(b.y - a.y) / 720.0)
		var right: Vector3 = (ShotCam.xf(key["pos"], key["aim"]).basis * Vector3(1, 0, 0))
		var smotion := mv.normalized().dot(right)
		var px := ShotCam.project(key["pos"], key["aim"], key["f"], FRM, fr[0]["pel"]).x
		var off := (px - 640.0) / 1280.0
		lead_txt.append("%s %+.2f (motion %+.2f)" % [s["beat"], off, smotion])
		if not (absf(smotion) > 0.2 and signf(off) == -signf(smotion) and absf(off) >= 0.08):
			lead_ok = false
	ok(float(hs[1]) >= 1.2 * float(hs[0]), "(3) %s: hero height on screen wind-up %.2f, contact %.2f (x%.2f), recover %.2f" % [tag, hs[0], hs[1], float(hs[1]) / float(hs[0]), hs[2]])
	ok(lead_ok, "(4) %s: hero's x offset opposite the motion: %s" % [tag, " ; ".join(lead_txt)])
	if two:
		var inside := true
		var worst := 1e9
		for bi in [0, 2]:
			var s: Dictionary = sugs[bi]
			var key: Dictionary = s["key"]
			var a: float = s["cut"]
			var b: float = sugs[bi + 1]["cut"] if bi == 0 else S.length()
			for t in [float(s["t"]), lerpf(a, b, 0.0), lerpf(a, b, 0.25), lerpf(a, b, 0.5), lerpf(a, b, 0.75), lerpf(a, b, 1.0)]:
				for fgt in read(S, minf(t, S.length())):
					for p in fgt["all"]:
						var q := ShotCam.project(key["pos"], key["aim"], key["f"], FRM, p)
						worst = minf(worst, minf(minf(q.x, 1280.0 - q.x), minf(q.y, 720.0 - q.y)))
						if q.x < 0 or q.x > 1280 or q.y < 0 or q.y > 720:
							inside = false
		ok(inside, "(5) %s: both fighters fully in the wind-up and recover frames (closest body point %.0f px from an edge)" % [tag, worst])


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	var S: Scene = m.S
	# ---- one fighter
	var t0 := Time.get_ticks_usec()
	var res := AutoCam.compute(S)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	check_scene("combo3", S, res, false)
	ok(ms < 600.0, "(9) compute on combo3: %.0f ms < 600 ms" % ms)
	for s in res["sugs"]:
		print("     ", s["why"])
	# ---- two fighters
	m._actor_add()
	await idle()
	var S2: Scene = m._hero_scene()
	ok(S2.actors.size() == 1, "two-fighter scene: combo3 + a mirrored fighter 150 cm in front")
	var res2 := AutoCam.compute(S2)
	check_scene("two fighters", S2, res2, true)
	# ---- the strip, on the two-fighter scene: nothing changes until a click
	var before := JSON.stringify(m._hero_scene().to_dict(m.B, false))
	var u0: int = m.undo.size()
	m.ac_ui.show()
	await m.ac_ui.settle()
	await idle()
	ok(JSON.stringify(m._hero_scene().to_dict(m.B, false)) == before and m.undo.size() == u0, "(6) the scene JSON is byte-identical after the strip and its thumbnails (%d chars), no undo step" % before.length())
	# (8) panel
	var vp := m.get_viewport().get_visible_rect()
	var pr: Rect2 = m.ac_ui.panel.get_global_rect()
	ok(m.ac_ui.panel.visible and vp.encloses(pr), "(8) the strip is inside the window: %s in %s" % [pr, vp])
	var n_sug: int = m.ac_ui.sugs.size()
	var drawn := 0
	var rules_ok := 0
	var keep_ok := 0
	for k in n_sug:
		var tr = m.ac_ui.panel.find_child("ac_thumb_%d" % (k + 1), true, false)
		var rl = m.ac_ui.panel.find_child("ac_rule_%d" % (k + 1), true, false)
		var kb = m.ac_ui.panel.find_child("ac_keep_%d" % (k + 1), true, false)
		if tr != null and tr.texture != null:
			var img: Image = tr.texture.get_image()
			var c0 := img.get_pixel(2, 2)
			var diff := 0
			for y in range(0, img.get_height(), 4):
				for x in range(0, img.get_width(), 4):
					if absf(img.get_pixel(x, y).r - c0.r) + absf(img.get_pixel(x, y).g - c0.g) + absf(img.get_pixel(x, y).b - c0.b) > 0.1:
						diff += 1
			if diff > 40 and tr.get_global_rect().size.x >= 180:
				drawn += 1
		if rl != null and String(rl.text).begins_with("rule: ") and vp.encloses(rl.get_global_rect()):
			rules_ok += 1
		if kb != null and vp.encloses(kb.get_global_rect()):
			keep_ok += 1
	ok(drawn == n_sug and rules_ok == n_sug and keep_ok == n_sug, "(8) %d suggestions: %d thumbnails drawn (not flat), %d rule labels, %d Keep buttons, all inside the window" % [n_sug, drawn, rules_ok, keep_ok])
	# (7) keep one
	var sugs: Array = m.ac_ui.sugs
	var u1: int = m.undo.size()
	m.ac_ui.keep(1)
	await idle()
	var sh: Array = m._shot_shots()
	ok(m.undo.size() == u1 + 1 and sh.size() == 1 and absf(float(sh[0]["t"])) < 1e-6 and (sh[0]["keys"][0]["pos"] as Vector3).distance_to(sugs[1]["key"]["pos"]) < 1e-5,
		"(7) Keep (contact): one undo step (%d -> %d), %d shot, its camera is the suggested one" % [u1, m.undo.size(), sh.size()])
	m._undo()
	await idle()
	ok(JSON.stringify(m._hero_scene().to_dict(m.B, false)) == before and m._shot_shots().is_empty(), "(7) undo: the scene JSON is exact again")
	var u2: int = m.undo.size()
	m.ac_ui.keep_all()
	await idle()
	sh = m._shot_shots()
	var fps: int = m.S.fps
	var cuts_ok := sh.size() == 3
	if cuts_ok:
		cuts_ok = absf(float(sh[0]["t"])) < 1e-6
		for i in [1, 2]:
			cuts_ok = cuts_ok and absf(float(sh[i]["t"]) - roundf(float(sugs[i]["cut"]) * fps) / fps) < 1e-6
	ok(m.undo.size() == u2 + 1 and cuts_ok, "(7) Keep all: one undo step, %d shots at %s" % [sh.size(), sh.map(func(x): return snappedf(float(x["t"]), 0.001))])
	# (8) the viewport through the kept contact camera
	m.playhead = float(res2["beats"]["tc"])
	m._refresh()
	await idle()
	m._shot_toggle()
	await idle(4)
	var rect: Rect2i = m.shot_rect()
	var fc := read(m._hero_scene(), m.playhead)
	var hp: Vector2 = m.cam.unproject_position(fc[0]["top"])
	var sd: String = res2["beats"]["strike"]["hand"]
	var hd: Vector2 = m.cam.unproject_position(fc[0]["h" + sd])
	ok(m.shot_through and Rect2(rect).has_point(hp) and Rect2(rect).has_point(hd), "(8) through the contact camera: the hero's head %s and striking hand %s are inside the shot frame %s" % [hp.round(), hd.round(), rect])
	await idle(3)
	root.get_texture().get_image().save_png(TMP + "i7.png")
	m._undo()
	await idle()
	ok(JSON.stringify(m._hero_scene().to_dict(m.B, false)) == before, "(7) undo of Keep all: the scene JSON is exact again")
	print("I7 AUTO CAMERA %s" % ("FAIL" if fails > 0 else "PASS") + (" (%d failed)" % fails if fails > 0 else ""))
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
