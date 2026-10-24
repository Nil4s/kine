## explain_motion.gd - N091 EXPLAIN THIS MOTION (docs/INNOVATIONS.md). A plain-words breakdown of a clip (or of one card's span,
## or of a t0-t1 window) for a beginner animator, with the number behind every sentence. Four parts:
##   PHASES   anticipation / action / contact / follow-through / recovery, as times and frames, found from the BODY's motion
##            (the striking end's speed, the centre of mass, the feet's N017 plants), never from the card names
##   POWER    where the power comes from: the I8 power chain (ForceView.chain_of: pelvis -> trunk -> upper arm -> forearm peaks)
##            and its order and timing, the segment with the biggest angular speed, and the weight transfer: the centre of
##            mass's travel toward the target and the body's momentum at contact (I36: Momentum.sample, P = M dCOM/dt)
##   READ     what makes it read fast / heavy / snappy / floaty: anticipation vs action length, the ease of the strike (where its
##            speed peaks), the holds, overshoot, the arc's kinks (ArcCheck) and the craft notes (Critique) - each against a
##            norm that says MEASURED / HEURISTIC (N020 trust words) and where it comes from
##   TRY      the one change most likely to help, as a run-step list and a poser_cli command line
## NOTHING IS JUDGED TWICE: the anticipation / floaty / dead-stop / even-timing notes are Critique.check's own (ROADMAP 11), the kinks
## ArcCheck.kinks_in's, the chain ForceView's, the momentum Momentum's, the samples and foot contacts EventQuery's (N017). This file
## only finds the phases and words the numbers.
##
## THE STRIKING END: of the wrists, the ankles and the weapon tip (EventQuery points, sampled at HZ = 60), the one whose speed peaks
## highest in the window. Its speed v(i) is EventQuery.speed_series (central difference, the formula `measure speed` uses).
## STRIKES: Rulebook.strikes(v): the peaks at least half the fastest, 0.25 s apart, the fastest at least 3 m/s (Rulebook.STRIKE_MIN).
## The MAIN strike is the fastest whose peak is in the window.
## MOVEMENT UNITS: the runs of v >= REST_MS, cut again at a dip under Rulebook.HITCH_DIP (30 %) of the smaller of the two peaks
## either side (the rulebook's own "one bell per reach" bar: Flash & Hogan 1985). One unit = one push of the striking end.
## PHASES of a strike whose peak pk is in unit k:
##   action          from unit k's first sample to pk - 1     contact   pk (the end is fastest: a hit lands there)
##   follow-through  pk + 1 to unit k's end, then each next unit that starts within FT_GAP of the last and does NOT take the
##                   body back toward its ready pose (RETURN: the mean joint distance to the ready pose falls by half or more)
##   anticipation    the units before k joined back while the pause between them is at most ANTIC_GAP, not past the previous
##                   strike's follow-through; it runs to a - 1 (the hold at the top included). None = "no anticipation"
##   recovery        the units after the follow-through that the next strike's anticipation does not take (none = flows on)
## The ready pose = the body at the anticipation's start (at the action's start without one).
## The hand labels the test holds this to were read off the speed curves BEFORE this file was written (tests/explain_test.gd).
## Read only: the scene is not changed and the body is put back as it was (the test checks both).
class_name ExplainMotion
extends RefCounted

const HZ := 60.0
const REST_MS := 0.1        # m/s, HEURISTIC: slower than this (1.7 mm a 60 Hz sample) the striking end is at rest
const FT_GAP := 6           # samples (0.1 s), HEURISTIC: a pause this short after the hit still carries its momentum on
const ANTIC_GAP := 12       # samples (0.2 s), HEURISTIC: a wind-up that pauses longer than this before the next push is a separate move
const RETURN := 0.5         # HEURISTIC: a unit that halves the body's distance to its ready pose is going back (recovery)
const MIN_UNIT_M := 0.03    # m: a unit whose end travels less is no move (Critique.ANTIC_BACK, 3 cm)
const FAST_ACTION := 0.10   # s, HEURISTIC: an action (start of the push -> contact) up to this reads fast; longer reads slower / heavier
const LATE_PEAK := 0.6      # HEURISTIC: the speed peaks this late in its push or later = it accelerates into the hit
const EARLY_PEAK := 0.4     # HEURISTIC: this early or earlier = it slows into the contact (soft)
const MJ_PEAK := 0.5        # minimum-jerk reach peaks half way, peak / mean 1.875 (Flash & Hogan 1985, J Neurosci 5(7):1688)
const MJ_PEAK_OVER_MEAN := 1.875
const HOLD_MIN := 2         # samples: a rest this long inside a strike is a hold
const OVERSHOOT_M := 0.01   # m, HEURISTIC: the end going past where it settles by less is no overshoot
const MAX_WORDS := 250
const ENDS := ["hand_l", "hand_r", "foot_l", "foot_r", "weapon_tip"]
const END_WORD := {"hand_l": "left hand", "hand_r": "right hand", "foot_l": "left foot", "foot_r": "right foot", "weapon_tip": "weapon tip"}
const SEG_WORD := {"hip": "hips", "trunk": "chest", "shoulder": "upper arm", "elbow": "forearm"}
const PHASES := ["anticipation", "action", "contact", "follow-through", "recovery"]
## the norms the read is held to: value, unit, trust (N020 words) and where it comes from
const NORMS := {
	"antic_ratio": {"value": TimingCoach.ANTIC_RATIO, "unit": "x", "trust": Trust.H,
		"src": "the action is shorter than its anticipation (Thomas & Johnston, The Illusion of Life 1981, 'Anticipation'; Williams, The Animator's Survival Kit 2001): the order is the books', the 2x is ours (TimingCoach.ANTIC_RATIO)"},
	"ft_ratio": {"value": TimingCoach.SETTLE_RATIO, "unit": "x", "trust": Trust.H,
		"src": "follow-through and overlapping action: the limb settles more slowly than it struck (same books); 1.5x is ours (TimingCoach.SETTLE_RATIO)"},
	"fast_action": {"value": FAST_ACTION, "unit": "s", "trust": Trust.H,
		"src": "timing: fewer frames between the poses read faster and lighter, more read slower and heavier (Thomas & Johnston; Williams, 'Timing'); the 0.1 s line is ours"},
	"peak_at": {"value": MJ_PEAK, "unit": "fraction", "trust": Trust.M,
		"src": "a smooth reach peaks half way, peak / mean speed 1.875 (minimum jerk, Flash & Hogan 1985, J Neurosci 5(7):1688-1703); the 0.4 / 0.6 lines for soft / snappy are ours"},
	"hold": {"value": HOLD_MIN / HZ, "unit": "s", "trust": Trust.H, "src": "a held beat at the top of the wind-up sharpens the hit (moving hold, Williams); the 2-frame bar is ours"},
	"overshoot": {"value": OVERSHOOT_M, "unit": "m", "trust": Trust.H, "src": "follow-through overshoots and settles back (Thomas & Johnston); the 1 cm bar is ours"},
}


