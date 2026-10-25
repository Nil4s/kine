class_name KMeshVPaint
extends RefCounted
## Vertex paint core (ROADMAP_400 E04): a brush stroke is a run of DABS along the surface, like a sculpt stroke
## (scripts/kmesh_sculpt.gd: same spacing, same falloff curves, same pen pressure), but each dab blends a COLOUR into the
## A09 attribute "color" instead of moving verts. Pure: no nodes, no viewport. A stroke is begin(mesh, params) ...
## to(point, pressure) ... end(); the caller brackets it with KMeshUndo.begin / commit so one stroke is one undo step
## (KMeshUndo keeps the channel that changed, A09).
##   params: {"color", "mode" (blend), "radius" (m), "strength" (0..1 at the centre at full pressure), "falloff",
##            "spacing" (fraction of the radius between dabs), "blur" (the dab smooths the colours instead), "sym_x"}
## CHANNEL: "color", Color, on the CORNER domain (one value per face corner, KMesh corner order face_he0[f] + i), white by
## default. Why corners and not verts: a brush dab writes every corner of a vertex alike, so a stroke stays smooth across
## the faces, but FILL on selected faces writes only those faces' corners, so a filled face keeps a hard colour edge
## (a per-vert channel would bleed every fill into the neighbours: no flat-coloured panels, no clean material masks).
## It is also what glTF and Blender store (COLOR_0 per split vertex; Blender's default colour attribute is per corner).
## A vertex's colour (eyedropper, blur) is the mean of its corners. A channel already on the VERT domain is painted as it is.
## BLEND of the old colour d with the brush colour c at weight w = strength * falloff(d / radius) * pressure:
##   target t:  mix c   add d + c   subtract d - c   multiply d * c   lighten max(d, c)   darken min(d, c)   (rgb, clamped
##   0..1; alpha: mix takes c's, the others keep d's);   new = t * w + d * (1 - w)   (w = 1 gives t EXACTLY, no lerp drift)
## BLUR: toward the mean colour of the vertex's edge neighbours, by w.
## X SYMMETRY: KMesh.symmetry_map(0); each vertex the dab reaches also paints its mirror partner at the same weight (the
## larger weight wins when a vertex is reached both ways, so a vertex near the plane is not painted twice).

const CH := "color"
const WHITE := Color(1, 1, 1, 1)

const MIX := "mix"
const ADD := "add"
const SUB := "subtract"
const MUL := "multiply"
const LIGHTEN := "lighten"
const DARKEN := "darken"
const MODES := [MIX, ADD, SUB, MUL, LIGHTEN, DARKEN]

const DEFAULTS := {"color": Color(0.9, 0.15, 0.1, 1.0), "mode": MIX, "radius": 0.1, "strength": 1.0,
	"falloff": KMeshSculpt.F_SMOOTH, "spacing": 0.1, "blur": false, "sym_x": false}

var mesh: KMesh
var p := {}
var dabs := 0
var _sc := KMeshSculpt.new()     # its spatial hash (verts_in) and nothing else: paint never moves a vert
var _sym := PackedInt32Array()
var _vc_start := PackedInt32Array()   # CSR: corners of each vertex
var _vc_list := PackedInt32Array()
var _has_last := false
var _prev := Vector3.ZERO
var _carry := 0.0


## the "color" channel, made (corner domain, white) when the mesh has none; false when a channel of that name is not a
## Color on the vert / corner domain (it is left alone)
static func ensure(m: KMesh) -> bool:
	if not m.has_attr(CH):
		return m.add_attr(CH, KMesh.AD_CORNER, TYPE_COLOR, WHITE)
	return usable(m)


## true when the mesh has a "color" channel paint can use (Color, on the vert or corner domain)
static func usable(m: KMesh) -> bool:
	var inf := m.attr_info(CH)
	return not inf.is_empty() and inf["type"] == TYPE_COLOR and (inf["domain"] == KMesh.AD_CORNER or inf["domain"] == KMesh.AD_VERT)


static func _clamp(c: Color) -> Color:
	return Color(clampf(c.r, 0.0, 1.0), clampf(c.g, 0.0, 1.0), clampf(c.b, 0.0, 1.0), clampf(c.a, 0.0, 1.0))


