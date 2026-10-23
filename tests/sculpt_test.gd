## godot --headless --path . -s tests/sculpt_test.gd     (ROADMAP_400 C01 + C02; scripts/kmesh_sculpt.gd)
## A flat plane 2 m x 2 m in XZ, 40 x 40 quads (5 cm cells, centred on the origin, normal +Y). Bars, written before measuring:
##   1 DRAW + FALLOFF: one dab at (0.3, 0, 0.2), radius 0.25, strength 1 cm raises the centre vert by exactly 1 cm (1e-6),
##     every vert by strength * falloff(d / r) (1e-6) for all 4 falloffs, and leaves every vert at d >= r at y = 0 exactly;
##     pressure 0.5 raises the centre by 5 mm; a mouse motion with pressure 0 reads as 1, a pen at 0.4 as 0.4
##   2 SPACING: a stroke 0.5 m long at spacing 0.1 x radius 0.1 lays 51 dabs (one at the press + one each 1 cm)
##   3 SMOOTH: on a noisy plane (y in +-1 cm, seeded) 5 dabs cut the mean |Laplacian| of the verts within r/2 by > 50 %,
##     and move no vert beyond the radius
##   4 INFLATE: on a sphere (cube 24 x 24 per side pushed to r = 0.5) every moved vert moves along its own normal (cos > 0.999)
##     and the mean distance from the centre of the verts under the brush grows
##   5 FLATTEN cuts the y spread under the brush by > 50 %; PINCH brings every vert under the brush no farther from the brush
##     axis and the mean closer; CREASE sinks the centre; CLAY STRIPS raises the low verts and puts none above the clay plane;
##     SNAKE HOOK moves the centre vert along the drag
##   6 GRAB: pressed on a vert and dragged by (0.05, 0.08, -0.03): that vert moves by exactly the delta (1e-6), a vert at
##     d >= r does not move, a vert 0.1 m off moves by delta * falloff(0.4)
##   7 X SYMMETRY: a draw dab at x = 0.3 with sym_x: every vert equals its mirror partner (|dy| < 1e-7) and the mirror side
##     is raised; a grab with sym_x moves the partner by the delta with x negated
##   8 UNDO: the stroke of bar 2 bracketed by KMeshUndo is ONE step; undo puts every vert back exactly, redo re-applies
##   9 TIMING: a 224 x 224 plane (50 625 verts): the stroke's spatial hash builds in < 300 ms, a dab (radius 0.1, ~390 verts)
##     takes < 16 ms on average over 20 dabs
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


static func plane(n: int, size := 2.0, noise := 0.0) -> KMesh:
	var vs := PackedVector3Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for j in n + 1:
		for i in n + 1:
			var y := rng.randf_range(-noise, noise) if noise > 0.0 else 0.0
			vs.append(Vector3(-size * 0.5 + size * i / n, y, -size * 0.5 + size * j / n))
	var fs: Array = []
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			fs.append([a, a + n + 1, a + n + 2, a + 1])   # CCW seen from +Y
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


static func lap(m: KMesh, ids: PackedInt32Array) -> float:
	var s := 0.0
	for v in ids:
		var nb := m.vert_neighbors(v)
		var mean := Vector3.ZERO
		for u in nb:
			mean += m.verts[u]
		s += (mean / nb.size() - m.verts[v]).length()
	return s / maxf(ids.size(), 1)


