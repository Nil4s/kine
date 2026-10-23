## godot --headless --path . -s tests/edgeflow_test.gd     (ROADMAP_400 B18; scripts/kmesh_edgeflow.gd)
## Bars, written before measuring:
##   1 RELAX on a jittered circle loop of a UV sphere (r 0.25, 32 x 16; the ring 5 bands up from the south pole, 32 verts,
##     each moved on the sphere by up to +-0.35 of a segment round and +-0.25 of a band up / down, seeded): relax 100 cuts
##     the std of the loop's radius (distance to the loop's centroid) by >= 10 x; every loop vert within 1e-4 m of the
##     sphere; the mean radius kept within 2 % (no shrink to the pole). A CLEAN ring: relax 10 moves no vert > 1e-6 m.
##     The instrument can move: the jitter raises the radius std above 1 mm.
##   2 STRAIGHTEN a jittered open run (9 verts of a row of a 8 x 8 plane, the 7 inside moved +-2 cm in x, y, z): max
##     distance to the line between the ends <= 1e-6, the 8 gaps equal within 1e-6, the ends unmoved.
##     On the surface: a 9-vert run along a sphere's latitude ring -> every vert within 1e-4 of the sphere and of the
##     plane through the centre and the two ends (a great circle), chord gaps equal within 1 %.
##   3 SET FLOW on a cylinder (r 0.25, depth 1, 32 x 8): the middle ring pushed in to 0.8 r; set flow 1 puts every vert
##     of it back at r within 1 % (and at its height within 1e-6); strength 0.5 lands at 0.9 r within 1 %. On the sphere
##     the equator pushed in 10 %: set flow 1 brings it back within 1 %.
##   4 EVEN SPACING on a loop of the sphere whose verts were slid round it unevenly (+-0.4 of a segment): each new vert
##     lies on the old polyline (< 1e-6) and its arc-length parameter there gives gaps equal within 1e-5; an open run
##     the same (ends kept).
##   5 every vert NOT in the loop is bit-exact after each op above
##   6 UNDO: each op in a KMeshUndo begin / commit is ONE step ("move"); undo puts every vert back exactly. The five
##     MeshTools rows run op:edgeflow_* (one undo step each, proportional editing on or off makes no difference to the
##     unselected verts); with nothing selected they say so and keep no step. (No panel: the rows are the UI.)
##   7 relax 10 on the 32-vert loop < 0.5 s
## HISTORY (the bars above did not move): the first relax (an explicit half step to the neighbours' midpoint, the mesh's
##   own area-weighted normals for the Phong lift) measured 7 x / 9.6 x on two jitters (bar 10 x) and 0.8 mm off the
##   sphere (bar 0.1 mm): the explicit step damps an ellipse of the loop ~1.5 % a pass, and the jittered faces tilt the
##   area-weighted normals. Now one IMPLICIT step a pass and Max's normals (exact on a sphere). The first straighten on
##   the surface took the NEAREST mesh point of each chord point: 3.3 mm off the great circle (deep under a faceted
##   mesh the nearest point snaps toward facet centres); now each chord point is cast within the plane through the ends
##   and their mean normal.
extends SceneTree

var fails := 0


class FakeUI extends RefCounted:
	var mesh: KMesh
	var sel: KMeshSelect
	var undo := KMeshUndo.new()
	var view = null
	var prop := KMeshProportional.new()


class FakeMain extends Node:
	var said := ""
	var kmed: FakeUI

	func _say(s: String) -> void:
		said = s


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


const R := 0.25


## the verts of a lathe ring at height y, in order round it
func ring_at(m: KMesh, y: float) -> PackedInt32Array:
	var ids := []
	for i in m.verts.size():
		if absf(m.verts[i].y - y) < 1e-6 and Vector2(m.verts[i].x, m.verts[i].z).length() > 1e-6:
			ids.append(i)
	ids.sort_custom(func(a, b): return atan2(-m.verts[a].z, m.verts[a].x) < atan2(-m.verts[b].z, m.verts[b].x))
	return PackedInt32Array(ids)


func select_run(m: KMesh, ids: PackedInt32Array, closed: bool) -> KMeshSelect:
	var s := KMeshSelect.new(m, KMeshSelect.EDGE)
	var n := ids.size()
	for i in (n if closed else n - 1):
		s.edges[KMeshSelect.ekey(ids[i], ids[(i + 1) % n])] = true
	return s


