## parkour.gd - CH7: an 8 s chained parkour run on a built course (Nick 11-03: Vector, mocap'd traceurs in silhouette;
## "we are able to make the same kind of animation"). This file is the ENGINE: it turns a PLAN (parkour_plan.gd: the
## course, the pelvis's keyed path, the four limbs' keyed targets with their contacts) into a Scene of one card per frame.
##
## Nothing here is a new solver. Per frame the body is posed with Kine's own tools, in this order:
##   1 the pelvis: Body.ang["pelvis"] (pitch = forward, roll = to his left) and Body.offset from the pelvis's keyed path
##     (PartKeys.at, the monotone cubic the part keys use); the spine takes the keyed trunk bend, the neck keeps the head level
##   2 each leg: Body.plant (the toe base on its keyed target, the foot flat while it is in CONTACT, the ankle eased in and out
##     of flat over FOOT_BLEND so there is no pop); a stance foot that cannot reach lowers the pelvis (a runner runs low), never
##     moves the foot
##   3 each arm: LimbIK.solve on the keyed wrist target; in a hand CONTACT ContactIK.reach (palm flat on the obstacle's face,
##     the whole arm clear of it), eased in and out the same way
##   4 the SET: Props.depth of every body capsule against the course (Parts); a body part inside a solid lifts the pelvis
##     (never moves a contact)
## The course is made of Parts (one box record each, BuildStage.use), so the obstacle solids are the ones Kine's checks read.
## The scene is a plain Scene dictionary (cards at 1/FPS, moving_holds off, no floor grounding: the decks are at Y0 over the street).
##
## Units: metres, +y up, +z the way he runs, +x his left (the camera looks from -x: he runs left to right).
class_name Parkour
extends RefCounted

const FPS := 30
const Y0 := 3.0               # the roof's top over the street (m): the Kine floor (y = 0) is the street, far below
const BASE := "res://poses/stand.json"
const FOOT_BLEND := 0.07      # s the foot / hand takes to come into (and 0.05 s out of) a contact pose
const REACH_EPS := 0.003      # m a stance foot may miss before the pelvis is lowered
const SKIN := 0.01            # m of penetration the check tolerates (the brief's bar)
## capsule depth of a foot / toe base against the surface it STANDS on when flat (the capsules reach below the sole by design:
## measured on the standing pose, tests/ch7_test.gd): a depth beyond it is a real penetration
const STAND_DEPTH := {"foot_l": 0.064, "foot_r": 0.064, "ball_l": 0.0322, "ball_r": 0.0322}

static var _body: Body = null
static var _base: Dictionary = {}


static func body() -> Body:
	if _body == null:
		_body = Body.new()
		_body.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		_base = JSON.parse_string(FileAccess.get_file_as_string(BASE))
		# this Body only (the app's limits file is untouched): a vault plant needs the hand to lie flat under a forearm that is steep,
		# which a real wrist does with forearm pronation and 70+ deg of extension; the rig has no forearm twist bones, so the hand's
		# own side and bend ranges take it (docs/CH7_FEEDBACK.md)
		for sd in ["_l", "_r"]:
			var L: Dictionary = _body.lim["hand" + sd]
			L["bend"] = Vector2(-85.0, 70.0)
			L["side"] = Vector2(-45.0, 45.0)
	return _body


## one Part record for a box (mm in the record; lo/hi in m): the obstacle as Kine's own Part
static func part_rec(nm: String, lo: Vector3, hi: Vector3) -> Dictionary:
	return {"name": nm, "seq": 1, "version": 1, "features": [{"t": "prim", "id": "f1", "name": nm, "kind": "box", "op": "new",
		"x": lo.x * 1000.0, "y": lo.y * 1000.0, "z": lo.z * 1000.0, "w": (hi.x - lo.x) * 1000.0, "h": (hi.y - lo.y) * 1000.0, "d": (hi.z - lo.z) * 1000.0}]}


