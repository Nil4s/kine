## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/i3_test.gd     (Innovations I3; a window)
## COUNTER SUGGESTION (scripts/counter.gd, counter_ui.gd; the command "Counter: suggest the defender's block, slip and parry").
## Two fighters in the app: the hero attacks with a free bat, fighter 2 stands 1.2 m away facing it. Two attacks, each as
## its own scene: a straight THRUST at the head and an OVERHEAD swing down onto it. The tip's path is re-measured here
## from the scene itself (Scene.apply + Body.wep_point, 1/120 s), not read from Counter. Bars, written before the numbers:
##   1 BLOCK (both attacks): the ghost's forearm AXIS passes within 3 cm of the path point at the ghost's intercept
##     time, and within 3 cm of the path anywhere; its axis is within 20 deg of square to the tip's velocity there.
##   2 SLIP (both): the ghost's head clears the path (head axis to the tip, minus the head radius) by >= 10 cm over the
##     whole path to 0.12 s past the contact; the centre of mass is inside the support (Balance margin >= 0); both feet
##     still on their marks (ball within 1.5 cm); the torso parts clear it by >= 10 cm too.
##   3 LIMITS: every ghost's every joint is inside its limits (Body.clamp_ang changes nothing, 1e-3 deg).
##   4 PARRY (both): the forearm axis within 3 cm of the path at its time, the tip deflected >= 20 deg, the contact
##     gap (weapon line to forearm surface) <= 2 cm.
##   5 UNCHANGED: while the ghosts show, both fighters' cards (JSON) and bodies' angles are identical to before.
##   6 ACCEPT: Enter places the picked ghost: ONE undo step; the defender's cards change; the new card replays the ghost's
##     forearm within 2 cm; Ctrl+Z restores the defender's cards exactly and the undo list. Tab cycles through all ghosts.
##   7 PLACEMENT: mid-swing, the 3 ghosts stand on the defender (node at its placement, pelvis within 0.5 m of its own,
##     head inside the window), each label on screen; then the screenshot.
extends SceneTree

var fails := 0
var m: Node
const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/i3.png"
const DXF_POS := [0.0, 1.2]
var dxf := Transform3D.IDENTITY


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
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	return b


## a card's pose: the stand pose with a free bat (not in a hand), its tip at `tip`, pointing along dir
func bat_pose(tip: Vector3, dir: Vector3) -> Dictionary:
	var b := body()
	var L := b.wep_len
	var d := dir.normalized()
	b.wep_on = true
	b.wep_hand = ""
	b.wep_pos = tip - d * L
	b.wep_rot = Quaternion(Vector3.UP, d)
	return b.to_dict()


## the attacker: [[tip, dir, move, hold], ...]
func attacker(cards: Array) -> Scene:
	var cs := []
	for i in cards.size():
		var c: Array = cards[i]
		cs.append({"name": "a%d" % i, "pose": bat_pose(c[0], c[1]), "move": -1.0 if i == 0 else float(c[2]), "hold": float(c[3])})
	var s := Scene.new()
	s.from_dict({"scene": "zz_i3_attacker", "fps": 30, "cards": cs})
	return s


func stand_scene() -> Scene:
	var pose := body().to_dict()
	var s := Scene.new()
	s.from_dict({"scene": "zz_i3_stand", "fps": 30, "cards": [{"name": "a", "pose": pose, "move": -1.0, "hold": 2.0},
		{"name": "b", "pose": pose, "move": 0.5, "hold": 3.0}]})
	return s


func thrust() -> Scene:
	return attacker([[Vector3(0.1, 1.6, 0.45), Vector3(0, 0.05, 1), 0, 0.5], [Vector3(0.0, 1.6, 1.35), Vector3(0, 0.05, 1), 0.4, 0.5]])


func overhead() -> Scene:
	return attacker([[Vector3(0, 2.3, 0.25), Vector3(0, 0.85, -0.5), 0, 0.5], [Vector3(0, 1.2, 1.0), Vector3(0, -0.5, 0.85), 0.8, 0.5]])


func tip_at(S: Scene, t: float) -> Vector3:
	var b := body()
	S.apply(b, t)
	return b.wep_point(b.wep_len)


## the path re-measured: tips at 1/120 s over the proposal's window
func my_path(S: Scene, P: Dictionary) -> Array:
	var out := []
	for t in P["ts"]:
		out.append(tip_at(S, float(t)))
	return out


