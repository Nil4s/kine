## VIDEO RETARGET (round: GMR-style two-stage IK for the video import; docs/research/ROBOT_MOTION.md section 4 item 2).
## The tracked person's 33 landmarks -> OUR skeleton's joint angles. The recipe is GMR's, "Retargeting Matters: General
## Motion Retargeting for Humanoid Motion Tracking", Araujo, Ze, Xu, Wu, Liu, arXiv:2510.02252 (code MIT, github.com/YanjieZe/GMR;
## read: the paper's method section and the README / DOC.md; NO code of it is used, this file is our own). What I took from it:
##   1 NON-UNIFORM LOCAL SCALING: the source is scaled to the target body per SEGMENT (the paper gives each key body its own
##     s_b; the numbers are not published, so ours are measured: our bone length over the median length of that bone in the
##     clip). The tracked person's arms and legs are not ours, so a global scale puts a wrist where our arm cannot reach.
##   2 STAGE 1: differential IK on ORIENTATIONS of the key bodies (pelvis, chest, head) + POSITIONS of the end effectors only
##     (wrists, ankles, toes, heels), under the joint limits. The paper: minimise |e + J dq|_W subject to q- <= q + dq <= q+,
##     initialised from the previous frame, stopped when the objective changes by < 0.001 or after 10 iterations. We take
##     those two stopping numbers as they are. DOC.md's example weights (position 100, rotation 10) are the starting weights.
##   3 STAGE 2: the stage-1 answer is refined with the position terms on EVERY key body (shoulders, elbows, knees too).
##   4 SEQUENCE: every frame starts from the last frame's answer; velocity limits on (GMR's class defaults to 3 pi rad/s on
##     a robot; a person is faster, so ours are the in-sport peaks of docs/research/HUMAN_LIMITS.md, per joint, below).
## What is OURS and differs: (a) the solver is a damped least squares (Levenberg-Marquardt) step with the limits applied by
## PROJECTION (clamp after each step, a step that raises the objective is undone), not mink's QP; the unknowns are one world
## rotation per joint, so a joint's three angles (bend, side, twist) are never differentiated. (b) A joint no target pins
## (an arm straight out has no elbow plane, a thigh's twist) keeps its last frame's value through the damping, where the
## geometric fit (VideoImport.fit) picks a shortest arc that can flip. (c) The root has no data: MediaPipe's hips are at 0, so
## the travel is rebuilt from FOOT CONTACT: a planted foot is pinned to the spot it landed on (GMR's last step instead lowers
## the sequence by the lowest body so nothing floats or sinks; Body.ground does that here).
## Input: VideoImport.parse's frames [{"t", "w": 33 Vector3, our axes, hips' midpoint at 0}] after VideoImport.level.
## Output: the form VideoImport.solve returns: [{"t", "ang": {joint: Vector3(bend, side, twist)}, "offset": Vector3}].
## Not done: a held weapon and the hands' fingers (a clip with "hands" or opts "held") go to VideoImport.solve unchanged.
class_name VideoRetarget
extends RefCounted

const VARS := ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head", "clavicle_l", "upperarm_l", "lowerarm_l",
	"clavicle_r", "upperarm_r", "lowerarm_r", "thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"]
const W_EE := 100.0      # position weight of a hand / foot target (GMR DOC.md's example: 100)
const W_KEY := 50.0      # position weight of the other key bodies, stage 2 only
const W_ROT1 := 10.0     # orientation weight in stage 1 (GMR DOC.md's example: 10)
const W_ROT2 := 3.0      # and in stage 2: the positions lead
const ITERS := 10        # GMR: at most 10 iterations per stage
const STOP := 0.001      # GMR: stop when the objective changes by less than this (relative here: ours is in metres and radians)
const MAXSTEP := 0.35    # rad: the largest turn one joint makes in one iteration
const FLOOR_H := 0.035   # m: a sole this near the lower sole is down
const RESEED_MISS := 0.08   # m: a key point this far off after both stages: try the geometric fit as the start too
const BAND := 0.06       # trunk / shoulder scale dead band (see scales)
const EXT_R := 0.05      # m: a contact grows over neighbouring frames while the foot stays this near the contact's spot (and low)
const EXT_STEP := 0.012   # m per frame: and moving slower than PLANT_V (0.4 m/s at 30 fps) to the frame it grows from
const BLEND := 0         # frames: after a release the foot is pulled back toward its anchor by 3/4, 2/4, 1/4 (no pop at the toe-off)
const PLANT_V := 0.4     # m/s: a planted foot's middle moves slower than this (over +-2 frames, in the rebuilt world)
const PLANT_MIN := 3     # frames: a shorter run is a tap, not a contact
const TRIM_OFF := 0      # frames cut off the end of a contact (the toe-off: the foot is already rolling)
## deg/s per joint, the in-sport PEAKS of docs/research/HUMAN_LIMITS.md (the WARN column): shoulder 6520 (Fortenbaugh, Fleisig &
## Andrews 2009), trunk 1120 (same), knee 1874 (Manolopoulos 2006), elbow 2210 (Fortenbaugh 2009). A joint with no verified peak
## takes VEL_DEFAULT = the knee's (MINE: the largest verified distal-segment figure, not a measured limit for that joint)
const VEL := {"upperarm": 6520.0, "spine": 1120.0, "pelvis": 1120.0, "calf": 1874.0, "lowerarm": 2210.0}
const VEL_DEFAULT := 1874.0

