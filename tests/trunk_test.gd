## godot --path . -s tests/trunk_test.gd     (TRUNK LEAN, Nick 10-23; scripts/trunk_lean.gd + smart_drag.gd's TRUNK_FOLLOW; needs a window)
## "the whole body moves, sometimes the back plus torso bend too much back or too much forward ... you can see it on kicks".
## Measured before any change (tools/trunk_drag_measure.gd, tools/trunk_measure.gd): a right foot dragged to kick height with
## smart drag on leaned the trunk 13.5-20.5 deg (pelvis tilt 14-21, twist 45, spine 8-23 summed); off, 0.0. BARS (stated
## before measuring the fix):
##   1 LIMB DRAG: through main's own input path (a press, 24 mouse moves, a release, as tests/drag_any_test.gd), with smart
##     drag AND keep balance ON (the app's defaults), the right foot dragged to kick height and the right hand forward to full
##     reach each change the trunk's pitch and roll (pelvis -> neck_01 against vertical, the hips' frame) by under 5 deg at
##     every mouse move (X = 5: the walking trunk's sagittal range 4.0 +- 1.8 deg, Chung et al. 2010, plus 1 for the
##     keep-balance counter-lean), the spine's summed bend and side change by at most 4.1 deg (TRUNK_FOLLOW), and the pelvis
##     does not tilt (bend, side unchanged within 0.01 deg); the instrument check: the dragged limb really moved over 15 cm
##   2 FLAGGED: a right roundhouse whose trunk leans 50 deg (+-2) back on its kick card is flagged TRUNK LEAN ("back", WARN,
##     with a Fix label); the same kick with the trunk 20 deg (+-2) back is not (the range: 40 back for a roundhouse)
##   3 THE FIX: Fixer.apply on it is kept, the finding is gone, the kick's window is inside the range at every frame, the
##     kicking foot's contact point (ball_r at the recognizer's contact frame) is within 3 cm of where it was, and both
##     ankles stay within 1 cm of where they were at every frame where they were down (planted); no card added or renamed
##   4 WALKS: templates/walk.json, templates/run.json and scenes/walk_bat.json have no TRUNK LEAN finding
##   5 THE TYPED MOVES: TextBlocking.build for front kick, roundhouse, side kick, jab, cross, hook: each window's worst lean is
##     PRINTED with its range (for the agent fixing the kick poses); the bar is only that every phrase builds and is read
extends SceneTree

var fails := 0
var t_start := Time.get_ticks_msec()
var B: Body
var stance := {"_l": [Vector3(0.12, 0.0152, 0.28), 0.0], "_r": [Vector3(-0.14, 0.0152, -0.18), 0.5]}
const BOTH := ["_l", "_r"]
const LEFT := ["_l"]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what + "   [%.0f s]" % ((Time.get_ticks_msec() - t_start) / 1000.0))
	if not c:
		fails += 1


