extends SceneTree
## c68 (C68): the step hint's whole text is visible (not overlapped, not clipped) at 1024/1280/1600 for the 5 longest hints.
## Bar (written before any number was read): per hint and size, text height needed <= label height, label inside its pill, pill overlaps no other visible Button/Label by more than 0 px2.
## Control: a planted button over the pill gives a positive area; a planted too-short pill gives a clip.
const SHOT := "C:/Users/Nick/tools/kine_workers/out/c68"
const DIRT := "user://c68_test"
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
	var hints := [
		"Cut a slot 2.0 cm deep into the solid: use the slider to change it, or press Round the edges or Cut a hole next",
		"Pulled out both ways from the middle: use the slider for how thick, or press Mirror that or Cut a hole next",
		"Pulled up 2.0 cm: use the slider to change it, or press Round the edges or Cut a hole next",
		"Pulled out of the face: use the slider to change it, or press Mirror that next",
		"Pulled into the solid: use the slider to change it, or press Cut a hole next"]
	var ep = pu().ep
	for sz in [Vector2i(1024, 600), Vector2i(1280, 720), Vector2i(1600, 900)]:
		root.size = sz
		root.content_scale_size = sz
		await idle(30)
		await ev_move(Vector2(sz.x * 0.5, sz.y * 0.72))
		var hi := 0
		for h in hints:
			hi += 1
			ep._say(h)
			await idle(40)
			var pill: Control = ep.hint
			var lb: Label = ep.hint_l
			var pr := pill.get_global_rect()
			var lr := lb.get_global_rect()
			var need := float(lb.get_line_count()) * float(lb.get_line_height()) + float(lb.get_theme_constant("line_spacing")) * float(maxi(lb.get_line_count() - 1, 0))
			var clipped := need > lr.size.y + 0.5 or lr.position.y < pr.position.y - 0.5 or lr.end.y > pr.end.y + 0.5 or lb.get_visible_line_count() < lb.get_line_count()
			var items: Array = []
			items_of(m, items)
			var total := 0.0
			var worst := ""
			for it in items:
				if it == lb or pill.is_ancestor_of(it):
					continue
				var ov := vis_rect(it).intersection(pr)
				var ar := ov.size.x * ov.size.y if ov.size.x > 0.0 and ov.size.y > 0.0 else 0.0
				if ar > 0.0:
					total += ar
					worst += " [%s %.0f]" % [tx(it), ar]
			ok(pill.is_visible_in_tree() and lb.get_line_count() >= 1, "setup %s hint %d visible" % [sz, hi])
			ok(not clipped, "1 NOT CLIPPED %s hint %d: need %.0f label %.0f pill %s label-rect %s lines %d vis %d" % [sz, hi, need, lr.size.y, pr, lr, lb.get_line_count(), lb.get_visible_line_count()])
			ok(total == 0.0, "2 NOT OVERLAPPED %s hint %d: %.0f px2 (bar 0):%s" % [sz, hi, total, worst.left(300)])
			# 3: a grid number (Label3D) must not peek out from under the pill or the chip rows (the "-30 cm" fragment under "next")
			var peek := ""
			for gl in ep._glabels:
				if not (gl as Label3D).visible:
					continue
				var gp: Vector2 = m.cam.unproject_position((gl as Label3D).global_position)
				var grect := Rect2(gp - Vector2(32, 9), Vector2(64, 18))
				for bx in [ep.hint, ep.round_box, ep.shape_box, ep.hole_box, ep.split_box, ep.colour_box]:
					if (bx as Control).is_visible_in_tree() and grect.intersects((bx as Control).get_global_rect()):
						peek += " [%s under %s]" % [(gl as Label3D).text, bx.name]
			ok(peek == "", "3 NO GRID NUMBER PEEKS OUT %s hint %d:%s" % [sz, hi, peek])
			if hi == 3:
				await shot("hint_%dx%d" % [sz.x, sz.y])
		# CONTROLS
		var pb := Button.new()
		pb.text = "xx"
		pb.position = ep.hint.get_global_rect().position + Vector2(5, 5)
		pb.size = Vector2(50, 20)
		m.add_child(pb)
		var ovc := vis_rect(pb).intersection(ep.hint.get_global_rect())
		ok(ovc.size.x * ovc.size.y > 0.0, "control %s: planted button over the hint is seen" % sz)
		pb.queue_free()
		var need2 := float(ep.hint_l.get_line_count()) * float(ep.hint_l.get_line_height())
		ok(need2 > 20.0, "control %s: a 20 px pill would clip this text (need %.0f)" % [sz, need2])
	print("c68: %d fail" % fails)
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


func tx(c: Control) -> String:
	var t: String = (c as Label).text if c is Label else (c as Button).text
	return t if t != "" else String(c.name)


## visible Buttons and Labels WITH text, real size, inside the ui (not the 3D view)
func items_of(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Button and (n as Button).size.x > 1.0 and (n as Button).size.y > 1.0 and (n as Button).modulate.a > 0.05:
		out.append(n)
	elif n is Label and (n as Label).text.strip_edges() != "" and (n as Label).size.x > 1.0 and (n as Label).size.y > 1.0 and (n as Label).modulate.a > 0.05:
		out.append(n)
	for c in n.get_children():
		items_of(c, out)


## the edge-choice chips: the Button children of the row that holds easypart_round_* buttons
func chip_row(root_n: Node) -> Array:
	var out: Array = []
	var any := root_n.find_child("easypart_round_*", true, false)
	if any != null and any.get_parent() != null:
		for c in any.get_parent().get_children():
			if c is Button and (c as Button).is_visible_in_tree():
				out.append(c)
	return out


## the width a chip's icon takes beside its words (icon + the gap), at the size it is drawn
func icon_w(ch: Button) -> float:
	if ch.icon == null:
		return 0.0
	var w := float(ch.icon.get_width())
	var mx := ch.get_theme_constant("icon_max_width")
	if mx > 0:
		w = minf(w, float(mx))
	return w + float(ch.get_theme_constant("h_separation"))
