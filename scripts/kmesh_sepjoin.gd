class_name KMeshSepJoin
extends RefCounted
## B17 (docs/ROADMAP_400.md): SEPARATE / JOIN PARTS and SET ORIGIN in the model preview. The preview edits ONE KMesh, so
## there are no objects: a PART is what B10 (kmesh_boolean.gd) calls one, a connected component (faces sharing a vertex),
## and a join ties components together. The tie is a face channel PART ("part", float): components that carry the same
## part id on any face are one part. Without the channel every component is its own part (B10's notion exactly).
##   separate        the selected faces become their own part: the verts they share with the other faces are doubled
##                   (the copies go at the END of the vertex list, so every old vertex keeps its index and position) and
##                   the selected faces take a new part id. Face and corner order never change. Selection: face mode the
##                   faces; vert / edge mode the faces whose every vertex is selected (Blender's rule)
##   separate_loose  every connected component its own part (undoes the ties of a join)
##   join            the parts holding the selection become one (nothing selected, or only one part: every part). No
##                   vertex moves. join_weld also welds BORDER verts (on an open edge) of different joined parts lying
##                   within WELD (0.1 mm) of each other: the lower index stays, the higher ones are dropped (so a separate
##                   then a weld gives the mesh back exactly)
##   origin_*        the mesh's ORIGIN (KMesh.origin) to the geometry centre (the centre of the bounding box), to the
##                   3D cursor (B14, KMeshPivot.cursor), or to the bottom centre (the box centre in x / z, the lowest y)
## ORIGIN: the mesh has no object transform, so the origin is a POINT IN MESH SPACE (the KMeshView's local coordinates)
## kept on the KMesh, saved in the .kmesh ("origin", only when not 0,0,0) and carried by KMeshUndo. The geometry never
## moves when it is set (Blender's "Origin to ...", not "Geometry to Origin"). It is where the mesh "is": the point a
## pivot, an export (the file's 0,0,0) or a size readout (B27) takes the mesh from; world point: origin_world(). Default
## (0,0,0), which for the test cube is its centre.
## Attributes (A09) are carried: vert channels copy to the doubled verts, face and corner channels stay on their faces,
## edge channels follow their edge (a doubled border edge: both copies; a welded pair: the lower index's). Shape keys:
## refused (the key deltas are per vertex), say so. Each op is one KMeshUndo step. Tests: tests/sepjoin_test.gd.

const PART := "part"
const WELD := 1e-4   # join_weld: border verts this close (m) become one

## message of the last refused call (empty after a success)
static var last_error := ""


## the parts of m as face lists (each ascending), in order of their first face
static func parts(m: KMesh) -> Array:
	var comps: Array = KMeshBoolean.components(m)
	if not m.has_attr(PART) or m.attr_info(PART)["domain"] != KMesh.AD_FACE:
		return comps
	var pd = m.attr_data(PART)
	var up := PackedInt32Array()
	up.resize(comps.size())
	for i in comps.size():
		up[i] = i
	var fnd := func(i: int) -> int:
		while up[i] != i:
			up[i] = up[up[i]]
			i = up[i]
		return i
	var owner := {}
	for ci in comps.size():
		for fi in (comps[ci] as PackedInt32Array):
			var id: float = pd[fi]
			if owner.has(id):
				var a: int = fnd.call(ci)
				var b: int = fnd.call(owner[id])
				if a != b:
					up[maxi(a, b)] = mini(a, b)
			else:
				owner[id] = ci
	var by := {}
	var out: Array = []
	for ci in comps.size():
		var r: int = fnd.call(ci)
		if not by.has(r):
			by[r] = out.size()
			out.append(PackedInt32Array())
		var l: PackedInt32Array = out[by[r]]
		l.append_array(comps[ci])
		out[by[r]] = l
	for i in out.size():
		var l: PackedInt32Array = out[i]
		l.sort()
		out[i] = l
	return out


