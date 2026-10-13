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
## The weapon (a metal bat) is a separate rigid object: FREE in the world, or LOCKED to a hand (then it rides the hand).
class_name Body
extends RefCounted

const BODY := ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head",
	"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
	"thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"]
const FINGERS := [
	"thumb_01_l", "thumb_02_l", "thumb_03_l", "index_01_l", "index_02_l",
	"index_03_l", "middle_01_l", "middle_02_l", "middle_03_l", "ring_01_l",
	"ring_02_l", "ring_03_l", "pinky_01_l", "pinky_02_l", "pinky_03_l",
	"thumb_01_r", "thumb_02_r", "thumb_03_r", "index_01_r", "index_02_r",
	"index_03_r", "middle_01_r", "middle_02_r", "middle_03_r", "ring_01_r",
	"ring_02_r", "ring_03_r", "pinky_01_r", "pinky_02_r", "pinky_03_r"]
## every joint, parents before children (FK order)
const ORDER := ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head",
	"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r",
	"thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r",
	"thumb_01_l", "thumb_02_l", "thumb_03_l", "index_01_l", "index_02_l",
	"index_03_l", "middle_01_l", "middle_02_l", "middle_03_l", "ring_01_l",
	"ring_02_l", "ring_03_l", "pinky_01_l", "pinky_02_l", "pinky_03_l",
	"thumb_01_r", "thumb_02_r", "thumb_03_r", "index_01_r", "index_02_r",
	"index_03_r", "middle_01_r", "middle_02_r", "middle_03_r", "ring_01_r",
	"ring_02_r", "ring_03_r", "pinky_01_r", "pinky_02_r", "pinky_03_r"]
## the joint whose position is this joint's "end" (its child along the limb); hands, balls, head, fingertips use an end point
const CHILD := {"pelvis": "spine_01", "spine_01": "spine_02", "spine_02": "spine_03", "spine_03": "neck_01",
	"neck_01": "head", "clavicle_l": "upperarm_l", "upperarm_l": "lowerarm_l", "lowerarm_l": "hand_l",
	"clavicle_r": "upperarm_r", "upperarm_r": "lowerarm_r", "lowerarm_r": "hand_r",
	"thigh_l": "calf_l", "calf_l": "foot_l", "foot_l": "ball_l", "thigh_r": "calf_r", "calf_r": "foot_r", "foot_r": "ball_r",
	"thumb_01_l": "thumb_02_l", "thumb_02_l": "thumb_03_l", "index_01_l": "index_02_l", "index_02_l": "index_03_l", "middle_01_l": "middle_02_l", "middle_02_l": "middle_03_l", "ring_01_l": "ring_02_l", "ring_02_l": "ring_03_l", "pinky_01_l": "pinky_02_l", "pinky_02_l": "pinky_03_l",
	"thumb_01_r": "thumb_02_r", "thumb_02_r": "thumb_03_r", "index_01_r": "index_02_r", "index_02_r": "index_03_r", "middle_01_r": "middle_02_r", "middle_02_r": "middle_03_r", "ring_01_r": "ring_02_r", "ring_02_r": "ring_03_r", "pinky_01_r": "pinky_02_r", "pinky_02_r": "pinky_03_r"}
const WEAPON := ["bat_handle", "bat_barrel"]

var parent := {}       # joint -> parent joint ("" for the pelvis)
var p0 := {}           # joint -> rest position
var e0 := {}           # joint -> rest end point
var rest_rot := {}     # joint -> rest world rotation (glTF, for writing back into the game)
var root_rot := Quaternion.IDENTITY   # the pelvis's parent node's world rotation (glTF "root" bone)
var root_pos := Vector3.ZERO
var t_ax := {}         # joint -> twist axis (unit, at rest)
var b_ax := {}         # joint -> bend axis
var a_ax := {}         # joint -> side axis
var lim := {}          # joint -> {"bend": Vector2(min,max), "side": ..., "twist": ..., "say": {...}}
var cap0 := {}         # part -> [a, b] its capsule's two end points at rest (skeleton.json, fitted to the mesh)
var rad := {}          # part -> capsule radius (m)
var pairs := []        # [part, part] checked for contact
var allow := {}        # "x|y" -> how deep that pair already sits in the body's neutral poses (m)
var ang := {}          # joint -> Vector3(bend, side, twist) degrees  (THE POSE)
var offset := Vector3.ZERO   # pelvis moved from rest (metres)

