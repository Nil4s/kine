## who_could.gd - WHO COULD DO THIS? (docs/INNOVATIONS.md N027). From a clip (or a card, or a t0-t1 span), the MINIMUM body
## that could perform it, capacity by capacity, as a population percentile where an opened source gives a distribution
## (mean and SD), else as a tier only, labelled HEURISTIC:
##     "Who could do this: a trained fighter: top 18 % hip flexibility (right hip 110 deg, knee straight), ..."
##     "Who could do this: no human: the right fist reaches 31.0 m/s; the record is ~20.1 m/s"
## WHY: a blind agent that animates "a kick" cannot tell a kick anyone could throw from one only a gymnast could, or none.
## Numbers, sources and DOIs: docs/research/WHO_COULD.md; each constant below has a Trust.REG row (scripts/trust.gd).
##
## WHAT IS READ (one pass over the window at 240 Hz, SpeedEnv.HZ: the hand and foot peaks are I47's own one-step differences)
##   hip flexibility   the hamstrings' DEMAND: the hip's flexion less the slack the knee's bend buys (CoupledLimits' hamstring
##                     curve: a straight knee buys none, 60 deg of knee buys the whole 30 deg to the table's 120). With the
##                     knee straight the demand IS the straight-leg raise, so it is read against the passive straight-leg
##                     raise of healthy adults, 90 +- 22 deg (Thomas et al. 2022; CoupledLimits.HAM_STRAIGHT)
##   hip extension     the rectus femoris' demand the same way (the modified Thomas test, -10.6 +- 9.61 deg at knee 50, Ferber 2010)
##   ankle flexibility the gastrocnemius' demand (weight-bearing dorsiflexion, knee straight, 25 +- 6 deg, Baumbach 2014)
##   spine flexion     the three spine joints' forward bend summed, against the one-joint table's sum: TIER ONLY, HEURISTIC
##                     (no spine-ROM distribution was opened)
##   shoulder          the upper arm's elevation from the trunk's down axis: TIER ONLY, HEURISTIC
##   hand / foot speed the peak world speed of either hand / ball of the foot (B.E hand_*, ball_*: what SpeedEnv reads),
##                     among amateur boxers' lead hooks (11.95 +- 1.84 m/s, Stanley 2018) and black belts' roundhouse feet
##                     (14.66 +- 1.18 m/s, Gavagan & Sayers 2017). NO HUMAN past the fastest punch recorded (Guinness, 45 mph)
##   jump power        each flight (neither foot within Balance.TOUCH of the floor for FLIGHT_MIN or longer): the centre of
##                     mass's rise from take-off to the apex (what flight-time CMJ height measures) and the take-off speed
##                     sqrt(2 g h), against Finnish men 26-30 (34.9 +- 8.5 cm, Koivunen 2026)
## NOT READ (said in the output, never guessed): strength (a held lever's moment needs a hold detector and a strength norm we
## have not opened) and reaction / contact timing (needs an opponent's cue; scripts/counter.gd judges it in a fight).
##
## PERCENTILE = the share of the stated population at or below the value (normal model from the mean and SD); "top X %" is
## 100 - it. TIER (any adult < trained < elite < beyond) from the percentile by TIER_TRAINED / TIER_ELITE where the population
## is healthy adults, from the stated speed cuts where the population is trained fighters. Overall = the highest tier;
## "no human" when any capacity is beyond. Read only: the body and the scene are put back.
class_name WhoCould
extends RefCounted

const HZ := 240.0
const G := 9.81
const TIERS := ["any adult", "trained", "elite", "beyond"]

# --- tier cuts on a healthy-adult percentile (HEURISTIC: ours; 97.7 = mean + 2 SD) ---
const TIER_TRAINED := 75.0
const TIER_ELITE := 97.7

