class_name Gaze
extends RefCounted
## gaze.gd - I41 GAZE DIRECTOR. Where does each fighter look over the clip? The default, as martial artists do it:
##   CHEST     the opponent's upper chest. Skilled karate and boxing players fixate the head / chest region of the opponent and read
##             the limbs in peripheral vision (Williams & Elliott 1999, J Sport Exerc Psychol 21:362-375, karate; Ripoll et al. 1995,
##             boxers' gaze, Int J Sport Psychol). CAVEAT: cited from memory, the papers were not read here, so the split below is a
##             stated DEFAULT, not their measured numbers.
##   WEAPON    a short glance (GLANCE_W) at the incoming weapon / limb of the opponent's strike, ending WEAPON_LEAD before it arrives.
##   TELEGRAPH a short glance (GLANCE_T) at the target of the fighter's own strike, starting TELEGRAPH_LEAD (0.2 s) before the strike
##             arrives: people look at where they are about to hit (the "telegraph", which a defender can read). Optional.
## The keys go to the neck and head as PART KEYS (scripts/part_keys.gd) through LookAt.solve (scripts/look_at.gd), which clamps each joint
## to the body's limits (Body.set_ang_safe), so the neck never leaves its range. A part key replaces the card blend for that joint, so the
## head and neck are written densely (every DT) and the glances get their own edge keys.
## LEARNING: learn() reads a two-fighter scene whose head keys already exist (Nick's own) and returns how often the head points at the
## opponent's weapon during incoming strikes; with no head keys the stated default is used.

const DT := 1.0 / 15.0          # s between gaze keys (the in-between frames come from the PCHIP curve of part_keys)
const TELEGRAPH_LEAD := 0.2     # s before the strike's arrival that the telegraph glance begins
const GLANCE_T := 0.1           # s the telegraph glance is held
const WEAPON_LEAD := 0.1        # s before the opponent's strike arrives that the weapon glance ends
const GLANCE_W := 0.1           # s the weapon glance is held
const CHEST_AT := 0.6           # the chest point: this far along spine_03 (0 = its base, 1 = the neck)
const MIN_AWAY := 0.15          # m: a strike target nearer than this to the chest point gets no telegraph glance (the gaze is there already)
const EDGE := 0.02              # s: the gaze shift to and from a glance (a saccade is fast), keyed as its own edge keys
const ON_CHEST := 0.10          # m: a gaze ray passing this close to the chest point counts as "on the chest"
const JOINTS := ["neck_01", "head"]
const DEFAULT := {"weapon": true, "weapon_share": 1.0, "source": "default", "n": 0}


## the opponent's upper chest in the attacker's space (xf takes D's space to A's)
static func chest(BD: Body, xf: Transform3D) -> Vector3:
	var a: Vector3 = BD.P["spine_03"]
	var b: Vector3 = BD.e0["spine_03"] if BD.e0.has("spine_03") else BD.P["neck_01"]
	return xf * a.lerp(b, CHEST_AT)


## a copy of scene S with no head / neck part keys (the cards' own head)
static func bare(S: Scene) -> Scene:
	var c := S.clone()
	for j in JOINTS:
		c.part_keys.erase(j)
	return c


## the distance (m) from point p to the gaze ray (eye, forward), INF when p is behind the eye
static func ray_miss(B: Body, p: Vector3) -> float:
	var o := LookAt.eye_point(B)
	var f := LookAt.head_forward(B)
	var d := p - o
	var u := d.dot(f)
	if u <= 0.0:
		return INF
	return (d - f * u).length()


## nearest non-weapon capsule of D's body to point p: [part name, u along its axis]
static func _near_cap(BD: Body, xf: Transform3D, p: Vector3) -> Array:
	var best := INF
	var out := ["spine_03", 0.5]
	for c in BD.cross_caps(xf):
		if Body.is_wep(String(c[0])):
			continue
		var a: Vector3 = c[1]
		var b: Vector3 = c[2]
		var ab := b - a
		var u := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		var dd := p.distance_to(a + ab * u) - float(c[3])
		if dd < best:
			best = dd
			out = [String(c[0]), u]
	return out


static func _cap_point(BD: Body, xf: Transform3D, part: String, u: float) -> Vector3:
	for c in BD.cross_caps(xf):
		if String(c[0]) == part:
			return (c[1] as Vector3).lerp(c[2], u)
	return chest(BD, xf)


