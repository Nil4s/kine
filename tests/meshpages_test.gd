extends SceneTree
## MESH PAGES (the MODEL / SCULPT / SURFACE pages, scripts/expert_pages.gd): the three pages that were greyed "coming"
## until the mesh tools landed are real pages now. Bars, stated before measuring:
##   1 each of MODEL, SCULPT, SURFACE opens in Expert (the page shows, its ribbon row has >= 3 live tools)
##   2 MODEL: extrude one face of the test cube from the ribbon: the vertex count grows (8 -> 12 for a cube face), one undo step
##   3 SCULPT: a draw stroke from the ribbon on the test sphere: >= 10 verts move
##   4 Easy mode hides the three pages (their page-bar buttons not visible; a page switch to one is refused)
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
