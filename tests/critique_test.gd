## godot --headless --path . -s tests/critique_test.gd     (ROADMAP 11, "critique that points at frames")
## The animation-craft notes (scripts/critique.gd), all NOTE, each at a time:
##   1 ANTICIPATION: a swing with a pull-back 0.1-0.4 s before it passes; the same swing from rest is noted AT the swing's start
##   2 FOLLOW-THROUGH: a strike whose tip stops dead (a 0.1 s arrival) is noted; the same strike with a 0.3 s decelerating
##     arrival is not
##   3 EVEN TIMING: four cards of the same length are noted; four varied lengths are not
##   4 FLOATY, on hand-built series: a free fall at g passes; a hover in the air is noted; a fall that eases in is noted
## CONTROL (anti-vacuity): every scene must hold a fast move, else the rule passes by emptiness.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## the body with its right upper arm bent to b degrees (forward), as a pose dict; the body is reloaded after
func arm(B: Body, b: float) -> Dictionary:
	B.set_ang("upperarm_r", Vector3(b, 0, 0))
	B.fk()
	var d := B.to_dict()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return d


func rule(fs: Array, name: String) -> Array:
	return fs.filter(func(f): return f["rule"] == name)


## a series of frames for rule_floaty: the ankles are off the floor for the run [a, b), the centre of mass falls with the
## vertical acceleration acc(k) (m/s^2); integrated the way a body moves (v += a dt, y += v dt), so the second difference is a
func floaty_series(a0: int, a1: int, acc: Callable) -> Dictionary:
	var raw := []
	var y := 1.0
	var v := 0.0
	var dt := 1.0 / 60.0
	for k in 120:
		var air := k >= a0 and k < a1
		if air:
			v += float(acc.call(k)) * dt
			y += v * dt
		else:
			v = 0.0
		raw.append({"bal": {"com": Vector3(0, y, 0)}, "fy": 0.2 if air else 0.0})
	return {"_raw": raw}


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()

	# 1. ANTICIPATION: the same swing (rest -> 135 deg in 0.1 s), with and without a pull-back (-20 deg, 0.3 s) before it
	var P := Scene.new()
	P.name = "zz_pullback"
	P.add("rest", arm(B, 0.0))
	P.cards[0]["hold"] = 0.3
	P.add("pull", arm(B, -20.0))
	P.cards[1]["move"] = 0.3
	P.cards[1]["hold"] = 0.2
	P.add("swing", arm(B, 135.0))
	P.cards[2]["move"] = 0.1
	P.cards[2]["hold"] = 0.5
	var N := Scene.new()
	N.name = "zz_nopull"
	N.add("rest", arm(B, 0.0))
	N.cards[0]["hold"] = 0.8
	N.add("swing", arm(B, 135.0))
	N.cards[1]["move"] = 0.1
	N.cards[1]["hold"] = 0.5
	var sp := Rulebook.sample(P, B)
	var sn := Rulebook.sample(N, B)
	var pk_p := Rulebook.strikes(sp["tip"])
	var pk_n := Rulebook.strikes(sn["tip"])
	ok(pk_p.size() == 1 and pk_n.size() == 1,
		"CONTROL 1a both swings hold one fast move (tip peak %.1f / %.1f m/s)" % [
			sp["tip"].max(), sn["tip"].max()])
	var ap_p := rule(Critique.check(P, B, sp), "ANTICIPATION")
	ok(ap_p.is_empty(), "1 the swing with a pull-back 0.1-0.4 s before it: not noted (%d)" % ap_p.size())
	var ap_n := rule(Critique.check(N, B, sn), "ANTICIPATION")
	var t_swing: float = float(sn["t"][pk_n[0]["a"]])
	ok(ap_n.size() == 1 and absf(float(ap_n[0]["t"]) - t_swing) < 0.02,
		"2 the same swing from rest: noted at %.2f s, where the swing starts (%.2f s): %s" % [
			float(ap_n[0]["t"]) if ap_n.size() > 0 else -1.0, t_swing, ap_n[0]["msg"] if ap_n.size() > 0 else "none"])
	ok(ap_n.size() == 1 and "pull-back" in String(ap_n[0]["msg"]),
		"2b the note names the fix (a pull-back)")

	# 2. FOLLOW-THROUGH: a 0.1 s arrival (dead stop) noted, a 0.3 s decelerating arrival not
	var D := Scene.new()
	D.name = "zz_deadstop"
	D.add("rest", arm(B, 0.0))
	D.cards[0]["hold"] = 0.5
	D.add("hit", arm(B, 135.0))
	D.cards[1]["move"] = 0.1
	D.cards[1]["hold"] = 0.5
	var F := Scene.new()
	F.name = "zz_followthrough"
	F.add("rest", arm(B, 0.0))
	F.cards[0]["hold"] = 0.5
	F.add("hit", arm(B, 135.0))
	F.cards[1]["move"] = 0.3
	F.cards[1]["hold"] = 0.5
	var sd := Rulebook.sample(D, B)
	var sf := Rulebook.sample(F, B)
	ok(Rulebook.strikes(sd["tip"]).size() == 1 and Rulebook.strikes(sf["tip"]).size() == 1,
		"CONTROL 2a both strikes hold one fast move (tip peak %.1f / %.1f m/s)" % [sd["tip"].max(), sf["tip"].max()])
	var st_d := rule(Critique.check(D, B, sd), "FOLLOW-THROUGH")
	var b_d: int = Rulebook.strikes(sd["tip"])[0]["b"]
	ok(st_d.size() == 1 and absf(float(st_d[0]["t"]) - float(sd["t"][b_d])) < 0.02,
		"3 the 0.1 s arrival is a dead stop: noted at %.2f s: %s" % [
			float(st_d[0]["t"]) if st_d.size() > 0 else -1.0, st_d[0]["msg"] if st_d.size() > 0 else "none"])
	var st_f := rule(Critique.check(F, B, sf), "FOLLOW-THROUGH")
	ok(st_f.is_empty(), "4 the 0.3 s decelerating follow-through: not noted (%d)" % st_f.size())

	# 3. EVEN TIMING: five cards, each 0.4 s long (0.2 move + 0.2 hold) against five with varied lengths
	var E := Scene.new()
	E.name = "zz_even"
	E.add("start", arm(B, 0.0))
	E.cards[0]["hold"] = 0.2
	var angs := [40.0, -20.0, 60.0, 10.0]
	for a in angs:
		E.add("beat", arm(B, a))
		E.cards[E.cards.size() - 1]["move"] = 0.2
		E.cards[E.cards.size() - 1]["hold"] = 0.2
	var V := Scene.new()
	V.name = "zz_varied"
	V.add("start", arm(B, 0.0))
	V.cards[0]["hold"] = 0.2
	var moves := [0.1, 0.4, 0.2, 0.6]
	var vangs := [40.0, -20.0, 60.0, 10.0]
	for k in 4:
		V.add("beat", arm(B, vangs[k]))
		V.cards[V.cards.size() - 1]["move"] = moves[k]
		V.cards[V.cards.size() - 1]["hold"] = 0.2
	var ev_e := rule(Critique.check(E, B), "EVEN TIMING")
	ok(ev_e.size() == 1 and absf(float(ev_e[0]["t"]) - 0.2) < 0.01,
		"5 five cards of 0.4 s: noted at the first beat (%.2f s): %s" % [
			float(ev_e[0]["t"]) if ev_e.size() > 0 else -1.0, ev_e[0]["msg"] if ev_e.size() > 0 else "none"])
	var ev_v := rule(Critique.check(V, B), "EVEN TIMING")
	ok(ev_v.is_empty(), "6 the same five cards with lengths 0.3 / 0.6 / 0.4 / 0.8 s: not noted (%d)" % ev_v.size())

	# 4. FLOATY on series (the centre of mass in the air; g = Scene.G): a fall at g passes, a hover is noted, an ease-in is noted
	var fall := floaty_series(30, 90, func(_k): return -Scene.G)
	ok(rule(Critique.rule_floaty(fall), "FLOATY").is_empty(), "7 a free fall at g in the air: not noted")
	var hover := floaty_series(30, 90, func(_k): return 0.0)
	var hv := rule(Critique.rule_floaty(hover), "FLOATY")
	ok(hv.size() == 1 and absf(float(hv[0]["t"]) - 0.5) < 0.02,
		"8 a hover in the air (no fall at all): noted at %.2f s: %s" % [float(hv[0]["t"]) if hv.size() > 0 else -1.0, hv[0]["msg"] if hv.size() > 0 else "none"])
	var ease := floaty_series(30, 90, func(k): return -0.1 * Scene.G if k < 42 else -Scene.G)
	var eu := rule(Critique.rule_floaty(ease), "FLOATY")
	ok(eu.size() == 1 and "eases in" in String(eu[0]["msg"]),
		"9 a fall that eases in (0.2 s at a tenth of g, then g): noted as an ease-in: %s" % (eu[0]["msg"] if eu.size() > 0 else "none"))

	print("CRITIQUE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