# ---------------------------------------------------------------- the clip

## the samples every part reads: EventQuery's clip (points, feet down), the striking-end speeds, Momentum's COM / P. B is put back
static func _sample(S: Scene, B: Body) -> Dictionary:
	var keep := B.state()
	var clip := EventQuery.sample([{"S": S, "B": B, "xf": Transform3D.IDENTITY, "name": S.name}], HZ, {"cross": false, "bal": false})
	var sp := {}
	for e in ENDS:
		var s := EventQuery.speed_series(clip, 0, e)
		var ok := true
		for v in s:
			if is_nan(v):
				ok = false
				break
		if ok:
			sp[e] = s
	var mo := Momentum.sample(S, B)
	B.set_state(keep)
	return {"clip": clip, "speed": sp, "mo": mo}


## the runs of v >= REST_MS, cut at deep dips: [[first, last, peak sample]]
static func units(v: PackedFloat32Array) -> Array:
	var runs := []
	var i := 0
	var n := v.size()
	while i < n:
		if v[i] < REST_MS:
			i += 1
			continue
		var a := i
		while i < n and v[i] >= REST_MS:
			i += 1
		runs.append([a, i - 1])
	var out := []
	for r in runs:
		var parts := [r]
		var changed := true
		while changed:   # cut a run at its deepest dip under HITCH_DIP of the smaller side peak, until none is left
			changed = false
			var np := []
			for q in parts:
				var cut := _dip(v, q[0], q[1])
				if cut < 0:
					np.append(q)
				else:
					np.append([q[0], cut])
					np.append([cut + 1, q[1]])
					changed = true
			parts = np
		for q in parts:
			out.append([q[0], q[1], _argmax(v, q[0], q[1])])
	return out


## the deepest local minimum in [a, b] that is under HITCH_DIP of the smaller peak either side of it, or -1
static func _dip(v: PackedFloat32Array, a: int, b: int) -> int:
	var best := -1
	var best_r := Rulebook.HITCH_DIP
	for m in range(a + 1, b):
		if not (v[m] <= v[m - 1] and v[m] < v[m + 1]):
			continue
		var lp := v[_argmax(v, a, m)]
		var rp := v[_argmax(v, m, b)]
		var r := v[m] / maxf(minf(lp, rp), 1e-9)
		if r < best_r:
			best_r = r
			best = m
	return best


static func _argmax(v: PackedFloat32Array, a: int, b: int) -> int:
	var k := a
	for i in range(a, b + 1):
		if v[i] > v[k]:
			k = i
	return k


## the unit containing sample i (-1 = none)
static func _unit_of(us: Array, i: int) -> int:
	for k in us.size():
		if i >= int(us[k][0]) and i <= int(us[k][1]):
			return k
	return -1


## the end's path length over a unit (m)
static func _travel(pts: Array, a: int, b: int) -> float:
	var d := 0.0
	for i in range(a + 1, b + 1):
		d += ((pts[i] as Vector3) - pts[i - 1]).length()
	return d


## the mean distance of the body's joints at sample i from where they are at sample r (m)
static func _pose_dist(clip: Dictionary, i: int, r: int) -> float:
	var a: PackedVector3Array = clip["pts"][0][i]
	var b: PackedVector3Array = clip["pts"][0][r]
	var s := 0.0
	for k in Body.BODY.size():
		s += a[k].distance_to(b[k])
	return s / Body.BODY.size()


# ---------------------------------------------------------------- phases

## is unit q a wind-up of the strike in unit k (peak pk): every pause from q to k at most ANTIC_GAP, and q prepares it
static func _winds_up(clip: Dictionary, pts: Array, end: String, us: Array, q: int, k: int, pk: int) -> bool:
	for j in range(q, k):
		if int(us[j + 1][0]) - int(us[j][1]) - 1 > ANTIC_GAP:
			return false
	return _travel(pts, us[q][0], us[q][1]) >= MIN_UNIT_M and float(_counter(clip, pts, end, us[q][0], us[k][0], pk)["back"]) >= Critique.ANTIC_BACK


