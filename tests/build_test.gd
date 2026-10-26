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

	print("BUILD %s: %d failed" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
