extends SceneTree
## godot --path . -s tests/n03_test.gd     (n03: KineMeshOpsNative, the native decimate / voxel remesh / STL, 3MF and OBJ packing)
## Runs each hot path on real app data both ways (KINE_NO_NATIVE switched in-process) and compares:
##   DECIMATE  the 13.8k sculpt sphere (KMeshSculptUI.make_sphere(0.3, 34)) to 2000 triangles, plain and with a UV seam (project_sphere):
##             identical vertex array, identical faces (same collapse order), ExportBudget.apply_bodies at the 2k budget identical
##   REMESH    KMeshVoxelRemesh.remesh of that sphere at the Remesh-lighter voxel: same vertex / face counts, vertices within 1e-5 relative
##   WRITERS   STL bytes and 3MF model text of a 30k-triangle welded body, and an OBJ with normals + uvs: byte identical
## Prints the timings (median of 5): GDScript ms / native ms / factor.
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func set_native(on: bool) -> void:
	OS.set_environment("KINE_NO_NATIVE", "" if on else "1")


func med(f: Callable) -> float:
	var a := []
	for i in 5:
		var t := Time.get_ticks_usec()
		f.call()
		a.append((Time.get_ticks_usec() - t) / 1000.0)
	a.sort()
	return a[2]


## the median of KMeshDecimate.collapse alone (the KMesh is built outside the clock)
func med_collapse(base: KMesh, nat: bool) -> float:
	set_native(nat)
	var a := []
	for i in 5:
		var k := KMesh.new().from_arrays(base.verts, base.faces)
		var t := Time.get_ticks_usec()
		KMeshDecimate.collapse(k, 1.0, 2000)
		a.append((Time.get_ticks_usec() - t) / 1000.0)
	a.sort()
	return a[2]


func row(name: String, g: float, n: float) -> void:
	print("TIME %-34s GDScript %9.1f ms   native %8.1f ms   x%.1f" % [name, g, n, g / maxf(n, 0.001)])


func max_rel(a: PackedVector3Array, b: PackedVector3Array) -> float:
	var w := 0.0
	var sc := 1e-9
	for p in a:
		sc = maxf(sc, p.length())
	for i in a.size():
		w = maxf(w, (a[i] - b[i]).length() / sc)
	return w


func body_of(k: KMesh) -> Dictionary:
	var arr := k.to_array_mesh().surface_get_arrays(0)
	var soup := PackedVector3Array()
	for ix in (arr[Mesh.ARRAY_INDEX] as PackedInt32Array):
		soup.append((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array)[ix])
	var b := MeshExport.weld(soup)
	b["name"] = "sphere"
	b["color"] = null
	return b


