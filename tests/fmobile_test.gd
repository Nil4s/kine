extends SceneTree
## FMOBILE: a beginner from the start screen (real clicks at 1280x720) opens the BUILDING card and then
## every Easy Part panel; at each state the layout is checked at 1280x720, 1024x600 and 1920x1080.
const SHOT := "C:/Temp/claude/fmobile"
const DIRT := "user://fmobile_test"
const SIZES := [[1280, 720], [1024, 600], [1920, 1080]]

var fails := 0
var m: Node
var issues_total := 0


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


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


## an embedded (host) window cannot be resized, so the layout size is the canvas size: the UI lays out in w x h logical pixels
func size_to(w: int, h: int) -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = Vector2i(w, h)
	await idle(12)


func leaves(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Button or n is LineEdit or n is Range or (n is Label and (n as Label).text.strip_edges() != ""):
		out.append(n)
	for c in n.get_children():
		leaves(c, out)


func is_anc(a: Node, b: Node) -> bool:
	var p := b
	while p != null:
		if p == a:
			return true
		p = p.get_parent()
	return false


## the topmost control under p (last drawn wins); mouse-ignoring controls are skipped
func top_at(n: Node, p: Vector2) -> Control:
	for i in range(n.get_child_count() - 1, -1, -1):
		var c = n.get_child(i)
		if c is CanvasItem and not (c as CanvasItem).is_visible_in_tree():
			continue
		var f := top_at(c, p)
		if f != null:
			return f
	if n is Control and (n as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE and (n as Control).get_global_rect().has_point(p):
		return n
	return null


func in_scroll(n: Node) -> bool:
	var p := n.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


## every visible control: cut off by the window or a clipping parent, text wider than its box, overlapping another, covered at its centre
func issues(scope: Node) -> Array:
	var out := []
	var ls := []
	leaves(scope, ls)
	var win := root.get_visible_rect()
	for c in ls:
		var ctl := c as Control
		var r := ctl.get_global_rect()
		if r.size.x < 1.0 or r.size.y < 1.0:
			continue
		var nm := String(c.text if (c is Button or c is Label) else c.name).left(28)
		if not in_scroll(ctl) and not win.encloses(r.grow(-0.5)):
			out.append("OFF %s %s" % [nm, r])
		var mn := ctl.get_combined_minimum_size()
		if (c is Button or c is Label) and (r.size.x < mn.x - 1.0 or r.size.y < mn.y - 1.0):
			out.append("CUT %s box %s needs %s" % [nm, r.size, mn])
		if c is Button and (c as Button).is_visible_in_tree() and not (c as Button).disabled:
			var hit := top_at(root, r.get_center())
			if hit != null and hit != c and not is_anc(c, hit) and not is_anc(hit, c):
				out.append("COVERED %s by %s" % [nm, hit.name])
	for i in ls.size():
		for j in range(i + 1, ls.size()):
			var a := ls[i] as Control
			var b := ls[j] as Control
			if is_anc(a, b) or is_anc(b, a) or in_scroll(a) or in_scroll(b):
				continue
			var ov := a.get_global_rect().intersection(b.get_global_rect())
			if ov.size.x > 2.0 and ov.size.y > 2.0:
				out.append("OVERLAP %s / %s" % [String(a.text if (a is Button or a is Label) else a.name).left(24), String(b.text if (b is Button or b is Label) else b.name).left(24)])
	return out


## one check per size; prints an ISSUE line per problem and one FM bar per size
func state_check(state: String, scope: Node) -> void:
	for sz in SIZES:
		await size_to(sz[0], sz[1])
		var iss := issues(scope)
		issues_total += iss.size()
		if m.bld != null and m.bld.part != null and m.bld.part.ep != null:
			var ep = m.bld.part.ep
			print("     GEOM %s %dx%d view %s cl %s panel %s bar %s rep %s status %s hint %s" % [state, sz[0], sz[1], root.get_visible_rect(), ep._cl, ep.panel.get_global_rect(), ep.bar.get_global_rect(), ep.repeat_box.get_global_rect(), ep.status.get_global_rect(), ep.hint.get_global_rect()])
		DirAccess.make_dir_recursive_absolute(SHOT)
		root.get_texture().get_image().save_png("%s/%s_%dx%d.png" % [SHOT, state, sz[0], sz[1]])
		ok(iss.is_empty(), "FM_%s_%dx%d no overlap, cut-off or covered button (%d issues)" % [state, sz[0], sz[1], iss.size()])
		for s in iss.slice(0, 12):
			print("     ISSUE %s %dx%d: %s" % [state, sz[0], sz[1], s])
	await size_to(1280, 720)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	await size_to(1280, 720)
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
	await state_check("start", ss)
	await size_to(1280, 720)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	ok(m.cur_page == "BUILD" and m.bld.part.on and m.bld.part.easy, "0 BUILDING card one click -> Easy Part on (page %s)" % m.cur_page)

	var ep = m.bld.part.ep
	m.target = Vector3.ZERO
	m.pitch = -25.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	await state_check("empty", m)

	await click_ctl(ep.make_btns["draw"])
	await drag_screen(scr(Vector3(-0.03, 0.0, -0.03)), scr(Vector3(0.03, 0.0, 0.03)))
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	await state_check("pulled", m)

	await click_ctl(ep.make_btns["hole"])
	await idle(10)
	await state_check("hole", m)

	await click_ctl(ep.make_btns["split"])
	await idle(10)
	await state_check("split", m)

	await click_ctl(ep.make_btns["colour"])
	await idle(10)
	await state_check("colour", m)

	await click_ctl(ep.make_btns["repeat"])
	await idle(10)
	await state_check("repeat", m)

	await click_ctl(ep.chips["sword"])
	await idle(10)
	await state_check("template", m)

	print("DEAD stick: the Stick together panel needs two picked pieces in the view (not reached by this walk)")
	print("fmobile: %d fail, %d issues" % [fails, issues_total])
	quit(1 if fails > 0 else 0)
