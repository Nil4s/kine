## FATIGUE (ROADMAP 39): a long fight slows the strikes. docs/research/FATIGUE.md has the sources and the fit.
##
## MEASURED (the size of the decline): Sensors 2025, 25(11):3270 (doi 10.3390/s25113270), 21 elite male MMA fighters,
## maximal punches normal vs fatigued: straight 8.4 -> 7.5 m/s (-10.7 %), swing 7.1 -> 6.4 m/s (-9.9 %), p < 0.01.
## Mean -10.3 % = DECLINE_REF. Bracketed by Stewart et al. 2025 (Bioengineering 12(12):1355, doi
## 10.3390/bioengineering12121355; 10 amateur boxers after a 9.5 min circuit: punch force -4.26 % on average, -9.84 % for
## the weakest punches). The velocity figure is the anchor; the force study only says "4 to 10 %" is the right order.
## MODEL (the time course; a modelling choice, not a measurement): a fatigue state F in 0..1 rises toward 1 while the
## fighter works (TAU_UP) and falls while he rests (TAU_REC); a strike at state F runs at (1 - decline * F) of its
## fresh speed, so its move takes 1 / that long. Fitted so a 60 s fight with no rest reaches F = 0.91 (decline 9.4 % of
## 10.3 %); the cited 11 x (5 s punching, 5 s rest) protocol (Sensors 2020, 20(20):5749) is 55 s of work.
## REST_TAU 30 s: phosphocreatine resynthesis, half-time ~20-30 s (textbook; re-check before quoting).
## FITNESS 0..1 (per scene, Scene.fitness): the end-of-fight decline = DECLINE_REF * (1 - fitness) / (1 - FIT_REF). The
## elite fighters of the study are FIT_REF = 0.5; fitness 1 = no decline; fitness 0 = 2x (an extrapolation, no data).
class_name Fatigue

const DECLINE_REF := 0.103   # mean of -10.7 % (straight) and -9.9 % (swing) velocity
const FIT_REF := 0.5
const TAU_UP := 25.0         # s of work to 63 % fatigued
const TAU_REC := 30.0        # s of rest to lose 63 % of it
const REST_HOLD := 1.5       # a hold at least this long (s) is rest; everything else is effort
const MARKER_TOL := 0.1      # a hit marker this close (s) to a card's arrival makes it a strike card


## the speed lost at fatigue state f (0..1) for a fighter of this fitness: 0.103 at f = 1, fitness 0.5
static func decline(f: float, fitness: float) -> float:
	return clampf(DECLINE_REF * (1.0 - fitness) / (1.0 - FIT_REF), 0.0, 0.6) * clampf(f, 0.0, 1.0)


## the strike cards: the card each "hit" marker lands on (by arrival time), 0-based, sorted, no repeats
static func strike_cards(S: Scene) -> Array:
	var out := []
	var ts := S.times()
	for m in S.markers:
		if String(m["kind"]) != "hit":
			continue
		var best := -1
		for i in range(1, S.cards.size()):
			if best < 0 or absf(float(ts[i][1]) - float(m["t"])) < absf(float(ts[best][1]) - float(m["t"])):
				best = i
		if best > 0 and absf(float(ts[best][1]) - float(m["t"])) <= MARKER_TOL and not best in out:
			out.append(best)
	out.sort()
	return out


## the plan, read from the scene as it is and changed nowhere: [{"card", "pct" (retime %), "f", "speed"}], one per strike
## card, in order. The clock runs on the NEW timing (a slowed strike is longer, so the later strikes are later).
static func plan(S: Scene, fitness: float) -> Array:
	var strikes := strike_cards(S)
	var out := []
	var f := 0.0
	for i in S.cards.size():
		var mv := S.move_time(i) if i > 0 else 0.0
		var hd := float(S.cards[i]["hold"])
		var k := 1.0
		if i in strikes:
			var speed := 1.0 - decline(f, fitness)
			k = 1.0 / speed
			out.append({"card": i, "pct": 100.0 * k, "f": f, "speed": speed})
		f = _step(f, mv * k, false)
		f = _step(f, hd * k, hd * k >= REST_HOLD)
	return out


static func _step(f: float, dt: float, rest: bool) -> float:
	if rest:
		return f * exp(-dt / TAU_REC)
	return 1.0 - (1.0 - f) * exp(-dt / TAU_UP)


## applies the plan with Scene.retime, one strike card at a time (its move and its hold x pct). -> the plan
static func apply(S: Scene, fitness: float) -> Array:
	var p := plan(S, fitness)
	for e in p:
		S.retime(int(e["card"]), int(e["card"]), float(e["pct"]))
	return p
