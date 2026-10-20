## feasible.gd - "Is this clip physically possible?" One verdict per clip: PASS / FIX (frames + reason) / IMPOSSIBLE.
## Built on the KungfuBot (PBHC) physics filter, Xie et al., NeurIPS 2025, arXiv:2506.12851, Eq. 1 and Table 3 (read 2026-10-19):
##   a frame is stable if the ground-projected distance between centre of mass and centre of pressure is under eps_stab;
##   a clip passes if its FIRST and LAST frames are stable and max(t_k+1 - t_k) < eps_N, the longest run of unstable frames.
##   Table 3: eps_stab = 0.1, eps_N = 100. The paper does not print the units: we read eps_stab as metres and eps_N as frames of
##   a 30 fps clip (3.33 s) (an assumption, stated).
## We have no force plate, so the centre of pressure is the point of the support polygon nearest the centre of mass (the best
## a body can do, since CoP is always inside the polygon): the COM-CoP distance is then the COM's distance OUTSIDE the polygon
## (Balance.read's margin, negative outside). A lower bound on the paper's distance, so the filter is lenient, never wrongly harsh.
## Added here:
##   AIRBORNE   frames with no foot down and no hand/weapon on a surface are ballistic, not unstable: the COM must follow
##              y = y0 + v t - g t^2/2 (g = 9.81) and a straight line on the floor, within BALLISTIC_TOL
##   FOOT SLIDE per contact span, how far the planted ball of the foot creeps (mm)
##   SELF-PENETRATION  the deepest Body.contacts() depth per frame
##   TIPPING    (human_limits.gd) the COM past the feet for longer than a fall from its height takes
## Findings have the Rulebook shape. Verdict: IMPOSSIBLE = the paper's rejection by a long unstable run (>= eps_N) or a flight
## that is not a parabola by more than IMPOSSIBLE_TOL; FIX = anything else found, with its frames; PASS = nothing.
class_name Feasible
extends RefCounted

const FPS := 60.0
const EPS_STAB := 0.1          # m (PBHC Table 3)
const EPS_N_FRAMES := 100      # frames at PBHC's 30 fps = 3.33 s (PBHC Table 3; unit assumed)
const EPS_N_S := EPS_N_FRAMES / 30.0
const GRAV := 9.81
const MIN_FLIGHT := 6          # frames (0.1 s) of air before a parabola is fitted
const BALLISTIC_TOL := 0.08    # m (mine): the COM may leave the parabola by this much (limbs moved in flight shift it a few cm)
const IMPOSSIBLE_TOL := 0.40   # m (mine): a "flight" this far off a parabola is a hover, not a jump
const SLIDE_FIX := 0.025       # m per contact span: Karunratanakul et al. 2023 (arXiv:2310.08580), as Rulebook.FOOT_SKATE
const PEN_FIX := 0.02          # m (mine): capsules this deep in each other (Rulebook.PROP_FAIL is 2 cm)
const DOWN_Y := 0.05           # m: the ball of the foot this low and slow = a planted contact (Rulebook.FOOT_DOWN, Karunratanakul 2023)
const STILL := 0.005          # m per 60 fps frame (0.3 m/s): Rulebook.FOOT_STILL; a planted foot moves slower than this along the floor


## the clip at 60 fps: per frame the COM, the margin outside the support (Balance.read), what is down / holding, the
## foot balls, the deepest self-penetration and its pair, and the support polygon
static func sample(S: Scene, B: Body) -> Dictionary:
	var n := int(ceil(S.length() * FPS)) + 1
	var was_stepped := S.stepped
	S.stepped = false
	var out := {"n": n, "t": [], "com": [], "margin": [], "down": [], "sup": [], "poly": [], "ball_l": [], "ball_r": [],
		"pen": [], "pen_pair": []}
	var mk := func(_i: int, t: float) -> Dictionary:
		FrameMemo.pose(S, B, t)
		var bal := Balance.read(B)
		var deep := 0.0
		var pair := ""
		for c in B.contacts():
			if float(c[2]) > deep:
				deep = float(c[2])
				pair = "%s/%s" % [c[0], c[1]]
		return {"t": t, "com": bal["com"], "margin": float(bal["margin"]), "down": (bal["down"] as Array).size() > 0, "sup": HumanLimits.supported(B),
			"poly": bal["poly"], "bl": B.P["ball_l"], "br": B.P["ball_r"], "pen": deep, "pp": pair}
	var recs: Array = FrameMemo.frames("fz", S, B, n, FPS, mk)
	for i in n:
		var r: Dictionary = recs[i]
		out["t"].append(i / FPS if i / FPS < S.length() else S.length())
		out["com"].append(r["com"])
		out["margin"].append(r["margin"])
		out["down"].append(r["down"])
		out["sup"].append(r["sup"])
		out["poly"].append(r["poly"])
		out["ball_l"].append(r["bl"])
		out["ball_r"].append(r["br"])
		out["pen"].append(r["pen"])
		out["pen_pair"].append(r["pp"])
	S.stepped = was_stepped
	return out


