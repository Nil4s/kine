## choreo.gd - CHOREOGRAPHY FOR 2+ FIGHTERS (ROADMAP 13). Static, no UI (choreo_view.gd draws it; main.gd owns undo).
## BEATS: named moments on the shared time line, the way an exchange is planned: "A attacks", "B parries", "B counters".
##   [{"t": seconds, "name": String, "by": fighter, "on": fighter}] sorted by t. Fighter numbers are the hero's
##   (0 = the hero, k = actors_rt[k], the file's actors in order). Held on the HERO's scene as "beats" (only when any).
## REACH (per beat, at its t, every fighter posed by its own scene and placed by its xf, everything in the hero's space):
##   tip   = the striker's weapon tip (wep_point(wep_len)) when it holds one, else the palm of the hand nearer the target
##   gap   = the tip's distance to the target's body: min over its body capsules of (distance to the axis - radius).
##           gap > 0 = out of range by gap; gap <= 0 = the tip is inside the target: "hits".
##   bat   = the striker's weapon on the target's body (Body.cross_contacts, kind "hit"): where the bat itself meets it.
## GUARD (the defender's): its forearms and hands, and its weapon when it holds one. The STRIKE point is the bat's point
##   nearest the target (the tip for a fist). A guard is BETWEEN when it lies on the line from the strike point to the
##   target's nearest surface point (within its radius). A PARRY LANDS when the guard is between AND the striker's weapon
##   (or fist) meets it (distance <= the two radii). Between but not met: the strike clears it.
## SHIFT (Nick: "shift a fighter's whole timeline by dragging their row"): Choreo.shift moves a scene's cards in time:
##   dt > 0 = the FIRST card holds dt longer (exact: every pose at t is the old pose at t - dt; the first card stays the
##   first, so a lead card of its own would change how the scene reads the card after it: probe, 0.9 rad off);
##   dt < 0 = the first -dt is cut: inside the first card's hold or any later card's hold, exact (that card becomes the
##   first, holding on to its end); inside a move, the move into the next card is shortened to the time left, from the
##   pose at the cut (an approximation).
class_name Choreo

const GUARD := ["lowerarm_l", "lowerarm_r", "hand_l", "hand_r"]
const VERBS := {"attacks": "attacks", "parries": "parries", "counters": "counters", "moves": "moves"}


static func _body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


# ---------------------------------------------------------------- beats (the file's list)

## one beat, cleaned (a missing name is "<by> <verb> <on>"-free: "beat <n>"; by / on are fighters >= 0)
static func clean(d: Dictionary, i := 0) -> Dictionary:
	return {"t": maxf(0.0, float(d.get("t", 0.0))), "name": String(d.get("name", "beat %d" % (i + 1))),
		"by": maxi(0, int(d.get("by", 0))), "on": maxi(0, int(d.get("on", 1)))}


## the file's list -> clean, sorted by t (anything that is not a dictionary with a t is dropped)
static func from_list(l) -> Array:
	var out := []
	if l is Array:
		for d in l:
			if d is Dictionary and d.has("t"):
				out.append(clean(d, out.size()))
	return sorted(out)


static func sorted(bs: Array) -> Array:
	var out := bs.duplicate(true)
	out.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	return out


## a beat's name when the caller gives none: "<by name> attacks <on name>"
static func auto_name(by_name: String, verb: String, on_name: String) -> String:
	return "%s %s %s" % [by_name, VERBS.get(verb, verb), on_name]


# ---------------------------------------------------------------- geometry

## distance from point p to the segment ab
static func point_seg(p: Vector3, a: Vector3, b: Vector3) -> float:
	return Body.seg_seg(p, p, a, b)