## the part channel, made when missing: one id per part as it is now
static func _ensure_parts(m: KMesh) -> void:
	if m.has_attr(PART) and m.attr_info(PART)["domain"] == KMesh.AD_FACE:
		return
	m.remove_attr(PART)
	var ps := parts(m)
	m.add_attr(PART, KMesh.AD_FACE, TYPE_FLOAT, 0.0)
	var pd: PackedFloat32Array = m.attr_data(PART)
	for i in ps.size():
		for fi in (ps[i] as PackedInt32Array):
			pd[fi] = float(i)
	m.set_attr_data(PART, pd)


## the faces a selection names: face mode its faces; vert / edge mode the faces whose every vertex is selected
static func sel_faces(m: KMesh, sel) -> PackedInt32Array:
	var out := PackedInt32Array()
	if sel == null:
		return out
	if sel.mode == KMeshSelect.FACE:
		for fi in sel.faces:
			out.append(int(fi))
		out.sort()
		return out
	var vs := {}
	for v in sel.verts:
		vs[v] = true
	for e in sel.edges:
		vs[(e as Vector2i).x] = true
		vs[(e as Vector2i).y] = true
	if vs.is_empty():
		return out
	for fi in m.face_count():
		var all := true
		for v in (m.faces[fi] as PackedInt32Array):
			if not vs.has(v):
				all = false
				break
		if all:
			out.append(fi)
	return out


## new topology in place (same face count and order, same corner count): verts V, faces F; src_v[i] = the old vert of new
## vert i. Every channel carried (see the header). to_new (a weld): old vert -> new vert, so an edge of welded verts finds
## its old edge through either of them (the lower old edge index wins)
static func _rebuild(m: KMesh, V: PackedVector3Array, F: Array, src_v: PackedInt32Array, to_new := PackedInt32Array()) -> void:
	var old_e: Array = m.edges()
	var e_of := {}
	for i in old_e.size():
		var e: Vector2i = old_e[i]
		if not to_new.is_empty():
			e = Vector2i(mini(to_new[e.x], to_new[e.y]), maxi(to_new[e.x], to_new[e.y]))
		if not e_of.has(e):
			e_of[e] = i
	var keep := m.attr_snapshot()
	m.attrs = {}   # sized for the old mesh: from_arrays must not fit them
	m.from_arrays(V, F)
	m.attrs = keep
	if keep.is_empty():
		return
	var src_e := PackedInt32Array()
	for e in m.edges():
		if not to_new.is_empty():
			src_e.append(int(e_of.get(e, -1)))
			continue
		var a: int = src_v[(e as Vector2i).x]
		var b: int = src_v[(e as Vector2i).y]
		src_e.append(int(e_of.get(Vector2i(mini(a, b), maxi(a, b)), -1)))
	m.attr_remap(src_v, null, null, src_e)


## the selected faces `flist` become their own part. {"faces", "doubled"} or {} with last_error set
static func separate(m: KMesh, flist: PackedInt32Array) -> Dictionary:
	last_error = ""
	flist = flist.duplicate()
	flist.sort()
	if flist.is_empty():
		last_error = "nothing selected to separate: select the faces (3) that should become their own part"
		return {}
	if flist.size() >= m.face_count():
		last_error = "every face is selected: separate needs some faces left behind (select only the faces to split off)"
		return {}
	var insel := {}
	for fi in flist:
		insel[fi] = true
	var used_out := {}
	for fi in m.face_count():
		if not insel.has(fi):
			for v in (m.faces[fi] as PackedInt32Array):
				used_out[v] = true
	var n := m.vert_count()
	var V := m.verts.duplicate()
	var src_v := PackedInt32Array()
	src_v.resize(n)
	for i in n:
		src_v[i] = i
	var dup := {}
	var F: Array = m.faces.duplicate()
	for fi in flist:
		var f: PackedInt32Array = (m.faces[fi] as PackedInt32Array).duplicate()
		for c in f.size():
			var v := f[c]
			if used_out.has(v):
				if not dup.has(v):
					dup[v] = V.size()
					V.append(m.verts[v])
					src_v.append(v)
				f[c] = dup[v]
		F[fi] = f
	var whole := dup.is_empty()
	if whole:   # already apart: is it already a part of its own?
		for p in parts(m):
			if p == flist:
				last_error = "the selection is already a part of its own (%d faces): nothing to separate" % flist.size()
				return {}
	_ensure_parts(m)
	var pd: PackedFloat32Array = m.attr_data(PART)
	var nid := -INF
	for x in pd:
		nid = maxf(nid, x)
	nid += 1.0
	for fi in flist:
		pd[fi] = nid
	m.set_attr_data(PART, pd)
	if not whole:
		_rebuild(m, V, F, src_v)
	return {"faces": flist.size(), "doubled": dup.size()}


