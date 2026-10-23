class_name KMeshLathe
extends RefCounted
## B11 (docs/ROADMAP_400.md): SPIN / SCREW / LATHE. A profile (a selected edge chain of the mesh, or a typed list of
## (radius, height) points) is revolved around an axis through a centre (the 3D cursor or the origin).
##   angle    degrees per turn (360 = a full turn: the last ring IS the first, the seam welded, no doubled verts)
##   steps    segments per turn (per `angle`)
##   screw    metres risen along the axis per 360 deg (Blender's Screw offset); turns: how many times round. A screw is
##            never welded (the end ring sits `screw` above the start one): total rise = screw x turns x angle / 360
## POLES: a profile point on the axis (closer than AXIS_EPS) is ONE vertex shared by every step (when there is no
##   screw): the faces beside it are triangles, and a profile segment lying ON the axis makes no face at all, so there is
##   never a zero-area face. With a screw the axis point rises, so it stays a vertex per step (the quads have area).
## WINDING: a closed result (a profile that closes or touches the axis at both ends, 360 deg) is turned so its signed
##   volume is positive (outward); an open one so its area-weighted normals point away from the axis on average.
## UVs (corner attribute "uv", KMeshUV's channel): u along the angle (0 at the start, 1 back at the seam: the seam's
##   corners carry u = 1, which is why UVs are per corner), v along the profile (arc length / total). A pole corner takes
##   the middle u of its triangle.
## Ops: mesh_tools "op:lathe" (the selected edge chain), "op:lathe_typed" (the typed profile); the panel is
## scripts/kmesh_curves_ui.gd (fields live until the next edit, like B09's primitives: one undo step).

const AXIS_EPS := 1e-6   # m: a profile point this close to the axis is on it (a pole)

static var last_error := ""


## the options with their defaults filled
static func opts_of(o: Dictionary) -> Dictionary:
	var d := {"axis": Vector3.UP, "center": Vector3.ZERO, "angle": 360.0, "steps": 32, "screw": 0.0, "turns": 1,
		"closed_profile": false}
	d.merge(o, true)
	return d


## one turn is welded: a full 360 with no rise
static func welded(o: Dictionary) -> bool:
	var d := opts_of(o)
	return absf(absf(float(d["angle"])) - 360.0) < 1e-6 and absf(float(d["screw"])) < 1e-12


