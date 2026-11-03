extends SceneTree
## godot --path . --position 4000,4000 -s tests/c28_test.gd     (C28: the FBX "For:" choice in the Export dialog; finishes C23's write_preset)
## BARS, written before any number was read:
##  A  CHOICE  the dialog carries an OptionButton "opt_fbx_for" with 4 entries (Default, Unity, Unreal, Blender), Default selected; it sits inside the 1280 x 720 window.
##  B  DEFAULT with the choice untouched, m._export_fbx writes a binary .fbx whose bytes equal FbxExport.write's of the same scene (byte-identical); UnitScaleFactor reads 1.
##  C  UNITY   a REAL click on the button + Down + Enter picks Unity (ExportNames.fbx_for == "unity"); m._export_fbx then writes a binary .fbx whose UnitScaleFactor reads 100
##             and whose first non-zero bone translation, in metres (value x factor / 100), equals the default file's within 1e-4.
##             CONTROL: the Unity numbers read under the default factor (1) are 100x off, so the equality bar fails on them.
##  D  1 M     ExportNames.fbx_write (what the choice sends to the writer) with a 1 m offset up reads 1.0000 m (translation x factor / 100) within 1e-4 for
##             Default, Unity, Unreal, Blender. Picking Unreal by click puts UpAxis 2 in the binary file.
const SHOT := "C:/Users/Nick/tools/kine_workers/out/c28"
const DIR := "user://zz_c28"
var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func _watchdog() -> void:
	await create_timer(400.0).timeout
	print("FAIL watchdog: the test did not finish in 400 s")
	quit(1)


func key(k: Key) -> void:
	for d in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = d
		root.push_input(e, true)
		await process_frame


func click(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	root.push_input(mv, true)
	await process_frame
	for d in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = d
		e.position = p
		e.global_position = p
		if d:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e, true)
		await process_frame
	await idle(2)


## the doubles after the property named nm in a binary FBX (n of them; the first non-zero triple when nonzero)
func bin_doubles(b: PackedByteArray, nm: String, n: int, nonzero := false) -> Array:
	var pat := nm.to_ascii_buffer()
	var from := 0
	while true:
		var i := -1
		for k in range(from, b.size() - pat.size()):
			if b[k] == pat[0] and b.slice(k, k + pat.size()) == pat:
				i = k
				break
		if i < 0:
			return []
		from = i + pat.size()
		var vals := []
		var j := from
		while j < mini(from + 120, b.size() - 9) and vals.size() < n:
			if b[j] == 68:
				var v := b.decode_double(j + 1)
				if absf(v) < 1e9:
					vals.append(v)
					j += 9
					continue
			j += 1
		if vals.size() == n and (not nonzero or absf(vals[0]) + absf(vals[1]) + absf(vals[2]) > 1e-6):
			return vals
	return []


## the Integer property nm of a binary FBX (-1 when absent)
func bin_int(b: PackedByteArray, nm: String) -> int:
	var pat := nm.to_ascii_buffer()
	var i := -1
	for k in range(0, b.size() - pat.size()):
		if b[k] == pat[0] and b.slice(k, k + pat.size()) == pat:
			i = k
			break
	if i < 0:
		return -1
	var j := i + nm.length()
	while j < b.size() - 5 and not (b[j] == 73 and b[j - 1] == 0 and b[j - 2] == 0 and b[j - 3] == 0 and b[j - 4] == 0):
		j += 1
	return b.decode_s32(j + 1)


func fbx_facts(t: String) -> Dictionary:
	var f := 0.0
	for line in t.split("\n"):
		var l := line.strip_edges()
		if l.begins_with("P: \"UnitScaleFactor\""):
			f = float(l.get_slice(",", l.get_slice_count(",") - 1))
	var i := t.find("Model::cube")
	var tr := Vector3.ZERO
	if i >= 0:
		var k := t.find("\"Lcl Translation\"", i)
		var seg := t.substr(k, t.find("\n", k) - k).split(",")
		tr = Vector3(float(seg[seg.size() - 3]), float(seg[seg.size() - 2]), float(seg[seg.size() - 1]))
	return {"factor": f, "t": tr}


