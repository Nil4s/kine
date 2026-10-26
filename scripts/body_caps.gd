## body_caps.gd - WHOLE-BODY SPEED CAPS (docs/INNOVATIONS.md N031). I47 (speed_env.gd) caps the LIMBS; this caps the whole body: how hard
## its centre of mass (Balance.com, de Leva masses) can START, STOP, CUT sideways, RISE and FALL. 0 to 8 m/s in 0.2 s is 40 m/s^2;
## the best sprinters on earth push about 11 (Haugen et al. 2019). Sources, populations and the arithmetic: docs/research/BODY_SPEED_CAPS.md.
##
## THE SIGNAL: the COM at 60 Hz (HumanLimits.sample's frames, so Check plays the scene once). Velocity and acceleration are each a central
## difference over +-K frames (K = 3: 0.1 s per difference, a 0.2 s triangular kernel in all). WHY not frame to frame: I47 does not take
## one-step differences of joint angles either (speed_env.gd ANG_STEPS: the papers are low-pass data, and a one-step difference of a keyed
## kink is a spike no body makes), and the lurch survey (docs/MOTION_RULES.md) found raw 60 fps accelerations of 336-377 m/s^2 in REAL
## landings and get-ups. The caps below are averages over a ground contact (sprint F0 is fitted to a smoothed speed curve; the cut is an
## impulse over a 0.152 s stance), so the signal is averaged over about one contact too. A constant acceleration reads exactly (a central
## difference of a parabola is exact); a step in velocity reads as dv / 0.1 s.
##
## THE CHANNELS (each frame):
##   START  horizontal acceleration along the way the body is going (speeding up). The reference direction is the faster of the velocities
##          K frames before and K after, so a body coming to rest is STOPPING to the end, and one leaving rest is STARTING from the first frame
##   STOP   the same, against the way it goes (slowing down)
##   CUT    horizontal acceleration across the way it goes (changing direction)
##   RISE   upward acceleration while the COM goes up (the push of a take-off; the braking of a landing or a countermovement, upward
##          acceleration while still going DOWN, is the stunt-load judge's LANDING LOAD, not graded here)
##   FALL   downward acceleration past g: feet only push, so nothing but a hand on something (HumanLimits.supported) can pull a body down
##          faster than free fall
## Below a body at rest (both speeds under STILL) all horizontal acceleration is START.
## Findings: rule "BODY ACCEL" in the human-limits set (HumanLimits.findings), WARN past the trained bar, FAIL past the elite one (FALL: FAIL
## only, it is physics). Each names its frames, the peak m/s^2 and its frame, and the caps.
## FIX (retime, the I16 / I47 way): the moves of the cards under the peak are lengthened until the peak is under the WARN cap; nothing else.
class_name BodyCaps
extends RefCounted

const FPS := 60.0
const K := 3                 # frames each side of a central difference (0.1 s per difference): HEURISTIC, see the header
const STILL := 0.05          # m/s: under this both ways, the body is at rest and has no direction (HEURISTIC: a 60 Hz COM jitters ~mm)
const GRAV := 9.81
## START: maximal horizontal force at zero speed per kg (F0, N/kg = m/s^2), sprint force-velocity profiles. Haugen, Breitschaedel & Seiler
## 2019, PLoS ONE 14(7):e0215551 (doi 10.1371/journal.pone.0215551), 666 athletes of 23 sports incl. 128 world / Olympic medallists:
## "F0 ... in the range 7-10 N/kg for men"; world-class sprinters ~11 (men) and ~10 (women) as the paper cites them. F0 is the ceiling at
## zero speed; the force falls with speed, so a cap held flat at every speed is lenient
const START_WARN := 10.0
const START_FAIL := 11.0
## STOP: peak deceleration, Harper et al. 2022 Sports Med 52:2321 (doi 10.1007/s40279-022-01693-0, PMC9474351), Table 1/2: 20 m sprint
## to stop, peak DEC -8.48 m/s^2 (Harper et al.); 505 change of direction, youth soccer, fast group, peak DEC -11.02 (Kaneko et al.)
const STOP_WARN := 8.48
const STOP_FAIL := 11.02
## CUT: Yamashita, Inaba, Asakura & Ito 2025, Front Sports Act Living 7:1576614 (doi 10.3389/fspor.2025.1576614), 10 highly trained / elite
## American football players, 45 deg cut at max effort from 6.66 m/s: execution-step medial impulse 1.75 +- 0.12 Ns/kg over a stance of
## 0.152 +- 0.008 s. Mean medial acceleration over the stance = 1.75 / 0.152 = 11.5 m/s^2 (WARN); (1.75 + 2 x 0.12) / 0.152 = 13.1 (FAIL)
const CUT_WARN := 11.5
const CUT_FAIL := 13.1
## RISE: countermovement-jump concentric peak force, Lin, Goldstein & Schroeder 2025, Sports 13(9):292 (doi 10.3390/sports13090292),
## 38 NCAA D1 male basketball / volleyball players: 24.51 +- 2.17 N/kg (the force includes the body's weight, so the net upward
## acceleration is F/m - g). WARN 24.51 - 9.81 = 14.7 m/s^2; FAIL (24.51 + 2 x 2.17) - 9.81 = 19.0. The paper's peak is instantaneous
## (force plate), ours is averaged over 0.2 s: lenient
const RISE_WARN := 14.7
const RISE_FAIL := 19.0
## FALL: free fall is the cap (physics). FALL_K is the measuring grace: a parabola reads exactly, but the floor pass (on_floor) and a card
## blend ripple the COM by millimetres. HEURISTIC
const FALL_K := 1.10
const AIM := 0.97            # the fix lengthens until the peak is this x the WARN cap
const MAX_ITER := 10

