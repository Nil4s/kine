## godot --path . -s tests/drag_stop_test.gd     (GATES PP2; needs a window)
## A DRAG THAT STOPS SAYS WHY, through real mouse events in the view: (1) the right upper arm dragged across into the
## body: the status line says STOPPED and which parts meet; (2) the right forearm swung round far past the elbow's
## range: STOPPED, at its limit, naming the joint and the range; (3) a small drag in free air says neither. Each
## status is read from the label the user sees.
extends SceneTree

var m: Node
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 4) -> void:
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
	await process_frame


## a press on p, steps of d, a release: what the user does
func drag(p: Vector2, d: Vector2, steps: int) -> String:
	await btn(true, p)
	var q := p
	var said := ""
	for i in steps:
		q += d
		var e := InputEventMouseMotion.new()
		e.position = q
		e.global_position = q
		e.relative = d
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e)
		await process_frame
		if "STOPPED" in m.ui_status.text and said == "":
			said = m.ui_status.text
	if said == "":
		said = m.ui_status.text
	await btn(false, q)
	await idle()
	return said


func spot(j: String, f := 0.5) -> Vector2:
	var c: Array = m.B.cap(j)
	return m.cam.unproject_position(c[0].lerp(c[1], f))


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.sel = "pelvis"
	m._refresh()
	await idle()
	# (1) the right upper arm (his right = screen left in the front view) swept across, into the body
	var p := spot("upperarm_r", 0.7)
	var toward: Vector2 = (m.cam.unproject_position(m.B.P["spine_03"]) - p)
	var s1 := await drag(p, toward.normalized() * 12.0 + Vector2(0, 6), 40)
	ok(m.sel == "upperarm_r", "the press picked the right upper arm (%s)" % m.sel)
	ok("STOPPED" in s1 and ("meets the" in s1 or "at its limit" in s1),   # ROADMAP 41: swung toward the mouse, the arm may reach its range before the body
	 "1 the arm dragged into the body: '%s'" % s1.strip_edges())
	m._reset_all()
	m._refresh()
	await idle()
	# (2) the left shin swung back and up, far past the knee's range (side view: a knee bends in the picture's plane;
	# ROADMAP 41 swings a part toward the mouse in the view plane, and a front-view elbow bends across the view)
	m.yaw = 90.0
	m._cam()
	await idle()
	var q := spot("calf_l", 0.8)
	m.B.set_ang("calf_l", Vector3(60, 0, 0))
	m.B.fk()
	m._refresh()
	await idle()
	var way := (spot("calf_l", 0.8) - q).normalized()   # the screen direction a knee bend goes
	m._reset_all()
	m._refresh()
	m._cam()
	await idle()
	var up := (way * 0.3 + Vector2(0, -1)).normalized()   # up and a little back: past 145 deg
	var s2 := await drag(q, up * 14.0, 40)
	ok(m.sel == "calf_l", "the press picked the left shin (%s)" % m.sel)
	ok("STOPPED" in s2 and "at its limit" in s2 and m.nice("calf_l") in s2, "2 the shin past the knee's range: '%s'" % s2.strip_edges())
	m._reset_all()
	m.yaw = 0.0
	m._cam()
	m._refresh()
	await idle()
	# (3) a small drag in free air
	var r := spot("lowerarm_l", 0.8)
	var s3 := await drag(r, Vector2(0, -3), 4)
	ok(m.sel == "lowerarm_l" and not ("STOPPED" in s3) and ("ROTATING" in s3), "3 a small free drag says neither: '%s'" % s3.strip_edges())
	print("DRAG STOP TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
