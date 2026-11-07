## godot --path . -s tests/pie_test.gd     (ROADMAP_400 P04; needs a window: real InputEvents through the viewport)
## PIE MENU for brushes (optional, OFF by default): on the SCULPT page the pie hotkey (Q) opens a ring of the brushes
## centred on the mouse; a mouse RELEASE on wedge k picks brush k; a release in the dead middle cancels.
## Bars:
##   1 default: m.pie_on is false (the option is off until the user turns it on)
##   2 option OFF: Q opens no ring and the brush is unchanged
##   3 option ON: Q opens the ring (visible), titled for the sculpt brushes, N = 10 wedges in the brush order
##     [draw, clay strips, inflate, smooth, flatten, pinch, crease, grab, snake hook, mask]; its centre is within 1 px of the
##     mouse (the mouse is far from every edge, so no clamping applies)
##   4 for every k in 0..N-1: a synthetic release at ring.at + dir at angle k*360/N (clockwise from up), 70 px out, picks
##     brush k exactly (the brush is set to a sentinel before each), and the ring closes
##   5 a release inside the dead zone (10 px from the centre) cancels: ring closed, brush unchanged
##   6 a release outside the ring (160 px out) cancels too
##   7 PLANTED FAKE: the same release as k=3 is checked against brush 4; that check MUST be false (a test that cannot fail
##     proves nothing)
extends SceneTree

var fails := 0
var m: Node
var ui: KMeshSculptUI
const NAMES := ["draw", "clay strips", "inflate", "smooth", "flatten", "pinch", "crease", "grab", "snake hook", "mask"]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e)
	await process_frame


func release(p: Vector2) -> void:
	await move(p)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = p
	e.global_position = p
	root.push_input(e)
	await idle(2)


func key(k: int) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	root.push_input(e)
	await idle(2)
	var u := InputEventKey.new()
	u.keycode = k
	u.physical_keycode = k
	u.pressed = false
	root.push_input(u)
	await idle(2)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._sculpt_start()
	await idle(3)
	ui = m.ksc
	var c := Vector2(root.size) * 0.5
	ok(ui.on and m.get("pie_on") == false, "(1) sculpt is open and the pie option is off by default (pie_on = %s)" % str(m.get("pie_on")))
	var pie = m.get("ui_pie")
	ok(pie is RingMenu, "(1b) main owns a pie ring (ui_pie)")
	if not (pie is RingMenu):
		print("pie_test: %d FAIL" % fails)
		quit(1)
		return
	# 2 option off
	ui.brush = "draw"
	await move(c)
	await key(KEY_Q)
	ok(not pie.visible and ui.brush == "draw", "(2) option off: Q opens no ring (visible %s) and the brush stays '%s'" % [pie.visible, ui.brush])
	# 3 option on
	m.pie_on = true
	await move(c)
	await key(KEY_Q)
	var n: int = pie.items.size()
	var names: Array = []
	for it in pie.items:
		names.append(String(it["name"]))
	ok(pie.visible and n == NAMES.size() and names == NAMES, "(3) option on: Q opens the ring, %d wedges %s" % [n, str(names)])
	ok(pie.at.distance_to(c) < 1.0, "(3b) ring centre (%.1f, %.1f) is within 1 px of the mouse (%.1f, %.1f): %.2f px" % [pie.at.x, pie.at.y, c.x, c.y, pie.at.distance_to(c)])
	# 4 every wedge by angle
	var wrong := 0
	var closed := 0
	for k in NAMES.size():
		if not pie.visible:
			await move(c)
			await key(KEY_Q)
		var a := deg_to_rad(k * 360.0 / NAMES.size())   # 0 = up, clockwise
		var p: Vector2 = pie.at + Vector2(sin(a), -cos(a)) * 70.0
		ui.brush = "sentinel"
		await release(p)
		if ui.brush != NAMES[k]:
			wrong += 1
			print("     k=%d at %.0f deg gave '%s', wanted '%s'" % [k, k * 360.0 / NAMES.size(), ui.brush, NAMES[k]])
		if not pie.visible:
			closed += 1
		if k == 3:
			ok(not (ui.brush == NAMES[4]), "(7) PLANTED: the k=3 release checked against brush 4 is false, as it must be")
	ok(wrong == 0 and closed == NAMES.size(), "(4) a release at angle k*360/%d picks brush k for every k: %d wrong, ring closed after %d / %d" % [NAMES.size(), wrong, closed, NAMES.size()])
	# 5 dead zone
	await move(c)
	await key(KEY_Q)
	ui.brush = "inflate"
	await release(pie.at + Vector2(0, -10))
	ok(not pie.visible and ui.brush == "inflate", "(5) release 10 px from the centre cancels: ring open %s, brush '%s'" % [pie.visible, ui.brush])
	# 6 outside
	await move(c)
	await key(KEY_Q)
	await release(pie.at + Vector2(160, 0))
	ok(not pie.visible and ui.brush == "inflate", "(6) release 160 px out cancels: ring open %s, brush '%s'" % [pie.visible, ui.brush])
	print("pie_test: %d FAIL" % fails if fails > 0 else "pie_test: all ok")
	quit(1 if fails > 0 else 0)
