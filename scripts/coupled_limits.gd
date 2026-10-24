## coupled_limits.gd - COUPLED LIMITS (docs/INNOVATIONS.md N028). data/body_limits.json limits one joint at a time, but
## three muscles of the leg cross TWO joints, so how far one joint goes depends on the other:
##   HAMSTRINGS   (hip extensors + knee flexors): with the knee straight the hip flexes only as far as the straight-leg
##                raise; bend the knee and the hamstrings slacken, so the hip goes on to its own stop (the table's 120)
##   GASTROCNEMIUS (knee flexor + ankle plantarflexor): with the knee straight the ankle dorsiflexes less; by 20 deg of knee
##                flexion the gastrocnemius no longer restrains it (Baumbach 2014)
##   RECTUS FEMORIS (hip flexor + knee extensor): with the knee bent the hip extends less (the Thomas test)
## Each coupling is a CURVE: the bar on one joint's bend as a piecewise-linear function of the other joint's bend, built from
## the cited points below and interpolated (continuous; monotonic where the physiology says so: a bent knee never lowers
## the hip's flexion bar, never raises its extension bar). Numbers, sources and DOIs: docs/research/COUPLED_LIMITS.md.
## Kine's angles: thigh bend + = hip flexion (- = extension), calf bend + = knee flexion (0 = straight), foot bend + = toes up
## (dorsiflexion), all relative to the parent part, so the hip angle is relative to the PELVIS. The clinical straight-leg
## raise is read against the table and includes some pelvic tilt: our pelvis-relative reading of the same number is lenient.
## Severity: WARN past the cited mean of healthy adults ("most people cannot"), FAIL past the flexibility-trained group
## (hamstrings: gymnasts) or mean + 2 SD (the others). Where a FAIL bar lies past the one-joint table it cannot fire: the table
## clamp already stops the pose, and the coupled rule says so instead of pretending.
## Wired in: Check's human-limit rules (HumanLimits.findings, rule "COUPLED LIMIT", on with "could a human do this?"),
## Feasible.check (FAIL only: a WARN is a trained person's range, not an impossible clip), the opt-in clamp
## (Body.coupled_clamp, off by default: Nick's saved poses would change under a default-on clamp) and serve `limits`.
## Shoulder/elbow (biceps) and wrist/finger (finger flexors' tenodesis) couplings: no opened source with numbers, left out.
class_name CoupledLimits
extends RefCounted

const FPS := 60.0
const TOL := 0.5      # deg: a bar crossed by less than this is the joint's own rounding, not a finding (Body.at_limit's 0.5)

# --- HAMSTRINGS: hip flexion with the knee straight (passive straight-leg raise, PSLR) ---
## PSLR of healthy, moderately active university students (13 F / 19 M, 25 y), inertial sensor, other leg strapped: the four
## sessions' baselines 86.7-91.1 deg, SD ~22 (Thomas et al. 2022, BMC Sports Sci Med Rehabil 14:202, doi:10.1186/s13102-022-00599-8,
## Table: T0 87.1 / 90.1 / 89.7 / 91.1 right leg). Female team-sport athletes, pelvis strapped, camera: 91.0 +- 7.2 and 92.4 +- 6.9
## (Donti et al. 2020, Sports 8(3):28, doi:10.3390/sports8030028). Rounded to 90
const HAM_STRAIGHT := 90.0
## flexibility-trained: artistic and rhythmic gymnasts' PSLR 140.9 +- 20.4 and 141.8 +- 20.3 (Donti 2020, same test): the FAIL bar
const HAM_TRAINED := 141.0
## HEURISTIC (ours): each degree of knee flexion buys this many degrees of hip flexion before the hamstrings bind. A muscle
## crossing two joints lengthens by r_hip dHip - r_knee dKnee; the ratio of the hamstrings' knee to hip moment arms is taken
## as about one half (a textbook proportion; no moment-arm paper was opened for Kine). Check against data: the active knee
## extension test (hip held at 90) leaves the knee 24.9 +- 9.3 deg short of straight (Hamid et al. 2013, J Phys Ther Sci 25:957,
## doi:10.1589/jpts.25.957, 16 sedentary adults, no warm-up): this curve lets those people's hip reach 90 with any knee bend,
## so it is LENIENT by about 12 deg there (stated, not fitted)
const HAM_SLOPE := 0.5
## the hip's own stop with the knee bent: data/body_limits.json thigh bend max (UNVERIFIED there: AAOS / Soucie, not opened)
const HIP_FLEX_MAX := 120.0

