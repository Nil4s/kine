## LEARN FROM MY EDITS (ROADMAP I26). Every one-click suggestion (next pose, timing coach, counter, fight rhythm) logs what it
## offered when it is ACCEPTED: {source, kind, card, params, accepted_at}. Then the journal watches:
##   undone within UNDO_WINDOW (30 s) on the undo stack         -> REJECTED
##   the same card's own parameter changed within EDIT_WINDOW (2 min)  -> EDITED, with the delta in that parameter (e.g. move time, s)
##   neither                                                    -> KEPT (when the 2 minutes are over)
## Per source/kind it keeps counts and the edit deltas in user://suggestion_journal.json (a test points `path` elsewhere).
## Use: rate() is the kept-rate with Laplace smoothing and a prior of 0.5 ((kept + 1) / (resolved + 2)); sort_offers() puts the
## kinds you keep first; learned() is the mean delta once LEARN_MIN = 3 edits agree in sign (and none disagree): the offer is then
## pre-applied and its button says so. Edited counts as kept (you used it and shaped it). The clock and the undo size are injected.
class_name SuggestionJournal
extends RefCounted

const UNDO_WINDOW := 30.0
const EDIT_WINDOW := 120.0
const LEARN_MIN := 3
const EPS := 0.0005    # a change smaller than this is not an edit
const PATH := "user://suggestion_journal.json"

var path := PATH
var stats: Dictionary = {}     # "source|kind" -> {source, kind, offers, kept, rejected, edited, n_pos, n_neg, sum_pos, sum_neg}
var habits: Array = []         # I46: [{kind, J, amp, delay, rec}] one row per edit of a written reaction (scripts/hit_habits.gd)
var pending: Array = []        # [{source, kind, card, params, accepted_at, undo_n, reader}] (not saved: a restart forgets what it was watching)
var now := Callable()          # () -> seconds; default: the engine clock


func _init(p := PATH) -> void:
	path = p
	load_file()


func _t() -> float:
	return float(now.call()) if now.is_valid() else float(Time.get_ticks_msec()) / 1000.0


func _key(source: String, kind: String) -> String:
	return source + "|" + kind


func _row(source: String, kind: String) -> Dictionary:
	var k := _key(source, kind)
	if not stats.has(k):
		stats[k] = {"source": source, "kind": kind, "offers": 0, "kept": 0, "rejected": 0, "edited": 0, "n_pos": 0, "n_neg": 0, "sum_pos": 0.0, "sum_neg": 0.0}
	return stats[k]


## an accepted suggestion. params: {"field": "move", "base": the suggestion's own value, "applied": what was written}. reader: Callable
## () -> Variant giving that field now (null = cannot be watched for edits, only for undo). Returns the pending index.
func log(source: String, kind: String, card: int, params: Dictionary, undo_n: int, reader := Callable()) -> void:
	_row(source, kind)["offers"] += 1
	pending.append({"source": source, "kind": kind, "card": card, "params": params, "accepted_at": _t(), "undo_n": undo_n, "reader": reader})
	save()


## call every frame (cheap) or whenever the user acts: undo_n is main.undo.size() now
func observe(undo_n: int) -> void:
	var t := _t()
	var keep := []
	for e in pending:
		var age := t - float(e["accepted_at"])
		var r := _row(e["source"], e["kind"])
		if age <= UNDO_WINDOW and undo_n < int(e["undo_n"]):
			r["rejected"] += 1
			_done()
			continue
		var rd: Callable = e["reader"]
		if age <= EDIT_WINDOW and rd.is_valid():
			var v: Variant = rd.call()
			if v != null and absf(float(v) - float(e["params"].get("applied", v))) > EPS:
				var d := float(v) - float(e["params"].get("base", e["params"].get("applied", v)))
				r["edited"] += 1
				if d >= 0.0:
					r["n_pos"] += 1
					r["sum_pos"] += d
				else:
					r["n_neg"] += 1
					r["sum_neg"] += d
				_done()
				continue
		if age > EDIT_WINDOW:
			r["kept"] += 1
			_done()
			continue
		keep.append(e)
	if keep.size() != pending.size():
		pending = keep
		save()


