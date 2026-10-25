## godot --path . -s tests/set_test.gd     (GATES SS5, SS6; needs a window; real clicks and drags)
## THE SET IN THE APP: combo3 open. SET > Add prop > table: a table in front of the body on the floor, picked, one
## undo step, a "Set" row in the browser. A real drag on it moves it over the floor (one undo step; Ctrl+Z puts it
## back). A box added and dragged over the table lands ON it (75 cm up). Turn right: 15 deg. Delete: gone; Ctrl+Z:
## back. A click on the body (no prop in front) picks the body part and lets go of the prop. The scene's file holds
## "props" and reads them back; combo3 itself has none and writes no "props" key. Mirror the scene reflects the set.
## IMPORT: a .glb dropped on the window (the files_dropped handler) is checked, copied into the library, and put in
## the set; a broken file is refused in words and changes nothing.
extends SceneTree

var fails := 0
var m: Node
var dir := ""


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func button(e: InputEventMouseButton, p: Vector2, down: bool) -> void:
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)


func drag(a: Vector2, b: Vector2) -> void:
	button(InputEventMouseButton.new(), a, true)
	await idle(2)
	for k in range(1, 11):
		var mm := InputEventMouseMotion.new()
		mm.position = a.lerp(b, k / 10.0)
		mm.global_position = mm.position
		mm.relative = (b - a) / 10.0
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(mm)
		await process_frame
	button(InputEventMouseButton.new(), b, false)
	await idle(3)


func click(p: Vector2) -> void:
	await drag(p, p)


func click_ctl(c: Control) -> void:
	await click(c.get_global_rect().get_center())


func on_set(t: String) -> Control:
	for b in m.ui_ribbon["SET"].find_children("*", "BaseButton", true, false) + m.ui_ribbon["SET"].get_children():
		if b is BaseButton and m.label_of(b) == t:
			return b
	return null


func add(kind: String) -> void:
	var ap: MenuButton = on_set("Add prop")
	await click_ctl(ap)   # opens its menu (the menu is its own window: its item is chosen through its signal)
	var pm := ap.get_popup()
	var idx := -1
	for k in pm.item_count:
		if String(pm.get_item_metadata(k)) == kind:
			idx = k
	pm.hide()
	pm.id_pressed.emit(pm.get_item_id(idx))
	await idle(3)


func prop_pos(i: int) -> Vector3:   # a missing prop reads far away (a failed check, not a crash that hangs the run)
	return (m.S.props[i]["xf"] as Transform3D).origin if i < m.S.props.size() else Vector3(99, 99, 99)


func yaw(i: int) -> float:
	return float(Props.to_dict(m.S.props[i])["yaw"]) if i < m.S.props.size() else 999.0


