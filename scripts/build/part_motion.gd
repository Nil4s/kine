class_name PartMotion
extends RefCounted
## P126 MOTION STUDY TO VIDEO (Friday plan 126, "export the mechanism moving as MP4"): the hinge's swing of an Easy Part, filmed. Each frame is
## the part replayed with the hinge turned by its curve (Part.replay's "pose", the same view as Expert's Play), drawn in a SubViewport of
## WIDTH x HEIGHT pixels and piped straight into ffmpeg (the Save video encoder: PlayblastExport.args_pipe). The curve is sampled at FPS,
## so a 2 s swing is 61 frames at 30 fps (the count Part.hinge_sweep walks). Nothing in the part changes: this only reads it.

const FPS := 30
const WIDTH := 1280
const HEIGHT := 720
const FOV := 35.0
const VIEW_DIR := Vector3(0.55, 0.4, 1.0)   # from the front, right and up a little: the swing and the piece beside it both show


## the frames of a hinge's swing: its curve's length at FPS, both ends included (0 s and 2 s at 30 fps = 61)
static func frame_count(f: Dictionary) -> int:
	var track: Array = f.get("track", [])
	if track.is_empty():
		return 0
	return int(floor(float(track[-1][0]) * FPS + 1e-6)) + 1


## the hinge's angle (degrees) at frame i: its curve at i / FPS, held inside the joint limit (as PartUI's Play holds it)
static func deg_at(f: Dictionary, i: int) -> float:
	var lim := Part.hinge_limit(f)
	return clampf(float(Curves.eval(f["track"], float(i) / FPS, Curves.mode_of(f))), -lim, lim)


## the box the whole swing fits in: the rest pose and the pose at the limit, both from Part.replay
static func swing_box(rec: Dictionary, f: Dictionary) -> AABB:
	var rest: AABB = Part.replay(rec, -1, {}).get("aabb", AABB())
	var turned: AABB = Part.replay(rec, -1, {"pose": {"f": String(f["id"]), "deg": Part.hinge_limit(f)}}).get("aabb", AABB())
	return rest.merge(turned)


## Films the swing of hinge hinge_id into mp4 (through the ffmpeg at ff). host: the node the SubViewport is added to (the main scene).
## Answers true when the file is written; false when the part cannot be shown or ffmpeg refuses the pipe.
static func render(host: Node, rec: Dictionary, hinge_id: String, mp4: String, ff: String) -> bool:
	var f := Part.feature(rec, hinge_id)
	var n := frame_count(f)
	var box := swing_box(rec, f)
	if n < 2 or box.size == Vector3.ZERO or ff == "":
		return false
	var sc := _scene(host, box)
	var vp: SubViewport = sc["vp"]
	var mi: MeshInstance3D = sc["mi"]
	var pipe := {}
	var wrote := true
	for i in n:
		var res := Part.replay(rec, -1, {"pose": {"f": hinge_id, "deg": deg_at(f, i)}})
		if res.get("mesh") == null:
			wrote = false
			break
		mi.mesh = res["mesh"]
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		if img == null or img.is_empty():
			wrote = false
			break
		img.convert(Image.FORMAT_RGB8)
		if pipe.is_empty():
			var io := OS.execute_with_pipe(ff, PlayblastExport.args_pipe(WIDTH, HEIGHT, FPS, mp4))
			if io.is_empty():
				wrote = false
				break
			pipe = {"stdin": io["stdio"], "pid": io["pid"]}
			Children.add(io["pid"], io["stdio"])   # closing the app mid-save ends ffmpeg too
		(pipe["stdin"] as FileAccess).store_buffer(img.get_data())
	vp.queue_free()
	if not pipe.is_empty():
		(pipe["stdin"] as FileAccess).close()
		while OS.is_process_running(pipe["pid"]):
			await host.get_tree().process_frame
		Children.done(pipe["pid"])
	return wrote and FileAccess.file_exists(mp4)


## the lit, framed SubViewport for the swing's box: {vp, mi} (mi takes the mesh of each pose)
static func _scene(host: Node, box: AABB) -> Dictionary:
	var bg := Tok.c("panel")
	bg.a = 1.0
	var vp := SubViewport.new()
	vp.size = Vector2i(WIDTH, HEIGHT)
	vp.transparent_bg = false
	vp.own_world_3d = true   # its own world: the app's scene (grid, the Easy part preview) is not in the picture
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	host.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = bg
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0.0)
	world.add_child(sun)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Tok.c("accent")
	mat.roughness = 0.6
	var mi := MeshInstance3D.new()
	mi.material_override = mat
	world.add_child(mi)
	var center := box.get_center()
	var radius := box.size.length() * 0.5 * 1.08
	var cam := Camera3D.new()
	cam.fov = FOV
	cam.near = 0.01
	cam.far = 100.0
	world.add_child(cam)
	cam.position = center + VIEW_DIR.normalized() * (radius / sin(deg_to_rad(FOV) * 0.5))
	cam.look_at(center, Vector3.UP)
	cam.current = true
	return {"vp": vp, "mi": mi}


## one picture of the part with the hinge at deg degrees, drawn by the same camera and light as the video (for comparing a video frame)
static func still(host: Node, rec: Dictionary, hinge_id: String, deg: float) -> Image:
	var f := Part.feature(rec, hinge_id)
	var sc := _scene(host, swing_box(rec, f))
	var vp: SubViewport = sc["vp"]
	var res := Part.replay(rec, -1, {"pose": {"f": hinge_id, "deg": deg}})
	var img: Image = null
	if res.get("mesh") != null:
		(sc["mi"] as MeshInstance3D).mesh = res["mesh"]
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		img = vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
	vp.queue_free()
	return img
