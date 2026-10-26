## godot --headless --path . -s tests/sepjoin_test.gd     (ROADMAP_400 B17 + the vertex-click fix in KMeshView.ray_face)
## Bars, written before measuring:
##  0 VERTEX CLICK (the fix): 1000 clicks EXACTLY on the projected point of a seen vertex (random camera 1.5-3 m away, any
##    direction; a vertex is seen when one of its faces faces the camera) on each of: the 1-quad-a-side cube, the 4x4 test
##    cube, the dense test sphere (KMeshSculptUI.make_sphere, 24 splits): ray_face hits a face at every one (0 misses
##    of 3000). The same rays through the OLD strict Moller-Trumbore (a copy kept here) miss some (> 0): the instrument can
##    move. Named cases: the click on each of a front-seen cube's 8 corners that faces the camera, and on a sphere vertex
##    on the silhouette, hit. Not too lenient: from 3 m on the cube's axis a ray 0.1 mm outside the silhouette corner
##    misses, 0.1 mm inside hits.
## B17 on a TWO-CUBE mesh (two 4x4 test cubes apart: 196 verts, 192 faces) carrying a corner UV channel, a vert label
## channel (anat_tag), an edge channel (crease) and a face channel, every value distinct:
##  1 SEPARATE a 2x2 patch of cube A's front (4 faces, given as a face list): the mesh then has 3 connected components
##    and one of them is exactly those faces; the doubled verts are exactly the patch's verts that other faces also use
##    (counted here independently); verts 0..195 bit-exact, every unselected face's index list bit-exact, every corner of
##    the patch at the same position as before
##  2 LOOSE PARTS: join (nothing selected) makes 1 part of 2 components, nothing moved; separate by loose parts then gives
##    parts == connected components (2); after a patch separate, a join and loose parts: 3 == 3
##  3 ROUND TRIPS: join then separate cube B's faces gives the verts back exactly (positions bit-exact, faces identical);
##    separate the patch then join_weld (a vert of the patch and one of cube A selected) gives the mesh before the
##    separate back exactly (verts, faces, and every channel but the part channel), 2 parts, welded count == doubled count
##  4 ORIGIN: to the bottom centre: origin.y == the lowest y, its x / z == the bounding box centre (both computed here in
##    float64, within 1e-7 m); to the geometry centre: the box centre; to the cursor: the cursor's point; no vertex moves
##  5 SAVE / LOAD: the origin comes back exactly from a .kmesh (and the part ids); a mesh with origin 0 writes no "origin";
##    a damaged origin is refused with a message naming a next step
##  6 CHANNELS: after the separate, the UV channel is bit-exact (corners never move), each doubled vert carries its
##    source's anat_tag, every edge's crease equals the crease of its source edge (mapped here independently), the face
##    channel unchanged; after join_weld every one equals the original
##  7 THE MODEL PREVIEW: 7 lines in the S box (MeshTools.TOOLS); with a cube added beside the test cube, each of separate /
##    join / join_weld / separate_loose / origin_geometry / origin_cursor / origin_bottom run through MeshTools.op is ONE
##    undo step (exactly +1), and Ctrl+Z (undo.undo) gives the verts, faces, channels and origin back exactly
extends SceneTree

var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


## the pre-fix ray_face test (strict barycentric bounds), for the before / after count
static func strict_hit(m: KMesh, o: Vector3, d: Vector3) -> bool:
	for f in m.faces:
		var fp: PackedInt32Array = f
		for i in range(1, fp.size() - 1):
			var a := m.verts[fp[0]]
			var e1 := m.verts[fp[i]] - a
			var e2 := m.verts[fp[i + 1]] - a
			var p := d.cross(e2)
			var det := e1.dot(p)
			if det <= 1e-14:
				continue
			var iv := 1.0 / det
			var tv := o - a
			var u := tv.dot(p) * iv
			if u < 0.0 or u > 1.0:
				continue
			var q := tv.cross(e1)
			var v := d.dot(q) * iv
			if v < 0.0 or u + v > 1.0:
				continue
			if e2.dot(q) * iv > 1e-6:
				return true
	return false


func seen(m: KMesh, vi: int, cam_pos: Vector3) -> bool:
	for fi in m.vert_faces(vi):
		if m.face_normals[fi].dot(cam_pos - m.verts[vi]) > 0.0:
			return true
	return false


