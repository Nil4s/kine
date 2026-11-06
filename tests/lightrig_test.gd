## godot --path . -s tests/lightrig_test.gd     (L25 LIGHT RIG; needs a window: the frames are read back from a SubViewport and the screen)
## GAP_AUDIT_1106 rendering item 4: light-rig presets, an HDRI picker and a light-linking toggle (scripts/light_rig.gd).
## THESE BARS WERE WRITTEN AND COMMITTED BEFORE THE IMPLEMENTATION. Numbers come from the lane brief, not from a run.
## MEASUREMENT PROTOCOL (fixed before the first run): an isolated stage (own World3D, 480x360): a grey sphere (albedo 0.5,
## radius 0.5 m) at (0,1,0), a floor at y=0, a perspective camera at (0,1,4) looking along -z, the three directional lights
## and the environment set by LightRig.apply_rig exactly as the app does. Pixels are read back and turned to LINEAR light
## (sRGB -> linear). The lit side is a 5x5 patch where the sphere's normal points 45 deg to the camera's left on the equator,
## the shadow side the same 45 deg to the right (the preset's key stands on the left, LightRig's azimuth + = camera left).
## key/fill ratio = lit luminance / shadow luminance.
##   1 RATIOS: studio (three_point) 2:1..4:1; dramatic (noir) >= 8:1; overcast <= 1.5:1; sunset 3:1..12:1, night 2:1..12:1
##     (the last two are this lane's own bands); all five pairwise distinct (each pair differs by >= 15 percent).
##     PLANTED: a flat rig (equal key and fill on opposite sides) measures about 1:1 and the same band check REFUSES it as
##     studio and as dramatic, so the check can fail; a rig with the key switched off measures about 1:1 as well.
##   2 HDRI: the mean background colour (sRGB, 0..1) of the sky render changes by >= 0.10 (Euclidean) when the map is
##     swapped clear_day -> sunset, every pair of the shipped maps differs by >= 0.04; rotation is set on the environment
##     (sky_rotation.y = the degrees); intensity 0.5 renders darker than 1.0 darker than 2.0 (0.5 <= 0.75 x of 1.0).
##     PLANTED: swapping to the SAME map moves the mean by < 0.01 and fails the margin check.
##   3 LINKING: character-only lights (LightRig.set_link): with the link ON the floor's luminance stays the same
##     (within 1 percent) when the key's energy drops to a fifth, while the character's changes by >= 15 percent; with the
##     link OFF both change by >= 15 percent. Per light: link the key only, then changing the FILL still moves the floor.
##     PLANTED: the floor must be lit at all (luminance > 0.02, else "unchanged" is vacuous), and a "link ON" run whose
##     lights were left at the everything mask fails the floor-unchanged check.
##   4 UNDO (in the app): a preset change is one undo step: Ctrl+Z puts the lights and the shot back exactly.
##     PLANTED: the preset really moved the lights (the before and after states differ), so "equal after undo" is not vacuous.
##   5 WIRING: the panel opens with a button per preset, the HDRI list, rotation and intensity sliders, a link check per light;
##     the commands exist in the palette; the app's functions drive the real world environment and lights.
## Set LIGHTRIG_SHEET=<png> to write the 5-preset contact sheet of the default character (1920x1080 frames, scaled down).
extends SceneTree

var fails := 0
var vp: SubViewport
var cam: Camera3D
var sph: MeshInstance3D
var flr: MeshInstance3D
var key: DirectionalLight3D
var fill: DirectionalLight3D
var rim: DirectionalLight3D
var env: Environment
const CAM_POS := Vector3(0, 1, 4)
const CAM_AIM := Vector3(0, 1, 0)
const SC := Vector3(0, 1, 0)


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func stage() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(480, 360)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment = env
	vp.add_child(we)
	cam = Camera3D.new()
	cam.fov = 40
	vp.add_child(cam)
	cam.position = CAM_POS
	cam.look_at(CAM_AIM)
	sph = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 64
	sm.rings = 32
	sph.mesh = sm
	var mt := StandardMaterial3D.new()
	mt.albedo_color = Color(0.5, 0.5, 0.5)
	sph.material_override = mt
	sph.position = SC
	vp.add_child(sph)
	flr = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8, 8)
	flr.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.7, 0.7, 0.7)
	flr.material_override = fm
	flr.layers = 1 | LightRig.WORLD_BIT   # the floor is "the world"; the sphere stays on layer 1 (the character)
	vp.add_child(flr)
	for pair in [["key", 0], ["fill", 1], ["rim", 2]]:
		var L := DirectionalLight3D.new()
		L.shadow_enabled = false
		vp.add_child(L)
		match pair[1]:
			0: key = L
			1: fill = L
			2: rim = L


