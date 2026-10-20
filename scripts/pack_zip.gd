## pack_zip.gd - N15 PACK PROJECT: the open scene and every file it depends on in ONE zip (user://packs/<scene>.kinezip), and back.
## Pack: the scene's dictionary is walked for strings that name a file (a sound, a model, a picture, a video, a pose pack...: by
## extension, and only strings with a folder part, so "my crate" or a card name is never mistaken); each that exists is copied into the
## zip under files/NN/<name>, the scene's string is rewritten to that pack-relative name, and manifest.json records relative paths,
## sha256 and size of every entry, the Kine version and the MISSING list (named in the result, never silent). Models a prop kind of
## the library uses (Props.EXTRA) are carried too, as "packed_props".
## Unpack: into a folder under user:// ONLY. Every entry name is checked first (no "..", no leading "/", no drive, no backslash: a
## zip-slip entry refuses the whole zip before a byte is written), every hash is checked against the manifest, then the files are
## written, the scene's pack-relative names point at the new folder, and the scene file is written there. Nothing here touches scenes/.
class_name PackZip
extends RefCounted

const Importer := preload("res://scripts/importer.gd")
const DIR := "user://packs"
const EXT := ["wav", "ogg", "mp3", "obj", "mtl", "glb", "gltf", "png", "jpg", "jpeg", "webp", "bmp", "mp4", "mov", "avi", "webm", "mkv", "json"]
const SIDECAR := ["mtl"]


static func safe(n: String) -> String:
	var o := ""
	for c in n:
		o += c if (c.is_valid_identifier() or c in "-.") or (c >= "0" and c <= "9") else "_"
	return o if o != "" else "scene"


static func version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "0.1.0"))


static func _looks_file(s: String) -> bool:
	if s.length() > 500 or s.length() < 5 or s.contains("\n"):
		return false
	if not (s.contains("/") or s.contains("\\")):
		return false
	return EXT.has(s.get_extension().to_lower())


static func _resolve(s: String, base: String) -> String:
	if FileAccess.file_exists(s):
		return s
	if base != "" and not s.is_absolute_path() and FileAccess.file_exists(base.path_join(s)):
		return base.path_join(s)
	return ""


static func _walk(v: Variant, fn: Callable) -> Variant:
	if v is String:
		return fn.call(v)
	if v is Array:
		var a := []
		for x in v:
			a.append(_walk(x, fn))
		return a
	if v is Dictionary:
		var o := {}
		for k in v:
			o[k] = _walk(v[k], fn)
		return o
	return v


