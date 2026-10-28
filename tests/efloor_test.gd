extends SceneTree
## godot --path . --position 4000,4000 -s tests/efloor_test.gd     (EFLOOR: Easy Part's empty-space sketches go on the FLOOR (Part top plane, y = 0); scripts/easy_part.gd; needs the CAD DLL and a window)
## Monkey-brain direction: a press with Draw shape / Curvy line on EMPTY space draws on the floor, Pull it up extrudes UP (+Y). Real clicks and drags at 1280 x 720.
## Bars:
##   1 FLOOR   a 40 x 40 mm square drawn on empty space, pulled up: one body, box min y = 0, box max y = the pull height (FAILED on the old code: the square sat on the front plane and pulled toward the viewer)
##   2 HOLE    Cut a hole on that floor body goes DOWN through it: the body keeps its height, volume drops by a vertical cylinder (pi r^2 h within 10 pct)
##   3 SPIN    Spin it round on a floor profile: a valid solid with volume, no failed step; it stands up and turns round the UP axis (a ring on the floor)
##   4 BLEND   two floor squares, Blend two shapes: one solid, the newer one offset UP 40 mm (box max y 40 mm)
##   5 REPEAT  Repeat it on a floor body: three copies, no failed step
##   6 MIRROR  Mirror that on a floor body at +X: a valid solid, no failed step
##   7 SPLIT   Cut in two on a floor body: two bodies
##   8 LEG     a press on the BOTTOM face of a floor-made top, pulled 60 mm: one body, box min y = -60 mm (the leg goes DOWN)
## Shot: C:/Temp/claude/efloor/shot.png, a table made only by clicks: a floor top, then four legs drawn on its underside (LOOK at it)
const SHOT := "C:/Temp/claude/efloor"
const DIRT := "user://efloor_test"

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


## a real drag: press at a, move in steps to b (held), release
func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


