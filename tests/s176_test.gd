extends SceneTree
## godot --path . --position 4000,4000 -s tests/s176_test.gd     (Friday plan 176: one walk per Parts library category; scripts/easy_part.gd; needs the CAD DLL)
## Walks EVERY category of the Easy Part Parts library (the list is read from EasyPartBase.LIB_CATS / LIB_READY, nothing hardcoded here), with REAL clicks at
## 1280 x 720: the Parts chip, the category chip, then the FIRST and the LAST chip of its page. Measured from the built result (mesh vertices in mm, the kernel volume).
## Per chip: the part is blank before the click, and after it
##   SOLID   a solid was added (faces on the floor, volume > 0, bodies >= 1)
##   BOX     the bounding box fits inside 1 m (every extent <= 1000 mm); Wood boards are real stock (8 ft 2x4, 4 x 8 ft sheet): 2500 mm
##   ONE     the click is ONE undo step
##   SCREEN  the chip sits on the 1280 x 720 screen, inside every scroll view above it, and not under the view column
## and per category: opening it is not an action (no undo step, no solid), and a category with no parts yet says "coming soon" and builds nothing.
## No SCRIPT ERROR anywhere in the log is checked by wtest.sh (it counts them).
## One line per category: "cat Screws: first M3 x 10 ... last M6 x 30 ...". Shots: C:/Temp/claude/s176/<category>.png
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s176"
const DIRT := "user://s176_test"
var pu: PartUI
var ep


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


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


func ev_move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(4)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm.replace(" ", "_")])


## a constant of the Easy Part script (or one of its base scripts)
func const_of(nm: String) -> Variant:
	var s = ep.get_script()
	while s != null:
		var mp: Dictionary = s.get_script_constant_map()
		if mp.has(nm):
			return mp[nm]
		s = s.get_base_script()
	return null


## what a user does when a chip is out of the panel's view: scroll it in (wheel); the bars below then judge where it ended up
func reveal(c: Control) -> void:
	if c == null or not c.is_visible_in_tree():
		return
	var n: Node = c.get_parent()
	while n != null:
		if n is ScrollContainer:
			(n as ScrollContainer).ensure_control_visible(c)
		n = n.get_parent()
	await idle(3)


## "" when the chip can be clicked where it is; else why not (screen, scroll views, the view column)
func where_bad(c: Control) -> String:
	if c == null:
		return "missing"
	if not c.is_visible_in_tree():
		return "not visible"
	var r := c.get_global_rect()
	if not Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(r):
		return "off the 1280 x 720 screen %s" % str(r)
	var n: Node = c.get_parent()
	while n != null:
		if n is ScrollContainer:
			var sr := (n as ScrollContainer).get_global_rect().grow(1.0)
			if not sr.encloses(r):
				return "outside its scroll view %s vs %s" % [str(r), str(sr)]
		n = n.get_parent()
	if ep.view_box != null and ep.view_box.is_visible_in_tree() and ep.view_box.get_global_rect().intersects(r):
		return "under the view column %s" % str(ep.view_box.get_global_rect())
	return ""


## the built result in mm: {"n": faces, "ext": biggest extent, "ctr": biggest |coordinate|, "vol": mm3, "bodies": n}
func geom() -> Dictionary:
	var faces: Array = Part.body_faces(m.S.part)
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	var big := 0.0
	for f in faces:
		var arr: PackedVector3Array = f
		for v in arr:
			var p := v * 1000.0
			lo = lo.min(p)
			hi = hi.max(p)
			big = maxf(big, maxf(absf(p.x), maxf(absf(p.y), absf(p.z))))
	if faces.is_empty():
		return {"n": 0, "ext": 0.0, "big": 0.0, "vol": 0.0, "bodies": 0}
	var sz := hi - lo
	return {"n": faces.size(), "ext": maxf(sz.x, maxf(sz.y, sz.z)), "big": big, "vol": float(pu.res.get("volume", 0.0)) * 1e9, "bodies": int(pu.res.get("bodies", 0))}


## the chips of one category's page, in page order: [[label, Button], ...]
func chips_of(cat: String) -> Array:
	var out := []
	var d: Dictionary = {}
	match cat:
		"Screws":
			d = ep.screw_btns
		"Bearings":
			d = ep.bear_btns
		"Brackets":
			d = ep.bracket_btns
		"Clips and feet":
			d = ep.clip_btns
		"Handles":
			d = ep.handle_btns
		"Wheels":
			d = ep.wheel_btns
		"Boards":
			d = ep.board_btns
		"Wood boards":
			d = ep.wood_btns
		"Favourites":
			d = ep.fav_btns
		"Gears":
			return [["Gear pair", ep.gp_pick], ["Cam and follower", ep.cam_pick]]
		"Hinges":
			return [["Hinge", ep.hinges_btn]]
		"Springs":
			return [["Spring", ep.spring_pick]]
		"Type it":
			return [["Build it", ep.type_go]]
	for k in d:
		out.append([str(k), d[k]])
	return out