## the key bodies as [landmark, joint, kind, weight]; kind 0 = the joint's point, 1 = its end point, 2 = the heel (on the foot)
static var _pts := []
static var _movers := {}


static func vel_cap(j: String) -> float:
	for k in VEL:
		if j.begins_with(k):
			return VEL[k]
	return VEL_DEFAULT


static func _init_tables() -> void:
	if not _pts.is_empty():
		return
	for sd in ["_l", "_r"]:
		_pts.append([VideoImport.SH[sd], "upperarm" + sd, 0, W_KEY])
		_pts.append([VideoImport.EL[sd], "lowerarm" + sd, 0, W_KEY])
		_pts.append([VideoImport.WR[sd], "hand" + sd, 0, W_EE])
		_pts.append([VideoImport.KN[sd], "calf" + sd, 0, W_KEY])
		_pts.append([VideoImport.AN[sd], "foot" + sd, 0, W_EE])
		_pts.append([VideoImport.TOE[sd], "ball" + sd, 1, W_EE])
		_pts.append([VideoImport.HEEL[sd], "foot" + sd, 2, W_EE])


## the unknowns (indices in VARS) that move a thing riding on joint j: its ancestors, and j itself when `self_too`
static func _movers_of(B: Body, j: String, self_too: bool) -> Array:
	var key := "%s|%s" % [j, self_too]
	if _movers.has(key):
		return _movers[key]
	var out := []
	var c: String = j if self_too else B.parent[j]
	while c != "":
		var i := VARS.find(c)
		if i >= 0:
			out.append(i)
		c = B.parent[c]
	_movers[key] = out
	return out


static func _median(a: Array, q := 0.5) -> float:
	var s := a.duplicate()
	s.sort()
	return s[int(q * (s.size() - 1))]


## each segment's scale: our bone length / the median of that bone in the clip (GMR's s_b, measured)
static func scales(B: Body, frames: Array) -> Dictionary:
	var p0: Dictionary = B.p0
	var S := {}
	var mine := {"hipw": ((p0["thigh_l"] as Vector3) - (p0["thigh_r"] as Vector3)).length(),
		"shw": ((p0["upperarm_l"] as Vector3) - (p0["upperarm_r"] as Vector3)).length(),
		"trunk": (((p0["upperarm_l"] as Vector3) + (p0["upperarm_r"] as Vector3)) * 0.5 - ((p0["thigh_l"] as Vector3) + (p0["thigh_r"] as Vector3)) * 0.5).length()}
	var lm := {"hipw": [23, 24], "shw": [11, 12]}
	for sd in ["_l", "_r"]:
		mine["ua" + sd] = ((p0["lowerarm" + sd] as Vector3) - (p0["upperarm" + sd] as Vector3)).length()
		mine["fa" + sd] = ((p0["hand" + sd] as Vector3) - (p0["lowerarm" + sd] as Vector3)).length()
		mine["th" + sd] = ((p0["calf" + sd] as Vector3) - (p0["thigh" + sd] as Vector3)).length()
		mine["sh" + sd] = ((p0["foot" + sd] as Vector3) - (p0["calf" + sd] as Vector3)).length()
		mine["ft" + sd] = ((B.e0["ball" + sd] as Vector3) - (p0["foot" + sd] as Vector3)).length()
		lm["ua" + sd] = [VideoImport.SH[sd], VideoImport.EL[sd]]
		lm["fa" + sd] = [VideoImport.EL[sd], VideoImport.WR[sd]]
		lm["th" + sd] = [VideoImport.HIP[sd], VideoImport.KN[sd]]
		lm["sh" + sd] = [VideoImport.KN[sd], VideoImport.AN[sd]]
		lm["ft" + sd] = [VideoImport.AN[sd], VideoImport.TOE[sd]]
	for k in lm:
		var ls := []
		for f in frames:
			var w: Array = f["w"]
			ls.append(((w[lm[k][0]] as Vector3) - (w[lm[k][1]] as Vector3)).length())
		# the shoulder line is not rigid (the clavicles move): its 90th percentile, the clip's most open posture, is nearest the rest
		S[k] = float(mine[k]) / maxf(_median(ls, 0.9 if k == "shw" else 0.5), 1e-6)
	var ts := []
	for f in frames:
		var w: Array = f["w"]
		ts.append((((w[11] as Vector3) + (w[12] as Vector3)) * 0.5 - ((w[23] as Vector3) + (w[24] as Vector3)) * 0.5).length())
	# the chord hips -> shoulders shortens as the spine bends: the 90th percentile (the most upright frames), not the median
	S["trunk"] = float(mine["trunk"]) / maxf(_median(ts, 0.9), 1e-6)
	# the trunk's chord and the shoulder line change with posture (the spine bends, the clavicles move), so their ratio carries
	# the posture as well as the person: inside +-BAND of 1 it is taken as posture and not scaled (measured: our own walk_bat
	# reads 1.033 and 0.973 against itself)
	for k in ["trunk", "shw"]:
		if absf(float(S[k]) - 1.0) < BAND:
			S[k] = 1.0
	return S


