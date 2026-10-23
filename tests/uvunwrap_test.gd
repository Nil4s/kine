extends SceneTree
## godot --headless --path . -s tests/uvunwrap_test.gd     (ROADMAP_400 D03 unwrap + D05 checker / stretch, scripts/kmesh_uv.gd)
## Bars, written before measuring:
##   1 FLAT GRID (12 x 9 quads, 2.0 x 1.3 m, uneven cell widths): LSCM gives no distortion: angle (s1 / s2) max < 1.001,
##     symmetric Dirichlet max < 1.001, Sander L2 within 0.001 of 1, every UV inside 0..1, no flipped face
##   2 CUBE (1 m, 4 x 4 quads a side) with seams: (a) the 7 cuts of a cross net -> 1 island, angle max < 1.01 (a cube net
##     is developable); (b) seams by angle (60 deg) -> 12 seam edges of the cube x 4 = 48 marked, 6 islands, angle max
##     < 1.01; both no flipped face; (c) a UV sphere cut along one meridian (not developable): no flipped face, area-weighted
##     mean angle distortion < 1.25 (LSCM keeps angles; the area is what it gives up, printed)
##   3 PROJECTIONS on known points: cube: +x face corner (0.5, 0.5, 0.5) of a 1 m cube -> (0, 1), (0.5, -0.5, -0.5) -> (1, 0),
##     +z face (x, y) -> (x + 0.5, y + 0.5); cylinder (r 0.5, y 0..2, 24 sides): (0, y, 0.5) -> u 0.5, (0.5, y, 0) -> u 0.75,
##     v = y / 2 (all within 1e-5), no face spans more than 0.5 in u; sphere: +y pole v = 1, -y pole v = 0, equator v = 0.5,
##     (r, 0, 0) -> u 0.75
##   4 STRETCH HEAT: the flat grid with uv = (4 x, y): angle max = 4 within 1e-3, every face heat >= 0.9 (red), the LSCM
##     grid every face heat < 0.01 (blue); one corner moved so a triangle folds: flipped_faces >= 1 and that face heat 1
##   5 CHECKER: 512 px, 8 cells: neighbouring cell centres differ in luminance by > 0.3, diagonal ones (same shade, the
##     next column's hue) by < 0.2;
##     KMeshView shading "uv_checker" puts the corner UVs on the surface and the checker texture on its material,
##     "uv_stretch" puts per-vertex heat colours on it
##   6 TIMING: a wavy 72 x 70 grid (5040 quads) unwraps by LSCM in < 10 s of CPU time (this process, /proc/self/stat; the
##     wall clock is printed too, it depends on the machine's load), angle mean < 1.05, no flipped face

var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


## nx x ny quads over w x h on the xy plane (z from zf), cell edges bent by `bend` so the cells are uneven
func grid(nx: int, ny: int, w: float, h: float, zf := Callable(), bend := 0.0) -> KMesh:
	var vs := PackedVector3Array()
	for j in ny + 1:
		for i in nx + 1:
			var s := float(i) / nx
			s = s + bend * s * (1.0 - s)
			var x := s * w
			var y := float(j) / ny * h
			vs.append(Vector3(x, y, zf.call(x, y) if zf.is_valid() else 0.0))
	var fs: Array = []
	for j in ny:
		for i in nx:
			var a := j * (nx + 1) + i
			fs.append([a, a + 1, a + nx + 2, a + nx + 1])
	return KMesh.new().from_arrays(vs, fs)


func _cdist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


## CPU seconds used by this process (user + system), from /proc/self/stat; -1 where there is none
func cpu_s() -> float:
	var f := FileAccess.open("/proc/self/stat", FileAccess.READ)
	if f == null:
		return -1.0
	var t := f.get_line()   # (a /proc file reads as size 0: get_as_text gives nothing)
	var parts := t.substr(t.rfind(")") + 2).split(" ")
	return (float(parts[11]) + float(parts[12])) / 100.0   # fields 14, 15 (utime, stime) in clock ticks of 1/100 s


