## human_limits.gd - "could a human do this?" (ROADMAP 10). Each frame of a scene at 60 fps, three checks against
## recorded human numbers (the sources and their status are in docs/research/HUMAN_LIMITS.md):
##   JOINT SPEED   a joint's turn (its rotation relative to the part it hangs from) against the fastest recorded peak
##   JOINT TORQUE  the net moment at the knee and the shoulder from inverse dynamics (point masses, de Leva's shares)
##                 against recorded strength: knee isokinetic extension, shoulder internal rotation
##   TIPPING       the centre of mass past the support polygon, with no hand or weapon holding it up, for longer than
##                 a fall from its height would take: t = sqrt(2 h / g)
## Findings have the Rulebook shape ({"sev", "t", "card", "rule", "msg", "v"}), so the CHECK panel and the timeline
## show them like the other rules. Rulebook.check calls findings().
class_name HumanLimits
extends RefCounted

static var on := false   # in the default Check only after "Check: could a human do this?" (rulebook.gd)
const FPS := 60.0
const GRAV := 9.81
const REF_MASS := 75.0      # kg (mine): the mass the absolute knee bar is quoted for; scaled as mass^(2/3)
const TOUCH := 0.02         # m: a hand or the weapon this close to a surface (or the floor) is holding on

## joint -> [the part whose rotation is measured, the part it is measured against]
const TURN := {"shoulder_r": ["upperarm_r", "clavicle_r"], "shoulder_l": ["upperarm_l", "clavicle_l"],
	"knee_r": ["calf_r", "thigh_r"], "knee_l": ["calf_l", "thigh_l"],
	"hip_r": ["thigh_r", "pelvis"], "hip_l": ["thigh_l", "pelvis"], "trunk": ["spine_03", "pelvis"]}
## deg/s per joint kind: [the fastest recorded peak (the WARN bar), the FAIL bar]. Sources: docs/research/HUMAN_LIMITS.md
const SPEED := {"shoulder": [4766.0, 6310.0], "knee": [1874.0, 2184.0], "hip": [745.0, 1117.0], "trunk": [601.0, 901.0]}
## Nm for a REF_MASS man (knee, isokinetic extension at 60 deg/s: mean, mean + 2 SD), and Nm per kg (shoulder
## internal rotation at 60 deg/s: mean, mean + 2 SD). Sources: docs/research/HUMAN_LIMITS.md
const KNEE_NM := [184.7, 273.1]
const SHOULDER_NM_KG := [0.70, 1.00]


## the mass the bars scale with (kg): the body's own, or REF_MASS for the default body
static func mass_of(B: Body) -> float:
	return float(B.body.get("mass", REF_MASS))


## one side's segment mass, kg (Proportions.masses sums both sides; with no mass set it gives shares of 1)
static func _seg_kg(B: Body, mm: Dictionary, seg: String) -> float:
	var k: float = float(mm[seg])
	if seg != "head" and seg != "trunk":
		k *= 0.5
	return k if B.body.has("mass") else k * REF_MASS


static func knee_limit(mass: float) -> float:
	return KNEE_NM[0] * pow(mass / REF_MASS, 2.0 / 3.0)


static func shoulder_limit(mass: float) -> float:
	return SHOULDER_NM_KG[0] * mass


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


## the scene at 60 fps: the turns (deg/s), the net moments (Nm), the centre of mass, its margin past the support
## (Balance.read: + inside), its height, whether a foot is down, and whether a hand or the weapon holds it up.
static func sample(S: Scene, B: Body) -> Dictionary:
	var n := int(ceil(S.length() * FPS)) + 1
	var was_stepped := S.stepped
	S.stepped = false
	var mm := Proportions.masses(B)
	var sex := String(B.body.get("sex", "male"))
	var lv: Dictionary = Proportions.DE_LEVA[sex]
	var kg := {}
	for seg in ["shank", "foot", "forearm", "hand"]:
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
		row["down"] = (bal["down"] as Array).size() > 0
		row["sup"] = supported(B)
		for sd in ["_l", "_r"]:
			var calf: Vector3 = B.P["calf" + sd]
			var foot: Vector3 = B.P["foot" + sd]
			var lower: Vector3 = B.P["lowerarm" + sd]
			var hand: Vector3 = B.P["hand" + sd]
			row["pts"]["knee" + sd] = calf
			row["pts"]["shoulder" + sd] = B.P["upperarm" + sd]
			row["pts"]["shank" + sd] = calf.lerp(foot, float(lv["shank"][1]))
			row["pts"]["foot" + sd] = Proportions.heel(B, sd).lerp(Proportions.toe(B, sd), float(lv["foot"][1]))
			row["pts"]["forearm" + sd] = lower.lerp(hand, float(lv["forearm"][1]))
			row["pts"]["hand" + sd] = hand.lerp(B.E["hand" + sd], float(lv["hand"][1]))
		rows.append(row)
	S.stepped = was_stepped
	var out := {"t": [], "speed": {}, "torque": {}, "margin": [], "h": [], "down": [], "sup": [], "mass": mass_of(B)}
	for i in n:
		out["t"].append(i / FPS)
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
	# the moments: the knee from the shank and the foot about the knee, the shoulder from the forearm and the hand about
	# the shoulder. Rotational inertia is left out (a lower bound on the moment: the bars are never raised by it).
	for sd in ["_l", "_r"]:
		out["torque"]["knee" + sd] = _moment(rows, "knee" + sd, [["shank" + sd, kg["shank"]], ["foot" + sd, kg["foot"]]], n)
		out["torque"]["shoulder" + sd] = _moment(rows, "shoulder" + sd, [["forearm" + sd, kg["forearm"]], ["hand" + sd, kg["hand"]]], n)
	return out


