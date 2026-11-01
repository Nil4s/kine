## SPLIT TO FIT THE PRINTER BED (Friday plan 114). A part bigger than the printer bed (default 220 x 220 x 250 mm) is cut with the CAD kernel into
## a grid of pieces that each fit, and every cut face gets matching dowel holes (2 x 5 mm, 10 mm deep, one set in each piece) so the pieces glue together aligned.
## Works on the kernel's solids of the part record (Part.replay keep), in the printer's millimetres (X, Y, Z up; see MeshExport.to_print), so a piece keeps its
## place in the assembled part. The result is bodies in the same shape MeshExport writes: {"name", "v", "t", "color"}.
##   split_rec(rec, bed)            -> {"bodies", "split": bool, "pieces": n, "cuts": [{"axis", "pos", "holes": [centre Vector3 mm], "dia", "depth"}], "why"}
##   export_part(rec, fmt, dir, bed) the Export dialog's road when "Split to fit" is ticked: 3MF = one file, one object a piece; STL = one file a piece
## A body that fits the bed in every axis is never touched.
class_name PrintSplit
extends RefCounted

const KCad := preload("res://scripts/kcad.gd")
const DEFAULT_BED := Vector3(220.0, 220.0, 250.0)
const DOWEL_D := 5.0   # mm, the hole
const CLEARANCE := 0.2   # mm, hole diameter minus pin diameter
const PIN_D := DOWEL_D - CLEARANCE   # mm, the separate dowel pins
const DOWEL_DEPTH := 10.0   # mm, in each piece
const DOWEL_COUNT := 2
const DEFLECT_M := 0.00005   # pieces are cut finer than a plain export (0.05 mm), so a 5 mm hole is a round hole
const ANGLE := 0.2
const AXES := ["X", "Y", "Z"]
## where on a cut face a dowel is tried, as (fraction along the longer side, fraction along the shorter side)
const SITES := [Vector2(0.25, 0.5), Vector2(0.75, 0.5), Vector2(0.5, 0.25), Vector2(0.5, 0.75), Vector2(0.25, 0.25), Vector2(0.75, 0.75),
		Vector2(0.25, 0.75), Vector2(0.75, 0.25), Vector2(0.5, 0.5), Vector2(0.1, 0.5), Vector2(0.9, 0.5)]

static var _size_key := 0
static var _size_sizes: Array = []


static func bbox_of(b: Dictionary) -> AABB:
	var v: PackedVector3Array = b["v"]
	if v.is_empty():
		return AABB()
	var box := AABB(v[0], Vector3.ZERO)
	for p in v:
		box = box.expand(p)
	return box


static func fits(size: Vector3, bed: Vector3) -> bool:
	return size.x <= bed.x + 0.001 and size.y <= bed.y + 0.001 and size.z <= bed.z + 0.001


## how many slabs along each axis a body of this size needs
static func grid_of(size: Vector3, bed: Vector3) -> Vector3i:
	var out := Vector3i(1, 1, 1)
	for a in 3:
		out[a] = maxi(1, ceili(size[a] / maxf(bed[a], 1.0) - 1e-6))
	return out


## the dialog's two plain lines: does the part fit, and what Split to fit will do. Cached by the record's content (the dialog refreshes often).
static func size_lines(rec: Dictionary, bed: Vector3, split_on: bool) -> Array:
	var key := hash(JSON.stringify(rec))
	if key != _size_key or _size_sizes.is_empty():
		_size_sizes = []
		var bo := MeshExport.bodies_of(rec)
		for b in bo["bodies"]:
			_size_sizes.append(bbox_of(b).size)
		_size_key = key
		if _size_sizes.is_empty():
			_size_key = 0
	var out := []
	var pieces := 0
	var big := 0
	for s in _size_sizes:
		var g := grid_of(s, bed)
		if not fits(s, bed):
			big += 1
			pieces += g.x * g.y * g.z
		else:
			pieces += 1
	var bedw := "%.0f x %.0f x %.0f mm" % [bed.x, bed.y, bed.z]
	if big == 0:
		out.append("OK    fits the printer bed (%s): nothing to cut" % bedw)
	elif split_on:
		out.append("OK    too big for the %s bed, so Split to fit cuts it into %d pieces, with %d dowel holes (%.0f mm wide, %.0f mm deep) on each cut face, and a separate %.1f mm dowel pin for each pair, to glue them aligned" % [bedw, pieces, DOWEL_COUNT, DOWEL_D, DOWEL_DEPTH, PIN_D])
	else:
		out.append("WARN  bigger than the printer bed (%s): tick Split to fit to cut it into pieces that fit, or your slicer will refuse it" % bedw)
	return out


