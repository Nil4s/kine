## human_limits.gd - "could a human do this?" (ROADMAP 10). Each frame of a scene at 60 fps, three checks against
## recorded human numbers (the sources and their status are in docs/research/HUMAN_LIMITS.md):
##   JOINT SPEED   a joint's turn (its rotation relative to the part it hangs from) against the PEAK turn recorded in
##                 sport (fast dynamic movements: pitching, hitting, kicking). WARN at the peak, FAIL at FAIL_K x peak
##   JOINT TORQUE  the shoulder's net moment from inverse dynamics (point masses + segment rotational inertia, de Leva's
##                 shares and radii, the bat's load shared between the two hands) against the in-sport peak moment
##                 (shoulder internal rotation in pitching). OFF in the default Check (opt-in: with_torque)
##   TIPPING       the centre of mass past the support polygon, with no hand or weapon holding it up, for longer than
##                 a fall from its height would take: t = sqrt(2 h / g)
## Findings have the Rulebook shape ({"sev", "t", "card", "rule", "msg", "v"}), so the CHECK panel and the timeline
## show them like the other rules. Rulebook.check calls findings().
class_name HumanLimits
extends RefCounted

static var on := false   # in the default Check only after "Check: could a human do this?" (rulebook.gd)
const FPS := 60.0
const GRAV := 9.81
const REF_MASS := 75.0      # kg (mine): the mass the torque bar is quoted for; scaled linearly with body mass (mine)
const TOUCH := 0.02         # m: a hand or the weapon this close to a surface (or the floor) is holding on
## FAIL = WARN x FAIL_K: mean + 2 SD with the SD as a fraction of the mean from Campbell's shoulder table (771.9 / 4765.7,
## the only SD in hand). Applies to every bar below (mine: no source gives a SD for the other joints)
const FAIL_K := 1.0 + 2.0 * (771.9 / 4765.7)
## the bat (mine, not read from a paper): a 33-inch adult bat about 0.9 kg, its centre 0.6 of its length from the knob,
## a uniform rod about its own centre for the rotational inertia
const BAT_KG := 0.9
const BAT_COM := 0.6

## joint -> [the part whose rotation is measured, the part it is measured against]
const TURN := {"shoulder_r": ["upperarm_r", "clavicle_r"], "shoulder_l": ["upperarm_l", "clavicle_l"],
	"knee_r": ["calf_r", "thigh_r"], "knee_l": ["calf_l", "thigh_l"], "trunk": ["spine_03", "pelvis"]}
## the hip is NOT graded: its only number (745 deg/s, Nunome 2002) is a kick mean of high-school players quoted by a review,
## not a sport peak read from the paper, and Nick's swings turn the hip past it with nothing verified to say what a person can do
## deg/s per joint kind: the PEAK recorded in sport (the WARN bar). Sources: docs/research/HUMAN_LIMITS.md
const SPEED := {"shoulder": 6520.0,   # internal rotation, collegiate fastball (Fortenbaugh 2009 review, primary not read)
	"knee": 1874.0,                    # extension in a soccer kick (Manolopoulos 2006, via a kick review's Table 4)
	"trunk": 1120.0}                   # upper trunk rotation, collegiate fastball (Fortenbaugh 2009 review, primary not read)
## Nm at the shoulder for a REF_MASS pitcher: shoulder internal rotation torque, the mean of 26 skilled adult pitchers
## in the acceleration of the pitch (Fleisig 1995, AJSM 23:233, abstract read). Sources: docs/research/HUMAN_LIMITS.md
const SHOULDER_IR_NM := 67.0
## de Leva 1996 Table 4, radii of gyration (transverse = mean of sagittal and transverse, / segment length), by sex:
## the forearm (elbow -> wrist) and the hand (wrist -> fingertip, the 'Hand*' row of the table)
const KT := {"male": {"forearm": 0.2705, "hand": 0.2585}, "female": {"forearm": 0.2590, "hand": 0.2235}}


