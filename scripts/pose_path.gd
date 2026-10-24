## PATH TO A POSE (N008, docs/INNOVATIONS.md): from the body as it stands to a named pose (poses/, poses/lib/, a pose
## file), a described one (pose words, scripts/pose_words.gd: "raise the right leg 90, bend the right knee 100") or one
## found by words (R21 pose search, scripts/pose_tags.gd: "kick"), Kine returns the `run` steps that get there. A blind
## agent replays them as they are (serve `run`, or the CLI line); nothing on the way breaks a joint limit, slides a
## planted foot, pushes a part through the floor or passes the body through itself.
##
## HOW (joint space, every number checked on Kine's own body):
##   1 THE TARGET: its raw angles are read BEFORE any clamp; a joint past its range (Body.lim, data/body_limits.json, by
##     more than set_ang_safe's own 0.5 deg) refuses the plan with the joint, the axis, the asked angle and the range.
##     A target that puts the body 2 cm inside itself (feasible.gd's PEN_FIX) is refused too. The target is snapped to the
##     floor (Body.floor_shift, as Snap to floor) when the body now stands on it.
##   2 THE FEET: a foot on the floor now and in the target is a candidate support. The target is moved (root only) so the
##     ANCHOR foot's ankle stays where it is; a candidate whose toe base would then move more than SLIDE_BAR turns on the
##     floor, so it cannot anchor. Both feet that keep their place are PLANTED: the anchor holds the root (the root is
##     solved from it at every waypoint), the other is held by Body.plant (leg IK). A foot that must move (or leave / land
##     on the floor) is the SWING foot: lifted LIFT first, set down from LIFT above its mark last (a straight move would
##     drag it along the floor before it rises: the first 2 deg of stand -> kick chamber move the heel 1.1 cm with the sole
##     still on the floor, measured). Both feet change on the floor (guard_bat's wider stance, toes out 4.6 deg): two
##     moves, one foot steps while the other holds, then the other is lifted and set down as the target has it.
##   3 THE ORDER: all the joints together by default (the shortest path in joint space; Body's limits are boxes per axis,
##     so a straight line between two angles inside them stays inside). Where that passes the body through itself, the
##     joints go in groups, proximal first (hips + legs, back + head, shoulders, forearms + hands), else distal first;
##     where it pushes the swing foot into the floor, a via-pose lifts it there. Each via-pose says why.
##   4 THE WAYPOINTS: the path is cut (bisection, MAX_DEPTH) until the straight line BETWEEN two waypoints, sampled every
##     RES_DEG of the largest joint change, keeps planted feet within PLAN_SLIDE (half the bar), nothing past a limit,
##     through the floor or inside the body. A waypoint is one step: `set=<joint>:b,s,t` per joint that changes (parents
##     first, Body.ORDER) and `root=x,y,z` (the pelvis offset, m) when the root moves.
##   5 THE PROOF: the steps are replayed on the body exactly as `run` runs them (Body.set_ang_safe stops at a contact);
##     a step whose joint is stopped is re-ordered (the stopped joint last); a touch the pose itself has (a salute's hand
##     on the brow, 7.6 mm into the head skin, measured) is set with `put=` (no contact stop, limits kept). The checks
##     are measured on the REPLAYED states, sampled every RES_DEG: limits, planted feet (from their place at the start),
##     any foot dragged on the floor, floor, self-penetration, and the target reached (worst joint, deg).
## The body is put back (B.state) after planning: a dry plan. apply: true then runs the steps through AgentTools.step
## (one undo step each, as `run` would).
## Not planned: the weapon (it stays in the hand as it is), props (the floor is y = 0), balance (N066 owns falling).
class_name PosePath
extends RefCounted

const RES_DEG := 2.0        # deg: the item's check resolution (docs/INNOVATIONS.md N008 test bars)
const SLIDE_BAR := 0.01     # m: a planted foot may not creep more (the item's bar; feasible.gd's SLIDE_FIX is 2.5 cm)
const PLAN_SLIDE := 0.005   # m: the planner keeps to half the bar, so the replay has room (HEURISTIC margin)
const FLOOR_ON := 0.01      # m: a sole point this close to the floor is on it (HEURISTIC; feasible.gd's DOWN_Y is 5 cm on the ball joint)
const SINK_BAR := 0.01      # m: a part this far under the floor is through it (HEURISTIC, = SLIDE_BAR)
const LIFT := 0.06          # m: the swing foot's lift (HEURISTIC, no source: clear of FLOOR_ON with room, so a foot moved in
							# joint space between two waypoints does not touch down early)
const PEN_BAR := Feasible.PEN_FIX   # m: self-penetration bar, feasible.gd's (2 cm)
const LIMIT_TOL := 0.5      # deg: Body.set_ang_safe's own "asked past the range" tolerance
const MAX_STEPS := 64       # steps a plan may have unless max_steps says otherwise
const MAX_DEPTH := 7        # bisections of one move (128 pieces at most)
const GROUPS := [["the hips and legs", ["root", "pelvis", "thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"]],
	["the back and head", ["spine_01", "spine_02", "spine_03", "neck_01", "head"]],
	["the shoulders", ["clavicle_l", "upperarm_l", "clavicle_r", "upperarm_r"]],
	["the forearms and hands", ["lowerarm_l", "hand_l", "lowerarm_r", "hand_r", "*fingers"]]]
const DIRS := ["res://poses", "res://poses/lib"]
const TAG_CACHE := "user://pose_path_tags.json"


static func _side(sd: String) -> String:
	return "left" if sd == "_l" else "right"


static func _other(sd: String) -> String:
	return "_r" if sd == "_l" else "_l"


# ------------------------------------------------------------------ states: {"ang": {joint: Vector3}, "off": Vector3}

static func _snap(B: Body) -> Dictionary:
	return {"ang": (B.ang as Dictionary).duplicate(), "off": B.offset}


static func _put(B: Body, st: Dictionary) -> void:
	var a: Dictionary = st["ang"]
	for j in a:
		B.ang[j] = a[j]
	B.offset = st["off"]
	B.fk()


static func _lerp(a: Dictionary, b: Dictionary, f: float) -> Dictionary:
	var out := {}
	var aa: Dictionary = a["ang"]
	var bb: Dictionary = b["ang"]
	for j in aa:
		out[j] = (aa[j] as Vector3).lerp(bb[j], f)
	return {"ang": out, "off": (a["off"] as Vector3).lerp(b["off"], f)}


