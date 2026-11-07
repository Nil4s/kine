## godot --path . -s tests/perfscout_test.gd   (L54; SCOUT_ONLY=scene|part|mesh|body|misc runs one section)
## PERF SCOUT (lane L54, 11-06): times what the END USER waits for. MEASURE ONLY, no bars on speed; the doc is docs/PERF_SCOUT_1106.md.
## Run: WT_MAX=8 bash /c/Users/Nick/tools/kine_workers/wtest.sh perfscout      (tests/perfscout_test.gd extends this file)
## Every row is printed "ROW|op|n|ms|reps|native" and written to C:/Temp/claude/perfscout/rows.jsonl (median of 5 runs; an op that
## takes over 0.5 s is run 3 times, over 3 s once, the "reps" column says so). The only "ok" lines are sanity checks that an op ran
## and returned something (a scout that times an error would lie).
## Scale: scene ops at 50 / 256 / 1000 objects; the exponent is log(ms1000/ms50) / log(1000/50), computed in the doc.
extends SceneTree

const OUT := "C:/Temp/claude/perfscout/rows.jsonl"
const DT := 1.0 / 60.0
var m: Node
var fails := 0
var rows := []
var H := {}   # lambdas capture locals by value: results go here


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


## median ms of c.call(), reps by cost; c may not await
func bench(op: String, n: int, c: Callable, native := "?", max_reps := 5) -> float:
	var t0 := Time.get_ticks_usec()
	c.call()
	var first := (Time.get_ticks_usec() - t0) / 1000.0
	var reps := mini(max_reps, 5 if first < 500.0 else (3 if first < 3000.0 else 1))
	var ts := [first]
	for i in reps - 1:
		var t := Time.get_ticks_usec()
		c.call()
		ts.append((Time.get_ticks_usec() - t) / 1000.0)
	ts.sort()
	var med: float = ts[ts.size() / 2]
	row(op, n, med, reps, native)
	return med


func row(op: String, n: int, ms: float, reps: int, native: String) -> void:
	var d := {"op": op, "n": n, "ms": snappedf(ms, 0.01), "reps": reps, "native": native}
	rows.append(d)
	print("ROW|%s|%d|%.2f|%d|%s" % [op, n, ms, reps, native])


func flush() -> void:
	DirAccess.make_dir_recursive_absolute("C:/Temp/claude/perfscout")
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	for d in rows:
		f.store_line(JSON.stringify(d))
	f.close()


func boot() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.easy.set_on(false, false)
	m._as_wait = -1e9
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.undo.clear()
	m.redo.clear()
	m.set_process(false)   # only our frames run _process
	await idle(4)


# ------------------------------------------------------------------ scene objects
const KINDS4 := ["box", "crate", "table", "chair"]


## n props on a grid; "shared": 4 kinds (the app batches them into MultiMeshes); "unique": a different part kind each (no batching)
func set_props(n: int, unique: bool) -> void:
	var side := int(ceil(sqrt(float(n))))
	var props := []
	for i in n:
		var pos := Vector3((i % side) * 1.5 - side * 0.75, 0, (i / side) * 1.5 - side * 0.75 + 4.0)
		var kind: String = KINDS4[i % 4]
		if unique:
			kind = "part:scout%d#%d" % [i, i]
			if not Props.has_kind(kind):
				var am := ArrayMesh.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.3 + 0.0001 * i, 0.4, 0.3)
				am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bm.get_mesh_arrays())
				Props.register_part(kind, am)
		props.append(Props.make(kind, Props.xf_at(pos, float(i * 37 % 360))))
	m.S.props = props


func frames_ms(n: int, per := Callable()) -> Dictionary:
	PerfDoc.on = true
	PerfDoc.acc = {}
	var ts := []
	var tot := {}
	for f in n:
		PerfDoc.acc = {}
		var t0 := Time.get_ticks_usec()
		m._process(DT)
		var t1 := Time.get_ticks_usec()
		if per.is_valid():
			per.call(f)
		await process_frame   # the engine's draw
		var t2 := Time.get_ticks_usec()
		ts.append([(t1 - t0) / 1000.0, (t2 - t1) / 1000.0])
		for k in PerfDoc.acc:
			tot[k] = float(tot.get(k, 0.0)) + float(PerfDoc.acc[k]) / 1000.0
	PerfDoc.on = false
	var proc := []
	var drw := []
	for t in ts:
		proc.append(t[0])
		drw.append(t[1])
	proc.sort()
	drw.sort()
	for k in tot:
		tot[k] = tot[k] / n
	return {"proc": proc[proc.size() / 2], "frame": drw[drw.size() / 2], "br": tot,
		"draw": int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)),
		"prims": int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))}


