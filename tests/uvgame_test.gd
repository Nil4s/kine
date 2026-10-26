extends SceneTree
## godot --path . -s tests/uvgame_test.gd     (ROADMAP_400 D15 one-click "game ready UVs", scripts/kmesh_uvpack.gd; part 5
## needs a window). The mannequin (assets/mannequin.glb, its mesh welded into a KMesh, moved by its nodes' transforms) has
## no seams: KMeshUVPack.game_ready cuts its own (auto_seams), unwraps by LSCM (D03) and packs (D04). Bars, written before
## measuring:
##   1 "1x2k" on the mannequin: ok; the reported px/cm equals an independent measure (sqrt(uv area / 3D area) * 2048 / 100
##     over the whole mesh) within 1%; no pixel covered by two islands at 1024 px; least gap between islands >= 8 px at
##     2048 (the default margin), >= 4 px to the border; every UV in 0..1; density spread across islands < 5%; packing
##     efficiency > 50%; the run takes < 30 s (printed)
##   2 "4x1k" on the mannequin: 4 tiles, each with islands; every face's "uv_tile" in 0..3 and its UVs in [tile, tile+1] x
##     [0, 1] (UDIM 1001-1004); per tile no overlap at 1024 px and >= 8 px gaps at 1024; ONE density across all tiles
##     (spread < 5%); px/cm reported at 1024 and checked as in 1; split "region": the islands of tile 0 sit higher on the
##     body than those of tile 3 (mean 3D centroid height); split "area": the tiles' 3D areas within 25% of each other
##   3 a 1 m cube cut into a cross net by hand (7 seams): game_ready keeps your seams (says "yours") -> 1 island
##   4 FIRST WRITTEN as "4x1k at 1024 and 1x2k at 2048 differ by > 5% (the instrument moves)": measured 10.01 vs 10.31
##     px/cm, and that is right, the bar was wrong: 4 x 1024^2 = 2048^2 pixels, the same budget, so the densities must
##     nearly agree. Now: they agree within 10% (the rest is what four tiles' margins and boxes cost), and the instrument
##     moves: the mannequin scaled x2 gets half the px/cm at 1x2k (within 2%)
##   5 THE APP: "Model: game ready UVs (4 x 1k)" from the mesh tools list runs on the model preview as ONE mesh undo step
##     ("Game ready UVs"), says the px/cm, shows the UV checker; Ctrl+Z gives back the mesh as it was (no tiles)

var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## pixels (px x px, centres) covered by triangles of two different islands; tile t takes u in [t, t+1] when tiles
func overlaps(m: KMesh, px: int, tile := -1) -> int:
	var d: PackedVector2Array = m.attr_data(KMeshUV.UV)
	var top := KMeshUVPack.islands(m)
	var isl: PackedInt32Array = top["island"]
	var own := PackedInt32Array()
	own.resize(px * px)
	own.fill(-1)
	var bad := 0
	var off := Vector2(maxi(tile, 0), 0)
	var td = m.attr_data(KMeshUVPack.TILE) if tile >= 0 and m.has_attr(KMeshUVPack.TILE) else null
	for f in m.face_count():
		if td != null and int(td[f]) != tile:
			continue
		var fp: PackedInt32Array = m.faces[f]
		var h0 := m.face_he0[f]
		for i in range(1, fp.size() - 1):
			var a := (d[h0] - off) * px
			var b := (d[h0 + i] - off) * px
			var c := (d[h0 + i + 1] - off) * px
			var lo := a.min(b).min(c)
			var hi := a.max(b).max(c)
			for y in range(maxi(int(floor(lo.y)), 0), mini(int(ceil(hi.y)), px)):
				for x in range(maxi(int(floor(lo.x)), 0), mini(int(ceil(hi.x)), px)):
					var p := Vector2(x + 0.5, y + 0.5)
					var w0 := (b - a).cross(p - a)
					var w1 := (c - b).cross(p - b)
					var w2 := (a - c).cross(p - c)
					if not ((w0 >= 0 and w1 >= 0 and w2 >= 0) or (w0 <= 0 and w1 <= 0 and w2 <= 0)):
						continue
					var k := y * px + x
					if own[k] == -1:
						own[k] = isl[f]
					elif own[k] != isl[f]:
						own[k] = -2
						bad += 1
	return bad