## the preparation in a wind-up that starts at sample q0 (the action starts at a, peaks at pk), in metres, the larger of:
##   COUNTER  the striking end, the pelvis or the centre of mass goes AGAINST its own way to the hit (q0 -> pk) before the action:
##            Critique's ANTICIPATION reading (the swing's way = the chord from the window's start to the peak), on any end
##   LOAD     a hand's or a foot's limb FOLDS first: the shoulder-wrist / hip-ankle distance shrinks (a chambered kick, a fist
##            drawn back) before it extends into the hit. HEURISTIC: "anticipation = the preparation for the action" (Thomas &
##            Johnston), read as either form; the bar is Critique.ANTIC_BACK (3 cm, ours) for both
static func _counter(clip: Dictionary, pts: Array, end: String, q0: int, a: int, pk: int) -> Dictionary:
	var best := 0.0
	var who := ""
	if end != "weapon_tip":
		var root := ("upperarm" if end.begins_with("hand") else "thigh") + end.right(2)
		var rp := EventQuery._pos(clip, 0, root)
		var l0: float = (pts[q0] as Vector3).distance_to(rp[q0])
		for i in range(q0, a):
			var fold: float = l0 - (pts[i] as Vector3).distance_to(rp[i])
			if fold > best:
				best = fold
				who = "load"
	for part in ["end", "pelvis", "com"]:
		var p: Array = pts if part == "end" else EventQuery._pos(clip, 0, part)
		var d: Vector3 = (p[pk] as Vector3) - (p[q0] as Vector3)
		if d.length() < Critique.ANTIC_DIR:
			continue
		var dn := d.normalized()
		for i in range(q0, a):
			var back := -((p[i] as Vector3) - (p[q0] as Vector3)).dot(dn)
			if back > best:
				best = back
				who = part
	return {"back": best, "part": who}


## every strike's phases: [{"pk", "unit", "antic": [a0, a1] or [], "action": [a, pk-1], "contact": pk, "ft": [pk+1, e],
## "rec": [r0, r1] or [], "ready": sample}]
static func phases_of(v: PackedFloat32Array, us: Array, pks: Array, clip: Dictionary, pts: Array, end: String) -> Array:
	var st := []
	for pk in pks:
		st.append({"pk": pk, "unit": _unit_of(us, pk)})
	# in time order: a strike's anticipation (back to the previous strike's follow-through, never into it), then its
	# follow-through (the anticipation fixes the ready pose the return test reads; never into the next strike's own push)
	for s in st.size():
		var k: int = st[s]["unit"]
		var floor_k: int = int(st[s - 1]["ft_last"]) if s > 0 else -1
		var first := k
		var q := k - 1
		var a0 := int(us[k][0])
		while q > floor_k:
			var gap := int(us[q + 1][0]) - int(us[q][1]) - 1
			if gap > ANTIC_GAP:
				break
			if _travel(pts, us[q][0], us[q][1]) >= MIN_UNIT_M and float(_counter(clip, pts, end, us[q][0], a0, int(st[s]["pk"]))["back"]) >= Critique.ANTIC_BACK:
				first = q
			q -= 1
		st[s]["first"] = first
		var a := int(us[k][0])
		st[s]["action"] = [a, int(st[s]["pk"]) - 1]
		st[s]["antic"] = [int(us[first][0]), a - 1] if first < k else []
		st[s]["ready"] = int(us[first][0]) if first < k else a
		var lim: int = int(st[s + 1]["unit"]) if s + 1 < st.size() else us.size()
		var e := int(us[k][1])
		q = k + 1
		while q < lim:
			var gap := int(us[q][0]) - e - 1
			if gap > FT_GAP:
				break
			if s + 1 < st.size() and _winds_up(clip, pts, end, us, q, lim, int(st[s + 1]["pk"])):
				break   # it already prepares the next strike: that strike's anticipation, not this one's follow-through
			var d0 := _pose_dist(clip, us[q][0], st[s]["ready"])
			var d1 := _pose_dist(clip, us[q][1], st[s]["ready"])
			if d1 <= RETURN * d0:
				break   # going back toward the ready pose: that is the recovery
			e = int(us[q][1])
			q += 1
		st[s]["ft"] = [int(st[s]["pk"]) + 1, e]
		st[s]["ft_last"] = q - 1
	# recovery: what is left between a strike's follow-through and the next strike's anticipation
	for s in st.size():
		var r0: int = int(st[s]["ft_last"]) + 1
		var r1: int = (int(st[s + 1]["first"]) if s + 1 < st.size() else us.size()) - 1
		st[s]["rec"] = [int(us[r0][0]), int(us[r1][1])] if r1 >= r0 else []
	return st


# ---------------------------------------------------------------- the explanation

static func _r(x: float, d := 2) -> float:
	return snappedf(x, pow(10.0, -d))


## a span of samples -> {"t0", "t1", "s", "f0", "f1"} (f = frames at the scene's fps, the timeline's numbers)
static func _span(a: int, b: int, fps: float) -> Dictionary:
	return {"t0": _r(a / HZ, 3), "t1": _r(b / HZ, 3), "s": _r((b - a + 1) / HZ, 3), "f0": int(round(a / HZ * fps)), "f1": int(round(b / HZ * fps)),
		"i0": a, "i1": b}


