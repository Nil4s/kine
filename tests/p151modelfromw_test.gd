extends SceneTree
## godot --headless -s tests/p151modelfromw_test.gd     (Friday plan 151: MODEL FROM WORDS, TYPED STEPS on the MODEL page)
## A beginner walk with real clicks and real keys at 1280 x 720: the test cube's panel "Model from words" (scripts/mesh_steps.gd)
## keeps each typed phrase as one row; a row can be edited (Enter runs the list again from it) or removed (x); Ctrl+Z takes the
## newest step back. Bars written before the code. Every measure is read from the built result (the mesh's verts and faces,
## the undo record, the rows on screen, the panel's rect), never from the code's own variables.
## The test cube is 0.60 m tall (y -0.30 .. +0.30), 96 faces. Bars:
##   P1 OPEN: the MODEL page (the test cube opens) shows the steps panel, the panel lies inside
##      the 1280 x 720 window, and it does not overlap the Add primitive panel (no shared pixel)
##   P2 ADD: a real click in the box, "extrude the top 5 cm" typed, a real Enter -> 1 row showing that text; 96 -> 112 faces;
##      ONE undo step (undo count +1); the top at y 0.35 m within 0.1 mm
##   P3 ADD 2: "make it 2 cm thicker" typed and Entered -> 2 rows; the mesh is 2 cm taller (0.02 m within 0.1 mm); ONE undo step
##   P4 EDIT: a real click in row 1, its words changed to "extrude the top 10 cm" (real Backspace and typing), a real Enter -> the
##      list runs again: 2 rows, the mesh 0.72 m tall (0.60 + 0.10 + 0.02 within 0.1 mm), 112 faces, undo count 2 (one step per row)
##   P5 REMOVE: a real click on row 2's x -> 1 row (the 10 cm extrude), the mesh 0.70 m tall within 0.1 mm, undo count 1
##   P6 REFUSED: "extrdue the top 5 cm" typed and Entered -> refused in words: rows still 1, undo count still 1, the box keeps the
##      words, the panel's words name a next step ("extrude" appears in them)
##   P7 CTRL+Z: a real Ctrl+Z with the cube open -> the newest step (row) goes too: 0 rows, 96 faces, 0.60 m tall within 0.1 mm
const SHOT := "user://p151modelfromw"
var fails := 0
var m: Node
var ui: KMeshEditUI


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


func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame


