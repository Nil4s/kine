## rise.gd - the helpers that generate cards for SIT DOWN, STAND UP and GET UP FROM THE FLOOR (ROADMAP 94).
## Each helper returns {"cards": [{"name", "pose", "move", "hold", "plant"}], "report": {...}} and leaves B in the
## last pose; the caller adds the cards in ONE undo step (main.gd's _use_card pattern; no ribbon button yet).
##
## SIT-TO-STAND, a chair (Props "chair"; the body faces away from the back, as Sit here does):
##   stand_up(B, prop): from the seated pose (hips on the seat, feet where they stood to rise) to standing. The feet never
##   move: each key plants both feet on their floor marks (Body.plant, the leg's IK), so a slide is only the IK's residual.
##   Trunk flexion rises to TRUNK_PEAK at seat-off, then falls to upright. The hips move forward over the feet and rise.
##   The forward shift at seat-off is SOLVED by bisection so the centre of mass (Balance) is COM_MIN inside the support.
##   sit_down(B, prop): the same keys played backwards (the body backs onto the seat; the seat-on is key 5 of 0..8).
## GET UP FROM THE FLOOR: get_up(B, xz): supine -> roll onto the right side -> hands and knees (see the block below).
##
## CITED DATA (the roadmap's sources; the numbers are the ones it gives, I did not re-read the papers here):
##   seat-off at ~35-40% of the rise (Schenkman et al. 1990; Riley et al. 1991): SEAT_OFF = 0.375 = key 3 of 0..8.
##   trunk flexion ~40-50 deg before seat-off: TRUNK_PEAK = 45 deg, split over the three spine joints (15 deg each).
##   total ~1.5-2.5 s: DUR = 2.0 s, eight equal moves of 0.25 s.
##   Floor: the order supine, roll, hands and knees is the pattern the roadmap cites to VanSant 1988. The heights, the
##   joint angles and the timing of the floor rise are OURS, set on this body, not taken from that paper.
##
## REVIEW (measured by tests/rise_test.gd on this body, before the bars were checked):
##   seat-off trunk flexion 45.0 deg; COM margin at seat-off 2.0 cm (the solved minimum) and after it 2.0, 3.5, 2.5, 0.7,
##   7.2 cm (all inside); feet creep 0.11 mm over the 2 s at 60 Hz; the seated thigh's lowest surface 0.9 cm under the seat top.
##   Floor: the keys have at most 8.5 mm of a part inside the floor (the kneel, the toes' and hands' solves); the raw
##   blend between keys, sampled at 60 Hz, at most 8.5 mm (needs the fine blend steps: FLOOR_STEPS).
class_name Rise
extends RefCounted

const SEAT_OFF := 0.375       # the fraction of the rise at which the hips leave the seat (cited)
const TRUNK_PEAK := 45.0      # deg of trunk flexion at seat-off (the cited 40-50 deg band's middle)
const DUR := 2.0              # s, the whole rise (the cited 1.5-2.5 s band's middle)
const NKEY := 9               # keys 0..8: u = k / 8; seat-off is key 3 (3/8 = 0.375)
const COM_MIN := 0.02         # m: the centre of mass this far inside the support at seat-off (our bar, not published)
const STAND_FWD := 0.45       # m: the standing pelvis this far ahead of the seat's middle (where the feet are)
const SEAT_BACK := 0.05       # m: the seated pelvis this far behind the seat's middle (as Sit here puts it)
const SPINE := ["spine_01", "spine_02", "spine_03"]
const FEET := ["_l", "_r"]
const FLOOR_DUR := 3.0        # s, the get-up (ours)
const FLOOR_STEPS := 40       # blends between the named floor poses: the scene's straight blend between two keys stays clear
const FLOOR_MM := 0.01        # m: a part this far into the floor is a finding (the roadmap's 1 cm bar)
const HAND_R := 0.047         # m: the hand's radius; its centre this high = the palm on the floor


