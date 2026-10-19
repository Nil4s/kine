## style_transfer.gd - STYLE TRANSFER (ROADMAP 25, top-25 #12; docs/research/STYLES.md has every number and its source).
## "Make this walk older / tired / heavy / angry": NO learned model. A style is a set of measurable changes to a scene
## FILE (the same dict Scene.mirror_file works on), returned as a NEW file dict; the caller saves it into scenes/_wip.
##   1 TIMING: each card's move and hold are scaled (a longer move = a slower peak speed; a longer hold = a longer contact).
##   2 EASE: a card's ease preset (EASE PRESETS, Scene._ease): "linear" has the lowest peak speed for a given move time,
##     "in" accelerates into the card and stops sharply (a higher peak acceleration).
##   3 POSTURE: one ADDITIVE layer over the cards (Scene.layers, NA1): joint -> offset in degrees, scaled by intensity.
## ANGRY is capped by the Check: the moves are shortened only as far as Rulebook.check allows (no new FAIL against the
## source), so the peak acceleration rises as much as the rules permit (see _angry_cap).
## Intensity 0..100 (%). At 0 the file comes back unchanged (the same dictionary, byte for byte once saved).
class_name StyleTransfer
extends RefCounted

const STYLES := ["older", "tired", "heavy", "angry"]
const FPS := 60.0

# OLDER: a 70+ walker's comfortable speed (Bohannon & Andrews 2011, the 70s-80s strata: ~0.9-1.1 m/s). The style only
# slows a walk that is FASTER than OLDER_SPEED; a walk already in the band keeps its time (walk_bat: 0.95 m/s).
const OLDER_SPEED := 1.0           # m/s the older walk's speed is brought down to (never up)
# OLDER trunk flexion at 100 %, degrees added to the spine (positive = forward; the sign checked on the rig): MINE, the
# size of the change is a choice. The DIRECTION is cited (more forward trunk flexion in older adults: STYLES.md).
# Measured as the spine's own flexion relative to the pelvis (StyleTransfer.measure "flex"), which is what is commanded.
const OLDER_TRUNK := {"spine_01": 2.0, "spine_02": 2.0, "spine_03": 1.0}
# TIRED (fatigue gait studies: STYLES.md): slower moves and longer holds, the head and shoulders droop
const TIRED_TIME := 0.5            # the move AND the hold are this much longer at 100 % (x 1.5); MINE
const TIRED_POSTURE := {"neck_01": 6.0, "clavicle_l": -3.0, "clavicle_r": -3.0, "spine_01": 3.0, "spine_02": 3.0}   # MINE
# HEAVY (a load on the body: STYLES.md, carried-load gait studies): a wider stance, longer contacts, more knee bend
const HEAVY_MOVE := 0.3            # the moves are this much longer at 100 % (x 1.3), slower acceleration; MINE
const HEAVY_HOLD := 0.5            # the holds (contacts) are this much longer at 100 % (x 1.5); MINE
const HEAVY_POSTURE := {"calf_l": 6.0, "calf_r": 6.0, "thigh_l": Vector3(0, 0, 4.0), "thigh_r": Vector3(0, 0, -4.0)}   # MINE
# ANGRY (Montepare, Goldstein & Clausen 1987; Roether et al. 2009: STYLES.md): faster, a sharp stop, shoulders up,
# forward lean. The moves are shorter at 100 % (x 0.6) at most; the ease is "in" (accelerate, then a hard stop) when the
# Check allows it, "smooth" otherwise. MINE on sizes.
const ANGRY_MOVE := 0.4            # the moves are this much shorter at 100 % (x 0.6) at most, then capped by the Check; MINE
const ANGRY_POSTURE := {"clavicle_l": 5.0, "clavicle_r": 5.0, "spine_01": 3.0}   # shoulders raised, forward lean; MINE
const ANGRY_SEARCH := 6            # bisection steps between the most a move may shorten and no change at all


