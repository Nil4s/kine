## ASSEMBLY RENDER (gaps G11 / G21 of docs/CHALLENGE_FEEDBACK.md): an Assembly and its animation (AssemblyAnim) filmed to PNG frames, a
## contact sheet and an .mp4, so a lane no longer writes its own scene and grab loop. One call:
##   var r: Dictionary = await AssemblyRender.render(host, asm, {"dir": "C:/Temp/x", "width": 640, "height": 360})
## Each frame is the animation at that time, posed through AssemblyAnim.frames (the drives, their links, the loop solver), drawn in its own
## SubViewport world (the app's scene is not in the picture). Nothing in the record changes.
## opts (all optional):
##   "dir"      the folder for frame_0000.png ... (made if missing; default <Assembly.export_dir>/<name>_motion_<stamp>)
##   "width", "height"   pixels (default 640 x 360)
##   "times"    the times to film (default every frame of the animation; an assembly with no keys gives the one still frame at 0)
##   "camera"   {"pos": Vector3 (m), "look": Vector3 (m), "fov": deg} or {"xf": Transform3D, "fov": deg}; default: framed on the box the
##              parts sweep through, from the front right and a little above (PartMotion's view), or from "view_dir" (a Vector3 toward the camera)
##   "cut"      {"n": Vector3, "w": float (m)}: SectionLook's section, the side n . x > w cut away, each part with its own cap colour
##   "only"     [part ids]: just these parts are drawn (the camera still frames them all)
##   "background" Color; "sheet" (default true), "sheet_tile" (tile width px, default 256), "sheet_cols" (default: about square);
##   "mp4" (default true: when ffmpeg is found, PlayblastExport's encoder), "ffmpeg" (a path; default PlayblastExport.find_ffmpeg)
##   "keep_images" true: the result carries the frames as Images too ("images")
##   "steps"    G33STAGE: the frames already posed, [{"t", "moves", "visible": [ids] (optional)}] (AssemblyStage.steps): used instead of the
##              animation; a part not in a step's "visible" is hidden in that frame. "fps": the .mp4's rate (default the animation's)
## Answers {"ok", "why", "dir", "frames": [paths], "n", "size": Vector2i, "times", "sheet": path | "", "tiles", "cols", "rows", "tile": Vector2i,
## "mp4": path | "", "ffmpeg": path | "", "unsolved": [t], "ms"}
class_name AssemblyRender
extends RefCounted

const W := 640
const H := 360
const FOV := 35.0
const VIEW_DIR := Vector3(0.55, 0.4, 1.0)
const BG := Color(0.93, 0.94, 0.96)
const TILE := 256


static func _stamp() -> String:
	return Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")


## the part's place in frame step (metres)
static func xf_in(step: Dictionary, p: Dictionary) -> Transform3D:
	var mv: Dictionary = step.get("moves", {})
	var id := String(p["id"])
	return (mv[id] as Transform3D) * Assembly.xf_of(p) if mv.has(id) else Assembly.xf_of(p)


## the box every part sweeps through over the frames (metres)
static func sweep_box(asm: Dictionary, steps: Array) -> AABB:
	var out := AABB()
	var first := true
	for st in steps:
		for p in asm["parts"]:
			var b: AABB = Assembly.built(p["rec"])["aabb"]
			if b.size == Vector3.ZERO:
				continue
			var w := xf_in(st, p) * b
			out = w if first else out.merge(w)
			first = false
	return out


## a contact sheet: the images (any size, all alike) shrunk to tile_w wide, cols across (0: about square), left to right, top to bottom
static func sheet(imgs: Array, tile_w := TILE, cols := 0) -> Image:
	if imgs.is_empty():
		return null
	var im0: Image = imgs[0]
	var tw := maxi(8, tile_w)
	var th := maxi(8, int(round(float(tw) * im0.get_height() / maxf(1.0, im0.get_width()))))
	var c := cols if cols > 0 else int(ceil(sqrt(float(imgs.size()))))
	var r := int(ceil(float(imgs.size()) / float(c)))
	var out := Image.create(c * tw, r * th, false, Image.FORMAT_RGB8)
	out.fill(Color(0.2, 0.2, 0.22))
	for i in imgs.size():
		out.blit_rect(tile_of(imgs[i], tw, th), Rect2i(0, 0, tw, th), Vector2i((i % c) * tw, (i / c) * th))
	return out


