extends SceneTree
## godot --path . --position 4000,4000 -s tests/eframe_test.gd     (EASY PART, FRAMING: scripts/easy_part.gd; needs the CAD DLL and a window)
## Bars (at 1280 x 720, from Easy home: a building project, Part, Easy; the plate is made through the model, then the camera is watched):
##   1 FRAME     a 3 mm x 20 mm plate (20 x 20 mm, 3 mm thick): after the step the camera eases (0.3 s) so the part's projected box spans
##               40-70% of the free view's height or width (the free view: clear of the MAKE row, the side panel, the status line)
##   2 NUDGE     a small edit (3 mm -> 3.3 mm: the box changes under 25%) moves the camera not at all
##   3 ANGLE     the framing keeps the view angle (pitch and yaw are the same before and after)
##   4 EXPERT    Expert Part is unchanged: a bigger box made in Expert does not move the camera
## Shots: C:/Temp/claude/eframe/shot.png (the framed plate, Easy Part)
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/eframe"
const DIRT := "user://eframe_test"


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


## the screen box of the part's bounds (its eight corners), null when a corner is behind the camera
func part_box(ep) -> Variant:
	var bb: AABB = m.bld.part.res.get("aabb", AABB())
	var r := Rect2()
	var first := true
	for i in 8:
		var q := bb.get_endpoint(i)
		if m.cam.is_position_behind(q):
			return null
		var sp: Vector2 = m.cam.unproject_position(q)
		r = Rect2(sp, Vector2.ZERO) if first else r.expand(sp)
		first = false
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
		print("FAIL: no KineCAD DLL, the framing cannot run")
		quit(1)
		return
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep
	var free_ok := ep.has_method("free_rect")
	await idle(6)
	# 1 FRAME: the plate is made (the feature list, then the rebuild: the same step a MAKE button takes)
	var pitch0: float = m.pitch
	var yaw0: float = m.yaw
	var pl := Part.make("Plate")
	pl["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [-10.0, -10.0], "b": [10.0, 10.0]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 3.0, "both": false, "op": "new"}]
	pl["seq"] = 2
	m.S.part = pl
	pu.upto = -1
	pu.sync()
	await idle(90)
	var box = part_box(ep)
	var frac := 0.0
	if free_ok and box != null:
		var fr: Rect2 = ep.free_rect()
		frac = maxf(box.size.x / fr.size.x, box.size.y / fr.size.y)
	ok(free_ok and box != null and frac >= 0.40 and frac <= 0.70,
		"1 FRAME a 3 mm x 20 mm plate spans %.0f%% of the free view (40-70%%) [free_rect %s]" % [frac * 100.0, str(ep.free_rect()) if free_ok else "missing"])
	await shot("shot")
	# 3 ANGLE: the same view angle as before the framing
	ok(absf(float(m.pitch) - pitch0) < 1e-4 and absf(float(m.yaw) - yaw0) < 1e-4,
		"3 ANGLE the view angle is kept (pitch %.2f -> %.2f, yaw %.2f -> %.2f)" % [pitch0, float(m.pitch), yaw0, float(m.yaw)])
	# 2 NUDGE: 3 mm -> 3.3 mm (a box change under 25%) moves nothing
	var t1: Vector3 = m.target
	var d1 := float(m.dist)
	var nudged: Dictionary = m.S.part.duplicate(true)
	for f in nudged["features"]:
		if String(f["t"]) == "extrude":
			f["dist"] = 3.3
	m.S.part = nudged
	pu.upto = -1
	pu.sync()
	await idle(90)
	ok(m.target.distance_to(t1) < 1e-4 and absf(float(m.dist) - d1) < 1e-4,
		"2 NUDGE a 3 mm -> 3.3 mm edit moves the camera not at all (dist %.4f -> %.4f)" % [d1, float(m.dist)])
	# 4 EXPERT: the same bounds change made in Expert Part does not move the camera
	await click_ctl(ep.expert_btn)
	await idle(6)
	var t2: Vector3 = m.target
	var d2 := float(m.dist)
	var big: Dictionary = m.S.part.duplicate(true)
	for f in big["features"]:
		if String(f["t"]) == "extrude":
			f["dist"] = 60.0
	m.S.part = big
	pu.upto = -1
	pu.sync()
	await idle(90)
	ok(m.target.distance_to(t2) < 1e-4 and absf(float(m.dist) - d2) < 1e-4,
		"4 EXPERT a bigger box in Expert Part does not move the camera (dist %.4f -> %.4f)" % [d2, float(m.dist)])
	print("eframe: %d FAIL" % fails)
	quit(1 if fails > 0 else 0)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])
