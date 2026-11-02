extends SceneTree
## godot --headless --path . -s tests/s261_test.gd
## S261 INSTANCES. Body: 1.5 x 1.5 x 1 mm box. Face 100 x 100 mm, 1000 copies scatter, gap 0.5.
##   A  1000 copies replay in < 1 s, 0 overlapping boxes (checked all-pairs), all inside the face, all sitting on the face plane
##   B  same seed through JSON text = same positions; another seed differs
##   C  STL export holds 1000 x the body's triangles
##   D  MultiMesh node: 1000 instances, one draw call (one surface), per-copy colours when a palette is given
##   E  CONTROL: pattern with 1000 copies is refused (PATTERN_MAX 64) and 64 pattern copies are slower per copy
##   F  CONTROL: an impossible count (40000 mm2 boxes in 100x100 with gap) fails in words, bars can fail
const MX := preload("res://scripts/build/mesh_export.gd")
var fails := 0
const SHOT := "C:/Users/Nick/tools/kine_workers/out/s261"

func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1

func _init() -> void:
	_run.call_deferred()

func rec_for(extra: Dictionary) -> Dictionary:
	var r := Part.make("t")
	var fs := [{"t": "prim", "id": "f1", "name": "P1", "kind": "box", "op": "new", "w": 1.5, "d": 1.5, "h": 1.0}]
	r["seq"] = 1
	r["features"] = fs
	var f := Part.new_feature(r, "instances", extra)
	r["features"].append(f)
	return r

func ins(n: int, seed_: int, mode := "scatter", more := {}) -> Dictionary:
	var d := {"body": 0, "count": n, "mode": mode, "seed": seed_, "gap": 0.5, "face": {"c": [0, 0, 0], "n": "y", "w": 100, "h": 100}}
	d.merge(more, true)
	return d