func screen(p: Vector3) -> Vector2:
	return m.cam.unproject_position(p)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.S.name = "zz_set_test"
	m._view_dir(Vector3(0.6, 0.45, 1.0), false)
	m.dist = 5.0
	m._cam()
	await idle(4)
	ok(m.S.props.is_empty() and not m.S.to_dict(m.B).has("props"), "combo3 has no set and its file has no \"props\" key (an old scene writes as before)")
	m._ribbon("SET")
	await idle(2)
	ok(on_set("Add prop") != null and on_set("Import model") != null and on_set("Turn left") != null and on_set("Delete prop") != null and on_set("Delete prop").disabled,
		"SET: Add prop, Import model, Turn, Delete (greyed with nothing picked: '%s')" % on_set("Delete prop").tooltip_text.right(50))
	var u0: int = m.undo.size()
	await add("table")
	ok(m.S.props.size() == 1 and m.sel_prop == 0 and prop_pos(0).z > 0.8 and absf(prop_pos(0).y) < 1e-4 and m.undo.size() == u0 + 1 and m.ui_props_root.get_child_count() == 1,
		"Add prop > table: in front of the body %s, on the floor, picked, one undo step (%d)" % [prop_pos(0), m.undo.size() - u0])
	await idle(3)
	var rows := []
	var it: TreeItem = m.ui_browser.get_root().get_first_child()
	while it != null:
		if it.get_metadata(0) is Dictionary and it.get_metadata(0).has("prop"):
			rows.append(it.get_text(0))
		it = it.get_next_in_tree()
	ok(rows == ["table"], "the browser's Set lists it %s" % [rows])
	var dm := Vector2(m.T.xf.origin.x, m.T.xf.origin.z)
	ok(m.dummy_on and not m._foot(m.S.props[0]).grow(0.1).has_point(dm), "it is not put where the dummy stands (dummy at %s, table's footprint %s)" % [dm, m._foot(m.S.props[0])])
	# a real drag on the table top: half a metre to the body's left
	var p0 := prop_pos(0)
	var top := p0 + Vector3(0, 0.75, 0)
	var u1: int = m.undo.size()
	await drag(screen(top), screen(top + Vector3(0.6, 0, 0)))
	var p1 := prop_pos(0)
	ok(p1.x - p0.x > 0.4 and absf(p1.z - p0.z) < 0.05 and absf(p1.y) < 1e-4 and m.undo.size() == u1 + 1 and m.sel_prop == 0,
		"a real drag on its top: moved %.2f m sideways (z %.3f, y %.3f), one undo step" % [p1.x - p0.x, p1.z - p0.z, p1.y])
	m._undo()
	await idle(2)
	ok(prop_pos(0).distance_to(p0) < 1e-3, "  Ctrl+Z: back where it was (%.4f m off)" % prop_pos(0).distance_to(p0))
	var u2: int = m.undo.size()
	await click(screen(top))
	ok(m.undo.size() == u2 and m.sel_prop == 0, "  a click that only picks: no undo step")
	# a box onto the table
	await add("box")
	var b0 := prop_pos(1)
	var tp := prop_pos(0)
	await drag(screen(b0 + Vector3(0, 0.38, 0)), screen(Vector3(tp.x, b0.y + 0.38, tp.z)))
	var b1 := prop_pos(1)
	ok(absf(b1.y - 0.75) < 1e-3 and Vector2(b1.x - tp.x, b1.z - tp.z).length() < 0.3, "a box dragged over the table lands ON it: %.3f m up, %.2f m from its middle" % [b1.y, Vector2(b1.x - tp.x, b1.z - tp.z).length()])
	# turn, delete
	await click_ctl(on_set("Turn right"))
	ok(absf(yaw(1) - 15.0) < 0.01, "Turn right clicked: the box at %.1f deg" % yaw(1))
	await click_ctl(on_set("Delete prop"))
	ok(m.S.props.size() == 1 and m.sel_prop == -1 and on_set("Delete prop").disabled, "Delete prop clicked: the box gone, nothing picked, Delete greyed again")
	m._undo()
	await idle(2)
	ok(m.S.props.size() == 2 and String(m.S.props[-1]["kind"]) == "box", "  Ctrl+Z: the box back")
	# the body still picks where no prop is in front
	m.sel_prop = 1
	var head: Vector3 = (m.B.cap("head")[0] + m.B.cap("head")[1]) * 0.5
	await click(screen(head))
	ok(m.sel == "head" and m.sel_prop == -1, "a click on the head (no prop in front): the head picked, the prop let go (sel '%s', prop %d)" % [m.sel, m.sel_prop])
	# the file
	var d: Dictionary = m.S.to_dict(m.B)
	var S2 := Scene.new()
	S2.from_dict(JSON.parse_string(JSON.stringify(d)))
	ok(d.has("props") and d["props"].size() == 2 and S2.props.size() == 2 and Props.to_dict(S2.props[-1]) == Props.to_dict(m.S.props[-1]) and m._unsaved(),
		"the scene's file holds the set (%d props) and reads it back the same; unsaved work" % d.get("props", []).size())
	# mirror the scene: the set reflected (a file in scenes/_wip, removed below)
	var before: Array = m.S.props.map(func(p): return Props.to_dict(p))
	m._mirror_scene()
	await idle(3)
	var after: Array = m.S.props.map(func(p): return Props.to_dict(p))
	var refl: bool = after.size() == 2
	for k in after.size():
		refl = refl and is_equal_approx(float(after[k]["pos"][0]), -float(before[k]["pos"][0])) and is_equal_approx(float(after[k]["pos"][2]), float(before[k]["pos"][2])) and is_equal_approx(float(after[k]["yaw"]), -float(before[k]["yaw"]))
	ok(m.S.name.ends_with("_mirrored") and refl, "Mirror the scene: the set reflected (x and yaw negated) in '%s'" % m.S.name)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://scenes/_wip/zz_set_test_mirrored.json"))
	# IMPORT by a drop
	dir = "user://zz_set_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(dir)
	var box := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 0.5, 0.3)
	mi.mesh = bm
	box.add_child(mi)
	mi.owner = box
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_scene(box, st)
	var src := ProjectSettings.globalize_path(dir + "/barrel.glb")
	doc.write_to_filesystem(st, src)
	box.free()
	var md5 := FileAccess.get_md5(src)
	var n0: int = m.S.props.size()
	m._on_drop(PackedStringArray([src]))
	await idle(3)
	var lib := Importer_list()
	var last: Dictionary = m.S.props[-1]
	ok(m.S.props.size() == n0 + 1 and String(last["kind"]) == "my barrel" and lib.has("barrel") and FileAccess.get_md5(src) == md5 and m.ui_status.text.contains("imported"),
		"a .glb dropped: in the set as '%s', copied into the library %s, the original unchanged; says '%s'" % [last["kind"], lib, m.ui_status.text.left(50)])
	var sz: Vector3 = Props.solids(last)[0]["half"] * 2.0
	ok(sz.is_equal_approx(Vector3(0.3, 0.5, 0.3)), "  its solid is its size %s" % sz)
	var junk := ProjectSettings.globalize_path(dir + "/junk.glb")
	var f := FileAccess.open(junk, FileAccess.WRITE)
	f.store_string("not a model at all")
	f.close()
	var n1: int = m.S.props.size()
	m._on_drop(PackedStringArray([junk]))
	await idle(2)
	ok(m.S.props.size() == n1 and Importer_list().size() == lib.size() and m.ui_status.text.contains("could not import"), "a broken file dropped: refused in words ('%s'), nothing changed" % m.ui_status.text.left(70))
	m._rm_tree(dir)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
	print("SET TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)


func Importer_list() -> Array:
	return m.Importer.library_list(m.library)["props"].map(func(e): return e["name"])
