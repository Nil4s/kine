class_name KMeshValidate
extends RefCounted
## A10 (docs/ROADMAP_400.md): find what is wrong with a mesh, and fix what can be fixed, each problem with its next step.
## Problems: doubled verts (same place), loose verts (in no face), degenerate faces (a repeated vert or no area), flipped
## faces (a neighbour winds the other way: the shared edge is walked the same direction twice), non-manifold edges (3+
## faces on one edge), holes (boundary loops), inside-out (a closed mesh whose volume is negative).
## repair() works on the KMesh's verts/faces and rebuilds; bracket it with KMeshUndo for one undo step.

const WELD := 1e-5          # m: verts closer than this are the same vert
const AREA_MIN := 1e-12     # m^2: a face with less area is degenerate
const HOLE_FILL_MAX := 12   # a boundary loop of up to this many edges is filled with one face


static func _ekey(a: int, b: int, nv: int) -> int:
	return mini(a, b) * nv + maxi(a, b)


static func _area(m: KMesh, f: PackedInt32Array) -> float:
	var n := Vector3.ZERO
	for i in f.size():
		var p: Vector3 = m.verts[f[i]]
		var q: Vector3 = m.verts[f[(i + 1) % f.size()]]
		n += Vector3((p.y - q.y) * (p.z + q.z), (p.z - q.z) * (p.x + q.x), (p.x - q.x) * (p.y + q.y))
	return n.length() * 0.5


static func _doubled(m: KMesh) -> Array:
	var cell := {}
	var out := []
	for v in m.verts.size():
		var p: Vector3 = m.verts[v]
		var k := Vector3i(floori(p.x / WELD), floori(p.y / WELD), floori(p.z / WELD))
		var hit := -1
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					for o in cell.get(k + Vector3i(dx, dy, dz), []):
						if hit < 0 and (m.verts[o] as Vector3).distance_to(p) <= WELD:
							hit = o
		if hit >= 0:
			out.append([v, hit])
		else:
			if not cell.has(k):
				cell[k] = []
			cell[k].append(v)
	return out


## boundary loops: each as the list of its verts in order
static func _holes(m: KMesh) -> Array:
	var nv := m.verts.size()
	var next_of := {}   # boundary: a -> b for a face edge a->b with no face on b->a
	var dir := {}
	for f in m.faces:
		var ff: PackedInt32Array = f
		for i in ff.size():
			dir[ff[i] * nv + ff[(i + 1) % ff.size()]] = true
	for f in m.faces:
		var ff: PackedInt32Array = f
		for i in ff.size():
			var a := ff[i]
			var b := ff[(i + 1) % ff.size()]
			if a != b and not dir.has(b * nv + a):
				next_of[b] = a   # the hole runs the other way round
	var loops := []
	var seen := {}
	for s in next_of:
		if seen.has(s):
			continue
		var loop := []
		var v: int = s
		while not seen.has(v) and next_of.has(v):
			seen[v] = true
			loop.append(v)
			v = next_of[v]
		if v == s and loop.size() >= 3:
			loops.append(loop)
	return loops


static func _volume(m: KMesh) -> float:
	var vol := 0.0
	for f in m.faces:
		var ff: PackedInt32Array = f
		for i in range(1, ff.size() - 1):
			vol += (m.verts[ff[0]] as Vector3).dot((m.verts[ff[i]] as Vector3).cross(m.verts[ff[i + 1]])) / 6.0
	return vol


## {"problems": [{"kind", "count", "items", "fix", "auto"}], "ok": bool}
static func report(m: KMesh) -> Dictionary:
	var nv := m.verts.size()
	var probs := []
	var dbl := _doubled(m)
	if not dbl.is_empty():
		probs.append({"kind": "doubled", "count": dbl.size(), "items": dbl.map(func(p): return p[0]), "auto": true,
			"fix": "%d verts sit on another vert: merge them by distance (Repair)" % dbl.size()})
	var used := PackedByteArray()
	used.resize(nv)
	for f in m.faces:
		for v in (f as PackedInt32Array):
			used[v] = 1
	var loose := []
	for v in nv:
		if used[v] == 0:
			loose.append(v)
	if not loose.is_empty():
		probs.append({"kind": "loose", "count": loose.size(), "items": loose, "auto": true, "fix": "%d verts are in no face: delete them (Repair)" % loose.size()})
	var degen := []
	var dircount := {}
	var undcount := {}
	for fi in m.faces.size():
		var f: PackedInt32Array = m.faces[fi]
		var uniq := {}
		for v in f:
			uniq[v] = true
		if uniq.size() < 3 or _area(m, f) < AREA_MIN:
			degen.append(fi)
			continue
		for i in f.size():
			var a := f[i]
			var b := f[(i + 1) % f.size()]
			dircount[a * nv + b] = int(dircount.get(a * nv + b, 0)) + 1
			undcount[_ekey(a, b, nv)] = int(undcount.get(_ekey(a, b, nv), 0)) + 1
	if not degen.is_empty():
		probs.append({"kind": "degenerate", "count": degen.size(), "items": degen, "auto": true, "fix": "%d faces have no area: delete them (Repair)" % degen.size()})
	var nonman := []
	var flipped := 0
	for k in undcount:
		if int(undcount[k]) > 2:
			nonman.append(k)
	for k in dircount:
		if int(dircount[k]) > 1 and int(undcount[_ekey(k / nv, k % nv, nv)]) == 2:
			flipped += 1
	if flipped > 0:
		probs.append({"kind": "flipped", "count": flipped, "items": [], "auto": true, "fix": "%d edges join faces that wind opposite ways: make the normals consistent (Repair)" % flipped})
	if not nonman.is_empty():
		probs.append({"kind": "non_manifold", "count": nonman.size(), "items": nonman.map(func(k): return [k / nv, k % nv]), "auto": false,
			"fix": "%d edges have 3 or more faces: select them and split or delete the extra face by hand" % nonman.size()})
	var holes := _holes(m)
	if not holes.is_empty():
		var small := holes.filter(func(l): return (l as Array).size() <= HOLE_FILL_MAX).size()
		probs.append({"kind": "holes", "count": holes.size(), "items": holes, "auto": small > 0,
			"fix": "%d open borders (%d small enough to fill with one face by Repair; the rest: Fill by hand, or leave it if the mesh is meant to be open)" % [holes.size(), small]})
	if holes.is_empty() and nonman.is_empty() and flipped == 0 and m.faces.size() > 0 and _volume(m) < 0.0:
		probs.append({"kind": "inside_out", "count": m.faces.size(), "items": [], "auto": true, "fix": "the mesh is inside out (its normals point in): flip every face (Repair)"})
	return {"problems": probs, "ok": probs.is_empty()}


