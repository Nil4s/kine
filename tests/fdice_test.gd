extends SceneTree
## FDICE (Nick 2026-10-28: "free 3D building, like Fusion 360, anything, nothing forced"): a beginner builds a DIE from the BUILDING card
## by real clicks and drags at 1280 x 720 (Easy Part only): a 40 mm cube, its edges rounded, and the pips (21 in all: 1 on the top, 2 on +X,
## 3 on +Z, 4 on -Z, 5 on -X, 6 on the bottom) cut into the faces, each pip a small round drawn ON its face, Cut a hole, and a shallow depth.
## Bars (marked (old) = FAILED on the code before the change, see the report):
##   0 BUILDING card, one click: page BUILD, Easy Part on, no chooser, an empty part
##   1 CUBE Draw shape (box) on the grid 40 x 40 mm, Pull it up (the slider to 4 cm): one body, box 40 x 40 x 40 mm
##   2 ROUND Round the edges: one fillet step, no failed step, the box stays 40 mm, the hint names Cut a hole next
##   3 PIPS each face gets its pips (the face number): after each face the cut steps grew by exactly that face's value
##   4 DIE 21 pip steps in all, one body, no failed step, the box is still 40 mm, the volume is smaller than the rounded cube
##   5 UNDO one undo takes away the newest pip only (21 -> 20 pip steps), redo gives it back
##   6 WORDS no jargon (sketch / extrude / body / feature / boolean / plane / profile) on screen during the walk
## Shots: C:/Temp/claude/fdice/*.png (open, cube, round, faces_a, faces_b, die; LOOK at them)
const SHOT := "C:/Temp/claude/fdice"
const DIRT := "user://fdice_test"
const JARGON := ["sketch", "extrude", "body", "feature", "boolean", "plane", "profile"]
const PIP_R := 5.5   # mm: the pip radius (the kernel needs a circle of at least 5 mm)
const PIP_DEPTH := 0.2   # cm: the How deep slider for a pip (2 mm)
const OFF := 10.0   # mm: a pip offset from the face middle (a 40 mm die)
const PIPS := {
	1: [[0, 0]],
	2: [[-1, -1], [1, 1]],
	3: [[-1, -1], [0, 0], [1, 1]],
	4: [[-1, -1], [1, -1], [-1, 1], [1, 1]],
	5: [[-1, -1], [1, -1], [0, 0], [-1, 1], [1, 1]],
	6: [[-1, -1], [-1, 0], [-1, 1], [1, -1], [1, 0], [1, 1]],
}
## the faces seen from each camera: view A from (+,+,+), view B from (-,+,-), view C from (+,-,+) under the floor for the bottom face
const VIEW_A := [[Vector3(0, 1, 0), 1], [Vector3(1, 0, 0), 2], [Vector3(0, 0, 1), 3]]
const VIEW_B := [[Vector3(-1, 0, 0), 5], [Vector3(0, 0, -1), 4]]
const VIEW_C := [[Vector3(0, -1, 0), 6]]

var fails := 0
var m: Node
var words_bad: Array = []
var hints := {}


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


