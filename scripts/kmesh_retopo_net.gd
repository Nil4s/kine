class_name KMeshRetopoNet
extends RefCounted
## I11: the CURVE NETWORK of stroke-guided retopology (Takayama, Panozzo, Sorkine-Hornung, Sorkine-Hornung 2013, "Sketch-Based
## Generation and Editing of Quad Meshes", ACM TOG 32(4)). Strokes lie on the source surface. Where two meet (within TOL x spacing,
## or an end within SNAP x spacing of another stroke) they intersect: a NODE. The strokes between nodes are ARCS, an arc carries an
## edge COUNT. Dangling arcs are dropped. Round each node the arcs are sorted by angle in the tangent plane; walking the half-edges
## "turn onto the next arc clockwise from where you came" traces the faces: each cycle is a REGION. A node where the region's border
## turns by more than FLAT_TURN is a CORNER of that region (a T-junction seen from its straight side is no corner there, so the two
## arcs form one side and the shared vertex is simply a vertex of it: no T-junction in the result). A region with 2 to 6 corners is
## a PATCH (a smooth loop or one corner gets 4 / 4 virtual corners); the patch is filled by KMeshRetopoFill / KineRetopoNative.
## COUNTS: an arc's count starts at length / edge_len; a search (single and pair +-1 moves on arcs not pinned by the user) makes every
## patch feasible (KMeshRetopoFill.plan). set_count pins an arc and re-solves only the patches touching it; a patch is re-solved only
## when its border (counts + points) changed (its signature), so an edit costs only the patches it touches.

const HS_FRAC := 0.006      # stroke resampling spacing, x bbox diagonal
const TOL := 0.4            # two strokes meet when their segments pass within TOL x spacing
const CLUSTER := 2.5        # ... and hits closer than CLUSTER x spacing are one node
const SNAP := 3.0           # a stroke end within SNAP x spacing of a stroke is joined to it
const FLAT_TURN := 0.5236   # rad (30 deg): a border turning less than this is straight
const MAX_SIDES := 6
const META := "retopo_record"   # G16: the mesh meta that keeps what the retopo did at the open edges

var src: KMesh
var tris := PackedInt32Array()
var nat = null              # KineRetopoNative or null
var diag := 1.0
var hs := 0.01
var edge_len := 0.1
var iters := 20             # relaxation steps per patch (tests/sretopo_test.gd bar 4)
var closed_src := true
var open_policy := false    # G16: false = the old path (a region holding an open edge is skipped); true = boundary as side / close the hole
var src0: KMesh             # the mesh as given (src is src0 with the closed holes filled)
var holes: Array = []       # G16: [{key, n, len, diam, simple, mode, default}] one per boundary loop of src0
var hole_override := {}     # key -> "side" / "close" chosen by the user
var bstrokes := {}          # G16: negative id -> the boundary loop of a hole used as a side (closed polyline, the mesh's own vertices)
var nt_src := 0             # triangles of src0 (the fill's triangles come after them)
var strokes := {}           # id -> PackedVector3Array (resampled, on the surface)
var next_id := 1
var nodes: Array = []       # {"pos", "nrm", "hes": [half-edge ids sorted ccw]}
var arcs: Array = []        # {"a","b","pts","len","count","pinned","stroke","patches"}
var patches: Array = []     # see _make_patch
var apts: Array = []        # per arc: PackedVector3Array (count + 1 points on the surface)
var vbase := PackedInt32Array()
var nverts := 0
var notes: Array = []       # what the last rebuild dropped / skipped
var solve_calls := 0        # patches solved (native or GDScript) since setup
var last_ms := 0.0          # C++ time of the last solve_patches call
var _he_next := PackedInt32Array()
var _pinned_mid: Array = [] # [{"mid", "len", "count"}] kept across rebuilds
var _old_patches := {}      # sig -> patch
var _tri_adj := PackedInt32Array()
var _mean_edge := 0.01


func setup(mesh: KMesh, p_edge_len := -1.0, open := false) -> void:
	open_policy = open
	src0 = mesh
	hole_override = {}
	strokes = {}
	_setup_core(p_edge_len)


func _setup_core(p_edge_len: float) -> void:
	var mesh := src0
	var bb := AABB(mesh.verts[0], Vector3.ZERO)
	for v in mesh.verts:
		bb = bb.expand(v)
	diag = bb.size.length()
	hs = diag * HS_FRAC
	edge_len = p_edge_len if p_edge_len > 0.0 else diag / 14.0
	nt_src = 0
	for f in mesh.faces:
		nt_src += f.size() - 2
	var work := mesh
	holes = []
	bstrokes = {}
	if open_policy:
		var to_close: Array = []
		for lp in KMeshHoles.loops(mesh):
			lp["default"] = lp["mode"]
			if hole_override.has(lp["key"]) and lp["simple"]:
				lp["mode"] = hole_override[lp["key"]]
			holes.append(lp)
			if lp["simple"] and lp["mode"] == KMeshHoles.MODE_CLOSE:
				to_close.append(lp)
			elif lp["simple"]:
				var pl := PackedVector3Array()
				for v in lp["verts"]:
					pl.append(mesh.verts[v])
				pl.append(mesh.verts[lp["verts"][0]])
				bstrokes[-1 - holes.size() + 1] = pl
		if not to_close.is_empty():
			work = KMeshHoles.close(mesh, to_close)
	src = work
	tris = PackedInt32Array()
	for f in work.faces:
		for k in range(1, f.size() - 1):
			tris.append(f[0])
			tris.append(f[k])
			tris.append(f[k + 1])
	closed_src = work.boundary_edge_count() == 0
	nat = null
	_tri_adj = PackedInt32Array()
	if NativeExt.ensure("kine_native", "KineRetopoNative"):
		nat = ClassDB.instantiate("KineRetopoNative")
		nat.set_source(work.verts, tris)
	_clear_derived()
	solve_calls = 0