# --- flexibility distributions ---
## the four sessions' baseline passive straight-leg raise SDs, 21.1-22.9 deg (Thomas et al. 2022, BMC Sports Sci Med Rehabil
## 14:202, doi:10.1186/s13102-022-00599-8, PMC9714235, Table 1: 87.1 +- 22.6 ... 91.1 +- 21.7; 32 students, Gyko sensor);
## the mean is CoupledLimits.HAM_STRAIGHT (90)
const HAM_SD := 22.0
## gymnasts' straight-leg raise 140.9 +- 20.4 (Donti et al. 2020, Sports 8(3):28, doi:10.3390/sports8030028, PMC7183084);
## the mean is CoupledLimits.HAM_TRAINED. Beyond = gymnasts' mean + 2 SD (HEURISTIC; the table's 120 stops it first)
const GYM_SD := 20.4
## weight-bearing dorsiflexion, knee straight, 25 +- 6 (Baumbach et al. 2014, doi:10.1186/1471-2474-15-246, Table 2); the mean
## is CoupledLimits.GAS_STRAIGHT
const ANKLE_SD := 6.0
const BEYOND_SD := 4.0     # HEURISTIC: past mean + 4 SD of healthy adults (1 in 30 000) a joint is called beyond

# --- spine and shoulder: TIER ONLY (HEURISTIC) ---
## the share of the one-joint table's summed forward bend (spine_01..03: 3 x 20 = 60 deg) under which any adult bends
const SPINE_ANY := 0.75
const SPINE_TRAINED := 0.95
## upper-arm elevation from the trunk's down axis: past this the arm is overhead and in line with the trunk
const SHOULDER_ANY := 170.0

# --- hand speed (trained fighters' distribution) ---
const FIST_MEAN := 11.95   # m/s, lead hook peak fist speed, 15 amateur boxers, 3D mocap (Stanley et al. 2018, Int J Perf Anal Sport 18:835)
const FIST_SD := 1.84
## junior boxers' lead straight peak 6.317 +- 0.415 m/s (Chen et al. 2022, Front Physiol 13:1015154, PMC9798280; elite 7.162):
## at or under it, ANY adult (HEURISTIC: an untrained adult's figure was not found; we take the junior boxers' mean)
const FIST_ANY := 6.317
const FIST_TRAINED := 13.79   # mean + 1 SD: SpeedEnv's I47 hand limit; over it = elite
## Guinness World Records "fastest punch", Keith Liddell, 45 mph = 20.1 m/s (via Wikipedia citing guinnessworldrecords.com,
## 2013; UNVERIFIED: the Guinness page itself was not opened, and a speed-puck reading is not a mocap peak)
const FIST_RECORD := 20.1

# --- foot speed ---
const FOOT_MEAN := 14.66   # m/s, taekwondo black belts' roundhouse max foot speed (Gavagan & Sayers 2017, PLoS ONE 12:e0182645, Table 2)
const FOOT_SD := 1.18
const FOOT_ANY := 8.64      # HEURISTIC: the slowest art's mean - 2 SD (Muay Thai 13.24 - 2 x 2.30, the same table)
const FOOT_TRAINED := 15.84 # mean + 1 SD: SpeedEnv's I47 foot limit
const FOOT_BEYOND := 19.38  # HEURISTIC: taekwondo mean + 4 SD (no kick speed record was found)

# --- jump ---
## countermovement jump, men 26-30, contact-mat flight time: 34.9 (8.5) cm, n = 54 (Koivunen, Laakkonen, Ahtiainen, Walker
## 2026, Scand J Med Sci Sports 36(6):e70322, doi:10.1111/sms.70322, PMC13280190, Table 1). Their young groups are athlete-heavy
const JUMP_MEAN := 0.349
const JUMP_SD := 0.085
## national-team sprinters, the highest group: men 62.7 (4.8) cm (Haugen et al. 2021, IJSPP 16:184, doi:10.1123/ijspp.2019-0964,
## abstract): quoted beside an elite jump
const JUMP_ELITE := 0.627
## the NFL Combine's best vertical jump, 46.0 in = 1.168 m (Gerald Sensabaugh 2005; via Wikipedia citing DraftScout:
## UNVERIFIED). A jump-and-reach with an arm swing: generous against a centre-of-mass rise
const JUMP_RECORD := 1.168
const FLIGHT_MIN := 0.05    # s, HEURISTIC: a shorter "flight" is a foot skimming the 1 cm touch band, not a jump


## the standard normal CDF (Abramowitz & Stegun 7.1.26 erf, |error| < 1.5e-7)
static func phi(z: float) -> float:
	var x := absf(z) / sqrt(2.0)
	var t := 1.0 / (1.0 + 0.3275911 * x)
	var y := 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * exp(-x * x)
	return 0.5 * (1.0 + (y if z >= 0.0 else -y))


