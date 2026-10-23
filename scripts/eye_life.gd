class_name EyeLife
extends RefCounted
## eye_life.gd - I08 LIVING EYES: a generated eye look-at track (saccades between fixations) and blinks over a whole scene, written into
## the face channels eye_yaw, eye_pitch and blink (scripts/face.gd) and NOTHING else. Every key it writes carries "gen": TAG, so
## remove() takes exactly them out again (the brows, jaw, visemes, lids and lips are never touched). Seeded: the same scene and seed give
## the same track, key for key.
##
## THE TARGET: with two fighters the opponent: his head (eye point), his upper chest (Gaze.chest, the I41 point) or his weapon / nearest
## striking limb (DistanceKeeper.tips), picked per fixation with the shares in PICK_2F (stated defaults after the I41 gaze note: skilled
## fighters fixate the head / chest region, Williams & Elliott 1999; from memory). With one fighter: the camera or a given point, with small
## re-fixations around it (SCATTER_DEG) and an occasional glance away (AWAY_P, AWAY_DEG) as a resting face does.
## The eye angles are the target's direction in the HEAD's frame (B.G["head"]: +Z front, +X the hero's LEFT, +Y up), from the eye point
## LookAt.eye_point, so whatever the neck and head do (the gaze director's keys included) the eyes counter it and land on the target.
##
## SACCADES (the numbers):
##   main sequence    duration = MS_SLOPE x amplitude + MS_BASE = 2.2 ms/deg x A + 21 ms (Carpenter, Movements of the Eyes, 1988; the
##                    same line in Baloh et al. 1975, Neurology 25:1065; cited from memory). The amplitude is the angle between the eye's
##                    direction before and after.
##   fixations        200-400 ms between saccades (FIX_MIN..FIX_MAX; scene viewing and reading, Rayner 1998, Psychol Bull 124:372;
##                    from memory), drawn uniformly.
##   keys             a key where the saccade starts (the held value) and one where it ends (the target), nothing in between: the PCHIP
##                    curve of part_keys.gd has zero speed at both (they are flat holds on each side), so the eye leaves and lands with a
##                    smooth bell of speed and NEVER overshoots the target (monotone between keys). The eye holds still in the head
##                    during a fixation (no pursuit); the next saccade corrects what the head moved.
##   out of range     a target the eye cannot reach (past +-45 deg yaw / +-30 deg pitch in the head) is passed over for another (REPICK
##                    tries); if none is reachable the saccade ends at the range's edge and is marked "clamped" (the head would have to turn:
##                    the I41 Gaze director turns it).
##   microsaccades    not generated (optional in the item; under MIN_AMP = 0.5 deg a re-fixation is skipped).
## BLINKS:
##   rate             REST_RATE = 17 / min at rest (15-20 / min, Bentivoglio et al. 1997, Mov Disord 12:1028; Doughty 2001; from
##                    memory). The scene is cut into slots of 60 / rate s and each slot gets ONE blink, at a jittered place inside it, so
##                    the count over a scene is set by the rate (the spacing is still irregular). Effort raises it: rate x (1 + EFFORT_K
##                    x the card expression weight of effort / pain, Scene.expr_at) - a stated default, no study read for the factor.
##   gaze-coupled     P_COUPLE (80 %) of the large gaze shifts (>= LARGE_DEG) carry a blink at their onset, and a slot only gets its
##                    jittered blink while the count is behind the slots (so the rate stays the slot rate unless large shifts crowd): blinks go with large gaze shifts and the lid starts down at about
##                    the saccade's start (Evinger et al. 1994, Exp Brain Res 100:337, "Not looking while leaping"; from memory).
##   after a hit      a reflex blink REFLEX_LAT = 40 ms after each hit on this fighter (a card the face would wear pain on, Face.suggest,
##                    and with two fighters each strike of the opponent that lands, BeatFight.contacts). Blink reflex R2 latency about
##                    30-40 ms (from memory). A rest blink closer than MIN_GAP to it is dropped.
##   shape            close CLOSE_MIN..CLOSE_MAX (40-60 ms), shut HOLD_MAX (0-20 ms), open OPEN_K x the close (1.8-2.4 x): the lid comes
##                    down faster than it goes up (Evinger, Manning & Sibony 1991, IOVS 32:387; from memory); a whole blink 0.11-0.22 s,
##                    inside the 0.1-0.4 s of face.gd's blink note (Doughty 2001).

