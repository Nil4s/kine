## line_of_action.gd - ROADMAP 23: sketch a line of action -> pose (top-25 #9). Sources: docs/research/LINE_OF_ACTION.md
##   DRAW: "Pose: draw a line of action" arms the view; the next left drag is one stroke, in screen space. Released =
##     one undo step. The stroke is cast onto the plane through the pelvis that faces the camera (a vertical plane
##     parallel to the screen; for a hero facing the camera that is his frontal plane), smoothed (Chaikin), resampled
##     to N_CURVE points by arc length, and moved so it passes through the pelvis (the chain's fixed anchor).
##   FIT: Gauss-Newton with the closest point on the curve re-found each step (ICP-style). Free angles: the pelvis tilt
##     (bend, side), spine_01..03 (bend, side), neck_01 and head (bend, side), the support thigh (bend, side) and knee
##     (bend). The joint points spine_01, spine_02, spine_03, neck_01, the head's centre and the support knee are pulled
##     onto the curve. The planted ankle is held by a heavy pull. Every step is clamped to Body.lim (the joint limits).
##     Arms, twist and every other joint are not touched (their points ride along with the spine).
##   SHIFT on release: mirror the stroke about the pelvis, so the lean goes the other way.
##   OVERLAY (on): the CURRENT line of action, drawn faint: head centre -> neck -> spine -> pelvis -> support knee -> ankle.
class_name LineOfAction
extends Node3D

const N_CURVE := 48          # points on the fitted curve
const MIN_LEN := 0.10        # m: a shorter stroke is a click, not a line
const FOOT_W := 1.0          # the planted ankle's pull back to where it stood (per m of drift)
const KNEE_W := 0.3          # the support knee's pull onto the curve: light, the planted ankle and the hip fix it
const REG := 1e-7            # m^2 per deg^2: a soft pull to the pose it started from
const ITERS := 60
const EPS := 0.05            # deg: the finite-difference step
const LIMIT_NEAR := 0.5      # deg: "at a limit" when an angle is within this of its bound
const COL := Color(1.0, 0.85, 0.2, 0.55)   # the overlay line (faint yellow)

var on := false              # overlay toggle: the current line of action
var armed := false           # the next left drag is a stroke
var stroke: Array = []       # the screen points of the drag in progress (Vector2)
var last_curve: Array = []   # the world curve of the last stroke applied (tests read it)
var last: Dictionary = {}    # the last apply's report
var _mesh: MeshInstance3D


func setup() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.mesh = ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true
	m.render_priority = 2
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh.material_override = m
	add_child(_mesh)


# ---- the overlay -------------------------------------------------------------------------------------------------

## the support leg: the foot lower in the world (y), "_l" or "_r"
static func support(B: Body) -> String:
	var fl: Vector3 = B.P["foot_l"]
	var fr: Vector3 = B.P["foot_r"]
	return "_l" if fl.y <= fr.y else "_r"


## the head's centre: the middle of the head bone (its base to its top)
static func head_c(B: Body) -> Vector3:
	var a: Vector3 = B.P["head"]
	var b: Vector3 = B.E["head"]
	return (a + b) * 0.5


## the points of the CURRENT line of action, head first: head centre, neck, spine, pelvis, support knee, ankle
static func current_line(B: Body) -> Array:
	var s := support(B)
	return [head_c(B), B.P["neck_01"], B.P["spine_03"], B.P["spine_02"], B.P["spine_01"], B.P["pelvis"],
		B.P["calf" + s], B.P["foot" + s]]


func draw(B: Body) -> void:
	if _mesh == null:
		return
	_mesh.visible = on
	var im := _mesh.mesh as ImmediateMesh
	im.clear_surfaces()
	if not on:
		return
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p: Vector3 in current_line(B):
		im.surface_set_color(COL)
		im.surface_add_vertex(p)
	im.surface_end()


# ---- the stroke ----------------------------------------------------------------------------------------------------