func _ev_btn(pos: Vector2, down: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = pos
	e.global_position = pos
	return e


func _ev_move(pos: Vector2, rel: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	return e


func _find(m: Node, part: String, at: Vector2) -> Vector2:
	for r in [0, 6, 12, 18, 24, 32, 40]:
		for k in 16:
			var p: Vector2 = at + Vector2.from_angle(TAU * k / 16.0) * r
			if m._pick(p) == part:
				return p
	return at


## the weight-transfer test's guard stance (tests/weightxfer_test.gd): left foot forward, both fists at the chin
func pose(angs: Dictionary, plant := ["_l", "_r"]) -> Dictionary:
	for j in B.ang:
		B.ang[j] = Vector3.ZERO
	B.offset = Vector3(0, -0.04, 0)
	var base := {"thigh_l": Vector3(20, 0, 0), "calf_l": Vector3(15, 0, 0), "thigh_r": Vector3(-15, 0, 0), "calf_r": Vector3(10, 0, 0),
		"upperarm_l": Vector3(35, -55, 0), "lowerarm_l": Vector3(135, 0, 0), "upperarm_r": Vector3(35, -55, 0), "lowerarm_r": Vector3(135, 0, 0)}
	for j in base:
		B.ang[j] = base[j]
	for j in angs:
		B.ang[j] = B.clamp_ang(j, angs[j])
	B.fk()
	for sd in plant:
		B.plant(sd, stance[sd][0], stance[sd][1], true)
	return B.to_dict()


## a foot's heading on the floor (ankle -> ball, deg about vertical): bar 6 compares it before and after a drag
func heading(BB: Body, sd: String) -> float:
	var d: Vector3 = BB.P["ball" + sd] - BB.P["foot" + sd]
	return rad_to_deg(atan2(d.x, d.z))


func lean_now() -> float:
	return TrunkLean.lean_of(B.P["pelvis"], B.P["neck_01"], B.P["thigh_l"], B.P["thigh_r"], TrunkLean.rest_pitch(B)).x


## the kick card with its trunk `back` deg behind vertical: the pelvis tilted back (bisection on its bend), support replanted
func kick_pose(back: float) -> Dictionary:
	# the pelvis is bent only (side 0, twist 0): with the old twist 110 the bend's axis was turned, so the bend tipped the
	# trunk sideways and the bisection ran away (trunk -184, 10-23 run). Pelvis bend + tips the trunk forward (the sign
	# check in _init prints it), so a trunk still too far forward (lean above -back) needs a smaller bend
	var kick := {"pelvis": Vector3(0, 0, 0), "thigh_r": Vector3(20, 45, 0), "calf_r": Vector3(5, 0, 0)}
	var lo := -100.0
	var hi := 100.0
	for i in 30:
		var mid := (lo + hi) * 0.5
		kick["pelvis"] = Vector3(mid, 0, 0)
		pose(kick, LEFT)
		if lean_now() > -back:
			hi = mid
		else:
			lo = mid
	kick["pelvis"] = Vector3((lo + hi) * 0.5, 0, 0)
	var p := pose(kick, LEFT)
	print("     kick card: pelvis bend %.1f -> trunk %.1f deg (- = back)" % [(lo + hi) * 0.5, lean_now()])
	return p


func roundhouse(back: float) -> Scene:
	var S := Scene.new()
	S.name = "roundhouse"
	var g := pose({})
	var ch := pose({"pelvis": Vector3(0, 20, 20), "thigh_r": Vector3(40, 45, 0), "calf_r": Vector3(120, 0, 0)}, LEFT)
	var k := kick_pose(back)
	S.cards = [{"name": "guard", "pose": g, "move": -1.0, "hold": 0.3}, {"name": "chamber", "pose": ch, "move": 0.2, "hold": 0.0},
		{"name": "roundhouse", "pose": k, "move": 0.15, "hold": 0.1}, {"name": "guard", "pose": g, "move": 0.35, "hold": 0.3}]
	return S


func tl(S: Scene) -> Array:
	return Rulebook.check(S, B).filter(func(f): return f["rule"] == "TRUNK LEAN")


func show_windows(nm: String, S: Scene) -> void:
	for it in TrunkLean.windows(S, B):
		var nmz: Array = it["norm"]
		print("     %-22s card %d %-11s worst %-8s at %.2f s: pitch %+.1f roll %+.1f (range back %.0f fwd %.0f side %.0f) %s" % [nm, int(it["card"]) + 1,
			it["class"] if it["class"] != "" else "(general)", it["what"], it["t"], it["pitch"], it["roll"], nmz[0], nmz[1], nmz[2],
			("FLAG %.1f deg past" % it["over"]) if float(it["over"]) > 0.0 else ""])


func _init() -> void:
	B = Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	print("rest offset %.1f deg (taken off: standing tall reads 0)" % TrunkLean.rest_pitch(B))
	# the sign check: a plain upright pose, then the pelvis bent 30 deg each way (+ bend leans the trunk back, - forward)
	for sg in [0.0, -30.0, 30.0]:
		for j in B.ang:
			B.ang[j] = Vector3.ZERO
		B.ang["pelvis"] = Vector3(sg, 0, 0)
		B.fk()
		print("sign check: pelvis bend %+.0f -> trunk pitch %+.1f (rest offset taken off; + forward)" % [sg, lean_now()])
	for j in B.ang:
		B.ang[j] = Vector3.ZERO
	B.fk()

	# 2 + 3
	var bad := roundhouse(50.0)
	var good := roundhouse(20.0)
	show_windows("roundhouse 50 back", bad)
	show_windows("roundhouse 20 back", good)
	var fb := tl(bad)
	var fg := tl(good)
	var back_b: float = -float(TrunkLean.windows(bad, B)[2]["pitch"])
	ok(fb.size() >= 1 and fb[0]["what"] == "back" and fb[0]["sev"] == "WARN" and Fixer.label(fb[0], bad) != "" and fg.is_empty() and absf(back_b - 50.0) <= 2.0,
		"2 the roundhouse leaning %.1f back is flagged (%s); at 20 back it is not (%d findings)" % [back_b, fb[0]["msg"] if fb.size() > 0 else "no finding", fg.size()])
	if fb.size() > 0:
		var names := bad.cards.map(func(c): return c["name"])
		# before: the contact point and the ankles, frame by frame
		var clip0 := EventQuery.sample([{"S": bad, "B": B, "xf": Transform3D.IDENTITY, "name": "rh"}], 60.0, {"cross": false, "bal": false})
		var ts := bad.times()
		var r0 := MoveRecognizer.analyze(clip0, 0, int(round(float(ts[2][0]) * 60.0)), int(round(float(ts[2][2]) * 60.0)))
		var cf: int = r0["frames"]["contact"]
		var pt: String = r0["point"]
		var c0 := MoveRecognizer._p(clip0, 0, cf, pt)
		var pre_pose: Dictionary = (bad.cards[2]["pose"] as Dictionary).duplicate(true)
		var r := Fixer.apply(fb[0], bad, B)
		print("  %s" % r["msg"])
		show_windows("after the fix", bad)
		var clip1 := EventQuery.sample([{"S": bad, "B": B, "xf": Transform3D.IDENTITY, "name": "rh"}], 60.0, {"cross": false, "bal": false})
		var c1 := MoveRecognizer._p(clip1, 0, cf, pt)
		# the planted feet's mark: where the kick card itself puts them (the card the fix turned), not the pre-fix clip: the
		# original clip slides a planted ankle up to 15 cm between the chamber and the kick (its own transition), which
		# the fix now stops; comparing with that slide would measure the slide, not the fix
		var worst_foot := 0.0
		var mark := {}
		Scene.put(B, Moves._flat(pre_pose))
		B.fk()
		for k in [["foot_l", 1], ["foot_r", 2]]:
			if (B.P["ball" + k[0].substr(4)] as Vector3).y < 0.03:   # planted on the card (the kicking foot is up)
				mark[k[0]] = (B.P[k[0]] as Vector3)
		var dn1: PackedByteArray = clip1["down"][0]
		for f in mini(int(clip0["n"]), int(clip1["n"])):
			for k in [["foot_l", 1], ["foot_r", 2]]:
				if int(dn1[f]) & int(k[1]) and mark.has(k[0]):
					worst_foot = maxf(worst_foot, MoveRecognizer._p(clip1, 0, f, k[0]).distance_to(mark[k[0]]))
		var inside := TrunkLean.windows(bad, B).all(func(it): return float(it["over"]) <= 0.0)
		ok(r["kept"] and tl(bad).is_empty() and inside and c0.distance_to(c1) <= 0.03 and worst_foot <= 0.01 and bad.cards.map(func(c): return c["name"]) == names,
			"3 the fix is kept, the finding gone, every window inside (%s), the contact (%s) moved %.1f cm (bar 3), the planted ankles %.2f cm (bar 1)" % [inside, pt, c0.distance_to(c1) * 100.0, worst_foot * 100.0])
	else:
		ok(false, "3 no finding to fix")

	# 4
	var walks := ["res://templates/walk.json", "res://templates/run.json", "res://scenes/walk_bat.json"]
	var clean := true
	for p in walks:
		var S := Scene.new()
		S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(p)))
		var ff := tl(S)
		show_windows(p.get_file(), S)
		clean = clean and ff.is_empty()
	ok(clean, "4 the walk templates have no TRUNK LEAN finding")

	# 5
	var built := 0
	for ph in ["front kick", "roundhouse", "side kick", "jab", "cross", "hook"]:
		var bb := TextBlocking.build(ph, B)
		if not bb.get("ok", false):
			print("     '%s' did not build: %s" % [ph, bb.get("error", "?")])
			continue
		built += 1
		show_windows("typed '%s'" % ph, bb["scene"])
	ok(built == 6, "5 the six typed moves built and read (%d), their windows listed above" % built)

	# 1
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var MB: Body = m.B
	var base: Dictionary = MB.state()
	m.smart_drag = true
	m.keep_balance = true
	for part in ["foot_r", "hand_r"]:
		m.yaw = -90.0   # the right side view: forward and up in the view plane, the right limbs nearest
		m._cam()
		MB.set_state(base)
		MB.fk()
		m._refresh()
		await process_frame
		var cam: Camera3D = m.cam
		var start: Vector3 = MB.P[part]
		var target: Vector3
		if part == "foot_r":
			target = Vector3(start.x, (MB.P["thigh_r"] as Vector3).y, (MB.P["pelvis"] as Vector3).z + 0.45)
		else:
			var sh: Vector3 = MB.P["upperarm_r"]
			target = Vector3(start.x, sh.y, sh.z + 0.62)
		var cp: Array = MB.cap(part)
		var press_at := _find(m, part, cam.unproject_position(((cp[0] as Vector3) + (cp[1] as Vector3)) * 0.5))
		m._unhandled_input(_ev_btn(press_at, true))
		if m.sel != part:
			ok(false, "1 %s: the press picked %s" % [part, m.sel])
			m._unhandled_input(_ev_btn(press_at, false))
			continue
		var a0 := TrunkLean.angles(MB)
		var p0: Vector3 = MB.ang["pelvis"]
		var h0 := {"_l": heading(MB, "_l"), "_r": heading(MB, "_r")}
		var end_at: Vector2 = press_at + (cam.unproject_position(target) - cam.unproject_position(start))
		var prev := press_at
		var worst := {"pitch": 0.0, "roll": 0.0, "bend": 0.0, "side": 0.0}
		var tilt := 0.0
		for k in 24:
			var pos := press_at.lerp(end_at, float(k + 1) / 24.0)
			m._unhandled_input(_ev_move(pos, pos - prev))
			prev = pos
			var a := TrunkLean.angles(MB)
			for q in worst:
				worst[q] = maxf(worst[q], absf(a[q] - a0[q]))
			var pn: Vector3 = MB.ang["pelvis"]
			tilt = maxf(tilt, maxf(absf(pn.x - p0.x), absf(pn.y - p0.y)))
		var moved: float = ((MB.P[part] as Vector3) - start).length()
		m._unhandled_input(_ev_btn(end_at, false))
		# 6 PLANTED FEET KEEP THEIR HEADING (Nick 10-24: "feet always try to point to each other"): a limb drag with smart drag
		# on turned the hips, and the planted feet with them (8-9 deg in, measured); the dragged leg's own foot is not planted
		var turn := 0.0
		for sd in ["_l", "_r"]:
			if not part.ends_with(sd) or part.begins_with("hand"):
				turn = maxf(turn, absf(wrapf(heading(MB, sd) - float(h0[sd]), -180.0, 180.0)))
		ok(turn <= 1.0 and moved > 0.15, "6 %s dragged %.0f cm (smart on): the planted feet turned %.2f deg (bar 1)" % [part, moved * 100.0, turn])
		ok(worst["pitch"] < 5.0 and worst["roll"] < 5.0 and worst["bend"] <= 4.1 and worst["side"] <= 4.1 and tilt <= 0.01 and moved > 0.15,
			"1 %s dragged %.0f cm (smart + balance on): trunk pitch %.1f roll %.1f deg (bar 5), spine bend %.1f side %.1f (bar 4.1), pelvis tilt %.2f (bar 0.01)" % [
			part, moved * 100.0, worst["pitch"], worst["roll"], worst["bend"], worst["side"], tilt])
		m._undo()
	# 7 EASY: a drag moves only the part you drag (Nick 10-24: "while dragging an arm the whole body moves"); smart drag stays on
	# in the settings (Expert keeps it), Easy does not use it
	MB.set_state(base)
	MB.fk()
	m.easy.set_on(true, false)
	for i in 4:
		await process_frame
	var ecam: Camera3D = m.cam
	var keep := ["head", "pelvis", "foot_l", "foot_r", "hand_l"]
	var before := {}
	for j in keep:
		before[j] = MB.P[j]
	var hs: Vector3 = MB.P["hand_r"]
	var ecp: Array = MB.cap("hand_r")
	var e_at := _find(m, "hand_r", ecam.unproject_position(((ecp[0] as Vector3) + (ecp[1] as Vector3)) * 0.5))
	m._unhandled_input(_ev_btn(e_at, true))
	var e_prev := e_at
	for k in 24:
		var pos: Vector2 = e_at + Vector2(-4.0, -6.0) * (k + 1)
		m._unhandled_input(_ev_move(pos, pos - e_prev))
		e_prev = pos
	m._unhandled_input(_ev_btn(e_prev, false))
	var e_moved: float = ((MB.P["hand_r"] as Vector3) - hs).length()
	var others := 0.0
	for j in keep:
		others = maxf(others, ((MB.P[j] as Vector3) - (before[j] as Vector3)).length())
	ok(m.smart_drag and m.sel == "hand_r" and e_moved > 0.10 and others <= 0.002,
		"7 Easy: the right hand dragged %.0f cm moved the head, hips, feet and other hand at most %.2f cm (bar 0.2; smart drag setting still %s)" % [e_moved * 100.0, others * 100.0, m.smart_drag])
	m.easy.set_on(false, false)
	m.queue_free()
	await process_frame
	print("TRUNK TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
