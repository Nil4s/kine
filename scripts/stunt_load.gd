## stunt_load.gd - "what load would a stunt performer take?" (ROADMAP 24). A separate report, opened only by
## "Check: stunt load report" (main.gd). Every finding is sev "NOTE" (never MUST FIX). Bars and sources: docs/research/STUNT_LOAD.md
##   LANDING LOAD    the centre of mass's touchdown: impact speed v (from the last airborne frame) and the stop d (the drop to
##                   the lowest point before it rises again). Mean stopping deceleration a = v^2 / (2 d) (constant-deceleration
##                   model, ours), peak vGRF = 1 + a / g in body weights. Bar: 3-7 BW (drop landing, brief's cite, NOT verified)
##   KNEE VALGUS     the frontal-plane valgus angle of each knee in the touchdown window (0.1 s, ours). Bar 10 deg (ours)
##   SPINE COMPRESS  L5/S1 compression, a two-term static estimate (ours): upper-body weight x (forward offset / lever + cos flex).
##                   Bar: NIOSH action limit 3400 N (Waters et al. 1993, read as cited by a 2015 critique)
##   SPINE FLEX+TWIST flexion AND twist together (McGill's combined-loading warning; the numbers 45 / 20 deg are ours)
##   NECK FLEX SPEED forward flexion of the head on the neck, deg/s (bar 200 deg/s, ours, no source found)
## Findings have the Rulebook shape ({"sev", "t", "card", "rule", "msg", "v"}). report(sm) is the pure part (tested on series).
class_name StuntLoad
extends RefCounted

const FPS := 60.0
const GRAV := 9.81
## bars (body weights for the landing; N for compression; degrees and deg/s otherwise)
const LAND_BW := [3.0, 7.0]    # peak vGRF in a drop landing (brief: Dufek & Bates 1991, McNitt-Gray 1993; not verified)
const COMP_AL := 3400.0        # N, NIOSH action limit at L5/S1 (Waters et al. 1993, as cited by a 2015 critique)
const VALGUS_BAR := 10.0       # deg, ours: no cutoff read from Hewett et al. 2005
const NECK_BAR := 200.0        # deg/s, ours: no fall or whiplash source found
const FLEX_BAR := 45.0         # deg, ours
const TWIST_BAR := 20.0        # deg, ours
## the model (ours)
const UB_SHARE := 0.5          # the upper body (trunk, head, arms) share of the body mass in the static estimate
const LEVER := 0.05            # m, the erector spinae's lever arm at L5/S1
const STOP_MIN := 0.005        # m: a stop under this is under one 60 fps frame's resolution: not graded
const VALGUS_WIN := 0.1        # s after touchdown in which the valgus is read
const LAND_MAX_STOP := 0.5     # s: the stop is looked for at most this long after touchdown


static func _f(sev: String, t: float, rule: String, msg: String, v := 0.0) -> Dictionary:
	return Rulebook._f(sev, t, rule, msg, v)


## the frontal-plane knee valgus (deg, + = the knee moves medially, toward the midline) of one leg (side "_l" / "_r"):
## 180 minus the included angle at the knee in the x-y plane, signed by the knee's side of the hip-ankle line
static func valgus(B: Body, side: String) -> float:
	var hip: Vector3 = B.P["thigh" + side]
	var kn: Vector3 = B.P["calf" + side]
	var an: Vector3 = B.P["foot" + side]
	var a := Vector2(hip.x - kn.x, hip.y - kn.y)
	var b := Vector2(an.x - kn.x, an.y - kn.y)
	var inc := absf(rad_to_deg(a.angle_to(b)))
	var f := 0.0
	if absf(hip.y - an.y) > 1e-6:
		var tt := (kn.y - an.y) / (hip.y - an.y)
		var lx := lerpf(an.x, hip.x, tt)
		f = (kn.x - lx) * (-signf(hip.x))   # the medial side: toward x = 0 from either leg
	return (180.0 - inc) * (1.0 if f >= 0.0 else -1.0)


