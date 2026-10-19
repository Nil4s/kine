## godot --headless --path . -s tests/feasible_test.gd     ("Is this clip physically possible?", scripts/feasible.gd)
## Bars (stated before measuring):
##  1 scenes/walk_bat.json (read only) -> PASS
##  2 a lean with the COM ~15 cm outside the feet for 0.5 s (feet planted) -> FIX, a FEASIBLE/TIPPING finding whose frames
##    lie inside the held lean, and none outside [lean start - 0.1 s, lean end + 0.1 s]
##  3 the jump (flight in the air) -> at least 10 airborne frames, no finding overlapping an airborne frame; and the same
##    flight with the COM lifted 1 m in mid-air (a hover) -> a FEASIBLE FLIGHT finding
##  4 a body that glides 10 cm sideways in 1 s with the feet planted -> a FEASIBLE SLIDE finding of 80-120 mm
##  5 the 1 cm lean on one leg that used to be a TIPPING MUST FIX -> no TIPPING finding (margin under the polygon's resolution)
##  6 Nick's scenes/*.json (read only): each verdict printed, not barred
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


func load_scene(path: String) -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
	return S


## stand, a card with the body shifted by off (held), stand again. one_leg: the left leg is lifted and only the right foot is
## planted, so shifting the body toward the left pushes the COM out past the one foot that carries it
func shifted(off: Vector3, hold: float, move: float, one_leg := false) -> Scene:
	var B := body()
	var S := Scene.new()
	S.name = "zz_shift"
	S.add("stand", B.to_dict())
	if one_leg:
		B.set_ang("thigh_l", Vector3(80, 0, 0))
		B.set_ang("calf_l", Vector3(100, 0, 0))
	B.offset = off
	B.fk()
	S.add("away", B.to_dict())
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	S.add("back", B.to_dict())
	S.cards[0]["hold"] = 0.3
	S.cards[1]["move"] = move
	S.cards[1]["hold"] = hold
	S.cards[2]["move"] = move
	if one_leg:
		S.cards[1]["plant"] = ["_r"]
	return S


func swing(ang: float) -> Scene:
	var B := body()
	var S := Scene.new()
	S.name = "zz_slide"
	S.add("stand", B.to_dict())
	B.set_ang("thigh_l", Vector3(ang, 0, 0))
	B.fk()
	S.add("away", B.to_dict())
	S.cards[1]["move"] = 1.0
	S.cards[1]["hold"] = 0.5
	return S