## the blend of brush colour c into d at weight w (0..1)
static func blend(mode: String, d: Color, c: Color, w: float) -> Color:
	var t: Color
	match mode:
		ADD:
			t = Color(d.r + c.r, d.g + c.g, d.b + c.b, d.a)
		SUB:
			t = Color(d.r - c.r, d.g - c.g, d.b - c.b, d.a)
		MUL:
			t = Color(d.r * c.r, d.g * c.g, d.b * c.b, d.a)
		LIGHTEN:
			t = Color(maxf(d.r, c.r), maxf(d.g, c.g), maxf(d.b, c.b), d.a)
		DARKEN:
			t = Color(minf(d.r, c.r), minf(d.g, c.g), minf(d.b, c.b), d.a)
		_:
			t = c
	t = _clamp(t)
	w = clampf(w, 0.0, 1.0)
	if w >= 1.0:
		return t
	var u := 1.0 - w
	return Color(t.r * w + d.r * u, t.g * w + d.g * u, t.b * w + d.b * u, t.a * w + d.a * u)


## corners of every vertex (CSR); vert domain: the vertex itself
static func corner_map(m: KMesh) -> Array:
	var nv := m.verts.size()
	var cnt := PackedInt32Array()
	cnt.resize(nv + 1)
	for f in m.faces:
		for v in (f as PackedInt32Array):
			cnt[v + 1] += 1
	for v in nv:
		cnt[v + 1] += cnt[v]
	var lst := PackedInt32Array()
	lst.resize(cnt[nv])
	var fill := cnt.duplicate()
	var c := 0
	for f in m.faces:
		for v in (f as PackedInt32Array):
			lst[fill[v]] = c
			fill[v] += 1
			c += 1
	return [cnt, lst]


static func _is_vert(m: KMesh) -> bool:
	return m.attr_info(CH).get("domain", "") == KMesh.AD_VERT


## the colour of vertex v: the mean of its corners (vert domain: its own)
static func vert_color(m: KMesh, v: int, cm := []) -> Color:
	var d: PackedColorArray = m.attr_data(CH)
	if _is_vert(m):
		return d[v]
	if cm.is_empty():
		cm = corner_map(m)
	var s: PackedInt32Array = cm[0]
	var l: PackedInt32Array = cm[1]
	var n := s[v + 1] - s[v]
	if n == 0:
		return m.attr_info(CH)["default"]
	var acc := Color(0, 0, 0, 0)
	for k in range(s[v], s[v + 1]):
		var c: Color = d[l[k]]
		acc = Color(acc.r + c.r, acc.g + c.g, acc.b + c.b, acc.a + c.a)
	return Color(acc.r / n, acc.g / n, acc.b / n, acc.a / n)


## EYEDROPPER: the colour at a surface point of face fi (mesh-local): the colour of that face's corner nearest the point
static func sample(m: KMesh, fi: int, point: Vector3) -> Color:
	var fp: PackedInt32Array = m.faces[fi]
	var best := 0
	var bd := INF
	for i in fp.size():
		var dd := m.verts[fp[i]].distance_squared_to(point)
		if dd < bd:
			bd = dd
			best = i
	var d: PackedColorArray = m.attr_data(CH)
	return d[fp[best]] if _is_vert(m) else d[m.face_he0[fi] + best]


## FILL the selection with colour c (blend mode, weight w): face mode = the corners of the selected faces only (a hard edge
## round them); vert / edge mode = every corner of the selected verts / the edges' ends. Returns the values written.
static func fill(m: KMesh, sel: KMeshSelect, c: Color, mode := MIX, w := 1.0) -> int:
	if not ensure(m):
		return 0
	var idx := {}
	var vd := _is_vert(m)
	if sel.mode == KMeshSelect.FACE:
		for fi in sel.faces:
			var fp: PackedInt32Array = m.faces[fi]
			for i in fp.size():
				idx[fp[i] if vd else m.face_he0[fi] + i] = true
	else:
		var vs := {}
		if sel.mode == KMeshSelect.EDGE:
			for e in sel.edges:
				vs[e.x] = true
				vs[e.y] = true
		else:
			vs = sel.verts
		var cm := [] if vd else corner_map(m)
		for v in vs:
			if vd:
				idx[v] = true
			else:
				for k in range(cm[0][v], cm[0][v + 1]):
					idx[cm[1][k]] = true
	var d: PackedColorArray = m.attr_data(CH)
	m.attrs[CH]["data"] = PackedColorArray()   # one owner while writing
	for i in idx:
		d[i] = blend(mode, d[i], c, w)
	m.attrs[CH]["data"] = d
	return idx.size()


# ---------------------------------------------------------------- a stroke

func begin(m: KMesh, params := {}) -> void:
	mesh = m
	ensure(m)
	p = DEFAULTS.duplicate()
	p.merge(params, true)
	dabs = 0
	_has_last = false
	_sc.begin(m, {"radius": float(p["radius"])})
	_sym = m.symmetry_map(0, 1e-4) if p["sym_x"] else PackedInt32Array()
	var cm := corner_map(m)
	_vc_start = cm[0]
	_vc_list = cm[1]


