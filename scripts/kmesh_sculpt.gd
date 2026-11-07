class_name KMeshSculpt
extends RefCounted
## Sculpt core (ROADMAP_400 C01 + C02): a brush stroke is a run of DABS along the surface; each dab moves the verts within
## `radius` of the hit point by the brush's rule, weighted by a falloff of the distance and by the pen pressure.
## Pure: no nodes, no viewport. A stroke is begin(mesh, params) ... to(point, normal, pressure) ... end(); the caller
## brackets it with KMeshUndo.begin / commit so one stroke is one undo step (KMeshUndo keeps just the verts that moved).
##   params: {"brush", "radius" (m), "strength" (m per dab at full pressure, the centre), "falloff", "spacing" (fraction of
##            the radius between dabs, Blender's 10 % default), "invert" (draw / inflate / clay / crease push in), "sym_x"}
##   BRUSHES   draw: along the stroke normal by strength * falloff   inflate: along each vert's own normal
##             smooth: toward the mean of the neighbours   flatten: toward the area plane   pinch: toward the brush axis
##             clay strips: up to a plane `strength` above the area   crease: draw inward + pinch   grab: the verts under
##             the press follow the drag (delta * falloff)   snake hook: grab that picks up the verts under each new dab
##   Blend brushes (smooth, flatten, pinch, clay) move a vert at most strength * falloff * pressure toward the target,
##   never past it, so every brush's strength is the same unit (metres per dab).
##   FALLOFF of t = d / radius (1 at the centre, 0 at the rim): smooth 1 - (3t^2 - 2t^3), sphere sqrt(1 - t^2),
##   sharp (1 - t)^2, linear 1 - t.
##   SPATIAL HASH: built once per stroke (cells of one radius); a dab reads the 3 x 3 x 3 cells around the hit (the verts
##   moved during the stroke are found while they stay within a cell of where they began) and tests the true distance.
##   X SYMMETRY: KMesh.symmetry_map(0): each vert's displacement is also applied, mirrored, to its partner; a vert on the
##   plane keeps x. B22: params "sym_map" (a partner per vert, KMeshTopoMirror: by connectivity) + "sym_axis" replace it.
##   MASK (C03, scripts/kmesh_mask.gd): the "mask" brush paints the mesh's 0..1 "mask" channel instead of moving verts
##   (invert = erase; params "mask_amount", 1 = a full mask at the centre in one dab); every other brush's displacement of
##   a vert (and grab's) is multiplied by (1 - mask), the mask as it was when the stroke began.
##   FACE SETS (C09, scripts/kmesh_face_sets.gd): the "face set" brush puts the faces under each dab in set p["fset_id"]
##   (a new set when not given) and moves nothing; every brush leaves frozen the verts of hidden faces and, with
##   p["only_set"] > 0, the verts of every face of another set (KMeshFaceSets.frozen, read when the stroke begins).
##   ALPHAS + STROKE METHODS (C08, scripts/sculpt_alpha_stroke.gd): params "alpha", "stroke_method" (dots / drag rect /
##   spray), "alpha_rot" ...: each dab's falloff is multiplied by the alpha in the dab's tangent frame. Off (null) by default.
##   NATIVE (native/, KineSculptNative): when ClassDB.class_exists("KineSculptNative") the spatial hash, a dab's displacements,
##   _apply and _renormal run in C++ (scripts/kmesh_sculpt_native.gd is the one door). Same results to ~1e-6; no DLL = the
##   GDScript below, unchanged. KMeshSculpt.native_on = false forces the GDScript path (tests/sculptnative_test.gd).

const DRAW := "draw"
const CLAY := "clay strips"
const INFLATE := "inflate"
const SMOOTH := "smooth"
const FLATTEN := "flatten"
const PINCH := "pinch"
const CREASE := "crease"
const GRAB := "grab"
const SNAKE := "snake hook"
const BRUSHES := [DRAW, CLAY, INFLATE, SMOOTH, FLATTEN, PINCH, CREASE, GRAB, SNAKE]
const MASK := "mask"   # C03: paints the mask, moves nothing
const FSET := "face set"   # C09: paints face sets, moves nothing

const F_SMOOTH := "smooth"
const F_SPHERE := "sphere"
const F_SHARP := "sharp"
const F_LINEAR := "linear"
const FALLOFFS := [F_SMOOTH, F_SPHERE, F_SHARP, F_LINEAR]

