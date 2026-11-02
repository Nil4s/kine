## part_facts.gd - THE PART AS TEXT (item 220, MODELING VIEW WITH MATHS): a blind agent reads the part's numbers instead of a picture,
## the way body_assert.gd / agent_tools.gd give it the body. One line per body, deterministic (same record in, same text out).
##   #5 Crankshaft  V 674036 mm3  box x[-50.0,50.0] y[-40.0,48.2] z[-70.0,40.0]  c(0.0,8.2,-18.2)  round axis (0,0,1) r 48.2 L 110.0 | touches 1,2 | overlaps 4 (120 mm3) | near 6 (2.5 mm)
## WHAT EACH NUMBER IS (formulas stated so a reader can re-derive them):
##   volume, centroid   the kernel's own mass properties of the exact solid (KCad.mass_properties), mm3 and mm;
##   box                the axis-aligned box of the body's tessellation, mm (the mesh vertices lie ON the surface: a flat face is exact,
##                      a curved one is exact at the vertices and at most the tessellation deflection (PartFacts.defl_mm) inside);
##   axis               the PRINCIPAL axis from the exact inertia tensor (3x3 Jacobi eigen-decomposition). Two equal moments (within 0.1 %)
##                      = a body of revolution (or a 3+ fold symmetric one): its axis is the odd moment's eigenvector, "round axis (..) r R L L"
##                      with R = the farthest vertex from the axis line through the centroid and L = the extent along it. Three different
##                      moments: no revolve axis, "long axis (..)" is the smallest moment's, with the box in the principal frame "dims A x B x C".
##                      Three equal: "cubic, no axis". An axis is a LINE; it is given a direction by pointing AWAY from the part's volume centre
##                      (a body on the centre: the first non-zero component positive), so "axis of 6 at 120 deg to axis of 7" has one answer;
##   contacts           for every pair of bodies whose boxes are within NEAR_MM: OVERLAP = the kernel's common (KCad.intersect) volume,
##                      mm3, more than HIT_MM3; else the gap = the shortest distance between the two tessellated surfaces (triangle-triangle
##                      distance, exact for flat faces, within the deflection for curved ones), mm. TOUCH = gap <= TOUCH_MM (0.05) or a
##                      shared face; NEAR = a gap up to NEAR_MM; farther pairs are only counted;
##   names              the body's name if the record has "body_names" (item 212), else the name of the feature that made it (a pattern's
##                      copies are "<name> 2", "<name> 3"), else BodyN. Numbers (#N, 1-based) are the ones the other tools use.
## Bodies are numbered in the order the Part's replay lists them (Body1 .. BodyN, the browser's order).
class_name PartFacts
extends RefCounted

const KCad := preload("res://scripts/kcad.gd")
const MM := 0.001          # m per mm: the record's mm to the kernel's metres
const TOUCH_MM := 0.05     # a gap this small (mm) is touching: the kernel's tessellation noise is far below it
const HIT_MM3 := 1.0       # an overlap volume above this (mm3) is interference (Part.HIT_VOL, 1 mm3)
const NEAR_MM := 25.0      # pairs closer than this are listed in the contact graph
const KERNEL_MM3 := 1e-3  # mm3: a common volume above this means the grown body reached the other (the kernel noise is far below it)
## the kernel refinement of a gap (offset one body, intersect, bisect) stays OFF: on the first KineCAD 5 DLL that could run it, the offset +
## intersect loses the thin common sliver between near-coincident round faces. Measured 11-01 on s220's peg (r 5.0 in a 5.1 hole, true 0.100 mm):
## growing the peg shares 0 mm3 with the block up to 0.102 mm, growing the block first shares volume past 0.101, so the bisect read 0.101-0.104,
## while the fine mesh gap reads 0.09995. The mesh gap is within the fine deflection (0.005-0.1 mm) and is what every bar was written on.
const KERNEL_GAP := false
const SAME_MOMENT := 1e-3  # two principal moments within this fraction are one (a body of revolution)


