extends SceneTree
## S218 SECTION COLOUR (Friday plan 218): the cut faces get a section look, a cap colour of their own per body (SectionLook), so a cut-away of
## two bodies no longer merges them. Real clicks (Section tool), 1280 x 720, Expert Part. Every number is measured from the screenshot / image.
##   1 CAPS     Section on across two side-by-side bodies: pixels of each body's cap colour >= 500 each; the two caps differ by >= 0.30 (RGB distance)
##   2 SIDES    in a 3/4 view each body's side faces (its own colour, shaded 0.7..1.0) show >= 200 px, and each cap differs from them by >= 0.20
##   3 OFF      Section off: cap-coloured pixels < 30; no material override; surface looks are the plain StandardMaterial3D again; record unchanged
##   4 SPLIT    a cube split at x = 50 (lower half kept): its cut face shows the cap colour (>= 500 px) with no section on; differs from the body colour
##   5 NICE     Nice picture of the cut (NiceRender.draw with the cut): two distinct cap hues >= 500 px each; the uncut picture has < 50 of each
const SHOT := "C:/Temp/claude/s218"
const DIRT := "user://s218_test"
var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	if c == null:
		fails += 1
		print("FAIL a control to click is missing")
		return
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func pick_tool(pu, nm: String) -> void:
	var b: Button = pu.tool_btns[nm]
	if b.visible:
		await click_ctl(b)
		return
	await click_ctl(m.ui_more)
	await idle(2)
	m._more_pick(m._more_tools.find(b))
	await idle(2)


func shot(nm: String) -> Image:
	await idle(4)
	DirAccess.make_dir_recursive_absolute(SHOT)
	var img: Image = root.get_texture().get_image()
	img.save_png("%s/%s.png" % [SHOT, nm])
	return img


func two_bodies() -> Dictionary:
	var rec := Part.make("TwoBodies")
	rec["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [0, 0], "b": [40, 100]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 100.0, "both": false, "op": "new"},
		{"t": "sketch", "id": "f3", "name": "Sketch2", "plane": "front", "ents": [{"k": "rect", "a": [60, 0], "b": [100, 100]}], "dims": []},
		{"t": "extrude", "id": "f4", "name": "Extrude2", "sketch": "f3", "dist": 100.0, "both": false, "op": "new"},
	]
	return rec


func cube_split() -> Dictionary:
	var rec := Part.make("CutCube")
	rec["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [0, 0], "b": [100, 100]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 100.0, "both": false, "op": "new"},
		{"t": "split", "id": "f3", "name": "Split1", "plane": "right", "at": 50.0, "keep": -1},
	]
	return rec


func near(c: Color, t: Color, tol: float) -> bool:
	return absf(c.r - t.r) < tol and absf(c.g - t.g) < tol and absf(c.b - t.b) < tol


func cdist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func count(img: Image, r: Rect2i, t: Color, tol: float) -> int:
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if near(img.get_pixel(x, y), t, tol):
				n += 1
	return n


func hue_count(img: Image, h: float, step := 2) -> int:
	var n := 0
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var c := img.get_pixel(x, y)
			if c.s > 0.45 and c.v > 0.25 and absf(fposmod(c.h - h + 0.5, 1.0) - 0.5) < 0.025:
				n += 1
	return n * step * step


func cl_rect() -> Rect2i:
	var cl: Rect2 = m.nav_clear_rect()
	return Rect2i(Vector2i(cl.position), Vector2i(cl.size))


## the shader's cap and solid colour of each surface, or the standard material's albedo (cap null)
func surf_cols(pu) -> Array:
	var out := []
	for s in pu.part_mesh.mesh.get_surface_count():
		var mt = pu.part_mesh.get_surface_override_material(s)
		if mt is ShaderMaterial:
			out.append([mt.get_shader_parameter("cap"), mt.get_shader_parameter("solid")])
		elif mt is StandardMaterial3D:
			out.append([null, mt.albedo_color])
		else:
			out.append([null, null])
	return out


