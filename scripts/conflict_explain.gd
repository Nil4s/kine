## conflict_explain.gd - THE CONFLICT EXPLAINER (docs/INNOVATIONS.md N006). An agent hands Kine a set of WISHES for one moment
## (N002 assertion lines, plus "both feet planted" and "lean 40 deg forward") and, when they can't all hold, Kine names the
## SMALLEST set that clash and what it costs to free each one:
##   "right fist needs 12.0 cm more reach: step 12.0 cm forward, or lean 5.1 deg forward over the feet, or drop 'both feet planted'"
## WHY: a blind agent that gets "FAIL" on three lines at once can't tell which one to give up. Re-trying at random wastes its
## budget; the minimal clash plus a number per way out turns it into one decision.
##
## ONE MOMENT. Every wish is read at one time: params t, or card N (its arrive time), else the first line's "at t" window,
## else 0. A line's own window only picks that moment (stated: the explainer is a pose question, not a clip question), so
## "speed" lines are refused (a speed needs neighbouring frames that the solver does not move).
##
## THE SOLVER (what Kine may change to make the wishes hold; everything else stays as the scene has it at t):
##   1 POSTURE PINS. An angle line ("right elbow below 60 deg") puts that joint at the nearest angle it allows, within the
##     joint's limits (Body.clamp_ang). A LEAN wish tips the whole body about the planted ankles (the axis through the
##     ankle midpoint, square to his forward, N007's body frame), the trunk and legs kept as they are, so "lean 40" adds
##     40 deg to the ankles-to-neck line. After a pin the legs that were on the floor are put back on their soles
##     (DragBalance._leg: leg IK onto the start's ankle, the foot and toe keep their world turn; the knee swings tried as
##     drag balance tries them). A pin on a joint of a leg's chain leaves that leg as pinned.
##   2 THE REACH. A "touches" / "at most D from" wish whose first thing is one of the hero's hands or feet (fist, hand,
##     foot, wrist, ankle, hand_r, ...) is reached by that limb's IK (LimbIK.solve, pole from its current bend): the wrist /
##     ankle is aimed so the far end of the fist / foot capsule (plus its radius) lands on the target point. Out of reach
##     the limb straightens toward it (LimbIK's closest pose) and the gap left is the SHORTFALL.
##   3 A STEP. If a reach still fails, the whole body slides along the floor toward the target (the horizontal line from
##     the limb's root, the shoulder / hip, to the target) by the SMALLEST distance that makes it hold (5 cm strides, then bisection
##     to 0.4 mm; at most STEP_MAX). The feet go with it, so a "planted" wish then measures that slide.
##   A pin on a joint of a reaching limb is overwritten by the reach and then measured, so that clash shows up as a miss.
##   The wishes hold together when some pose of 1-3 has every miss <= 0 (BodyAssert's bars: touch 1 cm, a planted toe base
##   within 2 cm of its height and 2.5 cm of where it stood, the COM's floor point inside the support polygon). A lean is
##   NOT tried to rescue a reach: it changes the posture nobody asked to change, so it is OFFERED as a fix instead, with
##   what it does to the other wishes.
## THE MINIMAL CLASH (a deletion filter, the plain linear way to find a minimal infeasible set): start from every wish;
##   drop each in turn; if the rest still clash it stays dropped. What is left clashes, and every wish in it is needed: drop any one
##   and the rest hold (the test re-checks every proper subset). n + 1 solves for n wishes.
## THE COST TO FREE EACH (measured with that wish dropped, everything else in the clash kept):
##   reach    the shortfall: the gap left once the others hold (cm), and the fixes: the step that closes it (cm, said in
##            his own frame, N007), the lean that closes it with the feet where they are (deg, bisection), and what that
##            lean breaks among ALL the wishes (the COM past the toes, ...)
##   planted  how far the feet must move: the step the solver takes without it (cm)
##   inside   how far past the edge of the feet the COM ends without it (cm)
##   lean / angle   the bound that still holds with the others: "lean at most 8.7 deg" (bisection on the bound, 0.05 deg)
##   other    its miss in the pose the others choose
## The scene is read, never written: the hero body is put back (B.state()) and the opponents are scratch bodies.
class_name ConflictExplain
extends RefCounted

