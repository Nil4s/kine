## godot --headless --path . -s tests/plant_all_test.gd     (round 43, GATES YY2)
## PLANT EVERY SLIDING FOOT: Fixer.plant_all plants all of Check's FOOT SLIDE findings at once. Fixture: a stand whose
## whole body creeps 15 cm forward over 2 s (both feet skate, slowly enough to read as standing). Bars: Check finds the
## slides first (> 2.5 cm); after: 0 FOOT SLIDE findings and each ball moves < 1 cm over the scene (plant_edges' pinned-foot bar); kept = true; a
## clean scene (the same stand, no creep) keeps nothing and leaves the cards byte for byte; the fixture's cards keep
## their count, names and poses (only "plant" lists are added).
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func ball_travel(S: Scene, B: Body) -> float:
	var worst := 0.0
	for sd in ["_l", "_r"]:
		S.apply(B, 0.0)
		var p0: Vector3 = B.P["ball" + sd]
		var k := 0
		while k / 30.0 <= S.length():
			S.apply(B, k / 30.0)
			var d: Vector3 = (B.P["ball" + sd] as Vector3) - p0
			worst = maxf(worst, Vector2(d.x, d.z).length())
			k += 1
	return worst


func creep(B: Body, dz: float) -> Scene:
	var keep := B.state()
	var S := Scene.new()
	S.name = "zz_creep"
	S.add("stand", B.to_dict())
	B.offset.z += dz
	B.fk()
	S.add("crept", B.to_dict())
	B.set_state(keep)
	S.cards[1]["move"] = 2.0
	S.cards[1]["hold"] = 0.5
	return S


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	var S := creep(B, 0.15)
	var poses0 := JSON.stringify(S.cards.map(func(c): return c["pose"]))
	var tr0 := ball_travel(S, B)
	var r := Fixer.plant_all(S, B)
	var tr1 := ball_travel(S, B)
	ok(r["n0"] >= 1 and r["worst0"] > 0.025, "1 the fixture: Check finds %d FOOT SLIDE, the worst %.1f cm (bar > 2.5); the balls travel %.1f cm" % [r["n0"], r["worst0"] * 100.0, tr0 * 100.0])
	ok(r["kept"] and r["n1"] == 0, "2 after: kept %s, FOOT SLIDE %d -> %d: '%s'" % [r["kept"], r["n0"], r["n1"], r["msg"]])
	ok(tr1 < 0.01, "3 each ball moves %.2f mm over the scene (bar < 10: plant_edges' pinned-foot bar; the hips creep 15 cm over straight legs, at full reach)" % (tr1 * 1000.0))
	ok(JSON.stringify(S.cards.map(func(c): return c["pose"])) == poses0 and S.cards.size() == 2, "4 the cards' poses untouched (only plant lists added: %s)" % str(S.cards.map(func(c): return c.get("plant", []))))
	var C := creep(B, 0.0)
	var c0 := JSON.stringify(C.cards)
	var rc := Fixer.plant_all(C, B)
	ok(not rc["kept"] and rc["n0"] == 0 and JSON.stringify(C.cards) == c0, "5 a clean stand: nothing kept, cards byte for byte: '%s'" % rc["msg"])
	print("PLANT ALL TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