const KINDS := ["start", "stop", "cut", "rise", "fall"]
const WORDS := {"start": "speeds up (start)", "stop": "slows down (stop)", "cut": "changes direction (cut)", "rise": "pushes up (take-off)",
	"fall": "drops faster than free fall"}
const WHO := {"start": "trained athletes' sprint-start F0 tops out at 10, world-class sprinters about 11 (Haugen et al. 2019)",
	"stop": "a trained player's peak sprint-to-stop deceleration is 8.48, the fastest change-of-direction group 11.02 (Harper et al. 2022 review)",
	"cut": "elite footballers' 45 deg cut averages 11.5 over the plant step, mean + 2 SD 13.1 (Yamashita et al. 2025)",
	"rise": "trained jumpers' countermovement push peaks at 14.7 net (24.5 N/kg), mean + 2 SD 19.0 (Lin et al. 2025)",
	"fall": "feet can only push: without a hand pulling, a body falls at g = 9.81 at most"}


## [WARN, FAIL] m/s^2 for a channel (FALL: the fail bar twice: it has no WARN)
static func caps(kind: String) -> Array:
	match kind:
		"start":
			return [START_WARN, START_FAIL]
		"stop":
			return [STOP_WARN, STOP_FAIL]
		"cut":
			return [CUT_WARN, CUT_FAIL]
		"rise":
			return [RISE_WARN, RISE_FAIL]
	return [GRAV * FALL_K, GRAV * FALL_K]


## the COM and the hand support at 60 Hz, played here (the fix's re-measure; Check passes HumanLimits.sample's own frames instead)
static func sample(S: Scene, B: Body) -> Dictionary:
	return play(S, B, 0, int(ceil(S.length() * FPS)))


## frames lo..hi (inclusive) of the clip; the others stay zero / false (a window is all peak_in reads, see there)
static func play(S: Scene, B: Body, lo: int, hi: int) -> Dictionary:
	var keep: Dictionary = B.state()
	var was := S.stepped
	S.stepped = false
	var n := int(ceil(S.length() * FPS)) + 1
	var com := []
	var sup := []
	com.resize(n)
	sup.resize(n)
	com.fill(Vector3.ZERO)
	sup.fill(false)
	for i in range(maxi(lo, 0), mini(hi, n - 1) + 1):
		S.apply_true(B, i / FPS)   # as HumanLimits.sample plays it (FrameMemo.pose when the memo is off)
		com[i] = Balance.com(B)
		sup[i] = HumanLimits.supported(B)
	S.stepped = was
	B.set_state(keep)
	return {"com": com, "sup": sup}


static func _diff(x: Array, i: int) -> Vector3:
	var n := x.size()
	var a := maxi(i - K, 0)
	var b := mini(i + K, n - 1)
	if b <= a:
		return Vector3.ZERO
	return ((x[b] as Vector3) - (x[a] as Vector3)) * FPS / float(b - a)


