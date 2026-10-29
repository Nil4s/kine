extends SceneTree
## FBOWL2 (Nick 2026-10-28: free 3D building, like Fusion 360): a beginner builds a SALAD BOWL from the BUILDING card by real clicks at
## 1280 x 720: one closed Curvy profile on the side-on FRONT view (a foot ring at the bottom, a wide rim at the top), Spin it round, then
## Colour > Wood on the whole bowl. Easy Part only. Bars marked (old) failed on the code before the fix.
##   0 BUILDING card, one click: page BUILD, Easy Part on, no chooser
##   1 BOWL the profile spins into ONE body, no failed step, it stands on the floor (box min y ~ 0)
##   2 RIM the rim is wide: the box is at least 180 mm across, and a ray 80 mm out from the middle hits the rim (top 54-60 mm)
##   3 FOOT a foot ring: a ray 40 mm out lands on the floor (y ~ 0), a ray down the middle does not (the middle is raised, y >= 2 mm)
##   4 HOLLOW a ray down the middle stops at the bowl floor (top hit below 15 mm), not at the rim
##   5 WOOD Colour > Wood on the bowl: one body, a wood-brown look (red > green > blue, red - blue >= 0.15)
##   6 WORDS no jargon word on screen during the walk
## Shots: C:/Temp/claude/fbowl2/*.png (open, bowl, wood)
const SHOT := "C:/Temp/claude/fbowl2"
const DIRT := "user://fbowl2_test"
const JARGON := ["sketch", "extrude", "body", "profile", "fillet", "pattern", "feature", "plane", "revolve"]
## the bowl wall (mm, x = from the middle line, y = up from the floor), drawn CLOSED: from the middle line at the recess, round the foot ring,
## up the wall, out to the wide rim, round the rim top and down the inside to the floor
const PROF := [[0.0, 3.0], [38.0, 3.0], [38.0, 0.0], [45.0, 0.0], [45.0, 6.0], [36.0, 6.0], [40.0, 22.0], [48.0, 40.0], [70.0, 52.0],
	[95.0, 58.0], [95.0, 63.0], [91.0, 63.0], [80.0, 57.0], [64.0, 49.0], [46.0, 41.0], [33.0, 29.0], [26.0, 18.0], [14.0, 13.0], [0.0, 12.0], [0.0, 3.0]]

var fails := 0
var m: Node
var words_bad: Array = []


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


