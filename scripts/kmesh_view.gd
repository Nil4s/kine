class_name KMeshView
extends Node3D
## KMeshView: draws a KMesh in the 3D viewport and picks on it (ROADMAP_400 A05 + A06).
## DRAW: a shaded surface (flat normals, back faces culled), a wire over it (every edge, pushed 3 mm out along the vertex
## normal so it lands on top of the surface), the verts as points in vert mode, and the selection in Tok "pick_sel":
## selected faces tinted (a see-through layer 1.5 mm off the face), selected edges as brighter lines, selected verts as
## bigger points. Everything is rebuilt only when `dirty` is set (mark_dirty(), set_mesh(), a palette switch).
## PICK (all in screen space, the mesh in this node's local space, so a moved / scaled view picks the same):
##   ray_face: nearest front-facing triangle under a ray (per-face AABB pass, then Moller-Trumbore over the fan triangles;
##     fine for < 100k tris), pick: the face under the mouse + the nearest vert / edge of THAT face within PICK_PX (12 px),
##   select_region: box / lasso (any 2D test) over verts / edges / faces by the selection mode. Without x-ray only what the
##     camera can see counts (a vertex is seen when the nearest front-facing hit on its view ray is the vertex's own
##     distance, a face when it faces the camera and its centre is seen); with x-ray everything inside the shape counts.
## HEAT (F08, show_heat): KMeshTopo.heat's faces as a colour tint (triangles, n-gons, stretched quads) and its poles as
## big coloured points, rebuilt with the mesh; `heat` holds the last result (the legend's counts).

signal rebuilt   # A11: after every rebuild (the modifier stack's surface re-evaluates when the base changed)

const OFF_WIRE := 0.003
const OFF_TINT := 0.0015
const PICK_PX := 12.0
const RAY_TOL := 1e-5   # ray_face's edge slack, relative to the distance (10 um at 1 m: far below a pixel)

var mesh: KMesh
var sel: KMeshSelect
var dirty := true
var show_wire := true
var show_verts := true   # points in vert mode
var smooth_shade := false   # C01: the sculpt sphere shades with the vertex normals (the MODEL cube stays flat)
## D05 surface shading: "" plain, "uv_checker" (the KMeshUV checker through the "uv" corner attribute), "uv_stretch"
## (KMeshUV.stretch heat per face, blue = no distortion, red = stretched or flipped)
var shading := ""
var stretch := {}        # the last KMeshUV.stretch result while shading is "uv_stretch"
var show_color := false  # E04: the surface takes the "color" attribute (vertex paint, scripts/kmesh_vpaint.gd)
var _pal_dark := true
var show_heat := false
var heat := {}

var _surf: MeshInstance3D
var _tint: MeshInstance3D
var _wire: MeshInstance3D
var _selwire: MeshInstance3D
var _pts: MeshInstance3D
var _selpts: MeshInstance3D
var _heat: MeshInstance3D
var _heatpts: MeshInstance3D

# pick caches (rebuilt with the mesh)
var _tri := PackedInt32Array()       # 3 vert ids per fan triangle
var _tri_face := PackedInt32Array()  # the face of each triangle
var _fbox: Array = []                # AABB of each face (local space)
var _ftri0 := PackedInt32Array()     # first triangle of each face (triangles of a face are consecutive)
var _ftri_n := PackedInt32Array()


func _init() -> void:
	for nm in ["_surf", "_tint", "_wire", "_selwire", "_pts", "_selpts", "_heat", "_heatpts"]:
		var mi := MeshInstance3D.new()
		mi.name = nm.trim_prefix("_")
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if nm != "_surf" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		set(nm, mi)
		add_child(mi)


func set_mesh(m: KMesh, s: KMeshSelect = null) -> void:
	mesh = m
	sel = s if s != null else KMeshSelect.new(m)
	dirty = true


func mark_dirty() -> void:
	dirty = true


func _process(_dt: float) -> void:
	if Tok.dark != _pal_dark:
		dirty = true
	if dirty:
		rebuild()


