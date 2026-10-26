## godot --path . -s tests/mousehint_test.gd     (ROADMAP_400 P05; needs a window, real InputEvents)
## The mouse-button hint strip above the status line. Bars, stated before the run:
##   1 CONTEXTS: at least 8 contexts, each one's hint names a binding and the real input does what the hint says:
##       pose_part  "Left: drag to turn the <part>"        -> a real left drag on it changes that part's angles
##       drag_joint "Esc: cancel the drag"                  -> during the drag the strip says so; Esc restores the angles
##       pose_empty "Left: nothing here ... Right: orbit ... Wheel: zoom" -> left drag changes nothing (pose, undo count);
##                  a right drag turns the view; the wheel changes the distance
##       drag_orbit while the right button is down
##       nav_orbit  "Left: drag to orbit the view"          -> a left drag ON A PART turns the view, not the part
##       weight     "Left: drag over the body to paint"     -> a left press on the body starts a stroke; weight_nobone: it does not
##       kmesh / kmesh_box  click selects an element; B then a left drag selects a box
##       tl_ruler   "Left: click or drag to scrub"          -> a left press on the ruler moves the playhead
##       tl_hold    "Left: drag to change this card's hold" -> a left drag on the hold edge changes the card's hold
##       cards      "Left: show the card"                   -> a left click on a card's picture picks it
##       loa        "Left: drag a line of action"           -> a left press starts the stroke
##   2 FIT: for every context at 1600 x 900 and at 1280 x 720 the items' minimum width <= the strip's width (no clipping)
##   3 PLACEMENT: the strip is visible, inside the 1600 x 900 window, between the view's left edge and the nav bar, right
##       above the line's texts, and intersects none of: the say line, the readout, the nav bar, the ViewCube
##   4 THROTTLE: a tick shorter than 50 ms since the last look does not re-read the mouse; the one that reaches 50 ms does
## Screenshot: C:/Users/Nick/.claude/jobs/9afc22db/tmp/mousehint.png
extends SceneTree