func _init() -> void:
	await process_frame
	var cam := Camera3D.new()
	root.add_child(cam)
	await process_frame
	# ---- 0 the vertex click
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var total_new := 0
	var total_old := 0
	for which in ["cube", "cube4", "sphere"]:
		var km: KMesh = KMeshPrims.cube() if which == "cube" else (KMeshView.make_cube(1.0, 4) if which == "cube4" else KMeshSculptUI.make_sphere())
		var v := KMeshView.new()
		root.add_child(v)
		await process_frame
		v.set_mesh(km)
		var miss := 0
		var miss_old := 0
		var n := 0
		while n < 1000:
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
			cam.position = dir * rng.randf_range(1.5, 3.0)
			cam.look_at(Vector3.ZERO, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
			var vi := rng.randi() % km.vert_count()
			if not seen(km, vi, cam.position):
				continue
			n += 1
			var sp := cam.unproject_position(km.verts[vi])
			var o := cam.project_ray_origin(sp)
			var d := cam.project_ray_normal(sp)
			if v.ray_face(o, d).is_empty():
				miss += 1
			if not strict_hit(km, o, d):
				miss_old += 1
		total_new += miss
		total_old += miss_old
		print("  %s: %d of 1000 vertex clicks missed before the fix, %d after" % [which, miss_old, miss])
		ok(miss == 0, "(0) %s (%d verts): 1000 clicks exactly on seen vertices, %d miss (bar 0; the old strict test missed %d)" % [which, km.vert_count(), miss, miss_old])
		v.free()
	ok(total_old > 0, "(0) the instrument can move: the old strict test misses %d of the same 3000 rays" % total_old)
	# named cases: a cube seen from a corner direction, every camera-facing corner; a silhouette vertex of the sphere
	var cube := KMeshPrims.cube()
	var cv := KMeshView.new()
	root.add_child(cv)
	await process_frame
	cv.set_mesh(cube)
	cam.position = Vector3(1.7, 1.3, 2.1)
	cam.look_at(Vector3.ZERO)
	var corners_hit := 0
	var corners_seen := 0
	for vi in cube.vert_count():
		if seen(cube, vi, cam.position):
			corners_seen += 1
			var sp := cam.unproject_position(cube.verts[vi])
			corners_hit += 0 if cv.ray_face(cam.project_ray_origin(sp), cam.project_ray_normal(sp)).is_empty() else 1
	ok(corners_seen == 7 and corners_hit == corners_seen, "(0) a cube seen from (1.7, 1.3, 2.1): a click on each of its %d seen corners hits (%d)" % [corners_seen, corners_hit])
	var sph := KMeshSculptUI.make_sphere()
	var sv := KMeshView.new()
	root.add_child(sv)
	await process_frame
	sv.set_mesh(sph)
	cam.position = Vector3(0, 0, 2.0)
	cam.look_at(Vector3.ZERO)
	var sil := -1   # the seen vertex nearest the outline (its normal most nearly square to the view)
	var best := INF
	for vi in sph.vert_count():
		var nn := sph.verts[vi].normalized()
		var c := nn.dot((cam.position - sph.verts[vi]).normalized())
		if c > 0.0 and c < best and seen(sph, vi, cam.position):
			best = c
			sil = vi
	var ssp := cam.unproject_position(sph.verts[sil])
	ok(not sv.ray_face(cam.project_ray_origin(ssp), cam.project_ray_normal(ssp)).is_empty(), "(0) a click on the sphere's silhouette vertex %d (its normal %.2f deg short of square to the view) hits" % [sil, 90.0 - rad_to_deg(acos(best))])
	sv.free()
	# not too lenient: 3 m away on the axis, the corner (0.5, 0.5, 0.5) is on the outline
	cam.position = Vector3(0, 0, 3.0)
	cam.look_at(Vector3.ZERO)
	var out_p := Vector3(0.5001, 0.5001, 0.5)
	var in_p := Vector3(0.4999, 0.4999, 0.5)
	var h_out := cv.ray_face(cam.position, (out_p - cam.position).normalized())
	var h_in := cv.ray_face(cam.position, (in_p - cam.position).normalized())
	ok(h_out.is_empty() and not h_in.is_empty(), "(0) 0.1 mm outside the outline corner misses (%s), 0.1 mm inside hits (%s)" % [h_out.is_empty(), not h_in.is_empty()])
	cv.free()
	cam.free()
	await b17()
	print("SEPJOIN ", "PASS" if fails == 0 else "FAIL %d" % fails)
	TestFiles.cleanup()
	quit(1 if fails else 0)


# ---------------------------------------------------------------- B17

func two_cubes() -> KMesh:
	var a := KMeshView.make_cube(1.0, 4)
	var V := a.verts.duplicate()
	var F: Array = a.faces.duplicate()
	var n := V.size()
	for p in a.verts:
		V.append(p + Vector3(2.0, 0.25, 0.0))
	for f in a.faces:
		var g := PackedInt32Array()
		for v in (f as PackedInt32Array):
			g.append(v + n)
		F.append(g)
	var m := KMesh.new().from_arrays(V, F)
	m.add_attr("uv", KMesh.AD_CORNER, TYPE_VECTOR2)
	var uv: PackedVector2Array = m.attr_data("uv")
	for i in uv.size():
		uv[i] = Vector2(i * 0.001, 1.0 - i * 0.0007)
	m.set_attr_data("uv", uv)
	m.add_attr("anat_tag", KMesh.AD_VERT, TYPE_FLOAT)
	var at: PackedFloat32Array = m.attr_data("anat_tag")
	for i in at.size():
		at[i] = float(i % 37) + 1.0
	m.set_attr_data("anat_tag", at)
	m.add_attr("crease", KMesh.AD_EDGE, TYPE_FLOAT)
	var cr: PackedFloat32Array = m.attr_data("crease")
	for i in cr.size():
		cr[i] = float(i) / 1000.0
	m.set_attr_data("crease", cr)
	m.add_attr("fid", KMesh.AD_FACE, TYPE_FLOAT)
	var fd: PackedFloat32Array = m.attr_data("fid")
	for i in fd.size():
		fd[i] = float(i) * 3.0
	m.set_attr_data("fid", fd)
	return m


func copy(m: KMesh) -> KMesh:
	var c := KMesh.new().from_arrays(m.verts, m.faces)
	c.attrs = m.attr_snapshot()
	c.origin = m.origin
	return c


func same_faces(a: Array, b: Array) -> bool:
	return KMeshUndo._same_faces(a, b)


func chans_equal(a: KMesh, b: KMesh, skip := ["part"]) -> bool:
	for k in a.attrs:
		if k in skip:
			continue
		if not b.attrs.has(k) or a.attrs[k]["data"] != b.attrs[k]["data"]:
			print("  channel %s differs" % k)
			return false
	return true


## a 2x2 block of cube A's front (z = +0.5): faces whose centre has z = 0.5, x and y in (-0.5, 0)
func patch(m: KMesh) -> PackedInt32Array:
	var out := PackedInt32Array()
	for fi in 96:
		var c := m.face_center(fi)
		if absf(c.z - 0.5) < 1e-6 and c.x < 0.0 and c.y < 0.0:
			out.append(fi)
	return out


func b17() -> void:
	# ---- 1 separate
	var m := two_cubes()
	var m0 := copy(m)
	var pf := patch(m)
	var inp := {}
	for fi in pf:
		inp[fi] = true
	var want_dup := {}
	for fi in m.face_count():
		if inp.has(fi):
			continue
		for v in (m.faces[fi] as PackedInt32Array):
			for gi in pf:
				if (m.faces[gi] as PackedInt32Array).has(v):
					want_dup[v] = true
	var r := KMeshSepJoin.separate(m, pf)
	var comps: Array = KMeshBoolean.components(m)
	var as_comp := false
	for c in comps:
		as_comp = as_comp or c == pf
	var rest_ok := true
	for v in m0.vert_count():
		rest_ok = rest_ok and m.verts[v] == m0.verts[v]
	for fi in m.face_count():
		if not inp.has(fi):
			rest_ok = rest_ok and m.faces[fi] == m0.faces[fi]
	var corners_ok := true
	for fi in pf:
		for c in (m.faces[fi] as PackedInt32Array).size():
			corners_ok = corners_ok and m.verts[(m.faces[fi] as PackedInt32Array)[c]] == m0.verts[(m0.faces[fi] as PackedInt32Array)[c]]
	ok(pf.size() == 4 and comps.size() == 3 and as_comp, "(1) separate %d selected faces of a two-cube mesh: %d components, one of them exactly the selected faces (%s)" % [pf.size(), comps.size(), as_comp])
	ok(int(r.get("doubled", -1)) == want_dup.size() and m.vert_count() == m0.vert_count() + want_dup.size(), "(1) %d border verts doubled (independent count %d), %d -> %d verts" % [int(r.get("doubled", -1)), want_dup.size(), m0.vert_count(), m.vert_count()])
	ok(rest_ok and corners_ok, "(1) the rest bit-exact: verts 0..%d and the %d other faces unchanged (%s); every patch corner at its old position (%s)" % [m0.vert_count() - 1, m.face_count() - pf.size(), rest_ok, corners_ok])
	# ---- 6 channels after the separate
	var uv_ok: bool = m.attr_data("uv") == m0.attr_data("uv")
	var at_ok := true
	var at: PackedFloat32Array = m.attr_data("anat_tag")
	var at0: PackedFloat32Array = m0.attr_data("anat_tag")
	var src := PackedInt32Array()   # new vert -> old vert, from the patch's corners (faces keep their corner order)
	src.resize(m.vert_count())
	for v in m0.vert_count():
		src[v] = v
	for fi in pf:
		for c in (m.faces[fi] as PackedInt32Array).size():
			src[(m.faces[fi] as PackedInt32Array)[c]] = (m0.faces[fi] as PackedInt32Array)[c]
	for v in m.vert_count():
		at_ok = at_ok and at[v] == at0[src[v]]
	var cr_ok := true
	var cr: PackedFloat32Array = m.attr_data("crease")
	var cr0: PackedFloat32Array = m0.attr_data("crease")
	var e0 := {}
	var el0: Array = m0.edges()
	for i in el0.size():
		e0[el0[i]] = i
	var el: Array = m.edges()
	for i in el.size():
		var a: int = src[(el[i] as Vector2i).x]
		var b: int = src[(el[i] as Vector2i).y]
		cr_ok = cr_ok and cr[i] == cr0[e0[Vector2i(mini(a, b), maxi(a, b))]]
	var fid_ok: bool = m.attr_data("fid") == m0.attr_data("fid")
	ok(uv_ok and at_ok and cr_ok and fid_ok, "(6) after the separate: UVs bit-exact %s, labels on the doubled verts from their sources %s, creases per source edge %s (%d -> %d edges), face channel %s" % [uv_ok, at_ok, cr_ok, el0.size(), el.size(), fid_ok])
	# ---- 3 separate then join_weld = the mesh before
	var js := KMeshSelect.new(m, KMeshSelect.VERT)   # a vert of the patch and one of the rest of cube A: those two parts join
	js.verts[(m.faces[pf[0]] as PackedInt32Array)[0]] = true
	js.verts[0] = true
	var jr := KMeshSepJoin.join(m, js, true)
	ok(m.verts == m0.verts and same_faces(m.faces, m0.faces) and int(jr.get("welded", -1)) == want_dup.size(), "(3) separate then join_weld: verts %s and faces %s as before, %d welded (doubled %d)" % [m.verts == m0.verts, same_faces(m.faces, m0.faces), int(jr.get("welded", -1)), want_dup.size()])
	ok(chans_equal(m0, m) and KMeshSepJoin.parts(m).size() == 2, "(6) after join_weld every channel equals the original; %d parts" % KMeshSepJoin.parts(m).size())
	# ---- 2 loose parts, 3 join then separate
	m = two_cubes()
	var jj := KMeshSepJoin.join(m)
	ok(int(jj.get("parts", 0)) == 2 and KMeshSepJoin.parts(m).size() == 1 and KMeshBoolean.components(m).size() == 2 and m.verts == m0.verts and same_faces(m.faces, m0.faces),
		"(2) join (nothing selected): %d part of %d components, nothing moved" % [KMeshSepJoin.parts(m).size(), KMeshBoolean.components(m).size()])
	var bf := PackedInt32Array()
	for fi in range(96, 192):
		bf.append(fi)
	KMeshSepJoin.separate(m, bf)
	ok(m.verts == m0.verts and same_faces(m.faces, m0.faces) and KMeshSepJoin.parts(m).size() == 2, "(3) join then separate cube B: verts bit-exact %s, faces %s, %d parts" % [m.verts == m0.verts, same_faces(m.faces, m0.faces), KMeshSepJoin.parts(m).size()])
	KMeshSepJoin.join(m)
	var nl := KMeshSepJoin.separate_loose(m)
	ok(nl == 2 and KMeshSepJoin.parts(m).size() == KMeshBoolean.components(m).size(), "(2) separate by loose parts: %d parts == %d components" % [KMeshSepJoin.parts(m).size(), KMeshBoolean.components(m).size()])
	KMeshSepJoin.separate(m, patch(m))
	KMeshSepJoin.join(m)
	KMeshSepJoin.separate_loose(m)
	ok(KMeshSepJoin.parts(m).size() == 3 and KMeshBoolean.components(m).size() == 3, "(2) after a patch separate, a join and loose parts: %d parts == %d components" % [KMeshSepJoin.parts(m).size(), KMeshBoolean.components(m).size()])
	# ---- 4 origin
	m = two_cubes()
	var lo := [INF, INF, INF]
	var hi := [-INF, -INF, -INF]
	for p in m.verts:
		for k in 3:
			lo[k] = minf(lo[k], float(p[k]))
			hi[k] = maxf(hi[k], float(p[k]))
	var o := KMeshSepJoin.origin_for(m, "bottom")
	m.origin = o
	ok(absf(o.y - lo[1]) <= 1e-7 and absf(o.x - (lo[0] + hi[0]) / 2.0) <= 1e-7 and absf(o.z - (lo[2] + hi[2]) / 2.0) <= 1e-7,
		"(4) origin to the bottom centre: %s; lowest y %.7f, box centre x %.7f z %.7f" % [o, lo[1], (lo[0] + hi[0]) / 2.0, (lo[2] + hi[2]) / 2.0])
	var g := KMeshSepJoin.origin_for(m, "geometry")
	ok(g.distance_to(Vector3((lo[0] + hi[0]) / 2.0, (lo[1] + hi[1]) / 2.0, (lo[2] + hi[2]) / 2.0)) <= 1e-7 and KMeshSepJoin.origin_for(m, "cursor", Vector3(0.3, -0.2, 7)) == Vector3(0.3, -0.2, 7) and m.verts == m0.verts,
		"(4) origin to the geometry centre %s, to the cursor = the cursor; no vertex moved" % g)
	# ---- 5 save / load
	KMeshSepJoin.separate_loose(m)
	KMeshSepJoin.join(m)
	m.origin = Vector3(0.1234567, -0.0000123, 3.75)
	var path := "user://sepjoin_test.kmesh"
	var err := m.save(path)
	var back := KMesh.load_file(path)
	ok(err == OK and back != null and back.origin == m.origin and back.attr_data("part") == m.attr_data("part") and KMeshSepJoin.parts(back).size() == 1, "(5) the origin survives save / load exactly: %s -> %s; part ids too (1 joined part)" % [m.origin, back.origin if back != null else "null"])
	ok(not KMesh.new().from_arrays(m.verts, m.faces).to_dict().has("origin"), "(5) a mesh with origin 0 writes no origin")
	var dd := m.to_dict()
	dd["origin"] = [1, "x"]
	ok(KMesh.new().from_dict(dd) == null and KMesh.last_error.contains("origin"), "(5) a damaged origin is refused: '%s'" % KMesh.last_error)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# ---- 7 the model preview
	var lines := MeshTools.TOOLS.filter(func(t): return String(t["do"]).begins_with("op:separate") or String(t["do"]).begins_with("op:join") or String(t["do"]).begins_with("op:origin_"))
	ok(lines.size() == 7, "(7) %d B17 lines in the S box (expect 7)" % lines.size())
	var mn: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(mn)
	for i in 4:
		await process_frame
	mn._kmesh_edit_start()
	await process_frame
	var ui = mn.kmed
	ui.add_prim("cube")
	await process_frame
	ui.pivot.cursor = ui.view.global_transform * Vector3(0.1, 0.2, 0.3)
	for name in ["separate", "join", "separate", "join_weld", "separate_loose", "origin_geometry", "origin_cursor", "origin_bottom"]:
		if name == "separate":
			ui.sel.mode = KMeshSelect.FACE
			ui.sel.faces.clear()
			for fi in [0, 1, 2]:
				ui.sel.faces[fi] = true
		var bv: PackedVector3Array = ui.mesh.verts.duplicate()
		var bfl: Array = ui.mesh.faces.duplicate()
		var ba: Dictionary = ui.mesh.attr_snapshot()
		var bo: Vector3 = ui.mesh.origin
		var n0: int = ui.undo.steps.size()
		var said := MeshTools.op(name, mn)
		var n1: int = ui.undo.steps.size()
		ui.undo.undo()
		var back_ok: bool = ui.mesh.verts == bv and same_faces(ui.mesh.faces, bfl) and ui.mesh.origin == bo and ui.mesh.attrs.size() == ba.size()
		for k in ba:
			back_ok = back_ok and ui.mesh.attrs.has(k) and ui.mesh.attrs[k]["data"] == ba[k]["data"]
		ui.undo.redo()
		ui._after_topo()
		ok(n1 == n0 + 1 and back_ok, "(7) %s: %d undo step (bar 1), Ctrl+Z gives it all back %s; said '%s'" % [name, n1 - n0, back_ok, said])
		if name == "origin_cursor":
			ok(ui.mesh.origin.distance_to(Vector3(0.1, 0.2, 0.3)) < 1e-6, "(7) origin to the cursor: %s in the mesh (the cursor was put at 0.1, 0.2, 0.3)" % ui.mesh.origin)
	ui.stop()
	mn.queue_free()
	await process_frame
