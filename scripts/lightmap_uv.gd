class_name LightmapUV
extends RefCounted
## LightmapUV (C09, complaint #28): a second UV set (ARRAY_TEX_UV2, glTF TEXCOORD_1) for baked lighting, with NO overlaps, on request.
## Engines (Unreal's "overlapping UVs" error) want every surface point to own its own lightmap texel; the first UV set may tile.
## METHOD: triangles are grouped into CHARTS by flood fill over shared edges (vertices welded by position), a triangle joining a chart
##   when its normal is within `angle` (default 20 deg) of the chart's seed normal, so a chart's triangles all face the chart's plane
##   (dot > 0) and its planar projection cannot fold over itself. Each chart is projected on its area-weighted normal's plane, all
##   charts get ONE scale (equal texel density), and the boxes are shelf-packed into 0..1 with `pad` between boxes and at the border.
## The output mesh is UNWELDED (3 own vertices a triangle) so a chart edge can carry two UV values; surfaces with bones are left as they were.
## First UV set, positions, normals, colours and materials are copied through untouched.

const ANGLE := 20.0
const PAD := 0.004


static func has_uv2(mesh: Mesh) -> bool:
	for s in mesh.get_surface_count():
		if mesh.surface_get_arrays(s)[Mesh.ARRAY_TEX_UV2] != null:
			return true
	return false


## a copy of mesh with UV2. Returns {"mesh", "charts", "tris", "skipped" (surfaces left alone)}
static func generate(mesh: Mesh, angle := ANGLE, pad := PAD) -> Dictionary:
	var out := ArrayMesh.new()
	var charts := 0
	var tris := 0
	var skipped := 0
	for si in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(si)
		var mat := mesh.surface_get_material(si)
		var pt: Mesh.PrimitiveType = mesh.surface_get_primitive_type(si)
		var V = arr[Mesh.ARRAY_VERTEX]
		if pt != Mesh.PRIMITIVE_TRIANGLES or V == null or arr[Mesh.ARRAY_BONES] != null:
			out.add_surface_from_arrays(pt, arr)
			if mat != null:
				out.surface_set_material(out.get_surface_count() - 1, mat)
			skipped += 1
			continue
		var r := _surface(arr, angle, pad)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, r["arrays"])
		if mat != null:
			out.surface_set_material(out.get_surface_count() - 1, mat)
		charts += int(r["charts"])
		tris += int(r["tris"])
	return {"mesh": out, "charts": charts, "tris": tris, "skipped": skipped}


## export-list form (ExportBudget style): [{"name", "mesh", "xf", ...}] -> the same list with UV2 meshes
static func apply_list(objs: Array) -> Array:
	var out := []
	for o in objs:
		var c: Dictionary = (o as Dictionary).duplicate()
		if c.get("mesh") is Mesh and not has_uv2(c["mesh"]):
			c["mesh"] = generate(c["mesh"])["mesh"]
		out.append(c)
	return out


