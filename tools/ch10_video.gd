extends SceneTree
## CH10 video: the CH1 house shaking under El Centro 1940 NS (z direction), drift exaggerated, code house beside the under-braced one, drift-vs-time plot.
## godot --position -30000,-30000 --audio-driver Dummy --resolution 1280x720 --path . -s tools/ch10_video.gd -- <outdir> [exaggeration=25] [planted=L | LR]
## Writes <outdir>/frames/f%05d.png, <outdir>/series.json; encode with ffmpeg afterwards (printed).
const FR := preload("res://scripts/build/ch10_frame.gd")
const HO := preload("res://scripts/build/ch10_house.gd")
const SIM := preload("res://scripts/build/ch10_sim.gd")

var outdir := ""
var S := 25.0
var planted := "L"


class Plot:
	extends Control
	var t: PackedFloat64Array
	var a: PackedFloat64Array
	var b: PackedFloat64Array
	var cur := 0
	var allow_mm := 49.4
	var ymax := 60.0
	var label_b := ""

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.07, 0.08, 0.10, 0.92))
		var f := ThemeDB.fallback_font
		var plot := Rect2(54, 22, size.x - 70, size.y - 44)
		draw_rect(plot, Color(0.12, 0.13, 0.16))
		var ymap := func(v: float) -> float: return plot.position.y + plot.size.y * (0.5 - 0.5 * v / ymax)
		var xmap := func(tt: float) -> float: return plot.position.x + plot.size.x * tt / t[t.size() - 1]
		for yv in [-allow_mm, allow_mm]:
			draw_line(Vector2(plot.position.x, ymap.call(yv)), Vector2(plot.end.x, ymap.call(yv)), Color(1, 0.8, 0.2, 0.8), 1.5)
		draw_line(Vector2(plot.position.x, ymap.call(0.0)), Vector2(plot.end.x, ymap.call(0.0)), Color(1, 1, 1, 0.25), 1.0)
		draw_string(f, Vector2(plot.position.x + 4, ymap.call(allow_mm) - 3), "ASCE 7 allowable 0.020 h = %.0f mm" % allow_mm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.8, 0.2))
		var n := t.size()
		var pa := PackedVector2Array()
		var pb := PackedVector2Array()
		for i in range(0, n, 2):
			pa.append(Vector2(xmap.call(t[i]), ymap.call(a[i])))
			pb.append(Vector2(xmap.call(t[i]), ymap.call(b[i])))
		draw_polyline(pb, Color(1.0, 0.35, 0.3), 1.6)
		draw_polyline(pa, Color(0.35, 0.75, 1.0), 1.6)
		draw_line(Vector2(xmap.call(t[cur]), plot.position.y), Vector2(xmap.call(t[cur]), plot.end.y), Color(1, 1, 1, 0.8), 1.5)
		draw_string(f, Vector2(6, 16), "roof drift vs time (mm, real, not exaggerated)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		draw_string(f, Vector2(plot.end.x - 360, 16), "code house", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.35, 0.75, 1.0))
		draw_string(f, Vector2(plot.end.x - 250, 16), label_b, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.35, 0.3))
		draw_string(f, Vector2(4, plot.position.y + 10), "+%.0f" % ymax, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.8, 0.8))
		draw_string(f, Vector2(4, plot.end.y), "-%.0f" % ymax, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.8, 0.8))
		draw_string(f, Vector2(plot.position.x, size.y - 4), "0 s", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.8, 0.8))
		draw_string(f, Vector2(plot.end.x - 40, size.y - 4), "%.0f s" % t[n - 1], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.8, 0.8))


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	outdir = args[0] if args.size() > 0 else "C:/Users/Nick/tools/kine_workers/out/ch10"
	if args.size() > 1:
		S = float(args[1])
	if args.size() > 2:
		planted = args[2]
	DirAccess.make_dir_recursive_absolute(outdir + "/frames")
	var mj = JSON.parse_string(FileAccess.get_file_as_string("res://out/ch1/members.json"))
	var rec := SIM.load_record()
	var dt := 0.01
	var ag := SIM.resample(rec, dt)
	var runs: Array = []
	for variant in [[], ["L"] if planted == "L" else ["L", "R"]]:
		var bld := HO.build(mj, {"remove_lines": variant})
		var mm := HO.to_model(bld)
		var ms := HO.masses(bld)
		var model: Dictionary = mm["model"]
		model["mass"] = ms["mass"]
		var n: int = bld["nodes"].size()
		var tops := SIM.top_nodes(bld)
		var load := PackedFloat64Array()
		load.resize(n * 6)
		for i in tops:
			load[i * 6 + 2] = 1.0
		var st := FR.solve(model, {"type": "static", "loads": load})
		var md := FR.solve(model, {"type": "modal", "start": st["u"], "iters": 3})
		var om: float = md["omega"]
		var w2 := 5.0 * om
		var recd := PackedInt32Array()
		for i in tops:
			recd.append(i * 6 + 2)
		var r := FR.solve(model, {"type": "newmark", "dt": dt, "nsteps": ag.size() - 1, "ag": ag, "dir": 2, "alpha": 2.0 * 0.05 * om * w2 / (om + w2), "beta": 2.0 * 0.05 / (om + w2), "record": recd, "snap_every": 5})
		print("variant %s: T %.3f s, %d snaps" % [str(variant), TAU / om, r["snaps"].size()])
		runs.append({"bld": bld, "r": r, "tops": tops, "T": TAU / om, "variant": variant})
	# roof drift series (mean top displacement, mm) at the snapshot rate
	var nsn: int = runs[0]["r"]["snaps"].size()
	var series_t := PackedFloat64Array()
	var sa := PackedFloat64Array()
	var sb := PackedFloat64Array()
	var ns: int = ag.size()
	for k in nsn:
		series_t.append(k * 5 * dt)
		for ri in 2:
			var sn: PackedFloat64Array = runs[ri]["r"]["snaps"][k]
			var tops: PackedInt32Array = runs[ri]["tops"]
			var m := 0.0
			var pk := 0.0
			for i in tops:
				m += sn[i * 6 + 2]
			m /= tops.size()
			(sa if ri == 0 else sb).append(m * 1000.0)
	# scene
	var root := get_root()
	root.size = Vector2i(1280, 720)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.19, 0.24)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.85)
	e.ambient_light_energy = 0.55
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = false
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(80, 80)
	ground.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.22, 0.30, 0.20)
	ground.material_override = gmat
	ground.position = Vector3(5, -0.002, 10)
	world.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 38.0
	world.add_child(cam)
	cam.position = Vector3(27.0, 9.5, -3.5)
	cam.look_at_from_position(cam.position, Vector3(4.9, 1.9, 10.0), Vector3.UP)
	var houses: Array = []
	for hi in 2:
		var hn := Node3D.new()
		hn.position = Vector3(0, 0, 0 if hi == 0 else 12.5)
		world.add_child(hn)
		var bld: Dictionary = runs[hi]["bld"]
		var tops: PackedInt32Array = runs[hi]["tops"]
		var items: Array = []
		for m in mj["members"]:
			var kd: String = m["kind"]
			if kd in ["ground", "siding", "shingle", "window", "door", "idoor"]:
				continue
			if kd == "wall_sheathing" and hi == 1 and (str(m["name"]).begins_with("sheathing.L.") or (planted == "LR" and str(m["name"]).begins_with("sheathing.R."))):
				continue
			var bb: Array = m["box_mm"]
			var mi := MeshInstance3D.new()
			var bx := BoxMesh.new()
			bx.size = Vector3((bb[3] - bb[0]) * 0.001, (bb[4] - bb[1]) * 0.001, (bb[5] - bb[2]) * 0.001)
			mi.mesh = bx
			var mat := StandardMaterial3D.new()
			var col := Color(0.82, 0.64, 0.38)
			if kd == "wall_sheathing" or kd == "gable_sheathing":
				col = Color(0.74, 0.62, 0.40)
			elif kd == "roof_sheathing":
				col = Color(0.46, 0.34, 0.26)
			elif kd == "slab" or kd == "footing":
				col = Color(0.55, 0.55, 0.57)
			elif kd in ["joist"]:
				col = Color(0.72, 0.55, 0.32)
			elif kd in ["rafter", "rafter_pair", "gable_rafter", "ridge"]:
				col = Color(0.88, 0.70, 0.42)
			mat.albedo_color = col
			mi.material_override = mat
			var c := Vector3((bb[0] + bb[3]) * 0.0005, (bb[1] + bb[4]) * 0.0005, (bb[2] + bb[5]) * 0.0005)
			mi.position = c
			hn.add_child(mi)
			# nearest top-plate node in plan
			var bi := 0
			var bd := 1e9
			for ti in tops:
				var p: Vector3 = bld["nodes"][ti]
				var d := (p.x - c.x) * (p.x - c.x) + (p.z - c.z) * (p.z - c.z)
				if d < bd:
					bd = d
					bi = ti
			var fixed_part: bool = kd in ["slab", "footing"]
			items.append({"mi": mi, "c": c, "ti": bi, "k": 0.0 if fixed_part else clampf(c.y / 2.448, 0.0, 1.0)})
		houses.append(items)
	# overlay
	var cl := CanvasLayer.new()
	root.add_child(cl)
	var title := Label.new()
	title.text = "CH10: the CH1 house under El Centro 1940 NS (PGA 0.349 g, z direction, unscaled)   |   displacement exaggerated x%d" % int(S)
	title.position = Vector2(14, 8)
	title.add_theme_font_size_override("font_size", 19)
	cl.add_child(title)
	var la := Label.new()
	la.text = "CODE HOUSE: all four wall lines braced\nT = %.2f s" % runs[0]["T"]
	la.position = Vector2(60, 60)
	la.add_theme_font_size_override("font_size", 17)
	cl.add_child(la)
	var lb := Label.new()
	var lbl_b := "line L bracing removed" if planted == "L" else "lines L and R bracing removed"
	lb.text = "UNDER-BRACED: %s\nT = %.2f s" % [lbl_b, runs[1]["T"]]
	lb.position = Vector2(760, 60)
	lb.add_theme_font_size_override("font_size", 17)
	cl.add_child(lb)
	var tl := Label.new()
	tl.position = Vector2(14, 36)
	tl.add_theme_font_size_override("font_size", 16)
	cl.add_child(tl)
	var plot := Plot.new()
	plot.position = Vector2(0, 540)
	plot.size = Vector2(1280, 180)
	plot.t = series_t
	plot.a = sa
	plot.b = sb
	plot.label_b = "under-braced (" + planted + " removed)"
	cl.add_child(plot)
	var pkA := 0.0
	var pkB := 0.0
	for k in nsn:
		pkA = maxf(pkA, absf(sa[k]))
		pkB = maxf(pkB, absf(sb[k]))
	plot.ymax = maxf(60.0, 1.2 * maxf(pkA, pkB))
	print("roof drift peaks: code %.2f mm, under-braced %.2f mm, plot +-%.0f mm" % [pkA, pkB, plot.ymax])
	await process_frame
	await process_frame
	for k in nsn:
		for hi in 2:
			var sn: PackedFloat64Array = runs[hi]["r"]["snaps"][k]
			for it in houses[hi]:
				var uz: float = sn[int(it["ti"]) * 6 + 2] * it["k"] * S
				it["mi"].position = it["c"] + Vector3(0, 0, uz)
		tl.text = "t = %5.1f s    ground accel %+0.2f g" % [k * 5 * dt, ag[mini(k * 5, ns - 1)] / SIM.G]
		plot.cur = k
		plot.queue_redraw()
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		img.save_png("%s/frames/f%05d.png" % [outdir, k])
	var f := FileAccess.open(outdir + "/series.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"dt": 5 * dt, "code_mm": Array(sa), "planted_mm": Array(sb), "planted": planted, "exaggeration": S, "T_code": runs[0]["T"], "T_planted": runs[1]["T"]}))
	f.close()
	print("frames done: ", nsn, "  ffmpeg -y -framerate 20 -i ", outdir, "/frames/f%05d.png -c:v libx264 -pix_fmt yuv420p ", outdir, "/ch10_el_centro.mp4")
	quit(0)
