## scene.gd - a SCENE = saved poses in a row ("cards"); the poser makes the movement between them. Math in MATH.md.
##
## Each card: {"name", "pose" (Body.to_dict), "move": seconds to get here from the card before (-1 = auto), "hold":
## seconds it stays still}. Between two cards, at u = 0..1 of the move:
##   NATURAL (default): the body leads and the ends follow. Each joint has a level L (hips 0, back 1, neck/shoulder
##   blades 2, upper arm/thigh 3, forearm/shin 4, hand/foot 5, fingers 6). Its own progress
##       u_j = clamp((u - LAG * L/6) / (1 - LAG), 0, 1),   LAG = 0.3
##   eased with smootherstep  e = u^3 (6u^2 - 15u + 10)  (zero speed AND zero acceleration at both ends: no jerk).
##   So the hips start first and the hands arrive last, like a real body (overlapping action).
##   PLAIN: every joint together, e = u^2 (3 - 2u).
##   Every angle blends between two legal values, so every frame is inside the body's ranges.
## AUTO time: the biggest angle change among the big joints (not fingers) sets it:
##       move = clamp(0.25 + biggest_deg / 200, 0.3, 1.6) s     (90 deg -> 0.7 s, 180 deg -> 1.15 s)
## FLOW card ("flow": true; 10-13, from comparing a real swing): a PASS-THROUGH key. Smootherstep stops every joint at
##   every card, so a swing slowed to zero AT the contact card (a hitch real swings never have). The moves from the
##   last normal card before a flow run to the first after it are eased as ONE move; the path goes through the flow
##   cards' poses on a monotone cubic (Fritsch-Carlson: a joint that reverses at a flow card stops there, as it must;
##   one that keeps going passes through at speed; nothing overshoots its two neighbours, so limits hold). Its hold is 0.
## SPLINE scene ("spline": true; 10-14, Nick: "more easy move and more natural", ~30 cards a combat scene): the WHOLE
##   scene is one smooth curve per angle, timed by the cards' own times (no global ease, so a card is where its time says).
##   A card with hold 0 is passed THROUGH; a card with hold > 0, and the first and last card, is a STOP. At a pass-through
##   card each angle's speed is the weighted harmonic mean of the two secants (Fritsch-Butland / Brodlie, as in scipy's
##   PCHIP): it keeps going at speed, and is 0 where that angle turns back. Between cards a cubic Hermite: monotone, so
##   no angle leaves the range of its two cards (limits hold by construction). Smootherstep stops EVERY joint at EVERY
##   card, so 30 cards would be 30 stops; this stops only where the body really does.
##   Overlap ("successive breaking of joints"): a joint of level L reads the curve LEAD * (5 - L) s AHEAD, so the hips
##   lead, the hands are exactly on the cards' times (the strike's timing is the cards'), the fingers trail.
## WALK card ("walk": true; round 42, Nick: "make them real"): over a run of walk cards the HIPS' travel (the offset)
##   is one curve through every card's offset at its arrival time, stopping only at the run's ends: a walking body
##   keeps going (people's speed varies ~10 % over a stride), it does not stop at each step. Before, every move eased
##   the travel to rest at its card and NATURAL's overlap let the hips finish the step in its first 70 % (x = u / 0.7)
##   while the stepping foot waited (level 5): the hips ran 2.3 m/s past the back foot, the leg locked straight and the
##   knee snapped ~54 deg in a frame (1628 deg/s; people's knee peaks ~400 in swing). Monotone cubic Hermite: interior
##   slopes as _mono (harmonic mean of the two secants), 0 at both ends (from standing, to standing). Joints and feet
##   keep their own easing. Saved only when set.
## EASE PRESETS (round 10, GATES Q2): a card's "ease" sets how the plain move INTO it eases. Absent = smooth (the
##   above). "linear": e = x; "in": e = x^3 (starts slow); "out": e = 1 - (1 - x)^3 (ends slow); "snap": e = 0 until the
##   card's arrival, then 1 (the pose before is held and the body jumps: a hit, a cut). x is the joint's own progress
##   (with NATURAL's overlap) or u (PLAIN); snap ignores the overlap. Flow runs and spline scenes have their own curves
##   and do not read it. Saved only when set, so older scenes save byte-identical.
## PLANTED FEET (round 10, GATES Q3): a card's "plant": ["_l"] (or "_r", or both) holds that foot where it stood in
##   the card BEFORE the run of cards that plant it, for the whole run (every move into those cards and every hold):
##   the leg is re-solved every frame (Body.plant), the poses are not changed, so taking the plant off gives the old
##   motion back. It works in spline scenes too, where the per-move pinning above does not stop a stance that differs
##   by a few cm from card to card from creeping along the floor (combo3 in spline: a 5 cm FOOT SLIDE).
## CLEARANCE: if an in-between frame puts parts inside each other (and the two cards don't), clear() adds a pass-by
##   pose at the worst frame: the arm involved is lifted out from the body until that frame is clean. It shows up as its
##   own card ("pass-by"), so you can see and edit it.
class_name Scene
extends RefCounted

const LAG := 0.3
const EASES := ["smooth", "linear", "in", "out", "snap"]   # a card's ease preset (EASE PRESETS above)
const LEAD := 0.015    # spline: seconds each joint level leads the next (hips 75 ms ahead of the hands)
var cards := []        # [{"name", "pose", "move", "hold"}]
var audio := {}        # the sound on the timeline (AudioTrack): {"path", "offset" s, "gain_db"}; in the file only when there is one
var markers := []      # named moments on the timeline (round 41, WW5; Markers): [{"t", "name", "kind"}] sorted by t; in the file only when any
var props := []        # the SET (round 37, SS5): [Props dicts {"kind", "xf"}]; in the file as "props" (only when any)
var props_skipped := []   # kinds the file named that this library does not have (from_dict)
var part_keys := {}    # PART KEYS (round 41, WW1): {"<joint>": [{"t", "v": Vector3}]} by time; see scripts/part_keys.gd
var ik := {}           # IK / FK (GAP_ANALYSIS row 13): {"hand_l": [{"t", "target", "pole", "w", "rot"?}]} by time; scripts/limb_ik.gd
var ik_last := {}      # what the last apply()'s IK pass did per limb (LimbIK.play: miss, clamped joints, weight); {} = nothing
var name := "scene"
var natural := true
var layer := {}        # YY9: ONE additive layer, joint -> Vector3 (deg) added to the played angles x layer_w; {} = none
var layer_w := 1.0     # YY9: the layer's weight 0..1 (written only with a layer)
var layers := []       # NA1: more layers over it, in order (see add_layers); [] = none, and nothing is written
var breath := 0.0      # YY6: breaths a minute added on playback (Body.breathe); 0 = off (written only when on)
var spline := false    # one smooth curve through every card (see SPLINE above); off = the per-card ease
var loop := false      # the scene plays round: CHECK grades the seam from the last frame to the first (round 16, W2)
var on_floor := true   # every frame: the hips move up/down so the lowest sole touches the floor (Body.ground)
var floor_body := false   # with on_floor: the whole body's lowest point instead of the soles (get-ups, falls)
var pin := true        # feet that stay put between two clips are planted: they don't slide while the body turns
const STEP := 0.12     # a toe base that moves more than this (m, along the floor) between clips = a step, not planted
var fps := 30
## MOVING HOLDS (10-14, the animators' "dead hold" complaint; opt-in, saved): during a card's hold the UPPER body keeps
## drifting toward the next card, HOLD_DRIFT of the way (smoothstep), so a held pose never freezes; the move out
## starts from the drifted pose (no jump). Hips, legs and the hips' offset stay: a drifting hip would slide the
## planted feet. Not in a spline scene (its holds are its STOPs) nor before a flow run. HOLD_DRIFT is taste, not data.
var moving_holds := false
const HOLD_DRIFT := 0.08
## STEPPED preview (blocking; view only, never saved): each card's pose is held until the next card ARRIVES, no
## in-betweens, the way animators check poses and timing before they spline
var stepped := false


static func level(j: String) -> int:
	if j == "pelvis":
		return 0
	if j.begins_with("spine"):
		return 1
	if j.begins_with("neck") or j == "head" or j.begins_with("clavicle"):
		return 2
	if j.begins_with("upperarm") or j.begins_with("thigh"):
		return 3
	if j.begins_with("lowerarm") or j.begins_with("calf"):
		return 4
	if j.begins_with("hand") or j.begins_with("foot") or j.begins_with("ball"):
		return 5
	return 6


func add(card_name: String, pose: Dictionary, at := -1) -> void:
	var c := {"name": card_name, "pose": pose, "move": -1.0, "hold": 0.3}
	if at < 0 or at >= cards.size():
		cards.append(c)
	else:
		cards.insert(at, c)


## card i's pose flattened, for READING only (move_time: times() runs it for every card, and apply() runs times()
## several times a frame: 8 s per card add on a 30-card scene, measured round 13). Kept per card while the card holds
## the SAME pose dictionary (is_same: a pose is always replaced whole, never edited in place: audited round 13).
## Never write into the result: _drift, which does, flattens its own copy
var _flat_memo := {}


func _flat_read(i: int) -> Dictionary:
	var p: Dictionary = cards[i]["pose"]
	var c: Variant = _flat_memo.get(i)
	if c != null and is_same(c[0], p):
		return c[1]
	var f := Moves._flat(p)
	_flat_memo[i] = [p, f]
	return f


## the time this card's move takes (its own value, or auto from the angles)
func move_time(i: int) -> float:
	if i == 0:
		return 0.0
	var m: float = cards[i]["move"]
	if m > 0.0:
		return m
	var a := _flat_read(i - 1)
	var b := _flat_read(i)
	var big := 0.0
	for j in a["ang"]:
		if level(j) >= 6 or not b["ang"].has(j):
			continue
		var d: Vector3 = ((b["ang"][j] as Vector3) - (a["ang"][j] as Vector3)).abs()
		big = maxf(big, maxf(d.x, maxf(d.y, d.z)))
	big = maxf(big, ((b["offset"] as Vector3) - (a["offset"] as Vector3)).length() * 300.0)   # 30 cm of hips ~ 90 deg
	return clampf(0.25 + big / 200.0, 0.3, 1.6)


## [start of move, arrival, end of hold] per card. MEMOIZED (round 13): apply() runs it about 5 times a frame, 1 ms each
## at 30 cards. The memo holds while every card has the same pose dictionary (is_same), move, hold and flow flag; the
## result is READ-ONLY (a caller that writes into it errors loudly instead of corrupting the next caller's times)
var _times_memo: Array = []   # [[pose, move, hold, flow] per card, the result]


func times() -> Array:
	if not _times_memo.is_empty() and _times_memo[0].size() == cards.size():
		var k: Array = _times_memo[0]
		var same := true
		for i in cards.size():
			var c: Dictionary = cards[i]
			var e: Array = k[i]
			if not (is_same(c["pose"], e[0]) and c["move"] == e[1] and c["hold"] == e[2] and c.get("flow", false) == e[3]):
				same = false
				break
		if same:
			return _times_memo[1]
	var out := _times_raw()
	var key := []
	for c in cards:
		key.append([c["pose"], c["move"], c["hold"], c.get("flow", false)])
	for r in out:
		(r as Array).make_read_only()
	out.make_read_only()
	_times_memo = [key, out]
	return out


func _times_raw() -> Array:
	var out := []
	var t := 0.0
	for i in cards.size():
		var m := move_time(i)
		var h := 0.0 if _flow(i) else float(cards[i]["hold"])
		out.append([t, t + m, t + m + h])
		t += m + h
	return out


func length() -> float:
	var ts := times()
	return ts[-1][2] if not ts.is_empty() else 0.0


## the pose at time t: {"offset", "ang", "weapon"} (same shape as Moves.sample). PART KEYS (round 41, WW1) go on top
## of the card blend: a keyed joint's angles are its keys' curve (PartKeys.at); no part keys = the card blend as it was
func sample(t: float) -> Dictionary:
	var s := _sample_cards(t)
	if part_keys.is_empty() or s.is_empty():
		return s
	return PartKeys.over(s, part_keys, t)


## the card blend alone (every joint from the cards)
func _sample_cards(t: float) -> Dictionary:
	if cards.is_empty():
		return {}
	if spline:
		return _spline_sample(t)
	var ts := times()
	for i in cards.size():
		if t < ts[i][1] and i > 0 and (_flow(i) or _flow(i - 1)):
			return _flow_sample(t, i, ts)
		if t < ts[i][1] and i > 0:
			var u := clampf((t - ts[i][0]) / maxf(1e-6, ts[i][1] - ts[i][0]), 0.0, 1.0)
			var a := Moves._flat(cards[i - 1]["pose"])
			if _drifts(i - 1, ts):
				a = _drift(i - 1, 1.0)
			var r := blend(a, Moves._flat(cards[i]["pose"]), u, cards[i].get("ease", ""))
			if bool(cards[i].get("walk", false)):
				r["offset"] = _walk_offset(t, i, ts)
			return r
		if t < ts[i][2]:
			if _drifts(i, ts):
				return _drift(i, (t - ts[i][1]) / maxf(1e-6, ts[i][2] - ts[i][1]))
			return Moves._flat(cards[i]["pose"])
	return Moves._flat(cards[-1]["pose"])