## ------------------------------------------------------------------------------------------------ the model (one replay, cached numbers)
class Model:
	extends RefCounted
	var rec: Dictionary
	var ok := false
	var why := ""
	var n := 0
	var ids: Array = []          # the kernel solids (kept until free())
	var labels: Array = []       # one name per body
	var errors: Dictionary = {}  # the replay's step errors {feature id: message}
	var looks: Array = []        # item 221: the body looks of the replay ({"c": Color, "preset", ...}), one per body
	var props: Array = []        # KCad.mass_properties per body (metres)
	var vol_mm3: Array = []
	var _tidx := {}              # s233: i -> TriIndex of tris(i)
	var _tris := {}              # i -> PackedVector3Array (flat triangles, mm)
	var _fine := {}              # i -> PackedVector3Array (finer tessellation, mm)
	var _kgap := {}              # "i,j" -> {"gap", "method"}
	var _box := {}               # i -> AABB (mm)
	var _axis := {}              # i -> Dictionary
	var _ov := {}                # "i,j" -> overlap volume mm3
	var _gap := {}               # "i,j" -> gap mm
	var defl_mm := {}            # i -> the tessellation deflection used (mm)
	var centre_mm := Vector3.ZERO   # the volume-weighted centre of the whole part

	func release() -> void:
		for id in ids:
			if int(id) != 0:
				KCad.release(int(id))
		ids = []
		ok = false

	func centroid(i: int) -> Vector3:
		return (props[i]["center"] as Vector3) / MM

	## the body's triangles (flat, mm) at a deflection that scales with its size (diagonal / 1000, 0.02 .. 0.3 mm): the facts' box, axis and gaps
	func tris(i: int) -> PackedVector3Array:
		if _tris.has(i):
			return _tris[i]
		var coarse := PartFacts.tess_mm(int(ids[i]), 0.002, 0.8)
		var bb := PartFacts.box_of(coarse)
		var dm := clampf(bb.size.length() * 1e-3, 0.02, 0.3)   # mm
		var t := PartFacts.tess_mm(int(ids[i]), dm * MM, 0.3)
		defl_mm[i] = dm
		_tris[i] = t
		_box[i] = PartFacts.box_of(t)
		return t

	## the same body, finer (diagonal / 10000, 0.002 .. 0.1 mm): what a part_assert gap reads before the kernel refines it
	func tris_fine(i: int) -> PackedVector3Array:
		if _fine.has(i):
			return _fine[i]
		var bb := box(i)
		var dm := clampf(bb.size.length() * 1e-4, 0.005, 0.1)
		var t := PartFacts.tess_mm(int(ids[i]), dm * MM, 0.12)
		_fine[i] = t
		return t

	func index(i: int) -> TriIndex:
		if not _tidx.has(i):
			_tidx[i] = TriIndex.new(tris(i))
		return _tidx[i]

	func box(i: int) -> AABB:
		if not _box.has(i):
			tris(i)
		return _box[i]

	func box_gap(i: int, j: int) -> float:
		return PartFacts.aabb_gap(box(i), box(j))

	## the overlap volume of bodies i and j, mm3 (0 when their boxes do not meet); the kernel's common
	func overlap(i: int, j: int) -> float:
		var key := "%d,%d" % [mini(i, j), maxi(i, j)]
		if _ov.has(key):
			return _ov[key]
		var v := 0.0
		if box_gap(i, j) <= 1e-6:
			var pk := PartFacts.pair_key(int(ids[i]), int(ids[j]))
			if PartFacts._pair_ov.has(pk):   # s233: the same two shapes met in an earlier call (the replay cache hands the same ids back)
				v = PartFacts._pair_ov[pk]
			else:
				var c: int = KCad.intersect(int(ids[i]), int(ids[j]))
				if c != 0:
					v = KCad.volume(c) / (MM * MM * MM)
					KCad.release(c)
				PartFacts._pair_ov[pk] = v
		_ov[key] = v
		return v

	## the shortest distance between the two surfaces, mm; INF when it is more than `limit`; 0 when they overlap or touch
	func gap(i: int, j: int, limit := INF) -> float:
		var key := "%d,%d" % [mini(i, j), maxi(i, j)]
		if _gap.has(key):
			var g: float = _gap[key]
			return g if g <= limit else INF
		if box_gap(i, j) > limit:
			return INF
		if overlap(i, j) > HIT_MM3:
			_gap[key] = 0.0
			return 0.0
		var pk2 := PartFacts.pair_key(int(ids[i]), int(ids[j]))
		var g2: float
		var hit: Variant = PartFacts._pair_gap.get(pk2)
		if hit != null and (not is_inf(float(hit[0])) or float(hit[1]) >= limit):   # a finite answer is the true gap; an INF one holds for any limit up to the one it was asked with
			g2 = float(hit[0])
		else:
			g2 = PartFacts.tri_gap(tris(i), tris(j), limit, {}, index(i), index(j))
			PartFacts._pair_gap[pk2] = [g2, limit]
		if g2 <= limit or is_inf(limit):
			_gap[key] = g2
		return g2 if g2 <= limit else INF

	## the gap for a part_assert: the fine mesh distance, then REFINED by the kernel when it can: the body with fewer faces is offset by g
	## (KCad.offset) and intersected with the other; bisecting g on "the common volume is above KERNEL_MM3" gives the gap to ~1e-4 mm.
	## -> {"gap": mm, "method": "kernel" | "mesh", "ov": overlap mm3}. A pair that overlaps has gap 0.
	func exact_gap(i: int, j: int) -> Dictionary:
		var key := "%d,%d" % [mini(i, j), maxi(i, j)]
		if _kgap.has(key):
			return _kgap[key]
		var ov := overlap(i, j)
		var out := {"gap": 0.0, "method": "kernel", "ov": ov}
		if ov > PartFacts.HIT_MM3:
			_kgap[key] = out
			return out
		var info := {}
		var g := PartFacts.tri_gap(tris_fine(i), tris_fine(j), INF, info)
		out = {"gap": g, "method": "mesh", "ov": ov, "a": info.get("a", Vector3.ZERO), "b": info.get("b", Vector3.ZERO)}
		if g <= 1e-9 or is_inf(g) or not KERNEL_GAP or not KCad.has_offset():
			_kgap[key] = out
			return out
		var small: int = i if KCad.face_count(int(ids[i])) <= KCad.face_count(int(ids[j])) else j
		var other: int = j if small == i else i
		var tol := maxf(defl_mm.get(i, 0.1), defl_mm.get(j, 0.1)) * 3.0 + 0.01   # mm: how far the mesh gap can be from the true one
		var lo := maxf(0.0, g - tol)
		var hi := g + tol
		if _hits(small, other, hi) and not _hits(small, other, lo):
			for _k in 18:
				var mid := (lo + hi) * 0.5
				if _hits(small, other, mid):
					hi = mid
				else:
					lo = mid
			out["gap"] = (lo + hi) * 0.5
			out["method"] = "kernel"
		_kgap[key] = out
		return out

	## does body `small` grown by d mm share volume (> KERNEL_MM3) with `other`?
	func _hits(small: int, other: int, d: float) -> bool:
		var o: int = KCad.offset(int(ids[small]), d * MM)
		if o == 0:
			return false
		var c: int = KCad.intersect(o, int(ids[other]))
		KCad.release(o)
		if c == 0:
			return false
		var v: float = KCad.volume(c) / (MM * MM * MM)
		KCad.release(c)
		return v > PartFacts.KERNEL_MM3

	## principal axis facts of body i (see the header): {"kind": round|general|cubic, "axis": Vector3 (unit, directed), "len", "radius", "dims": [..], "dir_ref": bool}
	func axis(i: int) -> Dictionary:
		if _axis.has(i):
			return _axis[i]
		var P: Dictionary = props[i]
		var e := PartFacts.eigen(P["inertia"] as Basis)   # ascending moments + their unit vectors
		var w: Array = e[0]
		var v: Array = e[1]
		var s := maxf(absf(w[2]), 1e-30)
		var kind := "general"
		var a: Vector3 = v[0]
		var d01 := absf(w[0] - w[1]) / s
		var d12 := absf(w[1] - w[2]) / s
		if d01 < SAME_MOMENT and d12 < SAME_MOMENT:
			kind = "cubic"
		elif d01 < SAME_MOMENT:
			kind = "round"
			a = v[2]
		elif d12 < SAME_MOMENT:
			kind = "round"
			a = v[0]
		a = a.normalized()
		var c := centroid(i)
		var how := kind
		if kind == "general":
			var fa := _flat_axis(i)
			if fa != Vector3.ZERO:
				a = fa
				how = "axial"   # the normal the body's flat faces share most area on (a piston whose moments are nearly equal still has one)
		var rel := c - centre_mm
		var sgn := 0.0
		var by_ref := false
		if absf(rel.dot(a)) > 1e-3 * maxf(1.0, box(i).size.length()):
			sgn = signf(rel.dot(a))
			by_ref = true
		else:
			sgn = 1.0
			var big := 0
			for k in 3:
				if absf(a[k]) > absf(a[big]) + 1e-9:
					big = k
			sgn = signf(a[big])
		a *= sgn
		# extents along the axis and the farthest vertex from the axis line through the centroid
		var T := tris(i)
		var lo := INF
		var hi := -INF
		var rmax := 0.0
		for p in T:
			var q: Vector3 = p - c
			var al := q.dot(a)
			lo = minf(lo, al)
			hi = maxf(hi, al)
			rmax = maxf(rmax, (q - a * al).length())
		var dims := []
		kind = how
		if kind == "general":
			dims = [snappedf(hi - lo, 0.001)]
			for k in [1, 2]:
				var l2 := INF
				var h2 := -INF
				for p in T:
					var al2 := (p - c).dot(v[k] as Vector3)
					l2 = minf(l2, al2)
					h2 = maxf(h2, al2)
				dims.append(snappedf(h2 - l2, 0.001))
		_axis[i] = {"kind": kind, "axis": a, "len": hi - lo, "radius": rmax, "lo": lo, "hi": hi, "dims": dims, "by_ref": by_ref, "moments": w}
		return _axis[i]

	## the unit normal (undirected) carrying the most FLAT face area of body i, or ZERO when the flat faces are under 15 % of the surface
	func _flat_axis(i: int) -> Vector3:
		var groups: Array = []   # [normal, area]
		var tot := 0.0
		var flat := 0.0
		for f in KCad.faces(int(ids[i])):
			var ar: float = f["area"]
			tot += ar
			if String(f.get("type", "")) != "plane":
				continue
			flat += ar
			var nf: Vector3 = (f["normal"] as Vector3).normalized()
			var hit := false
			for g in groups:
				if absf((g[0] as Vector3).dot(nf)) > 0.9999:
					g[1] += ar
					hit = true
					break
			if not hit:
				groups.append([nf, ar])
		if groups.is_empty() or flat < 0.15 * tot:
			return Vector3.ZERO
		groups.sort_custom(func(x, y): return x[1] > y[1])
		return groups[0][0]

	## body indices (0-based) whose label matches `word` (case-free substring, a trailing s is forgiven)
	func like(word: String) -> Array:
		var w := word.strip_edges().to_lower()
		var w2 := w.trim_suffix("s") if w.length() > 3 else w
		var out := []
		for i in n:
			var lb := String(labels[i]).to_lower()
			if lb.contains(w) or lb.contains(w2):
				out.append(i)
		return out

	## s233 BROAD PHASE: every pair (i < j) whose boxes are within `limit` mm (box_gap <= limit), in (i, j) order, exactly the pairs the
	## all-pairs loop would keep, found by a sweep over the boxes sorted along the axis with the fewest overlaps: near-linear in n plus the pairs found
	## (n=267: 35 000 box tests became about 1 000). pairs_tested counts the full box tests made, for the tests to read.
	func near_pairs(limit: float) -> Array:
		var bx: Array = []
		for i in n:
			bx.append(box(i))
		var best_axis := 0
		var best_cnt := -1
		var orders: Array = []
		for ax in 3:
			var ord: Array = range(n)
			ord.sort_custom(func(a, b): return bx[a].position[ax] < bx[b].position[ax] or (bx[a].position[ax] == bx[b].position[ax] and a < b))
			orders.append(ord)
			var cnt := 0   # the candidates this axis leaves (capped: a bad axis stops early)
			for a in n:
				var ia: int = ord[a]
				var hi: float = bx[ia].position[ax] + bx[ia].size[ax] + limit
				var b := a + 1
				while b < n and bx[ord[b]].position[ax] <= hi:
					cnt += 1
					b += 1
				if best_cnt >= 0 and cnt > best_cnt:
					break
			if best_cnt < 0 or cnt < best_cnt:
				best_cnt = cnt
				best_axis = ax
		var ord2: Array = orders[best_axis]
		var found := PackedInt64Array()
		for a in n:
			var ia: int = ord2[a]
			var hi: float = bx[ia].position[best_axis] + bx[ia].size[best_axis] + limit
			var b := a + 1
			while b < n and bx[ord2[b]].position[best_axis] <= hi:
				var ib: int = ord2[b]
				pairs_tested += 1
				if PartFacts.aabb_gap(bx[ia], bx[ib]) <= limit:
					found.append(mini(ia, ib) * n + maxi(ia, ib))
				b += 1
		found.sort()
		var out: Array = []
		for key in found:
			out.append([int(key) / n, int(key) % n])
		return out

	var pairs_tested := 0   # s233 probe: full box tests the broad phase made

	## connected pieces of the part: bodies joined when they overlap or touch (gap <= TOUCH_MM); [[i, ...], ...] by first body
	func components() -> Array:
		var par := []
		for i in n:
			par.append(i)
		for pr in near_pairs(TOUCH_MM):
			var i: int = pr[0]
			var j: int = pr[1]
			if gap(i, j, TOUCH_MM) <= TOUCH_MM:
				var a := _root(par, i)
				var b := _root(par, j)
				if a != b:
					par[maxi(a, b)] = mini(a, b)
		var groups := {}
		for i in n:
			var r := _root(par, i)
			if not groups.has(r):
				groups[r] = []
			groups[r].append(i)
		var out := []
		for r in groups:
			out.append(groups[r])
		return out

	func _root(par: Array, i: int) -> int:
		while int(par[i]) != i:
			i = int(par[i])
		return i


