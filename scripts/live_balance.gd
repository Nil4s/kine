## live_balance.gd - NEVER FALLS WHILE POSING (docs/INNOVATIONS.md N066). While a joint (or a hand / foot on IK) is dragged in
## the view, the body is kept over its feet LIVE: the hips slide (and the trunk counter-leans a little) so the centre of mass
## (Balance.com, de Leva masses) stays inside the support polygon of the feet that were planted at the press, those feet held.
## I24 (drag_balance.gd) is the reverse: there you drag the COM and the body follows; here you drag a limb and the COM is kept.
## REUSED: Balance (COM, footprint, hull, signed_dist), DragBalance.begin (the planted soles: ankle, foot / ball world turns, the
## knee pole, the leg length), DragBalance._leg (one leg back onto its sole) and DragBalance._rise_cap (how high the hips may be
## for both legs to still reach), DragBalance.edge_point.
## WHAT MOVES: the pelvis's offset (x, z; y only DOWN, as far as the legs need), spine_01..03 (a counter-lean slaved to the hip
## shift), and the planted legs' thigh / calf / foot / ball (their IK). NOTHING ELSE: the dragged joint keeps the angle the
## drag gave it (a hand / foot pulled on IK is put back on its target after the hips move: `redo`). The dragged leg is not a
## stance leg; a dragged spine joint turns the lean off.
## THE RULE: the margin kept is `keep` = the press pose's own margin, clamped to [KEEP_MIN, KEEP]. A pose that starts well
## inside is kept 2 cm inside; a pose the user put near an edge is not pulled to the middle (that would fight him), only kept
## from getting worse; a pose past the edge at the press is brought to KEEP_MIN. While the COM is inside by `keep` NOTHING is
## touched (the frame is the plain drag, bit for bit); past it the hips go the shortest way back to `keep` (the nearest point
## of the support polygon shrunk by keep). Every frame starts from the uncorrected pose, so pulling the arm back in brings the
## hips back to where they were.
## SOLVE: the COM's floor point moves with the hip shift u almost linearly (the upper body rides along, the legs rotate under
## it: gain ~0.8, re-estimated by the secant each step), so a few Newton steps on a 2-vector, warm-started from the last frame,
## are enough; each step is one FK, two analytic leg solves (LimbIK) and one COM. A shift whose legs cannot hold the soles within
## SOLE_TOL is cut back (bisection) and the drag says "can't keep balance: step or let go".
## COST (tests/livebal_test.gd, 10-23, this PC under other agents' load): median 0.8 ms (a hand pulled on IK) and 0.6 ms (an upper
## arm swung) per drag frame where it acted, 0.05 ms where it had nothing to do; a frame that cannot be held (the bisection) ~4 ms.
## The search runs with B.fast (limits, no contact search): a contact-checked reach alone is ~4 ms.
## ALT: Alt at the press, or held during the drag, lets him fall (the correction is taken back). On a hand / foot Alt already
## means "turn it, do not pull it" (main._drag_joint): that drag is a turn, with the balance off.
## OFF (the POSE toolbar's "Keep balance", saved as [pose] keep_balance): this file is never called; the drag is byte-identical to
## the code before N066 (the test's two drags, compared against the base tree).
class_name LiveBalance
extends RefCounted

const KEEP := 0.02        # m: the margin kept: BalanceView.EDGE (its amber band) = Balance.MARGIN_RES (what the model can tell)
const KEEP_MIN := 0.011   # m: the least kept (the N066 bar is >= 1 cm; 1 mm over it: the target is 3 mm further in, COM_TOL 2 mm)
const COM_TOL := 0.002    # m: the Newton steps stop when the COM is this close to its target (the target is 3 mm inside keep)
const SOLE_TOL := 0.003   # m: a planted sole may move this much in a frame (N066 bar: < 5 mm)
const ITERS := 4
const GAIN0 := 0.8        # COM shift per metre of hip shift, a first guess (HEURISTIC: the legs are ~1/3 of the mass and turn under
                          # the hips); the secant re-estimates it from the frame's own steps
