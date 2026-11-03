extends SceneTree
## godot --path . -s tests/c48ui_test.gd     (C48 fix round 1: real clicks at 1280x720 on a part with ONE hinge and NO cards)
## Bars, written before any number was read:
##  1 CHECK   with the Joints target picked, the checklist has no "no animation" / "2 cards" line and says OK for the 1 hinge (CONTROL: the Unreal target, same scene, still shows the cards line)
##  2 GLB     a real click on Export (format glTF) writes <name>_joints.glb in res://exports, size > 0 (the files are deleted first)
##  3 URDF    the same click with the URDF format writes <name>.urdf, size > 0
##  4 SAVE    in the hinge dialog of hinge 1: type a name, click Save frame; the part's frames hold it with hinge 1's pivot and axis
##  5 USE     open hinge 2 (other pivot and axis), pick the frame from "Use a saved frame", click OK: hinge 2's o and axis equal hinge 1's within 1e-6,
##            its angles and limit unchanged (CONTROL: before the pick they differed by > 1 mm)
const OUT := "C:/Temp/claude/c48ui"
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	root.push_input(mv, true)
	await process_frame
	await ev(p, true)
	await ev(p, false)
	await idle(3)


func shot(name: String) -> void:
	await idle(4)
	root.get_texture().get_image().save_png(OUT + "/" + name + ".png")


func size_of(p: String) -> int:
	if not FileAccess.file_exists(p):
		return -1
	return FileAccess.open(p, FileAccess.READ).get_length()


func _init() -> void:
	var wd := Timer.new()
	root.add_child(wd)
	wd.one_shot = true
	wd.timeout.connect(func():
		print("FAIL watchdog: past 200 s")
		quit(2))
	wd.start(200.0)
	run.call_deferred()


func pick_target(ed: ExportDialog, prefix: String) -> void:
	for i in ed.ui_target.item_count:
		if ed.ui_target.get_item_text(i).begins_with(prefix):
			ed.ui_target.select(i)
			ed._on_target(i)
	await idle(3)


func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	if not Part.available():
		print("c48ui: no CAD library")
		quit(1)
		return
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	await idle(4)
	var pu: PartUI = m.bld.part
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://c48ui"))
	ss.dirs_override = ["user://c48ui"]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu.set_on(false)
	m.S.part = Part.make("C48 UI Door")
	m.S.part["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [0, -20], "b": [800, 20]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 2000.0, "both": false, "op": "new"},
		{"t": "hinge", "id": "f3", "name": "Hinge1", "body": 0, "o": [800, 0, 0], "axis": [0, 0, 1], "track": [[0.0, 0.0], [3.0, 90.0]], "clear": []},
		{"t": "hinge", "id": "f4", "name": "Hinge2", "body": 0, "o": [0, 0, 1000], "axis": [1, 0, 0], "track": [[0.0, 0.0], [2.0, 45.0]], "clear": [], "limit": 30.0},
	]
	m.S.part["seq"] = 4
	pu.set_on(true)
	await idle(3)
	m.bld.sync()
	await idle(3)
	pu._view_model()
	await idle(3)
	# 4 SAVE / 5 USE first (the part dialog), real clicks on the frame row
	var hinge1: Dictionary = Part.feature(m.S.part, "f3")
	pu.open_dialog("hinge", 2)
	await idle(4)
	var le: LineEdit = pu.dlg_rows.find_child("part_frame_name", true, false)
	var sb: Button = pu.dlg_rows.find_child("part_frame_save", true, false)
	le.text = "door edge"
	await click_ctl(sb)
	var fr := C48Joints.get_frame(m.S.part, "door edge")
	ok(not fr.is_empty() and (fr["o"] as Vector3).distance_to(Vector3(800, 0, 0)) < 1e-6 and (fr["axis"] as Vector3).distance_to(Vector3(0, 0, 1)) < 1e-6, "4 SAVE frame door edge saved by a click: %s" % str(fr))
	pu.open_dialog("hinge", 3)
	await idle(4)
	var h2: Dictionary = Part.feature(m.S.part, "f4")
	var before := Vector3(h2["o"][0], h2["o"][1], h2["o"][2]).distance_to(Vector3(800, 0, 0))
	var ob: OptionButton = pu.dlg_rows.find_child("part_frame_use", true, false)
	ok(ob != null and before > 1.0, "5a USE the list is there for hinge 2; its pivot is %.1f mm from hinge 1 before the pick" % before)
	if ob != null:
		ob.select(1)
		ob.item_selected.emit(1)   # the popup's own pick
		await idle(3)
		await shot("hinge_frame_use")
		var okb: Button = pu.find_child("part_ok", true, false)
		await click_ctl(okb)
	h2 = Part.feature(m.S.part, "f4")
	var po := Vector3(h2["o"][0], h2["o"][1], h2["o"][2])
	var ax := Vector3(h2["axis"][0], h2["axis"][1], h2["axis"][2])
	ok(po.distance_to(Vector3(800, 0, 0)) < 1e-6 and ax.distance_to(Vector3(0, 0, 1)) < 1e-6 and absf(float(h2["limit"]) - 30.0) < 1e-6 and absf(float(h2["track"][1][1]) - 45.0) < 1e-6,
		"5b USE after OK, hinge 2 pivot %s axis %s equal hinge 1's; limit %s, end angle %s kept" % [str(po), str(ax), str(h2["limit"]), str(h2["track"][1][1])])
	# 1-3 the export dialog, a fresh part with one hinge and no cards
	(m.S.part["features"] as Array).pop_back()
	m.S.part["seq"] = 3
	pu.dlg = {}
	m._export_dialog_open()
	await idle(4)
	var ed: ExportDialog = m.export_ui
	await pick_target(ed, String(ExportDialog.targets()[0]["label"]).left(6))
	var ue := "\n".join(ed.text_of(String(ExportDialog.targets()[0]["id"]), 0)["checks"])
	await pick_target(ed, "Joints")
	var jt := "\n".join(ed.text_of("joints", 0)["checks"])
	ok(m.S.cards.size() < 2 and not jt.contains("no animation") and not jt.contains("2 cards") and jt.contains("OK") and jt.contains("1 hinge") and ue.contains("2 cards"),
		"1 CHECK joints checklist: [%s]; control (Unreal) still says 2 cards: %s" % [jt, str(ue.contains("2 cards"))])
	var base := "res://exports/" + C48Joints.stem(m.S.part)
	var gdir := ProjectSettings.globalize_path("res://exports")
	DirAccess.make_dir_recursive_absolute(gdir)
	var glb := gdir + "/" + C48Joints.stem(m.S.part) + "_joints.glb"
	var urdf := gdir + "/" + C48Joints.stem(m.S.part) + ".urdf"
	DirAccess.remove_absolute(glb)
	DirAccess.remove_absolute(urdf)
	await shot("export_joints_checklist")
	ed.ui_format.select(0)
	await click_ctl(ed.dlg.get_ok_button())
	await idle(4)
	ok(size_of(glb) > 0, "2 GLB the Export click wrote %s: %d bytes" % [glb.get_file(), size_of(glb)])
	m._export_dialog_open()
	await idle(4)
	await pick_target(ed, "Joints")
	ed.ui_format.select(1)
	ed._on_format(1)
	await idle(2)
	await click_ctl(ed.dlg.get_ok_button())
	await idle(4)
	ok(size_of(urdf) > 0, "3 URDF the Export click wrote %s: %d bytes" % [urdf.get_file(), size_of(urdf)])
	print("c48ui: %d fail" % fails)
	quit(1 if fails > 0 else 0)
