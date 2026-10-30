extends SceneTree
## NSLIDELOD (Friday plan item 170; Nick: monkey-brain easy): while a size slider is dragged, the Easy Part shows a coarse preview
## (fewer triangles, quicker frames); on release it goes back to full detail. Real clicks at 1280 x 720 from the real start screen,
## on the live Easy Part, on a rounded hollow part.
## Walk: Draw shape -> drag a 120 x 100 mm box on the floor -> Pull it up -> Round the edges -> Cut a hole > Hollow inside ->
##   a drag along the Wall slider (1 mm to 10 mm) -> Ctrl+Z
## Bars (measured from the BUILT result: the view mesh triangles, the frame clock, the solid volume; never from variables of the code):
##   0 the BUILDING card, one click: Easy Part on, empty part
##   1 the walk builds a rounded hollow part: one body, its newest slider is labelled Wall
##   2 at rest (full detail) the built mesh has triangles (T_fine)
##   3 mean frame time during the Wall drag <= 40 ms (a timing bar, Docker)
##   4 the most triangles on the mesh during the drag <= 0.75 x T_fine (the coarse preview)
##   5 after release the mesh is full detail again: its triangles within 1 pct of a full replay of the same record
##   6 the whole drag is ONE undo step, and Ctrl+Z puts the solid volume back within 0.5 pct
##   7 the words: the release says a line (non-empty msg or hint)
## shots: C:/Temp/claude/nslidelod/
const SHOT_DIR := "C:/Temp/claude/nslidelod"
const DIRT := "user://nslidelod_test"
const FRAME_BAR_MS := 40.0
const TRI_BAR := 0.75

var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT_DIR, nm])


func pu():
	return m.bld.part


## a floor point in mm (x right, y = -z) to the screen
func fl(x: float, y: float) -> Vector2:
	return m.cam.unproject_position(Part.to_world(Part.plane("top"), Vector2(x, y)))