static func _sha(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()


## Pack scene dictionary `d` named `nm`. `out` is the zip to write (default user://packs/<nm>.kinezip); `base` resolves relative names.
## Returns {"ok", "path", "entries" (files incl. the scene, not the manifest), "files": [rel], "missing": [original strings], "why"}
static func pack(d: Dictionary, nm: String, out := "", base := "") -> Dictionary:
	var scene: Dictionary = d.duplicate(true)
	var pp := {}
	for p in scene.get("props", []):
		if p is Dictionary:
			var kind := String(p.get("kind", ""))
			if Props.EXTRA.has(kind):
				pp[kind] = String(Props.EXTRA[kind].get("glb", ""))
	if not pp.is_empty():
		scene["packed_props"] = pp
	var src_of := {}    # original string -> rel
	var order := []     # [[abs source, rel]]
	var missing := []
	var take := func(s: String) -> String:
		if not _looks_file(s):
			return s
		if src_of.has(s):
			return src_of[s]
		var abs := _resolve(s, base)
		if abs == "":
			if not missing.has(s):
				missing.append(s)
			return s
		var n := src_of.size() + 1   # (a lambda's captured ints are copies: count from the dictionary)
		var rel := "files/%02d/%s" % [n, s.get_file()]
		src_of[s] = rel
		order.append([abs, rel])
		var stem := abs.get_basename()
		for sc in SIDECAR:
			if abs.get_extension().to_lower() == "obj" and FileAccess.file_exists(stem + "." + sc):
				order.append([stem + "." + sc, "files/%02d/%s" % [n, (stem + "." + sc).get_file()]])
		return rel
	var packed: Dictionary = _walk(scene, take)
	var fname := safe(nm)
	var path := out if out != "" else "%s/%s.kinezip" % [DIR, fname]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var z := ZIPPacker.new()
	if z.open(path) != OK:
		return {"ok": false, "path": path, "entries": 0, "files": [], "missing": missing, "why": "could not write %s: check the folder is writable, then try Pack again" % path}
	var files := []
	var man_files := []
	var sb := JSON.stringify(packed, "\t").to_utf8_buffer()
	var scene_rel := "scene/%s.json" % fname
	z.start_file(scene_rel)
	z.write_file(sb)
	z.close_file()
	man_files.append({"path": scene_rel, "sha256": _sha(sb), "size": sb.size()})
	files.append(scene_rel)
	for e in order:
		var b := FileAccess.get_file_as_bytes(e[0])
		z.start_file(e[1])
		z.write_file(b)
		z.close_file()
		man_files.append({"path": e[1], "sha256": _sha(b), "size": b.size(), "from": e[0]})
		files.append(e[1])
	var man := {"kine_pack": 1, "kine_version": version(), "scene": nm, "scene_file": scene_rel, "files": man_files, "missing": missing}
	z.start_file("manifest.json")
	z.write_file(JSON.stringify(man, "\t").to_utf8_buffer())
	z.close_file()
	z.close()
	return {"ok": true, "path": path, "entries": files.size(), "files": files, "missing": missing, "why": ""}


## a zip entry name that could leave the folder it is unpacked into
static func unsafe_name(n: String) -> bool:
	if n == "" or n.begins_with("/") or n.contains("\\") or n.contains(":"):
		return true
	for part in n.split("/"):
		if part == "..":
			return true
	return false


## Unpack `zip` into `dest` (must be under user://). Returns {"ok", "scene" (path of the rewritten scene file), "files": n,
## "missing": [..], "props": [kinds], "why"}. Refuses the whole zip, writing nothing, on a bad name or a hash that differs.
static func unpack(zip: String, dest: String) -> Dictionary:
	var bad := func(why: String) -> Dictionary:
		return {"ok": false, "scene": "", "files": 0, "missing": [], "props": [], "why": why}
	if not dest.begins_with("user://") or dest.contains(".."):
		return bad.call("Unpack only into a folder under user:// (the app's own storage), never the project: pick a folder there")
	var r := ZIPReader.new()
	if r.open(zip) != OK:
		return bad.call("could not open %s as a zip: pick a .kinezip made by Pack, or pack the scene again" % zip.get_file())
	var names := r.get_files()
	for n in names:
		if unsafe_name(n):
			r.close()
			return bad.call("refused: the zip holds an entry named \"%s\" that would write outside the unpack folder. Nothing was written; ask for the pack again" % n)
	if not names.has("manifest.json"):
		r.close()
		return bad.call("this zip has no manifest.json, so it is not a Kine pack: pack the scene again")
	var man: Variant = JSON.parse_string(r.read_file("manifest.json").get_string_from_utf8())
	if not (man is Dictionary) or not man.has("files"):
		r.close()
		return bad.call("the manifest.json inside is damaged: pack the scene again")
	var data := {}
	for f in man["files"]:
		var rel := String(f["path"])
		if unsafe_name(rel) or not names.has(rel):
			r.close()
			return bad.call("the manifest names \"%s\", which is not safely inside the zip. Nothing was written; pack the scene again" % rel)
		var b := r.read_file(rel)
		if _sha(b) != String(f["sha256"]):
			r.close()
			return bad.call("\"%s\" does not match its recorded sha256: the zip is damaged. Nothing was written; copy or pack it again" % rel)
		data[rel] = b
	r.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest))
	var rels := {}
	for rel in data:
		if rel == String(man.get("scene_file", "")):
			continue
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest.path_join(rel).get_base_dir()))
		var fw := FileAccess.open(dest.path_join(rel), FileAccess.WRITE)
		if fw == null:
			return bad.call("could not write %s: check the folder, then try again" % dest.path_join(rel))
		fw.store_buffer(data[rel])
		fw.close()
		rels[rel] = dest.path_join(rel)
	var sc: Variant = JSON.parse_string((data[String(man["scene_file"])] as PackedByteArray).get_string_from_utf8())
	if not (sc is Dictionary):
		return bad.call("the scene inside is damaged: pack the scene again")
	var fixed: Dictionary = _walk(sc, func(s: String) -> String: return rels.get(s, s))
	var sp := dest.path_join(String(man["scene_file"]))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(sp.get_base_dir()))
	var fs := FileAccess.open(sp, FileAccess.WRITE)
	fs.store_string(JSON.stringify(fixed, "\t"))
	fs.close()
	return {"ok": true, "scene": sp, "files": data.size(), "missing": man.get("missing", []), "props": (fixed.get("packed_props", {}) as Dictionary).keys(), "why": ""}


## after Unpack: register the models the pack carried so the scene's set finds them (Props.EXTRA), before the scene is loaded
static func register_props(scene_file: String) -> int:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(scene_file))
	var n := 0
	if d is Dictionary:
		for k in (d.get("packed_props", {}) as Dictionary):
			if Props.has_kind(k):
				continue
			var r: Dictionary = Importer.inspect(d["packed_props"][k])
			if r.get("ok", false):
				Props.register(k, r["aabb"], d["packed_props"][k], r["scale_factor"])
				n += 1
	return n


## a folder under user://unpacked/ that does not exist yet
static func fresh_dest(root: String, nm: String) -> String:
	var base := root.path_join(safe(nm))
	var p := base
	var i := 2
	while DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(p)):
		p = "%s_%d" % [base, i]
		i += 1
	return p
