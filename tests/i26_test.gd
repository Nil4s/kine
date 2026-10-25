## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/i26_test.gd     (ROADMAP I26: learn from my edits, scripts/suggestion_journal.gd + _ui.gd; needs a window)
## Bars, written before measuring:
##  (1) 5 accepts of the timing coach's 'less time' offer on combo3 card 3, each ending 0.05 s under the suggestion: the first 3 are 'edited' (the later 2 are
##      offered pre-applied at that value, so they are not edits), mean delta -0.05 s (+-0.001); learned() returns it, and not before the 3rd edit (NAN after 2)
##  (2) the 6th offer carries the learned delta: its move is the first offer's move - 0.05 (+-0.002), its Accept button reads 'shorten ... 0.05 s' and 'applied',
##      and accepting writes that value to the card
##  (3) 3 accepted counter 'parry' offers each undone within 30 s are 3 rejected; rate = (0+1)/(3+2) = 0.2 and a kind never seen is 0.5, so sort_offers puts parry last
##      of [parry, block, slip]; an undo at 31 s (fake clock) is NOT a rejection and the card is KEPT after 2 minutes
##  (4) the real user://suggestion_journal.json is byte-for-byte what it was before (or still absent); the test's own file has the PID in its name
##  (5) 'What I learned from you' lists >= 2 lessons inside the window; Reset empties stats, lessons and the file
##  (6) placement: the timing panel with the learned button and the lessons panel are both inside the window; the picture is saved
extends SceneTree

const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/i26.png"
var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func offer(db: Dictionary) -> Dictionary:
	m.sj.pending = []   # (the test's own reset of the card below is not the user's edit)
	m.S.cards[2]["move"] = 0.6
	m._rebuild_cards()
	m.tc_ui.show()
	await idle(2)
	for k in m.tc_ui.sugs.size():
		var s: Dictionary = m.tc_ui.sugs[k]
		if int(s["card"]) == 2 and s["kind"] == "STRIKE":
			return {"k": k, "s": s}
	return {}