func _init() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP: no window")
		print("s218: 0 fail")
		quit(0)
		return
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	var pu: PartUI = m.bld.part
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	m.S.part = two_bodies()
	if not pu.on:
		await click_ctl(pu.part_btn)
		await idle(3)
	pu._rebuild(true)
	await idle(4)
	var rec0 := JSON.stringify(m.S.part)
	ok(int(pu.res.get("bodies", 0)) == 2, "0 two bodies built: %d" % int(pu.res.get("bodies", 0)))

	# 1 CAPS
	pu._view_plane("front")
	await idle(4)
	await pick_tool(pu, "Section")
	await idle(3)
	pu.sec_slider.value = 50.0
	await idle(8)
	var img1 := await shot("section_on")
	var sc := surf_cols(pu)
	var capa: Color = sc[0][0] if sc[0][0] != null else Color(0, 0, 0)
	var capb: Color = sc[1][0] if sc[1][0] != null else Color(0, 0, 0)
	var na := count(img1, cl_rect(), capa, 0.03)
	var nb := count(img1, cl_rect(), capb, 0.03)
	ok(sc[0][0] != null and sc[1][0] != null and na >= 500 and nb >= 500 and cdist(capa, capb) >= 0.30,
		"1 CAPS: body 1 cap %s %d px, body 2 cap %s %d px, caps differ by %.2f (want >= 500 px each, >= 0.30)" % [capa.to_html(false), na, capb.to_html(false), nb, cdist(capa, capb)])

	# 2 SIDES: a 3/4 view, section still on
	m._turn_to(35.0, 30.0, 0.5, Vector3(0.05, 0.05, 0.05), false)
	await idle(30)
	var img2 := await shot("section_sides")
	var sa: Color = sc[0][1]
	var sb: Color = sc[1][1]
	var ok2 := true
	var rep := ""
	for pr in [[sa, capa], [sb, capb]]:
		var side: Color = pr[0]
		var cap: Color = pr[1]
		var n := 0
		for f in [0.7, 0.85, 1.0]:
			n += count(img2, cl_rect(), Color(side.r * f, side.g * f, side.b * f), 0.02)
		var d := minf(cdist(cap, side), cdist(cap, side * 0.7))
		rep += " [side %s %d px, cap-to-side %.2f]" % [side.to_html(false), n, d]
		ok2 = ok2 and n >= 200 and d >= 0.20
	ok(ok2, "2 SIDES: each body's side faces show and differ from its cap:" + rep)

	# 3 OFF
	pu._view_plane("front")
	await idle(3)
	pu._sec_set(false)
	await idle(8)
	var img3 := await shot("section_off")
	var offs := surf_cols(pu)
	var plain: bool = pu.part_mesh.material_override == null and offs[0][0] == null and offs[1][0] == null and offs[0][1] != null
	var rest := count(img3, cl_rect(), capa, 0.03) + count(img3, cl_rect(), capb, 0.03)
	ok(plain and rest < 30 and JSON.stringify(m.S.part) == rec0, "3 OFF: override %s, plain looks %s, cap-coloured px left %d, record unchanged %s" % [pu.part_mesh.material_override, plain, rest, JSON.stringify(m.S.part) == rec0])

	# 4 SPLIT
	m.S.part = cube_split()
	pu._rebuild(true)
	await idle(4)
	pu._view_plane("right")
	await idle(30)
	var img4 := await shot("split_cap")
	var s4 := surf_cols(pu)
	var cap4: Color = s4[0][0] if s4[0][0] != null else Color(0, 0, 0)
	var side4: Color = s4[0][1] if s4[0][1] != null else Color(0, 0, 0)
	var n4 := hue_count(img4.get_region(cl_rect()), cap4.h, 1)
	ok(s4[0][0] != null and n4 >= 500 and cdist(cap4, side4) >= 0.20 and not pu.sec_on,
		"4 SPLIT: the split cut face shows the cap colour %s, %d px, differs from the body colour %s by %.2f, no section on" % [cap4.to_html(false), n4, side4.to_html(false), cdist(cap4, side4)])

	# 5 NICE
	m.S.part = two_bodies()
	pu._rebuild(true)
	await idle(4)
	var capsn: Array = SectionLook.cap_colors(pu.res.get("looks", []), 2)
	var pl: Dictionary = Part.plane("front")
	var nz: Vector3 = pl["n"]
	var cutd := {"n": nz, "w": nz.dot((pl["o"] as Vector3) + nz * 0.05)}
	var nice_cut: Image = await NiceRender.draw(m, m.S.part, NiceRender.SIZE, cutd)
	var nice_unc: Image = await NiceRender.draw(m, m.S.part)
	DirAccess.make_dir_recursive_absolute(SHOT)
	nice_cut.save_png(SHOT + "/nice_cut.png")
	nice_unc.save_png(SHOT + "/nice_uncut.png")
	var h0: float = (capsn[0] as Color).h
	var h1: float = (capsn[1] as Color).h
	var c0 := hue_count(nice_cut, h0)
	var c1 := hue_count(nice_cut, h1)
	var u0 := hue_count(nice_unc, h0)
	var u1 := hue_count(nice_unc, h1)
	ok(c0 >= 500 and c1 >= 500 and u0 < 50 and u1 < 50 and absf(h0 - h1) > 0.1,
		"5 NICE: cut picture cap hues %.2f / %.2f show %d / %d px; the uncut picture %d / %d px" % [h0, h1, c0, c1, u0, u1])

	print("s218: %d fail" % fails)
	quit(1 if fails > 0 else 0)