# --- GASTROCNEMIUS: ankle dorsiflexion against knee flexion (Baumbach et al. 2014, BMC Musculoskelet Disord 15:246,
# doi:10.1186/1471-2474-15-246, PMC4118219, Table 2: 20 healthy adults, goniometer, knee braced at 0/20/30/45/60/75 deg) ---
## weight-bearing (a lunge: the case a standing body is in), pooled both legs: knee straight 25 +- 6 deg, knee 75 deg 39 +- 7;
## the 20-deg row reads 39 (right) / 37 (left). Non-weight-bearing (foot in the air) is lower: 4 +- 7 straight, 20 +- 9 bent;
## we use the weight-bearing row (lenient for a foot in the air, stated)
const GAS_STRAIGHT := 25.0
const GAS_BENT := 39.0
## "knee flexion beyond 20 deg could not further increase ADF" (Baumbach 2014, results): the knee angle where the
## gastrocnemius stops restraining the ankle. The curve is linear between 0 and 20 deg (the paper has no point in between)
const GAS_FREE_KNEE := 20.0
const GAS_SD := 7.0   # deg: the weight-bearing SD at 75 deg (6 straight); FAIL = mean + 2 SD

# --- RECTUS FEMORIS: hip extension against knee flexion (the modified Thomas test) ---
## the thigh 10.60 +- 9.61 deg below the table's line (hip extension), 300 recreational athletes, digital inclinometer, knee
## hanging free (Ferber et al. 2010, J Athl Train 45(4):344, doi:10.4085/1062-6050-45.4.344, PMC2902027). In the same test the
## hanging knee sits at 50 +- 12 deg (Peeler & Anderson 2008, J Athl Train 43(5):470, doi:10.4085/1062-6050-43.5.470, PMC2547866):
## the point (knee 50, hip -10.6). A gravity hang, not an end range pushed by a tester: strict, stated
const RECT_KNEE := 50.0
const RECT_EXT := -10.6
const RECT_SD := 9.61
## HEURISTIC: Kendall's pass criterion as Peeler 2008 quotes it: thigh flat on the table (hip 0) with the knee at 90 deg.
## A clinical cut-off, not a measured mean. Past 90 deg of knee flexion no source was opened: the bar is held at 0 (lenient)
const RECT_KNEE_FLAT := 90.0
## the hip's extension stop with the knee straight: data/body_limits.json thigh bend min (UNVERIFIED there)
const HIP_EXT_MAX := -25.0
const KNEE_MAX := 145.0   # data/body_limits.json calf bend max: where every curve ends

