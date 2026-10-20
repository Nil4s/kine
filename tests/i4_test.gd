## godot --path . -s tests/i4_test.gd     (ROADMAP I4: timing coach, scripts/timing_coach.gd + timing_coach_ui.gd; needs a window)
## Bars, written before measuring:
##  (1) combo3 with its CONTACT strike (card 3) slowed to 0.60 s: a STRIKE suggestion for card 3 whose move is shorter than 0.60
##      and inside the cited range [lo, hi] = hand travel d / (peak 11.95 .. 7.1 m/s / 1.875), checked here by hand from d
##  (2) that same clip with the move set to the suggested time (already inside the range): no STRIKE suggestion for card 3
##  (3) Preview plays to its end and the scene JSON is byte-identical before and after (and the body is back at the playhead)
##  (4) Accept (one line) changes exactly that card's move: every other field of every card identical; one undo step; Ctrl+Z exact
##  (5) Accept all: one undo step; Ctrl+Z exact
##  (6) compute on combo3 < 50 ms (database cached)
##  (7) the panel: shown inside the window, one line + Preview + Accept per suggestion, every line's text carries a source
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var B: Body = m.B
	var db := MotionMatch.build()
	print("     database: %d frames, %d clips" % [db["n"], (db["clips"] as Array).size()])
	m.tc_ui.db = db

	# (1)
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	var S: Scene = m.S
	S.cards[2]["move"] = 0.6
	var sg := TimingCoach.compute(S, B, db, "combo3")
	for s in sg:
		print("     ", s["reason"])
	var hit := sg.filter(func(x): return x["card"] == 2 and x["kind"] == "STRIKE")
	ok(hit.size() == 1, "(1) a STRIKE suggestion for card 3 (%d suggestions in all)" % sg.size())
	var to := 0.0
	if hit.size() == 1:
		var h: Dictionary = hit[0]
		to = float(h["to"])
		var ts := S.times()
		var tr: Array = TimingCoach._travel(S, B, float(ts[1][2]), float(ts[2][1]))
		var d: float = tr[0]
		var lo_hand := d / (11.95 / 1.875)
		var hi_hand := d / (7.1 / 1.875)
		print("     hand travel %.3f m: cited range %.3f - %.3f s (range used %.3f - %.3f); suggested %.3f s" % [d, lo_hand, hi_hand, h["range"][0], h["range"][1], to])
		ok(to < 0.6 and to >= lo_hand - 1e-3 and to <= hi_hand + 1e-3, "(1) %.3f s is shorter than 0.60 and inside the cited %.3f-%.3f s" % [to, lo_hand, hi_hand])
		ok(String(h["reason"]).contains("Stanley") and String(h["reason"]).contains("real clip") or String(h["reason"]).contains("no clip"), "(1) the reason names a real clip (or says none) and the source")
	S.cards[2]["move"] = to
	var sg2 := TimingCoach.compute(S, B, db, "combo3").filter(func(x): return x["card"] == 2 and x["kind"] == "STRIKE")
	ok(sg2.is_empty(), "(2) at %.3f s (inside the range) no STRIKE suggestion for card 3" % to)

	# back to the slow clip for the app tests
	S.cards[2]["move"] = 0.6
	m._rebuild_cards()
	m.tc_ui.show()
	await idle()
	var n_sug: int = m.tc_ui.sugs.size()
	var before := JSON.stringify(S.to_dict(B, false))
	var cards0 := JSON.stringify(S.cards)

	# (7) the panel
	var vp := m.get_viewport().get_visible_rect()
	var fr: Rect2 = m.ui_find.get_global_rect()
	ok(m.ui_find.visible and vp.encloses(fr), "(7) the panel is shown inside the window: %s in %s" % [fr, vp])
	var pbtn = m.ui_find_list.find_child("tc_preview_1", true, false)
	var abtn = m.ui_find_list.find_child("tc_accept_1", true, false)
	var line = m.ui_find_list.find_child("tc_line_1", true, false)
	ok(pbtn != null and abtn != null and line != null and n_sug >= 1, "(7) line, Preview and Accept for suggestion 1 (of %d)" % n_sug)
	var all_src := true
	for k in n_sug:
		var tx: String = (m.ui_find_list.find_child("tc_line_%d" % (k + 1), true, false) as Label).text
		all_src = all_src and (tx.contains("Thomas & Johnston") or tx.contains("Stanley"))
	ok(all_src, "(7) every line cites a source")
	var shot := root.get_texture().get_image()
	shot.save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/i4.png")

	# (3) preview
	m.tc_ui.preview(0)
	var ticks := 0
	while m.tc_ui.pv != null and ticks < 600:
		await process_frame
		ticks += 1
	ok(m.tc_ui.pv == null and ticks > 5, "(3) the preview played %d frames and ended" % ticks)
	ok(JSON.stringify(S.to_dict(B, false)) == before and JSON.stringify(S.cards) == cards0, "(3) the scene JSON is byte-identical after the preview")

	# (4) accept one
	var u0: int = m.undo.size()
	var first: Dictionary = m.tc_ui.sugs[0]
	m.tc_ui.accept(0)
	await idle()
	ok(m.undo.size() == u0 + 1, "(4) Accept is one undo step (%d -> %d)" % [u0, m.undo.size()])
	var c1: Array = JSON.parse_string(cards0)
	var c2: Array = JSON.parse_string(JSON.stringify(m.S.cards))
	var changed := []
	for i in c1.size():
		for key in c1[i].keys():
			if JSON.stringify(c1[i][key]) != JSON.stringify(c2[i][key]):
				changed.append("%d.%s" % [i, key])
	ok(changed == ["%d.move" % first["card"]] and absf(float(m.S.cards[first["card"]]["move"]) - float(first["to"])) < 1e-6, "(4) exactly one field changed: %s -> %.3f s" % [changed, float(first["to"])])
	m._undo()
	await idle()
	ok(JSON.stringify(m.S.cards) == cards0 and JSON.stringify(m.S.to_dict(m.B, false)) == before, "(4) Ctrl+Z: cards and scene JSON exact")

	# (5) accept all
	m.tc_ui.show()
	await idle()
	var u1: int = m.undo.size()
	var want: int = m.tc_ui.sugs.size()
	m.tc_ui.accept_all()
	await idle()
	ok(m.undo.size() == u1 + 1 and m.tc_ui.sugs.size() < want, "(5) Accept all: %d suggestions in one undo step, %d left" % [want, m.tc_ui.sugs.size()])
	m._undo()
	await idle()
	ok(JSON.stringify(m.S.cards) == cards0, "(5) Ctrl+Z: every card exact")

	# (6) speed on the untouched combo3
	m._load_scene("res://scenes/combo3.json")
	await idle()
	var best := 1e9
	var n_c3 := 0
	for r in 5:
		var t0 := Time.get_ticks_usec()
		n_c3 = TimingCoach.compute(m.S, B, db, "combo3").size()
		best = minf(best, float(Time.get_ticks_usec() - t0) / 1000.0)
	ok(best < 50.0, "(6) compute on combo3: %.1f ms (best of 5; %d suggestions) < 50 ms" % [best, n_c3])
	var t1 := Time.get_ticks_usec()
	TimingCoach.compute(m.S, B, db, "")
	print("     with combo3 itself in the database: %.1f ms" % (float(Time.get_ticks_usec() - t1) / 1000.0))

	print("I4 TIMING COACH %s" % ("FAIL" if fails > 0 else "PASS") + (" (%d failed)" % fails if fails > 0 else ""))
	quit(1 if fails > 0 else 0)
