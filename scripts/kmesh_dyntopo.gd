class_name KMeshDyntopo
extends RefCounted
## Dynamic topology (L52, GAP_AUDIT Sculpt item 1). Under the brush (centre c, radius r) the mesh follows the stroke: edges longer than
## L_max = detail * r are split at their midpoint, edges shorter than 0.4 * L_max are collapsed (to the midpoint, else onto one end).
## Written from the idea in the papers (edge split / edge collapse remeshing, Botsch & Kobbelt 2004), not from any program's code.
##   Only tris whose box meets the brush's box are looked at. A split needs the edge midpoint in the brush; a collapse needs both ends in
##   the brush, exactly two tris on the edge, the link condition, no tri turned over (unit normals' dot >= 0.35) or squashed (area >= 20 %),
##   and no new edge longer than L_max. So a vertex outside the brush never moves and an edge with both ends and midpoint outside is untouched.
##   Edges are taken in ascending (low vert, high vert) key order, a pass = all splits then all collapses, up to `passes` passes.
## HEAVY LOOP: refine_gd is the GDScript twin; native/src/kine_dyntopo_native.cpp is the same arithmetic in C++ (KineDyntopoNative.refine).
##   Both return {verts, tris, splits, collapses}: verts keep their order (new ones appended, collapsed ones dropped), tris = the untouched
##   ones in their order, then the rebuilt ones.

const SHORT := 0.4
static var native_on := true
static var _door = null
static var _tried := false

var P := PackedVector3Array()
var T := PackedInt32Array()      # local tris, 3 per tri
var alive := PackedByteArray()
var tsrc := PackedInt32Array()   # local tri -> the input tri it came from
var vsrc := PackedInt32Array()   # vert -> the input vert it came from (a new vert: the one end of its edge)
var emap := {}                   # edge key -> Array of local tri ids
var vt := {}                     # vert -> Array of local tri ids
var vdead := {}
var c := Vector3.ZERO
var r2 := 0.0
var l2 := 0.0
var s2 := 0.0
var splits := 0
var collapses := 0
var flips := 0


static func native_door():
	if not native_on:
		return null
	if not _tried:
		_tried = true
		if NativeExt.ensure("kine_native", "KineDyntopoNative"):
			_door = load("res://scripts/kmesh_dyntopo_native.gd")
	return _door


## refine verts / tris (flat, 3 per tri) around c; native when the DLL is there
static func refine(verts: PackedVector3Array, tris: PackedInt32Array, centre: Vector3, radius: float, detail: float, passes := 8) -> Dictionary:
	var d = native_door()
	var lmax := detail * radius
	if d != null:
		var res: Dictionary = d.refine(verts, tris, centre, radius, lmax, passes)
		res["native"] = true
		return res
	var g := refine_gd(verts, tris, centre, radius, lmax, passes)
	g["native"] = false
	return g


## a KMesh edited in place (triangulated first when it has other faces); returns the stats
static func step_mesh(mesh: KMesh, centre: Vector3, radius: float, detail: float, passes := 8) -> Dictionary:
	for k in mesh.attrs:   # a corner or edge channel (uv seams ...) cannot follow a split: leave such a mesh alone
		var dm: String = mesh.attrs[k]["domain"]
		if dm == KMesh.AD_CORNER or dm == KMesh.AD_EDGE:
			return {"verts": mesh.verts, "tris": PackedInt32Array(), "splits": 0, "collapses": 0, "changed": false, "native": false}
	if not mesh.shapes.is_empty():
		return {"verts": mesh.verts, "tris": PackedInt32Array(), "splits": 0, "collapses": 0, "changed": false, "native": false}
	var tris := PackedInt32Array()
	var tface := PackedInt32Array()
	for fi in mesh.faces.size():
		var fa: PackedInt32Array = mesh.faces[fi]
		for k in range(1, fa.size() - 1):
			tris.append(fa[0])
			tris.append(fa[k])
			tris.append(fa[k + 1])
			tface.append(fi)
	var t_before := tris.size() / 3
	var res := refine(mesh.verts, tris, centre, radius, detail, passes)
	if int(res["splits"]) + int(res["collapses"]) == 0 and t_before == mesh.faces.size():
		res["changed"] = false
		return res
	var nt: PackedInt32Array = res["tris"]
	var faces: Array = []
	faces.resize(nt.size() / 3)
	for i in faces.size():
		faces[i] = PackedInt32Array([nt[3 * i], nt[3 * i + 1], nt[3 * i + 2]])
	mesh.verts = res["verts"]
	mesh.faces = faces
	if not mesh.attrs.is_empty():
		var fs := PackedInt32Array()
		var ts: PackedInt32Array = res["tsrc"]
		fs.resize(ts.size())
		for i in ts.size():
			fs[i] = tface[ts[i]]
		mesh.attr_remap(res["vsrc"], fs, null, null)
	mesh.rebuild()
	res["changed"] = true
	return res


