## body_assert.gd - BODY ASSERTIONS (docs/INNOVATIONS.md N002): a blind agent writes checks about the body like tests,
## one line each, and gets pass / fail with the worst miss in cm, deg, m/s or s and the frame where it happens.
##   "left foot planted 0-0.4 s"                       "right fist touches his chin at 0.6 s +-1 f"
##   "COM inside the feet all clip"                    "right elbow below 120 deg flex 1.0-1.5 s"
##   "fighter 2 head at least 30 cm from fighter 1 right fist all clip"     "pelvis speed under 3 m/s all clip"
## THE GRAMMAR is small and fixed (GRAMMAR below; an unread line gets it back). One line = a THING clause + a WINDOW.
## THINGS (in the hero's space, y up, the floor y = 0):
##   a body word is that piece's SURFACE: fist / hand, foot (foot + ball capsules), toes, head, forearm, upper arm, thigh,
##     shin, pelvis / hips: Body.cap capsules with their radii (the capsules Check's contacts use);
##   a landmark is a point ON the surface: chin, face, mouth, forehead, eyes, ear, neck, chest, belly, back (SayIt.landmark,
##     the same points "put the right hand on the chin" aims at);
##   a joint word or a joint name is the joint CENTRE, as serve `measure` reads it: elbow, knee, shoulder, hip, wrist, ankle,
##     or hand_r, lowerarm_l, ... (Body.BODY); head and pelvis are body words (surfaces): "head joint" is the centre;
##   com (centre of mass, Balance.com), weapon tip / weapon knob (as measure).
##   "fighter N" in front picks fighter N (1 = the hero, 2 = the scene's first actor, placed by its xf: Constraints.actor_xf).
## WHAT EACH KIND MEASURES, per frame (formulas stated so a reader can re-derive every miss):
##   touches     gap = the shortest distance between the two things' segments (Body.seg_seg, Ericson 5.1.9) minus both
##               radii; holds when gap <= TOUCH (1 cm, Balance.TOUCH: what the balance code already counts as "on").
##               miss = gap - TOUCH.
##   distance    the same surface gap; "at least D": miss = D - gap; "at most D": miss = gap - D.
##   planted     lift = the toe base (ball joint) over its standing height (Body.foot_state's own test: ball.y - rest
##               ball.y; the capsules can't say it: the foot capsule's underside sits 6.4 cm under the floor in the rest
##               pose, measured); slide = the ball joint's floor (x, z) distance from where it was at the window's first
##               frame. Holds when lift <= DOWN (2 cm, Body.foot_state's "toe base on the floor" bar) and
##               slide <= SLIDE (2.5 cm: Rulebook.FOOT_SKATE, Karunratanakul et al. 2023, arXiv:2310.08580, the foot-skate
##               bar Check's FOOT SLIDE uses). miss = max(lift - DOWN, slide - SLIDE). A flat floor (props ignored: stated).
##   inside      Balance.read's margin (the COM's floor point to the support polygon's edge, + inside); miss = -margin.
##               No foot down = no support: a miss with no number ("no foot on the floor").
##   angle       the joint's own angle on one axis (bend / side / twist, degrees from rest, B.ang: what `state` and the
##               joint panel show; WhatIf.AXES names: flex = bend). below X: miss = v - X; above X: X - v; between A and B:
##               max(A - v, v - B).
##   speed       the thing's point (a capsule's middle, a joint, a landmark, the COM) by central difference over the
##               frames either side, |p(i+1) - p(i-1)| / (t(i+1) - t(i-1)) (one-sided at the clip's ends): `measure`'s
##               speed formula on the frame grid. under X: miss = v - X; over X: X - v.
## WINDOWS: frames at the scene's fps, t = i / fps over [0, length].
##   "all clip" (or no window): EVERY frame must hold; the miss is the worst frame's.
##   "a-b s" / "a-b f": every frame with a <= t <= b must hold (none on the grid: the nearest frame).
##   "at t s +-N f" (or "at N f"): an EVENT: it must hold on at least ONE frame within N frames of t (default N = 0); the
##     miss is the closest frame's, and a fail also says how many frames early / late the nearest frame that holds is.
## A pass is miss <= 0 (1e-9 m / deg slack for float noise).
## Saved assertions: Scene.asserts (the file's "asserts" list of lines); Check re-runs them (Rulebook.check -> findings()).
class_name BodyAssert
extends RefCounted

