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
##  B7  REAL thumbnails: every object (38) has its 128 x 128 PNG under user://thumbs/lib (LibraryThumbs.real_path) and its
##      picture in memory; each picture is not empty: at least 5 % of its pixels differ from its corner pixel (the background).
##  B8  DISTINCT WEAPONS: sword, katana, spear and metal bat are pairwise different: the mean absolute difference over
##      R, G, B (0..255, every pixel) is above DIFF_MIN = 2.0 for all six pairs. Noise floor: the sword drawn again differs
##      from its picture by less than NOISE_MAX = 0.5 (printed).
##  B9  FRAMES: the panel opened on a cold cache (every real and schematic PNG deleted first) and drawing its tiles, tab by
##      tab, never lets one frame take longer than FRAME_MAX_MS = 50 ms between two process frames.
##  B10 CACHE: a second open of the panel draws 0 pictures (renders delta 0), and a fresh LibraryThumbs on the same
##      folder draws 0 (every object read from disk: disk hits = 38).
## Clicks are the tile's own "pressed" signal (the same path a mouse click takes after the button's own press handling).
extends SceneTree

const BUILT_IN := {"Weapons": 11, "Furniture": 5, "Sports": 1, "Everyday": 13, "Armour": 7}
const DIFF_MIN := 2.0          # B8: the mean absolute difference (0..255, R G B, every pixel) a pair must exceed
const NOISE_MAX := 0.5         # B8: the same weapon drawn again must differ by less than this
const FRAME_MAX_MS := 50.0     # B9
const NONBG_MIN := 0.05        # B7: the share of pixels that differ from the corner (the background)
const WEAPON_IDS := ["weapon:sword", "weapon:katana", "weapon:spear", "weapon:metal_bat"]

var fails := 0
var m: Node
var lib: ObjectLibrary
var _last_us := 0
var _gap_ms := 0.0
var _measuring := false


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


## every frame's start: the longest gap between two frames while _measuring (B9)
func _tick() -> void:
	var now := Time.get_ticks_usec()
	if _measuring and _last_us > 0:
		_gap_ms = maxf(_gap_ms, (now - _last_us) / 1000.0)
	_last_us = now


## the mean absolute difference of two pictures over R, G, B, every pixel, on 0..255
func mean_diff(a: Image, b: Image) -> float:
	var x := a.duplicate() as Image
	x.convert(Image.FORMAT_RGBA8)
	var y := b.duplicate() as Image
	y.convert(Image.FORMAT_RGBA8)
	var da := x.get_data()
	var db := y.get_data()
	if da.size() != db.size():
		return INF
	var s := 0
	var n := 0
	for i in range(0, da.size(), 4):
		s += absi(da[i] - db[i]) + absi(da[i + 1] - db[i + 1]) + absi(da[i + 2] - db[i + 2])
		n += 3
	return float(s) / float(n)


## the share of pixels that differ from the corner pixel (the background) by more than 5 levels in any channel
func nonbg_share(img: Image) -> float:
	var x := img.duplicate() as Image
	x.convert(Image.FORMAT_RGBA8)
	var d := x.get_data()
	var n := d.size() / 4
	var c := 0
	for i in n:
		if absi(d[i * 4] - d[0]) > 5 or absi(d[i * 4 + 1] - d[1]) > 5 or absi(d[i * 4 + 2] - d[2]) > 5:
			c += 1
	return float(c) / float(n)


func _clear_cache() -> void:
	var d := DirAccess.open(LibraryThumbs.DIR)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)


