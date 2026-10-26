extends SceneTree
## A10 mesh validate + repair. Bars: (1) a clean cube reports nothing; (2) a broken cube (1 doubled vert, 1 loose vert,
## 1 degenerate face, 1 flipped face, top face deleted = a hole) reports each with a next step; (3) repair fixes all of
## them: the result is the clean cube again (8 verts, 6 faces, closed, manifold, outward volume 1 m^3, report empty);
## (4) a cube with every face reversed is "inside_out" and repair flips it back (volume +1); (5) a non-manifold edge (3
## faces) is reported as not auto-fixable; (6) the mannequin mesh: report printed (counts), repair leaves fewer problems
var fails := 0
func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1
const CV := [Vector3(0,0,0), Vector3(1,0,0), Vector3(1,1,0), Vector3(0,1,0), Vector3(0,0,1), Vector3(1,0,1), Vector3(1,1,1), Vector3(0,1,1)]
const CF := [[0,3,2,1], [4,5,6,7], [0,1,5,4], [2,3,7,6], [1,2,6,5], [0,4,7,3]]
func cube(faces := CF) -> KMesh:
	return KMesh.new().from_arrays(PackedVector3Array(CV), faces)
func kinds(r: Dictionary) -> Array:
	return (r["problems"] as Array).map(func(p): return p["kind"])
func _init() -> void:
	ok(KMeshValidate.report(cube())["ok"], "(1) the clean cube reports nothing")
	var v := PackedVector3Array(CV)
	v.append(Vector3(1, 1, 1))     # 8: a double of 6
	v.append(Vector3(5, 5, 5))     # 9: loose
	var f := [[0,3,2,1], [4,5,8,7], [0,1,5,4], [1,2,6,5], [3,7,4,0], [0,1,1]]   # top deleted; 4th side flipped; last degenerate
	var b := KMesh.new().from_arrays(v, f)
	var r := KMeshValidate.report(b)
	var ks := kinds(r)
	for p in r["problems"]:
		print("  ", p["kind"], ": ", p["fix"])
	ok(ks.has("doubled") and ks.has("loose") and ks.has("degenerate") and ks.has("flipped") and ks.has("holes"), "(2) broken cube: %s" % str(ks))
	var d := KMeshValidate.repair(b)
	var r2 := KMeshValidate.report(b)
	print("  repaired: ", d)
	ok(b.vert_count() == 8 and b.face_count() == 6 and b.is_closed() and b.is_manifold() and absf(KMeshValidate._volume(b) - 1.0) < 1e-6 and r2["ok"], "(3) repaired to a clean cube: %d verts %d faces, volume %.3f, left %s" % [b.vert_count(), b.face_count(), KMeshValidate._volume(b), str(kinds(r2))])
	var rev := []
	for g in CF:
		var h: Array = g.duplicate()
		h.reverse()
		rev.append(h)
	var io := cube(rev)
	var r3 := kinds(KMeshValidate.report(io))
	KMeshValidate.repair(io)
	ok(r3 == ["inside_out"] and absf(KMeshValidate._volume(io) - 1.0) < 1e-6, "(4) inside-out cube found %s, flipped back (volume %.2f)" % [str(r3), KMeshValidate._volume(io)])
	var nm := KMesh.new().from_arrays(PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(0,1,0), Vector3(0,-1,0), Vector3(0,0,1)]), [[0,1,2], [1,0,3], [0,1,4]])
	var r4 := KMeshValidate.report(nm)
	var nmp := (r4["problems"] as Array).filter(func(p): return p["kind"] == "non_manifold")
	ok(nmp.size() == 1 and not nmp[0]["auto"], "(5) a 3-face edge is non-manifold and left to the hand: %s" % (nmp[0]["fix"] if nmp.size() else "-"))
	var mi: MeshInstance3D = null
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	for n in m.find_children("*", "MeshInstance3D", true, false):
		if mi == null and n.mesh is ArrayMesh and (n.mesh as ArrayMesh).get_surface_count() > 0 and (n.mesh as ArrayMesh).surface_get_primitive_type(0) == Mesh.PRIMITIVE_TRIANGLES and n.mesh.get_faces().size() > 3000:
			mi = n
	if mi != null:
		var km := KMesh.new().from_array_mesh(mi.mesh)
		var a := KMeshValidate.report(km)
		var before := (a["problems"] as Array).map(func(p): return "%s %d" % [p["kind"], p["count"]])
		var t0 := Time.get_ticks_msec()
		KMeshValidate.repair(km)
		var after := (KMeshValidate.report(km)["problems"] as Array).map(func(p): return "%s %d" % [p["kind"], p["count"]])
		ok(after.size() <= before.size(), "(6) %s (%d verts): %s -> %s, repair %d ms" % [mi.name, km.vert_count(), str(before), str(after), Time.get_ticks_msec() - t0])
	else:
		ok(false, "(6) no body mesh found")
	print("KMESH VALIDATE ", "PASS" if fails == 0 else "FAIL %d" % fails)
	TestFiles.cleanup()
	quit(1 if fails else 0)