func apply(id: String) -> void:
	LightRig.apply_rig(LightRig.rig(id, CAM_POS, CAM_AIM), key, fill, rim, env)


func frame() -> Image:
	await idle(3)
	await RenderingServer.frame_post_draw
	return vp.get_texture().get_image()


func lin(c: Color) -> float:
	var l := c.srgb_to_linear()
	return 0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b


## mean linear luminance of a 5x5 patch at a screen point
func patch(img: Image, p: Vector2) -> float:
	var s := 0.0
	var n := 0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			s += lin(img.get_pixel(clampi(int(p.x) + dx, 0, img.get_width() - 1), clampi(int(p.y) + dy, 0, img.get_height() - 1)))
			n += 1
	return s / float(n)


func sph_px(az: float) -> Vector2:
	var n := LightRig.source_dir(Vector3(0, 0, -1), az, 0.0)
	return cam.unproject_position(SC + n * 0.5)


func floor_px() -> Vector2:
	return cam.unproject_position(Vector3(1.6, 0, 1.2))


## key/fill ratio: lit side over shadow side, linear light
func ratio(img: Image) -> float:
	return patch(img, sph_px(45.0)) / maxf(1e-6, patch(img, sph_px(-45.0)))


## the band check the ratio bars use (the planted controls call it too)
func in_band(id: String, r: float) -> bool:
	var b := {"three_point": [2.0, 4.0], "noir": [8.0, 1e9], "overcast": [0.0, 1.5], "sunset": [3.0, 12.0], "night": [2.0, 12.0]}
	return r >= b[id][0] and r <= b[id][1]


## mean sRGB colour of a frame (every 4th pixel)
func mean_col(img: Image) -> Color:
	var s := Vector3.ZERO
	var n := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			s += Vector3(c.r, c.g, c.b)
			n += 1
	s /= float(n)
	return Color(s.x, s.y, s.z)


func cdist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func lights(m: Node) -> Array:
	var out := []
	for L in [m.light_key, m.light_fill, m.light_rim]:
		out.append([L.light_energy, L.light_color, L.basis])
	out.append([m.world_env.ambient_light_energy, m.world_env.ambient_light_color, m.world_env.adjustment_enabled, m.world_env.adjustment_brightness, m.world_env.adjustment_contrast])
	return out


func same(a: Array, b: Array) -> bool:
	for i in 3:
		if absf(a[i][0] - b[i][0]) > 1e-6 or not (a[i][1] as Color).is_equal_approx(b[i][1]) or not (a[i][2] as Basis).is_equal_approx(b[i][2]):
			return false
	return absf(a[3][0] - b[3][0]) < 1e-6 and (a[3][1] as Color).is_equal_approx(b[3][1]) and a[3][2] == b[3][2] and absf(a[3][3] - b[3][3]) < 1e-6 and absf(a[3][4] - b[3][4]) < 1e-6


func pose() -> Dictionary:
	var R := Body.new()
	R.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	R.fk()
	return R.to_dict()


