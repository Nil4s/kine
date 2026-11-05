## hand_shape.gd - THE HAND'S COLLISION SHAPE (lane HAND, gaps G23 and G38). The rig's hand collided as ONE capsule from
## the wrist to the knuckles of radius 4.7 cm (a 9.4 cm thick sausage): it could not lie flat on a box (CH7b: 13-54 mm
## palm penetrations) nor close round a rope (CH6b swapped in 4 slim capsules of its own). Here the hand is:
##   THE PALM  a row of PALM_ROWS parallel capsules along the hand, together a slab of the cited palm length, hand breadth
##             and thickness (a rectangle swept by a sphere of radius thickness / 2: flat faces, round edges). Between two
##             neighbouring capsules the face dips by r - sqrt(r^2 - (s/2)^2) (s = their spacing): 1.0 mm at 6 rows.
##   FINGERS   one capsule per phalanx on the finger joints as they are posed (B.cap of each finger bone: the curl is
##             followed), radius FINGER_R.
## Every capsule is [a, b, r, part]: the same form as Body.cap + Body.rad, so any capsule test (Props.depth, the CH7b
## penetration scan, the CH6 rope colliders) takes it unchanged. HandShape.legacy = true gives the old single capsule
## (for comparing old and new numbers on the same pose).
## On top of the shape: palm_flat() (a palm laid flat on a surface, fingers along it or hooked over an edge) and close_on()
## (the fingers closed round capsules, a rope's segments, until they touch).
##
## SOURCES (men, 50th percentile; the default body is scaled by Body.hand_s):
##   ANSUR II, Gordon et al. 2014, "2012 Anthropometric Survey of U.S. Army Personnel", NATICK/TR-15/007 (the tables as
##   reproduced by ergoassessment.cam/ansur-2-data-explorer): hand breadth (no. 42) 8.8 cm, palm length (no. 65) 11.6 cm,
##   hand circumference over the knuckles (no. 43) 21.2 cm, hand length (no. 44) 19.3 cm, wrist circumference (no. 92) 17.6 cm.
##   THICKNESS is derived, not measured: the knuckle section as a stadium (a rectangle with round ends, the section the
##   capsule row has), C = 2 (B - t) + pi t, so t = (C - 2 B) / (pi - 2) = (21.2 - 17.6) / 1.1416 = 3.15 cm.
##   FINGER_R: FAA HFDS Appendix B (Technical Operations survey), index finger breadth at the PIP joint, men 50th 2.1 cm.
class_name HandShape
extends RefCounted

static var legacy := false   # true: every HandShape answer is the old single hand capsule (Body.cap(h), Body.rad[h])

const HAND_BREADTH := 0.088   # m, ANSUR II no. 42
const PALM_LENGTH := 0.116    # m, ANSUR II no. 65
const HAND_CIRC := 0.212      # m, ANSUR II no. 43
const HAND_LENGTH := 0.193    # m, ANSUR II no. 44 (reported, not used by the shape: the rig's fingers are its own)
const FINGER_R := 0.0105      # m, FAA HFDS App. B index finger breadth 2.1 cm / 2
const PALM_ROWS := 6
const FINGERS := ["index", "middle", "ring", "pinky", "thumb"]
const FINGERS4 := ["index", "middle", "ring", "pinky"]
const GAP := 0.0005           # m: palm_flat leaves the palm this far off the surface, close_on the fingers off the rope
## WHERE THE SLAB SITS through the hand: the drawn mannequin's palm skin is 3.5 cm palm-side of the hand's bone line (wrist
## -> middle knuckle) in the knuckle band, its back 1.9 cm the other side (tools/hand_mesh.gd, 76 palm vertices; the drawn
## hand is 5.4 cm thick there, a mitten, 1.7x the cited 3.15). The slab's palm face is put ON the drawn palm skin, so a
## palm that is flat in the collision model is flat on screen; its back then sits 2.3 cm inside the drawn back.
const PALM_SKIN := 0.035
## THE WRIST. The forearm's capsule (Body.rad lowerarm, 5.4 cm: the muscle belly) ends in a 5.4 cm ball round the wrist
## joint, which is only 3.5 cm off a surface the palm lies flat on: any flat palm would put the forearm 1.9 cm into it.
## A real wrist is far slimmer: ANSUR II wrist circumference (no. 92) men 50th 17.6 cm, as a circle r = 2.8 cm.
## forearm_caps() splits the forearm: elbow -> FOREARM_SPLIT of its length at Body.rad, then a wrist capsule of WRIST_R.
const WRIST_CIRC := 0.176
const FOREARM_SPLIT := 0.55


