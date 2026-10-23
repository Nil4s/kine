extends SceneTree
## godot --headless --path . -s tests/boolean_test.gd     (ROADMAP_400 B10 booleans, scripts/kmesh_boolean.gd)
## Bars (stated before measuring). Volumes are summed in float64 from the result's face fans; "clean" = closed (no
## border edge), manifold, and KMeshValidate.report finds nothing.
##  1 cube 1 m ∪ the same cube moved (0.5, 0.5, 0.5): volume 2 - 0.125 = 1.875 within 1e-6 m^3, clean. Moved (0.5, 0, 0)
##    (four faces in one plane with the other cube's, same facing): 1.5 within 1e-6, clean
##  2 cube − UV sphere r 0.3 (32 x 16) centred on a corner: the cube's faces pass exactly through the sphere's meridians
##    and equator (edges lying in the faces), so the mesh octant is exactly 1/8 of the mesh sphere: volume
##    1 - V_mesh / 8 within 1e-6, clean. The faceting error against the true sphere (pi r^3 / 6 - V_mesh / 8) is printed and
##    must be under 2 % of the octant. Generic case: an ico sphere (level 3) turned by an odd rotation on the corner: the
##    removed volume lies between the octants of its inscribed sphere (r_in = nearest face plane) and of r, +- 1e-6
##  3 cube ∩ cube moved (0.3, 0.4, 0.5): the overlap box 0.7 x 0.6 x 0.5 = 0.21 within 1e-6, clean, 6 faces (a box)
##  4 cubes touching face to face (x 0..1 and 1..2): union = one box: volume 2 within 1e-6, area 10 m^2 within 1e-6 (no
##    wall left inside), clean; difference = the first cube (volume 1, 6 faces); intersect = nothing (0 faces)
##  5 time: two ico spheres of 5120 faces each, overlapping: union under 20 s, clean, volume between the union of the
##    inscribed spheres and of the circumscribed spheres (lens formula); the difference likewise clean, its volume between
##    the mesh sphere minus the outer lens and minus the inscribed lens
##  6 attributes of the target: a corner UV that is a linear function of position comes back on every target corner
##    within 1e-5 (interpolated on the new corners), a vert label stays one of the original values (never a blend) and is
##    unchanged on the old verts, a face channel stays its source face's value; the operand's faces get the default
##  7 an open mesh is refused with a message naming a next step
##  8 the model preview: the S box has three boolean lines; with a sphere added and moved onto the test cube's corner,
##    MeshTools op "boolean_difference" is ONE undo step, the result is clean and lighter than the cube; Ctrl+Z gives the
##    mesh back exactly; selecting a vertex of the cube makes the cube the operand
##  9 hard cases: a cube with itself (all faces coplanar): union and intersect give the cube (6 faces, volume 1, clean),
##    difference nothing; cube − a sphere wholly inside: two clean shells, volume 1 - V_sphere within 1e-6
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func vol(m: KMesh) -> float:
	var s := 0.0
	for f in m.faces:
		var fp: PackedInt32Array = f
		var a := m.verts[fp[0]]
		for i in range(1, fp.size() - 1):
			var b := m.verts[fp[i]]
			var c := m.verts[fp[i + 1]]
			var ax := float(a.x)
			var ay := float(a.y)
			var az := float(a.z)
			var bx := float(b.x)
			var by := float(b.y)
			var bz := float(b.z)
			var cx := float(c.x)
			var cy := float(c.y)
			var cz := float(c.z)
			s += (ax * (by * cz - bz * cy) - ay * (bx * cz - bz * cx) + az * (bx * cy - by * cx)) / 6.0
	return s


func area(m: KMesh) -> float:
	var s := 0.0
	for f in m.faces:
		var fp: PackedInt32Array = f
		var nx := 0.0
		var ny := 0.0
		var nz := 0.0
		for i in fp.size():
			var p := m.verts[fp[i]]
			var q := m.verts[fp[(i + 1) % fp.size()]]
			nx += (float(p.y) - q.y) * (float(p.z) + q.z)
			ny += (float(p.z) - q.z) * (float(p.x) + q.x)
			nz += (float(p.x) - q.x) * (float(p.y) + q.y)
		s += sqrt(nx * nx + ny * ny + nz * nz) * 0.5
	return s


func clean(m: KMesh) -> bool:
	return m.face_count() > 0 and m.is_closed() and m.is_manifold() and KMeshValidate.report(m)["ok"]


func why(m: KMesh) -> String:
	return "closed %s manifold %s report %s" % [m.is_closed(), m.is_manifold(), str((KMeshValidate.report(m)["problems"] as Array).map(func(p): return [p["kind"], p["count"]]))]


