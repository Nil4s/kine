## hit_habits.gd - MY HIT REACTIONS (ROADMAP I46). When HitReaction (hit_reaction.gd) or Reaction direction (reaction_dir.gd) writes a reaction on a
## fighter, this watches the written cards. When Nick edits them (scales the poses, shifts the start, lengthens the recovery) the edit settles
## after SETTLE_S without another change, or at the end of EDIT_WINDOW_S (the journal's 2 minutes), and is measured against the written reaction
## and the fighter's own animation as ONE lesson in the SuggestionJournal (user:// only):
##   amp    peak deviation from the animation (the norm over every joint's three angles), edited / written
##   delay  the frame the deviation first reaches ONSET_FRAC (10 %) of its own peak, edited minus written, in frames of the scene
##   rec    recovery = from the peak until the deviation is back under ONSET_FRAC of the peak, edited / written
##   J      the impulse (kg m/s) of the blow, to file the lesson in a band
## habit(): the medians of the lessons (amplitude per J band when that band has MIN_LESSONS of its own, else all of them) with the count. Fewer than
## MIN_LESSONS lessons: the physics default is kept and the line says why. An undone reaction is not a lesson (undo_n). Nothing is written but the
## journal's own file.
class_name HitHabits
extends RefCounted

const SRC := "hit reaction"
const KIND := "edit"
const MIN_LESSONS := 3
const SETTLE_S := 2.0
const EDIT_WINDOW_S := 120.0
const ONSET_FRAC := 0.10
const STEP := 1.0 / 240.0
const MIN_PEAK_DEG := 0.5     # a written reaction that deviates less than this has no amplitude to scale
## J bands, kg m/s. HEURISTIC cut-offs (not a measured table): a jab of ~2.5 kg effective mass at 4 m/s is ~10, a straight at 8 m/s ~20+.
const BANDS := [10.0, 25.0]
const BAND_NAMES := ["light", "medium", "hard"]

var sj: SuggestionJournal
var pending: Array = []   # [{vk, base: Scene, written: Scene, hash, changed_at, born, t0, t1, J, undo_n, changed}]
var physics_only := false # the key: the plain physics default instead of my usual
var last_text := ""       # the line of the last reaction ("your usual ..." or why not)


func _init(journal: SuggestionJournal) -> void:
	sj = journal


static func band_of(J: float) -> int:
	return 0 if J < float(BANDS[0]) else (1 if J < float(BANDS[1]) else 2)


static func median(a: Array) -> float:
	if a.is_empty():
		return NAN
	var b := a.duplicate()
	b.sort()
	var n := b.size()
	return float(b[n / 2]) if n % 2 == 1 else 0.5 * (float(b[n / 2 - 1]) + float(b[n / 2]))


## what Nick usually does: {"on", "n", "amp", "delay_f", "rec", "band", "text"}; on = false keeps the physics default and text says why
func habit(J: float, fps: int) -> Dictionary:
	var rows := sj.habit_rows(SRC, KIND)
	var n := rows.size()
	if physics_only:
		return {"on": false, "n": n, "text": "physics default (you pressed the key for it; press it again for your usual)"}
	if n < MIN_LESSONS:
		return {"on": false, "n": n, "text": "physics default: only %d edit%s learned, %d needed before I use your usual" % [n, "" if n == 1 else "s", MIN_LESSONS]}
	var b := band_of(J)
	var in_band := rows.filter(func(r): return band_of(float(r.get("J", 0.0))) == b)
	var amp_rows := in_band if in_band.size() >= MIN_LESSONS else rows
	var amp := median(amp_rows.map(func(r): return float(r["amp"])))
	var dl := median(rows.map(func(r): return float(r["delay"])))
	var rc := median(rows.map(func(r): return float(r["rec"])))
	var df := roundi(dl)
	var txt := "your usual x%.1f amplitude%s, %s, recovery x%.1f (from %d edits)" % [
		amp, " for %s hits" % BAND_NAMES[b] if amp_rows == in_band and absf(amp - median(rows.map(func(r): return float(r["amp"])))) > 0.005 else "", ("%+d frame%s" % [df, "" if absi(df) == 1 else "s"]) if df != 0 else "no shift in the start", rc, n]
	return {"on": true, "n": n, "amp": amp, "delay_f": dl, "rec": rc, "band": b, "text": txt, "fps": fps}


