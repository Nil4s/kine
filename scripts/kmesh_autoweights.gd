class_name KMeshAutoWeights
extends RefCounted
## H01 (docs/ROADMAP_400.md): AUTO WEIGHTS by bone heat diffusion, our own implementation of Baran & Popovic 2007
## ("Automatic rigging and animation of 3D characters"). For every bone i the weights w_i solve
##     (-Lap + H) w_i = H p_i
## on the surface, where Lap is the cotangent Laplacian, H_jj = c / d(j)^2 with d(j) the distance from vertex j to its
## nearest VISIBLE bone (the segment from the vertex to the bone's closest point crosses no triangle of the vertex's own
## part; c = HEAT_C = 1), and p_i(j) = 1 when bone i is that nearest visible bone (shared 1/k between k bones at the same
## distance, the outside of a joint). A vertex that sees no bone gets H = 0: its weights come from its neighbours only.
## Multiplied through by the vertex areas A (the area-normalised Laplacian times A) the matrix is SYMMETRIC POSITIVE
## DEFINITE:   (L + A H) w_i = A H p_i,   L_jk = -(cot a + cot b) / 2,  L_jj = -sum_k L_jk
## and the same for every bone, so each bone is one Jacobi-preconditioned conjugate gradient solve. Because L 1 = 0 the
## weights of all bones add to 1 by themselves. A bone's solve starts on the vertices whose own bone is within HOPS steps
## of it in the skeleton and grows along the mesh's edges while its weight at the region's border is over LEAK_OK (parts
## the skeleton keeps apart can touch: the mannequin's fingertips), so the cut costs under 1% of weight.
## The mannequin (6994 welded verts, 52 bones) takes ~9 s; the test holds it under 30.
## FALLBACK (the "distance method"): a vertex on a non-manifold edge (3 or more faces), a vertex on no face, and every
## vertex of a part where no vertex sees a bone get w_i ~ 1 / d_i^4 instead; inside a heat part those values are fixed
## boundary values of the solve, so the two methods meet without a seam.
## AFTER: at most MAX_INFL bones per vertex (the largest), normalised, weights under PRUNE dropped, normalised again.
## Bones: [{"name", "id" (the skeleton bone index, what is stored), "a" (origin), "ends" (PackedVector3Array: the
## segment ends, its children's origins; a bone without one gets a stub along its parent's direction), "parent" (index
## in this list, -1)}], all in the mesh's space (bones_from_skeleton / chain build them).
## Stored on a KMesh as two A09 vertex channels: "skin_bones" (Color: four bone ids, -1 = none) and "skin_weights"
## (Color: their weights). bind() writes them; the preview's command does it as ONE KMeshUndo step.

const HEAT_C := 1.0
const MAX_INFL := 4
const PRUNE := 0.01
const HOPS := 2          # a bone's solve covers the vertices whose own bone is this close in the skeleton
const LEAK_OK := 0.01    # a bone's region grows while its weight at the region's border is over this
const GROW_ROUNDS := 6   # at most this many growths (2, 4, 8 ... rings of edges each)
const CG_TOL := 1e-6     # relative residual
const CG_MAX := 3000
const TIE := 1e-4        # bones within 0.01% of the nearest distance share p
const VIS_TRY := 8       # nearest bones tried for visibility before giving up (H = 0)
const D_MIN := 1e-4      # m: distances are floored here (a vertex on a bone)
const CH_BONES := "skin_bones"
const CH_WEIGHTS := "skin_weights"
const STUB_MIN := 0.05   # m: the least length of a childless bone's stub