## stroke to a new surface point (mesh-local): a dab every spacing * radius along the way (the first call lays one at the
## point). Returns the dabs laid.
## face: the face under the point (mesh-local face index) when the caller knows it, -1 when not. The first dab of a
## stroke (the press) takes it: its face's own corners get the full weight (see weights()).
func to(point: Vector3, pressure := 1.0, face := -1) -> int:
	if not _has_last:
		dab(point, pressure, face)
		_has_last = true
		_prev = point
		_carry = 0.0
		return 1
	var step := maxf(float(p["spacing"]) * float(p["radius"]), 1e-5)
	var seg := point - _prev
	var sl := seg.length()
	var laid := 0
	var s := step - _carry
	while s <= sl + 1e-6:
		dab(_prev + seg * (s / sl), pressure)
		laid += 1
		s += step
	_carry = sl - (s - step)
	_prev = point
	return laid


func end() -> void:
	_has_last = false


## the weights one dab at `hit` gives: {vert: w}, mirror partners included. FACE (>= 0): the dab is on that face, so its
## own corners get the full centre weight whatever the radius: a press on a low-poly face's centre paints the face (the
## corners of a 12-sided side are 15 cm from its centre, past a 12 cm brush's reach, and used to get nothing). On a dense
## mesh the face's corners sit within a hair of the centre, so their falloff weight is the same as the boost.
func weights(hit: Vector3, pressure := 1.0, face := -1) -> Dictionary:
	var r := float(p["radius"])
	var a := clampf(float(p["strength"]), 0.0, 1.0) * clampf(pressure, 0.0, 1.0)
	var fk := String(p["falloff"])
	var out := {}
	for v in _sc.verts_in(hit, r):
		var w := a * KMeshSculpt.falloff(fk, mesh.verts[v].distance_to(hit) / r)
		if w <= 0.0:
			continue
		_put(out, v, w)
	if face >= 0 and face < mesh.faces.size() and a > 0.0:
		for v in (mesh.faces[face] as PackedInt32Array):
			_put(out, v, a)
	return out


## out[v] = the larger of w and what v had, and the same for its mirror partner (X symmetry)
func _put(out: Dictionary, v: int, w: float) -> void:
	out[v] = maxf(w, float(out.get(v, 0.0)))
	if not _sym.is_empty():
		var u := _sym[v]
		if u >= 0:
			out[u] = maxf(w, float(out.get(u, 0.0)))


## one dab at `hit` (mesh-local); returns the verts painted
func dab(hit: Vector3, pressure := 1.0, face := -1) -> int:
	var ws := weights(hit, pressure, face)
	dabs += 1
	if ws.is_empty():
		return 0
	var vd := _is_vert(mesh)
	var d: PackedColorArray = mesh.attr_data(CH)
	var blur := bool(p["blur"])
	var means := {}
	if blur:   # every mean read before any write: the result does not depend on the order of the verts
		var cm := [_vc_start, _vc_list]
		for v in ws:
			var nb := mesh.vert_neighbors(v)
			if nb.is_empty():
				continue
			var acc := Color(0, 0, 0, 0)
			for u in nb:
				var c := vert_color(mesh, u, cm)
				acc = Color(acc.r + c.r, acc.g + c.g, acc.b + c.b, acc.a + c.a)
			var n := float(nb.size())
			means[v] = Color(acc.r / n, acc.g / n, acc.b / n, acc.a / n)
	mesh.attrs[CH]["data"] = PackedColorArray()   # one owner while writing: no copy of the whole array per corner
	var col: Color = p["color"]
	var mode := String(p["mode"])
	for v in ws:
		var w: float = ws[v]
		if blur:
			if not means.has(v):
				continue
			col = means[v]
			mode = MIX
		if vd:
			d[v] = blend(mode, d[v], col, w)
		else:
			for k in range(_vc_start[v], _vc_start[v + 1]):
				var ci := _vc_list[k]
				d[ci] = blend(mode, d[ci], col, w)
	mesh.attrs[CH]["data"] = d
	return ws.size()


# ---------------------------------------------------------------- export

## the mesh (with its colours: KMesh.to_array_mesh draws "color" as ARRAY_COLOR) as a .glb; the colours go out as the
## primitive's COLOR_0. OK or the error.
static func export_glb(m: KMesh, path: String, node_name := "kmesh") -> Error:
	var root := Node3D.new()
	root.name = node_name
	var mi := MeshInstance3D.new()
	mi.name = node_name + "_mesh"
	mi.mesh = m.to_array_mesh()
	root.add_child(mi)
	mi.owner = root
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_scene(root, st)
	if err == OK:
		var abs := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
		DirAccess.make_dir_recursive_absolute(abs.get_base_dir())
		err = doc.write_to_filesystem(st, abs)
	root.free()
	return err