const TOUCH := Balance.TOUCH        # m: a gap this small counts as touching (balance.gd's "on the floor" tolerance)
const DOWN := 0.02                 # m: the toe base this close to its standing height is on the floor (Body.foot_state)
const SLIDE := Rulebook.FOOT_SKATE  # m: a planted ball that drifts more than this along the floor is skating (Check's bar)
const EPS := 1e-9
const NUM := "(-?\\d+(?:\\.\\d+)?)"
const GRAMMAR := [
	"One check per line: THING clause, then a WINDOW (none = all clip).",
	"  <left|right> foot planted                      e.g. left foot planted 0-0.4 s",
	"  <thing> touches <thing>                        e.g. right fist touches his chin at 0.6 s +-1 f",
	"  com inside the feet                            e.g. COM inside the feet all clip",
	"  <joint> [bend|side|twist] below|above X deg    e.g. right elbow below 120 deg flex 1.0-1.5 s",
	"  <joint> between A and B deg [axis]             e.g. left knee between 10 and 60 deg bend all clip",
	"  <thing> at least|at most D cm|mm|m from <thing>  e.g. fighter 2 head at least 30 cm from fighter 1 right fist all clip",
	"  <thing> speed under|over X m/s                 e.g. right fist speed over 6 m/s at 1.2 s +-2 f",
	"WINDOWS: all clip | a-b s | a-b f | at t s +-N f | at N f",
	"THINGS: [fighter N] + fist/hand, foot, toes, head, forearm, upper arm, thigh, shin, pelvis/hips (surfaces);",
	"  chin, face, mouth, forehead, eyes, ear, neck, chest, belly, back (surface points); elbow, knee, shoulder, hip,",
	"  wrist, ankle or a joint name like hand_r, or 'head joint' (joint centres); com; weapon tip / weapon knob.",
	"  Paired parts need left / right; 'fighter 2 head' is the first actor's."]
const FILLER := ["his", "her", "their", "the", "must", "should", "is", "stays", "stay", "remains", "keeps", "be", "always"]
const CAPS := {"fist": ["hand"], "hand": ["hand"], "foot": ["foot", "ball"], "toes": ["ball"], "toe": ["ball"],
	"forearm": ["lowerarm"], "upper arm": ["upperarm"], "upperarm": ["upperarm"], "thigh": ["thigh"], "shin": ["calf"],
	"calf": ["calf"], "head": ["head"], "pelvis": ["pelvis"], "hips": ["pelvis"]}
const UNSIDED := ["head", "pelvis", "hips"]
const JOINTS := {"elbow": "lowerarm", "knee": "calf", "shoulder": "upperarm", "hip": "thigh", "wrist": "hand", "ankle": "foot"}
const LANDS := ["chin", "face", "mouth", "forehead", "eyes", "eye", "ear", "neck", "chest", "belly", "stomach", "waist", "back"]
const LT := ["below", "under", "at most", "less than", "slower than", "no more than"]   # the value must stay under X
const GT := ["above", "over", "at least", "more than", "faster than", "no less than"]


static func _re(p: String) -> RegEx:
	return RegEx.create_from_string(p)


static func _bad(line: String, why: String) -> Dictionary:
	return {"ok": false, "line": line, "error": why, "grammar": GRAMMAR}


static func norm(line: String) -> String:
	var s := line.strip_edges().to_lower().replace("±", "+-").replace("+/-", "+-").replace("°", " deg").replace("'s ", " ")
	s = s.rstrip(".").replace(",", " ")
	var out := []
	for w in s.split(" ", false):
		if not w in FILLER:
			out.append(w)
	return " ".join(out)


