extends "res://scripts/easy_part_pull.gd"
## EASY PART MOVE BY DRAG (Friday plan 53, Kine's own): with two or more separate pieces, press on a piece and drag it. While the pointer is over
## ANOTHER piece's flat face the dragged piece shows as a ghost sitting flush on that face (its near side on the face's plane, no gap), and it
## slides on the face in steps of 1 mm; on the release it lands there as ONE undo step, "Moved a piece". A click without a drag still picks the
## piece; a press on empty floor is not ours (the camera orbits and pans as before). With one piece nothing here starts.

const MV_GRID := 0.001   # m: the grid in the face's plane
const MV_GHOST := Color(0.35, 0.85, 1.0)

var _mv := {}   # {"bi": body, "grab": the pressed point (m), "p": press (px), "moved": bool, "faces": the bodies' triangles, "plan": the drop now}
var _mv_layer: Control   # the ghost's own overlay (made at the first drag)


## a press on a piece (when 2+ pieces are there and no pick mode waits for a click): a drag from it moves the piece
func _mv_start(p: Vector2) -> bool:
	if _tpl() != "" or not _drag.is_empty() or not _draft.is_empty() or wall_pick or hpat_pick or fill_pick or bool(get("bulge_pick")) or bool(get("text_pick")):
		return false
	var faces: Array = Part.body_faces(_rec(), -1)
	if faces.size() < 2:
		return false
	var hit: Dictionary = pu._ray_hit(p, faces)
	if hit.is_empty():
		return false
	_mv = {"bi": int(hit["body"]), "grab": hit["at"], "p": p, "moved": false, "faces": faces, "plan": {}}
	return true


func _mv_move(p: Vector2) -> void:
	if not bool(_mv.get("moved", false)):
		if p.distance_to(_mv["p"] as Vector2) < 6.0:
			return
		_mv["moved"] = true
		_say("Drop it on the face of another piece: it sits flush on that face")
	_mv["plan"] = _mv_plan(p)
	if _mv_layer == null:
		_mv_layer = Control.new()
		_mv_layer.name = "easypart_move_ghost"
		_mv_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		_mv_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mv_layer.draw.connect(_mv_draw)
		dots.get_parent().add_child(_mv_layer)
	_mv_layer.queue_redraw()


## where the piece would land with the pointer at p: {} (not over another piece's flat face) or {"delta": m, "ghost": the moved triangles, "target": body}
func _mv_plan(p: Vector2) -> Dictionary:
	var bi := int(_mv["bi"])
	var faces: Array = (_mv["faces"] as Array).duplicate()
	faces[bi] = PackedVector3Array()   # the piece in hand is not a target
	var hit: Dictionary = pu._ray_hit(p, faces)
	if hit.is_empty():
		return {}
	var tb := int(hit["body"])
	var at: Vector3 = hit["at"]
	var fc := _mv_face(faces[tb], at)
	if fc.is_empty():
		return {}
	var n: Vector3 = fc["n"]
	var plane_d: float = fc["d"]
	if n.dot(m.cam.project_ray_origin(p) - at) < 0.0:
		n = -n   # the outside of the face: the side the camera sees
		plane_d = -plane_d
	var ax := -1   # the axis the face is square to (-1: a slanted face: flush, but no grid)
	for a in 3:
		if absf(n[a]) > 0.9999:
			var sg := signf(n[a])
			ax = a
			n = Vector3.ZERO
			n[a] = sg
	var mine: PackedVector3Array = (_mv["faces"] as Array)[bi]
	var mb := _mv_bounds(mine)
	var low := INF
	for v in mine:
		low = minf(low, v.dot(n))
	var dv: Vector3 = at - (_mv["grab"] as Vector3)
	var delta := (dv - dv.dot(n) * n) + (plane_d - low) * n   # slide across to the drop point, then flush on the face
	if ax >= 0:
		var tbb := _mv_bounds(faces[tb])
		var on_edge := absf(plane_d * n[ax] - (tbb.end[ax] if n[ax] > 0.0 else tbb.position[ax])) < 1e-5   # the face is a side of the target's box
		for a in 3:
			if a == ax:
				continue
			var nm: float = mb.position[a] + delta[a]
			var lo: float = tbb.position[a]
			var hi: float = tbb.end[a] - mb.size[a]
			var fits := on_edge and hi >= lo - 1e-9
			if fits:
				nm = clampf(nm, lo, hi)
			var sn := roundf(nm / MV_GRID) * MV_GRID
			if fits:
				var slo := ceilf(lo / MV_GRID - 1e-6) * MV_GRID
				var shi := floorf(hi / MV_GRID + 1e-6) * MV_GRID
				if slo <= shi + 1e-9:
					sn = clampf(sn, slo, shi)
				else:
					sn = nm
			delta[a] = sn - mb.position[a]
	var ghost := PackedVector3Array()
	ghost.resize(mine.size())
	for i in mine.size():
		ghost[i] = mine[i] + delta
	return {"delta": delta, "ghost": ghost, "target": tb}


