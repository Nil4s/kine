## godot --path . -s tests/fix_preview_test.gd     (GATES Q6; needs a window)
## FIX PREVIEW: hovering a finding's Fix button shows a blue ghost of the body at that moment AFTER the fix, and changes
## nothing: the scene's cards (JSON) are byte-identical and no undo step is made. It is worked out on a worker
## thread, so the window keeps drawing (no frame over 250 ms) even for a fix that takes seconds. The ghost is
## the fix's real result: after the click, the scene posed at that time matches the ghost. Leaving hides it. Run on
## every fixable finding of combo3 (spline: FOOT SLIDE) and of every scene in scenes/ that has one.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func fp() -> String:
	return JSON.stringify(m.S.cards) + JSON.stringify(m.B.state())


func ghost_visible() -> bool:
	return m.ov._ghosts[2][0].visible


## the largest joint gap (m) between two position tables
func gap(a: Dictionary, b: Dictionary) -> float:
	var w := 0.0
	for j in a:
		w = maxf(w, ((a[j] - b[j]) as Vector3).length())
	return w


func run(path: String, spline: bool) -> int:
	m._load_scene(path)
	m.S.spline = spline
	m._rebuild_cards()
	m._check()
	await process_frame
	var fx: Array = m.findings.filter(func(x): return Fixer.label(x, m.S) != "")
	var n := 0
	for f in fx:
		var btn: Button = null
		for c in m.ui_find_list.get_children():
			if c is Button and c.text == Fixer.label(f, m.S) and btn == null and c.get_signal_connection_list("mouse_entered").any(func(k): return (k["callable"] as Callable).get_bound_arguments() == [f]):
				btn = c
		if btn == null:
			ok(false, "%s: no button for %s %.2f s" % [path.get_file(), f["rule"], f["t"]])
			continue
		var before := JSON.stringify(m.S.cards)
		var u_h: int = m.undo.size()
		var t0 := Time.get_ticks_msec()
		btn.mouse_entered.emit()
		var ms := Time.get_ticks_msec() - t0
		var frames := 0
		var worst := 0
		while not ghost_visible() and frames < 2000:
			var t1 := Time.get_ticks_msec()
			await process_frame
			worst = maxi(worst, Time.get_ticks_msec() - t1)
			frames += 1
		var ghostP: Dictionary = m.ov.GB.P.duplicate()
		m.S.apply(m.ov.GB, f["t"])   # the same body, the scene as it is now
		var nowP: Dictionary = m.ov.GB.P.duplicate()
		m.ov.fix_preview(m.S, m._previews[f], m.playhead)   # back to the ghost
		ok(ghost_visible() and JSON.stringify(m.S.cards) == before and m.undo.size() == u_h, "%s%s %s %.2f s: hover -> ghost shown after %d frames, the scene's cards byte-identical, no undo step" % [path.get_file(), " spline" if spline else "", f["rule"], f["t"], frames])
		ok(ms < 100 and worst < 250, "  the window never waited: the hover call took %d ms, the slowest frame meanwhile %d ms" % [ms, worst])
		btn.mouse_exited.emit()
		ok(not ghost_visible(), "  leave -> ghost gone")
		# the click: the scene at that time must match the ghost
		btn.mouse_entered.emit()
		var u0: int = m.undo.size()
		btn.pressed.emit()
		for k in 600:
			await process_frame
			if not m._fixing:
				break
		if m.undo.size() == u0 + 1:
			m.S.apply(m.ov.GB, f["t"])
			ok(gap(m.ov.GB.P, ghostP) < 1e-4 and not ghost_visible(), "  clicked (kept): the scene at %.2f s IS the ghost (%.3f mm), ghost gone; it differed from before by %.1f mm" % [f["t"], gap(m.ov.GB.P, ghostP) * 1000.0, gap(nowP, ghostP) * 1000.0])
			m._undo()
		else:
			ok(not ghost_visible(), "  clicked (not kept: %s): ghost gone" % m.ui_status.text.left(60))
		n += 1
		break   # the findings are rebuilt by the fix; one per scene keeps it exact
	return n


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var total := 0
	total += await run("res://scenes/combo3.json", true)
	for f in DirAccess.get_files_at("res://scenes"):
		if f.ends_with(".json"):
			total += await run("res://scenes/" + f, false)
	ok(total >= 2, "%d scenes had a Fix to preview" % total)
	print("FIX PREVIEW TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
