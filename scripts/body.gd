## body.gd - the mannequin's math, and nothing else (no drawing, no input). docs: MATH.md.
##
## Character space: +Y up, +Z forward (the hero faces +Z), +X = the hero's LEFT; metres.
## Each joint j has, from data/skeleton.json, its REST position P0[j] and from data/body_limits.json three axes fixed
## at rest:  t = along the bone (joint -> end),  b = bend axis (t x f),  a = side axis (t x s).
## Its pose is three angles (bend, side, twist) in degrees, turned into one rotation A[j]:
##     A = swing * twist,   swing = rotation by |v| about v/|v| with v = bend*b + side*a,   twist = rotation by twist about t
## FK, root first:
##     G[j] = G[parent] * A[j]                       (G = how far the joint's frame has turned from rest)
##     P[j] = P[parent] + G[parent] * (P0[j] - P0[parent])
## Root: G = A[pelvis], P = P0[pelvis] + offset.
class_name Body
extends RefCounted

const ORDER := ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head",
	"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
	"thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"]
## the joint whose position is this joint's "end" (its child along the limb); hands, balls, head use an end point
const CHILD := {"pelvis": "spine_01", "spine_01": "spine_02", "spine_02": "spine_03", "spine_03": "neck_01",
	"neck_01": "head", "clavicle_l": "upperarm_l", "upperarm_l": "lowerarm_l", "lowerarm_l": "hand_l",
	"clavicle_r": "upperarm_r", "upperarm_r": "lowerarm_r", "lowerarm_r": "hand_r",
	"thigh_l": "calf_l", "calf_l": "foot_l", "foot_l": "ball_l", "thigh_r": "calf_r", "calf_r": "foot_r", "foot_r": "ball_r"}

var parent := {}       # joint -> parent joint ("" for the pelvis)
var p0 := {}           # joint -> rest position
var e0 := {}           # joint -> rest end point
var rest_rot := {}     # joint -> rest world rotation (glTF, for writing back into the game)
var root_rot := Quaternion.IDENTITY   # the pelvis's parent node's world rotation (glTF "root" bone)
var root_pos := Vector3.ZERO
var t_ax := {}         # joint -> twist axis (unit, at rest)
var b_ax := {}         # joint -> bend axis
var a_ax := {}         # joint -> side axis
var lim := {}          # joint -> {"bend": Vector2(min,max), "side": ..., "twist": ..., "r": radius, "say": {...}}
var cap0 := {}         # part -> [a, b] its capsule's two end points at rest (skeleton.json, fitted to the mesh)
var rad := {}          # part -> capsule radius (m)
var pairs := []        # [part, part] checked for contact (all pairs, minus those already touching at rest)
var allow := {}        # "x|y" -> how deep that pair already sits in the body's neutral poses (m): touching beyond it = contact
var stick := false     # the stick in the right hand
var stick_len := 0.9   # metres (the shaft; the head is the last STICK_HEAD of it)
var grip := false      # the left hand holds the stick too
var grip_u := 0.35     # where the left hand holds it: 0 = the bottom end, 1 = the top
const STICK_R := 0.018
const STICK_HEAD := 0.16
const HEAD_R := 0.055
var ang := {}          # joint -> Vector3(bend, side, twist) degrees  (THE POSE)
var offset := Vector3.ZERO   # pelvis moved from rest (metres)

# results of the last fk()
var G := {}            # joint -> Quaternion
var P := {}            # joint -> Vector3
var E := {}            # joint -> Vector3 (end point)


