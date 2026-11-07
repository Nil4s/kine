## balance_view.gd - LIVE BALANCE (round 43, GATES YY1; Nick 10-17: "other stuff 3d human designers need that blender/maya
## dont offer"). Maya and Blender have no idea a character can fall over; Poser's Balance (de Leva masses) already
## measures it for Check. This draws it while you pose and scrub:
##   the SUPPORT POLYGON: the hull of the feet on the floor (Balance.read's poly), a line just above the floor;
##   the CENTRE OF MASS dropped to the floor: a cross there, and a plumb line from the COM itself down to it.
## Colour = how far inside the feet the COM is (Balance margin): GREEN inside by more than EDGE, AMBER within EDGE of the
## edge, RED outside (he would tip, unless something holds him), GREY when no foot is on the floor (a jump: nothing to
## balance on). Built from the main Body every frame it is on; it never touches the pose. Off = nothing drawn.
class_name BalanceView
extends Node3D

const EDGE := 0.02      # m: within this of the edge = amber (mine: a warning margin, not a measured sway)
const LIFT := 0.003     # m: drawn this far above the floor, so the floor does not hide it
const CROSS := 0.06     # m: the COM cross's half size
const GREEN := Color(0.25, 0.9, 0.4)
const AMBER := Color(1.0, 0.75, 0.15)
const RED := Color(1.0, 0.2, 0.15)
const GREY := Color(0.6, 0.6, 0.6)
const FILL_A := 0.3     # the support area's fill opacity
const DISC_R := 0.025   # m: the COM's floor disc
const DISC_N := 16
const RING_R := 0.05    # m: the ring at the point a COM drag asks for (I24)

var on := false
## what was drawn last, for the status line and tests: {"com": Vector3, "foot": Vector2 (COM on the floor), "poly":
## PackedVector2Array, "margin": float, "state": "inside" / "edge" / "outside" / "air"}
var last := {}
## I24 DRAG THE BALANCE: the point the COM is being dragged to while a drag runs ({} = none): {"xz": Vector2, "state": String}.
## A ring in the state's colour is drawn there (amber near the edge, red outside) and the solve's own marker stays where the body is
var req := {}
var split_labels := {}   # N069: "_l" / "_r" -> the Label3D of that foot's weight percent
var verts := 0   # vertices in the last drawing (tests)
var _mesh: MeshInstance3D
var _im: ImmediateMesh


func _ready() -> void:
	_im = ImmediateMesh.new()
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true   # seen through the body and the floor
	m.render_priority = 2
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh.material_override = m
	add_child(_mesh)
	# N069 WEIGHT SPLIT: a big % on the floor under each foot (left = his left, +x)
	for sd in ["_l", "_r"]:
		var lb := Label3D.new()
		lb.name = "split" + sd
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.fixed_size = true
		lb.pixel_size = 0.0022
		lb.font_size = 48
		lb.outline_size = 12
		lb.no_depth_test = true
		lb.render_priority = 3
		lb.visible = false
		add_child(lb)
		split_labels[sd] = lb


static func state_of(r: Dictionary) -> String:
	if (r["down"] as Array).is_empty():
		return "air"
	var mg: float = r["margin"]
	if mg < 0.0:
		return "outside"
	return "edge" if mg < EDGE else "inside"


static func colour(st: String) -> Color:
	return {"inside": GREEN, "edge": AMBER, "outside": RED}.get(st, GREY)


## draw for this pose (or clear, when off)
func show_body(B: Body) -> void:
	if _im == null:
		return
	_im.clear_surfaces()
	verts = 0
	for sd in split_labels:
		(split_labels[sd] as Label3D).visible = false
	if not on:
		last = {}
		return
	var r := Balance.read(B)
	var c: Vector3 = r["com"]
	var st := state_of(r)
	last = {"com": c, "foot": Vector2(c.x, c.z), "poly": r["poly"], "margin": r["margin"], "state": st}
	var col := colour(st)
	var sp := WeightSplit.read(B)   # N069: nothing at all when no foot is down
	last["split"] = sp
	if bool(sp["shown"]) and st != "air":
		for sd in split_labels:
			var lb: Label3D = split_labels[sd]
			var pt: Vector2 = sp["p" + sd.substr(1)]
			lb.text = str(sp[sd.substr(1)])
			lb.modulate = col
			lb.position = Vector3(pt.x, 0.02, pt.y - 0.12)
			lb.visible = true
	var poly: PackedVector2Array = r["poly"]
	# the support area filled, see-through (a fan from its first point: the hull is convex), and a disc at the COM's
	# floor point: 1-pixel lines alone were lost at a normal zoom (screenshot, round 43)
	var fill := Color(col, FILL_A)
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, poly.size() - 1):
		for q in [poly[0], poly[i], poly[i + 1]]:
			_im.surface_set_color(fill)
			_im.surface_add_vertex(Vector3(q.x, LIFT, q.y))
	var fc := Vector3(c.x, LIFT * 2.0, c.z)
	for i in DISC_N:
		for q in [fc, fc + Vector3(cos(TAU * i / DISC_N), 0, sin(TAU * i / DISC_N)) * DISC_R, fc + Vector3(cos(TAU * (i + 1) / DISC_N), 0, sin(TAU * (i + 1) / DISC_N)) * DISC_R]:
			_im.surface_set_color(col)
			_im.surface_add_vertex(q)
	_im.surface_end()
	_im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		_im.surface_set_color(col)
		_im.surface_add_vertex(Vector3(a.x, LIFT, a.y))
		_im.surface_set_color(col)
		_im.surface_add_vertex(Vector3(b.x, LIFT, b.y))
	var f := Vector3(c.x, LIFT, c.z)
	for d in [Vector3(CROSS, 0, 0), Vector3(0, 0, CROSS)]:
		_im.surface_set_color(col)
		_im.surface_add_vertex(f - d)
		_im.surface_set_color(col)
		_im.surface_add_vertex(f + d)
	_im.surface_set_color(col)
	_im.surface_add_vertex(c)
	_im.surface_set_color(col)
	_im.surface_add_vertex(f)
	_im.surface_end()
	if not req.is_empty():
		var rq: Vector2 = req["xz"]
		var rc := colour(String(req["state"]))
		_im.surface_begin(Mesh.PRIMITIVE_LINES)
		for i in DISC_N * 2:
			var a0 := TAU * i / (DISC_N * 2)
			var a1 := TAU * (i + 1) / (DISC_N * 2)
			for a in [a0, a1]:
				_im.surface_set_color(rc)
				_im.surface_add_vertex(Vector3(rq.x + cos(a) * RING_R, LIFT * 3.0, rq.y + sin(a) * RING_R))
		_im.surface_end()
	verts = poly.size() * 2 + 6   # the lines (the fill and disc are a surface of their own)


## N069: the texts of the visible weight labels, left then right ([] = none shown)
func split_text() -> Array:
	var out := []
	for sd in ["_l", "_r"]:
		var lb: Label3D = split_labels.get(sd)
		if lb != null and lb.visible:
			out.append(lb.text)
	return out


## the status line's words: "balance: inside by 4.1 cm" / "OUTSIDE by 2.0 cm: he tips" / "in the air"
func words() -> String:
	if last.is_empty():
		return ""
	var st: String = last["state"]
	if st == "air":
		return "balance: in the air"
	var cm := absf(float(last["margin"])) * 100.0
	if st == "outside":
		return "balance: OUTSIDE the feet by %.1f cm (he tips unless held)" % cm
	return "balance: inside by %.1f cm%s" % [cm, " (near the edge)" if st == "edge" else ""]