func drag_pts(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(pts[i])
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


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


## wait real seconds (the camera eases in real time)
func settle(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await process_frame


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


func check_words(step: String) -> void:
	var texts: Array = []
	texts_under(ep().panel, texts)
	texts_under(ep().make_box, texts)
	texts_under(ep().hint, texts)
	for t in texts:
		for j in JARGON:
			if String(t).to_lower().find(j) >= 0:
				words_bad.append("%s: %s in %s" % [step, j, t])


func pu():
	return m.bld.part


func ep():
	return pu().ep


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func bbox() -> AABB:   # mm
	var b: AABB = pu().res.get("aabb", AABB())
	return AABB(b.position / Part.MM, b.size / Part.MM)


func cut_steps() -> int:
	var n := 0
	for f in m.S.part.get("features", []):
		if String(f["t"]) == "extrude" and String(f.get("op", "")) == "cut":
			n += 1
	return n


## the camera looks from (cp sin yaw, -sin pitch, cp cos yaw): (+,+,+) is yaw 45 pitch -35.3; (-,-,-) is yaw -135 pitch 35.3
func look(yaw: float, pitch: float) -> void:
	m.target = Vector3(0.0, 0.02, 0.0)
	m.pitch = pitch
	m.yaw = yaw
	m._cam()
	await settle(0.5)
	await idle(30)


## tangent axes (u, v) of a face with normal n
func axes(n: Vector3) -> Array:
	if absf(n.x) > 0.5:
		return [Vector3(0, 0, 1), Vector3(0, 1, 0)]
	if absf(n.y) > 0.5:
		return [Vector3(1, 0, 0), Vector3(0, 0, 1)]
	return [Vector3(1, 0, 0), Vector3(0, 1, 0)]


## one pip: Draw shape (round) on the face at the pip centre, Cut a hole, the How deep slider to 2 mm
func pip(n: Vector3, x: float, y: float) -> void:
	var ax: Array = axes(n)
	# bar 4 fix (11-01, per Nick): the die spans y 0-40 mm, so its real centre is (0, 20, 0) mm, not the origin; the face middle is that
	# centre pushed out by n * 20 mm. Before, the side-face pips were centred at y = 0 and 12 of the 21 missed the die
	var c: Vector3 = Vector3(0.0, 0.02, 0.0) + n * 0.02 + (ax[0] as Vector3) * x / 1000.0 + (ax[1] as Vector3) * y / 1000.0
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["round"])
	var rim: Vector3 = c + (ax[0] as Vector3) * PIP_R / 1000.0
	await drag_pts([scr(c), scr(rim)])
	await click_ctl(ep().make_btns["hole"])
	await idle(5)
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			await drag_slider(r["slider"], PIP_DEPTH)
	await idle(3)


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
	var chooser_open: bool = m.build_choose != null and m.build_choose.open
	ok(m.cur_page == "BUILD" and m.S.kind == "building" and pu().on and pu().easy and not chooser_open and (m.S.part.get("features", []) as Array).is_empty(),
		"0 BUILDING card, one click -> Easy Part on, no chooser, an empty part (page %s, chooser %s)" % [m.cur_page, chooser_open])
	await look(45.0, -35.0)
	await shot("open")
	check_words("open")

	# 1 CUBE: a 40 mm square on the grid, pulled up 4 cm
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["box"])
	await drag_pts([scr(Vector3(-0.02, 0.0, -0.02)), scr(Vector3(0.02, 0.0, 0.02))])
	await click_ctl(ep().make_btns["pull"])
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			await drag_slider(r["slider"], 4.0)
	await idle(10)
	var bc := bbox()
	ok(int(pu().res.get("bodies", 0)) == 1 and absf(bc.size.x - 40.0) < 0.6 and absf(bc.size.y - 40.0) < 0.6 and absf(bc.size.z - 40.0) < 0.6,
		"1 CUBE one body, box 40 x 40 x 40 mm: %s" % bc)
	check_words("cube")
	await shot("cube")
	var vol_cube := vol_mm()

	# 2 ROUND the edges
	await click_ctl(ep().make_btns["round"])
	await idle(10)
	var br := bbox()
	var fl := false
	for f in m.S.part.get("features", []):
		if String(f["t"]) == "fillet":
			fl = true
	hints["round"] = ep().hint_l.text
	var vol_round := vol_mm()
	ok(fl and (pu().res.get("errors", {}) as Dictionary).is_empty() and absf(br.size.x - 40.0) < 0.6 and vol_round < vol_cube - 1.0,
		"2 ROUND one fillet step, no failed step, box 40 mm, volume %.0f -> %.0f mm3" % [vol_cube, vol_round])
	ok(String(hints["round"]).find("Cut a hole") >= 0, "2b HINT after Round names Cut a hole [%s]" % hints["round"])
	check_words("round")
	await shot("round")

	# 3 PIPS, face by face (view A: 1, 2, 3; view B: 6, 5, 4)
	for view in [[45.0, -35.0, VIEW_A, "a"], [-135.0, -35.0, VIEW_B, "b"], [45.0, 35.0, VIEW_C, "c"]]:
		await look(view[0], view[1])
		for fv in view[2]:
			var n: Vector3 = fv[0]
			var want: int = fv[1]
			var before := cut_steps()
			for p in PIPS[want]:
				await pip(n, float(p[0]) * OFF, float(p[1]) * OFF)
			var got := cut_steps() - before
			ok(got == want and int(pu().res.get("bodies", 0)) == 1 and (pu().res.get("errors", {}) as Dictionary).is_empty(),
				"3 PIPS face %d (normal %s): %d pip steps, want %d, one body, no failed step" % [want, str(n), got, want])
		await shot("faces_" + String(view[3]))
		check_words("faces")

	# 4 DIE
	await look(45.0, -35.0)
	var bd := bbox()
	var vol_die := vol_mm()
	ok(cut_steps() == 21 and int(pu().res.get("bodies", 0)) == 1 and (pu().res.get("errors", {}) as Dictionary).is_empty() and absf(bd.size.x - 40.0) < 0.6 and vol_round - vol_die > 21.0 * 150.0 and vol_round - vol_die < 21.0 * 210.0,
		"4 DIE 21 pip steps, one body, no failed step, box 40 mm, volume %.0f -> %.0f mm3" % [vol_round, vol_die])
	await shot("die")

	# 5 UNDO takes away the newest pip only
	await click_ctl(ep().undo_btn)
	await idle(10)
	var c_undo := cut_steps()
	await click_ctl(ep().redo_btn)
	await idle(10)
	ok(c_undo == 20 and cut_steps() == 21, "5 UNDO one undo = one pip (21 -> %d), redo brings it back (%d)" % [c_undo, cut_steps()])

	# 6 WORDS
	ok(words_bad.is_empty(), "6 WORDS no jargon on screen during the walk: %s" % [words_bad])

	print("fdice: %d fail" % fails)
	quit(1 if fails > 0 else 0)


## the solid's volume in mm3 (the replay gives m3)
func vol_mm() -> float:
	return float(pu().replay_full(m.S.part)["volume"]) / (Part.MM * Part.MM * Part.MM)
