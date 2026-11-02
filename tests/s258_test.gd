extends SceneTree
## S258 A LOOK THAT GLOWS (scripts/build/part_glow.gd): an appear step's "emission" [r, g, b] + "emission_energy" become the look's glow, are saved with
## the part and are drawn by the renderer as emission.
## Fixture: three 200 mm boxes in a row with the SAME blue look: "Glow" (emission blue, energy 2), "Plain" (no emission), "Zero" (emission fields, energy 0).
##   1 RECORD   look_of: Glow has glow + glow_k 2; Plain and Zero have none
##   2 SAVED    the record through JSON text and Part.from_file: the replayed looks are the same (glow kept)
##   3 BAR      a dark scene (black background, no light, no ambient), the part drawn by Part.paint: the Glow box's centre pixel is brighter than
##              the Plain box's (the same look unlit) by >= 0.25 and is >= 0.30; Plain <= 0.05
##   4 CONTROL  the Zero box (emission colour given, strength 0) reads like Plain (within 0.02): the bar can fail
##   5 VIEW     the app's Part view (_look_surfaces): the Glow body's surface material has emission on, Plain's has it off
##   6 STEP     PartGlow.add_step on Plain keeps its colour and adds the glow (replay: Plain glows, its colour unchanged)
var fails := 0
var m: Node
const DIRT := "user://s258_test"
const BLUE := [0.15, 0.35, 0.9]


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


func fixture() -> Dictionary:
	var rec := Part.make("Glow test")
	var names := ["Glow", "Plain", "Zero"]
	for k in 3:
		Part.prim(rec, "box", {"x": -400.0 + 300.0 * k, "y": -100.0, "z": -100.0, "w": 200.0, "h": 200.0, "d": 200.0, "name": names[k]})
		(rec["features"] as Array).append(Part.new_feature(rec, "bname", {"body": k, "called": names[k]}))
		var f := {"body": k, "preset": "Custom", "color": BLUE.duplicate(), "rough": 0.6, "metal": 0.0, "alpha": 1.0}
		if k == 0:
			f.merge(PartGlow.fields(Color(BLUE[0], BLUE[1], BLUE[2]), 2.0))
		elif k == 2:
			f["emission"] = BLUE.duplicate()
			f["emission_energy"] = 0.0
		(rec["features"] as Array).append(Part.new_feature(rec, "appear", f))
	return rec


func lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## the part drawn by Part.paint (the renderer every picture uses) in a dark world: black background, no lights, no ambient. The centre pixel of each box
func dark_pixels(rec: Dictionary) -> Array:
	var res := Part.replay(rec)
	var mesh: ArrayMesh = res["mesh"]
	Part.paint(mesh, res["looks"])
	var vp := SubViewport.new()
	vp.size = Vector2i(640, 360)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0, 0, 0)
	env.ambient_light_energy = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	vp.add_child(mi)
	var cam := Camera3D.new()
	cam.fov = 40.0
	vp.add_child(cam)
	root.add_child(vp)
	cam.look_at_from_position(Vector3(0, 0, 2.0), Vector3.ZERO, Vector3.UP)
	cam.current = true
	for i in 6:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var out: Array = []
	for k in 3:
		var p := cam.unproject_position(Vector3((-300.0 + 300.0 * k) * 0.001, 0.0, 0.1))
		out.append(lum(img.get_pixelv(Vector2i(p))))
	img.save_png(ProjectSettings.globalize_path(DIRT + "/dark.png"))
	vp.queue_free()
	return out


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	var rec := fixture()
	var res := Part.replay(rec)
	var bl: Array = res["body_looks"]
	ok(int(res["bodies"]) == 3 and (res["errors"] as Dictionary).is_empty(), "0 fixture: %d bodies, errors %s" % [res["bodies"], str(res["errors"])])
	ok(PartGlow.has(bl[0]) and is_equal_approx(float(bl[0]["glow_k"]), 2.0) and (bl[0]["glow"] as Color).is_equal_approx(Color(BLUE[0], BLUE[1], BLUE[2])), "1 Glow's look has glow %s k %s" % [str(bl[0].get("glow")), str(bl[0].get("glow_k"))])
	ok(not PartGlow.has(bl[1]) and not PartGlow.has(bl[2]), "1 Plain and Zero have no glow")
	var back := Part.from_file(JSON.parse_string(JSON.stringify(rec)))
	var res2 := Part.replay(back)
	ok(JSON.stringify(res2["body_looks"]) == JSON.stringify(bl) and PartGlow.has(res2["body_looks"][0]), "2 saved through JSON text and from_file: the looks are the same, the glow kept")
	var px: Array = await dark_pixels(rec)
	print("dark-scene centre luminance: Glow %.3f Plain %.3f Zero %.3f" % [px[0], px[1], px[2]])
	ok(px[1] <= 0.05, "3 the scene is dark: Plain (unlit) %.3f <= 0.05" % px[1])
	ok(px[0] >= 0.30 and px[0] - px[1] >= 0.25, "3 BAR the glowing look is brighter than the same look unlit: %.3f vs %.3f (>= 0.30, by >= 0.25)" % [px[0], px[1]])
	ok(absf(px[2] - px[1]) <= 0.02 and not (px[2] >= 0.30 and px[2] - px[1] >= 0.25), "4 CONTROL strength 0 reads like unlit: %.3f vs %.3f, and fails the bar" % [px[2], px[1]])
	# 5 the app's Part view
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	await idle(4)
	var ss: StartScreen = m.start_screen
	ss.dirs_override = [DIRT]
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	var cb: Control = ss._easy_btn["building"]
	var pt := cb.get_global_rect().get_center()
	await ev_mouse(pt, true)
	await ev_mouse(pt, false)
	await idle(3)
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(20)
	var pu: PartUI = m.bld.part
	if not pu.on:
		pu.set_on(true)
		await idle(4)
	m.S.part = rec.duplicate(true)
	pu.upto = -1
	pu.sync()
	var tw := Time.get_ticks_msec()
	while int(pu.res.get("bodies", -1)) != 3 and Time.get_ticks_msec() - tw < 30000:
		await idle(2)
	await idle(4)
	var sb: Array = pu.res.get("surf_body", [])
	var mg: Material = null
	var mp: Material = null
	for s in sb.size():
		if int(sb[s]) == 0:
			mg = pu.part_mesh.get_surface_override_material(s)
		elif int(sb[s]) == 1:
			mp = pu.part_mesh.get_surface_override_material(s)
	ok(mg is BaseMaterial3D and (mg as BaseMaterial3D).emission_enabled and is_equal_approx((mg as BaseMaterial3D).emission_energy_multiplier, 2.0), "5 Part view: Glow's surface draws emission (energy %s)" % (str((mg as BaseMaterial3D).emission_energy_multiplier) if mg is BaseMaterial3D else "none"))
	ok(mp is BaseMaterial3D and not (mp as BaseMaterial3D).emission_enabled, "5 Part view: Plain's surface has no emission")
	# 6 the helper step
	var r3 := rec.duplicate(true)
	var sid := PartGlow.add_step(r3, 1, Color(1.0, 0.2, 0.1), 3.0)
	var res3 := Part.replay(r3)
	var l1: Dictionary = res3["body_looks"][1]
	ok(sid != "" and PartGlow.has(l1) and is_equal_approx(float(l1["glow_k"]), 3.0) and (l1["c"] as Color).is_equal_approx(Color(BLUE[0], BLUE[1], BLUE[2])) and String(res3["body_names"][1]) == "Plain", "6 add_step: Plain glows k %s, its colour %s and name '%s' kept" % [str(l1.get("glow_k")), str(l1["c"]), res3["body_names"][1]])
	ok(PartGlow.add_step(r3, 9, Color.WHITE, 1.0) == "", "6 add_step on a body that is not there makes no step")
	print("s258: %d fail" % fails)
	quit(1 if fails > 0 else 0)
