## godot --path . --position 4000,4000 --resolution 1280x720 -s tests/perfprobe_scene.gd -- --out=C:/Temp/claude/perf/x.jsonl [--secs=10] [--scale3d=0.67] [--quality=low|medium|high] [--pages=BODY,POSE] [--stress=clips50]
## THE PERF PROBE'S SCENE (tools/perfprobe.py launches it and samples the process's CPU and RAM from outside; this script is a tool, not a suite:
## it has no bars). Runs the real app (main.tscn) at a fixed 1280 x 720, vsync off (the cost shows), and walks every page for --secs each:
## BODY, POSE, ANIMATE (a 6-clip scene playing), STAGE (20 props), CHECK, DELIVER, MODEL (the body's mesh open), SCULPT (strokes every frame),
## SURFACE. Per page it appends one JSON line to --out: fps median, 1 % low, frame time median / p99 / max, Godot static memory, VRAM,
## draw calls, primitives; "ev":"start" / "end" lines mark the page so the python side can attribute its samples. The first second of a page
## is a warm-up (pipelines compile, a panel builds) kept out of the fps figures, its worst frame is "first_max_ms".
## --stress=NAME runs one stress case instead of the tour: clips50|clips100|clips200, props20|props50|props100, mesh1m, tex4k, city.
## Nothing is written outside user:// and --out.
extends SceneTree

const PAGES := ["BODY", "POSE", "ANIMATE", "STAGE", "CHECK", "DELIVER", "MODEL", "SCULPT", "SURFACE"]
const CLIP_SRC := ["scenes/walk_bat.json", "scenes/combo3.json", "scenes/thrust.json", "scenes/swing_back.json", "scenes/swing_fore.json", "scenes/dodge_side.json"]
const PROP_KINDS := ["box", "crate", "table", "chair"]

var m: Node
var out_path := ""
var secs := 10.0
var args := {}
var stroke_phase := 0
var stroke_c := Vector2.ZERO
var stroke_down := false


func log_line(d: Dictionary) -> void:
	var f := FileAccess.open(out_path, FileAccess.READ_WRITE if FileAccess.file_exists(out_path) else FileAccess.WRITE)
	f.seek_end()
	f.store_line(JSON.stringify(d))
	f.flush()
	f.close()


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func pct(a: Array, p: float) -> float:
	if a.is_empty():
		return NAN
	var s := a.duplicate()
	s.sort()
	return float(s[mini(s.size() - 1, int(ceil(p * s.size())) - 1)])


func rinfo(k: int) -> float:
	return float(RenderingServer.get_rendering_info(k))


