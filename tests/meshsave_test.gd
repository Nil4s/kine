## godot --path . --position 3000,3000 -s tests/meshsave_test.gd   (MODEL: MESH FILE, Ctrl+S save and Open...)
## Real keys and clicks only (root.push_input). The mesh file of a hobbyist's chair: save it, open it again.
## Bars, stated before measuring:
##   (a) a cube edit (face mode, all faces, extrude, Enter), Ctrl+S, type "chair", Enter: meshes/chair.kmesh exists in the
##       test folder, and the status line says "Saved chair.kmesh"
##   (b) a second edit, Ctrl+S: saves silently to the same file (no name box), the file holds the new mesh, status "Saved chair.kmesh"
##   (c) a new test cube (Esc, then Test cube), Open... (the ribbon), pick chair, Open: the mesh equals the saved one
##       (vert count and every position within 1e-5), and it is not the fresh cube
##   (d) F3 then "save mesh": the first row is the mesh save command
## Pinned 1280x720. The files go to a user:// folder of this test (UserPaths.force + root), nothing in res:// is written.
## Each bar fails on the old code (no Save / Open / Ctrl+S in MODEL): the FAIL lines are in the report.
extends SceneTree

const ROOT := "user://meshsave_test"

var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func key(k: Key, ctrl := false, shift := false) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.ctrl_pressed = ctrl
		ev.shift_pressed = shift
		ev.pressed = down
		root.push_input(ev, true)
		await process_frame
	await idle(3)


func type_text(s: String) -> void:
	for c in s:
		var code: int = c.to_upper().unicode_at(0)
		for down in [true, false]:
			var ev := InputEventKey.new()
			ev.keycode = code as Key
			ev.physical_keycode = code as Key
			ev.unicode = c.unicode_at(0)
			ev.pressed = down
			root.push_input(ev, true)
			await process_frame
	await idle(4)


