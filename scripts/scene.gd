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
var markers := []      # named moments on the timeline (round 41, WW5; Markers): [{"t", "name", "kind"}] sorted by t; in the file only when any
var props := []        # the SET (round 37, SS5): [Props dicts {"kind", "xf"}]; in the file as "props" (only when any)
var props_skipped := []   # kinds the file named that this library does not have (from_dict)
var part_keys := {}    # PART KEYS (round 41, WW1): {"<joint>": [{"t", "v": Vector3}]} by time; see scripts/part_keys.gd
var name := "scene"
var natural := true
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
			return blend(a, Moves._flat(cards[i]["pose"]), u, cards[i].get("ease", ""))
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


func apply(B: Body, t: float) -> void:
	var was_fast := B.fast
	B.fast = true   # planting legs in playback: limits only (contacts are measured, not avoided, per frame)
	_apply(B, t)
	B.fast = was_fast


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
						at = (a[0] as Vector3).lerp(b[0], e) + Vector3.UP * lift * sin(PI * e)
						head = lerp_angle(a[1], b[1], e)
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
			else:
				for sd in ["_l", "_r"]:
					var h: Array = E[held][sd]
					if h[3] != "free":
						B.plant(sd, h[0], h[1], h[2])
	_planted(B, t)
	B.apply_grip()


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


## a scene of its own with the same settings and a deep copy of the cards (for work off the main thread: the fix
## preview). Caches start empty
func clone() -> Scene:
	var c := Scene.new()
	c.cards = cards.duplicate(true)
	for k in ["name", "natural", "spline", "on_floor", "floor_body", "pin", "fps", "moving_holds", "stepped", "loop"]:
		c.set(k, get(k))
	c.props = props   # the set (read only there)
	c.part_keys = part_keys.duplicate(true)
	c.markers = markers.duplicate(true)
	return c


## CARRY (round 39, GATES UU2 / UU3, #206). Written on the CARDS, so inserting, deleting or reordering cards keeps
## them where they belong: card["take"] = {"prop": i, "hands": ["_r"] / ["_l", "_r"]} (the hands hold prop i from
## this card's arrival on), card["drop"] = i (they let it go at this card's arrival). Nothing about the grip is
## stored: it is where the prop is relative to the hand(s) on the take card, so editing that card re-grips it and
## Mirror needs only the hands swapped. After the drop the prop FALLS: y(t) = y0 - G t^2 / 2 onto the top or floor
## under it (at t = sqrt(2 h / G)), keeping only its turn about the vertical; then it stays there.
const G := 9.81
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
	var key := [ts, JSON.stringify(cs), JSON.stringify(props.map(func(p): return Props.to_dict(p))), var_to_str(part_keys)]
	if not _carry_memo.is_empty() and is_same(_carry_memo[0][0], ts) and _carry_memo[0][1] == key[1] and _carry_memo[0][2] == key[2] 			and _carry_memo[0][3] == key[3]:   # a keyed hand moves the grip (WW1)
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


func to_dict(B: Body) -> Dictionary:
	# the file records the REAL motion: the stepped preview is a view setting (round 8: saving during it wrote the
	# stepped playback's bad_frames into the file)
	var was := stepped
	stepped = false
	var bad := check(B)
	stepped = was
	var ts := times()
	var cs := []
	for i in cards.size():
		var c: Dictionary = cards[i]
		cs.append({"name": c["name"], "move": c["move"], "hold": c["hold"], "arrive_s": snappedf(ts[i][1], 0.001),
			"leave_s": snappedf(ts[i][2], 0.001), "pose": c["pose"]})
		if c.get("flow", false):
			cs[-1]["flow"] = true
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
	var out := {"scene": name, "natural": natural, "on_floor": on_floor, "floor_body": floor_body, "pin": pin, "fps": fps, "length_s": snappedf(length(), 0.001), "cards": cs,
		"bad_frames": bad,
		"note": "cards = poses in order; move = seconds to arrive from the card before (-1 = auto), hold = seconds still. In-betweens: scene.gd / MATH.md (natural = body leads, hands follow, smootherstep). bad_frames = frames with parts inside each other."}
	if spline:
		out["spline"] = true   # written only when on, so every older scene saves byte-identical
	if moving_holds:
		out["moving_holds"] = true   # the same: only when on
	if loop:
		out["loop"] = true   # the same
	if not props.is_empty():
		out["props"] = props.map(func(p): return Props.to_dict(p))   # the same: a scene with no set saves as before
	if not part_keys.is_empty():
		out["part_keys"] = PartKeys.to_file(part_keys)   # WW1: the same, only when there is one
	if not markers.is_empty():
		out["markers"] = markers.duplicate(true)   # WW5: the same, only when there are any
	return out


## MIRROR'S LIST (round 19, GATES Z1, UPGRADES #3): every key a scene file and its cards hold, and what Mirror the
## scene does with it. "free" = has no side, copied as is; anything else is SIDED and says how it changes. A key not
## on this list fails tests/mirror_list_test.gd: whoever adds a key decides here whether it has a side.
const MIRROR_SCENE := {"scene": "renamed <name>_mirrored", "plan": "rewritten: where it came from", "cards": "each card, below",
	"bad_frames": "SIDED: recomputed from the mirrored motion (part names like thigh_l)", "natural": "free", "on_floor": "free",
	"floor_body": "free", "pin": "free", "fps": "free", "spline": "free", "moving_holds": "free", "loop": "free",
	"length_s": "free", "note": "free", "markers": "free (times, not sides)", "props": "SIDED: each prop's x negated and its yaw negated (the set reflected)",
	"part_keys": "SIDED: PartKeys.mirror_file (each joint's keys to its twin, each value reflected as mirror_pose does)"}
const MIRROR_CARD := {"pose": "SIDED: Body.mirror_pose (every joint to its twin, reflected; the weapon changes hands)",
	"steps": "SIDED: _l <-> _r, the sideways x negated", "plant": "SIDED: _l <-> _r", "name": "free", "move": "free",
	"hold": "free", "arrive_s": "free", "leave_s": "free", "flow": "free", "lift": "free", "ease": "free",
	"take": "SIDED: the holding hands _l <-> _r (the grip is re-read from the mirrored pose)", "drop": "free", "air": "free"}


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


func from_dict(d: Dictionary) -> void:
	name = d.get("scene", "scene")
	natural = bool(d.get("natural", true))
	spline = bool(d.get("spline", false))
	moving_holds = bool(d.get("moving_holds", false))
	loop = bool(d.get("loop", false))
	on_floor = bool(d.get("on_floor", true))
	floor_body = bool(d.get("floor_body", false))
	pin = bool(d.get("pin", true))
	fps = int(d.get("fps", 30))
	markers = Markers.from_list(d.get("markers", []))
	props = []
	props_skipped = []
	part_keys = PartKeys.from_file(d.get("part_keys", {}))   # WW1: absent = none
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
