## WAVEFRONT OBJ, own code (the format is public: Alias|Wavefront's text format; one record per line).
##   ObjIO.export(meshes, path)  meshes = [{"name", "mesh": ArrayMesh, "xf": Transform3D, "color": Color (optional)}]
##       writes <path> (v / vt / vn / f, one `o` group per entry, `usemtl` per entry) and <path base>.mtl (Kd = base colour).
##       Units are metres, Y up (as the app draws). Returns {"ok", "path", "tris", "verts", "why"}.
##   ObjIO.import_file(path) -> Array of {"name", "mesh": ArrayMesh, "color": Color}. Handles n-gons (fan triangulation),
##       negative (relative) indices, missing vt / vn (normals are then computed, smooth over shared v), `o` / `g` groups.
##   ObjIO.parse(text, mtl_dir) is the same from a string. ObjIO.bounds(path) is what Importer.inspect reads for an .obj.
## Winding: OBJ faces run counter-clockwise, Godot's front faces clockwise, so both directions swap two corners.
class_name ObjIO
extends RefCounted

const DEFAULT_COLOR := Color(0.70, 0.67, 0.62)


## the triangle count and vertex count of a mesh (all surfaces)
static func counts(mesh: Mesh) -> Vector2i:
	var tris := 0
	var verts := 0
	for si in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		verts += v.size()
		var ix = arr[Mesh.ARRAY_INDEX]
		tris += (ix.size() if ix != null else v.size()) / 3
	return Vector2i(tris, verts)


## n03: vertex / normal / face lines in C++ (KineMeshOpsNative); KINE_NO_NATIVE=1 forces the GDScript loops
static func native_on() -> bool:
	return MeshOpsDoor.on()


static func _f(x: float) -> String:
	return "%.6f" % x


## smooth vertex normals for triangles given as index triples in Godot (clockwise) order: area-weighted face normals
static func compute_normals(verts: PackedVector3Array, idx: PackedInt32Array) -> PackedVector3Array:
	var n := PackedVector3Array()
	n.resize(verts.size())
	for t in idx.size() / 3:
		var a := idx[t * 3]
		var b := idx[t * 3 + 1]
		var c := idx[t * 3 + 2]
		var fn := (verts[c] - verts[a]).cross(verts[b] - verts[a])   # clockwise corners: this points out of the front face
		n[a] += fn
		n[b] += fn
		n[c] += fn
	for i in n.size():
		n[i] = n[i].normalized() if n[i].length_squared() > 1e-18 else Vector3.UP
	return n


static func _safe(s: String) -> String:
	var r := ""
	for ch in s.strip_edges():
		r += ch if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "-" or ch == "_" else "_"
	return r if r != "" else "part"


static func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p) if p.begins_with("res://") or p.begins_with("user://") else p