## one coupling: the bar on `joint`'s bend ("max" = it may not go above, "min" = not below) as a curve over `other`'s bend.
## curve = [[other deg, bar deg], ...] increasing in other: the cited points. warn_shift (default 0) moves it to the WARN bar,
## fail_shift to the FAIL one
static func couplings() -> Array:
	return [
		{"id": "hamstrings", "joint": "thigh", "other": "calf", "side": "max", "muscle": "hamstrings",
			"curve": [[0.0, HAM_STRAIGHT], [(HIP_FLEX_MAX - HAM_STRAIGHT) / HAM_SLOPE, HIP_FLEX_MAX], [KNEE_MAX, HIP_FLEX_MAX]],
			"fail_shift": HAM_TRAINED - HAM_STRAIGHT, "monotonic": "up",
			"what": "hip flexion", "with": "knee flexion",
			"why": "the hamstrings run from the pelvis to below the knee: a straight knee keeps them long, so the hip flexes only as far as a straight-leg raise",
			"fix_hint": "lower the leg",
			"src": "straight-leg raise %.0f deg in healthy adults (Thomas et al. 2022; Donti et al. 2020 team-sport athletes 91), gymnasts %.0f (Donti 2020); %.1f deg of hip per deg of knee bend is ours" % [HAM_STRAIGHT, HAM_TRAINED, HAM_SLOPE],
			"url": "https://doi.org/10.1186/s13102-022-00599-8",
			"bars": ["CoupledLimits.HAM_STRAIGHT", "CoupledLimits.HAM_TRAINED", "CoupledLimits.HAM_SLOPE", "CoupledLimits.HIP_FLEX_MAX"]},
		{"id": "gastrocnemius", "joint": "foot", "other": "calf", "side": "max", "muscle": "gastrocnemius",
			"curve": [[0.0, GAS_STRAIGHT], [GAS_FREE_KNEE, GAS_BENT], [KNEE_MAX, GAS_BENT]],
			"fail_shift": 2.0 * GAS_SD, "monotonic": "up",
			"what": "ankle dorsiflexion", "with": "knee flexion",
			"why": "the gastrocnemius runs from above the knee to the heel: a straight knee keeps it long, so the toes come up less",
			"fix_hint": "point the toes down",
			"src": "weight-bearing dorsiflexion %.0f deg knee straight, %.0f deg knee bent 20 deg or more (Baumbach et al. 2014, 20 healthy adults)" % [GAS_STRAIGHT, GAS_BENT],
			"url": "https://doi.org/10.1186/1471-2474-15-246",
			"bars": ["CoupledLimits.GAS_STRAIGHT", "CoupledLimits.GAS_BENT", "CoupledLimits.GAS_FREE_KNEE", "CoupledLimits.GAS_SD"]},
		{"id": "rectus femoris", "joint": "thigh", "other": "calf", "side": "min", "muscle": "rectus femoris",
			"curve": [[0.0, HIP_EXT_MAX], [RECT_KNEE, RECT_EXT], [RECT_KNEE_FLAT, 0.0], [KNEE_MAX, 0.0]],
			# the Thomas numbers are where a thigh HANGS under gravity, not an end range pushed by a tester: half of all people hang
			# past the mean, so being past it says nothing. Only past mean - 2 SD (outside 97.5 % of the hang) is flagged, and then
			# as FAIL. Found by the run template (tools/template_plans.gd): its swing leg at hip -14 / knee 75 would WARN at the mean.
			"warn_shift": -2.0 * RECT_SD, "fail_shift": -2.0 * RECT_SD, "monotonic": "up",
			"what": "hip extension", "with": "knee flexion",
			"why": "the rectus femoris runs from the pelvis over the front of the knee: a bent knee keeps it long, so the thigh goes back less",
			"fix_hint": "bring the thigh forward",
			"src": "modified Thomas test: hip %.1f deg (extension) with the knee hanging at %.0f deg (Ferber et al. 2010; Peeler & Anderson 2008); thigh flat with the knee at 90 (Kendall's criterion, via Peeler 2008)" % [RECT_EXT, RECT_KNEE],
			"url": "https://doi.org/10.4085/1062-6050-45.4.344",
			"bars": ["CoupledLimits.RECT_EXT", "CoupledLimits.RECT_KNEE", "CoupledLimits.RECT_SD", "CoupledLimits.RECT_KNEE_FLAT", "CoupledLimits.HIP_EXT_MAX"]},
	]


## the curve's value at x: piecewise linear between its points, held flat past either end (continuous by construction)
static func at(curve: Array, x: float) -> float:
	if x <= float(curve[0][0]):
		return float(curve[0][1])
	for i in range(1, curve.size()):
		var x0: float = curve[i - 1][0]
		var x1: float = curve[i][0]
		if x <= x1:
			var u := (x - x0) / maxf(x1 - x0, 1e-9)
			return lerpf(float(curve[i - 1][1]), float(curve[i][1]), u)
	return float(curve[-1][1])


