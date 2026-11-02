extends SceneTree
## godot --path . --position 4000,4000 -s tests/s233_test.gd     (ITEM 233 BIG PARTS: a ~270-body part drawn whole, shared replay shapes, a broad phase, one-pass counts; needs the CAD DLL)
## Found by the hall rematch (C:/Users/Nick/tools/kine_workers/hall_compare/kine2/difficulties.md).
## Bars:
##   1 DRAWN    a 300-body part: every body is drawn (triangles == 12 x bodies), the surfaces stay within the engine limit of 256, the last body (far right) is inside the
##              mesh box; the same through the background preview's finish_mesh; a 40-body part keeps one surface per body (unchanged). The old code drew 256.
##   2 SHARED   replaying a part step by step (the UI cache) keeps O(bodies) kernel shapes alive, not O(steps x bodies); inc_clear frees all of them; the cached
##              result equals a full replay (bodies, volumes, errors, box, counts, looks)
##   3 BROAD    PartFacts.contacts by the sweep == the all-pairs contacts (overlaps, touches, near, apart) on a random mix of overlapping, touching, near and far
##              boxes, and components() == the all-pairs union; on a sparse 267-body part it tests a small fraction of the 35 511 pairs
##   4 APPEND   an appended step on a cached 200-step part runs ONE step (Part.step_runs), result equal to the full replay; labels from the one-pass counts ==
##              labels from a replay per prefix, on a part with a pattern
const KCad := preload("res://scripts/kcad.gd")
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func grid_part(n: int, pitch: float, name := "big") -> Dictionary:
	var rec := Part.make(name)
	for k in n:
		Part.prim(rec, "box", {"x": (k % 17) * pitch, "y": 0.0, "z": (k / 17) * pitch, "w": 20.0, "h": 20.0, "d": 20.0, "name": "B%d" % k})
	return rec


func tris_of(mesh: ArrayMesh) -> int:
	var t := 0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var ix: Variant = arr[Mesh.ARRAY_INDEX]
		t += (ix as PackedInt32Array).size() / 3 if ix != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return t


func same_result(a: Dictionary, b: Dictionary) -> bool:
	return int(a["bodies"]) == int(b["bodies"]) and JSON.stringify(a["volumes"]) == JSON.stringify(b["volumes"]) and JSON.stringify(a["errors"]) == JSON.stringify(b["errors"]) \
		and a["aabb"] == b["aabb"] and JSON.stringify(a["counts"]) == JSON.stringify(b["counts"]) and JSON.stringify(a["body_looks"]) == JSON.stringify(b["body_looks"])