## write the meshes (each transformed by its xf) as an .obj + .mtl
static func export(meshes: Array, path: String) -> Dictionary:
	var r := {"ok": false, "path": path, "tris": 0, "verts": 0, "why": ""}
	if meshes.is_empty():
		r["why"] = "there is nothing to write: no mesh was given"
		return r
	DirAccess.make_dir_recursive_absolute(_abs(path.get_base_dir()))
	var base := path.get_file().get_basename()
	var out := PackedStringArray()
	out.append("# Kine (Teschima Studios) OBJ export: metres, Y up")
	out.append("mtllib %s.mtl" % base)
	var mtl := PackedStringArray()
	var off_v := 0
	var off_t := 0
	var off_n := 0
	var used := {}
	for e in meshes:
		var mesh: Mesh = e["mesh"]
		if mesh == null:
			continue
		var xf: Transform3D = e.get("xf", Transform3D.IDENTITY)
		var nb := xf.basis.inverse().transposed()
		var nm := _safe(String(e.get("name", "part")))
		var u := nm
		var k := 2
		while used.has(u):
			u = "%s_%d" % [nm, k]
			k += 1
		used[u] = true
		var col: Color = e.get("color", DEFAULT_COLOR)
		mtl.append("newmtl %s" % u)
		mtl.append("Kd %s %s %s" % [_f(col.r), _f(col.g), _f(col.b)])
		mtl.append("Ka 0.000000 0.000000 0.000000")
		mtl.append("d 1.000000")
		mtl.append("")
		out.append("o %s" % u)
		out.append("usemtl %s" % u)
		for si in mesh.get_surface_count():
			var arr: Array = mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nrm = arr[Mesh.ARRAY_NORMAL]
			var uv = arr[Mesh.ARRAY_TEX_UV]
			var ix = arr[Mesh.ARRAY_INDEX]
			var has_n: bool = nrm != null and (nrm as PackedVector3Array).size() == v.size()
			var has_t: bool = uv != null and (uv as PackedVector2Array).size() == v.size()
			var nat := native_on()
			if nat:
				if not v.is_empty():
					out.append(MeshOpsDoor.door().obj_vertices(v, xf))
			else:
				for p in v:
					var q := xf * p
					out.append("v %s %s %s" % [_f(q.x), _f(q.y), _f(q.z)])
			if has_t:
				for t in (uv as PackedVector2Array):
					out.append("vt %s %s" % [_f(t.x), _f(1.0 - t.y)])   # OBJ's v runs up from the bottom
			if has_n:
				if nat:
					if not (nrm as PackedVector3Array).is_empty():
						out.append(MeshOpsDoor.door().obj_normals(nrm, nb))
				else:
					for nv in (nrm as PackedVector3Array):
						var q := (nb * nv).normalized()
						out.append("vn %s %s %s" % [_f(q.x), _f(q.y), _f(q.z)])
			var m := v.size()
			var cnt: int = (ix.size() if ix != null else m) / 3
			if nat:
				if cnt > 0:
					out.append(MeshOpsDoor.door().obj_faces(ix if ix != null else PackedInt32Array(), cnt, off_v, off_t, off_n, has_t, has_n))
			for t in (0 if nat else cnt):
				var c := []
				for corner in [0, 2, 1]:   # clockwise -> counter-clockwise
					var i: int = (ix[t * 3 + corner] if ix != null else t * 3 + corner)
					var a := str(off_v + i + 1)
					if has_t and has_n:
						a += "/%d/%d" % [off_t + i + 1, off_n + i + 1]
					elif has_t:
						a += "/%d" % (off_t + i + 1)
					elif has_n:
						a += "//%d" % (off_n + i + 1)
					c.append(a)
				out.append("f %s %s %s" % [c[0], c[1], c[2]])
			off_v += m
			if has_t:
				off_t += m
			if has_n:
				off_n += m
			r["tris"] += cnt
			r["verts"] += m
	var f := FileAccess.open(_abs(path), FileAccess.WRITE)
	if f == null:
		r["why"] = "the file could not be opened for writing (%s)" % error_string(FileAccess.get_open_error())
		return r
	f.store_string("\n".join(out) + "\n")
	f.close()
	var g := FileAccess.open(_abs(path.get_basename() + ".mtl"), FileAccess.WRITE)
	if g != null:
		g.store_string("\n".join(mtl))
		g.close()
	r["ok"] = true
	return r


static func import_file(path: String) -> Array:
	var f := FileAccess.open(_abs(path), FileAccess.READ)
	if f == null:
		return []
	var text := f.get_as_text()
	f.close()
	return parse(text, _abs(path).get_base_dir())


## one OBJ's text -> [{"name", "mesh", "color"}]; mtl_dir is where a `mtllib` file is looked for ("" = not read)
static func parse(text: String, mtl_dir := "") -> Array:
	var V := PackedVector3Array()
	var T := PackedVector2Array()
	var N := PackedVector3Array()
	var colors := {}
	var groups := []
	var cur := {}
	var mat_of := ""
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		var h := line.find("#")
		if h >= 0:
			line = line.substr(0, h).strip_edges()
		if line == "":
			continue
		var w := line.split(" ", false)
		if w.size() == 1 and line.contains("\t"):
			w = line.replace("\t", " ").split(" ", false)
		var tag := w[0]
		match tag:
			"v":
				if w.size() >= 4:
					V.append(Vector3(float(w[1]), float(w[2]), float(w[3])))
			"vt":
				if w.size() >= 3:
					T.append(Vector2(float(w[1]), 1.0 - float(w[2])))
			"vn":
				if w.size() >= 4:
					N.append(Vector3(float(w[1]), float(w[2]), float(w[3])))
			"o", "g":
				var nm := " ".join(w.slice(1)) if w.size() > 1 else "obj"
				if not cur.is_empty() and (cur["faces"] as Array).is_empty():
					cur["name"] = nm   # `o a` then `g b` with no face between: one group
				else:
					cur = {"name": nm, "faces": [], "mat": mat_of}
					groups.append(cur)
			"usemtl":
				mat_of = w[1] if w.size() > 1 else ""
				if not cur.is_empty():
					if (cur["faces"] as Array).is_empty():
						cur["mat"] = mat_of
			"mtllib":
				if mtl_dir != "" and w.size() > 1:
					colors.merge(_read_mtl(mtl_dir.path_join(" ".join(w.slice(1)))))
			"f":
				if w.size() < 4:
					continue
				if cur.is_empty():
					cur = {"name": "obj", "faces": [], "mat": mat_of}
					groups.append(cur)
				var face := []
				for k in range(1, w.size()):
					var p := String(w[k]).split("/")
					var vi := _ix(p[0], V.size())
					var ti := _ix(p[1], T.size()) if p.size() > 1 and p[1] != "" else -1
					var ni := _ix(p[2], N.size()) if p.size() > 2 and p[2] != "" else -1
					face.append(Vector3i(vi, ti, ni))
				(cur["faces"] as Array).append(face)
	var out := []
	for g in groups:
		if (g["faces"] as Array).is_empty():
			continue
		var m := _build(V, T, N, g["faces"])
		if m == null:
			continue
		out.append({"name": g["name"], "mesh": m, "color": colors.get(g["mat"], DEFAULT_COLOR)})
	return out


