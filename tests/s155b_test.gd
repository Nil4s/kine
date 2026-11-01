extends SceneTree
## godot --headless --path . -s tests/s155b_test.gd     (KineCAD 5: the kernel's own solid offset, and part_offset.gd using it; needs the CAD DLL)
## Bars (numbers measured from the kernel, written before running):
##   1 the DLL says version 5 and KCad.has_offset()
##   2 box 40x20x10 offset +1 mm: volume of a sharp 42x22x12 box within 1e-6 relative, area likewise
##   3 box offset -1 mm: 38x18x8 volume within 1e-6
##   4 plate 60x40x10 with a 10 mm hole, +1 mm: volume = 62*42*12 - pi*4^2*12 (hole 8 mm wide) within 0.05 pct; -1 mm: 58*38*8 - pi*6^2*8 (hole 12 wide)
##   5 plate with a Row of 4 holes (r 3 mm, 10 mm apart), +1 and -1 mm, volume against the same closed form within 0.05 pct
##   6 a wall thinner than 2 x |d| (1 mm plate, -1 mm): refused (0), last_error() names it, no crash
##   7 part_offset.gd grows through the kernel: the hole of the plate reads 8.00 / 12.00 mm in the tessellated mesh (nearest vertex to the axis, 0.05 mm)
##   8 TIMING table: kernel path vs the 26-copy fallback (part_offset.gd force_fallback) for box +1, plate with hole +1, plate with 4-hole Row +1;
##     BAR: the kernel path is faster than the fallback on every row
const KCad := preload("res://scripts/kcad.gd")
const POFF := preload("res://scripts/build/part_offset.gd")
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	if not c:
		fails += 1


func _plate(w: float, d: float, h: float, holes: Array, r: float) -> int:
	var b := KCad.box(w, d, h)
	for x in holes:
		var c := KCad.cylinder(r, h * 3.0)
		var cc: Vector3 = KCad.mass_properties(c).get("center", Vector3.ZERO)
		var m := KCad.translate(c, Vector3(float(x), 0.0, 0.0) - cc)
		var nb := KCad.cut(b, m)
		KCad.release(c)
		KCad.release(m)
		KCad.release(b)
		b = nb
	return b


## smallest distance from the hole axis (x0, 0) to a mesh vertex lying on the hole wall (|x - x0| < 15 mm, |y| < 15 mm), in mm, doubled = the hole's width
func _hole_width(id: int, x0: float) -> float:
	var mesh: ArrayMesh = KCad.tessellate(id, 0.0002, 0.1)
	if mesh == null or mesh.get_surface_count() == 0:
		return -1.0
	var best := INF
	for s in mesh.get_surface_count():
		var v: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for p in v:
			var dx := (p.x - x0) * 1000.0
			var dy := p.y * 1000.0
			var r := sqrt(dx * dx + dy * dy)
			if r < 14.0:
				best = minf(best, r)
	return best * 2.0


func _pct(a: float, b: float) -> float:
	return absf(a - b) / maxf(absf(b), 1e-12) * 100.0


func _time(id: int, d: float, fallback: bool) -> float:
	POFF.force_fallback = fallback
	var t := Time.get_ticks_usec()
	var r := POFF.grow(id, d)
	var ms := float(Time.get_ticks_usec() - t) / 1000.0
	POFF.force_fallback = false
	if r != 0:
		KCad.release(r)
	return ms if r != 0 else -ms


