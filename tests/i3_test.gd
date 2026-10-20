## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/i3_test.gd     (Innovations I3; a window)
## COUNTER SUGGESTION (scripts/counter.gd, counter_ui.gd; the command "Counter: suggest the defender's block, slip and parry").
## THE FIXTURE is a REAL strike: scenes/combo3.json (read only), its CONTACT card (card 3: the bat swing), the hero with
## its bat in hand; fighter 2 (a stand pose, facing the hero) is put where the swing lands: the first of a short list of
## spots at which the bat tip really gets inside its body (Choreo.surface_gap <= 0) and >= 2 counters are found.
## Bars, written before the numbers:
##   1 FOUND: >= 2 counters on the real strike; the tip path is re-measured here (Scene.apply + Body.wep_point, 1/120 s).
##   2 BLOCK / PARRY: the forearm axis within 3 cm of the path at its time; the tip there is >= 5 cm in front of the head
##     and torso surfaces (the weapon is stopped before it arrives); a BLOCK's forearm within 20 deg of square to the velocity.
##     SLIP / DUCK: head clears the path by >= 10 cm; centre of mass inside the support; both feet down.
##   3 REACTION: every counter's movement STARTS (time - Counter.MV) >= 0.2 s after the wind-up begins (the move into the
##     card before the strike), measured from the scene's own card times.
##   4 LIMITS: every ghost's every joint is inside its limits (Body.clamp_ang changes nothing, 1e-3 deg).
##   5 UNCHANGED: while the ghosts show, both fighters' cards (JSON) and bodies' angles are identical to before.
##   6 ACCEPT: Tab cycles; Enter places the picked ghost: ONE undo step; the defender's cards change; the new card replays
##     the ghost's forearm within 2 cm; Ctrl+Z restores the defender's cards exactly and the undo list.
##   7 MISS: a defender out of reach: "nothing to counter", no ghosts.
##   9 STEP-BACK (step 2): on combo3 card 3 >= 3 counter kinds (block, parry, step-back). The step-back starts >= 0.2 s after the
##     wind-up (+ the 0.2 s step), the pinned foot's ball stays within 1 cm of its mark (plant slide < 1 cm), the root ends
##     >= 90 % of the step further from the attacker's root, the re-measured tip path misses every body capsule by >= 5 cm
##     (tip radius included), centre of mass inside the support, both feet down, joints inside limits.
##  10 DUCK: a head-height horizontal swing (a free bat swept sideways through the head): a DUCK whose head clears the
##     re-measured path by >= 5 cm (the bat's radius included), weight inside the feet, feet kept, limits.
##  11 LABELS: no label rectangle overlaps another label or the defender's name tag, all inside the window; every kind placed
##     (block, parry, step-back) is ONE undo step that Ctrl+Z restores.
##   8 PLACEMENT: near the contact, the ghosts stand on the defender (node at its placement, pelvis within 0.5 m of its own,
##     head and label inside the window), then the screenshot.
extends SceneTree

var fails := 0
var m: Node
const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/i3d.png"
const SPOTS := [[0.4, 1.1], [0.6, 0.9], [0.4, 0.9], [0.0, 1.1], [0.6, 1.1], [0.2, 1.1]]
var DXF_POS := [0.0, 1.2]
var t_play := 0.0
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


func hero() -> Scene:
	var s := Scene.new()
	s.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	return s


func xf_at(x: float, z: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(180.0)), Vector3(x, 0.0, z))


## the bat swept sideways through a head: a free bat held level at head height, tip at the head's depth
func swing() -> Scene:
	return attacker([[Vector3(1.0, 1.62, 1.2), Vector3(0, 0, 1), 0, 0.2], [Vector3(1.0, 1.62, 1.2), Vector3(0, 0, 1), 0.3, 0.3],
		[Vector3(-1.0, 1.62, 1.2), Vector3(0, 0, 1), 0.35, 0.5]])


