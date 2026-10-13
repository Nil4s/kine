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
## extra capsules for the WIDE parts the spine capsules miss (the mannequin's chest + shoulders and hips are wider than
## deep): [the joint they ride on, end a, end b (rest positions, m), radius]. Tested against the bat and the forearms
## and hands only (the upper arms grow out of them).
const WIDE := {
	"chest_wide": ["spine_03", Vector3(-0.12, 1.34, -0.01), Vector3(0.12, 1.34, -0.01), 0.11],
	"hips_wide": ["pelvis", Vector3(-0.09, 0.93, -0.01), Vector3(0.09, 0.93, -0.01), 0.12],
}
const WIDE_VS := ["bat_handle", "bat_barrel", "lowerarm_r", "lowerarm_l", "hand_r", "hand_l"]

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
var fast := false      # true while a scene plays: set_ang_safe skips the contact bisection (10-13: 300 ms -> ~ms a frame)
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
	# the shoulder joint itself sits inside the chest (the ball of the shoulder is part of the trunk's shape): the
	# upper arm's capsule starts 8 cm down the arm, so an arm brought forward or across isn't "in the chest" at its root
	for sd in ["_r", "_l"]:
		var ca: Array = cap0["upperarm" + sd]
		var dirv: Vector3 = ((ca[1] as Vector3) - (ca[0] as Vector3)).normalized()
		cap0["upperarm" + sd] = [(ca[0] as Vector3) + dirv * 0.08, ca[1]]
	for w in WIDE:
		cap0[w] = [WIDE[w][1], WIDE[w][2]]
		rad[w] = WIDE[w][3]
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
	for w in WIDE:
		for y in WIDE_VS:
			pairs.append([w, y])
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


## AIM THE BAT: turn the holding hand (inside its limits) so the bat's axis (knob -> tip) points along `dir`.
##   R = the shortest turn from the axis now to dir;  turn_world(hand, R), clamped.
## Then the upper arm's roll (searched in 5 deg steps) does what the wrist couldn't. 4 rounds. Returns the angle left (deg).
func aim_weapon(dir: Vector3) -> float:
	if not wep_on or wep_hand == "":
		return 180.0
	var h := wep_hand
	var ua := "upperarm" + h.substr(h.length() - 2)
	dir = dir.normalized()
	for it in 4:
		var ax: Vector3 = ((wep_xform()[1] as Quaternion) * Vector3.UP).normalized()
		var c := ax.cross(dir)
		if c.length() > 1e-6:
			turn_world(h, Quaternion(c.normalized(), ax.angle_to(dir)))
		var v: Vector3 = ang[ua]
		var best := 0.0
		var e_best := ((wep_xform()[1] as Quaternion) * Vector3.UP).angle_to(dir)
		for k in 25:
			var tw := -60.0 + k * 5.0
			set_ang(ua, v + Vector3(0, 0, tw))
			var e := ((wep_xform()[1] as Quaternion) * Vector3.UP).angle_to(dir)
			if e < e_best - 1e-4:
				e_best = e
				best = tw
		set_ang(ua, v)
		if best != 0.0:
			set_ang_safe(ua, v + Vector3(0, 0, best))
	var ax2: Vector3 = ((wep_xform()[1] as Quaternion) * Vector3.UP).normalized()
	return rad_to_deg(ax2.angle_to(dir))


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
	var jn: String = WIDE[part][0] if WIDE.has(part) else part
	var g: Quaternion = G[jn]
	var pj: Vector3 = P[jn]
	var rj: Vector3 = p0[jn]
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
		# both hands on one handle touch by nature (their capsules include the fingers wrapped round it)
		if wep_on and grip and pr[0].begins_with("hand") and pr[1].begins_with("hand"):
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
	if fast:
		set_ang(j, v)   # playback: limits only (the cook already checked contacts frame by frame)
		return true
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
			fk_some([mid, tip])   # only the elbow/knee and the tip move here
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