## fix every automatic problem; returns {kind: how many fixed}. The KMesh is rebuilt once at the end.
static func repair(m: KMesh) -> Dictionary:
	var done := {}
	var nv := m.verts.size()
	# doubled: remap onto the first of each group
	var remap := PackedInt32Array()
	remap.resize(nv)
	for v in nv:
		remap[v] = v
	for p in _doubled(m):
		remap[p[0]] = p[1]
	var nd := 0
	var faces := []
	for f in m.faces:
		var g := PackedInt32Array()
		for v in (f as PackedInt32Array):
			var r := remap[v]
			if g.is_empty() or g[g.size() - 1] != r:
				g.append(r)
		if g.size() > 1 and g[0] == g[g.size() - 1]:
			g.remove_at(g.size() - 1)
		faces.append(g)
	for v in nv:
		nd += 1 if remap[v] != v else 0
	if nd > 0:
		done["doubled"] = nd
	# degenerate faces
	var keep := []
	var tmp := KMesh.new()
	tmp.verts = m.verts
	for g in faces:
		var uniq := {}
		for v in (g as PackedInt32Array):
			uniq[v] = true
		if uniq.size() >= 3 and _area(tmp, g) >= AREA_MIN:
			keep.append(g)
	if keep.size() < faces.size():
		done["degenerate"] = faces.size() - keep.size()
	faces = keep
	# flipped: flood from each component's first face, turning neighbours to agree on every shared edge
	var nflip := _orient(faces, nv)
	if nflip > 0:
		done["flipped"] = nflip
	# loose verts: compact the vertex array
	var used := PackedInt32Array()
	used.resize(nv)
	used.fill(-1)
	var nverts := PackedVector3Array()
	for g in faces:
		for v in (g as PackedInt32Array):
			if used[v] < 0:
				used[v] = nverts.size()
				nverts.append(m.verts[v])
	if nverts.size() < nv:
		done["loose"] = nv - nverts.size() - nd
		if int(done["loose"]) <= 0:
			done.erase("loose")
	var out := []
	for g in faces:
		var h := PackedInt32Array()
		for v in (g as PackedInt32Array):
			h.append(used[v])
		out.append(h)
	m.from_arrays(nverts, out)
	# small holes: one face each, wound to match the border
	var nh := 0
	for l in _holes(m):
		if (l as Array).size() <= HOLE_FILL_MAX:
			m.faces.append(PackedInt32Array(l))   # the loop already runs b -> a along each border edge a -> b
			nh += 1
	if nh > 0:
		done["holes"] = nh
	m.rebuild()
	if _holes(m).is_empty() and _volume(m) < 0.0:
		for i in m.faces.size():
			var r: PackedInt32Array = m.faces[i]
			r.reverse()
			m.faces[i] = r
		m.rebuild()
		done["inside_out"] = m.faces.size()
	return done


static func _orient(faces: Array, nv: int) -> int:
	var by_edge := {}
	for fi in faces.size():
		var f: PackedInt32Array = faces[fi]
		for i in f.size():
			var k := _ekey(f[i], f[(i + 1) % f.size()], nv)
			if not by_edge.has(k):
				by_edge[k] = []
			by_edge[k].append(fi)
	var done := PackedByteArray()
	done.resize(faces.size())
	var flips := 0
	for s in faces.size():
		if done[s] == 1:
			continue
		done[s] = 1
		var q := [s]
		while not q.is_empty():
			var fi: int = q.pop_back()
			var f: PackedInt32Array = faces[fi]
			for i in f.size():
				var a := f[i]
				var b := f[(i + 1) % f.size()]
				for gi in by_edge[_ekey(a, b, nv)]:
					if gi == fi or done[gi] == 1 or (by_edge[_ekey(a, b, nv)] as Array).size() != 2:
						continue
					var g: PackedInt32Array = faces[gi]
					var same := false
					for j in g.size():
						if g[j] == a and g[(j + 1) % g.size()] == b:
							same = true
					if same:
						g.reverse()
						faces[gi] = g
						flips += 1
					done[gi] = 1
					q.append(gi)
	return flips
