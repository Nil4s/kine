class_name BaseBody
extends RefCounted
## G01 (docs/ROADMAP_400.md): THE FIGHTER'S BODY MESH IN THE MODEL PREVIEW. "Model: edit the body mesh" opens the
## fighter's skin (the mannequin, assets/mannequin.glb: Quaternius UAL2, CC0, the UE5 skeleton Kine uses, 65 bones) as
## a KMesh in the same preview as the test cube (scripts/kmesh_edit_ui.gd), so every op there works on it; "Model:
## apply the body mesh to the fighter" writes the edited KMesh back as the fighter's skinned mesh, ONE undo step.
## READ: the body is drawn as 52 pieces (Overlays.split_parts), each holding all the vertex data and its own triangles.
##   The rest meshes are read (the corrective's copy when it has one: the drawn mesh may be bent at the elbow), the
##   distinct vertex arrays are the source surfaces (2), their triangles the union over the pieces; the weights come from
##   the weight-paint model when it holds that surface (it is the painted truth), else from the mesh. Positions within
##   KMesh.WELD_TOL weld into one vertex (seam copies have identical weights on the mannequin; the test counts it).
## CARRIED as A09 attributes: one float vertex channel per skin bind used, "skin:<UE5 bone name>" = that bone's weight
##   (a dense table, not 4 packed index / weight pairs: an index cannot be averaged, a weight can, so a subdivide that
##   averages its neighbours or an extrude that copies its source gives a new vertex the interpolated weights with no
##   op knowing about skins); "surface" (face, float) = the source surface; "uv" (corner, Vector2) = the texture coords.
## WRITE: per surface, one output vertex per distinct (vertex, uv), in vertex order; smooth vertex normals; per vertex
##   the 4 heaviest bones, renormalised only when there were more than 4 or the sum is off 1 by > 1e-6 (so an untouched
##   vertex keeps its weights bit for bit); a vertex with no weight at all (a primitive added in the preview) takes the
##   nearest bone (its rest segment) at 1. Triangles go to the pieces by the split_parts rule (the part whose bones weigh
##   most on its corners); the hidden original mesh gets them all. Then the weight-paint model, the corrective and the
##   precise pick are rebuilt from the new pieces. Tangents are not written (the body's material has no normal map).
## UNDO: main's snapshot carries gen(m) (an int): every apply makes a new generation of rest meshes, remembered here;
##   main._restore puts a generation back (restore_gen) before the painted weights are restored.
## TOPOLOGY, honestly: the mannequin skin is NOT quad-dominant. It is all triangles: 8546 file vertices (2 surfaces) weld
##   to 6994, 13744 triangles, 0 quads; 2 boundary edges; not manifold by KMesh's rule. Tris to quads (F06, Alt+J) could
##   pair 91 % of them (6240 quads + 1264 triangles, tests/basebody_test.gd prints it), but a pairing is not an edge flow:
##   no retopology is done here (G01's quad base body is still to come).
## WEIGHTS are snapped to what the GPU holds (canon): whole 1/65535 steps adding up to exactly 1, so the first open moves
##   a painted / loaded weight by at most 2 steps (~3e-5) and from then on a round trip is bit for bit.
## SAVED (G07, scripts/body_file.gd) as a .kbody; a scene saved with an applied body names that file ("body_mesh").
## EXPORTED (G12, scripts/body_export.gd): "Model: export the body as glb (skin weights)".

const SURF := "surface"
const UV := "uv"
const W := "skin:"
const MAX_INFL := 4
const SUM_TOL := 1e-6
const Q := 65535   # a weight's 16-bit steps (canon)

const META_GENS := "bb_gens"   # on main: Array of generations, each {"pieces": {piece: rest ArrayMesh}, "src": {mi: mesh}}
const META_GEN := "bb_gen"     # on main: the generation drawn now
const META_BASE := "bb_base"   # on main: sig_of the body as it was read or last applied


# ---------------------------------------------------------------- read