const DEFAULTS := {"brush": DRAW, "radius": 0.1, "strength": 0.005, "falloff": F_SMOOTH, "spacing": 0.1, "invert": false, "sym_x": false}

var mesh: KMesh
var p := {}
var dabs := 0              # dabs laid in this stroke
var dyn_splits := 0        # L52: edges split / collapsed by dynamic topology in this stroke
var dyn_collapses := 0
var _cell := 0.1
var _head := {}            # Vector3i -> first vert
var _chain := PackedInt32Array()
var _sym := PackedInt32Array()
var _sax := 0              # B22: the mirror axis of _sym (0 X, 1 Y, 2 Z)
var _last := Vector3.ZERO  # the last dab's centre (spacing, snake hook)
var _has_last := false
var _prev := Vector3.ZERO  # the last stroke point (spacing)
var _carry := 0.0          # the path laid since the last dab
var _grab0 := Vector3.ZERO # grab: the press point
var _grab_w := {}          # grab: vert -> weight at the press
var _grab_v := {}          # grab: vert -> position at the press
var _mask := PackedFloat32Array()   # C03: the mask at the stroke's start (empty = none)
var _lock := PackedByteArray()      # C09: 1 = a vert of a hidden face / another set (empty = none)
var _symx: KMeshSculptSym  # C07: Y / Z / radial symmetry (scripts/kmesh_sculpt_sym.gd), null when off
var _pend = null           # C07: while an Array, _apply holds the deltas back for the copies of one dab
var _alpha: SculptAlphaStroke   # C08: the alpha / stroke method of this stroke, null when plain
var _nb = null             # the native door (scripts/kmesh_sculpt_native.gd) for this stroke, null = GDScript path
var _nctx := {}            # the native topology + hash of this stroke

static var native_on := true
static var _door = null
static var _door_tried := false


## the native door, or null (no DLL, or native_on is false)
static func native_door():
	if not native_on:
		return null
	if not _door_tried:
		_door_tried = true
		if NativeExt.ensure("kine_native", "KineSculptNative"):
			_door = load("res://scripts/kmesh_sculpt_native.gd")
	return _door


static func falloff(kind: String, t: float) -> float:
	if t >= 1.0:
		return 0.0
	t = maxf(t, 0.0)
	match kind:
		F_SPHERE:
			return sqrt(1.0 - t * t)
		F_SHARP:
			return (1.0 - t) * (1.0 - t)
		F_LINEAR:
			return 1.0 - t
	return 1.0 - t * t * (3.0 - 2.0 * t)


## the pen pressure of a motion event: a mouse reports 0 (no tablet), which counts as full pressure
static func pressure_of(ev: InputEvent) -> float:
	if ev is InputEventMouseMotion:
		var pr := (ev as InputEventMouseMotion).pressure
		return pr if pr > 0.0 else 1.0
	return 1.0


func begin(m: KMesh, params := {}) -> void:
	mesh = m
	p = DEFAULTS.duplicate()
	p.merge(params, true)
	dabs = 0
	dyn_splits = 0
	dyn_collapses = 0
	_has_last = false
	_grab_w = {}
	_grab_v = {}
	_cell = maxf(float(p["radius"]), 1e-4)
	_nb = native_door()
	if _nb != null:
		_nctx = _nb.make_ctx(m.verts, m.faces, _cell)
	else:
		_build_hash()
	_sym = m.symmetry_map(0, 1e-4) if p["sym_x"] else PackedInt32Array()
	_sax = int(p.get("sym_axis", 0))   # B22: a partner map of any axis (KMeshTopoMirror: by connectivity) replaces it
	if p["sym_x"] and p.get("sym_map") is PackedInt32Array and (p["sym_map"] as PackedInt32Array).size() == m.verts.size():
		_sym = p["sym_map"]
	_mask = KMeshMask.values(m)
	_lock = KMeshFaceSets.frozen(m, int(p.get("only_set", 0)))
	if p["brush"] == FSET and int(p.get("fset_id", 0)) <= 0:
		p["fset_id"] = KMeshFaceSets.next_id(m)
	_symx = KMeshSculptSym.make(self)
	_alpha = SculptAlphaStroke.make(self)


