## godot --path . -s tests/nickbugs_test.gd     (NICK'S BUGS, expert mode; needs a window)
## Real mouse only (root.push_input at the visible control's centre, found by its tooltip or text), 1280 x 720.
## (1) The Scene menu's New empty scene and the other New entries: a click on the Scene button opens the menu and it stays
##     open; the scene becomes empty, or asks first over unsaved work.
## (2) The top bar's Undo, the inspector's Reset and the BODY menu's Reset body: a mouse click takes a drag back / resets it.
## (3) The browser tree keeps its scroll position when the mouse hovers the body (a refresh): it scrolls to the picked
##     part only when the picked part changes.
extends SceneTree

var m: Node
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func mouse_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e)
	await process_frame


func mouse_btn(down: bool, p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


## where a visible control's centre is on screen (a control inside a dialog window is placed in that window)
func centre_of(c: Control) -> Vector2:
	var w := c.get_window()
	var p := c.get_global_rect().get_center()
	if w != root:
		p += Vector2(w.position)
	return p


## a real click at the centre of a visible control
func click(c: Control) -> void:
	var p := centre_of(c)
	await mouse_move(p)
	await mouse_btn(true, p)
	await mouse_btn(false, p)
	await idle(6)


## the first visible button whose tooltip starts with `tip` (or whose text is `txt`)
func find_btn(tip: String, txt := "") -> Control:
	var out: Array = []
	_walk(root, tip, txt, out)
	return out[0] if not out.is_empty() else null


func _walk(n: Node, tip: String, txt: String, out: Array) -> void:
	if n is BaseButton and (n as Control).is_visible_in_tree() and (n as Control).get_global_rect().size.x > 2:
		var b := n as Control
		var t: String = b.tooltip_text
		var bt: String = n.text if "text" in n else ""
		if (tip != "" and t.begins_with(tip)) or (txt != "" and bt == txt):
			out.append(b)
			return
	for c in n.get_children():
		_walk(c, tip, txt, out)


## a menu the way a mouse uses it: a click on the menu button opens it and it stays open; a click on a row runs it.
## Returns false when the menu is not open or has no such row
func menu_pick(btn: Control, popup: PopupMenu, txt: String) -> bool:
	await click(btn)
	if popup == null or not popup.visible:
		return false
	return await pick_row(popup, txt)


func pick_row(popup: PopupMenu, txt: String) -> bool:
	for i in popup.item_count:
		if popup.get_item_text(i) == txt:
			var r := Rect2(Vector2(popup.position), Vector2(popup.size))   # a popup is a window: its position is on screen
			var rowh := r.size.y / float(maxi(popup.item_count, 1))
			var p := Vector2(r.position.x + r.size.x * 0.5, r.position.y + (i + 0.5) * rowh)
			await mouse_move(p)
			await mouse_btn(true, p)
			await mouse_btn(false, p)
			await idle(8)
			return true
	return false


func spot(j: String, f := 0.5) -> Vector2:
	var c: Array = m.B.cap(j)
	return m.cam.unproject_position(c[0].lerp(c[1], f))


## a press on p, steps of d, a release: what the user does
func drag(p: Vector2, d: Vector2, steps: int) -> void:
	await mouse_move(p)
	await mouse_btn(true, p)
	var q := p
	for i in steps:
		q += d
		var e := InputEventMouseMotion.new()
		e.position = q
		e.global_position = q
		e.relative = d
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e)
		await process_frame
	await mouse_btn(false, q)
	await idle()


func scene_menu() -> PopupMenu:
	return m.ui_scene_btn.get_popup()


