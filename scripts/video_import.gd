## VIDEO TO ANIMATION (round 45, GATES AA; docs/ANIM_RESEARCH.md: a phone video in place of 2000 hours of keying).
## Nick 10-18: "start round 45 with video tracing". The TRACKING is MediaPipe PoseLandmarker (a pretrained pose model, run
## OUTSIDE Poser by tools/see_video.py, the game repo's tools/see/pose.py): it writes pose.json, 33 world landmarks per frame
## (metres, the hips' midpoint at 0, y DOWN). Poser only READS that file, the way it reads a BVH: no model is inside the app.
## tools/export_landmarks.gd writes a Poser scene in the same layout, EXACTLY, so the fit is tested on a known answer.
## THE FIT, per frame, from the rest pose, parents before children (Body.fk's order):
##   pelvis    the frame of (hip line right -> left, trunk up = shoulders' midpoint - hips'), from the same pair at rest
##   spine     the turn from that frame to the shoulders' (shoulder line, trunk up), split in thirds over spine_01..03
##   neck/head the shoulders' midpoint -> landmark 0, split in halves over neck_01 and head
##   thigh, upper arm   aimed down the limb with the knee's / elbow's HINGE PLANE (the bend's own plane at rest), so the
##             twist is the limb's, not a shortest arc's; a near-straight limb has no plane: blended to the shortest arc
##   calf, forearm      the hinge's bend only (the angle between the two bones), the sign the joint allows
##   foot      aimed at the foot tip (31 / 32)
##   hands, fingers, clavicles: rest (the 33-point layout has no hand frame), unless the file has hands (ROADMAP 90): then the
##             fingers are fitted by HandImport (each hand on its own frame, so the arm does not enter it); clavicles stay rest
## THE TRAVEL: MediaPipe's hips are always at 0, so a tracked walk walks on the spot. The root is rebuilt from the feet:
## each frame the LOWER foot is the stance foot and stays where it was, the hips move the opposite way (people's stance
## foot does not slide: the same idea as MocapClean's foot lock). The height: the lower sole on the floor (Body.ground).
## Directions only: the tracked person's bone LENGTHS are not ours (no retarget of proportions; the travel scales by them).
class_name VideoImport
extends RefCounted

const STRAIGHT := 8.0    # deg: a limb bent less than this has no hinge plane to read (its twist: the shortest arc)
const PLANE_AT := 20.0   # deg: bent this much or more, the plane alone sets the twist (between: blended)
## the landmarks the fit reads (MediaPipe's numbering)
const NOSE := 0
const SH := {"_l": 11, "_r": 12}
const EL := {"_l": 13, "_r": 14}
const WR := {"_l": 15, "_r": 16}
const HIP := {"_l": 23, "_r": 24}
const KN := {"_l": 25, "_r": 26}
const AN := {"_l": 27, "_r": 28}
const TOE := {"_l": 31, "_r": 32}
const HEEL := {"_l": 29, "_r": 30}
static var LM_W := 1.0   # how much of the lock's pivot is the tracker's landmark (1) rather than the fitted body's foot (0)
const GAP_WIN := 8       # frames: a frame with no foot locked (the hand-over between two feet, a detector's late touchdown: walk_bat's right foot
                         # lands 8 frames before it is found) carries on at the mean root velocity of the last GAP_WIN locked frames ...
const GAP_HOLD := 12     # ... for at most this many frames in a row, then stands (a stop is a stop, not a gap)
const LOCK_JUMP := 0.05   # m: the hips move at most this much in a frame to the locked answer; more is blended halfway
const FOOT_LEN := 0.152   # x standing height: foot length (Drillis & Contini 1966, the segment table in Winter's Biomechanics
                          # and Motor Control of Human Movement): the heel's back is that far behind the toe tip


## the body's own 33 points in MediaPipe's numbering, OUR axes, the hips' midpoint at 0 (tools/export_landmarks.gd's MAP:
## the points it fills; the rest stay 0). What the fit reads back, so a round trip compares like with like
const MAP := {0: ["head", true], 11: ["upperarm_l", false], 12: ["upperarm_r", false], 13: ["lowerarm_l", false],
	14: ["lowerarm_r", false], 15: ["hand_l", false], 16: ["hand_r", false], 23: ["thigh_l", false],
	24: ["thigh_r", false], 25: ["calf_l", false], 26: ["calf_r", false], 27: ["foot_l", false], 28: ["foot_r", false],
	31: ["ball_l", true], 32: ["ball_r", true]}


