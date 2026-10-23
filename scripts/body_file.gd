class_name BodyFile
extends RefCounted
## G07 (docs/ROADMAP_400.md): BODIES AS FILES (.kbody). The fighter's body (G01, scripts/base_body.gd: the skin as a KMesh,
## one "skin:<UE5 bone>" weight channel per bone, "surface" and "uv" attributes) saved, listed and opened again.
## THE FILE (JSON, like .kmesh): {"format": "kbody", "version": 1, "name", "params": {"proportions": the scene's body dict
##   (Proportions.clean'd: stature, segment scales, sex, mass, preset; the G13 five numbers land there), "verts", "faces"},
##   "mesh": KMesh.to_dict()}. The mesh block is .kmesh's own (float32 / int32 deflated + base64), so every vertex and every
##   weight reads back bit for bit (tests/bodyfile_test.gd).
## WHERE: res://bodies/ (dir; a test points it elsewhere), beside scenes/ and poses/: the user's work, not a cache.
## WRITES (the confirm policy, tests/confirm_test.gd 1e): only NEW files in dir, never over another file (<name>_2, _3...);
##   the same body saved twice is the same file (found by its content hash), so saving never piles up copies. Nothing is
##   removed here. The thumbnails are a cache in user://thumbs (scripts/body_thumbs.gd).
## THE SCENE REMEMBERS ITS BODY BY REFERENCE: the scene's key "body_mesh" = {"file": the .kbody path, "sha256": the file's
##   hash}, written when the fighter draws an applied body (BaseBody generation > 0). Not embedded, because:
##   - size: the body is ~0.5-1 MB of JSON (7k verts x 60 weight channels); a scene is ~10-50 kB. A scene is autosaved every
##     few seconds, snapshotted into up to 30 timed versions (R20), diffed (scene_diff) and packed; embedding would copy the
##     body into every one of them.
##   - sharing: one body serves many scenes (G08 re-fits scenes to a body); an embedded copy per scene could drift apart.
##   - safety: body files are never overwritten (above), so a reference cannot be silently repointed; the hash says when the
##     file is not the one the scene was saved with (it still opens, and the status line says so).
##   Saving a scene whose applied body has no file yet writes it first (before_save: <scene>_body.kbody, a NEW file).
##   Opening a scene with the key puts that body on the fighter (no undo step: opening is not an edit); a scene without the
##   key leaves the fighter's body as it is (an applied body is not dropped by opening a scene to animate with it).
##   NOT covered: the autosave of a body applied but never saved as a file (the key needs a file to point at).

const FORMAT := "kbody"
const VERSION := 1
const EXT := "kbody"
const KEY := "body_mesh"

static var dir := "res://bodies"
static var last_error := ""


# ---------------------------------------------------------------- the file

static func to_dict(k: KMesh, params: Dictionary, nm: String) -> Dictionary:
	var p := params.duplicate(true)
	p["verts"] = k.verts.size()
	p["faces"] = k.faces.size()
	return {"format": FORMAT, "version": VERSION, "name": nm, "params": p, "mesh": k.to_dict()}


## {"mesh": KMesh, "params", "name"}, or {} with last_error set (a next step named)
static func from_dict(d) -> Dictionary:
	last_error = ""
	if not (d is Dictionary) or (d as Dictionary).get("format", "") != FORMAT:
		last_error = "not a .kbody file. Pick a body saved by Kine (Search \"Body: save the fighter's body\")."
		return {}
	if int(d.get("version", 0)) != VERSION:
		last_error = "unsupported .kbody version %s (this build reads %d). Update Kine." % [str(d.get("version", "?")), VERSION]
		return {}
	var k := KMesh.new().from_dict(d.get("mesh", {}) if d.get("mesh") is Dictionary else {})
	if k == null:
		last_error = "the body's mesh is damaged: " + KMesh.last_error
		return {}
	return {"mesh": k, "params": d.get("params", {}) if d.get("params") is Dictionary else {}, "name": String(d.get("name", ""))}


static func load_file(path: String) -> Dictionary:
	last_error = ""
	if not FileAccess.file_exists(path):
		last_error = "no body file at '%s'. Pick an existing .kbody." % path
		return {}
	var js := JSON.new()
	if js.parse(FileAccess.get_file_as_string(path)) != OK:
		last_error = "'%s' is not valid .kbody JSON. Pick a body saved by Kine." % path.get_file()
		return {}
	return from_dict(js.data)


