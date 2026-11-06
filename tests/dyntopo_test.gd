extends SceneTree
## godot --headless --path . -s tests/dyntopo_test.gd     (L52: GAP_AUDIT Sculpt item 1, dynamic topology; scripts/kmesh_dyntopo.gd, native/src/kine_dyntopo_native.cpp)
## Under the brush (centre c, radius r) edges longer than L_max = detail * r are split and edges shorter than 0.4 * L_max are collapsed.
## Bars, written BEFORE the code and never moved after a run (an unfit bar goes in the report as a flag):
##   1 BAND     after refine on an icosphere (r 0.5, 5120 tris, edge ~0.04) with the brush at (0.5, 0, 0), r 0.12: every edge with both ends in the
##              brush lies in [0.4, 1.0] * L_max +-10 % (so [0.36, 1.1] L_max). Three strokes: FINE (detail 0.25: splits), COARSE (detail 1.0: collapses),
##              and FINE then COARSE on the same mesh (both ways). Also: the tri count moved the right way (FINE up, COARSE down).
##   2 OUTSIDE  the edges with both ends and the midpoint outside the brush are the SAME set, by position (hash), before and after
##   3 MANIFOLD every edge in exactly 2 triangles, every directed edge once (winding agrees), Euler 2, adjacent face normals dot < 0 count = 0,
##              no zero-area triangle
##   4 SPEED    one stroke step on a 200k-triangle sheet (316 x 316 grid) <= 16 ms native (median of 5, arrays in -> arrays out)
##   5 EQUAL    native == GDScript on 3 meshes x 2 strokes: same vert count, tri count, splits, collapses; positions within 1e-5; tris identical
##   6 UNDO     KMeshUndo around a dyntopo step: Ctrl+Z puts the exact hash of verts + faces back (and redo goes forward again)
##   7 STROKE   KMeshSculpt with params dyntopo: a draw stroke across the sphere adds triangles, stays manifold, no flipped normals, one undo step
##   8 UI       the SCULPT page has a "Dynamic detail" check box (real click toggles ui.dyntopo), a real drag with it on adds triangles, one undo step
##              restores the exact hash
##   9 TOOL     agent tool dyntopo in AgentTools.MCP_EXTRA and tools/mcp/poser_mcp.py, and its serve returns the numbers (splits, collapses, band)
##  10 PLANTED the checkers catch planted faults: one flipped triangle (flip count), one duplicated triangle (non-manifold), an unrefined mesh (band),
##              one nudged outside vertex (outside hash), a wrong-order triangle swap (equality)
const TOL := 1e-5
var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


# ------------------------------------------------------------------ meshes
static func ico(level: int, rad: float) -> Dictionary:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var v := PackedVector3Array([Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
		Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)])
	var f := PackedInt32Array([0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1])
	for i in v.size():
		v[i] = v[i].normalized()
	for _l in level:
		var cache := {}
		var nf := PackedInt32Array()
		for k in range(0, f.size(), 3):
			var mid := []
			for e in 3:
				var a := f[k + e]
				var b := f[k + (e + 1) % 3]
				var key := mini(a, b) * 100000000 + maxi(a, b)
				if not cache.has(key):
					cache[key] = v.size()
					v.append(((v[a] + v[b]) * 0.5).normalized())
				mid.append(cache[key])
			nf.append_array(PackedInt32Array([f[k], mid[0], mid[2], mid[0], f[k + 1], mid[1], mid[2], mid[1], f[k + 2], mid[0], mid[1], mid[2]]))
		f = nf
	for i in v.size():
		v[i] *= rad
	return {"verts": v, "tris": f}


## n x n quads of a flat sheet in the xz plane, 1 m wide, lightly curved so the normals are not all equal: 2 n^2 triangles, open boundary
static func sheet(n: int) -> Dictionary:
	var v := PackedVector3Array()
	v.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			var x := float(i) / n - 0.5
			var z := float(j) / n - 0.5
			v[j * (n + 1) + i] = Vector3(x, 0.05 * sin(x * 4.0) * cos(z * 3.0), z)
	var f := PackedInt32Array()
	f.resize(n * n * 6)
	var k := 0
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			var b := a + 1
			var c := a + n + 1
			var d := c + 1
			f[k] = a
			f[k + 1] = c
			f[k + 2] = b
			f[k + 3] = b
			f[k + 4] = c
			f[k + 5] = d
			k += 6
	return {"verts": v, "tris": f}