func rad_stats(m: KMesh, ids: PackedInt32Array) -> Vector2:   # (mean, std) of the distance to the loop's centroid
	var c := Vector3.ZERO
	for v in ids:
		c += m.verts[v]
	c /= ids.size()
	var s := 0.0
	var s2 := 0.0
	for v in ids:
		var r := m.verts[v].distance_to(c)
		s += r
		s2 += r * r
	var mu := s / ids.size()
	return Vector2(mu, sqrt(maxf(s2 / ids.size() - mu * mu, 0.0)))


## max |p| - r over every vert NOT in ids, compared with a snapshot: bit-exact?
func others_exact(before: PackedVector3Array, m: KMesh, ids: PackedInt32Array) -> bool:
	var inl := {}
	for v in ids:
		inl[v] = true
	for i in before.size():
		if not inl.has(i) and before[i] != m.verts[i]:
			return false
	return true


func sphere_y(k: int, rings := 16) -> float:
	return R * cos(PI * (1.0 - float(k) / rings))


## one op as one undo step: (step count + 1, kind move, undo exact)
func undo_ok(m: KMesh, f: Callable) -> bool:
	var u := KMeshUndo.new()
	var v0 := m.verts.duplicate()
	u.begin(m)
	f.call()
	var st := u.commit("edge flow")
	var v1 := m.verts.duplicate()
	var one: bool = u.steps.size() == 1 and st.get("kind", "") == "move"
	u.undo()
	var back := m.verts == v0
	u.redo()
	return one and back and m.verts == v1


