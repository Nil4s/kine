## godot --path . -s tests/curve_why_test.gd     (round 48, GATES DD5, UPGRADES_300 #251; a window: pixels are read)
## THE WHY OF A CURVE (scripts/why.gd): red spans on the curve editor where a Check rule fires because of what the picked
## joint moves, named. Nick's bo_spin (read from scenes/, cloned in memory, never written) has 2 HITCH and 1 TIP SPEED.
##   1 every HITCH span is EXACTLY the rule's window: its finding's time +- HITCH_SPAN frames (Rulebook.check's own t)
##   2 every TIP SPEED span covers exactly the contiguous frames over the cap round the finding (rebuilt here from
##     Rulebook.sample: every frame inside over the cap, the frame just outside each end not), +- half a frame
##   3 whose business: the hips-and-head hitch is on calf_l and neck_01; the tip-only spans are not on calf_l; lowerarm_r
##     gets every span with the tip (3)
##   4 the editor on lowerarm_r (the clone, given part keys on that arm, so its own spans): its `why` = Why.for_joint of
##     that scene, recomputed here; the screen inside each span is redder than the same row outside
##     every span (read from the window's pixels: red minus green, the band's middle vs a clear column)
##   5 control: a scene whose two cards are the same pose has no spans, and the editor paints none
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/bo_spin.json")))
	var sm := Rulebook.sample(S, B)
	var fs := Rulebook.check(S, B, sm)
	var sp := Why.spans(S, B, sm)
	# 1 HITCH windows
	var hf := fs.filter(func(f): return f["rule"] == "HITCH")
	var hs := sp.filter(func(s): return s["rule"] == "HITCH")
	var w1 := 0.0
	for k in mini(hf.size(), hs.size()):
		w1 = maxf(w1, maxf(absf(float(hs[k]["t0"]) - (float(hf[k]["t"]) - 3.0 / 60.0)), absf(float(hs[k]["t1"]) - (float(hf[k]["t"]) + 3.0 / 60.0))))
	ok(hf.size() == 2 and hs.size() == 2 and w1 < 1e-6, "1 HITCH: %d findings, %d spans, each = its time +- 3 frames at 60 (worst %.9f s)" % [hf.size(), hs.size(), w1])
	# 2 TIP SPEED frames
	var cap: float = Rulebook.AT.TIP_MAX[sm["kind"]]
	var ts: Array = sm["t"]
	var good := true
	var spans_t := sp.filter(func(s): return s["rule"] == "TIP SPEED")
	var desc := []
	for s in spans_t:
		var inside := []
		for i in ts.size():
			if float(ts[i]) > float(s["t0"]) and float(ts[i]) < float(s["t1"]):
				inside.append(i)
		var a: int = inside[0]
		var b: int = inside[-1]
		for i in inside:
			good = good and float(sm["tip"][i]) > cap
		good = good and (a == 0 or float(sm["tip"][a - 1]) <= cap) and (b == ts.size() - 1 or float(sm["tip"][b + 1]) <= cap)
		desc.append("frames %d..%d, tip %.1f..%.1f m/s, outside %.1f / %.1f" % [a, b, sm["tip"][a], sm["tip"][b], sm["tip"][a - 1], sm["tip"][b + 1]])
	ok(spans_t.size() == 1 and good, "2 TIP SPEED (cap %.0f m/s): %s; every frame inside over the cap, each end's outside neighbour not: %s" % [cap, desc, good])
	# 3 whose business
	var calf := Why.for_joint(sp, "calf_l")
	var neck := Why.for_joint(sp, "neck_01")
	var arm := Why.for_joint(sp, "lowerarm_r")
	ok(calf.size() == 1 and "hips" in calf[0]["parts"] and neck.any(func(s): return "head" in s["parts"]) and not neck.any(func(s): return s["parts"] == ["tip"]) and arm.size() == 3,
		"3 calf_l: %d span (%s); neck_01: %d (no tip-only one); lowerarm_r: %d (every span with the tip)" % [calf.size(), calf.map(func(s): return s["parts"]), neck.size(), arm.size()])
	# 4 the editor
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var S4 := S.clone()
	S4.name = "zz_curve_why"
	S4.part_keys = {"lowerarm_r": [{"t": 0.0, "v": Vector3(20, 0, 0)}, {"t": S4.length(), "v": Vector3(60, 0, 0)}]}
	m.S = S4
	m._rebuild_cards()
	m.sel = "lowerarm_r"
	m._refresh()
	for c in m._commands():
		if c["id"] == "curve_editor":
			c["run"].call()
	await idle(4)
	var ce: CurveEditor = m.ui_curve
	ce.t0 = 0.0
	ce.t1 = S4.length()
	ce.queue_redraw()
	await idle(4)
	var img := root.get_texture().get_image()
	var off := ce.get_global_rect().position
	var y := off.y + ce.plot().position.y + ce.plot().size.y * 0.25
	var clear_x := -1.0
	for x in range(int(ce.plot().position.x) + 4, int(ce.plot().end.x) - 4, 3):
		var free := true
		for s in ce.why:
			var r := ce.why_rect(s)
			free = free and (x < r.position.x - 4 or x > r.end.x + 4)
		if free:
			clear_x = x
			break
	var redder := true
	var px := []
	for s in ce.why:
		var r := ce.why_rect(s)
		var cin := img.get_pixelv(Vector2i(int(off.x + r.get_center().x), int(y)))
		var cout := img.get_pixelv(Vector2i(int(off.x + clear_x), int(y)))
		redder = redder and (cin.r - cin.g) > (cout.r - cout.g) + 0.03
		px.append("%s %.3f vs %.3f" % [s["rule"], cin.r - cin.g, cout.r - cout.g])
	var want4 := Why.for_joint(Why.spans(S4, B), "lowerarm_r")
	var same4: bool = var_to_str(want4.map(func(s): return [s["rule"], s["t0"], s["t1"]])) == var_to_str(ce.why.map(func(s): return [s["rule"], s["t0"], s["t1"]]))
	ok(same4 and ce.why.size() > 0 and clear_x > 0 and redder, "4 the editor on lowerarm_r (the clone given part keys: its own spans): %d spans %s, = Why on that scene for lowerarm_r %s; red minus green inside vs a clear column (x %d): %s" % [ce.why.size(), ce.why.map(func(s): return s["rule"]), same4, clear_x, px])
	# 5 control
	var S5 := Scene.new()
	S5.name = "zz_curve_why_flat"
	B.fk()
	S5.add("a", B.to_dict())
	S5.add("b", B.to_dict())
	m.S = S5
	m._rebuild_cards()
	m._refresh()
	await idle(4)
	ok(Why.spans(S5, B).is_empty() and ce.why.is_empty(), "5 control: two equal cards -> %d spans, the editor paints %d" % [Why.spans(S5, B).size(), ce.why.size()])
	m.queue_free()
	print("CURVE WHY TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
