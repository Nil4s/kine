## godot --headless --path . -s tests/decimate_test.gd     (ROADMAP_400 F03)
## DECIMATE: quadric collapse + planar (scripts/kmesh_decimate.gd). Bars, written before measuring:
##   0 THE INSTRUMENTS CAN MOVE: distance() between the UV sphere and the same sphere scaled 1.05 x reads 0.05 m
##     (1e-3); flipped() of the sphere with every face reversed against itself counts every face
##   1 SPHERE: a UV sphere (64 segments, 32 rings: 3968 triangles) with a spherical UV map (one seam meridian) collapsed
##     to 25 %: the triangle count within 1 % of 992; the two-sided sampled Hausdorff distance to the original under 2 %
##     of the bbox diagonal; 0 faces flipped against the original surface; KMeshValidate clean (closed, manifold, no
##     doubled / degenerate / flipped / inside out); every output corner's uv is a uv its vertex had in the input (100 %);
##     the seam is still a seam (seam verts > 0, every one an input seam vert); 0 UV-flipped faces and the mean UV
##     stretch (symmetric Dirichlet, KMeshUV.stretch) at most 1.15 x the input's
##   2 LOCK: lock_features keeps the seam's vertex count exactly (and still lands within 1 % of the target)
##   3 FEATURES: a 1 m open grid (20 x 20 quads, 800 triangles), its left half material 0, right half 1 (a face
##     attribute), collapsed to 25 %: within 1 % of 200; the border is the same square (its length 4 m within 1e-4, every
##     border vert on the square), the 4 corners kept; no face straddles the material line x = 0 (each face's verts all
##     on its own side, 1e-6); an edge "crease" set along z = 0 keeps a creased path: every creased edge after lies on z = 0
##     and together they still run the whole 1 m (1e-5; added after the first run as a tighter check, the bar above passed)
##   4 PLANAR: a 1 m cube split 4 x 4 per side (96 quads) -> 6 faces, 8 verts, quads, clean, volume 1 (1e-6); the same
##     cube triangulated (192) -> 6; with a cube UV map -> 6 and every corner's uv is one its vertex had.
##     A UV sphere (32 x 16): below its smallest angle between neighbouring faces' normals (measured on it) every face
##     stays; at 5 deg every face of the band |y| < 0.5 stays (neighbours >= 9.7 deg apart there) and the result is clean
##     (CORRECTED after the first run: this bar first said "at 5 deg keeps every face", on the false premise that all
##     neighbours are 11.25 deg apart; near the poles they are under 5 deg apart, so joining them there is right)
##   5 UNDO: collapse and planar bracketed by KMeshUndo are ONE step each; undo gives back the exact verts and faces,
##     redo the decimated mesh
##   6 TIME: a 20480-triangle ico sphere (subdivided 5 times) with a spherical UV map collapsed to 25 % in under 10 s,
##     within 1 % of 5120, clean
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## uvs each vertex position had: {Vector3: {Vector2: true}}
func uv_sets(k: KMesh) -> Dictionary:
	var out := {}
	for fi in k.face_count():
		var f: PackedInt32Array = k.faces[fi]
		for i in f.size():
			var p: Vector3 = k.verts[f[i]]
			if not out.has(p):
				out[p] = {}
			out[p][k.get_attr("uv", k.face_he0[fi] + i)] = true
	return out


func seam_verts(k: KMesh) -> Dictionary:
	var out := {}
	var s := uv_sets(k)
	for p in s:
		if (s[p] as Dictionary).size() > 1:
			out[p] = true
	return out


## corners whose uv is one their vertex had in `ref`: [good, total]
func uv_kept(k: KMesh, ref: Dictionary) -> Array:
	var good := 0
	var tot := 0
	for fi in k.face_count():
		var f: PackedInt32Array = k.faces[fi]
		for i in f.size():
			tot += 1
			var p: Vector3 = k.verts[f[i]]
			if ref.has(p) and (ref[p] as Dictionary).has(k.get_attr("uv", k.face_he0[fi] + i)):
				good += 1
	return [good, tot]


func border_edges(k: KMesh) -> Array:
	var out := []
	for e in k.edges():
		if k.is_boundary_edge(e.x, e.y):
			out.append(e)
	return out


