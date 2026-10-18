## godot --headless --path . -s tools/cook.gd -- plans/<name>.json   -> scenes/<name>.json
## A PLAN = an animation written as clips. Each clip starts from the clip before (the first from "base") and says only
## what changes:
##   "set":   {joint: [bend, side, twist]}   absolute angles (degrees, the "say" text in data/body_limits.json)
##   "add":   {joint: [bend, side, twist]}   added to what the joint has
##   "hand":  [x, y, z]  where the bat hand's wrist goes (m; in the chest's frame: from spine_03, +x his left, +y up,
##            +z the way the chest faces; plan "frame": "world" = from the floor centre, +z the way he stands)
##   "aim":   [x, y, z]  the way the bat points, knob -> tip
##   "two_hands": true/false  the free hand on the handle (grip at "grip_m" metres up from the knob)
##   "heel_up": ["_r"]  that heel lifts (on the toes);  "steps": {"_l": [x, 0, z]} that foot steps (else feet planted)
##   "fist": ["l"] / "open": ["l"] / "grip": ["l"]  a hand's shape
##   "pose":  "guard_bat"  start this clip from a standard pose (poses/lib/<name>.json); set/add/hand go on top
##   "lift":  0.13      how high the stepping foot rises mid-step (m; default 0.08)
##   "hips":  [x, 0, z]  where the body stands now (m along the floor; kept until a clip changes it)
##   "move", "hold": seconds (move -1 = auto)
## Plan keys: "aim_weight" (default 0.15 per radian of bat direction vs 1 per metre of hand: raise it where the bat's
## direction is the look, as in swings), "name", "base" (a pose file), "bat_hand" ("hand_r" / "hand_l": the hand that holds the bat at the knob end)
## The tool: angles -> feet flat / heel up -> ground -> bat hand reach + aim (4 rounds) -> other hand on the grip ->
## the scene: feet planted, pass-bys round the body -> report (misses, contacts, bad frames).
extends SceneTree

const LEGS := ["foot_l", "foot_r", "ball_l", "ball_r"]