static func _delta(a: Dictionary, b: Dictionary) -> float:
	var d := 0.0
	var aa: Dictionary = a["ang"]
	var bb: Dictionary = b["ang"]
	for j in aa:
		var v: Vector3 = (aa[j] as Vector3) - (bb[j] as Vector3)
		d = maxf(d, maxf(absf(v.x), maxf(absf(v.y), absf(v.z))))
	return d


## the values a step's text carries (4 decimals of a degree, 0.01 mm): what the replay will set
static func _round(st: Dictionary) -> Dictionary:
	var out := {}
	for j in st["ang"]:
		var v: Vector3 = st["ang"][j]
		out[j] = Vector3(float("%.4f" % v.x), float("%.4f" % v.y), float("%.4f" % v.z))
	var o: Vector3 = st["off"]
	return {"ang": out, "off": Vector3(float("%.5f" % o.x), float("%.5f" % o.y), float("%.5f" % o.z))}


# ------------------------------------------------------------------ the target

## the target as raw angles (NOT clamped) + its root: {"ok", "ang", "off", "from", "name"?} or {"ok": false, "error"}
static func resolve(B: Body, target: String) -> Dictionary:
	var t := target.strip_edges()
	if t == "":
		return {"ok": false, "error": "path_to_pose needs {\"target\": a pose name (stand, salute, poses/lib/guard_bat), a pose file, or words (\"raise the right leg 90, bend the right knee 100\")}"}
	var path := _pose_file(t)
	if path != "":
		return _from_file(B, path, "pose file")
	var pw := PoseWords.parse(t)
	if pw["ok"]:
		var ang := (B.ang as Dictionary).duplicate()
		for op in pw["ops"]:
			var v: Vector3 = ang[op["joint"]]
			v[op["axis"]] = float(op["deg"]) if op["mode"] == "to" else v[op["axis"]] + float(op["deg"])
			ang[op["joint"]] = v
		var kept := _replant(B, ang, pw["ops"])
		var out := {"ok": true, "ang": ang, "off": B.offset, "from": "words"}
		if not kept.is_empty():
			out["feet_kept"] = kept
		return out
	# R21: the pose library searched by words (names and computed tags)
	var items := []
	for e in list_poses():
		items.append(e)
	var ix := PoseTags.Index.new()
	ix.cache_path = TAG_CACHE
	ix.build(items)
	var hits := ix.search(t)
	if not hits.is_empty():
		var e: Dictionary = ix.entries[hits[0]["i"]]
		var r := _from_file(B, e["path"], "pose search")
		if r["ok"]:
			r["search"] = {"q": t, "pose": e["name"], "tags": hits[0]["chips"], "others": hits.slice(1, 4).map(func(h): return ix.entries[h["i"]]["name"])}
		return r
	return {"ok": false, "error": "'%s' is not a pose name, a pose file, pose words, nor matches a pose by words. %s. Poses: %s" % [t, pw["error"],
		", ".join(list_poses().map(func(e): return e["name"]))]}


## WORDS MOVE WHAT THEY NAME: "turn the hips left 40" turns the pelvis, the root of the whole body, so taken literally
## both feet swing round 40 deg with it and the target stands somewhere else. Words that name no leg mean the feet stay:
## a foot on the floor now that the words moved off its place (more than 1 mm) is put back by its leg (Body.plant, the
## IK the plant tools use), so the target's legs are the ones that keep it there. ang is changed in place; the body is
## put back. Returns the feet kept ("left" / "right")
static func _replant(B: Body, ang: Dictionary, ops: Array) -> Array:
	var legs := {}
	for op in ops:
		for sd in ["_l", "_r"]:
			if op["joint"] in ["thigh" + sd, "calf" + sd, "foot" + sd, "ball" + sd]:
				legs[sd] = true
	if not past_limit(B, ang).is_empty():
		return []   # refused anyway: the joint past its range is named
	var keep := B.state()
	var ref := _feet_ref(B)
	for j in ang:
		B.ang[j] = ang[j]
	B.fk()
	var kept := []
	for sd in ["_l", "_r"]:
		if not ref[sd]["on"] or legs.has(sd):
			continue
		if ((B.P["foot" + sd] as Vector3) - (ref[sd]["ankle"] as Vector3)).length() < 0.001 and ((B.P["ball" + sd] as Vector3) - (ref[sd]["ball"] as Vector3)).length() < 0.001:
			continue
		if B.plant(sd, ref[sd]["ball"], ref[sd]["head"], ref[sd]["flat"]) < 0.003:
			kept.append(_side(sd))
	if not kept.is_empty():
		for j in ang:
			ang[j] = B.ang[j]
	B.set_state(keep)
	return kept


## the poses an agent can name: poses/*.json and poses/lib/*.json (scene files skipped, as the pose library does)
static func list_poses() -> Array:
	var out := []
	for dir in DIRS:
		var files := Array(DirAccess.get_files_at(dir))
		files.sort()
		for f: String in files:
			if not f.ends_with(".json"):
				continue
			var p: String = dir + "/" + f
			var txt := FileAccess.get_file_as_string(p)
			if txt.contains("\"cards\"") or not txt.contains("\"joints\""):
				continue
			out.append({"name": (dir.trim_prefix("res://poses").trim_prefix("/") + "/" if dir != "res://poses" else "") + f.get_basename(), "path": p})
	return out


static func _pose_file(t: String) -> String:
	for c in [t, t + ".json", "res://poses/" + t, "res://poses/" + t + ".json", "res://poses/lib/" + t + ".json"]:
		var p: String = c if c.begins_with("res://") or c.begins_with("user://") or c.is_absolute_path() else "res://" + c
		if c.ends_with(".json") or c.begins_with("res://poses/"):
			if FileAccess.file_exists(p):
				return p
	return ""


