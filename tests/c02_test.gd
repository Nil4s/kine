## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/c02_test.gd     (C02, complaints 491 487 500; a window)
## BARS (written before the first run), poses live in user://zz_c02_<pid>/ only:
##   B1 update   "Update from current pose": the pose file's angles = the body now within 0.01 deg, hips within 1e-3 m; the picture's bytes
##               change (remade); exactly ONE undo step; Ctrl+Z gives back the old file byte for byte; redo writes the new one.
##               CONTROL: before the update the file is NOT the body (>1 deg), so a no-op update fails B1.
##   B2 delete   Select several, click 3 of 5 pictures (real cell input), Delete ticked: those 3 .json AND .png gone, the other 2
##               untouched (md5), undo stack +1 exactly; ONE Ctrl+Z brings all 3 back with identical md5; redo removes them again.
##               CONTROL: Delete with nothing ticked deletes nothing and pushes no step; a bundled res://poses pose is refused (md5 same).
##   B3 rename   Rename: the new .json and .png exist, the old ones are gone, the pose keeps the same angles (0.01 deg);
##               a name already in use is refused and BOTH files keep their md5.  CONTROL: a bundled pose cannot be renamed.
##   B4 off      with Select several OFF a click still applies (default unchanged), no tick is made.
## Env C02_SHOT=<png> saves a 1280x720 screenshot of the panel with ticks and the menu.
extends SceneTree

var fails := 0
var m: Node
var lib: PoseLibrary
var dir := ""


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func qang(a: Quaternion, b: Quaternion) -> float:
	var d := a.inverse() * b
	return rad_to_deg(2.0 * asin(minf(1.0, Vector3(d.x, d.y, d.z).length())))


func pose_dict(angs: Dictionary, o := Vector3.ZERO) -> Dictionary:
	var keep: Dictionary = m.B.state()
	for j in Body.ORDER:
		m.B.ang[j] = Vector3.ZERO
	for j in angs:
		m.B.ang[j] = m.B.clamp_ang(j, angs[j])
	m.B.offset = o
	m.B.fk()
	var d: Dictionary = m.B.to_dict()
	m.B.set_state(keep)
	return d


func write_pose(nm: String, d: Dictionary) -> String:
	var p := dir + "/" + nm + ".json"
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, " "))
	f.close()
	return p


## worst per-joint turn error (deg) of the pose file against the body angles now
func file_vs_body(path: String) -> float:
	var c := lib.clip_of(path)
	var w := 0.0
	for j in Body.ORDER:
		w = maxf(w, qang(m.B.compose(j, m.B.ang[j]), m.B.compose(j, c["ang"][j])))
	return w


