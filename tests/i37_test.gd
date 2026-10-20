## godot --path . -s tests/i37_test.gd     (ROADMAP I37: auto opponent, scripts/auto_opponent.gd + auto_opponent_ui.gd; needs a window)
## SYNTHETIC HERO CLIP of 5 bat strikes (a free bat, the stand pose; fighter 2 stands 1.2 m in front, facing the hero):
##   1 thrust (slow), 2 overhead swing (slow), 3 side slash at head height (slow), 4 thrust (slow), 5 fast thrust (wind-up 0.10 s, strike 0.09 s).
## Habits given to the planner: Nick's clips answered a thrust with a block 5 of 5 times; nothing for a swing / slash (default order).
## Bars, written before measuring:
##  (1) 5 strikes -> 5 items, every one with a response (none NONE)
##  (2) every defended strike: the movement starts >= 0.2 s (Counter.REACT, - 5 ms) after the strike shows (read time) and is in place by the contact
##      (+ 5 ms); both re-measured from fighter 2's NEW scene's own card times (Scene.times) at the card the response made
##  (3) the fast strike 5 is HIT: readable -> contact < 0.2 + 0.12 s; its reaction cards ("hit at") start within 0.1 s of the contact and the pelvis is shoved
##      (impulse > 0)
##  (4) data: a thrust that is defended is a BLOCK ("your clips ..." why); strike 2 and 3 have the default reason ("no data ...")
##  (5) independent check: Precog.analyze on [hero, new fighter 2] reads every defended strike as status ok (>= 0.2 s, not late)
##  (6) Preview leaves both fighters' cards byte-identical; Accept = ONE undo step, fighter 2's cards become the plan's; Ctrl+Z restores
##      both fighters' cards exactly and the undo list
##  (7) PLACEMENT: at the first defence the ghost is visible, at fighter 2's placement, both whole bodies (head and feet of hero and fighter 2) inside the
##      window and clear of the panel; the panel holds a row per strike
extends SceneTree

var fails := 0
var m: Node
const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/i37.png"


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


func bat_pose(tip: Vector3, dir: Vector3) -> Dictionary:
	var b := body()
	var d := dir.normalized()
	b.wep_on = true
	b.wep_hand = ""
	b.wep_pos = tip - d * b.wep_len
	b.wep_rot = Quaternion(Vector3.UP, d)
	return b.to_dict()


func hero_scene() -> Scene:
	var cs := []
	var rest := [Vector3(0.1, 1.6, 0.45), Vector3(0, 0.05, 1)]
	cs.append({"name": "guard", "pose": bat_pose(rest[0], rest[1]), "move": -1.0, "hold": 0.5})
	# [wind-up tip, dir, wind-up move, strike name, strike tip, dir, strike move]
	var ex := [
		[Vector3(0.1, 1.6, 0.2), Vector3(0, 0.05, 1), 0.5, "thrust", Vector3(0.0, 1.6, 1.35), Vector3(0, 0.05, 1), 0.4],
		[Vector3(0, 2.3, 0.25), Vector3(0, 0.85, -0.5), 0.6, "overhead swing", Vector3(0, 1.2, 1.0), Vector3(0, -0.5, 0.85), 0.8],
		[Vector3(-0.9, 1.55, 1.1), Vector3(1, 0, 0.05), 0.6, "side slash", Vector3(0.9, 1.55, 1.1), Vector3(1, 0, 0.05), 0.4],
		[Vector3(0.1, 1.6, 0.2), Vector3(0, 0.05, 1), 0.5, "thrust high", Vector3(0.0, 1.7, 1.35), Vector3(0, 0.05, 1), 0.4],
		[Vector3(0.1, 1.6, 0.2), Vector3(0, 0.05, 1), 0.10, "fast thrust", Vector3(0.0, 1.6, 1.35), Vector3(0, 0.05, 1), 0.09]]
	for e in ex:
		cs.append({"name": "wind-up", "pose": bat_pose(e[0], e[1]), "move": e[2], "hold": 0.1})
		cs.append({"name": e[3], "pose": bat_pose(e[4], e[5]), "move": e[6], "hold": 0.2})
		cs.append({"name": "recover", "pose": bat_pose(rest[0], rest[1]), "move": 0.4, "hold": 0.8})
	var s := Scene.new()
	s.from_dict({"scene": "zz_i37_hero", "fps": 30, "cards": cs})
	return s


func stand_scene() -> Scene:
	var pose := body().to_dict()
	var s := Scene.new()
	s.from_dict({"scene": "zz_i37_stand", "fps": 30, "cards": [{"name": "guard", "pose": pose, "move": -1.0, "hold": 3.0}]})
	return s