static func _from_file(B: Body, path: String, how: String) -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary) or not (d.get("joints") is Dictionary):
		return {"ok": false, "error": "%s is not a pose file (no \"joints\")" % path}
	var ang := {}
	for j in Body.ORDER:
		ang[j] = Vector3.ZERO
	for j in d["joints"]:
		if not B.lim.has(j):
			continue
		var x: Dictionary = d["joints"][j]
		ang[j] = Vector3(float(x.get("bend", 0.0)), float(x.get("side", 0.0)), float(x.get("twist", 0.0)))
	var o: Array = d.get("offset", [0, 0, 0])
	return {"ok": true, "ang": ang, "off": Vector3(float(o[0]), float(o[1]), float(o[2])), "from": how, "name": path.get_file().get_basename(),
		"file": path, "weapon": not (d.get("weapon", {}) as Dictionary).is_empty()}


## the first joint axis past its range (by more than LIMIT_TOL): {joint, axis, asked, range, why} or {}
static func past_limit(B: Body, ang: Dictionary) -> Dictionary:
	for j in Body.ORDER:
		var v: Vector3 = ang[j]
		for k in 3:
			var ax: String = ["bend", "side", "twist"][k]
			var r: Vector2 = B.lim[j][ax]
			if v[k] < r.x - LIMIT_TOL or v[k] > r.y + LIMIT_TOL:
				var say: String = String(B.lim[j].get("say", {}).get(ax, ""))
				return {"joint": j, "axis": ax, "asked": snappedf(v[k], 0.01), "range": [r.x, r.y],
					"why": "%s %s %.1f deg is outside its range %.0f..%.0f deg%s: no body gets there, so no path does" % [j, ax, v[k], r.x, r.y,
						(" (%s)" % say) if say != "" else ""]}
	return {}


# ------------------------------------------------------------------ measures on the body as it is

## the deepest self-contact (m) and its pair
static func _pen(B: Body) -> Array:
	var deep := 0.0
	var pair := ""
	for c in B.contacts():
		if float(c[2]) > deep:
			deep = float(c[2])
			pair = "%s/%s" % [c[0], c[1]]
	return [deep, pair]


## how far the lowest part is UNDER the floor (m, + = under) and which: the sole points (Body.foot_sole_low) and every
## other capsule (Body.floor_shift's), fingers aside
static func _sink(B: Body) -> Array:
	var worst := 0.0
	var part := ""
	for j in Body.BODY:
		if (j as String).begins_with("foot") or (j as String).begins_with("ball"):
			continue
		var r: float = float(B.rad.get(j, 0.03))
		var low := minf((B.P[j] as Vector3).y, (B.E[j] as Vector3).y) - r
		if -low > worst:
			worst = -low
			part = j
	for sd in ["_l", "_r"]:
		var s := B.foot_sole_low(sd)
		if -s > worst:
			worst = -s
			part = "foot" + sd
	return [worst, part]


static func _past(B: Body) -> Array:
	var worst := 0.0
	var at := ""
	for j in Body.ORDER:
		var v: Vector3 = B.ang[j]
		for k in 3:
			var r: Vector2 = B.lim[j][["bend", "side", "twist"][k]]
			var p := maxf(r.x - v[k], v[k] - r.y)
			if p > worst:
				worst = p
				at = "%s %s" % [j, ["bend", "side", "twist"][k]]
	return [worst, at]


static func _feet_ref(B: Body) -> Dictionary:
	var out := {}
	for sd in ["_l", "_r"]:
		var fs := B.foot_state(sd)
		out[sd] = {"ankle": B.P["foot" + sd], "ball": B.P["ball" + sd], "head": float(fs[1]), "flat": bool(fs[3]), "g": B.G["foot" + sd],
			"on": B.foot_sole_low(sd) < FLOOR_ON}
	return out


# ------------------------------------------------------------------ one move: a path between two keyframes

## the body on the path at fraction f: the angles straight between, then the root from the anchor foot, then the other
## planted foot put back by leg IK. The ends are the keyframes themselves
static func _path(B: Body, ctx: Dictionary, a: Dictionary, b: Dictionary, f: float) -> Dictionary:
	if f <= 0.0:
		return a
	if f >= 1.0:
		return b
	_put(B, _lerp(a, b, f))
	_hold(B, ctx)
	return _snap(B)


static func _hold(B: Body, ctx: Dictionary) -> void:
	var an: String = ctx["anchor"]
	if an == "":
		return
	var ref: Dictionary = ctx["ref"][an]
	for it in 3:
		B.offset += (ref["ankle"] as Vector3) - (B.P["foot" + an] as Vector3)
		B.fk()
		if ((B.P["ball" + an] as Vector3) - (ref["ball"] as Vector3)).length() < 0.001:
			break
		B.plant(an, ref["ball"], ref["head"], ref["flat"])   # the anchor's toe base turned off its mark: the leg puts it back
	B.offset += (ref["ankle"] as Vector3) - (B.P["foot" + an] as Vector3)
	B.fk()
	if ctx["both"]:
		var o := _other(an)
		var ro: Dictionary = ctx["ref"][o]
		B.plant(o, ro["ball"], ro["head"], ro["flat"])


## the worst of the straight line from state a to b, sampled every RES_DEG: {"slide", "slide_at", "pen", "pair", "sink",
## "part", "past", "past_at", "n"}. Planted feet are measured from where they were at the start of the move
static func _line(B: Body, ctx: Dictionary, a: Dictionary, b: Dictionary) -> Dictionary:
	var n := maxi(1, int(ceil(_delta(a, b) / RES_DEG)))
	var w := {"slide": 0.0, "slide_at": "", "pen": 0.0, "pair": "", "sink": 0.0, "part": "", "past": 0.0, "past_at": "", "n": n}
	for i in range(1, n + 1):
		_put(B, _lerp(a, b, float(i) / n))
		_worse(B, ctx, w)
	return w


static func _worse(B: Body, ctx: Dictionary, w: Dictionary) -> void:
	for sd in ctx["planted"]:
		var ref: Dictionary = ctx["ref"][sd]
		var s := maxf(((B.P["foot" + sd] as Vector3) - (ref["ankle"] as Vector3)).length(), ((B.P["ball" + sd] as Vector3) - (ref["ball"] as Vector3)).length())
		if s > w["slide"]:
			w["slide"] = s
			w["slide_at"] = _side(sd) + " foot"
	var p := _pen(B)
	if p[0] > w["pen"]:
		w["pen"] = p[0]
		w["pair"] = p[1]
	var k := _sink(B)
	if k[0] > w["sink"]:
		w["sink"] = k[0]
		w["part"] = k[1]
	var x := _past(B)
	if x[0] > w["past"]:
		w["past"] = x[0]
		w["past_at"] = x[1]


