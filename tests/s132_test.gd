extends SceneTree
## s132 (Friday plan 132, "Grip point picker on any part: Hold it here"): on Easy Part's Colour page, Hold here + a click puts the grip where the hand
## holds the part, the Long axis / Face axis chips choose the way it lies in the hand, and Give to a character closes the hand on it.
## Real clicks at 1280x720 from the BUILDING card's Easy Part: a 200 mm rod drawn on the grid and pulled up. Every number is measured from the world
## (the drawn weapon mesh's own transform, Body.palm_point, the hand's grip axis, the saved file read back), never from the code's own variables.
## Bars:
##   1 the Colour page shows Hold here, Long axis and Face axis chips
##   2 Hold here + a click on the rod's end: ONE undo step; after Give the end is within 2 mm of the palm's centre (world, after the pose)
##   3 the hand is closed (index base joint bent more than 40 deg)
##   4 the rod lies along the hand's grip axis within 5 degrees
##   5 Hold here again on the middle: one undo step; the held rod's middle is within 2 mm of the palm
##   6 Face axis (one undo step): the clicked face's normal lies along the grip axis within 5 degrees, the rod across it
##   7 Long axis (one undo step): the rod is along the grip axis again within 5 degrees
##   8 Save the scene, read the file back, forget the Part in memory, load it: the grip is still the same spot (within 2 mm of the palm)
## shots: C:/Temp/claude/s132/end.png, middle.png, face.png
const SHOT := "C:/Temp/claude/s132"
const DIRT := "user://s132_test"

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


func ev_move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu():
	return m.bld.part


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func solid_box() -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for f in Part.body_faces(m.S.part, -1):
		for v in f:
			lo = lo.min(v)
			hi = hi.max(v)
	return AABB(lo, hi - lo)


func undo_n() -> int:
	return m.undo.size()


func held_kind() -> String:
	return String(m.B.wep_kind) if m.B.wep_on else ""


## a point of the Part (its own frame, m) in the world, through the drawn weapon mesh's own transform
func world_of(p: Vector3) -> Vector3:
	m._refresh()   # the drawn weapon is placed by the refresh: make sure it is the one for the pose now
	var mi := m.wep_model.find_child("part", true, false) as MeshInstance3D
	return mi.global_transform * p


func open_colour() -> void:
	var h = m.find_child("easypart_hold", true, false)
	if not (h as Button).is_visible_in_tree():
		await click_ctl(pu().ep.make_btns["colour"])
		await idle(6)


func palm() -> Vector3:
	return m.B.palm_point(m.B.wep_hand)


