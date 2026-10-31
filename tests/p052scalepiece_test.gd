extends SceneTree
## P052 SCALE A PIECE (Friday plan 52, "Scale a piece by % slider; non-uniform (only taller)"): on Easy Part, a piece picked by a click
## gets a Size % slider (50 to 200 %) and a Taller only chip. One slider release is one undo step: the piece is rebuilt from the record as it
## was before the drag, scaled about its own middle (the bottom stays on its shape's plane). Taller only scales the up axis, nothing else.
## Real clicks and drags at 1280 x 720 from the real start screen. Every number is measured from the BUILT result (Part.body_faces of the
## record, which Part.replay built), never from the code's variables. The slider's own value is the only number read from a control.
##   S0 an empty grid: the Size % slider is hidden
##   1  a 60 x 60 mm square pulled up into a block, then a click on its top: the piece is picked and the Size % slider shows at 100 %, range 50..200
##   2  a drag on Size % to about 150 %: the block is bigger in all three axes by the slider's own % (within 2 %), one undo step
##   3  Undo (a real click) takes the scale back: the block is its size before the drag (within 0.1 mm), one undo step
##   4  the Taller only chip on (a real click), a drag to about 150 %: the width and the depth stay (within 0.5 mm), the height grows by the % (within 2 %)
##   5  Undo (a real click) takes the taller step back: one undo step, the block is its size before the drag (within 0.1 mm)
##   6  a click on empty grid takes the pick away: the Size % slider is hidden
## shots: C:/Temp/claude/p052scalepiece/picked.png (after the pick), taller.png (after the taller drag)
const SHOT := "C:/Temp/claude/p052scalepiece"
const DIRT := "user://p052scalepiece_test"

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


## a drag on a slider: press at the left fraction of its track, move to the right fraction, release
func drag_slider(s: HSlider, fa: float, fb: float) -> float:
	var r := s.get_global_rect()
	var a := Vector2(r.position.x + r.size.x * fa, r.get_center().y)
	var b := Vector2(r.position.x + r.size.x * fb, r.get_center().y)
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	var held := s.value   # the value while the button is still held (a release puts the slider back to 100)
	await ev_mouse(b, false)
	await idle(3)
	return held


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu():
	return m.bld.part


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


## the built block's size in mm (x, y, z) and its lowest and highest corners (metres), from the record's faces
func built_size() -> Vector3:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for f in Part.body_faces(m.S.part, -1):
		for v in f:
			lo = lo.min(v)
			hi = hi.max(v)
	return (hi - lo) / Part.MM


func built_top_centre() -> Vector3:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for f in Part.body_faces(m.S.part, -1):
		for v in f:
			lo = lo.min(v)
			hi = hi.max(v)
	return Vector3((lo.x + hi.x) * 0.5, hi.y, (lo.z + hi.z) * 0.5)


func size_slider() -> HSlider:
	return m.find_child("easypart_size_slider", true, false) as HSlider


func size_taller() -> Button:
	return m.find_child("easypart_size_taller", true, false) as Button


