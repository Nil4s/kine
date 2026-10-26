## godot --headless --path . -s tests/loop_test.gd     (GATES W2, UPGRADES #58)
## LOOP SEAM: a loop scene's end must meet its start. A seamless loop has no finding; the same scene not marked a loop
## is not graded; a pose seam is found, the joint named, its gap matching the test's own reading of the points; a speed
## seam (the poses meet, the velocity does not) is found; 'Loop: close the seam' removes the pose seam, one undo step;
## the flag saves and loads, and a scene without it saves without the key.
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


func scene(poses: Array, loop: bool, spline := false, hold := 0.3) -> Scene:
	var S := Scene.new()
	S.name = "zz_loop"
	for k in poses.size():
		S.add("c%d" % (k + 1), poses[k].duplicate(true))
		S.cards[-1]["hold"] = hold
	S.loop = loop
	S.spline = spline
	return S


func seam(S: Scene) -> Array:
	return Rulebook.rule_loop(S, m.B)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	m._load_scene("res://scenes/combo3.json")
	var P: Array = m.S.cards.map(func(c): return c["pose"])
	var A: Dictionary = P[0]
	var Bp: Dictionary = P[3]
	var C: Dictionary = P[6]

	var S := scene([A, Bp, A], true)
	ok(seam(S).is_empty(), "1 a seamless loop (A, B, A): no LOOP SEAM")
	S = scene([A, Bp, C], false)
	ok(seam(S).is_empty() and Rulebook.check(S, m.B).filter(func(f): return f["rule"] == "LOOP SEAM").is_empty(),
		"2 the same open-ended scene NOT marked a loop: not graded")
	S = scene([A, Bp, C], true)
	var f := seam(S)
	var fp: Array = f.filter(func(x): return "does not meet" in x["msg"])
	# the test's own reading: every point at t = 0 and at the end
	var keep: Dictionary = m.B.state()
	S.apply(m.B, 0.0)
	var p0: Dictionary = m.B.P.duplicate()
	S.apply(m.B, S.length())
	var wg := 0.0
	for j in p0:
		wg = maxf(wg, ((p0[j] as Vector3) - m.B.P[j]).length())
	m.B.set_state(keep)
	ok(fp.size() == 1 and fp[0]["joint"] != "" and ("%.1f cm" % (wg * 100.0)) in fp[0]["msg"] and fp[0]["sev"] == "WARN",
		"3 a pose seam (A, B, C): found, the joint named (%s), the farthest point's gap %.1f cm as the test reads it: '%s'" % [
		fp[0]["joint"] if fp.size() > 0 else "-", wg * 100.0, fp[0]["msg"].left(150) if fp.size() > 0 else "nothing"])
	ok(Rulebook.check(S, m.B).filter(func(x): return x["rule"] == "LOOP SEAM").size() == f.size() and
		(Rulebook.check(S, m.B).filter(func(x): return x["rule"] == "LOOP SEAM")[0]["card"] == S.cards.size() - 1),
		"4 CHECK carries it, on the last card")

	# a speed seam: the scene ends at rest (the last card holds), and the next lap leaves the first card (no hold) at
	# speed: a LINEAR move into card 2. (Round 16 used the spline here; its "speed leaving the start" was the hips
	# reading 75 ms ahead at t = 0, the first frame 5.3 deg off its card: fixed in round 18, GATES Y2, and the spline
	# leaves its first card, a stop, at rest, so it has no seam to find - checked as 5c)
	var sp := scene([A, Bp, A], true, false, 0.0)
	sp.cards[1]["ease"] = "linear"
	sp.cards[-1]["hold"] = 0.3
	var fs := seam(sp).filter(func(x): return "speed jumps" in x["msg"])
	print("     A, linear into B, A, the first card with no hold: %s" % [seam(sp).map(func(x): return x["msg"].left(120))])
	ok(fs.size() == 1 and "0.00 m/s at the end" in fs[0]["msg"] and fs[0]["joint"] != "",
		"5 a speed seam (at rest at the end, at speed leaving the start): found as SPEED, the part named (%s)" % (fs[0]["joint"] if fs.size() > 0 else "-"))
	var rest := scene([A, Bp, A], true, false, 0.3)
	rest.cards[0]["hold"] = 0.0
	ok(seam(rest).is_empty(), "5b eased (no spline), the first card with no hold: the move leaves at rest, the pose within 0.44 deg: nothing")
	var spl := scene([A, Bp, A], true, true, 0.0)
	spl.cards[-1]["hold"] = 0.3
	ok(seam(spl).is_empty(), "5c the spline, the first card with no hold: its first frame is that card and it leaves at rest: nothing (round 16 found a 5.3 deg pose seam here: the lead at t = 0)")

	# the fix, through the window's command
	m.S = scene([A, Bp, C], true)
	m._rebuild_cards()
	var u0: int = m.undo.size()
	m._loop_close()
	ok(seam(m.S).filter(func(x): return "does not meet" in x["msg"]).is_empty() and m.undo.size() == u0 + 1,
		"6 'Loop: close the seam': the pose seam is gone, one undo step")
	m._undo()
	ok(not seam(m.S).filter(func(x): return "does not meet" in x["msg"]).is_empty(), "7 undo brings the seam back")

	# saved and loaded
	var d: Dictionary = scene([A, Bp, A], true).to_dict(m.B)
	var d0: Dictionary = scene([A, Bp, A], false).to_dict(m.B)
	var back := Scene.new()
	back.from_dict(JSON.parse_string(JSON.stringify(d)))
	ok(d.get("loop", false) == true and not d0.has("loop") and back.loop, "8 the flag saves and loads; a scene without it saves without the key")
	ok(m.find_child("check_loop", true, false) != null and m.ui_loop.text == "Loop", "9 the Loop box is in the window")
	m.B.set_state(keep)
	print("LOOP: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