const STEP_MAX := 1.5     # m: the longest step tried; a target further than this is "out of reach by stepping"
const STEP_COARSE := 0.05 # m: the stride of the first search for a step (the fist is ~9 cm long, so no hold is skipped)
const LEAN_MAX := 60.0    # deg: the biggest lean tried as a fix for a reach
const EPS := 1e-6         # m / deg: a miss this small is a hold (float noise of the IK and the hull)
const GRAMMAR_EXTRA := [
	"Also (the explainer only):  both feet planted  |  lean 40 deg forward  |  lean at most 10 deg",
	"The wishes are read at ONE moment: t, card, or the first line's 'at t s' window."]


static func _w(line: String, kind: String) -> Dictionary:
	return {"line": line, "kind": kind}


## one line -> a wish {"line", "kind", ...} or {"error"}
static func wish(line: String) -> Dictionary:
	var s := BodyAssert.norm(line)
	var win: Dictionary = BodyAssert._window(s)[1]
	var body: String = (BodyAssert._window(s)[0] as String).strip_edges()
	if body in ["both feet planted", "feet planted", "both feet on floor", "both feet on ground"]:
		var w := _w(line, "planted")
		w["feet"] = ["_l", "_r"]
		w["window"] = win
		return w
	if body.begins_with("lean") or body.begins_with("trunk lean") or body.begins_with("body lean"):
		var m := BodyAssert._re(BodyAssert.NUM + "\\s*(?:deg|degrees|degree)?").search(body)
		if m == null or body.contains("back") or body.contains("left") or body.contains("right"):
			return {"error": "'%s': a lean is 'lean 40 deg forward' or 'lean at most 10 deg' (forward only)" % line}
		var w := _w(line, "lean")
		w["op"] = "lt" if (body.contains("at most") or body.contains("under") or body.contains("below") or body.contains("less than") or body.contains("no more than")) else "gt"
		w["x"] = float(m.get_string(1))
		w["window"] = win
		return w
	var q := BodyAssert.parse(line)
	if not q["ok"]:
		return {"error": q["error"]}
	if q["kind"] == "speed":
		return {"error": "'%s': a speed needs the frames around it; the explainer works on one moment (check it with assert)" % line}
	var w := _w(line, q["kind"])
	w["q"] = q
	w["window"] = q["window"]
	if q["kind"] == "planted":
		w["feet"] = [q["foot"]]
	if q["kind"] == "angle":
		w.merge({"joint": q["joint"], "axis": q["axis"], "op": q["op"], "x": q.get("x", 0.0), "lo": q.get("lo", 0.0), "hi": q.get("hi", 0.0)})
		if int(q["a"]["fighter"]) != 0:
			return {"error": "'%s': the explainer moves only the hero (fighter 1); an opponent's angle is fixed" % line}
	if q["kind"] in ["touches", "distance"]:
		var lim := _limb(q["a"])
		var flip := false
		if lim == "" and q["kind"] == "touches":   # "his chin touches the right fist" reads the same way round
			lim = _limb(q["b"])
			flip = lim != ""
		if lim != "" and (q["kind"] == "touches" or q["op"] == "lt"):
			w["limb"] = lim
			w["flip"] = flip
	return w


## the hero limb a thing is the end of ("hand_r", "foot_l", ...) or ""
static func _limb(th: Dictionary) -> String:
	if int(th.get("fighter", -1)) != 0:
		return ""
	match th.get("kind", ""):
		"cap":
			var p0: String = th["parts"][0]
			return p0 if p0 in LimbIK.LIMBS else ""
		"joint":
			var j: String = th["joint"]
			return j if j in LimbIK.LIMBS else ""
	return ""


# ------------------------------------------------------------------------------------------------ the moment
## everything one moment needs: the hero at t (and its start state), the opponents at t, the planted soles, the frame
static func moment(S: Scene, B: Body, t: float, fighters: Array) -> Dictionary:
	if S.cards.size() >= 2:
		S.apply_true(B, t)
	var ctx := {"S": S, "B": B, "t": t, "start": B.state(), "bodies": {0: B}, "xfs": {0: Transform3D.IDENTITY}, "solves": 0}
	for k in fighters:
		if k > 0 and not ctx["bodies"].has(k):
			var bk := Body.new()
			bk.load_files("res://data/skeleton.json", "res://data/body_limits.json")
			bk.fk()
			(S.actors[k - 1]["scene"] as Scene).apply_true(bk, t)
			ctx["bodies"][k] = bk
			ctx["xfs"][k] = Constraints.actor_xf(S.actors[k - 1]["xf"])
	ctx["st"] = DragBalance.begin(B)
	ctx["F"] = BodyFrame.fighter(B)
	ctx["balls"] = {"_l": B.P["ball_l"], "_r": B.P["ball_r"]}
	ctx["pivot"] = _pivot(B, ctx["st"]["down"])
	ctx["tilt0"] = tilt(B, ctx)
	return ctx


