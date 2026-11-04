class_name PartFast
extends RefCounted
## s249 FAST BUILD. Two things that make a decorated building (the temple: 278 bodies, ornaments + roofs) build in minutes, not tens of minutes.
## 1. SEAT (default, output identical): an ornament rests on the host under it by shooting rays straight down at the host's triangles.  The old code
##    looped over EVERY triangle of EVERY host body for each of ~36 foot points, and re-measured every host's box from scratch each time (39.7 s of the
##    148 s temple replay).  Here a host body's box and an x/z grid of its triangles are made once per tessellation (cached by kernel id + generation) and a
##    ray tests only the triangles in its own cell, with the same arithmetic as PartFacts.ray_hit, so the answer is the same number.
## 2. FAST BUILD (opt-in: rec["fast_build"] = true; the Part page's "Fast build" switch): a roof that is the same shape as one already sewn, only somewhere else
##    (the two compound-wall cap roofs), is a translated copy of the sewn solid, not a second 10 s sewing.  Real solids (prims, extrudes...) are untouched.
const KCad := preload("res://scripts/kcad.gd")
const MM := 0.001
const EPS := 1e-3   # mm: a grid cell reaches this far past a triangle's box, so a ray the old code counted as a hit (barycentric slack 1e-9) is never missed

static var enabled := false   # set by Part.replay from rec["fast_build"]
static var _idx := {}         # "id.gen" -> {"t": tris, "box": AABB, "grid": Dictionary or null}
static var _idx_pts := 0
static var _roof := {}        # shape key (roof parameters without "at") -> {"at": Vector3 mm, "ids": [kernel ids kept as masters]}
static var roof_copies := 0   # tests read it


static func _entry(id: int) -> Dictionary:
	var key := "%d.%d" % [id, KCad.gen(id)]
	if _idx.has(key):
		return _idx[key]
	var t := PartFacts.tess_mm(id, 0.002, 0.8)
	var e := {"t": t, "box": PartFacts.box_of(t) if not t.is_empty() else AABB(), "grid": null, "cs": 1.0, "x0": 0.0, "z0": 0.0}
	if _idx_pts > 8000000:
		_idx.clear()
		_idx_pts = 0
	_idx[key] = e
	_idx_pts += t.size()
	return e


static func _grid(e: Dictionary) -> void:
	var t: PackedVector3Array = e["t"]
	var box: AABB = e["box"]
	var nt := t.size() / 3
	var cs := maxf(sqrt(maxf(box.size.x * box.size.z, 1.0) / maxf(float(nt) * 0.5, 1.0)), 0.5)
	var g := {}
	var x0 := box.position.x - EPS
	var z0 := box.position.z - EPS
	for i in nt:
		var a := t[i * 3]
		var b := t[i * 3 + 1]
		var c := t[i * 3 + 2]
		var lx := minf(a.x, minf(b.x, c.x)) - EPS
		var hx := maxf(a.x, maxf(b.x, c.x)) + EPS
		var lz := minf(a.z, minf(b.z, c.z)) - EPS
		var hz := maxf(a.z, maxf(b.z, c.z)) + EPS
		var cx0 := int(floor((lx - x0) / cs))
		var cx1 := int(floor((hx - x0) / cs))
		var cz0 := int(floor((lz - z0) / cs))
		var cz1 := int(floor((hz - z0) / cs))
		for cx in range(cx0, cx1 + 1):
			for cz in range(cz0, cz1 + 1):
				var k := cx * 1048576 + cz
				if g.has(k):
					var lst: PackedInt32Array = g[k]   # a packed array is a value: append, then store it back
					lst.append(i)
					g[k] = lst
				else:
					g[k] = PackedInt32Array([i])
	e["grid"] = g
	e["cs"] = cs
	e["x0"] = x0
	e["z0"] = z0