## put the plan's obstacles into the scene's set as Parts, each standing where its box is
static func add_course(S: Scene, obstacles: Array) -> void:
	for o in obstacles:
		var lo: Vector3 = o["lo"]
		var hi: Vector3 = o["hi"]
		var k := BuildStage.use(S, part_rec(String(o["name"]), lo, hi))
		if k == "":
			continue
		S.props[S.props.size() - 1]["xf"] = Transform3D(Basis(), Vector3((lo.x + hi.x) * 0.5, lo.y, (lo.z + hi.z) * 0.5))


# ------------------------------------------------------------------ keyed channels

## a key list in PartKeys' form from [[t, v], ...]
static func keys_of(rows: Array) -> Array:
	var out := []
	for r in rows:
		out.append({"t": float(r[0]), "v": Vector3(float(r[1]), 0, 0)})
	return out


static func ch(P: Dictionary, name: String, t: float) -> float:
	var k: Array = P["root"][name]
	if k.is_empty():
		return 0.0
	return PartKeys.at(k, t).x


static func root_at(P: Dictionary, t: float) -> Dictionary:
	return {"z": ch(P, "z", t), "y": ch(P, "y", t), "x": ch(P, "x", t), "p": ch(P, "p", t), "r": ch(P, "r", t), "s": ch(P, "s", t), "tw": ch(P, "tw", t)}


## a limb track's target at t and its contact state: {"v": Vector3, "w": 0..1 contact weight, "on": inside a contact, "i": the contact's index}
static func limb_at(keys: Array, t: float) -> Dictionary:
	var v: Vector3 = PartKeys.at(keys, t)
	var best := 0.0
	var on := false
	var idx := -1
	var bi := -1
	for i in keys.size() - 1:
		var a: Dictionary = keys[i]
		var b: Dictionary = keys[i + 1]
		if bool(a.get("c", false)) and bool(b.get("c", false)) and (a["v"] as Vector3).is_equal_approx(b["v"]):
			var t0: float = a["t"]
			var t1: float = b["t"]
			var w := 0.0
			if t >= t0 and t <= t1:
				w = 1.0
				on = true
				idx = i
			elif t < t0 and t > t0 - FOOT_BLEND:
				w = smoothstep(t0 - FOOT_BLEND, t0, t)
			elif t > t1 and t < t1 + 0.05:
				w = 1.0 - smoothstep(t1, t1 + 0.05, t)
			if w > best:
				best = w
				bi = i
	return {"v": v, "w": best, "on": on, "i": idx, "bi": bi}


# ------------------------------------------------------------------ the pose at t

static func _set_trunk(B: Body, rt: Dictionary) -> void:
	var p: float = rt["p"]
	var s: float = rt["s"]
	B.ang["pelvis"] = Vector3(p, 0.0, float(rt["r"]))
	B.ang["pelvis"] = Vector3(p, float(rt["tw"]), float(rt["r"]))
	B.ang["spine_01"] = Vector3(s * 0.25, 0.0, 0.0)
	B.ang["spine_02"] = Vector3(s * 0.35, 0.0, 0.0)
	B.ang["spine_03"] = Vector3(s * 0.4, 0.0, 0.0)
	# the head stays up: the neck takes back half of what the trunk leans (looking where he runs)
	B.ang["neck_01"] = Vector3(-(p + s) * 0.45, 0.0, -float(rt["r"]) * 0.5)
	B.ang["head"] = Vector3(-(p + s) * 0.15, 0.0, 0.0)


## a sole on a wall (mode "wall": the face at x) or on a ledge's face (mode "face": facing -z): LimbIK to the ankle target with the
## foot turned to lie on the face; the knee points along the run (wall) or at the face (face)
static func _surface_foot(B: Body, sd: String, tgt: Vector3, md: String) -> float:
	var ft: String = "foot" + sd
	var v0: Vector3 = (B.p0["ball" + sd] as Vector3) - (B.p0[ft] as Vector3)
	var qf := Quaternion(Vector3.RIGHT, atan2(v0.y, v0.z))
	var rot: Quaternion = (Quaternion(Vector3(0, 0, 1), PI * 0.5) if md == "wall" else Quaternion(Vector3.RIGHT, -PI * 0.5)) * qf
	var hip: Vector3 = B.P["thigh" + sd]
	var pole: Vector3 = hip + (Vector3(-0.3, 0.0, 1.0) if md == "wall" else Vector3(0.0, 0.2, 1.0))
	return float(LimbIK.solve(B, ft, tgt, pole, rot)["miss"])