## the smallest x where a rising curve reaches y (the knee bend a hip angle needs); INF when it never does
static func x_for(curve: Array, y: float) -> float:
	if y <= float(curve[0][1]):
		return float(curve[0][0])
	for i in range(1, curve.size()):
		var y0: float = curve[i - 1][1]
		var y1: float = curve[i][1]
		if y <= y1 and y1 > y0:
			return lerpf(float(curve[i - 1][0]), float(curve[i][0]), (y - y0) / (y1 - y0))
	return INF


## the largest x where a rising curve is still <= y (for a "min" bar: the most knee bend a hip extension allows); -INF never
static func x_upto(curve: Array, y: float) -> float:
	if y >= float(curve[-1][1]):
		return INF
	if y < float(curve[0][1]):
		return -INF
	for i in range(curve.size() - 1, 0, -1):
		var y0: float = curve[i - 1][1]
		var y1: float = curve[i][1]
		if y >= y0 and y < y1:
			return lerpf(float(curve[i - 1][0]), float(curve[i][0]), (y - y0) / (y1 - y0))
	return float(curve[0][0])


static func shifted(c: Dictionary, level: String) -> Array:
	var sh: float = c["fail_shift"] if level == "fail" else float(c.get("warn_shift", 0.0))
	return (c["curve"] as Array).map(func(p): return [float(p[0]), float(p[1]) + sh])


## "thigh_r" -> ["thigh", "_r"]; "" side for a centre joint
static func split(j: String) -> Array:
	for sd in ["_l", "_r"]:
		if j.ends_with(sd):
			return [j.left(j.length() - 2), sd]
	return [j, ""]


## what one pose breaks: {coupling id, joint, other, angle, other_angle, warn bar, fail bar, sev, over, knee_needed}. ang = joint ->
## Vector3 (or {bend: x}); only the legs are coupled
static func check_pose(ang: Dictionary) -> Array:
	var out := []
	for sd in ["_l", "_r"]:
		for c in couplings():
			var j: String = c["joint"] + sd
			var o: String = c["other"] + sd
			if not ang.has(j) or not ang.has(o):
				continue
			var a := _bend(ang[j])
			var x := _bend(ang[o])
			var wc := shifted(c, "warn")
			var w := at(wc, x)
			var f := at(shifted(c, "fail"), x)
			var over := (a - w) if c["side"] == "max" else (w - a)
			if over <= TOL:
				continue
			var past_fail := (a - f) if c["side"] == "max" else (f - a)
			var need := x_for(wc, a) if c["side"] == "max" else x_upto(wc, a)
			out.append({"coupling": c["id"], "joint": j, "other": o, "angle": a, "other_angle": x, "warn": w, "fail": f,
				"sev": "FAIL" if past_fail > TOL else "WARN", "over": over, "other_needed": need, "c": c})
	return out


static func _bend(v: Variant) -> float:
	if v is Vector3:
		return (v as Vector3).x
	if v is Dictionary:
		return float((v as Dictionary).get("bend", 0.0))
	if v is Array:
		return float((v as Array)[0])
	return float(v)


static func _side_word(sd: String) -> String:
	return "right" if sd == "_r" else "left"


