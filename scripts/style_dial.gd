## style_dial.gd - STYLE DIAL (ROADMAP I6): four sliders, "heavier / tired / angry / sneaky", each -1..+1, that change a WHOLE clip.
## LEARNED, NOT HAND-WRITTEN: the SIZE of every change is measured on Nick's own clips; only the DIRECTION of a style comes from
## published findings. Nothing here is an invented constant of "how much".
##   MEASURED (SPREAD, below; tools/style_spread.gd prints it, tests/i6_test.gd re-measures and fails when it drifts):
##     "move"  P90 of |ln(clip median move time / median over clips)| over the explicit move times in Nick's cards (the R27 habits index, NextPose.read_file)
##     "hold"  the same for his holds
##     "amp"   P90 of |ln(range / median)| over his clips; range = mean over the body's joints of the p95-p5 spread of the
##             angle (deg), read from the motion database (MotionMatch.build: scenes/ and moves/, played at the clip's fps)
##     "flex"  P90 of |spine flexion - median| (deg; the three spine joints' bend summed, clip mean)
##     "head"  P90 of |head height - median| (m, clip mean, floor to the head joint)
##   +1 on a slider = SPREAD x the style's weight for that feature (DIR). A weight is -1, -0.5, 0, 0.5 or 1: it carries the SIGN
##   and the RANK of the effect found in the literature, never a size. So "+1 tired" lengthens his moves by the amount his own
##   clips differ from each other at the 90th percentile.
## DIRECTIONS (what each style does to timing / amplitude / posture), and where it comes from:
##   tired    slower, smaller, flexed trunk, lower head, longer rests. Pollick, Paterson, Bruderlin & Sanford 2001, Cognition
##            82:B51-B61 ("Perceiving affect from arm movement": sad = slow and small, arousal is carried by velocity);
##            Montepare, Goldstein & Clausen 1987, J Nonverbal Behav 11:33-42 (sad gait: slow, short; slumped trunk);
##            Roether, Omlor, Christensen & Giese 2009, Curr Biol 19:R464 (sad: smaller arm swing, head and torso inclined).
##   angry    faster, larger, shorter rests. Pollick 2001 (angry: fastest, largest, most jerk); Montepare 1987 (angry gait:
##            heavy, fast); Roether 2009 (anger: larger elbow flexion amplitude).
##   heavier  longer anticipation, slower recovery, deeper knee bend, slower overall. Runeson & Frykholm 1981, J Exp Psych HPP
##            7:733-740 (a lifted weight is seen from the lifter's kinematics: slower, lower stance); Laban & Lawrence 1947,
##            "Effort" (Weight: strong = heavy, accelerates slowly); Thomas & Johnston 1981, "The Illusion of Life" (weight =
##            longer anticipation and settle); Cross & Bower 2006 (inertia slows a swing; weight_feel.gd).
##   sneaky   sustained, small, low, with freezes. Laban & Lawrence 1947 and Chi, Costa, Zhao & Badler 2000, SIGGRAPH "The EMOTE
##            model for effort and shape" (Time = sustained, Weight = light, Flow = bound: restrained, stop-and-go). The crouch
##            (head lower) and the hunch are OURS (sign only): no motion study of sneaking was found that gives them.
## APPLY (scripts/style_dial.gd style_cards): retime the moves and holds, scale every body joint's deviation from the clip's mean pose,
## add trunk flexion, lower the head with the legs (knees deeper) -- then KEEP what must not move: a planted foot's ankle and ball
## stay at their original world place and a strike card's contact point (weapon tip, else the striking hand) stays where it was
## (damped least squares on the legs / the arm, scripts/style_dial.gd _dls; checked against the full Scene.apply).
## Read only: style_cards() returns new cards; the caller (style_dial_ui.gd) writes them as ONE undo step.
class_name StyleDial
extends RefCounted

static var DEBUG := false
const STYLES := ["heavier", "tired", "angry", "sneaky"]
const FEATS := ["move", "hold", "amp", "flex", "head"]