const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/mousehint.png"
const KEY := "mousehint_test"
var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func btn(b: int, down: bool, p: Vector2, ctrl := false, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = b
	e.pressed = down
	e.position = p
	e.global_position = p
	e.ctrl_pressed = ctrl
	e.shift_pressed = shift
	if down:
		e.button_mask = {MOUSE_BUTTON_LEFT: MOUSE_BUTTON_MASK_LEFT, MOUSE_BUTTON_RIGHT: MOUSE_BUTTON_MASK_RIGHT}.get(b, 0)
	root.push_input(e)
	await idle()


func move(p: Vector2, rel: Vector2, mask: int) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = rel
	e.button_mask = mask
	root.push_input(e)
	await idle()


func drag(b: int, from: Vector2, step: Vector2, n := 5, release := true) -> Vector2:
	var mask: int = {MOUSE_BUTTON_LEFT: MOUSE_BUTTON_MASK_LEFT, MOUSE_BUTTON_RIGHT: MOUSE_BUTTON_MASK_RIGHT}[b]
	var p := from
	await btn(b, true, p)
	for i in n:
		p += step
		await move(p, step, mask)
	if release:
		await btn(b, false, p)
	return p


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


## the strip's context for the mouse at p over the 3D view (over = null), read after the strip has been refreshed
func ctx_at(p: Vector2, over: Control = null) -> String:
	m.ui_mouse.refresh(over, p)
	return m.ui_mouse.ctx


func said() -> String:
	return m.ui_mouse.shown_text()


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
	await idle(4)
	var strip: MouseHint = m.ui_mouse
	ok(strip != null and strip.get_parent() == m.ui_root, "the strip exists in the UI root")

	# ---- 1 CONTEXTS
	var forearm := "lowerarm_l"
	var p := spot(forearm)
	ok(m._pick(p) == forearm, "the left forearm is under %s" % p)
	var c := ctx_at(p)
	ok(c == "pose_part" and said().contains("Left: drag to turn the %s" % m.nice(forearm)) and said().contains("Right: orbit") and said().contains("Wheel: zoom"),
		"1 pose_part: '%s'" % said())
	var a0: Vector3 = m.B.ang[forearm]
	var u0: int = m.undo.size()
	var q := await drag(MOUSE_BUTTON_LEFT, p, Vector2(6, -6), 5, false)
	await idle(2)
	var a1: Vector3 = m.B.ang[forearm]
	ok(m.dragging == "joint" and ctx_at(q) == "drag_joint" and said().contains("Esc: cancel the drag"), "2 drag_joint while the left button is down: '%s'" % said())
	ok(a1.distance_to(a0) > 1.0, "  the left drag turned the forearm: %s -> %s (bar: > 1 degree)" % [a0, a1])
	await key(KEY_ESCAPE)
	ok(m.dragging == "" and (m.B.ang[forearm] as Vector3).distance_to(a0) < 0.01 and m.undo.size() == u0, "  Esc cancelled it: angles back (%s), no undo step left (%d vs %d)" % [m.B.ang[forearm], m.undo.size(), u0])
	await btn(MOUSE_BUTTON_LEFT, false, q)
	await idle()

	# an empty spot of the view: far left-bottom corner of the clear view, nothing of the body there
	var e := Vector2(m.LEFT_W + 40, m.TOP_H + 60)
	ok(m._pick(e) == "", "an empty spot of the stage is under %s" % e)
	ok(ctx_at(e) == "pose_empty" and said().contains("Left: nothing here") and said().contains("Right: orbit") and said().contains("Wheel: zoom"), "3 pose_empty: '%s'" % said())
	var state0: Dictionary = m.B.state()
	var u1: int = m.undo.size()
	var sel0: String = m.sel
	await drag(MOUSE_BUTTON_LEFT, e, Vector2(8, 5), 4)
	ok(JSON.stringify(m.B.state()) == JSON.stringify(state0) and m.undo.size() == u1 and m.sel == sel0, "  a left drag on empty stage changes nothing (pose, undo steps, pick)")
	var yaw0: float = m.yaw
	var pit0: float = m.pitch
	await btn(MOUSE_BUTTON_RIGHT, true, e)
	ok(m.dragging == "orbit" and ctx_at(e) == "drag_orbit", "4 drag_orbit while the right button is down: '%s'" % said())
	var mask_r := MOUSE_BUTTON_MASK_RIGHT
	for i in 4:
		await move(e + Vector2(10 * (i + 1), 4 * (i + 1)), Vector2(10, 4), mask_r)
	await btn(MOUSE_BUTTON_RIGHT, false, e + Vector2(40, 16))
	ok(absf(m.yaw - yaw0) > 5.0 or absf(m.pitch - pit0) > 1.0, "  Right drag orbits: yaw %.1f -> %.1f, pitch %.1f -> %.1f" % [yaw0, m.yaw, pit0, m.pitch])
	var d0: float = m.dist
	var w := InputEventMouseButton.new()
	w.button_index = MOUSE_BUTTON_WHEEL_UP
	w.pressed = true
	w.position = e
	w.global_position = e
	root.push_input(w)
	await idle()
	ok(m.dist < d0 - 0.01, "  Wheel zooms: distance %.2f -> %.2f" % [d0, m.dist])

	# the navigation bar's Orbit tool: a left drag ON A PART turns the view, not the part
	m._nav_set("orbit")
	await idle(2)
	p = spot(forearm)
	ok(ctx_at(p) == "nav_orbit" and said().contains("Left: drag to orbit the view"), "5 nav_orbit: '%s'" % said())
	yaw0 = m.yaw
	a0 = m.B.ang[forearm]
	await drag(MOUSE_BUTTON_LEFT, p, Vector2(8, 0), 5)
	ok(absf(m.yaw - yaw0) > 5.0 and (m.B.ang[forearm] as Vector3).distance_to(a0) < 0.01, "  the left drag turned the view (%.1f -> %.1f) and not the part" % [yaw0, m.yaw])
	m._nav_set("")
	await idle(2)

	# line of action armed
	m.loa.armed = true
	ctx_at(e)
	ok(m.ui_mouse.ctx == "loa" and said().contains("Left: drag a line of action"), "6 loa: '%s'" % said())
	await btn(MOUSE_BUTTON_LEFT, true, p)
	ok(m.dragging == "loa" and ctx_at(p) == "drag_loa", "  a left press starts the stroke (dragging = %s): '%s'" % [m.dragging, said()])
	await btn(MOUSE_BUTTON_LEFT, false, p)
	m.loa.armed = false
	m.dragging = ""

	# the timeline: ruler, and a hold edge
	var tl: Control = m.ui_timeline
	await idle(2)
	var tg: Vector2 = tl.get_global_rect().position
	var pr := Vector2(tl.x_of(1.0), Timeline.RULER * 0.5)
	ok(ctx_at(tg + pr, tl) == "tl_ruler" and said().contains("Left: click or drag to scrub"), "7 tl_ruler: '%s'" % said())
	var t0: float = m.playhead
	var pe := InputEventMouseButton.new()
	pe.button_index = MOUSE_BUTTON_LEFT
	pe.pressed = true
	pe.position = pr
	tl._gui_input(pe)
	await idle(2)
	var pe2 := InputEventMouseButton.new()
	pe2.button_index = MOUSE_BUTTON_LEFT
	pe2.pressed = false
	pe2.position = pr
	tl._gui_input(pe2)
	ok(absf(m.playhead - 1.0) < 0.06 and absf(m.playhead - t0) > 0.01, "  a left press on the ruler scrubs: playhead %.2f -> %.2f (asked 1.00)" % [t0, m.playhead])
	var ts: Array = m.S.times()
	var ci := -1
	for i in range(1, ts.size()):
		if ts[i][2] - ts[i][1] > 0.05:
			ci = i
			break
	ok(ci > 0, "a card with a hold exists (card %d)" % (ci + 1))
	var xh: float = tl.x_of(ts[ci][2])
	var ph := Vector2(xh, Timeline.RULER + 12.0)
	ok((tl as Timeline).hit(ph).get("kind", "") == "hold", "the hold edge of card %d is under %s: %s" % [ci + 1, ph, (tl as Timeline).hit(ph)])
	ok(ctx_at(tg + ph, tl) == "tl_hold" and said().contains("Left: drag to change this card's hold"), "8 tl_hold: '%s'" % said())
	var hold0: float = m.S.cards[ci]["hold"]
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = ph
	tl._gui_input(ev)
	var mv := InputEventMouseMotion.new()
	mv.position = ph + Vector2(40, 0)
	tl._gui_input(mv)
	ok(ctx_at(tg + ph, tl) == "tl_drag", "  while the drag is held the strip says tl_drag: '%s'" % said())
	var ev2 := InputEventMouseButton.new()
	ev2.button_index = MOUSE_BUTTON_LEFT
	ev2.pressed = false
	ev2.position = ph + Vector2(40, 0)
	tl._gui_input(ev2)
	await idle(2)
	var hold1: float = m.S.cards[ci]["hold"]
	ok(absf(hold1 - hold0) > 0.02, "  the left drag changed card %d's hold: %.3f -> %.3f s" % [ci + 1, hold0, hold1])
	m._undo()
	await idle(2)

	# the cards strip: a real click on the first card's picture
	var cb: Control = m.ui_cards.get_node("card_1").find_child("b_pick", true, false)
	var cp: Vector2 = (cb as Control).get_global_rect().get_center()
	ok(ctx_at(cp, cb) == "cards" and said().contains("Left: show the card"), "9 cards: '%s'" % said())
	var pick0: int = m.sel_card
	var tgt := 2
	var cb3 := m.ui_cards.get_node("card_%d" % (tgt + 1)).find_child("b_pick", true, false) as Control
	var cp3 := cb3.get_global_rect().get_center()
	await btn(MOUSE_BUTTON_LEFT, true, cp3)
	await btn(MOUSE_BUTTON_LEFT, false, cp3)
	ok(m.sel_card == tgt, "  a left click on card %d's picture picks it (sel_card %d -> %d)" % [tgt + 1, pick0, m.sel_card])

	# weight paint
	m.wp_key = KEY
	m._wp_toggle()
	m.wp_bind = -1
	m.sel = "head"
	m._refresh()
	await idle(3)
	p = spot("upperarm_r")
	ok(ctx_at(p) == "weight_nobone" and said().contains("Left: pick a bone first"), "10 weight_nobone: '%s'" % said())
	await btn(MOUSE_BUTTON_LEFT, true, p)
	ok(not m.wp_stroke, "  a left press without a bone paints nothing")
	await btn(MOUSE_BUTTON_LEFT, false, p)
	m.wp_bind = m._wp_bind_of("lowerarm_r")
	m.wp_mode = "add"
	SkinPaint.refresh(m.wp)
	p = spot("lowerarm_r")
	ok(ctx_at(p) == "weight" and said().contains("Left: drag over the body to paint (add)"), "11 weight: '%s'" % said())
	await btn(MOUSE_BUTTON_LEFT, true, p)
	var painted: bool = m.wp_stroke and m.wp_centres.size() > 0
	await btn(MOUSE_BUTTON_LEFT, false, p)
	ok(painted, "  a left press on the body starts a stroke (dabs %d)" % m.wp_centres.size())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SkinPaint.path(KEY)))
	m._wp_toggle()
	m.wp_key = "mannequin"
	await idle(2)

	# the test cube
	m._kmesh_edit_start()
	await idle(3)
	var km: KMeshEditUI = m.kmed
	var wc: Vector3 = km.view.global_position
	m._turn_to(0.0, 0.0, 2.4, wc + Vector3(0, 0.12, 0), false)
	await idle(4)
	var cc: Vector2 = m.cam.unproject_position(wc + Vector3(0, 0, 0.3))
	ok(ctx_at(cc) == "kmesh" and said().contains("click an element to select"), "12 kmesh: '%s'" % said())
	await btn(MOUSE_BUTTON_LEFT, true, cc)
	await btn(MOUSE_BUTTON_LEFT, false, cc)
	var n1: int = km.sel.count()
	ok(n1 == 1, "  a left click on an element selected it (%d, expect 1)" % n1)
	await key(KEY_B)
	ok(ctx_at(cc) == "kmesh_box" and said().contains("drag a rectangle"), "13 kmesh_box: '%s'" % said())
	var ra: Vector2 = m.cam.unproject_position(wc + Vector3(-0.2, 0.2, 0.3))
	var rb: Vector2 = m.cam.unproject_position(wc + Vector3(0.2, -0.2, 0.3))
	await btn(MOUSE_BUTTON_LEFT, true, ra)
	ok(ctx_at(ra) == "kmesh_drag", "  mid-drag the strip says kmesh_drag: '%s'" % said())
	await move(rb, rb - ra, MOUSE_BUTTON_MASK_LEFT)
	await btn(MOUSE_BUTTON_LEFT, false, rb)
	ok(km.sel.count() > 4, "  the left drag box-selected %d vertices (bar: more than 4)" % km.sel.count())
	km.stop()
	await idle(3)

	# ---- 2 FIT, at 1600 x 900 and 1280 x 720
	var all := ["pose_part", "pose_tip", "pose_pelvis", "pose_weapon", "pose_locked", "pose_empty", "nav_orbit", "nav_pan", "loa", "weight", "weight_nobone", "kmesh", "kmesh_box", "kmesh_lasso",
		"kmesh_drag", "sketch", "drag_joint", "drag_orbit", "drag_pan", "drag_loa", "drag_other", "tl_ruler", "tl_block", "tl_move", "tl_hold", "tl_edge0", "tl_clip", "tl_warp", "tl_drag", "cards"]
	m.set_meta("mh_part", "lowerarm_l")
	for sz in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		m.get_window().size = sz
		await idle(4)
		m._layout_bottom()
		await idle(3)
		var bad := []
		for cx in all:
			strip.show_ctx(cx)
			await process_frame
			if not strip.fits() or strip.shown_text() == "" or strip.box.get_combined_minimum_size().x > strip.size.x + 0.5:
				bad.append("%s (%d > %d)" % [cx, strip.box.get_combined_minimum_size().x, strip.size.x])
		ok(bad.is_empty(), "2 fit at %s: %d contexts, strip %d px wide, none wider than it %s" % [sz, all.size(), strip.size.x, bad])
		m.set_meta("mh_part", "lowerarm_l")
	m.get_window().size = Vector2i(1600, 900)
	await idle(4)
	m._layout_bottom()
	await idle(3)

	# ---- 3 PLACEMENT (the whole window, 1600 x 900)
	strip.show_ctx("pose_part")
	await idle(2)
	var vr := Rect2(0, 0, 1600, 900)
	var sr: Rect2 = strip.get_global_rect()
	var nr: Rect2 = m.ui_nav.get_global_rect()
	var lines_top: float = minf(m.ui_status.get_global_rect().position.y, m.ui_bar.get_global_rect().position.y)
	ok(strip.is_visible_in_tree() and vr.encloses(sr), "3 the strip is visible and inside 1600 x 900: %s" % sr)
	ok(not sr.intersects(m.ui_status.get_global_rect()) and not sr.intersects(m.ui_bar.get_global_rect()) and not sr.intersects(nr) and not sr.intersects(m.ui_cube.get_global_rect()),
		"  it overlaps neither the say line, the readout, the nav bar nor the ViewCube")
	ok(sr.position.x >= m.lw() + 11 and sr.end.x <= nr.position.x and sr.end.y <= lines_top + 0.5 and lines_top - sr.end.y <= 6.0,
		"  it runs from the view's left edge to the nav bar, directly above the line's texts (gap %.1f px)" % (lines_top - sr.end.y))

	# ---- 4 THROTTLE: ctx is set to a marker; a tick only looks at the mouse (and replaces it) once 50 ms have gathered
	m.nav_tool = ""
	strip._t = 0.0
	strip.ctx = "x"
	strip._sig = ""
	strip.tick(0.02)
	strip.tick(0.02)
	var held := strip.ctx == "x"
	strip.tick(0.02)
	ok(held and strip.ctx != "x", "4 throttle: two 20 ms ticks do not look at the mouse, the third (60 ms) does (ctx '%s' -> '%s')" % ["x", strip.ctx])

	# ---- screenshot: a part under the mouse, whole body in view
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m._layout_bottom()
	m._view(1)
	m._cam()
	m.sel = "head"
	m._refresh()
	m._say("")
	await idle(8)
	p = spot("lowerarm_l")
	m.hover_part = "lowerarm_l"
	m._refresh()
	strip._t = -100.0   # the real mouse is nowhere: no tick may overwrite the hint
	strip.refresh(null, p)
	await idle(3)
	var img := root.get_texture().get_image()
	var shot := SHOT if DirAccess.dir_exists_absolute(SHOT.get_base_dir()) else "user://mousehint.png"   # off Nick's machine: the user dir
	img.save_png(shot)
	print("shot: %s  strip text: %s  rect %s" % [ProjectSettings.globalize_path(shot), strip.shown_text(), strip.get_global_rect()])
	print("MOUSEHINT %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
