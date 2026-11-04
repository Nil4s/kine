extends SceneTree
## c69 (C69): every tooltip shown in Easy Part / Easy Pose at 1024x600 and 1280x720 is inside the window and its text is not clipped.
## Bar 1 (written before any number was read): each shown tip rect is enclosed by the window rect and its label is not cut (min size fits). Bar 2: >= 5 tips shown per sweep.
const SHOT := "C:/Users/Nick/tools/kine_workers/out/c69"
const DIRT := "user://c69_test"
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



var tipwin: Window


## the tooltip popup Godot shows: a visible Window under the root (internal child) whose panel is the TooltipPanel
func find_tip() -> Window:
	for c in root.get_children(true):
		if c is Window and (c as Window).visible and c != m:
			return c
	return null


func tip_label(w: Window) -> Label:
	for c in w.find_children("*", "Label", true, false):
		return c
	return null


## hover b until its tooltip shows (or give up): returns {rect, text_w, label_h, min_h} of the shown tip
func hover_tip(b: Control) -> Dictionary:
	var p := b.get_global_rect().get_center()
	await ev_move(Vector2(root.size.x * 0.5, root.size.y * 0.9))
	await ev_move(p)
	for i in 40:
		await process_frame
		var w := find_tip()
		if w != null:
			var lb := tip_label(w)
			for k in 4:
				await process_frame
			return {"rect": Rect2(Vector2(w.position), Vector2(w.size)), "label": lb}
	return {}


func clipped(d: Dictionary) -> bool:
	var lb: Label = d["label"]
	if lb == null:
		return false
	return lb.get_minimum_size().y > lb.size.y + 1.0 or lb.get_minimum_size().x > lb.size.x + 1.0 or lb.get_line_count() > lb.get_visible_line_count()


func enter(kind: String) -> void:
	var ss: StartScreen = m.start_screen
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn[kind])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)


func sweep(label: String, sz: Vector2i) -> void:
	root.size = sz
	root.content_scale_size = sz
	await idle(30)
	var items: Array = []
	btns(m, items)
	var seen := {}
	var n := 0
	var bad := ""
	var worst := 0
	for b in items:
		var tt: String = (b as Button).tooltip_text
		if tt.strip_edges() == "" or seen.has(tt):
			continue
		var r := vis_rect(b)
		if r.size.x < 2.0 or not Rect2(Vector2.ZERO, Vector2(sz)).encloses(r):
			continue
		seen[tt] = true
		var d := await hover_tip(b)
		if d.is_empty():
			continue
		n += 1
		var rc: Rect2 = d["rect"]
		var inside := Rect2(Vector2.ZERO, Vector2(sz)).encloses(rc)
		var cl := clipped(d)
		if not inside or cl:
			bad += " [%s %s %s%s]" % [(b as Button).text, rc, "OUT" if not inside else "", " CLIPPED" if cl else ""]
		if label == "Part %s" % sz and (b as Button).text.contains("Measure") or tt.begins_with("Click two spots"):
			await shot("measure_%s_%dx%d" % [label.get_slice(" ", 0), sz.x, sz.y])
	print("tips %s %s: %d shown" % [label, sz, n])
	ok(n >= 5, "%s %s: %d tooltips were shown (bar >= 5)" % [label, sz, n])
	ok(bad == "", "%s %s: every shown tip is inside the window and unclipped:%s" % [label, sz, bad.left(900)])


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	ProjectSettings.set_setting("gui/timers/tooltip_delay_sec", 0.05)
	await idle(4)
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	m.build_choose.auto = true
	# CONTROL: a planted over-wide tip is seen as out of the window / clipped by the same measure
	var cw := Window.new()
	ok(not Rect2(0, 0, 100, 100).encloses(Rect2(50, 50, 80, 20)), "control: the inside test fails a rect past the edge")
	cw.free()
	await enter("building")
	m.target = Vector3.ZERO
	await idle(30)
	# a shape drawn and pulled, so the Part tool row and the Measure chip are up
	await click_ctl(pu().ep.make_btns["draw"])
	await drag_screen(scr(Vector3(-0.02, 0.0, -0.02)), scr(Vector3(0.02, 0.0, 0.02)))
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(60)
	for sz in [Vector2i(1024, 600), Vector2i(1280, 720)]:
		await sweep("Part %s" % sz, sz)
	await enter("animation")
	for sz in [Vector2i(1024, 600), Vector2i(1280, 720)]:
		await sweep("Pose %s" % sz, sz)
	print("c69: %d fail" % fails)
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
