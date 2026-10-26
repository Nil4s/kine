extends SceneTree
## godot --headless --path . -s tests/build_test.gd     (BUILD mode phase 1 skeleton; scripts/build/building.gd, docs/BUILD_PLAN.md)
## Bars, written before measuring (a 4 x 3 m room, outer sizes, 2.7 m walls 0.2 m thick, floor slab 0.2 m):
##   1 CLOSED: the walls mesh has 0 boundary edges and is manifold
##   2 VOLUME: the walls' volume is within 1% of the analytic (4 x 3 - 3.6 x 2.6) x 2.7 = 7.128 m3
##   3 DOOR: a 0.9 x 2.1 m door on the front wall removes exactly its volume (0.9 x 2.1 x 0.2 = 0.378 m3, within 1e-6), the
##     mesh stays closed and manifold; anti-vacuity: the volume did change
##   4 WHOLE: walls + floor is one closed mesh of volume walls + 4 x 3 x 0.2
##   5 FILE: the scene's "building" round-trips (to_dict -> JSON -> from_dict -> to_dict: the same entry; the rebuilt mesh
##     has the same volume and vertex count); a scene with no building writes no "building" key
##   6 NAMED NUMBER: wall_height 2.7 -> 3.0 in params and the walls follow (volume = 2.64 x 3.0 - 0.378)
##   7 COLLISION: the collision boxes' volume = the mesh's; the doorway's middle is in no box, the wall beside it is in one
##   (phase 1d, bars 9-13, written before measuring; all exact to 1e-5: the mesh verts are float32, measured 2e-6 of rounding)
##   9 ROOF: gable / flat / shed over a 4 x 3 room, overhang 0.45: the roof solid alone is closed + manifold and its volume is the analytic
##     prism (gable: span x rise / 2 x length, shed: the trapezoid, flat: the slab); the house with the roof is closed and its volume =
##     house + roof; overhang param 0 is closed too; the roof is in the file only when there is one
##   10 FLOORS: + Floor: 2 floors closed, volume = ground floor + upper walls + slab - the slab's overlap with the walls below; floor_height 3.0 leaves
##     no gap (the slab reaches down); remove_top_floor gives one floor back; the slabs' tops are at y 0 and floor_height
##   11 WALL: an interior wall (6 x 4 room, axis z at x = 3) adds exactly its volume, stays closed; a door in it removes exactly 0.9 x 2.1 x 0.1
##     and is open in the collision; the same wall on x
##   12 ANCHORS: "front door" at the opening's middle at floor level, pointing out (-Z); a door on an interior wall is "inner door"; two front doors are numbered
##   13 FILE / MIRROR: floors, interior walls and the roof round-trip through the scene file; mirror twice = the original, mirrored volume equal
##   (phase 1f, bars 14-17, written before measuring; exact to 1e-5 for one piece, 1e-4 for a whole house: its float32 vertices sum ~2e-5 of rounding at 40 m3)
##   14 PIECES: each of the 9 kinds alone is ONE closed manifold solid whose volume is the analytic one (stairs: w x t x r x sum(k) over the
##     treads of an auto count from a 0.18 m riser; L stairs the same with a landing; table / bench / fence the union of their boxes; crate /
##     pillar / platform a box; ramp w x d x h / 2); rotated by 90 degrees the volume is the same and the footprint turns
##   15 STAIRWELL: stairs on floor 1 of a 2-floor house cut the upper slab: the house (walls + floors) loses exactly area x slab thickness
##     (straight and L), stays closed; with no floor above there is no hole; the stairs themselves are in the mesh
##   16 FILE: pieces round-trip (record, mesh volume), mirror twice = the original, the mirrored house has the same volume, a bad piece is dropped
##   17 COLLISION: a crate is a box with its top as a support; the stairs are a RAMP: a point on its slope is on a surface (surface_below),
##     the slope meets the upper floor's top, a point inside a step is inside the solid, the hole is open in the floor's collision
##   8 MIRROR twice = the original record, the mirrored house has the same volume (within 1e-5 m3: its verts are float32
##     and sit 4 m from the origin, measured 2e-6 of rounding); a record from a newer version is kept whole (read only)
var fails := 0
func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func vol(m: KMesh) -> float:
	return KMeshValidate._volume(m)


