## RIGGED CHARACTER IMPORT, IN THE APP (the logic is scripts/char_import.gd). The commands, the mapping panel, the scene key.
##   Character: import a rigged character (glb / fbx)   a file dialog; the file is copied into user://characters (the scene keeps
##        that copy), mapped (names, then geometry), the map shown in the bone-map screen when it is not a clean 22 of 22 by
##        name, then the character stands where the Kine body stood: the Kine body is hidden, the scene's proportions become
##        the character's own (Main.proportions_set: one undo step, cards keep their angles), and every pose, card and
##        playback frame is written onto its skeleton (CharImport.pose, from Main._refresh).
##   Character: map the imported skeleton (fix bones)   the same screen on the map in use; Import puts the new map to work.
##   Character: show the Kine body beside the import / put the Kine body back   the pair side by side (1 m apart), or the import alone.
##   Character: remove the import   the Kine body again.
## THE SCENE KEEPS IT: the scene's "charimp" key = {path, pairs (joint -> bone name), method, beside}; a scene with the key opens
## with the character on its body, a scene without it clears one. The map is by bone NAME, so a re-exported file with the same
## bones keeps it.
class_name CharImportApp
extends RefCounted

const META := "charimp_rt"
const DIR := "user://characters"
const SIDE_X := 1.0


static func _say(m: Node, t: String) -> void:
	if m.has_method("_say"):
		m._say(t)


static func active(m: Node) -> bool:
	return m.has_meta(META)


static func state(m: Node) -> Dictionary:
	return m.get_meta(META) if m.has_meta(META) else {}