## the window off the end of a normalised line -> [rest, window]; window {"mode": all|range|at, ...}
static func _window(s: String) -> Array:
	var m := _re("\\s*(?:all clip|whole clip|all of clip|throughout|all)$").search(s)
	if m != null:
		return [s.left(m.get_start()), {"mode": "all"}]
	m = _re("\\s*(?:from\\s+|over\\s+|during\\s+)?" + NUM + "\\s*(?:s\\s*)?(?:-|to)\\s*" + NUM + "\\s*(s|sec|f|frames?)$").search(s)
	if m != null:
		var u := "f" if m.get_string(3).begins_with("f") else "s"
		return [s.left(m.get_start()), {"mode": "range", "a": float(m.get_string(1)), "b": float(m.get_string(2)), "unit": u}]
	m = _re("\\s*at\\s+" + NUM + "\\s*(s|sec|f|frames?)?\\s*(?:\\+-\\s*" + NUM + "\\s*(f|frames?|s)?)?$").search(s)
	if m != null:
		var w := {"mode": "at", "t": float(m.get_string(1)), "unit": "f" if m.get_string(2).begins_with("f") else "s", "tol": 0.0, "tol_unit": "f"}
		if m.get_string(3) != "":
			w["tol"] = float(m.get_string(3))
			w["tol_unit"] = "s" if m.get_string(4) == "s" else "f"
		return [s.left(m.get_start()), w]
	return [s, {"mode": "all"}]


## "fighter 2 right fist" -> {"ok", "fighter" (0 = the hero), "kind": cap|joint|land|com|tip|knob, "parts"|"joint"|"land", "side", "name"}
static func thing(raw: String) -> Dictionary:
	var s := raw.strip_edges()
	var k := 0
	var m := _re("^(?:fighter|actor)\\s+(\\d+)\\s*").search(s)
	if m != null:
		k = int(m.get_string(1)) - 1
		s = s.substr(m.get_end()).strip_edges()
		if k < 0:
			return {"ok": false, "error": "fighters are numbered from 1 (1 = the hero)"}
	var out := {"ok": true, "fighter": k, "name": raw.strip_edges()}
	if s in ["com", "centre of mass", "center of mass", "cog"]:
		out["kind"] = "com"
		return out
	if s in ["weapon tip", "tip"]:
		out["kind"] = "tip"
		return out
	if s in ["weapon knob", "knob"]:
		out["kind"] = "knob"
		return out
	if s.ends_with(" joint") and WhatIf.joint_name(s.trim_suffix(" joint")) != "":   # "head joint", "right knee joint": the centre
		out["kind"] = "joint"
		out["joint"] = WhatIf.joint_name(s.trim_suffix(" joint"))
		return out
	if s in Body.BODY and not s in UNSIDED:   # head / pelvis are body words (their surfaces) first: "head joint" is the centre
		out["kind"] = "joint"
		out["joint"] = s
		return out
	var sd := ""
	for pre in [["right ", "_r"], ["left ", "_l"]]:
		if s.begins_with(pre[0]):
			sd = pre[1]
			s = s.substr(pre[0].length()).strip_edges()
	out["side"] = sd
	if CAPS.has(s):
		if sd == "" and not s in UNSIDED:
			return {"ok": false, "error": "'%s': say left or right %s" % [raw.strip_edges(), s]}
		out["kind"] = "cap"
		out["parts"] = (CAPS[s] as Array).map(func(p): return p + ("" if s in UNSIDED else sd))
		return out
	if JOINTS.has(s):
		if sd == "":
			return {"ok": false, "error": "'%s': say left or right %s" % [raw.strip_edges(), s]}
		out["kind"] = "joint"
		out["joint"] = JOINTS[s] + sd
		return out
	if s in LANDS:
		out["kind"] = "land"
		out["land"] = s
		return out
	return {"ok": false, "error": "'%s' is not a body thing I know" % raw.strip_edges()}


static func _op(w: String) -> String:
	return "lt" if w in LT else "gt" if w in GT else ""