## the deforming bones of a skeleton, in its rest space (or the bind space of `skin` when given: where its mesh lives).
## Skipped: names in `skip_names`, and any name containing "leaf" (end markers) or equal to "root" unless keep_all.
static func bones_from_skeleton(sk: Skeleton3D, skin: Skin = null, keep_all := false) -> Array:
	var pos := PackedVector3Array()
	pos.resize(sk.get_bone_count())
	for b in sk.get_bone_count():
		pos[b] = sk.get_bone_global_rest(b).origin
	if skin != null:
		for k in skin.get_bind_count():
			var bi := skin.get_bind_bone(k)
			if bi < 0:
				bi = sk.find_bone(skin.get_bind_name(k))
			if bi >= 0:
				pos[bi] = (skin.get_bind_pose(k) as Transform3D).affine_inverse().origin
	var keep := PackedByteArray()
	keep.resize(sk.get_bone_count())
	for b in sk.get_bone_count():
		var nm := sk.get_bone_name(b).to_lower()
		keep[b] = 1 if keep_all or not (nm == "root" or nm.contains("leaf")) else 0
	var out := []
	var at := {}
	for b in sk.get_bone_count():
		if keep[b] == 0:
			continue
		var ends := PackedVector3Array()
		for c in sk.get_bone_children(b):
			if pos[c].distance_to(pos[b]) > 1e-6:
				ends.append(pos[c])
		var par := sk.get_bone_parent(b)
		while par >= 0 and keep[par] == 0:
			par = sk.get_bone_parent(par)
		if ends.is_empty():
			var gp := sk.get_bone_parent(b)
			var dir := (pos[b] - pos[gp]) if gp >= 0 else Vector3.UP
			var l := maxf(dir.length(), STUB_MIN)
			ends.append(pos[b] + (dir.normalized() if dir.length() > 1e-9 else Vector3.UP) * l)
		at[b] = out.size()
		out.append({"name": sk.get_bone_name(b), "id": b, "a": pos[b], "ends": ends, "par_bone": par, "parent": -1})
	for e in out:
		e["parent"] = int(at.get(e["par_bone"], -1))
	return out


## a chain of bones through the points (bone k from pts[k] to pts[k + 1]); ids 0.., names "bone0"..
static func chain(pts: PackedVector3Array) -> Array:
	var out := []
	for k in pts.size() - 1:
		out.append({"name": "bone%d" % k, "id": k, "a": pts[k], "ends": PackedVector3Array([pts[k + 1]]), "parent": k - 1})
	return out


## distance from p to the segment a-b
static func _seg_d(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0) if l2 > 1e-14 else 0.0
	return p.distance_to(a + ab * t)


static func _seg_q(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0) if l2 > 1e-14 else 0.0
	return a + ab * t