func in01(m: KMesh) -> bool:
	for q in m.attr_data(KMeshUV.UV):
		if q.x < -1e-6 or q.y < -1e-6 or q.x > 1.0 + 1e-6 or q.y > 1.0 + 1e-6:
			return false
	return true


func uv_sphere(seg: int, rings: int, r: float) -> KMesh:
	var vs := PackedVector3Array([Vector3(0, r, 0)])
	for j in range(1, rings):
		var th := PI * j / rings
		for i in seg:
			var ph := TAU * i / seg
			vs.append(Vector3(r * sin(th) * sin(ph), r * cos(th), r * sin(th) * cos(ph)))
	vs.append(Vector3(0, -r, 0))
	var bot := vs.size() - 1
	var fs: Array = []
	var at := func(j: int, i: int) -> int: return 1 + (j - 1) * seg + posmod(i, seg)
	for i in seg:
		fs.append([0, at.call(1, i), at.call(1, i + 1)])
		fs.append([bot, at.call(rings - 1, i + 1), at.call(rings - 1, i)])
	for j in range(1, rings - 1):
		for i in seg:
			fs.append([at.call(j, i), at.call(j + 1, i), at.call(j + 1, i + 1), at.call(j, i + 1)])
	var m := KMesh.new().from_arrays(vs, fs)
	# CCW from outside? flip every face if the first normal points in
	if m.face_normals[0].dot(m.face_center(0)) < 0.0:
		for f in fs:
			f.reverse()
		m = KMesh.new().from_arrays(vs, fs)
	return m


func cylinder(seg: int, rows: int, r: float, h: float) -> KMesh:
	var vs := PackedVector3Array()
	for j in rows + 1:
		for i in seg:
			var ph := TAU * i / seg
			vs.append(Vector3(r * sin(ph), h * j / rows, r * cos(ph)))
	var fs: Array = []
	for j in rows:
		for i in seg:
			var a := j * seg + i
			var b := j * seg + (i + 1) % seg
			fs.append([a, b, b + seg, a + seg])
	var m := KMesh.new().from_arrays(vs, fs)
	if m.face_normals[0].dot(m.face_center(0) - Vector3(0, m.face_center(0).y, 0)) < 0.0:
		for f in fs:
			f.reverse()
		m = KMesh.new().from_arrays(vs, fs)
	return m


## uv of vertex v (first corner that has it)
func uv_of(m: KMesh, v: int, face := -1) -> Vector2:
	var d = m.attr_data(KMeshUV.UV)
	for f in m.face_count():
		if face != -1 and f != face:
			continue
		var fp: PackedInt32Array = m.faces[f]
		for i in fp.size():
			if fp[i] == v:
				return d[m.face_he0[f] + i]
	return Vector2(-9, -9)


func vert_near(m: KMesh, p: Vector3) -> int:
	for v in m.vert_count():
		if m.verts[v].distance_to(p) < 1e-5:
			return v
	return -1


