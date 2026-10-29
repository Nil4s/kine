extends SceneTree
## godot --path . --position 4000,4000 -s tests/alib2_test.gd     (ALIB2: EASY LIBRARY WALK, a beginner who never read a manual; needs a window)
## BARS (stated before the first run; the first run on the old code is the proof):
##  A1 START   the ANIMATION card (Easy) opens a scene with a visible Library button; its press opens the library (presses <= 2 to reach it)
##  A2 WORD    typing chair by key presses into the library search box shows the chair card (prop:chair), at most 3 cards
##  A3 CAT     Easy's Furniture tile opens Furniture: the chair card is on it and the cards are the Furniture cards
##  A4 DRAG    a real press on the chair card, dragged to the floor in the view: one chair in the set, ONE undo step
##  A5 COLOUR  the picked chair shows a visible Colour it button; one press changes its colour, ONE undo step
##  A6 UNDO    Ctrl+Z takes the colour back (the chair stays); a second Ctrl+Z takes the chair away
##  A7 WORDS   the visible Easy words on the walk name no key (Ctrl, Shift, Alt, Esc, Enter, Delete, F1..)
##  A8 PRESSES the walk from the start screen to the undo takes at most 12 presses
## Only user:// is written (UserPaths.root = user://alib2_test). Screenshots: C:/Temp/claude/alib2/<step>.png
const ROOT_DIR := "user://alib2_test"
const SHOT_DIR := "C:/Temp/claude/alib2"
const KEY_WORDS := ["Ctrl", "Shift", "Alt+", "Esc", "Enter", "Delete", "Backspace", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9"]
const MAX_PRESSES := 12

var m: Node
var fails := 0
var presses := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func gp(p: String) -> String:
	return ProjectSettings.globalize_path(p)


func shot(nm: String) -> void:
	await RenderingServer.frame_post_draw
	m.get_viewport().get_texture().get_image().save_png(SHOT_DIR + "/" + nm + ".png")
	print("SHOT %s/%s.png" % [SHOT_DIR, nm])


## a real click at a global point: move, press, release through the root viewport
func clk_at(p: Vector2) -> void:
	var hm := InputEventMouseMotion.new()
	hm.position = p
	hm.global_position = p
	root.push_input(hm)
	await process_frame
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e, true)
		await process_frame
	await idle(3)


func press(c: Control, what: String) -> bool:
	presses += 1
	if c == null or not c.is_visible_in_tree():
		print("NOCLICK ", what)
		return false
	await clk_at(c.get_global_rect().get_center())
	return true


## a real drag: press at a, move in steps to b, release at b
func drag(a: Vector2, b: Vector2) -> void:
	var steps := 10
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = a
	down.global_position = a
	down.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(down, true)
	await idle(2)
	for i in range(1, steps + 1):
		var p := a.lerp(b, float(i) / steps)
		var mm := InputEventMouseMotion.new()
		mm.position = p
		mm.global_position = p
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(mm)
		await idle(2)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = b
	up.global_position = b
	root.push_input(up, true)
	await idle(4)


## typed keys, one press and release per character, into whatever has focus
func type_text(s: String) -> void:
	for ch in s:
		var e := InputEventKey.new()
		e.pressed = true
		e.unicode = ch.unicode_at(0)
		e.keycode = OS.find_keycode_from_string(ch.to_upper())
		e.physical_keycode = e.keycode
		e.key_label = e.keycode
		root.push_input(e)
		await process_frame
		var r := e.duplicate() as InputEventKey
		r.pressed = false
		root.push_input(r)
		await process_frame
	await idle(3)


func ctrl_z() -> void:
	var e := InputEventKey.new()
	e.pressed = true
	e.keycode = KEY_Z
	e.physical_keycode = KEY_Z
	e.key_label = KEY_Z
	e.unicode = 122
	e.ctrl_pressed = true
	root.push_input(e)
	await idle(4)


func visible_texts() -> Array:
	var out := []
	for n in root.find_children("*", "", true, false):
		if n is Control and (n as Control).is_visible_in_tree():
			if n is Label:
				out.append((n as Label).text)
			elif n is Button:
				out.append((n as Button).text)
			if (n as Control).tooltip_text != "":
				out.append((n as Control).tooltip_text)
	return out


func _cat(c: String) -> Button:
	var lib: ObjectLibrary = m.ui_library
	for b in lib._cat_btns:
		if String((b as Button).get_meta("cat")) == c:
			return b
	return null


