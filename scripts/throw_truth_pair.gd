## throw_truth_pair.gd - the N040 pair render: both bodies at one frame, drawn from the real posed skeletons (Body.P through the actor placement).
##   left: SIDE view (the thrower's forward z across, height up): thrower blue, partner orange, centres of mass as rings, contact points dots
##   (white = a grip by hand or forearm, yellow = another body part)
##   right: PLAN view from above: each body's support polygon, centre of mass (ring) and extrapolated centre of mass (cross); a red line from
##   the partner's nearest foot edge to where his extrapolated COM lies when it is outside; the thrower's COM dot is green (holds) or red.
class_name ThrowTruthPair
extends Control

const COL_T := Color("4363d8")
const COL_P := Color("f58231")
const COL_BG := Color("1e1e24")
const COL_TXT := Color("f5f5f5")
const SIDE := Rect2(10, 40, 470, 470)
const PLAN := Rect2(500, 40, 390, 470)
const S_SIDE := 170.0   # px per m
const S_PLAN := 230.0

var S: Scene
var res: Dictionary
var frame := 0
var _b: Array = []
var _x: Array = []
var _bal: Array = []


static func _finger(j: String) -> bool:
	for p in ["thumb", "index", "middle", "ring", "pinky"]:
		if j.begins_with(p):
			return true
	return false


func show_case(scene: Scene, r: Dictionary, f: int) -> void:
	S = scene
	res = r
	frame = f
	_b = [ThrowTruth.new_body(), ThrowTruth.new_body()]
	_x = [Transform3D.IDENTITY, Constraints.actor_xf(S.actors[0]["xf"])]
	var t := float(f) / float(r["fps"])
	var scs: Array = [S, S.actors[0]["scene"]]
	for k in 2:
		(scs[k] as Scene).apply(_b[k], t)
		(_b[k] as Body).fk()
	var v := Vector3.ZERO
	var pi := 1 - int(r["thrower"])
	if f > 0:
		var bp := ThrowTruth.new_body()
		(scs[pi] as Scene).apply(bp, float(f - 1) / float(r["fps"]))
		bp.fk()
		v = (Balance.com(_b[pi]) - Balance.com(bp)) * float(r["fps"])
	_bal = []
	for k in 2:
		_bal.append(ThrowTruth.balance_of(_b[k], v if k == pi else Vector3.ZERO))
	queue_redraw()


func side_pt(w: Vector3) -> Vector2:
	return Vector2(SIDE.position.x + 70.0 + (w.z + 0.4) * S_SIDE, SIDE.end.y - 20.0 - w.y * S_SIDE)


func plan_pt(x: float, z: float) -> Vector2:
	return Vector2(PLAN.get_center().x - x * S_PLAN, PLAN.end.y - 30.0 - (z + 0.4) * S_PLAN)   # +x is his left: drawn left of the viewer looking along +z


## where body k's centre of mass is drawn in the plan (tests read the PNG here)
func plan_com_pixel(k: int) -> Vector2i:
	var c: Vector3 = (_x[k] as Transform3D) * (_bal[k]["com"] as Vector3)
	return Vector2i(plan_pt(c.x, c.z))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	if _b.is_empty():
		return
	var font := ThemeDB.fallback_font
	var ti := int(res["thrower"])
	var fr: Dictionary = res["frames"][frame]
	draw_string(font, Vector2(12, 24), "%s   f %d (%.2f s)   thrower = blue, partner = orange" % [String(fr["verdict"]).to_upper(), frame, float(fr["t"])], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ThrowTruthStrip.color_of(String(fr["verdict"])))
	draw_line(Vector2(SIDE.position.x, SIDE.end.y - 20.0), Vector2(SIDE.end.x, SIDE.end.y - 20.0), Color("55555f"), 2.0)
	for k in 2:
		var col := COL_T if k == ti else COL_P
		var B: Body = _b[k]
		for j in Body.ORDER:
			var pj := String(B.parent.get(j, ""))
			if pj == "" or _finger(String(j)):
				continue
			draw_line(side_pt((_x[k] as Transform3D) * (B.P[pj] as Vector3)), side_pt((_x[k] as Transform3D) * (B.P[j] as Vector3)), col, 3.0)
		var hd: Vector3 = (_x[k] as Transform3D) * (B.P["head"] as Vector3)
		draw_circle(side_pt(hd + Vector3(0, 0.1, 0)), 0.1 * S_SIDE, col)
		var c: Vector3 = (_x[k] as Transform3D) * (_bal[k]["com"] as Vector3)
		draw_arc(side_pt(c), 8.0, 0.0, TAU, 20, COL_TXT, 2.0)
	for c in fr["points"]:
		draw_circle(side_pt(c["at"]), 5.0, COL_TXT if c["grip"] else Color("ffe119"))
	draw_rect(PLAN, Color("2a2a32"))
	for k in 2:
		var col := COL_T if k == ti else COL_P
		var poly: PackedVector2Array = _bal[k]["poly"]
		var pts := PackedVector2Array()
		for p in poly:
			var w: Vector3 = (_x[k] as Transform3D) * Vector3(p.x, 0.0, p.y)
			pts.append(plan_pt(w.x, w.z))
		if pts.size() >= 3:
			draw_colored_polygon(pts, Color(col, 0.35))
			pts.append(pts[0])
			draw_polyline(pts, col, 2.0)
		var c: Vector3 = (_x[k] as Transform3D) * (_bal[k]["com"] as Vector3)
		var xi: Vector2 = _bal[k]["xi"]
		var xw: Vector3 = (_x[k] as Transform3D) * Vector3(xi.x, 0.0, xi.y)
		draw_arc(plan_pt(c.x, c.z), 7.0, 0.0, TAU, 20, COL_TXT, 2.0)
		draw_line(plan_pt(xw.x, xw.z) + Vector2(-6, 0), plan_pt(xw.x, xw.z) + Vector2(6, 0), COL_TXT, 2.0)
		draw_line(plan_pt(xw.x, xw.z) + Vector2(0, -6), plan_pt(xw.x, xw.z) + Vector2(0, 6), COL_TXT, 2.0)
		if k != ti and float(_bal[k]["out"]) > 0.0 and not bool(_bal[k]["airborne"]):
			var d: Vector2 = _bal[k]["dir"]
			var cp := xi - d * float(_bal[k]["out"])
			var a3: Vector3 = (_x[k] as Transform3D) * Vector3(cp.x, 0.0, cp.y)
			draw_line(plan_pt(a3.x, a3.z), plan_pt(xw.x, xw.z), ThrowTruthStrip.COL_FALLS, 4.0)
		if k == ti:
			var ok := float(_bal[k]["margin_com"]) >= -Balance.MARGIN_RES
			draw_circle(plan_pt(c.x, c.z), 4.0, ThrowTruthStrip.COL_WORKS if ok else ThrowTruthStrip.COL_FALLS)
	draw_multiline_string(font, Vector2(12, 530), String(res.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, 870.0, 12, 3, COL_TXT)