func load_files(skel_path: String, limits_path: String) -> void:
	var skf: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(skel_path))
	var sk: Dictionary = skf["joints"]
	if skf.has("pelvis_parent"):
		var rr: Array = skf["pelvis_parent"]["rot"]
		root_rot = Quaternion(rr[0], rr[1], rr[2], rr[3])
		root_pos = _v(skf["pelvis_parent"]["pos"])
	var li: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(limits_path))
	for j in ORDER:
		var d: Dictionary = sk[j]
		parent[j] = d["parent"] if d["parent"] != null else ""
		p0[j] = _v(d["pos"])
		var r: Array = d["rot"]
		rest_rot[j] = Quaternion(r[0], r[1], r[2], r[3])
	for j in ORDER:
		if CHILD.has(j):
			e0[j] = p0[CHILD[j]]
		elif sk[j].has("end"):
			e0[j] = _v(sk[j]["end"])
	# limits: right side + centre as written, left = mirror of right
	for j in ORDER:
		var src: String = j.replace("_l", "_r") if j.ends_with("_l") else j
		var L: Dictionary = li[src]
		var f := _v(L["f"])
		var s := _v(L["s"])
		var tw := Vector2(L["twist"][0], L["twist"][1])
		if j.ends_with("_l"):
			f.x = -f.x
			s.x = -s.x
			tw = Vector2(-tw.y, -tw.x)
		if not e0.has(j):   # the head: a point straight up from the joint
			e0[j] = p0[j] + Vector3.UP * float(L.get("len", 0.2))
		var t: Vector3 = (e0[j] - p0[j]).normalized()
		# an exact right-angle frame (t, fo, so): fo = f made square to the bone, so = square to both, on s's side.
		# (Squaring s to the bone alone left bend and side leaking into each other: 15 deg in the round trip.)
		var fo := (f - t * f.dot(t)).normalized()
		var so := t.cross(fo)
		if so.dot(s) < 0.0:
			so = -so
		t_ax[j] = t
		b_ax[j] = t.cross(fo).normalized()
		a_ax[j] = t.cross(so).normalized()
		lim[j] = {"bend": Vector2(L["bend"][0], L["bend"][1]), "side": Vector2(L["side"][0], L["side"][1]),
			"twist": tw, "r": float(L["r"]), "say": L.get("say", {})}
		ang[j] = Vector3.ZERO
		if sk[j].has("cap"):
			cap0[j] = [_v(sk[j]["cap"][0]), _v(sk[j]["cap"][1])]
			rad[j] = float(sk[j]["radius"])
		else:
			cap0[j] = [p0[j], e0[j]]
			rad[j] = float(L["r"])
	# the stick, held in the right fist: through the palm (60% down the hand), out of the fist on the thumb side (at
	# rest +Z); 12 cm sticks out below the fist
	var gp: Vector3 = (p0["hand_r"] as Vector3).lerp(e0["hand_r"], 0.6) + Vector3(0, -0.035, 0)
	var dz := Vector3(0, 0, 1)
	cap0["stick"] = [gp - dz * 0.12, gp + dz * (stick_len - 0.12 - STICK_HEAD)]
	cap0["stick_head"] = [gp + dz * (stick_len - 0.12 - STICK_HEAD), gp + dz * (stick_len - 0.12)]
	rad["stick"] = STICK_R
	rad["stick_head"] = HEAD_R
	fk()
	# contact pairs: every two parts except a part and its own parent/child; the stick only against the body.
	# A pair may already overlap in the body's NEUTRAL poses (the shoulder sits in the chest, a hanging arm rests on the
	# thigh): that much is its allowance, measured below; a contact is sinking deeper than that.
	var names: Array = ORDER + ["stick", "stick_head"]
	var held := ["hand_r", "lowerarm_r", "hand_l"]
	for i in names.size():
		for k in range(i + 1, names.size()):
			var x: String = names[i]
			var y: String = names[k]
			if parent.get(x, "") == y or parent.get(y, "") == x:
				continue
			if x.begins_with("stick") and y.begins_with("stick"):
				continue
			if (x.begins_with("stick") and y in held) or (y.begins_with("stick") and x in held):
				continue
			pairs.append([x, y])
	# the neutral poses: the T-pose, and arms hanging at the sides
	var calib := [{}, {"upperarm_r": Vector3(0, -90, 0), "upperarm_l": Vector3(0, -90, 0)},
		{"upperarm_r": Vector3(0, -95, 0), "upperarm_l": Vector3(0, -95, 0)}]
	for pose in calib:
		for j in ORDER:
			ang[j] = pose.get(j, Vector3.ZERO)
		fk()
		for pr in pairs:
			var key: String = pr[0] + "|" + pr[1]
			allow[key] = maxf(allow.get(key, 0.0), depth(pr[0], pr[1]) + 0.002)   # pairs apart: 0; touching: + 2 mm
	for j in ORDER:
		ang[j] = Vector3.ZERO
	fk()


