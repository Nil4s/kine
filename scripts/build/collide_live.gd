extends RefCounted
## P125 COLLIDE LIVE (Friday plan 125, "the door hits the wall: red flash"): the check that runs while a piece moves.
## A moving piece (the body a hinge turns) is a bag of triangles (metres) turned about the hinge axis by the angle of the frame. Per frame:
##   1. the turned box of the piece against each other piece's box (AABB prefilter: free motion costs a few microseconds),
##   2. only the moving triangles whose own box meets the overlap of the two boxes, each against the other piece's triangles in the grid
##      cells it spans (the other piece is binned once, in prep), by a real triangle-triangle test (an edge of one piercing the other).
## A touching face (no crossing) is not a hit; an edge or corner that crosses a face is. No kernel call per frame: the kernel is used once, to
## tessellate the pieces. No class_name on purpose (the global class cache is not rebuilt in a fresh worktree): load() this file by path.
## Answers are plain numbers: hit_at -> the body index it hits (-1 = free), first_contact -> {"free", "hit", "body"} in degrees.

const KCad := preload("res://scripts/kcad.gd")
const PART := preload("res://scripts/build/part.gd")
const GRID := 12
const EPS := 1e-9

static var ms := PackedFloat64Array()   # the time (ms) of each frame's check (hit_at), for the timing bar


## the moving piece and the others of a hinge step, tessellated once. {"ok", "why", "move", "mbox", "others": [{"body", "tris", "box", "cells"}], "pivot", "axis"}
static func prep(rec: Dictionary, hinge_id: String) -> Dictionary:
	if not PART.available():
		return {"ok": false, "why": PART.why_not()}
	var feats: Array = rec.get("features", [])
	var hi := -1
	for i in feats.size():
		if String(feats[i]["id"]) == hinge_id and String(feats[i]["t"]) == "hinge":
			hi = i
	if hi <= 0:
		return {"ok": false, "why": "there is no hinge %s" % hinge_id}
	var f: Dictionary = feats[hi]
	var ids: Array = PART.replay(rec, hi - 1, {"keep": true}).get("ids", [])
	var bi := int(f.get("body", -1))
	if bi < 0 or bi >= ids.size():
		for b in ids:
			KCad.release(b)
		return {"ok": false, "why": "there is no body %d to hinge" % bi}
	var out := {"ok": true, "why": "", "move": PackedVector3Array(), "mbox": AABB(), "others": [], "pivot": PART._pivot(f), "axis": PART._axis(f), "body": bi}
	out["move"] = PART._tris_of(int(ids[bi]))
	out["mbox"] = box_of(out["move"])
	for j in ids.size():
		if j == bi:
			continue
		var tr: PackedVector3Array = PART._tris_of(int(ids[j]))
		var bx := box_of(tr)
		out["others"].append({"body": j, "tris": tr, "box": bx, "cells": _bin(tr, bx)})
	for b in ids:
		KCad.release(b)
	if (out["move"] as PackedVector3Array).is_empty():
		out["ok"] = false
		out["why"] = "could not tessellate the moving piece"
	ms = PackedFloat64Array()
	return out


## prep for plain triangle soups (no kernel): the moving one, the others, the pivot and the axis (metres). For the timing bar on 2k-triangle parts
static func prep_soups(move: PackedVector3Array, others: Array, pivot: Vector3, axis: Vector3) -> Dictionary:
	var out := {"ok": true, "why": "", "move": move, "mbox": box_of(move), "others": [], "pivot": pivot, "axis": axis.normalized(), "body": 0}
	for j in others.size():
		var tr: PackedVector3Array = others[j]
		var bx := box_of(tr)
		out["others"].append({"body": j + 1, "tris": tr, "box": bx, "cells": _bin(tr, bx)})
	ms = PackedFloat64Array()
	return out


static func box_of(v: PackedVector3Array) -> AABB:
	if v.is_empty():
		return AABB()
	var lo := v[0]
	var hi := v[0]
	for p in v:
		lo = lo.min(p)
		hi = hi.max(p)
	return AABB(lo, hi - lo)


## the other piece's triangles by grid cell: key -> PackedInt32Array of triangle starts (index of the first vertex)
static func _bin(tr: PackedVector3Array, bx: AABB) -> Dictionary:
	var cells := {}
	var sz := bx.size.max(Vector3(1e-6, 1e-6, 1e-6))
	for i in range(0, tr.size(), 3):
		var lo := tr[i].min(tr[i + 1]).min(tr[i + 2])
		var hi := tr[i].max(tr[i + 1]).max(tr[i + 2])
		var c0 := _cell(lo, bx, sz)
		var c1 := _cell(hi, bx, sz)
		for x in range(c0.x, c1.x + 1):
			for y in range(c0.y, c1.y + 1):
				for z in range(c0.z, c1.z + 1):
					var k := (x * GRID + y) * GRID + z
					var lst: PackedInt32Array = cells.get(k, PackedInt32Array())
					lst.append(i)
					cells[k] = lst   # a packed array is a value: put the grown one back
	return cells