## a unit cube of side `side` centred on the origin, n x n quads per side, welded (shared verts), faces CCW from outside
static func make_cube(side := 1.0, n := 4) -> KMesh:
	var vs := PackedVector3Array()
	var fs: Array = []
	var ids := {}
	var h := side * 0.5
	for a in 3:
		for s in [-1, 1]:
			var u := (a + 1) % 3
			var v := (a + 2) % 3
			var corner := func(i: int, j: int) -> int:
				var ix := [0, 0, 0]
				ix[a] = n if s > 0 else 0
				ix[u] = i
				ix[v] = j
				var key: int = ix[0] * 4096 + ix[1] * 64 + ix[2]
				if not ids.has(key):
					ids[key] = vs.size()
					var p := Vector3.ZERO
					for k in 3:
						p[k] = -h + side * float(ix[k]) / float(n)
					vs.append(p)
				return ids[key]
			for i in n:
				for j in n:
					var q: Array = [corner.call(i, j), corner.call(i + 1, j), corner.call(i + 1, j + 1), corner.call(i, j + 1)]
					if s < 0:
						q.reverse()
					fs.append(q)
	return KMesh.new().from_arrays(vs, fs)


# ---------------------------------------------------------------- drawing

func _mat(col: Color, lit := false, point := 0.0) -> StandardMaterial3D:
	var mt := StandardMaterial3D.new()
	mt.albedo_color = col
	if col.a < 1.0:
		mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if not lit:
		mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	else:
		mt.roughness = 0.8
	mt.cull_mode = BaseMaterial3D.CULL_BACK
	if point > 0.0:
		mt.use_point_size = true
		mt.point_size = point
	return mt


func _put(mi: MeshInstance3D, prim: int, pos: PackedVector3Array, mt: Material) -> void:
	if pos.is_empty():
		mi.mesh = null
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(prim, arr)
	mi.mesh = am
	mi.material_override = mt


## flat-shaded surface with Godot's winding (KMesh.to_array_mesh keeps the counter-clockwise order, which Godot would cull
## as back faces, so a back-face-culled view of it shows the inside of the far side)
func _surface() -> ArrayMesh:
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var ud = mesh.attr_data(KMeshUV.UV) if shading == "uv_checker" and mesh.has_attr(KMeshUV.UV) and mesh.attr_info(KMeshUV.UV)["domain"] == KMesh.AD_CORNER else null
	stretch = KMeshUV.stretch(mesh) if shading == "uv_stretch" else {}
	var cd = mesh.attr_data("color") if show_color and ud == null and stretch.is_empty() and KMeshVPaint.usable(mesh) else null
	var cv: bool = cd != null and mesh.attr_info("color")["domain"] == KMesh.AD_VERT
	for fi in mesh.face_count():
		var fp: PackedInt32Array = mesh.faces[fi]
		for i in range(1, fp.size() - 1):
			for c in [0, i + 1, i]:
				pos.append(mesh.verts[fp[c]])
				nor.append(mesh.vert_normals[fp[c]] if smooth_shade else mesh.face_normals[fi])
				if ud != null:
					uvs.append(ud[mesh.face_he0[fi] + c])
				elif not stretch.is_empty():
					cols.append(KMeshUV.heat_color(stretch["heat"][fi]))
				elif cd != null:
					cols.append(cd[fp[c]] if cv else cd[mesh.face_he0[fi] + c])
	var am := ArrayMesh.new()
	if pos.is_empty():
		return am
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nor
	if not uvs.is_empty():
		arr[Mesh.ARRAY_TEX_UV] = uvs
	if not cols.is_empty():
		arr[Mesh.ARRAY_COLOR] = cols
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


func _out(v: int, off: float) -> Vector3:
	return mesh.verts[v] + mesh.vert_normals[v] * off