func moved(m: KMesh, d: Vector3, basis := Basis.IDENTITY) -> KMesh:
	var v := m.verts.duplicate()
	for i in v.size():
		v[i] = basis * v[i] + d
	return KMesh.new().from_arrays(v, m.faces)


func cube1() -> KMesh:
	return moved(KMeshPrims.cube(Vector3.ONE), Vector3(0.5, 0.5, 0.5))   # 0..1


## nearest face plane of a mesh from point c
func r_in(m: KMesh, c: Vector3) -> float:
	var r := INF
	for fi in m.face_count():
		r = minf(r, absf(m.face_normals[fi].dot(m.verts[(m.faces[fi] as PackedInt32Array)[0]] - c)))
	return r


## the overlap of two balls of radius r, centres d apart
func lens(r: float, d: float) -> float:
	return PI * (4.0 * r + d) * pow(2.0 * r - d, 2.0) / 12.0 if d < 2.0 * r else 0.0


func lens_union(r: float, d: float) -> float:
	return 2.0 * 4.0 / 3.0 * PI * r * r * r - lens(r, d)


func _init() -> void:
	# ---- 1 union
	var a := cube1()
	var r := KMeshBoolean.run(a, moved(cube1(), Vector3(0.5, 0.5, 0.5)), "union")
	ok(absf(vol(r) - 1.875) <= 1e-6 and clean(r), "(1) cube ∪ cube moved (.5 .5 .5): volume %.9f m^3 (expect 1.875), %d faces, %s, %s" % [vol(r), r.face_count(), why(r), str(KMeshBoolean.last)])
	r = KMeshBoolean.run(a, moved(cube1(), Vector3(0.5, 0, 0)), "union")
	ok(absf(vol(r) - 1.5) <= 1e-6 and clean(r), "(1) cube ∪ cube moved (.5 0 0), coplanar faces: volume %.9f (expect 1.5), %d faces, %s" % [vol(r), r.face_count(), why(r)])

	# ---- 2 cube − sphere on a corner
	var sph := KMeshPrims.uv_sphere(0.3, 32, 16)
	var vm := vol(sph)
	r = KMeshBoolean.run(a, moved(sph, Vector3(1, 1, 1)), "difference")
	var want := 1.0 - vm / 8.0
	var oct := PI * 0.3 * 0.3 * 0.3 / 6.0
	ok(absf(vol(r) - want) <= 1e-6 and clean(r), "(2) cube − UV sphere 32x16 on the corner: volume %.9f vs 1 - V_mesh/8 = %.9f (off %.12f), %d faces, %s, %s" % [vol(r), want, vol(r) - want, r.face_count(), why(r), str(KMeshBoolean.last)])
	var ferr := oct - vm / 8.0
	ok(ferr > 0.0 and ferr < 0.02 * oct, "(2) faceting error of the 32x16 sphere: the true octant %.6f m^3, the mesh octant %.6f: %.9f m^3 (%.2f %% of the octant, bar 2 %%)" % [oct, vm / 8.0, ferr, ferr / oct * 100.0])
	var ico := moved(KMeshPrims.ico_sphere(0.3, 3), Vector3(1, 1, 1), Basis.from_euler(Vector3(0.37, 1.13, -0.71)))
	var ri := r_in(ico, Vector3(1, 1, 1))
	r = KMeshBoolean.run(a, ico, "difference")
	var removed := 1.0 - vol(r)
	var lo := PI * ri * ri * ri / 6.0
	ok(removed >= lo - 1e-6 and removed <= oct + 1e-6 and clean(r), "(2) cube − turned ico sphere (level 3) on the corner: removed %.6f m^3 within [%.6f (r_in %.4f), %.6f], %s, %s" % [removed, lo, ri, oct, why(r), str(KMeshBoolean.last)])

	# ---- 3 intersect
	r = KMeshBoolean.run(a, moved(cube1(), Vector3(0.3, 0.4, 0.5)), "intersect")
	ok(absf(vol(r) - 0.21) <= 1e-6 and clean(r) and r.face_count() == 6, "(3) cube ∩ cube moved (.3 .4 .5): volume %.9f (expect 0.21), %d faces (expect 6), %s" % [vol(r), r.face_count(), why(r)])

	# ---- 4 touching
	var b := moved(cube1(), Vector3(1, 0, 0))
	r = KMeshBoolean.run(a, b, "union")
	ok(absf(vol(r) - 2.0) <= 1e-6 and absf(area(r) - 10.0) <= 1e-6 and clean(r), "(4) touching cubes ∪: volume %.9f (expect 2), area %.9f m^2 (expect 10: no inner wall), %d faces, %s" % [vol(r), area(r), r.face_count(), why(r)])
	r = KMeshBoolean.run(a, b, "difference")
	ok(absf(vol(r) - 1.0) <= 1e-6 and r.face_count() == 6 and clean(r), "(4) touching cubes −: the first cube (volume %.9f, %d faces), %s" % [vol(r), r.face_count(), why(r)])
	r = KMeshBoolean.run(a, b, "intersect")
	ok(r != null and r.face_count() == 0, "(4) touching cubes ∩: nothing (%d faces)" % (r.face_count() if r != null else -1))

	# ---- 9 more hard cases: the very same cube (every face coplanar), a sphere nested inside
	var ids := []
	for o in KMeshBoolean.OPS:
		r = KMeshBoolean.run(a, cube1(), o)
		ids.append([r.face_count(), snappedf(vol(r), 1e-9), clean(r) or r.face_count() == 0])
	ok(ids == [[6, 1.0, true], [0, 0.0, true], [6, 1.0, true]], "(9) a cube with itself: ∪ / − / ∩ = [faces, volume, clean] %s (expect the cube, nothing, the cube)" % str(ids))
	var inner := moved(sph, Vector3(0.5, 0.5, 0.5))
	r = KMeshBoolean.run(a, inner, "difference")
	ok(absf(vol(r) - (1.0 - vm)) <= 1e-6 and clean(r) and KMeshBoolean.components(r).size() == 2, "(9) cube − a sphere inside it: two shells (%d), volume %.9f (expect %.9f), %s" % [KMeshBoolean.components(r).size(), vol(r), 1.0 - vm, why(r)])

	# ---- 5 time, 2 x 5120 faces
	var s1 := KMeshPrims.ico_sphere(0.5, 4)
	var off := Vector3(0.35, 0.12, 0.07)
	var s2 := moved(KMeshPrims.ico_sphere(0.5, 4), off, Basis.from_euler(Vector3(0.2, 0.5, 0.1)))
	var t0 := Time.get_ticks_msec()
	r = KMeshBoolean.run(s1, s2, "union")
	var ms := Time.get_ticks_msec() - t0
	var ri1 := r_in(s1, Vector3.ZERO)
	var vlo := lens_union(ri1, off.length())
	var vhi := lens_union(0.5, off.length())
	ok(ms < 20000 and clean(r) and vol(r) >= vlo - 1e-6 and vol(r) <= vhi + 1e-6, "(5) %d + %d faces ∪ in %d ms (bar 20000): volume %.6f within [%.6f, %.6f], %d faces, %s, %s" % [s1.face_count(), s2.face_count(), ms, vol(r), vlo, vhi, r.face_count(), why(r), str(KMeshBoolean.last)])
	t0 = Time.get_ticks_msec()
	r = KMeshBoolean.run(s1, s2, "difference")
	var vd := vol(r)
	var dlo := vol(s1) - lens(0.5, off.length())
	var dhi := vol(s1) - lens(ri1, off.length())
	ok(clean(r) and vd >= dlo - 1e-6 and vd <= dhi + 1e-6, "(5) difference of the same in %d ms: volume %.6f within [%.6f, %.6f] (the mesh sphere minus the lens of the outer / inscribed spheres), %s" % [Time.get_ticks_msec() - t0, vd, dlo, dhi, why(r)])

	# ---- 6 attributes
	var at := cube1()
	at.add_attr("uv", KMesh.AD_CORNER, TYPE_VECTOR2)
	at.add_attr("body_bone", KMesh.AD_VERT, TYPE_FLOAT)
	at.add_attr("fidx", KMesh.AD_FACE, TYPE_FLOAT, -1.0)
	var uvf := func(p: Vector3) -> Vector2: return Vector2(p.x + 0.3 * p.z, p.y - 0.2 * p.z)
	var c := 0
	for fi in at.face_count():
		at.set_attr("fidx", fi, float(fi))
		for v in (at.faces[fi] as PackedInt32Array):
			at.set_attr("uv", c, uvf.call(at.verts[v]))
			c += 1
	for v in at.vert_count():
		at.set_attr("body_bone", v, float(v))
	r = KMeshBoolean.run(at, moved(sph, Vector3(1, 1, 1)), "difference")
	var uv_err := 0.0
	var ci := 0
	var lab_bad := 0
	var face_bad := 0
	var n_tgt := 0
	var n_op := 0
	for fi in r.face_count():
		var fp: PackedInt32Array = r.faces[fi]
		var nrm := r.face_normals[fi]
		var axis_aligned := absf(nrm.x) > 0.999 or absf(nrm.y) > 0.999 or absf(nrm.z) > 0.999
		var fv: float = r.get_attr("fidx", fi)
		if axis_aligned:
			n_tgt += 1
			var src := -1
			for gi in at.face_count():
				if at.face_normals[gi].dot(nrm) > 0.999:
					src = gi
			if fv != float(src):
				face_bad += 1
		else:
			n_op += 1
			if fv != -1.0:
				face_bad += 1
		for v in fp:
			if axis_aligned:
				uv_err = maxf(uv_err, (r.get_attr("uv", ci) - uvf.call(r.verts[v])).length())
			ci += 1
	for v in r.vert_count():
		var l: float = r.get_attr("body_bone", v)
		if l != floorf(l) or l < 0.0 or l > 7.0:
			lab_bad += 1
		for u in at.vert_count():
			if at.verts[u] == r.verts[v] and l != float(u):
				lab_bad += 1
	ok(uv_err <= 1e-5 and n_tgt > 0 and n_op > 0, "(6) UV on the %d target faces: worst error %.9f (bar 1e-5)" % [n_tgt, uv_err])
	ok(lab_bad == 0, "(6) vert label: %d of %d verts not an original value (or changed on an old vert)" % [lab_bad, r.vert_count()])
	ok(face_bad == 0, "(6) face channel: %d faces off (target faces keep their source face's value, the %d operand faces the default -1)" % [face_bad, n_op])

	# ---- 7 refuse an open mesh
	r = KMeshBoolean.run(KMeshPrims.plane(), a, "union")
	ok(r == null and KMeshBoolean.last_error.contains("not closed") and KMeshBoolean.last_error.contains("Fill"), "(7) open target refused: '%s'" % KMeshBoolean.last_error)

	# ---- 8 the model preview
	var lines := MeshTools.TOOLS.filter(func(t): return String(t["do"]).begins_with("op:boolean_"))
	ok(lines.size() == 3, "(8) the S box has %d boolean lines (expect 3)" % lines.size())
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 4:
		await process_frame
	m._kmesh_edit_start()
	await process_frame
	var ui = m.kmed
	var nv0: int = ui.mesh.vert_count()
	var cube_v0: float = vol(ui.mesh)
	var hi := -Vector3.INF
	for p in ui.mesh.verts:
		hi = hi.max(p)
	var said := KMeshBoolean.op("boolean_difference", m)
	ok(said.contains("two parts"), "(8) on the cube alone it says what to do: '%s'" % said)
	ui.add_prim("uv_sphere", {"radius": 0.15, "segments": 16, "rings": 8})
	ui.undo.begin(ui.mesh)   # the user moves the sphere onto the cube's top corner
	var slo := Vector3.INF
	var shi := -Vector3.INF
	for i in range(nv0, ui.mesh.vert_count()):
		slo = slo.min(ui.mesh.verts[i])
		shi = shi.max(ui.mesh.verts[i])
	var sc := (slo + shi) * 0.5
	for i in range(nv0, ui.mesh.vert_count()):
		ui.mesh.verts[i] += hi - sc
	ui.mesh.rebuild()
	ui.undo.commit("Move")
	var before_v: PackedVector3Array = ui.mesh.verts.duplicate()
	var before_f: Array = ui.mesh.faces.duplicate()
	var n0: int = ui.undo.steps.size()
	ui.sel.clear()
	MeshTools.op("boolean_difference", m)
	var v1 := vol(ui.mesh)
	ok(ui.undo.steps.size() == n0 + 1 and clean(ui.mesh) and v1 < cube_v0 - 1e-4 and v1 > cube_v0 - 4.0 / 3.0 * PI * 0.15 ** 3 / 8.0 - 1e-6,
		"(8) difference on the preview: one undo step (%d), volume %.6f < cube %.6f, %s; said '%s'" % [ui.undo.steps.size() - n0, v1, cube_v0, why(ui.mesh), m.ui_status.text])
	ui.undo.undo()
	ok(ui.mesh.verts == before_v and KMeshUndo._same_faces(ui.mesh.faces, before_f), "(8) Ctrl+Z gives the cube + sphere back exactly (%d verts)" % ui.mesh.vert_count())
	var sel := KMeshSelect.new(ui.mesh)
	sel.verts[0] = true
	var pk := KMeshBoolean.pick(ui.mesh, sel)
	ok(pk.has("operand") and (pk["operand"] as PackedInt32Array).size() == 96 and (pk["target"] as PackedInt32Array).size() == ui.mesh.face_count() - 96,
		"(8) a selected cube vertex makes the cube (96 faces) the operand: %s" % str(pk.keys()))
	ui.stop()
	print("BOOLEAN ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails else 0)
