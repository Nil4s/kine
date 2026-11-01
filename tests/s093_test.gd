extends SceneTree
## godot --path . --position 4000,4000 -s tests/s093_test.gd     (P093: Beginner / Comfortable / Expert slider; scripts/easy_part.gd, _level_*; needs the CAD DLL)
## Real clicks at 1280 x 720 from the BUILDING card. Pressing Easy opens the level slider (no new row). Bars are measured from the screen and the record:
##   1 DEFAULT      a fresh start is Comfortable: 12 MAKE buttons, the slider box closed, the bar one row high
##   2 BUILD        a box pulled up, Repeat it, Round the edges: the record has all those steps
##   3 OPEN         Easy opens a 3-stop slider (0..2, step 1) inside the window
##   4 BEGINNER     slider dragged to Beginner: 7 MAKE buttons (5 advanced hidden), fewer visible buttons than Comfortable, record JSON equal, undo stack equal, step list still lists every step
##   5 COMFORTABLE  slider back to the middle: 12 MAKE buttons, record equal
##   6 EXPERT       slider to Expert: Expert screen, same record JSON, more visible buttons than Comfortable (Beginner < Comfortable < Expert)
##   7 REMEMBER     the level is on disk (re-read), a fresh load starts Beginner, and Easy reopened from Expert is still Beginner
## Shots: C:/Temp/claude/s093/{comfortable,slider_open,beginner,expert}.png
const SHOT := "C:/Temp/claude/s093"
const DIRT := "user://s093_test"

var fails := 0
var m: Node


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


## a real drag: press at a, move in steps to b (held), release
func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


