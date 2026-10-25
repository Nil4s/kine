extends SceneTree
## MESH PAGES (the MODEL / SCULPT / SURFACE pages, scripts/expert_pages.gd): the three pages that were greyed "coming"
## until the mesh tools landed are real pages now. Bars, stated before measuring:
##   1 each of MODEL, SCULPT, SURFACE opens in Expert (the page shows, its ribbon row has >= 3 live tools)
##   2 MODEL: extrude one face of the test cube from the ribbon: the vertex count grows (8 -> 12 for a cube face), one undo step
##   3 SCULPT: a draw stroke from the ribbon on the test sphere: >= 10 verts move
##   4 Easy mode hides the three pages (their page-bar buttons not visible; a page switch to one is refused)
##   5 the hint (the top centre of the clear view): shown on MODEL / SCULPT / SURFACE with no mesh open, gone once one is open
##   6 the posing overlays (inspector, part tag, joint dots, target dummy) are off on the mesh pages, back exactly on POSE
##   7 the panels of MODEL do not overlap (browser, primitive panel, materials, modifiers, inspector, hint; 1 px tolerance)
##     at 1600x900 and 1280x720, the cube open and closed, Materials at FULL content (4 slots, its rect at least its
##     minimum height); 7b the browser back on POSE exactly as before
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

func move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame

func drag(a: Vector2, b: Vector2, steps := 8) -> void:
	await mouse(a, true)
	for k in steps:
		await move(a.lerp(b, (k + 1) / float(steps)))
	await mouse(b, false)
	await idle(2)

## a node that is on screen now (a freed or missing node is not)
func _shown(n) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	if n is CanvasItem:
		return (n as CanvasItem).is_visible_in_tree()
	return n is Node3D and (n as Node3D).is_visible_in_tree()


func live_tools(m: Node, p: String) -> int:
	var n := 0
	for b in m.ui_ribbon[p].get_children():
		if b is Button and not (b as Button).disabled:
			n += 1
	return n

func button(m: Node, p: String, label: String) -> Button:
	for b in m.ui_ribbon[p].get_children():
		if b is Button and String(b.text) == label:
			return b
	return null

## the panels of a mesh page that are on screen now, by name -> global rect (a hidden one is not in the list)
func _visible_panels(m: Node) -> Dictionary:
	var out := {}
	var cands := {"browser": m.ui_side_of["left"], "inspector": m.ui_side_of["right"], "hint": m.ui_mesh_hint_box}
	if m.kmed != null:
		cands["prim"] = m.kmed.prim_panel
		cands["mat"] = m.kmed.mat_panel
		if m.kmed.mods != null:
			cands["mods"] = m.kmed.mods.panel
	for k in cands:
		var c: Control = cands[k]
		if c != null and c.is_visible_in_tree():
			out[k] = c.get_global_rect()
	return out


## the pairs of panels whose rects overlap by more than 1 px (each rect is shrunk by half a px first)
func _clashes(r: Dictionary) -> Array:
	var out := []
	var keys := r.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			if (r[keys[i]] as Rect2).grow(-0.5).intersects((r[keys[j]] as Rect2).grow(-0.5)):
				out.append("%s x %s" % [keys[i], keys[j]])
	return out


