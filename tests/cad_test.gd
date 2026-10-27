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
##  PHASE 2 (sketch -> solid; closed forms only, bars written before measuring):
##  12 EXTRUDE: 2x1 rectangle (CCW and CW winding) by 3 -> volume 6 within 1e-9; symmetric (both) 6 and spans z -1.5..1.5; negative distance 6; tapered 1x1 by 1 at 10 deg -> frustum
##  13 REVOLVE: rectangle x 0..1, z 0..2 about Z, full turn -> pi*2; half turn -> pi
##  14 LOFT: squares 1 -> 0.5 over 2 m (ruled and smooth) -> frustum h/3*(A1+A2+sqrt(A1*A2)); three equal squares smooth -> box
##  15 SWEEP: circle r 0.1 along a 1 m line -> pi*0.01; along a quarter arc R 1 -> pi*r^2*(pi/2)
##  16 FILLET / CHAMFER on one picked edge: 2x1x1 box edge (len 2): volume - (1-pi/4)r^2*2 and - d^2/2*2, within 1e-6 relative
##  17 MIRROR doubles volume; linear x4 -> 4V, overlapping linear x4 -> 2.5V, circular x4 -> 4V
##  18 PICKING: faces()/edges() ids, outward unit normals, edge lengths sum 16, each edge borders 2 faces; bad edge id / solid extrude / open loop fail cleanly
##  19 MASS: volume / area / centre of mass / box inertia of a moved box
##  20 BLADE: sword-blade profile (lines + arc tip) extruded + edges filleted tessellates watertight, mesh volume within 1% of kernel; closed B-spline extrude volume = face area*h
##  21 STEP: the filleted blade round-trips with the same volume (1e-6)
##  22 RELEASE: ids made then released bring live_count back
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


## id of the face whose outward normal points along want (the first one found), 0 if none
func _face_with_normal(id: int, want: Vector3) -> int:
	for f in KCad.faces(id):
		if f["normal"].dot(want) > 0.999:
			return f["id"]
	return 0


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
		skip("12-22 PHASE 2 (sketch, extrude, revolve, loft, sweep, fillet/chamfer by edge, mirror, pattern, mass)")
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

	phase2()
	KCad.release_all()
	ok(KCad.live_count() == 0, "release_all leaves no live shapes")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	finish()


func nearest_edge(id: int, p: Vector3) -> int:
	var best := 0
	var bd := INF
	for e in KCad.edges(id):
		var d: float = (e["center"] as Vector3).distance_to(p)
		if d < bd:
			bd = d
			best = e["id"]
	return best


func zrange(m: ArrayMesh) -> Vector2:
	var v: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var r := Vector2(INF, -INF)
	for p in v:
		r.x = minf(r.x, p.z)
		r.y = maxf(r.y, p.z)
	return r


func frustum(h: float, a1: float, a2: float) -> float:
	return h / 3.0 * (a1 + a2 + sqrt(a1 * a2))


func square(s: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-s / 2, -s / 2), Vector2(s / 2, -s / 2), Vector2(s / 2, s / 2), Vector2(-s / 2, s / 2)])


