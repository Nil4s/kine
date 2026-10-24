## godot --path . -s tests/library_test.gd     (OBJECT LIBRARY, scripts/object_library.gd; needs a window)
## BARS, stated before any measurement:
##  B1  every category holds at least 1 item; the tiles on screen, tab by tab, add up to the inventory count.
##      Built-in: Weapons 11, Furniture 5, Sports 1, Everyday 13, Armour 7 (37); My models: the models registered (this test
##      registers one, so 1). Total = 38.
##  B2  clicking the Sword tile puts the sword in the right hand (B.wep_on, wep_kind "sword", wep_hand "hand_r");
##      clicking the Chair tile puts a chair on the floor: its lowest corner within 1 cm of the floor (|y| <= 0.01 m).
##  B3  each click is ONE undo step: the undo stack grows by exactly 1 (sword, chair, chest plate).
##  B4  the search "sw" finds the sword (weapon:sword) and no tile of another category is needed for it.
##  B5  the panel fits at 1280x720: its whole rectangle is inside a 1280x720 window (laid out by fit(), see the test).
##  B6  Easy's Library button opens the panel with one click, and a second click closes it.
##  B7  thumbnails: every object is drawn once or read from the cache (renders + disk hits = objects), each has its PNG
##      under user://thumbs/lib, and the panel's tiles hold a picture.
## Clicks are the tile's own "pressed" signal (the same path a mouse click takes after the button's own press handling).
extends SceneTree

const BUILT_IN := {"Weapons": 11, "Furniture": 5, "Sports": 1, "Everyday": 13, "Armour": 7}

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


func tile(id: String) -> Button:
	return lib.find_child("tile_" + id.replace(":", "_"), true, false) as Button