static func _legs(B: Body, P: Dictionary, t: float, drop: float, rt: Dictionary) -> float:
	## solve both legs; returns the worst stance miss (m)
	var worst := 0.0
	for sd: String in ["_l", "_r"]:
		var tr: Array = P["feet"]["foot" + sd]
		var st := limb_at(tr, t)
		var tgt: Vector3 = st["v"]
		var w: float = st["w"]
		var th: String = "thigh" + sd
		var cl: String = "calf" + sd
		var ft: String = "foot" + sd
		if w <= 0.0:
			var m := B.plant(sd, tgt, 0.0, false)
			if bool(P.get("feet_flat_free", false)):
				m = B.plant(sd, tgt, 0.0, true)
		else:
			var bidx := int(st["i"]) if w >= 1.0 else int(st["bi"])
			var md := String((tr[bidx] as Dictionary).get("mode", "")) if bidx >= 0 else ""
			if w >= 1.0 and md == "":
				worst = maxf(worst, B.plant(sd, tgt, 0.0, true))
			elif w >= 1.0:
				worst = maxf(worst, _surface_foot(B, sd, tgt, md))
			else:
				var m1 := B.plant(sd, tgt, 0.0, false)
				var a1 := {th: B.ang[th], cl: B.ang[cl], ft: B.ang[ft]}
				var m2 := _surface_foot(B, sd, tgt, md) if md != "" else B.plant(sd, tgt, 0.0, true)
				var a2 := {th: B.ang[th], cl: B.ang[cl], ft: B.ang[ft]}
				for j in a1:
					B.ang[j] = (a1[j] as Vector3).lerp(a2[j], w)
				B.fk()
				worst = maxf(worst, m2 * w)
	return worst


static func _arms(B: Body, P: Dictionary, t: float, surfs: Array) -> float:
	var worst := 0.0
	for sd: String in ["_l", "_r"]:
		var tr: Array = P["hands"]["hand" + sd]
		if tr.is_empty():
			continue
		var st := limb_at(tr, t)
		var tgt: Vector3 = st["v"]
		var w: float = st["w"]
		var sgn := 1.0 if sd == "_l" else -1.0
		var sh: Vector3 = B.P["upperarm" + sd]
		var pole: Vector3 = sh + Vector3(sgn * 0.6, -0.15, -0.5)
		if P.has("poles") and (P["poles"] as Dictionary).has("hand" + sd):
			pole = sh + (P["poles"]["hand" + sd] as Vector3) * Vector3(sgn, 1, 1)
		var tip: String = "hand" + sd
		var chain := ["upperarm" + sd, "lowerarm" + sd, tip]
		if w < 1.0:
			var r := LimbIK.solve(B, tip, tgt, pole)
			worst = maxf(worst, float(r["miss"]) * (1.0 - w))
		if w > 0.0:
			var a1 := {}
			for j in chain:
				a1[j] = B.ang[j]
			var rr := ContactIK.reach(B, tip, tgt, surfs)
			if rr.get("on", false):
				worst = maxf(worst, float(rr["miss"]) * w)
			if w < 1.0:
				for j in chain:
					B.ang[j] = (a1[j] as Vector3).lerp(B.ang[j], w)
				B.fk()
	return worst


## FK windows (the roll's tuck): the limbs' angles ease into a given set and out of it, over the window's ramp
static func _fk_windows(B: Body, P: Dictionary, t: float) -> void:
	for w in P.get("fk", []):
		var t0: float = w["t0"]
		var t1: float = w["t1"]
		var rp: float = w["ramp"]
		var k := 0.0
		if t >= t0 and t <= t1:
			k = 1.0
		elif t < t0 and t > t0 - rp:
			k = smoothstep(t0 - rp, t0, t)
		elif t > t1 and t < t1 + rp:
			k = 1.0 - smoothstep(t1, t1 + rp, t)
		if k > 0.0:
			for j in w["ang"]:
				B.ang[j] = (B.ang[j] as Vector3).lerp(w["ang"][j], k)
			B.fk()


