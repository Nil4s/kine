extends SceneTree
## Friday plan 140: authors the mood poses in poses/lib/ from joint angles (the mannequin's own FK, grounded), then prints what
## PoseMood MEASURES on each (the file's tags come from the body, not from this list).
##   godot --headless --path . -s tools/s140_make_poses.gd [-- write]
var B: Body


func V(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, y, z)


func base() -> Dictionary:
	return {"upperarm_l": V(0, -65, 0), "upperarm_r": V(0, -65, 0), "lowerarm_l": V(10, 0, 0), "lowerarm_r": V(10, 0, 0)}


func pose(nm: String, note: String, over: Dictionary, fist := 0.0, hands := {}) -> void:
	B.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	for j in Body.ORDER:
		B.ang[j] = Vector3.ZERO
	var a := base()
	for k in over:
		a[k] = over[k]
	for j in a:
		B.ang[j] = B.clamp_ang(j, a[j])
	B.fk()
	var hc: Vector3 = ((B.P["head"] as Vector3) + (B.E["head"] as Vector3)) * 0.5
	for sd in ["l", "r"]:
		B.ang["foot_" + sd] = B.clamp_ang("foot_" + sd, V(B.ang["calf_" + sd].x - B.ang["thigh_" + sd].x, 0, 0))
	B.fk()
	for hs in hands:
		aim_arm(hs, hc + (hands[hs] as Vector3))
	for s in ["l", "r"]:
		if fist > 0.0:
			B.hand_curl(s, fist, 0.0)
		else:
			B.hand_relaxed(s)
	B.fk()
	B.ground()
	var d: Dictionary = B.to_dict()
	d["note"] = note
	var mood := PoseMood.tags_of(d)
	var r := PoseMood.measure(d)
	print("%-22s alltags=%s moods=%s  head=%.0f lean=%.0f curl=%.0f shF=%.0f shU=%.0f knee=%.0f elb=%.0f/%.0f faceL=%.2f faceR=%.0f hands_apart=%.2f fist=%.0f aboveSh=%.2f/%.2f contacts=%d" % [nm, PoseTags.tags_of(d), mood, r["head_down"], r["trunk_lean"], r["spine_curl"], r["shoulder_fwd"], r["shoulder_up"], r["knee_flex"], r["elbow_l"], r["elbow_r"], r["face_l"], r["face_r"] * 100, r["hands_apart"], r["fist"], r["wrist_above_shoulder_l"], r["wrist_above_shoulder_r"], (d["contacts"] as Array).size()])
	var cs := []
	for c in d["contacts"]:
		cs.append("%s|%s %.0fmm" % [c[0], c[1], float(c[2]) * 1000.0])
	print("      contacts: ", cs)
	if OS.get_cmdline_user_args().has("write"):
		var f := FileAccess.open("res://poses/lib/%s.json" % nm, FileAccess.WRITE)
		f.store_string(JSON.stringify(d, " "))
		f.close()


## the arm (side "l"/"r") searched over the shoulder and elbow angles so the hand lands on `target` (m) with the least
## penetration of the body: the score is the miss (m) + 4 x the penetration (m)
func aim_arm(side: String, target: Vector3) -> void:
	var u := "upperarm_" + side
	var lw := "lowerarm_" + side
	var best := INF
	var bu := Vector3.ZERO
	var be := 0.0
	for bend in range(10, 111, 10):
		for sd in range(-80, 21, 10):
			for tw in range(-60, 61, 20):
				for el in range(60, 146, 15):
					B.ang[u] = B.clamp_ang(u, V(bend, sd, tw))
					B.ang[lw] = V(el, 0, 0)
					B.fk()
					var miss: float = (B.P["hand_" + side] as Vector3).distance_to(target)
					if miss > best or miss > 0.10:
						continue
					var sc: float = miss + 4.0 * B.penetration()
					if sc < best:
						best = sc
						bu = B.ang[u]
						be = el
	B.ang[u] = bu
	B.ang[lw] = V(be, 0, 0)
	B.fk()


func both(k: String, v: Vector3, o: Dictionary) -> void:
	o[k + "_l"] = v
	o[k + "_r"] = v