## one violation in words: what, how far past, why (the muscle), the source, and the two ways out
static func say(v: Dictionary) -> String:
	var c: Dictionary = v["c"]
	var sd: String = split(String(v["joint"]))[1]
	var x: float = v["other_angle"]
	var knee := "the knee straight (%.0f deg)" % x if x < 5.0 else "the knee bent %.0f deg" % x
	var lead := "%s %s %.0f deg with %s" % [_side_word(sd), c["what"], absf(float(v["angle"])), knee]
	var s := "%s: past the %s limit (%.0f deg at this knee angle, %.0f deg over): %s. Source: %s." % [lead, c["muscle"], absf(float(v["warn"])), float(v["over"]), c["why"], c["src"]]
	var need: float = v["other_needed"]
	var to_bar := "%s to %.0f deg" % [c["fix_hint"], absf(float(v["warn"]))]
	if c["side"] == "max" and need != INF and need <= KNEE_MAX:
		s += " To pass: bend the knee to %.0f deg, or %s." % [need, to_bar]
	elif c["side"] == "min" and need != -INF:
		s += " To pass: %s the knee to %.0f deg, or %s." % ["straighten" if maxf(need, 0.0) < x else "keep", maxf(need, 0.0), to_bar]
	else:
		s += " To pass: %s." % to_bar
	if v["sev"] == "WARN":
		s += " (WARN: past most adults; a flexibility-trained body reaches %.0f deg.)" % absf(float(v["fail"]))
	return s


## the scene at 60 fps: per frame the legs' bends (thigh, calf, foot each side)
static func sample(S: Scene, B: Body) -> Dictionary:
	var n := int(ceil(S.length() * FPS)) + 1
	var was_stepped := S.stepped
	S.stepped = false
	var mk := func(_i: int, t: float) -> Dictionary:
		FrameMemo.pose(S, B, t)
		var row := {}
		for sd in ["_l", "_r"]:
			for p in ["thigh", "calf", "foot"]:
				row[p + sd] = (B.ang[p + sd] as Vector3).x
		return row
	var rows: Array = FrameMemo.frames("cpl", S, B, n, FPS, mk)
	S.stepped = was_stepped
	var t := []
	for i in n:
		t.append(minf(i / FPS, S.length()))
	return {"n": n, "t": t, "rows": rows}


## Check findings (Rulebook shape): one per run of frames per coupling and side, its worst frame quoted. only_fail: Feasible's use
static func findings(S: Scene, B: Body, sm := {}, only_fail := false) -> Array:
	if S.cards.size() < 2:
		return []
	if sm.is_empty():
		sm = sample(S, B)
	var out := []
	var runs := {}   # "coupling|joint" -> {a, b, worst violation, t at worst, fail}
	var n: int = sm["n"]
	for i in n + 1:
		var seen := {}
		if i < n:
			for v in check_pose(sm["rows"][i]):
				var k: String = "%s|%s" % [v["coupling"], v["joint"]]
				seen[k] = true
				if not runs.has(k):
					runs[k] = {"a": i, "b": i, "w": v, "ti": i}
				runs[k]["b"] = i
				if float(v["over"]) > float(runs[k]["w"]["over"]):
					runs[k]["w"] = v
					runs[k]["ti"] = i
		for k in runs.keys():
			if seen.has(k):
				continue
			var r: Dictionary = runs[k]
			runs.erase(k)
			var w: Dictionary = r["w"]
			if only_fail and w["sev"] != "FAIL":
				continue
			var t0: float = sm["t"][r["a"]]
			var t1: float = sm["t"][r["b"]]
			var f := Rulebook._f(String(w["sev"]), t0, "COUPLED LIMIT", "%.2f-%.2f s (worst at %.2f s): %s" % [t0, t1, sm["t"][r["ti"]], say(w)], float(w["over"]))
			f["t1"] = t1
			f["joint"] = w["joint"]
			f["coupling"] = w["coupling"]
			out.append(f)
	for f in out:
		f["card"] = Rulebook.card_at(S, f["t"])
	out.sort_custom(func(x, y): return x["t"] < y["t"])
	return out


