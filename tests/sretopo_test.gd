## godot --path . -s tests/sretopo_test.gd     (lane I11 / SRETOPO: stroke-guided retopology; the roadmap id I11 is the fight phrase builder, tests/i11_test.gd; scripts/kmesh_retopo_*.gd, native/src/kine_retopo_native.cpp)
## Method: Takayama, Panozzo, Sorkine-Hornung, Sorkine-Hornung, "Sketch-Based Generation and Editing of Quad Meshes",
## ACM Transactions on Graphics 32(4), SIGGRAPH 2013, art. 97.
## BARS, COMMITTED BEFORE THE FIRST RUN (numbers fixed here; a fixture may be changed after a run only if the run shows it was wrong
## as a fixture, and that is said in the report, never the bar):
##   1 VALID PATCHES. For every side count n in 2..6 and every count vector d_i in 1..8 whose plan() is feasible, the filled patch
##     (a regular n-gon, flat, ccw seen from +z): every face has 4 distinct verts; the ring has sum(d_i) verts; every ring edge lies
##     in exactly 1 face and every other edge in exactly 2 (a manifold disk); no face is flipped (normal.z > 0); Euler V-E+F = 1.
##     The infeasible count vectors are listed with their reason (not filled). NETWORK: on the sphere network the baked mesh has every
##     edge in exactly 2 faces, no vertex lying inside another edge (no T-junction), and the count on a shared side is the same
##     from both patches. PLANTED (each must be caught by the same checker): a pair of patches whose shared side has 3 vs 4 edges
##     is flagged; one quad with its winding reversed is flagged as flipped; a vertex put on the middle of an edge is flagged T-junction.
##   2 SINGULARITIES. Interior (non-ring) vertices of valence != 4, per filled patch, <= MIN_SING[n] = {2:2, 3:1, 4:0, 5:1, 6:1}
##     (the Gauss-Bonnet count of a quad disk whose n corners have valence 2; KMeshRetopoFill header). Counts printed per n.
##     PLANTED: a patch with an extra valence-3 interior vertex is counted above the bound.
##   3 SURFACE FIT. Max distance from the baked mesh (vertices, edge midpoints, quad centres, 3x3 points per quad) to the source,
##     relative to the source bounding-box diagonal: sphere <= 1.0 %, the real mesh (mannequin head and torso from assets/mannequin.glb,
##     the densest organic surface in the repo) <= 2.5 %. The distance is measured against the analytic sphere / a brute-force
##     GDScript closest point on 40 samples, not only with the solver's own projection. PLANTED: the sphere baked mesh scaled 1.05
##     about the centre must read above its bound.
##   4 QUALITY. Minimum scaled Jacobian (min over a quad's 4 corners of the sine of the corner angle) of every quad >= 0.3 after
##     relaxation (20 iterations) on the sphere network and on the real-mesh network. PLANTED: the same curved patch with 0 relaxation
##     iterations must read below 0.3.
##   5 EDITS. Deleting a stroke merges its patches (count drops by the merged amount, the surviving patches that did not touch it are
##     bit-identical, the new patch solved). Changing a count re-solves ONLY the patches touching that side (solve counter per patch;
##     others bit-identical; the touched ones changed). Hand-set counts stay while auto counts of other arcs do not move.
##   6 SPEED. A 24-patch network (8 sectors x 3 bands on a sphere): the whole solve_patches call <= 50 ms, timed inside C++ (median of
##     5), and the edit re-solve (one side's count changed: 2-3 patches) <= 50 ms too; both printed.
##   7 C++ = GDScript. KMeshRetopoFill.fill vs KineRetopoNative.fill: every feasible count vector (n = 2..6, d_i in 1..8), ring points
##     perturbed by a fixed pseudo-random 0.3 jitter: verts within 1e-9, quads identical, plan() identical. PLANTED: one input
##     coordinate changed by 1e-6 on the C++ side must read above 1e-9.
##   8 UI. Q opens Retopo mode in the model preview (registry line mesh_retopo, do op:retopo); a drawn stroke (mouse events) snaps to
##     the surface; wheel over a side changes its count; Delete removes the hovered stroke; Bake replaces the mesh by an all-quad
##     mesh in ONE undo step and Ctrl+Z gives the source back exactly. The pole of the keys: Q was free in the model preview.
##   LOOK: screenshots of the mannequin head and torso: strokes, patches, baked quads with the heat map, beside the source.
## AMENDED after the first runs (fixtures only, no bar moved): (a) bar 3/4 real mesh: the stroke rings were at heights where
## the mannequin's head + chest piece is not a closed loop (its head shell is open below 1.67 m, its chest edge slants below
## 1.32 m), so they are now at 1.69 / 1.75 m (head) and 1.34 / 1.39 / 1.44 m (chest). (b) bar 4 planted: every patch of both
## networks already read >= 0.5 before relaxation, so none of them could be the planted; it is now a curved patch with skewed
## counts (the sphere's octant, sides 4, 10, 12), measured with 20 steps (>= 0.3) and with 0 (< 0.3).
extends SceneTree

const MIN_SING := {2: 2, 3: 1, 4: 0, 5: 1, 6: 1}
const SPHERE_FIT := 0.010
const REAL_FIT := 0.025
const SJ_MIN := 0.3
const SPEED_MS := 50.0
const EQ_TOL := 1e-9
const SHOT_DIR := "res://docs/sretopo/"

var fails := 0
var nat = null          # a KineRetopoNative for the plan / fill comparisons (no source)
var sphere: KMesh       # uv sphere r = 1 (64 x 32)
var man: KMesh          # the mannequin's head + chest piece
var man_strokes: Array = []
var _quit_done := false


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	if not c:
		fails += 1


func say(s: String) -> void:
	print("     " + s)


func _init() -> void:
	create_timer(380.0).timeout.connect(func():
		print("FAIL watchdog: the suite did not finish in 380 s")
		fails += 1
		_finish())
	if NativeExt.ensure("kine_native", "KineRetopoNative"):
		nat = ClassDB.instantiate("KineRetopoNative")
	ok(nat != null, "DLL: KineRetopoNative loads (version %s)" % (str(nat.version()) if nat != null else "-"))
	sphere = KMeshPrims.uv_sphere(1.0, 64, 32)
	man = load_man()
	ok(man != null and man.verts.size() > 300, "fixture: the mannequin head + chest piece (%s verts, %s faces)" % [str(man.verts.size()) if man else "-", str(man.face_count()) if man else "-"])
	bar_dictionary()       # 1 (patches), 2, 7
	bar_sphere_net()       # 1 (network), 3, 4 on the sphere
	bar_real_net()         # 3, 4 on the mannequin
	bar_edits_speed()      # 5, 6
	await bar_ui()         # 8 + LOOK
	_finish()


func _finish() -> void:
	if _quit_done:
		return
	_quit_done = true
	print("sretopo: %d failures" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)


# ====================================================================================== fixtures
## the head + chest piece of the mannequin's main surface (the connected piece holding the top of the head)
func load_man() -> KMesh:
	var sc := load("res://assets/mannequin.glb") as PackedScene
	if sc == null:
		return null
	var node: Node3D = sc.instantiate()
	var mis := node.find_children("*", "MeshInstance3D", true, false)
	if mis.is_empty():
		node.free()
		return null
	var am := (mis[0] as MeshInstance3D).mesh as ArrayMesh
	var k := KMesh.new().from_array_mesh(am, 0)
	node.free()
	var top := 0
	for i in k.verts.size():
		if k.verts[i].y > k.verts[top].y:
			top = i
	var nb := []
	nb.resize(k.verts.size())
	for i in nb.size():
		nb[i] = []
	for f in k.faces:
		for c in f.size():
			nb[f[c]].append(f[(c + 1) % f.size()])
			nb[f[(c + 1) % f.size()]].append(f[c])
	var keep := {top: true}
	var st := [top]
	while not st.is_empty():
		var v: int = st.pop_back()
		for w in nb[v]:
			if not keep.has(w):
				keep[w] = true
				st.append(w)
	var remap := {}
	var vs := PackedVector3Array()
	for i in k.verts.size():
		if keep.has(i):
			remap[i] = vs.size()
			vs.append(k.verts[i])
	var fs := []
	for f in k.faces:
		if keep.has(f[0]):
			var g := PackedInt32Array()
			for v in f:
				g.append(remap[v])
			fs.append(g)
	return KMesh.new().from_arrays(vs, fs)