func seg_d(p: Vector3, a: Vector3, b: Vector3) -> float:
	return Body.seg_seg(p, p, a, b)


func path_min(pts: Array, a: Vector3, b: Vector3) -> float:
	var d := INF
	for q in pts:
		d = minf(d, seg_d(q, a, b))
	return d


func prop(r: Dictionary, kind: String) -> Dictionary:
	for p in r["list"]:
		if String(p["kind"]) == kind or (kind == "SLIP" and String(p["kind"]) in ["DUCK", "STAY"]):
			return p
	return {}


func _init() -> void:
	dxf = Transform3D(Basis(Vector3.UP, deg_to_rad(180.0)), Vector3(DXF_POS[0], 0.0, DXF_POS[1]))
	var DS := stand_scene()
	var results := {}
	for name in ["thrust", "overhead"]:
		var AS: Scene = thrust() if name == "thrust" else overhead()
		var t0 := Time.get_ticks_msec()
		var r := Counter.suggest(AS, Transform3D.IDENTITY, DS, dxf, 0.7)
		print("     %s: suggest took %d ms" % [name, Time.get_ticks_msec() - t0])
		results[name] = r
		ok(bool(r["ok"]), "%s: a strike was found (contact at %.3f s, tip %s)" % [name, float(r["path"].get("tc", -1)), "inside the body" if bool(r["path"].get("contact", false)) else "no contact: card arrival"])
		if not bool(r["ok"]):
			print("     ", r["why"])
			continue
		var P: Dictionary = r["path"]
		var mine := my_path(AS, P)
		for p in r["list"]:
			print("     ", String(p["label"]).replace("\n", " | "))
		# 1 BLOCK
		var bl := prop(r, "BLOCK")
		ok(bool(bl.get("ok", false)), "%s BLOCK: found" % name)
		if bool(bl.get("ok", false)):
			var Gb: Body = bl["B"]
			var c: Array = Gb.cap("lowerarm" + String(bl["side"]))
			var fa: Vector3 = dxf * (c[0] as Vector3)
			var fb: Vector3 = dxf * (c[1] as Vector3)
			var tx := float(bl["tx"])
			var d_x := seg_d(tip_at(AS, tx), fa, fb)
			var d_any := path_min(mine, fa, fb)
			var v := (tip_at(AS, tx + 1.0 / 240.0) - tip_at(AS, tx - 1.0 / 240.0)) * 120.0
			var ang := rad_to_deg(acos(clampf(absf((fb - fa).normalized().dot(v.normalized())), 0.0, 1.0)))
			print("     BLOCK: forearm to the path at t=%.3f: %.2f cm; to the path anywhere %.2f cm; angle to velocity %.1f deg" % [tx, d_x * 100.0, d_any * 100.0, ang])
			ok(d_x <= 0.03, "%s BLOCK: forearm axis %.2f cm from the path at the intercept frame (<= 3)" % [name, d_x * 100.0])
			ok(d_any <= 0.03, "%s BLOCK: forearm axis %.2f cm from the path anywhere (<= 3)" % [name, d_any * 100.0])
			ok(absf(ang - 90.0) <= 20.0, "%s BLOCK: forearm %.1f deg to the velocity (square +-20)" % [name, ang])
		# 2 SLIP
		var sl := prop(r, "SLIP")
		ok(bool(sl.get("ok", false)), "%s SLIP: found (%s)" % [name, sl.get("kind", "")])
		if bool(sl.get("ok", false)):
			var Gs: Body = sl["B"]
			var hc: Array = Gs.cap("head")
			var ha: Vector3 = dxf * (hc[0] as Vector3)
			var hb: Vector3 = dxf * (hc[1] as Vector3)
			var clear := path_min(mine, ha, hb) - float(Gs.rad["head"])
			var tor := INF
			for part in ["spine_03", "spine_02"]:
				var cc: Array = Gs.cap(part)
				tor = minf(tor, path_min(mine, dxf * (cc[0] as Vector3), dxf * (cc[1] as Vector3)) - float(Gs.rad[part]))
			var bal := Balance.read(Gs)
			var G0 := Counter.ghost(DS, float(P["tc"]))
			var foot := 0.0
			for sd in ["_l", "_r"]:
				foot = maxf(foot, ((G0.P["ball" + sd] as Vector3) - (Gs.P["ball" + sd] as Vector3)).length())
			print("     SLIP: head clear %.1f cm, torso %.1f cm, COM margin %.1f cm, feet moved %.2f cm, head moved %.0f cm (%s)" % [clear * 100.0, tor * 100.0, float(bal["margin"]) * 100.0, foot * 100.0, float(sl["move"]) * 100.0, sl["kind"]])
			ok(clear >= 0.10, "%s SLIP: head clears the path by %.1f cm (>= 10)" % [name, clear * 100.0])
			ok(tor >= 0.10, "%s SLIP: torso clears it by %.1f cm (>= 10)" % [name, tor * 100.0])
			ok(float(bal["margin"]) >= 0.0 and (bal["down"] as Array).size() == 2, "%s SLIP: centre of mass %.1f cm inside the support, both feet down" % [name, float(bal["margin"]) * 100.0])
			ok(foot <= 0.015, "%s SLIP: feet stay on their marks (%.2f cm)" % [name, foot * 100.0])
		# 4 PARRY
		var pa := prop(r, "PARRY")
		ok(bool(pa.get("ok", false)), "%s PARRY: found" % name)
		if bool(pa.get("ok", false)):
			var Gp: Body = pa["B"]
			var c2: Array = Gp.cap("lowerarm" + String(pa["side"]))
			var d_p := seg_d(tip_at(AS, float(pa["tx"])), dxf * (c2[0] as Vector3), dxf * (c2[1] as Vector3))
			print("     PARRY: forearm to the path %.2f cm, deflects %.0f deg, gap %.1f cm" % [d_p * 100.0, float(pa["deflect"]), float(pa["gap"]) * 100.0])
			ok(d_p <= 0.03, "%s PARRY: forearm %.2f cm from the path at its time (<= 3)" % [name, d_p * 100.0])
			ok(float(pa["deflect"]) >= 20.0, "%s PARRY: the tip is deflected %.0f deg (>= 20)" % [name, float(pa["deflect"])])
			ok(float(pa["gap"]) <= 0.02, "%s PARRY: contact gap %.1f cm (<= 2)" % [name, float(pa["gap"]) * 100.0])
		# 3 LIMITS
		var worst := 0.0
		for p in r["list"]:
			if not bool(p["ok"]):
				continue
			var Gx: Body = p["B"]
			for j in Body.ORDER:
				var a: Vector3 = Gx.ang[j]
				var cl: Vector3 = Gx.clamp_ang(j, a)
				worst = maxf(worst, maxf(absf(a.x - cl.x), maxf(absf(a.y - cl.y), absf(a.z - cl.z))))
		ok(worst < 1e-3, "%s: every ghost inside its joint limits (worst %.6f deg)" % [name, worst])

	# the app: 5 UNCHANGED, 6 ACCEPT, 7 PLACEMENT
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m._load_scene("res://scenes/combo3.json")   # read only: nothing is written to scenes/
	var AS2 := overhead()
	m.S.from_dict({"scene": "zz_i3_hero", "fps": 30, "cards": AS2.cards})
	m._rebuild_cards()
	print("     playing: ", m.S.cards.size(), " cards")
	m.S.actors.append({"name": "fighter 2", "xf": {"pos": DXF_POS, "yaw": 180.0}, "scene": stand_scene()})
	m._actors_sync()
	m._refresh()
	await idle()
	ok(m._fighters_on() and m.actors_rt.size() == 2, "two fighters in the app")
	m.playhead = 0.72
	m._ps().apply(m.B, m.playhead)
	m.yaw = 90.0
	m.pitch = -6.0
	m.dist = 5.2
	m.target = Vector3(0.0, 1.15, 0.65)
	m._cam()
	m._refresh()
	await idle(2)
	var D0: Scene = m.actors_rt[1]["S"]
	var before := [JSON.stringify(m.actors_rt[0]["S"].cards), JSON.stringify(D0.cards), JSON.stringify((m.actors_rt[1]["B"] as Body).to_dict()), JSON.stringify((m.actors_rt[0]["B"] as Body).to_dict())]
	var n0: int = m.undo.size()
	var rr: Dictionary = m.counter_ui.start()
	ok(bool(rr.get("ok", false)) and m.counter_ui.on and m.counter_ui.shown.size() == 3, "the command shows 3 ghosts (%d)" % m.counter_ui.shown.size())
	await idle(3)
	var after := [JSON.stringify(m.actors_rt[0]["S"].cards), JSON.stringify(m.actors_rt[1]["S"].cards), JSON.stringify((m.actors_rt[1]["B"] as Body).to_dict()), JSON.stringify((m.actors_rt[0]["B"] as Body).to_dict())]
	ok(before == after and m.undo.size() == n0, "5 UNCHANGED: cards and bodies identical while the ghosts show, no undo step")

	# 7 PLACEMENT
	var cui = m.counter_ui
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	var dnode_ok := true
	var near_ok := true
	var on_screen := true
	var dpel: Vector3 = m.actors_rt[1]["xf"] * (m.actors_rt[1]["B"].P["pelvis"] as Vector3)
	for i in cui.shown.size():
		var g: Dictionary = cui._men[i]
		var nd: Node3D = g["node"]
		if not nd.visible or nd.transform.origin.distance_to((m.actors_rt[1]["xf"] as Transform3D).origin) > 1e-3:
			dnode_ok = false
		var Gp: Body = cui.shown[i]["B"]
		var pel: Vector3 = (m.actors_rt[1]["xf"] as Transform3D) * (Gp.P["pelvis"] as Vector3)
		if pel.distance_to(dpel) > 0.5:
			near_ok = false
		var hp: Vector3 = m.stage_root.global_transform * ((m.actors_rt[1]["xf"] as Transform3D) * (Gp.P["head"] as Vector3))
		var lp: Vector3 = (g["label"] as Label3D).global_position
		for q in [hp, lp]:
			var sp: Vector2 = m.cam.unproject_position(q)
			if sp.x < 0 or sp.y < 0 or sp.x > vp.x or sp.y > vp.y or m.cam.is_position_behind(q):
				on_screen = false
		print("     ghost %d %s: label at %s" % [i, cui.shown[i]["kind"], m.cam.unproject_position(lp)])
	ok(dnode_ok, "7 PLACEMENT: each ghost node is visible at the defender's placement")
	ok(near_ok, "7 PLACEMENT: each ghost's pelvis within 0.5 m of the defender's own")
	ok(on_screen, "7 PLACEMENT: every ghost's head and label are inside the window (%s)" % vp)
	var img: Image = m.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(SHOT.get_base_dir())
	var e := img.save_png(SHOT)
	ok(e == OK and img.get_width() > 0, "screenshot saved to %s (error %d, %dx%d)" % [SHOT, e, img.get_width(), img.get_height()])

	# 6 ACCEPT: Tab cycles, Enter places
	var k0: int = cui.sel
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	m._unhandled_input(tab)
	ok(cui.sel == (k0 + 1) % cui.shown.size(), "Tab picks the next ghost (%d -> %d)" % [k0, cui.sel])
	m._unhandled_input(tab)
	m._unhandled_input(tab)
	ok(cui.sel == k0, "Tab cycles back after %d presses" % cui.shown.size())
	for i in cui.shown.size():
		if String(cui.shown[i]["kind"]) == "BLOCK":
			cui.sel = i
	var pick: Dictionary = cui.shown[cui.sel]
	var dcards := JSON.stringify(m.actors_rt[1]["S"].cards)
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	m._unhandled_input(enter)
	ok(m.undo.size() == n0 + 1, "6 ACCEPT: Enter is ONE undo step (%d -> %d)" % [n0, m.undo.size()])
	var dnow := JSON.stringify(m.actors_rt[1]["S"].cards)
	ok(dnow != dcards and not cui.on, "6 ACCEPT: the defender's cards changed and the ghosts are put away")
	# the new card replays the ghost
	var Bx := Counter.scratch(m.actors_rt[1]["S"])
	(m.actors_rt[1]["S"] as Scene).apply(Bx, float(pick["t"]))
	var cc: Array = Bx.cap("lowerarm" + String(pick["side"]))
	var cg: Array = (pick["B"] as Body).cap("lowerarm" + String(pick["side"]))
	var rep := maxf(((cc[0] as Vector3) - (cg[0] as Vector3)).length(), ((cc[1] as Vector3) - (cg[1] as Vector3)).length())
	ok(rep <= 0.02, "6 ACCEPT: the card replays the ghost's forearm within %.2f cm (<= 2)" % [rep * 100.0])
	m._undo()
	ok(JSON.stringify(m.actors_rt[1]["S"].cards) == dcards and m.undo.size() == n0, "6 ACCEPT: Ctrl+Z restores the defender's cards exactly and the undo list")
	print("fails: ", fails)
	quit(1 if fails > 0 else 0)
