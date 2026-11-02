extends SceneTree
## s253 A SLOW FRAME NEVER LOSES A DRAG OR AN UNDO STATE (integ121: s252 "the drag made 0 undo step(s)" and aundo3 "REDO ALL ... (1 bad)" only with 14 suites running).
## Forced slow frames: Engine.max_fps = 8 (a frame is 125 ms, the way a loaded PC stretches it).
##  0 THE FRAMING AFTER A STEP NEVER RE-POSES THE BODY (easy_home._refresh_next asks frame_clip_next with keep_body; was: body re-applied at the playhead).
##  1 UNDO / REDO KEEP THE CLOCK EXACTLY: a clip stopped on a slow frame lands some microseconds either side of a frame time; the steps taken there
##    carry playheads 2 us apart. _restore kept the playhead whenever it was within is_equal_approx (8 us) of the step's, so Undo / Redo left the
##    clock (and the body posed at it) off the step's. Undo-all then Redo-all must give back each step's exact body and playhead.
##    CONTROL: is_equal_approx calls two playheads 2 us apart equal (the old condition that skipped the restore).
##  2 A DRAG ON A MOVING CAMERA: the Easy Part camera eases for FRAME_EASE s of REAL time after a resize / edit; corners projected mid-ease land
##    on the view column (the press is eaten) and the drag makes no step. With the ease forced and frames slow, a drag made after the camera is
##    still makes exactly ONE undo step at 1024x600, 1280x720 and 1920x1080. CONTROL: the corner moves more than the 6 px that separates it from the
##    view column while the ease runs (so the old order, project then press, is unsafe).
var fails := 0
var m: Node
var pu
var ep
const DIRT := "user://s253_test"
const SIZES := [[1024, 600], [1280, 720], [1920, 1080]]


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