## one line -> {"ok", "line", "kind", "window", ...} or {"ok": false, "error", "grammar"}
static func parse(line: String) -> Dictionary:
	var s := norm(line)
	if s == "":
		return _bad(line, "an empty line")
	var rw := _window(s)
	var body: String = (rw[0] as String).strip_edges()
	var win: Dictionary = rw[1]
	var q := {"ok": true, "line": line, "window": win}
	var ops := "below|under|at most|less than|no more than|above|over|at least|more than|no less than"
	# planted
	var m := _re("^(.+?)\\s+(?:planted|plants|on floor|on ground)$").search(body)
	if m != null:
		var th := thing(m.get_string(1))
		if not th["ok"]:
			return _bad(line, th["error"])
		if th["kind"] == "joint" and String(th["joint"]) in ["foot_l", "foot_r", "ball_l", "ball_r"]:
			th = thing(String(th["name"]).left(String(th["name"]).length() - String(th["joint"]).length()) + ("left foot" if th["joint"].ends_with("_l") else "right foot"))
		if th["kind"] != "cap" or not (th["parts"] as Array).has("foot" + String(th.get("side", ""))) or th["side"] == "":
			return _bad(line, "'planted' is for a foot: left foot / right foot")
		q.merge({"kind": "planted", "a": th, "foot": th["side"]})
		return q
	# inside support
	m = _re("^(?:(?:fighter|actor)\\s+(\\d+)\\s+)?(?:com|centre of mass|center of mass|cog)\\s+(?:inside|within|over|in)\\s+(?:feet|support|support polygon|base of support|base)$").search(body)
	if m != null:
		var k := int(m.get_string(1)) - 1 if m.get_string(1) != "" else 0
		if k < 0:
			return _bad(line, "fighters are numbered from 1 (1 = the hero)")
		q.merge({"kind": "inside", "a": {"ok": true, "fighter": k, "kind": "com", "name": "com"}})
		return q
	# touches
	m = _re("^(.+?)\\s+(?:touches|touch|contacts|meets)\\s+(.+)$").search(body)
	if m != null:
		var ta := thing(m.get_string(1))
		var tb := thing(m.get_string(2))
		if not ta["ok"] or not tb["ok"]:
			return _bad(line, ta.get("error", tb.get("error", "")))
		q.merge({"kind": "touches", "a": ta, "b": tb})
		return q
	# distance
	m = _re("^(.+?)\\s+(" + ops + "|within|no closer than|no further than|no farther than)\\s+" + NUM + "\\s*(mm|cm|m)\\s+(?:away\\s+)?(?:from|of|to)\\s+(.+)$").search(body)
	if m != null:
		var ta := thing(m.get_string(1))
		var tb := thing(m.get_string(5))
		if not ta["ok"] or not tb["ok"]:
			return _bad(line, ta.get("error", tb.get("error", "")))
		var w := m.get_string(2)
		var op := "gt" if w == "no closer than" else "lt" if w in ["within", "no further than", "no farther than"] else _op(w)
		var d: float = float(m.get_string(3)) * float({"mm": 0.001, "cm": 0.01, "m": 1.0}[m.get_string(4)])
		q.merge({"kind": "distance", "a": ta, "b": tb, "op": op, "x": d})
		return q
	# speed
	m = _re("^(.+?)\\s+speed\\s+(" + ops + ")\\s+" + NUM + "\\s*(m/s|km/h)?$").search(body)
	if m == null:
		m = _re("^(.+?)\\s+(?:moves\\s+)?(slower than|faster than)\\s+" + NUM + "\\s*(m/s|km/h)?$").search(body)
	if m != null:
		var ta := thing(m.get_string(1))
		if not ta["ok"]:
			return _bad(line, ta["error"])
		var x := float(m.get_string(3)) / (3.6 if m.get_string(4) == "km/h" else 1.0)
		q.merge({"kind": "speed", "a": ta, "op": _op(m.get_string(2)), "x": x})
		return q
	# angle: an axis word anywhere (flex = bend: WhatIf.AXES), then the joint and its bound in degrees
	var axis := "bend"
	var words := []
	for w in body.split(" ", false):
		if WhatIf.AXES.has(w) and not (w == "side" and words.size() > 0 and words[-1] in ["left", "right"]):
			axis = WhatIf.AXES[w]
		else:
			words.append(w)
	var ab := " ".join(words)
	m = _re("^(.+?)\\s+(?:(" + ops + ")|between\\s+" + NUM + "\\s*(?:deg|degrees)?\\s+and)\\s+" + NUM + "\\s*(?:deg|degrees|degree)$").search(ab)
	if m != null:
		var subj := m.get_string(1)
		var k := 0
		var fm := _re("^(?:fighter|actor)\\s+(\\d+)\\s+").search(subj)
		if fm != null:
			k = int(fm.get_string(1)) - 1
			subj = subj.substr(fm.get_end())
		var j := WhatIf.joint_name(subj)
		if j == "" or k < 0:
			return _bad(line, "'%s' is not a joint (elbow, knee, shoulder, hip, wrist, ankle, neck, ... with left / right)" % subj)
		var x := float(m.get_string(4))
		if m.get_string(3) != "":
			var lo := float(m.get_string(3))
			q.merge({"kind": "angle", "a": {"ok": true, "fighter": k, "kind": "joint", "joint": j, "name": subj}, "joint": j, "axis": axis, "op": "between", "lo": minf(lo, x), "hi": maxf(lo, x)})
		else:
			q.merge({"kind": "angle", "a": {"ok": true, "fighter": k, "kind": "joint", "joint": j, "name": subj}, "joint": j, "axis": axis, "op": _op(m.get_string(2)), "x": x})
		return q
	return _bad(line, "I can't read '%s'" % line.strip_edges())