## does card i's hold drift? (moving holds on, a real hold, a card after it, and that move is a plain one)
func _drifts(i: int, ts: Array) -> bool:
	return moving_holds and not spline and i < cards.size() - 1 and float(ts[i][2]) - float(ts[i][1]) > 1e-4 \
		and not _flow(i + 1)


## card i's pose with its upper body f of the way through its hold's drift toward card i+1
func _drift(i: int, f: float) -> Dictionary:
	var a := Moves._flat(cards[i]["pose"])
	var b := Moves._flat(cards[i + 1]["pose"])
	f = clampf(f, 0.0, 1.0)
	var k := HOLD_DRIFT * f * f * (3.0 - 2.0 * f)
	for j in a["ang"]:
		if j == "pelvis" or j.begins_with("thigh") or j.begins_with("calf") or j.begins_with("foot") or j.begins_with("ball"):
			continue
		if b["ang"].has(j):
			a["ang"][j] = (a["ang"][j] as Vector3) + _d(a["ang"][j], b["ang"][j], j) * k
	return a


func _flow(i: int) -> bool:
	return i > 0 and i < cards.size() - 1 and bool(cards[i].get("flow", false))


## WALK: the hips' offset at t inside the run of walk cards around move i (see WALK at the top)
func _walk_offset(t: float, i: int, ts: Array) -> Vector3:
	var p := i - 1
	while p > 0 and bool(cards[p].get("walk", false)):
		p -= 1
	var q := i
	while q < cards.size() - 1 and bool(cards[q + 1].get("walk", false)):
		q += 1
	var xs := [float(ts[p][2])]
	var ys := [Moves._flat(cards[p]["pose"])["offset"] as Vector3]
	for k in range(p + 1, q + 1):
		xs.append(float(ts[k][1]))
		ys.append(Moves._flat(cards[k]["pose"])["offset"] as Vector3)
	var out := Vector3.ZERO
	for c in 3:
		var v := []
		for y in ys:
			v.append((y as Vector3)[c])
		out[c] = _hermite0(xs, v, t)
	return out


## monotone cubic Hermite through (xs, ys), slope 0 at both ends (_mono's interior slopes)
static func _hermite0(xs: Array, ys: Array, x: float) -> float:
	var n := xs.size()
	var d := []
	for k in n - 1:
		d.append((ys[k + 1] - ys[k]) / maxf(1e-6, xs[k + 1] - xs[k]))
	var m := [0.0]
	for k in range(1, n - 1):
		m.append(0.0 if d[k - 1] * d[k] <= 0.0 else 2.0 / (1.0 / d[k - 1] + 1.0 / d[k]))
	m.append(0.0)
	var k := 0
	while k < n - 2 and x > xs[k + 1]:
		k += 1
	var h: float = maxf(1e-6, xs[k + 1] - xs[k])
	var s := clampf((x - xs[k]) / h, 0.0, 1.0)
	var s2 := s * s
	var s3 := s2 * s
	return (2 * s3 - 3 * s2 + 1) * ys[k] + (s3 - 2 * s2 + s) * h * m[k] + (-2 * s3 + 3 * s2) * ys[k + 1] + (s3 - s2) * h * m[k + 1]


## the flow run around segment i: one easing over [the last normal card before, the first normal card after]; the
## path through every card of the run on a monotone cubic per angle (and hips offset)
func _flow_sample(t: float, i: int, ts: Array) -> Dictionary:
	var p := i - 1
	while _flow(p):
		p -= 1
	var q := i
	while _flow(q):
		q += 1
	var t0: float = ts[p][2]
	var t1: float = ts[q][1]
	var u := clampf((t - t0) / maxf(1e-6, t1 - t0), 0.0, 1.0)
	var poses := []
	var knots := []
	for k in range(p, q + 1):
		poses.append(Moves._flat(cards[k]["pose"]))
		knots.append((ts[k][1] - t0) / maxf(1e-6, t1 - t0) if k > p else 0.0)
	var a: Dictionary = poses[0]
	var ang := {}
	for j in a["ang"]:
		var e := _ease(u, level(j))
		var v := Vector3.ZERO
		for c in 3:
			var ys := []
			for P in poses:
				ys.append(float((P["ang"].get(j, a["ang"][j]) as Vector3)[c]))
			v[c] = _mono(knots, ys, e)
		ang[j] = v
	var eh := _ease(u, 0)
	var off := Vector3.ZERO
	for c in 3:
		var ys := []
		for P in poses:
			ys.append(float((P["offset"] as Vector3)[c]))
		off[c] = _mono(knots, ys, eh)
	# the weapon and the second hand: the plain blend inside the piece the hands are in
	var eb := _ease(u, 5)
	var k2 := 1
	while k2 < knots.size() - 1 and eb > knots[k2]:
		k2 += 1
	var piece := blend(poses[k2 - 1], poses[k2], clampf((eb - knots[k2 - 1]) / maxf(1e-6, knots[k2] - knots[k2 - 1]), 0.0, 1.0))
	return {"offset": off, "ang": ang, "weapon": piece["weapon"], "weapon2": piece.get("weapon2", {})}


## monotone cubic (Fritsch-Carlson) through (xs, ys) at x: no overshoot, zero slope where the values turn back
static func _mono(xs: Array, ys: Array, x: float) -> float:
	var n := xs.size()
	var d := []
	for k in n - 1:
		d.append((ys[k + 1] - ys[k]) / maxf(1e-6, xs[k + 1] - xs[k]))
	var m := [d[0]]
	for k in range(1, n - 1):
		m.append(0.0 if d[k - 1] * d[k] <= 0.0 else 2.0 / (1.0 / d[k - 1] + 1.0 / d[k]))
	m.append(d[n - 2])
	var k := 0
	while k < n - 2 and x > xs[k + 1]:
		k += 1
	var h: float = maxf(1e-6, xs[k + 1] - xs[k])
	var s := clampf((x - xs[k]) / h, 0.0, 1.0)
	var s2 := s * s
	var s3 := s2 * s
	return (2 * s3 - 3 * s2 + 1) * ys[k] + (s3 - 2 * s2 + s) * h * m[k] + (-2 * s3 + 3 * s2) * ys[k + 1] + (s3 - s2) * h * m[k + 1]


## SPLINE: the pose at time t, every joint on one curve through all the cards (see SPLINE at the top)
func _spline_sample(t: float) -> Dictionary:
	var ts := times()
	var T: float = ts[-1][2]
	var F := {}   # card -> its flat pose, read once per sample
	var ang := {}
	# the lead RAMPS IN over the first LEAD * 5 s less the first card's hold (round 18, GATES Y2): read at t + lead x k,
	# k = (t + hold0) / (LEAD * 5) clamped to 0..1, so at t = 0 every joint reads at most hold0 ahead (inside the first
	# card's hold: the first frame IS the first card, as the end's clamp makes the last frame the last card). With
	# hold0 >= 75 ms, k = 1 from t = 0: unchanged. t + lead x k rises with t (slope 1 + lead / 75 ms): no joint runs back
	var k := clampf((t + float(ts[0][2])) / (LEAD * 5.0), 0.0, 1.0)
	for j in _flat_of(F, 0)["ang"]:
		ang[j] = _curve(F, j, clampf(t + LEAD * (5 - level(j)) * k, 0.0, T), ts)
	var off := _curve(F, "_off", clampf(t + LEAD * 5.0 * k, 0.0, T), ts)
	# the weapon's place in the hand: the plain blend inside the piece the hand is in (as in a flow run)
	var w := _where(clampf(t, 0.0, T), ts)
	var piece: Dictionary
	if w[1] < 0.0:
		piece = _flat_of(F, w[0])
	else:
		piece = blend(_flat_of(F, w[0] - 1), _flat_of(F, w[0]), w[1])
	return {"offset": off, "ang": ang, "weapon": piece["weapon"], "weapon2": piece.get("weapon2", {})}


func _flat_of(F: Dictionary, k: int) -> Dictionary:
	if not F.has(k):
		F[k] = Moves._flat(cards[k]["pose"])
	return F[k]


## where time tt falls: [i, s] = moving into card i, s = 0..1 of the move;  [i, -1] = holding card i
func _where(tt: float, ts: Array) -> Array:
	for i in cards.size():
		if tt < ts[i][1] and i > 0:
			return [i, clampf((tt - ts[i][0]) / maxf(1e-6, ts[i][1] - ts[i][0]), 0.0, 1.0)]
		if tt < ts[i][2]:
			return [i, -1.0]
	return [cards.size() - 1, -1.0]


## a STOP card: the first, the last, and any card that holds
func _stop(k: int) -> bool:
	return k <= 0 or k >= cards.size() - 1 or float(cards[k]["hold"]) > 0.0


## joint j ("_off" = the hips' offset) in card k; a joint a card lacks keeps the card before's value
func _val(F: Dictionary, k: int, j: String) -> Vector3:
	var P := _flat_of(F, k)
	if j == "_off":
		return P["offset"]
	if P["ang"].has(j):
		return P["ang"][j]
	return _val(F, k - 1, j) if k > 0 else Vector3.ZERO


## TWEEN (Tween Machine's rule): flat pose a + s x (b - a) on every angle and the hips; s 0 = a, 1 = b, past the ends
## = overshoot (put() clamps to the limits). The weapon's place in the hand blends inside [0, 1] when both hold it in
## the same hand, else it is the nearer card's. Used by the poser's tween slider and tools/detail.gd.
static func mix_flat(a: Dictionary, b: Dictionary, s: float) -> Dictionary:
	var ang := {}
	for j in a["ang"]:
		var v: Vector3 = (a["ang"][j] as Vector3) + _d(a["ang"][j], b["ang"].get(j, a["ang"][j]), j) * s
		if j == "pelvis":
			v.z = wrapf(v.z, -180.0, 180.0)
		ang[j] = v
	var w: Dictionary = a["weapon"] if s < 0.5 else b["weapon"]
	var wa: Dictionary = a["weapon"]
	var wb: Dictionary = b["weapon"]
	if not wa.is_empty() and not wb.is_empty() and wa.get("hand", "") == wb.get("hand", "") and wa.get("hand", "") != "":
		var u := clampf(s, 0.0, 1.0)
		w = wa.duplicate()
		w["local_pos"] = (wa["local_pos"] as Vector3).lerp(wb["local_pos"], u)
		w["local_rot"] = (wa["local_rot"] as Quaternion).slerp(wb["local_rot"], u)
	return {"offset": (a["offset"] as Vector3).lerp(b["offset"], s), "ang": ang, "weapon": w,
		"weapon2": Body.wep2_mix(a.get("weapon2", {}), b.get("weapon2", {}), clampf(s, 0.0, 1.0))}


## b - a, the hips' whole-body turn the short way round (as blend() does)
static func _d(a: Vector3, b: Vector3, j: String) -> Vector3:
	var d := b - a
	if j == "pelvis":
		d.z = wrapf(d.z, -180.0, 180.0)
	return d


## joint j's speed (units/s) at card k: 0 at a stop or where it turns back, else the weighted harmonic mean of the two
## secants (Brodlie: w1 = 2 h_right + h_left, w2 = h_right + 2 h_left) - never more than 3x the smaller: monotone
func _slope(F: Dictionary, k: int, j: String, ts: Array) -> Vector3:
	if _stop(k):
		return Vector3.ZERO
	var hl: float = maxf(1e-6, ts[k][1] - ts[k][0])
	var hr: float = maxf(1e-6, ts[k + 1][1] - ts[k + 1][0])
	var y := _val(F, k, j)
	var dl := _d(_val(F, k - 1, j), y, j) / hl
	var dr := _d(y, _val(F, k + 1, j), j) / hr
	var w1 := 2.0 * hr + hl
	var w2 := hr + 2.0 * hl
	var m := Vector3.ZERO
	for c in 3:
		if dl[c] * dr[c] > 0.0:
			m[c] = (w1 + w2) / (w1 / dl[c] + w2 / dr[c])
	return m


## joint j at time tt: held at a card, a cubic Hermite between two cards
func _curve(F: Dictionary, j: String, tt: float, ts: Array) -> Vector3:
	var w := _where(tt, ts)
	var i: int = w[0]
	var s: float = w[1]
	if s < 0.0:
		return _val(F, i, j)
	var h: float = maxf(1e-6, ts[i][1] - ts[i][0])
	var a := _val(F, i - 1, j)
	var b := a + _d(a, _val(F, i, j), j)
	var ma := _slope(F, i - 1, j, ts)
	var mb := _slope(F, i, j, ts)
	var s2 := s * s
	var s3 := s2 * s
	var v := (2 * s3 - 3 * s2 + 1) * a + (s3 - 2 * s2 + s) * h * ma + (-2 * s3 + 3 * s2) * b + (s3 - s2) * h * mb
	if j == "pelvis":
		v.z = wrapf(v.z, -180.0, 180.0)
	return v


