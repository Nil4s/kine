## cloth.gd - ROADMAP 86: a CAPE on the back, a position-based-dynamics cloth grid baked per frame (no drawing, no input).
##
## THE GRID: COLS x ROWS = 12 x 16 vertices. The TOP ROW is pinned to the shoulders: each pin is a fixed point in the
## spine_03 frame (x across from -HALF_W to +HALF_W at the shoulder height TOP_Y, on the back at z = BACK_Z, rest frame of
## spine_03). The cape hangs from those pins; the rest of the grid starts straight down from them, LEN metres long.
## Rest body numbers (data/skeleton.json, probed round 86): shoulder joints (upperarm_l/r) sit at x = +-0.19 m, y 1.44 m;
## the spine_03 capsule is 0.144 m radius at z -0.018 (its back surface is at z -0.162); the pelvis joint is at y 0.917 m.
## The pins sit at z -0.17: 8 mm behind the upper back and 4 cm clear of both upper-arm capsules (the arm capsules are
## 0.076 m radius). A pin inside a body capsule would never be pushed out (pins do not move), so the pin row is kept clear.
##
## THE SIM (position-based dynamics, Muller et al. 2007, the standard Verlet-style PBD solver):
##   each substep: free vertices take gravity and a drag (v *= 1 - DRAG dt), then predict p = x + v dt;
##   ITER passes over the constraints: the structural (row and column) distance constraints, each
##   pulling its two ends back to its rest length in proportion to their inverse masses (a pin has inverse mass 0);
##   after each distance pass every free vertex is pushed out of each body capsule (Body.cap, radius + MARGIN);
##   then v = (p - x) / dt, x = p. One fixed step: the sim never reads the frame rate except to set the substep count.
## Shear (diagonal) constraints exist (SHEAR) but are off: with them the grid is over-stiffened and the 30 passes stretch the
## rows more under a fast turn (measured at 10 passes: 16 % stretch with shear, 9 % without; round 86).
## Substeps: nsub = round(SUB_HZ / fps) per frame, so the frame times are exact and the sim is deterministic (same
## floats in the same order: two bakes of the same pose path are byte-identical; test 4).
##
## THE BAKE: the body is put at each frame's pose (a Callable, or the scene's S.apply), its pins and every capsule's end
## points are read at each frame, and the sim runs between them (linear interpolation between frames: the body is baked,
## so a substep sees the body where the frame says it is). PRE_S seconds of the first pose before frame 0 let the cape
## settle onto its pins, so frame 0 is a hanging cape (not one still falling).
## THE OUTPUT (cape dict): {"name", "fps", "frames": [PackedVector3Array per frame: the 192 vertex positions in world
## metres, index r * COLS + c, row 0 = the top row]}. It is replayed by frame (verts_at), never re-simulated on scrub.
##
## EXPORT: the cape as its own mesh with PER-FRAME VERTEX POSITIONS (a morph sequence, not bones: the cloth has no
## joints): export_dict() gives the faces (two triangles per grid cell), the rest vertices and every frame's vertices.
## save_json() writes it under user:// only.
##
## WHAT IS NOT MODELLED: the arms do not pull the cape (the pins ride spine_03 only, not the clavicles); the cape has
## no self-collision; the weapons (bat, second weapon) are not collided with; no wind; the cloth is one thickness (the
## MARGIN is the half-thickness).
class_name Cloth
extends RefCounted

const COLS := 12
const ROWS := 16
const HALF_W := 0.15          # half the top row's width (m): the pins at x = +-0.15
const TOP_Y := 1.44           # the shoulder height (m, rest): the top row
const BACK_Z := -0.17         # the top row on the back (m, spine_03 rest frame's z)
const LEN := 0.90             # from the top row to the lowest row (m): it ends at y 0.54, below the pelvis (0.917)
const SUB_HZ := 120           # substeps a second (the cape is stiff enough at 4 a frame for walk and turn: test 2/3)
const SHEAR := false          # shear (diagonal) constraints: off (they over-stiffen the grid; the solver then stretches the rows)
const ITER := 30              # distance + collision passes per substep
const GRAV := 9.81
const DRAG := 0.6             # 1/s: the velocity loss that stops the cape ringing forever
const MARGIN := 0.003         # m: half the cloth's thickness: a vertex is pushed to this far off a capsule's surface
const PRE_S := 1.0            # s: the first pose held before frame 0 so the cape settles onto its pins