## one frame's landmarks rebuilt at OUR proportions, the hips' midpoint at 0: every segment keeps its DIRECTION and takes our
## length, chained from the hips (GMR's p_target = s_b (p_j - p_root), applied along the chain so the limb joins up)
static func scale_frame(w: Array, S: Dictionary) -> Array:
	var o := w.duplicate()
	var hm: Vector3 = ((w[23] as Vector3) + (w[24] as Vector3)) * 0.5
	var sm0: Vector3 = ((w[11] as Vector3) + (w[12] as Vector3)) * 0.5
	var sm: Vector3 = (sm0 - hm) * float(S["trunk"])
	o[23] = ((w[23] as Vector3) - hm) * float(S["hipw"])
	o[24] = ((w[24] as Vector3) - hm) * float(S["hipw"])
	o[11] = sm + ((w[11] as Vector3) - sm0) * float(S["shw"])
	o[12] = sm + ((w[12] as Vector3) - sm0) * float(S["shw"])
	for sd in ["_l", "_r"]:
		var SH: int = VideoImport.SH[sd]
		var EL: int = VideoImport.EL[sd]
		var WR: int = VideoImport.WR[sd]
		var HP: int = VideoImport.HIP[sd]
		var KN: int = VideoImport.KN[sd]
		var AN: int = VideoImport.AN[sd]
		o[EL] = (o[SH] as Vector3) + ((w[EL] as Vector3) - (w[SH] as Vector3)) * float(S["ua" + sd])
		o[WR] = (o[EL] as Vector3) + ((w[WR] as Vector3) - (w[EL] as Vector3)) * float(S["fa" + sd])
		o[KN] = (o[HP] as Vector3) + ((w[KN] as Vector3) - (w[HP] as Vector3)) * float(S["th" + sd])
		o[AN] = (o[KN] as Vector3) + ((w[AN] as Vector3) - (w[KN] as Vector3)) * float(S["sh" + sd])
		for k in [VideoImport.TOE[sd], VideoImport.HEEL[sd]]:
			o[k] = (o[AN] as Vector3) + ((w[k] as Vector3) - (w[AN] as Vector3)) * float(S["ft" + sd])
	for k in [0, 7, 8]:
		o[k] = sm + ((w[k] as Vector3) - sm0) * float(S["trunk"])
	return o


static func _rv(q: Quaternion) -> Vector3:
	q = q.normalized()
	if q.w < 0.0:
		q = Quaternion(-q.x, -q.y, -q.z, -q.w)
	var v := Vector3(q.x, q.y, q.z)
	var l := v.length()
	return v / l * (2.0 * atan2(l, q.w)) if l > 1e-12 else Vector3.ZERO


static func _exp(v: Vector3) -> Quaternion:
	var n := v.length()
	return Quaternion(v / n, n) if n > 1e-12 else Quaternion.IDENTITY


static func _pos(B: Body, p: Array) -> Vector3:
	match int(p[2]):
		0:
			return B.P[p[1]]
		1:
			return B.E[p[1]]
	return VideoImport.heel(B, String(p[1]).right(2))


