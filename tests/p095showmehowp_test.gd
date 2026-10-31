extends SceneTree
## P095 SHOW ME HOW (Friday plan item 95, Nick's star item: Kine's own idea): Easy Part's "Show me how" plays the steps of the part one at a time
## as a see-through GHOST the user copies on their own part. A beginner from the real start screen, real clicks at 1280 x 720:
##   S0 the BUILDING card, Easy, Draw shape + Box chip + drag a 40 mm box, Pull it up, How far to 3 cm, Round the edges (Only the top), How round
##      to 2 mm: two solid steps on the list; the step list has a "Show me how" button
##   D0 a click on Show me how opens the ghost panel (easypart_demo) with no ghost yet and says "Press Next"; the model is unchanged
##   D1 Next: the ghost shows the step 1 solid, its height is the built height after the pull (30 mm +-0.3) and the panel names it
##      "Pulled up 3 cm" (the words are read off the screen)
##   D2 Next again: the ghost is the whole built solid (its height and its box match the built result within 0.3 mm), the panel says "2 of 2"
##   D3 Back: the ghost goes back to the step 1 solid (30 mm)
##   D4 the part (its record JSON) and the undo stack are exactly as before the demo: the demo copies nothing onto the model
##   D5 Done: the ghost and the panel are hidden
## Every number is measured from the ghost's mesh and from Part.replay of the built record, never from the code's own variables.
## shots: C:/Temp/claude/p095showmehowp/open.png, step1.png, step2.png
const SHOT := "C:/Temp/claude/p095showmehowp"
const DIRT := "user://p095showmehowp_test"
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
	if c == null:
		fails += 1
		print("FAIL a control to click is missing")
		return
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func drag_pts(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(pts[i])
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func mm(v: float) -> float:
	return v / Part.MM


func find_named(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var f := find_named(c, nm)
		if f != null:
			return f
	return null


func last_slider() -> HSlider:
	return find_named(m, "easypart_slider_last") as HSlider


## the step-list rows' words, in order
func step_words() -> Array:
	var out := []
	var box := find_named(m, "easypart_steps")
	if box == null:
		return out
	for b in box.find_children("*", "Button", true, false):
		out.append(String((b as Button).text))
	return out


## the ghost's mesh box in mm (the mesh the ghost shows), or Vector3.ZERO when there is no ghost
func ghost_mm() -> Vector3:
	var g := find_named(m, "easypart_demo_ghost") as MeshInstance3D
	if g == null or not g.visible or g.mesh == null:
		return Vector3.ZERO
	return g.mesh.get_aabb().size / Part.MM


func ghost_lo_hi() -> AABB:
	var g := find_named(m, "easypart_demo_ghost") as MeshInstance3D
	if g == null or not g.visible or g.mesh == null:
		return AABB()
	return g.mesh.get_aabb()


func demo_text() -> String:
	var l := find_named(m, "easypart_demo_words") as Label
	return String(l.text) if l != null else ""


func demo_open() -> bool:
	var p := find_named(m, "easypart_demo") as Control
	return p != null and p.is_visible_in_tree()


## the built result after the first k solid steps (the record, read through the kernel, not the code's own variables)
func built_upto(k: int) -> AABB:
	var feats: Array = m.S.part.get("features", [])
	var idx := -1
	var n := 0
	for i in feats.size():
		var t := String(feats[i].get("t", ""))
		if t == "sketch" or t == "plane":
			continue
		n += 1
		if n == k:
			idx = i
			break
	return Part.replay(m.S.part, idx, {})["aabb"]


func solid_all() -> AABB:
	return Part.replay(m.S.part, -1, {})["aabb"]


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
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	var pu = m.bld.part
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	var ep = pu.ep
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 40.0
	m.yaw = 25.0
	m._cam()
	await idle(60)

	# S0 a box, pulled up 3 cm, its top edges rounded 2 mm
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_pts([scr(Vector3(-0.02, 0.0, -0.02)), scr(Vector3(0.02, 0.0, 0.02))])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	var sl := last_slider()
	if sl != null:
		var g := sl.get_theme_icon("grabber")
		var gw := float(g.get_width()) if g != null else 16.0
		var frac := (3.0 - sl.min_value) / (sl.max_value - sl.min_value)
		var p := sl.get_global_rect().position + Vector2(gw * 0.5 + frac * (sl.size.x - gw), sl.size.y * 0.5)
		await ev_move(p, false)
		await ev_mouse(p, true)
		await ev_move(p)
		await ev_mouse(p, false)
		await idle(12)
	await click_ctl(ep.round_btns["top"])
	await click_ctl(ep.make_btns["round"])
	await idle(10)
	sl = last_slider()
	if sl != null:
		var g2 := sl.get_theme_icon("grabber")
		var gw2 := float(g2.get_width()) if g2 != null else 16.0
		var frac2 := (2.0 - sl.min_value) / (sl.max_value - sl.min_value)
		var p2 := sl.get_global_rect().position + Vector2(gw2 * 0.5 + frac2 * (sl.size.x - gw2), sl.size.y * 0.5)
		await ev_move(p2, false)
		await ev_mouse(p2, true)
		await ev_move(p2)
		await ev_mouse(p2, false)
		await idle(12)
	var show_btn := find_named(m, "easypart_show_how") as Button
	ok(show_btn != null and show_btn.is_visible_in_tree() and show_btn.text == "Show me how",
		"S0 the step list has a Show me how button (found %s, words %s)" % [show_btn != null, str(step_words())])

	# D0 open the panel: no ghost yet, the words say Next; the model is unchanged
	var rec_before := JSON.stringify(m.S.part)
	var undo_before: int = m.undo.size()
	await click_ctl(show_btn)
	await idle(6)
	ok(demo_open() and ghost_mm() == Vector3.ZERO and demo_text().find("Next") >= 0,
		"D0 a click on Show me how opens the ghost panel with no ghost yet (open %s, words %s)" % [demo_open(), demo_text()])

	# D1 Next: step 1 is the pull, 30 mm tall
	var nxt := find_named(m, "easypart_demo_next") as Button
	await click_ctl(nxt)
	await idle(6)
	var want1 := built_upto(1)
	var gb1 := ghost_lo_hi()
	ok(absf(mm(gb1.size.y) - 30.0) <= 0.3 and absf(mm(gb1.size.y) - mm(want1.size.y)) <= 0.3 and demo_text().find("Pulled up 3 cm") >= 0,
		"D1 Next shows step 1: ghost height %.2f mm (built after the pull %.2f, want 30 +-0.3), panel says Pulled up 3 cm (%s)" % [mm(gb1.size.y), mm(want1.size.y), demo_text()])
	await shot("step1")

	# D2 Next again: the whole solid, 2 of 2
	await click_ctl(nxt)
	await idle(6)
	var all := solid_all()
	var gb2 := ghost_lo_hi()
	ok(absf(mm(gb2.size.y - all.size.y)) <= 0.3 and absf(mm(gb2.size.x - all.size.x)) <= 0.3 and absf(mm(gb2.size.z - all.size.z)) <= 0.3 and demo_text().find("2 of 2") >= 0,
		"D2 Next again shows the whole solid: ghost %.2f x %.2f x %.2f mm, built %.2f x %.2f x %.2f mm, panel %s" % [mm(gb2.size.x), mm(gb2.size.y), mm(gb2.size.z), mm(all.size.x), mm(all.size.y), mm(all.size.z), demo_text()])
	await shot("step2")

	# D3 Back: step 1 again
	await click_ctl(find_named(m, "easypart_demo_back") as Button)
	await idle(6)
	var gb3 := ghost_lo_hi()
	ok(absf(mm(gb3.size.y) - 30.0) <= 0.3 and demo_text().find("1 of 2") >= 0,
		"D3 Back shows step 1 again: ghost height %.2f mm, panel %s" % [mm(gb3.size.y), demo_text()])

	# D4 nothing on the model changed
	ok(JSON.stringify(m.S.part) == rec_before and m.undo.size() == undo_before,
		"D4 the demo changed nothing: record same %s, undo steps %d -> %d" % [JSON.stringify(m.S.part) == rec_before, undo_before, m.undo.size()])

	# D5 Done hides the ghost and the panel
	await click_ctl(find_named(m, "easypart_demo_done") as Button)
	await idle(6)
	ok(not demo_open() and ghost_mm() == Vector3.ZERO,
		"D5 Done hides the ghost (%s) and the panel (open %s)" % [str(ghost_mm()), demo_open()])

	print("P095SHOWMEHOW %d fails" % fails)
	quit(1 if fails > 0 else 0)
