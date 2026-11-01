extends SceneTree
## s161 + s164 (Friday plan 161: My parts, thumbnails and tags; 164: part versions with a compare slider). Real clicks at 1280 x 720 in Easy,
## in the object library, My parts. Three parts are saved the way Use in a scene saves them (BuildUI._save_part: the record, then its picture).
## Every number is measured from files re-read from disk, the grid's cards and the labels on screen.
##   T1 saving 3 parts writes 3 PNGs, each 128 x 128, each with more than one colour (the picture is a render, not a blank)
##   T2 tags typed in the right-click menu (Save tags button) are in each part's file; a part never tagged has none
##   T3 the tag chip row shows All + bolt + metal; the metal chip shows exactly 2 cards, the bolt chip exactly 1, pressing bolt again shows all 3
##   T4 restart: the parts read fresh from the disk carry the same tags, and the library's items carry them
##   T5 saving a part again (new size) keeps its tags
##   V1 after 2 saves of Peg A, 2 versions exist on disk (an archived v1 json + png, and the current); a part saved once has 1
##   V2 the compare slider is in the menu; clicked to the left end the info line says the OLD volume (matches the cylinder pi r2 h of the first save, within 1 percent)
##   V3 clicked to the right end the info line says the NEW volume (the second save's cylinder, within 1 percent); the ghost's alpha is 1 there, 0 at the left
##   V4 the middle of the slider names both volumes and a blend percent between 1 and 99
## shots: C:/Temp/claude/s161/*.png
const SHOT := "C:/Temp/claude/s161"
const DIRT := "user://s161_test"
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


func peg_rec(nm: String, r: float, h: float) -> Dictionary:
	var rec := Part.make(nm)
	var sk := Part.new_feature(rec, "sketch", {"plane": "top", "ents": [{"k": "circle", "c": Part.arr2(Vector2.ZERO), "r": r}], "dims": []})
	rec["features"].append(sk)
	rec["features"].append(Part.new_feature(rec, "extrude", {"sketch": sk["id"], "dist": h, "both": false, "op": "new"}))
	return rec


func cyl_mm3(r: float, h: float) -> float:
	return PI * r * r * h


func grid_cards() -> int:
	var n := 0
	for c in lib._grid.get_children():
		if c is Button and String(c.name).begins_with("tile_mypart_saved_"):
			n += 1
	return n


func chip(tag: String) -> Button:
	return lib.find_child("tagchip_" + tag, true, false) as Button


func menu_ctl(nm: String) -> Control:
	var menu := root.find_child("library_collection_menu", true, false)
	return menu.find_child(nm, true, false) as Control if menu != null else null


func read_json(path: String) -> Dictionary:
	var f := FileAccess.get_file_as_string(path)
	var d = JSON.parse_string(f)
	return d if d is Dictionary else {}


func colours(path: String) -> int:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null or img.is_empty():
		return 0
	var seen := {}
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			seen[img.get_pixel(x, y).to_html()] = true
	return seen.size()


func save_part(rec: Dictionary) -> void:
	await m.bld._save_part(rec)
	await idle(4)