## the set's penetration: the deepest capsule beyond what a flat sole's own depth allows (m), and where.
## The loop (every capsule x every box x a sample per cm) is C++ when KineParkourNative is loaded (native/src/kine_parkour_native.cpp);
## deepest_gd is the same arithmetic in GDScript, the fallback and the equality bar's other side (tests/ch7_test.gd)
static var use_native := true


static func native_on() -> bool:
	return use_native and ClassDB.class_exists("KineParkourNative")


static func boxes_of(props: Array) -> Array:
	var out := []
	for p in props:
		for sw in Props.solids(p):
			if not sw.has("r") and not sw.has("poly"):
				out.append({"c": (sw["xf"] as Transform3D).origin, "h": sw["half"], "kind": String(p["kind"])})
	return out


static func deepest(B: Body, boxes: Array) -> Dictionary:
	if native_on():
		var a := PackedVector3Array()
		var b := PackedVector3Array()
		var r := PackedFloat32Array()
		var base := PackedFloat32Array()
		var c := PackedVector3Array()
		var h := PackedVector3Array()
		for part in Body.BODY:
			var cp: Array = B.cap(part)
			a.append(cp[0])
			b.append(cp[1])
			r.append(B.rad[part])
			base.append(STAND_DEPTH.get(part, 0.0))
		for bx in boxes:
			c.append(bx["c"])
			h.append(bx["h"])
		var o: Array = (load("res://scripts/parkour_native.gd") as GDScript).deepest(a, b, r, base, c, h)
		var w := ""
		if int(o[1]) >= 0:
			w = "%s in %s" % [Body.BODY[int(o[1])], String(boxes[int(o[2])]["kind"])]
		return {"d": float(o[0]), "where": w}
	return deepest_gd(B, boxes)


static func deepest_gd(B: Body, boxes: Array) -> Dictionary:
	var best := 0.0
	var where := ""
	for part in Body.BODY:
		var c: Array = B.cap(part)
		var r: float = B.rad[part]
		var base: float = STAND_DEPTH.get(part, 0.0)
		var n := maxi(1, ceili((c[0] as Vector3).distance_to(c[1]) / Props.STEP))
		for bx in boxes:
			var worst := 0.0
			for k in n + 1:
				var pt: Vector3 = (c[0] as Vector3).lerp(c[1], float(k) / n)
				var l: Vector3 = pt - (bx["c"] as Vector3)
				var hh: Vector3 = bx["h"]
				var q := Vector3(absf(l.x) - hh.x, absf(l.y) - hh.y, absf(l.z) - hh.z)
				var sd := Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0)).length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)
				worst = maxf(worst, r - sd)
			var d := worst - base
			if d > best:
				best = d
				where = "%s in %s" % [part, String(bx["kind"])]
	return {"d": best, "where": where}


## the pelvis's extra height at t from the smoothed lifts of the first pass (P["yadd"], one per frame; none = 0)
static func _yadd(P: Dictionary, t: float) -> float:
	var ya: Array = P.get("yadd", [])
	if ya.is_empty():
		return 0.0
	return float(ya[clampi(int(round(t * FPS)), 0, ya.size() - 1)])


## the lifts of a first pass, dilated (the max over +-reach frames) then smoothed: a lift that pops 0.5 m in one frame and
## is gone the next is a flicker, a lift that rises and settles over a few frames is a pelvis riding over an obstacle
static func smooth_lifts(lifts: Array, reach := 4) -> Array:
	var n := lifts.size()
	var dil := []
	for k in n:
		var m := 0.0
		for j in range(maxi(0, k - reach), mini(n, k + reach + 1)):
			m = maxf(m, float(lifts[j]))
		dil.append(m)
	var out := []
	for k in n:
		var acc := 0.0
		var wsum := 0.0
		for j in range(-reach, reach + 1):
			var w := float(reach + 1 - absi(j))
			var i := clampi(k + j, 0, n - 1)
			acc += w * float(dil[i])
			wsum += w
		out.append(acc / wsum)
	return out


