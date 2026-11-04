extends SceneTree
## CH1a export: blueprint sheets (plan, 4 elevations, 1 section), the 3/4 render and the making-of frames. Window needed (renders).
## godot --position -30000,-30000 --audio-driver Dummy --path . -s tools/ch1_export.gd -- <outdir> [sheets|shots|video]
## Everything goes to <outdir> (default res://out/ch1). Nothing is written into the user's Poser folder.
var outdir := ""
var d := {}
var denom_pick := {}
const XC := 2438.4   # the section cut: through a joist, a rafter and a stud of the front wall


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	outdir = args[0] if args.size() > 0 else ProjectSettings.globalize_path("res://out/ch1")
	var what: String = args[1] if args.size() > 1 else "all"
	DirAccess.make_dir_recursive_absolute(outdir)
	d = JSON.parse_string(FileAccess.get_file_as_string("res://data/challenges/ch1_house.json"))
	root.size = Vector2i(1280, 720)
	if what in ["all", "sheets"]:
		await sheets()
	if what in ["all", "shots"]:
		await shots()
	if what in ["all", "video"]:
		await video()
	quit()


# ------------------------------------------------------------------ blueprint
func yawed(b: Dictionary, tag: String) -> Dictionary:
	var c: Dictionary = b.duplicate(true)
	var r: Dictionary = c["rooms"][0]
	r["x"] = float(r["w"])
	r["z"] = float(r["d"])
	r["yaw"] = 180.0
	c["name"] = String(b["name"]) + " " + tag
	return c


func save_sheet(sh: Dictionary, fname: String) -> void:
	var px := Blueprint.png_size(sh)
	var vp := SubViewport.new()
	vp.size = px
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var v := BlueprintView.new()
	v.sheet = sh
	v.ppm = 300.0 / 25.4
	v.size = Vector2(px)
	vp.add_child(v)
	root.add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	img.save_png("%s/%s.png" % [outdir, fname])
	var f := FileAccess.open("%s/%s.svg" % [outdir, fname], FileAccess.WRITE)
	f.store_string(Blueprint.to_svg(sh))
	f.close()
	print("sheet ", fname, " ", sh["paper"], " 1:", sh["denom"], " ents ", sh["ents"].size())


func section_sheet(b: Dictionary, pick: Dictionary) -> Dictionary:
	var paper: String = pick["paper"]
	var denom := float(pick["denom"])
	var P := func(z: float, y: float) -> Vector2:
		return Vector2(z / denom, -y / denom)
	var ents := []
	ents.append(Blueprint._line(P.call(-1200.0, -102.0), P.call(8820.0, -102.0), "ground"))
	for m in d["members"]:
		var bb: Array = m["box"]
		if float(bb[0]) > XC + 0.5 or float(bb[3]) < XC - 0.5:
			continue
		var k: String = m["kind"]
		if k in ["ground", "window", "door", "idoor", "siding", "wall_sheathing"]:
			continue
		var cls := "roof" if k in ["roof_sheathing", "shingle"] else "wall"
		var pts := []
		if m.has("poly"):
			for p in m["poly"]:
				pts.append(P.call(float(p[0]), float(p[1])))
		else:
			var z0 := float(bb[2])
			var z1 := float(bb[5])
			var y0 := float(bb[1])
			var y1 := float(bb[4])
			pts = [P.call(z0, y0), P.call(z1, y0), P.call(z1, y1), P.call(z0, y1)]
		ents.append(Blueprint._poly(pts, cls, {"member": String(m["name"])}))
	var tx := 2.5
	var notes := [[200.0, 1200.0, "2x4 studs @ 16 in o.c., single bottom plate (PT) + double top plate"], [2000.0, 2600.0, "2x8 ceiling joists @ 16 in o.c. (rafter ties)"],
		[900.0, 3300.0, "2x10 rafters @ 24 in o.c., 4:12"], [3000.0, 4150.0, "2x12 ridge board"], [200.0, -450.0, "4 in slab on grade"], [5200.0, 700.0, "2x4 hall wall (bearing, joist splice)"]]
	for n in notes:
		ents.append(Blueprint._text(P.call(float(n[0]), float(n[1])), String(n[2]), tx, "l", "text"))
	ents.append_array(Blueprint._dim(P.call(0.0, -102.0), P.call(7620.0, -102.0), Vector2(0, 1), 14.0, "%.2f" % 7.62, {"kind": "overall", "axis": "z"}))
	ents.append_array(Blueprint._dim(P.call(0.0, 0.0), P.call(0.0, 2467.0), Vector2(-1, 0), 14.0, "%.3f" % 2.467, {"kind": "wall", "axis": "y"}))
	ents.append_array(Blueprint._dim(P.call(7620.0, 0.0), P.call(7620.0, 3966.0), Vector2(1, 0), 14.0, "%.2f" % 3.97, {"kind": "ridge", "axis": "y"}))
	var area := Blueprint._area(paper)
	var bb2 := Blueprint._bounds(ents)
	ents = Blueprint._shift(ents, area.get_center() - bb2.get_center())
	var bd := b.duplicate(true)
	bd["name"] = String(b["name"]) + " section A-A"
	ents.append_array(Blueprint._frame(bd, "Front", paper, int(denom), 6, 6))
	var sz := Blueprint.paper_size(paper)
	return {"paper": paper, "w": sz.x, "h": sz.y, "denom": int(denom), "k": 1000.0 / denom, "tab": "Section", "title": "Section A-A", "name": bd["name"], "ents": ents, "area": area}