# ------------------------------------------------------------------ checkers (independent of the code under test)
static func ekey(a: int, b: int) -> int:
	return (mini(a, b) << 32) | maxi(a, b)


static func pkey(p: Vector3) -> String:
	return "%.6f,%.6f,%.6f" % [p.x, p.y, p.z]


## {edges: key -> tri count, directed_dup, non2, euler, flips, degenerate}
static func topo(v: PackedVector3Array, t: PackedInt32Array) -> Dictionary:
	var ec := {}
	var dd := {}
	var dup := 0
	var fn := []
	var degen := 0
	for k in range(0, t.size(), 3):
		var tri := [t[k], t[k + 1], t[k + 2]]
		for e in 3:
			var a: int = tri[e]
			var b: int = tri[(e + 1) % 3]
			ec[ekey(a, b)] = int(ec.get(ekey(a, b), 0)) + 1
			var dk := (a << 32) | b
			if dd.has(dk):
				dup += 1
			dd[dk] = true
		var n := (v[tri[1]] - v[tri[0]]).cross(v[tri[2]] - v[tri[0]])
		if n.length() < 1e-12:
			degen += 1
		fn.append(n.normalized())
	var non2 := 0
	for k in ec:
		if ec[k] != 2:
			non2 += 1
	# adjacent face normals: build edge -> faces
	var ef := {}
	for k in range(0, t.size(), 3):
		for e in 3:
			var key := ekey(t[k + e], t[k + (e + 1) % 3])
			if not ef.has(key):
				ef[key] = []
			ef[key].append(k / 3)
	var flips := 0
	for key in ef:
		var l: Array = ef[key]
		if l.size() == 2 and (fn[l[0]] as Vector3).dot(fn[l[1]]) < 0.0:
			flips += 1
	var used := {}
	for i in t.size():
		used[t[i]] = true
	return {"ec": ec, "dup": dup, "non2": non2, "flips": flips, "degen": degen, "euler": used.size() - ec.size() + t.size() / 3}


static func band(v: PackedVector3Array, t: PackedInt32Array, c: Vector3, r: float, lmax: float) -> Dictionary:
	var lo := 0.4 * lmax * 0.9
	var hi := lmax * 1.1
	var seen := {}
	var n := 0
	var bad := 0
	var mn := 1e9
	var mx := 0.0
	for k in range(0, t.size(), 3):
		for e in 3:
			var a := t[k + e]
			var b := t[k + (e + 1) % 3]
			var key := ekey(a, b)
			if seen.has(key):
				continue
			seen[key] = true
			if v[a].distance_to(c) <= r and v[b].distance_to(c) <= r:
				var l := v[a].distance_to(v[b])
				n += 1
				mn = minf(mn, l)
				mx = maxf(mx, l)
				if l < lo or l > hi:
					bad += 1
	return {"n": n, "bad": bad, "min": mn, "max": mx, "lo": lo, "hi": hi}


## hash of the edges with both ends AND the midpoint outside the ball, by position
static func outside_hash(v: PackedVector3Array, t: PackedInt32Array, c: Vector3, r: float) -> int:
	var keys := []
	var seen := {}
	for k in range(0, t.size(), 3):
		for e in 3:
			var a := t[k + e]
			var b := t[k + (e + 1) % 3]
			var key := ekey(a, b)
			if seen.has(key):
				continue
			seen[key] = true
			if v[a].distance_to(c) > r and v[b].distance_to(c) > r and ((v[a] + v[b]) * 0.5).distance_to(c) > r:
				var ka := pkey(v[a])
				var kb := pkey(v[b])
				keys.append(ka + "|" + kb if ka < kb else kb + "|" + ka)
	keys.sort()
	return hash(keys)