## the pins now: the top row's COLS points, in world metres, from spine_03's frame
static func anchors(B: Body) -> PackedVector3Array:
	var out := PackedVector3Array()
	var j := "spine_03"
	var p0v: Vector3 = B.p0[j]
	for c in COLS:
		var x := lerpf(-HALF_W, HALF_W, float(c) / float(COLS - 1))
		var local := Vector3(x, TOP_Y, BACK_Z) - p0v
		out.append((B.P[j] as Vector3) + (B.G[j] as Quaternion) * local)
	return out


## every body capsule's two end points now (2 per part, in the order of names), world metres
static func caps_of(B: Body, names: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for n in names:
		var c: Array = B.cap(n)
		out.append(c[0])
		out.append(c[1])
	return out


## the grid's edges: [i, j, kind] with kind 0 = structural (row or column), 1 = shear (diagonal). Flat PackedInt32Array
## of (i, j) pairs; the first n_struct pairs are the structural ones
static func topology() -> Dictionary:
	var e := PackedInt32Array()
	var n_struct := 0
	for r in ROWS:
		for c in COLS:
			var i := r * COLS + c
			if c + 1 < COLS:
				e.append(i)
				e.append(i + 1)
			if r + 1 < ROWS:
				e.append(i)
				e.append(i + COLS)
	n_struct = e.size() / 2
	if SHEAR:
		for r in ROWS - 1:
			for c in COLS - 1:
				var i := r * COLS + c
				e.append(i)
				e.append(i + COLS + 1)
				e.append(i + 1)
				e.append(i + COLS)
	return {"edges": e, "n_struct": n_struct}


## the triangles of the grid (two per cell), for the mesh export and the view
static func faces() -> PackedInt32Array:
	var f := PackedInt32Array()
	for r in ROWS - 1:
		for c in COLS - 1:
			var i := r * COLS + c
			f.append_array(PackedInt32Array([i, i + COLS, i + 1, i + 1, i + COLS, i + COLS + 1]))
	return f


## a cape: the simulated grid baked over n_frames of the pose (pose_at(t) puts the body at time t and runs its fk)
static func bake(B: Body, n_frames: int, fps: int, pose_at: Callable, name := "cape") -> Dictionary:
	var names: Array = B.cap0.keys()
	var rads := PackedFloat64Array()
	for n in names:
		rads.append(float(B.rad[n]))
	var A: Array = []
	var C: Array = []
	for k in n_frames:
		pose_at.call(float(k) / float(fps))
		B.fk()
		A.append(anchors(B))
		C.append(caps_of(B, names))
	var N := COLS * ROWS
	var dy := LEN / float(ROWS - 1)
	var x := PackedVector3Array()
	x.resize(N)
	var pinned := PackedByteArray()
	pinned.resize(N)
	for r in ROWS:
		for c in COLS:
			var i := r * COLS + c
			x[i] = (A[0] as PackedVector3Array)[c] - Vector3(0.0, float(r) * dy, 0.0)
			pinned[i] = 1 if r == 0 else 0
	var v := PackedVector3Array()
	v.resize(N)
	var topo := topology()
	var E: PackedInt32Array = topo["edges"]
	var rest := PackedFloat64Array()
	rest.resize(E.size() / 2)
	for k in rest.size():
		rest[k] = x[E[2 * k]].distance_to(x[E[2 * k + 1]])
	var nsub := maxi(1, int(round(float(SUB_HZ) / float(fps))))
	var dt := 1.0 / float(fps * nsub)
	var pre := int(round(PRE_S * float(fps)))
	var frames: Array = []
	var m_end := (pre + n_frames - 1) * nsub
	var p := PackedVector3Array()
	p.resize(N)
	for m in range(1, m_end + 1):
		var u := float(m) / float(nsub) - float(pre)   # the sim clock in frames (negative = the held first pose)
		var pins := _lerp_frame(A, u)
		var capn := _lerp_frame(C, u)
		_substep(x, v, p, pinned, E, rest, pins, capn, rads, dt)
		if m % nsub == 0:
			var k := m / nsub - pre
			if k >= 0:
				frames.append(x.duplicate())
	return {"name": name, "fps": fps, "frames": frames}


## one substep of the PBD solver (x, v, p are the cape's state; pins and capn the body now)
static func _substep(x: PackedVector3Array, v: PackedVector3Array, p: PackedVector3Array, pinned: PackedByteArray,
		E: PackedInt32Array, rest: PackedFloat64Array, pins: PackedVector3Array, capn: PackedVector3Array,
		rads: PackedFloat64Array, dt: float) -> void:
	var N := x.size()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in N:
		if pinned[i] == 1:
			p[i] = pins[i]
			v[i] = Vector3.ZERO
		else:
			v[i] = v[i] * (1.0 - DRAG * dt) + Vector3(0.0, -GRAV * dt, 0.0)
			p[i] = x[i] + v[i] * dt
		lo = lo.min(p[i])
		hi = hi.max(p[i])
	# the capsules that can reach the cape this substep (the rest are skipped: most of the body is far from a cape)
	var near := []
	var pad := 0.08
	for k in rads.size():
		var a := capn[2 * k]
		var b := capn[2 * k + 1]
		var r := rads[k] + MARGIN
		var clo := a.min(b) - Vector3(r, r, r)
		var chi := a.max(b) + Vector3(r, r, r)
		if chi.x < lo.x - pad or clo.x > hi.x + pad or chi.y < lo.y - pad or clo.y > hi.y + pad or chi.z < lo.z - pad or clo.z > hi.z + pad:
			continue
		near.append(k)
	var ne := E.size() / 2
	for it in ITER:
		for kq in ne:
			var k := kq if it % 2 == 0 else ne - 1 - kq   # the sweep alternates direction: a chain settles from both ends
			var i := E[2 * k]
			var j := E[2 * k + 1]
			var wi := 0.0 if pinned[i] == 1 else 1.0
			var wj := 0.0 if pinned[j] == 1 else 1.0
			var ws := wi + wj
			if ws <= 0.0:
				continue
			var d := p[j] - p[i]
			var L := d.length()
			if L < 1e-12:
				continue
			var corr := d * ((L - rest[k]) / L)
			p[i] += corr * (wi / ws)
			p[j] -= corr * (wj / ws)
		for i in N:
			if pinned[i] == 1:
				continue
			var q := p[i]
			for kk in near:
				var ka: Vector3 = capn[2 * kk]
				var kb: Vector3 = capn[2 * kk + 1]
				var ab := kb - ka
				var t := clampf((q - ka).dot(ab) / maxf(ab.length_squared(), 1e-12), 0.0, 1.0)
				var c := ka + ab * t
				var dv := q - c
				var dist := dv.length()
				var rr: float = rads[kk] + MARGIN
				if dist < rr:
					var nrm := dv / dist if dist > 1e-9 else Vector3.UP
					q = c + nrm * rr
			p[i] = q
	for i in N:
		if pinned[i] == 0:
			v[i] = (p[i] - x[i]) / dt
		x[i] = p[i]


## the body's frame data at the sim clock u (frames): linear between the two frames either side, the first / last held
static func _lerp_frame(F: Array, u: float) -> PackedVector3Array:
	var f := clampf(u, 0.0, float(F.size() - 1))
	var i0 := int(floor(f))
	var i1 := mini(i0 + 1, F.size() - 1)
	var a := f - float(i0)
	var A: PackedVector3Array = F[i0]
	if a <= 0.0 or i1 == i0:
		return A
	var B: PackedVector3Array = F[i1]
	var out := PackedVector3Array()
	out.resize(A.size())
	for k in A.size():
		out[k] = A[k].lerp(B[k], a)
	return out


## BAKE THE SCENE: the cape over the scene's frames (S.apply puts the body at each time, the body is put back after)
static func bake_scene(S: Scene, B: Body, n_frames := -1) -> Dictionary:
	var keep := B.state()
	var fps := S.fps
	var nf := n_frames
	if nf < 0:
		nf = maxi(int(ceil(S.length() * float(fps) - 1e-6)), 1) + 1
	var cape := bake(B, nf, fps, func(t: float) -> void: S.apply(B, minf(t, S.length())))
	B.set_state(keep)
	B.fk()
	return cape


## the vertices (world metres) at time t: the nearest baked frame (scrubbing replays frames, it never re-simulates)
static func verts_at(cape: Dictionary, t: float) -> PackedVector3Array:
	var fr: Array = cape.get("frames", [])
	if fr.is_empty():
		return PackedVector3Array()
	var k := clampi(roundi(t * float(int(cape["fps"]))), 0, fr.size() - 1)
	return fr[k]


## THE TIP'S LAG (deg): the swing of the tip from straight down, about the top row's middle. A cape hangs along gravity, so
## the lag behind a turn shows as its swing: the tip stays where the body was and the cape swings out (the angle grows),
## then comes back under gravity and damping. 0 = hanging straight; the direction of the swing (which side) is in the
## vertices (test 6 reads the cape in the pelvis frame).
static func tip_lag_deg(verts: PackedVector3Array) -> float:
	var tip := verts[(ROWS - 1) * COLS + COLS / 2]
	var top := (verts[COLS / 2 - 1] + verts[COLS / 2]) * 0.5
	var d := tip - top
	if d.length() < 1e-9:
		return 0.0
	return rad_to_deg(acos(clampf(d.normalized().dot(Vector3.DOWN), -1.0, 1.0)))


## the mesh for export: per-frame vertex positions, the faces, the rest vertices (rest = frame 0)
static func export_dict(cape: Dictionary) -> Dictionary:
	var fr: Array = cape.get("frames", [])
	var frames := []
	for f in fr:
		var pa := []
		for p in f:
			pa.append([snappedf(p.x, 1e-6), snappedf(p.y, 1e-6), snappedf(p.z, 1e-6)])
		frames.append(pa)
	return {"format": "cloth-vertex-frames", "name": String(cape.get("name", "cape")), "fps": int(cape.get("fps", 30)),
		"cols": COLS, "rows": ROWS, "faces": Array(faces()), "frames": frames}


## writes the export under user:// only. Returns the path ("" on failure)
static func save_json(cape: Dictionary, file_name: String) -> String:
	var path := "user://" + file_name
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa == null:
		return ""
	fa.store_string(JSON.stringify(export_dict(cape)))
	fa.close()
	return path


## THE SCENE FILE: the frames as flat lists of numbers (metres), rounded to 1e-6 m
static func to_file(cape: Dictionary) -> Dictionary:
	var frames := []
	for f in cape.get("frames", []):
		var flat := []
		for p in f:
			flat.append_array([snappedf(p.x, 1e-6), snappedf(p.y, 1e-6), snappedf(p.z, 1e-6)])
		frames.append(flat)
	return {"name": String(cape.get("name", "cape")), "fps": int(cape.get("fps", 30)), "frames": frames}


static func from_file(d: Variant) -> Dictionary:
	if not (d is Dictionary) or (d as Dictionary).is_empty():
		return {}
	var frames := []
	for flat in (d as Dictionary).get("frames", []):
		var f := PackedVector3Array()
		var a: Array = flat
		for k in range(0, a.size() - 2, 3):
			f.append(Vector3(float(a[k]), float(a[k + 1]), float(a[k + 2])))
		frames.append(f)
	if frames.is_empty():
		return {}
	return {"name": String((d as Dictionary).get("name", "cape")), "fps": int((d as Dictionary).get("fps", 30)), "frames": frames}
