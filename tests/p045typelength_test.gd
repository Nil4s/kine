extends SceneTree
## p045typelength (Friday plan item 45: type an exact number on a segment while drawing, Fusion style).
## A beginner from the REAL start screen, real clicks, drags and keys at 1280 x 720:
##   Easy Part, Draw shape with the Line chip: press, drag, type a length while the button is held, Enter draws a straight
##   stretch of exactly that length from the last point, in the direction the pointer is going; the drag goes on; release.
##   Expert Part, Line tool: click the start, move, type 40, Enter: a 40 mm line from the click, in the pointer's direction.
## Bars (measured from the BUILT result: the newest sketch feature of the saved part and its entities in mm, the undo count,
## the camera angles, the words on the say line; never from variables of the code):
##   0 CHIP the Line chip is the shape
##   1 TYPED a typed 40 on a drag makes a stretch of 40.00 mm in the built sketch
##   2 SAME WAY the typed stretch turns less than 0.3 rad from the stretch before it (it runs on the way the drag went)
##   3 JOINED the typed stretch starts where the stretch before ends and ends where the next one starts (0.01 mm)
##   4 UNDO the whole drag with a typed stretch is ONE undo step
##   5 KEYS the typed digits do not turn the camera (yaw and pitch the same)
##   6 WORDS the say line says "Stretch of 40 mm drawn" in plain words
##   7 KINDS the drag's entities are all straight lines (no curve came from the typed stretch)
##   8 ZERO typing 0 and Enter says "above 0" (the say line)
##   9 NO ZERO no zero-length piece is drawn by that try (the shortest line is at least 1 mm)
##  10 BACK Backspace takes a digit back: "45", Backspace, "2", Enter makes a 42.00 mm stretch
##  11 EXPERT-A the Expert Line tool: a click, then 40 + Enter, makes a line of 40.00 mm
##  12 EXPERT-DIR that line runs exactly along the pointer (cosine of the angle to the pointer at least 0.9999)
##  13 EXPERT-AT that line starts at the click (within 0.01 mm)
## shots: C:/Temp/claude/p045typelength/
const SHOT := "C:/Temp/claude/p045typelength"
const DIRT := "user://p045typelength_test"
const LEN_TOL := 0.01

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


func key(k: Key, uni := 0) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.unicode = uni
		e.pressed = down
		root.push_input(e, true)
		await process_frame


## one typed character as the key it is: digits and "."
func type_chars(s: String) -> void:
	for ch in s:
		var k: Key = KEY_PERIOD if ch == "." else (KEY_0 + int(ch))
		await key(k, ch.unicode_at(0))
	await idle(2)


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


## the pointer walks in steps from a to b while the button is held
func walk(a: Vector2, b: Vector2) -> void:
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))


func press_tool(pu: PartUI, t: String) -> void:
	await click_ctl(pu.tool_btns[t])


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


## a sketch point (mm) of a plane, as a screen point (Expert)
func sp(pl_name: String, x: float, y: float) -> Vector2:
	return m.cam.unproject_position(Part.to_world(Part.plane(pl_name), Vector2(x, y)))


func sk_ents() -> Array:
	return m.bld.part._sk()["ents"] if m.bld.part.sk != "" else []


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


## the newest sketch feature of the saved part (its entities), or {} when there is none
func newest_sketch() -> Dictionary:
	var fs: Array = m.S.part.get("features", [])
	for i in range(fs.size() - 1, -1, -1):
		if String(fs[i].get("t", "")) == "sketch":
			return fs[i]
	return {}


## the entities of a sketch as lines: [kind, start, end] (mm); a curve has no end and is kept as its kind only
func kinds_of(ents: Array) -> Array:
	var out := []
	for e in ents:
		out.append(String(e.get("k", "")))
	return out


func e_a(e: Dictionary) -> Vector2:
	return Vector2(e["a"][0], e["a"][1])


func e_b(e: Dictionary) -> Vector2:
	return Vector2(e["b"][0], e["b"][1])


## the index of the first straight line of length len (mm, within LEN_TOL), or -1
func find_len(ents: Array, len: float) -> int:
	for i in ents.size():
		if String(ents[i].get("k", "")) == "line" and absf(e_a(ents[i]).distance_to(e_b(ents[i])) - len) < LEN_TOL:
			return i
	return -1


func lens_of(ents: Array) -> String:
	var out := []
	for e in ents:
		if String(e.get("k", "")) == "line":
			out.append("%.2f" % e_a(e).distance_to(e_b(e)))
	return str(out)


