## godot --path . -s tests/mask_test.gd     (ROADMAP_400 C03; scripts/kmesh_mask.gd, kmesh_mask_tint.gd, the mask in
## kmesh_sculpt.gd and kmesh_sculpt_ui.gd; needs a window for bars 7 and 8). Bars, written before measuring:
##   1 FROZEN: a 2 m plane, 40 x 40 quads; mask 1 on every vert with x < 0. 20 inflate dabs (radius 0.25, 5 mm) at the
##     origin: every masked vert moves exactly 0.0 m; the unmasked side moves (its largest move > 1 cm)
##   2 HALF: mask 0.5 everywhere: one draw dab moves every vert half of what the unmasked plane moves (worst ratio error
##     < 2 %), 20 inflate dabs on the surface over the centre vert move it half (within 2 %), a grab moves the pressed vert
##     by half the drag (2 %). (First run had the 20 dabs at a FIXED point (0,0,0): ratio 0.54, because the unmasked
##     centre rises 10 cm off that point and its falloff drops, the masked one 5 cm: the falloff drift, not the mask.
##     A stroke's dabs land on the surface, so the bar now dabs there.)
##   3 INVERT gives 1 - m on every vert (1e-6) of a random mask, twice gives it back; BLUR of a single 1 at an inner vert
##     gives 1/5 there and on its 4 neighbours, 0 two edges away, the sum stays 1 (1e-6); a constant mask stays constant
##   4 CAVITY: a V groove y = 0.2 |x| masks exactly the 41 verts of its bottom line (x = 0); the same crease as a ridge
##     (y = -0.2 |x|) masks none, a sphere none
##   5 UNDO + FILE: a mask stroke bracketed by KMeshUndo is ONE step, undo gives the old mask back exactly, redo the new;
##     the mask survives to_dict -> JSON -> from_dict value for value
##   6 MASK BRUSH: one "mask" dab: centre 1, every vert = falloff(d / r) (1e-6), 0 beyond r, no vert moved; an erase dab
##     (invert) at the same place brings it back to 0
##   7 KEYS (the test sphere, real key / mouse events): M picks the mask brush, a drag paints (one undo step, no vert moved);
##     D + a draw drag over the same place moves no vert whose mask is 1 and some unmasked ones; Ctrl+I gives 1 - m;
##     Shift+B blurs (the sum of the mask spreads to more verts); Alt+M clears to 0; Ctrl+Z gives the blurred mask back;
##     Shift+M (cavity) masks exactly the verts KMeshMask.cavity calls concave (the draw stroke left a rim of them; first
##     run's bar said "0 on the convex sphere", wrong: the sphere is no longer convex after bar 7's draw)
##   8 PLACEMENT (shot -> user://mask.png): a mask painted at the front centre of the sphere: the tint's mesh centre is
##     within the brush radius of the painted point (world), the pixel there is darker than the same pixel with the tint
##     hidden (difference > 0.1), and a sphere pixel 0.2 m to the side (unmasked: it differs > 0.05 from the same pixel
##     with the sphere hidden) differs < 0.02
extends SceneTree

var fails := 0
var m: Node
var ui: KMeshSculptUI


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


static func plane(n: int, size := 2.0, crease := 0.0) -> KMesh:
	var vs := PackedVector3Array()
	for j in n + 1:
		for i in n + 1:
			var x := -size * 0.5 + size * i / n
			vs.append(Vector3(x, crease * absf(x), -size * 0.5 + size * j / n))
	var fs: Array = []
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			fs.append([a, a + n + 1, a + n + 2, a + 1])
	return KMesh.new().from_arrays(vs, fs)


static func nearest(km: KMesh, q: Vector3) -> int:
	var b := -1
	var bd := INF
	for v in km.verts.size():
		var d := km.verts[v].distance_squared_to(q)
		if d < bd:
			bd = d
			b = v
	return b


static func set_mask(km: KMesh, f: Callable) -> void:
	KMeshMask.ensure(km)
	var d := PackedFloat32Array()
	d.resize(km.vert_count())
	for v in d.size():
		d[v] = f.call(v)
	km.set_attr_data(KMeshMask.NAME, d)


## 20 inflate dabs over the origin vert; on_surface: each dab at that vert's current position (where a stroke's ray
## hits), else at the fixed point (0, 0, 0)
static func inflate20(km: KMesh, on_surface := false) -> void:
	var sc := KMeshSculpt.new()
	sc.begin(km, {"brush": KMeshSculpt.INFLATE, "radius": 0.25, "strength": 0.005})
	var c := nearest(km, Vector3.ZERO)
	for k in 20:
		sc.dab(km.verts[c] if on_surface else Vector3.ZERO, Vector3.UP)


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func drag(a: Vector2, b: Vector2, steps := 8) -> void:
	await mouse(a, true)
	for k in steps:
		await move(a.lerp(b, (k + 1) / float(steps)))
	await mouse(b, false)
	await idle(2)


