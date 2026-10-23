class_name KMeshSculptSym
extends RefCounted
## Sculpt symmetry beyond X (ROADMAP_400 C07): mirror X / Y / Z in any combination (up to 8 dabs) and radial symmetry
## (N copies, 2..32, around the X, Y or Z axis), all through the mesh-local origin. Mirrors and turns combine: X + radial 6
## around Y is 12 dabs. Duplicate maps are dropped (radial 2 around Y with X + Z mirrors is the same 4 dabs).
## HOW: dab REPLICATION. A dab at (hit, normal) becomes one dab per map T at (T hit, T normal). Every copy reads the SAME
## mesh (the deltas are held back, KMeshSculpt._pend, and added in one _apply), so the copies do not see each other's
## moves: on a mesh that has the symmetry, each vert and its image get the same push, mirrored, and the mesh keeps it.
## Turned on by the stroke params "sym_y", "sym_z" (bool) and "radial" (int, 1 = off), "radial_axis" (0 X, 1 Y, 2 Z),
## with "sym_x" folded in. X alone keeps the old vertex-pair path (C01). Grab keeps X symmetry only (it is not a dab).
## The hook in KMeshSculpt is three lines: begin() asks make(), dab() hands over to dab() here, _apply() holds back.

const MAX_RADIAL := 32

var maps: Array[Basis] = []   # identity first
var _lasts: Array = []        # snake hook: each copy's last dab centre


static func radial_of(p: Dictionary) -> int:
	return clampi(int(p.get("radial", 1)), 1, MAX_RADIAL)


## the orthogonal maps of a symmetry setting: mirrors x rotations, identity first, duplicates removed
static func transforms(mx: bool, my: bool, mz: bool, radial := 1, axis := 1) -> Array[Basis]:
	var mir: Array[Basis] = [Basis.IDENTITY]
	var flips := [mx, my, mz]
	for a in 3:
		if not flips[a]:
			continue
		var s := Vector3.ONE
		s[a] = -1.0
		var f := Basis.from_scale(s)
		var more: Array[Basis] = []
		for b in mir:
			more.append(f * b)
		mir.append_array(more)
	var n := clampi(radial, 1, MAX_RADIAL)
	var ax := Vector3.ZERO
	ax[clampi(axis, 0, 2)] = 1.0
	var out: Array[Basis] = []
	for k in n:
		var r := Basis(ax, TAU * k / n) if k > 0 else Basis.IDENTITY
		for b in mir:
			var t := r * b
			var dup := false
			for o in out:
				if (o.x - t.x).length() + (o.y - t.y).length() + (o.z - t.z).length() < 1e-5:
					dup = true
					break
			if not dup:
				out.append(t)
	return out


## the replicator for a stroke, or null when the params need no more than the old X path
static func make(sc: KMeshSculpt) -> KMeshSculptSym:
	var p := sc.p
	if not (p.get("sym_y", false) or p.get("sym_z", false) or radial_of(p) > 1):
		return null
	var s := KMeshSculptSym.new()
	s.maps = transforms(bool(p.get("sym_x", false)), bool(p.get("sym_y", false)), bool(p.get("sym_z", false)), radial_of(p), int(p.get("radial_axis", 1)))
	if p["brush"] != KMeshSculpt.GRAB:
		sc._sym = PackedInt32Array()   # X is one of the maps now (grab is not a dab: it keeps the vertex-pair X path)
	return s


## one dab and all its copies, read from one mesh state and applied together; returns the verts moved
func dab(sc: KMeshSculpt, hit: Vector3, normal: Vector3, pressure: float) -> int:
	var d0 := sc.dabs
	var had := sc._has_last
	sc._pend = []
	for k in maps.size():
		var t := maps[k]
		if had and k < _lasts.size():
			sc._last = _lasts[k]
		sc._has_last = had
		sc.dab(t * hit, t * normal, pressure)
		if k < _lasts.size():
			_lasts[k] = sc._last
		else:
			_lasts.append(sc._last)
	var ids := PackedInt32Array()
	var d := PackedVector3Array()
	for e in sc._pend:
		ids.append_array(e[0])
		d.append_array(e[1])
	sc._pend = null
	sc._has_last = true
	sc._last = hit
	sc.dabs = d0 + 1
	return sc._apply(ids, d)