static func _sm(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## the prop's front (+Z of its frame), level, unit
static func fwd_of(prop: Dictionary) -> Vector3:
	var f: Vector3 = (prop["xf"] as Transform3D).basis * Vector3(0, 0, 1)
	f.y = 0.0
	return f.normalized()


## the seat's middle: the first support's top, over its centre
static func seat_of(prop: Dictionary) -> Vector3:
	var s: Dictionary = Props.supports(prop)[0]
	var c: Vector2 = s["c"]
	var w: Vector3 = (s["xf"] as Transform3D) * Vector3(c.x, 0.0, c.y)
	return Vector3(w.x, float(s["y"]), w.z)


## the body as a standing pose (poses/stand.json), its pelvis at xz, facing `fwd`, standing on the floor
static func _stand(B: Body, xz: Vector2, fwd: Vector3) -> void:
	B.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	B.props = []
	_place(B, xz, (B.p0["pelvis"] as Vector3).y, fwd)
	B.ground()


## the pelvis at (xz, y) facing `fwd` (the twist turns it; the body's own facing is +Z at rest)
static func _place(B: Body, xz: Vector2, y: float, fwd: Vector3) -> void:
	var p: Vector3 = B.p0["pelvis"]
	B.ang["pelvis"] = Vector3(0, 0, rad_to_deg(atan2(fwd.x, fwd.z)))
	B.offset = Vector3(xz.x - p.x, y - p.y, xz.y - p.z)
	B.fk()


static func _trunk(B: Body, deg: float) -> void:
	for j in SPINE:
		B.ang[j] = Vector3(deg / SPINE.size(), 0.0, 0.0)
	B.fk()


## the trunk's flexion now: the three spine joints' bends summed (deg)
static func trunk_flex(B: Body) -> float:
	var s := 0.0
	for j in SPINE:
		s += (B.ang[j] as Vector3).x
	return s


## both feet's ball positions (world), the marks the feet keep
static func _balls(B: Body) -> Array:
	return [(B.P["ball_l"] as Vector3), (B.P["ball_r"] as Vector3)]


## the seated pose: the thighs level, the shins down, the hips on the seat, the feet back on their marks
static func _sitting(B: Body, prop: Dictionary, feet: Array, fwd: Vector3, seat: Vector3) -> void:
	var xz := Vector2(seat.x, seat.z) - Vector2(fwd.x, fwd.z) * SEAT_BACK
	B.props = [prop]
	_place(B, xz, (B.p0["pelvis"] as Vector3).y, fwd)
	for sd in FEET:
		B.ang["thigh" + sd] = Vector3(90, 0, 0)
		B.ang["calf" + sd] = Vector3(90, 0, 0)
	B.fk()
	B.ground()
	for k in 2:
		for i in FEET.size():
			B.plant(FEET[i], feet[i], B.foot_heading(FEET[i]), true)


## one key of the rise: the trunk for u, the pelvis at base + d along fwd and height y, both feet planted on `feet`.
## Returns the largest miss of a foot's ball from its mark (m).
static func _key(B: Body, u: float, d: float, fwd: Vector3, base: Vector2, y: float, feet: Array) -> float:
	var trunk := TRUNK_PEAK * _sm(u / SEAT_OFF) if u <= SEAT_OFF else TRUNK_PEAK * (1.0 - _sm((u - SEAT_OFF) / (1.0 - SEAT_OFF)))
	var xz := base + Vector2(fwd.x, fwd.z) * d
	B.props = []
	_place(B, xz, y, fwd)
	_trunk(B, trunk)
	for k in 2:
		for i in FEET.size():
			B.plant(FEET[i], feet[i], B.foot_heading(FEET[i]), true)
	var miss := 0.0
	for i in FEET.size():
		miss = maxf(miss, ((B.P["ball" + FEET[i]] as Vector3) - (feet[i] as Vector3)).length())
	return miss


## the cards of keys (names, moves) in order, or backwards; every card keeps the feet on their marks
static func _cards(keys: Array, names: Array, move: float, reverse: bool, plant: Array) -> Array:
	var out := []
	var n := keys.size()
	for i in n:
		var k := n - 1 - i if reverse else i
		out.append({"name": names[k], "pose": keys[k], "move": move if i > 0 else -1.0, "hold": 0.0, "plant": plant})
	return out


static func _rise_names() -> Array:
	var out := []
	for k in NKEY:
		out.append("seated" if k == 0 else ("standing" if k == NKEY - 1 else "rising %d/%d" % [k, NKEY - 1]))
	return out


## the stand-up: {"cards": [...], "report": {...}}. B ends standing.
static func stand_up(B: Body, prop: Dictionary) -> Dictionary:
	var keys := _rise_keys(B, prop)
	var report: Dictionary = keys["report"]
	var cards := _cards(keys["keys"], _rise_names(), DUR / (NKEY - 1), false, ["_l", "_r"])
	return {"cards": cards, "report": report}


## the sit-down: the stand-up's keys played backwards: {"cards", "report"}. B ends standing (the first card is that pose).
static func sit_down(B: Body, prop: Dictionary) -> Dictionary:
	var keys := _rise_keys(B, prop)
	var report: Dictionary = keys["report"]
	var cards := _cards(keys["keys"], _rise_names(), DUR / (NKEY - 1), true, ["_l", "_r"])
	return {"cards": cards, "report": report}


## the keys of the rise: [seated, 7 in between, standing] and the report (seat-off margin, each key's trunk and COM)
static func _rise_keys(B: Body, prop: Dictionary) -> Dictionary:
	var fwd := fwd_of(prop)
	var seat := seat_of(prop)
	var base := Vector2(seat.x, seat.z) - Vector2(fwd.x, fwd.z) * SEAT_BACK
	# the standing pose: feet on the floor, the pelvis STAND_FWD ahead of the seat's middle; the feet's marks are these
	_stand(B, Vector2(seat.x, seat.z) + Vector2(fwd.x, fwd.z) * STAND_FWD, fwd)
	var stand_pose := B.to_dict()
	var feet := _balls(B)
	var y_stand: float = (B.P["pelvis"] as Vector3).y
	# the seated pose, feet put back on their marks
	_sitting(B, prop, feet, fwd, seat)
	var seat_pose := B.to_dict()
	var y_seat: float = (B.P["pelvis"] as Vector3).y
	var D := STAND_FWD - SEAT_BACK
	var sb := B.state()
	# the forward shift at seat-off: the least one that puts the COM COM_MIN inside the support (bisection on 0..D)
	var lo := 0.0
	var hi := D
	B.props = []
	_key(B, SEAT_OFF, D, fwd, base, y_seat, feet)
	var m_full: float = Balance.read(B)["margin"]
	B.set_state(sb)
	var solved: bool = m_full >= COM_MIN
	if solved:
		for it in 14:
			var m := (lo + hi) * 0.5
			_key(B, SEAT_OFF, m, fwd, base, y_seat, feet)
			if float(Balance.read(B)["margin"]) >= COM_MIN:
				hi = m
			else:
				lo = m
			B.set_state(sb)
	var d_off := hi if solved else D
	var keys := [seat_pose]
	var rows := []
	var miss_max := 0.0
	for k in range(1, NKEY - 1):
		var u := float(k) / (NKEY - 1)
		var d := d_off * _sm(u / SEAT_OFF) if u <= SEAT_OFF else d_off + (D - d_off) * _sm((u - SEAT_OFF) / (1.0 - SEAT_OFF))
		var y := y_seat if u <= SEAT_OFF else lerpf(y_seat, y_stand, _sm((u - SEAT_OFF) / (1.0 - SEAT_OFF)))
		var miss := _key(B, u, d, fwd, base, y, feet)
		miss_max = maxf(miss_max, miss)
		var bal := Balance.read(B)
		rows.append({"u": u, "trunk": trunk_flex(B), "margin": float(bal["margin"]), "down": bal["down"].size(), "miss": miss})
		keys.append(B.to_dict())
	keys.append(stand_pose)
	B.from_dict(stand_pose)
	var report := {"ok": solved, "d_off": d_off, "seat_off_key": 3, "keys": rows, "miss_max": miss_max}
	report["margin_off"] = float(rows[seat_off_key() - 1]["margin"])
	return {"keys": keys, "report": report}


## the seat-off key's index in NKEY-spaced keys (3)
static func seat_off_key() -> int:
	return int(round(SEAT_OFF * (NKEY - 1)))


## ---- GET UP FROM THE FLOOR (ROADMAP 94, the coordinator's list: supine -> side -> hands and knees -> half-kneel -> stand).
## Anchor poses are solved on this body (feet, knees, hands and toes put on the floor by the joints' own IK, see _kneel and
## _half); the in-between keys are lerps of the joint angles and hips' offset, lifted until clear of the floor (_clear_floor).
## The support at each anchor is the convex hull of its floor contacts (support_polygon), and the COM must lie inside it.
## Sources (checked by search, not by reading the full texts): Schenkman, Berger, Riley, Mann, Hodge 1990, Physical Therapy
## 70(10):638-648 (sit-to-stand phases: I flexion momentum to seat-off, II momentum transfer seat-off to max ankle dorsiflexion,
## III extension, IV stabilisation). VanSant 1988, Physical Therapy 68(2): rising from supine, movement patterns by upper
## extremity, axial and lower extremity; the half-kneel and asymmetric squat are the patterns of the lower extremity (VanSant
## 1988a children). The keys' angles and heights are ours.
## ---- GET UP FROM THE FLOOR.
## Keys: supine (the back on the floor, the arms raised), the roll (the pelvis turned 90 deg about the body's length),
## the side (lying on the right side, the lower arm under the chest), then the kneel (knees and hands on the floor).
## Every key is grounded by the body's own joints: lying = Body.ground_body (the lowest point on the floor); the kneel =
## the hips' height bisected so the knees (thigh ends) touch, the arms straight down from the shoulders with the hands
## reached to the floor (Body.reach on the arm alone), the wrist turned to lay the fist flat, the toes bent so the
## lowest toe point touches. The blends between keys are grounded the same way (_clear_floor lifts a body that is in).
## The get-up plays with the scene's floor-body grounding (Scene.floor_body), as the app's own get-ups do.
static func floor_depth(B: Body) -> float:
	var worst := 0.0
	for j in Body.ORDER:
		var r: float = float(B.rad.get(j, 0.03))
		worst = maxf(worst, r - minf((B.P[j] as Vector3).y, (B.E[j] as Vector3).y))
	return worst


static func _lie_on_back(B: Body, xz: Vector2) -> void:
	B.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	B.props = []
	for sd in FEET:
		for j in ["thigh" + sd, "calf" + sd, "foot" + sd]:
			B.ang[j] = Vector3.ZERO
	B.ang["pelvis"] = Vector3(-90, 0, 0)
	for sd in ["_l", "_r"]:
		B.ang["upperarm" + sd] = Vector3(90, 0, 0)
	B.fk()
	var p: Vector3 = B.p0["pelvis"]
	B.offset = Vector3(xz.x - p.x, 0.0, xz.y - p.z)
	B.fk()
	B.ground_body()


## the body rolled onto its right side from the back: the pelvis turns about the body's long axis (world Z here)
static func _roll_side(B: Body) -> void:
	B.turn_world("pelvis", Quaternion(Vector3(0, 0, 1), deg_to_rad(90.0)))
	B.ground_body()


## the joint's bend (and side, when `sides`) over its range that leaves its parts the least inside the floor: the search
## the knees, toes and hands use. parts = the capsules' names (their ends minus radii). Sets the joint to the best.
static func _least_into_floor(B: Body, j: String, parts: Array, sides := true) -> float:
	var rb: Vector2 = B.lim[j]["bend"]
	var rs: Vector2 = B.lim[j]["side"]
	var v: Vector3 = B.ang[j]
	var best := INF
	var bm := v
	for k in 41:
		for q in (13 if sides else 1):
			var m := Vector3(lerpf(rb.x, rb.y, k / 40.0), lerpf(rs.x, rs.y, q / 12.0) if sides else v.y, v.z)
			B.ang[j] = m
			B.fk()
			var d := 0.0
			for p in parts:
				d = maxf(d, float(B.rad.get(p, 0.03)) - minf((B.P[p] as Vector3).y, (B.E[p] as Vector3).y))
			if d < best:
				best = d
				bm = m
	B.ang[j] = bm
	B.fk()
	return best


## the kneel: the knees and hands on the floor (see the block above). Returns the misses left (m).
static func _kneel(B: Body) -> Dictionary:
	B.props = []
	B.ang["pelvis"] = Vector3(90, 0, 0)
	for sd in FEET:
		B.ang["thigh" + sd] = Vector3(90, 0, 0)
		B.ang["calf" + sd] = Vector3(90, 0, 0)
		B.ang["foot" + sd] = Vector3.ZERO
	for j in SPINE:
		B.ang[j] = Vector3.ZERO
	B.fk()
	var lo := -1.0
	var hi := 0.5
	var thigh_r: float = float(B.rad["thigh_l"])
	for it in 30:   # the hips' height: the knee joints one thigh radius off the floor
		var m := (lo + hi) * 0.5
		B.offset.y = m
		B.fk()
		var kn := ((B.P["calf_l"] as Vector3).y + (B.P["calf_r"] as Vector3).y) * 0.5
		if kn > thigh_r:
			hi = m
		else:
			lo = m
	B.offset.y = (lo + hi) * 0.5
	B.fk()
	var knee_miss := absf(((B.P["calf_l"] as Vector3).y + (B.P["calf_r"] as Vector3).y) * 0.5 - thigh_r)
	for sd in ["_l", "_r"]:   # the arms straight down from the shoulders (side -90 = down at his side): hands land under them
		B.ang["upperarm" + sd] = Vector3(0, -90, 0)
		B.ang["lowerarm" + sd] = Vector3.ZERO
	B.fk()
	for sd in ["_l", "_r"]:
		var sh: Vector3 = B.P["upperarm" + sd]
		B.reach("hand" + sd, Vector3(sh.x, HAND_R, sh.z))
	B.fk()
	var hand_miss := 0.0
	for sd in ["_l", "_r"]:
		hand_miss = maxf(hand_miss, absf((B.P["hand" + sd] as Vector3).y - HAND_R))
	for sd in FEET:   # the ankle, then the toes (bend only: a side turn would splay the feet)
		_least_into_floor(B, "foot" + sd, ["foot" + sd, "ball" + sd], false)
		_least_into_floor(B, "ball" + sd, ["ball" + sd], false)
	for sd in ["_l", "_r"]:   # a fist on the floor (the knuckles), then the wrist that leaves the fist least inside it
		B.hand_pose(sd.right(1), "fist")
		var parts := ["hand" + sd]
		parts.append_array(B.hand_joints(sd.right(1)))
		_least_into_floor(B, "hand" + sd, parts)
	return {"knee": knee_miss, "hand": hand_miss}


## the get-up: {"cards": [...], "report": {"depth": [mm per key], "miss": {...}, "ok": bool}}. B ends kneeling.









const FLOOR_KEYS := ["supine", "side", "kneel", "half-kneel", "stand"]
const FLOOR_MID := 1         # in-between keys per blend between anchors (cards: 5 anchors + 4 blends = 9)
const TOUCH := 0.015         # m: a part's lowest point this close to the floor counts as touching it


static func _support_pts(B: Body) -> PackedVector2Array:
	# the app's own foot footprints (Balance.footprint, the circles about each foot's ankle and ball) where a foot is down,
	# plus every other part whose lowest point is within TOUCH of the floor (hands, knees, the lying body)
	var pts := PackedVector2Array()
	var feet := {}
	for sd in ["_l", "_r"]:
		var f := Balance.footprint(B, sd)
		if f.size() > 0:
			pts.append_array(f)
			feet[sd] = true
	for j in Body.ORDER:
		if feet.has("_l") and j.ends_with("_l") and j in ["foot_l", "ball_l", "toe_l"]:
			continue
		if feet.has("_r") and j.ends_with("_r") and j in ["foot_r", "ball_r", "toe_r"]:
			continue
		var r: float = float(B.rad.get(j, 0.03))
		for e in [B.P[j], B.E[j]]:
			var v: Vector3 = e
			if v.y - r < TOUCH:
				pts.append(Vector2(v.x, v.z))
	return pts


## the COM's distance inside the convex hull of the body's floor contacts (m; + inside, - outside, -INF = no contact)
static func support_margin(B: Body) -> float:
	var hull := Balance.hull(_support_pts(B))
	var c := Balance.com(B)
	return Balance.signed_dist(hull, Vector2(c.x, c.z))


## the body on its back, arms by its sides (lying on the floor, not raised)
static func _lie_back_arms_down(B: Body, xz: Vector2) -> void:
	_lie_on_back(B, xz)
	for sd in ["_l", "_r"]:
		B.ang["upperarm" + sd] = Vector3(0, -90, 0)
		B.ang["lowerarm" + sd] = Vector3.ZERO
	B.fk()
	B.ground_body()


## half-kneel: the left knee on the floor under the hips (thigh upright, shin flat behind), the right foot ahead (thigh and
## shin bent), the trunk upright, the arms at the sides. The body is then lowered until its lowest part touches (_settle).
static func _half(B: Body) -> Dictionary:
	B.props = []
	B.ang["pelvis"] = Vector3.ZERO
	for j in SPINE:
		B.ang[j] = Vector3.ZERO
	B.ang["thigh_l"] = Vector3.ZERO
	B.ang["calf_l"] = Vector3(90, 0, 0)
	B.ang["thigh_r"] = Vector3(70, 0, 0)
	B.ang["calf_r"] = Vector3(20, 0, 0)
	for sd in ["_l", "_r"]:
		B.ang["upperarm" + sd] = Vector3(0, -65, 0)
		B.ang["lowerarm" + sd] = Vector3(10, 0, 0)
	B.offset = Vector3(0.0, 0.5, 0.0)
	B.fk()
	_settle(B)
	return {"lowest": floor_depth(B)}


## slides the body on the floor so its COM sits over the centre of its support (a rigid shift, no joint changes)
static func _centre_on_support(B: Body) -> void:
	var pts := _support_pts(B)
	if pts.size() == 0:
		return
	var m := Vector2.ZERO
	for q in pts:
		m += q
	m /= float(pts.size())
	var c := Balance.com(B)
	B.offset.x += m.x - c.x
	B.offset.z += m.y - c.z
	B.fk()


## lowers (or lifts) the body until its lowest part just touches the floor (floor_depth 0 within 0.1 mm)
static func _settle(B: Body) -> void:
	var lo := -1.0
	var hi := 1.0
	for it in 40:
		var m := (lo + hi) * 0.5
		B.offset.y = m
		B.fk()
		if floor_depth(B) > 0.0:
			lo = m
		else:
			hi = m
	B.offset.y = hi
	B.fk()


## the body's joint angles and offset, to put back later (the keys are built from one another)
static func _snap(B: Body) -> Array:
	return [B.ang.duplicate(), B.offset]


static func _restore(B: Body, snap: Array) -> void:
	B.ang = (snap[0] as Dictionary).duplicate()
	B.offset = snap[1]
	B.fk()


## lifts the body until no part is inside the floor (a key or a blend between keys is never inside it)
static func _clear_floor(B: Body) -> void:
	for it in 6:
		var d := floor_depth(B)
		if d <= 0.0:
			return
		B.offset.y += d
		B.fk()


## the blend between two states at t (0..1): every joint angle and the offset lerped, then lifted clear of the floor
static func _blend(B: Body, a: Array, b: Array, t: float) -> void:
	_restore(B, a)
	for j in B.ang.keys():
		B.ang[j] = (a[0][j] as Vector3).lerp(b[0][j], t)
	B.offset = (a[1] as Vector3).lerp(b[1], t)
	B.fk()
	_clear_floor(B)


## the get-up: {"cards": [...], "report": {"depth": [...], "margin": [...], "ok": bool}}. B ends standing.
## The cards: each anchor, with FLOOR_MID blends between anchors (9 cards for 5 anchors and FLOOR_MID = 1).
static func get_up(B: Body, xz: Vector2) -> Dictionary:
	var anchors := []
	_lie_back_arms_down(B, xz)
	anchors.append(_snap(B))
	# side: the pelvis rolled 90 deg about the body's length, the arms forward (the lower one under the chest)
	_restore(B, anchors[0])
	_roll_side(B)
	_settle(B)
	anchors.append(_snap(B))
	# kneel: hands and knees (the solve from the side)
	_kneel(B)
	anchors.append(_snap(B))
	# half-kneel: the right foot forward, the left knee down
	_half(B)
	anchors.append(_snap(B))
	# stand: the stand pose on the same spot, feet flat
	_stand(B, xz, Vector3(0, 0, 1))
	_centre_on_support(B)
	_settle(B)
	anchors.append(_snap(B))
	var states := []
	var names := []
	for k in anchors.size():
		states.append(anchors[k])
		names.append(FLOOR_KEYS[k])
		if k < anchors.size() - 1:
			for m in range(1, FLOOR_MID + 1):
				states.append(["mid", k, m])
				names.append("%s to %s" % [FLOOR_KEYS[k], FLOOR_KEYS[k + 1]])
	var poses := []
	var depth := []
	var margin := []
	var good := true
	for i in states.size():
		var st = states[i]
		if st is Array and st.size() == 2 and st[0] is Dictionary:
			_restore(B, st)
		else:
			var a: int = st[1]
			_blend(B, anchors[a], anchors[a + 1], float(st[2]) / (FLOOR_MID + 1))
		poses.append(B.to_dict())
		var d: float = floor_depth(B)
		depth.append(d)
		var mg := support_margin(B)
		margin.append(mg)
		good = good and d <= FLOOR_MM
	var cards := _cards(poses, names, FLOOR_DUR / (poses.size() - 1), false, [])
	return {"cards": cards, "report": {"depth": depth, "margin": margin, "ok": good}}