## ---- commands ---------------------------------------------------------------------------------------------------------
static func ask(m: Node) -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.glb, *.gltf, *.fbx ; rigged characters"])
	fd.use_native_dialog = true
	fd.title = "Import a rigged character (mesh, skin, blend shapes)"
	fd.file_selected.connect(func(p): open(m, p, {}, true); fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	m.add_child(fd)
	fd.popup_centered(Vector2i(800, 500))


## the file into user://characters (never over an earlier one), so a scene's key still finds it
static func keep_copy(path: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var base := path.get_file().get_basename().validate_filename()
	var ext := path.get_extension().to_lower()
	var dest := "%s/%s.%s" % [DIR, base, ext]
	var n := 2
	var bytes := FileAccess.get_file_as_bytes(path)
	while FileAccess.file_exists(dest):
		if FileAccess.get_file_as_bytes(dest) == bytes:
			return dest   # the very same file kept before
		dest = "%s/%s_%d.%s" % [DIR, base, n, ext]
		n += 1
	var f := FileAccess.open(dest, FileAccess.WRITE)
	if f == null:
		return path
	f.store_buffer(bytes)
	f.close()
	return dest


## load `path` and put the character on the body. key: a saved scene key ({} = map it now). review: show the map screen when
## the map is not a clean one. from_scene: the scene already holds the proportions (do not set them again).
## -> {"ok", "why", "mapping", "ch"}
static func open(m: Node, path: String, key := {}, review := false, from_scene := false) -> Dictionary:
	var use_path := path if from_scene else keep_copy(path)
	var ch := CharImport.load_character(ProjectSettings.globalize_path(use_path) if use_path.begins_with("user://") or use_path.begins_with("res://") else use_path)
	if not ch["ok"]:
		_say(m, "could not import %s: %s" % [path.get_file(), ch["why"]])
		return {"ok": false, "why": ch["why"]}
	ch["path"] = use_path
	var src: Dictionary = ch["src"]
	var mapping: Dictionary
	if not (key.get("pairs", {}) as Dictionary).is_empty():
		mapping = CharImport.from_key(src, key)
	else:
		mapping = RetargetMap.resolve(src) if RetargetMap.has_saved(src) else CharImport.map_bones(src)
		if not mapping.has("method"):
			mapping["method"] = "saved"
	mapping["_names"] = src["names"]
	var clean := int(mapping["main"]) == AnimImport.MAIN.size() and String(mapping.get("method", "name")) == "name"
	if review and not clean and m.is_inside_tree():
		_screen(m, ch, mapping, func(mm): _finish(m, ch, mm, from_scene))
		return {"ok": true, "why": "", "mapping": mapping, "ch": ch, "pending": true}
	return _finish(m, ch, mapping, from_scene)


static func _finish(m: Node, ch: Dictionary, mapping: Dictionary, from_scene: bool) -> Dictionary:
	var src: Dictionary = ch["src"]
	var B: Body = m.B
	mapping["_names"] = src["names"]
	if int(mapping["main"]) < CharImport.MAIN_NEED or not mapping["map"].has("pelvis"):
		(ch["root"] as Node).free()
		_say(m, "could not use %s: only %d of %d main bones could be matched (%s). Pick the bones by hand in 'Character: map the imported skeleton'" % [
			String(ch["path"]).get_file(), mapping["main"], AnimImport.MAIN.size(), CharImport.report(src, mapping)])
		return {"ok": false, "why": "too few bones matched", "mapping": mapping}
	clear(m)
	var bd := CharImport.body_dict(src, mapping, B)
	if not from_scene and not bd.is_empty() and m.has_method("proportions_set"):
		m.proportions_set(bd)
	var root3: Node3D = ch["root"]
	root3.name = "ImportedCharacter"
	m.add_child(root3)
	var dq := DqSkin.new()
	dq.attach(ch["meshes"], ch["sk"])
	m.set_meta(META, {"ch": ch, "mapping": mapping, "fit": {}, "sig": -1, "beside": false, "dq": dq})
	if m.get("man_root") != null:
		(m.get("man_root") as Node3D).visible = false
	update(m)
	_say(m, "imported %s as a Kine character: %s. %s" % [String(ch["path"]).get_file(), ch["text"], CharImport.report(src, mapping)])
	return {"ok": true, "why": "", "mapping": mapping, "ch": ch}


## remove the character; the Kine body is shown again
static func clear(m: Node) -> void:
	if not m.has_meta(META):
		return
	var st: Dictionary = m.get_meta(META)
	m.remove_meta(META)
	var r: Node = st["ch"]["root"]
	if is_instance_valid(r):
		if r.get_parent() != null:
			r.get_parent().remove_child(r)
		r.free()
	if m.get("man_root") != null:
		(m.get("man_root") as Node3D).visible = true


## main._refresh: the Kine pose onto the imported skeleton (the fit is made again only when the body's proportions changed)
static func update(m: Node) -> void:
	if not m.has_meta(META):
		return
	var st: Dictionary = m.get_meta(META)
	var B: Body = m.B
	var sig := B.body.hash()
	if int(st["sig"]) != sig:
		st["fit"] = CharImport.fit(st["ch"]["src"], st["mapping"], B)
		st["sig"] = sig
	if not st["fit"]["ok"]:
		return
	CharImport.pose(st["ch"], st["mapping"], st["fit"], B)
	var r: Node3D = st["ch"]["root"]
	var beside: bool = st["beside"]
	r.position = Vector3(SIDE_X if beside else 0.0, 0, 0)
	if m.get("man_root") != null:
		var mr := m.get("man_root") as Node3D
		mr.visible = beside and not (m.has_method("_hides") and m._hides("figure"))
		mr.position = Vector3(-SIDE_X, 0, 0) if beside else Vector3.ZERO
	var k := float(m.S.dq_skin) if m.get("S") != null else 0.0
	if k > 0.0 or int(st.get("dq_on", 0)) == 1:
		(st["dq"] as DqSkin).update(k)
		st["dq_on"] = 1 if k > 0.0 else 0


static func beside_toggle(m: Node) -> void:
	if not m.has_meta(META):
		_say(m, "no character is imported: use 'Character: import a rigged character'")
		return
	var st: Dictionary = m.get_meta(META)
	st["beside"] = not st["beside"]
	update(m)
	_say(m, "the Kine body is shown beside the import" if st["beside"] else "the import stands alone")


static func remove_cmd(m: Node) -> void:
	if not m.has_meta(META):
		_say(m, "no character is imported")
		return
	clear(m)
	_say(m, "the imported character is removed; the Kine body is back")


## the mapping screen on the map in use (or on `mapping` of a character not yet finished)
static func map_cmd(m: Node) -> void:
	if not m.has_meta(META):
		_say(m, "no character is imported: use 'Character: import a rigged character'")
		return
	var st: Dictionary = m.get_meta(META)
	_screen(m, st["ch"], st["mapping"].duplicate(true), func(mm):
		mm["method"] = "manual"
		mm["_names"] = st["ch"]["src"]["names"]
		st["mapping"] = mm
		st["sig"] = -1
		update(m)
		_say(m, "map changed: " + CharImport.report(st["ch"]["src"], mm)))


static func _screen(m: Node, ch: Dictionary, mapping: Dictionary, done: Callable) -> void:
	var src: Dictionary = ch["src"]
	var layer := CanvasLayer.new()
	layer.layer = 90
	layer.name = "CharMapLayer"
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var cen := CenterContainer.new()
	cen.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(cen)
	var sc := RetargetMap.Screen.new()
	var vp := Vector2(1024, 600)
	if m.is_inside_tree() and m.get_viewport() != null:
		vp = m.get_viewport().get_visible_rect().size
	sc.custom_minimum_size = Vector2(minf(760.0, vp.x - 32.0), minf(620.0, vp.y - 32.0))
	cen.add_child(sc)
	mapping["_names"] = src["names"]
	sc.setup(src, mapping)
	sc.done.connect(func(mm): layer.queue_free(); done.call(mm))
	sc.cancelled.connect(func():
		layer.queue_free()
		if not m.has_meta(META) and is_instance_valid(ch["root"]) and ch["root"].get_parent() == null:
			(ch["root"] as Node).free())
	m.add_child(layer)


## ---- the scene ------------------------------------------------------------------------------------------------------------
static func put_key(m: Node, d: Dictionary) -> void:
	if not m.has_meta(META):
		return
	var st: Dictionary = m.get_meta(META)
	var k := CharImport.to_key(st["ch"], st["mapping"])
	k["beside"] = st["beside"]
	d[CharImport.KEY] = k


static func from_scene(m: Node, d: Dictionary) -> void:
	if not d.has(CharImport.KEY):
		clear(m)
		return
	var k: Dictionary = d[CharImport.KEY]
	var p := String(k.get("path", ""))
	if p == "" or not FileAccess.file_exists(p):
		clear(m)
		_say(m, "this scene's imported character (%s) is not where it was kept: the Kine body is shown" % p.get_file())
		return
	var r := open(m, p, k, false, true)
	if r["ok"] and m.has_meta(META) and bool(k.get("beside", false)):
		(m.get_meta(META) as Dictionary)["beside"] = true
		update(m)
