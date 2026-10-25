## godot --path . -s tests/i33_test.gd     (ROADMAP I33: reaction direction, scripts/reaction_dir.gd + reaction_dir_ui.gd; needs a window)
## Bars, written before measuring (the 45 deg / 0.5-2 / one frame limits are the brief's heuristics):
##  (1) CLEAN: a head hit (bat from the right, 12 m/s) answered by the physics reaction (HitReaction.react) raises no flag: COM velocity change within
##      45 deg of J and the segment's too, the trunk turns the right way about r x J, onset within one frame of the contact (no pre-flinch), the
##      COM change within 0.5-2 of J / M
##  (2) WRONG WAY: the same hit answered by a shove TOWARD the attacker (the pelvis offset 0.15 m along -J) is flagged "direction" (angle > 90 deg here);
##      Fix (regenerate) leaves a scene whose angle is < 45 deg and whose trunk turns the right way about r x J (turn > 0), "direction" and
##      "rotation" no longer flagged
##  (3) PRE-FLINCH: the physics reaction started 3 frames (0.1 s) early is flagged "pre-flinch" (onset about -100 ms); the fix retimes or remakes it
##      and the onset is then within one frame (>= -34 ms), no pre-flinch
##  (4) IN THE APP (two fighters, combo3 hero, fighter 2 at 1.1 m answering the first strike the wrong way): the panel flags it with its numbers, the
##      timeline holds one badge per hit inside the track, the arrows are drawn at the contact on the struck body, JSON of every fighter byte-identical
##      after show / Fix / Preview; Accept = ONE undo step changing only the struck fighter's cards, the hit then fine on direction; Ctrl+Z exact
extends SceneTree

const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/i33.png"
var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func stand_body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	return b


func still(pose: Dictionary) -> Scene:
	var s := Scene.new()
	s.from_dict({"scene": "zz_still", "fps": 30, "cards": [{"name": "a", "pose": pose, "move": -1.0, "hold": 2.0},
		{"name": "b", "pose": pose, "move": 0.5, "hold": 3.0}]})
	return s


func hit_on(B: Body, part: String, t: float, v: float) -> Dictionary:
	var a: Array = B.cap(part)
	var mid := ((a[0] as Vector3) + (a[1] as Vector3)) * 0.5
	var r: float = float(B.rad[part])
	return {"t": t, "kind": "hit", "zone": "X", "part": "bat_barrel", "on": part, "by": "hero", "vs": 1, "u": 0.6,
		"depth": 0.01, "speed": v, "at": mid + Vector3(-r, 0, 0), "vec": Vector3(v, 0, 0)}


func shown(tag: String, r: Dictionary) -> void:
	print("       %s: %s  flags %s" % [tag, ReactionDir.line(r), str(r.get("flags", []))])