func step_checks(p: Dictionary, G: Body, AS: Scene, DS: Scene, P: Dictionary, t_read: float) -> void:
	var start := float(p["start"])
	ok(start >= t_read + 0.2 - 1e-6, "STEP-BACK REACTION: the step starts %.3f s = %.3f s after the wind-up begins (>= 0.2)" % [start, start - t_read])
	ok(float(p["t"]) - start >= Counter.STEP_MV - 1e-6, "STEP-BACK: the step takes %.2f s to be in place" % (float(p["t"]) - start))
	var G0 := Counter.ghost(DS, float(p["t"]))
	var pin := String(p["pinned"])
	var slide := ((G.P["ball" + pin] as Vector3) - (G0.P["ball" + pin] as Vector3)).length()
	ok(slide < 0.01, "STEP-BACK: the pinned foot (%s) slid %.2f cm (< 1)" % [pin, slide * 100.0])
	var st := String(p["step"])
	var landed := ((G.P["ball" + st] as Vector3) - (G0.P["ball" + st] as Vector3)).length()
	ok(absf(landed - float(p["shift"])) < 0.01, "STEP-BACK: the stepping foot (%s) lands %.1f cm on, the step is %.1f cm" % [st, landed * 100.0, float(p["shift"]) * 100.0])
	var aroot: Vector3 = P["root"]
	var d0 := Vector2((dxf * (G0.P["pelvis"] as Vector3)).x - aroot.x, (dxf * (G0.P["pelvis"] as Vector3)).z - aroot.z).length()
	var d1 := Vector2((dxf * (G.P["pelvis"] as Vector3)).x - aroot.x, (dxf * (G.P["pelvis"] as Vector3)).z - aroot.z).length()
	ok(d1 - d0 >= 0.9 * float(p["shift"]), "STEP-BACK: the root is %.1f cm further from the attacker (step %.1f cm, >= 90 %%)" % [(d1 - d0) * 100.0, float(p["shift"]) * 100.0])
	var mine := my_path(AS, P)
	var ts: Array = P["ts"]
	var worst := INF
	for i in ts.size():
		if float(ts[i]) < float(p["t"]) - 1e-6:
			continue
		for part in Counter.BODY:
			var cc: Array = G.cap(part)
			worst = minf(worst, seg_d(mine[i], dxf * (cc[0] as Vector3), dxf * (cc[1] as Vector3)) - float(G.rad[part]) - float(P["r"]))
	ok(worst >= 0.05, "STEP-BACK: the re-measured tip misses every body capsule by %.1f cm once in place (>= 5; the bat's radius included)" % (worst * 100.0))
	var bal := Balance.read(G)
	ok(float(bal["margin"]) >= 0.0 and (bal["down"] as Array).size() == 2, "STEP-BACK: centre of mass inside the support (%.1f cm), both feet down" % (float(bal["margin"]) * 100.0))


func duck_checks() -> void:
	var SW := swing()
	var DS := stand_scene()
	var ts := SW.times()
	var tp := float(ts[2][1]) - 0.06
	var dx := xf_at(0.0, 1.2)
	var r := Counter.suggest(SW, Transform3D.IDENTITY, DS, dx, tp)
	ok(bool(r["ok"]), "10 DUCK fixture: the head-height swing lands (%s)" % String(r.get("why", "")))
	if not bool(r["ok"]):
		return
	for p in r["list"]:
		print("     swing: ", String(p["label"]).replace("\n", " | "))
	var d := {}
	for p in r["list"]:
		if String(p["kind"]) == "DUCK" and bool(p["ok"]):
			d = p
	ok(not d.is_empty(), "10 DUCK: a duck is proposed for the head-height swing")
	if d.is_empty():
		return
	var G: Body = d["B"]
	var mine := my_path(SW, r["path"])
	var hc: Array = G.cap("head")
	var clear := INF
	for q in mine:
		clear = minf(clear, seg_d(q, dx * (hc[0] as Vector3), dx * (hc[1] as Vector3)) - float(G.rad["head"]) - float(r["path"]["r"]))
	ok(clear >= 0.05, "10 DUCK: the head clears the re-measured path by %.1f cm (>= 5, the bat's radius included)" % (clear * 100.0))
	var bal := Balance.read(G)
	ok(float(bal["margin"]) >= 0.0 and (bal["down"] as Array).size() == 2, "10 DUCK: centre of mass inside the support, both feet down")
	var G0 := Counter.ghost(DS, float(d["t"]))
	var fs := maxf(((G.P["ball_l"] as Vector3) - (G0.P["ball_l"] as Vector3)).length(), ((G.P["ball_r"] as Vector3) - (G0.P["ball_r"] as Vector3)).length())
	ok(fs < 0.015, "10 DUCK: both feet kept on their marks (%.2f cm)" % (fs * 100.0))
	var worst := 0.0
	for j in Body.ORDER:
		var a: Vector3 = G.ang[j]
		var cl: Vector3 = G.clamp_ang(j, a)
		worst = maxf(worst, maxf(absf(a.x - cl.x), maxf(absf(a.y - cl.y), absf(a.z - cl.z))))
	ok(worst < 1e-3, "10 DUCK: inside its joint limits (worst %.6f deg)" % worst)
	ok(float(d["start"]) >= float(r["path"]["t_read"]) + 0.2 - 1e-6, "10 DUCK REACTION: starts %.3f s" % float(d["start"]))
	print("     duck drops the head %.1f cm" % (float(d["move"]) * 100.0))


