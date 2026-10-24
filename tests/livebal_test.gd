## godot --path . -s tests/livebal_test.gd     (N066 never falls while posing, scripts/live_balance.gd; needs a window: main's input path)
## The mannequin stands on the floor, arms hanging 70 deg down, his back leaned toward his right and his hips slid by I24's DragBalance
## so his COM is 1.05 cm inside the RIGHT edge of his feet: a right arm raised out sideways (~1.3 cm of COM) WOULD tip him (the
## instrument can move: the OFF and Alt drags below show it does). Two drags with REAL mouse events (main._unhandled_input, as
## tests/i12_test.gd), 16 moves each: the right HAND pulled on IK to 1 m out sideways at shoulder height (full reach), and the right
## UPPER ARM swung out to the T by its middle (PartDrag, an angle drag).
## BARS, written before measuring (the N066 spec):
##  (1) Keep balance ON, both drags: the balance acts, at every move the COM is inside the planted feet's support by >= 1 cm
##      (Balance.signed_dist), and every sole point (ankle, ball joint, toe tip of both feet) moved < 0.5 cm from the press
##  (2) the dragged joint keeps the angle the drag asked: every frame LiveBalance.step leaves it within 0.1 deg (part_drift), and,
##      unit level, an upper arm set to a requested angle (hanging -> the T, 12 steps) is that angle after each step, +-0.1 deg
##  (3) Alt held at the press (balance off for that drag; the upper-arm drag, since on a hand Alt already means "turn the hand"):
##      the COM leaves the support (margin < 0)
##  (4) Keep balance OFF: LiveBalance never runs (no step result, no BALANCE words); the same drag again gives the same state string;
##      both final states are written to TMP/livebal_off_state.txt for the one-off comparison with the base tree (w4-integ ee8e403,
##      the same setup and drags without this item: byte-identical, checked 10-23 with cmp; see the N066 commit)
##  (5) the balance solve takes < 2 ms median per frame (LiveBalance.step's own clock, frames where it acted and all frames)
##  (6) one undo step per drag; Ctrl+Z restores B.state() bit for bit
##  (7) the far case: from a pose whose hips I24 alone slid to the planted legs' reach (COM 1.05 cm in), the arm out to the T needs
##      more hip than the legs give: the step says "can't keep balance: step or let go", does the best partial (margin better than the
##      plain pose by > 2 mm) and the feet still hold (<= SOLE_TOL)
##  (8) with Smart drag (I12) on as well, the upper-arm drag still keeps the COM >= 1 cm inside and the feet < 0.5 cm
extends SceneTree

var fails := 0
var TMPD := OS.get_environment("TMP").replace("\\", "/") + "/"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _ev_btn(pos: Vector2, down: bool, alt := false) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = pos
	e.global_position = pos
	e.alt_pressed = alt
	return e


func _ev_move(pos: Vector2, rel: Vector2, alt := false) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	e.alt_pressed = alt
	return e


func _find(m: Node, part: String, at: Vector2) -> Vector2:
	for r in [0, 4, 8, 12, 18, 24, 32]:
		for k in 16:
			var p: Vector2 = at + Vector2.from_angle(TAU * k / 16.0) * r
			if m._pick(p) == part:
				return p
	return at


func soles(B: Body) -> Dictionary:
	var out := {}
	for sd in ["_l", "_r"]:
		out["a" + sd] = B.P["foot" + sd]
		out["b" + sd] = B.P["ball" + sd]
		out["t" + sd] = B.E["ball" + sd]
	return out


func sole_err(a: Dictionary, b: Dictionary) -> float:
	var w := 0.0
	for k in a:
		w = maxf(w, ((a[k] as Vector3) - (b[k] as Vector3)).length())
	return w


func median(a: Array) -> float:
	if a.is_empty():
		return NAN
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2]) if b.size() % 2 == 1 else (float(b[b.size() / 2 - 1]) + float(b[b.size() / 2])) * 0.5