## cast each screen point onto the plane through pel that faces the camera
static func to_world(cam: Camera3D, pts2: Array, pel: Vector3) -> Array:
	var n := -cam.global_basis.z
	var out := []
	for s: Vector2 in pts2:
		var o := cam.project_ray_origin(s)
		var d := cam.project_ray_normal(s)
		var den := d.dot(n)
		out.append(o + d * ((pel - o).dot(n) / den))
	return out


## Chaikin corner cutting, iters times: the stroke's corners rounded into a smooth curve
static func smooth(pts: Array, iters := 3) -> Array:
	var p := pts
	for _k in iters:
		var q := [p[0]]
		for i in range(p.size() - 1):
			var a: Vector3 = p[i]
			var b: Vector3 = p[i + 1]
			q.append(a.lerp(b, 0.25))
			q.append(a.lerp(b, 0.75))
		q.append(p[p.size() - 1])
		p = q
	return p


static func length_of(pts: Array) -> float:
	var t := 0.0
	for i in range(1, pts.size()):
		t += (pts[i] as Vector3).distance_to(pts[i - 1])
	return t


## n points evenly spaced by arc length along the polyline
static func resample(pts: Array, n: int) -> Array:
	var L := [0.0]
	for i in range(1, pts.size()):
		L.append(L[i - 1] + (pts[i] as Vector3).distance_to(pts[i - 1]))
	var total: float = L[L.size() - 1]
	var out := []
	var j := 0
	for k in n:
		var s := total * float(k) / float(n - 1)
		while j < L.size() - 2 and L[j + 1] < s:
			j += 1
		var seg: float = L[j + 1] - L[j]
		var t: float = 0.0 if seg < 1e-12 else (s - L[j]) / seg
		out.append((pts[j] as Vector3).lerp(pts[j + 1], clampf(t, 0.0, 1.0)))
	return out


## the point on the polyline nearest p
static func closest(curve: Array, p: Vector3) -> Vector3:
	var best := INF
	var bq := Vector3.ZERO
	for i in range(curve.size() - 1):
		var a: Vector3 = curve[i]
		var ab: Vector3 = (curve[i + 1] as Vector3) - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 < 1e-12 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		var q := a + ab * t
		var d := p.distance_squared_to(q)
		if d < best:
			best = d
			bq = q
	return bq


# ---- the fit -------------------------------------------------------------------------------------------------------

## the free angles: [joint, axis index (0 bend, 1 side)], for the pelvis chain and the support leg
static func _vars(B: Body, s: String) -> Array:
	var v := []
	for j in ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head", "thigh" + s]:
		for k in 2:
			var r: Vector2 = B.lim[j][["bend", "side"][k]]
			if r.y - r.x > 0.5:   # a locked axis is not free
				v.append([j, k])
	var rc: Vector2 = B.lim["calf" + s]["bend"]
	if rc.y - rc.x > 0.5:
		v.append(["calf" + s, 0])
	return v


## the chain's joint points with the angles as they now stand (the pelvis, the spine, the leg; not the arms)
static func _chain(B: Body, s: String) -> void:
	for j in ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head", "thigh" + s, "calf" + s, "foot" + s]:
		var A := B.compose(j, B.ang[j])
		var pj: String = B.parent[j]
		if pj == "":
			B.G[j] = A
			B.P[j] = B.p0[j] + B.offset
		else:
			B.G[j] = (B.G[pj] as Quaternion) * A
			B.P[j] = (B.P[pj] as Vector3) + (B.G[pj] as Quaternion) * ((B.p0[j] - B.p0[pj]) as Vector3)
		B.E[j] = (B.P[j] as Vector3) + (B.G[j] as Quaternion) * ((B.e0[j] - B.p0[j]) as Vector3)


## the points that must lie on the curve: spine_01, spine_02, spine_03, neck_01, the head's centre, the support knee
const KNEE := 5   # index of the knee in _curve_pts


static func _curve_pts(B: Body, s: String) -> Array:
	return [B.P["spine_01"], B.P["spine_02"], B.P["spine_03"], B.P["neck_01"], head_c(B), B.P["calf" + s]]