func _v(a) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _init() -> void:
	var path: String = OS.get_cmdline_user_args()[0]
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://" + path))
	if not parsed is Dictionary:
		print("COOK: no plan at ", path)
		quit(1)
		return
	var plan: Dictionary = parsed
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var base: String = plan.get("base", "poses/bat_hold.json")
	B.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://" + base)))
	if plan.has("bat_hand") and plan["bat_hand"] != B.wep_hand:
		B.weapon_to_hand(plan["bat_hand"])   # the standard grip, mirrored for the left hand
	var S := Scene.new()
	S.name = plan["name"]
	var report := []
	var score := 0.0   # the lane score: hand misses (m) + aim misses (deg/100) + 0.02 per bad frame
	var ua_ := OS.get_cmdline_user_args()
	var ri := ua_.find("--roll")
	if ri >= 0 and ri + 1 < ua_.size():
		B.roll_start = float(ua_[ri + 1])
	B.elbow_low = float(plan.get("elbow_low", 0.0))   # Body.ELBOW LOW: the elbow under the wrist (a bat on the shoulder)
	var hips := Vector3.ZERO
	for c in plan["clips"]:
		for j in LEGS:
			B.ang[j] = Vector3.ZERO
		if c.has("pose"):
			# a STANDARD POSE from poses/lib/ (checked by tools/pose_check.gd): every angle from it, then this clip's
			# own "set"/"add"/"hand" on top. The bat stays in the plan's hand.
			var lp = JSON.parse_string(FileAccess.get_file_as_string("res://poses/lib/%s.json" % c["pose"]))
			if not lp is Dictionary:
				print("COOK: no library pose ", c["pose"])
				quit(1)
				return
			var keep_hand := B.wep_hand
			B.from_dict(lp)
			if keep_hand != "" and B.wep_hand != keep_hand:
				B.weapon_to_hand(keep_hand)
		for j in c.get("set", {}):
			B.ang[j] = B.clamp_ang(j, _v(c["set"][j]))
		for j in c.get("add", {}):
			B.ang[j] = B.clamp_ang(j, B.ang[j] + _v(c["add"][j]))
		B.offset = Vector3.ZERO
		if c.has("hips"):
			hips = _v(c["hips"])
		B.offset = Vector3(hips.x, 0.0, hips.z)   # the body travels (dodges, walks); the height comes from ground()
		B.fk()
		for kind in ["fist", "open", "grip"]:
			for k in c.get(kind, []):
				B.hand_shape(k, kind)
		if c.has("two_hands"):
			B.grip = bool(c["two_hands"])
		if c.has("grip_m"):
			B.grip_u = float(c["grip_m"])
		for sd in ["_l", "_r"]:
			B.flat_foot(sd)
		for sd in c.get("heel_up", []):
			B.set_ang("foot" + sd, B.ang["foot" + sd] + Vector3(-25, 0, 0))
			B.toes_flat(sd)
		B.ground()
		var aim := 0.0
		var miss := 0.0
		var gm := 0.0
		# "hand" is in the CHEST's frame (origin spine_03, its own left/up/forward axes, turning with the trunk) unless
		# the plan says "frame": "world". Reach check: the arm (shoulder -> wrist) is ~0.49 m.
		var at := Vector3.ZERO
		if c.has("hand"):
			at = _v(c["hand"])
			if plan.get("frame", "chest") == "chest":
				at = (B.P["spine_03"] as Vector3) + (B.G["spine_03"] as Quaternion) * at
			if B.wep_hand != "":
				var sh: String = "upperarm" + B.wep_hand.substr(B.wep_hand.length() - 2)
				var dd := ((B.P[sh] as Vector3) - at).length()
				if dd > 0.47:
					print("  ! %s: the hand target is %.2f m from the shoulder (the arm reaches ~0.49)" % [c["name"], dd])
		if B.wep_hand != "" and (c.has("hand") or c.has("aim")):
			# quick two-bone reach + wrist aim first, then both arms searched together (contact-aware)
			B.roll_free = S.cards.is_empty()   # the move's first key: nothing to spin from
			B.sweep_bat_arm(at, _v(c.get("aim", [0, 1, 0])), c.has("hand"), c.has("aim"), float(c.get("aim_weight", plan.get("aim_weight", 0.15))))
			var res := [((B.P[B.wep_hand] as Vector3) - at).length() if c.has("hand") else 0.0,
				rad_to_deg(B.wep_axis().angle_to(_v(c.get("aim", [0, 1, 0])).normalized())) if c.has("aim") else 0.0,
				B.apply_grip()]
			miss = res[0]
			aim = res[1]
			gm = res[2]
		B.apply_grip()
		S.add(c["name"], B.to_dict())
		S.cards[-1]["move"] = float(c.get("move", -1.0))
		S.cards[-1]["hold"] = float(c.get("hold", 0.0))
		S.cards[-1]["steps"] = c.get("steps", {})
		if c.has("lift"):
			S.cards[-1]["lift"] = float(c["lift"])
		var cs: Array = B.contacts().map(func(x): return "%s/%s %.0fmm" % [x[0], x[1], x[2] * 1000])
		score += miss + aim / 100.0
		report.append("  %-18s hand miss %.3f m  aim off %4.1f deg  2nd hand miss %.3f  contacts %s" % [c["name"], miss, aim, gm, cs])
	var pins := S.pin_cards(B)
	for x in S.spins():
		report.append("  SPIN (banned): " + x)
	var added := S.clear(B)
	var d := S.to_dict(B)
	d["plan"] = path
	var f := FileAccess.open("res://scenes/%s.json" % plan["name"], FileAccess.WRITE)
	f.store_string(JSON.stringify(d, " "))
	f.close()
	score += 0.02 * d["bad_frames"].size()
	print("LANE roll %s score %.3f" % [str(B.roll_start), score])
	print("COOK %s: %d clips (+%d pass-by), %.2f s, legs re-planted %d, bad frames %d" % [plan["name"], S.cards.size() - added, added, S.length(), pins, d["bad_frames"].size()])
	for r in report:
		print(r)
	if not d["bad_frames"].is_empty():
		var worst = d["bad_frames"][0]
		var wd := 0.0
		for b in d["bad_frames"]:
			for x in b[2]:
				if x[2] > wd:
					wd = x[2]
					worst = b
		print("  worst frame ", worst)
	quit()