static func pct(v: float, mean: float, sd: float) -> float:
	return 100.0 * phi((v - mean) / sd)


static func tier_of_pct(p: float) -> String:
	return "elite" if p >= TIER_ELITE else ("trained" if p >= TIER_TRAINED else "any adult")


static func _coupling(id: String) -> Dictionary:
	for c in CoupledLimits.couplings():
		if c["id"] == id:
			return c
	return {}


## the hamstrings' demand: the hip's flexion less what the knee's bend buys (0 with a straight knee)
static func ham_demand(hip: float, knee: float) -> float:
	return hip - (CoupledLimits.at(_coupling("hamstrings")["curve"], knee) - CoupledLimits.HAM_STRAIGHT)


## the rectus femoris' demand as an equivalent Thomas-test hip angle (knee at 50): more negative = more extension
static func rect_demand(hip: float, knee: float) -> float:
	return hip - (CoupledLimits.at(_coupling("rectus femoris")["curve"], knee) - CoupledLimits.RECT_EXT)


static func gas_demand(df: float, knee: float) -> float:
	return df - (CoupledLimits.at(_coupling("gastrocnemius")["curve"], knee) - CoupledLimits.GAS_STRAIGHT)


static func spine_bend(B: Body) -> float:
	return (B.ang["spine_01"] as Vector3).x + (B.ang["spine_02"] as Vector3).x + (B.ang["spine_03"] as Vector3).x


static func spine_table(B: Body) -> float:
	return B.lim["spine_01"]["bend"].y + B.lim["spine_02"]["bend"].y + B.lim["spine_03"]["bend"].y


## the upper arm's elevation (deg) from the trunk's down axis (pelvis -> neck reversed): 0 = hanging, 90 = level, 180 = overhead
static func elevation(B: Body, sd: String) -> float:
	var up: Vector3 = (B.P["neck_01"] as Vector3) - (B.P["spine_01"] as Vector3)
	var arm: Vector3 = (B.E["upperarm" + sd] as Vector3) - (B.P["upperarm" + sd] as Vector3)
	if up.length() < 1e-6 or arm.length() < 1e-6:
		return 0.0
	return rad_to_deg((-up.normalized()).angle_to(arm.normalized()))


## the window [t0, t1] at 240 Hz: per step every quantity the capacities read. The body and scene are put back
static func sample(S: Scene, B: Body, t0: float, t1: float) -> Dictionary:
	var keep: Dictionary = B.state()
	var was_stepped := S.stepped
	S.stepped = false
	var n := maxi(1, int(ceil((t1 - t0) * HZ)))
	var rows := []
	for s in n + 1:
		var t := minf(t0 + float(s) / HZ, t1)
		S.apply(B, t)
		var r := {"t": t, "com": Balance.com(B), "spine": spine_bend(B),
			"down": EventQuery.foot_down(B, "_l") or EventQuery.foot_down(B, "_r")}
		for sd in ["_l", "_r"]:
			r["hand" + sd] = B.E["hand" + sd]
			r["ball" + sd] = B.E["ball" + sd]
			r["hip" + sd] = (B.ang["thigh" + sd] as Vector3).x
			r["knee" + sd] = (B.ang["calf" + sd] as Vector3).x
			r["ankle" + sd] = (B.ang["foot" + sd] as Vector3).x
			r["elev" + sd] = elevation(B, sd)
		rows.append(r)
	S.stepped = was_stepped
	B.set_state(keep)
	return {"rows": rows, "t0": t0, "t1": t1, "spine_table": spine_table(B)}


static func _side(sd: String) -> String:
	return "right" if sd == "_r" else "left"


static func _f60(t: float) -> int:
	return int(round(t * 60.0))