static func refine_gd(verts: PackedVector3Array, tris: PackedInt32Array, centre: Vector3, radius: float, lmax: float, passes := 8) -> Dictionary:
	var w := KMeshDyntopo.new()
	return w._run(verts, tris, centre, radius, lmax, passes)


static func _key(a: int, b: int) -> int:
	return ((a << 32) | b) if a < b else ((b << 32) | a)


func _d2(a: Vector3, b: Vector3) -> float:
	var x: float = a.x - b.x
	var y: float = a.y - b.y
	var z: float = a.z - b.z
	return x * x + y * y + z * z


func _cross(a: Vector3, b: Vector3, d: Vector3) -> Array:   # (b - a) x (d - a) in doubles
	var ux: float = b.x - a.x
	var uy: float = b.y - a.y
	var uz: float = b.z - a.z
	var vx: float = d.x - a.x
	var vy: float = d.y - a.y
	var vz: float = d.z - a.z
	return [uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx]


func _add(t: int) -> void:
	for e in 3:
		var a: int = T[3 * t + e]
		var b: int = T[3 * t + (e + 1) % 3]
		var k := _key(a, b)
		if emap.has(k):
			(emap[k] as Array).append(t)
		else:
			emap[k] = [t]
		if vt.has(a):
			(vt[a] as Array).append(t)
		else:
			vt[a] = [t]


func _rem(t: int) -> void:
	for e in 3:
		var a: int = T[3 * t + e]
		var b: int = T[3 * t + (e + 1) % 3]
		var k := _key(a, b)
		var l: Array = emap[k]
		l.erase(t)
		if l.is_empty():
			emap.erase(k)
		(vt[a] as Array).erase(t)


func _run(verts: PackedVector3Array, tris: PackedInt32Array, centre: Vector3, radius: float, lmax: float, passes: int) -> Dictionary:
	c = centre
	r2 = radius * radius
	l2 = lmax * lmax
	s2 = SHORT * lmax * (SHORT * lmax)
	P = verts.duplicate()
	var nv0 := verts.size()
	var lo_x: float = c.x - radius
	var hi_x: float = c.x + radius
	var lo_y: float = c.y - radius
	var hi_y: float = c.y + radius
	var lo_z: float = c.z - radius
	var hi_z: float = c.z + radius
	var keep := PackedInt32Array()
	var nt := tris.size() / 3
	var act := PackedByteArray()
	act.resize(nt)
	for t in nt:
		var a := verts[tris[3 * t]]
		var b := verts[tris[3 * t + 1]]
		var d := verts[tris[3 * t + 2]]
		if maxf(maxf(a.x, b.x), d.x) < lo_x or minf(minf(a.x, b.x), d.x) > hi_x:
			continue
		if maxf(maxf(a.y, b.y), d.y) < lo_y or minf(minf(a.y, b.y), d.y) > hi_y:
			continue
		if maxf(maxf(a.z, b.z), d.z) < lo_z or minf(minf(a.z, b.z), d.z) > hi_z:
			continue
		act[t] = 1
		T.append(tris[3 * t])
		T.append(tris[3 * t + 1])
		T.append(tris[3 * t + 2])
		alive.append(1)
		tsrc.append(t)
		_add(alive.size() - 1)
	vsrc.resize(verts.size())
	for i in verts.size():
		vsrc[i] = i
	for _p in passes:
		var ch := _split_phase()
		ch = _collapse_phase() or ch
		if splits + collapses > 0:   # Botsch & Kobbelt 2004 steps 3-5: flip toward valence 6, retry the refused collapses, relax tangentially
			ch = _flip_phase() or ch
			ch = _collapse_phase() or ch
			_relax_phase()
		if not ch:
			break
	if splits + collapses == 0:   # nothing to do: the input comes back as it is (same order), so a no-op stroke is a no-op for undo too
		var idv := PackedInt32Array()
		idv.resize(verts.size())
		for i in verts.size():
			idv[i] = i
		var idt := PackedInt32Array()
		idt.resize(nt)
		for i in nt:
			idt[i] = i
		return {"verts": verts, "tris": tris, "splits": 0, "collapses": 0, "vsrc": idv, "tsrc": idt}
	# output
	var dead_n := vdead.size()
	var remap := PackedInt32Array()
	var ov := P
	var ovs := vsrc
	if dead_n > 0:
		remap.resize(P.size())
		ov = PackedVector3Array()
		ovs = PackedInt32Array()
		for i in P.size():
			if vdead.has(i):
				remap[i] = -1
			else:
				remap[i] = ov.size()
				ov.append(P[i])
				ovs.append(vsrc[i])
	var ot := PackedInt32Array()
	var ots := PackedInt32Array()
	for t in nt:
		if act[t] == 0:
			ots.append(t)
			for k in 3:
				ot.append(remap[tris[3 * t + k]] if dead_n > 0 else tris[3 * t + k])
	for t in alive.size():
		if alive[t] == 1:
			ots.append(tsrc[t])
			for k in 3:
				ot.append(remap[T[3 * t + k]] if dead_n > 0 else T[3 * t + k])
	return {"verts": ov, "tris": ot, "splits": splits, "collapses": collapses, "flips": flips, "vsrc": ovs, "tsrc": ots}