## explain the scene S on body B. opt: {"t0", "t1"} (s) or {"card": N (1-based)} = the window the main strike's peak is looked
## for in; "scene_path" = the file the try command names. B is put back; S is not written.
static func explain(S: Scene, B: Body, opt := {}) -> Dictionary:
	if S.cards.size() < 2:
		return {"ok": false, "error": "explain needs a scene of 2+ cards: open one first"}
	var L := S.length()
	var w0 := 0.0
	var w1 := L
	if opt.has("card"):
		var c := int(opt["card"])
		if c < 1 or c > S.cards.size():
			return {"ok": false, "error": "no card %d (the scene has %d)" % [c, S.cards.size()]}
		var ts := S.times()
		w0 = float(ts[c - 1][0])
		w1 = float(ts[c - 1][2])
	if opt.has("t0") or opt.has("t1"):
		w0 = float(opt.get("t0", 0.0))
		w1 = float(opt.get("t1", L))
	if w1 < w0:
		return {"ok": false, "error": "t1 (%.2f s) is before t0 (%.2f s)" % [w1, w0]}
	var smp := _sample(S, B)
	var clip: Dictionary = smp["clip"]
	var n: int = clip["n"]
	var i0 := clampi(int(floor(w0 * HZ)), 0, n - 1)
	var i1 := clampi(int(ceil(w1 * HZ)), 0, n - 1)
	# the striking end: the fastest end in the window
	var end := ""
	var top := -1.0
	for e in ENDS:
		if not smp["speed"].has(e):
			continue
		var s: PackedFloat32Array = smp["speed"][e]
		var k := _argmax(s, i0, i1)
		if s[k] > top:
			top = s[k]
			end = e
	var v: PackedFloat32Array = smp["speed"][end]
	var pts := EventQuery._pos(clip, 0, end)
	var all_pk := []
	for x in Rulebook.strikes(Array(v)):
		all_pk.append(int(x["pk"]))
	var main := -1
	for pk in all_pk:
		if pk >= i0 and pk <= i1 and (main < 0 or v[pk] > v[main]):
			main = pk
	var head := {"ok": true, "scene": S.name, "window": {"t0": _r(w0, 3), "t1": _r(w1, 3)}, "fps": S.fps, "hz": HZ,
		"end": {"part": end, "word": END_WORD[end], "peak_ms": _r(top)}}
	if main < 0:
		head["phases"] = []
		head["strikes"] = []
		head["power"] = {}
		head["read"] = {"words": ["no strike"]}
		head["try"] = {}
		head["text"] = "No strike here: the fastest end, the %s, peaks at %.1f m/s, under the %.1f m/s a strike needs. Explain reads strikes; pick a card span with a hit in it." % [END_WORD[end], top, Rulebook.STRIKE_MIN]
		head["sentences"] = [{"s": head["text"], "fields": ["end.peak_ms"]}]
		head["words"] = _count_words(head["text"])
		return head
	var us := units(v)
	var st := phases_of(v, us, all_pk, clip, pts, end)
	var si := all_pk.find(main)
	var ms: Dictionary = st[si]
	var fps := float(S.fps)
	# --- phases
	var phases := []
	if not (ms["antic"] as Array).is_empty():
		phases.append(_phase("anticipation", ms["antic"][0], ms["antic"][1], fps))
	phases.append(_phase("action", ms["action"][0], ms["action"][1], fps))
	phases.append(_phase("contact", main, main, fps))
	phases.append(_phase("follow-through", ms["ft"][0], ms["ft"][1], fps))
	if not (ms["rec"] as Array).is_empty():
		phases.append(_phase("recovery", ms["rec"][0], ms["rec"][1], fps))
	var p0: int = phases[0]["i0"]
	var p1: int = phases[-1]["i1"]
	# feet (N017 contacts): the plants and lifts inside the strike
	var feet := _foot_events(clip, p0, p1, main)
	for ph in phases:
		ph["events"] = feet.filter(func(f): return int(f["i"]) >= int(ph["i0"]) and int(f["i"]) <= int(ph["i1"])).map(func(f): return f["what"] + " at %.2f s" % f["t"])
	var strikes := []
	for k in all_pk.size():
		strikes.append({"t": _r(all_pk[k] / HZ, 3), "speed_ms": _r(v[all_pk[k]]), "card": Rulebook.card_at(S, all_pk[k] / HZ) + 1, "main": all_pk[k] == main,
			"in_window": all_pk[k] >= i0 and all_pk[k] <= i1})
	# --- power
	var power := _power(S, B, smp, ms, main, pts, end, i0 == 0 and i1 == n - 1)
	power["feet"] = feet
	# --- read
	var read := _read(S, B, v, us, ms, main, pts, clip, p0, p1, end)
	var out := head
	out["phases"] = phases
	out["strikes"] = strikes
	out["power"] = power
	out["read"] = read
	out["try"] = _try(S, opt, ms, read, power, main, phases)
	var sen := _sentences(out)
	out["sentences"] = sen
	out["text"] = " ".join(sen.map(func(x): return x["s"]))
	out["words"] = _count_words(out["text"])
	return out


static func _phase(nm: String, a: int, b: int, fps: float) -> Dictionary:
	var d := _span(a, b, fps)
	d["phase"] = nm
	return d


## the feet's plants and lifts (EventQuery's down bits, Balance's own 1 cm footprint test) in [a, b]
static func _foot_events(clip: Dictionary, a: int, b: int, pk: int) -> Array:
	var dn: PackedByteArray = clip["down"][0]
	var out := []
	for i in range(maxi(a, 1), b + 1):
		for sd in [["_l", 1, "left foot"], ["_r", 2, "right foot"]]:
			var was := (dn[i - 1] & int(sd[1])) != 0
			var now := (dn[i] & int(sd[1])) != 0
			if was != now:
				out.append({"i": i, "t": _r(i / HZ, 3), "foot": sd[0], "what": "%s %s" % [sd[2], "plants" if now else "lifts"],
					"plants": now, "from_contact_ms": _r((i - pk) * 1000.0 / HZ, 0)})
	return out