func blend(a: Dictionary, b: Dictionary, u: float, kind := "") -> Dictionary:
	var ang := {}
	for j in a["ang"]:
		var e := _ease(u, level(j), kind)
		ang[j] = (a["ang"][j] as Vector3).lerp(b["ang"].get(j, a["ang"][j]), e)
		if j == "pelvis":
			# the WHOLE BODY's turn takes the short way round (Nick 10-13: a spinning staff swing): keys at 0, 120, -120, 0
			# make one full turn; a plain lerp from 170 to -170 would swing back 340 the long way
			var tz: float = (a["ang"][j] as Vector3).z
			var tb: float = (b["ang"].get(j, a["ang"][j]) as Vector3).z
			ang[j].z = wrapf(tz + wrapf(tb - tz, -180.0, 180.0) * e, -180.0, 180.0)
	var eh := _ease(u, 0, kind)
	var w: Dictionary = a["weapon"].duplicate()
	var wb: Dictionary = b["weapon"]
	var eb := _ease(u, 5, kind)
	if w.is_empty() or wb.is_empty() or w.get("hand", "") != wb.get("hand", ""):
		w = a["weapon"] if eb < 0.5 else wb
	else:
		var key := "local_" if w.get("hand", "") != "" else ""
		w[key + "pos"] = (w[key + "pos"] as Vector3).lerp(wb[key + "pos"], eb)
		w[key + "rot"] = (w[key + "rot"] as Quaternion).slerp(wb[key + "rot"], eb)
	# the SECOND HAND holds during a move only if it holds at both ends: it lets go as the move starts and catches the
	# shaft as it ends (Nick 10-13 staff: before, it stayed glued till halfway and the swing dragged it through the head)
	if not w.is_empty() and not wb.is_empty():
		w = w.duplicate()
		w["grip"] = bool(a["weapon"].get("grip", false)) and bool(wb.get("grip", false))
		# and while it holds at both ends, it SLIDES from one card's place on the shaft to the next (round 45, AA3: it
		# stayed at the first card's place and jumped at the next; between the video axe clip's cards that put the
		# hands up to 31 cm off where the tracker had them, against 7 cm on the cards themselves)
		if w["grip"] and w.has("grip_m") and wb.has("grip_m"):
			w["grip_m"] = lerpf(float(a["weapon"]["grip_m"]), float(wb["grip_m"]), eb)
		# and its saved grip (turn, place, fingers) blends too (round 47)
		if w["grip"] and not (w.get("grip2", {}) as Dictionary).is_empty():
			w["grip2"] = Body.grip2_mix(a["weapon"]["grip2"], wb.get("grip2", {}), eb)
	return {"offset": (a["offset"] as Vector3).lerp(b["offset"], eh), "ang": ang, "weapon": w,
		"weapon2": Body.wep2_mix(a.get("weapon2", {}), b.get("weapon2", {}), eb)}


func _ease(u: float, lv: int, kind := "") -> float:
	if kind == "snap":
		return 1.0 if u >= 1.0 else 0.0
	var x := u if not natural else clampf((u - LAG * lv / 6.0) / (1.0 - LAG), 0.0, 1.0)
	match kind:
		"linear":
			return x
		"in":
			return x * x * x
		"out":
			return 1.0 - (1.0 - x) * (1.0 - x) * (1.0 - x)
	if not natural:
		return u * u * (3.0 - 2.0 * u)
	return x * x * x * (x * (6.0 * x - 15.0) + 10.0)


## put a sampled pose into the body (angles, hips, bat)
static func put(B: Body, s: Dictionary) -> void:
	if s.is_empty():
		return
	B.offset = s["offset"]
	for j in s["ang"]:
		if B.lim.has(j):
			B.ang[j] = B.clamp_ang(j, s["ang"][j])
	B.fk()
	B.put_wep2(s.get("weapon2", {}))
	var w: Dictionary = s["weapon"]
	B.wep_on = not w.is_empty()
	if B.wep_on:
		if B.wep_kind != String(w.get("kind", "metal_bat")):
			B.set_kind(String(w.get("kind", "metal_bat")))
		B.set_weapon_len(w["length"])
		B.wep_hand = w["hand"]
		B.wep_pos = w["pos"]
		B.wep_rot = w["rot"]
		B.wep_lpos = w["local_pos"]
		B.wep_lrot = w["local_rot"]
		B.grip = w["grip"]
		B.grip_u = w["grip_m"]
		if not (w.get("grip2", {}) as Dictionary).is_empty():
			B.grip2 = w["grip2"]   # the card's own Lock-both-hands grip (round 47)


func apply(B: Body, t: float) -> void:
	var was_fast := B.fast
	B.fast = true   # planting legs in playback: limits only (contacts are measured, not avoided, per frame)
	_apply(B, t)
	add_layer(B)           # YY9: on top of the cards; nothing without a layer or at weight 0
	add_layers(B, t)       # NA1: the further layers, in order; nothing without one
	B.breathe(t, breath)   # YY6: on top of the pose; nothing at 0
	ik_last = {}
	if not ik.is_empty():   # IK (GAP_ANALYSIS row 13): last, so a pinned hand stays pinned over everything above
		ik_last = LimbIK.play(ik, B, t)
		if not ik_last.is_empty() and B.wep_on and B.grip and B.wep_hand != "" and not ik_last.has("hand_l" if B.wep_hand == "hand_r" else "hand_r"):
			B.apply_grip()   # the weapon hand moved: the other hand follows it onto the bat (unless it is pinned itself)
	B.fast = was_fast


## LAYER (round 43, GATES YY9; docs/ANIM_RESEARCH.md idea 4: Maya's animation layers, Blender's NLA): one whole-scene
## offset on top of the cards, never written into them: each layered joint gets layer[j] x layer_w added to what the
## cards play, within the joint's limits. Weight 0 or no layer: the body is not touched (byte for byte).
func add_layer(B: Body) -> void:
	if layer.is_empty() or layer_w <= 0.0 or any_solo():   # NA1: a soloed layer silences this one too
		return
	for j in layer:
		if B.ang.has(j):
			B.ang[j] = B.clamp_ang(j, (B.ang[j] as Vector3) + (layer[j] as Vector3) * layer_w)
	B.fk()
	B.apply_grip()


## LAYERS (round 49, GATES NA1, UPGRADES_300 #254; Maya's animation layers: Additive / Override, Weight, Mute, Solo,
## Lock; Blender's NLA: blend Add / Replace with an Influence that can be keyed). Each is a Dictionary:
##   "name", "mode": "add" (v = an offset added, x weight) or "over" (v = the angle; the played angle goes to it by the
##   weight: lerp(below, v, w)), "w" (0..1), "wk" (the weight KEYED: [[t, w], ...] in time order, linear between, held
##   past the ends; with keys the weight is the keyed curve x "w", so "w" dials a keyed layer from none to all), "mute", "solo", "lock" (a locked layer refuses edits; the
##   lock is checked by main.gd's layer commands), "v": {joint: Vector3 degrees}; "v" may also hold "offset": the
##   hips' POSITION (Vector3 metres, Body.offset), added / blended the same way, and then the feet are put back on the
##   floor (Scene._ground, when on_floor) as playback does after it moves the hips (NA2: a head fix moves the hips).
## Played in list order over the cards and the YY9 layer (which stays the scene's first, additive one, so older files
## keep loading and saving byte for byte). Any solo: only the soloed layers play (the YY9 one too is silenced).
## Muted / weight 0: the layer does nothing, byte for byte.
static func layer_weight(L: Dictionary, t: float) -> float:
	var w := clampf(float(L.get("w", 1.0)), 0.0, 1.0)
	var wk: Array = L.get("wk", [])
	if wk.is_empty():
		return w
	return key_curve(wk, t) * w


## the keyed weight curve alone at t ("w" not applied)
static func key_curve(wk: Array, t: float) -> float:
	if t <= float(wk[0][0]):
		return clampf(float(wk[0][1]), 0.0, 1.0)
	for i in range(1, wk.size()):
		if t <= float(wk[i][0]):
			var a: Array = wk[i - 1]
			var b: Array = wk[i]
			var u := (t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1e-9)
			return clampf(lerpf(float(a[1]), float(b[1]), u), 0.0, 1.0)
	return clampf(float(wk[-1][1]), 0.0, 1.0)


func any_solo() -> bool:
	for L in layers:
		if bool(L.get("solo", false)):
			return true
	return false


func add_layers(B: Body, t: float) -> void:
	if layers.is_empty():
		return
	var solo := any_solo()
	var touched := false
	var moved := false
	for L in layers:
		if bool(L.get("mute", false)) or (solo and not bool(L.get("solo", false))):
			continue
		var w := layer_weight(L, t)
		if w <= 0.0:
			continue
		for j in L.get("v", {}):
			if j == "offset":
				var o: Vector3 = L["v"][j]
				B.offset = B.offset + o * w if String(L.get("mode", "add")) == "add" else B.offset.lerp(o, w)
				moved = true
				touched = true
				continue
			if not B.ang.has(j):
				continue
			var v: Vector3 = L["v"][j]
			var a: Vector3 = B.ang[j]
			B.ang[j] = B.clamp_ang(j, a + v * w if String(L.get("mode", "add")) == "add" else a.lerp(v, w))
			touched = true
	if touched:
		B.fk()
		if moved and on_floor:
			_ground(B)
		B.apply_grip()


## a layer for the file (angles to 0.01; flags only when on; "wk" only with keys)
static func layer_to_file(L: Dictionary) -> Dictionary:
	var v := {}
	for j in L.get("v", {}):
		var x: Vector3 = L["v"][j]
		var q := 0.0001 if j == "offset" else 0.01   # the hips' position in metres: to 0.1 mm, angles to 0.01 deg
		v[j] = [snappedf(x.x, q), snappedf(x.y, q), snappedf(x.z, q)]
	var out := {"name": String(L.get("name", "layer")), "mode": String(L.get("mode", "add")), "w": snappedf(float(L.get("w", 1.0)), 0.0001), "v": v}
	for f in ["mute", "solo", "lock"]:
		if bool(L.get(f, false)):
			out[f] = true
	if not (L.get("wk", []) as Array).is_empty():
		out["wk"] = (L["wk"] as Array).map(func(k): return [snappedf(float(k[0]), 0.0001), snappedf(float(k[1]), 0.0001)])
	return out


static func layer_from_file(d: Dictionary) -> Dictionary:
	var v := {}
	for j in d.get("v", {}):
		var a: Array = d["v"][j]
		v[String(j)] = Vector3(float(a[0]), float(a[1]), float(a[2]))
	var mode := String(d.get("mode", "add"))
	var out := {"name": String(d.get("name", "layer")), "mode": mode if mode in ["add", "over"] else "add",
		"w": clampf(float(d.get("w", 1.0)), 0.0, 1.0), "v": v, "mute": bool(d.get("mute", false)),
		"solo": bool(d.get("solo", false)), "lock": bool(d.get("lock", false)), "wk": []}
	for k in d.get("wk", []):
		out["wk"].append([float(k[0]), clampf(float(k[1]), 0.0, 1.0)])
	out["wk"].sort_custom(func(a, b): return a[0] < b[0])
	return out


## the layer MIRRORED (MIRROR_SCENE "layer"): each joint's offset to its twin, reflected as an angle is (Body.mirror_pose)
static func mirror_layer(d: Dictionary, M: Body) -> Dictionary:
	var out := {}
	for j in d:
		var o := Body.twin(String(j))
		var a: Array = d[j]
		var q := M.compose(String(j), Vector3(float(a[0]), float(a[1]), float(a[2])))
		var v := M.decompose(o, Quaternion(q.x, -q.y, -q.z, q.w))
		out[o] = [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]
	return out


func _ground(B: Body) -> void:
	B.props = solid_props()   # TT2: the set it stands on (UU2: never on a prop it carries)
	if floor_body:
		B.ground_body()
	else:
		B.ground()


