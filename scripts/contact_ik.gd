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


## put the hand's wrist on the nearest face of `surfs` for the raw wrist target `raw`: the palm turned to the face, the
## wrist one hand radius off it (less the 60 % point's lean, so the palm itself lands on the face), the limb solved to it
## with its elbow kept on the side it bends now (LimbIK.pole_from_pose). Returns {"on": false} with no surface, else
## {"on", "miss" (tip to the wrist target, m), "gap" (palm gap after the solve, m), "tip_gap", "clamped", "n", "c"}.
static func reach(B: Body, tip: String, raw: Vector3, surfs: Array) -> Dictionary:
	var pr := project(raw, surfs)
	if pr.is_empty():
		return {"on": false}
	var n: Vector3 = pr["n"]
	var c: Vector3 = pr["c"]
	var g: Quaternion = (B.G[tip] as Quaternion).normalized()
	var palm_dir := (g * Body.PALM_DROP).normalized()   # the palm's outward normal now (Body.palm_point's side)
	var q := _arc(palm_dir, -n) * g                     # the palm turned to face the surface, the hand's roll kept least
	var bone: Vector3 = (B.E[tip] as Vector3) - (B.P[tip] as Vector3)
	var lean := 0.6 * n.dot(_arc(palm_dir, -n) * bone)   # the 60 % point's height above the wrist once the hand is turned
	var wrist: Vector3 = (pr["S"] as Vector3) + n * (float(B.rad[tip]) - lean)
	var pole := LimbIK.pole_from_pose(B, tip)
	var w := (pr["S"] as Vector3) + n * (float(B.rad[tip]) - lean)
	var r := {}
	for it in 4:   # a wrist that stops at its limit cannot turn the palm all the way: the wrist moves by the palm's gap
		r = LimbIK.solve(B, tip, w, pole, q)
		var gap := palm_gap(B, tip, c, n)
		if absf(gap) < 0.0002:
			break
		w -= n * gap
	var inplane := ((B.P[tip] as Vector3) - (pr["S"] as Vector3))
	inplane -= n * n.dot(inplane)   # how far the wrist is from where the mouse put it, along the face (m)
	return {"on": true, "miss": inplane.length(), "clamped": r["clamped"], "n": n, "c": c,
		"gap": palm_gap(B, tip, c, n), "tip_gap": tip_gap(B, tip, c, n)}