## the lean's pivot: the midpoint of the ankles on the floor (one foot down: its ankle; none: the pelvis)
static func _pivot(B: Body, down: Array) -> Vector3:
	if down.is_empty():
		return B.P["pelvis"]
	var p := Vector3.ZERO
	for sd in down:
		p += B.P["foot" + String(sd)] as Vector3
	return p / float(down.size())


## the lean, deg: the line from the ankles' midpoint (the pivot) to the neck, from the vertical, toward his start forward
static func tilt(B: Body, ctx: Dictionary) -> float:
	var v: Vector3 = (B.P["neck_01"] as Vector3) - (ctx["pivot"] as Vector3)
	return rad_to_deg(atan2(v.dot(ctx["F"]["fwd"]), v.y))


# ------------------------------------------------------------------------------------------------ posing
## tip the whole body `deg` toward the floor direction `dir` (unit x, z) about the pivot; the feet are put back after
static func _lean(B: Body, ctx: Dictionary, deg: float, dir: Vector2) -> void:
	if absf(deg) < 1e-9:
		return
	var ax := Vector3.UP.cross(Vector3(dir.x, 0.0, dir.y)).normalized()
	var R := Quaternion(ax, deg_to_rad(deg))
	var pv: Vector3 = ctx["pivot"]
	var p0: Vector3 = B.P["pelvis"]
	B.ang["pelvis"] = B.decompose("pelvis", (R * (B.G["pelvis"] as Quaternion)).normalized())
	B.offset += (pv + R * (p0 - pv)) - p0
	B.fk()


## the legs that were down, back on their start soles (DragBalance's leg solve and knee swings), except a pinned leg
static func _replant(B: Body, ctx: Dictionary, pinned: Array) -> void:
	var st: Dictionary = ctx["st"]
	for foot in st["refs"]:
		var sd: String = String(foot).right(2)
		if pinned.any(func(j): return String(j).ends_with(sd) and (String(j).begins_with("thigh") or String(j).begins_with("calf") or String(j).begins_with("foot") or String(j).begins_with("ball"))):
			continue
		var best := {}
		for sw in DragBalance.SWINGS:
			var lr := DragBalance._leg(B, st, foot, sw)
			if best.is_empty() or float(lr["err"]) < float(best["err"]) - 1e-9:
				best = lr
			if float(lr["err"]) <= 0.0003 and (lr["clamped"] as Array).is_empty():
				best = lr
				break
		DragBalance._leg(B, st, foot, best["sw"])
	B.fk()


## the target point of a reach wish (the other thing's nearest shape point to the limb's root)
static func _target(w: Dictionary, ctx: Dictionary) -> Vector3:
	var q: Dictionary = w["q"]
	var th: Dictionary = q["a"] if w["flip"] else q["b"]
	var k := int(th["fighter"])
	var root: Vector3 = ctx["B"].P[LimbIK.chain(ctx["B"], w["limb"])[0]]
	var best := Vector3.ZERO
	var bd := INF
	for sh in BodyAssert.shapes(th, ctx["bodies"][k], ctx["xfs"][k]):
		var c := Geometry3D.get_closest_point_to_segment(root, sh[0], sh[1])
		var p: Vector3 = c + (root - c).normalized() * float(sh[2]) if float(sh[2]) > 0.0 and root.distance_to(c) > 1e-6 else c
		if root.distance_to(p) < bd:
			bd = root.distance_to(p)
			best = p
	return best


## the reaching limb onto the wish's target: the far end of its capsule (+ radius) put on the point. The hand / foot keeps
## its own angles, so a bent elbow points it off the root-target line: the wrist's aim is moved by what the far end
## still misses, until it lands (0.5 mm) or the limb is out of reach (LimbIK's miss: then straight at the target)
static func _reach(B: Body, w: Dictionary, ctx: Dictionary) -> void:
	var tip: String = w["limb"]
	var q: Dictionary = w["q"]
	var me: Dictionary = q["b"] if w["flip"] else q["a"]
	var T := _target(w, ctx)
	var root: Vector3 = B.P[LimbIK.chain(B, tip)[0]]
	var u := (T - root).normalized()
	var want := 0.0 if q["kind"] == "touches" else float(q["x"])   # "at most D": the far end may stop D short
	var goal := T - u * want
	var aim := goal - u * _ext(B, me, tip)
	for it in 8:
		var r := LimbIK.solve(B, tip, aim, LimbIK.pole_from_pose(B, tip))
		B.fk()
		if float(r["miss"]) > 0.001:   # out of reach: the closest pose is the limb straight at the target
			LimbIK.solve(B, tip, goal - u * _ext(B, me, tip), LimbIK.pole_from_pose(B, tip))
			B.fk()
			return
		var d := goal - _far(B, me, tip, u)
		if d.length() < 0.0005:
			return
		aim += d


