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
##   hands, fingers, clavicles: rest (the 33-point layout has no hand frame)
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
	return w


## the back of the heel at the sole (MediaPipe's 29 / 30): on the floor under the ankle's line, FOOT_LEN x height behind
## the toe tip at rest; carried by the foot bone
static func heel(B: Body, sd: String) -> Vector3:
	return (B.P["foot" + sd] as Vector3) + (B.G["foot" + sd] as Quaternion) * (heel0(B, sd) - (B.p0["foot" + sd] as Vector3))


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
		raw.append({"t": float(f.get("t", 0.0)), "w": w, "im": f.get("image", [])})
	for f in raw:
		var w := []
		for p in f["w"]:
			w.append(Vector3(p.x, -p.y, -p.z))   # MediaPipe y down -> ours (180 deg about x)
		out.append({"t": f["t"], "w": w})
	if out.size() < 2:
		return _fail("the pose file has %d usable frames (the tracker found nobody?)" % out.size())
	var tilt := level(out)
	return {"ok": true, "why": "", "fps": float(d.get("fps", 30.0)), "frames": out, "tilt": tilt}


## LEVEL: MediaPipe's world axes follow the CAMERA, so a camera looking down tips the whole person (walk_bat's render: 10 deg
## toward the lens). Up is taken from the clip: the mean of the trunk's up (hips -> shoulders) and the legs' down (hip ->
## ankle, reversed) over every frame, turned onto +y. A walker's trunk leans forward only a few degrees (people's mean
## pelvis/trunk tilt in gait is under 10 deg, Fukuchi band), and the legs swing both ways about vertical. Returns the
## correction's size in degrees
const LEVEL_MIN := 6.0   # deg: below this the clip's "up" is the person's lean, not the camera's tilt (walk_bat's exact
                         # landmarks: 1.2; its MediaPipe track from the app's camera: 10.7)


static func level(frames: Array) -> float:
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
		arc = Quaternion(_frame(d, toe) * _frame(d0, f0).inverse())
	var w := smoothstep(STRAIGHT, PLANE_AT, bend)
	var W := arc
	if w > 0.0:
		var pl := Quaternion(_frame(d, d.cross(e).normalized().cross(d)) * _frame(d0, n0.cross(d0)).inverse())
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
	_set_world(B, f, Quaternion(_frame(up, fw) * _frame(up0, fw0).inverse()).normalized())
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
	var Wp := Quaternion(_frame(w[HIP["_l"]] - w[HIP["_r"]], up) * _frame(r_hip, r_up).inverse())
	_set_world(B, "pelvis", Wp)
	var Wc := Quaternion(_frame(w[SH["_l"]] - w[SH["_r"]], up) * _frame(r_sh, r_up).inverse())
	var q := ((B.G["pelvis"] as Quaternion).inverse() * Wc).normalized()
	var third := Quaternion.IDENTITY.slerp(q, 1.0 / 3.0)
	for j in ["spine_01", "spine_02", "spine_03"]:
		B.ang[j] = B.clamp_ang(j, B.decompose(j, third))
	B.fk()
	# landmarks are about the hips' midpoint; the body's points about its own: o maps one to the other
	var o: Vector3 = ((B.P["thigh_l"] as Vector3) + (B.P["thigh_r"] as Vector3)) * 0.5
	# the spine's bend: thirds of the turn that brings the shoulders' midpoint onto the landmarks' (from spine_01)
	for it in 2:
		var smid0 := ((B.P["upperarm_l"] as Vector3) + (B.P["upperarm_r"] as Vector3)) * 0.5 - (B.P["spine_01"] as Vector3)
		var want := sh_m + o - (B.P["spine_01"] as Vector3)
		var t3 := Quaternion.IDENTITY.slerp(Quaternion(smid0.normalized(), want.normalized()), 1.0 / 3.0)
		for j in ["spine_01", "spine_02", "spine_03"]:
			_set_world(B, j, (t3 * (B.G[j] as Quaternion)).normalized())
	# the clavicles: each upper arm's joint onto its shoulder landmark
	for sd in ["_l", "_r"]:
		var cj: String = "clavicle" + sd
		_aim(B, cj, B.P[cj], B.P["upperarm" + sd], (w[SH[sd]] as Vector3) + o - (B.P[cj] as Vector3))
	# neck and head: halves of the turn that points the head's end at landmark 0 (from the neck)
	var hd: Vector3 = (w[NOSE] as Vector3) + o - (B.P["neck_01"] as Vector3)
	var cur: Vector3 = (B.E["head"] as Vector3) - (B.P["neck_01"] as Vector3)
	if cur.length() > 1e-6 and hd.length() > 1e-6:
		var half := Quaternion.IDENTITY.slerp(Quaternion(cur.normalized(), hd.normalized()), 0.5)
		_set_world(B, "neck_01", (half * (B.G["neck_01"] as Quaternion)).normalized())
		_set_world(B, "head", (half * (B.G["head"] as Quaternion)).normalized())
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
static func solve(B: Body, frames: Array) -> Array:
	# pass 1: every frame's pose, and each foot's two pivots (the heel's back, the toe joint: people roll over the heel,
	# then over the toes) with the hips at 0
	var poses := []
	var pivs := []
	for f in frames:
		fit(B, f["w"])
		var a := {}
		for j in Body.BODY:
			a[j] = B.ang[j]
		poses.append(a)
		var piv := {}
		for sd in ["_l", "_r"]:
			piv[sd] = [heel(B, sd), B.P["ball" + sd]]
		pivs.append(piv)
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
	# pass 2: the stance foot (the nearer its floor, this frame and the last summed) stays put; the hips move the opposite
	# way by its lower pivot's move (the one it rolls over)
	var out := []
	var root := Vector3.ZERO
	for i in poses.size():
		if i > 0:
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
		out.append({"t": frames[i]["t"], "ang": poses[i], "offset": B.offset})
	return out


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
		S.add("v%d" % i, {"joints": jd, "offset": [o.x, o.y, o.z]})
		var c: Dictionary = S.cards[-1]
		c["move"] = float(fr["t"]) - float(fitted[prev]["t"]) if i > 0 else -1.0
		c["hold"] = 0.0
		c["ease"] = "linear"
		prev = i
	return S
