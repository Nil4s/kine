class_name KMeshEdgeFlow
extends RefCounted
## EDGE FLOW TOOLS for the selected edge loops (ROADMAP_400 B18). Static ops on a KMesh: each moves ONLY the verts of the
## selected loops (positions only, no topology change: a KMeshUndo begin / commit around it is one "move" step) and
## leaves every other vert bit-exact. Proportional editing is never read: these ops act on the loops alone.
## THE LOOPS: the selected edges (KMeshCut.selected_edges: edge mode its edges, vertex mode the edges with both ends
##   selected, face mode the region's border) chained into runs. A vert where more than 2 selected edges meet ends the
##   runs through it (it stays put as an end). A run that comes back to its start is closed.
## relax(iters)    Laplacian along the loop only: one implicit (backward Euler) step of the loop's own Laplacian a pass
##                 (implicit_step, t = STEP), then each vert goes back onto the ORIGINAL surface (the nearest face of
##                 the mesh as it was before the op, within 2 rings of where the vert started, lifted onto a Phong
##                 patch through the face's vertex normals (Max's weights, see Surface), alpha 1/2:
##                 on a sphere that patch is within r theta^4 / 4 of the sphere, where the flat face sags r theta^2 / 8, so
##                 the loop stays ON the round surface, not on its facets). A plain Laplacian SHRINKS a closed loop (a
##                 circle on a sphere slides to the pole): on a closed loop the mean inward part of the step (toward the
##                 loop's centre, across the loop) is taken out, so a perfect circle does not move and only the wiggles
##                 go. Open runs keep their two ends.
## straighten      an open run's verts on the straight segment between its two ends, evenly spaced. straighten_surface:
##                 on the original surface instead: the normal section through the ends (the plane holding both ends
##                 and their mean normal; each chord point cast across the chord in it onto the mesh through
##                 KMeshShrinkwrap's BVH and lifted as relax does), the verts spaced evenly by arc length along that
##                 curve: a great-circle arc on a sphere. (The NEAREST point of a faceted mesh to a point deep under it
##                 snaps toward the facet centres: 3.3 mm off the great circle on the test sphere; the cast does not.)
##                 A closed loop has no ends: skipped.
## set_flow(s)     Maya's Edge Flow: each loop vert v with the 4 quads of a regular grid round it has two ring
##                 neighbours u, w across the loop (and uu, ww one step further on that ring). The cubic Hermite through
##                 u and w, with the tangent at u of the circle through uu, u, w (and at w of u, w, ww; a chord where the
##                 ring stops) scaled by |w - u|, is evaluated at v's own fraction |v - u| / (|v - u| + |w - v|); v moves
##                 s (0..1) of the way to it. All targets come from the positions before the op (no order effects).
## even_space      the verts redistributed by arc length along the loop's own polyline (its edges: they stay on the
##                 surface): open runs keep their ends, a closed loop keeps its first vert.
## Each op returns {"loops": n, "moved": verts that moved, "error": ""}. op(name, host) is the MeshTools entry: one
## KMeshUndo step on the model preview's mesh. Tests: tests/edgeflow_test.gd. Behaviour from Maya's / Blender
## LoopTools' manuals; no code of either.

const STEP := 2.0             # relax: the implicit step t of one pass (see implicit_step)
const RELAX_ITERS := 10       # the MeshTools row's iterations
const PHONG := 0.5            # the Phong patch's blend (1/2 keeps a sphere round to 4th order)
const RINGS := 2              # how far round a vert its candidate faces reach
const OPS := {"edgeflow_relax": "relax", "edgeflow_straighten": "straighten", "edgeflow_straighten_surface": "straighten on the surface",
	"edgeflow_flow": "set flow", "edgeflow_space": "even spacing"}


# ---------------------------------------------------------------- the loops

## the runs of the selected edges: [{"verts": PackedInt32Array in order, "closed": bool}]
static func loops_of(m: KMesh, sel: KMeshSelect) -> Array:
	return chains(KMeshCut.selected_edges(m, sel))


