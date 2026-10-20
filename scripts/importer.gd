## THE IMPORTER (GATES: "a .glb read with Godot's GLTFDocument -> its kind, its bounds in metres, a scale verdict in
## words, a broken file said in words, nothing changed; a library folder read at start; an accepted file COPIED in, a
## licence note beside it"). Pure helpers, no scene tree needed. The user's original file is only ever READ.
##   Importer.inspect(path)            -> what the file is (never changes anything)
##   Importer.library_list(root)       -> what the library folders hold
##   Importer.accept(path, kind, ...)  -> copy it into the library with a licence note
## The library root is a parameter (default user://library) so a test can point it somewhere else.
extends RefCounted

const DEFAULT_ROOT := "user://library"
## the three library folders, by the kind the user picks
const FOLDERS := {"prop": "props", "props": "props", "weapon": "weapons", "weapons": "weapons", "animation": "animations", "animations": "animations"}
## a prop or a weapon, longest side: 2 cm .. 10 m is believable; outside it the file was probably made in other units
const MIN_PLAUSIBLE := 0.02
const MAX_PLAUSIBLE := 10.0


## a res:// / user:// path made absolute (an absolute path stays as it is)
static func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p) if p.begins_with("res://") or p.begins_with("user://") else p


## a failed inspect: ok false and one plain sentence saying what is wrong and what to do
static func _bad(why: String) -> Dictionary:
	return {"ok": false, "kind": "", "bones": 0, "aabb": AABB(), "size": Vector3.ZERO, "scale_note": "", "scale_factor": 1.0, "why": why}


## every mesh under n, boxed in n's parent space (the generated scene is not in the SceneTree: transforms are composed by hand)
static func _boxes(n: Node, parent_xf: Transform3D, out: Array) -> void:
	var xf := parent_xf
	if n is Node3D:
		xf = parent_xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(xf * (n as MeshInstance3D).mesh.get_aabb())
	for c in n.get_children():
		_boxes(c, xf, out)


## the scale verdict for a longest side L (metres): [note, factor]. "" and 1.0 when plausible.
## Files from tools set to centimetres or millimetres arrive 100x / 1000x too big; the other way round, too small.
static func scale_verdict(longest: float) -> Array:
	if longest >= MIN_PLAUSIBLE and longest <= MAX_PLAUSIBLE:
		return ["", 1.0]
	if longest > MAX_PLAUSIBLE:
		if longest * 0.01 >= MIN_PLAUSIBLE and longest * 0.01 <= MAX_PLAUSIBLE:
			return ["About 100x too big (%s long): it was probably made in centimetres. It will be scaled by 0.01 to about %s." % [_len(longest), _len(longest * 0.01)], 0.01]
		if longest * 0.001 >= MIN_PLAUSIBLE and longest * 0.001 <= MAX_PLAUSIBLE:
			return ["About 1000x too big (%s long): it was probably made in millimetres. It will be scaled by 0.001 to about %s." % [_len(longest), _len(longest * 0.001)], 0.001]
		return ["Far too big (%s long) and the units cannot be guessed. Check the size in the program that made it." % _len(longest), 1.0]
	# too small
	if longest * 1000.0 >= MIN_PLAUSIBLE and longest * 1000.0 <= MAX_PLAUSIBLE and longest < 0.01:
		return ["About 1000x too small (%s long): the units were probably mixed up when it was exported. It will be scaled by 1000 to about %s." % [_len(longest), _len(longest * 1000.0)], 1000.0]
	if longest * 100.0 >= MIN_PLAUSIBLE and longest * 100.0 <= MAX_PLAUSIBLE:
		return ["About 100x too small (%s long): the units were probably mixed up when it was exported. It will be scaled by 100 to about %s." % [_len(longest), _len(longest * 100.0)], 100.0]
	return ["Far too small (%s long) and the units cannot be guessed. Check the size in the program that made it." % _len(longest), 1.0]


## a length in words a person reads: 40 m, 12 cm, 0.4 mm
static func _len(m: float) -> String:
	if m >= 1.0:
		return "%s m" % _round3(m)
	if m >= 0.01:
		return "%s cm" % _round3(m * 100.0)
	return "%s mm" % _round3(m * 1000.0)


