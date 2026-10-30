extends SceneTree
## NWHYCANT (Nick, Friday plan item 87, "Why can't I?"): a beginner from the REAL start screen (BUILDING card, Easy) walks the live Easy Part
## with real clicks at 1280 x 720. In three states (a blank part, a sketch drawn but not pulled, a one-part solid) every VISIBLE disabled
## button on the Easy Part page is counted from the built scene tree (never from the code's own variables). A greyed button must say in one
## line what to do first: the reason after the grey tag must be non-empty, one line, and short enough to read at a glance.
##   W0 the walk reaches a blank Easy Part (the BUILD page, Easy on, no chooser open)
##   W1 blank part: every disabled visible button on the page has a reason (count of bare greyed buttons = 0)
##   W2 sketch drawn, not pulled: every disabled visible button has a reason (count = 0)
##   W3 one solid: every disabled visible button has a reason (count = 0)
##   W4 every reason in all three states is one line, at most 100 characters
##   W5 the reasons use no kernel jargon (sketch words are plain: no extrude, loft, boolean, feature, kernel, fillet, revolve)
## shots: C:/Temp/claude/nwhycant/open.png, sketch.png, solid.png
const SHOT := "C:/Temp/claude/nwhycant"
const DIRT := "user://nwhycant_test"
const TAG := "\nNOT NOW: "
const STEPS := ["Restart", "Reinstall", "Turn", "Pick", "Draw", "Click", "Press", "Make", "Put", "Start", "Open", "Choose", "Reset"]
const JARGON := ["extrude", "loft", "boolean", "feature", "kernel", "fillet", "revolve", "sweep", "shell"]
var fails := 0
var m: Node
var bare := {}        # state -> the names of disabled visible buttons with no reason
var long_lines := []  # reasons that are two lines or longer than 100 characters
var jargon_hits := []
var reasons_seen := 0


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


## every visible disabled button under the Easy Part page's boxes, read from the scene tree
func page_roots(ep) -> Array:
	var out := []
	for nm in ["bar", "make_box", "panel", "shape_box", "repeat_box", "tilt_box", "screw_box", "stick_box", "hole_box", "split_box", "round_box", "colour_box", "hint", "status"]:
		var v = ep.get(nm)
		if v is Control and (v as Control).is_visible_in_tree():
			out.append(v)
	return out


func audit(ep, state: String) -> void:
	var names := []
	var seen := {}
	for r in page_roots(ep):
		for c in (r as Node).find_children("*", "BaseButton", true, false):
			var b := c as BaseButton
			if seen.has(b) or not b.is_visible_in_tree() or not b.disabled:
				continue
			seen[b] = true
			var tip := String(b.tooltip_text)
			var why := ""
			if tip.find(TAG) >= 0:
				why = tip.get_slice(TAG, 1).strip_edges()
			if why == "":
				names.append(b.name if b.name != "" else b.text)
			else:
				reasons_seen += 1
				if why.find("\n") >= 0 or why.length() > 100:
					long_lines.append("%s: %s" % [state, b.name])
				for j in JARGON:
					if why.to_lower().find(j) >= 0:
						jargon_hits.append("%s/%s" % [b.name, j])
	bare[state] = names
	print("%s: %d disabled visible buttons without a reason %s" % [state, names.size(), str(names)])


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
	var pu = m.bld.part
	var chooser_open: bool = m.build_choose != null and m.build_choose.open
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	var ep = pu.ep
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 40.0
	m.yaw = 25.0
	m._cam()
	await idle(60)
	ok(m.cur_page == "BUILD" and pu.on and not chooser_open and ep.active(),
		"W0 the BUILDING card, one click, a blank Easy Part (page %s, chooser %s)" % [m.cur_page, chooser_open])
	await shot("open")
	audit(ep, "blank")

	# the sketch: Draw shape, Box, drag a box on the grid (not pulled yet)
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_pts([scr(Vector3(-0.02, 0.0, -0.02)), scr(Vector3(0.02, 0.0, 0.02))])
	await idle(10)
	await shot("sketch")
	audit(ep, "sketch")

	# the solid: Pull it up
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	await shot("solid")
	audit(ep, "solid")

	ok(bare["blank"].size() == 0, "W1 blank part: every greyed button says why (%d bare: %s)" % [bare["blank"].size(), str(bare["blank"])])
	ok(bare["sketch"].size() == 0, "W2 sketch drawn: every greyed button says why (%d bare: %s)" % [bare["sketch"].size(), str(bare["sketch"])])
	ok(bare["solid"].size() == 0, "W3 one solid: every greyed button says why (%d bare: %s)" % [bare["solid"].size(), str(bare["solid"])])
	ok(long_lines.is_empty() and reasons_seen > 0, "W4 every reason is one line of at most 100 characters (%d reasons read, %d too long: %s)" % [reasons_seen, long_lines.size(), str(long_lines)])
	ok(jargon_hits.is_empty(), "W5 no kernel jargon in the reasons (%s)" % str(jargon_hits))

	# the no-DLL beginner: the engine is off for this session; the live page greys its buttons
	Part.force_off = true
	await idle(20)
	bare.clear()
	long_lines.clear()
	jargon_hits.clear()
	reasons_seen = 0
	audit(ep, "nodll")
	var grey_n := 0
	var steps := []
	var bad_step := []
	var bad_words := []
	for r in page_roots(ep):
		for c in (r as Node).find_children("*", "BaseButton", true, false):
			var b := c as BaseButton
			if b.is_visible_in_tree() and b.disabled:
				grey_n += 1
				var why := String(b.tooltip_text).get_slice(TAG, 1).strip_edges()
				if why != "":
					var first := why.get_slice(" ", 0)
					if STEPS.find(first) < 0:
						bad_step.append("%s: %s" % [b.name, first])
					for w in ["kernel", "dll", "native", ".md", "see "]:
						if why.to_lower().find(w) >= 0:
							bad_words.append("%s/%s" % [b.name, w])
	var draw_btn: Button = ep.make_btns["draw"]
	var said_grey := ""
	if draw_btn.disabled:
		await click_ctl(draw_btn)
		said_grey = String(ep.msg)
	await shot("nodll")
	ok(grey_n >= 3, "X0 the no-DLL page greys its buttons (%d disabled visible)" % grey_n)
	ok(bare["nodll"].size() == 0, "X1 every greyed button says why (%d bare: %s)" % [bare["nodll"].size(), str(bare["nodll"])])
	ok(long_lines.is_empty() and reasons_seen > 0, "X2 every reason is one line of at most 100 characters (%d read, %d too long: %s)" % [reasons_seen, long_lines.size(), str(long_lines)])
	ok(bad_step.is_empty(), "X3 every reason starts with a plain step word (%s)" % str(bad_step))
	ok(bad_words.is_empty(), "X4 no reason names the engine, a library file or a doc path (%s)" % str(bad_words))
	ok(draw_btn.disabled and said_grey.strip_edges() != "" and said_grey.find("
") < 0 and said_grey.length() <= 100,
		"X5 a click on a greyed Draw shape says why in one line (status: %s)" % said_grey)

	print("NWHYCANT %d fails" % fails)
	quit(1 if fails > 0 else 0)