## the closest point of segment ab to p
static func closest_on(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var d := b - a
	var l := d.length_squared()
	if l <= 1e-12:
		return a
	return a + d * clampf((p - a).dot(d) / l, 0.0, 1.0)


## the body's parts that can be hit (every capsule but the fingers and the weapons), by name
static func body_parts(B: Body) -> Array:
	var out := []
	for p in B.cross_parts():
		if not Body.is_wep(p) and not (p in Body.FINGERS):
			out.append(p)
	return out


## the striker's tip, in the hero's space: {"p", "what" ("tip" / "fist"), "hand"}
static func tip(S_B: Body, xf: Transform3D, T_B: Body, txf: Transform3D) -> Dictionary:
	if S_B.wep_on:
		return {"p": xf * S_B.wep_point(S_B.wep_len), "what": "tip", "hand": ""}
	var goal := txf * (T_B.P["spine_02"] as Vector3)
	var h := "hand_r"
	if (xf * S_B.palm_point("hand_l")).distance_to(goal) < (xf * S_B.palm_point("hand_r")).distance_to(goal):
		h = "hand_l"
	return {"p": xf * S_B.palm_point(h), "what": "fist", "hand": h}


## the target's surface gap to point p (hero's space): {"gap" (m; < 0 inside), "part", "at" (its axis's nearest point)}
static func surface_gap(p: Vector3, T_B: Body, txf: Transform3D) -> Dictionary:
	var best := {"gap": INF, "part": "", "at": Vector3.ZERO}
	for part in body_parts(T_B):
		var c: Array = T_B.cap(part)
		var a: Vector3 = txf * (c[0] as Vector3)
		var b: Vector3 = txf * (c[1] as Vector3)
		var g := point_seg(p, a, b) - float(T_B.rad[part])
		if g < float(best["gap"]):
			best = {"gap": g, "part": part, "at": closest_on(p, a, b)}
	return best


## the bat's point nearest the target's body (hero's space): the striking spot of a swing
static func nearest_on_weapon(S_B: Body, xf: Transform3D, T_B: Body, txf: Transform3D) -> Vector3:
	var best := xf * S_B.wep_point(0.0)
	var bd := INF
	var u := 0.0
	while u <= S_B.wep_len + 1e-6:
		var p := xf * S_B.wep_point(u)
		var g := float(surface_gap(p, T_B, txf)["gap"])
		if g < bd:
			bd = g
			best = p
		u += 0.01
	return best


## the guard parts of a defender: its forearms, hands and weapon (when it holds one)
static func guards(T_B: Body) -> Array:
	var out := GUARD.duplicate()
	if T_B.wep_on:
		out.append_array(Body.WEAPON)
	return out


## the striker's line that can meet a guard: its weapon's axis, or the fist as a point
static func striker_line(S_B: Body, xf: Transform3D, tp: Dictionary) -> Array:
	if S_B.wep_on:
		return [xf * S_B.wep_point(0.0), xf * S_B.wep_point(S_B.wep_len), float(S_B.rad["bat_barrel"])]
	var p: Vector3 = tp["p"]
	return [p, p, 0.02]


## THE REACH AND GUARD OF ONE BEAT. S_bodies: [Body] posed at the beat's t; xfs: [Transform3D] (hero's space).
## by / on index those. Returns {"t", "name", "by", "on", "what", "gap", "part", "zone", "bat", "guard", "between",
## "parry", "text"}; gap in m (positive = out of range); bat = the zone the bat meets ("" none); guard = the guard part
## that is between (the nearest), "" none.
static func check(beat: Dictionary, fighters: Array, S_bodies: Array, xfs: Array) -> Dictionary:
	var a: int = int(beat["by"])
	var b: int = int(beat["on"])
	var out := {"t": float(beat["t"]), "name": String(beat["name"]), "by": a, "on": b, "what": "", "gap": INF, "part": "",
		"zone": "", "bat": "", "guard": "", "between": false, "parry": false, "text": ""}
	if a == b or a >= S_bodies.size() or b >= S_bodies.size():
		out["text"] = "%s: needs two different fighters" % beat["name"]
		return out
	var SB: Body = S_bodies[a]
	var TB: Body = S_bodies[b]
	var sx: Transform3D = xfs[a]
	var tx: Transform3D = xfs[b]
	var tp := tip(SB, sx, TB, tx)
	var sg := surface_gap(tp["p"], TB, tx)
	out["what"] = tp["what"]
	out["gap"] = float(sg["gap"])
	out["part"] = sg["part"]
	out["zone"] = Body.cross_zone(sg["part"])
	# where the bat itself meets the target (the tip may be out of range while the barrel is in)
	var rel := sx.affine_inverse() * tx
	for row in SB.cross_contacts(TB, rel):
		if row[3] == "hit":
			out["bat"] = Body.cross_zone(row[1])
			break
	# the guard: a defender's forearm / hand / weapon on the line from the STRIKE point (the bat's point nearest the target;
	# the tip for a fist) to the target's surface. The tip is out of range while the bat's middle can be the one in contact
	var strike: Vector3 = nearest_on_weapon(SB, sx, TB, tx) if SB.wep_on else tp["p"]
	var line_to: Vector3 = surface_gap(strike, TB, tx)["at"]
	var sl := striker_line(SB, sx, tp)
	var best_g := ""
	var best_d := INF
	for g in guards(TB):
		var c: Array = TB.cap(g)
		var ga: Vector3 = tx * (c[0] as Vector3)
		var gb: Vector3 = tx * (c[1] as Vector3)
		var gr := float(TB.rad[g])
		var d := Body.seg_seg(strike, line_to, ga, gb) - gr
		if d <= 0.0 and d < best_d:
			best_d = d
			best_g = g
	if best_g != "":
		out["between"] = true
		out["guard"] = best_g
		var c2: Array = TB.cap(best_g)
		var d2 := Body.seg_seg(sl[0], sl[1], tx * (c2[0] as Vector3), tx * (c2[1] as Vector3)) - float(sl[2]) - float(TB.rad[best_g])
		out["parry"] = d2 <= 0.0
	out["text"] = _text(out, fighters)
	return out


static func _text(r: Dictionary, fighters: Array) -> String:
	var who: String = fighters[int(r["on"])]["name"]
	var head := ""
	var gap: float = float(r["gap"])
	if gap > 0.0:
		head = "out of range by %.0f cm (%s to %s)" % [gap * 100.0, r["what"], who]
	else:
		head = "hits %s's %s (%s %.0f cm in)" % [who, r["zone"], r["what"], -gap * 100.0]
	if r["bat"] != "" and gap > 0.0:
		head += "; the bat meets %s's %s" % [who, r["bat"]]
	var guard := ""
	if r["parry"]:
		guard = "parry lands: %s's %s meets the %s" % [who, r["guard"], r["what"] if r["what"] == "tip" else "fist"]
	elif r["between"]:
		guard = "guard between (%s), the strike clears it" % r["guard"]
	else:
		guard = "no guard between"
	return "%s: %s; %s" % [r["name"], head, guard]


## EVERY BEAT at once. fighters: [{"name", "S": Scene, "xf": Transform3D}], hero first (xf IDENTITY). Each fighter is posed
## by its own scene at the beat's t on a Body of its own. Returns [check(beat), ...] in beat order.
static func report(fighters: Array, beats: Array) -> Array:
	var out := []
	for beat in beats:
		var bodies := []
		var xfs := []
		for f in fighters:
			var B := _body()
			(f["S"] as Scene).apply(B, float(beat["t"]))
			bodies.append(B)
			xfs.append(f["xf"])
		out.append(check(beat, fighters, bodies, xfs))
	return out


# ---------------------------------------------------------------- the time shift

## a Body posed by scene S at t (its pose dictionary)
static func pose_at(S: Scene, t: float) -> Dictionary:
	var B := _body()
	S.apply(B, t)
	return B.to_dict()


## shifts the scene's timeline by dt seconds (rounded to frames), in place. Returns the shift done (0.0 = none). See the top.
static func shift(S: Scene, dt: float) -> float:
	var fps := float(S.fps)
	dt = roundf(dt * fps) / fps
	if S.cards.is_empty() or absf(dt) < 0.5 / fps:
		return 0.0
	if dt > 0.0:
		S.cards[0]["hold"] = float(S.cards[0]["hold"]) + dt
		return dt
	var s := -dt
	var ts: Array = S.times()
	if s >= float(ts[-1][2]):
		return 0.0
	var i := 0
	while float(ts[i][2]) <= s + 1e-9:
		i += 1
	var keep := []
	if float(ts[i][1]) <= s + 1e-9:   # in card i's hold: card i becomes the first card, holding on to its end
		var h: Dictionary = S.cards[i].duplicate(true)
		h["move"] = 0.0
		h["hold"] = float(ts[i][2]) - s
		h.erase("steps")
		keep.append(h)
	else:   # inside card i's move: the pose at the cut, then the move into card i on the time left
		var cut: Dictionary = S.cards[i].duplicate(true)
		cut["pose"] = pose_at(S, s)
		cut["move"] = 0.0
		cut["hold"] = 0.0
		cut.erase("steps")
		keep.append(cut)
		var arrive: Dictionary = S.cards[i].duplicate(true)
		arrive["move"] = float(ts[i][1]) - s
		keep.append(arrive)
	for j in range(i + 1, S.cards.size()):
		keep.append(S.cards[j].duplicate(true))
	S.cards = keep
	return dt


# ---------------------------------------------------------------- the file's key

## the beats of a scene, as the file holds them (a new array; "beats" in the file only when there are any)
static func to_list(bs: Array) -> Array:
	return sorted(bs).map(func(x): return {"t": snappedf(float(x["t"]), 0.001), "name": String(x["name"]), "by": int(x["by"]), "on": int(x["on"])})


## a beat added at t (the array stays sorted); -> the beat
static func add(bs: Array, t: float, by: int, on: int, name: String) -> Dictionary:
	var b := clean({"t": snappedf(t, 0.001), "name": name, "by": by, "on": on}, bs.size())
	bs.append(b)
	bs.sort_custom(func(x, y): return float(x["t"]) < float(y["t"]))
	return b


## the index of the beat nearest to t within tol seconds, else -1
static func near(bs: Array, t: float, tol: float) -> int:
	var best := -1
	var bd := tol + 1e-9
	for i in bs.size():
		var d := absf(float(bs[i]["t"]) - t)
		if d <= bd:
			bd = d
			best = i
	return best