const TAG := "i08"
const CHANNELS := ["eye_yaw", "eye_pitch", "blink"]
const MS_SLOPE := 0.0022     # s per deg of amplitude (2.2 ms/deg)
const MS_BASE := 0.021       # s (21 ms)
const FIX_MIN := 0.2         # s
const FIX_MAX := 0.4         # s
const MIN_AMP := 0.5         # deg: a re-fixation smaller than this is not keyed (microsaccade range)
const REST_RATE := 17.0      # blinks per minute at rest
const EFFORT_K := 0.5        # rate x (1 + EFFORT_K x effort)
const LARGE_DEG := 15.0      # deg: a gaze shift this large takes the slot's blink at its onset
const REFLEX_LAT := 0.04     # s from a hit to the reflex blink
const MIN_GAP := 0.4         # s: no two blinks start closer than this
const CLOSE_MIN := 0.04
const CLOSE_MAX := 0.06
const HOLD_MAX := 0.02
const OPEN_K := Vector2(1.8, 2.4)
const SCATTER_DEG := 4.0     # deg: one-fighter re-fixations land within this of the point
const AWAY_P := 0.08         # one-fighter: the share of fixations that glance away
const AWAY_DEG := Vector2(15.0, 28.0)
const REPICK := 6            # candidate targets tried per fixation before one out of the eye's range is kept (clamped)
const P_COUPLE := 0.8        # the share of large gaze shifts that carry a blink (a stated default for "often")
const PICK_2F := {"head": 0.55, "chest": 0.25, "weapon": 0.20}


## the main-sequence duration (s) of a saccade of amp degrees
static func ms_dur(amp: float) -> float:
	return MS_SLOPE * amp + MS_BASE


## the eye-in-head angles (deg) that look from B's eye at world point p: Vector2(yaw: + = the hero's LEFT, pitch: + = up)
static func eye_angles(B: Body, p: Vector3) -> Vector2:
	var g: Quaternion = B.G["head"]
	var d := p - LookAt.eye_point(B)
	var f := d.dot(g * Vector3(0, 0, 1))
	var l := d.dot(g * Vector3(1, 0, 0))
	var u := d.dot(g * Vector3(0, 1, 0))
	return Vector2(rad_to_deg(atan2(l, f)), rad_to_deg(atan2(u, sqrt(f * f + l * l))))


## the unit direction (head frame: x left, y up, z front) of eye angles a (deg)
static func dir_of(a: Vector2) -> Vector3:
	var y := deg_to_rad(a.x)
	var p := deg_to_rad(a.y)
	return Vector3(cos(p) * sin(y), sin(p), cos(p) * cos(y))


## the angle (deg) between two eye directions
static func amp_of(a: Vector2, b: Vector2) -> float:
	return rad_to_deg(dir_of(a).angle_to(dir_of(b)))


static func _clamp(a: Vector2) -> Vector2:
	return Vector2(clampf(a.x, -Face.EYE_YAW_MAX, Face.EYE_YAW_MAX), clampf(a.y, -Face.EYE_PITCH_MAX, Face.EYE_PITCH_MAX))


## the world point (A's space) a fixation looks at, at time t. fx = {"kind", "pt" (point kinds), "tip" (weapon)}; BD posed at t.
static func goal(fx: Dictionary, BD: Body, xf: Transform3D) -> Vector3:
	match String(fx["kind"]):
		"head":
			return xf * LookAt.eye_point(BD)
		"chest":
			return Gaze.chest(BD, xf)
		"weapon":
			return xf * (DistanceKeeper.tips(BD)[fx["tip"]] as Vector3)
	return fx["pt"]