func _init() -> void:
	ok(MeshOpsDoor.on(), "KineMeshOpsNative is registered (DLL version %d)" % (MeshOpsDoor.door().version() if MeshOpsDoor.on() else -1))
	var base := KMeshSculptUI.make_sphere(0.3, 34)
	ok(base.triangle_count() > 13000 and base.triangle_count() < 14500, "sculpt sphere: %d triangles" % base.triangle_count())

	# ---------------- DECIMATE
	for variant in ["plain", "uv"]:
		var res := {}
		for nat in [false, true]:
			set_native(nat)
			var k := KMesh.new().from_arrays(base.verts, base.faces)
			if variant == "uv":
				KMeshUV.project_sphere(k)
			var r := KMeshDecimate.collapse(k, 1.0, 2000)
			res[nat] = [k, r]
		set_native(true)
		var kg: KMesh = res[false][0]
		var kn: KMesh = res[true][0]
		ok(kg.triangle_count() == kn.triangle_count(), "decimate %s: triangle count %d (GDScript) == %d (native)" % [variant, kg.triangle_count(), kn.triangle_count()])
		ok(kg.verts == kn.verts, "decimate %s: vertex arrays identical (%d verts)" % [variant, kg.verts.size()])
		ok(kg.faces == kn.faces, "decimate %s: faces identical (same collapse order)" % variant)
		var rg: Dictionary = res[false][1]
		var rn: Dictionary = res[true][1]
		ok(rg["collapses"] == rn["collapses"] and rg["refused_flip"] == rn["refused_flip"] and rg["refused_link"] == rn["refused_link"] and rg["refused_side"] == rn["refused_side"] and rg["refused_lock"] == rn["refused_lock"], "decimate %s: stats identical (collapses %d, flip %d, link %d, side %d, lock %d)" % [variant, rn["collapses"], rn["refused_flip"], rn["refused_link"], rn["refused_side"], rn["refused_lock"]])
		ok(absf(float(rg["max_cost"]) - float(rn["max_cost"])) <= 1e-9 * maxf(1.0, float(rg["max_cost"])), "decimate %s: max_cost %s vs %s" % [variant, str(rg["max_cost"]), str(rn["max_cost"])])
		if kg.attrs.has("uv"):
			ok(kg.attrs["uv"]["data"] == kn.attrs["uv"]["data"], "decimate uv: uv data identical")
	var tg := med_collapse(base, false)
	var tn := med_collapse(base, true)
	set_native(true)
	row("decimate 13.8k -> 2000", tg, tn)

	# export budget (the Friday 157 wrapper) on the welded body
	var body := body_of(base)
	var eb := {}
	for nat in [false, true]:
		set_native(nat)
		eb[nat] = ExportBudget.apply_bodies([body], 2000)
	set_native(true)
	ok((eb[false][0]["t"] as PackedInt32Array) == (eb[true][0]["t"] as PackedInt32Array) and (eb[false][0]["v"] as PackedVector3Array) == (eb[true][0]["v"] as PackedVector3Array), "ExportBudget.apply_bodies 2k: identical bodies (%d triangles)" % ((eb[true][0]["t"] as PackedInt32Array).size() / 3))
	var ebf := func(nat: bool) -> Callable:
		return func():
			set_native(nat)
			ExportBudget.apply_bodies([body], 2000)
	var eg := med(ebf.call(false))
	var en := med(ebf.call(true))
	set_native(true)
	row("Export budget 2k (apply_bodies)", eg, en)

	# ---------------- REMESH
	var area := 0.0
	for f in base.faces:
		var fa := f as PackedInt32Array
		area += (base.verts[fa[1]] - base.verts[fa[0]]).cross(base.verts[fa[2]] - base.verts[fa[0]]).length() * 0.5
	var h := sqrt(3.0 * area / (base.triangle_count() * 0.5))
	var rm := {}
	for nat in [false, true]:
		set_native(nat)
		rm[nat] = KMeshVoxelRemesh.remesh(base, h)
	set_native(true)
	var mg: KMesh = rm[false]["mesh"]
	var mn: KMesh = rm[true]["mesh"]
	ok(rm[false]["ok"] and rm[true]["ok"], "remesh ok both ways (voxel %.4f m)" % h)
	ok(mg.verts.size() == mn.verts.size() and mg.faces.size() == mn.faces.size(), "remesh: %d verts / %d quads (GDScript) vs %d / %d (native)" % [mg.verts.size(), mg.faces.size(), mn.verts.size(), mn.faces.size()])
	if mg.verts.size() == mn.verts.size():
		var e := max_rel(mg.verts, mn.verts)
		ok(e <= 1e-5, "remesh: vertices agree, worst %s of the mesh size (tolerance 1e-5: float32 math is mirrored op for op)" % str(e))
		ok(mg.faces == mn.faces, "remesh: faces identical")
	ok(rm[false]["voxels"] == rm[true]["voxels"], "remesh: grid %d voxels both ways" % rm[true]["voxels"])
	var rmf := func(nat: bool) -> Callable:
		return func():
			set_native(nat)
			KMeshVoxelRemesh.remesh(base, h)
	var rg2 := med(rmf.call(false))
	var rn2 := med(rmf.call(true))
	set_native(true)
	row("voxel remesh (lighter, one pass)", rg2, rn2)
	var half := KMesh.new().from_arrays(base.verts, base.faces)
	var undo := KMeshUndo.new()
	var app := func(nat: bool) -> Callable:
		return func():
			set_native(nat)
			var k := KMesh.new().from_arrays(base.verts, base.faces)
			# the slider does up to 2 trial remeshes + the apply
			for i in 2:
				KMeshVoxelRemesh.remesh(k, h)
			KMeshVoxelRemesh.apply(k, h, undo)
	var ag := med(app.call(false))
	var an := med(app.call(true))
	set_native(true)
	row("Remesh slider total (3 passes)", ag, an)

	# ---------------- WRITERS
	var big := KMeshSculptUI.make_sphere(0.3, 50)
	var bb := body_of(big)
	var ntri := (bb["t"] as PackedInt32Array).size() / 3
	ok(ntri >= 20000, "writer part: %d triangles welded (%d verts)" % [ntri, (bb["v"] as PackedVector3Array).size()])
	var stl := {}
	var xml := {}
	for nat in [false, true]:
		set_native(nat)
		stl[nat] = MeshExport.stl_bytes([bb])
		xml[nat] = MeshExport.model_xml([bb], "n03")
		MeshExport.write_stl("user://n03_%s.stl" % str(nat), [bb])
		MeshExport.write_3mf("user://n03_%s.3mf" % str(nat), [bb], "n03")
	set_native(true)
	ok(stl[false] == stl[true] and stl[true].size() == 84 + 50 * ntri, "STL: %d bytes, byte identical" % stl[true].size())
	ok(xml[false] == xml[true], "3MF model text: identical (%d chars)" % (xml[true] as String).length())
	ok(FileAccess.get_file_as_bytes("user://n03_false.stl") == FileAccess.get_file_as_bytes("user://n03_true.stl"), "STL files on disk identical")
	var zr := []
	for nat in ["false", "true"]:
		var z := ZIPReader.new()
		z.open("user://n03_%s.3mf" % nat)
		zr.append(z.read_file("3D/3dmodel.model"))
		z.close()
	ok(zr[0] == zr[1], "3MF files: the 3dmodel.model inside is identical")
	var wf := func(nat: bool, kind: String) -> Callable:
		return func():
			set_native(nat)
			if kind == "stl":
				MeshExport.write_stl("user://n03_t.stl", [bb])
			else:
				MeshExport.write_3mf("user://n03_t.3mf", [bb], "n03")
	for kind in ["stl", "3mf"]:
		var a := med(wf.call(false, kind))
		var b := med(wf.call(true, kind))
		set_native(true)
		row("%s write, %d triangles" % [kind.to_upper(), ntri], a, b)
	# OBJ with normals + uvs
	var am := big.to_array_mesh()
	var uvk := KMesh.new().from_arrays(big.verts, big.faces)
	var objs := {}
	var xf := Transform3D(Basis.from_euler(Vector3(0.3, 0.5, 0.1)).scaled(Vector3(1.0, 2.0, 0.5)), Vector3(0.1, 0.2, 0.3))
	for nat in [false, true]:
		set_native(nat)
		var r := ObjIO.export([{"name": "sph", "mesh": am, "xf": xf, "color": ObjIO.DEFAULT_COLOR}], "user://n03_%s/s.obj" % str(nat))
		objs[nat] = r
	set_native(true)
	var og := FileAccess.get_file_as_bytes("user://n03_false/s.obj")
	var on_ := FileAccess.get_file_as_bytes("user://n03_true/s.obj")
	ok(objs[true]["ok"] and og == on_ and og.size() > 1000, "OBJ (normals, indexed, transformed): %d bytes, byte identical, %d tris" % [on_.size(), objs[true]["tris"]])
	var of := func(nat: bool) -> Callable:
		return func():
			set_native(nat)
			ObjIO.export([{"name": "sph", "mesh": am, "xf": xf, "color": ObjIO.DEFAULT_COLOR}], "user://n03_t.obj")
	row("OBJ write, %d triangles" % objs[true]["tris"], med(of.call(false)), med(of.call(true)))
	set_native(true)
	print("n03: %d fail" % fails)
	quit()
