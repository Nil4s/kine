extends SceneTree
## godot --path . --position 4000,4000 -s tests/ebowl_test.gd     (EBOWL: the three Easy Part dead ends found by the ewalk4 beginner walk; scripts/easy_part.gd; needs the CAD DLL and a window)
## Real clicks and drags at 1280 x 720 only.
## Bars (each FAILED on the old code):
##   1 BOWL    ViewCube FRONT (side-on), a Curvy line closed ON the middle line (a cup-wall profile on the +X side), Spin it round:
##             one body, no failed step, box min y ~ 0 (it stands on the floor), and a ray straight down the middle hits only the bottom
##             (every hit below 10 mm: a hollow you can see). Shot C:/Temp/claude/ebowl/bowl.png (LOOK at it).
##   2 CHIP    a Round mug (circle on the floor, pulled up), then Draw shape again: the next shape is a BOX (the Round chip did not carry over)
##   3 WORDS   Draw shape + Pointy, a drag that STARTS under the words bar (the hint pill, top-left of the grid) draws the triangle

const SHOT := "C:/Temp/claude/ebowl"
const DIRT := "user://ebowl_test"
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


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


func drag_path(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for k in range(1, pts.size()):
		var a: Vector2 = pts[k - 1]
		var b: Vector2 = pts[k]
		for i in range(1, 9):
			await ev_move(a.lerp(b, i / 8.0))
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func pu() -> PartUI:
	return m.bld.part


func ep():
	return pu().ep


func bbox() -> AABB:   # mm
	var b: AABB = pu().res.get("aabb", AABB())
	return AABB(b.position / Part.MM, b.size / Part.MM)


func errors_of(rec: Dictionary) -> int:
	return Part.replay(rec)["errors"].size()


## an empty part, the camera at the given pitch and yaw
func fresh(pitch: float, yaw := 20.0) -> void:
	m.S.part = Part.make("Part")
	pu().upto = -1
	pu().sync()
	m.target = Vector3(0.0, 0.0, 0.0)
	m.pitch = pitch
	m.yaw = yaw
	m._cam()
	await idle(60)


## the screen point of a floor mm coordinate (the floor sketch axes: x right, v = -Z)
func floor_scr(mm: Vector2) -> Vector2:
	return scr(Part.to_world(Part.plane("top"), mm))


## the heights (mm) where a ray straight down the middle (0.5 mm off the axis) meets the replayed mesh, sorted
func down_hits() -> Array:
	var mesh: ArrayMesh = pu().res.get("mesh")
	var out := []
	if mesh == null or mesh.get_surface_count() == 0:
		return out
	var arr: Array = mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ix = arr[Mesh.ARRAY_INDEX]
	var from := Vector3(0.5, 1000.0, 0.3)   # in MM, 0.5 mm off the axis, off the seam (a ray ON a triangle edge can miss). MM, not metres: Godot's
	                                        # ray_intersects_triangle drops a triangle whose determinant is under 1e-5, i.e. every mm-sized one in metres
	var n: int = (ix.size() if ix != null else vs.size()) / 3
	for t in n:
		var a: Vector3 = vs[ix[3 * t]] if ix != null else vs[3 * t]
		var b: Vector3 = vs[ix[3 * t + 1]] if ix != null else vs[3 * t + 1]
		var c: Vector3 = vs[ix[3 * t + 2]] if ix != null else vs[3 * t + 2]
		var h = Geometry3D.ray_intersects_triangle(from, Vector3.DOWN, a / Part.MM, b / Part.MM, c / Part.MM)
		if h != null:
			out.append((h as Vector3).y)
	out.sort()
	return out


## the camera for a look at the part (a view change, not a press)
func pitch_view(p: float, y: float) -> void:
	m.pitch = p
	m.yaw = y
	m._cam()
	await idle(30)


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
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	# Nick 2026-10-28 (free 3D building, #100): the BUILDING card now opens a blank Easy Part itself. Start from the
	# state the card gave before (Part off, no part), so the clicks below drive the same opening they always did
	pu().set_on(false)
	pu().m.S.part = {}
	await process_frame
	await click_ctl(pu().part_btn)
	await click_ctl(pu().easy_open_btn)
	await idle(4)
	var rec: Dictionary = {}
	var hits: Array = []

	# 1 BOWL: a closed Curvy profile on the middle line (x = 0 is the axis), on the +X side, spun round the up axis
	await fresh(-40.0)
	var cube: ViewCube = m.ui_cube
	var q := cube._quad(0)
	var cen := (q[0] + q[1] + q[2] + q[3]) * 0.25
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = cen
	cube._gui_input(ev)
	await idle(60)
	ok(ep()._side_on(), "1a SIDE the ViewCube FRONT click looks side-on (yaw %.1f, pitch %.1f)" % [float(m.yaw), float(m.pitch)])
	# the cup wall: outer curve up from the axis at the floor, round the rim, inner curve down to the axis 4 mm up, back along the axis
	var prof := [[0.0, 0.0], [18.0, 0.5], [32.0, 6.0], [40.0, 20.0], [40.0, 40.0], [36.0, 56.0], [33.0, 56.0], [34.0, 40.0], [33.0, 20.0], [26.0, 8.0], [14.0, 4.0], [0.0, 4.0], [0.0, 0.0]]
	var pts := []
	for p in prof:
		pts.append(scr(Vector3(p[0] * Part.MM, p[1] * Part.MM, 0.0)))
	await click_ctl(ep().make_btns["curve"])
	await drag_path(pts)
	rec = m.S.part
	ok(Part.profile_sketch(rec) != "", "1b DRAWN the closed Curvy profile is a sketch (profile %s)" % Part.profile_sketch(rec))
	await click_ctl(ep().make_btns["spin"])
	rec = m.S.part
	var words := String(ep().msg)
	ok(errors_of(rec) == 0 and int(pu().res.get("bodies", 0)) == 1, "1c BOWL spun: one body, no failed step (bodies %d, errors %d, words [%s])" % [int(pu().res.get("bodies", 0)), errors_of(rec), words])
	var bb := bbox()
	ok(absf(bb.position.y) < 0.5, "1d BOWL it stands on the floor: box min y %.2f mm" % bb.position.y)
	hits = down_hits()
	var top := float(hits[hits.size() - 1]) if hits.size() > 0 else 999.0
	ok(hits.size() >= 1 and top < 10.0, "1e BOWL hollow: a ray down the middle hits only the bottom (hits at mm %s)" % str(hits))
	await pitch_view(-25.0, 20.0)
	await shot("bowl")

	# 2 CHIP: a Round mug on the floor, then Draw shape again: the next shape is a box
	await fresh(-40.0)
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["round"])
	await drag_screen(scr(Vector3(0.0, 0.0, 0.0)), scr(Vector3(0.04, 0.0, 0.0)))
	await click_ctl(ep().make_btns["pull"])
	await click_ctl(ep().make_btns["draw"])
	await drag_screen(scr(Vector3(0.10, 0.0, 0.10)), scr(Vector3(0.14, 0.0, 0.14)))
	rec = m.S.part
	var ls := Part.feature(rec, Part.profile_sketch(rec))
	var kind := String((ls["ents"][0] as Dictionary).get("k", "")) if not ls.is_empty() else ""
	ok(kind == "rect", "2a CHIP after a Round mug, Draw shape draws a box (sketch entity %s, words [%s])" % [kind, String(ep().msg)])

	# 3 WORDS: Pointy, the drag starts inside the words bar (the hint pill)
	await fresh(-40.0)
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["pointy"])
	var hr: Rect2 = ep().hint.get_global_rect()
	var st := hr.position + Vector2(12.0, 12.0)
	var g = ep()._ground(st)
	var before := Part.count_of(m.S.part, "sketch")
	if g == null:
		ok(false, "3a WORDS the press under the words bar lands on the floor")
	else:
		var en := floor_scr((g as Vector2) + Vector2(40.0, 40.0))
		ok(hr.has_point(st) and ep().hint.visible, "3a WORDS the drag starts under the words bar (bar %s, press %s, hint on %s)" % [str(hr), str(st), str(ep().hint.visible)])
		await drag_screen(st, en)
		rec = m.S.part
		var lt := Part.feature(rec, Part.profile_sketch(rec))
		ok(Part.count_of(rec, "sketch") == before + 1 and not lt.is_empty() and (lt["ents"] as Array).size() == 3, "3b WORDS the Pointy drag draws the triangle (sketches %d -> %d)" % [before, Part.count_of(rec, "sketch")])
	print("ebowl: %d fail" % fails)
	quit(1 if fails > 0 else 0)
