extends SceneTree
## NROUNDFILTER (Friday plan item 14): Easy Part gets three plain-word filters next to Round the edges: All edges, Only the outside,
## Only the top. A beginner rounds just the top edges of a box. Real clicks at 1280 x 720 from the real start screen.
## Walk: BUILDING card -> Draw shape (Box) + drag a 4 cm square -> Pull it up (2 cm) -> Only the top + Round the edges -> Undo (one step)
##   -> All edges + Round the edges -> Undo -> Only the outside + Round the edges.
## Every geometry bar is measured from the BUILT mesh (its own bounding box and vertices), never from the code's variables.
## A sharp corner = a mesh vertex within 0.05 mm of a box corner; a rounded edge removes its corner vertices.
## Bars (the old code fails the ones marked FAILS):
##   0 the BUILDING card, one click: Easy Part on, empty
##   1 the box: one solid, built size 36..44 x 18..22 x 36..44 mm, volume near its box volume
##   2 the three chips are on screen with their plain words and an icon each (FAILS: no filter chips)
##   3 Only the top + Round the edges: the 4 top corners are rounded away (passes on the old code too: its Round rounds all 12 edges)
##   4 Only the top: the 4 bottom corners stay sharp (FAILS on the old code)
##   5 Only the top: the round takes a little volume (10..60 mm3), not a lot
##   6 one Undo click takes the top round back: the top corners sharp again, volume back to the box
##   7 All edges + Round: the top and bottom corners are rounded (the old Round, every edge)
##   8 Only the outside on a plain box: the same edges as All edges (top and bottom corners rounded)
##   9 every press says a line in plain words (no key names)
## shots: C:/Temp/claude/nroundfilter/