const U_MAX := 0.30       # m: the hips never slide further than this from where they were at the press (HEURISTIC)
## THE COUNTER-LEAN: the neck goes this share of the hip shift further the same way, by bending the back (HEURISTIC: "a little";
## 10 cm of hip shift -> ~2.5 cm at the neck, ~3 deg of trunk lean; no measured source)
const LEAN_SHARE := 0.25
const LEAN_MAX := 8.0     # deg: the most the counter-lean bends the back, total over the three joints (HEURISTIC)
const SPINE := ["spine_01", "spine_02", "spine_03"]
const LEG := {"foot_l": ["thigh_l", "calf_l", "foot_l", "ball_l"], "foot_r": ["thigh_r", "calf_r", "foot_r", "ball_r"]}
const HINT := "can't keep balance: step or let go"


## the press: what is planted, the support, the margin to keep. {} = nothing to do for this drag (no foot down, the pelvis or a
## weapon is dragged, or every planted foot is on the dragged leg)
static func begin(B: Body, part: String) -> Dictionary:
	if part == "" or part == "pelvis" or part in Body.WEAPON or part in Body.WEAPON2 or not B.P.has(part):
		return {}
	var db := DragBalance.begin(B)
	var up := {}   # the joints above `part`, itself included: a leg among them is not a stance leg
	var j := part
	while j != "":
		up[j] = true
		j = B.parent.get(j, "")
	var refs: Dictionary = db["refs"]
	for foot in refs.keys():
		if up.has(foot) or up.has(LEG[foot][0]) or up.has(LEG[foot][1]) or up.has(LEG[foot][3]):
			refs.erase(foot)
	# a dragged ball (toe) joint is below the foot: its leg is moved by the drag, not planted
	for foot in refs.keys():
		if part == LEG[foot][3]:
			refs.erase(foot)
	if refs.is_empty():
		return {}
	var pts := PackedVector2Array()
	for foot in refs:
		pts.append_array(Balance.footprint(B, String(foot).right(2)))
	var poly := Balance.hull(pts)
	if poly.size() < 3:
		return {}
	var c0: Vector3 = Balance.com(B)
	var m0 := Balance.signed_dist(poly, Vector2(c0.x, c0.z))
	var keep := clampf(m0, KEEP_MIN, KEEP)
	var shr := Geometry2D.offset_polygon(poly, -(keep + 0.003))   # the target: 3 mm inside the kept line (COM_TOL + 1 mm of slack)
	var st := {"part": part, "db": db, "poly": poly, "keep": keep, "m0": m0, "target_poly": shr[0] if shr.size() > 0 else PackedVector2Array(),
		"off0": B.offset, "lean": not part in SPINE,
		"applied": false, "wrote": {}, "base": {}, "u": Vector2.ZERO, "gain": GAIN0, "joints": []}
	var js: Array = []
	if st["lean"]:
		js.append_array(SPINE)
	for foot in refs:
		js.append_array(LEG[foot])
	st["joints"] = js
	# the lean's map: the neck's floor shift per degree of back bend / side, shared over the three joints (measured on this pose)
	var M := []
	if st["lean"]:
		var keep_ang := {}
		for sp in SPINE:
			keep_ang[sp] = B.ang[sp]
		var n0: Vector3 = B.P["neck_01"]
		for ax in 2:
			for sp in SPINE:
				var a: Vector3 = keep_ang[sp]
				a[ax] += 1.0 / 3.0
				B.ang[sp] = a
			B.fk()
			var d: Vector3 = (B.P["neck_01"] as Vector3) - n0
			M.append(Vector2(d.x, d.z))
			for sp in SPINE:
				B.ang[sp] = keep_ang[sp]
		B.fk()
		var det: float = (M[0] as Vector2).cross(M[1])
		if absf(det) < 1e-8:
			st["lean"] = false
	st["leanM"] = M
	return st