func find_named(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var f := find_named(c, nm)
		if f != null:
			return f
	return null


## triangles on a mesh (its surfaces' indices / 3, or vertices / 3 when not indexed)
func tris_of_mesh(me: Mesh) -> int:
	if me == null:
		return 0
	var n := 0
	for s in me.get_surface_count():
		var arr := me.surface_get_arrays(s)
		var idx = arr[Mesh.ARRAY_INDEX]
		n += (idx as PackedInt32Array).size() / 3 if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


## the triangles of the mesh the view shows now
func view_tris() -> int:
	return tris_of_mesh(pu().part_mesh.mesh)


## the Wall slider (the newest step slider) and whether it is labelled Wall
func wall_row() -> Array:
	var sl := find_named(m, "easypart_slider_last") as HSlider
	if sl == null:
		return [null, false]
	var lbl := false
	for c in sl.get_parent().find_children("*", "Label", true, false):
		if String((c as Label).text) == "Wall":
			lbl = true
	return [sl, lbl]


func ctrl_z() -> void:
	var e := InputEventKey.new()
	e.pressed = true
	e.keycode = KEY_Z
	e.physical_keycode = KEY_Z
	e.key_label = KEY_Z
	e.unicode = 122
	e.ctrl_pressed = true
	root.push_input(e)
	await idle(4)


## a drag from a to b in steps: the frame clock between frames (ms) and the most triangles of the view after each frame
func timed_drag(a: Vector2, b: Vector2, steps: int) -> Array:
	var dts := []
	var tmax := 0
	await ev_move(a, false)
	await ev_mouse(a, true)
	var last := Time.get_ticks_usec()
	for i in range(1, steps + 1):
		await ev_move(a.lerp(b, float(i) / float(steps)))
		var now := Time.get_ticks_usec()
		dts.append((now - last) / 1000.0)
		last = now
		tmax = maxi(tmax, view_tris())
	await ev_mouse(b, false)
	await idle(3)
	return [dts, tmax]


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return

	# 0 the BUILDING card, one click
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	m.target = Vector3.ZERO
	m.pitch = -25.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	await shot("00_open")
	ok(m.cur_page == "BUILD" and pu().on and pu().easy and int(pu().res.get("bodies", 0)) == 0,
		"0 BUILDING card, one click -> Easy Part on, empty (page %s)" % m.cur_page)
	var ep = pu().ep

	# 1 the rounded hollow part: a box, Pull it up, Round the edges, Cut a hole > Hollow inside
	await click_ctl(ep.make_btns["draw"])
	await drag_screen(fl(-60, -50), fl(60, 50))
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	await click_ctl(ep.make_btns["round"])
	await idle(10)
	await click_ctl(ep.make_btns["hole"])
	await idle(6)
	await click_ctl(ep.hole_btns["hollow"])
	await idle(12)
	var wr: Array = wall_row()
	var sl: HSlider = wr[0]
	var nb := int(pu().res.get("bodies", 0))
	ok(sl != null and bool(wr[1]) and nb == 1,
		"1 a rounded hollow part: one body (%d), its newest slider labelled Wall (%s)" % [nb, "found" if sl != null else "none"])
	await shot("01_hollow")

	# 2 at rest: full detail, triangles on the mesh the view shows
	var t_fine := view_tris()
	ok(t_fine > 0, "2 at rest the built mesh has triangles (T_fine = %d)" % t_fine)

	# 3, 4 a drag along the Wall slider (from its value to the thick end)
	var ua: int = m.undo.size()
	var v0 := float(pu().res.get("volume", 0.0))
	var dts := []
	var tmax := 0
	if sl != null:
		var r := sl.get_global_rect()
		var g := sl.get_theme_icon("grabber")
		var gw := float(g.get_width()) if g != null else 16.0
		var frac := (sl.value - sl.min_value) / (sl.max_value - sl.min_value)
		var a := Vector2(r.position.x + gw * 0.5 + (r.size.x - gw) * frac, r.get_center().y)
		var res_d: Array = await timed_drag(a, Vector2(r.end.x + 40.0, r.get_center().y), 30)
		dts = res_d[0]
		tmax = int(res_d[1])
	var mean_ms := 0.0
	for d in dts:
		mean_ms += float(d)
	mean_ms = mean_ms / maxf(1.0, float(dts.size()))
	print("MEASURE drag frames=%d mean_ms=%.2f T_fine=%d T_drag_max=%d" % [dts.size(), mean_ms, t_fine, tmax])
	ok(dts.size() > 0 and mean_ms <= FRAME_BAR_MS,
		"3 mean frame time during the Wall drag %.1f ms (bar <= %.0f ms; timing bar, Docker)" % [mean_ms, FRAME_BAR_MS])
	ok(t_fine > 0 and float(tmax) <= TRI_BAR * float(t_fine),
		"4 the most triangles during the drag %d <= %.2f x T_fine %d (= %.0f)" % [tmax, TRI_BAR, t_fine, TRI_BAR * float(t_fine)])
	await shot("02_dragged")

	# 5 on release: full detail again, the same triangles as a full replay of the record
	var ref := Part.replay(pu()._ensure(), -1, {})
	var t_rel := view_tris()
	var t_ref := tris_of_mesh(ref.get("mesh"))
	ok(t_ref > 0 and absf(float(t_rel - t_ref)) <= 0.01 * float(t_ref),
		"5 on release the mesh is full detail: %d triangles vs %d from a full replay" % [t_rel, t_ref])

	# 6 one undo step for the drag; Ctrl+Z puts the volume back
	var ub: int = m.undo.size()
	var v1 := float(pu().res.get("volume", 0.0))
	ok(ub == ua + 1 and absf(v1 - v0) > 0.0,
		"6a the drag is ONE undo step (undo %d -> %d), the solid changed (%.0f -> %.0f mm3)" % [ua, ub, v0 * 1e9, v1 * 1e9])
	await ctrl_z()
	var v2 := float(pu().res.get("volume", 0.0))
	ok(m.undo.size() == ua and absf(v2 - v0) <= 0.005 * v0,
		"6b Ctrl+Z takes the drag back: volume %.0f mm3 (before %.0f), one step fewer" % [v2 * 1e9, v0 * 1e9])

	# 7 the words after a release
	await shot("03_undone")
	ok(String(ep.msg) != "" or String(ep.hint_l.text) != "", "7 the release says a line in words")

	print("NSLIDELOD TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
