## godot --headless --path . -s tests/math_test.gd   (prints MATH PASS n/n)
extends SceneTree

var ok := 0
var n := 0


func check(name: String, cond: bool, info := "") -> void:
	n += 1
	if cond:
		ok += 1
	print(("ok   " if cond else "FAIL ") + name + ("  " + info if info != "" else ""))


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	# 1. angles -> rotation -> angles, every joint, random poses inside the limits
	var worst := 0.0
	seed(7)
	for k in 200:
		for j in Body.ORDER:
			var L: Dictionary = B.lim[j]
			var v := Vector3(randf_range(L["bend"].x, L["bend"].y), randf_range(L["side"].x, L["side"].y),
				randf_range(L["twist"].x, L["twist"].y))
			var back := B.decompose(j, B.compose(j, v))
			worst = maxf(worst, (func(w): return maxf(w.x, maxf(w.y, w.z))).call((back - v).abs()) if v.length() < 170.0 else 0.0)
	check("round trip angles", worst < 0.01, "worst %.5f deg" % worst)
	# 2. rest pose = the skeleton file exactly
	var d := 0.0
	for j in Body.ORDER:
		d = maxf(d, (B.P[j] - B.p0[j]).length())
	check("rest pose = skeleton.json", d < 1e-5, "%.7f m" % d)
	# 3. right elbow bend 90: the hand goes forward (+Z), the elbow stays put
	var h0: Vector3 = B.P["hand_r"]
	var up0: Vector3 = (B.P["lowerarm_r"] - B.P["upperarm_r"]).normalized()
	var fa0: Vector3 = (B.P["hand_r"] - B.P["lowerarm_r"]).normalized()
	B.set_ang("lowerarm_r", Vector3(90, 0, 0))
	var h1: Vector3 = B.P["hand_r"]
	var fa1: Vector3 = (B.P["hand_r"] - B.P["lowerarm_r"]).normalized()
	var opened := rad_to_deg(up0.angle_to(fa1)) - rad_to_deg(up0.angle_to(fa0))
	check("elbow bend 90 folds the arm 90, hand forward", absf(opened - 90.0) < 1.0 and h1.z > h0.z,
		"fold %.2f deg, dz %.3f" % [opened, h1.z - h0.z])
	# 4. the limit holds: asking 200 gives 145
	B.set_ang("lowerarm_r", Vector3(200, 0, 0))
	check("elbow clamps at 145", absf(B.ang["lowerarm_r"].x - 145.0) < 1e-4, str(B.ang["lowerarm_r"]))
	B.set_ang("lowerarm_r", Vector3.ZERO)
	# 5. right knee bend 90: the foot goes backward (-Z)
	var f0: Vector3 = B.P["foot_r"]
	B.set_ang("calf_r", Vector3(90, 0, 0))
	check("knee bend moves the foot back", B.P["foot_r"].z - f0.z < -0.2, "dz %.3f" % (B.P["foot_r"].z - f0.z))
	B.set_ang("calf_r", Vector3.ZERO)
	# 6. arm side -90 puts the right hand down at his side
	B.set_ang("upperarm_r", Vector3(0, -90, 0))
	var hr: Vector3 = B.P["hand_r"]
	check("arm side -90 = hand hangs below the shoulder", hr.y < B.P["upperarm_r"].y - 0.45 and absf(hr.x - B.P["upperarm_r"].x) < 0.08, str(hr))
	# 7. mirror: left becomes the right's reflection (x flipped)
	B.set_ang("upperarm_r", Vector3(40, -60, 25))
	B.set_ang("lowerarm_r", Vector3(70, 0, 0))
	B.mirror_side("_r")
	# the rest skeleton is symmetric to the elbows; the hands are 4 cm off at rest already (the hero glb's own)
	var a: Vector3 = B.P["hand_r"]
	var b: Vector3 = B.P["hand_l"]
	var ea: Vector3 = B.P["lowerarm_r"]
	var eb: Vector3 = B.P["lowerarm_l"]
	check("mirror R->L reflects the arm", (Vector3(-ea.x, ea.y, ea.z) - eb).length() < 0.002 and (Vector3(-a.x, a.y, a.z) - b).length() < 0.06,
		"elbow %.4f m, hand %.3f m" % [(Vector3(-ea.x, ea.y, ea.z) - eb).length(), (Vector3(-a.x, a.y, a.z) - b).length()])
	# 8. drag-style turn: rotate the right shoulder by 30 deg about +Y in world, angles stay legal
	B.turn_world("upperarm_r", Quaternion(Vector3.UP, deg_to_rad(30)))
	var v: Vector3 = B.ang["upperarm_r"]
	check("world turn stays inside limits", v == B.clamp_ang("upperarm_r", v), str(v))
	# 9. thigh forward 90: the knee goes forward and up to hip height
	B.set_ang("thigh_r", Vector3(90, 0, 0))
	var kn: Vector3 = B.P["calf_r"]
	check("thigh bend 90 = knee forward at hip height", kn.z > 0.35 and absf(kn.y - B.P["thigh_r"].y) < 0.08, str(kn))
	print("MATH %s %d/%d" % ["PASS" if ok == n else "FAIL", ok, n])
	quit(0 if ok == n else 1)