## per frame, each channel's m/s^2 (>= 0): {"start": [..], "stop", "cut", "rise", "fall", "v": [Vector3], "a": [Vector3]}
static func series(com: Array) -> Dictionary:
	var n := com.size()
	var v := []
	for i in n:
		v.append(_diff(com, i))
	var a := []
	for i in n:
		a.append(_diff(v, i))
	var out := {"v": v, "a": a}
	for k in KINDS:
		out[k] = []
	for i in n:
		var ac: Vector3 = a[i]
		var ah := Vector2(ac.x, ac.z)
		var v0: Vector3 = v[maxi(i - K, 0)]
		var v1: Vector3 = v[mini(i + K, n - 1)]
		var h0 := Vector2(v0.x, v0.z)
		var h1 := Vector2(v1.x, v1.z)
		var ref := h1 if h1.length() >= h0.length() else h0
		var st := 0.0
		var sp := 0.0
		var ct := 0.0
		if ref.length() < STILL:
			st = ah.length()
		else:
			var u := ref.normalized()
			var al := ah.dot(u)
			st = maxf(al, 0.0)
			sp = maxf(-al, 0.0)
			ct = (ah - u * al).length()
		out["start"].append(st)
		out["stop"].append(sp)
		out["cut"].append(ct)
		var vy: float = (v[i] as Vector3).y
		out["rise"].append(ac.y if ac.y > 0.0 and vy >= 0.0 else 0.0)
		out["fall"].append(-ac.y if ac.y < 0.0 else 0.0)
	return out


## runs of frames over bar where ok[i] (null = every frame): [{"a", "b", "peak", "at"}]
static func _runs(s: Array, bar: float, ok: Array = []) -> Array:
	var out := []
	var i := 0
	while i < s.size():
		if float(s[i]) > bar and (ok.is_empty() or bool(ok[i])):
			var r := {"a": i, "b": i, "peak": float(s[i]), "at": i}
			while i < s.size() and float(s[i]) > bar and (ok.is_empty() or bool(ok[i])):
				if float(s[i]) > float(r["peak"]):
					r["peak"] = float(s[i])
					r["at"] = i
				r["b"] = i
				i += 1
			out.append(r)
		else:
			i += 1
	return out


## the window around frame i in which a hand support counts (a pull anywhere in the difference's reach)
static func _free(sup: Array) -> Array:
	var out := []
	for i in sup.size():
		var f := true
		for j in range(maxi(i - 2 * K, 0), mini(i + 2 * K, sup.size() - 1) + 1):
			if bool(sup[j]):
				f = false
				break
		out.append(f)
	return out


## the findings of one COM track (pure: the test feeds synthetic tracks). sup: per frame, a hand or the weapon on something ([] = none)
static func rule(com: Array, sup: Array = []) -> Array:
	var se := series(com)
	var out := []
	var free := [] if sup.is_empty() else _free(sup)
	for k in KINDS:
		var c := caps(k)
		for r in _runs(se[k], float(c[0]), free if k == "fall" else []):
			var pk := float(r["peak"])
			var sev := "FAIL" if (k == "fall" or pk > float(c[1])) else "WARN"
			var t0 := float(r["a"]) / FPS
			var t1 := float(r["b"]) / FPS
			var bar := "FAIL past %.1f" % float(c[1]) if k != "fall" else "%.0f%% grace for the 60 Hz sampling" % ((FALL_K - 1.0) * 100.0)
			var f := Rulebook._f(sev, t0, "BODY ACCEL",
				"frames %d-%d (%.2f-%.2f s): the centre of mass %s at %.1f m/s^2 (peak at frame %d, %.2f s); the cap is %.1f m/s^2: %s (%s)." % [
					int(r["a"]), int(r["b"]), t0, t1, WORDS[k], pk, int(r["at"]), float(r["at"]) / FPS, float(c[0]), WHO[k], bar], pk)
			f["t1"] = t1
			f["kind"] = k
			f["frames"] = [int(r["a"]), int(r["b"])]
			f["peak_frame"] = int(r["at"])
			f["accel"] = snappedf(pk, 0.01)
			f["cap"] = float(c[0])
			f["cap_fail"] = float(c[1])
			out.append(f)
	out.sort_custom(func(x, y): return x["t"] < y["t"])
	return out


