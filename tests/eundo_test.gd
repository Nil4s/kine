extends SceneTree
## godot --path . --position 4000,4000 -s tests/eundo_test.gd     (EASY PART, EUNDO: every MAKE button and every chip pressed once, with real clicks; needs the CAD DLL)
## Bars (from Easy home: a 3D BUILDING project, Part, Easy; mouse only; 1280 x 720):
##   1 EACH PRESS  a press that changes the part is exactly ONE undo step (the undo count rises by 1, the part changes); an arming press
##                 (Draw shape, Curvy line, Colour, Stick together) takes no step
##   2 UNDO ALL    Undo once per step: after each one the part is identical (features, volume, bodies) to the part before that press
##   3 REDO ALL    Redo once per step: after each one the part is identical to the part after that press
## Shots: C:/Temp/claude/eundo/shot_end.png
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/eundo"
const DIRT := "user://eundo_test"
var steps := []     # {name, pre, post, pre_vol, post_vol, pre_bodies, post_bodies} for each press that made one undo step


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


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


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


## a drag on the grid that makes a shape (one undo step): recorded like a press
func press_drag(nm: String, pts: Array) -> void:
	var pre := JSON.stringify(rec())
	var pre_n: int = m.undo.size()
	var pv := vol()
	var pb := bodies()
	await drag_pts(pts)
	var dn: int = m.undo.size() - pre_n
	var post := JSON.stringify(rec())
	var changed := post != pre
	ok(dn == 1 and changed, "drag %s: ONE undo step (%d -> %d), the part changed (%s)" % [nm, pre_n, m.undo.size(), "yes" if changed else "NO"])
	if dn == 1 and changed:
		steps.append({"name": nm, "pre": pre, "post": post, "pre_vol": pv, "post_vol": vol(), "pre_bodies": pb, "post_bodies": bodies()})


## a press the app refuses on purpose: no undo step, and the sentence says why (it must contain `why` when that is not "")
func press_refused(nm: String, c: Control, why: String) -> void:
	var pre_n: int = m.undo.size()
	await click_ctl(c)
	var dn: int = m.undo.size() - pre_n
	var said := String(m.bld.part.ep.msg)
	ok(dn == 0 and (why == "" or said.contains(why)), "press %s: refused, no undo step (%d -> %d), says: %s" % [nm, pre_n, m.undo.size(), said])


func rec() -> Dictionary:
	return m.S.part


func vol() -> float:
	return float(m.bld.part.res.get("volume", 0.0))


func bodies() -> int:
	return int(m.bld.part.res.get("bodies", 0))


