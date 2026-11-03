extends SceneTree
## godot --path . --position 4000,4000 -s tests/c17_test.gd   (C17 mesh print safety: scripts/build/print_safety.gd)
## BARS (written before the first run; every one has a control that fails on origin, where PrintSafety does not exist):
##   1 INTERNAL  a 20 mm cube with a 5 mm solid cube inside: analyse_body finds 1 internal pair, shells == 2, lines() has a WARN naming INSIDE.
##               controls: two cubes side by side -> 0 internal; an inward-wound inner cube -> internal 1 but cavity (no WARN, a line says "kept").
##   2 REPAIR    the nested pair: changes has exactly 1 REMOVE line naming 125.0 mm3; repaired copy has 12 triangles, the original 24 stays 24; undo() gives 24.
##               controls: the cavity case removes nothing (count 0, 24 triangles kept, a KEPT line); a clean cube says "Nothing to repair".
##   3 RELOAD    nested pair written as STL and 3MF, read back FROM DISK: shells 2, tris 24, internal 1, closed true (both files).
##               controls: a clean cube reads shells 1 internal 0; a cube missing 2 triangles reads closed false with open > 0; a truncated STL reads ok false.
##               The repaired copy written to disk reads shells 1, internal 0, tris 12.
##   4 UI        1280 x 720, real click on the dialog's "Print safety check" button (3D printing target, a real 20 x 10 x 5 box): the label says "no closed shell sits inside another";
##               the row is hidden on another target; the "Repair list" button, clicked, writes a _repaired file; "Undo repair" removes it. Screenshot looked at by hand.
##   5 OLD ROAD  MeshExport.check_lines of the box is as before this change (no safety line added): first line begins "OK    closed".
const DIR := "user://zz_c17"
const SHOTS := "C:/Users/Nick/tools/kine_workers/out/c17"
var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	for d in [false, true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = d
		e.position = p
		e.global_position = p
		if d:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e, true)
		await process_frame
	await idle(3)


## a cube [lo, hi] appended to (v, t); outward winding unless inward
func cube(v: PackedVector3Array, t: PackedInt32Array, lo: float, hi: float, inward := false, shift := 0.0) -> void:
	var o := v.size()
	for i in 8:
		v.append(Vector3(hi if i & 1 else lo, hi if i & 2 else lo, hi if i & 4 else lo) + Vector3(shift, 0, 0))
	var f := [[0, 2, 3, 0, 3, 1], [4, 5, 7, 4, 7, 6], [0, 1, 5, 0, 5, 4], [2, 6, 7, 2, 7, 3], [0, 4, 6, 0, 6, 2], [1, 3, 7, 1, 7, 5]]
	for q in f:
		for k in 2:
			var a: int = q[k * 3]
			var b: int = q[k * 3 + 1]
			var c: int = q[k * 3 + 2]
			t.append_array(PackedInt32Array([o + a, o + c, o + b] if inward else [o + a, o + b, o + c]))


func body(kind: String, flip := false) -> Dictionary:
	var v := PackedVector3Array()
	var t := PackedInt32Array()
	cube(v, t, 0.0, 20.0, flip)
	match kind:
		"nested":
			cube(v, t, 7.5, 12.5, flip)
		"cavity":
			cube(v, t, 7.5, 12.5, not flip)
		"apart":
			cube(v, t, 0.0, 5.0, flip, 30.0)
	return {"name": "Test", "v": v, "t": t, "color": null}


