## sketch_pose.gd - ROADMAP I9: sketch to pose. Draw a stick figure over the view with the mouse; Kine fits the body to it.
##   DRAW (Sketch mode on the POSE page): a left drag is one stroke; Backspace removes the last stroke, Enter fits, Esc leaves.
##   RECOGNISE (recognise): a closed stroke is the head. The SPINE is the near-vertical stroke (chord within VERT_DEG of
##     the vertical) that is a JUNCTION at both ends (other strokes start at its top and at its bottom); of those the one
##     whose top is highest (the longest-vertical rule alone picks a leg, which is longer than the trunk). Strokes that
##     start at its top are ARMS, at its bottom LEGS (the nearer end is the attachment). A limb stroke is split at its
##     point of highest curvature, read as the point farthest from the chord (elbow / knee); a stroke whose farthest point
##     is under STRAIGHT_DEV of its chord is straight and the joint goes at the bone-length ratio. The stroke's far end is
##     read as the wrist / ankle (a hand's own length is not in a stick figure).
##     Which side: the body's right shoulder / hip is on one side of the screen; a stroke goes to the limb whose side it
##     is on, and when the view is a profile (no side to read) to the limb whose current wrist / ankle is nearer.
##   FIT (fit): the pelvis is put on the ray of the spine's foot; the trunk (pelvis + spine_01..03, bend and side; the neck
##     and head too when a head is drawn) is a Levenberg-Marquardt fit of the PROJECTED joint points to the stroke in the
##     image (so a foreshortened trunk tilts toward or away from the camera, starting from where it is now); each limb's
##     elbow / wrist is un-projected with its REAL bone lengths: the elbow on the elbow's ray at the upper-arm length from
##     the shoulder, the wrist on its ray at the forearm length from the elbow. Each ray meets the sphere twice (the depth
##     sign), so there are 4 candidates per limb, each solved by the app's LimbIK (the hinge and joint limits apply) and
##     scored by the reprojection error + a small price for each clamped joint + a small price for flipping the depth the
##     bone has now (the tie-break). The legs: when two candidates are within AMBIG of each other the balance (centre of mass
##     over the feet, scripts/balance.gd) decides. A limb that was not drawn is not touched. The body is then put on the floor.
##   Not recovered (a stick figure does not carry them): twist of the trunk / arms, the hands and feet's own angles (a foot near the floor is put flat), a scale (the sketch is read at the size drawn: limbs longer than the bones straighten).
##   I9 STEP 3 (the ambiguity as a UI choice): one drawing cannot say whether a bone near the picture plane points at the camera or
##     away (a mirror pair). After a fit every limb that has a second DEPTH CANDIDATE fitting the strokes within FLIP_PX gets a
##     small flip handle at its elbow / knee (flip(): the limb takes its next candidate at once, no re-fit; the caller makes it one
##     undo step). Two optional strokes: a SHOULDER LINE (horizontal, across the spine near its top) and a HIP LINE (across the
##     spine near its bottom) set the chest twist / hip yaw from their foreshortening (the projected shoulder / hip vector's length
##     is W cos(twist)), and the same mirror pair applies (+t and -t project alike): the side nearer the present twist is taken
##     and the handle flips it (a re-fit with the other side forced).
class_name SketchPose
extends Control

const MIN_STROKE := 12.0     # px: a shorter stroke is a click
const VERT_DEG := 55.0       # the spine's chord is within this of the vertical
const STRAIGHT_DEV := 0.03   # a limb whose farthest point is under this share of its chord is straight (tan(th/2)/2: 7 deg)
const JUNCTION := 0.2        # strokes meet when their ends are within this share of the median stroke length
const TAU_PX := 0.5          # px: the tremor a traced point may have (see relax); 1 px cost 9 deg on a bone in the picture plane even on clean strokes
const TIE_W := 0.04          # m-equivalent: price of flipping the depth side a bone has now
const CLAMP_W := 0.02        # m-equivalent: price of a clamped joint
const AMBIG := 0.03          # candidates within this cost of the best are ambiguous: the balance decides
const ITERS := 40            # trunk fit iterations at most
const EPS := 0.5             # deg: finite-difference step
const REG := 1e-5            # a soft pull to the angles the trunk started from
const PRIOR_SIG := 0.3       # m: the soft pull of the nearest library pose's depths (a tie-break along a flat valley, never a measurement)
const PRIOR_W := 0.03        # m-equivalent per metre of depth off the library pose's
const PRIOR_ROW := 0.02      # the weight of those priors among the pixel rows of the refinement
const REFINE_IT := 5         # Levenberg-Marquardt steps on the (elbow depth, wrist depth) of one candidate
const FLIP_PX := 2.0         # px: a second depth candidate that fits the strokes this well (both points together) is offered as a flip
const FLIP_DEG := 6.0        # deg: a candidate must differ from the others by this much on a bone to be a different answer
const LINE_DEG := 30.0       # a shoulder / hip line's chord is within this of the horizontal
const TWIST_AMBIG := 4.0     # deg: the two twist sides are an ambiguity when further apart than this
const TRUNK := ["pelvis", "spine_01", "spine_02", "spine_03"]
const TRUNK_H := ["neck_01", "head"]

var on := false
var drawing := false
var strokes: Array = []      # finished strokes (Array of Vector2 arrays)
var cur: Array = []          # the stroke in progress
var fitted: Array = []       # screen polylines of the fitted skeleton (faint, after a fit)
var last: Dictionary = {}    # the last fit's report
var flips: Dictionary = {}   # the last fit's flip entries (rep["flips"]): key -> {"kind", "at", ...}; {} = no handles
var flip_state: Dictionary = {}   # B.state() right after the fit / last flip: the handles are only valid while the body is this
var hist: Array = []         # [{"state": B.state() before a flip, "idx": {key: i}}]: Ctrl+Z of a flip brings its handles back
var hpos: Array = []         # [{"key", "pos"}] the handles on the screen, refreshed by main whenever it draws them

