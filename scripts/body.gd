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
## THE OFF-HAND WEAPON (round 33, Nick 10-16: "double dagger"): always held, in the hand the main weapon is not in
const WEAPON2 := ["wep2_handle", "wep2_blade"]
## extra capsules for the WIDE parts the spine capsules miss (the mannequin's chest + shoulders and hips are wider than
## deep): [the joint they ride on, end a, end b (rest positions, m), radius]. Tested against the bat and the forearms
## and hands only (the upper arms grow out of them).
const WIDE := {
	"chest_wide": ["spine_03", Vector3(-0.12, 1.34, -0.01), Vector3(0.12, 1.34, -0.01), 0.11],
	"hips_wide": ["pelvis", Vector3(-0.09, 0.93, -0.01), Vector3(0.09, 0.93, -0.01), 0.12],
}
const WIDE_VS := ["bat_handle", "bat_barrel", "wep2_handle", "wep2_blade", "lowerarm_r", "lowerarm_l", "hand_r", "hand_l"]

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
## SKIN test (Nick 10-13: a hand flat on the chest and a forearm in the belly passed the capsules). The chest and hips
## are flat ovals a capsule can't follow (their skin sits 3-4 cm outside the capsules: tools/mesh_fit.gd), so the
## trunk + head are ALSO tested as their real skin points (data/skin_points.json, one per 2.5 cm) against these parts.
const SKIN_VS := ["lowerarm_r", "lowerarm_l", "hand_r", "hand_l", "bat_handle", "bat_barrel", "wep2_handle", "wep2_blade"]
const SKIN_HAND_PAD := 0.01   # the knuckles and finger tips sit ~1 cm outside the hand capsule (tools/mesh_truth.gd found
                              # fingers in the thighs the capsule passed)
var skin := {}          # trunk/head part -> [rest skin points]
var skin_c := {}        # part -> [rest centre, bound radius] of its points (culls far capsules)
var allow := {}        # "x|y" -> how deep that pair already sits in the body's neutral poses (m)
var ang := {}          # joint -> Vector3(bend, side, twist) degrees  (THE POSE)
var offset := Vector3.ZERO   # pelvis moved from rest (metres)
var props: Array = []        # THE SET (round 38, TT2): the scene's props (Scene._ground sets it); grounding stands on them
const SEAT_PARTS := ["hips_wide", "thigh_l", "thigh_r"]   # what sits: lifted onto a seat they sink into
const SEAT_CATCH := 0.15     # a seat catches a part whose lowest surface is less than this below its top (deeper: through)

# the weapon. Its own frame: the butt end (the bat's knob) at the origin, the shaft along its +Y to the tip.
## KINDS (Nick 10-13: "a long bat so I can position hands on a long hammer or a staff; Ghost is kind of a ninja"):
##   len m, handle = where the shaft's first capsule ends (m from the butt, <0 = len + it), r_handle / r_barrel = radii,
##   head = [half width across, radius] for a hammer head set ACROSS the shaft at the tip ([] = none), aim = the AIM rule
##   applies (a staff is held in the middle and both ends strike: pointing one end back past you is how it's held),
##   grip = how the hand closes on it (GripWrap.TYPES, round 47 CC2: power across the palm; diagonal, the thumb along it)
const KINDS := {
	"metal_bat": {"len": 0.84, "handle": 0.40, "r_handle": 0.016, "r_barrel": 0.033, "head": [], "aim": true, "grip": "power"},
	"staff": {"len": 1.80, "handle": 0.90, "r_handle": 0.016, "r_barrel": 0.016, "head": [], "aim": false, "grip": "power"},
	"long_hammer": {"len": 1.10, "handle": -0.06, "r_handle": 0.017, "r_barrel": 0.045, "head": [0.12, 0.045], "aim": true, "grip": "power"},
	"dagger": {"len": 0.30, "handle": 0.11, "r_handle": 0.013, "r_barrel": 0.011, "head": [], "aim": true, "grip": "diagonal"},
	## round 45 (AA3, Nick 10-18's video: "a Viking with a double headed axe"): a Dane axe's combat haft is "between
	## approx. 0.9 and 1.2 m", its cutting edge "generally between 20 and 30 cm", 1-2 kg (en.wikipedia.org/wiki/Dane_axe,
	## read 10-18). The long end of the haft; a bit each side of the tip, 15 cm out, 6 cm round (a 12 cm edge drawn as a
	## capsule: the head is a stand-in shape, the length and the reach are the reference's)
	"long_axe": {"len": 1.20, "handle": -0.10, "r_handle": 0.017, "r_barrel": 0.017, "head": [0.15, 0.06], "aim": true, "grip": "power"},
}
var wep_kind := "metal_bat"
## the SECOND hand's fitted grip for this kind (data/grips/<kind>.json "second", from Nick's pose by
## tools/grip_from_pose.gd): its wrist + turn in the weapon's frame, its fingers. G then puts that hand on the
## shaft exactly so, slid to grip_u. {} = the old rough wrist-behind-the-grip-point reach.
var grip2 := {}
var wep_head := []          # [half width, radius] of a hammer head across the tip, or []
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
## the off-hand weapon: locked in wep2_hand (pos = P[h] + G[h] * wep2_lpos, rot = G[h] * wep2_lrot), a dagger
var wep2_on := false
var wep2_kind := "dagger"
var wep2_hand := "hand_l"
var wep2_lpos := Vector3.ZERO
var wep2_lrot := Quaternion.IDENTITY

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
	rad["wep2_handle"] = float(KINDS["dagger"]["r_handle"])
	rad["wep2_blade"] = float(KINDS["dagger"]["r_barrel"])
	fk()
	# contact pairs: body part vs body part (not a part and its own parent/child; fingers are left out: they wrap
	# round things), and the bat vs the body (not the hands: they hold it).
	var names: Array = BODY + WEAPON + WEAPON2
	for i in names.size():
		for k in range(i + 1, names.size()):
			var x: String = names[i]
			var y: String = names[k]
			if parent.get(x, "") == y or parent.get(y, "") == x:
				continue
			if is_wep(x) and is_wep(y):   # weapon on weapon is a clash, not the body
				continue
			if (is_wep(x) and y in ["hand_r", "hand_l"]) or (is_wep(y) and x in ["hand_r", "hand_l"]):
				continue
			pairs.append([x, y])
	for w in WIDE:
		for y in WIDE_VS:
			pairs.append([w, y])
	# A pair may already overlap in the body's NEUTRAL poses (the shoulder sits in the chest, a hanging arm rests on
	# the thigh): that much (+2 mm) is its allowance; a contact = sinking deeper. The bat is put away while measuring.
	var keep_on := wep_on
	var keep_on2 := wep2_on
	wep_on = false
	wep2_on = false
	var calib := [{}, {"upperarm_r": Vector3(0, -90, 0), "upperarm_l": Vector3(0, -90, 0)},
		{"upperarm_r": Vector3(0, -95, 0), "upperarm_l": Vector3(0, -95, 0)}]
	if FileAccess.file_exists("res://data/skin_points.json"):
		var sp: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/skin_points.json"))
		for part in sp:
			var pts := []
			var c := Vector3.ZERO
			for q in sp[part]:
				pts.append(Vector3(q[0], q[1], q[2]))
				c += pts[-1]
			c /= maxf(1.0, pts.size())
			var r := 0.0
			for q in pts:
				r = maxf(r, (q - c).length())
			skin[part] = pts
			skin_c[part] = [c, r]
	for pose in calib:
		for j in ORDER:
			ang[j] = pose.get(j, Vector3.ZERO)
		fk()
		for sc in skin_raw():
			if not is_wep(sc[1]):
				var sk_key: String = "skin:" + sc[0] + "|" + sc[1]
				allow[sk_key] = maxf(allow.get(sk_key, 0.0), float(sc[2]) + 0.002)
		for pr in pairs:
			if is_wep(pr[0]) or is_wep(pr[1]):
				continue
			var key: String = pr[0] + "|" + pr[1]
			allow[key] = maxf(allow.get(key, 0.0), depth(pr[0], pr[1]) + 0.002)
	# THE GIRDLE AT PEOPLE'S MEASURED EXTREME (round 43, YY5): the clavicle capsule starts at the sternum under the neck
	# and sits 3.2 cm inside the neck capsule at rest, so ANY shrug read as "contact" (10 up: 2 mm into the head; 15
	# back: 8 mm into the neck). People raise the clavicle ~10 and draw it back ~21 with nothing touching (McClure et al.
	# 2001, bone pins, 8 people), so that pose is neutral too: for the CLAVICLE's pairs only, the arms hanging and out
	for arm in [Vector3.ZERO, Vector3(0, -90, 0)]:
		for j in ORDER:
			ang[j] = Vector3.ZERO
		for sd in ["_r", "_l"]:
			ang["upperarm" + sd] = arm
			ang["clavicle" + sd] = clamp_ang("clavicle" + sd, Vector3(FOLLOW_ELEV, -FOLLOW_RETRACT, 0))
		fk()
		for pr in pairs:
			if (pr[0].begins_with("clavicle") or pr[1].begins_with("clavicle")) and not (is_wep(pr[0]) or is_wep(pr[1])):
				var key: String = pr[0] + "|" + pr[1]
				allow[key] = maxf(allow.get(key, 0.0), depth(pr[0], pr[1]) + 0.002)
	for j in ORDER:
		ang[j] = Vector3.ZERO
	wep_on = keep_on
	wep2_on = keep_on2
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
	# the angle from the VECTOR part (2 atan2(|v|, w)), not 2 acos(w): near w = 1 acos is ill-conditioned in float32 and
	# lost every swing under ~0.05 deg (round 41, WW7's finding; tests/decompose_test.gd)
	var v := Vector3(qs.x, qs.y, qs.z)
	var vl := v.length()
	var rv := Vector3.ZERO
	if vl > 1e-12:
		rv = v / vl * (2.0 * atan2(vl, qs.w))
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
	fk_sub(j)


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

