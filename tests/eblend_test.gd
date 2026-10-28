extends SceneTree
## godot --path . --position 4000,4000 -s tests/eblend_test.gd     (EBLEND: Easy Part Blend two shapes for a beginner: a round base into a square top (a vase); scripts/easy_part.gd _blend; needs the CAD DLL and a window)
## Real clicks and drags at 1280 x 720 from the start screen. Bars:
##   1 VASE     a Round shape on the floor and a Box shape on the floor, Blend two shapes: ONE solid (one body), volume grows, no failed step, ONE undo step
##   2 ANGLE    a Round shape on the TOP face of a slab and a Box shape on its +X SIDE face, Blend two shapes: REFUSED in words (no loft step, no undo step,
##              the volume and the sketch count do not change). The old code made an empty loft and said Blended (FAILED on the old code: see the report).
##   3 WORDS    the refusal says why, in words that name the angle and the faces (no failed step text, no empty "Blended" claim)
## Shots: C:/Temp/claude/eblend/vase.png (the vase on the floor), angle.png (the refused blend)
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/eblend"
const DIRT := "user://eblend_test"


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
	await idle(2)


## a real press, a drag through every point, a release
func drag_pts(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(pts[i])
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


func dot_near(p: Vector2) -> bool:
	var ep = m.bld.part.ep
	for d in ep._dot_list():
		if (d["scr"] as Vector2).distance_to(p) <= 30.0:
			return true
	return false


## a point in the clear view at fractions (fx, fy), moved down until no amber dot or Easy panel is under it
func free_at(fx: float, fy: float) -> Vector2:
	var ep = m.bld.part.ep
	var cl: Rect2 = m.nav_clear_rect()
	var p := Vector2(cl.position.x + cl.size.x * fx, cl.position.y + cl.size.y * fy)
	for i in 40:
		if not dot_near(p) and not ep._over_ui(p):
			return p
		p += Vector2(0, 14)
	return p


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func count_kind(rec: Dictionary, t: String) -> int:
	return Part.count_of(rec, t)


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func vol_mm3() -> float:
	var pu: PartUI = m.bld.part
	return float(pu.res.get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)


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
	var pu: PartUI = m.bld.part
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
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep

	# 1 VASE: a round base on the floor, a square top on the floor, blended
	var ub: int = m.undo.size()
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["round"])
	var c0 := free_at(0.22, 0.3)
	await drag_pts([c0, c0 + Vector2(30, 0), c0 + Vector2(60, 0)])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	var b0 := free_at(0.12, 0.5)
	await drag_pts([b0, b0 + Vector2(40, 40)])
	await click_ctl(ep.make_btns["draw"])
	var ub2: int = m.undo.size()
	await click_ctl(ep.make_btns["blend"])
	var r1: Dictionary = pu.res
	ok(String(m.S.part["features"][-1]["t"]) == "loft" and (r1.get("errors", {}) as Dictionary).is_empty() and int(r1.get("bodies", 0)) == 1 and vol_mm3() > 1000.0 and m.undo.size() == ub2 + 1,
		"1 VASE the round base and the square top blend into ONE solid (bodies %d, volume %.0f mm3), no failed step, ONE undo step (%d -> %d) [%s]" % [int(r1.get("bodies", 0)), vol_mm3(), ub2, m.undo.size(), ep.hint_l.text])
	await shot("vase")

	# 2 ANGLE: a slab; a round on its top face, a box on its +X side face: the two planes are at an angle
	var tp := Part.make("Slab")
	tp["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "top", "ents": [{"k": "rect", "a": [-50.0, -50.0], "b": [50.0, 50.0]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 20.0, "both": false, "op": "new"}]
	tp["seq"] = 2
	m.S.part = tp
	pu.upto = -1
	pu.sync()
	await idle(3)
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 60.0
	m.yaw = 0.0
	m._cam()
	await idle(60)
	var v0 := vol_mm3()
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["round"])
	var t0 := scr(Vector3(0.0, 0.02, 0.0))
	var t1 := scr(Vector3(0.015, 0.02, 0.0))
	await drag_pts([t0, t1])
	m.pitch = 25.0
	m.yaw = 40.0
	m._cam()
	await idle(60)
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	var s0 := scr(Vector3(0.05, 0.01, -0.01))
	var s1 := scr(Vector3(0.05, 0.02, 0.01))
	await drag_pts([s0, s1])
	await click_ctl(ep.make_btns["draw"])
	var n_sk := count_kind(m.S.part, "sketch")
	var n_lf := count_kind(m.S.part, "loft")
	var ub3: int = m.undo.size()
	var v_before := vol_mm3()
	await click_ctl(ep.make_btns["blend"])
	var r2: Dictionary = pu.res
	var said: String = ep.hint_l.text
	var refused: bool = count_kind(m.S.part, "loft") == n_lf and m.undo.size() == ub3 and absf(vol_mm3() - v_before) < 1.0 and count_kind(m.S.part, "sketch") == n_sk
	ok(refused, "2 ANGLE the blend of a top-face round and a side-face box is refused: no loft step, no undo step, volume %.0f -> %.0f mm3, sketches %d -> %d (v0 %.0f)" % [v_before, vol_mm3(), n_sk, count_kind(m.S.part, "sketch"), v0])
	ok(said.contains("angle") and said.contains("face") and not said.contains("Blended"), "3 WORDS the refusal names the angle and the faces: [%s]" % said)
	await shot("angle")

	print("eblend: %d fail" % fails)
	m.queue_free()
	quit(1 if fails > 0 else 0)
