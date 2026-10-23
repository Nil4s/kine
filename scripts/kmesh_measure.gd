class_name KMeshMeasure
extends Node3D
## B20 (docs/ROADMAP_400.md): the measure tool on a KMesh. Lengths are metres inside (like the rest of Kine), shown in
## cm / cm^2 / cm^3 (and litres), mass in kg once a density is set.
##   distance(a, b)          between two picked verts / points
##   angle(a, apex, c)       at the middle of three points, degrees
##   area(mesh, faces)       of selected faces (each polygon by Newell's vector: exact for planar faces, any vert count)
##   volume(mesh)            of a closed mesh by the divergence theorem (sum of signed tetrahedra from one vert over the
##                           fan triangles); an open, non-manifold or inside-out mesh is REFUSED with the reason, because
##                           the sum then depends on where the apex is and means nothing
##   mass(m^3, kg/m^3)       with MATERIALS for a few named densities (sources next to each)
## measure(mesh, sel) picks what to measure from the selection: 2 verts = distance, 3 verts = angle at the 2nd picked,
## edges = total length, faces = area, nothing (or everything) selected = the whole mesh's volume (+ mass with a density).
## As a node (a child of the KMeshView, so it shares its space) it draws the ruler: a line through the measured points on
## top of the mesh (no depth test), and draw_label() puts the readout beside the ruler's middle on a 2D overlay, kept
## inside the screen.

const CM := 100.0           # cm per m
const CM2 := 1e4            # cm^2 per m^2
const CM3 := 1e6            # cm^3 per m^3
const L_PER_M3 := 1000.0    # litres per m^3
const LABEL_GAP := 10.0     # px from the ruler's middle to the label
const LABEL_MARGIN := 4.0   # px kept clear of the screen edge
const FONT_SIZE := 14

## name -> {"kg_m3", "src"}: typical densities, one value each (real materials vary a few %)
const MATERIALS := {
	"steel": {"kg_m3": 7850.0, "src": "EN 1991-1-1 table A.4: steel 77-78.5 kN/m^3, the 7850 kg/m^3 every steel table uses"},
	"aluminium": {"kg_m3": 2700.0, "src": "EN 1991-1-1 table A.4: aluminium 27 kN/m^3 (pure Al 2.70 g/cm^3, CRC Handbook)"},
	"concrete": {"kg_m3": 2400.0, "src": "EN 1991-1-1 table A.1: normal-weight concrete 24 kN/m^3"},
	"glass": {"kg_m3": 2500.0, "src": "soda-lime glass 2.5 g/cm^3 (EN 572-1)"},
	"oak": {"kg_m3": 700.0, "src": "USDA Wood Handbook (FPL-GTR-190) table 5-3a: red / white oak air-dry ~0.65-0.75 g/cm^3"},
	"pine": {"kg_m3": 500.0, "src": "USDA Wood Handbook (FPL-GTR-190) table 5-3a: pines air-dry ~0.4-0.6 g/cm^3"},
	"water": {"kg_m3": 1000.0, "src": "pure water at 4 C, 999.97 kg/m^3"},
	"body": {"kg_m3": 1050.0, "src": "Siri 1961 two-compartment model (fat 0.90, lean 1.10 g/cm^3) at 20% body fat"},
}

var mesh: KMesh
var density := 0.0          # kg/m^3; 0 = no mass shown
var material := ""          # the MATERIALS name the density came from, "" = typed in or none
var result := {}            # the last measure(): {"kind", "value", "text", "points" (mesh space), "ok", "why"}
var _line: MeshInstance3D


func _init() -> void:
	_line = MeshInstance3D.new()
	_line.name = "ruler"
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line)


# ---------------------------------------------------------------- numbers

## All sums below run in GDScript floats (64-bit) on the components: Vector3 maths is 32-bit, which loses ~1e-7 of a
## length and, for a mesh away from the origin, several cm³ of a volume.

