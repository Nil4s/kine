## range_sweep.gd - SAFE RANGE SWEEP (docs/INNOVATIONS.md N013). R10 `ask` (what_if.gd) tests ONE value ("what if the
## right hip flexes 40"); a blind agent then guesses the next value and asks again. This answers the real question in one
## call: "what values of X keep ALL of these true?" -> the interval(s) of X, in the joint's own degrees and inside its
## limits, with what bounds each end and how much slack every condition has there, so the agent picks INSIDE the range.
##   serve: range {joint: "right hip", axis: "flex", conditions: ["balance", "reach right fist to 0.25,1.35,0.45 within 2 cm",
##                 "left foot planted"], card?: N | t?: s, step?: deg, from?: deg, to?: deg, joint2?, axis2?, step2?}
##   CLI:   range <scene.json|-> [card=N] [t=S] [step=D] <joint> <axis> "<condition>" ...
## CONDITIONS (a string, or a {"balance" | "reach" | "limits" | "line": ...} dictionary):
##   balance [N cm]        Balance.read (de Leva COM over the feet's support polygon, scripts/balance.gd): a foot down and
##                         margin >= N cm (default 0: the COM's floor point on or inside the polygon). slack = margin - N, cm.
##   reach <thing> to <target> [within D cm|mm|m]   the gap from the thing to the target <= D (default 1 cm = Balance.TOUCH,
##                         what the balance code already counts as touching). thing / target are N002 things (body_assert.gd:
##                         "right fist" = its capsule's SURFACE, "hand_r" / "right wrist" = the joint CENTRE, "chin" a surface
##                         point, "fighter 2 head") or a target point "x,y,z" in m (the hero's space `state` gives: y up).
##                         gap = BodyAssert.gap (segment-segment distance minus both radii). slack = D - gap, cm.
##   limits [N deg]        every value of X stays N deg (default 0) inside its joint limit (data/body_limits.json via B.lim).
##                         slack = min(x - lo, hi - x) - N, deg. (The sweep never leaves the limits anyway: this only adds a
##                         keep-away band.)
##   anything else         an N002 body assertion line (scripts/body_assert.gd grammar, e.g. "right knee below 60 deg flex",
##                         "right fist at least 20 cm from chin"). slack = -miss in the line's unit (cm / deg).
## WHERE IT IS EVALUATED (stated, because it changes the answer):
##   no card / t   the body AS IT STANDS (the live pose, what `state` without t gives); X is set with Body.set_ang (the
##                 joint's limits; NO stop where parts meet: the sweep asks about the angle, set_ang_safe would answer a
##                 different angle). N002 lines are measured on that one pose: their window is ignored, "speed" is refused
##                 (one pose has no speed), a planted foot is its lift only (slide 0 on one frame).
##   t: S          the scene's pose at S seconds (Scene.apply_true: the cards as made, no dummy landing), then as above;
##                 a fighter 2+ thing is that actor at S.
##   card: N       X is written into card N's pose (a copy; the original dictionary object is put back after) and N002
##                 lines run over the CLIP with their own windows (BodyAssert's measures and judge, as `assert`; the frames
##                 the card cannot move are played once: _clip_prepare); balance / reach /
##                 limits are read on card N's own pose. Each sample plays the clip, so this mode is slower (stated in ms).
## THE SWEEP: a coarse grid over the domain (default 2 deg steps: HEURISTIC, fine enough that a pass island narrower than
## that is the only thing missed; say step: to go finer), then each pass/fail boundary is bisected until its bracket is
## <= 0.05 deg, and the end is reported on the PASSING side, snapped inward to 0.01 deg (so the reported end itself
## passes and the value 0.1 deg outward fails). A second variable (joint2 / axis2) gives a small pass/fail grid instead.
## Nothing is changed: the body state, the last stop, the card's pose object and the playhead are put back exactly.
class_name RangeSweep
extends RefCounted

const STEP := 2.0           # deg: the coarse grid, pose mode (HEURISTIC: 76 samples over a 150 deg hip range)
const STEP_CARD := 5.0      # deg: the coarse grid, card mode (each sample plays the clip)
const TOL := 0.05           # deg: a boundary's bracket is bisected to this (the item asks for 0.1 deg)
const MAP_MAX := 25         # a 2D map has at most this many values per side
const NUM := "(-?\\d+(?:\\.\\d+)?)"


static func _err(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}


static func _re(p: String) -> RegEx:
	return RegEx.create_from_string(p)


