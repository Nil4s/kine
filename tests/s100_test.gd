extends SceneTree
## godot --path . --position 4000,4000 -s tests/s100_test.gd     (P100 KEYBOARD SHORTCUTS CARD in Easy Part; scripts/key_tips.gd; needs the CAD DLL)
## Real clicks and real key presses at 1280 x 720. The card is read from the screen (its Label, its rect), the state from the settings file on disk.
##   1 CARD     3 Undo clicks: the card shows "Tip: Ctrl+Z does Undo"
##   2 RECT     the card's rect overlaps no visible control (nor the part) at 1280 x 720
##   3 LEARN    pressing Ctrl+Z: the card hides, learned is on disk
##   4 GOTIT    3 Redo clicks (after the 2 minutes): the Ctrl+Y card; Got it hides it
##   5 GAP      a 3rd action (Pull it up x3) within 2 minutes of the last card: no card; after 2 minutes the next click shows it
##   6 RESTART  settings re-read from disk: Undo clicks show no card again; the file names undo, redo, pull as taught
##   7 DRAG     3 Mirror that clicks during a drag: no card; the next click after the drag shows it
##   8 LIST     the Shortcuts list holds >= 10 entries and each key does its job on one sample
const SHOT := "C:/Temp/claude/s100"
const DIRT := "user://s100_test"
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


