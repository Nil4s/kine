extends SceneTree
## godot --path . -s tests/libcat_test.gd     (OBJECT LIBRARY BY CATEGORY, scripts/object_library.gd; needs a window)
## BARS, stated before any measurement:
##  C1  every object the library lists is in exactly one category (the six built-in ones and BUILD's four): the counts add up to the catalog,
##      ids are unique, and every object of the old inventory is still in the category it had.
##  C2  counts per category: Weapons 11, Furniture 5, Sports 1, Everyday 13, Armour 7, My models 1 (this test registers one),
##      Fight blocks 4, Build stairs 2, Build furniture 3 (BuildPieces.CATS), My houses 0 without a house and 1 with one.
##  C3  the search finds objects across categories: "table" (Furniture and Build furniture), "stairs" (Everyday and Build stairs),
##      "ramp" (Everyday and Fight blocks), "sword" (Weapons, twice); a word that matches nothing shows nothing.
##  C4  EXPERT, real mouse clicks only: the STAGE page's Library button opens the library, the Fight blocks entry of the left column is
##      clicked, the Pillar card is clicked: a pillar is in the set (props +1), ONE undo step (undo stack +1), and Recent lists it.
##  C5  a BUILD house: with a room drawn, My houses lists it; its card puts the house in the set in ONE undo step.
##  C6  EASY, real clicks: the Library button opens it, the Furniture entry, the Chair card: a chair in the set, ONE undo step, Recent
##      shows it; the cards are bigger than Expert's.
##  C7  EASY text (every label, button and tooltip of the library and its note) names no key (Ctrl, Shift, Alt, Esc, Enter, Del, F1..).
##  C8  OPENING the library again (pictures cached) takes less than OPEN_MAX_MS = 150 ms.
##  C9  Recent keeps the last RECENT_MAX, newest first, no repeats.
## Screenshots: C:/Temp/claude/libcat/expert.png and easy.png.
const OPEN_MAX_MS := 150.0
const SHOT_DIR := "C:/Temp/claude/libcat"
const KEY_WORDS := ["Ctrl", "Shift", "Alt+", "Esc", "Enter", "Delete", "Backspace", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "Key "]

var fails := 0
var m: Node
var lib: ObjectLibrary


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


## a real left click on a control's middle: move, press, release
func click_ctl(c: Control) -> void:
	var at: Vector2 = c.get_global_rect().get_center()
	var hm := InputEventMouseMotion.new()
	hm.position = at
	hm.global_position = at
	root.push_input(hm)
	await idle(2)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = at
	e.global_position = at
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await idle(1)
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = at
	u.global_position = at
	root.push_input(u, true)
	await idle(4)


