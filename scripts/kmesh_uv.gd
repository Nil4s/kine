class_name KMeshUV
extends RefCounted
## KMeshUV: unwrap and UV checks for a KMesh (ROADMAP_400 D03 + D05). Pure GDScript, static funcs.
## UVs live in the corner attribute "uv" (Vector2, one per face corner = half-edge, A09); KMesh.to_array_mesh already
## draws it as TEX_UV. Seams live in the edge attribute "seam" (float, > 0.5 = cut), in edges() order.
##
## UNWRAP, angle-based: LSCM (Levy, Petitjean, Ray, Maillot 2002, "Least Squares Conformal Maps for Automatic Texture
##   Atlas Generation", SIGGRAPH). Each triangle T (n-gons fan-split) gets an orthonormal frame, its corners z_j in it and
##   W_1 = z_3 - z_2, W_2 = z_1 - z_3, W_3 = z_2 - z_1; the conformal energy is sum_T |sum_j W_j U_j|^2 / (2 area_T) over
##   the complex unknowns U_j = u_j + i v_j (it is 0 for any similarity of the triangle, so 0 = no angle distortion).
##   Two pinned verts (the island's two farthest apart) remove the similarity freedom. The normal equations H U = b
##   (H = M^H M, Hermitian positive definite, one complex row per corner wedge) are solved by conjugate gradient with a
##   symmetric Gauss-Seidel preconditioner (a third of the iterations of Jacobi on a 5k-quad sheet), complex arithmetic,
##   the diagonal + strictly lower part stored as sparse rows (CSR), started from a planar projection.
##   Seams: an edge cuts when it is marked in "seam" or is a boundary; corners around a vertex that are not separated by
##   a cut share one UV (a "wedge"); faces joined by uncut edges form an island. Islands are scaled to their 3D area and
##   set side by side in rows (a plain shelf, D04 does real packing), the whole layout fitted into 0..1.
## CONFORMAL: the same LSCM, every island; "conformal" and "angle" name the same solve (no ABF++ yet).
## PROJECTION: cube (each face by its dominant normal axis), cylinder and sphere (around the bbox centre, axis y by
##   default); a face that straddles the wrap seam is moved one turn so it never spans the whole texture.
## STRETCH (D05): per triangle the Jacobian of surface -> UV, its singular values s1 >= s2, scaled by
##   sqrt(area_3d / area_uv) over the whole mesh (so a map that is one uniform scale reads 1):
##   angle = s1 / s2 (1 = conformal), area = s1 s2 (1 = area kept), sd = sqrt((s1^2 + s2^2 + s1^-2 + s2^-2) / 4)
##   (the symmetric Dirichlet energy, Smith & Schaefer 2015, 1 = isometric), and the mesh L2 stretch of Sander, Snyder,
##   Gortler, Hoppe 2001 ("Texture Mapping Progressive Meshes", SIGGRAPH), normalised so 1 = ideal. heat = how far sd is
##   from 1 (0 at sd 1, 1 at sd >= SD_RED), shown blue -> green -> yellow -> red; a flipped triangle is red.

const UV := "uv"
const SEAM := "seam"
const SD_RED := 1.5        # symmetric Dirichlet at which the heat map is fully red (an angle distortion of 4 is 1.46)
const CG_TOL := 1e-9       # CG stops when the residual is this fraction of the first
const CG_MAX := 4000
static var cg_tol := CG_TOL
static var sgs := true     # symmetric Gauss-Seidel preconditioner (false: Jacobi)
const PACK_GAP := 0.02     # space between islands, as a fraction of the layout side
const HEAT := [Color(0.15, 0.35, 0.95), Color(0.15, 0.8, 0.35), Color(0.95, 0.85, 0.15), Color(0.95, 0.15, 0.1)]


# ---------------------------------------------------------------- seams, wedges, islands

## mark the edges in `list` (Vector2i a-b, any order) as seams (adds the "seam" attribute when missing); returns how many
static func mark_seams(m: KMesh, list: Array, on := true) -> int:
	_ensure_seam(m)
	var want := {}
	for e in list:
		want[Vector2i(mini(e.x, e.y), maxi(e.x, e.y))] = true
	var d: PackedFloat32Array = m.attr_data(SEAM)
	var n := 0
	var i := 0
	for e in m.edges():
		if want.has(e):
			d[i] = 1.0 if on else 0.0
			n += 1
		i += 1
	m.set_attr_data(SEAM, d)
	return n


## seam on every edge whose two faces meet at more than `angle` degrees (a cube's 12 edges at 60); returns how many
static func seams_by_angle(m: KMesh, angle := 60.0) -> int:
	_ensure_seam(m)
	var d: PackedFloat32Array = m.attr_data(SEAM)
	var c := cos(deg_to_rad(angle))
	var n := 0
	var i := 0
	var fn := m.face_normals
	for e in m.edges():
		var h := m.find_half_edge(e.x, e.y)
		var g := m.find_half_edge(e.y, e.x)
		if h != -1 and g != -1 and fn[m.he_face[h]].dot(fn[m.he_face[g]]) < c:
			d[i] = 1.0
			n += 1
		i += 1
	m.set_attr_data(SEAM, d)
	return n


