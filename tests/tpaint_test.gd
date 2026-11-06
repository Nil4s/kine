## godot --path . -s tests/tpaint_test.gd     (L53 TPAINT, GAP_AUDIT Sculpt item 5; needs a window: pixels are read back from a real render)
## BARS WRITTEN AND COMMITTED BEFORE THE IMPLEMENTATION (scripts/kmesh_tpaint.gd + native/src/kine_tpaint_native.cpp). Texture paint: a brush stamp
## in SCREEN space (centre px, radius px) is projected onto the mesh and written into the texels of every UV island it covers, with a seam bleed
## (the island's border texels continue `pad` texels outward, from the surface plane, so bilinear filtering never meets the unpainted gutter).
##   a SEAM: two coplanar quads whose UV islands are 4 texels apart (1024 tex); one stamp over their shared 3D edge changes >= 100 texels inside EACH
##     island rect; in a real render the pixels beside the seam (cols 255/256 vs 252/259, rows 226..286) differ by CIE76 dE < 2 (max printed)
##   b PLACEMENT / COVERAGE: one hard disk (hardness 1, radius 100 px) on a camera-facing quad: the rendered painted pixels (green < midpoint) number
##     pi r^2 within 5 %, and their centroid is within 1.5 px of the stamp centre
##   c BACK / OCCLUDED: on a closed cube viewed face on, a stamp at the screen centre changes 0 texels in the 5 other faces' islands (>0 on the front);
##     a lone quad seen from behind: 0 texels; a small quad in front of a large one: 0 texels on the one behind, >0 on the one in front
##   d NATIVE == GDSCRIPT: two stamps (pad 2) on a UV sphere, 256 tex, 256x256 screen: max texel byte diff <= 1 (1/255), and the stamps did write
##   e SPEED: a radius 150 px stamp on a 4096-triangle sphere into a 2048 x 2048 texture, 1280 x 720 screen: best of 7 <= 8 ms native (printed)
##   f UNDO: a 2-stamp stroke: hash changes; undo restores the EXACT initial hash; redo restores the stroked hash; a one-byte corruption changes it
##   g PLANTED FAILS: (g1) pad 0 (no dilation): the seam dE of bar a is > 5; (g2) culling off: the lone back quad changes > 0 texels; (g3) occlusion
##     off: the quad behind changes > 0 texels; (g4) a result nudged by 3/255 fails bar d's check
##   h TOOL: the agent tool texture_paint (scripts/tpaint_serve.gd) paints a sphere and reports texels > 0, engine native, ms; a bad argument is refused
##   i APP: the S box line "Model: texture paint on / off" opens the model preview in Texture mode; a real click on the cube changes texels, the pixel
##     under the click turns green (was not), a vertex colour channel is untouched, and Ctrl+Z restores the texture hash exactly
extends SceneTree

const W := 512
var fails := 0
var vp: SubViewport
var inst: MeshInstance3D
var cam3: Camera3D
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


# ---------------------------------------------------------------- helpers

func mvp_for(cam_pos: Vector3, aspect: float) -> Projection:
	return Projection.create_perspective(50.0, aspect, 0.05, 50.0) * Projection(Transform3D(Basis(), cam_pos).affine_inverse())


## faces: Array of {"p": 4 Vector3 (CCW from the front), "uv": Rect2}; corner uvs (0,1) (1,1) (1,0) (0,0) of the rect, x/y of the rect
func quads(faces: Array) -> KMesh:
	var vs := PackedVector3Array()
	var fs := []
	var uvs := PackedVector2Array()
	for f in faces:
		var base := vs.size()
		for p in f["p"]:
			vs.append(p)
		fs.append([base, base + 1, base + 2, base + 3])
		var r: Rect2 = f["uv"]
		uvs.append(Vector2(r.position.x, r.end.y))
		uvs.append(r.end)
		uvs.append(Vector2(r.end.x, r.position.y))
		uvs.append(r.position)
	var k := KMesh.new().from_arrays(vs, fs)
	k.add_attr("uv", KMesh.AD_CORNER, TYPE_VECTOR2)
	k.set_attr_data("uv", uvs)
	return k


func cube_mesh() -> KMesh:
	var P := [
		[Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)],
		[Vector3(1, -1, -1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1)],
		[Vector3(1, -1, 1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1)],
		[Vector3(-1, -1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1)],
		[Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(-1, 1, -1)],
		[Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1)]]
	var fl := []
	for i in 6:
		fl.append({"p": P[i], "uv": cell_rect(i)})
	return quads(fl)