## the mass the bars scale with (kg): the body's own, or REF_MASS for the default body
static func mass_of(B: Body) -> float:
	return float(B.body.get("mass", REF_MASS))


## one side's segment mass, kg (Proportions.masses sums both sides; with no mass set it gives shares of 1)
static func _seg_kg(B: Body, mm: Dictionary, seg: String) -> float:
	var k: float = float(mm[seg])
	if seg != "head" and seg != "trunk":
		k *= 0.5
	return k if B.body.has("mass") else k * REF_MASS


## [WARN, FAIL] deg/s for a joint kind
static func bars(kind: String) -> Array:
	var w: float = SPEED[kind]
	return [w, w * FAIL_K]


## [WARN, FAIL] Nm for the shoulder's internal rotation moment at this mass
static func shoulder_bars(mass: float) -> Array:
	var w := SHOULDER_IR_NM * mass / REF_MASS
	return [w, w * FAIL_K]


## a hand or the weapon's tip is on something: a surface under it (a prop, else the floor) within TOUCH
static func supported(B: Body) -> bool:
	for sd in ["_l", "_r"]:
		var h: Vector3 = B.P["hand" + sd]
		var r: float = float(B.rad["hand" + sd])
		var base := 0.0 if B.props.is_empty() else B.surface_at(h, r)
		if h.y - r - base < TOUCH:
			return true
	if B.wep_on:
		var tip: Vector3 = B.wep_point(B.wep_len)
		var base2 := 0.0 if B.props.is_empty() else B.surface_at(tip, B.wep_r_barrel)
		if tip.y - B.wep_r_barrel - base2 < TOUCH:
			return true
	return false


## the share of the bat's load on one arm: 0 with no bat or a free bat; the held hand alone takes all of it; with both
## hands on the bat (B.grip) each hand takes half (mine: an equal split, the simplest one that is not a whole bat per arm)
static func bat_share(B: Body, sd: String) -> float:
	if not B.wep_on or B.wep_hand == "":
		return 0.0
	if B.grip:
		return 0.5
	return 1.0 if B.wep_hand == "hand" + sd else 0.0


## the scene at 60 fps: the turns (deg/s), the shoulder's net moments (Nm), the centre of mass, its margin past the
## support (Balance.read: + inside), its height, whether a foot is down, and whether a hand or the weapon holds it up.
static func sample(S: Scene, B: Body) -> Dictionary:
	var n := int(ceil(S.length() * FPS)) + 1
	var was_stepped := S.stepped
	S.stepped = false
	var mm := Proportions.masses(B)
	var sex := String(B.body.get("sex", "male"))
	var lv: Dictionary = Proportions.DE_LEVA[sex]
	var kg := {}
	for seg in ["forearm", "hand"]:
		kg[seg] = _seg_kg(B, mm, seg)
	var rows := []
	for i in n:
		var t := minf(i / FPS, S.length())
		S.apply(B, t)
		var row := {"rel": {}, "pts": {}}
		for j in TURN:
			var pr: Array = TURN[j]
			row["rel"][j] = (B.G[pr[1]] as Quaternion).inverse() * (B.G[pr[0]] as Quaternion)
		var bal := Balance.read(B)
		row["margin"] = float(bal["margin"])
		row["h"] = (bal["com"] as Vector3).y
		row["com"] = bal["com"]
		row["down"] = (bal["down"] as Array).size() > 0
		row["sup"] = supported(B)
		for sd in ["_l", "_r"]:
			var lower: Vector3 = B.P["lowerarm" + sd]
			var hand: Vector3 = B.P["hand" + sd]
			row["pts"]["shoulder" + sd] = B.P["upperarm" + sd]
			row["pts"]["forearm" + sd] = lower.lerp(hand, float(lv["forearm"][1]))
			row["pts"]["hand" + sd] = hand.lerp(B.E["hand" + sd], float(lv["hand"][1]))
			row["pts"]["lower" + sd] = lower
			row["pts"]["wrist" + sd] = hand
			row["pts"]["fingertip" + sd] = B.E["hand" + sd]
		if B.wep_on:
			row["pts"]["knob"] = B.wep_point(0.0)
			row["pts"]["tip"] = B.wep_point(B.wep_len)
			row["pts"]["bat_com"] = B.wep_point(BAT_COM * B.wep_len)
		rows.append(row)
	S.stepped = was_stepped
	var out := {"t": [], "speed": {}, "torque": {}, "margin": [], "h": [], "down": [], "sup": [], "cv": [], "mass": mass_of(B)}
	for i in n:
		out["t"].append(i / FPS)
		var c0: Vector3 = rows[maxi(i - 1, 0)]["com"]
		var c1: Vector3 = rows[mini(i + 1, n - 1)]["com"]
		out["cv"].append(Vector2(c1.x - c0.x, c1.z - c0.z).length() * FPS / float(maxi(mini(i + 1, n - 1) - maxi(i - 1, 0), 1)))
		out["margin"].append(rows[i]["margin"])
		out["h"].append(rows[i]["h"])
		out["down"].append(rows[i]["down"])
		out["sup"].append(rows[i]["sup"])
	for j in TURN:
		var s := []
		for i in n:
			var prev: Dictionary = rows[maxi(i - 1, 0)]["rel"]
			s.append(Rulebook.ang_deg(prev[j], rows[i]["rel"][j]) * FPS if i > 0 else 0.0)
		if s.size() > 1:
			s[0] = s[1]
		out["speed"][j] = s
	# the shoulder's moment: the forearm and the hand (each with its rotational inertia), and the bat's share
	for sd in ["_l", "_r"]:
		out["torque"]["shoulder" + sd] = _shoulder_moment(rows, sd, kg, sex, bat_share(B, sd), n)
	return out


