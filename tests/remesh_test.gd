extends SceneTree
## M1 voxel remesh (scripts/kmesh_voxel_remesh.gd; AnyGrip.MeshField.build_banded). Bars with real numbers:
## godot --headless --path . -s tests/remesh_test.gd
##   1 a 10 cm UV sphere at 1 cm voxels: volume within 2 % of the input's own volume
##   2 a closed torus (R 12 cm, tube radius 4 cm) at 1 cm: volume within 2 %
##   3 a block ring (genus 1: a 7 cm square section bent round R 12 cm, a cube with a handle) at 1 cm: volume within 2 %
##   4 each output is closed and manifold: no holes, no non-manifold edges (KMeshValidate.report, is_manifold)
##   5 the sphere at 1 cm: quad count within 10 % of 1.5 * area / voxel^2 (the surface-net estimate: one quad per grid
##     edge the surface crosses; a plane crosses (|nx| + |ny| + |nz|) / h^2 edges per unit area, averaged over directions = 1.5)
##   6 the sculpt's own sphere (30 cm, 24 splits) at KMeshSculptUI.REMESH_VOXEL: quad count within 10 % of the same estimate
##   7 an open mesh (one quad removed) is refused and says "hole"; a voxel of 0 is refused
##   8 apply() in place: undo restores the old vert and face counts; redo gives the remeshed counts again
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## a mesh's signed volume and surface area (divergence theorem; fan triangles)
func measure(m: KMesh) -> Vector2:
	var vol := 0.0
	var area := 0.0
	for f in m.faces:
		var fa := f as PackedInt32Array
		for k in range(1, fa.size() - 1):
			var a := m.verts[fa[0]]
			var b := m.verts[fa[k]]
			var c := m.verts[fa[k + 1]]
			vol += a.dot(b.cross(c)) / 6.0
			area += (b - a).cross(c - a).length() * 0.5
	return Vector2(vol, area)


## the faces wind outward when the signed volume is positive; reverse them all if not
func orient(m: KMesh) -> KMesh:
	if measure(m).x < 0.0:
		for i in m.faces.size():
			var fa := m.faces[i] as PackedInt32Array
			fa.reverse()
			m.faces[i] = fa
	return m


func uv_sphere(r: float, seg: int, rings: int) -> KMesh:
	var v := PackedVector3Array()
	for ri in range(1, rings):
		var th := PI * ri / rings
		for s in seg:
			var ph := TAU * s / seg
			v.append(Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph)) * r)
	var top := v.size()
	v.append(Vector3(0, r, 0))
	var bot := v.size()
	v.append(Vector3(0, -r, 0))
	var f := []
	for ri in range(rings - 2):
		for s in seg:
			var a := ri * seg + s
			var b := ri * seg + (s + 1) % seg
			var c := (ri + 1) * seg + (s + 1) % seg
			var d := (ri + 1) * seg + s
			f.append(PackedInt32Array([a, d, c, b]))
	for s in seg:
		f.append(PackedInt32Array([top, s, (s + 1) % seg]))
		f.append(PackedInt32Array([bot, (rings - 2) * seg + (s + 1) % seg, (rings - 2) * seg + s]))
	return orient(KMesh.new().from_arrays(v, f))


func torus(R: float, r: float, nu: int, nv: int) -> KMesh:
	var v := PackedVector3Array()
	for i in nu:
		var u := TAU * i / nu
		for j in nv:
			var w := TAU * j / nv
			var rr := R + r * cos(w)
			v.append(Vector3(rr * cos(u), r * sin(w), rr * sin(u)))
	var f := []
	for i in nu:
		for j in nv:
			var a := i * nv + j
			var b := i * nv + (j + 1) % nv
			var c := ((i + 1) % nu) * nv + (j + 1) % nv
			var d := ((i + 1) % nu) * nv + j
			f.append(PackedInt32Array([a, d, c, b]))
	return orient(KMesh.new().from_arrays(v, f))


## a square-section ring: the section is a square of side 2h, its centre on a circle of radius R in the xz plane
func block_ring(R: float, h: float, nu: int) -> KMesh:
	var v := PackedVector3Array()
	var corners := [Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)]
	for i in nu:
		var u := TAU * i / nu
		var radial := Vector3(cos(u), 0, sin(u))
		var centre := radial * R
		for c in corners:
			v.append(centre + radial * c.x + Vector3.UP * c.y)
	var f := []
	for i in nu:
		var i2 := (i + 1) % nu
		for k in 4:
			var k2 := (k + 1) % 4
			f.append(PackedInt32Array([i * 4 + k, i * 4 + k2, i2 * 4 + k2, i2 * 4 + k]))
	return orient(KMesh.new().from_arrays(v, f))


