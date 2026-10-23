## godot --path . -s tests/matcap_test.gd     (ROADMAP_400 C12; needs a window: the shader's pixels are read back)
## Matcaps for sculpting (scripts/sculpt_matcap.gd). Bars, stated before measuring:
##   1 PICTURES: clay, red wax, skin, chrome, normal are made at startup (128 x 128, no file read); every two of them differ by
##     a mean colour distance > 0.05; the normal matcap's centre is (0.5, 0.5, 1.0) and its right edge (1.0, 0.5, 0.5 + z / 2, z = 0.125 at the
##     outermost texel centre) within 2/255 (the analytic picture is what it says)
##   2 SHADER: a sphere wearing each matcap, drawn off screen (orthographic, own world, linear tone map): the pixel where the
##     normal points at the camera == the texture's centre within 2/255 per channel; the pixel at the right of the disc
##     (normal (0.95, 0, 0.31)) == the texture read at that normal's uv within 4/255 (the mesh's normals are a tessellated
##     sphere's), and for the normal matcap that pixel is red (r > 0.9) and differs from the mirrored (left-edge) read by
##     > 0.3, so a flipped lookup would fail
##   3 IN SCULPT: the sphere wears clay at start; V (a real key) puts red wax on it and the sphere's pixel changes by > 0.1;
##     Shift+V puts clay back and the pixel returns within 2/255; after a stroke (a rebuild) the matcap is still on; skin
##     picked, Esc, the sphere opened again: still skin (remembered for the session); V through to "off" gives the view's
##     own lit material back; V never changes the brush
##   4 PLACEMENT (shot $TMP/matcap_ui.png): the strip is visible, wholly inside the clear view, does not meet the sphere's
##     projected outline, each button is >= 24 px tall; a real mouse click on the "chrome" button picks chrome
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


func key(k: int, shift := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.shift_pressed = shift
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


func click(p: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e)
		await process_frame
	await idle(2)


func shot() -> Image:
	await idle(4)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func dist(a: Color, b: Color) -> float:
	return sqrt(pow(a.r - b.r, 2) + pow(a.g - b.g, 2) + pow(a.b - b.b, 2))


func chan(a: Color, b: Color) -> float:
	return maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))


func mean_dist(a: Image, b: Image) -> float:
	var s := 0.0
	for y in a.get_height():
		for x in a.get_width():
			s += dist(a.get_pixel(x, y), b.get_pixel(x, y))
	return s / (a.get_width() * a.get_height())


func tmp(f: String) -> String:
	return OS.get_environment("TMP").path_join(f) if OS.get_environment("TMP") != "" else "user://" + f