## the capacities from a sample: [{name, used, unit, percentile|null, top, tier, pop, source, url, trust, tier_trust, frames, t, side, say}]
static func capacities(sm: Dictionary) -> Array:
	var rows: Array = sm["rows"]
	var out := []
	# --- flexibility: the worst frame per coupling over both legs ---
	var best := {"ham": [-INF, 0, ""], "rect": [INF, 0, ""], "gas": [-INF, 0, ""], "spine": [-INF, 0, ""], "elev": [-INF, 0, ""]}
	for i in rows.size():
		var r: Dictionary = rows[i]
		for sd in ["_l", "_r"]:
			var h := ham_demand(r["hip" + sd], r["knee" + sd])
			if h > best["ham"][0]:
				best["ham"] = [h, i, sd]
			var e := rect_demand(r["hip" + sd], r["knee" + sd])
			if e < best["rect"][0]:
				best["rect"] = [e, i, sd]
			var a := gas_demand(r["ankle" + sd], r["knee" + sd])
			if a > best["gas"][0]:
				best["gas"] = [a, i, sd]
			if float(r["elev" + sd]) > best["elev"][0]:
				best["elev"] = [float(r["elev" + sd]), i, sd]
		if float(r["spine"]) > best["spine"][0]:
			best["spine"] = [float(r["spine"]), i, ""]
	if rows.is_empty():
		return out
	# hip flexibility
	var hb: Array = best["ham"]
	var hr: Dictionary = rows[hb[1]]
	var hp := pct(hb[0], CoupledLimits.HAM_STRAIGHT, HAM_SD)
	var ht := "beyond" if hb[0] > CoupledLimits.HAM_TRAINED + 2.0 * GYM_SD else tier_of_pct(hp)
	var knee_h: float = hr["knee" + hb[2]]
	var bars := ["CoupledLimits.HAM_STRAIGHT", "WhoCould.HAM_SD"] + (["CoupledLimits.HAM_SLOPE"] if knee_h > 0.5 else [])
	out.append(_cap("hip flexibility", hb[0], "deg (straight-leg-raise equivalent)", hp, ht, hr["t"], hb[2],
		"healthy adults' passive straight-leg raise, 90 +- 22 deg (32 students)",
		"Thomas et al. 2022 (CoupledLimits.HAM_STRAIGHT; SD from Table 1); gymnasts 141 +- 20 (Donti et al. 2020)",
		"https://doi.org/10.1186/s13102-022-00599-8", bars,
		{"hip": snappedf(hr["hip" + hb[2]], 0.1), "knee": snappedf(knee_h, 0.1)},
		"%s hip %.0f deg, knee %s" % [_side(hb[2]), hr["hip" + hb[2]], "straight" if knee_h < 5.0 else "bent %.0f deg" % knee_h], bars.size()))
	# hip extension (the larger the extension, the higher the percentile)
	var eb: Array = best["rect"]
	var er: Dictionary = rows[eb[1]]
	var ep := 100.0 * phi((CoupledLimits.RECT_EXT - eb[0]) / CoupledLimits.RECT_SD)
	var et := "beyond" if eb[0] < CoupledLimits.RECT_EXT - BEYOND_SD * CoupledLimits.RECT_SD else tier_of_pct(ep)
	out.append(_cap("hip extension", -float(eb[0]), "deg (Thomas-test equivalent, extension +)", ep, et, er["t"], eb[2],
		"300 recreational athletes, modified Thomas test, 10.6 +- 9.6 deg", "Ferber et al. 2010 (CoupledLimits.RECT_EXT, RECT_SD)",
		"https://doi.org/10.4085/1062-6050-45.4.344", ["CoupledLimits.RECT_EXT", "CoupledLimits.RECT_SD", "CoupledLimits.RECT_KNEE"],
		{"hip": snappedf(er["hip" + eb[2]], 0.1), "knee": snappedf(er["knee" + eb[2]], 0.1)},
		"%s hip %.0f deg with the knee %.0f deg" % [_side(eb[2]), er["hip" + eb[2]], er["knee" + eb[2]]], 3))
	# ankle
	var ab: Array = best["gas"]
	var ar: Dictionary = rows[ab[1]]
	var ap := pct(ab[0], CoupledLimits.GAS_STRAIGHT, ANKLE_SD)
	var at := "beyond" if ab[0] > CoupledLimits.GAS_STRAIGHT + BEYOND_SD * ANKLE_SD else tier_of_pct(ap)
	out.append(_cap("ankle flexibility", ab[0], "deg (knee-straight dorsiflexion equivalent)", ap, at, ar["t"], ab[2],
		"20 healthy adults, weight-bearing lunge, 25 +- 6 deg", "Baumbach et al. 2014 (CoupledLimits.GAS_STRAIGHT; SD Table 2)",
		"https://doi.org/10.1186/1471-2474-15-246", ["CoupledLimits.GAS_STRAIGHT", "WhoCould.ANKLE_SD"],
		{"ankle": snappedf(ar["ankle" + ab[2]], 0.1), "knee": snappedf(ar["knee" + ab[2]], 0.1)},
		"%s ankle %.0f deg up with the knee %.0f deg" % [_side(ab[2]), ar["ankle" + ab[2]], ar["knee" + ab[2]]]))
	# spine (tier only)
	var sb: Array = best["spine"]
	var share: float = maxf(sb[0], 0.0) / maxf(float(sm["spine_table"]), 1e-6)
	var st := "any adult" if share <= SPINE_ANY else ("trained" if share <= SPINE_TRAINED else "elite")
	out.append(_cap("spine flexion", sb[0], "deg (spine_01..03 bend summed)", null, st, rows[sb[1]]["t"], "",
		"-", "HEURISTIC: no spine-ROM distribution opened; tier from the share of the one-joint table's %.0f deg (%.0f %% here)" % [sm["spine_table"], 100.0 * share],
		"res://docs/research/WHO_COULD.md", ["WhoCould.SPINE_ANY", "WhoCould.SPINE_TRAINED"], {"share": snappedf(share, 0.001)},
		"the back bent %.0f deg forward" % sb[0]))
	# shoulder (tier only)
	var lb: Array = best["elev"]
	out.append(_cap("shoulder flexibility", lb[0], "deg (upper arm from the trunk's down axis)", null,
		"any adult" if lb[0] <= SHOULDER_ANY else "trained", rows[lb[1]]["t"], lb[2], "-",
		"HEURISTIC: no shoulder-ROM distribution opened; past %.0f deg the arm is overhead in line with the trunk" % SHOULDER_ANY,
		"res://docs/research/WHO_COULD.md", ["WhoCould.SHOULDER_ANY"], {}, "%s arm raised %.0f deg" % [_side(lb[2]), lb[0]]))
	# --- hand and foot speed ---
	for spec in [["hand speed", "hand", FIST_MEAN, FIST_SD, FIST_ANY, FIST_TRAINED, FIST_RECORD,
			"15 male amateur boxers' lead hooks, peak fist speed 11.95 +- 1.84 m/s",
			"Stanley et al. 2018; any adult <= %.1f (junior boxers' straight, Chen et al. 2022: the cut is HEURISTIC); no human past the Guinness fastest punch, 45 mph = %.1f m/s (UNVERIFIED)" % [FIST_ANY, FIST_RECORD],
			"https://chesterrep.openrepository.com/entities/publication/0acdae9d-e8be-48cf-816e-ed9c667981b3",
			["WhoCould.FIST_MEAN", "WhoCould.FIST_SD", "WhoCould.FIST_ANY", "WhoCould.FIST_RECORD"], "fist"],
		["foot speed", "ball", FOOT_MEAN, FOOT_SD, FOOT_ANY, FOOT_TRAINED, FOOT_BEYOND,
			"8 taekwondo black belts' roundhouse, max foot speed 14.66 +- 1.18 m/s",
			"Gavagan & Sayers 2017, Table 2; any adult <= %.1f and beyond > %.1f are HEURISTIC (Muay Thai mean - 2 SD; taekwondo mean + 4 SD)" % [FOOT_ANY, FOOT_BEYOND],
			"https://doi.org/10.1371/journal.pone.0182645", ["WhoCould.FOOT_MEAN", "WhoCould.FOOT_SD", "WhoCould.FOOT_ANY", "WhoCould.FOOT_BEYOND"], "foot"]]:
		var pk := [0.0, 0, "_l"]
		for i in range(1, rows.size()):
			var dt: float = float(rows[i]["t"]) - float(rows[i - 1]["t"])
			if dt <= 1e-6:
				continue
			for sd in ["_l", "_r"]:
				var v: float = ((rows[i][String(spec[1]) + sd] as Vector3) - (rows[i - 1][String(spec[1]) + sd] as Vector3)).length() / dt
				if v > pk[0]:
					pk = [v, i, sd]
		var v0: float = pk[0]
		var tr := "any adult" if v0 <= spec[4] else ("trained" if v0 <= spec[5] else ("elite" if v0 <= spec[6] else "beyond"))
		var c := _cap(spec[0], v0, "m/s", pct(v0, spec[2], spec[3]), tr, rows[pk[1]]["t"], pk[2], spec[7], spec[8], spec[9], spec[10], {},
			"the %s %s reaches %.1f m/s" % [_side(pk[2]), spec[11], v0])
		c["limit"] = spec[6]
		c["limit_words"] = "the record is ~%.1f m/s (Guinness, 45 mph)" % FIST_RECORD if spec[11] == "fist" else "past %.1f m/s (black belts' mean + 4 SD, HEURISTIC: no record found)" % FOOT_BEYOND
		out.append(c)
	# --- jump: each flight's centre-of-mass rise from take-off to apex ---
	var jb := {"h": 0.0, "a": -1, "b": -1, "flight": 0.0}
	var i0 := -1
	for i in rows.size() + 1:
		var up: bool = i < rows.size() and not bool(rows[i]["down"])
		if up and i0 < 0:
			i0 = i
		elif not up and i0 >= 0:
			var fl: float = float(rows[i - 1]["t"]) - float(rows[i0]["t"])
			if fl >= FLIGHT_MIN:
				var to := maxi(i0 - 1, 0)   # the last frame with a foot down: the take-off
				for k in range(i0, i):
					var h: float = (rows[k]["com"] as Vector3).y - (rows[to]["com"] as Vector3).y
					if h > jb["h"]:
						jb = {"h": h, "a": to, "b": k, "flight": fl}
			i0 = -1
	var jh: float = jb["h"]
	var jp := pct(jh, JUMP_MEAN, JUMP_SD)
	var jt := "beyond" if jh > JUMP_RECORD else ("any adult" if jb["a"] < 0 else tier_of_pct(jp))
	var jc := _cap("jump power", jh, "m (centre-of-mass rise, take-off to apex)", jp if jb["a"] >= 0 else null, jt,
		rows[jb["b"]]["t"] if jb["b"] >= 0 else rows[0]["t"], "",
		"Finnish men 26-30, countermovement jump, 34.9 +- 8.5 cm (n = 54)",
		"Koivunen et al. 2026 (Table 1); national-team sprinters 62.7 cm (Haugen et al. 2021); no human past the NFL Combine's best 46 in = %.2f m (UNVERIFIED)" % JUMP_RECORD,
		"https://doi.org/10.1111/sms.70322", ["WhoCould.JUMP_MEAN", "WhoCould.JUMP_SD", "WhoCould.JUMP_RECORD", "WhoCould.FLIGHT_MIN"],
		{"takeoff_speed": snappedf(sqrt(2.0 * G * jh), 0.01), "flight_s": snappedf(jb["flight"], 0.001)},
		"no flight in the window" if jb["a"] < 0 else "a %.2f m rise (take-off %.1f m/s)" % [jh, sqrt(2.0 * G * jh)])
	if jb["a"] >= 0:
		jc["frames"] = [_f60(rows[jb["a"]]["t"]), _f60(rows[jb["b"]]["t"])]
	jc["limit"] = JUMP_RECORD
	jc["limit_words"] = "the best recorded is %.2f m (NFL Combine, a jump-and-reach)" % JUMP_RECORD
	out.append(jc)
	return out