static func landmarks_of(B: Body) -> Array:
	var hip: Vector3 = ((B.P["thigh_l"] as Vector3) + (B.P["thigh_r"] as Vector3)) * 0.5
	var w := []
	for k in 33:
		w.append(((B.E[MAP[k][0]] if MAP[k][1] else B.P[MAP[k][0]]) as Vector3) - hip if MAP.has(k) else Vector3.ZERO)
	for sd in ["_l", "_r"]:
		w[HEEL[sd]] = heel(B, sd) - hip
	w[NOSE] = _head_pt(B, NOSE0) - hip
	w[EAR["_l"]] = _head_pt(B, EAR0) + (B.G["head"] as Quaternion) * Vector3(EAR_W, 0, 0) - hip
	w[EAR["_r"]] = _head_pt(B, EAR0) - (B.G["head"] as Quaternion) * Vector3(EAR_W, 0, 0) - hip
	return w


## the face's points as MediaPipe numbers them: 0 the NOSE (the front of the face, not the crown), 7 / 8 the ears. On our
## head bone: the ears 40 % of the way from its base to the crown, 7.5 cm to each side; the nose 10.5 cm in front of their
## midpoint (MediaPipe's own nose-to-ears distance on walk_bat's track: 0.105 m), 31 % up the bone (MediaPipe's median nose
## elevation over the ears on the SIDE-view track of walk_bat, 11.6 deg; the 3/4 view read 52.7: its face depth is not
## trustworthy, so the fit takes only the head's TURN from the face, below)
const EAR := {"_l": 7, "_r": 8}
const EAR0 := Vector3(0.0, 0.4, 0.0)      # (side m, fraction up the head bone, forward m)
const NOSE0 := Vector3(0.0, 0.312, 0.105)
const EAR_W := 0.075


static func _head_pt(B: Body, at: Vector3) -> Vector3:
	var p: Vector3 = B.p0["head"]
	var rest := p + ((B.e0["head"] as Vector3) - p) * at.y + Vector3(at.x, 0.0, at.z)
	return (B.P["head"] as Vector3) + (B.G["head"] as Quaternion) * (rest - p)


## the back of the heel at the sole (MediaPipe's 29 / 30): on the floor under the ankle's line, FOOT_LEN x height behind
## the toe tip at rest; carried by the foot bone
static func heel(B: Body, sd: String) -> Vector3:
	return (B.P["foot" + sd] as Vector3) + (B.G["foot" + sd] as Quaternion) * (heel0(B, sd) - (B.p0["foot" + sd] as Vector3))


## our leg: hip to knee to ankle at rest
static func leg_length(B: Body) -> float:
	return ((B.p0["calf_l"] as Vector3) - (B.p0["thigh_l"] as Vector3)).length() + ((B.p0["foot_l"] as Vector3) - (B.p0["calf_l"] as Vector3)).length()


static func heel0(B: Body, sd: String) -> Vector3:
	var a: Vector3 = B.p0["foot" + sd]
	var tip: Vector3 = B.e0["ball" + sd]
	return Vector3(a.x, tip.y, tip.z - FOOT_LEN * (B.e0["head"] as Vector3).y)


static func _fail(why: String) -> Dictionary:
	return {"ok": false, "why": why}


## pose.json (tools/see/pose.py or tools/export_landmarks.gd) -> {"ok", "fps", "frames": [{"t", "w": [33 Vector3, OUR
## axes: y up]}], "why"}. Never crashes on a bad file
static func parse(txt: String) -> Dictionary:
	var d = JSON.parse_string(txt)
	if not d is Dictionary or not (d as Dictionary).has("frames"):
		return _fail("not a pose file: no \"frames\" (tools/see_video.py writes pose.json)")
	var out := []
	var raw := []
	for f in d["frames"]:
		if not f is Dictionary or not (f as Dictionary).has("world") or (f["world"] as Array).size() < 33:
			continue
		var w := []
		for p in f["world"]:
			w.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
		raw.append({"t": float(f.get("t", 0.0)), "w": w, "im": f.get("image", []), "hd": f.get("hands", null)})
	for f in raw:
		var w := []
		for p in f["w"]:
			w.append(Vector3(p.x, -p.y, -p.z))   # MediaPipe y down -> ours (180 deg about x)
		var e := {"t": f["t"], "w": w}
		if (f["im"] as Array).size() >= 33 and (f["im"][0] as Array).size() >= 3:
			var vs := []   # VIDEO IQ: the tracker's own visibility per landmark (0..1), read by VideoIQ.confidence
			for q in f["im"]:
				vs.append(float(q[2]))
			e["vis"] = vs
		if f["hd"] is Dictionary:
			# ROADMAP 90: each hand's 21 world points, ours (the same 180 deg about x). A hand without 21 points is no hand
			var hd := {}
			for sd in ["l", "r"]:
				if (f["hd"] as Dictionary).has(sd) and ((f["hd"][sd] as Dictionary).get("world", []) as Array).size() == 21:
					var hp := []
					for p in f["hd"][sd]["world"]:
						hp.append(Vector3(float(p[0]), -float(p[1]), -float(p[2])))
					hd[sd] = hp
			if not hd.is_empty():
				e["hands"] = hd
		out.append(e)
	if out.size() < 2:
		return _fail("the pose file has %d usable frames (the tracker found nobody?)" % out.size())
	var tilt := level(out)
	# VIDEO IQ: the camera's depth direction in the frames' axes now (the level turned the clip by `tilt` from the camera's z)
	return {"ok": true, "why": "", "fps": float(d.get("fps", 30.0)), "frames": out, "tilt": tilt, "axis": _axis}


