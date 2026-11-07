## godot --path . -s tests/coach_test.gd     (ROADMAP_400 P19: the task coach, scripts/task_coach.gd; needs a window)
## "Task coach: make a fighter" walks BODY -> MODEL -> SURFACE -> POSE, a small non-modal panel with the current step, what to do,
## a live check read from the app's real state, and a Next that is enabled only while the check is green.
## Checks (the coach reads them; the test reads the truth itself, never through the coach):
##   BODY    S.body is not the default {} (a proportion moved or a quick body picked)
##   MODEL   the mesh editor has run an edit (kmed.undo.steps > 0)
##   SURFACE the editor's mesh has a material slot
##   POSE    some joint's angle is more than 10 degrees from rest (0,0,0)
## Bars, written before the code:
##  (1) before any action every check is false, and the command starts the coach on step 0 with the BODY page up
##  (2) each step: the check is false before the real action and true after it (actions: a real click on Quick 95th; the
##      editor's own start + subdivide; the material library's apply; B.set_ang), and the truth read here agrees
##  (3) Next is disabled while red: a real click on it does nothing (step and page unchanged); green it is enabled, and a real click
##      moves on one step AND switches to that step's page (MODEL, SURFACE, POSE); at the last step it reads Done and closes
##  (4) Cancel closes the panel; the scene (S json, B angles, mesh json) is byte-identical before and after
##  (5) restarting mid-way resumes at the FIRST red step (after BODY+MODEL green: SURFACE, twice); a step that went red again
##      (body back to default) pulls the restart back to BODY
##  (6) PLANTED FAIL: a check that ignores state (always true) is caught by the same agreement test that passes the real one
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func click(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e)
		await process_frame
	await idle()


func cmd() -> Dictionary:
	for c in m.ui_cmd.commands:
		if c["name"] == "Task coach: make a fighter":
			return c
	return {}


## the truth, read from the app without the coach
func truth(i: int) -> bool:
	match i:
		0:
			return not m.S.body.is_empty()
		1:
			return m.kmed != null and m.kmed.undo.steps.size() > 0
		2:
			return m.kmed != null and m.kmed.mesh != null and m.kmed.mesh.materials.size() > 0
		_:
			for j in m.B.ang:
				var a: Vector3 = m.B.ang[j]
				if maxf(absf(a.x), maxf(absf(a.y), absf(a.z))) > 10.0:
					return true
			return false


## the coach agrees with the truth on step i, and its Next button agrees with its check
func agrees(c, i: int) -> bool:
	var t := truth(i)
	return c.check(i) == t and (c.step != i or c.btn_next.disabled == (not t))