## the normal and the plane offset (n . x = d) of the triangle of these faces that holds pt; {} when none
func _mv_face(tris: PackedVector3Array, pt: Vector3) -> Dictionary:
	for k in range(0, tris.size() - 2, 3):
		if _pt_on_tri(tris[k], tris[k + 1], tris[k + 2], pt):
			var n := (tris[k + 1] - tris[k]).cross(tris[k + 2] - tris[k]).normalized()
			return {"n": n, "d": n.dot(tris[k])}
	return {}


static func _mv_bounds(tris: PackedVector3Array) -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in tris:
		lo = lo.min(v)
		hi = hi.max(v)
	return AABB(lo, hi - lo)


## the release of a drag: true = a move was tried (or refused in words); false = it was only a click
func _mv_drop(p: Vector2) -> bool:
	var was_moved := bool(_mv.get("moved", false))
	var bi := int(_mv["bi"])
	var plan := _mv_plan(p) if was_moved else {}
	_mv_end()
	if not was_moved:
		return false
	if plan.is_empty():
		_say("Nothing moved: drop the piece on a flat face of another piece")
		return true
	var delta: Vector3 = plan["delta"]
	if delta.length() < 1e-6:
		_say("Already flush on that face: nothing moved")
		return true
	var mm := delta / Part.MM
	_flush_if_dirty()
	var snap := _rec().duplicate(true)
	_begin("Moved a piece")
	var rec := pu._ensure()
	var f := Part.new_feature(rec, "move", {"body": bi, "d": [snappedf(mm.x, 0.0001), snappedf(mm.y, 0.0001), snappedf(mm.z, 0.0001)]})
	rec["features"].append(f)
	var why := _last_error(rec, String(f["id"]))
	if why != "":
		m.S.part = snap
		m._drop_undo()
		_edit_n = -1
		_say("That piece cannot move there: " + _plain(why))
	else:
		_end()
		_say("Moved the piece onto the face. Undo puts it back")
	_pick_clear()
	tweak = {}
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_values_sync()
	return true


func _mv_end() -> void:
	_mv = {}
	if _mv_layer != null:
		_mv_layer.queue_redraw()


## the ghost: the piece where the drop would put it, tinted, with its outline
func _mv_draw() -> void:
	if _mv.is_empty() or not bool(_mv.get("moved", false)):
		return
	var plan: Dictionary = _mv.get("plan", {})
	if plan.is_empty():
		return
	var g: PackedVector3Array = plan["ghost"]
	for k in range(0, g.size() - 2, 3):
		var q := _proj3(g, k)
		if q.size() < 3 or absf((q[1] - q[0]).cross(q[2] - q[0])) < 0.5:
			continue
		_mv_layer.draw_colored_polygon(q, Color(MV_GHOST, 0.32))
	var bb := _mv_bounds(g)
	var c: Array = []
	for i in 8:
		c.append(bb.position + Vector3(bb.size.x * (i & 1), bb.size.y * ((i >> 1) & 1), bb.size.z * ((i >> 2) & 1)))
	for e in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
		var a: Vector3 = c[e[0]]
		var b: Vector3 = c[e[1]]
		if m.cam.is_position_behind(a) or m.cam.is_position_behind(b):
			continue
		_mv_layer.draw_line(m.cam.unproject_position(a), m.cam.unproject_position(b), MV_GHOST, 2.0, true)