## the part record -> a Model (one replay; call free() when done). ok = false with why when the kernel is missing / the part is empty.
static func build(rec: Dictionary) -> Model:
	var M := Model.new()
	M.rec = rec
	if not Part.available():
		M.why = "the CAD kernel is not installed (Part.why_not(): %s)" % Part.why_not()
		return M
	var r: Dictionary = Part.replay(rec, -1, {"keep": true, "props": true, "errors_only": true, "inc": true})
	M.ids = r.get("ids", [])
	M.n = M.ids.size()
	M.errors = r.get("errors", {})
	M.looks = r.get("body_looks", [])
	if M.n == 0:
		M.why = "the part has no solid body" + ((": " + JSON.stringify(M.errors)) if not M.errors.is_empty() else "")
		return M
	M.props = r["props"]
	var vs := 0.0
	var cs := Vector3.ZERO
	for i in M.n:
		var v: float = M.props[i]["volume"] / (MM * MM * MM)
		M.vol_mm3.append(v)
		vs += v
		cs += (M.props[i]["center"] as Vector3) / MM * v
	M.centre_mm = cs / maxf(vs, 1e-9)
	M.labels = labels_of(rec, M.n, r.get("counts", []))
	M.ok = true
	return M


## the name of each body, as the replay lists them. rec["body_names"] (item 212) first; else tracked through the timeline by how many
## bodies each step adds or removes: a new body takes its feature's name (a pattern's copies "<name> 2", ...), a combine drops its tools.
## Anything the tracking cannot follow (a split) falls back to BodyN for the bodies it cannot name.
static func labels_of(rec: Dictionary, n: int, counts: Array = []) -> Array:   # counts: the body count after each step (Part.replay res["counts"]); empty = replay each prefix
	var bn: Variant = rec.get("body_names")
	if bn is Array and (bn as Array).size() == n:
		return (bn as Array).map(func(s): return String(s))
	var out: Array = []
	var feats: Array = rec.get("features", [])
	var made: Array = []   # [feature index, body count after it]
	var cnt := 0
	var prev := 0
	var step_counts: Array = counts if counts.size() == feats.size() else _counts_after_each(rec, feats)
	for k in feats.size():
		var f: Dictionary = feats[k]
		var c: int = step_counts[k]
		if bool(f.get("off", false)):
			continue
		var t := String(f.get("t", ""))
		var nm := String(f.get("name", t))
		if t == "combine" and c < prev and not bool(f.get("keep", false)):
			var gone: Array = (f.get("tools", []) as Array).map(func(x): return int(x))
			gone.sort()
			gone.reverse()
			for g in gone:
				if int(g) >= 0 and int(g) < out.size():
					out.remove_at(int(g))
		elif c > out.size():
			var base := nm
			if t == "pattern" and int(f.get("body", -1)) >= 0 and int(f.get("body", -1)) < out.size():
				base = String(out[int(f["body"])])
				var k2 := 2
				while out.size() < c:
					out.append(_numbered(base, k2))
					k2 += 1
			else:
				var k3 := 1
				while out.size() < c:
					out.append(base if k3 == 1 else _numbered(base, k3))
					k3 += 1
		if out.size() > c:
			out.resize(c)
		prev = c
	while out.size() < n:
		out.append("Body%d" % (out.size() + 1))
	if out.size() > n:
		out.resize(n)
	return out