## the rest mesh of every piece: the corrective keeps the unbent one, the drawn one may be bent at a joint
static func rest_meshes(m: Node) -> Dictionary:
	var out := {}
	var corr_rest := {}
	if m.get("corr") != null:
		for e in m.corr._entries:
			corr_rest[e[0]] = e[1]
	for j in m.pieces:
		var mi: MeshInstance3D = m.pieces[j]
		out[mi] = corr_rest.get(mi, mi.mesh)
	return out


## the source surfaces: [{"arr": surface arrays (whole vertex data), "tris": PackedInt32Array, "mat", "flags"}]
static func sources(m: Node) -> Array:
	var srcs := []
	var rest := rest_meshes(m)
	for j in m.pieces:
		var am := rest[m.pieces[j]] as ArrayMesh
		if am == null:
			continue
		for si in am.get_surface_count():
			var arr := am.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var k := -1
			for q in srcs.size():
				if (srcs[q]["arr"][Mesh.ARRAY_VERTEX] as PackedVector3Array) == vs:
					k = q
					break
			if k < 0:
				srcs.append({"arr": arr, "tris": PackedInt32Array(), "mat": am.surface_get_material(si), "flags": am.surface_get_format(si) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS})
				k = srcs.size() - 1
			var ix = arr[Mesh.ARRAY_INDEX]
			if ix != null:
				var t: PackedInt32Array = srcs[k]["tris"]
				t.append_array(ix)
				srcs[k]["tris"] = t
	# the painted weights (ROADMAP 72) where the weight-paint model holds the same vertices
	var wp: Dictionary = m.get("wp") if m.get("wp") != null else {}
	for s in srcs:
		for ws in wp.get("surfs", []):
			if (ws["verts"] as PackedVector3Array) == (s["arr"][Mesh.ARRAY_VERTEX] as PackedVector3Array):
				s["arr"][Mesh.ARRAY_BONES] = ws["bones"]
				s["arr"][Mesh.ARRAY_WEIGHTS] = ws["w"]
				break
	return srcs


static func skin_of(m: Node) -> Skin:
	for j in m.pieces:
		if (m.pieces[j] as MeshInstance3D).skin != null:
			return (m.pieces[j] as MeshInstance3D).skin
	return null


