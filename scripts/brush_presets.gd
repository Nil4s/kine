class_name BrushPresets
extends Node
## BRUSH PRESETS (ROADMAP_400 C14): a preset is a sculpt brush set up, every field the sculpt page (scripts/kmesh_sculpt_ui.gd)
## strokes with: brush, radius (m), strength (m per dab), falloff, spacing (fraction of the radius between dabs), and the
## symmetry flags (sym_x / sym_y / sym_z, radial copies 1..32 and the radial axis 0 1 2 = X Y Z). apply() sets every one of
## them on the sculpt UI exactly; nothing else changes. The panel is scripts/brush_presets_panel.gd (B in sculpt).
## C08: a preset may also carry an "alpha" (an alpha's name, scripts/sculpt_alphas.gd); apply() sets it, and a preset without
##   one clears the UI's alpha. It is left out of a preset that has none, so the older presets and their thumbnails stay as they were.
## SHIPPED: SHIPPED below (12). USER presets: user://brush_presets.json ("Save current brush as preset"; a name already there is
##   replaced). FAVOURITES: the starred names, user://brush_favourites.json; the panel lists them first. Both are written
##   with full float precision, so a saved radius comes back == the one saved.
## THUMBNAILS: the preset's stroke run for real (KMeshSculpt) across a small bumpy plane (0.4 m, 40 x 40 quads, a ripple
##   of 1.5 mm so smooth and flatten have something to take away), heights drawn LIFT (4) x, drawn off screen with the clay matcap
##   (scripts/sculpt_matcap.gd; the mask brush's paint shows as a blue tint through the vertex colour), cached in
##   user://brush_thumbs/<sha256 of the fields>.png: drawn once per install, not once per open.

signal made(key: String)

const USER := "user://brush_presets.json"
const FAVS := "user://brush_favourites.json"
const DIR := "user://brush_thumbs"
const SIZE := Vector2i(64, 64)
const STAGE_V := "3"   # part of the cache key: a changed stage draws every thumbnail again
const FIELDS := ["brush", "radius", "strength", "falloff", "spacing", "sym_x", "sym_y", "sym_z", "radial", "radial_axis"]
const PLANE := 0.4
const PLANE_N := 40
const RIPPLE := 0.0015   # m: the plane's bumps (smooth and flatten need something to take away)
const LIFT := 4.0        # the thumbnail draws heights 4 x: a few mm of stroke on a 0.4 m plane reads at 64 px