func _init() -> void:
	stage()
	await idle(4)

	# ---------------------------------------------------------------- 1 the ratios on the grey sphere
	ok(LightRig.ALL_IDS.size() == 5, "1 five presets are named: %s" % str(LightRig.ALL_IDS))
	var rs := {}
	for id in LightRig.ALL_IDS:
		apply(id)
		var img := await frame()
		rs[id] = ratio(img)
		print("  %s lit %.4f shadow %.4f ratio %.2f:1" % [id, patch(img, sph_px(45.0)), patch(img, sph_px(-45.0)), rs[id]])
	ok(in_band("three_point", rs["three_point"]), "1 studio 3-point measures %.2f:1 (bar 2..4)" % rs["three_point"])
	ok(in_band("noir", rs["noir"]), "1 dramatic measures %.2f:1 (bar >= 8)" % rs["noir"])
	ok(in_band("overcast", rs["overcast"]), "1 overcast measures %.2f:1 (bar <= 1.5)" % rs["overcast"])
	ok(in_band("sunset", rs["sunset"]), "1 sunset measures %.2f:1 (bar 3..12)" % rs["sunset"])
	ok(in_band("night", rs["night"]), "1 night measures %.2f:1 (bar 2..12)" % rs["night"])
	var dist_ok := true
	for i in LightRig.ALL_IDS.size():
		for j in range(i + 1, LightRig.ALL_IDS.size()):
			var a: float = rs[LightRig.ALL_IDS[i]]
			var b: float = rs[LightRig.ALL_IDS[j]]
			if absf(a - b) / maxf(a, b) < 0.15:
				dist_ok = false
				print("  not distinct: %s %.2f vs %s %.2f" % [LightRig.ALL_IDS[i], a, LightRig.ALL_IDS[j], b])
	ok(dist_ok, "1 the five ratios are pairwise distinct (>= 15 percent apart)")
	# planted: a flat rig and a key-off rig must read about 1:1 and be refused by the band checks
	var flat := LightRig.rig("three_point", CAM_POS, CAM_AIM)
	flat["key"]["dir"] = -LightRig.source_dir(Vector3(0, 0, -1), 45.0, 20.0)
	flat["fill"]["dir"] = -LightRig.source_dir(Vector3(0, 0, -1), -45.0, 20.0)
	flat["key"]["energy"] = 1.0
	flat["fill"]["energy"] = 1.0
	flat["rim"]["energy"] = 0.0
	flat["adjust"] = {"brightness": 1.0, "contrast": 1.0}
	LightRig.apply_rig(flat, key, fill, rim, env)
	var rf := ratio(await frame())
	ok(rf < 1.5 and not in_band("three_point", rf) and not in_band("noir", rf), "1 PLANTED flat rig measures %.2f:1 and the studio and dramatic bands refuse it" % rf)
	flat["key"]["energy"] = 0.0
	LightRig.apply_rig(flat, key, fill, rim, env)
	var rk := ratio(await frame())
	ok(rk < 1.0 and not in_band("three_point", rk), "1 PLANTED key-off rig measures %.2f:1 (the key is what makes the ratio)" % rk)

	# ---------------------------------------------------------------- 2 the HDRI picker
	ok(LightRig.SKY_IDS.size() >= 4, "2 the picker lists %d maps: %s" % [LightRig.SKY_IDS.size(), str(LightRig.SKY_IDS)])
	var means := {}
	for sid in LightRig.SKY_IDS:
		LightRig.apply_hdri(env, sid, 0.0, 1.0)
		means[sid] = mean_col(await frame())
	var pairs_ok := true
	for i in LightRig.SKY_IDS.size():
		for j in range(i + 1, LightRig.SKY_IDS.size()):
			var dd := cdist(means[LightRig.SKY_IDS[i]], means[LightRig.SKY_IDS[j]])
			if dd < 0.04:
				pairs_ok = false
				print("  maps too alike: %s %s %.3f" % [LightRig.SKY_IDS[i], LightRig.SKY_IDS[j], dd])
	ok(pairs_ok, "2 every pair of maps differs in mean background colour by >= 0.04")
	var swap_d := cdist(means["clear_day"], means["sunset"])
	ok(swap_d >= 0.10, "2 swapping clear_day -> sunset moves the mean background by %.3f (bar 0.10)" % swap_d)
	LightRig.apply_hdri(env, "sunset", 0.0, 1.0)
	var same_d := cdist(mean_col(await frame()), means["sunset"])
	ok(same_d < 0.01 and not (same_d >= 0.10), "2 PLANTED swapping to the same map moves the mean by %.4f and the margin check refuses it" % same_d)
	ok(env.background_mode == Environment.BG_SKY and env.sky != null, "2 the swap really puts a sky on the world environment")
	LightRig.apply_hdri(env, "clear_day", 90.0, 1.0)
	ok(absf(env.sky_rotation.y - deg_to_rad(90.0)) < 1e-5, "2 rotation 90 deg is on the environment (sky_rotation.y %.3f)" % env.sky_rotation.y)
	var lum_i := {}
	for it in [0.5, 1.0, 2.0]:
		LightRig.apply_hdri(env, "clear_day", 0.0, it)
		var mc := mean_col(await frame())
		lum_i[it] = 0.2126 * mc.r + 0.7152 * mc.g + 0.0722 * mc.b
	ok(lum_i[0.5] < lum_i[1.0] and lum_i[1.0] < lum_i[2.0] and lum_i[0.5] <= 0.75 * lum_i[1.0], "2 intensity 0.5 / 1 / 2 renders %.3f / %.3f / %.3f (darker to brighter, 0.5 <= 0.75 of 1)" % [lum_i[0.5], lum_i[1.0], lum_i[2.0]])
	LightRig.apply_hdri(env, "", 0.0, 1.0)
	ok(env.background_mode == Environment.BG_COLOR, "2 no map: the flat world colour again")

	# ---------------------------------------------------------------- 3 light linking
	apply("three_point")
	env.ambient_light_energy = 0.4   # the floor must be lit by something that does not change, or "same" is vacuous
	env.adjustment_enabled = false
	var base_img := await frame()
	var f0 := patch(base_img, floor_px())
	var c0 := patch(base_img, sph_px(45.0))
	ok(f0 > 0.02, "3 PLANTED the floor is lit at all: luminance %.4f > 0.02 (else 'unchanged' proves nothing)" % f0)
	# unlinked (everything mask) with the key dropped to a fifth
	for L in [key, fill, rim]:
		LightRig.set_link(L, false)
	var e_key := key.light_energy
	key.light_energy = e_key * 0.2
	var off_img := await frame()
	var f_off := patch(off_img, floor_px())
	var c_off := patch(off_img, sph_px(45.0))
	ok(absf(f_off - f0) / f0 >= 0.15 and absf(c_off - c0) / c0 >= 0.15, "3 link OFF: floor %.4f -> %.4f and character %.4f -> %.4f both change by >= 15 percent" % [f0, f_off, c0, c_off])
	ok(not (absf(f_off - f0) / f0 <= 0.01), "3 PLANTED a link-ON claim with the everything mask fails the floor-unchanged check (floor moved %.1f percent)" % (100.0 * absf(f_off - f0) / f0))
	# linked
	key.light_energy = e_key
	for L in [key, fill, rim]:
		LightRig.set_link(L, true)
	ok(key.light_cull_mask == LightRig.link_mask(true) and (key.light_cull_mask & LightRig.WORLD_BIT) == 0, "3 a linked light's cull mask leaves out the world layer (mask %d)" % key.light_cull_mask)
	var on0 := await frame()
	var f_on0 := patch(on0, floor_px())
	var c_on0 := patch(on0, sph_px(45.0))
	key.light_energy = e_key * 0.2
	var on1 := await frame()
	var f_on1 := patch(on1, floor_px())
	var c_on1 := patch(on1, sph_px(45.0))
	ok(absf(f_on1 - f_on0) / maxf(f_on0, 1e-6) <= 0.01, "3 link ON: the floor stays %.4f -> %.4f (within 1 percent)" % [f_on0, f_on1])
	ok(absf(c_on1 - c_on0) / c_on0 >= 0.15, "3 link ON: the character changes %.4f -> %.4f (>= 15 percent)" % [c_on0, c_on1])
	# per light: key linked only, the fill still reaches the floor
	key.light_energy = e_key
	LightRig.set_link(fill, false)
	LightRig.set_link(rim, false)
	var p0 := patch(await frame(), floor_px())
	fill.light_energy = 3.0
	var p1 := patch(await frame(), floor_px())
	ok(absf(p1 - p0) / maxf(p0, 1e-6) >= 0.10, "3 per light: key linked, fill not: raising the fill moves the floor %.4f -> %.4f" % [p0, p1])

	# ---------------------------------------------------------------- 4 + 5 in the app
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var S := Scene.new()
	S.name = "zz_lightrig"
	S.fps = 24
	S.add("c0", pose())
	m.S = S
	m._rebuild_cards()
	m.sel_card = 0
	m.playhead = 0.0
	m._refresh()
	await idle(3)
	var before := lights(m)
	var shots0: Array = S.shots.duplicate(true)
	ok(m.lr_preset("noir"), "4 lr_preset('noir') works with no shot camera yet (the view keys one, in the same step)")
	await idle(2)
	var after := lights(m)
	ok(not same(before, after) and String(m.S.shots[0].get("light", "")) == "noir", "4 PLANTED the preset really moved the lights (before and after differ), shot light = noir")
	m.lr_preset("night")
	await idle(2)
	var night := lights(m)
	m._undo()
	await idle(2)
	ok(String(m.S.shots[0].get("light", "")) == "noir" and same(lights(m), after), "4 one undo after 'night' is back to 'noir', lights exactly as before")
	m._undo()
	await idle(2)
	ok(m.S.shots == shots0 and same(lights(m), before), "4 the next undo is the start: shots and lights exactly as they were")
	m._redo()
	await idle(2)
	ok(String(m.S.shots[0].get("light", "")) == "noir" and same(lights(m), after), "4 redo brings 'noir' back")
	ok(not same(night, after), "4 night and noir are different looks")

	# the picker on the real world environment
	m.lr_hdri("sunset")
	m.lr_hdri_rot(120.0)
	m.lr_hdri_int(1.5)
	await idle(2)
	var we: Environment = m.world_env
	ok(we.background_mode == Environment.BG_SKY and absf(we.sky_rotation.y - deg_to_rad(120.0)) < 1e-5 and absf(we.background_energy_multiplier - 1.5) < 1e-5, "5 the app's world environment shows the map: sky, rotation 120, intensity 1.5")
	m.lr_hdri("")
	await idle(2)
	ok(m.world_env.background_mode == Environment.BG_COLOR, "5 no map: the flat world colour")
	# linking in the app
	m.lr_set_link("key", true)
	ok(m.light_key.light_cull_mask == LightRig.link_mask(true) and m.light_fill.light_cull_mask == LightRig.link_mask(false), "5 the key is character-only, the fill still lights everything")
	m.lr_set_link("key", false)
	ok(m.light_key.light_cull_mask == LightRig.link_mask(false), "5 key back to everything")
	m.lr_set_link("rim", true)
	m._light_preset("")
	await idle(2)
	ok(m.light_rim.light_cull_mask == LightRig.link_mask(true), "5 the link survives a preset change (the rim stays character-only)")
	m.lr_set_link("rim", false)
	# the panel
	m.lr_ui.show()
	await idle(3)
	var P: Node = m.ui_find
	var names := []
	for id in LightRig.ALL_IDS:
		names.append("lr_preset_" + id)
	for k in ["lr_hdri", "lr_rot", "lr_int", "lr_link_key", "lr_link_fill", "lr_link_rim"]:
		names.append(k)
	var miss := []
	for nm in names:
		if P.find_child(nm, true, false) == null:
			miss.append(nm)
	ok(miss.is_empty(), "5 the panel has a control for every preset, the picker, rotation, intensity and each link (missing: %s)" % str(miss))
	var cmds: Array = m._commands().map(func(c): return String(c["name"]))
	var want_cmds := ["Light: overcast", "Light: sunset", "Light: night", "Light: sky map...", "Light: rig panel"]
	var no_cmd := []
	for w in want_cmds:
		if not (w in cmds):
			no_cmd.append(w)
	ok(no_cmd.is_empty(), "5 palette commands exist (missing: %s)" % str(no_cmd))

	# ---------------------------------------------------------------- contact sheet
	var sheet := OS.get_environment("LIGHTRIG_SHEET")
	if sheet != "":
		await contact_sheet(m, sheet)
	print("lightrig: %d fail" % fails)
	quit(fails)