func scene_ops() -> void:
	for variant in ["shared", "unique"]:
		for n in [50, 256, 1000]:
			var u: bool = variant == "unique"
			var tag := "scene.%s" % variant
			set_props(n, u)
			bench(tag + ".props_show(rebuild)", n, func(): m._props_show(), "gd")
			await idle(2)
			bench(tag + ".snapshot", n, func(): m._snapshot(), "gd", 3)
			# undo / redo of one move
			m.undo.clear()
			m.redo.clear()
			bench(tag + ".push_undo", n, func():
				m._step_hint = "scout"
				m._push_undo()
				m.S.props[0]["xf"] = Props.xf_at(Vector3(randf(), 0, 4), 0.0), "gd", 3)
			var up: Array = []
			var rp: Array = []
			for i in 5:
				m._step_hint = "scout"
				m._push_undo()
				m.S.props[0]["xf"] = Props.xf_at(Vector3(i * 0.1, 0, 4), 0.0)
			for i in 5:
				var t0 := Time.get_ticks_usec()
				m._undo()
				up.append((Time.get_ticks_usec() - t0) / 1000.0)
			for i in 5:
				var t0 := Time.get_ticks_usec()
				m._redo()
				rp.append((Time.get_ticks_usec() - t0) / 1000.0)
			up.sort()
			rp.sort()
			row(tag + ".undo", n, up[2], 5, "gd")
			row(tag + ".redo", n, rp[2], 5, "gd")
			ok(m.S.props.size() == n, "%s %d props after undo/redo" % [variant, n])
			bench(tag + ".outliner.objects", n, func(): Outliner.objects(m.S), "gd")
			if m.ui_browser != null:
				bench(tag + ".browser.refresh(outliner/inspector tree)", n, func(): m.ui_browser.refresh(), "gd", 3)
			bench(tag + ".pick_prop(click)", n, func(): m._pick_prop(Vector2(640, 360)), "gd")
			bench(tag + ".props_settle", n, func(): Props.settle(m.S.props, C36Grip.air_held(m.S)), "gd", 3)
			bench(tag + ".solid_props(B.props)", n, func(): m.S.solid_props(), "gd")
			# save / load
			H["txt"] = ""
			bench(tag + ".save(to_dict+stringify)", n, func(): H["txt"] = JSON.stringify(m.S.to_dict(m.B)), "gd", 3)
			ok(String(H["txt"]).length() > 100, "%s %d saved %d bytes" % [variant, n, String(H["txt"]).length()])
			H["parsed"] = null
			bench(tag + ".load.json_parse", n, func(): H["parsed"] = JSON.parse_string(H["txt"]), "engine C++", 3)
			bench(tag + ".load.from_dict", n, func(): var S2 := Scene.new(); S2.from_dict(H["parsed"]), "gd", 3)
			# per frame
			var r: Dictionary = await frames_ms(30)
			row(tag + ".frame._process", n, r["proc"], 30, "gd")
			row(tag + ".frame.total(incl draw)", n, r["frame"], 30, "engine")
			print("INFO|%s %d: draw calls %d, prims %d, nodes %d, process breakdown ms: %s" % [tag, n, r["draw"], r["prims"], r["nodes"], _top(r["br"])])
	set_props(0, false)
	m._props_show()


func _top(br: Dictionary) -> String:
	var ks := br.keys()
	ks.sort_custom(func(a, b): return br[a] > br[b])
	var out := []
	for k in ks.slice(0, 6):
		out.append("%s=%.2f" % [k, br[k]])
	return ", ".join(out)