## acceleration of a point track (m/s^2, central second difference at FPS)
static func _accel(c: Array, n: int) -> Array:
	var a := []
	for i in n:
		var c0: Vector3 = c[maxi(i - 1, 0)]
		var c2: Vector3 = c[mini(i + 1, n - 1)]
		a.append((c2 - 2.0 * (c[i] as Vector3) + c0) * FPS * FPS)
	return a


## angular acceleration (rad/s^2) of the direction from p to d: w = u x du/dt, alpha = dw/dt. The spin about the
## segment's own axis cannot be seen from its ends, so it is left out (stated)
static func _alpha(p: Array, d: Array, n: int) -> Array:
	var u := []
	for i in n:
		var v: Vector3 = (d[i] as Vector3) - (p[i] as Vector3)
		u.append(v.normalized() if v.length() > 1e-9 else Vector3.UP)
	var w := []
	for i in n:
		var a: int = maxi(i - 1, 0)
		var b: int = mini(i + 1, n - 1)
		var dt := (b - a) / FPS
		var du: Vector3 = ((u[b] as Vector3) - (u[a] as Vector3)) / maxf(dt, 1e-9)
		w.append((u[i] as Vector3).cross(du))
	var al := []
	for i in n:
		var a2: int = maxi(i - 1, 0)
		var b2: int = mini(i + 1, n - 1)
		var dt2 := (b2 - a2) / FPS
		al.append(((w[b2] as Vector3) - (w[a2] as Vector3)) / maxf(dt2, 1e-9))
	return al


## the rotational term I alpha about the centre of mass, I = m (kt L)^2 with L the length of the segment (its ends p, d
## per frame) and kt its transverse radius of gyration as a fraction of L
static func _rot(p: Array, d: Array, n: int, m: float, kt: float) -> Array:
	var al := _alpha(p, d, n)
	var out := []
	for i in n:
		var L: float = ((d[i] as Vector3) - (p[i] as Vector3)).length()
		out.append(al[i] * (m * (kt * L) * (kt * L)))
	return out