func click(path: String) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = Vector2(20, 20)
	ev.pressed = true
	(lib.cells[path] as Control).gui_input.emit(ev)
	var up := ev.duplicate() as InputEventMouseButton
	up.pressed = false
	(lib.cells[path] as Control).gui_input.emit(up)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	dir = "user://zz_c02_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var names := ["alpha", "bravo", "charlie", "delta", "echo"]
	var paths := []
	for i in names.size():
		paths.append(write_pose(names[i], pose_dict({"upperarm_r": Vector3(20 + 15 * i, 5 * i, 0), "thigh_l": Vector3(10 * i, 0, 0), "head": Vector3(0, 0, 4 * i)}, Vector3(0.0, -0.02 * i, 0))))
	lib = PoseLibrary.new()
	lib.m = m
	lib.name = "pose_library"
	lib.dirs = [dir, "res://poses"]
	m.ui_root.add_child(lib)
	m.set_meta("pose_library", lib)
	lib.visible = true
	await lib.settle()
	ok(lib.cells.has(paths[0]) and lib.cells.has(paths[4]), "fixture: the grid shows the 5 test poses")
	var nick_before := FileAccess.get_md5("res://poses/stand.json")

	# ---- B4 default unchanged
	var u0: int = m.undo.size()
	click(paths[2])
	ok(lib.multi.is_empty() and m.undo.size() == u0 + 1, "B4 Select several off: a click applies (1 step, no tick)")
	m._undo()

	# ---- B1 update
	var pa: String = paths[1]
	var old_bytes := FileAccess.get_file_as_string(pa)
	var old_png := FileAccess.get_md5(PoseLibrary.thumb_path(pa))
	for j in ["upperarm_l", "calf_r", "spine_02"]:
		m.B.ang[j] = m.B.clamp_ang(j, Vector3(35, 10, 5))
	m.B.offset = Vector3(0.04, -0.1, 0.0)
	m.B.fk()
	ok(file_vs_body(pa) > 1.0, "B1 control: before the update the file is NOT the body (%.1f deg)" % file_vs_body(pa))
	var us: int = m.undo.size()
	var r0 := lib.renders
	ok(PoseLibraryEdit.update(lib, pa), "B1 update returned true")
	await lib.settle()
	var worst := file_vs_body(pa)
	ok(worst < 0.01, "B1 the file's angles = the body now (worst %.5f deg, bar 0.01)" % worst)
	var offs: Array = JSON.parse_string(FileAccess.get_file_as_string(pa)).get("offset", [0, 0, 0])
	ok(Vector3(offs[0], offs[1], offs[2]).distance_to(m.B.offset) < 1e-3, "B1 the hips' offset too")
	ok(m.undo.size() == us + 1, "B1 exactly one undo step (%d)" % (m.undo.size() - us))
	ok(lib.renders == r0 + 1 and FileAccess.get_md5(PoseLibrary.thumb_path(pa)) != old_png, "B1 the picture was remade and its bytes changed")
	var new_bytes := FileAccess.get_file_as_string(pa)
	m._undo()
	ok(FileAccess.get_file_as_string(pa) == old_bytes, "B1 Ctrl+Z: the old file back, byte for byte")
	m._redo()
	ok(FileAccess.get_file_as_string(pa) == new_bytes, "B1 redo: the updated file again")
	m._undo()
	await lib.settle()

	# ---- B2 multi delete
	var md := {}
	for p in paths:
		md[p] = FileAccess.get_md5(p)
		md[PoseLibrary.thumb_path(p)] = FileAccess.get_md5(PoseLibrary.thumb_path(p))
	lib.several_box.button_pressed = true
	var b1: Dictionary = m.B.state()
	var u1: int = m.undo.size()
	click(paths[0])
	click(paths[2])
	click(paths[3])
	ok(lib.multi.size() == 3 and m.undo.size() == u1 and m.B.state() == b1, "B2 three ticked by clicking, the body untouched, no step")
	PoseLibraryEdit.delete_many(lib, [])
	ok(m.undo.size() == u1 and lib.multi.size() == 3, "B2 control: Delete of nothing pushes no step")
	var bund := PoseLibraryEdit.delete_many(lib, ["res://poses/stand.json"])
	ok(bund == 0 and FileAccess.get_md5("res://poses/stand.json") == nick_before and m.undo.size() == u1, "B2 control: a bundled pose is refused, file intact")
	lib.del_btn.pressed.emit()
	await lib.settle()
	var gone := true
	for i in [0, 2, 3]:
		gone = gone and not FileAccess.file_exists(paths[i]) and not FileAccess.file_exists(PoseLibrary.thumb_path(paths[i]))
	ok(gone, "B2 the 3 ticked poses and their pictures are gone")
	ok(FileAccess.get_md5(paths[1]) == md[paths[1]] and FileAccess.get_md5(paths[4]) == md[paths[4]], "B2 the other two untouched")
	ok(m.undo.size() == u1 + 1 and not lib.cells.has(paths[0]), "B2 exactly one undo step; the grid dropped them")
	m._undo()
	await lib.settle()
	var back := true
	for i in [0, 2, 3]:
		back = back and FileAccess.get_md5(paths[i]) == md[paths[i]] and FileAccess.get_md5(PoseLibrary.thumb_path(paths[i])) == md[PoseLibrary.thumb_path(paths[i])]
	ok(back, "B2 ONE Ctrl+Z: all 3 back, json and picture md5 identical")
	ok(lib.cells.has(paths[0]) and lib.cells.has(paths[3]), "B2 the grid shows them again")
	m._redo()
	ok(not FileAccess.file_exists(paths[0]) and not FileAccess.file_exists(paths[3]), "B2 redo deletes them again")
	m._undo()
	await lib.settle()
	lib.several_box.button_pressed = false

	# ---- B3 rename
	var pr: String = paths[4]
	var want := lib.clip_of(pr)
	var bytes_r := FileAccess.get_file_as_string(pr)
	var np := PoseLibraryEdit.rename(lib, pr, "echo two")
	var dst: String = dir + "/echo_two.json"
	ok(np == dst and FileAccess.file_exists(dst) and FileAccess.file_exists(PoseLibrary.thumb_path(dst)), "B3 new .json and .png exist")
	ok(not FileAccess.file_exists(pr) and not FileAccess.file_exists(PoseLibrary.thumb_path(pr)), "B3 the old ones are gone")
	ok(FileAccess.get_file_as_string(dst) == bytes_r, "B3 the pose content is untouched")
	var got := lib.clip_of(dst)
	var wr := 0.0
	for j in Body.ORDER:
		wr = maxf(wr, qang(m.B.compose(j, got["ang"][j]), m.B.compose(j, want["ang"][j])))
	ok(wr < 0.01, "B3 still the same angles (%.5f deg)" % wr)
	var m_b := FileAccess.get_md5(paths[1])
	var m_e := FileAccess.get_md5(dst)
	ok(PoseLibraryEdit.rename(lib, dst, "bravo") == "" and FileAccess.get_md5(paths[1]) == m_b and FileAccess.get_md5(dst) == m_e, "B3 a name in use is refused, both files keep their md5")
	ok(PoseLibraryEdit.rename(lib, "res://poses/stand.json", "stand2") == "" and not FileAccess.file_exists("res://poses/stand2.json"), "B3 control: a bundled pose cannot be renamed")

	if OS.get_environment("C02_SHOT") != "":
		root.get_window().size = Vector2i(1280, 720)
		await process_frame
		await process_frame
		lib.several_box.button_pressed = true
		click(lib.cells.keys()[0])
		click(lib.cells.keys()[2])
		await process_frame
		lib._open_menu(Vector2(900, 300))
		await process_frame
		await process_frame
		root.get_viewport().get_texture().get_image().save_png(OS.get_environment("C02_SHOT"))
	print("c02: %d fail(s)" % fails)
	quit(1 if fails > 0 else 0)