static var lib_exclude := ""   # a pose file (basename) the prior must NOT use: a test fits a library pose against the OTHERS
static var _lib: Array = []    # [{"name", "d"}] the poses of poses/ and poses/lib/ (the R27 / I12 library, as smart_drag.gd reads it)
static var _scratch: Body = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 40


# ---- the drawing ---------------------------------------------------------------------------------------------------

func begin(p: Vector2) -> void:
	drawing = true
	cur = [p]
	queue_redraw()


func add_point(p: Vector2) -> void:
	if cur.is_empty() or (cur[cur.size() - 1] as Vector2).distance_to(p) >= 2.0:
		cur.append(p)
		queue_redraw()


## the drag ends: a stroke of at least MIN_STROKE joins the sketch; returns whether it did
func finish() -> bool:
	drawing = false
	var s := cur
	cur = []
	queue_redraw()
	if s.size() < 2 or _plen(s) < MIN_STROKE:
		return false
	strokes.append(s)
	return true


func remove_last() -> bool:
	if strokes.is_empty():
		return false
	strokes.pop_back()
	queue_redraw()
	return true


func clear() -> void:
	strokes = []
	cur = []
	fitted = []
	flips = {}
	hist = []
	hpos = []
	drawing = false
	queue_redraw()


func _draw() -> void:
	if not on:
		return
	var gold := Tok.c("mk_gold")
	var faint := Tok.c("mk_green")
	faint.a = 0.6
	for pl in fitted:
		if (pl as Array).size() > 1:
			draw_polyline(PackedVector2Array(pl), faint, 2.0, true)
		for q: Vector2 in pl:
			draw_circle(q, 3.5, faint)
	for h in hpos:
		var q: Vector2 = h["pos"]
		draw_circle(q, 12.0, Tok.c("mk_gold"))
		draw_circle(q, 9.5, Color(0, 0, 0, 0.55))
		var ink := Tok.c("mk_gold")
		draw_line(q + Vector2(-5, -2.5), q + Vector2(5, -2.5), ink, 1.6, true)   # a two-way arrow: swap to the mirror depth
		draw_line(q + Vector2(5, -2.5), q + Vector2(2, -5.5), ink, 1.6, true)
		draw_line(q + Vector2(5, 2.5), q + Vector2(-5, 2.5), ink, 1.6, true)
		draw_line(q + Vector2(-5, 2.5), q + Vector2(-2, 5.5), ink, 1.6, true)
	for s in strokes:
		draw_polyline(PackedVector2Array(s), gold, 3.0, true)
	if cur.size() > 1:
		draw_polyline(PackedVector2Array(cur), gold, 3.0, true)


# ---- recognising ---------------------------------------------------------------------------------------------------

static func _plen(p: Array) -> float:
	var t := 0.0
	for i in range(1, p.size()):
		t += (p[i] as Vector2).distance_to(p[i - 1])
	return t


static func _clean(s: Array) -> Array:
	var out := []
	for p in s:
		if out.is_empty() or (out[out.size() - 1] as Vector2).distance_to(p) >= 1.0:
			out.append(p)
	return out


## the point of highest curvature of a limb stroke (the one farthest from its chord), or null when it is straight
static func corner(p: Array) -> Variant:
	var a: Vector2 = p[0]
	var ch: Vector2 = (p[p.size() - 1] as Vector2) - a
	var cl := ch.length()
	if cl < 1e-6:
		return null
	var best := 0.0
	var bi := -1
	for i in range(1, p.size() - 1):
		var d := absf(ch.cross((p[i] as Vector2) - a)) / cl
		if d > best:
			best = d
			bi = i
	if bi < 0 or best < STRAIGHT_DEV * cl:
		return null
	return p[bi]


static func _near_end(p: Array, q: Vector2) -> float:
	return minf((p[0] as Vector2).distance_to(q), (p[p.size() - 1] as Vector2).distance_to(q))