func _init() -> void:
	var AS := hero()
	var DS := stand_scene()
	var ts := AS.times()
	var ci := 2
	var t_read := float(ts[ci - 1][0])
	t_play = float(ts[ci][1]) - 0.06
	var r := {}
	var found := false
	for sp in SPOTS:
		DXF_POS = sp
		dxf = xf_at(sp[0], sp[1])
		var t0 := Time.get_ticks_msec()
		r = Counter.suggest(AS, Transform3D.IDENTITY, DS, dxf, t_play)
		var n := 0
		for p in r["list"]:
			if bool(p["ok"]):
				n += 1
		print("     spot %s: ok=%s, %d counters, %d ms" % [sp, str(r["ok"]), n, Time.get_ticks_msec() - t0])
		if bool(r["ok"]) and bool(r["path"]["contact"]) and n >= 3:
			found = true
			break
	ok(found, "FIXTURE: a real strike (combo3 card %d) lands on fighter 2 at %s, contact at %.3f s" % [ci + 1, DXF_POS, float(r["path"].get("tc", -1))])
	if not found:
		print("fails: ", fails)
		quit(1)
		return
	var P: Dictionary = r["path"]
	var mine := my_path(AS, P)
	print("     wind-up begins %.3f s, the strike card's move %.3f s, contact %.3f s" % [t_read, float(P["t0"]), float(P["tc"])])
	var good := 0
	for p in r["list"]:
		print("     ", String(p["label"]).replace("\n", " | "))
		if not bool(p["ok"]):
			continue
		good += 1
		var G: Body = p["B"]
		var kind := String(p["kind"])
		var start := float(p["t"]) - Counter.MV
		ok(start >= t_read + 0.2 - 1e-6, "%s REACTION: starts %.3f s = %.3f s after the wind-up begins (>= 0.2)" % [kind, start, start - t_read])
		if kind == "BLOCK" or kind == "PARRY":
			var c: Array = G.cap("lowerarm" + String(p["side"]))
			var fa: Vector3 = dxf * (c[0] as Vector3)
			var fb: Vector3 = dxf * (c[1] as Vector3)
			var tx := float(p["tx"])
			var tp := tip_at(AS, tx)
			var d_x := seg_d(tp, fa, fb)
			var front := INF
			for part in ["head", "spine_03", "spine_02", "spine_01", "pelvis"]:
				var cc: Array = G.cap(part)
				front = minf(front, seg_d(tp, dxf * (cc[0] as Vector3), dxf * (cc[1] as Vector3)) - float(G.rad[part]))
			var v := (tip_at(AS, tx + 1.0 / 240.0) - tip_at(AS, tx - 1.0 / 240.0)) * 120.0
			var ang := rad_to_deg(acos(clampf(absf((fb - fa).normalized().dot(v.normalized())), 0.0, 1.0)))
			print("     %s: forearm to the tip at %.3f s %.2f cm, tip %.1f cm in front of the body, %.1f deg to the velocity" % [kind, tx, d_x * 100.0, front * 100.0, ang])
			ok(d_x <= 0.03, "%s: forearm axis %.2f cm from the path at its time (<= 3)" % [kind, d_x * 100.0])
			ok(front >= 0.05, "%s: the tip is %.1f cm in front of the head/torso surface when it meets the forearm (>= 5)" % [kind, front * 100.0])
			ok(tx < float(P["tc"]), "%s: meets the weapon %.3f s before the contact" % [kind, float(P["tc"]) - tx])
			if kind == "BLOCK":
				ok(absf(ang - 90.0) <= 20.0, "BLOCK: forearm %.1f deg to the velocity (square +-20)" % ang)
			else:
				ok(float(p["deflect"]) >= 20.0, "PARRY: the tip is deflected %.0f deg (>= 20)" % float(p["deflect"]))
		elif kind == "STEP-BACK":
			step_checks(p, G, AS, DS, P, t_read)
		else:
			var hc: Array = G.cap("head")
			var clear := path_min(mine, dxf * (hc[0] as Vector3), dxf * (hc[1] as Vector3)) - float(G.rad["head"])
			var bal := Balance.read(G)
			ok(clear >= (0.05 if kind == "DUCK" else 0.10), "%s: head clears the path by %.1f cm (>= 10; a plain duck 5)" % [kind, clear * 100.0])
			ok(float(bal["margin"]) >= 0.0 and (bal["down"] as Array).size() == 2, "%s: centre of mass inside the support, both feet down" % kind)
		var worst := 0.0
		for j in Body.ORDER:
			var a: Vector3 = G.ang[j]
			var cl: Vector3 = G.clamp_ang(j, a)
			worst = maxf(worst, maxf(absf(a.x - cl.x), maxf(absf(a.y - cl.y), absf(a.z - cl.z))))
		ok(worst < 1e-3, "%s: inside its joint limits (worst %.6f deg)" % [kind, worst])
	ok(good >= 3, "1 FOUND: %d counters on the real strike (>= 3)" % good)
	var kinds := []
	for p in r["list"]:
		if bool(p["ok"]):
			kinds.append(String(p["kind"]))
	ok(kinds.has("BLOCK") and kinds.has("PARRY") and kinds.has("STEP-BACK"), "9 combo3 card 3 has block, parry and step-back: %s" % str(kinds))
	duck_checks()
	var rm := Counter.suggest(AS, Transform3D.IDENTITY, DS, xf_at(3.0, 3.0), t_play)
	ok(not bool(rm["ok"]) and String(rm["why"]).begins_with("nothing to counter"), "7 MISS: a defender out of reach: %s" % String(rm["why"]).left(60))

	# the app: 5 UNCHANGED, 6 ACCEPT, 7 PLACEMENT
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m._load_scene("res://scenes/combo3.json")   # read only: nothing is written to scenes/
	m.S.actors.append({"name": "fighter 2", "xf": {"pos": DXF_POS, "yaw": 180.0}, "scene": stand_scene()})
	m._actors_sync()
	m._refresh()
	await idle()
	ok(m._fighters_on() and m.actors_rt.size() == 2, "two fighters in the app")
	m.playhead = t_play
	m._ps().apply(m.B, m.playhead)
	m.yaw = 90.0
	m.pitch = -6.0
	m.dist = 5.0
	m.target = Vector3(0.3, 1.45, 0.7)
	m._cam()
	m._refresh()
	await idle(2)
	var D0: Scene = m.actors_rt[1]["S"]
	var before := [JSON.stringify(m.actors_rt[0]["S"].cards), JSON.stringify(D0.cards), JSON.stringify((m.actors_rt[1]["B"] as Body).to_dict()), JSON.stringify((m.actors_rt[0]["B"] as Body).to_dict())]
	var n0: int = m.undo.size()
	var rr: Dictionary = m.counter_ui.start()
	ok(bool(rr.get("ok", false)) and m.counter_ui.on and m.counter_ui.shown.size() >= 3, "the command shows >= 3 ghosts (%d)" % m.counter_ui.shown.size())
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
		var sp: Vector2 = m.cam.unproject_position(hp)
		if sp.x < 0 or sp.y < 0 or sp.x > vp.x or sp.y > vp.y or m.cam.is_position_behind(hp):
			on_screen = false
		var lr := Rect2((g["label"] as Label).position, (g["label"] as Label).size)
		if lr.position.x < 0 or lr.position.y < 0 or lr.end.x > vp.x or lr.end.y > vp.y:
			on_screen = false
		print("     ghost %d %s: label rect %s" % [i, cui.shown[i]["kind"], lr])
	ok(dnode_ok, "8 PLACEMENT: each ghost node is visible at the defender's placement")
	ok(near_ok, "8 PLACEMENT: each ghost's pelvis within 0.5 m of the defender's own")
	ok(on_screen, "8 PLACEMENT: every ghost's head and label are inside the window (%s)" % vp)
	# 11 LABELS: no rectangle over another or over the name tag
	var rects := []
	for i in cui.shown.size():
		rects.append(Rect2((cui._men[i]["label"] as Label).position, (cui._men[i]["label"] as Label).size))
	var tagr: Rect2 = cui.tag_rect_of()
	var over := 0
	for i in rects.size():
		if tagr.size != Vector2.ZERO and (rects[i] as Rect2).intersects(tagr):
			over += 1
			print("     label %d overlaps the name tag %s" % [i, tagr])
		for j in range(i + 1, rects.size()):
			if (rects[i] as Rect2).intersects(rects[j]):
				over += 1
				print("     labels %d and %d overlap" % [i, j])
	ok(over == 0 and rects.size() == cui.shown.size() and tagr.size != Vector2.ZERO, "11 LABELS: %d label rectangles, none over another or over the name tag %s (%d overlaps)" % [rects.size(), tagr, over])
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
	for i in range(cui.shown.size() - 1):
		m._unhandled_input(tab)
	ok(cui.sel == k0, "Tab cycles back after %d presses" % cui.shown.size())
	for kk in ["BLOCK", "PARRY", "STEP-BACK"]:
		if not cui.on:
			m._actor_set(0)   # an accepted counter made the defender the active fighter: back to the attacker
			m.playhead = t_play
			cui.start()
		for i in cui.shown.size():
			if String(cui.shown[i]["kind"]) == kk:
				cui.sel = i
		var pick: Dictionary = cui.shown[cui.sel]
		ok(String(pick["kind"]) == kk, "6 ACCEPT: %s picked" % kk)
		var dcards := JSON.stringify(m.actors_rt[1]["S"].cards)
		var enter := InputEventKey.new()
		enter.keycode = KEY_ENTER
		enter.pressed = true
		m._unhandled_input(enter)
		ok(m.undo.size() == n0 + 1, "6 ACCEPT %s: Enter is ONE undo step (%d -> %d)" % [kk, n0, m.undo.size()])
		var dnow := JSON.stringify(m.actors_rt[1]["S"].cards)
		ok(dnow != dcards and not cui.on, "6 ACCEPT %s: the defender's cards changed and the ghosts are put away" % kk)
		var Bx := Counter.scratch(m.actors_rt[1]["S"])
		(m.actors_rt[1]["S"] as Scene).apply(Bx, float(pick["t"]))
		if kk == "STEP-BACK":
			var hx: Vector3 = (m.actors_rt[1]["xf"] as Transform3D) * (Bx.P["head"] as Vector3)
			var hg: Vector3 = (m.actors_rt[1]["xf"] as Transform3D) * ((pick["B"] as Body).P["head"] as Vector3)
			print("     step-back card replay: head %.1f cm from the ghost's" % (hx.distance_to(hg) * 100.0))
			ok(hx.distance_to(hg) <= 0.05, "6 ACCEPT STEP-BACK: the card replays the ghost's head within %.1f cm (<= 5)" % (hx.distance_to(hg) * 100.0))
		else:
			var cc: Array = Bx.cap("lowerarm" + String(pick["side"]))
			var cg: Array = (pick["B"] as Body).cap("lowerarm" + String(pick["side"]))
			var rep := maxf(((cc[0] as Vector3) - (cg[0] as Vector3)).length(), ((cc[1] as Vector3) - (cg[1] as Vector3)).length())
			ok(rep <= 0.02, "6 ACCEPT %s: the card replays the ghost's forearm within %.2f cm (<= 2)" % [kk, rep * 100.0])
		m._undo()
		ok(JSON.stringify(m.actors_rt[1]["S"].cards) == dcards and m.undo.size() == n0, "6 ACCEPT %s: Ctrl+Z restores the defender's cards exactly and the undo list" % kk)
		m.playhead = t_play
		m._refresh()
		await idle(2)
	print("fails: ", fails)
	quit(1 if fails > 0 else 0)