static func _numbered(base: String, k: int) -> String:
	var tail := base.rsplit(" ", true, 1)
	if tail.size() == 2 and tail[1].is_valid_int():
		return "%s %d" % [tail[0], k]
	return "%s %d" % [base, k]


## the body count after feature k, for every k: one incremental replay per prefix (the replay caches the steps it already made)
static func _counts_after_each(rec: Dictionary, feats: Array) -> Array:
	var out: Array = []
	for k in feats.size():
		var r: Dictionary = Part.replay(rec, k, {"inc": true, "errors_only": true})
		out.append(int(r.get("bodies", 0)))
	return out


# ------------------------------------------------------------------------------------------------ geometry helpers (mm)
static var _pair_ov := {}    # s233: (shape a, shape b) -> common volume mm3, across calls
static var _pair_gap := {}   # s233: (shape a, shape b) -> [mesh gap or INF, the limit it was asked with]


## the key of an ordered pair of live shapes (their ids and generations: a freed and reused id never meets an old answer)
static func pair_key(a: int, b: int) -> String:
	return "%d.%d|%d.%d" % [a, KCad.gen(a), b, KCad.gen(b)]


static var _tess_mm := {}   # s233: (shape, deflection, angle) -> triangles, kept while the shape lives (every agent call tessellated the whole part again)
static var _tess_mm_pts := 0
const TESS_MM_PTS := 12000000


static func tess_mm(id: int, defl_m: float, ang: float) -> PackedVector3Array:
	var key := "%d.%d.%s.%s" % [id, KCad.gen(id), var_to_str(defl_m), var_to_str(ang)]
	if _tess_mm.has(key):
		return _tess_mm[key]
	var r := _tess_mm_make(id, defl_m, ang)
	if _tess_mm_pts + r.size() > TESS_MM_PTS:
		_tess_mm.clear()
		_tess_mm_pts = 0
	_tess_mm[key] = r
	_tess_mm_pts += r.size()
	return r


