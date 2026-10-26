## godot --headless --path . -s tests/meshsel_test.gd     (ROADMAP_400 A02 selection + A04 symmetry map)
## Bars, stated before measuring:
##   1 10x10 quad grid, interior edge: the loop is exactly 10 edges straight across (ends on the rim);
##     the ring is the parallel edges across the column of 10 quads = 11 edges (n quads -> n + 1 edges; the brief
##     said 10, but 11 vertex rows each own one parallel edge, so 11 is the geometric count and what is tested)
##   2 UV sphere (16 segments, 8 rings, pole triangles): equator loop = 16 edges and closed; a meridian loop = 8 edges,
##     reaches both poles and stops there (each pole has exactly 1 selected edge)
##   3 grow from one face: vertex-adjacent 1 -> 9 -> shrink 1; edge-adjacent 1 -> 5 -> shrink 1 (both implemented, both tested)
##   4 two separate cubes in one mesh: select linked from one face = its 6 faces, none of the other cube's
##   5 symmetry_map: cube centred on x=0 and a mirrored grid: every vert paired, partner of partner == self;
##     mirror_selection of a left face = the right face; mannequin: % paired reported, time < 1 s;
##     a 100k-vert mirrored grid maps in < 2 s
##   also: mode conversion, invert, by-normal (cube tops within 10 / 100 degrees), a non-mirrored vert gets -1
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func cube_at(cx: float, base: int, vs: PackedVector3Array, fs: Array) -> void:
	for i in 8:
		vs.append(Vector3(cx + (1 if i & 1 else -1), 1 if i & 2 else -1, 1 if i & 4 else -1))
	for q in [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]:
		fs.append([base + q[0], base + q[1], base + q[2], base + q[3]])


func grid(nx: int, ny: int, x0: float) -> KMesh:
	var gv := PackedVector3Array()
	for y in ny + 1:
		for x in nx + 1:
			gv.append(Vector3(x0 + x, 0, y))
	var gf: Array = []
	for y in ny:
		for x in nx:
			gf.append([y * (nx + 1) + x, (y + 1) * (nx + 1) + x, (y + 1) * (nx + 1) + x + 1, y * (nx + 1) + x + 1])
	return KMesh.new().from_arrays(gv, gf)


func sphere(n: int, rings: int) -> KMesh:
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
		sf.append([0, 1 + (s + 1) % n, 1 + s])
	for r in range(0, rings - 2):
		for s in n:
			var a := 1 + r * n + s
			var b := 1 + r * n + (s + 1) % n
			sf.append([a, b, b + n, a + n])
	var last := sv.size() - 1
	for s in n:
		sf.append([last, 1 + (rings - 2) * n + s, 1 + (rings - 2) * n + (s + 1) % n])
	return KMesh.new().from_arrays(sv, sf)


func degree(sel: KMeshSelect, v: int) -> int:
	var d := 0
	for e in sel.edges:
		if e.x == v or e.y == v:
			d += 1
	return d


