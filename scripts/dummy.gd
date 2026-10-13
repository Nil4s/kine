## dummy.gd - THE TARGET DUMMY (Nick 10-13: "we should have a dummy for combat scenes so we understand where the hits
## will land, if they seem proper"). A second mannequin stands `dist` m in front of the hero, facing him. It is the same
## body (Body, standing pose), so its capsules are the mannequin's own. Math in MATH.md ("Target dummy").
##
## Each frame both weapon capsules are tested against every dummy part:
##   depth = r_weapon + r_part - |closest points of the two axes|      (Body.seg_seg)      > 0 = the weapon is in it
## The FIRST frame a swing touches the dummy is its HIT:
##   zone   = the part's zone (HEAD, CHEST, BELLY, HIPS, LEGS, SHINS, FEET, ARMS)
##   u      = the spot on the weapon that lands (m from the butt), found by sampling the weapon's axis every 2 cm
##   speed  = how fast that spot moves:  v = |p_u(t) - p_u(t - dt)| / dt   (m/s; a real staff/bat strike: 10-20 m/s)
class_name Dummy
extends RefCounted

const ZONES := {
	"head": "HEAD", "neck_01": "HEAD", "spine_03": "CHEST", "spine_02": "CHEST", "spine_01": "BELLY", "pelvis": "HIPS",
	"thigh_l": "LEGS", "thigh_r": "LEGS", "calf_l": "SHINS", "calf_r": "SHINS", "foot_l": "FEET", "foot_r": "FEET",
	"upperarm_l": "ARMS", "upperarm_r": "ARMS", "lowerarm_l": "ARMS", "lowerarm_r": "ARMS", "hand_l": "ARMS", "hand_r": "ARMS"}
const STEP := 0.02     # the weapon's axis is sampled every 2 cm to find the spot that lands

var D := Body.new()
var dist := 1.5
var xf := Transform3D.IDENTITY   # the dummy's body space -> the hero's space (turned to face him, moved out front)


func _init() -> void:
	D.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	D.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	D.ground()
	place(dist)


## stand the dummy `d` m in front of the hero (+z), facing him
func place(d: float) -> void:
	dist = d
	xf = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, d))


## a dummy part's capsule axis in the hero's space
func cap(part: String) -> Array:
	var c: Array = D.cap(part)
	return [xf * (c[0] as Vector3), xf * (c[1] as Vector3)]


## the weapon in the dummy now: {} = no touch, else {"part", "zone", "depth" (m), "u" (m from the butt), "at" (world)}
func touch(B: Body) -> Dictionary:
	if not B.wep_on:
		return {}
	var best := {}
	for w in Body.WEAPON:
		var a: Array = B.cap(w)
		for part in ZONES:
			var c: Array = cap(part)
			var dp: float = float(B.rad[w]) + float(D.rad[part]) - Body.seg_seg(a[0], a[1], c[0], c[1])
			if dp > 0.0 and (best.is_empty() or dp > float(best["depth"])):
				best = {"part": part, "zone": ZONES[part], "depth": dp}
	if best.is_empty():
		return best
	# the spot on the weapon nearest the part's axis
	var c2: Array = cap(best["part"])
	var bu := 0.0
	var bd := INF
	var u := 0.0
	while u <= B.wep_len + 1e-6:
		var p: Vector3 = B.wep_point(u)
		var d := Body.seg_seg(p, p, c2[0], c2[1])
		if d < bd:
			bd = d
			bu = u
		u += STEP
	best["u"] = bu
	best["at"] = B.wep_point(bu)
	return best


## every hit of a scene (fps frames a second): [{"t", "zone", "part", "u", "speed", "depth", "at"}, ...]. A hit = the
## first frame of a touch; the weapon must leave the dummy before the next one counts.
func hits(S: Scene, B: Body, fps := 60) -> Array:
	var out := []
	var n := int(ceil(S.length() * fps))
	var was := false
	for f in n + 1:
		var t := float(f) / fps
		S.apply(B, t)
		var h := touch(B)
		if not h.is_empty() and not was:
			var now: Vector3 = h["at"]
			S.apply(B, maxf(0.0, t - 1.0 / fps))
			var before: Vector3 = B.wep_point(h["u"])
			h["t"] = t
			h["speed"] = (now - before).length() * fps
			out.append(h)
		was = not h.is_empty()
	return out
