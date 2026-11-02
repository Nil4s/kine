extends SceneTree
## s252 UNDO / REDO TOASTS NAME WHAT THEY CHANGED, AND NEVER COVER A BUTTON (1024 x 600, 1280 x 720, 1920 x 1080; Easy box + Expert sketch):
## the toast and the status line after Undo / Redo never end in ":" and name the step; an empty stack says "Nothing to undo / redo";
## the toast's rect intersects no visible button. CONTROL: origin's "Redid:" fails the same check.
## Shots: C:/Users/Nick/tools/kine_workers/out/252/
var fails := 0
var m: Node
var pu
var ep
const SHOT := "C:/Users/Nick/tools/kine_workers/out/252"
const DIRT := "user://s252_test"
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


func size_to(w: int, h: int) -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = Vector2i(w, h)
	await idle(14)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func _buttons(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Button:
		var r := (n as Control).get_global_rect()
		if r.size.x > 1.0 and r.size.y > 1.0:
			out.append([n, r])
	for ch in n.get_children():
		_buttons(ch, out)


## verdict for a sentence: "" when fine, else why not
func words_verdict(t: String) -> String:
	var s := t.strip_edges()
	if s == "":
		return "empty"
	if s.ends_with(":"):
		return "ends in a colon: '%s'" % t
	return ""


## the toast's rect against every visible button: "" when it covers none
func cover_verdict(tr: Rect2) -> String:
	var all := []
	_buttons(root, all)
	for p in all:
		var q: Rect2 = tr.intersection(p[1])
		if q.size.x > 1.0 and q.size.y > 1.0:
			return "toast %s covers button '%s' %s" % [tr, (p[0] as Button).text, p[1]]
	if not root.get_visible_rect().grow(1.0).encloses(tr):
		return "toast %s outside the window" % tr
	return ""


func after(tag: String, kind: String, must: String) -> void:
	await idle(6)
	var tt: String = m.ui_toast.text if m.ui_toast != null else ""
	var st: String = m.ui_status.text
	ok(m.ui_toast != null and m.ui_toast.visible, "%s %s: a toast shows ('%s')" % [tag, kind, tt])
	var vt := words_verdict(tt)
	var vs := words_verdict(st)
	ok(vt == "", "%s %s: toast '%s' %s" % [tag, kind, tt, vt])
	ok(vs == "", "%s %s: status '%s' %s" % [tag, kind, st, vs])
	if must != "":
		ok(tt.to_lower().contains(must.to_lower()) and st.to_lower().contains(must.to_lower()), "%s %s: toast '%s' and status '%s' both name '%s'" % [tag, kind, tt, st, must])
	if m.ui_toast != null and m.ui_toast.visible:
		var cv := cover_verdict(m.ui_toast.get_global_rect())
		ok(cv == "", "%s %s: toast covers no button %s" % [tag, kind, cv])


## S253: the camera ease after a window resize runs on real time (FRAME_EASE s), not on frames: on a loaded PC 14 idle frames can end
## before it does, and the box's corners were projected from a camera that was still moving (the press then landed on the view column).
## Wait for the same condition the drag always assumed: the ease is over and the camera has not moved for 5 frames (cap 900 frames).
func wait_cam_still() -> void:
	var still := 0
	var last := [m.target, float(m.dist)]
	for i in 900:
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
	var s0 := cam.unproject_position(Vector3(1.4, 0.0, 0.0))   # S253: projected after the camera is still (was: before the Draw click, mid-ease)
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


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	await size_to(1280, 720)
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
	# CONTROL first: origin's words fail the same checks
	ok(words_verdict("Redid:") != "", "control: origin's toast 'Redid:' is reported (%s)" % words_verdict("Redid:"))
	ok(words_verdict("redone:") != "", "control: origin's status 'redone:' is reported")
	ok(words_verdict("Redid: ") != "", "control: 'Redid: ' with a trailing space is reported")
	for sz in SIZES:
		var w: int = sz[0]
		var h: int = sz[1]
		await size_to(w, h)
		var tag := "%dx%d" % [w, h]
		m.S.part = {}
		pu.sync()
		await idle(8)
		m.undo.clear()
		m.redo.clear()
		# Easy: empty stacks
		m._undo()
		await after(tag + " Easy", "undo on an empty stack", "nothing to undo")
		m._redo()
		await after(tag + " Easy", "redo on an empty stack", "nothing to redo")
		# Easy: a real box
		await drag_box()
		ok(m.undo.size() >= 1, "%s Easy: the drag made %d undo step(s)" % [tag, m.undo.size()])
		var nm: String = m.easy_name(m.undo.back()) if not m.undo.is_empty() else "?"
		m._undo()
		await after(tag + " Easy", "undo of the box", nm)
		if w == 1024:
			await shot("easy_undo_%s" % tag)
		m._redo()
		await after(tag + " Easy", "redo of the box", nm)
		if w == 1024:
			await shot("easy_redo_%s" % tag)
		# Expert: a named sketch step, then an unnamed one
		ep.to_expert()
		await idle(10)
		m._step_hint = "Sketch a rectangle"
		m._push_undo()
		m._undo()
		await after(tag + " Expert", "undo of the sketch", "sketch a rectangle")
		m._redo()
		await after(tag + " Expert", "redo of the sketch", "sketch a rectangle")
		if w == 1024:
			await shot("expert_redo_%s" % tag)
		m._push_undo()
		m.undo.back()["name"] = ""
		m.undo.back().erase("hint")
		m._undo()
		await after(tag + " Expert", "undo of an unnamed step", "a change")
		m._redo()
		await after(tag + " Expert", "redo of an unnamed step", "a change")
		if w == 1024:
			await shot("expert_unnamed_redo_%s" % tag)
		m.undo.clear()
		m.redo.clear()
		m._redo()
		await after(tag + " Expert", "redo on an empty stack", "nothing to redo")
		if w == 1024:
			await shot("expert_empty_redo_%s" % tag)
		if not ep.panel.is_visible_in_tree():
			if not pu.easy_open_btn.is_visible_in_tree():
				await click_ctl(pu.part_btn)
			await click_ctl(pu.easy_open_btn)
			await idle(8)
	# CONTROL: a toast rect laid over a button fails the cover check
	var bs := []
	_buttons(root, bs)
	var pick: Rect2 = bs[0][1]
	ok(cover_verdict(pick) != "", "control: a rect laid on the button '%s' is reported covering" % (bs[0][0] as Button).text)
	print("s252: %d fail" % fails)
	quit(1 if fails > 0 else 0)