static func _bad(ctx: Dictionary, w: Dictionary, slide_bar: float) -> String:
	if w["past"] > 0.01:
		return "past"
	if w["slide"] > slide_bar:
		return "slide"
	if w["pen"] > maxf(PEN_BAR, ctx["pen_ends"] + 0.001):
		return "pen"
	if w["sink"] > maxf(SINK_BAR, ctx["sink_ends"] + 0.001):
		return "sink"
	return ""


## cut the move a -> b until every straight piece passes: the waypoints after a, and the worst piece left (if any)
static func _dense(B: Body, ctx: Dictionary, a: Dictionary, b: Dictionary, fa: float, wa: Dictionary, fb: float, wb: Dictionary, depth: int,
		out: Array, left: Array) -> void:
	var w := _line(B, ctx, wa, wb)
	var why := _bad(ctx, w, PLAN_SLIDE)
	if why == "" or depth >= MAX_DEPTH or _delta(wa, wb) <= RES_DEG:
		if why != "":
			w["kind"] = why
			left.append(w)
		out.append(wb)
		return
	var fm := (fa + fb) * 0.5
	var wm := _round(_path(B, ctx, a, b, fm))
	_dense(B, ctx, a, b, fa, wa, fm, wm, depth + 1, out, left)
	_dense(B, ctx, a, b, fm, wm, fb, wb, depth + 1, out, left)


## the path itself (not the waypoints' lines) sampled every RES_DEG: the first fraction where it passes the body through
## itself or a part through the floor. {} = none
static func _probe(B: Body, ctx: Dictionary, a: Dictionary, b: Dictionary) -> Dictionary:
	var n := maxi(1, int(ceil(_delta(a, b) / RES_DEG)))
	for i in range(1, n):
		var f := float(i) / n
		_path(B, ctx, a, b, f)
		var p := _pen(B)
		if p[0] > maxf(PEN_BAR, ctx["pen_ends"] + 0.001):
			return {"kind": "pen", "f": f, "depth": p[0], "what": p[1]}
		var k := _sink(B)
		if k[0] > maxf(SINK_BAR, ctx["sink_ends"] + 0.001):
			return {"kind": "sink", "f": f, "depth": k[0], "what": k[1]}
	return {}


static func _group_of(j: String) -> int:
	for g in GROUPS.size():
		if j in GROUPS[g][1]:
			return g
	return GROUPS.size() - 1   # the fingers


## the keyframes of a staged move: the groups in `order` arrive at b one after another (root with the hips)
static func _stages(B: Body, ctx: Dictionary, a: Dictionary, b: Dictionary, order: Array) -> Array:
	var ks := [a]
	var cur: Dictionary = a.duplicate(true)
	for gi in order:
		var nxt: Dictionary = cur.duplicate(true)
		for j in nxt["ang"]:
			if _group_of(j) == gi:
				nxt["ang"][j] = b["ang"][j]
		if gi == 0:
			nxt["off"] = b["off"]
		if gi == order[-1]:
			nxt = b
		else:
			_put(B, nxt)
			_hold(B, ctx)
			nxt = _round(_snap(B))
		ks.append(nxt)
		cur = nxt
	return ks


static func _pct(f: float) -> String:
	return "%d %%" % roundi(f * 100.0)


static func _what(s: String) -> String:
	return s.replace("skin:", "").replace("/", " into the ").replace("_l", " (left)").replace("_r", " (right)").replace("_", " ")


## one move a -> b: [{"say", "ways": [...]}...] parts, or {"blocked"}. Straight first; staged orders or a lifted swing foot
## when the straight path passes the body through itself or the floor
static func _move(B: Body, ctx: Dictionary, a: Dictionary, b: Dictionary, say: String) -> Dictionary:
	var hit := _probe(B, ctx, a, b)
	var tries := []   # [why, [keyframes], [says]]
	if hit.is_empty():
		tries.append(["", [a, b], [say]])
	else:
		var where := "straight there %s goes %.1f cm %s at %s of the way" % [_what(hit["what"]) if hit["kind"] == "pen" else "the " + _what(hit["what"]),
			hit["depth"] * 100.0, "deep" if hit["kind"] == "pen" else "into the floor", _pct(hit["f"])]
		if hit["kind"] == "sink" and ctx["swing"] != "":
			var sw: String = ctx["swing"]
			var mid := _path(B, ctx, a, b, hit["f"])
			_put(B, mid)
			B.reach("foot" + sw, (B.P["foot" + sw] as Vector3) + Vector3(0, hit["depth"] + LIFT, 0))
			var via := _round(_snap(B))
			tries.append([where, [a, via, b], ["keep the %s foot up on the way: %s" % [_side(sw), where], say]])
		var names := GROUPS.map(func(g): return g[0])
		for order in [[0, 1, 2, 3], [3, 2, 1, 0]]:
			var ks := _stages(B, ctx, a, b, order)
			var says := []
			for k in order.size():
				says.append("%s%s: %s" % ["first " if k == 0 else ("then " if k < order.size() - 1 else "last "), names[order[k]],
					("not all at once: " + where) if k == 0 else say])
			tries.append([where, ks, says])
	var last := {}
	for t in tries:
		var ks: Array = t[1]
		var parts := []
		var ok := true
		for k in range(1, ks.size()):
			var h := _probe(B, ctx, ks[k - 1], ks[k]) if not (t[0] == "" and k == 1) else {}
			if not h.is_empty():
				ok = false
				last = h
				break
			var ways := []
			var left := []
			_dense(B, ctx, ks[k - 1], ks[k], 0.0, ks[k - 1], 1.0, ks[k], 0, ways, left)
			if not left.is_empty():
				ok = false
				last = left[0]
				break
			parts.append({"say": t[2][k - 1], "ways": ways})
		if ok:
			return {"parts": parts}
	if last.has("f"):
		return {"blocked": {"why": "no order of the joints avoids it: %s goes %.1f cm %s at %s of the way" % [_what(last["what"]), last["depth"] * 100.0,
			"deep" if last["kind"] == "pen" else "into the floor", _pct(last["f"])], "kind": last["kind"]}}
	var k2: String = last.get("kind", "")
	var msg := {"slide": "the %s slides %.1f cm" % [last.get("slide_at", ""), last.get("slide", 0.0) * 100.0],
		"pen": "%s goes %.1f cm deep" % [_what(last.get("pair", "")), last.get("pen", 0.0) * 100.0],
		"sink": "the %s goes %.1f cm into the floor" % [_what(last.get("part", "")), last.get("sink", 0.0) * 100.0],
		"past": "%s passes its limit by %.1f deg" % [last.get("past_at", ""), last.get("past", 0.0)]}
	return {"blocked": {"why": "no waypoints keep it: " + String(msg.get(k2, "?")), "kind": k2}}