# ------------------------------------------------------------------------------------------------ geometry
## the thing's shapes [[a, b, r]] in the hero's space, on fighter body Bk placed by X
static func shapes(th: Dictionary, Bk: Body, X: Transform3D) -> Array:
	match th["kind"]:
		"cap":
			var out := []
			for p in th["parts"]:
				var c: Array = Bk.cap(p)
				out.append([X * (c[0] as Vector3), X * (c[1] as Vector3), float(Bk.rad[p])])
			return out
		"joint":
			var pj: Vector3 = X * (Bk.P[th["joint"]] as Vector3)
			return [[pj, pj, 0.0]]
	var q := point(th, Bk, X)
	return [[q, q, 0.0]]


static func point(th: Dictionary, Bk: Body, X: Transform3D) -> Vector3:
	match th["kind"]:
		"cap":
			var s := Vector3.ZERO
			for p in th["parts"]:
				var c: Array = Bk.cap(p)
				s += ((c[0] as Vector3) + (c[1] as Vector3)) * 0.5
			return X * (s / float((th["parts"] as Array).size()))
		"joint":
			return X * (Bk.P[th["joint"]] as Vector3)
		"land":
			return X * SayIt.landmark(Bk, th["land"], th.get("side", ""), "_r")
		"com":
			return X * Balance.com(Bk)
		"tip", "knob":
			if not Bk.wep_on:
				return X * (Bk.E["hand_r"] as Vector3)
			return X * Bk.wep_point(Bk.wep_len if th["kind"] == "tip" else 0.0)
	return Vector3.ZERO


static func gap(a: Array, b: Array) -> float:
	var best := INF
	for sa in a:
		for sb in b:
			best = minf(best, Body.seg_seg(sa[0], sa[1], sb[0], sb[1]) - float(sa[2]) - float(sb[2]))
	return best


## the toe base's height over its standing height, m (Body.foot_state's measure; X moves on the floor only, so y is kept)
static func lift(Bk: Body, sd: String) -> float:
	return (Bk.P["ball" + sd] as Vector3).y - (Bk.p0["ball" + sd] as Vector3).y


static func _fighters(q: Dictionary) -> Array:
	var ks := []
	for key in ["a", "b"]:
		if q.has(key) and not int(q[key]["fighter"]) in ks:
			ks.append(int(q[key]["fighter"]))
	return ks