func _init() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.easy.set_on(false, false)
	await idle(10)

	# ---- (1) New empty scene
	# 1a: an empty scene: the Scene menu's New empty scene empties it, with no question
	var sb := find_btn("Scene: save, open")
	ok(sb != null, "1a the Scene menu button is on screen")
	if sb != null:
		m.S.cards.clear()
		m._rebuild_cards()
		var picked := await menu_pick(sb, scene_menu(), "New empty scene")
		ok(picked, "1a a click on the Scene button opens its menu, and it stays open for a click on New empty scene")
		await idle(10)
		ok(m.S.cards.is_empty() and (m.ui_save_ask == null or not m.ui_save_ask.visible), "1a New empty scene from the menu: the scene is empty (cards %d, asks %s)" % [m.S.cards.size(), m.ui_save_ask != null and m.ui_save_ask.visible])
	# 1b: a scene with an unsaved clip: New empty scene asks first; Don't save makes the scene empty
	var clip := find_btn("the body as it is now becomes clip")
	ok(clip != null, "1b the Clip this pose button is on screen")
	if clip != null:
		await click(clip)
		await idle(6)
	var cards_before: int = m.S.cards.size()
	ok(cards_before >= 1, "1b clipping made a card (%d)" % cards_before)
	sb = find_btn("Scene: save, open")
	if sb != null:
		var got1b := await menu_pick(sb, scene_menu(), "New empty scene")
		ok(got1b, "1b the Scene menu stays open for New empty scene")
		await idle(10)
		ok(m.ui_save_ask != null and m.ui_save_ask.visible, "1b New empty scene over unsaved work asks first (dialog shown: %s)" % (m.ui_save_ask != null and m.ui_save_ask.visible))
		var dont: Control = m.ui_save_discard   # the dialog's own named button (main.gd ui_save_discard); the click is real
		ok(dont != null and dont.is_visible_in_tree(), "1b the Don't save button is on screen")
		if dont != null:
			await click(dont)
			await idle(10)
		ok(m.S.cards.is_empty(), "1b Don't save: the new scene is empty (cards %d)" % m.S.cards.size())
	# 1c: the recent scenes panel's "+ New scene" tile, pressed with the mouse
	m.recents.show_panel()
	await idle(10)
	var tile: Control = m.recents.new_tile
	ok(tile != null and tile.is_visible_in_tree(), "1c the recent scenes panel's New scene tile is on screen")
	m.S.cards.clear()
	m._rebuild_cards()
	m._clean = m._doc_key()
	m._card_add()
	await idle(6)
	if tile != null and tile.is_visible_in_tree():
		await click(tile)
		await idle(10)
		ok(m.ui_save_ask != null and m.ui_save_ask.visible, "1c the tile asks first over the unsaved clip")
		if m.ui_save_ask != null and m.ui_save_ask.visible:
			await click(m.ui_save_discard)
			await idle(10)
		ok(m.S.cards.is_empty(), "1c the tile's new scene is empty (cards %d)" % m.S.cards.size())
	# 1d: a saved, clean scene: the Scene menu's New empty scene, no question
	m._clean = m._doc_key()
	m._card_add()
	await idle(4)
	m._clean = m._doc_key()
	sb = find_btn("Scene: save, open")
	if sb != null:
		var got1d := await menu_pick(sb, scene_menu(), "New empty scene")
		ok(got1d, "1d the Scene menu stays open for New empty scene")
		await idle(10)
		ok(m.S.cards.is_empty() and (m.ui_save_ask == null or not m.ui_save_ask.visible), "1d a clean scene: New empty scene empties it with no question (cards %d)" % m.S.cards.size())

	# ---- (2) Undo, Reset and Reset body with the mouse
	m.sel = "upperarm_r"
	m._rebuild_cards()
	m._refresh()
	await idle()
	var p := spot("upperarm_r", 0.7)
	var toward: Vector2 = (m.cam.unproject_position(m.B.P["spine_03"]) - p)
	await drag(p, toward.normalized() * 12.0 + Vector2(0, 6), 30)
	var a1: Vector3 = m.B.ang["upperarm_r"]
	ok(not a1.is_zero_approx(), "2 the drag bent the right upper arm (%s)" % str(a1))
	var undo := find_btn("Undo")
	ok(undo != null, "2 the Undo button is on screen")
	if undo != null:
		await click(undo)
		await idle(6)
		ok(m.B.ang["upperarm_r"].is_zero_approx(), "2 a click on Undo takes the drag back (%s -> %s)" % [str(a1), str(m.B.ang["upperarm_r"])])
	# Reset (R) in the inspector
	await drag(spot("upperarm_r", 0.7), toward.normalized() * 12.0 + Vector2(0, 6), 30)
	var a3: Vector3 = m.B.ang["upperarm_r"]
	ok(not a3.is_zero_approx(), "2 the drag bent it again (%s)" % str(a3))
	var rs := find_btn("Reset (R)")
	ok(rs != null, "2 the inspector Reset button is on screen")
	if rs != null:
		await click(rs)
		await idle(6)
		ok(m.B.ang["upperarm_r"].is_zero_approx(), "2 a click on Reset puts the part back (%s)" % str(m.B.ang["upperarm_r"]))
	# Reset body from the BODY menu of the POSE tab
	await drag(spot("upperarm_r", 0.7), toward.normalized() * 12.0 + Vector2(0, 6), 30)
	ok(not m.B.ang["upperarm_r"].is_zero_approx(), "2 the drag bent the arm for Reset body (%s)" % str(m.B.ang["upperarm_r"]))
	var bodym := find_btn("", "BODY ▾")
	if bodym != null:
		var got2 := await menu_pick(bodym, (bodym as MenuButton).get_popup(), "Reset body")
		ok(got2, "2 the BODY menu opens and lists Reset body")
		await idle(6)
		ok(m.B.ang["upperarm_r"].is_zero_approx(), "2 Reset body from the BODY menu puts the pose back (%s)" % str(m.B.ang["upperarm_r"]))
	else:
		ok(false, "2 the BODY menu button is on screen")

	# ---- (3) the browser tree keeps its scroll: the wheel, then the body hovered (a refresh) with the picked part's row out of sight
	var tree: Tree = m.ui_browser
	ok(tree != null and tree.is_visible_in_tree(), "3 the browser tree is on screen")
	var ti: TreeItem = tree.get_root()
	while ti != null:   # every folder unfolded (the tree overflows the panel, as a long list does)
		if ti.get_child_count() > 0:
			ti.collapsed = false
		ti = ti.get_next_in_tree()
	m.sel = "pelvis"
	m._refresh()
	await idle(20)
	var wheel := centre_of(tree)
	await mouse_move(wheel)
	for i in 6:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_DOWN
		e.pressed = true
		e.position = wheel
		e.global_position = wheel
		root.push_input(e)
		await process_frame
	await idle(12)
	var at := tree.get_scroll().y
	ok(at > 20.0, "3 the mouse wheel scrolled the tree down (%.0f)" % at)
	# the body's parts lit by the mouse over the view (a hover is a refresh, which follows the picked part's row)
	for j in ["upperarm_r", "calf_l", "lowerarm_l", "thigh_r"]:
		await mouse_move(spot(j, 0.5))
		await idle(4)
	await idle(20)
	ok(absf(tree.get_scroll().y - at) < 1.0, "3 hovering the body does not move the tree back (%.0f -> %.0f)" % [at, tree.get_scroll().y])
	await idle(30)
	ok(absf(tree.get_scroll().y - at) < 1.0, "3 the tree stays where it was scrolled (%.0f -> %.0f)" % [at, tree.get_scroll().y])

	print("NICKBUGS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