## strokes -> {"ok", "spine": [top ... bottom], "head": {"c", "r"} or {}, "arms": [limb], "legs": [limb], "extra": n}
## limb = {"pts": attach ... tip, "tip", "corner": Vector2 or null}
static func recognise(strokes_in: Array) -> Dictionary:
	var open := []
	var head := {}
	for s in strokes_in:
		var p := _clean(s)
		if p.size() < 2:
			continue
		var L := _plen(p)
		if L < MIN_STROKE:
			continue
		var gap: float = (p[0] as Vector2).distance_to(p[p.size() - 1])
		if gap < 0.25 * L and p.size() >= 8:
			var c := Vector2.ZERO
			for q: Vector2 in p:
				c += q
			c /= float(p.size())
			if head.is_empty() or L > float(head["L"]):
				head = {"c": c, "r": L / TAU, "L": L}
		else:
			open.append({"p": p, "L": L})
	if open.is_empty():
		return {"ok": false, "why": "no line to read: draw the spine first, a line from the neck down to the hips"}
	var ls := open.map(func(o): return float(o["L"]))
	ls.sort()
	var tol: float = JUNCTION * float(ls[ls.size() / 2])
	var best := -1
	var best_key := Vector2(-1.0, 0.0)   # (junction ends, -top y)
	for i in open.size():
		var p: Array = open[i]["p"]
		var a: Vector2 = p[0]
		var b: Vector2 = p[p.size() - 1]
		var top := a if a.y <= b.y else b
		var bot := b if a.y <= b.y else a
		var ch := bot - top
		if ch.length() < 0.5 * float(open[i]["L"]) or absf(ch.x) > tan(deg_to_rad(VERT_DEG)) * absf(ch.y):
			continue
		var jt := 0
		var jb := 0
		for k in open.size():
			if k == i:
				continue
			var q: Array = open[k]["p"]
			if _near_end(q, top) <= tol:
				jt = 1
			if _near_end(q, bot) <= tol:
				jb = 1
		var key := Vector2(float(jt + jb), -top.y)
		if key.x > best_key.x or (key.x == best_key.x and key.y > best_key.y):
			best_key = key
			best = i
	if best < 0:
		return {"ok": false, "why": "no near-vertical line for the spine: draw it as a line from the neck down to the hips"}
	var sp: Array = (open[best]["p"] as Array).duplicate()
	if (sp[0] as Vector2).y > (sp[sp.size() - 1] as Vector2).y:
		sp.reverse()
	var top: Vector2 = sp[0]
	var bot: Vector2 = sp[sp.size() - 1]
	var slen := top.distance_to(bot)
	var arms := []
	var legs := []
	var extra := 0
	var lines := {"shoulder": null, "hip": null}   # a horizontal stroke ACROSS the spine, its ends clear of the spine's ends
	var is_line := {}
	for k in open.size():
		if k == best:
			continue
		var q: Array = open[k]["p"]
		var qa: Vector2 = q[0]
		var qb: Vector2 = q[q.size() - 1]
		var qc := qb - qa
		if qc.length() < 0.5 * float(open[k]["L"]) or absf(qc.y) > tan(deg_to_rad(LINE_DEG)) * absf(qc.x):
			continue
		if minf(minf(qa.distance_to(top), qa.distance_to(bot)), minf(qb.distance_to(top), qb.distance_to(bot))) < 0.08 * slen:
			continue   # starts at the spine's end: an arm or a leg
		var mp := (qa + qb) * 0.5
		if mp.distance_to(_closest2(sp, mp)) > 0.2 * slen:
			continue
		var dtm := mp.distance_to(top)
		var dbm := mp.distance_to(bot)
		var kind := "shoulder" if dtm <= dbm else "hip"
		if minf(dtm, dbm) > 0.35 * slen:
			continue
		if lines[kind] == null or float(open[k]["L"]) > float(lines[kind]["L"]):
			lines[kind] = {"p": q, "L": open[k]["L"]}
		is_line[k] = true
	for k in open.size():
		if k == best or is_line.has(k):
			continue
		var q: Array = (open[k]["p"] as Array).duplicate()
		var dt := _near_end(q, top)
		var db := _near_end(q, bot)
		if minf(dt, db) > 0.8 * slen:
			extra += 1   # does not start at the spine
			continue
		var arm := dt <= db
		var anchor := top if arm else bot
		if (q[0] as Vector2).distance_to(anchor) > (q[q.size() - 1] as Vector2).distance_to(anchor):
			q.reverse()   # attach first, tip last
		var limb := {"pts": q, "tip": q[q.size() - 1], "corner": corner(q), "L": open[k]["L"]}
		(arms if arm else legs).append(limb)
	for g in [arms, legs]:
		(g as Array).sort_custom(func(x, y): return float(x["L"]) > float(y["L"]))
		while (g as Array).size() > 2:
			(g as Array).pop_back()
			extra += 1
	return {"ok": true, "spine": sp, "head": head, "arms": arms, "legs": legs, "extra": extra,
		"shoulder": (lines["shoulder"]["p"] if lines["shoulder"] != null else []), "hip": (lines["hip"]["p"] if lines["hip"] != null else [])}


## which limb is which: limbs (<= 2) -> {"_l": limb or null, "_r": limb or null}. The side on the screen decides when the
## shoulders / hips are apart on it, else the limb whose present tip is nearer
static func assign(limbs: Array, cur_tip: Dictionary, side_dx: Dictionary, axis_x: float, scale_px: float, min_side: float) -> Dictionary:
	var out := {"_l": null, "_r": null}
	var cost := func(l: Dictionary, sd: String) -> float:
		var c := ((l["tip"] as Vector2) - (cur_tip[sd] as Vector2)).length() / scale_px
		var sx: float = side_dx[sd]
		var tdx: float = (l["tip"] as Vector2).x - axis_x
		if absf(sx) > min_side and absf(tdx) > 0.5 * min_side and signf(tdx) != signf(sx):
			c += 1.0
		return c
	if limbs.size() == 1:
		var sd := "_l" if cost.call(limbs[0], "_l") <= cost.call(limbs[0], "_r") else "_r"
		out[sd] = limbs[0]
	elif limbs.size() == 2:
		var straight: float = cost.call(limbs[0], "_l") + cost.call(limbs[1], "_r")
		var swapped: float = cost.call(limbs[0], "_r") + cost.call(limbs[1], "_l")
		if straight <= swapped:
			out["_l"] = limbs[0]
			out["_r"] = limbs[1]
		else:
			out["_r"] = limbs[0]
			out["_l"] = limbs[1]
	return out


# ---- the library prior (R27 / I12: the poses the user already has say which depth a limb tends to take) ---------------------

static func _library() -> Array:
	if _lib.is_empty():
		for dir in SmartDrag.POSE_DIRS:
			for fn in DirAccess.get_files_at(dir):
				if fn.ends_with(".json"):
					var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(dir) + fn))
					if d is Dictionary and (d as Dictionary).get("joints") is Dictionary:
						_lib.append({"name": fn, "d": d})
	return _lib


## per limb tip: the depths ([upper bone, lower bone], m along the view) of the library pose whose limb, put on THIS body's
## trunk, projects nearest to the drawn elbow / wrist; a limb that nothing matches within a body length gets no prior
static func library_prior(B: Body, cam: Camera3D, drawn: Dictionary, S: float) -> Dictionary:
	var out := {}
	if drawn.is_empty():
		return out
	if _scratch == null:
		_scratch = Body.new()
		_scratch.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var sb := _scratch
	var fwd := -cam.global_basis.z
	var best := {}
	for tip in drawn:
		best[tip] = [INF, [0.0, 0.0]]
	for e in _library():
		if String(e["name"]) == lib_exclude:
			continue
		sb.from_dict(e["d"])
		for j in TRUNK + TRUNK_H + ["clavicle_l", "clavicle_r"]:
			if B.ang.has(j) and sb.ang.has(j):
				sb.ang[j] = B.ang[j]
		sb.offset = B.offset
		sb.fk()
		for tip in drawn:
			var mid: String = sb.parent[tip]
			var root: String = sb.parent[mid]
			var c := (cam.unproject_position(sb.P[mid]) - (drawn[tip]["el"] as Vector2)).length() + (cam.unproject_position(sb.P[tip]) - (drawn[tip]["wr"] as Vector2)).length()
			if c < float(best[tip][0]):
				best[tip] = [c, [((sb.P[mid] - sb.P[root]) as Vector3).dot(fwd), ((sb.P[tip] - sb.P[mid]) as Vector3).dot(fwd)]]
	for tip in drawn:
		if float(best[tip][0]) / S < 1.0:
			out[tip] = best[tip][1]
	return out


