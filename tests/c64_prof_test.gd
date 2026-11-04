## godot --path . -s tests/c64_prof_test.gd   (C64: hot-loop audit; each path timed on a fixed scene, 3 repeats, median ms)
## Prints "PROF <name> <median ms> (<r1>,<r2>,<r3>)". Native-capable paths are timed both ways (KINE_NO_NATIVE=1 toggled via OS.set_environment).
## Writes nothing. No bar except that every path ran and returned a non-empty result (the table is the deliverable).
extends SceneTree

var fails := 0
var rows := []


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func time3(name: String, f: Callable) -> void:
	var ts := []
	var last = null
	for r in 3:
		var t := Time.get_ticks_usec()
		last = f.call()
		ts.append((Time.get_ticks_usec() - t) / 1000.0)
	var s := ts.duplicate()
	s.sort()
	print("PROF %s %.2f ms (%.2f, %.2f, %.2f)" % [name, s[1], ts[0], ts[1], ts[2]])
	ok(last != null, "%s ran" % name)


func sphere_mesh(seg: int, rings: int, r: float) -> KMesh:
	var prof := [[0.0, -r]]
	for k in range(1, rings):
		var a := -PI / 2.0 + PI * float(k) / rings
		prof.append([r * cos(a), r * sin(a)])
	prof.append([0.0, r])
	return KMeshPrims._lathe(seg, prof)


func skin_scene(nv: int, nb: int) -> Dictionary:
	var V := PackedVector3Array()
	var bo := PackedInt32Array()
	var w := PackedFloat32Array()
	V.resize(nv)
	bo.resize(nv * 4)
	w.resize(nv * 4)
	var mats := []
	for b in nb:
		mats.append(Transform3D(Basis(Vector3.UP, 0.1 * b).scaled(Vector3(1, 1.02, 1)), Vector3(0.01 * b, 0.02 * b, 0)))
	for i in nv:
		V[i] = Vector3(sin(i * 0.37), float(i) / nv * 1.8, cos(i * 0.37)) * 0.1
		var c := (i * 7) % nb
		for q in 4:
			bo[i * 4 + q] = (c + q) % nb
			w[i * 4 + q] = [0.5, 0.3, 0.15, 0.05][q]
	return {"V": V, "bo": bo, "w": w, "mats": mats}


func _init() -> void:
	var sph := sphere_mesh(64, 48, 0.5)
	print("scene: sphere %d verts %d faces" % [sph.verts.size(), sph.faces.size()])
	# 1 voxel remesh (M1)
	for mode in ["native", "gdscript"]:
		OS.set_environment("KINE_NO_NATIVE", "1" if mode == "gdscript" else "0")
		time3("voxel_remesh[%s] (sphere r0.5, voxel 0.02)" % mode, func(): return KMeshVoxelRemesh.remesh(sph, 0.02))
	# 2 decimate
	for mode in ["native", "gdscript"]:
		OS.set_environment("KINE_NO_NATIVE", "1" if mode == "gdscript" else "0")
		time3("decimate[%s] (to 25 %%)" % mode, func(): return KMeshDecimate.collapse(KMeshDecimate.copy(sph), 0.25))
	# 3 STL / 3MF packing
	var soup := PackedVector3Array()
	var tri := PackedInt32Array()
	var tm := sphere_mesh(96, 96, 0.5)
	var vv := tm.verts
	for f in tm.faces:
		var fa: PackedInt32Array = f
		for k in range(1, fa.size() - 1):
			tri.append(fa[0]); tri.append(fa[k]); tri.append(fa[k + 1])
	var bodies := [{"v": vv, "t": tri}]
	for mode in ["native", "gdscript"]:
		OS.set_environment("KINE_NO_NATIVE", "1" if mode == "gdscript" else "0")
		time3("stl_bytes[%s] (%d tris)" % [mode, tri.size() / 3], func(): return MeshExport.stl_bytes(bodies))
	OS.set_environment("KINE_NO_NATIVE", "0")
	# 4 skin weights (auto weights, heat)
	var cyl := KMeshPrims._lathe(24, [[0.0, 0.0], [0.05, 0.0], [0.05, 0.3], [0.05, 0.6], [0.05, 0.9], [0.0, 0.9]])
	var cyl2 := sphere_mesh(48, 40, 0.3)
	var bones := KMeshAutoWeights.chain(PackedVector3Array([Vector3(0, -0.28, 0), Vector3(0, -0.1, 0), Vector3(0, 0.1, 0), Vector3(0, 0.28, 0)]))
	time3("autoweights_compute (%d verts, 3 bones)" % cyl2.verts.size(), func(): return KMeshAutoWeights.compute(cyl2, bones))
	# 5 skinning (LBS and DQS reference over a surface) at 20k verts
	var sc := skin_scene(20000, 24)
	time3("dq_skin_surface LBS (20k verts)", func(): return DqSkin.skin_surface(sc["V"], sc["bo"], sc["w"], sc["mats"], 0.0))
	time3("dq_skin_surface DQS (20k verts)", func(): return DqSkin.skin_surface(sc["V"], sc["bo"], sc["w"], sc["mats"], 1.0))
	# 6 blueprint (hidden-line style sheet build: all tabs, SVG + DXF)
	var b := Building.make("Bay house")
	Building.add_room(b, 0, 0, 8, 6)
	Building.add_floor(b)
	Building.add_opening(b, "r1", "front", "door", 0.0)
	Building.add_opening(b, "r2", "front", "window", -2.0)
	Building.set_roof(b, "gable")
	time3("blueprint sheets+svg+dxf (4 tabs)", func():
		var n := 0
		for t in Blueprint.tabs(b):
			var sh := Blueprint.sheet(b, t, Blueprint.choose(b))
			n += Blueprint.to_svg(sh).length() + Blueprint.to_dxf(sh).length()
		return n)
	print("C64PROF %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
