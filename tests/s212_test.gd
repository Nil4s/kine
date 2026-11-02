extends SceneTree
## godot --path . --position 4000,4000 -s tests/s212_test.gd     (s212 NAME BODIES: scripts/build/part.gd bname step, part_ui.gd browser rename, easy_part_stick.gd name field,
## export names: mesh_export.gd / step_export.gd / part_names.gd; needs the CAD DLL). Bars, measured from the result:
##   1 DOUBLE   a double-click on the Body1 browser row opens a name field holding "Body1"
##   2 ENTER    typing Piston + Enter: the row reads Piston, ONE undo step, the record holds a bname step (body 0, "Piston"), Body2 stays Body2
##   3 HOVER    the timeline step's tooltip and the note line (name + volume in cm3) carry the name
##   4 FILE     the record as JSON and back (and a split replayed from it) keeps the name; the second half of a split is "Piston 2"
##   5 UNDO     one Undo gives Body1 back, Redo gives Piston
##   6 RIGHT    right-click on Body2 opens the menu with Rename; choosing it opens the field; Esc leaves the name alone (no undo step)
##   7 AGAIN    a second rename of the same body rewrites the same step (step count unchanged), still ONE undo step
##   8 EXPORT   3MF object names, GLB node names, OBJ group names and the STEP file all carry Piston and the second name, re-read from disk
##   9 EASY     Easy Part: pick a piece with a real click, type a name in its name field: ONE undo step, the pick stays, the Expert row shows it
## Shots: C:/Temp/claude/s212/rename.png (field open), named.png (named browser), easy.png (Easy name field)
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s212"
const DIRT := "user://s212_test"
var pu: PartUI


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool, btn := MOUSE_BUTTON_LEFT, dbl := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = down
	e.double_click = dbl and down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if btn == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
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


func click_ctl(c: Control, btn := MOUSE_BUTTON_LEFT) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true, btn)
	await ev_mouse(p, false, btn)
	await idle(2)


func double_click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await ev_mouse(p, true, MOUSE_BUTTON_LEFT, true)
	await ev_mouse(p, false)
	await idle(3)


func key(code: Key) -> void:
	for dn in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = dn
		root.push_input(e, true)
		await process_frame
	await idle(2)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func rect_sketch(id: String, plane: String) -> Dictionary:
	return {"t": "sketch", "id": id, "name": "Sketch" + id, "plane": plane, "ents": [{"k": "rect", "a": [0, 0], "b": [100, 60]}], "dims": []}


func two_bodies() -> Dictionary:
	var rec := Part.make("Engine")
	rec["features"] = [
		rect_sketch("f1", "front"),
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 40.0, "both": false, "op": "new"},
		{"t": "plane", "id": "f3", "name": "Plane1", "from": "front", "mm": 60.0},
		rect_sketch("f4", "f3"),
		{"t": "extrude", "id": "f5", "name": "Extrude2", "sketch": "f4", "dist": 40.0, "both": false, "op": "new"},
	]
	rec["seq"] = 5
	return rec


func cube_split() -> Dictionary:
	var rec := Part.make("Split test")
	rec["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [0, 0], "b": [100, 100]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 100.0, "both": false, "op": "new"},
		{"t": "bname", "id": "f3", "name": "Name1", "body": 0, "called": "Piston"},
		{"t": "split", "id": "f4", "name": "Split1", "plane": "right", "at": 50.0},
	]
	rec["seq"] = 4
	return rec


func names() -> Array:
	return pu.res.get("body_names", [])


func nsteps() -> int:
	return (m.S.part["features"] as Array).size()


func count_t(t: String) -> int:
	return Part.count_of(m.S.part, t)