func _split_phase() -> bool:
	var keys: Array = emap.keys()
	keys.sort()
	var any := false
	for k in keys:
		if not emap.has(k):
			continue
		var tl: Array = emap[k]
		if tl.size() > 2:
			continue
		var a: int = k >> 32
		var b: int = k & 0xFFFFFFFF
		if _d2(P[a], P[b]) <= l2:
			continue
		var m := Vector3((P[a].x + P[b].x) * 0.5, (P[a].y + P[b].y) * 0.5, (P[a].z + P[b].z) * 0.5)
		if _d2(m, c) > r2:
			continue
		var mi := P.size()
		P.append(m)
		vsrc.append(vsrc[a])
		for t in tl.duplicate():
			var i0 := -1
			for i in 3:
				var p: int = T[3 * t + i]
				var q: int = T[3 * t + (i + 1) % 3]
				if (p == a and q == b) or (p == b and q == a):
					i0 = i
			var p: int = T[3 * t + i0]
			var q: int = T[3 * t + (i0 + 1) % 3]
			var z: int = T[3 * t + (i0 + 2) % 3]
			_rem(t)
			T[3 * t] = p
			T[3 * t + 1] = mi
			T[3 * t + 2] = z
			_add(t)
			var t2 := alive.size()
			T.append(mi)
			T.append(q)
			T.append(z)
			alive.append(1)
			tsrc.append(tsrc[t])
			_add(t2)
		splits += 1
		any = true
	return any


func _nrm(t: int) -> Array:
	return _cross(P[T[3 * t]], P[T[3 * t + 1]], P[T[3 * t + 2]])


## a replacement triangle q (3 points) against an old normal n0: not turned over (dot >= 0.35 of the lengths) and not squashed (area >= 20 %)
func _tri_ok(q0: Vector3, q1: Vector3, q2: Vector3, n0: Array) -> bool:
	var n1 := _cross(q0, q1, q2)
	var co2: float = n0[0] * n0[0] + n0[1] * n0[1] + n0[2] * n0[2]
	var cn2: float = n1[0] * n1[0] + n1[1] * n1[1] + n1[2] * n1[2]
	var dt: float = n0[0] * n1[0] + n0[1] * n1[1] + n0[2] * n1[2]
	return not (cn2 <= 0.04 * co2 or dt < 0.35 * sqrt(co2) * sqrt(cn2))