## one press (a real click). is_step: the press must change the part and take exactly one undo step; else it must take none
func press(nm: String, c: Control, is_step: bool) -> void:
	var pre := JSON.stringify(rec())
	var pre_n: int = m.undo.size()
	var pv := vol()
	var pb := bodies()
	await click_ctl(c)
	var dn: int = m.undo.size() - pre_n
	var post := JSON.stringify(rec())
	if is_step:
		var changed := post != pre
		ok(dn == 1 and changed, "press %s: ONE undo step (%d -> %d), the part changed (%s)" % [nm, pre_n, m.undo.size(), "yes" if changed else "NO"])
		if dn == 1 and changed:
			steps.append({"name": nm, "pre": pre, "post": post, "pre_vol": pv, "post_vol": vol(), "pre_bodies": pb, "post_bodies": bodies()})
	else:
		ok(dn == 0, "press %s (arms): no undo step (%d -> %d)" % [nm, pre_n, m.undo.size()])
	if is_step and dn == 0:
		print("     said: " + String(m.bld.part.ep.msg))


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
		print("FAIL: no KineCAD DLL, the MAKE buttons cannot run")
		quit(1)
		return
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep
	var ub0: int = m.undo.size()
	var start_rec := JSON.stringify(rec())
	# every template chip (the one on the grid at the start goes last: pressing it changes nothing), then Empty
	var first_t: String = ep._tpl()
	var order := []
	for t in PartTemplates.ORDER:
		if t != first_t:
			order.append(t)
	order.append(first_t)
	for t in order:
		await press("chip " + t, ep.chips[t], true)
	await press("chip Empty", ep.empty_chip, true)
	# the MAKE buttons, in an order that gives each one the shape it needs
	await press("Draw shape (arm)", ep.make_btns["draw"], false)
	var a0 := free_at(0.12, 0.2)
	await press_drag("Draw shape A", [a0, a0 + Vector2(45, 35), a0 + Vector2(90, 70)])
	await press("Pull it up", ep.make_btns["pull"], true)
	await press("Draw shape (arm)", ep.make_btns["draw"], false)
	var b0 := free_at(0.12, 0.45)
	await press_drag("Draw shape B", [b0, b0 + Vector2(30, 30), b0 + Vector2(60, 60)])
	print("     profile before spin: " + JSON.stringify(Part.feature(rec(), Part.profile_sketch(rec()))).left(600))
	await press("Spin it round", ep.make_btns["spin"], true)
	await press("Round the edges", ep.make_btns["round"], true)
	await press("Cut a hole", ep.make_btns["hole"], true)
	# Hollow inside: this body is too thin for its 3 mm wall, so the chip is refused by design (no step, the sentence says why)
	await press_refused("chip Hollow inside (too thin here)", ep.hole_btns["hollow"], "too thin")
	await press_refused("chip Through (already on)", ep.hole_btns["through"], "")
	await press("Mirror that", ep.make_btns["mirror"], true)
	await press("Curvy line (arm)", ep.make_btns["curve"], false)
	var c0 := free_at(0.3, 0.6)
	var loop := []
	for i in 25:
		var a := TAU * float(i) / 24.0
		loop.append(c0 + Vector2(cos(a), sin(a)) * 50.0)
	loop[24] = loop[0]
	await press_drag("Curvy line", loop)
	await press("Pull it up (curve)", ep.make_btns["pull"], true)
	await press("Draw shape (arm)", ep.make_btns["draw"], false)
	var c1 := free_at(0.1, 0.25)
	await press_drag("Draw shape C", [c1, c1 + Vector2(40, 30), c1 + Vector2(80, 60)])
	await press("Draw shape (arm)", ep.make_btns["draw"], false)
	var d1 := free_at(0.1, 0.5)
	await press_drag("Draw shape D", [d1, d1 + Vector2(40, 30), d1 + Vector2(80, 60)])
	await press("Blend two shapes", ep.make_btns["blend"], true)
	await press("Cut in two", ep.make_btns["split"], true)
	await press("Colour (arm)", ep.make_btns["colour"], false)
	var colour_btns: Array = ep.colour_box.find_children("easypart_colour_*", "Button", true, false)
	for b in colour_btns:
		await press("colour " + String(b.name), b, true)
		await press("Colour (arm)", ep.make_btns["colour"], false)
	await press("Repeat it", ep.make_btns["repeat"], true)
	await press("Stick together (arm)", ep.make_btns["stick"], false)
	# two solid pieces, picked by real clicks on the body under the pointer
	var faces: Array = Part.body_faces(rec(), -1)
	var picks := []
	var cl: Rect2 = m.nav_clear_rect()
	for fy in [0.15, 0.25, 0.35, 0.45, 0.55, 0.65, 0.75, 0.85]:
		for fx in [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]:
			if picks.size() >= 2:
				break
			var p := Vector2(cl.position.x + cl.size.x * fx, cl.position.y + cl.size.y * fy)
			if ep._over_ui(p):
				continue
			var hit: Dictionary = pu._ray_hit(p, faces)   # the same pick as the app's click: the body under the pointer, else one within 12 px
			var bi := int(hit["body"]) if not hit.is_empty() else ep._near_body(p, faces)
			if bi >= 0 and not picks.has(bi):
				picks.append(bi)
				await click_at(p)
	ok(picks.size() == 2, "stick: two solid pieces picked by real clicks (%s)" % str(picks))
	await press("Join (stick)", ep.stick_btns["join"], true)
	await shot("shot_end")
	# UNDO ALL, by the Undo button: each undo gives back the part from before that step
	var n_steps := steps.size()
	for i in n_steps:
		var s: Dictionary = steps[n_steps - 1 - i]
		await click_ctl(ep.undo_btn)
		var same: bool = JSON.stringify(rec()) == String(s["pre"])
		if not same:
			var got := JSON.stringify(rec())
			var at := 0
			while at < got.length() and at < String(s["pre"]).length() and got[at] == String(s["pre"])[at]:
				at += 1
			print("     differ at char %d of %d/%d: got ...%s ... wanted ...%s ..." % [at, got.length(), String(s["pre"]).length(), got.substr(maxi(0, at - 60), 120), String(s["pre"]).substr(maxi(0, at - 60), 120)])
		print("     undo depth now %d, redo %d" % [m.undo.size(), m.redo.size()])
		ok(same and absf(vol() - float(s["pre_vol"])) < 1e-9 and bodies() == int(s["pre_bodies"]),
			"undo %s: the part is identical to the one before it (%.3f cm3, %d bodies)" % [s["name"], vol() * 1e6, bodies()])
	ok(m.undo.size() == ub0 and JSON.stringify(rec()) == start_rec, "undo all: back to the start part (undo %d -> %d)" % [ub0, m.undo.size()])
	# REDO ALL
	for i in n_steps:
		var s2: Dictionary = steps[i]
		await click_ctl(ep.redo_btn)
		ok(JSON.stringify(rec()) == String(s2["post"]) and absf(vol() - float(s2["post_vol"])) < 1e-9 and bodies() == int(s2["post_bodies"]),
			"redo %s: the part is identical to the one after it" % s2["name"])
	print("eundo: %d steps, %d fail" % [n_steps, fails])
	quit(1 if fails > 0 else 0)