func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 18

	# 1 relax ---------------------------------------------------------------------------------------------------
	var sph := KMeshPrims.uv_sphere(R, 32, 16)
	var ids := ring_at(sph, sphere_y(5))
	var clean0 := sph.verts.duplicate()
	var r10 := KMeshEdgeFlow.relax(sph, KMeshEdgeFlow.loops_of(sph, select_run(sph, ids, true)), 10)
	var cmax := 0.0
	for v in ids:
		cmax = maxf(cmax, sph.verts[v].distance_to(clean0[v]))
	ok(ids.size() == 32 and cmax <= 1e-6, "1a clean ring of %d verts: relax 10 moves no vert more than %.9f m (bar 1e-6)" % [ids.size(), cmax])
	var vs := sph.verts
	var th0 := PI * (1.0 - 5.0 / 16)
	for i in ids.size():
		var ph := atan2(-vs[ids[i]].z, vs[ids[i]].x) + rng.randf_range(-0.35, 0.35) * TAU / 32.0
		var th := th0 + rng.randf_range(-0.25, 0.25) * PI / 16.0
		vs[ids[i]] = Vector3(R * sin(th) * cos(ph), R * cos(th), -R * sin(th) * sin(ph))
	sph.verts = vs
	sph.rebuild()
	var st0 := rad_stats(sph, ids)
	var before := sph.verts.duplicate()
	var loops := KMeshEdgeFlow.loops_of(sph, select_run(sph, ids, true))
	var t0 := Time.get_ticks_usec()
	var res := KMeshEdgeFlow.relax(sph, loops, 100)
	var ms100 := (Time.get_ticks_usec() - t0) / 1000.0
	var st1 := rad_stats(sph, ids)
	var off := 0.0
	for v in ids:
		off = maxf(off, absf(sph.verts[v].length() - R))
	var drop := st0.y / maxf(st1.y, 1e-12)
	ok(loops.size() == 1 and loops[0]["closed"] and st0.y > 1e-3 and drop >= 10.0,
		"1b jittered ring: radius std %.3f mm -> %.4f mm (%.0f x, bar >= 10 x; the jitter's std > 1 mm: %s); %d verts moved, %.0f ms for 100 passes" % [st0.y * 1000, st1.y * 1000, drop, st0.y > 1e-3, res["moved"], ms100])
	ok(off <= 1e-4, "1c every relaxed vert within %.9f m of the sphere (bar 1e-4)" % off)
	ok(absf(st1.x - st0.x) / st0.x <= 0.02, "1d mean radius %.2f mm -> %.2f mm (%.2f %%, bar 2 %%: no shrink to the pole)" % [st0.x * 1000, st1.x * 1000, 100.0 * absf(st1.x - st0.x) / st0.x])
	ok(others_exact(before, sph, ids), "5a relax: every vert off the loop bit-exact")
	ok(undo_ok(sph, func(): KMeshEdgeFlow.relax(sph, loops, 5)), "6a relax = one 'move' undo step, undo exact, redo exact")
	sph.verts = before
	sph.rebuild()
	t0 = Time.get_ticks_usec()
	KMeshEdgeFlow.relax(sph, loops, 10)
	var ms10 := (Time.get_ticks_usec() - t0) / 1000.0
	ok(ms10 < 500.0, "7 relax 10 on the 32-vert loop: %.0f ms (bar 500)" % ms10)

	# 2 straighten ----------------------------------------------------------------------------------------------
	var pl := KMeshPrims.plane(1.0, 1.0, 8, 8)
	var row := []
	for i in pl.verts.size():
		if absf(pl.verts[i].z) < 1e-6:
			row.append(i)
	row.sort_custom(func(a, b): return pl.verts[a].x < pl.verts[b].x)
	var rid := PackedInt32Array(row)
	vs = pl.verts
	for i in range(1, rid.size() - 1):
		vs[rid[i]] += Vector3(rng.randf_range(-0.02, 0.02), rng.randf_range(-0.02, 0.02), rng.randf_range(-0.02, 0.02))
	pl.verts = vs
	pl.rebuild()
	before = pl.verts.duplicate()
	var rl := KMeshEdgeFlow.loops_of(pl, select_run(pl, rid, false))
	KMeshEdgeFlow.straighten(pl, rl)
	var a := pl.verts[rid[0]]
	var b := pl.verts[rid[rid.size() - 1]]
	var dev := 0.0
	var gmin := INF
	var gmax := 0.0
	for i in rid.size():
		var p := pl.verts[rid[i]]
		var t := (p - a).dot(b - a) / (b - a).length_squared()
		dev = maxf(dev, p.distance_to(a.lerp(b, t)))
		if i > 0:
			var g := p.distance_to(pl.verts[rid[i - 1]])
			gmin = minf(gmin, g)
			gmax = maxf(gmax, g)
	ok(rid.size() == 9 and rl.size() == 1 and not rl[0]["closed"] and dev <= 1e-6 and gmax - gmin <= 1e-6 and a == before[rid[0]] and b == before[rid[8]],
		"2a straighten 9-vert run: off the line %.9f (bar 1e-6), gaps %.6f..%.6f (spread %.9f, bar 1e-6), ends kept" % [dev, gmin, gmax, gmax - gmin])
	ok(others_exact(before, pl, rid), "5b straighten: every vert off the run bit-exact")
	pl.verts = before
	pl.rebuild()
	ok(undo_ok(pl, func(): KMeshEdgeFlow.straighten(pl, rl)), "6b straighten = one 'move' undo step, undo exact, redo exact")
	# on the surface: 9 verts of a latitude ring of the sphere
	var s2 := KMeshPrims.uv_sphere(R, 32, 16)
	var lat := ring_at(s2, sphere_y(11))
	var run := lat.slice(0, 9)
	before = s2.verts.duplicate()
	KMeshEdgeFlow.straighten(s2, KMeshEdgeFlow.loops_of(s2, select_run(s2, run, false)), true)
	var pa := s2.verts[run[0]]
	var pb := s2.verts[run[8]]
	var gc := pa.cross(pb).normalized()
	var son := 0.0
	var pln := 0.0
	gmin = INF
	gmax = 0.0
	for i in run.size():
		var p := s2.verts[run[i]]
		son = maxf(son, absf(p.length() - R))
		pln = maxf(pln, absf(p.dot(gc)))
		if i > 0:
			var g := p.distance_to(s2.verts[run[i - 1]])
			gmin = minf(gmin, g)
			gmax = maxf(gmax, g)
	var moved_gc := s2.verts[run[4]].distance_to(before[run[4]])
	ok(son <= 1e-4 and pln <= 1e-4 and (gmax - gmin) / gmax <= 0.01 and moved_gc > 1e-3,
		"2b straighten on the surface: off the sphere %.9f, off the great circle's plane %.9f (bars 1e-4), gaps spread %.3f %% (bar 1 %%); the middle vert moved %.1f mm" % [son, pln, 100.0 * (gmax - gmin) / gmax, moved_gc * 1000])
	ok(others_exact(before, s2, run), "5c straighten on the surface: every vert off the run bit-exact")

	# 3 set flow ------------------------------------------------------------------------------------------------
	var cyl := KMeshPrims.cylinder(R, 1.0, 32, 8)
	var mid := ring_at(cyl, 0.0)
	vs = cyl.verts
	for v in mid:
		vs[v] = Vector3(vs[v].x * 0.8, vs[v].y, vs[v].z * 0.8)
	cyl.verts = vs
	cyl.rebuild()
	before = cyl.verts.duplicate()
	var cl := KMeshEdgeFlow.loops_of(cyl, select_run(cyl, mid, true))
	var fr := KMeshEdgeFlow.set_flow(cyl, cl, 1.0)
	var rerr := 0.0
	var yerr := 0.0
	for v in mid:
		rerr = maxf(rerr, absf(Vector2(cyl.verts[v].x, cyl.verts[v].z).length() - R) / R)
		yerr = maxf(yerr, absf(cyl.verts[v].y))
	ok(mid.size() == 32 and fr["moved"] == 32 and rerr <= 0.01 and yerr <= 1e-6, "3a set flow 1 on the cylinder ring pushed to 0.8 r: %d verts moved, radius off %.4f %% (bar 1 %%), height off %.9f" % [fr["moved"], rerr * 100, yerr])
	ok(others_exact(before, cyl, mid), "5d set flow: every vert off the loop bit-exact")
	cyl.verts = before
	cyl.rebuild()
	ok(undo_ok(cyl, func(): KMeshEdgeFlow.set_flow(cyl, cl, 1.0)), "6c set flow = one 'move' undo step, undo exact, redo exact")
	cyl.verts = before
	cyl.rebuild()
	KMeshEdgeFlow.set_flow(cyl, cl, 0.5)
	var herr := 0.0
	for v in mid:
		herr = maxf(herr, absf(Vector2(cyl.verts[v].x, cyl.verts[v].z).length() - 0.9 * R) / (0.9 * R))
	ok(herr <= 0.01, "3b set flow 0.5: radius at 0.9 r within %.4f %% (bar 1 %%)" % (herr * 100))
	var s3 := KMeshPrims.uv_sphere(R, 32, 16)
	var eq := ring_at(s3, sphere_y(8))
	vs = s3.verts
	for v in eq:
		vs[v] *= 0.9
	s3.verts = vs
	s3.rebuild()
	KMeshEdgeFlow.set_flow(s3, KMeshEdgeFlow.loops_of(s3, select_run(s3, eq, true)), 1.0)
	var serr := 0.0
	for v in eq:
		serr = maxf(serr, absf(s3.verts[v].length() - R) / R)
	ok(eq.size() == 32 and serr <= 0.01, "3c set flow 1 on the sphere's equator pushed in 10 %%: radius off %.4f %% (bar 1 %%)" % (serr * 100))

	# 4 even spacing --------------------------------------------------------------------------------------------
	var s4 := KMeshPrims.uv_sphere(R, 32, 16)
	var lp := ring_at(s4, sphere_y(6))
	vs = s4.verts
	var th6 := PI * (1.0 - 6.0 / 16)
	for i in lp.size():
		var ph := atan2(-vs[lp[i]].z, vs[lp[i]].x) + rng.randf_range(-0.4, 0.4) * TAU / 32.0
		vs[lp[i]] = Vector3(R * sin(th6) * cos(ph), R * cos(th6), -R * sin(th6) * sin(ph))
	s4.verts = vs
	s4.rebuild()
	before = s4.verts.duplicate()
	var old := PackedVector3Array()
	for v in lp:
		old.append(before[v])
	old.append(old[0])
	KMeshEdgeFlow.even_space(s4, KMeshEdgeFlow.loops_of(s4, select_run(s4, lp, true)))
	var res4 := arc_gaps(old, lp, s4, true)
	ok(res4.x <= 1e-6 and res4.y <= 1e-5, "4a even spacing on a closed loop: off the old polyline %.9f (bar 1e-6), arc gaps spread %.9f m (bar 1e-5)" % [res4.x, res4.y])
	ok(others_exact(before, s4, lp), "5e even spacing: every vert off the loop bit-exact")
	s4.verts = before
	s4.rebuild()
	ok(undo_ok(s4, func(): KMeshEdgeFlow.even_space(s4, KMeshEdgeFlow.loops_of(s4, select_run(s4, lp, true)))), "6d even spacing = one 'move' undo step, undo exact, redo exact")
	s4.verts = before
	s4.rebuild()
	var op_run := lp.slice(0, 12)
	old = PackedVector3Array()
	for v in op_run:
		old.append(before[v])
	KMeshEdgeFlow.even_space(s4, KMeshEdgeFlow.loops_of(s4, select_run(s4, op_run, false)))
	var res5 := arc_gaps(old, op_run, s4, false)
	ok(res5.x <= 1e-6 and res5.y <= 1e-5 and s4.verts[op_run[0]] == before[op_run[0]] and s4.verts[op_run[11]] == before[op_run[11]],
		"4b even spacing on an open 12-vert run: off %.9f, arc gaps spread %.9f, ends kept" % [res5.x, res5.y])

	# 6 the MeshTools rows ----------------------------------------------------------------------------------------
	var rows := {}
	for t in MeshTools.TOOLS:
		if String(t["do"]).begins_with("op:edgeflow_"):
			rows[String(t["do"]).substr(3)] = t
	var mn := FakeMain.new()
	var ui := FakeUI.new()
	mn.kmed = ui
	var all_ok := rows.size() == 5
	var lines := []
	for nm in ["edgeflow_relax", "edgeflow_straighten", "edgeflow_straighten_surface", "edgeflow_flow", "edgeflow_space"]:
		for prop_on in [false, true]:
			var m := KMeshPrims.uv_sphere(R, 32, 16)
			var ring := ring_at(m, sphere_y(5))
			var sub := ring if not nm.begins_with("edgeflow_straighten") else ring.slice(0, 9)
			vs = m.verts
			for v in sub:
				vs[v] = vs[v] * rng.randf_range(0.97, 1.03)
			m.verts = vs
			m.rebuild()
			ui.mesh = m
			ui.sel = select_run(m, sub, not nm.begins_with("edgeflow_straighten"))
			ui.prop.on = prop_on
			ui.undo = KMeshUndo.new()
			var b0 := m.verts.duplicate()
			mn.said = ""
			MeshTools.op(nm, mn)
			var good: bool = ui.undo.steps.size() == 1 and others_exact(b0, m, sub) and m.verts != b0 and mn.said.contains("one undo step")
			all_ok = all_ok and good
			if not prop_on:
				lines.append("%s %s" % [nm.trim_prefix("edgeflow_"), "ok" if good else "BAD(%s)" % mn.said])
	ok(all_ok, "6e the 5 MeshTools rows (%d found): one undo step each, unselected exact, proportional on or off: %s" % [rows.size(), ", ".join(lines)])
	ui.sel = KMeshSelect.new(ui.mesh, KMeshSelect.EDGE)
	ui.undo = KMeshUndo.new()
	MeshTools.op("edgeflow_relax", mn)
	ok(ui.undo.steps.is_empty() and mn.said.contains("no edge loop selected"), "6f nothing selected: no step kept; said: %s" % mn.said)
	mn.free()

	print("edgeflow: %d failures" % fails)
	quit(1 if fails > 0 else 0)


## each new vert's arc-length parameter on the old polyline: (max distance off it, spread of the gaps)
func arc_gaps(old: PackedVector3Array, ids: PackedInt32Array, m: KMesh, closed: bool) -> Vector2:
	var cum := PackedFloat64Array([0.0])
	for j in range(1, old.size()):
		cum.append(cum[j - 1] + old[j].distance_to(old[j - 1]))
	var off := 0.0
	var ss := []
	for i in ids.size():
		var p := m.verts[ids[i]]
		var best := INF
		var bs := 0.0
		for j in old.size() - 1:
			var d := old[j + 1] - old[j]
			var t := clampf((p - old[j]).dot(d) / d.length_squared(), 0.0, 1.0)
			var dd := p.distance_to(old[j] + d * t)
			if dd < best:
				best = dd
				bs = cum[j] + t * d.length()
		off = maxf(off, best)
		ss.append(bs)
	if closed:
		ss.append(cum[cum.size() - 1])
	var gmin := INF
	var gmax := 0.0
	for i in range(1, ss.size()):
		gmin = minf(gmin, ss[i] - ss[i - 1])
		gmax = maxf(gmax, ss[i] - ss[i - 1])
	return Vector2(off, gmax - gmin)
