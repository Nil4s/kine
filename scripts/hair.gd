## hair.gd - ROADMAP 87: HAIR STRANDS, a ponytail of verlet strands rooted on the back of the head. Pure statics: no node.
##
## A PONYTAIL is K strands (6-12) rooted on a small ring on the back of the head, each a chain of N segments (8-12).
## The roots are read off the head MESH (the back-most surface along the ray from behind, Face.anchors' scale), kept in
## the head's rest frame, so they ride on the skull: a root is the head's rigid transform applied to a fixed point.
##
## THE SIM (position-based verlet, fixed step): SUB_HZ = 240 substeps a second, the same grid for every frame rate
## (the frames are sampled by linear / slerp interpolation between the scene's samples). Each substep, per strand:
##   1. the root (node 0) is pinned to the head: x0 = P + G * root_local (kinematic, no velocity of its own);
##   2. verlet: v = (x - x_prev) * (1 - DAMP dt); x += v + g dt^2   (gravity is the world's; damping is viscous, per second);
##   3. stiffness near the root: each node moves a fraction STIFF dt (1 - i/(N)) toward its rest chain on the head
##      (the chain straight down-and-back in the head's frame), so the first segments stay with the head and the tip is free;
##   4. length: ITERS passes of the segment constraint (the root is not moved, the free node takes the whole correction);
##   5. collision: every node (not the root) is pushed out of each body capsule to radius + RADIUS (head, neck, spine,
##      clavicles, upper arms, chest). Last, so the stored positions are never inside a capsule.
##
## Constants are ours, labelled: DAMP 6 /s (the pendulum's amplitude then decays as exp(-3 t): a 2 % settle in ~1.3 s),
## STIFF 12 /s at the root, RADIUS 4 mm (a hair bundle's half-thickness), a 0.30 m ponytail of 10 segments of 3 cm.
## Gravity is 9.81 m/s^2 (the world's). A ponytail in a tie is not measured here; these numbers are for the test bars.
class_name Hair
extends RefCounted

const SUB_HZ := 240
const GRAV := Vector3(0.0, -9.81, 0.0)
const RADIUS := 0.004
const DAMP := 6.0
const STIFF := 12.0
const ITERS := 24
const ITERS_AFTER := 4
const WARM := 1.5   # s: the strands settle in the first pose before the scene's frame 0 (deterministic)
## the body capsules the strands collide with (Body.cap / Body.rad part names)
const CAPS := ["head", "neck_01", "spine_01", "spine_02", "spine_03", "chest_wide", "clavicle_l", "clavicle_r", "upperarm_l", "upperarm_r"]
const PRESETS := {
	"ponytail": {"name": "ponytail", "strands": 12, "n": 10, "seg": 0.03, "spread": 0.014, "tie": 0.25, "rest": [0.0, -1.0, -0.5]},
}


## a copy of a preset
static func preset(key: String) -> Dictionary:
	return (PRESETS[key] as Dictionary).duplicate(true)


## the hair block of a scene file: the parameters only (the sim is deterministic, so the frames are baked again on load)
static func to_file(h: Dictionary) -> Dictionary:
	return h.duplicate(true)


## read a file's hair block: a block without the core numbers is dropped; the rest falls back to the preset
static func from_file(d: Variant) -> Dictionary:
	if not (d is Dictionary):
		return {}
	var dd := d as Dictionary
	if not dd.has("name") or not dd.has("n") or not dd.has("strands"):
		return {}
	var out := preset(String(dd["name"])) if PRESETS.has(String(dd["name"])) else preset("ponytail")
	for k in dd.keys():
		out[k] = dd[k]
	out["n"] = clampi(int(out["n"]), 8, 12)
	out["strands"] = clampi(int(out["strands"]), 6, 12)
	return out


## the back-most surface of the head mesh along z at (x, y): the smallest z of the ray from behind (-z is the back;
## +z is the hero's front, face.gd). INF if the ray misses. pts = triangle corners, three per triangle, rest space.
static func back_z(pts: PackedVector3Array, x: float, y: float) -> float:
	var best := INF
	for t in range(0, pts.size() - 2, 3):
		var h: Variant = Geometry3D.ray_intersects_triangle(Vector3(x, y, -1.0), Vector3(0, 0, 1), pts[t], pts[t + 1], pts[t + 2])
		if h != null:
			best = minf(best, (h as Vector3).z)
	return best


## the strand roots in the HEAD's frame (rest space minus the head joint p0, as Scene/main's face_at uses): a ring of
## `strands` points of radius spread about the tie point, which sits tie x H below the top of the head (the back of the
## skull above the occiput; Farkas 1994 puts the top of the head at the vertex). A ring point the ray misses is skipped.
static func roots(pts: PackedVector3Array, p: Dictionary, p0: Vector3) -> Array:
	var a := Face.anchors(pts)
	if a.is_empty():
		return []
	var top := float(a["top"])
	var H := float(a["H"])
	var ty := top - float(p["tie"]) * H
	var out := []
	var K := int(p["strands"])
	for s in K:
		var ang := TAU * float(s) / float(K)
		var x := float(p["spread"]) * cos(ang)
		var y := ty + float(p["spread"]) * sin(ang)
		var z := back_z(pts, x, y)
		if z == INF:
			continue
		out.append(Vector3(x, y, z) - p0)
	return out