func _init() -> void:
	# 1 pictures
	var kinds := ["clay", "red wax", "skin", "chrome", "normal"]
	var least := INF
	var pair := ""
	for i in kinds.size():
		for j in range(i + 1, kinds.size()):
			var d := mean_dist(SculptMatcap.image(kinds[i]), SculptMatcap.image(kinds[j]))
			if d < least:
				least = d
				pair = "%s / %s" % [kinds[i], kinds[j]]
	var nc := SculptMatcap.sample("normal", Vector2(0.5, 0.5))
	var nr := SculptMatcap.sample("normal", Vector2(1.0, 0.5))
	var sized := true
	for k in kinds:
		sized = sized and SculptMatcap.image(k).get_size() == Vector2i(128, 128)
	var rim_z := SculptMatcap.normal_at(127, 63.5).z   # the outermost texel centre: radius 127/128, z = 0.125
	ok(sized and least > 0.05 and chan(nc, Color(0.5, 0.5, 1.0)) <= 2.0 / 255.0 and chan(nr, Color(1.0, 0.5, 0.5 + 0.5 * rim_z)) <= 2.0 / 255.0,
		"(1) pictures: 5 made, 128 px %s; least mean distance %.3f (%s); normal centre %s, right edge %s" % [sized, least, pair, nc, nr])
	# 2 the shader, off screen
	var vp := SubViewport.new()
	vp.size = Vector2i(255, 255)   # odd: the disc's centre falls on a pixel's centre
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var ball := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.5
	sp.height = 1.0
	sp.radial_segments = 128
	sp.rings = 64
	ball.mesh = sp
	vp.add_child(ball)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.25
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 0, 3), Vector3.ZERO)
	cam.current = true
	await idle(3)
	var cpos := cam.unproject_position(Vector3.ZERO)
	var c_px := Vector2i(cpos.floor())
	var rpx := cam.unproject_position(Vector3(0.5, 0, 0)).x - cam.unproject_position(Vector3.ZERO).x   # the disc's radius in px
	var ex := Vector2i(roundi(c_px.x + 0.95 * rpx), c_px.y)
	var ex_c := Vector2(ex) + Vector2(0.5, 0.5) - cpos
	var en := Vector3(ex_c.x / rpx, -ex_c.y / rpx, 0.0)
	en.z = sqrt(maxf(0.0, 1.0 - en.x * en.x - en.y * en.y))
	var worst_c := 0.0
	var worst_e := 0.0
	var lines := PackedStringArray()
	var red_ok := false
	var mirror_gap := 0.0
	for k in kinds:
		ball.material_override = SculptMatcap.material(k)
		await idle(3)
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		var pc := img.get_pixelv(c_px)
		var want_c := SculptMatcap.sample(k, Vector2(0.5, 0.5))
		var pe := img.get_pixelv(ex)
		var want_e := SculptMatcap.sample(k, SculptMatcap.uv_of(en))
		worst_c = maxf(worst_c, chan(pc, want_c))
		worst_e = maxf(worst_e, chan(pe, want_e))
		lines.append("%s centre %d/255 edge %d/255" % [k, roundi(chan(pc, want_c) * 255.0), roundi(chan(pe, want_e) * 255.0)])
		if k == "normal":
			red_ok = pe.r > 0.9
			mirror_gap = dist(pe, SculptMatcap.sample(k, SculptMatcap.uv_of(Vector3(-en.x, en.y, en.z))))
			img.save_png(tmp("matcap_normal_ball.png"))
	vp.queue_free()
	ok(worst_c <= 2.0 / 255.0 + 1e-6 and worst_e <= 4.0 / 255.0 + 1e-6 and red_ok and mirror_gap > 0.3,
		"(2) shader: centre worst %d/255, right edge worst %d/255 (normal %s), normal matcap edge red %s, mirrored read differs %.2f [%s]" % [roundi(worst_c * 255.0),
		roundi(worst_e * 255.0), en, red_ok, mirror_gap, "; ".join(lines)])
	# 3 in sculpt
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	SculptMatcap.chosen = "clay"
	m._sculpt_start()
	await idle(3)
	ui = m.ksc
	var wc: Vector3 = ui.view.global_position
	m._turn_to(0.0, 0.0, 1.6, wc, false)
	await idle(6)
	var mcam: Camera3D = m.cam
	var cs := mcam.unproject_position(wc)
	var surf := ui.view.get_node("surf") as MeshInstance3D
	var tex_of := func() -> Variant:
		var mt := (ui.view.get_node("surf") as MeshInstance3D).material_override
		return (mt as ShaderMaterial).get_shader_parameter("matcap") if mt is ShaderMaterial else null
	var clay_on: bool = tex_of.call() == SculptMatcap.texture("clay")
	var probe := Vector2i(cs + Vector2(-25, -30))
	var p_clay := (await shot()).get_pixelv(probe)
	var brush0: String = ui.brush
	await key(KEY_V)
	var wax_on: bool = tex_of.call() == SculptMatcap.texture("red wax") and SculptMatcap.chosen == "red wax"
	var p_wax := (await shot()).get_pixelv(probe)
	await key(KEY_V, true)
	var p_back := (await shot()).get_pixelv(probe)
	var back_on: bool = tex_of.call() == SculptMatcap.texture("clay")
	ui.view.mark_dirty()
	ui.view.rebuild()
	var after_rebuild: bool = tex_of.call() == SculptMatcap.texture("clay")
	ui.matcap.pick("skin")
	await key(KEY_ESCAPE)
	await idle(3)
	m._sculpt_start()
	await idle(3)
	surf = ui.view.get_node("surf") as MeshInstance3D
	var kept: bool = SculptMatcap.chosen == "skin" and tex_of.call() == SculptMatcap.texture("skin")
	var seen := []
	for i in 3:   # skin -> chrome -> normal -> off
		await key(KEY_V)
		seen.append(SculptMatcap.chosen)
	var off_lit := SculptMatcap.chosen == "off" and surf.material_override is StandardMaterial3D
	await key(KEY_V)   # and round to clay again
	seen.append(SculptMatcap.chosen)
	off_lit = off_lit and tex_of.call() == SculptMatcap.texture("clay")
	ok(clay_on and wax_on and dist(p_clay, p_wax) > 0.1 and chan(p_clay, p_back) <= 2.0 / 255.0 and back_on and after_rebuild and kept
		and off_lit and ui.brush == brush0,
		"(3) in sculpt: clay at start %s; V -> red wax %s, pixel moved %.2f; Shift+V -> clay %s, back within %d/255; after a rebuild still clay %s; skin kept over Esc + reopen %s; V went %s, off = lit material %s; brush unchanged %s" % [
		clay_on, wax_on, dist(p_clay, p_wax), back_on, roundi(chan(p_clay, p_back) * 255.0), after_rebuild, kept, seen, off_lit, ui.brush == brush0])
	# 4 placement
	ui.matcap.pick("clay")
	await idle(3)
	var strip: PanelContainer = ui.matcap.strip
	var sr := strip.get_global_rect()
	var cl: Rect2 = m.nav_clear_rect()
	var lo := Vector2(INF, INF)
	var hi := -lo
	for dir in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
		var q := mcam.unproject_position(wc + dir * KMeshSculptUI.R)
		lo = lo.min(q)
		hi = hi.max(q)
	var sph := Rect2(lo, hi - lo)
	var tall := true
	for b in ui.matcap._btns.values():
		tall = tall and (b as Button).get_global_rect().size.y >= 24.0
	var cb := ui.matcap._btns["chrome"] as Button
	await click(cb.get_global_rect().get_center())
	var clicked := SculptMatcap.chosen == "chrome"
	var img := await shot()
	img.save_png(tmp("matcap_ui.png"))
	ok(strip.visible and cl.encloses(sr) and not sr.intersects(sph) and tall and clicked,
		"(4) placement: strip %s inside the clear view %s %s, sphere outline %s apart %s, buttons >= 24 px %s, a click on chrome picks it %s (shot %s)" % [
		sr, cl, cl.encloses(sr), sph, not sr.intersects(sph), tall, clicked, tmp("matcap_ui.png")])
	SculptMatcap.chosen = "clay"
	print("MATCAP ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails else 0)