func rebuild() -> void:
	dirty = false
	_pal_dark = Tok.dark
	if mesh == null:
		return
	_build_pick_cache()
	var sel_col := Tok.c("pick_sel")
	_surf.mesh = _surface()
	_surf.material_override = _mat(Tok.c("cube"), true)
	if shading == "uv_checker" and _surf.mesh.get_surface_count() > 0 and _surf.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_TEX_UV:
		_surf.material_override = KMeshUV.checker_material()
	elif not stretch.is_empty():
		_surf.material_override = KMeshUV.heat_material()
	elif show_color and _surf.mesh.get_surface_count() > 0 and _surf.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR:
		_surf.material_override.vertex_color_use_as_albedo = true   # E04: the painted colours (times the plain white albedo)
		_surf.material_override.vertex_color_is_srgb = true
		_surf.material_override.albedo_color = Color.WHITE
	elif shading == "" and not mesh.materials.is_empty():   # E01: one surface per material slot (scripts/kmesh_material.gd)
		KMeshMaterial.dress(_surf, mesh, smooth_shade)
	# wire: every edge
	var wp := PackedVector3Array()
	if show_wire:
		for e in mesh.edges():
			wp.append(_out(e.x, OFF_WIRE))
			wp.append(_out(e.y, OFF_WIRE))
	_put(_wire, Mesh.PRIMITIVE_LINES, wp, _mat(Tok.c("cube_edge")))
	# selected faces: tinted layer
	var tp := PackedVector3Array()
	for fi in sel.faces:
		var fp: PackedInt32Array = mesh.faces[fi]
		var nn := mesh.face_normals[fi] * OFF_TINT
		for i in range(1, fp.size() - 1):
			tp.append(mesh.verts[fp[0]] + nn)   # Godot's front face is CLOCKWISE; KMesh is counter-clockwise: swap two corners
			tp.append(mesh.verts[fp[i + 1]] + nn)
			tp.append(mesh.verts[fp[i]] + nn)
	_put(_tint, Mesh.PRIMITIVE_TRIANGLES, tp, _mat(Color(sel_col, 0.6)))
	# selected edges
	var sp := PackedVector3Array()
	for e in sel.edges:
		sp.append(_out(e.x, OFF_WIRE * 1.5))
		sp.append(_out(e.y, OFF_WIRE * 1.5))
	_put(_selwire, Mesh.PRIMITIVE_LINES, sp, _mat(sel_col))
	# verts (vert mode only)
	var pp := PackedVector3Array()
	var qp := PackedVector3Array()
	if sel.mode == KMeshSelect.VERT and show_verts:
		for v in mesh.vert_count():
			if sel.verts.has(v):
				qp.append(_out(v, OFF_WIRE * 2.0))
			else:
				pp.append(_out(v, OFF_WIRE * 2.0))
	_put(_pts, Mesh.PRIMITIVE_POINTS, pp, _mat(Tok.c("cube_edge"), false, 5.0))
	_put(_selpts, Mesh.PRIMITIVE_POINTS, qp, _mat(sel_col, false, 9.0))
	_build_heat()
	rebuilt.emit()


## F08: the heat layer (vertex colours: one material for every kind)
func _build_heat() -> void:
	heat = KMeshTopo.heat(mesh) if show_heat else {}
	var hp := PackedVector3Array()
	var hc := PackedColorArray()
	var vp := PackedVector3Array()
	var vc := PackedColorArray()
	if show_heat:
		var fk: PackedInt32Array = heat["face"]
		for fi in fk.size():
			if fk[fi] == KMeshTopo.F_QUAD:
				continue
			var col := Color(KMeshTopo.color_of(KMeshTopo.F_KEY[fk[fi]]), 0.75)
			var fp: PackedInt32Array = mesh.faces[fi]
			var nn := mesh.face_normals[fi] * OFF_TINT
			for t in KMeshTopo.face_tris(mesh, fp):
				for c in [t[0], t[2], t[1]]:   # Godot's clockwise front face
					hp.append(mesh.verts[fp[c]] + nn)
					hc.append(col)
		var vk: PackedInt32Array = heat["vert"]
		for v in vk.size():
			if vk[v] != KMeshTopo.V_OK:
				vp.append(_out(v, OFF_WIRE * 2.5))
				vc.append(KMeshTopo.color_of(KMeshTopo.V_KEY[vk[v]]))
	_put_col(_heat, Mesh.PRIMITIVE_TRIANGLES, hp, hc, _mat(Color(1, 1, 1, 0.99)))
	_put_col(_heatpts, Mesh.PRIMITIVE_POINTS, vp, vc, _mat(Color.WHITE, false, 12.0))


func _put_col(mi: MeshInstance3D, prim: int, pos: PackedVector3Array, cols: PackedColorArray, mt: StandardMaterial3D) -> void:
	mt.vertex_color_use_as_albedo = true
	if pos.is_empty():
		mi.mesh = null
		return
	mi.material_override = mt
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_COLOR] = cols
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(prim, arr)
	mi.mesh = am