# ---- un-projecting -------------------------------------------------------------------------------------------------

## the two points of the ray through screen point p2 that lie r from c (near first). A ray that misses the sphere gives
## the point of the sphere nearest the ray twice (the bone lies as flat as the picture allows)
static func ray_sphere(cam: Camera3D, p2: Vector2, c: Vector3, r: float) -> Array:
	var o := cam.project_ray_origin(p2)
	var d := cam.project_ray_normal(p2)
	var oc := c - o
	var b := d.dot(oc)
	var disc := r * r - (oc.length_squared() - b * b)
	if disc <= 1e-12:
		var q := o + d * b
		var v := q - c
		var p := c + (v.normalized() if v.length() > 1e-9 else cam.global_basis.x) * r
		return [p, p]
	var s := sqrt(disc)
	return [o + d * (b - s), o + d * (b + s)]


static func _hit(cam: Camera3D, p2: Vector2, on_pt: Vector3, n: Vector3) -> Vector3:
	var o := cam.project_ray_origin(p2)
	var d := cam.project_ray_normal(p2)
	return o + d * ((on_pt - o).dot(n) / d.dot(n))


static func _closest2(pl: Array, p: Vector2) -> Vector2:
	var best := INF
	var bq: Vector2 = pl[0]
	for i in range(pl.size() - 1):
		var a: Vector2 = pl[i]
		var ab: Vector2 = (pl[i + 1] as Vector2) - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 < 1e-12 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		var q := a + ab * t
		var d := p.distance_squared_to(q)
		if d < best:
			best = d
			bq = q
	return bq


# ---- the trunk -----------------------------------------------------------------------------------------------------

static func _trunk_fk(B: Body) -> void:
	B._fk_a = {}   # this writes G / P / E itself, outside the dirty-tracked fk() (as LineOfAction._chain)
	for j in ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head"]:
		var A := B.compose(j, B.ang[j])
		var pj: String = B.parent[j]
		if pj == "":
			B.G[j] = A
			B.P[j] = B.p0[j] + B.offset
		else:
			B.G[j] = (B.G[pj] as Quaternion) * A
			B.P[j] = (B.P[pj] as Vector3) + (B.G[pj] as Quaternion) * ((B.p0[j] - B.p0[pj]) as Vector3)
		B.E[j] = (B.P[j] as Vector3) + (B.G[j] as Quaternion) * ((B.e0[j] - B.p0[j]) as Vector3)


static func _trunk_res(B: Body, cam: Camera3D, S: float, spine: Array, head: Dictionary) -> Array:
	var r := []
	for j in ["spine_01", "spine_02", "spine_03"]:
		var u := cam.unproject_position(B.P[j])
		var d := (u - _closest2(spine, u)) / S
		r.append(d.x)
		r.append(d.y)
	var dn := (cam.unproject_position(B.P["neck_01"]) - (spine[0] as Vector2)) / S
	r.append(dn.x)
	r.append(dn.y)
	if not head.is_empty():
		var dh := (cam.unproject_position(LineOfAction.head_c(B)) - (head["c"] as Vector2)) / S
		r.append(dh.x)
		r.append(dh.y)
	return r


static func _fit_trunk(B: Body, cam: Camera3D, S: float, spine: Array, head: Dictionary) -> Dictionary:
	var vars := []
	for j in TRUNK + (TRUNK_H if not head.is_empty() else []):
		for k in 2:
			var r: Vector2 = B.lim[j][["bend", "side"][k]]
			if r.y - r.x > 0.5:
				vars.append([j, k])
	var n := vars.size()
	var th := []
	var lo := []
	var hi := []
	for v in vars:
		th.append((B.ang[v[0]] as Vector3)[v[1]])
		var r: Vector2 = B.lim[v[0]][["bend", "side"][v[1]]]
		lo.append(r.x)
		hi.append(r.y)
	var th0 := th.duplicate()
	var set_th := func(t: Array) -> void:
		for i in n:
			var a: Vector3 = B.ang[vars[i][0]]
			a[vars[i][1]] = t[i]
			B.ang[vars[i][0]] = B.clamp_ang(vars[i][0], a)
		_trunk_fk(B)
	var cost := func(r: Array, t: Array) -> float:
		var c := 0.0
		for x in r:
			c += float(x) * float(x)
		for i in n:
			c += REG * (float(t[i]) - float(th0[i])) * (float(t[i]) - float(th0[i]))
		return c
	set_th.call(th)
	var r0 := _trunk_res(B, cam, S, spine, head)
	var c0: float = cost.call(r0, th)
	var lam := 1e-2
	var iters := 0
	for it in ITERS:
		iters += 1
		var cols := []
		for i in n:
			var t2 := th.duplicate()
			t2[i] = th[i] + EPS
			set_th.call(t2)
			var r1 := _trunk_res(B, cam, S, spine, head)
			var col := []
			for m in r0.size():
				col.append((float(r1[m]) - float(r0[m])) / EPS)
			cols.append(col)
		var g := []
		var JtJ := []
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
		var r1b := r0
		for _try in 20:
			var A := []
			for i in n:
				var row: Array = (JtJ[i] as Array).duplicate()
				row[i] = float(row[i]) * (1.0 + lam) + REG + 1e-12
				A.append(row)
			var step: Array = LineOfAction._solve(A, g)
			if step.is_empty():
				lam *= 10.0
				continue
			for i in n:
				cand[i] = clampf(th[i] + float(step[i]), lo[i], hi[i])
			set_th.call(cand)
			r1b = _trunk_res(B, cam, S, spine, head)
			c1 = cost.call(r1b, cand)
			if c1 < c0:
				improved = true
				lam = maxf(lam / 3.0, 1e-7)
				break
			lam *= 4.0
		if not improved:
			break
		var gain := c0 - c1
		th = cand
		r0 = r1b
		c0 = c1
		if gain < 1e-10:
			break
	set_th.call(th)
	B.fk()
	var worst := 0.0
	for x in _trunk_res(B, cam, S, spine, head):
		worst = maxf(worst, absf(float(x)))
	return {"iters": iters, "worst_m": worst}


