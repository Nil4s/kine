extends SceneTree
## FKETTLE (Nick 2026-10-28): a beginner who never read a manual builds a kettle from the BUILDING card (a free part, no house) by real clicks at 1280x720.
## Walk (Easy): BUILDING -> Curvy line, a closed loop right of the middle line -> Spin it round (the body)
##   -> Curvy line open from the body (the spout) and a Round disc at its start -> Expert -> CREATE, Sweep (the spout)
##   -> Easy: Draw shape a box off the body -> Pull it up (the lid: a separate piece, not joined)
## Bars (run on the old code first: the FAIL lines are the dead ends):
##   0 the BUILDING card opens an empty Easy Part
##   1 a closed Curvy loop by a real drag: the hint names Spin it round
##   2 Spin it round: one solid and a revolve step on the record (the body)
##   3 an open Curvy line from the body: the hint names the spout (Sweep)
##   4 the spout: Sweep (Expert) adds a pipe, volume grows, one sweep step
##   5 the lid: a box drawn apart from the body and pulled up stays a SEPARATE piece (one more loose piece, the app's count)
##   6 the lid is one undo step: undo removes exactly the lid (the count goes back)
## shots: C:/Temp/claude/fkettle/
const SHOT := "C:/Temp/claude/fkettle"
const DIRT := "user://fkettle_test"

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


func volume() -> float:
	return float(Part.replay(pu()._ensure())["volume"])


func sweeps() -> int:
	var n := 0
	for f in pu()._ensure()["features"]:
		if f["t"] == "sweep":
			n += 1
	return n


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

	# 1 a closed Curvy loop by a real drag, on the floor: one side of the middle line (x = 0 mm), touching it along one edge: the hint names Spin it round
	var loop_mm := [Vector2(0, -40), Vector2(40, -40), Vector2(60, -20), Vector2(60, 20), Vector2(40, 40), Vector2(0, 40), Vector2(0, -40)]
	var loop: Array = []
	for q in loop_mm:
		loop.append(mm2scr(q))
	await click_ctl(pu().ep.make_btns["curve"])
	await drag_path(loop)
	await idle(10)
	await shot("02_loop")
	var say1: String = pu().ep.hint_l.text
	ok(say1.find("Spin") >= 0, "1 a closed Curvy loop: the hint names Spin it round (%s)" % say1)

	# 2 Spin it round: one solid, a revolve step (the body)
	await click_ctl(pu().ep.make_btns["spin"])
	await idle(20)
	await shot("03_body")
	var revs := 0
	for f in pu()._ensure()["features"]:
		if f["t"] == "revolve":
			revs += 1
	var nb: int = int(pu().res.get("bodies", 0))
	ok(revs == 1 and nb == 1 and volume() > 0.0, "2 Spin it round: one solid, one revolve (bodies %d, revolve %d)" % [nb, revs])

	# 3 an open Curvy line from the body's side outward names the spout
	await click_ctl(pu().ep.make_btns["curve"])
	await drag_path([mm2scr(Vector2(60, 0)), mm2scr(Vector2(90, -10)), mm2scr(Vector2(120, -20)), mm2scr(Vector2(150, -25))])
	await idle(10)
	await shot("04_spout_line")
	var say3: String = pu().ep.hint_l.text
	ok(say3.find("Sweep") >= 0, "3 an open Curvy line names the spout (Sweep) (%s)" % say3)

	# 4 the spout: a round disc at the line's start, then Expert CREATE, Sweep: volume grows by one sweep step
	await click_ctl(pu().ep.make_btns["draw"])
	await click_ctl(pu().ep.shape_btns["round"])
	await drag_path([mm2scr(Vector2(60, 0)), mm2scr(Vector2(75, 0))])
	await idle(5)
	var v0 := volume()
	var s0 := sweeps()
	await click_ctl(pu().ep.expert_btn)
	await idle(20)
	var cap: MenuButton = null
	for lst in m.ui_caps.values():
		for pair in lst:
			for b in pair[1]:
				if (b as Node).name == "part_tool_sweep" and (pair[0] as Control).is_visible_in_tree():
					cap = pair[0]
	if cap != null:
		await click_ctl(cap)
		await idle(5)
		var pop := cap.get_popup()
		for i in pop.item_count:
			if pop.get_item_text(i) == "Sweep":
				pop.id_pressed.emit(pop.get_item_id(i))
		pop.hide()
		await idle(10)
		await click_ctl(pu().ok_btn)
		await idle(20)
	await shot("05_spout")
	var add := volume() - v0
	ok(sweeps() == s0 + 1 and add > 0.0, "4 the spout: Sweep adds one pipe (sweeps %d -> %d, volume +%.3e m3)" % [s0, sweeps(), add])

	var n_before: int = pu().ep._lumps(pu().res)   # the pieces before the lid (the spout may or may not touch the wall)
	# 5 the lid: back in Easy, a box drawn APART from the body, then Pull it up: a separate piece
	await click_ctl(pu().easy_open_btn)
	await idle(20)
	await click_ctl(pu().ep.make_btns["draw"])
	await click_ctl(pu().ep.shape_btns["box"])
	await drag_path([Vector2(180, 560), Vector2(260, 610)])
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(20)
	await shot("06_lid")
	var nb2: int = pu().ep._lumps(pu().res)   # the app's own count of pieces that do not touch (a join of apart pieces is one body with two lumps)
	ok(nb2 == n_before + 1, "5 the lid stays a separate piece: %d pieces that do not touch (before %d, want one more)" % [nb2, n_before])

	# 6 undo takes the lid off, one step: the spouted body is one piece again
	await click_ctl(pu().ep.undo_btn)
	await idle(20)
	await shot("07_undo")
	var nb3: int = pu().ep._lumps(pu().res)
	ok(nb3 == n_before, "6 undo removes exactly the lid (pieces %d -> %d)" % [nb2, nb3])

	print("fkettle: %d fail" % fails)
	quit(1 if fails > 0 else 0)
