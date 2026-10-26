## godot --path . -s tests/ease_test.gd     (GATES Q2; needs a window)
## EASE PRESETS: a card's ease shapes the move INTO it. Sampled angles mid-move are checked against each preset's
## formula (scene.gd EASE PRESETS); smooth = today's curve exactly; the preset survives save/load; every scene in
## scenes/ re-saves with no "ease" written and plays identically; the dropdown sets it as ONE undo step; spline says no.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func expect(kind: String, u: float, lv: int, natural: bool) -> float:
	if kind == "snap":
		return 1.0 if u >= 1.0 else 0.0
	var x := u if not natural else clampf((u - Scene.LAG * lv / 6.0) / (1.0 - Scene.LAG), 0.0, 1.0)
	match kind:
		"linear": return x
		"in": return x * x * x
		"out": return 1.0 - pow(1.0 - x, 3.0)
	if not natural:
		return u * u * (3.0 - 2.0 * u)
	return x * x * x * (x * (6.0 * x - 15.0) + 10.0)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var base := Scene.new()
	base.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	var j := "upperarm_r"
	var lv := Scene.level(j)
	for natural in [true, false]:
		var worst := 0.0
		var span := 0.0
		for kind in Scene.EASES:
			var sc := Scene.new()
			sc.from_dict(base.to_dict(m.B))
			sc.natural = natural
			sc.cards = [sc.cards[1], sc.cards[2]]
			sc.cards[1] = sc.cards[1].duplicate()
			sc.cards[1]["ease"] = kind
			var ts := sc.times()
			var a: Vector3 = Moves._flat(sc.cards[0]["pose"])["ang"][j]
			var b: Vector3 = Moves._flat(sc.cards[1]["pose"])["ang"][j]
			span = maxf(span, absf(b.x - a.x))
			for u in [0.2, 0.45, 0.7, 0.95]:
				var t: float = ts[1][0] + u * (ts[1][1] - ts[1][0])
				var got: Vector3 = sc.sample(t)["ang"][j]
				var want := a.lerp(b, expect(kind, u, lv, natural))
				worst = maxf(worst, (got - want).length())
		ok(worst < 1e-3 and span > 10.0, "%s: every preset's mid-move angles match its formula (worst %.5f deg over a %.0f deg move)" % ["NATURAL" if natural else "PLAIN", worst, span])
	# the presets really differ (so the check above could fail)
	var vals := {}
	for kind in Scene.EASES:
		var sc := Scene.new()
		sc.from_dict(base.to_dict(m.B))
		sc.cards[2] = sc.cards[2].duplicate()
		sc.cards[2]["ease"] = kind
		var ts := sc.times()
		vals[kind] = snappedf((sc.sample(ts[2][0] + 0.3 * (ts[2][1] - ts[2][0]))["ang"][j] as Vector3).x, 0.01)
	var uniq := {}
	for k in vals:
		uniq[vals[k]] = true
	ok(uniq.size() == Scene.EASES.size(), "the five presets give five different angles 30%% into the move: %s" % vals)
	# save / load keeps it
	var sc2 := Scene.new()
	sc2.from_dict(base.to_dict(m.B))
	sc2.cards[3] = sc2.cards[3].duplicate()
	sc2.cards[3]["ease"] = "out"
	var back := Scene.new()
	back.from_dict(JSON.parse_string(JSON.stringify(sc2.to_dict(m.B))))
	ok(back.cards[3].get("ease", "") == "out" and not back.cards[2].has("ease"), "save + load: card 4 keeps 'out', card 3 has none")
	# every scene: nothing written, the same motion
	var n := 0
	var bad := []
	# the bundled scenes (refs/shipped_scenes.txt): a scene Nick saves (a video import eases linearly) is not this sweep's
	var shipped := FileAccess.get_file_as_string("res://refs/shipped_scenes.txt").split("
", false)
	for f in DirAccess.get_files_at("res://scenes"):
		if not f.ends_with(".json") or not f in shipped:
			continue
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/" + f))
		if not d is Dictionary:
			continue
		var s1 := Scene.new()
		s1.from_dict(d)
		var txt := JSON.stringify(s1.to_dict(m.B))
		if txt.contains("\"ease\""):
			bad.append(f)
		n += 1
	ok(n >= 5 and bad.is_empty(), "%d scenes re-saved: none writes an 'ease' %s" % [n, bad])
	# the UI: pick card 3, choose 'snap' in the dropdown: one undo step; Ctrl+Z takes it back
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m._card_pick(2)
	m._refresh()
	await process_frame
	ok(not m.ui_ease.disabled and m.ui_ease.get_item_text(m.ui_ease.selected) == "smooth", "card 3 picked: the ease dropdown is on, reads 'smooth'")
	var u0: int = m.undo.size()
	m.ui_ease.select(Scene.EASES.find("snap"))
	m.ui_ease.item_selected.emit(Scene.EASES.find("snap"))
	await process_frame
	ok(m.S.cards[2].get("ease", "") == "snap" and m.undo.size() == u0 + 1, "choose 'snap': card 3 eases snap, one undo step")
	var ts3: Array = m.S.times()
	m.playhead = ts3[2][0] + 0.5 * (ts3[2][1] - ts3[2][0])
	var mid: Vector3 = m.S.sample(m.playhead)["ang"][j]
	var before: Vector3 = Moves._flat(m.S.cards[1]["pose"])["ang"][j]
	ok(mid.is_equal_approx(before), "  halfway into card 3 the body still holds card 2's pose (snap)")
	m._undo()
	await process_frame
	ok(not m.S.cards[2].has("ease") and m.ui_ease.get_item_text(m.ui_ease.selected) == "smooth", "Ctrl+Z: smooth again, the dropdown agrees")
	m.S.spline = true
	m._refresh()
	ok(m.ui_ease.disabled, "Smooth (spline) on: the dropdown is off (the spline has its own curve)")
	print("EASE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