## a real drag of the slider knob to value v
func drag_slider(s: HSlider, v: float) -> void:
	var r := s.get_global_rect()
	var y := r.get_center().y
	var gw := 24.0
	var p0 := Vector2(r.position.x + gw * 0.5 + (s.value - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw), y)
	var x1 := r.position.x + gw * 0.5 + (v - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw)
	await ev_move(p0, false)
	await ev_mouse(p0, true)
	for i in range(1, 25):
		await ev_move(Vector2(lerpf(p0.x, x1, i / 24.0), y))
	await ev_mouse(Vector2(x1, y), false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


## a world point (metres) on screen
func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func pu() -> PartUI:
	return m.bld.part


func ep():
	return pu().ep


## the replay volume in mm3
func vol() -> float:
	return float(pu().res.get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)


func bbox() -> AABB:   # mm
	var b: AABB = pu().res.get("aabb", AABB())
	return AABB(b.position / Part.MM, b.size / Part.MM)


func errors_of(rec: Dictionary) -> int:
	return Part.replay(rec)["errors"].size()


## an empty part, the camera above (pitch < 0) or below (pitch > 0) the floor
func fresh(pitch: float) -> void:
	m.S.part = Part.make("Part")
	pu().upto = -1
	pu().sync()
	m.target = Vector3(0.0, 0.0, 0.0)
	m.pitch = pitch
	m.yaw = 20.0
	m._cam()
	await idle(60)


## the Draw shape button, then a real drag on the floor from world a to world b (metres, y = 0)
func draw_floor(a: Vector3, b: Vector3) -> void:
	await click_ctl(ep().make_btns["draw"])
	await drag_screen(scr(a), scr(b))


## Pull it up, then the slider to h cm (the default is 2 cm)
func pull(h: float) -> void:
	await click_ctl(ep().make_btns["pull"])
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			await drag_slider(r["slider"], h)
	await idle(3)


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
	await click_ctl(pu().part_btn)
	await click_ctl(pu().easy_open_btn)
	await idle(4)

	# 1 FLOOR: a 40 x 40 mm square on empty space, pulled up 20 mm
	await fresh(-40.0)
	await draw_floor(Vector3(0.01, 0.0, 0.01), Vector3(0.05, 0.0, 0.05))
	var rec: Dictionary = m.S.part
	ok(Part.count_of(rec, "plane") == 0 and Part.count_of(rec, "sketch") == 1, "1a FLOOR the draw is one sketch with no plane feature (sketches %d, planes %d)" % [Part.count_of(rec, "sketch"), Part.count_of(rec, "plane")])
	await pull(2.0)
	var bb := bbox()
	var ex: Dictionary = {}
	for f in rec["features"]:
		if String(f["t"]) == "extrude":
			ex = f
	var h := float(ex.get("dist", 0.0))
	ok(int(pu().res.get("bodies", 0)) == 1, "1b FLOOR one body after the pull (%d)" % int(pu().res.get("bodies", 0)))
	ok(absf(bb.position.y) < 0.5 and absf(bb.end.y - h) < 0.5, "1c FLOOR box min y = 0 and max y = the pull height: min %.1f, max %.1f (pull %.1f mm)" % [bb.position.y, bb.end.y, h])
	ok(absf(bb.size.x - 40.0) < 0.5 and absf(bb.size.z - 40.0) < 0.5, "1d FLOOR the footprint is the 40 x 40 mm square (%.1f x %.1f)" % [bb.size.x, bb.size.z])
	var h0 := vol()
	await shot("floor")

	# 2 HOLE: straight down through the floor body
	await click_ctl(ep().make_btns["hole"])
	var vh := vol()
	var r_mm := clampf(minf(bb.size.x, bb.size.z) * 0.12, 10.0, 40.0)
	var cyl := PI * r_mm * r_mm * h
	ok(absf((h0 - vh) - cyl) <= 0.1 * cyl and int(pu().res.get("bodies", 0)) == 1, "2a HOLE vertical: volume drops %.0f mm3, a cylinder r %.0f h %.0f is %.0f (within 10 pct)" % [h0 - vh, r_mm, h, cyl])
	var bb2 := bbox()
	ok(absf(bb2.position.y) < 0.5 and absf(bb2.end.y - h) < 0.5, "2b HOLE the body keeps its height: box y %.1f .. %.1f" % [bb2.position.y, bb2.end.y])
	await idle(3)

	# 3 SPIN: a floor profile spun round the up axis: valid, no failed step
	await fresh(-40.0)
	await draw_floor(Vector3(0.02, 0.0, 0.0), Vector3(0.04, 0.0, 0.02))
	await click_ctl(ep().make_btns["spin"])
	var hs: String = ep().hint_l.text
	ok(errors_of(m.S.part) == 0 and int(pu().res.get("bodies", 0)) >= 1 and vol() > 0.0, "3a SPIN a valid solid, no failed step: bodies %d, volume %.0f, words [%s]" % [int(pu().res.get("bodies", 0)), vol(), hs])
	# 3b: the floor drawing stands up and turns round the UP axis (a lathe piece on the floor): x 20..40, depth 0..20 -> a ring r 20..40,
	# 20 tall, from the floor up (spun round the floor line, half of it went under the floor)
	var sb := bbox()
	var ring := PI * (40.0 * 40.0 - 20.0 * 20.0) * 20.0
	ok(absf(sb.position.y) < 0.5 and absf(sb.end.y - 20.0) < 0.5 and absf(sb.size.x - 80.0) < 1.0 and absf(sb.size.z - 80.0) < 1.0 and absf(vol() - ring) < 0.01 * ring,
		"3b SPIN round the up axis, standing on the floor: box %s mm, volume %.0f vs a ring %.0f" % [sb, vol(), ring])

	# 4 BLEND: two floor squares, the newer one offset up 40 mm
	await fresh(-40.0)
	await draw_floor(Vector3(0.0, 0.0, 0.0), Vector3(0.03, 0.0, 0.03))
	await draw_floor(Vector3(0.0, 0.0, 0.0), Vector3(0.03, 0.0, 0.03))
	await click_ctl(ep().make_btns["blend"])
	var bl := bbox()
	ok(errors_of(m.S.part) == 0 and int(pu().res.get("bodies", 0)) == 1 and absf(bl.end.y - 40.0) < 0.5 and absf(bl.position.y) < 0.5, "4a BLEND one solid, the second shape offset UP: box y %.1f .. %.1f (want 0 .. 40)" % [bl.position.y, bl.end.y])

	# 5 REPEAT: three copies of a floor body
	await fresh(-40.0)
	await draw_floor(Vector3(0.01, 0.0, 0.01), Vector3(0.05, 0.0, 0.05))
	await pull(2.0)
	await click_ctl(ep().make_btns["repeat"])
	var lumps5 := ep()._lumps(Part.replay(m.S.part))   # the copies are pieces that do not touch: three lumps in one body
	ok(errors_of(m.S.part) == 0 and lumps5 == 3, "5a REPEAT three copies, no failed step (pieces %d)" % lumps5)

	# 6 MIRROR: a floor body at +X mirrored across the middle line
	await fresh(-40.0)
	await draw_floor(Vector3(0.01, 0.0, 0.01), Vector3(0.05, 0.0, 0.05))
	await pull(2.0)
	await click_ctl(ep().make_btns["mirror"])
	var nb6 := int(pu().res.get("bodies", 0))
	ok(errors_of(m.S.part) == 0 and nb6 in [1, 2], "6a MIRROR a valid solid, no failed step (bodies %d)" % nb6)

	# 7 SPLIT: a floor body cut in two
	await fresh(-40.0)
	await draw_floor(Vector3(0.01, 0.0, 0.01), Vector3(0.05, 0.0, 0.05))
	await pull(2.0)
	await click_ctl(ep().make_btns["split"])
	ok(errors_of(m.S.part) == 0 and int(pu().res.get("bodies", 0)) == 2, "7a SPLIT two bodies, no failed step (bodies %d)" % int(pu().res.get("bodies", 0)))

	# 8 LEG + the TABLE shot: a floor top, four legs drawn on its underside (pull goes DOWN)
	await fresh(-40.0)
	await draw_floor(Vector3(-0.05, 0.0, -0.05), Vector3(0.05, 0.0, 0.05))
	await pull(2.0)
	var bt := bbox()
	var topv := bt.end.y
	m.pitch = 35.0   # from below: the underside is in view
	m.yaw = 25.0
	m._cam()
	await idle(60)
	var legs := [[Vector3(-0.045, 0.0, -0.045), Vector3(-0.03, 0.0, -0.03)], [Vector3(0.03, 0.0, -0.045), Vector3(0.045, 0.0, -0.03)], [Vector3(-0.045, 0.0, 0.03), Vector3(-0.03, 0.0, 0.045)], [Vector3(0.03, 0.0, 0.03), Vector3(0.045, 0.0, 0.045)]]
	var first := true
	for lg in legs:
		await click_ctl(ep().make_btns["draw"])
		await drag_screen(scr(lg[0]), scr(lg[1]))
		await pull(6.0)
		if first:
			var bl1 := bbox()
			ok(int(pu().res.get("bodies", 0)) == 1 and absf(bl1.position.y + 60.0) < 0.5, "8a LEG a leg on the bottom of the top pulls DOWN: box min y %.1f (want -60)" % bl1.position.y)
			first = false
	var bl2 := bbox()
	ok(errors_of(m.S.part) == 0 and int(pu().res.get("bodies", 0)) == 1 and absf(bl2.position.y + 60.0) < 0.5 and absf(bl2.end.y - topv) < 0.5, "8b TABLE four legs on the underside: one body, y %.1f .. %.1f" % [bl2.position.y, bl2.end.y])
	await shot("shot")

	print("efloor: %d fail" % fails)
	quit(1 if fails > 0 else 0)