## the shoulder's joint moment (Nm, the length of the vector) for one side: each distal load (forearm, hand, the bat's
## share) gives (centre - shoulder) x m (a - g) + I alpha, the Newton-Euler sum for a chain of distal segments
static func _shoulder_moment(rows: Array, sd: String, kg: Dictionary, sex: String, bat: float, n: int) -> Array:
	var g := Vector3(0.0, -GRAV, 0.0)
	var fc := []
	var hc := []
	var sh := []
	var fl := []
	var hl := []
	var lo := []
	var wr := []
	var en := []
	for i in n:
		fc.append(rows[i]["pts"]["forearm" + sd])
		hc.append(rows[i]["pts"]["hand" + sd])
		sh.append(rows[i]["pts"]["shoulder" + sd])
		lo.append(rows[i]["pts"]["lower" + sd])
		wr.append(rows[i]["pts"]["wrist" + sd])
		en.append(rows[i]["pts"]["fingertip" + sd])
	var loads := []   # [centre track, mass kg, accel track, I alpha track, share]
	loads.append([fc, float(kg["forearm"]), _accel(fc, n), _rot(lo, wr, n, float(kg["forearm"]), float(KT[sex]["forearm"])), 1.0])
	loads.append([hc, float(kg["hand"]), _accel(hc, n), _rot(wr, en, n, float(kg["hand"]), float(KT[sex]["hand"])), 1.0])
	# the weapon can be off on some frames (dropped, taken, swapped by a later card): no bat load then
	if bat > 0.0 and rows.all(func(r): return r["pts"].has("bat_com")):
		var bc := []
		var kn := []
		var tp := []
		for i in n:
			bc.append(rows[i]["pts"]["bat_com"])
			kn.append(rows[i]["pts"]["knob"])
			tp.append(rows[i]["pts"]["tip"])
		# a uniform rod about its own centre: kt = 1 / sqrt(12) of its length
		loads.append([bc, BAT_KG, _accel(bc, n), _rot(kn, tp, n, BAT_KG, 1.0 / sqrt(12.0)), bat])
	var out := []
	for i in n:
		var tau := Vector3.ZERO
		for ld in loads:
			var c: Array = ld[0]
			var m: float = ld[1]
			var a: Array = ld[2]
			var r: Array = ld[3]
			var sh_w: float = ld[4]
			tau += sh_w * (((c[i] as Vector3) - (sh[i] as Vector3)).cross(m * ((a[i] as Vector3) - g)) + (r[i] as Vector3))
		out.append(tau.length())
	return out


## runs of frames over bar: [{"a", "b", "peak"}]
static func _runs(s: Array, bar: float) -> Array:
	var out := []
	var i := 0
	while i < s.size():
		if float(s[i]) > bar:
			var a := i
			var pk: float = s[i]
			while i < s.size() and float(s[i]) > bar:
				pk = maxf(pk, float(s[i]))
				i += 1
			out.append({"a": a, "b": i - 1, "peak": pk})
		else:
			i += 1
	return out


static func _f(sev: String, t: float, rule: String, msg: String, v := 0.0) -> Dictionary:
	return Rulebook._f(sev, t, rule, msg, v)


static func rule_speed(sm: Dictionary) -> Array:
	var out := []
	for j in sm["speed"]:
		var kind: String = String(j).split("_")[0]
		var bar: Array = bars(kind)
		for r in _runs(sm["speed"][j], float(bar[0])):
			var pk: float = r["peak"]
			var sev := "FAIL" if pk > float(bar[1]) else "WARN"
			var t0: float = sm["t"][r["a"]]
			var t1: float = sm["t"][r["b"]]
			out.append(_f(sev, t0, "JOINT SPEED",
				"%.2f-%.2f s: %s turns %.0f deg/s, %.0f%% over the fastest peak recorded in sport for a %s (%.0f deg/s; FAIL past %.0f)." % [
					t0, t1, _words(j), pk, (pk / float(bar[0]) - 1.0) * 100.0, kind, float(bar[0]), float(bar[1])], pk))
			out[-1]["t1"] = t1
			out[-1]["joint"] = j   # TextBlocking matches a blocking's findings to its source's by joint
	return out