func _overlays(m: Node) -> Dictionary:
	var n := 0
	for k in m.dots:
		if m.dots[k].visible:
			n += 1
	return {"insp": m.ui_insp.visible, "tag": m.tag.visible, "dots": n, "dummy_on": m.dummy_on, "dummy": m.dummy_node.visible, "pick": m.skp._state.has(m.sel)}


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.easy.set_on(false, false)
	await idle(2)

	# 1 each page opens in Expert and shows at least 3 live tools
	for p in ["MODEL", "SCULPT", "SURFACE"]:
		m.ui_page_btns[p].pressed.emit()
		await idle(3)
		var n := live_tools(m, p)
		ok(m.cur_page == p and m.ui_ribbon[p].visible and n >= 3 and m.ui_page_btns[p].visible and not m.ui_page_btns[p].disabled,
			"1 %s page opens in Expert: page %s, ribbon shows %d live tools" % [p, m.cur_page, n])

	# 2 extrude one face of the test cube from the MODEL ribbon
	m.ui_page_btns["MODEL"].pressed.emit()
	await idle(3)
	var ext := button(m, "MODEL", "Extrude")
	m._kmesh_edit_start()   # the cube is open: select its top face (the same selection a click makes)
	await idle(2)
	m.kmed.sel.clear()
	m.kmed.sel.set_mode(KMeshSelect.FACE)
	m.kmed.sel.select_by_normal(Vector3.UP, 30.0)
	var v0: int = m.kmed.mesh.vert_count()
	var u0: int = m.kmed.undo.steps.size()
	ext.pressed.emit()
	await idle(3)
	var v1: int = m.kmed.mesh.vert_count()
	ok(v1 > v0 and m.kmed.undo.steps.size() == u0 + 1, "2 extrude from the ribbon on the cube: %d -> %d verts, %d undo step" % [v0, v1, m.kmed.undo.steps.size() - u0])
	await idle(2)

	# 3 one draw stroke from the SCULPT ribbon on the test sphere
	m.ui_page_btns["SCULPT"].pressed.emit()
	await idle(3)
	button(m, "SCULPT", "Test sphere").pressed.emit()
	await idle(4)
	var ui = m.ksc
	button(m, "SCULPT", "Draw").pressed.emit()
	await idle(3)
	var cam: Camera3D = m.cam
	m._turn_to(0.0, 0.0, 1.6, ui.view.global_position, false)
	await idle(6)
	var cs := cam.unproject_position(ui.view.global_position)
	await move(cs + Vector2(-32, 0))   # the pointer arrives first: a press the view has seen the pointer over
	await idle(2)
	var s0: Array = ui.mesh.verts.duplicate()
	await drag(cs + Vector2(-30, 0), cs + Vector2(30, 0))
	var moved := 0
	for v in s0.size():
		if ui.mesh.verts[v] != s0[v]:
			moved += 1
	ok(ui.on and moved >= 10, "3 draw stroke from the ribbon on the sphere: %d verts moved" % moved)
	m.ksc.stop()
	await idle(2)

	# 5 the hint: on each page with no mesh open it says what to click first; it goes once a mesh is open
	if m.kmed != null and m.kmed.on:
		m.kmed.stop()
	if m.ksc != null and m.ksc.on:
		m.ksc.stop()
	await idle(2)
	var hint_on: Array = []
	for p in ["MODEL", "SCULPT", "SURFACE"]:
		m.ui_page_btns[p].pressed.emit()
		await idle(3)
		hint_on.append(m.ui_mesh_hint.visible and m.ui_mesh_hint.text == ExpertPages.HINTS[p])
	ok(hint_on == [true, true, true], "5a the hint on MODEL / SCULPT / SURFACE with no mesh open: %s (SURFACE says \"%s\")" % [hint_on, m.ui_mesh_hint.text])
	var hint_gone: Array = []
	m.ui_page_btns["MODEL"].pressed.emit()
	await idle(2)
	button(m, "MODEL", "Test cube").pressed.emit()
	await idle(3)
	hint_gone.append(not m.ui_mesh_hint.visible)
	m.kmed.stop()
	await idle(2)
	m.ui_page_btns["SCULPT"].pressed.emit()
	await idle(2)
	button(m, "SCULPT", "Test sphere").pressed.emit()
	await idle(3)
	hint_gone.append(not m.ui_mesh_hint.visible)
	m.ksc.stop()
	await idle(2)
	m.ui_page_btns["SURFACE"].pressed.emit()
	await idle(2)
	m._kmesh_edit_start()
	await idle(3)
	hint_gone.append(not m.ui_mesh_hint.visible)
	m.kmed.stop()
	await idle(2)
	ok(hint_gone == [true, true, true], "5b the hint is gone once a mesh is open (cube on MODEL, sphere on SCULPT, cube on SURFACE): %s" % [hint_gone])

	# 6 the posing overlays (inspector, part tag, joint dots, target dummy) are off on the mesh pages and come back as they were
	m.ui_page_btns["POSE"].pressed.emit()
	await idle(3)
	m.dummy_on = true
	m._dummy_hits()
	m._refresh()
	await idle(2)
	var before := _overlays(m)
	var off_all := true
	for p in ["MODEL", "SCULPT", "SURFACE"]:
		m.ui_page_btns[p].pressed.emit()
		await idle(3)
		var o := _overlays(m)
		off_all = off_all and not o["insp"] and not o["tag"] and o["dots"] == 0 and not o["dummy_on"] and not o["dummy"] and not o["pick"]
	ok(off_all, "6a inspector, tag, joint dots, dummy and the part's pick light off on MODEL / SCULPT / SURFACE (last: %s)" % [_overlays(m)])
	m.ui_page_btns["POSE"].pressed.emit()
	await idle(3)
	var after := _overlays(m)
	ok(after == before, "6b back on POSE the overlays are exactly as before: %s -> %s" % [before, after])

	# 7 the MODEL panels at two window sizes: the cube open (primitive, materials, modifiers) and closed (the hint alone)
	var was_scale: Vector2i = root.content_scale_size
	var was_mode: int = root.content_scale_mode
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1600, 900)
	await idle(6)
	m.ui_page_btns["POSE"].pressed.emit()
	await idle(3)
	var browser_before := [m.ui_side_of["left"].visible, m.ui_side_of["left"].get_global_rect()]
	for sz in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		root.content_scale_size = sz
		await idle(6)
		m.ui_page_btns["MODEL"].pressed.emit()
		await idle(3)
		if m.kmed != null and m.kmed.on:
			m.kmed.stop()
		await idle(3)
		var closed := _visible_panels(m)
		button(m, "MODEL", "Test cube").pressed.emit()
		await idle(4)
		# Materials at FULL content: 4 slots (a populated list, the fields of the picked slot), not the empty default
		while m.kmed.mat_panel.ui.mesh.materials.size() < 4:
			m.kmed.mat_panel.add_slot()
		await idle(4)
		var opened := _visible_panels(m)
		var c_clash := _clashes(closed)
		var o_clash := _clashes(opened)
		var mat_full: bool = opened.has("mat") and (opened["mat"] as Rect2).size.y >= m.kmed.mat_panel.get_combined_minimum_size().y - 1.0
		ok(c_clash.is_empty() and o_clash.is_empty() and closed.has("hint") and not closed.has("browser")
			and opened.has("prim") and opened.has("mat") and opened.has("mods") and not opened.has("browser") and not opened.has("inspector") and mat_full,
			"7a at %dx%d on MODEL: cube open %s, clashes %s; cube closed %s, clashes %s" % [sz.x, sz.y, opened.keys(), o_clash, closed.keys(), c_clash])
		m.kmed.stop()
		await idle(2)
	root.content_scale_size = Vector2i(1600, 900)
	await idle(6)
	m.ui_page_btns["POSE"].pressed.emit()
	await idle(3)
	var browser_after := [m.ui_side_of["left"].visible, m.ui_side_of["left"].get_global_rect()]
	ok(browser_after == browser_before, "7b back on POSE the browser is as before: %s -> %s" % [browser_before, browser_after])
	root.content_scale_size = was_scale
	root.content_scale_mode = was_mode
	await idle(4)

	# 8 a cube opened from a posing page (the search box): the MODEL page comes with it (the browser steps aside)
	m.ui_page_btns["POSE"].pressed.emit()
	await idle(3)
	if m.kmed != null and m.kmed.on:
		m.kmed.stop()
		await idle(2)
	m._kmesh_edit_start()
	await idle(3)
	ok(m.cur_page == "MODEL" and not m.ui_side_of["left"].visible, "8 Test cube from POSE opens the MODEL page (page %s, browser shown %s)" % [m.cur_page, m.ui_side_of["left"].visible])
	m.kmed.stop()
	m.ui_page_btns["POSE"].pressed.emit()
	await idle(3)

	# 9 PAGE-SWITCH LEFTOVERS (walk-through 2026-10-24, REPORT.md causes 3 / 4 / 5 / 6): each mesh page shows only its own object,
	# the status line says the page's own hint on each switch, and leaving the mesh pages hides the cube, the sphere and the
	# Materials panel (back on MODEL / SURFACE with nothing lost). Materials' Name and colour fields clear of the UV panel.
	m.ui_page_btns["POSE"].pressed.emit()
	await idle(3)
	if m.kmed != null and m.kmed.on:
		m.kmed.stop()
	if m.ksc != null and m.ksc.on:
		m.ksc.stop()
	await idle(2)
	m.ui_page_btns["MODEL"].pressed.emit()
	await idle(3)
	var st_ok: bool = m.ui_status.text.begins_with("MODEL page")   # read right after the switch (before a tool says its own line)
	button(m, "MODEL", "Test cube").pressed.emit()
	await idle(3)
	m.kmed.sel.clear()
	m.kmed.sel.set_mode(KMeshSelect.FACE)
	m.kmed.sel.select_by_normal(Vector3.UP, 30.0)
	button(m, "MODEL", "Extrude").pressed.emit()
	await idle(3)
	var v_edit: int = m.kmed.mesh.vert_count()
	m.ui_page_btns["SCULPT"].pressed.emit()
	await idle(3)
	st_ok = st_ok and m.ui_status.text.begins_with("SCULPT page")
	button(m, "SCULPT", "Test sphere").pressed.emit()
	await idle(4)
	var sph_drawn: bool = _shown(m.ksc.view)
	m.ui_page_btns["SURFACE"].pressed.emit()
	await idle(3)
	st_ok = st_ok and m.ui_status.text.begins_with("SURFACE page")
	var sph_hidden: bool = m.ksc == null or not m.ksc.on or not _shown(m.ksc.view)
	var cube_back: bool = m.kmed != null and m.kmed.on and _shown(m.kmed.view) and m.kmed.mesh.vert_count() == v_edit
	ok(sph_drawn and sph_hidden and cube_back, "9a MODEL -> SCULPT -> SURFACE: the sphere is drawn on SCULPT (%s) and not on SURFACE (hidden %s); the cube is on SURFACE with its edit (%s)" % [sph_drawn, sph_hidden, cube_back])
	ok(st_ok, "9b the status line says each page's own hint on the switch (now: \"%s\")" % m.ui_status.text.left(60))
	m.ui_page_btns["POSE"].pressed.emit()
	await idle(3)
	var pose_clean: bool = not _shown(m.kmed.view) and not _shown(m.kmed.prim_panel) and not _shown(m.kmed.mat_panel) and (not _shown(m.ksc.view))
	ok(pose_clean and m.ui_status.text.begins_with("POSE page"), "9c MODEL -> POSE: the cube, the sphere, the Materials panel and the primitive panel are hidden (%s), status \"%s\"" % [pose_clean, m.ui_status.text.left(40)])
	m.ui_page_btns["MODEL"].pressed.emit()
	await idle(3)
	var came_back: bool = m.kmed.on and _shown(m.kmed.view) and m.kmed.mesh.vert_count() == v_edit
	ok(came_back, "9d POSE -> MODEL: the cube is back with its edit (%d verts, was %d)" % [m.kmed.mesh.vert_count(), v_edit])
	m.ui_page_btns["SURFACE"].pressed.emit()
	await idle(3)
	while m.kmed.mesh.materials.size() < 4:
		m.kmed.mat_panel.add_slot()
	if m.kmed.uved == null or not m.kmed.uved.visible:
		m.kmed.toggle_uv_editor()   # builds the UV panel on first use
	var lay_was: Vector2i = root.content_scale_size
	var lay_mode: int = root.content_scale_mode
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var lay_ok := true
	var lay_note := ""
	for sz in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		root.content_scale_size = sz
		await idle(6)
		if not m.kmed.uved.visible:
			m.kmed.toggle_uv_editor()
		await idle(4)
		var uv: Rect2 = m.kmed.uved.get_global_rect()
		var vr := Rect2(Vector2.ZERO, m.get_viewport().get_visible_rect().size)
		var fields := {}
		for kind in ["LineEdit", "ColorPickerButton"]:
			fields[kind] = Rect2()
			for c in m.kmed.mat_panel.find_children("*", kind, true, false):
				if (c as Control).is_visible_in_tree():
					fields[kind] = (c as Control).get_global_rect()
					break
		var fine: bool = fields["LineEdit"].size.x > 0.0 and fields["ColorPickerButton"].size.x > 0.0
		for kind in fields:
			fine = fine and vr.encloses(fields[kind]) and not (fields[kind] as Rect2).intersects(uv)
		lay_ok = lay_ok and fine
		lay_note += "%dx%d: Name %s, colour %s, UV %s; " % [sz.x, sz.y, fields["LineEdit"], fields["ColorPickerButton"], uv]
	root.content_scale_size = lay_was
	root.content_scale_mode = lay_mode
	await idle(4)
	ok(lay_ok, "9e Materials' Name and colour fields are on screen and clear of the UV panel at 1600x900 and 1280x720: %s" % lay_note)
	m.kmed.stop()
	if m.ksc != null and m.ksc.on:
		m.ksc.stop()
	await idle(2)

	# 9f the sphere opened from MODEL (search box / shortcut while the cube is open): the page moves to SCULPT, so the sphere is
	# shown and takes strokes (it stayed on MODEL, which hides the sphere: every stroke was dropped; sculptpose's 8 bars)
	m.ui_page_btns["MODEL"].pressed.emit()
	await idle(2)
	m._kmesh_edit_start()
	await idle(2)
	m._sculpt_start()
	await idle(3)
	ok(m.cur_page == "SCULPT" and m.ksc != null and m.ksc.on and m.ksc.showing,
		"9f the sphere opened from MODEL: page %s, sphere on %s, shown %s" % [m.cur_page, str(m.ksc != null and m.ksc.on), str(m.ksc != null and m.ksc.showing)])
	m.ksc.stop()
	m.kmed.stop()
	await idle(2)

	# 4 Easy mode hides the three pages
	m.easy.set_on(true, false)
	await idle(3)
	var hidden: bool = true
	for p in ["MODEL", "SCULPT", "SURFACE"]:
		hidden = hidden and not m.ui_page_btns[p].visible
	m._page_set("MODEL", false)
	ok(hidden and m.cur_page != "MODEL", "4 Easy: the three page buttons hidden (%s), a switch to MODEL refused (page %s)" % [hidden, m.cur_page])
	m.easy.set_on(false, false)
	await idle(2)

	print("MESH PAGES ", "PASS" if fails == 0 else "FAIL %d" % fails)
	TestFiles.cleanup()
	quit(1 if fails else 0)
