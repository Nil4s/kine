class_name JudgeRender
extends Node3D
## JUDGE RENDER (ROADMAP_400 K23; the command "Deliver: breakdown video (with the judges drawn)"; the render loop is main.gd's
## _export_judge_render). The scene is rendered with the JUDGES DRAWN into the video, the way a coach marks up a tape:
##   SIDE BY SIDE: left = the clean picture, right = the same frame with the chosen overlays on; or SINGLE: the overlays on one view.
##   OVERLAYS (any subset): "balance"  the centre of mass over its support polygon (BalanceView: green / amber / red)
##                          "force"    the ground reaction as an arrow from the centre of pressure, 0.4 m per body weight (ForceView data)
##                          "boxes"    the hit (red / gold) and hurt (blue-grey) boxes of the frame data (Frame boxes)
##                          "limits"   a red marker on every joint in the last 10% of its range (Body.limit_fade)
##   CAPTION STRIP under the picture, every frame: the time, the card in play, and the CHECK verdicts that fire on THAT frame:
##                          "off balance (COM 4.0 cm outside the feet)"  (Balance.read, this frame's pose)
##                          "foot slides 3.0 cm", "flight off its arc", "body passes through itself", "tipping"  (Feasible.check, over the
##                          frames of the finding), "at its limit: elbow l"  (Body.limit_fade > 0.5)
## This file holds the drawing of the two overlays that have no view of their own (force arrow, limit markers) and the pure helpers;
## main.gd poses, toggles the existing views, captures and composes. Colours: Tok tokens (judge_force, judge_limit).

const ROOT := "user://breakdowns"
const STRIP_H := 44            # px: the caption strip's height
const ALL := ["balance", "force", "boxes", "limits"]
const BW_LEN := 0.4            # m of arrow per body weight of ground reaction
const MIN_BW := 0.05           # no arrow under this many body weights
const LIMIT_SHOW := 0.5        # a joint is "at its limit" in the caption from this share into its last 10%
const MARK_R := 0.045          # m: the limit marker's radius
const SHAFT_W := 0.014         # m: the arrow shaft's half width

var _mesh: MeshInstance3D
var _im: ImmediateMesh
## what was drawn last, for tests: {"arrow": bool, "limits": [joints]}
var last := {}


func _ready() -> void:
	_im = ImmediateMesh.new()
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true   # seen through the body, like the balance view
	m.render_priority = 3
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = m
	add_child(_mesh)


func clear() -> void:
	if _im != null:
		_im.clear_surfaces()
	last = {}


## draw this pose's force arrow ({} = none) and limit markers (joints = [] = none)
func show_frame(arrow: Dictionary, joints: Array, B: Body, cam_pos: Vector3, com := {}) -> void:
	clear()
	if _im == null:
		return
	var tris := []
	var fc := Tok.c("judge_force").srgb_to_linear()   # vertex colours are linear: the picture shows the token's own colour
	if not arrow.is_empty():
		_arrow(tris, arrow["from"], arrow["to"], cam_pos)
	var lc := Tok.c("judge_limit").srgb_to_linear()
	if not com.is_empty():   # the COM itself, a ball in the balance state's colour (the balance view's own line and disc are thin)
		_octa(tris, com["p"], MARK_R * 0.8, 2)
	for j in joints:
		_octa(tris, B.P[j], MARK_R)
	if tris.is_empty():
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in tris:
		_im.surface_set_color(fc if t[1] == 0 else (lc if t[1] == 1 else (com["col"] as Color)))
		_im.surface_add_vertex(t[0])
	_im.surface_end()
	last = {"arrow": not arrow.is_empty(), "limits": joints.duplicate(), "com": not com.is_empty()}


## tris: [[Vector3, kind]] with kind 0 = force, 1 = limit, 2 = the COM ball
static func _tri(tris: Array, a: Vector3, b: Vector3, c: Vector3, kind: int) -> void:
	tris.append([a, kind])
	tris.append([b, kind])
	tris.append([c, kind])


static func _octa(tris: Array, c: Vector3, r: float, kind := 1) -> void:
	var v := [c + Vector3(r, 0, 0), c - Vector3(r, 0, 0), c + Vector3(0, r, 0), c - Vector3(0, r, 0), c + Vector3(0, 0, r), c - Vector3(0, 0, r)]
	for sx in [0, 1]:
		for sy in [2, 3]:
			for sz in [4, 5]:
				_tri(tris, v[sx], v[sy], v[sz], kind)