func blank() -> void:
	m.S.part = {}
	await idle(6)


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
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.bld.part.set_on(false)
	m.S.part = {}
	await idle(8)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the parts cannot be built")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep
	var cats: Array = const_of("LIB_CATS")
	var ready: Array = const_of("LIB_READY")
	ok(cats != null and cats.size() >= 15 and ready != null, "0 the category list is read from the code (%d categories, %d with parts)" % [cats.size() if cats != null else -1, ready.size() if ready != null else -1])
	var pb := root.find_child("easypart_chip_parts", true, false) as Button
	await click_ctl(pb)   # the Parts chip opens the library page
	var summary := []
	for cat in cats:
		var cb: Button = ep.lib_btns.get(cat)
		var tag := "cat %s:" % cat
		await blank()
		var u0: int = m.undo.size()
		if ep.lib_box == null or not ep.lib_box.is_visible_in_tree():   # a chip like Hinge closes the page: open Parts again
			await click_ctl(pb)
			await blank()
		await reveal(cb)
		var why_cat := where_bad(cb)
		if why_cat == "":
			await click_ctl(cb)
		var open_ok: bool = why_cat == "" and ep.lib_cat == cat and m.undo.size() == u0 and int(geom()["n"]) == 0
		ok(open_ok, "%s the category chip is clickable [%s], opens its page, no undo step (%d -> %d), no solid" % [tag, why_cat, u0, m.undo.size()])
		await shot(cat)
		var chips := chips_of(cat)
		if not (cat in ready):
			var soon: bool = ep.lib_soon.is_visible_in_tree() and ep.lib_soon.text.contains(cat) and ep.lib_soon.text.to_lower().contains("coming soon")
			ok(soon and chips.is_empty(), "%s no parts yet: the page says coming soon in words and shows no chip [%s]" % [tag, ep.lib_soon.text])
			print("line %s coming soon" % tag)
			summary.append("%s: coming soon" % cat)
			continue
		ok(chips.size() >= 1, "%s the page has %d chip(s)" % [tag, chips.size()])
		if chips.is_empty():
			summary.append("%s: NO CHIPS" % cat)
			continue
		var picks := [chips[0]]
		if chips.size() > 1:
			picks.append(chips[chips.size() - 1])
		var line := ""
		var idx := 0
		for pk in picks:
			var label: String = pk[0]
			var b: Button = null   # looked up again now: the Favourites row rebuilds its chips after every press
			for cc in chips_of(cat):
				if cc[0] == label and is_instance_valid(cc[1]):
					b = cc[1]
			var which := "first" if idx == 0 else "last"
			idx += 1
			if idx > 1:   # the last chip: a blank part again, the same page open
				await blank()
				if ep.lib_cat != cat or not ep.parts_open:
					if ep.lib_box == null or not ep.lib_box.is_visible_in_tree():
						await click_ctl(pb)
					await reveal(cb)
					await click_ctl(cb)
					await blank()
			if cat == "Type it":
				ep.type_edit.text = PartWords.EXAMPLE
			b = null
			for cc in chips_of(cat):   # looked up again after the waits above
				if cc[0] == label and is_instance_valid(cc[1]):
					b = cc[1]
			await reveal(b)
			var c_bad := where_bad(b)
			var ub: int = m.undo.size()
			if c_bad == "":
				await click_ctl(b)
			else:
				await shot(cat + "_bad")
			var g := geom()
			var added: bool = int(g["n"]) > 0 and float(g["vol"]) > 0.0 and int(g["bodies"]) >= 1
			var lim := 2500.0 if cat == "Wood boards" else 1000.0   # the wood chips are stock by real size: an 8 ft 2x4 (2438 mm) and a 4 x 8 ft sheet (2440 mm); every other part is inside 1 m
			var inside: bool = float(g["ext"]) <= lim and float(g["big"]) <= lim
			var one: bool = m.undo.size() == ub + 1
			var tg := "%s %s chip [%s]" % [tag, which, label]
			ok(c_bad == "", "%s on screen, in its scroll view, not under the view column [%s]" % [tg, c_bad])
			ok(added, "%s added a solid (faces %d, volume %.0f mm3, bodies %d)" % [tg, int(g["n"]), float(g["vol"]), int(g["bodies"])])
			ok(inside, "%s bbox inside %.0f mm (biggest extent %.1f mm, farthest coordinate %.1f mm)" % [tg, lim, float(g["ext"]), float(g["big"])])
			ok(one, "%s ONE undo step (%d -> %d)" % [tg, ub, m.undo.size()])
			line += " %s [%s] %s ext %.0f mm vol %.0f mm3 undo +%d;" % [which, label, "solid" if added else "NO SOLID", float(g["ext"]), float(g["vol"]), m.undo.size() - ub]
			await shot("%s_%s" % [cat, which])
		print("line %s%s" % [tag, line])
		summary.append("%s ok" % cat)
	# Kids: a toggle chip on the library page, not a category: bigger chips, no solid, no undo step; pressed again it goes back
	await blank()
	await click_ctl(pb) if not ep.parts_open else await idle(1)
	var kb: Button = ep.kids_btn
	var u1: int = m.undo.size()
	var h0 := (ep.lib_btns["Screws"] as Button).size.y
	var kbad := where_bad(kb)
	if kbad == "":
		await click_ctl(kb)
	var h1 := (ep.lib_btns["Screws"] as Button).size.y
	await shot("Kids")
	if kbad == "":
		await click_ctl(kb)
	var h2 := (ep.lib_btns["Screws"] as Button).size.y
	ok(kbad == "" and h1 > h0 and absf(h2 - h0) < 0.5 and m.undo.size() == u1 and int(geom()["n"]) == 0, "cat Kids: chip clickable [%s], category chips %.0f -> %.0f px tall and back to %.0f, no undo step, no solid" % [kbad, h0, h1, h2])
	print("line cat Kids: chips %.0f -> %.0f -> %.0f px" % [h0, h1, h2])
	print("walk: " + " | ".join(summary))
	print("s176: %d fail" % fails)
	quit(1 if fails > 0 else 0)