func angle_deg(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(a.normalized().angle_to(b.normalized()))


func rod_axis(bb: AABB) -> Vector3:
	var zc := bb.position.z + bb.size.z * 0.5
	var yt := bb.position.y + bb.size.y
	return world_of(Vector3(bb.end.x, yt, zc)) - world_of(Vector3(bb.position.x, yt, zc))


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

	# a rod 200 mm long (x -100..100), 20 mm wide, pulled up
	await click_ctl(pu().ep.make_btns["draw"])
	await drag_screen(scr(Vector3(-0.1, 0.0, -0.01)), scr(Vector3(0.1, 0.0, 0.01)))
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(60)
	if pu().res.get("bodies", 0) != 1:
		print("s132: no solid to hold: cannot continue")
		quit(1)
		return
	var bb := solid_box()
	var L := bb.size.x
	print("rod: %.1f x %.1f x %.1f mm" % [bb.size.x * 1000.0, bb.size.y * 1000.0, bb.size.z * 1000.0])
	var cam0 := [m.target, m.dist, m.pitch, m.yaw]
	var yt := bb.position.y + bb.size.y
	var zc := bb.position.z + bb.size.z * 0.5
	var xm := bb.position.x + L * 0.5

	# 1 the chips
	await click_ctl(pu().ep.make_btns["colour"])
	var hold = m.find_child("easypart_hold", true, false)
	var lng = m.find_child("easypart_grip_long", true, false)
	var fac = m.find_child("easypart_grip_face", true, false)
	ok(hold is Button and lng is Button and fac is Button and (hold as Button).is_visible_in_tree() and (lng as Button).is_visible_in_tree() and (fac as Button).is_visible_in_tree(),
		"1 the Colour page shows Hold here, Long axis and Face axis")
	if not (hold is Button and lng is Button and fac is Button):
		print("s132: %d fail" % fails)
		quit(1)
		return

	# 2 the END of the rod (the top face, 0.4 mm in from the end edge)
	var u0 := undo_n()
	await click_ctl(hold)
	await click_at(scr(Vector3(bb.end.x - 0.0004, yt, zc)))
	ok(pu().ep.armed == "" and undo_n() == u0 + 1, "2a Hold here + a click on the rod's end is ONE undo step (undo %d -> %d)" % [u0, undo_n()])
	await click_ctl(pu().ep.give_btn)
	await idle(6)
	var kind := held_kind()
	ok(kind.begins_with("part:"), "2b Give to a character: he holds '%s'" % kind)
	var end_w := world_of(Vector3(bb.end.x, yt, zc))
	var d_end := end_w.distance_to(palm()) * 1000.0
	ok(d_end <= 2.0, "2c the rod's end is %.2f mm from the palm's centre (bar 2 mm; world, after the pose)" % d_end)
	await shot("end")
	# 3 the hand is closed
	var jn := "index_01_" + String(m.B.wep_hand).substr(String(m.B.wep_hand).length() - 1)
	var bend := absf(float(m.B.ang[jn].x))
	ok(bend > 40.0, "3 the hand is closed on it: %s bent %.0f deg (bar > 40)" % [jn, bend])
	# 4 the rod along the hand's grip axis
	var a4 := angle_deg(rod_axis(bb), m.B.grip_axis(m.B.wep_hand))
	ok(a4 <= 5.0, "4 the rod lies %.2f deg from the hand's grip axis (bar 5)" % a4)

	# 5 the middle (Give framed the figure: the camera goes back to the part, as a user would look at it again)
	m.target = cam0[0]
	m.dist = cam0[1]
	m.pitch = cam0[2]
	m.yaw = cam0[3]
	m._cam()
	await idle(10)
	await open_colour()
	print("hold visible %s, armed '%s', says '%s'" % [(hold as Button).is_visible_in_tree(), pu().ep.armed, pu().ep.msg])
	var u1 := undo_n()
	await click_ctl(hold)
	print("after hold click: armed '%s', says '%s'" % [pu().ep.armed, pu().ep.msg])
	print("click at %s (cam target %s dist %s)" % [str(scr(Vector3(xm, yt, zc))), str(m.target), str(m.dist)])
	await click_at(scr(Vector3(xm, yt, zc)))
	await idle(6)
	print("after pick: armed '%s', says '%s', grip %s, held %s" % [pu().ep.armed, pu().ep.msg, str(m.S.part.get("grip")), held_kind()])
	print("dbg: recs grip %s, KINDS grip_u %.4f rev %s, wep_hand '%s', palm-vs-point %.2f mm, key_of %s, rev meta %s" % [str(PartWeapon.recs.get(held_kind(), {}).get("grip")), float(Body.KINDS[held_kind()]["grip_u"]), str(Body.KINDS[held_kind()].get("rev")), m.B.wep_hand, (m.B.palm_point(m.B.wep_hand) - m.B.wep_point(float(Body.KINDS[held_kind()]["grip_u"]))).length() * 1000.0, PartWeapon.key_of(m.S.part), str(m.wep_model.get_meta("kind", ""))])
	var mid_w := world_of(Vector3(xm, yt, zc))
	var d_mid := mid_w.distance_to(palm()) * 1000.0
	ok(undo_n() == u1 + 1, "5a Hold here on the middle is ONE undo step (undo %d -> %d)" % [u1, undo_n()])
	ok(d_mid <= 2.0, "5b the rod's middle is %.2f mm from the palm's centre (bar 2 mm)" % d_mid)
	var d_end2 := world_of(Vector3(bb.end.x, yt, zc)).distance_to(palm()) * 1000.0
	ok(absf(d_end2 - L * 500.0) < 8.0, "5c the end is now half a rod (%.0f mm) from the palm: %.1f mm" % [L * 500.0, d_end2])
	await shot("middle")

	# 6 Face axis
	var u2 := undo_n()
	await open_colour()
	await click_ctl(fac)
	await idle(6)
	var up_w := world_of(Vector3(xm, yt + 1.0, zc)) - world_of(Vector3(xm, yt, zc))   # the top face's normal (+Y of the Part), in the world
	var a6 := angle_deg(up_w, m.B.grip_axis(m.B.wep_hand))
	var a6r := angle_deg(rod_axis(bb), m.B.grip_axis(m.B.wep_hand))
	ok(undo_n() == u2 + 1, "6a Face axis is ONE undo step (undo %d -> %d)" % [u2, undo_n()])
	ok(a6 <= 5.0 and absf(a6r - 90.0) <= 5.0, "6b the clicked face's normal is %.2f deg from the grip axis, the rod %.1f deg (bars 5, 90 +- 5)" % [a6, a6r])
	var d6 := world_of(Vector3(xm, yt, zc)).distance_to(palm()) * 1000.0
	ok(d6 <= 2.0, "6c the picked spot is still in the palm: %.2f mm" % d6)
	await shot("face")

	# 7 Long axis again
	var u3 := undo_n()
	await open_colour()
	await click_ctl(lng)
	await idle(6)
	print("dbg7: says '%s', lng visible %s rect %s, armed '%s', rec grip %s axis %s" % [pu().ep.msg, (lng as Button).is_visible_in_tree(), str((lng as Button).get_global_rect()), pu().ep.armed, str(m.S.part.get("grip")), str(m.S.part.get("grip_axis"))])
	var a7 := angle_deg(rod_axis(bb), m.B.grip_axis(m.B.wep_hand))
	ok(undo_n() == u3 + 1 and a7 <= 5.0, "7 Long axis: ONE undo step (%d -> %d) and the rod is %.2f deg from the grip axis (bar 5)" % [u3, undo_n(), a7])

	# 8 save, read the file back, forget the Part, load
	m._save_scene_now("s132_grip_%d" % Time.get_ticks_msec())
	await idle(30)
	var path: String = m.scene_path
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var hp: Dictionary = (d as Dictionary).get("held_parts", {}) if d is Dictionary else {}
	var g: Array = []
	if not hp.is_empty():
		g = (hp[hp.keys()[0]] as Dictionary).get("grip", [])
	print("file: %s, cards %d, held_parts %s" % [path, ((d as Dictionary).get("cards", []) as Array).size() if d is Dictionary else -1, str(hp.keys())])
	ok(g.size() == 3 and absf(float(g[0]) - (xm / 0.001)) < 1.0, "8a the file holds the part with its grip at %s mm (middle x = %.1f mm)" % [str(g), xm / 0.001])
	var pg: Array = ((d as Dictionary).get("part", {}) as Dictionary).get("grip", [])
	ok(pg.size() == 3 and absf(float(pg[0])) < 1.0, "8b the file's own part record keeps the grip too: %s" % str(pg))
	# forget the part in memory: only the file knows it now
	Body.KINDS.erase(kind)
	PartWeapon.recs.erase(kind)
	PartWeapon.meshes.erase(kind)
	m.B.wep_on = false
	m._load_scene(path)
	await idle(30)
	ok(Body.KINDS.has(kind), "8c loading the file makes the held part again (kind '%s' is back)" % kind)
	if Body.KINDS.has(kind):
		m._do(m._kind.bind(kind))
		await idle(10)
		var kk: Dictionary = Body.KINDS[kind]
		print("dbg8: grip_u %.4f len %.4f xf %s pick %s hand '%s' palm-vs-point %.2f mm, S.part grip %s axis %s, meta %s" % [float(kk["grip_u"]), float(kk["len"]), str(kk.get("mesh_xf")), str(kk.get("grip_pick")), m.B.wep_hand, (m.B.palm_point(m.B.wep_hand) - m.B.wep_point(float(kk["grip_u"]))).length() * 1000.0, str(m.S.part.get("grip")), str(m.S.part.get("grip_axis")), str(m.wep_model.get_meta("kind", ""))])
		var d8 := world_of(Vector3(xm, yt, zc)).distance_to(palm()) * 1000.0
		var a8 := angle_deg(rod_axis(bb), m.B.grip_axis(m.B.wep_hand))
		ok(d8 <= 2.0 and a8 <= 5.0, "8d from the file alone, held again: the rod's middle is %.2f mm from the palm, the rod %.2f deg from the grip axis" % [d8, a8])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))   # the scene file this test wrote
	print("s132: %d fail" % fails)
	quit(1 if fails > 0 else 0)