## I8 + I36: the power chain on this strike's window, its peak angular speeds, the COM travel and the momentum at contact
static func _power(S: Scene, B: Body, smp: Dictionary, ms: Dictionary, pk: int, pts: Array, end: String, whole_clip: bool) -> Dictionary:
	var keep := B.state()
	var cap := ForceView.capture(S, B)
	B.set_state(keep)
	var out := {}
	if not cap.is_empty():
		var n: int = cap["n"]
		# the chain is ForceView.chain_of exactly as the Force view calls it (I8's answer, bit for bit) on the whole clip; on a
		# window (card / t0-t1) the hands and bat outside this strike's span are held still, so the tip it picks is this strike's
		var a := clampi(int(floor(float(ms["ready"]) / HZ * ForceView.HZ)), 0, n - 1)
		var b := clampi(int(ceil(float(ms["ft"][1]) / HZ * ForceView.HZ)), 0, n - 1)
		var tips: Array = cap["tips"]
		var bat: Array = cap["bat"]
		if whole_clip:
			pass   # the whole clip: I8's own call, its own fastest tip
		else:
			tips = []
			bat = []
			for i in n:
				var j := clampi(i, a, b)
				tips.append(cap["tips"][j])
				bat.append(cap["bat"][j])
		var ch := ForceView.chain_of({}, cap["gtrack"], tips, bat, n)
		var order := ForceView.CHAIN.duplicate()
		order.sort_custom(func(x, y): return float(ch["peak"][x]) < float(ch["peak"][y]) or (float(ch["peak"][x]) == float(ch["peak"][y]) and ForceView.CHAIN.find(x) < ForceView.CHAIN.find(y)))
		var pdeg := {}
		var most := ""
		for nm in ForceView.CHAIN:
			var om: Array = ch["omega"][nm]
			var mx := 0.0
			for i in range(int(ch["a"]), int(ch["b"]) + 1):
				mx = maxf(mx, float(om[i]))
			pdeg[nm] = _r(rad_to_deg(mx), 0)
			if most == "" or float(pdeg[nm]) > float(pdeg[most]):
				most = nm
		var peaks := {}
		for nm in ForceView.CHAIN:
			peaks[nm] = _r(float(ch["peak"][nm]), 3)
		out["chain"] = {"side": String(ch["side"]).substr(1), "order": order, "in_order": bool(ch["ok"]), "peak_t": peaks,
			"peak_degs": pdeg, "most": most, "spread_ms": _r((float(ch["peak"][order[-1]]) - float(ch["peak"][order[0]])) * 1000.0, 0),
			"tip_peak_t": _r(float(ch["t_star"]), 3), "limb_matches": not end.begins_with("foot"),
			"source": "ForceView.chain_of (I8): Putnam 1993, J Biomech 26 Suppl 1:125, proximal-to-distal peaks", "trust": Trust.M}
	var mo: Dictionary = smp["mo"]
	if not mo.is_empty():
		var com: Array = mo["com"]
		var P: Array = mo["P"]
		var nm := com.size()
		var r := clampi(int(ms["ready"]), 0, nm - 1)
		var a := clampi(int(ms["action"][0]), 0, nm - 1)
		var c := clampi(pk, 0, nm - 1)
		var e := clampi(int(ms["ft"][1]), 0, nm - 1)
		var d: Vector3 = (pts[pk] as Vector3) - (pts[int(ms["action"][0])] as Vector3)
		var u := Vector3(d.x, 0.0, d.z)
		u = u.normalized() if u.length() > 1e-6 else Vector3.ZERO
		var back := 0.0
		for i in range(r, a + 1):
			back = maxf(back, -((com[i] as Vector3) - (com[r] as Vector3)).dot(u))
		var pmax := -INF
		var pmax_i := c
		for i in range(a, e + 1):
			var pu := (P[i] as Vector3).dot(u)
			if pu > pmax:
				pmax = pu
				pmax_i = i
		out["weight"] = {"mass_kg": _r(float(mo["mass"]), 1), "com_back_cm": _r(back * 100.0, 1),
			"com_to_target_cm": _r(((com[c] as Vector3) - (com[r] as Vector3)).dot(u) * 100.0, 1),
			"com_after_cm": _r(((com[e] as Vector3) - (com[c] as Vector3)).dot(u) * 100.0, 1),
			"p_contact": _r((P[c] as Vector3).dot(u), 1), "p_peak": _r(pmax, 1), "p_peak_from_contact_ms": _r((pmax_i - c) * 1000.0 / HZ, 0),
			"source": "Momentum.sample (I36): de Leva 1996 masses, P = M dCOM/dt; toward the target = the end's horizontal way from the action's start to contact",
			"trust": Trust.M}
	return out