## every .kbody in dir, sorted by name
static func list() -> Array:
	var out := []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		return out
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() == EXT:
			out.append(dir.path_join(f))
	out.sort()
	return out


static func _safe(nm: String) -> String:
	var s := ""
	for ch in nm.strip_edges():
		s += ch if (ch.is_valid_identifier() or ch.is_valid_int() or ch == "-") else "_"
	return s if s != "" else "body"


## write k as a .kbody in dir: a NEW file (<name>, <name>_2, ...), or the existing file holding exactly this content.
## -> {"ok", "path", "sha", "new", "error"}
static func save_kmesh(k: KMesh, params: Dictionary, nm: String) -> Dictionary:
	last_error = ""
	var txt := JSON.stringify(to_dict(k, params, nm))
	var sha := txt.sha256_text()
	for p in list():
		if FileAccess.get_sha256(p) == sha:
			return {"ok": true, "path": p, "sha": sha, "new": false, "error": ""}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var base := _safe(nm)
	var path := dir.path_join(base + "." + EXT)
	var n := 2
	while FileAccess.file_exists(path):
		path = dir.path_join("%s_%d.%s" % [base, n, EXT])
		n += 1
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		last_error = "could not write '%s' (error %d). Check the bodies folder can be written." % [path, FileAccess.get_open_error()]
		return {"ok": false, "path": "", "sha": "", "new": false, "error": last_error}
	f.store_string(txt)
	f.close()
	return {"ok": true, "path": path, "sha": sha, "new": true, "error": ""}


# ---------------------------------------------------------------- the fighter

## the generation record the fighter draws now (BaseBody's gens: {"pieces", "src"} plus our "kbody" / "sha")
static func _rec(m: Node) -> Dictionary:
	var gens: Array = BaseBody._ensure_gens(m)
	return gens[clampi(BaseBody.gen(m), 0, gens.size() - 1)]


static func _params(m: Node) -> Dictionary:
	var S: Scene = m._hero_scene() if m.has_method("_hero_scene") else m.S
	return {"proportions": S.body.duplicate(true)}


## the fighter's body as it is drawn now, saved (save_kmesh); the generation remembers its file
static func save_current(m: Node, nm: String) -> Dictionary:
	if m.pieces.is_empty() or BaseBody.skin_of(m) == null:
		return {"ok": false, "error": "the fighter has no skinned body to save"}
	var r := save_kmesh(BaseBody.read(m), _params(m), nm)
	if r["ok"]:
		var rec := _rec(m)
		rec["kbody"] = r["path"]
		rec["sha"] = r["sha"]
	return r


## put the body in a .kbody on the fighter (BaseBody.apply: one undo step when undo). -> {"ok", "error", "params", ...}
static func open(m: Node, path: String, undo := true) -> Dictionary:
	var b := load_file(path)
	if b.is_empty():
		return {"ok": false, "error": last_error}
	var r := BaseBody.apply(m, b["mesh"], undo)
	if not r["ok"]:
		return r
	var rec := _rec(m)
	rec["kbody"] = path
	rec["sha"] = FileAccess.get_sha256(path)
	r["params"] = b["params"]
	r["name"] = b["name"]
	return r


## the scene's key for the body drawn now ({} for the mannequin as shipped, or an applied body with no file yet)
static func scene_key(m: Node) -> Dictionary:
	if m.get("pieces") == null or not m.has_meta(BaseBody.META_GENS) or BaseBody.gen(m) == 0:
		return {}
	var rec := _rec(m)
	if not rec.has("kbody"):
		return {}
	return {"file": rec["kbody"], "sha256": rec["sha"]}


## main._scene_dict: the key on the scene's dict
static func put_key(m: Node, d: Dictionary) -> void:
	var k := scene_key(m)
	if not k.is_empty():
		d[KEY] = k


## main._save_scene_now, before the dict is made: an applied body with no file (or a file gone) is saved first
static func before_save(m: Node, scene_name: String) -> void:
	if m.get("pieces") == null or not m.has_meta(BaseBody.META_GENS) or BaseBody.gen(m) == 0:
		return
	var rec := _rec(m)
	if rec.has("kbody") and FileAccess.file_exists(rec["kbody"]):
		return
	save_current(m, (scene_name if scene_name != "" else "scene") + "_body")


