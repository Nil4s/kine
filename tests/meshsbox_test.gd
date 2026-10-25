## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/meshsbox_test.gd    (mesh edit friction, hobbyist walk-through)
## Bars, written before measuring:
##  (a) in mesh edit (the test cube), F3 opens the S box: visible and focused, and the mesh's scale mode did NOT start
##      (BlKeys.active is "": S is Scale here, so S cannot be the way in)
##  (b) typed into the open box, "subdivide" is not sent to the mesh (no scale mode starts, the mesh is unchanged until
##      Enter); Enter runs the first row (the Subdivide tool), the faces grow and the box closes; then S starts scale again
##      (BlKeys.active "S") and Esc cancels it
##  (c) at 1280 x 720, after an extrude ("Model: extrude by 10 cm; the new part is selected (Ctrl+Z takes it back)"): the status line's full text is readable: either its font width fits the label, or it wraps (autowrap
##      on, its wrapped height fits the label) and its rect does not overlap the readout's (ui_bar) rect; both are on screen.
##      Screenshot to the file named by env MESHSB_SHOT when set.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func key(k: int) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k as Key
		e.physical_keycode = k as Key
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


func typed(c: String) -> void:   # one typed character, as the keyboard sends it (the box takes its unicode)
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = c.to_upper().unicode_at(0) as Key
		e.physical_keycode = e.keycode
		e.unicode = c.unicode_at(0)
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(1)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.get_window().size = Vector2i(1280, 720)
	await idle(8)
	m._kmesh_edit_start()
	await idle(4)
	var km: KMesh = m.kmed.mesh
	var verts0 := km.vert_count()
	var faces0 := km.face_count()

	# ---- (a) F3 opens the S box; S is not the way in
	await key(KEY_F3)
	ok(m.ui_cmd.visible and m.ui_cmd.box.has_focus(), "(a) F3 in mesh edit opens the S box, visible and focused (visible %s, focus %s)" % [m.ui_cmd.visible, m.ui_cmd.box.has_focus()])
	ok(m.blk.active == "", "(a) the mesh's scale mode did not start (BlKeys.active '%s')" % m.blk.active)

	# ---- (b) typing goes to the box, not the mesh
	for c in "subdivide":
		await typed(c)
	ok(m.ui_cmd.box.text == "subdivide", "(b) typed into the box: '%s'" % m.ui_cmd.box.text)
	ok(m.blk.active == "" and km.vert_count() == verts0 and km.face_count() == faces0,
		"(b) the typing did not reach the mesh: scale %s, %d verts %d faces (were %d / %d)" % [m.blk.active, km.vert_count(), km.face_count(), verts0, faces0])
	var first: String = m.ui_cmd.shown[0]["name"] if not m.ui_cmd.shown.is_empty() else ""
	print("  first row: ", first)
	await key(KEY_ENTER)
	await idle(4)
	ok(not m.ui_cmd.visible and not m.ui_cmd.box.has_focus(), "(b) Enter runs and closes the box")
	var faces1 := KMeshModifiers.evaluate(km).face_count()   # the subdivide is a modifier: the surface shown is the evaluated one
	ok(first.to_lower().contains("subdivid") and faces1 > faces0,
		"(b) Enter runs 'subdivide': the shown faces %d -> %d (first row '%s')" % [faces0, faces1, first])
	await key(KEY_A)   # S scales the selected vertices: select them first
	await key(KEY_S)
	ok(m.blk.active == "S", "(b) after the box closes, S starts scale again (BlKeys.active '%s')" % m.blk.active)
	await key(KEY_ESCAPE)
	await idle(2)
	ok(m.blk.active == "" and m.kmed.on, "(b) Esc cancels the scale; the mesh is still open")

	# ---- (c) the status line's full text at 1280 x 720 (the test window opens at its host's size: pin the UI to 1280 x 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	await idle(6)
	await key(KEY_E)   # the extrude's message: E, a typed distance in metres (0.1 = 10 cm), Enter
	for c in "0.1":
		typed(c)
	await key(KEY_ENTER)
	await idle(6)
	var st: Label = m.ui_status
	var bar: Label = m.ui_bar
	var text := st.text
	print("  status: ", text)
	var win := root.get_visible_rect()
	print("  the UI at %s" % win.size)
	var r := st.get_global_rect()
	var rb := bar.get_global_rect()
	var f := st.get_theme_font("font")
	var fs := st.get_theme_font_size("font_size")
	var full_w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var wrapped_h := f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, r.size.x, fs).y
	print("  status rect %s, readout rect %s, window %s, text %.0f px wide, wrapped %.0f px tall" % [r, rb, win.size, full_w, wrapped_h])
	var fits := full_w <= r.size.x
	var wraps := st.autowrap_mode != TextServer.AUTOWRAP_OFF and wrapped_h <= r.size.y + 1.0 and not r.intersects(rb)
	ok(text.begins_with("Model: extrude by") and text.contains("Ctrl+Z"), "(c) the extrude message is on the status line: '%s'" % text)
	ok(win.encloses(r) and win.encloses(rb) and (fits or wraps),
		"(c) the full status text is readable at 1280 x 720: fits the label (%.0f <= %.0f) or wraps clear of the readout (text %.0f px tall in a %.0f px label, rects %s / %s)" % [full_w, r.size.x, wrapped_h, r.size.y, r, rb])
	# (d) on its own row the message lies over the 3D view (the body's legs behind it): a dim box behind the words
	var sbx := st.get_theme_stylebox("normal")
	var bg_a: float = (sbx as StyleBoxFlat).bg_color.a if sbx is StyleBoxFlat else 0.0
	ok(st.autowrap_mode == TextServer.AUTOWRAP_OFF or bg_a >= 0.7, "(d) the wrapped message has a box behind it over the 3D view (alpha %.2f, at least 0.70)" % bg_a)
	var shot := OS.get_environment("MESHSB_SHOT")
	await RenderingServer.frame_post_draw
	if shot != "":
		root.get_texture().get_image().save_png(shot)
		print("  shot -> ", shot)

	print("MESH SANDBOX ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails else 0)

