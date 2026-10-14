## rulebook.gd - recorded human numbers a move is graded against (Nick 10-14: "plenty of humans recorded maths and numbers
## about those animations"). Every rule names its source and its bar (docs/MOTION_RULES.md is the human-readable table).
## One pass samples the scene at 60 fps into series (sample()); each rule is a pure function over them, so a test can
## feed it a broken series on purpose. check() = both, a list of findings:
##   {"sev": "FAIL"/"WARN", "t": seconds, "card": index, "rule": "HEAD QUIET", "msg": plain words with the number vs the bar}
## The weapon's own timing rules live in tools/attack_timing.gd (docs/ATTACK_RULES.md): its tables are REUSED here.
class_name Rulebook
extends RefCounted

const AT := preload("res://tools/attack_timing.gd")
const FPS := 60.0

## the sources (docs/MOTION_RULES.md has the links)
const SRC := {
	"SEQUENCE": "pelvis -> trunk -> bat peak in that order in hitting (ISBS 2015, 3 hitters: 389 / 601 / 1953 deg/s)",
	"HIPS TURN": "hitters' pelvis peaks ~389 deg/s (ISBS 2015); warned below a quarter of it",
	"HEAD QUIET": "hitters' heads drop ~9 cm over the whole swing (Inkster et al., via SABR); skilled = steadier (Nakata)",
	"TIP SPEED": "the weapon's real tip cap (docs/ATTACK_RULES.md: pro bat ~37-40 m/s, staff end ~30, knife ~15)",
	"STRIKE FRAMES": "the swing itself <= the weapon's frame budget at 30 fps (docs/ATTACK_RULES.md, Aztez)",
	"FIST SPEED": "boxers' fastest punch (lead hook) 11.95 +- 1.84 m/s (Stanley et al. 2018); straight 9.3 +- 2.1 (Piorkowski 2011)",
	"HITCH": "a point-to-point move has ONE bell-shaped speed peak (Flash & Hogan 1985, J. Neurosci. 5(7))",
	"FOOT SLIDE": "foot skating: a foot under 5 cm off the floor that slides more than 2.5 cm (Karunratanakul et al. 2023, the motion-generation standard; there per frame, here per planted stretch: stricter)",
}
const HIPS_MIN := 389.0 / 4.0      # deg/s
const HEAD_WARN := 0.15            # m from where it was as the swing began (9 cm recorded + 6 cm grace)
const HEAD_FAIL := 0.30
const FIST_WARN := 11.95           # m/s: the recorded mean of the fastest punch
const FIST_FAIL := 11.95 + 2.0 * 1.84
const HITCH_DIP := 0.3             # a dip below 30% of the speed on BOTH sides, within HITCH_SPAN frames, = a hitch
const HITCH_SPAN := 3
const HITCH_FAST := 1.0            # m/s: both sides at least this fast (a slow drift is not a hitch)
const STRIKE_MIN := 3.0            # m/s: a tip slower than this all scene long = no strike in it
const SWING_LEAD := 0.5            # s before the tip's peak in which the hips and chest must peak
const HEAD_WIN := [0.3, 0.1]       # s before / after the tip's peak the head is watched
const AIR := 0.05                  # m: the lower foot this far above its lowest in the scene = off the ground
## not swings (the swing rules are measured on hitters): attack_timing's list + the get-ups
const NOT_SWINGS := ["getup_back", "getup_front"]
const FOOT_DOWN := 0.05            # m: the ball of the foot this low = on the floor (Karunratanakul 2023)
const FOOT_SKATE := 0.025          # m: sliding more than this along the floor while down = skating
const FOOT_STILL := 0.005          # m per 60 fps frame (0.3 m/s): slower than this = meant to stand (landings are faster)


