extends SceneTree
## godot --path . --position 4000,4000 -s tests/fdup_test.gd     (FDUP, Nick 2026-10-28: free 3D building, like Fusion 360: a beginner wants a second copy of the WHOLE part next to it; Duplicate, not Repeat; Undo removes it; needs the CAD DLL and a window)
## Real clicks at 1280 x 720 from the start screen: the BUILDING card (a blank Easy part), a 100 mm box pulled up 20 mm, then Duplicate.
## Bars (run on the old code before the change: 0, 1, 2, 3, 4 FAILED: there was no Duplicate button):
##   0 BUTTON  the top bar has a Duplicate button, its words are plain ("Duplicate", never "pattern" or "copy of the solid")
##   1 EMPTY   Duplicate on an empty part says why, adds no step and no undo step
##   2 PRESS   Duplicate on the box: two bodies, no failed step, ONE undo step
##   3 BESIDE  the copy sits beside the first (a gap, not fused): the box is 210 x 100 x 20 mm, the volume is twice the box (1 pct)
##   4 WORDS   the sentence after the press has no jargon (no pattern, feature, body, linear, record)
##   5 UNDO    Undo removes the copy: one body, the volume is the box again, the undo depth is back
## Shot: C:/Temp/claude/fdup/two.png (a 3/4 view of the two boxes; LOOK at it: two equal blocks side by side)
const SHOT := "C:/Temp/claude/fdup"
const DIRT := "user://fdup_test"

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


func last_of(rec: Dictionary, t: String) -> Dictionary:
	var out := {}
	for f in rec.get("features", []):
		if String(f["t"]) == t:
			out = f
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
	# state the card gave before (Part off, no part), so the clicks below drive the same opening
	pu().set_on(false)
	pu().m.S.part = {}
	await process_frame
	await click_ctl(pu().part_btn)
	await click_ctl(pu().easy_open_btn)
	await idle(4)
	await click_ctl(ep().empty_chip)
	await idle(4)
	ok(Part.count_of(m.S.part, "sketch") == 0 and Part.count_of(m.S.part, "extrude") == 0 and int(pu().res.get("bodies", 0)) == 0, "0 EMPTY the Empty chip leaves no steps and no body")

	# 0 BUTTON + 1 EMPTY: Duplicate is on the MAKE row; on a blank part it says why and adds nothing
	var dup_btn: Button = ep().dup_btn
	ok(dup_btn != null and String(dup_btn.text).to_lower().contains("duplicate") and not String(dup_btn.text).to_lower().contains("pattern"),
		"0 BUTTON the top bar has a Duplicate button: %s" % (String(dup_btn.text) if dup_btn != null else "none"))
	if dup_btn == null:
		print("fdup: %d fail" % fails)
		quit(1)
		return
	var ub0: int = m.undo.size()
	await click_ctl(dup_btn)
	var hint0 := String(ep().hint_l.text)
	ok(m.undo.size() == ub0 and Part.count_of(m.S.part, "pattern") == 0 and hint0.strip_edges() != "",
		"1 EMPTY Duplicate on a blank part adds no step and no undo step, says: %s" % hint0)

	m.pitch = -25.0
	m.yaw = 30.0
	m._cam()
	await idle(40)

	# the part: a 100 mm square on the floor, pulled up 20 mm
	await draw_floor(Vector3(-0.05, 0.0, -0.05), Vector3(0.05, 0.0, 0.05))
	await pull(2.0)
	var vseat := vol()
	var bs := bbox()
	ok(int(pu().res.get("bodies", 0)) == 1 and absf(bs.size.x - 100.0) < 0.5 and absf(bs.size.z - 100.0) < 0.5 and absf(bs.end.y - 20.0) < 0.5,
		"setup one body, 100 x 100 mm, 20 mm up: %s" % bs)

	# 2 PRESS: Duplicate once, one undo step
	var ubd1: int = m.undo.size()
	await click_ctl(ep().dup_btn)
	var ubd2: int = m.undo.size()
	var rd: Dictionary = pu().res
	ok(int(rd.get("bodies", 0)) == 2 and (rd.get("errors", {}) as Dictionary).is_empty() and ubd2 == ubd1 + 1,
		"2 PRESS Duplicate: two bodies, no failed step, one undo step (%d -> %d), bodies %d, errors %s" % [ubd1, ubd2, int(rd.get("bodies", 0)), str(rd.get("errors", {}))])

	# 3 BESIDE: the whole part again, next to it with a gap
	var bd := bbox()
	var vd := vol()
	ok(absf(bd.size.x - 210.0) < 1.0 and absf(bd.size.z - 100.0) < 1.0 and absf(bd.size.y - 20.0) < 1.0 and absf(vd - 2.0 * vseat) < 0.01 * 2.0 * vseat,
		"3 BESIDE the box is 210 x 100 x 20 mm and the volume is twice the box: %s, vol %.0f (want %.0f)" % [bd, vd, 2.0 * vseat])

	# 4 WORDS: the sentence after the press
	var hint_d := String(ep().hint_l.text)
	var bad := ""
	for w in ["pattern", "feature", "body", "linear", "record", "sketch"]:
		if hint_d.to_lower().contains(w):
			bad = w
	ok(bad == "", "4 WORDS the sentence after Duplicate has no jargon: %s" % hint_d)
	m.target = Vector3(0.0, 0.0, 0.0)
	m.dist = 0.6
	m.pitch = 18.0
	m.yaw = 35.0
	m._cam()
	await idle(60)
	await shot("two")

	# 5 UNDO: Undo takes the copy back
	await click_ctl(ep().undo_btn)
	await idle(3)
	var r5: Dictionary = pu().res
	ok(int(r5.get("bodies", 0)) == 1 and absf(vol() - vseat) < 0.01 * vseat and m.undo.size() == ubd1,
		"5 UNDO Undo removes the copy: one body, volume back to the box, undo depth %d (want %d)" % [m.undo.size(), ubd1])

	print("fdup: %d fail" % fails)
	quit(1 if fails > 0 else 0)