## the fighter's skin as a KMesh with its weights, surfaces and UVs as A09 attributes (see the header).
## info (optional out): {"conflicts": welded vertices whose copies disagreed on weights, "file_verts", "binds"}
static func to_kmesh(srcs: Array, skin: Skin, info := {}) -> KMesh:
	var inv := 1.0 / KMesh.WELD_TOL
	var grid := {}
	var pos := PackedVector3Array()
	var remaps := []
	var wsets := []   # per kmesh vertex: {bind: weight}
	var conflicts := 0
	var used := {}
	var nfile := 0
	for s in srcs:
		var arr: Array = s["arr"]
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES] if arr[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS] if arr[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		var per := bones.size() / maxi(vs.size(), 1)
		var rm := PackedInt32Array()
		rm.resize(vs.size())
		nfile += vs.size()
		for i in vs.size():
			var p := vs[i]
			var key := Vector3i(roundi(p.x * inv), roundi(p.y * inv), roundi(p.z * inv))
			var d := {}
			for q in per:
				var w := wts[i * per + q]
				if w > 0.0:
					d[bones[i * per + q]] = d.get(bones[i * per + q], 0.0) + w
					used[bones[i * per + q]] = true
			d = canon(d)
			var got: int = grid.get(key, -1)
			if got == -1:
				got = pos.size()
				grid[key] = got
				pos.append(p)
				wsets.append(d)
			elif wsets[got] != d:
				conflicts += 1
			rm[i] = got
		remaps.append(rm)
	var fs: Array = []
	var fsurf := PackedFloat32Array()
	var cuv := PackedVector2Array()
	for si in srcs.size():
		var arr: Array = srcs[si]["arr"]
		var uvs = arr[Mesh.ARRAY_TEX_UV]
		var t: PackedInt32Array = srcs[si]["tris"]
		var rm: PackedInt32Array = remaps[si]
		for i in range(0, t.size() - 2, 3):
			fs.append(PackedInt32Array([rm[t[i]], rm[t[i + 1]], rm[t[i + 2]]]))
			fsurf.append(float(si))
			for c in 3:
				cuv.append((uvs as PackedVector2Array)[t[i + c]] if uvs != null else Vector2.ZERO)
	var k := KMesh.new().from_arrays(pos, fs)
	k.add_attr(SURF, KMesh.AD_FACE, TYPE_FLOAT, 0.0)
	k.set_attr_data(SURF, fsurf)
	k.add_attr(UV, KMesh.AD_CORNER, TYPE_VECTOR2)
	k.set_attr_data(UV, cuv)
	var binds := used.keys()
	binds.sort()
	for b in binds:
		var nm: String = W + (String(skin.get_bind_name(b)) if skin != null and b < skin.get_bind_count() else str(b))
		k.add_attr(nm, KMesh.AD_VERT, TYPE_FLOAT, 0.0)
		var col := PackedFloat32Array()
		col.resize(pos.size())
		for v in pos.size():
			col[v] = float(wsets[v].get(b, 0.0))
		k.set_attr_data(nm, col)
	info["conflicts"] = conflicts
	info["file_verts"] = nfile
	info["binds"] = binds.size()
	return k


## the fighter's skin, read now
static func read(m: Node, info := {}) -> KMesh:
	return to_kmesh(sources(m), skin_of(m), info)


## per vertex: {bind: weight} of the "skin:" channels (only weights above 0)
static func weights_of(k: KMesh, skin: Skin) -> Array:
	var chans := []
	for nm in k.list_attrs():
		if String(nm).begins_with(W):
			var bn := String(nm).substr(W.length())
			var b := -1
			if skin != null:
				for q in skin.get_bind_count():
					if String(skin.get_bind_name(q)) == bn:
						b = q
						break
			if b < 0 and bn.is_valid_int():
				b = int(bn)
			if b >= 0:
				chans.append([b, k.attr_data(nm)])
	var out := []
	out.resize(k.verts.size())
	for v in k.verts.size():
		var d := {}
		for c in chans:
			var w: float = (c[1] as PackedFloat32Array)[v] if v < (c[1] as PackedFloat32Array).size() else 0.0
			if w > 0.0:
				d[c[0]] = w
		out[v] = d
	return out


## the 4 heaviest, renormalised only when needed (see the header); {} stays {} (the caller picks a bone)
static func fit4(d: Dictionary) -> Dictionary:
	if d.is_empty():
		return d
	var s := 0.0
	for b in d:
		s += float(d[b])
	if d.size() <= MAX_INFL and absf(s - 1.0) <= SUM_TOL:
		return d
	var ks := d.keys()
	ks.sort_custom(func(a, b): return float(d[a]) > float(d[b]) or (float(d[a]) == float(d[b]) and int(a) < int(b)))
	ks = ks.slice(0, MAX_INFL)
	s = 0.0
	for b in ks:
		s += float(d[b])
	var out := {}
	for b in ks:
		out[b] = float(d[b]) / s
	return out


## the weights as the GPU holds them: whole steps of 1/65535 (Godot stores a weight as a 16-bit fraction) that add up
## to exactly 65535 (largest remainder), so what is written reads back bit for bit and every vertex sums to 1
static func canon(d: Dictionary) -> Dictionary:
	if d.is_empty():
		return d
	var s := 0.0
	for b in d:
		s += float(d[b])
	var ks := d.keys()
	ks.sort()
	var units := {}
	var left := Q
	var rem := []
	for b in ks:
		var x := float(d[b]) / s * Q
		var u := floori(x)
		units[b] = u
		left -= u
		rem.append([x - u, b])
	rem.sort_custom(func(a, c): return a[0] > c[0] or (a[0] == c[0] and int(a[1]) < int(c[1])))
	for i in left:
		units[rem[i % rem.size()][1]] += 1
	var out := {}
	for b in ks:
		if int(units[b]) > 0:
			out[b] = float(units[b]) / float(Q)
	return out


## the bind whose rest segment (its head to its first child's head, in mesh space) is nearest p
static func nearest_bind(skin: Skin, sk: Skeleton3D, p: Vector3) -> int:
	var head := {}
	for q in skin.get_bind_count():
		head[q] = skin.get_bind_pose(q).affine_inverse().origin
	var best := 0
	var bd := INF
	for q in skin.get_bind_count():
		var bq := SkinPaint.bind_bone(skin, sk, q)
		var tail: Vector3 = head[q]
		for r in skin.get_bind_count():
			if sk.get_bone_parent(SkinPaint.bind_bone(skin, sk, r)) == bq:
				tail = head[r]
				break
		var d := p.distance_to(Geometry3D.get_closest_point_to_segment(p, head[q], tail))
		if d < bd:
			bd = d
			best = q
	return best


## the KMesh as surfaces ready for an ArrayMesh: [{"arr", "si"}] (full vertex data, all the surface's triangles)
## plus "unweighted": the vertices that had no weight (given their nearest bone)
static func build(k: KMesh, skin: Skin, sk: Skeleton3D, srcs: Array) -> Dictionary:
	var ws := weights_of(k, skin)
	var unw := 0
	for v in ws.size():
		ws[v] = canon(fit4(ws[v]))
		if (ws[v] as Dictionary).is_empty():
			ws[v] = {nearest_bind(skin, sk, k.verts[v]) if skin != null and sk != null else 0: 1.0}
			unw += 1
	var fsurf = k.attr_data(SURF) if k.has_attr(SURF) else null
	var uva = k.attr_data(UV) if k.has_attr(UV) and k.attr_info(UV)["domain"] == KMesh.AD_CORNER else null
	var he0 := k.face_he0
	var vn := k.vert_normals
	var by := {}   # surface -> [face]
	for fi in k.faces.size():
		var s := roundi(float(fsurf[fi])) if fsurf != null else 0
		if not by.has(s):
			by[s] = []
		by[s].append(fi)
	var out := []
	var keys := by.keys()
	keys.sort()
	for s in keys:
		# the distinct (vertex, uv) corners, in vertex order
		var corners := {}   # [v, uv] -> true
		for fi in by[s]:
			var f: PackedInt32Array = k.faces[fi]
			for i in f.size():
				corners[[f[i], (uva[he0[fi] + i] as Vector2) if uva != null else Vector2.ZERO]] = true
		var list := corners.keys()
		list.sort_custom(func(a, b): return int(a[0]) < int(b[0]) or (int(a[0]) == int(b[0]) and (a[1] as Vector2) < (b[1] as Vector2)))
		var at := {}
		var pos := PackedVector3Array()
		var nor := PackedVector3Array()
		var tuv := PackedVector2Array()
		var bones := PackedInt32Array()
		var wts := PackedFloat32Array()
		for c in list:
			at[c] = pos.size()
			var v: int = c[0]
			pos.append(k.verts[v])
			nor.append(vn[v])
			tuv.append(c[1])
			var d: Dictionary = ws[v]
			var bk := d.keys()
			bk.sort()
			for q in MAX_INFL:
				bones.append(int(bk[q]) if q < bk.size() else 0)
				wts.append(float(d[bk[q]]) if q < bk.size() else 0.0)
		var idx := PackedInt32Array()
		for fi in by[s]:
			var f: PackedInt32Array = k.faces[fi]
			var loc := PackedInt32Array()
			for i in f.size():
				loc.append(at[[f[i], (uva[he0[fi] + i] as Vector2) if uva != null else Vector2.ZERO]])
			for i in range(1, f.size() - 1):
				idx.append(loc[0])
				idx.append(loc[i])
				idx.append(loc[i + 1])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_NORMAL] = nor
		arr[Mesh.ARRAY_TEX_UV] = tuv
		arr[Mesh.ARRAY_BONES] = bones
		arr[Mesh.ARRAY_WEIGHTS] = wts
		arr[Mesh.ARRAY_INDEX] = idx
		out.append({"arr": arr, "si": s, "mat": srcs[s]["mat"] if s < srcs.size() else null})
	return {"surfs": out, "unweighted": unw}