static func _cap(name: String, used: float, unit: String, p: Variant, tier: String, t: float, sd: String, pop: String, src: String,
		url: String, bars: Array, extra: Dictionary, what: String, n_dist := 2) -> Dictionary:
	# trust = the percentile's (the distribution's bars, the first n_dist); tier_trust = every bar's and the cuts' (ours)
	var tw := bars.map(func(b): return Trust.row(b))
	tw.append({"status": Trust.H})
	var c := {"name": name, "used": snappedf(used, 0.01), "unit": unit, "tier": tier, "pop": pop, "source": src, "url": url,
		"bars": bars, "trust": Trust.weakest(tw.slice(0, n_dist)) if p != null else Trust.H,
		"tier_trust": Trust.weakest(tw), "t": snappedf(t, 0.0001), "frames": [_f60(t)], "side": _side(sd) if sd != "" else "", "what": what}
	if p != null:
		c["percentile"] = snappedf(float(p), 0.1)
		c["top"] = snappedf(100.0 - float(p), 0.1)
	else:
		c["percentile"] = null
		c["heuristic"] = "HEURISTIC: tier only, no population distribution opened"
	for k in extra:
		c[k] = extra[k]
	return c


## a capacity in the minimum-body words ("top 18 % hip flexibility (right hip 110 deg, knee straight)")
static func phrase(c: Dictionary) -> String:
	var nm: String = c["name"]
	if c["tier"] == "beyond":
		return "%s; %s" % [c["what"], c.get("limit_words", "past mean + 4 SD of healthy adults")]
	if nm == "hand speed" or nm == "foot speed":
		var who := "boxer's hand" if nm == "hand speed" else "kicker's foot"
		return "%s %s speed (%.1f m/s)" % ["a trained" if c["tier"] == "trained" else "an elite", who, c["used"]]
	if c["percentile"] == null:
		return "%s %s (%s, HEURISTIC)" % ["a trained" if c["tier"] == "trained" else "an elite", nm, c["what"]]
	var top: float = c["top"]
	var tw := ("top %.0f %%" % top) if top >= 1.0 else ("top %.1f %%" % top)
	if nm == "jump power" and c["tier"] == "elite":
		return "elite jump power (%s; national-team sprinters average %.2f m)" % [c["what"], JUMP_ELITE]
	return "%s %s (%s)" % [tw, nm, c["what"]]


