## godot --path . -s tests/plant_test.gd     (GATES Q3, Q4; needs a window)
## PLANTED FEET and the FOOT SLIDE fix, on a real slide: combo3 with Smooth (spline) on creeps a foot ~5 cm (the
## per-move pinning does not stop a stance that differs by a few cm from card to card). Check finds it; its Fix button
## in the findings panel plants that foot on the cards of the stretch; then: the foot's drift over the stretch is under
## 2 mm, Check no longer reports that slide and reports nothing new, it is ONE undo step, Ctrl+Z takes it back, the
## plant survives save/load, and taking it off gives back the old motion exactly (the poses were never changed).
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## the farthest the foot's toe base gets (along the floor) from where it is at t0, over [t0, t1]
func drift(S: Scene, B: Body, sd: String, t0: float, t1: float) -> float:
	S.apply(B, t0)
	var p0: Vector3 = B.P["ball" + sd]
	var far := 0.0
	var t := t0
	while t <= t1:
		S.apply(B, t)
		var d: Vector3 = B.P["ball" + sd] - p0
		far = maxf(far, Vector2(d.x, d.z).length())
		t += 1.0 / 30.0
	return far


## every joint position at 40 times through the scene
func motion(S: Scene, B: Body) -> Array:
	var out := []
	for k in 40:
		S.apply(B, S.length() * k / 39.0)
		out.append(B.P.duplicate())
	return out


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	m._load_scene("res://scenes/combo3.json")
	m.S.spline = true
	m._rebuild_cards()
	m._refresh()
	var B: Body = m.ov.GB
	# ROUND 32 (MM2): with automatic pinning ON, holds keep a pinned foot where its move put it, and combo3's creep is
	# gone; recorded here. The card "plant" fix is a separate mechanism, so the fixture is the same scene with pinning OFF
	m._check()
	await process_frame
	var pinned_slides: Array = m.findings.filter(func(x): return x["rule"] == "FOOT SLIDE")
	ok(pinned_slides.is_empty(), "combo3 in spline, pinning ON: Check finds %d FOOT SLIDE (round 32 holds the feet)" % pinned_slides.size())
	m.S.pin = false
	m._refresh()
	var plain := motion(m.S, B)
	m._check()
	await process_frame
	var slides: Array = m.findings.filter(func(x): return x["rule"] == "FOOT SLIDE")
	ok(slides.size() >= 1, "combo3 in spline, pinning OFF: Check finds %d FOOT SLIDE %s" % [slides.size(), slides.map(func(x): return "%s %.2f-%.2f s %.1f cm" % [x.get("foot", "?"), x["t"], x.get("t1", -1.0), x["v"] * 100.0])])
	if slides.is_empty():
		print("PLANT TEST FAIL (no slide to fix)")
		TestFiles.cleanup()
		quit(1)
		return
	var f: Dictionary = slides[0]
	var sd: String = f["foot"]
	var d0 := drift(m.S, B, sd, f["t"], f["t1"])
	ok(d0 > 0.025, "  before: the %s foot drifts %.1f cm over %.2f-%.2f s" % [sd, d0 * 100.0, f["t"], f["t1"]])
	var others0: Array = m.findings.filter(func(x): return x != f)
	# the Fix button, as the user presses it
	var fixb: Button = null
	for c in m.ui_find_list.get_children():
		if c is Button and c.text == "Fix: plant this foot":
			fixb = c
	ok(fixb != null, "the slide has a 'Fix: plant this foot' button")
	var poses0: Array = m.S.cards.map(func(c): return JSON.stringify(c["pose"]))
	var u0: int = m.undo.size()
	fixb.pressed.emit()
	for k in 400:
		await process_frame
		if not m._fixing:
			break
	print("     said: " + m.ui_status.text)
	ok(m.undo.size() == u0 + 1 and String(m.ui_status.text).begins_with("Fixed"), "pressed: kept, one undo step")
	var planted := []
	for i in m.S.cards.size():
		if sd in m.S.cards[i].get("plant", []):
			planted.append(i + 1)
	ok(not planted.is_empty() and m.S.cards.map(func(c): return JSON.stringify(c["pose"])) == poses0, "  the %s foot planted on cards %s; no pose changed" % [sd, planted])
	var d1 := drift(m.S, B, sd, f["t"], f["t1"])
	ok(d1 < 0.002, "  after: the foot drifts %.2f mm over the same stretch (bar 2 mm)" % (d1 * 1000.0))
	var after: Array = m.findings
	ok(after.filter(func(x): return Fixer._same_finding(f, x)).is_empty(), "  Check: that slide is gone")
	var new := after.filter(func(x): return others0.filter(func(y): return y["rule"] == x["rule"] and y["card"] == x["card"]).is_empty())
	ok(new.is_empty(), "  Check: nothing new (%d findings before the fix besides it, %d after) %s" % [others0.size(), after.size(), new.map(func(x): return x["rule"])])
	# save / load
	var back := Scene.new()
	back.from_dict(JSON.parse_string(JSON.stringify(m.S.to_dict(B))))
	ok(sd in back.cards[planted[0] - 1].get("plant", []), "save + load: card %d still plants the %s foot" % [planted[0], sd])
	# undo
	m._undo()
	var left := 0
	for c in m.S.cards:
		left += c.get("plant", []).size()
	ok(left == 0, "Ctrl+Z: no card plants a foot")
	ok(motion(m.S, B) == plain, "  and the scene plays exactly as before (every joint, 40 times, bit for bit)")
	# by hand: the registry's toggle on card 12 (search: "plant"), on then off, one undo step each
	m._card_pick(11)
	var tog: Callable
	for c in m._commands():
		if c["name"] == "Plant the right foot on this card":
			tog = c["run"]
	var u1: int = m.undo.size()
	tog.call()
	ok("_r" in m.S.cards[11].get("plant", []) and m.undo.size() == u1 + 1, "by hand: 'Plant the right foot on this card' on card 12: planted, one undo step")
	tog.call()
	ok(not m.S.cards[11].has("plant"), "  again: free (the key is gone, so the scene saves as it was)")
	print("PLANT TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