## one second warm-up, then secs of frames: the statistics of the frame gaps and the renderer's counters at the end
func measure(page: String, seconds: float, per_frame := Callable()) -> Dictionary:
	log_line({"ev": "start", "page": page, "t": Time.get_ticks_msec()})
	var gaps := []
	var first := []
	var t_start := Time.get_ticks_usec()
	var last := t_start
	var n := 0
	while true:
		await process_frame
		var now := Time.get_ticks_usec()
		var gap := (now - last) / 1000.0
		last = now
		var el := (now - t_start) / 1e6
		if el < 1.0:
			first.append(gap)
		else:
			gaps.append(gap)
		if per_frame.is_valid():
			per_frame.call(n)
		n += 1
		if el >= 1.0 + seconds:
			break
	var med := pct(gaps, 0.5)
	var p99 := pct(gaps, 0.99)
	var r := {"ev": "end", "page": page, "cur_page": String(m.cur_page) if m != null else "", "frames": gaps.size(),
		"fps_med": snappedf(1000.0 / med, 0.1), "fps_1low": snappedf(1000.0 / p99, 0.1), "ft_med_ms": snappedf(med, 0.01),
		"ft_p99_ms": snappedf(p99, 0.01), "ft_max_ms": snappedf(gaps.max() if not gaps.is_empty() else 0.0, 0.1),
		"first_max_ms": snappedf(first.max() if not first.is_empty() else 0.0, 0.1),
		"static_mb": snappedf(OS.get_static_memory_usage() / 1048576.0, 0.1),
		"vram_mb": snappedf(rinfo(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"draws": int(rinfo(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)),
		"prims": int(rinfo(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)),
		"objects": int(rinfo(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)),
		"renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(),
		"scale3d": root.scaling_3d_scale, "msaa": int(root.msaa_3d), "tier": Quality.applied["tier"], "t": Time.get_ticks_msec()}
	log_line(r)
	return r


func mouse(p: Vector2, down: bool, motion := false) -> void:
	var e: InputEvent
	if motion:
		var mm := InputEventMouseMotion.new()
		mm.position = p
		mm.global_position = p
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		e = mm
	else:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = down
		mb.position = p
		mb.global_position = p
		if down:
			mb.button_mask = MOUSE_BUTTON_MASK_LEFT
		e = mb
	root.push_input(e)


## a sculpt stroke around the sphere every frame: press once, move a point of a circle per frame, release at the end
func stroke_frame(n: int) -> void:
	if not stroke_down:
		mouse(stroke_c + Vector2(40, 0), true)
		stroke_down = true
	var a := n * 0.12
	mouse(stroke_c + Vector2(cos(a), sin(a)) * 40.0, true, true)


func stroke_end() -> void:
	if stroke_down:
		mouse(stroke_c, false)
		stroke_down = false


func boot() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	if not args.has("vsync"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.easy.set_on(false, false)   # Expert: the mesh pages exist
	if args.has("quality"):
		m.gfx_mode = String(args["quality"])
		m.gfx_tier = String(args["quality"])
		Quality.apply(root, m.gfx_tier, m.light_key)
	if args.has("scale3d"):
		root.scaling_3d_scale = float(args["scale3d"])
	m._as_wait = -1e9   # no autosave write while timing
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.undo.clear()
	m.redo.clear()
	await idle(10)


func clips_n(n: int) -> void:
	var cl := []
	for i in n:
		cl.append(Clips.make(CLIP_SRC[i % CLIP_SRC.size()], 0.4 * i, {"bin": 0.2, "bout": 0.2} if i % 2 == 0 else {}))
	m.S.clips = cl
	m._refresh()


func props_n(n: int, spread := 3.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	m.S.props = []
	for i in n:
		var p := Props.make(PROP_KINDS[i % PROP_KINDS.size()], Props.xf_at(Vector3(rng.randf_range(-spread, spread), 0, rng.randf_range(-spread, spread)), rng.randf_range(0, 360)))
		m.S.props.append(p)
	m._props_show()


## a UV sphere of about tris triangles as a .glb under user://, registered as a prop kind
func make_big_glb(tris: int) -> String:
	var rings := int(sqrt(tris / 2.0))
	var segs := rings
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.resize((rings + 1) * (segs + 1))
	norms.resize(verts.size())
	for r in rings + 1:
		var th := PI * r / rings
		for s in segs + 1:
			var ph := TAU * s / segs
			var n := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			verts[r * (segs + 1) + s] = n * 0.5
			norms[r * (segs + 1) + s] = n
	idx.resize(rings * segs * 6)
	var k := 0
	for r in rings:
		for s in segs:
			var a := r * (segs + 1) + s
			var b := a + segs + 1
			idx[k] = a; idx[k + 1] = b; idx[k + 2] = a + 1
			idx[k + 3] = a + 1; idx[k + 4] = b; idx[k + 5] = b + 1
			k += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = am
	var holder := Node3D.new()
	holder.add_child(mi)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_scene(holder, st)
	var path := "user://zz_perf_big_%d.glb" % OS.get_process_id()
	doc.write_to_filesystem(st, path)
	holder.free()
	Props.register("my big", AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 1, 1)), path, 1.0)
	return path


func tour() -> void:
	var pages: Array = String(args["pages"]).split(",") if args.has("pages") else PAGES
	for pg in pages:
		var per := Callable()
		match String(pg):
			"ANIMATE":
				clips_n(6)
				m.S.loop = true
				m.playhead = 0.0
				m.playing = true
			"STAGE":
				m.playing = false
				props_n(20)
			"MODEL":
				m.playing = false
				BaseBody.start(m)
			"SCULPT":
				m._sculpt_start()
				await idle(3)
				var wc: Vector3 = m.ksc.view.global_position
				m._turn_to(0.0, 0.0, 1.6, wc, false)
				await idle(6)
				stroke_c = m.cam.unproject_position(wc)
				stroke_down = false
				per = stroke_frame
		if String(pg) != "SCULPT":
			m._page_set(String(pg), false)
		else:
			m._page_set("SCULPT", false)
		await idle(3)
		await measure(String(pg), secs, per)
		stroke_end()
		await idle(2)


func stress() -> void:
	var name := String(args["stress"])
	var t0 := Time.get_ticks_usec()
	log_line({"ev": "start", "page": name, "t": Time.get_ticks_msec()})
	if name.begins_with("clips"):
		clips_n(int(name.trim_prefix("clips")))
		m.S.loop = true
		m.playhead = 0.0
		m.playing = true
		m._page_set("ANIMATE", false)
	elif name.begins_with("props"):
		props_n(int(name.trim_prefix("props")))
		m._page_set("STAGE", false)
	elif name == "city":
		props_n(200, 15.0)
		m._page_set("STAGE", false)
		m._turn_to(0.0, -0.9, 45.0, Vector3.ZERO, false)
	elif name == "mesh1m":
		make_big_glb(int(args.get("tris", 1000000)))
		m.S.props = [Props.make("my big", Props.xf_at(Vector3(1.5, 0, 0), 0.0))]
		m._props_show()
		m._page_set("STAGE", false)
	elif name == "tex4k":
		var img := Image.create(4096, 4096, true, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		for y in range(0, 4096, 8):   # a coarse pattern, then the mipmaps: the content does not change the cost
			for x in range(0, 4096, 8):
				img.fill_rect(Rect2i(x, y, 8, 8), Color(rng.randf(), rng.randf(), rng.randf()))
		img.generate_mipmaps()
		var tex := ImageTexture.create_from_image(img)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		props_n(3)
		for c in m.ui_props_root.get_children():
			for mi in c.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_override = mat
		for j in m.pieces:
			(m.pieces[j] as MeshInstance3D).material_override = mat
		m._page_set("STAGE", false)
	var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
	await idle(2)
	var r := await measure(name, secs)
	r["build_ms"] = snappedf(build_ms, 1.0)
	r["ev"] = "stress"
	log_line(r)


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := String(a).trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	out_path = String(args.get("out", "user://perfprobe.jsonl"))
	secs = float(args.get("secs", 10))
	if FileAccess.file_exists(out_path):
		DirAccess.remove_absolute(out_path)
	await boot()
	log_line({"ev": "boot", "renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(),
		"cores": OS.get_processor_count(), "size": [root.size.x, root.size.y], "version": Engine.get_version_info()["string"]})
	if args.has("stress"):
		await stress()
	else:
		await tour()
	log_line({"ev": "done"})
	quit(0)
