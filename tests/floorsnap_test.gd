## godot --headless --path . -s tests/floorsnap_test.gd     (ROADMAP 46; scripts/floor_snap.gd, Body.floor_shift)
## The floors are the app's own (Body.floor_shift): a SOLE stands on Body.ground()'s floor (the rest sole height, 15 mm above
## the joint origin: the on_floor playback puts it there), a knee / hip / hand CAPSULE on y = 0 (Body.ground_body()'s floor).
## Bars, written before measuring:
##   1 STANDING: poses/stand.json lifted 12 cm: the sole is 12 cm above its floor (anti-vacuity), after FloorSnap the lowest
##     sole is on its floor at 0 +- 1 mm, and the snapped root equals Body.ground()'s root for the same pose within 1 mm.
##   2 ONLY THE ROOT MOVES: every joint angle is equal before and after (1e-6 deg), and the root's x and z are unchanged.
##   3 KNEELING: a knee-down pose (thigh 0 deg, calf 120 deg) put on the floor, sunk 5 cm (anti-vacuity: the knee is 5 cm
##     under y = 0), then snapped: the knee capsule's surface is at y = 0 +- 1 mm, it is a thigh (the knee), and no sole
##     is under its floor.
##   4 CARDS: a 3-card scene (stand lifted 12 cm, kneel sunk 5 cm, stand): 2 cards move (the stand is on its floor already),
##     every card's lowest contact is on its floor at 0 +- 1 mm, nothing is under a floor, every joint angle unchanged,
##     and a second snap moves no card.
##   5 IDEMPOTENT: a snapped pose snapped again moves less than 0.01 mm.
## Undo is covered by tests/undo_audit_test.gd, which runs every registry command (these are marked as edits).
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


func stand() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json"))


## the same pose with its root raised by dy (m) and its named joints set to bend (deg)
func variant(d: Dictionary, dy: float, bends := {}) -> Dictionary:
	var out := d.duplicate(true)
	var o: Array = out["offset"]
	out["offset"] = [o[0], float(o[1]) + dy, o[2]]
	for j in bends:
		var x: Dictionary = out["joints"][j]
		x["bend"] = bends[j]
	return out


## the pose d's contacts: [sole gap (the lowest sole point above its floor), capsule gap (the lowest knee / hip / hand
## capsule above y = 0), the capsule's joint, the contact that is lowest ("sole" or the joint)]
func gaps(B: Body, d: Dictionary) -> Array:
	B.from_dict(d)
	var sole := minf(B.foot_sole_low("_l"), B.foot_sole_low("_r"))
	var cap := INF
	var who := ""
	for j in Body.ORDER:
		if j.begins_with("thumb") or j.begins_with("index") or j.begins_with("middle") or j.begins_with("ring") or j.begins_with("pinky"):
			continue
		if j.begins_with("foot") or j.begins_with("ball"):
			continue
		var g := minf((B.P[j] as Vector3).y, (B.E[j] as Vector3).y) - float(B.rad.get(j, 0.03))
		if g < cap:
			cap = g
			who = j
	return [sole, cap, who, "sole" if sole <= cap else who]


func angles(d: Dictionary) -> Dictionary:
	var out := {}
	for j in d["joints"]:
		var x: Dictionary = d["joints"][j]
		out[j] = [x["bend"], x["side"], x["twist"]]
	return out