static func rule_torque(sm: Dictionary) -> Array:
	var out := []
	var mass: float = sm["mass"]
	var bar: Array = shoulder_bars(mass)
	for j in sm["torque"]:
		for r in _runs(sm["torque"][j], float(bar[0])):
			var pk: float = r["peak"]
			var sev := "FAIL" if pk > float(bar[1]) else "WARN"
			var t0: float = sm["t"][r["a"]]
			var t1: float = sm["t"][r["b"]]
			out.append(_f(sev, t0, "JOINT TORQUE",
				"%.2f-%.2f s: %s needs %.0f Nm at its peak, %.0f%% over the in-sport peak for a %.0f kg body (shoulder internal rotation in pitching: %.0f Nm at 75 kg, Fleisig 1995; FAIL past %.0f)." % [
					t0, t1, _words(j), pk, (pk / float(bar[0]) - 1.0) * 100.0, mass, float(bar[0]), float(bar[1])], pk))
			out[-1]["t1"] = t1
	return out


## TIPPING: a run of frames with the centre of mass past the support, a foot down, and no hand or weapon holding,
## longer than the fall from its height takes (t = sqrt(2 h / g)): a person would be on the floor
static func rule_tipping(sm: Dictionary) -> Array:
	var out := []
	var s: Array = sm["margin"]
	var n := s.size()
	var i := 0
	while i < n:
		if _tipping(sm, i):
			var a := i
			while i < n and _tipping(sm, i):
				i += 1
			var b := i - 1
			var dur := float(b - a + 1) / FPS
			var h: float = sm["h"][a]
			var fall := sqrt(2.0 * maxf(h, 0.0) / GRAV)
			if dur > fall:
				var t0: float = sm["t"][a]
				var t1: float = sm["t"][b]
				out.append(_f("FAIL", t0, "TIPPING",
					"%.2f-%.2f s: the centre of mass %.0f cm past the feet with nothing in the hands for %.2f s; a fall from %.2f m takes %.2f s, so a person would be on the floor (%.0f%% over the fall time)." % [
						t0, t1, -float(s[a]) * 100.0, dur, h, fall, (dur / fall - 1.0) * 100.0], dur))
				out[-1]["t1"] = t1
		else:
			i += 1
	return out


## a centre of mass travelling this fast (m/s) along the floor is in a gait or a lunge, not tipping over: it is carried onto the
## next step. In walking and running the CoM is outside the base of support most of the time (Winter 1995, Gait & Posture 3:193:
## "Human balance and posture control during standing and walking": only in quiet standing must it stay inside), so the fall-time
## model below, a body that stands still and falls, is judged on the frames that are slow (a series with no "cv" is all slow)
const GAIT_SPEED := 1.0


static func _tipping(sm: Dictionary, i: int) -> bool:
	if sm.has("cv") and float(sm["cv"][i]) >= GAIT_SPEED:
		return false
	return float(sm["margin"][i]) < 0.0 and bool(sm["down"][i]) and not bool(sm["sup"][i])


static func _words(j: String) -> String:
	return j.replace("_", " ")


## every human-limit finding of a scene (sorted by time, card set as Rulebook.check does)
## with_torque: JOINT TORQUE is OFF in the default Check (opt-in until it passes Nick's real scenes). Speed and tipping
## are the default rules once on := true
static func findings(S: Scene, B: Body, sm := {}, with_torque := false) -> Array:
	if S.cards.size() < 2:
		return []
	if sm.is_empty():
		sm = sample(S, B)
	var out := []
	out += rule_speed(sm)
	if with_torque:
		out += rule_torque(sm)
	out += rule_tipping(sm)
	for f in out:
		f["card"] = Rulebook.card_at(S, f["t"])
	out.sort_custom(func(x, y): return x["t"] < y["t"])
	return out
