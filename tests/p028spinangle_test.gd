extends SceneTree
## godot --path . --position 4000,4000 -s tests/p028spinangle_test.gd     (P028 Friday item 28: Spin it round with an Angle slider: half a spin = a half bowl; needs the CAD DLL and a window)
## Real clicks and drags at 1280 x 720 from the BUILDING card. A square is drawn on the floor beside the middle line (x 20..40 mm, depth 0..20 mm),
## Spin it round: a full ring 80 x 80 mm, 20 mm tall. The Angle slider (30..360 degrees) shows under the step; a drag to 180 makes a half bowl,
## a drag to 30 a slim slice. Everything is measured from the built result (mesh box and replay volume), never from the code's own numbers.
## Bars:
##   1 SPIN    Spin it round on the floor square: one solid, a full ring: 80 x 80 mm across, 20 mm tall (within 1.5 mm), volume a ring (within 2 pct)
##   2 ROW     an Angle slider shows under How far round, 30 to 360 degrees, starting at a full turn (360)
##   3 HALF    drag Angle to 180: one solid, 80 mm across x, the depth stays 40 mm (one side only, within 2.5 mm), volume half a ring (within 4 pct)
##   4 SLIM    drag Angle to 30: one solid, 20 mm deep (within 2.5 mm), 20 to 25.5 mm across x (a slim slice of the ring)
##   5 ONE     each Angle drag is one undo step
##   6 WORDS   no sketch / extrude / fillet / boolean / loft / revolve words on screen
## shots: C:/Temp/claude/p028spinangle/spin.png, half.png, slim.png (LOOK at them)
const SHOT := "C:/Temp/claude/p028spinangle"
const DIRT := "user://p028spinangle_test"

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


## a real drag of a slider knob to value v (the slider's own units)
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


func texts_under(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Label and (n as Label).text.strip_edges() != "":
		out.append((n as Label).text)
	elif n is Button and (n as Button).text.strip_edges() != "":
		out.append((n as Button).text)
	for c in n.get_children():
		texts_under(c, out)


## a world point (metres) on screen
func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func pu() -> PartUI:
	return m.bld.part


func ep():
	return pu().ep


func bodies() -> int:
	return int(pu().res.get("bodies", 0))


## the replay volume in mm3
func vol() -> float:
	return float(pu().res.get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)


func bbox() -> AABB:   # mm
	var b: AABB = pu().res.get("aabb", AABB())
	return AABB(b.position / Part.MM, b.size / Part.MM)


func undo_n() -> int:
	return m.undo.size()


func errors_of(rec: Dictionary) -> int:
	return Part.replay(rec)["errors"].size()


func bad_words(texts: Array) -> Array:
	var out := []
	for t in texts:
		var l := String(t).to_lower()
		for w in ["sketch", "extrude", "fillet", "boolean", "loft", "revolve"]:
			if l.find(w) >= 0:
				out.append(String(t))
				break
	return out


## an empty part, the camera above the floor
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


## the Angle slider: the row whose label is Angle (none on the old code: its label was How far round)
func angle_row() -> Dictionary:
	for r in ep().rows:
		if String(r.get("label", "")) == "Angle":
			return r
	return {}


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
	pu().set_on(false)
	pu().m.S.part = {}
	await process_frame
	await click_ctl(pu().part_btn)
	await click_ctl(pu().easy_open_btn)
	await idle(4)

	# 1 SPIN: the floor square x 20..40 mm, depth 0..20 mm, spun round the up axis: a full ring
	await fresh(-40.0)
	await draw_floor(Vector3(0.02, 0.0, 0.0), Vector3(0.04, 0.0, 0.02))
	await click_ctl(ep().make_btns["spin"])
	await idle(3)
	var rec: Dictionary = m.S.part
	var ring := PI * (40.0 * 40.0 - 20.0 * 20.0) * 20.0
	var full := bbox()
	ok(bodies() == 1 and errors_of(rec) == 0 and absf(full.size.x - 80.0) <= 1.5 and absf(full.size.z - 80.0) <= 1.5 and absf(full.end.y - 20.0) <= 1.5 and absf(vol() - ring) <= 0.02 * ring,
		"1 SPIN one solid, a full ring: %.1f x %.1f mm across, %.1f mm tall, volume %.0f (a ring %.0f) (bodies %d, failed steps %d)" % [full.size.x, full.size.z, full.end.y, vol(), ring, bodies(), errors_of(rec)])
	await shot("spin")

	# 2 ROW: the Angle slider under How far round, 30 to 360, at a full turn
	var row := angle_row()
	var sl: HSlider = row.get("slider") if not row.is_empty() else null
	ok(sl != null and absf(sl.min_value - 30.0) < 0.01 and absf(sl.max_value - 360.0) < 0.01 and absf(sl.value - 360.0) < 0.01,
		"2 ROW an Angle slider shows, 30 to 360 degrees, at a full turn (shown %s)" % [("%.0f to %.0f, at %.0f" % [sl.min_value, sl.max_value, sl.value]) if sl != null else "no row"])

	# 3 HALF: drag Angle to 180 degrees: a half bowl, one side only
	var u1 := undo_n()
	if sl != null:
		await drag_slider(sl, 180.0)
	await idle(5)
	var half := bbox()
	var u_half := undo_n() - u1
	ok(bodies() == 1 and absf(half.size.x - 80.0) <= 1.5 and absf(half.size.z - 40.0) <= 2.5 and absf(vol() - ring / 2.0) <= 0.04 * ring / 2.0,
		"3 HALF a half bowl: %.1f mm across x, %.1f mm deep (40 for a half), volume %.0f (half a ring %.0f) (bodies %d)" % [half.size.x, half.size.z, vol(), ring / 2.0, bodies()])
	await shot("half")

	# 4 SLIM: drag Angle to 30 degrees: a slim slice
	var u2 := undo_n()
	if sl != null:
		await drag_slider(sl, 30.0)
	await idle(5)
	var slim := bbox()
	ok(bodies() == 1 and absf(slim.size.z - 20.0) <= 2.5 and slim.size.x >= 20.0 and slim.size.x <= 25.5,
		"4 SLIM a slim slice at 30 degrees: %.1f mm across x (20 to 25.5), %.1f mm deep (20) (bodies %d)" % [slim.size.x, slim.size.z, bodies()])
	await shot("slim")

	# 5 ONE: each Angle drag is one undo step
	ok(u_half == 1 and undo_n() - u2 == 1, "5 ONE each Angle drag is one undo step (180: %d, 30: %d)" % [u_half, undo_n() - u2])

	# 6 WORDS
	var texts: Array = []
	texts_under(m, texts)
	var bw := bad_words(texts)
	ok(bw.is_empty(), "6 WORDS no sketch / extrude / fillet / boolean / loft / revolve on screen %s" % [bw])

	print("p028spinangle: %d fail" % fails)
	quit(1 if fails > 0 else 0)