# ---------------------------------------------------------------- write

## the part of every bind (Overlays.split_parts' rule): the bone itself if it is a body joint, else its nearest one up
static func _part_of_bind(m: Node, skin: Skin) -> Dictionary:
	var sk: Skeleton3D = m.skel
	var ours := {}
	for j in m.bone_idx:
		if int(m.bone_idx[j]) >= 0:
			ours[int(m.bone_idx[j])] = j
	var out := {}
	for q in skin.get_bind_count():
		var c := SkinPaint.bind_bone(skin, sk, q)
		while c >= 0 and not ours.has(c):
			c = sk.get_bone_parent(c)
		out[q] = ours[c] if c >= 0 else "pelvis"
	return out


## the pieces' new meshes from the built surfaces: {piece: ArrayMesh} and the whole mesh (for the hidden original)
static func split(m: Node, surfs: Array, skin: Skin) -> Dictionary:
	var pob := _part_of_bind(m, skin)
	var tris := {}   # part -> {surface index in surfs -> PackedInt32Array}
	for n in surfs.size():
		var arr: Array = surfs[n]["arr"]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for t in range(0, ix.size(), 3):
			var w := {}
			for c in 3:
				var v: int = ix[t + c]
				for q in MAX_INFL:
					var pj: String = pob.get(bones[v * MAX_INFL + q], "pelvis")
					w[pj] = float(w.get(pj, 0.0)) + wts[v * MAX_INFL + q]
			var best := ""
			for pj in w:
				if best == "" or float(w[pj]) > float(w[best]):
					best = pj
			if not m.pieces.has(best):
				best = "pelvis" if m.pieces.has("pelvis") else String(m.pieces.keys()[0])
			if not tris.has(best):
				tris[best] = {}
			if not tris[best].has(n):
				tris[best][n] = PackedInt32Array()
			tris[best][n].append_array(ix.slice(t, t + 3))
	var out := {}
	for j in m.pieces:
		var am := ArrayMesh.new()
		for n in surfs.size():
			if tris.has(j) and tris[j].has(n):
				var arr: Array = (surfs[n]["arr"] as Array).duplicate()
				arr[Mesh.ARRAY_INDEX] = tris[j][n]
				am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				am.surface_set_material(am.get_surface_count() - 1, surfs[n]["mat"])
		out[m.pieces[j]] = am
	var whole := ArrayMesh.new()
	for n in surfs.size():
		whole.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfs[n]["arr"])
		whole.surface_set_material(n, surfs[n]["mat"])
	return {"pieces": out, "whole": whole}