static func is_wep(part: String) -> bool:
	return part in WEAPON or part in WEAPON2


## the off-hand weapon's butt position and rotation now
func wep2_xform() -> Array:
	var g: Quaternion = G[wep2_hand]
	return [(P[wep2_hand] as Vector3) + g * wep2_lpos, g * wep2_lrot]


func wep2_point(d: float) -> Vector3:
	var x := wep2_xform()
	return (x[0] as Vector3) + (x[1] as Quaternion) * Vector3(0, d, 0)


func wep2_len() -> float:
	return float(KINDS[wep2_kind]["len"])


## the off-hand weapon into hand h with the standard grip (the grip file's, mirrored to h as weapon_to_hand does)
func wep2_to_hand(h: String) -> void:
	var path := "res://data/grips/dagger.json"
	if not FileAccess.file_exists(path):
		path = "res://data/grips/metal_bat.json"
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
	wep2_on = true
	wep2_hand = h
	wep2_lpos = lp
	wep2_lrot = q
	fk()


## the off-hand weapon as plain data (cards: "weapon2"; {} = none)
func wep2_dict() -> Dictionary:
	if not wep2_on:
		return {}
	var x := wep2_xform()
	return {"kind": wep2_kind, "hand": wep2_hand, "knob": _p(x[0]), "tip": _p(wep2_point(wep2_len())),
		"rot": _q(x[1]), "local_pos": _p(wep2_lpos), "local_rot": _q(wep2_lrot)}


## a card's "weapon2" in the sampler's shape: {hand, kind, local_pos, local_rot} or {}
static func wep2_flat(w: Dictionary) -> Dictionary:
	if w.is_empty():
		return {}
	var lp: Array = w.get("local_pos", [0, 0, 0])
	var lr: Array = w.get("local_rot", [0, 0, 0, 1])
	return {"hand": String(w.get("hand", "hand_l")), "kind": String(w.get("kind", "dagger")),
		"local_pos": Vector3(lp[0], lp[1], lp[2]), "local_rot": Quaternion(lr[0], lr[1], lr[2], lr[3])}


## between two cards: in the same hand -> its place in the hand blends; otherwise the nearer card's (as the bat)
static func wep2_mix(a: Dictionary, b: Dictionary, e: float) -> Dictionary:
	if a.is_empty() or b.is_empty() or a["hand"] != b["hand"]:
		return a if e < 0.5 else b
	var w := a.duplicate()
	w["local_pos"] = (a["local_pos"] as Vector3).lerp(b["local_pos"], e)
	w["local_rot"] = (a["local_rot"] as Quaternion).slerp(b["local_rot"], e)
	return w


## a sampled off-hand weapon into the body ({} = none)
func put_wep2(w: Dictionary) -> void:
	wep2_on = not w.is_empty()
	if wep2_on:
		wep2_kind = w["kind"]
		wep2_hand = w["hand"]
		wep2_lpos = w["local_pos"]
		wep2_lrot = w["local_rot"]

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
	var path := "res://data/grips/%s.json" % wep_kind
	if not FileAccess.file_exists(path):
		path = "res://data/grips/metal_bat.json"   # the same hand round a shaft until Nick fits this kind's own
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
	var own: bool = path.ends_with("/%s.json" % wep_kind)
	grip2 = g.get("second", {}) if own and String(g.get("hand", "")) == h else {}
	if not grip2.is_empty():
		grip = true
		grip_u = float(grip2["u"])
		apply_grip()
	elif own and float(g.get("other_hand_m", -1.0)) >= 0.0:
		grip = true
		grip_u = float(g["other_hand_m"])
	elif not own and wep_kind == "staff":
		# no staff grip fitted yet: the bat hand a third of the way up, the other hand on at two thirds
		grip_u = 0.0
		slide_in_hand(0.6)
		grip = true
		grip_u = 1.2
	elif not own and wep_kind in ["long_hammer", "long_axe"]:
		# no hammer / axe grip yet: the bat hand at the butt, the other hand 40 cm up (a sledge hold)
		grip = true
		grip_u = 0.4


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
	wep_len = clampf(L, 0.2, 2.2)   # 0.2: the dagger (0.30 m) is the shortest kind
	var k: Dictionary = KINDS[wep_kind]
	var hh: float = k["handle"]
	wep_handle = (wep_len + hh) if hh < 0.0 else wep_len * hh / float(k["len"])


## switch the weapon: its size, radii, head (the grip stays: the hand holds the shaft the same way)
func set_kind(kind: String) -> void:
	if not KINDS.has(kind):
		return
	wep_kind = kind
	grip2 = {}
	var k: Dictionary = KINDS[kind]
	wep_r_handle = k["r_handle"]
	wep_r_barrel = k["r_barrel"]
	wep_head = k["head"]
	rad["bat_handle"] = wep_r_handle
	rad["bat_barrel"] = wep_r_barrel if wep_head.is_empty() else float(wep_head[1])
	set_weapon_len(k["len"])
	grip_u = clampf(grip_u, 0.0, wep_len)


## slide the weapon in the bat hand: + = the hand moves toward the tip (the butt sticks out further behind it)
func slide_in_hand(d: float) -> void:
	if wep_hand == "":
		return
	wep_lpos += wep_lrot * Vector3(0, -d, 0)
	grip_u = clampf(grip_u + d, 0.0, wep_len)


## where the bat hand holds the shaft (m from the butt)
func hold_u() -> float:
	if wep_hand == "":
		return 0.0
	# the hand's centre seen in the weapon frame
	var x := wep_xform()
	return ((x[1] as Quaternion).inverse() * ((P[wep_hand] as Vector3) - (x[0] as Vector3))).y


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
	if not grip2.is_empty() and String(grip2.get("hand", "")) == other:
		return _fit_second(other)
	var back: Vector3 = ((P[other] - E[other]) as Vector3).normalized() * ((e0[other] - p0[other]) as Vector3).length() * 0.45
	return reach(other, grip_point() + back)


## the second hand into its fitted grip: wrist on its spot (slid along the shaft to grip_u) AND the hand turned
## round the shaft as Nick held it. Skipped when already within 1 cm and 8 deg (dragging stays fast). Returns the miss (m).
func _fit_second(h: String) -> float:
	var x := wep_xform()
	var q: Quaternion = x[1]
	var lp := _v(grip2["lpos"]) + Vector3(0, grip_u, 0)
	var target: Vector3 = (x[0] as Vector3) + q * lp
	var lr: Array = grip2["lrot"]
	var want: Quaternion = (q * Quaternion(lr[0], lr[1], lr[2], lr[3])).normalized()
	for j in grip2["fingers"]:
		var a: Array = grip2["fingers"][j]
		ang[j] = clamp_ang(j, Vector3(a[0], a[1], a[2]))
	if (P[h] as Vector3).distance_to(target) < 0.01 and rad_to_deg((G[h] as Quaternion).angle_to(want)) < 8.0:
		return (P[h] as Vector3).distance_to(target)
	return fit_hand(h, target, want)