func number_in(t: String) -> float:
	var rx := RegEx.new()
	rx.compile("volume ([0-9.]+) mm3")
	var mt := rx.search(t)
	return float(mt.get_string(1)) if mt != null else -1.0


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	MyParts.dir = DIRT
	var ad := ProjectSettings.globalize_path(DIRT)
	for d in [ad + "/versions", ad]:
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d + "/" + f)
	DirAccess.make_dir_recursive_absolute(ad)
	m.easy.set_on(true, false)
	m._new_scene()
	await idle(4)
	await save_part(peg_rec("Peg A", 1.2, 20.0))
	await save_part(peg_rec("Peg B", 3.0, 20.0))
	await save_part(peg_rec("Peg C", 2.0, 10.0))

	# T1: three pictures, 128 x 128, not one colour
	var bad := []
	for nm in ["Peg A", "Peg B", "Peg C"]:
		var im := Image.load_from_file(ProjectSettings.globalize_path(MyParts.thumb_of(nm)))
		var sz := Vector2i(im.get_size()) if im != null and not im.is_empty() else Vector2i.ZERO
		var nc := colours(MyParts.thumb_of(nm))
		print("diag %s png %s colours %d" % [nm, str(sz), nc])
		if sz != Vector2i(128, 128) or nc < 2:
			bad.append(nm)
	var pngs := 0
	for f in DirAccess.get_files_at(ad):
		if f.ends_with(".png"):
			pngs += 1
	ok(bad.is_empty() and pngs == 3, "T1 %d PNGs in the store, wrong or one-colour ones: %s (want 3 and none)" % [pngs, str(bad)])

	m._library_toggle()
	await idle(3)
	lib = m.ui_library
	lib.recent_file = "user://s161_recent.json"
	lib.clear_recent()
	lib.more = lib.extra_items()
	lib.open()
	await idle(3)
	await click_ctl(cat_btn("My parts"))
	await idle(3)
	await lib.thumbs.settle()

	# T2: type tags in the menu
	var want := {"Peg A": "bolt, Metal", "Peg B": "metal"}
	for nm in want:
		await right_click_ctl(tile("mypart:saved:" + nm))
		var le := menu_ctl("tag_edit") as LineEdit
		if le != null:
			le.text = want[nm]
		var sv := menu_ctl("tag_save")
		if sv != null:
			await click_ctl(sv)
		await idle(4)
	await lib.thumbs.settle()
	var ta: Array = read_json(MyParts.path_of("Peg A")).get("tags", [])
	var tb: Array = read_json(MyParts.path_of("Peg B")).get("tags", [])
	var tc := read_json(MyParts.path_of("Peg C"))
	ok(ta == ["bolt", "metal"] and tb == ["metal"] and not tc.has("tags"), "T2 files hold Peg A %s, Peg B %s, Peg C has tags: %s (want [bolt, metal], [metal], false)" % [str(ta), str(tb), str(tc.has("tags"))])
	await shot("1_chips")

	# T3: the chips
	var names: Array = []
	for c in lib._tag_row.get_children():
		names.append(String(c.name))
	names.sort()
	ok(lib._tag_row.visible and names == ["tagchip_all", "tagchip_bolt", "tagchip_metal"], "T3 chip row %s visible %s" % [str(names), str(lib._tag_row.visible)])
	var n_all := grid_cards()
	await click_ctl(chip("metal"))
	await lib.thumbs.settle()
	var n_metal := grid_cards()
	var shown_metal := shown_names()
	shown_metal.sort()
	await shot("2_metal")
	await click_ctl(chip("bolt"))
	await lib.thumbs.settle()
	var n_bolt := grid_cards()
	var shown_bolt := shown_names()
	await click_ctl(chip("bolt"))
	await lib.thumbs.settle()
	var n_back := grid_cards()
	ok(n_all == 3 and n_metal == 2 and shown_metal == ["Peg A", "Peg B"] and n_bolt == 1 and shown_bolt == ["Peg A"] and n_back == 3,
		"T3 cards: all %d, metal %d %s, bolt %d %s, bolt pressed again %d (want 3, 2 [A,B], 1 [A], 3)" % [n_all, n_metal, str(shown_metal), n_bolt, str(shown_bolt), n_back])

	# T4: a fresh read of the disk (what a restart sees)
	var fresh := {}
	for pt in MyParts.list():
		fresh[String(pt["name"])] = MyParts.tags_of(pt["record"])
	var items := {}
	for it in lib.extra_items():
		if String(it["id"]).begins_with("mypart:saved:"):
			items[String(it["name"])] = it.get("tags", [])
	ok(fresh.get("Peg A") == ["bolt", "metal"] and fresh.get("Peg B") == ["metal"] and fresh.get("Peg C") == [] and items == fresh,
		"T4 fresh from disk %s, library items %s" % [str(fresh), str(items)])

	# V1: the second save of Peg A (a fatter peg)
	await save_part(peg_rec("Peg A", 2.0, 20.0))
	var va := MyParts.versions("Peg A")
	var vb := MyParts.versions("Peg B")
	var v1json := FileAccess.file_exists(ProjectSettings.globalize_path(DIRT + "/versions/Peg A.v1.json"))
	var v1png := FileAccess.file_exists(ProjectSettings.globalize_path(DIRT + "/versions/Peg A.v1.png"))
	ok(va.size() == 2 and vb.size() == 1 and v1json and v1png, "V1 Peg A has %d versions (json %s, png %s), Peg B %d (want 2 and 1)" % [va.size(), str(v1json), str(v1png), vb.size()])
	ok(MyParts.tags_of(read_json(MyParts.path_of("Peg A"))) == ["bolt", "metal"], "T5 Peg A saved again keeps its tags: %s" % str(MyParts.tags_of(read_json(MyParts.path_of("Peg A")))))

	# V2..V4: the compare slider, real clicks on the slider
	lib.more = lib.extra_items()
	lib._rebuild()
	await idle(3)
	await lib.thumbs.settle()
	await right_click_ctl(tile("mypart:saved:Peg A"))
	await idle(3)
	var sl := menu_ctl("ver_slider") as HSlider
	var info := menu_ctl("ver_info") as Label
	var ghost := menu_ctl("ver_new") as TextureRect
	ok(sl != null and info != null, "V2 the menu has the compare slider")
	if sl != null and info != null:
		var r := sl.get_global_rect()
		var y := r.get_center().y
		var want_old := cyl_mm3(1.2, 20.0)
		var want_new := cyl_mm3(2.0, 20.0)
		await ev_move(Vector2(r.position.x + 1, y))
		await ev_mouse(Vector2(r.position.x + 1, y), true)
		await ev_mouse(Vector2(r.position.x + 1, y), false)
		await idle(3)
		var t0 := info.text
		var a0 := ghost.modulate.a
		var v_old := number_in(t0)
		ok(sl.value < 0.01 and t0.begins_with("Old") and absf(v_old - want_old) <= 0.01 * want_old and a0 < 0.01,
			"V2 slider at %.2f: \"%s\" (want Old, %.1f mm3), ghost alpha %.2f" % [sl.value, t0, want_old, a0])
		var xm := r.get_center().x
		await ev_move(Vector2(xm, y))
		await ev_mouse(Vector2(xm, y), true)
		await ev_mouse(Vector2(xm, y), false)
		await idle(3)
		var tm := info.text
		var pct := int(tm.get_slice("%", 0)) if tm.contains("%") else -1
		ok(pct > 0 and pct < 100 and tm.contains("version 1") and tm.contains("version 2"), "V4 middle (%.2f): \"%s\"" % [sl.value, tm])
		await shot("3_compare_middle")
		var xr := r.position.x + r.size.x - 1
		await ev_move(Vector2(xr, y))
		await ev_mouse(Vector2(xr, y), true)
		await ev_mouse(Vector2(xr, y), false)
		await idle(3)
		var t1 := info.text
		var v_new := number_in(t1)
		ok(sl.value > 0.99 and t1.begins_with("New") and absf(v_new - want_new) <= 0.01 * want_new and ghost.modulate.a > 0.99,
			"V3 slider at %.2f: \"%s\" (want New, %.1f mm3), ghost alpha %.2f" % [sl.value, t1, want_new, ghost.modulate.a])
		await shot("4_compare_new")

	for d in [ad + "/versions", ad]:
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d + "/" + f)
	print("s161: %d fail" % fails)
	quit(1 if fails > 0 else 0)