## MEASURED on this machine's scenes/ + moves/ (tools/style_spread.gd). tests/i6_test.gd re-measures and compares (5 %).
const SPREAD := {"move": 1.1866, "hold": 0.5596, "amp": 0.7789, "flex": 13.7012, "head": 0.0362}
const BASIS := {"clips": 11}   # the clips the spreads rest on (scenes/ with explicit move times)

## weights: dur (+ = longer moves), hold (+ = longer holds), amp (+ = bigger), flex (+ = trunk more forward), head (+ = head higher),
## ant / rec (+ = the wind-up moves / the recovery moves longer, on top of dur)
const DIR := {
	"heavier": {"dur": 0.5, "hold": 0.5, "amp": 0.0, "flex": 0.0, "head": -0.5, "ant": 1.0, "rec": 1.0},
	"tired": {"dur": 1.0, "hold": 1.0, "amp": -1.0, "flex": 1.0, "head": -1.0, "ant": 0.0, "rec": 0.0},
	"angry": {"dur": -1.0, "hold": -1.0, "amp": 1.0, "flex": 0.0, "head": 0.0, "ant": 0.0, "rec": 0.0},
	"sneaky": {"dur": 0.5, "hold": 0.5, "amp": -0.5, "flex": 0.5, "head": -1.0, "ant": 0.5, "rec": 0.0},
}
const SPINE_SPLIT := {"spine_01": 0.3, "spine_02": 0.3, "spine_03": 0.4}
const BODY_N := 22          # Body.ORDER[0..21] are the body's joints; the rest are fingers and toes
const STILL := 8.0          # deg/s: a frame slower than this is a hold
const PLANT_Y := 0.04       # m: a ball of the foot this near the floor is planted
const MIN_MOVE := 0.04
const FACTOR_MIN := 0.4
const FACTOR_MAX := 2.5
const DROP_MAX := 0.30      # m: the head goes no lower than this under the style (a crouch, not a fall)


# ---- the sliders -> weights ------------------------------------------------------------------------------------------

static func neutral() -> Dictionary:
	return {"heavier": 0.0, "tired": 0.0, "angry": 0.0, "sneaky": 0.0}


static func is_neutral(v: Dictionary) -> bool:
	for s in STYLES:
		if absf(float(v.get(s, 0.0))) > 1e-6:
			return false
	return true


## the summed weight of every feature for slider values v
static func weights(v: Dictionary) -> Dictionary:
	var w := {"dur": 0.0, "hold": 0.0, "amp": 0.0, "flex": 0.0, "head": 0.0, "ant": 0.0, "rec": 0.0}
	for s in STYLES:
		var x := clampf(float(v.get(s, 0.0)), -1.0, 1.0)
		for k in w:
			w[k] += x * float((DIR[s] as Dictionary)[k])
	return w


## the shift each feature gets at slider values v, in its own unit (ln time, ln amplitude, deg, m): weight x measured spread
static func shifts(v: Dictionary, spread := SPREAD) -> Dictionary:
	var w := weights(v)
	return {"dur": float(w["dur"]) * float(spread["move"]), "hold": float(w["hold"]) * float(spread["hold"]),
		"amp": float(w["amp"]) * float(spread["amp"]), "flex": float(w["flex"]) * float(spread["flex"]),
		"head": float(w["head"]) * float(spread["head"]), "ant": float(w["ant"]) * float(spread["move"]),
		"rec": float(w["rec"]) * float(spread["move"])}


# ---- measuring (the learned part) -------------------------------------------------------------------------------------

static func _pct(xs: Array, p: float) -> float:
	if xs.is_empty():
		return 0.0
	var a := xs.duplicate()
	a.sort()
	var f := p * float(a.size() - 1)
	var i := int(floor(f))
	var j := mini(i + 1, a.size() - 1)
	return lerpf(float(a[i]), float(a[j]), f - float(i))


