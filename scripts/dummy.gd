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
var yaw := 0.0                   # deg round the hero the dummy stands (0 = in front, + = to his left)
var xf := Transform3D.IDENTITY   # the dummy's body space -> the hero's space (turned to face him, moved out front)


func _init() -> void:
	D.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	D.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	D.ground()
	place(dist)


## stand the dummy `d` m from the hero, `a` deg round him (0 = in front, +z; + = to his left, +x), facing him
func place(d: float, a := 0.0) -> void:
	dist = d
	yaw = a
	var r := Basis(Vector3.UP, deg_to_rad(a))
	xf = Transform3D(r * Basis(Vector3.UP, PI), r * Vector3(0, 0, d))


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
	# every playback flag goes with the copy (10-14: it kept only `natural`, so a solid dummy played a spline scene with
	# the old per-card ease, and a get-up without floor_body)
	L.natural = S.natural
	L.spline = S.spline
	L.on_floor = S.on_floor
	L.floor_body = S.floor_body
	L.pin = S.pin
	L.fps = S.fps
	L.body = S.body   # PR2: the proportions go with the copy too
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


# ---------------------------------------------------------------- two fighters (round 50, GATES TC5)
## THE DUMMY'S REPORT BETWEEN TWO FIGHTERS. The hero plays `sa` on body `ba`; the other fighter plays `sb` on `bb` and
## stands where `xf` puts it (its space -> the hero's); both on the same clock. Every frame (fps a second) the two bodies
## are tested with Body.cross_contacts (every capsule of each, their weapons included). Each contact row is named by
## its kind and the ZONE it lands on (cross_name):
##   hit    the hero's weapon on the other's part        zone = that part's zone (HEAD, CHEST, ... ARMS)
##   struck the other's weapon on the hero's part        zone = the hero's part's zone
##   clash  weapon on weapon                             zone = WEAPON
##   block  forearm/hand on forearm/hand                 zone = ARMS
##   touch  any other body on body                       zone = the other's part's zone
## A contact starts the first sample its kind + zone is present after a sample without it (as the dummy's hit: it must
## leave before the next one counts). Samples: every frame, and every 1/240 s inside a frame where they may touch (see
## BETWEEN FRAMES). For it: t = its onset, found between that sample and the one before by bisection (10 halvings);
## part = the striking part (a weapon part when one is in it), on = the part struck; at = where it first touches (the
## midpoint of the two axes' closest points at the onset, the hero's space); u = m up the weapon (weapons; -1 for a body
## part); speed = |p(t) - p(t')| / (t - t') of the striking spot (the same spot on its part; t' = the sample before);
## depth = the deepest it goes before it leaves (m, at the samples).
## Returns [{"t", "kind", "zone", "part", "on", "by" ("hero" / "other"), "depth", "speed", "u", "at"}, ...] by t.
const BISECT := 10


static func cross_name(c: Array) -> String:
	var kind: String = c[3]
	if kind == "clash":
		return "clash|WEAPON"
	if kind == "struck":
		return "struck|" + Body.cross_zone(c[0])
	return kind + "|" + Body.cross_zone(c[1])


## the deepest contact row of each kind + zone now: {key: row}
static func cross_named(ba: Body, bb: Body, xf: Transform3D) -> Dictionary:
	var out := {}
	for c in ba.cross_contacts(bb, xf):   # deepest first: the first row of a key is its deepest
		var k := cross_name(c)
		if not out.has(k):
			out[k] = c
	return out


static func _pose2(sa: Scene, ba: Body, sb: Scene, bb: Body, t: float) -> void:
	sa.apply(ba, t)
	sb.apply(bb, t)


