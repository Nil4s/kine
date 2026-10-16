## godot --headless --path . -s tests/fix_test.gd      (GATES K2-K6)
## Every fixable finding on real scenes, each applied to a FRESH copy: a kept fix removes its finding and adds no
## must-fix; a refused one leaves the cards byte-identical; the cards always keep their count, names and order.
## Also: the head fix's windowed re-sample equals a full re-play bit for bit (spline and not), and its cost.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func load_scene(path: String) -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
	return S


## the windowed sample after a pose edit on card c == the full sample, every raw frame
func window_exact(path: String, c: int, B: Body) -> void:
	var S := load_scene(path)
	var sm0 := Rulebook.sample(S, B)
	var a := Moves._flat(S.cards[c - 1]["pose"])
	var b := Moves._flat(S.cards[c]["pose"])
	Fixer._put(S, B, c, a, b, 0.4)
	var w := Fixer.window(S, c)
	var t0 := Time.get_ticks_msec()
	var part := Rulebook.sample(S, B, sm0, w.x, w.y)
	var t1 := Time.get_ticks_msec()
	var full := Rulebook.sample(S, B)
	var t2 := Time.get_ticks_msec()
	var diff := 0
	var moved := 0
	for i in full["_raw"].size():
		if var_to_str(part["_raw"][i]) != var_to_str(full["_raw"][i]):
			diff += 1
		if var_to_str(sm0["_raw"][i]) != var_to_str(full["_raw"][i]):
			moved += 1
	ok(diff == 0 and moved > 0, "%s card %d edited: window %.2f-%.2f s re-played == full re-play on all %d frames (%d frames really moved: anti-vacuity); %d ms vs %d ms" % [path.get_file(), c + 1, w.x, w.y, full["_raw"].size(), moved, t1 - t0, t2 - t1])


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	window_exact("res://scenes/combo3.json", 9, B)
	window_exact("res://scenes/_wip/combo3_detail.json", 23, B)
	var kept := {}
	var putback := 0
	for path in ["res://scenes/combo3.json", "res://scenes/bo_spin.json", "res://scenes/thrust.json", "res://scenes/_wip/combo3_detail.json"]:
		var S0 := load_scene(path)
		var sm := Rulebook.sample(S0, B)
		var found := Rulebook.check(S0, B, sm)
		print("== %s: %d findings" % [path.get_file(), found.size()])
		for f in found:
			var lbl := Fixer.label(f, S0)
			if lbl == "":
				ok(f["rule"] in ["SEQUENCE", "HIPS TURN", "FOOT SLIDE", "BALANCE"] or (f["rule"] == "HITCH" and S0.spline) or f["card"] == 0, "  no button for %s at %.2f s (%s)" % [f["rule"], f["t"], "spline: two cards fight" if f["rule"] == "HITCH" else "no safe fix"])
				continue
			var S := load_scene(path)
			var names := S.cards.map(func(c): return c["name"])
			var cards0 := JSON.stringify(S.cards)
			var t0 := Time.get_ticks_msec()
			var r := Fixer.apply(f, S, B, sm)
			var ms := Time.get_ticks_msec() - t0
			var all0: Array = r["before"]
			var all1 := Rulebook.check(S, B)   # a FULL re-check, independent of the fix's own (windowed) one
			if r["kept"]:
				ok(all1.filter(func(x): return Fixer._same_finding(f, x)).is_empty(), "  KEPT %s at %.2f s [%.1f s]: %s" % [f["rule"], f["t"], ms / 1000.0, r["msg"]])
				ok(all1.filter(func(x): return x["sev"] == "FAIL").size() <= all0.filter(func(x): return x["sev"] == "FAIL").size(), "    no more must-fix than before (full re-check)")
				ok(var_to_str(all1) == var_to_str(r["after"]), "    the fix's own after-list == a full re-check (%d findings)" % all1.size())
				kept[f["rule"]] = true
			else:
				ok(JSON.stringify(S.cards) == cards0, "  PUT BACK %s at %.2f s [%.1f s] (cards byte-identical): %s" % [f["rule"], f["t"], ms / 1000.0, r["msg"]])
				putback += 1
			ok(S.cards.map(func(c): return c["name"]) == names, "    cards kept: %d, same names and order" % S.cards.size())
			print("    whole check: %d findings (%d FAIL) -> %d (%d FAIL)" % [all0.size(), all0.filter(func(x): return x["sev"] == "FAIL").size(), all1.size(), all1.filter(func(x): return x["sev"] == "FAIL").size()])
	for r in ["TIP SPEED", "HITCH", "HEAD QUIET"]:
		ok(kept.has(r), "a %s fix was KEPT on a real scene" % r)
	ok(putback > 0, "the put-back path ran on a real scene (%d times): the guard can refuse" % putback)
	print("FIX TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