## LEVEL: MediaPipe's world axes follow the CAMERA, so a camera looking down tips the whole person (walk_bat's render: 10 deg
## toward the lens). Up is taken from the clip: the mean of the trunk's up (hips -> shoulders) and the legs' down (hip ->
## ankle, reversed) over every frame, turned onto +y. A walker's trunk leans forward only a few degrees (people's mean
## pelvis/trunk tilt in gait is under 10 deg, Fukuchi band), and the legs swing both ways about vertical. Returns the
## correction's size in degrees
const LEVEL_MIN := 6.0   # deg: below this the clip's "up" is the person's lean, not the camera's tilt (walk_bat's exact
                         # landmarks: 1.2; its MediaPipe track from the app's camera: 10.7)


static var _axis := Vector3(0, 0, 1)   # the camera's depth direction after the last level() (VideoIQ.fix_depth reads it from parse)


static func level(frames: Array) -> float:
	_axis = Vector3(0, 0, 1)
	var m := Vector3.ZERO
	for f in frames:
		var w: Array = f["w"]
		var hip := ((w[HIP["_l"]] as Vector3) + (w[HIP["_r"]] as Vector3)) * 0.5
		var sh := ((w[SH["_l"]] as Vector3) + (w[SH["_r"]] as Vector3)) * 0.5
		m += (sh - hip).normalized()
		for sd in ["_l", "_r"]:
			m += ((w[HIP[sd]] as Vector3) - (w[AN[sd]] as Vector3)).normalized() * 0.5
	if m.length() < 1e-6:
		return 0.0
	var R := Quaternion(m.normalized(), Vector3.UP)
	if rad_to_deg(R.get_angle()) < LEVEL_MIN:
		return 0.0   # within a walker's own lean: the file is level already (an exported Poser scene is)
	_axis = R * Vector3(0, 0, 1)
	for f in frames:
		var w: Array = f["w"]
		for k in w.size():
			w[k] = R * (w[k] as Vector3)
	return rad_to_deg(R.get_angle())


static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("no file at %s" % path)
	return parse(FileAccess.get_file_as_string(path))


## an orthonormal frame: x along a, y as near b as it can be
## a rotation from a frame: orthonormalized first. A frame from two nearly parallel vectors, or one off by rounding, is not
## normalized, and Godot's Quaternion(Basis) refuses it with "Basis ... must be normalized" (walk_bat's leg frames did)
static func _quat(m: Basis) -> Quaternion:
	return Quaternion(m.orthonormalized())


static func _frame(a: Vector3, b: Vector3) -> Basis:
	var x := a.normalized()
	var y := (b - x * b.dot(x)).normalized()
	return Basis(x, y, x.cross(y))


## put joint j at world rotation W (character space): its local rotation is G[parent]^-1 W, split and clamped
static func _set_world(B: Body, j: String, W: Quaternion) -> void:
	var pj: String = B.parent[j]
	var gp: Quaternion = B.G[pj] if pj != "" else Quaternion.IDENTITY
	B.ang[j] = B.clamp_ang(j, B.decompose(j, (gp.inverse() * W).normalized()))
	B.fk_sub(j)


## the hinge plane's normal of a two-bone limb (root -> mid -> tip) at rest, bent a little the way the joint allows
static func _rest_normal(B: Body, mid: String) -> Vector3:
	var root: String = B.parent[mid]
	var tip: String = Body.CHILD[mid]
	var keep: Vector3 = B.ang[mid]
	B.ang[mid] = Vector3(_bend_sign(B, mid) * 30.0, 0.0, 0.0)
	B.fk()
	var n := ((B.P[mid] as Vector3) - (B.P[root] as Vector3)).cross((B.P[tip] as Vector3) - (B.P[mid] as Vector3)).normalized()
	B.ang[mid] = keep
	B.fk()
	return n


## the sign of a hinge's bend: the side of its range that is wider (a knee bends one way, an elbow too)
static func _bend_sign(B: Body, j: String) -> float:
	var r: Vector2 = B.lim[j]["bend"]
	return 1.0 if r.y >= -r.x else -1.0