static func seg_dist(p1: Vector2, q1: Vector2, p2: Vector2, q2: Vector2) -> float:
	var a := Geometry2D.get_closest_points_between_segments(p1, q1, p2, q2)
	return (a[0] as Vector2).distance_to(a[1])


## {"gap": least distance between edges of two different islands, "edge": least distance from an island to its tile's
## border} in UV units; the tile per face from "uv_tile" when present
func gaps(m: KMesh) -> Dictionary:
	var d: PackedVector2Array = m.attr_data(KMeshUV.UV)
	var data := KMeshUVPack.island_data(m)
	var segs: Array = []   # per island PackedVector2Array of segment ends
	var bbs: Array = []
	var tl: Array = []
	var td = m.attr_data(KMeshUVPack.TILE) if m.has_attr(KMeshUVPack.TILE) else null
	var edge := INF
	var isl: PackedInt32Array = KMeshUVPack.islands(m)["island"]
	for r in data:
		var s := PackedVector2Array()
		var bb := Rect2(d[(r["corners"] as PackedInt32Array)[0]], Vector2.ZERO)
		var f0: int = (r["faces"] as PackedInt32Array)[0]
		var t := int(td[f0]) if td != null else 0
		for f in (r["faces"] as PackedInt32Array):
			var n := (m.faces[f] as PackedInt32Array).size()
			var h0 := m.face_he0[f]
			for i in n:
				var tw := m.he_twin[h0 + i]
				if tw == -1 or isl[m.he_face[tw]] != isl[f]:   # the island's outline (two separate islands are nearest there)
					s.append(d[h0 + i])
					s.append(d[h0 + (i + 1) % n])
				bb = bb.expand(d[h0 + i])
				var q := d[h0 + i] - Vector2(t, 0)
				edge = minf(edge, minf(minf(q.x, q.y), minf(1.0 - q.x, 1.0 - q.y)))
		segs.append(s)
		bbs.append(bb)
		tl.append(t)
	var gap := INF
	for i in data.size():
		for j in range(i + 1, data.size()):
			if tl[i] != tl[j]:
				continue
			var bi: Rect2 = bbs[i]
			var bj: Rect2 = bbs[j]
			if bi.grow(gap).intersects(bj) == false and gap < INF:
				continue
			var si: PackedVector2Array = segs[i]
			var sj: PackedVector2Array = segs[j]
			for a in range(0, si.size(), 2):
				for b in range(0, sj.size(), 2):
					gap = minf(gap, seg_dist(si[a], si[a + 1], sj[b], sj[b + 1]))
	return {"gap": gap, "edge": edge}


func spread(v: PackedFloat64Array) -> float:
	var lo := INF
	var hi := 0.0
	for x in v:
		lo = minf(lo, x)
		hi = maxf(hi, x)
	return hi / lo - 1.0


func in01(m: KMesh) -> bool:
	for q in m.attr_data(KMeshUV.UV):
		if q.x < -1e-9 or q.y < -1e-9 or q.x > 1.0 + 1e-9 or q.y > 1.0 + 1e-9:
			return false
	return true


## the whole mesh's px/cm: sqrt(total uv area / total 3D area) * px / 100
func px_cm(m: KMesh, px: int) -> float:
	var a3 := 0.0
	var au := 0.0
	for r in KMeshUVPack.island_data(m):
		a3 += float(r["a3"])
		au += float(r["auv"])
	return sqrt(au / a3) * px / 100.0


func mannequin() -> KMesh:
	var holder := Node3D.new()
	var mq := Overlays.mannequin(holder, StandardMaterial3D.new())
	var mi: MeshInstance3D = (mq[0] as Node3D).find_children("*", "MeshInstance3D", true, false)[0]
	var km := KMesh.new().from_array_mesh(mi.mesh, 0)
	var xf := Transform3D.IDENTITY
	var n: Node = mi
	while n != null and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	var vs := km.verts.duplicate()
	for i in vs.size():
		vs[i] = xf * vs[i]
	var fs: Array = []
	for f in km.faces:
		fs.append(f)
	holder.free()
	return KMesh.new().from_arrays(vs, fs)