static func bbox_diag(vs: PackedVector3Array) -> float:
	var bb := AABB(vs[0], Vector3.ZERO)
	for v in vs:
		bb = bb.expand(v)
	return bb.size.length()


## a closed circle stroke: centre c, through point s, in the plane with normal n (first point == last point)
static func circle(c: Vector3, s: Vector3, n: Vector3, m := 720) -> PackedVector3Array:
	var r := s - c
	var u := n.normalized().cross(r)
	var out := PackedVector3Array()
	for i in m:
		var a := TAU * float(i) / float(m)
		out.append(c + r * cos(a) + u * sin(a))
	out.append(out[0])
	return out


## strokes put on the net in one rebuild (each resampled and projected as add_stroke does)
static func put_strokes(net: KMeshRetopoNet, list: Array) -> void:
	for pl in list:
		var r: PackedVector3Array = net._resample(pl)
		if r.size() >= 2:
			net.strokes[net.next_id] = r
			net.next_id += 1
	net.rebuild()


## per baked face: the index of the patch it came from (KMeshRetopoNet.bake's order)
static func face_patches(net: KMeshRetopoNet) -> PackedInt32Array:
	var fp := PackedInt32Array()
	for pi in net.patches.size():
		var p: Dictionary = net.patches[pi]
		if p["valid"] and p["ok"]:
			for q in (p["quads"] as PackedInt32Array).size() / 4:
				fp.append(pi)
	return fp


static func ok_patches(net: KMeshRetopoNet) -> Array:
	var out := []
	for pi in net.patches.size():
		if net.patches[pi]["valid"] and net.patches[pi]["ok"]:
			out.append(pi)
	return out


static func patch_centre(p: Dictionary) -> Vector3:
	var pv: PackedFloat64Array = p["verts"]
	var c := Vector3.ZERO
	var n := pv.size() / 3
	for i in n:
		c += Vector3(pv[i * 3], pv[i * 3 + 1], pv[i * 3 + 2])
	return c / maxf(1.0, float(n))


# ====================================================================================== flat patches
## side i: d[i] + 1 points from corner i to corner i + 1 of a regular n-gon of radius 1, ccw seen from +z (n = 2: the two half
## circles); `jitter` moves every ring point by a fixed pseudo-random amount in x, y, z
static func ngon_sides(d: PackedInt32Array, jitter := 0.0, seed := 0) -> Array:
	var n := d.size()
	var ring := []
	for i in n:
		var c0 := Vector2(cos(TAU * float(i) / float(n)), sin(TAU * float(i) / float(n)))
		var c1 := Vector2(cos(TAU * float(i + 1) / float(n)), sin(TAU * float(i + 1) / float(n)))
		for k in d[i]:
			var t := float(k) / float(d[i])
			var p := c0.lerp(c1, t)
			if n == 2:
				var a := PI * (float(i) + t)
				p = Vector2(cos(a), sin(a))
			ring.append([p.x, p.y, 0.0])
	if jitter > 0.0:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		for r in ring:
			for c in 3:
				r[c] += rng.randf_range(-jitter, jitter)
	return sides_from_ring(ring, d)


static func sides_from_ring(ring: Array, d: PackedInt32Array) -> Array:
	var sides := []
	var o := 0
	for i in d.size():
		var f := PackedFloat64Array()
		for k in d[i] + 1:
			var q: Array = ring[(o + k) % ring.size()]
			f.append(q[0])
			f.append(q[1])
			f.append(q[2])
		sides.append(f)
		o += d[i]
	return sides


## the 4 sides of the rectangle x0..x1, y0..y1 (ccw from +z) with counts d
static func rect_sides(x0: float, y0: float, x1: float, y1: float, d: PackedInt32Array) -> Array:
	var cs := [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]
	var sides := []
	for i in 4:
		var f := PackedFloat64Array()
		for k in d[i] + 1:
			var p: Vector2 = (cs[i] as Vector2).lerp(cs[(i + 1) % 4], float(k) / float(d[i]))
			f.append(p.x)
			f.append(p.y)
			f.append(0.0)
		sides.append(f)
	return sides


## bar 1's patch checker on a filled flat patch: "" = a valid manifold disk, else what is wrong
static func check_patch(r: Dictionary, d: PackedInt32Array) -> String:
	var pv: PackedFloat64Array = r["verts"]
	var qv: PackedInt32Array = r["quads"]
	var nring: int = r["nring"]
	var nv := pv.size() / 3
	var nf := qv.size() / 4
	var sumd := 0
	for x in d:
		sumd += x
	if nring != sumd:
		return "the ring has %d verts, sum(d) = %d" % [nring, sumd]
	var ec := {}
	var used := {}
	for q in nf:
		var f := [qv[q * 4], qv[q * 4 + 1], qv[q * 4 + 2], qv[q * 4 + 3]]
		for i in 4:
			used[f[i]] = true
			for j in range(i + 1, 4):
				if f[i] == f[j]:
					return "quad %d repeats a vert" % q
		var nz := 0.0
		for i in 4:
			var a: int = f[i]
			var b: int = f[(i + 1) % 4]
			nz += (pv[a * 3] - pv[b * 3]) * (pv[a * 3 + 1] + pv[b * 3 + 1])
		if nz <= 0.0:
			return "quad %d is flipped (normal.z %s)" % [q, String.num_scientific(nz)]
		for i in 4:
			var a: int = f[i]
			var b: int = f[(i + 1) % 4]
			var key := mini(a, b) * 1000000 + maxi(a, b)
			ec[key] = int(ec.get(key, 0)) + 1
	var ringe := {}
	for i in nring:
		var a := i
		var b := (i + 1) % nring
		var key := mini(a, b) * 1000000 + maxi(a, b)
		ringe[key] = true
		if int(ec.get(key, 0)) != 1:
			return "ring edge %d-%d lies in %d faces" % [a, b, int(ec.get(key, 0))]
	for key in ec:
		if not ringe.has(key) and ec[key] != 2:
			return "inner edge %d-%d lies in %d faces" % [key / 1000000, key % 1000000, ec[key]]
	if used.size() != nv:
		return "%d verts are in no face" % (nv - used.size())
	if nv - ec.size() + nf != 1:
		return "Euler V-E+F = %d" % (nv - ec.size() + nf)
	return ""


## interior verts (not on the ring) whose valence is not 4
static func sing_count(quads: PackedInt32Array, nring: int) -> int:
	var nb := {}
	for q in quads.size() / 4:
		for k in 4:
			var a := quads[q * 4 + k]
			var b := quads[q * 4 + (k + 1) % 4]
			if not nb.has(a):
				nb[a] = {}
			if not nb.has(b):
				nb[b] = {}
			nb[a][b] = true
			nb[b][a] = true
	var n := 0
	for v in nb:
		if v >= nring and (nb[v] as Dictionary).size() != 4:
			n += 1
	return n


static func plan_same(a: Dictionary, b: Dictionary) -> bool:
	for k in ["ok", "kind", "reason", "n", "p", "alpha", "beta"]:
		if a.get(k) != b.get(k):
			return false
	return PackedInt32Array(a["f"]) == PackedInt32Array(b["f"]) and PackedInt32Array(a["singular"]) == PackedInt32Array(b["singular"])