# ---- the limbs -----------------------------------------------------------------------------------------------------

## DEPTH INSIDE THE PIXEL: a bone of length r whose picture is ell long has depth sqrt(r^2 - ell^2), and near the picture plane
## that is wildly sensitive (a bone 6 deg out of the plane is 0.5 % shorter on the screen: half a pixel of a hand tremor moves
## its depth by 10 deg). So the depth is not taken from the exact intersection but from the old pose's, clamped into the range
## the picture allows when its length is good to tau (the sign stays the candidate's). e0 = the exact intersection, c = the
## bone's start, hint = the depth (m along the view) of this bone now
static func relax(fwd: Vector3, c: Vector3, e0: Vector3, r: float, hint: float, tau: float) -> Vector3:
	var v := e0 - c
	var z := v.dot(fwd)
	var lat := v - fwd * z
	var ell := lat.length()
	if ell < 1e-6:
		return e0
	var zlo := sqrt(maxf(0.0, r * r - (ell + tau) * (ell + tau)))
	var zhi := sqrt(maxf(0.0, r * r - maxf(ell - tau, 0.0) * maxf(ell - tau, 0.0)))
	var zm := clampf(absf(hint), zlo, zhi)
	var sg := signf(z) if absf(z) > 1e-6 else (signf(hint) if hint != 0.0 else 1.0)
	return c + lat / ell * sqrt(maxf(r * r - zm * zm, 0.0)) + fwd * (sg * zm)


## one candidate's residuals: the mid joint and the tip on the screen (m-equivalent) + the soft depth priors. The body is
## posed by LimbIK from the elbow point e (the pole: it fixes the bend plane) and the wrist point w
static func _cand_res(B: Body, cam: Camera3D, tip: String, el2: Vector2, wr2: Vector2, S: float, e: Vector3, w: Vector3, rot, keep: Array, hint: Array, prior: Array) -> Array:
	var mid: String = B.parent[tip]
	var root: String = B.parent[mid]
	B.ang[root] = keep[0]
	B.ang[mid] = keep[1]
	B.ang[tip] = keep[2]
	B.fk()
	var res := LimbIK.solve(B, tip, w, e, rot)
	var fwd := -cam.global_basis.z
	var r := []
	var dm := cam.unproject_position(B.P[mid]) - el2
	var dt := cam.unproject_position(B.P[tip]) - wr2
	r.append_array([dm.x / S, dm.y / S, dt.x / S, dt.y / S])
	var d1 := ((B.P[mid] - B.P[root]) as Vector3).dot(fwd)
	var d2 := ((B.P[tip] - B.P[mid]) as Vector3).dot(fwd)
	for h in [hint, prior]:
		if not (h as Array).is_empty():
			r.append((d1 - float(h[0])) / PRIOR_SIG * PRIOR_ROW)
			r.append((d2 - float(h[1])) / PRIOR_SIG * PRIOR_ROW)
	return [r, res, d1, d2]


