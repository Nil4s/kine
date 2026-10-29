extends SceneTree
## FWRENCH (Nick 2026-10-28: free 3D building, anything, nothing forced; a simple wrench): a beginner who never read a manual
## builds a wrench from the BUILDING card (blank Easy Part). Real clicks at 1280x720 from the real start screen.
## Walk: Draw shape (Box) + drag = the bar -> Pull it up -> Round the edges -> Draw shape (Round) + drag at one end = the ring
##   -> Pull it up -> Cut a hole (the ring's hole) -> Stick together: Join bar + ring -> Draw shape (Box) + drag at the other end = the jaw slot
##   -> Pull it up -> Stick together: bar, then slot, Cut away (the open jaw).
## Bars:
##   0 the BUILDING card, one click: page BUILD, Easy Part on, empty part
##   1 the bar: Draw shape + drag + Pull it up makes one body; Round the edges keeps one body, volume goes down
##   2 the ring: Round chip + drag at the far end + Pull it up: a second body; Cut a hole: volume goes down
##   3 Join bar and ring: ONE solid
##   4 the jaw: a Box at the open end, Pulled up, CUTS the bar (volume down, one solid)
##   5 the words: every press says a line (no empty sentence)
## shots: C:/Temp/claude/fwrench/
const SHOT := "C:/Temp/claude/fwrench"
const DIRT := "user://fwrench_test"

var fails := 0
var m: Node
var words: Array = []


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


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu():
	return m.bld.part


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func body_box(faces: Array, i: int) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for w in faces[i]:
		var q: Vector2 = m.cam.unproject_position(w)
		lo = lo.min(q)
		hi = hi.max(q)
	return Rect2(lo, hi - lo)


## a point on body i that the ray hits on body i (not over the Easy panel)
func inside_pt(faces: Array, i: int) -> Vector2:
	var ep = pu().ep
	var r := body_box(faces, i)
	for f in [Vector2(0.5, 0.5), Vector2(0.35, 0.5), Vector2(0.65, 0.5), Vector2(0.5, 0.35), Vector2(0.5, 0.65), Vector2(0.3, 0.3), Vector2(0.7, 0.7)]:
		var p: Vector2 = r.position + r.size * f
		var hit: Dictionary = pu()._ray_hit(p, faces)
		if not hit.is_empty() and int(hit["body"]) == i and not ep._over_ui(p):
			return p
	return Vector2(-1, -1)


func note(press: String) -> void:
	words.append([press, pu().ep.msg])


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
	ok(m.cur_page == "BUILD" and pu().on and pu().easy and int(pu().res.get("bodies", 0)) == 0,
		"0 BUILDING card, one click -> Easy Part on, empty (page %s)" % m.cur_page)

	# 1 the bar: Draw shape (Box), a drag along x, Pull it up, Round the edges
	var ep = pu().ep
	await click_ctl(ep.make_btns["draw"])
	await drag_screen(scr(Vector3(-0.10, 0.0, -0.015)), scr(Vector3(0.10, 0.0, 0.015)))
	note("draw bar")
	await click_ctl(ep.make_btns["pull"])
	note("pull bar")
	var b1 := int(pu().res.get("bodies", 0))
	var v1: float = float(pu().res.get("volume", 0.0))
	ok(b1 == 1 and v1 > 0.0, "1a Draw shape + drag + Pull it up: one body (bodies %d) [%s]" % [b1, ep.msg])
	await click_ctl(ep.make_btns["round"])
	note("round bar")
	var v1r: float = float(pu().res.get("volume", 0.0))
	ok(int(pu().res.get("bodies", 0)) == 1 and v1r < v1 - 1e-9, "1b Round the edges: one body, volume down (%.2f -> %.2f cm3) [%s]" % [v1 * 1e6, v1r * 1e6, ep.msg])
	await shot("01_bar")

	# 2 the ring: Round chip, a drag at the +x end (its left side on the bar's end), Pull it up, Cut a hole
	await click_ctl(ep.make_btns["draw"])
	ok(ep.shape_btns.has("round") and (ep.shape_btns["round"] as Control).is_visible_in_tree(), "2a the Round chip is on screen after Draw shape")
	await click_ctl(ep.shape_btns["round"])
	await drag_screen(scr(Vector3(0.09, 0.0, -0.04)), scr(Vector3(0.17, 0.0, 0.04)))
	await click_ctl(ep.make_btns["pull"])
	note("pull ring")
	var v2: float = float(pu().res.get("volume", 0.0))
	var pull_words: String = ep.msg
	ok(int(pu().res.get("bodies", 0)) == 1 and v2 > v1r + 1e-9, "2b the ring joins the bar at its end: one solid, more volume (%.2f -> %.2f cm3) [%s]" % [v1r * 1e6, v2 * 1e6, pull_words])
	ok(pull_words.to_lower().find("face") < 0, "2w the words after the ring say no \"face\" (a beginner does not know the word) [%s]" % pull_words)
	await click_ctl(ep.make_btns["hole"])
	note("hole ring")
	var v2h: float = float(pu().res.get("volume", 0.0))
	ok(v2h < v2 - 1e-9, "2c Cut a hole: the volume goes down (%.2f -> %.2f cm3) [%s]" % [v2 * 1e6, v2h * 1e6, ep.msg])
	await shot("02_ring")

	# 3 Stick together with ONE solid: the words say how to get two pieces (draw a second shape apart, Pull it up)
	await click_ctl(ep.make_btns["stick"])
	var sw: String = ep.msg
	ok(sw.to_lower().find("apart") >= 0 and sw.to_lower().find("draw") >= 0, "3 Stick together with one solid says how to get two pieces [%s]" % sw)
	if ep.armed == "stick":
		await click_ctl(ep.make_btns["stick"])

	# 4 the jaw: a Box at the -x end (its right side in the bar), Pulled up: the jaw must CUT the bar (volume down, one solid)
	var v3: float = float(pu().res.get("volume", 0.0))
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_screen(scr(Vector3(-0.14, 0.0, -0.006)), scr(Vector3(-0.06, 0.0, 0.006)))
	await click_ctl(ep.make_btns["pull"])
	note("pull jaw")
	var v4: float = float(pu().res.get("volume", 0.0))
	var cut_ok := int(pu().res.get("bodies", 0)) == 1 and v4 < v3 - 1e-9
	var jmsg := "a slot at the open end CUTS the jaw: one solid, volume down (%.2f -> %.2f cm3) [%s]" % [v3 * 1e6, v4 * 1e6, ep.msg]
	ok(cut_ok, "4 " + jmsg)
	await shot("04_jaw_slot")

	# 5 the words: no press leaves an empty sentence
	var empty := []
	for w in words:
		if String(w[1]).strip_edges() == "":
			empty.append(String(w[0]))
	ok(empty.is_empty(), "5 every press says a line (empty after: %s) %s" % [str(empty), str(words)])
	await shot("06_done")

	print("fwrench: %d fail" % fails)
	quit(1 if fails > 0 else 0)