## a two-bone limb root -> mid -> tip onto three landmark points a -> b -> c
static func _limb(B: Body, root: String, mid: String, a: Vector3, b: Vector3, c: Vector3, n0: Vector3, toe := Vector3.ZERO) -> void:
	var tip: String = Body.CHILD[mid]
	var d := b - a
	var e := c - b
	var bend := rad_to_deg(d.angle_to(e))
	# the root: the shortest arc from where the bone points now, and (bent) the frame of (bone, hinge normal)
	var cur := (B.P[mid] as Vector3) - (B.P[root] as Vector3)
	var arc := Quaternion(cur.normalized(), d.normalized()) * (B.G[root] as Quaternion)
	var d0: Vector3 = (B.p0[mid] as Vector3) - (B.p0[root] as Vector3)
	if toe.length() > 1e-6:
		# a leg: near straight it has no knee plane, but the foot points where the knee does (the plane of thigh and foot)
		var sd := root.right(2)
		var f0: Vector3 = (B.e0["ball" + sd] as Vector3) - (B.p0["foot" + sd] as Vector3)
		arc = _quat(_frame(d, toe) * _frame(d0, f0).inverse())
	var w := smoothstep(STRAIGHT, PLANE_AT, bend)
	var W := arc
	if w > 0.0:
		var pl := _quat(_frame(d, d.cross(e).normalized().cross(d)) * _frame(d0, n0.cross(d0)).inverse())
		W = arc.slerp(pl, w)
	_set_world(B, root, W.normalized())
	# the hinge: the bend (its axis only) whose lower bone points nearest e. Searched, not read off the landmarks' angle:
	# our knee is not on the hip-ankle line at rest (the rest chain is bent a few degrees), so that angle is off by it
	var r: Vector2 = B.lim[mid]["bend"]
	var lo := r.x
	var hi := r.y
	for it in 40:
		var m1 := lo + (hi - lo) / 3.0
		var m2 := hi - (hi - lo) / 3.0
		if _hinge_err(B, mid, tip, m1, e) <= _hinge_err(B, mid, tip, m2, e):
			hi = m2
		else:
			lo = m1
	B.ang[mid] = Vector3((lo + hi) * 0.5, 0.0, 0.0)
	B.fk()


## the foot: its frame from heel -> ankle (fixed in the foot) and the toe's direction (only its side of that line counts,
## so a bent toe does not tip it), then the toe joint bent until the toe tip points at landmark 31 / 32
static func _foot(B: Body, sd: String, w: Array) -> void:
	var f := "foot" + sd
	var up := (w[AN[sd]] as Vector3) - (w[HEEL[sd]] as Vector3)
	var fw := (w[TOE[sd]] as Vector3) - (w[HEEL[sd]] as Vector3)
	var up0 := (B.p0[f] as Vector3) - heel0(B, sd)
	var fw0 := (B.e0["ball" + sd] as Vector3) - heel0(B, sd)
	if up.length() < 1e-6 or fw.length() < 1e-6:
		return
	_set_world(B, f, _quat(_frame(up, fw) * _frame(up0, fw0).inverse()).normalized())
	var b := "ball" + sd
	var e := (w[TOE[sd]] as Vector3) - (w[AN[sd]] as Vector3) - ((B.P[b] as Vector3) - (B.P[f] as Vector3))
	var r: Vector2 = B.lim[b]["bend"]
	var lo := r.x
	var hi := r.y
	for it in 40:
		var m1 := lo + (hi - lo) / 3.0
		var m2 := hi - (hi - lo) / 3.0
		if _toe_err(B, b, m1, e) <= _toe_err(B, b, m2, e):
			hi = m2
		else:
			lo = m1
	B.ang[b] = Vector3((lo + hi) * 0.5, 0.0, 0.0)
	B.fk_sub(b)


static func _toe_err(B: Body, b: String, bend: float, e: Vector3) -> float:
	B.ang[b] = Vector3(bend, 0.0, 0.0)
	B.fk_sub(b)
	return ((B.E[b] as Vector3) - (B.P[b] as Vector3)).normalized().distance_to(e.normalized())


static func _hinge_err(B: Body, mid: String, tip: String, bend: float, e: Vector3) -> float:
	B.ang[mid] = Vector3(bend, 0.0, 0.0)
	B.fk_sub(mid)
	return ((B.P[tip] as Vector3) - (B.P[mid] as Vector3)).normalized().distance_to(e.normalized())


## turn joint j (world, shortest arc) so the direction from its point `from` to `to_pt` (both body points now) is d
static func _aim(B: Body, j: String, from: Vector3, to_pt: Vector3, d: Vector3) -> void:
	var cur := to_pt - from
	if cur.length() < 1e-6 or d.length() < 1e-6:
		return
	_set_world(B, j, (Quaternion(cur.normalized(), d.normalized()) * (B.G[j] as Quaternion)).normalized())


## the body on one frame's landmarks w (our axes, hips' midpoint at 0). The pose only: offset is left at 0
static func fit(B: Body, w: Array) -> void:
	var was := B.fast
	B.fast = true   # fk_sub: only the joints below the one that moved (the hinge search tries 80 bends a limb)
	_fit(B, w)
	B.fast = was