# ------------------------------------------------------------------------------------------------ conditions
## one condition (a string or a dictionary) -> {"ok", "name", "kind", "unit", ...} or {"ok": false, "error"}
static func condition(c: Variant) -> Dictionary:
	if c is Dictionary:
		var d: Dictionary = c
		if d.has("balance"):
			var bv: Variant = d["balance"]
			return {"ok": true, "kind": "balance", "name": "balance", "unit": "cm",
				"min_m": (float(bv.get("margin_cm", 0.0)) if bv is Dictionary else (float(bv) if (bv is float or bv is int) else 0.0)) / 100.0}
		if d.has("limits"):
			var lv: Variant = d["limits"]
			return {"ok": true, "kind": "limits", "name": "limits", "unit": "deg",
				"min": float(lv.get("margin_deg", 0.0)) if lv is Dictionary else (float(lv) if (lv is float or lv is int) else 0.0)}
		if d.has("reach"):
			var th := BodyAssert.thing(BodyAssert.norm(String(d["reach"])))
			if not th["ok"]:
				return _err("reach: " + String(th["error"]))
			var to := _target(d.get("to", null))
			if not to["ok"]:
				return to
			var w := float(d.get("within_cm", BodyAssert.TOUCH * 100.0)) / 100.0
			return {"ok": true, "kind": "reach", "name": "reach %s to %s within %.1f cm" % [d["reach"], to["name"], w * 100.0], "unit": "cm",
				"a": th, "b": to["thing"], "within": w}
		if d.has("line"):
			return condition(String(d["line"]))
		return _err("a condition dictionary needs one of balance, reach, limits or line (got %s)" % JSON.stringify(d))
	if not (c is String):
		return _err("a condition is a string or a dictionary (got %s)" % str(c))
	var s := String(c).strip_edges()
	var low := s.to_lower()
	var m := _re("^balance(?:d|\\s+margin)?(?:\\s+(?:at least\\s+)?" + NUM + "\\s*(mm|cm|m))?$").search(low)
	if m != null:
		var mn := 0.0
		if m.get_string(1) != "":
			mn = float(m.get_string(1)) * float({"mm": 0.001, "cm": 0.01, "m": 1.0}[m.get_string(2)])
		return {"ok": true, "kind": "balance", "name": s, "unit": "cm", "min_m": mn}
	m = _re("^(?:joint\\s+)?limits?(?:\\s+" + NUM + "\\s*(?:deg|degrees)?)?$").search(low)
	if m != null:
		return {"ok": true, "kind": "limits", "name": s, "unit": "deg", "min": float(m.get_string(1)) if m.get_string(1) != "" else 0.0}
	m = _re("^reach(?:es)?\\s+(.+?)\\s+(?:to|at)\\s+(.+?)(?:\\s+within\\s+" + NUM + "\\s*(mm|cm|m))?$").search(low)
	if m != null:
		var th := BodyAssert.thing(BodyAssert.norm(m.get_string(1)))
		if not th["ok"]:
			return _err("'%s': %s" % [s, th["error"]])
		var to := _target(m.get_string(2))
		if not to["ok"]:
			return _err("'%s': %s" % [s, to["error"]])
		var w := BodyAssert.TOUCH
		if m.get_string(3) != "":
			w = float(m.get_string(3)) * float({"mm": 0.001, "cm": 0.01, "m": 1.0}[m.get_string(4)])
		return {"ok": true, "kind": "reach", "name": s, "unit": "cm", "a": th, "b": to["thing"], "within": w}
	var q := BodyAssert.parse(s)
	if not q["ok"]:
		return {"ok": false, "error": "'%s': %s. A condition is balance [N cm], reach <thing> to <x,y,z | thing> [within D cm], limits [N deg], or an N002 line" % [s, q["error"]], "grammar": BodyAssert.GRAMMAR}
	return {"ok": true, "kind": "line", "name": s, "unit": BodyAssert.unit_of(q["kind"]), "q": q}