## the lowest corner of a prop's solids, in metres (its bottom on the floor when 0)
func bottom_of(p: Dictionary) -> float:
	var lo := INF
	for s in Props.solids(p):
		var xf: Transform3D = s["xf"]
		var h: Vector3 = s["half"]
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					lo = minf(lo, (xf * Vector3(h.x * sx, h.y * sy, h.z * sz)).y)
	return lo


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	Props.register("my test_box", AABB(Vector3.ZERO, Vector3(0.3, 0.3, 0.3)), "")   # one model of "your own" for the My models tab
	m._new_scene()
	await idle()
	m._library_toggle()
	await idle()
	lib = m.ui_library

	# B1: every category has an item; the tiles on screen per tab equal the inventory
	var cats := ObjectLibrary.CATS
	var total := 0
	var per := {}
	for c in cats:
		per[c] = lib.in_cat(c).size()
		total += per[c]
	for c in BUILT_IN:
		ok(per[c] == BUILT_IN[c], "%s holds %d (built-in %d)" % [c, per[c], BUILT_IN[c]])
	ok(per["My models"] >= 1, "My models holds the registered model (%d)" % per["My models"])
	ok(total == lib.items.size() and total == 38, "the inventory: %d objects in all (38 with one model of your own)" % total)
	var shown_all := 0
	var empty_tab := []
	for i in cats.size():
		lib._pick_tab(i)
		await idle(2)
		var n := 0
		for b in lib._grid.get_children():
			if b is Button:
				n += 1
		shown_all += n
		if n == 0:
			empty_tab.append(cats[i])
		ok(n == per[cats[i]], "tab %s: %d tiles on screen = %d in the inventory" % [cats[i], n, per[cats[i]]])
	ok(empty_tab.is_empty(), "every category holds at least 1 tile %s" % str(empty_tab))
	ok(shown_all == total, "the tiles on screen add up to the inventory (%d = %d)" % [shown_all, total])

	# B2 + B3: a sword into the right hand, a chair onto the floor; each one undo step
	lib._pick_tab(0)
	await idle(2)
	var u0: int = m.undo.size()
	tile("weapon:sword").pressed.emit()
	await idle(2)
	ok(m.undo.size() == u0 + 1, "the sword click is one undo step (%d -> %d)" % [u0, m.undo.size()])
	ok(m.B.wep_on and m.B.wep_kind == "sword" and m.B.wep_hand == "hand_r", "the sword is in the right hand (on %s, kind %s, hand %s)" % [m.B.wep_on, m.B.wep_kind, m.B.wep_hand])
	lib._pick_tab(1)
	await idle(2)
	var n0: int = m.S.props.size()
	u0 = m.undo.size()
	tile("prop:chair").pressed.emit()
	await idle(2)
	ok(m.undo.size() == u0 + 1, "the chair click is one undo step (%d -> %d)" % [u0, m.undo.size()])
	ok(m.S.props.size() == n0 + 1 and String(m.S.props[-1]["kind"]) == "chair", "a chair was added to the set")
	var bot := bottom_of(m.S.props[-1])
	ok(absf(bot) <= 0.01, "the chair stands on the floor: its bottom at %.4f m (within 1 cm)" % bot)
	lib._pick_tab(4)
	await idle(2)
	var parts0: int = ArmourFromBody.parts(m).size()
	u0 = m.undo.size()
	tile("armour:chest").pressed.emit()
	await idle(2)
	print("info: armour click: undo %d -> %d, note: %s" % [u0, m.undo.size(), lib._note.text])
	ok(m.undo.size() == u0 + 1 and ArmourFromBody.parts(m).size() == parts0 + 1, "the chest plate: one undo step and one plate on the body (%d parts)" % ArmourFromBody.parts(m).size())
	m._undo()   # the plate comes off with its step
	await idle(2)
	ok(ArmourFromBody.parts(m).size() == parts0, "Ctrl+Z takes the plate back off")

	# B4: search
	lib._search.text = "sw"
	lib._on_search("sw")
	await idle(2)
	var found := lib.names_matching("sw")
	ok("weapon:sword" in lib._shown().map(func(it): return it["id"]) and tile("weapon:sword") != null, "search sw finds the sword (%d matches: %s)" % [found.size(), str(found)])
	lib._search.text = ""
	lib._on_search("")

	# B5: fits 1280x720 (the window is set to that size above)
	await idle(8)
	# run_par embeds this window at its own size (1600x900 here, it cannot be resized), so the 1280x720 window is laid out
	# by fit(), the same call open() makes, and the rectangle is checked against that size
	lib.fit(Vector2(1280, 720))
	await idle(4)
	var r := lib.get_global_rect()
	ok(r.position.x >= 0 and r.position.y >= 0 and r.end.x <= 1280 and r.end.y <= 720,
		"the panel fits at 1280x720: %s" % str(r))

	# B6: Easy's Library button
	lib.hide_panel()
	m.easy.button("Library").pressed.emit()
	await idle(2)
	var on1 := lib.visible
	m.easy.button("Library").pressed.emit()
	await idle(2)
	ok(on1 and not lib.visible, "Easy's Library button opens the panel, a second press closes it")
	lib.open()
	await idle(2)

	# B7: thumbnails
	await lib.thumbs.settle()
	var have := 0
	for it in lib.items:
		if FileAccess.file_exists(ProjectSettings.globalize_path(LibraryThumbs.cache_path(LibraryThumbs.key_of(it["shapes"])))):
			have += 1
	var pics := 0
	for it in lib.items:
		if lib.thumbs.picture(String(it["id"])) != null:
			pics += 1
	ok(lib.thumbs.renders + lib.thumbs.disk_hits == lib.items.size() and have == lib.items.size(),
		"thumbnails: %d drawn, %d read from disk, %d PNGs under %s (objects %d)" % [lib.thumbs.renders, lib.thumbs.disk_hits, have, LibraryThumbs.DIR, lib.items.size()])
	ok(pics == lib.items.size(), "every object has its picture in memory (%d)" % pics)
	ok(LibraryThumbs.DIR.begins_with("user://") and lib.thumbs.picture("weapon:sword") is ImageTexture, "the sword's picture is an ImageTexture")

	print("LIBRARY TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