func _init() -> void:
	var B := body()
	var S0 := stand()

	# ---- 1 standing, lifted 12 cm
	var lift := variant(S0, 0.12)
	var g_lift: Array = gaps(B, lift)
	ok(absf(float(g_lift[0]) - 0.12) < 0.0005, "anti-vacuity: the lifted sole is 12 cm above its floor (%.1f mm)" % (float(g_lift[0]) * 1000.0))
	var snapped := FloorSnap.snapped_pose(B, lift)
	var g_sn: Array = gaps(B, snapped)
	ok(absf(float(g_sn[0])) < 0.001, "standing lifted 12 cm: lowest sole on its floor at 0 +- 1 mm (%.3f mm, %s)" % [float(g_sn[0]) * 1000.0, g_sn[3]])
	ok(g_sn[3] == "sole", "the lowest contact is a sole (heel or ball), not a knee or hand: %s" % g_sn[3])
	var ground := body()
	ground.from_dict(stand())
	ground.ground()
	var diff := absf(float(snapped["offset"][1]) - ground.offset.y)
	ok(diff < 0.001, "the snapped root equals Body.ground()'s root for this pose within 1 mm (diff %.3f mm)" % (diff * 1000.0))

	# ---- 2 only the root moves
	var a0 := angles(lift)
	var a1 := angles(snapped)
	var worst := 0.0
	for j in a0:
		for k in 3:
			worst = maxf(worst, absf(float(a0[j][k]) - float(a1[j][k])))
	ok(worst < 1e-6, "joint angles unchanged (worst difference %.6f deg over %d joints)" % [worst, a0.size()])
	var o0: Array = lift["offset"]
	var o1: Array = snapped["offset"]
	ok(absf(float(o0[0]) - float(o1[0])) < 1e-9 and absf(float(o0[2]) - float(o1[2])) < 1e-9, "root x and z unchanged")

	# ---- 3 kneeling: on the floor, sunk 5 cm, snapped back
	var knee_up := variant(S0, 0.0, {"thigh_l": 0.0, "thigh_r": 0.0, "calf_l": 120.0, "calf_r": 120.0})
	var kneel := variant(FloorSnap.snapped_pose(B, knee_up), -0.05)
	var g_k: Array = gaps(B, kneel)
	ok(float(g_k[1]) < -0.04 and float(g_k[1]) > -0.06, "anti-vacuity: the sunk kneel's knee is 5 cm under y = 0 (%.1f mm)" % (float(g_k[1]) * 1000.0))
	var kf := FloorSnap.snapped_pose(B, kneel)
	var g_kf: Array = gaps(B, kf)
	ok(absf(float(g_kf[1])) < 0.001, "kneeling sunk 5 cm: knee surface at 0 +- 1 mm (%.3f mm, lowest %s)" % [float(g_kf[1]) * 1000.0, g_kf[2]])
	ok(String(g_kf[2]) == "thigh_l" or String(g_kf[2]) == "thigh_r", "the lowest capsule is a thigh (the knee): %s" % g_kf[2])
	ok(float(g_kf[0]) > -0.001, "no sole is under its floor (sole gap %.3f mm)" % (float(g_kf[0]) * 1000.0))

	# ---- 4 a 3-card scene
	var S := Scene.new()
	S.add("stand up", lift)
	S.add("kneel", kneel)
	S.add("stand", S0)
	var before := []
	for c in S.cards:
		before.append(angles(c["pose"]))
	var moved := FloorSnap.snap_all(S, B)
	ok(moved == 2, "snap_all moved the 2 cards off the floor, and the stand already on it stayed (%d moved)" % moved)
	var card_ok := true
	var card_under := true
	var card_ang := true
	for i in S.cards.size():
		var d: Dictionary = S.cards[i]["pose"]
		var g: Array = gaps(B, d)
		var contact := minf(float(g[0]), float(g[1]))
		if absf(contact) > 0.001:
			card_ok = false
		if contact < -0.001:
			card_under = false
		var a2 := angles(d)
		for j in a2:
			for k in 3:
				if absf(float(before[i][j][k]) - float(a2[j][k])) > 1e-6:
					card_ang = false
	ok(card_ok, "every card's lowest contact on its floor at 0 +- 1 mm")
	ok(card_under, "no card has any part under its floor")
	ok(card_ang, "every card's joint angles unchanged")
	ok(FloorSnap.snap_all(S, B) == 0, "a second snap of the scene moves no card")

	# ---- 5 idempotent
	var again := FloorSnap.snapped_pose(B, snapped)
	ok(absf(float(again["offset"][1]) - float(snapped["offset"][1])) < 0.00001, "snapping a snapped pose again changes it by less than 0.01 mm")

	print("floorsnap: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
