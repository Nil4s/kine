extends SceneTree
## MESH CLEAN-UP (Nick, Expert MODEL / SCULPT / SURFACE: phase 1, clean-up only). Real mouse clicks on the bottom page tabs and
## the ribbon buttons. Bars, stated before measuring:
##   1 the weapon Hands strip is shown on the pose pages only (POSE), never on MODEL / SCULPT / SURFACE
##   2 SURFACE: the MODEL side panels (Modifiers, Add primitive) are not shown; MODEL shows them with the cube open
##   3 no two visible panels intersect and none leaves the viewport, on MODEL / SCULPT / SURFACE at 1280x720 and 1024x600
##     (browser, inspector, primitive, Materials, Modifiers, hint, edit line, hands strip, UV editor)
##   4 going to MODEL / SCULPT / SURFACE with no mesh open opens the fighter's body by itself (no Test cube click)
##   5 leaving the mesh pages for POSE after a body edit applies it (the fighter's generation +1), the status says so, the
##     posing body shows the edit (its pieces visible again)
##   6 Undo after leaving takes that apply back (the generation goes back to the one before)
##   7 leaving the mesh pages with no body edit applies nothing (no generation change, no undo step)
##   8 the mesh page's edit line says what is open: "Editing: the fighter's body" with the body, "Editing: Test cube" with the cube,
##     and its Switch... button opens the cube (the body is applied and closed first)
##   9 the MODEL ribbon's body buttons are "Edit body" and "Save to body" (the old "Body mesh" / "Apply body" are gone) and
##     "Edit body" (a real click) opens the body
## Script errors are checked by the runner's log scan (a SCRIPT ERROR line fails the suite).
var fails := 0
func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1

func idle(n := 3) -> void:
	for i in n:
		await process_frame

func mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame

## a real click at the centre of a control (press, then release)
func click(c: Control) -> void:
	if c == null or not is_instance_valid(c):
		return   # a missing control: its bar fails by its own check
	var p := c.get_global_rect().get_center()
	await mouse(p, true)
	await mouse(p, false)
	await idle(3)

