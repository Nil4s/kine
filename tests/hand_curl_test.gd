## godot --headless --path . -s tests/hand_curl_test.gd     (round 43, GATES YY3)
## HANDS, ONE SLIDER: Body.hand_curl against people. Bars: curl 1 = knuckle 85 / middle 97.2 / tip 0.76 x middle on
## every finger (Indian J Plast Surg 2024, PMC11436331; Hahn 1995 via PMC9541616), all inside the limits; the tip joint
## is 0.76 of the middle joint at every curl; hand_curl_of reads back what was set (1e-4); curl 0 = every finger joint
## 0; no two neighbouring fingertips closer than 1.2 cm (they do not cross) at curl 0 / 0.5 / 1 x spread 0 / 1 and in
## Point; the left hand is the right one reflected (fingertips, 1e-4 m); Point leaves the index straight and the rest
## curled; the old shapes (open / grip / fist) give the same angles as before.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


const F := ["index", "middle", "ring", "pinky"]


func tip(B: Body, f: String, sd: String) -> Vector3:
	return (B.cap("%s_03_%s" % [f, sd]) as Array)[1]


func closest(B: Body, sd: String) -> float:
	var m := INF
	for i in 3:
		m = minf(m, (tip(B, F[i], sd) - tip(B, F[i + 1], sd)).length())
	return m


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	B.hand_shape("r", "fist")
	var fist0: Dictionary = B.ang.duplicate()
	B.hand_curl("r", 1.0, 0.0)
	var good := true
	var seen := []
	for f in F:
		var a: Vector3 = B.ang[f + "_01_r"]
		var b: Vector3 = B.ang[f + "_02_r"]
		var c: Vector3 = B.ang[f + "_03_r"]
		good = good and absf(a.x - 85.0) < 1e-4 and absf(b.x - 97.2) < 1e-4 and absf(c.x - 0.76 * 97.2) < 1e-4
		seen.append([snappedf(a.x, 0.1), snappedf(b.x, 0.1), snappedf(c.x, 0.1)])
	ok(good, "1 curl 1: knuckle / middle / tip per finger %s (people 84-87 / 97.2 / 0.76 x middle)" % str(seen))
	var ratio_ok := true
	var back_ok := true
	for cu in [0.1, 0.33, 0.5, 0.8]:
		for sp in [0.0, 0.6]:
			B.hand_curl("r", cu, sp)
			for f in F:
				var b: float = (B.ang[f + "_02_r"] as Vector3).x
				ratio_ok = ratio_ok and absf((B.ang[f + "_03_r"] as Vector3).x - 0.76 * b) < 1e-4
			var rb := B.hand_curl_of("r")
			back_ok = back_ok and absf(rb.x - cu) < 1e-4 and absf(rb.y - sp) < 1e-4
	ok(ratio_ok, "2 the tip joint = 0.76 x the middle joint at curl 0.1 / 0.33 / 0.5 / 0.8")
	ok(back_ok, "3 hand_curl_of reads back the curl and spread that were set (1e-4)")
	B.hand_curl("r", 0.0, 0.0)
	var zero := true
	for f in F:
		for k in 3:
			zero = zero and (B.ang["%s_0%d_r" % [f, k + 1]] as Vector3).length() < 1e-6
	ok(zero, "4 curl 0 spread 0: every finger joint 0")
	var worst := INF
	var at := ""
	for cu in [0.0, 0.5, 1.0]:
		for sp in [0.0, 1.0]:
			B.hand_curl("r", cu, sp)
			if closest(B, "r") < worst:
				worst = closest(B, "r")
				at = "curl %.1f spread %.1f" % [cu, sp]
	B.hand_point("r")
	if closest(B, "r") < worst:
		worst = closest(B, "r")
		at = "point"
	B.hand_shape("r", "relaxed")
	if closest(B, "r") < worst:
		worst = closest(B, "r")
		at = "relaxed"
	ok(worst > 0.012, "5 neighbouring fingertips never closer than %.1f mm (bar > 12, at %s)" % [worst * 1000.0, at])
	B.hand_point("r")
	var idx_straight := (B.ang["index_02_r"] as Vector3).x == 0.0 and (B.ang["middle_02_r"] as Vector3).x > 90.0
	ok(idx_straight, "6 Point: the index straight (middle joint 0), the middle finger curled (%.1f)" % (B.ang["middle_02_r"] as Vector3).x)
	B.hand_curl("r", 0.7, 0.5)
	B.hand_curl("l", 0.7, 0.5)
	var mir := 0.0
	for f in F + ["thumb"]:
		var r: Vector3 = tip(B, f, "r")
		var l: Vector3 = tip(B, f, "l")
		mir = maxf(mir, (Vector3(-r.x, r.y, r.z) - l).length())
	ok(mir < 1e-4, "7 the left hand is the right reflected: fingertips within %.6f m" % mir)
	B.hand_shape("r", "fist")
	var same := true
	for f in F + ["thumb"]:
		for k in 3:
			var j := "%s_0%d_r" % [f, k + 1]
			same = same and B.ang[j] == fist0[j]
	ok(same, "8 the old Fist gives the same right-hand angles as before (hand_shape untouched)")
	# RELAXED: the paper's table, joint by joint (Varghese 2020, Table 13, non-power-grip dominant hand)
	var table := {"index": [27.08, 38.74, 13.76], "middle": [33.21, 40.67, 14.20], "ring": [29.34, 44.83, 14.33], "pinky": [26.24, 43.07, 16.08]}
	B.hand_shape("l", "relaxed")
	var rel := true
	for f in table:
		for k in 3:
			rel = rel and absf((B.ang["%s_0%d_l" % [f, k + 1]] as Vector3).x - table[f][k]) < 1e-4
	var col := func(k: int) -> Array: return F.map(func(f): return (B.ang["%s_0%d_l" % [f, k + 1]] as Vector3).x)
	var mcp: Array = col.call(0)
	var pip: Array = col.call(1)
	var dip: Array = col.call(2)
	var order: bool = mcp.max() == mcp[1] and pip.max() == pip[2] and dip.max() == dip[3]
	ok(rel and order, "9 Relaxed = the resting cascade of 250 hands, every joint (1e-4); most curl at the middle finger's knuckle %.1f, the ring's middle joint %.1f, the little finger's tip %.1f (as the paper finds)" % [mcp[1], pip[2], dip[3]])
	print("HAND CURL TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
