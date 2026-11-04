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
const CAND_PAD := 0.06        # m: a (vertex, capsule) pair is tested while the vertex is this near the capsule's box
const MARGIN := 0.003         # m: half the cloth's thickness: a vertex is pushed to this far off a capsule's surface
const THICK := 0.006          # m: the cloth's thickness (2 x MARGIN): C54 self-collision keeps triangles of one cloth this far apart
const SELF_EVERY := 5         # C54: a self-collision pass after every this-many distance passes, and 6 more at the end
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


## THE BAKE, IN TWO HALVES (round 86b). sample_frames() reads the body's pins and capsules at each frame (it moves the
## body, so it runs where the body is: the main thread, on a private copy). simulate() is pure math on those arrays: it
## runs on a WorkerThreadPool task (scripts/cloth_job.gd) and reports progress and honours a cancel through ctl.
static func sample_frames(B: Body, n_frames: int, fps: int, pose_at: Callable) -> Dictionary:
	var names: Array = B.cap0.keys()
	var A: Array = []
	var C: Array = []
	for k in n_frames:
		pose_at.call(float(k) / float(fps))
		B.fk()
		A.append(anchors(B))
		C.append(caps_of(B, names))
	return {"A": A, "C": C, "names": names}


## the rest radii, in the order of the capsules of sample_frames
static func radii(B: Body, names: Array) -> PackedFloat64Array:
	var rads := PackedFloat64Array()
	for n in names:
		rads.append(float(B.rad[n]))
	return rads


## a cape baked on this thread: sample, then simulate (pose_at(t) puts the body at time t; fk is run here)
static func bake(B: Body, n_frames: int, fps: int, pose_at: Callable, name := "cape") -> Dictionary:
	var sm := sample_frames(B, n_frames, fps, pose_at)
	var out := simulate(sm["A"], sm["C"], radii(B, sm["names"]), fps, null)
	out["name"] = name
	return out


static var self_collide := false   # C54: opt-in cloth self-collision (GDScript sim only: the native door has none)
static var force_gdscript := false   # true (or KINE_NO_NATIVE=1) forces the GDScript sim below
static var _door = null
static var _door_tried := false


## true when the sim will run in C++
static func native_on() -> bool:
	return native_door() != null


## the native door, or null (no DLL, native_on false, or KINE_NO_NATIVE set)
static func native_door():
	if force_gdscript or OS.get_environment("KINE_NO_NATIVE") == "1":
		return null
	if not _door_tried:
		_door_tried = true
		if NativeExt.ensure("kine_native", "KineClothNative"):
			_door = load("res://scripts/cloth_native.gd")
	return _door