func sphere_uv(seg: int, rings: int) -> KMesh:
	var s := KMeshPrims.uv_sphere(1.0, seg, rings)
	KMeshUV.project_sphere(s)
	return s


func _init() -> void:
	# ---- bar 0
	var i0 := sphere_uv(64, 32)
	var big := KMeshDecimate.copy(i0)
	for vi in big.verts.size():
		big.verts[vi] *= 1.05
	big.rebuild()
	var dbig: float = KMeshDecimate.distance(i0, big)["max"]
	var rev := KMeshDecimate.copy(i0)
	for fi in rev.faces.size():
		var f: PackedInt32Array = rev.faces[fi]
		f.reverse()
		rev.faces[fi] = f
	rev.rebuild()
	var nfl := KMeshDecimate.flipped(rev, i0)
	ok(absf(dbig - 0.05) < 1e-3 and nfl == rev.face_count(), "bar 0: distance to the 1.05 x sphere %.5f m (0.05), reversed faces counted flipped %d of %d" % [dbig, nfl, rev.face_count()])
	# ---- bar 1
	var s0 := sphere_uv(64, 32)
	var ref := KMeshDecimate.copy(s0)
	var t0 := s0.triangle_count()
	var uv0 := uv_sets(s0)
	var seam0 := seam_verts(s0)
	var st0 := KMeshUV.stretch(s0)
	var s1 := KMeshDecimate.copy(s0)
	var r := KMeshDecimate.collapse(s1, 0.25)
	var tgt := int(round(t0 * 0.25))
	var dg := KMeshDecimate.diag(ref)
	var hd := KMeshDecimate.distance(s1, ref)
	var fl := KMeshDecimate.flipped(s1, ref)
	var rep := KMeshValidate.report(s1)
	ok(t0 == 3968 and absf(s1.face_count() - tgt) <= 0.01 * tgt, "bar 1: %d triangles -> %d (target %d, %.2f %% off), %d collapses in %.0f ms (refused: flip %d, link %d, side %d, lock %d)" % [t0, s1.face_count(), tgt, 100.0 * absf(s1.face_count() - tgt) / tgt, r["collapses"], r["ms"], r["refused_flip"], r["refused_link"], r["refused_side"], r["refused_lock"]])
	ok(hd["max"] < 0.02 * dg, "bar 1: Hausdorff %.4f m = %.3f %% of the diagonal %.3f (bar 2 %%; mean %.5f m)" % [hd["max"], 100.0 * hd["max"] / dg, dg, hd["mean"]])
	ok(fl == 0, "bar 1: %d faces flipped against the original" % fl)
	ok(rep["ok"] and s1.is_manifold() and s1.is_closed(), "bar 1: KMeshValidate clean %s, manifold %s, closed %s %s" % [rep["ok"], s1.is_manifold(), s1.is_closed(), rep["problems"].map(func(p): return p["kind"])])
	var kept := uv_kept(s1, uv0)
	ok(kept[0] == kept[1] and kept[1] == 3 * s1.face_count(), "bar 1: %d of %d corners carry a uv their vertex had" % kept)
	var seam1 := seam_verts(s1)
	var seam_in := seam1.keys().all(func(p): return seam0.has(p))
	ok(seam1.size() > 0 and seam_in, "bar 1: seam verts %d -> %d, all of them input seam verts %s" % [seam0.size(), seam1.size(), seam_in])
	var st1 := KMeshUV.stretch(s1)
	ok(int(st1["flipped_faces"]) == 0 and float(st1["sd_mean"]) <= 1.15 * float(st0["sd_mean"]), "bar 1: UV stretch sd_mean %.4f -> %.4f (x%.3f, bar 1.15), UV-flipped faces %d -> %d" % [st0["sd_mean"], st1["sd_mean"], float(st1["sd_mean"]) / float(st0["sd_mean"]), st0["flipped_faces"], st1["flipped_faces"]])
	# ---- bar 2
	var s2 := KMeshDecimate.copy(s0)
	var r2 := KMeshDecimate.collapse(s2, 0.25, -1, true)
	var seam2 := seam_verts(s2)
	ok(seam2.size() == seam0.size() and absf(s2.face_count() - tgt) <= 0.01 * tgt and KMeshValidate.report(s2)["ok"], "bar 2: lock: seam verts %d -> %d, %d triangles (target %d), refused lock %d" % [seam0.size(), seam2.size(), s2.face_count(), tgt, r2["refused_lock"]])
	# ---- bar 3
	var g := KMeshPrims.plane(1.0, 1.0, 20, 20)
	g.add_attr("mat", KMesh.AD_FACE, TYPE_FLOAT)
	for fi in g.face_count():
		g.set_attr("mat", fi, 0.0 if g.face_center(fi).x < 0.0 else 1.0)
	g.add_attr("crease", KMesh.AD_EDGE, TYPE_FLOAT)
	var ge: Array = g.edges()
	var n_cr := 0
	for ei in ge.size():
		if absf(g.verts[ge[ei].x].z) < 1e-6 and absf(g.verts[ge[ei].y].z) < 1e-6:
			g.set_attr("crease", ei, 1.0)
			n_cr += 1
	var gt0 := g.triangle_count()
	var r3 := KMeshDecimate.collapse(g, 0.25)
	var gt := int(round(gt0 * 0.25))
	var blen := 0.0
	var bon := true
	for e in border_edges(g):
		blen += g.verts[e.x].distance_to(g.verts[e.y])
		for v in [e.x, e.y]:
			var p: Vector3 = g.verts[v]
			bon = bon and (absf(absf(p.x) - 0.5) < 1e-6 or absf(absf(p.z) - 0.5) < 1e-6)
	var corners := 0
	for p in g.verts:
		if absf(absf(p.x) - 0.5) < 1e-6 and absf(absf(p.z) - 0.5) < 1e-6:
			corners += 1
	var straddle := 0
	for fi in g.face_count():
		var mat: float = g.get_attr("mat", fi)
		for v in (g.faces[fi] as PackedInt32Array):
			var x: float = g.verts[v].x
			if (mat == 0.0 and x > 1e-6) or (mat == 1.0 and x < -1e-6):
				straddle += 1
				break
	var cr_bad := 0
	var cr_n := 0
	var cr_len := 0.0
	var ge2: Array = g.edges()
	for ei in ge2.size():
		if float(g.get_attr("crease", ei)) > 0.5:
			cr_n += 1
			cr_len += g.verts[ge2[ei].x].distance_to(g.verts[ge2[ei].y])
			if absf(g.verts[ge2[ei].x].z) > 1e-6 or absf(g.verts[ge2[ei].y].z) > 1e-6:
				cr_bad += 1
	ok(gt0 == 800 and absf(g.face_count() - gt) <= 0.01 * gt, "bar 3: grid %d -> %d triangles (target %d; refused lock %d, side %d)" % [gt0, g.face_count(), gt, r3["refused_lock"], r3["refused_side"]])
	ok(absf(blen - 4.0) < 1e-4 and bon and corners == 4, "bar 3: border length %.6f m, all border verts on the square %s, corners %d" % [blen, bon, corners])
	ok(straddle == 0, "bar 3: %d faces straddle the material line" % straddle)
	ok(cr_n > 0 and cr_bad == 0 and absf(cr_len - 1.0) < 1e-5, "bar 3: crease: %d creased edges before, %d after, %d off the z = 0 line, %.6f m long" % [n_cr, cr_n, cr_bad, cr_len])
	# ---- bar 4
	var c := KMeshPrims.cube(Vector3.ONE, 4)
	var cf0 := c.face_count()
	var rp := KMeshDecimate.planar(c)
	var quads := c.faces.all(func(f): return (f as PackedInt32Array).size() == 4)
	ok(cf0 == 96 and c.face_count() == 6 and c.vert_count() == 8 and quads and KMeshValidate.report(c)["ok"] and absf(KMeshValidate._volume(c) - 1.0) < 1e-6,
		"bar 4: planar cube %d -> %d faces, %d verts, quads %s, clean %s, volume %.7f (%s)" % [cf0, c.face_count(), c.vert_count(), quads, KMeshValidate.report(c)["ok"], KMeshValidate._volume(c), rp])
	var ct := KMeshPrims.cube(Vector3.ONE, 4)
	KMeshTopo.triangulate(ct)
	var ctf := ct.face_count()
	KMeshDecimate.planar(ct)
	ok(ctf == 192 and ct.face_count() == 6, "bar 4: triangulated cube %d -> %d faces" % [ctf, ct.face_count()])
	var cu := KMeshPrims.cube(Vector3.ONE, 4)
	KMeshUV.project_cube(cu)
	var cuv := uv_sets(cu)
	KMeshDecimate.planar(cu)
	var ck := uv_kept(cu, cuv)
	ok(cu.face_count() == 6 and ck[0] == ck[1] and ck[1] == 24, "bar 4: UV-mapped cube -> %d faces, %d of %d corners keep a uv their vertex had" % [cu.face_count(), ck[0], ck[1]])
	var sp := KMeshPrims.uv_sphere(1.0, 32, 16)
	var spf := sp.face_count()
	var amin := 180.0
	for h in sp.he_twin.size():
		var tw: int = sp.he_twin[h]
		if tw >= 0:
			amin = minf(amin, rad_to_deg(sp.face_normals[sp.he_face[h]].angle_to(sp.face_normals[sp.he_face[tw]])))
	var band := {}
	for fi in spf:
		if absf(sp.face_center(fi).y) < 0.5:
			var vs: PackedVector3Array = []
			for v in (sp.faces[fi] as PackedInt32Array):
				vs.append(sp.verts[v])
			band[vs] = true
	var sp_lo := KMeshDecimate.copy(sp)
	KMeshDecimate.planar(sp_lo, amin * 0.9)
	ok(sp_lo.face_count() == spf, "bar 4: UV sphere 32 x 16 at %.2f deg (0.9 x its smallest neighbour angle %.2f) keeps %d of %d faces" % [amin * 0.9, amin, sp_lo.face_count(), spf])
	KMeshDecimate.planar(sp)
	var band_kept := 0
	for fi in sp.face_count():
		var vs: PackedVector3Array = []
		for v in (sp.faces[fi] as PackedInt32Array):
			vs.append(sp.verts[v])
		if band.has(vs):
			band_kept += 1
	ok(band_kept == band.size() and KMeshValidate.report(sp)["ok"], "bar 4: at 5 deg: %d of the %d band faces (|y| < 0.5) kept, %d -> %d faces, clean %s" % [band_kept, band.size(), spf, sp.face_count(), KMeshValidate.report(sp)["ok"]])
	# ---- bar 5
	var u := KMeshUndo.new()
	var s5 := sphere_uv(32, 16)
	var v5 := s5.verts.duplicate()
	var f5 := s5.faces.duplicate()
	u.begin(s5)
	KMeshDecimate.collapse(s5, 0.5)
	u.commit("decimate")
	var nd := s5.face_count()
	var n_steps := u.steps.size()
	u.undo()
	var back: bool = s5.verts == v5 and KMeshUndo._same_faces(s5.faces, f5) and s5.attr_data("uv").size() == s5.domain_count(KMesh.AD_CORNER)
	u.redo()
	ok(n_steps == 1 and back and s5.face_count() == nd, "bar 5: collapse = %d undo step, undo exact %s, redo %d faces" % [n_steps, back, s5.face_count()])
	var u2 := KMeshUndo.new()
	var c5 := KMeshPrims.cube(Vector3.ONE, 4)
	u2.begin(c5)
	KMeshDecimate.planar(c5)
	u2.commit("planar decimate")
	var n2 := u2.steps.size()
	u2.undo()
	var c96 := c5.face_count()
	u2.redo()
	ok(n2 == 1 and c96 == 96 and c5.face_count() == 6, "bar 5: planar = %d undo step, undo %d faces, redo %d" % [n2, c96, c5.face_count()])
	# ---- bar 6
	var ico := KMeshPrims.ico_sphere(1.0, 5)
	KMeshUV.project_sphere(ico)
	var it0 := ico.triangle_count()
	var us := Time.get_ticks_usec()
	var r6 := KMeshDecimate.collapse(ico, 0.25)
	var sec := (Time.get_ticks_usec() - us) / 1e6
	var it := int(round(it0 * 0.25))
	ok(it0 == 20480 and sec < 10.0 and absf(ico.face_count() - it) <= 0.01 * it and KMeshValidate.report(ico)["ok"],
		"bar 6: %d triangles -> %d (target %d) in %.2f s (bar 10 s), clean %s, %d collapses" % [it0, ico.face_count(), it, sec, KMeshValidate.report(ico)["ok"], r6["collapses"]])
	print("DECIMATE ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails else 0)
