extends SceneTree
## p163collection (Friday plan 163: Collections, my workshop and my game props). A saved part (My parts) can go into one of two
## collections, My workshop or My game props: a right-click on the part's card opens a small menu with a button per collection and
## a button to take it out. A collection gets its own column entry, shown only when it holds a part (like My parts). Real clicks at
## 1280 x 720 in Easy, in the object library:
##   Walk 1: My parts -> right-click Shield -> Put in My workshop -> My workshop shows Shield only, My parts shows Coin only
##   Walk 2: My parts -> right-click Coin -> Put in My game props -> My game props shows Coin
##   Walk 3: saving Coin again (Use in a scene) keeps its collection
##   Walk 4: My workshop -> right-click Shield -> Take out of its collection -> My parts shows both again, My workshop column is gone
## Every number is measured from the built result: the card counts on the grid, the column entries shown, the record in the file on
## disk, the undo count. The expected numbers come from the walks above, never from the code's own variables.
## Bars (written with the code, not before it; there is no run on the old code: the small item is a chip and a menu):
##   K0 My parts lists the two saved parts (Shield, Coin) as cards, and no collection column entry is shown
##   K1 a right-click on Shield opens the menu: three buttons (My workshop, My game props, take out) under the mouse
##   K2 Put in My workshop: the file of Shield holds collection "My workshop"; My workshop shows Shield alone; My parts shows Coin alone
##   K3 the My workshop column entry is shown and its count is 1 (the column names the collection, the tiles are Shield)
##   K4 Put in My game props on Coin: its file holds "My game props"; My game props shows Coin alone
##   K5 saving Coin again keeps "My game props" in its file (the same name replaces the part, the collection stays)
##   K6 Take out of its collection on Shield: its file has no collection key; My workshop is empty and its column entry is hidden;
##      My parts then shows Shield alone
##   K7 no scene edit: the undo count does not move in the whole walk (a collection is a list, not a model step)
##   K8 the menu closes after a pick (no menu node left in the window)
## shots: C:/Temp/claude/p163collection/*.png
const SHOT := "C:/Temp/claude/p163collection"
const DIRT := "user://p163collection_test"
var fails := 0
var m: Node
var lib: ObjectLibrary


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool, btn := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if btn == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
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


## a card or column entry under a scroll: the scroll moves it into view first (a click on a clipped button does nothing)
func reveal(c: Control) -> void:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			(p as ScrollContainer).ensure_control_visible(c)
		p = p.get_parent()
	await idle(2)


func click_ctl(c: Control) -> void:
	await reveal(c)
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func right_click_ctl(c: Control) -> void:
	await reveal(c)
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true, MOUSE_BUTTON_RIGHT)
	await ev_mouse(p, false, MOUSE_BUTTON_RIGHT)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func tile(id: String) -> Button:
	return lib.find_child("tile_" + id.replace(":", "_"), true, false) as Button


## the card names on the grid right now (the walk's count and names)
func shown_names() -> Array:
	var out := []
	for id in lib._shown().map(func(it): return String(it["id"])):
		if id.begins_with("mypart:saved:"):
			out.append(id.trim_prefix("mypart:saved:"))
	return out


## a column entry (Easy's category tiles: the entry's meta "cat")
func cat_btn(c: String) -> Button:
	for b in lib._cat_btns:
		if String((b as Button).get_meta("cat")) == c:
			return b
	return null


func menu_buttons() -> Array:
	var menu := root.find_child("library_collection_menu", true, false)
	if menu == null:
		return []
	return menu.find_children("coll_*", "Button", true, false)


func menu_button(nm: String) -> Button:
	for b in menu_buttons():
		if (b as Button).name == nm:
			print("diag %s rect %s visible %s" % [nm, str((b as Button).get_global_rect()), str((b as Button).is_visible_in_tree())])
			return b as Button
	return null


func part_rec(nm: String) -> Dictionary:
	return MyParts.load_part(nm)