static func airborne(sm: Dictionary, i: int) -> bool:
	return not bool(sm["down"][i]) and not bool(sm["sup"][i])


## unstable per PBHC Eq. 1 (grounded frames only): the COM more than EPS_STAB outside what carries it
static func unstable(sm: Dictionary, i: int) -> bool:
	return not airborne(sm, i) and float(sm["margin"][i]) < -EPS_STAB and not bool(sm["sup"][i])


static func _f(sev: String, t: float, rule: String, msg: String, v := 0.0) -> Dictionary:
	return Rulebook._f(sev, t, rule, msg, v)


static func _fr(sm: Dictionary, a: int, b: int, fps: int) -> String:
	return "frames %d-%d (%.2f-%.2f s)" % [roundi(float(sm["t"][a]) * fps), roundi(float(sm["t"][b]) * fps), sm["t"][a], sm["t"][b]]


## PBHC whole-clip rule: first and last frame stable, and no run of unstable frames of eps_N or more
static func rule_balance(sm: Dictionary, fps: int) -> Array:
	var out := []
	var n: int = sm["n"]
	for end in [0, n - 1]:
		if unstable(sm, end):
			out.append(_f("FAIL", sm["t"][end], "FEASIBLE BALANCE", "the %s frame (%s) is not stable: the centre of mass is %.0f cm outside the feet (KungfuBot: a clip must start and end stable, bar %.0f cm)." % [
				"first" if end == 0 else "last", _fr(sm, end, end, fps), -float(sm["margin"][end]) * 100.0, EPS_STAB * 100.0], -float(sm["margin"][end])))
			out[-1]["t1"] = sm["t"][end]
	var i := 0
	while i < n:
		if unstable(sm, i):
			var a := i
			var far := 0.0
			while i < n and unstable(sm, i):
				far = maxf(far, -float(sm["margin"][i]))
				i += 1
			var b := i - 1
			var dur := float(b - a + 1) / FPS
			if dur >= EPS_N_S:
				out.append(_f("FAIL", sm["t"][a], "FEASIBLE BALANCE", "%s: the centre of mass stays up to %.0f cm outside the feet for %.1f s; KungfuBot rejects a clip with an unstable run of %d frames (%.1f s) or more." % [
					_fr(sm, a, b, fps), far * 100.0, dur, EPS_N_FRAMES, EPS_N_S], far))
				out[-1]["t1"] = sm["t"][b]
				out[-1]["impossible"] = true
		else:
			i += 1
	return out


## flights: runs of AIRBORNE frames; the COM must follow the parabola. Vertical: y + g t^2/2 is a straight line in t;
## horizontal: x and z are straight lines. Least squares line fits; the worst miss in metres is the test
static func rule_flight(sm: Dictionary, fps: int) -> Array:
	var out := []
	var n: int = sm["n"]
	var i := 0
	while i < n:
		if airborne(sm, i):
			var a := i
			while i < n and airborne(sm, i):
				i += 1
			var b := i - 1
			if b - a + 1 < MIN_FLIGHT:
				continue
			var worst := _parabola_miss(sm, a, b)
			if worst > BALLISTIC_TOL:
				var imp := worst > IMPOSSIBLE_TOL
				out.append(_f("FAIL", sm["t"][a], "FEASIBLE FLIGHT", "%s: in the air the centre of mass leaves a free-fall path (g = %.2f m/s^2) by up to %.0f cm (bar %.0f cm): nothing pushes off in the air, so it cannot %s." % [
					_fr(sm, a, b, fps), GRAV, worst * 100.0, BALLISTIC_TOL * 100.0, "float or swerve like this" if imp else "move like this"], worst))
				out[-1]["t1"] = sm["t"][b]
				if imp:
					out[-1]["impossible"] = true
		else:
			i += 1
	return out


## worst distance (m) of the COM from its best-fit ballistic path over frames a..b
static func _parabola_miss(sm: Dictionary, a: int, b: int) -> float:
	var m := b - a + 1
	var ts := []
	var ys := []
	var xs := []
	var zs := []
	for k in range(a, b + 1):
		var t: float = float(k - a) / FPS
		var c: Vector3 = sm["com"][k]
		ts.append(t)
		ys.append(c.y + 0.5 * GRAV * t * t)
		xs.append(c.x)
		zs.append(c.z)
	var worst := 0.0
	for v in [ys, xs, zs]:
		var tm := 0.0
		var vm := 0.0
		for k in m:
			tm += ts[k]
			vm += v[k]
		tm /= m
		vm /= m
		var sxx := 0.0
		var sxy := 0.0
		for k in m:
			sxx += (ts[k] - tm) * (ts[k] - tm)
			sxy += (ts[k] - tm) * (v[k] - vm)
		var slope := sxy / maxf(sxx, 1e-12)
		for k in m:
			worst = maxf(worst, absf(v[k] - (vm + slope * (ts[k] - tm))))
	return worst


