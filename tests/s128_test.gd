extends SceneTree
## P128 CENTRE OF MASS + TIP-OVER WARNING (Friday plan 128). A small red dot at the part's centre of mass (kernel mass properties) and, when that
## point lies outside the footprint of what touches the floor, the plain words "It will tip over: its weight is N mm outside its feet" in the
## size line under the part. Reading only: no step, no undo.
## Bars (written before the code; mm are measured from the kernel / the mesh, never from the code's own variable):
##   C1 a 40 x 40 x 40 cube: the centre of mass is (20, 20, 20) mm within 0.05 mm
##   C2 an L-shape (60 x 20 and 20 x 40 rectangles, 20 deep): analytic centre (22, 22, 10) mm (areas 1200 at (30,10) and 800 at (10,40)) within 0.1 mm
##   C3 a tall thin box (20 x 100 x 20 mm) leaned 20 degrees: warns, the number in the words is the analytic 50 sin20 - 10 cos20 = 7.70 mm within 1 mm
##   C4 a stable box (and the cube, the L): no warning words
##   U1 in the app (real clicks): a plate stands: the size line has no warning, and pressing "Does it fall over?" puts the red dot on the mesh's middle (1 mm)
##   U2 Tilt it: the size line shows the warning with the mesh's own distance (within 1 mm), the dot is on, still at the middle
##   U3 pressing, showing the dot, the warning: the Part JSON is unchanged and the undo list did not grow
##   U4 Undo takes the lean back: the warning is gone
## shots: C:/Temp/claude/s128/plate.png, tip.png
const SHOT := "C:/Temp/claude/s128"
const DIRT := "user://s128_test"
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