# ------------------------------------------------------------------ the plan

## plan from the body as it is to `target`; the body is put back. {"ok", "target", "feet", "steps", "checks", "blocked"?, ...}
static func plan(B: Body, target: String, max_steps := MAX_STEPS) -> Dictionary:
	var keep := B.state()
	var r := _plan(B, target, max_steps)
	B.set_state(keep)
	return r


static func _plan(B: Body, target: String, max_steps: int) -> Dictionary:
	var tg := resolve(B, target)
	if not tg["ok"]:
		return {"ok": false, "error": tg["error"]}
	var head := {"ok": true, "target": {"asked": target, "from": tg["from"]}, "steps": [], "checks": []}
	if tg.has("name"):
		head["target"]["pose"] = tg["name"]
	if tg.has("search"):
		head["target"]["search"] = tg["search"]
	if tg.has("feet_kept"):
		head["target"]["feet_kept"] = tg["feet_kept"]
		head["target"]["note"] = "the words name no leg, so the feet stay where they are: the legs follow (Body.plant)"
	if tg.get("weapon", false) or B.wep_on:
		head["note"] = "the weapon is not planned: it stays in the hand as it is"
	var lim := past_limit(B, tg["ang"])
	if not lim.is_empty():
		head["blocked"] = lim
		return head
	var s0 := _round(_snap(B))
	_put(B, s0)
	var start_ref := _feet_ref(B)
	var grounded := absf(B.floor_shift()) < FLOOR_ON
	# the target as the body would stand it: on the floor (when the body is now), its root then moved by the anchor
	var t0 := {"ang": tg["ang"], "off": tg["off"]}
	_put(B, t0)
	if grounded:
		t0["off"] = (t0["off"] as Vector3) - Vector3(0, B.floor_shift(), 0)
		_put(B, t0)
	var tp := _pen(B)
	if tp[0] > PEN_BAR:
		head["blocked"] = {"why": "the target itself puts %s %.1f cm deep (bar %.0f cm, feasible.gd): no path ends there" % [_what(tp[1]), tp[0] * 100.0, PEN_BAR * 100.0], "kind": "pen"}
		return head
	var tref := _feet_ref(B)
	var cands := []   # [side, its target root, keeps its toes?, flat in target, distance to the target COM]
	for sd in ["_l", "_r"]:
		if not (start_ref[sd]["on"] and tref[sd]["on"]):
			continue
		var off: Vector3 = (t0["off"] as Vector3) + (start_ref[sd]["ankle"] as Vector3) - (tref[sd]["ankle"] as Vector3)
		_put(B, {"ang": t0["ang"], "off": off})
		var turn := ((B.P["ball" + sd] as Vector3) - (start_ref[sd]["ball"] as Vector3)).length()
		var c := Balance.com(B)
		var dc := Vector2(c.x - (B.P["foot" + sd] as Vector3).x, c.z - (B.P["foot" + sd] as Vector3).z).length()
		cands.append({"sd": sd, "off": off, "turn": turn, "flat": tref[sd]["flat"], "com": dc})
	var keepers := cands.filter(func(c): return c["turn"] < SLIDE_BAR)
	keepers.sort_custom(func(x, y): return (x["flat"] and not y["flat"]) or (x["flat"] == y["flat"] and x["com"] < y["com"]))
	var moves := []   # [ctx, from, to, say]
	var feet := {}
	if not keepers.is_empty():
		var an: String = keepers[0]["sd"]
		var tgt := _round({"ang": t0["ang"], "off": keepers[0]["off"]})
		_put(B, tgt)
		var o := _other(an)
		var o_still: bool = start_ref[o]["on"] and B.foot_sole_low(o) < FLOOR_ON and ((B.P["foot" + o] as Vector3) - (start_ref[o]["ankle"] as Vector3)).length() < SLIDE_BAR \
			and ((B.P["ball" + o] as Vector3) - (start_ref[o]["ball"] as Vector3)).length() < SLIDE_BAR
		feet = {"anchor": _side(an), "planted": [_side(an)] + ([_side(o)] if o_still else []), "swing": "" if o_still else _side(o)}
		moves.append([_ctx(start_ref, an, o_still, "" if o_still else o), s0, tgt, "to the target, the %s planted" % ("feet" if o_still else _side(an) + " foot")])
	elif cands.size() == 2:
		# both feet change on the floor (each turns if the other anchors): two moves, a step each. The target is placed by
		# foot X (its ankle stays); first X holds as it is now (its leg turns it back: Body.plant) while the other foot steps
		# to its place, then X is lifted and set down as the target has it, the other foot holding. Left first, else right
		var done := false
		for tr in 4:
			var c: Dictionary = cands[tr % 2]
			var x: String = c["sd"]
			var y := _other(x)
			# the in-between: the body as now with y's leg putting its foot where the target has it (tries 0-1), else the
			# target with x's leg holding x as it is now (tries 2-3, a long step a leg alone cannot reach)
			var mid := _mid_reach(B, s0, t0, c["off"], x, start_ref) if tr < 2 else _mid_step(B, t0, start_ref, c["off"], x)
			if mid.is_empty():
				continue
			_put(B, mid)
			var mid_ref := _feet_ref(B)
			feet = {"anchor": "%s, then %s" % [_side(x), _side(y)], "planted": [], "swing": "%s, then %s" % [_side(y), _side(x)], "two_steps": true}
			moves.append([_ctx(start_ref, x, false, y), s0, mid, "the %s foot steps to its place, the %s foot planted" % [_side(y), _side(x)]])
			# the target placed by y's ankle as the first step left it (the leg puts the toe base exactly; the ankle within 1 cm)
			_put(B, {"ang": t0["ang"], "off": c["off"]})
			var off2: Vector3 = (c["off"] as Vector3) + (mid_ref[y]["ankle"] as Vector3) - (B.P["foot" + y] as Vector3)
			moves.append([_ctx(mid_ref, y, false, x), mid, _round({"ang": t0["ang"], "off": off2}), "the %s foot turns to its place, the %s foot planted" % [_side(x), _side(y)]])
			done = true
			break
		if not done:
			head["blocked"] = {"why": "both feet change on the floor and neither leg can hold its foot as it is while the other steps", "kind": "feet"}
			return head
	elif not cands.is_empty():
		var c0: Dictionary = cands[0]
		head["blocked"] = {"why": "the %s foot is the only one on the floor in both, and the target turns it on the floor (its toes move %.0f cm when its ankle stays): a planted foot cannot turn; lift it, or put the other foot down in the target" % [
			_side(c0["sd"]), c0["turn"] * 100.0], "kind": "feet"}
		return head
	elif start_ref["_l"]["on"] or start_ref["_r"]["on"]:
		head["blocked"] = {"why": "no foot is on the floor both now and in the target (a jump, a fall, lying down): there is no planted path to it", "kind": "feet"}
		return head
	else:
		var tgt := _round(t0)
		feet = {"anchor": "", "planted": [], "swing": ""}
		var ctx := _ctx(start_ref, "", false, "")
		ctx["planted"] = []
		moves.append([ctx, s0, tgt, "to the target (no foot stays on the floor)"])
	head["feet"] = feet
	# each move: the swing foot lifted first and set down last, then the parts
	var parts := []
	for mv in moves:
		var ctx: Dictionary = mv[0]
		var a: Dictionary = mv[1]
		var b: Dictionary = mv[2]
		_put(B, a)
		var pa := _pen(B)
		var ka := _sink(B)
		_put(B, b)
		ctx["pen_ends"] = maxf(pa[0], _pen(B)[0])
		ctx["sink_ends"] = maxf(ka[0], _sink(B)[0])
		var ks := [[a, ""]]
		var sw: String = ctx["swing"]
		if sw != "":
			_put(B, a)
			var a_on := B.foot_sole_low(sw) < FLOOR_ON
			var a_ank: Vector3 = B.P["foot" + sw]
			_put(B, b)
			var b_on := B.foot_sole_low(sw) < FLOOR_ON
			var b_ank: Vector3 = B.P["foot" + sw]
			var travel := (b_ank - a_ank).length()
			if a_on:
				_lift(B, a, sw, a_ank)
				ks.append([_round(_snap(B)), ("lift the %s foot %.0f cm first: it is on the floor and goes %.0f cm (moved straight it would slide on the floor before it rises)" % [
					_side(sw), LIFT * 100.0, travel * 100.0]) if travel >= SLIDE_BAR else ("lift the %s foot %.0f cm first: it turns on the floor where it stands (a planted foot cannot turn)" % [_side(sw), LIFT * 100.0])])
			if b_on:
				_lift(B, b, sw, b_ank)
				ks.append([_round(_snap(B)), mv[3] + ", the %s foot held %.0f cm above its mark" % [_side(sw), LIFT * 100.0]])
				ks.append([b, "set the %s foot down last, straight onto its mark (it lands without sliding)" % _side(sw)])
			else:
				ks.append([b, mv[3]])
		else:
			ks.append([b, mv[3]])
		for k in range(1, ks.size()):
			var r := _move(B, ctx, ks[k - 1][0], ks[k][0], ks[k][1])
			if r.has("blocked"):
				head["blocked"] = r["blocked"]
				return head
			parts.append_array(r["parts"])
	# the steps: one per waypoint, the joints that change (parents first) and the root
	var steps := []
	var prev := s0
	for pt in parts:
		var ways: Array = pt["ways"]
		for i in ways.size():
			var w: Dictionary = ways[i]
			var run := []
			for j in Body.ORDER:
				var v: Vector3 = w["ang"][j]
				if not v.is_equal_approx(prev["ang"][j]):
					run.append("%s=%s:%.4f,%.4f,%.4f" % ["set" if j in Body.BODY else "put", j, v.x, v.y, v.z])   # set= takes no finger
			var o: Vector3 = w["off"]
			if not o.is_equal_approx(prev["off"]):
				run.append("root=%.5f,%.5f,%.5f" % [o.x, o.y, o.z])
			prev = w
			if run.is_empty():
				continue
			steps.append({"n": steps.size() + 1, "say": pt["say"] + ("" if ways.size() == 1 else " (%d/%d)" % [i + 1, ways.size()]), "run": run, "_want": w})
	if steps.size() > max_steps:
		head["blocked"] = {"why": "the path needs %d steps; max_steps is %d (ask again with a larger max_steps)" % [steps.size(), max_steps], "kind": "steps", "needs": steps.size()}
		return head
	# THE PROOF: replay as `run` would, re-order a step whose joint a contact stops, then measure the replayed states
	_put(B, s0)
	var states := [s0]
	for st in steps:
		var at := _snap(B)
		var stopped := _run_tokens(B, st["run"])
		if not stopped.is_empty():
			# a contact stopped a joint: first the same step with that joint last (the others may move out of its way) ...
			var re: Array = (st["run"] as Array).filter(func(x): return not x in stopped) + stopped
			_put(B, at)
			var again := _run_tokens(B, re)
			var why := "moves last: it touches"
			if not again.is_empty():
				# ... else the touch is the pose's own (the target's hand on the head): put= sets it without set's contact
				# stop. Allowed only because every sampled state is held to feasible.gd's 2 cm (the audit below)
				re = re.map(func(x): return "put=" + x.substr(4) if x in again else x)
				_put(B, at)
				_run_tokens(B, re)
				why = "put=, not set=: the pose touches there (set stops at the first touch; checked under %.0f cm)" % (PEN_BAR * 100.0)
				stopped = again
			st["run"] = re
			st["say"] += " (%s %s)" % [", ".join(stopped.map(func(x): return x.get_slice(":", 0).get_slice("=", 1))), why]
		states.append(_snap(B))
	for st in steps:
		st.erase("_want")
	head["steps"] = steps
	head["checks"] = audit(B, states, start_ref, feet, tg["ang"])
	var failed: Array = (head["checks"] as Array).filter(func(c): return not c["ok"])
	if not failed.is_empty():   # never hand out a path that fails its own bars
		head["blocked"] = {"why": "the replayed path fails: " + ", ".join(failed.map(func(c): return "%s %s" % [c["check"], JSON.stringify(c)])), "kind": "check"}
	var flat := []
	for st in steps:
		flat.append_array(st["run"])
	head["run"] = {"method": "run", "params": {"steps": flat}}
	return head


