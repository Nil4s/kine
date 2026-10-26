extends SceneTree
## MODEL TASK CARDS (scripts/model_cards.gd, mockup B): "What do you want to do?" over the MODEL page. Bars, stated before measuring:
##   1 the first Expert open of MODEL (a real launch) shows 4 cards, each with a Start, and "Show all the tools"; the ribbon stays
##     on screen; no key names in the cards' text
##   2 each Start reaches its tool, state checked: shape -> the BODY page; part -> the body mesh open on MODEL; armour -> the
##     armour panel on the open body; prop -> a BUILDING project on the BUILD page (a scene with unsaved work gets the test cube)
##   3 "Show all the tools" closes the cards (remembered: the next MODEL open has none), the ribbon is still there
##   4 an Expert MODEL that was seen, and a test launch, show no cards
##   5 the rule (Easy always; Expert first open only) as a truth table; Easy hides the MODEL page today, so it is read, not clicked
##   6 Done / back: the POSE page button leaves MODEL and the cards go with it
##   7 at 1280x720 (and 1600x900) the cards, the link and the title stay on screen and do not overlap each other or the ribbon
## The Starts and the page buttons are real clicks (mouse events at the button's centre).
var fails := 0
func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1

func idle(n := 3) -> void:
	for i in n:
		await process_frame

func click(b: Control) -> void:
	var p: Vector2 = root.get_final_transform() * (b.get_global_rect().get_center())
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e)
		await process_frame
	await idle(3)

func shown(n) -> bool:
	return n != null and is_instance_valid(n) and (n as CanvasItem).is_visible_in_tree()

func goto(m: Node, page: String) -> void:
	await click(m.ui_page_btns[page])
	await idle(3)

func cards_up(m: Node) -> bool:
	var mc: ModelCards = m.model_cards
	return mc.open and shown(mc.root_box)

func fresh(m: Node) -> void:   # the cards were never answered: the next MODEL open is a first open
	var cf := ConfigFile.new()
	cf.load(m.settings)
	cf.set_value(ModelCards.SEC, "seen", false)
	cf.save(m.settings)

func leave_body(m: Node) -> void:
	if m.ksc != null and m.ksc.on:
		m.ksc.stop()
	await goto(m, "POSE")