static func _tess_mm_make(id: int, defl_m: float, ang: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var tm: ArrayMesh = KCad.tessellate(id, defl_m, ang)
	if tm == null:
		return out
	for s in tm.get_surface_count():
		var arr := tm.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: Variant = arr[Mesh.ARRAY_INDEX]
		if idx == null or (idx as PackedInt32Array).is_empty():
			for p in verts:
				out.append(p / MM)
		else:
			for k in (idx as PackedInt32Array):
				out.append(verts[k] / MM)
	return out


static func box_of(pts: PackedVector3Array) -> AABB:
	if pts.is_empty():
		return AABB()
	var bb := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		bb = bb.expand(p)
	return bb


## the distance between two boxes (0 when they meet)
static func aabb_gap(a: AABB, b: AABB) -> float:
	var d := Vector3.ZERO
	for k in 3:
		d[k] = maxf(0.0, maxf(b.position[k] - (a.position[k] + a.size[k]), a.position[k] - (b.position[k] + b.size[k])))
	return d.length()


## the shortest distance between two triangle soups (flat, three points per triangle), mm; INF when it is more than `limit`.
## Region filter (only triangles near the other soup's box), then a grid over B so each triangle of A meets only its neighbours.
static func tri_gap(A: PackedVector3Array, B: PackedVector3Array, limit := INF, info := {}, ia: TriIndex = null, ib: TriIndex = null) -> float:   # ia / ib: s233 per-body triangle indexes (Model.index), same answer, no scan of every triangle per pair
	if A.is_empty() or B.is_empty():
		return INF
	var ba := box_of(A)
	var bb := box_of(B)
	var lb := aabb_gap(ba, bb)
	if lb > limit:
		return INF
	# an upper bound from real surface points: any A vertex to any B vertex of a sample (a distance between two surface points >= the gap)
	var best := INF
	var sa := maxi(1, A.size() / 48)
	var sb := maxi(1, B.size() / 48)
	for i in range(0, A.size(), sa):
		for j in range(0, B.size(), sb):
			best = minf(best, A[i].distance_to(B[j]))
	var reach := minf(best, limit)
	var region := ba.grow(reach).intersection(bb.grow(reach))
	if region.size == Vector3.ZERO and not (ba.grow(reach).intersects(bb.grow(reach))):
		return INF
	# the triangles that can matter
	var ta: Array = _near(A, ia, region)
	var tb: Array = _near(B, ib, region)
	if ta.is_empty() or tb.is_empty():
		ta = _near(A, ia, bb.grow(reach))
		tb = _near(B, ib, ba.grow(reach))
	# grid over tb
	var cell := maxf(region.size.length() / 12.0, 0.05)
	var grid := {}
	for t in tb:
		var tbx: AABB = t[1]
		for cx in range(int(floor(tbx.position.x / cell)), int(floor((tbx.position.x + tbx.size.x) / cell)) + 1):
			for cy in range(int(floor(tbx.position.y / cell)), int(floor((tbx.position.y + tbx.size.y) / cell)) + 1):
				for cz in range(int(floor(tbx.position.z / cell)), int(floor((tbx.position.z + tbx.size.z) / cell)) + 1):
					var key := Vector3i(cx, cy, cz)
					if not grid.has(key):
						grid[key] = []
					grid[key].append(t[0])
	var stamp := {}
	for t in ta:
		var tax: AABB = t[1]
		var rad := minf(best, limit)
		var q := tax.grow(rad)
		var seen := []
		for cx in range(int(floor(q.position.x / cell)), int(floor((q.position.x + q.size.x) / cell)) + 1):
			for cy in range(int(floor(q.position.y / cell)), int(floor((q.position.y + q.size.y) / cell)) + 1):
				for cz in range(int(floor(q.position.z / cell)), int(floor((q.position.z + q.size.z) / cell)) + 1):
					var key2 := Vector3i(cx, cy, cz)
					if grid.has(key2):
						for jt in grid[key2]:
							if not stamp.has(jt) or stamp[jt] != t[0]:
								stamp[jt] = t[0]
								seen.append(jt)
		for j in seen:
			var d := Part._tri_tri(A[t[0]], A[t[0] + 1], A[t[0] + 2], B[j], B[j + 1], B[j + 2])
			if d < best:
				best = d
				info["a"] = (A[t[0]] + A[t[0] + 1] + A[t[0] + 2]) / 3.0
				info["b"] = (B[j] + B[j + 1] + B[j + 2]) / 3.0
				if best <= 1e-9:
					return 0.0
	return best if best <= limit else INF


## true when point `o` is inside the closed triangle soup P: a ray in an odd direction crosses its triangles an odd number of times
static func inside(P: PackedVector3Array, o: Vector3) -> bool:
	var d := Vector3(0.5773, 0.5774, 0.5775).normalized()
	var n := 0
	for i in range(0, P.size() - 2, 3):
		var e1 := P[i + 1] - P[i]
		var e2 := P[i + 2] - P[i]
		var h := d.cross(e2)
		var a := e1.dot(h)
		if absf(a) < 1e-12:
			continue
		var f := 1.0 / a
		var sv := o - P[i]
		var u := f * sv.dot(h)
		if u < 0.0 or u > 1.0:
			continue
		var qv := sv.cross(e1)
		var v := f * d.dot(qv)
		if v < 0.0 or u + v > 1.0:
			continue
		if f * e2.dot(qv) > 0.0:
			n += 1
	return n % 2 == 1


## the distance (mm) along a ray from `o` in unit direction `d` to the first triangle of P it meets (Moller-Trumbore), INF when it meets none
static func ray_hit(P: PackedVector3Array, o: Vector3, d: Vector3) -> float:
	var best := INF
	for i in range(0, P.size() - 2, 3):
		var e1 := P[i + 1] - P[i]
		var e2 := P[i + 2] - P[i]
		var h := d.cross(e2)
		var a := e1.dot(h)
		if absf(a) < 1e-12:
			continue
		var f := 1.0 / a
		var sv := o - P[i]
		var u := f * sv.dot(h)
		if u < -1e-9 or u > 1.0 + 1e-9:
			continue
		var qv := sv.cross(e1)
		var v := f * d.dot(qv)
		if v < -1e-9 or u + v > 1.0 + 1e-9:
			continue
		var t := f * e2.dot(qv)
		if t >= -1e-9 and t < best:
			best = maxf(t, 0.0)
	return best


static func _near(P: PackedVector3Array, idx: TriIndex, region: AABB) -> Array:
	return idx.near(region) if idx != null else _near_tris(P, region)


## s233 TRIANGLE INDEX: a body's triangle boxes and a uniform grid over them, built once per body. near(region) answers exactly what _near_tris(P, region)
## answers (same triangles, same ascending order, same boxes) by looking only in the grid cells the region covers, not at all 400 000 triangles.
class TriIndex:
	extends RefCounted
	var P: PackedVector3Array
	var mins := PackedVector3Array()
	var maxs := PackedVector3Array()
	var cell := 1.0
	var origin := Vector3.ZERO
	var grid := {}   # Vector3i -> PackedInt32Array of triangle numbers
	var maxc := Vector3.ZERO   # the last cell with triangles in it, per axis

	func _init(pts: PackedVector3Array) -> void:
		P = pts
		var nt := pts.size() / 3
		mins.resize(nt)
		maxs.resize(nt)
		var all := AABB()
		for t in nt:
			var a := pts[3 * t]
			var b := pts[3 * t + 1]
			var c := pts[3 * t + 2]
			mins[t] = Vector3(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)), minf(a.z, minf(b.z, c.z)))
			maxs[t] = Vector3(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)), maxf(a.z, maxf(b.z, c.z)))
		if nt == 0:
			return
		all = PartFacts.box_of(pts)
		origin = all.position
		cell = maxf(all.size.length() / 40.0, 1e-3)
		maxc = ((all.position + all.size - origin) / cell).floor()
		for t in nt:
			var lo := ((mins[t] - origin) / cell).floor()
			var hi := ((maxs[t] - origin) / cell).floor()
			for cx in range(int(lo.x), int(hi.x) + 1):
				for cy in range(int(lo.y), int(hi.y) + 1):
					for cz in range(int(lo.z), int(hi.z) + 1):
						var key := Vector3i(cx, cy, cz)
						var cellv: PackedInt32Array = grid.get(key, PackedInt32Array())   # packed arrays are values: put it back
						cellv.append(t)
						grid[key] = cellv

	func near(region: AABB) -> Array:
		var out := []
		if mins.is_empty():
			return out
		var lo := ((region.position - origin) / cell).floor().max(Vector3.ZERO)
		var hi := ((region.position + region.size - origin) / cell).floor().min(maxc)
		var seen := {}
		var hit: Array = []
		for cx in range(int(lo.x), int(hi.x) + 1):
			for cy in range(int(lo.y), int(hi.y) + 1):
				for cz in range(int(lo.z), int(hi.z) + 1):
					var key := Vector3i(cx, cy, cz)
					if grid.has(key):
						for t in (grid[key] as PackedInt32Array):
							if not seen.has(t):
								seen[t] = true
								hit.append(t)
		hit.sort()
		for t in hit:
			var tb := AABB(P[3 * t], Vector3.ZERO).expand(P[3 * t + 1]).expand(P[3 * t + 2])
			if tb.intersects(region) or region.encloses(tb):
				out.append([3 * t, tb])
		return out