## a reach target: [x, y, z] / "x,y,z" (m) -> a point thing; else an N002 thing
static func _target(t: Variant) -> Dictionary:
	var pt: Variant = null
	if t is Array and (t as Array).size() == 3:
		pt = Vector3(float(t[0]), float(t[1]), float(t[2]))
	elif t is String:
		var m := _re("^\\s*\\(?\\s*" + NUM + "\\s*[, ]\\s*" + NUM + "\\s*[, ]\\s*" + NUM + "\\s*\\)?\\s*(?:m)?\\s*$").search(String(t))
		if m != null:
			pt = Vector3(float(m.get_string(1)), float(m.get_string(2)), float(m.get_string(3)))
		else:
			var th := BodyAssert.thing(BodyAssert.norm(String(t)))
			if not th["ok"]:
				return _err("reach target: " + String(th["error"]) + " (or give a point \"x,y,z\" in m)")
			return {"ok": true, "thing": th, "name": String(t)}
	if pt == null:
		return _err("reach needs a target: to = [x, y, z] (m, the hero's space) or a body thing like \"chin\" / \"fighter 2 head\"")
	return {"ok": true, "thing": {"ok": true, "kind": "point", "fighter": 0, "p": pt, "name": "(%.3f, %.3f, %.3f) m" % [pt.x, pt.y, pt.z]},
		"name": "(%.3f, %.3f, %.3f) m" % [pt.x, pt.y, pt.z]}


static func _shapes(th: Dictionary, Bk: Body, X: Transform3D) -> Array:
	if th["kind"] == "point":
		var p: Vector3 = th["p"]
		return [[p, p, 0.0]]
	return BodyAssert.shapes(th, Bk, X)


static func _fighters_of(c: Dictionary) -> Array:
	var ks := []
	match c["kind"]:
		"reach":
			ks = [int(c["a"]["fighter"]), int(c["b"]["fighter"])]
		"line":
			for key in ["a", "b"]:
				if (c["q"] as Dictionary).has(key):
					ks.append(int(c["q"][key]["fighter"]))
	return ks


# ------------------------------------------------------------------------------------------------ evaluation
## the slack of every condition on the pose the context's body now holds -> [[holds, slack (unit) or null], ...]
static func _on_pose(cx: Dictionary, x: float) -> Array:
	var B: Body = cx["B"]
	var out := []
	for c in cx["conds"]:
		match c["kind"]:
			"balance":
				var r := Balance.read(B)
				if (r["down"] as Array).is_empty():
					out.append([false, null])
				else:
					var sl: float = float(r["margin"]) - float(c["min_m"])
					out.append([sl >= 0.0, sl * 100.0])
			"limits":
				var L: Vector2 = cx["lim"]
				var sl := minf(x - L.x, L.y - x) - float(c["min"])
				out.append([sl >= -1e-9, sl])
			"reach":
				var ka := int(c["a"]["fighter"])
				var kb := int(c["b"]["fighter"])
				var g := BodyAssert.gap(_shapes(c["a"], cx["bodies"][ka], cx["xfs"][ka]), _shapes(c["b"], cx["bodies"][kb], cx["xfs"][kb]))
				var sl: float = float(c["within"]) - g
				out.append([sl >= -1e-9, sl * 100.0])
			"line":
				if cx["mode"] == "card":
					out.append(null)   # filled from BodyAssert.run over the clip
					continue
				var q: Dictionary = c["q"]
				var raw: Variant = _raw(q, cx["bodies"], cx["xfs"])
				var mi: float = float((BodyAssert.misses(q, [raw], [0.0], 0)[0] as Array)[0])
				var sh: Variant = BodyAssert.shown(q["kind"], -mi)
				out.append([mi <= BodyAssert.EPS, sh])
	return out


## one frame of one N002 line, measured as BodyAssert.run measures it (the same match, on one pose)
static func _raw(q: Dictionary, bodies: Dictionary, xfs: Dictionary) -> Variant:
	var ka := int(q["a"]["fighter"])
	var Ba: Body = bodies[ka]
	var Xa: Transform3D = xfs[ka]
	match q["kind"]:
		"planted":
			var bp: Vector3 = Xa * (Ba.P["ball" + String(q["foot"])] as Vector3)
			return [BodyAssert.lift(Ba, q["foot"]), Vector2(bp.x, bp.z)]
		"inside":
			var r := Balance.read(Ba)
			return float(r["margin"]) if (r["down"] as Array).size() > 0 else -INF
		"touches", "distance":
			var kb := int(q["b"]["fighter"])
			return BodyAssert.gap(BodyAssert.shapes(q["a"], Ba, Xa), BodyAssert.shapes(q["b"], bodies[kb], xfs[kb]))
		"angle":
			return float((Ba.ang[q["joint"]] as Vector3)[WhatIf.AXI[q["axis"]]])
	return 0.0