func _init() -> void:
	# bar 1
	var g := grid(10, 10, 0.0)
	var sel := KMeshSelect.new(g, KMeshSelect.EDGE)
	var ea := 5 * 11 + 4
	sel.select_loop(ea, ea + 1)
	var straight := true
	for e in sel.edges:
		if e.y - e.x != 1 or e.x / 11 != 5:
			straight = false
	print("grid loop: %d edges, straight=%s" % [sel.count(), straight])
	ok(sel.count() == 10 and straight, "bar 1: loop through an interior edge = 10 edges straight across")
	sel.select_ring(ea, ea + 1)
	var par := true
	for e in sel.edges:
		if e.y - e.x != 1 or e.x % 11 != 4:
			par = false
	print("grid ring: %d edges, all parallel in column 4 = %s" % [sel.count(), par])
	ok(sel.count() == 11 and par, "bar 1: ring = 11 parallel edges across the 10 quads of the column")
	var vloop := KMeshSelect.new(g, KMeshSelect.EDGE)
	vloop.select_loop(5 * 11 + 5, 6 * 11 + 5)
	ok(vloop.count() == 10, "bar 1b: the loop along the other direction is 10 too")
	# bar 2
	var n := 16
	var rings := 8
	var sp := sphere(n, rings)
	ok(sp.is_closed() and sp.is_manifold(), "bar 2 setup: test sphere closed and manifold")
	var ss := KMeshSelect.new(sp, KMeshSelect.EDGE)
	var eq0 := 1 + 3 * n
	ss.select_loop(eq0, eq0 + 1)
	var closed_ring := true
	for s in n:
		if not ss.edges.has(KMeshSelect.ekey(eq0 + s, eq0 + (s + 1) % n)):
			closed_ring = false
	ok(ss.count() == n and closed_ring, "bar 2: equator loop = %d edges (segments), closed (got %d)" % [n, ss.count()])
	ss.select_loop(eq0, eq0 + n)
	var south := sp.vert_count() - 1
	print("meridian: %d edges, pole degrees N=%d S=%d" % [ss.count(), degree(ss, 0), degree(ss, south)])
	ok(ss.count() == rings and degree(ss, 0) == 1 and degree(ss, south) == 1, "bar 2: meridian loop = %d edges, stops at both poles" % rings)
	ss.select_loop(0, 1)
	ok(degree(ss, 0) == 1, "bar 2b: a loop started on a pole edge ends at the pole (pole has %d loop edge)" % degree(ss, 0))
	# bar 3
	var fsel := KMeshSelect.new(g, KMeshSelect.FACE)
	var mid := 5 * 10 + 5
	fsel.faces[mid] = true
	fsel.grow()
	var g9 := fsel.count()
	var ring_ok := true
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if not fsel.faces.has(mid + dy * 10 + dx):
				ring_ok = false
	fsel.shrink()
	print("grow (vertex-adjacent): 1 -> %d, shrink -> %d" % [g9, fsel.count()])
	ok(g9 == 9 and ring_ok and fsel.count() == 1 and fsel.faces.has(mid), "bar 3: vertex-adjacent grow 1 -> 9 (the 3x3 block), shrink back to the same 1 face")
	fsel.grow(false)
	var g5 := fsel.count()
	fsel.shrink(false)
	print("grow (edge-adjacent): 1 -> %d, shrink -> %d" % [g5, fsel.count()])
	ok(g5 == 5 and fsel.count() == 1 and fsel.faces.has(mid), "bar 3: edge-adjacent grow 1 -> 5, shrink back to 1")
	# bar 4
	var cv := PackedVector3Array()
	var cf: Array = []
	cube_at(0.0, 0, cv, cf)
	cube_at(10.0, 8, cv, cf)
	var two := KMesh.new().from_arrays(cv, cf)
	var ts := KMeshSelect.new(two, KMeshSelect.FACE)
	ts.faces[8 + 2] = true  # a face of the second cube
	ts.select_linked()
	var only2 := true
	for fi in ts.faces:
		if fi < 6 or fi > 11:
			only2 = false
	print("two cubes: linked from one face = %d faces, all in cube B = %s" % [ts.count(), only2])
	ok(ts.count() == 6 and only2, "bar 4: select linked = the 6 faces of one cube only")
	# conversions, invert, by-normal
	var cs := KMeshSelect.new(two, KMeshSelect.FACE)
	cs.faces[0] = true
	cs.set_mode(KMeshSelect.VERT)
	var nvv := cs.count()
	cs.set_mode(KMeshSelect.FACE)
	var back1 := cs.count()
	cs.verts.clear()
	cs.set_mode(KMeshSelect.EDGE)
	cs.edges.clear()
	cs.set_mode(KMeshSelect.FACE)
	cs.faces[0] = true
	cs.set_mode(KMeshSelect.EDGE)
	var ne0 := cs.count()
	cs.set_mode(KMeshSelect.FACE)
	print("conversion: face -> %d verts -> %d face; face -> %d edges -> %d faces" % [nvv, back1, ne0, cs.count()])
	ok(nvv == 4 and back1 == 1 and ne0 == 4 and cs.count() == 1, "modes: face -> verts -> face, face -> edges -> face round trip (4 verts, 4 edges, 1 face)")
	cs.invert()
	ok(cs.count() == 11 and not cs.faces.has(0), "invert: 11 of 12 faces")
	cs.select_all()
	ok(cs.count() == 12, "select all = 12 faces")
	cs.select_none()
	ok(cs.count() == 0, "select none")
	cs.select_by_normal(Vector3.UP, 10.0)
	ok(cs.count() == 2 and cs.mode == KMeshSelect.FACE, "by normal: 2 cube tops within 10 degrees of up (one per cube)")
	cs.select_by_normal(Vector3.UP, 100.0)
	ok(cs.count() == 10, "by normal: within 100 degrees of up = tops + 4 sides each = 10")
	# bar 5
	var cube := KMesh.new().from_arrays(cv.slice(0, 8), [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]])
	var cm := cube.symmetry_map(0)
	ok(_involution(cm) and _all_paired(cm), "bar 5: cube centred on x=0: every vert paired, partner of partner == self")
	var mg := grid(10, 10, -5.0)
	var gm := mg.symmetry_map(0)
	var selfs := 0
	for v in gm.size():
		if gm[v] == v:
			selfs += 1
	print("mirrored grid: %d verts, %d on the plane" % [gm.size(), selfs])
	ok(_involution(gm) and _all_paired(gm) and selfs == 11, "bar 5: mirrored grid all paired, involution, 11 verts on the plane map to themselves")
	var ms := KMeshSelect.new(mg, KMeshSelect.FACE)
	ms.faces[5 * 10 + 1] = true
	ms.mirror_selection(gm)
	ok(ms.count() == 1 and ms.faces.has(5 * 10 + 8), "bar 5: mirror_selection of the left face = the right face")
	ms.faces[5 * 10 + 1] = true
	ms.mirror_selection(gm, true)
	ok(ms.count() == 2, "bar 5: mirror_selection(add) keeps both sides")
	var skew := grid(10, 10, -5.0)
	skew.verts[3] = skew.verts[3] + Vector3(0.01, 0, 0)
	var sk := skew.symmetry_map(0)
	ok(sk[3] == -1 and sk[7] == -1, "bar 5b: a vert moved 1 cm off its mirror loses its partner (-1), and the map stays mutual")
	ok(_involution(sk), "bar 5b: the skewed map is still an involution on paired verts")
	var big := grid(316, 316, -158.0)
	var t0 := Time.get_ticks_usec()
	var bm := big.symmetry_map(0)
	var bms := (Time.get_ticks_usec() - t0) / 1000.0
	print("100k grid: %d verts, symmetry_map %.0f ms" % [big.vert_count(), bms])
	ok(big.vert_count() >= 100000 and bms < 2000.0 and _all_paired(bm), "bar 5: %d-vert mirrored grid maps in %.0f ms (< 2000)" % [big.vert_count(), bms])
	var root := Node3D.new()
	var mq := Overlays.mannequin(root, StandardMaterial3D.new())
	var mi: MeshInstance3D = (mq[0] as Node3D).find_children("*", "MeshInstance3D", true, false)[0]
	var km := KMesh.new().from_array_mesh(mi.mesh, 0)
	t0 = Time.get_ticks_usec()
	var mm := km.symmetry_map(0)
	var mt := (Time.get_ticks_usec() - t0) / 1000.0
	var paired := 0
	for v in mm.size():
		if mm[v] != -1:
			paired += 1
	print("mannequin: %d verts, %d paired = %.1f%%, symmetry_map %.1f ms" % [km.vert_count(), paired, 100.0 * paired / maxi(1, mm.size()), mt])
	ok(mt < 1000.0 and _involution(mm), "bar 5: mannequin map < 1 s (%.1f ms) and an involution" % mt)
	root.free()
	print("meshsel_test: %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(1 if fails else 0)


func _involution(m: PackedInt32Array) -> bool:
	for v in m.size():
		if m[v] != -1 and m[m[v]] != v:
			return false
	return true


func _all_paired(m: PackedInt32Array) -> bool:
	for v in m.size():
		if m[v] == -1:
			return false
	return true