static func _fit(B: Body, w: Array) -> void:
	for j in B.ang:
		B.ang[j] = Vector3.ZERO
	B.offset = Vector3.ZERO
	B.fk()
	var hip_m: Vector3 = ((w[HIP["_l"]] as Vector3) + (w[HIP["_r"]] as Vector3)) * 0.5
	var sh_m: Vector3 = ((w[SH["_l"]] as Vector3) + (w[SH["_r"]] as Vector3)) * 0.5
	var up := sh_m - hip_m
	var r_hip: Vector3 = (B.p0["thigh_l"] as Vector3) - (B.p0["thigh_r"] as Vector3)
	var r_sh: Vector3 = (B.p0["upperarm_l"] as Vector3) - (B.p0["upperarm_r"] as Vector3)
	var r_up: Vector3 = ((B.p0["upperarm_l"] as Vector3) + (B.p0["upperarm_r"] as Vector3)) * 0.5 - ((B.p0["thigh_l"] as Vector3) + (B.p0["thigh_r"] as Vector3)) * 0.5
	# the pelvis, then the spine's turn to the shoulders' frame in thirds
	var Wp := _quat(_frame(w[HIP["_l"]] - w[HIP["_r"]], up) * _frame(r_hip, r_up).inverse())
	_set_world(B, "pelvis", Wp)
	var Wc := _quat(_frame(w[SH["_l"]] - w[SH["_r"]], up) * _frame(r_sh, r_up).inverse())
	var q := ((B.G["pelvis"] as Quaternion).inverse() * Wc).normalized()
	var third := Quaternion.IDENTITY.slerp(q, 1.0 / 3.0)
	for j in ["spine_01", "spine_02", "spine_03"]:
		B.ang[j] = B.clamp_ang(j, B.decompose(j, third))
	B.fk()
	# landmarks are about the hips' midpoint; the body's points about its own: o maps one to the other
	var o: Vector3 = ((B.P["thigh_l"] as Vector3) + (B.P["thigh_r"] as Vector3)) * 0.5
	# the spine's bend: thirds of the turn that brings the shoulders' midpoint onto the landmarks' DIRECTION from the hips
	# (directions only: the tracked person's trunk is not ours in length; matching the point bent ours forward)
	for it in 2:
		var smid0 := ((B.P["upperarm_l"] as Vector3) + (B.P["upperarm_r"] as Vector3)) * 0.5 - o
		var want := sh_m - hip_m
		var t3 := Quaternion.IDENTITY.slerp(Quaternion(smid0.normalized(), want.normalized()), 1.0 / 3.0)
		for j in ["spine_01", "spine_02", "spine_03"]:
			_set_world(B, j, (t3 * (B.G[j] as Quaternion)).normalized())
	# the clavicles: each upper arm's joint toward its shoulder landmark's DIRECTION from the shoulders' midpoint, at our
	# own shoulder width (directions only, as the spine)
	# (round 46) the target is the landmark itself, on the body's own hips (o): the clavicle's joint is turned so the arm's joint
	# lies toward the landmark FROM the clavicle. The old target (the body's shoulder midpoint plus our width) moved the
	# arm by the spine's error, and walk_bat's clavicle came out -4.7 deg against the source's -10
	for sd in ["_l", "_r"]:
		var cj: String = "clavicle" + sd
		var tgt: Vector3 = o + ((w[SH[sd]] as Vector3) - hip_m)
		_aim(B, cj, B.P[cj], B.P["upperarm" + sd], tgt - (B.P[cj] as Vector3))
	# neck and head: the head TURNS where the face points (ears -> nose, about the trunk's up) and otherwise stays on the
	# trunk: MediaPipe's face depth swings the nose's height over the ears by 40 deg with the camera (11.6 side-on, 52.7
	# at 3/4 on the same walk), so its pitch and tilt are not read. Half the turn in the neck, the rest in the head
	var em := ((w[EAR["_l"]] as Vector3) + (w[EAR["_r"]] as Vector3)) * 0.5
	var fw := (w[NOSE] as Vector3) - em
	var hu := up
	if fw.length() > 1e-6 and hu.length() > 1e-6:
		var B0p: Vector3 = B.p0["head"]
		var e0 := B0p + ((B.e0["head"] as Vector3) - B0p) * EAR0.y
		var n0 := B0p + ((B.e0["head"] as Vector3) - B0p) * NOSE0.y + Vector3(0.0, 0.0, NOSE0.z)
		var sm0 := ((B.p0["upperarm_l"] as Vector3) + (B.p0["upperarm_r"] as Vector3)) * 0.5
		var Wh := _quat(_frame(hu, fw) * _frame(r_up, n0 - e0).inverse()).normalized()
		var rel := ((B.G["neck_01"] as Quaternion).inverse() * Wh).normalized()   # neck + head together, from the neck's now
		var half := Quaternion.IDENTITY.slerp(rel, 0.5)
		_set_world(B, "neck_01", ((B.G["neck_01"] as Quaternion) * half).normalized())
		_set_world(B, "head", Wh)
	for sd in ["_l", "_r"]:
		_limb(B, "thigh" + sd, "calf" + sd, w[HIP[sd]], w[KN[sd]], w[AN[sd]], _rest_n(B, "calf" + sd), (w[TOE[sd]] as Vector3) - (w[AN[sd]] as Vector3))
		_foot(B, sd, w)
		_limb(B, "upperarm" + sd, "lowerarm" + sd, w[SH[sd]], w[EL[sd]], w[WR[sd]], _rest_n(B, "lowerarm" + sd))