## the measures of a scene (its file dict or a Scene): the WALK = the walking cards (all but the first and the last).
## {"speed" m/s (pelvis path over the walk, floor plane), "flex" deg (the spine's own forward flexion relative to the
##  pelvis, the walk's mean minus rest: the commanded trunk angle), "lean" deg (the pelvis-to-head vector, for the eye:
##  it reads less than the flexion, since the spine's hinge is above the pelvis), "hand_v" m/s (peak hand speed),
##  "hand_a" m/s2 (peak hand acceleration), "t0", "t1" (the walk's span)}
static func measure(S: Scene) -> Dictionary:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var R := Body.new()
	R.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	R.fk()
	var rest_lean := _lean(R)
	var rest_flex := _flex(R)
	var ts := S.times()
	var k := ts.size()
	var t0: float = ts[1][0] if k > 2 else 0.0
	var t1: float = ts[k - 2][2] if k > 2 else S.length()
	var n := int(ceil((t1 - t0) * FPS)) + 1
	var path := 0.0
	var prev := Vector3.ZERO
	var lean := 0.0
	var flex := 0.0
	var hv := 0.0
	var ha := 0.0
	var hands := []
	for i in n:
		S.apply(B, minf(t0 + i / FPS, S.length()))
		var p: Vector3 = B.P["pelvis"]
		if i > 0:
			path += Vector2(p.x - prev.x, p.z - prev.z).length()
		prev = p
		lean += _lean(B) - rest_lean
		flex += _flex(B) - rest_flex
		hands.append([B.E["hand_l"], B.E["hand_r"]])
	for i in range(1, n):
		for h in 2:
			hv = maxf(hv, ((hands[i][h] as Vector3) - (hands[i - 1][h] as Vector3)).length() * FPS)
	for i in range(1, n - 1):
		for h in 2:
			var a1: Vector3 = ((hands[i + 1][h] as Vector3) - (hands[i][h] as Vector3)) * FPS
			var a0: Vector3 = ((hands[i][h] as Vector3) - (hands[i - 1][h] as Vector3)) * FPS
			ha = maxf(ha, ((a1 - a0) * FPS).length())
	var dur := maxf(t1 - t0, 1e-6)
	return {"speed": path / dur, "flex": flex / n, "lean": lean / n, "hand_v": hv, "hand_a": ha, "t0": t0, "t1": t1}


## trunk forward angle (deg): the pelvis to the head, in the side view (+z = forward, as the rig's spine flexion)
static func _lean(B: Body) -> float:
	var v: Vector3 = (B.P["head"] as Vector3) - (B.P["pelvis"] as Vector3)
	return rad_to_deg(atan2(v.z, v.y))


## the spine's forward flexion relative to the pelvis (deg): the x-rotation of spine_03 in the pelvis frame. The
## spine joints' x angles add up here, so it reads the commanded offset (the layer's spine_01..03) as it is.
static func _flex(B: Body) -> float:
	var rel: Quaternion = (B.G["pelvis"] as Quaternion).inverse() * (B.G["spine_03"] as Quaternion)
	return rad_to_deg(2.0 * atan2(rel.x, rel.w))


## the style applied to a scene FILE dict: returns a NEW file dict (the input is not changed). Intensity in % (0..100).
## Style names: "older", "tired", "heavy", "angry". Unknown style or 0 %: the input, copied unchanged.
static func make(d: Dictionary, style: String, intensity: float) -> Dictionary:
	var I := clampf(intensity, 0.0, 100.0) / 100.0
	if I <= 0.0 or not style in STYLES:
		return d.duplicate(true)
	var src := Scene.new()
	src.from_dict(d)
	var plan := _plan(src, style, I)
	if style == "angry":
		plan = _angry_cap(d, src, plan, I, intensity)
	return _emit(d, src, plan, style, intensity)


## the plan of a style at fraction I: f_move (each move x), f_hold (each hold x), ease ("" = as the file has it), posture
static func _plan(src: Scene, style: String, I: float) -> Dictionary:
	var p := {"f_move": 1.0, "f_hold": 1.0, "ease": "", "posture": {}}
	match style:
		"older":
			# slow the walk only when it is faster than the older speed (time x full, interpolated by intensity)
			var v := measure(src)["speed"] as float
			var full := maxf(1.0, v / OLDER_SPEED)
			p["f_move"] = 1.0 + (full - 1.0) * I
			p["f_hold"] = p["f_move"]
			for j in OLDER_TRUNK:
				p["posture"][j] = Vector3(OLDER_TRUNK[j] * I, 0, 0)
		"tired":
			p["f_move"] = 1.0 + TIRED_TIME * I
			p["f_hold"] = p["f_move"]
			p["ease"] = "linear"
			for j in TIRED_POSTURE:
				p["posture"][j] = Vector3(TIRED_POSTURE[j] * I, 0, 0)
		"heavy":
			p["f_move"] = 1.0 + HEAVY_MOVE * I
			p["f_hold"] = 1.0 + HEAVY_HOLD * I
			for j in HEAVY_POSTURE:
				var v3 = HEAVY_POSTURE[j]
				p["posture"][j] = (Vector3(float(v3) * I, 0, 0) if v3 is float else (v3 as Vector3) * I)
		"angry":
			p["f_move"] = 1.0 - ANGRY_MOVE * I
			p["ease"] = "in"
			for j in ANGRY_POSTURE:
				p["posture"][j] = Vector3(ANGRY_POSTURE[j] * I, 0, 0)
	return p


