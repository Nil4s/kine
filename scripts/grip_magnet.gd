## THE MAGNET (round 47, GATES CC3, UPGRADES_300 #338; Nick 10-18: "a magnetic version for hands, that could adapt
## hands within its limits w weapons and its limits of grip"). The free hand dragged near the weapon the other hand
## holds snaps onto the grippable part of the shaft, holding it the standard way (the kind's grip file, turned round the
## shaft to the side the hand came from, the fingers wrapped by GripWrap). Dragged on, it SLIDES along the shaft and
## ROLLS round it; pulled past the shaft's ends, too far off it, or past the arm's reach, it lets go. The arm is fitted
## by Body.fit_hand, inside every joint's limits (clamp_ang): it can fall short, never bend past.
##   snap   the wrist within one hand length (this body's hand_r, wrist to knuckles) of the shaft's axis, between its
##          grippable ends
##   held   the palm within 2 cm of the shaft's surface; a slide or roll the arm cannot make stops there (still held)
##   let go the wrist dragged 1.5 hand lengths off the axis, half a hand past an end, or (snapping) no reachable place
class_name GripMagnet
extends RefCounted

const REACH_MISS := 0.015   # the arm cannot get the wrist there: let go (slide_hand's own bar)
const PALM_ON := 0.02       # the palm's distance from the shaft's surface that still holds it
const SEARCH_MAX := 3       # NA6: places searched at most (each ~0.1-0.25 s)
const SEARCH_NEAR := 0.03   # NA6: the joint search runs only when the quick way came this close (m): its 12..1.5 deg
                            # steps close a near miss; a place further off stays out of reach (it cost 0.6 s to learn)


## the hand's length on this body (wrist -> knuckles, rest pose) = the snap distance
static func hand_len(B: Body) -> float:
	return ((B.e0["hand_r"] - B.p0["hand_r"]) as Vector3).length()


## the grippable part of the held weapon, metres from the knob: [lo, hi]. A swelling barrel (the bat) ends it at the
## handle; a plain shaft (the staff) is grippable to its far end; a head (the axe, the hammer) ends it below the head
static func span(B: Body) -> Vector2:
	var lo := B.wep_r_handle
	var hi := B.wep_handle
	if B.wep_r_barrel <= B.wep_r_handle * 1.1 and B.wep_head.is_empty():
		hi = B.wep_len - B.wep_r_handle
	return Vector2(lo, maxf(lo, hi))


## the standard hand on a shaft, in the weapon's frame with the knob at 0: [wrist offset, turn] for hand h, from the
## kind's grip file: Nick's own second hand when the file has one for h (the staff), else the main hand's grip (the bat
## file when the kind has none; the other hand is its mirror, x flipped, as the file says)
static func template(B: Body, h: String) -> Array:
	var path := "res://data/grips/%s.json" % B.wep_kind
	if not FileAccess.file_exists(path):
		path = "res://data/grips/metal_bat.json"
	var g: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	# Nick's own second hand for this kind (the staff's "second", fitted from his two-hand pose) when it is this hand:
	# already in the weapon's frame
	var sec: Dictionary = g.get("second", {})
	if not sec.is_empty() and String(sec.get("hand", "")) == h:
		var w2 := Body._v(sec["lpos"]) * B.hand_s(h)   # the file's offset is default-hand metres (round 52)
		w2.y = 0.0
		var r2: Array = sec["lrot"]
		return [w2, Quaternion(r2[0], r2[1], r2[2], r2[3]).normalized()]
	var lp := Body._v(g["local_pos"])
	var lr: Array = g["local_rot"]
	var q := Quaternion(lr[0], lr[1], lr[2], lr[3]).normalized()
	if h.ends_with("_l") != String(g.get("hand", "hand_r")).ends_with("_l"):
		lp.x = -lp.x
		q = Quaternion(q.x, -q.y, -q.z, q.w)
	var t := q.inverse()   # the hand's turn in the weapon's frame
	var kh := B.knob_in_hand(lp, q, h)   # the file's knob in default-hand metres, this hand's size and palm here (round 52)
	var w := -(t * kh)
	w.y = 0.0   # the file's own place along the shaft (the staff's 0.30 m) is not the template's: u says where
	return [w, t]


## the wrist place and turn (world) for hand h held at u along the shaft, rolled phi (rad) round it
static func pose_at(B: Body, h: String, u: float, phi: float) -> Array:
	var x := B.wep_xform()
	var q: Quaternion = x[1]
	var tp := template(B, h)
	var R := Quaternion(Vector3.UP, phi)
	var lpos: Vector3 = R * (tp[0] as Vector3)
	var lrot: Quaternion = (R * (tp[1] as Quaternion)).normalized()
	return [(x[0] as Vector3) + q * (lpos + Vector3(0, u, 0)), (q * lrot).normalized(), lpos, lrot]


## where a world point sits round and along the shaft: [u (m along), r (m off the axis), angle round it (rad)]
static func shaft_coords(B: Body, p: Vector3) -> Array:
	var x := B.wep_xform()
	var l: Vector3 = (x[1] as Quaternion).inverse() * (p - (x[0] as Vector3))
	return [l.y, Vector2(l.x, l.z).length(), atan2(l.x, l.z)]


## the roll that puts the template's wrist on the side of the shaft at `ang` (rad round it)
static func roll_to(B: Body, h: String, ang: float) -> float:
	var w: Vector3 = template(B, h)[0]
	return ang - atan2(w.x, w.z)


