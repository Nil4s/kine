class_name KMeshMaterial
extends RefCounted
## PBR MATERIALS ON A KMESH (ROADMAP_400 E01): a slot list on the mesh (KMesh.materials, saved in the .kmesh as
## "materials") and a per-face index (the A09 face attribute "mat", float, 0 = the first slot). A face whose index is
## out of range draws with slot 0.
## A slot is a Dictionary of the fields below (FIELDS: name -> default). Colours are Color, the numbers are kept as
## float32 values (clean() rounds them through a PackedFloat32Array) so a .kmesh save / load gives them back exactly.
## Maps are file paths (res://, user:// or absolute; "" = none), read with Image.load_from_file when the view is built.
##   albedo, albedo_tex          base colour (the map is multiplied by the colour)
##   metallic, metallic_tex      0 dielectric .. 1 metal (map: red channel)
##   roughness, roughness_tex    0 mirror .. 1 matte (map: red channel)
##   normal_scale, normal_tex    a tangent-space normal map (OpenGL convention, as PhotoMaterial writes) and its strength
##   ao, ao_tex                  ambient occlusion: the map, and how much it darkens direct light too (ao_light_affect)
##   emission, emission_energy, emission_tex   glow colour, its strength (0 = off) and a map
##   sss, sss_tex                subsurface scattering strength (0 = off; skin mode on) and a thickness / strength map
## The view (KMeshView.rebuild, shading "") draws one surface per slot that has faces, with a StandardMaterial3D of the
## matching fields (subsurf_scatter_* for SSS). A mesh with no "uv" corner attribute gets triplanar mapping (1 tile / m).
## E15 feeds a slot with one call: from_photo(slot, name) points its three maps at user://materials/<name>/.

const ATTR := "mat"
const TEX_KEYS := ["albedo_tex", "metallic_tex", "roughness_tex", "normal_tex", "ao_tex", "emission_tex", "sss_tex"]
const NUM_KEYS := ["metallic", "roughness", "normal_scale", "ao", "emission_energy", "sss"]
const COL_KEYS := ["albedo", "emission"]
const FIELDS := {
	"name": "Material", "albedo": Color(0.8, 0.8, 0.8, 1.0), "metallic": 0.0, "roughness": 0.6, "normal_scale": 1.0,
	"ao": 0.0, "emission": Color(0, 0, 0, 1), "emission_energy": 0.0, "sss": 0.0,
	"albedo_tex": "", "metallic_tex": "", "roughness_tex": "", "normal_tex": "", "ao_tex": "", "emission_tex": "", "sss_tex": "",
}
## slider ranges of the numbers: [min, max, step]
const RANGES := {"metallic": [0.0, 1.0, 0.01], "roughness": [0.0, 1.0, 0.01], "normal_scale": [-4.0, 4.0, 0.05],
	"ao": [0.0, 1.0, 0.01], "emission_energy": [0.0, 16.0, 0.1], "sss": [0.0, 1.0, 0.01]}

static var _tex_cache := {}   # path -> [modified time, ImageTexture]


static func _f32(v: float) -> float:
	return PackedFloat32Array([v])[0]


static func _c32(c: Color) -> Color:
	var p := PackedFloat32Array([c.r, c.g, c.b, c.a])
	return Color(p[0], p[1], p[2], p[3])


## a slot with every field: the defaults, then `over`; numbers clamped to RANGES and kept float32
static func clean(over := {}) -> Dictionary:
	var s := {}
	for k in FIELDS:
		var v = over.get(k, FIELDS[k])
		if k in COL_KEYS:
			s[k] = _c32(v if v is Color else FIELDS[k])
		elif k in NUM_KEYS:
			var r: Array = RANGES[k]
			s[k] = _f32(clampf(float(v), r[0], r[1]))
		else:
			s[k] = String(v)
	return s


static func count(m: KMesh) -> int:
	return m.materials.size()


## the slot index of face fi (0 when the mesh has no index channel or the index is out of range)
static func face_slot(m: KMesh, fi: int) -> int:
	if not m.has_attr(ATTR):
		return 0
	var i := int(m.get_attr(ATTR, fi))
	return i if i >= 0 and i < m.materials.size() else 0


static func _ensure_attr(m: KMesh) -> void:
	if not m.has_attr(ATTR) or m.attr_info(ATTR)["domain"] != KMesh.AD_FACE:
		m.remove_attr(ATTR)
		m.add_attr(ATTR, KMesh.AD_FACE, TYPE_FLOAT, 0.0)