func _apply(B: Body, t: float) -> void:
	if stepped:
		var ts := times()
		var k := 0
		for i in cards.size():
			if t >= float(ts[i][1]) - 1e-6:
				k = i
		put(B, Moves._flat(cards[k]["pose"]))
		if on_floor:
			_ground(B)
		B.apply_grip()
		return
	if on_floor and not flights().is_empty():   # VV1: a jump in the air: no floor, no pins, a parabola
		var fl := flight_at(t)
		if not fl.is_empty():
			_fly(B, t, fl)
			B.apply_grip()
			return
	put(B, sample(t))
	if on_floor:
		_ground(B)
	if pin:
		# NO SNAP AT A CARD EDGE (round 32, GATES MM2): every foot has an ANCHOR per card (_anchors: where it really
		# stands, carried through a run of pinned cards); a move plants from the last card's anchor, and a HOLD plants
		# exactly as its move ended. Before, a hold showed the card's raw legs, so the leg jumped from the planted
		# solution to the raw one on arrival (up to 42 degrees in one frame) and back when the next move began.
		var i := span(t)
		var held := -1 if i > 0 else _held(t)
		if i > 0 or held > 0:
			var E := _anchors(B)
			put(B, sample(t))
			if on_floor:
				_ground(B)
			if i > 0:
				var e := _ease(clampf((t - times()[i][0]) / maxf(1e-6, move_time(i)), 0.0, 1.0), 5)
				if walk_feet(i):
					_vault(B, E[i - 1], E[i], clampf((t - times()[i][0]) / maxf(1e-6, move_time(i)), 0.0, 1.0))
				for sd in ["_l", "_r"]:
					var a: Array = E[i - 1][sd]
					var b: Array = E[i][sd]
					if b[3] == "free" and a[3] == "free":
						continue
					# THE RULE CHANGES ACROSS THE MOVE, NEVER AT ITS EDGE: the leg as the hold before solved it (old)
					# fades into the leg as this card solves it (new) over e, so both edges meet their holds exactly
					var raw := {}
					for j in _leg(sd):
						raw[j] = B.ang[j]
					var at: Vector3 = a[0]
					var head: float = a[1]
					if b[3] == "step":
						# a STEP: the toe base travels from where it stood to where it lands, lifted on an arc
						#   at = lerp(a, b, e) + up * lift * sin(pi e)   (lift = the card's "lift", else LIFT)
						var lift := float(cards[i].get("lift", LIFT))
						var ep := e
						if walk_feet(i):
							ep = _swing_path(clampf((t - times()[i][0]) / maxf(1e-6, move_time(i)), 0.0, 1.0))
						at = (a[0] as Vector3).lerp(b[0], ep) + Vector3.UP * lift * sin(PI * ep)
						head = lerp_angle(a[1], b[1], ep)
					var new_leg := raw
					if b[3] != "free":
						B.plant(sd, at, head, b[2])
						new_leg = {}
						for j in _leg(sd):
							new_leg[j] = B.ang[j]
					# the old leg: planted as the hold before was; after a FREE hold, the foot on its mark with the raw
					# leg's own knee direction (the raw leg itself would slide the foot off a pin as the move begins)
					for j in _leg(sd):
						B.ang[j] = raw[j]
					B.fk()
					var old_leg := raw
					if a[3] != "free":
						B.plant(sd, at, head, a[2])
					elif b[3] == "pin":
						B.plant(sd, at, head, false, B.knee_heading(sd))
					if a[3] != "free" or b[3] == "pin":
						old_leg = {}
						for j in _leg(sd):
							old_leg[j] = B.ang[j]
					for j in _leg(sd):
						B.ang[j] = (old_leg[j] as Vector3).lerp(new_leg[j], e)
					B.fk()
					if b[3] != "free" and ((B.P["ball" + sd] - at) as Vector3).length() > 0.005:
						# a blend of two legs on the same mark can leave the foot off it (~1 cm): put it back (only then: a
						# re-solve of a foot already on its mark would move the leg for nothing), keeping
						# the blended knee's direction and foot angle
						B.plant(sd, at, head, false, B.knee_heading(sd))
					if b[3] == "pin" and walk_feet(i):
						var ss := clampf((t - times()[i][0]) / maxf(1e-6, move_time(i)), 0.0, 1.0)
						# ZZ1: a foot that landed heel first in the move before, with no hold between, ends its roll here
						var ru := _roll_up((1.0 - HS_AT + ss) / (1.0 - HS_AT + ROLL_AFTER)) if a[3] == "step" and i > 1 and walk_feet(i - 1) and _carry(i - 1) else 0.0
						_stance(B, sd, at, head, ss, ru)
					if b[3] == "step" and walk_feet(i):
						_toe_off(B, sd, at, head, a[0], a[1], a[2], clampf((t - times()[i][0]) / maxf(1e-6, move_time(i)), 0.0, 1.0), b[0], b[1], _carry(i), move_time(i))
			else:
				# the hold after a WALK move holds that move's last frame (its BUILT legs, s = 1): a plain plant here is
				# another solution, and the legs jumped 4.2 deg as walk_bat's last step arrived (plant_edges)
				var wk := walk_feet(held)
				if wk:
					_vault(B, E[held - 1], E[held], 1.0)
				for sd in ["_l", "_r"]:
					var h: Array = E[held][sd]
					var h0: Array = E[held - 1][sd]
					if h[3] != "free":
						B.plant(sd, h[0], h[1], h[2])
						if wk and h[3] == "pin":
							_stance(B, sd, h[0], h[1], 1.0)
						elif wk and h[3] == "step":
							_toe_off(B, sd, h[0], h[1], h0[0], h0[1], h0[2], 1.0, h[0], h[1])
	_planted(B, t)
	B.apply_grip()


## TOE-OFF (round 42, Nick: "make them real"; only on WALK cards, so every other step plays as before). The stepping
## foot of a real walk does not slide off flat: its heel rises while the hips pass over it, it leaves the floor toes
## last with the knee still bent, and it lands level. Here, over the move (s = 0..1):
##   ANKLE: the card blend bent toward TOE_PLANTAR deg plantarflexed, fully by TOE_OFF_AT (the foot leaves: it waits
##     that long under NATURAL's overlap, people's pre-swing ~ 0.2-0.25 of a step), held to TOE_HOLD, back to 0 by
##     TOE_LEVEL. The move starts from, and ends in, the BUILT leg (_construct) the stance either side of it uses, so
##     the two meet exactly at every card.
##     People's ankle: ~20 deg plantarflexed at toe-off, neutral by mid-swing (Perry, Gait Analysis).
##   KNEE: never less bent than TOE_KNEE around toe-off: where keeping the toes on their mark would lock the leg
##     straight, the toes leave the mark instead (the ball slides toward the hip, bisection).
##   TOES: bent back at the ball so the tips stay on the floor (people's MTP joint, ~50-60 deg at toe-off), unbending
##     by TOE_LEVEL.
## The foot-ground angle at toe-off this gives is set by the trailing shank, not steered: people at 4.5 km/h 60.3 +-
## 5.1 deg (49.4 at 3 km/h, 68.5 at 6; 49 healthy adults, WalkinSense insoles, Eckelt et al. 2026, PMID 41583941).
## Before: the trailing leg locked straight on its toes and the knee went 40 -> 0 -> 52 deg in four frames (1743 deg/s;
## people's knee peaks ~400 in swing).
const TOE_OFF := 60.3     # deg, people's foot-ground angle at toe-off at 4.5 km/h (the reference the test reads)
const TOE_PLANTAR := 20.0 # deg: the ankle at toe-off, plantarflexed (absolute: the card's trail ankle is ~10 UP, and
                          # adding 20 to it gave 10 down and a 38 deg foot-ground angle at lift-off; people ~60)
const TOE_OFF_AT := 0.1   # ZZ1: was 0.25, when the card was the heel strike. The card is now the lead foot flat (8 % of its
                          # cycle) and the trailing foot leaves at people's 62 % (Fukuchi band), 0.1 of a move. At 0.25
                          # the swing ran ~8 % late: the knee peaked at 82-85 % (people 73 %), still 50 deg at 90 % (people 21)
const TOE_RATE := 400.0   # deg/s: the knee's bend to TOE_KNEE no faster than people's early-swing flexion (~350-400, Perry):
                          # out of a straight-kneed card (standing, the half step) the toes leave later (_toe_off_at)
const TOE_MIN_T := 0.1    # s: the push-off (ankle to TOE_PLANTAR, the toes unbending) takes at least this (people ~0.1 s,
                          # 50-62 % of a ~1.1 s cycle); in 0.057 s the ankle and toes turned 840-880 deg/s
const TOE_HOLD := 0.3     # early swing: the ankle stays down until here (people's knee peaks ~73 % = 0.3 of the move)
const TOE_LEVEL := 0.5    # level by mid-swing (people's ankle back to neutral ~75-80 % of the cycle)
const SWING_STRAIGHT := 0.82   # the swing knee's floor reaches 0 here (people ~5 deg at 95 % of the cycle)
const TOE_SEED := 20.0    # deg: the knee bend toe-off's plant starts from (not the straight branch)
const TOE_KNEE := 38.0    # deg: the knee is still this bent as the toes leave (people ~35-40 at toe-off, Perry)

## HEEL STRIKE (round 44, GATES ZZ1; Nick: "go for the heel strike, make it real"). People land on the heel, toes up:
## foot-ground angle at initial contact 22.7 +- 3.7 deg at 4.5 km/h (17.1 at 3, 28.1 at 6; 49 adults, Eckelt et al.
## 2026, PMID 41583941), the ankle near neutral; the forefoot comes down over the loading response (heel rocker, foot flat
## ~8 % of the cycle = 0.16 of a step, Perry). Here the card is that foot-flat instant, so the heel lands at HS_AT of the
## move with the foot HS_UP toes-up and rolls flat by the card. The body's heel is the point under the ankle (sole_low):
## a round heel ROLLS, so the ankle keeps its height and moves forward r x angle (r = the ankle's rest height) as the foot
## comes down; it never dips into the floor. Before: the foot came down flat, the ankle 22-26 deg plantarflexed at landing
## (people ~0), and the lead leg stretched for a flat foot 0.70 m ahead (its knee snapped 9.5 deg in a frame).
const HS_UP := 26.0     # deg toes-up commanded at heel strike: the heel touches at ~3 deg less (it rolls), so people's
                        # 22.7 +- 3.7 at 4.5 km/h (the test's reference) lands with the ankle near neutral, as theirs
const HS_AT := 0.92     # the heel lands here in the move; flat at 1 (the card). People's heel rocker is ~0.16 of a step; at 0.84
                        # the straight leg could not reach the heel yet (it hung 24-34 mm off the floor), at 0.92 it lands (6-10 mm)
const ROLL_AFTER := 0.08  # ZZ1: when the next move follows with no hold, the roll ends here in it (foot flat at ~8 % of the
                          # cycle, people's; ending it at the card squeezed 26 deg into 0.046 s: the foot turned 880 deg/s)
const SWING_KNEE := 60.0   # deg: the swing knee's floor from TOE_HOLD, easing to 0 at HS_AT (people peak ~60-65 in swing and
                           # extend to ~5 by heel strike, Perry): terminal swing straightens the knee as the foot reaches


func walk_feet(i: int) -> bool:
	return bool(cards[i].get("walk", false))


## STANCE (WALK moves; round 42, Nick: "make them real"). The cards are double support, the gait's low point. Between
## them the hips used to travel at the cards' height while the IK bent the stance knee to fit: it folded to 37 deg as the
## hips passed over the foot (people ~5-10 at mid-stance), and near full extension a two-bone knee is ill-conditioned (a
## millimetre of hips = 20 deg of knee), so it flickered. People work the other way round: the stance leg is an inverted
## pendulum and the HIPS' HEIGHT FOLLOWS THE LEG. So here, for the planted foot:
##   SOLE: flat (people's foot is flat from foot flat to mid-stance), the heel rising from HEEL_FROM of the move to
##     HEEL_END deg at the card (terminal stance: heel rise begins ~30-35 % of the gait cycle, Perry).
##   KNEE: STANCE_KNEE (people ~5-10 at mid-stance, Perry); the hips' height is SOLVED for it in closed form (_vault),
##     weighted by sin^2(pi s): zero, with zero speed, at both cards, so the cards are unchanged (the pelvis rises
##     ~4-5 cm over the stance leg in people; this lifts what the leg says).
##   The leg itself is BUILT (_construct), so the moves either side of a card meet in the same leg.
const STANCE_KNEE := 8.0
const VAULT_UP := 0.08     # m: the most the hips are lifted
const VAULT_DOWN := 0.04   # m: the most they are lowered (a leg too far behind to keep its knee: the pendulum falls)
const HEEL_FROM := 0.6
const REACH_TOL := 0.0005   # m: ZZ0, the hips may be this far beyond the bent leg's reach before the heel rises
const CARD_KNEE := 22.6     # deg: ZZ0, the trailing knee at the card (people's at 58 % of the cycle, Fukuchi 2018: pre-swing,
                            # the knee bends while the heel rises; the card is the lead foot flat, 8 % of ITS cycle)
const PRESWING := 0.84      # the stance move's s where people's knee starts that bend (50 % of the cycle)


## ZZ0: the knee the stance leg's heel keeps it within reach of: straight in early stance, STANCE_KNEE by late stance,
## CARD_KNEE at the card (pre-swing). The heel rises as far as the hips need for that knee
## (a card standing FLAT -- the walk's first and last -- is not pre-swing: no CARD_KNEE there)
static func _reach_knee(s: float, flat := false) -> float:
	return STANCE_KNEE * smoothstep(HEEL_FROM, 1.0, s) + (0.0 if flat else (CARD_KNEE - STANCE_KNEE) * smoothstep(PRESWING, 1.0, s))


## ZZ0: the vault's weight over the stance move: sin^2(pi s) up to mid-stance (the hips rise out of the card, the knee's
## loading-response bend), then held up longer and let down late, 1 - smoothstep(VAULT_FALL, 1, s): people's pelvis
## falls in terminal stance with the knee at 4-8 and the heel rising (Fukuchi band 40-52 %); with sin^2 ours sank from
## mid-stance and the knee bent to 16 at 44 %. Zero, with zero speed, at both cards.
const VAULT_FALL := 0.6


static func _vault_w(s: float) -> float:
	return pow(sin(PI * s), 2.0) if s <= 0.5 else 1.0 - smoothstep(VAULT_FALL, 1.0, s) * (1.0 if s >= VAULT_FALL else 0.0)
const HEEL_END := 0.0   # ZZ0: was 20 (a forced heel lift at every card shortened the trailing leg: knee ~30 in late stance, people 4-8); the heel now rises only where the leg must reach (_vault, _heel_at_card)