## one step of a drag of hand h toward the wrist target `target` (world). Returns "free" (no weapon in the other hand,
## or not near it: the plain reach), "snap", "held" (slid / rolled), or "let go".
## quick (a mouse step, NA6): the places are tried the quick way only, never searched; main.gd searches once on release
static func drag(B: Body, h: String, target: Vector3, quick := false) -> String:
	var other := "hand_l" if h == "hand_r" else "hand_r"
	if not (B.wep_on and B.wep_hand == other):
		B.reach(h, target)
		return "free"
	var L := hand_len(B)
	var sp := span(B)
	var sc := shaft_coords(B, target)
	var u: float = sc[0]
	var holding := B.grip and String(B.grip2.get("hand", "")) == h
	if holding:
		if float(sc[1]) > 1.5 * L or u < sp.x - 0.5 * L or u > sp.y + 0.5 * L:
			return _let_go(B, h, target)
	elif float(sc[1]) > L or u < sp.x or u > sp.y:
		B.reach(h, target)
		return "free"
	u = clampf(u, sp.x, sp.y)
	var phi := roll_to(B, h, sc[2])
	# the place asked for first; if the arm cannot get there, the nearest place it CAN: a little along the shaft toward
	# the holding hand, a little round it (a hand reaching for a pole takes the part it can reach). Let go if none.
	var keep := B.state()
	var tries := [[0.0, 0.0], [0.0, 30.0], [0.0, -30.0], [-0.05, 0.0], [-0.05, 30.0], [-0.05, -30.0], [0.0, 60.0],
		[0.0, -60.0], [-0.10, 0.0], [-0.10, 30.0], [-0.10, -30.0]]
	var toward := -1.0 if _main_u(B) < u else 1.0
	var best := []
	var best_miss := INF
	# THE FREEZE (round 49, GATES NA6; Nick 10-18: "a little freeze for 0.5 sec" moving a hand when the pose is all
	# wrong): every place used to run fit_hand's full joint search (a whole body's contacts a step), and when NONE was
	# reachable all 11 ran: up to 9.6 s a mouse step. Now each place is tried the QUICK way (B.fast: reach + turn, no
	# search), and only the best of them gets the search, once.
	var was_fast := B.fast
	var best_ps := []
	var near := []   # [place, pose] the quick way got within SEARCH_NEAR, in the tries' order (the asked place first)
	for t in tries:
		var uu := clampf(u + toward * absf(float(t[0])), sp.x, sp.y)
		var pp := phi + deg_to_rad(float(t[1]))
		var ps := pose_at(B, h, uu, pp)
		B.set_state(keep)
		B.fast = true   # NA6: every place the quick way first (11 full fits on an unreachable pose were the freeze)
		var miss := B.fit_hand(h, ps[0], ps[1])
		B.fast = was_fast
		# held means the PALM on the shaft, not only the wrist near its spot (a wrist that cannot turn far enough
		# leaves the palm off the handle: round 47, the roll drag left it 2.7 cm off)
		var bad := maxf(0.0, miss - REACH_MISS) + maxf(0.0, palm_off(B, h) - PALM_ON)
		if bad < best_miss - 1e-5:
			best_miss = bad
			best = [uu, B.state()]
			best_ps = ps
		if bad <= 0.0:
			break
		if bad <= SEARCH_NEAR:
			near.append([uu, ps])
	if not quick and not was_fast:
		# the full fit (the joint search, which also turns the wrist: the roll drag needs it), once the mouse lets go:
		# held the quick way -> refit that one place; not held -> search the (at most SEARCH_MAX) places that came near
		var todo := [[best[0], best_ps]] if best_miss <= 0.0 and not best_ps.is_empty() else near.slice(0, SEARCH_MAX)
		for nb in todo:
			B.set_state(keep)
			var miss2 := B.fit_hand(h, nb[1][0], nb[1][1])
			var bad2 := maxf(0.0, miss2 - REACH_MISS) + maxf(0.0, palm_off(B, h) - PALM_ON)
			if bad2 <= 0.0 or bad2 < best_miss - 1e-5:
				best_miss = bad2
				best = [nb[0], B.state()]
			if bad2 <= 0.0:
				break
	if best_miss > 0.0:
		B.set_state(keep)
		if holding:
			return "held"   # the hand stops where it is: the arm cannot slide or roll it further (its limits)
		return _let_go(B, h, target)
	u = best[0]
	B.set_state(best[1])
	var a := B.wep_point(sp.x)
	var b := B.wep_point(sp.y)
	B.wrap_fingers(h, a, b, B.wep_r_handle)
	var fing := {}
	for j in Body.FINGERS:
		if j.ends_with(h.right(2)):
			var v: Vector3 = B.ang[j]
			fing[j] = [snappedf(v.x, 0.1), snappedf(v.y, 0.1), snappedf(v.z, 0.1)]
	var x := B.wep_xform()
	var q: Quaternion = x[1]
	var wl: Vector3 = q.inverse() * ((B.P[h] as Vector3) - (x[0] as Vector3))
	B.grip2 = {"hand": h, "u": snappedf(u, 0.001), "lpos": Body._p((wl - Vector3(0, u, 0)) / B.hand_s(h)),
		"lrot": Body._q((q.inverse() * (B.G[h] as Quaternion)).normalized()), "fingers": fing}
	B.grip = true
	B.grip_u = u
	return "held" if holding else "snap"


## the palm's distance from the shaft's surface (m; the palm as capture_second places it)
static func palm_off(B: Body, h: String) -> float:
	return float(shaft_coords(B, B.palm_point(h))[1]) - B.wep_r_handle


## where the holding hand is along the shaft (m from the knob)
static func _main_u(B: Body) -> float:
	return float(shaft_coords(B, B.P[B.wep_hand])[0])


static func _let_go(B: Body, h: String, target: Vector3) -> String:
	B.grip = false
	B.grip2 = {}
	B.reach(h, target)
	return "let go"