# the weapon: a metal bat. Its own frame: the knob at the origin, the bat along its +Y to the tip.
var wep_on := false
var wep_len := 0.84          # 33 inches, a common adult bat
var wep_handle := 0.40       # knob -> where the barrel starts to swell
var wep_r_handle := 0.016
var wep_r_barrel := 0.033
var wep_pos := Vector3(-0.45, 0.0, 0.25)     # free: the knob's world position ...
var wep_rot := Quaternion.IDENTITY           # ... and the bat's world rotation (standing upright)
var wep_hand := ""                           # locked to "hand_r" / "hand_l", or "" = free
var wep_lpos := Vector3.ZERO                 # locked: the knob in the hand's frame:  pos = P[h] + G[h] * lpos
var wep_lrot := Quaternion.IDENTITY          #                                         rot = G[h] * lrot
var grip := false      # the OTHER hand holds the bat too
var grip_u := 0.18     # where it holds it: metres up the bat from the knob

# results of the last fk()
var G := {}            # joint -> Quaternion
var P := {}            # joint -> Vector3
var E := {}            # joint -> Vector3 (end point)


## which entry of body_limits.json a joint uses: left = its right twin; fingers share "finger_01..03", thumbs "thumb_0k"
static func lim_key(j: String) -> String:
	var src: String = j.substr(0, j.length() - 2) + "_r" if j.ends_with("_l") else j
	for f in ["index", "middle", "ring", "pinky"]:
		if src.begins_with(f + "_"):
			return "finger_" + src.substr(f.length() + 1, 2)
	if src.begins_with("thumb_"):
		return src.substr(0, 8)
	return src


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
	# limits: right side + centre as written (fingers by kind), left = mirror of right
	for j in ORDER:
		var L: Dictionary = li[lim_key(j)]
		var f := _v(L["f"])
		var s := _v(L["s"])
		var tw := Vector2(L["twist"][0], L["twist"][1])
		if j.ends_with("_l"):
			f.x = -f.x
			s.x = -s.x
			tw = Vector2(-tw.y, -tw.x)
		if not e0.has(j):
			e0[j] = p0[j] + Vector3.UP * float(L.get("len", 0.2))
		var t: Vector3 = (e0[j] - p0[j]).normalized()
		# an exact right-angle frame (t, fo, so): fo = f made square to the bone, so = square to both, on s's side.
		var fo := (f - t * f.dot(t)).normalized()
		var so := t.cross(fo)
		if so.dot(s) < 0.0:
			so = -so
		t_ax[j] = t
		b_ax[j] = t.cross(fo).normalized()
		a_ax[j] = t.cross(so).normalized()
		lim[j] = {"bend": Vector2(L["bend"][0], L["bend"][1]), "side": Vector2(L["side"][0], L["side"][1]),
			"twist": tw, "say": L.get("say", {})}
		ang[j] = Vector3.ZERO
		if sk[j].has("cap"):
			cap0[j] = [_v(sk[j]["cap"][0]), _v(sk[j]["cap"][1])]
			rad[j] = float(sk[j]["radius"])
		else:
			cap0[j] = [p0[j], e0[j]]
			rad[j] = float(L["r"])
	rad["bat_handle"] = wep_r_handle
	rad["bat_barrel"] = wep_r_barrel
	fk()
	# contact pairs: body part vs body part (not a part and its own parent/child; fingers are left out: they wrap
	# round things), and the bat vs the body (not the hands: they hold it).
	var names: Array = BODY + WEAPON
	for i in names.size():
		for k in range(i + 1, names.size()):
			var x: String = names[i]
			var y: String = names[k]
			if parent.get(x, "") == y or parent.get(y, "") == x:
				continue
			if x in WEAPON and y in WEAPON:
				continue
			if (x in WEAPON and y in ["hand_r", "hand_l"]) or (y in WEAPON and x in ["hand_r", "hand_l"]):
				continue
			pairs.append([x, y])
	# A pair may already overlap in the body's NEUTRAL poses (the shoulder sits in the chest, a hanging arm rests on
	# the thigh): that much (+2 mm) is its allowance; a contact = sinking deeper. The bat is put away while measuring.
	var keep_on := wep_on
	wep_on = false
	var calib := [{}, {"upperarm_r": Vector3(0, -90, 0), "upperarm_l": Vector3(0, -90, 0)},
		{"upperarm_r": Vector3(0, -95, 0), "upperarm_l": Vector3(0, -95, 0)}]
	for pose in calib:
		for j in ORDER:
			ang[j] = pose.get(j, Vector3.ZERO)
		fk()
		for pr in pairs:
			if pr[0] in WEAPON or pr[1] in WEAPON:
				continue
			var key: String = pr[0] + "|" + pr[1]
			allow[key] = maxf(allow.get(key, 0.0), depth(pr[0], pr[1]) + 0.002)
	for j in ORDER:
		ang[j] = Vector3.ZERO
	wep_on = keep_on
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


