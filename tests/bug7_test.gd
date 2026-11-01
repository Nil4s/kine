extends SceneTree
## BUG7 (Nick 11-01): "when you press Examples it puts you instantly in modeling mode without you asking for it, instead of only showing examples
## and coming back; plus the examples we have are only animations, none of the pretty 3D stuff you built is available yet".
## godot --path . --position 4000,4000 -s tests/bug7_test.gd     (needs a window and the CAD DLL; real clicks at 1280 x 720 on the real start screen)
## Bars:
##   1 PRESS     Examples (a real click) leaves the app as it was: the start screen is still up, the same scene object, the same page, the same Easy/Expert mode,
##               the same project kind; the Open grid now says Examples and Back to my projects shows
##   2 LIST      the grid lists at least 8 Building examples AND the animation examples (3); every card has a name and a tag
##   3 PICTURES  every Building card has a picture drawn from its real geometry: pixel stddev above BAR_SD and more than BAR_PART of the pixels differ from the
##               empty background (the Nice picture's gradient for a part, the corner colour for the room)
##   4 CHIPS     the Building chip shows only Building cards, the Animation chip only the animation ones
##   5 BACK      Back to my projects returns to the saved scenes (the test's own saved scene, no example card)
##   6 OPEN      a click on a Building card opens Easy Part with that part: the same bodies as building it by hand through the same builder, volume within 1 %
##               (every part example); at least 8 of them are ONE body (the box-and-lid ones are two by design)
##   7 ANIM      a click on an animation card opens that scene as before (kind animation, its cards, a copy with no path)
## Shots in C:/Temp/claude/bug7/ . Only user:// is written (and the shots).
var fails := 0
var m: Node
var ss: StartScreen
const SHOT := "C:/Temp/claude/bug7"
const DIRT := "user://bug7_test"
const BAR_SD := 0.03
const BAR_PART := 0.03


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func click(c: Control) -> bool:
	if c == null or not c.is_visible_in_tree():
		return false
	var sc: Node = c.get_parent()
	while sc != null and not (sc is ScrollContainer):
		sc = sc.get_parent()
	if sc != null and not (sc as Control).get_global_rect().encloses(c.get_global_rect()):
		(sc as ScrollContainer).ensure_control_visible(c)
		await idle(2)
	var p := c.get_global_rect().get_center()
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
	return true


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func tiles_of(kind: String) -> Array:
	var out := []
	for p in ss._tiles:
		if String(ss._tiles[p]["kind"]) == kind:
			out.append(p)
	return out


func visible_paths() -> Array:
	var out := []
	for p in ss._tiles:
		if (ss._tiles[p]["tile"] as Control).visible:
			out.append(p)
	return out


func sd_of(img: Image) -> float:
	var n := 0
	var sum := 0.0
	var sum2 := 0.0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			var l := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
			sum += l
			sum2 += l * l
			n += 1
	var mean := sum / float(n)
	return sqrt(maxf(sum2 / float(n) - mean * mean, 0.0))