## the read: timing ratios, ease, holds, overshoot, arc kinks, craft notes -> words
static func _read(S: Scene, B: Body, v: PackedFloat32Array, us: Array, ms: Dictionary, pk: int, pts: Array, clip: Dictionary, p0: int, p1: int, end: String) -> Dictionary:
	var a: int = ms["action"][0]
	var has_antic := not (ms["antic"] as Array).is_empty()
	var antic_s := (a - int(ms["antic"][0])) / HZ if has_antic else 0.0
	var action_s := maxf(pk - a, 1) / HZ
	var ft_s := (int(ms["ft"][1]) - pk) / HZ
	var ue: int = us[ms["unit"]][1]
	var push := float(pk - a) / maxf(float(ue - a), 1.0)
	var mean := 0.0
	for i in range(a, ue + 1):
		mean += v[i]
	mean /= float(ue - a + 1)
	# the holds inside the strike (the end at rest for HOLD_MIN samples or more)
	var holds := []
	var i := p0
	while i <= p1:
		if v[i] >= REST_MS:
			i += 1
			continue
		var h0 := i
		while i <= p1 and v[i] < REST_MS:
			i += 1
		if i - h0 >= HOLD_MIN:
			holds.append({"t0": _r(h0 / HZ, 3), "t1": _r((i - 1) / HZ, 3), "s": _r((i - h0) / HZ, 3), "before_action": i - 1 < a})
	var hold_top := 0.0
	for h in holds:
		if h["before_action"]:
			hold_top += float(h["s"])
	# overshoot: in the follow-through the end goes past the point it settles at
	var over := 0.0
	var P0: Vector3 = pts[pk]
	var P1: Vector3 = pts[int(ms["ft"][1])]
	var dd := P1 - P0
	if dd.length() > OVERSHOOT_M:
		var dn := dd.normalized()
		for k in range(pk, int(ms["ft"][1]) + 1):
			over = maxf(over, ((pts[k] as Vector3) - P0).dot(dn) - dd.length())
	# arc kinks on the end's path over the strike (ArcCheck's own test; a foot on the floor is a contact, not a path)
	var path := pts.slice(p0, p1 + 1)
	var ok := []
	var bit := 0 if not end.begins_with("foot") else (1 if end.ends_with("_l") else 2)
	var dn: PackedByteArray = clip["down"][0]
	for k in range(p0, p1 + 1):
		ok.append(bit == 0 or (dn[k] & bit) == 0)
	var kinks := ArcCheck.kinks_in(path, ok, HZ)
	var worst := 0.0
	for kk in kinks:
		worst = maxf(worst, float(kk["angle"]))
	# Critique's craft notes and the rulebook's findings over ONE Rulebook sample (the body is put back)
	var keep := B.state()
	var rsm := Rulebook.sample(S, B)
	var notes := Critique.check(S, B, rsm)
	var rules := Rulebook.check(S, B, rsm)
	B.set_state(keep)
	var t0 := p0 / HZ - 0.05
	var t1 := p1 / HZ + 0.05
	var mine := notes.filter(func(f): return float(f["t"]) >= t0 and float(f["t"]) <= t1)
	var words := []
	words.append("fast" if action_s <= FAST_ACTION + 1e-6 else "slower / heavier")
	if not has_antic:
		words.append("no anticipation")
	elif antic_s < TimingCoach.ANTIC_RATIO * action_s:
		words.append("short anticipation")
	if push >= LATE_PEAK:
		words.append("snappy" if action_s <= FAST_ACTION + 1e-6 else "accelerates into the hit")
	elif push <= EARLY_PEAK:
		words.append("soft contact")
	if hold_top >= HOLD_MIN / HZ and action_s <= FAST_ACTION + 1e-6 and not words.has("snappy"):
		words.append("snappy")
	if mine.any(func(f): return f["rule"] == "FLOATY"):
		words.append("floaty")
	if mine.any(func(f): return f["rule"] == "FOLLOW-THROUGH"):
		words.append("dead stop")
	if ft_s < TimingCoach.SETTLE_RATIO * action_s:
		words.append("short follow-through")
	# the rulebook's HITCH at the contact (a dead stop at a card between two fast moves): its Fix makes that card flow
	var hitch := -1
	for k in rules.size():
		if rules[k]["rule"] == "HITCH" and absf(float(rules[k]["t"]) - pk / HZ) <= 0.15 and hitch < 0:
			hitch = k + 1
	return {"words": words, "antic_s": _r(antic_s, 3), "action_s": _r(action_s, 3), "ft_s": _r(ft_s, 3),
		"antic_ratio": _r(antic_s / action_s, 1), "ft_ratio": _r(ft_s / action_s, 1), "has_antic": has_antic,
		"peak_at": _r(push), "peak_over_mean": _r(v[pk] / maxf(mean, 1e-6)), "hold_top_s": _r(hold_top, 3), "holds": holds,
		"overshoot_cm": _r(over * 100.0, 1), "kinks": kinks.size(), "worst_kink_deg": _r(worst, 0),
		"notes": mine.map(func(f): return {"rule": f["rule"], "t": _r(float(f["t"]), 2), "t1": _r(float(f.get("t1", f["t"])), 2), "msg": f["msg"]}),
		"hitch_fix": hitch, "end": end, "norms": NORMS}