# ------------------------------------------------------------------------------------------------ running
## check lines on the scene as made -> {"pass", "passed", "failed", "unread", "fps", "length_s", "results": [...]}
## B is put back as it was. The frames are the scene's own fps grid.
static func run(S: Scene, B: Body, lines: Array) -> Dictionary:
	var fps := float(S.fps)
	var L := S.length()
	var n := int(floor(L * fps + 1e-6)) + 1
	var ts := []
	for i in n:
		ts.append(minf(i / fps, L))
	var qs := []
	var results := []
	for l in lines:
		var q := parse(String(l))
		if q["ok"]:
			for k in _fighters(q):
				if k > S.actors.size():
					q = _bad(String(l), "there is no fighter %d (the scene has %d)" % [k + 1, S.actors.size() + 1])
		qs.append(q)
	var need := {}
	for q in qs:
		if q["ok"]:
			for k in _fighters(q):
				need[k] = true
	var keep := B.state()
	var bodies := {0: B}
	var xfs := {0: Transform3D.IDENTITY}
	for k in need:
		if k > 0:
			var bk := Body.new()
			bk.load_files("res://data/skeleton.json", "res://data/body_limits.json")
			bk.fk()
			bodies[k] = bk
			xfs[k] = Constraints.actor_xf(S.actors[k - 1]["xf"])
	var raw := []   # raw[qi][i]
	for q in qs:
		raw.append([])
	for i in n:
		for k in bodies:
			var sc: Scene = S if k == 0 else S.actors[k - 1]["scene"]
			sc.apply_true(bodies[k], ts[i])
		for qi in qs.size():
			var q: Dictionary = qs[qi]
			if not q["ok"]:
				continue
			var ka := int(q["a"]["fighter"])
			var Ba: Body = bodies[ka]
			var Xa: Transform3D = xfs[ka]
			match q["kind"]:
				"planted":
					var bp: Vector3 = Xa * (Ba.P["ball" + String(q["foot"])] as Vector3)
					raw[qi].append([lift(Ba, q["foot"]), Vector2(bp.x, bp.z)])
				"inside":
					var r := Balance.read(Ba)
					raw[qi].append(float(r["margin"]) if (r["down"] as Array).size() > 0 else -INF)
				"touches", "distance":
					var kb := int(q["b"]["fighter"])
					raw[qi].append(gap(shapes(q["a"], Ba, Xa), shapes(q["b"], bodies[kb], xfs[kb])))
				"angle":
					raw[qi].append(float((Ba.ang[q["joint"]] as Vector3)[WhatIf.AXI[q["axis"]]]))
				"speed":
					raw[qi].append(point(q["a"], Ba, Xa))
	B.set_state(keep)
	var passed := 0
	var failed := 0
	var unread := 0
	for qi in qs.size():
		var q: Dictionary = qs[qi]
		if not q["ok"]:
			unread += 1
			results.append({"line": q["line"], "ok": false, "pass": false, "error": q["error"], "grammar": GRAMMAR})
			continue
		var r := judge(q, raw[qi], ts, fps)
		results.append(r)
		if r["pass"]:
			passed += 1
		else:
			failed += 1
	return {"pass": failed == 0 and unread == 0, "passed": passed, "failed": failed, "unread": unread, "fps": int(fps),
		"length_s": snappedf(L, 0.0001), "frames": n, "results": results}


## the frames [f0, f1] a window covers on an n-frame grid
static func frames_of(w: Dictionary, fps: float, n: int, ts: Array) -> Array:
	match w["mode"]:
		"range":
			var a: float = w["a"] / (fps if w["unit"] == "f" else 1.0)
			var b: float = w["b"] / (fps if w["unit"] == "f" else 1.0)
			if b < a:
				var tmp := a
				a = b
				b = tmp
			var f0 := clampi(int(ceil(a * fps - 1e-6)), 0, n - 1)
			var f1 := clampi(int(floor(b * fps + 1e-6)), 0, n - 1)
			if f1 < f0:   # no grid frame inside: the nearest one
				f0 = clampi(roundi((a + b) * 0.5 * fps), 0, n - 1)
				f1 = f0
			return [f0, f1]
		"at":
			var c := roundi(w["t"] * (1.0 if w["unit"] == "f" else fps))
			var tol := roundi(w["tol"] * (fps if w["tol_unit"] == "s" else 1.0))
			return [clampi(c - tol, 0, n - 1), clampi(c + tol, 0, n - 1)]
	return [0, n - 1]