## add a slot (the fields of `over` over the defaults); returns its index. The first slot owns every face.
static func add(m: KMesh, over := {}) -> int:
	_ensure_attr(m)
	var s := clean(over)
	if not over.has("name"):
		s["name"] = "Material %d" % (m.materials.size() + 1)
	m.materials.append(s)
	return m.materials.size() - 1


## remove slot i: its faces go to slot 0 (to the new first slot when i is 0), the indices above it shift down.
## The last slot removed takes the index channel with it.
static func remove(m: KMesh, i: int) -> bool:
	if i < 0 or i >= m.materials.size():
		return false
	m.materials.remove_at(i)
	if m.materials.is_empty():
		m.remove_attr(ATTR)
		return true
	var d: PackedFloat32Array = m.attr_data(ATTR).duplicate()
	for fi in d.size():
		var k := int(d[fi])
		d[fi] = 0.0 if k == i else (float(k - 1) if k > i else float(k))
	m.set_attr_data(ATTR, d)
	return true


## faces -> slot i; returns how many faces changed (the channel is replaced, not written in place, so an undo snapshot
## taken before is never touched)
static func assign(m: KMesh, faces, i: int) -> int:
	if i < 0 or i >= m.materials.size():
		return 0
	_ensure_attr(m)
	var d: PackedFloat32Array = m.attr_data(ATTR).duplicate()
	var n := 0
	for fi in faces:
		if int(fi) >= 0 and int(fi) < d.size() and int(d[fi]) != i:
			d[fi] = float(i)
			n += 1
	if n > 0:
		m.set_attr_data(ATTR, d)
	return n


