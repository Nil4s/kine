## godot --headless --path . -s tests/jump_test.gd     (GATES VV1, VV2; headless is fine)
## AIRBORNE CARDS. A countermovement jump: stand, dip (take-off), legs reaching in the air (air), land in a crouch,
## stand. The flight is the take-off card's leave to the landing card's arrival, T = 0.571 s. REAL PEOPLE: a flight of
## T means a jump of g T^2 / 8 (Bosco; Asmussen & Bonde-Petersen): 0.571 s -> 0.40 m, about a recreational adult's
## countermovement jump (40 +- 11 cm on a force plate). Checked by numbers: the CoM's apex over their take-off height,
## the CoM on the parabola at 9 times, both soles off the floor mid-flight, on the floor at the landing, a scene
## without "air" unchanged, save/load and mirror keep it.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func legs(B: Body, thigh: float, calf: float) -> Dictionary:
	for sd in ["_l", "_r"]:
		B.set_ang("thigh" + sd, Vector3(thigh, 0, 0))
		B.set_ang("calf" + sd, Vector3(calf, 0, 0))
	B.fk()
	var d := B.to_dict()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return d


func jump() -> Scene:
	var B := body()
	var S := Scene.new()
	S.name = "zz_jump"
	S.add("stand", B.to_dict())
	S.add("dip", legs(B, 50, 90))
	S.add("air", legs(B, 10, 20))
	S.add("land", legs(B, 50, 90))
	S.add("stand", B.to_dict())
	var mv := [0.3, 0.3, 0.2855, 0.2855, 0.4]
	var hd := [0.1, 0.05, 0.0, 0.1, 0.2]
	for i in 5:
		S.cards[i]["move"] = mv[i]
		S.cards[i]["hold"] = hd[i]
	S.cards[2]["air"] = true
	return S


## the lowest point of either sole (the body's own measure, the one grounding puts on the floor)
func sole(B: Body) -> float:
	return B.sole_low()


func _init() -> void:
	var S := jump()
	var B := body()
	var fl := S.flights()
	ok(fl.size() == 1 and int(fl[0]["k"]) == 1 and int(fl[0]["l"]) == 3, "one flight, from the dip card to the landing card %s" % [fl.map(func(f): return [f["k"], f["l"]])])
	if fl.size() != 1:
		print("JUMP TEST FAIL %d" % fails)
		TestFiles.cleanup()
		quit(fails)
		return
	var t0: float = fl[0]["t0"]
	var t1: float = fl[0]["t1"]
	var T := t1 - t0
	S.apply(B, t0)
	var y0: float = Balance.com(B).y   # round 41: the CENTRE OF MASS rides the parabola, not the pelvis
	S.apply(B, t1)
	var y1: float = Balance.com(B).y
	S.apply(B, (t0 + t1) / 2.0)
	var apex: float = Balance.com(B).y
	var want := Scene.G * T * T / 8.0
	print("REFERENCE vs OURS: flight %.3f s -> people jump g T^2/8 = %.3f m (recreational CMJ 0.40 +- 0.11) | the CoM rises %.3f m over the take-off height (take-off %.3f, landing %.3f)" % [T, want, apex - (y0 + y1) / 2.0, y0, y1])
	ok(absf(apex - (y0 + y1) / 2.0 - want) < 0.01, "CoM apex = g T^2 / 8 over the take-off height (1 cm)")
	var worst := 0.0
	for k in range(1, 10):
		var t := t0 + T * k / 10.0
		S.apply(B, t)
		var par := lerpf(y0, y1, k / 10.0) + Scene.G / 2.0 * (t - t0) * (t1 - t)
		worst = maxf(worst, absf(Balance.com(B).y - par))
	ok(worst < 0.002, "the CoM on the parabola at 9 times (worst %.4f m)" % worst)
	S.apply(B, (t0 + t1) / 2.0)
	ok(sole(B) > 0.20, "mid-flight both feet are off the floor (lowest sole %.3f m)" % sole(B))
	S.apply(B, t1)
	ok(absf(sole(B)) < 0.005, "at the landing the feet are on the floor (lowest %.3f m)" % sole(B))
	# no air card: exactly the old playback (the flight code must not touch it)
	var P := jump()
	P.cards[2].erase("air")
	var Q := jump()
	Q.cards[2].erase("air")
	ok(P.flights().is_empty(), "no air card: no flight")
	var B1 := body()
	P.apply(B1, (t0 + t1) / 2.0)
	ok(absf(sole(B1)) < 0.005, "  and the body stays on the floor then (lowest %.3f m)" % sole(B1))
	# save / load and mirror keep it
	var D := S.to_dict(body())
	ok(D["cards"][2].get("air", false) == true and not D["cards"][1].has("air"), "saved only where on")
	var R := Scene.new()
	R.from_dict(D)
	ok(R.flights().size() == 1, "loaded back: still one flight")
	var M := S.clone()
	var mc := Scene.mirror_card(M.cards[2], body())
	ok(mc.get("air", false) == true, "mirror keeps it")
	# VV2 THE JUMP RULE: the good jump against real jumps, then one bad thing at a time
	var j: Array = Rulebook.jumps(S, body())
	print("REFERENCE vs OURS (JUMP): height people 0.40 +- 0.11 m, bar %.2f -> ours %.2f | dip people ~90 deg, bar %.0f -> ours %.0f | landing knee people soft 117 / stiff 77, bar %.0f -> ours %.0f" % [
		Rulebook.JUMP_HIGH, j[0]["h"], Rulebook.JUMP_DIP, j[0]["dip"], Rulebook.JUMP_LAND, j[0]["land"]])
	var fs := Rulebook.check(S, body())
	ok(fs.is_empty(), "the good jump: Check finds nothing at all %s" % [fs.map(func(f): return "%s: %s" % [f["rule"], String(f["msg"]).left(90)])])
	var hi := jump()
	hi.cards[2]["move"] = 0.5
	hi.cards[3]["move"] = 0.5
	var w := Rulebook.check(hi, body()).filter(func(f): return f["rule"] == "JUMP")
	ok(w.size() == 1 and String(w[0]["msg"]).contains("1.00 s in the air means a 123 cm jump"), "a 1.0 s flight: WARN JUMP '%s'" % (String(w[0]["msg"]) if not w.is_empty() else "-"))
	var stiff := jump()
	stiff.cards[3]["pose"] = stiff.cards[4]["pose"]
	w = Rulebook.check(stiff, body()).filter(func(f): return f["rule"] == "JUMP")
	ok(w.size() == 1 and String(w[0]["msg"]).contains("a stiff landing") and not String(w[0]["msg"]).contains("no dip"), "straight legs at the landing: WARN stiff '%s'" % (String(w[0]["msg"]) if not w.is_empty() else "-"))
	var nodip := jump()
	nodip.cards[1]["pose"] = nodip.cards[0]["pose"]
	w = Rulebook.check(nodip, body()).filter(func(f): return f["rule"] == "JUMP")
	ok(w.size() == 1 and String(w[0]["msg"]).contains("no dip") and not String(w[0]["msg"]).contains("stiff"), "straight legs before take-off: WARN no dip '%s'" % (String(w[0]["msg"]) if not w.is_empty() else "-"))
	var none := jump()
	none.cards[2].erase("air")
	ok(Rulebook.check(none, body()).filter(func(f): return f["rule"] == "JUMP").is_empty(), "no air card: the rule says nothing")
	print("JUMP TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
