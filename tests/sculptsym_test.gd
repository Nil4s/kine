## godot --headless --path . -s tests/sculptsym_test.gd     (ROADMAP_400 C07; scripts/kmesh_sculpt_sym.gd)
## Bars, written before measuring:
##   1 MAPS: X+Z = 4 maps, X+Y+Z = 8, radial 6 around Y = 6, X + radial 6 around Y = 12, radial 2 around Y with X+Z = 4
##     (the duplicates go), radial 40 is clamped to 32; X alone needs no replicator (the C01 path stays)
##   2 X + Z: one draw dab (radius 0.1, strength 1 cm) at (0.3, 0, 0.2) on the 2 m plane (40 x 40) lands 4 bumps: the verts
##     at (+-0.3, 0, +-0.2) each rise by 1 cm (1e-5); every vert's rise equals its X, Z and XZ images' (1e-5); 4 x the verts
##     of a single dab move, and the total rise is 4 x a single dab's (1e-5 relative)
##   3 RADIAL 6 around Y on a polar disc (72 sectors, 30 rings of 2 cm): one draw dab at (0.4, 0, 0) lands 6 bumps: the 6
##     bump peaks (verts at r 0.4, angle 60 k) rise by the same amount (1e-5); every vert's rise equals the one 60 deg on
##     (1e-5); the rise-weighted angle of each bump is 60 k deg (0.5 deg); the total is 6 x a single dab's (1e-4 relative)
##   4 SYMMETRIC SPHERE (KMeshSculptUI.make_sphere, 3 458 verts, r 0.3) with X + Y + Z, a 30-dab draw stroke off every plane:
##     the mesh moved (> 1 mm somewhere) and the max mirror mismatch over X, Y, Z is < 0.01 mm. The instrument can move: the
##     same stroke with X only leaves a Y mismatch > 1 mm
##   5 ONE UNDO STEP: the stroke of bar 4 bracketed by KMeshUndo is one step; undo puts every vert back exactly
##   6 KEYS (KMeshSculptUI, no window): Y and Z toggle sym_y / sym_z, R / Shift+R step the radial count, Alt+R the axis; the
##     stroke params carry them; the status line names them
extends SceneTree

var fails := 0


class FakeMain extends Node:
	var said := ""

	func _say(s: String) -> void:
		said = s


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


static func plane(n: int, size := 2.0) -> KMesh:
	var vs := PackedVector3Array()
	for j in n + 1:
		for i in n + 1:
			vs.append(Vector3(-size * 0.5 + size * i / n, 0.0, -size * 0.5 + size * j / n))
	var fs: Array = []
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			fs.append([a, a + n + 1, a + n + 2, a + 1])
	return KMesh.new().from_arrays(vs, fs)


## centre + `rings` rings of `sec` verts (ring i at radius i * dr); vert of ring i (1..), sector j = 1 + (i - 1) * sec + j
static func disc(rings: int, sec: int, dr: float) -> KMesh:
	var vs := PackedVector3Array([Vector3.ZERO])
	for i in range(1, rings + 1):
		for j in sec:
			var t := TAU * j / sec
			vs.append(Vector3(cos(t), 0.0, sin(t)) * dr * i)
	var fs: Array = []
	for j in sec:
		fs.append([0, 1 + (j + 1) % sec, 1 + j])
	for i in range(1, rings):
		for j in sec:
			var a := 1 + (i - 1) * sec
			var b := 1 + i * sec
			fs.append([a + j, a + (j + 1) % sec, b + (j + 1) % sec, b + j])
	return KMesh.new().from_arrays(vs, fs)


static func nearest(m: KMesh, q: Vector3) -> int:
	var b := -1
	var bd := INF
	for v in m.verts.size():
		var d := m.verts[v].distance_squared_to(q)
		if d < bd:
			bd = d
			b = v
	return b


static func rise(m: KMesh) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for v in m.verts:
		out.append(v.y)
	return out


func one_dab(m: KMesh, at: Vector3, params: Dictionary) -> int:
	var sc := KMeshSculpt.new()
	var pp := {"brush": KMeshSculpt.DRAW, "radius": 0.1, "strength": 0.01}
	pp.merge(params, true)
	sc.begin(m, pp)
	var n := sc.dab(at, Vector3.UP, 1.0)
	sc.end()
	return n


## max |v[partner] - S v| over the verts with a partner, for the mirror of axis a
static func mismatch(m: KMesh, part: PackedInt32Array, a: int) -> float:
	var w := 0.0
	for v in m.verts.size():
		var u := part[v]
		if u < 0:
			continue
		var q := m.verts[v]
		q[a] = -q[a]
		w = maxf(w, m.verts[u].distance_to(q))
	return w