## one tile as sheet() makes it (a test compares a sheet's tile with it)
static func tile_of(img: Image, tw: int, th: int) -> Image:
	var t := img.duplicate() as Image
	t.convert(Image.FORMAT_RGB8)
	t.resize(tw, th, Image.INTERPOLATE_BILINEAR)
	return t


static func _scene(host: Node, asm: Dictionary, opts: Dictionary, box: AABB) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = Vector2i(int(opts.get("width", W)), int(opts.get("height", H)))
	vp.transparent_bg = false
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	host.add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = opts.get("background", BG)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	world.add_child(sun)
	sun.look_at_from_position(Vector3(0.5, 1.0, 1.0), Vector3.ZERO, Vector3.UP)
	var nodes := {}
	var cut: Dictionary = opts.get("cut", {})
	var only: Array = opts.get("only", [])
	var i := 0
	for p in asm["parts"]:
		var mi := MeshInstance3D.new()
		mi.name = String(p["id"])
		var mesh = Assembly.built(p["rec"])["mesh"]
		if not cut.is_empty() and mesh != null:
			var res := Part.replay(p["rec"], -1, {})
			if res.get("mesh") != null:
				var cm := (res["mesh"] as ArrayMesh).duplicate() as ArrayMesh
				var mats := SectionLook.materials(res.get("looks", []), cm.get_surface_count(), cut, [], false)
				for s in cm.get_surface_count():
					var mt: ShaderMaterial = mats[s]
					mt.set_shader_parameter("cap", SectionLook.CAPS[i % SectionLook.CAPS.size()])   # one cap colour per part (ch13_scene's rule)
					cm.surface_set_material(s, mt)
				mesh = cm
		mi.mesh = mesh
		mi.visible = only.is_empty() or only.has(String(p["id"]))
		world.add_child(mi)
		nodes[String(p["id"])] = mi
		i += 1
	var cam := Camera3D.new()
	cam.near = 0.001
	cam.far = 1000.0
	world.add_child(cam)
	var cdef: Dictionary = opts.get("camera", {})
	cam.fov = float(cdef.get("fov", FOV))
	if cdef.has("xf"):
		cam.global_transform = cdef["xf"]
	elif cdef.has("pos"):
		cam.look_at_from_position(cdef["pos"], cdef.get("look", box.get_center()), Vector3.UP)
	else:
		var radius := maxf(box.size.length() * 0.5 * 1.08, 1e-3)
		var aspect := float(vp.size.x) / maxf(1.0, float(vp.size.y))
		var half := deg_to_rad(cam.fov) * 0.5
		var fit := minf(half, atan(tan(half) * aspect))   # the narrower of the two half-angles
		var vd: Vector3 = opts.get("view_dir", VIEW_DIR)
		if vd.length() < 1e-6 or absf(vd.normalized().dot(Vector3.UP)) > 0.999:
			vd = VIEW_DIR
		cam.look_at_from_position(box.get_center() + vd.normalized() * (radius / sin(fit)), box.get_center(), Vector3.UP)
	cam.current = true
	return {"vp": vp, "nodes": nodes, "cam": cam}