## the reaching thing's far end: the capsule end furthest along u, plus its radius (a joint: the joint itself)
static func _far(B: Body, me: Dictionary, tip: String, u: Vector3) -> Vector3:
	if me["kind"] != "cap":
		return B.P[tip]
	var best := Vector3.ZERO
	var bd := -INF
	for p in me["parts"]:
		var c: Array = B.cap(p)
		for e in [c[0], c[1]]:
			var v := (e as Vector3) + u * float(B.rad[p])
			if v.dot(u) > bd:
				bd = v.dot(u)
				best = v
	return best


## how far the far end sits beyond the wrist / ankle along the limb as it is now
static func _ext(B: Body, me: Dictionary, tip: String) -> float:
	if me["kind"] != "cap":
		return 0.0
	var ext := 0.0
	for p in me["parts"]:
		var c: Array = B.cap(p)
		ext = maxf(ext, maxf((c[0] as Vector3).distance_to(B.P[tip]), (c[1] as Vector3).distance_to(B.P[tip])) + float(B.rad[p]))
	return ext


static func _gap(w: Dictionary, ctx: Dictionary) -> float:
	var q: Dictionary = w["q"]
	var ka := int(q["a"]["fighter"])
	var kb := int(q["b"]["fighter"])
	return BodyAssert.gap(BodyAssert.shapes(q["a"], ctx["bodies"][ka], ctx["xfs"][ka]), BodyAssert.shapes(q["b"], ctx["bodies"][kb], ctx["xfs"][kb]))


## the pose for these wishes with a step of `s` m along `dir` (+ an extra lean, for the lean fix); misses per wish
static func pose(ws: Array, ctx: Dictionary, s: float, dir: Vector2, extra_lean := 0.0) -> Array:
	var B: Body = ctx["B"]
	B.set_state(ctx["start"])
	var pinned := []
	var moved := false
	for w in ws:
		if w["kind"] == "lean":
			var need: float = float(w["x"]) - float(ctx["tilt0"])
			var go := maxf(need + 0.01, 0.0) if w["op"] == "gt" else minf(need - 0.01, 0.0)
			_lean(B, ctx, go, Vector2(ctx["F"]["fwd"].x, ctx["F"]["fwd"].z).normalized())
			moved = moved or go != 0.0
	if extra_lean != 0.0:
		_lean(B, ctx, extra_lean, dir)
		moved = true
	for w in ws:
		if w["kind"] == "angle":
			var j: String = w["joint"]
			var ai: int = WhatIf.AXI[w["axis"]]
			var v: Vector3 = B.ang[j]
			var x: float = v[ai]
			match w["op"]:
				"lt":
					x = minf(x, float(w["x"]) - 0.001)
				"gt":
					x = maxf(x, float(w["x"]) + 0.001)
				"between":
					x = clampf(x, float(w["lo"]), float(w["hi"]))
			v[ai] = x
			B.ang[j] = B.clamp_ang(j, v)
			pinned.append(j)
			moved = true
	B.fk()
	if moved:
		_replant(B, ctx, pinned)
	if s != 0.0:
		B.offset += Vector3(dir.x, 0.0, dir.y) * s
		B.fk()
	for w in ws:
		if w.has("limb"):
			_reach(B, w, ctx)
	ctx["solves"] = int(ctx["solves"]) + 1
	return ws.map(func(w): return miss(w, ctx))


