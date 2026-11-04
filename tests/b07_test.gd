extends SceneTree
## b07 (B07): in Easy Part with a shape picked, no two visible buttons overlap, at 1600x900, 1280x720, 1024x600.
## Bar 1 (written before any number was read): the summed overlap area of every pair of visible Button rects is 0 px2 at each size.
## Control: a planted pair of overlapping buttons gives a positive area with the same arithmetic.
const SHOT := "C:/Users/Nick/tools/kine_workers/out/b07"
const DIRT := "user://b07_test"
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


func ev_move(p: Vector2, held := false) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	if c == null:
		return   # a missing button: the bars that follow say so
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0), true)
	await ev_mouse(b, false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu():
	return m.bld.part


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


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
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	m.target = Vector3.ZERO
	m.pitch = -25.0
	m.yaw = 20.0
	m._cam()
	await idle(60)

	# a 4 cm square drawn and pulled: a shape is picked (the edge-choice row with Round / Bevel shows)
	await click_ctl(pu().ep.make_btns["draw"])
	await drag_screen(scr(Vector3(-0.02, 0.0, -0.02)), scr(Vector3(0.02, 0.0, 0.02)))
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(60)
	for sz in [Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(1024, 600)]:
		root.size = sz
		root.content_scale_size = sz
		await idle(30)
		var rects: Array = []
		btns(m, rects)
		var total := 0.0
		var worst := ""
		var n_pairs := 0
		for i in rects.size():
			for j in range(i + 1, rects.size()):
				var a: Button = rects[i]
				var b: Button = rects[j]
				if a.is_ancestor_of(b) or b.is_ancestor_of(a):
					continue
				var ov := vis_rect(a).intersection(vis_rect(b))
				var ar := ov.size.x * ov.size.y if ov.size.x > 0.0 and ov.size.y > 0.0 else 0.0
				if ar > 0.0:
					total += ar
					n_pairs += 1
					worst += " [%s|%s %.0f]" % [a.text if a.text != "" else a.name, b.text if b.text != "" else b.name, ar]
		var bev := m.find_child("easypart_bevel", true, false) as Button
		ok(bev != null and bev.is_visible_in_tree(), "setup %s: the Bevel button is visible (%d visible buttons)" % [sz, rects.size()])
		ok(total == 0.0, "1 OVERLAP at %s: %d overlapping button pairs, %.0f px2 in all (bar 0):%s" % [sz, n_pairs, total, worst.left(600)])
		# CONTROL: the measurer sees two planted overlapping buttons
		var p1 := Button.new()
		var p2 := Button.new()
		p1.position = Vector2(100, 100)
		p1.size = Vector2(50, 20)
		p2.position = Vector2(120, 105)
		p2.size = Vector2(50, 20)
		m.add_child(p1)
		m.add_child(p2)
		var ovc := p1.get_global_rect().intersection(p2.get_global_rect())
		ok(ovc.size.x * ovc.size.y > 0.0, "control %s: the measure sees a planted overlap (%.0f px2)" % [sz, ovc.size.x * ovc.size.y])
		p1.queue_free()
		p2.queue_free()
		await shot("edge_%dx%d" % [sz.x, sz.y])
	print("b07: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func btns(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Button and (n as Button).size.x > 1.0 and (n as Button).size.y > 1.0 and (n as Button).modulate.a > 0.05:
		out.append(n)
	for c in n.get_children():
		btns(c, out)


## the part of a button that can be SEEN: its rect cut by every scroll panel it sits in (a step row half under the panel's foot is not on top of the button below)
func vis_rect(c: Control) -> Rect2:
	var r := c.get_global_rect()
	var n: Node = c.get_parent()
	while n != null:
		if n is ScrollContainer:
			r = r.intersection((n as Control).get_global_rect())
		n = n.get_parent()
	return r