## the orientation targets of one frame (scaled landmarks): the same frames VideoImport.fit builds, as WORLD rotations
static func orient_targets(B: Body, w: Array) -> Dictionary:
	var up: Vector3 = ((w[11] as Vector3) + (w[12] as Vector3)) * 0.5
	var r_hip: Vector3 = (B.p0["thigh_l"] as Vector3) - (B.p0["thigh_r"] as Vector3)
	var r_sh: Vector3 = (B.p0["upperarm_l"] as Vector3) - (B.p0["upperarm_r"] as Vector3)
	var r_up: Vector3 = ((B.p0["upperarm_l"] as Vector3) + (B.p0["upperarm_r"] as Vector3)) * 0.5 - ((B.p0["thigh_l"] as Vector3) + (B.p0["thigh_r"] as Vector3)) * 0.5
	up = up - ((w[23] as Vector3) + (w[24] as Vector3)) * 0.5
	var T := {}
	T["pelvis"] = VideoImport._quat(VideoImport._frame((w[23] as Vector3) - (w[24] as Vector3), up) * VideoImport._frame(r_hip, r_up).inverse())
	T["spine_03"] = VideoImport._quat(VideoImport._frame((w[11] as Vector3) - (w[12] as Vector3), up) * VideoImport._frame(r_sh, r_up).inverse())
	var em: Vector3 = ((w[7] as Vector3) + (w[8] as Vector3)) * 0.5
	var fw: Vector3 = (w[0] as Vector3) - em
	if fw.length() > 1e-6 and up.length() > 1e-6:
		var B0p: Vector3 = B.p0["head"]
		var e0 := B0p + ((B.e0["head"] as Vector3) - B0p) * VideoImport.EAR0.y
		var n0 := B0p + ((B.e0["head"] as Vector3) - B0p) * VideoImport.NOSE0.y + Vector3(0.0, 0.0, VideoImport.NOSE0.z)
		T["head"] = VideoImport._quat(VideoImport._frame(up, fw) * VideoImport._frame(r_up, n0 - e0).inverse())
	return T


## cost and the normal equations of one stage at the body's present pose. Residuals: key points (relative to the hips'
## midpoint, minus the target) and key orientations (minus the target). Returns [cost, H, g]
static func _linearize(B: Body, tw: Array, rt: Dictionary, stage: int) -> Array:
	var n := VARS.size() * 3
	var H := PackedFloat64Array()
	H.resize(n * n)
	var g := PackedFloat64Array()
	g.resize(n)
	var cost := 0.0
	var hm: Vector3 = ((B.P["thigh_l"] as Vector3) + (B.P["thigh_r"] as Vector3)) * 0.5
	for p in _pts:
		var wt: float = p[3]
		if stage == 1 and wt < W_EE:
			continue
		var pp := _pos(B, p)
		var e: Vector3 = (pp - hm) - (tw[p[0]] as Vector3)
		var w2 := wt * wt
		cost += w2 * e.length_squared()
		var mv: Array = _movers_of(B, p[1], int(p[2]) != 0)
		for c in 3:
			var idx := PackedInt32Array()
			var val := PackedFloat64Array()
			for a in mv:
				var ja: String = VARS[a]
				var d: Vector3 = pp - (hm if ja == "pelvis" else (B.P[ja] as Vector3))
				var row: Vector3 = [Vector3(0.0, d.z, -d.y), Vector3(-d.z, 0.0, d.x), Vector3(d.y, -d.x, 0.0)][c]
				idx.append(a * 3)
				idx.append(a * 3 + 1)
				idx.append(a * 3 + 2)
				val.append(row.x)
				val.append(row.y)
				val.append(row.z)
			_acc(H, g, n, idx, val, w2, e[c])
	var wr := W_ROT1 if stage == 1 else W_ROT2
	for j in rt:
		var w2r := wr * wr * (0.25 if j == "head" else 1.0)
		var er := -_rv((rt[j] as Quaternion) * (B.G[j] as Quaternion).inverse())
		cost += w2r * er.length_squared()
		var mvr: Array = _movers_of(B, j, true)
		for c in 3:
			var idx := PackedInt32Array()
			var val := PackedFloat64Array()
			for a in mvr:
				idx.append(a * 3 + c)
				val.append(1.0)
			_acc(H, g, n, idx, val, w2r, er[c])
	return [cost, H, g]


static func _acc(H: PackedFloat64Array, g: PackedFloat64Array, n: int, idx: PackedInt32Array, val: PackedFloat64Array, w2: float, r: float) -> void:
	for a in idx.size():
		var va := val[a] * w2
		if va == 0.0:
			continue
		g[idx[a]] += va * r
		var base := idx[a] * n
		for b in idx.size():
			H[base + idx[b]] += va * val[b]