static func _ensure_seam(m: KMesh) -> void:
	if not m.has_attr(SEAM):
		m.add_attr(SEAM, KMesh.AD_EDGE, TYPE_FLOAT, 0.0)


## one byte per half-edge: 1 when it cuts (boundary, seam, or a non-manifold / repeated edge)
static func _cuts(m: KMesh, seam := SEAM) -> PackedByteArray:
	var nh := m.half_edge_count()
	var cut := PackedByteArray()
	cut.resize(nh)
	var marked := {}
	if m.has_attr(seam):
		var sd = m.attr_data(seam)
		var i := 0
		for e in m.edges():
			if float(sd[i]) > 0.5:
				marked[e] = true
			i += 1
	var hv := m.he_vert
	var hn := m.he_next
	var ht := m.he_twin
	for h in nh:
		var a := hv[h]
		var b := hv[hn[h]]
		if ht[h] == -1 or a == b or (not marked.is_empty() and marked.has(Vector2i(mini(a, b), maxi(a, b)))):
			cut[h] = 1
	for h in nh:   # a twin pair cuts on both sides
		if ht[h] != -1 and cut[ht[h]] == 1:
			cut[h] = 1
	return cut


static func _find(p: PackedInt32Array, i: int) -> int:
	while p[i] != i:
		p[i] = p[p[i]]
		i = p[i]
	return i


## {"wedge": per corner its wedge id (0..n-1), "wedges": n, "island": per face its island id, "islands": count}
static func topology(m: KMesh, seam := SEAM) -> Dictionary:
	var cut := _cuts(m, seam)
	var nh := cut.size()
	var hn := m.he_next
	var ht := m.he_twin
	var hf := m.he_face
	var pc := PackedInt32Array()
	pc.resize(nh)
	for h in nh:
		pc[h] = h
	var nf := m.face_count()
	var pf := PackedInt32Array()
	pf.resize(nf)
	for f in nf:
		pf[f] = f
	for h in nh:
		var t := ht[h]
		if t == -1 or cut[h] == 1 or t < h:
			continue
		# h: a->b in face F, t: b->a in face G. Corner a of F is h, of G is next(t); corner b of F is next(h), of G is t.
		var x := _find(pc, h)
		var y := _find(pc, hn[t])
		if x != y:
			pc[x] = y
		x = _find(pc, hn[h])
		y = _find(pc, t)
		if x != y:
			pc[x] = y
		x = _find(pf, hf[h])
		y = _find(pf, hf[t])
		if x != y:
			pf[x] = y
	var wedge := PackedInt32Array()
	wedge.resize(nh)
	var ids := {}
	for h in nh:
		var r := _find(pc, h)
		if not ids.has(r):
			ids[r] = ids.size()
		wedge[h] = ids[r]
	var isl := PackedInt32Array()
	isl.resize(nf)
	var fids := {}
	for f in nf:
		var r := _find(pf, f)
		if not fids.has(r):
			fids[r] = fids.size()
		isl[f] = fids[r]
	return {"wedge": wedge, "wedges": ids.size(), "island": isl, "islands": fids.size()}


# ---------------------------------------------------------------- LSCM

## Unwrap every island by LSCM and write the corner attribute `uv`. Returns {"islands", "iters" (CG, all islands),
## "ms", "wedges"}. "conformal" is the same call (unwrap(m, "conformal")).
static func unwrap_lscm(m: KMesh, seam := SEAM, uv := UV) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var top := topology(m, seam)
	var wedge: PackedInt32Array = top["wedge"]
	var nw: int = top["wedges"]
	var nisl: int = top["islands"]
	var isl: PackedInt32Array = top["island"]
	var wpos := PackedVector3Array()
	wpos.resize(nw)
	var hv := m.he_vert
	for h in wedge.size():
		wpos[wedge[h]] = m.verts[hv[h]]
	var by_isl: Array = []
	for i in nisl:
		by_isl.append(PackedInt32Array())
	for f in m.face_count():
		by_isl[isl[f]].append(f)
	var wu := PackedFloat64Array()
	var wv := PackedFloat64Array()
	wu.resize(nw)
	wv.resize(nw)
	var iters := 0
	var boxes: Array = []
	for i in nisl:
		var r := _lscm_island(m, by_isl[i], wedge, wpos, wu, wv)
		iters += int(r["iters"])
		boxes.append(r["box"])
	_pack(boxes, by_isl, m, wedge, wu, wv)
	if not m.has_attr(uv):
		m.add_attr(uv, KMesh.AD_CORNER, TYPE_VECTOR2)
	var out := PackedVector2Array()
	out.resize(wedge.size())
	for h in wedge.size():
		out[h] = Vector2(wu[wedge[h]], wv[wedge[h]])
	m.set_attr_data(uv, out)
	return {"islands": nisl, "iters": iters, "wedges": nw, "ms": (Time.get_ticks_usec() - t0) / 1000.0}