func key(k: int, ctrl := false, shift := false, alt := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.ctrl_pressed = ctrl
		e.shift_pressed = shift
		e.alt_pressed = alt
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


func shot() -> Image:
	await idle(4)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


static func dist(a: Color, b: Color) -> float:
	return sqrt(pow(a.r - b.r, 2) + pow(a.g - b.g, 2) + pow(a.b - b.b, 2))


static func msum(d: PackedFloat32Array) -> float:
	var s := 0.0
	for x in d:
		s += x
	return s


static func mcount(d: PackedFloat32Array) -> int:
	var n := 0
	for x in d:
		if x > 1e-6:
			n += 1
	return n


func _init() -> void:
	# 1 frozen
	var p1 := plane(40)
	set_mask(p1, func(v): return 1.0 if p1.verts[v].x < -1e-6 else 0.0)
	var a1 := p1.verts.duplicate()
	inflate20(p1)
	var worst_masked := 0.0
	var best_free := 0.0
	for v in a1.size():
		var mv := p1.verts[v].distance_to(a1[v])
		if a1[v].x < -1e-6:
			worst_masked = maxf(worst_masked, mv)
		else:
			best_free = maxf(best_free, mv)
	ok(worst_masked == 0.0 and best_free > 0.01, "(1) 20 inflate dabs: the masked half moved %s m at most, the unmasked side %.4f m" % [worst_masked, best_free])
	# 2 half
	var full := plane(40)
	var half := plane(40)
	set_mask(half, func(_v): return 0.5)
	for km in [full, half]:
		var sc := KMeshSculpt.new()
		sc.begin(km, {"brush": KMeshSculpt.DRAW, "radius": 0.25, "strength": 0.01})
		sc.dab(Vector3(0.3, 0, 0.2), Vector3.UP)
	var worst_r := 0.0
	var cnt := 0
	for v in full.verts.size():
		if full.verts[v].y > 1e-6:
			cnt += 1
			worst_r = maxf(worst_r, absf(half.verts[v].y / full.verts[v].y - 0.5) / 0.5)
	full = plane(40)
	half = plane(40)
	set_mask(half, func(_v): return 0.5)
	inflate20(full, true)
	inflate20(half, true)
	var c := nearest(plane(40), Vector3.ZERO)
	var inf_r: float = half.verts[c].y / full.verts[c].y
	var g := plane(40)
	set_mask(g, func(_v): return 0.5)
	var gs := KMeshSculpt.new()
	gs.begin(g, {"brush": KMeshSculpt.GRAB, "radius": 0.25})
	var g0 := g.verts[c]
	gs.to(g0, Vector3.UP)
	gs.to(g0 + Vector3(0, 0.1, 0), Vector3.UP)
	gs.end()
	var grab_r := (g.verts[c].y - g0.y) / 0.1
	ok(cnt > 50 and worst_r < 0.02 and absf(inf_r - 0.5) / 0.5 < 0.02 and absf(grab_r - 0.5) / 0.5 < 0.02,
		"(2) half mask: draw worst ratio error %.4f %% over %d verts, 20 inflate dabs centre ratio %.4f, grab ratio %.4f" % [worst_r * 100.0, cnt, inf_r, grab_r])
	# 3 invert, blur
	var p3 := plane(40)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	set_mask(p3, func(_v): return rng.randf())
	var r0 := KMeshMask.values(p3).duplicate()
	KMeshMask.invert(p3)
	var worst_i := 0.0
	var r1 := KMeshMask.values(p3)
	for v in r0.size():
		worst_i = maxf(worst_i, absf(r1[v] - (1.0 - r0[v])))
	KMeshMask.invert(p3)
	var back := 0.0
	for v in r0.size():
		back = maxf(back, absf(KMeshMask.values(p3)[v] - r0[v]))
	ok(worst_i < 1e-6 and back < 1e-6, "(3) invert: worst |m' - (1 - m)| %s, twice back to the start within %s" % [worst_i, back])
	var p3b := plane(40)
	var ci := nearest(p3b, Vector3.ZERO)
	set_mask(p3b, func(v): return 1.0 if v == ci else 0.0)
	KMeshMask.blur(p3b)
	var bd := KMeshMask.values(p3b)
	var nb := p3b.vert_neighbors(ci)
	var nb_ok := nb.size() == 4
	for u in nb:
		nb_ok = nb_ok and absf(bd[u] - 0.2) < 1e-6
	var two := nearest(p3b, Vector3(0.1, 0, 0))
	var two_d := nearest(p3b, Vector3(0.05, 0, 0.05))
	var p3c := plane(40)
	set_mask(p3c, func(_v): return 0.3)
	KMeshMask.blur(p3c, 3)
	var cw := 0.0
	for x in KMeshMask.values(p3c):
		cw = maxf(cw, absf(x - 0.3))
	ok(absf(bd[ci] - 0.2) < 1e-6 and nb_ok and bd[two] == 0.0 and bd[two_d] == 0.0 and absf(msum(bd) - 1.0) < 1e-6 and cw < 1e-6,
		"(3) blur: centre %.4f, its %d neighbours 0.2 %s, two edges away %s / %s, sum %.6f; a constant 0.3 after 3 passes off by %s" % [bd[ci], nb.size(), nb_ok, bd[two], bd[two_d], msum(bd), cw])
	# 4 cavity
	var gr := plane(40, 2.0, 0.2)
	var n_g := KMeshMask.by_cavity(gr)
	var line_ok := true
	var gd := KMeshMask.values(gr)
	for v in gd.size():
		var on_line := absf(gr.verts[v].x) < 1e-6
		line_ok = line_ok and (gd[v] == 1.0) == on_line
	var ri := plane(40, 2.0, -0.2)
	var n_r := KMeshMask.by_cavity(ri)
	var sph := KMeshSculptUI.make_sphere()
	var n_s := KMeshMask.by_cavity(sph)
	var cv := KMeshMask.cavity(gr)
	ok(n_g == 41 and line_ok and n_r == 0 and n_s == 0, "(4) cavity: groove masks %d verts (the bottom line exactly: %s; its curvature %.3f, a wall vert %.4f), ridge %d, sphere %d" % [n_g, line_ok, cv[nearest(gr, Vector3.ZERO)], cv[nearest(gr, Vector3(0.5, 0.1, 0))], n_r, n_s])
	# 5 undo + file
	var p5 := plane(40)
	KMeshMask.ensure(p5)
	var u0 := KMeshMask.values(p5).duplicate()
	var un := KMeshUndo.new()
	un.begin(p5)
	var ms := KMeshSculpt.new()
	ms.begin(p5, {"brush": KMeshSculpt.MASK, "radius": 0.2})
	for k in 6:
		ms.to(Vector3(-0.3 + 0.1 * k, 0, 0), Vector3.UP)
	ms.end()
	un.commit("sculpt mask")
	var u1 := KMeshMask.values(p5).duplicate()
	var st := un.steps.size()
	un.undo()
	var und_ok: bool = KMeshMask.values(p5) == u0
	un.redo()
	var red_ok: bool = KMeshMask.values(p5) == u1
	var js := JSON.stringify(p5.to_dict())
	var back5 := KMesh.new().from_dict(JSON.parse_string(js))
	var file_ok: bool = back5 != null and KMeshMask.values(back5) == u1
	ok(st == 1 and mcount(u1) > 20 and und_ok and red_ok and file_ok, "(5) mask stroke = %d undo step (%d verts masked); undo exact %s, redo exact %s; save/load keeps it %s" % [st, mcount(u1), und_ok, red_ok, file_ok])
	# 6 mask brush
	var p6 := plane(40)
	var a6 := p6.verts.duplicate()
	var mb := KMeshSculpt.new()
	var H := Vector3(0.3, 0, 0.2)
	mb.begin(p6, {"brush": KMeshSculpt.MASK, "radius": 0.25})
	mb.dab(H, Vector3.UP)
	var md := KMeshMask.values(p6)
	var worst6 := 0.0
	for v in md.size():
		worst6 = maxf(worst6, absf(md[v] - KMeshSculpt.falloff(KMeshSculpt.F_SMOOTH, a6[v].distance_to(H) / 0.25)))
	var centre6 := md[nearest(p6, H)]
	var er := KMeshSculpt.new()
	er.begin(p6, {"brush": KMeshSculpt.MASK, "radius": 0.25, "invert": true})
	er.dab(H, Vector3.UP)
	ok(centre6 == 1.0 and worst6 < 1e-6 and p6.verts == a6 and msum(KMeshMask.values(p6)) == 0.0,
		"(6) mask dab: centre %.3f, worst |m - falloff| %s, verts unmoved %s; erase dab leaves sum %s" % [centre6, worst6, p6.verts == a6, msum(KMeshMask.values(p6))])
	await _ui()
	print("MASK ", "PASS" if fails == 0 else "FAIL %d" % fails)
	TestFiles.cleanup()
	quit(1 if fails else 0)


func _ui() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._sculpt_start()
	await idle(3)
	ui = m.ksc
	var wc: Vector3 = ui.view.global_position
	m._turn_to(0.0, 0.0, 1.6, wc, false)
	await idle(6)
	var cam: Camera3D = m.cam
	var cs := cam.unproject_position(wc)
	# 7 keys
	await key(KEY_M)
	var picked := ui.brush
	var v0 := ui.mesh.verts.duplicate()
	var s0: int = ui.undo.steps.size()
	await drag(cs + Vector2(-10, 0), cs + Vector2(10, 0))
	var mk := KMeshMask.values(ui.mesh).duplicate()
	var paint_ok: bool = picked == KMeshSculpt.MASK and mcount(mk) > 10 and ui.mesh.verts == v0 and ui.undo.steps.size() == s0 + 1
	await key(KEY_D)
	await drag(cs + Vector2(-30, 0), cs + Vector2(30, 0))
	var frozen_moved := 0
	var full_n := 0
	var free_moved := 0
	for v in v0.size():
		if mk[v] >= 1.0:
			full_n += 1
			if ui.mesh.verts[v] != v0[v]:
				frozen_moved += 1
		elif mk[v] == 0.0 and ui.mesh.verts[v] != v0[v]:
			free_moved += 1
	await key(KEY_I, true)
	var inv := KMeshMask.values(ui.mesh)
	var inv_w := 0.0
	for v in mk.size():
		inv_w = maxf(inv_w, absf(inv[v] - (1.0 - mk[v])))
	await key(KEY_I, true)
	var n_before := mcount(KMeshMask.values(ui.mesh))
	await key(KEY_B, false, true)
	var blurred := KMeshMask.values(ui.mesh).duplicate()
	var n_blur := mcount(blurred)
	await key(KEY_M, false, false, true)
	var cleared := msum(KMeshMask.values(ui.mesh))
	await key(KEY_Z, true)
	var back_blur: bool = KMeshMask.values(ui.mesh) == blurred
	var cav_want := 0
	for x in KMeshMask.cavity(ui.mesh):
		if x > KMeshMask.CAVITY_THRESHOLD:
			cav_want += 1
	await key(KEY_M, false, true)
	var cav := mcount(KMeshMask.values(ui.mesh))
	await key(KEY_Z, true)
	ok(paint_ok and full_n > 0 and frozen_moved == 0 and free_moved > 0 and inv_w < 1e-6 and n_blur > n_before and cleared == 0.0 and back_blur and cav == cav_want and ui.mesh.verts != v0,
		"(7) keys: M -> %s, paint %s (%d verts); draw over it: %d fully masked verts, %d of them moved, %d unmasked moved; Ctrl+I worst %s; Shift+B %d -> %d masked verts; Alt+M sum %s; Ctrl+Z back %s; Shift+M masks %d (the concave verts of the stroked sphere: %d)" % [picked, paint_ok, mcount(mk), full_n, frozen_moved, free_moved, inv_w, n_before, n_blur, cleared, back_blur, cav, cav_want])
	# 8 placement
	await key(KEY_M, false, false, true)
	await key(KEY_M)
	var hit: Dictionary = ui.surface_at(cam, cs)
	await drag(cs, cs + Vector2(1, 0))
	await idle(2)   # the tint rebuilds itself in its _process: no call from here
	var tm: Mesh = ui.tint.mesh
	var tc := Vector3.INF
	if tm != null:
		var ab := tm.get_aabb()
		tc = ui.view.global_transform * (ab.position + ab.size * 0.5)
	var off_c: float = tc.distance_to(hit["point"]) if not hit.is_empty() else INF
	m.ui_root.visible = false
	await move(cs + Vector2(300, 300), false)
	var side := cam.unproject_position(wc + Vector3(0.2, 0.0, 0.0) + (cam.global_position - wc).normalized() * 0.2)
	var img := await shot()
	img.save_png("user://mask.png")
	ui.tint.visible = false
	var img_no := await shot()
	ui.view.visible = false
	var img_none := await shot()
	ui.view.visible = true
	ui.tint.visible = true
	m.ui_root.visible = true
	var pc := Vector2i(cs.round())
	var ps := Vector2i(side.round())
	var d_c := dist(img.get_pixelv(pc), img_no.get_pixelv(pc))
	var darker := img.get_pixelv(pc).get_luminance() < img_no.get_pixelv(pc).get_luminance()
	var d_s := dist(img.get_pixelv(ps), img_no.get_pixelv(ps))
	var on_sph := dist(img_no.get_pixelv(ps), img_none.get_pixelv(ps)) > 0.05   # the side pixel is on the sphere
	ok(off_c < ui.radius and d_c > 0.1 and darker and d_s < 0.02 and on_sph,
		"(8) placement: tint centre %.4f m from the painted point (brush %.3f m); pixel there differs %.3f with / without the tint, darker %s; side pixel %s (on the sphere %s) differs %.4f (shot user://mask.png)" % [off_c, ui.radius, d_c, darker, ps, on_sph, d_s])