## edges (Vector2i) -> runs: a vert of degree != 2 ends every run through it
static func chains(es: Array) -> Array:
	var adj := {}
	for e in es:
		var k := e as Vector2i
		if k.x == k.y:
			continue
		if not adj.has(k.x):
			adj[k.x] = []
		if not adj.has(k.y):
			adj[k.y] = []
		adj[k.x].append(k.y)
		adj[k.y].append(k.x)
	var used := {}
	var out := []
	for v in adj:   # open runs first: from every end / junction
		if (adj[v] as Array).size() == 2:
			continue
		for n in adj[v]:
			if used.has(KMeshSelect.ekey(v, n)):
				continue
			var run := PackedInt32Array([v])
			var a: int = v
			var b: int = n
			while true:
				used[KMeshSelect.ekey(a, b)] = true
				run.append(b)
				if (adj[b] as Array).size() != 2:
					break
				var c: int = adj[b][0] if adj[b][0] != a else adj[b][1]
				if used.has(KMeshSelect.ekey(b, c)):
					break
				a = b
				b = c
			out.append({"verts": run, "closed": false})
	for v in adj:   # what is left: closed loops (every vert degree 2)
		for n in adj[v]:
			if used.has(KMeshSelect.ekey(v, n)):
				continue
			var run := PackedInt32Array([v])
			var a: int = v
			var b: int = n
			while true:
				used[KMeshSelect.ekey(a, b)] = true
				if b == v:
					break
				run.append(b)
				var c: int = adj[b][0] if adj[b][0] != a else adj[b][1]
				a = b
				b = c
			out.append({"verts": run, "closed": run.size() >= 3})
	return out


static func _done(m: KMesh, vs: PackedVector3Array, before: PackedVector3Array, n: int) -> Dictionary:
	var moved := 0
	for i in vs.size():
		if vs[i] != before[i]:
			moved += 1
	if moved > 0:
		m.verts = vs
		m._fresh()
		m._compute_normals()
	return {"loops": n, "moved": moved, "error": ""}


static func _none(msg: String) -> Dictionary:
	return {"loops": 0, "moved": 0, "error": msg}


# ---------------------------------------------------------------- the original surface

