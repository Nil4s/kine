extends SceneTree
## P026 PULL ALONG (Friday plan item 26, Nick): a beginner builds a pipe by drawing a curve on the view and pulling the round shape along it.
## No Expert step, no separate path step: the Curvy line IS the path. Real clicks at 1280x720 from the BUILDING card.
## Walk (Easy): BUILDING -> Draw shape (Round) disc at the start of the curve -> Curvy line open from the disc's centre
##   -> Pull along (one press: the pipe) -> Undo (the pipe goes, one step)
## Bars (run on the code before the change: the FAIL lines are the dead ends):
##   0 the BUILDING card opens an empty Easy Part
##   1 a round disc drawn alone: the Pull along chip is not shown yet (it needs an open curve)
##   2 an open Curvy line from the disc: the Pull along chip shows and the hint names it
##   3 Pull along, one press: one sweep step, one solid
##   4 the built solid (the app's own mesh bounds, mm): the two long sides are the curve's length plus the disc, the short side is the disc
##   5 the pipe's volume matches the disc area x the length of the drawn curve (within 15%, from the drawn points in mm)
##   6 undo is one step: the pipe goes, the sweep count and the solid count go back to 0
## shots: C:/Temp/claude/p026pullalonga/
const SHOT := "C:/Temp/claude/p026pullalonga"
const DIRT := "user://p026pullalonga_test"

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


func drag_path(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		for k in range(1, 9):
			await ev_move(a.lerp(b, k / 8.0))
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu():
	return m.bld.part


## the screen point (1280 x 720 view) where the floor sketch point mm (x, y) lands: the app's own ground projection, inverted by Newton steps
func mm2scr(mm: Vector2) -> Vector2:
	var p := Vector2(432, 352)
	for i in 5:
		var g: Vector2 = pu().ep._ground(p, {}, false)
		var gx: Vector2 = pu().ep._ground(p + Vector2(4, 0), {}, false)
		var gy: Vector2 = pu().ep._ground(p + Vector2(0, 4), {}, false)
		var jx := (gx - g) / 4.0
		var jy := (gy - g) / 4.0
		var det := jx.x * jy.y - jy.x * jx.y
		var r := mm - g
		var d := Vector2((r.x * jy.y - jy.x * r.y) / det, (jx.x * r.y - r.x * jx.y) / det)
		p += d
	return p


func replayed() -> Dictionary:
	return Part.replay(pu()._ensure())


func volume() -> float:
	return float(replayed()["volume"])


func sweeps() -> int:
	var n := 0
	for f in pu()._ensure()["features"]:
		if f["t"] == "sweep":
			n += 1
	return n


func chip_shown() -> bool:
	var b = pu().ep.get("pull_along_btn")   # a property the code does not have yet is null, not a script error
	return b != null and (b as Button).is_visible_in_tree()


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
	await idle(90)   # the camera eases to its 3/4 view: the drawing maps must wait for it
	await shot("01_open")
	ok(m.cur_page == "BUILD" and m.S.kind == "building" and pu().on and pu().easy and pu()._ensure()["features"].size() <= 1,
		"0 BUILDING card opens an empty Easy Part (page %s)" % m.cur_page)

	# 1 a round disc drawn at mm (0, -40), radius 5 mm: no open curve yet, so the Pull along chip is not shown
	await click_ctl(pu().ep.make_btns["draw"])
	await click_ctl(pu().ep.shape_btns["round"])
	await drag_path([mm2scr(Vector2(0, -40)), mm2scr(Vector2(5, -40))])
	await idle(10)
	await shot("02_disc")
	ok(not chip_shown(), "1 a round disc alone: the Pull along chip is not shown (no curve yet)")

	# 2 an open Curvy line from the disc's centre: the chip shows and the hint names it
	await click_ctl(pu().ep.make_btns["curve"])
	await drag_path([mm2scr(Vector2(0, -40)), mm2scr(Vector2(40, -40)), mm2scr(Vector2(60, -20)), mm2scr(Vector2(60, 20))])
	await idle(10)
	await shot("03_curve")
	var say2: String = pu().ep.hint_l.text
	ok(chip_shown() and say2.find("Pull along") >= 0, "2 an open curve from the disc: the Pull along chip shows, the hint names it (%s)" % say2)

	# 3 Pull along, one real press: one sweep step, one solid
	var v0 := volume()
	var s0 := sweeps()
	var b0 := int(pu().res.get("bodies", 0))
	if chip_shown():   # no chip (bar 2 failed): the press cannot happen, and bar 3 fails
		await click_ctl(pu().ep.pull_along_btn)
	await idle(20)
	await shot("04_pipe")
	var b1 := int(pu().res.get("bodies", 0))
	ok(sweeps() == s0 + 1 and b0 == 0 and b1 == 1, "3 Pull along: one sweep step, one solid (sweeps %d -> %d, solids %d -> %d)" % [s0, sweeps(), b0, b1])

	# 4 the built solid's own bounds in mm: the curve runs 60 mm across and 60 mm down, the disc adds its size at each end;
	# the two long sides are about 70 mm, the short side is the disc's width (about 10 mm)
	var box: AABB = replayed()["aabb"]
	var sz := [box.size.x * 1000.0, box.size.y * 1000.0, box.size.z * 1000.0]
	sz.sort()
	ok(sz[0] > 8.0 and sz[0] < 13.0 and sz[1] > 60.0 and sz[1] < 85.0 and sz[2] > 60.0 and sz[2] < 85.0,
		"4 the pipe's bounds in mm, sorted: %.1f x %.1f x %.1f (short side the disc, long sides the curve)" % [sz[0], sz[1], sz[2]])

	# 5 the volume: the disc's area (radius 5 mm) x the drawn curve's length (40 + 28.3 + 40 mm), within 15%
	var want := PI * 5.0 * 5.0 * (40.0 + 28.28 + 40.0) * 1e-9
	var got := volume() - v0
	ok(absf(got - want) <= 0.15 * want, "5 the pipe's volume %.0f mm3 near the disc x curve %.0f mm3" % [got * 1e9, want * 1e9])

	# 6 undo: one step takes the pipe off (the pipe must be there first, so the bar fails when nothing was made)
	var made := sweeps()
	await click_ctl(pu().ep.undo_btn)
	await idle(20)
	await shot("05_undo")
	var b2 := int(pu().res.get("bodies", 0))
	ok(made == s0 + 1 and sweeps() == s0 and b2 == b0, "6 undo removes exactly the pipe (sweeps %d before undo, %d after; solids %d)" % [made, sweeps(), b2])

	print("p026pullalonga: %d fail" % fails)
	quit(1 if fails > 0 else 0)