const SHIPPED := [
	{"name": "Clay buildup", "brush": KMeshSculpt.CLAY, "radius": 0.06, "strength": 0.003, "falloff": KMeshSculpt.F_SMOOTH, "spacing": 0.1, "sym_x": true, "sym_y": false, "sym_z": false, "radial": 1, "radial_axis": 1},
	{"name": "Draw medium", "brush": KMeshSculpt.DRAW, "radius": 0.08, "strength": 0.004, "falloff": KMeshSculpt.F_SMOOTH, "spacing": 0.1, "sym_x": true, "sym_y": false, "sym_z": false, "radial": 1, "radial_axis": 1},
	{"name": "Smooth soft", "brush": KMeshSculpt.SMOOTH, "radius": 0.1, "strength": 0.004, "falloff": KMeshSculpt.F_SPHERE, "spacing": 0.1, "sym_x": true, "sym_y": false, "sym_z": false, "radial": 1, "radial_axis": 1},
	{"name": "Crease sharp", "brush": KMeshSculpt.CREASE, "radius": 0.03, "strength": 0.003, "falloff": KMeshSculpt.F_SHARP, "spacing": 0.08, "sym_x": true, "sym_y": false, "sym_z": false, "radial": 1, "radial_axis": 1},
	{"name": "Pinch fine", "brush": KMeshSculpt.PINCH, "radius": 0.025, "strength": 0.002, "falloff": KMeshSculpt.F_SHARP, "spacing": 0.1, "sym_x": true, "sym_y": false, "sym_z": false, "radial": 1, "radial_axis": 1},
	{"name": "Inflate big", "brush": KMeshSculpt.INFLATE, "radius": 0.14, "strength": 0.003, "falloff": KMeshSculpt.F_SMOOTH, "spacing": 0.12, "sym_x": true, "sym_y": false, "sym_z": false, "radial": 1, "radial_axis": 1},
	{"name": "Grab large", "brush": KMeshSculpt.GRAB, "radius": 0.18, "strength": 0.004, "falloff": KMeshSculpt.F_SMOOTH, "spacing": 0.1, "sym_x": true, "sym_y": false, "sym_z": false, "radial": 1, "radial_axis": 1},
	{"name": "Flatten plane", "brush": KMeshSculpt.FLATTEN, "radius": 0.09, "strength": 0.004, "falloff": KMeshSculpt.F_LINEAR, "spacing": 0.1, "sym_x": true, "sym_y": false, "sym_z": false, "radial": 1, "radial_axis": 1},
	{"name": "Mask paint", "brush": KMeshSculpt.MASK, "radius": 0.05, "strength": 0.004, "falloff": KMeshSculpt.F_SMOOTH, "spacing": 0.1, "sym_x": true, "sym_y": false, "sym_z": false, "radial": 1, "radial_axis": 1},
	{"name": "Snake hook", "brush": KMeshSculpt.SNAKE, "radius": 0.05, "strength": 0.004, "falloff": KMeshSculpt.F_SMOOTH, "spacing": 0.1, "sym_x": false, "sym_y": false, "sym_z": false, "radial": 1, "radial_axis": 1},
	{"name": "Radial draw x8", "brush": KMeshSculpt.DRAW, "radius": 0.04, "strength": 0.003, "falloff": KMeshSculpt.F_SMOOTH, "spacing": 0.1, "sym_x": false, "sym_y": false, "sym_z": false, "radial": 8, "radial_axis": 1},
	{"name": "Skin pores", "brush": KMeshSculpt.DRAW, "radius": 0.035, "strength": 0.002, "falloff": KMeshSculpt.F_SMOOTH, "spacing": 0.7, "sym_x": false, "sym_y": false, "sym_z": false, "radial": 1, "radial_axis": 1, "alpha": "pores"},
]

var renders := 0     # thumbnails drawn this session (the test counts them)
var disk_hits := 0
var _tex := {}
var _vp: SubViewport
var _plane: MeshInstance3D
var _drawing := false


# ---------------------------------------------------------------- the presets

## a preset with every field present and of its type ({} when it cannot be one)
static func clean(p: Variant) -> Dictionary:
	if not (p is Dictionary):
		return {}
	var d := p as Dictionary
	var br := String(d.get("brush", ""))
	if not (KMeshSculpt.BRUSHES.has(br) or br == KMeshSculpt.MASK):
		return {}
	var fo := String(d.get("falloff", KMeshSculpt.F_SMOOTH))
	if not KMeshSculpt.FALLOFFS.has(fo):
		fo = KMeshSculpt.F_SMOOTH
	return {"name": String(d.get("name", "Brush")), "brush": br, "radius": clampf(float(d.get("radius", 0.08)), 0.01, 0.5),
		"strength": clampf(float(d.get("strength", 0.004)), 0.0002, 0.05), "falloff": fo,
		"spacing": clampf(float(d.get("spacing", 0.1)), 0.01, 1.0), "sym_x": bool(d.get("sym_x", false)),
		"sym_y": bool(d.get("sym_y", false)), "sym_z": bool(d.get("sym_z", false)),
		"radial": clampi(int(d.get("radial", 1)), 1, KMeshSculptSym.MAX_RADIAL), "radial_axis": clampi(int(d.get("radial_axis", 1)), 0, 2)}.merged(
		{"alpha": String(d["alpha"])} if d.get("alpha") is String and String(d["alpha"]) != "" else {})


static func shipped() -> Array:
	var out := []
	for p in SHIPPED:
		var e := clean(p)
		e["user"] = false
		out.append(e)
	return out