## the glance windows of A looking at D. {"tele": [{"card", "t0", "t1", "part", "u"}], "weap": [{"card", "t0", "t1", "tip"}]}
static func events(A: Scene, D: Scene, xf: Transform3D, tele: bool, weapon: bool, fps: int) -> Dictionary:
	var BA := DistanceKeeper.new_body()
	var BD := DistanceKeeper.new_body()
	var out := {"tele": [], "weap": []}
	var ta := A.times()
	for i in BeatFight.contacts(A):
		var arrive := float(ta[i][1])
		var sp := DistanceKeeper.span(A, BA, D, BD, xf, i, fps)
		A.apply(BA, sp["t_min"])
		D.apply(BD, sp["t_min"])
		var tip: Vector3 = DistanceKeeper.tips(BA)[sp["tip"]]
		var nc := _near_cap(BD, xf, tip)
		var t0 := maxf(0.0, arrive - TELEGRAPH_LEAD)
		# no glance when the target is already under the chest gaze (nothing to look away for)
		var tp := _cap_point(BD, xf, String(nc[0]), float(nc[1]))
		if tp.distance_to(chest(BD, xf)) <= MIN_AWAY:
			continue
		out["tele"].append({"card": i, "t0": t0, "t1": t0 + GLANCE_T, "part": nc[0], "u": nc[1], "arrive": arrive})
	if weapon:
		var td := D.times()
		var inv := xf.affine_inverse()
		for i in BeatFight.contacts(D):
			var arrive := float(td[i][1])
			var sp := DistanceKeeper.span(D, BD, A, BA, inv, i, fps)
			var t1 := maxf(GLANCE_W, arrive - WEAPON_LEAD)
			out["weap"].append({"card": i, "t0": t1 - GLANCE_W, "t1": t1, "tip": sp["tip"], "arrive": arrive})
	if not tele:
		out["tele"] = []
	return out


## the sample times: the grid plus the window edges, ascending, no two closer than 5 ms
static func _times(L: float, ev: Dictionary) -> Array:
	var ts := []
	var n := int(ceil(L / DT))
	for k in n + 1:
		ts.append(minf(L, float(k) * DT))
	for kind in ["tele", "weap"]:
		for w in ev[kind]:
			ts.append(float(w["t0"]) - EDGE)
			ts.append(float(w["t0"]))
			ts.append(float(w["t1"]))
			ts.append(float(w["t1"]) + EDGE)
	ts.sort()
	var out := []
	for t in ts:
		if float(t) < 0.0 or float(t) > L:
			continue
		if out.is_empty() or float(t) - float(out[-1]) > 0.005:
			out.append(float(t))
	return out


## Compute the gaze keys for fighter A looking at D. Neither is touched (clones). {"ok", "msg", "keys": {"neck_01": [...], "head": [...]},
## "ev" (events), "n" (keys per joint), "weapon" (bool used)}. tele: the telegraph glance; habit: learn()'s answer ({} = the default)
static func compute(A0: Scene, D0: Scene, xf: Transform3D, tele := true, habit := {}, fps := 30) -> Dictionary:
	var h: Dictionary = DEFAULT if habit.is_empty() else habit
	var A := bare(A0)
	var D := D0.clone()
	var BA := DistanceKeeper.new_body()
	var BD := DistanceKeeper.new_body()
	var weapon: bool = bool(h["weapon"])
	var ev := events(A, D, xf, tele, weapon, fps)
	var ts := _times(maxf(A.length(), D.length()), ev)
	var keys := {"neck_01": [], "head": []}
	var kinds := []
	for t in ts:
		A.apply(BA, t)
		D.apply(BD, t)
		var kind := "chest"
		var target := chest(BD, xf)
		for w in ev["weap"]:
			if t >= float(w["t0"]) - 1e-6 and t <= float(w["t1"]) + 1e-6:
				kind = "weapon"
				target = xf * (DistanceKeeper.tips(BD)[w["tip"]] as Vector3)
		for w in ev["tele"]:
			if t >= float(w["t0"]) - 1e-6 and t <= float(w["t1"]) + 1e-6:
				kind = "telegraph"
				target = _cap_point(BD, xf, String(w["part"]), float(w["u"]))
		LookAt.solve(BA, target)
		for j in JOINTS:
			(keys[j] as Array).append({"t": t, "v": BA.ang[j]})
		kinds.append(kind)
	var n_t: int = ev["tele"].size()
	var n_w: int = ev["weap"].size()
	return {"ok": not ts.is_empty() and A0.cards.size() > 1, "keys": keys, "ev": ev, "n": ts.size(), "times": ts, "kinds": kinds, "weapon": weapon, "tele": tele,
		"msg": "%d gaze key%s per joint: chest by default, %d weapon glance%s, %d telegraph glance%s" % [ts.size(), "" if ts.size() == 1 else "s", n_w, "" if n_w == 1 else "s", n_t, "" if n_t == 1 else "s"]}


