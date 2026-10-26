## godot --path . -s tests/topomirror_test.gd     (ROADMAP_400 B22; scripts/kmesh_topomirror.gd; needs a window: main + keys)
## Bars, written before measuring (the mannequin's % was probed once while building the map, 100.00 % on X; the bar is
## set below it so a small regression in the seeding still shows):
##   1 GRID 21 x 11 (10 cm steps, a centre column): the right half (x > 0) displaced at random, 1..3 cm each (seed 22).
##     The topological map of the displaced grid equals the positional map of the undisplaced grid on 100 % of the verts,
##     0 unpaired. The instrument can move: the positional map of the displaced grid pairs < 10 %. The same with the grid
##     turned so the mirror is Y (axis choice), and a 20-column grid (no centre verts: the seed is an edge straddling the
##     plane)
##   2 FIND ASYMMETRY on the displaced grid lists exactly the displaced verts (+ side), and its max deviation equals the
##     largest displacement (1e-6 m)
##   3 SYMMETRIZE (+X onto -X) on the displaced grid: max deviation after < 1e-6 m, the + side bit-exact unchanged
##   4 SCULPT with the mirror on, on the displaced grid: one draw dab at x = 0.6: every moved vert's partner moved by the
##     mirrored delta (1e-7 m) and as many partners as verts under the dab; with the plain X symmetry (by position) < 10 %
##     of them follow (the instrument)
##   5 MAIN, the model preview's cube with its +X half displaced 1 cm at random, Blender keys on, the mirror on (op):
##     "find asymmetry" selects exactly the displaced verts and names the max in mm; the map op says 100.0 %;
##     G X 0.05 on 3 +X verts + 1 centre vert: each +X vert moves (0.05, 0, 0), its partner (-0.05, 0, 0) (1e-6), the
##     centre vert stays (x kept), nothing else moves, ONE KMeshUndo step, Ctrl+Z puts every vert back bit-exact;
##     G Y 0.07: the partners and the centre vert move (0, 0.07, 0) too; symmetrize op: deviation < 1e-6, one step;
##     R Z 30 on the symmetric cube: each partner is the mirror image of its vert (1e-6); world plane (the cube sits at
##     x = 1): 0 % partnered and G moves the selection only; the mirror off: G moves the selection only
##   6 THE MANNEQUIN (G01, welded body): the X map partners >= 99 % of its verts (stated, info line), every pair mutual,
##     built in < 3 s; with its right arm turned 40 deg (verts x > 0.2, about Z) the topological map is the same map
##     on >= 99.9 % of verts, while the positional map of the posed body pairs < 90 % (the instrument)
## No new panel: the ops answer in the status line (checked in 5); the highlight is the selection, drawn by KMeshView.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func tap(code: Key, ctrl := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.ctrl_pressed = ctrl
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


func typ(s: String) -> void:
	for ch in s:
		await tap(KEY_PERIOD if ch == "." else (KEY_0 + int(ch)) as Key)


## nx columns (x centred on 0), nz rows, quads
static func grid(nx: int, nz: int, d := 0.1) -> KMesh:
	var vs := PackedVector3Array()
	for j in nz:
		for i in nx:
			vs.append(Vector3((i - (nx - 1) * 0.5) * d, 0.0, j * d))
	var fs: Array = []
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			fs.append([a, a + nx, a + nx + 1, a + 1])
	return KMesh.new().from_arrays(vs, fs)


## the + side (x > 0) moved 1..3 cm in a random direction; returns the verts moved
static func displace(k: KMesh, seed_: int, lo := 0.01, hi := 0.03, ax := 0) -> PackedInt32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var out := PackedInt32Array()
	var vs := k.verts
	for v in vs.size():
		if vs[v][ax] > 1e-6:
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
			vs[v] += dir * rng.randf_range(lo, hi)
			out.append(v)
	k.verts = vs
	k._compute_normals()
	return out


static func pct_same(a: PackedInt32Array, b: PackedInt32Array) -> float:
	var n := 0
	for v in a.size():
		if a[v] == b[v]:
			n += 1
	return 100.0 * n / maxf(1.0, a.size())


static func pct_paired(a: PackedInt32Array) -> float:
	var n := 0
	for v in a:
		if v >= 0:
			n += 1
	return 100.0 * n / maxf(1.0, a.size())