## the style features of one clip of the motion database (MotionMatch.build: {"ang", "hip", "n", "fps", "first"...}); B is a scratch Body
static func clip_features(db: Dictionary, ci: int, B: Body) -> Dictionary:
	var c: Dictionary = db["clips"][ci]
	var nj: int = Body.ORDER.size()
	var ang: PackedVector3Array = db["ang"]
	var off: PackedVector3Array = db["off"]
	var n: int = c["n"]
	var first: int = c["first"]
	var fps: float = c["fps"]
	var oi := {}
	for i in nj:
		oi[Body.ORDER[i]] = i
	var speed := []
	var flex := 0.0
	var head := 0.0
	var com := 0.0
	var knee := 0.0
	var cols := []   # per body joint, per axis: the values over the clip
	for j in BODY_N:
		cols.append([[], [], []])
	for f in n:
		var base := (first + f) * nj
		if f > 0:
			var s := 0.0
			for j in BODY_N:
				s += (ang[base + j] - ang[base - nj + j]).length() * fps
			speed.append(s / float(BODY_N))
		for j in BODY_N:
			var a: Vector3 = ang[base + j]
			(cols[j][0] as Array).append(a.x)
			(cols[j][1] as Array).append(a.y)
			(cols[j][2] as Array).append(a.z)
		flex += (ang[base + int(oi["spine_01"])].x + ang[base + int(oi["spine_02"])].x + ang[base + int(oi["spine_03"])].x)
		knee += (ang[base + int(oi["calf_l"])].x + ang[base + int(oi["calf_r"])].x) * 0.5
		for j in Body.ORDER:
			B.ang[j] = ang[base + int(oi[j])]
		B.offset = off[first + f]
		B.fk()
		head += (B.P["head"] as Vector3).y
		com += (B.P["pelvis"] as Vector3).y
	var mean_s := 0.0
	var still := 0
	for s in speed:
		mean_s += float(s)
		if float(s) < STILL:
			still += 1
	mean_s /= maxf(1.0, float(speed.size()))
	var rng := 0.0
	for j in BODY_N:
		var m := 0.0
		for k in 3:
			m = maxf(m, _pct(cols[j][k], 0.95) - _pct(cols[j][k], 0.05))
		rng += m
	rng /= float(BODY_N)
	return {"name": String(c["name"]), "speed": mean_s, "still": float(still) / maxf(1.0, float(speed.size())),
		"sharp": _pct(speed, 0.95) / maxf(mean_s, 1e-6), "range": rng, "flex": flex / float(n), "head_h": head / float(n),
		"com_h": com / float(n), "knee": knee / float(n), "n": n}


## the SPREAD table from the motion database and the habits index: {"spread": {...}, "basis": {...}, "clips": [features per clip]}
static func measure_spreads(db: Dictionary, dirs := ["res://scenes/"]) -> Dictionary:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var clips := []
	for ci in (db["clips"] as Array).size():
		clips.append(clip_features(db, ci, B))
	var mv := []
	var hd := []
	for dir in dirs:
		for fn in DirAccess.get_files_at(dir):
			if not fn.ends_with(".json"):
				continue
			var m1 := []
			var h1 := []
			for card in NextPose.read_file(String(dir) + fn):
				if float(card["mv"]) > 0.0:
					m1.append(float(card["mv"]))
				if float(card["hd"]) > 0.0:
					h1.append(float(card["hd"]))
			if not m1.is_empty():
				mv.append(_pct(m1, 0.5))   # one number per clip: its median explicit move time
			if not h1.is_empty():
				hd.append(_pct(h1, 0.5))
	var spread := {"move": _log_p90(mv), "hold": _log_p90(hd), "amp": _log_p90(clips.map(func(x): return x["range"])),
		"flex": _abs_p90(clips.map(func(x): return x["flex"])), "head": _abs_p90(clips.map(func(x): return x["head_h"]))}
	return {"spread": spread, "basis": {"clips": clips.size(), "clips_with_moves": mv.size(), "clips_with_holds": hd.size()}, "clips": clips}


static func _log_p90(xs: Array) -> float:
	if xs.size() < 2:
		return 0.0
	var med := _pct(xs, 0.5)
	return _pct(xs.map(func(x): return absf(log(float(x) / med))), 0.9)


static func _abs_p90(xs: Array) -> float:
	if xs.size() < 2:
		return 0.0
	var med := _pct(xs, 0.5)
	return _pct(xs.map(func(x): return absf(float(x) - med)), 0.9)


