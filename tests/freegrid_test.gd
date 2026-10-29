extends SceneTree
## FREEGRID (Nick 2026-10-28: "frame the empty part's grid like Fusion 360"): the BUILDING card opens a blank Easy Part whose floor grid
## (1 m square, y = 0) is centred in the free view (EasyPart.free_rect) and fills most of it, from a 3/4 view. Real clicks at 1280x720.
## Bars: 0 the card, one click -> Easy Part on, page BUILD; 1 the grid's screen box is centred in free_rect (within 4% of its size);
## 2 it fills most of it (the bigger side at least 80%) and sits inside it; 3 still so after 90 frames (no drift, no ease left);
## 4 a 3/4 view: pitch between -15 and -60 and yaw not square-on (between 15 and 75 degrees off a multiple of 90).
## shot: C:/Temp/claude/freegrid/open.png
const SHOT := "C:/Temp/claude/freegrid"
const DIRT := "user://freegrid_test"

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


func pu():
	return m.bld.part


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func grid_box() -> Rect2:
	var n := 10
	var e := n * 50.0 * Part.MM
	var r := Rect2()
	var first := true
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := scr(Vector3(sx * e, 0.0, sz * e))
			if first:
				r = Rect2(p, Vector2.ZERO)
				first = false
			else:
				r = r.expand(p)
	return r


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
	ok(m.cur_page == "BUILD" and m.S.kind == "building" and pu().on and pu().easy,
		"0 BUILDING card, one click -> Easy Part on, page BUILD (page %s)" % m.cur_page)
	await shot("open")

	var ep = pu().ep
	# the card's view tween and the grid's ease finish in their own time: wait until the grid stands still (10 frames), at most 300 frames
	var still := 0
	var last := grid_box()
	for i in 300:
		await process_frame
		var now := grid_box()
		still = still + 1 if now.position.distance_to(last.position) < 0.01 and now.size.distance_to(last.size) < 0.01 else 0
		last = now
		if still >= 10:
			break
	var fr: Rect2 = ep.free_rect()
	var gb := grid_box()
	var c_off := (gb.get_center() - fr.get_center())
	var fx := absf(c_off.x) / fr.size.x
	var fy := absf(c_off.y) / fr.size.y
	ok(fr.size.x > 40.0 and fr.size.y > 40.0 and fx <= 0.04 and fy <= 0.04,
		"1 grid centred in the free view (offset %.3f x %.3f of its size; free %s grid %s)" % [fx, fy, fr, gb])
	var fill := maxf(gb.size.x / fr.size.x, gb.size.y / fr.size.y)
	var inside := fr.grow(2.0).encloses(gb)
	ok(fill >= 0.8 and inside, "2 grid fills most of the free view (bigger side %.2f, inside %s)" % [fill, inside])

	await idle(90)
	var gb2 := grid_box()
	var drift := gb2.position.distance_to(gb.position) + gb2.size.distance_to(gb.size)
	ok(drift <= 2.0 and m.get_viewport().get_visible_rect().size.x > 0.0, "3 still framed after 90 frames (drift %.2f px)" % drift)

	var sq := fposmod(float(m.yaw), 90.0)
	var off_square := minf(sq, 90.0 - sq)
	ok(float(m.pitch) <= -15.0 and float(m.pitch) >= -60.0 and off_square >= 15.0,
		"4 a 3/4 view: pitch %.1f, yaw %.1f (%.1f deg off square-on)" % [float(m.pitch), float(m.yaw), off_square])

	print("freegrid: %d fail" % fails)
	quit(1 if fails > 0 else 0)
