extends SceneTree
## p085typetobuil (Friday plan item 85, Nick: monkey-brain easy): Type-to-build for parts. Parts > Type it: one line of words, "a box 20 by 10 by 5 cm,
## hollow, 2 mm walls, lid", then Build it: a box 200 x 100 x 50 mm, hollowed out with a 2 mm wall, its top 5 mm off as a lid. The steps
## stay editable: the Wall slider is the newest step. Real clicks at 1280 x 720 from the real start screen, on the live Easy Part.
## Walk: BUILDING card -> Parts -> Type it -> (type the words) -> Build it -> Wall slider -> two refusals (the words read from ep.msg, the sentence of the press)
## Bars (each one measured from the BUILT result: the replay bbox and body count, mesh rays, the undo list and the step list, never from the
## code's own variables):
##   0 Parts > Type it, one click: the words line and Build it show
##   1 Build it, one click: a box with a lid: two bodies, no build error
##   2 the bounding box: 200 long (x) x 50 tall (y) x 100 wide (z) mm (+-0.5)
##   3 the wall: a ray across the middle of the box at 25 mm up hits the outside of the +x wall, then its inside: 2 mm apart (+-0.2)
##   4 the lid: a ray down the middle hits the lid's top, then its underside 5 mm lower (+-0.2)
##   5 the steps are editable: the step list has at least 3 steps (the box, the split, the shell)
##   6 the Wall slider, moved to 4 mm, changes the built wall: the same ray pair is 4 mm apart (+-0.2)
##   7 the Build it press is one undo step
##   8 a side under 5 cm: refused, the words say a size to type, and nothing changes (undo count and bodies)
##   9 words with no box: refused, the words say "box", nothing changes
## shots: C:/Temp/claude/p085typetobuil/

const SHOT_DIR := "C:/Temp/claude/p085typetobuil"
const DIRT := "user://p085typetobuil_test"
const WORDS := "a box 20 by 10 by 5 cm, hollow, 2 mm walls, lid"

var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT_DIR, nm])


func pu():
	return m.bld.part


## the built bounding box in mm
func bbox() -> AABB:
	var b: AABB = pu().res.get("aabb", AABB())
	return AABB(b.position / Part.MM, b.size / Part.MM)


func build_errors() -> int:
	return (pu().res.get("errors", {}) as Dictionary).size()


## the built mesh's triangles in world metres
func world_tris() -> PackedVector3Array:
	var out := PackedVector3Array()
	var mi: MeshInstance3D = pu().part_mesh
	if mi == null or mi.mesh == null:
		return out
	var t := mi.global_transform
	for s in mi.mesh.get_surface_count():
		var arr: Array = mi.mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix = arr[Mesh.ARRAY_INDEX]
		if ix == null or (ix as PackedInt32Array).is_empty():
			for v in vs:
				out.append(t * v)
		else:
			for i in ix:
				out.append(t * vs[i])
	return out


