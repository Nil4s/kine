class_name WaterSurface
extends RefCounted
## L5: the water surface from the solver's particles, as ONE connected, closed, smooth mesh with per-vertex foam.
## Pipeline: surface_aniso (anisotropic kernel density + Taubin-smoothed centres, iso 0.5, marching tetrahedra; native) -> weld the triangle soup ->
## Taubin smoothing of the mesh (lambda|mu, Taubin 1995, SIGGRAPH "Curve and surface smoothing without shrinkage") -> area weighted vertex normals ->
## foam from the particle speed near each vertex.


## triangle soup -> {pos: PackedVector3Array, idx: PackedInt32Array}; vertices closer than 1e-6 m are one vertex
static func weld(soup: PackedVector3Array) -> Dictionary:
	var map := {}
	var pos := PackedVector3Array()
	var idx := PackedInt32Array()
	idx.resize(soup.size())
	for i in soup.size():
		var p := soup[i]
		var key := Vector3i(roundi(p.x * 1e6), roundi(p.y * 1e6), roundi(p.z * 1e6))
		var id: int = map.get(key, -1)
		if id < 0:
			id = pos.size()
			pos.append(p)
			map[key] = id
		idx[i] = id
	# drop degenerate triangles
	var out := PackedInt32Array()
	for t in range(0, idx.size() - 2, 3):
		if idx[t] != idx[t + 1] and idx[t + 1] != idx[t + 2] and idx[t] != idx[t + 2]:
			out.append(idx[t])
			out.append(idx[t + 1])
			out.append(idx[t + 2])
	return {"pos": pos, "idx": out}


static func signed_volume(pos: PackedVector3Array, idx: PackedInt32Array) -> float:
	var v := 0.0
	for t in range(0, idx.size() - 2, 3):
		v += pos[idx[t]].dot(pos[idx[t + 1]].cross(pos[idx[t + 2]])) / 6.0
	return v


## one-ring Laplacian steps: x += w * (mean(neighbours) - x); lambda > 0 then mu < 0 (Taubin) so the volume does not shrink
static func taubin(pos: PackedVector3Array, idx: PackedInt32Array, iters: int, lam := 0.5, mu := -0.53) -> PackedVector3Array:
	var n := pos.size()
	var nb: Array = []
	nb.resize(n)
	for i in n:
		nb[i] = PackedInt32Array()
	var seen := {}
	for t in range(0, idx.size() - 2, 3):
		for e in 3:
			var a := idx[t + e]
			var b := idx[t + (e + 1) % 3]
			var key := (mini(a, b) << 32) | maxi(a, b)
			if seen.has(key):
				continue
			seen[key] = true
			(nb[a] as PackedInt32Array).append(b)
			(nb[b] as PackedInt32Array).append(a)
	var cur := pos.duplicate()
	for it in iters:
		for w in [lam, mu]:
			var nxt := cur.duplicate()
			for i in n:
				var l: PackedInt32Array = nb[i]
				if l.size() == 0:
					continue
				var m := Vector3.ZERO
				for j in l:
					m += cur[j]
				m /= float(l.size())
				nxt[i] = cur[i] + w * (m - cur[i])
			cur = nxt
	return cur


static func normals(pos: PackedVector3Array, idx: PackedInt32Array) -> PackedVector3Array:
	var nrm := PackedVector3Array()
	nrm.resize(pos.size())
	for t in range(0, idx.size() - 2, 3):
		# Godot front faces are CLOCKWISE seen from outside, so the right-handed cross product points INTO the body: negate it
		var fn := -(pos[idx[t + 1]] - pos[idx[t]]).cross(pos[idx[t + 2]] - pos[idx[t]])   # length = 2 * area
		for e in 3:
			nrm[idx[t + e]] += fn
	for i in nrm.size():
		nrm[i] = nrm[i].normalized() if nrm[i].length() > 1e-18 else Vector3.UP
	return nrm


## foam per vertex in 0..1: the mean speed of the particles within 1.5 h of the vertex, smoothstep(v0, 2 v0, speed)
static func foam(pos: PackedVector3Array, pdata: PackedFloat64Array, h: float, v0 := 1.0) -> PackedFloat32Array:
	var cell := 2.0 * h
	var grid := {}
	var np := pdata.size() / 6
	for p in np:
		var key := Vector3i(floori(pdata[6 * p] / cell), floori(pdata[6 * p + 1] / cell), floori(pdata[6 * p + 2] / cell))
		if not grid.has(key):
			grid[key] = PackedInt32Array()
		(grid[key] as PackedInt32Array).append(p)
	var out := PackedFloat32Array()
	out.resize(pos.size())
	var r2 := 2.25 * h * h
	for i in pos.size():
		var q := pos[i]
		var c := Vector3i(floori(q.x / cell), floori(q.y / cell), floori(q.z / cell))
		var s := 0.0
		var cnt := 0
		for dz in range(-1, 2):
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var l = grid.get(c + Vector3i(dx, dy, dz))
					if l == null:
						continue
					for p in (l as PackedInt32Array):
						var d := Vector3(pdata[6 * p], pdata[6 * p + 1], pdata[6 * p + 2]) - q
						if d.length_squared() <= r2:
							s += Vector3(pdata[6 * p + 3], pdata[6 * p + 4], pdata[6 * p + 5]).length()
							cnt += 1
		out[i] = smoothstep(v0, 2.0 * v0, s / cnt) if cnt > 0 else 0.0
	return out


## the whole chain from a solver: returns {mesh, pos, idx, volume} (mesh null when there is no surface)
static func build(F: Object, iso := 0.5, ndiv := 4, smooth_iters := 4, h := 0.01, foam_v0 := 1.0, with_foam := true) -> Dictionary:
	var sf: Dictionary = F.surface_aniso(iso, ndiv)
	var soup: PackedVector3Array = sf["verts"]
	if soup.size() < 3:
		return {"mesh": null}
	var w := weld(soup)
	var pos: PackedVector3Array = w["pos"]
	var idx: PackedInt32Array = w["idx"]
	if smooth_iters > 0:
		pos = taubin(pos, idx, smooth_iters)
	var vol := signed_volume(pos, idx)   # > 0: counter-clockwise from outside (right-handed). Godot wants CLOCKWISE front faces: flip then.
	if vol > 0.0:
		for t in range(0, idx.size() - 2, 3):
			var tmp := idx[t + 1]
			idx[t + 1] = idx[t + 2]
			idx[t + 2] = tmp
	vol = absf(vol)
	var nrm := normals(pos, idx)
	var fo := PackedFloat32Array()
	if with_foam:
		fo = foam(pos, F.particle_data(), h, foam_v0)
	return {"mesh": make_mesh(pos, idx, nrm, fo), "pos": pos, "idx": idx, "volume": vol, "foam": fo}


static func make_mesh(pos: PackedVector3Array, idx: PackedInt32Array, nrm: PackedVector3Array, fo: PackedFloat32Array) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nrm
	var col := PackedColorArray()
	col.resize(pos.size())
	for i in pos.size():
		col[i] = Color(fo[i] if i < fo.size() else 0.0, 0, 0, 1)
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## L31 STUB (bars commit): volume preserving smoothing is not implemented yet; returns the positions unchanged.
static func smooth_volume(pos: PackedVector3Array, _idx: PackedInt32Array, _iters := 40) -> PackedVector3Array:
	return pos.duplicate()
