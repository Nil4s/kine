## godot --path . -s tests/pagetour_test.gd     (docs/ROADMAP_400.md P01; needs a window)
## PAGE TOUR (scripts/page_tour.gd): BODY / MODEL / SCULPT / SURFACE each get a 5-step tour the first time they open.
## BARS, written before measuring:
##  1 STEPS: each of the 4 pages has exactly 5 steps, every step a title and a sentence; a greyed page's "why" step says
##    its real controls (the ribbon tools; the expert pages are live now, not greyed)
##  2 PLACEMENT, every step of every page, at UI size 100 (1600 x 900) and 150 (1920 x 1080): the target is a visible
##    control, at least 8 x 8 px, inside the window; the callout is inside the window and clear of the target; the
##    arrow's tip is within 6 px of the target
##  3 FIRST OPEN: with auto on, opening BODY starts its tour (step 1 of 5); Next walks it to the end and it closes; the
##    seen flag is in the settings FILE (a fresh ConfigFile reads pagetour/BODY = true); BODY opened again shows nothing.
##    The greyed MODEL button starts MODEL's tour once; SCULPT / SURFACE stay unseen until opened
##  4 REPLAY: the search row "Page tour" plays this page's tour although seen; from POSE it plays BODY's (and opens BODY);
##    Skip closes it. No undo step is added by any of it
## Screenshot: BODY step 4 (the quick bodies) to $PAGETOUR_PNG or user://pagetour.png
extends SceneTree

var m: Node
var pt: PageTour
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func file_seen(p: String) -> bool:
	var cf := ConfigFile.new()
	cf.load(m.settings)
	return PageTour.seen(cf, p)