static func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func _write(path: String, data: Variant) -> int:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "\t", true, true))   # full precision: a radius comes back ==
	f.close()
	return OK


static func user_presets() -> Array:
	var out := []
	var d: Variant = _read(USER)
	if d is Dictionary and (d as Dictionary).get("presets") is Array:
		for p in d["presets"]:
			var e := clean(p)
			if not e.is_empty():
				e["user"] = true
				out.append(e)
	return out


## shipped + the user's, the user's last
static func all() -> Array:
	return shipped() + user_presets()


static func find(nm: String) -> Dictionary:
	var hit := {}
	for e in all():   # a user preset of a shipped name wins (it comes later)
		if String(e["name"]).to_lower() == nm.to_lower():
			hit = e
	return hit


## add (or replace, by name) a preset in the user file; OK or an error
static func save_user(p: Dictionary) -> int:
	var e := clean(p)
	if e.is_empty():
		return ERR_INVALID_DATA
	var keep := []
	for u in user_presets():
		if u["name"] != e["name"]:
			u.erase("user")
			keep.append(u)
	keep.append(e)
	return _write(USER, {"presets": keep})


static func remove_user(nm: String) -> int:
	var keep := []
	for u in user_presets():
		if u["name"] != nm:
			u.erase("user")
			keep.append(u)
	return _write(USER, {"presets": keep})


static func favourites() -> Array:
	var d: Variant = _read(FAVS)
	var out := []
	if d is Dictionary and (d as Dictionary).get("favourites") is Array:
		for n in d["favourites"]:
			out.append(String(n))
	return out


static func is_favourite(nm: String) -> bool:
	return favourites().has(nm)


static func set_favourite(nm: String, on: bool) -> int:
	var f := favourites()
	if on and not f.has(nm):
		f.append(nm)
	elif not on:
		f.erase(nm)
	return _write(FAVS, {"favourites": f})


## the fields of the sculpt UI as a preset
static func of_ui(ui, nm := "My brush") -> Dictionary:
	var p := {"name": nm}
	for k in FIELDS:
		p[k] = ui.get(k)
	if ui.get("alpha") is String and String(ui.get("alpha")) != "":   # C08
		p["alpha"] = ui.get("alpha")
	return p


## every field of the preset onto the sculpt UI, exactly
static func apply(ui, p: Dictionary) -> void:
	for k in FIELDS:
		ui.set(k, p[k])
	if "alpha" in ui:   # C08: a preset without an alpha clears it
		ui.set("alpha", String(p.get("alpha", "")))


## true when every field of the sculpt UI equals the preset's
static func matches_ui(ui, p: Dictionary) -> bool:
	for k in FIELDS:
		if ui.get(k) != p[k]:
			return false
	return not ("alpha" in ui) or String(ui.get("alpha")) == String(p.get("alpha", ""))


# ---------------------------------------------------------------- the thumbnail stroke

## the bumpy plane the thumbnail stroke runs over (XZ, facing +Y)
static func base_plane() -> KMesh:
	var m := KMeshPrims.plane(PLANE, PLANE, PLANE_N, PLANE_N)
	for v in m.verts.size():
		var q := m.verts[v]
		m.verts[v] = Vector3(q.x, RIPPLE * sin(q.x * 31.0) * cos(q.z * 27.0), q.z)
	m.rebuild()
	return m