## L52 dynamic topology: split / collapse edges under this dab (scripts/kmesh_dyntopo.gd), then the stroke's hash, mirror map and
## normals are rebuilt. Vert and face channels (mask, face sets) follow the split verts / faces; a mesh with corner / edge channels or shape keys is left alone.
func _dyntopo(hit: Vector3) -> void:
	if p["brush"] == GRAB or p["brush"] == MASK or p["brush"] == FSET:
		return
	var st := KMeshDyntopo.step_mesh(mesh, hit, float(p["radius"]), float(p.get("detail", 0.25)))
	if not st.get("changed", false):
		return
	dyn_splits += int(st["splits"])
	dyn_collapses += int(st["collapses"])
	if _nb != null:
		_nctx = _nb.make_ctx(mesh.verts, mesh.faces, _cell)
	else:
		_build_hash()
	# every per-vert array of the stroke was sized for the old mesh: take them again from the new one
	if p["sym_x"]:
		_sym = mesh.symmetry_map(0, 1e-4)
		_sax = 0
	_mask = KMeshMask.values(mesh)
	_lock = KMeshFaceSets.frozen(mesh, int(p.get("only_set", 0)))


func _build_hash() -> void:
	_head = {}
	var nv := mesh.verts.size()
	_chain.resize(nv)
	var vs := mesh.verts
	for v in nv:
		var k := _key(vs[v])
		_chain[v] = _head.get(k, -1)
		_head[k] = v


func _key(q: Vector3) -> Vector3i:
	return Vector3i(floori(q.x / _cell), floori(q.y / _cell), floori(q.z / _cell))


## verts within r of c (true distance, current positions)
func verts_in(c: Vector3, r: float) -> PackedInt32Array:
	if _nb != null:
		return _nb.verts_in(_nctx, mesh.verts, c, r)
	var out := PackedInt32Array()
	var k := _key(c)
	var n := ceili(r / _cell)
	var r2 := r * r
	var vs := mesh.verts
	for x in range(k.x - n, k.x + n + 1):
		for y in range(k.y - n, k.y + n + 1):
			for z in range(k.z - n, k.z + n + 1):
				var u: int = _head.get(Vector3i(x, y, z), -1)
				while u != -1:
					if vs[u].distance_squared_to(c) <= r2:
						out.append(u)
					u = _chain[u]
	return out


## stroke to a new surface point: lays dabs every spacing * radius along the way (the first call lays one at the point).
## Grab is not spaced: every call moves the grabbed verts to follow the point. Returns the dabs laid.
func to(point: Vector3, normal: Vector3, pressure := 1.0) -> int:
	if p["brush"] == GRAB:
		if not _has_last:
			_grab_start(point, pressure)
		else:
			_grab_move(point)
		_last = point
		dabs += 1
		return 1
	if not _has_last:
		dab(point, normal, pressure)
		_prev = point
		_carry = 0.0
		return 1
	var step := maxf(float(p["spacing"]) * float(p["radius"]), 1e-5)
	var seg := point - _prev
	var sl := seg.length()
	var laid := 0
	var s := step - _carry   # the path since the last dab counts: dabs stay evenly spaced however the mouse events fall
	while s <= sl + 1e-6:
		dab(_prev + seg * (s / sl), normal, pressure)
		laid += 1
		s += step
	_carry = sl - (s - step)
	_prev = point
	return laid


func end() -> void:
	_grab_w = {}
	_grab_v = {}
	_has_last = false


# ---------------------------------------------------------------- one dab

