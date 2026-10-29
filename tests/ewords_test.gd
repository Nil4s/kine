extends SceneTree
## godot --path . --position 4000,4000 -s tests/ewords_test.gd     (EWORDS: every string Easy Part shows in a 40-press session is plain words, no jargon; scripts/easy_part.gd; needs the CAD DLL and a window)
## Real clicks and drags at 1280 x 720 from the start screen: Easy Part is opened, then 40 presses go round every visible Easy Part button (Draw shape is followed by a drag on the grid).
## After each press the words on the Easy Part panel (labels, buttons, the status line, the hint, the toast) are read and checked for jargon.
## Bars (the old code FAILED bar 3: the report has the list of hits):
##   1 PRESSES  40 real presses ran
##   2 SEEN     at least 15 different strings were shown (the scan is not empty)
##   3 WORDS    no shown string has a jargon word (sketch, profile, extrude, fillet, boolean, loft, wire, kernel, manifold, feature, f16, revolve, mesh, shell, body, plane, offset, CAD, DLL ...)
## Prints every shown string once ("shown: ...") so the list can be read.
const DIRT := "user://ewords_test"
const PRESSES := 40
const MIN_SEEN := 15
const LEAVES := ["Home", "Use in a scene", "Give to a character", "Easy", "Expert", "What to build", "Undo", "Exact sizes? Use Expert"]   # buttons that leave Easy Part or open another screen
const BANNED := "(?i)\\b(sketch\\w*|profile\\w*|extrud\\w*|fillet\\w*|boolean\\w*|loft\\w*|wire\\w*|kernel\\w*|manifold\\w*|features?|revolv\\w*|params?|mesh\\w*|shell\\w*|bod(y|ies)|primitive\\w*|tessel\\w*|topolog\\w*|planes?|offset\\w*|dll|cad|f\\d{1,2})\\b"

var fails := 0
var m: Node
var re := RegEx.new()
var seen := {}      # text -> true: every string shown
var hits := {}      # text -> the jargon word found in it
var n_press := 0


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


func pu() -> PartUI:
	return m.bld.part


func ep():
	return pu().ep


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


