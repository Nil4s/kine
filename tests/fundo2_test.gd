extends SceneTree
## FUNDO2 (Nick 2026-10-28: "like Fusion 360, the BUILDING card opens a blank part"): a beginner from the start screen, real clicks at 1280x720,
## makes a part of 10 steps (one undo entry each), then Undo all 10 and Redo all 10: by keys (Ctrl+Z / Ctrl+Y) and by the Undo and Redo buttons on the top bar.
## Every step must come back exactly: the record, the volume, the box and the body colours. Bars per step (S1..S10), per undo (U1..U10), per redo (R1..R10).
## shots: C:/Temp/claude/fundo2/ (open, s7, s10, undo_all, redo_all)
## FIXES found by these bars (each failed on the code before): W1-W20 (Undo/Redo words named the step below: "Took back: Took back: ..."), H0 (the blank part's hint kept "Colour: Blue")
const SHOT := "C:/Temp/claude/fundo2"
const DIRT := "user://fundo2_test"

var fails := 0
var m: Node
var sigs := []          # sigs[i] = the whole-part signature after i steps (sigs[0] = the blank part)
var ubs := []           # undo depth after i steps


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


func press_key(kc: Key, ctrl := true) -> void:
	var e := InputEventKey.new()
	e.keycode = kc
	e.physical_keycode = kc
	e.key_label = kc
	e.ctrl_pressed = ctrl
	e.pressed = true
	root.push_input(e, true)
	await process_frame
	var u := InputEventKey.new()
	u.keycode = kc
	u.physical_keycode = kc
	u.key_label = kc
	u.ctrl_pressed = ctrl
	u.pressed = false
	root.push_input(u, true)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func solid() -> Dictionary:
	return Part.replay(m.S.part)


## the whole part as one string: the record, the volume, the box and each body colour
func sig() -> String:
	var s := solid()
	var looks: Array = s.get("body_looks", [])
	var cols := []
	for i in int(s.get("bodies", 0)):
		cols.append(str(Part.look_at(looks, i)["c"]))
	var bb: AABB = s.get("aabb", AABB())
	return JSON.stringify(m.S.part) + "|v=" + str(float(s.get("volume", 0.0))) + "|bb=" + str(bb) + "|c=" + str(cols) + "|e=" + str(s.get("errors", {}))


func vol() -> float:
	return float(solid().get("volume", 0.0))


func vol_of_sig(sg: String) -> float:
	var k := sg.find("|v=")
	var e := sg.find("|bb=")
	if k < 0 or e < 0:
		return 0.0
	return float(sg.substr(k + 3, e - k - 3))


## one step done: one undo entry more, the part changed, no failed feature
func step_bar(i: int, name: String, want_vol_change: bool) -> void:
	var before: String = sigs[i - 1]
	var now := sig()
	var entries: int = m.undo.size() - int(ubs[i - 1])
	var errs: Dictionary = solid().get("errors", {})
	var changed := now != before
	var volok: bool = (not want_vol_change) or absf(vol() - vol_of_sig(before)) > 1e-12   # m3: a volume change of at least 1e-6 mm3
	var has_body: bool = int(solid().get("bodies", 0)) >= 1 or i <= 1 or i == 3   # the two outline steps (1, 3) come before any solid
	ok(entries == 1 and changed and volok and errs.is_empty() and has_body,
		"S%d %s: +%d undo entries, part changed %s, failed features %s, vol %.0f mm3" % [i, name, entries, str(changed), str(errs.keys()), vol() / (Part.MM * Part.MM * Part.MM)])
	sigs.append(now)
	ubs.append(m.undo.size())