## three significant figures, no trailing noise (GDScript's % has no %g)
static func _round3(x: float) -> String:
	var step := pow(10.0, floor(log(maxf(absf(x), 1e-12)) / log(10.0)) - 2.0)
	return String.num(snappedf(x, step), 3).trim_suffix(".0")


## Read a .glb / .gltf with Godot's own importer and say what it is. Changes nothing.
## ok true: {"ok", "kind": "rigged" (has a skeleton) | "object", "bones", "aabb" (metres), "size", "scale_note" ("" when the
## size is believable), "scale_factor" (what to multiply by; 1.0 when fine)}.  ok false: {"ok": false, "why": a sentence}.
static func inspect(path: String) -> Dictionary:
	var abs := _abs(path)
	if not FileAccess.file_exists(abs):
		return _bad("That file could not be found. Check that it was not moved or deleted, then try again. Nothing was changed.")
	var ext := path.get_extension().to_lower()
	if ext == "obj":   # Wavefront OBJ (scripts/obj_io.gd): the same answer, in metres
		if not FileAccess.file_exists(abs):
			return _bad("That file could not be found. Check that it was not moved or deleted, then try again. Nothing was changed.")
		var ob := ObjIO.bounds(path)
		if ob.size == Vector3.ZERO:
			return _bad("That .obj holds no faces, or all its points sit in one place, so there is nothing to show. Export it again from your 3D program with the mesh selected. Nothing was changed.")
		var ov := scale_verdict(maxf(ob.size.x, maxf(ob.size.y, ob.size.z)))
		return {"ok": true, "kind": "object", "bones": 0, "aabb": ob, "size": ob.size, "scale_note": ov[0], "scale_factor": ov[1], "why": ""}
	if ext != "glb" and ext != "gltf":
		return _bad("Only .glb and .gltf models can be imported, this one is \"%s\". Export it from your 3D program as glTF binary (.glb) and try again. Nothing was changed." % path.get_extension())
	var f := FileAccess.open(abs, FileAccess.READ)
	if f == null:
		return _bad("That file could not be opened (another program may be using it). Close it there and try again. Nothing was changed.")
	var len_bytes := f.get_length()
	var head := f.get_buffer(mini(len_bytes, 16))
	f.close()
	if len_bytes == 0:
		return _bad("That file is empty (0 bytes), so there is nothing to import. Export it again from the program that made it. Nothing was changed.")
	if ext == "glb" and head.get_string_from_ascii().substr(0, 4) != "glTF":
		return _bad("That is not a valid .glb model: it looks damaged or is a different kind of file. Export it again as glTF binary (.glb). Nothing was changed.")
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(abs, st) != OK:
		return _bad("That model could not be read: the file looks damaged or incomplete. Export it again from your 3D program. Nothing was changed.")
	var scene: Node = doc.generate_scene(st)
	if scene == null:
		return _bad("That model could not be built from the file. Export it again from your 3D program. Nothing was changed.")
	var boxes := []
	_boxes(scene, Transform3D.IDENTITY, boxes)
	var bones := 0
	for sk in scene.find_children("*", "Skeleton3D", true, false):
		bones += (sk as Skeleton3D).get_bone_count()
	scene.free()
	if boxes.is_empty():
		return _bad("The file is a valid glTF model but it holds no 3D shapes, so there is nothing to show. Check that the mesh was exported. Nothing was changed.")
	var box: AABB = boxes[0]
	for i in range(1, boxes.size()):
		box = box.merge(boxes[i])
	var size := box.size
	var longest := maxf(size.x, maxf(size.y, size.z))
	if longest <= 0.0:
		return _bad("The model has no size: all its points sit in one place. Check the mesh in your 3D program. Nothing was changed.")
	var verdict := scale_verdict(longest)
	return {"ok": true, "kind": "rigged" if bones > 0 else "object", "bones": bones, "aabb": box, "size": size,
		"scale_note": verdict[0], "scale_factor": verdict[1], "why": ""}