## solve (H + damping) x = -g by Cholesky; returns x (zeros if the factorisation fails)
static func _solve_ls(H: PackedFloat64Array, g: PackedFloat64Array, n: int) -> PackedFloat64Array:
	var tr := 0.0
	for i in n:
		tr += H[i * n + i]
	var lam := 1e-3 * tr / n + 1e-2
	var L := PackedFloat64Array()
	L.resize(n * n)
	for i in n:
		for j in i + 1:
			var s := H[i * n + j] + (lam if i == j else 0.0)
			for k in j:
				s -= L[i * n + k] * L[j * n + k]
			if i == j:
				if s <= 1e-12:
					var z := PackedFloat64Array()
					z.resize(n)
					return z
				L[i * n + i] = sqrt(s)
			else:
				L[i * n + j] = s / L[j * n + j]
	var y := PackedFloat64Array()
	y.resize(n)
	for i in n:
		var s := -g[i]
		for k in i:
			s -= L[i * n + k] * y[k]
		y[i] = s / L[i * n + i]
	var x := PackedFloat64Array()
	x.resize(n)
	for i in range(n - 1, -1, -1):
		var s := y[i]
		for k in range(i + 1, n):
			s -= L[k * n + i] * x[k]
		x[i] = s / L[i * n + i]
	return x


## apply the joints' world turns, parents first. Each joint keeps its local angles but for the turn; the result goes
## through (bend, side, twist) and the body's limits, so the limits hold EXACTLY after every step (projection)
static func _apply(B: Body, x: PackedFloat64Array) -> void:
	var Gn := {}
	for i in VARS.size():
		var j: String = VARS[i]
		var pj: String = B.parent[j]
		var gp_old: Quaternion = B.G[pj] if pj != "" else Quaternion.IDENTITY
		var gp_new: Quaternion = Gn[pj] if Gn.has(pj) else gp_old
		var v := Vector3(x[i * 3], x[i * 3 + 1], x[i * 3 + 2])
		if v.length() > MAXSTEP:
			v = v.normalized() * MAXSTEP
		var A_new := gp_old.inverse() * _exp(v) * gp_old * B.compose(j, B.ang[j])   # turn_world's rule: the OLD parent frame
		var a: Vector3 = B.clamp_ang(j, B.decompose(j, A_new.normalized()))
		B.ang[j] = a
		Gn[j] = gp_new * B.compose(j, a)
	B.fk()


static func _snapshot(B: Body) -> Dictionary:
	var s := {}
	for j in VARS:
		s[j] = B.ang[j]
	return s


static func _restore(B: Body, s: Dictionary) -> void:
	for j in s:
		B.ang[j] = s[j]
	B.fk()


## one stage: iterate to GMR's stop. Returns the final objective
static func _stage(B: Body, tw: Array, rt: Dictionary, stage: int) -> float:
	var n := VARS.size() * 3
	var prev := INF
	var snap := {}
	var c := 0.0
	for it in ITERS + 1:
		var L := _linearize(B, tw, rt, stage)
		c = L[0]
		if it > 0:
			if c > prev:
				_restore(B, snap)
				return prev
			if prev - c < STOP * maxf(prev, 1e-6):
				return c
		if it == ITERS:
			break
		prev = c
		snap = _snapshot(B)
		_apply(B, _solve_ls(L[1], L[2], n))
	return c


## stage 1 then stage 2 on one frame, from the body's present pose
static func _frame_ik(B: Body, tw: Array, rt: Dictionary) -> float:
	_stage(B, tw, rt, 1)
	return _stage(B, tw, rt, 2)


## largest key-point miss (m) of the body against the scaled landmarks, hips' midpoint to hips' midpoint
static func _miss(B: Body, tw: Array) -> float:
	var hm: Vector3 = ((B.P["thigh_l"] as Vector3) + (B.P["thigh_r"] as Vector3)) * 0.5
	var m := 0.0
	for p in _pts:
		m = maxf(m, ((_pos(B, p) - hm) - (tw[p[0]] as Vector3)).length())
	return m


