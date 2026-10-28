extends SceneTree
## godot --path . -s tests/stagewalk_test.gd   (STAGEWALK: a beginner's walk on the STAGE page, 1280x720, real clicks from the real start screen)
## The walk: 1 Expert > Animation on the start screen; 2 the STAGE page; 3 a second fighter (typed into Search); 4 a prop from
## Library > Furniture > chair; 5 a shot camera (typed into Search); 6 Play. Every step takes a screenshot (C:/Temp/claude/stagewalk/).
## A bar with KNOWN after its name is a documented dead end: it prints KNOWN while it fails and FAILs once it is fixed (then drop KNOWN).
## Each dead end's words and press are printed as DEAD END lines. Exits 0 when every plain bar holds and no known bar has been fixed.
const OUT := "C:/Temp/claude/stagewalk/"
const SIZE := Vector2i(1280, 720)
var fails := 0
var m: Node
var dead := []


func bar(c: bool, w: String, known := false) -> void:
	if known:
		if c:
			print("FAIL (known dead end now works, drop KNOWN) " + w)
			fails += 1
		else:
			print("KNOWN " + w)
	else:
		print(("ok   " if c else "FAIL ") + w)
		if not c:
			fails += 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func walk(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children(true):
		walk(c, out)
	return out


func shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	m.get_viewport().get_texture().get_image().save_png(OUT + name + ".png")


func mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func click(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	var hm := InputEventMouseMotion.new()
	hm.position = p
	hm.global_position = p
	root.push_input(hm)
	await idle(2)
	await mouse(p, true)
	await mouse(p, false)
	await idle(8)


func key(code: Key, ch := "") -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.physical_keycode = code
	k.unicode = ch.unicode_at(0) if ch != "" else 0
	k.pressed = true
	root.push_input(k)
	await process_frame
	var u := InputEventKey.new()
	u.keycode = code
	u.physical_keycode = code
	u.pressed = false
	root.push_input(u)
	await idle(3)


func type_text(s: String) -> void:
	for ch in s:
		if ch == " ":
			await key(KEY_SPACE, " ")
		else:
			await key(OS.find_keycode_from_string(ch.to_upper()), ch)


func visible_btn(txt: String, prefix := false) -> Button:
	for n in walk(root, []):
		if n is Button and (n as Button).is_visible_in_tree():
			var t := (n as Button).text.strip_edges()
			if t == txt or (prefix and t.begins_with(txt)):
				return n
	return null


func by_tip(t: String) -> Button:
	for n in walk(root, []):
		if n is Button and (n as Button).is_visible_in_tree() and str((n as Button).tooltip_text).contains(t):
			return n
	return null


func on_screen(c: Control) -> bool:
	var r := c.get_global_rect()
	return r.size.x > 1.0 and r.size.y > 1.0 and Rect2(Vector2.ZERO, Vector2(SIZE)).encloses(r)


func fighters() -> int:
	m._actors_sync()
	return m.actors_rt.size()


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.get_window().size = SIZE
	await idle(10)
	m.start_screen.show_screen(true)   # the real start screen (the testing build does not show it at boot)
	await idle(10)
	shot("01_start")

	# 1 the start screen's Expert button under Animation
	var ex: Button = m.start_screen.find_child("expert_animation", true, false)
	bar(ex != null and ex.is_visible_in_tree() and on_screen(ex), "1 the start screen has a visible Expert button under Animation")
	await click(ex)
	bar(m.cur_page == "POSE" and not m.easy.on, "1 Expert opens the animation page (page %s, easy %s)" % [m.cur_page, str(m.easy.on)])
	shot("02_pose")

	# 2 the STAGE page button (a word on the page row)
	var st := visible_btn("STAGE")
	bar(st != null and on_screen(st), "2 the page row has a visible STAGE button")
	await click(st)
	bar(m.cur_page == "STAGE", "2 STAGE opens the set page (page %s)" % m.cur_page)
	shot("03_stage")

	# 3 a second fighter: the STAGE page has no button for it, so the beginner types into Search. On an empty scene it is refused
	var sb := visible_btn("Actor: add a second fighter", true)
	bar(sb != null, "3 a STAGE button says 'Add a second fighter' (no words on the page; only Search finds it)", true)
	await click(by_tip("Search (S)"))
	await type_text("second fighter")
	await idle(6)
	await key(KEY_ENTER, "")
	await idle(10)
	print("DEAD END 3a: typed 'second fighter' + Enter on an empty scene; status says: " + str(m.ui_status.text))
	bar(fighters() == 0 and str(m.ui_status.text) != "", "3a an empty scene refuses a second fighter in words (fighters %d)" % fighters())
	shot("04_refused_fighter")
	# a shot camera on the empty scene: refused in words too (dead end 3b)
	await click(by_tip("Search (S)"))
	await type_text("key the shot camera")
	await key(KEY_ENTER, "")
	await idle(8)
	print("DEAD END 3b: typed 'key the shot camera' + Enter on an empty scene; status says: " + str(m.ui_status.text))
	bar(m._hero_scene().shots.size() > 0, "3b a shot camera can be keyed on an empty scene (shots %d)" % m._hero_scene().shots.size(), true)
	# the card first (Enter adds the body as a card), then the second fighter
	var c0: int = m.S.cards.size()
	await key(KEY_ENTER, "")
	await idle(8)
	bar(m.S.cards.size() > c0, "3 Enter adds the body as a card (cards %d -> %d)" % [c0, m.S.cards.size()])
	# one card: Space does not play (dead end 3c)
	await key(KEY_SPACE, " ")
	await idle(6)
	print("DEAD END 3c: one card, Space (Play / pause); status says: " + str(m.ui_status.text))
	bar(m.playing, "3c one card plays on Space (playing %s)" % str(m.playing), true)
	var f0 := fighters()   # the body alone: 1 actor (the scene is not yet two fighters)
	await click(by_tip("Search (S)"))
	await type_text("second fighter")
	await idle(6)
	shot("05_search_fighter")
	await key(KEY_ENTER, "")
	await idle(10)
	bar(fighters() == 2 and fighters() > f0, "3 with a card, typing 'second fighter' and Enter puts a second fighter in the scene (fighters %d -> %d)" % [f0, fighters()])
	shot("06_two_fighters")

	# 4 a prop: Library (an icon on the SET row) > Furniture > chair
	var lib := by_tip("Open the object library")
	bar(lib != null and on_screen(lib) and lib.text.strip_edges() != "", "4 the Library button has a visible word (icon only: %s)" % str(lib != null and on_screen(lib) and lib.text.strip_edges() == ""), true)
	if lib == null:
		lib = by_tip("Library")
	await click(lib)
	var tab := visible_btn("Furniture", true)
	if tab != null:
		await click(tab)
	var chair: Control = null
	for n in walk(root, []):
		if n.name == "tile_prop_chair" and (n as Control).is_visible_in_tree():
			chair = n
	var n0: int = m.S.props.size()
	if chair != null:
		await click(chair)
		await idle(6)
	bar(m.S.props.size() == n0 + 1, "4 Library > Furniture > chair puts a chair in the scene (props %d -> %d)" % [n0, m.S.props.size()])
	shot("06_chair")
	if m.ui_library != null:
		m.ui_library.hide_panel()
	await idle(4)

	# 5 a shot camera (Search "key the shot camera"); the card is already there
	await click(by_tip("Search (S)"))
	await type_text("key the shot camera")
	await idle(6)
	await key(KEY_ENTER, "")
	await idle(10)
	bar(m._shot_shots().size() > 0 or m._hero_scene().shots.size() > 0, "5 Search 'key the shot camera' + Enter makes a shot camera (shots %d)" % m._hero_scene().shots.size())
	shot("07_camera")

	# 6 Play (Space). A scene needs two cards to play: a second card is added by Enter first
	if m.S.cards.size() < 2:
		await key(KEY_ENTER, "")
		await idle(6)
	await key(KEY_SPACE, " ")
	await idle(30)
	bar(m.playing, "6 Space plays the scene (playing %s, playhead %.2f, status: %s)" % [str(m.playing), m.playhead, m.ui_status.text if m.ui_status != null else ""])
	shot("08_play")
	if m.playing:
		await key(KEY_SPACE, " ")
	await idle(4)

	# 7 Easy (the start screen's Easy button under Animation) with unsaved work: the dialog comes first (dead end 7a).
	# NOT MEASURED past the dialog: the Save / Don't save buttons sit in a window this walk cannot click yet (see the report).
	m.start_screen.show_screen(true)
	await idle(8)
	var eb: Button = m.start_screen.find_child("easy_animation", true, false)
	await click(eb)
	await idle(8)
	print("DEAD END 7a: Easy card with unsaved work asks first: " + str(visible_btn("Don't save") != null))
	shot("09_easy_asks_save")
	print("STAGEWALK TEST ", "PASS" if fails == 0 else "FAIL %d" % fails)
	TestFiles.cleanup()
	quit(1 if fails else 0)