static func _cell(p: Vector3, bx: AABB, sz: Vector3) -> Vector3i:
	var q := (p - bx.position) / sz * float(GRID)
	return Vector3i(clampi(int(floor(q.x)), 0, GRID - 1), clampi(int(floor(q.y)), 0, GRID - 1), clampi(int(floor(q.z)), 0, GRID - 1))


## the transform that turns the moving piece by deg about the hinge axis through the pivot
static func xform(P: Dictionary, deg: float) -> Transform3D:
	var b := Basis(P["axis"] as Vector3, deg_to_rad(deg))
	return Transform3D(b, (P["pivot"] as Vector3) - b * (P["pivot"] as Vector3))


## the body index the moving piece hits when turned by deg, -1 when it is free. The time of the call is kept in ms
static func hit_at(P: Dictionary, deg: float) -> int:
	var t0 := Time.get_ticks_usec()
	var r := _hit(P, deg)
	ms.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	return r


static func _hit(P: Dictionary, deg: float) -> int:
	var xf := xform(P, deg)
	var mb: AABB = P["mbox"]
	var moved_box := xf * mb   # the turned box, grown to hold the turned piece (a loose box is fine: it is only the prefilter)
	var mv: PackedVector3Array = P["move"]
	var moved := PackedVector3Array()
	for o in P["others"]:
		var ob: AABB = o["box"]
		if not moved_box.intersects(ob):
			continue
		if moved.is_empty():
			moved = xf * mv
		var ib := moved_box.intersection(ob)
		if _hit_pair(moved, o, ib):
			return int(o["body"])
	return -1


static func _hit_pair(moved: PackedVector3Array, o: Dictionary, ib: AABB) -> bool:
	var ob: AABB = o["box"]
	var sz := ob.size.max(Vector3(1e-6, 1e-6, 1e-6))
	var cells: Dictionary = o["cells"]
	var tr: PackedVector3Array = o["tris"]
	var lo_b := ib.position
	var hi_b := ib.end
	for i in range(0, moved.size(), 3):
		var a := moved[i]
		var b := moved[i + 1]
		var c := moved[i + 2]
		var lo := a.min(b).min(c)
		var hi := a.max(b).max(c)
		if lo.x > hi_b.x or hi.x < lo_b.x or lo.y > hi_b.y or hi.y < lo_b.y or lo.z > hi_b.z or hi.z < lo_b.z:
			continue
		var c0 := _cell(lo, ob, sz)
		var c1 := _cell(hi, ob, sz)
		for x in range(c0.x, c1.x + 1):
			for y in range(c0.y, c1.y + 1):
				for z in range(c0.z, c1.z + 1):
					var key := (x * GRID + y) * GRID + z
					if not cells.has(key):
						continue
					for j in (cells[key] as PackedInt32Array):
						if tri_tri(a, b, c, tr[j], tr[j + 1], tr[j + 2]):
							return true
	return false


## two triangles cross: an edge of one pierces the other (coplanar overlap and plain touching are not a crossing)
static func tri_tri(a: Vector3, b: Vector3, c: Vector3, d: Vector3, e: Vector3, f: Vector3) -> bool:
	return _seg_tri(a, b, d, e, f) or _seg_tri(b, c, d, e, f) or _seg_tri(c, a, d, e, f) or _seg_tri(d, e, a, b, c) or _seg_tri(e, f, a, b, c) or _seg_tri(f, d, a, b, c)


static func _seg_tri(p: Vector3, q: Vector3, a: Vector3, b: Vector3, c: Vector3) -> bool:
	var d := q - p
	var e1 := b - a
	var e2 := c - a
	var h := d.cross(e2)
	var det := e1.dot(h)
	if absf(det) < 1e-18:
		return false
	var inv := 1.0 / det
	var s := p - a
	var u := inv * s.dot(h)
	if u < -EPS or u > 1.0 + EPS:
		return false
	var qv := s.cross(e1)
	var v := inv * d.dot(qv)
	if v < -EPS or u + v > 1.0 + EPS:
		return false
	var t := inv * e2.dot(qv)
	return t > 1e-6 and t < 1.0 - 1e-6


## walk the angle from from_deg to to_deg in steps of at most step_deg; at the first step that hits, bisect between the last free angle and
## it down to tol_deg. {"hit": false} or {"hit": true, "free" (the last free angle), "deg" (the first angle that hits), "body"}
static func first_contact(P: Dictionary, from_deg: float, to_deg: float, step_deg := 1.5, tol_deg := 0.05) -> Dictionary:
	var n := maxi(1, int(ceil(absf(to_deg - from_deg) / step_deg - 1e-9)))
	var free := from_deg
	var b0 := hit_at(P, from_deg)
	if b0 >= 0:
		return {"hit": true, "free": from_deg, "deg": from_deg, "body": b0}
	for i in range(1, n + 1):
		var d := lerpf(from_deg, to_deg, float(i) / float(n))
		var bh := hit_at(P, d)
		if bh < 0:
			free = d
			continue
		var lo := free
		var hi := d
		while absf(hi - lo) > tol_deg:
			var mid := (lo + hi) * 0.5
			if hit_at(P, mid) >= 0:
				hi = mid
			else:
				lo = mid
		return {"hit": true, "free": lo, "deg": hi, "body": bh}
	return {"hit": false, "free": free}