func _init() -> void:
	EasyMode.start_fresh = true
	UserPaths.force = true
	UserPaths.root = gp(ROOT_DIR)
	DirAccess.make_dir_recursive_absolute(gp(ROOT_DIR))
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	m._library_toggle()   # builds the library once (setup, as libcat_test does), then closes it
	await idle(3)
	m._library_toggle()
	await idle(2)
	m.easy.set_on(true, false)
	await idle(4)
	var ss: StartScreen = m.start_screen
	ss.dirs_override = [gp(ROOT_DIR) + "/scenes"]
	ss.show_screen(true)
	await idle(20)
	await shot("00_start")

	# A1 start screen -> ANIMATION card (Easy), then the Library button
	await press(ss._card_art["animation"], "ANIMATION card")
	await idle(20)
	var lib: ObjectLibrary = m.ui_library
	lib.recent_file = "user://alib2_test_recent.json"   # never Nick's own Recent list
	lib.clear_recent()
	var lb := m.easy.button("Library") as Button
	ok(lb != null and lb.is_visible_in_tree() and presses <= 2, "A1 START the ANIMATION card (Easy) shows a visible Library button (presses %d)" % presses)
	await press(lb, "Library")
	await idle(6)
	ok(lib.visible, "A1 the Library button opens the library")
	await shot("01_library")

	# A2 type a word
	var search := lib.find_child("library_search", true, false) as LineEdit
	presses += 1
	await clk_at(search.get_global_rect().get_center())
	await type_text("chair")
	var shown: Array = lib._shown().map(func(it): return String(it["id"]))
	ok(shown.has("prop:chair") and shown.size() <= 3, "A2 typing chair shows the chair card (shown %s)" % str(shown))
	await shot("02_typed_chair")

	# A3 category tile
	await press(_cat("Furniture"), "Furniture tile")
	await idle(6)
	var fur: Array = lib.in_group("Furniture").map(func(it): return String(it["id"]))
	var got: Array = lib._shown().map(func(it): return String(it["id"]))
	ok(got.has("prop:chair") and got.size() == fur.size(), "A3 the Furniture tile opens the furniture cards with the chair (%s)" % str(got))
	await shot("03_furniture")

	# A4 drag the chair onto the floor
	var n0: int = m.S.props.size()
	var u0: int = m.undo.size()
	var tile := lib.find_child("tile_prop_chair", true, false) as Control
	if tile != null and tile.is_visible_in_tree():
		presses += 1
		await drag(tile.get_global_rect().get_center(), Vector2(900, 560))
	await idle(4)
	var placed: bool = m.S.props.size() == n0 + 1 and String(m.S.props[-1]["kind"]) == "chair"
	ok(placed and m.undo.size() == u0 + 1, "A4 the chair dragged onto the floor is one chair in the set, ONE undo step (props %d -> %d, undo %d -> %d)" % [n0, m.S.props.size(), u0, m.undo.size()])
	await shot("04_dropped")
	# DEAD END (kept, not fixed: the existing easyhome bars 124-128 need the library to stay open after a drop): the object
	# bar with Colour it is hidden while the library is open, so the beginner presses Library (the same button) to close it
	var cb := m.find_child("eh_prop_colour", true, false) as Button
	var hid_open: bool = lib.visible and cb != null and not cb.is_visible_in_tree()
	print("NOTE dead end: with the library open after a drop, Colour it is %s" % ("hidden" if hid_open else "on screen"))
	if lib.visible:
		presses += 1
		await press(lb, "Library (close)")
		await idle(3)
	ok(not lib.visible, "A4 the library closes with its Library button after the drop")

	# A5 colour
	var c0: String = str(m.S.props[-1].get("colour", "grey")) if placed else ""
	var u1: int = m.undo.size()
	await press(cb, "Colour it")
	await idle(4)
	var c1: String = str(m.S.props[-1].get("colour", "grey")) if not m.S.props.is_empty() else ""
	ok(cb != null and c1 != c0 and m.undo.size() == u1 + 1, "A5 Colour it changes the chair's colour (%s -> %s), ONE undo step" % [c0, c1])
	await shot("05_coloured")

	# A6 undo
	await ctrl_z()
	var c2: String = str(m.S.props[-1].get("colour", "grey")) if not m.S.props.is_empty() else ""
	ok(m.S.props.size() == n0 + 1 and c2 == c0, "A6 Ctrl+Z takes the colour back and keeps the chair (colour %s, props %d)" % [c2, m.S.props.size()])
	await ctrl_z()
	ok(m.S.props.size() == n0, "A6 a second Ctrl+Z takes the chair away (props %d)" % m.S.props.size())
	await shot("06_undone")

	# A7 words
	var keys := []
	for t in visible_texts():
		for k in KEY_WORDS:
			if String(t).contains(k):
				keys.append("%s in %s" % [k, String(t).left(50)])
	ok(keys.is_empty(), "A7 the Easy walk's visible words name no key %s" % str(keys.slice(0, 4)))

	# A8 presses
	ok(presses <= MAX_PRESSES, "A8 the walk took %d presses (at most %d)" % [presses, MAX_PRESSES])

	print("ALIB2 TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