func walk(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children(true):
		walk(c, out)
	return out


func visible_buttons() -> Array:
	var out := []
	for n in walk(root, []):
		if n is Button and (n as Button).is_visible_in_tree():
			out.append(n)
	return out


func text_of(b: Button) -> String:
	if b.text.strip_edges() != "":
		return b.text.strip_edges()
	if b.has_meta("label"):   # ribbon standard 5f40546c/6bde3d2d, Nick OK 2026-10-26: an icon-only ribbon button keeps its name in the label meta
		return String(b.get_meta("label"))
	for n in walk(b, []):
		if n is Label and (n as Label).text.strip_edges() != "":
			return (n as Label).text.strip_edges()
	return ""


## the screen point at a control's centre: a control inside a dialog reports its rect in the dialog's own window
func centre_of(c: Control) -> Vector2:
	var w := c.get_window()
	return (w.position if w != null else Vector2i.ZERO) + Vector2i(c.get_global_rect().get_center())


func click_at(p: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e, true)
		await process_frame
	await idle(4)


## a visible button by its text, clicked with the mouse (false when there is none)
func click_btn(txt: String) -> bool:
	for b in visible_buttons():
		if text_of(b) == txt:
			await click_at((b as Button).get_global_rect().get_center())
			return true
	return false


## a rest tool (under its group's caption, ribbon standard 5f40546c/6bde3d2d, Nick OK 2026-10-26): the caption's menu picks it by name,
## as a click on the caption then on the item does (false when no caption of that tab holds it)
func caption_pick(tab: String, label: String) -> bool:
	for pair in m.ui_caps[tab]:
		var tools: Array = pair[1]
		for i in tools.size():
			if m.label_of(tools[i]) == label:
				(pair[0] as MenuButton).get_popup().id_pressed.emit(i)
				return true
	return false


func save_dialog() -> Node:
	var d := m.find_child("mesh_save_dialog", true, false)
	return d if d != null and (d as Window).visible else null


func open_dialog() -> Node:
	var d := m.find_child("mesh_open_dialog", true, false)
	return d if d != null and (d as Window).visible else null


func status() -> String:
	return str(m.ui_status.text) if m.ui_status != null else ""


func saved_path() -> String:
	return UserPaths.w("res://meshes").path_join("chair.kmesh")


func _init() -> void:
	get_root().size = Vector2i(1280, 720)
	UserPaths.force = true
	UserPaths.root = ROOT
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT + "/meshes"))
	for f in DirAccess.get_files_at(ROOT + "/meshes"):
		DirAccess.remove_absolute(ROOT + "/meshes/" + f)   # this test's own folder: left empty before the run
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(10)
	if m.easy.on:
		await click_btn("Switch to Expert")
		await idle(10)

	# ---- (a) a cube edit, Ctrl+S, the name box, Enter ----
	await click_btn("MODEL")
	await click_btn("Test cube")
	await idle(10)
	var fresh_n: int = m.kmed.mesh.verts.size() if m.kmed != null and m.kmed.on else -1
	var fresh_p: PackedVector3Array = m.kmed.mesh.verts.duplicate() if m.kmed != null and m.kmed.on else PackedVector3Array()
	await key(KEY_3)     # face mode
	await key(KEY_A)     # every face
	var ext_ok := await click_btn("Extrude")   # the ribbon's Extrude: 10 cm along the normals, one undo step
	await idle(6)
	var edited_n: int = m.kmed.mesh.verts.size() if m.kmed != null and m.kmed.on else -1
	var moved := 0
	var edited_p: PackedVector3Array = m.kmed.mesh.verts if m.kmed != null and m.kmed.on else PackedVector3Array()
	for i in mini(fresh_p.size(), edited_p.size()):
		if fresh_p[i].distance_to(edited_p[i]) > 1e-4:
			moved += 1
	await key(KEY_S, true)   # Ctrl+S
	var box := save_dialog() != null
	await type_text("chair")
	await key(KEY_ENTER)
	await idle(6)
	var fa: bool = FileAccess.file_exists(saved_path())
	var msg_a := "(a) Ctrl+S asks a name (box %s), chair.kmesh exists in the test folder (%s), status '%s', the extrude moved %d of %d verts" % [str(box), str(fa), status(), moved, edited_n]
	ok(box and fa and status().findn("Saved chair.kmesh") >= 0 and moved > 0 and edited_n == fresh_n, msg_a)

	# ---- (b) a second edit, Ctrl+S: silent, the same file ----
	await click_btn("Extrude")
	await idle(6)
	var second_n: int = m.kmed.mesh.verts.size() if m.kmed != null and m.kmed.on else -1
	var second_pos: PackedVector3Array = m.kmed.mesh.verts.duplicate() if m.kmed != null and m.kmed.on else PackedVector3Array()
	await key(KEY_S, true)
	await idle(6)
	var no_box := save_dialog() == null
	var on_disk := KMesh.load_file(saved_path())
	var same_file := on_disk != null and on_disk.verts.size() == second_n
	var disk_n := on_disk.verts.size() if on_disk != null else -1
	var files_n := DirAccess.get_files_at(ROOT + "/meshes").size()
	ok(no_box and same_file and files_n == 1 and status().findn("Saved chair.kmesh") >= 0,
		"(b) second Ctrl+S: no box (%s), the same file holds the new mesh (%d verts, %s), one file in the folder (%d), status '%s'" % [str(no_box), second_n, str(same_file), files_n, status()])

	# ---- (c) a new test cube, Open..., pick chair ----
	await key(KEY_ESCAPE)
	await click_btn("MODEL")
	await click_btn("Test cube")
	await idle(10)
	var again_n: int = m.kmed.mesh.verts.size() if m.kmed != null and m.kmed.on else -1
	var again_p: PackedVector3Array = m.kmed.mesh.verts.duplicate() if m.kmed != null and m.kmed.on else PackedVector3Array()
	var fresh_far := 0.0   # how far the fresh cube's verts are from the saved ones (the saved one was extruded 10 cm)
	if on_disk != null and again_p.size() == on_disk.verts.size():
		for i in again_p.size():
			fresh_far = maxf(fresh_far, again_p[i].distance_to(on_disk.verts[i]))
	var opened := caption_pick("MODEL", "Open...")   # ribbon standard 5f40546c/6bde3d2d, Nick OK 2026-10-26: Open... is under the MESH caption now
	await idle(6)
	var od := open_dialog()
	var picked := false
	if od != null:
		var lists := []
		for n in walk(od, []):
			if n is ItemList:
				lists.append(n)
		if not lists.is_empty():
			var il: ItemList = lists[0]
			var p := centre_of(il) + il.get_item_rect(0).get_center() - il.get_global_rect().get_center()
			await click_at(p)
			picked = il.is_selected(0)
	if od != null:
		await click_at(centre_of((od as ConfirmationDialog).get_ok_button()))   # the dialog's Open button
	await idle(8)
	var same := false
	var worst := -1.0
	if m.kmed != null and m.kmed.on and on_disk != null:
		var got: PackedVector3Array = m.kmed.mesh.verts
		same = got.size() == on_disk.verts.size()
		if same:
			for i in got.size():
				worst = maxf(worst, got[i].distance_to(on_disk.verts[i]))
			same = worst <= 1e-5
	var msg_c := "(c) Open... (button %s), chair listed and picked (%s), the editor has the saved mesh (%d verts, worst position error %.6f), the fresh cube is %.3f m away from it" % [str(opened), str(picked), m.kmed.mesh.verts.size() if m.kmed != null and m.kmed.on else -1, maxf(worst, 0.0), fresh_far]
	ok(opened and od != null and picked and same and fresh_far > 0.05, msg_c)

	# ---- (d) F3 "save mesh": the command first ----
	await key(KEY_F3)
	var box_open: bool = m.ui_cmd != null and m.ui_cmd.visible
	await type_text("save mesh")
	var first := ""
	if box_open and m.ui_cmd.shown.size() > 0:
		first = String(m.ui_cmd.shown[0]["name"])
	ok(box_open and first.findn("save") >= 0 and first.findn("mesh") >= 0,
		"(d) F3 'save mesh' lists first: '%s'" % first)
	await key(KEY_ESCAPE)

	# leave the folder as it was found: this test's own file
	DirAccess.remove_absolute(saved_path())
	print("meshsave: %d FAIL" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