## the features of a scene as it PLAYS (MotionMatch's own clip reader, then clip_features): what a slider is judged by
static func scene_features(S: Scene, B: Body) -> Dictionary:
	var c := MotionMatch._clip(S, B, String(S.name), "")
	var db := MotionMatch._pack([c])
	var T := Body.new()
	T.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	return clip_features(db, 0, T)


## peak hand speed (m/s) and the largest hand travel from its clip mean (m) of a scene as it plays, 60 Hz
static func hand_stats(S: Scene, B: Body) -> Dictionary:
	var L := S.length()
	var n := int(ceil(L * 60.0)) + 1
	var prev := {}
	var peak := 0.0
	var pts := {"hand_l": [], "hand_r": []}
	for i in n:
		S.apply(B, minf(float(i) / 60.0, L))
		for h in ["hand_l", "hand_r"]:
			var p: Vector3 = B.E[h]
			if prev.has(h):
				peak = maxf(peak, (p - (prev[h] as Vector3)).length() * 60.0)
			prev[h] = p
			(pts[h] as Array).append(p)
	var rng := 0.0
	for h in pts:
		var mean := Vector3.ZERO
		for p in pts[h]:
			mean += p
		mean /= float((pts[h] as Array).size())
		for p in pts[h]:
			rng = maxf(rng, (p - mean).length())
	return {"peak": peak, "reach": rng}


# ---- applying ---------------------------------------------------------------------------------------------------------

static func _place(W: Scene, B: Body, flat: Dictionary) -> void:
	Scene.put(B, flat)
	if W.on_floor:
		W._ground(B)


static func _dup_flat(f: Dictionary) -> Dictionary:
	var a := {}
	for j in f["ang"]:
		a[j] = f["ang"][j]
	return {"offset": f["offset"], "ang": a, "weapon": f["weapon"], "weapon2": f["weapon2"]}


## a pose with the joints' angles replaced (the A/G/pos fields are stale until _pose_of rebuilds them)
static func _pose_with(pose: Dictionary, ang: Dictionary) -> Dictionary:
	var p := pose.duplicate(false)
	var js: Dictionary = (pose["joints"] as Dictionary).duplicate(false)
	for j in ang:
		if js.has(j):
			var x: Dictionary = (js[j] as Dictionary).duplicate(false)
			var a: Vector3 = ang[j]
			x["bend"] = a.x
			x["side"] = a.y
			x["twist"] = a.z
			js[j] = x
	p["joints"] = js
	return p


## the card's pose rebuilt from a flat pose: every derived field (rotations, positions, weapon, contacts) recomputed
static func _pose_of(B: Body, flat: Dictionary) -> Dictionary:
	Scene.put(B, flat)
	return B.to_dict()