## the 4 depth candidates of a limb (elbow side x wrist side), each solved by LimbIK and scored; best first. The body is
## left as it was. hint = the depth (m, along the view) of [upper bone, lower bone] now: flipping it costs TIE_W.
## Each candidate starts at the relaxed intersection and is then REFINED: the limb is a hinge, so the elbow's depth (the bend
## plane) and the wrist's depth (the bend angle) together decide where the mid joint lands on the screen; a 2-parameter
## Levenberg-Marquardt moves e and w along their rays until the mid joint and the tip fall on the drawn points, the depth
## priors (the old pose + the nearest library pose) only breaking the tie along a flat valley. prior = [] when there is none
static func limb_cands(B: Body, cam: Camera3D, tip: String, el2: Vector2, wr2: Vector2, S: float, hint: Array, rot, prior := []) -> Array:
	var mid: String = B.parent[tip]
	var root: String = B.parent[mid]
	var R: Vector3 = B.P[root]
	var u: float = ((B.p0[mid] - B.p0[root]) as Vector3).length()
	var f: float = ((B.p0[tip] - B.p0[mid]) as Vector3).length()
	var fwd := -cam.global_basis.z
	var keep := [B.ang[root], B.ang[mid], B.ang[tip]]
	var out := []
	var tau := TAU_PX / S   # m: a point on the screen is good to about this many pixels; a bone's depth is free inside that
	var de := cam.project_ray_normal(el2)
	var dw := cam.project_ray_normal(wr2)
	for e0: Vector3 in ray_sphere(cam, el2, R, u):
		var e1 := relax(fwd, R, e0, u, float(hint[0]), tau)
		for w0: Vector3 in ray_sphere(cam, wr2, e1, f):
			var w1 := relax(fwd, e1, w0, f, float(hint[1]), tau)
			var pa := [0.0, 0.0]
			var rr := _cand_res(B, cam, tip, el2, wr2, S, e1, w1, rot, keep, hint, prior)
			var c0 := 0.0
			for x in rr[0]:
				c0 += float(x) * float(x)
			var lam := 1e-2
			for _it in REFINE_IT:
				var cols := []
				for k in 2:
					var pk := pa.duplicate()
					pk[k] += 0.004
					var r2 := _cand_res(B, cam, tip, el2, wr2, S, e1 + de * float(pk[0]), w1 + dw * float(pk[1]), rot, keep, hint, prior)
					var col := []
					for m in (rr[0] as Array).size():
						col.append((float(r2[0][m]) - float(rr[0][m])) / 0.004)
					cols.append(col)
				var a00 := 0.0
				var a01 := 0.0
				var a11 := 0.0
				var g0 := 0.0
				var g1 := 0.0
				for m in (rr[0] as Array).size():
					a00 += float(cols[0][m]) * float(cols[0][m])
					a01 += float(cols[0][m]) * float(cols[1][m])
					a11 += float(cols[1][m]) * float(cols[1][m])
					g0 -= float(cols[0][m]) * float(rr[0][m])
					g1 -= float(cols[1][m]) * float(rr[0][m])
				var better := false
				for _t in 6:
					var b00 := a00 * (1.0 + lam) + 1e-9
					var b11 := a11 * (1.0 + lam) + 1e-9
					var det := b00 * b11 - a01 * a01
					if absf(det) < 1e-18:
						lam *= 10.0
						continue
					var s0 := clampf((g0 * b11 - a01 * g1) / det, -0.15, 0.15)
					var s1 := clampf((b00 * g1 - a01 * g0) / det, -0.15, 0.15)
					var pn := [float(pa[0]) + s0, float(pa[1]) + s1]
					var r3 := _cand_res(B, cam, tip, el2, wr2, S, e1 + de * float(pn[0]), w1 + dw * float(pn[1]), rot, keep, hint, prior)
					var c3 := 0.0
					for x in r3[0]:
						c3 += float(x) * float(x)
					if c3 < c0:
						pa = pn
						rr = r3
						c0 = c3
						lam = maxf(lam / 3.0, 1e-7)
						better = true
						break
					lam *= 4.0
				if not better:
					break
			# the last trial of the loop above may have been a worse one: put the limb back at the best parameters
			rr = _cand_res(B, cam, tip, el2, wr2, S, e1 + de * float(pa[0]), w1 + dw * float(pa[1]), rot, keep, hint, prior)
			var res: Dictionary = rr[1]
			var err := (cam.unproject_position(B.P[mid]) - el2).length() + (cam.unproject_position(B.P[tip]) - wr2).length()
			var c := err / S + CLAMP_W * (res["clamped"] as Array).size()
			var d1: float = rr[2]
			var d2: float = rr[3]
			if absf(float(hint[0])) > 0.03 and signf(d1) != signf(float(hint[0])):
				c += TIE_W
			if absf(float(hint[1])) > 0.03 and signf(d2) != signf(float(hint[1])):
				c += TIE_W
			if not prior.is_empty():
				c += PRIOR_W * (absf(d1 - float(prior[0])) + absf(d2 - float(prior[1])))
			out.append({"cost": c, "ang": [B.ang[root], B.ang[mid], B.ang[tip]], "clamped": res["clamped"], "miss": res["miss"], "err": err,
				"u": ((B.P[mid] - B.P[root]) as Vector3).normalized(), "l": ((B.P[tip] - B.P[mid]) as Vector3).normalized()})
	B.ang[root] = keep[0]
	B.ang[mid] = keep[1]
	B.ang[tip] = keep[2]
	B.fk()
	out.sort_custom(func(a, b): return float(a["cost"]) < float(b["cost"]))
	return out


static func _put(B: Body, tip: String, c: Dictionary) -> void:
	var mid: String = B.parent[tip]
	var root: String = B.parent[mid]
	B.ang[root] = c["ang"][0]
	B.ang[mid] = c["ang"][1]
	B.ang[tip] = c["ang"][2]
	B.fk()


static func _balance_pen(B: Body) -> float:
	var keep := B.offset
	B.ground()
	var m: float = Balance.read(B)["margin"]
	B.offset = keep
	B.fk()
	return maxf(0.0, -m)


static func _poly(B: Body, cam: Camera3D, names: Array) -> Array:
	var out := []
	for j in names:
		out.append(cam.unproject_position(B.P[j]))
	return out


## the candidates a user may choose between for one limb: the chosen one first, then the others that fit the strokes within
## FLIP_PX and point somewhere else (a bone FLIP_DEG apart), best fit first; one entry only = no ambiguity, no handle
static func _alts(chosen: Dictionary, all: Array) -> Array:
	var out := [chosen]
	if float(chosen["err"]) > FLIP_PX:
		return out
	var rest := all.filter(func(c): return float(c["err"]) <= FLIP_PX)
	rest.sort_custom(func(a, b): return float(a["err"]) < float(b["err"]))
	for c in rest:
		var distinct := true
		for o in out:
			if maxf(rad_to_deg((c["u"] as Vector3).angle_to(o["u"])), rad_to_deg((c["l"] as Vector3).angle_to(o["l"]))) < FLIP_DEG:
				distinct = false
		if distinct and out.size() < 4:
			out.append(c)
	return out


