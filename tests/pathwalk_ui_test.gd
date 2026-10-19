## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/pathwalk_ui_test.gd     (ROADMAP 92b; needs a window)
## "Walk along a path..." in the app. Bars, stated first:
##   1 the ribbon button is in ANIMATE, has an icon and sits in the MAKE caption group; the command search finds it
##   2 Esc cancels: the scene is untouched, the panel hidden
##   3 a click on the floor (the real mouse event, through the camera) adds a point; Enter with a 90-degree path builds the walk:
##     the scene has the walk's cards, and ONE Ctrl+Z puts the old scene back (same card count, same name)
##     (BUILD MAKES A NEW SCENE 'path walk 1': the open scene object is untouched; undo puts that very scene back)
##   4 the speed box is clamped to the cited range: walk 0.6-1.6, run 3.0-4.0
##   5 a bend tighter than the generator allows is refused in the status line with a next step, the scene untouched
##   6 Run builds a scene with air cards (flights) in one undo step too
##   7 PLACEMENT: in the app's own whole-body picture of the walk, the hips are on the path (<= 0.1 m from the drawn curve in the
##     floor plane) and every footprint drawn is within 0.1 m of the ball that lands on it
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	await idle(2)
	var name0: String = m.S.name
	var n0: int = m.S.cards.size()
	var old_scene = m.S
	# 1 ribbon + icon + group + search
	var btn: Button = null
	for b in m.ui_ribbon["ANIMATE"].get_children():
		if b is Button and m.label_of(b) == "Walk along a path...":
			btn = b
	var in_group := false
	for g in m.RIBBON_GROUPS["ANIMATE"]:
		if g[0] == "MAKE" and (g[1] as Array).has("Walk along a path..."):
			in_group = true
	var found := false
	for c in m._commands():
		if String(c["name"]) == "Walk along a path...":
			found = true
	ok(btn != null and m.ICON_OF.has("Walk along a path...") and in_group and found, "1 button in ANIMATE (%s), icon, MAKE group (%s), command search (%s)" % [btn != null, in_group, found])
	# 2 Esc
	m._pathwalk_start()
	var ui: PathWalkUI = m.pwui
	ui.add_point(Vector3(0, 0, 0))
	ok(ui.on and ui.panel.visible, "2a the mode is on, the panel shows")
	ui.input(key(KEY_ESCAPE))
	ok(not ui.on and not ui.panel.visible and m.S.cards.size() == n0 and m.S.name == name0, "2b Esc cancels: scene untouched (%d cards), panel hidden" % m.S.cards.size())
	# 4 clamps
	ui.mode_pick.select(0)
	ui._mode_changed()
	var w_ok: bool = is_equal_approx(ui.speed_box.min_value, 0.6) and is_equal_approx(ui.speed_box.max_value, 1.6)
	ui.speed_box.value = 9.0
	var w_clamped: bool = ui.speed_box.value <= 1.6
	ui.mode_pick.select(1)
	ui._mode_changed()
	var r_ok: bool = is_equal_approx(ui.speed_box.min_value, 3.0) and is_equal_approx(ui.speed_box.max_value, 4.0)
	ui.speed_box.value = 0.5
	ok(w_ok and w_clamped and r_ok and ui.speed_box.value >= 3.0, "4 speed clamps: walk 0.6-1.6 (9 -> %.1f), run 3.0-4.0 (0.5 -> %.1f)" % [1.6 if w_clamped else -1.0, ui.speed_box.value])
	ui.mode_pick.select(0)
	ui._mode_changed()
	# 5 a tight bend
	m._pathwalk_start()
	for i in 11:
		ui.add_point(Vector3(0, 0, 2.0 * i / 10.0))
	for i in range(1, 12):
		var phi := (PI / 2.0) * i / 11.0
		ui.add_point(Vector3(0.4 - 0.4 * cos(phi), 0, 2.0 + 0.4 * sin(phi)))
	ui.input(key(KEY_ENTER))
	var say5: String = m.ui_status.text
	ok(ui.on and m.S.cards.size() == n0 and say5.contains("radius") and (say5.contains("Widen") or say5.contains("add points")), "5 a 0.4 m bend refused with a next step: %s" % say5.left(110))
	ui.cancel(false)
	# 3 a real mouse click on the floor, then the 90-degree path, Enter
	m._pathwalk_start()
	var vp := root.get_visible_rect().size
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = Vector2(vp.x * 0.5, vp.y * 0.85)
	var used: bool = ui.input(ev)
	ok(used and ui.pts.size() == 1, "3a a real click at the bottom of the view adds a floor point (%s)" % str(ui.pts))
	ui.pts = []
	ui.add_point(Vector3(0, 0, 0))
	var turn := []
	for i in range(1, 21):
		turn.append(Vector3(0, 0, 2.0 * i / 20.0))
	for i in range(1, 24):
		var phi := (PI / 2.0) * i / 23.0
		turn.append(Vector3(1.5 - 1.5 * cos(phi), 0, 2.0 + 1.5 * sin(phi)))
	for i in range(1, 26):
		turn.append(Vector3(1.5 + 2.5 * i / 25.0, 0, 3.5))
	for p in turn:
		ui.add_point(p)
	ui.mode_pick.select(0)
	ui._mode_changed()
	ui.input(key(KEY_ENTER))
	await idle(2)
	var built: int = m.S.cards.size()
	var walk_cards: bool = built > n0 and String(m.S.cards[1]["name"]).begins_with("pivot")
	var new_ok: bool = m.S != old_scene and String(m.S.name) == "path walk 1" and m.scene_path == "" and old_scene.cards.size() == n0 and old_scene.name == name0
	ok(new_ok, "3c Enter made a NEW scene '%s' (unsaved); the open scene '%s' still has its %d cards" % [m.S.name, old_scene.name, old_scene.cards.size()])
	m._undo()
	await idle(2)
	ok(walk_cards and m.S == old_scene and m.S.cards.size() == n0 and m.S.name == name0, "3b Enter built %d cards; ONE Ctrl+Z gives back %d cards named '%s'" % [built, m.S.cards.size(), m.S.name])
	m._redo()
	await idle(2)
	# 7 the picture: the walk replayed, the app's own view
	m.playhead = m.S.length() * 0.6
	m.S.apply(m.B, m.playhead)
	m._refresh()
	var hip: Vector3 = m.B.offset + Vector3(0, 0.85, 0)
	m.cam.look_at_from_position(hip + Vector3(-3.4, 3.6, 5.2), hip)
	await idle(3)
	var img := root.get_texture().get_image()
	var path := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/pathwalk.png"
	if img != null and not img.is_empty():
		img.save_png(path)
		print("picture saved: ", path)
	# placement: hips on the drawn curve; each footprint near the ball that lands on it
	var cv := PathWalk.curve(turn)
	var P: Array = cv["p"]
	var best_hip := INF
	for q in P:
		best_hip = minf(best_hip, Vector2((q as Vector3).x - m.B.offset.x, (q as Vector3).z - m.B.offset.z).length())
	var worst_fp := 0.0
	var ts: Array = m.S.times()
	var li := 0
	for i in m.S.cards.size():
		if String(m.S.cards[i]["name"]).begins_with("step"):
			if li < ui.marks.size():
				m.S.apply(m.B, ts[i][1])
				var sd := "_l" if li % 2 == 0 else "_r"
				var bl: Vector3 = m.B.P["ball" + sd]
				var mk: Vector3 = ui.marks[li][0]
				worst_fp = maxf(worst_fp, Vector2(bl.x - mk.x, bl.z - mk.z).length())
			li += 1
	ok(best_hip <= 0.1 and worst_fp <= 0.1 and ui.marks.size() > 4, "7 placement: hips %.3f m from the drawn path, worst footprint %.3f m from its landing ball (%d footprints; bars 0.1)" % [best_hip, worst_fp, ui.marks.size()])
	# 6 run
	m._load_scene("res://scenes/combo3.json")
	await idle(2)
	var n1: int = m.S.cards.size()
	var old1 = m.S
	m._pathwalk_start()
	ui.mode_pick.select(1)
	ui._mode_changed()
	ui.add_point(Vector3(0, 0, 0))
	ui.add_point(Vector3(0, 0, 14))
	ui.input(key(KEY_ENTER))
	await idle(2)
	var fl: int = m.S.flights().size()
	m._undo()
	await idle(2)
	ok(fl >= 5 and m.S == old1 and m.S.cards.size() == n1, "6 Run: %d flights in the built scene; one Ctrl+Z restores %d cards" % [fl, m.S.cards.size()])
	# 8 a RUN along a curved path, mid-flight: both feet off the floor, the whole body, the path and footprints drawn
	m._load_scene("res://scenes/combo3.json")
	await idle(2)
	m._pathwalk_start()
	ui.mode_pick.select(1)
	ui._mode_changed()
	var curve_pts := []
	for i in 13:
		curve_pts.append(Vector3(0, 0, 8.0 * i / 12.0))   # 8 m straight, then a quarter circle of radius 5 m, then 6 m straight
	for i in range(1, 16):
		var ph := (PI / 2.0) * i / 15.0
		curve_pts.append(Vector3(5.0 - 5.0 * cos(ph), 0, 8.0 + 5.0 * sin(ph)))
	for i in range(1, 11):
		curve_pts.append(Vector3(5.0 + 6.0 * i / 10.0, 0, 13.0))
	for p in curve_pts:
		ui.add_point(p)
	ui.input(key(KEY_ENTER))
	await idle(2)
	var fls: Array = m.S.flights()
	var fi := fls.size() - 3   # a flight on the bend
	var tf: float = (float(fls[fi]["t0"]) + float(fls[fi]["t1"])) * 0.5
	m.playhead = tf
	m.S.apply(m.B, tf)
	m._refresh()
	var hip8: Vector3 = m.B.offset + Vector3(0, 0.9, 0)
	m.cam.look_at_from_position(hip8 + Vector3(-4.0, 2.2, 3.0), hip8)
	await idle(3)
	var img8 := root.get_texture().get_image()
	if img8 != null and not img8.is_empty():
		img8.save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/pathfix.png")
	var up_l: float = m.B.P["ball_l"].y
	var up_r: float = m.B.P["ball_r"].y
	var cv8 := PathWalk.curve(curve_pts)
	var near8 := INF
	for q in cv8["p"]:
		near8 = minf(near8, Vector2((q as Vector3).x - m.B.offset.x, (q as Vector3).z - m.B.offset.z).length())
	ok(up_l > 0.08 and up_r > 0.08 and near8 <= 0.15 and ui.marks.size() > 8, "8 run mid-flight on the bend: balls %.2f / %.2f m up (both off the floor), hips %.3f m from the path, %d footprints drawn" % [up_l, up_r, near8, ui.marks.size()])
	print("PATH WALK UI TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
