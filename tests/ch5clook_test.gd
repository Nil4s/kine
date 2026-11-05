extends SceneTree
## CH5c quick look (not a bar suite): build the PBR street, render wet + dry from pose x = 0, save PNGs, print the asphalt mean luminance.
const OUT := "C:/Users/Nick/tools/kine_workers/out/ch5c/"
var ws: WetStreet


func _init() -> void:
	_run.call_deferred()


func asphalt_mean(cam: Camera3D, img: Image) -> float:
	var s := 0.0
	var n := 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var o := cam.project_ray_origin(Vector2(x, y))
			var d := cam.project_ray_normal(Vector2(x, y))
			if d.y >= -0.001:
				continue
			var g := o + d * (-o.y / d.y)
			if g.x < 1.2 or g.x > 2.6 or g.z < -7.0 or g.z > -1.0 or ws.bowl_field(g.x, g.z) < -0.01:
				continue
			var c := img.get_pixel(x, y)
			s += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return s / maxf(float(n), 1.0)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var poses := [Vector3(-1.2, WetStreet.EYE, 1.5), Vector3(0.0, WetStreet.EYE, 1.5), Vector3(0.7, WetStreet.EYE, 1.5)]   ## AMENDED per Nick 11-04: pose 2 was x = 1.2, over the plinth of the photo's 2.3 m lane (x -1.30..1.02); x 0.7 puts its puddle (x 0.49) on the stones
	ws = WetStreet.new()
	root.add_child(ws)
	var t0 := Time.get_ticks_msec()
	ws.build(poses)
	print("LOOK build %d ms" % (Time.get_ticks_msec() - t0))
	var cam := Camera3D.new()
	cam.fov = WetStreet.FOV
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.far = 80.0
	root.add_child(cam)
	cam.global_position = Vector3(0.0, WetStreet.EYE, 1.5)
	cam.rotation_degrees = Vector3(WetStreet.PITCH_DEG, 0, 0)
	cam.current = true
	DirAccess.make_dir_recursive_absolute(OUT)
	for mode in ["wet", "dry", "probe", "legacy"]:
		ws.set_dry(mode == "dry")
		ws.set_probe(0 if mode == "probe" else -1)
		ws.set_legacy(mode == "legacy")
		for f in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.save_png(OUT + "look_" + mode + ".png")
		print("LOOK %s asphalt mean luminance %.4f" % [mode, asphalt_mean(cam, img)])
	print("ch5clook: 0 fail")
	quit(0)
