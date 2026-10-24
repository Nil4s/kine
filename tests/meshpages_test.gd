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
##     at 1600x900 and 1280x720, the cube open and closed; 7b the browser back on POSE exactly as before
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
		var opened := _visible_panels(m)
		var c_clash := _clashes(closed)
		var o_clash := _clashes(opened)
		ok(c_clash.is_empty() and o_clash.is_empty() and closed.has("hint") and not closed.has("browser")
			and opened.has("prim") and opened.has("mat") and opened.has("mods") and not opened.has("browser") and not opened.has("inspector"),
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
	quit(1 if fails else 0)