# ---------------------------------------------------------------- picking

func _build_pick_cache() -> void:
	_tri = PackedInt32Array()
	_tri_face = PackedInt32Array()
	_ftri0 = PackedInt32Array()
	_ftri_n = PackedInt32Array()
	_fbox = []
	for fi in mesh.face_count():
		var fp: PackedInt32Array = mesh.faces[fi]
		_ftri0.append(_tri_face.size())
		_ftri_n.append(maxi(fp.size() - 2, 0))
		var bb := AABB(mesh.verts[fp[0]], Vector3.ZERO)
		for v in fp:
			bb = bb.expand(mesh.verts[v])
		_fbox.append(bb.grow(1e-4))
		for i in range(1, fp.size() - 1):
			_tri.append(fp[0])
			_tri.append(fp[i])
			_tri.append(fp[i + 1])
			_tri_face.append(fi)


func _ensure() -> void:
	if dirty or _fbox.size() != mesh.face_count():
		rebuild()


## nearest front-facing hit of the world ray (origin, dir): {"face", "t" (along dir as given), "point"} or {}.
## backfaces=true also hits faces seen from behind (x-ray through the shell's far side is NOT this: it is select-only).
func ray_face(origin_w: Vector3, dir_w: Vector3, backfaces := false) -> Dictionary:
	if mesh == null:
		return {}
	_ensure()
	var inv := global_transform.affine_inverse()
	var o := inv * origin_w
	var d := inv.basis * dir_w
	var best_t := INF
	var best_f := -1
	for fi in _fbox.size():
		if (_fbox[fi] as AABB).intersects_ray(o, d) == null:
			continue
		var t0 := _ftri0[fi]
		for k in _ftri_n[fi]:
			var ti := (t0 + k) * 3
			var a := mesh.verts[_tri[ti]]
			var e1 := mesh.verts[_tri[ti + 1]] - a
			var e2 := mesh.verts[_tri[ti + 2]] - a
			var p := d.cross(e2)
			var det := e1.dot(p)
			if backfaces:
				if absf(det) < 1e-14:
					continue
			elif det <= 1e-14:
				continue
			var iv := 1.0 / det
			var tv := o - a
			var u := tv.dot(p) * iv
			var q := tv.cross(e1)
			var v := d.dot(q) * iv
			if u < 0.0 or v < 0.0 or u + v > 1.0:
				# epsilon-inclusive edges: the ray may pass up to RAY_TOL x the distance (perpendicular to the ray) outside the
				# triangle. A click exactly on a projected vertex otherwise slips between the triangles sharing it (float32
				# round-off in the ray, ~1e-7 relative) and misses at silhouettes. A shift s across the edge opposite a corner
				# moves that corner's barycentric weight by s * |d x edge| / |det|, so each weight gets its own slack.
				var tol := RAY_TOL * tv.length() / absf(det)
				if u < -tol * p.length() or v < -tol * e1.cross(d).length() or u + v > 1.0 + tol * d.cross(e2 - e1).length():
					continue
			var t := e2.dot(q) * iv
			if t > 1e-6 and t < best_t:
				best_t = t
				best_f = fi
	if best_f < 0:
		return {}
	return {"face": best_f, "t": best_t, "point": origin_w + dir_w * best_t}


func ray_at(cam: Camera3D, p: Vector2) -> Array:
	return [cam.project_ray_origin(p), cam.project_ray_normal(p)]


func _to_world(v: int) -> Vector3:
	return global_transform * mesh.verts[v]


func _screen(cam: Camera3D, wp: Vector3) -> Variant:
	if cam.is_position_behind(wp):
		return null
	return cam.unproject_position(wp)


func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-9:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0))