## one wish's miss on the hero as it stands now: m (planted, inside, touches, distance) or deg (angle, lean); <= 0 holds
static func miss(w: Dictionary, ctx: Dictionary) -> float:
	var B: Body = ctx["B"]
	match w["kind"]:
		"planted":
			var worst := -INF
			for sd in w["feet"]:
				var lf := BodyAssert.lift(B, sd)
				var b0: Vector3 = ctx["balls"][sd]
				var b1: Vector3 = B.P["ball" + String(sd)]
				var sl := Vector2(b1.x - b0.x, b1.z - b0.z).length()
				worst = maxf(worst, maxf(lf - BodyAssert.DOWN, sl - BodyAssert.SLIDE))
			return worst
		"inside":
			var k := int(w["q"]["a"]["fighter"])
			var r := Balance.read(ctx["bodies"][k])
			return INF if (r["down"] as Array).is_empty() else -float(r["margin"])
		"touches":
			return _gap(w, ctx) - BodyAssert.TOUCH
		"distance":
			var g := _gap(w, ctx)
			return g - float(w["q"]["x"]) if w["q"]["op"] == "lt" else float(w["q"]["x"]) - g
		"angle":
			var v: float = (B.ang[w["joint"]] as Vector3)[WhatIf.AXI[w["axis"]]]
			match w["op"]:
				"lt":
					return v - float(w["x"])
				"gt":
					return float(w["x"]) - v
			return maxf(float(w["lo"]) - v, v - float(w["hi"]))
		"lean":
			var tl := tilt(B, ctx)
			return tl - float(w["x"]) if w["op"] == "lt" else float(w["x"]) - tl
	return 0.0


static func _holds(ms: Array) -> bool:
	return ms.all(func(x): return float(x) <= EPS)


## the floor direction of a reach wish: from the limb's root to its target, flat (unit); ZERO when straight overhead
static func _dir(w: Dictionary, ctx: Dictionary) -> Vector2:
	var B: Body = ctx["B"]
	var d: Vector3 = _target(w, ctx) - (B.P[LimbIK.chain(B, w["limb"])[0]] as Vector3)
	var f := Vector2(d.x, d.z)
	return f.normalized() if f.length() > 1e-6 else Vector2.ZERO


## CAN THESE WISHES ALL HOLD? -> {"ok", "step" (m), "dir", "misses"}. The solver above: no step, then the smallest step
## that makes the first failing reach hold
static func solve(ws: Array, ctx: Dictionary) -> Dictionary:
	if ws.is_empty():
		return {"ok": true, "step": 0.0, "dir": Vector2.ZERO, "misses": []}
	var ms := pose(ws, ctx, 0.0, Vector2.ZERO)
	if _holds(ms):
		return {"ok": true, "step": 0.0, "dir": Vector2.ZERO, "misses": ms}
	var ri := -1
	for i in ws.size():
		if ws[i].has("limb") and float(ms[i]) > EPS:
			ri = i
			break
	if ri < 0:
		return {"ok": false, "step": 0.0, "dir": Vector2.ZERO, "misses": ms}
	var dir := _dir(ws[ri], ctx)
	if dir == Vector2.ZERO:
		return {"ok": false, "step": 0.0, "dir": dir, "misses": ms}
	var reach_at := func(s: float) -> float: return float(pose(ws, ctx, s, dir)[ri])
	# march out in STEP_COARSE strides (a step too long walks him PAST the target, so the far end can't be the bracket),
	# then bisect the first stride that holds down to 0.4 mm
	var hi := -1.0
	var x := STEP_COARSE
	while x <= STEP_MAX + 1e-9:
		if float(reach_at.call(x)) <= EPS:
			hi = x
			break
		x += STEP_COARSE
	if hi < 0.0:
		return {"ok": false, "step": STEP_MAX, "dir": dir, "misses": pose(ws, ctx, STEP_MAX, dir), "too_far": true}
	var lo := hi - STEP_COARSE
	while hi - lo > 0.0004:
		var mid := (lo + hi) * 0.5
		if float(reach_at.call(mid)) <= EPS:
			hi = mid
		else:
			lo = mid
	var m2 := pose(ws, ctx, hi, dir)
	return {"ok": _holds(m2), "step": hi, "dir": dir, "misses": m2}


# ------------------------------------------------------------------------------------------------ the explainer
static func _without(ws: Array, w: Dictionary) -> Array:
	return ws.filter(func(x): return not is_same(x, w))


## the deletion filter: the smallest clashing subset (each wish in it is needed)
static func minimal(ws: Array, ctx: Dictionary) -> Array:
	var core := ws.duplicate()
	for w in ws:
		var rest := _without(core, w)
		if not solve(rest, ctx)["ok"]:
			core = rest
	return core