func rnd_part(n: int, seed_: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var rec := Part.make("rnd")
	for k in n:
		var w := rng.randf_range(5.0, 40.0)
		var h := rng.randf_range(5.0, 40.0)
		var d := rng.randf_range(5.0, 40.0)
		# positions on a 2.5 mm lattice so some faces touch exactly, some boxes overlap, some sit 2-20 mm apart, some are far
		Part.prim(rec, "box", {"x": snappedf(rng.randf_range(0.0, 260.0), 2.5), "y": snappedf(rng.randf_range(0.0, 260.0), 2.5), "z": snappedf(rng.randf_range(0.0, 260.0), 2.5), "w": w, "h": h, "d": d, "name": "R%d" % k})
	for k in 6:   # six exactly touching pairs (a shared face), far from the rest
		Part.prim(rec, "box", {"x": 400.0 + 60.0 * k, "y": 0.0, "z": 0.0, "w": 20.0, "h": 20.0, "d": 20.0, "name": "TA%d" % k})
		Part.prim(rec, "box", {"x": 420.0 + 60.0 * k, "y": 0.0, "z": 0.0, "w": 20.0, "h": 20.0, "d": 20.0, "name": "TB%d" % k})
	return rec


func _init() -> void:
	if not Part.available():
		print("FAIL: no KineCAD DLL, the parts cannot be built")
		quit(1)
		return
	# ------------------------------------------------------------------ 1 DRAWN
	var big := grid_part(299, 30.0)
	Part.prim(big, "box", {"x": 5000.0, "y": 0.0, "z": 0.0, "w": 90000.0, "h": 700.0, "d": 900.0, "name": "Compound wall"})   # body 300: a long wall, built LAST (the hall's)
	for k in [3, 120, 260]:
		(big["features"] as Array).append(Part.new_feature(big, "appear", {"body": k, "preset": "Custom", "color": [0.7, 0.1, 0.1]}))
	var r := Part.replay(big)
	var mesh: ArrayMesh = r["mesh"]
	ok(int(r["bodies"]) == 300, "1 the part has 300 bodies (%d)" % int(r["bodies"]))
	ok(tris_of(mesh) == 12 * 300, "1 DRAWN: %d triangles drawn, a box is 12: wanted %d (the old code drew 256 bodies = 3072)" % [tris_of(mesh), 12 * 300])
	ok(mesh.get_surface_count() <= 256 and (r["looks"] as Array).size() == mesh.get_surface_count(), "1 %d surfaces (<= 256), %d looks, one per surface" % [mesh.get_surface_count(), (r["looks"] as Array).size()])
	var wall_end: float = 5.0 + 90.0   # metres: x 5000 + w 90000 mm
	ok(mesh.get_aabb().end.x >= wall_end - 0.001, "1 the last body (the wall) is inside the drawn mesh: box ends at x %.3f m (wanted %.3f)" % [mesh.get_aabb().end.x, wall_end])
	var red_ok := false
	for lk in r["looks"]:
		if (lk["c"] as Color).is_equal_approx(Color(0.7, 0.1, 0.1)):
			red_ok = true
	ok(red_ok, "1 the painted bodies keep their own look on a surface")
	var small := Part.replay(grid_part(40, 30.0))
	ok((small["mesh"] as ArrayMesh).get_surface_count() == 40 and (small["surf_body"] as Array).size() == 40, "1 a 40-body part keeps one surface per body (%d), surf_body %d" % [(small["mesh"] as ArrayMesh).get_surface_count(), (small["surf_body"] as Array).size()])
	var rd := Part.replay(big, -1, {"defer_tess": true})   # the background preview: tessellate off the main thread, then finish_mesh
	var outs: Array = []
	outs.resize((rd["tess_ids"] as Array).size())
	Part.tessellate_job(rd["tess_ids"], outs, false)
	Part.finish_mesh(rd, outs)
	ok(rd["mesh"] != null and tris_of(rd["mesh"]) == 12 * 300 and (rd["mesh"] as ArrayMesh).get_surface_count() <= 256, "1 the background preview draws all 300 too: %d triangles" % tris_of(rd["mesh"]))
	Part.release_kept(rd["tess_ids"])
	# ------------------------------------------------------------------ 2 SHARED
	Part.inc_clear()
	var live0 := KCad.live_count()
	var grow: Dictionary = {}
	var t0 := Time.get_ticks_msec()
	for k in range(1, 151):
		grow = grid_part(k, 30.0)
		Part.replay(grow, -1, {"inc": true, "errors_only": true})
	var ms_grow := Time.get_ticks_msec() - t0
	var live1 := KCad.live_count() - live0
	ok(live1 <= 2 * 150 + 20, "2 SHARED: 150 appended steps leave %d kernel shapes alive (the cache shares bodies; the old deep copies held about 96 x 150 = 14 000)" % live1)
	var inc_full := Part.replay(grow, -1, {"inc": true})
	var plain := Part.replay(grow)
	ok(same_result(inc_full, plain), "2 the cached replay equals the full replay (bodies, volumes, errors, box, counts, looks); %d snapshots, %d ms for the 150 appends" % [Part.inc_cache.size(), ms_grow])
	Part.inc_clear()
	ok(KCad.live_count() == live0, "2 inc_clear frees every shape: live %d, before %d" % [KCad.live_count(), live0])
	# ------------------------------------------------------------------ 3 BROAD
	var pairs_ok := true
	var comp_ok := true
	var shown := ""
	for sd in [7, 11, 23]:
		var M := PartFacts.build(rnd_part(110, sd))
		var a := PartFacts.contacts(M)
		var b := PartFacts.contacts_all_pairs(M)
		var same := JSON.stringify(a) == JSON.stringify(b)
		pairs_ok = pairs_ok and same
		shown += " seed%d: ov %d tc %d nr %d apart %d%s;" % [sd, a["overlaps"].size(), a["touches"].size(), a["near"].size(), a["apart"], "" if same else " DIFFERS"]
		var par := range(M.n)
		for i in M.n:
			for j in range(i + 1, M.n):
				if M.box_gap(i, j) <= PartFacts.TOUCH_MM and M.gap(i, j, PartFacts.TOUCH_MM) <= PartFacts.TOUCH_MM:
					var ra: int = i
					while par[ra] != ra:
						ra = par[ra]
					var rb: int = j
					while par[rb] != rb:
						rb = par[rb]
					if ra != rb:
						par[maxi(ra, rb)] = mini(ra, rb)
		var groups := {}
		for i in M.n:
			var ri: int = i
			while par[ri] != ri:
				ri = par[ri]
			if not groups.has(ri):
				groups[ri] = []
			groups[ri].append(i)
		comp_ok = comp_ok and JSON.stringify(groups.values()) == JSON.stringify(M.components())
		M.release()
	ok(pairs_ok, "3 BROAD: sweep contacts == all-pairs contacts on random mixes:" + shown)
	ok(comp_ok, "3 components() by the sweep == the all-pairs union")
	var M2 := PartFacts.build(rnd_part(70, 5))
	var idx_ok := true
	var near_ok := true
	var checked := 0
	for i in range(0, M2.n, 3):
		for j in range(i + 1, M2.n, 5):
			var A := M2.tris(i)
			var B := M2.tris(j)
			var g1 := PartFacts.tri_gap(A, B, 40.0)
			var g2 := PartFacts.tri_gap(A, B, 40.0, {}, M2.index(i), M2.index(j))
			idx_ok = idx_ok and (g1 == g2 or (is_inf(g1) and is_inf(g2)))
			var reg := M2.box(j).grow(7.0)
			near_ok = near_ok and JSON.stringify(PartFacts._near_tris(A, reg)) == JSON.stringify(M2.index(i).near(reg))
			checked += 1
	ok(idx_ok and near_ok and checked > 100, "3 TRIANGLE INDEX: tri_gap and the near-triangle lists with the index == without, %d pairs" % checked)
	M2.release()
	var mixed := PartFacts.build(rnd_part(110, 7))
	var cc := PartFacts.contacts(mixed)
	ok(cc["overlaps"].size() > 3 and cc["touches"].size() > 0 and cc["near"].size() > 3, "3 the fixture has all three kinds of contact (ov %d, tc %d, nr %d)" % [cc["overlaps"].size(), cc["touches"].size(), cc["near"].size()])
	mixed.release()
	var sparse := PartFacts.build(grid_part(267, 60.0))
	var t1 := Time.get_ticks_msec()
	var cs := PartFacts.contacts(sparse)
	var ms_c := Time.get_ticks_msec() - t1
	var all := sparse.n * (sparse.n - 1) / 2
	ok(sparse.pairs_tested < all / 10, "3 sparse 267 bodies: %d full box tests of %d pairs (%d ms), near %d" % [sparse.pairs_tested, all, ms_c, cs["near"].size()])
	var cs2 := PartFacts.contacts_all_pairs(sparse)
	ok(JSON.stringify(cs) == JSON.stringify(cs2), "3 and equal to the all-pairs graph on it")
	sparse.release()
	# ------------------------------------------------------------------ 4 APPEND
	Part.inc_clear()
	var base := grid_part(200, 30.0)
	Part.replay(base, -1, {"inc": true, "errors_only": true})
	var more := grid_part(200, 30.0)
	Part.prim(more, "box", {"x": 9000.0, "name": "Appended", "w": 5.0, "h": 5.0, "d": 5.0})
	var s0 := Part.step_runs
	var ta := Time.get_ticks_msec()
	var ra := Part.replay(more, -1, {"inc": true, "errors_only": true})
	var ms_app := Time.get_ticks_msec() - ta
	var runs := Part.step_runs - s0
	ok(runs == 1, "4 APPEND: an appended step on a cached 200-step part runs %d step (%d ms)" % [runs, ms_app])
	var tf := Time.get_ticks_msec()
	var rf := Part.replay(more, -1, {"errors_only": true})
	ok(same_result(ra, rf) and int(ra["bodies"]) == 201, "4 and equals the full replay (%d ms): %d bodies, %d counts" % [Time.get_ticks_msec() - tf, int(ra["bodies"]), (ra["counts"] as Array).size()])
	Part.inc_clear()
	var rp := Part.make("bars")
	Part.prim(rp, "box", {"x": 10.0, "y": -2.0, "z": -2.0, "w": 40.0, "h": 4.0, "d": 4.0, "name": "Bar"})
	(rp["features"] as Array).append(Part.new_feature(rp, "pattern", {"body": 0, "kind": "circular", "count": 3, "axis": "z", "deg": 360.0, "op": "new", "name": "Ring of bars"}))
	Part.prim(rp, "box", {"x": 100.0, "name": "Post", "w": 5.0, "h": 5.0, "d": 5.0})
	var rr := Part.replay(rp, -1, {"keep": true, "errors_only": true, "inc": true})
	var l_fast := PartFacts.labels_of(rp, int(rr["bodies"]), rr["counts"])
	var l_slow := PartFacts.labels_of(rp, int(rr["bodies"]))
	ok(l_fast == l_slow and l_fast.size() >= 4, "4 labels from the one-pass counts == labels from a replay per prefix: %s" % str(l_fast))
	Part.release_kept(rr["ids"])
	Part.inc_clear()
	print("s233: %d fail%s" % [fails, "" if fails == 1 else "s"])
	quit(1 if fails > 0 else 0)