## put X (and Y) on the body / the card and measure every condition -> {"pass", "c": [[holds, slack], ...]}
static func _eval(cx: Dictionary, x: float, y: Variant = null) -> Dictionary:
	cx["n"] = int(cx["n"]) + 1
	var B: Body = cx["B"]
	var j: String = cx["joint"]
	var ai: int = cx["ai"]
	var res: Array
	if cx["mode"] == "card":
		var S: Scene = cx["S"]
		var k: int = cx["card"]
		var pose: Dictionary = (cx["orig"] as Dictionary).duplicate(true)
		_put(pose, j, ai, x)
		if y != null:
			_put(pose, cx["joint2"], cx["ai2"], float(y))
		S.cards[k]["pose"] = pose
		B.from_dict(pose)   # the card's own pose: balance / reach / limits are read on it
		res = _on_pose(cx, x)
		if cx["has_lines"]:
			_clip_lines(cx, res)
		S.cards[k]["pose"] = cx["orig"]
	else:
		var v: Vector3 = cx["base"]
		v[ai] = x
		B.set_ang(j, v)
		if y != null:
			var j2: String = cx["joint2"]
			var v2: Vector3 = v if j2 == j else (cx["base2"] as Vector3)
			v2[int(cx["ai2"])] = float(y)
			B.set_ang(j2, v2)
		res = _on_pose(cx, x)
	var ok := true
	for r in res:
		ok = ok and bool(r[0])
	return {"pass": ok, "c": res}


## CARD MODE, THE CLIP: N002 lines measured frame by frame as BodyAssert.run measures them (its match, its judge), on
## the scene with the card as it now is. A frame the card cannot move is not played again: _clip_prepare plays the clip
## three times (the card as made, the swept joint at the domain's low end, at its high end) and a frame whose body state
## (Body.state: every angle, the offset, the weapon) is the same in all three is taken as untouched by the card, its
## measures kept from the first pass. (ASSUMED: a frame the two extremes leave unchanged is unchanged in between; the
## test checks the answer against BodyAssert.run on the whole clip at the pick and past each end.) combo3 card 2: a
## sample played 141 frames (~720 ms measured); "exact": true plays every frame every sample.
static func _clip_prepare(cx: Dictionary, lo: float, hi: float, exact: bool) -> void:
	var S: Scene = cx["S"]
	var B: Body = cx["B"]
	var fps := float(S.fps)
	var L := S.length()
	var n := int(floor(L * fps + 1e-6)) + 1
	var ts := []
	for i in n:
		ts.append(minf(i / fps, L))
	var qs := []
	for c in cx["conds"]:
		if c["kind"] == "line":
			qs.append(c["q"])
	var bodies := {0: B}
	var xfs := {0: Transform3D.IDENTITY}
	for q in qs:
		for key in ["a", "b"]:
			var kf := int(q[key]["fighter"]) if (q as Dictionary).has(key) else 0
			if kf > 0 and not bodies.has(kf):
				var bk := Body.new()
				bk.load_files("res://data/skeleton.json", "res://data/body_limits.json")
				bk.fk()
				bodies[kf] = bk
				xfs[kf] = Constraints.actor_xf(S.actors[kf - 1]["xf"])
	cx["clip"] = {"n": n, "ts": ts, "fps": fps, "qs": qs, "bodies": bodies, "xfs": xfs}
	var k: int = cx["card"]
	var sig0 := []
	var base := []   # base[qi][i]: the card as made
	for q in qs:
		base.append([])
	for i in n:
		_play(cx, ts[i])
		sig0.append(var_to_str(B.state()))
		for qi in qs.size():
			base[qi].append(_frame_raw(qs[qi], bodies, xfs))
	var moved := []
	moved.resize(n)
	moved.fill(exact)
	if not exact:
		for x in [lo, hi]:
			var pose: Dictionary = (cx["orig"] as Dictionary).duplicate(true)
			_put(pose, cx["joint"], cx["ai"], x)
			if cx.has("joint2"):
				for y in [(cx["lim2"] as Vector2).x, (cx["lim2"] as Vector2).y]:
					var p2 := pose.duplicate(true)
					_put(p2, cx["joint2"], cx["ai2"], y)
					S.cards[k]["pose"] = p2
					for i in n:
						if not moved[i]:
							S.apply_true(B, ts[i])
							moved[i] = var_to_str(B.state()) != sig0[i]
			S.cards[k]["pose"] = pose
			for i in n:
				if not moved[i]:
					S.apply_true(B, ts[i])
					moved[i] = var_to_str(B.state()) != sig0[i]
		S.cards[k]["pose"] = cx["orig"]
	cx["clip"]["base"] = base
	cx["clip"]["moved"] = moved
	cx["clip"]["played"] = moved.count(true)


