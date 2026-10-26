extends SceneTree
## godot --headless --path . -s tests/cad_test.gd     (CAD kernel pilot: native/cad KineCAD = Open CASCADE, door scripts/kcad.gd)
## A 2x1x1 box minus a through hole (r 0.25), every edge filleted 0.1, checked against closed-form volumes.
## Bars, written before measuring:
##   1 DLL: KCad.available() (reported) or every kernel bar says SKIP (the suite still PASSes without the DLL)
##   2 NO DLL: the door answers cleanly: available() false, builders return 0, tessellate() null, last_error() names the build note
##   3 PRIMITIVES: box / cylinder / sphere kernel volumes within 1e-6 relative of closed form
##   4 BOOLEANS: union / intersect of two overlapping boxes, kernel volume within 1e-6 (inclusion-exclusion)
##   5 PART: (box 2x1x1 - cylinder r.25) filleted 0.1: kernel volume within 1e-4 of the closed form (rounded box + two rim fillets)
##   6 MESH: tessellate(deflection 0.002): mesh volume (signed tetrahedra, Godot clockwise winding: outward = positive) within 1% of the closed form, normals unit length
##     and pointing out (dot with the face normal > 0 on 99% of corners)
##   7 WATERTIGHT: welded at 1e-5, every directed edge appears once and its reverse once (no holes, no flipped triangles)
##   8 STEP: export, import: volume equal to 1e-6 relative; the file starts with ISO-10303-21 and holds a MANIFOLD_SOLID_BREP
##   9 SHELL: a 1 m cube hollowed 0.1 open at +Z has volume 1 - 0.8*0.8*0.9; hollowed closed 1 - 0.8^3
##  10 ERRORS: bad ids, a missing STEP file and a too-big fillet return 0 / false with a non-empty last_error() and no crash
##  11 TIMING: every op's time is printed (ms); BAR: the whole part (build + fillet + tessellate) in under 2 s
const KCad := preload("res://scripts/kcad.gd")
const R_HOLE := 0.25
const R_FIL := 0.1
var fails := 0
var skips := 0
var times := []


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func skip(what: String) -> void:
	print("SKIP " + what + " (no KineCAD: the DLL is missing)")
	skips += 1


func tm(label: String, t0: int) -> void:
	times.append([label, (Time.get_ticks_usec() - t0) / 1000.0])


func near(a: float, b: float, rel: float) -> bool:
	return absf(a - b) <= rel * absf(b)


## closed form: Minkowski sum of a box with a ball gives the rounded box; the rim fillets come from Pappus (centroid of the removed corner)
static func part_volume() -> float:
	var r := R_FIL
	var x := 2.0 - 2 * r
	var y := 1.0 - 2 * r
	var z := 1.0 - 2 * r
	var rounded := x * y * z + 2 * (x * y + y * z + z * x) * r + PI * r * r * (x + y + z) + 4.0 / 3.0 * PI * r * r * r
	var hole := PI * R_HOLE * R_HOLE * 1.0
	var a := r * r * (1.0 - PI / 4.0)
	var xbar := r * (5.0 / 6.0 - PI / 4.0) / (1.0 - PI / 4.0)
	var rims := 2.0 * a * TAU * (R_HOLE + xbar)
	return rounded - hole - rims


static func mesh_volume(m: ArrayMesh) -> float:
	var a := m.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var s := 0.0
	for t in ix.size() / 3:
		var p := v[ix[t * 3]]
		var q := v[ix[t * 3 + 1]]
		var r := v[ix[t * 3 + 2]]
		s += p.dot(q.cross(r)) / 6.0
	return -s   # Godot's front face is clockwise: an outward mesh has a negative signed volume in the right-handed formula


## [holes (edges without exactly one reverse), welded verts, degenerate-dropped triangles]
static func watertight(m: ArrayMesh) -> Array:
	var a := m.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var key := {}
	var wid := PackedInt32Array()
	wid.resize(v.size())
	for i in v.size():
		var k := Vector3i((v[i] * 100000.0).round())
		if not key.has(k):
			key[k] = key.size()
		wid[i] = key[k]
	var edges := {}
	var dropped := 0
	for t in ix.size() / 3:
		var a0 := wid[ix[t * 3]]
		var a1 := wid[ix[t * 3 + 1]]
		var a2 := wid[ix[t * 3 + 2]]
		if a0 == a1 or a1 == a2 or a0 == a2:
			dropped += 1
			continue
		for e in [[a0, a1], [a1, a2], [a2, a0]]:
			var k2: int = e[0] * 1000003 + e[1]
			edges[k2] = int(edges.get(k2, 0)) + 1
	var bad := 0
	for k2 in edges:
		var u: int = k2 / 1000003
		var w: int = k2 % 1000003
		if edges[k2] != 1 or int(edges.get(w * 1000003 + u, 0)) != 1:
			bad += 1
	return [bad, key.size(), dropped]


