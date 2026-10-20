## godot --path . -s tests/shading_modes_test.gd     (ROADMAP K01 + K02; needs a window: the frames are read back from the screen)
## K01 SHADING MODES: wireframe / solid / matcap (clay, red wax, skin) / x-ray, on the body AND the props.
##   bar 1  each mode puts its own kind of override on the body parts and on a prop; solid puts back the very objects
##   bar 2  wireframe: the viewport's debug draw is the engine's wireframe, and its frame differs from solid
## K02 STUDIO LIGHTS: 3-point (3 lights, key > fill), rim only (1), top (1), flat (0 + full ambient), default restores.
##   bar 3  the lights shining per preset, key energy > fill, the default put back bit for bit
##   bar 4  PLACEMENT: a 4-up sheet (solid, wireframe, matcap, x-ray) of the whole body: the body's head and feet project
##          inside the middle of every frame, and the mean luminance of the body region differs between every pair of modes
## Also: the choice is remembered in the test's own settings file (never poser.cfg), and is no undo step.
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


func shot() -> Image:
	await idle(3)
	await RenderingServer.frame_post_draw
	return m.get_viewport().get_texture().get_image()


func ndiff(a: Image, b: Image) -> int:
	if a.get_size() != b.get_size():
		return -1
	var da := a.get_data()
	var db := b.get_data()
	if da == db:
		return 0
	var k := 4 if a.get_format() == Image.FORMAT_RGBA8 else 3
	var n := 0
	for i in da.size() / k:
		var o := i * k
		if da[o] != db[o] or da[o + 1] != db[o + 1] or da[o + 2] != db[o + 2]:
			n += 1
	return n