## OPT-IN CLAMP (Body.coupled_clamp: 0 off, 1 = the healthy-adult WARN curves, 2 = the trained FAIL curves): keep joint j's
## new bend inside its couplings with the OTHER joint as it stands now. The thigh and foot are bounded by the knee; the knee
## by the thigh and the foot (the curves read backwards)
static func clamp(B: Body, j: String, v: Vector3) -> Vector3:
	var lvl := "fail" if B.coupled_clamp >= 2 else "warn"
	var ps := split(j)
	var part: String = ps[0]
	var sd: String = ps[1]
	if sd == "" or not part in ["thigh", "calf", "foot"]:
		return v
	for c in couplings():
		var cv := shifted(c, lvl)
		if part == c["joint"]:
			var x: float = (B.ang[c["other"] + sd] as Vector3).x
			var bar := at(cv, x)
			v.x = minf(v.x, bar) if c["side"] == "max" else maxf(v.x, bar)
		elif part == c["other"]:
			var a: float = (B.ang[c["joint"] + sd] as Vector3).x
			if c["side"] == "max":
				var need := x_for(cv, a)
				if need != INF:
					v.x = maxf(v.x, need)
			else:
				var most := x_upto(cv, a)
				if most != INF and most != -INF:
					v.x = minf(v.x, most)
	return v


## why set_ang_safe stopped joint j short (the coupled clamp, not the table): {} when the coupling did not cut it
static func stop(B: Body, j: String, asked: Vector3, got: Vector3) -> Dictionary:
	var L: Vector2 = B.lim[j]["bend"]
	var table := clampf(asked.x, L.x, L.y)
	if absf(table - got.x) <= TOL:
		return {}
	var sd: String = split(j)[1]
	var ang := {}
	for p in ["thigh", "calf", "foot"]:
		ang[p + sd] = B.ang[p + sd]
	ang[j] = Vector3(table, asked.y, asked.z)
	var vs := check_pose(ang)
	return {"kind": "coupled", "joint": j, "axis": "bend", "at": got.x, "asked": asked.x,
		"why": say(vs[0]) if not vs.is_empty() else "a two-joint muscle (CoupledLimits)"}


## the effective range of a joint's bend given the other joints' angles (serve `limits`). other: joint -> bend deg (or
## {bend}); a missing other joint is read from the body as it stands
static func effective(B: Body, j: String, other := {}) -> Dictionary:
	var L: Dictionary = B.lim[j]
	var out := {"joint": j, "table": {"bend": [L["bend"].x, L["bend"].y], "side": [L["side"].x, L["side"].y], "twist": [L["twist"].x, L["twist"].y]},
		"bend": {"warn": [L["bend"].x, L["bend"].y], "fail": [L["bend"].x, L["bend"].y]}, "couplings": [],
		"table_source": "data/body_limits.json (one joint at a time; UNVERIFIED there: AAOS / Soucie quoted, not opened)"}
	var ps := split(j)
	var part: String = ps[0]
	var sd: String = ps[1]
	var get_b := func(name: String) -> float:
		if other.has(name):
			return _bend(other[name])
		var bare: String = split(name)[0]
		if other.has(bare):
			return _bend(other[bare])
		return (B.ang[name] as Vector3).x
	for c in couplings():
		if sd == "" or (part != c["joint"] and part != c["other"]):
			continue
		var row := {"muscle": c["muscle"], "why": c["why"], "source": c["src"], "url": c["url"], "trust": trust_of(c),
			"curve": c["curve"], "bars": c["bars"]}
		for lvl in ["warn", "fail"]:
			var cv := shifted(c, lvl)
			var r: Array = out["bend"][lvl]
			if part == c["joint"]:
				var x: float = get_b.call(c["other"] + sd)
				var bar := at(cv, x)
				if c["side"] == "max":
					r[1] = minf(r[1], bar)
				else:
					r[0] = maxf(r[0], bar)
				row["given"] = {c["other"] + sd: x}
				row[lvl] = bar
			else:
				var a: float = get_b.call(c["joint"] + sd)
				row["given"] = {c["joint"] + sd: a}
				if c["side"] == "max":
					var need := x_for(cv, a)
					r[0] = maxf(r[0], need if need != INF else r[1] + 1.0)
					row[lvl] = need if need != INF else null
				else:
					var most := x_upto(cv, a)
					if most == -INF:
						r[1] = r[0] - 1.0
					elif most != INF:
						r[1] = minf(r[1], most)
					row[lvl] = most if absf(most) != INF else null
		var bt: Vector2 = L["bend"]
		var wv: Variant = row.get("warn")
		row["binds"] = wv != null and ((part == c["joint"] and ((c["side"] == "max" and float(wv) < bt.y - TOL) or (c["side"] == "min" and float(wv) > bt.x + TOL)))
			or (part == c["other"] and ((c["side"] == "max" and float(wv) > bt.x + TOL) or (c["side"] == "min" and float(wv) < bt.y - TOL))))
		row["say"] = _explain(c, part, row, bt)
		out["couplings"].append(row)
	var rw: Array = out["bend"]["warn"]
	out["possible"] = rw[0] <= rw[1]
	var lines := []
	for r in out["couplings"]:
		lines.append(r["say"])
	out["say"] = "%s bend: table %.0f..%.0f deg; with the other joints as given, a healthy adult %.0f..%.0f, a trained body %.0f..%.0f. %s" % [
		j, L["bend"].x, L["bend"].y, rw[0], rw[1], out["bend"]["fail"][0], out["bend"]["fail"][1], " ".join(lines) if not lines.is_empty() else "No two-joint muscle couples this joint."]
	return out