func _init() -> void:
	var have := KCad.available()
	print("KineCAD: ", KCad.version())
	if have:
		ok(true, "1 DLL: loaded, " + KCad.version())
	else:
		print("SKIP 1 DLL: not available (" + KCad.last_error() + ")")
		skips += 1
		ok(KCad.box(1, 1, 1) == 0 and KCad.cylinder(1, 1) == 0 and KCad.union(1, 2) == 0 and KCad.tessellate(1) == null
				and KCad.volume(1) < 0.0 and not KCad.export_step(1, "user://x.step") and KCad.live_count() == 0,
				"2 NO DLL: builders return 0, tessellate null, volume < 0, export false")
		ok("native/CAD_BUILD.md" in KCad.last_error(), "2 NO DLL: last_error names the build note: " + KCad.last_error())
		for b in ["3 PRIMITIVES", "4 BOOLEANS", "5 PART", "6 MESH", "7 WATERTIGHT", "8 STEP", "9 SHELL", "10 ERRORS", "11 TIMING"]:
			skip(b)
		finish()
		return
	KCad.release_all()

	# 3 primitives
	var t0 := Time.get_ticks_usec()
	var bx := KCad.box(2, 1, 1)
	tm("box", t0)
	t0 = Time.get_ticks_usec()
	var cy := KCad.cylinder(R_HOLE, 1.4)
	tm("cylinder", t0)
	t0 = Time.get_ticks_usec()
	var sp := KCad.sphere(0.5)
	tm("sphere", t0)
	ok(bx > 0 and cy > 0 and sp > 0, "3 PRIMITIVES: ids %d %d %d" % [bx, cy, sp])
	ok(near(KCad.volume(bx), 2.0, 1e-6) and near(KCad.volume(cy), PI * R_HOLE * R_HOLE * 1.4, 1e-6) and near(KCad.volume(sp), 4.0 / 3.0 * PI * 0.125, 1e-6),
			"3 PRIMITIVES: volumes box %.6f cyl %.6f sphere %.6f" % [KCad.volume(bx), KCad.volume(cy), KCad.volume(sp)])
	ok(KCad.face_count(bx) == 6 and KCad.edge_count(bx) == 12, "3 PRIMITIVES: box has 6 faces, 12 edges")

	# 4 booleans: two 1x1x1 cubes offset by 0.5 along x: union 1.5, intersection 0.5
	var c1 := KCad.box(1, 1, 1)
	var c2 := KCad.translate(KCad.box(1, 1, 1), Vector3(0.5, 0, 0))
	t0 = Time.get_ticks_usec()
	var un := KCad.union(c1, c2)
	tm("union", t0)
	t0 = Time.get_ticks_usec()
	var it := KCad.intersect(c1, c2)
	tm("intersect", t0)
	ok(un > 0 and it > 0 and near(KCad.volume(un), 1.5, 1e-6) and near(KCad.volume(it), 0.5, 1e-6),
			"4 BOOLEANS: union %.6f (1.5) intersect %.6f (0.5)" % [KCad.volume(un), KCad.volume(it)])

	# 5 the part
	t0 = Time.get_ticks_usec()
	var holed := KCad.cut(bx, cy)
	tm("cut", t0)
	t0 = Time.get_ticks_usec()
	var part := KCad.fillet_all(holed, R_FIL)
	tm("fillet_all", t0)
	var want := part_volume()
	ok(holed > 0 and part > 0, "5 PART: cut + fillet made shapes (%s)" % KCad.last_error())
	var kv := KCad.volume(part)
	ok(near(kv, want, 1e-4), "5 PART: kernel volume %.6f vs closed form %.6f (%.4f%%)" % [kv, want, absf(kv - want) / want * 100.0])
	print("     faces %d, edges %d, area %.5f" % [KCad.face_count(part), KCad.edge_count(part), KCad.area(part)])

	# 6 mesh
	t0 = Time.get_ticks_usec()
	var mesh := KCad.tessellate(part, 0.002, 0.3)
	tm("tessellate(0.002)", t0)
	ok(mesh != null and mesh.get_surface_count() == 1, "6 MESH: an ArrayMesh with one surface")
	if mesh != null:
		var arr := mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var mv := mesh_volume(mesh)
		ok(absf(mv - want) <= 0.01 * want, "6 MESH: mesh volume %.6f vs %.6f (%.3f%%), %d verts, %d tris" % [mv, want, absf(mv - want) / want * 100.0, v.size(), ix.size() / 3])
		var unit := true
		for i in n.size():
			if absf(n[i].length() - 1.0) > 1e-3:
				unit = false
				break
		ok(unit and n.size() == v.size(), "6 MESH: one unit normal per vertex")
		var good := 0
		var all := 0
		for t in ix.size() / 3:
			var p := v[ix[t * 3]]
			var fn := (v[ix[t * 3 + 2]] - p).cross(v[ix[t * 3 + 1]] - p)   # clockwise winding: the outward normal is the reversed cross
			if fn.length() < 1e-12:
				continue
			fn = fn.normalized()
			for k in 3:
				all += 1
				if n[ix[t * 3 + k]].dot(fn) > 0.0:
					good += 1
		ok(all > 0 and good >= int(all * 0.99), "6 MESH: normals agree with the winding on %d of %d corners" % [good, all])
		var w := watertight(mesh)
		ok(w[0] == 0, "7 WATERTIGHT: %d bad edges (welded verts %d, degenerate triangles dropped %d)" % [w[0], w[1], w[2]])
		t0 = Time.get_ticks_usec()
		var fine := KCad.tessellate(part, 0.0005, 0.2)
		tm("tessellate(0.0005)", t0)
		ok(fine != null and absf(mesh_volume(fine) - want) <= absf(mv - want) + 1e-6, "6 MESH: a finer deflection is not worse")

	# 8 STEP
	var path := "user://cad_test_part.step"
	t0 = Time.get_ticks_usec()
	var wrote := KCad.export_step(part, path)
	tm("export_step", t0)
	ok(wrote and FileAccess.file_exists(path), "8 STEP: exported (%s)" % KCad.last_error())
	t0 = Time.get_ticks_usec()
	var back := KCad.import_step(path)
	tm("import_step", t0)
	ok(back > 0 and near(KCad.volume(back), kv, 1e-6), "8 STEP: re-imported volume %.6f vs %.6f" % [KCad.volume(back), kv])
	var txt := FileAccess.get_file_as_string(path)
	ok(txt.begins_with("ISO-10303-21") and "MANIFOLD_SOLID_BREP" in txt, "8 STEP: a real ISO-10303-21 file with a MANIFOLD_SOLID_BREP (%d bytes)" % txt.length())
	print("     face count after STEP round trip: %d (was %d)" % [KCad.face_count(back), KCad.face_count(part)])

	# 9 shell
	var cube := KCad.box(1, 1, 1)
	t0 = Time.get_ticks_usec()
	var open_cup := KCad.shell(cube, 0.1, Vector3(0, 0, 1))
	tm("shell(open +Z)", t0)
	t0 = Time.get_ticks_usec()
	var closed := KCad.shell(cube, 0.1)
	tm("shell(closed)", t0)
	ok(open_cup > 0 and near(KCad.volume(open_cup), 1.0 - 0.8 * 0.8 * 0.9, 1e-4), "9 SHELL: open cup %.6f vs %.6f (%s)" % [KCad.volume(open_cup), 1.0 - 0.8 * 0.8 * 0.9, KCad.last_error()])
	ok(closed > 0 and near(KCad.volume(closed), 1.0 - 0.512, 1e-4), "9 SHELL: closed hollow %.6f vs %.6f" % [KCad.volume(closed), 1.0 - 0.512])

	# 10 errors
	ok(KCad.cut(99999, bx) == 0 and KCad.last_error() != "", "10 ERRORS: bad id -> 0 + message (%s)" % KCad.last_error())
	ok(KCad.import_step("user://no_such_file.step") == 0 and KCad.last_error() != "", "10 ERRORS: missing STEP -> 0 + message (%s)" % KCad.last_error())
	var gpath := "user://cad_test_garbage.step"
	var gf := FileAccess.open(gpath, FileAccess.WRITE)
	gf.store_string("this is not a step file
at all")
	gf.close()
	ok(KCad.import_step(gpath) == 0 and KCad.last_error() != "", "10 ERRORS: a garbage file -> 0 + message (%s)" % KCad.last_error())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gpath))
	var tiny := KCad.box(0.1, 0.1, 0.1)
	var big := KCad.fillet_all(tiny, 0.5)
	ok(big == 0 and KCad.last_error() != "", "10 ERRORS: fillet bigger than the part -> 0 + message (%s)" % KCad.last_error())
	ok(KCad.tessellate(424242) == null and KCad.volume(424242) < 0.0, "10 ERRORS: tessellate / volume of a bad id are null / negative")

	# 11 timing
	print("op\tms")
	var total := 0.0
	for e in times:
		print("%s\t%.2f" % [e[0], e[1]])
	for lbl in ["box", "cut", "fillet_all", "tessellate(0.002)"]:
		for e in times:
			if e[0] == lbl:
				total += e[1]
	ok(total < 2000.0, "11 TIMING: build + fillet + tessellate %.1f ms (< 2000)" % total)

	KCad.release_all()
	ok(KCad.live_count() == 0, "release_all leaves no live shapes")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	finish()


func finish() -> void:
	print("cad: %d fail, %d skip" % [fails, skips])
	print("PASS" if fails == 0 else "FAIL")
	quit(1 if fails > 0 else 0)
