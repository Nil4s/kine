extends SceneTree
## s240 FRAMED FLOOR OVERLAP (Easy Parts). A fresh Easy part + Fit view puts the 1 m floor grid in the free view; its four corners must be on screen,
## inside the free view, and not under any Easy-mode control. A deliberately zoomed-in camera must fail the same bars (control test).
## The Challenges card must be gone once its challenge is closed, and must not come back on a fresh part.
## Shots: C:/Temp/claude/s240/ (S240_SHOT overrides)
var fails := 0
var m: Node
var SHOT := OS.get_environment("S240_SHOT") if OS.get_environment("S240_SHOT") != "" else "C:/Temp/claude/s240"
const DIRT := "user://s240_test"
const SIZES := [[1280, 720], [1024, 600]]
const E := 0.5   # the floor grid's half side (m)
var pu: PartUI
var ep


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


func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
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


func settle() -> void:
	var nn := 0
	while not ep._ease.is_empty() and nn < 300:
		await process_frame
		nn += 1
	await idle(8)


func corners() -> Array:
	var out := []
	for cx in [-E, E]:
		for cz in [-E, E]:
			out.append(m.cam.unproject_position(Vector3(cx, 0.0, cz)))
	return out


## every visible Easy-mode control whose rect holds p: buttons, labels with text, sliders, line edits, panels and anything that takes the mouse.
## Containers that ignore the mouse and are not panels are layout only. A control as big as the window is a backdrop, not a cover.
func covering(p: Vector2) -> Array:
	var out := []
	_cov(ep.panel.get_parent(), p, root.get_visible_rect(), out)
	return out


func _cov(n: Node, p: Vector2, vr: Rect2, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Control:
		var c := n as Control
		var r := c.get_global_rect()
		var leaf := c is Button or c is LineEdit or c is Range or c is TextureRect or (c is Label and (c as Label).text.strip_edges() != "")
		var pan := c is PanelContainer or c is Panel or c is ScrollContainer
		var stop := c.mouse_filter == Control.MOUSE_FILTER_STOP
		if (leaf or pan or stop) and r.size.x > 1.0 and r.size.y > 1.0 and r.size.x < vr.size.x * 0.9 and r.has_point(p) and c.modulate.a > 0.05:
			out.append("%s %s" % [String(c.name) if String(c.name) != "" else c.get_class(), r])
	for ch in n.get_children():
		_cov(ch, p, vr, out)


## the framed floor, measured: corners on screen, inside the free view, not covered. expect_framed false: counts the corners that fail one of the three.
func floor_bars(tag: String, expect_framed: bool) -> int:
	var cs := corners()
	var fr: Rect2 = ep.free_rect()
	var vr := root.get_visible_rect()
	var flagged := 0
	print("     FLOOR %s free_rect %s" % [tag, fr])
	for i in cs.size():
		var p: Vector2 = cs[i]
		var onscr := vr.has_point(p)
		var infree := fr.grow(1.0).has_point(p)
		var cv := covering(p)
		print("     CORNER %s #%d at %s on-screen %s in-free-view %s covered by %s" % [tag, i, p, onscr, infree, cv])
		if not (onscr and infree and cv.is_empty()):
			flagged += 1
		if expect_framed:
			ok(onscr, "%s corner %d %s is on screen" % [tag, i, p])
			ok(infree, "%s corner %d %s is inside the free view %s" % [tag, i, p, fr])
			ok(cv.is_empty(), "%s corner %d is under no control: %s" % [tag, i, cv])
	return flagged


func fresh_part() -> void:
	m.S.part = {}
	pu.sync()
	await idle(8)


func run_size(w: int, h: int) -> void:
	await size_to(w, h)
	await fresh_part()
	await settle()
	var tag := "%dx%d fresh" % [w, h]
	await shot("fresh_%dx%d" % [w, h])
	floor_bars(tag, true)
	var fit := root.find_child("easypart_view_fit", true, false) as Button
	ok(fit != null, "%s the Fit view button exists" % tag)
	if fit != null:
		await click_ctl(fit)
		await settle()
	await shot("fit_%dx%d" % [w, h])
	floor_bars("%dx%d fit" % [w, h], true)


func control(w: int, h: int) -> void:
	await size_to(w, h)
	# a deliberately zoomed-in camera puts the corners off screen, so these bars can fail
	m.dist = 0.05
	m._cam()
	print("     CONTROL camera dist %.3f" % float(m.dist))
	var nf := floor_bars("%dx%d zoomed" % [w, h], false)
	ok(nf == 4, "%dx%d control: the zoomed-in camera fails the bars at all 4 corners (%d of 4 flagged)" % [w, h, nf])
	await shot("zoomed_%dx%d" % [w, h])


func chip(nm: String) -> Button:
	return root.find_child(nm, true, false) as Button


func challenge_run() -> void:
	await size_to(1280, 720)
	await fresh_part()
	var card = ep.challenge_card
	await click_ctl(chip("easypart_chip_parts"))
	await open_group_of(chip("easypart_challenges"))
	await click_ctl(chip("easypart_challenges"))
	ok(card.visible and card.modulate.a > 0.5, "challenge: the card is up after the chip")
	await click_ctl(chip("easypart_challenge_check"))
	await shot("challenge_open")
	await click_ctl(chip("easypart_challenge_close"))
	await idle(4)
	ok(not card.visible, "challenge: the card is hidden after Close")
	ok(not chip("easypart_challenges").button_pressed, "challenge: the Challenges chip is released after Close")
	# a card left open, then a fresh part: the card is gone
	m.S.part = EasyChallenge.target_record("stand").duplicate(true)
	pu.sync()
	await idle(6)
	await open_group_of(chip("easypart_challenges"))
	await click_ctl(chip("easypart_challenges"))
	ok(card.visible, "challenge: the card reopens over a built part")
	await idle(4)
	await fresh_part()
	await settle()
	print("     CARD after a fresh part: visible %s rect %s" % [card.visible, card.get_global_rect()])
	ok(not card.visible, "challenge: a fresh part closes the card")
	# the card left up while Easy is left: it is gone when Easy comes back
	await open_group_of(chip("easypart_challenges"))
	await click_ctl(chip("easypart_challenges"))
	ok(card.visible, "challenge: the card is up again")
	pu.easy = false
	await idle(4)
	ok(not card.visible, "challenge: leaving Easy closes the card")
	pu.easy = true
	await idle(4)
	ok(not card.visible and card.modulate.a > 0.5, "challenge: back in Easy the card does not come back")


func open_ep() -> void:
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep


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
	await open_ep()
	for sz in SIZES:
		await run_size(sz[0], sz[1])
	for sz in SIZES:
		await control(sz[0], sz[1])
	await challenge_run()
	print("s240: %d fail" % fails)
	quit(1 if fails > 0 else 0)

## item 239 grouped the library chips under group tabs: open the tab that holds a chip before a real click on it (navigation only)
func open_group_of(c: Control) -> void:
	if c == null or c.is_visible_in_tree():
		return
	for g in root.find_children("easypart_libgroup_*", "Button", true, false):
		var fl := root.find_child("easypart_libchips_" + (g as Button).text, true, false)
		if fl != null and fl.is_ancestor_of(c):
			await click_ctl(g)
			return
