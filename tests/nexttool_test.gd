## godot --path . -s tests/nexttool_test.gd     (ROADMAP P17: next suggested tool, scripts/next_tool.gd; needs a window)
## The page bar learns which command you run after which and offers the top 3 as chips after the "Next:" line.
## Bars, written before measuring:
##  (1) after 20 runs of A->B and 5 of A->C, after A the first suggestion is B and the second C
##  (2) decay (half-life 200 commands): after 300 newer A->C runs, C is first (B's 20 have faded to a fraction)
##  (3) the counts reload from the file in a fresh instance and give the same suggestions (the test's own user:// file)
##  (4) a real click on a chip runs the command: ONE dispatch (the counter moves by 1), one undo step; a command that cannot run now
##      (Check with no cards) is never offered; Help: forget my command habits empties the table
##  (5) PLACEMENT (C:/Users/Nick/.claude/jobs/9afc22db/tmp/nexttool.png): the chips are visible on the page bar, right of the "Next:" line,
##      inside the window, and no chip rect intersects a page button rect
extends SceneTree

var fails := 0
var m: Node
const FILE := "user://nexttool_test.json"
const OUT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/nexttool.png"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func click(c: Control) -> void:
	var p := c.get_global_rect().get_center()
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
	await idle()


func chips() -> Array:
	var out := []
	for b in m.ui_nt_box.get_children():
		if b.visible:
			out.append(b.text)
	return out


func _init() -> void:
	var yes := func(_n): return true
	var t := NextTool.new()
	t.path = FILE
	t.forget()
	for i in 20:
		t.record("A", "POSE")
		t.record("B", "POSE")
	for i in 5:
		t.record("A", "POSE")
		t.record("C", "POSE")
	t.record("A", "POSE")
	var s1: Array = t.suggest("POSE", yes, 3)
	print("  after 20 A>B and 5 A>C: ", s1)
	ok(s1.size() >= 2 and s1[0] == "B" and s1[1] == "C", "(1) after A the chips lead with B then C")
	for i in 300:
		t.record("C", "POSE")
		t.record("A", "POSE")
	var s2: Array = t.suggest("POSE", yes, 3)
	print("  after 300 newer A>C: ", s2)
	ok(s2[0] == "C", "(2) decay: C leads after 300 newer A>C runs")
	var u := NextTool.new()
	u.path = FILE
	u.load_file()
	var s3: Array = u.suggest("POSE", yes, 3)
	ok(s3 == s2 and u.tick == t.tick and u.last == "A", "(3) a fresh instance reloads the same table (tick %d) and gives %s" % [u.tick, str(s3)])
	ok(NextTool.skipped("Undo") and NextTool.skipped("Front view") and NextTool.skipped("Page: POSE") and not NextTool.skipped("Mirror the whole pose"),
		"views, undo and page switches are never counted")
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle()
	m.nt.path = FILE   # first: the real user file is never written
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.check_ran = false
	m.findings = []
	m.nt.forget()
	var CL := "CLIP this pose (add a card)"
	var MI := "Mirror the whole pose"
	for i in 6:
		m.nt.record(CL, m.cur_page)
		m.nt.record(MI, m.cur_page)
		m.nt.record(CL, m.cur_page)
		m.nt.record("Check the motion", m.cur_page)
	m.nt.record(CL, m.cur_page)
	m._nt_sync()
	await idle()
	print("  chips: ", chips(), "  next: ", m.ui_next.text)
	ok(chips().size() >= 2 and chips().has(MI), "(4) the chips offer the habit '%s'" % MI)
	var hint: String = m.next_step()["cmd"]
	ok(not chips().has(hint), "(4) the rule-based hint ('%s') is not repeated as a chip" % hint)
	var chip: Button = m.ui_nt_box.get_child(chips().find(MI))
	var t0: int = m.nt.tick
	var u0: int = m.undo.size()
	await click(chip)
	ok(m.nt.tick == t0 + 1 and m.nt.last == MI, "(4) a chip click is one dispatch (counter %d -> %d)" % [t0, m.nt.tick])
	ok(m.undo.size() == u0 + 1, "(4) and one undo step (%d -> %d)" % [u0, m.undo.size()])
	# a command that cannot run now is not offered: no cards, so no Check
	m.nt.record(CL, m.cur_page)
	m.S.cards.clear()
	m._rebuild_cards()
	m._nt_sync()
	await idle()
	ok(not chips().has("Check the motion"), "(4) with no cards 'Check the motion' is not offered (chips %s)" % str(chips()))
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.check_ran = false
	m.findings = []
	m.nt.record(CL, m.cur_page)
	m._nt_sync()
	await idle()
	# placement
	var win: Rect2 = m.get_viewport().get_visible_rect()
	var nxt: Rect2 = m.ui_next.get_global_rect()
	var vis := chips()
	var inside := vis.size() > 0
	var clear := true
	var right := true
	for b in m.ui_nt_box.get_children():
		if not b.visible:
			continue
		var r: Rect2 = b.get_global_rect()
		inside = inside and win.encloses(r)
		right = right and r.position.x >= nxt.position.x + nxt.size.x - 1.0
		for p in m.ui_page_btns:
			if r.intersects(m.ui_page_btns[p].get_global_rect()):
				clear = false
	print("  window ", win, " next ", nxt, " chips ", vis)
	ok(vis.size() >= 1 and inside, "(5) %d chips visible, inside the window" % vis.size())
	ok(right and nxt.size.x > 100.0, "(5) chips sit right of the Next: line (it is %.0f px wide)" % nxt.size.x)
	ok(clear, "(5) no chip rect intersects a page button")
	root.get_texture().get_image().save_png(OUT)
	# forget
	for c in m.ui_cmd.commands:
		if c["name"] == "Help: forget my command habits":
			c["run"].call()
	ok(m.nt.counts.is_empty() and m.nt.tick == 0, "Help: forget my command habits empties the table")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
	print("nexttool_test: ", "PASS" if fails == 0 else "FAIL (%d)" % fails)
	TestFiles.cleanup()
	quit(fails)
