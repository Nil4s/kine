## godot --path . -s tests/timeline_marks_test.gd     (GATES DD3, UPGRADES #30; a real window, real clicks)
## FINDINGS ON THE TIMELINE: a scene with findings, Check run. Every finding is in exactly one mark, each mark at its
## findings' time (within MARK_PX), marks closer than MARK_PX merged (none left closer); a mark's colour is red when any
## of its findings is a FAIL, amber otherwise (read from the drawn pixels); its tooltip names its rules. A REAL click
## on each of 3 marks: the playhead at that finding's time, its card picked, the Check list open with that finding's
## row in sight. A card retimed (a real undo step): no marks; Check again: back. Before any Check: no marks.
extends SceneTree

var fails := 0
var m: Node
var tl: Timeline


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func click(p: Vector2) -> void:
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


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	tl = m.ui_timeline
	# the scene with the most findings
	var best := ""
	var most := -1
	for f in DirAccess.get_files_at("res://scenes/"):
		if not f.ends_with(".json"):
			continue
		m._load_scene("res://scenes/" + f)
		m._rebuild_cards()
		if m.S.cards.size() < 2:
			continue
		m._check()
		if m.findings.size() > most:
			most = m.findings.size()
			best = f
	m._load_scene("res://scenes/" + best)
	m._rebuild_cards()
	m._refresh()
	await idle(3)
	ok(tl.marks().is_empty(), "1 %s opened, Check not run: no marks" % best)
	m._check()
	m._refresh()
	await idle(4)
	var mk: Array = tl.marks()
	var all := []
	var place_bad := []
	for k in mk.size():
		all.append_array(mk[k][1])
		for i in mk[k][1]:
			if absf(tl.x_of(float(m.findings[i]["t"])) - float(mk[k][0])) > Timeline.MARK_PX:
				place_bad.append(i)
		if k > 0 and float(mk[k][0]) - float(mk[k - 1][0]) < Timeline.MARK_PX:
			place_bad.append("marks %d and %d too close" % [k - 1, k])
	all.sort()
	ok(all == range(m.findings.size()) and place_bad.is_empty() and mk.size() >= 2,
		"2 Check run on %s: %d findings in %d marks, each in exactly one, each at its time, none closer than %.0f px (bad: %s)" % [best, m.findings.size(), mk.size(), Timeline.MARK_PX, place_bad])
	# merging: a second finding 2 ms after the first (the scene has none that close) joins its mark with a count
	var twin: Dictionary = (m.findings[mk[0][1][0]] as Dictionary).duplicate()
	twin["t"] = float(twin["t"]) + 0.002
	m.findings.append(twin)
	var mk2: Array = tl.marks()
	var joined: Array = mk2.filter(func(k): return (m.findings.size() - 1) in k[1])
	ok(mk2.size() == mk.size() and joined.size() == 1 and joined[0][1].size() == 2,
		"2b a finding 2 ms from another: no new mark (%d marks), it joins that mark (2 in it, the count drawn beside it)" % mk2.size())
	m.findings.pop_back()
	# colour, read from what is on screen
	var img := root.get_texture().get_image()
	var col_bad := []
	for k in mk:
		var fail: bool = k[1].any(func(i): return m.findings[i]["sev"] == "FAIL")
		var g: Vector2 = tl.get_global_transform() * Vector2(float(k[0]), 7.0)
		var px := img.get_pixelv(Vector2i(g))
		var want: Color = Tok.c("fail") if fail else Tok.c("warn")
		if absf(px.r - want.r) + absf(px.g - want.g) + absf(px.b - want.b) > 0.12:
			col_bad.append([k[1], px, want])
	ok(col_bad.is_empty(), "3 each mark drawn red when it holds a FAIL, amber otherwise (read from the screen; bad: %s)" % [col_bad.slice(0, 2)])
	var tip := tl._get_tooltip(Vector2(float(mk[0][0]), 7.0))
	ok(String(m.findings[mk[0][1][0]]["rule"]) in tip and "click" in tip, "4 a mark's tooltip names its rule: '%s'" % tip.get_slice("\n", 0).left(70))
	m._close_findings()
	var picks := [0, mk.size() / 2, mk.size() - 1]
	var go_bad := []
	for k in picks:
		var i: int = mk[k][1][0]
		var f: Dictionary = m.findings[i]
		m.playhead = 0.0 if float(f["t"]) > 0.5 else m.S.length()
		await click(tl.get_global_transform() * Vector2(float(mk[k][0]), 7.0))
		await idle(2)
		var row: Control = m.ui_find_list.get_node_or_null("finding_%d" % (i + 1))
		var sc: ScrollContainer = m.ui_find_list.get_parent()
		var in_sight := row != null and sc.get_global_rect().grow(1).encloses(row.get_global_rect())
		if absf(m.playhead - float(f["t"])) > 1e-4 or m.sel_card != mini(int(f["card"]), m.S.cards.size() - 1) or not m.ui_find.visible or not in_sight:
			go_bad.append([k, m.playhead, f["t"], m.sel_card, f["card"], m.ui_find.visible, in_sight])
	ok(go_bad.is_empty(), "5 real clicks on marks %s: the playhead at the finding, its card picked, the Check list open with its row in sight (bad: %s)" % [picks, go_bad])
	# a real retime (one undo step), then Check again
	m.ui_timeline.retime_started.emit()
	m.S.cards[1]["hold"] = float(m.S.cards[1]["hold"]) + 0.1
	m.ui_timeline.retimed.emit(true)
	await idle(3)
	var gone := tl.marks().is_empty()
	m._check()
	await idle(3)
	ok(gone and not tl.marks().is_empty(), "6 a card retimed (an undo step): the marks gone (%s); Check again: %d back" % [gone, tl.marks().size()])
	print("TIMELINE MARKS: %d failed" % fails)
	quit(1 if fails > 0 else 0)