static func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


## (bend, side, twist) degrees -> the joint's rotation A, in rest character axes
func compose(j: String, v: Vector3) -> Quaternion:
	var rv: Vector3 = b_ax[j] * deg_to_rad(v.x) + a_ax[j] * deg_to_rad(v.y)
	var n := rv.length()
	var sw := Quaternion(rv / n, n) if n > 1e-9 else Quaternion.IDENTITY
	return sw * Quaternion(t_ax[j], deg_to_rad(v.z))


## the joint's rotation A -> (bend, side, twist) degrees. swing-twist split: A = swing * twist, twist about t
func decompose(j: String, q: Quaternion) -> Vector3:
	var t: Vector3 = t_ax[j]
	var pr := Vector3(q.x, q.y, q.z).dot(t) * t
	var qt := Quaternion(pr.x, pr.y, pr.z, q.w)
	qt = qt.normalized() if qt.length() > 1e-9 else Quaternion.IDENTITY
	var qs := q * qt.inverse()
	if qs.w < 0.0:
		qs = Quaternion(-qs.x, -qs.y, -qs.z, -qs.w)
	var s := sqrt(maxf(0.0, 1.0 - qs.w * qs.w))
	var rv := Vector3.ZERO
	if s > 1e-9:
		rv = Vector3(qs.x, qs.y, qs.z) / s * (2.0 * acos(clampf(qs.w, -1.0, 1.0)))
	var tw := 2.0 * atan2(Vector3(qt.x, qt.y, qt.z).dot(t), qt.w)
	if tw > PI:
		tw -= TAU
	elif tw < -PI:
		tw += TAU
	return Vector3(rad_to_deg(rv.dot(b_ax[j])), rad_to_deg(rv.dot(a_ax[j])), rad_to_deg(tw))


## keep each angle inside the body's range
func clamp_ang(j: String, v: Vector3) -> Vector3:
	var L: Dictionary = lim[j]
	return Vector3(clampf(v.x, L["bend"].x, L["bend"].y), clampf(v.y, L["side"].x, L["side"].y),
		clampf(v.z, L["twist"].x, L["twist"].y))


## which of the joint's three angles sit on a limit (within 0.5 deg), e.g. ["bend"]; locked axes don't count, nor a
## limit AT the rest angle 0 (a straight elbow or knee is its stop, but straight is normal, not a warning)
func at_limit(j: String) -> Array:
	var out := []
	var v: Vector3 = ang[j]
	for k in [["bend", v.x], ["side", v.y], ["twist", v.z]]:
		var r: Vector2 = lim[j][k[0]]
		var lo: bool = r.x != 0.0 and k[1] <= r.x + 0.5
		var hi: bool = r.y != 0.0 and k[1] >= r.y - 0.5
		if r.y - r.x > 0.5 and (lo or hi):
			out.append(k[0])
	return out


func set_ang(j: String, v: Vector3) -> void:
	ang[j] = clamp_ang(j, v)
	fk()


## turn joint j by a rotation R given in CHARACTER space (now, not at rest), e.g. from a mouse drag; the result is
## split back into its three angles and clamped. A_new = G[parent]^-1 * R * G[parent] * A_old
func turn_world(j: String, R: Quaternion) -> void:
	var gp: Quaternion = G[parent[j]] if parent[j] != "" else Quaternion.IDENTITY
	var a_new := gp.inverse() * R * gp * compose(j, ang[j])
	var v := decompose(j, a_new.normalized())
	var old: Vector3 = ang[j]
	# keep the twist continuous across +-180
	while v.z - old.z > 180.0:
		v.z -= 360.0
	while v.z - old.z < -180.0:
		v.z += 360.0
	set_ang_safe(j, v)


func set_stick_len(L: float) -> void:
	stick_len = clampf(L, 0.3, 1.8)
	var a: Vector3 = cap0["stick"][0]
	var dz: Vector3 = ((cap0["stick"][1] as Vector3) - a).normalized()
	var gp := a + dz * 0.12
	cap0["stick"] = [a, gp + dz * (stick_len - 0.12 - STICK_HEAD)]
	cap0["stick_head"] = [gp + dz * (stick_len - 0.12 - STICK_HEAD), gp + dz * (stick_len - 0.12)]