## bars 1 (patches), 2 and 7: every count vector n = 2..6, d_i in 1..8
func bar_dictionary() -> void:
	var t0 := Time.get_ticks_msec()
	var all_valid := true
	var sing_ok := true
	var eq_ok := nat != null
	var worst_eq := 0.0
	var n_feas := 0
	for n in range(2, 7):
		var d := PackedInt32Array()
		d.resize(n)
		d.fill(1)
		var total := 0
		var feas := 0
		var bad := 0
		var first_bad := ""
		var reasons := {}
		var smax := 0
		var sover := 0
		var plan_diff := 0
		var quad_diff := 0
		var vmax := 0.0
		while true:
			total += 1
			var pg := KMeshRetopoFill.plan(d)
			if pg["ok"]:
				feas += 1
				var sides := ngon_sides(d)
				var r: Dictionary = nat.fill(sides) if nat != null else KMeshRetopoFill.fill(sides)
				var why := check_patch(r, d) if r.get("ok", false) else "fill failed: %s" % r.get("reason", "")
				if why != "":
					bad += 1
					if first_bad == "":
						first_bad = "%s: %s" % [str(d), why]
				else:
					var sc := sing_count(r["quads"], r["nring"])
					smax = maxi(smax, sc)
					if sc > MIN_SING[n]:
						sover += 1
				if nat != null:
					if not plan_same(pg, nat.plan(d)):
						plan_diff += 1
					var sj := ngon_sides(d, 0.3, total * 7919 + n)
					var rg := KMeshRetopoFill.fill(sj)
					var rc: Dictionary = nat.fill(sj)
					if not (rg["ok"] and rc.get("ok", false)) or PackedInt32Array(rg["quads"]) != PackedInt32Array(rc["quads"]) or (rg["verts"] as PackedFloat64Array).size() != (rc["verts"] as PackedFloat64Array).size():
						quad_diff += 1
					else:
						var a: PackedFloat64Array = rg["verts"]
						var b: PackedFloat64Array = rc["verts"]
						for i in a.size():
							vmax = maxf(vmax, absf(a[i] - b[i]))
			else:
				var rs: String = pg["reason"]
				if not reasons.has(rs):
					reasons[rs] = [0, []]
				reasons[rs][0] += 1
				if (reasons[rs][1] as Array).size() < 3:
					(reasons[rs][1] as Array).append(str(d))
			var i := 0
			while i < n:
				d[i] += 1
				if d[i] <= 8:
					break
				d[i] = 1
				i += 1
			if i == n:
				break
		n_feas += feas
		all_valid = all_valid and bad == 0 and feas > 0
		sing_ok = sing_ok and sover == 0
		say("n = %d: %d count vectors, %d feasible, %d invalid fills%s" % [n, total, feas, bad, ("" if first_bad == "" else " (first: %s)" % first_bad)])
		for rs in reasons:
			say("   infeasible %d x \"%s\", e.g. %s" % [reasons[rs][0], rs, ", ".join(PackedStringArray(reasons[rs][1]))])
		say("   SINGULARITIES n = %d: max %d interior singular verts per patch (bound MIN_SING = %d), %d above" % [n, smax, MIN_SING[n], sover])
		if nat != null:
			say("   C++ = GD n = %d: plan differs %d, quads differ %d, verts max diff %s" % [n, plan_diff, quad_diff, String.num_scientific(vmax)])
			eq_ok = eq_ok and plan_diff == 0 and quad_diff == 0 and vmax <= EQ_TOL
			worst_eq = maxf(worst_eq, vmax)
	ok(all_valid, "1 VALID PATCHES: every feasible count vector (%d, n = 2..6, d_i 1..8) fills a manifold disk: 4 distinct verts per face, ring = sum(d), ring edges in 1 face, inner in 2, nothing flipped, Euler 1 (%d ms)" % [n_feas, Time.get_ticks_msec() - t0])
	ok(sing_ok, "2 SINGULARITIES: every filled patch has <= MIN_SING[n] interior singular verts (counts per n above)")
	# 2 planted: a diagonal collapse inside a 4 x 4 grid puts in valence-3 interior verts
	var g := KMeshRetopoFill.fill(rect_sides(0, 0, 1, 1, PackedInt32Array([4, 4, 4, 4])))
	var gq: PackedInt32Array = g["quads"]
	var nring: int = g["nring"]
	var victim := -1
	for q in gq.size() / 4:
		var all_in := true
		for c in 4:
			all_in = all_in and gq[q * 4 + c] >= nring
		if all_in:
			victim = q
			break
	var keep_v := gq[victim * 4]
	var gone_v := gq[victim * 4 + 2]
	var pq := PackedInt32Array()
	for q in gq.size() / 4:
		if q == victim:
			continue
		for c in 4:
			var v := gq[q * 4 + c]
			pq.append(keep_v if v == gone_v else v)
	var s0 := sing_count(gq, nring)
	var s1 := sing_count(pq, nring)
	ok(s0 == 0 and s1 > MIN_SING[4], "2 PLANTED: a 4-sided 4 x 4 patch has %d interior singular verts; with one quad collapsed on its diagonal (two valence-3 verts) %d > %d is counted above the bound" % [s0, s1, MIN_SING[4]])
	# 7
	if nat == null:
		ok(false, "7 C++ = GDScript: no KineRetopoNative")
		return
	ok(eq_ok, "7 C++ = GDScript: every feasible count vector, jittered 0.3: plan identical, quads identical, verts max diff %s (<= 1e-9)" % String.num_scientific(worst_eq))
	var dd := PackedInt32Array([3, 4, 5])
	var sj := ngon_sides(dd, 0.3, 4242)
	var sj2 := []
	for s in sj:
		sj2.append((s as PackedFloat64Array).duplicate())
	var s0p: PackedFloat64Array = sj2[0]   # a packed array in an Array is a copy: change it, put it back
	s0p[3] += 1e-6
	sj2[0] = s0p
	var ra := KMeshRetopoFill.fill(sj)
	var rb: Dictionary = nat.fill(sj2)
	var pm := 0.0
	var va: PackedFloat64Array = ra["verts"]
	var vb: PackedFloat64Array = rb["verts"]
	for i in va.size():
		pm = maxf(pm, absf(va[i] - vb[i]))
	ok(pm > EQ_TOL, "7 PLANTED: one input coordinate moved by 1e-6 on the C++ side reads %s (> 1e-9)" % String.num_scientific(pm))


# ====================================================================================== network checker
## bar 1's network checker: edges not in exactly 2 faces, faces flipped against outward(centre), verts lying inside another
## edge (T-junctions), and pairs of patches whose shared side has a different edge count from each side
static func check_net(vs: PackedVector3Array, faces: Array, fp: PackedInt32Array, outward: Callable) -> Dictionary:
	var diag := bbox_diag(vs)
	var tol := 1e-5 * diag
	var ec := {}
	var flipped := 0
	var maxe := 0.0
	for fi in faces.size():
		var f: PackedInt32Array = faces[fi]
		var nrm := Vector3.ZERO
		var c := Vector3.ZERO
		for i in f.size():
			var a := vs[f[i]]
			var b := vs[f[(i + 1) % f.size()]]
			nrm += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
			c += a
			maxe = maxf(maxe, a.distance_to(b))
			var key := Vector2i(mini(f[i], f[(i + 1) % f.size()]), maxi(f[i], f[(i + 1) % f.size()]))
			ec[key] = int(ec.get(key, 0)) + 1
		c /= float(f.size())
		if nrm.dot(outward.call(c)) <= 0.0:
			flipped += 1
	var edges_bad := 0
	for key in ec:
		if ec[key] != 2:
			edges_bad += 1
	# T-junctions: a hash of the verts, every edge asks the cells it passes
	var cell := maxf(maxe, 1e-6)
	var grid := {}
	for i in vs.size():
		var k := Vector3i((vs[i] / cell).floor())
		if not grid.has(k):
			grid[k] = []
		(grid[k] as Array).append(i)
	var tj := 0
	for key in ec:
		var a := vs[key.x]
		var b := vs[key.y]
		var ab := b - a
		var l2 := ab.length_squared()
		if l2 < 1e-24:
			continue
		var lo := Vector3i((a.min(b) / cell).floor())
		var hi := Vector3i((a.max(b) / cell).floor())
		for x in range(lo.x, hi.x + 1):
			for y in range(lo.y, hi.y + 1):
				for z in range(lo.z, hi.z + 1):
					var kk := Vector3i(x, y, z)
					if not grid.has(kk):
						continue
					for w in grid[kk]:
						if w == key.x or w == key.y:
							continue
						var t := (vs[w] - a).dot(ab) / l2
						if t > 1e-4 and t < 1.0 - 1e-4 and vs[w].distance_to(a + ab * t) < tol:
							tj += 1
	# shared sides: per patch its border edges; a border edge of P lies on Q's border when its ends and middle do
	var border := {}   # patch -> [[a, b]]
	var pe := {}
	for fi in faces.size():
		var f: PackedInt32Array = faces[fi]
		for i in f.size():
			var key := Vector3i(fp[fi], mini(f[i], f[(i + 1) % f.size()]), maxi(f[i], f[(i + 1) % f.size()]))
			pe[key] = int(pe.get(key, 0)) + 1
	for key in pe:
		if pe[key] == 1:
			if not border.has(key.x):
				border[key.x] = []
			(border[key.x] as Array).append([vs[key.y], vs[key.z]])
	var mismatch := 0
	var pl := border.keys()
	for i in pl.size():
		for j in range(i + 1, pl.size()):
			var cp := _on_border(border[pl[i]], border[pl[j]], tol)
			var cq := _on_border(border[pl[j]], border[pl[i]], tol)
			if (cp > 0 or cq > 0) and cp != cq:
				mismatch += 1
	return {"edges_bad": edges_bad, "flipped": flipped, "tjunc": tj, "mismatch": mismatch, "edges": ec.size()}