## the velocity limit: no joint turns faster than its cap between two frames (slerp back along the turn); `prev` is last
## frame's angles
static func limit_velocity(B: Body, prev: Dictionary, dt: float) -> int:
	var hit := 0
	for j in Body.BODY:
		var q0 := B.compose(j, prev[j])
		var q1 := B.compose(j, B.ang[j])
		var turn := q0.angle_to(q1)
		var cap := deg_to_rad(vel_cap(j)) * dt * 0.98
		if turn > cap:
			B.ang[j] = B.clamp_ang(j, B.decompose(j, q0.slerp(q1, cap / turn).normalized()))
			hit += 1
	if hit > 0:
		B.fk()
	return hit


## the travel with NO contact knowledge, VideoImport.solve's rule: each foot has two pivots (the heel's back, the ball: people
## roll over the heel, then the toes); the foot nearer ITS OWN floor (the 10th percentile of its lower pivot over the clip,
## so a leg the tracker holds too bent is judged against itself) is the stance foot, and the hips move opposite to the pivot
## it rolls over. pivs[i][sd] = [heel, ball]. Returns [per-frame hips offset (x, z), per-frame {side: height above its floor}]
static func stance_travel(pivs: Array) -> Array:
	var n := pivs.size()
	var floor := {}
	for sd in ["_l", "_r"]:
		var hs := []
		for pv in pivs:
			hs.append(minf((pv[sd][0] as Vector3).y, (pv[sd][1] as Vector3).y))
		hs.sort()
		floor[sd] = hs[int(0.1 * (hs.size() - 1))]
	var hts := []
	for pv in pivs:
		var h := {}
		for sd in ["_l", "_r"]:
			h[sd] = minf((pv[sd][0] as Vector3).y, (pv[sd][1] as Vector3).y) - float(floor[sd])
		hts.append(h)
	var out := [Vector3.ZERO]
	var root := Vector3.ZERO
	for i in range(1, n):
		var lo := {}
		for sd in ["_l", "_r"]:
			lo[sd] = float(hts[i][sd]) + float(hts[i - 1][sd])
		var st := "_l" if float(lo["_l"]) <= float(lo["_r"]) else "_r"
		var c: Array = pivs[i][st]
		var p: Array = pivs[i - 1][st]
		var k2 := 0 if (c[0] as Vector3).y + (p[0] as Vector3).y <= (c[1] as Vector3).y + (p[1] as Vector3).y else 1
		var mv: Vector3 = (c[k2] as Vector3) - (p[k2] as Vector3)
		root -= Vector3(mv.x, 0.0, mv.z)
		out.append(root)
	return [out, hts]


## CONTACTS: per frame {"_l": bool, "_r": bool}. A foot is down when its sole is within FLOOR_H of the lower sole AND its middle
## moves under PLANT_V in the world the stance rule rebuilt (its height is above the foot's own floor), for PLANT_MIN frames or more. (VideoCleanup.detect reads the speed
## against the HIPS: for a walk, with the hips pinned at 0 by the tracker, the stance foot slides back at walking speed, so on
## walk_bat it finds only the standing frames at both ends. Height alone calls a foot rolling over its toes planted.)
static func contacts(mids: Array, heights: Array, tr: Array, fps: float) -> Array:
	var n := heights.size()
	var out := []
	for i in n:
		out.append({"_l": false, "_r": false})
	for sd in ["_l", "_r"]:
		var down := []
		for i in n:
			var a := maxi(i - 2, 0)
			var b := mini(i + 2, n - 1)
			var pa: Vector3 = (mids[a][sd] as Vector3) + (tr[a] as Vector3)
			var pb: Vector3 = (mids[b][sd] as Vector3) + (tr[b] as Vector3)
			var v := Vector2(pb.x - pa.x, pb.z - pa.z).length() * fps / maxf(b - a, 1)
			down.append(float(heights[i][sd]) < FLOOR_H and v < PLANT_V)
		var i := 0
		while i < n:
			if not down[i]:
				i += 1
				continue
			var a := i
			while i < n and down[i]:
				i += 1
			var b := i - 1 - (TRIM_OFF if i < n else 0)
			if b - a + 1 >= PLANT_MIN:
				for k in range(a, b + 1):
					out[k][sd] = true
	return out


## VideoIQ.contacts' per-foot flags as this file's per-frame {"_l": bool, "_r": bool}
static func contacts_from_iq(K: Dictionary, n: int) -> Array:
	var out := []
	for i in n:
		out.append({"_l": bool(K["flags"]["_l"][i]), "_r": bool(K["flags"]["_r"][i])})
	return out