func find_btn(txt: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		var bt: Button = b
		if bt.is_visible_in_tree() and bt.text == txt:
			return bt
	return null


func tile(id: String) -> Button:
	return lib.find_child("tile_" + id.replace(":", "_"), true, false) as Button


func side(nm: String) -> Button:
	return lib.find_child("cat_" + nm.replace(" ", "_").to_lower(), true, false) as Button


func ids_in_group(c: String) -> Array:
	return lib.in_group(c).map(func(it): return String(it["id"]))


func shown_ids() -> Array:
	return lib._shown().map(func(it): return String(it["id"]))


func shot(nm: String) -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	await idle(3)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT_DIR, nm])
	print("SHOT %s/%s.png" % [SHOT_DIR, nm])


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	Props.register("my test_box", AABB(Vector3.ZERO, Vector3(0.3, 0.3, 0.3)), "")
	m.easy.set_on(false, false)
	m._new_scene()
	await idle(4)
	m._library_toggle()
	await idle(3)
	lib = m.ui_library
	lib.recent_file = "user://libcat_test_recent.json"   # never Nick's own Recent list
	lib.clear_recent()
	m._library_toggle()
	await idle(2)

	# C1 / C2
	lib.open()
	await idle(2)
	var cats: Array = ObjectLibrary.CATS + ObjectLibrary.EXTRA_CATS
	var total := 0
	var seen := {}
	var dup := []
	for c in cats:
		total += lib.in_group(c).size()
		for id in ids_in_group(c):
			if seen.has(id):
				dup.append(id)
			seen[id] = c
	var cat_count := lib.catalog().size()
	var once := lib.catalog().all(func(it): return seen.has(String(it["id"])))
	ok(total == cat_count and dup.is_empty() and once, "C1 every object is in exactly one category (%d in categories, %d in the catalog, repeated: %s)" % [total, cat_count, str(dup)])
	var moved := []
	for it in lib.items:
		if lib.group_of(it) != String(it["cat"]):
			moved.append(it["id"])
	ok(moved.is_empty() and lib.items.size() == 38, "C1 the old inventory (%d objects) is where it was (moved: %s)" % [lib.items.size(), str(moved)])
	var want := {"Weapons": 11, "Furniture": 5, "Sports": 1, "Everyday": 13, "Armour": 7, "My models": 1, "Fight blocks": 4, "Build stairs": 2, "Build furniture": 3, "My houses": 0}
	var bad := []
	for c in want:
		if lib.in_group(c).size() != int(want[c]):
			bad.append("%s %d (want %d)" % [c, lib.in_group(c).size(), int(want[c])])
	ok(bad.is_empty(), "C2 counts per category %s" % (str(bad) if not bad.is_empty() else str(want)))
	var cols_ok := side("Recent") != null
	for c in cats:
		cols_ok = cols_ok and side(c) != null if not ObjectLibrary.CATS.has(c) else cols_ok and lib.find_child("tab_%d" % ObjectLibrary.CATS.find(c), true, false) != null
	ok(cols_ok, "the left column lists Recent and all %d categories" % cats.size())

	# C3 search across categories
	var ob := lib.find_child("library_search", true, false) as LineEdit
	var probes := {"table": ["Furniture", "Build furniture"], "stairs": ["Everyday", "Build stairs"], "ramp": ["Everyday", "Fight blocks"], "sword": ["Weapons"]}
	for w in probes:
		ob.text = w
		ob.text_changed.emit(w)
		await idle(2)
		var got := {}
		for id in shown_ids():
			got[String(lib.item(id)["cat"])] = true
		var miss: Array = probes[w].filter(func(c): return not got.has(c))
		var tiles := lib.find_children("tile_*", "Button", true, false).size()
		ok(miss.is_empty() and tiles == shown_ids().size() and tiles >= probes[w].size(), "C3 search '%s' finds %d cards across %s (missing: %s)" % [w, tiles, str(got.keys()), str(miss)])
	ob.text = "zzzz"
	ob.text_changed.emit("zzzz")
	await idle(2)
	ok(shown_ids().is_empty() and lib.find_children("tile_*", "Button", true, false).is_empty(), "C3 a word that matches nothing shows no card")
	ob.text = ""
	ob.text_changed.emit("")
	m._library_toggle()
	await idle(2)

	# C4 expert, real clicks
	m.ui_page_btns["STAGE"].pressed.emit()
	await idle(6)
	var open_btn := find_btn("Library")
	ok(open_btn != null, "C4 the STAGE page shows a Library button")
	if open_btn != null:
		await click_ctl(open_btn)
	ok(m.ui_library != null and m.ui_library.visible, "C4 a click on Library opens the library")
	var fb := side("Fight blocks")
	ok(fb != null and fb.is_visible_in_tree(), "C4 the Fight blocks entry is on screen")
	if fb != null:
		await click_ctl(fb)
	ok(lib.view == "Fight blocks" and shown_ids().size() == 4 and tile("build:pillar") != null, "C4 a click on Fight blocks shows its 4 cards (view %s)" % lib.view)
	await lib.thumbs.settle()
	var pil := tile("build:pillar")
	var n0: int = m.S.props.size()
	var u0: int = m.undo.size()
	if pil != null:
		await click_ctl(pil)
	await idle(3)
	ok(m.S.props.size() == n0 + 1 and String(m.S.props[-1]["kind"]) == "piece:pillar", "C4 the Pillar card put a pillar in the set (props %d -> %d, kind %s)" % [n0, m.S.props.size(), String(m.S.props[-1]["kind"]) if not m.S.props.is_empty() else "-"])
	ok(m.undo.size() == u0 + 1, "C4 one click is ONE undo step (%d -> %d)" % [u0, m.undo.size()])
	var rb := side("Recent")
	if rb != null:
		await click_ctl(rb)
	ok(shown_ids() == ["build:pillar"] and tile("build:pillar") != null, "C4 Recent shows the pillar (%s)" % str(shown_ids()))
	m._undo()
	await idle(3)
	ok(m.S.props.size() == n0, "C4 Undo takes the pillar away")
	m._library_toggle()
	await idle(2)
	m._library_toggle()
	await idle(2)
	await click_ctl(side("Fight blocks"))
	await lib.thumbs.settle()
	await shot("expert")

	# C5 a BUILD house
	m.S.building = Building.make("Test house")
	Building.add_room(m.S.building, 0.0, 0.0, 4.0, 4.0)
	lib.open()
	await idle(2)
	ok(ids_in_group("My houses").size() == 1, "C5 with a room drawn, My houses lists the house (%s)" % str(ids_in_group("My houses")))
	var hb := side("My houses")
	if hb != null:
		await click_ctl(hb)
	var hid := String(ids_in_group("My houses")[0]) if not ids_in_group("My houses").is_empty() else ""
	var ht := tile(hid) if hid != "" else null
	n0 = m.S.props.size()
	u0 = m.undo.size()
	if ht != null:
		await click_ctl(ht)
	await idle(3)
	ok(m.S.props.size() == n0 + 1 and String(m.S.props[-1]["kind"]).begins_with("building:") and m.undo.size() == u0 + 1, "C5 the house card puts the house in the set in ONE undo step (props %d -> %d, undo %d -> %d)" % [n0, m.S.props.size(), u0, m.undo.size()])
	m._undo()
	await idle(3)
	m.S.building = {}

	# C6 / C7 easy
	m._library_toggle()   # close
	await idle(2)
	m.easy.set_on(true, false)
	await idle(6)
	m._new_scene()
	await idle(4)
	var eb := m.easy.button("Library") as Button
	ok(eb != null and eb.is_visible_in_tree(), "C6 Easy shows a Library button")
	if eb != null:
		await click_ctl(eb)
	ok(lib.visible, "C6 a click on Library opens the library in Easy")
	var fu := lib.find_child("tab_%d" % ObjectLibrary.CATS.find("Furniture"), true, false) as Button
	if fu != null:
		await click_ctl(fu)
	await lib.thumbs.settle()
	var ch := tile("prop:chair")
	ok(ch != null and ch.size.x > ObjectLibrary.TILE.x and ch.size.y > ObjectLibrary.TILE.y, "C6 Easy's cards are bigger than Expert's (%s vs %s)" % [str(ch.size) if ch != null else "-", str(ObjectLibrary.TILE)])
	n0 = m.S.props.size()
	u0 = m.undo.size()
	if ch != null:
		await click_ctl(ch)
	await idle(3)
	ok(m.S.props.size() == n0 + 1 and String(m.S.props[-1]["kind"]) == "chair", "C6 the Chair card put a chair in the set (props %d -> %d)" % [n0, m.S.props.size()])
	ok(m.undo.size() == u0 + 1, "C6 one click is ONE undo step (%d -> %d)" % [u0, m.undo.size()])
	var rb2 := side("Recent")
	if rb2 != null:
		await click_ctl(rb2)
	ok(shown_ids().size() >= 1 and shown_ids()[0] == "prop:chair", "C6 Recent shows the chair first (%s)" % str(shown_ids()))
	await lib.thumbs.settle()
	var texts := []
	for n in lib.find_children("*", "", true, false):
		if n is Label:
			texts.append((n as Label).text)
		if n is Button:
			texts.append((n as Button).text)
		if n is Control:
			texts.append((n as Control).tooltip_text)
	for c in cats:   # the other categories' tooltips too (their cards are not on screen at once)
		var sb := side(c)
		if sb == null:
			sb = lib.find_child("tab_%d" % ObjectLibrary.CATS.find(c), true, false) as Button
		if sb != null:
			texts.append(sb.tooltip_text)
	for it in lib.catalog():   # a card's own tooltip in Easy
		texts.append("%s: click it, or drag it onto the floor, to give it to him" % it["name"])
	var keys := []
	for t in texts:
		for k in KEY_WORDS:
			if String(t).contains(k):
				keys.append("%s in '%s'" % [k, String(t).left(60)])
	ok(keys.is_empty(), "C7 Easy's library text (%d strings) names no key %s" % [texts.size(), str(keys.slice(0, 4))])
	# a piece card's note after a click, in Easy
	await click_ctl(side("Fight blocks"))
	var pl := tile("build:platform")
	if pl != null:
		await click_ctl(pl)
	await idle(2)
	var note := String(lib._note.text)
	var note_keys := KEY_WORDS.filter(func(k): return note.contains(k))
	ok(note != "" and note_keys.is_empty(), "C7 Easy's note after a BUILD card names no key ('%s')" % note)
	await click_ctl(side("Recent"))
	await lib.thumbs.settle()
	await shot("easy")

	# C9 Recent: newest first, no repeats, capped
	lib.clear_recent()
	var all_ids: Array = lib.catalog().map(func(it): return String(it["id"]))
	for i in ObjectLibrary.RECENT_MAX + 3:
		lib._recent_add(String(all_ids[i % all_ids.size()]))
	lib._recent_add(String(all_ids[2]))
	var r: Array = lib._recent
	var uniq := {}
	for id in r:
		uniq[id] = true
	ok(r.size() == ObjectLibrary.RECENT_MAX and uniq.size() == r.size() and r[0] == all_ids[2], "C9 Recent holds %d, newest first, no repeats (first %s)" % [r.size(), str(r[0])])

	# C8 opening again: the pictures are cached
	m.easy.set_on(false, false)
	await idle(4)
	for c in cats:
		if ObjectLibrary.CATS.has(c):
			lib._pick_tab(ObjectLibrary.CATS.find(c))
		else:
			lib._pick_view(c)
		await idle(2)
		await lib.thumbs.settle()
	lib._pick_tab(0)
	await idle(2)
	lib.hide_panel()
	await idle(2)
	var worst := 0.0
	for k in 3:
		var t0 := Time.get_ticks_usec()
		lib.open()
		await process_frame
		worst = maxf(worst, float(Time.get_ticks_usec() - t0) / 1000.0)
		lib.hide_panel()
		await idle(2)
	ok(worst < OPEN_MAX_MS, "C8 opening the library again takes %.1f ms (at most %.0f)" % [worst, OPEN_MAX_MS])

	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://libcat_test_recent.json"))
	print("LIBCAT TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