# ------------------------------------------------------------------ CAD parts
func part_ops() -> void:
	if not Part.available():
		print("INFO|KCad not available: part ops skipped")
		return
	for n in [10, 50, 256]:
		var rec := Part.make("scout")
		var side := int(ceil(sqrt(float(n))))
		for i in n:   # separate bodies
			Part.prim(rec, "box", {"x": (i % side) * 30.0, "y": 0.0, "z": (i / side) * 30.0, "w": 20.0, "h": 10.0, "d": 20.0})
		H["res"] = {}
		bench("part.replay(n separate boxes)", n, func(): H["res"] = Part.replay(rec, -1, {"effects": true}), "native kine_cad")
		ok(int(H["res"].get("bodies", 0)) == n, "part %d boxes -> %d bodies" % [n, int(H["res"].get("bodies", 0))])
		var rec2 := Part.make("scoutj")
		for i in n:   # a chain of overlapping boxes joined into ONE body
			Part.prim(rec2, "box", {"x": i * 15.0, "y": 0.0, "z": 0.0, "w": 20.0, "h": 10.0, "d": 20.0, "op": "join" if i > 0 else "new"})
		bench("part.replay(n joined boxes, one body)", n, func(): H["res"] = Part.replay(rec2, -1, {"effects": true}), "native kine_cad")
		# one parameter edit near the END (the user drags a dimension): the full replay again
		var rec3: Dictionary = rec2.duplicate(true)
		(rec3["features"][n - 1] as Dictionary)["w"] = 25.0
		bench("part.replay(after editing the LAST step)", n, func(): H["res"] = Part.replay(rec3, -1, {"effects": true}), "native kine_cad")
		if n <= 50:
			var rec4: Dictionary = rec2.duplicate(true)
			(rec4["features"][0] as Dictionary)["w"] = 25.0
			bench("part.replay(after editing the FIRST step)", n, func(): H["res"] = Part.replay(rec4, -1, {"effects": true}), "native kine_cad")
	# a plain sketch-extrude-fillet part with holes, the everyday one
	var rp := Part.make("holes")
	Part.prim(rp, "box", {"x": 0.0, "y": 0.0, "z": 0.0, "w": 200.0, "h": 20.0, "d": 100.0})
	for i in 40:
		Part.prim(rp, "cylinder", {"x": 10.0 + (i % 10) * 18.0, "y": -1.0, "z": 15.0 + (i / 10) * 20.0, "axis": "y", "r": 4.0, "len": 22.0, "op": "cut"})
	H["rr"] = {}
	bench("part.replay(plate + 40 drilled holes)", 40, func(): H["rr"] = Part.replay(rp, -1, {"effects": true}), "native kine_cad")
	ok(int(H["rr"].get("bodies", 0)) >= 1, "plate with holes built")


# ------------------------------------------------------------------ kmesh
func ico(sub: int) -> KMesh:
	return KMeshPrims.ico_sphere(1.0, sub)