## the cut-and-dowel result for the part record; a body that fits is returned as MeshExport would write it
static func split_rec(rec: Dictionary, bed: Vector3) -> Dictionary:
	var bo := MeshExport.bodies_of(rec)
	var bodies: Array = bo["bodies"]
	if bodies.is_empty():
		return {"bodies": [], "split": false, "pieces": 0, "cuts": [], "why": String(bo["why"])}
	var any_big := false
	for b in bodies:
		if not fits(bbox_of(b).size, bed):
			any_big = true
	if not any_big:
		return {"bodies": bodies, "split": false, "pieces": bodies.size(), "cuts": [], "why": ""}
	var res := Part.replay(rec, -1, {"keep": true})
	var ids: Array = res.get("ids", [])
	var out := []
	var cuts := []
	for i in bodies.size():
		var b: Dictionary = bodies[i]
		if fits(bbox_of(b).size, bed) or i >= ids.size():
			out.append(b)
			continue
		var made := _split_body(int(ids[i]), b, bed, cuts)
		for k in made.size():
			var pb: Dictionary = made[k]
			pb["name"] = "%s piece %d of %d" % [String(b["name"]), k + 1, made.size()]
			pb["color"] = b["color"]
			out.append(pb)
	for id in ids:
		KCad.release(int(id))
	var np := _add_pins(out, cuts, bodies)
	return {"bodies": out, "split": true, "pins": np, "pieces": out.size() - np, "cuts": cuts, "why": ""}


## one separate dowel pin (PIN_D wide, 2 x depth - 1 mm long) per hole pair, stood upright in a row beside the part so it prints on its own; appended to out
static func _add_pins(out: Array, cuts: Array, orig: Array) -> int:
	var box := AABB()
	for i in orig.size():
		box = bbox_of(orig[i]) if i == 0 else box.merge(bbox_of(orig[i]))
	var n := 0
	var total := 0
	for c in cuts:
		total += (c["holes"] as Array).size()
	for c in cuts:
		var len := 2.0 * float(c["depth"]) - 1.0
		for h in (c["holes"] as Array):
			n += 1
			var at := Vector3(box.end.x + 10.0 + float(n - 1) * (PIN_D + 4.0), box.get_center().y, box.position.z + len * 0.5)
			var id := _kcyl(at, 2, PIN_D * 0.5, len)
			var tb := _tess(id)
			KCad.release(id)
			if (tb["t"] as PackedInt32Array).size() > 0:
				tb["name"] = "Dowel pin %d of %d" % [n, total]
				tb["color"] = (orig[0] as Dictionary).get("color", Color(0.8, 0.8, 0.8))
				out.append(tb)
	return n


static func _kbox(lo: Vector3, hi: Vector3) -> int:
	var sz := hi - lo
	var b := KCad.box(sz.x / 1000.0, sz.z / 1000.0, sz.y / 1000.0)
	var t := KCad.translate(b, MeshExport.to_print_inv((lo + hi) * 0.5))
	KCad.release(b)
	return t


## a cylinder along printer axis a (0 X, 1 Y, 2 Z), centred on c (mm), length len (mm)
static func _kcyl(c: Vector3, a: int, r: float, len: float) -> int:
	var cy := KCad.cylinder(r / 1000.0, len / 1000.0)   # the kernel's own axis is z = printer -Y
	var turned := cy
	if a == 0:
		turned = KCad.rotate(cy, Vector3.UP, PI * 0.5)
	elif a == 2:
		turned = KCad.rotate(cy, Vector3.RIGHT, PI * 0.5)
	if turned != cy:
		KCad.release(cy)
	var t := KCad.translate(turned, MeshExport.to_print_inv(c))
	KCad.release(turned)
	return t


