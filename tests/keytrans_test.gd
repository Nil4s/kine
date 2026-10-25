## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/keytrans_test.gd    (ROADMAP_400 P20)
## COMING FROM BLENDER / MAYA. Bars (stated before measuring):
##  1 every Kine command id the tables map exists in the real registry: 0 dangling (and "@search" = a real S opens the box)
##  2 >= 35 Blender and >= 20 Maya entries
##  3 mode on: a simulated I shows a toast naming Kine's K and "Key the part here"; off: no toast; a key Kine already
##    does the same way (Ctrl+Z) shows none; a key Kine uses otherwise (R) shows a toast but Kine's R still resets the part
##    unless "keys win" is on (then M, mapped to Add marker, adds a marker instead of copying the arm)
##  4 PLACEMENT: the toast sits in the viewport, in the top-centre of the 3D view (below the ribbon, over the body view,
##    not off screen), whole body in view. Screenshot: env KEYTRANS_SHOT (default user://keytrans.png)
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


func send(code: Key, down: bool, shift := false, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.shift_pressed = shift
	e.ctrl_pressed = ctrl
	e.pressed = down
	root.push_input(e)
	await process_frame
	await idle(2)


func tap(code: Key, shift := false, ctrl := false) -> void:
	await send(code, true, shift, ctrl)
	await send(code, false, shift, ctrl)


func toast_text() -> String:
	var t: Label = m.kt.toast
	return t.text if t != null and is_instance_valid(t) and t.is_visible_in_tree() else ""


func cmd_run(id: String) -> void:
	for c in m.ui_cmd.commands:
		if c["id"] == id:
			(c["run"] as Callable).call()


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	ok(m.settings.begins_with("user://poser_test_"), "0 the test saves to its own config (%s)" % m.settings)

	# 1. no dangling command
	var dang := KeymapTranslate.dangling(m.ui_cmd.commands)
	ok(dang.is_empty(), "1 every mapped Kine command exists in the registry: %d dangling %s" % [dang.size(), dang])
	await tap(KEY_S)
	ok(m.ui_cmd.visible, "1b '@search' is real: S opens the command box")
	m.ui_cmd.close()
	await idle(2)

	# 2. table sizes
	var nb := KeymapTranslate.BLENDER.size()
	var nm := KeymapTranslate.MAYA.size()
	var mapped_b := KeymapTranslate.BLENDER.filter(func(e): return String(e[2]) != "").size()
	ok(nb >= 35 and nm >= 20, "2 entries: %d Blender (%d mapped), %d Maya" % [nb, mapped_b, nm])

	# 3. the toast
	m._card_add()
	m.sel = "upperarm_r"
	m._view(1)
	await idle(3)
	await tap(KEY_I)
	ok(toast_text() == "", "3a helper off: I shows no toast")
	m.kt.set_mode("blender", true)
	await tap(KEY_I)
	var t: String = toast_text()
	print("     toast: ", t.replace("\n", " | "))
	ok("In Blender, I inserts a keyframe" in t and "that's K (Key the part here)" in t, "3b Blender mode: I shows the toast naming Kine's K")
	var u0: int = m.undo.size()
	await send(KEY_ENTER, true, true)
	await send(KEY_ENTER, false, true)
	ok(m.S.part_keys.has("upperarm_r") and m.undo.size() == u0 + 1, "3c Shift+Enter ran the offered command (key the part, one undo step)")
	print("     after offer: ", toast_text().replace("
", " | "))
	ok(toast_text() == "", "3d the toast is gone after the offer is taken")
	await tap(KEY_Z, false, true)
	ok(toast_text() == "", "3e Ctrl+Z (Kine does the same) shows no toast")
	# a key Kine uses otherwise: toast, Kine's own action still runs
	m.B.ang["upperarm_r"] = Vector3(30, 0, 0)
	await tap(KEY_R)
	ok("In Blender, R rotates" in toast_text() and "Kine has no equivalent yet" in toast_text() and "Reset the part" in toast_text(),
		"3f R: toast says Kine has no equivalent and that Kine's R is Reset the part")
	ok(m.B.ang["upperarm_r"].length() < 0.01, "3g ... and Kine's R still reset the part (the helper did not block it)")
	# Maya
	m.kt.set_mode("maya", true)
	await tap(KEY_S)
	ok("In Maya, S sets a key" in toast_text() and "that's K (Key the part here)" in toast_text(), "3h Maya mode: S shows Kine's K")
	ok(m.ui_cmd.visible, "3i ... S still opens Kine's command box (not blocked)")
	m.ui_cmd.close()
	await idle(2)
	# keys win
	m.kt.set_mode("blender", true)
	m.kt.set_wins(true, true)
	var nmk: int = m.S.markers.size()
	await tap(KEY_M)
	ok(m.S.markers.size() == nmk + 1, "3j keys win: Blender M ran Add marker (%d -> %d) instead of Kine's M" % [nmk, m.S.markers.size()])
	m.kt.set_wins(false, true)
	# saved
	var cf := ConfigFile.new()
	cf.load(m.settings)
	ok(cf.get_value("look", "keytrans", "") == "blender" and cf.get_value("look", "keytrans_wins", true) == false, "3k the mode is saved in the test config")
	var k2 := KeymapTranslate.new(m)
	k2.load_from(m.settings)
	ok(k2.mode == "blender", "3l read back")
	# the commands exist
	var have := ["help_i_come_from_blender", "help_i_come_from_maya", "help_blender_maya_key_helper_off", "help_blender_maya_keys_win_on_off"].filter(func(id): return KeymapTranslate.command(m.ui_cmd.commands, id).is_empty())
	ok(have.is_empty(), "3m the four helper commands are in the palette (missing %s)" % [have])
	cmd_run("help_blender_maya_key_helper_off")
	await tap(KEY_I)
	ok(m.kt.mode == "" and toast_text() == "", "3n the off command turns the helper off: no toast")

	# 4. placement
	m.kt.set_mode("blender", false)
	m._view(1)
	await idle(2)
	await tap(KEY_G, false, false)
	await tap(KEY_N)
	await tap(KEY_I)
	await idle(3)
	var vp := m.get_viewport().get_visible_rect()
	var r: Rect2 = m.kt.toast.get_global_rect()
	var view_c := vp.size.x * 0.5
	print("     toast rect %s in viewport %s" % [r, vp])
	ok(vp.encloses(r) and r.position.y >= 100.0 and absf(r.get_center().x - view_c) < vp.size.x * 0.25,
		"4 the toast is on screen, top-centre of the view, below the ribbon (y %.0f)" % r.position.y)
	var shot := OS.get_environment("KEYTRANS_SHOT")
	if shot == "":
		shot = "user://keytrans.png"
	m.get_viewport().get_texture().get_image().save_png(shot)
	print("     screenshot: ", shot)
	print("KEYTRANS: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