func save_part(nm: String) -> void:
	MyParts.save({"features": [], "name": nm}, nm)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	# the saved parts go to the test's own folder: the user's My parts is never touched
	MyParts.dir = DIRT
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	for nm in ["Shield", "Coin"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MyParts.path_of(nm)))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MyParts.thumb_of(nm)))
	save_part("Shield")
	save_part("Coin")
	m.easy.set_on(true, false)
	m._new_scene()
	await idle(4)
	m._library_toggle()
	await idle(3)
	lib = m.ui_library
	lib.recent_file = "user://p163collection_recent.json"   # never Nick's own Recent list
	lib.clear_recent()
	lib.open()
	await idle(3)
	var undo0: int = m.undo.size()

	# K0: My parts shows the two saved cards, no collection column entry
	await click_ctl(cat_btn("My parts"))
	await idle(3)
	await lib.thumbs.settle()
	var names0 := shown_names()
	names0.sort()
	ok(names0 == ["Coin", "Shield"] and not side_shown("My workshop") and not side_shown("My game props"),
		"K0 My parts shows %s; no collection entry shown (%s, %s)" % [str(names0), str(side_shown("My workshop")), str(side_shown("My game props"))])
	await shot("1_my_parts")

	# K1: right-click Shield: the menu with three buttons
	await right_click_ctl(tile("mypart:saved:Shield"))
	await idle(3)
	var mb := menu_buttons()
	ok(mb.size() == 3, "K1 a right-click on Shield opens the menu with %d buttons (want 3)" % mb.size())
	await shot("2_menu")

	# K2: Put in My workshop
	var put := menu_button("coll_my_workshop")
	if put != null:
		await click_ctl(put)
	await idle(5)
	await lib.thumbs.settle()
	var f_shield: String = str(part_rec("Shield").get("collection", ""))
	var mine := shown_names()
	ok(f_shield == "My workshop" and mine == ["Coin"],
		"K2 Shield's file says \"%s\"; My parts shows %s (want Shield in My workshop, Coin alone)" % [f_shield, str(mine)])

	# K3: the My workshop column entry, its count, and its cards
	ok(side_shown("My workshop") and lib.in_group("My workshop").size() == 1,
		"K3 the My workshop entry is shown and holds %d part (want 1)" % lib.in_group("My workshop").size())
	await click_ctl(cat_btn("My workshop"))
	await idle(3)
	await lib.thumbs.settle()
	var ws := shown_names()
	ok(ws == ["Shield"], "K3 My workshop shows %s (want Shield alone)" % str(ws))
	await shot("3_my_workshop")

	# K4: Coin into My game props, from My parts
	await click_ctl(cat_btn("My parts"))
	await idle(3)
	await right_click_ctl(tile("mypart:saved:Coin"))
	var put2 := menu_button("coll_my_game_props")
	if put2 != null:
		await click_ctl(put2)
	await idle(5)
	await lib.thumbs.settle()
	var f_coin: String = str(part_rec("Coin").get("collection", ""))
	ok(f_coin == "My game props" and shown_names() == [] and side_shown("My game props"),
		"K4 Coin's file says \"%s\"; My parts is empty; My game props entry shown" % f_coin)
	await click_ctl(cat_btn("My game props"))
	await idle(3)
	await lib.thumbs.settle()
	ok(shown_names() == ["Coin"], "K4 My game props shows %s (want Coin alone)" % str(shown_names()))

	# K5: saving Coin again keeps its collection
	save_part("Coin")
	ok(str(part_rec("Coin").get("collection", "")) == "My game props",
		"K5 Coin saved again: its file still says \"%s\"" % str(part_rec("Coin").get("collection", "")))

	# K6: Take out of its collection (Shield, from My workshop)
	await click_ctl(cat_btn("My workshop"))
	await idle(3)
	await right_click_ctl(tile("mypart:saved:Shield"))
	var out := menu_button("coll_none")
	if out != null:
		await click_ctl(out)
	await idle(5)
	await lib.thumbs.settle()
	var back := shown_names()
	back.sort()
	ok(not part_rec("Shield").has("collection") and not side_shown("My workshop") and lib.view == "My parts" and back == ["Shield"],
		"K6 Shield's file has no collection; the emptied My workshop entry is hidden and the view went back to My parts (%s, shows %s)" % [lib.view, str(back)])
	# My parts: Shield alone (Coin is in My game props); the walk's end state
	await click_ctl(cat_btn("My parts"))
	await idle(3)
	await lib.thumbs.settle()
	var mp := shown_names()
	ok(mp == ["Shield"], "K6 My parts shows %s (want Shield alone: Coin is in My game props)" % str(mp))
	await shot("4_taken_out")

	# K7: the undo count did not move
	ok(m.undo.size() == undo0, "K7 the undo count is unchanged by the collection walk (%d -> %d)" % [undo0, m.undo.size()])

	# K8: no menu left in the window
	ok(menu_buttons().is_empty(), "K8 the menu is gone after a pick (%d buttons left)" % menu_buttons().size())

	# clean up the test's own folder
	for nm in ["Shield", "Coin"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MyParts.path_of(nm)))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MyParts.thumb_of(nm)))
	print("p163collection: %d fail" % fails)
	quit(1 if fails > 0 else 0)


## a column entry is shown (not hidden by its empty-group rule)
func side_shown(c: String) -> bool:
	var b := cat_btn(c)
	return b != null and b.visible
