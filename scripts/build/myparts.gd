## myparts.gd - MY PARTS: saved Parts (Easy Part's and Expert's, "Use in a scene"). One JSON file per part under user://parts/ (the Part
## record itself, Part.make's dictionary, as JSON), a picture beside it (<file>.png, a small render of the part's mesh, drawn once at save).
## The same name replaces the part (one file per name, never a duplicate). Tests never reach the real folder: while a test script runs
## (res://tests/...) the folder is user://myparts_test, and a test may set MyParts.dir itself.
class_name MyParts
extends RefCounted

const DIR := "user://parts"
const TEST_DIR := "user://myparts_test"

static var dir := ""            # "" = the default for the running script (DIR, or TEST_DIR under res://tests)


static func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)


## the folder in use
static func folder() -> String:
	if dir != "":
		return dir
	var ml := Engine.get_main_loop()
	var sc: Script = ml.get_script() if ml != null else null
	if sc != null and sc.resource_path.begins_with("res://tests/"):
		return TEST_DIR
	return DIR


## a part name as a file name (the same rule as a house's: letters, digits, space, dash, underscore; the rest "_")
static func file_stem(nm: String) -> String:
	var out := ""
	for ch in nm.strip_edges():
		var c := ch.unicode_at(0)
		var keep := (c < 128 and (ch.is_valid_identifier() or ch == " " or ch == "-" or ch.is_valid_int())) or (c >= 128 and ch.to_lower() != ch.to_upper())
		out += ch if keep else "_"
	return out if out != "" else "Part"


static func path_of(nm: String) -> String:
	return "%s/%s.json" % [folder(), file_stem(nm)]


static func thumb_of(nm: String) -> String:
	return "%s/%s.png" % [folder(), file_stem(nm)]


static func exists(nm: String) -> bool:
	return FileAccess.file_exists(_abs(path_of(nm)))


## the first "<base> N" (N from 1) not saved yet
static func free_name(base: String) -> String:
	var i := 1
	while exists("%s %d" % [base, i]):
		i += 1
	return "%s %d" % [base, i]


## the record in a file ({} when missing, not JSON, or without a solid record)
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(_abs(path)):
		return {}
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	var d = j.data
	if not (d is Dictionary) or not (d as Dictionary).has("features") or not ((d as Dictionary)["features"] is Array):
		return {}
	return d


static func load_part(nm: String) -> Dictionary:
	return read(path_of(nm))


## every saved part: [{"name", "path", "thumb" ("" when no picture yet), "record"}]. A bad file is skipped with one line
static func list() -> Array:
	var out: Array = []
	var d := folder()
	if not DirAccess.dir_exists_absolute(_abs(d)):
		return out
	var files := DirAccess.get_files_at(_abs(d))
	files.sort()
	for f in files:
		if not f.ends_with(".json"):
			continue
		var path := "%s/%s" % [d, f]
		var rec := read(path)
		if rec.is_empty():
			print("myparts: skipped %s (not a part file)" % f)
			continue
		var th := path.trim_suffix(".json") + ".png"
		out.append({"name": String(rec.get("name", f.trim_suffix(".json"))), "path": path, "record": rec,
			"thumb": th if FileAccess.file_exists(_abs(th)) else ""})
	return out


## save the record as the part called nm (the record's name becomes nm; the same name replaces). `img` is the picture (null keeps the old one)
static func save(rec: Dictionary, nm: String, img: Image = null) -> String:
	DirAccess.make_dir_recursive_absolute(_abs(folder()))
	var r := rec.duplicate(true)
	r["name"] = nm.strip_edges() if nm.strip_edges() != "" else "Part"
	var path := path_of(String(r["name"]))
	var kept := read(path)   # p163collection: saving the part again keeps its collection
	if not r.has("collection") and kept.has("collection"):
		r["collection"] = kept["collection"]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(r, "\t"))
	f.close()
	if img != null and not img.is_empty():
		img.save_png(_abs(thumb_of(String(r["name"]))))
	return path

## MY PARTS, import (ROADMAP 84): a part file someone shared (its .json record, its picture beside it) is copied into the store.
## The name it was saved under is kept; a name already saved is never replaced: the copy is saved as "<name> 1" (the first free).
## {"ok", "name" (the name it is saved under), "why" (the next step, when refused)}
static func import_file(src: String) -> Dictionary:
	var rec := read(src)
	if rec.is_empty():
		return {"ok": false, "name": "", "why": "it is not a part file. A part file is the .json that Use in a scene saves (its features); ask for that file, or make the part in Easy Part and press Use in a scene"}
	var base := String(rec.get("name", "")).strip_edges()
	if base == "":
		base = src.get_file().get_basename()
	var nm := free_name(base) if exists(base) else base
	rec["name"] = nm
	DirAccess.make_dir_recursive_absolute(_abs(folder()))
	var f := FileAccess.open(path_of(nm), FileAccess.WRITE)
	if f == null:
		return {"ok": false, "name": "", "why": "the My parts folder cannot be written. Check the disk has room, then drop the file again"}
	f.store_string(JSON.stringify(rec, "\t"))
	f.close()
	var pic := src.get_basename() + ".png"
	if FileAccess.file_exists(pic):
		DirAccess.copy_absolute(_abs(pic), _abs(thumb_of(nm)))
	return {"ok": true, "name": nm, "why": ""}

## COLLECTIONS (Friday plan 163, Kine's own: a saved part belongs to one collection, My workshop or My game props, so the library
## shows it there). The name is kept in the part's own record ("collection"); "" = none. false when the part is not saved.
static func set_collection(nm: String, coll: String) -> bool:
	var path := path_of(nm)
	var rec := read(path)
	if rec.is_empty():
		return false
	if coll == "":
		rec.erase("collection")
	else:
		rec["collection"] = coll
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(rec, "	"))
	f.close()
	return true


## the collection a saved part's record belongs to ("" = none)
static func collection_of(rec: Dictionary) -> String:
	return String(rec.get("collection", ""))