## the 5 presets on the default character, a 1920x1080 window rendered through the shot camera, scaled to 640 wide
func contact_sheet(m: Node, path: String) -> void:
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	await idle(6)
	var S: Scene = m.S
	m.clean = true
	m.ui_root.visible = false
	m.ui_find.visible = false
	m._shot_toggle()
	await idle(8)
	var rect: Rect2i = m.shot_rect()
	var tiles := []
	for id in LightRig.ALL_IDS:
		m.lr_preset(id)
		await idle(6)
		await RenderingServer.frame_post_draw
		var im: Image = root.get_texture().get_image().get_region(rect)
		print("  sheet %s frame %dx%d" % [id, im.get_width(), im.get_height()])
		im.convert(Image.FORMAT_RGB8)
		im.resize(640, int(640.0 * float(im.get_height()) / float(im.get_width())), Image.INTERPOLATE_LANCZOS)
		tiles.append(im)
	var w: int = (tiles[0] as Image).get_width()
	var h: int = (tiles[0] as Image).get_height()
	var out := Image.create(w * 3, h * 2, false, Image.FORMAT_RGB8)
	for i in tiles.size():
		out.blit_rect(tiles[i], Rect2i(0, 0, w, h), Vector2i((i % 3) * w, (i / 3) * h))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	out.save_png(path)
	print("  contact sheet written: %s (%dx%d)" % [path, out.get_width(), out.get_height()])