static func _play(cx: Dictionary, t: float) -> void:
	var S: Scene = cx["S"]
	(S as Scene).apply_true(cx["B"], t)
	var cl: Dictionary = cx["clip"]
	for kf in cl["bodies"]:
		if kf > 0:
			(S.actors[kf - 1]["scene"] as Scene).apply_true(cl["bodies"][kf], t)


static func _frame_raw(q: Dictionary, bodies: Dictionary, xfs: Dictionary) -> Variant:
	if q["kind"] == "speed":
		var ka := int(q["a"]["fighter"])
		return BodyAssert.point(q["a"], bodies[ka], xfs[ka])
	return _raw(q, bodies, xfs)


static func _clip_lines(cx: Dictionary, res: Array) -> void:
	var cl: Dictionary = cx["clip"]
	var qs: Array = cl["qs"]
	var raw := []
	for qi in qs.size():
		raw.append((cl["base"][qi] as Array).duplicate())
	var moved: Array = cl["moved"]
	for i in int(cl["n"]):
		if moved[i]:
			_play(cx, cl["ts"][i])
			for qi in qs.size():
				raw[qi][i] = _frame_raw(qs[qi], cl["bodies"], cl["xfs"])
	var qi := 0
	for ci in (cx["conds"] as Array).size():
		if cx["conds"][ci]["kind"] == "line":
			var r := BodyAssert.judge(qs[qi], raw[qi], cl["ts"], float(cl["fps"]))
			qi += 1
			var mv: Variant = r["worst"]["miss"]
			res[ci] = [bool(r["pass"]), null if mv == null else -float(mv)]


static func _put(pose: Dictionary, j: String, ai: int, x: float) -> void:
	var js: Dictionary = pose.get("joints", {})
	if not js.has(j):
		js[j] = {"bend": 0.0, "side": 0.0, "twist": 0.0}
	js[j][["bend", "side", "twist"][ai]] = x
	pose["joints"] = js