## the stance side of a WALK move ("" if none): the foot pinned on the way into card i (also out of card 0, whose
## anchors are all "free": the half step's standing foot is a stance foot too)
static func _stance_side(A: Dictionary, E: Dictionary) -> String:
	for x in ["_l", "_r"]:
		if (E[x] as Array)[3] == "pin":
			return x
	return ""


var _heel_now := 0.0   # the stance sole (deg, heel up) _vault chose for this frame; _stance plants with it


## the ankle of a foot whose toe base is on `ball`, pointing `head`, its sole `sole` deg heel-up (pivot on the ball)
static func _ankle_at(B: Body, sd: String, ball: Vector3, head: float, sole: float) -> Vector3:
	var d0: Vector3 = (B.p0["foot" + sd] as Vector3) - (B.p0["ball" + sd] as Vector3)   # ball -> ankle, flat, facing +z
	var turned := Basis(Vector3.UP, head) * Basis(Vector3.RIGHT, deg_to_rad(sole)) * d0
	return ball + turned


## the hips' lift (m) that puts the stance knee at STANCE_KNEE with the sole at the heel curve, in closed form: the
## ankle from the ball and the sole, the hip -> ankle distance from the knee (the rest chain bent), the hip's height from
## that distance and the horizontal gap, weighted by sin^2(pi s). Where the hips so placed are beyond a STRAIGHT leg's
## reach (they have passed the foot) the heel goes up 1 deg at a time until they are not: the leg reaches by lifting its
## heel, as people's does in terminal stance, never by leaving its mark.
func _vault(B: Body, A: Dictionary, E: Dictionary, s: float) -> void:
	_heel_now = 0.0   # never last frame's
	var sd := _stance_side(A, E)
	if sd == "":
		return
	var an: Array = E[sd]
	_heel_now = (0.0 if an[2] else HEEL_END) * smoothstep(HEEL_FROM, 1.0, s)   # a card standing flat keeps its heel down
	# hip -> ankle at a knee bend: the REST chain bent about the knee's axis (the knee is not on the hip-ankle line at rest,
	# so the law of cosines on the two bone lengths is off 4 mm at 12 deg, 10 at 38; this matches the body exactly)
	var u: Vector3 = (B.p0["calf" + sd] as Vector3) - (B.p0["thigh" + sd] as Vector3)
	var v: Vector3 = (B.p0["foot" + sd] as Vector3) - (B.p0["calf" + sd] as Vector3)
	var dd := (u + Basis(Vector3.RIGHT, deg_to_rad(STANCE_KNEE)) * v).length()
	# the reach the heel keeps: a straight leg's in early stance, a leg bent STANCE_KNEE by the card (_heel_at_card)
	var dr := (u + Basis(Vector3.RIGHT, deg_to_rad(_reach_knee(s, an[2]))) * v).length()
	var hip: Vector3 = B.P["thigh" + sd]
	var w := _vault_w(s)
	var lift := 0.0
	for it in 45:
		var ank := _ankle_at(B, sd, an[0], an[1], _heel_now)
		var h := Vector2(hip.x - ank.x, hip.z - ank.z).length()
		var dy := (ank.y + sqrt(maxf(0.0, dd * dd - h * h)) - hip.y) if h < dd else -1.0
		# ZZ0: the reach of a leg still bent STANCE_KNEE (was: a straight leg's, 2 mm to spare; with the heel down at the card
		# the trailing leg then arrived 2 mm from locked, where a millimetre is degrees of knee: 6.8 deg in a frame at toe-off)
		var top := (ank.y + sqrt(maxf(0.0, dr * dr - h * h)) - hip.y) if h < dr else -1.0
		lift = clampf(dy, -VAULT_DOWN, VAULT_UP) * w
		# the hips as they will stand (weighted) must be within that reach (mid-stance's lift IS it: 0.5 mm over allowed),
		# else the heel goes up
		if lift <= top + REACH_TOL or _heel_now >= 44.0:
			break
		_heel_now += 1.0
	B.offset.y += lift
	B.fk()


## the foot's pitch alone (bisection on its bend, the ankle staying) so the toe base is at the height of its mark
static func _foot_pitch(B: Body, sd: String, at: Vector3) -> void:
	var f := "foot" + sd
	var r: Vector2 = B.lim[f]["bend"]
	var v: Vector3 = B.ang[f]
	var lo := r.x
	var hi := r.y
	for it in 16:
		var m := (lo + hi) * 0.5
		B.ang[f] = Vector3(m, v.y, v.z)
		B.fk_some([f, "ball" + sd])
		if (B.P["ball" + sd] as Vector3).y > at.y:
			hi = m   # toes too high: point them down (heel up)
		else:
			lo = m
	B.ang[f] = Vector3((lo + hi) * 0.5, v.y, v.z)
	B.fk()


## the stance leg: built on its mark with the sole _vault chose for this frame
func _stance(B: Body, sd: String, at: Vector3, head: float, s: float, up := 0.0) -> void:
	_construct(B, sd, at, head, _heel_now, up)


## A FOOT ON ITS MARK, BUILT (not searched): the ankle goes straight to where the sole puts it (reach bisects the knee on
## DISTANCE, which stays well-conditioned at full stretch; Body.plant iterates from the leg it is given, and from a
## straight leg that misses it turned the foot toes-up 9 deg with the ball 3 cm off its mark); then the foot's heading:
## the leg swung about its hip -> ankle line (the ankle stays, the foot turns with it ~1:1) until the foot points along
## its mark (pointing the KNEE there left this leg's toe-out: 4.3 deg, the ball 11 mm aside); then only the foot's pitch
## (1-D, monotone) puts the ball on its mark. The result does not depend on the leg it starts from: the two moves either
## side of a card both end / start in it, so they meet exactly.
func _construct(B: Body, sd: String, at: Vector3, head: float, sole: float, up := 0.0) -> void:
	var f := "foot" + sd
	var ank := _ankle_at(B, sd, at, head, sole)
	var ball := at
	if up > 0.0:   # ZZ1: on the heel, toes `up` deg: the heel rolled back r x up, the ball raised about the ankle
		var hb := Basis(Vector3.UP, head)
		var a := deg_to_rad(up)
		var flat := ank
		ank = flat - hb * Vector3(0, 0, 1) * (B.p0[f] as Vector3).y * a
		ball = ank + hb * (Basis(Vector3.RIGHT, -a) * (hb.inverse() * (at - flat)))
	B.reach(f, ank)
	var kh := B.knee_heading(sd)
	if is_nan(kh):
		kh = head
	for it in 4:
		_foot_pitch(B, sd, ball)
		var dh := angle_difference(B.foot_heading(sd), head)
		if absf(dh) < 0.002:
			break
		kh += dh
		B.knee_over_toes(sd, kh)
	if up <= 0.0 and ((B.P["ball" + sd] - at) as Vector3).length() > 0.003:
		B.plant(sd, at, head, false, B.knee_heading(sd))
	B.toes_flat(sd)
	if up > 0.0:   # the toes in the air: from flat on the floor toward their rest as the foot lifts
		B.ang["ball" + sd] = (B.ang["ball" + sd] as Vector3).lerp(Vector3.ZERO, clampf(up / HS_UP, 0.0, 1.0))
		B.fk()


## the heel a foot standing on `at` needs at the card: `base` (the card's: HEEL_END if its heel is up, else 0), raised a
## degree at a time while a STRAIGHT leg could not reach the hips with 2 mm to spare. _vault's own loop at s = 1 is
## this, so a stance that ends at a card and the toe-off that starts from it agree
func _heel_at_card(B: Body, sd: String, at: Vector3, head: float, base: float, flat := false) -> float:
	var u: Vector3 = (B.p0["calf" + sd] as Vector3) - (B.p0["thigh" + sd] as Vector3)
	var v: Vector3 = (B.p0["foot" + sd] as Vector3) - (B.p0["calf" + sd] as Vector3)
	var d0 := (u + Basis(Vector3.RIGHT, deg_to_rad(_reach_knee(1.0, flat))) * v).length()   # ZZ0: as _vault at s = 1
	var hip: Vector3 = B.P["thigh" + sd]
	var heel := base
	while heel < 44.0:
		var ank := _ankle_at(B, sd, at, head, heel)
		var h := Vector2(hip.x - ank.x, hip.z - ank.z).length()
		var top := (ank.y + sqrt(maxf(0.0, d0 * d0 - h * h)) - hip.y) if h < d0 else -1.0
		if 0.0 <= top + REACH_TOL:
			break
		heel += 1.0
	return heel


## a WALK step's swing foot along its path: from SWING_FROM of the move (just before the toes leave) to the card, on a
## smoothstep (peak 1.5x its mean speed; NATURAL's smootherstep from 0.25 peaks at 1.875x over less time: a 0.70 m
## step's foot crossed 1.4 m at ~6 m/s, people's swing foot peaks ~4.4 m/s at 1.25 m/s walking; this: 1.4 m in 0.85 x 0.57 s, peak 4.3)
const SWING_FROM := 0.08   # ZZ1: was 0.15 (the toes leave earlier now)


static func _swing_path(s: float) -> float:
	return smoothstep(SWING_FROM, HS_AT, s)   # ZZ1: the foot is on its mark (heel down) at the heel strike, not the card


## 0 -> 1 by TOE_OFF_AT, 1 to TOE_HOLD, 0 by TOE_LEVEL: the shape of the ankle bump and the knee floor
## ZZ1: the toes-up angle along the heel roll, u = 0 at the heel strike, 1 at foot flat
static func _roll_up(u: float) -> float:
	return HS_UP * (1.0 - smoothstep(0.0, 1.0, u))


## the roll of a foot landing in move i carries into move i + 1: a WALK move follows with no hold at card i
func _carry(i: int) -> bool:
	return i + 1 < cards.size() and walk_feet(i + 1) and float(times()[i][2]) - float(times()[i][1]) < 1e-6


## the toes-up angle (deg) of foot sd at t while it ROLLS onto its heel (ZZ1: from the heel strike to foot flat), else 0.
## While it rolls the heel holds the mark and the ball comes down to it (tests read the heel then, not the ball)
func heel_roll(t: float, sd: String) -> float:
	var i := span(t)
	if i <= 0 or not pin:
		return 0.0
	var s := clampf((t - float(times()[i][0])) / maxf(1e-6, move_time(i)), 0.0, 1.0)
	if walk_feet(i) and (cards[i].get("steps", {}) as Dictionary).has(sd) and s >= HS_AT:
		return _roll_up((s - HS_AT) / (1.0 - HS_AT + (ROLL_AFTER if _carry(i) else 0.0)))
	if i > 1 and walk_feet(i - 1) and _carry(i - 1) and (cards[i - 1].get("steps", {}) as Dictionary).has(sd) and not (cards[i].get("steps", {}) as Dictionary).has(sd):
		return _roll_up((1.0 - HS_AT + s) / (1.0 - HS_AT + ROLL_AFTER))
	return 0.0


static func _toe_bump(s: float, off := TOE_OFF_AT) -> float:
	return smoothstep(0.0, off, s) if s < TOE_HOLD else 1.0 - smoothstep(TOE_HOLD, TOE_LEVEL, s)


func _toe_off(B: Body, sd: String, at: Vector3, head: float, from_at: Vector3, head0: float, from_flat: bool, s: float, to_at: Vector3, to_head: float, carry := false, mt := 0.57) -> void:
	var f := "foot" + sd
	var heel0 := _heel_at_card(B, sd, from_at, head0, 0.0 if from_flat else HEEL_END, from_flat)
	var off := _toe_off_at(B, sd, from_at, head0, heel0, mt)
	var foot: Vector3 = B.ang[f]
	B.ang[f] = B.clamp_ang(f, foot.lerp(Vector3(-TOE_PLANTAR, foot.y, foot.z), _toe_bump(s, off)))
	# plant iterates from the leg it is given; from the sample's near-straight knee it stayed straight one frame and found
	# 21 deg the next (calf 666 deg/s). Seeded bent, it finds the same branch every frame
	var c := "calf" + sd
	var kh := B.knee_heading(sd)
	B.ang[c] = Vector3(maxf((B.ang[c] as Vector3).x, TOE_SEED), (B.ang[c] as Vector3).y, (B.ang[c] as Vector3).z)
	B.fk()
	B.plant(sd, at, head, false, kh if not is_nan(kh) else B.knee_heading(sd))
	# both ends in the BUILT leg (_construct), as the stance either side of them: out of the card from its heel (the
	# stance that ended there, _heel_at_card), BEFORE the knee floor lifts the toes (the blend re-plants on the path)
	_toward_built(B, sd, from_at, head0, heel0, 1.0 - smoothstep(0.0, off, s), at, head, true)
	# the knee floor: TOE_KNEE around toe-off, then (ZZ1) easing to 0 at the heel strike, so in terminal swing the knee
	# straightens as the foot reaches its mark (people ~60 -> ~5 deg), never locked straight on a path point out of reach
	_knee_floor(B, sd, at, head, maxf(TOE_KNEE * _toe_bump(s, off), SWING_KNEE * smoothstep(off, TOE_HOLD, s) * (1.0 - smoothstep(TOE_HOLD, SWING_STRAIGHT, s))))
	var toe := "ball" + sd
	var t0: Vector3 = B.ang[toe]
	B.toes_flat(sd)
	B.ang[toe] = t0.lerp(B.ang[toe] as Vector3, 1.0 - smoothstep(off, TOE_LEVEL, s))
	B.fk()
	# ...and onto the next card's mark HEEL FIRST (ZZ1): toward the leg on its heel, toes HS_UP up, reached at HS_AT; from
	# there the heel stays and the foot rolls flat by the card (the stance that starts there)
	_toward_built(B, sd, to_at, to_head, 0.0, smoothstep(TOE_LEVEL, HS_AT, s), to_at, to_head, false, _roll_up((s - HS_AT) / (1.0 - HS_AT + (ROLL_AFTER if carry else 0.0))))