func _init() -> void:
	var H := Vector3(0.3, 0.0, 0.2)
	var R := 0.25
	# 1 draw + falloff
	var m := plane(40)
	print("  plane normal ", m.vert_normals[0])
	var all_f := true
	var worst := 0.0
	for fk in KMeshSculpt.FALLOFFS:
		m = plane(40)
		var sc := KMeshSculpt.new()
		sc.begin(m, {"brush": KMeshSculpt.DRAW, "radius": R, "strength": 0.01, "falloff": fk})
		sc.dab(H, Vector3.UP)
		var c := nearest(m, H)
		all_f = all_f and absf(m.verts[c].y - 0.01) < 1e-6
		for v in m.verts.size():
			var q := m.verts[v]
			var d := Vector2(q.x - H.x, q.z - H.z).length()
			var want := 0.01 * KMeshSculpt.falloff(fk, d / R)
			worst = maxf(worst, absf(q.y - want))
			if d >= R and q.y != 0.0:
				all_f = false
	ok(all_f and worst < 1e-6, "(1) draw: centre +1 cm, every vert = strength * falloff (worst error %s m), 0 beyond r, for %s" % [worst, KMeshSculpt.FALLOFFS])
	m = plane(40)
	var sp := KMeshSculpt.new()
	sp.begin(m, {"radius": R, "strength": 0.01})
	sp.dab(H, Vector3.UP, 0.5)
	var mm := InputEventMouseMotion.new()
	mm.pressure = 0.0
	var pen := InputEventMouseMotion.new()
	pen.pressure = 0.4
	ok(absf(m.verts[nearest(m, H)].y - 0.005) < 1e-6 and KMeshSculpt.pressure_of(mm) == 1.0 and is_equal_approx(KMeshSculpt.pressure_of(pen), 0.4),
		"(1) pressure 0.5 -> centre +%.4f m; mouse pressure 0 reads 1, pen 0.4 reads %.2f" % [m.verts[nearest(m, H)].y, KMeshSculpt.pressure_of(pen)])
	# 2 spacing
	m = plane(40)
	var st := KMeshSculpt.new()
	st.begin(m, {"radius": 0.1, "strength": 0.001, "spacing": 0.1})
	var a0 := Vector3(-0.25, 0, 0)
	for k in 11:
		st.to(a0 + Vector3(0.05 * k, 0, 0), Vector3.UP)
	st.end()
	ok(st.dabs == 51, "(2) a 0.5 m stroke at 1 cm spacing lays %d dabs (want 51)" % st.dabs)
	# 3 smooth
	m = plane(40, 2.0, 0.01)
	var v0 := m.verts.duplicate()
	var inner := KMeshSculpt.new()
	inner.begin(m, {"radius": R})
	var ids := inner.verts_in(H, R * 0.5)
	var l0 := lap(m, ids)
	var sm := KMeshSculpt.new()
	sm.begin(m, {"brush": KMeshSculpt.SMOOTH, "radius": R, "strength": 0.01})
	for k in 5:
		sm.dab(H, Vector3.UP)
	var l1 := lap(m, ids)
	var outside_still := true
	for v in m.verts.size():
		if v0[v].distance_to(H) >= R and m.verts[v] != v0[v]:
			outside_still = false
	ok(l1 < l0 * 0.5 and outside_still, "(3) smooth: mean |Laplacian| under r/2 %.5f -> %.5f (%.0f %% less), nothing beyond r moved: %s" % [l0, l1, 100.0 * (1.0 - l1 / l0), outside_still])
	# 4 inflate on a sphere
	var sph := KMeshView.make_cube(1.0, 24)
	for v in sph.verts.size():
		sph.verts[v] = sph.verts[v].normalized() * 0.5
	sph.rebuild()
	var top := nearest(sph, Vector3(0, 0.5, 0))
	var pts := sph.verts.duplicate()
	var nrm := sph.vert_normals.duplicate()
	var inf := KMeshSculpt.new()
	inf.begin(sph, {"brush": KMeshSculpt.INFLATE, "radius": 0.2, "strength": 0.01})
	var under := inf.verts_in(sph.verts[top], 0.2)
	var r_0 := 0.0
	for v in under:
		r_0 += pts[v].length()
	inf.dab(sph.verts[top], sph.vert_normals[top])
	var r_1 := 0.0
	var worst_cos := 1.0
	var moved := 0
	for v in sph.verts.size():
		var dv := sph.verts[v] - pts[v]
		if dv.length() > 1e-9:
			moved += 1
			worst_cos = minf(worst_cos, dv.normalized().dot(nrm[v]))
	for v in under:
		r_1 += sph.verts[v].length()
	ok(moved > 0 and worst_cos > 0.999 and r_1 > r_0, "(4) inflate: %d verts moved, worst cos to own normal %.5f, mean radius %.4f -> %.4f m" % [moved, worst_cos, r_0 / under.size(), r_1 / under.size()])
	# 5 flatten, pinch, crease, clay, snake
	m = plane(40, 2.0, 0.01)
	var fl := KMeshSculpt.new()
	fl.begin(m, {"radius": R})
	var fu := fl.verts_in(H, R * 0.5)
	var sd0 := _spread(m, fu)
	fl.begin(m, {"brush": KMeshSculpt.FLATTEN, "radius": R, "strength": 0.01})
	for k in 3:
		fl.dab(H, Vector3.UP)
	var sd1 := _spread(m, fu)
	ok(sd1 < sd0 * 0.5, "(5) flatten: y spread under r/2 %.5f -> %.5f m" % [sd0, sd1])
	m = plane(40)
	var pn := KMeshSculpt.new()
	pn.begin(m, {"brush": KMeshSculpt.PINCH, "radius": R, "strength": 0.01})
	var pu := pn.verts_in(H, R)
	var before := {}
	for v in pu:
		before[v] = Vector2(m.verts[v].x - H.x, m.verts[v].z - H.z).length()
	pn.dab(H, Vector3.UP)
	var never_out := true
	var sb := 0.0
	var sa := 0.0
	for v in pu:
		var dn := Vector2(m.verts[v].x - H.x, m.verts[v].z - H.z).length()
		never_out = never_out and dn <= before[v] + 1e-9
		sb += before[v]
		sa += dn
	ok(never_out and sa < sb, "(5) pinch: no vert farther from the axis, mean %.4f -> %.4f m" % [sb / pu.size(), sa / pu.size()])
	m = plane(40)
	var cr := KMeshSculpt.new()
	cr.begin(m, {"brush": KMeshSculpt.CREASE, "radius": R, "strength": 0.01})
	cr.dab(H, Vector3.UP)
	var cy := m.verts[nearest(m, H)].y
	m = plane(40, 2.0, 0.01)
	var cl := KMeshSculpt.new()
	cl.begin(m, {"radius": R})
	var cu := cl.verts_in(H, R * 0.5)
	var low0 := _min_y(m, cu)
	cl.begin(m, {"brush": KMeshSculpt.CLAY, "radius": R, "strength": 0.004})
	cl.dab(H, Vector3.UP)
	var low1 := _min_y(m, cu)
	var maxy := -INF
	for v in cl.verts_in(H, R):
		maxy = maxf(maxy, m.verts[v].y)
	m = plane(40)
	var sn := KMeshSculpt.new()
	sn.begin(m, {"brush": KMeshSculpt.SNAKE, "radius": R, "strength": 0.01, "spacing": 0.1})
	var c0 := nearest(m, H)
	sn.to(H, Vector3.UP)
	sn.to(H + Vector3(0, 0.1, 0), Vector3.UP)
	var snake_y := m.verts[c0].y
	ok(cy < -0.005 and low1 > low0 and maxy <= 0.004 + 0.011 and snake_y > 0.05,
		"(5) crease centre %.4f m; clay lowest under r/2 %.4f -> %.4f m, highest %.4f; snake hook lifted the centre to %.4f m" % [cy, low0, low1, maxy, snake_y])
	# 6 grab
	m = plane(40)
	var gb := KMeshSculpt.new()
	gb.begin(m, {"brush": KMeshSculpt.GRAB, "radius": R})
	var gc := nearest(m, H)
	var half := nearest(m, H + Vector3(0.1, 0, 0))
	var far := nearest(m, H + Vector3(R + 0.05, 0, 0))
	var g0 := m.verts.duplicate()
	var delta := Vector3(0.05, 0.08, -0.03)
	gb.to(m.verts[gc], Vector3.UP)
	gb.to(g0[gc] + delta * 0.5, Vector3.UP)
	gb.to(g0[gc] + delta, Vector3.UP)
	gb.end()
	var e_c := (m.verts[gc] - g0[gc] - delta).length()
	var e_h := (m.verts[half] - g0[half] - delta * KMeshSculpt.falloff(KMeshSculpt.F_SMOOTH, g0[half].distance_to(g0[gc]) / R)).length()
	ok(e_c < 1e-6 and e_h < 1e-6 and m.verts[far] == g0[far], "(6) grab: centre off the delta by %s m, the vert 0.1 m off (t = 0.4) off delta*falloff by %s m, far vert still" % [e_c, e_h])
	# 7 symmetry
	m = plane(40)
	var sy := KMeshSculpt.new()
	sy.begin(m, {"radius": R, "strength": 0.01, "sym_x": true})
	sy.dab(H, Vector3.UP)
	var smap := m.symmetry_map(0)
	var worst_s := 0.0
	for v in m.verts.size():
		if smap[v] >= 0:
			worst_s = maxf(worst_s, absf(m.verts[v].y - m.verts[smap[v]].y))
	var mir_y := m.verts[nearest(m, Vector3(-H.x, 0, H.z))].y
	m = plane(40)
	var sg := KMeshSculpt.new()
	sg.begin(m, {"brush": KMeshSculpt.GRAB, "radius": R, "sym_x": true})
	var gm := nearest(m, Vector3(-H.x, 0, H.z))
	var gm0 := m.verts[gm]
	sg.to(m.verts[gc], Vector3.UP)
	sg.to(m.verts[gc] + delta, Vector3.UP)
	var e_m := (m.verts[gm] - gm0 - Vector3(-delta.x, delta.y, delta.z)).length()
	ok(worst_s < 1e-7 and absf(mir_y - 0.01) < 1e-6 and e_m < 1e-6, "(7) symmetry: worst |dy| to the partner %s, mirror centre +%.4f m, mirrored grab off by %s m" % [worst_s, mir_y, e_m])
	# 8 undo
	m = plane(40)
	var u0 := m.verts.duplicate()
	var und := KMeshUndo.new()
	var us := KMeshSculpt.new()
	und.begin(m)
	us.begin(m, {"radius": 0.1, "strength": 0.001, "spacing": 0.1})
	for k in 11:
		us.to(a0 + Vector3(0.05 * k, 0, 0), Vector3.UP)
	us.end()
	und.commit("sculpt draw")
	var after := m.verts.duplicate()
	var steps := und.steps.size()
	und.undo()
	var back := m.verts == u0
	und.redo()
	ok(steps == 1 and back and m.verts == after and us.dabs == 51, "(8) undo: %d dabs = %d step (%d verts in it); undo exact %s, redo exact %s" % [us.dabs, steps, (und.steps[0]["idx"] as PackedInt32Array).size(), back, m.verts == after])
	# 9 timing
	var big := plane(224)
	var t0 := Time.get_ticks_usec()
	var tb := KMeshSculpt.new()
	tb.begin(big, {"radius": 0.1, "strength": 0.001})
	var t_hash := (Time.get_ticks_usec() - t0) / 1000.0
	var nin := tb.verts_in(Vector3.ZERO, 0.1).size()
	t0 = Time.get_ticks_usec()
	for k in 20:
		tb.dab(Vector3(-0.5 + 0.05 * k, 0, 0), Vector3.UP)
	var t_dab := (Time.get_ticks_usec() - t0) / 1000.0 / 20.0
	ok(t_hash < 300.0 and t_dab < 16.0, "(9) timing on %d verts: hash %.1f ms, dab %.2f ms (%d verts in the radius)" % [big.verts.size(), t_hash, t_dab, nin])
	print("SCULPT ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails else 0)


static func _spread(m: KMesh, ids: PackedInt32Array) -> float:
	var lo := INF
	var hi := -INF
	for v in ids:
		lo = minf(lo, m.verts[v].y)
		hi = maxf(hi, m.verts[v].y)
	return hi - lo


static func _min_y(m: KMesh, ids: PackedInt32Array) -> float:
	var lo := INF
	for v in ids:
		lo = minf(lo, m.verts[v].y)
	return lo