## the per-frame miss (m, deg or m/s; + = the line is broken there) over the whole clip, and what was measured
static func misses(q: Dictionary, raw: Array, ts: Array, f0: int) -> Array:
	var n := raw.size()
	var ms := []
	var vs := []
	match q["kind"]:
		"planted":
			var ref: Vector2 = raw[f0][1]
			for i in n:
				var lf: float = raw[i][0]
				var sl: float = (raw[i][1] as Vector2).distance_to(ref)
				ms.append(maxf(lf - DOWN, sl - SLIDE))
				vs.append([lf, sl])
		"inside":
			for i in n:
				ms.append(-float(raw[i]))
				vs.append(raw[i])
		"touches":
			for i in n:
				ms.append(float(raw[i]) - TOUCH)
				vs.append(raw[i])
		"distance", "angle", "speed":
			for i in n:
				var v: float
				if q["kind"] == "speed":
					var a := maxi(i - 1, 0)
					var b := mini(i + 1, n - 1)
					v = (raw[b] as Vector3).distance_to(raw[a]) / maxf(float(ts[b]) - float(ts[a]), 1e-9) if b > a else 0.0
				else:
					v = raw[i]
				vs.append(v)
				match q["op"]:
					"lt":
						ms.append(v - float(q["x"]))
					"gt":
						ms.append(float(q["x"]) - v)
					"between":
						ms.append(maxf(float(q["lo"]) - v, v - float(q["hi"])))
	return [ms, vs]


static func unit_of(kind: String) -> String:
	return "deg" if kind == "angle" else "m/s" if kind == "speed" else "cm"


## a number in the line's unit: m -> cm to 0.01 cm (0.1 mm), deg to 0.01, m/s to 0.001
static func shown(kind: String, v: float) -> Variant:
	if is_inf(v) or is_nan(v):
		return null
	match kind:
		"angle":
			return snappedf(v, 0.01)
		"speed":
			return snappedf(v, 0.001)
	return snappedf(v * 100.0, 0.01)


static func judge(q: Dictionary, raw: Array, ts: Array, fps: float) -> Dictionary:
	var n := raw.size()
	var fr := frames_of(q["window"], fps, n, ts)
	var f0: int = fr[0]
	var f1: int = fr[1]
	var mv := misses(q, raw, ts, f0)
	var ms: Array = mv[0]
	var vs: Array = mv[1]
	var event: bool = q["window"]["mode"] == "at"
	var at := f0
	for i in range(f0, f1 + 1):
		if (event and float(ms[i]) < float(ms[at])) or (not event and float(ms[i]) > float(ms[at])):
			at = i
	var miss: float = ms[at]
	var ok := miss <= EPS
	var kind: String = q["kind"]
	var u := unit_of(kind)
	var out := {"line": q["line"], "ok": true, "pass": ok, "kind": kind,
		"window": {"mode": q["window"]["mode"], "from_s": snappedf(ts[f0], 0.0001), "to_s": snappedf(ts[f1], 0.0001), "frames": [f0, f1]},
		"worst": {"frame": at, "t": snappedf(ts[at], 0.0001), "miss": shown(kind, miss), "unit": u}}
	if kind == "planted":
		out["worst"]["lift_cm"] = snappedf(float(vs[at][0]) * 100.0, 0.01)
		out["worst"]["slide_cm"] = snappedf(float(vs[at][1]) * 100.0, 0.01)
	else:
		out["worst"]["value"] = shown(kind, vs[at])
	var what := _says(q, vs[at])
	if not ok:
		out["miss"] = {"value": shown(kind, miss), "unit": u, "frame": at, "t": snappedf(ts[at], 0.0001)}
		if is_inf(miss):
			out["miss"]["note"] = "no foot on the floor: no support at all"
		if event:   # how far off in time: the nearest frame anywhere in the clip where it holds
			# a planted foot is judged against where it stood at the window's start: elsewhere, against its own frame (lift only)
			var found := false
			var best := 0   # signed frames: - = before the window, + = after
			for i in n:
				var mi: float = (float(raw[i][0]) - DOWN) if kind == "planted" else float(ms[i])
				if mi <= EPS:
					var d: int = (f0 - i) if i < f0 else (i - f1)
					if not found or d < absi(best):
						best = -d if i < f0 else d
						found = true
			if not found:
				out["time_miss"] = {"never": true, "note": "it holds on no frame of the clip"}
			else:
				out["time_miss"] = {"frames": absi(best), "s": snappedf(absi(best) / fps, 0.0001), "late": best > 0,
					"note": "it holds %d frame(s) %s the window" % [absi(best), "after" if best > 0 else "before"]}
	out["say"] = ("PASS  " if ok else "FAIL  ") + String(q["line"]).strip_edges() + ":  " + what + \
		("" if ok else "; misses by %s %s at %.3f s (frame %d)" % [_num(shown(kind, miss)), u, ts[at], at]) + \
		(("; " + String(out["time_miss"]["note"])) if out.has("time_miss") else "")
	return out