## the head and capsules at time t, interpolated between the scene's samples: [origin, quat, [[a, b, r] per capsule]]
static func _pose(head: Array, caps: Array, t: float, fps: float) -> Array:
	var last := head.size() - 1
	var f := clampf(t * fps, 0.0, float(last))
	var i0 := int(floor(f))
	var i1 := mini(i0 + 1, last)
	var a := f - float(i0)
	var o: Vector3 = (head[i0][0] as Vector3).lerp(head[i1][0] as Vector3, a)
	var q: Quaternion = (head[i0][1] as Quaternion).slerp(head[i1][1] as Quaternion, a)
	var cs := []
	var c0: Array = caps[i0]
	var c1: Array = caps[i1]
	for c in c0.size():
		cs.append([(c0[c][0] as Vector3).lerp(c1[c][0] as Vector3, a), (c0[c][1] as Vector3).lerp(c1[c][1] as Vector3, a),
			lerpf(float(c0[c][2]), float(c1[c][2]), a)])
	return [o, q, cs]


## THE SIM. roots = the strands' root points in the head frame (roots()); p = the preset; fps = the scene's frame rate;
## head[k] = [origin, quat] of the head at frame k (world); caps[k] = the body capsules [a, b, r] at frame k (world).
## Returns one entry per frame (k = 0 .. head.size() - 1): a flat PackedVector3Array, strand s node i at s * (n + 1) + i.
## The sim starts WARM seconds before frame 0, in the pose of frame 0, so the first frame is a settled state.
static func sim(roots_local: Array, p: Dictionary, fps: float, head: Array, caps: Array) -> Array:
	var n := int(p["n"])
	var N := n + 1
	var seg := float(p["seg"])
	var rd := Vector3(float(p["rest"][0]), float(p["rest"][1]), float(p["rest"][2])).normalized()
	var K := roots_local.size()
	var rest := PackedVector3Array()   # head-local rest chain, flat
	rest.resize(K * N)
	for s in K:
		var r: Vector3 = roots_local[s]
		for i in N:
			rest[s * N + i] = r + rd * (seg * float(i))
	var X := PackedVector3Array()
	var XP := PackedVector3Array()
	X.resize(K * N)
	XP.resize(K * N)
	var pz := _pose(head, caps, -WARM, fps)
	var o: Vector3 = pz[0]
	var q: Quaternion = pz[1]
	for s in K:
		for i in N:
			X[s * N + i] = o + q * rest[s * N + i]
			XP[s * N + i] = X[s * N + i]
	var dt := 1.0 / float(SUB_HZ)
	var nf := head.size()
	var total := int(round((WARM + float(nf - 1) / fps) * float(SUB_HZ)))
	var out := []
	var k := 0
	for step in range(total):
		var t := float(step) / float(SUB_HZ) - WARM
		while k < nf and t >= float(k) / fps - 1e-9:
			out.append(X.duplicate())
			k += 1
		pz = _pose(head, caps, t + dt, fps)
		o = pz[0]
		q = pz[1]
		var cs: Array = pz[2]
		for s in K:
			var b := s * N
			X[b] = o + q * rest[b]   # the root rides on the head
			XP[b] = X[b]
			for i in range(1, N):
				var j := b + i
				var v := (X[j] - XP[j]) * (1.0 - DAMP * dt)
				XP[j] = X[j]
				X[j] = X[j] + v + GRAV * (dt * dt)
				X[j] = X[j].lerp(o + q * rest[j], minf(STIFF * dt * (1.0 - float(i) / float(N)), 1.0))
			for _it in ITERS:
				for i in range(1, N):
					var j := b + i
					var d := X[j] - X[j - 1]
					var L := d.length()
					if L < 1e-12:
						continue
					var c := d * ((L - seg) / L)
					if i == 1:
						X[j] -= c   # the root is pinned: the first free node takes the whole correction
					else:
						X[j - 1] += c * 0.5
						X[j] -= c * 0.5
			for i in range(1, N):
				var j := b + i
				for c in cs:
					var ca: Vector3 = c[0]
					var cb: Vector3 = c[1]
					var ab := cb - ca
					var ll := ab.length_squared()
					var u := 0.0 if ll < 1e-12 else clampf((X[j] - ca).dot(ab) / ll, 0.0, 1.0)
					var cp := ca + ab * u
					var dv := X[j] - cp
					var dist := dv.length()
					var minr := float(c[2]) + RADIUS
					if dist < minr:
						var nrm := dv / dist if dist > 1e-9 else Vector3(0, 0, 1)
						X[j] = cp + nrm * minr
			for _it in ITERS_AFTER:   # the push-out stretches a segment by ~1 mm: the lengths again (the margin is RADIUS)
				for i in range(1, N):
					var j := b + i
					var d := X[j] - X[j - 1]
					var L := d.length()
					if L < 1e-12:
						continue
					var c := d * ((L - seg) / L)
					if i == 1:
						X[j] -= c
					else:
						X[j - 1] += c * 0.5
						X[j] -= c * 0.5
	while k < nf:
		out.append(X.duplicate())
		k += 1
	return out


## the node points of frame t (seconds), linear between the baked frames: a flat array as sim() returns per frame
static func at(frames: Array, t: float, fps: float) -> PackedVector3Array:
	var last := frames.size() - 1
	var f := clampf(t * fps, 0.0, float(last))
	var i0 := int(floor(f))
	var i1 := mini(i0 + 1, last)
	var a := f - float(i0)
	var A: PackedVector3Array = frames[i0]
	var B: PackedVector3Array = frames[i1]
	var out := PackedVector3Array()
	out.resize(A.size())
	for j in A.size():
		out[j] = A[j].lerp(B[j], a)
	return out