## one dab at `hit` (on the surface, mesh-local space) with the stroke normal `normal`; returns the verts moved
func dab(hit: Vector3, normal: Vector3, pressure := 1.0) -> int:
	if p.get("dyntopo", false) and _pend == null:
		_dyntopo(hit)
	if _alpha != null and not _alpha.inside:
		return _alpha.dab(self, hit, normal, pressure)
	if _symx != null and _pend == null:
		return _symx.dab(self, hit, normal, pressure)
	var r := float(p["radius"])
	var a := float(p["strength"]) * clampf(pressure, 0.0, 1.0)
	var sgn := -1.0 if p["invert"] else 1.0
	var fk := String(p["falloff"])
	var n := normal.normalized() if normal.length_squared() > 0.0 else Vector3.UP
	var ids := verts_in(hit, r)
	if ids.is_empty():   # p152sculptbrus: a small brush between two verts of a coarse mesh still reaches the nearest one
		r = reach_radius(hit, r)
		a *= clampf(0.5 / maxf(falloff(fk, 1.0 / 1.05), 1e-3), 1.0, 60.0)   # the nearest vert sits at the rim: give it half a dab
		ids = verts_in(hit, r)
	var br := String(p["brush"])
	if _nb != null and _alpha == null and br != MASK and br != FSET:
		var nd = _nb.displacements(_nctx, mesh.verts, mesh.vert_normals, ids, br, fk, hit, n, r, a, float(p["strength"]), sgn, _has_last, _last)
		if nd != null:
			_has_last = true
			_last = hit
			dabs += 1
			return _apply(ids, nd)
	var vp := mesh.verts
	var w := PackedFloat32Array()
	w.resize(ids.size())
	for i in ids.size():
		w[i] = falloff(fk, vp[ids[i]].distance_to(hit) / r)
	if _alpha != null:
		w = _alpha.weigh(self, ids, w, hit, n, r)
	if (br == MASK or br == FSET) and not _lock.is_empty():   # C09: nothing painted on a frozen vert
		var ki := PackedInt32Array()
		var kw := PackedFloat32Array()
		for i in ids.size():
			if not _lock[ids[i]]:
				ki.append(ids[i])
				kw.append(w[i])
		ids = ki
		w = kw
	if br == FSET:
		_has_last = true
		_last = hit
		dabs += 1
		return KMeshFaceSets.paint(mesh, ids, w, int(p["fset_id"]))
	if br == MASK:
		_has_last = true
		_last = hit
		dabs += 1
		return KMeshMask.paint(mesh, ids, w, float(p.get("mask_amount", 1.0)) * clampf(pressure, 0.0, 1.0), sgn)
	var vn := mesh.vert_normals
	var d := PackedVector3Array()
	d.resize(ids.size())
	# the area under the brush: weighted centre and normal (flatten, clay)
	var ac := hit
	var an := n
	if br == FLATTEN or br == CLAY:
		var sw := 0.0
		var sc := Vector3.ZERO
		var sn := Vector3.ZERO
		for i in ids.size():
			sc += vp[ids[i]] * w[i]
			sn += vn[ids[i]] * w[i]
			sw += w[i]
		if sw > 0.0:
			ac = sc / sw
		if sn.length_squared() > 1e-12:
			an = sn.normalized()
	for i in ids.size():
		var v := ids[i]
		var q := vp[v]
		var s := a * w[i]
		match br:
			DRAW:
				d[i] = n * s * sgn
			INFLATE:
				d[i] = vn[v] * s * sgn
			SMOOTH:
				var nb := mesh.vert_neighbors(v)
				if nb.is_empty():
					continue
				var mean := Vector3.ZERO
				for u in nb:
					mean += vp[u]
				d[i] = _toward(q, mean / nb.size(), s)
			FLATTEN:
				d[i] = _toward(q, q - an * an.dot(q - ac), s)
			CLAY:
				var pc := ac + an * float(p["strength"]) * sgn
				var h := an.dot(q - pc)
				if h * sgn < 0.0:   # below the clay plane (above it when inverted): fill up to it
					d[i] = _toward(q, q - an * h, s)
			PINCH:
				var off := q - hit
				var tg := off - n * n.dot(off)   # the offset from the brush axis, in the surface plane
				d[i] = _toward(q, q - tg, s) if sgn > 0.0 else tg.normalized() * s
			CREASE:
				var off2 := q - hit
				var tang := off2 - n * n.dot(off2)
				d[i] = -n * s * sgn + _toward(q, q - tang, s * 0.5)
			SNAKE:
				if _has_last:
					d[i] = (hit - _last) * w[i]
	_has_last = true
	_last = hit
	dabs += 1
	vp = PackedVector3Array()   # drop the read references: _apply writes the arrays in place
	vn = PackedVector3Array()
	return _apply(ids, d)


## C03: how much of a displacement a vert keeps (1 - mask); C09: none on a frozen vert
func _keep(v: int) -> float:
	if not _lock.is_empty() and _lock[v]:
		return 0.0
	return 1.0 if _mask.is_empty() else 1.0 - clampf(_mask[v], 0.0, 1.0)


static func _toward(q: Vector3, target: Vector3, s: float) -> Vector3:
	var dv := target - q
	var l := dv.length()
	if l <= s or l < 1e-12:
		return dv
	return dv * (s / l)