static func _skel(B: Body, cam: Camera3D) -> Array:
	var sk := []
	sk.append(_poly(B, cam, ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01"]))
	for sd in ["_l", "_r"]:
		sk.append(_poly(B, cam, ["upperarm" + sd, "lowerarm" + sd, "hand" + sd]))
		sk.append(_poly(B, cam, ["thigh" + sd, "calf" + sd, "foot" + sd]))
	var hc := cam.unproject_position(LineOfAction.head_c(B))
	sk.append([cam.unproject_position(B.P["neck_01"]), hc])
	return sk


static func _stand_on_floor(B: Body, tips: Array) -> void:
	B.ground()
	for tip in tips:   # a foot near the floor stands flat on it (a raised foot keeps its angle to the shin)
		if (B.P[tip] as Vector3).y < 0.15:
			B.flat_foot((tip as String).right(2))
	B.ground()


## ---- twist from a shoulder / hip line. The line's projected vector has the length of the real one times cos(twist), so the
## twist is found by scanning the joint's twist and comparing the PROJECTED vector between the two joints with the stroke's
## (orientation: the sign that agrees with the present vector). +t and -t project alike: both sides are returned
static func _twist_scan(B: Body, cam: Camera3D, ja: String, jb: String, line: Array, setter: Callable, lo: float, hi: float) -> Dictionary:
	var v: Vector2 = (line[line.size() - 1] as Vector2) - (line[0] as Vector2)
	var saved: Dictionary = B.ang.duplicate(true)
	B.fk()
	var w0 := cam.unproject_position(B.P[jb]) - cam.unproject_position(B.P[ja])
	var target := v * (1.0 if w0.dot(v) >= 0.0 else -1.0)
	var pos := [0.0, INF]
	var neg := [0.0, INF]
	var t := lo
	while t <= hi + 1e-6:
		setter.call(t)
		B.fk()
		var c := (cam.unproject_position(B.P[jb]) - cam.unproject_position(B.P[ja]) - target).length()
		if t >= 0.0 and c < float(pos[1]):
			pos = [t, c]
		if t <= 0.0 and c < float(neg[1]):
			neg = [t, c]
		t += 1.0
	B.ang = saved
	B.fk()
	return {"pos": pos, "neg": neg}


## which side to take: the forced one (+1 / -1), else the side whose cost is clearly lower, else the side of the present twist
static func _pick_side(sc: Dictionary, cur: float, force: int) -> Dictionary:
	var p: Array = sc["pos"]
	var n: Array = sc["neg"]
	var amb := float(p[1]) <= FLIP_PX and float(n[1]) <= FLIP_PX and absf(float(p[0]) - float(n[0])) > TWIST_AMBIG
	var side := 1
	if force != 0:
		side = force
	elif absf(float(p[1]) - float(n[1])) > FLIP_PX:
		side = 1 if float(p[1]) < float(n[1]) else -1
	elif absf(cur) >= 2.0:
		side = 1 if cur > 0.0 else -1
	var t: float = float((p if side > 0 else n)[0])
	return {"t": t, "side": side, "ambiguous": amb, "cost": float((p if side > 0 else n)[1])}


static func _set_spine_twist(B: Body, total: float) -> void:
	for j in ["spine_01", "spine_02", "spine_03"]:
		var a: Vector3 = B.ang[j]
		a.z = total / 3.0
		B.ang[j] = B.clamp_ang(j, a)


static func _spine_twist(B: Body) -> float:
	return (B.ang["spine_01"] as Vector3).z + (B.ang["spine_02"] as Vector3).z + (B.ang["spine_03"] as Vector3).z


static func _set_pelvis_twist(B: Body, t: float) -> void:
	var a: Vector3 = B.ang["pelvis"]
	a.z = t
	B.ang["pelvis"] = B.clamp_ang("pelvis", a)


## the handles' screen places: [{"key", "pos"}]. A limb's is at its elbow / knee, the hips' between the thighs, the chest's between the shoulders
static func handles(B: Body, cam: Camera3D, flips: Dictionary) -> Array:
	var out := []
	for key in flips:
		var f: Dictionary = flips[key]
		var at: Vector3
		if f["kind"] == "limb":
			at = B.P[f["at"]]
		elif f["kind"] == "hip":
			at = ((B.P["thigh_l"] as Vector3) + (B.P["thigh_r"] as Vector3)) * 0.5
		else:
			at = ((B.P["upperarm_l"] as Vector3) + (B.P["upperarm_r"] as Vector3)) * 0.5
		out.append({"key": key, "pos": cam.unproject_position(at)})
	return out


## the flip handle of `key` was clicked: a limb takes its next candidate AT ONCE (no re-fit; the caller makes it one undo step);
## a twist side re-fits the body with the other side forced (the limbs hang on the trunk, so they are read again). Returns the
## report (the same one, or the new fit's)
static func flip(B: Body, cam: Camera3D, strokes_in: Array, rep: Dictionary, key: String) -> Dictionary:
	var f: Dictionary = rep["flips"][key]
	if f["kind"] == "limb":
		f["i"] = (int(f["i"]) + 1) % (f["cands"] as Array).size()
		var tip: String = f["tip"]
		_put(B, tip, f["cands"][f["i"]])
		if tip.begins_with("foot"):
			_stand_on_floor(B, ["foot_l", "foot_r"])
		rep["skeleton"] = _skel(B, cam)
		return rep
	var force := {key: -int(f["side"])}
	var other := "sh" if key == "hip" else "hip"
	if rep["flips"].has(other):
		force[other] = int(rep["flips"][other]["side"])
	return fit(B, cam, strokes_in, force)


## strokes (screen points) -> the body posed. The caller pushes the undo step first. Returns the report.
## force = {"hip": +1/-1, "sh": +1/-1}: the twist side to take instead of the default (a flip of the twist handles)
static func fit(B: Body, cam: Camera3D, strokes_in: Array, force := {}) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var rec := recognise(strokes_in)
	if not rec["ok"]:
		return rec
	B.fk()
	var fwd := -cam.global_basis.z
	var pel0: Vector3 = B.P["pelvis"]
	var S := (cam.unproject_position(pel0 + cam.global_basis.x) - cam.unproject_position(pel0)).length()
	var spine: Array = rec["spine"]
	var head: Dictionary = rec["head"]
	var hint := {}
	var rot := {}
	for tip in LimbIK.LIMBS:
		var mid: String = B.parent[tip]
		var root: String = B.parent[mid]
		hint[tip] = [((B.P[mid] - B.P[root]) as Vector3).dot(fwd), ((B.P[tip] - B.P[mid]) as Vector3).dot(fwd)]
		rot[tip] = null
	var cur_px := {}   # the present wrist / ankle on the screen, for the side assignment
	var side_dx := {"arms": {}, "legs": {}}
	var neck_x := cam.unproject_position(B.P["neck_01"]).x
	var pel_x := cam.unproject_position(B.P["pelvis"]).x
	for sd in ["_l", "_r"]:
		cur_px["hand" + sd] = cam.unproject_position(B.P["hand" + sd])
		cur_px["foot" + sd] = cam.unproject_position(B.P["foot" + sd])
		side_dx["arms"][sd] = cam.unproject_position(B.P["upperarm" + sd]).x - neck_x
		side_dx["legs"][sd] = cam.unproject_position(B.P["thigh" + sd]).x - pel_x
	# the pelvis on the ray of the spine's foot, at the depth it has now
	var W := _hit(cam, spine[spine.size() - 1], pel0, fwd)
	B.offset += W - pel0
	B.fk()
	var tr := _fit_trunk(B, cam, S, spine, head)
	var rep := {"ok": true, "trunk": tr, "limbs": {}, "kept": [], "extra": rec["extra"], "head": not head.is_empty(), "flips": {}}
	# twist from the optional lines: the hip yaw first (the pelvis carries the whole trunk), then the chest relative to it
	if (rec["hip"] as Array).size() >= 2:
		var hs := _twist_scan(B, cam, "thigh_l", "thigh_r", rec["hip"], func(t: float) -> void: _set_pelvis_twist(B, t), -85.0, 85.0)
		var pk := _pick_side(hs, (B.ang["pelvis"] as Vector3).z, int(force.get("hip", 0)))
		_set_pelvis_twist(B, pk["t"])
		B.fk()
		rep["hip_yaw"] = pk["t"]
		if pk["ambiguous"]:
			rep["flips"]["hip"] = {"kind": "hip", "side": pk["side"]}
	if (rec["shoulder"] as Array).size() >= 2:
		var ss := _twist_scan(B, cam, "upperarm_l", "upperarm_r", rec["shoulder"], func(t: float) -> void: _set_spine_twist(B, t), -51.0, 51.0)
		var pk2 := _pick_side(ss, _spine_twist(B), int(force.get("sh", 0)))
		_set_spine_twist(B, pk2["t"])
		B.fk()
		rep["chest_twist"] = _spine_twist(B)
		if pk2["ambiguous"]:
			rep["flips"]["sh"] = {"kind": "sh", "side": pk2["side"]}
	var spine_px := (spine[0] as Vector2).distance_to(spine[spine.size() - 1])
	var min_side := 0.08 * spine_px
	var drawn := {}
	for grp in ["arms", "legs"]:
		var ends: Dictionary = {}
		var tips := {"_l": ("hand_l" if grp == "arms" else "foot_l"), "_r": ("hand_r" if grp == "arms" else "foot_r")}
		var ct := {"_l": cur_px[tips["_l"]], "_r": cur_px[tips["_r"]]}
		var a := assign(rec[grp], ct, side_dx[grp], (spine[0] as Vector2).x if grp == "arms" else (spine[spine.size() - 1] as Vector2).x, S, min_side)
		for sd in ["_l", "_r"]:
			var limb = a[sd]
			var tip: String = tips[sd]
			if limb == null:
				rep["kept"].append(tip)
				continue
			var mid: String = B.parent[tip]
			var root: String = B.parent[mid]
			var wr: Vector2 = limb["tip"]
			var el: Vector2
			if limb["corner"] != null:
				el = limb["corner"]
			else:
				var u: float = ((B.p0[mid] - B.p0[root]) as Vector3).length()
				var f: float = ((B.p0[tip] - B.p0[mid]) as Vector3).length()
				var sh := cam.unproject_position(B.P[root])
				el = sh + (wr - sh) * (u / (u + f))
			drawn[tip] = {"el": el, "wr": wr}
	# arms: each on its own; legs: together when the pick is ambiguous (the balance decides)
	var cands := {}
	var prior := library_prior(B, cam, drawn, S)
	rep["prior"] = prior.keys()
	for tip in drawn:
		cands[tip] = limb_cands(B, cam, tip, drawn[tip]["el"], drawn[tip]["wr"], S, hint[tip], rot[tip], prior.get(tip, []))
	var chosen_all := {}
	for tip in ["hand_l", "hand_r"]:
		if cands.has(tip):
			_put(B, tip, cands[tip][0])
			chosen_all[tip] = cands[tip][0]
			rep["limbs"][tip] = {"cost": cands[tip][0]["cost"], "clamped": cands[tip][0]["clamped"], "ambiguous": cands[tip].size() > 1 and float(cands[tip][1]["cost"]) - float(cands[tip][0]["cost"]) < AMBIG}
	var lt := []
	for tip in ["foot_l", "foot_r"]:
		if cands.has(tip):
			lt.append(tip)
	var pick := {}
	for tip in lt:
		var ok_c := []
		for c in cands[tip]:
			if float(c["cost"]) - float(cands[tip][0]["cost"]) < AMBIG and ok_c.size() < 2:
				ok_c.append(c)
		pick[tip] = ok_c
	var amb := false
	for tip in lt:
		if (pick[tip] as Array).size() > 1:
			amb = true
	var chosen := {}
	if not amb:
		for tip in lt:
			chosen[tip] = pick[tip][0]
	else:
		var bestc := INF
		var combos := [{}]
		for tip in lt:
			var nxt := []
			for cb in combos:
				for c in pick[tip]:
					var d: Dictionary = (cb as Dictionary).duplicate()
					d[tip] = c
					nxt.append(d)
			combos = nxt
		for cb in combos:
			var tot := 0.0
			for tip in lt:
				_put(B, tip, cb[tip])
				tot += float(cb[tip]["cost"])
			tot += _balance_pen(B)
			if tot < bestc:
				bestc = tot
				chosen = cb
		rep["balance_used"] = true
	for tip in lt:
		_put(B, tip, chosen[tip])
		chosen_all[tip] = chosen[tip]
		rep["limbs"][tip] = {"cost": chosen[tip]["cost"], "clamped": chosen[tip]["clamped"], "ambiguous": (pick[tip] as Array).size() > 1}
	if not lt.is_empty():
		_stand_on_floor(B, lt)
	for tip in chosen_all:
		var al := _alts(chosen_all[tip], cands[tip])
		if al.size() > 1:
			rep["flips"][tip] = {"kind": "limb", "tip": tip, "at": B.parent[tip], "cands": al, "i": 0}
	rep["skeleton"] = _skel(B, cam)
	rep["ms"] = float(Time.get_ticks_usec() - t0) / 1000.0
	return rep