## the words on screen: every visible label and button text
func texts_under(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Label and (n as Label).text.strip_edges() != "":
		out.append((n as Label).text)
	elif n is Button and (n as Button).text.strip_edges() != "":
		out.append((n as Button).text)
	for c in n.get_children():
		texts_under(c, out)


## W bars: an undo or redo says "Took back: X" / "Put back: X" once, and names no step "Took back ..."
func back_words_bad() -> String:
	var t := []
	texts_under(m, t)
	for s in t:
		if String(s).count("Took back") + String(s).count("Put back") > 1:
			return "on screen: " + String(s)
	for e in m.undo:
		if String(e.get("name", "")).find("back") >= 0:
			return "undo step named: " + String(e.get("name", ""))
	for e in m.redo:
		if String(e.get("name", "")).find("back") >= 0:
			return "redo step named: " + String(e.get("name", ""))
	return ""


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
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	var pu = m.bld.part
	var ep = pu.ep
	ok(m.cur_page == "BUILD" and pu.on and pu.easy and ep != null and ep.make_btns.has("draw"), "B0 BUILDING card, one click -> Easy part on (page %s)" % m.cur_page)
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 35.0
	m.yaw = 30.0
	m._cam()
	await idle(60)
	await shot("open")
	sigs = [sig()]
	ubs = [m.undo.size()]

	# S1 the plate: Draw shape (a drag on the grid), then Pull it up
	await click_ctl(ep.make_btns["draw"])
	await drag_pts([scr(Vector3(-0.05, 0.0, -0.04)), scr(Vector3(0.05, 0.0, 0.04))])
	await idle(5)
	step_bar(1, "plate: Draw shape (the outline)", false)
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	step_bar(2, "plate: Pull it up", true)
	# S2 the knob: a round shape on the top face, pulled up
	var top_y := (solid()["aabb"] as AABB).end.y
	m.pitch = 40.0
	m.yaw = 25.0
	m._cam()
	await idle(60)
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["round"])
	var c0 := scr(Vector3(0.02, top_y, 0.0))
	await drag_pts([c0, c0 + Vector2(22, 0)])
	await idle(5)
	step_bar(3, "knob: round shape on the top face", false)
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	step_bar(4, "knob: Pull it up", true)
	# S5 Mirror that
	await click_ctl(ep.make_btns["mirror"])
	await idle(10)
	step_bar(5, "Mirror that", true)
	# S6 Round the edges
	await click_ctl(ep.make_btns["round"])
	await idle(10)
	step_bar(6, "Round the edges", true)
	# S7 Colour Red
	await click_ctl(ep.make_btns["colour"])
	await idle(3)
	await click_ctl(ep.colour_box.find_child("easypart_colour_red", true, false))
	await idle(10)
	step_bar(7, "Colour Red", false)
	await shot("s7")
	# S8 Cut a hole through the middle
	await click_ctl(ep.make_btns["hole"])
	await idle(10)
	step_bar(8, "Cut a hole", true)
	# S9 Repeat it (copies of the newest solid in a row)
	await click_ctl(ep.make_btns["repeat"])
	await idle(10)
	step_bar(9, "Repeat it", true)
	# S10 Colour Blue on the whole part
	await click_ctl(ep.make_btns["colour"])
	await idle(3)
	await click_ctl(ep.colour_box.find_child("easypart_colour_blue", true, false))
	await idle(10)
	step_bar(10, "Colour Blue", false)
	await shot("s10")
	var top_sig := sig()

	# undo all 10: keys (Ctrl+Z) for steps 10..6, the Undo button for steps 5..1
	for i in range(10, 0, -1):
		if i >= 6:
			await press_key(KEY_Z)
		else:
			await click_ctl(ep.undo_btn)
		ok(sig() == sigs[i - 1] and m.undo.size() == ubs[i - 1],
			"U%d undo %s: back to step %d exactly (%s)" % [11 - i, "key" if i >= 6 else "button", i - 1, "match" if sig() == sigs[i - 1] else "DIFFERENT"])
		ok(back_words_bad() == "", "W%d after undo %d the words say it once (%s)" % [11 - i, i, back_words_bad()])
	await shot("undo_all")
	ok(m.redo.size() == 10, "U0 redo holds the 10 steps (%d)" % m.redo.size())
	# H0 the blank part's hint names no step it took back (it said "Colour: Blue" on the empty part before the fix)
	var hint_blank := String(ep.hint_l.text)
	ok(hint_blank.find("Colour") < 0 and hint_blank.find("Blue") < 0, "H0 the blank part's hint names no step: [%s]" % hint_blank)

	# redo all 10: the Redo button for steps 1..5, keys (Ctrl+Y) for steps 6..10
	for i in range(1, 11):
		if i <= 5:
			await click_ctl(ep.redo_btn)
		else:
			await press_key(KEY_Y)
		ok(sig() == sigs[i] and m.undo.size() == ubs[i],
			"R%d redo %s: step %d back exactly (%s)" % [i, "button" if i <= 5 else "key", i, "match" if sig() == sigs[i] else "DIFFERENT"])
		ok(back_words_bad() == "", "W%d after redo %d the words say it once (%s)" % [10 + i, i, back_words_bad()])
	await shot("redo_all")
	ok(sig() == top_sig, "R0 after redo all 10 the part is the one saved after S10")

	print("fundo2: %d fail" % fails)
	quit(1 if fails > 0 else 0)