func _done() -> void:
	pass   # (observe saves once at the end)


func resolved(source: String, kind: String) -> int:
	var r := _row(source, kind)
	return int(r["kept"]) + int(r["rejected"]) + int(r["edited"])


## kept-rate, Laplace-smoothed, prior 0.5 (nothing seen = 0.5). Edited counts as kept.
func rate(source: String, kind: String) -> float:
	var r := _row(source, kind)
	return (float(int(r["kept"]) + int(r["edited"])) + 1.0) / (float(resolved(source, kind)) + 2.0)


## stable sort, best kept-rate first. key_of: Callable(offer) -> kind String
func sort_offers(source: String, offers: Array, key_of: Callable) -> Array:
	var tag := []
	for i in offers.size():
		tag.append([i, rate(source, String(key_of.call(offers[i]))), offers[i]])
	tag.sort_custom(func(a, b): return float(a[1]) > float(b[1]) + 1e-9 or (absf(float(a[1]) - float(b[1])) <= 1e-9 and int(a[0]) < int(b[0])))
	return tag.map(func(x): return x[2])


## the mean edit delta once >= LEARN_MIN edits agree in sign and none disagree; NAN otherwise
func learned(source: String, kind: String) -> float:
	var r := _row(source, kind)
	if int(r["n_neg"]) == 0 and int(r["n_pos"]) >= LEARN_MIN:
		return float(r["sum_pos"]) / float(r["n_pos"])
	if int(r["n_pos"]) == 0 and int(r["n_neg"]) >= LEARN_MIN:
		return float(r["sum_neg"]) / float(r["n_neg"])
	return NAN


## "you usually shorten this by 0.05 s" (move times); other units pass their own noun
static func phrase(delta: float, unit := "s", more := "lengthen", less := "shorten") -> String:
	return "you usually %s this by %.2f %s" % [less if delta < 0.0 else more, absf(delta), unit]


## the strongest lessons first: [{source, kind, text, n}]
func lessons(limit := 8) -> Array:
	var out := []
	for k in stats:
		var r: Dictionary = stats[k]
		var n := resolved(r["source"], r["kind"])
		if n == 0:
			continue
		var d := learned(r["source"], r["kind"])
		var rt := rate(r["source"], r["kind"])
		var txt := "%s / %s: kept %d of %d (%d%%)" % [r["source"], r["kind"], int(r["kept"]) + int(r["edited"]), n, roundi(100.0 * rt)]
		if int(r["rejected"]) > 0:
			txt += ", undone %d" % int(r["rejected"])
		if not is_nan(d):
			txt += "; " + phrase(d) + " (%d edits)" % maxi(int(r["n_pos"]), int(r["n_neg"]))
		out.append({"source": r["source"], "kind": r["kind"], "text": txt, "n": n, "w": absf(rt - 0.5) * n + (3.0 if not is_nan(d) else 0.0)})
	out.sort_custom(func(a, b): return float(a["w"]) > float(b["w"]))
	return out.slice(0, limit)


## I46: a lesson from an edit of something Kine wrote (rows are plain numbers); counted as an edited offer of source/kind
func add_habit(source: String, kind: String, row: Dictionary) -> void:
	var r := _row(source, kind)
	r["offers"] += 1
	r["edited"] += 1
	var h := row.duplicate()
	h["source"] = source
	h["kind"] = kind
	habits.append(h)
	save()


func habit_rows(source: String, kind: String) -> Array:
	return habits.filter(func(h): return h.get("source") == source and h.get("kind") == kind)


func reset() -> void:
	stats = {}
	habits = []
	pending = []
	save()


func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"stats": stats}, "\t"))


func load_file() -> void:
	if not FileAccess.file_exists(path):
		return
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if j is Dictionary and j.get("stats") is Dictionary:
		stats = j["stats"]
		if j.get("habits") is Array:
			habits = j["habits"]