func key(k: int, ctrl := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.ctrl_pressed = ctrl
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(3)

func ribbon_button(m: Node, p: String, label: String) -> Button:
	for b in m.ui_ribbon[p].get_children():
		if b is Button and String(b.text) == label:
			return b
	return null

func _shown(n) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	if n is CanvasItem:
		return (n as CanvasItem).is_visible_in_tree()
	return false

## the visible panels of the page (global rects), by name
func _panels(m: Node) -> Dictionary:
	var out := {}
	var cands := {"browser": m.ui_side_of["left"], "inspector": m.ui_side_of["right"], "hint": m.ui_mesh_hint_box,
		"edit_line": m.get("ui_mesh_edit_box"), "hands": m.ui_hands_panel}
	if m.kmed != null:
		cands["prim"] = m.kmed.prim_panel
		cands["mat"] = m.kmed.mat_panel
		if m.kmed.mods != null:
			cands["mods"] = m.kmed.mods.panel
		if m.kmed.uved != null:
			cands["uv"] = m.kmed.uved
	for k in cands:
		var c: Control = cands[k]
		if c != null and is_instance_valid(c) and c.is_visible_in_tree():
			out[k] = c.get_global_rect()
	return out

func _clashes(r: Dictionary) -> Array:
	var out := []
	var keys := r.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			if (r[keys[i]] as Rect2).grow(-0.5).intersects((r[keys[j]] as Rect2).grow(-0.5)):
				out.append("%s x %s" % [keys[i], keys[j]])
	return out

func _outside(r: Dictionary, vp: Rect2) -> Array:
	var out := []
	for k in r:
		if not vp.grow(0.5).encloses(r[k]):
			out.append(k)
	return out

## a picture of the page as it is (windowed runs only: the headless renderer has no picture)
func shot(name: String) -> void:
	await idle(3)
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("C:/Temp/claude/mc")
	root.get_texture().get_image().save_png("C:/Temp/claude/mc/%s.png" % name)


func _is_body(m: Node) -> bool:
	return BaseBody.is_open(m)

func _is_body_sculpt(m: Node) -> bool:
	return m.ksc != null and m.ksc.on and m.ksc.source.is_valid()

func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.easy.set_on(false, false)
	await idle(2)
	var vp := Rect2(Vector2.ZERO, m.get_viewport().get_visible_rect().size)

	# 1 the hands strip: a weapon in the right hand shows the strip on POSE and never on the mesh pages
	m.B.wep_on = true
	m.B.wep_hand = "hand_r"
	m._hands_refresh()
	await idle(2)
	click(m.ui_page_btns["POSE"])
	await idle(3)
	var hands_pose: bool = _shown(m.ui_hands_panel)
	var hands_mesh: Array = []
	for p in ["MODEL", "SCULPT", "SURFACE"]:
		click(m.ui_page_btns[p])
		await idle(3)
		hands_mesh.append(_shown(m.ui_hands_panel))
	ok(hands_pose and hands_mesh == [false, false, false],
		"1 Hands strip: shown on POSE (%s), hidden on MODEL / SCULPT / SURFACE (%s)" % [hands_pose, hands_mesh])
	m.B.wep_on = false
	m.B.wep_hand = ""
	m._hands_refresh()
	click(m.ui_page_btns["POSE"])
	await idle(3)

	# 4 the body opens by itself on the three mesh pages (no Test cube, no Test sphere click)
	var auto: Array = []
	for p in ["MODEL", "SURFACE"]:
		click(m.ui_page_btns["POSE"])
		await idle(3)
		click(m.ui_page_btns[p])
		await idle(4)
		auto.append(_is_body(m) and m.cur_page == p)
		await shot(p.to_lower())
		click(m.ui_page_btns["POSE"])
		await idle(3)
	click(m.ui_page_btns["SCULPT"])
	await idle(4)
	auto.append(_is_body_sculpt(m) and m.cur_page == "SCULPT")
	await shot("sculpt")
	click(m.ui_page_btns["POSE"])
	await idle(3)
	ok(auto == [true, true, true], "4 going to MODEL / SURFACE / SCULPT with no mesh open opens the fighter's body: %s (page %s)" % [auto, m.cur_page])

	# 9 the ribbon names and a real click on "Edit body"
	var names_ok: bool = ribbon_button(m, "MODEL", "Edit body") != null and ribbon_button(m, "MODEL", "Save to body") != null \
		and ribbon_button(m, "MODEL", "Body mesh") == null and ribbon_button(m, "MODEL", "Apply body") == null
	click(m.ui_page_btns["MODEL"])
	await idle(3)
	if m.kmed != null and m.kmed.on:
		m.kmed.stop()   # the body is open from the page switch: a real Edit body click is then the way back in
		await idle(2)
	if ribbon_button(m, "MODEL", "Edit body") != null:
		await click(ribbon_button(m, "MODEL", "Edit body"))
	ok(names_ok and _is_body(m), "9 MODEL ribbon has \"Edit body\" and \"Save to body\" (old names gone: %s), and a real click on Edit body opens the body (%s)" % [names_ok, _is_body(m)])

	# 2 + 3 the panels: MODEL with the cube open shows Modifiers and Add primitive; SURFACE does not; no clashes, all in view
	var clashes_all: Array = []
	var off_all: Array = []
	var sized := {}
	m.B.wep_on = true   # a weapon in the right hand while the panels are checked: its hands strip is a panel too (bar 1)
	m.B.wep_hand = "hand_r"
	m._hands_refresh()
	for sz in [Vector2i(1280, 720), Vector2i(1024, 600)]:
		var was_scale: Vector2i = root.content_scale_size
		var was_mode: int = root.content_scale_mode
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.content_scale_size = sz
		await idle(6)
		vp = Rect2(Vector2.ZERO, m.get_viewport().get_visible_rect().size)
		for p in ["MODEL", "SCULPT", "SURFACE"]:
			click(m.ui_page_btns[p])
			await idle(4)
			if p != "SCULPT" and (m.kmed == null or not m.kmed.on) and ribbon_button(m, p, "Test cube") != null:
				await click(ribbon_button(m, p, "Test cube"))   # no body opened by itself (before the page opens one): the cube
				await idle(3)
			if p == "SCULPT" and not _is_body_sculpt(m) and not (m.ksc != null and m.ksc.on) and ribbon_button(m, p, "Test sphere") != null:
				await click(ribbon_button(m, p, "Test sphere"))
				await idle(3)
			var r := _panels(m)
			clashes_all.append_array(_clashes(r).map(func(s): return "%dx%d %s: %s" % [sz.x, sz.y, p, s]))
			off_all.append_array(_outside(r, vp).map(func(s): return "%dx%d %s: %s" % [sz.x, sz.y, p, s]))
			sized["%dx%d %s" % [sz.x, sz.y, p]] = r.keys()
		root.content_scale_size = was_scale
		root.content_scale_mode = was_mode
		await idle(4)
	m.B.wep_on = false
	m.B.wep_hand = ""
	m._hands_refresh()
	ok(clashes_all.is_empty() and off_all.is_empty(), "3 no two visible panels intersect and none leaves the viewport on MODEL / SCULPT / SURFACE at 1280x720 and 1024x600: clashes %s, outside %s" % [clashes_all, off_all])

	# 2 the MODEL side panels belong to MODEL: open the cube on MODEL, then SURFACE hides them and MODEL shows them again
	click(m.ui_page_btns["MODEL"])
	await idle(3)
	if m.kmed != null and m.kmed.on:
		m.kmed.stop()
		await idle(2)
	await click(ribbon_button(m, "MODEL", "Test cube"))
	await idle(3)
	var on_model: bool = m.kmed != null and m.kmed.on and _shown(m.kmed.prim_panel) and _shown(m.kmed.mods.panel)
	click(m.ui_page_btns["SURFACE"])
	await idle(3)
	var on_surface: bool = m.kmed != null and not _shown(m.kmed.prim_panel) and not _shown(m.kmed.mods.panel)
	click(m.ui_page_btns["MODEL"])
	await idle(3)
	var back_model: bool = m.kmed != null and _shown(m.kmed.prim_panel) and _shown(m.kmed.mods.panel)
	ok(on_model and on_surface and back_model, "2 Modifiers and Add primitive: shown on MODEL with the cube (%s), hidden on SURFACE (%s), back on MODEL (%s)" % [on_model, on_surface, back_model])

	# 5 a body edit, then POSE: applied on leaving, the generation +1, the status says so, the posing body shows it
	if m.kmed != null and m.kmed.on and not _is_body(m):
		m.kmed.stop()
		await idle(2)
	click(m.ui_page_btns["MODEL"])
	await idle(3)
	if not _is_body(m):
		click(ribbon_button(m, "MODEL", "Edit body"))
		await idle(3)
	var g0: int = BaseBody.gen(m)
	if m.kmed == null or not _is_body(m):
		print("FAIL 5 the body is not open on MODEL with no click on it")
	if m.kmed != null and m.kmed.on:
		var vv: PackedVector3Array = m.kmed.mesh.verts
		vv[0] = vv[0] + Vector3(0.02, 0.0, 0.0)
		m.kmed.mesh.verts = vv
		m.kmed.view.mark_dirty()
	await idle(2)
	click(m.ui_page_btns["POSE"])
	await idle(4)
	var g1: int = BaseBody.gen(m)
	await shot("pose")
	var pieces_vis := true
	for j in m.pieces:
		pieces_vis = pieces_vis and (m.pieces[j] as MeshInstance3D).visible
	ok(g1 == g0 + 1 and not _is_body(m) and pieces_vis and "applied" in m.ui_status.text.to_lower(),
		"5 body edit then POSE: applied on leaving (generation %d -> %d), body closed %s, posing body shown %s, status \"%s\"" % [g0, g1, not _is_body(m), pieces_vis, m.ui_status.text.left(70)])

	# 6 Undo after leaving takes the apply back
	await key(KEY_Z, true)
	var g2: int = BaseBody.gen(m)
	ok(g1 == g0 + 1 and g2 == g0, "6 Ctrl+Z after leaving takes the apply back (generation %d -> %d, was %d)" % [g1, g2, g0])

	# 7 leaving with no body edit applies nothing
	click(m.ui_page_btns["MODEL"])
	await idle(4)
	var gg0: int = BaseBody.gen(m)
	click(m.ui_page_btns["POSE"])
	await idle(3)
	var gg1: int = BaseBody.gen(m)
	ok(gg1 == gg0 and not _is_body(m), "7 leaving the body with no edit applies nothing (generation %d -> %d)" % [gg0, gg1])

	# 8 the edit line: the body, then the cube through Switch...
	click(m.ui_page_btns["MODEL"])
	await idle(4)
	var line_body: String = m.get("ui_mesh_edit").text if m.get("ui_mesh_edit") != null else ""
	var line_ok: bool = line_body == "Editing: the fighter's body" and _shown(m.get("ui_mesh_edit_box"))
	if m.get("ui_mesh_switch") != null:
		await click(m.get("ui_mesh_switch"))
		await idle(2)
		if m.has_method("_mesh_switch_pick"):
			m._mesh_switch_pick(1)   # the menu's "Test cube" row (the menu's own pick, after a real click on Switch...)
		await idle(4)
	var line_cube: String = m.get("ui_mesh_edit").text if m.get("ui_mesh_edit") != null else ""
	ok(line_ok and line_cube == "Editing: Test cube" and not _is_body(m) and m.kmed.on,
		"8 the edit line: \"%s\" with the body, \"%s\" after Switch... to the cube (body closed %s)" % [line_body, line_cube, not _is_body(m)])
	if m.kmed != null and m.kmed.on:
		m.kmed.stop()
	await idle(2)

	# the walk through the three pages with the body: the hint and the edit line are on the mesh pages only
	click(m.ui_page_btns["POSE"])
	await idle(3)
	ok(not _shown(m.get("ui_mesh_edit_box")) and not _shown(m.ui_mesh_hint_box),
		"8b the edit line and the hint are off on POSE")

	print("MESH CLEAN ", "PASS" if fails == 0 else "FAIL %d" % fails)
	TestFiles.cleanup()
	quit(1 if fails else 0)