## wait real seconds (the camera eases in real time)
func settle(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await process_frame


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func texts_under(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Label and (n as Label).text.strip_edges() != "":
		out.append((n as Label).text)
	elif n is Button and (n as Button).text.strip_edges() != "":
		out.append((n as Button).text)
	for c in n.get_children():
		texts_under(c, out)


func check_words(step: String) -> void:
	var texts: Array = []
	texts_under(ep().panel, texts)
	texts_under(ep().make_box, texts)
	texts_under(ep().hint, texts)
	for t in texts:
		for j in JARGON:
			if String(t).to_lower().find(j) >= 0:
				words_bad.append("%s: %s in %s" % [step, j, t])


func pu() -> PartUI:
	return m.bld.part


func ep():
	return pu().ep


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func bbox() -> AABB:   # mm
	var b: AABB = pu().res.get("aabb", AABB())
	return AABB(b.position / Part.MM, b.size / Part.MM)


func errors_of(rec: Dictionary) -> int:
	return Part.replay(rec)["errors"].size()


## the heights (mm) where a ray straight down at x = xmm (mm, z = 0.3 mm off the middle) meets the replayed mesh, sorted
func hits_at(xmm: float) -> Array:
	var mesh: ArrayMesh = pu().res.get("mesh")
	var out := []
	if mesh == null or mesh.get_surface_count() == 0:
		return out
	var arr: Array = mesh.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ix = arr[Mesh.ARRAY_INDEX]
	var from := Vector3(xmm, 1000.0, 0.3)   # in MM (see ebowl_test: a metre-sized ray misses mm triangles)
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

	# 0 the BUILDING card, one click
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	var chooser_open: bool = m.build_choose != null and m.build_choose.open
	ok(m.cur_page == "BUILD" and m.S.kind == "building" and pu().on and pu().easy and not chooser_open,
		"0 BUILDING card, one click -> Easy Part on, no chooser (page %s, chooser %s)" % [m.cur_page, chooser_open])
	m.target = Vector3.ZERO
	m.pitch = -30.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	await shot("open")

	# 1 BOWL: the ViewCube FRONT click (side-on), the closed profile drawn by real drags, Spin it round
	var cube: ViewCube = m.ui_cube
	var q := cube._quad(0)
	var cen := (q[0] + q[1] + q[2] + q[3]) * 0.25
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = cen
	cube._gui_input(ev)
	await idle(60)
	var pts := []
	for p in PROF:
		pts.append(scr(Vector3(float(p[0]) * Part.MM, float(p[1]) * Part.MM, 0.0)))
	await click_ctl(ep().make_btns["curve"])
	await drag_path(pts)
	await click_ctl(ep().make_btns["spin"])
	var rec: Dictionary = m.S.part
	var bb := bbox()
	var words := String(ep().msg)
	ok(errors_of(rec) == 0 and int(pu().res.get("bodies", 0)) == 1,
		"1a BOWL spun: one body, no failed step (bodies %d, errors %d, words [%s])" % [int(pu().res.get("bodies", 0)), errors_of(rec), words])
	ok(absf(bb.position.y) < 0.5, "1b BOWL it stands on the floor: box min y %.2f mm" % bb.position.y)
	await settle(1.5)
	await shot("bowl")

	# 2 RIM: wide. The box is 180 mm across or more, and the rim is solid 80 mm out (top 54-60 mm)
	ok(bb.size.x >= 180.0, "2a RIM the box is 180 mm across or more (%.1f mm)" % bb.size.x)
	var h80 := hits_at(80.0)
	var top80 := float(h80[h80.size() - 1]) if h80.size() > 0 else -1.0
	ok(top80 > 54.0 and top80 < 60.0, "2b RIM a ray 80 mm out hits the rim top at 54-60 mm (hits %s)" % str(h80))

	# 3 FOOT: the ring stands on the floor (40 mm out hits y ~ 0), the middle is raised (no hit below 2 mm)
	var h40 := hits_at(40.0)
	var low40 := float(h40[0]) if h40.size() > 0 else -1.0
	ok(absf(low40) < 1.0, "3a FOOT a ray 40 mm out lands on the floor ring (a spline rounds the foot corner: within 1 mm) (lowest %.2f mm)" % low40)
	var h0 := hits_at(0.5)
	var low0 := float(h0[0]) if h0.size() > 0 else -1.0
	ok(low0 >= 2.0, "3b FOOT the middle is raised off the floor (lowest hit %.2f mm, hits %s)" % [low0, str(h0)])

	# 4 HOLLOW: a ray down the middle stops at the bowl floor (top hit below 15 mm)
	var top0 := float(h0[h0.size() - 1]) if h0.size() > 0 else 999.0
	ok(h0.size() >= 1 and top0 < 15.0, "4 HOLLOW a ray down the middle stops at the bowl floor (top %.1f mm)" % top0)

	# 5 WOOD: Colour > Wood on the bowl
	await click_ctl(ep().make_btns["colour"])
	var wb: Button = ep().colour_box.find_child("easypart_colour_wood", true, false) as Button
	ok(wb != null, "5a WOOD a Wood colour chip is on the Colour row")
	if wb != null:
		await click_ctl(wb)
	var looks: Array = pu().res.get("body_looks", [])
	var lk: Dictionary = Part.look_at(looks, 0)
	var cc: Color = lk.get("c", Color.WHITE)
	ok(int(pu().res.get("bodies", 0)) == 1 and cc.r > cc.g and cc.g > cc.b and cc.r - cc.b >= 0.15,
		"5b WOOD the bowl is wood-brown: colour %s" % str(cc))
	await shot("wood")

	# 6 WORDS
	check_words("walk")
	ok(words_bad.is_empty(), "6 WORDS no jargon on screen during the walk: %s" % [words_bad])

	print("fbowl2: %d fail" % fails)
	quit(1 if fails > 0 else 0)