## "12.0 cm forward" / "8.5 cm forward and 3.0 cm toward his left": a floor vector in his own frame (N007's frame)
static func dir_words(v: Vector3, ctx: Dictionary) -> String:
	var F: Dictionary = ctx["F"]
	var f := snappedf(v.dot(F["fwd"]) * 100.0, 0.1)
	var l := snappedf(v.dot(F["left"]) * 100.0, 0.1)
	var parts := []
	if f != 0.0:
		parts.append("%.1f cm %s" % [absf(f), "forward" if f > 0.0 else "back"])
	if l != 0.0:
		parts.append("%.1f cm toward his %s" % [absf(l), "left" if l > 0.0 else "right"])
	return " and ".join(parts) if not parts.is_empty() else "0 cm"


## a floor direction's name in his frame: "forward", "toward his left", "forward and toward his right" (within 15 deg: one word)
static func dir_name(d: Vector2, ctx: Dictionary) -> String:
	var F: Dictionary = ctx["F"]
	var f := d.x * float(F["fwd"].x) + d.y * float(F["fwd"].z)
	var l := d.x * float(F["left"].x) + d.y * float(F["left"].z)
	var a := rad_to_deg(atan2(l, f))
	if absf(a) <= 15.0:
		return "forward"
	if absf(a) >= 165.0:
		return "back"
	var side := "toward his %s" % ("left" if l > 0.0 else "right")
	if absf(absf(a) - 90.0) <= 15.0:
		return side
	return ("forward and " if f > 0.0 else "back and ") + side


static func _q(w: Dictionary) -> String:
	return "'%s'" % String(w["line"]).strip_edges()


## which of `all` break in the pose that is on the body now -> their lines
static func _broken(all: Array, ctx: Dictionary) -> Array:
	return all.filter(func(w): return miss(w, ctx) > EPS).map(func(w): return String(w["line"]).strip_edges())


## the smallest lean (deg, toward dir, feet where they are) that makes reach wish w hold with the others in `ws`; -1 = none
static func _lean_fix(ws: Array, w: Dictionary, ctx: Dictionary, dir: Vector2) -> float:
	var i := ws.find(w)
	var at := func(d: float) -> float: return float(pose(ws, ctx, 0.0, dir, d)[i])
	var hi := -1.0   # 2-deg strides first: too far a lean carries the shoulder past the target (as a too-long step does)
	var x := 2.0
	while x <= LEAN_MAX + 1e-9:
		if float(at.call(x)) <= EPS:
			hi = x
			break
		x += 2.0
	if hi < 0.0:
		return -1.0
	var lo := hi - 2.0
	while hi - lo > 0.02:
		var mid := (lo + hi) * 0.5
		if float(at.call(mid)) <= EPS:
			hi = mid
		else:
			lo = mid
	return hi


## an angle / lean wish's bound moved toward what the others allow: the bound closest to the asked one that holds
static func _bound_fix(core: Array, w: Dictionary, ctx: Dictionary) -> Dictionary:
	if not w.has("op") or w["op"] == "between":
		return {}
	var rest := _without(core, w)
	solve(rest, ctx)   # the pose the others choose: the free end of the search
	var free := float(w["x"]) - miss(w, ctx) if w["op"] == "gt" else float(w["x"]) + miss(w, ctx)   # the value the wish sees there
	var asked := float(w["x"])
	var lo := free     # holds (the others' own pose)
	var hi := asked    # clashes
	for it in 40:
		if absf(hi - lo) <= 0.05:
			break
		var mid := (lo + hi) * 0.5
		var w2 := w.duplicate()
		w2["x"] = mid
		if solve(rest + [w2], ctx)["ok"]:
			lo = mid
		else:
			hi = mid
	return {"bound": snappedf(lo, 0.01), "asked": asked, "by": snappedf(absf(asked - lo), 0.01)}


static func _name(w: Dictionary) -> String:
	if w["kind"] in ["touches", "distance"] and w.has("limb"):
		var me: Dictionary = w["q"]["b"] if w["flip"] else w["q"]["a"]
		return String(me["name"])
	return String(w["line"]).strip_edges()