## the preset's stroke run on the plane: an S across it (grab / snake hook: a pull up and over). Pure, no nodes
static func stroke_mesh(p: Dictionary) -> KMesh:
	var m := base_plane()
	var sc := KMeshSculpt.new()
	var prm := p.duplicate()
	prm["invert"] = false
	sc.begin(m, prm)
	var n := 24
	for i in n + 1:
		var t := float(i) / n
		var pt: Vector3
		if p["brush"] == KMeshSculpt.GRAB or p["brush"] == KMeshSculpt.SNAKE:
			pt = Vector3(0.05 + 0.06 * t, 0.07 * t, 0.02 - 0.05 * t)
		else:
			pt = Vector3(lerpf(-0.13, 0.13, t), 0.0, 0.07 * sin(t * TAU))
		sc.to(pt, Vector3.UP, 1.0)
	sc.end()
	m.rebuild()
	if p["brush"] == KMeshSculpt.MASK:   # the mask as a tint the matcap shader multiplies by
		var mk := KMeshMask.values(m)
		m.add_attr("color", KMesh.AD_VERT, TYPE_COLOR, Color.WHITE)
		for v in mini(mk.size(), m.verts.size()):
			m.set_attr("color", v, Color.WHITE.lerp(Color(0.25, 0.4, 0.95), clampf(mk[v], 0.0, 1.0)))
	return m


static func key_of(p: Dictionary) -> String:
	var f := {}
	for k in FIELDS:
		f[k] = p[k]
	if String(p.get("alpha", "")) != "":
		f["alpha"] = p["alpha"]
	return (STAGE_V + JSON.stringify(f, "", true, true)).sha256_text()


static func cache_path(key: String) -> String:
	return "%s/%s.png" % [DIR, key]


func picture(p: Dictionary) -> Texture2D:
	return _tex.get(key_of(p))


## the thumbnail of a preset: memory, else the disk cache, else drawn now and cached. null if it cannot be drawn
func thumb(p: Dictionary) -> Texture2D:
	var key := key_of(p)
	if _tex.has(key):
		return _tex[key]
	var img: Image = null
	if FileAccess.file_exists(cache_path(key)):
		img = Image.load_from_file(ProjectSettings.globalize_path(cache_path(key)))
		if img != null and not img.is_empty():
			disk_hits += 1
	if img == null or img.is_empty():
		img = await draw(p)
		if img == null or img.is_empty():
			return null
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
		img.save_png(ProjectSettings.globalize_path(cache_path(key)))
	_tex[key] = ImageTexture.create_from_image(img)
	made.emit(key)
	return _tex[key]


func forget() -> void:
	_tex.clear()


func _frame() -> Signal:
	return (Engine.get_main_loop() as SceneTree).process_frame


## the preset's stroke drawn now; null when it cannot be (not in the tree)
func draw(p: Dictionary) -> Image:
	while _drawing:
		await _frame()
	_drawing = true
	_stage()
	var sm := stroke_mesh(p)
	for v in sm.verts.size():
		sm.verts[v].y *= LIFT
	sm.rebuild()
	_plane.mesh = _godot_facing(sm.to_array_mesh(true))
	await _frame()
	if not is_inside_tree() or _vp == null or not is_instance_valid(_vp):
		_drawing = false
		return null
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if not is_inside_tree() or _vp == null or not is_instance_valid(_vp):
		_drawing = false
		return null
	var img := _vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	renders += 1
	_drawing = false
	return img


## KMesh.to_array_mesh keeps KMesh's counter-clockwise triangles; Godot's front face is CLOCKWISE (see KMeshView), so the
## plane would be culled from above: each triangle's last two corners are swapped
static func _godot_facing(am: ArrayMesh) -> ArrayMesh:
	var a := am.surface_get_arrays(0)
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	for i in range(0, idx.size() - 2, 3):
		var t := idx[i + 1]
		idx[i + 1] = idx[i + 2]
		idx[i + 2] = t
	a[Mesh.ARRAY_INDEX] = idx
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return out


## the stage: the plane under the clay matcap, seen from above at a slant, its own world and a flat dark background
func _stage() -> void:
	if _vp != null:
		return
	_vp = SubViewport.new()
	_vp.name = "brush_thumb_stage"
	_vp.size = SIZE
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.msaa_3d = Quality.thumb_msaa() as Viewport.MSAA
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.14, 0.16)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	_plane = MeshInstance3D.new()
	_plane.material_override = SculptMatcap.material("clay")
	_vp.add_child(_plane)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 0.36
	_vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 0.5, 0.32), Vector3(0, 0.0, 0.0))
	cam.current = true
