## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/blkeys_test.gd    (ROADMAP_400 B16)
## BLENDER-STYLE MODAL KEYS (layer, off by default). Bars (stated before measuring):
##  1 layer OFF (default): R resets the picked part (angles -> 0, one undo step), S opens the command box, G is the second
##    hand (its status words), and X / Y / Z start no modal edit (blk.active stays "")
##  2 layer ON via its command: R X 45 Enter on the right forearm turns it 45.0 +- 0.5 deg about its local X (the elbow-
##    to-hand vector turns by that angle), exactly ONE undo step; Ctrl+Z restores the pose bit-exact
##  3 R X 30 then Esc: the pose (B.state()) is bit-exact the one before and no undo step is left
##  4 G on the right hand with X 0.1 moves the hand 0.1 m (+-5 mm; IK) along world X; Esc puts it back bit-exact
##  5 S on a joint says why (status names a next step) and starts nothing
##  6 mesh preview: select 5 vertices, G X 0.25 Enter: those move by exactly 0.25 on X (1e-6), the others not at all, ONE
##    KMeshUndo step; Esc mid-move restores the vertex array bit-exact and keeps no step; R Z 90 Enter keeps their
##    distances to the centre (+-1e-5); Ctrl+Z takes the step back
##  7 PLACEMENT: mid-rotate, the status line shows "R  X  45" and sits inside the window (whole-window screenshot,
##    env BLKEYS_SHOT) with its text not clipped
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