## the one change most likely to help, highest first: no anticipation > short anticipation > dead stop / short follow-through >
## floaty > soft contact; nothing = an N019 sweep of the strike's timing
static func _try(S: Scene, opt: Dictionary, ms: Dictionary, read: Dictionary, power: Dictionary, pk: int, phases: Array) -> Dictionary:
	var path := String(opt.get("scene_path", "scenes/<scene>.json"))
	if path.begins_with("res://"):
		path = path.substr(6)
	var cpk := Rulebook.card_at(S, pk / HZ)   # 0-based: the card the contact falls in
	var ca := Rulebook.card_at(S, int(ms["action"][0]) / HZ)
	var steps := []
	var why := ""
	var expect := ""
	var w: Array = read["words"]
	if w.has("no anticipation"):
		var prev := maxi(ca - 1, 0)   # the card the action starts from: the wind-up goes in after it
		var end: String = read["end"]
		var side := ("right" if end.ends_with("_r") else "left") if end != "weapon_tip" else ("right" if String(power.get("chain", {}).get("side", "r")) == "r" else "left")
		var words := "turn the chest %s 20, lean the chest back 5" % side   # a swing: the shoulders turn away, the tip goes back
		if end.begins_with("hand"):
			words = "bend the %s elbow 40, swing the %s arm back 20, turn the chest %s 15" % [side, side, side]   # the fist drawn back
		elif end.begins_with("foot"):
			words = "raise the %s leg 45, bend the %s knee 90" % [side, side]   # a chamber: the leg folds before it extends
		# the new card (Scene.add: an auto move, a 0.3 s hold) at 50 %: a 0.15 s hold at the top keeps it within ANTIC_GAP of the hit
		steps = ["card=%d" % (prev + 1), "add", "pose=" + words, "update", "name=wind-up", "retime=%d-%d:50" % [prev + 2, prev + 2]]
		why = "the strike starts from rest with nothing going the other way first, so the eye has no warning and the hit has no weight; a wind-up card (the %s drawn back first) gives it one" % ("leg" if end.begins_with("foot") else ("fist" if end.begins_with("hand") else "weapon"))
		expect = "anticipation > 0 s"
	elif w.has("short anticipation"):
		var a0 := Rulebook.card_at(S, int(ms["antic"][0]) / HZ)
		var pct := clampf(100.0 * TimingCoach.ANTIC_RATIO / maxf(float(read["antic_ratio"]), 0.1), 110.0, 300.0)
		steps = ["retime=%d-%d:%d" % [a0 + 1, maxi(ca, a0) + 1, int(round(pct))]]
		why = "the wind-up is %.1fx the action, under the %.0fx that reads clearly: stretch the wind-up cards" % [read["antic_ratio"], TimingCoach.ANTIC_RATIO]
		expect = "antic_ratio >= %.0f" % TimingCoach.ANTIC_RATIO
	elif w.has("dead stop") or w.has("short follow-through"):
		if int(read["hitch_fix"]) > 0:
			steps = ["fix=%d" % int(read["hitch_fix"])]
			why = "the end stops dead at the contact card and starts again; Check's HITCH fix lets the body flow through that card"
			expect = "no dead stop"
		else:
			steps = ["card=%d" % mini(cpk + 2, S.cards.size()), "ease_out"]
			why = "the follow-through is %.1fx the action, under %.1fx: the end stops too soon after the hit; an ease out on the move after it keeps it going and slows it" % [read["ft_ratio"], TimingCoach.SETTLE_RATIO]
			expect = "ft_ratio >= %.1f" % TimingCoach.SETTLE_RATIO
	elif w.has("floaty"):
		var fn: Array = (read["notes"] as Array).filter(func(f): return f["rule"] == "FLOATY")
		var c0 := Rulebook.card_at(S, float(fn[0]["t"]))
		var c1 := maxi(Rulebook.card_at(S, float(fn[0]["t1"])), c0)
		steps = ["retime=%d-%d:80" % [c0 + 1, c1 + 1]]
		why = "in the air the body falls slower than gravity pulls; shorter air time (those cards at 80%) brings the fall closer to g"
		expect = "no FLOATY note"
	elif w.has("soft contact"):
		steps = ["card=%d" % (cpk + 1), "card_ease_like_a_real_strike"]
		why = "the speed peaks early and the end slows into the contact; the measured strike ease puts the peak late"
		expect = "peak_at >= %.1f" % LATE_PEAK
	else:
		steps = ["retime=%d-%d:{pct}" % [ca + 1, cpk + 1]]
		why = "nothing stands out: feel the tempo by sweeping the strike's timing (N019 try)"
		expect = "pick the variant that reads best"
		return {"steps": steps, "why": why, "expect": expect,
			"cli": "poser_cli try %s %s --sweep pct=80,90,100,110,120" % [path, steps[0]]}
	var out := "scenes/_wip/%s_try.json" % path.get_file().get_basename()
	return {"steps": steps, "why": why, "expect": expect, "cli": "poser_cli run %s %s --out %s" % [path, " ".join(steps.map(func(s): return ('"%s"' % s) if " " in s else s)), out]}