## which of the joint's three angles sit on a limit (within 0.5 deg); locked axes don't count, nor a limit AT the
## rest angle 0 (a straight elbow or knee is its stop, but straight is normal, not a warning)
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
	while v.z - old.z > 180.0:
		v.z -= 360.0
	while v.z - old.z < -180.0:
		v.z += 360.0
	set_ang_safe(j, v)


# ---------------------------------------------------------------- the weapon

## the bat's knob position and rotation in the world now: [Vector3, Quaternion]
func wep_xform() -> Array:
	if wep_hand != "":
		var g: Quaternion = G[wep_hand]
		return [(P[wep_hand] as Vector3) + g * wep_lpos, g * wep_lrot]
	return [wep_pos, wep_rot]


## lock the bat to a hand where it is now: from then on it keeps its place in that hand
##   lrot = G[h]^-1 * rot,   lpos = G[h]^-1 * (pos - P[h])
func lock_weapon(h: String) -> void:
	var x := wep_xform()
	wep_pos = x[0]
	wep_rot = x[1]
	var g: Quaternion = G[h]
	wep_lrot = g.inverse() * wep_rot
	wep_lpos = g.inverse() * (wep_pos - (P[h] as Vector3))
	wep_hand = h


func unlock_weapon() -> void:
	var x := wep_xform()
	wep_pos = x[0]
	wep_rot = x[1]
	wep_hand = ""


## the STANDARD grip (data/grips/metal_bat.json, fitted by Nick 10-12): the bat's place in the hand + the finger angles.
## Left hand = the mirror: x of the position flipped, rotation (x, y, z, w) -> (x, -y, -z, w), finger twist negated.
func weapon_to_hand(h: String) -> void:
	var path := "res://data/grips/metal_bat.json"
	if not FileAccess.file_exists(path):
		_weapon_to_hand_rough(h)
		return
	var g: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var lp := _v(g["local_pos"])
	var lr: Array = g["local_rot"]
	var q := Quaternion(lr[0], lr[1], lr[2], lr[3])
	var mirror: bool = h != g["hand"]
	if mirror:
		lp.x = -lp.x
		q = Quaternion(q.x, -q.y, -q.z, q.w)
	for j in g["fingers"]:
		var a: Array = g["fingers"][j]
		var jj: String = j
		var v := Vector3(a[0], a[1], a[2])
		if mirror:
			jj = j.substr(0, j.length() - 2) + h.substr(h.length() - 2)
			v.z = -v.z
		ang[jj] = clamp_ang(jj, v)
	fk()
	wep_on = true
	wep_hand = h
	wep_lpos = lp
	wep_lrot = q
	unlock_weapon()
	lock_weapon(h)


## the old rough start (no grip file): the bat through the palm, out on the thumb side, knob 6 cm below, locked
func _weapon_to_hand_rough(h: String) -> void:
	wep_on = true
	wep_hand = ""
	var g: Quaternion = G[h]
	var palm: Vector3 = (P[h] as Vector3).lerp(E[h], 0.6) + g * Vector3(0, -0.03, 0)
	var axis: Vector3 = (g * Vector3(0, 0, 1)).normalized()
	wep_rot = Quaternion(Vector3.UP, axis)
	wep_pos = palm - axis * 0.06
	lock_weapon(h)


## move the FREE bat by dp (world) and turn it by R (world) about its knob; it stops at the body like a joint does
func move_weapon(dp: Vector3, R: Quaternion) -> void:
	if wep_hand != "":
		return
	var p_old := wep_pos
	var r_old := wep_rot
	var r_new := (R * r_old).normalized()
	var pen0 := penetration()
	wep_pos = p_old + dp
	wep_rot = r_new
	if penetration() <= pen0 + 1e-4:
		return
	var lo := 0.0
	var hi := 1.0
	for i in 10:
		var m := (lo + hi) * 0.5
		wep_pos = p_old + dp * m
		wep_rot = r_old.slerp(r_new, m)
		if penetration() <= pen0 + 1e-4:
			lo = m
		else:
			hi = m
	wep_pos = p_old + dp * lo
	wep_rot = r_old.slerp(r_new, lo)