func tap(code: Key, ctrl := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.ctrl_pressed = ctrl
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


func typ(s: String) -> void:
	for ch in s:
		await tap(KEY_PERIOD if ch == "." else (KEY_0 + int(ch)) as Key)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	ok(m.settings.begins_with("user://poser_test_"), "0 own config (%s)" % m.settings)
	m._card_add()
	m._view(1)

	# 1. layer off
	ok(not m.blk.on, "1a the layer is off by default")
	m.sel = "lowerarm_r"
	m.B.ang["lowerarm_r"] = Vector3(40, 0, 0)
	m.B.fk()
	var u0: int = m.undo.size()
	await tap(KEY_R)
	ok(m.B.ang["lowerarm_r"].length() < 0.01 and m.undo.size() == u0 + 1 and m.blk.active == "", "1b R resets the part (one step), no modal")
	await tap(KEY_G)
	ok("second hand" in m.ui_status.text and m.blk.active == "", "1c G is the second hand (%s)" % m.ui_status.text)
	await tap(KEY_X)
	await tap(KEY_Y)
	await tap(KEY_Z)
	ok(m.blk.active == "", "1d X / Y / Z start nothing")
	await tap(KEY_S)
	ok(m.ui_cmd.visible and m.blk.active == "", "1e S opens the command box")
	m.ui_cmd.close()
	await idle(2)

	# 2. layer on through its command
	var found := false
	for c in m.ui_cmd.commands:
		if String(c["name"]) == "Keys: Blender-style G R S on / off":
			(c["run"] as Callable).call()
			found = true
	ok(found and m.blk.on, "2a the command exists and turns the layer on")
	var cf := ConfigFile.new()
	cf.load(m.settings)
	ok(cf.get_value("look", "blkeys", false) == true, "2b remembered in the test config")
	m.sel = "lowerarm_r"
	m.B.ang["lowerarm_r"] = Vector3(20, 0, 0)
	m.B.fk()
	m._refresh()
	var v0: Vector3 = m.B.P["hand_r"] - m.B.P["lowerarm_r"]
	var a0: Vector3 = m.B.ang["lowerarm_r"]
	u0 = m.undo.size()
	await tap(KEY_R)
	await tap(KEY_X)
	await typ("45")
	print("     readout: ", m.ui_status.text)
	ok(m.blk.active == "R" and m.ui_status.text.begins_with("R  X  45°"), "2c mid-rotate the readout reads 'R  X  45°'")
	# 7. placement + screenshot mid-rotate
	await idle(3)
	var vp := m.get_viewport().get_visible_rect()
	var r: Rect2 = m.ui_status.get_global_rect()
	var f: Font = m.ui_status.get_theme_font("font")
	var tw := f.get_string_size(m.ui_status.text, HORIZONTAL_ALIGNMENT_LEFT, -1, m.ui_status.get_theme_font_size("font_size")).x
	print("     status rect %s text %.0f px viewport %s" % [r, tw, vp])
	ok(m.ui_status.is_visible_in_tree() and vp.encloses(r) and r.size.x >= tw - 2.0 and r.position.y > vp.size.y * 0.5, "7 the readout is inside the status line, on screen, not clipped (rect %s)" % r)
	var shot := OS.get_environment("BLKEYS_SHOT")
	if shot == "":
		shot = "user://blkeys.png"
	m.get_viewport().get_texture().get_image().save_png(shot)
	print("     screenshot: ", shot)
	await tap(KEY_ENTER)
	var v1: Vector3 = m.B.P["hand_r"] - m.B.P["lowerarm_r"]
	var turned := rad_to_deg(v0.angle_to(v1))
	var da: float = m.B.ang["lowerarm_r"].x - a0.x
	print("     bend +%.3f deg, bone turned %.3f deg" % [da, turned])
	ok(absf(da - 45.0) <= 0.5 and absf(turned - 45.0) <= 0.5 and m.undo.size() == u0 + 1 and m.blk.active == "",
		"2d R X 45 Enter: forearm +%.2f deg about local X (bone %.2f), one undo step (%d)" % [da, turned, m.undo.size() - u0])
	await tap(KEY_Z, true)
	ok(m.B.ang["lowerarm_r"] == a0 and m.undo.size() == u0, "2e Ctrl+Z restores the pose bit-exact")

	# 3. Esc restores
	var s0: Dictionary = m.B.state()
	u0 = m.undo.size()
	await tap(KEY_R)
	await tap(KEY_X)
	await typ("30")
	ok(m.B.ang["lowerarm_r"].x > a0.x + 29.0, "3a mid-rotate the forearm is turned (%.1f)" % m.B.ang["lowerarm_r"].x)
	await tap(KEY_ESCAPE)
	ok(m.B.state() == s0 and m.undo.size() == u0 and m.blk.active == "", "3b Esc: pose bit-exact, no step left")

	# 4. grab
	m.sel = "hand_r"
	var h0: Vector3 = m.B.P["hand_r"]
	s0 = m.B.state()
	await tap(KEY_G)
	await tap(KEY_X)
	await typ("0.1")
	var dh: Vector3 = m.B.P["hand_r"] - h0
	print("     hand moved ", dh, " readout ", m.ui_status.text)
	ok(absf(dh.x - 0.1) <= 0.005 and absf(dh.y) <= 0.01 and absf(dh.z) <= 0.01 and m.ui_status.text.begins_with("G  X  0.1 m"), "4a G X 0.1 moves the hand 0.1 m along X (%.4f)" % dh.x)
	await tap(KEY_ESCAPE)
	ok(m.B.state() == s0, "4b Esc puts the hand back bit-exact")

	# 5. S on a joint
	m.sel = "lowerarm_r"
	await tap(KEY_S)
	ok(m.blk.active == "" and "no size" in m.ui_status.text and "Proportions" in m.ui_status.text, "5 S on a joint says why (%s)" % m.ui_status.text.left(60))

	# 6. mesh preview
	m._kmesh_edit_start()
	await idle(3)
	var ui = m.kmed
	for i in [0, 3, 7, 11, 20]:
		ui.sel.verts[i] = true
	var base: PackedVector3Array = ui.mesh.verts.duplicate()
	await tap(KEY_G)
	await tap(KEY_X)
	await typ("0.25")
	await tap(KEY_ENTER)
	var worst := 0.0
	var other := 0.0
	for i in base.size():
		var want := base[i] + (Vector3(0.25, 0, 0) if ui.sel.verts.has(i) else Vector3.ZERO)
		var e: float = (ui.mesh.verts[i] - want).length()
		if ui.sel.verts.has(i):
			worst = maxf(worst, e)
		else:
			other = maxf(other, e)
	ok(worst < 1e-6 and other == 0.0 and ui.undo.steps.size() == 1, "6a G X 0.25: selected err %s, others %s, KMeshUndo steps %d" % [str(worst), str(other), ui.undo.steps.size()])
	var moved: PackedVector3Array = ui.mesh.verts.duplicate()
	await tap(KEY_G)
	await tap(KEY_Y)
	await typ("0.4")
	await tap(KEY_ESCAPE)
	ok(ui.mesh.verts == moved and ui.undo.steps.size() == 1, "6b Esc mid-move: vertices bit-exact, still one step")
	var c0 := Vector3.ZERO
	for i in ui.sel.verts:
		c0 += moved[i]
	c0 /= 5.0
	await tap(KEY_R)
	await tap(KEY_Z)
	await typ("90")
	await tap(KEY_ENTER)
	var dr := 0.0
	for i in ui.sel.verts:
		dr = maxf(dr, absf((ui.mesh.verts[i] - c0).length() - (moved[i] - c0).length()))
	ok(dr < 1e-5 and ui.mesh.verts != moved and ui.undo.steps.size() == 2, "6c R Z 90: distances to the centre kept (%s), 2 steps" % str(dr))
	await tap(KEY_Z, true)
	ok(ui.mesh.verts == moved and ui.undo.steps.size() == 1, "6d Ctrl+Z takes the rotate back")
	m.blk.set_on(false, false)
	print("BLKEYS: %d failed" % fails)
	quit(1 if fails > 0 else 0)