func world() -> String:
	var kj := ""
	if m.kmed != null and m.kmed.mesh != null:
		kj = JSON.stringify(m.kmed.mesh.to_dict())
	return JSON.stringify(m.S.to_dict(m.B)) + "|" + str(m.B.ang) + "|" + kj


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var c = m.task_coach
	ok(c != null, "(0) main has a task coach")
	ok(not cmd().is_empty(), "(0) the command 'Task coach: make a fighter' is registered")
	if c == null or cmd().is_empty():
		print("coach_test: FAIL (no coach)")
		quit(1)
		return
	# (1)
	for i in 4:
		ok(not c.check(i) and not truth(i), "(1) step %d: check false before any action (coach %s, truth %s)" % [i, c.check(i), truth(i)])
	cmd()["run"].call()
	await idle(3)
	ok(c.on and c.step == 0 and m.cur_page == "BODY" and c.panel.visible, "(1) the command starts the coach on BODY (step %d, page %s)" % [c.step, m.cur_page])
	ok(c.btn_next.disabled, "(1) Next is disabled at the start")
	# (6) planted: a check that ignores state
	c.check_override[0] = func(): return true
	c.refresh()
	await idle(2)
	ok(not agrees(c, 0), "(6) PLANTED always-true check is caught: it says green, the truth is red")
	c.check_override.erase(0)
	c.refresh()
	await idle(2)
	ok(agrees(c, 0), "(6) the real check passes the same agreement test")
	# (3) red click does nothing
	await click(c.btn_next)
	ok(c.step == 0 and m.cur_page == "BODY", "(3) a real click on a red Next does nothing (step %d, page %s)" % [c.step, m.cur_page])
	# BODY action: a real click
	var q: Button = m.ui_body.find_child("quick_95", true, false)
	await click(q)
	ok(c.check(0) and truth(0) and agrees(c, 0) and not c.btn_next.disabled, "(2) BODY: green after the real Quick 95th click; Next enabled (S.body keys %d)" % m.S.body.size())
	await click(c.btn_next)
	ok(c.step == 1 and m.cur_page == "MODEL", "(3) Next moved to MODEL and switched the page (step %d, page %s)" % [c.step, m.cur_page])
	# MODEL
	ok(not c.check(1) and not truth(1) and c.btn_next.disabled, "(2) MODEL: red before the edit, Next disabled")
	await click(c.btn_next)
	ok(c.step == 1 and m.cur_page == "MODEL", "(3) red click on MODEL does nothing")
	m._kmesh_edit_start()
	await idle(3)
	ok(not c.check(1), "(2) MODEL: opening the editor alone is not an edit (red)")
	m.kmed.subdivide(1)
	await idle(3)
	ok(c.check(1) and truth(1) and agrees(c, 1) and not c.btn_next.disabled, "(2) MODEL: green after an edit (%d undo steps)" % m.kmed.undo.steps.size())
	await click(c.btn_next)
	ok(c.step == 2 and m.cur_page == "SURFACE", "(3) Next moved to SURFACE (step %d, page %s)" % [c.step, m.cur_page])
	# (4) cancel
	var before := world()
	var pg: String = m.cur_page
	await click(c.btn_cancel)
	ok(not c.on and not c.panel.visible, "(4) Cancel closes the coach")
	ok(world() == before and m.cur_page == pg, "(4) the scene is byte-identical after Cancel (%d chars)" % before.length())
	# (5) resume
	cmd()["run"].call()
	await idle(3)
	ok(c.on and c.step == 2 and m.cur_page == "SURFACE", "(5) restart resumes at the first red step: SURFACE (step %d)" % c.step)
	await click(c.btn_cancel)
	cmd()["run"].call()
	await idle(3)
	ok(c.step == 2, "(5) and again (step %d)" % c.step)
	await click(c.btn_cancel)
	var keep: Dictionary = m.S.body.duplicate(true)
	m.S.body = {}   # the user reset the body by hand: the first red step is BODY again
	cmd()["run"].call()
	await idle(3)
	ok(c.step == 0 and m.cur_page == "BODY", "(5) a step gone red again pulls the restart back to BODY (step %d)" % c.step)
	m.S.body = keep
	c.refresh()
	await idle(2)
	ok(c.check(0) and not c.btn_next.disabled, "(5) body back: green again")
	await click(c.btn_cancel)
	cmd()["run"].call()
	await idle(3)
	ok(c.step == 2, "(5) restart after the body is back: SURFACE again (step %d)" % c.step)
	# SURFACE
	ok(not c.check(2) and not truth(2) and c.btn_next.disabled, "(2) SURFACE: red with no material, Next disabled")
	await click(c.btn_next)
	ok(c.step == 2, "(3) red click on SURFACE does nothing")
	if m.kmed == null or not m.kmed.on:
		m._kmesh_edit_start()
		await idle(3)
	var lp = m.kmed.mat_panel.open_library()
	await idle(3)
	lp.apply(MaterialLibrary.find("Polished steel"))
	await idle(3)
	ok(c.check(2) and truth(2) and agrees(c, 2) and not c.btn_next.disabled, "(2) SURFACE: green after a library material (%d slot)" % m.kmed.mesh.materials.size())
	await click(c.btn_next)
	ok(c.step == 3 and m.cur_page == "POSE", "(3) Next moved to POSE (step %d, page %s)" % [c.step, m.cur_page])
	# POSE
	ok(not c.check(3) and not truth(3) and c.btn_next.disabled, "(2) POSE: red at rest, Next disabled")
	await click(c.btn_next)
	ok(c.on and c.step == 3, "(3) red click on POSE does nothing")
	var small := ""
	for j in m.B.ang:
		m.B.set_ang(j, Vector3(9.0, 0, 0))
		if (m.B.ang[j] as Vector3).length() > 5.0:
			small = j
			break
		m.B.set_ang(j, Vector3(0, 0, 0))
	c.refresh()
	await idle(2)
	ok(small != "" and not truth(3) and not c.check(3), "(2) POSE: %s at 9 degrees is not enough (red)" % small)
	if small != "":
		m.B.set_ang(small, Vector3(0, 0, 0))
	var moved := ""
	for j in m.B.ang:
		m.B.set_ang(j, Vector3(40.0, 0, 0))
		if truth(3):
			moved = j
			break
		m.B.set_ang(j, Vector3(0, 0, 0))
	m._refresh()
	await idle(3)
	ok(moved != "" and c.check(3) and truth(3) and agrees(c, 3) and not c.btn_next.disabled, "(2) POSE: green after %s turned 40 degrees" % moved)
	ok(c.btn_next.text == "Done", "(3) the last Next reads Done (%s)" % c.btn_next.text)
	await click(c.btn_next)
	ok(not c.on and not c.panel.visible, "(3) Done closes the coach")
	print("coach_test: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	TestFiles.cleanup()
	quit(fails)
