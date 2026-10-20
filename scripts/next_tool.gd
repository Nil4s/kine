class_name NextTool
extends RefCounted
## P17: THE NEXT SUGGESTED TOOL. A first-order Markov table over the user's own commands: P(next | last, page), learned from
## every command run (palette, hotkey, ribbon, chip). Counts decay with a half-life of HALF_LIFE commands, so an old habit
## fades and a new one takes over; they are kept in one small JSON in user:// (never in a scene). Cold start: SEED, the
## everyday sequence (key a pose -> clip the next card -> play -> check). Views, undo/redo and the page switches never count and are never suggested.
const HALF_LIFE := 200.0
const MAX_KEYS := 400
const SEED := ["CLIP this pose (add a card)", "CLIP this pose (add a card)", "Play / pause", "Check the motion"]

var path := "user://next_tool.json"
var tick := 0                # commands recorded so far (the decay clock)
var last := ""               # the last counted command
var counts := {}             # "last|page" -> {next: [weight at tick t, t]}


## views, undo/redo and page switches say nothing about a habit of working
static func skipped(n: String) -> bool:
	return n == "" or n == "Undo" or n == "Redo" or n.ends_with(" view") or n.begins_with("View") or n.begins_with("Page:") \
		or n.begins_with("Help") or n.begins_with("Mode:") or n == "Every key on one screen"


static func _eff(e: Array, now: int) -> float:
	return float(e[0]) * pow(0.5, float(now - int(e[1])) / HALF_LIFE)


## a command was run on this page
func record(name: String, page: String) -> void:
	if skipped(name):
		return
	tick += 1
	if last != "":
		var k := last + "|" + page
		var row: Dictionary = counts.get(k, {})
		row[name] = [(_eff(row[name], tick) if row.has(name) else 0.0) + 1.0, tick]
		counts[k] = row
	last = name
	_prune()
	save()


## the top n commands to run after the last one, on this page; ok(name) -> bool says whether a command can run now
func suggest(page: String, ok: Callable, n := 3, skip := []) -> Array:
	var sc := {}
	for nm in counts.get(last + "|" + page, {}):
		sc[nm] = _eff(counts[last + "|" + page][nm], tick)
	var out := []
	var names: Array = sc.keys()
	names.sort_custom(func(a, b): return sc[a] > sc[b] or (sc[a] == sc[b] and a < b))
	for nm in names:
		if out.size() < n and sc[nm] >= 0.05 and _fit(nm, ok, skip, out):
			out.append(nm)
	if out.size() < n:   # cold start (or too few habits): the default sequence, after the step the last command stood on
		var at := SEED.rfind(last)
		for i in SEED.size():
			var nm: String = SEED[(at + 1 + i) % SEED.size()] if at >= 0 else SEED[i]
			if _fit(nm, ok, skip, out) and out.size() < n:
				out.append(nm)
	return out


func _fit(nm: String, ok: Callable, skip: Array, out: Array) -> bool:
	return not skipped(nm) and not out.has(nm) and not skip.has(nm) and (not ok.is_valid() or ok.call(nm))


func _prune() -> void:
	if counts.size() <= MAX_KEYS and tick % 50 != 0:
		return
	for k in counts.keys():
		for nm in counts[k].keys():
			if _eff(counts[k][nm], tick) < 0.02:
				counts[k].erase(nm)
		if counts[k].is_empty():
			counts.erase(k)


func forget() -> void:
	counts = {}
	last = ""
	tick = 0
	save()


func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"tick": tick, "last": last, "counts": counts}))


func load_file() -> void:
	counts = {}
	tick = 0
	last = ""
	if not FileAccess.file_exists(path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d is Dictionary and d.get("counts") is Dictionary:
		tick = int(d.get("tick", 0))
		last = String(d.get("last", ""))
		counts = d["counts"]
