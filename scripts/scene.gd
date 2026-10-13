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
## CLEARANCE: if an in-between frame puts parts inside each other (and the two cards don't), clear() adds a pass-by
##   pose at the worst frame: the arm involved is lifted out from the body until that frame is clean. It shows up as its
##   own card ("pass-by"), so you can see and edit it.
class_name Scene
extends RefCounted

const LAG := 0.3
var cards := []        # [{"name", "pose", "move", "hold"}]
var name := "scene"
var natural := true
var on_floor := true   # every frame: the hips move up/down so the lowest sole touches the floor (Body.ground)
var pin := true        # feet that stay put between two clips are planted: they don't slide while the body turns
const STEP := 0.12     # a toe base that moves more than this (m, along the floor) between clips = a step, not planted
var fps := 30


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


## the time this card's move takes (its own value, or auto from the angles)
func move_time(i: int) -> float:
	if i == 0:
		return 0.0
	var m: float = cards[i]["move"]
	if m > 0.0:
		return m
	var a := Moves._flat(cards[i - 1]["pose"])
	var b := Moves._flat(cards[i]["pose"])
	var big := 0.0
	for j in a["ang"]:
		if level(j) >= 6 or not b["ang"].has(j):
			continue
		var d: Vector3 = ((b["ang"][j] as Vector3) - (a["ang"][j] as Vector3)).abs()
		big = maxf(big, maxf(d.x, maxf(d.y, d.z)))
	big = maxf(big, ((b["offset"] as Vector3) - (a["offset"] as Vector3)).length() * 300.0)   # 30 cm of hips ~ 90 deg
	return clampf(0.25 + big / 200.0, 0.3, 1.6)


## [start of move, arrival, end of hold] per card
func times() -> Array:
	var out := []
	var t := 0.0
	for i in cards.size():
		var m := move_time(i)
		out.append([t, t + m, t + m + float(cards[i]["hold"])])
		t += m + float(cards[i]["hold"])
	return out


func length() -> float:
	var ts := times()
	return ts[-1][2] if not ts.is_empty() else 0.0


## the pose at time t: {"offset", "ang", "weapon"} (same shape as Moves.sample)
func sample(t: float) -> Dictionary:
	if cards.is_empty():
		return {}
	var ts := times()
	for i in cards.size():
		if t < ts[i][1] and i > 0:
			var u := clampf((t - ts[i][0]) / maxf(1e-6, ts[i][1] - ts[i][0]), 0.0, 1.0)
			return blend(Moves._flat(cards[i - 1]["pose"]), Moves._flat(cards[i]["pose"]), u)
		if t < ts[i][2]:
			return Moves._flat(cards[i]["pose"])
	return Moves._flat(cards[-1]["pose"])


func blend(a: Dictionary, b: Dictionary, u: float) -> Dictionary:
	var ang := {}
	for j in a["ang"]:
		var e := _ease(u, level(j))
		ang[j] = (a["ang"][j] as Vector3).lerp(b["ang"].get(j, a["ang"][j]), e)
	var eh := _ease(u, 0)
	var w: Dictionary = a["weapon"].duplicate()
	var wb: Dictionary = b["weapon"]
	var eb := _ease(u, 5)
	if w.is_empty() or wb.is_empty() or w.get("hand", "") != wb.get("hand", ""):
		w = a["weapon"] if eb < 0.5 else wb
	else:
		var key := "local_" if w.get("hand", "") != "" else ""
		w[key + "pos"] = (w[key + "pos"] as Vector3).lerp(wb[key + "pos"], eb)
		w[key + "rot"] = (w[key + "rot"] as Quaternion).slerp(wb[key + "rot"], eb)
	return {"offset": (a["offset"] as Vector3).lerp(b["offset"], eh), "ang": ang, "weapon": w}


func _ease(u: float, lv: int) -> float:
	if not natural:
		return u * u * (3.0 - 2.0 * u)
	var x := clampf((u - LAG * lv / 6.0) / (1.0 - LAG), 0.0, 1.0)
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
	var w: Dictionary = s["weapon"]
	B.wep_on = not w.is_empty()
	if B.wep_on:
		B.set_weapon_len(w["length"])
		B.wep_hand = w["hand"]
		B.wep_pos = w["pos"]
		B.wep_rot = w["rot"]
		B.wep_lpos = w["local_pos"]
		B.wep_lrot = w["local_rot"]
		B.grip = w["grip"]
		B.grip_u = w["grip_m"]


func apply(B: Body, t: float) -> void:
	put(B, sample(t))
	if on_floor:
		B.ground()
	if pin:
		var i := span(t)
		if i > 0:
			var a := _feet(B, i - 1)
			var b := _feet(B, i)
			put(B, sample(t))
			if on_floor:
				B.ground()
			var e := _ease(clampf((t - times()[i][0]) / maxf(1e-6, move_time(i)), 0.0, 1.0), 5)
			for sd in ["_l", "_r"]:
				if _pinned(i, sd, a[sd], b[sd]):
					B.plant(sd, a[sd][0], a[sd][1], a[sd][3] and b[sd][3])
				elif _steps(i).has(sd):
					# a STEP: the toe base travels from where it stood to where it lands, lifted on an arc
					#   at = lerp(a, b, e) + up * LIFT * sin(pi e)
					var at: Vector3 = (a[sd][0] as Vector3).lerp(b[sd][0], e) + Vector3.UP * LIFT * sin(PI * e)
					B.plant(sd, at, lerp_angle(a[sd][1], b[sd][1], e), false)
	B.apply_grip()


## the card the body is moving INTO at time t (-1 while holding still)
func span(t: float) -> int:
	var ts := times()
	for i in range(1, cards.size()):
		if t >= ts[i][0] and t < ts[i][1]:
			return i
	return -1


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
		B.ground()
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
			put(B, blend(a, b, u))
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
		put(B, blend(a, b, worst_u))
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
	var bad := check(B)
	var ts := times()
	var cs := []
	for i in cards.size():
		var c: Dictionary = cards[i]
		cs.append({"name": c["name"], "move": c["move"], "hold": c["hold"], "arrive_s": snappedf(ts[i][1], 0.001),
			"leave_s": snappedf(ts[i][2], 0.001), "pose": c["pose"]})
		if c.has("steps"):
			var st := {}
			for sd in _steps(i):
				var v: Vector3 = _steps(i)[sd]
				st[sd] = [v.x, v.y, v.z]
			cs[-1]["steps"] = st
	return {"scene": name, "natural": natural, "on_floor": on_floor, "pin": pin, "fps": fps, "length_s": snappedf(length(), 0.001), "cards": cs,
		"bad_frames": bad,
		"note": "cards = poses in order; move = seconds to arrive from the card before (-1 = auto), hold = seconds still. In-betweens: scene.gd / MATH.md (natural = body leads, hands follow, smootherstep). bad_frames = frames with parts inside each other."}


func from_dict(d: Dictionary) -> void:
	name = d.get("scene", "scene")
	natural = bool(d.get("natural", true))
	on_floor = bool(d.get("on_floor", true))
	pin = bool(d.get("pin", true))
	fps = int(d.get("fps", 30))
	cards = []
	for c in d.get("cards", []):
		cards.append({"name": c["name"], "pose": c["pose"], "move": float(c.get("move", -1.0)), "hold": float(c.get("hold", 0.3))})
		if c.has("steps"):
			cards[-1]["steps"] = c["steps"]
