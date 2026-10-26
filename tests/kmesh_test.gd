## godot --headless --path . -s tests/kmesh_test.gd     (ROADMAP_400 A01: KMesh, the editable mesh core)
## Bars, stated before measuring:
##   1 cube from 8 verts / 6 quads: 12 edges, V-E+F = 2, closed, manifold, every vertex has exactly 3 neighbours
##   2 open 10x10-quad grid: 40 boundary edges, 220 edges, V-E+F = 1, not closed, still manifold
##   3 the mannequin mesh -> KMesh -> ArrayMesh: same triangle count and every triangle corner within 1e-5 m of the
##     original; the weld joined verts (KMesh verts < ArrayMesh verts)
##   4 a cube face normal points outward: dot(normal, face_center - cube_center) > 0 for all 6 faces, and the vertex
##     normals point outward too (dot with the vertex offset > 0)
##   5 a subdivided UV sphere of >= 50k triangles builds (from_arrays) in < 2 s headless; its Euler characteristic is 2
##   also: an edge shared by 3 faces is reported non-manifold (the check can say no)
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func cube() -> KMesh:
	var v := PackedVector3Array()
	for i in 8:
		v.append(Vector3(1 if i & 1 else -1, 1 if i & 2 else -1, 1 if i & 4 else -1))
	# outward counter-clockwise quads
	var f: Array = [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]
	return KMesh.new().from_arrays(v, f)


func _init() -> void:
	# bar 1
	var c := cube()
	var all3 := true
	for i in 8:
		if c.vert_neighbors(i).size() != 3:
			all3 = false
	print("cube: V=%d E=%d F=%d euler=%d" % [c.vert_count(), c.edge_count(), c.face_count(), c.euler()])
	ok(c.edge_count() == 12 and c.euler() == 2 and c.is_closed() and c.is_manifold() and all3, "bar 1: cube 12 edges, euler 2, closed, manifold, 3 neighbours each")
	# bar 2
	var gv := PackedVector3Array()
	for y in 11:
		for x in 11:
			gv.append(Vector3(x, 0, y))
	var gf: Array = []
	for y in 10:
		for x in 10:
			gf.append([y * 11 + x, (y + 1) * 11 + x, (y + 1) * 11 + x + 1, y * 11 + x + 1])
	var g := KMesh.new().from_arrays(gv, gf)
	print("grid: E=%d boundary=%d euler=%d closed=%s manifold=%s" % [g.edge_count(), g.boundary_edge_count(), g.euler(), g.is_closed(), g.is_manifold()])
	ok(g.boundary_edge_count() == 40 and g.edge_count() == 220 and g.euler() == 1 and not g.is_closed() and g.is_manifold(), "bar 2: grid 40 boundary edges, 220 edges, euler 1, manifold")
	ok(g.is_boundary_edge(0, 1) and not g.is_boundary_edge(12, 13), "bar 2b: is_boundary_edge true on the rim, false inside")
	var nm := KMesh.new().from_arrays(PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1)]), [[0, 1, 2], [1, 0, 3], [1, 0, 4]])
	ok(not nm.is_manifold(), "control: an edge shared by 3 faces is non-manifold")
	# bar 3
	var root := Node3D.new()
	var mq := Overlays.mannequin(root, StandardMaterial3D.new())
	var mi: MeshInstance3D = (mq[0] as Node3D).find_children("*", "MeshInstance3D", true, false)[0]
	var src: ArrayMesh = mi.mesh
	var sa := src.surface_get_arrays(0)
	var sp: PackedVector3Array = sa[Mesh.ARRAY_VERTEX]
	var si: PackedInt32Array = sa[Mesh.ARRAY_INDEX]
	var km := KMesh.new().from_array_mesh(src, 0)
	var back := km.to_array_mesh(true)
	var ba := back.surface_get_arrays(0)
	var bp: PackedVector3Array = ba[Mesh.ARRAY_VERTEX]
	var bi: PackedInt32Array = ba[Mesh.ARRAY_INDEX]
	var worst := 0.0
	if bi.size() == si.size():
		for k in si.size():
			worst = maxf(worst, sp[si[k]].distance_to(bp[bi[k]]))
	print("mannequin: %d tris -> %d tris, verts %d -> %d, worst corner error %f m, manifold=%s, closed=%s" % [si.size() / 3, bi.size() / 3, sp.size(), km.vert_count(), worst, km.is_manifold(), km.is_closed()])
	ok(bi.size() == si.size() and worst <= 1e-5 and km.vert_count() < sp.size(), "bar 3: mannequin round trip same triangle count, corners within 1e-5, weld joined verts")
	# bar 4
	var out := true
	for fi in 6:
		if c.face_normals[fi].dot(c.face_center(fi)) <= 0.0:
			out = false
	for v in 8:
		if c.vert_normals[v].dot(c.verts[v]) <= 0.0:
			out = false
	ok(out, "bar 4: cube face and vertex normals point outward")
	# bar 5: UV sphere, n segments around, n/2 rings
	var n := 232
	var rings := n / 2
	var sv := PackedVector3Array()
	sv.append(Vector3(0, 1, 0))
	for r in range(1, rings):
		var th := PI * r / rings
		for s in n:
			var ph := TAU * s / n
			sv.append(Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph)))
	sv.append(Vector3(0, -1, 0))
	var sf: Array = []
	for s in n:
		sf.append(PackedInt32Array([0, 1 + (s + 1) % n, 1 + s]))
	for r in range(0, rings - 2):
		for s in n:
			var a := 1 + r * n + s
			var b := 1 + r * n + (s + 1) % n
			var a2 := a + n
			var b2 := b + n
			sf.append(PackedInt32Array([a, b, b2]))
			sf.append(PackedInt32Array([a, b2, a2]))
	var last := sv.size() - 1
	for s in n:
		sf.append(PackedInt32Array([last, 1 + (rings - 2) * n + s, 1 + (rings - 2) * n + (s + 1) % n]))
	var t0 := Time.get_ticks_usec()
	var sph := KMesh.new().from_arrays(sv, sf)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("sphere: %d tris, built in %.0f ms, euler=%d, closed=%s" % [sph.triangle_count(), ms, sph.euler(), sph.is_closed()])
	ok(sph.triangle_count() >= 50000 and ms < 2000.0 and sph.euler() == 2 and sph.is_closed(), "bar 5: sphere >= 50k tris builds < 2 s, euler 2, closed")
	root.free()
	print("kmesh_test: %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(1 if fails else 0)
