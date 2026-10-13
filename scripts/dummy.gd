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


## THE DUMMY IS SOLID (Nick 10-13: "the dummy needs limits ... so when it hits it doesn't go through"). The scene as it
## plays against the dummy: the swing runs until the weapon meets its surface, then stops there and rebounds.
##   1. the first hit's frame t1 (60 fps); the surface time tc between t1 - dt and t1 by bisection (10 halvings: the
##      weapon stops within ~0.1 mm of the skin):  touching(mid) ? hi = mid : lo = mid
##   2. the cards up to tc are kept (one still holding at tc is cut there); IMPACT = the pose at tc (the weapon on the
##      surface), held a breath (0.04 s); REBOUND = the pose REBOUND_S before the impact (the strike bounces back the
##      way it came), 0.10 s; then the scene's last card (the recovery) as authored, 0.45 s.
## Returns [the landed scene, the hit] or [S, {}] when nothing lands.
const REBOUND_S := 0.10


func landed(S: Scene, B: Body) -> Array:
	var hs := hits(S, B, 60)
	if hs.is_empty():
		return [S, {}]
	var h: Dictionary = hs[0]
	var lo := maxf(0.0, float(h["t"]) - 1.0 / 60.0)
	var hi := float(h["t"])
	for k in 10:
		var mid := (lo + hi) * 0.5
		S.apply(B, mid)
		if touch(B).is_empty():
			lo = mid
		else:
			hi = mid
	var tc := lo
	var L := Scene.new()
	L.name = S.name
	L.natural = S.natural
	var ts: Array = S.times()
	var last := -1
	for i in S.cards.size():
		if float(ts[i][1]) > tc:
			break
		var c: Dictionary = S.cards[i].duplicate()
		c["hold"] = minf(float(c["hold"]), tc - float(ts[i][1]))
		L.cards.append(c)
		last = i
	if last < 0:
		return [S, {}]
	var t_last: float = float(ts[last][1]) + float(L.cards[-1]["hold"])
	S.apply(B, tc)
	var pc: Dictionary = B.to_dict()
	S.apply(B, maxf(0.0, tc - REBOUND_S))
	var pr: Dictionary = B.to_dict()
	if tc - t_last > 0.005:
		L.cards.append({"name": "IMPACT", "pose": pc, "move": tc - t_last, "hold": 0.04})
	else:
		L.cards[-1]["hold"] = float(L.cards[-1]["hold"]) + 0.04
	L.cards.append({"name": "rebound", "pose": pr, "move": REBOUND_S, "hold": 0.06})
	if last < S.cards.size() - 1:
		var end: Dictionary = S.cards[-1].duplicate()
		end["move"] = 0.45
		end.erase("steps")
		L.cards.append(end)
	h["t"] = tc
	return [L, h]
