## godot --path . -s tests/i45_test.gd     (ROADMAP I45: the newer physics judges in the realism score; scripts/judge_suite.gd + realism_score.gd + realism_ui.gd; needs a window)
## DEAD STOP: the synthetic lunge of i36 (stand -> lunge 0.8 m in 0.9 s -> back), the move into the lunge LINEAR (arrives at full speed) vs the default smooth ease.
## Bars, written before measuring:
##  (1) the dead-stop clip's MOMENTUM penalty is exactly W_MOMENTUM x (1 transition of 2) = 20.0 points, the eased clip's is 0, and the dead-stop clip scores lower
##  (2) a clip with no weapon: the WEAPON judge abstains (penalty 0, share 0, listed in res.abstain); forcing an abstaining judge's sub-score to 0 does not move the score
##  (3) all 8 newer judges are listed in the panel's judge rows (as a weighted row or as 'abstains'), with their weights
##  (4) the biggest gain on the dead-stop clip is the MOMENTUM fix (judge name), its predicted gain > 0, applying it through the panel raises the score by the prediction +-1.0,
##      the stop is no longer flagged, and it is ONE undo step; Ctrl+Z restores the cards JSON byte for byte
##  (5) the unchanged-scene re-score on combo3 takes < 200 ms (the judges come from the cache); a cold full score on combo3 takes < 2x the old cold time
##      (old = this run minus the newer judges' own time; reported honestly either way)
##  (6) a fix of the newer judges is predicted on a copy: the scene's cards are byte-identical after gain_of
##  (7) PLACEMENT: the panel is inside the window and shows the biggest-gain line, the judge rows and a fix button; the screenshot is taken on it
extends SceneTree

const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/i45.png"
var fails := 0
var m: Node
var stand: Dictionary
var lunge: Dictionary


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func make_poses() -> void:
	var b := DistanceKeeper.new_body()
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	b.fk()
	stand = b.to_dict()
	b.offset += Vector3(0.0, 0.0, -0.8)
	b.fk()
	lunge = b.to_dict()


func cards_for(ease: String) -> Array:
	var c1 := {"name": "go", "pose": lunge, "move": 0.9, "hold": 0.6}
	if ease != "":
		c1["ease"] = ease
	return [{"name": "stand", "pose": stand, "move": -1.0, "hold": 0.4}, c1, {"name": "back", "pose": stand, "move": 1.2, "hold": 0.2}]


func load_cards(cs: Array) -> void:
	m.S.markers = []
	m.S.cards = cs
	m._rebuild_cards()
	m._refresh()