static func _pose_set(B: Body, vars: Array, th: Array, s: String) -> void:
	for i in vars.size():
		var j: String = vars[i][0]
		var k: int = vars[i][1]
		var v: Vector3 = B.ang[j]
		v[k] = th[i]
		B.ang[j] = B.clamp_ang(j, v)
	_chain(B, s)


## the residual: each curve point minus its closest point on the curve (qs fixed), then the foot's drift
static func _resid(B: Body, vars: Array, th: Array, s: String, qs: Array, foot0: Vector3) -> Array:
	_pose_set(B, vars, th, s)
	var r := []
	var pts := _curve_pts(B, s)
	for k in pts.size():
		var d: Vector3 = (pts[k] as Vector3) - (qs[k] as Vector3)
		if k == KNEE:
			d *= KNEE_W
		r.append(d.x)
		r.append(d.y)
		r.append(d.z)
	var fpos: Vector3 = B.P["foot" + s]
	var fp := (fpos - foot0) * FOOT_W
	r.append(fp.x)
	r.append(fp.y)
	r.append(fp.z)
	return r


static func _cost(r: Array, th: Array, th0: Array) -> float:
	var c := 0.0
	for x in r:
		c += float(x) * float(x)
	for i in th.size():
		c += REG * (float(th[i]) - float(th0[i])) * (float(th[i]) - float(th0[i]))
	return c


## Gaussian elimination with partial pivoting; [] if singular
static func _solve(A: Array, b: Array) -> Array:
	var n := b.size()
	var M := []
	for i in n:
		var row: Array = (A[i] as Array).duplicate()
		row.append(b[i])
		M.append(row)
	for c in n:
		var piv := c
		for r in range(c + 1, n):
			if absf(M[r][c]) > absf(M[piv][c]):
				piv = r
		var tmp = M[c]
		M[c] = M[piv]
		M[piv] = tmp
		var d: float = M[c][c]
		if absf(d) < 1e-30:
			return []
		for r in range(c + 1, n):
			var f: float = M[r][c] / d
			for k in range(c, n + 1):
				M[r][k] -= f * M[c][k]
	var x := []
	x.resize(n)
	for i in range(n - 1, -1, -1):
		var acc: float = M[i][n]
		for k in range(i + 1, n):
			acc -= M[i][k] * x[k]
		x[i] = acc / M[i][i]
	return x