## edge flip toward valence 6: an interior edge (a, b) with both ends and both opposite verts (z, w) in the brush becomes (z, w) when that
## lowers the sum of (valence - 6)^2 over the four, z-w is not an edge yet, the new edge lies in [0.4, 1.0] * L_max, and no tri turns over.
func _flip_phase() -> bool:
	var keys: Array = emap.keys()
	keys.sort()
	var any := false
	for k in keys:
		if not emap.has(k):
			continue
		var tl: Array = emap[k]
		if tl.size() != 2:
			continue
		var a: int = k >> 32
		var b: int = k & 0xFFFFFFFF
		if _d2(P[a], c) > r2 or _d2(P[b], c) > r2:
			continue
		var t1: int = tl[0]
		var t2: int = tl[1]
		var i0 := -1
		for i in 3:
			var pp: int = T[3 * t1 + i]
			var qq: int = T[3 * t1 + (i + 1) % 3]
			if (pp == a and qq == b) or (pp == b and qq == a):
				i0 = i
		var p: int = T[3 * t1 + i0]
		var q: int = T[3 * t1 + (i0 + 1) % 3]
		var z: int = T[3 * t1 + (i0 + 2) % 3]
		var w := -1
		for i in 3:
			var u: int = T[3 * t2 + i]
			if u != p and u != q:
				w = u
		if w < 0 or w == z or emap.has(_key(z, w)):
			continue
		if _d2(P[z], c) > r2 or _d2(P[w], c) > r2:
			continue
		var lzw := _d2(P[z], P[w])
		if lzw > l2 or lzw < s2:
			continue
		var vp: int = (vt[p] as Array).size()
		var vq: int = (vt[q] as Array).size()
		var vz: int = (vt[z] as Array).size()
		var vw: int = (vt[w] as Array).size()
		if vp <= 3 or vq <= 3:
			continue
		var before := (vp - 6) * (vp - 6) + (vq - 6) * (vq - 6) + (vz - 6) * (vz - 6) + (vw - 6) * (vw - 6)
		var after := (vp - 7) * (vp - 7) + (vq - 7) * (vq - 7) + (vz - 5) * (vz - 5) + (vw - 5) * (vw - 5)
		if after >= before:
			continue
		var n1 := _nrm(t1)
		var n2 := _nrm(t2)
		if not (_tri_ok(P[p], P[w], P[z], n1) and _tri_ok(P[p], P[w], P[z], n2) and _tri_ok(P[w], P[q], P[z], n1) and _tri_ok(P[w], P[q], P[z], n2)):
			continue
		var m1 := _cross(P[p], P[w], P[z])
		var m2 := _cross(P[w], P[q], P[z])
		if m1[0] * m2[0] + m1[1] * m2[1] + m1[2] * m2[2] < 0.35 * sqrt(m1[0] * m1[0] + m1[1] * m1[1] + m1[2] * m1[2]) * sqrt(m2[0] * m2[0] + m2[1] * m2[1] + m2[2] * m2[2]):
			continue
		_rem(t1)
		_rem(t2)
		T[3 * t1] = p
		T[3 * t1 + 1] = w
		T[3 * t1 + 2] = z
		T[3 * t2] = w
		T[3 * t2 + 1] = q
		T[3 * t2 + 2] = z
		_add(t1)
		_add(t2)
		flips += 1
		any = true
	return any


## tangential relaxation (2 sweeps, ascending vert order): a vert in the brush goes half way to its neighbours' centroid, with the move
## projected onto the tangent plane (normal = sum of its tris' area normals). Refused when it would leave the brush, turn or squash a tri,
## or push an incident edge further out of [0.4, 1.0] * L_max.
func _relax_phase() -> void:
	var vs: Array = vt.keys()
	vs.sort()
	for _s in 2:
		for v in vs:
			var pv := P[v]
			if _d2(pv, c) > r2:
				continue
			var ts: Array = vt[v]
			if ts.is_empty():
				continue
			var nb: Array = []
			var nx := 0.0
			var ny := 0.0
			var nz := 0.0
			for t in ts:
				var nn := _nrm(t)
				nx += nn[0]
				ny += nn[1]
				nz += nn[2]
				for k in 3:
					var u: int = T[3 * t + k]
					if u != v and not nb.has(u):
						nb.append(u)
			var nl := sqrt(nx * nx + ny * ny + nz * nz)
			if nl <= 0.0 or nb.size() < 3:
				continue
			nx /= nl
			ny /= nl
			nz /= nl
			var qx := 0.0
			var qy := 0.0
			var qz := 0.0
			for u in nb:
				qx += P[u].x
				qy += P[u].y
				qz += P[u].z
			qx /= nb.size()
			qy /= nb.size()
			qz /= nb.size()
			var mx: float = qx - pv.x
			var my: float = qy - pv.y
			var mz: float = qz - pv.z
			var md: float = mx * nx + my * ny + mz * nz
			mx -= md * nx
			my -= md * ny
			mz -= md * nz
			var np := Vector3(pv.x + 0.5 * mx, pv.y + 0.5 * my, pv.z + 0.5 * mz)
			if _d2(np, c) > r2:
				continue
			var good := true
			for u in nb:
				var o := _d2(pv, P[u])
				var n := _d2(np, P[u])
				if (n > l2 and n > o) or (n < s2 and n < o):
					good = false
					break
			if not good:
				continue
			for t in ts:
				var n0 := _nrm(t)
				var q0 := np if T[3 * t] == v else P[T[3 * t]]
				var q1 := np if T[3 * t + 1] == v else P[T[3 * t + 1]]
				var q2 := np if T[3 * t + 2] == v else P[T[3 * t + 2]]
				if not _tri_ok(q0, q1, q2, n0):
					good = false
					break
			if good:
				P[v] = np