static func _tess(id: int) -> Dictionary:
	var soup := PackedVector3Array()
	var tm := KCad.tessellate(id, DEFLECT_M, ANGLE)
	if tm != null:
		for s in tm.get_surface_count():
			var arr := tm.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx = arr[Mesh.ARRAY_INDEX]
			if idx == null:
				soup.append_array(vs)
			else:
				for k in (idx as PackedInt32Array):
					soup.append(vs[k])
	return MeshExport.weld(soup)


## cut one kernel solid into the grid, put the dowel holes in; the pieces as bodies (cuts gets one entry a cut face)
static func _split_body(id: int, body: Dictionary, bed: Vector3, cuts: Array) -> Array:
	var box := bbox_of(body)
	var n := grid_of(box.size, bed)
	var ed := [[], [], []]   # the cut positions along each axis, ends included
	for a in 3:
		for i in n[a] + 1:
			(ed[a] as Array).append(box.position[a] + box.size[a] * float(i) / float(n[a]))
	var pieces := {}   # Vector3i cell -> kernel id
	for i in n.x:
		for j in n.y:
			for k in n.z:
				var cell := Vector3i(i, j, k)
				var lo := Vector3(ed[0][i], ed[1][j], ed[2][k])
				var hi := Vector3(ed[0][i + 1], ed[1][j + 1], ed[2][k + 1])
				for a in 3:   # the outer faces are pushed out 1 mm so they never share a face with the body's own
					if cell[a] == 0:
						lo[a] -= 1.0
					if cell[a] == n[a] - 1:
						hi[a] += 1.0
				var kb := _kbox(lo, hi)
				var p := KCad.intersect(id, kb)
				KCad.release(kb)
				if p != 0 and KCad.volume(p) > 1e-12:
					pieces[cell] = p
				elif p != 0:
					KCad.release(p)
	var r := DOWEL_D * 0.5
	for a in 3:
		var b := (a + 1) % 3
		var c := (a + 2) % 3
		for ci in range(1, n[a]):
			var pos: float = ed[a][ci]
			for bi in n[b]:
				for cj in n[c]:
					var lo_cell := Vector3i.ZERO
					lo_cell[a] = ci - 1
					lo_cell[b] = bi
					lo_cell[c] = cj
					var hi_cell := lo_cell
					hi_cell[a] = ci
					if not pieces.has(lo_cell) or not pieces.has(hi_cell):
						continue
					var depth := minf(DOWEL_DEPTH, 0.45 * minf(float(ed[a][ci]) - float(ed[a][ci - 1]), float(ed[a][ci + 1]) - float(ed[a][ci])))
					var b0: float = ed[b][bi]
					var b1: float = ed[b][bi + 1]
					var c0: float = ed[c][cj]
					var c1: float = ed[c][cj + 1]
					var long_is_b := (b1 - b0) >= (c1 - c0)
					var holes := []
					for s in SITES:
						if holes.size() >= DOWEL_COUNT:
							break
						var fb: float = s.x if long_is_b else s.y
						var fc: float = s.y if long_is_b else s.x
						var ctr := Vector3.ZERO
						ctr[a] = pos
						ctr[b] = b0 + (b1 - b0) * fb
						ctr[c] = c0 + (c1 - c0) * fc
						if ctr[b] - r < b0 + 1.0 or ctr[b] + r > b1 - 1.0 or ctr[c] - r < c0 + 1.0 or ctr[c] + r > c1 - 1.0:
							continue
						var apart := true
						for h in holes:
							if (h as Vector3).distance_to(ctr) < 3.0 * DOWEL_D:
								apart = false
						if not apart:
							continue
						# only where the hole is in solid material on both sides of the cut
						var cyl := _kcyl(ctr, a, r, 2.0 * depth)
						var common := KCad.intersect(id, cyl)
						var inside := KCad.volume(common) / (PI * r * r * 2.0 * depth * 1e-9) if common != 0 else 0.0
						if common != 0:
							KCad.release(common)
						if inside < 0.98:
							KCad.release(cyl)
							continue
						for cell2 in [lo_cell, hi_cell]:
							var cut := KCad.cut(int(pieces[cell2]), cyl)
							if cut != 0:
								KCad.release(int(pieces[cell2]))
								pieces[cell2] = cut
						KCad.release(cyl)
						holes.append(ctr)
					cuts.append({"axis": a, "pos": pos, "holes": holes, "dia": DOWEL_D, "depth": depth, "cells": [lo_cell, hi_cell]})
	var keys := pieces.keys()
	keys.sort_custom(func(x: Vector3i, y: Vector3i): return x.z < y.z or (x.z == y.z and (x.y < y.y or (x.y == y.y and x.x < y.x))))
	var out := []
	for key in keys:
		var tb := _tess(int(pieces[key]))
		if (tb["t"] as PackedInt32Array).size() > 0:
			out.append(tb)
		KCad.release(int(pieces[key]))
	return out