## a part's capsule now: its rest end points carried by its joint (the stick rides the right hand)
func cap(part: String) -> Array:
	var j := "hand_r" if part.begins_with("stick") else part
	var c: Array = cap0[part]
	var g: Quaternion = G[j]
	var pj: Vector3 = P[j]
	var rj: Vector3 = p0[j]
	return [pj + g * ((c[0] as Vector3) - rj), pj + g * ((c[1] as Vector3) - rj)]


## how far two capsules sink into each other (m): > 0 = inside, < 0 = the gap between them
func depth(x: String, y: String) -> float:
	var a: Array = cap(x)
	var b: Array = cap(y)
	return float(rad[x]) + float(rad[y]) - seg_seg(a[0], a[1], b[0], b[1])


## every contact now: [[part, part, depth], ...] with depth > 0
func contacts() -> Array:
	var out := []
	for pr in pairs:
		if not stick and ((pr[0] as String).begins_with("stick") or (pr[1] as String).begins_with("stick")):
			continue
		var d := depth(pr[0], pr[1]) - float(allow.get(pr[0] + "|" + pr[1], 0.0))
		if d > 0.0:
			out.append([pr[0], pr[1], d])
	return out


func penetration() -> float:
	var t := 0.0
	for c in contacts():
		t += float(c[2])
	return t