## FOOT SLIDE per contact span: a ball that is low and not fast, its farthest creep from where the span began
static func rule_slide(sm: Dictionary, fps: int) -> Array:
	var out := []
	var n: int = sm["n"]
	for k in ["ball_l", "ball_r"]:
		var s: Array = sm[k]
		var i := 1
		while i < n:
			if not _planted(s, i):
				i += 1
				continue
			var a := i - 1
			var p0: Vector3 = s[a]
			var far := 0.0
			while i < n and _planted(s, i):
				var d: Vector3 = (s[i] as Vector3) - p0
				far = maxf(far, Vector2(d.x, d.z).length())
				i += 1
			if far > SLIDE_FIX:
				out.append(_f("FAIL", sm["t"][a], "FEASIBLE SLIDE", "%s: the %s foot slides %.0f mm while planted (bar %.0f mm per contact; Karunratanakul 2023). Feet do not skate on the floor." % [
					_fr(sm, a, i - 1, fps), "left" if k == "ball_l" else "right", far * 1000.0, SLIDE_FIX * 1000.0], far))
				out[-1]["t1"] = sm["t"][i - 1]
	return out


static func _planted(s: Array, i: int) -> bool:
	var p: Vector3 = s[i]
	var d: Vector3 = p - (s[i - 1] as Vector3)
	return p.y < DOWN_Y and Vector2(d.x, d.z).length() < STILL


## SELF-PENETRATION: runs of frames with Body.contacts() deeper than PEN_FIX
static func rule_pen(sm: Dictionary, fps: int) -> Array:
	var out := []
	var n: int = sm["n"]
	var i := 0
	while i < n:
		if float(sm["pen"][i]) > PEN_FIX:
			var a := i
			var deep := 0.0
			var pair := ""
			while i < n and float(sm["pen"][i]) > PEN_FIX:
				if float(sm["pen"][i]) > deep:
					deep = float(sm["pen"][i])
					pair = sm["pen_pair"][i]
				i += 1
			out.append(_f("FAIL", sm["t"][a], "FEASIBLE PENETRATION", "%s: the body passes through itself, %s %.0f mm deep (bar %.0f mm)." % [
				_fr(sm, a, i - 1, fps), pair.replace("_", " "), deep * 1000.0, PEN_FIX * 1000.0], deep))
			out[-1]["t1"] = sm["t"][i - 1]
		else:
			i += 1
	return out


## everything plus the verdict: {"verdict": "PASS"|"FIX"|"IMPOSSIBLE", "findings": [...], "sm": sample}
static func check(S: Scene, B: Body, sm := {}) -> Dictionary:
	if S.cards.size() < 2:
		return {"verdict": "PASS", "findings": [], "sm": {}}
	if sm.is_empty():
		sm = sample(S, B)
	var fps: int = S.fps
	var fs := []
	fs += rule_balance(sm, fps)
	fs += rule_flight(sm, fps)
	fs += rule_slide(sm, fps)
	fs += rule_pen(sm, fps)
	var n: int = sm["n"]
	var hl := {"t": sm["t"], "margin": sm["margin"], "h": [], "down": sm["down"], "sup": sm["sup"], "cv": []}
	for i in n:
		hl["h"].append((sm["com"][i] as Vector3).y)
		var c0: Vector3 = sm["com"][maxi(i - 1, 0)]
		var c1: Vector3 = sm["com"][mini(i + 1, n - 1)]
		hl["cv"].append(Vector2(c1.x - c0.x, c1.z - c0.z).length() * FPS / float(maxi(mini(i + 1, n - 1) - maxi(i - 1, 0), 1)))
	for f in HumanLimits.rule_tipping(hl):
		var body_msg: String = String(f["msg"])
		body_msg = body_msg.substr(body_msg.find(": ") + 2)   # drop its own "a-b s: " lead, the frames lead instead
		f["msg"] = _fr(sm, roundi(float(f["t"]) * FPS), roundi(float(f["t1"]) * FPS), fps) + ": " + body_msg
		fs.append(f)
	var imp := false
	for f in fs:
		imp = imp or bool(f.get("impossible", false))
	fs.sort_custom(func(x, y): return x["t"] < y["t"])
	var verdict := "IMPOSSIBLE" if imp else ("FIX" if not fs.is_empty() else "PASS")
	return {"verdict": verdict, "findings": fs, "sm": sm}


## the verdict as one Check-panel finding (FIX / IMPOSSIBLE only; PASS adds none): it jumps to the first bad frame
static func verdict_finding(S: Scene, r: Dictionary) -> Array:
	if r["verdict"] == "PASS":
		return []
	var fs: Array = r["findings"]
	var why := ""
	for f in fs:
		why += "\n  - " + str(f["msg"])
	var f0 := _f("FAIL", fs[0]["t"], "FEASIBLE",
		"%s - a body cannot do this clip as it stands. %d problem%s:%s" % [r["verdict"], fs.size(), "" if fs.size() == 1 else "s", why])
	f0["card"] = Rulebook.card_at(S, f0["t"])
	return [f0]