## two rotations' difference in degrees, by how far they carry each axis (float32 acos near 1 floors at ~0.04 deg)
static func ang_deg(q: Quaternion, r: Quaternion) -> float:
	var w := 0.0
	for v in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		w = maxf(w, (q * v - r * v).length())
	return rad_to_deg(2.0 * asin(clampf(w * 0.5, 0.0, 1.0)))


static func dir_deg(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(2.0 * asin(clampf((a.normalized() - b.normalized()).length() * 0.5, 0.0, 1.0)))


## the scene at 60 fps: per-frame speeds (m/s, deg/s) of what the rules read, plus the positions the head rule needs.
## base + [t0, t1] (10-14, the Fix button): frames outside the window are taken from base's raw frames instead of
## re-played (a pose edit on one card cannot move them; tests/fix_test.gd asserts window == full, bit for bit).
## contacts: also count each frame's parts-inside-each-other in the window ("bad", a Fix may not add any).
static func sample(S: Scene, B: Body, base := {}, t0 := INF, t1 := -INF, contacts := false) -> Dictionary:
	var n := int(ceil(S.length() * FPS)) + 1
	var was_stepped := S.stepped
	S.stepped = false   # the stepped preview is a view: the rules grade the scene as it really plays
	var reuse: bool = not base.is_empty() and base["_raw"].size() == n
	var raw := []
	var bad := 0
	for i in n:
		var t := minf(i / FPS, S.length())
		if reuse and (t < t0 or t > t1):
			raw.append(base["_raw"][i])
			continue
		S.apply(B, t)
		raw.append({"tip": Overlays.tracked(B), "hips": B.P["pelvis"], "head": B.P["head"], "hand_l": B.E["hand_l"],
			"hand_r": B.E["hand_r"], "gp": B.G["pelvis"], "gt": B.G["spine_03"],
			"wd": (B.wep_point(B.wep_len) - B.wep_point(0.0)) if B.wep_on else (B.E["hand_r"] - B.P["hand_r"]),
			"fy": minf((B.P["foot_l"] as Vector3).y, (B.P["foot_r"] as Vector3).y), "wep": B.wep_on, "kind": B.wep_kind,
			"bl": B.P["ball_l"], "br": B.P["ball_r"]})
		if contacts and not B.contacts().is_empty():
			bad += 1
	S.stepped = was_stepped
	var out := {"t": [], "tip": [], "hips": [], "head": [], "hand_l": [], "hand_r": [], "w_pelvis": [], "w_trunk": [],
		"w_weapon": [], "head_pos": [], "foot_y": [], "ball_l": [], "ball_r": [], "armed": false, "kind": "",
		"spline": S.spline, "_raw": raw, "bad": bad}
	for i in n:
		var now: Dictionary = raw[i]
		var prev: Dictionary = raw[maxi(i - 1, 0)]
		if now["wep"]:
			out["armed"] = true
			out["kind"] = now["kind"]
		out["t"].append(i / FPS)
		out["head_pos"].append(now["head"])
		out["foot_y"].append(now["fy"])
		out["ball_l"].append(now["bl"])
		out["ball_r"].append(now["br"])
		for k in ["tip", "hips", "head", "hand_l", "hand_r"]:
			out[k].append(((now[k] as Vector3) - prev[k]).length() * FPS if i > 0 else 0.0)
		out["w_pelvis"].append(ang_deg(prev["gp"], now["gp"]) * FPS if i > 0 else 0.0)
		out["w_trunk"].append(ang_deg(prev["gt"], now["gt"]) * FPS if i > 0 else 0.0)
		out["w_weapon"].append(dir_deg(prev["wd"], now["wd"]) * FPS if i > 0 else 0.0)
	for k in ["tip", "hips", "head", "hand_l", "hand_r", "w_pelvis", "w_trunk", "w_weapon"]:
		if out[k].size() > 1:
			out[k][0] = out[k][1]
	return out


## the strikes: the tip's speed peaks at least half the scene's fastest, 0.25 s apart (the bigger wins), each with the
## run of frames around it above half its own peak: [{"pk": frame, "a": first, "b": last}]
static func strikes(tip: Array) -> Array:
	var top := 0.0
	for v in tip:
		top = maxf(top, v)
	if top < STRIKE_MIN:
		return []
	var cands := []
	for i in range(1, tip.size() - 1):
		if tip[i] >= tip[i - 1] and tip[i] > tip[i + 1] and tip[i] >= 0.5 * top:
			cands.append(i)
	cands.sort_custom(func(x, y): return tip[x] > tip[y])
	var keep := []
	for c in cands:
		var near := false
		for k in keep:
			if absi(k - c) < int(0.25 * FPS):
				near = true
		if not near:
			keep.append(c)
	keep.sort()
	var out := []
	for pk in keep:
		var a: int = pk
		var b: int = pk
		while a > 0 and tip[a - 1] > 0.5 * tip[pk]:
			a -= 1
		while b < tip.size() - 1 and tip[b + 1] > 0.5 * tip[pk]:
			b += 1
		out.append({"pk": pk, "a": a, "b": b})
	return out


static func _argmax(s: Array, a: int, b: int) -> int:
	var best := a
	for i in range(a, b + 1):
		if s[i] > s[best]:
			best = i
	return best


## a finding; v = the measured number (m/s, m, frames) the Fix button works from
static func _f(sev: String, t: float, rule: String, msg: String, v := 0.0) -> Dictionary:
	return {"sev": sev, "t": t, "card": -1, "rule": rule, "msg": msg, "v": v}


## SEQUENCE + HIPS TURN: in the SWING_LEAD before the tip's peak, the hips peak first, then the chest, then the weapon
static func rule_sequence(sm: Dictionary, st: Dictionary) -> Array:
	var out := []
	var pk: int = st["pk"]
	var a := maxi(0, pk - int(SWING_LEAD * FPS))
	var b := mini(sm["w_weapon"].size() - 1, pk + 2)
	var ip := _argmax(sm["w_pelvis"], a, b)
	var it := _argmax(sm["w_trunk"], a, b)
	var iw := _argmax(sm["w_weapon"], a, b)
	var tol := 1   # one frame at 60 fps: a tie
	var t: float = sm["t"][pk]
	var wp: float = sm["w_pelvis"][ip]
	if wp < HIPS_MIN:
		out.append(_f("WARN", t, "HIPS TURN", "the hips barely turn into this swing: %.0f deg/s at most (real hitters ~389, bar %.0f). The arms swing alone." % [wp, HIPS_MIN]))
	elif it + tol < ip or iw + tol < ip:
		out.append(_f("FAIL" if iw + tol < ip else "WARN", t, "SEQUENCE", "the hips turn LATE: their fastest moment is %.0f ms after the %s's. Real swings go hips -> chest -> weapon." % [(ip - mini(it, iw)) * 1000.0 / FPS, "weapon" if iw < it else "chest"]))
	elif iw + tol < it:
		out.append(_f("FAIL", t, "SEQUENCE", "the chest turns after the weapon: %.0f ms late. Real swings go hips -> chest -> weapon." % ((it - iw) * 1000.0 / FPS)))
	return out


## HEAD QUIET: from HEAD_WIN[0] before the tip's peak to HEAD_WIN[1] after, how far the head gets from where it began
static func rule_head(sm: Dictionary, st: Dictionary) -> Array:
	var pk: int = st["pk"]
	var a := maxi(0, pk - int(HEAD_WIN[0] * FPS))
	var b := mini(sm["head_pos"].size() - 1, pk + int(HEAD_WIN[1] * FPS))
	var ground: float = sm["foot_y"].min()
	for i in range(maxi(0, a - int(0.2 * FPS)), mini(sm["foot_y"].size(), b + 1 + int(0.2 * FPS))):   # a jump near the swing too
		if sm["foot_y"][i] > ground + AIR:
			return []   # off the ground: the hitters' numbers are for feet on it
	var far := 0.0
	var at := a
	for i in range(a, b + 1):
		var d: float = ((sm["head_pos"][i] as Vector3) - sm["head_pos"][a]).length()
		if d > far:
			far = d
			at = i
	if far <= HEAD_WARN:
		return []
	return [_f("FAIL" if far > HEAD_FAIL else "WARN", sm["t"][at], "HEAD QUIET", "the head travels %.0f cm during the swing (real hitters ~9; bar %.0f cm). Keep the head still and let the hips and arms do the work." % [far * 100.0, HEAD_WARN * 100.0], far)]


## TIP SPEED + STRIKE FRAMES: attack_timing's tables for this weapon
static func rule_weapon(sm: Dictionary, st: Dictionary) -> Array:
	if not sm["armed"]:
		return []
	var out := []
	var kind: String = sm["kind"]
	var cap: float = AT.TIP_MAX.get(kind, 40.0)
	var budget: int = AT.RULES.get(kind, AT.RULES["metal_bat"])[1]
	var v: float = sm["tip"][st["pk"]]
	var t: float = sm["t"][st["pk"]]
	if v > cap:
		out.append(_f("FAIL", t, "TIP SPEED", "the %s's tip hits %.1f m/s; a real one tops out near %.0f. Give this move more time (the card's 'move')." % [kind.replace("_", " "), v, cap], v))
	var frames30: float = (st["b"] - st["a"] + 1) * 30.0 / FPS
	if frames30 > budget + 0.5:
		out.append(_f("WARN", t, "STRIKE FRAMES", "the swing itself lasts %.0f frames at 30 fps (budget %d for a %s): it reads slow. Shorten the strike card's move." % [frames30, budget, kind.replace("_", " ")], frames30))
	return out


## FIST SPEED (unarmed only): either hand's end over the recorded fastest punch
static func rule_fist(sm: Dictionary) -> Array:
	if sm["armed"]:
		return []
	var out := []
	for k in ["hand_l", "hand_r"]:
		var i := _argmax(sm[k], 0, sm[k].size() - 1)
		var v: float = sm[k][i]
		if v > FIST_WARN:
			out.append(_f("FAIL" if v > FIST_FAIL else "WARN", sm["t"][i], "FIST SPEED", "the %s hand moves at %.1f m/s, faster than boxers' fastest punch (12 on average; bar %.1f). It will read as a pop." % ["left" if k == "hand_l" else "right", v, FIST_WARN if v <= FIST_FAIL else FIST_FAIL], v))
	return out


## FOOT SLIDE: a foot that is DOWN (ball under FOOT_DOWN) and SETTLED (moving under FOOT_STILL per frame along the
## floor) but creeps: over each run of such frames, its farthest point from where it settled; over FOOT_SKATE = skating.
## A landing or a take-off is fast near the floor and is not counted (10-14: the first version, which counted every
## frame under 5 cm, called combo3's landing a 10 cm slide; the foot then sits still to the millimetre for 1.1 s).
static func rule_feet(sm: Dictionary) -> Array:
	var out := []
	if not sm.has("ball_l"):
		return out
	for k in ["ball_l", "ball_r"]:
		var s: Array = sm[k]
		var i := 1
		while i < s.size():
			if not _settled(s, i):
				i += 1
				continue
			var a := i
			var far := 0.0
			var p0: Vector3 = s[a]
			while i < s.size() and _settled(s, i):
				var d: Vector3 = (s[i] as Vector3) - p0
				far = maxf(far, Vector2(d.x, d.z).length())
				i += 1
			if far > FOOT_SKATE:
				out.append(_f("WARN", sm["t"][a], "FOOT SLIDE", "the %s foot creeps %.1f cm along the floor while it should stand (%.2f-%.2f s); more than 2.5 cm reads as skating. Pin it: give it the same place in the cards around it." % ["left" if k == "ball_l" else "right", far * 100.0, sm["t"][a], sm["t"][i - 1]], far))
	return out


static func _settled(s: Array, i: int) -> bool:
	var p: Vector3 = s[i]
	var d: Vector3 = p - (s[i - 1] as Vector3)
	return p.y < FOOT_DOWN and Vector2(d.x, d.z).length() < FOOT_STILL


## HITCH: on the weapon tip, the hips and the head, a speed dip below HITCH_DIP of BOTH sides within HITCH_SPAN frames.
## A dip inside a card's HOLD is a pose held on purpose (ATTACK_RULES: hold the top of the wind-up), not a hitch.
## One moment = one finding, naming every part that stutters there.
static func rule_hitch(sm: Dictionary, holds: Array) -> Array:
	var names := {"tip": "the weapon tip" if sm["armed"] else "the right hand", "hips": "the hips", "head": "the head"}
	var hits := []   # [frame, part, left, dip, right]
	for k in names:
		var s: Array = sm[k]
		for i in range(HITCH_SPAN, s.size() - HITCH_SPAN):
			var l := 0.0
			var r := 0.0
			for d in range(1, HITCH_SPAN + 1):
				l = maxf(l, s[i - d])
				r = maxf(r, s[i + d])
			if minf(l, r) >= HITCH_FAST and s[i] < HITCH_DIP * minf(l, r) and s[i] <= s[i - 1] and s[i] <= s[i + 1]:
				var t: float = sm["t"][i]
				var held := false
				for h in holds:
					if t >= h[0] - 1.0 / FPS and t <= h[1] + 1.0 / FPS:
						held = true
				if not held:
					hits.append([i, names[k], l, s[i], r])
	hits.sort_custom(func(x, y): return x[0] < y[0])
	var out := []
	var group := []
	for h in hits + [[1 << 30]]:
		if not group.is_empty() and h[0] - group[0][0] > HITCH_SPAN * 2:
			var w: Array = group[0]
			var parts := []
			for g in group:
				if not g[1] in parts:
					parts.append(g[1])
			var fix := "two cards here fight: move one, or delete one" if sm["spline"] else "the body stops dead at a card between two fast moves. Tick 'Smooth (spline)' (or press Polish) so it flows through"
			out.append(_f("WARN", sm["t"][w[0]], "HITCH", "%s: %.1f -> %.1f -> %.1f m/s within %d ms (%s). A real move has one smooth speed peak; %s." % [parts[0].left(1).to_upper() + parts[0].substr(1), w[2], w[3], w[4], int(2 * HITCH_SPAN * 1000 / FPS), ", ".join(parts.slice(1)) if parts.size() > 1 else "alone", fix]))
			group = []
		if h[0] < 1 << 30:
			group.append(h)
	return out


## which card a moment belongs to: the card being moved into or held
static func card_at(S: Scene, t: float) -> int:
	var ts := S.times()
	for i in ts.size():
		if t <= float(ts[i][2]) + 1e-4:
			return i
	return ts.size() - 1


## every rule over a scene; sorted by time
## sm: a sample already taken of this scene (the Fix button re-samples only a window)
static func check(S: Scene, B: Body, sm := {}) -> Array:
	if S.cards.size() < 2:
		return []
	if sm.is_empty():
		sm = sample(S, B)
	var out := []
	var attack := not S.name in AT.NOT_ATTACKS and not S.name in NOT_SWINGS
	if attack:
		for st in strikes(sm["tip"]):
			out += rule_sequence(sm, st)
			out += rule_head(sm, st)
			out += rule_weapon(sm, st)
	out += rule_fist(sm)
	out += rule_feet(sm)
	var holds := []
	for ts in S.times():
		if float(ts[2]) - float(ts[1]) > 1e-4:
			holds.append([float(ts[1]), float(ts[2])])
	out += rule_hitch(sm, holds)
	for f in out:
		f["card"] = card_at(S, f["t"])
	out.sort_custom(func(x, y): return x["t"] < y["t"])
	return out