## {capacities, overall, text, not_read}
static func judge(caps: Array) -> Dictionary:
	var rank := 0
	var lead := ""
	for c in caps:
		var r := TIERS.find(String(c["tier"]))
		if r > rank:
			rank = r
			lead = c["name"]
	var overall: String = "no human" if rank == 3 else TIERS[rank]
	var text := ""
	if rank == 3:
		text = "Who could do this: no human: " + "; ".join(caps.filter(func(c): return c["tier"] == "beyond").map(func(c): return phrase(c)))
	elif rank == 0:
		text = "Who could do this: any adult."
	else:
		var dom := "fighter" if lead in ["hand speed", "foot speed"] else ("jumper" if lead == "jump power" else "athlete")
		var above := caps.filter(func(c): return c["tier"] != "any adult")
		above.sort_custom(func(a, b): return TIERS.find(String(a["tier"])) > TIERS.find(String(b["tier"])))
		text = "Who could do this: %s %s: %s" % ["a trained" if rank == 1 else "an elite", dom, ", ".join(above.map(func(c): return phrase(c)))]
	return {"capacities": caps, "overall": overall, "text": text,
		"not_read": [{"name": "strength", "why": "a held lever's moment needs a hold detector and an opened strength norm (none yet)"},
			{"name": "reaction / contact timing", "why": "needs an opponent's cue: scripts/counter.gd judges it in a fight"}]}