## the keyframe st with foot sd's ankle LIFT higher (leg IK, Body.reach) and the foot turned back to how it lay in st
## (Body.turn_world): the sole goes up level, the toes do not dip into the floor (a bare reach bends the knee and the
## toe tip sank 1.1 cm at 20 % of the lift, measured on stand -> kick chamber)
static func _lift(B: Body, st: Dictionary, sd: String, ank: Vector3) -> void:
	_put(B, st)
	var g0: Quaternion = B.G["foot" + sd]
	for it in 2:
		B.reach("foot" + sd, ank + Vector3(0, LIFT, 0))
		B.turn_world("foot" + sd, g0 * (B.G["foot" + sd] as Quaternion).inverse())


static func _ctx(ref: Dictionary, anchor: String, both: bool, swing: String) -> Dictionary:
	var planted := []
	if anchor != "":
		planted.append(anchor)
		if both:
			planted.append(_other(anchor))
	return {"ref": ref, "anchor": anchor, "both": both, "swing": swing, "planted": planted, "pen_ends": 0.0, "sink_ends": 0.0}


## the in-between pose of a two-step move, first try: the body as it is now with its root at the target's height and half
## way to the target's place (a straight leg from the hips as they stand cannot reach the floor 20 cm out: 5 mm short,
## measured on stand -> guard_bat), foot x held
## where and how it lies now, foot y put where and how the target (placed by root off) has it; the legs alone do it
## (Body.reach + turn_world). {} when a leg cannot
static func _mid_reach(B: Body, s0: Dictionary, t0: Dictionary, off: Vector3, x: String, ref: Dictionary) -> Dictionary:
	_put(B, {"ang": t0["ang"], "off": off})
	var tr := _feet_ref(B)
	var st: Dictionary = s0.duplicate(true)
	var o0: Vector3 = s0["off"]
	st["off"] = Vector3(lerpf(o0.x, off.x, 0.5), off.y, lerpf(o0.z, off.z, 0.5))   # the hips half way: over both feet
	_put(B, st)
	var y := _other(x)
	for it in 3:
		for f in [[x, ref[x]], [y, tr[y]]]:
			B.reach("foot" + f[0], f[1]["ankle"])
			B.turn_world("foot" + f[0], (f[1]["g"] as Quaternion) * (B.G["foot" + f[0]] as Quaternion).inverse())
	for f in [[x, ref[x]], [y, tr[y]]]:
		if ((B.P["foot" + f[0]] as Vector3) - (f[1]["ankle"] as Vector3)).length() > 0.002 or ((B.P["ball" + f[0]] as Vector3) - (f[1]["ball"] as Vector3)).length() > 0.002:
			return {}
	return _round(_snap(B))