## a copy of A0 with the gaze keys written in (what Accept makes)
static func applied(A0: Scene, g: Dictionary) -> Scene:
	var c := A0.clone()
	for j in JOINTS:
		c.part_keys[j] = (g["keys"][j] as Array).duplicate(true)
	return c


## how the gaze of A (as it stands, head keys included) sits on D's chest over the clip, read every 1/fps s:
## {"frames", "on_chest" (share of frames the ray passes within ON_CHEST of the chest), "worst" (m), "miss": [m per frame], "worst_neck"}
static func measure(A0: Scene, D0: Scene, xf: Transform3D, fps := 30) -> Dictionary:
	var A := A0.clone()
	var D := D0.clone()
	var BA := DistanceKeeper.new_body()
	var BD := DistanceKeeper.new_body()
	var L := maxf(A.length(), D.length())
	var n := int(floor(L * fps)) + 1
	var miss := []
	var on := 0
	var worst := 0.0
	for f in n:
		var t := float(f) / float(fps)
		A.apply(BA, t)
		D.apply(BD, t)
		var m := ray_miss(BA, chest(BD, xf))
		miss.append(m)
		if m <= ON_CHEST:
			on += 1
		if is_finite(m):
			worst = maxf(worst, m)
	return {"frames": n, "on_chest": float(on) / float(maxi(1, n)), "worst": worst, "miss": miss}


## the largest excess (deg) of the neck's and head's angles over the body's limits, over the clip every 1/fps s (0 = inside)
static func limit_excess(A0: Scene, fps := 30) -> float:
	var A := A0.clone()
	var BA := DistanceKeeper.new_body()
	var worst := 0.0
	for f in int(floor(A.length() * fps)) + 1:
		A.apply(BA, float(f) / float(fps))
		for j in JOINTS:
			var v: Vector3 = BA.ang[j]
			var c: Vector3 = BA.clamp_ang(j, v)
			worst = maxf(worst, maxf(absf(v.x - c.x), maxf(absf(v.y - c.y), absf(v.z - c.z))))
	return worst


## LEARN the habit from a two-fighter scene whose fighter A already has head keys (Nick's): over the opponent's incoming strikes, did the
## head point at the weapon (within 2 x ON_CHEST of the tip) just before it arrived? {"weapon" (bool), "weapon_share", "n" (strikes read),
## "source": "learned" | "default"}. No head keys, or no incoming strike = the stated default.
static func learn(A: Scene, D: Scene, xf: Transform3D, fps := 30) -> Dictionary:
	if not A.part_keys.has("head") or (A.part_keys["head"] as Array).is_empty():
		return DEFAULT.duplicate()
	var BA := DistanceKeeper.new_body()
	var BD := DistanceKeeper.new_body()
	var a := A.clone()
	var d := D.clone()
	var inv := xf.affine_inverse()
	var td := d.times()
	var n := 0
	var hit := 0
	for i in BeatFight.contacts(d):
		var arrive := float(td[i][1])
		var sp := DistanceKeeper.span(d, BD, a, BA, inv, i, fps)
		var best := INF
		for k in 7:
			var t := maxf(0.0, arrive - 0.4 + 0.05 * k)
			a.apply(BA, t)
			d.apply(BD, t)
			best = minf(best, ray_miss(BA, xf * (DistanceKeeper.tips(BD)[sp["tip"]] as Vector3)))
		n += 1
		if best <= 2.0 * ON_CHEST:
			hit += 1
	if n == 0:
		return DEFAULT.duplicate()
	var share := float(hit) / float(n)
	return {"weapon": share >= 0.5, "weapon_share": share, "source": "learned", "n": n}