## G16: change what one hole does ("side" / "close"); the strokes stay (put back on the new surface) and the network is rebuilt
func set_hole_mode(key: int, mode: String) -> bool:
	var found := false
	for h in holes:
		if h["key"] == key and h["simple"]:
			found = true
	if not found or (mode != KMeshHoles.MODE_SIDE and mode != KMeshHoles.MODE_CLOSE):
		return false
	hole_override[key] = mode
	_setup_core(edge_len)
	for id in strokes.keys():
		strokes[id] = project(strokes[id])["pts"]
	rebuild()
	return true


## G16: what the retopo did about the open edges, for the undo step and the file
func record() -> Dictionary:
	var hs_: Array = []
	for h in holes:
		hs_.append({"key": h["key"], "n": h["n"], "mode": h["mode"], "default": h["default"], "simple": h["simple"]})
	var rs: Array = []
	for i in patches.size():
		var p: Dictionary = patches[i]
		if p["valid"]:
			rs.append({"patch": i, "mode": String(p.get("mode", "none")), "ok": bool(p["ok"])})
	return {"policy": open_policy, "holes": hs_, "regions": rs, "skipped": skipped_regions().size()}


func _clear_derived() -> void:
	nodes = []
	arcs = []
	patches = []
	apts = []
	_old_patches = {}
	_pinned_mid = []


# ------------------------------------------------------------------ projection
func project(pts: PackedVector3Array) -> Dictionary:
	var out := PackedVector3Array()
	var nr := PackedVector3Array()
	out.resize(pts.size())
	nr.resize(pts.size())
	if nat != null:
		var flat := PackedFloat64Array()
		flat.resize(pts.size() * 3)
		for i in pts.size():
			flat[i * 3] = pts[i].x
			flat[i * 3 + 1] = pts[i].y
			flat[i * 3 + 2] = pts[i].z
		var r: Dictionary = nat.project(flat)
		var q: PackedFloat64Array = r["pts"]
		var nn: PackedFloat64Array = r["normals"]
		for i in pts.size():
			out[i] = Vector3(q[i * 3], q[i * 3 + 1], q[i * 3 + 2])
			nr[i] = Vector3(nn[i * 3], nn[i * 3 + 1], nn[i * 3 + 2])
	else:
		for i in pts.size():   # GDScript fallback: the nearest source vertex (no native solver built)
			var bi := 0
			var bd := INF
			for v in src.verts.size():
				var d := pts[i].distance_squared_to(src.verts[v])
				if d < bd:
					bd = d
					bi = v
			out[i] = src.verts[bi]
			nr[i] = src.vert_normals[bi]
	return {"pts": out, "nrm": nr}


