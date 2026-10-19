## godot --headless --path . -s tests/hand_pose_test.gd     (ROADMAP 73: finger pose library + per-finger curl)
## Body only (the numbers; the undo step and the screenshot are in hand_pose_ui_test.gd). Bars, stated before measuring:
##   1 LIMITS: every library pose (POSE_NAMES) on both hands: each finger and thumb joint within body_limits (clamp_ang
##     changes nothing, 1e-6 deg).
##   2 CURL 0 = REST: finger_curl(0) on all five fingers of both hands leaves every finger joint exactly Vector3.ZERO.
##   3 FIST: curl 1 on the index, each joint within 10 deg of the cited fist: MCP 85 / PIP 97.2 / DIP 74 (the curl model,
##     body.gd CURL_*; Indian J Plast Surg 2024 PMC11436331, Hahn 1995 PMC9541616) and of hand_shape("fist") (90 / 105 / 70).
##   4 GRIP: the grip pose's index joints are Gulke 2010's 28 / 43 / 26 deg exactly (1e-6).
##   5 MIRROR: each pose on the right hand, then mirror_side to the left: every joint of the left matches the right within
##     0.05 deg; and the same pose applied to the left hand matches within 0.05 deg.
##   6 READBACK: finger_curl_of reads back the curl set for every finger at 0.3 and 0.8 (1e-4), and a finger's curl leaves
##     its neighbours alone.
##   7 THUMB: the thumb follows its own curl (thumb_02 at curl 1 = 60 deg, the table's value) and no spread.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func fresh() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