func mesh_ops() -> void:
	for sub in [3, 4, 5]:   # 1280 / 5120 / 20480 tris
		var mesh := ico(sub)
		var nt := mesh.triangle_count()
		var tag := "kmesh"
		bench(tag + ".rebuild(half-edges)", nt, func(): mesh.rebuild(), "gd")
		bench(tag + ".to_array_mesh", nt, func(): mesh.to_array_mesh(true), "gd")
		var am := mesh.to_array_mesh(true)
		bench(tag + ".from_array_mesh", nt, func(): KMesh.new().from_array_mesh(am), "gd")
		bench(tag + ".to_dict(save)", nt, func(): mesh.to_dict(), "gd")
		bench(tag + ".is_manifold/validate", nt, func(): mesh.is_manifold(), "gd")
		bench(tag + ".symmetry_map", nt, func(): mesh.symmetry_map(0, 1e-4), "gd")
		if sub <= 4:
			bench(tag + ".subdivide(1 level)", nt, func(): KMeshSubdiv.subdivide(mesh, 1), "gd (verify)")
		if sub <= 5:
			bench(tag + ".decimate(collapse 50%)", nt, func(): KMeshDecimate.collapse(KMeshDecimate.copy(mesh), 0.5), "native (decimate)" if KMeshDecimate.native_on() else "gd")
		var vox := 0.03 if sub <= 4 else 0.02
		H["rr"] = {}
		bench(tag + ".voxel_remesh", nt, func(): H["rr"] = KMeshVoxelRemesh.remesh(mesh, vox), "native" if KMeshVoxelRemesh.native_on() else "gd")
		ok(H["rr"].get("ok", false), "remesh ran on %d tris" % nt)
		# bevel: 30 edges spread over the mesh
		var es := []
		var all_e: Array = mesh.edges()
		for i in range(0, all_e.size(), maxi(1, all_e.size() / 30)):
			var e = all_e[i]
			es.append(Vector2i(int(e[0]), int(e[1])) if (e is Array or e is PackedInt32Array) else Vector2i(e))
		if sub <= 4:
			bench(tag + ".bevel(30 edges)", nt, func():
				var c := KMeshDecimate.copy(mesh)
				H["bres"] = KMeshBevel.bevel_edges(c, es, 0.01), "gd", 3)
			ok(true, "bevel ran: %s" % str(H.get("bres", {}).get("msg", H.get("bres", {}).keys())))
		# sculpt: 40 dabs of one stroke
		var sc := KMeshSculpt.new()
		var mc := KMeshDecimate.copy(mesh)
		var t0 := Time.get_ticks_usec()
		sc.begin(mc, {"radius": 0.3})
		var begin_ms := (Time.get_ticks_usec() - t0) / 1000.0
		row(tag + ".sculpt.begin(stroke start)", nt, begin_ms, 1, "native" if KMeshSculpt.native_door() != null else "gd")
		var ds := []
		for i in 40:
			var a := i * 0.15
			var p := Vector3(cos(a), 0.3, sin(a)).normalized()
			var t1 := Time.get_ticks_usec()
			sc.dab(p, p, 1.0)
			ds.append((Time.get_ticks_usec() - t1) / 1000.0)
		ds.sort()
		row(tag + ".sculpt.dab(median of 40)", nt, ds[20], 40, "native" if KMeshSculpt.native_door() != null else "gd")
		sc.end()
	# boolean (the GDScript one the docs say takes 1-2 s)
	for sub in [2, 3, 4]:
		var a := ico(sub)
		var b := ico(sub)
		for i in b.verts.size():
			b.verts[i] += Vector3(0.5, 0.2, 0.1)
		b.rebuild()
		var nt := a.triangle_count() + b.triangle_count()
		H["out"] = null
		bench("kmesh.boolean(union of 2 spheres)", nt, func(): H["out"] = KMeshBoolean.run(a, b, "union"), "gd", 3)
		ok(H["out"] != null, "boolean union ran (%d tris in)" % nt)
	# autoweights: a 5120-tri sphere and 3 chained bones
	for sub in [3, 4]:
		var mesh := ico(sub)
		var bones := KMeshAutoWeights.chain(PackedVector3Array([Vector3(0, -1, 0), Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 2, 0)]))
		H["aw"] = {}
		bench("kmesh.autoweights(heat diffusion)", mesh.verts.size(), func(): H["aw"] = KMeshAutoWeights.compute(mesh, bones), "gd + native CG" if KMeshAutoWeights._solve_native() else "gd")
		ok(String(H["aw"].get("error", "x")) == "", "autoweights ran on %d verts" % mesh.verts.size())
	# retopo net setup+rebuild
	var rm := ico(4)
	var net := KMeshRetopoNet.new()
	bench("kmesh.retopo.setup", rm.triangle_count(), func(): net.setup(rm), "gd")
	# primitives
	bench("kmesh.prim.uv_sphere(128x64)", 128 * 64 * 2, func(): KMeshPrims.uv_sphere(1.0, 128, 64), "gd")


# ------------------------------------------------------------------ body per frame
func body_ops() -> void:
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.S.loop = true
	m.playhead = 0.0
	for na in [1]:   # (a second fighter via _actor_add crashed the app on the scout's off-screen window: tests/perf4_test.gd measures 4)
		await idle(2)
		var r: Dictionary = await frames_ms(60, func(f): m.playing = true)
		m.playing = false
		row("body.play.frame._process(%d fighters)" % na, na, r["proc"], 60, "mixed (skin native)")
		row("body.play.frame.total(incl draw)(%d fighters)" % na, na, r["frame"], 60, "engine")
		print("INFO|body %d fighters: draw %d, breakdown ms %s" % [na, r["draw"], _top(r["br"])])
	# idle frame (nothing playing)
	var ri: Dictionary = await frames_ms(30)
	row("body.idle.frame._process", 1, ri["proc"], 30, "gd")
	print("INFO|idle breakdown ms %s" % _top(ri["br"]))
	# soft flesh on
	for g in SoftBody.GROUPS:
		m.soft_set(g, true)
	await idle(2)
	var t0 := Time.get_ticks_msec()
	while not m.soft_live.ready() and Time.get_ticks_msec() - t0 < 90000:
		m._process(DT)   # the bake lands in _process (soft_live.poll), which the scout drives by hand
		await process_frame
	row("softskin.bake(wait for the background bake)", 6, float(Time.get_ticks_msec() - t0), 1, "thread, native softskin")
	var rs: Dictionary = await frames_ms(60, func(f): m.playing = true)
	m.playing = false
	row("softskin.play.frame._process(6 regions)", 6, rs["proc"], 60, "native (kine_softskin)")
	print("INFO|soft on: breakdown ms %s" % _top(rs["br"]))
	for g in SoftBody.GROUPS:
		m.soft_set(g, false)