## every hit distance (mm, sorted, hits closer than 0.05 mm merged) of a ray from o (mm) along unit d through the built mesh (Moller-Trumbore)
func ray_all(o_mm: Vector3, d: Vector3) -> Array:
	var o := o_mm * Part.MM
	var tris := world_tris()
	var hits: Array = []
	for k in range(0, tris.size() - 2, 3):
		var a := tris[k]
		var e1 := tris[k + 1] - a
		var e2 := tris[k + 2] - a
		var p := d.cross(e2)
		var det := e1.dot(p)
		if absf(det) < 1e-12:
			continue
		var s := o - a
		var u := s.dot(p) / det
		if u < 0.0 or u > 1.0:
			continue
		var q := s.cross(e1)
		var v := d.dot(q) / det
		if v < 0.0 or u + v > 1.0:
			continue
		var tt := e2.dot(q) / det
		if tt > 1e-6:
			hits.append(tt / Part.MM)
	hits.sort()
	var out: Array = []
	for h in hits:
		if out.is_empty() or float(h) - float(out[-1]) > 0.05:
			out.append(h)
	return out


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
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return

	# the BUILDING card, one click: Easy Part on, empty
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	m.target = Vector3.ZERO
	m.pitch = -25.0
	m.yaw = 20.0
	m._cam()
	await idle(60)

	# 0 Parts, then Type it: the words line and Build it show
	var parts: Button = root.find_child("easypart_chip_parts", true, false) as Button
	if parts != null:
		await click_ctl(parts)
	var type_it: Button = root.find_child("easypart_lib_Type it", true, false) as Button
	if type_it != null:
		await click_ctl(type_it)
	var edit: LineEdit = root.find_child("easypart_type_edit", true, false) as LineEdit
	var go: Button = root.find_child("easypart_type_go", true, false) as Button
	ok(type_it != null and edit != null and go != null and edit.is_visible_in_tree() and go.is_visible_in_tree(),
		"0 Parts > Type it shows the words line and Build it")

	# type the words, then one press of Build it
	var u0: int = m.undo.size()
	if edit != null:
		edit.text = WORDS
	if go != null:
		await click_ctl(go)
	await shot("01_typed_box")

	# 1 a box with a lid: two bodies, no build error
	var bodies: int = int(pu().res.get("bodies", 0))
	ok(bodies == 2 and build_errors() == 0,
		"1 the typed box with a lid: two bodies, no build error (bodies %d, errors %d)" % [bodies, build_errors()])

	# 2 the bounding box: 200 x 100 x 50 mm
	var bb: AABB = bbox()
	ok(absf(bb.size.x - 200.0) <= 0.5 and absf(bb.size.y - 50.0) <= 0.5 and absf(bb.size.z - 100.0) <= 0.5,
		"2 bounding box %.1f x %.1f x %.1f mm (want 200 x 50 x 100: long, tall, wide)" % [bb.size.x, bb.size.y, bb.size.z])

	# 3 the wall: a ray across the middle at 25 mm up, from past the +x side: the outside (10 mm away), then the inside 2 mm further
	var cx := bb.position.x + bb.size.x * 0.5
	var cz := bb.position.z + bb.size.z * 0.5
	var hits_x := ray_all(Vector3(bb.end.x + 10.0, bb.position.y + 25.0, cz), Vector3.LEFT)
	var wall := float(hits_x[1]) - float(hits_x[0]) if hits_x.size() >= 2 else -1.0
	ok(hits_x.size() >= 2 and absf(wall - 2.0) <= 0.2,
		"3 the wall is 2 mm: a ray across the +x wall hits the outside at %.1f mm and the inside at %.1f mm (wall %.2f, want 2)" % [
			float(hits_x[0]) if hits_x.size() >= 1 else -1.0, float(hits_x[1]) if hits_x.size() >= 2 else -1.0, wall])

	# 4 the lid: a ray down the middle hits its top, then its underside 5 mm lower
	var hits_y := ray_all(Vector3(cx, bb.end.y + 10.0, cz), Vector3.DOWN)
	var lid := float(hits_y[1]) - float(hits_y[0]) if hits_y.size() >= 2 else -1.0
	ok(hits_y.size() >= 2 and absf(lid - 5.0) <= 0.2,
		"4 the lid is 5 mm: a ray down the middle hits the top, then the underside %.2f mm lower (want 5)" % lid)

	# 5 the steps are editable: the step list shows at least 3 steps
	var steps_n := 0
	var steps_vb: VBoxContainer = m.bld.part.ep.steps_vb
	for c in steps_vb.get_children():
		if c is Button:
			steps_n += 1
	ok(steps_n >= 3, "5 the step list shows %d steps (want at least 3: the box, the split, the shell)" % steps_n)

	# 7 one undo step for the Build it press
	var u1: int = m.undo.size()
	ok(u1 == u0 + 1, "7 Build it is one undo step (undo %d -> %d)" % [u0, u1])

	# 6 the Wall slider: 4 mm; the built wall follows
	var wsl: HSlider = root.find_child("easypart_slider_last", true, false) as HSlider
	if wsl != null:
		wsl.value = 4.0
	await idle(30)
	var hits_w := ray_all(Vector3(bb.end.x + 10.0, bb.position.y + 25.0, cz), Vector3.LEFT)
	var wall4 := float(hits_w[1]) - float(hits_w[0]) if hits_w.size() >= 2 else -1.0
	ok(wsl != null and hits_w.size() >= 2 and absf(wall4 - 4.0) <= 0.2,
		"6 the Wall slider at 4 mm: the built wall is %.2f mm (want 4)" % wall4)
	await shot("02_wall_4mm")

	# 8 a side under 5 cm: refused in words, nothing changes (the box template's smallest side is 5 cm)
	var bodies_b: int = int(pu().res.get("bodies", 0))
	var u2: int = m.undo.size()
	if edit != null:
		edit.text = "a box 3 by 10 by 5 cm, hollow, 2 mm walls, lid"
	if go != null:
		await click_ctl(go)
	var st8: String = m.bld.part.ep.msg
	ok(m.undo.size() == u2 and int(pu().res.get("bodies", 0)) == bodies_b and st8.find("Try") >= 0,
		"8 a side under 5 cm is refused and names a size to type (undo %d -> %d, words: %s)" % [u2, m.undo.size(), st8])

	# 9 words with no box: refused, nothing changes
	var u3: int = m.undo.size()
	if edit != null:
		edit.text = "a sword with a long blade"
	if go != null:
		await click_ctl(go)
	var st9: String = m.bld.part.ep.msg
	ok(m.undo.size() == u3 and st9.find("box") >= 0,
		"9 words with no box are refused and say box (undo %d -> %d, words: %s)" % [u3, m.undo.size(), st9])

	print("P085TYPETOBUIL TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