## THE LATHE: profile points (mesh space) revolved by opts (see opts_of / the header). null + last_error on bad input
static func spin(profile: PackedVector3Array, opts := {}) -> KMesh:
	last_error = ""
	var o := opts_of(opts)
	var ax := (o["axis"] as Vector3)
	if ax.length_squared() < 1e-20:
		last_error = "the lathe axis has no direction. Pick X, Y or Z."
		return null
	ax = ax.normalized()
	var c: Vector3 = o["center"]
	var closed_p := bool(o["closed_profile"])
	var np := profile.size()
	if np < 2:
		last_error = "a profile needs at least 2 points (select a chain of edges, or type two or more r,y pairs)."
		return null
	var weld := welded(o)
	var turns := 1 if weld else maxi(1, int(o["turns"]))
	var steps := maxi(3 if weld else 1, int(o["steps"]))
	var segs := steps * turns
	var total_a := deg_to_rad(float(o["angle"])) * turns
	var rise := float(o["screw"]) * float(o["angle"]) / 360.0 * turns
	var rings := segs if weld else segs + 1
	# the profile in axis terms: height along the axis, radial vector, on the axis or not
	var hh := PackedFloat64Array()
	var rad := PackedVector3Array()
	var pole := PackedByteArray()
	for p in profile:
		var q := p - c
		var h := q.dot(ax)
		var rv := q - ax * h
		hh.append(h)
		rad.append(rv)
		pole.append(1 if rv.length() < AXIS_EPS else 0)
	var poles := absf(rise) < 1e-12   # a screw lifts the axis points: they stay one vert per step
	# arc length along the profile (v)
	var arc := PackedFloat64Array([0.0])
	for j in range(1, np):
		arc.append(arc[j - 1] + profile[j].distance_to(profile[j - 1]))
	var arc_total := arc[np - 1] + (profile[np - 1].distance_to(profile[0]) if closed_p else 0.0)
	if arc_total <= 1e-12:
		last_error = "the profile has no length (its points all coincide)."
		return null
	# verts
	var vs := PackedVector3Array()
	var id := []   # id[j] = PackedInt32Array per ring, or a single pole index
	for j in np:
		var row := PackedInt32Array()
		if pole[j] == 1 and poles:
			row.append(vs.size())
			vs.append(c + ax * hh[j])
		else:
			for i in rings:
				var f := float(i) / float(segs)
				vs.append(c + Basis(ax, total_a * f) * rad[j] + ax * (hh[j] + rise * f))
				row.append(vs.size() - 1)
		id.append(row)
	var vid := func(i: int, j: int) -> int:
		var row: PackedInt32Array = id[j]
		if row.size() == 1:
			return row[0]
		return row[i % segs] if weld else row[i]
	# faces + UVs: a quad per profile segment per step; a pole collapses it to a triangle, two poles drop it
	var fs: Array = []
	var uvs := PackedVector2Array()
	var nseg := np if closed_p else np - 1
	for j in nseg:
		var k := (j + 1) % np
		if profile[j].distance_to(profile[k]) < 1e-12:
			continue
		var pj := (id[j] as PackedInt32Array).size() == 1
		var pk := (id[k] as PackedInt32Array).size() == 1
		if pj and pk:
			continue   # a segment on the axis sweeps no area
		var vj := arc[j] / arc_total
		var vk := (arc[k] if k != 0 else arc_total) / arc_total
		for i in segs:
			var u0 := float(i) / segs
			var u1 := float(i + 1) / segs
			var um := (u0 + u1) * 0.5
			var f := PackedInt32Array()
			var corners := [[vid.call(i, j), Vector2(um if pj else u0, vj)], [vid.call(i + 1, j), Vector2(um if pj else u1, vj)],
				[vid.call(i + 1, k), Vector2(um if pk else u1, vk)], [vid.call(i, k), Vector2(um if pk else u0, vk)]]
			var fu := PackedVector2Array()
			for cr in corners:
				if f.size() > 0 and f[f.size() - 1] == int(cr[0]):
					continue
				f.append(int(cr[0]))
				fu.append(cr[1])
			if f.size() > 1 and f[0] == f[f.size() - 1]:
				f.resize(f.size() - 1)
				fu.resize(fu.size() - 1)
			if f.size() < 3:
				continue
			fs.append(f)
			uvs.append_array(fu)
	if fs.is_empty():
		last_error = "the profile sweeps no surface (every segment lies on the axis)."
		return null
	var km := KMesh.new().from_arrays(vs, fs)
	km.add_attr("uv", KMesh.AD_CORNER, TYPE_VECTOR2)
	km.set_attr_data("uv", uvs)
	if _inward(km, ax, c):
		flip(km)
	return km


## true when the faces point the wrong way: a closed mesh by its signed volume, an open one by its normals against the
## direction away from the axis (area-weighted); a flat disc (no radial lean) by the axis direction
static func _inward(km: KMesh, ax: Vector3, c: Vector3) -> bool:
	if km.is_closed():
		return KMeshValidate._volume(km) < 0.0
	var s := 0.0
	var sa := 0.0
	for fi in km.face_count():
		var n := km._newell(fi)   # length = 2 x area
		var q := km.face_center(fi) - c
		var rv := q - ax * q.dot(ax)
		if rv.length_squared() > 1e-20:
			s += n.dot(rv.normalized())
		sa += n.dot(ax)
	if absf(s) > 1e-12:
		return s < 0.0
	return sa < 0.0