## Compute the living eyes of scene A0 (neither scene is touched: clones). opts: "seed" (int), "point" (Vector3, A's space: what one
## fighter looks at), "D" (Scene: the opponent) with "xf" (Transform3D: D's space to A's). Returns {"keys": {eye_yaw, eye_pitch, blink:
## [{"t", "v", "gen"}]}, "sacc": [{"t0", "t1", "amp", "dur", "kind", "pt" (the goal at t1), "clamped"}], "blinks": [{"t0", "close", "hold",
## "open", "why": "rest" | "gaze" | "hit"}], "fix": [s per fixation], "rate" (blinks / min over the scene), "L", "msg", "ok"}
static func compute(A0: Scene, opts: Dictionary = {}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(opts.get("seed", 1))
	var A := A0.clone()
	var D: Scene = (opts["D"] as Scene).clone() if opts.get("D") is Scene else null
	var xf: Transform3D = opts.get("xf", Transform3D.IDENTITY)
	var BA := DistanceKeeper.new_body()
	var BD := DistanceKeeper.new_body()
	var L := A.length()
	if D != null:
		L = maxf(L, D.length())
	var last := [-1.0]
	var pose := func(t: float) -> void:
		if t == float(last[0]):
			return   # posed there already
		last[0] = t
		A.apply(BA, t)
		BA.fk()
		if D != null:
			D.apply(BD, t)
			BD.fk()
	pose.call(0.0)
	var pt0: Vector3 = opts["point"] if opts.get("point") is Vector3 else LookAt.eye_point(BA) + LookAt.head_forward(BA) * 2.0
	# --- the fixation targets
	var pick := func(t: float) -> Dictionary:
		if D != null:
			var r := rng.randf()
			if r < float(PICK_2F["head"]):
				return {"kind": "head"}
			if r < float(PICK_2F["head"]) + float(PICK_2F["chest"]):
				return {"kind": "chest"}
			pose.call(t)
			var tips := DistanceKeeper.tips(BD)
			var best := ""
			var bd := INF
			for k in tips:
				var dd := (xf * (tips[k] as Vector3)).distance_to(LookAt.eye_point(BA))
				if k == "weapon":
					dd = -1.0   # a weapon in the hand is the threat to read
				if dd < bd:
					bd = dd
					best = String(k)
			return {"kind": "weapon", "tip": best}
		pose.call(t)
		var eye := LookAt.eye_point(BA)
		var to := pt0 - eye
		var dist := maxf(0.3, to.length())
		var dn := to / dist
		var side := dn.cross(Vector3.UP)
		if side.length() < 1e-4:
			side = Vector3.RIGHT
		side = side.normalized()
		var upv := side.cross(dn).normalized()
		var away := rng.randf() < AWAY_P
		var rr := deg_to_rad(rng.randf_range(AWAY_DEG.x, AWAY_DEG.y)) if away else deg_to_rad(SCATTER_DEG) * sqrt(rng.randf())
		var th := rng.randf_range(0.0, TAU)
		if away:
			th = rng.randf_range(-0.6, 0.6) + (0.0 if rng.randf() < 0.5 else PI)   # mostly sideways, as a resting glance goes
		var dir := (dn * cos(rr) + (side * cos(th) + upv * sin(th) * 0.6).normalized() * sin(rr)).normalized()
		return {"kind": "away" if away else "point", "pt": eye + dir * dist}
	var aim := func(fx: Dictionary, t: float) -> Vector2:
		pose.call(t)
		return eye_angles(BA, goal(fx, BD, xf))
	# --- saccades
	var yaw := []
	var pit := []
	var sacc := []
	var fixd := []
	var fx0: Dictionary = pick.call(0.0)
	var cur: Vector2 = _clamp(aim.call(fx0, 0.0))
	yaw.append({"t": 0.0, "v": Vector3(cur.x / Face.EYE_YAW_MAX, 0, 0), "gen": TAG})
	pit.append({"t": 0.0, "v": Vector3(cur.y / Face.EYE_PITCH_MAX, 0, 0), "gen": TAG})
	var t := 0.0
	var fix_start := 0.0
	while true:
		t += rng.randf_range(FIX_MIN, FIX_MAX)
		if t >= L:
			break
		var fx: Dictionary = pick.call(t)
		for tries in REPICK:   # a target the eyes cannot reach without a head turn is passed over for one they can (if any)
			var a0: Vector2 = aim.call(fx, t)
			if absf(a0.x) <= Face.EYE_YAW_MAX - 2.0 and absf(a0.y) <= Face.EYE_PITCH_MAX - 2.0:
				break
			fx = pick.call(t)
		var t1 := t + MS_BASE
		var nxt: Vector2 = cur
		var amp := 0.0
		for it in 4:   # the end time depends on the amplitude, the amplitude on where the target is at the end time
			nxt = aim.call(fx, t1)
			amp = amp_of(cur, _clamp(nxt))
			t1 = t + ms_dur(amp)
		nxt = aim.call(fx, t1)
		var clamped := _clamp(nxt) != nxt
		nxt = _clamp(nxt)
		amp = amp_of(cur, nxt)
		if amp < MIN_AMP:
			continue   # already there: the fixation goes on
		if t1 > L:
			break
		fixd.append(t - fix_start)
		yaw.append({"t": t, "v": Vector3(cur.x / Face.EYE_YAW_MAX, 0, 0), "gen": TAG})
		pit.append({"t": t, "v": Vector3(cur.y / Face.EYE_PITCH_MAX, 0, 0), "gen": TAG})
		yaw.append({"t": t1, "v": Vector3(nxt.x / Face.EYE_YAW_MAX, 0, 0), "gen": TAG})
		pit.append({"t": t1, "v": Vector3(nxt.y / Face.EYE_PITCH_MAX, 0, 0), "gen": TAG})
		pose.call(t1)
		sacc.append({"t0": t, "t1": t1, "dur": t1 - t, "amp": amp, "kind": fx["kind"], "pt": goal(fx, BD, xf), "clamped": clamped, "from": cur, "to": nxt})
		cur = nxt
		t = t1
		fix_start = t1
	# --- blinks: the hits, then one per slot
	var hits := []
	var ts := A.times()
	for i in A.cards.size():
		if Face.suggest(String(A.cards[i].get("name", ""))) == "pain":
			hits.append(float(ts[i][0]))
	if D != null:
		var td := D.times()
		for i in BeatFight.contacts(D):
			hits.append(float(td[i][1]))
	hits.sort()
	var starts := []   # [t0, why]
	for h in hits:
		var tb: float = float(h) + REFLEX_LAT
		if tb < L - 0.25 and (starts.is_empty() or tb - float(starts[-1][0]) >= MIN_GAP):
			starts.append([tb, "hit"])
	var s := 0.0
	var n_slot := 0
	var n_made := 0
	while true:   # the rest slots: a blink with each large gaze shift (P_COUPLE of them), then a jittered one if the count is behind the slots
		var ex: Dictionary = A.expr_at(s)
		var eff := maxf(float(ex.get("effort", 0.0)), float(ex.get("pain", 0.0)))
		var ls := 60.0 / (REST_RATE * (1.0 + EFFORT_K * clampf(eff, 0.0, 1.0)))
		if s + ls > L + 1e-6:
			break
		n_slot += 1
		var tries := []
		for sc in sacc:
			var t0 := float(sc["t0"])
			if t0 >= s and t0 < s + ls and float(sc["amp"]) >= LARGE_DEG and rng.randf() < P_COUPLE:
				tries.append([t0, "gaze"])
		if n_made + tries.size() < n_slot:
			tries.append([s + ls * rng.randf_range(0.2, 0.8), "rest"])
		s += ls
		for e2 in tries:
			var clash := false
			for e in starts:
				clash = clash or absf(float(e[0]) - float(e2[0])) < MIN_GAP
			if not clash and float(e2[0]) < L - 0.25:
				starts.append(e2)
				n_made += 1
	starts.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var bk := []
	var blinks := []
	for e in starts:
		var t0 := float(e[0])
		var c := rng.randf_range(CLOSE_MIN, CLOSE_MAX)
		var hd := rng.randf_range(0.0, HOLD_MAX)
		var o := c * rng.randf_range(OPEN_K.x, OPEN_K.y)
		blinks.append({"t0": t0, "close": c, "hold": hd, "open": o, "dur": c + hd + o, "why": e[1]})
		bk.append({"t": t0, "v": Vector3.ZERO, "gen": TAG})
		bk.append({"t": t0 + c, "v": Vector3(1, 0, 0), "gen": TAG})
		if hd >= 0.002:
			bk.append({"t": t0 + c + hd, "v": Vector3(1, 0, 0), "gen": TAG})
		bk.append({"t": t0 + c + hd + o, "v": Vector3.ZERO, "gen": TAG})
	if bk.is_empty():
		bk.append({"t": 0.0, "v": Vector3.ZERO, "gen": TAG})
	var rate := float(blinks.size()) / maxf(L, 1e-6) * 60.0
	var n_g := 0
	for b in blinks:
		if b["why"] == "gaze":
			n_g += 1
	return {"ok": L > 0.0, "L": L, "keys": {"eye_yaw": yaw, "eye_pitch": pit, "blink": bk}, "sacc": sacc, "blinks": blinks, "fix": fixd, "rate": rate,
		"two": D != null, "seed": int(opts.get("seed", 1)),
		"msg": "%d saccade%s, %d blink%s (%.1f / min; %d with a large gaze shift, %d after a hit) over %.1f s" % [sacc.size(), "" if sacc.size() == 1 else "s",
			blinks.size(), "" if blinks.size() == 1 else "s", rate, n_g, hits.size(), L]}


## how many keys of the face would the plan replace that are NOT the generator's (the user's own eye / blink keys)
static func displaced(face: Dictionary) -> int:
	var n := 0
	for ch in CHANNELS:
		for k in face.get(ch, []):
			if String((k as Dictionary).get("gen", "")) != TAG:
				n += 1
	return n


## write the plan into a face dict: the three channels become the plan's keys (each tagged); every other channel as it was
static func write(face: Dictionary, plan: Dictionary) -> void:
	for ch in CHANNELS:
		face[ch] = (plan["keys"][ch] as Array).duplicate(true)


## a copy of face with the plan in (the preview)
static func applied(face: Dictionary, plan: Dictionary) -> Dictionary:
	var f := face.duplicate(true)
	write(f, plan)
	return f


## REMOVE BY TAG: every key with "gen" == TAG goes; a channel left empty goes. Returns how many keys went.
static func remove(face: Dictionary) -> int:
	var n := 0
	for ch in face.keys():
		var ks: Array = face[ch]
		for i in range(ks.size() - 1, -1, -1):
			if String((ks[i] as Dictionary).get("gen", "")) == TAG:
				ks.remove_at(i)
				n += 1
		if ks.is_empty():
			face.erase(ch)
	return n


## how many tagged keys a face holds
static func count(face: Dictionary) -> int:
	var n := 0
	for ch in face:
		for k in face[ch]:
			if String((k as Dictionary).get("gen", "")) == TAG:
				n += 1
	return n