## the posture numbers of one frame: flexion (deg, + forward), twist (deg, the hips against the shoulders, 0 = square),
## the knees' valgus, the head's forward flexion on the neck (deg), and the upper body's offset from L5/S1 (m)
static func pose(B: Body) -> Dictionary:
	var P: Dictionary = B.P
	var up: Vector3 = P["neck_01"] - P["pelvis"]
	var sl: Vector3 = P["upperarm_l"] - P["upperarm_r"]
	var hl: Vector3 = P["thigh_l"] - P["thigh_r"]
	var hv: Vector3 = P["head"] - P["neck_01"]
	return {
		"flex": rad_to_deg(atan2(up.z, up.y)),
		"twist": absf(rad_to_deg(Vector2(hl.x, hl.z).angle_to(Vector2(sl.x, sl.z)))),
		"vgl": valgus(B, "_l"),
		"vgr": valgus(B, "_r"),
		"hf": rad_to_deg(atan2(hv.z, hv.y)),
		"ub": P["spine_03"] - P["pelvis"],
	}


## the scene at 60 fps: the centre of mass height and whether a foot is down, plus pose() per frame
static func sample(S: Scene, B: Body) -> Dictionary:
	var n := int(ceil(S.length() * FPS)) + 1
	var was_stepped := S.stepped
	S.stepped = false
	var sm := {"t": [], "h": [], "down": [], "flex": [], "twist": [], "vgl": [], "vgr": [], "hf": [], "ub": [],
		"mass": HumanLimits.mass_of(B)}
	for i in n:
		var t := minf(i / FPS, S.length())
		S.apply(B, t)
		var bal := Balance.read(B)
		var pm := pose(B)
		sm["t"].append(t)
		sm["h"].append((bal["com"] as Vector3).y)
		sm["down"].append((bal["down"] as Array).size() > 0)
		for k in ["flex", "twist", "vgl", "vgr", "hf", "ub"]:
			sm[k].append(pm[k])
	S.stepped = was_stepped
	return sm


## L5/S1 compression (N): the upper body's weight through the spine plus its moment over the lever (ours, static)
static func comp_n(flex_deg: float, ub: Vector3, mass: float) -> float:
	var m := UB_SHARE * mass
	var fwd := Vector2(ub.x, ub.z).length()
	return m * GRAV * (fwd / LEVER + cos(deg_to_rad(flex_deg)))


## the touchdowns in a centre-of-mass track: a frame in the air, then a frame on the floor, the body falling into it.
## Returns [{"i", "v" (m/s, impact), "d" (m, stop), "unresolved" (d under STOP_MIN), "a" (m/s^2, mean stop decel),
## "bw" (peak vGRF in body weights = 1 + a/g)}]
static func landing_rows(t: Array, h: Array, down: Array) -> Array:
	var out := []
	var n := h.size()
	var k := 2
	while k < n:
		if bool(down[k]) and not bool(down[k - 1]) and float(h[k - 1]) > float(h[k]):
			var v := (float(h[k - 1]) - float(h[k])) * FPS + GRAV / (2.0 * FPS)   # the frame's mean fall, to the touch
			var lim := mini(n - 1, k + int(round(LAND_MAX_STOP * FPS)))
			var m := k
			while m < lim and float(h[m + 1]) < float(h[m]):
				m += 1
			var low := float(h[k])
			for j in range(k, m + 1):
				low = minf(low, float(h[j]))
			var d := float(h[k]) - low
			var row := {"i": k, "v": v, "d": d, "unresolved": d < STOP_MIN, "a": 0.0, "bw": 0.0}
			if not row["unresolved"]:
				row["a"] = v * v / (2.0 * d)
				row["bw"] = 1.0 + float(row["a"]) / GRAV
			out.append(row)
			k = m + 1
		else:
			k += 1
	return out


## runs of frames over bar: [{"a", "b", "peak"}]
static func _runs(s: Array, bar: float) -> Array:
	return HumanLimits._runs(s, bar)