## the pose at t as a Body (the shared one), with the iteration's report: {"miss", "lift", "pen"}
static func pose(P: Dictionary, t: float, boxes: Array, surfs: Array) -> Dictionary:
	var B := body()
	var rt := root_at(P, t)
	var drop := 0.0
	var miss := 0.0
	var pen := {"d": 0.0, "where": ""}
	var pen0 := {"d": -1.0, "where": ""}
	var y: float = float(rt["y"]) + _yadd(P, t)
	for it in 6:
		B.from_dict(_base)
		_set_trunk(B, rt)
		var p0: Vector3 = B.p0["pelvis"]
		B.offset = Vector3(float(rt["x"]), y - p0.y, float(rt["z"]))
		B.fk()
		miss = _legs(B, P, t, drop, rt)
		var am := _arms(B, P, t, surfs)
		_fk_windows(B, P, t)
		if miss > REACH_EPS:
			y -= minf(miss, 0.12)
			continue
		pen = deepest(B, boxes)
		if float(pen0["d"]) < 0.0:
			pen0 = pen
		if float(pen["d"]) > SKIN * 0.3 and bool(P.get("lift", true)) and not bool(P.get("nolift_" + str(int(t * FPS)), false)):
			y += minf(float(pen["d"]), 0.12)
			continue
		miss = maxf(miss, 0.0)
		return {"miss": miss, "arm_miss": am, "lift": y - float(rt["y"]), "pen": pen, "pen0": pen0}
	return {"miss": miss, "arm_miss": 0.0, "lift": y - float(rt["y"]), "pen": pen, "pen0": pen0}


## the whole run as a Scene dictionary: {"ok", "scene": dict, "report": per-frame [{t, miss, lift, pen}]}
static func build(P: Dictionary) -> Dictionary:
	var S := Scene.new()
	add_course(S, P["obstacles"])
	var surfs := ContactIK.surfaces(S.props)
	var boxes := boxes_of(S.props)
	var B := body()
	var cards := []
	var rep := []
	var n := int(round(float(P["length"]) * FPS)) + 1
	if bool(P.get("two_pass", true)) and not P.has("yadd"):
		var lifts := []
		for k in n:
			lifts.append(maxf(0.0, float(pose(P, float(k) / FPS, boxes, surfs)["lift"])))
		P["yadd"] = smooth_lifts(lifts)
	for k in n:
		var t := float(k) / FPS
		var r := pose(P, t, boxes, surfs)
		if k % 15 == 0:
			print("frame %d t %.2f ms %d miss %.3f pen %.3f" % [k, t, Time.get_ticks_msec(), r["miss"], (r["pen"] as Dictionary)["d"]])
		var d := B.to_dict()
		cards.append({"name": "f%d" % k, "pose": d, "move": (0.0 if k == 0 else 1.0 / FPS), "hold": 0.0, "arrive_s": snappedf(t, 0.0001), "leave_s": snappedf(t, 0.0001), "walk": false})
		rep.append({"t": t, "miss": r["miss"], "arm_miss": r["arm_miss"], "lift": r["lift"], "pen": (r["pen"] as Dictionary)["d"], "pen_where": (r["pen"] as Dictionary)["where"]})
	var d := {"fps": FPS, "on_floor": false, "floor_body": false, "natural": false, "pin": false, "free_limits": true, "scene": "ch7_run",
		"plan": "CH7: chained parkour run (speed vault, kong, wall run, cat leap, drop and roll, slide)", "cards": cards, "length_s": float(P["length"])}
	var out := S.to_dict(body(), false)
	for k in d:
		out[k] = d[k]
	if out.has("props") == false:
		out["props"] = S.props.map(func(p): return Props.to_dict(p))
	return {"ok": true, "scene": out, "report": rep, "props": S.props}
