## contact_ik.gd - CONTACT-AWARE HAND IK (ROADMAP 88): a hand dragged on a wall or a table SLIDES along it instead of
## passing through. The contact surfaces are the scene's props (Props: a "wall", a "table", any box): each box face is a
## rectangle with an outward normal. With contact on, a hand's raw target (where the mouse put the wrist) is projected
## onto the nearest rectangle, and the wrist sits one HAND RADIUS off that face (the hand's capsule touches it), with the
## palm turned to face it. The limb is then solved with LimbIK.solve (the same closed-form IK as every other pull), so the
## elbow stays inside its joint limits and the existing undo, keys and pole behave as before.
##
## THE PALM GAP: the palm's surface is the hand capsule on its palm side, at the 60 % point of the hand (Body.palm_point's
## place). Its signed distance to the face is n.(P + 0.6 (E - P) - c) - r, r = Body.rad[hand] (the capsule radius): 0 =
## flat on the face, negative = into it. tip_gap() is the same for the whole capsule (its two ends), for the no-penetration bar.
class_name ContactIK
extends RefCounted

const LEAD := 0.0005   # m: the forearm's underside sits this far off the face at the wrist (the forearm clears by 0.5 mm)


## the contact faces of the props: [{"c": face centre, "n": outward normal, "a", "b": in-face axes, "ha", "hb": half
## extents}]. Spheres (the ball) are not surfaces. A prop with no solids gives none.
static func surfaces(props: Array) -> Array:
	var out := []
	for p in props:
		for sw in Props.solids(p):
			if sw.has("r"):
				continue
			var X: Transform3D = sw["xf"]
			var h: Vector3 = sw["half"]
			var ax := [X.basis.x.normalized(), X.basis.y.normalized(), X.basis.z.normalized()]
			for i in 3:
				var j := (i + 1) % 3
				var k := (i + 2) % 3
				for s in [-1.0, 1.0]:
					var n: Vector3 = ax[i] * s
					out.append({"c": X.origin + n * h[i], "n": n, "a": ax[j], "b": ax[k], "ha": h[j], "hb": h[k]})
	return out


## the face nearest the raw target: {"S": the point of the face's rectangle nearest it, "n": the face's normal,
## "c": the face's centre, "d": the distance}; {} with no surfaces
static func project(raw: Vector3, surfs: Array) -> Dictionary:
	var best := {}
	var best_d := INF
	for f in surfs:
		var d: Vector3 = raw - (f["c"] as Vector3)
		var x := clampf(d.dot(f["a"]), -float(f["ha"]), float(f["ha"]))
		var y := clampf(d.dot(f["b"]), -float(f["hb"]), float(f["hb"]))
		var S: Vector3 = (f["c"] as Vector3) + (f["a"] as Vector3) * x + (f["b"] as Vector3) * y
		var dist := (raw - S).length()
		if dist < best_d - 1e-9:
			best_d = dist
			best = {"S": S, "n": f["n"], "c": f["c"], "d": dist}
	return best


## the palm's signed gap to the face (c, n): 0 = the palm is on it, < 0 = into it (m)
static func palm_gap(B: Body, tip: String, c: Vector3, n: Vector3) -> float:
	var P: Vector3 = B.P[tip]
	var E: Vector3 = B.E[tip]
	return n.dot(P + 0.6 * (E - P) - c) - float(B.rad[tip])


## the hand capsule's signed gap to the face (the nearer of its two ends, less its radius): < 0 = penetrating (m)
static func tip_gap(B: Body, tip: String, c: Vector3, n: Vector3) -> float:
	var r := float(B.rad[tip])
	return minf(n.dot((B.P[tip] as Vector3) - c), n.dot((B.E[tip] as Vector3) - c)) - r


## the shortest rotation taking unit direction a onto unit direction b
static func _arc(a: Vector3, b: Vector3) -> Quaternion:
	a = a.normalized()
	b = b.normalized()
	var d := clampf(a.dot(b), -1.0, 1.0)
	if d > 1.0 - 1e-9:
		return Quaternion.IDENTITY
	if d < -1.0 + 1e-9:
		var ax := a.cross(Vector3.UP)
		if ax.length() < 1e-6:
			ax = a.cross(Vector3.RIGHT)
		return Quaternion(ax.normalized(), PI)
	return Quaternion(a.cross(b).normalized(), acos(d))


