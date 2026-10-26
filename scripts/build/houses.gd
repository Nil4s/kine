## houses.gd - MY HOUSES: saved houses. One JSON file per house under user://houses/ (the Building record, Building.to_file: its own
## "version"), a cached picture beside it (<file>.png, drawn once at save), and a trash folder (_trash/) that Delete moves a house to.
## Nothing here is ever hard-deleted. The folder is a parameter (Houses.dir), so a test writes only under user://houses_test/.
## A file that does not parse, or is not a building record, is skipped with one line (Houses.skipped holds the names).
class_name Houses
extends RefCounted

const DIR := "user://houses"
const TRASH := "_trash"

static var dir := DIR           # the folder in use (a test points it at its own)
static var skipped: Array = []  # the files the last list() could not read


static func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)


## a house name as a file name: letters (accented ones too: "Casa do João" and "Pão" / "Pêo" stay apart), digits, space, dash and
## underscore; the rest becomes "_"
static func file_stem(nm: String) -> String:
	var out := ""
	for ch in nm.strip_edges():
		var c := ch.unicode_at(0)
		var keep := (c < 128 and (ch.is_valid_identifier() or ch == " " or ch == "-" or ch.is_valid_int())) or (c >= 128 and ch.to_lower() != ch.to_upper())
		out += ch if keep else "_"
	return out if out != "" else "House"


## the first rule (every non-ASCII letter became "_"): houses saved under it are still found by their own name
static func _legacy_stem(nm: String) -> String:
	var out := ""
	for ch in nm.strip_edges():
		out += ch if (ch.unicode_at(0) < 128 and (ch.is_valid_identifier() or ch == " " or ch == "-" or ch.is_valid_int())) else "_"
	return out if out != "" else "House"


## the stem on disk: the file of this name, or an older file saved under the first rule when ITS record carries this name
static func _stem(nm: String) -> String:
	var st := file_stem(nm)
	var old := _legacy_stem(nm)
	if old != st and not FileAccess.file_exists(_abs("%s/%s.json" % [dir, st])) and FileAccess.file_exists(_abs("%s/%s.json" % [dir, old])):
		var j := JSON.new()
		if j.parse(FileAccess.get_file_as_string("%s/%s.json" % [dir, old])) == OK and j.data is Dictionary and String((j.data as Dictionary).get("name", "")) == nm.strip_edges():
			return old
	return st


static func path_of(nm: String) -> String:
	return "%s/%s.json" % [dir, _stem(nm)]


static func thumb_of(nm: String) -> String:
	return "%s/%s.png" % [dir, _stem(nm)]


static func exists(nm: String) -> bool:
	return FileAccess.file_exists(_abs(path_of(nm)))


## "House 1", "House 2", ...: the first one no saved house has
static func next_name() -> String:
	var n := 1
	while exists("House %d" % n):
		n += 1
	return "House %d" % n


## the record in a file, as Building reads it ({} when the file is missing, not JSON, or not a building)
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(_abs(path)):
		return {}
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK:   # (JSON.parse_string would log an engine error for a bad file)
		return {}
	var d = j.data
	if not (d is Dictionary) or not (d as Dictionary).has("rooms") or not (d["rooms"] is Array):
		return {}
	return Building.from_file(d)


static func load_house(nm: String) -> Dictionary:
	return read(path_of(nm))


## every saved house, by name: [{"name", "path", "thumb" (a path, "" when it has no picture yet), "record"}]. A bad file is
## skipped with one line and named in `skipped`
static func list() -> Array:
	skipped = []
	var out: Array = []
	if not DirAccess.dir_exists_absolute(_abs(dir)):   # no house saved yet: get_files_at on a missing folder logs an engine ERROR and costs 6-46 ms (library B9)
		return out
	var files := DirAccess.get_files_at(_abs(dir))
	files.sort()
	for f in files:
		if not f.ends_with(".json"):
			continue
		var path := "%s/%s" % [dir, f]
		var rec := read(path)
		if rec.is_empty():
			skipped.append(f)
			print("houses: skipped %s (not a house file)" % f)
			continue
		var th := path.trim_suffix(".json") + ".png"
		out.append({"name": String(rec.get("name", f.trim_suffix(".json"))), "path": path, "record": rec,
			"thumb": th if FileAccess.file_exists(_abs(th)) else ""})
	return out


## save the record as the house called nm (the record's name becomes nm). `img` is the picture, drawn once by the caller; null keeps
## the old one. Returns the path ("" when the folder cannot be written)
static func save(b: Dictionary, nm: String, img: Image = null) -> String:
	DirAccess.make_dir_recursive_absolute(_abs(dir))
	var rec: Dictionary = Building.to_file(b)
	rec["name"] = nm
	var path := path_of(nm)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(rec, "\t"))
	f.close()
	if img != null and not img.is_empty():
		img.save_png(_abs(thumb_of(nm)))
	return path


## the house under another name (its file and picture move; false when the new name is taken or the old one is not there)
static func rename(old: String, nw: String) -> bool:
	nw = nw.strip_edges()
	if nw == "" or not exists(old) or (exists(nw) and _stem(nw).to_lower() != _stem(old).to_lower()):   # (Windows names ignore case: "dojo" -> "Dojo" is the same file)
		return false
	var rec := load_house(old)
	if rec.is_empty():
		return false
	if file_stem(nw) != _stem(old):
		var to_json := "%s/%s.json" % [dir, file_stem(nw)]
		var to_png := "%s/%s.png" % [dir, file_stem(nw)]
		var had_png := FileAccess.file_exists(_abs(thumb_of(old)))
		var from_png := thumb_of(old)
		DirAccess.rename_absolute(_abs(path_of(old)), _abs(to_json))   # a move: the old file is never removed
		if had_png:
			DirAccess.rename_absolute(_abs(from_png), _abs(to_png))
	return save(rec, nw) != ""


## Delete: the file (and its picture) move to _trash/, with a number added when the trash already has that name. Returns the new path
static func trash(nm: String) -> String:
	if not exists(nm):
		return ""
	var tdir := "%s/%s" % [dir, TRASH]
	DirAccess.make_dir_recursive_absolute(_abs(tdir))
	var stem := file_stem(nm)
	var n := 0
	var dst := "%s/%s.json" % [tdir, stem]
	while FileAccess.file_exists(_abs(dst)):
		n += 1
		dst = "%s/%s_%d.json" % [tdir, stem, n]
	DirAccess.rename_absolute(_abs(path_of(nm)), _abs(dst))
	if FileAccess.file_exists(_abs(thumb_of(nm))):
		DirAccess.rename_absolute(_abs(thumb_of(nm)), _abs(dst.trim_suffix(".json") + ".png"))
	return dst


## the house as a node for its picture: the mesh BUILD draws, in one plain material
static func picture_node(b: Dictionary) -> Node3D:
	if b.is_empty() or bool(b.get("readonly", false)) or (b.get("rooms", []) as Array).is_empty():
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = Building.to_array_mesh(b)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.84, 0.8)
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	var root := Node3D.new()
	root.add_child(mi)
	return root