## the hidden original mesh(es) of the mannequin (split_parts hid it, the pieces draw it)
static func _originals(m: Node) -> Array:
	var out := []
	var pcs := {}
	for j in m.pieces:
		pcs[m.pieces[j]] = true
	var par: Node = (m.pieces.values()[0] as Node).get_parent() if not m.pieces.is_empty() else null
	if par == null:
		return out
	for c in par.get_children():
		if c is MeshInstance3D and not pcs.has(c) and (c as MeshInstance3D).skin != null:
			out.append(c)
	return out


static func gen(m: Node) -> int:
	return int(m.get_meta(META_GEN, 0))


## remember the generation drawn now (gen 0 = the body as loaded) the first time it is needed
static func _ensure_gens(m: Node) -> Array:
	var gens: Array = m.get_meta(META_GENS, [])
	if gens.is_empty():
		var src := {}
		for o in _originals(m):
			src[o] = (o as MeshInstance3D).mesh
		gens.append({"pieces": rest_meshes(m), "src": src})
		m.set_meta(META_GENS, gens)
		m.set_meta(META_GEN, 0)
	return gens


## put generation g's meshes on the fighter (main._restore, undo / redo of an apply); false when it is drawn already
static func restore_gen(m: Node, g: int) -> bool:
	if g == gen(m) or not m.has_meta(META_GENS):
		return false
	var gens: Array = m.get_meta(META_GENS)
	if g < 0 or g >= gens.size():
		return false
	_put(m, gens[g])
	m.set_meta(META_GEN, g)
	return true