func stroke(m: KMesh, params: Dictionary, undo: KMeshUndo = null) -> int:
	var sc := KMeshSculpt.new()
	var pp := {"brush": KMeshSculpt.DRAW, "radius": 0.08, "strength": 0.002, "spacing": 0.1}
	pp.merge(params, true)
	if undo != null:
		undo.begin(m)
	sc.begin(m, pp)
	# along a small circle on the sphere, off every mirror plane (the 30 dabs stay in the +x +y +z octant)
	var k := 0
	while sc.dabs < 30 and k < 4000:
		var t := 0.002 * k
		var q := Vector3(0.55 + 0.25 * cos(t), 0.5 + 0.25 * sin(t), 0.6).normalized() * 0.3
		sc.to(q, q.normalized(), 1.0)
		k += 1
	sc.end()
	if undo != null:
		undo.commit("sculpt draw")
	return sc.dabs


func _init() -> void:
	# 1 maps
	var T := KMeshSculptSym
	var c := [T.transforms(true, false, true).size(), T.transforms(true, true, true).size(), T.transforms(false, false, false, 6, 1).size(),
		T.transforms(true, false, false, 6, 1).size(), T.transforms(true, false, true, 2, 1).size(), T.transforms(false, false, false, 40, 1).size()]
	print("  map counts ", c)
	var sx := KMeshSculpt.new()
	sx.begin(plane(4), {"sym_x": true})
	ok(c == [4, 8, 6, 12, 4, 32] and sx._symx == null and not sx._sym.is_empty(), "1 maps: X+Z 4, XYZ 8, radial 6, X+radial 6 12, radial 2 + XZ 4, radial 40 -> 32; X alone keeps the C01 path")

	# 2 X + Z on the plane
	var H := Vector3(0.3, 0.0, 0.2)
	var single := plane(40)
	var n1 := one_dab(single, H, {})
	var m := plane(40)
	var n4 := one_dab(m, H, {"sym_x": true, "sym_z": true})
	var y := rise(m)
	var pk := []
	for s in [Vector3(1, 1, 1), Vector3(-1, 1, 1), Vector3(1, 1, -1), Vector3(-1, 1, -1)]:
		pk.append(y[nearest(m, H * s)])
	var worst := 0.0
	var mx := m.symmetry_map(0, 1e-4)
	var mz := m.symmetry_map(2, 1e-4)
	for v in m.verts.size():
		worst = maxf(worst, absf(y[v] - y[mx[v]]))
		worst = maxf(worst, absf(y[v] - y[mz[v]]))
		worst = maxf(worst, absf(y[v] - y[mx[mz[v]]]))
	var t1 := 0.0
	for v in rise(single):
		t1 += v
	var t4 := 0.0
	for v in y:
		t4 += v
	var pkw := 0.0
	for q in pk:
		pkw = maxf(pkw, absf(q - 0.01))
	print("  peaks ", pk, "  image mismatch %.9f  moved %d vs single %d  total %.6f vs 4 x %.6f" % [worst, n4, n1, t4, t1])
	ok(pkw < 1e-5 and worst < 1e-5 and n4 == 4 * n1 and absf(t4 - 4.0 * t1) < 1e-5 * absf(4.0 * t1), "2 X+Z: 4 bumps of 1 cm at the mirrored points, equal within 1e-5, 4 x the verts and the rise of one dab")

	# 3 radial 6 around Y on a polar disc
	var SEC := 72
	var d1 := disc(30, SEC, 0.02)
	one_dab(d1, Vector3(0.4, 0, 0), {})
	var d6 := disc(30, SEC, 0.02)
	one_dab(d6, Vector3(0.4, 0, 0), {"radial": 6, "radial_axis": 1})
	var y6 := rise(d6)
	var peaks := []
	for k in 6:
		peaks.append(y6[1 + 19 * SEC + k * 12])   # ring 20 (r 0.4), sector 12 k (60 k deg)
	var pmax := 0.0
	for q in peaks:
		pmax = maxf(pmax, absf(q - peaks[0]))
	var rot := 0.0
	for v in range(1, d6.verts.size()):
		var i := (v - 1) / SEC
		var j := (v - 1) % SEC
		rot = maxf(rot, absf(y6[v] - y6[1 + i * SEC + (j + 12) % SEC]))
	rot = maxf(rot, 0.0)
	var angs := []
	var aw := 0.0
	for k in 6:
		var a0 := TAU * k / 6.0
		var sv := Vector2.ZERO
		for v in range(1, d6.verts.size()):
			var q := d6.verts[v]
			var a := atan2(q.z, q.x)
			if absf(wrapf(a - a0, -PI, PI)) < PI / 6.0 and y6[v] > 0.0:
				sv += Vector2(cos(a), sin(a)) * y6[v]
		var ang := rad_to_deg(sv.angle())
		angs.append(snappedf(ang, 0.001))
		aw = maxf(aw, absf(wrapf(ang - 60.0 * k, -180.0, 180.0)))
	var s1 := 0.0
	for v in rise(d1):
		s1 += v
	var s6 := 0.0
	for v in y6:
		s6 += v
	print("  radial peaks ", peaks, "  60-deg mismatch %.9f  bump angles " % rot, angs, "  total %.6f vs 6 x %.6f" % [s6, s1])
	ok(peaks[0] > 0.009 and pmax < 1e-5 and rot < 1e-5 and aw < 0.5 and absf(s6 - 6.0 * s1) < 1e-4 * 6.0 * s1, "3 radial 6 around Y: 6 equal bumps (1e-5) 60 deg apart (worst %.3f deg), the field turns onto itself by 60 deg" % aw)

	# 4 symmetric sphere, 30-dab stroke with X + Y + Z
	var sp := KMeshSculptUI.make_sphere()
	var rest := sp.verts.duplicate()
	var px := sp.symmetry_map(0, 1e-5)
	var py := sp.symmetry_map(1, 1e-5)
	var pz := sp.symmetry_map(2, 1e-5)
	var m0 := maxf(mismatch(sp, px, 0), maxf(mismatch(sp, py, 1), mismatch(sp, pz, 2)))
	var undo := KMeshUndo.new()
	var nd := stroke(sp, {"sym_x": true, "sym_y": true, "sym_z": true}, undo)
	var moved := 0.0
	for v in sp.verts.size():
		moved = maxf(moved, sp.verts[v].distance_to(rest[v]))
	var mm := [mismatch(sp, px, 0), mismatch(sp, py, 1), mismatch(sp, pz, 2)]
	var mw := maxf(mm[0], maxf(mm[1], mm[2]))
	var ctl := KMeshSculptUI.make_sphere()
	stroke(ctl, {"sym_x": true})
	var cy := mismatch(ctl, py, 1)
	print("  sphere: %d dabs, max move %.2f mm, mirror mismatch before %.9f, after X %.9f Y %.9f Z %.9f m; X-only control Y mismatch %.2f mm" % [nd, moved * 1000.0, m0, mm[0], mm[1], mm[2], cy * 1000.0])
	ok(nd == 30 and moved > 0.001 and mw < 1e-5, "4 symmetric sphere + XYZ, 30-dab stroke: moved %.2f mm, max mirror mismatch %.4f mm < 0.01 mm" % [moved * 1000.0, mw * 1000.0])
	ok(cy > 0.001, "4 the instrument can move: the same stroke with X only leaves a Y mismatch of %.2f mm" % (cy * 1000.0))

	# 5 one undo step
	var st_n := undo.steps.size()
	undo.undo()
	var back := true
	for v in sp.verts.size():
		if sp.verts[v] != rest[v]:
			back = false
			break
	ok(st_n == 1 and back, "5 the symmetric stroke is ONE undo step (%d) and undo puts every vert back exactly" % st_n)

	# 6 keys
	var fm := FakeMain.new()
	var ui := KMeshSculptUI.new()
	ui.m = fm
	ui.on = true
	ui.mesh = KMeshSculptUI.make_sphere()
	var res := []
	for e in [[KEY_Y, false, false], [KEY_Z, false, false], [KEY_R, false, false], [KEY_R, false, false], [KEY_R, false, false], [KEY_R, true, false], [KEY_R, false, true], [KEY_R, false, true]]:
		var ke := InputEventKey.new()
		ke.keycode = e[0]
		ke.shift_pressed = e[1]
		ke.alt_pressed = e[2]
		ke.pressed = true
		res.append(ui.input(ke))
	var pp := ui._params(InputEventMouseMotion.new())
	print("  params ", pp, "  said: ", fm.said)
	ok(not res.has(false) and pp["sym_y"] and pp["sym_z"] and pp["sym_x"] and pp["radial"] == 3 and pp["radial_axis"] == 0 and fm.said.contains("radial 3 around X"),
		"6 keys: Y Z toggle, R R R Shift+R -> radial 3, Alt+R Alt+R -> axis X; the params and the status line carry them")
	ui.free()
	fm.free()

	print("SCULPTSYM %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
