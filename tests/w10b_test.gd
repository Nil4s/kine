## godot --headless --path . -s tests/w10b_test.gd   (W10b: the app's piece counter _lumps counts by shared faces, not shared vertices)
## BARS (written before the run): two boxes touching along an edge: _lumps == 2; face-touching (joined) boxes: 1; a box alone: 1;
## a half-face contact (small box on a big one's face): 1; two boxes touching at one corner: 2; two boxes with a gap: 2.
## Control: the OLD rule (union of triangle vertices) reads the edge pair as 1, so the bar can fail.
extends SceneTree
const KCad := preload("res://scripts/kcad.gd")
const EP := preload("res://scripts/easy_part_base.gd")
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func bx(sx: float, sy: float, sz: float, x: float, y: float, z: float) -> int:
	return KCad.translate(KCad.box(sx, sy, sz), Vector3(x, y, z))


func lumps(id: int, ep: Object) -> int:
	return ep._lumps({"mesh": KCad.tessellate(id, 0.001)})


## the old vertex-weld rule, for the control
func old_lumps(id: int) -> int:
	var m: ArrayMesh = KCad.tessellate(id, 0.001)
	var par := {}
	var f := func(k):
		while par[k] != k:
			k = par[k]
		return k
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var key := func(i): return Vector3i(roundi(vs[i].x * 1e5), roundi(vs[i].y * 1e5), roundi(vs[i].z * 1e5))
		for i in vs.size():
			par[key.call(i)] = key.call(i)
		for t in range(0, ix.size() - 2, 3):
			for k in [1, 2]:
				var ra = f.call(key.call(ix[t]))
				var rb = f.call(key.call(ix[t + k]))
				if ra != rb:
					par[ra] = rb
	var roots := {}
	for k in par:
		roots[f.call(k)] = true
	return roots.size()


func _init() -> void:
	if not KCad.available():
		print("SKIP no KineCAD DLL")
		print("w10b: 0 fail")
		quit(0)
		return
	var ep = EP.new()
	var a := bx(0.01, 0.01, 0.01, 0, 0, 0)
	var edge := KCad.union(a, bx(0.01, 0.01, 0.01, 0.01, 0.01, 0))
	var face := KCad.union(bx(0.01, 0.01, 0.01, 0, 0, 0), bx(0.01, 0.01, 0.01, 0.01, 0, 0))
	var half := KCad.union(bx(0.02, 0.01, 0.02, 0, 0, 0), bx(0.01, 0.01, 0.01, 0.0, 0.01, 0))
	var corner := KCad.union(bx(0.01, 0.01, 0.01, 0, 0, 0), bx(0.01, 0.01, 0.01, 0.01, 0.01, 0.01))
	var gap := KCad.union(bx(0.01, 0.01, 0.01, 0, 0, 0), bx(0.01, 0.01, 0.01, 0.03, 0, 0))
	ok(lumps(bx(0.01, 0.01, 0.01, 0, 0, 0), ep) == 1, "a box alone: 1")
	ok(lumps(edge, ep) == 2, "edge-touching boxes: 2 (got %d)" % lumps(edge, ep))
	ok(lumps(face, ep) == 1, "face-touching joined boxes: 1 (got %d)" % lumps(face, ep))
	ok(lumps(half, ep) == 1, "small box on part of a big face: 1 (got %d)" % lumps(half, ep))
	ok(lumps(corner, ep) == 2, "corner-touching boxes: 2 (got %d)" % lumps(corner, ep))
	ok(lumps(gap, ep) == 2, "boxes with a gap: 2 (got %d)" % lumps(gap, ep))
	ok(old_lumps(edge) == 1, "control: the old vertex rule reads the edge pair as 1 (got %d)" % old_lumps(edge))
	print("w10b: %d fail" % fails)
	quit(1 if fails > 0 else 0)
