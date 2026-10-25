## godot --path . -s tests/realism_lazy_test.gd     (I16 lazy gains: the Realism score panel draws the score and the reasons with no gain predicted; "Find the biggest gain" predicts; needs a window)
## Bars, written before measuring:
##  (a) on scenes/combo3.json, the "Realism score" command (its registry callable, called the way the command search's _run calls it: not awaited) shows the score label within 12 s cold, and no gain is predicted yet
##  (b) pressing rs_find then shows rs_best with the same gain (to 0.01 points) as RealismUI.biggest_gain() called directly on cold caches
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


## a score from nothing cached: the judges asked again, the frame memo and the force cache empty (the move database stays: it is read once per run)
func cold(rs: RealismUI) -> void:
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
	m.tc_ui.db = MotionMatch.build()   # read once for the run, as the timing coach's database; show() would read it itself when empty
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m._refresh()
	await idle()
	var rs: RealismUI = m.rs_ui

	# the registry entry of "Realism score", as the command search holds it
	var reg := {}
	rs.commands(func(n, _a, f, _k, _h, _d): reg[n] = f)
	var fn: Callable = reg["Realism score"]

	# (a) cold, the command runs and the score label is on the panel within 12 s
	cold(rs)
	var t0 := Time.get_ticks_usec()
	fn.call()
	var sc = m.ui_find_list.find_child("rs_score", true, false)
	var waited := 0
	while sc == null and Time.get_ticks_usec() - t0 < 60000000:
		await process_frame
		sc = m.ui_find_list.find_child("rs_score", true, false)
		waited += 1
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	ok(sc != null and ms <= 12000.0, "(a) the Realism score command on combo3, cold: score label '%s' after %.0f ms (bar 12000 ms)" % [sc.text if sc != null else "none", ms])
	var fb = m.ui_find_list.find_child("rs_find", true, false)
	ok(fb != null and rs.gains.is_empty() and m.ui_find_list.find_child("rs_best", true, false) == null,
		"(a) the panel is drawn with no gain predicted yet (rs_find button %s, %d gains)" % [fb != null, rs.gains.size()])

	# (b) the find button predicts the gains and shows the biggest one
	if fb != null:
		fb.pressed.emit()
	var t1 := Time.get_ticks_usec()
	var bb = null
	while fb != null and bb == null and Time.get_ticks_usec() - t1 < 300000000:
		await process_frame
		bb = m.ui_find_list.find_child("rs_best", true, false)
	var bl = m.ui_find_list.find_child("rs_best_label", true, false)
	ok(bb != null and bl != null and not rs.best.is_empty(), "(b) rs_find shows rs_best and its label after %.0f ms" % (float(Time.get_ticks_usec() - t1) / 1000.0))
	if not rs.best.is_empty() and bl != null:
		var shown := float(rs.best["gain"])
		ok(String(bl.text).contains("+%.1f points" % shown), "(b) the label reads the gain: '%s'" % String(bl.text).left(60))
		rs.gains = {}
		var direct: Dictionary = rs.biggest_gain()
		var same := not direct.is_empty() and absf(float(direct["gain"]) - shown) <= 0.01 and String(direct["item"]["text"]) == String(rs.best["item"]["text"])
		ok(same, "(b) rs_best gain %+.2f equals RealismUI.biggest_gain() called directly: %s" % [shown, str(direct.get("gain", "none"))])

	print("realism_lazy: ", "ALL OK" if fails == 0 else "%d FAILED" % fails)
	quit(1 if fails > 0 else 0)