## the weights of `mesh` for `bones`. opts: "xf" (Transform3D: mesh space -> bone space), "c" (heat constant),
## "hops", "visibility" (false = every nearest bone counts as visible). Returns {"ids": PackedInt32Array (V * 4, bone
## ids, -1 = none), "w": PackedFloat32Array (V * 4), "ms", "ms_parts" {...}, "heat", "fallback", "unseen",
## "nonmanifold", "cg_iters", "cg_worst", "leak", "solves", "error"}
static func compute(mesh: KMesh, bones: Array, opts := {}) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var parts := {}
	var nb := bones.size()
	var xf: Transform3D = opts.get("xf", Transform3D.IDENTITY)
	var c: float = opts.get("c", HEAT_C)
	var hops: int = opts.get("hops", HOPS)
	var vis_on: bool = opts.get("visibility", true)
	var nv := mesh.verts.size()
	var res := {"ids": PackedInt32Array(), "w": PackedFloat32Array(), "error": ""}
	if nb == 0 or nv == 0:
		res["error"] = "no bones" if nb == 0 else "no vertices"
		return res
	var P := PackedVector3Array()
	P.resize(nv)
	for i in nv:
		P[i] = xf * mesh.verts[i]
	# ---- triangles (fan), components, non-manifold edges
	var tri := PackedInt32Array()
	for f in mesh.faces:
		var fa: PackedInt32Array = f
		for k in range(1, fa.size() - 1):
			tri.append(fa[0])
			tri.append(fa[k])
			tri.append(fa[k + 1])
	var nt := tri.size() / 3
	var uf := PackedInt32Array()
	uf.resize(nv)
	for i in nv:
		uf[i] = i
	for t in nt:
		for k in range(1, 3):
			var ra := _find(uf, tri[t * 3])
			var rb := _find(uf, tri[t * 3 + k])
			if ra != rb:
				uf[rb] = ra
	var comp := PackedInt32Array()
	comp.resize(nv)
	for i in nv:
		comp[i] = _find(uf, i)
	var on_face := PackedByteArray()
	on_face.resize(nv)
	for x in tri:
		on_face[x] = 1
	var fixed := PackedByteArray()   # 1 = distance method
	fixed.resize(nv)
	var ecount := {}
	for f in mesh.faces:
		var fa: PackedInt32Array = f
		for k in fa.size():
			var a := fa[k]
			var b := fa[(k + 1) % fa.size()]
			var key := mini(a, b) * nv + maxi(a, b)
			ecount[key] = int(ecount.get(key, 0)) + 1
	var nonman := 0
	for key in ecount:
		if int(ecount[key]) > 2:
			var a: int = int(key) / nv
			var b: int = int(key) % nv
			if fixed[a] == 0:
				nonman += 1
			if fixed[b] == 0:
				nonman += 1
			fixed[a] = 1
			fixed[b] = 1
	for i in nv:
		if on_face[i] == 0:
			fixed[i] = 1
	# ---- bone segments (flat), distances, nearest bones
	var sa := PackedVector3Array()
	var sb := PackedVector3Array()
	var sbone := PackedInt32Array()
	for k in nb:
		var bo: Dictionary = bones[k]
		for e in (bo["ends"] as PackedVector3Array):
			sa.append(bo["a"])
			sb.append(e)
			sbone.append(k)
		if (bo["ends"] as PackedVector3Array).is_empty():
			sa.append(bo["a"])
			sb.append(bo["a"])
			sbone.append(k)
	var ns := sa.size()
	var D := PackedFloat32Array()   # V * nb distances
	D.resize(nv * nb)
	D.fill(INF)
	for i in nv:
		var p := P[i]
		var o := i * nb
		for s in ns:
			var d := _seg_d(p, sa[s], sb[s])
			if d < D[o + sbone[s]]:
				D[o + sbone[s]] = d
	parts["dist"] = (Time.get_ticks_usec() - t0) / 1000.0
	# ---- visibility: the nearest bones in order, the first whose closest point the vertex can see
	var t1 := Time.get_ticks_usec()
	var grid := _grid(P, tri, comp) if vis_on else {}
	var hv := PackedFloat32Array()   # A H (filled below), first H
	hv.resize(nv)
	var own := PackedInt32Array()    # the vertex's own bone (nearest visible, else nearest)
	own.resize(nv)
	var near := PackedInt32Array()   # the nearest bone, seen or not
	near.resize(nv)
	var tie_b := PackedInt32Array()  # up to 4 bones sharing p (-1 = none)
	tie_b.resize(nv * 4)
	tie_b.fill(-1)
	var unseen := 0
	var order := PackedInt32Array()
	order.resize(nb)
	var stamp := PackedInt32Array()
	stamp.resize(nt)
	stamp.fill(-1)
	var qid := 0
	for i in nv:
		var o := i * nb
		var best := -1
		var bd := INF
		for k in nb:
			if D[o + k] < bd:
				bd = D[o + k]
				best = k
		own[i] = best
		near[i] = best
		if fixed[i] == 1:
			continue
		# candidates in distance order (a short selection: VIS_TRY of them)
		var tried := 0
		var used := PackedByteArray()
		used.resize(nb)
		var seen_k := -1
		while tried < mini(VIS_TRY, nb):
			var ck := -1
			var cd := INF
			for k in nb:
				if used[k] == 0 and D[o + k] < cd:
					cd = D[o + k]
					ck = k
			used[ck] = 1
			tried += 1
			if not vis_on or _visible(i, P, _closest_on_bone(P[i], ck, sa, sb, sbone), grid, tri, comp, stamp, qid):
				seen_k = ck
				qid += 1
				break
			qid += 1
		if seen_k < 0:
			unseen += 1
			continue
		own[i] = seen_k
		var d0 := maxf(D[o + seen_k], D_MIN)
		hv[i] = c / (d0 * d0)
		var nt_ := 0
		for k in nb:
			if nt_ < 4 and (k == seen_k or absf(D[o + k] - D[o + seen_k]) <= TIE * maxf(D[o + seen_k], D_MIN)):
				tie_b[i * 4 + nt_] = k
				nt_ += 1
	parts["visibility"] = (Time.get_ticks_usec() - t1) / 1000.0
	# a part where no vertex sees a bone: all of it by distance
	var comp_heat := {}
	for i in nv:
		if fixed[i] == 0 and hv[i] > 0.0:
			comp_heat[comp[i]] = true
	for i in nv:
		if not comp_heat.has(comp[i]):
			fixed[i] = 1
	# ---- distance weights of the fixed vertices (dense rows, only for them)
	var W := PackedFloat32Array()   # V * nb result before the limit
	W.resize(nv * nb)
	var nfix := 0
	for i in nv:
		if fixed[i] == 1:
			nfix += 1
			_distance_row(W, D, i, nb)
	# ---- cotangent Laplacian (CSR, symmetric) and vertex areas
	var t2 := Time.get_ticks_usec()
	var area := PackedFloat64Array()
	area.resize(nv)
	var wmap := {}   # key a * nv + b (a < b) -> cot weight
	for t in nt:
		var ia := tri[t * 3]
		var ib := tri[t * 3 + 1]
		var ic := tri[t * 3 + 2]
		var a := P[ia]
		var b := P[ib]
		var cc := P[ic]
		var cr := (b - a).cross(cc - a).length()
		if cr < 1e-14:
			continue
		area[ia] += cr / 6.0
		area[ib] += cr / 6.0
		area[ic] += cr / 6.0
		# the cot of the angle at each corner weighs the edge opposite it
		var cot_a := (b - a).dot(cc - a) / cr
		var cot_b := (a - b).dot(cc - b) / cr
		var cot_c := (a - cc).dot(b - cc) / cr
		_addw(wmap, ib, ic, cot_a * 0.5, nv)
		_addw(wmap, ia, ic, cot_b * 0.5, nv)
		_addw(wmap, ia, ib, cot_c * 0.5, nv)
	var deg := PackedInt32Array()
	deg.resize(nv + 1)
	for key in wmap:
		deg[int(key) / nv] += 1
		deg[int(key) % nv] += 1
	var rp := PackedInt32Array()
	rp.resize(nv + 1)
	for i in nv:
		rp[i + 1] = rp[i] + deg[i]
	var col := PackedInt32Array()
	col.resize(rp[nv])
	var val := PackedFloat64Array()
	val.resize(rp[nv])
	var fill := rp.duplicate()
	var Ld := PackedFloat64Array()
	Ld.resize(nv)
	for key in wmap:
		var a: int = int(key) / nv
		var b: int = int(key) % nv
		var w: float = wmap[key]
		col[fill[a]] = b
		val[fill[a]] = w
		fill[a] += 1
		col[fill[b]] = a
		val[fill[b]] = w
		fill[b] += 1
		Ld[a] += w
		Ld[b] += w
	var AH := PackedFloat64Array()
	AH.resize(nv)
	for i in nv:
		AH[i] = area[i] * hv[i]
	parts["laplacian"] = (Time.get_ticks_usec() - t2) / 1000.0
	# ---- per bone: the region, the solve
	var t3 := Time.get_ticks_usec()
	var nbr := []   # bone graph
	for k in nb:
		nbr.append(PackedInt32Array())
	for k in nb:
		var pk: int = bones[k].get("parent", -1)
		if pk >= 0:
			var mine: PackedInt32Array = nbr[k]
			mine.append(pk)
			nbr[k] = mine   # written back: an append on the element changes a copy
			var lst: PackedInt32Array = nbr[pk]
			lst.append(k)
			nbr[pk] = lst
	var verts_of := []
	for k in nb:
		verts_of.append(PackedInt32Array())
	for i in nv:
		if fixed[i] == 0:
			var lst: PackedInt32Array = verts_of[own[i]]
			lst.append(i)
			verts_of[own[i]] = lst
	var loc := PackedInt32Array()
	loc.resize(nv)
	loc.fill(-1)
	var iters_total := 0
	var iters_worst := 0
	var leak := 0.0
	var leak_bone := ""
	var leak_vert := -1
	var solves := 0
	var regrown := 0
	for k in nb:
		# bones within `hops` steps
		var hood := {k: 0}
		var front := [k]
		for h in hops:
			var nxt := []
			for q in front:
				for r in (nbr[q] as PackedInt32Array):
					if not hood.has(r):
						hood[r] = h + 1
						nxt.append(r)
			front = nxt
		var reg := PackedInt32Array()
		for q in hood:
			reg.append_array(verts_of[q])
		if reg.is_empty():
			continue
		for li in reg.size():
			loc[reg[li]] = li
		# solve; while the weight at the region's border is over LEAK_OK, grow the region (by mesh edges: two parts the
		# skeleton keeps apart can touch, joined fingertips) and solve again from the last answer
		var x := PackedFloat64Array()
		var grow := 2
		for rnd in GROW_ROUNDS + 1:
			var n := reg.size()
			var x0 := x
			x = PackedFloat64Array()
			x.resize(n)
			# local system: M = diag(Ld + AH) - W; rhs = AH p_k + fixed neighbours' values
			var lrp := PackedInt32Array()
			lrp.resize(n + 1)
			var lcol := PackedInt32Array()
			var lval := PackedFloat64Array()
			var dg := PackedFloat64Array()
			dg.resize(n)
			var rhs := PackedFloat64Array()
			rhs.resize(n)
			var border := PackedByteArray()
			border.resize(n)
			for li in n:
				var i := reg[li]
				dg[li] = Ld[i] + AH[i]
				var pk := 0.0
				var tc := 0
				var hit := false
				for q in 4:
					var tb := tie_b[i * 4 + q]
					if tb >= 0:
						tc += 1
						if tb == k:
							hit = true
				if hit:
					pk = 1.0 / tc
				rhs[li] = AH[i] * pk
				if li < x0.size():
					x[li] = x0[li]
				elif rnd == 0:
					x[li] = pk if hv[i] > 0.0 else (1.0 if own[i] == k else 0.0)
				for e in range(rp[i], rp[i + 1]):
					var j := col[e]
					var lj := loc[j]
					if lj >= 0:
						lcol.append(lj)
						lval.append(-val[e])
					elif fixed[j] == 1:
						rhs[li] += val[e] * W[j * nb + k]
					else:
						border[li] = 1
				lrp[li + 1] = lcol.size()
			var it := _cg(n, lrp, lcol, lval, dg, rhs, x)
			solves += 1
			iters_total += it
			iters_worst = maxi(iters_worst, it)
			var bmax := 0.0
			var bv := -1
			for li in n:
				if border[li] == 1 and x[li] > bmax:
					bmax = x[li]
					bv = reg[li]
			if bmax <= LEAK_OK or rnd == GROW_ROUNDS:
				if bmax > leak:
					leak = bmax
					leak_bone = bones[k]["name"]
					leak_vert = bv
				break
			# grow: `grow` rings of free vertices past the border, appended (the old ones keep their local index)
			var ring := PackedInt32Array()
			for li in n:
				if border[li] == 1:
					ring.append(reg[li])
			for g in grow:
				var nxt := PackedInt32Array()
				for i in ring:
					for e in range(rp[i], rp[i + 1]):
						var j := col[e]
						if loc[j] < 0 and fixed[j] == 0:
							loc[j] = reg.size()
							reg.append(j)
							nxt.append(j)
				ring = nxt
			grow *= 2
			regrown += 1
		for li in reg.size():
			var i := reg[li]
			W[i * nb + k] = maxf(float(x[li]), 0.0)
			loc[i] = -1
	parts["solve"] = (Time.get_ticks_usec() - t3) / 1000.0
	# ---- limit, normalise, prune
	var ids := PackedInt32Array()
	ids.resize(nv * MAX_INFL)
	ids.fill(-1)
	var ww := PackedFloat32Array()
	ww.resize(nv * MAX_INFL)
	for i in nv:
		var top := _top(W, i, nb)
		for q in top.size():
			ids[i * MAX_INFL + q] = int(bones[top[q][0]]["id"])
			ww[i * MAX_INFL + q] = top[q][1]
	res["ids"] = ids
	res["w"] = ww
	res["own"] = own
	res["near"] = near
	res["heat"] = nv - nfix
	res["fallback"] = nfix
	res["unseen"] = unseen
	res["nonmanifold"] = nonman
	res["solves"] = solves
	res["regrown"] = regrown
	res["cg_iters"] = iters_total
	res["cg_worst"] = iters_worst
	res["leak"] = leak
	res["leak_bone"] = leak_bone
	res["leak_vert"] = leak_vert
	res["parts"] = comp_heat.size()
	res["ms_parts"] = parts
	res["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	return res


static func _find(uf: PackedInt32Array, i: int) -> int:
	var r := i
	while uf[r] != r:
		r = uf[r]
	while uf[i] != r:
		var nx := uf[i]
		uf[i] = r
		i = nx
	return r


static func _addw(m: Dictionary, a: int, b: int, w: float, nv: int) -> void:
	var key := mini(a, b) * nv + maxi(a, b)
	m[key] = float(m.get(key, 0.0)) + w


## w ~ 1 / d^4 over every bone, into the dense row of vertex i
static func _distance_row(W: PackedFloat32Array, D: PackedFloat32Array, i: int, nb: int) -> void:
	var tot := 0.0
	for k in nb:
		var d := maxf(D[i * nb + k], D_MIN)
		var x := 1.0 / (d * d * d * d)
		W[i * nb + k] = x
		tot += x
	for k in nb:
		W[i * nb + k] = W[i * nb + k] / tot


## the MAX_INFL largest of vertex i's row, normalised, the ones under PRUNE dropped, normalised again: [[bone, w], ...].
## A tie across the cut (the 4th and the 5th equal within 0.1%: a vertex on the mirror plane between a left and a right
## bone) drops both, so the cut never picks a side.
static func _top(W: PackedFloat32Array, i: int, nb: int) -> Array:
	var top := []
	for k in nb:
		var x := W[i * nb + k]
		if x <= 0.0:
			continue
		if top.size() < MAX_INFL + 1:
			top.append([k, x])
			top.sort_custom(func(a, b): return a[1] > b[1])
		elif x > top[MAX_INFL][1]:
			top[MAX_INFL] = [k, x]
			top.sort_custom(func(a, b): return a[1] > b[1])
	if top.size() > MAX_INFL:
		var cut: float = top[MAX_INFL][1]
		top.resize(MAX_INFL)
		while top.size() > 1 and absf(top[top.size() - 1][1] - cut) <= 1e-3 * cut:
			top.pop_back()
	var tot := 0.0
	for e in top:
		tot += e[1]
	if tot <= 0.0:
		return top
	var kept := []
	for e in top:
		if e[1] / tot >= PRUNE:
			kept.append(e)
	if kept.is_empty():
		kept.append(top[0])
	tot = 0.0
	for e in kept:
		tot += e[1]
	for e in kept:
		e[1] = e[1] / tot
	return kept


## Jacobi-preconditioned conjugate gradient on the local SPD system (diagonal dg, off-diagonal CSR); x holds the start
## and gets the answer. Returns the iterations.
static func _cg(n: int, rp: PackedInt32Array, ci: PackedInt32Array, cv: PackedFloat64Array, dg: PackedFloat64Array,
		b: PackedFloat64Array, x: PackedFloat64Array) -> int:
	var r := PackedFloat64Array()
	r.resize(n)
	var z := PackedFloat64Array()
	z.resize(n)
	var p := PackedFloat64Array()
	p.resize(n)
	var q := PackedFloat64Array()
	q.resize(n)
	var bn := 0.0
	for i in n:
		var s := dg[i] * x[i]
		for e in range(rp[i], rp[i + 1]):
			s += cv[e] * x[ci[e]]
		r[i] = b[i] - s
		bn += b[i] * b[i]
	if bn <= 0.0:
		bn = 1.0
	var tol2 := CG_TOL * CG_TOL * bn
	var rz := 0.0
	var rr := 0.0
	for i in n:
		z[i] = r[i] / dg[i]
		p[i] = z[i]
		rz += r[i] * z[i]
		rr += r[i] * r[i]
	var it := 0
	while it < CG_MAX and rr > tol2:
		var pq := 0.0
		for i in n:
			var s := dg[i] * p[i]
			for e in range(rp[i], rp[i + 1]):
				s += cv[e] * p[ci[e]]
			q[i] = s
			pq += p[i] * s
		if pq <= 0.0:
			break
		var al := rz / pq
		var rz2 := 0.0
		rr = 0.0
		for i in n:
			x[i] += al * p[i]
			r[i] -= al * q[i]
			z[i] = r[i] / dg[i]
			rz2 += r[i] * z[i]
			rr += r[i] * r[i]
		var be := rz2 / rz
		rz = rz2
		for i in n:
			p[i] = z[i] + be * p[i]
		it += 1
	return it


# ---------------------------------------------------------------- visibility

static func _closest_on_bone(p: Vector3, k: int, sa: PackedVector3Array, sb: PackedVector3Array, sbone: PackedInt32Array) -> Vector3:
	var best := INF
	var out := p
	for s in sa.size():
		if sbone[s] != k:
			continue
		var q := _seg_q(p, sa[s], sb[s])
		var d := p.distance_squared_to(q)
		if d < best:
			best = d
			out = q
	return out


## a uniform grid of the triangles: {"o", "h", "cells": {Vector3i: PackedInt32Array}}
static func _grid(P: PackedVector3Array, tri: PackedInt32Array, _comp: PackedInt32Array) -> Dictionary:
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for p in P:
		lo = lo.min(p)
		hi = hi.max(p)
	var nt := tri.size() / 3
	var el := 0.0
	for t in nt:
		el += P[tri[t * 3]].distance_to(P[tri[t * 3 + 1]])
	el /= maxf(nt, 1)
	var h := maxf(maxf(el * 2.0, (hi - lo).length() / 200.0), 1e-4)
	var cells := {}
	for t in nt:
		var a := P[tri[t * 3]]
		var b := P[tri[t * 3 + 1]]
		var c := P[tri[t * 3 + 2]]
		var mn := ((a.min(b).min(c) - lo) / h).floor()
		var mx := ((a.max(b).max(c) - lo) / h).floor()
		for x in range(int(mn.x), int(mx.x) + 1):
			for y in range(int(mn.y), int(mx.y) + 1):
				for z in range(int(mn.z), int(mx.z) + 1):
					var key := Vector3i(x, y, z)
					if not cells.has(key):
						cells[key] = PackedInt32Array()
					var lst: PackedInt32Array = cells[key]
					lst.append(t)
					cells[key] = lst
	return {"o": lo, "h": h, "cells": cells}


## can vertex i see point q: the segment crosses no triangle of its own part (its own triangles excepted)
static func _visible(i: int, P: PackedVector3Array, q: Vector3, g: Dictionary, tri: PackedInt32Array, comp: PackedInt32Array,
		stamp: PackedInt32Array, qid: int) -> bool:
	var a := P[i]
	if a.distance_to(q) < 1e-6:
		return true
	var h: float = g["h"]
	var o: Vector3 = g["o"]
	var cells: Dictionary = g["cells"]
	var ci := comp[i]
	var p0 := (a - o) / h
	var p1 := (q - o) / h
	var cell := Vector3i(p0.floor())
	var last := Vector3i(p1.floor())
	var d := p1 - p0
	var stp := Vector3i(signi(int(signf(d.x))), signi(int(signf(d.y))), signi(int(signf(d.z))))
	var tmax := Vector3(INF, INF, INF)
	var tdel := Vector3(INF, INF, INF)
	for ax in 3:
		if absf(d[ax]) > 1e-12:
			var nxt := float(cell[ax] + (1 if stp[ax] > 0 else 0))
			tmax[ax] = (nxt - p0[ax]) / d[ax]
			tdel[ax] = absf(1.0 / d[ax])
	var guard := 0
	while guard < 4096:
		guard += 1
		if cells.has(cell):
			for t in (cells[cell] as PackedInt32Array):
				if stamp[t] == qid:
					continue
				stamp[t] = qid
				var ta := tri[t * 3]
				var tb := tri[t * 3 + 1]
				var tc := tri[t * 3 + 2]
				if ta == i or tb == i or tc == i or comp[ta] != ci:
					continue
				var hit = Geometry3D.segment_intersects_triangle(a, q, P[ta], P[tb], P[tc])
				if hit != null and (hit as Vector3).distance_to(a) > 1e-6:
					return false
		if cell == last:
			break
		var ax := 0
		if tmax.y < tmax[ax]:
			ax = 1
		if tmax.z < tmax[ax]:
			ax = 2
		if tmax[ax] > 1.0:
			break
		cell[ax] += stp[ax]
		tmax[ax] += tdel[ax]
	return true


# ---------------------------------------------------------------- on a KMesh

## compute and store on the mesh as the two vertex channels (added when missing). Returns compute()'s result.
static func bind(mesh: KMesh, bones: Array, opts := {}) -> Dictionary:
	var r := compute(mesh, bones, opts)
	if r["error"] != "":
		return r
	var nv := mesh.verts.size()
	var cb := PackedColorArray()
	cb.resize(nv)
	var cw := PackedColorArray()
	cw.resize(nv)
	var ids: PackedInt32Array = r["ids"]
	var w: PackedFloat32Array = r["w"]
	for i in nv:
		cb[i] = Color(ids[i * 4], ids[i * 4 + 1], ids[i * 4 + 2], ids[i * 4 + 3])
		cw[i] = Color(w[i * 4], w[i * 4 + 1], w[i * 4 + 2], w[i * 4 + 3])
	for ch in [[CH_BONES, cb, Color(-1, -1, -1, -1)], [CH_WEIGHTS, cw, Color(0, 0, 0, 0)]]:
		if not mesh.has_attr(ch[0]):
			mesh.add_attr(ch[0], KMesh.AD_VERT, TYPE_COLOR, ch[2])
		mesh.set_attr_data(ch[0], ch[1])
	return r


## the stored weights back: {"ids": PackedInt32Array V*4, "w": PackedFloat32Array V*4}, {} when the mesh has none
static func read(mesh: KMesh) -> Dictionary:
	if not (mesh.has_attr(CH_BONES) and mesh.has_attr(CH_WEIGHTS)):
		return {}
	var cb: PackedColorArray = mesh.attr_data(CH_BONES)
	var cw: PackedColorArray = mesh.attr_data(CH_WEIGHTS)
	var ids := PackedInt32Array()
	var w := PackedFloat32Array()
	for i in cb.size():
		for q in 4:
			ids.append(roundi(cb[i][q]))
			w.append(cw[i][q])
	return {"ids": ids, "w": w}


## linear blend skinning: mats[id] = the bone's transform from rest to pose (bone space); a missing id stays at rest
static func deform(verts: PackedVector3Array, ids: PackedInt32Array, w: PackedFloat32Array, mats: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(verts.size())
	for i in verts.size():
		var p := Vector3.ZERO
		for q in MAX_INFL:
			var x := w[i * MAX_INFL + q]
			if x > 0.0:
				var m: Transform3D = mats.get(ids[i * MAX_INFL + q], Transform3D.IDENTITY)
				p += (m * verts[i]) * x
		out[i] = p
	return out


## "Model: bind to the skeleton (auto weights)": the model preview's mesh (opened first when it is not) gets heat weights
## for the fighter's skeleton, as ONE undo step of the preview (Ctrl+Z there takes the two channels back).
static func preview_bind(m) -> void:
	if m.skel == null:
		m._say("Model: no skeleton to bind to: pick the mannequin first")
		return
	if m.kmed == null or not m.kmed.on:
		m._kmesh_edit_start()
	var ed = m.kmed
	var sk: Skeleton3D = m.skel
	var bones := bones_from_skeleton(sk)
	var xf: Transform3D = sk.global_transform.affine_inverse() * ed.view.global_transform if ed.view.is_inside_tree() and sk.is_inside_tree() else Transform3D(Basis(), ed.view.position)
	ed.undo.begin(ed.mesh)
	var r := bind(ed.mesh, bones, {"xf": xf})
	if r["error"] != "":
		ed.undo.commit("cancelled")
		m._say("Model: auto weights could not run: %s" % r["error"])
		return
	ed.undo.commit("Auto weights")
	m._say("Model: bound to the skeleton by bone heat (%d bones, %d verts by heat, %d by distance) in %.1f s. Ctrl+Z takes it back" % [bones.size(), r["heat"], r["fallback"], r["ms"] / 1000.0])