func in_boxes(boxes: Array, p: Vector3) -> bool:
	for bx in boxes:
		var l: Vector3 = (bx["xf"] as Transform3D).affine_inverse() * p
		var h: Vector3 = bx["half"]
		if absf(l.x) < h.x and absf(l.y) < h.y and absf(l.z) < h.z:
			return true
	return false


func _init() -> void:
	var b := Building.make("Bay house")
	var r := Building.add_room(b, 0.0, 0.0, 4.0, 3.0)
	var walls := Building.to_kmesh(b, ["wall"])
	ok(walls.boundary_edge_count() == 0 and walls.is_manifold() and walls.face_count() > 0,
		"1 walls closed: %d boundary edges, manifold %s, %d faces %d verts" % [walls.boundary_edge_count(), walls.is_manifold(), walls.face_count(), walls.vert_count()])
	var analytic := (4.0 * 3.0 - 3.6 * 2.6) * 2.7
	var v0 := vol(walls)
	ok(absf(v0 - analytic) <= 0.01 * analytic, "2 wall volume %.6f m3 vs analytic %.6f (%.4f%%)" % [v0, analytic, 100.0 * absf(v0 - analytic) / analytic])

	var door := Building.add_opening(b, r, "front", "door", 0.0)
	var wd := Building.to_kmesh(b, ["wall"])
	var v1 := vol(wd)
	var cut := 0.9 * 2.1 * 0.2
	ok(door != "" and absf((v0 - v1) - cut) < 1e-6 and wd.boundary_edge_count() == 0 and wd.is_manifold() and v0 - v1 > 0.3,
		"3 the door removed %.6f m3 (its own %.6f), closed %s (%d boundary), manifold %s" % [v0 - v1, cut, wd.is_closed(), wd.boundary_edge_count(), wd.is_manifold()])

	var whole := Building.to_kmesh(b)
	var vw := vol(whole)
	ok(whole.boundary_edge_count() == 0 and whole.is_manifold() and absf(vw - (v1 + 4.0 * 3.0 * 0.2)) < 1e-6,
		"4 walls + floor closed (%d boundary), volume %.6f = %.6f + %.6f" % [whole.boundary_edge_count(), vw, v1, 4.0 * 3.0 * 0.2])

	var S := Scene.new()
	var B := Body.new()
	ok(not S.to_dict(B, false).has("building"), "5a a scene with no building writes no \"building\"")
	S.building = b
	var d: Dictionary = JSON.parse_string(JSON.stringify(S.to_dict(B, false)))
	var S2 := Scene.new()
	S2.from_dict(d)
	var d2: Dictionary = JSON.parse_string(JSON.stringify(S2.to_dict(B, false)))
	var back := Building.to_kmesh(S2.building)
	ok(d.has("building") and JSON.stringify(d2["building"]) == JSON.stringify(d["building"]) and absf(vol(back) - vw) < 1e-6 and back.vert_count() == whole.vert_count(),
		"5b round trip: same entry %s, volume %.6f vs %.6f, verts %d vs %d" % [JSON.stringify(d2.get("building")) == JSON.stringify(d.get("building")), vol(back), vw, back.vert_count(), whole.vert_count()])
	print("  file entry: ", JSON.stringify(d.get("building")))

	S2.building["params"]["wall_height"] = 3.0
	var v3 := vol(Building.to_kmesh(S2.building, ["wall"]))
	var want3 := (4.0 * 3.0 - 3.6 * 2.6) * 3.0 - cut
	ok(absf(v3 - want3) < 1e-6, "6 wall_height 3.0: walls %.6f m3 (want %.6f)" % [v3, want3])

	var cb := Building.collision_boxes(b)
	var cv := 0.0
	for bx in cb:
		var h: Vector3 = bx["half"]
		cv += 8.0 * h.x * h.y * h.z
	var mid_door := Vector3(2.0, 1.0, 0.1)
	var wall_pt := Vector3(1.0, 1.0, 0.1)
	ok(absf(cv - vw) < 1e-6 and not in_boxes(cb, mid_door) and in_boxes(cb, wall_pt),
		"7 collision: %d boxes, volume %.6f vs mesh %.6f, doorway open %s, wall solid %s" % [cb.size(), cv, vw, not in_boxes(cb, mid_door), in_boxes(cb, wall_pt)])

	var f := Building.to_file(b)
	var m2 := Building.mirror_file(Building.mirror_file(f))
	var mv := vol(Building.to_kmesh(Building.from_file(Building.mirror_file(f))))
	var fut := {"version": Building.VERSION + 1, "name": "from the future", "zones": [1, 2, 3]}
	var kept := Building.to_file(Building.from_file(fut))
	ok(JSON.stringify(m2) == JSON.stringify(f) and absf(mv - vw) < 1e-5 and JSON.stringify(kept) == JSON.stringify(fut) and Building.from_file(fut)["readonly"],
		"8 mirror twice = original %s, mirrored volume %.6f; newer version kept whole %s" % [JSON.stringify(m2) == JSON.stringify(f), mv, JSON.stringify(kept) == JSON.stringify(fut)])

	# ---- phase 1d
	var b9 := Building.make("Roofed")
	Building.add_room(b9, 0.0, 0.0, 4.0, 3.0)
	var house_vol := vol(Building.to_kmesh(b9))
	var ov := 0.45
	var span := 3.0 + 2.0 * ov
	var length := 4.0 + 2.0 * ov
	var rise := tan(deg_to_rad(Building.ROOF_PITCH)) * span
	var want_roof := {"gable": 0.5 * span * rise * 0.5 * length, "flat": span * 0.2 * length, "shed": 0.5 * (Building.SHED_LOW + (Building.SHED_LOW + rise)) * span * length}
	for k in ["gable", "flat", "shed"]:
		Building.set_roof(b9, k)
		var rs := Building.roof_solid(b9)
		var rk := KMesh.new().from_arrays(PackedVector3Array(rs["verts"]), rs["faces"])
		var full := Building.to_kmesh(b9)
		ok(rk.boundary_edge_count() == 0 and rk.is_manifold() and absf(vol(rk) - want_roof[k]) < 1e-5 and full.boundary_edge_count() == 0 and full.is_manifold() and absf(vol(full) - house_vol - want_roof[k]) < 1e-5,
			"9 roof %s: solid closed %s, volume %.6f (analytic %.6f), the house with it closed %s, adds %.6f" % [k, rk.is_closed(), vol(rk), want_roof[k], full.is_closed(), vol(full) - house_vol])
	Building.set_roof(b9, "gable")
	var top_gable := Building.to_kmesh(b9).to_array_mesh(false).get_aabb().end.y
	b9["params"]["roof_overhang"] = 0.0
	var g0 := Building.to_kmesh(b9)
	var rise0 := tan(deg_to_rad(Building.ROOF_PITCH)) * 3.0
	ok(g0.boundary_edge_count() == 0 and g0.is_manifold() and absf(vol(g0) - house_vol - 0.5 * 3.0 * rise0 * 0.5 * 4.0) < 1e-5 and absf(top_gable - (2.7 + rise * 0.5)) < 1e-4,
		"9 overhang param 0: closed %s, the roof prism %.6f; the 0.45 gable's ridge was at %.4f m (want %.4f)" % [g0.is_closed(), vol(g0) - house_vol, top_gable, 2.7 + rise * 0.5])
	ok(Building.from_file(Building.to_file(b9))["roof"]["kind"] == "gable" and not Building.to_file(Building.make()).has("roof") and not Building.to_file(Building.make()).has("walls"),
		"9 the roof is in the file only when there is one")

	var b10 := Building.make("Two floors")
	Building.add_room(b10, 0.0, 0.0, 4.0, 3.0)
	var v_one := vol(Building.to_kmesh(b10))
	var ring := (4.0 * 3.0 - 3.6 * 2.6) * 0.1
	var n_floor := Building.add_floor(b10)
	var two := Building.to_kmesh(b10)
	var want_two := v_one + 7.128 + 12.0 * 0.2 - ring
	ok(n_floor == 1 and Building.storey_count(b10) == 2 and two.boundary_edge_count() == 0 and two.is_manifold() and absf(vol(two) - want_two) < 1e-5 and absf(two.to_array_mesh(false).get_aabb().end.y - 5.5) < 1e-4,
		"10 + Floor: 2 floors, closed %s, volume %.6f (want %.6f = %.6f + 7.128 + 2.4 - %.3f overlap), top at %.2f m" % [two.is_closed(), vol(two), want_two, v_one, ring, two.to_array_mesh(false).get_aabb().end.y])
	b10["params"]["floor_height"] = 3.0
	var tall := Building.to_kmesh(b10)
	var want_tall := v_one + 7.128 + 12.0 * 0.3
	ok(tall.boundary_edge_count() == 0 and absf(vol(tall) - want_tall) < 1e-5, "10 floor_height 3.0: the slab reaches down to the walls (volume %.6f, want %.6f)" % [vol(tall), want_tall])
	b10["params"]["floor_height"] = 2.8
	var sup2 := Building.supports(b10)
	var gone := Building.remove_top_floor(b10)
	ok(gone and Building.storey_count(b10) == 1 and absf(vol(Building.to_kmesh(b10)) - v_one) < 1e-9 and not Building.remove_top_floor(b10),
		"10 removing the top floor gives one floor back (volume %.6f); the last floor stays" % vol(Building.to_kmesh(b10)))
	ok(sup2.size() == 2 and absf(float(sup2[0][0])) < 1e-9 and absf(float(sup2[1][0]) - 2.8) < 1e-9, "10 the floor slabs' tops: y 0 and y 2.8")

	var b11 := Building.make("Split")
	var r11 := Building.add_room(b11, 0.0, 0.0, 6.0, 4.0)
	var v_sh := vol(Building.to_kmesh(b11))
	var iw := Building.add_wall(b11, r11, "z", 3.0)
	var km_iw := Building.to_kmesh(b11)
	var v_iw := vol(km_iw)
	ok(iw != "" and km_iw.boundary_edge_count() == 0 and km_iw.is_manifold() and absf((v_iw - v_sh) - 0.1 * 3.6 * 2.7) < 1e-5,
		"11 interior wall z at x 3: adds %.6f m3 (want %.6f), closed %s" % [v_iw - v_sh, 0.1 * 3.6 * 2.7, km_iw.is_closed()])
	var od := Building.add_opening(b11, r11, iw, "door", 0.0)
	var km_d := Building.to_kmesh(b11)
	var cb11 := Building.collision_boxes(b11)
	ok(od != "" and km_d.boundary_edge_count() == 0 and km_d.is_manifold() and absf((v_iw - vol(km_d)) - 0.9 * 2.1 * 0.1) < 1e-5 and not in_boxes(cb11, Vector3(3.0, 1.0, 2.0)) and in_boxes(cb11, Vector3(3.0, 1.0, 0.7)),
		"11 a door in it removes %.6f m3 (want %.6f), open in the collision %s, the wall beside it solid %s" % [v_iw - vol(km_d), 0.9 * 2.1 * 0.1, not in_boxes(cb11, Vector3(3.0, 1.0, 2.0)), in_boxes(cb11, Vector3(3.0, 1.0, 0.7))])
	ok(Building.add_opening(b11, r11, "i9", "door") == "", "11 an opening on a wall that does not exist is refused")
	var b11x := Building.make("SplitX")
	var r11x := Building.add_room(b11x, 0.0, 0.0, 6.0, 4.0)
	Building.add_wall(b11x, r11x, "x", 2.0)
	ok(absf(vol(Building.to_kmesh(b11x)) - v_sh - 0.1 * 5.6 * 2.7) < 1e-5, "11 an interior wall on x: adds %.6f m3 (want %.6f)" % [vol(Building.to_kmesh(b11x)) - v_sh, 0.1 * 5.6 * 2.7])

	var an := Building.anchors(b11)
	var b12 := Building.make("Doors")
	var r12 := Building.add_room(b12, 0.0, 0.0, 4.0, 3.0)
	Building.add_opening(b12, r12, "front", "door", 0.5)
	Building.add_opening(b12, r12, "front", "door", -1.0)
	Building.add_opening(b12, r12, "back", "window", 0.0)
	var an12 := Building.anchors(b12)
	var fd := Building.anchor(b12, "front door")
	ok(an.size() == 1 and an[0]["name"] == "inner door" and an12.size() == 2 and an12[1]["name"] == "front door 2" and (fd["pos"] as Vector3).is_equal_approx(Vector3(2.5, 0, 0.1)) and (fd["out"] as Vector3).is_equal_approx(Vector3(0, 0, -1)),
		"12 named points: %s; front door at %s pointing %s; a window is none" % [an12.map(func(a): return a["name"]), fd.get("pos"), fd.get("out")])

	var b13 := Building.make("All")
	var r13 := Building.add_room(b13, 1.0, 2.0, 6.0, 4.0)
	Building.add_wall(b13, r13, "z", 2.0)
	Building.add_opening(b13, r13, "i1", "door", 0.4)
	Building.add_opening(b13, r13, "front", "door", 1.0)
	Building.add_floor(b13)
	Building.set_roof(b13, "shed")
	var f13 := Building.to_file(b13)
	var S13 := Scene.new()
	S13.building = b13
	var S13b := Scene.new()
	S13b.from_dict(JSON.parse_string(JSON.stringify(S13.to_dict(B, false))))
	var f13b := Building.to_file(S13b.building)
	var mir := Building.mirror_file(f13)
	var mir2 := Building.mirror_file(mir)
	var v13 := vol(Building.to_kmesh(b13))
	var vm := vol(Building.to_kmesh(Building.from_file(mir)))
	ok(JSON.stringify(f13b) == JSON.stringify(f13) and f13.has("walls") and f13.has("roof") and f13["rooms"][1]["storey"] == 1 and JSON.stringify(mir2) == JSON.stringify(f13) and absf(vm - v13) < 1e-4,
		"13 floors, interior wall and roof round-trip %s; mirror twice = original %s; mirrored volume %.6f vs %.6f" % [JSON.stringify(f13b) == JSON.stringify(f13), JSON.stringify(mir2) == JSON.stringify(f13), vm, v13])

	# ---- phase 1f: PIECES
	var kinds: Array = BuildPieces.DEFS.keys()
	var fh := 2.8
	var nst := int(ceil(fh / 0.18 - 1e-9))
	var rr := fh / nst
	var sum_k := 0.0
	for k in range(1, nst):
		sum_k += k
	var want := {"stairs": 1.0 * 0.28 * rr * sum_k, "crate": 0.6 * 0.4 * 0.5, "pillar": 0.4 * 0.4 * 2.7, "ramp": 0.5 * 1.0 * 2.0 * 0.5, "platform": 2.0 * 2.0 * 0.5}
	# L stairs: a = (n - 2) / 2 treads, a landing, b = n - 2 - a treads
	var la := int((nst - 2) / 2)
	var lb := nst - 2 - la
	var lsum := 0.0
	for k in range(1, la + 1):
		lsum += 0.28 * rr * k * 1.0
	lsum += 1.0 * 1.0 * (la + 1) * rr
	for j in range(1, lb + 1):
		lsum += 0.28 * 1.0 * (la + 1 + j) * rr
	want["stairs_l"] = lsum
	want["table"] = 1.2 * 0.04 * 0.7 + 4.0 * 0.06 * 0.06 * 0.71
	want["bench"] = 1.4 * 0.04 * 0.35 + 4.0 * 0.05 * 0.05 * 0.41
	var post := minf(0.12, 2.0 * 0.2)
	var rail := 1.0 * 0.1
	want["fence"] = 2.0 * post * 0.1 * 1.0 + 2.0 * ((2.0 - 2.0 * post) * rail * 0.1)   # two posts, two rails between them
	var all_ok := true
	var why := []
	for kd in kinds:
		var bq := Building.make("One")
		var idp := Building.add_piece(bq, kd, 3.0, 2.0)
		var pc := Building.piece_of(bq, idp)
		var km := Building.to_kmesh(bq)
		var vv := vol(km)
		var good := idp != "" and km.face_count() > 0 and km.boundary_edge_count() == 0 and km.is_manifold() and absf(vv - float(want[kd])) < 1e-5 and absf(vv - BuildPieces.volume(bq, pc)) < 1e-5
		if good:
			pc["yaw"] = 90.0
			var km2 := Building.to_kmesh(bq)
			var fp0 := BuildPieces.footprint(bq, Building.piece_of(bq, idp))
			good = km2.boundary_edge_count() == 0 and km2.is_manifold() and absf(vol(km2) - vv) < 1e-5 and absf(km2.to_array_mesh(false).get_aabb().size.x - km.to_array_mesh(false).get_aabb().size.z) < 1e-5 and absf(fp0.size.x - km.to_array_mesh(false).get_aabb().size.z) < 1e-5
		all_ok = all_ok and good
		if not good:
			why.append("%s: volume %.8f want %.8f, closed %s manifold %s" % [kd, vv, want[kd], km.boundary_edge_count() == 0, km.is_manifold()])
	ok(all_ok and kinds.size() == 9, "14 each of the %d piece kinds is one closed manifold solid with its analytic volume, and the same turned 90 deg %s" % [kinds.size(), why])
	var bs := Building.make("Stairs")
	var sn := BuildPieces.stairs_numbers(bs, {"kind": "stairs", "w": 1.0, "t": 0.28})
	ok(int(sn["n"]) == 16 and absf(float(sn["r"]) - 0.175) < 1e-9 and float(sn["r"]) <= 0.18, "14 the step count is automatic from a 0.18 m riser: rise 2.8 m = %d risers of %.4f m" % [sn["n"], sn["r"]])
	bs["params"]["floor_height"] = 3.2
	var sn2 := BuildPieces.stairs_numbers(bs, {"kind": "stairs", "w": 1.0, "t": 0.28})
	ok(int(sn2["n"]) == 18 and absf(float(sn2["r"]) * 18.0 - 3.2) < 1e-9, "14 the rise follows floor_height: 3.2 m = %d risers of %.4f m" % [sn2["n"], sn2["r"]])

	var b15 := Building.make("Two floors")
	Building.add_room(b15, 0.0, 0.0, 6.0, 6.0)   # inside 5.6 x 5.6 m: the 4.2 m flight fits
	Building.add_floor(b15)
	var w0 := vol(Building.to_kmesh(b15, ["wall", "floor"]))
	var slab := maxf(0.2, 2.8 - 2.7)
	var ps := Building.add_piece(b15, "stairs", 3.0, 3.0)
	var psp := Building.piece_of(b15, ps)
	var area := 1.0 * 15.0 * 0.28
	var kh := Building.to_kmesh(b15, ["wall", "floor"])
	ok(kh.boundary_edge_count() == 0 and kh.is_manifold() and absf((w0 - vol(kh)) - area * slab) < 1e-4,
		"15 straight stairs on floor 1: the upper slab loses exactly the stairwell, %.6f m3 (plan %.3f m2 x slab %.2f m); closed %s" % [w0 - vol(kh), area, slab, kh.boundary_edge_count() == 0])
	var kall := Building.to_kmesh(b15)
	var stair_v := vol(Building.to_kmesh({"version": 1, "name": "x", "params": b15["params"], "rooms": [], "openings": [], "pieces": b15["pieces"]}))
	ok(kall.boundary_edge_count() == 0 and kall.is_manifold() and absf(vol(kall) - (vol(kh) + stair_v)) < 1e-4 and absf(stair_v - BuildPieces.volume(b15, psp)) < 1e-5,
		"15 the stairs are in the house's mesh: closed %s, volume = house with the hole + the stairs (%.6f m3)" % [kall.boundary_edge_count() == 0, stair_v])
	var cuts := BuildPieces.stairwell(b15, psp)
	var cvol := 0.0
	for c in cuts:
		cvol += (c as AABB).get_volume()
	ok(absf(cvol - area * slab) < 1e-5 and cuts.size() == 15, "15 the stairwell is %d cut boxes, %.6f m3" % [cuts.size(), cvol])
	psp["yaw"] = 90.0
	var kh90 := Building.to_kmesh(b15, ["wall", "floor"])
	ok(kh90.boundary_edge_count() == 0 and absf((w0 - vol(kh90)) - area * slab) < 1e-4, "15 turned 90 deg the hole is the same size (%.6f m3)" % (w0 - vol(kh90)))
	Building.remove_piece(b15, ps)
	ok(absf(vol(Building.to_kmesh(b15, ["wall", "floor"])) - w0) < 1e-9 and not b15.has("pieces"), "15 Delete: the slab is whole again, the pieces list is gone")
	Building.add_piece(b15, "stairs_l", 3.0, 3.0)
	var apl := 1.0 * 0.28 * float(la) + 1.0 + 1.0 * 0.28 * float(lb)   # flight 1, landing, flight 2 (plan areas, w = 1)
	var khl := Building.to_kmesh(b15, ["wall", "floor"])
	ok(khl.boundary_edge_count() == 0 and khl.is_manifold() and absf((w0 - vol(khl)) - apl * slab) < 1e-4,
		"15 L stairs cut their L: %.6f m3 (plan %.3f m2 x %.2f m), closed %s" % [w0 - vol(khl), apl, slab, khl.boundary_edge_count() == 0])
	var tight := Building.make("Tight")
	Building.add_room(tight, 0.0, 0.0, 4.0, 3.0)
	var tp := BuildPieces.make("p1", "stairs", 2.0, 1.5)
	var fit1 := BuildPieces.fit(tight, tp)
	var fit2 := BuildPieces.fit(b15, BuildPieces.make("p9", "crate", 0.3, 0.3))
	var fit3 := BuildPieces.fit(b15, BuildPieces.make("p9", "crate", 9.0, 9.0))
	ok(not fit1["ok"] and fit2["ok"] and absf(float(fit2["x"]) - 0.5) < 1e-6 and not fit3["ok"], "15 placement: stairs longer than the room are refused (%s), a crate in the wall is moved inside (x 0.3 -> %.2f), outside any room refused" % [fit1.get("why"), fit2.get("x", -1.0)])
	var b15b := Building.make("Ground only")
	Building.add_room(b15b, 0.0, 0.0, 6.0, 4.0)
	var v15b := vol(Building.to_kmesh(b15b, ["wall", "floor"]))
	Building.add_piece(b15b, "stairs", 3.0, 2.0)
	ok(absf(vol(Building.to_kmesh(b15b, ["wall", "floor"])) - v15b) < 1e-9 and BuildPieces.stairwell(b15b, b15b["pieces"][0]).is_empty(), "15 with no floor above there is no hole")

	Building.add_piece(b15, "crate", 1.5, 1.5)
	Building.piece_of(b15, "p2")["yaw"] = 270.0
	Building.add_piece(b15, "ramp", 4.5, 1.5, 180.0)
	var f15 := Building.to_file(b15)
	var S16 := Scene.new()
	S16.building = b15
	var S16b := Scene.new()
	S16b.from_dict(JSON.parse_string(JSON.stringify(S16.to_dict(B, false))))
	var f16 := Building.to_file(S16b.building)
	var mir16 := Building.mirror_file(f15)
	var mir16b := Building.mirror_file(mir16)
	var v16 := vol(Building.to_kmesh(b15))
	var vm16 := vol(Building.to_kmesh(Building.from_file(mir16)))
	ok(JSON.stringify(f16) == JSON.stringify(f15) and f15["pieces"].size() == 3 and JSON.stringify(mir16b) == JSON.stringify(f15) and absf(vm16 - v16) < 1e-4
		and absf(vol(Building.to_kmesh(S16b.building)) - v16) < 1e-5 and mir16["pieces"][0].get("flip", false) == true and absf(float(mir16["pieces"][0]["x"]) + 3.0) < 1e-9,
		"16 pieces round-trip %s, mirror twice = original %s, mirrored volume %.6f vs %.6f, the L stairs flip %s" % [JSON.stringify(f16) == JSON.stringify(f15), JSON.stringify(mir16b) == JSON.stringify(f15), vm16, v16, mir16["pieces"][0].get("flip")])
	var bad := Building.from_file({"version": 1, "name": "bad", "rooms": [{"id": "r1", "x": 0, "z": 0, "w": 4, "d": 3}], "pieces": [
		{"id": "p1", "kind": "spaceship"}, {"id": "p2", "kind": "crate", "x": "NaN", "w": 99.0, "yaw": 45.0}, "junk", {"id": "p2", "kind": "table", "x": 1.0, "z": 1.0}]})
	ok(bad["pieces"].size() == 2 and absf(float(bad["pieces"][0]["w"]) - 3.0) < 1e-9 and float(bad["pieces"][0]["x"]) == 0.0 and bad["pieces"][0]["id"] != bad["pieces"][1]["id"],
		"16 a bad piece is dropped (unknown kind, junk), numbers are clamped (w 99 -> 3), ids stay unique: %s" % [bad["pieces"].map(func(p): return "%s %s w%s yaw%s" % [p["id"], p["kind"], p.get("w"), p["yaw"]])])

	# 17 COLLISION on the set: boxes + tops, the stairs' ramp
	var b17 := Building.make("Walk")
	Building.add_room(b17, 0.0, 0.0, 6.0, 6.0)
	Building.add_floor(b17)
	Building.add_piece(b17, "crate", 1.0, 1.0)
	Building.add_piece(b17, "stairs", 3.0, 3.0)
	var pcol := BuildPieces.collision_all(b17)
	ok(pcol["boxes"].size() == 1 and pcol["supports"].size() == 1 and pcol["ramps"].size() == 1 and absf(float(pcol["supports"][0][0]) - 0.5) < 1e-9,
		"17 the crate is a box with its top (0.5 m) as a support; the stairs are one ramp (%d boxes, %d supports, %d ramps)" % [pcol["boxes"].size(), pcol["supports"].size(), pcol["ramps"].size()])
	Props.register_building("building:Walk", Building.collision_boxes(b17) + pcol["boxes"], Building.supports(b17) + pcol["supports"], pcol["ramps"])
	var prop17 := Props.make("building:Walk", Transform3D.IDENTITY)
	var props17 := [prop17]
	var z0 := 3.0 - 15.0 * 0.28 * 0.5
	# the slope is the line through the nosings: y = r + (r / t) z; a point 3 cm above it stands on it
	var slope_ok := true
	var worst := 0.0
	for zz in [0.1, 1.0, 2.0, 3.0, 4.0]:
		var yy: float = rr + rr / 0.28 * zz
		var sf := Props.surface_below(props17, Vector3(3.0, yy + 0.03, z0 + zz))
		worst = maxf(worst, absf(float(sf["y"]) - yy))
		slope_ok = slope_ok and absf(float(sf["y"]) - yy) < 1e-6 and (sf["n"] as Vector3).y > 0.5
	ok(slope_ok, "17 the stairs are a RAMP: a point over the nosing line stands on it (worst error %.6f m)" % worst)
	var head := Props.surface_below(props17, Vector3(3.0, 2.8, z0 + 15.0 * 0.28 - 0.01))
	ok(absf(float(head["y"]) - 2.8) < 0.01, "17 the slope meets the upper floor's top (2.8 m) at the stairs' head: %.4f" % float(head["y"]))
	ok(Props.depth(prop17, Vector3(3.0, 0.05, z0 + 1.0), Vector3(3.0, 0.05, z0 + 1.0), 0.02) > 0.0 and Props.depth(prop17, Vector3(3.0, 2.3, z0 + 1.0), Vector3(3.0, 2.3, z0 + 1.0), 0.02) == 0.0,
		"17 inside the stairs is solid; above the slope is free")
	var cb17 := Building.collision_boxes(b17)
	ok(not in_boxes(cb17, Vector3(3.0, 2.7, 3.0)) and in_boxes(cb17, Vector3(1.0, 2.7, 3.0)), "17 the stairwell is open in the floor's collision, the slab beside it is solid")

	print("BUILD %s: %d failed" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
