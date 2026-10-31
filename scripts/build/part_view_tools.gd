class_name PartViewTools
extends Node
## S102 + S104 (Friday plan): two small VIEW toggles in a part's view tools, beside the ViewCube's Studio lights and Shading buttons.
##   X-ray (102): the part is drawn see-through (every body's alpha drops to X_ALPHA) and its hidden edges are drawn on top, so a hole inside shows.
##   Turntable (104): the CAMERA turns slowly round the part (one turn in TURN_SECONDS); the part's record is never touched.
## Both are VIEW settings: off at the start, never saved, never in the record, never an undo step. X-ray off puts back the exact looks (PartUI._look_surfaces
## rebuilds them from the replay's looks). The buttons show only while the Part workspace is on.
const X_ALPHA := 0.3
const TURN_SECONDS := 10.0
const FEATURE_DOT := 0.906   # cos 25 deg: two faces meeting at more than 25 deg make a drawn edge

var m: Node
var xray_btn: Button
var turn_btn: Button
var xray := false
var turntable := false
var turn_period := TURN_SECONDS
var edges_mi: MeshInstance3D
var _edge_mesh_id := 0
var _last_ms := 0


## called from main._place_cube: makes the tools once, then puts the two buttons under the cube, left of the two menus
static func place(main: Node) -> void:
	if main == null or main.ui_cube == null:
		return
	var t := main.get_node_or_null("part_view_tools") as PartViewTools
	if t == null:
		t = PartViewTools.new()
		t.name = "part_view_tools"
		t.m = main
		main.add_child(t)
		t._build()
	t._layout()


func _build() -> void:
	for spec in [["xray", "X-ray", "shade_xray", "see through the part: hidden edges and holes inside show (a view only, off at the start)"],
			["turntable", "Turntable", "turn_r", "the view turns slowly round the part for showing (one turn in 10 seconds; a view only, off at the start)"]]:
		var b := Button.new()
		b.name = "view_" + String(spec[0])
		b.text = spec[1]
		b.tooltip_text = spec[1] + ": " + spec[3]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.anchor_left = 1.0
		b.anchor_right = 1.0
		m._icon_only(b, spec[2], Vector2(m.NAV_W, m.NAV_H))
		b.visible = false
		m.ui_root.add_child(b)
		if spec[0] == "xray":
			xray_btn = b
			b.toggled.connect(set_xray)
		else:
			turn_btn = b
			b.toggled.connect(set_turntable)


func _layout() -> void:
	var r: float = m.rw() + 10.0 + 2.0 * (m.NAV_W + 4)
	var y: float = m.ui_cube.offset_bottom + 6.0
	for b in [xray_btn, turn_btn]:
		b.offset_right = -r
		b.offset_left = -r - m.NAV_W
		b.offset_top = y
		b.offset_bottom = y + m.NAV_H
		r += m.NAV_W + 4


func _pu() -> Node:
	return m.bld.part if m.bld != null else null


func _part_showing() -> bool:
	var pu = _pu()
	return pu != null and pu.on


func _process(_dt: float) -> void:
	var now := Time.get_ticks_msec()
	var dt := float(now - _last_ms) / 1000.0 if _last_ms > 0 else 0.0
	_last_ms = now
	var show := _part_showing()
	for b in [xray_btn, turn_btn]:
		if b != null and b.visible != show:
			b.visible = show
	if turntable and show:
		m.yaw = fposmod(m.yaw + dt * 360.0 / maxf(turn_period, 0.1), 360.0)
		m._cam()
	if xray:
		_sync_edges()


## the part draws see-through (or back to its looks); one call for the button and for tests
func set_xray(on: bool) -> void:
	xray = on
	if xray_btn != null:
		xray_btn.set_pressed_no_signal(on)
	var pu = _pu()
	if pu == null:
		return
	pu.xray = on
	pu._look_surfaces()
	if on:
		_sync_edges()
	elif edges_mi != null:
		edges_mi.visible = false
		edges_mi.mesh = null
		_edge_mesh_id = 0


func set_turntable(on: bool) -> void:
	turntable = on
	_last_ms = Time.get_ticks_msec()
	if turn_btn != null:
		turn_btn.set_pressed_no_signal(on)


## the hidden edges: every edge of the shown mesh where two faces meet at a sharp angle (or only one face stands), drawn with no depth test
func _sync_edges() -> void:
	var pu = _pu()
	if pu == null or pu.part_mesh == null or pu.part_mesh.mesh == null:
		if edges_mi != null:
			edges_mi.visible = false
		return
	var mesh: ArrayMesh = pu.part_mesh.mesh
	if edges_mi == null:
		edges_mi = MeshInstance3D.new()
		edges_mi.name = "xray_edges"
		var mt := StandardMaterial3D.new()
		mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mt.albedo_color = Color(0.05, 0.1, 0.2, 1.0)
		mt.no_depth_test = true
		mt.render_priority = 20
		mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		edges_mi.material_override = mt
		edges_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pu.part_mesh.add_child(edges_mi)
	if mesh.get_instance_id() == _edge_mesh_id and edges_mi.mesh != null:
		edges_mi.visible = true
		return
	_edge_mesh_id = mesh.get_instance_id()
	var lines := feature_edges(mesh)
	if lines.is_empty():
		edges_mi.mesh = null
		return
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = lines
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	edges_mi.mesh = am
	edges_mi.visible = true


## the sharp edges of a triangle mesh as line-segment end points (pairs). Positions are welded to 0.01 mm so a flat-shaded mesh still pairs up its faces
static func feature_edges(mesh: Mesh) -> PackedVector3Array:
	var out := PackedVector3Array()
	var seen := {}   # edge key -> [a, b, first normal, count, sharp]
	for s in mesh.get_surface_count():
		var arrs: Array = mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
		var ix: Variant = arrs[Mesh.ARRAY_INDEX]
		var idx: PackedInt32Array = ix if ix != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(vs.size())
			for i in vs.size():
				idx[i] = i
		var tris := idx.size() / 3
		if tris > 120000:
			continue
		for t in tris:
			var a := vs[idx[t * 3]]
			var b := vs[idx[t * 3 + 1]]
			var c := vs[idx[t * 3 + 2]]
			var n := (b - a).cross(c - a)
			if n.length_squared() < 1e-24:
				continue
			n = n.normalized()
			var ka := _key(a)
			var kb := _key(b)
			var kc := _key(c)
			for e in [[a, b, ka, kb], [b, c, kb, kc], [c, a, kc, ka]]:
				var k1: Vector3i = e[2]
				var k2: Vector3i = e[3]
				if k1 == k2:
					continue
				var key: Array = [k1, k2] if _lt(k1, k2) else [k2, k1]
				var rec: Variant = seen.get(key)
				if rec == null:
					seen[key] = [e[0], e[1], n, 1, false]
				else:
					rec[3] += 1
					if (rec[2] as Vector3).dot(n) < FEATURE_DOT:
						rec[4] = true
	for key in seen:
		var r: Array = seen[key]
		if int(r[3]) == 1 or bool(r[4]):
			out.append(r[0])
			out.append(r[1])
	return out


static func _key(v: Vector3) -> Vector3i:
	return Vector3i(roundi(v.x * 100000.0), roundi(v.y * 100000.0), roundi(v.z * 100000.0))


static func _lt(a: Vector3i, b: Vector3i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	if a.y != b.y:
		return a.y < b.y
	return a.z < b.z