## fan triangles of the faces as corner (half-edge) triples
static func _fan(m: KMesh, faces: PackedInt32Array) -> PackedInt32Array:
	var tri := PackedInt32Array()
	var he0 := m.face_he0
	for f in faces:
		var h0 := he0[f]
		var n := (m.faces[f] as PackedInt32Array).size()
		for i in range(1, n - 1):
			tri.append(h0)
			tri.append(h0 + i)
			tri.append(h0 + i + 1)
	return tri


## solve one island; fills wu/wv for its wedges (scaled to the 3D area, bbox at the origin). {"iters", "box": Vector2 size}
static func _lscm_island(m: KMesh, faces: PackedInt32Array, wedge: PackedInt32Array, wpos: PackedVector3Array, wu: PackedFloat64Array, wv: PackedFloat64Array) -> Dictionary:
	var tri := _fan(m, faces)
	# local numbering of the island's wedges
	var loc := {}
	var glob := PackedInt32Array()
	for c in tri:
		var w := wedge[c]
		if not loc.has(w):
			loc[w] = glob.size()
			glob.append(w)
	var n := glob.size()
	if n < 3:
		for k in n:
			wu[glob[k]] = 0.0
			wv[glob[k]] = 0.0
		return {"iters": 0, "box": Vector2.ZERO}
	# H = M^H M, accumulated per (row, col) pair
	var key_ix := {}
	var er := PackedInt32Array()
	var ec := PackedInt32Array()
	var ere := PackedFloat64Array()
	var eim := PackedFloat64Array()
	var area3 := 0.0
	var nrm := Vector3.ZERO
	var ma := PackedFloat64Array([0.0, 0.0, 0.0])
	var mb := PackedFloat64Array([0.0, 0.0, 0.0])
	var lj := PackedInt32Array([0, 0, 0])
	for t in range(0, tri.size(), 3):
		var p0 := wpos[wedge[tri[t]]]
		var p1 := wpos[wedge[tri[t + 1]]]
		var p2 := wpos[wedge[tri[t + 2]]]
		var e1 := p1 - p0
		var e2 := p2 - p0
		var cr := e1.cross(e2)
		var dt := cr.length()   # twice the area
		if dt < 1e-14:
			continue
		area3 += dt * 0.5
		nrm += cr
		var ax := e1.normalized()
		var ay := (cr / dt).cross(ax)
		var x1 := e1.length()
		var x2 := e2.dot(ax)
		var y2 := e2.dot(ay)
		var s := 1.0 / sqrt(dt)
		# z0 = 0, z1 = (x1, 0), z2 = (x2, y2):  W0 = z2 - z1, W1 = z0 - z2, W2 = z1 - z0
		ma[0] = (x2 - x1) * s
		mb[0] = y2 * s
		ma[1] = -x2 * s
		mb[1] = -y2 * s
		ma[2] = x1 * s
		mb[2] = 0.0
		for j in 3:
			lj[j] = loc[wedge[tri[t + j]]]
		for j in 3:
			for k in 3:
				var key: int = lj[j] * n + lj[k]
				var ix: int = key_ix.get(key, -1)
				if ix == -1:
					ix = er.size()
					key_ix[key] = ix
					er.append(lj[j])
					ec.append(lj[k])
					ere.append(0.0)
					eim.append(0.0)
				# conj(M_j) M_k
				ere[ix] += ma[j] * ma[k] + mb[j] * mb[k]
				eim[ix] += ma[j] * mb[k] - mb[j] * ma[k]
	# H is Hermitian: keep the diagonal (real) and the strictly lower part, row by row (CSR); H_kj = conj(H_jk)
	var rs := PackedInt32Array()
	rs.resize(n + 1)
	var diag := PackedFloat64Array()
	diag.resize(n)
	var nz := er.size()
	for e in nz:
		if ec[e] < er[e]:
			rs[er[e] + 1] += 1
		elif ec[e] == er[e]:
			diag[er[e]] = ere[e]
	for r in n:
		rs[r + 1] += rs[r]
	var fill := rs.duplicate()
	var cc := PackedInt32Array()
	var hr := PackedFloat64Array()
	var hi := PackedFloat64Array()
	cc.resize(rs[n])
	hr.resize(rs[n])
	hi.resize(rs[n])
	for e in nz:
		var r := er[e]
		if ec[e] >= r:
			continue
		var q := fill[r]
		fill[r] += 1
		cc[q] = ec[e]
		hr[q] = ere[e]
		hi[q] = eim[e]
	# pins: the two wedges farthest apart (two sweeps)
	var pa := 0
	var pb := 0
	var bd := -1.0
	for k in n:
		var d := wpos[glob[k]].distance_squared_to(wpos[glob[0]])
		if d > bd:
			bd = d
			pa = k
	bd = -1.0
	for k in n:
		var d := wpos[glob[k]].distance_squared_to(wpos[glob[pa]])
		if d > bd:
			bd = d
			pb = k
	var L := sqrt(bd)
	# start: projection on the island's mean plane, moved by a similarity onto the pins
	var xr := PackedFloat64Array()
	var xi := PackedFloat64Array()
	xr.resize(n)
	xi.resize(n)
	var nn := nrm.normalized() if nrm.length() > 1e-12 else Vector3.UP
	var bx := (Vector3.UP if absf(nn.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).cross(nn).normalized()
	var by := nn.cross(bx)
	for k in n:
		var p := wpos[glob[k]]
		xr[k] = p.dot(bx)
		xi[k] = p.dot(by)
	var dzr := xr[pb] - xr[pa]
	var dzi := xi[pb] - xi[pa]
	var dz2 := dzr * dzr + dzi * dzi
	if dz2 > 1e-20:
		# a = L / dz (complex), z' = a (z - z_a)
		var sr := L * dzr / dz2
		var si := -L * dzi / dz2
		var ar := xr[pa]
		var ai := xi[pa]
		for k in n:
			var zr := xr[k] - ar
			var zi := xi[k] - ai
			xr[k] = sr * zr - si * zi
			xi[k] = sr * zi + si * zr
	else:
		xr.fill(0.0)
		xi.fill(0.0)
	xr[pa] = 0.0
	xi[pa] = 0.0
	xr[pb] = L
	xi[pb] = 0.0
	var iters := _pcg(n, rs, cc, hr, hi, diag, xr, xi, pa, pb)
	# area to 3D, orientation, bbox at the origin
	var auv := 0.0
	for t in range(0, tri.size(), 3):
		var a: int = loc[wedge[tri[t]]]
		var b: int = loc[wedge[tri[t + 1]]]
		var c: int = loc[wedge[tri[t + 2]]]
		auv += 0.5 * ((xr[b] - xr[a]) * (xi[c] - xi[a]) - (xr[c] - xr[a]) * (xi[b] - xi[a]))
	var flip := auv < 0.0
	var sc := sqrt(area3 / absf(auv)) if absf(auv) > 1e-20 else 1.0
	var lo := Vector2(INF, INF)
	var hi2 := Vector2(-INF, -INF)
	for k in n:
		var u := xr[k] * sc * (-1.0 if flip else 1.0)
		var v := xi[k] * sc
		xr[k] = u
		xi[k] = v
		lo = Vector2(minf(lo.x, u), minf(lo.y, v))
		hi2 = Vector2(maxf(hi2.x, u), maxf(hi2.y, v))
	for k in n:
		wu[glob[k]] = xr[k] - lo.x
		wv[glob[k]] = xi[k] - lo.y
	return {"iters": iters, "box": hi2 - lo}


## Jacobi-preconditioned CG on H x = 0 with x[pa], x[pb] held (complex: real and imaginary parts in xr / xi)
static func _pcg(n: int, rs: PackedInt32Array, cc: PackedInt32Array, hr: PackedFloat64Array, hi: PackedFloat64Array, diag: PackedFloat64Array,
		xr: PackedFloat64Array, xi: PackedFloat64Array, pa: int, pb: int) -> int:
	var rr := PackedFloat64Array()
	var ri := PackedFloat64Array()
	var pr := PackedFloat64Array()
	var pi := PackedFloat64Array()
	var qr := PackedFloat64Array()
	var qi := PackedFloat64Array()
	var dinv := PackedFloat64Array()
	rr.resize(n)
	ri.resize(n)
	pr.resize(n)
	pi.resize(n)
	qr.resize(n)
	qi.resize(n)
	dinv.resize(n)
	for k in n:
		dinv[k] = 1.0 / diag[k] if diag[k] > 1e-30 and k != pa and k != pb else 0.0
	_matvec(n, rs, cc, hr, hi, diag, xr, xi, qr, qi)
	var rz := 0.0
	var r0 := 0.0
	var zr := PackedFloat64Array()
	var zi := PackedFloat64Array()
	zr.resize(n)
	zi.resize(n)
	for k in n:
		rr[k] = -qr[k] * (1.0 if dinv[k] > 0.0 else 0.0)
		ri[k] = -qi[k] * (1.0 if dinv[k] > 0.0 else 0.0)
		r0 += rr[k] * rr[k] + ri[k] * ri[k]
	_precond(n, rs, cc, hr, hi, dinv, rr, ri, zr, zi)
	for k in n:
		pr[k] = zr[k]
		pi[k] = zi[k]
		rz += rr[k] * zr[k] + ri[k] * zi[k]
	if r0 < 1e-30:
		return 0
	var tol2 := r0 * cg_tol * cg_tol
	var it := 0
	while it < CG_MAX:
		it += 1
		_matvec(n, rs, cc, hr, hi, diag, pr, pi, qr, qi)
		var pq := 0.0
		for k in n:
			if dinv[k] > 0.0:
				pq += pr[k] * qr[k] + pi[k] * qi[k]
		if pq <= 0.0:
			break
		var al := rz / pq
		var rn := 0.0
		for k in n:
			if dinv[k] == 0.0:
				continue
			xr[k] += al * pr[k]
			xi[k] += al * pi[k]
			rr[k] -= al * qr[k]
			ri[k] -= al * qi[k]
			rn += rr[k] * rr[k] + ri[k] * ri[k]
		if rn < tol2:
			break
		_precond(n, rs, cc, hr, hi, dinv, rr, ri, zr, zi)
		var rz2 := 0.0
		for k in n:
			rz2 += rr[k] * zr[k] + ri[k] * zi[k]
		var be := rz2 / rz
		rz = rz2
		for k in n:
			pr[k] = zr[k] + be * pr[k]
			pi[k] = zi[k] + be * pi[k]
	return it


## z = M^-1 r. Jacobi: M = D. Symmetric Gauss-Seidel: M = (D + L) D^-1 (D + L)^H (L the strictly lower part of H): a
## forward sweep by rows of L, then a backward one by its columns; held (pinned) rows and columns count as zero
static func _precond(n: int, rs: PackedInt32Array, cc: PackedInt32Array, hr: PackedFloat64Array, hi: PackedFloat64Array, dinv: PackedFloat64Array,
		rr: PackedFloat64Array, ri: PackedFloat64Array, zr: PackedFloat64Array, zi: PackedFloat64Array) -> void:
	if not sgs:
		for k in n:
			zr[k] = rr[k] * dinv[k]
			zi[k] = ri[k] * dinv[k]
		return
	for j in n:
		var sr := rr[j]
		var si := ri[j]
		for e in range(rs[j], rs[j + 1]):
			var k := cc[e]
			var a := hr[e]
			var b := hi[e]
			sr -= a * zr[k] - b * zi[k]
			si -= a * zi[k] + b * zr[k]
		zr[j] = sr * dinv[j]
		zi[j] = si * dinv[j]
	for j in range(n - 1, -1, -1):
		var xr := zr[j]
		var xi := zi[j]
		if xr == 0.0 and xi == 0.0:
			continue
		for e in range(rs[j], rs[j + 1]):
			var k := cc[e]
			var a := hr[e] * dinv[k]
			var b := hi[e] * dinv[k]
			zr[k] -= a * xr + b * xi
			zi[k] -= a * xi - b * xr


## y = H x from the diagonal and the lower part
static func _matvec(n: int, rs: PackedInt32Array, cc: PackedInt32Array, hr: PackedFloat64Array, hi: PackedFloat64Array, diag: PackedFloat64Array,
		xr: PackedFloat64Array, xi: PackedFloat64Array, yr: PackedFloat64Array, yi: PackedFloat64Array) -> void:
	for j in n:
		yr[j] = diag[j] * xr[j]
		yi[j] = diag[j] * xi[j]
	for j in n:
		var sr := 0.0
		var si := 0.0
		var pr := xr[j]
		var pi := xi[j]
		for e in range(rs[j], rs[j + 1]):
			var k := cc[e]
			var a := hr[e]
			var b := hi[e]
			sr += a * xr[k] - b * xi[k]
			si += a * xi[k] + b * xr[k]
			yr[k] += a * pr + b * pi
			yi[k] += a * pi - b * pr
		yr[j] += sr
		yi[j] += si


## islands in rows (tallest first), the whole fitted into 0..1 keeping one scale for all
static func _pack(boxes: Array, by_isl: Array, m: KMesh, wedge: PackedInt32Array, wu: PackedFloat64Array, wv: PackedFloat64Array) -> void:
	var order := range(boxes.size())
	order.sort_custom(func(a, b): return (boxes[a] as Vector2).y > (boxes[b] as Vector2).y)
	var tot := 0.0
	var big := 0.0
	for b in boxes:
		tot += (b as Vector2).x * (b as Vector2).y
		big = maxf(big, maxf((b as Vector2).x, (b as Vector2).y))
	var row_w := maxf(sqrt(tot) * 1.15, big)
	var gap := row_w * PACK_GAP
	var off := {}
	var x := 0.0
	var y := 0.0
	var rh := 0.0
	var W := 0.0
	for i in order:
		var b: Vector2 = boxes[i]
		if x > 0.0 and x + b.x > row_w:
			x = 0.0
			y += rh + gap
			rh = 0.0
		off[i] = Vector2(x, y)
		x += b.x + gap
		rh = maxf(rh, b.y)
		W = maxf(W, x - gap)
	var side := maxf(W, y + rh)
	var s := 1.0 / side if side > 1e-12 else 1.0
	var he0 := m.face_he0
	var done := {}
	for i in boxes.size():
		var o: Vector2 = off[i]
		for f in (by_isl[i] as PackedInt32Array):
			for c in (m.faces[f] as PackedInt32Array).size():
				var w := wedge[he0[f] + c]
				if done.has(w):
					continue
				done[w] = true
				wu[w] = (wu[w] + o.x) * s
				wv[w] = (wv[w] + o.y) * s


## unwrap by name: "angle" / "lscm" / "conformal" (LSCM), "cube", "cylinder", "sphere". Returns the call's dictionary.
static func unwrap(m: KMesh, method := "angle", uv := UV) -> Dictionary:
	match method:
		"cube":
			return project_cube(m, uv)
		"cylinder":
			return project_cylinder(m, 1, uv)
		"sphere":
			return project_sphere(m, 1, uv)
	return unwrap_lscm(m, SEAM, uv)


# ---------------------------------------------------------------- projections

static func _bbox(m: KMesh) -> AABB:
	if m.vert_count() == 0:
		return AABB()
	var bb := AABB(m.verts[0], Vector3.ZERO)
	for p in m.verts:
		bb = bb.expand(p)
	return bb


static func _write(m: KMesh, uv: String, out: PackedVector2Array) -> void:
	if not m.has_attr(uv):
		m.add_attr(uv, KMesh.AD_CORNER, TYPE_VECTOR2)
	m.set_attr_data(uv, out)


## Cube (box) projection: each face by its normal's dominant axis, coordinates over the bbox's largest side S (0..1), read
## as if you face that side from outside, up = +y (for +y / -y: up = -z / +z):
##   +x: ((max.z - z) / S, (y - min.y) / S)   -x: ((z - min.z) / S, ...)   +z: ((x - min.x) / S, ...)   -z: ((max.x - x) / S, ...)
##   +y: ((x - min.x) / S, (max.z - z) / S... flipped so +z is down)   -y: ((x - min.x) / S, (z - min.z) / S)
static func project_cube(m: KMesh, uv := UV) -> Dictionary:
	var bb := _bbox(m)
	var S := maxf(bb.size[bb.get_longest_axis_index()], 1e-12)
	var lo := bb.position
	var hi := bb.end
	var out := PackedVector2Array()
	out.resize(m.half_edge_count())
	var he0 := m.face_he0
	var fn := m.face_normals
	for f in m.face_count():
		var nr := fn[f]
		var ax := 0
		for k in 3:
			if absf(nr[k]) > absf(nr[ax]):
				ax = k
		var pos := nr[ax] > 0.0
		var fp: PackedInt32Array = m.faces[f]
		for i in fp.size():
			var p := m.verts[fp[i]]
			var q := Vector2.ZERO
			match ax:
				0:
					q = Vector2((hi.z - p.z) if pos else (p.z - lo.z), p.y - lo.y)
				2:
					q = Vector2((p.x - lo.x) if pos else (hi.x - p.x), p.y - lo.y)
				_:
					q = Vector2(p.x - lo.x, (p.z - lo.z) if pos else (hi.z - p.z))
			out[he0[f] + i] = q / S
	_write(m, uv, out)
	return {"islands": 6, "iters": 0}


## u = atan2 around `axis` (for y: atan2(x, z) from the bbox centre) / TAU + 0.5; one face never spans the wrap
static func _turn_u(d: Vector3, axis: int) -> float:
	return atan2(d[(axis + 2) % 3], d[(axis + 1) % 3]) / TAU + 0.5


static func _unwrap_faces(m: KMesh, out: PackedVector2Array, pole: Callable) -> void:
	var he0 := m.face_he0
	for f in m.face_count():
		var n := (m.faces[f] as PackedInt32Array).size()
		var h0 := he0[f]
		var umin := INF
		var umax := -INF
		for i in n:
			if not pole.call(m.faces[f][i]):
				umin = minf(umin, out[h0 + i].x)
				umax = maxf(umax, out[h0 + i].x)
		if umax - umin > 0.5:
			for i in n:
				if out[h0 + i].x < 0.5:
					out[h0 + i].x += 1.0
		# a corner on the axis (a pole) takes the mean u of the face's other corners
		var su := 0.0
		var sn := 0
		for i in n:
			if not pole.call(m.faces[f][i]):
				su += out[h0 + i].x
				sn += 1
		if sn > 0 and sn < n:
			for i in n:
				if pole.call(m.faces[f][i]):
					out[h0 + i].x = su / sn


## Cylinder projection around `axis` (0 x, 1 y, 2 z) through the bbox centre: u = turn (0..1, u = 0.5 toward +z for axis y),
## v = height over the bbox (0 at the bottom, 1 at the top)
static func project_cylinder(m: KMesh, axis := 1, uv := UV) -> Dictionary:
	var bb := _bbox(m)
	var c := bb.get_center()
	var hgt := maxf(bb.size[axis], 1e-12)
	var out := PackedVector2Array()
	out.resize(m.half_edge_count())
	var he0 := m.face_he0
	var r_eps := 1e-9 * maxf(bb.size.length(), 1e-12)
	for f in m.face_count():
		var fp: PackedInt32Array = m.faces[f]
		for i in fp.size():
			var p := m.verts[fp[i]]
			out[he0[f] + i] = Vector2(_turn_u(p - c, axis), (p[axis] - bb.position[axis]) / hgt)
	var on_axis := func(v: int) -> bool:
		var d := m.verts[v] - c
		d[axis] = 0.0
		return d.length() < r_eps
	_unwrap_faces(m, out, on_axis)
	_write(m, uv, out)
	return {"islands": 1, "iters": 0}


## Sphere projection around the bbox centre: u = turn as the cylinder, v = 1 - polar angle / PI (1 at the +axis pole)
static func project_sphere(m: KMesh, axis := 1, uv := UV) -> Dictionary:
	var bb := _bbox(m)
	var c := bb.get_center()
	var out := PackedVector2Array()
	out.resize(m.half_edge_count())
	var he0 := m.face_he0
	var r_eps := 1e-9 * maxf(bb.size.length(), 1e-12)
	for f in m.face_count():
		var fp: PackedInt32Array = m.faces[f]
		for i in fp.size():
			var d := m.verts[fp[i]] - c
			var r := d.length()
			var v := 1.0 - acos(clampf(d[axis] / r, -1.0, 1.0)) / PI if r > 1e-12 else 0.5
			out[he0[f] + i] = Vector2(_turn_u(d, axis), v)
	var on_axis := func(v: int) -> bool:
		var d := m.verts[v] - c
		d[axis] = 0.0
		return d.length() < r_eps
	_unwrap_faces(m, out, on_axis)
	_write(m, uv, out)
	return {"islands": 1, "iters": 0}


# ---------------------------------------------------------------- stretch (D05)

## Per face: "angle" (worst s1 / s2 of its triangles), "area" (s1 s2, area-weighted), "sd" (symmetric Dirichlet,
## area-weighted), "heat" (0..1), "flipped" (1 when a triangle is mirrored in UV). Mesh: "l2" (Sander, normalised: 1 =
## ideal), "angle_max", "angle_mean" (area-weighted), "sd_max", "sd_mean", "flipped_faces". {} without a uv attribute.
static func stretch(m: KMesh, uv := UV) -> Dictionary:
	if not m.has_attr(uv):
		return {}
	var r: Dictionary = m.attr_info(uv)
	var d = m.attr_data(uv)
	var dom: String = r["domain"]
	var nf := m.face_count()
	var he0 := m.face_he0
	# pass 1: areas
	var a3 := 0.0
	var auv := 0.0
	var tris: Array = []   # per triangle [face, p0, p1, p2, u0, u1, u2]
	for f in nf:
		var fp: PackedInt32Array = m.faces[f]
		var q: Array = []
		for i in fp.size():
			q.append(d[fp[i] if dom == KMesh.AD_VERT else (f if dom == KMesh.AD_FACE else he0[f] + i)])
		for i in range(1, fp.size() - 1):
			var t := [f, m.verts[fp[0]], m.verts[fp[i]], m.verts[fp[i + 1]], q[0], q[i], q[i + 1]]
			a3 += 0.5 * ((t[2] - t[1]) as Vector3).cross(t[3] - t[1]).length()
			auv += 0.5 * absf(((t[5] - t[4]) as Vector2).cross(t[6] - t[4]))
			tris.append(t)
	var k := sqrt(a3 / auv) if auv > 1e-20 else 1.0
	var f_ang := PackedFloat32Array()
	var f_area := PackedFloat32Array()
	var f_sd := PackedFloat32Array()
	var f_w := PackedFloat32Array()
	var f_flip := PackedByteArray()
	f_ang.resize(nf)
	f_area.resize(nf)
	f_sd.resize(nf)
	f_w.resize(nf)
	f_flip.resize(nf)
	var l2s := 0.0
	var am := 0.0
	var ws := 0.0
	for t in tris:
		var f: int = t[0]
		var e1: Vector3 = t[2] - t[1]
		var e2: Vector3 = t[3] - t[1]
		var cr := e1.cross(e2)
		var A := cr.length() * 0.5
		if A < 1e-14:
			continue
		var ax := e1.normalized()
		var ay := (cr / (2.0 * A)).cross(ax)
		# surface frame: q1 = (x1, 0), q2 = (x2, y2); uv edges d1, d2. J = [d1 d2] [q1 q2]^-1
		var x1 := e1.length()
		var x2 := e2.dot(ax)
		var y2 := e2.dot(ay)
		var d1: Vector2 = ((t[5] as Vector2) - (t[4] as Vector2)) * k
		var d2: Vector2 = ((t[6] as Vector2) - (t[4] as Vector2)) * k
		# inverse of [[x1, x2], [0, y2]] = [[1/x1, -x2/(x1 y2)], [0, 1/y2]]
		var ja := d1.x / x1
		var jc := d1.y / x1
		var jb := (d2.x - d1.x * x2 / x1) / y2
		var jd := (d2.y - d1.y * x2 / x1) / y2
		var F := ja * ja + jb * jb + jc * jc + jd * jd
		var D := ja * jd - jb * jc
		var disc := sqrt(maxf(F * F - 4.0 * D * D, 0.0))
		var s1 := sqrt(maxf((F + disc) * 0.5, 0.0))
		var s2 := sqrt(maxf((F - disc) * 0.5, 0.0))
		var ang := s1 / s2 if s2 > 1e-12 else 1e6
		var sd := sqrt((s1 * s1 + s2 * s2 + (1.0 / (s1 * s1) if s1 > 1e-12 else 1e12) + (1.0 / (s2 * s2) if s2 > 1e-12 else 1e12)) * 0.25)
		if D < 0.0:
			f_flip[f] = 1
		f_ang[f] = maxf(f_ang[f], ang)
		f_area[f] += s1 * s2 * A
		f_sd[f] += sd * A
		f_w[f] += A
		# Sander L2 of texture -> surface: singular values 1/s2, 1/s1
		if s2 > 1e-12:
			l2s += (1.0 / (s1 * s1) + 1.0 / (s2 * s2)) * 0.5 * A
		else:
			l2s += 1e12 * A
		am += ang * A
		ws += A
	var heat := PackedFloat32Array()
	heat.resize(nf)
	var sdmax := 0.0
	var sdm := 0.0
	var amax := 0.0
	var nflip := 0
	for f in nf:
		if f_w[f] > 0.0:
			f_area[f] /= f_w[f]
			f_sd[f] /= f_w[f]
		sdmax = maxf(sdmax, f_sd[f])
		sdm += f_sd[f] * f_w[f]
		amax = maxf(amax, f_ang[f])
		heat[f] = 1.0 if f_flip[f] == 1 else clampf((f_sd[f] - 1.0) / (SD_RED - 1.0), 0.0, 1.0)
		nflip += f_flip[f]
	return {"angle": f_ang, "area": f_area, "sd": f_sd, "heat": heat, "flipped": f_flip,
		"l2": sqrt(l2s / ws) if ws > 0.0 else 0.0, "angle_max": amax, "angle_mean": am / ws if ws > 0.0 else 0.0,
		"sd_max": sdmax, "sd_mean": sdm / ws if ws > 0.0 else 0.0, "flipped_faces": nflip}


## heat 0..1 -> blue, green, yellow, red
static func heat_color(t: float) -> Color:
	var x := clampf(t, 0.0, 1.0) * (HEAT.size() - 1)
	var i := mini(int(x), HEAT.size() - 2)
	return (HEAT[i] as Color).lerp(HEAT[i + 1], x - i)


# ---------------------------------------------------------------- checker (D05)

## size x size px, cells x cells squares: light / dark alternate, each column a hue step (so a flipped or rotated island
## shows), a 1 px dark line on every cell's left and bottom edge
static func checker_image(size := 512, cells := 8) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGB8)
	var cs := float(size) / cells
	for y in size:
		var j := int(y / cs)
		for x in size:
			var i := int(x / cs)
			var light := (i + j) % 2 == 0
			var c := Color.from_hsv(float(i) / cells, 0.35, 0.92 if light else 0.38)
			if x - int(i * cs) == 0 or int((j + 1) * cs) - 1 - y == 0:
				c = c.darkened(0.5)
			img.set_pixel(x, y, c)
	return img


static var _checker_tex: ImageTexture

## lit material with the checker (16 x 16 cells), nearest filter (crisp cells), back faces culled
static func checker_material() -> StandardMaterial3D:
	if _checker_tex == null:
		var img := checker_image(512, 16)
		img.generate_mipmaps()
		_checker_tex = ImageTexture.create_from_image(img)
	var mt := StandardMaterial3D.new()
	mt.albedo_texture = _checker_tex
	mt.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mt.roughness = 0.8
	mt.cull_mode = BaseMaterial3D.CULL_BACK
	return mt


## unlit-ish material that shows the per-vertex colour (the heat map)
static func heat_material() -> StandardMaterial3D:
	var mt := StandardMaterial3D.new()
	mt.vertex_color_use_as_albedo = true
	mt.roughness = 0.9
	mt.cull_mode = BaseMaterial3D.CULL_BACK
	return mt