# ------------------------------------------------------------------ strokes
## resample to even spacing and put on the surface
func _resample(pts: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	if pts.size() < 2:
		return out
	var cum := [0.0]
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
	var total: float = cum[cum.size() - 1]
	if total < hs * 2.0:
		return out
	var n := maxi(2, int(round(total / hs)))
	var seg := 0
	for k in n + 1:
		var s: float = total * float(k) / float(n)
		while seg < pts.size() - 2 and cum[seg + 1] < s:
			seg += 1
		var l: float = cum[seg + 1] - cum[seg]
		var t := 0.0 if l < 1e-12 else clampf((s - cum[seg]) / l, 0.0, 1.0)
		out.append(pts[seg].lerp(pts[seg + 1], t))
	return project(out)["pts"]


func add_stroke(pts: PackedVector3Array) -> int:
	var r := _resample(pts)
	if r.size() < 2:
		return -1
	var id := next_id
	next_id += 1
	strokes[id] = r
	rebuild()
	return id


func delete_stroke(id: int) -> bool:
	if not strokes.has(id):
		return false
	strokes.erase(id)
	rebuild()
	return true


# ------------------------------------------------------------------ geometry
static func _seg_seg(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> Array:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-14 and e <= 1e-14:
		return [p1.distance_to(p2), 0.0, 0.0]
	if a <= 1e-14:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-14:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var den := a * e - b * b
			if den > 1e-14:
				s = clampf((b * f - c * e) / den, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return [(p1 + d1 * s).distance_to(p2 + d2 * t), s, t]


func _cum(pl: PackedVector3Array) -> PackedFloat64Array:
	var c := PackedFloat64Array()
	c.resize(pl.size())
	for i in range(1, pl.size()):
		c[i] = c[i - 1] + pl[i].distance_to(pl[i - 1])
	return c


func _at(pl: PackedVector3Array, cum: PackedFloat64Array, s: float) -> Vector3:
	if s <= 0.0:
		return pl[0]
	if s >= cum[cum.size() - 1]:
		return pl[pl.size() - 1]
	var lo := 0
	var hi := cum.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid
	var l := cum[hi] - cum[lo]
	return pl[lo].lerp(pl[hi], 0.0 if l < 1e-12 else (s - cum[lo]) / l)


## the sub-polyline of pl between arclengths s0 < s1
func _slice(pl: PackedVector3Array, cum: PackedFloat64Array, s0: float, s1: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.append(_at(pl, cum, s0))
	for i in pl.size():
		if cum[i] > s0 + 1e-9 and cum[i] < s1 - 1e-9:
			out.append(pl[i])
	out.append(_at(pl, cum, s1))
	return out


func _poly_len(pl: PackedVector3Array) -> float:
	var l := 0.0
	for i in range(1, pl.size()):
		l += pl[i].distance_to(pl[i - 1])
	return l


# ------------------------------------------------------------------ rebuild
func rebuild() -> void:
	notes = []
	var keep_arcs: Array = []
	for a in arcs:   # remember the counts the user set (and the auto ones: they are matched by place, kept)
		keep_arcs.append({"mid": _mid(a["pts"]), "len": a["len"], "count": a["count"], "pinned": a["pinned"]})
	for p in patches:
		if p.get("sig", "") != "" and p.get("ok", false):
			_old_patches[p["sig"]] = p
	nodes = []
	arcs = []
	patches = []
	if strokes.is_empty():
		return
	var ids := strokes.keys()
	ids.sort()
	var sk := {}   # the strokes as used here (the drawn ones are kept as drawn: a rebuild must not grow them)
	for id in ids:
		sk[id] = strokes[id]
	for bid in bstrokes:   # G16: a boundary loop used as a side joins the network as a stroke made of the mesh's own vertices
		ids.append(bid)
		sk[bid] = bstrokes[bid]
	# 1 ends: join a stroke end that is near another stroke by one more point on it
	for id in ids:
		var pl: PackedVector3Array = sk[id]
		for end in [0, 1]:
			var pe: Vector3 = pl[0] if end == 0 else pl[pl.size() - 1]
			var best := SNAP * hs
			var bp := Vector3.ZERO
			var found := false
			var cum := _cum(pl)
			for id2 in ids:
				var q: PackedVector3Array = sk[id2]
				var cq := _cum(q)
				for i in q.size() - 1:
					if id2 == id:
						var sa: float = cum[i] if end == 0 else cum[cum.size() - 1] - cum[i + 1]
						if sa < 4.0 * hs:
							continue
					var ab := q[i + 1] - q[i]
					var l2 := ab.length_squared()
					var t := 0.0 if l2 < 1e-14 else clampf((pe - q[i]).dot(ab) / l2, 0.0, 1.0)
					var c := q[i] + ab * t
					var d := pe.distance_to(c)
					if d < best:
						best = d
						bp = c
						found = true
			if found and best > 1e-7:
				var np := PackedVector3Array()
				if end == 0:
					np.append(project(PackedVector3Array([bp]))["pts"][0])
					np.append_array(pl)
				else:
					np.append_array(pl)
					np.append(project(PackedVector3Array([bp]))["pts"][0])
				pl = np
				sk[id] = pl
	# 2 hits: segment pairs that pass within TOL x hs, found with a hash grid
	var segs: Array = []   # [stroke, i, p, q, s0, s1]
	var cums := {}
	for id in ids:
		var pl2: PackedVector3Array = sk[id]
		var cu := _cum(pl2)
		cums[id] = cu
		for i in pl2.size() - 1:
			segs.append([id, i, pl2[i], pl2[i + 1], cu[i], cu[i + 1]])
	var cell := 3.0 * hs
	var grid := {}
	var hits: Array = []   # [pos, stroke_a, param_a, stroke_b, param_b]
	for si in segs.size():
		var sg: Array = segs[si]
		var lo: Vector3 = (sg[2] as Vector3).min(sg[3]) - Vector3.ONE * TOL * hs
		var hi: Vector3 = (sg[2] as Vector3).max(sg[3]) + Vector3.ONE * TOL * hs
		var seen := {}
		for x in range(int(floor(lo.x / cell)), int(floor(hi.x / cell)) + 1):
			for y in range(int(floor(lo.y / cell)), int(floor(hi.y / cell)) + 1):
				for z in range(int(floor(lo.z / cell)), int(floor(hi.z / cell)) + 1):
					var key := Vector3i(x, y, z)
					if grid.has(key):
						for sj in grid[key]:
							if seen.has(sj):
								continue
							seen[sj] = true
							var o: Array = segs[sj]
							if o[0] == sg[0] and absi(int(o[1]) - int(sg[1])) <= 2:
								continue
							var r := _seg_seg(sg[2], sg[3], o[2], o[3])
							if r[0] < TOL * hs:
								var pa: Vector3 = (sg[2] as Vector3).lerp(sg[3], r[1])
								var pb: Vector3 = (o[2] as Vector3).lerp(o[3], r[2])
								hits.append([(pa + pb) * 0.5, sg[0], lerpf(sg[4], sg[5], r[1]), o[0], lerpf(o[4], o[5], r[2])])
					else:
						grid[key] = []
					if not grid.has(key):
						grid[key] = []
					(grid[key] as Array).append(si)
	# 3 nodes: cluster the hits by position
	var cl := []   # cluster id per hit
	cl.resize(hits.size())
	cl.fill(-1)
	var groups: Array = []
	for i in hits.size():
		if cl[i] >= 0:
			continue
		var g := [i]
		cl[i] = groups.size()
		var qi := 0
		while qi < g.size():
			var hq: Array = hits[g[qi]]
			qi += 1
			for j in hits.size():
				if cl[j] < 0 and (hits[j][0] as Vector3).distance_to(hq[0]) < CLUSTER * hs:
					cl[j] = groups.size()
					g.append(j)
		groups.append(g)
	var node_pos := PackedVector3Array()
	var node_tags: Array = []   # per node: {stroke: [params]}
	for g in groups:
		var c := Vector3.ZERO
		var tags := {}
		for hi2 in g:
			var h: Array = hits[hi2]
			c += h[0]
			for k in [1, 3]:
				if not tags.has(h[k]):
					tags[h[k]] = []
				(tags[h[k]] as Array).append(h[k + 1])
		node_pos.append(c / float(g.size()))
		node_tags.append(tags)
	var pr := project(node_pos)
	node_pos = pr["pts"]
	for i in node_pos.size():
		nodes.append({"pos": node_pos[i], "nrm": (pr["nrm"] as PackedVector3Array)[i], "hes": []})
	# 4 arcs: along each stroke between consecutive node tags
	for id in ids:
		var pl3: PackedVector3Array = sk[id]
		var cu3: PackedFloat64Array = cums[id]
		var tl: Array = []   # [param, node]
		for ni in nodes.size():
			var tg: Dictionary = node_tags[ni]
			if not tg.has(id):
				continue
			var ps: Array = tg[id].duplicate()
			ps.sort()
			var gp := [ps[0]]
			for k in range(1, ps.size()):
				if ps[k] - gp[gp.size() - 1] > 3.0 * hs:
					tl.append([_avg(gp), ni])
					gp = [ps[k]]
				else:
					gp.append(ps[k])
			tl.append([_avg(gp), ni])
		tl.sort_custom(func(x, y): return x[0] < y[0])
		for k in range(0, tl.size() - 1):
			var s0: float = tl[k][0]
			var s1: float = tl[k + 1][0]
			if s1 - s0 < 0.5 * hs and tl[k][1] == tl[k + 1][1]:
				continue
			if s1 - s0 < 1e-6:
				continue
			var poly := _slice(pl3, cu3, s0, s1)
			poly[0] = nodes[tl[k][1]]["pos"]
			poly[poly.size() - 1] = nodes[tl[k + 1][1]]["pos"]
			arcs.append({"a": tl[k][1], "b": tl[k + 1][1], "pts": poly, "len": _poly_len(poly), "count": 0, "pinned": false, "stroke": id, "patches": [], "old": false})
	# 5 prune dangling arcs (an end node used by this arc only)
	var changed := true
	var dropped := 0
	while changed:
		changed = false
		var deg := {}
		for a in arcs:
			deg[a["a"]] = int(deg.get(a["a"], 0)) + 1
			deg[a["b"]] = int(deg.get(a["b"], 0)) + 1
		for i in range(arcs.size() - 1, -1, -1):
			if deg[arcs[i]["a"]] == 1 or deg[arcs[i]["b"]] == 1:
				arcs.remove_at(i)
				dropped += 1
				changed = true
	if dropped > 0:
		notes.append("%d stroke piece(s) hang loose (an end joins nothing) and are left out" % dropped)
	# 6 counts: from the previous state where an arc is the same place, else length / edge_len
	for a in arcs:
		var mid := _mid(a["pts"])
		var hit := false
		for k in keep_arcs:
			if (k["mid"] as Vector3).distance_to(mid) < 0.002 * diag and absf(k["len"] - a["len"]) < 0.004 * diag:
				a["count"] = k["count"]
				a["pinned"] = k["pinned"]
				a["old"] = true
				hit = true
				break
		if not hit:
			a["count"] = maxi(1, int(round(a["len"] / edge_len)))
	_topology()
	auto_fix()
	_layout_and_solve()


func _avg(a: Array) -> float:
	var s := 0.0
	for x in a:
		s += x
	return s / float(a.size())


func _mid(pl: PackedVector3Array) -> Vector3:
	var cu := _cum(pl)
	return _at(pl, cu, cu[cu.size() - 1] * 0.5)


# ------------------------------------------------------------------ topology: rotation system, faces, corners
func _tangent(h: int, lk: float) -> Vector3:
	var a: Dictionary = arcs[h >> 1]
	var pl: PackedVector3Array = a["pts"]
	var fwd := (h & 1) == 0
	var acc := 0.0
	var n := pl.size()
	for k in range(1, n):
		var i0 := k - 1 if fwd else n - k
		var i1 := k if fwd else n - 1 - k
		acc += pl[i0].distance_to(pl[i1])
		if acc >= lk or k == n - 1:
			return (pl[i1] - pl[0 if fwd else n - 1]).normalized()
	return Vector3.RIGHT


func _he_from(h: int) -> int:
	return arcs[h >> 1]["a"] if (h & 1) == 0 else arcs[h >> 1]["b"]


func _he_to(h: int) -> int:
	return arcs[h >> 1]["b"] if (h & 1) == 0 else arcs[h >> 1]["a"]


func _angle_at(node: int, h: int) -> float:
	var n: Vector3 = nodes[node]["nrm"]
	var e1 := n.cross(Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
	var e2 := n.cross(e1)
	var t := _tangent(h, 1.5 * hs)
	return atan2(t.dot(e2), t.dot(e1))


func _signed_turn(node: int, t_in: Vector3, t_out: Vector3) -> float:
	var n: Vector3 = nodes[node]["nrm"]
	var a := t_in - n * t_in.dot(n)
	var b := t_out - n * t_out.dot(n)
	return atan2(n.dot(a.cross(b)), a.dot(b))


func _topology() -> void:
	for nd in nodes:
		nd["hes"] = []
	for ai in arcs.size():
		arcs[ai]["patches"] = []
		(nodes[arcs[ai]["a"]]["hes"] as Array).append(ai * 2)
		(nodes[arcs[ai]["b"]]["hes"] as Array).append(ai * 2 + 1)
	for ni in nodes.size():
		var hs_: Array = nodes[ni]["hes"]
		var ang := {}
		for h in hs_:
			ang[h] = _angle_at(ni, h)
		hs_.sort_custom(func(x, y): return ang[x] < ang[y])
	_he_next = PackedInt32Array()
	_he_next.resize(arcs.size() * 2)
	for h in _he_next.size():
		var v := _he_to(h)
		var tw := h ^ 1
		var lst: Array = nodes[v]["hes"]
		var k := lst.find(tw)
		_he_next[h] = lst[(k - 1 + lst.size()) % lst.size()]
	var seen := PackedByteArray()
	seen.resize(_he_next.size())
	patches = []
	for h0 in _he_next.size():
		if seen[h0] == 1:
			continue
		var ring := PackedInt32Array()
		var h := h0
		while seen[h] == 0:
			seen[h] = 1
			ring.append(h)
			h = _he_next[h]
		if h != h0:
			continue   # not a cycle (cannot happen on a permutation)
		_make_patch(ring)
	_flag_open_regions()


func _make_patch(ring: PackedInt32Array) -> void:
	var p := {"ring": ring, "corners": PackedInt32Array(), "ok": false, "reason": "", "kind": "none", "n": 0, "sig": "", "verts": PackedFloat64Array(),
			"quads": PackedInt32Array(), "nring": 0, "ring_ids": PackedInt32Array(), "valid": true, "sing": PackedInt32Array(), "n_real": 0, "solved_at": 0}
	var inring := {}
	for h in ring:
		inring[h] = true
	for h in ring:
		if inring.has(h ^ 1):
			p["valid"] = false
			p["reason"] = "a stroke inside the region joins nothing else"
	var turn_sum := 0.0
	var corners := PackedInt32Array()
	for i in ring.size():
		var h: int = ring[i]
		var hn: int = ring[(i + 1) % ring.size()]
		var v := _he_to(h)
		var t_in := -_tangent(h ^ 1, 1.5 * hs)
		var t_out := _tangent(hn, 1.5 * hs)
		var tr := _signed_turn(v, t_in, t_out)
		turn_sum += tr
		if absf(tr) > FLAT_TURN:
			corners.append((i + 1) % ring.size())   # the corner is at the START of half-edge i+1
		var pl: PackedVector3Array = arcs[h >> 1]["pts"]
		var nrm: Vector3 = nodes[v]["nrm"]
		for k in range(1, pl.size() - 1):
			var d0 := (pl[k] - pl[k - 1]) if (h & 1) == 0 else (pl[pl.size() - k - 1] - pl[pl.size() - k])
			var d1 := (pl[k + 1] - pl[k]) if (h & 1) == 0 else (pl[pl.size() - k - 2] - pl[pl.size() - k - 1])
			turn_sum += atan2(nrm.dot(d0.cross(d1)), d0.dot(d1))
	corners.sort()
	p["corners"] = corners
	p["n_real"] = corners.size()
	p["turn"] = turn_sum
	if not closed_src and turn_sum <= 0.0:
		p["valid"] = false
		p["reason"] = "the outside of a loop on an open surface"
	if corners.size() > MAX_SIDES:
		p["valid"] = false
		p["reason"] = "%d sides: more than %d" % [corners.size(), MAX_SIDES]
	if open_policy:
		var nb := 0
		for h in ring:
			if int(arcs[h >> 1]["stroke"]) < 0:
				nb += 1
		p["side"] = nb > 0
		if nb == ring.size():   # the empty side of a boundary loop is not a region at all
			p["valid"] = false
			p["outside"] = true
			p["reason"] = ""
	var pi := patches.size()
	patches.append(p)
	if p["valid"]:
		for h in ring:
			var pa: Array = arcs[h >> 1]["patches"]
			if not pa.has(pi):
				pa.append(pi)


## Not every cycle of the network bounds a disk. On an OPEN source (a scan with a hole, a bust cut at the neck) the strokes'
## outside is a region too, and it holds the hole's edge. And a band between two rings of strokes (round the neck, between a
## ring on the head and one on the chest) is traced as TWO cycles, one per ring, each of which would be filled as a disk across
## the band's opening. So: the source triangles the strokes pass through are walls, the rest is flooded into regions, each cycle
## looks at the region on its left; a region that holds a boundary edge of the source, or is claimed by more than one cycle, is
## not a patch.
func _assign_modes() -> void:
	for p in patches:
		var parts: Array = []
		if p.get("side", false):
			parts.append("boundary_side")
		if p.get("fill", false):
			parts.append("closed_hole")
		p["mode"] = "none" if parts.is_empty() else "+".join(parts)


func _flag_open_regions() -> void:
	if nat == null:
		_assign_modes()
		return
	var nt := tris.size() / 3
	if _tri_adj.size() != nt * 3:
		_tri_adj = PackedInt32Array()
		_tri_adj.resize(nt * 3)
		_tri_adj.fill(-1)
		var em := {}
		var el := 0.0
		for t in nt:
			for k in 3:
				var a := tris[t * 3 + k]
				var b := tris[t * 3 + (k + 1) % 3]
				el += src.verts[a].distance_to(src.verts[b])
				var key := mini(a, b) * 1000003 + maxi(a, b)
				if em.has(key):
					var o: Vector2i = em[key]
					_tri_adj[t * 3 + k] = o.x
					_tri_adj[o.x * 3 + o.y] = t
				else:
					em[key] = Vector2i(t, k)
		_mean_edge = el / float(nt * 3)
	var wall := PackedInt32Array()
	wall.resize(nt)   # 0 free, arc + 1, or -1 where several arcs pass
	for ai in arcs.size():
		var a: Dictionary = arcs[ai]
		var pl: PackedVector3Array = a["pts"]
		var cu := _cum(pl)
		var n := maxi(2, int(ceil(cu[cu.size() - 1] / (0.25 * _mean_edge))))
		var raw := PackedVector3Array()
		for k in n + 1:
			raw.append(_at(pl, cu, cu[cu.size() - 1] * float(k) / float(n)))
		if nat != null:
			var flat := PackedFloat64Array()
			for q in raw:
				flat.append(q.x)
				flat.append(q.y)
				flat.append(q.z)
			var tr: PackedInt32Array = nat.project(flat)["tris"]
			for t in tr:
				wall[t] = ai + 1 if wall[t] == 0 or wall[t] == ai + 1 else -1
	var comp := PackedInt32Array()
	comp.resize(nt)
	comp.fill(-1)
	var open: Array = []
	var nc := 0
	for t0 in nt:
		if wall[t0] != 0 or comp[t0] >= 0:
			continue
		var stack := [t0]
		comp[t0] = nc
		var is_open := false
		while not stack.is_empty():
			var t: int = stack.pop_back()
			for k in 3:
				var o := _tri_adj[t * 3 + k]
				if o < 0:
					is_open = true
				elif wall[o] == 0 and comp[o] < 0:
					comp[o] = nc
					stack.append(o)
		open.append(is_open)
		nc += 1
	var fill_comp := {}
	for t in range(nt_src, nt):
		if comp[t] >= 0:
			fill_comp[comp[t]] = true
	var claims := {}   # region -> [patch indices]
	for pi in patches.size():
		var p: Dictionary = patches[pi]
		if not p["valid"]:
			continue
		var c := _left_region(p, wall, comp)
		if c < 0:
			continue
		p["fill"] = fill_comp.has(c)
		if open[c]:
			p["valid"] = false
			p["reason"] = "this region holds the open edge of the mesh"
			continue
		if not claims.has(c):
			claims[c] = []
		(claims[c] as Array).append(pi)
	for c in claims:
		var lst: Array = claims[c]
		if lst.size() < 2:
			continue
		for pi in lst:
			patches[pi]["valid"] = false
			patches[pi]["reason"] = "this region is a band between two rings of strokes, not a disk: draw a stroke across it"
	for pi in patches.size():   # the arcs list only the patches that are patches
		if not patches[pi]["valid"]:
			for h in patches[pi]["ring"]:
				(arcs[h >> 1]["patches"] as Array).erase(pi)
	_assign_modes()


## the flood region on the left of a patch's first half-edges (-1: none found next to them)
func _left_region(p: Dictionary, wall: PackedInt32Array, comp: PackedInt32Array) -> int:
	var ring: PackedInt32Array = p["ring"]
	for hi in mini(ring.size(), 3):
		var h: int = ring[hi]
		var pl2: PackedVector3Array = arcs[h >> 1]["pts"]
		var cu2 := _cum(pl2)
		var tot: float = cu2[cu2.size() - 1]
		var m0 := _at(pl2, cu2, tot * 0.5)
		var m1 := _at(pl2, cu2, tot * 0.5 + 0.01 * tot)
		var tg := (m1 - m0).normalized() * (1.0 if (h & 1) == 0 else -1.0)
		var nrm: Vector3 = (project(PackedVector3Array([m0]))["nrm"] as PackedVector3Array)[0]
		var left := nrm.cross(tg).normalized()
		var own: int = (h >> 1) + 1
		var wp := m0
		for k in 24:   # walk on the surface to the left until a free triangle; another stroke's wall first = no answer here
			var q := wp + left * (0.25 * _mean_edge)
			var r: Dictionary = nat.project(PackedFloat64Array([q.x, q.y, q.z]))
			var tri: int = (r["tris"] as PackedInt32Array)[0]
			var rp: PackedFloat64Array = r["pts"]
			var rn: PackedFloat64Array = r["normals"]
			wp = Vector3(rp[0], rp[1], rp[2])
			var n2 := Vector3(rn[0], rn[1], rn[2])
			left = (left - n2 * left.dot(n2)).normalized()
			if tri < 0:
				break
			if wall[tri] == 0:
				return comp[tri]
			if wall[tri] != own:
				break
	return -1


## the edge counts of a patch's sides given the arcs' counts; [] if it has too few edges for sides
func side_counts(p: Dictionary) -> PackedInt32Array:
	var ring: PackedInt32Array = p["ring"]
	var pos := PackedInt32Array()   # cumulative count at the start of each half-edge
	var L := 0
	for h in ring:
		pos.append(L)
		L += int(arcs[h >> 1]["count"])
	var cuts := PackedInt32Array()
	var corners: PackedInt32Array = p["corners"]
	if corners.size() >= 2:
		for c in corners:
			cuts.append(pos[c])
	else:
		if L < 4:
			return PackedInt32Array()
		var r0 := pos[corners[0]] if corners.size() == 1 else 0
		cuts.append(r0)
		for k in range(1, 4):
			cuts.append((r0 + int(floor(float(k) * float(L) / 4.0 + 0.5))) % L)
	var cs := PackedInt32Array()
	for i in cuts.size():
		var d := cuts[(i + 1) % cuts.size()] - cuts[i]
		if d <= 0:
			d += L
		cs.append(d)
	return cs


func _plan_ok(p: Dictionary) -> bool:
	if not p["valid"]:
		return true   # not a patch: not our problem
	var cs := side_counts(p)
	if cs.size() < 2:
		return false
	return KMeshRetopoFill.plan(cs)["ok"]


func _bad_count(pis: Array) -> int:
	var n := 0
	for pi in pis:
		if not _plan_ok(patches[pi]):
			n += 1
	return n


## make every patch feasible by +-1 moves on arcs the user has not set (single moves first, then pairs)
func auto_fix(max_iter := 200) -> void:
	var tabu := {}
	for it in max_iter:
		var bad: Array = []
		for pi in patches.size():
			if not _plan_ok(patches[pi]):
				bad.append(pi)
		if bad.is_empty():
			return
		var cand := {}
		for pi in bad:
			for h in patches[pi]["ring"]:
				if not arcs[h >> 1]["pinned"]:
					cand[h >> 1] = true
		var best := []
		var best_score := Vector2(1e9, 1e9)
		var cl := cand.keys()
		var moves: Array = []
		for ai in cl:
			for dl in [-1, 1]:
				moves.append([[ai, dl]])
		for i in cl.size():
			for j in range(i + 1, cl.size()):
				for di in [-1, 1]:
					for dj in [-1, 1]:
						moves.append([[cl[i], di], [cl[j], dj]])
		for mv in moves:
			var key := str(mv)
			if tabu.has(key):
				continue
			var touched := {}
			var ok := true
			for e in mv:
				if arcs[e[0]]["count"] + e[1] < 1:
					ok = false
				for pi in arcs[e[0]]["patches"]:
					touched[pi] = true
			if not ok:
				continue
			var before := _bad_count(touched.keys())
			for e in mv:
				arcs[e[0]]["count"] += e[1]
			var after := _bad_count(touched.keys())
			var cost := 0.0
			for e in mv:
				cost += absf(float(arcs[e[0]]["count"]) - arcs[e[0]]["len"] / edge_len) + (5.0 if arcs[e[0]]["old"] else 0.0)
			for e in mv:
				arcs[e[0]]["count"] -= e[1]
			var sc := Vector2(float(after - before), cost + 0.01 * mv.size())
			if sc.x < best_score.x or (sc.x == best_score.x and sc.y < best_score.y):
				best_score = sc
				best = mv
			if mv.size() == 1 and sc.x < 0.0 and false:
				break
		if best.is_empty() or best_score.x > 0.0:
			return
		for e in best:
			arcs[e[0]]["count"] += e[1]
		tabu[str([best.map(func(e): return [e[0], -e[1]])])] = true
		tabu[str(best.map(func(e): return [e[0], -e[1]]))] = true


# ------------------------------------------------------------------ layout + solve
func _layout() -> void:
	vbase = PackedInt32Array()
	vbase.resize(arcs.size())
	var n := nodes.size()
	apts = []
	for ai in arcs.size():
		var a: Dictionary = arcs[ai]
		var d: int = a["count"]
		vbase[ai] = n
		n += d - 1
		var pl: PackedVector3Array = a["pts"]
		var cu := _cum(pl)
		var raw := PackedVector3Array()
		for k in range(1, d):
			raw.append(_at(pl, cu, cu[cu.size() - 1] * float(k) / float(d)))
		var pj: PackedVector3Array = project(raw)["pts"] if raw.size() > 0 else raw
		var ap := PackedVector3Array()
		ap.append(nodes[a["a"]]["pos"])
		ap.append_array(pj)
		ap.append(nodes[a["b"]]["pos"])
		apts.append(ap)
	nverts = n


func ring_of(p: Dictionary) -> Dictionary:
	var ids := PackedInt32Array()
	var pos := PackedVector3Array()
	for h in p["ring"]:
		var ai: int = h >> 1
		var d: int = arcs[ai]["count"]
		var ap: PackedVector3Array = apts[ai]
		if (h & 1) == 0:
			ids.append(arcs[ai]["a"])
			pos.append(ap[0])
			for k in range(1, d):
				ids.append(vbase[ai] + k - 1)
				pos.append(ap[k])
		else:
			ids.append(arcs[ai]["b"])
			pos.append(ap[d])
			for k in range(1, d):
				ids.append(vbase[ai] + (d - k) - 1)
				pos.append(ap[d - k])
	return {"ids": ids, "pos": pos}


## where each side starts on the ring (ring positions, as ring_of lists them)
func side_starts(p: Dictionary) -> PackedInt32Array:
	var ring: PackedInt32Array = p["ring"]
	var corners: PackedInt32Array = p["corners"]
	var starts := PackedInt32Array()
	var acc := 0
	var cum := PackedInt32Array()
	for h in ring:
		cum.append(acc)
		acc += int(arcs[h >> 1]["count"])
	var L := acc
	if corners.size() >= 2:
		for c in corners:
			starts.append(cum[c])
	else:
		var r0 := cum[corners[0]] if corners.size() == 1 else 0
		starts.append(r0)
		for k in range(1, 4):
			starts.append((r0 + int(floor(float(k) * float(L) / 4.0 + 0.5))) % L)
	return starts


func sides_of(p: Dictionary, rg: Dictionary) -> Array:
	var cs := side_counts(p)
	var pos: PackedVector3Array = rg["pos"]
	var L := pos.size()
	var starts := side_starts(p)
	var sides: Array = []
	for i in starts.size():
		var f := PackedFloat64Array()
		for k in cs[i] + 1:
			var q := pos[(starts[i] + k) % L]
			f.append(q.x)
			f.append(q.y)
			f.append(q.z)
		sides.append(f)
	return sides


func _layout_and_solve() -> void:
	_layout()
	var todo: Array = []   # [patch index, sides]
	last_ms = 0.0
	for pi in patches.size():
		var p: Dictionary = patches[pi]
		if not p["valid"]:
			continue
		var cs := side_counts(p)
		if cs.size() < 2:
			p["reason"] = "too few edges to cut into sides"
			continue
		var rg := ring_of(p)
		var sides := sides_of(p, rg)
		var ids0: PackedInt32Array = rg["ids"]
		var r0: int = side_starts(p)[0]
		var rid := PackedInt32Array()   # the fill's ring starts at the first side's start, not at ring position 0
		rid.resize(ids0.size())
		for r in ids0.size():
			rid[r] = ids0[(r0 + r) % ids0.size()]
		p["ring_ids"] = rid
		p["n"] = cs.size()
		var flat := PackedFloat64Array()
		for s in sides:
			flat.append_array(s)
		var sig := "%d:%d:%d" % [cs.size(), flat.size(), hash(flat)]
		p["sig"] = sig
		var pl := KMeshRetopoFill.plan(cs)
		p["kind"] = pl["kind"]
		if not pl["ok"]:
			p["reason"] = pl["reason"]
			p["ok"] = false
			continue
		if _old_patches.has(sig):
			var o: Dictionary = _old_patches[sig]
			for k in ["verts", "quads", "nring", "sing", "ok", "reason", "kind", "solved_at"]:
				p[k] = o.get(k, 0)
			continue
		todo.append([pi, sides])
	if todo.is_empty():
		return
	for t in todo:
		var r: Dictionary
		if nat != null:
			r = nat.solve_patch(t[1], iters)
		else:
			r = KMeshRetopoFill.fill(t[1])
		solve_calls += 1
		last_ms += float(r.get("ms", 0.0))
		var p2: Dictionary = patches[t[0]]
		p2["ok"] = r["ok"]
		p2["reason"] = r["reason"]
		p2["solved_at"] = solve_calls
		if r["ok"]:
			p2["verts"] = r["verts"]
			p2["quads"] = r["quads"]
			p2["nring"] = r["nring"]
			p2["sing"] = r["singular"]
			var folded := _folded(r["verts"], r["quads"])
			if folded > 0:
				p2["ok"] = false
				p2["reason"] = "%d quads fold over (the sides are too curved for one patch): draw a stroke across it" % folded
		patches[t[0]] = p2
	for p in patches:
		if p["ok"] and p["sig"] != "":
			_old_patches[p["sig"]] = p


## quads whose normal points against the source surface under them (a fill that folded over)
func _folded(pv: PackedFloat64Array, qv: PackedInt32Array) -> int:
	if nat == null:
		return 0
	var nq := qv.size() / 4
	var flat := PackedFloat64Array()
	flat.resize(nq * 3)
	var nn := PackedVector3Array()
	nn.resize(nq)
	for q in nq:
		var p := []
		for c in 4:
			var v := qv[q * 4 + c]
			p.append(Vector3(pv[v * 3], pv[v * 3 + 1], pv[v * 3 + 2]))
		var ce: Vector3 = (p[0] + p[1] + p[2] + p[3]) * 0.25
		nn[q] = (p[2] - p[0]).cross(p[3] - p[1])
		flat[q * 3] = ce.x
		flat[q * 3 + 1] = ce.y
		flat[q * 3 + 2] = ce.z
	var sn: PackedFloat64Array = nat.project(flat)["normals"]
	var bad := 0
	for q in nq:
		if nn[q].dot(Vector3(sn[q * 3], sn[q * 3 + 1], sn[q * 3 + 2])) < 0.0:
			bad += 1
	return bad


## the patches that all the given arcs' counts reach
func patches_touching(ai: int) -> Array:
	return (arcs[ai]["patches"] as Array).duplicate()


## pin arc `ai` at n edges (and, with `propagate`, the opposite arcs of the 4-sided patches it touches, round the loop);
## re-solves only the patches touching a changed arc. -> the patch indices solved
func set_count(ai: int, n: int, propagate := false) -> Array:
	n = maxi(1, n)
	var changed := {}
	var work := [[ai, n]]
	var seen := {}
	while not work.is_empty():
		var w: Array = work.pop_back()
		if seen.has(w[0]):
			continue
		seen[w[0]] = true
		if arcs[w[0]]["count"] == w[1] and arcs[w[0]]["pinned"]:
			continue
		arcs[w[0]]["count"] = w[1]
		arcs[w[0]]["pinned"] = true
		changed[w[0]] = true
		if propagate:
			for pi in arcs[w[0]]["patches"]:
				var opp := _opposite_arc(patches[pi], w[0])
				if opp >= 0 and not seen.has(opp):
					work.append([opp, w[1]])
	var before := solve_calls
	var touched := {}
	for c in changed:
		for pi in arcs[c]["patches"]:
			touched[pi] = true
	_layout_and_solve()
	return touched.keys()


## in a 4-sided patch, the single arc on the side opposite the one holding arc ai (-1 if the sides are not one arc each)
func _opposite_arc(p: Dictionary, ai: int) -> int:
	if p["n_real"] != 4:
		return -1
	var ring: PackedInt32Array = p["ring"]
	var corners: PackedInt32Array = p["corners"]
	var side_arcs: Array = []
	for i in 4:
		var a0: int = corners[i]
		var a1: int = corners[(i + 1) % 4]
		var lst := []
		var k := a0
		while k != a1:
			lst.append(ring[k] >> 1)
			k = (k + 1) % ring.size()
		side_arcs.append(lst)
	for i in 4:
		if side_arcs[i].has(ai):
			var o: Array = side_arcs[(i + 2) % 4]
			return o[0] if o.size() == 1 and side_arcs[i].size() == 1 else -1
	return -1


## the solved network as a mesh of quads (all patches that filled), the shared border vertices welded by construction
func bake() -> KMesh:
	var remap := {}
	var vs := PackedVector3Array()
	var fs: Array = []
	# global border vertex positions
	var gpos := PackedVector3Array()
	gpos.resize(nverts)
	for ni in nodes.size():
		gpos[ni] = nodes[ni]["pos"]
	for ai in arcs.size():
		var ap: PackedVector3Array = apts[ai]
		for k in range(1, ap.size() - 1):
			gpos[vbase[ai] + k - 1] = ap[k]
	for pidx in patches.size():
		var p: Dictionary = patches[pidx]
		if not (p["valid"] and p["ok"]):
			continue
		var ids: PackedInt32Array = p["ring_ids"]
		var pv: PackedFloat64Array = p["verts"]
		var qv: PackedInt32Array = p["quads"]
		var nring: int = p["nring"]
		var local := {}
		for q in qv.size() / 4:
			var f := PackedInt32Array()
			for c in 4:
				var lv: int = qv[q * 4 + c]
				var key: Variant
				var pos: Vector3
				if lv < nring:
					key = ids[lv]
					pos = gpos[ids[lv]]
				else:
					key = "p%d_%d" % [pidx, lv]
					pos = Vector3(pv[lv * 3], pv[lv * 3 + 1], pv[lv * 3 + 2])
				if not remap.has(key):
					remap[key] = vs.size()
					vs.append(pos)
				f.append(remap[key])
			fs.append(f)
	return KMesh.new().from_arrays(vs, fs)


func stats() -> Dictionary:
	var ok := 0
	var bad := 0
	var skipped := 0
	for p in patches:
		if p.get("outside", false):
			continue
		if not p["valid"]:
			skipped += 1
		elif p["ok"]:
			ok += 1
		else:
			bad += 1
	return {"strokes": strokes.size(), "nodes": nodes.size(), "arcs": arcs.size(), "patches": ok, "unsolved": bad, "skipped": skipped}


## G16: every skipped region with its reason, so the UI can say WHAT was skipped instead of only "3 regions skipped"
func skipped_regions() -> Array:
	var out: Array = []
	for i in patches.size():
		var p: Dictionary = patches[i]
		if not bool(p.get("valid", false)) and String(p.get("reason", "")) != "":
			out.append({"patch": i, "reason": String(p["reason"])})
	return out
