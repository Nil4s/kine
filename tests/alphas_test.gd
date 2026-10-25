## godot --path . -s tests/alphas_test.gd     (ROADMAP_400 C08; needs a window: real keys, clicks and drags, a shot)
## Sculpt alphas (scripts/sculpt_alphas.gd), the stamp / stroke methods (scripts/sculpt_alpha_stroke.gd) and the alpha
## strip (scripts/sculpt_alpha_strip.gd). The DENSE PLANE: 0.4 m, 200 x 200 quads (2 mm), facing +Y. Bars, stated before
## measuring:
##   1 PICTURES: pores, scales, weave, crater, rivet, disc, noise are made (256 x 256, every value in 0..1, each one's
##     standard deviation > 0.05, every two differ by a mean |difference| > 0.05; all seven in < 3 s); a user PNG (64 x 48,
##     a horizontal ramp) loads as an alpha of its file name, 256 x 256, and its value at the frame point (0.5, 0) equals the
##     source's luminance there within 0.03
##   2 ONE STAMP: one draw dab of "scales" (radius 0.12 m, strength 5 mm, smooth falloff, the default fade, fixed rotation 0)
##     at the plane's centre: the rise of the verts within the radius correlates with the alpha resampled at those verts'
##     stamp-frame points (Pearson r) >= 0.9; no vert outside the radius moves
##   3 ROTATION: the same stamp at alpha_angle 90 deg: r with the alpha read in the turned frame >= 0.9, and r with the
##     unturned frame lower than that by > 0.3
##   4 DRAG RECT: drag_rect from a = (0.02, 0, -0.01) to b = a + (0.09, 0, 0.05): the stamp's radius == |ab| within 2 %, the
##     farthest moved vert from a lies at |ab| within 2 %, the stamp's x axis is along ab (cos > 0.999); one dab
##   5 SPRAY: a 21-point spray stroke of "pores" (radius 0.05, spacing 0.5) with seed 42, twice on fresh planes: every vert
##     == (bit-exact) and the stamps' centres / radii / axes ==; seed 43 gives a different mesh; the jitter is real: stamp
##     centres leave the path by > 0.1 radius somewhere, radii span > 20 % of the radius, axes differ by > 30 deg somewhere
##   6 MASK (C03): mask = 1 on every vert with x < 0, the spray stroke of bar 5 across x = 0: every masked vert is
##     bit-exactly where it was, and unmasked verts moved (> 0.5 mm somewhere)
##   7 PRESETS (C14): BrushPresets.clean keeps an "alpha" field and every shipped preset without one stays clean(p) == p;
##     "Skin pores" ships with alpha pores; apply() sets the sculpt UI's alpha (a preset without one clears it); of_ui()
##     carries it; its thumbnail stroke moves the plane (> 0.5 mm)
##   8 IN SCULPT (window, real input): A / Shift+A step the alpha (a real key) and change no brush field; a dots stroke with
##     an alpha (60 px drag) is ONE undo step and Ctrl+Z puts every vert back exactly; spray: one step; DRAG RECT (a real
##     70 px drag from the sphere's front centre): one step, the stamp's radius == the drag length on the tangent plane
##     within 2 %
##   9 PLACEMENT (shot $TMP/alphas_ui.png): the strip is visible, wholly inside the clear view, not over the matcap strip,
##     not over the presets panel (open), not over the sphere's projected outline (front, 1.6 m); every alpha button is
##     >= 24 px tall; a real click on "weave" picks it; a real pick of "drag rect" in the method box sets the method
extends SceneTree

var fails := 0
var m: Node
var ui: KMeshSculptUI


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func tmp(f: String) -> String:
	return OS.get_environment("TMP").path_join(f) if OS.get_environment("TMP") != "" else "user://" + f


static func plane() -> KMesh:
	var p := KMeshPrims.plane(0.4, 0.4, 200, 200)
	p.rebuild()
	return p