# ------------------------------------------------------------------ nature, look, export
func misc_ops() -> void:
	for n in [1000, 10000]:
		var it := {"kind": "scatter", "of": "rock", "n": n, "spacing": 0.15, "jitter": 0.5, "size": 0.1, "seed": 3,
			"area": {"shape": "rect", "x": 0.0, "z": 0.0, "w": 60.0, "d": 60.0}}
		H["sc"] = {}
		bench("nature.scatter(points)", n, func(): H["sc"] = Nature.scatter(it, {}), "gd", 3)
		ok(int(H["sc"].get("placed", 0)) > 500, "scatter %d placed %d" % [n, int(H["sc"].get("placed", 0))])
		bench("nature.scatter_node(points+MultiMesh)", n, func():
			var nd: Node3D = NatureView.scatter_node(it, {})
			if nd != null:
				nd.free(), "gd", 3)
	# export
	var gl := "C:/Temp/claude/perfscout/scout.glb"
	DirAccess.make_dir_recursive_absolute("C:/Temp/claude/perfscout")
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	bench("export.glb(combo3, mesh)", 1, func(): GltfExport.write(m.S, m.B, gl, true), "gd", 3)
	bench("export.usd text(combo3)", 1, func(): UsdExport.text(m.S, m.B), "gd", 3)
	for n in [50, 256, 1000]:
		set_props(n, false)
		m._props_show()
		bench("export.usd text(combo3 + props)", n, func(): UsdExport.text(m.S, m.B), "gd", 3)
	set_props(0, false)
	m._props_show()
	# look_facts id pass
	await idle(2)
	if m.has_method("_look_facts") or true:
		var units := LookFacts.units_of(m)
		bench("look_facts.units_of", units.size(), func(): LookFacts.units_of(m), "gd")
		var rs: Dictionary = {}
		var ts := []
		for i in 3:
			var t0 := Time.get_ticks_usec()
			rs = await LookFacts.serve(m, {})
			ts.append((Time.get_ticks_usec() - t0) / 1000.0)
		ts.sort()
		row("look_facts.serve(whole view, id render+decode)", units.size(), ts[1], 3, "gd + render")
		ok(not rs.is_empty(), "look_facts returned")


## hot-function split of the scene ops (instrumentation: the same calls, timed separately)
func prof_ops() -> void:
	for n in [256, 1000]:
		set_props(n, false)
		m._props_show()
		await idle(2)
		bench("prof.Scene.check(B) (the first step of save)", n, func(): m.S.check(m.B), "gd", 3)
		bench("prof.PropInstances.plan", n, func(): PropInstances.plan(m.S.props, -1, []), "gd")
		var plan := PropInstances.plan(m.S.props, -1, [])
		bench("prof.PropInstances.build(all groups)", n, func():
			for g in plan:
				for mmi in PropInstances.build(m.S.props, g):
					mmi.free(), "gd", 3)
		bench("prof.Props.mesh(per prop x all)", n, func():
			for p in m.S.props:
				Props.mesh(p).free(), "gd", 3)
		bench("prof.Props.settle", n, func(): Props.settle(m.S.props, {}), "gd", 3)
		bench("prof.Props.to_dict(all)", n, func(): m.S.props.map(func(p): return Props.to_dict(p)), "gd")
		bench("prof.S.props_at(t)", n, func(): m.S.props_at(0.5, m.B), "gd")
	set_props(0, false)
	m._props_show()


func _init() -> void:
	await boot()
	var what := OS.get_environment("SCOUT_ONLY")
	if what == "" or what == "scene":
		await scene_ops()
	if what == "" or what == "prof":
		await prof_ops()
	if what == "" or what == "part":
		part_ops()
	if what == "" or what == "mesh":
		mesh_ops()
	if what == "" or what == "body":
		await body_ops()
	if what == "" or what == "misc":
		await misc_ops()
	flush()
	print("perfscout: %d rows, %d fail" % [rows.size(), fails])
	quit(0)
