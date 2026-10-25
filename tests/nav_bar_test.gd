## godot --path . -s tests/nav_bar_test.gd     (GATES HH2, UPGRADES #23; a real window, real clicks and drags)
## A NAVIGATION BAR: combo3 open (a bat out). The bar (round 36, RR4/RR5: one row of icons at the status line's
## right end; it was a block under the ViewCube), covering no body part, clear of the
## cube, the line's messages and its readout: normal, big view, the empty scene, a 1280 x 720 window. Orbit by a real click, then a real left drag that STARTS ON A
## PART: the view turns, the part is not picked or turned; Esc = off, and a press on a part picks it again. Pan: a real
## drag slides the view (the angle kept); Pan again = off. + and -: zoom in and out. Fit, after zooming far out and
## panning away: every point of the body and the bat inside the clear view (between the ribbon and the bar, between
## the panels), filling at least 60% of it one way; again in the big view. Grid: hidden, shown. No undo steps at all.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func btn(down: bool, p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await idle()


func move(p: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await idle()


func click(name: String) -> void:
	var c: Control = m.ui_nav.get_node(name)
	var p := c.get_global_rect().get_center()
	await btn(true, p)
	await btn(false, p)


func drag(from: Vector2, step: Vector2, n := 5) -> void:
	var p := from
	await btn(true, p)
	for i in n:
		p += step
		await move(p, step)
	await btn(false, p)


func key(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle()


func spot(j: String) -> Vector2:
	var c: Array = m.B.cap(j)
	return m.cam.unproject_position((c[0] + c[1]) * 0.5)


## [all inside the clear view, the larger of (body height / clear height, body width / clear width)]
func framed() -> Array:
	var clear: Rect2 = m.nav_clear_rect()
	var r := Rect2(m.cam.unproject_position(m.fit_points()[0]), Vector2.ZERO)
	var inside := true
	for q in m.fit_points():
		var s: Vector2 = m.cam.unproject_position(q)
		r = r.expand(s)
		if not clear.has_point(s) or m.cam.is_position_behind(q):
			inside = false
	return [inside, maxf(r.size.y / clear.size.y, r.size.x / clear.size.x)]


## [inside the view, under the cube at the view's right edge, clear of the cube, the say-line and the status bar, and
## covering no point of the body (each part's two ends and middle) as it is shown now; the rect]
func placed() -> Array:
	var nr: Rect2 = m.ui_nav.get_global_rect()
	var vs := root.get_visible_rect().size
	var x0 := 0.0 if m.big_view else float(m.LEFT_W)
	var x1 := vs.x   # round 36: the inspector is a box at the top right; the view runs to the window's edge below it
	var view := Rect2(x0, m.TOP_H, x1 - x0, vs.y - m.bottom_h - m.TOP_H)
	var cube: Rect2 = m.ui_cube.get_global_rect()
	# round 36: in the status line's band (just above the scene panel), at its right end
	var under: bool = vs.x - nr.end.x < 16.0 and nr.end.y <= vs.y - m.bottom_h and nr.position.y >= vs.y - m.bottom_h - 6 - m.LINE_H - 1
	var clear_of: bool = not nr.intersects(cube) and not nr.intersects(m.ui_status.get_global_rect()) and not nr.intersects(m.ui_bar.get_global_rect())
	var covers := []
	for jn in Body.BODY:
		var c: Array = m.B.cap(jn)
		for q in [c[0], c[1], (c[0] + c[1]) * 0.5]:
			if nr.grow(6.0).has_point(m.cam.unproject_position(q)):
				covers.append(jn)
				break
	return [m.ui_nav.is_visible_in_tree() and view.encloses(nr) and under and clear_of and covers.is_empty(), nr, covers]


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m._layout_bottom()
	m.sel = "head"
	m._refresh()
	await idle(3)
	var u0: int = m.undo.size()
	var pl := placed()
	m._big_view()
	await idle(3)
	var pb := placed()
	m._big_view()
	await idle(3)
	m._new_scene()   # the opening state: the empty scene (the smaller bottom panel), the opening view
	m._layout_bottom()
	m._refresh()
	await idle(3)
	var pe := placed()
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m._layout_bottom()   # the full bottom panel: the least room above it
	m.sel = "head"
	m._refresh()
	m.get_window().size = Vector2i(1280, 720)   # the smallest window the poser allows
	await idle(6)
	var ps := placed()
	m.get_window().size = Vector2i(1600, 900)
	await idle(6)
	ok(pl[0] and pb[0] and pe[0] and ps[0], "1 the bar on the status line's right end, inside the view, clear of the cube, the line's texts and every body part: combo3 %s %s %s; big view %s %s; the empty scene %s %s; combo3 at 1280 x 720 %s %s %s" % [pl[0], pl[1], pl[2], pb[0], pb[2], pe[0], pe[2], ps[0], ps[1], ps[2]])
	# Orbit
	await click("nav_orbit")
	var ang0: Dictionary = m.B.ang.duplicate()
	var y0: float = m.yaw
	var on: bool = m.nav_tool == "orbit" and (m.ui_nav.get_node("nav_orbit") as Button).button_pressed
	await drag(spot("upperarm_l"), Vector2(14, 0))
	ok(on and absf(m.yaw - y0) > 10.0 and m.sel == "head" and m.B.ang == ang0, "2 Orbit on (%s); a real drag starting on the left upper arm: the view turned %.0f deg, nothing picked (%s) or turned" % [on, m.yaw - y0, m.sel])
	await key(KEY_ESCAPE)
	var off: bool = m.nav_tool == "" and not (m.ui_nav.get_node("nav_orbit") as Button).button_pressed
	var arm := spot("upperarm_l")
	var u_pick: int = m.undo.size()
	await btn(true, arm)
	await btn(false, arm)
	u0 += m.undo.size() - u_pick   # a press on a part is a posing grab (its own step), not the bar's
	ok(off and m.sel == "upperarm_l", "3 Esc: Orbit off (%s); a press on the left upper arm picks it again (%s)" % [off, m.sel])
	# Pan
	await click("nav_pan")
	var t0: Vector3 = m.target
	var y1: float = m.yaw
	await drag(spot("pelvis"), Vector2(0, 12))
	var panned: float = (m.target - t0).length()
	await click("nav_pan")
	ok(panned > 0.05 and m.yaw == y1 and m.sel == "upperarm_l" and m.nav_tool == "", "4 Pan: a real drag slid the view %.2f m, the angle kept; Pan again: off ('%s')" % [panned, m.nav_tool])
	# zoom
	var d0: float = m.dist
	await click("nav_in")
	var d_in: float = m.dist
	await click("nav_out")
	ok(d_in < d0 * 0.85 and absf(m.dist - d0) < 1e-3, "5 + : %.2f -> %.2f m; - : back to %.2f" % [d0, d_in, m.dist])
	# Fit, from far and off to one side
	m.dist = 11.0
	m.target += Vector3(1.5, 0.8, 0)
	m._cam()
	var before := framed()
	await click("nav_fit")
	var f := framed()
	ok(f[0] and f[1] >= 0.6 and f[1] <= 1.0, "6 Fit from far away and off to the side (fill %.2f): body and bat all inside the clear view %s, filling %.2f of it" % [before[1], f[0], f[1]])
	m._big_view()
	await idle(3)
	await click("nav_fit")
	var fb := framed()
	m._big_view()
	await idle(3)
	ok(fb[0] and fb[1] >= 0.6, "7 Fit in the big view: all inside %s, filling %.2f" % [fb[0], fb[1]])
	# Grid
	await click("nav_grid")
	var hid: bool = not m.grid_node.visible and not (m.ui_nav.get_node("nav_grid") as Button).button_pressed
	await click("nav_grid")
	ok(hid and m.grid_node.visible and (m.ui_nav.get_node("nav_grid") as Button).button_pressed, "8 Grid: hidden (%s), then shown again (%s)" % [hid, m.grid_node.visible])
	ok(m.undo.size() == u0, "9 no undo steps from any of it (+%d)" % (m.undo.size() - u0))
	print("NAV BAR: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
