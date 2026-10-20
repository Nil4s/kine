## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/i2_test.gd     (ROADMAP I2; a window; runs python + MuJoCo, about 1.5 min)
## THE HIT DECIDES THE REACTION (scripts/hit_physics.gd, tools/physics/react.py, the command "React to the hit (physics)").
## Bars, written before measuring:
##   1 SPEED: a bat hit to the head from the front at 10 / 20 / 30 m/s (a hit row in the struck fighter's space): the impulse J, the
##     sim's peak head rotation and its peak trunk (spine_03) rotation in the first 0.6 s all rise STRICTLY with the speed (monotone over
##     the 3 speeds), and J(20)/J(10) and J(30)/J(10) are 2 and 3 within 5 % (J = m_eff x v).
##   2 SWING.PY (step 2): at the four bat swings tools/physics/measure_swing.py measured (strike_legs 21.3 m/s -> 17.1 N s on the head,
##     swing_fore 25.5 -> 20.9, swing_back 27.4 -> 25.0, combo3 32.6 -> 35.8, all on an upper arm), the striker posed at each clip's contact,
##     our J = (1 + e) x mu x v (m_eff from the arm's pose, mu with the struck part's mass) at swing.py's speed is within 0.7-1.3 x of
##     swing.py's at all four. The effective bat mass is printed with J / v; if one is outside the bar the line says which.
##   8 ROOT (step 2): a fighter whose pelvis leans back 20 deg (and turned 30 deg) at the contact starts the sim leaning 20 +-2 deg
##     (react.py's lean0_deg = the pelvis's tilt from vertical at t = 0; the neck-pelvis line within 20 +-3) and facing 30 +-2 deg.
##   9 3D: an uppercut impulse (45 deg up) keeps the head higher (mean height over 0.3 s, centre of mass) than a horizontal one of the same |J| by more than 2 mm. First written as 'lifts by 1 cm'; arithmetic before the first run showed it cannot: 354 N up for 50 ms is less than the 735 N weight, so the feet carry it and nothing leaves the floor.
##   3 FIST: a punch at 9 m/s (Walilko et al. 2005: ~9 m/s, ~26 N s) gives J within 20-33 N s.
##   4 IN THE APP (two fighters, the hero plays combo3, fighter 2 stands D0 in front): the command finds the contact; the first reaction
##     card of fighter 2 starts moving within 1 frame (1/30 s) of the contact the test's own 1/240 s sweep finds.
##   5 ATTACKER: the hero's scene is byte-identical (JSON) after the command; fighter 2's cards before the contact keep their poses.
##   6 UNDO: one undo step; Ctrl+Z restores both scenes exactly (JSON), redo puts the reaction back exactly.
##   7 LABEL: strength word light / medium / hard and fell / stayed up are read off the cards; in the app the measured impulse label is
##     shown mid-reaction, whole inside the window, within 160 px of fighter 2's head, with the number the command measured; the contact
##     offer button is shown at the contact before the command and sits inside the window. The picture is saved.
extends SceneTree

var fails := 0
var m: Node
const D0 := 1.2
const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/i2b.png"
## swing.py duel (tools/physics/measure_swing.py, bat): [clip, struck part, speed at hit (m/s), impulse (N s), swing.py's contact time in the clip (s)]
const SWING := [["strike_legs", "head", 21.3, 17.1, 1.932], ["swing_fore", "upperarm_l", 25.5, 20.9, 0.854], ["swing_back", "upperarm_r", 27.4, 25.0, 0.589], ["combo3", "upperarm_l", 32.6, 35.8, 0.850]]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


func stand_pose() -> Dictionary:
	var b := body()
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	return b.to_dict()


func still(pose: Dictionary) -> Scene:
	var s := Scene.new()
	s.from_dict({"scene": "zz_still", "fps": 30, "cards": [{"name": "a", "pose": pose, "move": -1.0, "hold": 2.0},
		{"name": "b", "pose": pose, "move": 0.5, "hold": 3.0}]})
	return s