func cell_rect(i: int) -> Rect2:
	return Rect2(Vector2(i % 3, i / 3) * Vector2(1.0 / 3.0, 0.5) + Vector2(0.01, 0.01), Vector2(1.0 / 3.0 - 0.02, 0.5 - 0.02))


func quad_xy(x0: float, x1: float, y0: float, y1: float, z: float, uv: Rect2, flip := false) -> Dictionary:
	var p := [Vector3(x0, y0, z), Vector3(x1, y0, z), Vector3(x1, y1, z), Vector3(x0, y1, z)]
	if flip:
		p.reverse()
	return {"p": p, "uv": uv}


## texels that differ between two RGBA8 buffers inside a uv rect
func changed_in(a: PackedByteArray, b: PackedByteArray, size: int, r: Rect2) -> int:
	var n := 0
	var x0 := int(floor(r.position.x * size))
	var x1 := int(ceil(r.end.x * size))
	var y0 := int(floor(r.position.y * size))
	var y1 := int(ceil(r.end.y * size))
	for y in range(y0, y1):
		for x in range(x0, x1):
			var i := (y * size + x) * 4
			if a[i] != b[i] or a[i + 1] != b[i + 1] or a[i + 2] != b[i + 2]:
				n += 1
	return n


func max_diff(a: PackedByteArray, b: PackedByteArray) -> int:
	if a.size() != b.size():
		return 999
	var d := 0
	for i in a.size():
		d = maxi(d, absi(a[i] - b[i]))
	return d