## LOCK BOTH HANDS (Nick 10-13: "it still doesn't lock both hands on the bo when I press lock, only one arm keeps
## holding it"). If the other hand is on the shaft now (palm within 5 cm of its axis), its grip AS IT IS becomes the
## second grip (wrist + turn in the weapon's frame, fingers, place along the shaft) and G is switched on: from then on
## it holds the weapon as the body moves. Returns the palm's distance from the axis (m), or -1 with no weapon in a hand.
func capture_second() -> float:
	if not wep_on or wep_hand == "":
		return -1.0
	var o := "hand_l" if wep_hand == "hand_r" else "hand_r"
	var x := wep_xform()
	var q: Quaternion = x[1]
	var k: Vector3 = x[0]
	var palm: Vector3 = (P[o] as Vector3).lerp(E[o], 0.6) + (G[o] as Quaternion) * Vector3(0, -0.03, 0)
	var pl := q.inverse() * (palm - k)
	var off := Vector2(pl.x, pl.z).length()
	if off > 0.05 or pl.y < 0.0 or pl.y > wep_len:
		return off
	var wl := q.inverse() * ((P[o] as Vector3) - k)
	var fing := {}
	for j in FINGERS:
		if j.ends_with(o.right(2)):
			var v: Vector3 = ang[j]
			fing[j] = [snappedf(v.x, 0.1), snappedf(v.y, 0.1), snappedf(v.z, 0.1)]
	grip2 = {"hand": o, "u": snappedf(pl.y, 0.001), "lpos": _p(wl - Vector3(0, pl.y, 0)),
		"lrot": _q((q.inverse() * (G[o] as Quaternion)).normalized()), "fingers": fing}
	grip = true
	grip_u = pl.y
	return off


## SLIDE THE MAIN HAND ALONG THE SHAFT, THE BODY FOLLOWS (Nick 10-13: "slide the hand on the weapon and the body
## already adjusts, after the grip too"). The weapon stays where it is in the world; the bat hand's wrist moves d m
## along the shaft (+ = toward the tip) keeping its turn round it; the arm is re-fitted to get there (fit_hand), the
## second hand (G) re-fits to the weapon that hasn't moved. If the arm can't get there (> 1.5 cm short) nothing
## changes and it returns false.
func slide_hand(d: float) -> bool:
	if not wep_on or wep_hand == "":
		return false
	var h := wep_hand
	var x := wep_xform()
	var q: Quaternion = x[1]
	var knob: Vector3 = x[0]
	var keep_ang := ang.duplicate()
	var keep := [wep_lpos, wep_lrot, grip_u]
	var target: Vector3 = (P[h] as Vector3) + q * Vector3(0, d, 0)
	var want: Quaternion = G[h]
	var miss := fit_hand(h, target, want)
	if miss > 0.015:
		ang = keep_ang
		fk()
		return false
	# the weapon where it was: its place in the hand from the hand's new spot
	var g: Quaternion = G[h]
	wep_lrot = (g.inverse() * q).normalized()
	wep_lpos = g.inverse() * (knob - (P[h] as Vector3))
	apply_grip()
	return true


## put a hand's wrist on `target` turned as `want` (world): the safe reach, then a search over that arm (clavicle,
## upper arm 3 ways, elbow, hand 3 ways). cost = wrist miss (m) + 0.004 per degree of turn off + 5 x this arm's
## deepest contact (never bought with a better grip). Returns the wrist miss (m).
func fit_hand(h: String, target: Vector3, want: Quaternion) -> float:
	var sd := h.right(2)
	var arm := ["clavicle" + sd, "upperarm" + sd, "lowerarm" + sd, h]
	var cost := func() -> float:
		var turn := rad_to_deg((G[h] as Quaternion).angle_to(want))
		var inside := 0.0   # this arm in the body (or the other arm): never bought with a better grip
		for c in contacts():
			if (c[0] as String).trim_prefix("skin:") in arm or c[1] in arm:
				inside = maxf(inside, c[2])
		return ((P[h] as Vector3).distance_to(target)) + 0.004 * turn + 5.0 * inside
	reach(h, target)
	var before: Vector3 = ang[h]
	turn_world(h, (want * (G[h] as Quaternion).inverse()).normalized())
	# PLAYBACK CONTINUITY (round 47, flip_survey on Nick's locked axe scene: the left wrist's twist at its limit, a grip
	# asking past it wrapped through 180 and the clamp landed on the OTHER limit: 164 deg in one 60 fps frame against the
	# 105 deg human bar): in playback the wrist keeps the in-between pose's angle rather than jump across its range
	if fast:
		var dv: Vector3 = (ang[h] as Vector3) - before
		if absf(dv.x) > 90.0 or absf(dv.y) > 90.0 or absf(dv.z) > 90.0:
			ang[h] = before
	fk()
	if (P[h] as Vector3).distance_to(target) < 0.01 and rad_to_deg((G[h] as Quaternion).angle_to(want)) < 8.0:
		return (P[h] as Vector3).distance_to(target)   # the quick way did it (dragging stays smooth)   # the safe reach (stops at the body)
	# PLAYBACK (B.fast: limits only, contacts measured, not avoided) keeps the quick way: the search below costs a whole
	# body's FK and contacts per step, 245 ms a frame on Nick's locked axe scene (round 47) against 0.8 ms without it
	if fast:
		return (P[h] as Vector3).distance_to(target)
	var js := ["clavicle" + sd, "upperarm" + sd, "lowerarm" + sd, h]
	var best: float = cost.call()
	for stp in [12.0, 6.0, 3.0, 1.5]:
		var moved := true
		var rounds := 0
		while moved and rounds < 4:
			moved = false
			rounds += 1
			for j in js:
				for k in 3:
					if j.begins_with("lowerarm") and k != 0:
						continue
					for sg in [-1.0, 1.0]:
						var v: Vector3 = ang[j]
						var nv := v
						nv[k] += sg * stp
						nv = clamp_ang(j, nv)
						if nv == v:
							continue
						ang[j] = nv
						fk()
						var c: float = cost.call()
						if c < best - 1e-5:
							best = c
							moved = true
						else:
							ang[j] = v
							fk()
	return (P[h] as Vector3).distance_to(target)


# ---------------------------------------------------------------- contacts

## a part's capsule now: its rest end points carried by its joint; the bat's from its own frame
func cap(part: String) -> Array:
	if part == "wep2_handle":
		return [wep2_point(float(rad[part])), wep2_point(float(KINDS[wep2_kind]["handle"]))]
	if part == "wep2_blade":
		return [wep2_point(float(KINDS[wep2_kind]["handle"])), wep2_point(wep2_len() - float(rad[part]))]
	if part == "bat_handle":
		return [wep_point(wep_r_handle), wep_point(wep_handle)]
	if part == "bat_barrel":
		if not wep_head.is_empty():
			# the hammer head: across the shaft at the tip (along the weapon's own X)
			var x := wep_xform()
			var c := wep_point(wep_len - float(wep_head[1]))
			var side: Vector3 = (x[1] as Quaternion) * Vector3(float(wep_head[0]) - float(wep_head[1]), 0, 0)
			return [c - side, c + side]
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
		if not wep2_on and (pr[0] in WEAPON2 or pr[1] in WEAPON2):
			continue
		# both hands on one handle touch by nature (their capsules include the fingers wrapped round it)
		if wep_on and grip and pr[0].begins_with("hand") and pr[1].begins_with("hand"):
			continue
		var d := depth(pr[0], pr[1]) - float(allow.get(pr[0] + "|" + pr[1], 0.0))
		if d > 0.001:   # under 1 mm is touching, not inside
			out.append([pr[0], pr[1], d])
	for sc in skin_raw():
		var d2: float = float(sc[2]) - float(allow.get("skin:" + sc[0] + "|" + sc[1], 0.0))
		if d2 > 0.001:
			out.append(["skin:" + sc[0], sc[1], d2])
	return out


## the trunk + head skin points vs the forearms, hands and bat: [[part, other, deepest point inside (m)], ...] (raw)
func skin_raw(mv := {}) -> Array:   # mv (NA6): only what touches these parts ({} = all)
	var out := []
	if skin.is_empty():
		return out
	var caps := {}
	var mv_skin := false   # NA6: does a skin part (the trunk / head) itself move? then every capsule is needed
	for part in skin:
		if mv.has(part):
			mv_skin = true
	for y in SKIN_VS:
		if (y in WEAPON and not wep_on) or (y in WEAPON2 and not wep2_on):
			continue
		if not mv.is_empty() and not mv_skin and not mv.has(y):
			continue   # NA6: neither side of this pair moves
		caps[y] = cap(y)
	for part in skin:
		var g: Quaternion = G[part]
		var pj: Vector3 = P[part]
		var rj: Vector3 = p0[part]
		var cen: Vector3 = pj + g * ((skin_c[part][0] as Vector3) - rj)
		var br: float = skin_c[part][1]
		for y in caps:
			if not mv.is_empty() and not (mv.has(part) or mv.has(y)):
				continue
			var a: Vector3 = caps[y][0]
			var b: Vector3 = caps[y][1]
			var r: float = float(rad[y]) + (SKIN_HAND_PAD if (y as String).begins_with("hand") else 0.0)
			var ab := b - a
			var L2 := maxf(1e-9, ab.length_squared())
			var tc := clampf((cen - a).dot(ab) / L2, 0.0, 1.0)
			if (cen - (a + ab * tc)).length() > br + r:
				continue
			var deep := 0.0
			for q in skin[part]:
				var w: Vector3 = pj + g * ((q as Vector3) - rj)
				var t := clampf((w - a).dot(ab) / L2, 0.0, 1.0)
				deep = maxf(deep, r - (w - (a + ab * t)).length())
			if deep > 0.0:
				out.append([part, y, deep])
	return out


