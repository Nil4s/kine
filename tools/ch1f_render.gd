extends SceneTree
## CH1f render: wood, confined masonry and light steel frame side by side (front wall cut away), soil strata under each footing coloured by Vs.
## godot --position -30000,-30000 --audio-driver Dummy --resolution 1280x720 --path . -s tools/ch1f_render.gd -- <out.png>
## Caption on the image: physics model with cited typical values, NOT an NBR code check.
const SYS := preload("res://scripts/build/ch1f_systems.gd")
const SO := preload("res://scripts/build/ch1f_soil.gd")

var out := "C:/Users/Nick/tools/kine_workers/out/ch1f/ch1f_render.png"
var frames := 0
var cam: Camera3D


func vs_color(vs: float) -> Color:
	# 120 m/s red, 270 orange, 560 yellow-green, 1100 blue-grey
	var stops := [[120.0, Color(0.85, 0.15, 0.12)], [270.0, Color(0.95, 0.55, 0.12)], [560.0, Color(0.70, 0.80, 0.25)], [1100.0, Color(0.30, 0.45, 0.80)]]
	if vs <= stops[0][0]:
		return stops[0][1]
	for i in 3:
		if vs <= stops[i + 1][0]:
			var t: float = (vs - stops[i][0]) / (stops[i + 1][0] - stops[i][0])
			return (stops[i][1] as Color).lerp(stops[i + 1][1], t)
	return stops[3][1]


func box(parent: Node3D, a: Vector3, b: Vector3, thick: float, col: Color, alpha := 1.0) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var len := a.distance_to(b)
	if len < 1e-4:
		return
	bm.size = Vector3(thick, thick, len)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	parent.add_child(mi)
	var mid := (a + b) * 0.5
	var up := Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT
	mi.transform = Transform3D(Basis.looking_at((b - a).normalized(), up), mid)


func slab(parent: Node3D, c: Vector3, size: Vector3, col: Color, alpha := 1.0) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.position = c
	parent.add_child(mi)


func label(parent: Node3D, txt: String, p: Vector3, px: float, col := Color(1, 1, 1)) -> void:
	var l := Label3D.new()
	l.text = txt
	l.position = p
	l.pixel_size = px
	l.modulate = col
	l.outline_size = 6
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	parent.add_child(l)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var mj = JSON.parse_string(FileAccess.get_file_as_string("res://out/ch1/members.json"))
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.11, 0.14)
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.9
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 25, 0)
	world.add_child(sun)
	var names := ["wood", "masonry", "lsf"]
	var titles := {"wood": "wood frame (CH10 house)", "masonry": "confined masonry (ceramic block, RC ties)", "lsf": "light steel frame (C90 studs, OSB)"}
	var cols := {"wood": Color(0.85, 0.65, 0.35), "masonry": Color(0.80, 0.40, 0.30), "lsf": Color(0.65, 0.75, 0.85)}
	var gap := 13.0
	for si in 3:
		var n: String = names[si]
		var sys := SYS.build(n, mj)
		var g := Node3D.new()
		g.position = Vector3((si - 1) * gap - 4.877, 0, -3.81)
		world.add_child(g)
		var xyz: PackedFloat64Array = sys["model"]["xyz"]
		var bm: PackedFloat64Array = sys["model"]["beams"]
		var th := 0.09 if n == "wood" else 0.14
		for b in range(0, bm.size(), 12):
			var p1 := Vector3(xyz[int(bm[b]) * 3], xyz[int(bm[b]) * 3 + 1], xyz[int(bm[b]) * 3 + 2])
			var p2 := Vector3(xyz[int(bm[b + 1]) * 3], xyz[int(bm[b + 1]) * 3 + 1], xyz[int(bm[b + 1]) * 3 + 2])
			if p1.z < 0.5 and p2.z < 0.5:
				continue       # cutaway: the front (F) wall line is removed
			box(g, p1, p2, th * (0.6 if n == "wood" else 1.0), cols[n])
		var sp: PackedFloat64Array = sys["model"]["springs"]
		for s in range(0, sp.size(), 3):
			var p1 := Vector3(xyz[int(sp[s]) * 3], xyz[int(sp[s]) * 3 + 1], xyz[int(sp[s]) * 3 + 2])
			var p2 := Vector3(xyz[int(sp[s + 1]) * 3], xyz[int(sp[s + 1]) * 3 + 1], xyz[int(sp[s + 1]) * 3 + 2])
			if p1.z < 0.5 and p2.z < 0.5:
				continue
			if p1.y > 2.0 and p2.y > 2.0:
				continue
			box(g, p1, p2, 0.03, Color(0.15, 0.85, 0.55))
		# roof schematic: back slope only (cut), translucent
		slab(g, Vector3(4.877, 3.2, 5.6), Vector3(9.8, 0.05, 4.4), Color(0.7, 0.7, 0.75), 0.35)
		# foundation slab and soil strata (top 0..-1.5 stiff clay Vs 270, below 1.5..-5 dense Vs 560)
		slab(g, Vector3(4.877, -0.05, 3.81), Vector3(9.754, 0.1, 7.62), Color(0.55, 0.55, 0.55))
		slab(g, Vector3(4.877, -0.85, 3.81), Vector3(13.0, 1.5, 11.0), vs_color(270.0))
		slab(g, Vector3(4.877, -3.35, 3.81), Vector3(13.0, 3.5, 11.0), vs_color(560.0))
		label(g, titles[n], Vector3(4.877, 6.0, 3.81), 0.012)
		var gz := SO.gazetas(SO.soil("stiff_clay"))
		label(g, "Vs 270 m/s over 560 m/s", Vector3(4.877, -0.6, 9.8), 0.009, Color(0, 0, 0))
	label(world, "CH1f: physics model with cited typical values, NOT an NBR code check", Vector3(0, 8.6, -3.8), 0.016, Color(1, 0.9, 0.4))
	label(world, "front wall cut away; green = shear panel springs; soil colour = Vs (red 120, orange 270, yellow-green 560, blue 1100 m/s)", Vector3(0, 7.4, -3.8), 0.0085)
	cam = Camera3D.new()
	cam.position = Vector3(0, 12.0, 34.0)
	cam.look_at_from_position(cam.position, Vector3(0, -0.3, -3.0), Vector3.UP)
	cam.fov = 42.0
	world.add_child(cam)
	cam.current = true
	root.size = Vector2i(1280, 720)


func _process(_d: float) -> bool:
	frames += 1
	if frames == 8:
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(out)
		print("saved ", out, " ", img.get_size())
		quit(0)
	return false