## every face reversed (and its UV corners with it)
static func flip(km: KMesh) -> void:
	var uv: PackedVector2Array = km.attr_data("uv") if km.has_attr("uv") else PackedVector2Array()
	var nf: Array = []
	var nuv := PackedVector2Array()
	var base := 0
	for f in km.faces:
		var g := PackedInt32Array(f)
		g.reverse()
		nf.append(g)
		if not uv.is_empty():
			for i in g.size():
				nuv.append(uv[base + g.size() - 1 - i])
		base += g.size()
	var a := km.attrs
	km.attrs = {}
	km.from_arrays(km.verts, nf)
	km.attrs = a
	if not uv.is_empty():
		km.set_attr_data("uv", nuv)


# ---------------------------------------------------------------- profiles

## the selected edges as one ordered chain: {"verts": PackedInt32Array, "closed": bool} or {} + last_error (no edges,
## a branch, two pieces)
static func chain(edges: Array) -> Dictionary:
	last_error = ""
	if edges.is_empty():
		last_error = "no edges selected. Select a chain of edges (2, then click; Shift+click adds) for the profile."
		return {}
	var adj := {}
	for e in edges:
		var a: int = (e as Vector2i).x
		var b: int = (e as Vector2i).y
		if a == b:
			continue
		for pr in [[a, b], [b, a]]:
			if not adj.has(pr[0]):
				adj[pr[0]] = []
			if not (adj[pr[0]] as Array).has(pr[1]):
				adj[pr[0]].append(pr[1])
	var start := -1
	for v in adj:
		var dg: int = (adj[v] as Array).size()
		if dg > 2:
			last_error = "the selected edges branch at a vertex (%d edges meet there). Select one chain, end to end." % dg
			return {}
		if dg == 1 and (start < 0 or v < start):
			start = v
	var closed := start < 0
	if closed:
		start = adj.keys().min()
	var out := PackedInt32Array([start])
	var prev := -1
	var cur: int = start
	while true:
		var nxt := -1
		for w in adj[cur]:
			if w != prev and not (closed and w == start and out.size() < 3):
				nxt = w
				break
		if nxt < 0 or nxt == start:
			break
		out.append(nxt)
		prev = cur
		cur = nxt
	if out.size() != adj.size():
		last_error = "the selected edges are %s pieces. Select one connected chain." % ("several" if out.size() < adj.size() else "odd")
		return {}
	return {"verts": out, "closed": closed}


## a typed profile: "r,y r,y ..." in cm (radius from the axis, height along it), pairs split by spaces or ';'; the word
## "closed" (or a last point equal to the first) closes it. -> {"pts": PackedVector2Array (m), "closed"} or {} + last_error
static func parse(text: String) -> Dictionary:
	last_error = ""
	var t := text.to_lower().replace(";", " ").replace("\n", " ")
	var closed := t.contains("closed")
	t = t.replace("closed", " ")
	var pts := PackedVector2Array()
	for tok in t.split(" ", false):
		var xy := tok.split(",", false)
		if xy.size() != 2 or not xy[0].strip_edges().is_valid_float() or not xy[1].strip_edges().is_valid_float():
			last_error = "\"%s\" is not an r,y pair. Type pairs in cm like: 10,0 20,0 20,10 10,10 closed" % tok
			return {}
		pts.append(Vector2(float(xy[0]), float(xy[1])) / 100.0)
	if pts.size() >= 3 and pts[0].distance_to(pts[pts.size() - 1]) < 1e-9:
		pts.resize(pts.size() - 1)
		closed = true
	if pts.size() < 2:
		last_error = "a profile needs at least 2 points. Type pairs in cm like: 0,0 10,0 10,20 0,20"
		return {}
	return {"pts": pts, "closed": closed}


## (radius, height) pairs placed in mesh space around the axis through c: radius along a direction square to the axis
static func place(pts: PackedVector2Array, ax: Vector3, c: Vector3) -> PackedVector3Array:
	ax = ax.normalized()
	var side := Vector3.RIGHT if absf(ax.x) < 0.9 else Vector3.UP
	side = (side - ax * side.dot(ax)).normalized()
	var out := PackedVector3Array()
	for p in pts:
		out.append(c + side * p.x + ax * p.y)
	return out