static func mesh_hash(v: PackedVector3Array, f: Array) -> int:
	return hash([v, f])


func tri_faces(t: PackedInt32Array) -> Array:
	var f := []
	for k in range(0, t.size(), 3):
		f.append(PackedInt32Array([t[k], t[k + 1], t[k + 2]]))
	return f


# ------------------------------------------------------------------ the run
func _init() -> void:
	var s := ico(4, 0.5)
	var c := Vector3(0.5, 0, 0)
	var r := 0.12
	var edge0 := 0.0
	var v0: PackedVector3Array = s["verts"]
	var t0: PackedInt32Array = s["tris"]
	edge0 = v0[t0[0]].distance_to(v0[t0[1]])
	print("   icosphere: %d verts %d tris, edge ~%.1f mm; brush r %.0f mm at +x" % [v0.size(), t0.size() / 3, edge0 * 1000.0, r * 1000.0])
	var base_topo := topo(v0, t0)
	ok(base_topo["non2"] == 0 and base_topo["euler"] == 2 and base_topo["flips"] == 0 and base_topo["dup"] == 0, "(0) the starting icosphere is a clean closed manifold (euler %d, flips %d)" % [base_topo["euler"], base_topo["flips"]])
	# ---- bars 1, 2, 3 on three strokes
	var h_out0 := outside_hash(v0, t0, c, r)
	var fine: Dictionary = KMeshDyntopo.refine(v0, t0, c, r, 0.25)
	var coarse: Dictionary = KMeshDyntopo.refine(v0, t0, c, r, 1.0)
	var fc: Dictionary = KMeshDyntopo.refine(fine["verts"], fine["tris"], c, r, 1.0)
	var both: Dictionary = KMeshDyntopo.refine(coarse["verts"], coarse["tris"], c, r, 0.25)
	var cases := [["FINE d0.25", fine, 0.25, 1], ["COARSE d1.0", coarse, 1.0, -1], ["FINE then COARSE", fc, 1.0, -1], ["COARSE then FINE", both, 0.25, 1]]
	var nt0 := t0.size() / 3
	for cs in cases:
		var res: Dictionary = cs[1]
		var lmax: float = float(cs[2]) * r
		var b := band(res["verts"], res["tris"], c, r, lmax)
		var tp := topo(res["verts"], res["tris"])
		var nt: int = (res["tris"] as PackedInt32Array).size() / 3
		var dir_ok: bool = (nt > nt0) if int(cs[3]) > 0 else (nt < nt0)
		if cs[0] == "FINE then COARSE":
			dir_ok = nt < (fine["tris"] as PackedInt32Array).size() / 3
		if cs[0] == "COARSE then FINE":
			dir_ok = nt > (coarse["tris"] as PackedInt32Array).size() / 3
		ok(b["n"] > 20 and b["bad"] == 0 and dir_ok, "(1) BAND %s: %d in-brush edges, %d outside [%.1f, %.1f] mm, range %.1f..%.1f mm, tris %d -> %d (splits %d, collapses %d)" % [cs[0], b["n"], b["bad"], b["lo"] * 1000.0, b["hi"] * 1000.0, b["min"] * 1000.0, b["max"] * 1000.0, nt0, nt, res.get("splits", -1), res.get("collapses", -1)])
		ok(outside_hash(res["verts"], res["tris"], c, r) == h_out0 or cs[0].contains("then"), "(2) OUTSIDE %s: edges outside the brush are the same set (hash %d)" % [cs[0], h_out0]) if not cs[0].contains("then") else null
		ok(tp["non2"] == 0 and tp["dup"] == 0 and tp["euler"] == 2 and tp["flips"] == 0 and tp["degen"] == 0, "(3) MANIFOLD %s: non-2 edges %d, repeated directed edges %d, euler %d, flipped %d, degenerate %d" % [cs[0], tp["non2"], tp["dup"], tp["euler"], tp["flips"], tp["degen"]])
	ok(outside_hash(fc["verts"], fc["tris"], c, r) == h_out0 and outside_hash(both["verts"], both["tris"], c, r) == h_out0, "(2) OUTSIDE after two strokes in a row: still the same set")
	# ---- bar 4 speed
	var sh := sheet(316)
	var sv: PackedVector3Array = sh["verts"]
	var st: PackedInt32Array = sh["tris"]
	var sc := Vector3(0.0, 0.0, 0.0)
	var times := []
	var last := {}
	KMeshDyntopo.refine(sv, st, sc, 0.04, 0.3)   # warm
	for i in 5:
		var t0u := Time.get_ticks_usec()
		last = KMeshDyntopo.refine(sv, st, sc, 0.04, 0.3)
		times.append((Time.get_ticks_usec() - t0u) / 1000.0)
	times.sort()
	var med: float = times[2]
	print("   sheet: %d tris -> %d tris; step times ms %s; native=%s" % [st.size() / 3, (last["tris"] as PackedInt32Array).size() / 3, str(times), str(last.get("native"))])
	ok(st.size() / 3 >= 199000 and bool(last.get("native", false)) and med <= 16.0, "(4) SPEED 200k-tri stroke step native median %.2f ms (bar <= 16)" % med)
	var sb := band(last["verts"], last["tris"], sc, 0.04, 0.3 * 0.04)
	ok(sb["bad"] == 0 and sb["n"] > 50, "(4) the 200k step also meets the band: %d edges in brush, %d outside, range %.2f..%.2f mm" % [sb["n"], sb["bad"], sb["min"] * 1000.0, sb["max"] * 1000.0])
	# ---- bar 5 native == GDScript
	var ico3 := ico(3, 0.5)
	var meshes := [["ico4", s], ["ico3", ico3], ["sheet40", sheet(40)]]
	var all_eq := true
	var worst := 0.0
	for mm in meshes:
		var mv: PackedVector3Array = mm[1]["verts"]
		var mt: PackedInt32Array = mm[1]["tris"]
		var mc := Vector3(0.5, 0, 0) if mm[0] != "sheet40" else Vector3(0.0, 0.0, 0.0)
		var mr := 0.12 if mm[0] != "sheet40" else 0.2
		for det in [0.25, 1.0]:
			var a: Dictionary = KMeshDyntopo.refine(mv, mt, mc, mr, det)
			var g: Dictionary = KMeshDyntopo.refine_gd(mv, mt, mc, mr, det * mr, 8)
			var same: bool = a["splits"] == g["splits"] and a["collapses"] == g["collapses"] and (a["verts"] as PackedVector3Array).size() == (g["verts"] as PackedVector3Array).size() and a["tris"] == g["tris"] and bool(a.get("native", false))
			var d := 0.0
			if same:
				for i in (a["verts"] as PackedVector3Array).size():
					d = maxf(d, (a["verts"][i] - g["verts"][i]).length())
			worst = maxf(worst, d)
			all_eq = all_eq and same and d <= TOL and int(a["splits"]) + int(a["collapses"]) > 0
			print("     %s detail %.2f: native splits %d collapses %d | gd splits %d collapses %d | verts %d/%d tris %d/%d maxdiff %.2e" % [mm[0], det, a["splits"], a["collapses"], g["splits"], g["collapses"], (a["verts"] as PackedVector3Array).size(), (g["verts"] as PackedVector3Array).size(), (a["tris"] as PackedInt32Array).size() / 3, (g["tris"] as PackedInt32Array).size() / 3, d])
	ok(all_eq and worst <= TOL, "(5) EQUAL native == GDScript on 3 meshes x 2 strokes, worst position diff %.2e (bar %.0e)" % [worst, TOL])
	# ---- bar 6 undo
	var km := KMesh.new().from_arrays(v0, tri_faces(t0))
	var h0 := mesh_hash(km.verts, km.faces)
	var undo := KMeshUndo.new()
	undo.begin(km)
	var stats := KMeshDyntopo.step_mesh(km, c, r, 0.25)
	var stp := undo.commit("dyntopo")
	var h1 := mesh_hash(km.verts, km.faces)
	undo.undo()
	var h2 := mesh_hash(km.verts, km.faces)
	undo.redo()
	var h3 := mesh_hash(km.verts, km.faces)
	ok(not stp.is_empty() and h1 != h0 and h2 == h0 and h3 == h1 and km.is_manifold() and km.triangle_count() == (fine["tris"] as PackedInt32Array).size() / 3, "(6) UNDO: step_mesh changed the hash (%d splits), undo restored the exact hash %s, redo went forward again %s, mesh manifold %s" % [stats.get("splits", -1), h2 == h0, h3 == h1, km.is_manifold()])
	# ---- bar 7 sculpt stroke with dyntopo
	var sm := KMesh.new().from_arrays(v0, tri_faces(t0))
	var sh0 := mesh_hash(sm.verts, sm.faces)
	var su := KMeshUndo.new()
	var sc2 := KMeshSculpt.new()
	su.begin(sm)
	sc2.begin(sm, {"brush": "draw", "radius": 0.12, "strength": 0.004, "sym_x": false, "dyntopo": true, "detail": 0.3})
	for k in 7:
		var ang := -0.3 + 0.1 * k
		var pt := Vector3(cos(ang), 0.0, sin(ang)) * 0.5
		sc2.to(pt, pt.normalized(), 1.0)
	sc2.end()
	var sstep := su.commit("sculpt draw")
	var tp2 := topo(sm.verts, PackedInt32Array(_flat(sm.faces)))
	var n_after: int = sm.faces.size()
	ok(n_after > nt0 and tp2["non2"] == 0 and tp2["dup"] == 0 and tp2["flips"] == 0 and tp2["degen"] == 0 and not sstep.is_empty() and su.steps.size() == 1,
		"(7) STROKE dyntopo draw: tris %d -> %d, non-2 edges %d, flipped %d, degenerate %d, undo steps %d" % [nt0, n_after, tp2["non2"], tp2["flips"], tp2["degen"], su.steps.size()])
	su.undo()
	ok(mesh_hash(sm.verts, sm.faces) == sh0, "(7) STROKE undo restores the exact hash")
	# ---- bar 10 planted faults (the checkers must SEE them)
	var fv: PackedVector3Array = fine["verts"]
	var ft: PackedInt32Array = fine["tris"]
	var pf := ft.duplicate()
	var tmp := pf[1]
	pf[1] = pf[2]
	pf[2] = tmp
	var tpf := topo(fv, pf)
	ok(tpf["flips"] > 0 or tpf["dup"] > 0, "(10) PLANTED flipped triangle: flips %d, repeated directed edges %d (must be > 0)" % [tpf["flips"], tpf["dup"]])
	var pd := ft.duplicate()
	pd.append_array(PackedInt32Array([ft[0], ft[1], ft[2]]))
	ok(topo(fv, pd)["non2"] > 0, "(10) PLANTED duplicated triangle: non-2 edges %d (must be > 0)" % topo(fv, pd)["non2"])
	var bu := band(v0, t0, c, r, 0.25 * r)
	ok(bu["bad"] > 0, "(10) PLANTED unrefined mesh: %d edges outside the band (must be > 0)" % bu["bad"])
	var nv := fv.duplicate()
	var far := 0
	for i in nv.size():
		if nv[i].distance_to(c) > r * 2.0:
			far = i
			break
	nv[far] += Vector3(0.001, 0, 0)
	ok(outside_hash(nv, ft, c, r) != outside_hash(fv, ft, c, r), "(10) PLANTED nudged outside vertex: the outside hash changes")
	var sw := (fine["tris"] as PackedInt32Array).duplicate()
	var s0 := sw[3]
	sw[3] = sw[6]
	sw[6] = s0
	ok(sw != fine["tris"], "(10) PLANTED swapped triangle: the equality comparison sees different tris")
	# ---- bar 8 UI
	await _ui_bars()
	# ---- bar 9 tool
	await _tool_bars()
	print("dyntopo: %d fail" % fails)
	quit(1 if fails > 0 else 0)