## the correction of the last frame taken back where it is still ours (a joint someone else wrote since keeps theirs; a stance
## leg rewritten by another tool is put back on its sole): the body is the plain, uncorrected drag again
static func untake(B: Body, st: Dictionary, redo := Callable()) -> void:
	if st.is_empty() or not st["applied"]:
		return
	B.offset = st["off0"]
	var wrote: Dictionary = st["wrote"]
	var base: Dictionary = st["base"]
	var foreign := {}
	for j in wrote:
		var a: Vector3 = B.ang[j]
		var w: Vector3 = wrote[j]
		if a.x == w.x and a.y == w.y and a.z == w.z:
			B.ang[j] = base[j]
		else:
			foreign[j] = true
	B.fk()
	var was_fast := B.fast
	B.fast = true
	for foot in (st["db"]["refs"] as Dictionary):
		for j in LEG[foot]:
			if foreign.has(j):
				DragBalance._leg(B, st["db"], foot, 0.0)
				break
	st["applied"] = false
	st["wrote"] = {}
	if redo.is_valid():
		redo.call()
	B.fast = was_fast


## one candidate: the hips shifted by u (floor x, z), the back counter-leaned, the stance legs back on their soles, the pulled
## end back on its target. Returns [COM, worst sole miss m]
static func _pose(B: Body, st: Dictionary, u: Vector2, redo: Callable) -> Array:
	var base: Dictionary = st["base"]
	var db: Dictionary = st["db"]
	var drop := minf(0.0, DragBalance._rise_cap(db, u.x, u.y))
	B.offset = (st["off0"] as Vector3) + Vector3(u.x, drop, u.y)
	if st["lean"]:
		var M: Array = st["leanM"]
		var n := u * LEAN_SHARE   # the neck's extra floor shift wanted
		var a: Vector2 = M[0]
		var b: Vector2 = M[1]
		var det := a.cross(b)
		var d := Vector2(n.cross(b) / det, a.cross(n) / det)   # degrees of (bend, side): a*d.x + b*d.y = n
		if d.length() > LEAN_MAX:
			d = d * (LEAN_MAX / d.length())
		for sp in SPINE:
			B.ang[sp] = B.clamp_ang(sp, (base[sp] as Vector3) + Vector3(d.x, d.y, 0.0) / 3.0)
	for foot in (db["refs"] as Dictionary):
		for j in LEG[foot]:
			B.ang[j] = base[j]
	B.fk()
	var sole := 0.0
	for foot in (db["refs"] as Dictionary):
		sole = maxf(sole, float(DragBalance._leg(B, db, foot, 0.0)["err"]))
	if redo.is_valid():
		redo.call()
	return [Balance.com(B), sole]


