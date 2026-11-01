extends SceneTree
## FROOM (Nick 2026-10-28: "free 3D building, like Fusion 360, anything, nothing forced"): a beginner builds a small room from the
## BUILDING card by real clicks at 1280x720: a floor plate, two walls, a table inside, then tries a door cut and a window cut.
## Dead ends and confusing words are bars. Shots: C:/Temp/claude/froom/
const SHOT := "C:/Temp/claude/froom"
const DIRT := "user://froom_test"

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


## a real drag of an HSlider: from its grabber to the fraction fr of its track
func slide(s: HSlider, fr: float) -> void:
	var r := s.get_global_rect()
	var a := Vector2(r.position.x + r.size.x * (s.value - s.min_value) / maxf(s.max_value - s.min_value, 0.0001), r.get_center().y)
	var b := Vector2(r.position.x + r.size.x * fr, r.get_center().y)
	await drag_screen(a, b)


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


func vol() -> float:
	return float(pu().res.get("volume", 0.0))


func height() -> float:
	var bb: AABB = pu().res.get("aabb", AABB())
	return bb.size.y


## Easy Part's camera ease (EFRAME, 0.3 s) after a step that changes the box: a drag aimed from a camera read mid-ease lands
## off the floor. Wait until the ease is done (the view the user sees is the view a drag is aimed at). Not a bar: a settle.
func settle() -> void:
	var ep = pu().ep
	var n := 0
	while ep != null and not ep._ease.is_empty() and n < 200:
		await process_frame
		n += 1
	await idle(2)


func draw_on_floor(a: Vector2, b: Vector2) -> void:
	await click_ctl(pu().ep.make_btns["draw"])
	await settle()   # the Draw press may start an ease: aim the drag at the settled view
	var pa := scr(Vector3(a.x, 0.0, a.y))
	var pb := scr(Vector3(b.x, 0.0, b.y))
	if pu().ep._over_ui(pa):   # s178: the press point sits under the hint label (a press there is the label's, as for a user): draw the SAME rectangle from the other corner
		var tp := pa
		pa = pb
		pb = tp
	await drag_screen(pa, pb)


## the middle of the newest round hole, in metres on the floor (x, z); Vector2.INF when there is none
func hole_centre_m() -> Vector2:
	var rec: Dictionary = m.S.part
	var out := Vector2.INF
	for f in rec.get("features", []):
		if f["t"] == "sketch" and not f.get("ents", []).is_empty() and String(f["ents"][0].get("k", "")) == "circle":
			var c: Array = f["ents"][0]["c"]
			out = Vector2(float(c[0]) * Part.MM, -float(c[1]) * Part.MM)
	return out


func slider():
	var found = m.find_children("easypart_slider_last", "HSlider", true, false)
	return found[0] if not found.is_empty() else null


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
	m.pitch = -70.0
	m.yaw = 25.0
	m._cam()
	await idle(60)
	await shot("01_open")
	ok(m.cur_page == "BUILD" and pu().on and pu().easy, "0 BUILDING card, one click -> Easy Part on, page BUILD")

	# 1 floor plate: 0.8 m x 0.6 m, Draw shape + Pull it up
	await draw_on_floor(Vector2(-0.4, -0.3), Vector2(0.4, 0.3))
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(10)
	await shot("02_floor")
	ok(int(pu().res.get("bodies", 0)) == 1, "1 floor plate: Draw shape + Pull it up -> one body (bodies %d)" % int(pu().res.get("bodies", 0)))

	# 2 wall A (back): a 8 cm strip on the grid just outside the floor's back edge, pulled up, the How far slider to its far end
	await draw_on_floor(Vector2(-0.4, -0.36), Vector2(0.4, -0.28))
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(5)
	var sl = slider()
	if sl != null:
		await slide(sl, 1.0)
	await idle(10)
	await shot("03_wall_a")
	ok(height() >= 1.99, "2 wall A is 2 m tall (How far slider reaches 2 m) (height %.2f m, slider %s)" % [height(), sl != null])

	# 3 door: Cut a hole on wall A (a round hole through the middle of the newest solid): the volume drops
	var v0 := vol()
	await click_ctl(pu().ep.make_btns["hole"])
	await idle(10)
	await shot("04_door")
	var v1 := vol()
	ok(v1 < v0 - 1e-9 and v0 > 0.0, "3 door: Cut a hole through wall A lowers the volume (before %.6f, after %.6f)" % [v0, v1])

	# 3b the door's hole is in wall A: its middle (top-plane sketch, mm) is inside the wall's footprint (x -0.4..0.4, z -0.36..-0.28)
	var hc := hole_centre_m()
	ok(hc != Vector2.INF and absf(hc.x) <= 0.4 and hc.y >= -0.36 and hc.y <= -0.28, "3b the door hole is in wall A (hole middle at x,z %s m)" % [hc])

	# 4 wall B (left): strip outside the floor's left edge, pulled up, slider to its far end
	await draw_on_floor(Vector2(-0.44, -0.3), Vector2(-0.36, 0.3))
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(5)
	sl = slider()
	if sl != null:
		await slide(sl, 1.0)
	await idle(10)
	await shot("05_wall_b")
	ok(int(pu().res.get("bodies", 0)) == 1 and height() >= 1.99, "4 wall B joins the room: one body, 2 m tall (bodies %d, height %.2f)" % [int(pu().res.get("bodies", 0)), height()])

	# 6 window: Cut a hole on wall B
	var v2 := vol()
	await click_ctl(pu().ep.make_btns["hole"])
	await idle(10)
	await shot("07_window")
	ok(vol() < v2 - 1e-9, "6 window: Cut a hole through wall B lowers the volume (before %.6f, after %.6f)" % [v2, vol()])

	# 5 table: a box drawn on the floor top, pulled up, slider to 75 cm
	await draw_on_floor(Vector2(0.0, -0.1), Vector2(0.3, 0.2))
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(5)
	sl = slider()
	if sl != null:
		await slide(sl, (75.0 - 0.2) / 299.8)
	await idle(10)
	await shot("06_table")
	ok(int(pu().res.get("bodies", 0)) == 1, "5 table on the floor joins the room: one body (bodies %d)" % int(pu().res.get("bodies", 0)))

	# 6b the window hole is in wall B (footprint x -0.44..-0.36, z -0.3..0.3)
	var hc2 := hole_centre_m()
	ok(hc2 != Vector2.INF and hc2.x >= -0.44 and hc2.x <= -0.36 and absf(hc2.y) <= 0.3, "6b the window hole is in wall B (hole middle at x,z %s m)" % [hc2])

	# 7 plain words: no engineer words on screen
	var texts: Array = []
	texts_under(m, texts)
	var bad := []
	for t in texts:
		var s := String(t).to_lower()
		for w in ["sketch", "extrude", "boolean", "profile", "feature"]:
			if s.find(w) >= 0:
				bad.append(String(t))
				break
	ok(bad.is_empty(), "7 no engineer words on screen %s" % [bad])
	await shot("10_end")

	print("froom: %d fail" % fails)
	quit(1 if fails > 0 else 0)