static func _flat(faces: Array) -> Array:
	var o := []
	for f in faces:
		for i in (f as PackedInt32Array):
			o.append(i)
	return o


func _ui_bars() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._sculpt_start()
	await idle(3)
	var ui = m.ksc
	var cb: CheckBox = null
	for n in _walk(root, []):
		if n is CheckBox and String((n as CheckBox).text).contains("Dynamic detail"):
			cb = n
	ok(cb != null and cb.is_visible_in_tree() and ui.get("dyntopo") == false, "(8) UI: a visible 'Dynamic detail' check box exists, off by default")
	if cb == null:
		return
	var wc: Vector3 = ui.view.global_position
	m._turn_to(0.0, 0.0, 1.6, wc, false)
	await idle(6)
	var c := cb.get_global_rect().get_center()
	await _click(c)
	ok(ui.dyntopo == true and cb.button_pressed, "(8) UI: a real click on the box turns dyntopo on")
	var h0 := mesh_hash(ui.mesh.verts, ui.mesh.faces)
	var f0: int = ui.mesh.faces.size()
	var u0: int = ui.undo.steps.size()
	var cs: Vector2 = (m.cam as Camera3D).unproject_position(wc)
	await _drag(cs + Vector2(-30, 0), cs + Vector2(30, 0))
	var f1: int = ui.mesh.faces.size()
	ok(f1 != f0 and ui.undo.steps.size() == u0 + 1 and ui.mesh.is_manifold(), "(8) UI: a real drag with it on changes the triangle count %d -> %d, one undo step, manifold %s" % [f0, f1, ui.mesh.is_manifold()])
	var ev := InputEventKey.new()
	ev.keycode = KEY_Z
	ev.physical_keycode = KEY_Z
	ev.ctrl_pressed = true
	for down in [true, false]:
		ev.pressed = down
		root.push_input(ev)
		await process_frame
	await idle(3)
	ok(mesh_hash(ui.mesh.verts, ui.mesh.faces) == h0, "(8) UI: Ctrl+Z restores the exact hash of verts and faces")