func file_text(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	DirAccess.make_dir_recursive_absolute(SHOT)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the names cannot run")
		quit(1)
		return
	var ss: StartScreen = m.start_screen
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu = m.bld.part
	pu.set_on(false)
	m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await idle(3)
	m.S.part = two_bodies()
	pu.sync()
	await idle(4)
	ok(int(pu.res.get("bodies", 0)) == 2 and names() == ["Body1", "Body2"], "0 setup: two bodies called %s" % str(names()))

	# 1 DOUBLE
	var row0 := pu.browser.find_child("part_body_0", true, false) as Button
	await double_click_ctl(row0)
	var le := pu.browser.find_child("part_body_rename", true, false) as LineEdit
	ok(le != null and le.text == "Body1" and pu.browser.find_child("part_body_0", true, false) == null, "1 double-click on the Body1 row opens a name field holding '%s'" % (le.text if le != null else "-"))
	await shot("rename")

	# 2 ENTER
	var u0: int = m.undo.size()
	var n0 := nsteps()
	if le != null:
		le.text = "Piston"
		le.caret_column = 6
	await key(KEY_ENTER)
	var row := pu.browser.find_child("part_body_0", true, false) as Button
	var last: Dictionary = (m.S.part["features"] as Array)[-1]
	ok(row != null and row.text.strip_edges() == "Piston" and names() == ["Piston", "Body2"], "2 the row reads '%s', names %s" % [row.text.strip_edges() if row != null else "-", str(names())])
	ok(m.undo.size() == u0 + 1 and nsteps() == n0 + 1 and String(last.get("t", "")) == "bname" and int(last.get("body", -1)) == 0 and String(last.get("called", "")) == "Piston", "2 ONE undo step (%d -> %d), a bname step for body 0 'Piston' (%s)" % [u0, m.undo.size(), str(last)])
	var row1 := pu.browser.find_child("part_body_1", true, false) as Button
	ok(row1 != null and row1.text.strip_edges() == "Body2", "2 Body2 stays Body2")
	await shot("named")

	# 3 HOVER
	var tip := ""
	for c in pu.tl_row.get_children():
		var b := c.get_child(0) as Button
		if b != null and b.name == "part_step_%d" % (nsteps() - 1):
			tip = b.tooltip_text
	var vol0 := float((pu.res["volumes"] as Array)[0]) * 1e6
	var note_ok: bool = pu.note_l.text.contains("Piston %s cm3" % str(snappedf(vol0, 0.01)))
	ok(tip.contains("Piston"), "3 the timeline hover carries the name: [%s]" % tip)
	ok(note_ok, "3 the readout carries the name and its volume %.2f cm3: [%s]" % [vol0, pu.note_l.text])

	# 4 FILE
	var back: Dictionary = JSON.parse_string(JSON.stringify(m.S.part))
	var rb := Part.replay(back, -1, {"edges": false})
	ok((rb["body_names"] as Array) == ["Piston", "Body2"], "4 JSON and back replays the names %s" % str(rb["body_names"]))
	var rs := Part.replay(cube_split(), -1, {"edges": false})
	ok((rs["body_names"] as Array) == ["Piston", "Piston 2"], "4 a split replays 'Piston' and 'Piston 2': %s" % str(rs["body_names"]))
	var path := "user://s212_scene.kine"
	var saved: Variant = m.get("S")
	var js := JSON.stringify(m.S.part)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(js)
	f.close()
	var back2: Dictionary = JSON.parse_string(file_text(path))
	m.S.part = back2
	pu.sync()
	await idle(4)
	ok(names() == ["Piston", "Body2"], "4 the record re-read from disk and loaded into the app shows %s" % str(names()))

	# 5 UNDO
	m.S.part = back
	m._undo()
	await idle(4)
	var after_undo := names()
	m._redo()
	await idle(4)
	ok(after_undo == ["Body1", "Body2"] and names() == ["Piston", "Body2"], "5 Undo gives %s, Redo gives %s" % [str(after_undo), str(names())])

	# 6 RIGHT + Esc
	var row2 := pu.browser.find_child("part_body_1", true, false) as Button
	await click_ctl(row2, MOUSE_BUTTON_RIGHT)
	var menu := pu.ren_menu
	ok(menu != null and menu.item_count == 1 and menu.get_item_text(0) == "Rename" and menu.visible, "6 right-click on Body2 opens a menu with Rename")
	if menu != null:
		menu.hide()   # a real click on the item closes the menu
		menu.id_pressed.emit(0)
	await idle(3)
	var le2 := pu.browser.find_child("part_body_rename", true, false) as LineEdit
	ok(le2 != null and le2.text == "Body2", "6 Rename opens the field on Body2")
	var u1: int = m.undo.size()
	if le2 != null:
		le2.text = "Cylinder"
	await key(KEY_ESCAPE)
	ok(m.undo.size() == u1 and names() == ["Piston", "Body2"] and pu.browser.find_child("part_body_rename", true, false) == null, "6 Esc leaves the name alone: no undo step, names %s" % str(names()))
	# name Body2 through the same field (a real Enter)
	await double_click_ctl(pu.browser.find_child("part_body_1", true, false))
	le2 = pu.browser.find_child("part_body_rename", true, false) as LineEdit
	if le2 != null:
		le2.text = "Cylinder"
	await key(KEY_ENTER)
	ok(names() == ["Piston", "Cylinder"], "6 Body2 renamed Cylinder: %s" % str(names()))

	# 7 AGAIN
	var n1 := nsteps()
	var u2: int = m.undo.size()
	await double_click_ctl(pu.browser.find_child("part_body_1", true, false))
	le2 = pu.browser.find_child("part_body_rename", true, false) as LineEdit
	if le2 != null:
		le2.text = "Sleeve"
	await key(KEY_ENTER)
	ok(names() == ["Piston", "Sleeve"] and nsteps() == n1 and m.undo.size() == u2 + 1 and count_t("bname") == 2, "7 a second rename rewrites its step: steps %d -> %d, undo +%d, bname steps %d, names %s" % [n1, nsteps(), m.undo.size() - u2, count_t("bname"), str(names())])

	# 8 EXPORT
	var dir := "user://s212_out"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gd := ProjectSettings.globalize_path(dir)
	var bo := MeshExport.bodies_of(m.S.part)
	var bn: Array = (bo["bodies"] as Array).map(func(b): return String(b["name"]))
	ok(bn == ["Piston", "Sleeve"], "8 MeshExport body names %s" % str(bn))
	var r3 := MeshExport.export_part(m.S.part, "3mf", dir)
	var zr := ZIPReader.new()
	var zt := ""
	if zr.open(String(r3["path"])) == OK:
		zt = zr.read_file("3D/3dmodel.model").get_string_from_utf8()
		zr.close()
	ok(zt.contains("name=\"Piston\"") and zt.contains("name=\"Sleeve\""), "8 the 3MF file has objects named Piston and Sleeve")
	var rg: Variant = m._export_objects(dir, false, 0)
	var gnodes := []
	var gdoc := GLTFDocument.new()
	var gst := GLTFState.new()
	if String(rg) != "" and gdoc.append_from_file(ProjectSettings.globalize_path(String(rg)), gst) == OK:
		for nd in gst.get_nodes():
			gnodes.append(String((nd as GLTFNode).resource_name))
	ok(gnodes.has("Piston") and gnodes.has("Sleeve"), "8 the GLB file has nodes %s" % str(gnodes))
	var ro: Variant = m._export_obj_objects(dir, true, 0)
	var ot := file_text(ProjectSettings.globalize_path(String(ro))) if String(ro) != "" else ""
	ok(ot.contains("\no Piston\n") and ot.contains("\no Sleeve\n"), "8 the OBJ file has groups Piston and Sleeve (file %s)" % String(ro).get_file())
	var rt := StepExport.export_part(m.S.part, dir)
	var st := file_text(String(rt["path"]))
	ok(bool(rt["ok"]) and st.contains("Kine bodies: Piston, Sleeve"), "8 the STEP file names the bodies: %s" % (st.substr(st.find("FILE_DESCRIPTION"), 70) if st.contains("FILE_DESCRIPTION") else "none"))
	var bare := Part.replay(two_bodies(), -1, {"edges": false})
	ok((bare["body_names"] as Array) == ["Body1", "Body2"] and (m._free_part_object().get("name", "") == "Engine"), "8 an unnamed part still exports as one object named by the part")

	# 9 EASY
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep
	m.S.part = two_bodies()
	pu.sync()
	await idle(4)
	await idle(10)
	var faces: Array = Part.body_faces(m.S.part, -1)
	var cen := Vector3.ZERO
	var cn := 0
	for v in faces[1]:
		cen += v
		cn += 1
	cen /= float(maxi(cn, 1))
	var scr: Vector2 = m.cam.unproject_position(cen)
	await click_ctl_at(scr)
	var picked: bool = ep.del_on
	ok(picked and ep.del_bi >= 0, "9 a real click on a piece picks it (body %d)" % ep.del_bi)
	var ne := root.find_child("easypart_name_edit", true, false) as LineEdit
	ok(ne != null and ne.is_visible_in_tree() and ne.text == "Body%d" % (ep.del_bi + 1), "9 the name field shows '%s'" % (ne.text if ne != null else "-"))
	if ne != null and picked:
		var tb: int = ep.del_bi
		var u3: int = m.undo.size()
		await click_ctl(ne)
		ne.text = "Crank"
		await key(KEY_ENTER)
		ok(names()[tb] == "Crank" and m.undo.size() == u3 + 1 and ep.del_on, "9 typed Crank: names %s, ONE undo step (%d -> %d), the pick stays (%s)" % [str(names()), u3, m.undo.size(), str(ep.del_on)])
		var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))
		ok(vp.encloses(ne.get_global_rect()) and vp.encloses((ne.get_parent().get_parent() as Control).get_global_rect()), "9 the name field is on the 1280 x 720 screen: %s" % str(ne.get_global_rect()))
		await shot("easy")
		var steps_txt := ""
		for l in ep.steps_box.find_children("*", "Label", true, false):
			steps_txt += (l as Label).text + "|"
		for l in ep.steps_box.find_children("*", "Button", true, false):
			steps_txt += (l as Button).text + "|"
		ok(steps_txt.contains("Named piece"), "9 the step list says it: [%s]" % steps_txt.left(160))
	print("s212: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func click_ctl_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)