## the faces drawn with slot i
static func faces_of(m: KMesh, i: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for fi in m.face_count():
		if face_slot(m, fi) == i:
			out.append(fi)
	return out


## faces per slot
static func counts(m: KMesh) -> PackedInt32Array:
	var c := PackedInt32Array()
	c.resize(m.materials.size())
	if c.is_empty():
		return c
	for fi in m.face_count():
		c[face_slot(m, fi)] += 1
	return c


## set one field of slot i (cleaned like clean()); returns the stored value
static func set_field(m: KMesh, i: int, key: String, value):
	var s: Dictionary = m.materials[i].duplicate()
	s[key] = value
	m.materials[i] = clean(s)
	return m.materials[i][key]


## E15: the slot wears a photo material (scripts/photo_material.gd's folder): its albedo, roughness and normal maps
static func from_photo(slot: Dictionary, name: String) -> Dictionary:
	var dir := "%s/%s" % [PhotoMaterial.DIR, PhotoMaterial.clean_name(name)]
	return clean(slot.merged({"albedo": Color.WHITE, "roughness": 1.0, "albedo_tex": dir + "/albedo.png", "roughness_tex": dir + "/rough.png", "normal_tex": dir + "/normal.png"}, true))


## the photo materials there are (the folder names under user://materials)
static func photo_names() -> PackedStringArray:
	var da := DirAccess.open(PhotoMaterial.DIR)
	return da.get_directories() if da != null else PackedStringArray()


# ---------------------------------------------------------------- the file (.kmesh "materials") and undo

## JSON-ready: one dictionary per slot, colours as [r, g, b, a]
static func to_file(mats: Array) -> Array:
	var out := []
	for s in mats:
		var d := {}
		for k in FIELDS:
			var v = s.get(k, FIELDS[k])
			d[k] = [v.r, v.g, v.b, v.a] if v is Color else v
		out.append(d)
	return out


## from to_file's form; [] for none. A damaged block sets KMesh.last_error (and returns [])
static func from_file(a) -> Array:
	var out := []
	if a == null:
		return out
	if not (a is Array):
		KMesh.last_error = "the materials block is damaged. Re-save the mesh from the app, or restore a backup."
		return []
	for d in a:
		if not (d is Dictionary):
			KMesh.last_error = "a material slot is damaged. Re-save the mesh from the app, or restore a backup."
			return []
		var s := {}
		for k in FIELDS:
			if not d.has(k):
				continue
			var v = d[k]
			if k in COL_KEYS:
				if not (v is Array) or v.size() != 4:
					KMesh.last_error = "material '%s' has a bad %s colour. Re-save the mesh from the app, or restore a backup." % [str(d.get("name", "?")), k]
					return []
				v = Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
			s[k] = v
		out.append(clean(s))
	return out


## a copy that shares nothing with the live list (an undo snapshot)
static func snapshot(mats: Array) -> Array:
	return mats.duplicate(true)


# ---------------------------------------------------------------- drawing

static func texture(path: String) -> Texture2D:
	if path == "":
		return null
	var t := FileAccess.get_modified_time(path)
	if _tex_cache.has(path) and _tex_cache[path][0] == t:
		return _tex_cache[path][1]
	var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
	if img == null or img.is_empty():
		return null
	img.generate_mipmaps()
	var tx := ImageTexture.create_from_image(img)
	_tex_cache[path] = [t, tx]
	return tx


## the StandardMaterial3D of a slot. triplanar: no UVs on the mesh, so the maps are projected (1 tile per metre)
static func material(s: Dictionary, triplanar := true) -> StandardMaterial3D:
	var mt := StandardMaterial3D.new()
	mt.cull_mode = BaseMaterial3D.CULL_BACK
	mt.albedo_color = s["albedo"]
	mt.albedo_texture = texture(s["albedo_tex"])
	if s["albedo"].a < 1.0:
		mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.metallic = s["metallic"]
	mt.metallic_specular = 0.5
	mt.metallic_texture = texture(s["metallic_tex"])
	mt.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	mt.roughness = s["roughness"]
	mt.roughness_texture = texture(s["roughness_tex"])
	mt.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	var nt := texture(s["normal_tex"])
	if nt != null:
		mt.normal_enabled = true
		mt.normal_texture = nt
		mt.normal_scale = s["normal_scale"]
	var at := texture(s["ao_tex"])
	if at != null:
		mt.ao_enabled = true
		mt.ao_texture = at
		mt.ao_light_affect = s["ao"]
		mt.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	var et := texture(s["emission_tex"])
	if s["emission_energy"] > 0.0 or et != null:
		mt.emission_enabled = true
		mt.emission = s["emission"]
		mt.emission_energy_multiplier = s["emission_energy"]
		mt.emission_texture = et
	var st := texture(s["sss_tex"])
	if s["sss"] > 0.0:
		mt.subsurf_scatter_enabled = true
		mt.subsurf_scatter_strength = s["sss"]
		mt.subsurf_scatter_skin_mode = true
		mt.subsurf_scatter_texture = st
	if triplanar:
		mt.uv1_triplanar = true
		mt.uv1_scale = Vector3.ONE
	mt.texture_repeat = true
	return mt


## The view's surface: one ArrayMesh surface per slot that has faces, in slot order, named after the slot; flat (or
## smooth) normals, Godot's clockwise winding (as KMeshView._surface), UVs from a "uv" corner attribute when there is
## one (tangents generated for the normal map). Returns {"mesh": ArrayMesh, "slots": [slot of each surface],
## "faces": [faces of each surface]}.
static func build(m: KMesh, smooth := false) -> Dictionary:
	var ns := maxi(m.materials.size(), 1)
	var by: Array = []
	for i in ns:
		by.append(PackedInt32Array())
	for fi in m.face_count():
		by[face_slot(m, fi)].append(fi)
	var ud = m.attr_data("uv") if m.has_attr("uv") and m.attr_info("uv")["domain"] == KMesh.AD_CORNER and m.attr_info("uv")["type"] == TYPE_VECTOR2 else null
	var am := ArrayMesh.new()
	var slots := []
	var nfaces := []
	for i in ns:
		var fs: PackedInt32Array = by[i]
		if fs.is_empty():
			continue
		var pos := PackedVector3Array()
		var nor := PackedVector3Array()
		var uvs := PackedVector2Array()
		for fi in fs:
			var fp: PackedInt32Array = m.faces[fi]
			for k in range(1, fp.size() - 1):
				for c in [0, k + 1, k]:
					pos.append(m.verts[fp[c]])
					nor.append(m.vert_normals[fp[c]] if smooth else m.face_normals[fi])
					if ud != null:
						uvs.append(ud[m.face_he0[fi] + c])
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_NORMAL] = nor
		if ud != null:
			arr[Mesh.ARRAY_TEX_UV] = uvs
			var stl := SurfaceTool.new()
			stl.create_from_arrays(arr)
			stl.generate_tangents()
			arr = stl.commit_to_arrays()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var si := am.get_surface_count() - 1
		if not m.materials.is_empty():
			am.surface_set_name(si, String(m.materials[i]["name"]))
			am.surface_set_material(si, material(m.materials[i], ud == null))
		slots.append(i)
		nfaces.append(fs.size())
	return {"mesh": am, "slots": slots, "faces": nfaces}


## KMeshView hook: put the per-slot surfaces on the view's surface node (no override: each surface has its material)
static func dress(mi: MeshInstance3D, m: KMesh, smooth := false) -> Dictionary:
	var r := build(m, smooth)
	mi.mesh = r["mesh"]
	mi.material_override = null
	mi.set_meta("mat_slots", r["slots"])
	mi.set_meta("mat_faces", r["faces"])
	return r