## the text: sentences, each with the JSON fields its numbers come from
static func _sentences(o: Dictionary) -> Array:
	var out := []
	var ph: Array = o["phases"]
	var by := {}
	for p in ph:
		by[p["phase"]] = p
	var ew: String = o["end"]["word"]
	var parts := []
	var fl := []
	for k in ph.size():
		var p: Dictionary = ph[k]
		if p["phase"] == "contact":
			parts.append("contact at %.2f s (frame %d)" % [p["t0"], p["f0"]])
		else:
			parts.append("%s %.2f-%.2f s (frames %d-%d)" % [p["phase"], p["t0"], p["t1"], p["f0"], p["f1"]])
		fl.append("phases.%d" % k)
	out.append({"s": "Phases, read from the %s's speed: %s." % [ew, ", ".join(parts)], "fields": fl})
	if not by.has("anticipation"):
		out.append({"s": "There is no anticipation: the %s goes straight from rest into the hit." % ew, "fields": ["read.has_antic"]})
	if not by.has("recovery"):
		out.append({"s": "No recovery: it flows into the next move.", "fields": ["phases"]})
	var ns: int = (o["strikes"] as Array).filter(func(x): return x["in_window"]).size()
	if ns > 1:
		out.append({"s": "This is the fastest of %d strikes in the window (%.1f m/s)." % [ns, o["end"]["peak_ms"]], "fields": ["strikes", "end.peak_ms"]})
	else:
		out.append({"s": "The %s peaks at %.1f m/s." % [ew, o["end"]["peak_ms"]], "fields": ["end.peak_ms"]})
	var pw: Dictionary = o["power"]
	if pw.has("chain"):
		var ch: Dictionary = pw["chain"]
		if not ch["limb_matches"]:
			out.append({"s": "The I8 power chain reads the arms, and this strike is a kick, so it is not judged here.", "fields": ["power.chain.limb_matches"]})
		else:
			var ow := " > ".join((ch["order"] as Array).map(func(x): return SEG_WORD[x]))
			var same: bool = ch["order"] == ForceView.CHAIN
			var verdict := "in order" if same else ("in order within I8's tie of 1 sample" if ch["in_order"] else "OUT OF ORDER (a strong strike peaks hips, chest, upper arm, forearm)")
			out.append({"s": "Power chain (%s side): %s, %s, spread over %d ms; the %s %s fastest (%d deg/s)." % [ch["side"], ow, verdict, ch["spread_ms"],
				SEG_WORD[ch["most"]], "turn" if ch["most"] == "hip" else "turns", ch["peak_degs"][ch["most"]]],
				"fields": ["power.chain.order", "power.chain.in_order", "power.chain.spread_ms", "power.chain.most", "power.chain.peak_degs"]})
	if pw.has("weight"):
		var wt: Dictionary = pw["weight"]
		out.append({"s": "Weight: the centre of mass loads %.1f cm back, travels %.1f cm toward the target by contact, and the body carries %.1f kg m/s toward it at contact." % [wt["com_back_cm"], wt["com_to_target_cm"], wt["p_contact"]],
			"fields": ["power.weight.com_back_cm", "power.weight.com_to_target_cm", "power.weight.p_contact"]})
	var plants: Array = (pw.get("feet", []) as Array).filter(func(f): return f["plants"] and absf(float(f["from_contact_ms"])) <= 150.0)
	if not plants.is_empty():
		var f0: Dictionary = plants[0]
		out.append({"s": "The %s %s %d ms %s contact." % [String(f0["what"]).trim_suffix(" plants"), "plants", absi(int(f0["from_contact_ms"])), "before" if float(f0["from_contact_ms"]) <= 0.0 else "after"],
			"fields": ["power.feet"]})
	var rd: Dictionary = o["read"]
	out.append({"s": "It reads %s." % ", ".join(rd["words"]), "fields": ["read.words"]})
	var tim := "Anticipation %.2f s against an action of %.2f s (%.1fx; %.0fx or more reads clearly, HEURISTIC); follow-through %.2f s (%.1fx; %.1fx or more settles, HEURISTIC)." % [
		rd["antic_s"], rd["action_s"], rd["antic_ratio"], TimingCoach.ANTIC_RATIO, rd["ft_s"], rd["ft_ratio"], TimingCoach.SETTLE_RATIO]
	out.append({"s": tim, "fields": ["read.antic_s", "read.action_s", "read.antic_ratio", "read.ft_s", "read.ft_ratio", "read.norms"]})
	out.append({"s": "The speed peaks %d%% of the way through its push (a smooth reach peaks at 50%%, Flash & Hogan 1985), %.1fx its mean." % [int(round(float(rd["peak_at"]) * 100.0)), rd["peak_over_mean"]],
		"fields": ["read.peak_at", "read.peak_over_mean", "read.norms.peak_at"]})
	var ex := []
	var exf := []
	if float(rd["hold_top_s"]) > 0.0:
		ex.append("a %.2f s hold before the hit" % rd["hold_top_s"])
		exf.append("read.hold_top_s")
	if float(rd["overshoot_cm"]) > 0.0:
		ex.append("%.1f cm of overshoot" % rd["overshoot_cm"])
		exf.append("read.overshoot_cm")
	ex.append(("%d arc kinks (worst %d deg)" % [rd["kinks"], rd["worst_kink_deg"]]) if int(rd["kinks"]) > 0 else "a smooth arc (0 kinks)")
	exf.append("read.kinks")
	out.append({"s": "It has %s." % ", ".join(ex), "fields": exf})
	var tr: Dictionary = o["try"]
	if not tr.is_empty():
		out.append({"s": "Try: %s. `%s`" % [tr["why"], tr["cli"]], "fields": ["try.why", "try.cli"]})
	return out


static func _count_words(t: String) -> int:
	var n := 0
	for w in t.split(" ", false):
		if w.strip_edges() != "":
			n += 1
	return n


# ---------------------------------------------------------------- the live app

## serve's `explain {card? | t0?, t1?}` on the live poser (its scene and body; the body is put back, the scene untouched)
static func serve(m: Node, p: Dictionary) -> Dictionary:
	var opt := {"scene_path": String(m.scene_path) if "scene_path" in m else ""}
	for k in ["card", "t0", "t1"]:
		if p.has(k):
			if not (p[k] is int or p[k] is float):
				return {"ok": false, "error": "explain {card: N} or {t0: s, t1: s}: %s must be a number" % k}
			opt[k] = p[k]
	return explain(m.S, m.ov.GB, opt)   # Check's own grading body (Critique and Rulebook.check read it): the live body is not touched


## the Explain button (CHECK panel, beside Critique): the text in the panel's list; theme tokens only
static func show(m: Node) -> void:
	if m.S.cards.size() < 2:
		m._say("Explain needs a scene of two cards or more: add a card first")
		return
	var r := serve(m, {})
	var list: Node = m.ui_find_list
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	var head := HBoxContainer.new()
	list.add_child(head)
	var title: Label = m._label("EXPLAIN THIS MOTION", 18, "heading")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", m._close_findings))
	for s in r.get("sentences", [{"s": r.get("error", "")}]):
		var l: Label = m._label(String(s["s"]), 14, "text:0.85", true)
		l.custom_minimum_size = Vector2(380, 0)
		list.add_child(l)
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(400, clampf(60.0 + 40.0 * list.get_child_count(), 60.0, 440.0))
	m.ui_find.visible = true
	m._say("explain: %d words. Every number is in serve `explain`'s JSON." % int(r.get("words", 0)))
