extends SceneTree
## godot --headless -s tests/p139mocapmix_test.gd     (Friday plan 139: MIX A CLIP WITH A TYPED MOOD. "this walk, but angry")
## A beginner walk with real clicks and real keys at 1280 x 720, in Easy: the Walk card builds the clip; the Mood button on the
## clip's strip opens a box; a typed mood word blends onto the clip (scripts/style_dial.gd's four styles, one undo step).
## Bars written before the code. Every measure is read from the built record (counts, seconds, rects), never from the code's variables.
##   M1 the Walk card (a real click) builds a clip of at least two cards, and the clip's strip shows a visible "Mood" button
##   M2 a real click on Mood opens the mood panel inside the 1280 x 720 window, and the panel overlaps no Walk style button
##   M3 "this walk, but angry" typed in the box, a real click on Blend: ONE undo step, the card count is the same, the clip is
##      at least 10 % shorter, and no move got longer (counts of cards: moves longer = 0, moves shorter >= 1)
##   M4 Undo (its button) after the blend: the card count is the walk's, the clip length is back within one frame (1/24 s) of the walk's
##   M5 "jab" typed and blended: refused in words, NO undo step, and the words name the next step ("angry")
##   M6 "a bit tired" typed and blended onto the walk (after M5 refused): ONE undo step, the clip gets longer (slower), and it is
##      less than twice the walk's length (a half-strength tired is a stretch, not a new clip)
const SHOT := "C:/Temp/claude/p139mocapmix"
var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## a picture of the window as it is now, in the test's own folder
func shot(nm: String) -> void:
	await idle(3)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


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


func ev_move(p: Vector2, held := false) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


## a real press and release at the middle of the control (inside a popup: the popup's corner is added)
func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center() + Vector2(c.get_window().position)   # a popup's controls are laid out from the popup's own corner
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


## the visible Undo button of the Easy bar, clicked as a beginner clicks it
func click_undo() -> void:
	for n in root.find_children("*", "Button", true, false):
		var b := n as Button
		var words := b.text
		for k in b.find_children("*", "Label", true, false):   # the Easy bar's button may keep its words in a Label
			words += (k as Label).text
		if words.strip_edges() == "Undo" and b.is_visible_in_tree():
			await click_ctl(b)
			return
	print("FAIL no visible Undo button")


## the words the box holds, typed as a beginner would: the box takes the focus, the old words are replaced, then the line
func type_into(box: LineEdit, txt: String) -> void:
	await click_ctl(box)
	box.text = txt
	await idle(2)


## the card moves of the scene as it is: each card's move time (the walk's own timing, read from the built cards)
func moves() -> Array:
	var out := []
	for i in range(1, m.S.cards.size()):
		out.append(float(m.S.cards[i]["move"]))
	return out


func _init() -> void:
	EasyMode.start_fresh = true   # a fresh install: the app opens in Easy with the home panel
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var home: EasyHome = m.easy.home
	var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT))

	# M1: the Walk card, a real click
	var walk_btn: Button = root.find_child("eh_card_0", true, false) as Button
	await click_ctl(walk_btn)
	await idle(10)
	var mood: Button = root.find_child("eh_mood", true, false) as Button
	var n0: int = m.S.cards.size()
	var len0: float = m.S.length()
	var mv0 := moves()
	ok(n0 >= 2 and mood != null and mood.is_visible_in_tree(), "M1 the Walk card builds %d cards and the clip's strip shows a visible Mood button (%s)" % [n0, str(mood != null and mood.is_visible_in_tree())])

	# M2: the Mood button opens the panel, inside the window, clear of Walk style
	await click_ctl(mood)
	await idle(4)
	var pop: PopupPanel = root.find_child("eh_mood_panel", true, false) as PopupPanel
	var box: LineEdit = root.find_child("eh_mood_box", true, false) as LineEdit
	var go: Button = root.find_child("eh_mood_go", true, false) as Button
	var ws: Button = root.find_child("eh_walk_style", true, false) as Button
	var inside := false
	var clear := false
	if pop != null and pop.visible and go != null:
		inside = vp.encloses(Rect2(Vector2(pop.position), Vector2(pop.size)))
		clear = ws == null or not Rect2(ws.global_position, ws.size).intersects(Rect2(Vector2(pop.position), Vector2(pop.size)))
	ok(pop != null and pop.visible and inside and clear and box != null, "M2 the Mood panel opens inside the 1280 x 720 window (%s), clear of Walk style (%s)" % [str(inside), str(clear)])
	await shot("shot_mood_open")

	# M3: "this walk, but angry": one undo step, same cards, at least 10 % shorter, no move longer
	var u0: int = m.undo.size()
	await type_into(box, "this walk, but angry")
	await click_ctl(go)
	await idle(6)
	var n1: int = m.S.cards.size()
	var len1: float = m.S.length()
	var mv1 := moves()
	var longer := 0
	var shorter := 0
	for i in mini(mv0.size(), mv1.size()):
		if float(mv1[i]) > float(mv0[i]) + 1e-6:
			longer += 1
		elif float(mv1[i]) < float(mv0[i]) - 1e-6:
			shorter += 1
	ok(m.undo.size() == u0 + 1 and n1 == n0 and len1 <= 0.9 * len0 and longer == 0 and shorter >= 1,
		"M3 angry: %d undo step(s), cards %d -> %d, length %.2f s -> %.2f s (%.0f %%), moves shorter %d, longer %d" % [m.undo.size() - u0, n0, n1, len0, len1, 100.0 * len1 / maxf(len0, 0.001), shorter, longer])
	await shot("shot_angry")

	# M4: Ctrl+Z takes the blend back: the walk's card count and length (within one frame at 24 fps)
	await click_undo()
	await idle(4)
	var n2: int = m.S.cards.size()
	var len2: float = m.S.length()
	ok(n2 == n0 and absf(len2 - len0) <= 1.0 / 24.0 + 1e-6, "M4 Ctrl+Z: %d cards, length %.2f s (the walk had %d cards, %.2f s)" % [n2, len2, n0, len0])

	# M5: a word with no mood is refused in words, no undo step, and the words name the next step
	var u1: int = m.undo.size()
	await click_ctl(mood)   # Undo's click closed the panel (a click outside it): the Mood button opens it again
	await idle(4)
	await type_into(box, "jab")
	await click_ctl(go)
	await idle(4)
	var msg: Label = root.find_child("eh_mood_msg", true, false) as Label
	var said := msg.text if msg != null else ""
	ok(m.undo.size() == u1 and said.begins_with("No mood") and said.to_lower().contains("angry"), "M5 'jab' refused: %d undo step(s); the words say: %s" % [m.undo.size() - u1, said])

	# M6: "a bit tired": one undo step, slower, under twice as long
	var len3: float = m.S.length()
	var u2: int = m.undo.size()
	await type_into(box, "a bit tired")   # the panel is still open after the refusal (a click inside it)
	await click_ctl(go)
	await idle(6)
	var len4: float = m.S.length()
	ok(m.undo.size() == u2 + 1 and len4 > len3 and len4 < 2.0 * len3, "M6 a bit tired: %d undo step(s), length %.2f s -> %.2f s (%.0f %%)" % [m.undo.size() - u2, len3, len4, 100.0 * len4 / maxf(len3, 0.001)])
	await shot("shot_tired")

	print("p139mocapmix: %d fail" % fails)
	quit(1 if fails > 0 else 0)
