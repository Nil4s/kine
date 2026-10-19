## weight_feel.gd - WEIGHT FEEL (ROADMAP 40). A heavy weapon is slow to swing: this retimes a swing's wind-up and
## recovery by the held weapon's moment of inertia about the shoulder. Research and numbers: docs/research/WEIGHT_FEEL.md.
##
##   I = m r^2 + I_cm      m the weapon's mass (Body.KINDS "mass"), r the distance from the shoulder to the weapon's centre
##                         of mass (arm reach to the hand, plus the centre of mass's place along the weapon from the grip),
##                         I_cm = m (k len)^2 about the centre of mass (Body.KINDS "k")
##   T / T_ref = (I / I_ref)^N       N = 0.27: swing speed V = C / I^n (Cross & Bower 2006, n = 0.27); over the same arc
##                         the time is inversely as the speed, so the time goes as I^n
## The scene's timing is taken as authored for the REFERENCE implement (the metal bat, I_REF) until the command has run;
## the contact card remembers the inertia its timing now fits ("weight_i"), so running it again is a no-op and a change
## of weapon retimes by the RATIO of the two. Wind-up = the moves into cards 1..c and the holds of cards 1..c-1; recovery =
## the moves and holds of the cards after c. The contact card c (the card the first "hit" marker sits on) keeps its
## pose, its hold and its own place in the swing; only the time before and after it stretches.
class_name WeightFeel
extends RefCounted

const N := 0.27            # Cross & Bower 2006: V = C / I^n, n = 0.27 (docs/research/WEIGHT_FEEL.md)
const REF_KIND := "metal_bat"
const FMIN := 0.5          # the most a swing is sped up or slowed in one go
const FMAX := 2.0
const GRIP_U := 0.18       # m from the butt where the hand holds (the bat's default), at most half the handle


## the arm's reach shoulder -> palm (m), arm straight, from the body's rest skeleton
static func reach(B: Body) -> float:
	var a := "_r"
	var u: Vector3 = B.p0["upperarm" + a]
	var l: Vector3 = B.p0["lowerarm" + a]
	var h: Vector3 = B.p0["hand" + a]
	var e: Vector3 = B.e0["hand" + a]
	return u.distance_to(l) + l.distance_to(h) + 0.6 * h.distance_to(e)


## {"mass", "r", "i_cm", "i"} of weapon `kind` swung about the shoulder of B ({} for an unknown kind)
static func inertia(B: Body, kind: String) -> Dictionary:
	if not Body.KINDS.has(kind):
		return {}
	var k: Dictionary = Body.KINDS[kind]
	var L: float = k["len"]
	var hh: float = k["handle"]
	var hl := hh if hh >= 0.0 else L + hh
	var grip := minf(GRIP_U, 0.5 * hl)
	var m: float = k["mass"]
	var r := reach(B) + (float(k["com"]) * L - grip)
	var icm := m * pow(float(k["k"]) * L, 2.0)
	return {"mass": m, "r": r, "i_cm": icm, "i": m * r * r + icm}


## the time factor from a swing timed for inertia i_from to one for i_to
static func factor(i_from: float, i_to: float) -> float:
	return clampf(pow(i_to / i_from, N), FMIN, FMAX)


## the contact card: the card nearest the first "hit" marker (arrival time); -1 with no marker or only card 0 to pick
static func contact_card(S: Scene) -> int:
	var t := -1.0
	for mk in S.markers:
		if String(mk["kind"]) == "hit":
			t = float(mk["t"])
			break
	if t < 0.0 or S.cards.size() < 2:
		return -1
	var ts := S.times()
	var best := 1
	for i in range(1, S.cards.size()):
		if absf(float(ts[i][1]) - t) < absf(float(ts[best][1]) - t):
			best = i
	return best


## the weapon kind the contact card holds ("" = none)
static func kind_at(S: Scene, c: int, B: Body) -> String:
	var w: Variant = (S.cards[c]["pose"] as Dictionary).get("weapon", {})
	if w is Dictionary and not (w as Dictionary).is_empty():
		return String(w.get("kind", REF_KIND))
	return B.wep_kind if B.wep_on else ""


## wind-up length (s): the first card's hold ends -> the contact card arrives
static func windup_s(S: Scene, c: int) -> float:
	var ts := S.times()
	return float(ts[c][1]) - float(ts[0][2])


## recovery length (s): the contact card's hold ends -> the scene's end
static func recovery_s(S: Scene, c: int) -> float:
	var ts := S.times()
	return float(ts[-1][2]) - float(ts[c][2])


## RETIME scene S (a clone is the caller's job when it wants to keep the old one). Returns {"ok", "msg", "factor",
## "card", "kind", "i", "i_from", "windup_before", "windup_after", "recovery_before", "recovery_after"}.
static func apply(S: Scene, B: Body) -> Dictionary:
	var res := {"ok": false, "msg": "", "factor": 1.0}
	var c := contact_card(S)
	if c < 0:
		res["msg"] = "no contact to time the swing to: put a hit marker on the strike card first (Markers), then run this again"
		return res
	var kind := kind_at(S, c, B)
	if kind == "":
		res["msg"] = "no weapon held at the contact card %d: pick a weapon first (Weapon: metal bat ...), then run this again" % (c + 1)
		return res
	var inr := inertia(B, kind)
	if inr.is_empty():
		res["msg"] = "the weapon '%s' has no mass on file: pick one of the built-in weapons first" % kind
		return res
	var i_ref := float(inertia(B, REF_KIND)["i"])
	var i_from := float(S.cards[c].get("weight_i", i_ref))
	var f := factor(i_from, float(inr["i"]))
	res["card"] = c
	res["kind"] = kind
	res["i"] = inr["i"]
	res["i_from"] = i_from
	res["factor"] = f
	if absf(f - 1.0) < 0.005:
		res["msg"] = "the swing is already timed for the %s (I = %.2f kg m2 about the shoulder): change the weapon, then run this again" % [kind, float(inr["i"])]
		return res
	res["windup_before"] = windup_s(S, c)
	res["recovery_before"] = recovery_s(S, c)
	var t_old: Array = S.times().duplicate(true)
	var mv := []
	for i in S.cards.size():
		mv.append(S.move_time(i))   # every move is read BEFORE any is written: an auto move reads its neighbours
	for i in range(1, S.cards.size()):
		if i <= c:
			S.cards[i]["move"] = snappedf(maxf(0.04, mv[i] * f), 0.001)
			if i < c:
				S.cards[i]["hold"] = snappedf(float(S.cards[i]["hold"]) * f, 0.001)
		else:
			S.cards[i]["move"] = snappedf(maxf(0.04, mv[i] * f), 0.001)
			S.cards[i]["hold"] = snappedf(float(S.cards[i]["hold"]) * f, 0.001)
	S.cards[c]["weight_i"] = snappedf(float(inr["i"]), 0.0001)
	S.markers = Markers.remap(S.markers, t_old, S.times())   # every marker rides with the card time it sat in (the hit stays on its card)
	res["windup_after"] = windup_s(S, c)
	res["recovery_after"] = recovery_s(S, c)
	res["ok"] = true
	res["msg"] = "timed the swing to the %s (%.2f kg, I = %.2f kg m2 about the shoulder): wind-up %.2f -> %.2f s, recovery %.2f -> %.2f s (x%.2f). The contact card stays as it was" % [
		kind, float(inr["mass"]), float(inr["i"]), res["windup_before"], res["windup_after"], res["recovery_before"], res["recovery_after"], f]
	return res