func _init() -> void:
	# ---- 1 flat grid
	var g := grid(12, 9, 2.0, 1.3, Callable(), 0.6)
	var r := KMeshUV.unwrap_lscm(g)
	var s := KMeshUV.stretch(g)
	print("  flat grid: %d islands, %d CG iterations, %.1f ms; angle max %.6f, sd max %.6f, L2 %.6f" % [r["islands"], r["iters"], r["ms"], s["angle_max"], s["sd_max"], s["l2"]])
	ok(r["islands"] == 1 and s["angle_max"] < 1.001 and s["sd_max"] < 1.001 and absf(s["l2"] - 1.0) < 1e-3 and in01(g) and s["flipped_faces"] == 0,
		"(1) flat grid unwraps with no distortion: angle max %.5f, sd max %.5f, L2 %.5f, in 0..1 %s, flipped %d" % [s["angle_max"], s["sd_max"], s["l2"], in01(g), s["flipped_faces"]])

	# ---- 2 cube with seams
	var c := KMeshView.make_cube(1.0, 4)
	var h := 0.5
	var cuts: Array = []
	for e in c.edges():
		var mid: Vector3 = (c.verts[e.x] + c.verts[e.y]) * 0.5
		var on := []
		for k in 3:
			on.append(absf(absf(mid[k]) - h) < 1e-6)
		var big: bool = (int(on[0]) + int(on[1]) + int(on[2])) >= 2
		if not big:
			continue
		var vert_back_left: bool = on[0] and on[2] and mid.x < 0.0 and mid.z < 0.0
		var top_or_bottom_not_front: bool = on[1] and (on[0] or (on[2] and mid.z < 0.0))
		if vert_back_left or top_or_bottom_not_front:
			cuts.append(e)
	KMeshUV.mark_seams(c, cuts)
	r = KMeshUV.unwrap_lscm(c)
	s = KMeshUV.stretch(c)
	print("  cube net: %d seam edges, %d islands, %d CG iterations, %.1f ms" % [cuts.size(), r["islands"], r["iters"], r["ms"]])
	ok(cuts.size() == 28 and r["islands"] == 1 and s["angle_max"] < 1.01 and s["flipped_faces"] == 0 and in01(c),
		"(2a) cube cut as a cross net (7 edges, 28 seam edges): %d island, angle max %.5f, sd max %.5f, flipped %d" % [r["islands"], s["angle_max"], s["sd_max"], s["flipped_faces"]])
	var c2 := KMeshView.make_cube(1.0, 4)
	var ns := KMeshUV.seams_by_angle(c2, 60.0)
	r = KMeshUV.unwrap_lscm(c2)
	s = KMeshUV.stretch(c2)
	ok(ns == 48 and r["islands"] == 6 and s["angle_max"] < 1.01 and s["flipped_faces"] == 0 and in01(c2),
		"(2b) cube, seams by angle: %d seam edges, %d islands, angle max %.5f, flipped %d" % [ns, r["islands"], s["angle_max"], s["flipped_faces"]])
	var sp := uv_sphere(24, 12, 0.5)
	var mer: Array = []
	for e in sp.edges():
		var a: Vector3 = sp.verts[e.x]
		var b: Vector3 = sp.verts[e.y]
		if absf(a.x) < 1e-6 and absf(b.x) < 1e-6 and a.z <= 1e-6 and b.z <= 1e-6:
			mer.append(e)
	KMeshUV.mark_seams(sp, mer)
	r = KMeshUV.unwrap_lscm(sp)
	s = KMeshUV.stretch(sp)
	var amin := INF
	var amax := 0.0
	for a in s["area"]:
		amin = minf(amin, a)
		amax = maxf(amax, a)
	ok(r["islands"] == 1 and s["flipped_faces"] == 0 and s["angle_mean"] < 1.25,
		"(2c) sphere cut on one meridian (%d edges): angle mean %.3f, max %.3f, area ratio %.2f..%.2f, L2 %.2f, flipped %d, %d CG iterations" % [mer.size(), s["angle_mean"], s["angle_max"], amin, amax, s["l2"], s["flipped_faces"], r["iters"]])

	# ---- 3 projections
	var cb := KMeshView.make_cube(1.0, 2)
	KMeshUV.project_cube(cb)
	var px_f := -1
	var pz_f := -1
	for f in cb.face_count():
		if cb.face_normals[f].x > 0.9 and px_f == -1 and cb.faces[f].has(vert_near(cb, Vector3(0.5, 0.5, 0.5))):
			px_f = f
		if cb.face_normals[f].z > 0.9 and pz_f == -1:
			pz_f = f
	var q1 := uv_of(cb, vert_near(cb, Vector3(0.5, 0.5, 0.5)), px_f)
	var pxf2 := -1
	for f in cb.face_count():
		if cb.face_normals[f].x > 0.9 and cb.faces[f].has(vert_near(cb, Vector3(0.5, -0.5, -0.5))):
			pxf2 = f
	var q2 := uv_of(cb, vert_near(cb, Vector3(0.5, -0.5, -0.5)), pxf2)
	var zgood := true
	for v in cb.faces[pz_f]:
		var p: Vector3 = cb.verts[v]
		if uv_of(cb, v, pz_f).distance_to(Vector2(p.x + 0.5, p.y + 0.5)) > 1e-5:
			zgood = false
	ok(q1.distance_to(Vector2(0, 1)) < 1e-5 and q2.distance_to(Vector2(1, 0)) < 1e-5 and zgood,
		"(3) cube projection: +x (0.5, 0.5, 0.5) -> %s (expect (0, 1)), (0.5, -0.5, -0.5) -> %s (expect (1, 0)), +z face = (x + 0.5, y + 0.5) %s" % [q1, q2, zgood])
	var cy := cylinder(24, 4, 0.5, 2.0)
	KMeshUV.project_cylinder(cy)
	var cerr := 0.0
	for f in cy.face_count():
		var fp: PackedInt32Array = cy.faces[f]
		for i in fp.size():
			var p: Vector3 = cy.verts[fp[i]]
			var q: Vector2 = cy.attr_data(KMeshUV.UV)[cy.face_he0[f] + i]
			cerr = maxf(cerr, absf(q.y - p.y / 2.0))
			if absf(p.x) < 1e-6 and p.z > 0.0:
				cerr = maxf(cerr, absf(q.x - 0.5))
			if absf(p.z) < 1e-6 and p.x > 0.0:
				cerr = maxf(cerr, absf(q.x - 0.75))
	var span := 0.0
	for f in cy.face_count():
		var lo := INF
		var hi := -INF
		for i in (cy.faces[f] as PackedInt32Array).size():
			var q: Vector2 = cy.attr_data(KMeshUV.UV)[cy.face_he0[f] + i]
			lo = minf(lo, q.x)
			hi = maxf(hi, q.x)
		span = maxf(span, hi - lo)
	ok(cerr < 1e-5 and span <= 0.5, "(3) cylinder projection: worst error on the known points %.7f, widest face span in u %.3f (one face = %.3f)" % [cerr, span, 1.0 / 24.0])
	var sph := uv_sphere(24, 12, 0.5)
	KMeshUV.project_sphere(sph)
	var n_pole := uv_of(sph, 0)
	var s_pole := uv_of(sph, sph.vert_count() - 1)
	var eq := uv_of(sph, vert_near(sph, Vector3(0.5, 0, 0)))
	ok(absf(n_pole.y - 1.0) < 1e-5 and absf(s_pole.y) < 1e-5 and absf(eq.y - 0.5) < 1e-5 and absf(eq.x - 0.75) < 1e-5,
		"(3) sphere projection: +y pole v %.5f, -y pole v %.5f, (r, 0, 0) -> %s (expect v 1, 0, (0.75, 0.5))" % [n_pole.y, s_pole.y, eq])

	# ---- 4 stretch heat
	var gs := grid(12, 9, 2.0, 1.3)
	var su := PackedVector2Array()
	for f in gs.face_count():
		for v in gs.faces[f]:
			su.append(Vector2(gs.verts[v].x * 4.0, gs.verts[v].y))
	gs.add_attr(KMeshUV.UV, KMesh.AD_CORNER, TYPE_VECTOR2)
	gs.set_attr_data(KMeshUV.UV, su)
	var st := KMeshUV.stretch(gs)
	var hmin := 1.0
	for t in st["heat"]:
		hmin = minf(hmin, t)
	var lscm_heat := 0.0
	for t in KMeshUV.stretch(g)["heat"]:
		lscm_heat = maxf(lscm_heat, t)
	ok(absf(st["angle_max"] - 4.0) < 1e-3 and hmin >= 0.9 and lscm_heat < 0.01,
		"(4) uv = (4 x, y): angle max %.4f (expect 4), lowest face heat %.3f (bar >= 0.9, colour %s); the LSCM grid's highest heat %.4f (bar < 0.01)" % [st["angle_max"], hmin, KMeshUV.heat_color(hmin).to_html(false), lscm_heat])
	var gf := grid(4, 4, 1.0, 1.0)
	KMeshUV.unwrap_lscm(gf)
	var fd = gf.attr_data(KMeshUV.UV)
	fd[gf.face_he0[5] + 2] = fd[gf.face_he0[5]] - (fd[gf.face_he0[5] + 2] - fd[gf.face_he0[5]])   # corner 2 through corner 0: the quad folds
	gf.set_attr_data(KMeshUV.UV, fd)
	var sf := KMeshUV.stretch(gf)
	ok(sf["flipped_faces"] >= 1 and sf["flipped"][5] == 1 and sf["heat"][5] == 1.0, "(4) a folded face is found: %d flipped, face 5 heat %.2f" % [sf["flipped_faces"], sf["heat"][5]])

	# ---- 5 checker + the view hook
	var img := KMeshUV.checker_image(512, 8)
	var cs := 64
	var nb := 0.0
	var dg := 1.0
	var diag_d := 0.0
	for j in 7:
		for i in 7:
			var l0 := img.get_pixel(i * cs + 32, j * cs + 32).get_luminance()
			var lr := img.get_pixel((i + 1) * cs + 32, j * cs + 32).get_luminance()
			var ld := img.get_pixel(i * cs + 32, (j + 1) * cs + 32).get_luminance()
			var lg := img.get_pixel((i + 1) * cs + 32, (j + 1) * cs + 32).get_luminance()
			dg = minf(dg, minf(absf(l0 - lr), absf(l0 - ld)))
			diag_d = maxf(diag_d, absf(l0 - lg))
	nb = dg
	ok(nb > 0.3 and diag_d < 0.2, "(5) checker 512 px x 8 cells: neighbours differ by >= %.3f luminance, diagonals by <= %.3f" % [nb, diag_d])
	var vw := KMeshView.new()
	var vc := KMeshView.make_cube(0.6, 4)
	KMeshUV.seams_by_angle(vc, 60.0)
	KMeshUV.unwrap_lscm(vc)
	vw.set_mesh(vc)
	vw.shading = "uv_checker"
	vw.rebuild()
	var surf: MeshInstance3D = vw.get_node("surf")
	var arr: Array = surf.mesh.surface_get_arrays(0)
	var mt := surf.material_override as StandardMaterial3D
	var uv_ok: bool = arr[Mesh.ARRAY_TEX_UV] != null and (arr[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() == (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	ok(uv_ok and mt != null and mt.albedo_texture != null, "(5) view shading uv_checker: %d surface UVs for %d vertices, checker texture on %s" % [(arr[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() if uv_ok else 0, (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), mt.albedo_texture if mt else null])
	vw.shading = "uv_stretch"
	vw.rebuild()
	arr = surf.mesh.surface_get_arrays(0)
	mt = surf.material_override as StandardMaterial3D
	var col_ok: bool = arr[Mesh.ARRAY_COLOR] != null and (arr[Mesh.ARRAY_COLOR] as PackedColorArray).size() == (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	ok(col_ok and mt.vertex_color_use_as_albedo and _cdist((arr[Mesh.ARRAY_COLOR] as PackedColorArray)[0], KMeshUV.heat_color(0.0)) < 0.02,
		"(5) view shading uv_stretch: per-vertex heat colours %s, the unwrapped cube is blue (%s)" % [col_ok, (arr[Mesh.ARRAY_COLOR] as PackedColorArray)[0].to_html(false) if col_ok else "-"])
	vw.free()

	# ---- 6 timing
	var wv := grid(72, 70, 3.0, 2.8, func(x: float, y: float) -> float: return 0.15 * sin(x * 2.5) * cos(y * 2.0))
	var t0 := Time.get_ticks_msec()
	var c0 := cpu_s()
	r = KMeshUV.unwrap_lscm(wv)
	var cpu := cpu_s() - c0
	var ms := Time.get_ticks_msec() - t0
	s = KMeshUV.stretch(wv)
	var ms2 := Time.get_ticks_msec() - t0 - ms
	ok(wv.face_count() == 5040 and (cpu < 10.0 if c0 >= 0.0 else ms < 60000) and s["angle_mean"] < 1.05 and s["flipped_faces"] == 0,
		"(6) wavy grid %d faces: LSCM %.1f s CPU, %d ms wall (%d CG iterations, %d wedges), stretch %d ms; angle mean %.4f, max %.4f, L2 %.4f" % [wv.face_count(), cpu, ms, r["iters"], r["wedges"], ms2, s["angle_mean"], s["angle_max"], s["l2"]])

	print("UVUNWRAP ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails else 0)
