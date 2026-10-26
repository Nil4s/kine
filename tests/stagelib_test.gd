extends SceneTree
## STAGE LIBRARY (the object library reachable from the STAGE page, not only from Easy). Bars, stated before measuring:
##   1 the STAGE page's ribbon has a visible "Library" button (inside the window, not clipped off the row)
##   2 pressing it opens the object library
##   3 clicking Furniture > chair places a chair prop (S.props grows by 1)
##   4 a model exported with "Use as a prop" is listed under My models (and its tile is on screen)
##   5 at 1600x900 and 1280x720 the open library overlaps no visible STAGE panel and sits inside the window
## Each bar fails on the code before this round: the SET row's button was "Object library..." (not a visible "Library").
## Script errors are checked by the runner's log scan (a SCRIPT ERROR line fails the suite).
const SIZES := [Vector2i(1600, 900), Vector2i(1280, 720)]
const SHOT := "C:/Temp/claude/C--Users-Nick-Desktop/904598b3-9ea7-4084-af90-fc9f1424ac10/scratchpad/stage_library.png"
var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


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


func hover(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e)
	await process_frame
	await idle(2)


func click(p: Vector2) -> void:
	await hover(p)
	await mouse(p, true)
	await mouse(p, false)
	await idle(4)


## the first visible button whose text is txt (or starts with it when prefix)
func find_btn(txt: String, prefix := false) -> Button:
	for b in root.find_children("*", "Button", true, false):
		var bt: Button = b
		if bt.is_visible_in_tree() and (bt.text == txt or (prefix and bt.text.begins_with(txt))):
			return bt
	return null


func lib_tiles() -> Array:
	return [] if m.ui_library == null else m.ui_library.find_children("tile_*", "Button", true, false)


func on_screen(r: Rect2) -> bool:
	var vp := Rect2(Vector2.ZERO, m.get_viewport().get_visible_rect().size)
	return r.size.x > 1.0 and r.size.y > 1.0 and vp.encloses(r)


## the visible STAGE panels (global rects); the library is checked against these
func stage_rects() -> Array:
	var out := []
	var cands := [
		["browser", m.ui_browser, m.ui_browser != null and m.ui_browser.is_visible_in_tree()],
		["reactions", m.ui_reactions, m.ui_reactions != null and m.ui_reactions.is_visible_in_tree()],
		["card strip", m.ui_cards, m.ui_cards != null and m.ui_cards.is_visible_in_tree()],
		["status line", m.ui_status, m.ui_status != null and m.ui_status.is_visible_in_tree() and m.ui_status.text != ""],
		["welcome line", m.ui_mouse, m.ui_mouse != null and m.ui_mouse.is_visible_in_tree()],
		["readout", m.ui_bar, m.ui_bar != null and m.ui_bar.is_visible_in_tree()],
		["page bar", m.ui_page_bar, m.ui_page_bar != null and m.ui_page_bar.is_visible_in_tree()],
		["top strip", m.get("strip"), m.get("strip") != null and m.get("strip").is_visible_in_tree()],
	]
	for c in cands:
		if c[2]:
			var n: Control = c[1]
			if n.get_global_rect().size.x > 0.0 and n.get_global_rect().size.y > 0.0:
				out.append([c[0], n.get_global_rect()])
	return out