func tile_check(m: KMesh) -> bool:
	if not m.has_attr(KMeshUVPack.TILE):
		return false
	var td = m.attr_data(KMeshUVPack.TILE)
	var d: PackedVector2Array = m.attr_data(KMeshUV.UV)
	for f in m.face_count():
		var t := int(td[f])
		if t < 0 or t > 3 or float(td[f]) != float(t):
			return false
		for i in (m.faces[f] as PackedInt32Array).size():
			var q := d[m.face_he0[f] + i]
			if q.x < t - 1e-9 or q.x > t + 1 + 1e-9 or q.y < -1e-9 or q.y > 1 + 1e-9:
				return false
	return true


func _init() -> void:
	var m := mannequin()
	var bb := AABB(m.verts[0], Vector3.ZERO)
	for p in m.verts:
		bb = bb.expand(p)
	print("mannequin: %d verts, %d faces, %.2f m tall" % [m.vert_count(), m.face_count(), bb.size.y])
	# 1
	var r := KMeshUVPack.game_ready(m, "1x2k")
	print("1x2k: ", r)
	var st := KMeshUV.stretch(m)
	print("  LSCM: angle mean %.3f, flipped faces %d" % [st["angle_mean"], st["flipped_faces"]])
	var pc := px_cm(m, 2048)
	var ov := overlaps(m, 1024)
	var gp := gaps(m)
	var sp := spread(KMeshUVPack.densities(m, 2048))
	print("bar 1: seams %s, %d islands, %.3f px/cm (measured %.3f), overlaps %d px, gap %.2f px, border %.2f px at 2048, spread %.3f%%, efficiency %.1f%%, %.0f ms (unwrap %.0f)" % [
		r["seams"], r["islands"], r["px_per_cm"], pc, ov, gp["gap"] * 2048, gp["edge"] * 2048, sp * 100.0, r["efficiency"] * 100.0, r["ms"] + r["unwrap_ms"], r["unwrap_ms"]])
	ok(r["ok"] and absf(r["px_per_cm"] / pc - 1.0) < 0.01, "bar 1: 1x2k reports %.2f px/cm, measured %.2f" % [r["px_per_cm"], pc])
	ok(ov == 0 and gp["gap"] * 2048 >= 8.0 - 1e-3 and gp["edge"] * 2048 >= 4.0 - 1e-3 and in01(m), "bar 1: no overlap, margin 8 px at 2048, inside 0..1")
	ok(sp < 0.05, "bar 1: density spread %.3f%% < 5%%" % (sp * 100.0))
	ok(r["efficiency"] > 0.5, "bar 1: packing efficiency %.1f%% > 50%%" % (r["efficiency"] * 100.0))
	ok(r["ms"] + r["unwrap_ms"] < 30000.0, "bar 1: the run takes %.1f s < 30 s" % ((r["ms"] + r["unwrap_ms"]) / 1000.0))
	var p2k: float = r["px_per_cm"]
	# 2
	for how in ["region", "area"]:
		var m4 := mannequin()
		var r4 := KMeshUVPack.game_ready(m4, "4x1k", {"split": how})
		print("4x1k %s: %d islands, %.3f px/cm, tile efficiency %s, %.0f ms" % [how, r4["islands"], r4["px_per_cm"], r4["tile_eff"], r4["ms"]])
		var td = m4.attr_data(KMeshUVPack.TILE)
		var data := KMeshUVPack.island_data(m4)
		var cnt := [0, 0, 0, 0]
		var hy := [0.0, 0.0, 0.0, 0.0]
		var ar := [0.0, 0.0, 0.0, 0.0]
		for d in data:
			var t := int(td[(d["faces"] as PackedInt32Array)[0]])
			cnt[t] += 1
			hy[t] += (d["c3"] as Vector3).y
			ar[t] += float(d["a3"])
		var ovs := 0
		for t in 4:
			ovs += overlaps(m4, 1024, t)
		var g4 := gaps(m4)
		var sp4 := spread(KMeshUVPack.densities(m4, 1024))
		var pc4 := px_cm(m4, 1024)
		print("  islands per tile %s, 3D area per tile %s, mean height per tile %s; overlaps %d, gap %.2f px, border %.2f px, spread %.3f%%, measured %.3f px/cm" % [
			cnt, ar.map(func(a): return snappedf(a, 0.001)), [0, 1, 2, 3].map(func(t): return snappedf(hy[t] / maxi(cnt[t], 1), 0.001)), ovs, g4["gap"] * 1024, g4["edge"] * 1024, sp4 * 100.0, pc4])
		ok(r4["ok"] and int(r4["tiles"]) == 4 and cnt.min() > 0 and tile_check(m4), "bar 2 %s: 4 tiles, each with islands, every UV in its tile" % how)
		ok(ovs == 0 and g4["gap"] * 1024 >= 8.0 - 1e-3 and sp4 < 0.05 and absf(r4["px_per_cm"] / pc4 - 1.0) < 0.01, "bar 2 %s: no overlap per tile, 8 px gaps, one density (%.3f%%), %.2f px/cm checked" % [how, sp4 * 100.0, r4["px_per_cm"]])
		if how == "region":
			ok(hy[0] / cnt[0] > hy[3] / cnt[3], "bar 2 region: tile 0 sits higher on the body than tile 3")
			ok(absf(r4["px_per_cm"] / p2k - 1.0) < 0.1, "bar 4: 4x1k (%.2f px/cm) and 1x2k (%.2f), the same pixel budget, agree within 10%%" % [r4["px_per_cm"], p2k])
			var big := mannequin()
			var vs := big.verts.duplicate()
			for i in vs.size():
				vs[i] *= 2.0
			var fs: Array = []
			for f in big.faces:
				fs.append(f)
			big = KMesh.new().from_arrays(vs, fs)
			var rb := KMeshUVPack.game_ready(big, "1x2k")
			print("bar 4: mannequin x2: %.3f px/cm (x1: %.3f, ratio %.4f)" % [rb["px_per_cm"], p2k, rb["px_per_cm"] / p2k])
			ok(absf(rb["px_per_cm"] / p2k - 0.5) < 0.01, "bar 4: twice the size, half the px/cm (ratio %.4f)" % (rb["px_per_cm"] / p2k))
		else:
			ok(ar.max() / ar.min() < 1.25, "bar 2 area: the tiles' 3D areas within 25%% (%.3f)" % (ar.max() / ar.min()))
	# 3
	var c := KMeshView.make_cube(1.0, 1)
	var cut := []
	for e in c.edges():
		var mid := (c.verts[e.x] + c.verts[e.y]) * 0.5
		# cross net: one vertical edge (-x -z) opens the ring of 4 sides; top and bottom stay on the front (+z) edge only
		if absf(mid.y) < 1e-6 and mid.x < 0 and mid.z < 0:
			cut.append(e)
		elif absf(mid.y) > 0.49 and mid.z < 0.49:
			cut.append(e)
	KMeshUV.mark_seams(c, cut)
	var rc := KMeshUVPack.game_ready(c, "1x2k")
	print("bar 3: cube with %d hand seams -> seams %s, %d islands" % [cut.size(), rc["seams"], rc["islands"]])
	ok(rc["seams"] == "yours" and int(rc["islands"]) == 1, "bar 3: your seams kept, 1 island")
	await app()
	print("uvgame: %d failures" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)