## the signed gap of every arm capsule (upper arm, forearm, hand) to the face (c, n): the least of them (m). The forearm
## is thicker than the hand (Body.rad), so at the wrist it is the forearm that reaches the face first.
static func arm_gap(B: Body, tip: String, c: Vector3, n: Vector3) -> float:
	var mid: String = B.parent[tip]
	var root: String = B.parent[mid]
	var P := B.P
	var g := n.dot((P[root] as Vector3) - c) - float(B.rad[root])
	g = minf(g, minf(n.dot((P[root] as Vector3) - c), n.dot((P[mid] as Vector3) - c)) - float(B.rad[root]))
	g = minf(g, minf(n.dot((P[mid] as Vector3) - c), n.dot((P[tip] as Vector3) - c)) - float(B.rad[mid]))
	g = minf(g, minf(n.dot((P[tip] as Vector3) - c), n.dot((B.E[tip] as Vector3) - c)) - float(B.rad[tip]))
	return g


## put the hand on the nearest face of `surfs` for the raw wrist target `raw`, with the WHOLE ARM clear of it. The palm is
## turned to the face. The wrist sits one forearm radius off the face (less LEAD), because the forearm is the thicker capsule
## and would otherwise be the part that reaches the face first; the hand then leans its knuckle end off the face by the
## difference (a degree or two), so the palm stays within about 3 mm of it. The limb is solved with LimbIK.solve and its
## elbow kept on the side it bends now (LimbIK.pole_from_pose); the wrist is corrected to its height after the solve, so a
## joint limit that stops the turn is reported, not hidden. Returns {"on": false} with no surface, else {"on", "miss"
## (the wrist from the mouse's point on the face, m), "gap" (palm), "tip_gap" (hand capsule), "arm_gap" (every arm capsule),
## "clamped", "n", "c"}.
static func reach(B: Body, tip: String, raw: Vector3, surfs: Array) -> Dictionary:
	var pr := project(raw, surfs)
	if pr.is_empty():
		return {"on": false}
	var n: Vector3 = pr["n"]
	var c: Vector3 = pr["c"]
	var S: Vector3 = pr["S"]
	var g: Quaternion = (B.G[tip] as Quaternion).normalized()
	var palm_dir := (g * Body.PALM_DROP).normalized()   # the palm's outward normal now (Body.palm_point's side)
	var q := _arc(palm_dir, -n) * g                     # the palm turned to face the surface, the hand's roll kept least
	var rh := float(B.rad[tip])
	var rf := float(B.rad[B.parent[tip]])
	var d := maxf(rh, rf - LEAD)                        # the wrist's height off the face: the forearm clears it
	var u := rh - d                                     # the knuckle end's lean off the face (<= 0): palm within 3 mm
	var vf := _arc(palm_dir, -n) * ((B.E[tip] as Vector3) - (B.P[tip] as Vector3))   # the bone once the palm is turned flat
	var kv := vf.cross(n)
	var kl := kv.length()
	var qt := q
	if kl > 1e-9:
		var al := clampf((u - n.dot(vf)) / kl, -0.5, 0.5)   # the small turn that puts the bone's face-normal part at u
		qt = (Quaternion(kv / kl, al) * q).normalized()
	var pole := LimbIK.pole_from_pose(B, tip)
	var w := S + n * d
	var r := {}
	for it in 4:   # a limit that stops the wrist leaves it off its height: the wrist moves by the miss, and the solve repeats
		r = LimbIK.solve(B, tip, w, pole, qt)
		var err := n.dot((B.P[tip] as Vector3) - c) - d
		if absf(err) < 0.0002:
			break
		w -= n * err
	var inplane := ((B.P[tip] as Vector3) - S)
	inplane -= n * n.dot(inplane)   # how far the wrist is from where the mouse put it, along the face (m)
	return {"on": true, "miss": inplane.length(), "clamped": r["clamped"], "n": n, "c": c,
		"gap": palm_gap(B, tip, c, n), "tip_gap": tip_gap(B, tip, c, n), "arm_gap": arm_gap(B, tip, c, n)}
