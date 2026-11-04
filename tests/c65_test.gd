extends SceneTree
## godot --headless --path . -s tests/c65_test.gd     (C65: over 256 bodies the look-merge key held the body NAME, so later bodies took the wrong material)
## 600 named boxes in 6 materials on a grid. Bars:
##   A  every body is drawn (600 x 12 triangles) and the surfaces stay within 256
##   B  every body's surface material colour == the colour of its own material (600 of 600)
##   C  surf_ranges lists every body exactly once (picking / highlight keep working)
##   D  the surface count is 6 (grouped by material only), no cap note
##   E  CONTROL: the old key (look with its name) gives 600 distinct keys, the new key 6
##   F  more distinct materials than surfaces: res["surface_cap"] says so in words
var fails := 0
const N := 600
const COLS := [[0.9, 0.1, 0.1], [0.1, 0.9, 0.1], [0.1, 0.1, 0.9], [0.9, 0.9, 0.1], [0.1, 0.9, 0.9], [0.9, 0.1, 0.9]]


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func rec_of(n: int, ncol: int) -> Dictionary:
	var rec := Part.make("c65")
	for k in n:
		Part.prim(rec, "box", {"x": (k % 25) * 30.0, "y": 0.0, "z": (k / 25) * 30.0, "w": 20.0, "h": 20.0, "d": 20.0, "name": "B%d" % k})
	for k in n:
		var c: Array = COLS[k % 6] if ncol <= 6 else [float(k % 251) / 255.0, float((k / 251) % 251) / 255.0, 0.5]
		(rec["features"] as Array).append(Part.new_feature(rec, "appear", {"body": k, "preset": "Custom", "color": c}))
		(rec["features"] as Array).append(Part.new_feature(rec, "bname", {"name": "Name %d" % k, "body": k, "called": "Box number %d" % k}))
	return rec


func _init() -> void:
	var rec := rec_of(N, 6)
	var res := Part.replay(rec)
	var mesh: ArrayMesh = res["mesh"]
	var tris := 0
	for s in mesh.get_surface_count():
		tris += (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	ok(res["bodies"] == N and tris == N * 12 and mesh.get_surface_count() <= 256, "A drawn: %d bodies, %d tris, %d surfaces" % [res["bodies"], tris, mesh.get_surface_count()])
	Part.paint(mesh, res["looks"])
	var seen := {}
	var right := 0
	for s in res["surf_ranges"].size():
		var mt: StandardMaterial3D = mesh.surface_get_material(s)
		for r in res["surf_ranges"][s]:
			var b := int(r[0])
			seen[b] = int(seen.get(b, 0)) + 1
			var want: Array = COLS[b % 6]
			if absf(mt.albedo_color.r - want[0]) < 0.01 and absf(mt.albedo_color.g - want[1]) < 0.01 and absf(mt.albedo_color.b - want[2]) < 0.01:
				right += 1
	ok(right == N, "B own material: %d of %d" % [right, N])
	var once := seen.size() == N
	for b in seen:
		once = once and seen[b] == 1
	ok(once, "C every body once in surf_ranges (%d)" % seen.size())
	ok(mesh.get_surface_count() == 6 and not res.has("surface_cap"), "D surfaces = %d, cap note '%s'" % [mesh.get_surface_count(), res.get("surface_cap", "")])
	var olds := {}
	var news := {}
	for l in res["body_looks"] if res.has("body_looks") else []:
		olds[JSON.stringify(l)] = 1
		news[Part.merge_key(l)] = 1
	ok(olds.size() == N and news.size() == 6, "E control: old key %d distinct, new key %d" % [olds.size(), news.size()])
	var r2 := Part.replay(rec_of(300, 300))
	ok(String(r2.get("surface_cap", "")) != "", "F cap said: '%s'" % r2.get("surface_cap", ""))
	print("c65: ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(fails)
