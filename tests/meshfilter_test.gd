## godot --headless --path . -s tests/meshfilter_test.gd     (ROADMAP_400 C18; scripts/kmesh_filters.gd)
## Bars, written before measuring:
##   1 INFLATE 1 cm on the sculpt sphere (3 458 verts, r 0.3): every vert moves 1 cm (within 0.01 mm) along its own normal
##     at the start (cos > 0.99999); -1 cm deflates the same way
##   2 SMOOTH on a noisy sphere (each vert pushed out by +-3 mm, seeded): smooth 1 cuts the variance of the radius by > 2 x,
##     smooth 6 by > 5 x (measured and printed); on a CLEAN sphere smooth 6 adds < 0.01 mm^2 of radius variance and
##     shrinks the mean radius < 0.5 mm; smooth 0 moves nothing.
##     HISTORY: the first bar was "smooth 1 > 5 x" against a plain Laplacian; it measured 3.9 x, and 3 passes only 4.85 x,
##     6 passes WORSE (the plain Laplacian shrinks the cube-sphere unevenly: a clean sphere got 1.2 mm^2 of radius variance
##     from 6 passes). That was a filter defect, so the filter became HC Laplacian (no shrink) and the bars above were
##     written for it before it was measured.
##   3 SHARPEN 0.5 on the same noisy sphere: the curvature contrast (std of the signed Laplacian along the normal) grows by
##     > 1.3 x; the instrument can move: SMOOTH lowers the same number
##   4 MASK: with a per-vert float "mask" channel = 1 on the verts with x > 0 (0 elsewhere) every masked vert stays put
##     exactly under inflate, smooth and sharpen while the unmasked ones move (> 1 mm for inflate); mask 0.5 moves half
##   5 SESSION + UNDO: begin, drag-like set_amount 0.004 then 0.01 (preview from the start state, not stacked: the result
##     equals one inflate of 1 cm within 1e-6), commit = ONE undo step, undo puts every vert back exactly; cancel leaves
##     the mesh exact and keeps no step
##   6 KEYS (KMeshSculptUI, no window): L starts inflate, mouse x +100 px = 10 mm, typed "2.5" = 2.5 mm, Enter applies one
##     step; L L switches to sharpen; Esc cancels with nothing changed
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


static func noisy(amp := 0.003) -> KMesh:
	var m := KMeshSculptUI.make_sphere()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var vs := m.verts
	for v in vs.size():
		vs[v] = vs[v].normalized() * (0.3 + rng.randf_range(-amp, amp))
	m.verts = vs
	m.rebuild()
	return m


static func rvar(m: KMesh) -> float:
	var s := 0.0
	var s2 := 0.0
	for q in m.verts:
		var r := q.length()
		s += r
		s2 += r * r
	var n := float(m.verts.size())
	return s2 / n - (s / n) * (s / n)


## std of the signed Laplacian along the vert normal (a curvature contrast)
static func contrast(m: KMesh) -> float:
	var vals := PackedFloat32Array()
	var vn := m.vert_normals
	for v in m.verts.size():
		var nb := m.vert_neighbors(v)
		var mean := Vector3.ZERO
		for u in nb:
			mean += m.verts[u]
		vals.append((mean / nb.size() - m.verts[v]).dot(vn[v]))
	var s := 0.0
	for x in vals:
		s += x
	var mu := s / vals.size()
	var s2 := 0.0
	for x in vals:
		s2 += (x - mu) * (x - mu)
	return sqrt(s2 / vals.size())


static func key(ui, k: int) -> bool:
	var r := false
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.pressed = down
		r = ui.input(e) or r
	return r