# ------------------------------------------------------------------------------------------------ the sweep
## m = the main node; p = serve's params. Returns {"ok", "intervals", "text", ...}; nothing in the session changes
static func run(m: Node, p: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var B: Body = m.B
	var S: Scene = m.S
	var j := WhatIf.joint_name(String(p.get("joint", "")))
	if j == "":
		return _err("range needs {\"joint\": \"right hip\" | \"thigh_r\" | \"elbow_r\", \"axis\": \"flex\", \"conditions\": [...]} (got joint '%s')" % p.get("joint", ""))
	var ax: String = WhatIf.AXES.get(String(p.get("axis", "bend")).to_lower(), "")
	if ax == "":
		return _err("no axis '%s': say flex (bend), side or twist" % p.get("axis", ""))
	var cl: Variant = p.get("conditions", [])
	if cl is String:
		cl = [cl]
	if not (cl is Array) or (cl as Array).is_empty():
		return _err("range needs {\"conditions\": [\"balance\", \"reach right fist to 0.25,1.35,0.45 within 2 cm\", \"left foot planted\", ...]}")
	var conds := []
	for c in cl:
		var cd := condition(c)
		if not cd["ok"]:
			return cd
		conds.append(cd)
	var L: Vector2 = B.lim[j][ax]
	if L.y - L.x <= 0.5:
		return _err("%s %s is a LOCKED axis (%.0f..%.0f deg): nothing to sweep" % [j, ax, L.x, L.y])
	var lo := maxf(L.x, float(p.get("from", L.x)))
	var hi := minf(L.y, float(p.get("to", L.y)))
	if hi <= lo:
		return _err("from %.1f to %.1f leaves nothing inside the joint's limits %.0f..%.0f deg" % [p.get("from", L.x), p.get("to", L.y), L.x, L.y])
	var mode := "card" if p.has("card") else ("t" if p.has("t") else "pose")
	var cx := {"B": B, "S": S, "joint": j, "ai": int(WhatIf.AXI[ax]), "conds": conds, "lim": L, "mode": mode, "n": 0,
		"has_lines": conds.any(func(c): return c["kind"] == "line")}
	if mode != "card":
		for c in conds:
			if c["kind"] == "line" and c["q"]["kind"] == "speed":
				return _err("'%s': a speed needs a clip; one pose has none. Sweep a card instead: {\"card\": N}" % c["name"])
	var two := p.has("joint2")
	if two:
		var j2 := WhatIf.joint_name(String(p["joint2"]))
		var ax2: String = WhatIf.AXES.get(String(p.get("axis2", "bend")).to_lower(), "")
		if j2 == "" or ax2 == "":
			return _err("joint2 / axis2: no joint '%s' or axis '%s'" % [p["joint2"], p.get("axis2", "")])
		if j2 == j and ax2 == ax:
			return _err("joint2 / axis2 is the same variable as joint / axis")
		cx["joint2"] = j2
		cx["ax2"] = ax2
		cx["ai2"] = int(WhatIf.AXI[ax2])
		cx["lim2"] = B.lim[j2][ax2]
	var keep: Dictionary = B.state()
	var keep_stop: Dictionary = B.last_stop.duplicate(true)
	var at_t: float = m.playhead
	if mode == "card":
		var k := int(p["card"]) - 1
		if k < 0 or k >= S.cards.size():
			return _err("no card %s (the scene has %d)" % [str(p["card"]), S.cards.size()])
		if cx["has_lines"] and S.cards.size() < 2:
			return _err("N002 lines in card mode run over the clip: the scene needs 2+ cards")
		cx["card"] = k
		cx["orig"] = S.cards[k]["pose"]
		at_t = float(S.times()[k][1])
	elif mode == "t":
		if S.cards.size() < 2 or not (p["t"] is float or p["t"] is int):
			return _err("range {\"t\": seconds} needs a number and a scene of 2+ cards: open one first")
		at_t = float(p["t"])
		S.apply_true(B, at_t)
	# the other fighters a condition names, placed at the moment swept (the actors' scenes at at_t)
	var bodies := {0: B}
	var xfs := {0: Transform3D.IDENTITY}
	for c in conds:
		for kf in _fighters_of(c):
			if kf > 0 and not bodies.has(kf):
				if kf > S.actors.size():
					B.set_state(keep)
					return _err("'%s': there is no fighter %d (the scene has %d)" % [c["name"], kf + 1, S.actors.size() + 1])
				var bk := Body.new()
				bk.load_files("res://data/skeleton.json", "res://data/body_limits.json")
				(S.actors[kf - 1]["scene"] as Scene).apply_true(bk, at_t)
				bodies[kf] = bk
				xfs[kf] = Constraints.actor_xf(S.actors[kf - 1]["xf"])
	cx["bodies"] = bodies
	cx["xfs"] = xfs
	var base: Vector3
	if mode == "card":
		var fl := Moves._flat(cx["orig"])
		base = fl["ang"].get(j, Vector3.ZERO)
		if two:
			cx["now2"] = float((fl["ang"].get(cx["joint2"], Vector3.ZERO) as Vector3)[int(cx["ai2"])])
	else:
		base = B.ang[j]
		if two:
			cx["base2"] = B.ang[cx["joint2"]]
			cx["now2"] = float((B.ang[cx["joint2"]] as Vector3)[int(cx["ai2"])])
	cx["base"] = base
	var now: float = base[int(cx["ai"])]
	var step := maxf(float(p.get("step", STEP_CARD if mode == "card" else STEP)), 0.1)
	if mode == "card" and cx["has_lines"]:
		_clip_prepare(cx, lo, hi, bool(p.get("exact", false)))
	var out: Dictionary
	if two:
		out = _map(cx, lo, hi, p)
	else:
		out = _sweep(cx, lo, hi, step, now)
	# put everything back exactly
	if mode == "card":
		S.cards[int(cx["card"])]["pose"] = cx["orig"]
	B.set_state(keep)
	B.last_stop = keep_stop
	out.merge({"ok": true, "joint": j, "axis": ax, "unit": "deg", "mode": mode, "limits": [L.x, L.y], "domain": [lo, hi],
		"now": snappedf(now, 0.01), "conditions": conds.map(func(c): return c["name"]),
		"where": {"pose": "the body as it stands", "t": "the scene's pose at %.3f s" % at_t, "card": "card %d's pose (N002 lines over the clip)" % (int(cx.get("card", 0)) + 1)}[mode],
		"clip_frames_played": "%d of %d per sample" % [cx["clip"]["played"], cx["clip"]["n"]] if cx.has("clip") else null,
		"samples": cx["n"], "ms": snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1), "scene_changed": false})
	(out["text"] as Array).push_front("%s %s, %s (limits %.0f..%.0f deg); %d samples, %.0f ms; nothing changed" % [j, ax, out["where"], L.x, L.y, cx["n"], out["ms"]])
	return out


