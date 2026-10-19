## godot --headless --path . -s tests/drag_speed_test.gd     (round 49, GATES NA6; Nick 10-18: "a little freeze for 0.5 sec"
## moving a hand when the pose is all wrong)
##   1 Body.penetration_moving(j) changes exactly as penetration() does when j turns (the pairs it skips cannot move):
##     200 random turns over 12 joints on 4 poses (rest, tangled arms, a held axe, a two-hand grip), worst |difference|
##     <= 1e-6 m; anti-vacuity: some turns change the penetration at all
##   2 a hand drag on a tangled arm beside a held axe (the magnet's path, quick), 12 mouse steps: the worst step under
##     400 ms (the suite runs 8 at once; idle the same steps measured 49..108 ms, GATES NA6) and the results printed
##   3 Body.reach stops early when blocked: on the tangled arm it returns the same miss as before the early stop would
##     have reached within 1 mm (the rounds after a blocked one redo the same stop)
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	return B


func tangle(B: Body) -> void:
	B.set_ang("upperarm_l", Vector3(-60, 80, -90))
	B.set_ang("lowerarm_l", Vector3(140, 0, 0))
	B.set_ang("hand_l", Vector3(60, 80, 70))
	B.set_ang("upperarm_r", Vector3(70, -40, 30))
	B.set_ang("lowerarm_r", Vector3(130, 0, 0))
	B.set_ang("spine_03", Vector3(0, 35, 0))
	B.fk()


func _init() -> void:
	# 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 49
	var js := ["upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r", "clavicle_l", "spine_03",
		"neck_01", "thigh_l", "calf_r", "spine_01"]
	var worst := 0.0
	var moved := 0
	var n := 0
	for pose in 4:
		var B := body()
		if pose == 1 or pose == 3:
			tangle(B)
		if pose >= 2:
			B.set_kind("long_axe")
			B.weapon_to_hand("hand_r")
			B.fk()
		if pose == 3:
			B.grip = true
		for k in 50:
			var j: String = js[rng.randi() % js.size()]
			var old: Vector3 = B.ang[j]
			var p0 := B.penetration()
			var m0 := B.penetration_moving(j)
			B.set_ang(j, old + Vector3(rng.randf_range(-40, 40), rng.randf_range(-30, 30), rng.randf_range(-30, 30)))
			var d_full := B.penetration() - p0
			var d_mv := B.penetration_moving(j) - m0
			worst = maxf(worst, absf(d_full - d_mv))
			if absf(d_full) > 1e-4:
				moved += 1
			n += 1
	ok(worst <= 1e-6 and moved > 10, "1 %d turns: penetration_moving's change = penetration()'s within %.9f m (bar 0.000001); %d of them changed it (anti-vacuity)" % [n, worst, moved])
	# 2
	var A := body()
	A.set_kind("long_axe")
	A.weapon_to_hand("hand_r")
	A.fk()
	tangle(A)
	var x := A.wep_xform()
	var q: Quaternion = x[1]
	var w := 0
	var first := 0
	var rest := 0
	var outs := {}
	for k in 12:
		var target: Vector3 = (x[0] as Vector3) + q * Vector3(0.06, 0.25 + 0.03 * k, 0.0)
		var t0 := Time.get_ticks_usec()
		var r := GripMagnet.drag(A, "hand_l", target, true)
		var us := Time.get_ticks_usec() - t0
		w = maxi(w, us)
		if k == 0:
			first = us
		else:
			rest = maxi(rest, us)
		outs[r] = outs.get(r, 0) + 1
	ok(w < 400000, "2 a hand drag beside a held axe, arm tangled, 12 steps: worst step %.0f ms (bar 400 here): the first %.0f ms, the 11 after it at most %.0f ms; results %s" % [w / 1000.0, first / 1000.0, rest / 1000.0, outs])
	# 3
	var C := body()
	tangle(C)
	var tgt: Vector3 = (C.P["spine_02"] as Vector3) + Vector3(0.0, 0.0, -0.05)   # behind the back: blocked
	var t1 := Time.get_ticks_usec()
	var miss := C.reach("hand_l", tgt)
	var ms := (Time.get_ticks_usec() - t1) / 1000.0
	var miss2 := C.reach("hand_l", tgt)   # rounds after it, from where it stopped
	ok(absf(miss - miss2) < 0.001 and miss > 0.01, "3 a blocked reach stops at %.3f m off in %.1f ms; reaching again from there gets %.3f m (the rounds it skipped would not have helped, 1 mm)" % [miss, ms, miss2])
	print("DRAG SPEED TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