## main._load_scene: the scene's body back on the fighter (no undo step: opening a file is not an edit)
static func from_scene(m: Node, d: Dictionary) -> void:
	var key = d.get(KEY)
	if not (key is Dictionary):
		return
	var p := String(key.get("file", ""))
	if not FileAccess.file_exists(p):
		m._say.call_deferred("this scene's body file %s is missing: the fighter keeps the body it has (restore the file to bodies/ and open the scene again)" % p.get_file())
		return
	var sha := FileAccess.get_sha256(p)
	if m.has_meta(BaseBody.META_GENS) and BaseBody.gen(m) > 0:
		var rec := _rec(m)
		if rec.get("kbody", "") == p and rec.get("sha", "") == sha:
			return   # drawn already
	var r := open(m, p, false)
	if not r["ok"]:
		m._say.call_deferred("this scene's body %s could not be opened: %s" % [p.get_file(), r["error"]])
	elif sha != String(key.get("sha256", sha)):
		m._say.call_deferred("this scene's body %s changed since the scene was saved: the file as it is now was put on the fighter" % p.get_file())


# ---------------------------------------------------------------- the commands and the Browser

## "Body: save the fighter's body (.kbody)"
static func save_cmd(m: Node) -> void:
	var S: Scene = m._hero_scene()
	var r := save_current(m, (S.name if S.name != "" else "body") + ("_body" if S.name != "" else ""))
	if not r["ok"]:
		m._say("Body: NOT SAVED: " + String(r["error"]))
		return
	_browser_refresh(m)
	m._say("Body: %s %s (mesh, skin weights, the scene's proportions); the Browser lists it under Bodies, a click puts it on the fighter" % ["saved as" if r["new"] else "already saved, the same body is", String(r["path"]).get_file()])


## the Browser's "Bodies" rows: one per file, its picture as the icon once drawn (BodyThumbs)
static func fill_browser(m: Node, tree: Tree, folder: TreeItem) -> void:
	for c in folder.get_children():
		c.free()
	var files := list()
	folder.visible = not files.is_empty()
	folder.set_text(0, "Bodies  (%d)" % files.size())
	var th := thumbs(m)
	for p in files:
		var it := tree.create_item(folder)
		it.set_text(0, String(p).get_file().get_basename())
		it.set_metadata(0, {"kbody": p})
		it.set_tooltip_text(0, "click: the fighter takes this body (one undo step)")
		var tex := th.picture(p) if th != null else null
		if tex != null:
			it.set_icon(0, tex)
			it.set_icon_max_width(0, 24)
		elif th != null:
			th.request(p)


## the Browser's click on a body row
static func open_cmd(m: Node, path: String) -> void:
	var r := open(m, path, true)
	if not r["ok"]:
		m._say("Body: NOT OPENED: " + String(r["error"]))
		return
	var props: Dictionary = (r["params"] as Dictionary).get("proportions", {})
	var S: Scene = m._hero_scene()
	var note := "" if props == S.body else "; it was saved with other proportions (%s): 'Body: proportions...' sets them" % ("the mannequin's" if props.is_empty() else "%.1f cm" % (100.0 * float(props.get("stature", Proportions.DEFAULT_STATURE))))
	m._say("Body: the fighter has the body %s (%d verts); Ctrl+Z takes it back%s" % [path.get_file().get_basename(), r["verts"], note])


## the thumbnail maker, one per main (made lazily; its pictures refresh the Browser)
static func thumbs(m: Node) -> BodyThumbs:
	if not (m is Node) or not m.is_inside_tree():
		return null
	var th := m.get_node_or_null("body_thumbs") as BodyThumbs
	if th == null:
		th = BodyThumbs.new()
		th.name = "body_thumbs"
		m.add_child(th)
		th.made.connect(func(_p): _browser_refresh(m))
	return th


static func _browser_refresh(m: Node) -> void:
	if is_instance_valid(m) and m.get("ui_browser") != null and is_instance_valid(m.ui_browser):
		m.ui_browser.refresh()