func _init() -> void:
	var real := "user://suggestion_journal.json"
	var real0 := FileAccess.get_file_as_string(real) if FileAccess.file_exists(real) else "<absent>"
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	ok(m.sj.path.contains(str(OS.get_process_id())) and m.sj.path != real, "(4) the app's journal in this test is %s" % m.sj.path)
	var db := MotionMatch.build()
	m.tc_ui.db = db
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()

	# (1) five accepts, each edited by -0.05 s
	var first_to := NAN
	var learned_after := []
	for r in 5:
		var o: Dictionary = await offer(db)
		if o.is_empty():
			ok(false, "(1) round %d: no STRIKE offer on card 3" % (r + 1))
			break
		if r == 0:
			first_to = float(o["s"]["to"])
		m.tc_ui.accept(int(o["k"]))
		var base := float(o["s"].get("base", o["s"]["to"]))
		m.S.cards[2]["move"] = base - 0.05   # the user's own edit: always 0.05 s under the suggestion (rounds 4-5 come pre-applied at exactly that: no further edit)
		await idle(2)   # (main's tick sees it)
		learned_after.append(m.sj.learned("timing coach", "less time"))
	var row: Dictionary = m.sj._row("timing coach", "less time")
	print("     row: ", row, "  learned after each round: ", learned_after)
	ok(int(row["edited"]) == 3 and int(row["n_neg"]) == 3 and absf(float(row["sum_neg"]) / 3.0 + 0.05) <= 0.001, "(1) 3 edited (rounds 4-5 came pre-applied at the same value), mean delta %.4f s (bar -0.05 +-0.001)" % (float(row["sum_neg"]) / maxf(1.0, float(row["n_neg"]))))
	ok(is_nan(learned_after[0]) and is_nan(learned_after[1]) and not is_nan(learned_after[2]) and absf(learned_after[4] + 0.05) <= 0.001, "(1) learned() is NAN after 2 edits, -0.05 from the 3rd on")

	# (2) the 6th offer
	var o6: Dictionary = await offer(db)
	var btn: Button = m.ui_find_list.find_child("tc_accept_%d" % (int(o6["k"]) + 1), true, false)
	print("     6th button: ", btn.text if btn != null else "<none>", "   move ", o6["s"]["to"], " (first offer ", first_to, ")")
	ok(absf(float(o6["s"]["to"]) - (first_to - 0.05)) <= 0.002, "(2) the 6th offer's move %.3f = first %.3f - 0.05" % [float(o6["s"]["to"]), first_to])
	ok(btn != null and btn.text.contains("shorten") and btn.text.contains("0.05 s") and btn.text.contains("applied"), "(2) the button says so: '%s'" % (btn.text if btn != null else ""))
	var vp := m.get_viewport().get_visible_rect()
	ok(vp.encloses(m.ui_find.get_global_rect()) and m.ui_find.visible, "(6) the timing panel is inside the window: %s" % m.ui_find.get_global_rect())
	var shot_a: Image = m.get_viewport().get_texture().get_image()
	m.tc_ui.accept(int(o6["k"]))
	ok(absf(float(m.S.cards[2]["move"]) - (first_to - 0.05)) <= 0.002, "(2) accepting writes %.3f s to the card" % float(m.S.cards[2]["move"]))

	# (3) rejects, a late undo, and a kept card, on a journal with a fake clock
	var tmp := "user://zz_i26_journal_%d.json" % OS.get_process_id()
	var sj := SuggestionJournal.new(tmp)
	var clk := [0.0]
	sj.now = func(): return clk[0]
	var un := 10
	for i in 3:
		sj.log("counter", "parry", -1, {}, un)
		clk[0] += 5.0
		sj.observe(un - 1)
		clk[0] += 1.0
	ok(int(sj._row("counter", "parry")["rejected"]) == 3 and sj.pending.is_empty(), "(3) 3 undone parries are 3 rejected")
	sj.log("counter", "block", -1, {}, un)
	clk[0] += 31.0
	sj.observe(un - 1)
	ok(int(sj._row("counter", "block")["rejected"]) == 0 and sj.pending.size() == 1, "(3) an undo at 31 s is not a rejection")
	clk[0] += 100.0
	sj.observe(un)
	ok(int(sj._row("counter", "block")["kept"]) == 1, "(3) the block is KEPT after 2 minutes")
	var rp := sj.rate("counter", "parry")
	var sorted := sj.sort_offers("counter", [{"kind": "parry"}, {"kind": "block"}, {"kind": "slip"}], func(x): return x["kind"])
	print("     rates: parry %.3f block %.3f slip %.3f -> order %s" % [rp, sj.rate("counter", "block"), sj.rate("counter", "slip"), sorted.map(func(x): return x["kind"])])
	ok(absf(rp - 0.2) <= 1e-9 and absf(sj.rate("counter", "slip") - 0.5) <= 1e-9 and sorted[2]["kind"] == "parry" and sorted[0]["kind"] == "block", "(3) parry rate 0.2 sorts last, block (kept) first")
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(tmp))
	ok(disk is Dictionary and (disk["stats"] as Dictionary).has("counter|parry"), "(3) the journal file holds the counts")
	DirAccess.remove_absolute(tmp)

	# (5) the lessons panel (the app's journal also gets three undone parries, so there are two lessons)
	for i in 3:
		m.sj.log("counter", "parry", -1, {}, 50)
		m.sj.observe(49)
	m.sj_ui.show()
	await idle(2)
	var n_les: int = m.sj.lessons().size()
	var l1 = m.ui_find_list.find_child("sj_lesson_1", true, false)
	var l2 = m.ui_find_list.find_child("sj_lesson_2", true, false)
	for ls in m.sj.lessons():
		print("     lesson: ", ls["text"])
	ok(n_les >= 2 and l1 != null and l2 != null, "(5) the panel lists %d lessons" % n_les)
	ok(vp.encloses(m.ui_find.get_global_rect()), "(6) the lessons panel is inside the window: %s" % m.ui_find.get_global_rect())
	var shot_b: Image = m.get_viewport().get_texture().get_image()
	var both := Image.create(shot_a.get_width() * 2, shot_a.get_height(), false, shot_a.get_format())
	both.blit_rect(shot_a, Rect2i(Vector2i.ZERO, shot_a.get_size()), Vector2i.ZERO)
	both.blit_rect(shot_b, Rect2i(Vector2i.ZERO, shot_b.get_size()), Vector2i(shot_a.get_width(), 0))
	ok(both.save_png(SHOT) == OK, "(6) picture saved: " + SHOT)
	m.sj_ui.reset()
	await idle()
	var disk2: Variant = JSON.parse_string(FileAccess.get_file_as_string(m.sj.path))
	ok(m.sj.stats.is_empty() and m.sj.lessons().is_empty() and disk2 is Dictionary and (disk2["stats"] as Dictionary).is_empty(), "(5) Reset empties the stats, the lessons and the file")

	# (4)
	var real1 := FileAccess.get_file_as_string(real) if FileAccess.file_exists(real) else "<absent>"
	ok(real1 == real0, "(4) the real user://suggestion_journal.json is untouched (%s)" % ("absent" if real0 == "<absent>" else "%d bytes" % real0.length()))
	DirAccess.remove_absolute(m.sj.path)
	print("RESULT: ", "ALL OK" if fails == 0 else "%d FAILED" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