## the clip or [t0, t1] on body B
static func of_scene(S: Scene, B: Body, t0 := 0.0, t1 := -1.0) -> Dictionary:
	var L := S.length()
	if t1 < 0.0 or t1 > L:
		t1 = L
	var r := judge(capacities(sample(S, B, maxf(t0, 0.0), t1)))
	r["ok"] = true
	r["t0"] = snappedf(maxf(t0, 0.0), 0.001)
	r["t1"] = snappedf(t1, 0.001)
	return r


## serve's who_could {card?} | {t0?, t1?}: the move INTO card N (its move and hold), or a span, or the whole clip
static func serve(m: Node, p: Dictionary) -> Dictionary:
	var S: Scene = m.S
	if S.cards.size() < 2:
		return {"ok": false, "error": "who_could needs a scene of 2+ cards: open one first"}
	var t0 := float(p.get("t0", 0.0))
	var t1 := float(p.get("t1", -1.0))
	if p.has("card"):
		var k := int(p["card"]) - 1
		if k < 1 or k >= S.cards.size():
			return {"ok": false, "error": "card %d: pick 2..%d (the move INTO the card is read; card 1 has none)" % [k + 1, S.cards.size()]}
		var ts := S.times()
		t0 = float(ts[k - 1][2])
		t1 = float(ts[k][2])
	var L := S.length()
	if t1 < 0.0 or t1 > L:
		t1 = L
	if t0 < 0.0 or t0 >= t1:
		return {"ok": false, "error": "t0 %.3f must be under t1 %.3f (the clip is %.3f s)" % [t0, t1, L]}
	var r := of_scene(S, m.ov.GB, t0, t1)
	if p.has("card"):
		r["card"] = int(p["card"])
	return r