## ONE DRAG FRAME, after the drag's own edit: take back the last correction, measure, and if the COM is past `keep` slide the
## hips. redo: puts a pulled hand / foot back on its target (the hips moved it); empty for an angle drag.
## Returns {"applied", "margin" (m, after), "margin_raw" (m, the plain drag's), "keep", "u" (Vector2 m), "lean" (deg), "sole"
## (m), "partial" (the best that holds, short of keep), "hint", "ms", "part_drift" (deg the dragged joint moved: always 0)}
static func step(B: Body, st: Dictionary, redo := Callable()) -> Dictionary:
	if st.is_empty():
		return {}
	var t0 := Time.get_ticks_usec()
	var part: String = st["part"]
	untake(B, st, redo)
	var asked: Vector3 = B.ang[part]
	var poly: PackedVector2Array = st["poly"]
	var keep: float = st["keep"]
	var c := Balance.com(B)
	var q := Vector2(c.x, c.z)
	var raw := Balance.signed_dist(poly, q)
	var out := {"applied": false, "margin": raw, "margin_raw": raw, "keep": keep, "u": Vector2.ZERO, "lean": 0.0, "sole": 0.0,
		"partial": false, "hint": ""}
	if raw >= keep - 1e-4:
		st["u"] = Vector2.ZERO
		out["ms"] = float(Time.get_ticks_usec() - t0) / 1000.0
		out["part_drift"] = 0.0
		return out
	# the target: the nearest point of the support shrunk by keep
	var tp: PackedVector2Array = st["target_poly"]
	var tgt: Vector2
	if tp.size() >= 3:
		tgt = DragBalance.edge_point(tp, q)
	else:
		tgt = Vector2.ZERO
		for p in poly:
			tgt += p
		tgt /= float(poly.size())
	# the joints this frame may write, as the plain drag left them
	var base := {}
	for j in st["joints"]:
		base[j] = B.ang[j]
	st["base"] = base
	# limits only (no contact search) for everything this step does, as SmartDrag.plant: a contact-checked reach is ~4 ms (measured,
	# tests/livebal_test.gd), twice the frame's whole budget. The drag's own edit next frame runs with the contacts on again
	var was_fast := B.fast
	B.fast = true
	var gain: float = st["gain"]
	var u: Vector2 = st["u"]   # the warm start: last frame's shift (the mouse moved a little)
	if u == Vector2.ZERO:
		u = (tgt - q) / gain
	var prev := Vector2(NAN, NAN)
	var prev_c := Vector2.ZERO
	var res: Array = []
	var at := Vector2(NAN, NAN)   # the u the body is posed at now
	for it in ITERS:
		if u.length() > U_MAX:
			u *= U_MAX / u.length()
		res = _pose(B, st, u, redo)
		at = u
		var cn := Vector2((res[0] as Vector3).x, (res[0] as Vector3).z)
		var e := tgt - cn
		if not is_nan(prev.x):
			var du := u - prev
			if du.length_squared() > 1e-10:
				gain = clampf((cn - prev_c).dot(du) / du.length_squared(), 0.3, 1.5)
		if e.length() < COM_TOL or (u.length() >= U_MAX - 1e-6 and e.dot(u) > 0.0):
			break
		prev = u
		prev_c = cn
		u += e / gain
	if u.length() > U_MAX:
		u *= U_MAX / u.length()
	if u != at:
		res = _pose(B, st, u, redo)
	# the legs cannot hold the soles that far: the largest share of u that they can (bisection)
	if float(res[1]) > SOLE_TOL:
		var lo := 0.0
		var hi := 1.0
		for i in 4:   # 1/16 of the shift: ~3 ms more on a frame that cannot be held (measured), the rest stay < 2 ms
			var f := (lo + hi) * 0.5
			if float(_pose(B, st, u * f, redo)[1]) <= SOLE_TOL:
				lo = f
			else:
				hi = f
		u *= lo
		res = _pose(B, st, u, redo)
		out["partial"] = true
	B.fast = was_fast
	st["gain"] = gain
	st["u"] = u
	var wrote := {}
	for j in st["joints"]:
		wrote[j] = B.ang[j]
	st["wrote"] = wrote
	st["applied"] = true
	var cf: Vector3 = res[0]
	var mg := Balance.signed_dist(poly, Vector2(cf.x, cf.z))
	if mg < keep - 0.003:
		out["partial"] = true
	var lean := 0.0
	if st["lean"]:
		lean = ((B.ang["spine_01"] as Vector3) - (base["spine_01"] as Vector3)).length() * 3.0
	out["applied"] = true
	out["margin"] = mg
	out["u"] = u
	out["lean"] = lean
	out["sole"] = res[1]
	out["part_drift"] = ((B.ang[part] as Vector3) - asked).length()
	if out["partial"]:
		out["hint"] = HINT
	out["ms"] = float(Time.get_ticks_usec() - t0) / 1000.0
	return out


## the drag's status words (appended to the drag's own line): "" while nothing was needed
static func words(r: Dictionary) -> String:
	if r.is_empty() or not r.get("applied", false):
		return ""
	var u: Vector2 = r["u"]
	var s := "     BALANCE: hips %.1f cm over, %.1f cm inside the feet" % [u.length() * 100.0, float(r["margin"]) * 100.0]
	if String(r.get("hint", "")) != "":
		s += "  -  " + String(r["hint"]) + " (Alt+drag lets him fall)"
	return s