static func distance(a: Vector3, b: Vector3) -> float:
	var x := float(a.x) - b.x
	var y := float(a.y) - b.y
	var z := float(a.z) - b.z
	return sqrt(x * x + y * y + z * z)


## the angle at `apex` between the rays to a and c, degrees (0 when a leg has no length)
static func angle(a: Vector3, apex: Vector3, c: Vector3) -> float:
	var ux := float(a.x) - apex.x
	var uy := float(a.y) - apex.y
	var uz := float(a.z) - apex.z
	var wx := float(c.x) - apex.x
	var wy := float(c.y) - apex.y
	var wz := float(c.z) - apex.z
	if ux * ux + uy * uy + uz * uz < 1e-24 or wx * wx + wy * wy + wz * wz < 1e-24:
		return 0.0
	var cx := uy * wz - uz * wy
	var cy := uz * wx - ux * wz
	var cz := ux * wy - uy * wx
	return rad_to_deg(atan2(sqrt(cx * cx + cy * cy + cz * cz), ux * wx + uy * wy + uz * wz))


## area of one face, m^2 (half the length of Newell's vector, about the face's first vert)
static func face_area(m: KMesh, fi: int) -> float:
	var f: PackedInt32Array = m.faces[fi]
	var o: Vector3 = m.verts[f[0]]
	var nx := 0.0
	var ny := 0.0
	var nz := 0.0
	for i in f.size():
		var p: Vector3 = m.verts[f[i]]
		var q: Vector3 = m.verts[f[(i + 1) % f.size()]]
		var px := float(p.x) - o.x
		var py := float(p.y) - o.y
		var pz := float(p.z) - o.z
		var qx := float(q.x) - o.x
		var qy := float(q.y) - o.y
		var qz := float(q.z) - o.z
		nx += (py - qy) * (pz + qz)
		ny += (pz - qz) * (px + qx)
		nz += (px - qx) * (py + qy)
	return sqrt(nx * nx + ny * ny + nz * nz) * 0.5


## total area of the faces listed (all faces when `faces` is empty), m^2
static func area(m: KMesh, faces: Array = []) -> float:
	var s := 0.0
	for fi in (faces if not faces.is_empty() else range(m.face_count())):
		s += face_area(m, fi)
	return s


static func edge_length(m: KMesh, e: Vector2i) -> float:
	return (m.verts[e.x] as Vector3).distance_to(m.verts[e.y])


## {"ok": true, "m3": volume} for a closed, manifold, outward-wound mesh, else {"ok": false, "why": the reason + next step}
static func volume(m: KMesh) -> Dictionary:
	if m == null or m.face_count() == 0:
		return {"ok": false, "why": "no faces: nothing to hold a volume"}
	if not m.is_manifold():
		return {"ok": false, "why": "the mesh is not manifold (an edge or vert is shared oddly): no single inside, so no volume"}
	var holes := m.boundary_edge_count()
	if holes > 0:
		return {"ok": false, "why": "the mesh is open (boundary edges count: %d): close the holes (Validate > Repair fills small ones) to get a volume" % holes}
	var o: Vector3 = m.verts[0]   # tetrahedra from the first vert, not the origin: the same sum, smaller numbers
	var v := 0.0
	for f in m.faces:
		var ff: PackedInt32Array = f
		var a: Vector3 = m.verts[ff[0]]
		var ax := float(a.x) - o.x
		var ay := float(a.y) - o.y
		var az := float(a.z) - o.z
		for i in range(1, ff.size() - 1):
			var b: Vector3 = m.verts[ff[i]]
			var c: Vector3 = m.verts[ff[i + 1]]
			var bx := float(b.x) - o.x
			var by := float(b.y) - o.y
			var bz := float(b.z) - o.z
			var cx := float(c.x) - o.x
			var cy := float(c.y) - o.y
			var cz := float(c.z) - o.z
			v += (ax * (by * cz - bz * cy) + ay * (bz * cx - bx * cz) + az * (bx * cy - by * cx)) / 6.0
	if v < 0.0:
		return {"ok": false, "why": "the mesh is inside out (its faces wind inward, volume %.1f cm³): flip it (Validate > Repair)" % (v * CM3)}
	return {"ok": true, "m3": v}