func _init() -> void:
	# ---------------------------------------------------------------- 1 grids
	var g0 := grid(21, 11)
	var p0 := g0.symmetry_map(0)
	var g := grid(21, 11)
	var moved := displace(g, 22)
	var r := KMeshTopoMirror.build(g, 0, 0.0)
	var same := pct_same(r["map"], p0)
	ok(same == 100.0 and (r["unpaired"] as PackedInt32Array).is_empty() and pct_paired(p0) == 100.0,
		"1a displaced grid: topological map == the undisplaced positional map on %.1f %% of %d verts, %d unpaired (%d by connectivity)" % [same, g.verts.size(), (r["unpaired"] as PackedInt32Array).size(), r["topo_pairs"]])
	var pd := pct_paired(g.symmetry_map(0))
	ok(pd < 10.0, "1b the instrument: the positional map of the displaced grid pairs %.1f %%" % pd)
	var gy := KMesh.new().from_arrays(PackedVector3Array(Array(g.verts).map(func(p): return Vector3(p.z, p.x, p.y))), g.faces.duplicate())
	var ry := KMeshTopoMirror.build(gy, 1, 0.0)
	var rx_wrong := KMeshTopoMirror.build(gy, 0, 0.0)
	ok(pct_same(ry["map"], p0) == 100.0 and float(rx_wrong["pct"]) < 50.0,
		"1c axis Y on the turned grid: %.1f %% the same map (axis X there: %.1f %% partnered)" % [pct_same(ry["map"], p0), rx_wrong["pct"]])
	var e0 := grid(20, 11)
	var pe := e0.symmetry_map(0)
	var e := grid(20, 11)
	displace(e, 23)
	var re := KMeshTopoMirror.build(e, 0, 0.0)
	ok(pct_same(re["map"], pe) == 100.0 and int(re["centre"]) == 0, "1d 20 columns (no centre verts, a straddling seed): %.1f %% the same" % pct_same(re["map"], pe))

	# ---------------------------------------------------------------- 2 find asymmetry
	var a := KMeshTopoMirror.asymmetry(g, r["map"], 0, 0.0)
	var want := moved.duplicate()
	want.sort()
	var big := 0.0
	for v in moved:
		big = maxf(big, g.verts[v].distance_to(g0.verts[v]))
	ok(a["plus"] == want and absf(float(a["max"]) - big) < 1e-6, "2 find asymmetry: %d listed, %d displaced, the same set %s; max %.3f mm (largest displacement %.3f mm)" % [
		(a["plus"] as PackedInt32Array).size(), want.size(), str(a["plus"] == want), a["max_mm"], big * 1000.0])

	# ---------------------------------------------------------------- 3 symmetrize
	var gs := KMesh.new().from_arrays(g.verts.duplicate(), g.faces.duplicate())
	KMeshTopoMirror.symmetrize(gs, r["map"], 0, 0.0, true)
	var after := KMeshTopoMirror.asymmetry(gs, r["map"], 0, 0.0)
	var plus_same := true
	for v in moved:
		plus_same = plus_same and gs.verts[v] == g.verts[v]
	ok(float(after["max"]) < 1e-6 and plus_same, "3 symmetrize +X onto -X: max deviation %s m (was %.1f mm), + side bit-exact %s" % [str(after["max"]), a["max_mm"], str(plus_same)])

	# ---------------------------------------------------------------- 4 sculpt
	var tm := KMeshTopoMirror.new()
	tm.on = true
	var gk := KMesh.new().from_arrays(g.verts.duplicate(), g.faces.duplicate())
	var before := gk.verts.duplicate()
	var sc := KMeshSculpt.new()
	sc.begin(gk, tm.sculpt_params(gk, Transform3D.IDENTITY, {"brush": KMeshSculpt.DRAW, "radius": 0.15, "strength": 0.01, "sym_x": false}))
	sc.dab(Vector3(0.6, 0.0, 0.5), Vector3.UP, 1.0)
	var mp: PackedInt32Array = tm.last["map"]
	var src := 0
	var err := 0.0
	var follow := 0
	for v in gk.verts.size():
		if before[v].x > 1e-6 and gk.verts[v] != before[v]:
			src += 1
			var u := mp[v]
			var dv := gk.verts[v] - before[v]
			var du := gk.verts[u] - before[u]
			err = maxf(err, du.distance_to(Vector3(-dv.x, dv.y, dv.z)))
			if du != Vector3.ZERO:
				follow += 1
	var gp := KMesh.new().from_arrays(g.verts.duplicate(), g.faces.duplicate())
	var bp := gp.verts.duplicate()
	var sp := KMeshSculpt.new()
	sp.begin(gp, {"brush": KMeshSculpt.DRAW, "radius": 0.15, "strength": 0.01, "sym_x": true})
	sp.dab(Vector3(0.6, 0.0, 0.5), Vector3.UP, 1.0)
	var pf := 0
	for v in gp.verts.size():
		if bp[v].x < -1e-6 and gp.verts[v] != bp[v]:
			pf += 1
	ok(src > 3 and follow == src and err < 1e-7 and pf * 10 < src,
		"4 sculpt dab with the mirror on: %d verts moved, %d partners followed, mirror err %s m; positional X symmetry: %d follow" % [src, follow, str(err), pf])

	# ---------------------------------------------------------------- 5 main: the model preview
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._card_add()
	m._view(1)
	m.blk.set_on(true, false)
	m._kmesh_edit_start()
	await idle(3)
	var ui = m.kmed
	var mesh: KMesh = ui.mesh
	var cube0: PackedVector3Array = mesh.verts.duplicate()
	var pc := mesh.symmetry_map(0)
	var cmoved := displace(mesh, 5, 0.01, 0.01)
	var disp: PackedVector3Array = mesh.verts.duplicate()
	ui.view.mark_dirty()
	var tms := KMeshTopoMirror.get_shared()
	tms.on = false
	tms.axis = 0
	tms.space = KMeshTopoMirror.LOCAL
	var said := MeshTools.op("mirror_asym", m)
	var cw := cmoved.duplicate()
	cw.sort()
	var selv := PackedInt32Array(ui.sel.verts.keys())
	selv.sort()
	ok(selv == cw and "10.0 mm" in said and "10.0 mm" in String(m.ui_status.text), "5a find asymmetry selects the %d displaced verts (%d selected): %s" % [cw.size(), selv.size(), said])
	said = MeshTools.op("mirror_map", m)
	ok("100.0 %" in said and pct_same(tms.last["map"], pc) == 100.0, "5b map op: %s" % said)
	said = MeshTools.op("mirror_edit", m)
	ok(tms.on and "on" in said, "5c the mirror on: %s" % said)
	var plusv: Array = []
	var cen := -1
	for v in mesh.verts.size():
		if cube0[v].x > 0.1 and plusv.size() < 3:
			plusv.append(v)
		if absf(cube0[v].x) < 1e-9 and cen < 0:
			cen = v
	ui.sel.clear()
	for v in plusv + [cen]:
		ui.sel.verts[v] = true
	var u0: int = ui.undo.steps.size()
	await tap(KEY_G)
	await tap(KEY_X)
	await typ("0.05")
	await tap(KEY_ENTER)
	var e1 := 0.0
	var e2 := 0.0
	var other := 0.0
	var parts := {}
	for v in plusv:
		parts[pc[v]] = true
		e1 = maxf(e1, (mesh.verts[v] - disp[v]).distance_to(Vector3(0.05, 0, 0)))
		e2 = maxf(e2, (mesh.verts[pc[v]] - disp[pc[v]]).distance_to(Vector3(-0.05, 0, 0)))
	for v in mesh.verts.size():
		if not (v in plusv) and not parts.has(v):
			other = maxf(other, mesh.verts[v].distance_to(disp[v]))
	ok(e1 < 1e-6 and e2 < 1e-6 and other == 0.0 and ui.undo.steps.size() == u0 + 1,
		"5d G X 0.05, mirror on: verts err %s, partners (-0.05) err %s, the rest (centre vert too) moved %s, KMeshUndo steps +%d" % [str(e1), str(e2), str(other), ui.undo.steps.size() - u0])
	await tap(KEY_Z, true)
	ok(mesh.verts == disp and ui.undo.steps.size() == u0, "5e Ctrl+Z: the move and the partner moves back in one step, bit-exact")
	await tap(KEY_G)
	await tap(KEY_Y)
	await typ("0.07")
	await tap(KEY_ENTER)
	var ey := 0.0
	for v in plusv + [cen] + parts.keys():
		ey = maxf(ey, (mesh.verts[v] - disp[v]).distance_to(Vector3(0, 0.07, 0)))
	ok(ey < 1e-6 and ui.undo.steps.size() == u0 + 1, "5f G Y 0.07: verts, partners and the centre vert all rise 7 cm (err %s)" % str(ey))
	await tap(KEY_Z, true)
	said = MeshTools.op("symmetrize", m)
	var asy := KMeshTopoMirror.asymmetry(mesh, tms.last["map"], 0, 0.0)
	ok(float(asy["max"]) < 1e-6 and ui.undo.steps.size() == u0 + 1 and "one undo step" in said, "5g symmetrize op: max deviation %s m, one step: %s" % [str(asy["max"]), said])
	var sym: PackedVector3Array = mesh.verts.duplicate()
	await tap(KEY_R)
	await tap(KEY_Z)
	await typ("30")
	await tap(KEY_ENTER)
	var er := 0.0
	for v in plusv:
		er = maxf(er, mesh.verts[pc[v]].distance_to(KMeshTopoMirror.reflect(mesh.verts[v], 0, 0.0)))
	ok(er < 1e-6 and mesh.verts != sym and ui.undo.steps.size() == u0 + 2, "5h R Z 30, mirror on: each partner is its vert's mirror image (err %s)" % str(er))
	await tap(KEY_Z, true)
	said = MeshTools.op("mirror_space", m)
	var rw := tms.map_for(mesh, ui.view.global_transform)
	await tap(KEY_G)
	await tap(KEY_X)
	await typ("0.05")
	await tap(KEY_ENTER)
	var nw := 0
	for v in mesh.verts.size():
		if mesh.verts[v] != sym[v]:
			nw += 1
	ok(float(rw["pct"]) == 0.0 and nw == 4 and "world" in said, "5i world plane (x = %s in the cube's frame): %.1f %% partnered, G moved %d verts (the selection)" % [str(rw["plane"]), rw["pct"], nw])
	await tap(KEY_Z, true)
	MeshTools.op("mirror_space", m)
	MeshTools.op("mirror_edit", m)
	await tap(KEY_G)
	await tap(KEY_X)
	await typ("0.05")
	await tap(KEY_ENTER)
	nw = 0
	for v in mesh.verts.size():
		if mesh.verts[v] != sym[v]:
			nw += 1
	ok(not tms.on and nw == 4, "5j the mirror off: G moved %d verts (the selection only)" % nw)
	await tap(KEY_Z, true)
	m.blk.set_on(false, false)

	# ---------------------------------------------------------------- 6 the mannequin
	var k := BaseBody.read(m)
	var t0 := Time.get_ticks_msec()
	var rb := KMeshTopoMirror.build(k, 0, 0.0)
	var ms := Time.get_ticks_msec() - t0
	var mp0: PackedInt32Array = rb["map"]
	var mutual := true
	for v in mp0.size():
		if mp0[v] >= 0 and mp0[mp0[v]] != v:
			mutual = false
	print("info: mannequin %d verts: %.2f %% partnered on X (%d by connectivity, %d by position, %d on the plane, %d unpaired, %d pieces seeded, %d of them by shape, %d clashes)" % [
		k.verts.size(), rb["pct"], rb["topo_pairs"], rb["pos_pairs"], rb["centre"], (rb["unpaired"] as PackedInt32Array).size(), rb["seeds"], rb["shape_pairs"], rb["clashes"]])
	ok(float(rb["pct"]) >= 99.0 and mutual and ms < 3000, "6a mannequin: %.2f %% partnered, mutual %s, %d ms" % [rb["pct"], str(mutual), ms])
	var arm := PackedInt32Array()
	var piv := Vector3.ZERO
	for v in k.verts.size():
		if k.verts[v].x > 0.2:
			arm.append(v)
			piv += k.verts[v]
	piv /= float(maxi(arm.size(), 1))
	piv.x = 0.2
	var turn := Basis(Vector3.BACK, deg_to_rad(40.0))
	var kv := k.verts
	for v in arm:
		kv[v] = piv + turn * (kv[v] - piv)
	k.verts = kv
	k._compute_normals()
	var rp := KMeshTopoMirror.build(k, 0, 0.0)
	var posd := pct_paired(k.symmetry_map(0))
	ok(pct_same(rp["map"], mp0) >= 99.9 and posd < 90.0, "6b the right arm turned 40 deg (%d verts): topological map the same on %.2f %% (%d pieces by shape); positional pairs %.1f %%" % [arm.size(), pct_same(rp["map"], mp0), rp["shape_pairs"], posd])

	tms.on = false
	print("TOPOMIRROR: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