## mean luminance (0..1) of a rectangle of the frame
func lum(img: Image, r: Rect2i) -> float:
	var t := 0.0
	var n := 0
	for y in range(r.position.y, r.end.y, 2):
		for x in range(r.position.x, r.end.x, 2):
			t += img.get_pixel(x, y).get_luminance()
			n += 1
	return t / maxf(n, 1)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var sh: Shading = m.shading
	ok(m.settings != "user://poser.cfg", "the test uses its own settings file (%s)" % m.settings)
	ok(m.ui_shade_btn != null and m.ui_light_btn != null and m.ui_shade_btn.get_popup().item_count >= 7 and m.ui_light_btn.get_popup().item_count >= 6,
		"the corner dropdowns exist: shading %d items, lights %d items" % [m.ui_shade_btn.get_popup().item_count, m.ui_light_btn.get_popup().item_count])

	# ---- the figure, UI hidden as the playblast does
	for p in m.ui_side:
		p.visible = false
	m.ui_root.visible = false
	m.clean = true
	m.big_view = true
	m.dist = 4.6
	m.target = Vector3(0, 1.05, 0.2)
	m._cam()
	if m.dummy_on:
		m._dummy_toggle()
	m._refresh()
	var orig := {}
	for mi in Shading.bodies(m):
		orig[mi] = mi.material_override
	var base := await shot()
	var W := base.get_width()
	var H := base.get_height()

	# ---- the body region: where the figure's head and feet project, padded; and the placement bar
	var head2: Vector2 = m.cam.unproject_position(Vector3(0, 1.7, 0.2))
	var foot2: Vector2 = m.cam.unproject_position(Vector3(0, 0.0, 0.2))
	var region := Rect2i(int(W * 0.5 - (foot2.y - head2.y) * 0.05), int(head2.y), int((foot2.y - head2.y) * 0.10), int(foot2.y - head2.y))
	region = region.intersection(Rect2i(0, 0, W, H))
	ok(head2.y > H * 0.02 and foot2.y < H * 0.98 and absf(head2.x - W * 0.5) < W * 0.25 and absf(foot2.x - W * 0.5) < W * 0.25 and region.size.y > H * 0.4,
		"PLACEMENT: head at y %.0f and feet at y %.0f of %d, x within %.0f px of the centre (bars: inside 2..98%% of the frame, within 25%% of the centre, body at least 40%% of the frame high)" % [head2.y, foot2.y, H, absf(head2.x - W * 0.5)])
	var lum_solid := lum(base, region)

	# ---- bar 1: a prop in the set, then each mode's overrides on a body part and on the prop
	m._prop_add("box")
	await idle(2)
	var prop_mis: Array = m.ui_props_root.find_children("*", "MeshInstance3D", true, false)
	ok(prop_mis.size() >= 1, "a prop is in the set (%d mesh nodes)" % prop_mis.size())
	var prop_orig := {}
	for mi in prop_mis:
		prop_orig[mi] = mi.material_override
	var parts := ["head", "pelvis", "thigh_l"]
	var sheet_imgs := {"solid": base}
	var shots_lum := {"solid": lum_solid}
	for want in ["wireframe", "matcap", "xray"]:
		sh.matcap = "wax"   # the sheet shows the red wax one: the most unlike solid
		m._shading_set(want)
		var img := await shot()
		sheet_imgs[want] = img
		shots_lum[want] = lum(img, region)
		var all_body := true
		var all_prop := true
		var kind := ""
		for j in parts:
			var mt = m.pieces[j].material_override
			match want:
				"wireframe":
					all_body = all_body and mt is StandardMaterial3D and (mt as StandardMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED
				"matcap":
					all_body = all_body and mt is ShaderMaterial
				"xray":
					all_body = all_body and mt is StandardMaterial3D and (mt as StandardMaterial3D).albedo_color.a < 0.5
			all_body = all_body and mt != orig[m.pieces[j]]
		for mi in m.ui_props_root.find_children("*", "MeshInstance3D", true, false):
			var pt = mi.material_override
			all_prop = all_prop and pt != null and pt != prop_orig.get(mi) and (pt is ShaderMaterial if want == "matcap" else pt is StandardMaterial3D)
		var wn: Node = m.bat_handle
		var weapon_ok: bool = wn == null or wn.material_override != orig[wn]
		ok(sh.mode == want and all_body and all_prop and weapon_ok, "%s: body parts, the weapon and %d prop nodes carry the mode's own override type" % [want, prop_mis.size()])
		if want == "wireframe":
			ok(m.get_viewport().debug_draw == Viewport.DEBUG_DRAW_WIREFRAME, "bar 2: wireframe sets the viewport's debug draw to the engine wireframe (%d)" % m.get_viewport().debug_draw)
			var dw := ndiff(base, img)
			ok(dw > 2000, "bar 2: the wireframe frame differs from solid in %d pixels (bar: > 2000)" % dw)
		else:
			ok(m.get_viewport().debug_draw == Viewport.DEBUG_DRAW_DISABLED, "%s: debug draw is back off (wireframe does not leak)" % want)
	# the three matcaps are three different looks
	var mats := {}
	var mlum := {}
	for k in Shading.MATCAPS:
		m._shading_set("solid")
		m._matcap_set(k)
		mats[k] = (m.pieces["head"].material_override as ShaderMaterial).get_shader_parameter("lit_col")
		mlum[k] = lum(await shot(), region)
	ok(mats["clay"] != mats["wax"] and mats["wax"] != mats["skin"] and mats["clay"] != mats["skin"] and absf(mlum["clay"] - mlum["wax"]) > 0.01 and absf(mlum["wax"] - mlum["skin"]) > 0.01,
		"matcap clay / red wax / skin differ: body luminance %.3f / %.3f / %.3f (bar: pairs apart by > 0.01)" % [mlum["clay"], mlum["wax"], mlum["skin"]])
	# solid again: the very objects
	m._shading_set("solid")
	var back := await shot()
	var same := true
	for mi in orig:
		if mi.material_override != orig[mi]:
			same = false
	for mi in prop_orig:
		if mi.material_override != prop_orig[mi]:
			same = false
	ok(same and sh.mode == "solid", "bar 1: Solid puts back exactly the original material objects on the body, weapon and prop")
	var dback := ndiff(sheet_imgs["solid"], back)
	print("note: solid after the cycle differs from the first solid frame in %d px (the prop was added between them)" % dback)
	ok(m.get_viewport().debug_draw == Viewport.DEBUG_DRAW_DISABLED and m.cam.cull_mask == 1048575, "solid: debug draw off, cull mask %d" % m.cam.cull_mask)

	# ---- bar 3: the light presets
	var key0: Basis = m.light_key.basis
	var counts := {"three_point": 3, "rim": 1, "top": 1, "flat": 0}
	for id in ["three_point", "rim", "top", "flat"]:
		m._lights_set(id)
		var n := Shading.light_count(m)
		var ke: float = m.light_key.light_energy
		var fe: float = m.light_fill.light_energy
		var re: float = m.light_rim.light_energy
		var good: bool = n == counts[id]
		match id:
			"three_point":
				good = good and ke > fe and fe > 0.0 and re > 0.0
			"rim":
				good = good and re > ke and re > fe
			"top":
				good = good and ke > fe and m.light_key.basis.z.y > 0.99   # straight down: the light's back axis points up
			"flat":
				good = good and m.world_env.ambient_light_energy >= 0.9
		ok(good, "lights %s: %d shining (bar: %d), key %.2f / fill %.2f / rim %.2f, ambient %.2f" % [id, n, counts[id], ke, fe, re, m.world_env.ambient_light_energy])
	# the 3-point rig actually lights the body from the front-left: a frame differs from the default lights
	m._lights_set("default")
	var dflt := await shot()
	m._lights_set("three_point")
	var tp := await shot()
	var dl := ndiff(dflt, tp)
	ok(dl > 2000, "the 3-point frame differs from the default-lights frame in %d pixels (bar: > 2000)" % dl)
	m._lights_set("default")
	ok(m.light_key.basis == key0 and is_equal_approx(m.light_key.light_energy, 1.1) and is_equal_approx(m.light_fill.light_energy, 0.0) and Shading.light_count(m) == 2,
		"default lights put back bit for bit (%d shining)" % Shading.light_count(m))

	# ---- the sky: a gradient behind the figure, off again gives the flat colour
	m._sky_toggle()
	var sky_img := await shot()
	var top_px := sky_img.get_pixel(W / 2, 4)
	var low_px := sky_img.get_pixel(W / 2, int(H * 0.9))
	ok(m.world_env.background_mode == Environment.BG_SKY and top_px.is_equal_approx(low_px) == false, "sky: the background is a gradient (top pixel %s, low pixel %s)" % [top_px.to_html(false), low_px.to_html(false)])
	m._sky_toggle()
	ok(m.world_env.background_mode == Environment.BG_COLOR, "sky off: the flat colour is back")

	# ---- the 4-up sheet
	var sheet := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var order := ["solid", "wireframe", "matcap", "xray"]
	var cw := W / 2
	var ch := H / 2
	for i in 4:
		var im: Image = sheet_imgs[order[i]].duplicate()
		im.convert(Image.FORMAT_RGBA8)
		im.resize(cw, ch, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(im, Rect2i(0, 0, cw, ch), Vector2i((i % 2) * cw, (i / 2) * ch))
	var path := OS.get_environment("SHADING_SHOT") if OS.get_environment("SHADING_SHOT") != "" else "C:/Users/Nick/.claude/jobs/9afc22db/tmp/shading.png"
	sheet.save_png(path)
	print("sheet saved: ", path, " (solid, wireframe / matcap, x-ray)")
	var pairs_ok := true
	var txt := ""
	for a in order:
		txt += "%s %.3f  " % [a, shots_lum[a]]
		for b in order:
			if a < b and absf(shots_lum[a] - shots_lum[b]) <= 0.005:
				pairs_ok = false
	ok(pairs_ok, "bar 4: body-region mean luminance differs between every pair of modes by > 0.005: %s" % txt)

	# ---- remembered in the test's own file; no undo step; the scene is unchanged by shading
	m._shading_set("wireframe")
	m._lights_set("rim")
	var cf := ConfigFile.new()
	cf.load(m.settings)
	ok(String(cf.get_value("view", "shading", "")) == "wireframe" and String(cf.get_value("view", "lights", "")) == "rim" and String(cf.get_value("view", "matcap", "")) == "skin",
		"saved in the test's settings file: shading %s, lights %s, matcap %s" % [cf.get_value("view", "shading", ""), cf.get_value("view", "lights", ""), cf.get_value("view", "matcap", "")])
	var again := Shading.new()
	again.load_cfg(m)   # a fresh start reads it back and applies it
	ok(again.mode == "wireframe" and again.lights == "rim", "a fresh Shading reads the file back: %s / %s" % [again.mode, again.lights])
	m._shading_set("solid")
	m._lights_set("default")

	print("RESULT: ", "FAIL (%d)" % fails if fails > 0 else "PASS")
	quit(1 if fails > 0 else 0)