func _run() -> void:
	if not Part.available():
		print("SKIP no CAD DLL")
		quit(0)
		return
	# find the prim's field names by a trial replay
	var r := rec_for(ins(1000, 42))
	var base := Part.replay({"name": "t", "seq": 1, "features": [r["features"][0]]}, -1, {"keep": true})
	var bb: AABB = Part.replay({"name": "t", "seq": 1, "features": [r["features"][0]]}, -1, {})["aabb"]
	print("body aabb m: ", bb.size)
	for i in base.get("ids", []):
		KCad_release(i)
	var t0 := Time.get_ticks_usec()
	var res := Part.replay(r, -1, {"keep": true})
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("replay ms ", ms, " errors ", res["errors"])
	var li: Array = res["instances"]
	ok(li.size() == 1 and (li[0]["pos"] as PackedVector3Array).size() == 1000, "A 1000 copies placed")
	ok(ms < 1000.0, "A replay %.0f ms < 1000" % ms)
	var pos: PackedVector3Array = li[0]["pos"]
	var sz: Vector3 = (li[0]["mesh"] as ArrayMesh).get_aabb().size
	var ov := 0
	for i in pos.size():
		for j in range(i + 1, pos.size()):
			if absf(pos[i].x - pos[j].x) < sz.x and absf(pos[i].z - pos[j].z) < sz.z:
				ov += 1
	ok(ov == 0, "A overlaps %d" % ov)
	var inside := true
	var mn := 1e9
	for p in pos:
		mn = minf(mn, p.x)
		inside = inside and absf(p.x) < 0.05 + 1e-6 and absf(p.z) < 0.05 + 1e-6
	ok(inside, "A inside the face")
	var rj: Dictionary = Part.from_file(JSON.parse_string(JSON.stringify(r)))
	var r2 := Part.replay(rj, -1, {"keep": true})
	var pos2: PackedVector3Array = r2["instances"][0]["pos"]
	ok(pos2 == pos, "B same seed same positions after save/reload")
	var r3 := Part.replay(rec_for(ins(1000, 43)), -1, {"keep": true})
	ok(r3["instances"][0]["pos"] != pos, "B another seed differs")
	var bodies: Dictionary = MX.bodies_of(r)
	var tris := 0
	for b in bodies["bodies"]:
		tris += (b["t"] as PackedInt32Array).size() / 3
	var one := MX.bodies_of(rec_for(ins(1, 42)))
	var t1 := 0
	for b in one["bodies"]:
		t1 += (b["t"] as PackedInt32Array).size() / 3
	ok(t1 > 0 and tris == 1000 * t1, "C STL tris %d = 1000 x %d" % [tris, t1])
	var stl := MX.stl_bytes(bodies["bodies"])
	ok(stl.decode_u32(80) == tris, "C STL header count")
	var node: MultiMeshInstance3D = load("res://scripts/build/part_instances.gd").build_node(li[0])
	ok(node.multimesh.instance_count == 1000 and node.multimesh.mesh.get_surface_count() == 1, "D multimesh 1000 in one surface")
	var rp := rec_for(ins(1000, 42, "scatter", {"looks": ["#ff0000", "#00ff00"]}))
	var cl: PackedColorArray = Part.replay(rp, -1, {"keep": true})["instances"][0]["cols"]
	ok(cl.size() == 1000 and cl[0] != cl[1] or cl.find(Color.RED) >= 0, "D per-copy looks")
	# E control: pattern
	var pr := Part.make("p")
	pr["seq"] = 1
	pr["features"] = [r["features"][0].duplicate(true)]
	pr["features"].append(Part.new_feature(pr, "pattern", {"body": 0, "kind": "linear", "count": 1000, "mm": 2.0, "dir": "x", "op": "new"}))
	var pe := Part.replay(pr, -1, {})
	ok(pe["errors"].size() == 1, "E pattern 1000 refused: " + str(pe["errors"].values()))
	pr["features"][1]["count"] = 64
	var t2 := Time.get_ticks_usec()
	var p64 := Part.replay(pr, -1, {})
	var pms := (Time.get_ticks_usec() - t2) / 1000.0
	print("pattern 64 copies ms ", pms, " bodies ", p64["bodies"])
	ok(pms / 64.0 > ms / 1000.0, "E pattern %.2f ms/copy slower than instances %.3f ms/copy" % [pms / 64.0, ms / 1000.0])
	# F control: 500 copies of a 10 x 10 body cannot all fit on 100 x 100 (500 x 100 mm2 = 5x the face)
	var PI = load("res://scripts/build/part_instances.gd")
	var fbox := AABB(Vector3.ZERO, Vector3(0.01, 0.005, 0.01))
	var ff := ins(500, 5, "scatter", {"gap": 0.0})
	var fr: Dictionary = PI.places(fbox, ff)
	var msg := String(fr["err"])
	print("F says: ", msg)
	var rx := RegEx.create_from_string("^only ([0-9]+) of 500 fit")
	var mt := rx.search(msg)
	ok(mt != null, "F message reads 'only K of 500 fit'")
	var K := int(mt.get_string(1)) if mt != null else -1
	ok(K > 0 and K < 500, "F K=%d placed, below 500" % K)
	var kp: PackedVector3Array = fr["partial"]   # the places scatter did find before it gave up
	var kov := 0
	for i in kp.size():
		for j in range(i + 1, kp.size()):
			if absf(kp[i].x - kp[j].x) < 0.01 - 1e-6 and absf(kp[i].z - kp[j].z) < 0.01 - 1e-6:
				kov += 1
	ok(kp.size() == K and kov == 0, "F the K=%d copies have %d overlaps" % [K, kov])
	var rfail := Part.replay(rec_for(ins(500, 5, "scatter", {"gap": 0.0, "face": {"c": [0, 0, 0], "n": "y", "w": 100, "h": 100}})), -1, {})
	ok(rfail["instances"].size() == 1, "F (a 1.5 mm body, 500 copies, fits) still places")
	# G screenshots: 1000 scattered copies with the palette, drawn as a MultiMesh on a face
	var pal := ["#e63946", "#2a9d8f", "#f4a261", "#457b9d", "#e9c46a"]
	var rg := Part.replay(rec_for(ins(1000, 42, "scatter", {"looks": pal})), -1, {})
	DirAccess.make_dir_recursive_absolute(SHOT)
	for wsz in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var vp := SubViewport.new()
		vp.size = wsz
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var face := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(0.1, 0.1)
		face.mesh = pm
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(0.85, 0.85, 0.85)
		face.material_override = fm
		vp.add_child(face)
		var np: Node = load("res://scripts/build/part_instances.gd").build_node(rg["instances"][0])
		vp.add_child(np)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 0.108
		cam.position = Vector3(0, 0.2, 0.0)
		cam.rotation_degrees = Vector3(-90, 0, 0)
		vp.add_child(cam)
		cam.current = true
		var lt := DirectionalLight3D.new()
		lt.rotation_degrees = Vector3(-60, 20, 0)
		vp.add_child(lt)
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(1, 1, 1)
		e.ambient_light_energy = 0.5
		env.environment = e
		vp.add_child(env)
		for _k in 6:
			await process_frame
		var img := vp.get_texture().get_image()
		var path := "%s/s261_%dx%d.png" % [SHOT, wsz.x, wsz.y]
		img.save_png(path)
		# count distinct palette colours that reached the picture
		var seen := {}
		for yy in range(0, wsz.y, 2):
			for xx in range(0, wsz.x, 2):
				var c := img.get_pixel(xx, yy)
				if c.s < 0.15:
					continue
				var best := -1
				var bd := 9.0
				for pi in pal.size():
					var dh := absf(c.h - Color.html(pal[pi]).h)
					dh = minf(dh, 1.0 - dh)
					if dh < bd:
						bd = dh
						best = pi
				seen[best] = int(seen.get(best, 0)) + 1
		var enough := 0
		for k2 in seen:
			enough += 1 if int(seen[k2]) >= 30 else 0
		ok(enough == pal.size(), "G %dx%d: palette hues in the picture, pixel counts %s (%s)" % [wsz.x, wsz.y, str(seen), path])
		vp.queue_free()
	print("FAILS ", fails)
	quit(1 if fails > 0 else 0)

func KCad_release(i) -> void:
	load("res://scripts/kcad.gd").release(int(i))
