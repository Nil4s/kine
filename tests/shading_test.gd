## godot --path . -s tests/shading_test.gd     (GATES XX10; needs a window: the frames are read back from the screen)
## SHADING: solid is today's look (a frame after cycling through every mode and back is pixel-identical to the first,
## and the body's materials are the very objects they were); silhouette is exactly two colours with the 2D chrome
## hidden (what it hides is the camera's cull mask: floor, grid, axes, joint dots, capsules, tag, dummy, overlays);
## matcap and x-ray differ from solid; the mode is a view setting (the scene's dictionary is unchanged).
## FPS TRUTH: Shading.fps_stats on a list of deltas (60 frames of 1/60 s and one of 100 ms: 1 dropped, the right fps),
## the live Meter agrees, and a real playback in this window reports a number above 0.
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


## pixels that differ (compared four bytes at a time, on the image's raw data)
func ndiff(a: Image, b: Image) -> int:
	if a.get_size() != b.get_size():
		return -1
	var da := a.get_data()
	var db := b.get_data()
	if da == db:
		return 0
	var n := 0
	var px := da.size() / 4 if a.get_format() == Image.FORMAT_RGBA8 else da.size() / 3
	var k := 4 if a.get_format() == Image.FORMAT_RGBA8 else 3
	for i in px:
		var o := i * k
		if da[o] != db[o] or da[o + 1] != db[o + 1] or da[o + 2] != db[o + 2]:
			n += 1
	return n