static func mass(m3: float, kg_m3: float) -> float:
	return m3 * kg_m3


# ---------------------------------------------------------------- text

static func fmt_len(m: float) -> String:
	return "%.2f cm" % (m * CM) if m < 0.1 else "%.1f cm" % (m * CM)


static func fmt_area(m2: float) -> String:
	return "%.1f cm²" % (m2 * CM2)


static func fmt_vol(m3: float) -> String:
	return "%.0f cm³ (%.3f L)" % [m3 * CM3, m3 * L_PER_M3]


static func fmt_mass(kg: float) -> String:
	return "%.3f kg" % kg if kg < 10.0 else "%.1f kg" % kg


static func fmt_ang(deg: float) -> String:
	return "%.1f°" % deg


# ---------------------------------------------------------------- tool

## set the density by MATERIALS name ("" = none); false for an unknown name
func set_material(nm: String) -> bool:
	if nm == "":
		density = 0.0
		material = ""
		return true
	if not MATERIALS.has(nm):
		return false
	density = MATERIALS[nm]["kg_m3"]
	material = nm
	return true


## the next material in MATERIALS order after the current one, then none again; returns its name
func cycle_material() -> String:
	var names := MATERIALS.keys()
	var i := names.find(material)
	set_material("" if i == names.size() - 1 else names[i + 1])
	return material


## measure what `sel` holds (see the header) and redraw the ruler; returns `result`
func measure(m: KMesh, sel: KMeshSelect = null) -> Dictionary:
	mesh = m
	var r := {"ok": true, "kind": "", "value": 0.0, "text": "", "points": PackedVector3Array(), "why": ""}
	var md := sel.mode if sel != null else KMeshSelect.VERT
	var vs: Array = sel.verts.keys() if sel != null and md == KMeshSelect.VERT else []
	var es: Array = sel.edges.keys() if sel != null and md == KMeshSelect.EDGE else []
	var fs: Array = sel.faces.keys() if sel != null and md == KMeshSelect.FACE else []
	var whole := vs.is_empty() and es.is_empty() and fs.is_empty()
	whole = whole or vs.size() == m.vert_count() or fs.size() == m.face_count()   # A (select all) = the whole mesh too
	if whole:
		var v := volume(m)
		r["kind"] = "volume"
		if not v["ok"]:
			r["ok"] = false
			r["why"] = v["why"]
			r["text"] = "no volume: " + v["why"]
		else:
			r["value"] = v["m3"]
			r["text"] = fmt_vol(v["m3"])
			if density > 0.0:
				r["kg"] = mass(v["m3"], density)
				r["text"] += ", %s as %s" % [fmt_mass(r["kg"]), material if material != "" else "%.0f kg/m³" % density]
		var bb := AABB(m.verts[0], Vector3.ZERO) if m.vert_count() > 0 else AABB()
		for p in m.verts:
			bb = bb.expand(p)
		r["points"] = PackedVector3Array([bb.get_center()])
	elif vs.size() == 2:
		var a: Vector3 = m.verts[vs[0]]
		var b: Vector3 = m.verts[vs[1]]
		r["kind"] = "distance"
		r["value"] = distance(a, b)
		r["text"] = fmt_len(r["value"])
		r["points"] = PackedVector3Array([a, b])
	elif vs.size() == 3:
		var a: Vector3 = m.verts[vs[0]]
		var o: Vector3 = m.verts[vs[1]]
		var c: Vector3 = m.verts[vs[2]]
		r["kind"] = "angle"
		r["value"] = angle(a, o, c)
		r["text"] = "%s at the 2nd vert" % fmt_ang(r["value"])
		r["points"] = PackedVector3Array([a, o, c])
	elif not es.is_empty():
		var s := 0.0
		var pts := PackedVector3Array()
		for e in es:
			s += edge_length(m, e)
			pts.append(m.verts[e.x])
			pts.append(m.verts[e.y])
		r["kind"] = "length"
		r["value"] = s
		r["text"] = fmt_len(s) if es.size() == 1 else "%s (picked %d edges)" % [fmt_len(s), es.size()]
		r["points"] = pts if es.size() == 1 else PackedVector3Array()
	elif not fs.is_empty():
		r["kind"] = "area"
		r["value"] = area(m, fs)
		r["text"] = "%s (picked %d faces)" % [fmt_area(r["value"]), fs.size()]
		var c := Vector3.ZERO
		for fi in fs:
			c += m.face_center(fi)
		r["points"] = PackedVector3Array([c / fs.size()])
	else:
		r["ok"] = false
		r["why"] = "pick two verts (distance), three (angle), edges (length), faces (area), or nothing (volume)"
		r["text"] = r["why"]
	result = r
	_draw_ruler()
	return r