static var _n_cache := {}


static func _rest_n(B: Body, mid: String) -> Vector3:
	var k := "%d|%s" % [B.get_instance_id(), mid]
	if not _n_cache.has(k):
		var keep := {}
		for j in B.ang:
			keep[j] = B.ang[j]
		for j in B.ang:
			B.ang[j] = Vector3.ZERO
		B.fk()
		_n_cache[k] = _rest_normal(B, mid)
		for j in keep:
			B.ang[j] = keep[j]
		B.fk()
	return _n_cache[k]


## every frame fitted: [{"t", "ang": {joint: Vector3}, "offset": Vector3}], the travel rebuilt from the stance foot and the
## lower sole put on the floor
static func solve(B: Body, frames: Array, held := "", fps := 30.0, contact := {}) -> Array:
	# pass 1: every frame's pose, and each foot's two pivots (the heel's back, the toe joint: people roll over the heel,
	# then over the toes) with the hips at 0
	var poses := []
	var pivs := []
	var lpivs := []
	var legs := []
	var k_leg := leg_length(B)
	var grips := []
	var d_prev := Vector3.ZERO
	if held != "":
		B.set_kind(held)
		B.weapon_to_hand("hand_r")
	# ROADMAP 90: the hands, when the file has any (no "hands" key anywhere: nothing below runs and the body is as before)
	var has_hands := false
	for f in frames:
		if (f as Dictionary).has("hands"):
			has_hands = true
			break
	var hraw := {"l": [], "r": []}
	var hprev := {"l": {}, "r": {}}
	for f in frames:
		fit(B, f["w"])
		if has_hands:
			var hd: Dictionary = f.get("hands", {})
			for sd in ["l", "r"]:
				var got := {}
				if hd.has(sd):
					var H := HandImport.fit_hand(B, sd, hd[sd], hprev[sd])
					if not H.is_empty():
						got = H["ang"]
						hprev[sd] = got
				hraw[sd].append(got if not got.is_empty() else null)
		if held != "":
			var was := B.fast
			B.fast = true   # as fit: limits only, no contact search per turn (136 s -> seconds on the 300-frame axe clip)
			d_prev = _hold(B, f["w"], d_prev)
			B.fast = was
			grips.append(B.grip_u)
		var a := {}
		for j in Body.BODY + (Body.FINGERS if held != "" else []):
			a[j] = B.ang[j]
		poses.append(a)
		var piv := {}
		for sd in ["_l", "_r"]:
			piv[sd] = [heel(B, sd), B.P["ball" + sd]]
		pivs.append(piv)
		# THE TRACKER'S OWN FEET (the root is read here, see below): heel and toe landmarks, hips-relative, in the tracker's metres
		var wl: Array = f["w"]
		lpivs.append({"_l": [wl[HEEL["_l"]], wl[TOE["_l"]]], "_r": [wl[HEEL["_r"]], wl[TOE["_r"]]]})
		for sd in ["_l", "_r"]:
			var t_leg := ((wl[KN[sd]] as Vector3) - (wl[HIP[sd]] as Vector3)).length() + ((wl[AN[sd]] as Vector3) - (wl[KN[sd]] as Vector3)).length()
			if t_leg > 0.2:
				legs.append(k_leg / t_leg)
	# each foot's own floor: the 10th percentile of its lower pivot's height over the clip. A tracker can hold one leg too
	# bent all clip long (MediaPipe's far leg in walk_bat's render: ~20 deg, its foot 8-19 cm above the other's): the
	# lower-foot rule then never plants it and the steps cancel. Each foot is judged against its own floor
	var floor := {}
	for sd in ["_l", "_r"]:
		var hs := []
		for pv in pivs:
			hs.append(minf((pv[sd][0] as Vector3).y, (pv[sd][1] as Vector3).y))
		hs.sort()
		floor[sd] = hs[int(0.1 * (hs.size() - 1))]
	# the hands: filled over the gaps (hold, then ease) and smoothed on the clean path's One Euro filter, then into each frame's pose
	if has_hands:
		var fin := {}
		for sd in ["l", "r"]:
			fin[sd] = HandImport.smooth(HandImport.fill(hraw[sd], fps, sd), fps)
		for i in poses.size():
			for sd in ["l", "r"]:
				var d: Dictionary = fin[sd][i]
				for j in d:
					poses[i][j] = d[j]
	# pass 2: the stance foot (the nearer its floor, this frame and the last summed) stays put; the hips move the opposite
	# way by its lower pivot's move (the one it rolls over)
	# VIDEO IQ (contact = VideoIQ.contacts' "piv": {"_l0" (left heel), "_l1" (left ball), "_r0", "_r1": [bool per frame]}): a pivot that is
	# down is LOCKED instead: each of the two pivots of a foot in contact that is on its floor gets a world anchor the first frame it lands, and the hips are put where the
	# anchors hold the pivots still (the mean of the anchors' answers). No step is integrated, so no error accumulates
	# along a stance: the foot-lock of IK-based foot-skate cleanup (Kovar, Schreiner & Gleicher 2002, "Footskate cleanup for motion
	# capture editing"), here on the root instead of the leg
	var out := []
	var root := Vector3.ZERO
	var anchor := {}
	var lockd := not contact.is_empty()
	var rhist := []
	var gap := 0
	# the tracker's metres to ours: our legs over its legs, the median over the clip (a shorter person's stride is shorter; the
	# body that walks it is ours). The lock below reads the tracker's own heel and toe, not the fitted body's: the fit puts the foot
	# where OUR bones reach from a noisy knee (walk_bat, 1.5 cm noise: its ball speed in stance 0.6-1.7 m/s against the tracker's
	# toe 1.2-1.3 and the real 1.28), the landmark does not carry that error
	var scl := 1.0
	if not legs.is_empty():
		legs.sort()
		scl = legs[legs.size() / 2]
	for i in poses.size():
		if lockd:
			# no pivot anchored from the frame before: the anchors about to be made start from where the root has got to, so a frame
			# that restarts the lock (after a gap) first carries the root on at the walk's own speed, or it would stand still for it
			var cand := []
			var anchored := false
			for sd in ["_l", "_r"]:
				for k in 2:
					var key := "%s%d" % [sd, k]
					var p: Vector3 = (pivs[i][sd][k] as Vector3).lerp((lpivs[i][sd][k] as Vector3) * scl, LM_W)
					if bool(contact[key][i]):
						cand.append([key, p])
						if anchor.has(key):
							anchored = true
					else:
						anchor.erase(key)
			if not anchored and i > 0 and gap <= GAP_HOLD and not rhist.is_empty():
				var rv0 := Vector3.ZERO
				for v in rhist:
					rv0 += v as Vector3
				root += rv0 / float(rhist.size())
			var sols := []
			for cd in cand:
				var key: String = cd[0]
				var p: Vector3 = cd[1]
				if not anchor.has(key):
					anchor[key] = Vector3(root.x + p.x, 0.0, root.z + p.z)
				sols.append(Vector3((anchor[key] as Vector3).x - p.x, 0.0, (anchor[key] as Vector3).z - p.z))
			if not sols.is_empty() and anchored:
				var mean := Vector3.ZERO
				for sv in sols:
					mean += sv as Vector3
				mean /= float(sols.size())
				var nr := mean if i == 0 or (mean - root).length() < LOCK_JUMP else root.lerp(mean, 0.5)
				rhist.append(nr - root)
				if rhist.size() > GAP_WIN:
					rhist.pop_front()
				root = nr
				gap = 0
			elif sols.is_empty():
				gap += 1   # (a frame with nothing locked: the root was carried on above)
			else:
				gap = 0   # the lock restarts here: its anchors were just put at the carried root
		elif i > 0:
			var lo := {}
			for sd in ["_l", "_r"]:
				lo[sd] = 0.0
				for k in [i - 1, i]:
					lo[sd] += minf((pivs[k][sd][0] as Vector3).y, (pivs[k][sd][1] as Vector3).y) - float(floor[sd])
			var st := "_l" if float(lo["_l"]) <= float(lo["_r"]) else "_r"
			var c: Array = pivs[i][st]
			var p: Array = pivs[i - 1][st]
			var k2 := 0 if (c[0] as Vector3).y + (p[0] as Vector3).y <= (c[1] as Vector3).y + (p[1] as Vector3).y else 1
			var mv: Vector3 = (c[k2] as Vector3) - (p[k2] as Vector3)
			root -= Vector3(mv.x, 0.0, mv.z)
		for j in poses[i]:
			B.ang[j] = poses[i][j]
		B.offset = root
		B.fk()
		B.ground()
		var fr := {"t": frames[i]["t"], "ang": poses[i], "offset": B.offset}
		if held != "":
			B.grip_u = grips[i]
			var x := B.wep_xform()
			fr["weapon"] = {"kind": B.wep_kind, "length": B.wep_len, "hand": B.wep_hand, "knob": Body._p(x[0]), "rot": Body._q(x[1]),
				"local_pos": Body._p(B.wep_lpos), "local_rot": Body._q(B.wep_lrot), "two_hand_grip": true, "grip_m": grips[i]}
		out.append(fr)
	return out


