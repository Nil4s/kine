extends SceneTree
## WHAT DO YOU WANT TO BUILD? (scripts/build_choose.gd, mockup C:/Temp/claude/partmock/build_choose.png). Bars, stated before measuring
## (real mouse clicks through root.push_input):
##   0 a test launch shows no chooser by itself
##   1 the 3D BUILDING start card, with the chooser on, shows the chooser over BUILD with 6 cards (House / Set, Part, Vehicle,
##     Prop pack, From a template, Import STEP), each with an Easy and an Expert button
##   2 House Easy -> the chooser closes, Easy Building (easy on, BUILD, room tool); House Expert -> Expert BUILD, room tool, no Easy
##   3 the greyed cards (Part, Vehicle, From a template, and Import STEP with no KineCAD) do nothing but say why: the chooser stays,
##     the mode and page are as they were, the card and the status line carry the reason
##   4 Prop pack opens the object library on the Build furniture category (Easy and Expert)
##   5 "What to build" on the BUILD ribbon (Expert) and on Easy's bar reopens the chooser
##   6 Import STEP is live when KCad.available(): a picked file shows as a solid on BUILD (read, not clicked, when the DLL is absent)
##   7 fit at 1280x720 and 1024x600: six cards and their buttons inside the window, no overlap
##   1b every card has a rendered texture, non-uniform (pixel stddev > 8), cached under user://build_choose_art; greyed cards dimmed
##   8 no key names in the chooser's texts (mouse only)
##   shots: C:/Temp/claude/buildchoose/{choose,choose_art,choose_1024,easy}.png. Only user:// is written.
var fails := 0
var m: Node
const KCad := preload("res://scripts/kcad.gd")
const SHOT := "C:/Temp/claude/buildchoose"
const KEYS := ["Esc", "Escape", "Tab", "Enter", "Return", "Delete", "Del", "Ctrl", "Alt", "Shift", "Backspace", "Space", "F1", "F2", "F3", "F4", "F5"]
const IDS := ["house", "part", "vehicle", "props", "template", "step"]


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func click(c: Control) -> void:
	var p: Vector2 = c.get_global_rect().get_center()
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


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func texts_under(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Label and (n as Label).text.strip_edges() != "":
		out.append((n as Label).text)
	elif n is Button and (n as Button).text.strip_edges() != "":
		out.append((n as Button).text)
	for c in n.get_children():
		texts_under(c, out)


func key_in(t: String) -> String:
	var s := t
	for ch in ["/", ",", ".", ":", "(", ")", "+", "\n", "!", "?", ";", "\""]:
		s = s.replace(ch, " ")
	for w in s.split(" ", false):
		if KEYS.has(w):
			return w
	return ""


## the Building card of the start screen, clicked (a new project; unsaved work above is discarded)
func start_building(ss: StartScreen) -> void:
	ss.show_screen()
	await idle(3)
	await click(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(8)


func b(id: String, mode: String) -> Button:
	return m.build_choose.btns[id][mode]


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
	var bc: BuildChoose = m.build_choose
	var dirt := "user://buildchoose_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dirt))
	ss.dirs_override = [dirt]

	# 0 a test launch gets no chooser by itself
	await start_building(ss)
	ok(m.S.kind == "building" and not bc.open, "0 a test launch shows no chooser by itself (it would cover the page the other tests click)")

	# 1 the chooser
	bc.auto = true
	await start_building(ss)
	ok(bc.open and bc.root_box.is_visible_in_tree() and m.cur_page == "BUILD" and m.S.kind == "building", "1 Building card -> the chooser over BUILD (open %s, page %s)" % [bc.open, m.cur_page])
	var six := bc.cards.size() == 6
	for id in IDS:
		six = six and bc.cards.has(id) and (bc.cards[id] as Control).is_visible_in_tree() and b(id, "easy").is_visible_in_tree() and b(id, "expert").is_visible_in_tree()
	ok(six, "1 six cards, each with an Easy and an Expert button")
	# 1 art: a real render on every card (non-uniform pixels), cached under user://, the greyed ones dimmed
	var waited := 0
	while waited < 900 and not bc.art.ready_all():
		await process_frame
		waited += 1
	await idle(3)
	var flat := []
	var sds := []
	for id in IDS:
		var t: Texture2D = bc.art.get_art(id)
		if t == null or t.get_width() < 8:
			flat.append(id + " no texture")
			continue
		var img := t.get_image()
		var n := 0
		var sum := 0.0
		var sum2 := 0.0
		for y in range(0, img.get_height(), 2):
			for x in range(0, img.get_width(), 2):
				var l := img.get_pixel(x, y).get_luminance() * 255.0
				sum += l
				sum2 += l * l
				n += 1
		var sd := sqrt(maxf(0.0, sum2 / n - (sum / n) * (sum / n)))
		sds.append("%s %.1f" % [id, sd])
		if sd <= 8.0:
			flat.append("%s stddev %.1f" % [id, sd])
	ok(flat.is_empty(), "1 art: every card has a rendered texture with non-uniform pixels (stddev > 8): %s %s" % [sds, flat])
	var cached := true
	for id in IDS:
		cached = cached and FileAccess.file_exists(BuildChooseArt.cache_path(id)) and BuildChooseArt.cache_path(id).begins_with("user://")
	ok(cached and bc.art.renders + bc.art.disk_hits >= 6, "1 art: the six pictures are cached under user://build_choose_art/ (renders %d, disk %d)" % [bc.art.renders, bc.art.disk_hits])
	var shown := true
	for a in bc._arts:
		shown = shown and (a as Control).is_visible_in_tree() and bc.art.get_art((a as BuildChoose.Art).kind) != null
	ok(shown, "1 art: the cards show their pictures")
	var dim := (bc.cards["vehicle"] as CanvasItem).modulate.a < 1.0 and (bc.cards["house"] as CanvasItem).modulate.a == 1.0   # Vehicle: Part went live with the Part workspace (w4-partws)
	ok(dim, "1 art: a greyed card shows its picture dimmed, a live one at full strength")
	await shot("choose")
	await shot("choose_art")

	# 7 fit (the live chooser)
	for sz in [Vector2i(1280, 720), Vector2i(1024, 600)]:
		root.size = sz
		root.content_scale_size = sz
		await idle(8)
		var vp := Rect2(Vector2.ZERO, Vector2(sz))
		var bad := []
		var rects := []
		for id in IDS:
			var cr: Rect2 = (bc.cards[id] as Control).get_global_rect()
			rects.append(cr)
			var cover: Rect2 = bc.root_box.get_global_rect()
			if not cover.grow(1.0).encloses(cr):
				bad.append("%s card %s runs out of the cover %s" % [id, cr, cover])
			if m.ui_status != null and m.ui_status.visible and cr.end.y > m.ui_status.get_global_rect().position.y:
				bad.append("%s card %s runs over the status line" % [id, cr])
			if not vp.encloses(cr):
				bad.append("%s outside %s" % [id, cr])
			for mode in ["easy", "expert"]:
				var br: Rect2 = b(id, mode).get_global_rect()
				if not cr.encloses(br) or br.size.x < 40.0 or br.size.y < 24.0:
					bad.append("%s %s button %s not in card %s" % [id, mode, br, cr])
			var w: Label = bc.whys[id]
			if w.visible and not cr.encloses(w.get_global_rect()):
				bad.append("%s why text out of card" % id)
		for i in rects.size():
			for j in range(i + 1, rects.size()):
				if (rects[i] as Rect2).intersects(rects[j]):
					bad.append("cards %d and %d overlap" % [i, j])
		ok(bad.is_empty(), "7 at %dx%d six cards and their buttons are inside the window, no overlap %s" % [sz.x, sz.y, bad])
		if sz.x == 1024:
			await shot("choose_1024")
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	await idle(8)

	# 8 mouse only
	var tx := []
	texts_under(bc.root_box, tx)
	var kk := ""
	for t in tx:
		kk = kk if kk != "" else key_in(String(t))
	ok(kk == "" and tx.size() > 20, "8 no key names in the chooser's texts (%d texts, first key name '%s')" % [tx.size(), kk])

	# 3 greyed cards say why
	m.easy.set_on(false)
	await idle(3)
	var page0: String = m.cur_page
	var greys_ok := true
	for id in ["vehicle"] + ([] if KCad.available() else ["step", "part"]):   # 2a89b914: From a template opens the starter buildings now. Part is live with KineCAD since the Part workspace (w4-partws)
		for mode in ["easy", "expert"]:
			m._say("")
			await click(b(id, mode))
			var why := String(bc.why_not(id))
			var said: String = m.ui_status.text if m.ui_status != null else ""
			var card_says: bool = (bc.whys[id] as Label).visible and (bc.whys[id] as Label).text == why and why != ""
			var still: bool = bc.open and m.cur_page == page0 and not m.easy.on and m.S.kind == "building"
			if not (card_says and still and said.contains(why.substr(0, 20))):
				greys_ok = false
				print("   grey %s %s: card_says %s still %s said '%s'" % [id, mode, card_says, still, said])
	ok(greys_ok, "3 the greyed cards (Vehicle%s) do nothing but say why: the chooser stays, mode and page unchanged" % ("" if KCad.available() else ", Import STEP, Part"))
	ok(not (bc.whys["house"] as Label).visible and not (bc.whys["props"] as Label).visible, "3 the live cards carry no reason")
	if KCad.available():   # 3b PART: the card opens the Part workspace on BUILD (Expert) or Easy Part (Easy). Easy Part was "not built yet" until
		# commit 'Easy Part from the chooser' (972f9fa6, w4-partflow): Part Easy now closes the chooser and opens Easy Part, as the same record
		await click(b("part", "easy"))
		ok(not bc.open and m.bld.part.easy and m.bld.part.on and m.easy.on and m.cur_page == "BUILD", "3b Part Easy opens Easy Part (page %s, part easy %s)" % [m.cur_page, m.bld.part.easy])
		bc.show_chooser()
		await idle(3)
		await click(b("part", "expert"))
		await idle(3)
		ok(not bc.open and m.cur_page == "BUILD" and m.bld.part.on and not m.easy.on, "3b Part Expert opens the Part workspace (page %s, part %s)" % [m.cur_page, m.bld.part.on])
		m.bld.part.set_on(false)
		bc.show_chooser()
		await idle(3)

	# 2 House Easy / Expert
	await click(b("house", "easy"))
	ok(not bc.open and m.easy.on and m.cur_page == "BUILD" and m.bld.tool == "Room" and m.easy.building.is_active(), "2 House Easy -> Easy Building with the room tool (easy %s, tool %s)" % [m.easy.on, m.bld.tool])
	await shot("easy")

	# 5 reopen from Easy's bar
	var rb := m.ui_root.find_child("easybuild_btn_what_to_build", true, false) as Button
	ok(rb != null and rb.is_visible_in_tree(), "5 Easy's bar has a What to build button")
	if rb != null:
		await click(rb)
	ok(bc.open and bc.root_box.is_visible_in_tree(), "5 What to build on Easy's bar reopens the chooser")

	await click(b("house", "expert"))
	ok(not bc.open and not m.easy.on and m.cur_page == "BUILD" and m.bld.tool == "Room" and m.S.kind == "building", "2 House Expert -> Expert BUILD with the room tool (easy %s, tool %s)" % [m.easy.on, m.bld.tool])
	ok(m.ui_ribbon["BUILD"].is_visible_in_tree(), "2 Expert BUILD's ribbon shows")

	# 5 reopen from the Expert ribbon
	var rb2 := m.ui_ribbon["BUILD"].find_child("build_choose_open", true, false) as Button
	ok(rb2 != null and rb2.is_visible_in_tree(), "5 the BUILD ribbon has a What to build button")
	if rb2 != null:
		await click(rb2)
	ok(bc.open, "5 What to build on the ribbon reopens the chooser")

	# 4 Prop pack
	for mode in ["expert", "easy"]:
		if m.ui_library != null:
			m.ui_library.hide_panel()
		if not bc.open:
			bc.show_chooser()
			await idle(3)
		await click(b("props", mode))
		var lib: ObjectLibrary = m.ui_library
		ok(not bc.open and lib != null and lib.visible and lib.view == "Build furniture" and m.easy.on == (mode == "easy"), "4 Prop pack %s opens the object library on Build furniture (easy %s, view '%s')" % [mode, m.easy.on, lib.view if lib != null else "-"])

	# 6 Import STEP
	if KCad.available():
		var f := "res://tests/data/bracket.step"
		bc.step_picker = func(cb: Callable): cb.call(f)
		bc.show_chooser()
		await idle(3)
		await click(b("step", "expert"))
		ok(m.bld.root3.find_child("build_step_solid", true, false) != null and not bc.open, "6 Import STEP shows a solid on BUILD")
	else:
		ok(not b("step", "easy").disabled and String(bc.why_not("step")).contains("KineCAD"), "6 KineCAD is absent: Import STEP is greyed with the reason (live branch is not run here)")

	# 10 PARTFLOW (w4-partflow): Easy hides the two not-ready cards (Expert keeps them with why); Part Easy opens Easy Part; a card leaves the Part
	# workspace (Expert's way back to the house); the Part ribbon keeps "What to build" with its words
	m.easy.set_on(true)
	bc.show_chooser()
	await idle(4)
	var pf_vis := []
	for id in ["house", "part", "vehicle", "props", "template", "step"]:
		pf_vis.append(bc.cards[id].visible)
	ok(pf_vis == [true, true, false, true, false, true] and bc.whys["vehicle"].visible == false, "10 Easy chooser: the not-ready Vehicle and From a template cards are gone (visible %s)" % str(pf_vis))
	m.easy.set_on(false)
	bc.show_chooser()
	await idle(4)
	ok(bc.cards["vehicle"].visible and bc.cards["template"].visible and (bc.whys["vehicle"] as Label).visible and (bc.whys["vehicle"] as Label).text != "", "10 Expert chooser: Vehicle and From a template stay, greyed, with why")
	if KCad.available():
		await click(b("part", "easy"))
		await idle(8)
		ok(not bc.open and m.bld.part.easy and m.bld.part.on and m.cur_page == "BUILD" and m.easy.on, "10 Part Easy from the chooser opens Easy Part (page %s, part easy %s, easy %s)" % [m.cur_page, m.bld.part.easy, m.easy.on])
		var pf_rb: Button = m.bld.part.reopen_btn
		ok(pf_rb != null and pf_rb.is_visible_in_tree() and pf_rb.text == "What to build" and not m.bld.part.reopen_btn.disabled, "10 Easy Part: the What to build button is there (text '%s')" % (pf_rb.text if pf_rb != null else "-"))
		m.bld.part.ep.to_expert()
		await idle(6)
		var pf_rb2: Button = m.bld.part.reopen_btn
		ok(m.bld.part.on and not m.bld.part.easy and pf_rb2.is_visible_in_tree() and pf_rb2.text == "What to build", "10 Expert Part: the ribbon keeps What to build with its words")
		await click(pf_rb2)
		await idle(6)
		ok(bc.open and m.bld.part.on, "10 Expert Part: What to build reopens the chooser over the part (the Part workspace stays until a card is chosen)")
		await click(b("house", "expert"))
		await idle(6)
		ok(not bc.open and not m.bld.part.on and m.bld.tool == "Room" and m.cur_page == "BUILD", "10 from Expert Part, the House card leaves the Part workspace for the house (part on %s, tool %s)" % [m.bld.part.on, m.bld.tool])
	else:
		print("   (no KineCAD: the Part Easy bar is not run)")

	m.easy.set_on(false)
	print("buildchoose_test: %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(0 if fails == 0 else 1)