func _init() -> void:
	var sphere := uv_sphere(0.1, 48, 24)
	var torus_m := torus(0.12, 0.04, 48, 24)
	var ring := block_ring(0.12, 0.035, 48)
	var names := ["sphere", "torus", "block ring"]
	var shapes := [sphere, torus_m, ring]
	for n in shapes.size():
		var m: KMesh = shapes[n]
		var inm := measure(m)
		var r: Dictionary = KMeshVoxelRemesh.remesh(m, 0.01)
		ok(r["ok"], "%s: remesh at 1 cm ran (%s)" % [names[n], str(r.get("why", ""))])
		if not r["ok"]:
			continue
		var out: KMesh = r["mesh"]
		var outm := measure(out)
		var err := absf(outm.x - inm.x) / absf(inm.x)
		var rep := KMeshValidate.report(out)
		var kinds := (rep["problems"] as Array).map(func(p): return p["kind"])
		print("     %s: input %.6f m3 (%d faces), output %.6f m3 (%d quads, %d voxels, cell %.4f m)" % [
			names[n], inm.x, m.faces.size(), outm.x, out.faces.size(), r["voxels"], r["cell"]])
		ok(err <= 0.02, "%s: volume within 2 %% of the input (error %.3f %%)" % [names[n], err * 100.0])
		ok(out.is_closed() and out.is_manifold() and not kinds.has("non_manifold") and not kinds.has("holes"),
			"%s: closed and manifold (report kinds %s)" % [names[n], str(kinds)])
		if n == 0:
			var est := 1.5 * inm.y / (0.01 * 0.01)
			var dev := absf(out.faces.size() - est) / est
			ok(dev <= 0.10, "sphere: %d quads, estimate %.0f, off by %.2f %%" % [out.faces.size(), est, dev * 100.0])
	var sc := KMeshSculptUI.make_sphere()
	var rs: Dictionary = KMeshVoxelRemesh.remesh(sc, KMeshSculptUI.REMESH_VOXEL)
	ok(rs["ok"], "sculpt sphere: remesh at %.1f cm ran" % (KMeshSculptUI.REMESH_VOXEL * 100.0))
	if rs["ok"]:
		var sarea := measure(sc).y
		var sest := 1.5 * sarea / (KMeshSculptUI.REMESH_VOXEL * KMeshSculptUI.REMESH_VOXEL)
		var sq: int = (rs["mesh"] as KMesh).faces.size()
		var sdev := absf(sq - sest) / sest
		ok(sdev <= 0.10, "sculpt sphere: %d quads, estimate %.0f, off by %.2f %%" % [sq, sest, sdev * 100.0])
	var open := uv_sphere(0.1, 48, 24)
	open.faces.remove_at(0)
	open.rebuild()
	var ro: Dictionary = KMeshVoxelRemesh.remesh(open, 0.01)
	ok(not ro["ok"] and String(ro["why"]).contains("hole"), "open mesh refused: \"%s\"" % str(ro.get("why", "")))
	var r0: Dictionary = KMeshVoxelRemesh.remesh(sphere, 0.0)
	ok(not r0["ok"], "voxel 0 refused: \"%s\"" % str(r0.get("why", "")))
	# (8) in place with undo: the sculpt's path
	var m8 := uv_sphere(0.1, 48, 24)
	var v0 := m8.verts.size()
	var f0 := m8.faces.size()
	var undo := KMeshUndo.new()
	var ra: Dictionary = KMeshVoxelRemesh.apply(m8, 0.01, undo)
	var v1 := m8.verts.size()
	var f1 := m8.faces.size()
	ok(ra["ok"] and v1 != v0 and f1 > 0, "apply: remeshed in place (%d verts / %d faces -> %d / %d)" % [v0, f0, v1, f1])
	undo.undo()
	ok(m8.verts.size() == v0 and m8.faces.size() == f0, "undo restores the counts (%d / %d)" % [m8.verts.size(), m8.faces.size()])
	undo.redo()
	ok(m8.verts.size() == v1 and m8.faces.size() == f1, "redo gives the remesh again (%d / %d)" % [m8.verts.size(), m8.faces.size()])
	print("remesh: %d fails" % fails)
	quit(1 if fails > 0 else 0)
