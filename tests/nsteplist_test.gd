extends SceneTree
## NSTEPLIST (Friday plan item 88, Nick: monkey-brain easy): the step list on the side of Easy Part, in plain words ("Pulled up 3 cm",
## "Rounded 4 edges 2 mm"). A click on a step reopens it to change; the change replays the later steps. Real clicks at 1280 x 720 from the
## real start screen, on the live Easy Part. Every number is measured from the BUILT result (Part.replay with faces and props), never from
## the code's own variables; the step words are read off the screen.
##   S0 the BUILDING card, one click; Easy; Draw shape + Box chip + drag a 40 mm box on the grid + Pull it up
##   S1 the How far slider set to 3 cm by a click on its track: the built height is 30 mm (+-0.3)
##   S2 Round the edges with the Only the top chip (4 top edges), the How round slider to 2 mm by a click: the built top edges are rounded
##      (the volume lost to the rounds is (1 - pi/4) r^2 x the top perimeter, r = 2 mm, within 15 pct)
##   S3 the step list (easypart_steps) names the steps in order: "Pulled up 3 cm", then "Rounded 4 edges 2 mm"; each has an icon; no jargon
##   S4 a click on the "Pulled up 3 cm" step reopens it (its slider reads How far, about 3 cm); a click on the track to 5 cm:
##      the built height is 50 mm (+-0.3), the rounds still there (same loss within 15 pct), the list says "Pulled up 5 cm"
##      and "Rounded 4 edges 2 mm" still, and that change is exactly ONE undo step
##   S5 Ctrl+Z takes that change back: the built height is 30 mm again and the list says "Pulled up 3 cm"
## shots: C:/Temp/claude/nsteplist/open.png, steps.png, reopen.png
const SHOT := "C:/Temp/claude/nsteplist"
const DIRT := "user://nsteplist_test"
const JARGON := ["sketch", "extrude", "fillet", "feature", "kernel", "shell", "loft", "boolean", "profile"]
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
	if c == null:
		fails += 1
		print("FAIL a control to click is missing")
		return
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


func solid() -> Dictionary:
	return Part.replay(m.S.part, -1, {"faces": true, "props": true})


func mm(v: float) -> float:
	return v / Part.MM