## the in-between pose of a two-step move: the target's angles placed by foot x (its ankle where it is now), x's leg
## turning that foot back to how it lies now (Body.plant). {} when the leg cannot
static func _mid_step(B: Body, t0: Dictionary, ref: Dictionary, off: Vector3, x: String) -> Dictionary:
	_put(B, {"ang": t0["ang"], "off": off})
	B.plant(x, ref[x]["ball"], ref[x]["head"], ref[x]["flat"])
	B.turn_world("foot" + x, (ref[x]["g"] as Quaternion) * (B.G["foot" + x] as Quaternion).inverse())   # the sole as it lies now (roll too)
	B.offset += (ref[x]["ankle"] as Vector3) - (B.P["foot" + x] as Vector3)
	B.fk()
	if ((B.P["ball" + x] as Vector3) - (ref[x]["ball"] as Vector3)).length() > PLAN_SLIDE * 0.5:
		return {}
	return _round(_snap(B))


## run steps on the body as AgentTools.step does (set= through set_ang_safe, root= the offset, then the grip as
## main._after_edit): the tokens a contact stopped
static func _run_tokens(B: Body, toks: Array) -> Array:
	var stopped := []
	for t: String in toks:
		if t.begins_with("set="):
			var p := t.substr(4).split(":")
			var v := p[1].split(",")
			if not B.set_ang_safe(p[0], Vector3(float(v[0]), float(v[1]), float(v[2]))):
				stopped.append(t)
		elif t.begins_with("put="):
			var p := t.substr(4).split(":")
			var v := p[1].split(",")
			B.set_ang(p[0], Vector3(float(v[0]), float(v[1]), float(v[2])))
		elif t.begins_with("root="):
			var v := t.substr(5).split(",")
			B.offset = Vector3(float(v[0]), float(v[1]), float(v[2]))
			B.fk()
		if B.wep_on and B.grip:
			B.apply_grip()
	return stopped