func drag_pts(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(pts[i])
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func rec_of(feats: Array) -> Dictionary:
	return {"version": 1, "name": "t", "seq": 9, "features": feats}


func rect_ext(id: int, a: Array, b: Array, dist: float, op: String, extra := {}) -> Array:
	var sk := {"t": "sketch", "id": "s%d" % id, "name": "S%d" % id, "plane": "front", "ents": [{"k": "rect", "a": a, "b": b}], "dims": []}
	var ex := {"t": "extrude", "id": "e%d" % id, "name": "E%d" % id, "sketch": "s%d" % id, "dist": dist, "both": false, "op": op}
	ex.merge(extra)
	return [sk, ex]


func verts_of(s: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	var mesh: ArrayMesh = s["mesh"]
	for i in mesh.get_surface_count():
		out.append_array(mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX])
	return out


## the number in "... is 12 mm outside its feet" (-999 when there is none)
func mm_of(t: String) -> float:
	var rx := RegEx.new()
	rx.compile("(\\d+) mm outside")
	var mt := rx.search(t)
	return float(mt.get_string(1)) if mt != null else -999.0


## [the mesh's own middle (mean of the unique corners: a box), its distance in mm to the line the lowest corners rest on, how many corners are on the floor]
func mesh_dist_mm(s: Dictionary) -> Array:
	var seen := {}
	for q in verts_of(s):
		seen[Vector3(snappedf(q.x, 1e-4), snappedf(q.y, 1e-4), snappedf(q.z, 1e-4))] = true
	var mid := Vector3.ZERO
	var lo := INF
	for q in seen.keys():
		mid += q
		lo = minf(lo, q.y)
	mid /= float(seen.size())
	var feet := []
	for q in seen.keys():
		if q.y - lo <= 0.0005:
			feet.append(q)
	var d := INF
	if feet.size() >= 2:
		var a := Vector2((feet[0] as Vector3).x, (feet[0] as Vector3).z)
		var b := Vector2((feet[-1] as Vector3).x, (feet[-1] as Vector3).z)
		d = Vector2(mid.x, mid.z).distance_to(Geometry2D.get_closest_point_to_segment(Vector2(mid.x, mid.z), a, b))
	return [mid, d * 1000.0, feet.size()]


func dot_node(pu) -> MeshInstance3D:
	return pu.bu.root3.find_child("easypart_com_dot", true, false) as MeshInstance3D


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
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	var pu = m.bld.part
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	var ep = pu.ep
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 35.0
	m.yaw = 30.0
	m._cam()
	await idle(60)

	# C1..C4 straight from the kernel, by record
	var cube := PartCom.read(rec_of(rect_ext(1, [0, 0], [40, 40], 40.0, "new")))
	var cc: Vector3 = (cube["com"] as Vector3) * 1000.0
	print("     cube com mm ", cc)
	ok(bool(cube["ok"]) and (cc.distance_to(Vector3(20, 20, 20)) < 0.05 or cc.distance_to(Vector3(20, 20, -20)) < 0.05),
		"C1 cube centre of mass (%.3f, %.3f, %.3f) mm vs (20, 20, 20)" % [cc.x, cc.y, cc.z])
	var lf := rect_ext(1, [0, 0], [60, 20], 20.0, "new") + rect_ext(2, [0, 20], [20, 60], 20.0, "join")
	var lres := PartCom.read(rec_of(lf))
	var lc: Vector3 = (lres["com"] as Vector3) * 1000.0
	print("     L com mm ", lc)
	ok(bool(lres["ok"]) and absf(lc.x - 22.0) < 0.1 and absf(lc.y - 22.0) < 0.1 and absf(absf(lc.z) - 10.0) < 0.1,
		"C2 L-shape centre of mass (%.3f, %.3f, %.3f) mm vs (22, 22, 10)" % [lc.x, lc.y, lc.z])
	var tall := PartCom.read(rec_of(rect_ext(1, [-10, 0], [10, 100], 20.0, "new", {"tilt": 20.0})))
	var want_tall := 50.0 * sin(deg_to_rad(20.0)) - 10.0 * cos(deg_to_rad(20.0))
	var tw := String(tall["warn"])
	print("     tall: ", tw, "  margin ", tall["margin_mm"])
	ok(bool(tall["ok"]) and bool(tall["tips"]) and absf(mm_of(tw) - want_tall) < 1.0 and absf(-float(tall["margin_mm"]) - want_tall) < 1.0,
		"C3 leaning tall box: '%s', analytic %.2f mm, kernel margin %.2f mm" % [tw, want_tall, float(tall["margin_mm"])])
	var sb := PartCom.read(rec_of(rect_ext(1, [0, 0], [60, 40], 20.0, "new")))
	ok(bool(sb["ok"]) and not bool(sb["tips"]) and String(sb["warn"]) == "" and String(cube["warn"]) == "" and String(lres["warn"]) == "",
		"C4 stable box, cube and L: no warning (box margin %.1f mm inside)" % float(sb["margin_mm"]))

	# U1..U4 in the app, real clicks: a plate, Colour, Does it fall over?, Tilt it, Undo
	await click_ctl(ep.make_btns["draw"])
	await drag_pts([scr(Vector3(-0.06, 0.0, -0.04)), scr(Vector3(0.06, 0.0, 0.04))])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await idle(20)
	var info1: Array = mesh_dist_mm(Part.replay(m.S.part))
	var pre_size := String(ep.size_l.text) if ep.size_l.visible else "(hidden)"
	var nowarn: bool = ep.size_l.visible and String(ep.size_l.text).find("tip over") < 0
	var undo0: int = m.undo.size()
	var json0 := JSON.stringify(m.S.part)
	await click_ctl(ep.make_btns["colour"])
	await idle(10)
	var chip: Button = ep.colour_box.find_child("easypart_stand_check", true, false) as Button
	await click_ctl(chip)
	await idle(10)
	var d: MeshInstance3D = dot_node(pu)
	var want1: Vector3 = pu.part_mesh.global_transform * (info1[0] as Vector3)
	var got1: Vector3 = d.global_transform.origin if d != null else Vector3(INF, INF, INF)
	await shot("plate")
	ok(nowarn and d != null and d.visible and got1.distance_to(want1) < 0.001,
		"U1 plate stands: size line '%s' (no warning); dot %.2f mm from the mesh's middle" % [pre_size.replace("\n", " / "), got1.distance_to(want1) * 1000.0])
	ok(JSON.stringify(m.S.part) == json0 and m.undo.size() == undo0, "U3 the press changed nothing (undo %d -> %d)" % [undo0, m.undo.size()])

	await click_ctl(ep.make_btns["colour"])   # shut Colour: Tilt it shows with no step armed, the size line has room
	await idle(10)
	await click_ctl(ep.tilt_btn)
	await idle(20)
	await create_timer(0.6).timeout   # the reading is re-made at most every 300 ms
	await idle(5)
	var info2: Array = mesh_dist_mm(Part.replay(m.S.part))
	var txt2 := String(ep.size_l.text)
	var d2: MeshInstance3D = dot_node(pu)
	var want2: Vector3 = pu.part_mesh.global_transform * (info2[0] as Vector3)
	var got2: Vector3 = d2.global_transform.origin if d2 != null else Vector3(INF, INF, INF)
	await shot("tip")
	print("     size line: ", txt2.replace("\n", " / "), "  mesh distance ", info2[1], " on ", info2[2], " floor corners")
	ok(ep.size_l.visible and txt2.find("It will tip over: its weight is") >= 0 and absf(mm_of(txt2) - float(info2[1])) < 1.0,
		"U2 tilted plate: warning in the size line, %d mm vs the mesh's %.2f mm" % [int(mm_of(txt2)), float(info2[1])])
	ok(d2 != null and d2.visible and got2.distance_to(want2) < 0.001, "U2b the dot is on the tipping part at its middle (%.2f mm off)" % [got2.distance_to(want2) * 1000.0])
	ok(m.undo.size() == undo0 + 1, "U3b only the Tilt step is in the undo list (%d -> %d)" % [undo0, m.undo.size()])

	await click_ctl(ep.undo_btn)
	await idle(20)
	await create_timer(0.6).timeout
	await idle(5)
	var txt4 := String(ep.size_l.text)
	ok(ep.size_l.visible and txt4.find("tip over") < 0 and JSON.stringify(m.S.part) == json0, "U4 after Undo: no warning ('%s')" % txt4.replace("\n", " / "))
	print("s128: %d fail" % fails)
	quit(1 if fails > 0 else 0)