func find_named(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var f := find_named(c, nm)
		if f != null:
			return f
	return null


## the newest step's slider (How far, How round, Thickness...), or null
func last_slider() -> HSlider:
	return find_named(m, "easypart_slider_last") as HSlider


func last_label() -> String:
	var sl := last_slider()
	if sl == null:
		return ""
	for c in sl.get_parent().find_children("*", "Label", true, false):
		var t := String((c as Label).text)
		if t == "How far" or t == "How round" or t == "Thickness":
			return t
	return ""


func step_buttons() -> Array:
	var box := find_named(m, "easypart_steps")
	if box == null:
		return []
	return box.find_children("*", "Button", true, false)


## the plain words of the step list: one string per step row (the row's button text), in order
func step_words() -> Array:
	var out := []
	for b in step_buttons():
		out.append(String((b as Button).text))
	return out


func grab_w(sl: HSlider) -> float:
	var g := sl.get_theme_icon("grabber")
	return float(g.get_width()) if g != null else 16.0


## a real click on the slider's track at value v (the grabber centre sits at v; the track's ends keep half a grabber in)
func slide_to(sl: HSlider, v: float) -> void:
	if sl == null:
		fails += 1
		print("FAIL no slider to move")
		return
	var g := grab_w(sl)
	var frac := (v - sl.min_value) / (sl.max_value - sl.min_value)
	var lx := g * 0.5 + frac * (sl.size.x - g)
	var p := sl.get_global_rect().position + Vector2(lx, sl.size.y * 0.5)
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_move(p)
	await ev_mouse(p, false)
	await idle(12)


## the solid's total volume (mm3), from the built bodies
func vol_mm3(s: Dictionary) -> float:
	var tot := 0.0
	for v in s.get("volumes", []):
		tot += float(v)
	return tot / (Part.MM * Part.MM * Part.MM)


## the loss of the rounds on the top four edges of a W x D box (mm3): (1 - pi/4) r^2 x the top perimeter
func round_loss(W: float, D: float, r: float) -> float:
	return (1.0 - PI / 4.0) * r * r * (2.0 * W + 2.0 * D)


func ctrl_z() -> void:
	var e := InputEventKey.new()
	e.pressed = true
	e.keycode = KEY_Z
	e.physical_keycode = KEY_Z
	e.key_label = KEY_Z
	e.unicode = 122
	e.ctrl_pressed = true
	root.push_input(e)
	await idle(20)


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
	var note_words := String(pu.note_l.text) if pu.note_l != null else ""
	ok(m.cur_page == "BUILD" and pu.on and not chooser_open and note_words.find("Easy") >= 0,
		"S0a BUILDING card, one click, a blank part, words name Easy (page %s, chooser %s)" % [m.cur_page, chooser_open])
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	var ep = pu.ep
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 40.0
	m.yaw = 25.0
	m._cam()
	await idle(60)

	# S0 the box: Draw shape, Box chip, drag 40 mm on the grid, Pull it up
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_pts([scr(Vector3(-0.02, 0.0, -0.02)), scr(Vector3(0.02, 0.0, 0.02))])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)

	# S1 How far to 3 cm by a click on its track
	await slide_to(last_slider(), 3.0)
	var s1 := solid()
	var bb1: AABB = s1["aabb"]
	ok(int(s1["bodies"]) == 1 and absf(mm(bb1.size.y) - 30.0) <= 0.3,
		"S1 the pull is 3 cm tall: built height %.2f mm (want 30 +-0.3), %d body" % [mm(bb1.size.y), int(s1["bodies"])])
	await shot("open")

	# S2 Round the edges, Only the top, then How round to 2 mm
	await click_ctl(ep.round_btns["top"])
	await click_ctl(ep.make_btns["round"])
	await idle(10)
	await slide_to(last_slider(), 0.2)
	var s2 := solid()
	var bb2: AABB = s2["aabb"]
	var W := mm(bb2.size.x)
	var D := mm(bb2.size.z)
	var box_v := W * D * mm(bb2.size.y)
	var lost := box_v - vol_mm3(s2)
	var want_lost := round_loss(W, D, 2.0)
	ok(absf(lost - want_lost) <= 0.15 * want_lost,
		"S2 the top edges are rounded 2 mm: %.1f mm3 lost (want %.1f, 15 pct), box %.1f x %.1f mm" % [lost, want_lost, W, D])

	# S3 the step list in plain words
	var words := step_words()
	var pi_at := -1
	var ro_at := -1
	for i in words.size():
		var w := String(words[i]).to_lower()
		if w.find("pulled up 3 cm") >= 0 and pi_at < 0:
			pi_at = i
		if w.find("rounded 4 edges 2 mm") >= 0 and ro_at < 0:
			ro_at = i
	var icons := words.size() > 0
	for b in step_buttons():
		if (b as Button).icon == null:
			icons = false
	var bad := ""
	for w in words:
		for j in JARGON:
			if String(w).to_lower().find(j) >= 0:
				bad = j
	ok(pi_at >= 0 and ro_at > pi_at and icons and bad == "",
		"S3 the step list reads in order: Pulled up 3 cm, then Rounded 4 edges 2 mm; icons %s, jargon [%s] (list %s)" % [icons, bad, str(words)])
	await shot("steps")

	# S4 reopen the pull by a click on its step, then How far to 5 cm
	var pull_btn: Button = null
	for b in step_buttons():
		if String((b as Button).text).to_lower().find("pulled up 3 cm") >= 0:
			pull_btn = b
	await click_ctl(pull_btn)
	var reopened := last_label() == "How far" and last_slider() != null and absf(last_slider().value - 3.0) <= 0.21
	var ub4: int = m.undo.size()
	await slide_to(last_slider(), 5.0)
	var s4 := solid()
	var bb4: AABB = s4["aabb"]
	var W4 := mm(bb4.size.x)
	var D4 := mm(bb4.size.z)
	var lost4 := W4 * D4 * mm(bb4.size.y) - vol_mm3(s4)
	var want4 := round_loss(W4, D4, 2.0)
	var has5 := false
	var has_r := false
	for w in step_words():
		if String(w).to_lower().find("pulled up 5 cm") >= 0:
			has5 = true
		if String(w).to_lower().find("rounded 4 edges 2 mm") >= 0:
			has_r = true
	ok(reopened and absf(mm(bb4.size.y) - 50.0) <= 0.3,
		"S4a a click on the pull's step reopens it (How far %s), the change makes it 5 cm: built height %.2f mm (want 50 +-0.3)" % [last_label(), mm(bb4.size.y)])
	ok(absf(lost4 - want4) <= 0.15 * want4 and has5 and has_r,
		"S4b the change replays the rounds: %.1f mm3 lost (want %.1f), list has Pulled up 5 cm %s and Rounded 4 edges 2 mm %s" % [lost4, want4, has5, has_r])
	ok(m.undo.size() == ub4 + 1, "S4c the reopen change is ONE undo step (undo %d -> %d)" % [ub4, m.undo.size()])
	await shot("reopen")

	# S5 Ctrl+Z takes it back
	await ctrl_z()
	var s5 := solid()
	var bb5: AABB = s5["aabb"]
	var back3 := false
	for w in step_words():
		if String(w).to_lower().find("pulled up 3 cm") >= 0:
			back3 = true
	ok(absf(mm(bb5.size.y) - 30.0) <= 0.3 and back3,
		"S5 Ctrl+Z takes the change back: built height %.2f mm (want 30), list says Pulled up 3 cm %s" % [mm(bb5.size.y), back3])

	print("NSTEPLIST %d fails" % fails)
	quit(1 if fails > 0 else 0)