## the checks, measured on replayed states: every straight line between two of them sampled every RES_DEG
static func audit(B: Body, states: Array, ref: Dictionary, feet: Dictionary, want: Dictionary) -> Array:
	var ctx := {"ref": ref, "planted": []}
	for sd in ["_l", "_r"]:
		if _side(sd) in feet.get("planted", []):
			ctx["planted"].append(sd)
	var w := {"slide": 0.0, "slide_at": "", "pen": 0.0, "pair": "", "sink": 0.0, "part": "", "past": 0.0, "past_at": "", "n": 0}
	var drag := {"_l": 0.0, "_r": 0.0}
	var run0 := {}   # foot -> where its on-floor run began
	for i in states.size():
		var n := 1 if i == 0 else maxi(1, int(ceil(_delta(states[i - 1], states[i]) / RES_DEG)))
		for k in (range(1, n + 1) if i > 0 else [0]):
			_put(B, states[i] if i == 0 else _lerp(states[i - 1], states[i], float(k) / n))
			_worse(B, ctx, w)
			w["n"] += 1
			for sd in ["_l", "_r"]:
				if B.foot_sole_low(sd) < FLOOR_ON:
					if not run0.has(sd):
						run0[sd] = [B.P["foot" + sd], B.P["ball" + sd]]
					for q in 2:
						var d: Vector3 = (B.P[["foot", "ball"][q] + sd] as Vector3) - (run0[sd][q] as Vector3)
						drag[sd] = maxf(drag[sd], Vector2(d.x, d.z).length())
				else:
					run0.erase(sd)
	var miss := 0.0
	var miss_at := ""
	var last: Dictionary = states[-1]["ang"]
	for j in Body.ORDER:
		var v: Vector3 = (last[j] as Vector3) - (want[j] as Vector3)
		var e := maxf(absf(v.x), maxf(absf(v.y), absf(v.z)))
		if e > miss:
			miss = e
			miss_at = j
	var dr := maxf(drag["_l"], drag["_r"])
	return [
		{"check": "target reached", "ok": miss <= 1.0, "worst_deg": snappedf(miss, 0.001), "joint": miss_at, "bar_deg": 1.0},
		{"check": "joint limits", "ok": w["past"] <= 0.01, "worst_past_deg": snappedf(w["past"], 0.001), "at": w["past_at"], "samples": w["n"], "every_deg": RES_DEG},
		{"check": "planted feet", "ok": w["slide"] <= SLIDE_BAR, "feet": feet.get("planted", []), "worst_cm": snappedf(w["slide"] * 100.0, 0.01), "bar_cm": SLIDE_BAR * 100.0},
		{"check": "no foot dragged on the floor", "ok": dr <= SLIDE_BAR, "worst_cm": snappedf(dr * 100.0, 0.01), "foot": "left" if drag["_l"] >= drag["_r"] else "right", "bar_cm": SLIDE_BAR * 100.0},
		{"check": "self-intersection", "ok": w["pen"] <= PEN_BAR, "worst_cm": snappedf(w["pen"] * 100.0, 0.01), "pair": w["pair"], "bar_cm": PEN_BAR * 100.0, "source": "feasible.gd PEN_FIX"},
		{"check": "floor", "ok": w["sink"] <= SINK_BAR, "worst_under_cm": snappedf(w["sink"] * 100.0, 0.01), "part": w["part"], "bar_cm": SINK_BAR * 100.0}]


# ------------------------------------------------------------------ serve / CLI

## the two run steps path_to_pose adds (AgentTools.step), each one undo step; "" or what to type:
##   root=x,y,z          the body's root (the pelvis offset, m)
##   put=<joint>:b,s,t   a joint's angles inside its limits WITHOUT set='s contact stop (a finger, which set= does not
##                       take, or a pose that touches itself; path_to_pose has checked the path under 2 cm)
static func step_token(m: Node, tok: String) -> String:
	if tok.begins_with("root="):
		var v := tok.substr(5).split(",")
		if v.size() != 3 or not (v[0].is_valid_float() and v[1].is_valid_float() and v[2].is_valid_float()):
			return "root=x,y,z  the body's root (pelvis offset) in metres, e.g. root=0,-0.35,0.1"
		m._do(func():
			m.B.offset = Vector3(float(v[0]), float(v[1]), float(v[2]))
			m.B.fk())
		return ""
	var p := tok.substr(4).split(":")
	var a: PackedStringArray = p[1].split(",") if p.size() == 2 else PackedStringArray()
	if p.size() != 2 or a.size() != 3 or not p[0] in Body.ORDER or not (a[0].is_valid_float() and a[1].is_valid_float() and a[2].is_valid_float()):
		return "put=<joint>:bend,side,twist  e.g. put=index_01_r:40,0,0 (any joint, fingers too; limits apply, contacts do not stop it)"
	m.sel = p[0]
	m._do(func(): m.B.set_ang(p[0], Vector3(float(a[0]), float(a[1]), float(a[2]))))
	return ""


## serve `path_to_pose {target, max_steps?, apply?}`
static func serve(T, id: Variant, p: Dictionary) -> Dictionary:
	var mx := int(p.get("max_steps", MAX_STEPS))
	if mx < 1:
		return T._err(id, -32602, "max_steps must be 1 or more")
	var r := plan(T.m.B, String(p.get("target", "")), mx)
	if not r["ok"]:
		return T._err(id, -32602, r["error"], {"poses": list_poses().map(func(e): return e["name"])})
	if T.m.scene_path != "":
		r["cli"] = "run %s %s" % [ProjectSettings.localize_path(T.m.scene_path), " ".join(r.get("run", {}).get("params", {}).get("steps", []))]
	r["applied"] = false
	if bool(p.get("apply", false)) and not r.has("blocked"):
		for st in r["steps"]:
			for tok in st["run"]:
				var s: Dictionary = await T.step(tok)
				if not s["ok"]:
					return T._err(id, -32000, "apply: step %d (%s) failed: %s" % [st["n"], tok, s.get("error", "")], r)
		r["applied"] = true
	return T._ok(id, r)


## readable lines for the CLI
static func lines(r: Dictionary) -> Array:
	var out := []
	if not r.get("ok", false):
		return [String(r.get("error", ""))]
	var tg: Dictionary = r["target"]
	out.append("PATH TO %s (%s)%s" % [tg.get("pose", tg["asked"]), tg["from"], ("   matched '%s' by %s" % [tg["search"]["pose"], ", ".join(tg["search"]["tags"]) if not tg["search"]["tags"].is_empty() else "its name"]) if tg.has("search") else ""])
	if r.has("blocked"):
		out.append("BLOCKED: " + String(r["blocked"]["why"]))
		return out
	var f: Dictionary = r.get("feet", {})
	out.append("feet: planted %s, swing %s" % [", ".join(f.get("planted", [])) if not f.get("planted", []).is_empty() else "none", f.get("swing", "") if f.get("swing", "") != "" else "none"])
	for st in r["steps"]:
		out.append("%3d  %s   [%d joints%s]" % [st["n"], st["say"], (st["run"] as Array).filter(func(x): return x.begins_with("set=")).size(),
			", root" if (st["run"] as Array).any(func(x): return x.begins_with("root=")) else ""])
	for c in r["checks"]:
		var d: Dictionary = c.duplicate()
		d.erase("check")
		d.erase("ok")
		out.append("%-4s %-30s %s" % ["ok" if c["ok"] else "FAIL", c["check"], JSON.stringify(d)])
	return out