## the palm's thickness from the cited breadth and circumference (the stadium section above), m
static func palm_thickness() -> float:
	return (HAND_CIRC - 2.0 * HAND_BREADTH) / (PI - 2.0)


## the wrist capsule's radius (m): the cited wrist circumference as a circle
static func wrist_r() -> float:
	return WRIST_CIRC / TAU


## the palm's size on hand h of B, m: {"length", "breadth", "thickness", "rho" (the capsules' radius), "off" (the slab's
## middle plane, palm-side of the bone line), "rows", "s" (scale)}
static func dims(B: Body, h: String) -> Dictionary:
	var s := B.hand_s(h) if B != null else 1.0
	var t := palm_thickness() * s
	return {"length": PALM_LENGTH * s, "breadth": HAND_BREADTH * s, "thickness": t, "rho": t * 0.5, "off": PALM_SKIN * s - t * 0.5,
		"rows": PALM_ROWS, "s": s}


## the hand's own frame AT REST (body space): "ax" along the hand (wrist -> middle knuckle), "br" across the knuckles
## (pinky -> index), "nr" the palm's outward normal (the side the fingers curl to: Body.PALM_DROP's side), "c" the
## palm's centre across (m along br from the wrist joint: the middle of the index and pinky knuckles)
static func frame0(B: Body, h: String) -> Dictionary:
	var sd := h.substr(4)
	var w: Vector3 = B.p0[h]
	var ax := ((B.e0[h] as Vector3) - w).normalized()
	var ix: Vector3 = B.p0["index_01" + sd]
	var px: Vector3 = B.p0["pinky_01" + sd]
	var br := ix - px
	br = (br - ax * br.dot(ax)).normalized()
	var nr := ax.cross(br).normalized()
	if nr.dot(Body.PALM_DROP) < 0.0:
		nr = -nr
	return {"ax": ax, "br": br, "nr": nr, "c": ((ix + px) * 0.5 - w).dot(br)}


## a rest point of hand h carried to where the hand is now
static func _pose(B: Body, h: String, p: Vector3) -> Vector3:
	return (B.P[h] as Vector3) + (B.G[h] as Quaternion) * (p - (B.p0[h] as Vector3))


## a rest point of the palm (u along from the wrist, v across from the palm's centre line, z through, from the slab's
## middle plane toward the palm side), m, in body rest space
static func _palm_rest(B: Body, h: String, u: float, v: float, z: float) -> Vector3:
	var f := frame0(B, h)
	var d := dims(B, h)
	return (B.p0[h] as Vector3) + (f["ax"] as Vector3) * u + (f["br"] as Vector3) * (float(f["c"]) + v) + (f["nr"] as Vector3) * (float(d["off"]) + z)


## the palm's capsules now: [[a, b, r, h], ...] (PALM_ROWS of them, across the hand)
static func palm_caps(B: Body, h: String) -> Array:
	if legacy:
		var c: Array = B.cap(h)
		return [[c[0], c[1], float(B.rad[h]), h]]
	var d := dims(B, h)
	var rho: float = d["rho"]
	var half_core: float = float(d["breadth"]) * 0.5 - rho
	var out := []
	for i in PALM_ROWS:
		var v := lerpf(-half_core, half_core, float(i) / float(PALM_ROWS - 1))
		out.append([_pose(B, h, _palm_rest(B, h, rho, v, 0.0)), _pose(B, h, _palm_rest(B, h, float(d["length"]) - rho, v, 0.0)), rho, h])
	return out


## the finger capsules now: [[a, b, r, joint], ...] (index, middle, ring, pinky, thumb; 3 each). None with legacy on.
static func finger_caps(B: Body, h: String) -> Array:
	if legacy:
		return []
	var sd := h.substr(4)
	var r := FINGER_R * B.hand_s(h)
	var out := []
	for fg in FINGERS:
		for k in 3:
			var j := "%s_0%d%s" % [fg, k + 1, sd]
			var c: Array = B.cap(j)
			out.append([c[0], c[1], r, j])
	return out


