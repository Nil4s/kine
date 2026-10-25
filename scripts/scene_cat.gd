class_name SceneCat
extends RefCounted
## EASY'S "My scenes" CATALOG (Nick: "a better way to check the available animations, cuz scrolling is crazy, plus filter them
## by quality, some are cool but we got weird ones too"). Two things, both for a scene FILE, never for an open scene:
##   category(path, scene): the chip a scene sits under. Drafts = a path in scenes/_wip. A scene the catalog (data/catalog.json)
##     lists takes its catalog category through CAT_MAP (Moves and Everyday fall through to the names). Otherwise the words of the
##     file name and of the cards' names decide, in CHIPS order; no word = "Dance & other".
##   grade(path): the scene's quality, from Kine's own Check (Rulebook.check on a Scene + Body loaded from the file, the same
##     rules main's _check runs): "Weird" with any FAIL finding, "Good" with no FAIL and <= 2 WARN, else "OK".
## A Check costs seconds on a long clip, so the panel asks for grades lazily, one scene per frame (scripts/easy_scenes.gd), and
## CACHE (user://scene_quality.json) keeps each file's category and grade under its path + modified time + size: a second open
## of the panel runs no Check at all. Plain statics; the Body is loaded once per process.

const DRAFTS := "Drafts"
const CHIPS := ["Walk & run", "Fight", "Weapons", "Jump & dodge", "Dance & other"]   # the order the words are tried in
const WORDS := {
	"Walk & run": ["walk", "run", "jog", "step", "turn"],
	"Fight": ["punch", "kick", "jab", "hook", "cross", "block", "guard"],
	"Weapons": ["sword", "axe", "bat", "swing", "thrust", "weapon"],
	"Jump & dodge": ["jump", "dodge", "roll", "fall", "duck"],
}
## the catalog's own categories that name a chip (Moves, Everyday: the names decide)
const CAT_MAP := {"Fighting": "Fight", "Sports": "Jump & dodge", "Poses": "Dance & other"}
static var cache_path := "user://scene_quality.json"   # a test points it at its own folder
const CACHE_V := 1   # bump when the rules or the category words change: an old cache is then ignored

static var checks_run := 0   # every Check this process ran on a scene file (the panel's test counts them)
static var _body: Body = null
static var _listed_cats := {}   # "res://<source>" -> chip, from data/catalog.json (read once)
static var _listed_read := false


## the chip a scene file sits under. scene: the parsed scene dictionary (the cards' names are read from it); {} = the name alone
static func category(path: String, scene: Dictionary = {}) -> String:
	if is_draft(path):
		return DRAFTS
	var listed := _listed(path)
	if listed != "":
		return listed
	var text := path.get_file().get_basename()
	var names: Array = [scene.get("from", "")]
	for c in scene.get("cards", []):
		if c is Dictionary:
			names.append(c.get("name", ""))
	for n in names:
		text += " " + String(n)
	var toks := _tokens(text)
	for chip in CHIPS:
		for w in WORDS.get(chip, []):
			for t in toks:
				if t.begins_with(w):
					return chip
	return "Dance & other"


static func is_draft(path: String) -> bool:
	return path.contains("/_wip/")


## the quality grade from its findings: "Weird" with any FAIL, "Good" with <= 2 WARN, else "OK"
static func grade_of(fails: int, warns: int) -> String:
	if fails > 0:
		return "Weird"
	return "Good" if warns <= 2 else "OK"


## runs Kine's Check on the scene file: [fails, warns] (the findings are not kept). Counts the Check in checks_run.
static func grade(path: String) -> Array:
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (v is Dictionary) or not (v as Dictionary).has("cards"):
		checks_run += 1
		return [0, 0]
	if _body == null:
		_body = Body.new()
		_body.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		_body.fk()
	var S := Scene.new()
	S.from_dict(v)
	checks_run += 1
	var fs: Array = Rulebook.check(S, _body)
	var fails := 0
	var warns := 0
	for f in fs:
		if String(f["sev"]) == "FAIL":
			fails += 1
		else:
			warns += 1
	return [fails, warns]


## the cache: path -> {"v", "mtime", "size", "cat", "fails", "warns"} (fails/warns absent until graded)
static func load_cache() -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(cache_path):
		return out
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(cache_path))
	if v is Dictionary:
		out = v
	return out


static func save_cache(c: Dictionary) -> void:
	var f := FileAccess.open(cache_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(c))


## the file's modified time and size: the cache key
static func stamp(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	var size := f.get_length() if f != null else -1
	return [FileAccess.get_modified_time(path), size]


## true when the cache entry is for the file as it is now
static func fresh(entry: Dictionary, path: String) -> bool:
	var st := stamp(path)
	return int(entry.get("v", 0)) == CACHE_V and int(entry.get("mtime", -1)) == int(st[0]) and int(entry.get("size", -2)) == int(st[1])


static func _tokens(text: String) -> Array:
	var s := text.to_lower()
	for ch in ["_", "-", ".", "(", ")", "/", ",", ":", "'", "\""]:
		s = s.replace(ch, " ")
	return Array(s.split(" ", false))


static func _listed(path: String) -> String:
	if not _listed_read:
		_listed_read = true
		for e in Catalog.load():
			var chip := String(CAT_MAP.get(String(e.get("category", "")), ""))
			if chip != "":
				_listed_cats["res://" + String(e.get("source", ""))] = chip
	return String(_listed_cats.get(path, ""))