## ZZ1: when the toes leave in this move: TOE_OFF_AT, or later where the card's knee (the BUILT leg on the mark it leaves)
## is so straight that bending it to TOE_KNEE by then would beat TOE_RATE (smoothstep peaks at 1.5 x its mean rate)
func _toe_off_at(B: Body, sd: String, at: Vector3, head: float, heel: float, mt: float) -> float:
	var keep := {}
	for j in B.ang:
		keep[j] = B.ang[j]
	_construct(B, sd, at, head, heel)
	var k0: float = (B.ang["calf" + sd] as Vector3).x
	for j in keep:
		B.ang[j] = keep[j]
	B.fk()
	return clampf(maxf(1.5 * maxf(0.0, TOE_KNEE - k0) / TOE_RATE, TOE_MIN_T) / maxf(mt, 1e-3), TOE_OFF_AT, TOE_HOLD - 0.05)


## the leg now blended w of the way into the BUILT leg on `at` with that sole (w = 1: exactly it), the ball then put on
## the step's path point `path` if `replant`
func _toward_built(B: Body, sd: String, at: Vector3, head: float, sole: float, w: float, path: Vector3, path_head: float, replant: bool, up := 0.0) -> void:
	if w <= 0.0:
		return
	var cur := {}
	for j in _leg(sd):
		cur[j] = B.ang[j]
	_construct(B, sd, at, head, sole, up)
	if w >= 1.0:
		return
	for j in _leg(sd):
		B.ang[j] = (cur[j] as Vector3).lerp(B.ang[j], w)
	B.fk()
	# a blend of joint angles between two legs on the mark is not on it (16 mm aside, 6 mm into the floor): put the ball
	# back on the step's path point. Only out of a card, where the foot stands; on the way in the blend lands exactly on
	# the card (w = 1), and re-planting an arc point the leg cannot yet reach locked the knee straight (15 -> 0 -> 5)
	# The ANKLE is moved by the ball's miss with reach (the knee bisected on distance): plant, iterating from a near-
	# straight blended leg, jumped 0 -> 21 deg between two frames
	for it in 8:
		var miss: Vector3 = path - (B.P["ball" + sd] as Vector3)
		if not replant or miss.length() < 0.0005:
			break
		B.reach("foot" + sd, (B.P["foot" + sd] as Vector3) + miss)


## the knee no less bent than k: below it, the toe target slides toward the hip (bisection) until the knee bends that
## much, the ball lifting off its mark. k is continuous in s, so the lift-off has no jump.
func _knee_floor(B: Body, sd: String, at: Vector3, head: float, k: float) -> void:
	var c := "calf" + sd
	if (B.ang[c] as Vector3).x >= k:
		return
	var leg := {}
	for j in _leg(sd):
		leg[j] = B.ang[j]
	var hip: Vector3 = B.P["thigh" + sd]
	var kh := B.knee_heading(sd)   # read ONCE: re-read after each trial plant it drifts, and one frame flipped the thigh
	var lo := 0.0
	var hi := 0.5
	for it in 16:
		var m := (lo + hi) * 0.5
		_try_leg(B, sd, leg, at.lerp(hip, m), head, kh)
		if (B.ang[c] as Vector3).x >= k:
			hi = m
		else:
			lo = m
	_try_leg(B, sd, leg, at.lerp(hip, hi), head, kh)


## every trial plant starts from the SAME leg: plant iterates from the leg it is given, and near full extension the
## knee is so sensitive (1.7 mm closer = 11 deg) that a trial started from a straight leg stays straight
func _try_leg(B: Body, sd: String, leg: Dictionary, to: Vector3, head: float, kh: float) -> void:
	for j in leg:
		B.ang[j] = leg[j]
	B.fk()
	B.plant(sd, to, head, false, kh)


## PLANTED FEET: the card whose move or hold contains t; for each foot it plants, back to the run's first card; the foot
## goes where it stood in the card before that
func _planted(B: Body, t: float) -> void:
	var ts := times()
	var c := -1
	for i in range(1, cards.size()):
		if t >= ts[i][0] and t < ts[i][2]:
			c = i
	if c < 1 and not cards.is_empty() and t >= float(ts[-1][2]):
		c = cards.size() - 1
	if c < 1:
		return
	for sd in ["_l", "_r"]:
		if not sd in cards[c].get("plant", []):
			continue
		var r := c
		while r > 1 and sd in cards[r - 1].get("plant", []):
			r -= 1
		var at: Array
		var cached = _feet_cache.get(r - 1, null)
		if cached != null and is_same(cached[0], cards[r - 1]["pose"]):
			at = cached[1][sd]
		else:   # _feet loads that card into the body: keep the frame being played
			var keep := B.state()
			at = _feet(B, r - 1)[sd]
			B.set_state(keep)
			B.fk()
		B.plant(sd, at[0], at[1], at[3])


static func _leg(sd: String) -> Array:
	return ["thigh" + sd, "calf" + sd, "foot" + sd, "ball" + sd]


## the card whose HOLD contains t (after its move, before the next card's; the last card from its arrival on), or -1
func _held(t: float) -> int:
	var ts := times()
	for i in range(cards.size() - 1, -1, -1):
		if t >= float(ts[i][1]) - 1e-6:
			return i
	return -1


## each foot's ANCHOR per card: [{"_l": [ball position, heading, flat, how], "_r": ...}, ...]; how = "pin" (held where
## it stood: the anchor carries over from the card before), "step" (lands on the card's own place), "free" (the
## card's raw foot, no planting). Card 0 is "free". Loads cards into the body (through _feet): put the frame back after
func _anchors(B: Body) -> Array:
	var out := []
	for i in cards.size():
		var b := _feet(B, i)
		var row := {}
		for sd in ["_l", "_r"]:
			var r: Array = b[sd]
			if i == 0:
				row[sd] = [r[0], r[1], r[3], "free"]
				continue
			var a: Array = _feet(B, i - 1)[sd]
			var prev: Array = out[i - 1][sd]
			if _pinned(i, sd, a, r):
				row[sd] = [prev[0], prev[1], a[3] and r[3], "pin"]
			elif _steps(i).has(sd):
				row[sd] = [r[0], r[1], false, "step"]
			else:
				row[sd] = [r[0], r[1], r[3], "free"]
		out.append(row)
	return out


## the card the body is moving INTO at time t (-1 while holding still)
func span(t: float) -> int:
	var ts := times()
	for i in range(1, cards.size()):
		if t >= ts[i][0] and t < ts[i][1]:
			return i
	return -1


## TWO-CHARACTER (G1): further actors beside this one (this scene is actor 0, the hero). Each {"name": String,
## "xf": {"pos": [x, z], "yaw": deg} (where actor k stands in actor 0's space, like Dummy.xf), "scene": Scene}.
## Empty = one actor; the file key "actors" is written only when there are any, so every older file saves byte-identical
var actors := []


## a scene of its own with the same settings and a deep copy of the cards (for work off the main thread: the fix
## preview). Caches start empty
func clone() -> Scene:
	var c := Scene.new()
	c.cards = cards.duplicate(true)
	for k in ["name", "natural", "spline", "on_floor", "floor_body", "pin", "fps", "moving_holds", "stepped", "loop", "breath"]:
		c.set(k, get(k))
	c.props = props   # the set (read only there)
	c.part_keys = part_keys.duplicate(true)
	c.markers = markers.duplicate(true)
	c.audio = audio.duplicate()
	c.layer = layer.duplicate()   # YY9 (Vector3 values: copies)
	c.layer_w = layer_w
	c.layers = layers.duplicate(true)   # NA1
	for a in actors:   # G1: deep (each actor's own scene is cloned, its xf copied)
		c.actors.append({"name": a["name"], "xf": (a["xf"] as Dictionary).duplicate(true), "scene": (a["scene"] as Scene).clone()})
	c.ik = ik.duplicate(true)   # IK keys (limb_ik.gd)
	return c


## CARRY (round 39, GATES UU2 / UU3, #206). Written on the CARDS, so inserting, deleting or reordering cards keeps
## them where they belong: card["take"] = {"prop": i, "hands": ["_r"] / ["_l", "_r"]} (the hands hold prop i from
## this card's arrival on), card["drop"] = i (they let it go at this card's arrival). Nothing about the grip is
## stored: it is where the prop is relative to the hand(s) on the take card, so editing that card re-grips it and
## Mirror needs only the hands swapped. After the drop the prop FALLS: y(t) = y0 - G t^2 / 2 onto the top or floor
## under it (at t = sqrt(2 h / G)), keeping only its turn about the vertical; then it stays there.
const G := 9.81
const THROW_DT := 1.0 / 60.0   # WW8: the hand's velocity at the let-go is the held prop's drift over this long before it
const RELEASE := 0.1   # s after letting go the holding hands are still not "through" it: it falls 4.9 cm, clear of a grip


## [{"prop", "a" (take card), "b" (drop card, -1 = held to the end), "hands"}] in card order
func carries() -> Array:
	var out := []
	for i in cards.size():
		var tk = cards[i].get("take", null)
		if not (tk is Dictionary and tk.has("prop")):
			continue
		var pi := int(tk["prop"])
		var b := -1
		for k in range(i + 1, cards.size()):
			if int(cards[k].get("drop", -1)) == pi:
				b = k
				break
		out.append({"prop": pi, "a": i, "b": b, "hands": Array(tk.get("hands", ["_r"]))})
	return out


## the props the body can stand on: every prop no card carries
func solid_props() -> Array:
	var held := {}
	for c in carries():
		held[c["prop"]] = true
	if held.is_empty():
		return props
	var out := []
	for i in props.size():
		if not held.has(i):
			out.append(props[i])
	return out


## the frame the prop is held in: one hand's (its joint, its rotation), or both hands' (between them; x from the
## right hand to the left, up the hands' mean up)
static func hand_frame(B: Body, hands: Array) -> Transform3D:
	if hands.size() < 2:
		var h := "hand" + String(hands[0])
		return Transform3D(Basis(B.G[h] as Quaternion), B.P[h])
	var pl: Vector3 = B.P["hand_l"]
	var pr: Vector3 = B.P["hand_r"]
	var x := (pl - pr).normalized()
	var up := ((B.G["hand_l"] as Quaternion) * Vector3.UP + (B.G["hand_r"] as Quaternion) * Vector3.UP).normalized()
	var z := x.cross(up).normalized()
	if z.length() < 0.5:
		z = x.cross(Vector3.FORWARD).normalized()
	return Transform3D(Basis(x, z.cross(x), z), (pl + pr) / 2.0)


var _carry_memo := []   # [key, [per carry: {"grip", "home", "drop", "land", "y0", "tf", "ta", "tb"}]]


## per carry: the grip (the prop in the hand frame on the take card), where it is let go, where it lands. The body is
## posed at the take and drop cards to read the hands, then put back exactly as it was
func _carry_data(B: Body) -> Array:
	var cs := carries()
	var ts := times()
	var key := [ts, JSON.stringify(cs), JSON.stringify(props.map(func(p): return Props.to_dict(p))), var_to_str(part_keys), var_to_str(ik)]
	if not _carry_memo.is_empty() and is_same(_carry_memo[0][0], ts) and _carry_memo[0][1] == key[1] and _carry_memo[0][2] == key[2] 			and _carry_memo[0][3] == key[3] and _carry_memo[0][4] == key[4]:   # a keyed hand moves the grip (WW1)
		return _carry_memo[1]
	var st := B.state()
	var bp := B.props
	var rest := {}   # prop -> where it is now (its home, then where its last drop landed)
	var out := []
	var floor_of := solid_props()
	for c in cs:
		var pi: int = c["prop"]
		if pi < 0 or pi >= props.size():
			out.append({})
			continue
		var home: Transform3D = rest.get(pi, props[pi]["xf"])
		var ta: float = ts[c["a"]][1]
		apply(B, ta)
		var grip := hand_frame(B, c["hands"]).affine_inverse() * home
		var d := {"grip": grip, "home": home, "ta": ta, "tb": INF}
		if int(c["b"]) >= 0:
			var tb: float = ts[c["b"]][1]
			var tp := maxf(ta, tb - THROW_DT)   # the held prop one frame before the let-go (WW8: its velocity)
			apply(B, tp)
			var before := hand_frame(B, c["hands"]) * grip
			apply(B, tb)
			var rel := hand_frame(B, c["hands"]) * grip
			var fx := rel.basis * Vector3(1, 0, 0)
			var drop := Props.xf_at(rel.origin, rad_to_deg(atan2(-fx.z, fx.x)))
			var y0 := maxf(0.0, drop.origin.y)
			var land := 0.0
			for q in floor_of:
				for sup in Props.supports(q):
					if Props._over(sup, drop.origin) and float(sup["y"]) <= y0 + 0.001:
						land = maxf(land, float(sup["y"]))
			drop.origin.y = y0
			d["tb"] = tb
			d["drop"] = drop
			d["land"] = land
			d["tf"] = sqrt(2.0 * (y0 - land) / G)
			var lx := drop
			lx.origin.y = land
			rest[pi] = lx
			# WW8 THROWN: a moving hand lets go with its velocity (and its turn about Y); a still one changes nothing
			var v0 := (rel.origin - before.origin) / (tb - tp) if tb > tp else Vector3.ZERO
			var bx := before.basis * Vector3(1, 0, 0)
			var w0 := rad_to_deg(angle_difference(atan2(-bx.z, bx.x), atan2(-fx.z, fx.x))) / (tb - tp) if tb > tp else 0.0
			if v0.length() > 1e-4 or absf(w0) > 1e-3:
				var tr := Throw.trajectory(drop.origin, v0, floor_of, float(props[pi].get("e", Throw.E)))
				d["tr"] = tr
				d["w"] = w0
				lx.origin = tr["rest"]
				rest[pi] = lx
		out.append(d)
	B.set_state(st)
	B.props = bp
	B.fk()
	_carry_memo = [key, out]
	return out


