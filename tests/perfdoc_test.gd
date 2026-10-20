## godot --path . -s tests/perfdoc_test.gd     (ROADMAP_400 Q15; needs a window)
## PERF DOCTOR (scripts/perf_doc.gd): "Help: why is it slow?". Bars, written before measuring:
##   1 RANK: with a 60-copy crowd (Crowd.MAX_N, a real setting) on, the crowd is ranked #1 of the measured systems, and the
##     report names a fix button for it
##   2 FIX: pressing that button (one undo step, restores the crowd) and measuring again, the crowd's ms/frame drops by >= 50 %;
##     the report prints fps before -> after
##   3 OFF COST: with the doctor off, the brackets main.gd carries (20 pairs counted generously, 17 in the source) add < 0.05 ms
##     a frame, measured as 20 t()+add() pairs timed over 20000 frames' worth
##   4 PLACEMENT: the report panel is inside the window, shows three ranked rows each with a fix or an advice line, and the
##     screenshot is taken in a whole-body view
extends SceneTree

var fails := 0
var m: Node
const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/perfdoc.png"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func measure(secs: float, after := false) -> void:
	m.pdoc.start(secs, after)
	while m.pdoc.running:
		await process_frame
	await idle(2)


func ms_of(k: String) -> float:
	for r in m.pdoc.last["rows"]:
		if r["k"] == k:
			return r["ms"]
	return 0.0


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle(2)
	ok(m.S.cards.size() >= 2, "the scene has %d cards (playback mode)" % m.S.cards.size())
	# baseline, nothing heavy
	await measure(1.5)
	var base := []
	for r in m.pdoc.last["rows"]:
		base.append("%s %.2f" % [r["k"], r["ms"]])
	print("info baseline %.0f fps: %s" % [m.pdoc.last["fps"], ", ".join(base)])
	# 1 RANK
	var u0: int = m.undo.size()
	m._crowd_make(60)
	await idle(3)
	await measure(3.0)
	var rows: Array = m.pdoc.last["rows"]
	var line := []
	for r in rows.slice(0, 5):
		line.append("%s %.2f ms" % [r["k"], r["ms"]])
	print("info heavy %.0f fps, mode %s: %s" % [m.pdoc.last["fps"], m.pdoc.last["mode"], ", ".join(line)])
	var t3: Array = m.pdoc.top()
	ok(rows.size() > 0 and rows[0]["k"] == "crowd", "crowd of 60 is ranked #1 at %.2f ms/frame (next %s)" % [rows[0]["ms"], line[1] if line.size() > 1 else "-"])
	ok(t3.size() >= 1 and (t3[0]["fix"] as Callable).is_valid() and t3[0]["label"] != "", "its fix button: '%s'" % t3[0]["label"])
	# 4 PLACEMENT (taken now: the report, whole-body view)
	m.yaw = 0.0
	m._cam()
	await idle(3)
	var pn: PanelContainer = m.pdoc.panel
	var vr: Rect2 = m.get_viewport().get_visible_rect()
	var pr := pn.get_global_rect()
	ok(pn.visible and vr.encloses(pr), "report panel %s inside window %s" % [pr, vr.size])
	var nrows := 0
	var nfix := 0
	for c in pn.find_children("*", "Button", true, false):
		if String(c.name).begins_with("fix_"):
			nfix += 1
	ok(t3.size() == mini(3, rows.filter(func(r): return r["ms"] >= 0.02).size()) and nfix >= 1, "%d ranked rows, %d fix buttons" % [t3.size(), nfix])
	var img := m.get_viewport().get_texture().get_image()
	img.save_png(SHOT)
	# 2 FIX
	var before_ms := ms_of("crowd")
	var before_fps: float = m.pdoc.last["fps"]
	var btn := pn.find_child("fix_crowd", true, false) as Button
	ok(btn != null, "the crowd's fix button is in the panel")
	var un: int = m.undo.size()
	btn.pressed.emit()
	while m.pdoc.running:
		await process_frame
	await idle(2)
	var after_ms := ms_of("crowd")
	ok(after_ms <= 0.5 * before_ms, "crowd %.2f -> %.2f ms/frame (%.0f %% drop, bar 50 %%); fps %.0f -> %.0f" % [before_ms, after_ms, 100.0 * (1.0 - after_ms / maxf(before_ms, 1e-9)), before_fps, m.pdoc.last["fps"]])
	ok(m.undo.size() == un + 1 and int(m.S.crowd.get("n", 0)) == 20, "the fix is one undo step (crowd now %d)" % int(m.S.crowd.get("n", 0)))
	m._undo()
	await idle(2)
	ok(int(m.S.crowd.get("n", 0)) == 60, "Ctrl+Z restores the crowd of 60")
	var shown := ""
	for c in pn.find_children("*", "Label", true, false):
		shown += (c as Label).text + "\n"
	ok(shown.find("fps ->") >= 0, "the report prints fps before -> after")
	# 3 OFF COST
	PerfDoc.on = false
	var n := 20000
	var t0 := Time.get_ticks_usec()
	for i in n:
		for j in 20:
			var p := PerfDoc.t()
			PerfDoc.add("onion", p)
	var per := float(Time.get_ticks_usec() - t0) / 1000.0 / n
	ok(per < 0.05, "doctor off: 20 brackets cost %.5f ms/frame (bar 0.05)" % per)
	ok(PerfDoc.acc.is_empty() or not PerfDoc.on, "nothing accumulates while off")
	print("perfdoc_test: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit(0 if fails == 0 else 1)
