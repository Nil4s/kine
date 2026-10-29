extends SceneTree
## FHELP3 (Nick 2026-10-28: free 3D building, like Fusion 360; a beginner who never read a manual): from the real start screen,
## the BUILDING card opens a blank Easy Part. Every Easy Part button that is shown is pressed ONCE from a blank part and ONCE
## from a one-part state (a box drawn and pulled up), by real clicks at 1280 x 720. Each press must DO something visible
## (the part, the undo count, the page, the armed tool, a dialog) or SAY something in words (the status line).
## Bars:
##   H0 the blank state and the one-part state differ (the test is measuring something)
##   H1 every press on a blank part changes something or says a line (a dead end is a bar)
##   H2 every press on a one-part state changes something or says a line
##   H3 no jargon in any line said (sketch, extrude, loft, boolean, feature, body, fillet, revolve, kernel)
##   H4 the Easy button pressed while Easy is on says what Easy is, or does something
## Buttons that need a prerequisite press first (Cut a hole, Cut in two, Repeat it, Draw shape, Colour) are pressed after that
## press, the way a beginner reaches them. Stick together needs two solid pieces: it is listed as not reached.
## shots: C:/Temp/claude/fhelp3/open.png (blank), one.png (one part), after_<state>_<name>.png for the presses that said words, end.png
const SHOT := "C:/Temp/claude/fhelp3"
const DIRT := "user://fhelp3_test"
const JARGON := ["sketch", "extrude", "loft", "boolean", "feature", "body", "fillet", "revolve", "kernel"]
var fails := 0
var m: Node
var pu
var ep
var rows := []
var dead := []
var said_jargon := []
var not_reached := []


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