## SEARCH: coordinate descent on the joints in `js` (each free angle), minimising cost.call() + 10 * the body's new
## penetration (m). Steps 16, 8, 4, 2, 1 deg; a step is kept only if it lowers the total. Limits hold (set_ang clamps).
func search(js: Array, cost: Callable, pen0 := -1.0) -> float:
	if pen0 < 0.0:
		pen0 = penetration()
	var total := func() -> float:
		return float(cost.call()) + 10.0 * maxf(0.0, penetration() - pen0)
	var best: float = total.call()
	for st in [16.0, 8.0, 4.0, 2.0, 1.0]:
		var better := true
		var guard := 0
		while better and guard < 30:
			better = false
			guard += 1
			for j in js:
				for k in 3:
					var r: Vector2 = lim[j][["bend", "side", "twist"][k]]
					if r.y - r.x < 0.5:
						continue
					for sgn in [1.0, -1.0]:
						var v: Vector3 = ang[j]
						var dv := Vector3.ZERO
						dv[k] = st * sgn
						set_ang(j, v + dv)
						var c: float = total.call()
						if c < best - 1e-5:
							best = c
							better = true
						else:
							ang[j] = v
							fk()
	return best


## FK for a few joints only (an arm), parents first: the same math as fk(), for fast sweeps
func fk_some(js: Array) -> void:
	for j in js:
		var A := compose(j, ang[j])
		var pj: String = parent[j]
		G[j] = G[pj] * A
		P[j] = P[pj] + G[pj] * (p0[j] - p0[pj])
		E[j] = P[j] + G[j] * (e0[j] - p0[j])


## SWEEP THE BAT ARM: every upper arm (bend, side, roll every 20 deg), elbow (every 20) and forearm turn (the hand's
## twist, every 30 to +-60: pronation is not a wrist fold), the wrist itself straight; score = |wrist - at| + 0.15 * angle(bat, dir) [rad]. The best few
## are then refined by search() with the body's contacts counted. Bat direction comes from the arm, never from a
## folded wrist (Nick 10-12: "keep hand straight w forearm").
func sweep_bat_arm(at: Vector3, dir: Vector3, use_at := true, use_dir := true, aw := 0.15) -> float:
	var h := wep_hand
	var sd := h.substr(h.length() - 2)
	var ua := "upperarm" + sd
	var la := "lowerarm" + sd
	var chain := [ua, la, h]
	dir = dir.normalized()
	var lu: Dictionary = lim[ua]
	var ll: Dictionary = lim[la]
	var keep := ang.duplicate()
	var ou := "upperarm" + ("_l" if sd == "_r" else "_r")
	var best := []   # [score, ua, la, hand]
	# the pairs this arm or the bat take part in (the rest of the body doesn't move while sweeping)
	var mine := [ua, la, h] + WEAPON
	var prs := []
	for pr in pairs:
		if (pr[0] in mine) != (pr[1] in mine):
			prs.append([pr[0], pr[1], float(allow.get(pr[0] + "|" + pr[1], 0.0))])
	var b: float = lu["bend"].x
	while b <= lu["bend"].y:
		var sv: float = lu["side"].x
		while sv <= lu["side"].y:
			var t: float = lu["twist"].x
			while t <= lu["twist"].y:
				ang[ua] = Vector3(b, sv, t)
				var e: float = ll["bend"].x
				while e <= ll["bend"].y:
					ang[la] = Vector3(e, 0, 0)
					for ht in [-60.0, -30.0, 0.0, 30.0, 60.0]:
						for hs in [0.0]:
							ang[h] = Vector3(0, hs, ht)
							fk_some(chain)
							var c := 0.0
							if use_at:
								c += ((P[h] - at) as Vector3).length()
							if use_dir:
								c += aw * wep_axis().angle_to(dir)
							for pr in prs:
								c += 10.0 * maxf(0.0, depth(pr[0], pr[1]) - pr[2] - 0.001)
							if grip:
								# two hands: the other hand has to reach the handle (its arm is ~0.49 m long)
								c += 2.0 * maxf(0.0, (grip_point() - (P[ou] as Vector3)).length() - 0.42)
							if best.size() < 6 or c < best[-1][0]:
								best.append([c, ang[ua], ang[la], ang[h]])
								best.sort_custom(func(x, y): return x[0] < y[0])
								if best.size() > 6:
									best.pop_back()
					e += 20.0
				t += 20.0
			sv += 20.0
		b += 20.0
	# refine the best few with contacts counted (every contact, from zero: the pose before may already be inside);
	# the lowest total wins
	var pen0 := 0.0
	var cost := func() -> float:
		var c := 0.0
		if use_at:
			c += ((P[h] - at) as Vector3).length()
		if use_dir:
			c += aw * wep_axis().angle_to(dir)
		if grip:
			# cheap: the handle within the other arm's reach (solving that arm here made a cook take 25+ min)
			c += 2.0 * maxf(0.0, (grip_point() - (P[ou] as Vector3)).length() - 0.42)
		return c
	var won := {}
	var won_c := INF
	var keep_lim: Dictionary = lim[h].duplicate()
	lim[h]["bend"] = Vector2(-15, 15)
	lim[h]["side"] = Vector2(-20, 20)
	lim[h]["twist"] = Vector2(-60, 60)
	for cand in best:
		ang = keep.duplicate()
		ang[ua] = cand[1]
		ang[la] = cand[2]
		ang[h] = cand[3]
		fk()
		var c := search([ua, la, h, "clavicle" + sd], cost, pen0)
		if c < won_c:
			won_c = c
			won = ang.duplicate()
	lim[h] = keep_lim
	ang = won
	fk()
	return won_c