## add the displacements (and their mirror images to the partners); the normals of the faces touched are refreshed
func _apply(ids: PackedInt32Array, d: PackedVector3Array) -> int:
	if _pend != null:
		_pend.append([ids, d])
		return 0
	if _nb != null:
		return _nb.apply(_nctx, mesh, ids, d, _sym, _sax, _mask, _lock)
	var tot := {}
	for i in ids.size():
		if d[i] == Vector3.ZERO:
			continue
		var v := ids[i]
		tot[v] = tot.get(v, Vector3.ZERO) + d[i]
		if not _sym.is_empty():
			var u := _sym[v]
			if u >= 0:
				var mv := KMeshTopoMirror.flip(d[i], _sax)
				tot[u] = tot.get(u, Vector3.ZERO) + mv
	var vs := mesh.verts
	mesh.verts = PackedVector3Array()   # one owner while writing: no copy of the whole array per vert
	for v in tot:
		var dv: Vector3 = tot[v] * _keep(v)
		if not _sym.is_empty() and _sym[v] == v:
			dv[_sax] = 0.0   # on the mirror plane: stays on it
		vs[v] += dv
	mesh.verts = vs
	_renormal(tot.keys())
	return tot.size()


func _renormal(moved: Array) -> void:
	if moved.is_empty():
		return
	if _nb != null:
		_nb.renormal(_nctx, mesh, PackedInt32Array(moved))
		return
	var fs := {}
	for v in moved:
		for fi in mesh.vert_faces(v):
			fs[fi] = true
	var fn := mesh._face_normals
	var vn := mesh._vert_normals
	mesh._face_normals = PackedVector3Array()
	mesh._vert_normals = PackedVector3Array()
	var nw := {}
	var vs := {}
	for fi in fs:
		var a := mesh._newell(fi)
		nw[fi] = a
		fn[fi] = a.normalized()
		for v in (mesh.faces[fi] as PackedInt32Array):
			vs[v] = true
	for v in vs:
		var s := Vector3.ZERO
		for fi in mesh.vert_faces(v):
			s += nw[fi] if nw.has(fi) else mesh._newell(fi)
		vn[v] = s.normalized()
	mesh._face_normals = fn
	mesh._vert_normals = vn


# ---------------------------------------------------------------- grab

func _grab_start(point: Vector3, pressure: float) -> void:
	_grab0 = point
	_has_last = true
	var r := float(p["radius"])
	var pr := clampf(pressure, 0.0, 1.0)
	# the vert nearest the press is the one under the cursor: it follows the mouse 1:1. The falloff at its offset from the
	# press (6-13 mm on the test sphere, radius 80 mm) held it back 2-7 %, so every weight is divided by the anchor's
	var near := -1
	var nd := INF
	for v in verts_in(point, r):
		var d: float = mesh.verts[v].distance_to(point)
		_grab_w[v] = falloff(String(p["falloff"]), d / r)
		_grab_v[v] = mesh.verts[v]
		if d < nd:
			nd = d
			near = v
	var anchor := float(_grab_w[near]) if near >= 0 else 0.0
	for v in _grab_w.keys():
		_grab_w[v] = minf(float(_grab_w[v]) / anchor, 1.0) * pr if anchor > 1e-6 else float(_grab_w[v]) * pr
	if not _sym.is_empty():   # the partners follow from where they were too
		for v in _grab_w.keys():
			var u := _sym[v]
			if u >= 0 and not _grab_v.has(u):
				_grab_v[u] = mesh.verts[u]
				_grab_w[u] = 0.0


func _grab_move(point: Vector3) -> void:
	var delta := point - _grab0
	var md := KMeshTopoMirror.flip(delta, _sax)
	var tot := {}
	for v in _grab_w:
		tot[v] = tot.get(v, Vector3.ZERO) + delta * float(_grab_w[v])
		if not _sym.is_empty():
			var u := _sym[v]
			if u >= 0 and u != v and float(_grab_w[v]) > 0.0:
				tot[u] = tot.get(u, Vector3.ZERO) + md * float(_grab_w[v])
	var vs := mesh.verts
	mesh.verts = PackedVector3Array()
	for v in tot:
		var dv: Vector3 = tot[v] * _keep(v)
		if not _sym.is_empty() and _sym[v] == v:
			dv[_sax] = 0.0
		vs[v] = _grab_v[v] + dv
	mesh.verts = vs
	_renormal(tot.keys())


## p152sculptbrus: the radius a dab really uses when no vert is inside the brush (a 10 mm brush on a mesh with 20 mm cells): 1.05x the
## distance to the nearest vert within 3 radii, so the dab moves only that vert, by about half a dab; the brush itself is unchanged when a vert is in reach
func reach_radius(hit: Vector3, r: float) -> float:
	var near := verts_in(hit, r * 3.0)
	if near.is_empty():
		return r
	var best := INF
	for u in near:
		best = minf(best, mesh.verts[u].distance_to(hit))
	return maxf(r, best * 1.05)
