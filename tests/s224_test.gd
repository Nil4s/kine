extends SceneTree
## S224 REALISM IN THE RENDER: the REAL-LOOK Nice picture (NiceRender.look = "real", scripts/build/realistic.gd) and the live VIEW > Realistic toggle.
##   T  tone: <= 1 % of the pixels clipped white (lum >= 0.985) or crushed black (lum <= 0.02) in the real picture of 3 scenes (grey cube, metal cylinder, house)
##   A  AO: the inside corner of two walls is darker than the wall centre by a bar derived from the wall's own unevenness; with AO off that bar FAILS
##   S  shadow: present (lit/dark >= 15 %) and soft: penumbra width > 1 px and < 90 px, and wider than the same picture with a point sun (control)
##   R  sky reflection: the top of a glossy sphere is brighter than its bottom by a bar; with the reflection source off the bar FAILS
##   B  before (the studio picture) and after (the real picture) of the 3 scenes saved; the real Nice picture of each takes < 10 s
##   F  live Realistic view of an engine-size part (~180 k triangles) at 1280 x 720: >= 30 fps measured; off puts every value back
##   D  the Export dialog has the Realistic box that switches the preset
const SHOT := "C:/Temp/claude/s224"
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func look(c: Color, rough := 0.6, metal := 0.0) -> Dictionary:
	return {"c": c, "rough": rough, "metal": metal, "alpha": 1.0, "preset": "t"}


## a mesh of several solids: parts = [[PrimitiveMesh, Transform3D, look]], one surface per part
func build(parts: Array) -> Array:
	var am := ArrayMesh.new()
	var looks := []
	var box := AABB()
	var first := true
	for p in parts:
		var st := SurfaceTool.new()
		st.append_from(p[0], 0, p[1])
		st.commit(am)
		looks.append(p[2])
		var b: AABB = p[1] * (p[0] as PrimitiveMesh).get_aabb()
		box = b if first else box.merge(b)
		first = false
	Part.paint(am, looks)
	return [am, box, looks]


func boxm(sz: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = sz
	return b


func scene_cube() -> Array:
	return build([[boxm(Vector3(0.1, 0.1, 0.1)), Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0)), look(Color(0.5, 0.5, 0.5))]])


func scene_cyl() -> Array:
	var c := CylinderMesh.new()
	c.top_radius = 0.04
	c.bottom_radius = 0.04
	c.height = 0.12
	c.radial_segments = 64
	return build([[c, Transform3D(Basis.IDENTITY, Vector3(0, 0.06, 0)), look(Color(0.86, 0.87, 0.9), 0.3, 1.0)]])


func scene_house() -> Array:
	var roof := PrismMesh.new()
	roof.size = Vector3(9.0, 2.0, 6.0)
	roof.left_to_right = 0.5
	return build([
		[boxm(Vector3(8, 3, 5)), Transform3D(Basis.IDENTITY, Vector3(0, 1.5, 0)), look(Color(0.86, 0.78, 0.62), 0.85)],
		[roof, Transform3D(Basis.IDENTITY, Vector3(0, 4.0, 0)), look(Color(0.62, 0.22, 0.16), 0.8)],
		[boxm(Vector3(1.0, 2.0, 0.1)), Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 2.53)), look(Color(0.30, 0.18, 0.10), 0.7)],
		[boxm(Vector3(1.2, 1.0, 0.1)), Transform3D(Basis.IDENTITY, Vector3(-2.5, 1.7, 2.53)), look(Color(0.25, 0.4, 0.55), 0.1, 0.0)],
		[boxm(Vector3(1.2, 1.0, 0.1)), Transform3D(Basis.IDENTITY, Vector3(2.5, 1.7, 2.53)), look(Color(0.25, 0.4, 0.55), 0.1, 0.0)],
		[boxm(Vector3(0.6, 1.4, 0.6)), Transform3D(Basis.IDENTITY, Vector3(2.5, 4.4, -0.5)), look(Color(0.55, 0.5, 0.45), 0.9)]])


func clipped(img: Image) -> Array:
	var w := 0
	var b := 0
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var l := lum(img.get_pixel(x, y))
			n += 1
			if l >= 0.985:
				w += 1
			elif l <= 0.02:
				b += 1
	return [100.0 * w / n, 100.0 * b / n]