func _init() -> void:
	var B := fresh()
	# 1 limits, both hands, every pose
	var worst_out := 0.0
	for side in ["r", "l"]:
		for pn in Body.POSE_NAMES:
			B.hand_pose(side, pn)
			for j in B.hand_joints(side):
				var v: Vector3 = B.ang[j]
				var c: Vector3 = B.clamp_ang(j, v)
				worst_out = maxf(worst_out, maxf(absf(c.x - v.x), maxf(absf(c.y - v.y), absf(c.z - v.z))))
	ok(worst_out < 1e-6, "1 LIMITS: %d poses x 2 hands x 15 joints, worst clip %.6f deg (every value inside body_limits)" % [Body.POSE_NAMES.size(), worst_out])

	# 2 curl 0 = rest, exactly
	var R := fresh()
	for side in ["r", "l"]:
		R.hand_curl(side, 0.0, 0.0)
		for f in ["index", "middle", "ring", "pinky", "thumb"]:
			R.finger_curl(side, f, 0.0, 0.0)
	R.fk()
	var nz := 0
	for side in ["r", "l"]:
		for j in R.hand_joints(side):
			if R.ang[j] != Vector3.ZERO:
				nz += 1
	ok(nz == 0, "2 CURL 0 = REST: %d of 30 finger / thumb joints not exactly zero after curl 0 on both hands" % nz)

	# 3 fist: index curl 1 vs the cited fist, per joint
	var F := fresh()
	F.finger_curl("r", "index", 1.0, 0.0)
	F.fk()
	var cited_curl := [85.0, 97.2, 74.0]   # body.gd: CURL_MCP, CURL_PIP, DIP_PER_PIP x CURL_PIP
	var cited_shape := [90.0, 105.0, 70.0]   # body.gd hand_shape("fist"), the index's three joints
	var worst_c := 0.0
	var worst_s := 0.0
	var got := []
	for k in 3:
		var a: float = (F.ang["index_0%d_r" % (k + 1)] as Vector3).x
		got.append(snappedf(a, 0.01))
		worst_c = maxf(worst_c, absf(a - cited_curl[k]))
		worst_s = maxf(worst_s, absf(a - cited_shape[k]))
	ok(worst_c <= 10.0, "3a FIST (curl model): index at curl 1 = %s deg, cited 85 / 97.2 / 74: worst %.2f deg (bar 10)" % [str(got), worst_c])
	ok(worst_s <= 10.0, "3b FIST (hand_shape fist 90 / 105 / 70): worst %.2f deg (bar 10)" % worst_s)

	# 4 grip = Gulke
	var G := fresh()
	G.hand_pose("r", "grip")
	var gg := [(G.ang["index_01_r"] as Vector3).x, (G.ang["index_02_r"] as Vector3).x, (G.ang["index_03_r"] as Vector3).x]
	ok(absf(gg[0] - 28.0) < 1e-6 and absf(gg[1] - 43.0) < 1e-6 and absf(gg[2] - 26.0) < 1e-6,
		"4 GRIP (Gulke 2010 mean: MCP 28 / PIP 43 / DIP 26): index = %.4f / %.4f / %.4f" % gg)

	# 5 mirror, and the same pose on the other hand
	var worst_m := 0.0
	var worst_o := 0.0
	for pn in Body.POSE_NAMES:
		var M := fresh()
		M.hand_pose("r", pn)
		M.mirror_side("_r")
		M.fk()
		for j in M.hand_joints("r"):
			var jl: String = j.substr(0, j.length() - 2) + "_l"
			var d: Vector3 = ((M.ang[jl] as Vector3) - (M.ang[j] as Vector3)).abs()
			worst_m = maxf(worst_m, maxf(d.x, maxf(d.y, d.z)))
		var O := fresh()
		O.hand_pose("l", pn)
		var Lh := fresh()
		Lh.hand_pose("r", pn)
		for j in Lh.hand_joints("r"):
			var jl2: String = j.substr(0, j.length() - 2) + "_l"
			var d2: Vector3 = ((O.ang[jl2] as Vector3) - (Lh.ang[j] as Vector3)).abs()
			worst_o = maxf(worst_o, maxf(d2.x, maxf(d2.y, d2.z)))
	ok(worst_m < 0.05, "5a MIRROR: each pose on the right, mirrored to the left: worst joint difference %.4f deg (bar 0.05)" % worst_m)
	ok(worst_o < 0.05, "5b the same pose on the left hand as on the right: worst difference %.4f deg (bar 0.05)" % worst_o)

	# 6 readback, neighbours untouched
	var Q := fresh()
	var worst_r := 0.0
	var neighbour_ok := true
	for f in ["index", "middle", "ring", "pinky", "thumb"]:
		for cu in [0.3, 0.8]:
			Q.finger_curl("r", f, cu, 0.0)
			Q.fk()
			worst_r = maxf(worst_r, absf(Q.finger_curl_of("r", f) - cu))
	Q.hand_pose("r", "open")
	Q.finger_curl("r", "middle", 1.0, 0.0)
	Q.fk()
	for j in ["index_01_r", "index_02_r", "ring_01_r", "pinky_02_r", "thumb_01_r"]:
		if (Q.ang[j] as Vector3) != Vector3.ZERO:
			neighbour_ok = false
	ok(worst_r < 1e-4, "6a READBACK: finger_curl_of reads back the curl set, every finger, 0.3 and 0.8 (worst %.6f)" % worst_r)
	ok(neighbour_ok, "6b the middle finger's curl leaves index, ring, pinky and thumb at rest")

	# 7 thumb: curl 1 = the table's 30 / 60 / 48 with no spread
	var T := fresh()
	T.finger_curl("r", "thumb", 1.0, 1.0)
	T.fk()
	var th := [(T.ang["thumb_01_r"] as Vector3), (T.ang["thumb_02_r"] as Vector3), (T.ang["thumb_03_r"] as Vector3)]
	ok(absf(th[1].x - 60.0) < 1e-6 and absf(th[2].x - 48.0) < 1e-6 and absf(th[0].x - 30.0) < 1e-6 and absf(th[0].y + 10.0) < 1e-6,
		"7 THUMB at curl 1: %.1f / %.1f / %.1f deg (table 30 / 60 / 48); thumb_01 side %.1f (table -10, the spread-free thumb)" % [th[0].x, th[1].x, th[2].x, th[0].y])

	print("hand_pose_test: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)