func cold() -> void:
	var rs: RealismUI = m.rs_ui
	rs._memo = {}
	rs.jcache = {}
	rs.gains = {}
	m.force_cache = {}
	FrameMemo.reset()


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	print("     building db"); m.tc_ui.db = MotionMatch.build()
	var rs: RealismUI = m.rs_ui
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m._refresh()
	await idle()
	make_poses()

	# (5) combo3 timing, first (the scene as shipped)
	cold()
	var t0 := Time.get_ticks_usec()
	rs.refresh()
	var cold_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	var judges_ms := float(rs.lap.get("judges", 0.0))
	var old_ms := cold_ms - judges_ms
	print("     combo3 cold score %.0f ms = old judges %.0f + newer judges %.0f; score %.1f" % [cold_ms, old_ms, judges_ms, float(rs.res["score"])])
	print("     per newer judge (ms): ", rs.jlap)
	print("     combo3 pen: ", rs.res["pen"], " abstain: ", rs.res["abstain"])
	t0 = Time.get_ticks_usec()
	rs.refresh()
	var warm_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	ok(warm_ms < 200.0, "(5) unchanged-scene re-score %.0f ms < 200 ms" % warm_ms)
	ok(cold_ms < 2.0 * old_ms, "(5) cold full score %.0f ms vs old %.0f ms: x%.2f (bar < x2)" % [cold_ms, old_ms, cold_ms / maxf(old_ms, 1.0)])

	# (1) dead stop vs eased
	load_cards(cards_for("linear"))
	await idle()
	rs.refresh()
	var dead_score := float(rs.res["score"])
	var dead_pen := float(rs.res["pen"]["MOMENTUM"])
	print("     dead stop: score %.2f pen %s" % [dead_score, rs.res["pen"]])
	load_cards(cards_for(""))
	await idle()
	rs.refresh()
	var eased_score := float(rs.res["score"])
	var eased_pen := float(rs.res["pen"]["MOMENTUM"])
	print("     eased: score %.2f MOMENTUM pen %.2f" % [eased_score, eased_pen])
	ok(absf(dead_pen - RealismScore.W_MOMENTUM * 0.5) < 1e-6 and eased_pen == 0.0, "(1) MOMENTUM penalty dead stop %.2f (= %.0f x 1/2), eased %.2f" % [dead_pen, RealismScore.W_MOMENTUM, eased_pen])
	ok(dead_score < eased_score, "(1) dead stop %.2f < eased %.2f" % [dead_score, eased_score])

	# (2) abstain
	ok(rs.res["abstain"].has("WEAPON") and float(rs.res["pen"]["WEAPON"]) == 0.0 and float(rs.res["share"]["WEAPON"]) == 0.0, "(2) WEAPON abstains on a clip with no weapon: %s" % str(rs.res["abstain"].get("WEAPON")))
	var inp2: Dictionary = rs.inp.duplicate(true)
	inp2["judges"]["WEAPON"] = {"abstain": true, "why": "x", "sub": 0.0, "n": 0, "bad": 0, "items": []}
	ok(is_equal_approx(float(RealismScore.compute(m.S, inp2)["score"]), eased_score), "(2) an abstaining judge with sub-score 0 does not move the score")

	# dead stop again for the panel
	load_cards(cards_for("linear"))
	await idle()
	rs.refresh()
	var before := JSON.stringify(m.S.cards)
	var u0: int = m.undo.size()
	var score0 := float(rs.res["score"])
	rs.show()
	await idle(4)
	var tb := Time.get_ticks_usec()
	m.ui_find_list.find_child("rs_find", true, false).pressed.emit()   # the panel predicts no gain until "Find the biggest gain" is pressed
	var tw := Time.get_ticks_usec()
	while m.ui_find_list.find_child("rs_best", true, false) == null and Time.get_ticks_usec() - tw < 300000000:
		await process_frame
	var bg: Dictionary = rs.best
	ok(JSON.stringify(m.S.cards) == before, "(6) cards byte-identical after the predictions")
	print("     biggest gain: ", "none" if bg.is_empty() else "%s +%.2f  %s" % [bg["item"]["judge"], bg["gain"], String(bg["item"]["text"]).left(100)])
	ok(not bg.is_empty() and String(bg["item"]["judge"]) == "MOMENTUM" and float(bg["gain"]) > 0.0, "(4) the biggest gain is the MOMENTUM fix")

	# (3) + (7) panel
	var jl: Label = m.ui_find_list.find_child("rs_judges", true, false)
	var txt := jl.text if jl != null else ""
	var all8 := true
	for jd in RealismScore.NEW:
		all8 = all8 and txt.contains(jd)
	ok(all8, "(3) the judge rows list all 8 newer judges")
	print(txt)
	var btn = m.ui_find_list.find_child("rs_best", true, false)
	ok(btn != null and m.ui_find_list.find_child("rs_best_label", true, false) != null, "(7) the biggest-gain line and its button are in the panel")
	var win := Rect2(Vector2.ZERO, m.get_viewport().get_visible_rect().size)
	ok(win.encloses(m.ui_find.get_global_rect()), "(7) the panel %s is inside the window %s" % [str(m.ui_find.get_global_rect()), str(win)])
	(m.ui_find.get_child(0) as ScrollContainer).scroll_vertical = 100000   # the judge rows are at the foot of the panel: that is what the shot shows
	await idle(3)
	ok(jl.get_global_rect().intersects(m.ui_find.get_global_rect()) and jl.get_global_rect().end.y <= m.ui_find.get_global_rect().end.y + 2.0, "(7) scrolled to the foot, the judge rows are inside the panel")
	root.get_texture().get_image().save_png(SHOT)
	(m.ui_find.get_child(0) as ScrollContainer).scroll_vertical = 0

	# (4) apply
	if btn != null:
		var pred := float(bg["gain"])
		btn.pressed.emit()
		await idle(6)
		var after := float(rs.res["score"])
		ok(absf((after - score0) - pred) <= 1.0, "(4) predicted %+.2f, got %+.2f (%.2f -> %.2f)" % [pred, after - score0, score0, after])
		ok(after > score0 and float(rs.res["pen"]["MOMENTUM"]) == 0.0, "(4) the stop is no longer flagged and the score rose")
		ok(m.undo.size() == u0 + 1, "(4) one undo step (%d -> %d)" % [u0, m.undo.size()])
		m._undo()
		await idle()
		ok(JSON.stringify(m.S.cards) == before, "(4) Ctrl+Z restores the cards byte for byte")
	print("i45: ", "ALL OK" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails > 0 else 0)