func sheets() -> void:
	var b: Dictionary = d["building"]
	var pick := Blueprint.choose(b)
	print("pick ", pick)
	var bb: Dictionary = b.duplicate(true)
	save_sheet(Blueprint.sheet(bb, "Floor 1", pick), "01_plan")
	save_sheet(Blueprint.sheet(bb, "Front", pick), "02_front_elevation")
	save_sheet(Blueprint.sheet(bb, "Side", pick), "03_right_elevation")
	var by := yawed(b, "(rear)")
	save_sheet(Blueprint.sheet(by, "Front", pick), "04_rear_elevation")
	var bl := yawed(b, "(left)")
	save_sheet(Blueprint.sheet(bl, "Side", pick), "05_left_elevation")
	save_sheet(section_sheet(b, pick), "06_section")


# ------------------------------------------------------------------ 3D
var vp: SubViewport
var cam: Camera3D
var mi: MeshInstance3D
var lab: Label
var lab2: Label


func make_view(size: Vector2i) -> void:
	vp = SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var world := Node3D.new()
	vp.add_child(world)
	mi = MeshInstance3D.new()
	world.add_child(mi)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -40, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	world.add_child(sun)
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.36, 0.55, 0.85)
	psm.sky_horizon_color = Color(0.72, 0.82, 0.92)
	psm.ground_horizon_color = Color(0.72, 0.82, 0.92)
	psm.ground_bottom_color = Color(0.30, 0.42, 0.26)
	sky.sky_material = psm
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.near = 0.1
	cam.far = 400.0
	world.add_child(cam)
	cam.current = true
	var cl := CanvasLayer.new()
	vp.add_child(cl)
	lab = Label.new()
	lab.position = Vector2(24, 18)
	lab.add_theme_font_size_override("font_size", 34)
	lab.add_theme_color_override("font_color", Color.WHITE)
	lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lab.add_theme_constant_override("outline_size", 8)
	cl.add_child(lab)
	lab2 = Label.new()
	lab2.position = Vector2(24, size.y - 52)
	lab2.add_theme_font_size_override("font_size", 22)
	lab2.add_theme_color_override("font_color", Color.WHITE)
	lab2.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lab2.add_theme_constant_override("outline_size", 6)
	cl.add_child(lab2)
	root.add_child(vp)


func show_prefix(n: int) -> void:
	var rec: Dictionary = (d["part"] as Dictionary).duplicate(true)
	rec["features"] = (rec["features"] as Array).slice(0, n)
	var res := Part.replay(rec)
	var mesh: ArrayMesh = res["mesh"]
	if mesh == null:
		return
	Part.paint(mesh, res["looks"])
	mi.mesh = mesh


func aim(az_deg: float, el_deg: float, dist: float) -> void:
	var tgt := Vector3(4.877, 1.4, 3.81)
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	var off := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el)) * dist   # az 0 = from the street (-Z side)
	cam.look_at_from_position(tgt + off, tgt, Vector3.UP)


func grab(path: String, jpg := false) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if jpg:
		img.save_jpg(path, 0.9)
	else:
		img.save_png(path)


func shots() -> void:
	make_view(Vector2i(1600, 900))
	var n := (d["part"]["features"] as Array).size()
	show_prefix(n)
	lab.text = "Levitt Ranch 1949, one storey, 32 x 25 ft"
	lab2.text = ""
	aim(-35.0, 24.0, 21.0)
	await grab(outdir + "/front_3q.png")
	aim(145.0, 24.0, 21.0)
	await grab(outdir + "/rear_3q.png")
	# the framing alone: stop before the wall sheathing
	var stages: Array = d["stages"]
	var fr := 0
	for s in stages:
		if s["name"] == "Rafters and ridge":
			fr = int(s["upto"])
	show_prefix(fr)
	lab.text = "Framing only"
	aim(-35.0, 28.0, 17.0)
	await grab(outdir + "/framing_3q.png")
	print("shots done")


func video() -> void:
	make_view(Vector2i(1280, 720))
	var feats: Array = d["part"]["features"]
	var stages: Array = d["stages"]
	var steps := {"Slab": 2, "Sill plates": 3, "Wall framing": 22, "Top plates": 4, "Ceiling joists": 3, "Gable studs": 4, "Rafters and ridge": 6, "Wall sheathing": 6,
		"Roof sheathing": 4, "Shingles": 3, "Siding": 4, "Windows and doors": 5}
	var shown := {"prim": 1, "extrude": 1, "pattern": 1}
	var plan := []   # [upto, stage name]
	var prev := 0
	for s in stages:
		var up: int = int(s["upto"])
		var cuts := []
		for i in range(prev, up):
			if shown.has(String(feats[i]["t"])):
				cuts.append(i + 1)
		var m: int = int(steps.get(s["name"], 3))
		for j in m:
			var idx := mini(cuts.size() - 1, int(round(float(j + 1) / float(m) * cuts.size())) - 1)
			plan.append([cuts[maxi(idx, 0)], s["name"]])
		prev = up
	plan.append([feats.size(), "Windows and doors"])
	var fps := 24
	var hold := 13
	var frame := 0
	var total := plan.size() * hold
	DirAccess.make_dir_recursive_absolute(outdir + "/frames")
	for si in plan.size():
		show_prefix(int(plan[si][0]))
		lab.text = "%s" % plan[si][1]
		lab2.text = "Levitt Ranch 1949 on Kine   step %d / %d" % [si + 1, plan.size()]
		for h in hold:
			var u := float(frame) / float(total)
			aim(-40.0 + 230.0 * u, 26.0 - 4.0 * u, 20.0 - 2.0 * u)
			await grab("%s/frames/f_%04d.jpg" % [outdir, frame], true)
			frame += 1
	# a last hold on the front
	for h in 36:
		aim(-35.0, 22.0, 18.0)
		await grab("%s/frames/f_%04d.jpg" % [outdir, frame], true)
		frame += 1
	print("frames ", frame)