func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.easy.set_on(false, false)
	await idle(2)
	var mc: ModelCards = m.model_cards

	# 4a a test launch: the cards never come by themselves
	ok(not mc.auto, "4a a test launch has auto off")
	await goto(m, "MODEL")
	ok(m.cur_page == "MODEL" and not cards_up(m), "4a MODEL on a test launch: no cards (page %s)" % m.cur_page)
	await leave_body(m)

	# 1 a real launch, first open
	mc.auto = true
	fresh(m)
	await goto(m, "MODEL")
	var all_up := cards_up(m)
	for id in ["shape", "part", "armour", "prop"]:
		all_up = all_up and shown(mc.cards[id]) and shown(mc.starts[id])
	ok(m.cur_page == "MODEL" and all_up and mc.cards.size() == 4, "1 first open: 4 cards with a Start each (page %s)" % m.cur_page)
	ok(shown(mc.show_all) and shown(mc._title), "1 the title and Show all the tools are on screen")
	var ribbon_ok: bool = m.ui_ribbon["MODEL"].is_visible_in_tree() and m.ui_ribbon["MODEL"].get_global_rect().end.y <= mc.root_box.get_global_rect().position.y + 1.0
	ok(ribbon_ok, "1 the ribbon stays above the cards")
	var texts := ""
	for c in mc.cards.values():
		for l in c.find_children("*", "Label", true, false):
			texts += " " + (l as Label).text
	for l in mc.root_box.find_children("*", "Label", true, false):
		texts += " " + (l as Label).text
	var rx := RegEx.new()
	rx.compile("(?i)ctrl|shift|\\balt\\b|\\bkey\\b|press |\\bF[0-9]\\b")
	ok(rx.search(texts) == null, "1 no key names in the cards' text")
	var hint_gone: bool = not shown(m.ui_mesh_hint_box)
	ok(hint_gone, "1 the 'Start with Test cube' hint steps aside")

	# 2a shape -> BODY
	await click(mc.starts["shape"])
	ok(m.cur_page == "BODY" and not cards_up(m), "2a Change his shape: page %s, cards closed" % m.cur_page)
	# 2b part -> the body mesh open
	fresh(m)
	await goto(m, "MODEL")
	ok(cards_up(m), "2b cards back on a first open")
	await click(mc.starts["part"])
	await idle(6)
	ok(m.cur_page == "MODEL" and BaseBody.is_open(m) and m.kmed.on and not cards_up(m), "2b Edit part: page %s, body mesh open %s, cards closed" % [m.cur_page, str(BaseBody.is_open(m))])
	await leave_body(m)
	# 2c armour -> the armour panel on the body
	fresh(m)
	await goto(m, "MODEL")
	await click(mc.starts["armour"])
	await idle(6)
	var au := ArmourUI.of(m)
	ok(m.cur_page == "MODEL" and BaseBody.is_open(m) and au.panel != null and au.panel.visible and not cards_up(m),
		"2c Add armour: body open %s, armour panel %s, cards closed" % [str(BaseBody.is_open(m)), str(au.panel != null and au.panel.visible)])
	await leave_body(m)
	# 2d prop -> BUILD on a clean scene
	fresh(m)
	await goto(m, "MODEL")
	var clean_before: bool = m._clean == m._doc_key()
	await click(mc.starts["prop"])
	await idle(6)
	if clean_before:
		ok(m.S.kind == "building" and m.cur_page == "BUILD" and not cards_up(m), "2d Make a prop (clean scene): kind %s, page %s" % [m.S.kind, m.cur_page])
	else:
		ok(m.kmed != null and m.kmed.on and m.cur_page == "MODEL" and m.S.kind != "building", "2d Make a prop (unsaved scene): the test cube opens, nothing replaced (kind %s)" % m.S.kind)
	print("     (scene clean before the prop Start: %s)" % str(clean_before))
	# 2e prop on a scene with unsaved work keeps it: the test cube
	m._new_scene()
	await idle(3)
	fresh(m)
	await goto(m, "MODEL")
	m._clean = "something else"   # the scene differs from its saved state
	await click(mc.starts["prop"])
	await idle(4)
	ok(m.S.kind != "building" and m.kmed != null and m.kmed.on, "2e Make a prop with unsaved work: the test cube opens, the scene is kept (kind %s)" % m.S.kind)
	m.kmed.stop()
	m._clean = m._doc_key()
	await idle(2)

	# 3 Show all the tools
	await leave_body(m)
	fresh(m)
	await goto(m, "MODEL")
	ok(cards_up(m), "3 cards up before the link")
	await click(mc.show_all)
	ok(not cards_up(m) and m.ui_ribbon["MODEL"].is_visible_in_tree() and mc.seen(), "3 Show all the tools: cards closed, ribbon still there, remembered")
	await leave_body(m)
	await goto(m, "MODEL")
	ok(m.cur_page == "MODEL" and not cards_up(m), "4b a seen Expert MODEL goes straight to the tools: no cards")

	# 5 the rule
	ok(ModelCards.wanted(true, false, true) and ModelCards.wanted(true, true, false), "5 Easy: cards always")
	ok(ModelCards.wanted(false, true, false) and not ModelCards.wanted(false, true, true) and not ModelCards.wanted(false, false, false), "5 Expert: first real open only")

	# 6 Done / back
	fresh(m)
	await leave_body(m)
	await goto(m, "MODEL")
	var up := cards_up(m)
	await goto(m, "POSE")
	ok(up and m.cur_page == "POSE" and not cards_up(m) and not shown(mc.root_box), "6 back to POSE from the cards: page %s, cards gone" % m.cur_page)
	await goto(m, "MODEL")
	ok(cards_up(m), "6 unanswered cards come back on the next MODEL open")
	await leave_body(m)

	# 7 layout at two window sizes
	var was_scale: Vector2i = root.content_scale_size
	var was_mode: int = root.content_scale_mode
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var was_size: Vector2i = root.size
	for sz in [Vector2i(1280, 720), Vector2i(1600, 900)]:
		root.size = sz
		root.content_scale_size = sz
		await idle(6)
		fresh(m)
		await goto(m, "MODEL")
		await idle(6)
		var vr := Rect2(Vector2.ZERO, Vector2(sz))
		var items := {}
		for id in mc.cards:
			items["card_" + id] = (mc.cards[id] as Control).get_global_rect()
		items["title"] = mc._title.get_global_rect()
		items["link"] = mc.show_all.get_global_rect()
		var inside := true
		var apart := true
		var keys := items.keys()
		for k in keys:
			var r: Rect2 = items[k]
			if not vr.grow(1.0).encloses(r):
				inside = false
				print("     off screen: %s %s" % [k, str(r)])
			for k2 in keys:
				if k < k2 and (items[k] as Rect2).grow(-1.0).intersects((items[k2] as Rect2).grow(-1.0)):
					apart = false
					print("     overlap: %s %s / %s %s" % [k, str(items[k]), k2, str(items[k2])])
		# the cards' text stays inside its card; the Start inside its card
		var texts_in := true
		for id in mc.cards:
			var cr: Rect2 = (mc.cards[id] as Control).get_global_rect()
			if not cr.grow(1.0).encloses((mc.starts[id] as Control).get_global_rect()):
				texts_in = false
			for l in (mc.cards[id] as Control).find_children("*", "Label", true, false):
				if not cr.grow(1.0).encloses((l as Control).get_global_rect()):
					texts_in = false
					print("     label out of its card: %s %s vs %s" % [(l as Label).text, str((l as Control).get_global_rect()), str(cr)])
		var rib: Rect2 = m.ui_top_bar.get_global_rect()
		var bar: Rect2 = m.ui_page_bar.get_global_rect()
		var rb: Rect2 = mc.root_box.get_global_rect()
		var clear_of_chrome: bool = not rb.grow(-1.0).intersects(rib) and not rb.grow(-1.0).intersects(bar)
		ok(inside and apart and texts_in and clear_of_chrome, "7 %dx%d: cards on screen %s, no overlap %s, text inside its card %s, clear of ribbon and page bar %s" % [sz.x, sz.y, str(inside), str(apart), str(texts_in), str(clear_of_chrome)])
		if sz == Vector2i(1280, 720):
			DirAccess.make_dir_recursive_absolute("C:/Temp/claude/modelcards")
			var img := root.get_texture().get_image()
			if img != null:
				img.save_png("C:/Temp/claude/modelcards/cards.png")
		await leave_body(m)
	root.size = was_size
	root.content_scale_size = was_scale
	root.content_scale_mode = was_mode

	print("MODEL CARDS ", "PASS" if fails == 0 else "FAIL %d" % fails)
	TestFiles.cleanup()
	quit(1 if fails else 0)