func _init() -> void:
	if not KCad.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		print("s155b: 1 fail")
		quit(1)
		return
	ok(KCad.version_number() >= 5 and KCad.has_offset(), "1 %s, has_offset %s" % [KCad.version(), str(KCad.has_offset())])
	var MM := 0.001
	var b := KCad.box(0.04, 0.02, 0.01)
	var v0 := KCad.volume(b)
	var bp := KCad.offset(b, MM)
	var vp := KCad.volume(bp)
	var want := 0.042 * 0.022 * 0.012
	ok(bp != 0 and _pct(vp, want) < 1e-4, "2a box +1 mm: volume %.4f mm3 (sharp 42x22x12 = %.4f), %.6f pct" % [vp * 1e9, want * 1e9, _pct(vp, want)])
	var wa := 2.0 * (0.042 * 0.022 + 0.042 * 0.012 + 0.022 * 0.012)
	ok(_pct(KCad.area(bp), wa) < 1e-4, "2b area %.2f mm2 (want %.2f)" % [KCad.area(bp) * 1e6, wa * 1e6])
	var bm := KCad.offset(b, -MM)
	var wm := 0.038 * 0.018 * 0.008
	ok(bm != 0 and _pct(KCad.volume(bm), wm) < 1e-4, "3 box -1 mm: volume %.4f mm3 (38x18x8 = %.4f)" % [KCad.volume(bm) * 1e9, wm * 1e9])
	ok(KCad.volume(b) == v0, "3b the input solid is unchanged (id stays valid)")

	var p1 := _plate(0.06, 0.04, 0.01, [0.0], 0.005)
	var p1p := KCad.offset(p1, MM)
	var e1 := KCad.last_error()
	var p1m := KCad.offset(p1, -MM)
	if p1p == 0 or p1m == 0:
		print("  plate offset refused: ", e1, " | ", KCad.last_error())
	var wp1 := 0.062 * 0.042 * 0.012 - PI * 0.004 * 0.004 * 0.012
	var wm1 := 0.058 * 0.038 * 0.008 - PI * 0.006 * 0.006 * 0.008
	ok(p1p != 0 and _pct(KCad.volume(p1p), wp1) < 0.05, "4a plate with hole +1 mm: %.2f mm3 (want %.2f), %.4f pct" % [KCad.volume(p1p) * 1e9, wp1 * 1e9, _pct(KCad.volume(p1p), wp1)])
	ok(p1m != 0 and _pct(KCad.volume(p1m), wm1) < 0.05, "4b plate with hole -1 mm: %.2f mm3 (want %.2f), %.4f pct" % [KCad.volume(p1m) * 1e9, wm1 * 1e9, _pct(KCad.volume(p1m), wm1)])

	var xs := [-0.015, -0.005, 0.005, 0.015]
	var p4 := _plate(0.06, 0.04, 0.01, xs, 0.003)
	var p4p := KCad.offset(p4, MM)
	var p4m := KCad.offset(p4, -MM)
	var wp4 := 0.062 * 0.042 * 0.012 - 4.0 * PI * 0.002 * 0.002 * 0.012
	var wm4 := 0.058 * 0.038 * 0.008 - 4.0 * PI * 0.004 * 0.004 * 0.008
	ok(p4p != 0 and _pct(KCad.volume(p4p), wp4) < 0.05, "5a 4-hole Row +1 mm: %.2f mm3 (want %.2f), %.4f pct" % [KCad.volume(p4p) * 1e9, wp4 * 1e9, _pct(KCad.volume(p4p), wp4)])
	ok(p4m != 0 and _pct(KCad.volume(p4m), wm4) < 0.05, "5b 4-hole Row -1 mm: %.2f mm3 (want %.2f), %.4f pct" % [KCad.volume(p4m) * 1e9, wm4 * 1e9, _pct(KCad.volume(p4m), wm4)])

	var thin := KCad.box(0.04, 0.04, 0.001)
	var tn := KCad.offset(thin, -MM)
	ok(tn == 0 and KCad.last_error() != "", "6 a 1 mm plate -1 mm is refused: id %d, '%s'" % [tn, KCad.last_error()])

	var hw_p := _hole_width(p1p, 0.0)
	var hw_m := _hole_width(p1m, 0.0)
	ok(absf(hw_p - 8.0) <= 0.05 and absf(hw_m - 12.0) <= 0.05, "7 hole width in the mesh: +1 -> %.3f (want 8.00), -1 -> %.3f (want 12.00)" % [hw_p, hw_m])
	# part_offset.gd (the path the app takes)
	var viaapp: Array = [KCad.translate(p1, Vector3.ZERO)]
	var e := POFF.apply(viaapp, {"mm": 1.0})
	ok(e == "" and absf(_hole_width(int(viaapp[0]), 0.0) - 8.0) <= 0.05, "7b part_offset.apply +1: hole %.3f mm (want 8.00), '%s'" % [_hole_width(int(viaapp[0]), 0.0), e])

	# timing: median of 3
	var rows := [["box +1", b], ["plate with hole +1", p1], ["plate with 4-hole Row +1", p4]]
	print("TIMING (ms, median of 3)   before = 26-copy fallback   after = kernel offset")
	var allfast := true
	for r in rows:
		var fb: Array = []
		var kn: Array = []
		for i in 3:
			fb.append(_time(int(r[1]), MM, true))
			kn.append(_time(int(r[1]), MM, false))
		fb.sort()
		kn.sort()
		print("  %-26s before %8.0f   after %8.0f   x%.1f faster" % [r[0], fb[1], kn[1], fb[1] / maxf(kn[1], 0.001)])
		if kn[1] <= 0.0 or kn[1] >= fb[1]:
			allfast = false
	ok(allfast, "8 the kernel offset is faster than the 26-copy path on every row")
	print("s155b: %d fail" % fails)
	quit(1 if fails > 0 else 0)