## an OBJ index (1-based, or negative = counted back from the last record so far) -> 0-based; -1 when out of range
static func _ix(s: String, count: int) -> int:
	if not s.is_valid_int():
		return -1
	var i := int(s)
	i = i - 1 if i > 0 else count + i
	return i if i >= 0 and i < count else -1


static func _read_mtl(path: String) -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(path):
		return out
	var cur := ""
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var w := raw.strip_edges().split(" ", false)
		if w.size() >= 2 and w[0] == "newmtl":
			cur = w[1]
		elif w.size() >= 4 and w[0] == "Kd" and cur != "":
			out[cur] = Color(float(w[1]), float(w[2]), float(w[3]))
	return out


## the faces (arrays of Vector3i(v, vt, vn)) -> one ArrayMesh surface; a corner = one distinct (v, vt, vn)
static func _build(V: PackedVector3Array, T: PackedVector2Array, N: PackedVector3Array, faces: Array) -> ArrayMesh:
	var key := {}
	var pos := PackedVector3Array()
	var uvs := PackedVector2Array()
	var nrm := PackedVector3Array()
	var has_n := true
	var has_t := true
	var vsrc := PackedInt32Array()   # per corner: the v it came from (for the computed normals)
	var idx := PackedInt32Array()
	for face in faces:
		var ids := []
		for c in face:
			var c3: Vector3i = c
			if c3.x < 0:
				ids.clear()
				break
			var kk := c3
			if not key.has(kk):
				key[kk] = pos.size()
				pos.append(V[c3.x])
				vsrc.append(c3.x)
				if c3.y >= 0:
					uvs.append(T[c3.y])
				else:
					uvs.append(Vector2.ZERO)
					has_t = false
				if c3.z >= 0:
					nrm.append(N[c3.z])
				else:
					nrm.append(Vector3.ZERO)
					has_n = false
			ids.append(key[kk])
		if ids.size() < 3:
			continue
		for t in range(1, ids.size() - 1):   # fan from the first corner; OBJ is counter-clockwise, Godot clockwise: swap two
			idx.append(ids[0])
			idx.append(ids[t + 1])
			idx.append(ids[t])
	if idx.is_empty():
		return null
	if not has_n:
		# computed normals: smooth over the SAME v (corners that share a v but differ in vt still shade as one point)
		var acc := {}
		for i in pos.size():
			acc[vsrc[i]] = Vector3.ZERO
		for t in idx.size() / 3:
			var a := idx[t * 3]
			var b := idx[t * 3 + 1]
			var c := idx[t * 3 + 2]
			var fn := (pos[c] - pos[a]).cross(pos[b] - pos[a])
			for q in [a, b, c]:
				acc[vsrc[q]] = acc[vsrc[q]] + fn
		for i in pos.size():
			var s: Vector3 = acc[vsrc[i]]
			if nrm[i].length_squared() < 1e-12 or not has_n:
				nrm[i] = s.normalized() if s.length_squared() > 1e-18 else Vector3.UP
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nrm
	if has_t:
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## the box of everything in an .obj (a zero AABB when it holds no faces or does not exist); Importer.inspect builds its answer from it
static func bounds(path: String) -> AABB:
	var box := AABB()
	var objs := import_file(path) if FileAccess.file_exists(_abs(path)) else []
	for i in objs.size():
		var b: AABB = (objs[i]["mesh"] as ArrayMesh).get_aabb()
		box = b if i == 0 else box.merge(b)
	return box