## a real drag of the slider knob to value v
func drag_slider(s: HSlider, v: float) -> void:
	var r := s.get_global_rect()
	var y := r.get_center().y
	var gw := 24.0
	var p0 := Vector2(r.position.x + gw * 0.5 + (s.value - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw), y)
	var x1 := r.position.x + gw * 0.5 + (v - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw)
	await ev_move(p0, false)
	await ev_mouse(p0, true)
	for i in range(1, 25):
		await ev_move(Vector2(lerpf(p0.x, x1, i / 24.0), y))
	await ev_mouse(Vector2(x1, y), false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


## a world point (metres) on screen
func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func pu() -> PartUI:
	return m.bld.part


func ep():
	return pu().ep


## the replay volume in mm3
func vol() -> float:
	return float(pu().res.get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)


func bbox() -> AABB:   # mm
	var b: AABB = pu().res.get("aabb", AABB())
	return AABB(b.position / Part.MM, b.size / Part.MM)


func errors_of(rec: Dictionary) -> int:
	return Part.replay(rec)["errors"].size()


## an empty part, the camera above (pitch < 0) or below (pitch > 0) the floor
func fresh(pitch: float) -> void:
	m.S.part = Part.make("Part")
	pu().upto = -1
	pu().sync()
	m.target = Vector3(0.0, 0.0, 0.0)
	m.pitch = pitch
	m.yaw = 20.0
	m._cam()
	await idle(60)


## the Draw shape button, then a real drag on the floor from world a to world b (metres, y = 0)
func draw_floor(a: Vector3, b: Vector3) -> void:
	await click_ctl(ep().make_btns["draw"])
	await drag_screen(scr(a), scr(b))


## Pull it up, then the slider to h cm (the default is 2 cm)
func pull(h: float) -> void:
	await click_ctl(ep().make_btns["pull"])
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			await drag_slider(r["slider"], h)
	await idle(3)



const ADV := ["spin", "curve", "blend", "stick", "repeat"]


func make_visible() -> Array:
	var out := []
	for k in ep().make_btns:
		if (ep().make_btns[k] as Control).is_visible_in_tree():
			out.append(k)
	return out


## every visible button on screen (the step list buttons are steps, not tools)
func count_tools() -> int:
	var n := 0
	var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var st := [m]
	while not st.is_empty():
		var c: Node = st.pop_back()
		for k in c.get_children():
			st.append(k)
		if c is Button and (c as Button).is_visible_in_tree() and not String(c.name).begins_with("easypart_step_"):
			var r := (c as Button).get_global_rect()
			if r.size.x > 4.0 and r.size.y > 4.0 and vp.intersects(r):
				n += 1
	return n


## Expert's own tool buttons that are visible (PartUI.tool_btns), by name
func expert_tools() -> Array:
	var out := []
	for t in pu().tool_btns:
		var b := pu().tool_btns[t] as Control
		if b != null and b.is_visible_in_tree() and b.get_global_rect().size.x > 4.0:
			out.append(String(t))
	return out


func step_btns() -> int:
	var n := 0
	for c in ep().steps_vb.get_children():
		if (c as Control).is_visible_in_tree():
			n += 1
	return n


func cfg_level() -> int:
	var cf := ConfigFile.new()
	if cf.load(ep().level_file) != OK:
		return -1
	return int(cf.get_value("easy", "level", -1))


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
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	pu().set_on(false)
	pu().m.S.part = {}
	await process_frame
	await click_ctl(pu().part_btn)
	await click_ctl(pu().easy_open_btn)
	await idle(4)
	# a test-own settings file, empty: the default must be Comfortable
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIRT + "/level.cfg"))
	ep().level_file = DIRT + "/level.cfg"
	ep()._level_load()
	ep()._level_apply()
	await idle(3)
	await click_ctl(ep().empty_chip)
	await idle(4)
	m.pitch = -25.0
	m.yaw = 30.0
	m._cam()
	await idle(40)

	# 1 DEFAULT
	var mv := make_visible()
	var bar_r: Rect2 = ep().bar.get_global_rect()
	ok(ep().level == 1 and mv.size() == 12 and not ep().level_box.visible and bar_r.size.y <= float(m.TOP_H) + 1.0,
		"1 DEFAULT Comfortable: level %d, %d MAKE buttons visible, slider box closed, bar %.0f px high (TOP_H %d)" % [ep().level, mv.size(), bar_r.size.y, m.TOP_H])
	var tools_comf := count_tools()

	# 2 BUILD: a box, pulled up, Repeat it, Round the edges
	await draw_floor(Vector3(-0.05, 0.0, -0.05), Vector3(0.05, 0.0, 0.05))
	await pull(2.0)
	await click_ctl(ep().make_btns["repeat"])
	await click_ctl(ep().make_btns["round"])
	await idle(4)
	var feats_t := []
	for f in m.S.part.get("features", []):
		feats_t.append(String(f["t"]))
	var rec_json := JSON.stringify(m.S.part)
	var nfeat: int = feats_t.size()
	ok("pattern" in feats_t and "extrude" in feats_t and "sketch" in feats_t and Part.replay(m.S.part)["errors"].is_empty(), "2 BUILD record steps %s, no failed step" % str(feats_t))
	var steps_comf := step_btns()
	var undo_n: int = m.undo.size()
	tools_comf = count_tools()
	var n_comf := make_visible().size()
	print("info Comfortable tool buttons (%d): %s" % [n_comf, str(make_visible())])
	await shot("comfortable")

	# 3 OPEN: pressing Easy opens the slider
	await click_ctl(ep().easy_btn)
	await idle(3)
	var sl: HSlider = ep().level_slider
	var br: Rect2 = ep().level_box.get_global_rect()
	ok(ep().level_box.visible and sl.min_value == 0.0 and sl.max_value == 2.0 and sl.step == 1.0 and int(sl.value) == 1 and Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(br),
		"3 OPEN the Easy press opens a 3-stop slider (%s..%s step %s) at Comfortable, box %s inside the window" % [sl.min_value, sl.max_value, sl.step, br])
	await shot("slider_open")

	# 4 BEGINNER
	await drag_slider(sl, 0.0)
	await idle(3)
	mv = make_visible()
	var hidden_ok := true
	for k in ADV:
		if k in mv:
			hidden_ok = false
	var tools_beg := count_tools()
	var n_beg := mv.size()
	ok(ep().level == 0 and mv.size() == 7 and hidden_ok, "4 BEGINNER %d MAKE buttons: %s (hidden: %s)" % [mv.size(), str(mv), str(ADV)])
	ok(tools_beg < tools_comf, "4 BEGINNER visible buttons %d < Comfortable %d" % [tools_beg, tools_comf])
	ok(JSON.stringify(m.S.part) == rec_json and m.undo.size() == undo_n and (m.S.part["features"] as Array).size() == nfeat, "4 BEGINNER nothing deleted: record JSON equal, %d steps, undo stack %d" % [nfeat, m.undo.size()])
	ok(step_btns() == steps_comf and steps_comf >= 3, "4 BEGINNER the step list still lists every step (%d vs %d at Comfortable)" % [step_btns(), steps_comf])
	var rep_listed := false
	for c in ep().steps_vb.get_children():
		var tx := String((c as Button).text).to_lower()
		if tx.contains("repeat") or tx.contains("cop") or tx.contains("row"):
			rep_listed = true
	ok(rep_listed, "4 BEGINNER the hidden Repeat it step is listed in the step list")
	print("info Beginner tool buttons (%d): %s" % [mv.size(), str(mv)])
	var lay := []
	for k in mv:
		var r := (ep().make_btns[k] as Control).get_global_rect()
		if not Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(r) or r.size.x < 60.0:
			lay.append(k)
	ok(lay.is_empty(), "4 BEGINNER the seven buttons are inside the window and wide %s" % str(lay))
	await shot("beginner")

	# 5 COMFORTABLE again
	await drag_slider(sl, 1.0)
	await idle(3)
	mv = make_visible()
	ok(ep().level == 1 and mv.size() == 12 and count_tools() == tools_comf and JSON.stringify(m.S.part) == rec_json, "5 COMFORTABLE back: %d MAKE buttons, %d visible buttons (was %d), record equal" % [mv.size(), count_tools(), tools_comf])

	# 7 REMEMBER (before Expert): Beginner, saved, re-read
	await drag_slider(sl, 0.0)
	await idle(3)
	ok(cfg_level() == 0, "7 REMEMBER the settings file on disk says level %d (want 0 Beginner)" % cfg_level())
	ep().level = 1
	ep()._level_load()
	ep()._level_apply_buttons()
	ok(ep().level == 0 and make_visible().size() == 7, "7 REMEMBER a fresh load of the file starts Beginner: %d MAKE buttons" % make_visible().size())

	# 6 EXPERT: slider to the right stop
	await drag_slider(sl, 2.0)
	await idle(6)
	var tools_exp := count_tools()
	var ex := expert_tools()
	var ex_all: int = pu().tool_btns.size()
	print("info Expert tool buttons: %d on the bar now %s, %d in all (the rest sit under the ribbon captions)" % [ex.size(), str(ex), ex_all])
	ok(not pu().easy and pu().browser.visible and not ep().panel.visible, "6 EXPERT the slider's right stop opens the Expert screen")
	ok(JSON.stringify(m.S.part) == rec_json and pu().tl_btns.size() >= nfeat, "6 EXPERT the same record (JSON equal), the timeline shows %d buttons for %d steps" % [pu().tl_btns.size(), nfeat])
	ok(n_beg < n_comf and n_comf < ex_all, "6 ORDER tool buttons Beginner %d < Comfortable %d < Expert %d (Expert: every tool of its ribbon, %d showing on the bar before a caption is opened)" % [n_beg, n_comf, ex_all, ex.size()])
	ok(cfg_level() == 0, "6 the drag from Beginner past Comfortable to Expert left the Easy level on disk at Beginner (%d)" % cfg_level())
	await shot("expert")
	await click_ctl(pu().easy_open_btn)
	await idle(4)
	ok(pu().easy and ep().level == 0 and make_visible().size() == 7 and JSON.stringify(m.S.part) == rec_json, "7 REMEMBER back from Expert the Easy screen is still Beginner (%d MAKE buttons), same record" % make_visible().size())
	# leave no setting behind
	ep().level = 1
	ep()._level_save(1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIRT + "/level.cfg"))
	print("s093: %d fail" % fails)
	quit(1 if fails > 0 else 0)
