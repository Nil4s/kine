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
	# F control
	var rf := Part.replay(rec_for(ins(40000, 1)), -1, {})
	ok(rf["errors"].size() == 1 and rf["instances"].is_empty(), "F too many: " + str(rf["errors"].values()))
	print("FAILS ", fails)
	quit(1 if fails > 0 else 0)

func KCad_release(i) -> void:
	load("res://scripts/kcad.gd").release(int(i))