static func _surface(arr: Array, angle: float, pad: float) -> Dictionary:
	var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ix = arr[Mesh.ARRAY_INDEX]
	var idx: PackedInt32Array
	if ix == null:
		idx = PackedInt32Array()
		for i in V.size():
			idx.append(i)
	else:
		idx = ix
	var nt := idx.size() / 3
	var weld := {}
	var wid := PackedInt32Array()
	for i in V.size():
		var k := Vector3i((V[i] * 10000.0).round())
		if not weld.has(k):
			weld[k] = weld.size()
		wid.append(weld[k])
	var nrm := PackedVector3Array()
	var area := PackedFloat32Array()
	var edge := {}
	for t in nt:
		var a := V[idx[t * 3]]
		var b := V[idx[t * 3 + 1]]
		var c := V[idx[t * 3 + 2]]
		var cr := (b - a).cross(c - a)
		area.append(cr.length() * 0.5)
		nrm.append(cr.normalized() if cr.length() > 1e-14 else Vector3.UP)
		for e in 3:
			var p := wid[idx[t * 3 + e]]
			var q := wid[idx[t * 3 + (e + 1) % 3]]
			var key := Vector2i(mini(p, q), maxi(p, q))
			if not edge.has(key):
				edge[key] = []
			edge[key].append(t)
	var cosl := cos(deg_to_rad(angle))
	var chart := PackedInt32Array()
	chart.resize(nt)
	chart.fill(-1)
	var cl := []   # per chart: Array of triangles
	for s in nt:
		if chart[s] >= 0:
			continue
		var id := cl.size()
		var tl := [s]
		chart[s] = id
		var q := [s]
		while not q.is_empty():
			var t: int = q.pop_back()
			for e in 3:
				var p := wid[idx[t * 3 + e]]
				var pp := wid[idx[t * 3 + (e + 1) % 3]]
				for u in edge[Vector2i(mini(p, pp), maxi(p, pp))]:
					if chart[u] < 0 and nrm[u].dot(nrm[s]) >= cosl:
						chart[u] = id
						tl.append(u)
						q.append(u)
		cl.append(tl)
	# project each chart
	var pos2 := PackedVector2Array()   # per triangle corner (nt * 3)
	pos2.resize(nt * 3)
	var boxes := []
	for id in cl.size():
		var n := Vector3.ZERO
		for t in cl[id]:
			n += nrm[t] * area[t]
		n = n.normalized() if n.length() > 1e-12 else nrm[cl[id][0]]
		var ax := Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT
		var ux := ax.cross(n).normalized()
		var uy := n.cross(ux)
		var lo := Vector2(1e30, 1e30)
		var hi := Vector2(-1e30, -1e30)
		for t in cl[id]:
			for e in 3:
				var p := V[idx[t * 3 + e]]
				var q2 := Vector2(p.dot(ux), p.dot(uy))
				pos2[t * 3 + e] = q2
				lo = lo.min(q2)
				hi = hi.max(q2)
		boxes.append({"lo": lo, "size": hi - lo})
	var place := _pack(boxes, pad)
	var s: float = place["scale"]
	var V2 := PackedVector3Array()
	var N2 := PackedVector3Array()
	var T1 := PackedVector2Array()
	var T2 := PackedVector2Array()
	var C2 := PackedColorArray()
	var Nn = arr[Mesh.ARRAY_NORMAL]
	var Tt = arr[Mesh.ARRAY_TEX_UV]
	var Cc = arr[Mesh.ARRAY_COLOR]
	for t in nt:
		var id := chart[t]
		var org: Vector2 = place["origin"][id]
		for e in 3:
			var vi := idx[t * 3 + e]
			V2.append(V[vi])
			if Nn != null:
				N2.append(Nn[vi])
			if Tt != null:
				T1.append(Tt[vi])
			if Cc != null:
				C2.append(Cc[vi])
			T2.append(org + ((pos2[t * 3 + e] - (boxes[id]["lo"] as Vector2)) * s))
	var res := []
	res.resize(Mesh.ARRAY_MAX)
	res[Mesh.ARRAY_VERTEX] = V2
	if Nn != null:
		res[Mesh.ARRAY_NORMAL] = N2
	if Tt != null:
		res[Mesh.ARRAY_TEX_UV] = T1
	if Cc != null:
		res[Mesh.ARRAY_COLOR] = C2
	res[Mesh.ARRAY_TEX_UV2] = T2
	return {"arrays": res, "charts": cl.size(), "tris": nt}


## shelf packing at the largest scale (by shrinking) where every padded box fits in 0..1: {"scale", "origin": per box}
static func _pack(boxes: Array, pad: float) -> Dictionary:
	var order := range(boxes.size())
	order.sort_custom(func(a, b): return (boxes[a]["size"] as Vector2).y > (boxes[b]["size"] as Vector2).y)
	var tot := 0.0
	for b in boxes:
		tot += (b["size"] as Vector2).x * (b["size"] as Vector2).y
	var s := sqrt(0.7 / maxf(tot, 1e-12))
	for it in 200:
		var org := []
		org.resize(boxes.size())
		var x := pad
		var y := pad
		var row := 0.0
		var okf := true
		for i in order:
			var sz: Vector2 = (boxes[i]["size"] as Vector2) * s
			if x + sz.x + pad > 1.0 and x > pad:
				x = pad
				y += row + pad
				row = 0.0
			if x + sz.x + pad > 1.0 or y + sz.y + pad > 1.0:
				okf = false
				break
			org[i] = Vector2(x, y)
			x += sz.x + pad
			row = maxf(row, sz.y)
		if okf:
			return {"scale": s, "origin": org}
		s *= 0.93
	return {"scale": s, "origin": range(boxes.size()).map(func(i): return Vector2(pad, pad))}