## a real click on the button through the dialog's own window (events reach a sub-window there), then the popup's row
func win_click(w: Window, p: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	w.push_input(mv, true)
	await process_frame
	for d in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = d
		e.position = p
		e.global_position = p
		if d:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		w.push_input(e, true)
		await process_frame
	await idle(2)


## press on the button, drag to the popup's row, release there (how a Godot drop-down is used with one gesture)
func pick(opt: OptionButton, idx: int) -> void:
	# C30 navigation edit: the choice now sits in the dialog's options scroll; bring it into view first, as a user would
	var sc := opt.get_window().find_child("export_opts_scroll", true, false) as ScrollContainer
	if sc != null:
		sc.ensure_control_visible(opt)
		await idle(3)
	var dlg: Window = opt.get_window()
	var off := Vector2(dlg.position) if dlg != root else Vector2.ZERO
	var pb := off + opt.get_global_rect().get_center()
	var mv := InputEventMouseMotion.new()
	mv.position = pb
	mv.global_position = pb
	root.push_input(mv, true)
	await process_frame
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = pb
	e.global_position = pb
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await idle(3)
	var pop := opt.get_popup()
	var pi := Vector2(pop.position) + Vector2(pop.size.x / 2.0, (idx + 0.5) * float(pop.size.y) / float(pop.item_count))
	var m2 := InputEventMouseMotion.new()
	m2.position = pi
	m2.global_position = pi
	m2.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(m2, true)
	await idle(2)
	var r := InputEventMouseButton.new()
	r.button_index = MOUSE_BUTTON_LEFT
	r.pressed = false
	r.position = pi
	r.global_position = pi
	root.push_input(r, true)
	await idle(3)


func _init() -> void:
	_watchdog()
	DirAccess.make_dir_recursive_absolute(SHOT)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	await idle(4)
	m._load_scene("res://scenes/combo3.json")
	await idle(3)
	m._export_dialog_open()
	await idle(6)
	var ui: ExportDialog = m.export_ui
	var opt := ui.dlg.find_child("opt_fbx_for", true, false) as OptionButton
	ok(opt != null and opt.item_count == 4 and opt.selected == 0 and opt.get_item_text(1).begins_with("Unity"), "A the choice exists with 4 entries, Default selected")
	# C30/C25/C27 moved UI: options scroll in export_opts_scroll; reach the choice first (reachable = scrollable into the window)
	var sc0 := ui.dlg.find_child("export_opts_scroll", true, false) as ScrollContainer
	if sc0 != null and opt != null:
		sc0.ensure_control_visible(opt)
		await idle(3)
	var win := Rect2(Vector2.ZERO, Vector2(1280, 720))
	ok(opt != null and win.encloses(opt.get_global_rect()), "A the choice sits inside the 1280 x 720 window (rect %s)" % str(opt.get_global_rect() if opt != null else Rect2()))
	root.get_texture().get_image().save_png(SHOT + "/dialog_1280x720.png")

	var B: Body = m.B
	var S: Scene = m.S
	var d_path: String = m._export_fbx(DIR)
	var db := FileAccess.get_file_as_bytes(d_path)
	var ref_path := DIR + "/ref_default.fbx"
	FbxExport.write(S, B, ref_path, false, Transform3D.IDENTITY, "", false, ExportNames.cam_keys(S))
	var rb := FileAccess.get_file_as_bytes(ref_path)
	ok(d_path != "" and db.size() > 100 and db == rb, "B default choice: the file is byte-identical to FbxExport.write's (%d vs %d bytes)" % [db.size(), rb.size()])
	var fd := bin_doubles(db, "UnitScaleFactor", 1)
	var td := bin_doubles(db, "Lcl Translation", 3, true)
	ok(fd == [1.0] and td.size() == 3, "B default UnitScaleFactor reads %s, a bone translation %s" % [str(fd), str(td)])

	await pick(opt, 1)
	ok(ExportNames.fbx_for == "unity", "C a real click + keys on the button picks Unity (fbx_for = %s)" % ExportNames.fbx_for)
	root.get_texture().get_image().save_png(SHOT + "/unity_1280x720.png")
	var u_path: String = m._export_fbx(DIR)
	var ub := FileAccess.get_file_as_bytes(u_path)
	var fu := bin_doubles(ub, "UnitScaleFactor", 1)
	var tu := bin_doubles(ub, "Lcl Translation", 3, true)
	if fu.size() == 1 and tu.size() == 3 and td.size() == 3:
		var mu := Vector3(tu[0], tu[1], tu[2]) * float(fu[0]) / 100.0
		var md := Vector3(td[0], td[1], td[2]) / 100.0
		ok(absf(float(fu[0]) - 100.0) < 1e-6 and (mu - md).length() < 1e-4 and md.length() > 1e-4, "C Unity file: factor %s; bone translation %s m vs default %s m" % [str(fu), str(mu), str(md)])
		var wrong := Vector3(tu[0], tu[1], tu[2]) / 100.0
		ok(not ((wrong - md).length() < 1e-4), "C CONTROL: Unity's numbers under the default factor give %s m, so the bar fails on them" % str(wrong))
	else:
		ok(false, "C could not read the Unity file's factor / translation (%s, %s)" % [str(fu), str(tu)])

	var xf := Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))
	for pr in ["default", "unity", "unreal", "blender"]:
		ExportNames.fbx_for = pr
		var r := ExportNames.fbx_write(S, B, "%s/d_%s.fbx" % [DIR, pr], false, xf, "cube", true)
		var fa := fbx_facts(r["text"])
		var metres := (fa["t"] as Vector3).length() * float(fa["factor"]) / 100.0
		ok(r["err"] == OK and absf(metres - 1.0) < 1e-4, "D %s: a 1 m offset reads %.5f m" % [pr, metres])
	ExportNames.fbx_for = "unity"
	await pick(opt, 2)
	ok(ExportNames.fbx_for == "unreal", "D a click picks Unreal")
	var z_path: String = m._export_fbx(DIR)
	var zu := bin_int(FileAccess.get_file_as_bytes(z_path), "UpAxis")
	ok(zu == 2, "D the Unreal file's UpAxis reads %s (2 = Z up)" % str(zu))
	await pick(opt, 0)
	ok(ExportNames.fbx_for == "default", "A choosing Default again restores it")
	ExportNames.fbx_for = "default"
	print("C28 DONE fails=", fails)
	quit(1 if fails > 0 else 0)