## films the animation (see the header). Await it: each frame waits for the GPU
static func render(host: Node, asm: Dictionary, opts := {}) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var out := {"ok": false, "why": "", "dir": "", "frames": [], "n": 0, "size": Vector2i.ZERO, "times": [], "sheet": "", "tiles": 0, "cols": 0, "rows": 0,
		"tile": Vector2i.ZERO, "mp4": "", "ffmpeg": "", "unsolved": [], "ms": 0}
	if (asm.get("parts", []) as Array).is_empty():
		out["why"] = "the assembly has no parts"
		return out
	if host == null or not host.is_inside_tree():
		out["why"] = "the host node is not in the scene tree"
		return out
	if DisplayServer.get_name() == "headless":
		out["why"] = "no pictures without a screen (headless)"
		return out
	var ts: Array = opts.get("times", [])
	var steps: Array = []
	if opts.get("steps", null) is Array:   # G33STAGE: posed by the caller (AssemblyStage.steps)
		steps = opts["steps"]
		ts = steps.map(func(s): return float(s["t"]))
		for s in steps:
			if not bool(s.get("ok", true)):
				(out["unsolved"] as Array).append(s["t"])
	else:
		if ts.is_empty():
			ts = AssemblyAnim.times(asm) if AssemblyAnim.has_anim(asm) else [0.0]
		var fr := AssemblyAnim.frames(asm, ts)
		steps = fr["steps"]
		out["unsolved"] = fr["unsolved"]
	out["times"] = ts
	var dir := String(opts.get("dir", ""))
	if dir == "":
		dir = "%s/%s_motion_%s" % [Assembly._out_dir(), Assembly._stem(asm), _stamp()]
	dir = ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	out["dir"] = dir
	var sc := _scene(host, asm, opts, sweep_box(asm, steps))
	var vp: SubViewport = sc["vp"]
	var nodes: Dictionary = sc["nodes"]
	var imgs: Array = []
	var paths: Array = []
	var only: Array = opts.get("only", [])
	for k in steps.size():
		for p in asm["parts"]:
			var mi := nodes[String(p["id"])] as MeshInstance3D
			mi.transform = xf_in(steps[k], p)
			if (steps[k] as Dictionary).get("visible", null) is Array:
				mi.visible = (only.is_empty() or only.has(String(p["id"]))) and (steps[k]["visible"] as Array).has(String(p["id"]))
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		if img == null or img.is_empty():
			out["why"] = "the GPU gave no picture for frame %d" % k
			break
		img.convert(Image.FORMAT_RGB8)
		var path := "%s/frame_%04d.png" % [dir, k]
		if img.save_png(path) != OK:
			out["why"] = "could not write %s" % path
			break
		paths.append(path)
		imgs.append(img)
	vp.queue_free()
	out["frames"] = paths
	out["n"] = paths.size()
	if imgs.is_empty() or paths.size() != steps.size():
		out["ms"] = Time.get_ticks_msec() - t0
		return out
	out["size"] = Vector2i((imgs[0] as Image).get_width(), (imgs[0] as Image).get_height())
	if bool(opts.get("sheet", true)):
		var tw := int(opts.get("sheet_tile", TILE))
		var cols := int(opts.get("sheet_cols", 0))
		var sh := sheet(imgs, tw, cols)
		var c := cols if cols > 0 else int(ceil(sqrt(float(imgs.size()))))
		out["cols"] = c
		out["rows"] = int(ceil(float(imgs.size()) / float(c)))
		out["tiles"] = imgs.size()
		out["tile"] = Vector2i(sh.get_width() / c, sh.get_height() / int(out["rows"]))
		var sp := dir + "/sheet.png"
		if sh.save_png(sp) == OK:
			out["sheet"] = sp
	if bool(opts.get("mp4", true)) and imgs.size() > 1:
		var ff := PlayblastExport.find_ffmpeg(String(opts.get("ffmpeg", "")))
		out["ffmpeg"] = ff
		if ff != "":
			var mp4 := "%s/%s.mp4" % [dir, Assembly._stem(asm)]
			if PlayblastExport.encode(ff, dir, int(opts.get("fps", AssemblyAnim.fps(asm))), mp4) == 0 and FileAccess.file_exists(mp4):
				out["mp4"] = mp4
	if bool(opts.get("keep_images", false)):
		out["images"] = imgs
	out["ok"] = true
	out["ms"] = Time.get_ticks_msec() - t0
	return out