## HIS WEAPON IN BOTH HANDS (round 45, GATES AA3; Nick 10-18's axe video: "we are only missing the two handed long axe
## he's using"). The tracker sees no weapon, but it sees both wrists on it: the shaft runs from the bat hand (the right,
## at the butt: the sledge hold Body gives a long hammer or axe) through the other wrist, and the other hand holds it as
## far up as the tracker put that wrist. The fit alone kept each arm's DIRECTION on our own shoulders and arm lengths, so
## two arms aimed at one point landed apart: on the axe clip it spread the wrists 4-37 cm wider than MediaPipe had them.
## Wrists nearer than GRIP_MIN give no direction (a line through two points 10 cm apart, each a few cm off): the last
## frame's is kept. Returns the shaft's direction
const GRIP_MIN := 0.10
static func _hold(B: Body, w: Array, d_prev: Vector3) -> Vector3:
	var a: Vector3 = w[WR["_r"]]
	var b: Vector3 = w[WR["_l"]]
	var sp := a.distance_to(b)
	var d := (b - a) / sp if sp >= GRIP_MIN else d_prev
	if d == Vector3.ZERO:
		d = (a - (w[EL["_r"]] as Vector3)).normalized()   # nothing yet: along the forearm
	B.aim_weapon(d)
	var u0 := B.hold_u()
	B.grip = true
	B.grip_u = clampf(u0 + sp, u0 + 0.08, B.wep_len - 0.12)
	B.apply_grip()
	return d