## the cost to free each wish of the clash
static func costs(core: Array, all: Array, ctx: Dictionary) -> Array:
	var out := []
	for w in core:
		var rest := _without(core, w)
		var sv := solve(rest, ctx)
		var c := {"line": String(w["line"]).strip_edges(), "kind": w["kind"]}
		match w["kind"]:
			"touches", "distance":
				pose(core, ctx, float(sv["step"]), sv["dir"])   # the limb reaches for it in the others' pose
				var short := miss(w, ctx)
				c["shortfall_cm"] = snappedf(short * 100.0, 0.01)
				var fixes := []
				if w.has("limb"):
					var dir := _dir(w, ctx)
					var others: Array = all.filter(func(x): return not is_same(x, w))
					var loose: Array = rest.filter(func(x): return x["kind"] != "planted") + [w]   # the feet may move
					var st := solve(loose, ctx)
					if st["ok"]:
						var stp: float = st["step"]
						c["step_cm"] = snappedf(stp * 100.0, 0.01)
						var sd: Vector2 = st["dir"]
						c["step_words"] = dir_words(Vector3(sd.x, 0.0, sd.y) * stp, ctx)
						pose(loose, ctx, stp, sd)
						var br := _broken(others, ctx)
						c["step_breaks"] = br
						fixes.append("step %s%s" % [c["step_words"], (" (gives up %s)" % ", ".join(br.map(func(l): return "'%s'" % l))) if not br.is_empty() else ""])
					var lf := _lean_fix(core, w, ctx, dir)
					if lf >= 0.0:
						c["lean_deg"] = snappedf(lf, 0.01)
						pose(core, ctx, 0.0, dir, lf)
						var br2 := _broken(others, ctx)
						c["lean_breaks"] = br2
						var bal := Balance.read(ctx["B"])
						c["lean_com_margin_cm"] = snappedf(float(bal["margin"]) * 100.0, 0.01) if (bal["down"] as Array).size() > 0 else null
						fixes.append("lean %.1f deg %s over the feet%s" % [lf, dir_name(dir, ctx), (" (but it breaks %s)" % ", ".join(br2.map(func(l): return "'%s'" % l))) if not br2.is_empty() else ""])
				for o in rest:
					fixes.append("drop " + _q(o))
				c["fixes"] = fixes
				c["say"] = "%s needs %.1f cm more reach: %s" % [_name(w), short * 100.0, ", or ".join(fixes)]
			"planted":
				var stp: float = sv["step"]
				c["step_cm"] = snappedf(stp * 100.0, 0.01)
				var d: Vector2 = sv["dir"]
				c["step_words"] = dir_words(Vector3(d.x, 0.0, d.y) * stp, ctx)
				pose(rest, ctx, stp, d)
				c["slide_cm"] = snappedf(maxf(miss(w, ctx) + BodyAssert.SLIDE, 0.0) * 100.0, 0.01)
				c["say"] = ("free %s: the feet must move %.1f cm (a step %s)" % [_q(w), stp * 100.0, c["step_words"]]) if stp > 0.0 \
					else "free %s: it misses by %.1f cm in the pose the others need" % [_q(w), maxf(miss(w, ctx), 0.0) * 100.0]
			"inside":
				var mi := miss(w, ctx)
				c["past_edge_cm"] = snappedf(mi * 100.0, 0.01) if not is_inf(mi) else null
				c["say"] = ("free %s: balance: the COM ends %.1f cm past the edge of the feet" % [_q(w), mi * 100.0]) if not is_inf(mi) \
					else "free %s: balance: no foot is left on the floor" % _q(w)
			"lean", "angle":
				var bf := _bound_fix(core, w, ctx)
				var u := "deg"
				if bf.is_empty():
					var mi := miss(w, ctx)
					c["miss_deg"] = snappedf(mi, 0.01)
					c["say"] = "free %s: it misses by %.1f deg in the pose the others need" % [_q(w), mi]
				else:
					c.merge(bf)
					var word := ("lean" if w["kind"] == "lean" else "%s %s" % [w["joint"], w["axis"]])
					c["say"] = "%s at %s %.1f %s holds with the rest (asked %s %.1f): %.1f %s %s" % [word, "most" if w["op"] == "gt" else "least", bf["bound"], u,
						"at least" if w["op"] == "gt" else "at most", bf["asked"], bf["by"], u, "less" if w["op"] == "gt" else "more"]
			_:
				var mi := miss(w, ctx)
				c["miss"] = snappedf(mi * 100.0, 0.01)
				c["say"] = "free %s: it misses by %.1f cm in the pose the others need" % [_q(w), mi * 100.0]
		out.append(c)
	return out