func set_weapon_len(L: float) -> void:
	wep_len = clampf(L, 0.4, 1.6)
	wep_handle = wep_len * 0.48


## a point on the bat, d metres up from the knob
func wep_point(d: float) -> Vector3:
	var x := wep_xform()
	return (x[0] as Vector3) + (x[1] as Quaternion) * Vector3(0, d, 0)


## where the other hand holds the bat
func grip_point() -> Vector3:
	return wep_point(clampf(grip_u, 0.0, wep_len))


## the other hand's wrist onto the bat: the wrist sits ~half a hand behind the grip point, back along that hand
func apply_grip() -> float:
	if not (wep_on and grip and wep_hand != ""):
		return 0.0
	var other := "hand_l" if wep_hand == "hand_r" else "hand_r"
	var back: Vector3 = ((P[other] - E[other]) as Vector3).normalized() * ((e0[other] - p0[other]) as Vector3).length() * 0.45
	return reach(other, grip_point() + back)


# ---------------------------------------------------------------- contacts

## a part's capsule now: its rest end points carried by its joint; the bat's from its own frame
func cap(part: String) -> Array:
	if part == "bat_handle":
		return [wep_point(wep_r_handle), wep_point(wep_handle)]
	if part == "bat_barrel":
		return [wep_point(wep_handle), wep_point(wep_len - wep_r_barrel)]
	var c: Array = cap0[part]
	var g: Quaternion = G[part]
	var pj: Vector3 = P[part]
	var rj: Vector3 = p0[part]
	return [pj + g * ((c[0] as Vector3) - rj), pj + g * ((c[1] as Vector3) - rj)]


## how far two capsules sink into each other (m): > 0 = inside, < 0 = the gap between them
func depth(x: String, y: String) -> float:
	var a: Array = cap(x)
	var b: Array = cap(y)
	return float(rad[x]) + float(rad[y]) - seg_seg(a[0], a[1], b[0], b[1])


## every contact now: [[part, part, depth beyond the allowance], ...]
func contacts() -> Array:
	var out := []
	for pr in pairs:
		if not wep_on and (pr[0] in WEAPON or pr[1] in WEAPON):
			continue
		var d := depth(pr[0], pr[1]) - float(allow.get(pr[0] + "|" + pr[1], 0.0))
		if d > 0.001:   # under 1 mm is touching, not inside
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
## turns the tip onto the target (turn_world). Limits and contacts apply at every step. Returns the miss (m).
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


## curl one hand's fingers to a shape: "open" | "grip" (round a bat handle) | "fist". side = "l" or "r".
## values per joint: knuckle (01), middle (02), tip (03); thumb 01 also swings across the palm.
func hand_shape(side: String, kind: String) -> void:
	var c: Array = {"open": [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO],
		"grip": [Vector3(70, 0, 0), Vector3(90, 0, 0), Vector3(50, 0, 0), Vector3(5, 0, 0), Vector3(35, 0, 0), Vector3(28, 0, 0)],
		"fist": [Vector3(90, 0, 0), Vector3(105, 0, 0), Vector3(70, 0, 0), Vector3(30, -10, 0), Vector3(60, 0, 0), Vector3(48, 0, 0)]}[kind]
	# thumbs found by search (10-12): fist = thumb tip 4 mm from the index's middle joint underside; grip = 5 mm from
	# where a 3.2 cm handle's surface sits
	for f in ["index", "middle", "ring", "pinky"]:
		for k in 3:
			var j := "%s_0%d_%s" % [f, k + 1, side]
			ang[j] = clamp_ang(j, c[k])
	for k in 3:
		var j := "thumb_0%d_%s" % [k + 1, side]
		ang[j] = clamp_ang(j, c[3 + k])
	fk()


## the lowest sole point's height above where it rests (m): heel (the ankle joint, minus its rest height) and toe tip
func sole_low() -> float:
	var low := INF
	for sd in ["_l", "_r"]:
		low = minf(low, (P["foot" + sd] as Vector3).y - (p0["foot" + sd] as Vector3).y)
		low = minf(low, (E["ball" + sd] as Vector3).y - (e0["ball" + sd] as Vector3).y)
		low = minf(low, (P["ball" + sd] as Vector3).y - (p0["ball" + sd] as Vector3).y)
	return low


## FEET ON THE FLOOR: move the hips straight up/down so the lowest sole point touches the ground
##   offset.y -= sole_low()      (a bent knee drops the body; nothing floats, nothing sinks)
func ground() -> void:
	offset.y -= sole_low()
	fk()