func overlaps(a: Rect2, b: Rect2) -> bool:
	var x := a.intersection(b)
	return x.size.x > 1.0 and x.size.y > 1.0


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.easy.set_on(false, false)
	await idle(2)
	m.ui_page_btns["STAGE"].pressed.emit()
	await idle(6)

	# 1 the visible Library button on the STAGE ribbon
	var lib := find_btn("Library")
	var lib_rect := lib.get_global_rect() if lib != null else Rect2()
	ok(lib != null and on_screen(lib_rect), "1 the STAGE ribbon has a visible 'Library' button on screen (%s)" % str(Rect2i(lib_rect)))

	# 2 pressing it opens the library
	if lib != null:
		await click(lib_rect.get_center())
	ok(m.ui_library != null and m.ui_library.visible, "2 pressing Library opens the object library")

	# 3 Furniture > chair places a chair prop
	var tab := find_btn("Furniture", true)
	if tab != null:
		await click(tab.get_global_rect().get_center())
	var n0: int = m.S.props.size()
	var chair: Control = null
	for t in lib_tiles():
		if t.name == "tile_prop_chair":
			chair = t
	var chair_ok := chair != null and chair.is_visible_in_tree() and on_screen(chair.get_global_rect())
	if chair_ok:
		await click(chair.get_global_rect().get_center())
		await idle(6)
	ok(chair_ok and m.S.props.size() == n0 + 1, "3 Furniture > chair places a chair prop (props %d -> %d, tile on screen %s)" % [n0, m.S.props.size(), str(chair_ok)])

	# 4 a model exported with Use as a prop is listed under My models
	if m.ui_library != null:
		m.ui_library.hide_panel()
	m.ui_page_btns["MODEL"].pressed.emit()
	await idle(4)
	m._kmesh_edit_start()
	await idle(4)
	m.kmed.undo.steps.clear()
	var path: String = m._export_model()
	await idle(3)
	m._use_export_as_prop()
	await idle(4)
	var kind := "my test_cube"
	var reg := Props.has_kind(kind)
	m.ui_page_btns["STAGE"].pressed.emit()
	await idle(6)
	var lib2 := find_btn("Library")
	if lib2 != null:
		await click(lib2.get_global_rect().get_center())
	var mine := find_btn("My models", true)
	if mine != null:
		await click(mine.get_global_rect().get_center())
	var tile: Control = null
	for t in lib_tiles():
		if t.has_meta("item") and String(t.get_meta("item")) == "model:" + kind:   # the tile's id (its node name keeps the space)
			tile = t
	var listed := tile != null and tile.is_visible_in_tree()
	ok(reg and listed, "4 a model exported with Use as a prop is listed under My models (registered %s, tile shown %s)" % [str(reg), str(listed)])
	if reg:
		var kd: Dictionary = Props.kind_of(kind)
		Props.EXTRA.erase(kind)   # the run's own copy: removed with its files below
		if FileAccess.file_exists(String(kd["glb"])):
			DirAccess.remove_absolute(String(kd["glb"]))
	if path != "":
		for p in [path, path.trim_suffix(".glb") + ".obj", path.trim_suffix(".glb") + ".mtl"]:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(p)

	# 5 no overlap with the STAGE panels, at both sizes (the library open, on the STAGE page)
	var win0: Vector2i = m.get_window().size
	for sz in SIZES:
		m.get_window().size = sz
		await idle(10)
		if m.ui_library != null:
			m.ui_library.open()
		await idle(10)
		var lr: Rect2 = Rect2() if m.ui_library == null else m.ui_library.get_global_rect()
		var bad := []
		for r in stage_rects():
			if overlaps(lr, r[1]):
				bad.append(str(r[0]))
		var lib_vis: bool = m.ui_library != null and m.ui_library.visible and on_screen(lr)
		ok(lib_vis and bad.is_empty(), "5 %dx%d: the library (%s) is on screen and overlaps no STAGE panel (overlaps: %s; panels %s)" % [sz.x, sz.y, str(Rect2i(lr)), str(bad), str(stage_rects().map(func(r): return [r[0], Rect2i(r[1])]))])
		if sz == SIZES[0]:
			m.get_window().size = sz
			await idle(6)
			if m.ui_library != null:
				m.ui_library.open()
				m.ui_library._pick_tab(1)   # Furniture: the picture shows the tiles (My models is empty again by now)
			await idle(8)
			var img := m.get_viewport().get_texture().get_image()
			DirAccess.make_dir_recursive_absolute(SHOT.get_base_dir())
			img.save_png(SHOT)
			print("screenshot %s" % SHOT)
	m.get_window().size = win0
	if m.ui_library != null:
		m.ui_library.hide_panel()
	await idle(4)

	print("STAGELIB TEST ", "PASS" if fails == 0 else "FAIL %d" % fails)
	TestFiles.cleanup()
	quit(1 if fails else 0)