## every connected component its own part. Returns the number of parts after (last_error set when nothing changed)
static func separate_loose(m: KMesh) -> int:
	last_error = ""
	var comps: Array = KMeshBoolean.components(m)
	if parts(m).size() == comps.size():
		last_error = "every loose part is already a part of its own (%d)" % comps.size()
		return comps.size()
	_ensure_parts(m)
	var pd: PackedFloat32Array = m.attr_data(PART)
	for ci in comps.size():
		for fi in (comps[ci] as PackedInt32Array):
			pd[fi] = float(ci)
	m.set_attr_data(PART, pd)
	return comps.size()


## the parts holding the selection join into one (fewer than two held: every part). weld: border verts of different
## joined parts within WELD become one. {"parts" (how many were joined), "welded"} or {} with last_error set
static func join(m: KMesh, sel = null, weld := false, tol := WELD) -> Dictionary:
	last_error = ""
	var ps := parts(m)
	if ps.size() < 2:
		last_error = "there is only one part: add a primitive (Add primitive) or separate some faces first"
		return {}
	var hit := {}
	if sel != null:
		for v in sel.verts:
			hit[v] = true
		for e in sel.edges:
			hit[(e as Vector2i).x] = true
			hit[(e as Vector2i).y] = true
		for fi in sel.faces:
			for v in (m.faces[fi] as PackedInt32Array):
				hit[v] = true
	var chosen: Array = []
	for p in ps:
		var held := false
		for fi in (p as PackedInt32Array):
			for v in (m.faces[fi] as PackedInt32Array):
				if hit.has(v):
					held = true
					break
			if held:
				break
		if held:
			chosen.append(p)
	if chosen.size() < 2:
		chosen = ps
	_ensure_parts(m)
	var pd: PackedFloat32Array = m.attr_data(PART)
	var id := INF
	for p in chosen:
		for fi in (p as PackedInt32Array):
			id = minf(id, pd[fi])
	var part_of := PackedInt32Array()   # vert -> index in chosen (-1 = not joined)
	part_of.resize(m.vert_count())
	part_of.fill(-1)
	for pi in chosen.size():
		for fi in (chosen[pi] as PackedInt32Array):
			pd[fi] = id
			for v in (m.faces[fi] as PackedInt32Array):
				part_of[v] = pi
	m.set_attr_data(PART, pd)
	var welded := 0
	if weld:
		welded = _weld(m, part_of, tol)
	return {"parts": chosen.size(), "welded": welded}


## border verts of different joined parts within tol: the higher index goes, its faces take the lower one
static func _weld(m: KMesh, part_of: PackedInt32Array, tol: float) -> int:
	var border := {}
	for e in m.edges():
		if m.is_boundary_edge((e as Vector2i).x, (e as Vector2i).y):
			border[(e as Vector2i).x] = true
			border[(e as Vector2i).y] = true
	var grid := {}
	var to := PackedInt32Array()
	to.resize(m.vert_count())
	for i in to.size():
		to[i] = i
	var ids: Array = border.keys()
	ids.sort()
	var n := 0
	for v in ids:
		if part_of[v] < 0:
			continue
		var p := m.verts[v]
		var c := Vector3i((p / tol).floor())
		var tgt := -1
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					for w in grid.get(c + Vector3i(dx, dy, dz), []):
						if tgt < 0 and part_of[w] != part_of[v] and m.verts[w].distance_to(p) <= tol:
							tgt = w
		if tgt >= 0:
			to[v] = tgt
			n += 1
		else:
			if not grid.has(c):
				grid[c] = []
			grid[c].append(v)
	if n == 0:
		return 0
	var newi := PackedInt32Array()
	newi.resize(to.size())
	var V := PackedVector3Array()
	var src_v := PackedInt32Array()
	for i in to.size():
		if to[i] == i:
			newi[i] = V.size()
			V.append(m.verts[i])
			src_v.append(i)
	var F: Array = []
	for f in m.faces:
		var g := PackedInt32Array()
		for v in (f as PackedInt32Array):
			g.append(newi[to[v]])
		F.append(g)
	var to_new := PackedInt32Array()
	to_new.resize(to.size())
	for i in to.size():
		to_new[i] = newi[to[i]]
	_rebuild(m, V, F, src_v, to_new)
	return n