## one finger's capsules now (fg = "index" .. "thumb")
static func _finger(B: Body, h: String, fg: String) -> Array:
	var sd := h.substr(4)
	var r := FINGER_R * B.hand_s(h)
	var out := []
	for k in 3:
		var j := "%s_0%d%s" % [fg, k + 1, sd]
		var c: Array = B.cap(j)
		out.append([c[0], c[1], r, j])
	return out


## every capsule of hand h now (palm, then fingers unless fingers = false)
static func caps(B: Body, h: String, fingers := true) -> Array:
	var out := palm_caps(B, h)
	if fingers:
		out.append_array(finger_caps(B, h))
	return out


## the forearm of hand h's arm now: [[elbow, split, Body.rad, part], [split, wrist, wrist_r(), part]] (legacy: Body's one capsule)
static func forearm_caps(B: Body, h: String) -> Array:
	var fa: String = B.parent[h]
	var c: Array = B.cap(fa)
	if legacy:
		return [[c[0], c[1], float(B.rad[fa]), fa]]
	var m: Vector3 = (c[0] as Vector3).lerp(c[1], FOREARM_SPLIT)
	return [[c[0], m, float(B.rad[fa]), fa], [m, c[1], wrist_r() * B.hand_s(h), fa]]


## the palm's face now: {"o": the centre of its outer (palm-side) face, "n": its outward normal, "ax": along the hand,
## "br": across}. With legacy on: the old capsule's palm side at the 60 % point (ContactIK.palm_gap's place).
static func palm_face(B: Body, h: String) -> Dictionary:
	var f := frame0(B, h)
	var g: Quaternion = B.G[h]
	var n: Vector3 = g * (f["nr"] as Vector3)
	if legacy:
		return {"o": (B.P[h] as Vector3).lerp(B.E[h], 0.6) + n * float(B.rad[h]), "n": n, "ax": g * (f["ax"] as Vector3), "br": g * (f["br"] as Vector3)}
	var d := dims(B, h)
	return {"o": _pose(B, h, _palm_rest(B, h, float(d["length"]) * 0.5, 0.0, float(d["rho"]))), "n": n, "ax": g * (f["ax"] as Vector3), "br": g * (f["br"] as Vector3)}


# ---------------------------------------------------------------- distances

## the nearest point of segment a-b to p
static func seg_point(a: Vector3, b: Vector3, p: Vector3) -> Vector3:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(1e-12, ab.length_squared()), 0.0, 1.0)
	return a + ab * t


## signed distance from pt to a Props solid ({"xf", "half"} box, {"xf", "r"} sphere, {"xf", "poly", "w"} outline): Props._sd
static func sd(sw: Dictionary, pt: Vector3) -> float:
	return Props._sd(sw, pt)


## a capsule's signed gap to a solid (m): the least signed distance along its axis less its radius (< 0 = inside). Boxes
## and spheres: exact (a convex solid's signed distance is convex along a line: a golden-section search to 1e-7 of the
## axis); an extruded outline: sampled every 2 mm.
static func cap_gap(c: Array, sw: Dictionary) -> float:
	var a: Vector3 = c[0]
	var b: Vector3 = c[1]
	var r := float(c[2])
	if sw.has("poly"):
		var n := maxi(1, ceili(a.distance_to(b) / 0.002))
		var best := INF
		for i in n + 1:
			best = minf(best, sd(sw, a.lerp(b, float(i) / n)))
		return best - r
	var lo := 0.0
	var hi := 1.0
	var gr := 0.6180339887498949
	var x1 := hi - gr * (hi - lo)
	var x2 := lo + gr * (hi - lo)
	var f1 := sd(sw, a.lerp(b, x1))
	var f2 := sd(sw, a.lerp(b, x2))
	for it in 40:
		if f1 < f2:
			hi = x2
			x2 = x1
			f2 = f1
			x1 = hi - gr * (hi - lo)
			f1 = sd(sw, a.lerp(b, x1))
		else:
			lo = x1
			x1 = x2
			f1 = f2
			x2 = lo + gr * (hi - lo)
			f2 = sd(sw, a.lerp(b, x2))
	return minf(minf(f1, f2), minf(sd(sw, a), sd(sw, b))) - r