static func _num(v: Variant) -> String:
	return "?" if v == null else str(v)


static func _says(q: Dictionary, v: Variant) -> String:
	match q["kind"]:
		"planted":
			return "the toe base is %.1f cm up and has slid %.1f cm (bars: %.0f cm up, %.1f cm slide)" % [float(v[0]) * 100.0, float(v[1]) * 100.0, DOWN * 100.0, SLIDE * 100.0]
		"inside":
			return "no foot on the floor" if is_inf(float(v)) else "the COM is %.1f cm %s the feet's edge" % [absf(float(v)) * 100.0, "inside" if float(v) >= 0.0 else "past"]
		"touches", "distance":
			return "the gap is %.1f cm" % (float(v) * 100.0)
		"angle":
			return "%s %s is %.1f deg" % [q["joint"], q["axis"], float(v)]
		"speed":
			return "%.2f m/s" % float(v)
	return ""


## the saved assertions as Check findings: a failing one is MUST FIX at its worst frame, with the miss; an unread one is a look
static func findings(S: Scene, B: Body) -> Array:
	var out := []
	if S.asserts.is_empty() or S.cards.size() < 2:
		return out
	var r := run(S, B, S.asserts)
	for x in r["results"]:
		if not x["ok"]:
			out.append({"sev": "WARN", "t": 0.0, "card": -1, "rule": "ASSERT", "msg": "a saved assertion I can't read: '%s' (%s)" % [x["line"], x["error"]], "v": 0.0, "line": x["line"]})
		elif not x["pass"]:
			var mi: Dictionary = x["miss"]
			var v: float = 0.0 if mi["value"] == null else float(mi["value"])
			out.append({"sev": "FAIL", "t": float(mi["t"]), "card": -1, "rule": "ASSERT", "msg": String(x["say"]).trim_prefix("FAIL  "), "v": v,
				"line": x["line"], "miss": mi})
	return out


## Mirror the scene: each line's sides swap (left <-> right, _l <-> _r); fighters and times are free
static func mirror_file(lines: Array) -> Array:
	var rx := _re("(?i)\\b(left|right)\\b|_(l|r)\\b")
	return lines.map(func(l):
		var s := String(l)
		var out := ""
		var at := 0
		for m in rx.search_all(s):
			out += s.substr(at, m.get_start() - at)
			var w := m.get_string()
			out += {"left": "right", "right": "left", "_l": "_r", "_r": "_l", "Left": "Right", "Right": "Left"}.get(w, w)
			at = m.get_end()
		return out + s.substr(at))


## the file form: the lines that are text, trimmed, empty ones dropped
static func from_file(d: Variant) -> Array:
	var out := []
	if d is Array:
		for l in d:
			if l is String and String(l).strip_edges() != "":
				out.append(String(l).strip_edges())
	return out
