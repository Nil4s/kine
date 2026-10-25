## godot --headless --path . -s tests/inbetween_test.gd     (GATES WW3, UPGRADES #279 #280; headless is fine)
## PUSH / RELAX / BLEND (scripts/inbetween.gd). Blender's Pose Mode in-betweens (manual: animation/in_betweens.rst):
## push p + f (p - mid), relax p + f (mid - p), blend to rest / neighbour p + f (target - p), mid = the neighbours' mix.
## Pure math on a 3-card scene. The bar for every check is a number printed beside it.
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


## a pose dictionary with these joint angles on a straight body
func pose(a: Dictionary) -> Dictionary:
	var B := body()
	for j in a:
		B.set_ang(j, a[j])
	B.fk()
	return B.to_dict()


## 3 cards: thigh_l bend 0 / 30 / 40, spine_01 bend 0 / 10 / 14, lowerarm_r bend 0 / 130 / 0, head twist 0 / 8 / 0
func scene3() -> Scene:
	var S := Scene.new()
	S.name = "zz_inbetween"
	S.add("a", pose({}))
	S.add("b", pose({"thigh_l": Vector3(30, 0, 0), "spine_01": Vector3(10, 0, 0), "lowerarm_r": Vector3(130, 0, 0), "head": Vector3(0, 0, 8)}))
	S.add("c", pose({"thigh_l": Vector3(40, 0, 0), "spine_01": Vector3(14, 0, 0)}))
	return S


func at(S: Scene, k: int) -> Body:
	var B := body()
	B.from_dict(S.cards[k]["pose"])
	return B


