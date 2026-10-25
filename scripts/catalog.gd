class_name Catalog
extends RefCounted
## THE CATALOG (data/catalog.json): one entry per move or pose Kine ships, read by Easy's "Then ..." buttons (easy_home.gd)
## and by tools/catalog_check.gd. A JSON file, not a database: ~30 entries now, ~1000 later from a ComfyUI batch.
## An entry: {id, words (the name a person reads), kind: move|pose, category (Moves, Fighting, Everyday, Sports, Poses),
## tags, seconds, source (templates/<x>.json, poses/<x>.json or a scene), made_by ("hand-made" | "AI video (Wan 2.1,
## Apache-2.0)" | "public-domain film: <title>"), goes_after: [ids that flow well after it]}.
## Plain functions, no state: each call reads what it is given (entries) or the file (load()).

const PATH := "res://data/catalog.json"
const KEYS := ["id", "words", "kind", "category", "tags", "seconds", "source", "made_by", "goes_after"]
const KINDS := ["move", "pose"]
const CATEGORIES := ["Moves", "Fighting", "Everyday", "Sports", "Poses"]


## the entries in the file (a list of dictionaries); [] when the file is missing or not a list. path: res:// or an absolute path
static func load(path := PATH) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var out: Array = v if v is Array else []
	return out


## the entry with this id, {} when there is none
static func by_id(id: String, entries: Array = []) -> Dictionary:
	var all: Array = entries if not entries.is_empty() else Catalog.load()
	for e in all:
		if String(e.get("id", "")) == id:
			return e
	return {}


## the entries in one category, in file order
static func by_category(category: String, entries: Array = []) -> Array:
	var all: Array = entries if not entries.is_empty() else Catalog.load()
	var out := []
	for e in all:
		if String(e.get("category", "")) == category:
			out.append(e)
	return out


## the moves to offer after move id: its goes_after first (in that order), then the same category's other moves in file
## order. Only moves (a pose is not a clip to add) whose source file exists; the id itself only if its goes_after lists it;
## at most n. [] for an unknown id.
static func next_after(id: String, n := 3, entries: Array = []) -> Array:
	var all: Array = entries if not entries.is_empty() else Catalog.load()
	var src := by_id(id, all)
	if src.is_empty() or n <= 0:
		return []
	var out := []
	var ids := []
	for g in src.get("goes_after", []):
		var e := by_id(String(g), all)
		if _offerable(e) and not ids.has(String(g)) and (String(g) != id or (src["goes_after"] as Array).has(id)):
			out.append(e)
			ids.append(String(g))
	for e in by_category(String(src.get("category", "")), all):
		if out.size() >= n:
			break
		if _offerable(e) and not ids.has(String(e["id"])) and String(e["id"]) != id:
			out.append(e)
			ids.append(String(e["id"]))
	return out.slice(0, n)


static func _offerable(e: Dictionary) -> bool:
	return not e.is_empty() and String(e.get("kind", "")) == "move" and FileAccess.file_exists("res://" + String(e.get("source", "")))


## every problem with a catalog (an empty list = good): a missing key, an unknown kind, category or made_by, a source file
## that is not there (under res://), a goes_after id that is not an entry, a duplicate id
static func problems(entries: Array) -> Array:
	var out := []
	var seen := {}
	var ids := {}
	for e in entries:
		if e is Dictionary:
			ids[String(e.get("id", ""))] = true
	for e in entries:
		if not (e is Dictionary):
			out.append("an entry is not an object")
			continue
		var id := String(e.get("id", "?"))
		for k in KEYS:
			if not e.has(k):
				out.append("%s: no '%s'" % [id, k])
		if seen.has(id):
			out.append("%s: duplicate id" % id)
		seen[id] = true
		if String(e.get("kind", "")) not in KINDS:
			out.append("%s: kind '%s' is not move or pose" % [id, e.get("kind", "")])
		if String(e.get("category", "")) not in CATEGORIES:
			out.append("%s: category '%s' is not one of %s" % [id, e.get("category", ""), ", ".join(CATEGORIES)])
		var mb := String(e.get("made_by", ""))
		if not (mb == "hand-made" or mb.begins_with("AI video (") or mb.begins_with("public-domain film: ")):
			out.append("%s: made_by '%s' is not hand-made, AI video (...) or public-domain film: ..." % [id, mb])
		var src := String(e.get("source", ""))
		if src == "" or not FileAccess.file_exists("res://" + src):
			out.append("%s: source '%s' is not a file" % [id, src])
		for g in e.get("goes_after", []):
			if not ids.has(String(g)):
				out.append("%s: goes_after '%s' is not an entry" % [id, g])
	return out