## |sum over the distal segments of (c - p) x m (a - g)| per frame: a = the segment's centre's second difference
static func _moment(rows: Array, joint: String, segs: Array, n: int) -> Array:
	var out := []
	var g := Vector3(0.0, -GRAV, 0.0)
	var acc := []
	for sg in segs:
		var c := []
		for i in n:
			c.append(rows[i]["pts"][sg[0]])
		var a := []
		for i in n:
			var c0: Vector3 = c[maxi(i - 1, 0)]
			var c2: Vector3 = c[mini(i + 1, n - 1)]
			a.append((c2 - 2.0 * (c[i] as Vector3) + c0) * FPS * FPS)
		acc.append([c, a, float(sg[1])])
	for i in n:
		var tau := Vector3.ZERO
		for k in acc.size():
			var c: Array = acc[k][0]
			var a: Array = acc[k][1]
			var m: float = acc[k][2]
			tau += ((c[i] as Vector3) - (rows[i]["pts"][joint] as Vector3)).cross(m * ((a[i] as Vector3) - g))
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
		var bar: Array = SPEED[kind]
		for r in _runs(sm["speed"][j], float(bar[0])):
			var pk: float = r["peak"]
			var sev := "FAIL" if pk > float(bar[1]) else "WARN"
			var t0: float = sm["t"][r["a"]]
			var t1: float = sm["t"][r["b"]]
			out.append(_f(sev, t0, "JOINT SPEED",
				"%.2f-%.2f s: %s turns %.0f deg/s, %.0f%% over the fastest a person's %s is recorded at (%.0f deg/s; FAIL past %.0f)." % [
					t0, t1, _words(j), pk, (pk / float(bar[0]) - 1.0) * 100.0, kind, float(bar[0]), float(bar[1])], pk))
			out[-1]["t1"] = t1
	return out


static func rule_torque(sm: Dictionary) -> Array:
	var out := []
	var mass: float = sm["mass"]
	for j in sm["torque"]:
		var is_knee: bool = String(j).begins_with("knee")
		var lim: float = knee_limit(mass) if is_knee else shoulder_limit(mass)
		var fail: float = lim * (KNEE_NM[1] / KNEE_NM[0]) if is_knee else lim * (SHOULDER_NM_KG[1] / SHOULDER_NM_KG[0])
		for r in _runs(sm["torque"][j], lim):
			var pk: float = r["peak"]
			var sev := "FAIL" if pk > fail else "WARN"
			var t0: float = sm["t"][r["a"]]
			var t1: float = sm["t"][r["b"]]
			var what := "a man's knee extension, mean %.0f Nm at 60 deg/s (mean + 2 SD %.0f)" % [lim, fail] if is_knee \
				else "shoulder internal rotation, mean %.0f Nm at 60 deg/s (mean + 2 SD %.0f)" % [lim, fail]
			out.append(_f(sev, t0, "JOINT TORQUE",
				"%.2f-%.2f s: %s needs %.0f Nm at its peak, %.0f%% over the recorded strength for a %.0f kg body: %s." % [
					t0, t1, _words(j), pk, (pk / lim - 1.0) * 100.0, mass, what], pk))
			out[-1]["t1"] = t1
	return out


## TIPPING: a run of frames with the centre of mass past the support, a foot down, and no hand or weapon holding it,
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


static func _tipping(sm: Dictionary, i: int) -> bool:
	return float(sm["margin"][i]) < 0.0 and bool(sm["down"][i]) and not bool(sm["sup"][i])


static func _words(j: String) -> String:
	return j.replace("_", " ")


## every human-limit finding of a scene (sorted by time, card set as Rulebook.check does)
## with_torque: JOINT TORQUE is OFF in the default Check (Nick's combo3 bat swing read 508 Nm at the shoulder against a
## 53 Nm isokinetic bar: the model hangs the whole bat on each arm, has no two-hand load sharing and compares a fast
## swing with a slow strength test, so it shouts MUST FIX on real motion). Speed and tipping stay on
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