## What the library holds: {"props": [...], "weapons": [...], "animations": [...]}, each entry
## {"name", "path", "licence": the note's path or ""}. A missing folder gives an empty list; nothing is created.
static func library_list(root := DEFAULT_ROOT) -> Dictionary:
	var out := {"props": [], "weapons": [], "animations": []}
	for folder in out.keys():
		var dir := "%s/%s" % [root, folder]
		if not DirAccess.dir_exists_absolute(_abs(dir)):
			continue
		var files := Array(DirAccess.get_files_at(_abs(dir)))
		files.sort()
		for fn in files:
			if not String(fn).get_extension().to_lower() in ["glb", "obj"]:
				continue
			var base := String(fn).get_basename()
			var lic := "%s/%s.licence.txt" % [dir, base]
			out[folder].append({"name": base, "path": "%s/%s" % [dir, fn], "licence": lic if FileAccess.file_exists(_abs(lic)) else ""})
	return out


## a file name made safe: letters, digits, - and _ only
static func _clean(s: String) -> String:
	var r := ""
	for ch in s:
		r += ch if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "-" or ch == "_" else "_"
	return r if r.strip_edges(true, true).replace("_", "") != "" else "import"


## Copy a model into the library: root/<props|weapons|animations>/<name>.glb plus <name>.licence.txt beside it. as_kind is
## "prop", "weapon" or "animation". Never overwrites (a second "sword" becomes "sword_2"). Refuses, writing nothing, when
## inspect says the file is broken. The original is only read.
## Returns {"ok", "path" (the library copy), "licence" (its note), "kind", "scale_note", "scale_factor", "why"}.
static func accept(path: String, as_kind: String, root := DEFAULT_ROOT, licence := "") -> Dictionary:
	var r := {"ok": false, "path": "", "licence": "", "kind": "", "scale_note": "", "scale_factor": 1.0, "why": ""}
	if not FOLDERS.has(as_kind):
		r["why"] = "Choose what this file is: a prop, a weapon or an animation. Nothing was imported."
		return r
	var info := inspect(path)
	if not info["ok"]:
		r["why"] = info["why"]
		return r
	var folder: String = FOLDERS[as_kind]
	var dir := "%s/%s" % [root, folder]
	DirAccess.make_dir_recursive_absolute(_abs(dir))
	var base := _clean(path.get_file().get_basename())
	var name := base
	var n := 2
	var fext := "obj" if path.get_extension().to_lower() == "obj" else "glb"
	while FileAccess.file_exists(_abs("%s/%s.glb" % [dir, name])) or FileAccess.file_exists(_abs("%s/%s.obj" % [dir, name])) or FileAccess.file_exists(_abs("%s/%s.licence.txt" % [dir, name])):
		name = "%s_%d" % [base, n]
		n += 1
	var dest := "%s/%s.%s" % [dir, name, fext]
	var bytes := FileAccess.get_file_as_bytes(_abs(path))
	var w := FileAccess.open(_abs(dest), FileAccess.WRITE)
	if w == null:
		r["why"] = "The library folder could not be written to. Check that there is free disk space, then try again. Nothing was imported."
		return r
	w.store_buffer(bytes)
	w.close()
	if FileAccess.get_file_as_bytes(_abs(dest)).size() != bytes.size():
		DirAccess.remove_absolute(_abs(dest))
		r["why"] = "The copy into the library came out incomplete (the disk may be full). Nothing was imported."
		return r
	var lic := "%s/%s.licence.txt" % [dir, name]
	var text := licence.strip_edges() if licence.strip_edges() != "" else "licence: not given (the user's own file)"
	var note := FileAccess.open(_abs(lic), FileAccess.WRITE)
	if note != null:
		note.store_string("%s\nsource: %s\nimported: %s\nkind: %s\nsize: %s m\n%s\n" % [text, path, Time.get_date_string_from_system(), info["kind"], info["size"], info["scale_note"]])
		note.close()
	r["ok"] = true
	r["path"] = dest
	r["licence"] = lic if note != null else ""
	r["kind"] = info["kind"]
	r["scale_note"] = info["scale_note"]
	r["scale_factor"] = info["scale_factor"]
	return r