static func pearson(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var n := a.size()
	var ma := 0.0
	var mb := 0.0
	for i in n:
		ma += a[i]
		mb += b[i]
	ma /= n
	mb /= n
	var sab := 0.0
	var saa := 0.0
	var sbb := 0.0
	for i in n:
		sab += (a[i] - ma) * (b[i] - mb)
		saa += (a[i] - ma) * (a[i] - ma)
		sbb += (b[i] - mb) * (b[i] - mb)
	return sab / sqrt(maxf(saa * sbb, 1e-30))


## the rise of the verts within r of c, and the alpha read at their frame points (frame x axis t, normal +Y)
static func field(p0: PackedVector3Array, p1: PackedVector3Array, c: Vector3, r: float, nm: String, t: Vector3) -> Array:
	var rise := PackedFloat32Array()
	var al := PackedFloat32Array()
	var b := t.cross(Vector3.UP)
	var d := SculptAlphas.data(nm)
	for v in p0.size():
		var o := p0[v] - c
		if o.length() < r:
			rise.append(p1[v].y - p0[v].y)
			al.append(SculptAlphas.sample(d, o.dot(t) / r, o.dot(b) / r))
	return [rise, al]


func stamp(nm: String, ang: float) -> Array:
	var pl := plane()
	var v0 := pl.verts.duplicate()
	var sc := KMeshSculpt.new()
	sc.begin(pl, {"brush": KMeshSculpt.DRAW, "radius": 0.12, "strength": 0.005, "falloff": KMeshSculpt.F_SMOOTH, "alpha": nm,
		"alpha_rot": SculptAlphaStroke.R_FIXED, "alpha_angle": ang})
	sc.to(Vector3.ZERO, Vector3.UP, 1.0)
	sc.end()
	var outside := 0
	for v in v0.size():
		if v0[v].length() >= 0.12 and pl.verts[v] != v0[v]:
			outside += 1
	return [v0, pl.verts, outside]


func spray(seed_: int, mask := false) -> Array:
	var pl := plane()
	if mask:
		KMeshMask.ensure(pl)
		var mk := PackedFloat32Array()
		mk.resize(pl.verts.size())
		for v in pl.verts.size():
			mk[v] = 1.0 if pl.verts[v].x < 0.0 else 0.0
		pl.set_attr_data(KMeshMask.NAME, mk)
	var v0 := pl.verts.duplicate()
	var sc := KMeshSculpt.new()
	sc.begin(pl, {"brush": KMeshSculpt.DRAW, "radius": 0.05, "strength": 0.004, "spacing": 0.5, "alpha": "pores",
		"stroke_method": SculptAlphaStroke.SPRAY, "seed": seed_})
	for i in 21:
		sc.to(Vector3(lerpf(-0.12, 0.12, i / 20.0), 0.0, 0.0), Vector3.UP, 1.0)
	sc.end()
	return [v0, pl.verts, sc._alpha.stamps]


func _init() -> void:
	# 1 pictures
	var ms := SculptAlphas.make_all()
	var nms := SculptAlphas.NAMES
	var shape_ok := true
	var sds := PackedStringArray()
	for nm in nms:
		var d := SculptAlphas.data(nm)
		var im := SculptAlphas.image(nm)
		var mn := 0.0
		for x in d:
			mn += x
		mn /= d.size()
		var sd := 0.0
		var rng_ok := true
		for x in d:
			sd += (x - mn) * (x - mn)
			rng_ok = rng_ok and x >= 0.0 and x <= 1.0
		sd = sqrt(sd / d.size())
		sds.append("%s %.2f" % [nm, sd])
		shape_ok = shape_ok and im.get_size() == Vector2i(256, 256) and d.size() == 65536 and rng_ok and sd > 0.05
	var least := INF
	var pair := ""
	for i in nms.size():
		for j in range(i + 1, nms.size()):
			var a := SculptAlphas.data(nms[i])
			var b := SculptAlphas.data(nms[j])
			var s := 0.0
			for k in a.size():
				s += absf(a[k] - b[k])
			s /= a.size()
			if s < least:
				least = s
				pair = "%s / %s" % [nms[i], nms[j]]
	var src := Image.create(64, 48, false, Image.FORMAT_RGBA8)
	for y in 48:
		for x in 64:
			var g := float(x) / 63.0
			src.set_pixel(x, y, Color(g, g, g))
	var pth := tmp("alphas_ramp_7c1.png")
	src.save_png(pth)
	var unm := SculptAlphas.load_png(pth)
	var uval := SculptAlphas.sample(SculptAlphas.data(unm), 0.5, 0.0)
	# frame x 0.5 -> 3/4 across the centred 48 x 48 square of the 64 wide picture: source x = 8 + 0.75 * 48
	var want := (8.0 + 0.75 * 48.0 - 0.5) / 63.0
	ok(shape_ok and least > 0.05 and ms < 3000.0 and unm == "alphas_ramp_7c1" and SculptAlphas.names().has(unm)
		and SculptAlphas.image(unm).get_size() == Vector2i(256, 256) and absf(uval - want) <= 0.03,
		"(1) pictures: 7 made in %d ms, 256 px, 0..1, sd [%s]; least mean difference %.3f (%s); user PNG '%s' value %.3f (want %.3f)" % [
		ms, ", ".join(sds), least, pair, unm, uval, want])
	# 2 one stamp
	var s0 := stamp("scales", 0.0)
	var f0 := field(s0[0], s0[1], Vector3.ZERO, 0.12, "scales", Vector3.RIGHT)
	var r0 := pearson(f0[0], f0[1])
	ok(r0 >= 0.9 and s0[2] == 0, "(2) one scales stamp: r = %.3f over %d verts; verts moved outside the radius %d" % [r0, (f0[0] as PackedFloat32Array).size(), s0[2]])
	# 3 rotation
	var s90 := stamp("scales", PI / 2.0)
	var tt := Vector3.RIGHT.rotated(Vector3.UP, PI / 2.0)
	var r_t := pearson(field(s90[0], s90[1], Vector3.ZERO, 0.12, "scales", tt)[0], field(s90[0], s90[1], Vector3.ZERO, 0.12, "scales", tt)[1])
	var fu := field(s90[0], s90[1], Vector3.ZERO, 0.12, "scales", Vector3.RIGHT)
	var r_u := pearson(fu[0], fu[1])
	ok(r_t >= 0.9 and r_t - r_u > 0.3, "(3) rotation 90 deg: r with the turned alpha %.3f, with the unturned %.3f" % [r_t, r_u])
	# 4 drag rect
	var pl := plane()
	var pv0 := pl.verts.duplicate()
	var a := Vector3(0.02, 0.0, -0.01)
	var b2 := a + Vector3(0.09, 0.0, 0.05)
	var sc := KMeshSculpt.new()
	var rr := SculptAlphaStroke.drag_rect(sc, pl, {"brush": KMeshSculpt.DRAW, "strength": 0.004, "alpha": "scales"}, a, b2, Vector3.UP)
	var far := 0.0
	for v in pv0.size():
		if pl.verts[v] != pv0[v]:
			far = maxf(far, Vector2(pv0[v].x - a.x, pv0[v].z - a.z).length())
	var L := a.distance_to(b2)
	var ax: Vector3 = sc._alpha.stamps[0]["t"]
	ok(absf(rr - L) <= 0.02 * L and absf(far - L) <= 0.02 * L and ax.dot((b2 - a).normalized()) > 0.999 and sc.dabs == 1,
		"(4) drag rect: drag %.4f m, radius %.4f, farthest moved vert %.4f (%.2f %%), axis . drag %.5f, %d dab" % [L, rr, far, 100.0 * (far - L) / L, ax.dot((b2 - a).normalized()), sc.dabs])
	# 5 spray
	var sa := spray(42)
	var sb := spray(42)
	var sc3 := spray(43)
	var same_st := (sa[2] as Array).size() == (sb[2] as Array).size()
	for i in mini((sa[2] as Array).size(), (sb[2] as Array).size()):
		same_st = same_st and sa[2][i]["at"] == sb[2][i]["at"] and sa[2][i]["radius"] == sb[2][i]["radius"] and sa[2][i]["t"] == sb[2][i]["t"]
	var off_path := 0.0
	var rmin := INF
	var rmax := 0.0
	var ang_span := 0.0
	var t_first: Vector3 = sa[2][0]["t"]
	for st in sa[2]:
		off_path = maxf(off_path, absf((st["at"] as Vector3).z) / 0.05)
		rmin = minf(rmin, st["radius"])
		rmax = maxf(rmax, st["radius"])
		ang_span = maxf(ang_span, rad_to_deg(t_first.angle_to(st["t"])))
	ok(sa[1] == sb[1] and same_st and sa[1] != sc3[1] and off_path > 0.1 and (rmax - rmin) / 0.05 > 0.2 and ang_span > 30.0,
		"(5) spray: seed 42 twice bit-exact %s, stamps == %s (%d); seed 43 differs %s; off the path %.2f r, radii span %.0f %%, axes %.0f deg apart" % [
		sa[1] == sb[1], same_st, (sa[2] as Array).size(), sa[1] != sc3[1], off_path, 100.0 * (rmax - rmin) / 0.05, ang_span])
	# 6 mask
	var sm := spray(42, true)
	var frozen := true
	var moved := 0.0
	for v in (sm[0] as PackedVector3Array).size():
		if sm[0][v].x < 0.0:
			frozen = frozen and sm[1][v] == sm[0][v]
		else:
			moved = maxf(moved, (sm[1][v] as Vector3).distance_to(sm[0][v]))
	ok(frozen and moved > 0.0005, "(6) mask: masked verts bit-exact %s; unmasked moved up to %.2f mm" % [frozen, moved * 1000.0])
	await presets_and_ui()
	print("ALPHAS ", "PASS" if fails == 0 else "FAIL %d" % fails)
	TestFiles.cleanup()
	quit(1 if fails else 0)


func key(k: int, shift := false, ctrl := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.shift_pressed = shift
		e.ctrl_pressed = ctrl
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


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


func click(p: Vector2) -> void:
	await move(p, false)
	await mouse(p, true)
	await mouse(p, false)
	await idle(2)


func shot() -> Image:
	await idle(4)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func presets_and_ui() -> void:
	# 7 presets
	var raw := {"name": "x", "brush": KMeshSculpt.DRAW, "alpha": "weave"}
	var kept := String(BrushPresets.clean(raw).get("alpha", "")) == "weave"
	var old_clean := true
	var pores_p := {}
	for p in BrushPresets.SHIPPED:
		if not p.has("alpha"):
			old_clean = old_clean and BrushPresets.clean(p) == p and not BrushPresets.clean(p).has("alpha")
		if p["name"] == "Skin pores":
			pores_p = BrushPresets.clean(p)
	var base := BrushPresets.base_plane()
	var sm := BrushPresets.stroke_mesh(pores_p) if not pores_p.is_empty() else base
	var lift := 0.0
	for v in base.verts.size():
		lift = maxf(lift, sm.verts[v].distance_to(base.verts[v]))
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._sculpt_start()
	await idle(3)
	ui = m.ksc
	BrushPresets.apply(ui, pores_p)
	var set_on: bool = ui.alpha == "pores"
	var carried := String(BrushPresets.of_ui(ui, "t").get("alpha", "")) == "pores" and BrushPresets.matches_ui(ui, pores_p)
	BrushPresets.apply(ui, BrushPresets.clean(BrushPresets.SHIPPED[1]))
	var cleared: bool = ui.alpha == ""
	ok(kept and old_clean and pores_p.get("alpha", "") == "pores" and set_on and carried and cleared and lift > 0.0005,
		"(7) presets: clean keeps alpha %s, old presets clean(p) == p %s, Skin pores ships with %s, apply sets it %s, of_ui / matches carry it %s, a preset without one clears it %s, its thumbnail stroke lifts %.2f mm" % [
		kept, old_clean, pores_p.get("alpha", "-"), set_on, carried, cleared, lift * 1000.0])
	# 8 in sculpt
	var wc: Vector3 = ui.view.global_position
	m._turn_to(0.0, 0.0, 1.6, wc, false)
	await idle(6)
	var cam: Camera3D = m.cam
	var cs := cam.unproject_position(wc)
	var brush0 := [ui.brush, ui.radius, ui.strength, ui.falloff]
	await key(KEY_A)
	var a1: String = ui.alpha
	await key(KEY_A)
	var a2: String = ui.alpha
	await key(KEY_A, true)
	var a3: String = ui.alpha
	var fields_same: bool = [ui.brush, ui.radius, ui.strength, ui.falloff] == brush0
	ui.alphas.pick("scales")
	ui.alphas.set_method(SculptAlphaStroke.DOTS)
	var v0 := ui.mesh.verts.duplicate()
	var n0: int = ui.undo.steps.size()
	await drag(cs + Vector2(-30, 0), cs + Vector2(30, 0))
	var dots_steps: int = ui.undo.steps.size() - n0
	var dots_moved: bool = ui.mesh.verts != v0
	var dots_alpha: bool = ui.sculpt._alpha != null and not ui.sculpt._alpha.dat.is_empty()
	await key(KEY_Z, false, true)
	var dots_back: bool = ui.mesh.verts == v0
	ui.alphas.set_method(SculptAlphaStroke.SPRAY)
	n0 = ui.undo.steps.size()
	await drag(cs + Vector2(-30, 10), cs + Vector2(30, 10))
	var spray_steps: int = ui.undo.steps.size() - n0
	var spray_stamps: int = ui.sculpt._alpha.stamps.size() if ui.sculpt._alpha != null else 0
	await key(KEY_Z, false, true)
	var spray_back: bool = ui.mesh.verts == v0
	ui.alphas.set_method(SculptAlphaStroke.DRAG_RECT)
	var hit: Dictionary = ui.surface_at(cam, cs)
	var pa: Vector3 = hit["point"]
	var pn: Vector3 = hit["normal"]
	var pb: Vector3 = Plane(pn, pa).intersects_ray(cam.project_ray_origin(cs + Vector2(70, 0)), cam.project_ray_normal(cs + Vector2(70, 0)))
	var dd := pb - pa
	var L := (dd - pn * pn.dot(dd)).length()
	n0 = ui.undo.steps.size()
	var r_v0 := ui.mesh.verts.duplicate()
	await drag(cs, cs + Vector2(70, 0))
	var rect_steps: int = ui.undo.steps.size() - n0
	var rr: float = ui.alphas.last_rect
	var st_r: float = ui.sculpt._alpha.stamps[0]["radius"] if ui.sculpt._alpha != null and not ui.sculpt._alpha.stamps.is_empty() else 0.0
	var rect_moved: bool = ui.mesh.verts != r_v0
	ok(a1 == "pores" and a2 == "scales" and a3 == "pores" and fields_same and dots_steps == 1 and dots_moved and dots_alpha and dots_back
		and spray_steps == 1 and spray_stamps > 1 and spray_back and rect_steps == 1 and rect_moved and absf(rr - L) <= 0.02 * L and absf(st_r - L) <= 0.02 * L,
		"(8) in sculpt: A -> %s, A -> %s, Shift+A -> %s, brush fields unchanged %s; dots stroke with scales: %d undo step, moved %s, alpha on %s, Ctrl+Z exact %s; spray: %d step, %d stamps, Ctrl+Z exact %s; drag rect 70 px: %d step, moved %s, radius %.4f m / stamp %.4f vs drag %.4f (%.2f %%)" % [
		a1, a2, a3, fields_same, dots_steps, dots_moved, dots_alpha, dots_back, spray_steps, spray_stamps, spray_back, rect_steps, rect_moved, rr, st_r, L, 100.0 * (rr - L) / maxf(L, 1e-9)])
	# 9 placement
	ui.alphas.set_method(SculptAlphaStroke.DOTS)
	ui.presets.open()
	await idle(4)
	var sr: Rect2 = ui.alphas.strip.get_global_rect()
	var mr: Rect2 = ui.matcap.strip.get_global_rect()
	var pr: Rect2 = ui.presets.get_global_rect()
	var cl: Rect2 = m.nav_clear_rect()
	var lo := Vector2(INF, INF)
	var hi := -lo
	for dir in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
		var q := cam.unproject_position(wc + dir * KMeshSculptUI.R)
		lo = lo.min(q)
		hi = hi.max(q)
	var sph := Rect2(lo, hi - lo)
	var tall := true
	for b in ui.alphas._btns.values():
		tall = tall and (b as Button).get_global_rect().size.y >= 24.0
	await click((ui.alphas._btns["weave"] as Button).get_global_rect().get_center())
	var clicked: bool = ui.alpha == "weave"
	var img := await shot()
	img.save_png(tmp("alphas_ui.png"))
	var mb: OptionButton = ui.alphas.method_box
	await click(mb.get_global_rect().get_center())
	await idle(3)
	var pop := mb.get_popup()
	var opened := pop.visible
	var picked_rect := false
	if opened:
		var ih := pop.size.y / float(pop.item_count)
		var at := Vector2(pop.position) + Vector2(pop.size.x * 0.5, (SculptAlphaStroke.METHODS.find(SculptAlphaStroke.DRAG_RECT) + 0.5) * ih)
		await click(at)
		await idle(3)
		picked_rect = ui.stroke_method == SculptAlphaStroke.DRAG_RECT
	ok(ui.alphas.strip.visible and cl.encloses(sr) and not sr.intersects(mr) and not sr.intersects(pr) and not sr.intersects(sph) and tall and clicked and picked_rect,
		"(9) placement: strip %s inside the clear view %s %s; matcap strip %s apart %s; presets panel %s apart %s; sphere %s apart %s; buttons >= 24 px %s; a click on weave picks it %s; the method box opened %s and a click on drag rect set it %s (shot %s)" % [
		sr, cl, cl.encloses(sr), mr, not sr.intersects(mr), pr, not sr.intersects(pr), sph, not sr.intersects(sph), tall, clicked, opened, picked_rect, tmp("alphas_ui.png")])
	ui.presets.close()
	ui.alphas.set_method(SculptAlphaStroke.DOTS)
	ui.alphas.pick("")