func drag_pts(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(pts[i])
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func windows_up() -> int:
	return _visible_windows().size()


func _visible_windows() -> Array:
	var out := []
	for host in [root, m]:   # the export dialog is a Window under Main, not under the root
		for c in (host as Node).get_children():
			if c is Window and (c as Window).visible:
				out.append(c)
	return out


## what the screen says: the Easy line, else the status line the app shows
func said_now() -> String:
	var t := String(ep.msg).strip_edges()
	if t == "" and m.ui_status != null and m.ui_status.visible:
		t = String(m.ui_status.text).strip_edges()
	if t == "" and m.easy != null and m.easy.building != null:
		t = String(m.easy.building._msg).strip_edges()   # the Easy bar's own line (Use in a scene on a blank part)
	return t


func snapshot() -> Dictionary:
	return {
		"part": JSON.stringify(m.S.part), "undo": m.undo.size(), "page": m.cur_page,
		"easy": pu.easy, "armed": ep.armed, "win": windows_up(),
		"vis": [ep.shape_box.visible, ep.hole_box.visible, ep.split_box.visible, ep.colour_box.visible, ep.repeat_box.visible, ep.stick_box.visible, ep.panel.visible],
	}


func changed(a: Dictionary, b: Dictionary) -> bool:
	for k in a:
		if str(a[k]) != str(b[k]):
			return true
	return false


## put the part back to the state the press starts from
func restore(state: String, snap: Dictionary) -> void:
	ep.armed = ""
	ep.msg = ""
	ep.hole_base = {}
	ep.split_id = ""
	ep.rep_id = ""
	ep.stick_picks = []
	ep._draft = {}
	for w in _visible_windows():
		w.visible = false   # an export dialog left open by the last press
	if m.cur_page != "BUILD":
		m._page_set("BUILD")   # Use in a scene leaves the part page: the beginner's way back is the page's own tab
	if not pu.easy:
		pu.open_easy()
	m.S.part = (snap[state] as Dictionary).duplicate(true)
	pu.upto = -1
	pu.sync()
	ep._rows_sync()
	ep._values_sync()
	await idle(3)


func press(state: String, nm: String, btn: Control, snap: Dictionary, keep := false) -> void:
	if not keep:
		await restore(state, snap)
	if not btn.is_visible_in_tree():
		not_reached.append("%s %s (not shown in this state)" % [state, nm])
		return
	var before := snapshot()
	ep.msg = ""
	if m.ui_status != null:
		m.ui_status.text = ""
	if m.easy != null and m.easy.building != null:
		m.easy.building._msg = ""
	await click_ctl(btn)
	await idle(8)
	var moved := changed(before, snapshot())
	var said := said_now()
	rows.append([state, nm, moved, said])
	if not moved and said == "":
		dead.append("%s %s" % [state, nm])
	elif said != "":
		var low := said.to_lower()
		for j in JARGON:
			if low.find(j) >= 0:
				said_jargon.append("%s %s: %s" % [state, nm, said])
				break
	if said != "" and not moved:
		await shot("after_%s_%s" % [state, nm])
	print("   %-6s %-22s moved=%s bodies=%d said=[%s]" % [state, nm, moved, int(Part.replay(m.S.part)["bodies"]), said])


func press_all(state: String, snap: Dictionary) -> void:
	var order := [
		["undo", ep.undo_btn], ["redo", ep.redo_btn], ["use_scene", ep.use_scene_btn], ["give", ep.give_btn], ["export", ep.export_btn], ["easy", ep.easy_btn],
	]
	for mk in ["draw", "pull", "spin", "round", "hole", "mirror", "curve", "blend", "split", "colour", "repeat", "stick"]:
		order.append(["make_" + mk, ep.make_btns[mk]])
	order.append(["chip_empty", ep.empty_chip])
	for t in ["sword", "axe", "shield", "chair", "crate"]:
		if ep.chips.has(t):
			order.append(["chip_" + t, ep.chips[t]])
	order.append(["back", ep.back_btn])
	for e in order:
		await press(state, String(e[0]), e[1], snap)
	# the sub-buttons, each reached by the press that shows its panel
	for pre in ["hole", "split", "repeat", "draw", "colour"]:
		await restore(state, snap)
		ep._make(pre)
		await idle(8)
		if pre == "colour":
			for b in ep.colour_box.get_child(0).get_children():
				if b is Button:
					await press(state, "colour_" + String(b.name), b, snap, true)   # the colour row is open while Colour is armed: no restore between chips
			await restore(state, snap)
			continue
		var group := {}
		if pre == "hole":
			group = ep.hole_btns
		elif pre == "split":
			group = ep.split_btns
		elif pre == "repeat":
			group = ep.rep_btns
		else:
			group = ep.shape_btns
		for k in group:
			await press(state, "%s_%s" % [pre, k], group[k], snap)
	await restore(state, snap)


func expert_check(state: String, snap: Dictionary) -> void:
	await restore(state, snap)
	var before := snapshot()
	ep.msg = ""
	if m.ui_status != null:
		m.ui_status.text = ""
	await click_ctl(ep.expert_btn)
	await idle(8)
	var moved := changed(before, snapshot())
	rows.append([state, "expert", moved, said_now()])
	if not moved and said_now() == "":
		dead.append("%s expert" % state)
	pu.open_easy()
	await idle(8)


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
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	pu = m.bld.part
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	ep = pu.ep
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 35.0
	m.yaw = 30.0
	m._cam()
	await idle(60)
	await shot("open")
	var blank: Dictionary = (m.S.part as Dictionary).duplicate(true)
	await click_ctl(ep.make_btns["draw"])
	await drag_pts([scr(Vector3(-0.05, 0.0, -0.04)), scr(Vector3(0.05, 0.0, 0.04))])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	var one: Dictionary = (m.S.part as Dictionary).duplicate(true)
	m.pitch = 40.0
	m._cam()
	await idle(40)
	await shot("one")
	var snap := {"blank": blank, "one": one}
	ok(not blank.is_empty() and JSON.stringify(blank) != JSON.stringify(one), "H0 the two states differ (blank part and one pulled box)")
	await press_all("blank", snap)
	await press_all("one", snap)
	await expert_check("blank", snap)
	await expert_check("one", snap)
	await restore("one", snap)
	print("---- every press (state, button, changed, said):")
	for r in rows:
		print("   %s" % str(r))
	print("---- not reached: %s" % str(not_reached))
	print("---- dead ends: %s" % str(dead))
	print("---- jargon: %s" % str(said_jargon))
	ok(dead.is_empty(), "H1/H2 every press changes something or says a line (%d presses, dead ends %d: %s)" % [rows.size(), dead.size(), str(dead)])
	ok(said_jargon.is_empty(), "H3 no jargon in any line (%s)" % str(said_jargon))
	var easy_row := []
	for r in rows:
		if r[1] == "easy":
			easy_row.append(r)
	ok(not easy_row.is_empty() and (bool(easy_row[0][2]) or String(easy_row[0][3]) != ""), "H4 the Easy button while Easy is on says what Easy is or does something (%s)" % str(easy_row))
	await shot("end")
	print("fhelp3: %d fail" % fails)
	quit(1 if fails > 0 else 0)