## a click on a control: a real press and release at its centre
func press(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await process_frame
	await process_frame


## a drag on the floor from world a to world b (metres)
func draw_floor(a: Vector3, b: Vector3) -> void:
	var pa := scr(a)
	var pb := scr(b)
	await ev_move(pa, false)
	await ev_mouse(pa, true)
	for i in range(1, 13):
		await ev_move(pa.lerp(pb, i / 12.0))
	await ev_mouse(pb, false)
	await idle(3)


func fresh() -> void:
	m.S.part = Part.make("Part")
	pu().upto = -1
	pu().sync()
	m.target = Vector3(0.0, 0.0, 0.0)
	m.pitch = -40.0
	m.yaw = 20.0
	m._cam()
	await idle(60)


## every Label and Button under the Easy Part panels that is on screen, plus the toast
func shown_nodes() -> Array:
	var roots := [ep().hint, ep().status, ep().panel, ep().shape_box, ep().repeat_box, ep().stick_box,
		ep().hole_box, ep().colour_box, ep().make_box, ep().bar, m.ui_toast]
	var out := []
	for r in roots:
		if r != null and is_instance_valid(r):
			_walk(r, out)
	return out


func _walk(n: Node, out: Array) -> void:
	if n is Control and not (n as Control).is_visible_in_tree():
		return
	if n is Label or n is Button:
		out.append(n)
	for c in n.get_children():
		_walk(c, out)


func scan() -> void:
	for n in shown_nodes():
		var t := String((n as Label).text) if n is Label else String((n as Button).text)
		t = t.strip_edges()
		if t == "":
			continue
		if not seen.has(t):
			print("shown: " + t)
		seen[t] = true
		var mt := re.search(t)
		if mt != null:
			hits[t] = mt.get_string()


## the buttons a press may go to: on screen, enabled, not the ones that leave Easy Part or open another screen
func press_list() -> Array:
	var skip := [ep().easy_btn, ep().expert_btn, ep().use_btn, ep().use_scene_btn]
	var out := []
	for n in shown_nodes():
		if not (n is Button) or (n as Button).disabled:
			continue
		if n in skip or (n as Button).text in LEAVES:
			continue
		var c := (n as Button).get_global_rect().get_center()
		if c.x < 0.0 or c.y < 0.0 or c.x > 1280.0 or c.y > 720.0:
			continue
		out.append(n)
	return out


## one press of a button; a drag (world a to b on the floor, or on the top face when face is true) first when the button draws
func _step(b: Control, a, bb, face := false) -> void:
	if not b.is_visible_in_tree() or (b is BaseButton and (b as BaseButton).disabled):
		return
	print("press %d: %s" % [n_press + 1, (b as Button).text if b is Button else "?"])
	await press(b)
	n_press += 1
	if a != null:
		if face:
			var c: AABB = pu().res.get("aabb", AABB())
			var top := Vector3(c.get_center().x, c.end.y, c.get_center().z)
			await draw_floor(top + (a as Vector3), top + (bb as Vector3))
		else:
			await draw_floor(a, bb)
	await idle(3)
	print("  after: %s | %s | hint %s %s" % [ep().msg, ep().status_l.text, ep().hint_l.text, ep().hint.is_visible_in_tree()])
	scan()


func _init() -> void:
	re.compile(BANNED)
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
	await press(ss._cards["building"])
	await idle(3)
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	# Nick 2026-10-28 (free 3D building, #100): the BUILDING card now opens a blank Easy Part itself. Start from the
	# state the card gave before (Part off, no part), so the clicks below drive the same opening they always did
	pu().set_on(false)
	pu().m.S.part = {}
	await process_frame
	await press(pu().part_btn)
	await idle(3)
	await press(pu().easy_open_btn)
	await idle(4)
	await fresh()
	scan()

	# SESSION: 40 real presses. First the walk through the shapes that make words (a shape off the solid, a cut on a face,
	# a pull into the solid), then round the visible buttons in turn until 40
	var mk: Dictionary = ep().make_btns
	await _step(mk["draw"], Vector3(-0.12, 0.0, -0.06), Vector3(-0.08, 0.0, -0.02))
	await _step(mk["pull"], null, null)
	await _step(mk["hole"], null, null)
	await _step(ep().hole_btns["hollow"], null, null)
	await _step(mk["draw"], Vector3(0.15, 0.0, 0.12), Vector3(0.19, 0.0, 0.16))
	await _step(mk["hole"], null, null)
	await _step(mk["draw"], Vector3(-0.02, 0.0, 0.0), Vector3(0.02, 0.0, 0.03), true)
	await _step(mk["pull"], null, null)
	await _step(mk["mirror"], null, null)
	await _step(mk["stick"], null, null)
	await _step(mk["repeat"], null, null)
	await _step(ep().rep_btns["corners"], null, null)
	var k := 0
	while n_press < PRESSES and k < 400:
		k += 1
		var bs := press_list()
		if bs.is_empty():
			continue
		var b: Button = bs[k % bs.size()]
		await _step(b, null, null)
	scan()
	print("presses %d, strings shown %d" % [n_press, seen.size()])

	ok(n_press == PRESSES, "1 PRESSES %d real presses ran (want %d)" % [n_press, PRESSES])
	ok(seen.size() >= MIN_SEEN, "2 SEEN %d different strings shown (at least %d)" % [seen.size(), MIN_SEEN])
	for t in hits:
		print("jargon: \"%s\"  (word: %s)" % [t, hits[t]])
	ok(hits.is_empty(), "3 WORDS %d shown string(s) with a jargon word" % hits.size())
	print("ewords: %d fail" % fails)
	quit(1 if fails > 0 else 0)