## THE SIM. Pure math on the arrays (safe on a worker thread: it touches no node and no Body). A: the pins per frame,
## C: the capsule end points per frame. ctl (a ClothJob or null): report(f) gets the fraction done, cancelled() stops it
## (returns {}). The inner loop allocates nothing per step: pins, capsules, candidate pairs and state are preallocated.
static func simulate(A: Array, C: Array, rads: PackedFloat64Array, fps: int, ctl = null) -> Dictionary:
	var n_frames := A.size()
	var N := COLS * ROWS
	var nparts := rads.size()
	var dy := LEN / float(ROWS - 1)
	var a0: PackedVector3Array = A[0]
	var x := PackedVector3Array()
	x.resize(N)
	var pinned := PackedByteArray()
	pinned.resize(N)
	for r in ROWS:
		for c in COLS:
			var i := r * COLS + c
			x[i] = a0[c] - Vector3(0.0, float(r) * dy, 0.0)
			pinned[i] = 1 if r == 0 else 0
	var v := PackedVector3Array()
	v.resize(N)
	var p := PackedVector3Array()
	p.resize(N)
	var E := topology()["edges"] as PackedInt32Array
	var ne := E.size() / 2
	var rest := PackedFloat64Array()
	rest.resize(ne)
	for k in ne:
		rest[k] = x[E[2 * k]].distance_to(x[E[2 * k + 1]])
	var nsub := maxi(1, int(round(float(SUB_HZ) / float(fps))))
	var dt := 1.0 / float(fps * nsub)
	var pre := int(round(PRE_S * float(fps)))
	var pins := PackedVector3Array()
	pins.resize(COLS)
	var capn := PackedVector3Array()
	capn.resize(2 * nparts)
	var near := PackedInt32Array()
	near.resize(nparts)
	var cand := PackedInt32Array()
	cand.resize(2 * N * nparts)   # (vertex, capsule) pairs: the worst case, allocated once
	var frames: Array = []
	var m_end := (pre + n_frames - 1) * nsub
	var total := float(m_end)
	var door = native_door()
	var sc: ClothSelf = null
	if self_collide:
		door = null
		sc = ClothSelf.new(faces(), THICK)
	if door != null:
		# the native door: the same substeps in C++ (native/src/kine_cloth_native.cpp), one call per baked frame so the
		# progress report and the cancel keep their cadence; with no ctl the whole run is one call
		var m_done := 0
		var chunk := nsub if ctl != null else m_end
		while m_done < m_end:
			var m_to := mini(m_done + chunk, m_end)
			var res: Array = door.run(x, v, A, C, rads, E, rest, pinned, nsub, pre, m_done, m_to, dt, ITER, GRAV, DRAG, MARGIN, CAND_PAD)
			x = res[0]
			v = res[1]
			frames.append_array(res[2])
			m_done = m_to
			if ctl != null:
				ctl.report(float(m_done) / total)
				if ctl.cancelled():
					return {}
		return {"fps": fps, "frames": frames}
	for m in range(1, m_end + 1):
		var u := float(m) / float(nsub) - float(pre)   # the sim clock in frames (negative = the held first pose)
		_lerp_into(A, u, pins)
		_lerp_into(C, u, capn)
		var nnear := _near(p, capn, rads, near)
		var ncand := _candidates(p, pinned, capn, rads, near, nnear, cand)
		_substep(x, v, p, pinned, E, rest, pins, capn, rads, cand, ncand, dt, sc)
		if m % nsub == 0:
			var k := m / nsub - pre
			if k >= 0:
				frames.append(x.duplicate())
			if ctl != null:
				ctl.report(float(m) / total)
				if ctl.cancelled():
					return {}
	return {"fps": fps, "frames": frames}


## the capsules that can reach the cape in this substep: those whose box overlaps the cape's box (padded)
static func _near(p: PackedVector3Array, capn: PackedVector3Array, rads: PackedFloat64Array, near: PackedInt32Array) -> int:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in p.size():
		lo = lo.min(p[i])
		hi = hi.max(p[i])
	lo -= Vector3(0.08, 0.08, 0.08)
	hi += Vector3(0.08, 0.08, 0.08)
	var n := 0
	for k in rads.size():
		var a := capn[2 * k]
		var b := capn[2 * k + 1]
		var r: float = rads[k] + MARGIN
		if (minf(a.x, b.x) - r) > hi.x or (maxf(a.x, b.x) + r) < lo.x:
			continue
		if (minf(a.y, b.y) - r) > hi.y or (maxf(a.y, b.y) + r) < lo.y:
			continue
		if (minf(a.z, b.z) - r) > hi.z or (maxf(a.z, b.z) + r) < lo.z:
			continue
		near[n] = k
		n += 1
	return n