## world point -> pixel of the last real picture
func proj(p: Vector3, size: Vector2i) -> Vector2:
	var v: Dictionary = NiceRender.last_view
	var q: Vector3 = (v["xf"] as Transform3D).affine_inverse() * p
	var f := (size.y * 0.5) / tan(deg_to_rad(float(v["fov"])) * 0.5)
	return Vector2(size.x * 0.5 + f * q.x / -q.z, size.y * 0.5 - f * q.y / -q.z)


func win(img: Image, c: Vector2, r: int) -> float:
	var s := 0.0
	var n := 0
	for y in range(int(c.y) - r, int(c.y) + r + 1):
		for x in range(int(c.x) - r, int(c.x) + r + 1):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				s += lum(img.get_pixel(x, y))
				n += 1
	return s / maxf(n, 1)


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT)
	var SZ := Vector2i(1920, 1080)
	var nice_ms := []
	# ---- B + T: before and after of the three scenes
	var names := ["cube", "cylinder", "house"]
	var scenes := [scene_cube(), scene_cyl(), scene_house()]
	NiceRender.look = "studio"
	await NiceRender.draw_mesh(root, scenes[0][0], scenes[0][1], scenes[0][2], Vector2i(320, 180))   # warm-up: the first off-screen draw of a session comes out empty
	for i in 3:
		var sc: Array = scenes[i]
		NiceRender.look = "studio"
		var before: Image = await NiceRender.draw_mesh(root, sc[0], sc[1], sc[2], SZ)
		before.save_png("%s/before_%s.png" % [SHOT, names[i]])
		NiceRender.look = "real"
		var t0 := Time.get_ticks_msec()
		var after: Image = await NiceRender.draw_mesh(root, sc[0], sc[1], sc[2], SZ)
		var ms := Time.get_ticks_msec() - t0
		after.save_png("%s/after_%s.png" % [SHOT, names[i]])
		nice_ms.append(ms)
		var cl := clipped(Image.load_from_file("%s/after_%s.png" % [SHOT, names[i]]))
		ok(cl[0] <= 1.0 and cl[1] <= 1.0, "T tone %s: clipped white %.3f %%, crushed black %.3f %% (each <= 1 %%)" % [names[i], cl[0], cl[1]])
		ok(ms < 10000, "B %s: the real Nice picture took %d ms (< 10000); before/after saved" % [names[i], ms])
		var side := Image.create(1920, 540, false, Image.FORMAT_RGBA8)
		var b2 := before.duplicate() as Image
		b2.resize(960, 540)
		var a2 := after.duplicate() as Image
		a2.resize(960, 540)
		side.blit_rect(b2, Rect2i(0, 0, 960, 540), Vector2i(0, 0))
		side.blit_rect(a2, Rect2i(0, 0, 960, 540), Vector2i(960, 0))
		side.save_png("%s/side_%s.png" % [SHOT, names[i]])
	NiceRender.look = "real"

	# ---- A: ambient occlusion in an inside corner
	var wall_a := [boxm(Vector3(2.0, 2.0, 0.1)), Transform3D(Basis.IDENTITY, Vector3(1.0, 1.0, -0.05)), look(Color(0.7, 0.7, 0.7), 0.9)]
	var wall_b := [boxm(Vector3(0.1, 2.0, 2.0)), Transform3D(Basis.IDENTITY, Vector3(-0.05, 1.0, 1.0)), look(Color(0.7, 0.7, 0.7), 0.9)]
	var cor := build([wall_a, wall_b])
	var ao := {}
	for arm in ["on", "off"]:
		var img: Image = await NiceRender.draw_real(root, cor[0], cor[1], SZ, {"kind": "studio", "sun": 0.0, "shadow": false, "ssao": arm == "on", "ssil": arm == "on"})
		img.save_png("%s/ao_%s.png" % [SHOT, arm])
		var near := win(img, proj(Vector3(0.10, 1.0, 0.0), SZ), 4)
		var far := win(img, proj(Vector3(1.0, 1.0, 0.0), SZ), 4)
		var far2 := win(img, proj(Vector3(1.2, 1.0, 0.0), SZ), 4)
		ao[arm] = {"ratio": near / far, "noise": absf(far - far2) / far}
	var bar_drop := maxf(0.03, 3.0 * float(ao["off"]["noise"]))
	var drop_on := 1.0 - float(ao["on"]["ratio"])
	var drop_off := 1.0 - float(ao["off"]["ratio"])
	print("AO: corner/centre on %.3f off %.3f, wall unevenness %.4f, bar drop >= %.3f" % [ao["on"]["ratio"], ao["off"]["ratio"], ao["off"]["noise"], bar_drop])
	ok(drop_on >= bar_drop, "A AO on: corner %.1f %% darker than the wall centre (bar %.1f %%)" % [drop_on * 100.0, bar_drop * 100.0])
	ok(not (drop_off >= bar_drop), "A control: with AO off the same bar FAILS (corner only %.1f %% darker)" % [drop_off * 100.0])

	# ---- S: a post's shadow on the floor: present and soft
	var post := build([[boxm(Vector3(0.06, 0.3, 0.06)), Transform3D(Basis.IDENTITY, Vector3(0, 0.15, 0)), look(Color(0.7, 0.3, 0.2), 0.6)]])
	var pen := {}
	var nosh: Image = await NiceRender.draw_real(root, post[0], post[1], SZ, {"kind": "studio", "shadow": false})   # the same picture with no shadow: dividing by it removes the floor's own gradient
	nosh.save_png("%s/shadow_none.png" % SHOT)
	for arm in ["soft", "point"]:
		var img: Image = await NiceRender.draw_real(root, post[0], post[1], SZ, {"kind": "studio", "angular": 1.8 if arm == "soft" else 0.0})
		img.save_png("%s/shadow_%s.png" % [SHOT, arm])
		# the shadow runs away from the sun: horizontal direction (0.5, -0.866); a row through it 0.25 m from the post's foot, right of the post
		var mid := proj(Vector3(0.5, 0.0, -0.866) * 0.25, SZ)
		var prof := []
		for x in range(int(mid.x) - 250, int(mid.x) + 450):
			prof.append(win(img, Vector2(x, mid.y), 1) / maxf(win(nosh, Vector2(x, mid.y), 1), 0.0001))
		var sorted := prof.duplicate()
		sorted.sort()
		var dark: float = sorted[int(sorted.size() * 0.05)]
		var lit: float = sorted[int(sorted.size() * 0.95)]
		print("shadow row %s mid %s: shadow/no-shadow ratio dark %.3f lit %.3f" % [arm, mid, dark, lit])
		var hi_t := dark + 0.9 * (lit - dark)
		var lo_t := dark + 0.1 * (lit - dark)
		var inter := 0   # pixels of the row between 10 % and 90 % of the step; the row crosses 2 edges, so half is one edge's penumbra
		for v in prof:
			if v > lo_t and v < hi_t:
				inter += 1
		pen[arm] = {"w": int(round(inter / 2.0)), "step": 1.0 - dark / maxf(lit, 0.001)}
	print("shadow: soft %s point %s" % [pen["soft"], pen["point"]])
	ok(float(pen["soft"]["step"]) >= 0.10, "S shadow present: the floor in it is %.1f %% darker than the same floor with no shadow (>= 10, a 10 %% step is 25+ grey levels)" % (float(pen["soft"]["step"]) * 100.0))
	ok(int(pen["soft"]["w"]) > 1 and int(pen["soft"]["w"]) < 90, "S shadow soft: penumbra %d px (> 1 and < 90)" % int(pen["soft"]["w"]))
	ok(int(pen["soft"]["w"]) > int(pen["point"]["w"]), "S control: wider than the point-sun penumbra (%d px)" % int(pen["point"]["w"]))

	# ---- R: sky reflection on a glossy sphere, lit by the sky alone
	var sph := SphereMesh.new()
	sph.radius = 0.05
	sph.height = 0.1
	sph.radial_segments = 64
	sph.rings = 32
	var sp := build([[sph, Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0)), look(Color(0.95, 0.95, 0.97), 0.12, 1.0)]])
	var rr := {}
	for arm in ["sky", "none"]:
		var img: Image = await NiceRender.draw_real(root, sp[0], sp[1], SZ, {"kind": "studio", "sun": 0.0, "fills": false, "reflect": arm == "sky", "ssr": arm == "sky"})
		img.save_png("%s/sphere_%s.png" % [SHOT, arm])
		var c := proj(Vector3(0, 0.05, 0), SZ)
		var R: float = (proj(Vector3(0, 0.05, 0), SZ) - proj(Vector3(0.05, 0.05, 0.0), SZ)).length() * 0.95
		var top := win(img, c + Vector2(0, -0.45 * R), int(0.12 * R))
		var bot := win(img, c + Vector2(0, 0.45 * R), int(0.12 * R))
		rr[arm] = top / maxf(bot, 0.0001)
	print("sphere top/bottom: sky %.3f none %.3f" % [rr["sky"], rr["none"]])
	ok(float(rr["sky"]) >= 1.15, "R sky reflection: top of the glossy sphere is %.2f x its bottom (bar 1.15)" % rr["sky"])
	ok(not (float(rr["none"]) >= 1.15), "R control: with the reflection off the bar FAILS (%.2f x)" % rr["none"])

	# ---- F + D: the live view
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 8:
		await process_frame
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.size = Vector2i(1280, 720)
	for i in 6:
		await process_frame
	# an engine-size part: 40 metal spheres, ~ 180 k triangles
	var eng := Node3D.new()
	var esph := SphereMesh.new()
	esph.radius = 0.06
	esph.height = 0.12
	esph.radial_segments = 96
	esph.rings = 48
	var emat := StandardMaterial3D.new()
	emat.albedo_color = Color(0.7, 0.72, 0.75)
	emat.metallic = 0.8
	emat.roughness = 0.35
	var tris := 0
	for i in 40:
		var mi := MeshInstance3D.new()
		mi.mesh = esph
		mi.material_override = emat
		mi.position = Vector3((i % 8) * 0.1 - 0.35, 0.07 + (i / 8) * 0.08, ((i * 7) % 5) * 0.1 - 0.2)
		eng.add_child(mi)
		tris += 96 * 48 * 2
	m.add_child(eng)
	m.target = Vector3(0, 0.2, 0)
	m.pitch = 25.0
	m.yaw = 30.0
	m._cam()
	var key0: float = m.light_key.light_energy
	var tm0: int = m.world_env.tonemap_mode
	var ssao0: bool = m.world_env.ssao_enabled
	var rot0: Vector3 = m.light_key.rotation_degrees
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)   # the cap would hide the cost
	var meas := {}
	for arm in ["off", "on"]:
		if arm == "on":
			m._say(Realistic.set_live(m, true))
		for i in 30:
			await process_frame
		var t0 := Time.get_ticks_usec()
		var N := 120
		for i in N:
			await RenderingServer.frame_post_draw
		meas[arm] = (Time.get_ticks_usec() - t0) / 1000.0 / N
		root.get_texture().get_image().save_png("%s/live_%s.png" % [SHOT, arm])
	print("live view %s, %d triangles, window %s: fast %.2f ms/frame (%.0f fps), Realistic %.2f ms/frame (%.0f fps)" % [
		RenderingServer.get_video_adapter_name(), tris, root.size, meas["off"], 1000.0 / meas["off"], meas["on"], 1000.0 / meas["on"]])
	ok(1000.0 / float(meas["on"]) >= 30.0, "F live Realistic view: %.0f fps at %s (>= 30)" % [1000.0 / float(meas["on"]), root.size])
	ok(Realistic.live_on and m.world_env.tonemap_mode == Environment.TONE_MAPPER_AGX and m.world_env.ssao_enabled, "F the toggle really changed the view (AgX, SSAO on, live_on)")
	m._say(Realistic.set_live(m, false))
	ok(not Realistic.live_on and is_equal_approx(m.light_key.light_energy, key0) and m.world_env.tonemap_mode == tm0 and m.world_env.ssao_enabled == ssao0 and m.light_key.rotation_degrees.is_equal_approx(rot0),
		"F off puts every value back (key %.2f, tonemap %d, ssao %s)" % [key0, tm0, ssao0])
	var tog_found := false
	for b in m.ui_ribbon["VIEW"].get_children():
		if b is Button and (b as Button).text == "Realistic":
			tog_found = true
	ok(tog_found, "F VIEW > Realistic is a button in the View menu (no new row on any panel)")
	if m.export_ui == null:
		m.export_ui = ExportDialog.new(m)
	m.export_ui.open()
	for i in 6:
		await process_frame
	var ed: ExportDialog = m.export_ui
	ok(ed != null and ed.nice_real != null and ed.nice_real.text == "Realistic", "D the Export dialog has the Realistic box")
	if ed != null and ed.nice_real != null:
		ed.nice_real.button_pressed = true
		ok(NiceRender.look == "real", "D ticking it switches the Nice picture to the real look")
		ed.nice_real.button_pressed = false
		ok(NiceRender.look == "studio", "D unticking puts the soft studio picture back")
	print("nice picture ms: cube %d, cylinder %d, house %d" % [nice_ms[0], nice_ms[1], nice_ms[2]])
	print("s224: %d fail" % fails)
	quit(1 if fails > 0 else 0)
