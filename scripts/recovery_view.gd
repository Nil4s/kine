## recovery_view.gd - draws the RECOVERY STEP read (ROADMAP I39) on the floor: the BASE OF SUPPORT (outline, its fill red while the capture
## point is outside), the COM's floor point (cross), the CAPTURE POINT (a diamond, amber outside the base or green inside) joined to the COM by
## a line, and, when a step is planned, the landing foot's mark (a ring) and the base after the step (green outline). Colours are BalanceView's.
## Built from a report dictionary; it never touches the pose. Empty = nothing drawn.
class_name RecoveryView
extends Node3D

const LIFT := 0.004
const DIAMOND := 0.08   # m: the capture point's half size
const RING := 0.07      # m: the landing mark's radius
const N := 20

var verts := 0
var last := {}
var _mesh: MeshInstance3D
var _im: ImmediateMesh


func _ready() -> void:
	_im = ImmediateMesh.new()
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true
	m.render_priority = 3
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh.material_override = m
	add_child(_mesh)


func _line(a: Vector2, b: Vector2, col: Color, y := LIFT) -> void:
	_im.surface_set_color(col)
	_im.surface_add_vertex(Vector3(a.x, y, a.y))
	_im.surface_set_color(col)
	_im.surface_add_vertex(Vector3(b.x, y, b.y))


func _poly(poly: PackedVector2Array, col: Color) -> void:
	for i in poly.size():
		_line(poly[i], poly[(i + 1) % poly.size()], col)


## rd = Recovery.read, pl = the plan (or {})
func show_rep(rd: Dictionary, pl: Dictionary) -> void:
	if _im == null:
		return
	_im.clear_surfaces()
	verts = 0
	last = {}
	if rd.is_empty() or not bool(rd.get("ok", false)):
		return
	var poly: PackedVector2Array = rd["poly"]
	var xi: Vector2 = rd["xi"]
	var inside := float(rd["margin"]) >= 0.0
	var col := BalanceView.GREEN if inside else BalanceView.RED
	var capc := BalanceView.GREEN if inside else BalanceView.AMBER
	last = {"poly": poly, "xi": xi, "inside": inside, "com": Vector2((rd["com"] as Vector3).x, (rd["com"] as Vector3).z)}
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var fill := Color(col, BalanceView.FILL_A)
	for i in range(1, poly.size() - 1):
		for q in [poly[0], poly[i], poly[i + 1]]:
			_im.surface_set_color(fill)
			_im.surface_add_vertex(Vector3(q.x, LIFT, q.y))
	# the capture point's diamond and the landing mark are filled: lines alone are lost at a whole-body zoom
	var dcol := Color(capc, 0.9)
	var dq := [xi + Vector2(DIAMOND, 0), xi + Vector2(0, DIAMOND), xi - Vector2(DIAMOND, 0), xi - Vector2(0, DIAMOND)]
	for i in 4:
		for q in [xi, dq[i], dq[(i + 1) % 4]]:
			_im.surface_set_color(dcol)
			_im.surface_add_vertex(Vector3(q.x, LIFT * 3.0, q.y))
	if bool(pl.get("ok", false)):
		var la2: Vector2 = pl["land_at"]
		for i in N:
			for q in [la2, la2 + Vector2(cos(TAU * i / N), sin(TAU * i / N)) * RING, la2 + Vector2(cos(TAU * (i + 1) / N), sin(TAU * (i + 1) / N)) * RING]:
				_im.surface_set_color(Color(BalanceView.GREEN, 0.4))
				_im.surface_add_vertex(Vector3(q.x, LIFT * 2.0, q.y))
	_im.surface_end()
	_im.surface_begin(Mesh.PRIMITIVE_LINES)
	_poly(poly, col)
	var c2: Vector2 = last["com"]
	_line(c2 - Vector2(BalanceView.CROSS, 0), c2 + Vector2(BalanceView.CROSS, 0), BalanceView.GREY, LIFT * 2.0)
	_line(c2 - Vector2(0, BalanceView.CROSS), c2 + Vector2(0, BalanceView.CROSS), BalanceView.GREY, LIFT * 2.0)
	_line(c2, xi, capc, LIFT * 2.0)
	var dm := [xi + Vector2(DIAMOND, 0), xi + Vector2(0, DIAMOND), xi - Vector2(DIAMOND, 0), xi - Vector2(0, DIAMOND)]
	for i in 4:
		_line(dm[i], dm[(i + 1) % 4], capc, LIFT * 3.0)
		_line(xi + (dm[i] - xi) * 0.5, xi + (dm[(i + 1) % 4] - xi) * 0.5, capc, LIFT * 3.0)
	if bool(pl.get("ok", false)):
		_poly(pl["poly_after"], BalanceView.GREEN)
		var la: Vector2 = pl["land_at"]
		for i in N:
			var a0 := TAU * i / N
			var a1 := TAU * (i + 1) / N
			_line(la + Vector2(cos(a0), sin(a0)) * RING, la + Vector2(cos(a1), sin(a1)) * RING, BalanceView.GREEN, LIFT * 3.0)
	_im.surface_end()
	verts = poly.size() * 2 + 12