func strike_t(hs: Scene, fs: Scene, xf: Transform3D) -> float:
	var a := hs.clone()
	var o := fs.clone()
	var ba := body()
	var bo := body()
	var n := int(ceil(maxf(a.length(), o.length()) * 240.0))
	for i in n + 1:
		var t := i / 240.0
		a.apply(ba, t)
		o.apply(bo, t)
		for c in ba.cross_contacts(bo, xf):
			if c[3] == "hit":
				return t
	return -1.0


func sj(s: Scene) -> String:
	var d := s.to_dict(body())
	d.erase("actors")
	return JSON.stringify(d)


func screen_of(k: int, j: String) -> Vector2:
	var W: Vector3 = m._stage_xf() * (m.actors_rt[k]["xf"] as Transform3D) * ((m.actors_rt[k]["B"] as Body).P[j] as Vector3)
	return m.cam.unproject_position(W)


## a hit row as Dummy.fighter_hits gives it: the striker's part touching `on` of the standing fighter, moving along -z (toward him) at v
func front_hit(B: Body, striker_part: String, on: String, v: float, u := 0.6) -> Dictionary:
	var a: Array = B.cap(on)
	var mid := ((a[0] as Vector3) + (a[1] as Vector3)) * 0.5
	return {"t": 1.0, "kind": "hit", "zone": "X", "part": striker_part, "on": on, "by": "hero", "vs": 1, "u": u, "depth": 0.01, "speed": v,
		"at": mid + Vector3(0, 0, float(B.rad[on])), "vec": Vector3(0, 0, -v)}


