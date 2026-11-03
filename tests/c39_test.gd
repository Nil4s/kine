extends SceneTree
## godot --path . --position 4000,4000 -s tests/c39_test.gd     (C39: FBX materials; Blender headless reads the file back)
## BARS, written before any number was read:
##  A  CHECKBOX  the Export dialog has CheckBox "chk_fbx_materials", off by default, inside the 1280 x 720 window; a REAL click turns ExportNames.fbx_materials on.
##  B  DEFAULT   with it off, m._export_fbx writes bytes equal to FbxExport.write's of the same scene (byte-identical, no Material in the file).
##  C  BLENDER   with it on, the binary .fbx read back by Blender 4.5 headless has exactly 4 materials: Body = the body colour (blue, 0.25 0.42 0.78),
##               Prop_box_0 = Props red (0.84 0.14 0.12), Prop_crate_1 = Props blue (0.15 0.36 0.88), Prop_box_2 (a photo material) with an image
##               texture whose path ends in albedo.png; each colour within 0.02 per channel.
##  D  CONTROL   Blender reading the default (materials off) file finds 0 materials, so the count bar and the colour bars fail on it; and Body's
##               colour compared with the red prop's fails the Body bar (the bar can fail).
##  E  WITH UNITY the Unity-target file with materials on also reads back 4 materials (the two options compose).
const SHOT := "C:/Users/Nick/tools/kine_workers/out/c39"
const DIR := "user://zz_c39"
const BLENDER := "C:/Program Files/Blender Foundation/Blender 4.5/blender.exe"
const CHK := "C:/Users/Nick/tools/kine_workers/q4/c39_matchk.py"
var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func _watchdog() -> void:
	await create_timer(500.0).timeout
	print("FAIL watchdog: the test did not finish in 500 s")
	quit(1)


func click(c: Control) -> void:
	var dlg: Window = c.get_window()
	var off := Vector2(dlg.position) if dlg != root else Vector2.ZERO
	var p := off + c.get_global_rect().get_center()
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


## Blender headless on a file -> the materials it found ([] when it did not finish in 120 s)
func blender_mats(fbx: String, tag: String) -> Array:
	var out := ProjectSettings.globalize_path(DIR + "/mats_%s.json" % tag)
	if FileAccess.file_exists(out):
		DirAccess.remove_absolute(out)
	var pid := OS.create_process(BLENDER, ["-b", "--factory-startup", "--python", CHK, "--", ProjectSettings.globalize_path(fbx), out])
	var t0 := Time.get_ticks_msec()
	while not FileAccess.file_exists(out) and Time.get_ticks_msec() - t0 < 120000:
		await create_timer(0.5).timeout
	if not FileAccess.file_exists(out):
		OS.kill(pid)
		return []
	await create_timer(0.5).timeout
	var r = JSON.parse_string(FileAccess.get_file_as_string(out))
	return r if r is Array else []


func _has(b: PackedByteArray, w: String) -> bool:
	var pat := w.to_ascii_buffer()
	for k in range(0, b.size() - pat.size()):
		if b[k] == pat[0] and b.slice(k, k + pat.size()) == pat:
			return true
	return false


func find_mat(ms: Array, nm: String) -> Dictionary:
	for x in ms:
		if String(x["name"]).begins_with(nm):
			return x
	return {}


func near(c, want: Color, tol := 0.02) -> bool:
	return c is Array and c.size() == 3 and absf(float(c[0]) - want.r) <= tol and absf(float(c[1]) - want.g) <= tol and absf(float(c[2]) - want.b) <= tol