## [[first vertex index, its box]] for the triangles of P whose box meets `region`
static func _near_tris(P: PackedVector3Array, region: AABB) -> Array:
	var out := []
	for i in range(0, P.size() - 2, 3):
		var tb := AABB(P[i], Vector3.ZERO).expand(P[i + 1]).expand(P[i + 2])
		if tb.intersects(region) or region.encloses(tb):
			out.append([i, tb])
	return out


## eigen-decomposition of a symmetric 3x3 (Jacobi): [[w0 <= w1 <= w2], [unit vector for each]]
static func eigen(b: Basis) -> Array:
	var a := [[b.x.x, b.y.x, b.z.x], [b.x.y, b.y.y, b.z.y], [b.x.z, b.y.z, b.z.z]]
	var v := [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
	var scale := absf(a[0][0]) + absf(a[1][1]) + absf(a[2][2])
	for _it in 60:
		var p := 0
		var q := 1
		var big := absf(a[0][1])
		if absf(a[0][2]) > big:
			p = 0
			q = 2
			big = absf(a[0][2])
		if absf(a[1][2]) > big:
			p = 1
			q = 2
			big = absf(a[1][2])
		if big <= 1e-15 * maxf(scale, 1e-300):
			break
		var theta: float = (a[q][q] - a[p][p]) / (2.0 * a[p][q])
		var t := signf(theta) / (absf(theta) + sqrt(theta * theta + 1.0)) if theta != 0.0 else 1.0
		var c := 1.0 / sqrt(t * t + 1.0)
		var s := t * c
		for k in 3:
			var akp: float = a[k][p]
			var akq: float = a[k][q]
			a[k][p] = c * akp - s * akq
			a[k][q] = s * akp + c * akq
		for k in 3:
			var apk: float = a[p][k]
			var aqk: float = a[q][k]
			a[p][k] = c * apk - s * aqk
			a[q][k] = s * apk + c * aqk
		for k in 3:
			var vkp: float = v[k][p]
			var vkq: float = v[k][q]
			v[k][p] = c * vkp - s * vkq
			v[k][q] = s * vkp + c * vkq
	var idx := [0, 1, 2]
	idx.sort_custom(func(x, y): return a[x][x] < a[y][y])
	var ws := []
	var vs := []
	for i in idx:
		ws.append(a[i][i])
		vs.append(Vector3(v[0][i], v[1][i], v[2][i]).normalized())
	return [ws, vs]


# ------------------------------------------------------------------------------------------------ the facts text
static func _f(x: float) -> String:
	return "%.1f" % (0.0 if absf(x) < 0.05 else x)


static func _v3(v: Vector3) -> String:
	return "(%s,%s,%s)" % [_f(v.x), _f(v.y), _f(v.z)]


static func _u3(v: Vector3) -> String:
	return "(%.3f,%.3f,%.3f)" % [0.0 if absf(v.x) < 5e-4 else v.x, 0.0 if absf(v.y) < 5e-4 else v.y, 0.0 if absf(v.z) < 5e-4 else v.z]


## the contact graph: {"overlaps": [[i, j, mm3]], "touches": [[i, j]], "near": [[i, j, gap]], "apart": count of the other pairs}
static func contacts(M: Model, near_mm := NEAR_MM) -> Dictionary:
	var ov := []
	var tc := []
	var nr := []
	for pr in M.near_pairs(near_mm):   # s233: only the pairs whose boxes are within near_mm (the sweep); the rest are "apart" by count
		var i: int = pr[0]
		var j: int = pr[1]
		var o := M.overlap(i, j)
		if o > HIT_MM3:
			ov.append([i, j, o])
			continue
		var g := M.gap(i, j, near_mm)
		if is_inf(g):
			continue
		elif g <= TOUCH_MM:
			tc.append([i, j])
		else:
			nr.append([i, j, g])
	return {"overlaps": ov, "touches": tc, "near": nr, "apart": M.n * (M.n - 1) / 2 - ov.size() - tc.size() - nr.size()}


## the all-pairs contact graph the broad phase replaced: kept as the reference tests/s233_test.gd compares against (identical results)
static func contacts_all_pairs(M: Model, near_mm := NEAR_MM) -> Dictionary:
	var ov := []
	var tc := []
	var nr := []
	var apart := 0
	for i in M.n:
		for j in range(i + 1, M.n):
			if M.box_gap(i, j) > near_mm:
				apart += 1
				continue
			var o := M.overlap(i, j)
			if o > HIT_MM3:
				ov.append([i, j, o])
				continue
			var g := M.gap(i, j, near_mm)
			if is_inf(g):
				apart += 1
			elif g <= TOUCH_MM:
				tc.append([i, j])
			else:
				nr.append([i, j, g])
	return {"overlaps": ov, "touches": tc, "near": nr, "apart": apart}


## groups of identical bodies (same volume to 0.01 % and same box dimensions to 0.05 mm): [[i, ...]] with 2+ members
static func repeats(M: Model) -> Array:
	var groups := {}
	for i in M.n:
		var key := "%.0f" % snappedf(M.vol_mm3[i], maxf(M.vol_mm3[i] * 1e-4, 1e-3))   # a rotated copy has another bbox but the same volume
		if not groups.has(key):
			groups[key] = []
		groups[key].append(i)
	var out := []
	for k in groups:
		if groups[k].size() >= 2:
			out.append(groups[k])
	return out


static func _ids(a: Array) -> String:
	return ",".join(a.map(func(i): return str(int(i) + 1)))


## the whole report: {"ok", "bodies": n, "lines": [text...], "data": {...}}. cap = longest list of neighbours a line prints.
static func facts(rec: Dictionary, opts := {}) -> Dictionary:
	var M := build(rec)
	if not M.ok:
		return {"ok": false, "error": M.why, "lines": [], "bodies": 0}
	var r := facts_of(M, opts)
	M.release()
	return r


static func facts_of(M: Model, opts := {}) -> Dictionary:
	var cap: int = int(opts.get("cap", 6))
	var C := contacts(M, float(opts.get("near_mm", NEAR_MM)))
	var rep := repeats(M)
	var rep_of := {}
	for g in rep:
		for i in g:
			rep_of[i] = g
	var comps := M.components()
	var tot := 0.0
	var bb := AABB()
	for i in M.n:
		tot += M.vol_mm3[i]
		bb = M.box(i) if i == 0 else bb.merge(M.box(i))
	var lines: Array = []
	lines.append("PART %s: %d bodies, volume %.0f mm3, box %s to %s (size %s mm), %d piece%s (bodies that touch or overlap), %d feature%s%s" % [
		String(M.rec.get("name", "Part")), M.n, tot, _v3(bb.position), _v3(bb.end), _v3(bb.size), comps.size(), "" if comps.size() == 1 else "s",
		(M.rec.get("features", []) as Array).size(), "" if (M.rec.get("features", []) as Array).size() == 1 else "s",
		(", %d step error%s: %s" % [M.errors.size(), "" if M.errors.size() == 1 else "s", JSON.stringify(M.errors)]) if not M.errors.is_empty() else ""])
	var data_b := []
	for i in M.n:
		var ax := M.axis(i)
		var b := M.box(i)
		var cen := M.centroid(i)
		var shape := ""
		match ax["kind"]:
			"round", "axial":
				shape = "round axis %s r %s L %s" % [_u3(ax["axis"]), _f(ax["radius"]), _f(ax["len"])]
			"cubic":
				shape = "cubic, no axis"
			_:
				shape = "long axis %s dims %s" % [_u3(ax["axis"]), " x ".join((ax["dims"] as Array).map(func(d): return _f(d)))]
		var ts := []
		var os := []
		var ns := []
		for p in C["touches"]:
			if p[0] == i or p[1] == i:
				ts.append(p[1] if p[0] == i else p[0])
		for p in C["overlaps"]:
			if p[0] == i or p[1] == i:
				os.append([p[1] if p[0] == i else p[0], p[2]])
		for p in C["near"]:
			if p[0] == i or p[1] == i:
				ns.append([p[1] if p[0] == i else p[0], p[2]])
		ns.sort_custom(func(x, y): return x[1] < y[1])
		var tail := ""
		if not ts.is_empty():
			tail += " | touches " + _cap_list(ts.map(func(k): return str(int(k) + 1)), cap)
		if not os.is_empty():
			tail += " | overlaps " + _cap_list(os.map(func(q): return "%d (%.0f mm3)" % [int(q[0]) + 1, q[1]]), cap)
		if not ns.is_empty():
			tail += " | near " + _cap_list(ns.map(func(q): return "%d (%s mm)" % [int(q[0]) + 1, _gap_s(q[1])]), cap)
		if rep_of.has(i):
			tail += " | x%d identical (%s)" % [(rep_of[i] as Array).size(), _ids(rep_of[i])]
		lines.append("#%d %s  V %.0f mm3  box x[%s,%s] y[%s,%s] z[%s,%s]  c%s  %s%s" % [i + 1, M.labels[i], M.vol_mm3[i],
			_f(b.position.x), _f(b.end.x), _f(b.position.y), _f(b.end.y), _f(b.position.z), _f(b.end.z), _v3(cen), shape, tail])
		data_b.append({"n": i + 1, "name": M.labels[i], "volume_mm3": snappedf(M.vol_mm3[i], 0.01), "box_min": b.position, "box_max": b.end, "centroid": cen,
			"kind": ax["kind"], "axis": ax["axis"], "radius_mm": snappedf(ax["radius"], 0.001), "len_mm": snappedf(ax["len"], 0.001), "dims": ax["dims"],
			"touches": ts.map(func(k): return int(k) + 1), "overlaps": os.map(func(q): return {"body": int(q[0]) + 1, "mm3": snappedf(q[1], 0.01)}),
			"near": ns.map(func(q): return {"body": int(q[0]) + 1, "gap_mm": snappedf(q[1], 0.001)})})
	if not rep.is_empty():
		lines.append("REPEATS: " + "; ".join(rep.map(func(g): return "%dx %s (%s)" % [(g as Array).size(), String(M.labels[g[0]]), _ids(g)])))
	var by_name := {}
	for i in M.n:
		var base := String(M.labels[i])
		var tail2 := base.rsplit(" ", true, 1)
		if tail2.size() == 2 and tail2[1].is_valid_int():
			base = tail2[0]
		by_name[base] = int(by_name.get(base, 0)) + 1
	var reps2 := []
	for k in by_name:
		if by_name[k] >= 2:
			reps2.append("%s x%d" % [k, by_name[k]])
	if not reps2.is_empty():
		lines.append("COUNTS BY NAME: " + ", ".join(reps2))
	lines.append("CONTACTS: %d overlap%s, %d touching, %d near (<= %.0f mm), %d apart" % [C["overlaps"].size(), "" if C["overlaps"].size() == 1 else "s", C["touches"].size(), C["near"].size(), NEAR_MM, C["apart"]])
	var fl := floats(M, comps)
	for fw in fl:
		lines.append("FLOATS: " + String(fw["text"]))
	if comps.size() > 1:
		lines.append("PIECES: " + "; ".join(comps.map(func(g): return "{" + _ids(g) + "}")))
	return {"ok": true, "bodies": M.n, "lines": lines, "volume_mm3": snappedf(tot, 0.01), "pieces": comps.size(), "repeats": rep.map(func(g): return (g as Array).map(func(i): return int(i) + 1)),
		"overlaps": C["overlaps"].map(func(p): return {"a": int(p[0]) + 1, "b": int(p[1]) + 1, "mm3": snappedf(p[2], 0.01)}), "apart_pairs": C["apart"],
		"data": data_b, "errors": M.errors, "floats": fl.map(func(q): return {"body": int(q["body"]) + 1, "name": q["label"], "gap_mm": q["gap_mm"], "to": int(q["to"]) + 1, "to_name": q["to_label"], "text": q["text"]})}


## s237 FLOATS (Nick looked at the temple: "the golden stuff are not connected, they are flying"): a SMALL piece (a group of bodies that touch or overlap,
## whose longest box side is at most FLOATS_SMALL of the part's longest side) that touches nothing, yet whose nearest other body is closer than
## FLOATS_NEAR x its own longest side: it LOOKS attached and is not. A gap of more than that is a piece standing apart on purpose (a lantern in a courtyard):
## look.floating says that one. -> [{"body": index of its biggest body, "label", "gap_mm", "to": index, "to_label", "size_mm", "text"}]
const FLOATS_SMALL := 0.25
const FLOATS_NEAR := 1.0


static func floats(M: Model, comps: Array = []) -> Array:
	var out: Array = []
	if M.n < 2:
		return out
	var groups: Array = comps if not comps.is_empty() else M.components()
	if groups.size() < 2:
		return out
	var whole := AABB()
	for i in M.n:
		whole = M.box(i) if i == 0 else whole.merge(M.box(i))
	var longest := maxf(whole.size.x, maxf(whole.size.y, whole.size.z))
	var owner := {}
	for gi in groups.size():
		for i in groups[gi]:
			owner[int(i)] = gi
	for gi in groups.size():
		var g: Array = groups[gi]
		var gb := AABB()
		var big := int(g[0])
		for k in g.size():
			var i := int(g[k])
			gb = M.box(i) if k == 0 else gb.merge(M.box(i))
			if M.vol_mm3[i] > M.vol_mm3[big]:
				big = i
		var side := maxf(gb.size.x, maxf(gb.size.y, gb.size.z))
		if side > FLOATS_SMALL * longest or side <= 0.0:
			continue
		var limit := FLOATS_NEAR * side
		var best := INF
		var best_j := -1
		for j in M.n:
			if int(owner[j]) == gi or aabb_gap(gb, M.box(j)) > limit:
				continue
			for i in g:
				var d := M.gap(int(i), j, minf(limit, best))
				if d < best:
					best = d
					best_j = j
		if best_j >= 0 and best > TOUCH_MM and best <= limit:
			out.append({"body": big, "label": String(M.labels[big]), "gap_mm": snappedf(best, 0.001), "to": best_j, "to_label": String(M.labels[best_j]), "size_mm": snappedf(side, 0.1),
				"text": "%s floats: it looks attached but is not. It touches nothing; its nearest piece, %s, is %.1f mm away (it is %.0f mm across)." % [M.labels[big], M.labels[best_j], best, side]})
	return out


static func _gap_s(g: float) -> String:
	return "%.3f" % g if g < 1.0 else "%.2f" % g


static func _cap_list(a: Array, cap: int) -> String:
	if a.size() <= cap:
		return ", ".join(a)
	return ", ".join(a.slice(0, cap)) + ", +%d more" % (a.size() - cap)