## The mesh as it was, for putting a vert back onto it: positions, vertex normals and triangles (fans of the faces).
## The normals are Max's (1999: each corner's cross product over |e1|^2 |e2|^2), exact for verts on a sphere, where the
## mesh's own area-weighted normals tilt wherever the faces are uneven (a jittered loop's faces put relaxed verts 0.8 mm
## off the sphere with them). The Phong lift uses the normal twice, so its sign (the winding) does not matter.
class Surface:
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var m: KMesh
	var _tris := {}   # vert -> PackedInt32Array of triangle corners (flat, 3 per triangle) within RINGS of it
	var _fan := PackedInt32Array()   # every face fanned (the order KMeshShrinkwrap.build uses)
	var _bvh: KMeshShrinkwrap

	func _init(p_m: KMesh) -> void:
		m = p_m
		vs = m.verts.duplicate()
		ns.resize(vs.size())
		for f in m.faces:
			var fp: PackedInt32Array = f
			var k := fp.size()
			for i in k:
				var c := vs[fp[i]]
				var e1 := vs[fp[(i + 1) % k]] - c
				var e2 := vs[fp[(i + k - 1) % k]] - c
				var w := e1.length_squared() * e2.length_squared()
				if w > 1e-30:
					ns[fp[i]] += e1.cross(e2) / w
			for i in range(1, k - 1):
				_fan.append_array([fp[0], fp[i], fp[i + 1]])
		for i in ns.size():
			ns[i] = ns[i].normalized()

	## the triangles near vert v (cached)
	func near(v: int) -> PackedInt32Array:
		if _tris.has(v):
			return _tris[v]
		var ring := {v: true}
		var front := [v]
		for _r in RINGS:
			var nx := []
			for a in front:
				for b in m.vert_neighbors(a):
					if not ring.has(b):
						ring[b] = true
						nx.append(b)
			front = nx
		var fs := {}
		for a in ring:
			for fi in m.vert_faces(a):
				fs[fi] = true
		var t := PackedInt32Array()
		for fi in fs:
			var f: PackedInt32Array = m.faces[fi]
			for k in range(1, f.size() - 1):
				t.append_array([f[0], f[k], f[k + 1]])
		_tris[v] = t
		return t

	## p lifted from the flat point q of triangle (a, b, c) at barycentric bb onto its Phong patch
	func _lift(q: Vector3, bb: Vector3, a: int, b: int, c: int) -> Vector3:
		var lift := Vector3.ZERO
		var ids := [a, b, c]
		for k in 3:
			var n: Vector3 = ns[ids[k]]
			lift += -((q - vs[ids[k]]).dot(n)) * n * bb[k]
		return q + lift * PHONG

	## p put onto the surface: near vert v (v >= 0: its faces within RINGS, so a vert never jumps to another part of
	## the mesh) or anywhere (v < 0: the nearest point of the whole mesh, through a BVH); the nearest flat triangle,
	## lifted onto its Phong patch
	func project(p: Vector3, v: int) -> Vector3:
		if v < 0:
			if _bvh == null:
				_bvh = KMeshShrinkwrap.build(m, Transform3D.IDENTITY, false)
			var h := _bvh.nearest(p)
			if h.is_empty():
				return p
			var src: int = _bvh.tsrc[h["t"]]
			return _lift(h["p"], h["b"], _fan[src * 3], _fan[src * 3 + 1], _fan[src * 3 + 2])
		var t := near(v)
		var best := INF
		var bq := p
		var bb := Vector3.ZERO
		var bi := -1
		for i in range(0, t.size(), 3):
			var r := KMeshEdgeFlow.closest_tri(p, vs[t[i]], vs[t[i + 1]], vs[t[i + 2]])
			var q: Vector3 = vs[t[i]] * r.x + vs[t[i + 1]] * r.y + vs[t[i + 2]] * r.z
			var d := q.distance_squared_to(p)
			if d < best:
				best = d
				bq = q
				bb = r
				bi = i
		if bi < 0:
			return p
		return _lift(bq, bb, t[bi], t[bi + 1], t[bi + 2])


## barycentric coordinates of the point of triangle abc nearest p (Ericson, Real-Time Collision Detection 5.1.5)
static func closest_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return Vector3(1, 0, 0)
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return Vector3(0, 1, 0)
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		var t := d1 / (d1 - d3)
		return Vector3(1.0 - t, t, 0)
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return Vector3(0, 0, 1)
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		var t := d2 / (d2 - d6)
		return Vector3(1.0 - t, 0, t)
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		var t := (d4 - d3) / ((d4 - d3) + (d5 - d6))
		return Vector3(0, 1.0 - t, t)
	var den := 1.0 / (va + vb + vc)
	var v := vb * den
	var w := vc * den
	return Vector3(1.0 - v - w, v, w)


# ---------------------------------------------------------------- relax

## one implicit Laplacian step along a run (Desbrun et al. 1999, backward Euler): solves
## (1 + t) q_i - t / 2 (q_i-1 + q_i+1) = p_i for q (closed: cyclic; open: the ends fixed). Unconditionally stable, and a
## pass damps a slow mode (an ellipse of the loop) far more than an explicit half step can (explicit is held at 1/2 by
## the fastest mode); tridiagonal (Thomas), cyclic by Sherman-Morrison.
static func implicit_step(p: PackedVector3Array, closed: bool, t: float) -> PackedVector3Array:
	var n := p.size()
	var lo := -t * 0.5
	var di := 1.0 + t
	if not closed:
		var q := p.duplicate()
		var m := n - 2
		if m <= 0:
			return q
		var rhs := PackedVector3Array()
		rhs.resize(m)
		for i in m:
			rhs[i] = p[i + 1]
		rhs[0] -= lo * p[0]
		rhs[m - 1] -= lo * p[n - 1]
		var x := _thomas(lo, di, lo, rhs, di, di)
		for i in m:
			q[i + 1] = x[i]
		return q
	# cyclic: A = T + u v^T with T tridiagonal (corners folded in), Sherman-Morrison
	var g := -di
	var b0 := di - g
	var bn := di - lo * lo / g
	var y := _thomas(lo, di, lo, p, b0, bn)
	var u := PackedVector3Array()
	u.resize(n)
	u[0] = Vector3.ONE * g
	u[n - 1] = Vector3.ONE * lo
	var z := _thomas(lo, di, lo, u, b0, bn)
	var fy := y[0] + y[n - 1] * (lo / g)
	var fz: float = z[0].x + z[n - 1].x * (lo / g)
	var k := fy / (1.0 + fz)
	var q := PackedVector3Array()
	q.resize(n)
	for i in n:
		q[i] = y[i] - k * z[i].x
	return q