## Check's entry (HumanLimits.findings): sm = HumanLimits.sample (its "com" / "sup"); card set by the caller
static func findings(S: Scene, B: Body, sm := {}) -> Array:
	if S.cards.size() < 2:
		return []
	if not sm.has("com"):
		sm = sample(S, B)
	return rule(sm["com"], sm["sup"])


## the peak of one channel over [t0, t1] s of a scene
static func peak_in(S: Scene, B: Body, kind: String, t0: float, t1: float) -> Array:
	# only the frames the peak reads and the 2K on each side that series / _free look at: the rest of the clip is not played (the
	# retime loop asks again after every lengthening; a full replay per ask was most of a step's time: 1e74ee6a)
	var lo := maxi(int(floor(t0 * FPS)) - 2 * K - 2, 0)
	var hi := mini(int(ceil(t1 * FPS)) + 2 * K + 2, int(ceil(S.length() * FPS)))
	var sm := play(S, B, lo, hi)
	var s: Array = series(sm["com"])[kind]
	var free := _free(sm["sup"])
	var pk := 0.0
	var at := -1
	for i in range(maxi(int(floor(t0 * FPS)), 0), mini(int(ceil(t1 * FPS)), s.size() - 1) + 1):
		if kind == "fall" and not bool(free[i]):
			continue
		if float(s[i]) > pk:
			pk = float(s[i])
			at = i
	return [pk, at]


## the cards whose moves lie under a peak at time t (the difference's reach, 2K frames, each side)
static func cards_under(S: Scene, t: float) -> Array:
	var ts := S.times()
	var r := 2.0 * K / FPS
	var out := []
	for i in range(1, S.cards.size()):
		if float(ts[i - 1][2]) < t + r and float(ts[i][1]) > t - r:
			out.append(i)
	if out.is_empty():
		out.append(maxi(1, Rulebook.card_at(S, t)))
	return out


## how much slower (percent of the move's time) a stretch of moves must play for f's peak to fall under AIM x its cap: an
## acceleration over a fixed path goes as 1 / T^2, so T x sqrt(peak / (AIM x cap)). For the blockers' retime loops (TextBlocking,
## StrikeBlocking), which otherwise slow by a fixed step and run out of tries on a 2-3x lurch. Clamped 110..200.
static func stretch(f: Dictionary) -> float:
	return clampf(sqrt(float(f.get("accel", 0.0)) / maxf(AIM * float(f.get("cap", 1.0)), 1e-6)) * 100.0, 110.0, 200.0)


## FIX in place: lengthen the moves of the cards under f's peak until that channel peaks under AIM x its WARN cap. Only "move" changes.
## {"did", "cards", "from", "to", "peak_before", "peak_after", "cap", "kind"} (no "after": Fixer reads that key as the findings after)
static func retime(f: Dictionary, S: Scene, B: Body) -> Dictionary:
	var kind := String(f.get("kind", "start"))
	var cap := float(caps(kind)[0])
	var tp := float(f.get("peak_frame", int(float(f["t"]) * FPS))) / FPS
	var cs := cards_under(S, tp)
	var m0 := cs.map(func(i): return S.move_time(i))
	var before := float(f["v"])
	var pk := before
	for it in MAX_ITER:
		var ratio := pk / cap
		if ratio <= 1.0:
			break
		var k := clampf(sqrt(ratio / AIM), 1.05, 2.0)
		for i in cs:
			S.cards[i]["move"] = snappedf(S.move_time(i) * k, 0.001)
		var ts := S.times()
		var a := float(ts[cs[0] - 1][2]) - 2.0 * K / FPS
		var b := float(ts[cs[-1]][1]) + 2.0 * K / FPS
		pk = float(peak_in(S, B, kind, a, b)[0])
	var to := cs.map(func(i): return S.move_time(i))
	var parts := []
	for j in cs.size():
		parts.append("card %d '%s' move %.2f -> %.2f s" % [cs[j] + 1, S.cards[cs[j]]["name"], m0[j], to[j]])
	return {"did": "%s; the %s peak %.1f -> %.1f m/s^2 (cap %.1f)" % [", ".join(parts), kind, before, pk, cap],
		"cards": cs, "from": m0, "to": to, "peak_before": before, "peak_after": pk, "cap": cap, "kind": kind}