## the set at time t, the body B posed at t: [Props dicts] in the same order as props (a carried prop in the hand, a
## dropped one falling or landed). With no carries: props itself
func props_at(t: float, B: Body) -> Array:
	var cs := carries()
	if cs.is_empty():
		return props
	var data := _carry_data(B)
	var out := props.duplicate()
	for k in cs.size():
		var c: Dictionary = cs[k]
		var d: Dictionary = data[k]
		if d.is_empty() or t < float(d["ta"]):
			continue
		var pi: int = c["prop"]
		if t < float(d["tb"]):
			out[pi] = {"kind": props[pi]["kind"], "xf": hand_frame(B, c["hands"]) * (d["grip"] as Transform3D)}
		else:
			var xf: Transform3D = d["drop"]
			var dt := t - float(d["tb"])
			if d.has("tr"):
				xf.origin = Throw.pos_at(d["tr"], dt)
				xf.basis = Basis(Vector3.UP, deg_to_rad(float(d["w"]) * minf(dt, float(d["tr"]["t_rest"])))) * xf.basis
				out[pi] = {"kind": props[pi]["kind"], "xf": xf}
				continue
			xf.origin.y = maxf(float(d["land"]), xf.origin.y - G * dt * dt / 2.0)
			out[pi] = {"kind": props[pi]["kind"], "xf": xf}
	return out


## JUMPS (round 40, GATES VV1, #230). A card marked "air" is in the air at its arrival. A run of air cards between a
## take-off card k and a landing card l is a FLIGHT from k's leave time T0 to l's arrival T1. In it there is no floor
## and no pin: the limbs blend through the cards as ever, and the CENTRE OF MASS (Balance.com, de Leva masses; round 41,
## GATES WW10, #311 momentum) follows the ballistic path through its grounded heights at both ends:
##   y(t) = lerp(y0, y1, u) + G/2 (t - T0)(T1 - t),  u = (t - T0) / (T1 - T0)
## (round 40 put the pelvis there; but in the air only the CoM is on the parabola, so arms thrown up lift the CoM off
## it, the body must sit LOWER by that shift, the pelvis no longer on the parabola. Legs tucked, arms up: pelvis
## drops, CoM keeps the path.)
## (a body in free fall: y'' = -G; the apex over level ground is G T^2 / 8, T = T1 - T0: 0.571 s -> 0.40 m)
var _flight_memo := []   # [key, flights]


## [{"k", "l", "t0", "t1"}] in time order (a run with no card before or after it is not a flight)
func flights() -> Array:
	var ts := times()
	var key := "".join(cards.map(func(c): return "1" if c.get("air", false) else "0"))
	if not _flight_memo.is_empty() and is_same(_flight_memo[0][0], ts) and _flight_memo[0][1] == key:
		return _flight_memo[1]
	var out := []
	var i := 0
	while i < cards.size():
		if not cards[i].get("air", false):
			i += 1
			continue
		var a := i
		while i < cards.size() and cards[i].get("air", false):
			i += 1
		if a >= 1 and i < cards.size():
			out.append({"k": a - 1, "l": i, "t0": float(ts[a - 1][2]), "t1": float(ts[i][1])})
	_flight_memo = [[ts, key], out]
	return out


func flight_at(t: float) -> Dictionary:
	for f in flights():
		if t > float(f["t0"]) and t < float(f["t1"]):
			return f
	return {}


## the body in the air: the cards' blend, the CoM put on the parabola (the ends measured by posing B at T0 and T1
## the ordinary way, cached per flight while the cards are the same)
func _fly(B: Body, t: float, f: Dictionary) -> void:
	if not f.has("y0"):
		_apply(B, float(f["t0"]))
		f["y0"] = Balance.com(B).y
		_apply(B, float(f["t1"]))
		f["y1"] = Balance.com(B).y
	var t0: float = f["t0"]
	var t1: float = f["t1"]
	var u := (t - t0) / maxf(1e-6, t1 - t0)
	put(B, sample(t))
	B.fk()
	var y: float = lerpf(f["y0"], f["y1"], u) + G / 2.0 * (t - t0) * (t1 - t)
	B.offset.y += y - Balance.com(B).y
	B.fk()


## the parts that hold a prop at time t (not "through" it): {prop index: [part, ...]}
func holding(t: float, B: Body) -> Dictionary:
	var out := {}
	var cs := carries()
	if cs.is_empty():
		return out
	var data := _carry_data(B)
	for k in cs.size():
		var d: Dictionary = data[k]
		if not d.is_empty() and t >= float(d["ta"]) and t < float(d["tb"]) + RELEASE:
			var parts: Array = out.get(cs[k]["prop"], [])
			for sd in cs[k]["hands"]:
				parts += ["hand" + sd, "lowerarm" + sd]
			out[cs[k]["prop"]] = parts
	return out


var _feet_cache := {}   # card i -> [its pose dict, feet] (the same dict object = still valid)


## each foot's state in card i, as it stands (grounded)
func _feet(B: Body, i: int) -> Dictionary:
	var c = _feet_cache.get(i, null)
	if c != null and is_same(c[0], cards[i]["pose"]):
		return c[1]
	var r := _feet_raw(B, i)
	_feet_cache[i] = [cards[i]["pose"], r]
	return r


func _feet_raw(B: Body, i: int) -> Dictionary:
	B.from_dict(cards[i]["pose"])
	if on_floor:
		_ground(B)
	return {"_l": B.foot_state("_l"), "_r": B.foot_state("_r")}


const LIFT := 0.08     # how high a stepping foot lifts mid-step (m)


## the feet card i steps with: {"_l": Vector3 offset along the floor from where that foot stood} (from the card's
## "steps"); a card without "steps" is judged by distance (STEP)
func _steps(i: int) -> Dictionary:
	var out := {}
	var s = cards[i].get("steps", null)
	if s is Dictionary:
		for sd in s:
			var v = s[sd]
			out[sd] = Vector3(v[0], v[1], v[2]) if v is Array else v
	return out


## is foot sd held where it stood, on the way into card i?
func _pinned(i: int, sd: String, a: Array, b: Array) -> bool:
	if cards[i].has("steps"):
		return a[2] and not _steps(i).has(sd)
	return a[2] and b[2] and ((b[0] - a[0]) as Vector3).slide(Vector3.UP).length() < STEP


## PIN THE CARDS: walking the clips in order, a foot that is on the floor in two clips in a row and moved less than STEP
## is put back where it stood (the leg is re-solved, the rest of the body untouched). Returns how many legs moved.
func pin_cards(B: Body) -> int:
	var n := 0
	var prev := {}
	for i in cards.size():
		var now := _feet_raw(B, i)
		var moved := false
		for sd in ["_l", "_r"]:
			if prev.has(sd) and _pinned(i, sd, prev[sd], now[sd]):
				var miss := B.plant(sd, prev[sd][0], prev[sd][1], now[sd][3])
				if miss > 0.01:
					print("  pin %s card %d: the leg misses by %.3f m (thigh %s calf %s foot %s, hip-ball %.3f m)" % [sd, i, miss, B.ang["thigh" + sd], B.ang["calf" + sd], B.ang["foot" + sd], ((B.P["thigh" + sd] - prev[sd][0]) as Vector3).length()])
				moved = true
				n += 1
			elif prev.has(sd) and _steps(i).has(sd):
				var land: Vector3 = prev[sd][0] + _steps(i)[sd]
				land.y = prev[sd][0].y
				B.plant(sd, land, now[sd][1], true)
				moved = true
				n += 1
		if moved:
			B.apply_grip()
			cards[i]["pose"] = B.to_dict()
			now = _feet_raw(B, i)
			for sd in ["_l", "_r"]:
				if prev.has(sd) and _pinned(i, sd, prev[sd], now[sd]):
					now[sd][0] = prev[sd][0]
					now[sd][1] = prev[sd][1]
		prev = now
	return n


## frames where parts sink into each other: [[frame, time, [[a, b, depth m], ...]], ...]
func check(B: Body) -> Array:
	var bad := []
	var n := int(ceil(length() * fps))
	for f in n + 1:
		var t := float(f) / fps
		apply(B, t)
		var c := B.contacts()
		if not c.is_empty():
			bad.append([f, snappedf(t, 0.001), c.map(func(x): return [x[0], x[1], snappedf(x[2], 0.001)])])
	return bad


## add pass-by poses where a move goes through the body. Returns how many it added.
func clear(B: Body) -> int:
	var added := 0
	var guard := 0
	var i := 1
	while i < cards.size() and guard < 12:
		guard += 1
		var ts := times()
		var a := Moves._flat(cards[i - 1]["pose"])
		var b := Moves._flat(cards[i]["pose"])
		var worst := 0.0
		var worst_u := -1.0
		var worst_c := []
		put(B, a)
		var base := B.penetration()
		put(B, b)
		base = maxf(base, B.penetration())
		for k in range(1, 20):
			var u := k / 20.0
			put(B, blend(a, b, u, cards[i].get("ease", "")))
			B.apply_grip()
			var p := B.penetration() - base
			if p > 0.002 and p > worst:
				worst = p
				worst_u = u
				worst_c = B.contacts()
		if worst_u < 0.0:
			i += 1
			continue
		# lift the arm(s) in the contacts out from the body until that frame is clean
		put(B, blend(a, b, worst_u, cards[i].get("ease", "")))
		var arms := {}
		for c in worst_c:
			for part in [c[0], c[1]]:
				var s: String = part
				if s in Body.WEAPON and B.wep_hand != "":
					s = B.wep_hand
				for side in ["_r", "_l"]:
					if s.ends_with(side) and (s.begins_with("upperarm") or s.begins_with("lowerarm") or s.begins_with("hand")):
						arms["upperarm" + side] = true
		if arms.is_empty():
			i += 1
			continue
		# search the arm(s) out of the body, staying as close as it can to the in-between (so the path keeps its shape);
		# the wrist stays nearly straight (forearm turn allowed), as in the keys
		var js := []
		var want := {}
		for ua in arms:
			var sd: String = (ua as String).substr((ua as String).length() - 2)
			for j in ["clavicle" + sd, "upperarm" + sd, "lowerarm" + sd, "hand" + sd]:
				js.append(j)
				want[j] = B.ang[j]
		var keep_lim := {}
		for j in js:
			if (j as String).begins_with("hand"):
				keep_lim[j] = (B.lim[j] as Dictionary).duplicate()
				B.lim[j]["bend"] = Vector2(-15, 15)
				B.lim[j]["side"] = Vector2(-20, 20)
				B.lim[j]["twist"] = Vector2(-60, 60)
		var near := func() -> float:
			var c := 0.0
			for j in js:
				c += ((B.ang[j] as Vector3) - (want[j] as Vector3)).length() / 400.0
			return c
		B.search(js, near, base)
		for j in keep_lim:
			B.lim[j] = keep_lim[j]
		B.apply_grip()
		var clean := B.penetration() <= base + 0.001
		var via := B.to_dict()
		var mv := move_time(i)
		cards.insert(i, {"name": "pass-by", "pose": via, "move": maxf(0.15, mv * worst_u), "hold": 0.0})
		if cards[i + 1]["move"] <= 0.0:
			cards[i + 1]["move"] = maxf(0.15, mv * (1.0 - worst_u))
		added += 1
		i += 2   # one pass-by per segment: re-checking the halves stacked 20+ of them (10-13) (a -> pass-by); the second half is checked when i reaches it
	return added