## the angle (rad) between two directions a->b and c->d, 0 when the same way
func turn(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	return absf(wrapf((d - c).angle() - (b - a).angle(), -PI, PI))


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
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep

	# ---- EASY: the Line chip, then a drag with a typed stretch
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["line"])
	ok(ep.shape == "line" and (ep.shape_btns["line"] as Button).button_pressed, "0 CHIP the Line chip is the shape (shape %s)" % str(ep.shape))
	var ub1: int = m.undo.size()
	var c0 := free_at(0.2, 0.3)
	await ev_move(c0, false)
	await ev_mouse(c0, true)
	await walk(c0, c0 + Vector2(120, 0))
	var yaw0: float = m.yaw
	var pitch0: float = m.pitch
	await type_chars("40")
	await key(KEY_ENTER)
	await idle(2)
	var said1 := String(ep.msg)
	await walk(c0 + Vector2(120, 0), c0 + Vector2(120, 60))
	await ev_mouse(c0 + Vector2(120, 60), false)
	await idle(3)
	await shot("typed_easy_40")
	var ents: Array = newest_sketch().get("ents", [])
	var ti := find_len(ents, 40.0)
	ok(ti >= 0, "1 TYPED a typed 40 on the drag makes a 40.00 mm line in the built sketch (line lengths %s)" % lens_of(ents))
	var same := false
	var joined := false
	if ti >= 1 and ti + 1 < ents.size():
		var pre: Dictionary = ents[ti - 1]
		var typed: Dictionary = ents[ti]
		var nxt: Dictionary = ents[ti + 1]
		same = String(pre.get("k", "")) == "line" and turn(e_a(pre), e_b(pre), e_a(typed), e_b(typed)) < 0.3
		joined = e_b(pre).distance_to(e_a(typed)) <= LEN_TOL and e_b(typed).distance_to(e_a(nxt)) <= LEN_TOL
	ok(same, "2 SAME WAY the typed stretch runs on from the stretch before it (the kinds %s)" % str(kinds_of(ents)))
	ok(joined, "3 JOINED the typed stretch starts and ends on its neighbours (0.01 mm)")
	ok(m.undo.size() == ub1 + 1, "4 UNDO the whole drag with a typed stretch is ONE undo step (%d -> %d)" % [ub1, m.undo.size()])
	ok(is_equal_approx(m.yaw, yaw0) and is_equal_approx(m.pitch, pitch0), "5 KEYS the typed digits do not turn the camera (yaw %.2f -> %.2f, pitch %.2f -> %.2f)" % [yaw0, m.yaw, pitch0, m.pitch])
	ok(said1.begins_with("Stretch of 40 mm drawn"), "6 WORDS the say line says Stretch of 40 mm drawn (%s)" % said1)
	var all_line := ents.size() >= 2
	for k in kinds_of(ents):
		all_line = all_line and k == "line"
	ok(all_line, "7 KINDS the drag is straight lines only (kinds %s)" % str(kinds_of(ents)))

	# ---- EASY: "0" says above 0 and adds nothing; Backspace takes a digit back; "45", Backspace, "2" makes 42
	var c2 := free_at(0.2, 0.62)
	await click_ctl(ep.make_btns["draw"])   # a finished line disarms Draw: the second drag is armed again, as a beginner presses it
	await click_ctl(ep.shape_btns["line"])
	await ev_move(c2, false)
	await ev_mouse(c2, true)
	await walk(c2, c2 + Vector2(120, 0))
	await type_chars("0")
	await key(KEY_ENTER)
	await idle(2)
	var said0 := String(ep.msg)
	ok(said0.find("above 0") >= 0, "8 ZERO typing 0 and Enter says above 0 (%s)" % said0)
	await key(KEY_BACKSPACE)
	await type_chars("45")
	await key(KEY_BACKSPACE)
	await type_chars("2")
	await key(KEY_ENTER)
	await idle(2)
	await walk(c2 + Vector2(120, 0), c2 + Vector2(120, 60))
	await ev_mouse(c2 + Vector2(120, 60), false)
	await idle(3)
	var ents2: Array = newest_sketch().get("ents", [])
	var shortest := 1e9
	for e in ents2:
		if String(e.get("k", "")) == "line":
			shortest = minf(shortest, e_a(e).distance_to(e_b(e)))
	ok(ents2.size() >= 1 and shortest >= 1.0, "9 NO ZERO no zero-length piece was drawn (shortest %.2f mm)" % shortest)
	ok(find_len(ents2, 42.0) >= 0, "10 BACK Backspace takes a digit back: 45, Backspace, 2, Enter makes a 42.00 mm stretch (line lengths %s)" % lens_of(ents2))
	await shot("typed_easy_42")

	# ---- EXPERT: the Line tool, a click, then 40 + Enter from the click along the pointer
	pu.set_on(false)
	pu.m.S.part = {}
	pu.easy = false
	await process_frame
	await click_ctl(pu.part_btn)
	await idle(3)
	ok(pu.on and pu.tool_btns.has("Line"), "start: Expert Part tools on")
	await press_tool(pu, "Line")
	var a_scr := sp("front", 0, 0)
	await click_at(a_scr)
	await ev_move(sp("front", 30, 20), false)
	await type_chars("40")
	await key(KEY_ENTER)
	await idle(2)
	var xl := {}
	for e in sk_ents():
		if String(e["k"]) == "line" and absf(e_a(e).distance_to(e_b(e)) - 40.0) < LEN_TOL:
			xl = e
	ok(not xl.is_empty(), "11 EXPERT-A the Line tool: a click, then 40 + Enter, makes a 40.00 mm line (%d shapes)" % sk_ents().size())
	if not xl.is_empty():
		var dir := (e_b(xl) - e_a(xl)).normalized()
		var want := Vector2(30, 20).normalized()
		var cosv := dir.dot(want)
		ok(cosv >= 0.9999, "12 EXPERT-DIR the line runs along the pointer (cosine %.6f)" % cosv)
		ok(e_a(xl).distance_to(Vector2.ZERO) <= LEN_TOL, "13 EXPERT-AT the line starts at the click (%.3f, %.3f mm)" % [e_a(xl).x, e_a(xl).y])
	await shot("typed_expert_40")

	print("p045typelength: %d fail" % fails)
	m.queue_free()
	quit(1 if fails > 0 else 0)