## the bat's axis now (knob -> tip, unit)
func wep_axis() -> Vector3:
	return ((wep_xform()[1] as Quaternion) * Vector3.UP).normalized()


## where the free hand's wrist should be to hold the handle (as apply_grip aims it)
func grip_wrist() -> Vector3:
	var other := "hand_l" if wep_hand == "hand_r" else "hand_r"
	var back: Vector3 = ((P[other] - E[other]) as Vector3).normalized() * ((e0[other] - p0[other]) as Vector3).length() * 0.45
	return grip_point() + back


## HOLD THE BAT: both arms searched together so the bat hand's wrist is at `at`, the bat points along `dir` and (two
## hands) the free wrist is on the handle. cost = |wrist - at| + 0.06 * angle(axis, dir) [rad] + |free wrist - grip|.
## Returns [wrist miss m, aim off deg, free hand miss m].
func hold_bat(at: Vector3, dir: Vector3, use_at := true, use_dir := true) -> Array:
	var h := wep_hand
	var sd := h.substr(h.length() - 2)
	var od := "_l" if sd == "_r" else "_r"
	# the WRIST STAYS STRAIGHT with the forearm (Nick: that is what makes a swing look natural; the game skin has no
	# forearm twist bones either): the bat is aimed by the shoulder, the elbow and the upper arm's roll only
	# A wrist may cock a little, like a batter's: bend +-15, side (radial/ulnar) +-20, no roll. Never the 90 deg folds.
	var keep_lim := {}
	for hh in ["hand" + sd, "hand" + od]:
		keep_lim[hh] = lim[hh].duplicate()
		lim[hh]["bend"] = Vector2(-15, 15)
		lim[hh]["side"] = Vector2(-20, 20)
		lim[hh]["twist"] = Vector2(0, 0)
		ang[hh] = clamp_ang(hh, ang[hh])
	var js := ["upperarm" + sd, "lowerarm" + sd, "hand" + sd, "clavicle" + sd]
	if grip:
		js += ["upperarm" + od, "lowerarm" + od, "hand" + od, "clavicle" + od]
	fk()
	dir = dir.normalized()
	var cost := func() -> float:
		var c := 0.0
		if use_at:
			c += ((P[h] - at) as Vector3).length()
		if use_dir:
			c += 0.06 * wep_axis().angle_to(dir)   # the bat's direction only breaks ties: the arm's path leads
		if grip:
			c += ((P["hand" + od] - grip_wrist()) as Vector3).length()
		return c
	# two starts: as the arms are now, and both arms out in front of the chest (elbows bent) - a hand crossing the body
	# can't get round the belly from the side by small steps. The lower cost wins.
	var keep := ang.duplicate()
	var pen0 := penetration()
	var c1 := search(js, cost, pen0)
	var won := ang.duplicate()
	ang = keep.duplicate()
	for s2 in [sd, od] if grip else [sd]:
		ang["upperarm" + s2] = clamp_ang("upperarm" + s2, Vector3(55, -35, 0))
		ang["lowerarm" + s2] = clamp_ang("lowerarm" + s2, Vector3(70, 0, 0))
	fk()
	var c2 := search(js, cost, pen0)
	if c1 < c2:
		ang = won
		fk()
	for hh in keep_lim:
		lim[hh] = keep_lim[hh]
	var gm := ((P["hand" + od] - grip_wrist()) as Vector3).length() if grip else 0.0
	return [((P[h] - at) as Vector3).length() if use_at else 0.0, rad_to_deg(wep_axis().angle_to(dir)) if use_dir else 0.0, gm]


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
		fk_some(["foot" + sd, "ball" + sd])
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
		fk_some(["ball" + sd])
		if (E["ball" + sd] as Vector3).y - (P["ball" + sd] as Vector3).y > want:
			hi = m
		else:
			lo = m
	ang["ball" + sd] = Vector3((lo + hi) * 0.5, 0, 0)
	fk()