func placed(label: String) -> bool:
	await idle(5)
	var win := Rect2(Vector2.ZERO, Vector2(m.get_viewport().get_visible_rect().size))
	var t := pt.target_rect()
	var c := Rect2(pt.card.global_position, pt.card.size)
	var cs: Array = pt._controls(String(PageTour.steps_of(pt.page)[pt.step][2]))
	var vis := not cs.is_empty() and cs.all(func(x): return (x as Control).is_visible_in_tree())
	var tipd := t.grow(6.0).has_point(pt.arrow_tip())
	var good := vis and t.size.x >= 8.0 and t.size.y >= 8.0 and win.encloses(t) and win.encloses(c) and not c.intersects(t) and pt.card.visible and tipd
	if not good:
		print("    %s: vis=%s target %s callout %s window %s tip %s" % [label, vis, t, c, win.size, pt.arrow_tip()])
	return good


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.easy.on:
		m.easy.set_on(false, false)
	pt = m.page_tour
	ok(pt != null and pt.page == "" and not pt.auto, "a test starts with no page tour and auto off")
	var und: int = (m.undo as Array).size() if m.get("undo") != null else -1

	# 1. five steps each
	var all5 := true
	for p in PageTour.TOURED:
		var st := PageTour.steps_of(p)
		all5 = all5 and st.size() == 5
		pt.page = p
		for k in st.size():
			all5 = all5 and String(st[k][0]) != "" and pt.step_text(p, k).length() > 20
	pt.page = ""
	ok(all5, "(1) BODY / MODEL / SCULPT / SURFACE: 5 steps each, each with a title and a sentence")
	var why := pt.step_text("SCULPT", 1)
	ok(why.contains("brush"), "(1) SCULPT's brushes step names the brushes: %s" % why)
	print("  MODEL works-now: ", pt.step_text("MODEL", 2))

	# 2. placement at two sizes
	for sz in [[Vector2i(1600, 900), 100], [Vector2i(1920, 1080), 150]]:
		m.get_window().size = sz[0]
		await idle(4)
		m._set_scale(sz[1])
		await idle(4)
		var bad := []
		var n := 0
		for p in PageTour.TOURED:
			pt.begin_page(p)
			for k in 5:
				pt._go(k)
				if not await placed("%s %d @%d" % [p, k + 1, sz[1]]):
					bad.append("%s %d" % [p, k + 1])
				n += 1
			pt.finish(false, false)
		ok(bad.is_empty() and n == 20, "(2) @%d %s: 20 / 20 steps on screen, inside, clear of the callout; bad: %s" % [sz[1], sz[0], bad])
	m._set_scale(100)
	m.get_window().size = Vector2i(1600, 900)
	await idle(4)

	# 3. first open (the placement run above marked them seen: start from a clean file)
	var cf := ConfigFile.new()
	cf.load(m.settings)
	if cf.has_section(PageTour.SEC):
		cf.erase_section(PageTour.SEC)
	cf.save(m.settings)
	ok(not file_seen("BODY") and not file_seen("MODEL"), "(3) a clean file: nothing seen")
	pt.auto = true
	m._page_set("POSE", false)
	await idle(3)
	ok(pt.page == "", "(3) POSE has no tour")
	m._page_set("BODY", false)
	await idle(4)
	ok(pt.page == "BODY" and pt.step == 0 and pt.card.visible and String(pt._title.text).contains("1 of 5"), "(3) BODY opened the first time: its tour, %s" % pt._title.text)
	ok(file_seen("BODY"), "(3) the seen flag is in the settings file")
	pt._go(3)
	await idle(6)
	var img: Image = root.get_viewport().get_texture().get_image()
	var out := OS.get_environment("PAGETOUR_PNG") if OS.get_environment("PAGETOUR_PNG") != "" else "user://pagetour.png"
	img.save_png(ProjectSettings.globalize_path(out))
	pt._go(0)
	var nx: Button = pt.card.find_child("pagetour_next", true, false)
	for i in 5:
		nx.pressed.emit()
		await idle(1)
	ok(pt.page == "" and not pt.card.visible, "(3) Next x5 walks it to the end and it closes")
	m._page_set("POSE", false)
	await idle(2)
	m._page_set("BODY", false)
	await idle(4)
	ok(pt.page == "", "(3) BODY again: no tour (seen)")
	m._page_set("POSE", false)
	await idle(2)
	var mb: Button = m.find_child("tab_model", true, false)
	mb.pressed.emit()
	await idle(3)
	ok(pt.page == "MODEL" and pt.step == 0, "(3) the greyed MODEL button: its tour starts")
	nx.pressed.emit()
	await idle(2)
	ok(pt.page == "MODEL" and pt.step == 1, "(3) MODEL: the next step moves on (step 2 of 3): %s" % pt.step_text("MODEL", 1).left(80))
	pt.finish(true)
	mb.pressed.emit()
	await idle(3)
	ok(pt.page == "", "(3) MODEL again: no tour")
	ok(file_seen("MODEL") and not file_seen("SCULPT") and not file_seen("SURFACE"), "(3) MODEL seen; SCULPT, SURFACE not yet")

	# 4. replay from the search box
	var row := {}
	for c in m._commands():
		if c["name"] == "Page tour":
			row = c
	ok(not row.is_empty(), "(4) the search has a \"Page tour\" row")
	m._page_set("BODY", false)
	await idle(3)
	(row["run"] as Callable).call()
	await idle(3)
	ok(pt.page == "BODY" and pt.step == 0 and pt.card.visible, "(4) Page tour on BODY plays BODY's tour (seen or not)")
	var sk: Button = pt.card.find_child("pagetour_skip", true, false)
	sk.pressed.emit()
	await idle(2)
	ok(pt.page == "" and not pt.card.visible, "(4) Skip closes it")
	m._page_set("POSE", false)
	await idle(3)
	(row["run"] as Callable).call()
	await idle(4)
	ok(pt.page == "BODY" and m.cur_page == "BODY" and await placed("replay from POSE"), "(4) Page tour on POSE: opens BODY and plays its tour, placed")
	pt.finish(true, false)
	ok(und < 0 or (m.undo as Array).size() == und, "(4) no undo step added (%d)" % und)
	print("PAGE TOUR ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails else 0)
