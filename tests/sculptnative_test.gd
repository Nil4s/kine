extends SceneTree
## godot --headless --path . -s tests/sculptnative_test.gd     (first GDExtension pilot: native/ KineSculptNative, scripts/kmesh_sculpt.gd)
## Native vs GDScript sculpt core, on a test sphere (4 Catmull-Clark levels of a box pushed to r = 0.5: 1538 verts) and the
## fighter body (BaseBody.read of the mannequin skin: ~7k verts). One 20-dab stroke per brush, the same dabs on two copies of the mesh.
## Bars, written before measuring:
##   1 DLL: the class loads (reported) or every native bar says SKIP (the suite still PASSes without the DLL)
##   2 EQUAL: for every brush (9), on both meshes: every vert, face normal and vert normal of the native stroke is within 1e-5 of
##     the GDScript stroke; also draw inverted, the 4 falloffs, X symmetry (draw, smooth, grab) on the sphere
##   3 verts_in: native and GDScript return the same ids in the same order (sphere + body)
##   4 NO DLL: with KMeshSculpt.native_on = false the stroke runs the GDScript path (no native door) and is deterministic
##   5 TIMING (median of 5, begin + 20 dabs + end): the table is printed; BAR native >= 5x faster than GDScript on the body for
##     draw / smooth / flatten / inflate (the profile's 240-1650 ms strokes)
const MANNEQUIN := "res://assets/mannequin.glb"
const REPS := 5
const TOL := 1e-5
var fails := 0
var skips := 0
var have := false
var table := []


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func skip(what: String) -> void:
	print("SKIP " + what + " (no KineSculptNative: the DLL is missing)")
	skips += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


static func med(a: Array) -> float:
	var s := a.duplicate()
	s.sort()
	return float(s[s.size() / 2])


static func sphere() -> KMesh:
	var m := KMeshSubdiv.subdivide(KMeshPrims.cube(Vector3.ONE, 1), 4)
	for i in m.verts.size():
		m.verts[i] = m.verts[i].normalized() * 0.5
	m.rebuild()
	return m


## 20 surface points walked along the mesh's own connectivity (dabs one vert apart, the worst overlap), with their vert normals
static func walk(m: KMesh) -> Dictionary:
	var hits := []
	var ns := []
	var seen := {}
	var v := m.verts.size() / 3
	for i in 20:
		hits.append(m.verts[v])
		ns.append(m.vert_normals[v])
		seen[v] = true
		var nxt := -1
		for u in m.vert_neighbors(v):
			if not seen.has(u):
				nxt = u
				break
		if nxt < 0:
			nxt = (v + 7) % m.verts.size()
		v = nxt
	return {"hits": hits, "ns": ns}


static func copy_of(src: KMesh) -> KMesh:
	var m := KMeshDecimate.copy(src)
	m.rebuild()
	return m


static func stroke(m: KMesh, w: Dictionary, params: Dictionary, native: bool) -> KMeshSculpt:
	KMeshSculpt.native_on = native
	var sc := KMeshSculpt.new()
	sc.begin(m, params)
	for i in 20:
		if params["brush"] == KMeshSculpt.GRAB:
			sc.to(w["hits"][i], w["ns"][i], 1.0)
		else:
			sc.dab(w["hits"][i], w["ns"][i], 1.0)
	sc.end()
	KMeshSculpt.native_on = true
	return sc


static func diff(a: KMesh, b: KMesh) -> float:
	var worst := 0.0
	for i in a.verts.size():
		worst = maxf(worst, (a.verts[i] - b.verts[i]).length())
	for i in a.vert_normals.size():
		worst = maxf(worst, (a.vert_normals[i] - b.vert_normals[i]).length())
	for i in a.face_normals.size():
		worst = maxf(worst, (a.face_normals[i] - b.face_normals[i]).length())
	return worst


func same(name: String, src: KMesh, w: Dictionary, params: Dictionary) -> void:
	if not have:
		skip("EQUAL %s" % name)
		return
	var a := copy_of(src)
	var b := copy_of(src)
	stroke(a, w, params, false)
	var sb := stroke(b, w, params, true)
	var moved := 0
	for i in a.verts.size():
		if a.verts[i] != src.verts[i]:
			moved += 1
	var d := diff(a, b)
	ok(sb._nb != null and moved > 0 and d < TOL, "EQUAL %s: native door %s, %d verts moved, max diff %s (< 1e-5)" % [name, str(sb._nb != null), moved, String.num_scientific(d)])


func time_stroke(src: KMesh, w: Dictionary, params: Dictionary, native: bool) -> float:
	var ts := []
	for r in REPS:
		var m := copy_of(src)
		var t0 := Time.get_ticks_usec()
		stroke(m, w, params, native)
		ts.append((Time.get_ticks_usec() - t0) / 1000.0)
	return med(ts)