static func _explain(c: Dictionary, part: String, row: Dictionary, bt: Vector2) -> String:
	var g: Dictionary = row["given"]
	var gk: String = g.keys()[0]
	var wv: Variant = row.get("warn")
	if wv == null:
		return "%s: no knee angle gives that %s for a healthy adult." % [c["muscle"], c["what"]]
	var bind := " (tighter than the table)" if row["binds"] else " (the table is tighter: the coupling does not bind here)"
	if part == c["joint"]:
		return "%s: with %s at %.0f deg, %s %s %.0f deg%s; %s. Source: %s." % [c["muscle"], gk, float(g[gk]), c["what"],
			"at most" if c["side"] == "max" else "at least", absf(float(wv)), bind, c["why"], c["src"]]
	return "%s: with %s at %.0f deg, knee flexion %s %.0f deg%s; %s. Source: %s." % [c["muscle"], gk, float(g[gk]),
		"at least" if c["side"] == "max" else "at most", float(wv), bind, c["why"], c["src"]]


## a coupling's trust: the weakest of its own bars (the one-joint table's rows, *_MAX, are the table's question, not the curve's)
static func trust_of(c: Dictionary) -> String:
	return Trust.weakest((c["bars"] as Array).filter(func(n): return not String(n).ends_with("_MAX")).map(func(n): return Trust.row(n)))


## serve's `limits {joint, other_angles?}`
static func serve(m: Node, p: Dictionary) -> Dictionary:
	var j := WhatIf.joint_name(String(p.get("joint", "")))
	if j == "":
		return {"ok": false, "error": "limits needs {\"joint\": \"right hip\" | \"thigh_r\" | \"calf_l\" | \"foot_r\", \"other_angles\"?: {\"calf_r\": 0}} (got '%s')" % p.get("joint", "")}
	var oa: Variant = p.get("other_angles", {})
	if not (oa is Dictionary):
		return {"ok": false, "error": "other_angles must be an object: {\"calf_r\": 60} (degrees of bend) or {\"knee\": 60}"}
	var named := {}
	for k in oa:
		var jn := WhatIf.joint_name(String(k))
		if jn == "" and String(k).to_lower() in ["knee", "hip", "ankle"]:
			jn = {"knee": "calf", "hip": "thigh", "ankle": "foot"}[String(k).to_lower()] + split(j)[1]
		if jn == "":
			return {"ok": false, "error": "other_angles: no joint '%s'" % k}
		named[jn] = oa[k]
	var r := effective(m.B, j, named)
	r["ok"] = true
	return r
