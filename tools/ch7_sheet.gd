## godot --position -30000,-30000 --path . -s tools/ch7_sheet.gd -- <out.png>   (CH7b: a contact sheet of the parkour run)
## Side view from -x (he runs left to right), an orthographic camera that follows the pelvis; every 7th frame, 7 columns x 5 rows.
## The body is drawn as its own collision capsules (Body.cap / Body.rad), the course as its boxes, the planned contact points as
## red dots, so what the sheet shows is exactly what the penetration and contact bars read.
extends SceneTree

const COLS := 7
const ROWS := 5
const STEP := 7
const W := 300
const H := 230


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var out := "C:/Temp/claude/ch7b/sheet.png"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var P := ParkourPlan.build()
	var R := Parkour.build(P)
	var S := Scene.new()
	S.from_dict(R["scene"])
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.93, 0.93, 0.95)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -60, 0)
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 3.4
	vp.add_child(cam)
	var mbox := StandardMaterial3D.new()
	mbox.albedo_color = Color(0.55, 0.45, 0.35)
	for o in P["obstacles"]:
		var lo: Vector3 = o["lo"]
		var hi: Vector3 = o["hi"]
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = hi - lo
		mi.mesh = bm
		mi.material_override = mbox
		mi.position = (lo + hi) * 0.5
		vp.add_child(mi)
	var mbody := StandardMaterial3D.new()
	mbody.albedo_color = Color(0.25, 0.4, 0.75)
	var caps := {}
	for part in Body.BODY:
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radial_segments = 12
		cm.rings = 3
		mi.mesh = cm
		mi.material_override = mbody
		vp.add_child(mi)
		caps[part] = mi
	var mdot := StandardMaterial3D.new()
	mdot.albedo_color = Color(0.9, 0.1, 0.1)
	mdot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var dots := []
	for i in 6:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.035
		sm.height = 0.07
		mi.mesh = sm
		mi.material_override = mdot
		mi.position.x = -5.0
		vp.add_child(mi)
		dots.append(mi)
	var sheet := Image.create(W * COLS, H * ROWS, false, Image.FORMAT_RGB8)
	var nfr := int(round(float(P["length"]) * 30.0)) + 1
	for i in COLS * ROWS:
		var k := mini(i * STEP, nfr - 1)
		var t := k / 30.0
		S.apply(B, t)
		for part in Body.BODY:
			var c: Array = B.cap(part)
			var a: Vector3 = c[0]
			var b: Vector3 = c[1]
			var r: float = B.rad[part]
			var mi: MeshInstance3D = caps[part]
			var cm: CapsuleMesh = mi.mesh
			cm.radius = r
			cm.height = a.distance_to(b) + 2.0 * r
			var yax := (b - a).normalized() if a.distance_to(b) > 1e-5 else Vector3.UP
			var xax := yax.cross(Vector3.FORWARD if absf(yax.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
			mi.transform = Transform3D(Basis(xax, yax, xax.cross(yax)), (a + b) * 0.5)
		# the contacts in force at t (every limb track: a key pair with "c" at one point)
		var di := 0
		for g in ["feet", "hands"]:
			for tip in P[g]:
				var st := Parkour.limb_at(P[g][tip], t)
				if bool(st["on"]) and di < dots.size():
					(dots[di] as MeshInstance3D).position = (st["v"] as Vector3) + Vector3(-0.3, 0, 0)
					di += 1
		for j in range(di, dots.size()):
			(dots[j] as MeshInstance3D).position = Vector3(-5, -50, 0)
		var pel: Vector3 = B.P["pelvis"]
		cam.position = Vector3(-6.0, Parkour.Y0 + 1.0, pel.z)
		cam.look_at(Vector3(0.0, Parkour.Y0 + 1.0, pel.z), Vector3.UP)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(img, Rect2i(0, 0, W, H), Vector2i((i % COLS) * W, (i / COLS) * H))
		# a dark corner tick per tile: a bar whose length is the frame index / 8 px (frames 0, 7, 14 ... read left to right)
		sheet.fill_rect(Rect2i((i % COLS) * W, (i / COLS) * H, 2 + k / 2, 4), Color(0.1, 0.1, 0.1))
	sheet.save_png(out)
	print("sheet ", out)
	quit(0)