func _init() -> void:
	var S := scene3()
	var f := Inbetween.FACTOR
	ok(absf(f - 0.25) < 1e-9, "default factor %.2f (bar 0.25)" % f)
	# PUSH twice on the middle card: thigh_l p=30, mid=(0+40)/2=20; p1 = 30 + .25 (30-20) = 32.5; p2 = 32.5 + .25 (32.5-20) = 35.625
	var B := at(S, 1)
	var r := Inbetween.run(B, S, 1, "push", f, [])
	ok(r["ok"], "push runs on the middle card")
	var t1: float = B.ang["thigh_l"].x
	print("     thigh_l after push 1: %.4f (predicted 32.5000)" % t1)
	ok(absf(t1 - 32.5) < 1e-4, "push 1: thigh_l 30 -> 32.5 within 1e-4 (off by %.6f)" % absf(t1 - 32.5))
	Inbetween.run(B, S, 1, "push", f, [])
	var t2: float = B.ang["thigh_l"].x
	ok(absf(t2 - 35.625) < 1e-4, "push 2: thigh_l -> 35.625 within 1e-4 (got %.4f)" % t2)
	var s2: float = B.ang["spine_01"].x   # mid 7, p 10: 10.75 then 10.75 + .25 (3.75) = 11.6875
	ok(absf(s2 - 11.6875) < 1e-4, "push 2: spine_01 10 -> 11.6875 within 1e-4 (got %.4f)" % s2)
	# RELAX converges toward mid: distance to mid shrinks by (1 - f) each press
	B = at(S, 1)
	var d0 := absf(B.ang["thigh_l"].x - 20.0)
	var prev := d0
	var shrink_ok := true
	for i in 6:
		Inbetween.run(B, S, 1, "relax", f, [])
		var d: float = absf(B.ang["thigh_l"].x - 20.0)
		if absf(d - prev * 0.75) > 1e-4:
			shrink_ok = false
		prev = d
	ok(shrink_ok, "relax x6: the distance to the in-between shrinks by exactly 0.75 each press (%.4f -> %.4f, bar %.4f)" % [d0, prev, d0 * pow(0.75, 6)])
	ok(absf(prev - d0 * pow(0.75, 6)) < 1e-3, "  and ends at 10 * 0.75^6 = %.4f deg from mid (got %.4f)" % [d0 * pow(0.75, 6), prev])
	# a limit: lowerarm_r bend p=130, neighbours 0 and 0, mid 0: push wants 162.5, the range ends at 145
	B = at(S, 1)
	var hi: float = B.lim["lowerarm_r"]["bend"].y
	r = Inbetween.run(B, S, 1, "push", f, [])
	var got: float = B.ang["lowerarm_r"].x
	print("     lowerarm_r bend: asked 162.5, limit %.1f, got %.4f" % [hi, got])
	ok(absf(got - hi) < 1e-4 and got <= hi, "at a limit it stops AT the limit (%.4f vs %.1f)" % [got, hi])
	var st: Array = r["stopped"].filter(func(e): return e["joint"] == "lowerarm_r" and e["axis"] == "bend")
	ok(st.size() == 1 and absf(float(st[0]["wanted"]) - 162.5) < 1e-3, "and says so: stopped list names lowerarm_r bend, wanted %s" % [st[0]["wanted"] if not st.is_empty() else "-"])
	ok(Inbetween.describe("push", f, r, "the whole body").contains("STOPPED"), "the say-line says STOPPED: '%s'" % Inbetween.describe("push", f, r, "the whole body").right(70))
	ok(r["stopped"].filter(func(e): return e["joint"] == "thigh_l").is_empty(), "a joint inside its range is not reported")
	# selected parts only: the other joints are byte for byte the same
	B = at(S, 1)
	var before := {}
	for j in B.ang:
		before[j] = B.ang[j]
	r = Inbetween.run(B, S, 1, "push", f, ["thigh_l", "spine_01"])
	var same := true
	var others := 0
	for j in B.ang:
		if j in ["thigh_l", "spine_01"]:
			continue
		others += 1
		if var_to_bytes(B.ang[j]) != var_to_bytes(before[j]):
			same = false
	ok(same, "selected-only: %d other joints are byte-identical" % others)
	ok(absf(B.ang["thigh_l"].x - 32.5) < 1e-4 and r["n"] == 2, "  and the two selected moved (n=%d, thigh_l %.3f)" % [r["n"], B.ang["thigh_l"].x])
	# first / last card refused, nothing touched
	for k in [0, 2]:
		B = at(S, k)
		var bd := JSON.stringify(B.to_dict())
		for op in ["push", "relax"]:
			r = Inbetween.run(B, S, k, op, f, [])
			ok(not r["ok"] and JSON.stringify(B.to_dict()) == bd, "card %d %s refused: '%s'" % [k, op, String(r["why"]).left(40)])
	B = at(S, 0)
	ok(not Inbetween.run(B, S, 0, "prev", f, [])["ok"], "blend to previous on the first card refused")
	B = at(S, 2)
	ok(not Inbetween.run(B, S, 2, "next", f, [])["ok"], "blend to next on the last card refused")
	# blend to rest: 25%
	B = at(S, 1)
	Inbetween.run(B, S, 1, "rest", f, [])
	ok(absf(B.ang["thigh_l"].x - 22.5) < 1e-4 and absf(B.ang["head"].z - 6.0) < 1e-4, "blend to rest: thigh_l 30 -> 22.5, head twist 8 -> 6 (got %.4f, %.4f)" % [B.ang["thigh_l"].x, B.ang["head"].z])
	# blend to neighbours: toward card 0 (0) and card 2 (40)
	B = at(S, 1)
	Inbetween.run(B, S, 1, "prev", f, [])
	ok(absf(B.ang["thigh_l"].x - 22.5) < 1e-4, "blend to previous: thigh_l 30 -> 22.5 (got %.4f)" % B.ang["thigh_l"].x)
	B = at(S, 1)
	Inbetween.run(B, S, 1, "next", f, [])
	ok(absf(B.ang["thigh_l"].x - 32.5) < 1e-4, "blend to next: thigh_l 30 -> 32.5 (got %.4f)" % B.ang["thigh_l"].x)
	# the cards themselves are never touched
	ok(JSON.stringify(S.cards) == JSON.stringify(scene3().cards), "the cards are unchanged by any of it (Update keeps a result)")
	print("INBETWEEN TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
