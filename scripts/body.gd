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
	set_ang(j, v)


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
	return {"offset": _p(offset), "joints": joints}


func from_dict(d: Dictionary) -> void:
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