func _init() -> void:
	var door = KMeshSculpt.native_door()   # loads native/kine_native.gdext when its DLL is there
	have = ClassDB.class_exists("KineSculptNative")
	ok(true, "1 DLL: KineSculptNative %s%s" % ["loaded" if have else "MISSING (native bars SKIP)", ", door ok" if door != null else ""])
	if have:
		ok(door != null, "1 DLL: the door script loads (version %d)" % door.version())
	# the fighter body
	var man: Node3D = (load(MANNEQUIN) as PackedScene).instantiate()
	root.add_child(man)
	for ap in man.find_children("*", "AnimationPlayer", true, false):
		ap.queue_free()
	await idle(2)
	var sk: Skeleton3D = man.find_children("*", "Skeleton3D", true, false)[0]
	sk.reset_bone_poses()
	var fake := FakeM.new()
	fake.skel = sk
	var n := 0
	for mi in man.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).skin != null:
			fake.pieces["body%d" % n] = mi
			n += 1
	fake.bone_idx = {"pelvis": sk.find_bone("pelvis")}
	var body := BaseBody.read(fake, {})
	body.rebuild()
	var sph := sphere()
	print("sphere %d verts / %d faces; body %d verts / %d faces" % [sph.verts.size(), sph.faces.size(), body.verts.size(), body.faces.size()])
	var meshes := {"sphere": [sph, 0.15], "body": [body, 0.1]}
	var walks := {"sphere": walk(sph), "body": walk(body)}
	# 3 verts_in
	for mn in meshes:
		if not have:
			skip("verts_in %s" % mn)
			continue
		var m: KMesh = copy_of(meshes[mn][0])
		var r: float = meshes[mn][1]
		KMeshSculpt.native_on = false
		var g := KMeshSculpt.new()
		g.begin(m, {"radius": r})
		KMeshSculpt.native_on = true
		var nt := KMeshSculpt.new()
		nt.begin(m, {"radius": r})
		var same_ids := true
		var tot := 0
		for h in walks[mn]["hits"]:
			var ia := g.verts_in(h, r)
			var ib := nt.verts_in(h, r)
			tot += ia.size()
			same_ids = same_ids and ia == ib and ia.size() > 0
		ok(same_ids, "3 verts_in %s: same ids, same order, 20 queries (%d ids)" % [mn, tot])
	# 2 equality
	for mn in meshes:
		var src: KMesh = meshes[mn][0]
		var r: float = meshes[mn][1]
		for br in KMeshSculpt.BRUSHES:
			same("%s %s" % [mn, br], src, walks[mn], {"brush": br, "radius": r, "strength": 0.005})
	var sw: Dictionary = walks["sphere"]
	same("sphere draw inverted", sph, sw, {"brush": "draw", "radius": 0.15, "strength": 0.01, "invert": true})
	same("sphere clay inverted", sph, sw, {"brush": "clay strips", "radius": 0.15, "strength": 0.01, "invert": true})
	same("sphere pinch inverted", sph, sw, {"brush": "pinch", "radius": 0.15, "strength": 0.01, "invert": true})
	for fo in KMeshSculpt.FALLOFFS:
		same("sphere draw falloff %s" % fo, sph, sw, {"brush": "draw", "radius": 0.15, "strength": 0.01, "falloff": fo})
	for br in [KMeshSculpt.DRAW, KMeshSculpt.SMOOTH, KMeshSculpt.GRAB, KMeshSculpt.INFLATE]:
		same("sphere %s sym_x" % br, sph, sw, {"brush": br, "radius": 0.15, "strength": 0.01, "sym_x": true})
	same("sphere draw sym_x + sym_y + radial 3", sph, sw, {"brush": "draw", "radius": 0.15, "strength": 0.01, "sym_x": true, "sym_y": true, "radial": 3})
	# 4 no DLL: the GDScript path is what runs, and it is deterministic
	var a := copy_of(sph)
	var b := copy_of(sph)
	var sa := stroke(a, sw, {"brush": "draw", "radius": 0.15, "strength": 0.01}, false)
	stroke(b, sw, {"brush": "draw", "radius": 0.15, "strength": 0.01}, false)
	ok(sa._nb == null and diff(a, b) == 0.0 and a.verts != sph.verts, "4 NO DLL: native_on = false runs the GDScript path (door null), twice the same bits")
	# 5 timing
	print("TIMING median of %d, begin + 20 dabs + end, ms" % REPS)
	print("mesh\tbrush\tgdscript\tnative\tspeedup")
	var fast := true
	for mn in ["sphere", "body"]:
		var src: KMesh = meshes[mn][0]
		var r: float = meshes[mn][1]
		for br in KMeshSculpt.BRUSHES:
			var pr := {"brush": br, "radius": r, "strength": 0.005}
			var tg := time_stroke(src, walks[mn], pr, false)
			var tn := time_stroke(src, walks[mn], pr, true) if have else -1.0
			print("%s\t%s\t%.2f\t%s\t%s" % [mn, br, tg, ("%.2f" % tn) if have else "-", ("%.1fx" % (tg / tn)) if have else "-"])
			if have and mn == "body" and br in [KMeshSculpt.DRAW, KMeshSculpt.SMOOTH, KMeshSculpt.FLATTEN, KMeshSculpt.INFLATE]:
				fast = fast and tn * 5.0 <= tg
	if have:
		ok(fast, "5 TIMING: native >= 5x faster on the body for draw / smooth / flatten / inflate")
	else:
		skip("5 TIMING native >= 5x")
	print("sculptnative: %d fail, %d skip" % [fails, skips])
	print("PASS" if fails == 0 else "FAIL")
	quit(1 if fails > 0 else 0)


class FakeM extends Node:
	var pieces := {}
	var bone_idx := {}
	var skel: Skeleton3D = null