const SHOT := "C:/Temp/claude/nroundfilter"
const DIRT := "user://nroundfilter_test"
const BAD := ["ctrl", "shift", "alt+", "esc", "enter", "tab ", "delete", "backspace", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12"]

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


func pu():
	return m.bld.part


func fl(x: float, y: float) -> Vector2:
	return m.cam.unproject_position(Part.to_world(Part.plane("top"), Vector2(x, y)))


func chip(nm: String) -> Control:
	return root.find_child(nm, true, false) as Control


## the built mesh's box corners (of its own bounding box): [sharp top corners, sharp bottom corners] (0..4 each); -1 = no mesh
func corners() -> Array:
	var mesh: Mesh = pu().res.get("mesh", null)
	if mesh == null:
		return [-1, -1]
	var bb: AABB = mesh.get_aabb()
	var pts := PackedVector3Array()
	for s in mesh.get_surface_count():
		pts.append_array(mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
	var tol := 0.05 * Part.MM
	var top := 0
	var bot := 0
	for sx: float in [0.0, 1.0]:
		for sz: float in [0.0, 1.0]:
			var x: float = bb.position.x + sx * bb.size.x
			var z: float = bb.position.z + sz * bb.size.z
			var ct := Vector3(x, bb.end.y, z)
			var cb := Vector3(x, bb.position.y, z)
			for p in pts:
				if p.distance_to(ct) < tol:
					top += 1
					break
			for p in pts:
				if p.distance_to(cb) < tol:
					bot += 1
					break
	return [top, bot]


func vol() -> float:
	return float(pu().res.get("volume", 0.0)) * 1e9   # mm3


func size_mm() -> Vector3:
	var mesh: Mesh = pu().res.get("mesh", null)
	if mesh == null:
		return Vector3.ZERO
	return mesh.get_aabb().size / Part.MM


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
	m.target = Vector3.ZERO
	m.pitch = -25.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	await shot("00_open")
	var ep = pu().ep
	ok(m.cur_page == "BUILD" and pu().on and pu().easy and int(pu().res.get("bodies", 0)) == 0,
		"0 BUILDING card, one click -> Easy Part on, empty (page %s)" % m.cur_page)

	# 1 the box: Draw shape (Box), a 4 cm square on the floor, Pull it up (2 cm)
	await click_ctl(ep.make_btns["draw"])
	await drag_screen(fl(-20, -20), fl(20, 20))
	await click_ctl(ep.make_btns["pull"])
	var sz := size_mm()
	var v0 := vol()
	var box_v := sz.x * sz.y * sz.z
	ok(int(pu().res.get("bodies", 0)) == 1 and sz.x >= 36.0 and sz.x <= 44.0 and sz.z >= 36.0 and sz.z <= 44.0 and sz.y >= 18.0 and sz.y <= 22.0 and absf(v0 - box_v) < box_v * 0.15,
		"1 the box: one solid, built %.0f x %.0f x %.0f mm, volume %.0f mm3 (box %.0f)" % [sz.x, sz.y, sz.z, v0, box_v])
	await shot("01_box")

	# 2 the three filter chips, plain words, an icon each
	var names := {"easypart_round_all": "All edges", "easypart_round_outside": "Only the outside", "easypart_round_top": "Only the top"}
	var chips_ok := true
	for k in names:
		var c := chip(k)
		if c == null or not c.is_visible_in_tree() or not (c is Button) or (c as Button).text != names[k] or (c as Button).icon == null:
			chips_ok = false
	ok(chips_ok, "2 the chips All edges / Only the outside / Only the top are on screen, plain words, an icon each")

	# 3 Only the top + Round the edges
	if chip("easypart_round_top") != null:
		await click_ctl(chip("easypart_round_top"))
	await click_ctl(ep.make_btns["round"])
	var c3 := corners()
	var v3 := vol()
	ok(c3[0] == 0, "3 Only the top: the 4 top corners are rounded (sharp top corners left: %d of 4) [%s]" % [c3[0], ep.msg])
	await shot("03_top")

	# 4 the bottom corners stay sharp
	ok(c3[1] == 4, "4 Only the top: the 4 bottom corners stay sharp (sharp bottom corners: %d of 4)" % c3[1])

	# 5 the round takes a little volume
	var loss := v0 - v3
	ok(loss >= 10.0 and loss <= 60.0, "5 Only the top: volume lost %.1f mm3 (10..60: a small round)" % loss)

	# 6 one Undo click takes it back
	await click_ctl(ep.undo_btn)
	var c6 := corners()
	ok(c6[0] == 4 and absf(vol() - v0) < 0.5, "6 one Undo: the top corners sharp again (%d of 4), volume back to %.1f mm3 (box %.1f)" % [c6[0], vol(), v0])

	# 7 All edges + Round: every edge, the bottom corners too
	if chip("easypart_round_all") != null:
		await click_ctl(chip("easypart_round_all"))
	await click_ctl(ep.make_btns["round"])
	var c7 := corners()
	ok(c7[1] == 0 and c7[0] == 0, "7 All edges: the bottom and top corners are rounded (sharp: top %d, bottom %d)" % [c7[0], c7[1]])
	await click_ctl(ep.undo_btn)

	# 8 Only the outside on a plain box: the same edges as All edges
	if chip("easypart_round_outside") != null:
		await click_ctl(chip("easypart_round_outside"))
	await click_ctl(ep.make_btns["round"])
	var c8 := corners()
	ok(c8[0] == 0 and c8[1] == 0, "8 Only the outside on a plain box: every outside edge rounded (sharp: top %d, bottom %d)" % [c8[0], c8[1]])
	await shot("08_outside")

	# 9 the words
	var bad := ""
	for w in BAD:
		if String(ep.msg).to_lower().contains(w):
			bad = w
	ok(String(ep.msg) != "" and bad == "", "9 the words say a line in plain words (%s)" % ep.msg)

	print("NROUNDFILTER: %d fail(s)" % fails)
	m.queue_free()
	quit(1 if fails > 0 else 0)