## the parameters (s on p1-q1, t on p2-q2) of the two segments' closest points (Ericson 5.1.9, as Body.seg_seg)
static func seg_params(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> Vector2:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-12 and e <= 1e-12:
		return Vector2.ZERO
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
	return Vector2(s, t)


## a contact row's two axes in the hero's space: [hero part a, b, other part a, b]
static func _axes(ba: Body, bb: Body, xf: Transform3D, c: Array) -> Array:
	var p: Array = ba.cap(c[0])
	var q: Array = bb.cap(c[1])
	return [p[0], p[1], xf * (q[0] as Vector3), xf * (q[1] as Vector3)]


## where a contact row is: the midpoint of the closest points of its two axes (the hero's space)
static func cross_at(ba: Body, bb: Body, xf: Transform3D, c: Array) -> Vector3:
	var ax := _axes(ba, bb, xf, c)
	var st := seg_params(ax[0], ax[1], ax[2], ax[3])
	return ((ax[0] as Vector3).lerp(ax[1], st.x) + (ax[2] as Vector3).lerp(ax[3], st.y)) * 0.5


## a point on a part's axis (s = 0..1 from its first end), carried by xf
static func _spot(b: Body, part: String, s: float, xf: Transform3D) -> Vector3:
	var a: Array = b.cap(part)
	return xf * (a[0] as Vector3).lerp(a[1], s)


## BETWEEN FRAMES. A bat at 30 m/s moves a metre in a 30 fps frame: a contact can begin and end between two frames
## (combo3's wind-up brushes a head 1.2 m out for less than 1/60 s). So where the two bodies MAY touch inside a frame
## (_may_touch), the frame is sampled SUB_HZ times a second as well (the same Scene.apply). _may_touch, per pair of
## capsules (one of each body): the straight path of each one's bounding sphere centre across the frame; the closest
## approach of the two paths (Body.seg_seg: a lower bound of their distance at any one moment) under the two sphere
## radii + SAG x the two parts' chords (the most an end point moved): SAG = 0.5 covers an arc up to 180 deg a frame
## (sagitta / chord = tan(theta / 4) / 2). Frames where nothing is near cost one test; the rest are sampled as the
## ground truth is (tests/actors_hit_test.gd: every 1/240 s).
const SUB_HZ := 240.0
const SAG := 0.5


static func _may_touch(c0: Array, c1: Array) -> bool:
	var A0: Array = c0[0]
	var A1: Array = c1[0]
	var B0: Array = c0[1]
	var B1: Array = c1[1]
	if A0.size() != A1.size() or B0.size() != B1.size():
		return true   # a weapon came or went: sample it
	var ch_b := []
	for j in B0.size():
		ch_b.append(maxf((B0[j][1] as Vector3).distance_to(B1[j][1]), (B0[j][2] as Vector3).distance_to(B1[j][2])))
	for i in A0.size():
		var pa0: Array = A0[i]
		var pa1: Array = A1[i]
		var ch_a := maxf((pa0[1] as Vector3).distance_to(pa1[1]), (pa0[2] as Vector3).distance_to(pa1[2]))
		var ma := (pa0[4] as Vector3).distance_to(pa1[4])
		for j in B0.size():
			var pb0: Array = B0[j]
			var pb1: Array = B1[j]
			var lim: float = float(pa0[5]) + float(pb0[5]) + SAG * (ch_a + float(ch_b[j])) + Body.CROSS_MIN
			# cheap reject: apart at the start by more than both centres travel
			if (pa0[4] as Vector3).distance_to(pb0[4]) - ma - (pb0[4] as Vector3).distance_to(pb1[4]) > lim:
				continue
			if Body.seg_seg(pa0[4], pa1[4], pb0[4], pb1[4]) < lim:
				return true
	return false


static func fighter_hits(sa: Scene, ba: Body, sb: Scene, bb: Body, xf: Transform3D, fps := 30) -> Array:
	var st := {"out": [], "going": {}, "tp": -1.0}
	var n := int(ceil(maxf(sa.length(), sb.length()) * fps))
	var dt := 1.0 / fps
	var sub := maxi(1, int(ceil(SUB_HZ / fps)))
	var caps0 := []
	for f in n + 1:
		var t := float(f) / fps
		_pose2(sa, ba, sb, bb, t)
		var caps1 := [ba.cross_caps(), bb.cross_caps(xf)]
		if f > 0 and sub > 1 and _may_touch(caps0, caps1):
			for i in range(1, sub):
				var ts := t - dt + dt * i / sub
				_pose2(sa, ba, sb, bb, ts)
				_sample(st, sa, ba, sb, bb, xf, ts)
			_pose2(sa, ba, sb, bb, t)
		_sample(st, sa, ba, sb, bb, xf, t)
		caps0 = caps1
	var out: Array = st["out"]
	out.sort_custom(func(x, y): return float(x["t"]) < float(y["t"]))
	return out


## one sample at t (the bodies posed at t; left posed at t): contacts that go on deepen theirs, new ones start a row
static func _sample(st: Dictionary, sa: Scene, ba: Body, sb: Scene, bb: Body, xf: Transform3D, t: float) -> void:
	var out: Array = st["out"]
	var going: Dictionary = st["going"]   # kind + zone -> index in out of the contact still going on
	var tp: float = st["tp"]
	st["tp"] = t
	var now := cross_named(ba, bb, xf)
	for k in going.keys():
		if not now.has(k):
			going.erase(k)
	var fresh := []
	for k in now:
		if going.has(k):
			var g: Dictionary = out[going[k]]
			g["depth"] = maxf(float(g["depth"]), float(now[k][2]))
		else:
			fresh.append(k)
	for k in fresh:   # (each new one re-poses the bodies, then puts them back at t)
		var c: Array = now[k]
		var theirs: bool = c[3] == "struck"   # the other's weapon strikes; else the hero's part does
		var h := {"kind": c[3], "zone": (k as String).get_slice("|", 1), "depth": float(c[2]), "t": t,
			"part": c[1] if theirs else c[0], "on": c[0] if theirs else c[1], "by": "other" if theirs else "hero",
			"at": cross_at(ba, bb, xf, c), "u": -1.0, "speed": 0.0}
		var ax := _axes(ba, bb, xf, c)
		var sp := seg_params(ax[0], ax[1], ax[2], ax[3])
		var s: float = sp.y if theirs else sp.x
		var sbody: Body = bb if theirs else ba
		var sxf: Transform3D = xf if theirs else Transform3D.IDENTITY
		var p_now := _spot(sbody, h["part"], s, sxf)
		if Body.is_wep(h["part"]):
			var butt: Vector3 = sbody.wep2_point(0.0) if h["part"] in Body.WEAPON2 else sbody.wep_point(0.0)
			h["u"] = (sxf * butt).distance_to(p_now)
		if tp >= 0.0:
			_pose2(sa, ba, sb, bb, tp)
			h["speed"] = _spot(sbody, h["part"], s, sxf).distance_to(p_now) / (t - tp)
			var lo := tp   # the onset: between the sample before (not in it) and this one
			var hi := t
			for i in BISECT:
				var mid := (lo + hi) * 0.5
				_pose2(sa, ba, sb, bb, mid)
				if cross_named(ba, bb, xf).has(k):
					hi = mid
				else:
					lo = mid
			h["t"] = hi
			_pose2(sa, ba, sb, bb, hi)
			var at_hi := cross_named(ba, bb, xf)
			if at_hi.has(k):
				h["at"] = cross_at(ba, bb, xf, at_hi[k])   # where it first touches
			_pose2(sa, ba, sb, bb, t)
		going[k] = out.size()
		out.append(h)