## the Export dialog's road with Split to fit ticked. fmt "stl" | "3mf". Answers
## {"ok", "path" (the first file), "paths", "why", "report", "text", "pieces", "split", "cuts"}
static func export_part(rec: Dictionary, fmt: String, dir: String, bed: Vector3) -> Dictionary:
	var sp := split_rec(rec, bed)
	var bodies: Array = sp["bodies"]
	if bodies.is_empty():
		return {"ok": false, "path": "", "paths": [], "why": String(sp["why"]), "report": {}, "text": "NOT DONE: " + String(sp["why"]), "pieces": 0, "split": false, "cuts": []}
	if not bool(sp["split"]):
		var r := MeshExport.export_part(rec, fmt, dir)
		r["paths"] = [r["path"]] if String(r["path"]) != "" else []
		r["pieces"] = bodies.size()
		r["split"] = false
		r["cuts"] = []
		r["text"] = String(r["text"]) + ". It fits the %.0f x %.0f x %.0f mm bed, so it was not cut" % [bed.x, bed.y, bed.z]
		return r
	var rep := MeshExport.report(bodies)
	var gdir := ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(gdir)
	var name := String(rec.get("name", "Part"))
	var paths := []
	var e := OK
	if fmt == "stl":
		for b in bodies:
			var p := "%s/%s.stl" % [gdir, MeshExport.stem(String(b["name"]))]
			e = MeshExport.write_stl(p, [b])
			if e != OK:
				break
			paths.append(p)
	else:
		var p3 := "%s/%s.3mf" % [gdir, MeshExport.stem(name)]
		e = MeshExport.write_3mf(p3, bodies, name)
		if e == OK:
			paths.append(p3)
	if e != OK:
		return {"ok": false, "path": "", "paths": [], "why": error_string(e), "report": rep, "text": "NOT DONE: the file could not be written (%s). Check that the folder is writable, then export again" % error_string(e), "pieces": bodies.size(), "split": true, "cuts": sp["cuts"]}
	var nh := 0
	for c in (sp["cuts"] as Array):
		nh += (c["holes"] as Array).size()
	var msg := "exported %s: cut into %d pieces to fit the %.0f x %.0f x %.0f mm bed, with %d dowel holes (%.1f mm wide, 10 mm deep) on the cut faces and %d separate dowel pins (%.1f mm wide, %.1f mm clearance) to glue the pieces aligned" % [
		(paths[0] as String).get_file() if fmt != "stl" else "%d STL files" % paths.size(), int(sp["pieces"]), bed.x, bed.y, bed.z, nh * 2, DOWEL_D, int(sp.get("pins", 0)), PIN_D, CLEARANCE]
	return {"ok": true, "path": paths[0], "paths": paths, "why": "", "report": rep, "text": msg, "pieces": int(sp["pieces"]), "pins": int(sp.get("pins", 0)), "split": true, "cuts": sp["cuts"]}