func _init() -> void:
	var PS = load("res://scripts/build/print_safety.gd")
	if PS == null:
		print("FAIL no PrintSafety")
		quit(1)
		return
	var cu := body("clean")
	# the fixture winding: if the cube comes out negative, flip every fixture
	var flip := MeshExport.signed_volume(cu) < 0.0
	cu = body("clean", flip)
	ok(bool(MeshExport.check(cu)["closed"]) and absf(MeshExport.signed_volume(cu) - 8000.0) < 0.01, "0 fixture: clean cube closed, 8000 mm3")
	var nest := body("nested", flip)
	var a = PS.analyse_body(nest)
	var ln: Array = PS.lines([nest])
	ok(int(a["shells"]) == 2 and (a["internal"] as Array).size() == 1 and not bool(a["internal"][0]["cavity"]) and "\n".join(ln).contains("INSIDE") and String(ln[0]).begins_with("WARN"),
		"1 nested cube: shells %d internal %d, lines [%s]" % [int(a["shells"]), (a["internal"] as Array).size(), String(ln[0]).left(60)])
	var ap = PS.analyse_body(body("apart", flip))
	ok(int(ap["shells"]) == 2 and (ap["internal"] as Array).is_empty() and String(PS.lines([body("apart", flip)])[0]).begins_with("OK"), "1c side by side: 2 shells, 0 internal")
	var cv = PS.analyse_body(body("cavity", flip))
	var cvl: Array = PS.lines([body("cavity", flip)])
	ok((cv["internal"] as Array).size() == 1 and bool(cv["internal"][0]["cavity"]) and not "\n".join(cvl).contains("WARN") and "\n".join(cvl).contains("kept"), "1c inward inner cube is a cavity, kept")
	var rp = PS.repair([nest])
	var chg: Array = rp["changes"]
	var rem := chg.filter(func(s): return String(s).begins_with("REMOVE"))
	ok(rem.size() == 1 and String(rem[0]).contains("125.0 mm3") and int(rp["count"]) == 1 and (rp["bodies"][0]["t"] as PackedInt32Array).size() / 3 == 12 and (nest["t"] as PackedInt32Array).size() / 3 == 24 and (PS.undo(rp)[0]["t"] as PackedInt32Array).size() / 3 == 24,
		"2 repair lists %d REMOVE (%s), copy 12 tris, original 24, undo 24" % [rem.size(), String(rem[0]) if rem.size() > 0 else "-"])
	var rc = PS.repair([body("cavity", flip)])
	ok(int(rc["count"]) == 0 and (rc["bodies"][0]["t"] as PackedInt32Array).size() / 3 == 24 and "\n".join(rc["changes"]).contains("KEPT"), "2c cavity repair removes nothing")
	var rn = PS.repair([cu])
	ok(int(rn["count"]) == 0 and String(rn["changes"][0]).begins_with("Nothing to repair"), "2c clean cube: nothing to repair")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var g := ProjectSettings.globalize_path(DIR)
	MeshExport.write_stl(g + "/n.stl", [nest])
	MeshExport.write_3mf(g + "/n.3mf", [nest], "n")
	for ext in ["stl", "3mf"]:
		var r = PS.reload_check(g + "/n." + ext)
		ok(bool(r["ok"]) and int(r["shells"]) == 2 and int(r["tris"]) == 24 and int(r["internal"]) == 1 and bool(r["closed"]), "3 reload %s: shells %d tris %d internal %d closed %s" % [ext, int(r["shells"]), int(r["tris"]), int(r["internal"]), str(r["closed"])])
	MeshExport.write_stl(g + "/c.stl", [cu])
	var rcl = PS.reload_check(g + "/c.stl")
	ok(int(rcl["shells"]) == 1 and int(rcl["internal"]) == 0 and bool(rcl["closed"]), "3c clean cube reads 1 shell, 0 internal")
	var hole := cu.duplicate()
	hole["t"] = (cu["t"] as PackedInt32Array).slice(0, 30)
	MeshExport.write_stl(g + "/h.stl", [hole])
	var rh = PS.reload_check(g + "/h.stl")
	ok(not bool(rh["closed"]) and int(rh["open"]) > 0, "3c cube missing 2 triangles reads open %d" % int(rh["open"]))
	var bytes := FileAccess.get_file_as_bytes(g + "/c.stl")
	var f := FileAccess.open(g + "/t.stl", FileAccess.WRITE)
	f.store_buffer(bytes.slice(0, 200))
	f.close()
	ok(not bool(PS.reload_check(g + "/t.stl")["ok"]), "3c truncated STL reads ok false")
	var rr = PS.repair([nest])
	MeshExport.write_stl(g + "/r.stl", rr["bodies"])
	var rrl = PS.reload_check(g + "/r.stl")
	ok(int(rrl["shells"]) == 1 and int(rrl["internal"]) == 0 and int(rrl["tris"]) == 12, "3 repaired copy reads shells %d internal %d tris %d" % [int(rrl["shells"]), int(rrl["internal"]), int(rrl["tris"])])
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	if not Part.available():
		print("FAIL no KineCAD DLL")
		quit(1)
		return
	var rec := Part.make("C17 box")
	var fs: Array = rec["features"]
	var sid := PartTemplates._sk(fs, "top", [PartTemplates._rect(Vector2(0, 0), Vector2(20, 10))])
	PartTemplates._ex(fs, sid, "extrude", 5.0, "new")
	rec["seq"] = fs.size()
	rec["kept"] = true
	m.S.part = rec
	m.bld.part.set_on(true)
	await idle(6)
	var l5: Array = MeshExport.check_lines(rec)
	ok(String(l5[0]).begins_with("OK    closed") and not "\n".join(l5).contains("INSIDE") and not "\n".join(l5).contains("shell"), "5 old check lines unchanged: [%s]" % String(l5[0]).left(40))
	var ui: ExportDialog = ExportDialog.new(m)
	m.export_ui = ui
	ui.open()
	await idle(4)
	var sb := ui.dlg.find_child("export_safety_box", true, false) as Control
	ok(sb != null and sb.is_visible_in_tree(), "4 the safety row shows on the 3D printing target")
	var say := ui.dlg.find_child("export_safety_text", true, false) as Label
	(ui.dlg.find_child("btn_safety_check", true, false) as Button).pressed.emit()
	await idle(4)   # the dialog is an embedded window: root.push_input does not reach it, so its buttons are pressed this way (as the other export tests do)
	ok(say.text.contains("no closed shell sits inside another"), "4 real click on Print safety check says [%s]" % say.text.left(60))
	DirAccess.make_dir_recursive_absolute(SHOTS)
	root.get_texture().get_image().save_png(SHOTS + "/c17_check.png")
	var rp_path := ProjectSettings.globalize_path("res://exports") + "/C17_box_repaired.3mf"
	if FileAccess.file_exists(rp_path):
		DirAccess.remove_absolute(rp_path)
	(ui.dlg.find_child("btn_safety_repair", true, false) as Button).pressed.emit()
	await idle(4)   # the dialog is an embedded window: root.push_input does not reach it, so its buttons are pressed this way (as the other export tests do)
	ok(FileAccess.file_exists(rp_path) and say.text.contains("Nothing to repair") and say.text.contains("read back"), "4 Repair list click wrote %s; text [%s]" % [rp_path.get_file(), say.text.left(50)])
	root.get_texture().get_image().save_png(SHOTS + "/c17_repair.png")
	(ui.dlg.find_child("btn_safety_undo", true, false) as Button).pressed.emit()
	await idle(4)   # the dialog is an embedded window: root.push_input does not reach it, so its buttons are pressed this way (as the other export tests do)
	ok(not FileAccess.file_exists(rp_path) and say.text.contains("never changed"), "4 Undo repair removed the copy")
	ui.ui_target.select(0)
	ui._on_target(0)
	await idle(2)
	ok(not sb.visible, "4 the safety row is hidden on another target")
	ui.dlg.hide()
	print("c17: %d fail" % fails)
	quit(1 if fails > 0 else 0)