## the shortest distance between segments p1-q1 and p2-q2 (Ericson, Real-Time Collision Detection 5.1.9)
static func seg_seg(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-12 and e <= 1e-12:
		return r.length()
	if a <= 1e-12:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-12:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var den := a * e - b * b
			s = clampf((b * f - c * e) / den, 0.0, 1.0) if den > 1e-12 else 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return ((p1 + d1 * s) - (p2 + d2 * t)).length()


## set a joint's angles, but never INTO the body: if the new angles sink parts deeper than before, go only as far as
## the contact (bisection on the way from the old angles to the new: 10 halvings = 0.1% of the move)
func set_ang_safe(j: String, v: Vector3) -> bool:
	var old: Vector3 = ang[j]
	var pen0 := penetration()
	set_ang(j, v)
	if penetration() <= pen0 + 1e-4:
		return true
	var target: Vector3 = ang[j]
	var lo := 0.0
	var hi := 1.0
	for i in 10:
		var m := (lo + hi) * 0.5
		set_ang(j, old.lerp(target, m))
		if penetration() <= pen0 + 1e-4:
			lo = m
		else:
			hi = m
	set_ang(j, old.lerp(target, lo))
	return false


## reach: put a limb's tip (hand_r/l = the wrist, foot_r/l = the ankle) on a target point. Two joints, in turns: the
## elbow/knee bend sets the shoulder-to-tip DISTANCE (bisection: it falls as the bend grows), then the shoulder/hip
## turns the tip onto the target (turn_world). Every step goes through the limits and the contacts, so the limb stops
## where the body stops it. Returns how far the tip ends from the target (m).
func reach(tip: String, target: Vector3) -> float:
	var mid: String = parent[tip]
	var root: String = parent[mid]
	for it in 6:
		var want := ((target - P[root]) as Vector3).length()
		var r: Vector2 = lim[mid]["bend"]
		var v: Vector3 = ang[mid]
		var lo := r.x
		var hi := r.y
		for k in 14:
			var m := (lo + hi) * 0.5
			ang[mid] = Vector3(m, v.y, v.z)
			fk()
			if ((P[tip] - P[root]) as Vector3).length() > want:
				lo = m
			else:
				hi = m
		ang[mid] = v
		fk()
		set_ang_safe(mid, Vector3((lo + hi) * 0.5, v.y, v.z))
		var r1: Vector3 = P[tip] - P[root]
		var r2: Vector3 = target - P[root]
		var ax := r1.cross(r2)
		if ax.length() > 1e-9:
			turn_world(root, Quaternion(ax.normalized(), r1.angle_to(r2)))
	return ((P[tip] - target) as Vector3).length()


## where the left hand holds the stick (grip_u along it)
func grip_point() -> Vector3:
	var c: Array = cap("stick")
	var h: Array = cap("stick_head")
	return (c[0] as Vector3).lerp(h[1], clampf(grip_u, 0.0, 1.0))


## the left wrist onto the stick: the wrist sits a fist behind the grip point, back along the left hand
func apply_grip() -> float:
	if not (stick and grip):
		return 0.0
	var back: Vector3 = ((P["hand_l"] - E["hand_l"]) as Vector3).normalized() * ((e0["hand_l"] - p0["hand_l"]) as Vector3).length() * 0.6
	return reach("hand_l", grip_point() + back)


func fk() -> void:
	for j in ORDER:
		var A := compose(j, ang[j])
		var pj: String = parent[j]
		if pj == "":
			G[j] = A
			P[j] = p0[j] + offset
		else:
			G[j] = G[pj] * A
			P[j] = P[pj] + G[pj] * (p0[j] - p0[pj])
		E[j] = P[j] + G[j] * (e0[j] - p0[j])


## the glTF node's local rotation for this pose (for writing the pose back into a hero glb):
## W[j] = G[j] * W0[j]  ->  L[j] = W[parent]^-1 * W[j] = W0[parent]^-1 * A[j] * W0[j]
func gltf_local(j: String) -> Quaternion:
	var w0: Quaternion = rest_rot[j]
	var A := compose(j, ang[j])
	if parent[j] == "":
		return root_rot.inverse() * A * w0   # the pelvis: relative to its parent node, the glTF "root" bone
	return (rest_rot[parent[j]] as Quaternion).inverse() * A * w0


## the pelvis's local position for this pose (its parent is the "root" bone): Wroot^-1 * (P - root position)
func gltf_pelvis_pos() -> Vector3:
	return root_rot.inverse() * (P["pelvis"] - root_pos)


func mirror_side(from_side: String) -> void:
	var to_side := "_l" if from_side == "_r" else "_r"
	for j in ORDER:
		if j.ends_with(from_side):
			var v: Vector3 = ang[j]
			ang[j.replace(from_side, to_side)] = clamp_ang(j.replace(from_side, to_side), Vector3(v.x, v.y, -v.z))
	fk()


## the pose as plain data: angles, rotations and positions, all readable
func to_dict() -> Dictionary:
	var joints := {}
	for j in ORDER:
		var a: Vector3 = ang[j]
		var A := compose(j, a)
		var g: Quaternion = G[j]
		joints[j] = {
			"bend": snappedf(a.x, 0.01), "side": snappedf(a.y, 0.01), "twist": snappedf(a.z, 0.01),
			"A": _q(A), "G": _q(g), "pos": _p(P[j]), "end": _p(E[j]), "at_limit": at_limit(j)}
	var con := []
	for c in contacts():
		con.append([c[0], c[1], snappedf(c[2], 0.0001)])
	var st := {}
	if stick:
		var a: Array = cap("stick")
		var h: Array = cap("stick_head")
		st = {"length": stick_len, "bottom": _p(a[0]), "top": _p(h[1]), "left_grip": grip, "grip_u": grip_u}
	return {"offset": _p(offset), "joints": joints, "stick": st, "contacts": con}


func from_dict(d: Dictionary) -> void:
	var st: Dictionary = d.get("stick", {})
	stick = not st.is_empty() or not d.has("stick")
	if not st.is_empty():
		set_stick_len(float(st.get("length", stick_len)))
		grip = bool(st.get("left_grip", false))
		grip_u = float(st.get("grip_u", grip_u))
	var o: Array = d.get("offset", [0, 0, 0])
	offset = _v(o)
	for j in d["joints"]:
		var x: Dictionary = d["joints"][j]
		ang[j] = clamp_ang(j, Vector3(x["bend"], x["side"], x["twist"]))
	fk()


static func _q(q: Quaternion) -> Array:
	return [snappedf(q.x, 0.00001), snappedf(q.y, 0.00001), snappedf(q.z, 0.00001), snappedf(q.w, 0.00001)]


static func _p(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]