## every stunt-load note of a sampled scene (sorted by time). Pure: no Body, so the test feeds it series.
static func report(sm: Dictionary) -> Array:
	var out := []
	var t: Array = sm["t"]
	var h: Array = sm["h"]
	var n := t.size()
	if n < 3:
		return out
	var mass := float(sm["mass"])
	# 1. landings, each with the knee valgus of the touchdown window
	for r in landing_rows(t, h, sm["down"]):
		var k: int = r["i"]
		var tt: float = t[k]
		if bool(r["unresolved"]):
			out.append(_f("NOTE", tt, "LANDING LOAD", "%.2f s: landing at %.2f m/s, but the stop is %.1f mm: under one 60 fps frame, not graded (ours: 5 mm)." % [
				tt, float(r["v"]), float(r["d"]) * 1000.0], 0.0))
			continue
		var bw: float = r["bw"]
		var verdict := "ABOVE" if bw > float(LAND_BW[1]) else ("within" if bw >= float(LAND_BW[0]) else "below")
		out.append(_f("NOTE", tt, "LANDING LOAD", "%.2f s: impact %.2f m/s, stop %s: peak vGRF %.1f BW (%.1f g) is %s the 3-7 BW drop-landing range (Dufek & Bates 1991; McNitt-Gray 1993, brief's cite, not verified)." % [
			tt, float(r["v"]), Units.len(float(r["d"])), bw, float(r["a"]) / GRAV, verdict], bw))
		var w := int(round(VALGUS_WIN * FPS))
		var vl := -999.0
		var vr := -999.0
		for j in range(k, mini(k + w + 1, n)):
			vl = maxf(vl, float(sm["vgl"][j]))
			vr = maxf(vr, float(sm["vgr"][j]))
		var side := "left" if vl >= vr else "right"
		var vm := maxf(vl, vr)
		out.append(_f("NOTE", tt, "KNEE VALGUS", "%.2f s: %s knee valgus %.1f° in the first %.1f s of the landing: %s the 10° bar (ours; no Hewett 2005 cutoff read, ACL risk per Hewett et al. 2005, AJSM 33:492)." % [
			tt, side, vm, VALGUS_WIN, "over" if vm > VALGUS_BAR else "within"], vm))
	# 2. L5/S1 compression over the NIOSH action limit, and the combined flexion + twist
	var comp := []
	var combo := []
	var cpk := 0.0
	var cpki := 0
	for i in n:
		var c := comp_n(float(sm["flex"][i]), sm["ub"][i], mass)
		comp.append(c)
		combo.append(minf(float(sm["flex"][i]) / FLEX_BAR, float(sm["twist"][i]) / TWIST_BAR))
		if c > cpk:
			cpk = c
			cpki = i
	out.append(_f("NOTE", t[cpki], "SPINE COMPRESS", "%.2f s: L5/S1 compression ~%.0f N at its peak (ours, static estimate; the NIOSH action limit is 3400 N, Waters et al. 1993): %s." % [
		t[cpki], cpk, "OVER" if cpk > COMP_AL else "within"], cpk))
	for r in _runs(comp, COMP_AL):
		out.append(_f("NOTE", t[r["a"]], "SPINE COMPRESS", "%.2f-%.2f s: L5/S1 compression ~%.0f N, over the 3400 N NIOSH action limit (Waters et al. 1993) (ours model)." % [
			t[r["a"]], t[r["b"]], float(r["peak"])], float(r["peak"])))
	for r in _runs(combo, 1.0):
		var ia: int = r["a"]
		out.append(_f("NOTE", t[ia], "SPINE FLEX+TWIST", "%.2f-%.2f s: flexed %.0f deg AND twisted %.0f deg together (ours bars 45 / 20 deg; McGill: combined flexion and twist is the load to avoid)." % [
			t[ia], t[r["b"]], float(sm["flex"][ia]), float(sm["twist"][ia])], float(r["peak"])))
	# 3. neck: the head's forward flexion speed, the peak of the scene
	var npk := 0.0
	var npki := 1
	for i in range(1, n - 1):
		var v := (float(sm["hf"][i + 1]) - float(sm["hf"][i - 1])) * FPS / 2.0
		if v > npk:
			npk = v
			npki = i
	out.append(_f("NOTE", t[npki], "NECK FLEX SPEED", "%.2f s: the head's forward flexion peaks at %.0f deg/s: %s the 200 deg/s bar (ours; no fall or whiplash source found)." % [
		t[npki], npk, "over" if npk > NECK_BAR else "within"], npk))
	out.sort_custom(func(x, y): return x["t"] < y["t"])
	return out


## the scene's stunt-load notes (sample + report); card set as Rulebook.check does
static func findings(S: Scene, B: Body, sm := {}) -> Array:
	if S.cards.size() < 2:
		return []
	if sm.is_empty():
		sm = sample(S, B)
	var out := report(sm)
	for f in out:
		f["card"] = Rulebook.card_at(S, f["t"])
	return out
