## godot --headless --path . -s tests/mirror_test.gd      (GATES L4, L5, L6, L7)
## MIRROR: every joint of the mirrored pose sits where its twin sat, reflected (x -> -x), the weapon's knob and tip
## too; mirroring twice gives the pose back. A control: a WRONG mirror (angles copied without the reflection) must
## fail the same check. Also: copy/paste a pose between cards, the stepped preview, moving holds.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func refl(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, v.z)


## worst distance between the mirrored body's joints (and weapon ends) and the original's reflected
func mirror_err(a: Body, m: Body) -> Array:
	var worst := 0.0
	var at := ""
	for j in Body.ORDER:
		var e := (m.P[Body.twin(j)] as Vector3).distance_to(refl(a.P[j]))
		e = maxf(e, (m.E[Body.twin(j)] as Vector3).distance_to(refl(a.E[j])))
		if e > worst:
			worst = e
			at = j
	if a.wep_on:
		for u in [0.0, a.wep_len]:
			var e := (m.wep_point(u) as Vector3).distance_to(refl(a.wep_point(u)))
			if e > worst:
				worst = e
				at = "weapon %.2f" % u
	return [worst, at]


func load_scene(path: String) -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
	return S


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var M := Body.new()
	M.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var worst := 0.0
	var n := 0
	var clamped := 0
	var twice := 0.0
	for path in ["res://scenes/combo3.json", "res://scenes/bo_spin.json", "res://scenes/thrust.json", "res://scenes/walk_bat.json", "res://scenes/dodge_side.json"]:
		var S := load_scene(path)
		for c in S.cards:
			B.from_dict(c["pose"])
			M.from_dict(c["pose"])
			M.mirror_pose()
			var r := mirror_err(B, M)
			if r[0] > 0.001:
				print("     %s '%s': off by %.1f mm at %s" % [path.get_file(), c["name"], r[0] * 1000.0, r[1]])
				clamped += 1
			worst = maxf(worst, r[0])
			n += 1
			M.mirror_pose()
			for j in Body.ORDER:
				twice = maxf(twice, (M.P[j] as Vector3).distance_to(B.P[j]))
	ok(worst < 0.001, "MIRROR: %d card poses over 5 scenes; every joint end + the weapon's ends land on the original reflected: worst %.3f mm (%d poses over 1 mm)" % [n, worst * 1000.0, clamped])
	ok(twice < 1e-4, "  mirrored twice = the pose: worst %.4f mm over the same %d poses" % [twice * 1000.0, n])
	# the control: copying angles straight across (no reflection) must FAIL the same check
	var S := load_scene("res://scenes/combo3.json")
	B.from_dict(S.cards[9]["pose"])
	M.from_dict(S.cards[9]["pose"])
	for j in Body.ORDER:
		M.ang[j] = B.ang[Body.twin(j)]
	M.offset.x = -M.offset.x
	M.fk()
	ok(mirror_err(B, M)[0] > 0.05, "control: a naive mirror (angles copied, no reflection) is off by %.0f mm: the check can fail" % (mirror_err(B, M)[0] * 1000.0))

	# COPY / PASTE between cards: the body takes card 3's pose (picking it), Update on card 6 stores it
	S = load_scene("res://scenes/combo3.json")
	B.from_dict(S.cards[2]["pose"])
	S.cards[5]["pose"] = B.to_dict()
	B.from_dict(S.cards[5]["pose"])
	var A := Body.new()
	A.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	A.from_dict(S.cards[2]["pose"])
	var cp := 0.0
	for j in Body.ORDER:
		cp = maxf(cp, (A.P[j] as Vector3).distance_to(B.P[j]))
	ok(cp < 1e-4, "COPY/PASTE: card 3's pose stored on card 6 plays back identical (%.4f mm)" % (cp * 1000.0))

	# STEPPED: between cards the body is exactly the last card it arrived at; the rules still grade the real motion
	S = load_scene("res://scenes/combo3.json")
	var ts := S.times()
	S.stepped = true
	var t: float = (float(ts[3][1]) + float(ts[4][1])) * 0.5   # after card 4 arrives, before card 5 does
	S.apply(B, t)
	var ref := Body.new()
	ref.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	ref.from_dict(S.cards[3]["pose"])
	S._ground(ref)
	var st := 0.0
	for j in Body.ORDER:
		st = maxf(st, (ref.P[j] as Vector3).distance_to(B.P[j]))
	ok(st < 1e-3, "STEPPED: at %.2f s the body is card 4's pose exactly (%.3f mm), no in-between" % [t, st * 1000.0])
	var fs_step := var_to_str(Rulebook.check(S, B))
	S.stepped = false
	ok(fs_step == var_to_str(Rulebook.check(S, B)), "STEPPED is a view: Check grades the same either way")
	ok(not S.to_dict(B).has("stepped"), "STEPPED is never saved")

	# MOVING HOLDS: in a hold the upper body drifts; the hips and feet don't; no jump where the hold meets the move
	S = load_scene("res://scenes/combo3.json")
	S.moving_holds = true
	ts = S.times()
	var hi := -1
	var gap := 0.0   # the hold whose next card's head is farthest away (a drift toward a near twin reads as 0)
	for i in range(1, S.cards.size() - 1):
		if S._drifts(i, ts):
			A.from_dict(S.cards[i]["pose"])
			ref.from_dict(S.cards[i + 1]["pose"])
			var g: float = (A.P["head"] as Vector3).distance_to(ref.P["head"])
			if g > gap:
				gap = g
				hi = i
	var h0: float = ts[hi][1]
	var h1: float = ts[hi][2]
	S.apply(B, h0 + 0.001)
	var head0: Vector3 = B.P["head"]
	var feet0: Vector3 = B.P["ball_l"]
	S.apply(B, h1 - 0.001)
	var drift: float = (B.P["head"] as Vector3).distance_to(head0)
	var feet: float = (B.P["ball_l"] as Vector3).distance_to(feet0)
	ok(drift > 0.03 * gap and drift < 0.15 * gap, "MOVING HOLD: card %d '%s' held %.2f s: the head drifts %.1f cm of the %.0f cm to the next card (%.0f%%; the drift is %.0f%% of the angles)" % [hi + 1, S.cards[hi]["name"], h1 - h0, drift * 100.0, gap * 100.0, drift / gap * 100.0, Scene.HOLD_DRIFT * 100.0])
	ok(feet < 0.002, "  the planted foot stays: %.1f mm" % (feet * 1000.0))
	var jump := 0.0
	for k in [h0, h1]:
		S.apply(B, k - 1.0 / 240.0)
		var p0: Vector3 = B.P["hand_r"]
		S.apply(B, k + 1.0 / 240.0)
		jump = maxf(jump, (B.P["hand_r"] as Vector3).distance_to(p0))
	ok(jump < 0.01, "  no jump where the hold meets the moves (hand moves %.1f mm in 1/120 s across each seam)" % (jump * 1000.0))
	var saved := S.to_dict(B)
	ok(saved.get("moving_holds", false) == true, "  saved with the scene (on)")
	S.moving_holds = false
	ok(not S.to_dict(B).has("moving_holds"), "  off: not written (older scenes save byte-identical)")
	print("MIRROR TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