## a flat ribbon shaft facing the camera (width 2 SHAFT_W) and a cone-ish head (a flat triangle pair), from a to b
static func _arrow(tris: Array, a: Vector3, b: Vector3, cam_pos: Vector3) -> void:
	var d := b - a
	var ln := d.length()
	if ln < 1e-4:
		return
	var u := d / ln
	var view := (cam_pos - (a + b) * 0.5)
	var side := u.cross(view)
	if side.length() < 1e-6:
		side = u.cross(Vector3.RIGHT)
	side = side.normalized()
	var head := minf(0.12, ln * 0.4)
	var neck := b - u * head
	var w := side * SHAFT_W
	_tri(tris, a - w, a + w, neck + w, 0)
	_tri(tris, a - w, neck + w, neck - w, 0)
	var hw := side * (SHAFT_W * 3.0)
	_tri(tris, neck - hw, neck + hw, b, 0)


# ---------------------------------------------------------------- pure helpers (tests call these)

static func frame_count(seconds: float, fps: int) -> int:
	return maxi(1, roundi(seconds * float(fps)))


static func time_of(k: int, fps: int) -> float:
	return float(k) / float(fps)


## the ground reaction arrow at time t from ForceView's sample, {} when none ("from": the centre of pressure on the floor, "to": the tip)
static func arrow_at(sm: Dictionary, t: float) -> Dictionary:
	if sm.is_empty() or not sm.has("grf") or (sm["grf"] as Array).is_empty():
		return {}
	var n: int = (sm["grf"] as Array).size()
	var i := clampi(roundi(t * float(sm["hz"])), 0, n - 1)
	var f: Vector3 = sm["grf"][i]
	var bw: float = sm["bw"]
	if bw <= 0.0 or f.length() < MIN_BW * bw:
		return {}
	var cop: Vector3 = sm["cop"][i]
	var from := Vector3(cop.x, 0.004, cop.z)
	return {"from": from, "to": from + f / bw * BW_LEN}


## the joints within the last 10% of their range at this pose (strength > 0): the red markers
static func limit_joints(B: Body, min_fade := 0.0) -> Array:
	var out := []
	for j in Body.ORDER:
		if B.P.has(j) and B.limit_fade(j) > min_fade:
			out.append(j)
	return out


## the smallest distance from `centre` at which every point (of any frame) projects inside a frame of this aspect with the margin, camera at
## this yaw / pitch (degrees); fov: the viewport's vertical field of view; fy: the share of the viewport's height the frame covers
static func fit_dist(pts: Array, centre: Vector3, yaw_deg: float, pitch_deg: float, fov_deg: float, aspect: float, fy := 1.0, margin := Turntable.MARGIN) -> float:
	var ty := tan(deg_to_rad(fov_deg * 0.5)) * fy
	var tx := ty * aspect
	var inv := Basis.from_euler(Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0)).inverse()
	var best := 0.5
	for p in pts:
		var q: Vector3 = inv * ((p[0] as Vector3) - centre)
		var r: float = p[1]
		best = maxf(best, q.z + (absf(q.y) + r) * margin / ty)
		best = maxf(best, q.z + (absf(q.x) + r) * margin / tx)
	return best


## the verdicts that fire at time t: Balance.read of B (already posed at t), the Feasible findings over their frames, the joints at a limit
static func verdicts_at(B: Body, findings: Array, t: float) -> Array:
	var out := []
	var r := Balance.read(B)
	if not (r["down"] as Array).is_empty() and float(r["margin"]) < 0.0:
		out.append("off balance (COM %.1f cm outside the feet)" % (-float(r["margin"]) * 100.0))
	for f in findings:
		var rule := String(f["rule"])
		if rule == "FEASIBLE BALANCE":
			continue   # the live reading above says it on every frame it is true
		if t < float(f["t"]) - 1e-6 or t > float(f.get("t1", f["t"])) + 1e-6:
			continue
		var s := ""
		match rule:
			"FEASIBLE SLIDE": s = "foot slides %.1f cm" % (float(f["v"]) * 100.0)
			"FEASIBLE FLIGHT": s = "flight off its arc"
			"FEASIBLE PENETRATION": s = "body passes through itself"
			_: s = rule.trim_prefix("FEASIBLE ").to_lower()
		if not out.has(s):
			out.append(s)
	var lim := []
	for j in limit_joints(B, LIMIT_SHOW):
		lim.append(String(j).replace("_", " "))
	if not lim.is_empty():
		out.append("at its limit: " + ", ".join(lim.slice(0, 2)) + (" +%d" % (lim.size() - 2) if lim.size() > 2 else ""))
	return out


## the card in play at t: the last card whose move starts at or before t
static func card_at(S: Scene, t: float) -> int:
	var ts: Array = S.times()
	var k := 0
	for i in ts.size():
		if float(ts[i][0]) <= t + 1e-6:
			k = i
	return k


static func caption(S: Scene, t: float, fps: int, verdicts: Array) -> String:
	var k := card_at(S, t)
	var nm := String(S.cards[k].get("name", "")) if k < S.cards.size() else ""
	var card := "card %d%s" % [k + 1, (" " + nm) if nm != "" else ""]
	return "%s   %s   |   %s" % [Units.time(t, float(fps)), card, "; ".join(verdicts) if not verdicts.is_empty() else "no verdict fires"]