static func _sweep(cx: Dictionary, lo: float, hi: float, step: float, now: float) -> Dictionary:
	var conds: Array = cx["conds"]
	var n := maxi(int(ceil((hi - lo) / step - 1e-9)), 1)
	var xs := []
	var ev := []
	for i in n + 1:
		var x := lo + (hi - lo) * float(i) / float(n)
		xs.append(x)
		ev.append(_eval(cx, x))
	# each boundary bisected: [x_pass, x_fail, eval at x_pass, eval at x_fail]
	var ivs := []
	var cur = null   # the open interval: {"lo_x", "lo_end"}
	for i in xs.size():
		if ev[i]["pass"] and cur == null:
			if i == 0:
				cur = {"from": xs[0], "lo_end": _end_at(cx, xs[0], ev[0], null, "lo", lo, hi)}
			else:
				var bb := _bisect(cx, xs[i], xs[i - 1], ev[i], ev[i - 1])
				cur = {"from": bb[0], "lo_end": _end_at(cx, bb[0], bb[2], bb[3], "lo", lo, hi)}
		elif not ev[i]["pass"] and cur != null:
			var bb := _bisect(cx, xs[i - 1], xs[i], ev[i - 1], ev[i])
			ivs.append(_iv(cur, bb[0], _end_at(cx, bb[0], bb[2], bb[3], "hi", lo, hi)))
			cur = null
	if cur != null:
		ivs.append(_iv(cur, xs[-1], _end_at(cx, xs[-1], ev[-1], null, "hi", lo, hi)))
	# each condition alone, on the grid: where it holds and its best slack (what an empty answer explains with)
	var alone := []
	for ci in conds.size():
		var on := []
		var best = null
		var best_x := 0.0
		var run0 = null
		for i in xs.size():
			var r: Array = ev[i]["c"][ci]
			if r[1] != null and (best == null or float(r[1]) > float(best)):
				best = r[1]
				best_x = xs[i]
			if r[0] and run0 == null:
				run0 = xs[i]
			elif not r[0] and run0 != null:
				on.append([snappedf(run0, 0.01), snappedf(xs[i - 1], 0.01)])
				run0 = null
		if run0 != null:
			on.append([snappedf(run0, 0.01), snappedf(xs[-1], 0.01)])
		alone.append({"condition": conds[ci]["name"], "kind": conds[ci]["kind"], "unit": conds[ci]["unit"], "holds_on": on,
			"never": on.is_empty(), "best_slack": null if best == null else snappedf(float(best), 0.01), "best_at": snappedf(best_x, 0.01)})
	var inside := false
	var to_edge = null
	for iv in ivs:
		if now >= float(iv["from"]) - 0.005 and now <= float(iv["to"]) + 0.005:
			inside = true
			to_edge = snappedf(minf(now - float(iv["from"]), float(iv["to"]) - now), 0.01)
	var text := []
	if ivs.is_empty():
		var nev := alone.filter(func(a): return a["never"])
		if not nev.is_empty():
			for a in nev:
				text.append("EMPTY: '%s' holds for NO value of %s %s in %.1f..%.1f deg%s" % [a["condition"], cx["joint"], ["bend", "side", "twist"][int(cx["ai"])], lo, hi,
					("" if a["best_slack"] == null else "; closest at %.1f deg, still %.2f %s short" % [a["best_at"], -float(a["best_slack"]), a["unit"]])])
		else:
			text.append("EMPTY: each condition holds somewhere, never all at once: " + "; ".join(alone.map(func(a): return "'%s' on %s" % [a["condition"], " + ".join((a["holds_on"] as Array).map(func(h): return "%.1f..%.1f" % [h[0], h[1]]))])))
	else:
		for iv in ivs:
			text.append("SAFE %.2f .. %.2f deg (%.2f wide, pick %.1f): low end %s; high end %s" % [iv["from"], iv["to"], iv["width"], iv["pick"], _end_words(iv["ends"][0]), _end_words(iv["ends"][1])])
	text.append("now %.2f deg: %s" % [now, ("inside, %.2f deg from the nearest end" % to_edge) if inside else "OUTSIDE every safe range"])
	return {"intervals": ivs, "empty": ivs.is_empty(), "never": alone.filter(func(a): return a["never"]).map(func(a): return a["condition"]),
		"alone": alone, "now_inside": inside, "now_to_edge_deg": to_edge, "step": snappedf((hi - lo) / float(n), 0.001), "text": text}


static func _iv(cur: Dictionary, to: float, hi_end: Dictionary) -> Dictionary:
	var a := ceilf(float(cur["from"]) * 100.0 - 1e-6) / 100.0 + 0.0   # snapped INWARD: the reported end itself passes (+ 0.0: no "-0")
	var b := floorf(to * 100.0 + 1e-6) / 100.0 + 0.0
	if b < a:   # a sliver narrower than 0.01 deg
		a = snappedf(float(cur["from"]), 0.01)
		b = a
	var e0: Dictionary = cur["lo_end"]
	e0["value"] = a
	hi_end["value"] = b
	return {"from": a, "to": b, "width": snappedf(b - a, 0.01), "pick": snappedf((a + b) * 0.5, 0.01), "ends": [e0, hi_end]}