## Fit the chain and the support leg to curve (world points). Leaves the body posed; returns the report.
static func fit(B: Body, curve: Array, s: String) -> Dictionary:
	var vars := _vars(B, s)
	var n := vars.size()
	var lo := []
	var hi := []
	var th := []
	for v in vars:
		var r: Vector2 = B.lim[v[0]][["bend", "side"][v[1]]]
		lo.append(r.x)
		hi.append(r.y)
		th.append((B.ang[v[0]] as Vector3)[v[1]])
	var th0 := th.duplicate()
	_chain(B, s)
	var foot0: Vector3 = B.P["foot" + s]
	var lam := 1e-2   # Levenberg-Marquardt damping: up when a step fails, down when it works
	var iters := 0
	for it in ITERS:
		iters += 1
		_pose_set(B, vars, th, s)
		var qs := []
		for p in _curve_pts(B, s):
			qs.append(closest(curve, p))
		var r0 := _resid(B, vars, th, s, qs, foot0)
		var c0 := _cost(r0, th, th0)
		var cols := []
		for i in n:
			var h: float = EPS if th[i] + EPS <= hi[i] else -EPS
			var t2 := th.duplicate()
			t2[i] = th[i] + h
			var r1 := _resid(B, vars, t2, s, qs, foot0)
			var col := []
			for m in r0.size():
				col.append((float(r1[m]) - float(r0[m])) / h)
			cols.append(col)
		var JtJ := []
		var g := []
		for i in n:
			var row := []
			var gi := 0.0
			for j in n:
				var a := 0.0
				for m in r0.size():
					a += float(cols[i][m]) * float(cols[j][m])
				row.append(a)
			for m in r0.size():
				gi += float(cols[i][m]) * float(r0[m])
			gi += REG * (float(th[i]) - float(th0[i]))
			JtJ.append(row)
			g.append(-gi)
		var improved := false
		var cand := th.duplicate()
		var c1 := c0
		for _try in 30:
			var A := []
			for i in n:
				var row: Array = (JtJ[i] as Array).duplicate()
				row[i] = float(row[i]) * (1.0 + lam) + REG + 1e-12
				A.append(row)
			var step: Array = _solve(A, g)
			if step.is_empty():
				lam *= 10.0
				continue
			for i in n:
				cand[i] = clampf(th[i] + float(step[i]), lo[i], hi[i])
			c1 = _cost(_resid(B, vars, cand, s, qs, foot0), cand, th0)
			if c1 < c0:
				improved = true
				lam = maxf(lam / 3.0, 1e-7)
				break
			lam *= 4.0
		if not improved:
			break
		var gain := c0 - c1
		th = cand
		if gain < 1e-13:
			break
	_pose_set(B, vars, th, s)
	# the planted ankle back where it stood: the existing 2-bone IK (Body.reach) turns the leg only, the hip stays
	B.reach("foot" + s, foot0)
	# still off (a straight leg cannot follow a hip that tilts away from the ankle): move the whole body by the drift,
	# so the planted ankle stands exactly where it did and the chain moves with it, by that same few mm
	B.offset -= (B.P["foot" + s] as Vector3) - foot0
	B.fk()
	# the report: distances from the curve, the limits reached, the foot's drift
	var dist := {}
	var names := ["spine_01", "spine_02", "spine_03", "neck_01", "head", "knee"]
	var worst := 0.0   # the spine, neck and head (the knee is reported apart: a straight leg may not reach)
	var pts := _curve_pts(B, s)
	for k in pts.size():
		var d := (pts[k] as Vector3).distance_to(closest(curve, pts[k]))
		dist[names[k]] = d
		if k != KNEE:
			worst = maxf(worst, d)
	var at := []
	for i in n:
		var v: Vector3 = B.ang[vars[i][0]]
		var ax: String = ["bend", "side"][vars[i][1]]
		var val: float = v[vars[i][1]]
		var r: Vector2 = B.lim[vars[i][0]][ax]
		if val <= r.x + LIMIT_NEAR or val >= r.y - LIMIT_NEAR:
			at.append("%s %s" % [vars[i][0], ax])
	return {"dist": dist, "worst": worst, "knee": dist["knee"], "limits": at, "iters": iters,
		"foot_drift": (B.P["foot" + s] as Vector3).distance_to(foot0)}


## one stroke, as the view gave it (screen points). mirror = Shift: the lean goes the other way. Returns the report
## ({} when the stroke is too short). The caller pushes the undo step first.
func apply(B: Body, cam: Camera3D, pts2: Array, mirror := false) -> Dictionary:
	if pts2.size() < 3:
		return {}
	var pel: Vector3 = B.P["pelvis"]
	var s2 := pts2
	if mirror:
		var px := cam.unproject_position(pel).x
		s2 = []
		for p: Vector2 in pts2:
			s2.append(Vector2(2.0 * px - p.x, p.y))
	var raw := to_world(cam, s2, pel)
	if length_of(raw) < MIN_LEN:
		return {}
	var curve := resample(smooth(raw), N_CURVE)
	# the chain's anchor: the curve passes through the pelvis
	var shift: Vector3 = pel - closest(curve, pel)
	for i in curve.size():
		curve[i] = (curve[i] as Vector3) + shift
	last_curve = curve
	var s := support(B)
	var rep := fit(B, curve, s)
	rep["ok"] = true
	rep["side"] = s
	last = rep
	return rep


## the stroke as the view saw it: a drag's screen points, in order
func begin(p: Vector2) -> void:
	stroke = [p]


func add_point(p: Vector2) -> void:
	if stroke.is_empty() or (stroke[stroke.size() - 1] as Vector2).distance_to(p) >= 2.0:
		stroke.append(p)


func take_stroke() -> Array:
	var s := stroke
	stroke = []
	return s