## the deepest of the capsules in any of the solids: {"d": m (0 = none inside), "part": its name, "gap": the least signed gap}
static func deepest(cs: Array, solids: Array) -> Dictionary:
	var best := INF
	var part := ""
	for c in cs:
		for sw in solids:
			var g := cap_gap(c, sw)
			if g < best:
				best = g
				part = String(c[3]) if c.size() > 3 else ""
	return {"d": maxf(0.0, -best), "part": part, "gap": best}


## the least gap (m, < 0 = overlap) between capsules cs and capsules obs ([a, b, r, ...] both)
static func caps_gap(cs: Array, obs: Array) -> float:
	var best := INF
	for c in cs:
		for o in obs:
			best = minf(best, Body.seg_seg(c[0], c[1], o[0], o[1]) - float(c[2]) - float(o[2]))
	return best


## the least gap (m, < 0 = inside) between capsules cs and a ball (a rope particle) at p of radius r
static func point_gap(cs: Array, p: Vector3, r: float) -> float:
	var best := INF
	for c in cs:
		best = minf(best, p.distance_to(seg_point(c[0], c[1], p)) - float(c[2]) - r)
	return best


## a half-space as a Props box solid: everything on the -n side of the plane through c
static func half_space(c: Vector3, n: Vector3) -> Dictionary:
	n = n.normalized()
	var t := n.cross(Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
	var bs := Basis(t, n, t.cross(n)).orthonormalized()
	if bs.y.dot(n) < 0.0:
		bs.y = -bs.y
	return {"xf": Transform3D(bs, c - n * 50.0), "half": Vector3(50, 50, 50)}


## the union of capsules' signed distance at p (< 0 = inside one)
static func _caps_sd(cs: Array, p: Vector3) -> float:
	var best := INF
	for c in cs:
		best = minf(best, p.distance_to(seg_point(c[0], c[1], p)) - float(c[2]))
	return best


## THE PALM'S CONTACT AREA, 0..1: the cited palm (PALM_LENGTH x HAND_BREADTH, on the slab's face) gridded nu x nv; from
## each grid point a ray goes into the hand along the palm normal and stops on the palm capsules' real surface (sphere
## tracing: the round edges and the 1 mm dips between the rows count as they are); the point touches when that surface
## point is within tol of a solid's surface. With legacy on the same grid falls on the old capsule.
static func contact_area(B: Body, h: String, solids: Array, tol := 0.003, nu := 24, nv := 18) -> float:
	var d := dims(B, h)
	var pc := palm_caps(B, h)
	var n: Vector3 = palm_face(B, h)["n"]
	var hit := 0
	for i in nu:
		for k in nv:
			var u := (float(i) + 0.5) / nu * float(d["length"])
			var v := ((float(k) + 0.5) / nv - 0.5) * float(d["breadth"])
			var q := _pose(B, h, _palm_rest(B, h, u, v, float(d["rho"])))
			var p := q + n * 0.06
			var trav := 0.0
			var on := false
			while trav < 0.2:
				var s := _caps_sd(pc, p)
				if s < 1e-5:
					on = true
					break
				p -= n * s
				trav += s
			if not on:
				continue
			var best := INF
			for sw in solids:
				best = minf(best, absf(sd(sw, p)))
			if best <= tol:
				hit += 1
	return float(hit) / float(nu * nv)


# ---------------------------------------------------------------- posing

## a finger's (or the thumb's) clearance to the solids now, m (< 0 = into one)
static func _finger_gap(B: Body, h: String, fg: String, solids: Array) -> float:
	return deepest(_finger(B, h, fg), solids)["gap"]


## set joint j's bend (degrees, clamped to its limits) and run FK
static func _bend(B: Body, j: String, deg: float) -> void:
	var v: Vector3 = B.ang[j]
	B.ang[j] = B.clamp_ang(j, Vector3(deg, v.y, v.z))
	B.fk()


## the largest bend of joint j in [lo, hi] (deg) that leaves finger fg GAP clear of the solids (bisection; the clearance
## falls as the joint bends toward the surface). Returns the bend set.
static func _bend_to_touch(B: Body, h: String, fg: String, j: String, lo: float, hi: float, solids: Array) -> float:
	_bend(B, j, hi)
	if _finger_gap(B, h, fg, solids) >= GAP:
		return hi
	_bend(B, j, lo)
	if _finger_gap(B, h, fg, solids) < GAP:
		return lo
	for it in 30:
		var mid := (lo + hi) * 0.5
		_bend(B, j, mid)
		if _finger_gap(B, h, fg, solids) >= GAP:
			lo = mid
		else:
			hi = mid
	_bend(B, j, lo)
	return lo


## the thumb laid on the surface: thumb_01's bend and side searched over its range on a 5 deg grid (thumb_02 / 03 straight),
## the pose kept that is clear (GAP) and nearest the surface; if none is clear, the least deep
static func _thumb_rest(B: Body, h: String, solids: Array) -> void:
	var sd := h.substr(4)
	var j := "thumb_01" + sd
	for k in ["thumb_02" + sd, "thumb_03" + sd]:
		B.ang[k] = Vector3.ZERO
	var L: Dictionary = B.lim[j]
	var best := Vector3.ZERO
	var best_c := INF
	var b := float(L["bend"].x)
	while b <= float(L["bend"].y) + 1e-6:
		var s := float(L["side"].x)
		while s <= float(L["side"].y) + 1e-6:
			B.ang[j] = Vector3(b, s, 0.0)
			B.fk()
			var g := _finger_gap(B, h, "thumb", solids)
			var cost := (g - GAP) if g >= GAP else 10.0 + (GAP - g)
			if cost < best_c:
				best_c = cost
				best = Vector3(b, s, 0.0)
			s += 5.0
		b += 5.0
	B.ang[j] = B.clamp_ang(j, best)
	B.fk()


## the turn taking the hand's rest frame onto (ax1 along, nr1 the palm's outward normal), the handedness of the rest frame kept
static func _hand_rot(f: Dictionary, ax1: Vector3, nr1: Vector3) -> Quaternion:
	var M0 := Basis(f["ax"], f["br"], f["nr"])
	var br1 := nr1.cross(ax1).normalized()
	var M1 := Basis(ax1, br1, nr1)
	if signf(M1.determinant()) != signf(M0.determinant()):
		M1 = Basis(ax1, -br1, nr1)
	return Quaternion((M1 * M0.inverse()).orthonormalized()).normalized()


## the palm's lowest point off the plane (c, n), m (< 0 = into it): its capsules' end balls are its lowest points on a plane
static func palm_plane_gap(B: Body, h: String, c: Vector3, n: Vector3) -> float:
	var best := INF
	for pc in palm_caps(B, h):
		best = minf(best, minf(n.dot((pc[0] as Vector3) - c), n.dot((pc[1] as Vector3) - c)) - float(pc[2]))
	return best


## PALM FLAT (G23): pose hand h so its palm lies on the surface at point c with outward normal n.
##   The hand's turn takes the rest palm normal to -n and the rest finger line to fdir (a direction along the surface;
##   opts "fdir", default: where the fingers point now, laid into the surface). The palm's face centre goes to c, GAP off.
##   LimbIK.solve puts the wrist there inside the arm's limits; a limit that stops the turn leaves the palm tilted, so the
##   wrist then moves along n until the palm's lowest point is GAP off (4 passes): never into the surface.
##   FINGERS (flat): straight, then each knuckle (MCP) bends down until the finger rests on the surface (GAP); the thumb
##   is laid on it (_thumb_rest). HOOK (opts "hook": {"edge": a point on the edge, "over_n": the outward normal of the face
##   the fingers curl onto}): the hand slides along fdir until the middle knuckle is FINGER_R + GAP past that face, then
##   each finger's three joints bend in turn, each as far as it goes without entering (_bend_to_touch).
##   opts "solids": the Props solids the fingers and thumb are kept out of (default: the half-space under the plane);
##   opts "pole": the elbow's pole (default: the current bend).
## Returns {"miss": wrist from its target (m), "clamped": [joints a limit stopped], "pen": the deepest hand capsule in the
## solids (m), "palm_gap": the palm's lowest point off the plane (m), "forearm_gap": forearm_caps' least gap to the solids}
static func palm_flat(B: Body, h: String, c: Vector3, n: Vector3, opts := {}) -> Dictionary:
	n = n.normalized()
	var solids: Array = opts.get("solids", [half_space(c, n)])
	var f := frame0(B, h)
	var fdir: Vector3 = opts.get("fdir", (B.G[h] as Quaternion) * (f["ax"] as Vector3))
	fdir = (fdir - n * fdir.dot(n))
	if fdir.length() < 1e-6:
		fdir = n.cross(Vector3.FORWARD if absf(n.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT)
	fdir = fdir.normalized()
	var Q := _hand_rot(f, fdir, -n)
	var sd := h.substr(4)
	for fg in FINGERS4:
		for k in 3:
			B.ang["%s_0%d%s" % [fg, k + 1, sd]] = Vector3.ZERO
	B.fk()
	var d := dims(B, h)
	var w0: Vector3 = B.p0[h]
	var o0 := _palm_rest(B, h, float(d["length"]) * 0.5, 0.0, float(d["rho"])) - w0
	var W := c + n * GAP - Q * o0
	var hook: Dictionary = opts.get("hook", {})
	if not hook.is_empty():
		var on: Vector3 = (hook["over_n"] as Vector3).normalized()
		var k0: Vector3 = (B.p0["middle_01" + sd] as Vector3) - w0
		var mcp := W + Q * k0
		var along := on.dot(fdir)
		if absf(along) > 1e-6:
			W += fdir * ((FINGER_R * B.hand_s(h) + GAP - on.dot(mcp - (hook["edge"] as Vector3))) / along)
	var pole: Vector3 = opts.get("pole", LimbIK.pole_from_pose(B, h))
	var r := {}
	for it in 5:
		r = LimbIK.solve(B, h, W, pole, Q)
		var g := palm_plane_gap(B, h, c, n)
		if absf(g - GAP) < 0.0001:
			break
		W += n * (GAP - g)
	if hook.is_empty():
		for fg in FINGERS4:
			_bend_to_touch(B, h, fg, "%s_01%s" % [fg, sd], 0.0, 25.0, solids)
	else:
		for fg in FINGERS4:
			for k in 3:
				var j := "%s_0%d%s" % [fg, k + 1, sd]
				_bend_to_touch(B, h, fg, j, 0.0, float(B.lim[j]["bend"].y), solids)
	_thumb_rest(B, h, solids)
	return {"miss": ((B.P[h] as Vector3) - W).length(), "clamped": r.get("clamped", []), "pen": deepest(caps(B, h), solids)["d"],
		"palm_gap": palm_plane_gap(B, h, c, n), "forearm_gap": deepest(forearm_caps(B, h), solids)["gap"]}


## the curl c of finger fg (0 = straight, 1 = Body.POSE_FIST, its three joints together, as a fist closes)
static func _curl(B: Body, h: String, fg: String, c: float) -> void:
	var sd := h.substr(4)
	var fi: int = (FINGERS4 + ["thumb"]).find(fg)
	for k in 3:
		var j := "%s_0%d%s" % [fg, k + 1, sd]
		var v: Vector3 = Body.POSE_FIST[3 * fi + k]
		if sd == "_l" and fg == "thumb" and k == 0:
			v.z = -v.z
		B.ang[j] = B.clamp_ang(j, v * c)
	B.fk()


## CLOSE ON (G38): each finger of hand h (and the thumb) curls (_curl, 0 -> 1 in steps of 0.02) until it would come within
## GAP of the obstacles ([[a, b, r], ...] capsules: a rope's segments with its own radius); the last clear step is refined
## by bisection. A finger never enters. Returns {finger: [curl, clearance m]}
static func close_on(B: Body, h: String, obstacles: Array) -> Dictionary:
	var out := {}
	for fg in FINGERS4 + ["thumb"]:
		var lo := 0.0
		var hi := -1.0
		var c := 0.0
		while c <= 1.0 + 1e-9:
			_curl(B, h, fg, c)
			if caps_gap(_finger(B, h, fg), obstacles) < GAP:
				hi = c
				break
			lo = c
			c += 0.02
		if hi >= 0.0:
			for it in 25:
				var mid := (lo + hi) * 0.5
				_curl(B, h, fg, mid)
				if caps_gap(_finger(B, h, fg), obstacles) >= GAP:
					lo = mid
				else:
					hi = mid
		_curl(B, h, fg, lo)
		out[fg] = [lo, caps_gap(_finger(B, h, fg), obstacles)]
	return out