## grow each contact run over the frames either side where the foot has not left its spot: the detector (VideoIQ.contacts, on
## 1.5 cm noisy landmarks) drops the first / last frames of a plant and splits some in two (measured on combo3: 7 of 12 true
## contact runs only partly covered), and a frame it drops slides. W[i][sd] = the foot's middle in the rebuilt world, h = its height
static func _step(W: Array, sd: String, a: int, b: int) -> float:
	var d: Vector3 = (W[a][sd] as Vector3) - (W[b][sd] as Vector3)
	return Vector2(d.x, d.z).length()


static func extend_contacts(ct: Array, W: Array, heights: Array) -> int:
	var n := ct.size()
	var grown := 0
	for sd in ["_l", "_r"]:
		var i := 0
		while i < n:
			if not ct[i][sd]:
				i += 1
				continue
			var a := i
			while i < n and ct[i][sd]:
				i += 1
			var b := i - 1
			var xs := []
			var zs := []
			for k in range(a, b + 1):
				xs.append((W[k][sd] as Vector3).x)
				zs.append((W[k][sd] as Vector3).z)
			var ref := Vector2(_median(xs), _median(zs))
			var k := b + 1
			while k < n and not ct[k][sd] and float(heights[k][sd]) < 2.0 * FLOOR_H and Vector2((W[k][sd] as Vector3).x, (W[k][sd] as Vector3).z).distance_to(ref) < EXT_R and _step(W, sd, k, k - 1) < EXT_STEP:
				ct[k][sd] = true
				grown += 1
				k += 1
			i = maxi(i, k)
			k = a - 1
			while k >= 0 and not ct[k][sd] and float(heights[k][sd]) < 2.0 * FLOOR_H and Vector2((W[k][sd] as Vector3).x, (W[k][sd] as Vector3).z).distance_to(ref) < EXT_R and _step(W, sd, k, k + 1) < EXT_STEP:
				ct[k][sd] = true
				grown += 1
				k -= 1
	return grown


## where the contact run starting at (or holding) frame i sits, as an offset from frame i's own spot: the MEDIAN of the run's
## world spots (rebuilt, no anchors) less frame i's. The anchor is the run's centre, not the first frame's noisy landing
static func _run_centre(ct: Array, W: Array, sd: String, i: int) -> Vector3:
	var b := i
	while b + 1 < ct.size() and ct[b + 1][sd]:
		b += 1
	var xs := []
	var zs := []
	for k in range(i, b + 1):
		xs.append((W[k][sd] as Vector3).x)
		zs.append((W[k][sd] as Vector3).z)
	return Vector3(_median(xs) - (W[i][sd] as Vector3).x, 0.0, _median(zs) - (W[i][sd] as Vector3).z)