## what is under screen point p: {"face", "vert" (-1 if none within px), "edge" (Vector2i(-1,-1) if none), "t"} or {} on a miss.
## vert / edge are the nearest corner / side of the HIT face within `px` screen pixels.
func pick(cam: Camera3D, p: Vector2, px := PICK_PX) -> Dictionary:
	var r := ray_at(cam, p)
	var h := ray_face(r[0], r[1])
	if h.is_empty():
		return {}
	var fi: int = h["face"]
	var fp: PackedInt32Array = mesh.faces[fi]
	var bv := -1
	var bd := px
	var be := Vector2i(-1, -1)
	var ed := px
	var sp: Array = []
	for v in fp:
		sp.append(_screen(cam, _to_world(v)))
	for i in fp.size():
		var a: Variant = sp[i]
		var b: Variant = sp[(i + 1) % fp.size()]
		if a != null:
			var dv := p.distance_to(a)
			if dv <= bd:
				bd = dv
				bv = fp[i]
		if a != null and b != null:
			var de := _seg_dist(p, a, b)
			if de <= ed:
				ed = de
				be = KMeshSelect.ekey(fp[i], fp[(i + 1) % fp.size()])
	return {"face": fi, "vert": bv, "edge": be, "t": h["t"]}


## is world point wp seen from the camera (nothing front-facing nearer on its view ray)?
func point_visible(cam: Camera3D, wp: Vector3) -> bool:
	var sp: Variant = _screen(cam, wp)
	if sp == null:
		return false
	var r := ray_at(cam, sp)
	var dist: float = (wp - (r[0] as Vector3)).dot(r[1])
	var h := ray_face(r[0], r[1])
	return h.is_empty() or float(h["t"]) >= dist - maxf(1e-3, dist * 1e-4)


## Click at p in the current selection mode. Plain: replace (a miss clears). additive (Shift): toggle the element hit.
## Returns true when something was hit.
func click(cam: Camera3D, p: Vector2, additive := false) -> bool:
	var h := pick(cam, p)
	var key: Variant = null
	if not h.is_empty():
		match sel.mode:
			KMeshSelect.VERT:
				if int(h["vert"]) >= 0:
					key = int(h["vert"])
			KMeshSelect.EDGE:
				if (h["edge"] as Vector2i).x >= 0:
					key = h["edge"]
			_:
				key = int(h["face"])
	var live: Dictionary = sel._live()
	if not additive:
		var had := not live.is_empty()
		sel.clear()
		live = sel._live()
		if key != null:
			live[key] = true
		if had or key != null:
			dirty = true
	elif key != null:
		if live.has(key):
			live.erase(key)
		else:
			live[key] = true
		dirty = true
	return key != null


## Box / lasso: `inside` is a Callable(Vector2) -> bool in screen space. Selects by the mode: verts inside; edges with
## both ends inside; faces whose centre is inside. Without xray only what is seen counts. additive keeps the old set.
## Returns the number selected after.
func select_region(cam: Camera3D, inside: Callable, xray := false, additive := false) -> int:
	_ensure()
	if not additive:
		sel.clear()
	var vin := {}
	for v in mesh.vert_count():
		var wp := _to_world(v)
		var sp: Variant = _screen(cam, wp)
		if sp != null and inside.call(sp) and (xray or point_visible(cam, wp)):
			vin[v] = true
	var live: Dictionary = sel._live()
	match sel.mode:
		KMeshSelect.VERT:
			for v in vin:
				live[v] = true
		KMeshSelect.EDGE:
			for e in mesh.edges():
				if vin.has(e.x) and vin.has(e.y):
					live[e] = true
		_:
			for fi in mesh.face_count():
				var wc := global_transform * mesh.face_center(fi)
				var sp: Variant = _screen(cam, wc)
				if sp == null or not inside.call(sp):
					continue
				if not xray:
					var wn := (global_transform.basis * mesh.face_normals[fi]).normalized()
					var to_cam := (cam.global_position - wc) if cam.projection == Camera3D.PROJECTION_PERSPECTIVE else cam.global_transform.basis.z
					if wn.dot(to_cam) <= 0.0 or not point_visible(cam, wc + wn * 1e-3):
						continue
				live[fi] = true
	dirty = true
	return live.size()


func select_box(cam: Camera3D, r: Rect2, xray := false, additive := false) -> int:
	return select_region(cam, func(s: Vector2) -> bool: return r.has_point(s), xray, additive)


func select_lasso(cam: Camera3D, poly: PackedVector2Array, xray := false, additive := false) -> int:
	if poly.size() < 3:
		return select_region(cam, func(_s): return false, xray, additive)
	return select_region(cam, func(s: Vector2) -> bool: return Geometry2D.is_point_in_polygon(s, poly), xray, additive)