func click_at(p: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	root.push_input(mv, true)
	await process_frame
	await ev(p, true)
	await ev(p, false)
	await idle(2)


func snap() -> Dictionary:
	var u: Dictionary = m._snapshot()
	return {"body": var_to_str(u["body"]), "playhead": var_to_str(m.playhead)}


## wait for the condition the drag assumes: the camera ease is over and the camera has not moved for 5 frames (cap 300 frames)
func wait_cam_still() -> void:
	var still := 0
	var last := [m.target, float(m.dist)]
	for i in 300:
		await process_frame
		var now := [m.target, float(m.dist)]
		if ep._ease.is_empty() and now[0] == last[0] and now[1] == last[1]:
			still += 1
			if still >= 5:
				return
		else:
			still = 0
		last = now


func drag_box() -> void:
	await click_ctl(ep.make_btns["draw"])
	await wait_cam_still()
	var cam: Camera3D = m.cam
	var s0 := cam.unproject_position(Vector3(1.4, 0.0, 0.0))
	var s1 := cam.unproject_position(Vector3(1.5, 0.1, 0.0))
	var mv := InputEventMouseMotion.new()
	mv.position = s0
	root.push_input(mv, true)
	await process_frame
	await ev(s0, true)
	var mv2 := InputEventMouseMotion.new()
	mv2.position = s1
	mv2.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(mv2, true)
	await process_frame
	await ev(s1, false)
	await idle(3)


func text_of(b: Button) -> String:
	if b.text.strip_edges() != "":
		return b.text.strip_edges()
	for n in _walk(b, []):
		if n is Label and (n as Label).text.strip_edges() != "":
			return (n as Label).text.strip_edges()
	return ""


func _walk(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children():
		_walk(c, out)
	return out


func vis_btn(txt: String) -> Button:
	for n in _walk(root, []):
		if n is Button and (n as Button).is_visible_in_tree() and text_of(n as Button) == txt:
			return n as Button
	return null


## 0 THE FRAMING AFTER A STEP NEVER RE-POSES THE BODY: the "Then ..." row under the clip changes the strip's height a frame after an Undo / Redo
## (it depends on the move shown); easy_home._refresh_next then asked frame_clip_next() with keep_body false, which puts the body back by applying the
## clip at the playhead: a hair off (1e-3 deg) the state the step restored, and off a hand-posed step completely. Needs the Easy clip built.
func part0_framing() -> void:
	var b := vis_btn("Punch")
	if b == null:
		ok(false, "0. the Punch button is on the Easy home panel")
		return
	await click_ctl(b)
	await idle(12)
	var home: EasyHome = m.easy.home
	ok(home._built and m.S.cards.size() > 0, "0. a clip is built (%d cards)" % m.S.cards.size())
	m.playing = false
	await idle(4)
	var k: String = "upperarm_l"
	m.B.ang[k] = Vector3(33.0, 12.0, 0.0)   # a hand-posed body, not the clip's pose
	m.B.fk()
	var before: String = var_to_str(m.B.state())
	home._row_h = -1.0   # the strip "changed height": the framing is asked for
	home._refresh_next()
	await idle(4)
	ok(var_to_str(m.B.state()) == before, "0. the framing after a strip height change left the body exactly as it was (arm %s, was %s)" % [str(m.B.ang[k]), "(33, 12, 0)"])


func part1_clock() -> void:
	var base := 0.8333287
	var keys: Array = m.B.ang.keys()
	var k: String = keys[mini(3, keys.size() - 1)]
	m.undo.clear()
	m.redo.clear()
	m.playing = false
	var states: Array = []
	m.playhead = base
	states.append(snap())
	var n := 5
	for i in n:
		m._push_undo()   # the step keeps the playhead and body as they are NOW
		m.B.ang[k] = Vector3(7.0 * (i + 1), 0.0, 0.0)
		m.playhead = base + 2e-6 * float(i + 1)   # each stop lands a little later: 2 us apart
		states.append(snap())
		await process_frame
	ok(is_equal_approx(base, base + 2e-6) and base != base + 2e-6, "control: is_equal_approx calls two playheads 2 us apart equal (%s vs %s), the old condition that skipped the restore" % [str(base), str(base + 2e-6)])
	ok(m.undo.size() == n, "%d steps recorded (%d)" % [n, m.undo.size()])
	var bad := 0
	for i in range(n, 0, -1):
		m._undo()
		await idle(2)
		var got := snap()
		var want: Dictionary = states[i - 1]
		if got["playhead"] != want["playhead"] or got["body"] != want["body"]:
			bad += 1
			print("     undo to depth %d: playhead %s want %s, body equal %s" % [i - 1, got["playhead"], want["playhead"], str(got["body"] == want["body"])])
	ok(bad == 0 and m.undo.size() == 0 and m.redo.size() == n, "UNDO ALL on slow frames: each of %d Undos back to its exact body and playhead (%d bad), redo holds %d" % [n, bad, m.redo.size()])
	bad = 0
	for i in n:
		m._redo()
		await idle(2)
		var got2 := snap()
		var want2: Dictionary = states[i + 1]
		if got2["playhead"] != want2["playhead"] or got2["body"] != want2["body"]:
			bad += 1
			print("     redo to depth %d: playhead %s want %s, body equal %s" % [i + 1, got2["playhead"], want2["playhead"], str(got2["body"] == want2["body"])])
	ok(bad == 0 and m.undo.size() == n and m.redo.size() == 0, "REDO ALL on slow frames: each of %d Redos forward to its exact body and playhead (%d bad), redo left %d" % [n, bad, m.redo.size()])


func part2_drag() -> void:
	for sz in SIZES:
		var w: int = sz[0]
		var h: int = sz[1]
		var tag := "%dx%d" % [w, h]
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		root.content_scale_size = Vector2i(w, h)
		await idle(3)   # NOT the 14 frames s252 waits: the drag itself must wait for the camera
		await wait_cam_still()
		var c0: Vector2 = m.cam.unproject_position(Vector3(1.4, 0.0, 0.0))
		m.dist = float(m.dist) * 1.15   # the camera partway through an ease: 15 % further out
		m._cam()
		var cm: Vector2 = m.cam.unproject_position(Vector3(1.4, 0.0, 0.0))
		m.dist = float(m.dist) / 1.15
		m._cam()
		ok(cm.distance_to(c0) > 6.0, "control: %s the box corner moves %.1f px when the camera is partway through an ease (> the 6 px between it and the view column): projecting before the camera is still is unsafe" % [tag, cm.distance_to(c0)])
		for rep in 2:
			m.undo.clear()
			m.redo.clear()
			await drag_box()
			ok(m.undo.size() == 1, "%s drag %d on slow frames: exactly one undo step (%d)" % [tag, rep + 1, m.undo.size()])
			m._undo()
			await idle(2)
			ok(m.undo.size() == 0 and m.redo.size() == 1, "%s drag %d: Undo takes the one step back (undo %d, redo %d)" % [tag, rep + 1, m.undo.size(), m.redo.size()])
			m._redo()
			await idle(2)
			ok(m.undo.size() == 1 and m.redo.size() == 0, "%s drag %d: Redo puts the one step forward (undo %d, redo %d)" % [tag, rep + 1, m.undo.size(), m.redo.size()])
			m._undo()   # the box goes: the next drag starts from the same empty part (a reset through pu.sync() would close the Easy screen)
			await idle(2)
			m.undo.clear()
			m.redo.clear()


func _init() -> void:
	EasyMode.start_fresh = true
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	Engine.max_fps = 8
	await part0_framing()
	await part1_clock()
	Engine.max_fps = 0
	# part 2 starts from a fresh app, as s252 does (the Easy clip built above leaves its strip and panels over the Easy Part grid)
	m.queue_free()
	await idle(6)
	EasyMode.start_fresh = false
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.bld.part.set_on(false)
	m.S.part = {}
	await idle(8)
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep
	Engine.max_fps = 8
	await part2_drag()
	Engine.max_fps = 0
	print("s253: %d fail" % fails)
	quit(1 if fails > 0 else 0)