## PartFacts.ray_hit(tris, (x, top, z), DOWN) for the triangles that can be under (x, z): the same arithmetic, the same minimum
static func ray_down(e: Dictionary, x: float, top: float, z: float) -> float:
	if e["grid"] == null:
		_grid(e)
	var cs: float = e["cs"]
	var cxq := int(floor((x - float(e["x0"])) / cs))
	var czq := int(floor((z - float(e["z0"])) / cs))
	if cxq < 0 or czq < 0 or cxq >= 1048576 or czq >= 1048576:
		return INF
	var k := cxq * 1048576 + czq
	var g: Dictionary = e["grid"]
	if not g.has(k):
		return INF
	var P: PackedVector3Array = e["t"]
	var o := Vector3(x, top, z)
	var d := Vector3.DOWN
	var best := INF
	for ti in (g[k] as PackedInt32Array):
		var i: int = ti * 3
		var e1 := P[i + 1] - P[i]
		var e2 := P[i + 2] - P[i]
		var h := d.cross(e2)
		var a := e1.dot(h)
		if absf(a) < 1e-12:
			continue
		var f := 1.0 / a
		var sv := o - P[i]
		var u := f * sv.dot(h)
		if u < -1e-9 or u > 1.0 + 1e-9:
			continue
		var qv := sv.cross(e1)
		var v := f * d.dot(qv)
		if v < -1e-9 or u + v > 1.0 + 1e-9:
			continue
		var tt := f * e2.dot(qv)
		if tt >= -1e-9 and tt < best:
			best = maxf(tt, 0.0)
	return best


## PartOrnament._surface_under, same answers: per sample point the highest host surface y in [low_y, top_y], NAN for none
static func surface_under(bodies: Array, pts: Array, top_y: float, low_y: float) -> Array:
	var region := AABB()
	var first := true
	for q in pts:
		var qq: Vector3 = q
		var bx := AABB(Vector3(qq.x, low_y, qq.z), Vector3.ZERO)
		region = bx if first else region.merge(bx)
		first = false
	region = region.grow(1.0)
	region.size.y = maxf(region.size.y, top_y - low_y)
	var cand: Array = []
	for id in bodies:
		var e := _entry(int(id))
		if (e["t"] as PackedVector3Array).is_empty():
			continue
		var bb: AABB = e["box"]
		if bb.position.x > region.end.x or bb.end.x < region.position.x or bb.position.z > region.end.z or bb.end.z < region.position.z or bb.end.y < low_y or bb.position.y > top_y:
			continue
		cand.append(e)
	var hits: Array = []
	for q in pts:
		var qq: Vector3 = q
		var best := NAN
		for e in cand:
			var d := ray_down(e, qq.x, top_y, qq.z)
			if is_inf(d):
				continue
			var y := top_y - d
			if y >= low_y and (is_nan(best) or y > best):
				best = y
		hits.append(best)
	return hits


# ------------------------------------------------------------------------------------------- roofs (fast build only)
static func _shape_key(f: Dictionary) -> String:
	var P := PartRoof.norm(f)
	P["at"] = Vector3.ZERO
	return str(hash(JSON.stringify(P)))


## a roof of a shape already sewn, somewhere else: translated copies of the sewn solids. true when it did the step
static func roof_copy(bodies: Array, f: Dictionary) -> bool:
	if not enabled:
		return false
	var key := _shape_key(f)
	if not _roof.has(key):
		return false
	var m: Dictionary = _roof[key]
	var delta: Vector3 = (PartRoof.norm(f)["at"] as Vector3) - (m["at"] as Vector3)
	var got: Array = []
	for mid in m["ids"]:
		var c := KCad.translate(int(mid), delta * MM)
		if c == 0:
			for g in got:
				KCad.release(int(g))
			_roof.erase(key)
			return false
		got.append(c)
	bodies.append_array(got)
	roof_copies += 1
	return true


## the roof Part just sewed: keep copies of its solids as the masters for a same-shaped roof elsewhere
static func roof_keep(f: Dictionary, made: Array) -> void:
	if not enabled or made.is_empty():
		return
	var key := _shape_key(f)
	if _roof.has(key):
		return
	var ids: Array = []
	for id in made:
		var c := KCad.translate(int(id), Vector3.ZERO)
		if c == 0:
			for g in ids:
				KCad.release(int(g))
			return
		ids.append(c)
	_roof[key] = {"at": PartRoof.norm(f)["at"], "ids": ids}