## where a foot points on the floor (radians about up; 0 = +z)
func foot_heading(sd: String) -> float:
	var d: Vector3 = P["ball" + sd] - P["foot" + sd]
	return atan2(d.x, d.z)


## [ball (toe base) position, heading, toe base on the floor?, heel on the floor?]
func foot_state(sd: String) -> Array:
	var b: Vector3 = P["ball" + sd]
	var on := b.y - (p0["ball" + sd] as Vector3).y < 0.02
	var heel := (P["foot" + sd] as Vector3).y - (p0["foot" + sd] as Vector3).y < 0.02
	return [b, foot_heading(sd), on, heel]


## PLANT A FOOT: the leg alone (thigh, knee, ankle) puts the toe base at `ball_at`, pointing `head`.
##   loop: (flat foot) -> reach the ankle to ball_at - (ball - ankle) -> turn the thigh about its length by Newton's
##   step  dtwist = -err / (d err / d twist)  so the foot points where it pointed (flat feet only; a heel-up foot
##   pivots on its ball). Returns the miss (m).
func plant(sd: String, ball_at: Vector3, head: float, flat: bool) -> float:
	var th := "thigh" + sd
	for it in 5:
		if flat:
			flat_foot(sd)
		var d: Vector3 = P["ball" + sd] - P["foot" + sd]
		reach("foot" + sd, ball_at - d)
		# a heel-up back foot pivots with the hips: its knee follows the hips' facing, not its own foot (that chases itself)
		var hf: Vector3 = (G["pelvis"] as Quaternion) * Vector3(0, 0, 1)
		knee_over_toes(sd, head if flat else atan2(hf.x, hf.z))
	return ((P["ball" + sd] - ball_at) as Vector3).length()


## KNEE OVER THE TOES: swing the whole leg about the hip -> ankle line (the ankle stays put) until the knee points the
## way the foot points.  u = (ankle - hip)/|..|,  k = knee dir without its u part,  want = heading without its u part,
## angle = atan2(u . (k x want), k . want),  turn_world(thigh, rotation(u, angle)).
func knee_over_toes(sd: String, head: float) -> void:
	var th := "thigh" + sd
	var H: Vector3 = P[th]
	var u: Vector3 = ((P["foot" + sd] - H) as Vector3).normalized()
	var k: Vector3 = (P["calf" + sd] as Vector3) - H
	k -= u * u.dot(k)
	var w := Vector3(sin(head), 0.0, cos(head))
	w -= u * u.dot(w)
	if k.length() < 0.01 or w.length() < 0.01:
		return   # a straight leg has no knee direction to fix
	k = k.normalized()
	w = w.normalized()
	var a := atan2(u.dot(k.cross(w)), k.dot(w))
	turn_world(th, Quaternion(u, a))


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