## distinct colours in the frame, from the raw bytes
func colours(img: Image) -> int:
	var d := img.get_data()
	var k := 4 if img.get_format() == Image.FORMAT_RGBA8 else 3
	var seen := {}
	for i in d.size() / k:
		var o := i * k
		seen[(d[o] << 16) | (d[o + 1] << 8) | d[o + 2]] = true
	return seen.size()


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false

	# ---- the pure fps rule
	var dl := []
	for i in 60:
		dl.append(1.0 / 60.0)
	var clean_st := Shading.fps_stats(dl, 1.0 / 60.0)
	ok(clean_st[1] == 0 and absf(clean_st[0] - 60.0) < 0.01, "60 frames of 1/60 s: %.3f fps, %d dropped (bar: 60.000, 0)" % [clean_st[0], clean_st[1]])
	dl[30] = 0.1
	var st := Shading.fps_stats(dl, 1.0 / 60.0)
	var want_fps := 60.0 / (59.0 / 60.0 + 0.1)
	ok(st[1] == 1 and absf(st[0] - want_fps) < 0.001, "one forced 100 ms frame: %.3f fps, %d dropped (bar: %.3f, exactly 1)" % [st[0], st[1], want_fps])
	var edge := Shading.fps_stats([0.0249, 0.0251], 1.0 / 60.0 * 1.5 / 1.5 * 1.0 + 0.0)   # 1.5 x (1/60) = 0.025
	ok(edge[1] == 1, "the 1.5 x target line: 24.9 ms is kept, 25.1 ms is dropped: %d dropped (bar: 1)" % edge[1])
	var mt := Shading.Meter.new()
	mt.start(1.0 / 60.0)
	mt.feed(0.5)   # the first delta after start is the idle time before: not counted
	for d in dl:
		mt.feed(d)
	var ms := mt.stats()
	ok(ms[2] == 60 and ms[1] == 1 and absf(ms[0] - want_fps) < 0.001, "the live Meter on the same list: %d frames, %d dropped, %.3f fps (bar: 60, 1, %.3f)" % [ms[2], ms[1], ms[0], want_fps])
	ok(Shading.fps_text(st) == "playing %.1f fps, 1 dropped" % want_fps, "the words: '%s'" % Shading.fps_text(st))

	# ---- the figure, UI hidden as the playblast does
	for p in m.ui_side:
		p.visible = false
	m.ui_root.visible = false
	m.clean = true
	m.big_view = true
	m.dist = 4.6
	m.target = Vector3(0, 1.05, 0.2)
	m._cam()
	var dummy_was: bool = m.dummy_on
	if m.dummy_on:
		m._dummy_toggle()   # the solid dummy stands in front of the hero by default: take it away for the look checks
	m._refresh()
	var orig := {}
	for mi in Shading.bodies(m):
		orig[mi] = mi.material_override
	var dict0 := JSON.stringify(m.S.to_dict(m.B))
	var base := await shot()
	var nc0 := colours(base)
	ok(m.shading.mode == "solid", "the default mode is solid")

	# ---- matcap
	m._shading_next()
	var mc := await shot()
	var dm := ndiff(base, mc)
	var ncm := colours(mc)
	ok(m.shading.mode == "matcap" and dm > 2000, "matcap: %d pixels differ from solid (bar: > 2000), %d colours" % [dm, ncm])
	ok(m.pieces["head"].material_override is ShaderMaterial, "matcap is a ShaderMaterial on the body parts")

	# ---- silhouette
	m._shading_next()
	var si := await shot()
	var nsil := colours(si)
	ok(m.shading.mode == "silhouette", "the next mode is silhouette")
	print("silhouette distinct colours: ", nsil, " format ", si.get_format(), " size ", si.get_size())
	ok(nsil == 2, "silhouette frame: exactly %d distinct colours (bar: 2)" % nsil)
	var body_px := 0
	var ink := Tok.c("ink").to_rgba32()
	var bg0 := si.get_pixel(2, 2).to_rgba32()
	var sd := si.get_data()
	var sk := 4 if si.get_format() == Image.FORMAT_RGBA8 else 3
	var bgr := sd[0]
	var bgg := sd[1]
	var bgb := sd[2]
	for i in sd.size() / sk:
		var o := i * sk
		if sd[o] != bgr or sd[o + 1] != bgg or sd[o + 2] != bgb:
			body_px += 1
	ok(body_px > 3000 and bg0 != ink, "the body fills %d pixels (bar: > 3000) on a background that is not the body colour" % body_px)
	ok(m.get_viewport().msaa_3d == Viewport.MSAA_DISABLED, "MSAA is off while silhouette is on")

	# ---- x-ray
	m._shading_next()
	var xr := await shot()
	var dx := ndiff(base, xr)
	ok(m.shading.mode == "xray" and dx > 2000, "x-ray: %d pixels differ from solid (bar: > 2000)" % dx)
	var bgc: Color = Tok.c("world")
	var dist_solid := 0.0
	var dist_xray := 0.0
	var nb := 0
	for y in range(0, base.get_height(), 3):
		for x in range(0, base.get_width(), 3):
			var cs := base.get_pixel(x, y)
			if cs != bgc and ndiff_px(cs, xr.get_pixel(x, y)) > 0.01:
				dist_solid += ndiff_px(cs, bgc)
				dist_xray += ndiff_px(xr.get_pixel(x, y), bgc)
				nb += 1
	ok(nb > 200 and dist_xray < dist_solid, "x-ray body pixels sit closer to the background than solid ones: %.2f < %.2f over %d samples" % [dist_xray, dist_solid, nb])
	ok(m.pieces["head"].material_override is StandardMaterial3D and (m.pieces["head"].material_override as StandardMaterial3D).albedo_color.a < 0.5, "x-ray material is see-through")

	# ---- back to solid: pixel identical, same material objects, nothing saved
	m._shading_next()
	var back := await shot()
	var dback := ndiff(base, back)
	ok(m.shading.mode == "solid" and dback == 0, "solid after the cycle: %d pixels differ from the first solid frame (bar: 0)" % dback)
	var same := true
	for mi in orig:
		if mi.material_override != orig[mi]:
			same = false
	ok(same and nc0 > 20, "every body part has the very material it had (%d solid colours seen)" % nc0)
	ok(m.get_viewport().msaa_3d != Viewport.MSAA_DISABLED or ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d") == 0, "MSAA put back")
	ok(m.cam.cull_mask == 1048575, "camera cull mask put back: %d (bar: 1048575)" % m.cam.cull_mask)
	var dict1 := JSON.stringify(m.S.to_dict(m.B))
	ok(dict0 == dict1, "the scene's saved form is unchanged by shading")

	# ---- silhouette with the dummy standing there: still two colours (the dummy is not on the body's layer)
	if dummy_was:
		m._dummy_toggle()
	m.shading.set_mode(m, "silhouette")
	var sd2 := await shot()
	var n2 := colours(sd2)
	ok(n2 == 2, "silhouette with the dummy on: %d distinct colours (bar: 2)" % n2)
	m.shading.set_mode(m, "solid")
	var back2 := await shot()
	ok(m.shading.mode == "solid" and m.cam.cull_mask == 1048575, "solid again, cull mask %d" % m.cam.cull_mask)

	# ---- a real playback reports a number
	m.ui_root.visible = true
	for p in m.ui_side:
		p.visible = true
	m.clean = false
	var S := Scene.new()
	S.name = "zz_shading"
	var R := Body.new()
	R.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	R.fk()
	S.add("a", R.to_dict())
	R.set_ang("thigh_l", Vector3(60, 0, 0))
	R.fk()
	S.add("b", R.to_dict())
	S.cards[0]["move"] = 1.0
	S.cards[0]["hold"] = 0.5
	S.cards[1]["move"] = 1.0
	S.cards[1]["hold"] = 0.5
	m.S = S
	m._rebuild_cards()
	m._refresh()
	await idle(2)
	m.playhead = 0.0
	m.playing = true
	await idle(40)
	var ps: Array = m.shading.meter.stats()
	var txt: String = m.ui_fps_lbl.text
	m.playing = false
	await idle(2)
	ok(ps[2] > 10 and ps[0] > 0.0, "real playback: %d frames, %.1f fps, %d dropped (bar: frames > 10, fps > 0)" % [ps[2], ps[0], ps[1]])
	ok(txt.begins_with("playing ") and txt.ends_with(" dropped"), "the readout beside the time says: '%s'" % txt)

	print("SHADING TEST ", "PASS" if fails == 0 else "FAIL %d" % fails)
	TestFiles.cleanup()
	quit(fails)


func ndiff_px(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