func cards_json() -> String:
	var a := []
	for k in m.actors_rt.size():
		a.append(m.actors_rt[k]["S"].cards)
	return JSON.stringify(a)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false

	var B := stand_body()
	var Bs := ReactionDir.new_body()
	var xf := Transform3D.IDENTITY
	var hit := hit_on(B, "head", 1.0, 12.0)
	var base := still(B.to_dict())

	# (1) clean
	var rr := HitReaction.react(base, B, xf, hit, Bs)
	var good := still(B.to_dict())
	good.cards = rr["cards"]
	var j1 := ReactionDir.judge(good, B, xf, hit, Bs)
	shown("clean", j1)
	ok(j1["ok"] and (j1["flags"] as Array).is_empty(), "(1) the physics reaction raises no flag (angle %.0f, seg %.0f, turn %+.2f rad/s, onset %+.0f ms, ratio %.2f)" % [
		j1["angle"], j1["seg_angle"], j1["turn"], j1["onset_ms"], j1["ratio"]])

	# (2) toward the attacker: J is +x (the bat moves to +x), so toward = -x
	var J: Vector3 = j1["J"]
	var toward := (-Vector3(J.x, 0, J.z)).normalized() * 0.15
	var p0 := B.to_dict()
	var p1: Dictionary = p0.duplicate(true)
	var o: Array = p0["offset"]
	p1["offset"] = [float(o[0]) + toward.x, float(o[1]), float(o[2]) + toward.z]
	var wrong := Scene.new()
	wrong.from_dict({"scene": "zz_wrong", "fps": 30, "cards": [{"name": "a", "pose": p0, "move": -1.0, "hold": 1.0},
		{"name": "away", "pose": p1, "move": 0.12, "hold": 1.0}, {"name": "c", "pose": p1, "move": 0.5, "hold": 2.0}]})
	var j2 := ReactionDir.judge(wrong, B, xf, hit, Bs)
	shown("wrong way", j2)
	ok(j2["ok"] and "direction" in j2["flags"] and float(j2["angle"]) > 90.0, "(2) the shove toward the attacker is flagged direction (angle %.0f deg)" % j2["angle"])
	var f2 := ReactionDir.fix(wrong, B, xf, hit, Bs, j2)
	ok(f2["ok"] and f2["kind"] == "regenerate", "(2) the fix is a regeneration (%s)" % f2.get("why", f2.get("msg", "")))
	var a2: Dictionary = f2["after"]
	shown("wrong way, fixed", a2)
	ok(float(a2["angle"]) < 45.0 and float(a2["turn"]) > 0.0 and not ("direction" in a2["flags"]) and not ("rotation" in a2["flags"]),
		"(2) after the fix: angle %.0f deg (< 45), the trunk turns %+.2f rad/s about r x J, flags %s" % [a2["angle"], a2["turn"], str(a2["flags"])])

	# (3) three frames early
	var h_early := hit.duplicate()
	h_early["t"] = 0.9
	var re := HitReaction.react(base, B, xf, h_early, Bs)
	var early := still(B.to_dict())
	early.cards = re["cards"]
	var j3 := ReactionDir.judge(early, B, xf, hit, Bs)
	shown("3 frames early", j3)
	ok(j3["ok"] and "pre-flinch" in j3["flags"] and float(j3["onset_ms"]) < -66.0, "(3) the early start is flagged pre-flinch (onset %+.0f ms)" % j3["onset_ms"])
	var f3 := ReactionDir.fix(early, B, xf, hit, Bs, j3)
	var a3: Dictionary = f3.get("after", {"onset_ms": -999.0, "flags": ["none"], "pre": true})
	shown("3 frames early, fixed (" + String(f3.get("kind", "?")) + ")", a3)
	ok(f3["ok"] and float(a3["onset_ms"]) >= -34.0 and not a3["pre"], "(3) after the %s the onset is %+.0f ms (bar >= -34), no pre-flinch" % [f3.get("kind", "?"), a3["onset_ms"]])

	# (4) in the app
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	m.S.cards = m.S.cards.slice(0, 7)
	m._rebuild_cards()
	var sb := stand_body()
	m.S.actors.append({"name": "fighter 2", "xf": {"pos": [0.0, 1.1], "yaw": 180.0}, "scene": still(sb.to_dict())})
	m._actors_sync()
	m._refresh()
	await idle()
	var ui = m.rd_ui
	ui.show()
	await idle()
	ok(ui.rows.size() >= 1, "(4) %d contacts judged on the still fighter 2" % ui.rows.size())
	if ui.rows.is_empty():
		print("I33 REACTION DIRECTION FAIL (no contact)")
		TestFiles.cleanup()
		quit(1)
		return
	var r0: Dictionary = ui.rows[0]
	var res0: Dictionary = r0["res"]
	shown("app, no reaction", res0)
	# fighter 2 answers the first blow the wrong way (in its own space: along -J, 0.15 m)
	var Jb: Vector3 = res0["J"]
	var tw := (-Vector3(Jb.x, 0, Jb.z)).normalized() * 0.15
	var q0: Dictionary = sb.to_dict()
	var q1: Dictionary = q0.duplicate(true)
	var oo: Array = q0["offset"]
	q1["offset"] = [float(oo[0]) + tw.x, float(oo[1]), float(oo[2]) + tw.z]
	var t_c: float = res0["t"]
	var ws := Scene.new()
	ws.from_dict({"scene": "zz_wrong2", "fps": 30, "cards": [{"name": "a", "pose": q0, "move": -1.0, "hold": snappedf(t_c, 0.0001)},
		{"name": "away", "pose": q1, "move": 0.12, "hold": 1.0}, {"name": "c", "pose": q1, "move": 0.5, "hold": 3.0}]})
	m.actors_rt[1]["S"].cards = ws.cards
	m.actors_rt[1]["S"].fps = 30
	ui.show()
	await idle()
	r0 = ui.rows[0]
	res0 = r0["res"]
	shown("app, wrong way", res0)
	ok(res0["bad"] and "direction" in res0["flags"], "(4) the panel flags the wrong-way reaction: %s" % str(res0["flags"]))
	var before := cards_json()
	var u0: int = m.undo.size()
	ui.select(0)
	await idle()
	ok(not ui.fx.is_empty() and ui.fx["kind"] == "regenerate" and m.ui_find_list.find_child("rd_accept", true, false) != null, "(4) Fix this reaction builds a regeneration with Preview and Accept")
	var fa: Dictionary = ui.fx.get("after", {"flags": ["none"], "angle": 999.0})
	shown("app, fixed", fa)
	print("       fix: " + String(ui.fx.get("msg", "")))
	# placement
	var tl = m.ui_timeline
	await idle(3)
	var inside := true
	for b in tl.rd:
		var x0: float = tl.x_of(float(b["t0"]))
		var x1: float = tl.x_of(float(b["t1"]))
		inside = inside and x0 >= 0.0 and x1 <= tl.size.x and x1 > x0
	var rows_ui := 0
	for c in m.ui_find_list.get_children():
		if c is HBoxContainer and c.get_child_count() > 0 and String(c.get_child(0).name).begins_with("rd_row_"):
			rows_ui += 1
	ok(tl.rd.size() == ui.rows.size() and inside and rows_ui == ui.rows.size() and (tl.rd[0]["cls"] == "bad"), "(4) the timeline holds %d badges inside the track, the panel %d numbered rows" % [tl.rd.size(), rows_ui])
	# the contact lies on the struck body, the arrows start there, inside the view and clear of the panel
	m.yaw = 90.0
	m.pitch = -4.0
	m.dist = 3.6
	var at_h: Vector3 = res0["at"]
	m.playhead = t_c + 0.12
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	var panel_r: Rect2 = m.ui_find.get_global_rect()
	var vr: Rect2 = m.get_viewport().get_visible_rect()
	var px := Vector2.ZERO
	for dz in [0.0, 0.5, 1.0, 1.5, -0.5, -1.0, -1.5]:   # slide the view until the contact is clear of the panel
		m.target = Vector3(at_h.x, 1.1, at_h.z + dz)
		m._cam()
		await idle(2)
		px = m.cam.unproject_position(m._stage_xf() * at_h)
		if px.x > panel_r.end.x + 120.0 and px.x < vr.size.x - 120.0:
			break
	await idle(2)
	var Bv: Body = m.actors_rt[1]["B"]
	m.actors_rt[1]["S"].apply(Bv, t_c)
	var pv: Vector3 = (m.actors_rt[1]["xf"] as Transform3D).affine_inverse() * at_h
	var cp: Array = Bv.cap(String(res0["on"]))
	var gap := DistanceKeeper._seg_dist(pv, cp[0], cp[1]) - float(Bv.rad[String(res0["on"])])
	var arrows: int = ui._node.get_child_count()
	print("       contact: %.1f cm from the struck capsule's surface, pixel %s, arrows %d, panel %s" % [gap * 100.0, str(px), arrows, str(panel_r)])
	ok(gap < 0.06 and vr.has_point(px) and not panel_r.has_point(px) and arrows == 4, "(4) PLACEMENT: the arrows (%d parts) start at the contact, %.1f cm from the struck body, inside the view and clear of the panel" % [arrows, gap * 100.0])
	m.playing = false
	await idle(3)
	root.get_texture().get_image().save_png(SHOT)

	ui.preview()
	var ticks := 0
	while ui.pv != null and ticks < 1200:
		await process_frame
		ticks += 1
	ok(ui.pv == null and ticks > 5 and cards_json() == before and m.undo.size() == u0, "(4) the preview played %d frames; every fighter's JSON is byte-identical and nothing was pushed to undo" % ticks)

	var hero_cards := JSON.stringify(m.actors_rt[0]["S"].cards)
	ui.accept()
	await idle()
	m._actors_sync()
	var after_ui: Dictionary = ui.rows[0]["res"]
	shown("app, accepted", after_ui)
	ok(m.undo.size() == u0 + 1 and cards_json() != before and JSON.stringify(m.actors_rt[0]["S"].cards) == hero_cards and not ("direction" in after_ui["flags"]),
		"(4) Accept is one undo step (%d -> %d), only the struck fighter changed, direction now fine (angle %.0f deg)" % [u0, m.undo.size(), after_ui["angle"]])
	m._undo()
	await idle()
	m._actors_sync()
	ok(cards_json() == before and m.undo.size() == u0, "(4) Ctrl+Z: every fighter's cards exact")

	print("I33 REACTION DIRECTION %s" % ("FAIL" if fails > 0 else "PASS") + (" (%d failed)" % fails if fails > 0 else ""))
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