func size_shown() -> bool:
	var s := size_slider()
	return s != null and s.is_visible_in_tree()


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

	# the BUILDING card, one click: a blank Easy Part
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

	# S0 an empty grid: no slider
	ok(not size_shown(), "S0 an empty grid: the Size % slider is hidden")

	# a 60 x 60 mm square, pulled up into a block
	var draw = pu().ep.make_btns["draw"]
	await click_ctl(draw)
	await drag_screen(scr(Vector3(-0.03, 0.0, -0.03)), scr(Vector3(0.03, 0.0, 0.03)))
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(20)
	var s0 := built_size()
	print("block before: %.1f x %.1f x %.1f mm" % [s0.x, s0.y, s0.z])

	# 1 a click on the top picks the block: the slider shows at 100 %, range 50..200
	await click_at(scr(built_top_centre() - Vector3(0.0, 0.002, 0.0)))
	await idle(5)
	var sl := size_slider()
	var rng_ok := sl != null and absf(sl.min_value - 50.0) < 0.01 and absf(sl.max_value - 200.0) < 0.01 and absf(sl.value - 100.0) < 0.01
	ok(size_shown() and rng_ok, "1 a click on the block picks it: the Size %% slider shows at %s %%, range %s..%s" % [sl.value if sl else -1, sl.min_value if sl else -1, sl.max_value if sl else -1])
	await shot("picked")

	# 2 a drag on Size % to about 150 %: all three axes grow by the slider's %, one undo step
	var u0: int = m.undo.size()
	var held_pct: float = await drag_slider(sl, 1.0 / 3.0, 2.0 / 3.0)
	await idle(10)
	var s1 := built_size()
	var pct := held_pct / 100.0
	var grew := absf(s1.x / s0.x - pct) < 0.02 and absf(s1.y / s0.y - pct) < 0.02 and absf(s1.z / s0.z - pct) < 0.02
	ok(grew and pct > 1.4 and pct < 1.6 and m.undo.size() == u0 + 1, "2 a drag on Size %%: the block is %.1f x %.1f x %.1f mm (was %.1f x %.1f x %.1f), each axis x %.3f against the slider's %.1f %%, undo steps +%d" % [s1.x, s1.y, s1.z, s0.x, s0.y, s0.z, s1.x / s0.x, pct * 100.0, m.undo.size() - u0])

	# 3 Undo takes the scale back
	await click_ctl(pu().ep.undo_btn)
	await idle(10)
	var s2 := built_size()
	ok(absf(s2.x - s0.x) < 0.1 and absf(s2.y - s0.y) < 0.1 and absf(s2.z - s0.z) < 0.1, "3 Undo takes the scale back: %.1f x %.1f x %.1f mm (was %.1f x %.1f x %.1f)" % [s2.x, s2.y, s2.z, s0.x, s0.y, s0.z])

	# pick the block again (Undo cleared nothing else: the pick follows the block)
	await click_at(scr(built_top_centre() - Vector3(0.0, 0.002, 0.0)))
	await idle(5)
	sl = size_slider()
	var tx := size_taller()

	# 4 Taller only: the width and depth stay, the height grows by the slider's %
	if tx != null:
		await click_ctl(tx)
	await idle(5)
	var u1: int = m.undo.size()
	held_pct = await drag_slider(sl, 1.0 / 3.0, 2.0 / 3.0)
	await idle(10)
	var s3 := built_size()
	var pct3 := held_pct / 100.0
	var tall := absf(s3.y / s2.y - pct3) < 0.02 and pct3 > 1.4 and pct3 < 1.6
	var flat := absf(s3.x - s2.x) < 0.5 and absf(s3.z - s2.z) < 0.5
	ok(tx != null and tall and flat and m.undo.size() == u1 + 1, "4 Taller only, a drag to %.1f %%: the block is %.1f x %.1f x %.1f mm (was %.1f x %.1f x %.1f): height x %.3f, width and depth kept" % [pct3 * 100.0, s3.x, s3.y, s3.z, s2.x, s2.y, s2.z, s3.y / s2.y])
	await shot("taller")

	# 5 Undo takes the taller step back
	await click_ctl(pu().ep.undo_btn)
	await idle(10)
	var s4 := built_size()
	ok(absf(s4.x - s2.x) < 0.1 and absf(s4.y - s2.y) < 0.1 and absf(s4.z - s2.z) < 0.1, "5 Undo takes the taller step back: %.1f x %.1f x %.1f mm (was %.1f x %.1f x %.1f)" % [s4.x, s4.y, s4.z, s2.x, s2.y, s2.z])

	# 6 a click on empty grid takes the pick away: no slider
	await click_at(scr(Vector3(0.2, 0.0, 0.2)))
	await idle(5)
	ok(not size_shown(), "6 a click on empty grid takes the pick away: the Size % slider is hidden")

	print("p052scalepiece: %d fail" % fails)
	quit(1 if fails > 0 else 0)