func penetration() -> float:
	var t := 0.0
	for c in contacts():
		t += float(c[2])
	return t


## THE HAND-DRAG FREEZE (round 49, GATES NA6; Nick 10-18: "a little freeze for 0.5 sec" moving a hand when the pose is
## all wrong). set_ang_safe asks "did this turn push anything deeper in?" about a dozen times a blocked step, and each
## ask summed EVERY pair and skin point of the body. Turning joint j moves only the parts below it (and a held weapon),
## so every other pair's depth is the same before and after: the CHANGE is the change of this sum over the pairs that
## touch a moving part. Same answer as penetration()'s difference (to float rounding), a fraction of the work.
var _mv_cache := {}


func moving_parts(j: String) -> Dictionary:
	if _mv_cache.has(j):
		return _mv_cache[j]
	var mv := {}
	for x in parent:
		var y: String = x
		while y != "":
			if y == j:
				mv[x] = true
				break
			y = parent.get(y, "")
	if mv.has("hand_l") or mv.has("hand_r"):   # a held weapon goes with the hand (over-including is still exact)
		for w in WEAPON + WEAPON2:
			mv[w] = true
	_mv_cache[j] = mv
	return mv


func penetration_moving(j: String) -> float:
	var mv := moving_parts(j)
	var t := 0.0
	for pr in pairs:
		if not (mv.has(pr[0]) or mv.has(pr[1])):
			continue
		if not wep_on and (pr[0] in WEAPON or pr[1] in WEAPON):
			continue
		if not wep2_on and (pr[0] in WEAPON2 or pr[1] in WEAPON2):
			continue
		if wep_on and grip and pr[0].begins_with("hand") and pr[1].begins_with("hand"):
			continue
		var d := depth(pr[0], pr[1]) - float(allow.get(pr[0] + "|" + pr[1], 0.0))
		if d > 0.001:
			t += d
	for sc in skin_raw(mv):
		var d2: float = float(sc[2]) - float(allow.get("skin:" + sc[0] + "|" + sc[1], 0.0))
		if d2 > 0.001:
			t += d2
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
## WHY A MOVE STOPPED (round 35, GATES PP2): set_ang_safe records it here, for the status line to say. A caller clears
## it before an edit and reads it after. {"kind": "limit", "joint", "axis", "at", "lo", "hi"} when an angle asked for
## lies past the joint's range (more than 0.5 deg); {"kind": "contact", "joint", "pairs": [[a, b], ...]} when the move
## was cut short where parts meet (the pairs touching at the asked angles that were not touching before)
var last_stop := {}


func set_ang_safe(j: String, v: Vector3) -> bool:
	if fast:
		set_ang(j, v)   # playback: limits only (the cook already checked contacts frame by frame)
		return true
	var cl := clamp_ang(j, v)
	for k in 3:
		var r: Vector2 = lim[j][["bend", "side", "twist"][k]]
		if r.y - r.x > 0.5 and absf(cl[k] - v[k]) > 0.5:   # a locked axis (a hinge's side, twist) is not a stop
			last_stop = {"kind": "limit", "joint": j, "axis": ["bend", "side", "twist"][k], "at": cl[k], "lo": r.x, "hi": r.y}
			break
	var old: Vector3 = ang[j]
	var pen0 := penetration_moving(j)   # NA6: only the pairs this turn can change
	set_ang(j, v)
	if penetration_moving(j) <= pen0 + 1e-4:
		return true
	var target: Vector3 = ang[j]
	var now := {}
	for c in contacts():
		now[[c[0], c[1]]] = float(c[2])
	set_ang(j, old)
	for c in contacts():
		now.erase([c[0], c[1]])
	var ps: Array = now.keys()
	ps.sort_custom(func(a, b): return now[a] > now[b])   # the deepest first
	last_stop = {"kind": "contact", "joint": j, "pairs": ps}
	var lo := 0.0
	var hi := 1.0
	for i in 10:
		var m := (lo + hi) * 0.5
		set_ang(j, old.lerp(target, m))
		if penetration_moving(j) <= pen0 + 1e-4:
			lo = m
		else:
			hi = m
	set_ang(j, old.lerp(target, lo))
	return false


## IK stops when the tip is this close (m): 0.01 mm, a tenth of what a file holds (0.1 mm). Round 13: reach and plant
## always ran every round (6 and 5): a 30-card scene's playback spent 5 ms a frame there, a card edit 2.5 s
const IK_EPS := 1e-5


## reach: put a limb's tip (hand_r/l = the wrist, foot_r/l = the ankle) on a target point. Two joints, in turns: the
## elbow/knee bend sets the shoulder-to-tip DISTANCE (bisection: it falls as the bend grows), then the shoulder/hip
## turns the tip onto the target (turn_world). Limits and contacts apply at every step. Returns the miss (m).
func reach(tip: String, target: Vector3) -> float:
	var mid: String = parent[tip]
	var root: String = parent[mid]
	var prev := INF
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
		fk_sub(mid)
		set_ang_safe(mid, Vector3((lo + hi) * 0.5, v.y, v.z))
		var r1: Vector3 = P[tip] - P[root]
		var r2: Vector3 = target - P[root]
		var ax := r1.cross(r2)
		if ax.length() > 1e-9:
			turn_world(root, Quaternion(ax.normalized(), r1.angle_to(r2)))
		var miss := ((P[tip] - target) as Vector3).length()
		if miss < IK_EPS:
			break   # there (round 13: the rounds after this moved nothing a file can hold, and cost 5 ms a frame)
		if miss > prev - 1e-6:
			break   # NA6: blocked (a limit or the body): the next rounds would redo the same stop (Nick's drag freeze)
		prev = miss
	return ((P[tip] - target) as Vector3).length()


## IK POLE (round 10, GATES Q5): swing the elbow / knee about the root-to-tip line by `deg`, the tip (hand / foot)
## staying put. The root (upper arm / thigh) turns about that line, which carries the limb round it; but the turn
## goes through the joint's bend/side/twist angles, which do not reproduce an arbitrary turn exactly (the hip: asked
## 20, got 10.8, the foot off by 6 mm). So it is a loop: turn the rest of the way, put the tip back (reach), MEASURE
## the elbow's angle about the line, repeat (8 at most). The tip keeps its world orientation. A limit stops it short.
## Returns the angle actually swung (deg).
func swing_pole(tip: String, deg: float) -> float:
	var mid: String = parent[tip]
	var root: String = parent[mid]
	var at: Vector3 = P[tip]
	var g0: Quaternion = G[tip]
	var ref := _pole_ref(root, tip)
	var a0 := _pole_angle(root, mid, tip, ref)
	var done := 0.0
	for it in 8:
		var left := deg - done
		if absf(left) < 0.05:
			break
		var ax: Vector3 = ((P[tip] - P[root]) as Vector3).normalized()
		turn_world(root, Quaternion(ax, deg_to_rad(left)))
		fk()
		reach(tip, at)
		var now := wrapf(_pole_angle(root, mid, tip, ref) - a0, -180.0, 180.0)
		if absf(now - done) < 0.01:   # no progress: a limit
			break
		done = now
	var gp: Quaternion = G[parent[tip]]
	set_ang_safe(tip, decompose(tip, (gp.inverse() * g0).normalized()))   # G = G[parent] * A: the tip's old G
	fk()
	return done


