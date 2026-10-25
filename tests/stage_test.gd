## godot --path . -s tests/stage_test.gd     (round 43, GATES YY8; needs a window: the real poser UI)
## BLOCK -> SPLINE -> CHECK, one guided path (main._stage_block / _stage_spline). Bars:
##   1 BLOCK holds each card to the next: at 25 / 50 / 95 % of every gap the body is the card's own pose, bit for bit.
##   2 SPLINE = the old playback: 24 times over the scene play to the same angles as before blocking, bit for bit.
##   3 one undo step each (block 1, spline 1), a second Block while blocking adds none; the saved scene never changes.
##   4 Check ran after the spline: its findings are what Check gives on the scene itself (same rules, same times).
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func angs(t: float) -> Dictionary:
	m._ps().apply(m.B, t)
	return m.B.ang.duplicate()


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	m._load_scene("res://scenes/combo3.json")
	await process_frame
	var L: float = m.S.length()
	var before := []
	for i in 24:
		before.append(angs(L * i / 23.0))
	var saved := JSON.stringify(m.S.to_dict(m.B))
	var u0: int = m.undo.size()
	m._stage_block()
	var u1: int = m.undo.size()
	m._stage_block()
	var u1b: int = m.undo.size()
	# the app's pose bake drops its table and re-bakes a frame AFTER an edit (main._bake_poll, ROADMAP 99): drop it here, as that poll
	# does, so the poses below are the stepped cards' own and not the table of the cards as they were (no frames: they would move the body)
	m.S.baker = null
	var ts: Array = m.S.times()
	var held := 0
	var bad := []
	for k in ts.size() - 1:
		var at := angs(float(ts[k][1]))
		for f in [0.25, 0.5, 0.95]:
			var t := lerpf(float(ts[k][1]), float(ts[k + 1][1]), f)
			if angs(t) == at:
				held += 1
			else:
				bad.append([k, f])
	ok(m.stepped_view and bad.is_empty() and held == 3 * (ts.size() - 1), "1 BLOCK: %d of %d in-gap times hold the card's own pose %s" % [held, 3 * (ts.size() - 1), bad])
	var saved_block := JSON.stringify(m.S.to_dict(m.B))
	m.findings = []
	m.check_ran = false
	m._stage_spline()
	var u2: int = m.undo.size()
	var same := 0
	for i in 24:
		if angs(L * i / 23.0) == before[i]:
			same += 1
	ok(not m.stepped_view and same == 24, "2 SPLINE: %d of 24 times play exactly as before blocking" % same)
	ok(u1 - u0 == 1 and u1b == u1 and u2 - u1 == 1 and saved_block == saved and JSON.stringify(m.S.to_dict(m.B)) == saved,
		"3 undo steps: block %d, block again %d, spline %d; the saved scene unchanged %s" % [u1 - u0, u1b - u1, u2 - u1, JSON.stringify(m.S.to_dict(m.B)) == saved])
	var direct: Array = Rulebook.check(m.S, m.ov.GB, Rulebook.sample(m.S, m.ov.GB))
	var a: Array = m.findings.map(func(f): return "%s@%.3f" % [f["rule"], f["t"]])
	var b: Array = direct.map(func(f): return "%s@%.3f" % [f["rule"], f["t"]])
	ok(m.check_ran and a == b and a.size() > 0, "4 Check ran after the spline: %d findings, the same as Check on the scene %s" % [a.size(), a])
	print("STAGE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