func _nbrs(v: int) -> Dictionary:
	var d := {}
	for t in vt.get(v, []):
		for k in 3:
			var u: int = T[3 * t + k]
			if u != v:
				d[u] = true
	return d


func _collapse_phase() -> bool:
	var keys: Array = emap.keys()
	keys.sort()
	var any := false
	for k in keys:
		if not emap.has(k):
			continue
		var tl: Array = emap[k]
		if tl.size() != 2:
			continue
		var a: int = k >> 32
		var b: int = k & 0xFFFFFFFF
		if _d2(P[a], c) > r2 or _d2(P[b], c) > r2:
			continue
		if _d2(P[a], P[b]) >= s2:
			continue
		if _try_collapse(a, b, tl):
			collapses += 1
			any = true
	return any


func _try_collapse(a: int, b: int, tl: Array) -> bool:
	var na := _nbrs(a)
	var nb := _nbrs(b)
	var common := 0
	for u in na:
		if nb.has(u):
			common += 1
	if common != 2:
		return false
	var pa := P[a]
	var pb := P[b]
	var mid := Vector3((pa.x + pb.x) * 0.5, (pa.y + pb.y) * 0.5, (pa.z + pb.z) * 0.5)
	var cands := [[a, b, mid], [a, b, pa], [b, a, pb]]   # survivor, removed, where the survivor goes
	var star := {}
	for t in vt[a]:
		star[t] = true
	for t in vt[b]:
		star[t] = true
	for cd in cands:
		var s: int = cd[0]
		var rm: int = cd[1]
		var p: Vector3 = cd[2]
		var good := true
		for t in star:
			var has_a := false
			var has_b := false
			for k in 3:
				if T[3 * t + k] == a:
					has_a = true
				if T[3 * t + k] == b:
					has_b = true
			if has_a and has_b:
				continue
			var q0 := P[T[3 * t]]
			var q1 := P[T[3 * t + 1]]
			var q2 := P[T[3 * t + 2]]
			var n0 := _cross(q0, q1, q2)
			var i0: int = T[3 * t]
			var i1: int = T[3 * t + 1]
			var i2: int = T[3 * t + 2]
			if i0 == rm:
				i0 = s
			if i1 == rm:
				i1 = s
			if i2 == rm:
				i2 = s
			var r0 := p if i0 == s else P[i0]
			var r1 := p if i1 == s else P[i1]
			var r2v := p if i2 == s else P[i2]
			var n1 := _cross(r0, r1, r2v)
			var co2: float = n0[0] * n0[0] + n0[1] * n0[1] + n0[2] * n0[2]
			var cn2: float = n1[0] * n1[0] + n1[1] * n1[1] + n1[2] * n1[2]
			var dt: float = n0[0] * n1[0] + n0[1] * n1[1] + n0[2] * n1[2]
			if cn2 <= 0.04 * co2 or dt < 0.35 * sqrt(co2) * sqrt(cn2):
				good = false
				break
		if not good:
			continue
		for u in na:
			if u != b and _d2(p, P[u]) > l2:
				good = false
				break
		if not good:
			continue
		for u in nb:
			if u != a and _d2(p, P[u]) > l2:
				good = false
				break
		if not good:
			continue
		# commit
		for t in tl.duplicate():
			_rem(t)
			alive[t] = 0
		for t in (vt[rm] as Array).duplicate():
			_rem(t)
			for k in 3:
				if T[3 * t + k] == rm:
					T[3 * t + k] = s
			_add(t)
		vt.erase(rm)
		P[s] = p
		vdead[rm] = true
		return true
	return false


## the edges with both ends in the brush against the band [0.4, 1.0] * L_max (+-10 %): {n, bad, min, max}
static func band_report(verts: PackedVector3Array, tris: PackedInt32Array, centre: Vector3, radius: float, lmax: float) -> Dictionary:
	var seen := {}
	var n := 0
	var bad := 0
	var mn := 1e9
	var mx := 0.0
	for k in range(0, tris.size(), 3):
		for e in 3:
			var a := tris[k + e]
			var b := tris[k + (e + 1) % 3]
			var key := _key(a, b)
			if seen.has(key):
				continue
			seen[key] = true
			if verts[a].distance_to(centre) <= radius and verts[b].distance_to(centre) <= radius:
				var l := verts[a].distance_to(verts[b])
				n += 1
				mn = minf(mn, l)
				mx = maxf(mx, l)
				if l < 0.4 * lmax * 0.9 or l > lmax * 1.1:
					bad += 1
	return {"n": n, "bad": bad, "min": mn, "max": mx}