## a fixed direction perpendicular to the root->tip line (the elbow's angle is measured from it)
func _pole_ref(root: String, tip: String) -> Vector3:
	var ax: Vector3 = ((P[tip] - P[root]) as Vector3).normalized()
	var r := Vector3.UP if absf(ax.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
	return (r - ax * r.dot(ax)).normalized()


func _pole_angle(root: String, mid: String, tip: String, ref: Vector3) -> float:
	var ax: Vector3 = ((P[tip] - P[root]) as Vector3).normalized()
	var e: Vector3 = (P[mid] - P[root]) as Vector3
	e = (e - ax * e.dot(ax)).normalized()
	var r := (ref - ax * ref.dot(ax)).normalized()
	return rad_to_deg(r.signed_angle_to(e, ax))


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
## NO SPINS (Nick 10-13: "the arm is straight up front and abruptly spins around itself ... nobody turns the hand the
## opposite way, those should be banned"): from the pose before, the upper arm may roll and the forearm may turn at most
## ROLL_STEP degrees per key, and every degree of roll costs a little (continuity wins over a slightly better aim).
const ROLL_STEP := 45.0
const ROLL_COST := 0.08   # per 45 deg of roll
var roll_free := false    # the first key of a move has no key before it: no step limit (cook sets it)
var roll_start := NAN     # with roll_free: the first key's forearm turn is held near this (cook --roll: the move's "lane")


## ELBOW LOW (Nick 10-17, walk_bat): a weight per metre the elbow is above (wrist - ELBOW_UNDER). A person resting a
## bat on the shoulder keeps the elbow down by the ribs and the hand up by the collarbone; with only the wrist and
## the aim scored, the sweep raised the elbow to the shoulder and folded the forearm back into the chest. 0 = off.
var elbow_low := 0.0
const ELBOW_UNDER := 0.10


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
	var ku: float = (ang[ua] as Vector3).z   # the upper arm's roll and the forearm's turn in the key before
	var kh: float = (ang[h] as Vector3).z
	var step := 999.0 if roll_free else ROLL_STEP
	var step_h := step
	var rc := 0.0 if roll_free else ROLL_COST
	if roll_free and not is_nan(roll_start):
		kh = roll_start
		step_h = 15.0
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
				if absf(t - ku) > step + 10.0:   # (the 20-deg grid: the refine holds the exact step)
					t += 20.0
					continue
				ang[ua] = Vector3(b, sv, t)
				var e: float = ll["bend"].x
				while e <= ll["bend"].y:
					ang[la] = Vector3(e, 0, 0)
					for ht in [-60.0, -30.0, 0.0, 30.0, 60.0]:
						if absf(ht - kh) > step_h:
							continue
						for hs in [0.0]:
							ang[h] = Vector3(0, hs, ht)
							fk_some(chain)
							var c := 0.0
							if use_at:
								c += ((P[h] - at) as Vector3).length()
							if use_dir:
								c += aw * wep_axis().angle_to(dir)
							if elbow_low > 0.0:
								c += elbow_low * maxf(0.0, (P[la] as Vector3).y - ((P[h] as Vector3).y - ELBOW_UNDER))
							for pr in prs:
								c += 10.0 * maxf(0.0, depth(pr[0], pr[1]) - pr[2] - 0.001)
							if grip:
								# two hands: the other hand has to reach the handle (its arm is ~0.49 m long)
								c += 2.0 * maxf(0.0, (grip_point() - (P[ou] as Vector3)).length() - 0.42)
							c += rc * (absf(t - ku) + absf(ht - kh)) / 45.0
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
		if elbow_low > 0.0:
			c += elbow_low * maxf(0.0, (P[la] as Vector3).y - ((P[h] as Vector3).y - ELBOW_UNDER))
		if grip:
			# cheap: the handle within the other arm's reach (solving that arm here made a cook take 25+ min)
			c += 2.0 * maxf(0.0, (grip_point() - (P[ou] as Vector3)).length() - 0.42)
		c += rc * (absf((ang[ua] as Vector3).z - ku) + absf((ang[h] as Vector3).z - kh)) / 45.0
		return c
	var won := {}
	var won_c := INF
	var keep_lim: Dictionary = lim[h].duplicate()
	lim[h]["bend"] = Vector2(-15, 15)
	lim[h]["side"] = Vector2(-20, 20)
	lim[h]["twist"] = Vector2(maxf(-60.0, kh - step_h), minf(60.0, kh + step_h))
	var keep_lim_u: Dictionary = lim[ua].duplicate()
	lim[ua]["twist"] = Vector2(maxf(keep_lim_u["twist"].x, ku - step), minf(keep_lim_u["twist"].y, ku + step))
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
	lim[ua] = keep_lim_u
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
## one_start: search only from the arms as they are (no second start): a CONTINUATION from the key before can't flip.
func hold_bat(at: Vector3, dir: Vector3, use_at := true, use_dir := true, twist_lane := NAN, lane_w := 15.0, one_start := false, dir_w := 0.06) -> Array:
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
		# the forearm's turn: 0 for the bat; a staff guard holds the palms turned in (Nick's guard -55 / -66 deg), so a
		# staff move keeps the turn it starts with, +-15 (twist_lane = that turn; the other hand keeps its own +-15)
		if is_nan(twist_lane):
			lim[hh]["twist"] = Vector2(0, 0)
		else:
			var tl: float = twist_lane if hh == "hand" + sd else (ang[hh] as Vector3).z
			lim[hh]["twist"] = Vector2(maxf(keep_lim[hh]["twist"].x, tl - lane_w), minf(keep_lim[hh]["twist"].y, tl + lane_w))
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
			c += dir_w * wep_axis().angle_to(dir)   # default 0.06: the bat's direction only breaks ties (a scripted key where the weapon's line IS the pose passes more)
		if grip:
			c += ((P["hand" + od] - grip_wrist()) as Vector3).length()
		return c
	# two starts: as the arms are now, and both arms out in front of the chest (elbows bent) - a hand crossing the body
	# can't get round the belly from the side by small steps. The lower cost wins.
	var keep := ang.duplicate()
	var pen0 := penetration()
	var c1 := search(js, cost, pen0)
	var won := ang.duplicate()
	if one_start:
		for hh in keep_lim:
			lim[hh] = keep_lim[hh]
		var gm1 := ((P["hand" + od] - grip_wrist()) as Vector3).length() if grip else 0.0
		return [((P[h] - at) as Vector3).length() if use_at else 0.0, rad_to_deg(wep_axis().angle_to(dir)) if use_dir else 0.0, gm1]
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
	if kind == "relaxed":
		hand_relaxed(side)
		return
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


## BREATH (round 43, GATES YY6): quiet breathing as a small rise of the chest, added on top of whatever pose is shown.
## People (Massaroni et al. 2015, IEEE EMBC 1291-4, DOI 10.1109/EMBC.2015.7318604: the physiological range their chest
## wall simulator was set to): chest wall surface moves 1-8 mm in quiet breathing at 0.17-0.33 Hz (10-20 breaths a
## minute; resting adults 12-20). Here: the chest (spine_03) leans back BREATH_CHEST deg at full inhale, which moves
## the front of the chest ~5 mm (tests/breath_test.gd measures it), the neck turns it back so the head keeps its angle,
## the clavicles lift BREATH_CLAV (MINE: no number). The breath is a raised cosine (inhale = exhale: MINE).
const BREATH_CHEST := 1.8
const BREATH_CLAV := 1.0
const BREATH_DEFAULT := 15.0   # breaths a minute when switched on (the middle of people's 12-20)


## how far into the breath at t seconds: 0 = out, 1 = in
static func breath_at(t: float, rate: float) -> float:
	return 0.5 - 0.5 * cos(TAU * t * rate / 60.0)


func breathe(t: float, rate: float) -> void:
	if rate <= 0.0:
		return
	var b := breath_at(t, rate)
	ang["spine_03"] = clamp_ang("spine_03", (ang["spine_03"] as Vector3) + Vector3(-BREATH_CHEST * b, 0, 0))
	ang["neck_01"] = clamp_ang("neck_01", (ang["neck_01"] as Vector3) + Vector3(BREATH_CHEST * b, 0, 0))
	for sd in ["_r", "_l"]:
		ang["clavicle" + sd] = clamp_ang("clavicle" + sd, (ang["clavicle" + sd] as Vector3) + Vector3(BREATH_CLAV * b, 0, 0))
	fk()


## SHOULDERS THAT FOLLOW (round 43, GATES YY5): raising an arm brings the collarbone with it. McClure et al. 2001 (J
## Shoulder Elbow Surg 10:269-77; bone pins, 8 people, arm raised in the scapular plane 11 -> 147 deg): the clavicle
## ELEVATED ~10 deg and RETRACTED ~21 deg over the raise, the scapula moved "very little" in the first 30 deg, the
## retraction began near 25 deg (Inman 1944 gave ~30 deg of elevation, method unclear). This body has no scapula: the
## clavicle joint carries the girdle. Here: nothing below FOLLOW_FROM, then linear to FOLLOW_TO (McClure's upward
## rotation is near linear past 50; the linear form is MINE). Retraction stops at this body's limit, 15 (people 21).
## The arm's elevation is measured from straight down in the CHEST's frame (humerothoracic, as McClure's x axis); the
## clavicle tilts the arm, so it is solved to its own fixed point (FOLLOW_ITERS), and stops where it would meet the
## neck or head (contact-safe).
const FOLLOW_FROM := 30.0
const FOLLOW_TO := 147.0
const FOLLOW_ELEV := 10.0
const FOLLOW_RETRACT := 21.0
const FOLLOW_ITERS := 6


## the arm's elevation (deg): its upper arm from straight down, in the chest's frame. 0 = hanging, 90 = out level
func arm_elevation(sd: String) -> float:
	var d: Vector3 = (G["spine_03"] as Quaternion).inverse() * ((P["lowerarm" + sd] - P["upperarm" + sd]) as Vector3)
	return rad_to_deg(d.angle_to(Vector3.DOWN))


## the clavicle (bend = up, side = forward) that goes with an arm raised e degrees
func follow_clav(e: float) -> Vector3:
	var f := clampf((e - FOLLOW_FROM) / (FOLLOW_TO - FOLLOW_FROM), 0.0, 1.0)
	return Vector3(FOLLOW_ELEV * f, -FOLLOW_RETRACT * f, 0.0)


## true = the clavicle reached what the arm asks; false = a contact (the raised arm meeting the head) stopped it short
func shoulder_follow(sd: String) -> bool:
	var c := "clavicle" + sd
	ang[c] = Vector3.ZERO
	fk()
	var keep := last_stop
	var reached := true
	for i in FOLLOW_ITERS:
		# contact-safe: set_ang_safe stops it where parts would meet (the clavicle's own girdle pairs are calibrated to
		# people's measured shrug, below; what is left is real, e.g. an overhead arm meeting the head)
		reached = set_ang_safe(c, follow_clav(arm_elevation(sd)))
	last_stop = keep   # the arm edit's own stop words, not the follow's
	return reached


## THE BACK, ONE BEND (round 43, GATES YY4): forward / side / twist for the whole back at once, shared over the three
## spine joints, the neck and the head IN PROPORTION TO EACH ONE'S RANGE that way (data/body_limits.json), so they all
## reach their limits together and no one joint kinks while the others are straight. The sum is what was asked, up
## to the sum of the limits. People for scale (Apti et al. 2023, 300 young adults, goniometer): lumbar flexion 69.9,
## extension 40.0, lateral 36, rotation 38; cervical flexion 57.7, extension 59.1, lateral 42, rotation 71. This body:
## spine_01..03 bend -21..60, side +-21, twist +-51 (stiffer than people's lumbar alone: the hips carry the rest); neck +
## head bend -55..60, side +-35, twist +-75. Thoracic: no checked number (the meta-analysis's values are in figures).
const BACK := ["spine_01", "spine_02", "spine_03", "neck_01", "head"]
const BACK_AXIS := {"bend": 0, "side": 1, "twist": 2}


## the back's range that way: Vector2(sum of the lows, sum of the highs)
func back_range(axis: String) -> Vector2:
	var r := Vector2.ZERO
	for j in BACK:
		r += lim[j][axis] as Vector2
	return r


func back_of(axis: String) -> float:
	var s := 0.0
	for j in BACK:
		s += (ang[j] as Vector3)[BACK_AXIS[axis]]
	return s


func back_bend(axis: String, total: float) -> void:
	var r := back_range(axis)
	total = clampf(total, r.x, r.y)
	for j in BACK:
		var l: Vector2 = lim[j][axis]
		var share := (l.y / r.y if r.y != 0.0 else 0.0) if total >= 0.0 else (l.x / r.x if r.x != 0.0 else 0.0)
		var v: Vector3 = ang[j]
		v[BACK_AXIS[axis]] = total * share
		ang[j] = clamp_ang(j, v)
	fk()


## HANDS, ONE SLIDER (round 43, GATES YY3; Nick: "move plenty of parts but lightly"): curl 0..1 bends the four
## fingers' three joints at once in people's proportions, spread 0..1 fans them at the knuckles.
##   CURL_MCP / CURL_PIP: people's mean active flexion, 390 hands (Indian J Plast Surg 2024, PMC11436331): knuckle (MCP)
##     84-87 deg, middle joint (PIP) 97.2 (index).
##   DIP_PER_PIP: the tip joint follows the middle one, theta_DIP = 0.76 theta_PIP closing a fist (Hahn et al. 1995, the
##     index; table in PMC9541616). So curl 1 = MCP 85 / PIP 97 / DIP 74, inside this body's limits (90 / 105 / 80).
##   The thumb goes from open to the fist's thumb (hand_shape) by the same curl.
##   SPREAD: each finger's knuckle side angle at spread 1, away from the middle finger (MINE: proportions, not data;
##     the limits are +-20).
const CURL_MCP := 85.0
const CURL_PIP := 97.2
const DIP_PER_PIP := 0.76
const SPREAD := {"index": 15.0, "middle": 0.0, "ring": -8.0, "pinky": -18.0}
const THUMB_FIST := [Vector3(30, -10, 0), Vector3(60, 0, 0), Vector3(48, 0, 0)]
## RELAXED (YY3): the resting finger cascade, each finger's own knuckle / middle / tip angles. Varghese et al., J Clin
## Diagn Res 2020;14(5):YC01-07, Table 13: 250 non-power-grip workers, dominant hand, goniometer, seated, hand supported,
## wrist 15-20 deg extended. The little finger curls most at the tip, the ring at the middle joint, the middle finger
## at the knuckle, as in the paper. The thumb's rest is MINE (no number in the source).
const RELAXED := {"index": [27.08, 38.74, 13.76], "middle": [33.21, 40.67, 14.20], "ring": [29.34, 44.83, 14.33], "pinky": [26.24, 43.07, 16.08]}
const THUMB_RELAXED := [Vector3(10, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 0)]


func hand_relaxed(side: String) -> void:
	for f in RELAXED:
		for k in 3:
			var j := "%s_0%d_%s" % [f, k + 1, side]
			ang[j] = clamp_ang(j, Vector3(RELAXED[f][k], 0, 0))
	for k in 3:
		var j := "thumb_0%d_%s" % [k + 1, side]
		ang[j] = clamp_ang(j, THUMB_RELAXED[k])
	fk()


func hand_curl(side: String, curl: float, spread: float, fingers := ["index", "middle", "ring", "pinky"]) -> void:
	curl = clampf(curl, 0.0, 1.0)
	spread = clampf(spread, 0.0, 1.0)
	for f in fingers:
		var pip := CURL_PIP * curl
		var v := [Vector3(CURL_MCP * curl, SPREAD[f] * spread, 0), Vector3(pip, 0, 0), Vector3(DIP_PER_PIP * pip, 0, 0)]
		for k in 3:
			var j := "%s_0%d_%s" % [f, k + 1, side]
			ang[j] = clamp_ang(j, v[k])
	if fingers.size() == 4:
		for k in 3:
			var j := "thumb_0%d_%s" % [k + 1, side]
			ang[j] = clamp_ang(j, (THUMB_FIST[k] as Vector3) * curl)
	fk()


## POINT: the index straight, the other fingers and the thumb curled (a fist with the index out)
func hand_point(side: String) -> void:
	hand_curl(side, 1.0, 0.0)
	hand_curl(side, 0.0, 0.0, ["index"])


## the hand's curl and spread as the sliders read them back: the four middle joints' mean over CURL_PIP; the spread from
## the pinky's knuckle side (the widest)
func hand_curl_of(side: String) -> Vector2:
	var s := 0.0
	for f in ["index", "middle", "ring", "pinky"]:
		s += (ang["%s_02_%s" % [f, side]] as Vector3).x
	return Vector2(clampf(s / 4.0 / CURL_PIP, 0.0, 1.0), clampf((ang["pinky_01_" + side] as Vector3).y / SPREAD["pinky"], 0.0, 1.0))


## the lowest sole point's height above where it rests (m): heel (the ankle joint, minus its rest height) and toe tip
func sole_low() -> float:
	if not props.is_empty():
		return _sole_low_set()
	var low := INF
	for sd in ["_l", "_r"]:
		low = minf(low, (P["foot" + sd] as Vector3).y - (p0["foot" + sd] as Vector3).y)
		low = minf(low, (E["ball" + sd] as Vector3).y - (e0["ball" + sd] as Vector3).y)
		low = minf(low, (P["ball" + sd] as Vector3).y - (p0["ball" + sd] as Vector3).y)
	return low


## the same on the set (TT2): each sole point measured from the surface under it, not from the floor
## The toe TIP stands on what the ball of its foot stands on: the heel or the ball carries a foot on a step, a toe tip
## touching a crate's face does not (round 39: toes 2 cm into a 1 m crate stack lifted the whole body onto it)
func _sole_low_set() -> float:
	var low := INF
	for sd in ["_l", "_r"]:
		var ball_up: float = (p0["ball" + sd] as Vector3).y
		var ball_s := surface_at(P["ball" + sd], ball_up)
		var heel_up: float = (p0["foot" + sd] as Vector3).y
		low = minf(low, (P["foot" + sd] as Vector3).y - heel_up - surface_at(P["foot" + sd], heel_up))
		low = minf(low, (P["ball" + sd] as Vector3).y - ball_up - ball_s)
		low = minf(low, (E["ball" + sd] as Vector3).y - (e0["ball" + sd] as Vector3).y - ball_s)
	return low


## the surface under a point (world x, z): the floor (0) or a support's top, the LOWEST one at which the point, `up`
## metres above it, is not inside a prop: a foot over a box stands on its top; a foot under a table or between a
## chair's legs stays on the floor
func surface_at(pt: Vector3, up: float) -> float:
	var hs := [0.0]
	for p in props:
		for s in Props.supports(p):
			if Props._over(s, pt):
				hs.append(float(s["y"]))
	hs.sort()
	for h in hs:
		var q := Vector3(pt.x, h + up, pt.z)
		var inside := false
		for p in props:
			for sw in Props.solids(p):
				if Props._sd(sw, q) < -Props.REST_SINK:
					inside = true
		if not inside:
			return h
	return hs[-1]


## how far the hips and thighs must rise to sit ON a seat they sink into (0 = none): the part of each capsule that is
## OVER a support (its axis sampled every 2 cm) whose top is above it, its lowest surface under the top by less than
## SEAT_CATCH. Only the part over the seat: a thigh tilting down past the seat's front edge is not lifted by its knee
func seat_lift() -> float:
	var lift := 0.0
	for part in SEAT_PARTS:
		var c := cap(part)
		var r: float = rad[part]
		var a: Vector3 = c[0]
		var b: Vector3 = c[1]
		if maxf(a.y, b.y) + r <= 0.0:
			continue
		var n := maxi(1, int(ceil(a.distance_to(b) / 0.02)))
		for p in props:
			for s in Props.supports(p):
				var top: float = s["y"]
				var lo := INF
				for k in n + 1:
					var q := a.lerp(b, float(k) / n)
					if Props._over(s, q):
						lo = minf(lo, q.y - r)
				if lo < top and top - lo < SEAT_CATCH and maxf(a.y, b.y) + r > top:
					lift = maxf(lift, top - lo)
	return lift


## FEET ON THE FLOOR: move the hips straight up/down so the lowest sole point touches the ground
##   offset.y -= sole_low()      (a bent knee drops the body; nothing floats, nothing sinks)
## On the set (TT2): the soles stand on what is under them, and hips sinking into a seat are lifted onto it
func ground() -> void:
	offset.y -= sole_low()
	if not props.is_empty():
		fk()
		offset.y += seat_lift()
	fk()


## the WHOLE body's lowest point on the floor (each capsule's ends minus its radius, fingers aside): a body that sits
## or lies rests on its hips/back, not lifted onto its soles (Nick 10-13: "the butt touches the ground when we stand up")
func ground_body() -> void:
	fk()
	var low := INF
	for j in ORDER:
		if j.begins_with("thumb") or j.begins_with("index") or j.begins_with("middle") or j.begins_with("ring") or j.begins_with("pinky"):
			continue
		var r: float = float(rad.get(j, 0.03))
		low = minf(low, minf((P[j] as Vector3).y, (E[j] as Vector3).y) - r)
	offset.y -= low
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
	fk_sub("foot" + sd)


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
	# a heel high up (a deep lunge's back foot) stands the foot almost on end: ankle -> toe base then points nearly
	# straight down and its floor direction is noise (it read 85-130 deg off on a good lunge). The toes lie flat on
	# the floor there, so they say where the foot points: toe base -> toe tip.
	if Vector2(d.x, d.z).length() < 0.5 * d.length():
		d = E["ball" + sd] - P["ball" + sd]
	return atan2(d.x, d.z)


## [ball (toe base) position, heading, toe base on the floor?, heel on the floor?]
func foot_state(sd: String) -> Array:
	var b: Vector3 = P["ball" + sd]
	var on := b.y - (p0["ball" + sd] as Vector3).y < 0.02
	var heel := (P["foot" + sd] as Vector3).y - (p0["foot" + sd] as Vector3).y < 0.02
	if not props.is_empty():   # TT2: on the ground = on the surface under it (a step's top counts)
		var bu: float = (p0["ball" + sd] as Vector3).y
		var fu: float = (p0["foot" + sd] as Vector3).y
		on = b.y - bu - surface_at(b, bu) < 0.02
		heel = (P["foot" + sd] as Vector3).y - fu - surface_at(P["foot" + sd], fu) < 0.02
	return [b, foot_heading(sd), on, heel]


## PLANT A FOOT: the leg alone (thigh, knee, ankle) puts the toe base at `ball_at`, pointing `head`.
##   loop: (flat foot) -> reach the ankle to ball_at - (ball - ankle) -> turn the thigh about its length by Newton's
##   step  dtwist = -err / (d err / d twist)  so the foot points where it pointed (flat feet only; a heel-up foot
##   pivots on its ball). Returns the miss (m).
## knee: the heading the knee should point along (NAN = the rule: the foot's heading if flat, else the hips' facing)
func plant(sd: String, ball_at: Vector3, head: float, flat: bool, knee := NAN) -> float:
	var th := "thigh" + sd
	for it in 5:
		if flat:
			flat_foot(sd)
		var d: Vector3 = P["ball" + sd] - P["foot" + sd]
		reach("foot" + sd, ball_at - d)
		# a heel-up back foot pivots with the hips: its knee follows the hips' facing, not its own foot (that chases itself)
		var hf: Vector3 = (G["pelvis"] as Quaternion) * Vector3(0, 0, 1)
		knee_over_toes(sd, knee if not is_nan(knee) else (head if flat else atan2(hf.x, hf.z)))
		if ((P["ball" + sd] - ball_at) as Vector3).length() < IK_EPS:
			break   # the knee turn left the ball on its mark: the next round would change nothing that shows
	return ((P["ball" + sd] - ball_at) as Vector3).length()


## the heading the knee points along now (the knee's offset from the hip -> ankle line, on the floor), or NAN if straight
func knee_heading(sd: String) -> float:
	var H: Vector3 = P["thigh" + sd]
	var u: Vector3 = ((P["foot" + sd] - H) as Vector3).normalized()
	var k: Vector3 = (P["calf" + sd] as Vector3) - H
	k -= u * u.dot(k)
	if k.length() < 0.01:
		return NAN
	return atan2(k.x, k.z)


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


## PLAYBACK COST (round 34, GATES OO1b): joint j moved, only j and the joints below it can change. While a scene plays
## (fast) only that subtree is recomputed, in ORDER, by the same expressions as fk(), so every number comes out bit for
## bit as a full fk() would make it (a leg solve recomputed all 52 joints ~200 times a frame; round 32's fade added two
## solves per foot and tripled a frame). Outside playback a full fk() as before: an edit may have written ang directly.
var _below := {}   # j -> [j and every joint under it, in ORDER]


func fk_sub(j: String) -> void:
	if not fast:
		fk()
		return
	var js = _below.get(j, null)
	if js == null:
		var inside := {j: true}
		js = []
		for k in ORDER:
			if k == j or inside.has(parent[k]):
				inside[k] = true
				js.append(k)
		_below[j] = js
	for k in js:
		var A := compose(k, ang[k])
		var pk: String = parent[k]
		if pk == "":
			G[k] = A
			P[k] = p0[k] + offset
		else:
			G[k] = G[pk] * A
			P[k] = P[pk] + G[pk] * (p0[k] - p0[pk])
		E[k] = P[k] + G[k] * (e0[k] - p0[k])


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


## the joint's twin on the other side (hand_l <-> hand_r); a middle joint is its own twin
static func twin(j: String) -> String:
	if j.ends_with("_l"):
		return j.substr(0, j.length() - 2) + "_r"
	if j.ends_with("_r"):
		return j.substr(0, j.length() - 2) + "_l"
	return j


## MIRROR THE WHOLE POSE (10-14, animators: "the left-handed version of this move"): left <-> right through the
## body's middle plane (x -> -x). Each joint takes its twin's rotation reflected, A' = M A M, which for a quaternion
## is (x, y, z, w) -> (x, -y, -z, w) (the same rule weapon_to_hand uses for the left-hand grip); the hips' offset x
## flips; the weapon goes to the other hand, its place in the hand reflected the same way. Mirroring twice = the pose.
## COPY / PASTE POSE (round 10, GATES Q1): the body's angles and hip offset (not the weapon: it stays as it is)
## the pose with ITS WEAPON (round 32, GATES MM1; Nick 2026-10-16 overrides round 10's Q1: a mirrored paste builds the
## other side of a combo, so the weapon must follow): the hand and the grip in it, or the free weapon's place
func pose_copy() -> Dictionary:
	var c := {"ang": ang.duplicate(), "offset": offset}
	if wep_on:
		c["wep"] = {"hand": wep_hand, "lpos": wep_lpos, "lrot": wep_lrot, "pos": wep_pos, "rot": wep_rot}
	if wep2_on:
		c["wep2"] = {"hand": wep2_hand, "lpos": wep2_lpos, "lrot": wep2_lrot}
	return c


## j and every joint below it (an upper arm -> the arm, forearm, hand and fingers)
func below(j: String) -> Array:
	var out := []
	for k in ORDER:
		var c: String = k
		while c != "":
			if c == j:
				out.append(k)
				break
			c = parent[c]
	return out


## paste a copied pose: mirrored = reflected left <-> right (as mirror_pose does to the angles); only = just these
## joints (empty = all, and then the hips' offset too)
func pose_paste(p: Dictionary, mirrored := false, only := []) -> void:
	var src: Dictionary = p["ang"]
	for j in ORDER:
		if not only.is_empty() and not j in only:
			continue
		if mirrored:
			var q := compose(twin(j), src[twin(j)])
			ang[j] = clamp_ang(j, decompose(j, Quaternion(q.x, -q.y, -q.z, q.w)))
		else:
			ang[j] = src[j]
	if only.is_empty():
		var o: Vector3 = p["offset"]
		offset = Vector3(-o.x, o.y, o.z) if mirrored else o
		if wep_on and p.has("wep"):   # the weapon comes with the pose; mirrored = into the other hand, as mirror_pose
			var w: Dictionary = p["wep"]
			wep_hand = twin(w["hand"]) if mirrored and w["hand"] != "" else w["hand"]
			var lp: Vector3 = w["lpos"]
			var lr: Quaternion = w["lrot"]
			var wp: Vector3 = w["pos"]
			var wr: Quaternion = w["rot"]
			wep_lpos = Vector3(-lp.x, lp.y, lp.z) if mirrored else lp
			wep_lrot = Quaternion(lr.x, -lr.y, -lr.z, lr.w) if mirrored else lr
			wep_pos = Vector3(-wp.x, wp.y, wp.z) if mirrored else wp
			wep_rot = Quaternion(wr.x, -wr.y, -wr.z, wr.w) if mirrored else wr
		if wep2_on and p.has("wep2"):
			var w2: Dictionary = p["wep2"]
			var lp2: Vector3 = w2["lpos"]
			var lr2: Quaternion = w2["lrot"]
			wep2_hand = twin(w2["hand"]) if mirrored else w2["hand"]
			wep2_lpos = Vector3(-lp2.x, lp2.y, lp2.z) if mirrored else lp2
			wep2_lrot = Quaternion(lr2.x, -lr2.y, -lr2.z, lr2.w) if mirrored else lr2
	fk()


func mirror_pose() -> void:
	var A := {}
	for j in ORDER:
		A[j] = compose(j, ang[j])
	for j in ORDER:
		var q: Quaternion = A[twin(j)]
		ang[j] = clamp_ang(j, decompose(j, Quaternion(q.x, -q.y, -q.z, q.w)))
	offset.x = -offset.x
	if wep_hand != "":
		wep_hand = twin(wep_hand)
		wep_lpos.x = -wep_lpos.x
		wep_lrot = Quaternion(wep_lrot.x, -wep_lrot.y, -wep_lrot.z, wep_lrot.w)
	else:
		wep_pos.x = -wep_pos.x
		wep_rot = Quaternion(wep_rot.x, -wep_rot.y, -wep_rot.z, wep_rot.w)
	if wep2_on:   # the off-hand weapon crosses too: with one in each hand, the hands swap what they hold
		wep2_hand = twin(wep2_hand)
		wep2_lpos.x = -wep2_lpos.x
		wep2_lrot = Quaternion(wep2_lrot.x, -wep2_lrot.y, -wep2_lrot.z, wep2_lrot.w)
	# Lock both hands' grip crosses too (round 47): it lives in the weapon's frame, which reflects like the weapon's place
	# in the hand (x of the position flipped, the turn conjugated); its fingers go to the twin hand as the body's do
	if not grip2.is_empty():
		var g2 := grip2.duplicate(true)
		g2["hand"] = twin(String(grip2["hand"]))
		var lp := _v(grip2["lpos"])
		g2["lpos"] = _p(Vector3(-lp.x, lp.y, lp.z))
		var lr: Array = grip2["lrot"]
		g2["lrot"] = _q(Quaternion(lr[0], -float(lr[1]), -float(lr[2]), lr[3]))
		var fing := {}
		for j in grip2.get("fingers", {}):
			var a: Array = grip2["fingers"][j]
			var q := compose(j, Vector3(a[0], a[1], a[2]))
			var m := decompose(twin(j), Quaternion(q.x, -q.y, -q.z, q.w))
			fing[twin(j)] = [snappedf(m.x, 0.1), snappedf(m.y, 0.1), snappedf(m.z, 0.1)]
		g2["fingers"] = fing
		grip2 = g2
	fk()


## two Lock-both-hands grips blended (round 47: between two cards that both lock, the second hand's turn, place and
## fingers move from one grip to the next instead of snapping at the card: a finger turned 97 deg in one frame)
## THE WRAP (round 47, GATES CC1/CC2): the fingers of hand h closed round the handle a-b of radius r (scripts/grip_wrap.gd)
func wrap_fingers(h: String, a: Vector3, b: Vector3, r: float, kind := "") -> Dictionary:
	return GripWrap.wrap(self, h, a, b, r, kind if kind != "" else GripWrap.type_of(wep_kind))


static func grip2_mix(a: Dictionary, b: Dictionary, e: float) -> Dictionary:
	if a.is_empty() or b.is_empty() or String(a.get("hand", "")) != String(b.get("hand", "")):
		return a if e < 0.5 else b
	var out := a.duplicate(true)
	out["u"] = lerpf(float(a.get("u", 0.0)), float(b.get("u", 0.0)), e)
	out["lpos"] = _p(_v(a["lpos"]).lerp(_v(b["lpos"]), e))
	var ra: Array = a["lrot"]
	var rb: Array = b["lrot"]
	out["lrot"] = _q(Quaternion(ra[0], ra[1], ra[2], ra[3]).normalized().slerp(Quaternion(rb[0], rb[1], rb[2], rb[3]).normalized(), e))
	var fing := {}
	for j in a.get("fingers", {}):
		var x: Array = a["fingers"][j]
		var y: Array = b.get("fingers", {}).get(j, x)
		fing[j] = [lerpf(x[0], y[0], e), lerpf(x[1], y[1], e), lerpf(x[2], y[2], e)]
	out["fingers"] = fing
	return out


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
		w = {"kind": wep_kind, "length": wep_len, "hand": wep_hand, "knob": _p(x[0]), "tip": _p(wep_point(wep_len)),
			"rot": _q(x[1]), "local_pos": _p(wep_lpos), "local_rot": _q(wep_lrot), "two_hand_grip": grip, "grip_m": grip_u}
		# Lock both hands' grip (the second hand's turn round the shaft + its fingers) goes into the file (round 47, Nick
		# 10-18 "lock hands in place ... so it can work": before, it lived in memory only and a reopened scene re-solved
		# the second arm its own way)
		if grip and not grip2.is_empty():
			w["grip2"] = grip2.duplicate(true)
	var out := {"offset": _p(offset), "joints": joints, "weapon": w, "contacts": con}
	if wep2_on:
		out["weapon2"] = wep2_dict()
	return out


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
		set_kind(String(w.get("kind", "metal_bat")))
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
		if w.get("grip2") is Dictionary and not (w["grip2"] as Dictionary).is_empty():
			grip2 = (w["grip2"] as Dictionary).duplicate(true)
	put_wep2(wep2_flat(d.get("weapon2", {})))


## THE POSE, LOSSLESS (round 8, for undo): to_dict rounds for the files (0.01 deg, 0.1 mm), so an undo through it
## re-solved from rounded numbers and a chain of undos drifted (tests/undo_fuzz_test.gd: 0.1 mm, 4th decimal of G)
func state() -> Dictionary:
	return {"ang": ang.duplicate(), "offset": offset, "wep_on": wep_on, "wep_kind": wep_kind, "wep_len": wep_len,
		"wep_pos": wep_pos, "wep_rot": wep_rot, "wep_hand": wep_hand, "wep_lpos": wep_lpos, "wep_lrot": wep_lrot,
		"grip": grip, "grip_u": grip_u, "grip2": grip2.duplicate(true), "wep2_on": wep2_on, "wep2_kind": wep2_kind,
		"wep2_hand": wep2_hand, "wep2_lpos": wep2_lpos, "wep2_lrot": wep2_lrot}


func set_state(s: Dictionary) -> void:
	ang = (s["ang"] as Dictionary).duplicate()
	offset = s["offset"]
	set_kind(s["wep_kind"])
	set_weapon_len(s["wep_len"])
	wep_on = s["wep_on"]
	wep_pos = s["wep_pos"]
	wep_rot = s["wep_rot"]
	wep_hand = s["wep_hand"]
	wep_lpos = s["wep_lpos"]
	wep_lrot = s["wep_lrot"]
	grip = s["grip"]
	grip_u = s["grip_u"]
	grip2 = (s["grip2"] as Dictionary).duplicate(true)
	wep2_on = s.get("wep2_on", false)
	wep2_kind = s.get("wep2_kind", "dagger")
	wep2_hand = s.get("wep2_hand", "hand_l")
	wep2_lpos = s.get("wep2_lpos", Vector3.ZERO)
	wep2_lrot = s.get("wep2_lrot", Quaternion.IDENTITY)
	fk()


static func _q(q: Quaternion) -> Array:
	return [snappedf(q.x, 0.00001), snappedf(q.y, 0.00001), snappedf(q.z, 0.00001), snappedf(q.w, 0.00001)]


static func _p(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]