func _init() -> void:
	_watchdog()
	DirAccess.make_dir_recursive_absolute(SHOT)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://materials/c39tex"))
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	img.fill(Color(0.5, 0.3, 0.1))
	img.save_png(ProjectSettings.globalize_path("user://materials/c39tex/albedo.png"))
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
	var S: Scene = m.S
	var B: Body = m.B
	m.body_colour = 3   # blue
	var p0 := Props.make("box", Transform3D(Basis.IDENTITY, Vector3(2, 0, 0)))
	p0["colour"] = "red"
	var p1 := Props.make("crate", Transform3D(Basis.IDENTITY, Vector3(-2, 0, 0)))
	p1["colour"] = "blue"
	var p2 := Props.make("box", Transform3D(Basis.IDENTITY, Vector3(0, 0, 2)))
	p2["mat"] = "c39tex"
	S.props = [p0, p1, p2]
	ExportNames.fbx_materials = false
	ExportNames.fbx_for = "default"
	m._export_dialog_open()
	await idle(6)
	var ui: ExportDialog = m.export_ui
	var chk := ui.dlg.find_child("chk_fbx_materials", true, false) as CheckBox
	var sc0 := ui.dlg.find_child("export_opts_scroll", true, false) as ScrollContainer
	if sc0 != null and chk != null:
		sc0.ensure_control_visible(chk)
		await idle(3)
	var win := Rect2(Vector2.ZERO, Vector2(1280, 720))
	ok(chk != null and not chk.button_pressed and not ExportNames.fbx_materials and win.encloses(chk.get_global_rect()), "A checkbox exists, off, inside the window (rect %s)" % str(chk.get_global_rect() if chk != null else Rect2()))
	root.get_texture().get_image().save_png(SHOT + "/dialog_off_1280x720.png")

	var d_path: String = m._export_fbx(DIR)
	var db := FileAccess.get_file_as_bytes(d_path)
	var ref_path := DIR + "/ref_default.fbx"
	FbxExport.write(S, B, ref_path, false, Transform3D.IDENTITY, "", false, ExportNames.cam_keys(S))
	var rb := FileAccess.get_file_as_bytes(ref_path)
	ok(db.size() > 100 and db == rb and _has(db, "Material") == false, "B default (off): byte-identical to FbxExport.write's, no Material (%d vs %d bytes)" % [db.size(), rb.size()])

	await click(chk)
	ok(chk.button_pressed and ExportNames.fbx_materials, "A a real click turns the switch on")
	root.get_texture().get_image().save_png(SHOT + "/dialog_on_1280x720.png")
	var on_path: String = m._export_fbx(DIR)
	var ob := FileAccess.get_file_as_bytes(on_path)
	ok(ob.size() > db.size() and _has(ob, "Material"), "C the file with materials is bigger (%d > %d bytes) and names Material" % [ob.size(), db.size()])
	var keep_on := DIR + "/with_materials.fbx"
	DirAccess.copy_absolute(ProjectSettings.globalize_path(on_path), ProjectSettings.globalize_path(keep_on))
	var mats: Array = await blender_mats(keep_on, "on")
	ok(mats.size() == 4, "C Blender found %d materials (want 4)" % mats.size())
	var bd := find_mat(mats, "Body")
	var bx := find_mat(mats, "Prop_box_0")
	var cr := find_mat(mats, "Prop_crate_1")
	var tx := find_mat(mats, "Prop_box_2")
	var body_c: Color = m.BODY_COLOURS[3][1]
	ok(near(bd.get("base"), body_c), "C Body base colour %s ~ %s" % [str(bd.get("base")), str(body_c)])
	ok(near(bx.get("base"), Props.COLOURS["red"]), "C Prop_box_0 base colour %s ~ red %s" % [str(bx.get("base")), str(Props.COLOURS["red"])])
	ok(near(cr.get("base"), Props.COLOURS["blue"]), "C Prop_crate_1 base colour %s ~ blue %s" % [str(cr.get("base")), str(Props.COLOURS["blue"])])
	ok(String(tx.get("tex", "")).ends_with("albedo.png"), "C Prop_box_2 texture path %s ends in albedo.png" % str(tx.get("tex")))

	var off_mats: Array = await blender_mats(ref_path, "off")
	ok(off_mats.size() != 4 and not near(find_mat(off_mats, "Body").get("base"), body_c), "D CONTROL the default file reads %d materials in Blender, so the count and colour bars fail on it" % off_mats.size())
	ok(not near(bd.get("base"), Props.COLOURS["red"]), "D CONTROL the Body colour is not the red prop's, so the colour bar can fail")

	ExportNames.fbx_for = "unity"
	var u_path: String = m._export_fbx(DIR)
	var um: Array = await blender_mats(u_path, "unity")
	ok(um.size() == 4 and near(find_mat(um, "Prop_box_0").get("base"), Props.COLOURS["red"]), "E Unity target + materials: %d materials, red prop %s" % [um.size(), str(find_mat(um, "Prop_box_0").get("base"))])
	ExportNames.fbx_for = "default"
	ExportNames.fbx_materials = false
	print("C39 DONE fails=", fails)
	quit(1 if fails > 0 else 0)