static func _solve(A: Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var m := b.size()
	var M := []
	for i in m:
		var row: Array = (A[i] as Array).duplicate()
		row.append(b[i])
		M.append(row)
	for c in m:
		var piv := c
		for r in range(c + 1, m):
			if absf(float(M[r][c])) > absf(float(M[piv][c])):
				piv = r
		var tmp: Array = M[c]
		M[c] = M[piv]
		M[piv] = tmp
		var d: float = M[c][c]
		if absf(d) < 1e-14:
			continue
		for r in range(c + 1, m):
			var f: float = float(M[r][c]) / d
			if f == 0.0:
				continue
			for k in range(c, m + 1):
				M[r][k] = float(M[r][k]) - f * float(M[c][k])
	var x := PackedFloat64Array()
	x.resize(m)
	for i in range(m - 1, -1, -1):
		var s: float = M[i][m]
		for k in range(i + 1, m):
			s -= float(M[i][k]) * x[k]
		var d2: float = M[i][i]
		x[i] = s / d2 if absf(d2) > 1e-14 else 0.0
	return x


## damped least squares on a black box: move the angles `ang` (joint -> Vector3, edited in place, kept inside B's limits) so that
## f(ang) -> target. vars: [[joint, axis 0..2]]. Returns the largest absolute residual (m).
static func _dls(B: Body, ang: Dictionary, vars: Array, f: Callable, target: PackedFloat64Array, iters := 6, tol := 0.0012) -> float:
	var live := []
	for v in vars:
		var r: Vector2 = [B.lim[v[0]]["bend"], B.lim[v[0]]["side"], B.lim[v[0]]["twist"]][int(v[1])]
		if r.y - r.x > 0.5:
			live.append(v)
	var m := target.size()
	var cur: PackedFloat64Array = f.call(ang)
	var err := _maxabs(target, cur)
	for it in iters:
		if err <= tol or live.is_empty():
			break
		var J := []
		for v in live:
			var j: String = v[0]
			var k: int = v[1]
			var a0: Vector3 = ang[j]
			var a1 := a0
			a1[k] += 1.0
			ang[j] = a1
			var c1: PackedFloat64Array = f.call(ang)
			ang[j] = a0
			var col := PackedFloat64Array()
			col.resize(m)
			for i in m:
				col[i] = c1[i] - cur[i]
			J.append(col)
		var A := []
		for i in m:
			var row := []
			for k2 in m:
				var s := 0.0
				for c in J.size():
					s += float(J[c][i]) * float(J[c][k2])
				row.append(s + (2e-6 if i == k2 else 0.0))
			A.append(row)
		var r := PackedFloat64Array()
		r.resize(m)
		for i in m:
			r[i] = target[i] - cur[i]
		var y := _solve(A, r)
		var step := PackedFloat64Array()
		step.resize(live.size())
		var big := 0.0
		for c in live.size():
			var s2 := 0.0
			for i in m:
				s2 += float(J[c][i]) * y[i]
			step[c] = s2
			big = maxf(big, absf(s2))
		var scale := minf(1.0, 12.0 / maxf(big, 1e-9))
		var saved := ang.duplicate()
		var ok := false
		for tr in 4:
			for c in live.size():
				var j2: String = live[c][0]
				var k3: int = live[c][1]
				var a: Vector3 = (saved[j2] as Vector3)
				a[k3] += step[c] * scale
				ang[j2] = B.clamp_ang(j2, a)
			var nx: PackedFloat64Array = f.call(ang)
			var e2 := _maxabs(target, nx)
			if DEBUG:
				print("   dls it %d try %d scale %.3f big %.2f err %.4f -> %.4f" % [it, tr, scale, big, err, e2])
			if e2 < err:
				cur = nx
				err = e2
				ok = true
				break
			scale *= 0.5
			for j3 in saved:
				ang[j3] = saved[j3]
		if not ok:
			break
	return err


static func _maxabs(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var m := 0.0
	for i in a.size():
		m = maxf(m, absf(a[i] - b[i]))
	return m


static func _v3(out: PackedFloat64Array, p: Vector3) -> void:
	out.append(p.x)
	out.append(p.y)
	out.append(p.z)


## where a strike card's contact is on this body: the weapon tip, else the striking hand's end. [point, side "l"|"r"]
static func contact_point(B: Body) -> Array:
	if B.wep_on:
		return [B.wep_point(B.wep_len), "l" if String(B.wep_hand).ends_with("_l") else "r"]
	var l: Vector3 = B.E["hand_l"]
	var r: Vector3 = B.E["hand_r"]
	var p: Vector3 = B.P["pelvis"]
	return [l, "l"] if (l - p).length() >= (r - p).length() else [r, "r"]


## the cards S would have at slider values v, from `base` (the cards at slider 0). Returns {"cards", "report"}; report: {"timing", "feet_err_m",
## "tip_err_m": {card: m}, "drop_m", "contacts": [cards], "planted": n}
static func style_cards(S: Scene, B: Body, base: Array, v: Dictionary, spread := SPREAD) -> Dictionary:
	var out := {"cards": base.duplicate(true), "report": {"timing": {}, "feet_err_m": 0.0, "tip_err_m": {}, "drop_m": 0.0, "contacts": [], "planted": 0}}
	if is_neutral(v) or base.size() < 2:
		return out
	var sh := shifts(v, spread)
	var W := S.clone()
	W.cards = base.duplicate(true)
	var n := W.cards.size()
	var contacts := []
	for i in range(1, n):
		if TimingCoach.is_strike(W, i):
			contacts.append(i)
	out["report"]["contacts"] = contacts
	var ts0 := W.times()

	# full-pipeline contact points before (the 1 cm bar is judged here)
	var tip_full := {}
	for i in contacts:
		W.apply(B, float(ts0[i][1]))
		tip_full[i] = contact_point(B)

	# model of every card before: the grounded pose (planted feet, pelvis, contact point)
	var flats := []
	var plant := []   # per card: {"l": [ankle, ball] | null, ...}
	var pel0 := PackedFloat64Array()
	var tip0 := {}
	for i in n:
		var fl := _dup_flat(W._flat_read(i))
		flats.append(fl)
		_place(W, B, fl)
		var pl := {}
		for s in ["l", "r"]:
			if (B.P["ball_" + s] as Vector3).y < PLANT_Y:
				pl[s] = [B.P["foot_" + s], B.P["ball_" + s]]
		plant.append(pl)
		pel0.append((B.P["pelvis"] as Vector3).y)
		if i in contacts:
			tip0[i] = contact_point(B)

	# 1. TIMING: the moves and holds
	var first_c: int = contacts[0] if not contacts.is_empty() else -1
	var last_c: int = contacts[-1] if not contacts.is_empty() else -1
	var mv0 := []
	for i in n:
		mv0.append(W.move_time(i))
	var tinfo := {}
	for i in range(1, n):
		var lf: float = float(sh["dur"])
		if first_c > 0 and i < first_c:
			lf += float(sh["ant"])
		elif last_c > 0 and i > last_c:
			lf += float(sh["rec"])
		var fac := clampf(exp(lf), FACTOR_MIN, FACTOR_MAX)
		if absf(fac - 1.0) > 1e-9:
			W.cards[i]["move"] = snappedf(maxf(MIN_MOVE, float(mv0[i]) * fac), 0.001)
		tinfo[i] = fac
	var hf := clampf(exp(float(sh["hold"])), FACTOR_MIN, FACTOR_MAX)
	for i in n:
		var h: float = W.cards[i]["hold"]
		if h > 0.0:
			W.cards[i]["hold"] = snappedf(h * hf, 0.001)
	out["report"]["timing"] = {"move_factor": tinfo, "hold_factor": hf}

	# 2. POSE: amplitude about the clip's mean pose, trunk flexion
	var amp := clampf(exp(float(sh["amp"])), FACTOR_MIN, FACTOR_MAX)
	var mean := {}
	for j in Body.ORDER.slice(0, BODY_N):
		if j == "pelvis" or j.begins_with("thigh") or j.begins_with("calf") or j.begins_with("foot") or j.begins_with("ball"):
			continue   # the hips and legs are held by the plant solve below; they are not scaled
		var s := Vector3.ZERO
		for i in n:
			s += (flats[i]["ang"][j] as Vector3)
		mean[j] = s / float(n)
	for i in n:
		var a: Dictionary = flats[i]["ang"]
		if absf(amp - 1.0) > 1e-9:
			for j in mean:
				a[j] = B.clamp_ang(j, (mean[j] as Vector3) + ((a[j] as Vector3) - (mean[j] as Vector3)) * amp)
		if absf(float(sh["flex"])) > 1e-9:
			for j in SPINE_SPLIT:
				var x: Vector3 = a[j]
				x.x += float(sh["flex"]) * float(SPINE_SPLIT[j])
				a[j] = B.clamp_ang(j, x)

	# 3. HEAD / KNEES: the pelvis goes down by the head's shift, the planted feet stay where they were
	var drop := clampf(-float(sh["head"]), -DROP_MAX, DROP_MAX)
	out["report"]["drop_m"] = drop
	var feet_err := 0.0
	var feet_errs := {}
	var nplant := 0
	for i in n:
		var pl: Dictionary = plant[i]
		var a: Dictionary = flats[i]["ang"]
		if pl.is_empty():
			continue
		nplant += pl.size()
		var a0: Dictionary = a.duplicate()
		var e := INF
		var best_a: Dictionary = a
		for fac in [1.0, 0.6, 0.3, 0.0]:
			var drop_i: float = drop * float(fac)
			a = a0.duplicate()
			var vars := []
			var tgt := PackedFloat64Array()
			for s in pl:
				for jn in ["thigh_", "calf_", "foot_"]:
					for k in 3:
						vars.append([jn + s, k])
				_v3(tgt, pl[s][0])
				_v3(tgt, pl[s][1])
			var use_pel: bool = absf(drop_i) > 1e-4
			if use_pel:
				tgt.append(pel0[i] - drop_i)
			var fl: Dictionary = flats[i]
			var sides: Array = pl.keys()
			var f := func(ang: Dictionary) -> PackedFloat64Array:
				var g := {"offset": fl["offset"], "ang": ang, "weapon": fl["weapon"], "weapon2": fl["weapon2"]}
				_place(W, B, g)
				var o := PackedFloat64Array()
				for s in sides:
					_v3(o, B.P["foot_" + s])
					_v3(o, B.P["ball_" + s])
				if use_pel:
					o.append((B.P["pelvis"] as Vector3).y)
				return o
			# a straight leg has no first-order way to get shorter (cos is flat at 0): seed the squat (hip flexes d, knee 2d, ankle
			# takes the difference) from the leg's length, then let the least squares finish the job
			if use_pel and drop_i > 0.0:
				_place(W, B, {"offset": fl["offset"], "ang": a, "weapon": fl["weapon"], "weapon2": fl["weapon2"]})
				var seeds := {}
				for sd in sides:
					var hip: Vector3 = B.P["thigh_" + sd]
					var knee: Vector3 = B.P["calf_" + sd]
					var ank: Vector3 = B.P["foot_" + sd]
					var ltot := hip.distance_to(knee) + knee.distance_to(ank)
					var dist := hip.distance_to(ank)
					var th0 := acos(clampf(dist / ltot, 0.0, 1.0))
					var th1 := acos(clampf((dist - drop_i) / ltot, 0.0, 1.0))
					seeds[sd] = rad_to_deg(th1 - th0)
				var best_k := 1.0
				var best_e := INF
				for kk in [1.0, -1.0]:
					var tr := a.duplicate()
					for sd in sides:
						var d: float = seeds[sd]
						tr["thigh_" + sd] = B.clamp_ang("thigh_" + sd, (tr["thigh_" + sd] as Vector3) + Vector3(d, 0, 0))
						tr["calf_" + sd] = B.clamp_ang("calf_" + sd, (tr["calf_" + sd] as Vector3) + Vector3(2.0 * d, 0, 0))
						tr["foot_" + sd] = B.clamp_ang("foot_" + sd, (tr["foot_" + sd] as Vector3) + Vector3(kk * d, 0, 0))
					var c: PackedFloat64Array = f.call(tr)
					var ee := _maxabs(tgt, c)
					if ee < best_e:
						best_e = ee
						best_k = kk
				for sd in sides:
					var d2: float = seeds[sd]
					a["thigh_" + sd] = B.clamp_ang("thigh_" + sd, (a["thigh_" + sd] as Vector3) + Vector3(d2, 0, 0))
					a["calf_" + sd] = B.clamp_ang("calf_" + sd, (a["calf_" + sd] as Vector3) + Vector3(2.0 * d2, 0, 0))
					a["foot_" + sd] = B.clamp_ang("foot_" + sd, (a["foot_" + sd] as Vector3) + Vector3(best_k * d2, 0, 0))
			var e_try := _dls(B, a, vars, f, tgt, 10)
			if DEBUG and e_try > 0.03:
				var cc: PackedFloat64Array = f.call(a)
				var dd := []
				for q in cc.size():
					dd.append(snappedf(cc[q] - tgt[q], 0.001))
				print("   card %d sides %s err %.3f resid %s  thigh %s calf %s" % [i, sides, e_try, dd, [a.get("thigh_l"), a.get("thigh_r")], [a.get("calf_l"), a.get("calf_r")]])
			if e_try < e:
				e = e_try
				best_a = a.duplicate()
			if e_try <= 0.01:
				break
		a = best_a
		for jj in best_a:
			(flats[i]["ang"] as Dictionary)[jj] = best_a[jj]
		feet_errs[i] = e
		feet_err = maxf(feet_err, e)
	out["report"]["feet_err_m"] = feet_err
	out["report"]["planted"] = nplant
	out["report"]["feet_errs"] = feet_errs

	# 4. CONTACT: the strike's point goes back where it was (model), then (full pipeline) the last millimetres
	for i in contacts:
		var a: Dictionary = flats[i]["ang"]
		var side: String = tip0[i][1]
		var vars := []
		for jn in ["clavicle_", "upperarm_", "lowerarm_"]:
			for k in 3:
				vars.append([jn + side, k])
		var tgt := PackedFloat64Array()
		_v3(tgt, tip0[i][0])
		var fl: Dictionary = flats[i]
		var f := func(ang: Dictionary) -> PackedFloat64Array:
			var g := {"offset": fl["offset"], "ang": ang, "weapon": fl["weapon"], "weapon2": fl["weapon2"]}
			_place(W, B, g)
			var o := PackedFloat64Array()
			_v3(o, contact_point(B)[0])
			return o
		# from the styled arm; when that cannot get back (a doubled swing is out of reach), from the arm as it was
		var a_styled := a.duplicate()
		var e_s := _dls(B, a, vars, f, tgt, 8, 0.0008)
		if e_s > 0.004:
			var a_base := a_styled.duplicate()
			for jn in ["clavicle_", "upperarm_", "lowerarm_"]:
				a_base[jn + side] = W._flat_read(i)["ang"][jn + side]
			var e_b := _dls(B, a_base, vars, f, tgt, 10, 0.0008)
			if e_b < e_s:
				for jj in a_base:
					a[jj] = a_base[jj]

	# write the poses: only the cards whose angles changed are rebuilt
	for i in n:
		var changed := false
		var f0: Dictionary = W._flat_read(i)
		for j in flats[i]["ang"]:
			if not (f0["ang"][j] as Vector3).is_equal_approx(flats[i]["ang"][j]):
				changed = true
				break
		if changed:
			W.cards[i]["pose"] = _pose_of(B, flats[i])

	# the full pipeline's check, and the last correction on the arm (pin and step logic live there, not in the model)
	var tip_err := {}
	var ts1 := W.times()
	for i in contacts:
		var side2: String = tip_full[i][1]
		for it in 5:
			W.apply(B, float(ts1[i][1]))
			var e2: float = (contact_point(B)[0] - (tip_full[i][0] as Vector3)).length()
			if e2 <= 0.003 or it == 4:
				tip_err[i] = e2
				break
			var ang2 := {}
			for jn in ["clavicle_", "upperarm_", "lowerarm_"]:
				ang2[jn + side2] = Vector3(W.cards[i]["pose"]["joints"][jn + side2]["bend"], W.cards[i]["pose"]["joints"][jn + side2]["side"], W.cards[i]["pose"]["joints"][jn + side2]["twist"])
			var vars2 := []
			for jn in ang2:
				for k in 3:
					vars2.append([jn, k])
			var tg := PackedFloat64Array()
			_v3(tg, tip_full[i][0])
			var pose0: Dictionary = W.cards[i]["pose"]
			var t_i: float = float(ts1[i][1])
			var f2 := func(ang: Dictionary) -> PackedFloat64Array:
				W.cards[i]["pose"] = _pose_with(pose0, ang)
				W.apply(B, t_i)
				var o := PackedFloat64Array()
				_v3(o, contact_point(B)[0])
				return o
			_dls(B, ang2, vars2, f2, tg, 3, 0.002)
			var fl2 := _dup_flat(W._flat_read(i))
			for jn in ang2:
				fl2["ang"][jn] = ang2[jn]
			W.cards[i]["pose"] = _pose_of(B, fl2)
	out["report"]["tip_err_m"] = tip_err
	for i in n:
		if W.cards[i].has("arrive_s"):
			W.cards[i]["arrive_s"] = snappedf(float(ts1[i][1]), 0.01)
		if W.cards[i].has("leave_s"):
			W.cards[i]["leave_s"] = snappedf(float(ts1[i][2]), 0.01)
	out["cards"] = W.cards
	return out