## a real press and release at the middle of a control
func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func key(code: int, uni := 0, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code as Key
	e.physical_keycode = code as Key
	e.unicode = uni
	e.ctrl_pressed = ctrl
	e.pressed = true
	root.push_input(e, true)
	await process_frame
	e = e.duplicate()
	e.pressed = false
	root.push_input(e, true)
	await process_frame


## each character typed as a real key press
func type_text(t: String) -> void:
	for i in t.length():
		var c := t[i]
		var code := c.to_upper().unicode_at(0)
		if c == " ":
			code = KEY_SPACE
		await key(code, t.unicode_at(i))
	await idle(2)


func steps_panel() -> Control:
	return _find("mesh_steps_panel") as Control


func _find(nm: String) -> Node:
	for n in root.find_children(nm, "", true, false):
		return n
	return null


func add_box() -> LineEdit:
	return _find("steps_add") as LineEdit


func rows() -> Array:
	var r: Array = []
	for n in root.find_children("steps_row_*", "LineEdit", true, false):
		r.append(n)
	return r


func row_btn(i: int) -> Button:
	return _find("steps_remove_%d" % i) as Button


func height() -> float:
	return MeshWords.bbox(ui.mesh).size.y


func top() -> float:
	var y := -INF
	for v in ui.mesh.verts:
		y = maxf(y, v.y)
	return y


func _init() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))   # the bar's window: 1280 x 720
	await idle(3)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	m._load_scene("res://scenes/combo3.json")
	await idle(3)
	m._commands()
	await idle(2)

	# P1 OPEN: the test cube opens on the MODEL page (the page's own open; the ribbon click is not used: the scene's body would open)
	m._kmesh_edit_start()
	ui = m.kmed
	await idle(5)
	var panel := steps_panel()
	var prim: Control = ui.prim_panel
	var inside := false
	var overlap := true
	if panel != null and panel.visible:
		var r := panel.get_global_rect()
		inside = r.position.x >= 0 and r.position.y >= 0 and r.end.x <= 1280 and r.end.y <= 720
		overlap = prim != null and prim.visible and r.intersects(prim.get_global_rect())
	var rect_s := str(panel.get_global_rect()) if panel != null else "none"
	ok(panel != null and panel.visible and inside and not overlap, "P1 the MODEL page: steps panel visible %s, inside 1280 x 720 %s (panel %s, window %s), no overlap with Add primitive %s" % [str(panel != null and panel.visible), str(inside), rect_s, str(root.get_visible_rect().size), str(not overlap)])

	# P2 ADD: real click in the box, typed, real Enter
	var v0 := ui.mesh.face_count()
	var u0 := ui.undo.steps.size()
	await click_ctl(add_box())
	await type_text("extrude the top 5 cm")
	await key(KEY_ENTER)
	await idle(3)
	var rw := rows()
	var t1 := top()
	ok(rw.size() == 1 and rw[0].text == "extrude the top 5 cm" and ui.mesh.face_count() == 112 and ui.undo.steps.size() - u0 == 1 and absf(t1 - 0.35) < 1e-4,
		"P2 extrude the top 5 cm typed: %d row (bar 1), %d -> %d faces (bar 112), %d undo step (bar 1), top y %.5f m (bar 0.35000 within 0.1 mm)" % [rw.size(), v0, ui.mesh.face_count(), ui.undo.steps.size() - u0, t1])

	# P3 ADD 2: a second phrase is one more row and one more undo step; the mesh grows 2 cm taller
	var h0 := height()
	var u1 := ui.undo.steps.size()
	await click_ctl(add_box())
	await type_text("make it 2 cm thicker")
	await key(KEY_ENTER)
	await idle(3)
	var dh := height() - h0
	rw = rows()
	ok(rw.size() == 2 and absf(dh - 0.02) < 1e-4 and ui.undo.steps.size() - u1 == 1,
		"P3 make it 2 cm thicker typed: %d rows (bar 2), taller by %.5f m (bar 0.02000 within 0.1 mm), %d undo step (bar 1)" % [rw.size(), dh, ui.undo.steps.size() - u1])

	# P4 EDIT: row 1 changed by real clicks and keys; the list runs again from it
	await click_ctl(rw[0])
	for i in 30:
		await key(KEY_BACKSPACE)
	await type_text("extrude the top 10 cm")
	await key(KEY_ENTER)
	await idle(3)
	rw = rows()
	var h4 := height()
	ok(rw.size() == 2 and absf(h4 - 0.72) < 1e-4 and ui.mesh.face_count() == 112 and ui.undo.steps.size() == 2,
		"P4 row 1 edited to 10 cm: %d rows (bar 2), %.5f m tall (bar 0.72000 within 0.1 mm), %d faces (bar 112), undo count %d (bar 2)" % [rw.size(), h4, ui.mesh.face_count(), ui.undo.steps.size()])

	# P5 REMOVE: row 2's x removes the thicker step; the 10 cm extrude stays
	await click_ctl(row_btn(2))
	await idle(3)
	rw = rows()
	var h5 := height()
	ok(rw.size() == 1 and absf(h5 - 0.70) < 1e-4 and ui.undo.steps.size() == 1,
		"P5 row 2 removed: %d row (bar 1), %.5f m tall (bar 0.70000 within 0.1 mm), undo count %d (bar 1)" % [rw.size(), h5, ui.undo.steps.size()])

	# P6 REFUSED: a typo is refused in words; nothing changes and the box keeps the words
	var u6 := ui.undo.steps.size()
	await click_ctl(add_box())
	await type_text("extrdue the top 5 cm")
	await key(KEY_ENTER)
	await idle(3)
	var say := _find("steps_say") as Label
	rw = rows()
	ok(rw.size() == 1 and ui.undo.steps.size() == u6 and add_box().text == "extrdue the top 5 cm" and say != null and "extrude" in say.text,
		"P6 typo refused: %d row (bar 1), undo count %d -> %d (bar unchanged), box keeps the words %s, the words say %s" % [rw.size(), u6, ui.undo.steps.size(), str(add_box().text == "extrdue the top 5 cm"), "extrude" in (say.text if say != null else "")])

	# P7 CTRL+Z: the newest step is taken back and its row goes with it
	await key(KEY_Z, 0, true)
	await idle(3)
	rw = rows()
	var h7 := height()
	ok(rw.size() == 0 and ui.mesh.face_count() == 96 and absf(h7 - 0.60) < 1e-4,
		"P7 Ctrl+Z: %d rows (bar 0), %d faces (bar 96), %.5f m tall (bar 0.60000 within 0.1 mm)" % [rw.size(), ui.mesh.face_count(), h7])

	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png(SHOT + "/p151_end.png")
	print("shot: " + ProjectSettings.globalize_path(SHOT + "/p151_end.png"))
	print("p151modelfromw: %d fail(s)" % fails)
	quit(1 if fails > 0 else 0)
