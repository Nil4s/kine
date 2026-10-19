## godot --headless --path . -s tests/balance_test.gd     (GATES W3, UPGRADES #63)
## BALANCE: the centre of mass over the feet. Checked against what does not come from the model: the masses sum to
## 100; standing, the COM is 53-58% of his height up (the anthropometric range) and over the middle of his feet; the
## polygon distance on a unit square; the rule on series built by hand (the run length, one foot down); a lean that
## moves the COM forward step by step until it is past the toes, which CHECK then finds, the frames named; and the
## shipped scenes' base rate pinned (none: bo_spin's opening stance is 2.0 cm past the edge, under the bar).
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func sm(margins: Array, down: Array) -> Dictionary:
	var t := []
	for i in margins.size():
		t.append(i / Rulebook.FPS)
	return {"t": t, "balance": margins, "both_down": down}


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	var tot := 0.0
	for k in Balance.MASS:
		tot += Balance.MASS[k]
	ok(absf(tot - 100.0) < 1e-6 and Balance.MASS.size() == 17, "1 de Leva's shares over 17 parts sum to %.3f %%" % tot)

	var r := Balance.read(B)
	var hc: Array = B.cap("head")
	var tall: float = (hc[1] as Vector3).y + float(B.rad["head"])
	var frac: float = r["com"].y / tall
	ok(frac > 0.53 and frac < 0.58, "2 standing: the COM is %.1f%% of his height up (%.3f of %.3f m; people: 53-58%%)" % [frac * 100.0, r["com"].y, tall])
	ok(r["down"].size() == 2 and r["margin"] > 0.04 and absf(r["com"].x) < 1e-3,
		"3 standing: both feet down, the COM %.1f cm inside the edge, on the middle line (x %.4f)" % [r["margin"] * 100.0, r["com"].x])

	var sq := Balance.hull(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(0.5, 0.5)]))
	ok(sq.size() == 4 and absf(Balance.signed_dist(sq, Vector2(0.5, 0.5)) - 0.5) < 1e-6 and absf(Balance.signed_dist(sq, Vector2(1.25, 0.5)) + 0.25) < 1e-6
		and absf(Balance.signed_dist(sq, Vector2(0.9, 0.2)) - 0.1) < 1e-6, "4 the unit square: the inner point dropped; the centre +0.5, a point 0.25 outside -0.25, near an edge +0.1")

	var five := [0.05, -0.05, -0.05, -0.05, -0.05, -0.05, 0.05]
	var six := [0.05, -0.05, -0.05, -0.06, -0.05, -0.05, -0.05, 0.05]
	ok(Rulebook.rule_balance(sm(five, five.map(func(_x): return true))).is_empty(), "5 5 frames past (under 0.1 s): momentum, no finding")
	var f6 := Rulebook.rule_balance(sm(six, six.map(func(_x): return true)))
	ok(f6.size() == 1 and absf(f6[0]["v"] - 0.06) < 1e-9 and absf(f6[0]["t"] - 3 / 60.0) < 1e-9 and "6.0 cm" in f6[0]["msg"],
		"6 6 frames past: one finding at its worst (6.0 cm, frame 3): '%s'" % (f6[0]["msg"].left(110) if f6.size() > 0 else "nothing"))
	var one_foot := six.map(func(_x): return false)
	ok(Rulebook.rule_balance(sm(six, one_foot)).is_empty(), "7 the same with one foot off the floor (mid-step): not graded")

	# a lean past the toes: the hips 34 cm forward (12 down, the knees bend) over feet PLANTED where he stood (the scene's own planted feet,
	# Body.plant re-solves the legs). (Bending the trunk alone can't: the hips stay, the COM got 12 cm forward, measured)
	var keep := B.state()
	var S := Scene.new()
	S.name = "zz_lean"
	S.add("stand", B.to_dict())
	B.offset = Vector3(0.0, -0.12, 0.34)
	B.fk()
	S.add("lean", B.to_dict())
	B.set_state(keep)
	S.cards[1]["hold"] = 0.5
	S.cards[1]["plant"] = ["_l", "_r"]
	var t1: float = S.times()[1][1]   # the lean arrives
	var zs := []
	var ms := []
	var dn := true
	for k in 7:
		S.apply(B, t1 * k / 6.0)
		var b := Balance.read(B)
		zs.append(b["com"].z)
		ms.append(b["margin"])
		dn = dn and b["down"].size() == 2
	var up: bool = zs[-1] > zs[0] + 0.15   # never back, and well forward in all (the card before holds: equal frames)
	for k in range(1, zs.size()):
		up = up and zs[k] >= zs[k - 1] - 1e-6
	print("     through the move, COM forward (m): %s; margin: %s" % [zs.map(func(z): return snappedf(z, 0.001)), ms.map(func(x): return snappedf(x, 0.001))])
	ok(up and dn and ms[0] > 0.0 and ms[-1] < -0.03, "8 hips forward over planted feet: the COM goes forward every step, both feet down throughout, from inside (%.3f) to past the toes (%.3f)" % [ms[0], ms[-1]])
	var fl := Rulebook.check(S, B).filter(func(x): return x["rule"] == "BALANCE")
	B.set_state(keep)
	ok(fl.size() == 1 and fl[0]["card"] == 1 and "with both feet down" in fl[0]["msg"], "9 that scene: CHECK finds it once, on the lean: '%s'" % (fl[0]["msg"].left(120) if fl.size() > 0 else "nothing"))

	# the shipped scenes: the base rate, pinned
	var hits := {}
	var d := DirAccess.open("res://scenes")
	for fn in d.get_files():
		if not fn.ends_with(".json"):
			continue
		var jd: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/" + fn))
		if not (jd is Dictionary) or not (jd as Dictionary).has("cards"):
			continue   # not a scene file (a pose or an empty file): nothing to grade
		var Sc := Scene.new()
		Sc.from_dict(jd)
		var n := Rulebook.check(Sc, B).filter(func(x): return x["rule"] == "BALANCE")
		if n.size() > 0:
			hits[fn] = n.map(func(x): return snappedf(x["t"], 0.01))
	B.set_state(keep)
	# was "only bo_spin, once: its opening stance" (3.8 cm past the edge). 149c083 (foot twist = subtalar roll, merged 97d8598) turns bo_spin's
	# twisted feet about the right axis and the opening margin is 2.0 cm, under the 3 cm bar: no shipped scene has a BALANCE finding now.
	ok(hits.is_empty(), "10 the shipped scenes: none has a BALANCE finding (bo_spin's opening stance is 2.0 cm past the edge, under the 3 cm bar) (%s)" % hits)
	var Sb := Scene.new()
	Sb.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/bo_spin.json")))
	var smb := Rulebook.sample(Sb, B)
	var fb := Rulebook.rule_balance(smb)
	var deep := 0.0
	for i in smb["balance"].size():
		if smb["both_down"][i]:
			deep = maxf(deep, -smb["balance"][i])
	B.set_state(keep)
	ok(fb.is_empty() and absf(smb["balance"][0] + 0.020) < 0.002 and bool(smb["both_down"][0]) and deep > 0.1,
		"11 bo_spin's opening stance is %.1f cm past the edge with both feet down (under the 3 cm bar, no finding); its deepest, %.1f cm, is too short to report" % [
		-smb["balance"][0] * 100.0, deep * 100.0])
	print("BALANCE: %d failed" % fails)
	quit(1 if fails > 0 else 0)