## tridiagonal solve, constant off-diagonals a (below) and c (above), diagonal d (the first b0, the last bn)
static func _thomas(a: float, d: float, c: float, r: PackedVector3Array, b0: float, bn: float) -> PackedVector3Array:
	var n := r.size()
	var cp := PackedFloat64Array()
	cp.resize(n)
	var x := PackedVector3Array()
	x.resize(n)
	var bi := b0 if n > 1 else bn
	cp[0] = c / bi
	x[0] = r[0] / bi
	for i in range(1, n):
		var di := bn if i == n - 1 else d
		var den := di - a * cp[i - 1]
		cp[i] = c / den
		x[i] = (r[i] - x[i - 1] * a) / den
	for i in range(n - 2, -1, -1):
		x[i] -= x[i + 1] * cp[i]
	return x


static func relax(m: KMesh, loops: Array, iters := RELAX_ITERS) -> Dictionary:
	if loops.is_empty():
		return _none("no edge loop selected: select the edges of a loop (or the verts along it)")
	var before := m.verts
	var vs := m.verts.duplicate()
	var surf := Surface.new(m)
	for lp in loops:
		var ids: PackedInt32Array = lp["verts"]
		var closed: bool = lp["closed"]
		var n := ids.size()
		if n < 3:
			continue
		var p := PackedVector3Array()
		for v in ids:
			p.append(vs[v])
		for _it in maxi(iters, 0):
			var q := implicit_step(p, closed, STEP)
			if closed:   # take out the mean inward pull (toward the loop's centre, across it): a round loop keeps its size
				var c := Vector3.ZERO
				for x in p:
					c += x
				c /= n
				var us := PackedVector3Array()
				us.resize(n)
				var kbar := 0.0
				for i in n:
					var tg := (p[(i + 1) % n] - p[(i + n - 1) % n]).normalized()
					var toc := c - p[i]
					us[i] = (toc - toc.dot(tg) * tg).normalized()
					kbar += (q[i] - p[i]).dot(us[i])
				kbar /= n
				for i in n:
					q[i] -= us[i] * kbar
			for i in n:
				if not closed and (i == 0 or i == n - 1):
					continue
				p[i] = surf.project(q[i], ids[i])
		for i in n:
			vs[ids[i]] = p[i]
	return _done(m, vs, before, loops.size())


# ---------------------------------------------------------------- straighten

## the point of the surface on the line through o along d (the hit nearest o, lifted), else the nearest point
static func _on_plane(surf: Surface, o: Vector3, d: Vector3) -> Vector3:
	if surf._bvh == null:
		surf._bvh = KMeshShrinkwrap.build(surf.m, Transform3D.IDENTITY, false)
	var h := surf._bvh.cast(o, d, -KMeshShrinkwrap.FAR, KMeshShrinkwrap.FAR)
	if h.is_empty():
		return surf.project(o, -1)
	var src: int = surf._bvh.tsrc[h["tri"]]
	return surf._lift(h["p"], h["b"], surf._fan[src * 3], surf._fan[src * 3 + 1], surf._fan[src * 3 + 2])