func app() -> void:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await idle(6)
	main.tour_step = -1
	if main.ui_tour != null:
		main.ui_tour.visible = false
	main._kmesh_edit_start()
	await idle(3)
	var ui: KMeshEditUI = main.kmed
	var had := ui.mesh.has_attr(KMeshUV.UV)
	var n0: int = ui.undo.steps.size()
	var line := {}
	for t in MeshTools.TOOLS:
		if t["label"] == "Model: game ready UVs (4 x 1k)":
			line = t
	ok(not line.is_empty(), "bar 5: the mesh tools line is there")
	MeshTools.run(line, main)
	await idle(2)
	var said := String(main.ui_status.text)
	print("bar 5: said \"%s\"" % said)
	var steps: Array = ui.undo.steps
	ok(steps.size() == n0 + 1 and String(steps[-1]["label"]) == "Game ready UVs" and said.contains("px/cm") and said.contains("4 x 1k") and ui.view.shading == "uv_checker",
		"bar 5: one undo step \"Game ready UVs\", px/cm said, checker shown")
	ok(ui.mesh.has_attr(KMeshUV.UV) and tile_check(ui.mesh), "bar 5: the cube has UVs in its 4 tiles")
	ui.undo.undo()
	ok(ui.mesh.has_attr(KMeshUV.UV) == had and not ui.mesh.has_attr(KMeshUVPack.TILE), "bar 5: Ctrl+Z gives back the mesh as it was (uv %s, no tiles)" % had)