## the ANGRY plan, capped by the Check: the most a move may shorten, the ease "in" first and "smooth" if "in" cannot pass
## at any speed-up. A plan passes when its Check FAIL count is no higher than the source's. Bisection between the no
## change move (x 1) and the requested one (x 1 - ANGRY_MOVE I); the shortest move that passes is kept.
static func _angry_cap(d: Dictionary, src: Scene, want: Dictionary, I: float, pct: float) -> Dictionary:
	var base := _fails(d)
	var lo: float = want["f_move"]
	for ease in [want["ease"], "smooth"]:
		var p: Dictionary = want.duplicate(true)
		p["ease"] = ease
		p["f_move"] = lo
		if _fails(_emit(d, src, p, "angry", pct)) <= base:
			return p
		p["f_move"] = 1.0
		if _fails(_emit(d, src, p, "angry", pct)) > base:
			continue   # this ease fails the Check even at no speed-up: try the next one
		var a := lo
		var b := 1.0
		var best: Dictionary = p.duplicate(true)
		for _k in ANGRY_SEARCH:
			var m := (a + b) * 0.5
			var q: Dictionary = p.duplicate(true)
			q["f_move"] = m
			if _fails(_emit(d, src, q, "angry", pct)) <= base:
				b = m
				best = q
			else:
				a = m
		return best
	var z: Dictionary = want.duplicate(true)   # neither ease passes: the posture alone, no retiming
	z["f_move"] = 1.0
	z["ease"] = "smooth"
	return z


## the number of Check FAIL findings of a scene file (the Check, Rulebook.check, as the panel counts MUST FIX)
static func _fails(d: Dictionary) -> int:
	var S := Scene.new()
	S.from_dict(d)
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	return Rulebook.check(S, B).filter(func(f): return f["sev"] == "FAIL").size()


## the file built from a plan: timing, ease and the posture layer, then the scene as the file writes it
static func _emit(d: Dictionary, src: Scene, p: Dictionary, style: String, pct: float) -> Dictionary:
	var out: Dictionary = d.duplicate(true)
	var n := (out["cards"] as Array).size()
	# 1 TIMING: each card's resolved move (Scene.move_time: a move of -1 is worked out) and its hold, scaled
	for i in n:
		var c: Dictionary = out["cards"][i]
		if i >= 1:
			c["move"] = snappedf(src.move_time(i) * float(p["f_move"]), 0.001)
			if String(p["ease"]) != "":
				c["ease"] = p["ease"]
		if not c.get("flow", false):
			c["hold"] = snappedf(float(c["hold"]) * float(p["f_hold"]), 0.001)
	# 3 POSTURE: one additive layer over the cards, named for the style (Scene.layer_from_file shape)
	var posture: Dictionary = p["posture"]
	if not posture.is_empty():
		var v := {}
		for j in posture:
			var x: Vector3 = posture[j]
			v[j] = [snappedf(x.x, 0.01), snappedf(x.y, 0.01), snappedf(x.z, 0.01)]
		var layers: Array = out.get("layers", [])
		layers.append({"name": "style: %s %d%%" % [style, int(round(pct))], "mode": "add", "w": 1.0, "v": v})
		out["layers"] = layers
	out["scene"] = "%s_%s" % [String(d.get("scene", "scene")), style]
	out["plan"] = "Style transfer (%s, %d%%) from %s: StyleTransfer.make; numbers in docs/research/STYLES.md" % [style, int(round(pct)), String(d.get("scene", "scene"))]
	# the file as the scene writes it (arrive/leave times, bad_frames recomputed on the new motion)
	var S2 := Scene.new()
	S2.from_dict(out)
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	return S2.to_dict(B)
