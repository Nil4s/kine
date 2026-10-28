extends SceneTree
## godot --path . --position 4000,4000 -s tests/eside_test.gd     (ESIDE: Easy Part draws UPRIGHT through the middle when the camera looks side-on; scripts/easy_part.gd; needs the CAD DLL and a window)
## Monkey-brain direction: "you draw on what you look at". Side-on (|pitch| < 15, Easy opens at -30) a Draw shape / Curvy line press on EMPTY space draws on the upright
## plane through the part's middle that faces the camera (Front or Right by yaw); Pull it up pulls BOTH ways so the handle is centred on the mug.
## Looking down (|pitch| >= 15) still draws on the floor. Real clicks and drags at 1280 x 720.
## Bars (bar 1 FAILED on the old code: the side-on press drew on the floor, so the handle lay flat and one-sided):
##   1 HANDLE  a mug (round r 40 on the floor, Pull to 80, Cut a hole > Hollow inside), camera side-on by a ViewCube FRONT click, a closed Curvy loop
##             overlapping the wall at two places and bulging out to +X, Pull it up 10 mm: ONE body, volume grows, the box grows on the +X side only,
##             the handle centred (box z symmetric within 1 mm)
##   2 UNDO    the sketch is one undo step, the Pull press another, the slider drag another
##   3 FLOOR   looking down (pitch -40) a Draw shape on empty space is a floor sketch (plane "top"), no plane feature; efloor unchanged
## Shot: C:/Temp/claude/eside/shot.png, the mug with its handle at a 3/4 view (LOOK: it must read as a mug)

const SHOT := "C:/Temp/claude/eside"
const DIRT := "user://eside_test"

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


## a round cup: a circle r 40 mm on the floor, pulled up h cm (made by clicks)
func round_cup(h: float) -> void:
	await fresh(-40.0)
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["round"])
	await drag_screen(scr(Vector3(0.0, 0.0, 0.0)), scr(Vector3(0.04, 0.0, 0.0)))
	await click_ctl(ep().make_btns["pull"])
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			await drag_slider(r["slider"], h)
	await idle(3)


func chip(nm: String) -> Button:
	return root.find_child(nm, true, false) as Button


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
	# 0 ENTRY: the app starts level (main.gd pitch -8, side-on by the rule): Easy Part must open LOOKING DOWN, or every first drawing is upright
	ok(not ep()._side_on() and float(m.pitch) <= -15.0, "0 ENTRY Easy Part opens looking down (pitch %.1f): a first drawing goes on the floor" % float(m.pitch))

	# 0 + the mug: round r 40, Pull to 80 mm, Cut a hole > Hollow inside
	await round_cup(8.0)
	var bb0 := bbox()
	ok(absf(bb0.size.x - 80.0) < 0.6 and absf(bb0.size.y - 80.0) < 0.6, "0a SETUP round r 40 mm, 80 mm tall (x %.2f, y %.2f)" % [bb0.size.x, bb0.size.y])
	await click_ctl(ep().make_btns["hole"])
	var chh := chip("easypart_hole_hollow")
	if chh != null:
		await click_ctl(chh)
	await idle(3)
	var bm := bbox()
	ok(int(pu().res.get("bodies", 0)) == 1 and errors_of(m.S.part) == 0, "0b SETUP the mug is one hollow body (bodies %d)" % int(pu().res.get("bodies", 0)))

	# the camera side-on: the ViewCube FRONT face, a real click
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

	# 1 HANDLE: a closed Curvy loop on the wall: in at the top and bottom of the wall, out to +X
	var v0 := vol()
	var u0: int = m.undo.size()
	var loop := [[35.0, 15.0], [50.0, 20.0], [62.0, 42.0], [50.0, 60.0], [35.0, 70.0], [45.0, 42.0], [35.0, 15.0]]
	var pts := []
	for p in loop:
		pts.append(scr(Vector3(p[0] * 0.001, p[1] * 0.001, 0.0)))
	await click_ctl(ep().make_btns["curve"])
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	var words := String(ep().msg)
	ok(words.contains("Drawing upright, through the middle"), "1d WORDS on press [%s]" % words)
	for k in range(1, pts.size()):
		var a: Vector2 = pts[k - 1]
		var b: Vector2 = pts[k]
		for i in range(1, 9):
			await ev_move(a.lerp(b, i / 8.0))
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)
	var rec: Dictionary = m.S.part
	var sk := Part.feature(rec, Part.profile_sketch(rec))
	var pln := String(sk.get("plane", ""))
	var pf := Part.feature(rec, pln)
	ok(String(pf.get("t", "")) == "plane" and bool(pf.get("through", false)) and String(pf.get("from", "")) == "front", "1b SKETCH the loop sits on the upright front plane through the middle (plane %s, mm %s)" % [pln, str(pf.get("mm", ""))])
	ok(m.undo.size() == u0 + 1, "1c UNDO the loop is one undo step (%d -> %d)" % [u0, m.undo.size()])
	await click_ctl(ep().make_btns["pull"])
	var u1: int = m.undo.size()
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			await drag_slider(r["slider"], 1.0)
	var bh := bbox()
	var vh := vol()
	ok(errors_of(m.S.part) == 0 and int(pu().res.get("bodies", 0)) == 1, "1e HANDLE one body, no failed step (bodies %d)" % int(pu().res.get("bodies", 0)))
	ok(vh > v0 + 1000.0, "1f HANDLE volume grows: %.0f -> %.0f mm3" % [v0, vh])
	ok(bh.end.x > bm.end.x + 15.0 and absf(bh.position.x - bm.position.x) < 0.5, "1g HANDLE the box grows on the +X (handle) side only: x %.1f .. %.1f -> %.1f .. %.1f" % [bm.position.x, bm.end.x, bh.position.x, bh.end.x])
	ok(ep().hint_l.text.begins_with("Pulled out both ways"), "1i HANDLE the words say how it was pulled [%s]" % ep().hint_l.text)
	ok(absf(bh.position.z + bh.end.z) < 2.0, "1h HANDLE centred: box z %.2f .. %.2f (symmetric within 1 mm)" % [bh.position.z, bh.end.z])
	await shot("shot_front")
	m.pitch = -10.0
	m.yaw = 35.0
	m._cam()
	await shot("shot")
	m.pitch = -8.0
	m.yaw = 0.0
	m._cam()

	# 2 UNDO: the pull is one more undo step
	ok(u1 == u0 + 2 and m.undo.size() == u1 + 1, "2a UNDO the Pull press is one undo step, the slider another (%d -> %d -> %d)" % [u0 + 1, u1, m.undo.size()])

	# 3 FLOOR: looking down, the same press on empty space draws on the floor
	await fresh(-40.0)
	await draw_floor(Vector3(0.01, 0.0, 0.01), Vector3(0.05, 0.0, 0.05))
	var rf: Dictionary = m.S.part
	var skf := Part.feature(rf, Part.profile_sketch(rf))
	ok(String(skf.get("plane", "")) == "top" and Part.count_of(rf, "plane") == 0, "3a FLOOR looking down draws on the floor (plane %s, planes %d)" % [String(skf.get("plane", "")), Part.count_of(rf, "plane")])

	print("eside: %d fail" % fails)
	quit(1 if fails > 0 else 0)