## frames = false: no bad_frames (the whole-scene collision playback, seconds on a long scene): the autosave's quick copy
func to_dict(B: Body, frames := true) -> Dictionary:
	# the file records the REAL motion: the stepped preview is a view setting (round 8: saving during it wrote the
	# stepped playback's bad_frames into the file)
	var was := stepped
	stepped = false
	var bad := check(B) if frames else []
	stepped = was
	var ts := times()
	var cs := []
	for i in cards.size():
		var c: Dictionary = cards[i]
		cs.append({"name": c["name"], "move": c["move"], "hold": c["hold"], "arrive_s": snappedf(ts[i][1], 0.001),
			"leave_s": snappedf(ts[i][2], 0.001), "pose": c["pose"]})
		if c.get("flow", false):
			cs[-1]["flow"] = true
		if c.get("walk", false):
			cs[-1]["walk"] = true
		if c.has("steps"):
			var st := {}
			for sd in _steps(i):
				var v: Vector3 = _steps(i)[sd]
				st[sd] = [v.x, v.y, v.z]
			cs[-1]["steps"] = st
		if c.has("lift"):
			cs[-1]["lift"] = c["lift"]
		if c.get("ease", "smooth") != "smooth":
			cs[-1]["ease"] = c["ease"]
		if not c.get("plant", []).is_empty():
			cs[-1]["plant"] = c["plant"]
		if c.has("take"):
			cs[-1]["take"] = c["take"]   # UU2: only on a card that has one
		if c.has("drop"):
			cs[-1]["drop"] = c["drop"]
		if c.get("air", false):
			cs[-1]["air"] = true   # VV1: only when on
		if c.has("ktype"):
			cs[-1]["ktype"] = c["ktype"]   # XX3: a key's Blender type (breakdown, moving_hold, extreme); never written for a plain key
	var out := {"scene": name, "natural": natural, "on_floor": on_floor, "floor_body": floor_body, "pin": pin, "fps": fps, "length_s": snappedf(length(), 0.001), "cards": cs,
		"bad_frames": bad,
		"note": "cards = poses in order; move = seconds to arrive from the card before (-1 = auto), hold = seconds still. In-betweens: scene.gd / MATH.md (natural = body leads, hands follow, smootherstep). bad_frames = frames with parts inside each other."}
	if not frames:
		out.erase("bad_frames")   # key order of the rest kept: a full save is byte-identical to before
	if spline:
		out["spline"] = true   # written only when on, so every older scene saves byte-identical
	if moving_holds:
		out["moving_holds"] = true   # the same: only when on
	if loop:
		out["loop"] = true   # the same
	if breath > 0.0:
		out["breath"] = breath   # YY6: the same, only when on
	if not layer.is_empty():   # YY9: only with a layer, so a scene without one saves as before
		var ly := {}
		for j in layer:
			var v: Vector3 = layer[j]
			ly[j] = [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]
		out["layer"] = ly
		out["layer_w"] = layer_w
	if not layers.is_empty():   # NA1: only with a further layer
		out["layers"] = layers.map(func(L): return Scene.layer_to_file(L))
	if not props.is_empty():
		out["props"] = props.map(func(p): return Props.to_dict(p))   # the same: a scene with no set saves as before
	if not part_keys.is_empty():
		out["part_keys"] = PartKeys.to_file(part_keys)   # WW1: the same, only when there is one
	if not markers.is_empty():
		out["markers"] = markers.duplicate(true)   # WW5: the same, only when there are any
	if not audio.is_empty():
		out["audio"] = AudioTrack.clean(audio)   # the sound: the same, only when there is one
	if not actors.is_empty():   # G1: the same, only with a second actor
		out["actors"] = actors.map(func(a): return {"name": a["name"], "xf": {"pos": [float(a["xf"]["pos"][0]), float(a["xf"]["pos"][1])], "yaw": float(a["xf"]["yaw"])},
			"scene": (a["scene"] as Scene).to_dict(B, frames)})
	if not ik.is_empty():
		out["ik"] = LimbIK.to_file(ik)   # IK keys: the same, only when there is one
	return out


## MIRROR'S LIST (round 19, GATES Z1, UPGRADES #3): every key a scene file and its cards hold, and what Mirror the
## scene does with it. "free" = has no side, copied as is; anything else is SIDED and says how it changes. A key not
## on this list fails tests/mirror_list_test.gd: whoever adds a key decides here whether it has a side.
const MIRROR_SCENE := {"scene": "renamed <name>_mirrored", "plan": "rewritten: where it came from", "cards": "each card, below",
	"bad_frames": "SIDED: recomputed from the mirrored motion (part names like thigh_l)", "natural": "free", "on_floor": "free",
	"floor_body": "free", "pin": "free", "fps": "free", "spline": "free", "moving_holds": "free", "loop": "free", "breath": "free", "layer_w": "free",
	"layer": "SIDED: Scene.mirror_layer (each joint's offset to its twin, reflected as mirror_pose does)",
	"layers": "SIDED: each layer's \"v\" by Scene.mirror_layer (an override's angles reflect the same way), its \"offset\" x negated; the rest free",
	"length_s": "free", "note": "free", "markers": "free (times, not sides)", "audio": "free (the sound is not mirrored)", "props": "SIDED: each prop's x negated and its yaw negated (the set reflected)",
	"actors": "SIDED: each actor's scene mirrored whole (Scene.mirror_file), its xf pos x negated and its yaw negated",
	"part_keys": "SIDED: PartKeys.mirror_file (each joint's keys to its twin, each value reflected as mirror_pose does)",
	"ik": "SIDED: LimbIK.mirror_file (each limb's keys to its twin, hand_l <-> hand_r, foot_l <-> foot_r; target and pole x negated; the tip rotation reflected)"}
const MIRROR_CARD := {"pose": "SIDED: Body.mirror_pose (every joint to its twin, reflected; the weapon changes hands)",
	"steps": "SIDED: _l <-> _r, the sideways x negated", "plant": "SIDED: _l <-> _r", "name": "free", "move": "free",
	"hold": "free", "arrive_s": "free", "leave_s": "free", "flow": "free", "walk": "free", "lift": "free", "ease": "free",
	"take": "SIDED: the holding hands _l <-> _r (the grip is re-read from the mirrored pose)", "drop": "free", "air": "free", "ktype": "free"}


## one card of a scene file, mirrored by MIRROR_CARD (M: a Body to mirror poses on); keys not on the list are copied
static func mirror_card(c: Dictionary, M: Body) -> Dictionary:
	var out := c.duplicate(true)
	M.from_dict(c["pose"])
	M.mirror_pose()
	out["pose"] = M.to_dict()
	if c.has("steps"):
		var st := {}
		for sd in c["steps"]:
			var v: Array = c["steps"][sd]
			st["_r" if sd == "_l" else "_l"] = [-float(v[0]), v[1], v[2]]
		out["steps"] = st
	if c.has("plant"):
		out["plant"] = c["plant"].map(func(sd): return "_r" if sd == "_l" else "_l")
	if c.has("take"):
		var hs: Array = c["take"].get("hands", ["_r"]).map(func(sd): return "_r" if sd == "_l" else "_l")
		hs.sort()
		out["take"] = {"prop": c["take"]["prop"], "hands": hs}
	return out


## a whole scene FILE mirrored (the dict main's Mirror the scene builds, plus the actors, G1): cards, part_keys, layer, layers,
## props, and each actor's scene by the same, its xf x and yaw negated. The name toggles "_mirrored" so twice is the original.
## The caller adds "plan". M is a scratch Body (its pose is overwritten; the caller keeps its own state)
static func mirror_file(d: Dictionary, M: Body) -> Dictionary:
	var d2: Dictionary = d.duplicate(true)
	d2["cards"] = d2["cards"].map(func(c): return Scene.mirror_card(c, M))
	if d2.has("part_keys"):
		d2["part_keys"] = PartKeys.mirror_file(d2["part_keys"], M)
	if d2.has("ik"):
		d2["ik"] = LimbIK.mirror_file(d2["ik"])   # as main._mirror_scene: hand_l <-> hand_r, points x negated
	if d2.has("layer"):
		d2["layer"] = Scene.mirror_layer(d2["layer"], M)
	for L in d2.get("layers", []):
		var o = L["v"].get("offset")
		L["v"].erase("offset")
		L["v"] = Scene.mirror_layer(L["v"], M)
		if o != null:
			L["v"]["offset"] = [-float(o[0]), o[1], o[2]]
	var nm := String(d2.get("scene", "scene"))
	d2["scene"] = nm.trim_suffix("_mirrored") if nm.ends_with("_mirrored") else nm + "_mirrored"
	var acts: Array = d2.get("actors", [])
	d2.erase("actors")
	var S2 := Scene.new()
	S2.from_dict(d2)
	var out := S2.to_dict(M)   # bad_frames recomputed on the mirrored motion
	if out.has("props"):
		out["props"] = out["props"].map(func(q): return {"kind": q["kind"], "pos": [-float(q["pos"][0]), q["pos"][1], q["pos"][2]], "yaw": -float(q["yaw"])})
	if not acts.is_empty():
		out["actors"] = acts.map(func(a): return {"name": a["name"], "xf": {"pos": [-float(a["xf"]["pos"][0]), float(a["xf"]["pos"][1])], "yaw": -float(a["xf"]["yaw"])},
			"scene": Scene.mirror_file(a["scene"], M)})
	return out


func from_dict(d: Dictionary) -> void:
	actors = []
	for a in d.get("actors", []):   # G1: each nested scene by this same from_dict
		var xf: Dictionary = a.get("xf", {})
		var pp: Array = xf.get("pos", [0.0, 0.0])
		var sc := Scene.new()
		sc.from_dict(a.get("scene", {}))
		actors.append({"name": String(a.get("name", "B")), "xf": {"pos": [float(pp[0]), float(pp[1])], "yaw": float(xf.get("yaw", 0.0))}, "scene": sc})
	name = d.get("scene", "scene")
	natural = bool(d.get("natural", true))
	spline = bool(d.get("spline", false))
	moving_holds = bool(d.get("moving_holds", false))
	loop = bool(d.get("loop", false))
	breath = float(d.get("breath", 0.0))
	layer = {}
	for j in d.get("layer", {}):
		var a: Array = d["layer"][j]
		layer[j] = Vector3(float(a[0]), float(a[1]), float(a[2]))
	layer_w = clampf(float(d.get("layer_w", 1.0)), 0.0, 1.0)
	layers = (d.get("layers", []) as Array).map(func(L): return Scene.layer_from_file(L))   # NA1
	on_floor = bool(d.get("on_floor", true))
	floor_body = bool(d.get("floor_body", false))
	pin = bool(d.get("pin", true))
	fps = int(d.get("fps", 30))
	markers = Markers.from_list(d.get("markers", []))
	audio = AudioTrack.clean(d["audio"]) if d.get("audio") is Dictionary and String(d["audio"].get("path", "")) != "" else {}
	props = []
	props_skipped = []
	part_keys = PartKeys.from_file(d.get("part_keys", {}))   # WW1: absent = none
	ik = LimbIK.from_file(d.get("ik", {}))   # IK keys: absent = none
	for p in d.get("props", []):
		if p is Dictionary and Props.has_kind(String(p.get("kind", ""))):
			props.append(Props.from_dict(p))
		elif p is Dictionary:
			props_skipped.append(String(p.get("kind", "?")))   # a model not in this library: said on load (main.gd)
	cards = []
	for c in d.get("cards", []):
		cards.append({"name": c["name"], "pose": c["pose"], "move": float(c.get("move", -1.0)), "hold": float(c.get("hold", 0.3))})
		if c.has("steps"):
			cards[-1]["steps"] = c["steps"]
		if c.has("lift"):
			cards[-1]["lift"] = float(c["lift"])
		if c.get("flow", false):
			cards[-1]["flow"] = true
		if c.get("walk", false):
			cards[-1]["walk"] = true
		if String(c.get("ease", "smooth")) in EASES and c.get("ease", "smooth") != "smooth":
			cards[-1]["ease"] = c["ease"]
		if c.get("plant", []) is Array and not c.get("plant", []).is_empty():
			cards[-1]["plant"] = c["plant"].filter(func(x): return x in ["_l", "_r"])
		if c.get("take", null) is Dictionary and c["take"].has("prop"):
			var hs: Array = Array(c["take"].get("hands", ["_r"])).filter(func(x): return x in ["_l", "_r"])
			cards[-1]["take"] = {"prop": int(c["take"]["prop"]), "hands": hs if not hs.is_empty() else ["_r"]}
		if c.has("drop"):
			cards[-1]["drop"] = int(c["drop"])
		if c.get("air", false):
			cards[-1]["air"] = true
		if String(c.get("ktype", "")) in DopeSheet.TYPED:
			cards[-1]["ktype"] = String(c["ktype"])   # XX3


## SPINS (Nick 10-13: banned): key pairs where an arm rolls around itself more than Body.ROLL_STEP + 5 deg: the upper
## arm's roll or the forearm's turn (the hand's twist). Blending such a pair turns the arm and the weapon through the
## body. Returns ["key a -> key b: upperarm_r roll +63", ...]
func spins() -> Array:
	var out := []
	for i in range(1, cards.size()):
		var a: Dictionary = Moves._flat(cards[i - 1]["pose"])["ang"]
		var b: Dictionary = Moves._flat(cards[i]["pose"])["ang"]
		for j in ["upperarm_r", "upperarm_l", "hand_r", "hand_l"]:
			if not a.has(j) or not b.has(j):
				continue
			var d: float = float((b[j] as Vector3).z) - float((a[j] as Vector3).z)
			if absf(d) > Body.ROLL_STEP + 5.0:
				out.append("%s -> %s: %s %s %+.0f" % [cards[i - 1]["name"], cards[i]["name"], j, "roll" if j.begins_with("upper") else "forearm turn", d])
	return out