## the meshes onto the pieces, then the weight model, the corrective and the pick read them again
static func _put(m: Node, rec: Dictionary) -> void:
	for mi in rec["pieces"]:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).mesh = rec["pieces"][mi]
	for o in rec["src"]:
		if is_instance_valid(o):
			(o as MeshInstance3D).mesh = rec["src"][o]
	m.wp = SkinPaint.read(m.pieces.values(), m.skel)
	if m.wp.is_empty() or m.wp["skin"] == null:
		m.wp = {}
	m.corr.attach(m.pieces.values(), m.skel)
	m._skp_build()
	if m.has_method("_refresh"):
		m._refresh()


## write k as the fighter's skinned mesh: ONE undo step (none when undo is false: G07 opening a scene that names its body).
## -> {"ok", "verts", "tris", "unweighted", "error"}
static func apply(m: Node, k: KMesh, undo := true) -> Dictionary:
	var skin := skin_of(m)
	if skin == null or k == null:
		return {"ok": false, "error": "the fighter has no skinned body to write to"}
	_ensure_gens(m)
	var srcs := sources(m)
	var b := build(k, skin, m.skel, srcs)
	var sp := split(m, b["surfs"], skin)
	if undo:
		m._step_hint = "Apply the body mesh to the fighter"
		m._push_undo()
	var src := {}
	for o in _originals(m):
		src[o] = sp["whole"]
	var gens: Array = m.get_meta(META_GENS)
	gens.append({"pieces": sp["pieces"], "src": src})
	m.set_meta(META_GEN, gens.size() - 1)
	_put(m, gens[gens.size() - 1])
	var nt := 0
	var nv := 0
	for s in b["surfs"]:
		nt += (s["arr"][Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		nv += (s["arr"][Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return {"ok": true, "verts": nv, "tris": nt, "unweighted": b["unweighted"], "error": ""}


# ---------------------------------------------------------------- the preview

## "Model: edit the body mesh": the model preview opens on the fighter's skin, where the fighter stands, framed
static func start(m: Node) -> void:
	if m.pieces.is_empty() or skin_of(m) == null:
		m._say("Model: the fighter has no skinned body to edit")
		return
	if m.kmed == null:
		m.kmed = load("res://scripts/kmesh_edit_ui.gd").new()
		m.add_child(m.kmed)
		m.kmed.setup(m)
	if m.kmed.on:
		m.kmed.stop()
	var info := {}
	var k := read(m, info)
	var p0 := m.pieces.values()[0] as MeshInstance3D
	var at: Transform3D = (m.stage_root as Node3D).global_transform.affine_inverse() * p0.global_transform
	var vis := {}
	for j in m.pieces:
		vis[m.pieces[j]] = (m.pieces[j] as MeshInstance3D).visible
	var cam_was := {"target": m.target, "dist": m.dist, "yaw": m.yaw, "pitch": m.pitch}
	m.kmed.source = func(): return {"mesh": k, "at": at}
	m.kmed.left = func(): _leave(m, vis, cam_was)
	m._mesh_page_for("MODEL")   # the body's mesh is edited on the MODEL page (its keys and panels)
	m.kmed.start()
	m.set_meta(META_BASE, sig_of(m.kmed.mesh))   # after the editor starts: Apply with no edit since then writes nothing
	m.kmed.prim_panel.visible = false   # the cube's "Add primitive" panel is not the body's
	m.kmed.set_meta("base_body", true)
	m.kmed.set_meta("fighter_vis", vis)   # the fighter's parts come back on another page, and go again on MODEL (kmesh_edit_ui.set_showing)
	for mi in vis:
		(mi as MeshInstance3D).visible = false   # the edited copy stands where the fighter stood
	m._mesh_show_sync()
	frame(m)
	var quads := 0
	for f in k.faces:
		if (f as PackedInt32Array).size() == 4:
			quads += 1
	m._say("Model: the fighter's body: %d verts, %d faces (%d quads: the mannequin is triangles), %d bones weighted. Every model key works; Search \"Model: apply the body mesh to the fighter\" writes it back (one undo step), Esc leaves without changing the fighter" % [k.verts.size(), k.faces.size(), quads, info.get("binds", 0)])


static func is_open(m: Node) -> bool:
	return m.get("kmed") != null and m.kmed.on and m.kmed.has_meta("base_body")


static func _leave(m: Node, vis: Dictionary, cam_was: Dictionary) -> void:
	for mi in vis:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).visible = vis[mi]
	m.kmed.source = Callable()
	m.kmed.left = Callable()
	m.kmed.remove_meta("base_body")
	m.kmed.remove_meta("fighter_vis")
	for key in cam_was:
		m.set(key, cam_was[key])
	m._cam()
	m._say("Model: left the body mesh. The fighter is %s" % ("the applied mesh (Ctrl+Z takes it back)" if gen(m) > 0 else "as it was (nothing applied)"))


## the camera on the whole edited body: centred, its height ~75 % of the free view's (its width at most 90 %)
static func frame(m: Node) -> void:
	var view: Node3D = m.kmed.view
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in m.kmed.mesh.verts:
		var w: Vector3 = view.global_transform * p
		lo = lo.min(w)
		hi = hi.max(w)
	var vs: Vector2 = m.get_viewport().get_visible_rect().size if m.is_inside_tree() else Vector2(1600, 900)
	var free_h: float = maxf(200.0, vs.y - float(m.TOP_H) - float(m.bottom_h) - float(m.LINE_H) - 6.0)
	var free_w: float = maxf(200.0, vs.x - float(m.lw()) - float(m.rw()))
	var t := tan(deg_to_rad((m.cam as Camera3D).fov * 0.5))
	var size := hi - lo
	var d_h := size.y * vs.y / (0.75 * free_h * 2.0 * t)
	var d_w := maxf(size.x, size.z) * vs.y / (0.9 * free_w * 2.0 * t)
	m.target = (lo + hi) * 0.5
	m.dist = maxf(d_h, d_w) + maxf(size.x, size.z) * 0.5
	m.yaw = 0.0
	m.pitch = 0.0
	m._cam()


## "Model: apply the body mesh to the fighter"
## what the editor's KMesh holds, as a number: the same when no edit changed it (Ctrl+Z back to the start counts too)
static func sig_of(k: KMesh) -> int:
	return hash(k.to_dict())


static func apply_cmd(m: Node) -> void:
	if not is_open(m):
		m._say("Model: open the body first (Search \"Model: edit the body mesh\"), edit it, then apply")
		return
	# an unedited body is not rebuilt: the rebuild splits the vertices at UV seams (6994 -> 7330 on the mannequin) for no change
	if m.has_meta(META_BASE) and sig_of(m.kmed.mesh) == int(m.get_meta(META_BASE)):
		m._say("Model: the body has no edits since it was read, so nothing is applied (the fighter is as it was: %s)" % ("the applied mesh" if gen(m) > 0 else "the original"))
		return
	var r := apply(m, m.kmed.mesh)
	if not r["ok"]:
		m._say("Model: " + String(r["error"]))
		return
	m.set_meta(META_BASE, sig_of(m.kmed.mesh))
	for j in m.pieces:
		(m.pieces[j] as MeshInstance3D).visible = false   # still editing: the preview stands in for it until Esc
	m._say("Model: the fighter's body is now the edited mesh (%d verts, %d triangles%s). Ctrl+Z after leaving takes it back in one step" % [r["verts"], r["tris"], (", %d unweighted verts given their nearest bone" % r["unweighted"]) if int(r["unweighted"]) > 0 else ""])