func _init() -> void:
	B = Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var o: Dictionary
	# ---------------------------------------------------------------- tired
	o = {"spine_01": V(4, 0, 0), "spine_02": V(9, 0, 0), "spine_03": V(9, 0, 0), "neck_01": V(12, 0, 0), "head": V(5, 0, 0)}
	both("clavicle", V(-5, 10, 0), o)
	both("upperarm", V(10, -75, 0), o)
	both("lowerarm", V(15, 0, 0), o)
	pose("tired_slump", "Tired: head down, back rounded, shoulders slumped forward, arms hanging", o)
	o = {"spine_01": V(6, 0, 0), "spine_02": V(11, 0, 0), "spine_03": V(11, 0, 0), "neck_01": V(13, 0, 0), "head": V(5, 0, 0)}
	both("clavicle", V(-8, 15, 0), o)
	both("upperarm", V(15, -78, 0), o)
	both("lowerarm", V(20, 0, 0), o)
	both("thigh", V(8, 0, 0), o)
	both("calf", V(16, 0, 0), o)
	pose("tired_droop", "Tired: all the way down, knees soft, head hanging, shoulders dropped and forward", o)
	o = {"spine_01": V(7, 0, 0), "spine_02": V(7, 0, 0), "spine_03": V(7, 0, 0), "neck_01": V(12, 0, 0), "head": V(6, 0, 0)}
	both("clavicle", V(-8, 8, 0), o)
	o["upperarm_l"] = V(10, -75, 0)
	o["lowerarm_l"] = V(15, 0, 0)
	o["upperarm_r"] = V(75, -20, 0)
	o["lowerarm_r"] = V(125, 0, 0)
	pose("tired_rub_face", "Tired: slumped, one hand up to rub the face", o, 0.0, {"r": V(-0.03, -0.06, 0.20)})
	o = {"spine_01": V(5, 0, 0), "spine_02": V(9, 0, 0), "spine_03": V(9, 0, 0), "neck_01": V(12, 0, 0), "head": V(5, 0, 0)}
	both("clavicle", V(-6, 10, 0), o)
	o["upperarm_l"] = V(10, -75, 0)
	o["lowerarm_l"] = V(15, 0, 0)
	pose("tired_chin_on_hand", "Tired: slumped, one hand propping the chin", o, 0.0, {"r": V(-0.05, -0.14, 0.17)})
	o = {"pelvis": V(3, 0, 0), "spine_01": V(4, 0, 0), "spine_02": V(8, 0, 0), "spine_03": V(8, 0, 0), "neck_01": V(12, 0, 0), "head": V(6, 0, 0)}
	both("clavicle", V(-4, 12, 0), o)
	both("upperarm", V(30, -72, 0), o)
	both("lowerarm", V(25, 0, 0), o)
	both("thigh", V(5, 0, 0), o)
	both("calf", V(10, 0, 0), o)
	pose("tired_heavy_arms", "Tired: bent forward, arms swinging heavy and forward, knees soft", o)
	# ---------------------------------------------------------------- proud
	o = {"spine_01": V(-2.3, 0, 0), "spine_02": V(-2.3, 0, 0), "spine_03": V(-2.3, 0, 0), "neck_01": V(-4, 0, 0), "head": V(-6, 0, 0)}
	both("clavicle", V(4, -10, 0), o)
	both("upperarm", V(0, -60, 0), o)
	both("lowerarm", V(10, 0, 0), o)
	pose("proud_chest_out", "Proud: chest up, chin up, shoulders back, arms easy at the sides", o)
	o = {"spine_01": V(-2.3, 0, 0), "spine_02": V(-2.3, 0, 0), "spine_03": V(-2.3, 0, 0), "neck_01": V(-4, 0, 0), "head": V(-6, 0, 0)}
	both("clavicle", V(4, -10, 0), o)
	both("upperarm", V(-15, -40, 0), o)
	both("lowerarm", V(100, 0, 0), o)
	pose("proud_hands_on_hips", "Proud: fists on the hips, elbows out, chest up, chin up", o, 0.6)
	o = {"spine_01": V(-2.3, 0, 0), "spine_02": V(-2.3, 0, 0), "spine_03": V(-2.3, 0, 0), "neck_01": V(-5, 0, 0), "head": V(-7, 0, 0)}
	both("clavicle", V(8, -10, 0), o)
	both("upperarm", V(0, 55, 0), o)
	both("lowerarm", V(10, 0, 0), o)
	pose("proud_victory", "Proud: both arms thrown up in a V, chest out, chin up", o)
	# ---------------------------------------------------------------- scared
	o = {"neck_01": V(-12, 0, 0), "head": V(-8, 0, 0), "spine_01": V(-2, 0, 0)}
	o["upperarm_l"] = V(85, -30, 0)
	o["lowerarm_l"] = V(125, 0, 0)
	o["upperarm_r"] = V(5, -70, 0)
	o["lowerarm_r"] = V(20, 0, 0)
	both("thigh", V(20, 0, 0), o)
	both("calf", V(35, 0, 0), o)
	both("clavicle", V(8, 0, 0), o)
	pose("scared_shield", "Scared: one forearm up in front of the face, the other arm low and back, knees bent, head pulled back", o, 0.0, {"l": V(0.10, -0.02, 0.30)})
	o = {"neck_01": V(10, 0, 0), "head": V(5, 0, 0), "spine_01": V(4, 0, 0), "spine_02": V(9, 0, 0), "spine_03": V(9, 0, 0)}
	o["upperarm_r"] = V(80, -20, 0)
	o["lowerarm_r"] = V(130, 0, 0)
	o["upperarm_l"] = V(5, -72, 0)
	o["lowerarm_l"] = V(15, 0, 0)
	both("thigh", V(25, 0, 0), o)
	both("calf", V(45, 0, 0), o)
	both("clavicle", V(10, 5, 0), o)
	pose("scared_hand_to_mouth", "Scared: ducked, one hand pressed to the mouth, the other arm hanging, knees bent, head down", o, 0.0, {"r": V(-0.03, -0.07, 0.17)})
	o = {"neck_01": V(-12, 0, 0), "head": V(-10, 0, 0), "pelvis": V(-6, 0, 0)}
	o["upperarm_l"] = V(80, -30, 0)
	o["lowerarm_l"] = V(120, 0, 0)
	o["upperarm_r"] = V(30, -25, 0)
	o["lowerarm_r"] = V(60, 0, 0)
	both("thigh", V(10, 0, 0), o)
	both("calf", V(25, 0, 0), o)
	o["clavicle_l"] = V(8, 0, 0)
	o["clavicle_r"] = V(8, 0, 0)
	pose("scared_back_away", "Scared: leaning back, one arm up to shield the face, the other drawn in, knees bent", o, 0.0, {"l": V(0.10, 0.0, 0.30)})
	# ---------------------------------------------------------------- happy
	o = {"neck_01": V(-6, 0, 0), "head": V(-4, 0, 0), "spine_01": V(-2, 0, 0), "spine_02": V(-2, 0, 0), "spine_03": V(-2, 0, 0)}
	both("upperarm", V(0, 40, 0), o)
	both("lowerarm", V(10, 0, 0), o)
	pose("happy_cheer", "Happy: arms up and open, head up", o)
	o = {"neck_01": V(-4, 0, 0), "head": V(-4, 0, 0)}
	both("upperarm", V(10, 20, 0), o)
	both("lowerarm", V(15, 0, 0), o)
	pose("happy_open_arms", "Happy: arms open and a little raised, head up", o)
	# ---------------------------------------------------------------- excited
	o = {"neck_01": V(-4, 0, 0), "head": V(-4, 0, 0)}
	both("upperarm", V(0, 70, 0), o)
	both("lowerarm", V(10, 0, 0), o)
	both("thigh", V(14, 0, 0), o)
	both("calf", V(28, 0, 0), o)
	pose("excited_jump", "Excited: arms high, knees bent, ready to jump", o)
	o = {"neck_01": V(-4, 0, 0), "head": V(-4, 0, 0)}
	both("upperarm", V(10, 85, 0), o)
	both("lowerarm", V(10, 0, 0), o)
	both("thigh", V(18, 0, 0), o)
	both("calf", V(36, 0, 0), o)
	pose("excited_bounce", "Excited: both arms straight up, bouncing on bent knees", o)
	# ---------------------------------------------------------------- angry
	o = {"spine_01": V(4, 0, 0), "spine_02": V(4, 0, 0), "spine_03": V(4, 0, 0), "neck_01": V(8, 0, 0), "head": V(6, 0, 0)}
	both("clavicle", V(10, 10, 0), o)
	both("upperarm", V(30, -15, 0), o)
	both("lowerarm", V(100, 0, 0), o)
	pose("angry_fists", "Angry: leaning in, shoulders up and forward, fists clenched out in front and wide", o, 1.0, {"l": V(0.30, -0.45, 0.35), "r": V(-0.30, -0.45, 0.35)})
	o = {"pelvis": V(4, 0, 0), "spine_01": V(5, 0, 0), "spine_02": V(5, 0, 0), "spine_03": V(5, 0, 0), "neck_01": V(10, 0, 0), "head": V(8, 0, 0)}
	both("clavicle", V(12, 14, 0), o)
	both("upperarm", V(35, -10, 0), o)
	both("lowerarm", V(90, 0, 0), o)
	both("thigh", V(8, 0, 0), o)
	both("calf", V(12, 0, 0), o)
	pose("angry_glare", "Angry: leaning hard forward, chin down, clenched fists held out and wide", o, 1.0, {"l": V(0.26, -0.40, 0.30), "r": V(-0.26, -0.40, 0.30)})
	# ---------------------------------------------------------------- sad
	o = {"spine_01": V(4, 0, 0), "spine_02": V(4, 0, 0), "spine_03": V(3, 0, 0), "neck_01": V(10, 0, 0), "head": V(6, 0, 0)}
	both("clavicle", V(-3, 4, 0), o)
	both("upperarm", V(5, -78, 0), o)
	both("lowerarm", V(8, 0, 0), o)
	pose("sad_hang", "Sad: head hanging, chest sunk a little, arms limp at the sides", o)
	o = {"spine_01": V(3, 0, 0), "spine_02": V(3, 0, 0), "spine_03": V(3, 0, 0), "neck_01": V(12, 0, 0), "head": V(8, 0, 0)}
	both("clavicle", V(-2, 2, 0), o)
	both("upperarm", V(8, -80, 0), o)
	both("lowerarm", V(5, 0, 0), o)
	pose("sad_head_down", "Sad: head right down, shoulders sagging, arms hanging", o)
	# ---------------------------------------------------------------- calm
	o = {}
	both("clavicle", V(-4, 0, 0), o)
	pose("calm_easy", "Calm: upright and level, shoulders let down, arms loose, knees easy", o)
	o = {}
	both("upperarm", V(0, -55, 0), o)
	both("lowerarm", V(15, 0, 0), o)
	both("clavicle", V(-5, 0, 0), o)
	pose("calm_open_hands", "Calm: upright, arms a little out from the body, relaxed", o)
	quit()