static func _seg_d(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0 if l2 < 1e-24 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## how many edges of `mine` lie on the polyline made of `other`'s edges
static func _on_border(mine: Array, other: Array, tol: float) -> int:
	var n := 0
	for e in mine:
		var hit := 0
		for p in [e[0], e[1], (e[0] + e[1]) * 0.5]:
			for o in other:
				if _seg_d(p, o[0], o[1]) < tol:
					hit += 1
					break
		if hit == 3:
			n += 1
	return n


# ====================================================================================== measures
## the points of a quad mesh a fit is measured on: verts, edge midpoints, 3 x 3 points per quad
static func fit_points(vs: PackedVector3Array, faces: Array) -> PackedVector3Array:
	var out := PackedVector3Array(vs)
	for f in faces:
		var n: int = f.size()
		for i in n:
			out.append((vs[f[i]] + vs[f[(i + 1) % n]]) * 0.5)
		if n == 4:
			for u in [0.25, 0.5, 0.75]:
				for w in [0.25, 0.5, 0.75]:
					out.append(vs[f[0]] * ((1.0 - u) * (1.0 - w)) + vs[f[1]] * (u * (1.0 - w)) + vs[f[2]] * (u * w) + vs[f[3]] * ((1.0 - u) * w))
	return out


## min over quads of min over corners of the sine of the corner angle, signed by the quad's normal
static func min_sj(vs: PackedVector3Array, faces: Array) -> float:
	var m := 1.0
	for f in faces:
		if f.size() != 4:
			continue
		var nrm := Vector3.ZERO
		for i in 4:
			var a := vs[f[i]]
			var b := vs[f[(i + 1) % 4]]
			nrm += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
		nrm = nrm.normalized()
		for i in 4:
			var p := vs[f[i]]
			var e1 := vs[f[(i + 1) % 4]] - p
			var e2 := vs[f[(i + 3) % 4]] - p
			var den := e1.length() * e2.length()
			var s := -1.0 if den < 1e-20 else e1.cross(e2).dot(nrm) / den
			m = minf(m, s)
	return m


static func min_sj_patch(r: Dictionary) -> float:
	var pv: PackedFloat64Array = r["verts"]
	var qv: PackedInt32Array = r["quads"]
	var vs := PackedVector3Array()
	for i in pv.size() / 3:
		vs.append(Vector3(pv[i * 3], pv[i * 3 + 1], pv[i * 3 + 2]))
	var fs := []
	for q in qv.size() / 4:
		fs.append(PackedInt32Array([qv[q * 4], qv[q * 4 + 1], qv[q * 4 + 2], qv[q * 4 + 3]]))
	return min_sj(vs, fs)


## Ericson's closest point on a triangle
static func tri_closest(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var den := 1.0 / (va + vb + vc)
	return a + ab * (vb * den) + ac * (vc * den)


static func brute_dist(p: Vector3, k: KMesh) -> float:
	var best := INF
	for f in k.faces:
		for t in range(1, f.size() - 1):
			best = minf(best, p.distance_to(tri_closest(p, k.verts[f[0]], k.verts[f[t]], k.verts[f[t + 1]])))
	return best


# ====================================================================================== sphere network (bars 1, 3, 4)
func sphere_net_a() -> KMeshRetopoNet:
	var net := KMeshRetopoNet.new()
	net.setup(sphere, 0.15)
	put_strokes(net, [circle(Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 0, 1)), circle(Vector3.ZERO, Vector3(0, 1, 0), Vector3(1, 0, 0)),
		circle(Vector3.ZERO, Vector3(0, 0, 1), Vector3(0, 1, 0))])
	return net


func bar_sphere_net() -> void:
	var net := sphere_net_a()
	var st := net.stats()
	say("sphere network (3 great circles, edge 0.15): %s; notes %s" % [str(st), str(net.notes)])
	for p in net.patches:
		if p["valid"] and not p["ok"]:
			say("   patch not filled: %s (%s)" % [p["reason"], p["kind"]])
	var k := net.bake()
	var fp := face_patches(net)
	ok(st["patches"] == 8 and k.face_count() > 0, "sphere network: 8 three-sided patches filled (%d patches, %d unsolved, %d quads)" % [st["patches"], st["unsolved"], k.face_count()])
	if k.face_count() == 0:
		ok(false, "1 NETWORK / 3 / 4 on the sphere: nothing baked")
		return
	var outward := func(c: Vector3) -> Vector3: return c
	var chk := check_net(k.verts, k.faces, fp, outward)
	ok(chk["edges_bad"] == 0 and chk["tjunc"] == 0 and chk["mismatch"] == 0 and chk["flipped"] == 0,
		"1 NETWORK: the baked sphere (%d quads, %d edges): edges not in 2 faces %d, T-junctions %d, shared sides with unequal counts %d, flipped %d" % [k.face_count(), chk["edges"], chk["edges_bad"], chk["tjunc"], chk["mismatch"], chk["flipped"]])
	# planted: unequal shared side
	var ra := KMeshRetopoFill.fill(rect_sides(0, 0, 1, 1, PackedInt32Array([3, 3, 3, 3])))
	var rb := KMeshRetopoFill.fill(rect_sides(1, 0, 2, 1, PackedInt32Array([3, 4, 3, 4])))
	var wv := PackedVector3Array()
	var wf := []
	var wfp := PackedInt32Array()
	var at := {}
	for pi in 2:
		var r: Dictionary = [ra, rb][pi]
		var pv: PackedFloat64Array = r["verts"]
		var qv: PackedInt32Array = r["quads"]
		var loc := {}
		for i in pv.size() / 3:
			var p := Vector3(pv[i * 3], pv[i * 3 + 1], pv[i * 3 + 2])
			var key := Vector3i((p * 1e6).round())
			if not at.has(key):
				at[key] = wv.size()
				wv.append(p)
			loc[i] = at[key]
		for q in qv.size() / 4:
			wf.append(PackedInt32Array([loc[qv[q * 4]], loc[qv[q * 4 + 1]], loc[qv[q * 4 + 2]], loc[qv[q * 4 + 3]]]))
			wfp.append(pi)
	var cm := check_net(wv, wf, wfp, func(_c: Vector3) -> Vector3: return Vector3(0, 0, 1))
	var ff := k.faces.duplicate()
	var f0: PackedInt32Array = (ff[0] as PackedInt32Array).duplicate()
	f0.reverse()
	ff[0] = f0
	var cf := check_net(k.verts, ff, fp, outward)
	var tv := k.verts.duplicate()
	var tf := k.faces.duplicate()
	var g0: PackedInt32Array = tf[0]
	tv.append((tv[g0[0]] + tv[g0[1]]) * 0.5)
	tf[0] = PackedInt32Array([g0[0], tv.size() - 1, g0[1], g0[2], g0[3]])
	var ct := check_net(tv, tf, fp, outward)
	ok(cm["mismatch"] > 0 and cf["flipped"] > 0 and ct["tjunc"] > 0,
		"1 PLANTED: shared side 3 vs 4 edges flagged %d, one quad reversed flagged flipped %d, a vert on the middle of an edge flagged T-junction %d" % [cm["mismatch"], cf["flipped"], ct["tjunc"]])
	# 3 fit against the analytic sphere
	var pts := fit_points(k.verts, k.faces)
	var diag := bbox_diag(sphere.verts)
	var worst := 0.0
	for p in pts:
		worst = maxf(worst, absf(p.length() - 1.0))
	var scaled := PackedVector3Array()
	for v in k.verts:
		scaled.append(v * 1.05)
	var worst2 := 0.0
	for p in fit_points(scaled, k.faces):
		worst2 = maxf(worst2, absf(p.length() - 1.0))
	ok(worst / diag <= SPHERE_FIT, "3 SURFACE FIT sphere: max distance to the analytic sphere %.3f %% of the diagonal over %d points (<= 1.0 %%)" % [100.0 * worst / diag, pts.size()])
	ok(worst2 / diag > SPHERE_FIT, "3 PLANTED: the baked sphere scaled 1.05 reads %.3f %% (> 1.0 %%)" % [100.0 * worst2 / diag])
	var sj := min_sj(k.verts, k.faces)
	ok(sj >= SJ_MIN, "4 QUALITY sphere: min scaled Jacobian %.3f after %d relaxation steps (>= 0.3)" % [sj, net.iters])
	# 4 planted: a curved patch with skewed counts, the sphere's octant with sides of 4, 10 and 12 edges (great-circle arcs),
	# solved with 20 steps and with 0. (First run: the networks' own patches all read >= 0.5 unrelaxed, so none could be the
	# planted; this fixture replaced it, see the header's AMENDED note.)
	var oct := [arc_pts(Vector3(1, 0, 0), Vector3(0, 1, 0), 4), arc_pts(Vector3(0, 1, 0), Vector3(0, 0, 1), 10), arc_pts(Vector3(0, 0, 1), Vector3(1, 0, 0), 12)]
	var o20 := min_sj_patch(net.nat.solve_patch(oct, 20))
	var o0 := min_sj_patch(net.nat.solve_patch(oct, 0))
	ok(o20 >= SJ_MIN and o0 < SJ_MIN, "4 PLANTED: the skewed octant patch (sides 4, 10, 12) reads %.3f after 20 relaxation steps and %.3f with 0 (< 0.3)" % [o20, o0])


## points along the great circle from a to b (unit vectors), n edges, flat xyz
static func arc_pts(a: Vector3, b: Vector3, n: int) -> PackedFloat64Array:
	var f := PackedFloat64Array()
	for k in n + 1:
		var p := a.slerp(b, float(k) / float(n))
		f.append(p.x)
		f.append(p.y)
		f.append(p.z)
	return f


# ====================================================================================== the mannequin (bars 3, 4)
## the closed sections of k by the plane n.x = d, as polylines (a closed one ends where it starts)
static func section(k: KMesh, n: Vector3, d: float) -> Array:
	var s := PackedFloat64Array()
	s.resize(k.verts.size())
	for i in k.verts.size():
		s[i] = n.dot(k.verts[i]) - d
	var pt := {}
	var adj := {}
	for f in k.faces:
		for t in range(1, f.size() - 1):
			var tri := [f[0], f[t], f[t + 1]]
			var ks := []
			for e in 3:
				var a: int = tri[e]
				var b: int = tri[(e + 1) % 3]
				if (s[a] > 0.0) != (s[b] > 0.0):
					var key := Vector2i(mini(a, b), maxi(a, b))
					if not pt.has(key):
						pt[key] = k.verts[a].lerp(k.verts[b], s[a] / (s[a] - s[b]))
					ks.append(key)
			if ks.size() == 2:
				for z in 2:
					if not adj.has(ks[z]):
						adj[ks[z]] = []
					(adj[ks[z]] as Array).append(ks[1 - z])
	var used := {}
	var out := []
	var order := []
	for key in adj:
		if (adj[key] as Array).size() == 1:
			order.append(key)
	order.append_array(adj.keys())
	for st in order:
		if used.has(st):
			continue
		used[st] = true
		var chain := PackedVector3Array([pt[st]])
		var cur = st
		while true:
			var nxt = null
			for o in adj[cur]:
				if not used.has(o):
					nxt = o
					break
			if nxt == null:
				if chain.size() > 2 and (adj[cur] as Array).has(st):
					chain.append(pt[st])
				break
			used[nxt] = true
			chain.append(pt[nxt])
			cur = nxt
		out.append(chain)
	return out


static func poly_len(pl: PackedVector3Array) -> float:
	var l := 0.0
	for i in range(1, pl.size()):
		l += pl[i].distance_to(pl[i - 1])
	return l


## the ring of k at height y, starting where it crosses x = 0 in front (largest z)
static func ring_at(k: KMesh, y: float) -> PackedVector3Array:
	var best := PackedVector3Array()
	for c in section(k, Vector3.UP, y):
		var cc: PackedVector3Array = c
		if cc.size() > 3 and cc[0] == cc[cc.size() - 1] and poly_len(cc) > poly_len(best):
			best = cc
	if best.is_empty():
		return best
	var u := best.slice(0, best.size() - 1)
	var m := u.size()
	var bi := -1
	var bz := -INF
	var bp := Vector3.ZERO
	for i in m:
		var a := u[i]
		var b := u[(i + 1) % m]
		if (a.x <= 0.0) != (b.x <= 0.0):
			var p := a.lerp(b, a.x / (a.x - b.x))
			if p.z > bz:
				bz = p.z
				bi = i
				bp = p
	if bi < 0:
		return best
	var out := PackedVector3Array([bp])
	for j in range(1, m + 1):
		out.append(u[(bi + j) % m])
	out.append(bp)
	return out


## the pieces of the sections of k by the plane n.x = d that lie between heights ylo and yhi (longer than lmin)
static func runs_between(k: KMesh, n: Vector3, d: float, ylo: float, yhi: float, lmin: float) -> Array:
	var out := []
	for c in section(k, n, d):
		var cc: PackedVector3Array = c
		var closed := cc.size() > 3 and cc[0] == cc[cc.size() - 1]
		if closed:   # start outside the band so no run wraps round the start
			var u := cc.slice(0, cc.size() - 1)
			var s0 := -1
			for i in u.size():
				if u[i].y < ylo or u[i].y > yhi:
					s0 = i
					break
			if s0 < 0:
				continue
			cc = PackedVector3Array()
			for j in u.size() + 1:
				cc.append(u[(s0 + j) % u.size()])
		var cur := PackedVector3Array()
		for i in cc.size():
			var p := cc[i]
			var inside := p.y >= ylo and p.y <= yhi
			if i > 0:
				var q := cc[i - 1]
				var qin := q.y >= ylo and q.y <= yhi
				if inside != qin:
					var lim := ylo if (p.y < ylo or q.y < ylo) else yhi
					var x := q.lerp(p, (lim - q.y) / (p.y - q.y))
					cur.append(x)
					if not inside:
						if poly_len(cur) > lmin:
							out.append(cur)
						cur = PackedVector3Array()
			if inside:
				cur.append(p)
		if poly_len(cur) > lmin:
			out.append(cur)
	return out


static func z_mid(k: KMesh, ylo: float, yhi: float) -> float:
	var lo := INF
	var hi := -INF
	for v in k.verts:
		if v.y >= ylo and v.y <= yhi:
			lo = minf(lo, v.z)
			hi = maxf(hi, v.z)
	return (lo + hi) * 0.5


## the head: rings at 1.69 and 1.75 m, two section planes over the top; the chest: rings at 1.34, 1.39, 1.44 m and the
## same two planes between 1.315 and 1.465 m (stroke ends run 2.5 cm past the outer rings and are left loose). The piece is
## a closed loop only at 1.32-1.48 m (chest) and above 1.67 m (head): below, the head shell is open and the chest's lower
## edge slants. (The first run used rings at 1.62 / 1.255 / 1.295 m, which are not closed loops on this mesh: fixture fixed.)
static func make_man_strokes(k: KMesh) -> Array:
	var out := []
	for y in [1.69, 1.75, 1.34, 1.39, 1.44]:
		var r := ring_at(k, y)
		if r.size() > 3:
			out.append(r)
	var zh := z_mid(k, 1.67, 2.0)
	var zt := z_mid(k, 1.33, 1.45)
	out.append_array(runs_between(k, Vector3(1, 0, 0), 1e-4, 1.665, 9.0, 0.08))
	out.append_array(runs_between(k, Vector3(0, 0, 1), zh + 1e-4, 1.665, 9.0, 0.08))
	out.append_array(runs_between(k, Vector3(1, 0, 0), 1e-4, 1.315, 1.465, 0.06))
	out.append_array(runs_between(k, Vector3(0, 0, 1), zt + 1e-4, 1.315, 1.465, 0.06))
	return out


func real_net() -> KMeshRetopoNet:
	var net := KMeshRetopoNet.new()
	net.setup(man, 0.03)
	put_strokes(net, man_strokes)
	return net


func bar_real_net() -> void:
	if man == null:
		ok(false, "3 / 4 real mesh: no mannequin")
		return
	man_strokes = make_man_strokes(man)
	var net := real_net()
	var st := net.stats()
	say("mannequin network: %d strokes (%s); %s; notes %s" % [man_strokes.size(), ", ".join(PackedStringArray(man_strokes.map(func(s): return "%.0f cm" % (poly_len(s) * 100.0)))), str(st), str(net.notes)])
	var kinds := {}
	for p in net.patches:
		if not p["valid"]:
			say("   region skipped: %s" % p["reason"])
		elif not p["ok"]:
			say("   patch not filled: %s (%s, sides %s)" % [p["reason"], p["kind"], str(net.side_counts(p))])
		else:
			kinds[p["kind"]] = int(kinds.get(p["kind"], 0)) + 1
	say("   filled: %s" % str(kinds))
	var k := net.bake()
	ok(st["patches"] >= 16 and st["unsolved"] == 0 and k.face_count() > 0, "real mesh network: %d patches filled (>= 16: 8 on the head, 8 on the chest), %d unsolved, %d quads" % [st["patches"], st["unsolved"], k.face_count()])
	if k.face_count() == 0 or net.nat == null:
		ok(false, "3 / 4 real mesh: nothing baked or no native solver")
		return
	var pts := fit_points(k.verts, k.faces)
	var flat := PackedFloat64Array()
	for p in pts:
		flat.append(p.x)
		flat.append(p.y)
		flat.append(p.z)
	var pr: Dictionary = net.nat.project(flat)
	var dist: PackedFloat64Array = pr["dist"]
	var worst := 0.0
	for x in dist:
		worst = maxf(worst, x)
	var agree := 0.0
	var bworst := 0.0
	for s in 40:
		var i := int(float(s) * float(pts.size() - 1) / 39.0)
		var bd := brute_dist(pts[i], man)
		bworst = maxf(bworst, bd)
		agree = maxf(agree, absf(bd - dist[i]))
	worst = maxf(worst, bworst)
	var diag := bbox_diag(man.verts)
	ok(worst / diag <= REAL_FIT and agree < 1e-5, "3 SURFACE FIT real mesh: max distance to the mannequin %.3f %% of the diagonal (%.1f mm of %.0f cm) over %d points (<= 2.5 %%); the brute-force GDScript closest point on 40 samples agrees with the solver's to %s" % [100.0 * worst / diag, worst * 1000.0, diag * 100.0, pts.size(), String.num_scientific(agree)])
	var sj := min_sj(k.verts, k.faces)
	ok(sj >= SJ_MIN, "4 QUALITY real mesh: min scaled Jacobian %.3f after %d relaxation steps (>= 0.3)" % [sj, net.iters])
	# the patch of this network that reads lowest before relaxation (printed: it is not the planted, see bar_sphere_net)
	var low := INF
	var low20 := INF
	var lowk := ""
	for pi in ok_patches(net):
		var p: Dictionary = net.patches[pi]
		var sides := net.sides_of(p, net.ring_of(p))
		var r0: Dictionary = net.nat.solve_patch(sides, 0)
		var s0 := min_sj_patch(r0)
		if s0 < low:
			low = s0
			low20 = min_sj_patch(net.nat.solve_patch(sides, 20))
			lowk = "%s %s" % [p["kind"], str(net.side_counts(p))]
	say("real mesh: its lowest patch before relaxation (%s) reads %.3f with 0 steps, %.3f with 20" % [lowk, low, low20])


# ====================================================================================== edits + speed (bars 5, 6)
## 8 sectors x 3 bands: 4 great circles through the poles, rings at y = +-0.5
func sphere_net_b() -> Dictionary:
	var net := KMeshRetopoNet.new()
	net.setup(sphere)
	var list := []
	for i in 4:
		var a := PI * float(i) / 4.0
		list.append(circle(Vector3.ZERO, Vector3(0, 1, 0), Vector3(cos(a), 0, sin(a))))
	var r := sqrt(0.75)
	list.append(circle(Vector3(0, 0.5, 0), Vector3(0, 0.5, r), Vector3.UP))
	list.append(circle(Vector3(0, -0.5, 0), Vector3(0, -0.5, r), Vector3.UP))
	put_strokes(net, list)
	return {"net": net, "north": 5, "south": 6}


static func arc_near(net: KMeshRetopoNet, mid: Vector3) -> int:
	var bi := -1
	var bd := INF
	for ai in net.arcs.size():
		var d: float = net._mid(net.arcs[ai]["pts"]).distance_to(mid)
		if d < bd:
			bd = d
			bi = ai
	return bi


static func patch_near(net: KMeshRetopoNet, c: Vector3) -> int:
	var bi := -1
	var bd := INF
	for pi in ok_patches(net):
		var d := patch_centre(net.patches[pi]).distance_to(c)
		if d < bd:
			bd = d
			bi = pi
	return bi


static func med(a: Array) -> float:
	var s := a.duplicate()
	s.sort()
	return float(s[s.size() / 2])


func bar_edits_speed() -> void:
	var t0 := Time.get_ticks_msec()
	var b := sphere_net_b()
	var net: KMeshRetopoNet = b["net"]
	var st := net.stats()
	say("24-patch sphere network: %s (%d ms to build)" % [str(st), Time.get_ticks_msec() - t0])
	for p in net.patches:
		if p["valid"] and not p["ok"]:
			say("   patch not filled: %s (%s, sides %s)" % [p["reason"], p["kind"], str(net.side_counts(p))])
	ok(st["patches"] == 24 and st["unsolved"] == 0, "24-patch network: %d patches filled (8 sectors x 3 bands), %d unsolved" % [st["patches"], st["unsolved"]])
	if net.nat == null or st["patches"] == 0:
		ok(false, "5 / 6: no network")
		return
	# 6 the whole solve
	var all := []
	for pi in ok_patches(net):
		all.append(net.sides_of(net.patches[pi], net.ring_of(net.patches[pi])))
	var ms := []
	for rep in 5:
		ms.append(float(net.nat.solve_patches(all, 20)["ms"]))
	var ms_all := med(ms)
	# 5 a count change: a south-ring arc (its band quad's opposite side follows), 2-3 patches
	var south: int = b["south"]
	var ai := -1
	for i in net.arcs.size():
		if net.arcs[i]["stroke"] == south and (net.arcs[i]["patches"] as Array).size() == 2:
			ai = i
			break
	var counts0 := []
	for a in net.arcs:
		counts0.append(a["count"])
	var verts0 := {}
	var stamp0 := {}
	for pi in net.patches.size():
		verts0[pi] = net.patches[pi]["verts"]
		stamp0[pi] = net.patches[pi].get("solved_at", 0)
	var calls0 := net.solve_calls
	# the step that keeps the touched patches fillable (+2 keeps the parity)
	var delta := 0
	for dl in [2, -2, 4, -4]:
		var c0: int = net.arcs[ai]["count"]
		if c0 + dl < 1:
			continue
		var opp := -1
		for pi in net.arcs[ai]["patches"]:
			var o := net._opposite_arc(net.patches[pi], ai)
			if o >= 0:
				opp = o
		var ch := [ai] if opp < 0 else [ai, opp]
		for a in ch:
			net.arcs[a]["count"] += dl
		var good := true
		for a in ch:
			for pi in net.arcs[a]["patches"]:
				good = good and KMeshRetopoFill.plan(net.side_counts(net.patches[pi]))["ok"]
		for a in ch:
			net.arcs[a]["count"] -= dl
		if good:
			delta = dl
			break
	var c_before: int = net.arcs[ai]["count"]
	var solved: Array = net.set_count(ai, c_before + delta, true)
	var changed := []
	for i in net.arcs.size():
		if net.arcs[i]["count"] != counts0[i]:
			changed.append(i)
	var expect := {}
	for a in changed:
		for pi in net.arcs[a]["patches"]:
			expect[pi] = true
	var resolved := []
	var same_ok := true
	var touched_changed := true
	for pi in net.patches.size():
		if not (net.patches[pi]["valid"] and net.patches[pi]["ok"]):
			continue
		var was: int = stamp0.get(pi, 0)
		if int(net.patches[pi].get("solved_at", 0)) != was:
			resolved.append(pi)
		if expect.has(pi):
			touched_changed = touched_changed and net.patches[pi]["verts"] != verts0[pi]
		else:
			same_ok = same_ok and net.patches[pi]["verts"] == verts0[pi]
	resolved.sort()
	var ek := expect.keys()
	ek.sort()
	ok(delta != 0 and resolved == ek and ek.size() >= 2 and ek.size() <= 3 and same_ok and touched_changed and net.solve_calls - calls0 == ek.size(),
		"5 COUNT: arc %d %d -> %d (with its opposite: arcs %s changed): re-solved patches %s = the patches touching them %s (%d solves); the others bit-identical %s, the touched changed %s" % [ai, c_before, net.arcs[ai]["count"], str(changed), str(resolved), str(ek), net.solve_calls - calls0, str(same_ok), str(touched_changed)])
	var others_still := true
	for i in net.arcs.size():
		if not changed.has(i) and net.arcs[i]["count"] != counts0[i]:
			others_still = false
	# 6 the edit re-solve
	var edit := []
	for pi in ek:
		edit.append(net.sides_of(net.patches[pi], net.ring_of(net.patches[pi])))
	var ms2 := []
	for rep in 5:
		ms2.append(float(net.nat.solve_patches(edit, 20)["ms"]))
	var ms_edit := med(ms2)
	ok(ms_all <= SPEED_MS and ms_edit <= SPEED_MS, "6 SPEED: solve_patches on the 24 patches %.2f ms, the edit re-solve (%d patches) %.2f ms, medians of 5 timed in C++ (<= 50 ms each)" % [ms_all, ek.size(), ms_edit])
	# 5 delete the north ring: its 16 patches merge pairwise into 8; the 8 south caps stay bit-identical
	var north: int = b["north"]
	var pinned_mid: Vector3 = net._mid(net.arcs[ai]["pts"])
	var pinned_count: int = net.arcs[ai]["count"]
	var keep_counts := []   # [mid, count] of the arcs south of the south ring, and the south ring's
	for a in net.arcs:
		var m: Vector3 = net._mid(a["pts"])
		if m.y < -0.45:
			keep_counts.append([m, a["count"]])
	var touched := {}
	var parent := {}
	for i in net.arcs.size():
		if net.arcs[i]["stroke"] == north:
			var ps: Array = net.arcs[i]["patches"]
			for pi in ps:
				touched[pi] = true
				if not parent.has(pi):
					parent[pi] = pi
			if ps.size() == 2:
				var ra: int = _root(parent, ps[0])
				var rb: int = _root(parent, ps[1])
				parent[ra] = rb
	var groups := {}
	for pi in touched:
		groups[_root(parent, pi)] = true
	var before: int = net.stats()["patches"]
	var keep := {}   # untouched patch centre -> verts
	for pi in ok_patches(net):
		if not touched.has(pi):
			keep[patch_centre(net.patches[pi])] = net.patches[pi]["verts"]
	var stamp_del := net.solve_calls
	net.delete_stroke(north)
	var after: int = net.stats()["patches"]
	var ident := true
	for c in keep:
		var pi := patch_near(net, c)
		ident = ident and pi >= 0 and net.patches[pi]["verts"] == keep[c]
	var fresh := 0
	var fresh_ok := true
	for pi in net.patches.size():
		if net.patches[pi]["valid"] and int(net.patches[pi].get("solved_at", 0)) > stamp_del:
			fresh += 1
			fresh_ok = fresh_ok and net.patches[pi]["ok"]
	for p in net.patches:
		if p["valid"] and not p["ok"]:
			say("   after the delete, not filled: %s (%s, sides %s)" % [p["reason"], p["kind"], str(net.side_counts(p))])
	ok(after == before - touched.size() + groups.size() and touched.size() > 0 and ident and fresh == groups.size() and fresh_ok,
		"5 DELETE: the north ring touched %d patches, merged into %d: %d -> %d patches (expected %d); the %d untouched bit-identical %s; new patches solved %d (all filled %s)" % [touched.size(), groups.size(), before, after, before - touched.size() + groups.size(), keep.size(), str(ident), fresh, str(fresh_ok)])
	var pa := arc_near(net, pinned_mid)
	var still := true
	for kc in keep_counts:
		var a2 := arc_near(net, kc[0])
		still = still and a2 >= 0 and net.arcs[a2]["count"] == kc[1]
	ok(others_still and pa >= 0 and net.arcs[pa]["count"] == pinned_count and net.arcs[pa]["pinned"] and still,
		"5 PINNED: after the count change the other arcs kept their counts %s; after the delete the hand-set arc still has %d (pinned %s) and the %d arcs round the south cap kept their auto counts %s" % [str(others_still), net.arcs[pa]["count"] if pa >= 0 else -1, str(net.arcs[pa]["pinned"]) if pa >= 0 else "-", keep_counts.size(), str(still)])


static func _root(parent: Dictionary, x: int) -> int:
	while parent[x] != x:
		x = parent[x]
	return x


# ====================================================================================== UI (bar 8) + LOOK
func key(code: int, ctrl := false) -> InputEventKey:
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = code
	k.physical_keycode = code
	k.ctrl_pressed = ctrl
	return k


func mbtn(p: Vector2, b := MOUSE_BUTTON_LEFT, pressed := true) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = b
	e.pressed = pressed
	e.position = p
	return e


func motion(p: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = p
	return e


func draw_stroke(ui, a: Vector2, b: Vector2) -> void:
	ui.input(motion(a))
	ui.input(mbtn(a))
	for i in 40:
		ui.input(motion(a.lerp(b, float(i + 1) / 40.0)))
	ui.input(mbtn(b, MOUSE_BUTTON_LEFT, false))


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func shot() -> Image:
	await idle(4)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img != null:
		img.convert(Image.FORMAT_RGBA8)
	return img


func open_mesh(mn: Node, k: KMesh) -> void:
	if mn.kmed != null and mn.kmed.on:
		mn.kmed.stop()
	mn._kmesh_edit_start()
	await idle(2)
	var ui = mn.kmed
	ui.stop()
	ui.source = func() -> Dictionary: return {"mesh": k}
	ui.start()
	await idle(3)


func look_at_mesh(mn: Node, yaw: float, pitch: float, zoom := 1.0) -> void:
	var ui = mn.kmed
	var c := Vector3.ZERO
	var pts := []
	for v in ui.mesh.verts:
		pts.append(ui.view.global_transform * v)
		c += pts[pts.size() - 1]
	c /= float(pts.size())
	var r := 0.0
	for p in pts:
		r = maxf(r, (p - c).length())
	mn._turn_to(yaw, pitch, r * 3.0 * zoom, c, false)
	await idle(3)


func bar_ui() -> void:
	var mn: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(mn)
	await idle(3)
	# registry + the pole of the keys
	var line := {}
	var q_users := []
	for t in MeshTools.TOOLS:
		if t.get("id", "") == "mesh_retopo":
			line = t
		if str(t.get("keys", "")) == "Q" and str(t.get("page", "")) == "MODEL":
			q_users.append(t.get("id", ""))
	var src := KMeshPrims.uv_sphere(0.3, 48, 24)
	await open_mesh(mn, src)
	var ui = mn.kmed
	var said_on := MeshToolOps.op("retopo", mn)
	var t := KMeshRetopoUI.of(ui)
	var on1: bool = t != null and t.on
	var said_off := MeshToolOps.op("retopo", mn)
	var off1: bool = t != null and not t.on
	ok(line.get("do", "") == "op:retopo" and line.get("keys", "") == "Q" and q_users == ["mesh_retopo"] and on1 and off1,
		"8 REGISTRY: mesh_retopo do %s keys %s; Q is the key of %s only on MODEL; the op opens (%s) and closes (%s): \"%s\"" % [line.get("do", "-"), line.get("keys", "-"), str(q_users), str(on1), str(off1), said_on.left(70)])
	ui.input(key(KEY_Q))
	t = KMeshRetopoUI.of(ui)
	ok(t != null and t.on and t.net != null, "8 Q: Retopo mode on in the model preview (%s)" % (mn.ui_status.text.left(80) if mn.get("ui_status") != null else ""))
	if t == null or not t.on:
		return
	await idle(2)
	var cam: Camera3D = ui.m.cam
	var cw: Vector3 = ui.view.global_transform * Vector3.ZERO
	var c := cam.unproject_position(cw)
	var rpx := (cam.unproject_position(cw + cam.global_transform.basis.x * 0.3) - c).length()
	var px := func(x: float, y: float) -> Vector2: return c + Vector2(x, y) * rpx
	draw_stroke(ui, px.call(-0.75, -0.3), px.call(0.75, -0.3))
	draw_stroke(ui, px.call(-0.75, 0.3), px.call(0.75, 0.3))
	draw_stroke(ui, px.call(-0.3, -0.75), px.call(-0.3, 0.75))
	draw_stroke(ui, px.call(0.3, -0.75), px.call(0.3, 0.75))
	var net: KMeshRetopoNet = t.net
	var on_surf := 0.0 if net.nat != null else INF
	var npts := 0
	for id in (net.strokes if net.nat != null else {}):
		var flat := PackedFloat64Array()
		for p in net.strokes[id]:
			flat.append(p.x)
			flat.append(p.y)
			flat.append(p.z)
			npts += 1
		for dd in (net.nat.project(flat)["dist"] as PackedFloat64Array):
			on_surf = maxf(on_surf, dd)
	var st := net.stats()
	say("UI network: %s" % str(st))
	ok(net.strokes.size() == 4 and npts > 40 and on_surf < 1e-5 and st["patches"] >= 1, "8 STROKES: 4 drawn with the mouse, %d points, all on the surface (max %s off), %d patch(es) filled" % [npts, String.num_scientific(on_surf), st["patches"]])
	# wheel over the top side of the middle patch
	var sp: Vector2 = px.call(0.0, -0.3)
	ui.input(motion(sp))
	var ha: int = t.hover_arc
	var n0: int = net.arcs[ha]["count"] if ha >= 0 else -1
	ui.input(mbtn(sp, MOUSE_BUTTON_WHEEL_UP))
	var n1: int = net.arcs[ha]["count"] if ha >= 0 else -1
	ok(ha >= 0 and n1 == n0 + 1, "8 WHEEL: over a side (arc %d) its count %d -> %d" % [ha, n0, n1])
	# a fifth stroke in a corner, hovered, Delete
	draw_stroke(ui, px.call(0.5, -0.62), px.call(0.62, -0.5))
	var ns5: int = net.strokes.size()
	ui.input(motion(px.call(0.56, -0.56)))
	var hs: int = t.hover_stroke
	ui.input(key(KEY_DELETE))
	ok(ns5 == 5 and hs >= 0 and net.strokes.size() == 4 and not net.strokes.has(hs), "8 DELETE: the hovered stroke %d removed (strokes %d -> %d)" % [hs, ns5, net.strokes.size()])
	# bake: one undo step, all quads; Ctrl+Z gives the source back
	var v0: PackedVector3Array = ui.mesh.verts.duplicate()
	var f0: Array = ui.mesh.faces.duplicate()
	var steps0: int = ui.undo.steps.size()
	var expect_q := 0
	for pi in ok_patches(net):
		expect_q += (net.patches[pi]["quads"] as PackedInt32Array).size() / 4
	ui.input(key(KEY_ENTER))
	await idle(2)
	var allq: bool = ui.mesh.faces.size() > 0
	for f in ui.mesh.faces:
		allq = allq and (f as PackedInt32Array).size() == 4
	var steps1: int = ui.undo.steps.size()
	ok(allq and ui.mesh.faces.size() == expect_q and steps1 == steps0 + 1 and not t.on, "8 BAKE: Enter: the mesh is %d quads (all quads %s, expected %d), undo steps %d -> %d, Retopo closed" % [ui.mesh.faces.size(), str(allq), expect_q, steps0, steps1])
	ui.input(key(KEY_Z, true))
	await idle(1)
	var back: bool = ui.mesh.verts == v0 and KMeshUndo._same_faces(ui.mesh.faces, f0)
	ok(back, "8 UNDO: Ctrl+Z gives the source back exactly (%d verts, %d faces)" % [ui.mesh.verts.size(), ui.mesh.faces.size()])
	await look(mn)


func look(mn: Node) -> void:
	if DisplayServer.get_name() == "headless" or man == null:
		print("SKIP LOOK: no window")
		return
	var head: KMesh = KMesh.new().from_arrays(man.verts, man.faces)
	await open_mesh(mn, head)
	var ui = mn.kmed
	var rows := []
	for view in [[25.0, -8.0], [-140.0, -12.0]]:
		await look_at_mesh(mn, view[0], view[1], 0.7)
		rows.append([await shot()])
	ui.input(key(KEY_Q))
	var t := KMeshRetopoUI.of(ui)
	if t == null or not t.on:
		ok(false, "LOOK: Retopo did not open on the mannequin")
		return
	t.net.edge_len = 0.03
	put_strokes(t.net, man_strokes)
	t._refresh()
	for i in 2:
		var view: Array = [[25.0, -8.0], [-140.0, -12.0]][i]
		await look_at_mesh(mn, view[0], view[1], 0.7)
		rows[i].append(await shot())
	t.bake()
	await idle(3)
	for i in 2:
		var view: Array = [[25.0, -8.0], [-140.0, -12.0]][i]
		await look_at_mesh(mn, view[0], view[1], 0.7)
		rows[i].append(await shot())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	var names := ["mannequin_front.png", "mannequin_back.png"]
	for i in 2:
		var imgs: Array = rows[i]
		if imgs.size() != 3 or imgs[0] == null:
			continue
		var w: int = imgs[0].get_width()
		var h: int = imgs[0].get_height()
		var cx := int(w * 0.2)
		var cwid := int(w * 0.6)
		var out := Image.create(cwid * 3, h, false, Image.FORMAT_RGBA8)
		for j in 3:
			out.blit_rect(imgs[j], Rect2i(cx, 0, cwid, h), Vector2i(j * cwid, 0))
		out.resize(out.get_width() / 2, out.get_height() / 2, Image.INTERPOLATE_LANCZOS)
		out.save_png(SHOT_DIR + names[i])
		say("LOOK: %s%s (source | strokes + patches | baked quads with the heat map)" % [SHOT_DIR, names[i]])
	print("LOOK written")