## the fitted frames -> a Scene, one card per frame (exact) or a card every `every` frames (BvhImport's rule), linear and
## unplanted like a BVH import (MocapClean's foot lock is the next step, as for mocap)
static func to_scene(B: Body, fitted: Array, fps: float, every := 1, scene_name := "video_import") -> Scene:
	var S := Scene.new()
	S.name = scene_name
	S.fps = maxi(1, int(round(fps)))
	S.natural = false
	S.on_floor = false
	S.pin = false
	var n := fitted.size()
	var picks := []
	var k := 0
	while k < n:
		picks.append(k)
		k += maxi(1, every)
	if picks[-1] != n - 1:
		picks.append(n - 1)
	var prev := 0
	for i in picks:
		var fr: Dictionary = fitted[i]
		var jd := {}
		for j in fr["ang"]:
			var v: Vector3 = fr["ang"][j]
			jd[j] = {"bend": v.x, "side": v.y, "twist": v.z}
		var o: Vector3 = fr["offset"]
		var pose := {"joints": jd, "offset": [o.x, o.y, o.z]}
		if fr.has("weapon"):
			pose["weapon"] = fr["weapon"]
		S.add("v%d" % i, pose)
		var c: Dictionary = S.cards[-1]
		c["move"] = float(fr["t"]) - float(fitted[prev]["t"]) if i > 0 else -1.0
		c["hold"] = 0.0
		c["ease"] = "linear"
		prev = i
	return S


## SPARSE CARDS (AA2): a card per frame is mocap, not something to edit. Keep a card every `every` frames and the last,
## each with its "plant" list (MocapClean's contacts); the moves of the dropped cards add into the next kept card's move,
## so the timing is unchanged. On walk_bat's track at every 5 (6 cards a second at 30 fps): 106 -> 22 cards, the planted
## ball's slide 1.59 cm against 1.56 for the dense scene. Also keeping both sides of every contact change (33 cards)
## measured the SAME slide (Scene._planted anchors on the first planted card, not the one before): inert, not kept.
## every_for(fps) gives the step
static func every_for(fps: float) -> int:
	return maxi(1, int(round(fps / 6.0)))


## extra: more card indices to keep (AnimImport's refinement: the frames the even spacing would blend wrong)
static func thin(S: Scene, every: int, extra := {}) -> Scene:
	var n := S.cards.size()
	var keep := {0: true, n - 1: true}
	keep.merge(extra)
	for i in n:
		if i % maxi(1, every) == 0:
			keep[i] = true
	var T := Scene.new()
	T.name = S.name
	T.fps = S.fps
	T.natural = S.natural
	T.on_floor = S.on_floor
	T.pin = S.pin
	var mv := 0.0
	for i in n:
		mv += maxf(0.0, float(S.cards[i]["move"]))
		if keep.has(i):
			var c: Dictionary = S.cards[i].duplicate(true)
			c["move"] = mv if i > 0 else -1.0
			T.cards.append(c)
			mv = 0.0
	return T
