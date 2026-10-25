## godot --headless --path . -s tests/jump_physics_test.gd     (GATES WW10, UPGRADES_300 #311 + #312; headless is fine)
## MOMENTUM (#311): in a flight the CENTRE OF MASS (Balance.com, de Leva masses), not the pelvis, rides the parabola.
## Arms thrown up in the air move the CoM, so the pelvis must sit off the parabola by that shift.
## LANDING vs HEIGHT (#312): the stiff-landing bar grows with the fall. REAL PEOPLE: DeVita & Skelly 1992 (PMID 1548984)
## 59 cm drop: stiff 77 / soft 117 deg knee flexion; Rosen 2015 (PMID 26665034) 40 cm drop jump: 82.5 +- 9.0 deg.
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


func pose(thigh: float, calf: float, arm: float) -> Dictionary:
	var B := body()
	for sd in ["_l", "_r"]:
		B.set_ang("thigh" + sd, Vector3(thigh, 0, 0))
		B.set_ang("calf" + sd, Vector3(calf, 0, 0))
		B.set_ang("upperarm" + sd, Vector3(arm, 0, 0))
	B.fk()
	return B.to_dict()


## dip / air / land cards; the air card throws the arms up by arm degrees; mv = the move time into the air card
func jump(arm: float, mv: float, land_thigh: float, land_calf: float) -> Scene:
	var B := body()
	var S := Scene.new()
	S.name = "zz_jphys"
	S.add("stand", B.to_dict())
	S.add("dip", pose(50, 90, 0))
	S.add("air", pose(10, 20, arm))
	S.add("land", pose(land_thigh, land_calf, 0))
	S.add("stand", B.to_dict())
	var mvs := [0.3, 0.3, mv, mv, 0.4]
	var hd := [0.1, 0.05, 0.0, 0.1, 0.2]
	for i in 5:
		S.cards[i]["move"] = mvs[i]
		S.cards[i]["hold"] = hd[i]
	S.cards[2]["air"] = true
	return S


func _init() -> void:
	# 1. MOMENTUM: arms swing up in the air
	var S := jump(150.0, 0.2855, 50, 90)
	var fl := S.flights()
	if fl.size() != 1:
		print("JUMP PHYSICS TEST FAIL (no flight)")
		TestFiles.cleanup()
		quit(1)
		return
	var B := body()
	var t0: float = fl[0]["t0"]
	var t1: float = fl[0]["t1"]
	var T := t1 - t0
	S.apply(B, t0)
	var c0 := Balance.com(B).y
	var p0 := (B.P["pelvis"] as Vector3).y
	S.apply(B, t1)
	var c1 := Balance.com(B).y
	var p1 := (B.P["pelvis"] as Vector3).y
	var worst := 0.0
	var pel := 0.0
	for k in range(1, 10):
		var t := t0 + T * k / 10.0
		S.apply(B, t)
		var par := lerpf(c0, c1, k / 10.0) + Scene.G / 2.0 * (t - t0) * (t1 - t)
		worst = maxf(worst, absf(Balance.com(B).y - par))
		var ppar := lerpf(p0, p1, k / 10.0) + Scene.G / 2.0 * (t - t0) * (t1 - t)
		pel = maxf(pel, absf((B.P["pelvis"] as Vector3).y - ppar))
	print("REFERENCE vs OURS: free fall y'' = -g, the CoM on the parabola: worst CoM error %.5f m (bar 0.002) | the pelvis is off it by up to %.4f m (the arms' and legs' shift)" % [worst, pel])
	ok(worst < 0.002, "arms up in the air: the CoM on the parabola at 9 times (worst %.5f m, bar 0.002)" % worst)
	ok(pel > 0.01, "  and the pelvis is NOT on it: off by %.4f m (bar > 0.01)" % pel)
	# old scene without arms in the air still has a flight, and a scene with no air card is untouched
	var N := jump(0.0, 0.2855, 50, 90)
	N.cards[2].erase("air")
	var Bn := body()
	N.apply(Bn, (t0 + t1) / 2.0)
	ok(absf(Bn.sole_low()) < 0.005, "no air card: the body stays on the floor (lowest sole %.4f m)" % Bn.sole_low())
	# 2. LANDING vs HEIGHT
	print("REFERENCE vs OURS: stiff bar at 0.40 m %.0f (old bar 45) | 0.50 m %.0f | 0.59 m %.0f (DeVita stiff 77) | 0.78 m %.0f | capped %.0f" % [
		Rulebook.land_bar(0.40), Rulebook.land_bar(0.50), Rulebook.land_bar(0.59), Rulebook.land_bar(0.78), Rulebook.land_bar(5.0)])
	ok(Rulebook.land_bar(0.30) == Rulebook.JUMP_LAND and absf(Rulebook.land_bar(0.59) - 77.0) < 0.01, "the bar: 45 up to 0.40 m, 77 at 0.59 m")
	ok(Rulebook.land_bar(0.78) > Rulebook.land_bar(0.5) and Rulebook.land_bar(5.0) <= Rulebook.JUMP_LAND_MAX, "the bar grows with the fall and is capped")
	var hi := jump(0.0, 0.4, 50, 90)   # 0.8 s in the air, 0.78 m, 94 deg landing
	var jh: Array = Rulebook.jumps(hi, body())
	var lo := jump(0.0, 0.2855, 50, 90)
	var jl: Array = Rulebook.jumps(lo, body())
	print("high jump: T %.2f s, %.2f m, landing bend %.0f deg | normal: T %.2f s, %.2f m, landing %.0f" % [jh[0]["T"], jh[0]["h"], jh[0]["land"], jl[0]["T"], jl[0]["h"], jl[0]["land"]])
	var w := Rulebook.check(hi, body()).filter(func(f): return f["rule"] == "JUMP")
	var msg := String(w[0]["msg"]) if not w.is_empty() else "-"
	ok(w.size() == 1 and msg.contains("a stiff landing from %.0f cm" % (float(jh[0]["h"]) * 100.0)) and msg.contains("%.0f°" % jh[0]["land"]), "a high jump with a 94 deg landing: WARN names the height and the bend '%s'" % msg)
	ok(Rulebook.check(lo, body()).filter(func(f): return f["rule"] == "JUMP").is_empty(), "the same 94 deg landing at 0.57 s: silent")
	print("JUMP PHYSICS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