func _init() -> void:
	process_frame.connect(_tick)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	Props.register("my test_box", AABB(Vector3.ZERO, Vector3(0.3, 0.3, 0.3)), "")   # one model of "your own" for the My models tab
	m._new_scene()
	await idle()
	_clear_cache()   # B9: a cold start, every picture drawn again
	_measuring = true
	m._library_toggle()
	await idle(2)
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
	await lib.thumbs.settle()   # every tab's tiles drawn: the B9 window ends here
	_measuring = false
	ok(empty_tab.is_empty(), "every category holds at least 1 tile %s" % str(empty_tab))
	ok(shown_all == total, "the tiles on screen add up to the inventory (%d = %d)" % [shown_all, total])
	print("info: cold start drew %d pictures (%d real); longest build %.1f ms, longest draw %.1f ms; failed real: %s" % [lib.thumbs.renders, lib.thumbs.real_renders, lib.thumbs.build_ms_max, lib.thumbs.draw_ms_max, str(lib.thumbs.failed_real)])

	# B9: the frames of the cold open and the tab-by-tab drawing
	ok(_gap_ms <= FRAME_MAX_MS, "B9 the panel's cold open and its tiles drawn tab by tab: the longest frame %.1f ms (at most %.0f)" % [_gap_ms, FRAME_MAX_MS])

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

	# B7: real thumbnails, every object
	await lib.thumbs.settle()
	var real_n := 0
	var least := 1.0
	var least_id := ""
	for it in lib.items:
		var id := String(it["id"])
		var path := LibraryThumbs.real_path(id, String(lib.thumb_source(it)["spec"]))
		var tex := lib.thumbs.picture(id)
		if not FileAccess.file_exists(ProjectSettings.globalize_path(path)) or tex == null:
			continue
		var img := (tex as ImageTexture).get_image()
		var share := nonbg_share(img)
		if img.get_width() == 128 and img.get_height() == 128 and share >= NONBG_MIN:
			real_n += 1
		if share < NONBG_MIN:
			print("info: coverage %s %.2f %% (%d x %d)" % [id, share * 100.0, img.get_width(), img.get_height()])
		if share < least:
			least = share
			least_id = id
	for it in lib.items:
		var pth := LibraryThumbs.real_path(String(it["id"]), String(lib.thumb_source(it)["spec"]))
		if not FileAccess.file_exists(ProjectSettings.globalize_path(pth)):
			print("info: no real PNG for %s (%s)" % [it["id"], pth.get_file()])
	ok(real_n == lib.items.size(), "B7 %d of %d objects have a real 128 px PNG and at least %.0f %% non-background pixels (least: %.1f %%, %s)" % [real_n, lib.items.size(), NONBG_MIN * 100.0, least * 100.0, least_id])

	# B8: the four weapons differ pairwise; the same sword drawn again is the noise floor
	var pics := {}
	for id in WEAPON_IDS:
		pics[id] = (lib.thumbs.picture(id) as ImageTexture).get_image()
	for i in WEAPON_IDS.size():
		for j in range(i + 1, WEAPON_IDS.size()):
			var a: String = WEAPON_IDS[i]
			var b: String = WEAPON_IDS[j]
			var d := mean_diff(pics[a], pics[b])
			ok(d > DIFF_MIN, "B8 %s vs %s: mean difference %.2f (more than %.1f)" % [a, b, d, DIFF_MIN])
	var again: Image = await lib.thumbs.draw_node(LibraryThumbs.weapon_node("sword"), LibraryThumbs.SIZE)
	var noise := mean_diff(again, pics["weapon:sword"]) if again != null else INF
	ok(noise < NOISE_MAX, "B8 noise floor: the sword drawn again differs by %.2f (less than %.1f)" % [noise, NOISE_MAX])

	# B10: a second open draws nothing; a fresh instance on the same folder reads every object from disk
	var r0 := lib.thumbs.renders
	lib.hide_panel()
	lib.open()
	await idle(2)
	await lib.thumbs.settle()
	ok(lib.thumbs.renders == r0, "B10 a second open draws nothing (renders %d -> %d)" % [r0, lib.thumbs.renders])
	var fresh := LibraryThumbs.new()
	root.add_child(fresh)
	for it in lib.items:
		fresh.request(String(it["id"]), lib.thumb_source(it))
	await fresh.settle()
	ok(fresh.renders == 0 and fresh.disk_hits == lib.items.size(), "B10 a fresh instance on the same folder draws 0 (renders %d, disk hits %d of %d)" % [fresh.renders, fresh.disk_hits, lib.items.size()])
	root.remove_child(fresh)
	fresh.free()

	# the Weapons tab, for the eye (user://thumbs/library_weapons.png)
	lib._pick_tab(0)
	await idle(4)
	await lib.thumbs.settle()
	await idle(2)
	var shot := root.get_texture().get_image()
	var shot_path := ProjectSettings.globalize_path("user://thumbs/library_weapons.png")
	shot.save_png(shot_path)
	print("SHOT %s" % shot_path)

	print("LIBRARY TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