## [x_pass, x_fail] -> bisected until <= TOL apart: [x_pass, x_fail, eval_pass, eval_fail]
static func _bisect(cx: Dictionary, xp: float, xf: float, ep: Dictionary, ef: Dictionary) -> Array:
	while absf(xf - xp) > TOL:
		var xm := (xp + xf) * 0.5
		var em := _eval(cx, xm)
		if em["pass"]:
			xp = xm
			ep = em
		else:
			xf = xm
			ef = em
	return [xp, xf, ep, ef]


## what bounds an end: the conditions that fail just outside it (or the joint's limit / the asked range), and every
## condition's slack at the end
static func _end_at(cx: Dictionary, x: float, ep: Dictionary, ef: Variant, side: String, lo: float, hi: float) -> Dictionary:
	var conds: Array = cx["conds"]
	var by := []
	if ef == null:
		var L: Vector2 = cx["lim"]
		var lim_end: bool = absf(x - (L.x if side == "lo" else L.y)) < 1e-6
		by.append("joint limit %.0f deg" % (L.x if side == "lo" else L.y) if lim_end else "the asked range's end %.1f deg" % (lo if side == "lo" else hi))
	else:
		for ci in conds.size():
			if not bool(ef["c"][ci][0]):
				by.append(conds[ci]["name"])
	var sl := {}
	for ci in conds.size():
		var v: Variant = ep["c"][ci][1]
		sl[conds[ci]["name"]] = null if v == null else snappedf(float(v), 0.01)
	return {"side": side, "bound_by": by, "slack": sl}


static func _end_words(e: Dictionary) -> String:
	var bits := []
	for k in e["slack"]:
		if e["slack"][k] != null and k in e["bound_by"]:
			bits.append("%s slack %.2f" % [k, e["slack"][k]])
	return "%.2f, bound by %s%s" % [e["value"], " + ".join(e["bound_by"]), (" (" + ", ".join(bits) + ")") if not bits.is_empty() else ""]


## TWO VARIABLES: a pass / fail grid, at most MAP_MAX values a side; no bisection (a map, to see the shape)
static func _map(cx: Dictionary, lo: float, hi: float, p: Dictionary) -> Dictionary:
	var L2: Vector2 = cx["lim2"]
	var lo2 := maxf(L2.x, float(p.get("from2", L2.x)))
	var hi2 := minf(L2.y, float(p.get("to2", L2.y)))
	var nx := clampi(int(ceil((hi - lo) / maxf(float(p.get("step", 10.0)), 0.1))), 1, MAP_MAX - 1)
	var ny := clampi(int(ceil((hi2 - lo2) / maxf(float(p.get("step2", 10.0)), 0.1))), 1, MAP_MAX - 1)
	var xs := []
	var ys := []
	for i in nx + 1:
		xs.append(snappedf(lo + (hi - lo) * float(i) / float(nx), 0.01))
	for i in ny + 1:
		ys.append(snappedf(lo2 + (hi2 - lo2) * float(i) / float(ny), 0.01))
	var rows := []
	var grid := []
	var npass := 0
	for yi in range(ny, -1, -1):   # the top row = the largest Y, as a plot reads
		var row := ""
		var g := []
		for xi in nx + 1:
			var e := _eval(cx, xs[xi], ys[yi])
			row += "#" if e["pass"] else "."
			g.append(e["pass"])
			npass += 1 if e["pass"] else 0
		rows.append(row)
		grid.push_front(g)
	var text := ["MAP %s %s (x, %.0f..%.0f) by %s %s (y, %.0f..%.0f, top row = %.0f): # = every condition holds" % [cx["joint"], ["bend", "side", "twist"][int(cx["ai"])], lo, hi,
		cx["joint2"], cx["ax2"], lo2, hi2, hi2]]
	text.append_array(rows)
	text.append("%d of %d cells pass" % [npass, (nx + 1) * (ny + 1)])
	return {"map": {"x": xs, "y": ys, "rows": rows, "pass": grid, "passing": npass, "cells": (nx + 1) * (ny + 1),
		"x_joint": cx["joint"], "y_joint": cx["joint2"], "y_axis": cx["ax2"], "y_now": snappedf(float(cx.get("now2", 0.0)), 0.01)},
		"empty": npass == 0, "text": text}