func phase2() -> void:
	# 12 extrude
	var rect := PackedVector2Array([Vector2(-1, -0.5), Vector2(1, -0.5), Vector2(1, 0.5), Vector2(-1, 0.5)])
	var rect_cw := PackedVector2Array([Vector2(-1, -0.5), Vector2(-1, 0.5), Vector2(1, 0.5), Vector2(1, -0.5)])
	var f_ccw := KCad.sketch_face(KCad.polygon(rect))
	var f_cw := KCad.sketch_face(KCad.polygon(rect_cw))
	ok(f_ccw > 0 and f_cw > 0, "12 EXTRUDE: sketch faces built (%s)" % KCad.last_error())
	var e1 := KCad.extrude(f_ccw, 3.0)
	var e2 := KCad.extrude(f_cw, 3.0)
	ok(e1 > 0 and near(KCad.volume(e1), 6.0, 1e-9), "12 EXTRUDE: 2x1 by 3 (CCW) volume %.9f" % KCad.volume(e1))
	ok(e2 > 0 and near(KCad.volume(e2), 6.0, 1e-9), "12 EXTRUDE: 2x1 by 3 (CW winding) volume %.9f" % KCad.volume(e2))
	var e3 := KCad.extrude(f_ccw, 3.0, true)
	var m3 := KCad.tessellate(e3, 0.01)
	var zr := zrange(m3) if m3 != null else Vector2.ZERO
	ok(e3 > 0 and near(KCad.volume(e3), 6.0, 1e-9) and absf(zr.x + 1.5) < 1e-6 and absf(zr.y - 1.5) < 1e-6, "12 EXTRUDE: symmetric volume %.9f, z %.4f..%.4f" % [KCad.volume(e3), zr.x, zr.y])
	var e4 := KCad.extrude(f_ccw, -3.0)
	var m4 := KCad.tessellate(e4, 0.01)
	var zr4 := zrange(m4) if m4 != null else Vector2.ZERO
	ok(e4 > 0 and near(KCad.volume(e4), 6.0, 1e-9) and absf(zr4.x + 3.0) < 1e-6 and absf(zr4.y) < 1e-6, "12 EXTRUDE: negative distance goes against the normal: volume %.9f, z %.4f..%.4f" % [KCad.volume(e4), zr4.x, zr4.y])
	var sq := KCad.sketch_face(KCad.polygon(square(1.0)))
	var ang := deg_to_rad(10.0)
	var s_top := 1.0 - 2.0 * tan(ang) * 1.0
	var et := KCad.extrude(sq, 1.0, false, ang)
	ok(et > 0 and near(KCad.volume(et), frustum(1.0, 1.0, s_top * s_top), 1e-6), "12 EXTRUDE: taper 10 deg narrows: volume %.9f vs frustum %.9f (%s)" % [KCad.volume(et), frustum(1.0, 1.0, s_top * s_top), KCad.last_error()])
	var etb := KCad.extrude(sq, 1.0, true, ang)
	var s_end := 1.0 - 2.0 * tan(ang) * 0.5
	var want_b := 2.0 * frustum(0.5, 1.0, s_end * s_end)
	ok(etb > 0 and near(KCad.volume(etb), want_b, 1e-6), "12 EXTRUDE: taper both sides volume %.9f vs %.9f (%s)" % [KCad.volume(etb), want_b, KCad.last_error()])

	# 13 revolve
	var prof := KCad.sketch_face(KCad.polygon(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 2), Vector2(0, 2)])), Vector3.ZERO, Vector3.RIGHT, Vector3(0, -1, 0))
	var rv := KCad.revolve(prof, Vector3.ZERO, Vector3.BACK)
	ok(rv > 0 and near(KCad.volume(rv), PI * 2.0, 1e-9), "13 REVOLVE: full turn volume %.9f vs %.9f (%s)" % [KCad.volume(rv), PI * 2.0, KCad.last_error()])
	var rh := KCad.revolve(prof, Vector3.ZERO, Vector3.BACK, PI)
	ok(rh > 0 and near(KCad.volume(rh), PI, 1e-9), "13 REVOLVE: half turn volume %.9f vs %.9f" % [KCad.volume(rh), PI])

	# 14 loft
	var sq1 := KCad.sketch_face(KCad.polygon(square(1.0)))
	var sq2 := KCad.sketch_face(KCad.polygon(square(0.5)), Vector3(0, 0, 2))
	var sq3 := KCad.sketch_face(KCad.polygon(square(1.0)), Vector3(0, 0, 4))
	var want_f := frustum(2.0, 1.0, 0.25)
	var lr := KCad.loft(PackedInt32Array([sq1, sq2]), true)
	var ls := KCad.loft(PackedInt32Array([sq1, sq2]), false)
	ok(lr > 0 and near(KCad.volume(lr), want_f, 1e-9), "14 LOFT: ruled frustum %.9f vs %.9f (%s)" % [KCad.volume(lr), want_f, KCad.last_error()])
	ok(ls > 0 and near(KCad.volume(ls), want_f, 1e-9), "14 LOFT: smooth, two profiles %.9f vs %.9f (%s)" % [KCad.volume(ls), want_f, KCad.last_error()])
	var sq1b := KCad.sketch_face(KCad.polygon(square(1.0)), Vector3(0, 0, 2))
	var l3 := KCad.loft(PackedInt32Array([sq1, sq1b, sq3]), false)
	ok(l3 > 0 and near(KCad.volume(l3), 4.0, 1e-9), "14 LOFT: three equal squares smooth = box %.9f vs 4 (%s)" % [KCad.volume(l3), KCad.last_error()])

	# 15 sweep
	var circ := KCad.sketch_face([KCad.circle(Vector2.ZERO, 0.1)], Vector3.ZERO, Vector3.UP, Vector3.RIGHT)
	var line_path := KCad.path_wire(PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0)]))
	var sw := KCad.sweep(circ, line_path)
	ok(sw > 0 and near(KCad.volume(sw), PI * 0.01, 1e-9), "15 SWEEP: circle r .1 along 1 m: %.9f vs %.9f (%s)" % [KCad.volume(sw), PI * 0.01, KCad.last_error()])
	var arc_path := KCad.sketch_wire([KCad.arc(Vector2(0, 0), Vector2(sin(PI / 4), 1.0 - cos(PI / 4)), Vector2(1, 1))])
	var sw2 := KCad.sweep(circ, arc_path)
	var want_s := PI * 0.01 * (PI / 2.0)
	ok(sw2 > 0 and near(KCad.volume(sw2), want_s, 1e-6), "15 SWEEP: along a quarter arc R 1: %.9f vs %.9f (%s)" % [KCad.volume(sw2), want_s, KCad.last_error()])

	# 16 fillet / chamfer by picked edge
	var bx2 := KCad.box(2, 1, 1)
	var pick := nearest_edge(bx2, Vector3(0, 0.5, 0.5))
	var fe := KCad.fillet_edges(bx2, PackedInt32Array([pick]), 0.1)
	var want_fe := 2.0 - (1.0 - PI / 4.0) * 0.01 * 2.0
	ok(fe > 0 and near(KCad.volume(fe), want_fe, 1e-6), "16 FILLET: one edge r .1: %.9f vs %.9f (%s)" % [KCad.volume(fe), want_fe, KCad.last_error()])
	var ce := KCad.chamfer_edges(bx2, PackedInt32Array([pick]), 0.1)
	var want_ce := 2.0 - 0.01 / 2.0 * 2.0
	ok(ce > 0 and near(KCad.volume(ce), want_ce, 1e-6), "16 CHAMFER: one edge d .1: %.9f vs %.9f (%s)" % [KCad.volume(ce), want_ce, KCad.last_error()])
	ok(KCad.face_count(fe) == 7 and KCad.face_count(ce) == 7, "16 FILLET/CHAMFER: one extra face each (%d, %d)" % [KCad.face_count(fe), KCad.face_count(ce)])

	# 17 mirror and patterns
	var unit := KCad.translate(KCad.box(1, 1, 1), Vector3(1.5, 0, 0))
	var mj := KCad.mirror_join(unit, Vector3.ZERO, Vector3.RIGHT)
	ok(mj > 0 and near(KCad.volume(mj), 2.0, 1e-9), "17 MIRROR: part + mirror %.9f vs 2 (%s)" % [KCad.volume(mj), KCad.last_error()])
	var mc := KCad.mass_properties(mj).get("center", Vector3(9, 9, 9)) as Vector3
	ok(mc.length() < 1e-6, "17 MIRROR: the joined centre is on the mirror plane (%s)" % str(mc))
	var cube := KCad.box(1, 1, 1)
	var pl := KCad.pattern_linear(cube, Vector3(2, 0, 0), 4)
	ok(pl > 0 and near(KCad.volume(pl), 4.0, 1e-9), "17 PATTERN: linear x4 %.9f vs 4 (%s)" % [KCad.volume(pl), KCad.last_error()])
	var po := KCad.pattern_linear(cube, Vector3(0.5, 0, 0), 4)
	ok(po > 0 and near(KCad.volume(po), 2.5, 1e-9), "17 PATTERN: overlapping linear x4 %.9f vs 2.5" % KCad.volume(po))
	var peg := KCad.translate(KCad.box(0.2, 0.2, 0.2), Vector3(1, 0, 0))
	var pc := KCad.pattern_circular(peg, Vector3.ZERO, Vector3.BACK, 4)
	ok(pc > 0 and near(KCad.volume(pc), 4.0 * 0.008, 1e-9), "17 PATTERN: circular x4 %.9f vs %.9f" % [KCad.volume(pc), 4.0 * 0.008])
	var pc2 := KCad.pattern_circular(peg, Vector3.ZERO, Vector3.BACK, 3, PI)
	var cm := KCad.mass_properties(pc2).get("center", Vector3.ZERO) as Vector3
	ok(pc2 > 0 and near(KCad.volume(pc2), 3.0 * 0.008, 1e-9) and absf(cm.x) < 1e-6 and absf(cm.y - 1.0 / 3.0) < 1e-6, "17 PATTERN: circular x3 over 180 deg %.9f, centre %s (0, 1/3)" % [KCad.volume(pc2), str(cm)])

	# 18 picking data
	var fl := KCad.faces(bx2)
	var el := KCad.edges(bx2)
	var out_ok := fl.size() == 6
	var top_id := 0
	for f in fl:
		var n: Vector3 = f["normal"]
		var c: Vector3 = f["center"]
		if absf(n.length() - 1.0) > 1e-9 or n.dot(c) <= 0.0 or f["type"] != "plane":
			out_ok = false
		if n.dot(Vector3.BACK) > 0.99:
			top_id = f["id"]
	ok(out_ok and top_id > 0, "18 PICKING: 6 planar faces, unit normals pointing out of the box, a +Z face found")
	var tot := 0.0
	var two := true
	for e in el:
		tot += float(e["length"])
		if (e["faces"] as PackedInt32Array).size() != 2:
			two = false
	ok(el.size() == 12 and absf(tot - 16.0) < 1e-9 and two, "18 PICKING: 12 edges, total length %.6f vs 16, each borders 2 faces" % tot)
	ok(KCad.fillet_edges(bx2, PackedInt32Array([999]), 0.1) == 0 and KCad.last_error() != "", "18 PICKING: a bad edge id -> 0 + message (%s)" % KCad.last_error())
	ok(KCad.extrude(e1, 1.0) == 0 and KCad.last_error() != "", "18 PICKING: extruding a solid -> 0 + message (%s)" % KCad.last_error())
	ok(KCad.sketch_face([KCad.line(Vector2(0, 0), Vector2(1, 0)), KCad.line(Vector2(1, 0), Vector2(1, 1))]) == 0 and KCad.last_error() != "", "18 PICKING: an open loop is no face (%s)" % KCad.last_error())

	# 19 mass properties
	var mb := KCad.translate(KCad.box(2, 1, 1), Vector3(1, 2, 3))
	var mp := KCad.mass_properties(mb)
	var ctr: Vector3 = mp.get("center", Vector3.ZERO)
	var inertia: Basis = mp.get("inertia", Basis())
	ok(near(mp.get("volume", 0.0), 2.0, 1e-9) and near(mp.get("area", 0.0), 10.0, 1e-9) and ctr.distance_to(Vector3(1, 2, 3)) < 1e-6,
			"19 MASS: volume %.9f area %.9f centre %s" % [mp.get("volume", 0.0), mp.get("area", 0.0), str(ctr)])
	ok(near(inertia.x.x, 2.0 * 2.0 / 12.0, 1e-6) and near(inertia.y.y, 2.0 * 5.0 / 12.0, 1e-6) and near(inertia.z.z, 2.0 * 5.0 / 12.0, 1e-6),
			"19 MASS: box inertia about the centre %.6f %.6f %.6f vs %.6f %.6f %.6f" % [inertia.x.x, inertia.y.y, inertia.z.z, 4.0 / 12.0, 10.0 / 12.0, 10.0 / 12.0])

	# 20 blade: lines + arc tip, extruded, edges filleted
	var blade_items := [
		KCad.line(Vector2(-0.05, 0.0), Vector2(0.05, 0.0)),
		KCad.line(Vector2(0.05, 0.0), Vector2(0.04, 0.8)),
		KCad.arc(Vector2(0.04, 0.8), Vector2(0.0, 0.85), Vector2(-0.04, 0.8)),
		KCad.line(Vector2(-0.04, 0.8), Vector2(-0.05, 0.0)),
	]
	var bf := KCad.sketch_face(blade_items)
	var blade := KCad.extrude(bf, 0.012)
	ok(bf > 0 and blade > 0 and KCad.volume(blade) > 0.0005 and KCad.volume(blade) < 0.001, "20 BLADE: extruded, volume %.9f (%s)" % [KCad.volume(blade), KCad.last_error()])
	var vert := PackedInt32Array()
	for e in KCad.edges(blade):
		if absf((e["dir"] as Vector3).z) > 0.99:
			vert.append(e["id"])
	ok(vert.size() == 4, "20 BLADE: 4 edges run along the extrusion (%d)" % vert.size())
	var bl := KCad.fillet_edges(blade, vert, 0.002)
	ok(bl > 0, "20 BLADE: the 4 edges along the extrusion filleted 2 mm (%s)" % KCad.last_error())
	if bl > 0:
		var bm := KCad.tessellate(bl, 0.0002, 0.3)
		var wt := watertight(bm) if bm != null else [-1, 0, 0]
		ok(bm != null and wt[0] == 0, "20 BLADE: tessellated blade is watertight (%d open/flipped edges, %d welded verts)" % [wt[0], wt[1]])
		ok(bm != null and near(mesh_volume(bm), KCad.volume(bl), 0.01), "20 BLADE: mesh volume %.9f vs kernel %.9f" % [mesh_volume(bm) if bm != null else 0.0, KCad.volume(bl)])
	var pts := PackedVector2Array()
	for i in 8:
		var a := TAU * i / 8.0
		var r := 1.0 + 0.25 * cos(3.0 * a)
		pts.append(Vector2(cos(a), sin(a)) * r)
	var blob_f := KCad.sketch_face([KCad.bspline(pts, true)])
	var blob := KCad.extrude(blob_f, 0.5)
	var area := float(KCad.mass_properties(blob_f).get("area", -1.0))
	ok(blob_f > 0 and blob > 0 and area > 2.0 and near(KCad.volume(blob), area * 0.5, 1e-9), "20 BLADE: closed B-spline outline extruded: volume %.9f = area %.9f * 0.5 (%s)" % [KCad.volume(blob), area, KCad.last_error()])
	var blob_m := KCad.tessellate(blob, 0.002, 0.3)
	var wtb := watertight(blob_m) if blob_m != null else [-1, 0, 0]
	ok(blob_m != null and wtb[0] == 0, "20 BLADE: B-spline solid is watertight (%d bad edges)" % wtb[0])

	# 21 STEP
	if bl > 0:
		var sp := "user://cad_test_blade.step"
		var wrote := KCad.export_step(bl, sp)
		var back := KCad.import_step(sp) if wrote else 0
		ok(back > 0 and near(KCad.volume(back), KCad.volume(bl), 1e-6), "21 STEP: filleted blade round trip volume %.9f vs %.9f" % [KCad.volume(back), KCad.volume(bl)])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(sp))

	# 22 release
	var before := KCad.live_count()
	var made := []
	for i in 20:
		made.append(KCad.extrude(KCad.sketch_face(KCad.polygon(square(1.0))), 1.0))
	ok(KCad.live_count() == before + 40, "22 RELEASE: 20 faces + 20 solids live (%d)" % (KCad.live_count() - before))
	for i in 20:
		KCad.release(made[i])
	ok(KCad.live_count() - before == 20, "22 RELEASE: solids released, the 20 sketch faces remain (%d)" % (KCad.live_count() - before))
	KCad.release_all()
	ok(KCad.live_count() == 0, "22 RELEASE: release_all frees everything")

	# 23 OFFSET FACE / DRAFT (added with KineCAD version 3). Closed forms; faces picked by faces() (outward normal).
	var ob := KCad.box(1.0, 1.0, 1.0)
	var top := _face_with_normal(ob, Vector3.UP)
	var up := KCad.offset_face(ob, top, 0.2)
	ok(up > 0 and near(KCad.volume(up), 1.2, 1e-9), "23 OFFSET: +0.2 on a unit cube's top face: volume %.9f vs 1.2 (%s)" % [KCad.volume(up), KCad.last_error()])
	var down := KCad.offset_face(ob, _face_with_normal(ob, Vector3.UP), -0.2)
	ok(down > 0 and near(KCad.volume(down), 0.8, 1e-9), "23 OFFSET: -0.2 on the top face: volume %.9f vs 0.8 (%s)" % [KCad.volume(down), KCad.last_error()])
	ok(KCad.offset_face(ob, 999, 0.1) == 0 and KCad.last_error() != "", "23 OFFSET: bad face id fails cleanly")
	var wb := KCad.translate(KCad.box(0.1, 0.06, 0.04), Vector3(0, 0, 0.02))
	var wall := _face_with_normal(wb, Vector3.RIGHT)
	var dr := KCad.draft_faces(wb, PackedInt32Array([wall]), deg_to_rad(5.0), Vector3(0, 0, 1), Vector3.ZERO)
	var wn := KCad.faces(dr)
	var lean := -1.0
	for f in wn:
		if f.get("normal", Vector3.ZERO).x > 0.9:
			lean = rad_to_deg(asin(absf(f["normal"].z)))
	ok(dr > 0 and absf(lean - 5.0) <= 0.1, "23 DRAFT: 5 deg on one wall of a 100x60x40 box: wall lean %.4f deg (%s)" % [lean, KCad.last_error()])
	ok(KCad.draft_faces(wb, PackedInt32Array([999]), 0.1, Vector3(0, 0, 1), Vector3.ZERO) == 0 and KCad.last_error() != "", "23 DRAFT: bad face id fails cleanly")


func finish() -> void:
	print("cad: %d fail, %d skip" % [fails, skips])
	print("PASS" if fails == 0 else "FAIL")
	quit(1 if fails > 0 else 0)
