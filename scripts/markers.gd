## MARKERS (round 41, GATES WW5, UPGRADES_300 #261 + the export half of UPGRADES_200 #106): named moments on the scene's
## timeline, the way an editor drops a cue: [{"t": seconds, "name": String, "kind": "hit"|"step"|"swoosh"|"note"}] sorted
## by t. The game that plays an export fires its own sound / spark / camera shake on them ("events" in the game JSON,
## t as a fraction of the length). They are written to the scene file only when there are any (old scenes save as before).
## All static: the Scene holds the array (Scene.markers), main.gd owns the undo and the commands.
class_name Markers

const KINDS := ["hit", "step", "swoosh", "note"]
const COLORS := {"hit": Color(0.95, 0.3, 0.25), "step": Color(0.35, 0.75, 0.4), "swoosh": Color(0.35, 0.65, 0.95), "note": Color(0.9, 0.8, 0.3)}


static func sorted(ms: Array) -> Array:
	var out := ms.duplicate(true)
	out.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	return out


## one marker, cleaned (a bad kind is a note, a missing name is "m<i+1>")
static func clean(d: Dictionary, i := 0) -> Dictionary:
	var k := String(d.get("kind", "note"))
	return {"t": maxf(0.0, float(d.get("t", 0.0))), "name": String(d.get("name", "m%d" % (i + 1))), "kind": k if k in KINDS else "note"}


## the file's list -> clean, sorted (anything not a dictionary with a t is dropped)
static func from_list(l) -> Array:
	var out := []
	if l is Array:
		for d in l:
			if d is Dictionary and d.has("t"):
				out.append(clean(d, out.size()))
	return sorted(out)


## the next free name "m<n>"
static func next_name(ms: Array) -> String:
	var n := ms.size() + 1
	var used := ms.map(func(x): return String(x["name"]))
	while ("m%d" % n) in used:
		n += 1
	return "m%d" % n


## adds one at t (the array stays sorted); -> the marker added
static func add(ms: Array, t: float, name := "", kind := "note") -> Dictionary:
	var mk := clean({"t": snappedf(t, 0.001), "name": name if name != "" else next_name(ms), "kind": kind})
	ms.append(mk)
	ms.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	return mk


## the index of the marker nearest to t within tol seconds, else -1
static func near(ms: Array, t: float, tol: float) -> int:
	var best := -1
	var bd := tol + 1e-9
	for i in ms.size():
		var d := absf(float(ms[i]["t"]) - t)
		if d <= bd:
			bd = d
			best = i
	return best


## the time of the first marker after t (by more than eps), else -1
static func next_t(ms: Array, t: float, eps := 1e-3) -> float:
	for x in ms:
		if float(x["t"]) > t + eps:
			return float(x["t"])
	return -1.0


static func prev_t(ms: Array, t: float, eps := 1e-3) -> float:
	for i in range(ms.size() - 1, -1, -1):
		if float(ms[i]["t"]) < t - eps:
			return float(ms[i]["t"])
	return -1.0


## RETIME: where a time t goes when the scene's timing changes from `old` to `new` (both Scene.times(): [start of move,
## arrival, end of hold] per card, same card count). Piecewise linear through those points, so a marker at a card's
## arrival stays at that card's arrival, and one inside a stretched move or hold is stretched with it; after the
## last point the end shifts.
static func remap_time(t: float, old: Array, new: Array) -> float:
	var xs := [0.0]
	var ys := [0.0]
	for i in old.size():
		for j in 3:
			var o := float(old[i][j])
			if o > xs[-1] + 1e-9:
				xs.append(o)
				ys.append(float(new[i][j]))
	if t <= 0.0 or xs.size() < 2:
		return t
	for k in range(1, xs.size()):
		if t <= xs[k] + 1e-9:
			var u: float = (t - float(xs[k - 1])) / (float(xs[k]) - float(xs[k - 1]))
			return ys[k - 1] + u * (ys[k] - ys[k - 1])
	return t + (ys[-1] - xs[-1])


## the list after a retime (a new array; the input is untouched)
static func remap(ms: Array, old: Array, new: Array) -> Array:
	if old.size() != new.size() or old.is_empty():
		return ms.duplicate(true)
	var out := ms.duplicate(true)
	for x in out:
		x["t"] = snappedf(remap_time(float(x["t"]), old, new), 0.001)
	return sorted(out)


## the game export's "events": t as a fraction of the length (4 decimals, like the table's keys)
static func events(ms: Array, length: float) -> Array:
	var out := []
	for x in ms:
		out.append({"t_frac": snappedf(clampf(float(x["t"]) / maxf(length, 1e-6), 0.0, 1.0), 0.0001), "name": x["name"], "kind": x["kind"]})
	return out