func _init() -> void:
	# 1 inflate
	var worst_inf := 0.0
	for d in [0.01, -0.01]:
		var m := KMeshSculptUI.make_sphere()
		var v0 := m.verts.duplicate()
		var n0 := m.vert_normals.duplicate()
		KMeshFilters.inflate(m, d)
		var wl := 0.0
		var wc := 1.0
		for v in m.verts.size():
			var dv := m.verts[v] - v0[v]
			wl = maxf(wl, absf(dv.length() - 0.01))
			wc = minf(wc, dv.normalized().dot(n0[v] * signf(d)))
		print("  inflate %+.0f mm: worst length error %.6f mm, worst cos to the normal %.7f" % [d * 1000.0, wl * 1000.0, wc])
		worst_inf = maxf(worst_inf, wl)
		ok(wl < 1e-5 and wc > 0.99999, "1 inflate %+.0f mm: every vert moves 1 cm along its normal (worst %.6f mm)" % [d * 1000.0, wl * 1000.0])

	# 2 smooth
	var a := noisy()
	var va := rvar(a)
	var c0 := contrast(a)
	KMeshFilters.smooth(a, 1.0)
	var vb := rvar(a)
	var a3 := noisy()
	KMeshFilters.smooth(a3, 6.0)
	var v3 := rvar(a3)
	var cl := KMeshSculptUI.make_sphere()
	var cr0 := 0.0
	for q in cl.verts:
		cr0 += q.length()
	KMeshFilters.smooth(cl, 6.0)
	var cr1 := 0.0
	for q in cl.verts:
		cr1 += q.length()
	var shrink := (cr0 - cr1) / cl.verts.size()
	var cvar := rvar(cl)
	var z := noisy()
	var z0 := z.verts.duplicate()
	KMeshFilters.smooth(z, 0.0)
	print("  radius variance (mm^2): noisy %.5f, smooth 1 %.5f (factor %.2f), smooth 6 %.5f (factor %.2f); clean sphere after smooth 6: variance %.6f mm^2, mean radius shrink %.4f mm" % [va * 1e6, vb * 1e6, va / vb, v3 * 1e6, va / v3, cvar * 1e6, shrink * 1000.0])
	ok(va / vb > 2.0 and va / v3 > 5.0 and z.verts == z0, "2 smooth cuts the noisy sphere's radius variance: smooth 1 %.2f x (> 2), smooth 6 %.2f x (> 5); smooth 0 moves nothing" % [va / vb, va / v3])
	ok(cvar < 1e-8 and absf(shrink) < 0.0005, "2 smooth 6 on a clean sphere keeps it round (%.6f mm^2 < 0.01) and its size (shrink %.4f mm < 0.5)" % [cvar * 1e6, shrink * 1000.0])

	# 3 sharpen
	var b := noisy()
	KMeshFilters.sharpen(b, 0.5)
	var cs := contrast(b)
	var cm := contrast(a)
	print("  curvature contrast: noisy %.4f mm, sharpen 0.5 %.4f mm (x %.2f), smooth 1 %.4f mm" % [c0 * 1000.0, cs * 1000.0, cs / c0, cm * 1000.0])
	ok(cs / c0 > 1.3 and cm < c0, "3 sharpen 0.5 raises the curvature contrast %.2f x (> 1.3); smooth lowers it (%.4f < %.4f mm)" % [cs / c0, cm * 1000.0, c0 * 1000.0])

	# 4 mask
	var mask_ok := true
	var free_moved := 0.0
	var half_ok := true
	for k in KMeshFilters.KINDS:
		var m := noisy()
		m.add_attr("mask", "vert", TYPE_FLOAT, 0.0)
		for v in m.verts.size():
			if m.verts[v].x > 0.0:
				m.set_attr("mask", v, 1.0)
		var v0 := m.verts.duplicate()
		KMeshFilters.run(m, k, 0.01 if k == KMeshFilters.INFLATE else 0.5)
		var fm := 0.0
		for v in m.verts.size():
			if v0[v].x > 0.0:
				if m.verts[v] != v0[v]:
					mask_ok = false
			else:
				fm = maxf(fm, m.verts[v].distance_to(v0[v]))
		print("  mask %s: masked verts exact %s, unmasked max move %.3f mm" % [k, mask_ok, fm * 1000.0])
		if k == KMeshFilters.INFLATE:
			free_moved = fm
		elif fm <= 0.0:
			mask_ok = false
	var hm := KMeshSculptUI.make_sphere()
	hm.add_attr("mask", "vert", TYPE_FLOAT, 0.5)
	var h0 := hm.verts.duplicate()
	KMeshFilters.inflate(hm, 0.01)
	for v in hm.verts.size():
		if absf(hm.verts[v].distance_to(h0[v]) - 0.005) > 1e-5:
			half_ok = false
	ok(mask_ok and free_moved > 0.001 and half_ok, "4 mask = 1 freezes the verts exactly under all 3 filters, unmasked move (%.2f mm); mask 0.5 moves half" % (free_moved * 1000.0))

	# 5 session + undo
	var s := KMeshSculptUI.make_sphere()
	var rest := s.verts.duplicate()
	var ref := KMeshSculptUI.make_sphere()
	KMeshFilters.inflate(ref, 0.01)
	var u := KMeshUndo.new()
	var f := KMeshFilters.new()
	f.begin(s, u, KMeshFilters.INFLATE)
	f.set_amount(0.004)
	f.set_amount(0.01)
	var dref := 0.0
	for v in s.verts.size():
		dref = maxf(dref, s.verts[v].distance_to(ref.verts[v]))
	var st := f.commit()
	var nsteps := u.steps.size()
	u.undo()
	var back := s.verts == rest
	f.begin(s, u, KMeshFilters.SMOOTH)
	f.set_amount(2.0)
	f.cancel()
	var exact := s.verts == rest
	print("  session: preview vs one inflate %.9f m, steps %d, undo exact %s, cancel exact %s, steps after cancel %d" % [dref, nsteps, back, exact, u.steps.size()])
	ok(dref < 1e-6 and not st.is_empty() and nsteps == 1 and back and exact and u.steps.size() == 0,
		"5 preview is from the start state (not stacked), commit = one undo step, undo exact, cancel leaves it exact with no step")

	# 6 keys through the sculpt UI
	var fmn := FakeMain.new()
	var ui := KMeshSculptUI.new()
	ui.m = fmn
	ui.on = true
	ui.mesh = KMeshSculptUI.make_sphere()
	var r0 := ui.mesh.verts.duplicate()
	var used := key(ui, KEY_L)
	var on1: bool = ui.filt.active and ui.filt.kind == KMeshFilters.INFLATE
	var mv := InputEventMouseMotion.new()
	mv.position = Vector2(400, 300)
	ui.input(mv)
	mv = InputEventMouseMotion.new()
	mv.position = Vector2(500, 300)
	ui.input(mv)
	var drag_mm: float = ui.filt.amount * 1000.0
	for k in [KEY_2, KEY_PERIOD, KEY_5]:
		key(ui, k)
	var typed_mm: float = ui.filt.amount * 1000.0
	key(ui, KEY_ENTER)
	var d0 := ui.mesh.verts[0].distance_to(r0[0])
	var steps1 := ui.undo.steps.size()
	key(ui, KEY_L)
	key(ui, KEY_L)
	key(ui, KEY_L)
	var kind3: String = ui.filt.kind
	var r1 := ui.mesh.verts.duplicate()
	mv = InputEventMouseMotion.new()
	mv.position = Vector2(560, 300)
	ui.input(mv)
	mv = InputEventMouseMotion.new()
	mv.position = Vector2(640, 300)
	ui.input(mv)
	key(ui, KEY_ESCAPE)
	var esc_exact := ui.mesh.verts == r1 and not ui.filt.active and ui.undo.steps.size() == 1
	print("  keys: drag 100 px = %.2f mm, typed 2.5 -> %.2f mm, vert 0 moved %.4f mm, steps %d, L L L -> %s, Esc exact %s; said: %s" % [drag_mm, typed_mm, d0 * 1000.0, steps1, kind3, esc_exact, fmn.said])
	ok(used and on1 and absf(drag_mm - 10.0) < 1e-4 and absf(typed_mm - 2.5) < 1e-4 and absf(d0 - 0.0025) < 1e-5 and steps1 == 1 and kind3 == KMeshFilters.SHARPEN and esc_exact,
		"6 L starts inflate, drag 100 px = 10 mm, typed 2.5 = 2.5 mm, Enter = one step; L L L -> sharpen; Esc cancels exactly")
	ui.free()
	fmn.free()

	print("MESHFILTER %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