func lab(c: Color) -> Vector3:
	var f := func(u: float) -> float: return u / 12.92 if u <= 0.04045 else pow((u + 0.055) / 1.055, 2.4)
	var r: float = f.call(c.r)
	var g: float = f.call(c.g)
	var b: float = f.call(c.b)
	var X := (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
	var Y := 0.2126 * r + 0.7152 * g + 0.0722 * b
	var Z := (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
	var h := func(t: float) -> float: return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0
	var fx: float = h.call(X)
	var fy: float = h.call(Y)
	var fz: float = h.call(Z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


func dE(a: Color, b: Color) -> float:
	return lab(a).distance_to(lab(b))


func make_view(mesh: KMesh) -> void:
	if vp == null:
		vp = SubViewport.new()
		vp.size = Vector2i(W, W)
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.msaa_3d = Viewport.MSAA_DISABLED
		root.add_child(vp)
		cam3 = Camera3D.new()
		cam3.fov = 50.0
		cam3.near = 0.05
		cam3.far = 50.0
		cam3.position = Vector3(0, 0, 3)
		vp.add_child(cam3)
		cam3.current = true
		inst = MeshInstance3D.new()
		vp.add_child(inst)
	inst.mesh = mesh.to_array_mesh(false)


func render(tex: PackedByteArray, size: int) -> Image:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.albedo_texture = ImageTexture.create_from_image(Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, tex))
	inst.material_override = mat
	await idle(2)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return vp.get_texture().get_image()


func seam_de(img: Image) -> float:
	var worst := 0.0
	for y in range(226, 287, 6):
		var a := img.get_pixel(255, y)
		var b := img.get_pixel(256, y)
		worst = maxf(worst, maxf(dE(a, img.get_pixel(252, y)), maxf(dE(b, img.get_pixel(259, y)), dE(a, b))))
	return worst


func seam_mesh() -> KMesh:
	return quads([quad_xy(-1, -0.0022, -1, 1, 0, Rect2(0.1, 0.1, 0.398, 0.8)), quad_xy(-0.0022, 1, -1, 1, 0, Rect2(0.502, 0.1, 0.398, 0.8))])


# ---------------------------------------------------------------- the bars

func _init() -> void:
	call_deferred("run")


func run() -> void:
	var cp := Vector3(0, 0, 3)
	var mv := mvp_for(cp, 1.0)
	var scr := Vector2i(W, W)
	var green := Color(0.1, 0.8, 0.1)
	var red := Color(0.9, 0.1, 0.1)
	var native_ok := NativeExt.ensure("kine_native", "KineTPaintNative")
	ok(native_ok, "native class KineTPaintNative is loaded")

	# a SEAM
	var sm := seam_mesh()
	make_view(sm)
	var tp := KMeshTPaint.new(sm, 1024)
	var t0 := tp.data()
	tp.stamp(mv, cp, scr, Vector2(256, 256), 80.0, red, 1.0, 0.7, 2)
	var t1 := tp.data()
	var nl := changed_in(t0, t1, 1024, Rect2(0.1, 0.1, 0.398, 0.8))
	var nr := changed_in(t0, t1, 1024, Rect2(0.502, 0.1, 0.398, 0.8))
	var img := await render(t1, 1024)
	var de := seam_de(img)
	img.save_png("C:/Temp/claude/L53/seam.png")
	ok(nl >= 100 and nr >= 100 and de < 2.0, "a SEAM: texels changed left %d, right %d (each >= 100); render seam dE %.3f (< 2); engine %s" % [nl, nr, de, tp.engine])
	var tpn := KMeshTPaint.new(sm, 1024)
	tpn.stamp(mv, cp, scr, Vector2(256, 256), 80.0, red, 1.0, 0.7, 0)
	var img0 := await render(tpn.data(), 1024)
	var de0 := seam_de(img0)
	ok(de0 > 5.0, "g1 PLANTED no dilation (pad 0): the seam shows, dE %.3f (> 5)" % de0)

	# b COVERAGE / PLACEMENT
	var qm := quads([quad_xy(-1, 1, -1, 1, 0, Rect2(0.05, 0.05, 0.9, 0.9))])
	make_view(qm)
	var tb := KMeshTPaint.new(qm, 1024)
	tb.stamp(mv, cp, scr, Vector2(256, 256), 100.0, Color(0.1, 0.9, 0.1), 1.0, 1.0, 2)
	var ib := await render(tb.data(), 1024)
	ib.save_png("C:/Temp/claude/L53/disk.png")
	var cnt := 0
	var sx := 0.0
	var sy := 0.0
	for y in W:
		for x in W:
			var pc := ib.get_pixel(x, y)
			if pc.g - pc.r > 0.4:   # painted (0.1, 0.9, 0.1): g - r = 0.8; white and the grey background 0 (mid 0.4)
				cnt += 1
				sx += x + 0.5
				sy += y + 0.5
	var area := PI * 100.0 * 100.0
	var cen := Vector2(sx, sy) / maxf(cnt, 1)
	var err := absf(cnt - area) / area
	ok(err <= 0.05 and cen.distance_to(Vector2(256, 256)) <= 1.5,
		"b COVERAGE: %d px vs disk %.0f (%.2f %% off, <= 5); centroid %s vs (256,256) off %.2f px (<= 1.5); screen coverage %.2f %%" % [cnt, area, err * 100.0, cen, cen.distance_to(Vector2(256, 256)), 100.0 * cnt / (W * W)])

	# c BACK / OCCLUDED
	var cm := cube_mesh()
	var tc := KMeshTPaint.new(cm, 512)
	var c0 := tc.data()
	tc.stamp(mv, cp, scr, Vector2(256, 256), 60.0, green, 1.0, 0.5, 2)
	var c1 := tc.data()
	var per := []
	for i in 6:
		per.append(changed_in(c0, c1, 512, cell_rect(i)))
	var others := 0
	for i in range(1, 6):
		others += int(per[i])
	ok(int(per[0]) > 500 and others == 0, "c1 CUBE: front face changed %d texels, the other five faces %d (== 0) %s" % [per[0], others, per])
	var bq := quads([quad_xy(-1, 1, -1, 1, 0, Rect2(0.05, 0.05, 0.9, 0.9), true)])
	var tq := KMeshTPaint.new(bq, 256)
	var q0 := tq.data()
	tq.stamp(mv, cp, scr, Vector2(256, 256), 60.0, green, 1.0, 0.5, 2)
	var nback := changed_in(q0, tq.data(), 256, Rect2(0, 0, 1, 1))
	ok(nback == 0, "c2 BACK-FACING quad: %d texels changed (== 0)" % nback)
	var oc := quads([quad_xy(-0.3, 0.3, -0.3, 0.3, 0.5, Rect2(0.0, 0.0, 0.5, 0.5)), quad_xy(-1.5, 1.5, -1.5, 1.5, -0.5, Rect2(0.5, 0.0, 0.5, 0.5))])
	var to := KMeshTPaint.new(oc, 512)
	var o0 := to.data()
	to.stamp(mv, cp, scr, Vector2(256, 256), 30.0, green, 1.0, 0.5, 2)
	var nfront := changed_in(o0, to.data(), 512, Rect2(0, 0, 0.5, 0.5))
	var nbehind := changed_in(o0, to.data(), 512, Rect2(0.5, 0, 0.5, 0.5))
	ok(nfront > 200 and nbehind == 0, "c3 OCCLUDED: front quad %d texels, the quad behind it %d (== 0)" % [nfront, nbehind])
	var tg2 := KMeshTPaint.new(bq, 256)
	tg2.cull_back = false
	tg2.stamp(mv, cp, scr, Vector2(256, 256), 60.0, green, 1.0, 0.5, 2)
	var g2 := changed_in(q0, tg2.data(), 256, Rect2(0, 0, 1, 1))
	var tg3 := KMeshTPaint.new(oc, 512)
	tg3.occlusion = false
	tg3.stamp(mv, cp, scr, Vector2(256, 256), 30.0, green, 1.0, 0.5, 2)
	var g3 := changed_in(o0, tg3.data(), 512, Rect2(0.5, 0, 0.5, 0.5))
	ok(g2 > 100 and g3 > 100, "g2/g3 PLANTED culling off: back quad changes %d texels; occlusion off: the quad behind changes %d (both > 100)" % [g2, g3])

	# d NATIVE == GDSCRIPT
	var sph := KMeshPrims.uv_sphere(1.0, 24, 12)
	KMeshUV.project_sphere(sph)
	var mv2 := mvp_for(cp, 1.0)
	var pn := KMeshTPaint.new(sph, 256, true)
	var pg := KMeshTPaint.new(sph, 256, false)
	for p in [pn, pg]:
		p.stamp(mv2, cp, Vector2i(256, 256), Vector2(120, 125), 40.0, red, 0.8, 0.3, 2)
		p.stamp(mv2, cp, Vector2i(256, 256), Vector2(150, 135), 30.0, green, 1.0, 0.0, 2)
	var dd := max_diff(pn.data(), pg.data())
	var wrote := changed_in(KMeshTPaint.new(sph, 256, false).data(), pg.data(), 256, Rect2(0, 0, 1, 1))
	ok(native_ok and pn.engine == "native" and pg.engine == "gdscript" and dd <= 1 and wrote > 300,
		"d NATIVE == GDSCRIPT: engines %s / %s, max byte diff %d (<= 1), %d texels written" % [pn.engine, pg.engine, dd, wrote])
	var nz := pn.data()
	var wi := 0
	for i in range(0, nz.size(), 4):
		if pg.data()[i] > 10 and pg.data()[i] < 245:
			wi = i
			break
	nz[wi] = clampi(nz[wi] + 3, 0, 255)
	ok(max_diff(nz, pg.data()) > 1, "g4 PLANTED a texel nudged by 3/255 fails the equality check (diff %d)" % max_diff(nz, pg.data()))

	# e SPEED
	var big := KMeshPrims.uv_sphere(1.0, 64, 32)
	KMeshUV.project_sphere(big)
	var mv3 := mvp_for(cp, 1280.0 / 720.0)
	var ps := KMeshTPaint.new(big, 2048, true)
	var best := 1e9
	for r in 7:
		var t := Time.get_ticks_usec()
		ps.stamp(mv3, cp, Vector2i(1280, 720), Vector2(640, 360), 150.0, red, 0.5, 0.2, 2)
		best = minf(best, (Time.get_ticks_usec() - t) / 1000.0)
	ok(native_ok and ps.engine == "native" and best <= 8.0, "e SPEED: 2048 tex, %d tris, r 150 px: best of 7 %.2f ms (<= 8), engine %s" % [big.triangle_count(), best, ps.engine])

	# f UNDO
	var pu := KMeshTPaint.new(sph, 256, true)
	var h0 := pu.hash()
	pu.begin_stroke()
	pu.stamp(mv2, cp, Vector2i(256, 256), Vector2(120, 125), 40.0, red, 0.8, 0.3, 2)
	pu.stamp(mv2, cp, Vector2i(256, 256), Vector2(130, 130), 30.0, green, 1.0, 0.3, 2)
	pu.end_stroke()
	var h1 := pu.hash()
	var undone := pu.undo()
	var h2 := pu.hash()
	var redone := pu.redo()
	var h3 := pu.hash()
	pu.undo()
	var bad := pu.data()
	bad[100] = (bad[100] + 1) % 256
	pu.set_data(bad)
	ok(h1 != h0 and undone and h2 == h0 and redone and h3 == h1 and pu.hash() != h0,
		"f UNDO: stroked hash differs; undo restores the exact initial hash %s; redo restores the stroke %s; a one-byte corruption changes the hash %s" % [h2 == h0, h3 == h1, pu.hash() != h0])

	# h TOOL
	var rr: Dictionary = TPaintServe.serve(null, {"shape": "sphere", "x": 256, "y": 256, "radius": 60, "size": 512})
	var rb: Dictionary = TPaintServe.serve(null, {"shape": "sphere", "radius": -3})
	ok(rr.get("ok", false) and int(rr["texels"]) > 100 and rr["engine"] == "native" and float(rr["ms"]) >= 0.0 and not rb.get("ok", true),
		"h TOOL texture_paint: texels %s, islands %s, engine %s, %s ms; radius -3 refused (%s)" % [rr.get("texels"), rr.get("islands"), rr.get("engine"), rr.get("ms"), str(rb.get("error", "")).left(60)])

	await app_bars()
	print("\ntpaint: %s" % ("ALL OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails > 0 else 0)


func app_bars() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var line: Dictionary = {}
	for t in MeshTools.TOOLS:
		if t["id"] == "mesh_tpaint":
			line = t
	ok(not line.is_empty(), "i0 the S box has a \"Model: texture paint on / off\" line")
	if line.is_empty():
		return
	MeshTools.run(line, m)
	await idle(4)
	var pu := KMeshVPaintUI.of(m)
	var ui = m.kmed
	ok(ui != null and ui.on and pu.on and pu.tex_mode and pu.panel.visible, "i1 the line opens the model preview in Texture mode (panel shown %s)" % pu.panel.visible)
	var wc: Vector3 = ui.view.global_position
	m._turn_to(0.0, 0.0, 1.6, wc, false)
	await idle(6)
	var cam: Camera3D = m.cam
	var s0 := cam.unproject_position(wc)
	pu.color = Color(0.0, 1.0, 0.0, 1.0)
	pu.radius = 0.12
	pu.softness = 0.0   # a hard round brush: full colour inside the radius, so the probe pixel beside the click is not on a soft falloff
	pu.strength = 1.0
	m.ui_root.visible = false
	await idle(4)
	await RenderingServer.frame_post_draw
	var a0 := root.get_texture().get_image().get_pixelv(Vector2i((s0 + Vector2(9, 5)).round()))
	m.ui_root.visible = true
	var h0 = pu.tp.hash() if pu.tp != null else ""
	var col0 = ui.mesh.attr_data(KMeshVPaint.CH).duplicate() if ui.mesh.has_attr(KMeshVPaint.CH) else null
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = s0
	ev.global_position = s0
	ev.pressed = true
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(ev)
	await process_frame
	var ev2 := ev.duplicate()
	ev2.pressed = false
	ev2.button_mask = 0
	root.push_input(ev2)
	await idle(3)
	var h1 = pu.tp.hash() if pu.tp != null else ""
	m.ui_root.visible = false
	await idle(4)
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	var a1 := shot.get_pixelv(Vector2i((s0 + Vector2(9, 5)).round()))
	m.ui_root.visible = true
	var grn := a1.g > a1.r + 0.25 and a1.g > a1.b + 0.25
	var was := a0.g > a0.r + 0.25 and a0.g > a0.b + 0.25
	var col_same: bool = (col0 == null and not ui.mesh.has_attr(KMeshVPaint.CH)) or (col0 != null and ui.mesh.attr_data(KMeshVPaint.CH) == col0)
	shot.save_png("C:/Temp/claude/L53/app.png")
	ok(h1 != h0 and grn and not was and col_same,
		"i2 a real click painted the texture (view tex %s, uv fmt %s, hash changed %s), PLACEMENT pixel at the click %s -> %s (green %s, was %s), vertex colours untouched %s" % [ui.view.paint_tex != null, int(ui.view._surf.mesh.surface_get_format(0)) & Mesh.ARRAY_FORMAT_TEX_UV, h1 != h0, a0, a1, grn, was, col_same])
	for down in [true, false]:
		var ke := InputEventKey.new()
		ke.keycode = KEY_Z
		ke.physical_keycode = KEY_Z
		ke.ctrl_pressed = true
		ke.pressed = down
		root.push_input(ke)
		await process_frame
	await idle(3)
	ok(pu.tp.hash() == h0, "i3 Ctrl+Z restores the texture hash exactly (%s)" % (pu.tp.hash() == h0))