## the share of pixels that differ from the empty Nice-picture background (the part and its shadow) / from the corner colour (the room)
func drawn_share(img0: Image, part: bool) -> float:
	var img := img0.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	var bg: Image = NiceRender.background(img.get_size()) if part else null
	var corner := img.get_pixel(1, 1)
	var n := 0
	var d := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			var r: Color = bg.get_pixel(x, y) if part else corner
			if absf(c.r - r.r) + absf(c.g - r.g) + absf(c.b - r.b) > 0.15:
				d += 1
			n += 1
	return float(d) / float(n)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	ss = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	var src: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json"))
	src["kind"] = "modeling"
	var mine := DIRT + "/bug7_mine.json"
	var f := FileAccess.open(mine, FileAccess.WRITE)
	f.store_string(JSON.stringify(src))
	f.close()
	ss.dirs_override = [DIRT]

	# a project the user is in: Easy Part building, so a switch to animation / modeling would show
	m._new_scene()
	m.S.kind = "building"
	m._page_set("BUILD")
	if m.easy != null:
		m.easy.set_on(true)
	await idle(3)
	var s_before = m.S
	var page_before: String = m.cur_page
	var easy_before: bool = m.easy.on
	var kind_before: String = m.S.kind
	ss.show_screen()
	await idle(4)
	ok(ss.visible and not ss._examples_mode, "0 the start screen opens on the user's projects")
	await shot("projects")

	# 1 PRESS
	ok(await click(ss.find_child("examples_btn", true, false)), "1 Examples clicked")
	await idle(3)
	ok(ss.visible and m.S == s_before and m.cur_page == page_before and m.easy.on == easy_before and m.S.kind == kind_before,
		"1 PRESS: still on the start screen, same scene, page %s, Easy %s, kind %s (now page %s, Easy %s, kind %s, screen %s)" % [page_before, easy_before, kind_before, m.cur_page, m.easy.on, m.S.kind, ss.visible])
	ok(ss._open_title.text == "Examples" and ss._back_btn.visible and not ss.find_child("examples_btn", true, false).visible, "1 the grid says Examples and Back to my projects shows")

	# 2 LIST
	var bld := tiles_of("building")
	var ani := tiles_of("animation")
	ok(bld.size() >= 8, "2 LIST: %d Building examples (bar 8)" % bld.size())
	ok(ani.size() >= 3, "2 LIST: %d animation examples (bar 3)" % ani.size())
	var noname := []
	for p in ss._tiles:
		var t: Dictionary = ss._tiles[p]
		if String(t["name"]).strip_edges() == "" or (t["tag"] as Label).text.strip_edges() == "":
			noname.append(p)
	ok(noname.is_empty(), "2 LIST: every card has a name and a tag %s" % [noname])
	ok(not ss._tiles.has(mine), "2 LIST: the user's own scene is not among the examples")

	# 3 PICTURES
	var waited := 0
	var pending := true
	while pending and waited < 1500:
		pending = false
		for p in bld:
			if (ss._tiles[p]["pic"] as TextureRect).texture == null:
				pending = true
		await process_frame
		waited += 1
	await idle(3)
	var bad := []
	var worst_sd := 9.0
	var worst_share := 9.0
	for p in bld:
		var tex: Texture2D = (ss._tiles[p]["pic"] as TextureRect).texture
		if tex == null:
			bad.append(String(p).get_file() + " none")
			continue
		var img := tex.get_image()
		var is_part := not String(p).ends_with("/room.json")
		var sd := sd_of(img)
		var share := drawn_share(img, is_part)
		worst_sd = minf(worst_sd, sd)
		worst_share = minf(worst_share, share)
		if sd < BAR_SD or share < BAR_PART:
			bad.append("%s sd %.3f share %.3f" % [String(p).get_file(), sd, share])
	ok(bad.is_empty(), "3 PICTURES: all %d Building cards are drawn (lowest stddev %.3f vs bar %.2f, lowest drawn share %.3f vs bar %.2f) %s" % [bld.size(), worst_sd, BAR_SD, worst_share, BAR_PART, bad])
	await shot("examples")

	# 4 CHIPS
	ss._pick_chip("building")
	await idle(2)
	var shown := visible_paths()
	var only_b := true
	for p in shown:
		only_b = only_b and String(ss._tiles[p]["kind"]) == "building"
	ok(only_b and shown.size() == bld.size(), "4 CHIPS: Building shows %d cards, all Building" % shown.size())
	ss._pick_chip("animation")
	await idle(2)
	shown = visible_paths()
	var only_a := true
	for p in shown:
		only_a = only_a and String(ss._tiles[p]["kind"]) == "animation"
	ok(only_a and shown.size() == ani.size(), "4 CHIPS: Animation shows %d cards, all animation" % shown.size())
	ss._pick_chip("all")

	# 5 BACK
	ok(await click(ss._back_btn), "5 Back clicked")
	await idle(3)
	ok(ss.visible and not ss._examples_mode and ss._tiles.has(mine) and tiles_of("building").is_empty() and ss._open_title.text == "Open",
		"5 BACK: the saved scenes again (own scene listed %s, %d tiles, no Building example)" % [ss._tiles.has(mine), ss._tiles.size()])
	await shot("back")

	# 6 OPEN every example
	var checked := 0
	var single := 0
	for e in StartExamples.LIST:
		var id: String = e["id"]
		var path := StartExamples.path_of(id)
		ss.show_screen()
		await idle(2)
		await click(ss.find_child("examples_btn", true, false))
		await idle(2)
		var tile: Control = ss._tiles[path]["tile"] if ss._tiles.has(path) else null
		if tile == null:
			ok(false, "6 OPEN %s: has a card" % id)
			continue
		await click(tile)
		await idle(5)
		if e.has("house"):
			ok(not ss.visible and m.S.kind == "building" and m.cur_page == "BUILD" and (m.S.building.get("rooms", []) as Array).size() >= 1,
				"6 OPEN %s: the room opens on BUILD with its house (%d rooms)" % [id, (m.S.building.get("rooms", []) as Array).size()])
			continue
		var res := Part.replay(m.S.part, -1, {})
		var want := Part.replay(StartExamples.part_record(e), -1, {})
		var v := float(res["volume"])
		var w := float(want["volume"])
		var in_easy: bool = m.bld.part.on and m.bld.part.easy and m.easy.on
		var good: bool = not ss.visible and m.S.kind == "building" and m.cur_page == "BUILD" and in_easy and int(res["bodies"]) == int(want["bodies"]) and w > 0.0 and absf(v - w) <= 0.01 * w and (res["errors"] as Dictionary).is_empty()
		ok(good, "6 OPEN %s: Easy Part, %d body(ies) as built by hand (%d), volume %.2f cm3 vs %.2f (%.3f %%), screen %s, page %s, easy part %s, errors %s" % [id, int(res["bodies"]), int(want["bodies"]), v * 1.0e6, w * 1.0e6, 100.0 * absf(v - w) / maxf(w, 1.0e-9), ss.visible, m.cur_page, in_easy, res["errors"]])
		ok(m.scene_path == "" and m.S.name.ends_with("_mine"), "6 OPEN %s: opened as a copy (no path, name %s)" % [id, m.S.name])
		checked += 1
		if int(res["bodies"]) == 1:
			single += 1
		if checked == 1:
			await shot("opened_" + id)
	ok(checked >= 8 and single >= 8, "6 OPEN: %d part examples opened and measured, %d of them one body (bar 8)" % [checked, single])

	# 7 ANIM
	ss.show_screen()
	await idle(2)
	await click(ss.find_child("examples_btn", true, false))
	await idle(2)
	var apath := "res://scenes/walk_bat.json"
	ok(ss._tiles.has(apath), "7 ANIM: the walk example has a card")
	await click(ss._tiles[apath]["tile"])
	await idle(5)
	ok(not ss.visible and m.S.kind == "animation" and m.S.cards.size() > 0 and m.scene_path == "" and m.cur_page == "POSE",
		"7 ANIM: the walk example opens as an animation copy (kind %s, %d cards, path '%s', page %s)" % [m.S.kind, m.S.cards.size(), m.scene_path, m.cur_page])

	print("bug7: %d fail" % fails)
	quit(1 if fails > 0 else 0)