static func solve(frames: Array, B: Body, opts := {}) -> Array:
	_init_tables()
	var held: String = opts.get("held", "")
	for f in frames:
		if (f as Dictionary).has("hands"):
			return VideoImport.solve(B, frames, held, float(opts.get("fps", 30.0)), {}, opts.get("fly", {}))
	if held != "":
		return VideoImport.solve(B, frames, held, float(opts.get("fps", 30.0)), {}, opts.get("fly", {}))
	var n := frames.size()
	if n == 0:
		return []
	var fps: float = opts.get("fps", 30.0)
	var src: Array = VideoCleanup.smooth(frames, fps) if opts.get("smooth", true) else frames
	var S := scales(B, src)
	var rep: Dictionary = opts.get("report", {})
	rep["scales"] = S
	rep["reseeds"] = 0
	rep["vel_hits"] = 0
	var was := B.fast
	var poses := []
	var mids := []
	var pivs := []
	var prev := {}
	for i in n:
		if VideoIQ.cancelled():   # R13: the import runs on a worker; Cancel / quit ends it at the next frame
			B.fast = was
			return []
		VideoIQ.progress = 0.2 + 0.5 * float(i) / float(n)
		var w := scale_frame(src[i]["w"], S)
		var tw := w
		var rt := orient_targets(B, w)
		if i == 0:
			VideoImport.fit(B, w)
		else:
			B.offset = Vector3.ZERO
		B.fk()
		var c1 := _frame_ik(B, tw, rt)
		if _miss(B, tw) > RESEED_MISS:   # a fast swing from a stale start can sit in a wrong basin: seed this frame as the first, keep the better
			var keep := _snapshot(B)
			VideoImport.fit(B, w)
			B.fk()
			var c2 := _frame_ik(B, tw, rt)
			if c2 < c1:
				rep["reseeds"] += 1
			else:
				_restore(B, keep)
		if i > 0:
			var dt := maxf(float(src[i]["t"]) - float(src[i - 1]["t"]), 1e-3)
			rep["vel_hits"] += limit_velocity(B, prev, dt)
		var a := {}
		for j in Body.BODY:
			a[j] = B.ang[j]
		prev = a
		poses.append(a)
		var m := {}
		var pv := {}
		for sd in ["_l", "_r"]:
			m[sd] = (VideoImport.heel(B, sd) + (B.E["ball" + sd] as Vector3)) * 0.5
			pv[sd] = [VideoImport.heel(B, sd), B.P["ball" + sd]]
		mids.append(m)
		pivs.append(pv)
	B.fast = was
	var st := stance_travel(pivs)
	var tr: Array = st[0]
	var heights: Array = st[1]
	var ct: Array = opts.get("contacts", contacts(mids, heights, tr, fps))
	if opts.has("iq"):   # VideoIQ.contacts' verdict (confidence-aware, per-foot ground) replaces the geometric one
		ct = contacts_from_iq(opts["iq"], n)
	var W := []
	for i in n:
		W.append({"_l": (mids[i]["_l"] as Vector3) + (tr[i] as Vector3), "_r": (mids[i]["_r"] as Vector3) + (tr[i] as Vector3)})
	rep["grown"] = extend_contacts(ct, W, heights)
	rep["contacts"] = ct
	# the travel: a planted foot is pinned to where it landed (absolute anchor, so a long contact cannot creep); no foot down:
	# the lower foot is the stance foot and stays where it was (VideoImport.solve's rule)
	var out := []
	var root := Vector3.ZERO
	var anchor := {}
	var fade := {}   # sd -> [anchor, frames since the release]
	var vlast := {}  # VideoIQ.vertical: the last grounded height (a flight keeps its rise from there)
	var fly: Dictionary = opts.get("fly", {})
	for i in n:
		if i > 0:
			var rs := []
			for sd in ["_l", "_r"]:
				if ct[i][sd] and ct[i - 1][sd] and anchor.has(sd):
					var r: Vector3 = (anchor[sd] as Vector3) - (mids[i][sd] as Vector3)
					rs.append(Vector3(r.x, 0.0, r.z))
			if rs.is_empty():
				root += (tr[i] as Vector3) - (tr[i - 1] as Vector3)
			else:
				var s := Vector3.ZERO
				for r in rs:
					s += r
				root = s / rs.size()
		for sd in ["_l", "_r"]:
			if ct[i][sd]:
				if not (i > 0 and ct[i - 1][sd]) or not anchor.has(sd):
					anchor[sd] = (mids[i][sd] as Vector3) + root + _run_centre(ct, W, sd, i)
			else:
				if anchor.has(sd):   # a release: the anchor stays for the BLEND frames that ease the foot off it
					fade[sd] = [anchor[sd], 0]
				anchor.erase(sd)
				if fade.has(sd):
					fade[sd][1] += 1
					if int(fade[sd][1]) > BLEND:
						fade.erase(sd)
		for j in poses[i]:
			B.ang[j] = poses[i][j]
		B.offset = root
		B.fk()
		VideoIQ.vertical(B, fly, i, vlast)
		# FOOT LOCK: two planted feet whose spacing the fit did not keep share the miss through the mean root above; each is
		# now put exactly on its anchor by a leg reach (the ankle moves by the middle's miss, limits kept)
		if i > 0:
			B.fast = true
			var moved := false
			for sd in ["_l", "_r"]:
				if ct[i][sd] and ct[i - 1][sd] and anchor.has(sd):
					var now: Vector3 = (VideoImport.heel(B, sd) + (B.E["ball" + sd] as Vector3)) * 0.5
					var miss: Vector3 = (anchor[sd] as Vector3) - now
					miss.y = 0.0
					if miss.length() > 0.001:
						B.reach("foot" + sd, (B.P["foot" + sd] as Vector3) + miss)
						moved = true
			for sd in fade:   # the release: 3/4, 2/4, 1/4 of the way back to the anchor, so the toe-off does not pop
				var wgt: float = 1.0 - float(fade[sd][1]) / float(BLEND + 1)
				var nowf: Vector3 = (VideoImport.heel(B, sd) + (B.E["ball" + sd] as Vector3)) * 0.5
				var missf: Vector3 = ((fade[sd][0] as Vector3) - nowf) * wgt
				missf.y = 0.0
				if missf.length() > 0.001:
					B.reach("foot" + sd, (B.P["foot" + sd] as Vector3) + missf)
					moved = true
			B.fast = was
			if moved:
				for j in Body.BODY:
					poses[i][j] = B.ang[j]
		out.append({"t": src[i]["t"], "ang": poses[i], "offset": B.offset, "pinned": ct[i]})
	return out