static func straighten(m: KMesh, loops: Array, on_surface := false) -> Dictionary:
	if loops.is_empty():
		return _none("no edge loop selected: select the edges of a run (or the verts along it)")
	var before := m.verts
	var vs := m.verts.duplicate()
	var surf: Surface = Surface.new(m) if on_surface else null
	var open := 0
	for lp in loops:
		var ids: PackedInt32Array = lp["verts"]
		if lp["closed"] or ids.size() < 3:
			continue
		open += 1
		var n := ids.size() - 1
		var a := vs[ids[0]]
		var b := vs[ids[n]]
		if not on_surface:
			for i in range(1, n):
				vs[ids[i]] = a.lerp(b, float(i) / n)
			continue
		# on the surface: the normal section through the ends (the plane holding a, b and their mean normal: on a
		# sphere it holds the centre, a great circle). Each chord point is cast across the chord in that plane onto the
		# surface; the verts then go at even arc length along that curve.
		var e := (b - a).normalized()
		var nn := surf.ns[ids[0]] + surf.ns[ids[n]]
		var dn := nn - nn.dot(e) * e
		if dn.length_squared() < 1e-20:
			dn = (vs[ids[n / 2]] - a) - (vs[ids[n / 2]] - a).dot(e) * e
		dn = dn.normalized()
		var k := n * 16
		var pts := PackedVector3Array()
		var arc := PackedFloat64Array([0.0])
		for j in k + 1:
			var q := a if j == 0 else (b if j == k else _on_plane(surf, a.lerp(b, float(j) / k), dn))
			if j > 0:
				arc.append(arc[j - 1] + q.distance_to(pts[j - 1]))
			pts.append(q)
		var total := arc[k]
		var at := 0
		for i in range(1, n):
			var want := total * i / n
			while at < k - 1 and arc[at + 1] < want:
				at += 1
			var f := (want - arc[at]) / maxf(arc[at + 1] - arc[at], 1e-30)
			vs[ids[i]] = _on_plane(surf, a.lerp(b, (float(at) + f) / k), dn)
	if open == 0:
		return _none("straighten needs an open run (two ends): a closed loop has none")
	return _done(m, vs, before, open)


# ---------------------------------------------------------------- set flow

## arriving at b along a->b on a regular quad grid (4 quads round b): the vert straight on, or -1
static func through(m: KMesh, a: int, b: int) -> int:
	var nb := m.vert_neighbors(b)
	if nb.size() != 4 or m.vert_faces(b).size() != 4:
		return -1
	var skip := {a: true}
	for fi in m.vert_faces(b):
		var f: PackedInt32Array = m.faces[fi]
		if f.size() != 4:
			return -1
		var i := f.find(b)
		if f[(i + 1) % 4] == a or f[(i + 3) % 4] == a:
			skip[f[(i + 1) % 4]] = true
			skip[f[(i + 3) % 4]] = true
	var rest := -1
	for n in nb:
		if not skip.has(n):
			if rest != -1:
				return -1
			rest = n
	return rest


## the tangent at q of the circle through p, q, r (p or r = null-ish: the chord)
static func _tan(p: Vector3, q: Vector3, r: Vector3, has_p: bool) -> Vector3:
	if not has_p:
		return (r - q).normalized()
	var l0 := q.distance_to(p)
	var l1 := r.distance_to(q)
	if l0 < 1e-12 or l1 < 1e-12:
		return (r - q).normalized()
	return ((q - p) * (l1 / l0) + (r - q) * (l0 / l1)).normalized()