func key(code: int, ctrl := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code as Key
		e.physical_keycode = code as Key
		e.pressed = down
		e.ctrl_pressed = ctrl
		root.push_input(e, true)
		await process_frame
	await idle(2)


func press(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func draw_floor(a: Vector3, b: Vector3) -> void:
	var pa := scr(a)
	var pb := scr(b)
	await ev_move(pa, false)
	await ev_mouse(pa, true)
	for i in range(1, 13):
		await ev_move(pa.lerp(pb, i / 12.0))
	await ev_mouse(pb, false)
	await idle(3)


## the floor point under a screen point (metres)
func floor_at(p: Vector2) -> Vector3:
	var o: Vector3 = m.cam.project_ray_origin(p)
	var d: Vector3 = m.cam.project_ray_normal(p)
	var h: Variant = Plane(Vector3.UP, 0.0).intersects_ray(o, d)
	return h if h != null else Vector3.ZERO


func fresh() -> void:
	m.S.part = Part.make("Part")
	pu().upto = -1
	pu().sync()
	m.target = Vector3(0.0, 0.0, 0.0)
	m.pitch = -40.0
	m.yaw = 20.0
	m._cam()
	await idle(60)


func pu() -> PartUI:
	return m.bld.part


func ep():
	return pu().ep


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func nsteps() -> int:
	return (ep()._rec().get("features", []) as Array).size()


func kt() -> KeyTips:
	return ep().kt


func card_up() -> bool:
	return kt().card.visible and kt().card.is_visible_in_tree()


func clicks(b: Control, n: int) -> void:
	for i in n:
		await press(b)


func disk() -> Dictionary:
	var cf := ConfigFile.new()
	var out := {"taught": [], "learned": []}
	if cf.load(m.settings) == OK:
		out["taught"] = Array(cf.get_value("keytips", "taught", PackedStringArray()))
		out["learned"] = Array(cf.get_value("keytips", "learned", PackedStringArray()))
	return out


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


## every visible control the card sits on (empty = none)
func overlaps() -> Array:
	var out := []
	var cr := kt().card.get_global_rect()
	var vp := root.get_visible_rect()
	for c in m.find_children("*", "Control", true, false):
		var n := c as Control
		if n == kt().card or kt().card.is_ancestor_of(n) or n.is_ancestor_of(kt().card) or not n.is_visible_in_tree():
			continue
		if not (n is BaseButton or n is Range or n is LineEdit or n is Label or n is PanelContainer):
			continue
		var r := n.get_global_rect()
		if r.size.x * r.size.y > vp.size.x * vp.size.y * 0.4 or r.size.x < 2.0 or r.size.y < 2.0:
			continue
		if r.intersects(cr):
			out.append("%s %s" % [n.name, str(r)])
	var pr: Rect2 = kt().part_rect()
	if pr.size != Vector2.ZERO and pr.intersects(cr):
		out.append("the part %s" % str(pr))
	return out


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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	m.settings = DIRT + "/settings.cfg"   # the test's own settings, never the user's
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
	var ss: StartScreen = m.start_screen
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await press(ss._cards["building"])
	await idle(3)
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
	await press(pu().part_btn)
	await idle(3)
	await press(pu().easy_open_btn)
	await idle(4)
	await fresh()
	kt().reload()
	kt().fake_ms = 1000

	# build three steps with real clicks: Draw shape + a drag, Pull it up, Mirror that
	await press(ep().make_btns["draw"])
	await draw_floor(Vector3(-0.12, 0.0, -0.06), Vector3(-0.08, 0.0, -0.02))
	await press(ep().make_btns["pull"])
	await press(ep().make_btns["mirror"])
	print("built steps: %d" % nsteps())

	# 1 CARD
	await clicks(ep().undo_btn, 2)
	ok(not card_up(), "1 CARD two Undo clicks: no card yet")
	await press(ep().undo_btn)
	ok(card_up() and kt().tip_l.text == "Tip: Ctrl+Z does Undo", "1 CARD third Undo click: the card says '%s'" % kt().tip_l.text)
	ok(kt().ok_btn.is_visible_in_tree() and kt().ok_btn.text == "Got it", "1 CARD a Got it button is on the card")
	# 2 RECT
	await idle(3)
	var ov := overlaps()
	ok(ov.is_empty(), "2 RECT the card %s overlaps nothing %s" % [str(kt().card.get_global_rect()), str(ov)])
	var cr := kt().card.get_global_rect()
	ok(cr.position.x < 640.0 and cr.position.y > 360.0 and cr.end.y <= ep().status.get_global_rect().position.y, "2 RECT the card is bottom-left, above the status line (%s, status top %.0f)" % [str(cr), ep().status.get_global_rect().position.y])
	await shot("card")
	# 3 LEARN
	await key(KEY_Z, true)
	ok(not card_up() and kt().learned.has("undo") and "undo" in disk()["learned"], "3 LEARN Ctrl+Z pressed: the card is gone, learned on disk %s" % str(disk()["learned"]))

	# 4 GOTIT
	kt().fake_ms += 130000
	await clicks(ep().redo_btn, 3)
	ok(card_up() and kt().tip_l.text == "Tip: Ctrl+Y does Redo", "4 GOTIT three Redo clicks: '%s'" % kt().tip_l.text)
	await press(kt().ok_btn)
	ok(not card_up(), "4 GOTIT Got it hides the card")

	# 5 GAP
	kt().fake_ms += 130000
	await clicks(ep().make_btns["hole"], 3)
	ok(card_up() and kt().tip_l.text == "Tip: H does Cut a hole", "5 GAP (after 2 minutes) three Cut a hole clicks: '%s'" % kt().tip_l.text)
	await press(kt().ok_btn)
	kt().fake_ms += 10000
	await clicks(ep().make_btns["pull"], 3)
	ok(not card_up() and not kt().taught.has("pull"), "5 GAP a 4th action (Pull it up x3) 10 s after the last card: no card")
	kt().fake_ms += 130000
	await press(ep().make_btns["pull"])
	ok(card_up() and kt().tip_l.text == "Tip: P does Pull it up", "5 GAP after 2 minutes the next click shows it: '%s'" % kt().tip_l.text)
	await press(kt().ok_btn)

	# 6 RESTART
	var d := disk()
	ok("undo" in d["taught"] and "redo" in d["taught"] and "pull" in d["taught"] and "hole" in d["taught"], "6 RESTART the file names %s as taught" % str(d["taught"]))
	kt().reload()
	kt().fake_ms = 900000
	await clicks(ep().undo_btn, 4)
	ok(not card_up() and kt().taught.has("undo"), "6 RESTART after reload four Undo clicks: no Ctrl+Z card")
	await clicks(ep().redo_btn, 3)
	ok(not card_up(), "6 RESTART after reload three Redo clicks: no Ctrl+Y card")

	# 7 DRAG
	kt().fake_ms += 130000
	ep()._drag = {"k": 1}
	await clicks(ep().make_btns["mirror"], 3)
	var during := card_up()
	ep()._drag = {}
	ok(not during, "7 DRAG three Mirror that clicks during a drag: no card")
	await press(ep().make_btns["mirror"])
	ok(card_up() and kt().tip_l.text == "Tip: M does Mirror that", "7 DRAG the next click after the drag: '%s'" % kt().tip_l.text)
	await press(kt().ok_btn)

	# 8 LIST
	await fresh()
	var good := []
	var bad := []
	await key(KEY_D)
	(good if ep().armed == "draw" else bad).append("D armed=%s" % ep().armed)
	# Esc: half a drawn shape is cancelled (drawn low on the screen, under the chips Draw shape opens)
	var wa := floor_at(Vector2(520, 440))
	var wb := floor_at(Vector2(650, 520))
	var pa := scr(wa)
	await ev_move(pa, false)
	await ev_mouse(pa, true)
	for i in range(1, 6):
		await ev_move(pa.lerp(scr(wb), i / 6.0))
	var had: bool = not ep()._draft.is_empty()
	await key(KEY_ESCAPE)
	var cancelled: bool = had and ep()._draft.is_empty()
	await ev_mouse(pa, false)
	await idle(3)
	(good if cancelled else bad).append("Esc had draft %s, then empty %s" % [str(had), str(ep()._draft.is_empty())])
	if ep().armed != "draw":
		await key(KEY_D)
	await draw_floor(wa, wb)
	var n0 := nsteps()
	await key(KEY_P)
	(good if nsteps() == n0 + 1 else bad).append("P steps %d -> %d" % [n0, nsteps()])
	n0 = nsteps()
	await key(KEY_M)
	(good if nsteps() == n0 + 1 else bad).append("M steps %d -> %d" % [n0, nsteps()])
	await key(KEY_H)
	(good if ep().hole_box.visible else bad).append("H hole box visible=%s" % str(ep().hole_box.visible))
	# the same state undone by the Undo BUTTON (one click) and then by Ctrl+Z: both must take the same number of steps (a shortcut that fires twice would take more)
	n0 = nsteps()
	var u0: int = m.undo.size()
	await press(ep().undo_btn)
	var btn_lost := n0 - nsteps()
	var btn_stack: int = u0 - m.undo.size()
	await press(ep().redo_btn)
	ok(nsteps() == n0, "8 UNDO-BUTTON one click: steps %d -> %d (lost %d), undo stack %d -> %d; Redo click puts them back (%d)" % [n0, n0 - btn_lost, btn_lost, u0, u0 - btn_stack, nsteps()])
	u0 = m.undo.size()
	await key(KEY_Z, true)
	var key_lost := n0 - nsteps()
	var key_stack: int = u0 - m.undo.size()
	ok(key_lost == btn_lost and key_stack == btn_stack and key_stack == 1, "8 CTRL+Z-ONCE one press loses %d steps (button lost %d), undo stack moved %d (button %d): the key fires once" % [key_lost, btn_lost, key_stack, btn_stack])
	(good if key_lost > 0 else bad).append("Ctrl+Z steps %d -> %d" % [n0, nsteps()])
	n0 = nsteps()
	u0 = m.undo.size()
	await key(KEY_Y, true)
	(good if m.undo.size() == u0 + 1 and nsteps() > n0 else bad).append("Ctrl+Y undo stack %d -> %d, steps %d -> %d" % [u0, m.undo.size(), n0, nsteps()])
	n0 = nsteps()
	await key(KEY_DELETE)
	(good if nsteps() == n0 - 1 else bad).append("Delete steps %d -> %d" % [n0, nsteps()])
	await key(KEY_S)
	var srch: bool = m.ui_cmd.visible
	(good if srch else bad).append("S search visible=%s" % str(srch))
	m.ui_cmd.visible = false
	await idle(2)
	await key(KEY_1)
	await idle(30)
	var y1: float = m.yaw
	var p1: float = m.pitch
	await key(KEY_2)
	await idle(30)
	var y2: float = m.yaw
	await key(KEY_3)
	await idle(30)
	var p3: float = m.pitch
	(good if absf(y1) < 2.0 and p1 > -20.0 else bad).append("1 front yaw %.1f pitch %.1f" % [y1, p1])
	(good if absf(y2 + 90.0) < 2.0 else bad).append("2 left yaw %.1f" % y2)
	(good if p3 < -80.0 else bad).append("3 top pitch %.1f" % p3)
	await press(ep().easy_btn)
	var sb := root.find_child("easypart_shortcuts_btn", true, false) as Button
	if sb != null and sb.is_visible_in_tree():
		await press(sb)
	var lb := root.find_child("easypart_keys_list", true, false) as Control
	var rows := 0
	if lb != null and lb.is_visible_in_tree():
		for c in lb.find_children("key_*", "Label", true, false):
			if (c as Label).is_visible_in_tree():
				rows += 1
	ok(rows >= 10, "8 LIST the Shortcuts list shows %d entries" % rows)
	await shot("list")
	if lb != null:
		lb.visible = false
	ep().level_box.visible = false
	print("keys good: %s" % str(good))
	ok(bad.is_empty() and good.size() >= 10, "8 LIST %d of the listed keys did their job on one sample, failed: %s" % [good.size(), str(bad)])
	print("s100: %d fail" % fails)
	quit(1 if fails > 0 else 0)