## the Callable HitReaction.react wants (J length -> the habit as react's dict; {} = physics); last_text keeps the line
func chooser(fps: int) -> Callable:
	return func(Jlen: float) -> Dictionary:
		var h := habit(Jlen, fps)
		last_text = String(h["text"])
		return {} if not h["on"] else {"amp": h["amp"], "delay_s": float(h["delay_f"]) / float(fps), "rec": h["rec"], "text": h["text"]}


# ------------------------------------------------------------------------------------------------ measuring an edit

## deviation norm (deg) of a scene from the base scene at each STEP in [a, b]
static func dev_series(base: Scene, sc: Scene, B: Body, a: float, b: float) -> Array:
	var keep := B.state()
	var out := []
	var n := int(ceil((b - a) / STEP))
	for k in n + 1:
		var t := a + float(k) * STEP
		base.apply(B, t)
		var g: Dictionary = B.ang.duplicate()
		sc.apply(B, t)
		var s2 := 0.0
		for j in g:
			if B.ang.has(j):
				s2 += ((B.ang[j] as Vector3) - (g[j] as Vector3)).length_squared()
		out.append(sqrt(s2))
	B.set_state(keep)
	return out


## {"peak", "t_peak", "onset", "rec"} (seconds from the series start) of a deviation series
static func shape(ser: Array) -> Dictionary:
	var pk := 0.0
	var ip := 0
	for i in ser.size():
		if float(ser[i]) > pk:
			pk = float(ser[i])
			ip = i
	var lim := pk * ONSET_FRAC
	var on := 0
	for i in ser.size():
		if float(ser[i]) >= lim:
			on = i
			break
	var re := ser.size() - 1
	for i in range(ip, ser.size()):
		if float(ser[i]) <= lim:
			re = i
			break
	return {"peak": pk, "t_peak": float(ip) * STEP, "onset": float(on) * STEP, "rec": float(re - ip) * STEP}


## the lesson of an edit: {amp, delay (frames), rec} or {} when the written reaction has no amplitude. B is any posed body.
static func measure(base: Scene, written: Scene, edited: Scene, B: Body, t0: float, t1: float) -> Dictionary:
	var a := maxf(0.0, t0 - 0.15)
	var b := t1 + 0.6
	var w := shape(dev_series(base, written, B, a, b))
	var e := shape(dev_series(base, edited, B, a, b))
	if float(w["peak"]) < MIN_PEAK_DEG:
		return {}
	var rec_w := maxf(float(w["rec"]), STEP)
	return {"amp": float(e["peak"]) / float(w["peak"]), "delay": (float(e["onset"]) - float(w["onset"])) * float(base.fps), "rec": float(e["rec"]) / rec_w}


# ------------------------------------------------------------------------------------------------ watching

## a reaction was just written. base = the fighter's scene before, written = after (clones), r = HitReaction.react's result
func watch(vk: int, base: Scene, written: Scene, t0: float, t1: float, J: float, undo_n: int) -> void:
	pending = pending.filter(func(e): return int(e["vk"]) != vk)   # a newer reaction on the same fighter replaces the old watch
	pending.append({"vk": vk, "base": base.clone(), "written": written.clone(), "hash": written.cards.hash(), "t0": t0, "t1": t1, "J": J, "undo_n": undo_n,
		"born": sj._t(), "changed_at": -1.0})


## every frame: cur(vk) -> the fighter's scene now (or null); body: any Body to pose. Returns lessons recorded this call.
func observe(undo_n: int, cur: Callable, body: Body) -> int:
	var made := 0
	var keep := []
	var t := sj._t()
	for e in pending:
		var sc: Scene = cur.call(int(e["vk"]))
		if sc == null or undo_n < int(e["undo_n"]):   # undone (or gone): the reaction was not kept, nothing to learn
			continue
		var h: int = sc.cards.hash()
		if h != int(e["hash"]):
			e["hash"] = h
			e["changed_at"] = t
		var age := t - float(e["born"])
		var changed: bool = float(e["changed_at"]) >= 0.0
		if changed and (t - float(e["changed_at"]) >= SETTLE_S or age > EDIT_WINDOW_S):
			var m := measure(e["base"], e["written"], sc, body, float(e["t0"]), float(e["t1"]))
			if not m.is_empty():
				m["J"] = float(e["J"])
				sj.add_habit(SRC, KIND, m)
				made += 1
			continue
		if age > EDIT_WINDOW_S:
			continue   # kept as written
		keep.append(e)
	pending = keep
	return made