func clear() -> void:
	result = {}
	_line.mesh = null


func _draw_ruler() -> void:
	var pts: PackedVector3Array = result.get("points", PackedVector3Array())
	if pts.size() < 2:
		_line.mesh = null
		return
	var seg := PackedVector3Array()
	if result["kind"] == "length" or result["kind"] == "distance":
		seg = pts
	else:   # the angle: both legs from the apex
		seg = PackedVector3Array([pts[0], pts[1], pts[1], pts[2]])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = seg
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	var mt := StandardMaterial3D.new()
	mt.albedo_color = Tok.c("focus")
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.no_depth_test = true
	mt.render_priority = 10
	_line.mesh = am
	_line.material_override = mt


## the world point the label hangs off: the ruler's middle (the apex for an angle, the centre for an area / volume)
func anchor_world() -> Vector3:
	var pts: PackedVector3Array = result.get("points", PackedVector3Array())
	if pts.is_empty():
		return global_position
	var p: Vector3 = pts[1] if result.get("kind") == "angle" else (pts[0] + pts[pts.size() - 1]) * 0.5 if result.get("kind") in ["distance", "length"] else pts[0]
	return global_transform * p


## where the readout goes on a screen of `screen` px: LABEL_GAP above-right of the anchor, pushed back inside the edges.
## An anchor behind the camera puts it in the top-left corner. Returns the label's Rect2.
static func label_rect(cam: Camera3D, anchor_w: Vector3, size: Vector2, screen: Rect2) -> Rect2:
	var at := screen.position + Vector2(LABEL_MARGIN, LABEL_MARGIN)
	if not cam.is_position_behind(anchor_w):
		at = cam.unproject_position(anchor_w) + Vector2(LABEL_GAP, -LABEL_GAP - size.y)
	var lo := screen.position + Vector2(LABEL_MARGIN, LABEL_MARGIN)
	var hi := screen.end - size - Vector2(LABEL_MARGIN, LABEL_MARGIN)
	return Rect2(at.clamp(lo, hi.max(lo)), size)


## draw the readout on a 2D overlay (a full-screen Control): a backed box with the text. Returns its Rect2 (empty when
## there is nothing to show).
func draw_label(ci: CanvasItem, cam: Camera3D) -> Rect2:
	if result.is_empty() or result.get("text", "") == "":
		return Rect2()
	var font := ThemeDB.fallback_font
	var txt: String = result["text"]
	var sz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE) + Vector2(12, 8)
	var r := label_rect(cam, anchor_world(), sz, ci.get_viewport_rect())
	ci.draw_rect(r, Tok.c("say_bg"), true)
	ci.draw_rect(r, Tok.c("focus"), false, 1.0)
	ci.draw_string(font, r.position + Vector2(6, 4 + font.get_ascent(FONT_SIZE)), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Tok.c("fail") if not result.get("ok", true) else Tok.c("text"))
	return r