## the origin point (mesh space) for a mode: "geometry" the box centre, "bottom" the box centre at the lowest y,
## "cursor" the given point (the 3D cursor already in mesh space)
static func origin_for(m: KMesh, how: String, cursor := Vector3.ZERO) -> Vector3:
	if how == "cursor" or m.vert_count() == 0:
		return cursor if how == "cursor" else Vector3.ZERO
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for p in m.verts:
		lo = lo.min(p)
		hi = hi.max(p)
	var c := (lo + hi) * 0.5
	return Vector3(c.x, lo.y, c.z) if how == "bottom" else c


## the model preview's origin in world space
static func origin_world(ui) -> Vector3:
	return ui.view.global_transform * ui.mesh.origin


## MeshTools.op "separate" / "separate_loose" / "join" / "join_weld" / "origin_geometry" / "origin_cursor" /
## "origin_bottom" on the model preview's mesh: ONE undo step each; returns what to say
static func op(name: String, m) -> String:
	var ui = m.kmed
	if ui == null or ui.mesh == null:
		return ""
	var mesh: KMesh = ui.mesh
	if name.begins_with("origin_"):
		var how := name.trim_prefix("origin_")
		var cur := Vector3.ZERO
		if how == "cursor":
			cur = ui.view.global_transform.affine_inverse() * ui.pivot.cursor
		var o := origin_for(mesh, how, cur)
		ui.undo.begin(mesh)
		mesh.origin = o
		var st: Dictionary = ui.undo.commit("Set origin")
		var wo := origin_world(ui)
		return "Model: origin %s: %s in the mesh (%s in the world)%s" % [{"geometry": "to the geometry centre", "cursor": "to the 3D cursor", "bottom": "to the bottom centre"}.get(how, how),
			_v(o), _v(wo), "; one undo step (Ctrl+Z)" if not st.is_empty() else "; it was already there"]
	if not KMeshShapes.keys(mesh).is_empty():
		return "Model: the mesh has shape keys: separating or joining would break them (their deltas are per vertex). Remove the keys first"
	var nv0 := mesh.vert_count()
	ui.undo.begin(mesh)
	var said := ""
	match name:
		"separate":
			var r := separate(mesh, sel_faces(mesh, ui.sel))
			if not r.is_empty():
				said = "Model: separated %d faces into a part of their own (%d border verts doubled; %s now)" % [r["faces"], r["doubled"], _n_parts(mesh)]
		"separate_loose":
			var n := separate_loose(mesh)
			if last_error == "":
				said = "Model: separated by loose parts: %d parts" % n
		"join", "join_weld":
			var r := join(mesh, ui.sel, name == "join_weld")
			if not r.is_empty():
				said = "Model: joined %d parts into one%s (%s now)" % [r["parts"], (", %d border verts welded" % r["welded"]) if name == "join_weld" else "", _n_parts(mesh)]
		_:
			last_error = "no op called '%s'" % name
	var st: Dictionary = ui.undo.commit({"separate": "Separate selection", "separate_loose": "Separate by loose parts", "join": "Join parts", "join_weld": "Join parts (weld)"}.get(name, name))
	if last_error != "":
		return "Model: " + last_error + ". Nothing changed"
	if mesh.vert_count() != nv0:
		ui.live = {}
		ui._after_topo()
	else:
		ui.view.mark_dirty()
	return said + (". One undo step (Ctrl+Z)" if not st.is_empty() else "")


static func _v(p: Vector3) -> String:
	return "%s, %s, %s" % [Units.len(p.x), Units.len(p.y), Units.len(p.z)]


static func _n_parts(m: KMesh) -> String:
	var n := parts(m).size()
	return "%d part%s" % [n, "" if n == 1 else "s"]