func _tool_bars() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/agent_tools.gd")
	var py := FileAccess.get_file_as_string("res://tools/mcp/poser_mcp.py")
	var in_list: bool = (AgentTools.MCP_EXTRA as Array).has("dyntopo")
	var r := DyntopoServe.serve(m, {"detail": 0.25, "radius": 0.12})
	var res: Dictionary = r.get("result", {})
	ok(in_list and py.contains("\"dyntopo\"") and src.contains("\"dyntopo\":") and bool(r.get("ok", false)) and int(res.get("splits", 0)) > 0 and int(res.get("band_bad", -1)) == 0 and res.has("tris_after"),
		"(9) TOOL: dyntopo is in MCP_EXTRA %s and poser_mcp.py %s; serve -> %s" % [in_list, py.contains("\"dyntopo\""), str(res).left(180)])


func _walk(n: Node, out: Array) -> Array:
	out.append(n)
	for ch in n.get_children(true):
		_walk(ch, out)
	return out


func _click(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e)
	await process_frame
	for down in [true, false]:
		var b := InputEventMouseButton.new()
		b.button_index = MOUSE_BUTTON_LEFT
		b.pressed = down
		b.position = p
		b.global_position = p
		if down:
			b.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(b)
		await process_frame
	await idle(3)


func _drag(a: Vector2, b: Vector2, steps := 8) -> void:
	var d := InputEventMouseButton.new()
	d.button_index = MOUSE_BUTTON_LEFT
	d.pressed = true
	d.position = a
	d.global_position = a
	d.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(d)
	await process_frame
	for k in steps:
		var e := InputEventMouseMotion.new()
		e.position = a.lerp(b, (k + 1) / float(steps))
		e.global_position = e.position
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e)
		await process_frame
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = b
	u.global_position = b
	root.push_input(u)
	await process_frame
	await idle(3)