func _init() -> void:
	var B := body()
	# 1 walk_bat
	var W := load_scene("res://scenes/walk_bat.json")
	var rw := Feasible.check(W, B)
	print("     walk_bat: ", rw["verdict"], " ", (rw["findings"] as Array).map(func(f): return "%s %.2f %s" % [f["rule"], f["t"], String(f["msg"]).left(110)]))
	ok(rw["verdict"] == "PASS", "1 walk_bat: PASS")

	# 2 the lean: the offset whose COM is nearest 15 cm outside the planted feet
	var best := 0.0
	var bm := 9.0
	for k in 40:
		var x := 0.01 * k
		var T := shifted(Vector3(x, 0, 0), 0.5, 0.3, true)
		T.apply(B, T.times()[1][2] - 0.01)
		var m := float(Balance.read(B)["margin"])
		if m > -INF and absf(m + 0.15) < bm:
			bm = absf(m + 0.15)
			best = x
	var L := shifted(Vector3(best, 0, 0), 0.5, 0.3, true)
	var rl := Feasible.check(L, B)
	var tl: Array = L.times()
	var lean_a: float = tl[1][1]
	var lean_b: float = tl[1][2]
	print("     lean x=%.2f (margin err %.3f): %s %s" % [best, bm, rl["verdict"], (rl["findings"] as Array).map(func(f): return "%s %.2f-%.2f" % [f["rule"], f["t"], f.get("t1", 0.0)])])
	var inside := true
	var named := false
	for f in rl["findings"]:
		if f["rule"] == "TIPPING" or f["rule"] == "FEASIBLE BALANCE":
			named = true
			inside = inside and float(f["t"]) >= float(tl[1][0]) and float(f["t1"]) <= lean_b + 0.1
	ok(rl["verdict"] == "FIX" and named and inside, "2 15 cm outside for 0.5 s: FIX, naming frames inside the held lean [%.2f, %.2f] s" % [lean_a, lean_b])
	var msg := ""
	for f in rl["findings"]:
		msg += String(f["msg"])
	ok("frames " in msg, "2b the reason names the frames: %s" % msg.left(160))

	# 3 the jump
	var J := load_scene("res://templates/jump.json") if FileAccess.file_exists("res://templates/jump.json") else null
	if J == null or J.cards.size() < 2:
		J = null
	var rj := {}
	if J != null:
		rj = Feasible.check(J, B)
		var sm: Dictionary = rj["sm"]
		var air := 0
		var hit := 0
		for i in sm["n"]:
			if Feasible.airborne(sm, i):
				air += 1
				for f in rj["findings"]:
					if float(sm["t"][i]) >= float(f["t"]) - 1e-6 and float(sm["t"][i]) <= float(f.get("t1", f["t"])) + 1e-6 and f["rule"] != "FEASIBLE SLIDE":
						hit += 1
		print("     jump: %s, %d airborne frames, %d findings overlapping them: %s" % [rj["verdict"], air, hit, (rj["findings"] as Array).map(func(f): return "%s %.2f %s" % [f["rule"], f["t"], String(f["msg"]).left(90)])])
		ok(air >= 10 and hit == 0, "3 jump: %d airborne frames, none flagged" % air)
		# a hover: lift the mid-air frames' COM by editing the sample (the rule reads the sample)
		var sm2: Dictionary = sm.duplicate(true)
		for i in sm2["n"]:
			if Feasible.airborne(sm2, i):
				var c: Vector3 = sm2["com"][i]
				sm2["com"][i] = c + Vector3(0, 0.5 if i % 2 == 0 else 0.0, 0)
		var fl := Feasible.rule_flight(sm2, 30)
		ok(fl.size() >= 1, "3b a hovering COM in the air: FEASIBLE FLIGHT (%d)" % fl.size())
	else:
		ok(false, "3 templates/jump.json is missing")

	# 4 the slide
	# the left thigh swung so the planted ball creeps forward ~10 cm over 1 s (the engine pins the feet when the whole body shifts,
	# so a slide has to come from the legs: the way real scenes slide between two cards' stances)
	var Sl: Scene = null
	var bd := 9.0
	for k in 25:
		var cand := swing(5.0 + 0.5 * k)
		cand.apply(B, 0.0)
		var z0 := float((B.P["ball_l"] as Vector3).z)
		cand.apply(B, cand.length())
		var d := absf(float((B.P["ball_l"] as Vector3).z) - z0 - 0.10)
		if d < bd and float((B.P["ball_l"] as Vector3).y) < 0.045:
			bd = d
			Sl = cand
	var rs := Feasible.check(Sl, B)
	var sl := (rs["findings"] as Array).filter(func(f): return f["rule"] == "FEASIBLE SLIDE")
	print("     slide: ", rs["verdict"], " ", sl.map(func(f): return "%.0f mm %s" % [float(f["v"]) * 1000.0, f["msg"]]))
	ok(sl.size() >= 1 and float(sl[0]["v"]) > 0.08 and float(sl[0]["v"]) < 0.12, "4 a 10 cm glide on planted feet: FEASIBLE SLIDE, %.0f mm" % (float(sl[0]["v"]) * 1000.0 if sl.size() > 0 else -1.0))

	# 5 the 1 cm lean: old TIPPING MUST FIX at margin -0.01
	var hl := {"t": [], "margin": [], "h": [], "down": [], "sup": [], "cv": []}
	for i in 90:
		hl["t"].append(i / 60.0)
		hl["margin"].append(-0.01)
		hl["h"].append(0.9)
		hl["down"].append(true)
		hl["sup"].append(false)
		hl["cv"].append(0.0)
	ok(HumanLimits.rule_tipping(hl).is_empty(), "5 COM 1 cm past the feet for 1.5 s: no TIPPING (resolution %.0f mm)" % (Balance.MARGIN_RES * 1000.0))
	for i in 90:
		hl["margin"][i] = -0.15
	ok(HumanLimits.rule_tipping(hl).size() == 1, "5b 15 cm past for 1.5 s still TIPPING")

	# 6 Nick's scenes
	var d := DirAccess.open("res://scenes")
	for fn in d.get_files():
		if fn.ends_with(".json"):
			var N := load_scene("res://scenes/" + fn)
			if N.cards.size() < 2:
				continue
			var rn := Feasible.check(N, B)
			print("     scene %-18s %-10s %s" % [fn, rn["verdict"], (rn["findings"] as Array).map(func(f): return "%s %.2f-%.2f" % [f["rule"].replace("FEASIBLE ", ""), f["t"], f.get("t1", 0.0)])])
	print("FEASIBLE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(1 if fails > 0 else 0)