## EXPLAIN: lines -> {"ok", "t", "conflict", "wishes", "minimal", "costs", "say", "solves"} or {"ok": false, "error"}.
## t < 0 = pick it from the lines (the first "at t" window), else 0. B is put back exactly as it was.
static func explain(S: Scene, B: Body, lines: Array, t := -1.0) -> Dictionary:
	if lines.is_empty():
		return {"ok": false, "error": "explain_conflict needs {\"lines\": [\"right fist touches fighter 2 chin\", \"both feet planted\", ...]}",
			"grammar": BodyAssert.GRAMMAR + GRAMMAR_EXTRA}
	var ws := []
	for l in lines:
		var w := wish(String(l))
		if w.has("error"):
			return {"ok": false, "error": w["error"], "line": l, "grammar": BodyAssert.GRAMMAR + GRAMMAR_EXTRA}
		ws.append(w)
	var fighters := [0]
	for w in ws:
		if w.has("q"):
			for k in BodyAssert._fighters(w["q"]):
				if k > S.actors.size():
					return {"ok": false, "error": "%s: there is no fighter %d (the scene has %d)" % [_q(w), k + 1, S.actors.size() + 1]}
				if not k in fighters:
					fighters.append(k)
	if t < 0.0:
		t = 0.0
		for w in ws:
			if w["window"]["mode"] == "at":
				t = float(w["window"]["t"]) / (float(S.fps) if w["window"]["unit"] == "f" else 1.0)
				break
	t = clampf(t, 0.0, S.length()) if S.cards.size() >= 2 else 0.0
	var keep := B.state()
	var ctx := moment(S, B, t, fighters)
	var asis := ws.map(func(w): return miss(w, ctx))
	var wl := []
	for i in ws.size():
		var w: Dictionary = ws[i]
		var cm: bool = w["kind"] in ["planted", "inside", "touches", "distance"]
		wl.append({"line": String(w["line"]).strip_edges(), "kind": w["kind"], "holds_as_is": float(asis[i]) <= EPS,
			"miss_as_is": (null if is_inf(float(asis[i])) else snappedf(float(asis[i]) * (100.0 if cm else 1.0), 0.01)), "unit": "cm" if cm else "deg",
			"moved_by_solver": w.has("limb") or w["kind"] in ["angle", "lean"]})
	var all := solve(ws, ctx)
	var out := {"ok": true, "t": snappedf(t, 0.0001), "wishes": wl}
	if all["ok"]:
		out["conflict"] = false
		out["minimal"] = []
		out["step_cm"] = snappedf(float(all["step"]) * 100.0, 0.01)
		out["say"] = "no conflict at %.3f s: all %d wishes hold together%s" % [t, ws.size(),
			(" (with a step %s)" % dir_words(Vector3(all["dir"].x, 0.0, all["dir"].y) * float(all["step"]), ctx)) if float(all["step"]) > 0.0 else ""]
	else:
		var core := minimal(ws, ctx)
		var cs := costs(core, ws, ctx)
		out["conflict"] = true
		out["minimal"] = core.map(func(w): return String(w["line"]).strip_edges())
		out["costs"] = cs
		out["note"] = "this is ONE smallest clash (the deletion filter keeps the first it finds); free it and ask again: another may remain"
		if core.size() == 1:
			out["say"] = "CONFLICT at %.3f s: %s can't hold even alone. %s" % [t, _q(core[0]), cs[0]["say"]]
		else:
			out["say"] = "CONFLICT at %.3f s: these %d of the %d wishes can't all hold: %s. %s." % [t, core.size(), ws.size(),
				", ".join(core.map(func(w): return _q(w))), ". ".join(cs.map(func(c): return String(c["say"])))]
	out["solves"] = ctx["solves"]
	B.set_state(keep)
	return out


## serve / CLI: {lines, t?, card?} on a live poser (its scene and body; nothing is changed)
static func serve(m: Node, p: Dictionary) -> Dictionary:
	var ls: Variant = p.get("lines")
	if not (ls is Array) or not ls.all(func(s): return s is String):
		return {"ok": false, "error": "explain_conflict needs {\"lines\": [\"right fist touches fighter 2 chin at 0.6 s\", \"both feet planted\", \"COM inside the feet\"], \"t\"?: s, \"card\"?: N}",
			"grammar": BodyAssert.GRAMMAR + GRAMMAR_EXTRA}
	var t := -1.0
	if p.has("card"):
		var n := int(p["card"])
		if n < 1 or n > m.S.cards.size():
			return {"ok": false, "error": "no card %d (the scene has %d)" % [n, m.S.cards.size()]}
		t = float(m.S.times()[n - 1][1]) if m.S.cards.size() >= 2 else 0.0
	elif p.has("t"):
		t = maxf(float(p["t"]), 0.0)
	return explain(m.S, m.B, ls, t)