func _init() -> void:
	# 4 - 7 IN THE APP
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	m.S.actors.append({"name": "fighter 2", "xf": {"pos": [0.0, D0], "yaw": 180.0}, "scene": still(stand_pose())})
	m._actors_sync()
	m._page_set("STAGE", false)
	m._refresh()
	await idle()
	var hs: Scene = m.actors_rt[0]["S"]
	var fs: Scene = m.actors_rt[1]["S"]
	var t_sweep := strike_t(hs, fs, m.actors_rt[1]["xf"])
	var row: Dictionary = m._hit_row_for(1)
	ok(m.actors_rt.size() == 2 and t_sweep > 0.0 and not row.is_empty(), "4 two fighters; the sweep finds the touch at %.4f s; the app's row: %s on %s at %.4f s" % [t_sweep, row.get("part", "?"), row.get("on", "?"), float(row.get("t", -1.0))])
	# the offer, before the command
	m._dummy_hits()
	await m.dummy_settle()
	m._hit_ui_tick()
	await idle(2)
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	var ob: Button = m.hit_offer_btn
	ok(ob != null and ob.visible and Rect2(Vector2.ZERO, vp).encloses(Rect2(ob.position, ob.size)), "7 the contact is offered: button '%s' at %s inside the %s window" % [ob.text if ob != null else "-", ob.position if ob != null else "-", vp])
	var u_real: float = float(row.get("u", 0.6))   # where on the bat the real swing lands
	# 1 SPEED
	var Bv := body()
	Bv.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	Bv.ground()
	var Sv := still(Bv.to_dict())
	var Bs: Body = m.actors_rt[0]["B"]   # the hero's own body, wielding the bat of the scene
	var Js := []
	var head := []
	var tors := []
	var m_eff := 0.0
	for v in [10.0, 20.0, 30.0]:
		var blow := HitPhysics.measure(Sv, Bv, Transform3D.IDENTITY, front_hit(Bv, "bat_barrel", "head", v, u_real), Bs, hs)
		var res := HitPhysics.work(blow, body(), "t1_%d" % int(v))
		ok(bool(blow["ok"]) and bool(res["ok"]), "bat to the head at %.0f m/s: measured and simulated (%s)" % [v, res["why"]])
		if not res["ok"]:
			print("PHYSICS FAIL")
			quit(1)
			return
		var rp: Dictionary = res["report"]
		m_eff = float(blow["m_eff"])
		Js.append(float(blow["J_h"]))
		head.append(float(rp["head_rot_deg"]))
		tors.append(float(rp["torso_rot_deg"]))
		print("     v %.0f m/s: m_eff %.3f kg, J %.2f N s (dir %.0f deg, body %s), head %.1f deg, trunk %.1f deg in 0.6 s, steps %d, fell %s | %s" % [
			v, m_eff, Js[-1], float(blow["dir_deg"]), blow["body"], head[-1], tors[-1], int(rp["steps"]), rp["fell"], HitPhysics.label(res)])
	ok(Js[0] < Js[1] and Js[1] < Js[2] and head[0] < head[1] and head[1] < head[2] and tors[0] < tors[1] and tors[1] < tors[2],
		"1 monotone over 10 / 20 / 30 m/s: J %s, head rotation %s, trunk rotation %s" % [Js.map(func(x): return snappedf(x, 0.1)), head.map(func(x): return snappedf(x, 0.1)), tors.map(func(x): return snappedf(x, 0.1))])
	ok(absf(Js[1] / Js[0] - 2.0) <= 0.1 and absf(Js[2] / Js[0] - 3.0) <= 0.15, "1 J is linear in the speed: x%.3f at 2x, x%.3f at 3x" % [Js[1] / Js[0], Js[2] / Js[0]])

	# 2 SWING.PY
	var worst := 0.0
	var lines := []
	var Bst := body()
	Bst.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	var in_bar := true
	for sw in SWING:
		var sc := Scene.new()
		sc.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/%s.json" % sw[0])))
		var Ba := body()
		var tb := 0.0
		var vb := 0.0
		var dirb := Vector3.ZERO
		for i in range(-24, 13):   # the fastest barrel point within the clip's contact time +-0.1 s
			var tt: float = float(sw[4]) + i / 240.0
			sc.apply(Ba, tt - 1.0 / 240.0)
			var p0 := Ba.wep_point(0.7 * Ba.wep_len)
			sc.apply(Ba, tt)
			var dv := (Ba.wep_point(0.7 * Ba.wep_len) - p0) * 240.0
			if dv.length() > vb:
				vb = dv.length()
				tb = tt
				dirb = dv.normalized()
		sc.apply(Ba, tb)
		var me := HitPhysics.arm_mass(Ba, Ba.wep_point(0.7 * Ba.wep_len), dirb)
		var Mt := HitPhysics.struck_mass(String(sw[1]), Bst)
		var mu := me * Mt / (me + Mt)
		var mine: float = (1.0 + HitPhysics.RESTITUTION) * mu * float(sw[2])
		var ratio: float = mine / float(sw[3])
		worst = maxf(worst, absf(ratio - 1.0))
		lines.append("%s %.1f m/s (Kine's own barrel peak %.1f at %.3f s): m_eff %.2f kg, struck %s %.1f kg, mu %.2f, J/v ours %.2f vs swing.py %.2f kg, ours %.1f vs %.1f N s (x%.2f)" % [
			sw[0], sw[2], vb, tb, me, sw[1], Mt, mu, mine / float(sw[2]), float(sw[3]) / float(sw[2]), mine, sw[3], ratio])
		if ratio < 0.7 or ratio > 1.3:
			in_bar = false
			ok(false, "2 outside 0.7-1.3 x of swing.py: %s" % sw[0])
	for l in lines:
		print("     " + l)
	ok(in_bar, "2 our J is within 0.7-1.3 x of swing.py's at all 4 bat speeds (worst %.0f %% off)" % (worst * 100.0))

	# 3 FIST
	var fb := HitPhysics.measure(Sv, Bv, Transform3D.IDENTITY, front_hit(Bv, "hand_r", "spine_03", 9.0, u_real), Bs)
	ok(bool(fb["ok"]) and float(fb["J_h"]) >= 20.0 and float(fb["J_h"]) <= 33.0, "3 fist at 9 m/s: m_eff %.2f kg, J %.1f N s (Walilko 2005: ~26 N s; bar 20-33)" % [float(fb["m_eff"]), float(fb["J_h"])])

	var hero0 := sj(hs)
	var f0 := sj(fs)
	var cards0: Array = fs.cards.duplicate(true)
	var ts0 := fs.times()
	var u0: int = m.undo.size()
	m._react_physics(1)
	for i in 1200:   # the worker: python + the importer (about 15 s)
		await process_frame
		if not m._imp_busy():
			break
	await idle(3)
	ok(not m.hit_info.is_empty(), "4 the physics reaction landed (%s)" % [m.hit_info.get("text", "no result")])
	if m.hit_info.is_empty():
		print("I2 TEST FAIL (no result)")
		quit(1)
		return
	var vs: Scene = m.actors_rt[1]["S"]
	var ts := vs.times()
	var keep := 0
	for i in cards0.size():
		if float(ts0[i][1]) <= m.hit_info["t0"] + 1e-9:
			keep = i + 1
	var arr: float = float(ts[keep][0])
	ok(absf(arr - t_sweep) <= 1.0 / 30.0 + 1e-9, "4 the first reaction card starts moving at %.4f s; the contact (sweep) is %.4f s: %.1f ms apart (bar one frame, 33.3 ms)" % [arr, t_sweep, absf(arr - t_sweep) * 1000.0])
	# 5 ATTACKER
	var before_ok := true
	for i in keep:
		before_ok = before_ok and JSON.stringify(vs.cards[i]["pose"]) == JSON.stringify(cards0[i]["pose"])
	ok(sj(m.actors_rt[0]["S"]) == hero0 and before_ok and vs.cards.size() != cards0.size(), "5 the attacker's scene is byte-identical; fighter 2's %d cards before the contact keep their poses; cards %d -> %d" % [keep, cards0.size(), vs.cards.size()])
	# 7 LABEL (strength words) and the picture
	var res: Dictionary = m.hit_info["res"]
	var inf: Dictionary = res["info"]
	ok(["light", "medium", "hard"].has(inf["strength"]) and inf.has("fell"), "7 the strength label read off the cards: %s" % HitPhysics.label(res))
	m._view(2)
	m.dist = 5.5
	m.target = Vector3(0, 0.9, -0.6)
	var t_show: float = float(m.hit_info["t0"]) + 0.35
	m.playhead = t_show
	m.playing = false
	m._ps().apply(m.B, t_show)
	m._refresh()
	await idle(3)
	m._hit_ui_tick()
	await idle(2)
	m._hit_ui_tick()
	await RenderingServer.frame_post_draw
	var lb: Label = m.hit_label
	var lrect := Rect2(lb.position, lb.size)
	var hp := screen_of(1, "head")
	var near := absf((lrect.position.x + lrect.size.x * 0.5) - hp.x) <= 160.0 and absf((lrect.position.y + lrect.size.y) - hp.y) <= 160.0 and not lrect.has_point(hp)
	var Jtxt: String = "%.1f N s" % float(res["blow"]["J_h"])
	ok(lb != null and lb.visible and lb.text.contains(Jtxt) and Rect2(Vector2.ZERO, vp).encloses(lrect) and near, "7 label '%s' shown mid-reaction at %s, inside the window %s, near the head %s (head at %s)" % [lb.text if lb != null else "-", lrect, Rect2(Vector2.ZERO, vp).encloses(lrect), near, hp])
	var bodies_clear := true
	for k in 2:
		for j in ["pelvis", "head"]:
			if lrect.has_point(screen_of(k, j)):
				bodies_clear = false
	ok(bodies_clear, "7 placement: the label covers no fighter's pelvis or head")
	DirAccess.make_dir_recursive_absolute(SHOT.get_base_dir())
	var img: Image = m.get_viewport().get_texture().get_image()
	ok(img.save_png(SHOT) == OK, "7 picture saved: %s" % SHOT)
	# 6 UNDO
	var steps: int = m.undo.size() - u0
	var after := sj(vs)
	m._undo()
	await idle()
	ok(steps == 1 and sj(m.actors_rt[1]["S"]) == f0 and sj(m.actors_rt[0]["S"]) == hero0, "6 one undo step (%d); Ctrl+Z restores fighter 2 exactly (%s) and the hero (%s)" % [steps, sj(m.actors_rt[1]["S"]) == f0, sj(m.actors_rt[0]["S"]) == hero0])
	m._redo()
	await idle()
	ok(sj(m.actors_rt[1]["S"]) == after, "6 redo puts the reaction back exactly")
	# 8 ROOT: upright (the baseline), 20 deg back, and turned 30 deg
	var pb := stand_pose()
	var pl := stand_pose()
	var pt := stand_pose()
	var ql := Quaternion(Vector3.RIGHT, deg_to_rad(-20.0))
	var qy := Quaternion(Vector3.UP, deg_to_rad(30.0))
	pl["joints"]["pelvis"]["G"] = [ql.x, ql.y, ql.z, ql.w]
	pt["joints"]["pelvis"]["G"] = [qy.x, qy.y, qy.z, qy.w]
	var r8 := []
	for pp in [pb, pl, pt]:
		r8.append(HitPhysics.simulate({"pose": pp, "body": "head", "J_h": 5.0, "J_v": 0.0, "dir_deg": 0.0}, "t8"))
	if r8[0]["ok"] and r8[1]["ok"] and r8[2]["ok"]:
		var b0: Dictionary = r8[0]["report"]
		var b1: Dictionary = r8[1]["report"]
		var b2: Dictionary = r8[2]["report"]
		var dline: float = float(b0["trunk_lean_signed0"]) - float(b1["trunk_lean_signed0"])
		ok(absf(float(b1["lean0_deg"]) - 20.0) <= 2.0 and absf(dline - 20.0) <= 2.0 and absf(absf(float(b2["yaw0_deg"])) - 30.0) <= 2.0,
			"8 the sim starts leaning %.1f deg (pelvis tilt; upright %.1f), the neck-pelvis line leans %.1f deg more back than upright's (%.1f -> %.1f), and a fighter turned 30 deg faces %.1f deg: bars 20 +-2, 20 +-2, 30 +-2" % [
			float(b1["lean0_deg"]), float(b0["lean0_deg"]), dline, float(b0["trunk_lean_signed0"]), float(b1["trunk_lean_signed0"]), float(b2["yaw0_deg"])])
	else:
		ok(false, "8 simulated (%s)" % [r8.map(func(x): return x["why"])])
	# 9 3D: the same |J| = 25 N s on the head, horizontal vs 45 deg up
	var ps := stand_pose()
	var rh := HitPhysics.simulate({"pose": ps, "body": "head", "J_h": 25.0, "J_v": 0.0, "dir_deg": 0.0}, "t9h")
	var ru := HitPhysics.simulate({"pose": ps, "body": "head", "J_h": 25.0 * cos(deg_to_rad(45.0)), "J_v": 25.0 * sin(deg_to_rad(45.0)), "dir_deg": 0.0}, "t9u")
	if rh["ok"] and ru["ok"]:
		var uh: float = float(rh["report"]["head_dy_mean_m"])
		var uu: float = float(ru["report"]["head_dy_mean_m"])
		ok(uu > uh + 0.002, "9 the head's centre is on average %+.4f m from where it was over 0.3 s after the uppercut (peak rise %.4f m, lowest %+.4f) vs %+.4f m after the horizontal blow (peak %.4f, lowest %+.4f) at the same |J| (bar: higher on average by > 2 mm; a rise above the start is not expected, a force under the body's weight cannot lift it: 17.7 N s up is 354 N for 50 ms < 735 N)" % [
			uu, float(ru["report"]["head_up_m"]), float(ru["report"]["head_dy_min_m"]), uh, float(rh["report"]["head_up_m"]), float(rh["report"]["head_dy_min_m"])])
	else:
		ok(false, "9 simulated (%s %s)" % [rh["why"], ru["why"]])
	print("I2 TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