static func set_flow(m: KMesh, loops: Array, strength := 1.0) -> Dictionary:
	if loops.is_empty():
		return _none("no edge loop selected: select the edges of a loop (or the verts along it)")
	var s := clampf(strength, 0.0, 1.0)
	var before := m.verts
	var src := m.verts
	var vs := m.verts.duplicate()
	for lp in loops:
		var ids: PackedInt32Array = lp["verts"]
		var closed: bool = lp["closed"]
		var n := ids.size()
		for i in n:
			var v: int = ids[i]
			var a: int = ids[(i + n - 1) % n] if (closed or i > 0) else -1
			var b: int = ids[(i + 1) % n] if (closed or i < n - 1) else -1
			if a == -1:
				a = through(m, b, v)
			if b == -1:
				b = through(m, a, v)
			if a == -1 or b == -1 or m.vert_faces(v).size() != 4:
				continue
			if through(m, a, v) != b:   # the run turns a corner here: no ring across it
				continue
			var cross := []
			for x in m.vert_neighbors(v):
				if x != a and x != b:
					cross.append(x)
			if cross.size() != 2:
				continue
			var u: int = cross[0]
			var w: int = cross[1]
			var uu := through(m, v, u)
			var ww := through(m, v, w)
			var pu := src[u]
			var pw := src[w]
			var pv := src[v]
			var L := pu.distance_to(pw)
			if L < 1e-12:
				continue
			var tu := _tan(src[uu] if uu >= 0 else pu, pu, pw, uu >= 0) * L
			var tw := -_tan(src[ww] if ww >= 0 else pw, pw, pu, ww >= 0) * L
			var du := pv.distance_to(pu)
			var dw := pv.distance_to(pw)
			var t := du / maxf(du + dw, 1e-12)
			var t2 := t * t
			var t3 := t2 * t
			var h := pu * (2 * t3 - 3 * t2 + 1) + tu * (t3 - 2 * t2 + t) + pw * (-2 * t3 + 3 * t2) + tw * (t3 - t2)
			vs[v] = pv.lerp(h, s)
	return _done(m, vs, before, loops.size())


# ---------------------------------------------------------------- even spacing

static func even_space(m: KMesh, loops: Array) -> Dictionary:
	if loops.is_empty():
		return _none("no edge loop selected: select the edges of a loop (or the verts along it)")
	var before := m.verts
	var vs := m.verts.duplicate()
	for lp in loops:
		var ids: PackedInt32Array = lp["verts"]
		var closed: bool = lp["closed"]
		var n := ids.size()
		if n < 3:
			continue
		var pts := PackedVector3Array()
		for v in ids:
			pts.append(vs[v])
		if closed:
			pts.append(pts[0])
		var arc := PackedFloat64Array([0.0])
		for j in range(1, pts.size()):
			arc.append(arc[j - 1] + pts[j].distance_to(pts[j - 1]))
		var segs := pts.size() - 1
		var total := arc[segs]
		var j := 0
		for i in range(1, n if closed else n - 1):
			var want := total * i / segs
			while j < segs - 1 and arc[j + 1] < want:
				j += 1
			var f := (want - arc[j]) / maxf(arc[j + 1] - arc[j], 1e-30)
			vs[ids[i]] = pts[j].lerp(pts[j + 1], f)
	return _done(m, vs, before, loops.size())


# ---------------------------------------------------------------- the MeshTools entry

## one op on the selected loops of the model preview's mesh, one KMeshUndo step. -> what it said
static func op(name: String, host) -> String:
	var ui = host.kmed
	var loops := loops_of(ui.mesh, ui.sel)
	ui.undo.begin(ui.mesh)
	var r: Dictionary
	match name:
		"edgeflow_relax":
			r = relax(ui.mesh, loops, RELAX_ITERS)
		"edgeflow_straighten":
			r = straighten(ui.mesh, loops, false)
		"edgeflow_straighten_surface":
			r = straighten(ui.mesh, loops, true)
		"edgeflow_flow":
			r = set_flow(ui.mesh, loops, 1.0)
		"edgeflow_space":
			r = even_space(ui.mesh, loops)
		_:
			r = _none("no edge flow op '%s'" % name)
	ui.undo.commit("Edge flow: " + String(OPS.get(name, name)))
	if r["error"] != "":
		return "Model: " + String(r["error"])
	if int(r["moved"]) > 0 and ui.view != null:
		ui.view.mark_dirty()
	return "Model: %s on %d loop%s: %d verts moved (one undo step)" % [OPS[name], r["loops"], "" if r["loops"] == 1 else "s", r["moved"]]