## FLAT FOOT: the ankle's bend that puts the toes' ball back at the heel's height difference it has at rest
## (bisection: the ball rises as the bend grows). Toes off = the toes bend so their tip touches the floor too.
func flat_foot(sd: String) -> void:
	var want: float = (p0["ball" + sd] as Vector3).y - (p0["foot" + sd] as Vector3).y
	var r: Vector2 = lim["foot" + sd]["bend"]
	var v: Vector3 = ang["foot" + sd]
	var lo := r.x
	var hi := r.y
	for k in 16:
		var m := (lo + hi) * 0.5
		ang["foot" + sd] = Vector3(m, v.y, v.z)
		fk()
		if (P["ball" + sd] as Vector3).y - (P["foot" + sd] as Vector3).y > want:
			hi = m
		else:
			lo = m
	ang["foot" + sd] = Vector3((lo + hi) * 0.5, v.y, v.z)
	fk()


## ON THE TOES: heel up, the toes bend back so they lie flat on the floor (the back foot of a lunge)
func toes_flat(sd: String) -> void:
	var r: Vector2 = lim["ball" + sd]["bend"]
	var lo := r.x
	var hi := r.y
	var want: float = (e0["ball" + sd] as Vector3).y - (p0["ball" + sd] as Vector3).y
	for k in 16:
		var m := (lo + hi) * 0.5
		ang["ball" + sd] = Vector3(m, 0, 0)
		fk()
		if (E["ball" + sd] as Vector3).y - (P["ball" + sd] as Vector3).y > want:
			hi = m
		else:
			lo = m
	ang["ball" + sd] = Vector3((lo + hi) * 0.5, 0, 0)
	fk()


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


## the glTF node's local rotation for this pose: W[j] = G[j] * W0[j] -> L[j] = W0[parent]^-1 * A[j] * W0[j]
func gltf_local(j: String) -> Quaternion:
	var w0: Quaternion = rest_rot[j]
	var A := compose(j, ang[j])
	if parent[j] == "":
		return root_rot.inverse() * A * w0
	return (rest_rot[parent[j]] as Quaternion).inverse() * A * w0


## the pelvis's local position for this pose (its parent is the "root" bone): Wroot^-1 * (P - root position)
func gltf_pelvis_pos() -> Vector3:
	return root_rot.inverse() * (P["pelvis"] - root_pos)


func mirror_side(from_side: String) -> void:
	var to_side := "_l" if from_side == "_r" else "_r"
	for j in ORDER:
		if j.ends_with(from_side):
			var v: Vector3 = ang[j]
			var o: String = j.substr(0, j.length() - 2) + to_side
			ang[o] = clamp_ang(o, Vector3(v.x, v.y, -v.z))
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
	var w := {}
	if wep_on:
		var x := wep_xform()
		w = {"kind": "metal_bat", "length": wep_len, "hand": wep_hand, "knob": _p(x[0]), "tip": _p(wep_point(wep_len)),
			"rot": _q(x[1]), "local_pos": _p(wep_lpos), "local_rot": _q(wep_lrot), "two_hand_grip": grip, "grip_m": grip_u}
	return {"offset": _p(offset), "joints": joints, "weapon": w, "contacts": con}


func from_dict(d: Dictionary) -> void:
	var o: Array = d.get("offset", [0, 0, 0])
	offset = _v(o)
	for j in ORDER:
		ang[j] = Vector3.ZERO
	for j in d["joints"]:
		if not lim.has(j):
			continue
		var x: Dictionary = d["joints"][j]
		ang[j] = clamp_ang(j, Vector3(x["bend"], x["side"], x["twist"]))
	fk()
	var w: Dictionary = d.get("weapon", {})
	wep_on = not w.is_empty()
	if wep_on:
		set_weapon_len(float(w.get("length", wep_len)))
		var r: Array = w["rot"]
		wep_rot = Quaternion(r[0], r[1], r[2], r[3])
		wep_pos = _v(w["knob"])
		wep_hand = w.get("hand", "")
		var lr: Array = w.get("local_rot", [0, 0, 0, 1])
		wep_lrot = Quaternion(lr[0], lr[1], lr[2], lr[3])
		wep_lpos = _v(w.get("local_pos", [0, 0, 0]))
		grip = bool(w.get("two_hand_grip", false))
		grip_u = float(w.get("grip_m", grip_u))


static func _q(q: Quaternion) -> Array:
	return [snappedf(q.x, 0.00001), snappedf(q.y, 0.00001), snappedf(q.z, 0.00001), snappedf(q.w, 0.00001)]


static func _p(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]