## a drag by main's input path: press, 16 moves, release. Per move: the margin, the sole error, the step's ms and drift
func drag(m: Node, poly: PackedVector2Array, from: Vector2, to: Vector2, alt := false) -> Dictionary:
	var B: Body = m.B
	var s0 := soles(B)
	var out := {"margins": [], "sole": 0.0, "ms": [], "ms_acted": [], "drift": 0.0, "steps": 0, "hint": "", "words": false, "partial": false}
	m._unhandled_input(_ev_btn(from, true, alt))
	var prev := from
	for k in 16:
		var pos := from.lerp(to, float(k + 1) / 16.0)
		m._unhandled_input(_ev_move(pos, pos - prev, alt))
		prev = pos
		var c := Balance.com(B)
		(out["margins"] as Array).append(Balance.signed_dist(poly, Vector2(c.x, c.z)))
		out["sole"] = maxf(out["sole"], sole_err(s0, soles(B)))
		var r: Dictionary = m._lb_r
		if not r.is_empty():
			out["steps"] += 1
			(out["ms"] as Array).append(float(r["ms"]))
			if r["applied"]:
				(out["ms_acted"] as Array).append(float(r["ms"]))
			out["drift"] = maxf(out["drift"], float(r["part_drift"]))
			if String(r["hint"]) != "":
				out["hint"] = r["hint"]
		if String(m.ui_status.text if "ui_status" in m and m.ui_status != null else "").contains("BALANCE"):
			out["words"] = true
	out["last"] = (m._lb_r as Dictionary).duplicate()
	m._unhandled_input(_ev_btn(to, false, alt))
	return out


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var B: Body = m.B
	m.playing = false
	B.wep_on = false
	for j in B.ang:
		B.ang[j] = Vector3.ZERO
	B.offset = Vector3.ZERO
	B.fk()
	# the arms hang (the zero pose is a T): each upper arm 70 deg down (the hand clear of the thigh, so a press picks it), the sign that puts its hand below its shoulder
	for sd in ["_l", "_r"]:
		var best := 0.0
		var lowest := INF
		for sgn in [1.0, -1.0]:
			B.set_ang("upperarm" + sd, Vector3(0, 70.0 * sgn, 0))
			B.fk()
			if (B.P["hand" + sd] as Vector3).y < lowest:
				lowest = (B.P["hand" + sd] as Vector3).y
				best = sgn
		B.set_ang("upperarm" + sd, Vector3(0, 70.0 * best, 0))
	B.fk()
	B.ground()
	B.fk()
	# THE PRESS POSE: his COM 1.05 cm inside the right edge of his feet, so a right arm out sideways (~1.3 cm of COM) WOULD tip him.
	# His back is leaned fully toward his right (spine_01..03 side, 7 deg each: 2.7 cm of COM), then I24 (DragBalance) slides the
	# hips the rest of the way (~15 cm). (I24 alone, all by the hips, is the far case, 7: there the legs have ~0.8 cm left)
	var st0 := DragBalance.begin(B)
	var poly: PackedVector2Array = st0["poly"]
	var c0: Vector3 = st0["com0"]
	var right := Vector2((B.P["upperarm_r"] as Vector3).x - (B.P["upperarm_l"] as Vector3).x, (B.P["upperarm_r"] as Vector3).z - (B.P["upperarm_l"] as Vector3).z).normalized()
	var q0 := Vector2(c0.x, c0.z)
	var rest: Dictionary = B.state()
	var lean_sgn := 0.0
	var best_x := -INF
	for sgn in [1.0, -1.0]:
		B.set_state(rest)
		for sp in ["spine_01", "spine_02", "spine_03"]:
			B.set_ang(sp, B.clamp_ang(sp, Vector3(0, 90.0 * sgn, 0)))
		B.fk()
		var cl := Balance.com(B)
		var dx := (Vector2(cl.x, cl.z) - q0).dot(right)
		if dx > best_x:
			best_x = dx
			lean_sgn = sgn
	B.set_state(rest)
	for sp in ["spine_01", "spine_02", "spine_03"]:
		B.set_ang(sp, B.clamp_ang(sp, Vector3(0, 90.0 * lean_sgn, 0)))
	B.fk()
	var to_edge := func(B2: Body) -> void:   # I24: the COM to 1.05 cm inside the right edge, by the hips
		var s2 := DragBalance.begin(B2)
		var c2: Vector3 = s2["com0"]
		var q2 := Vector2(c2.x, c2.z)
		var lo := 0.0
		var hi := 0.5
		for i in 30:
			var f := (lo + hi) * 0.5
			if Balance.signed_dist(poly, q2 + right * f) > 0.0105:
				lo = f
			else:
				hi = f
		var goal := q2 + right * lo
		DragBalance.drag(B2, s2, Vector3(goal.x, NAN, goal.y))
		B2.fk()
	to_edge.call(B)
	var cs := Balance.com(B)
	print("     press pose: rest margin %.1f cm; back leaned %.1f deg toward his right (COM %.1f cm over), hips slid %.1f cm by I24: margin %.2f cm" % [
		Balance.signed_dist(poly, q0) * 100.0, (B.ang["spine_01"] as Vector3).length() * 3.0, best_x * 100.0, (B.offset - (rest["offset"] as Vector3)).length() * 100.0,
		Balance.signed_dist(poly, Vector2(cs.x, cs.z)) * 100.0])
	ok(absf(Balance.signed_dist(poly, Vector2(cs.x, cs.z)) - 0.0105) < 0.002, "(setup) the press pose is 1.05 cm inside the edge (+-2 mm)")
	var leaned: Dictionary = B.state()
	# the far case's pose (7): I24 alone moves the hips to put the COM 1.05 cm inside the right edge: the planted legs at their reach
	B.set_state(rest)
	B.fk()
	to_edge.call(B)
	var edge_pose: Dictionary = B.state()
	B.set_state(leaned)
	B.fk()
	m.sel = "spine_03"
	m.hover_part = ""
	m._refresh()
	m._turn_to(0.0, -10.0, 3.6, Vector3(0, 0.95, 0), false)
	for i in 4:
		await process_frame
	var base: Dictionary = B.state()
	var cam: Camera3D = m.cam
	# the drag: the right hand from where it is to 1 m out sideways from the shoulder at shoulder height (beyond full reach)
	var hp: Vector3 = B.P["hand_r"]
	var press_at := _find(m, "hand_r", cam.unproject_position(hp))
	var sh: Vector3 = B.P["upperarm_r"]
	var far := sh + Vector3(right.x, 0.0, right.y) * 1.0
	var end_at := press_at + (cam.unproject_position(far) - cam.unproject_position(hp))
	print("     drag: press %s (picks %s), to %s" % [press_at, m._pick(press_at), end_at])

	# the second drag: the right UPPER ARM swung out to the T by its middle (an angle drag: PartDrag puts its handle on the mouse)
	var cp: Array = B.cap("upperarm_r")
	var arm_at := _find(m, "upperarm_r", cam.unproject_position(((cp[0] as Vector3) + (cp[1] as Vector3)) * 0.5))
	m._unhandled_input(_ev_btn(arm_at, true))
	var pd: Dictionary = m._pd
	var grab_px: Vector2 = arm_at - cam.unproject_position(PartDrag.handle(B, pd))
	m._unhandled_input(_ev_btn(arm_at, false))
	m._undo()
	B.set_state(base)
	B.set_ang("upperarm_r", Vector3.ZERO)
	B.fk()
	B.shoulder_follow("_r")
	var arm_end: Vector2 = cam.unproject_position(PartDrag.handle(B, pd)) + grab_px
	B.set_state(base)
	B.fk()
	m._refresh()
	print("     drags: hand press %s (picks %s) -> %s; upper arm press %s (picks %s) -> %s" % [press_at, m._pick(press_at), end_at, arm_at, m._pick(arm_at), arm_end])
	m.keep_balance = true
	var states_on := {}
	for which in ["hand", "arm"]:
		B.set_state(base)
		B.fk()
		m._refresh()
		var u0: int = m.undo.size()
		var on := drag(m, poly, press_at if which == "hand" else arm_at, end_at if which == "hand" else arm_end)
		var ml: float = (on["margins"] as Array).min()
		var last: Dictionary = on["last"]
		var extra := ""
		if which == "hand":
			var reach := ((B.P["hand_r"] as Vector3) - (B.P["upperarm_r"] as Vector3)).length()
			var arm_len := ((B.p0["lowerarm_r"] as Vector3) - (B.p0["upperarm_r"] as Vector3)).length() + ((B.p0["hand_r"] as Vector3) - (B.p0["lowerarm_r"] as Vector3)).length()
			extra = "hand at %.0f %% of the arm's length" % (reach / arm_len * 100.0)
			ok(reach / arm_len > 0.95, "(1) hand: the hand went to full reach (%.0f %% of the arm's length)" % (reach / arm_len * 100.0))
		else:
			var hd := ((B.P["hand_r"] as Vector3) - (B.P["upperarm_r"] as Vector3)).normalized()
			extra = "arm %.0f deg from horizontal-out" % rad_to_deg(hd.angle_to(Vector3(right.x, 0, right.y)))
			ok(rad_to_deg(hd.angle_to(Vector3(right.x, 0, right.y))) < 25.0, "(1) arm: the arm is out sideways (%s)" % extra)
		print("     ON %s: worst margin %.2f cm, final %.2f cm, soles %.2f mm, hips %.1f cm, lean %.2f deg, %s, %d steps (%d acted)" % [which,
			ml * 100.0, float((on["margins"] as Array)[-1]) * 100.0, float(on["sole"]) * 1000.0, (last.get("u", Vector2.ZERO) as Vector2).length() * 100.0,
			float(last.get("lean", 0.0)), extra, on["steps"], (on["ms_acted"] as Array).size()])
		print("     solve ms per frame (%s): %s" % [which, str(on["ms"])])
		ok((on["ms_acted"] as Array).size() >= 4, "(1) %s: the balance acted (%d of 16 moves)" % [which, (on["ms_acted"] as Array).size()])
		ok(ml >= 0.01, "(1) %s: COM inside the support by >= 1 cm at every move (worst %.2f cm)" % [which, ml * 100.0])
		ok(float(on["sole"]) < 0.005, "(1) %s: the feet moved < 0.5 cm (worst sole point %.2f mm)" % [which, float(on["sole"]) * 1000.0])
		ok(float(on["drift"]) <= 0.1, "(2) %s: the dragged joint keeps the drag's angle every frame (worst drift %.5f deg)" % [which, float(on["drift"])])
		var mso: float = median(on["ms_acted"])
		var msa: float = median(on["ms"])
		ok(mso < 2.0 and msa < 2.0, "(5) %s: the balance solve, median %.3f ms on frames it acted, %.3f ms on all frames (bar < 2)" % [which, mso, msa])
		ok(m.undo.size() == u0 + 1, "(6) %s: one undo step per drag (%d -> %d)" % [which, u0, m.undo.size()])
		states_on[which] = str(B.state())
		m._undo()
		ok(str(B.state()) == str(base), "(6) %s: Ctrl+Z restores the body bit for bit" % which)

	# ---- (3) Alt at the press: he may fall (the upper-arm drag: on a hand, Alt already means "turn the hand", see live_balance.gd)
	B.set_state(base)
	B.fk()
	m._refresh()
	var alt := drag(m, poly, arm_at, arm_end, true)
	var ma: float = (alt["margins"] as Array).min()
	print("     ALT arm: worst margin %.2f cm, steps %d" % [ma * 100.0, alt["steps"]])
	ok(ma < 0.0 and alt["steps"] == 0, "(3) Alt+drag: balance off, the COM leaves the support (worst margin %.2f cm)" % (ma * 100.0))
	m._undo()

	# ---- (4) Keep balance OFF: the old drag
	m.keep_balance = false
	var offs := {}
	for which in ["hand", "arm"]:
		B.set_state(base)
		B.fk()
		m._refresh()
		var off := drag(m, poly, press_at if which == "hand" else arm_at, end_at if which == "hand" else arm_end)
		offs[which] = str(B.state())
		var mo: float = (off["margins"] as Array).min()
		print("     OFF %s: worst margin %.2f cm (the plain drag)" % [which, mo * 100.0])
		ok(off["steps"] == 0 and not off["words"], "(4) %s, toggle off: LiveBalance never ran (%d steps), no BALANCE words" % [which, off["steps"]])
		ok(mo < 0.0, "(4) %s (control): the plain drag really tips him (worst margin %.2f cm), so the ON numbers are the balance's doing" % [which, mo * 100.0])
		ok(offs[which] != states_on[which], "(4) %s (control): ON differs from OFF" % which)
		m._undo()
		B.set_state(base)
		B.fk()
		m._refresh()
		drag(m, poly, press_at if which == "hand" else arm_at, end_at if which == "hand" else arm_end)
		ok(str(B.state()) == offs[which], "(4) %s, toggle off is deterministic: the same drag again, the same state string" % which)
		m._undo()
	var f := FileAccess.open(TMPD + "livebal_off_state.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(offs["hand"] + "\n" + offs["arm"])
		f.close()

	# ---- (2) unit: a requested upper-arm angle stays exactly what was asked
	B.set_state(base)
	B.fk()
	var lst := LiveBalance.begin(B, "upperarm_r")
	var a0: Vector3 = B.ang["upperarm_r"]
	var worst_d := 0.0
	var worst_mu := INF
	var acted := 0
	var want := Vector3.ZERO
	var lean := 0.0
	for k in 12:
		want = B.clamp_ang("upperarm_r", a0.lerp(Vector3.ZERO, float(k + 1) / 12.0))   # from hanging (70 deg down) to straight out: the T
		B.set_ang("upperarm_r", want)
		B.fk()
		var r := LiveBalance.step(B, lst)
		acted += 1 if r["applied"] else 0
		worst_d = maxf(worst_d, ((B.ang["upperarm_r"] as Vector3) - want).length())
		worst_mu = minf(worst_mu, float(r["margin"]))
		lean = float(r["lean"])
	print("     unit: upper arm asked %s, acted %d of 12, worst margin %.2f cm, last lean %.2f deg" % [want, acted, worst_mu * 100.0, lean])
	ok(worst_d <= 0.1, "(2) unit: the upper arm is the requested angle after every step (worst %.5f deg)" % worst_d)
	ok(lean > 0.0, "(1) unit: the back counter-leans a little (%.2f deg)" % lean)

	# ---- (7) the far case: from the pose whose hips I24 already pushed to the legs' reach, the arm out to the T
	B.set_state(edge_pose)
	B.fk()
	var fst := LiveBalance.begin(B, "upperarm_r")
	B.set_ang("upperarm_r", Vector3.ZERO)
	B.fk()
	var cc := Balance.com(B)
	var plain := Balance.signed_dist(fst["poly"], Vector2(cc.x, cc.z))
	var rr := LiveBalance.step(B, fst)
	print("     far: plain margin %.2f cm -> after the step %.2f cm, hips %.2f cm, partial %s, %.2f ms, hint '%s'" % [plain * 100.0, float(rr.get("margin", NAN)) * 100.0,
		(rr.get("u", Vector2.ZERO) as Vector2).length() * 100.0, rr.get("partial", false), float(rr.get("ms", NAN)), rr.get("hint", "")])
	ok(String(rr.get("hint", "")) == LiveBalance.HINT, "(7) the far case says '%s'" % LiveBalance.HINT)
	ok(float(rr.get("margin", -INF)) > plain + 0.002, "(7) and still does the best partial (margin %.2f -> %.2f cm)" % [plain * 100.0, float(rr.get("margin", NAN)) * 100.0])
	ok(float(rr.get("sole", 1.0)) <= LiveBalance.SOLE_TOL + 1e-6, "(7) the feet still held (%.2f mm)" % (float(rr.get("sole", 1.0)) * 1000.0))
	# ---- (8) with Smart drag on too (its model learned from poses/ + scenes/, the test's own cache file)
	B.set_state(base)
	B.fk()
	m._refresh()
	m.keep_balance = true
	m.smart_drag = true
	m.smart_follow = 0.6
	var sm := drag(m, poly, arm_at, arm_end)
	var msm: float = (sm["margins"] as Array).min()
	print("     SMART + balance, arm: worst margin %.2f cm, soles %.2f mm, %d steps (%d acted), median %.3f ms" % [msm * 100.0, float(sm["sole"]) * 1000.0,
		sm["steps"], (sm["ms_acted"] as Array).size(), median(sm["ms"])])
	ok(msm >= 0.01 and float(sm["sole"]) < 0.005, "(8) smart drag + keep balance: COM >= 1 cm inside (%.2f cm), feet < 0.5 cm (%.2f mm)" % [msm * 100.0, float(sm["sole"]) * 1000.0])
	m._undo()
	m.smart_drag = false
	print("N066 livebal: %d failures" % fails)
	quit(1 if fails > 0 else 0)