func cards_json() -> String:
	return JSON.stringify([m.actors_rt[0]["S"].cards, m.actors_rt[1]["S"].cards])


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")   # read only
	m._rebuild_cards()
	await idle()
	m.S.markers = []
	m.S.cards = hero_scene().cards.duplicate(true)
	m.S.actors.append({"name": "fighter 2", "xf": {"pos": [0.0, 1.2], "yaw": 180.0}, "scene": stand_scene()})
	m._actors_sync()
	m._rebuild_cards()
	m._refresh()
	await idle()
	ok(m._fighters_on() and m.actors_rt.size() == 2, "two fighters")
	var ui = m.ao_ui
	ui.hab = {"_files": 1, "thrust": {"block": 5}}
	ui.use_hab = true
	var before := cards_json()
	var u0: int = m.undo.size()
	var t0 := Time.get_ticks_msec()
	var res: Dictionary = ui.show()
	print("       plan took %d ms: %s" % [Time.get_ticks_msec() - t0, res.get("msg", "")])
	await idle(3)
	var items: Array = res.get("items", [])
	for it in items:
		print("       %s" % [{"k": it["kind"], "resp": it["resp"], "read": snappedf(it["readable"], 0.001), "start": snappedf(it["start"], 0.001), "t": snappedf(it["t"], 0.001), "contact": snappedf(it["contact"], 0.001), "why": it["why"], "tried": it["tried"]}])
	ok(bool(res.get("ok", false)) and items.size() == 5, "(1) 5 strikes -> %d items" % items.size())
	var none := 0
	for it in items:
		none += 1 if it["resp"] == "NONE" else 0
	ok(none == 0, "(1) every strike has a response (%d without)" % none)
	if items.size() < 5:
		print("I37 AUTO OPPONENT FAIL (no plan)")
		quit(1)
		return
	var NS: Scene = res["scene"]
	var worst_gap := 9.0
	var worst_late := -9.0
	var defended := 0
	for it in items:
		if it["resp"] == "HIT" or it["resp"] == "NONE":
			continue
		defended += 1
		# the new scene's own card times: the response's card is the one arriving at it["t"]
		var ts := NS.times()
		var found := -1
		for i in range(1, NS.cards.size()):
			if absf(float(ts[i][1]) - float(it["t"])) <= 0.003 and String(NS.cards[i]["name"]).begins_with("auto") and String(NS.cards[i]["name"]) != "auto guard":
				found = i
		if found < 0:
			ok(false, "(2) a response card arrives at %.2f s" % it["t"])
			continue
		worst_gap = minf(worst_gap, float(ts[found][0]) - float(it["readable"]))
		worst_late = maxf(worst_late, float(ts[found][1]) - float(it["contact"]))
	ok(defended >= 3 and worst_gap >= Counter.REACT - 0.005 and worst_late <= 0.005,
		"(2) %d defended strikes: the earliest movement starts %.3f s after the strike shows (>= 0.2), the latest arrival %.3f s vs the contact (<= 0.005)" % [defended, worst_gap, worst_late])
	var it5: Dictionary = items[4]
	var hit_card := -1
	var ts2 := NS.times()
	for i in NS.cards.size():
		if String(NS.cards[i]["name"]) == "hit at":
			hit_card = i
	var imp := float((it5.get("hit", {}) as Dictionary).get("impulse", 0.0))
	ok(it5.get("resp", "") == "HIT" and float(it5["contact"]) - float(it5["readable"]) < Counter.REACT + Counter.MV and hit_card > 0
		and absf(float(ts2[hit_card][1]) - float(it5["contact"])) <= 0.1 and imp > 0.0,
		"(3) the fast strike is a HIT: shows %.3f s, lands %.3f s (%.3f s < 0.32), 'hit at' card %d at %.3f s, impulse %.1f kg m/s" % [
			it5.get("readable", 0.0), it5.get("contact", 0.0), float(it5.get("contact", 0.0)) - float(it5.get("readable", 0.0)), hit_card, float(ts2[hit_card][1]) if hit_card > 0 else -1.0, imp])
	var blocks_ok := true
	for k in [0, 3]:
		if items[k]["resp"] != "HIT":
			blocks_ok = blocks_ok and (items[k]["resp"] == "BLOCK" and String(items[k]["why"]).begins_with("your clips"))
	ok(blocks_ok and String(items[1]["src"]).begins_with("no data") and String(items[2]["src"]).begins_with("no data"),
		"(4) thrusts follow the clips' habit (block), swing and slash the stated default: %s" % [items.map(func(i): return i["resp"])])
	# (5) Precog on the new pair
	var pr := Precog.analyze([m.actors_rt[0]["S"], NS], ["hero", "fighter 2"])
	var oks := 0
	var bad := []
	for p in pr["items"]:
		if p["status"] == "ok":
			oks += 1
		else:
			bad.append(p["status"])
	ok(oks == defended and bad.is_empty(), "(5) Precog reads %d of %d defended strikes as ok (%s)" % [oks, defended, bad])
	# (6) preview, accept, undo
	ok(cards_json() == before and m.undo.size() == u0, "(6) after planning no card changed and no undo step")
	ui.preview()
	var ticks := 0
	while ui.playing and ticks < 150:   # ~2.5 s of the preview is enough to show it leaves the cards alone
		await process_frame
		ticks += 1
	var pv_t: float = ui.pv_t
	ui.halt()
	ok(cards_json() == before and ticks > 5 and pv_t > 0.5, "(6) after Preview (%d frames) both fighters' cards are byte-identical (preview reached %.1f s)" % [ticks, pv_t])
	ui.show()
	await idle(3)
	var plan_cards := JSON.stringify((ui.res["scene"] as Scene).cards)
	ui.accept()
	await idle(2)
	m._actors_sync()
	ok(m.undo.size() == u0 + 1 and JSON.stringify(m.actors_rt[1]["S"].cards) == plan_cards and cards_json() != before,
		"(6) Accept is one undo step (%d -> %d), fighter 2's cards are the plan's" % [u0, m.undo.size()])
	m._undo()
	await idle(2)
	m._actors_sync()
	ok(cards_json() == before and m.undo.size() == u0, "(6) Ctrl+Z restores both fighters' cards exactly")
	# (7) placement
	m.yaw = 90.0
	m.pitch = -6.0
	m.dist = 6.2
	m.target = Vector3(0.3, 1.0, 0.65)
	m._cam()
	ui.show()
	await idle(3)
	# BAR PLACEMENT: shift the camera's target along the fighters' axis until the two bodies stand right of the panel (it covers the window's left-middle)
	var panel0: Rect2 = m.ui_find.get_global_rect()
	var want_x := (panel0.end.x + m.get_viewport().get_visible_rect().size.x) * 0.5
	for it_n in 3:
		await idle(2)
		var xs := []
		for k in 2:
			xs.append(m.cam.unproject_position(m.stage_root.global_transform * ((m.actors_rt[k]["xf"] as Transform3D) * (m.actors_rt[k]["B"].P["pelvis"] as Vector3))).x)
		var cx := (float(xs[0]) + float(xs[1])) * 0.5
		var tz: Vector3 = m.target
		m.target = tz + Vector3(0, 0, 0.1)
		m._cam()
		await idle(2)
		var xs2 := []
		for k in 2:
			xs2.append(m.cam.unproject_position(m.stage_root.global_transform * ((m.actors_rt[k]["xf"] as Transform3D) * (m.actors_rt[k]["B"].P["pelvis"] as Vector3))).x)
		var slope := ((float(xs2[0]) + float(xs2[1])) * 0.5 - cx) / 0.1   # px per metre of target z
		m.target = tz + Vector3(0, 0, (want_x - cx) / slope)
		m._cam()
	var t_show := 0.0
	for it in ui.res["items"]:
		if it["resp"] != "HIT" and it["resp"] != "NONE":
			t_show = float(it["t"])
			break
	m.playhead = t_show
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	await idle(4)
	if m.ui_toast != null:
		m.ui_toast.visible = false
	if m.ui_insp != null:
		m.ui_insp.visible = false   # the part inspector left over from the loaded scene would cover fighter 2
	await idle(2)
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	var pts := []
	for k in 2:
		var Bk: Body = m.actors_rt[k]["B"]
		var xf: Transform3D = m.actors_rt[k]["xf"]
		for j in ["head", "ball_l", "ball_r"]:
			var q: Vector2 = m.cam.unproject_position(m.stage_root.global_transform * (xf * (Bk.P[j] as Vector3) + (Vector3(0, 0.15, 0) if j == "head" else Vector3.ZERO)))
			pts.append(q)
	# the stage's view is the window above the timeline strip (y 90..600): head top and both toes inside it, right of the panel's left edge
	var inside := true
	for p in pts:
		inside = inside and p.x >= 20 and p.y >= 95 and p.x <= vp.x - 20 and p.y <= 600
	var panel: Rect2 = m.ui_find.get_global_rect()
	var bb := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		bb = bb.expand(p)
	var clear := not bb.intersects(panel)
	var gn: Node3D = ui._g["node"]
	var gpos := gn.transform.origin.distance_to((m.actors_rt[1]["xf"] as Transform3D).origin)
	var rows := 0
	for c in m.ui_find_list.get_children():
		if c is Label and String(c.name).begins_with("ao_row_"):
			rows += 1
	print("       bodies %s panel %s window %s" % [bb, panel, vp])
	ok(gn.visible and gpos < 1e-3 and inside and clear and rows == 5 and m.ui_find.visible,
		"(7) ghost visible at fighter 2's place, both whole bodies in the window and clear of the panel, %d rows" % rows)
	root.get_texture().get_image().save_png(SHOT)

	print("I37 AUTO OPPONENT %s" % ("FAIL" if fails > 0 else "PASS") + (" (%d failed)" % fails if fails > 0 else ""))
	quit(1 if fails > 0 else 0)