## the (vertex, capsule) pairs that can touch in this substep: a free vertex inside a near capsule's box, padded by
## CAND_PAD (a vertex moves a few mm a substep, so the pairs are tested again on every pass)
static func _candidates(p: PackedVector3Array, pinned: PackedByteArray, capn: PackedVector3Array, rads: PackedFloat64Array,
		near: PackedInt32Array, nnear: int, cand: PackedInt32Array) -> int:
	var n := 0
	for i in p.size():
		if pinned[i] == 1:
			continue
		var q := p[i]
		for kk in nnear:
			var c := near[kk]
			var a := capn[2 * c]
			var b := capn[2 * c + 1]
			var r: float = rads[c] + MARGIN + CAND_PAD
			if q.x < minf(a.x, b.x) - r or q.x > maxf(a.x, b.x) + r:
				continue
			if q.y < minf(a.y, b.y) - r or q.y > maxf(a.y, b.y) + r:
				continue
			if q.z < minf(a.z, b.z) - r or q.z > maxf(a.z, b.z) + r:
				continue
			cand[2 * n] = i
			cand[2 * n + 1] = c
			n += 1
	return n


## one substep of the PBD solver: predict, ITER passes of (distance, collision), then the velocities
static func _substep(x: PackedVector3Array, v: PackedVector3Array, p: PackedVector3Array, pinned: PackedByteArray,
		E: PackedInt32Array, rest: PackedFloat64Array, pins: PackedVector3Array, capn: PackedVector3Array,
		rads: PackedFloat64Array, cand: PackedInt32Array, ncand: int, dt: float, sc: ClothSelf = null) -> void:
	var N := x.size()
	var drag := 1.0 - DRAG * dt
	var gdt := Vector3(0.0, -GRAV * dt, 0.0)
	for i in N:
		if pinned[i] == 1:
			p[i] = pins[i]
			v[i] = Vector3.ZERO
		else:
			v[i] = v[i] * drag + gdt
			p[i] = x[i] + v[i] * dt
	var ne := E.size() / 2
	if sc != null:
		sc.begin(p)
	for it in ITER:
		# the distance pass, inlined (this is the hot loop: ITER x edges x substeps). Each edge pulls its two ends back to
		# its rest length, split by inverse mass (a pin has none). The sweep alternates direction (a chain settles from both ends)
		for kq in ne:
			var k := kq if it % 2 == 0 else ne - 1 - kq
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
		for kc in ncand:
			var i := cand[2 * kc]
			var c := cand[2 * kc + 1]
			var ka := capn[2 * c]
			var ab := capn[2 * c + 1] - ka
			var t := clampf((p[i] - ka).dot(ab) / maxf(ab.length_squared(), 1e-12), 0.0, 1.0)
			var cp := ka + ab * t
			var dv := p[i] - cp
			var dist := dv.length()
			var rr: float = rads[c] + MARGIN
			if dist < rr:
				var nrm := dv / dist if dist > 1e-9 else Vector3.UP
				p[i] = cp + nrm * rr
		if sc != null and sc.npairs > 0 and it % SELF_EVERY == SELF_EVERY - 1:
			if sc.nat != null:   # C++ returns the moved positions: rebind (p is this substep's own buffer)
				p = sc.nat.solve(p, pinned, it == SELF_EVERY - 1 or it == 3 * SELF_EVERY - 1)
			else:
				sc.solve(p, pinned, it == SELF_EVERY - 1 or it == 3 * SELF_EVERY - 1)
	if sc != null and sc.npairs > 0:
		for k in 6:
			if sc.nat != null:
				p = sc.nat.solve(p, pinned, false)
			else:
				sc.solve(p, pinned)
	for i in N:
		if pinned[i] == 0:
			v[i] = (p[i] - x[i]) / dt
		x[i] = p[i]


## the body's frame data at the sim clock u (frames), written into out: linear between the two frames either side
static func _lerp_into(F: Array, u: float, out: PackedVector3Array) -> void:
	var f := clampf(u, 0.0, float(F.size() - 1))
	var i0 := int(floor(f))
	var i1 := mini(i0 + 1, F.size() - 1)
	var a := f - float(i0)
	var A: PackedVector3Array = F[i0]
	if a <= 0.0 or i1 == i0:
		for k in out.size():
			out[k] = A[k]
		return
	var B: PackedVector3Array = F[i1]
	for k in out.size():
		out[k] = A[k].lerp(B[k], a)


## BAKE THE SCENE on this thread (the tests and any caller off the UI; the app bakes through ClothJob)
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
