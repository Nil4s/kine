## pose_pack.gd - THE ASSET STORE (ROADMAP 96): a pose or a scene shared as one file, and a pack read back in. No server.
## A pack is ONE JSON file (*.kinepack). It is DATA: nothing in it is run, and every key is checked, each refusal named:
##   format, version, kind (pose | scene), name, author, licence (CC0 / CC-BY / All rights reserved), app_version (the
##   project's application/config/version), skeleton (id), sha256 (of the payload text), payload (the pose file's or the
##   scene file's text, byte for byte), thumb (a PNG, base64), thumb_sha256.
## Unknown keys, wrong types, joint angles outside data/body_limits.json, file paths, scripts, a hash that does not
## match, a picture that is not a PNG and any pack over 5 MB are refused. A pose of another skeleton is retargeted by
## bone name and says so; a scene of another skeleton is refused.
##   PosePack.share(pose_path, dest, name, author, licence, thumb)   -> the pose pack written
##   PosePack.share_scene(scene_path, dest, name, author, licence)   -> the scene pack written
##   PosePack.read(path)                                             -> {ok, why, pack}: checked, nothing written
##   PosePack.commit(m, pack)                                        -> into Library > Imported, ONE undo step
##   PosePack.lib_move(files, to_trash)                              -> what Ctrl+Z / redo do with an import's files
## Writes only under user:// (the library, its trash) or the folder the user picks in the save dialog.
class_name PosePack
extends RefCounted

const FORMAT := "kinepack"
const VERSION := 1
const KINDS := ["pose", "scene"]
const SKELETON := "kine-mannequin-1"        # the rig data/skeleton.json describes; another id is retargeted (poses) or refused (scenes)
const MAX_BYTES := 5 * 1024 * 1024          # a whole pack, checked before it is read
const MAX_POSE_BYTES := 512 * 1024          # a pose file's text (a real pose is ~20 kB)
const MAX_SCENE_BYTES := 4 * 1024 * 1024    # a scene file's text (the pack's 5 MB less the picture and the wrapping)
const MAX_THUMB_BYTES := 1024 * 1024        # the picture
const MAX_THUMB_PX := 1024
const MAX_NAME := 60
const MAX_CARDS := 300
const MAX_PROPS := 200
const LICENCES := ["CC0", "CC-BY", "All rights reserved"]
const LICENCE_SAY := {
	"CC0": "anyone may use it for anything; no credit asked",
	"CC-BY": "anyone may use it if they credit the author",
	"All rights reserved": "not for reuse without the author's permission",
}
const TOP_KEYS := ["format", "version", "kind", "name", "author", "licence", "app_version", "skeleton", "sha256", "payload", "thumb", "thumb_sha256"]
const POSE_KEYS := ["joints", "offset", "contacts", "note", "weapon", "weapon2", "from", "heel_up", "settled", "stick", "rejected"]
const WEAPON_KEYS := ["kind", "length", "hand", "knob", "tip", "rot", "local_pos", "local_rot", "two_hand_grip", "grip_m", "grip2"]
const JOINT_KEYS := ["bend", "side", "twist", "A", "G", "pos", "end", "at_limit"]
## a saved scene's own keys (scene.gd to_dict). Not accepted: "actors" (other scenes), "audio" (a file), anything else
const SCENE_KEYS := ["scene", "natural", "on_floor", "floor_body", "pin", "fps", "length_s", "cards", "bad_frames", "note", "plan",
	"spline", "free_limits", "moving_holds", "loop", "fitness", "breath", "layer", "layer_w", "layers", "props", "part_keys", "markers", "notes",
	"beats", "beats_audio", "face", "attrs", "iq", "lip", "ik", "plants", "drivers", "secondary", "hair", "cape", "constraints", "body",
	"shots", "clips", "sets", "camera", "boxes"]
const CARD_KEYS := ["name", "move", "hold", "arrive_s", "leave_s", "pose", "flow", "walk", "steps", "lift", "ease", "ease_bias",
	"plant", "take", "drop", "drop_rig", "air", "ktype", "weight_i"]
const PROP_KEYS := ["kind", "pos", "yaw", "swing", "keys"]
const PROP_KEY_KEYS := ["t", "pos", "yaw", "swing"]
const BANNED_KEYS := ["script", "path", "file", "src", "code", "expression", "url", "audio", "actors", "res"]
const FREE_TEXT := ["note", "from", "rejected", "plan", "scene", "name", "reason", "text"]   # prose: a path inside is still refused
const FILE_EXT := [".gd", ".gdshader", ".glb", ".gltf", ".json", ".tscn", ".tres", ".scn", ".wav", ".ogg", ".mp3", ".png", ".exe", ".py", ".sh", ".bat", ".cs"]
const TOL := 0.05                            # degrees: a saved angle is written at 0.01 deg, so the limit is not strict to the last digit
const IMPORTED := "imported"                # the library folder: <root>/imported (poses and scenes both)
const LIB_DIRS := ["res://poses/lib", "res://poses", "res://moves"]
const PNG_SIG := [137, 80, 78, 71, 13, 10, 26, 10]

static var _lim := {}                        # joint -> {"bend": Vector2, "side", "twist"}: data/body_limits.json, read once


## the joint limits of the rig (Body reads data/body_limits.json)
static func limits() -> Dictionary:
	if _lim.is_empty():
		var b := Body.new()
		b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		_lim = b.lim.duplicate(true)
	return _lim


## the parts of a list as one line of text
static func _join(a: Array) -> String:
	var out := ""
	for i in a.size():
		out += ("" if i == 0 else ", ") + str(a[i])
	return out


static func _bad(why: String) -> Dictionary:
	return {"ok": false, "why": why, "pack": {}, "path": ""}


static func _is_num(v: Variant) -> bool:
	return (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and is_finite(float(v))


static func sha(b: PackedByteArray) -> String:
	var c := HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	c.update(b)
	return c.finish().hex_encode()


## a name as a file name takes it: no slashes, colons or control characters; at most MAX_NAME letters
static func clean_name(s: String) -> String:
	var out := ""
	for c in s.strip_edges():
		if "/\\:*?\"<>|".contains(c) or c.unicode_at(0) < 32:
			continue
		out += c
	return out.left(MAX_NAME)


## the project's version, as a pack records it (application/config/version in project.godot)
static func app_version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "dev"))


## a pack as a dictionary (no check): what share writes and what a test can write by hand
static func build(payload_text: String, name: String, author: String, licence: String, thumb: PackedByteArray,
		app := "", kind := "pose") -> Dictionary:
	return {"format": FORMAT, "version": VERSION, "kind": kind, "name": name, "author": author, "licence": licence,
		"app_version": app if app != "" else app_version(), "skeleton": SKELETON, "sha256": sha(payload_text.to_utf8_buffer()),
		"payload": payload_text, "thumb": Marshalls.raw_to_base64(thumb), "thumb_sha256": sha(thumb)}


## the pack dictionary written as JSON at dest (the folder made if missing)
static func write(d: Dictionary, dest: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest.get_base_dir()))
	var f := FileAccess.open(dest, FileAccess.WRITE)
	if f == null:
		return _bad("could not write %s (error %d)" % [dest.get_file(), FileAccess.get_open_error()])
	f.store_string(JSON.stringify(d, " "))
	f.close()
	return {"ok": true, "why": "", "path": dest, "pack": {}}


## SHARE a pose: the pose file's bytes go in as they are (a held weapon travels with it)
static func share(pose_path: String, dest: String, name: String, author: String, licence: String,
		thumb: PackedByteArray = PackedByteArray(), app := "") -> Dictionary:
	return share_file("pose", pose_path, dest, name, author, licence, thumb, app)


## SHARE a scene: the scene file's bytes as they are (cards, timings, markers, props)
static func share_scene(scene_path: String, dest: String, name: String, author: String, licence: String,
		thumb: PackedByteArray = PackedByteArray(), app := "") -> Dictionary:
	return share_file("scene", scene_path, dest, name, author, licence, thumb, app)


## the shared file's bytes wrapped as a pack, checked before it is written (so a pack that could not be read back is
## never shared)
static func share_file(kind: String, path: String, dest: String, name: String, author: String, licence: String,
		thumb: PackedByteArray, app: String) -> Dictionary:
	var raw := FileAccess.get_file_as_bytes(path)
	if raw.is_empty():
		return _bad("%s is empty or missing: nothing was shared. Save it again, then share it" % path.get_file())
	var text := raw.get_string_from_utf8()
	if text.to_utf8_buffer() != raw:
		return _bad("%s is not plain UTF-8 text, so it cannot be shared exactly: nothing was shared" % path.get_file())
	var pd: Variant = JSON.parse_string(text)
	var key := "joints" if kind == "pose" else "cards"
	if not (pd is Dictionary) or not (pd as Dictionary).has(key):
		return _bad("%s is not a %s file: nothing was shared. Pick one from the %s" % [path.get_file(), kind,
			"pose library" if kind == "pose" else "Scene files"])
	var nm := clean_name(name)
	if nm == "":
		return _bad("the pack needs a name: type one, then save again")
	var pic := thumb if not thumb.is_empty() else _placeholder()
	var pack := build(text, nm, author.strip_edges().left(MAX_NAME), licence, pic, app, kind)
	var chk := check(pack)
	if not chk["ok"]:
		return _bad("the pack did not check out, so nothing was shared: %s" % chk["why"])
	var w := write(pack, dest)
	if not w["ok"]:
		return w
	return {"ok": true, "why": "", "path": dest, "pack": {}, "note": "", "name": nm, "kind": kind}


## the picture of a pack with no picture of its own: the pose library's backdrop, empty
static func _placeholder() -> PackedByteArray:
	var img := Image.create_empty(160, 200, false, Image.FORMAT_RGB8)
	img.fill(PoseLibrary.BG)
	return img.save_png_to_buffer()


## READ: the file as a pack, checked. Returns {ok, why, pack}; pack holds what import needs. Nothing is written
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _bad("there is no file at %s" % path)
	var f := FileAccess.open(path, FileAccess.READ)
	var n := f.get_length()
	f.close()
	if n > MAX_BYTES:
		return _bad("the pack is %.1f MB and the limit is 5 MB, so it was not read. A pack is a few kilobytes: this file is not one" % (float(n) / 1048576.0))
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary):
		return _bad("it is not a Kine pack: the file is not a JSON object")
	return check(d)


## every key of a pack checked, in the order a reader meets them; the reason is the first thing wrong
static func check(d: Dictionary) -> Dictionary:
	for k in d.keys():
		if not k in TOP_KEYS:
			return _bad("unknown key '%s' at the top of the pack: a pack holds only %s" % [k, _join(TOP_KEYS)])
	for k in TOP_KEYS:
		if not d.has(k):
			return _bad("the pack has no '%s': it is not a complete pack" % k)
	if typeof(d["format"]) != TYPE_STRING or d["format"] != FORMAT:
		return _bad("not a Kine pack: its format is %s" % str(d["format"]))
	if not _is_num(d["version"]) or int(d["version"]) != VERSION:
		return _bad("pack version %s: this app reads version %d" % [str(d["version"]), VERSION])
	for k in ["kind", "name", "author", "licence", "app_version", "skeleton", "sha256", "payload", "thumb", "thumb_sha256"]:
		if typeof(d[k]) != TYPE_STRING:
			return _bad("'%s' must be text, not %s" % [k, type_string(typeof(d[k]))])
	var kind: String = d["kind"]
	if not kind in KINDS:
		return _bad("kind '%s' is not one of %s" % [kind, _join(KINDS)])
	var nm: String = d["name"]
	if nm == "" or nm.length() > MAX_NAME or nm != clean_name(nm):
		return _bad("the name '%s' is empty, too long (over %d letters) or has a character a file name cannot take" % [nm.left(20), MAX_NAME])
	var au: String = d["author"]
	if au.length() > MAX_NAME or au != au.strip_edges():
		return _bad("the author name is longer than %d letters or has spaces at its ends" % MAX_NAME)
	if not (d["licence"] in LICENCES):
		return _bad("licence '%s' is not one of %s" % [d["licence"], _join(LICENCES)])
	if d["app_version"].length() > 40 or d["skeleton"].length() > 60:
		return _bad("the app version or skeleton id is too long")
	var payload: String = d["payload"]
	var pbytes := payload.to_utf8_buffer()
	var limit := MAX_POSE_BYTES if kind == "pose" else MAX_SCENE_BYTES
	if pbytes.size() > limit:
		return _bad("the %s inside is %d kB and the limit is %d kB" % [kind, pbytes.size() / 1024, limit / 1024])
	if sha(pbytes) != d["sha256"]:
		return _bad("content hash mismatch: the %s inside is not the one this pack was shared with, so the pack was changed or damaged after sharing. Nothing was imported; ask for it again" % kind)
	var pd: Variant = JSON.parse_string(payload)
	if not (pd is Dictionary):
		return _bad("the %s inside is not a JSON object" % kind)
	var same := String(d["skeleton"]) == SKELETON
	var body := {}
	if kind == "pose":
		body = check_pose(pd as Dictionary, same, payload)
	else:
		if not same:
			return _bad("a scene of skeleton '%s' is not this rig's: scenes are not retargeted, so it was not imported" % d["skeleton"])
		body = check_scene(pd as Dictionary, payload)
	if not body["ok"]:
		return body
	var thumb := Marshalls.base64_to_raw(d["thumb"])
	if thumb.is_empty() or thumb.size() > MAX_THUMB_BYTES:
		return _bad("the picture is missing or over %d kB" % (MAX_THUMB_BYTES / 1024))
	if sha(thumb) != d["thumb_sha256"]:
		return _bad("picture hash mismatch: the picture was changed after sharing. Nothing was imported; ask for it again")
	if thumb.slice(0, 8) != PackedByteArray(PNG_SIG):
		return _bad("the picture is not a PNG")
	var img := Image.new()
	if img.load_png_from_buffer(thumb) != OK or img.get_width() > MAX_THUMB_PX or img.get_height() > MAX_THUMB_PX:
		return _bad("the picture is not a readable PNG of at most %d px" % MAX_THUMB_PX)
	var pack := {"kind": kind, "name": nm, "author": au, "licence": d["licence"], "app_version": d["app_version"],
		"skeleton": d["skeleton"], "pose_text": body["text"], "thumb": thumb, "joints": int(body["joints"]),
		"kept": int(body["kept"]), "dropped": body["dropped"], "retargeted": body["retargeted"], "note": body["note"],
		"cards": int(body["cards"]), "props": int(body["props"]), "length_s": float(body["length_s"])}
	return {"ok": true, "why": "", "pack": pack, "path": ""}


## the pose inside: keys, types, angles inside the rig's limits. A pose of another skeleton keeps the bones this rig
## has (by name) and lists the rest; the same skeleton with a bone it does not have is refused
static func check_pose(pd: Dictionary, same_rig: bool, original: String) -> Dictionary:
	for k in pd.keys():
		if not k in POSE_KEYS:
			return _bad("unknown key '%s' in the pose: a pose may hold only %s" % [k, _join(POSE_KEYS)])
	var sc := _scan(pd, "", 0)
	if sc != "":
		return _bad(sc)
	for k in ["weapon", "weapon2"]:
		if pd.has(k):
			var w: Variant = pd[k]
			if not (w is Dictionary):
				return _bad("'%s' must be a table (empty when no weapon is held)" % k)
			for wk in (w as Dictionary).keys():
				if not wk in WEAPON_KEYS:
					return _bad("unknown key '%s' in '%s': a weapon may hold only %s" % [wk, k, _join(WEAPON_KEYS)])
			if not (w as Dictionary).is_empty() and not (_nums((w as Dictionary).get("knob", null), 3) and _nums((w as Dictionary).get("tip", null), 3)):
				return _bad("'%s' needs 'knob' and 'tip' as three numbers each" % k)
	for k in ["from", "rejected"]:
		if pd.has(k) and (typeof(pd[k]) != TYPE_STRING or (pd[k] as String).length() > 500):
			return _bad("'%s' must be text of at most 500 letters" % k)
	for k in ["heel_up", "settled"]:
		if pd.has(k) and not (pd[k] is Array and (pd[k] as Array).all(func(x): return typeof(x) == TYPE_STRING)):
			return _bad("'%s' must be a list of part names" % k)
	if pd.has("stick") and not _plain(pd["stick"], 0):
		return _bad("'stick' must be plain data (numbers, text, lists, tables)")
	if pd.has("offset"):
		var o: Variant = pd["offset"]
		if not (o is Array) or (o as Array).size() != 3 or not (o as Array).all(func(x): return _is_num(x) and absf(float(x)) <= 5.0):
			return _bad("'offset' must be three numbers in metres, each within 5 m")
	if pd.has("note") and (typeof(pd["note"]) != TYPE_STRING or (pd["note"] as String).length() > 500):
		return _bad("'note' must be text of at most 500 letters")
	if pd.has("contacts"):
		if not (pd["contacts"] is Array):
			return _bad("'contacts' must be a list")
		for c in pd["contacts"]:
			if not (c is Array) or (c as Array).size() != 3 or typeof(c[0]) != TYPE_STRING or typeof(c[1]) != TYPE_STRING or not _is_num(c[2]):
				return _bad("each contact must be [part, part, depth in metres]")
	if not pd.has("joints") or not (pd["joints"] is Dictionary):
		return _bad("the pose has no 'joints' table")
	var js: Dictionary = pd["joints"]
	if js.size() > 200:
		return _bad("the pose has %d joints: a body has at most 200" % js.size())
	var lim := limits()
	var kept := {}
	var dropped := []
	for j in js:
		var jn := String(j)
		if jn.length() > 32 or not _bone_name(jn):
			return _bad("'%s' is not a bone name (lowercase letters, digits and _, at most 32)" % jn.left(40))
		var jd: Variant = js[j]
		if not (jd is Dictionary):
			return _bad("joint '%s' is not a table of angles" % jn)
		for k in (jd as Dictionary).keys():
			if not k in JOINT_KEYS:
				return _bad("unknown key '%s' in joint '%s': a joint may hold only %s" % [k, jn, _join(JOINT_KEYS)])
		for k in ["bend", "side", "twist"]:
			if not (jd as Dictionary).has(k) or not _is_num(jd[k]):
				return _bad("joint '%s' has no '%s' angle (a number, in degrees)" % [jn, k])
			var a := float(jd[k])
			if lim.has(jn):
				var rg: Vector2 = lim[jn][k]
				if a < rg.x - TOL or a > rg.y + TOL:
					return _bad("joint '%s' %s %.1f deg is out of its range %.1f..%.1f deg (data/body_limits.json): the pack was not imported" % [jn, k, a, rg.x, rg.y])
			elif absf(a) > 180.0:
				return _bad("joint '%s' %s %.1f deg is past a full turn" % [jn, k, a])
		for k in ["A", "G"]:
			if (jd as Dictionary).has(k) and not _nums((jd as Dictionary)[k], 4):
				return _bad("joint '%s': '%s' must be four numbers (a quaternion)" % [jn, k])
		for k in ["pos", "end"]:
			if (jd as Dictionary).has(k) and not _nums((jd as Dictionary)[k], 3):
				return _bad("joint '%s': '%s' must be three numbers in metres" % [jn, k])
		if (jd as Dictionary).has("at_limit") and not ((jd as Dictionary)["at_limit"] is Array):
			return _bad("joint '%s': 'at_limit' must be a list" % jn)
		if lim.has(jn):
			kept[jn] = jd
		else:
			if same_rig:
				return _bad("joint '%s' is not a bone of the %s skeleton: the pack was not imported" % [jn, SKELETON])
			dropped.append(jn)
	if not same_rig and js.size() > 0 and kept.is_empty():
		return _bad("none of the pack's joints (%s...) is a bone of this rig: the pack was not imported" % _join(js.keys().slice(0, 3)))
	var retargeted := not same_rig
	var text := original   # the file's own bytes: a pack that is not retargeted keeps them exactly
	var note := ""
	if retargeted:
		var rp: Dictionary = pd.duplicate(true)
		rp["joints"] = kept
		text = JSON.stringify(rp, " ")
		note = "the pack's skeleton is not this rig's: retargeted by bone name, kept %d of %d joints%s" % [kept.size(), js.size(),
			"" if dropped.is_empty() else ", dropped " + _join(dropped.slice(0, 6))]
	return {"ok": true, "why": "", "pack": {}, "path": "", "text": text, "joints": js.size(), "kept": kept.size(),
		"dropped": dropped, "retargeted": retargeted, "note": note, "cards": 0, "props": 0, "length_s": 0.0}


## a saved scene: its keys, its cards (each pose checked against the rig), its props, plain data elsewhere. Nothing
## in it may name a file, call a script or carry a key that runs code
static func check_scene(sd: Dictionary, original: String) -> Dictionary:
	for k in sd.keys():
		if not k in SCENE_KEYS:
			return _bad("unknown key '%s' in the scene: a scene pack holds only a saved scene's own keys (cards, props, markers, timings...)" % k)
	var sc := _scan(sd, "", 0)
	if sc != "":
		return _bad(sc)
	if not (sd.get("cards") is Array) or (sd["cards"] as Array).is_empty() or (sd["cards"] as Array).size() > MAX_CARDS:
		return _bad("a scene needs a 'cards' list of 1 to %d cards" % MAX_CARDS)
	var cards: Array = sd["cards"]
	for i in cards.size():
		var c: Variant = cards[i]
		if not (c is Dictionary):
			return _bad("card %d is not a table" % (i + 1))
		var cd := c as Dictionary
		for k in cd.keys():
			if not k in CARD_KEYS:
				return _bad("unknown key '%s' in card %d: a card may hold only %s" % [k, i + 1, _join(CARD_KEYS)])
		var cname := String(cd.get("name", ""))
		if cname.length() > MAX_NAME:
			return _bad("card %d's name is longer than %d letters" % [i + 1, MAX_NAME])
		for k in ["hold", "arrive_s", "leave_s"]:
			if cd.has(k) and (not _is_num(cd[k]) or float(cd[k]) < 0.0 or float(cd[k]) > 600.0):
				return _bad("card %d '%s' must be a time from 0 to 600 s" % [i + 1, k])
		if cd.has("move") and (not _is_num(cd["move"]) or float(cd["move"]) < -1.0 or float(cd["move"]) > 600.0):
			return _bad("card %d 'move' must be -1 (auto) or a time from 0 to 600 s" % (i + 1))
		if not (cd.get("pose") is Dictionary):
			return _bad("card %d has no pose" % (i + 1))
		var pc := check_pose(cd["pose"] as Dictionary, true, "")
		if not pc["ok"]:
			return _bad("card %d ('%s'): %s" % [i + 1, cname, pc["why"]])
	if sd.has("fps") and (not _is_num(sd["fps"]) or int(sd["fps"]) < 1 or int(sd["fps"]) > 240):
		return _bad("'fps' must be from 1 to 240")
	if sd.has("length_s") and (not _is_num(sd["length_s"]) or float(sd["length_s"]) < 0.0 or float(sd["length_s"]) > 3600.0):
		return _bad("'length_s' must be from 0 to 3600 s")
	for k in ["natural", "on_floor", "floor_body", "free_limits", "pin", "spline", "moving_holds", "loop"]:
		if sd.has(k) and typeof(sd[k]) != TYPE_BOOL:
			return _bad("'%s' must be true or false" % k)
	var props: Variant = sd.get("props", [])
	if not (props is Array) or (props as Array).size() > MAX_PROPS:
		return _bad("'props' must be a list of at most %d props" % MAX_PROPS)
	for p in props:
		if not (p is Dictionary):
			return _bad("a prop is not a table")
		for k in (p as Dictionary).keys():
			if not k in PROP_KEYS:
				return _bad("unknown key '%s' in a prop: a prop may hold only %s" % [k, _join(PROP_KEYS)])
		if typeof((p as Dictionary).get("kind", "")) != TYPE_STRING or String((p as Dictionary).get("kind", "")).length() > 60:
			return _bad("a prop needs a 'kind' name of at most 60 letters")
		if not _nums((p as Dictionary).get("pos", null), 3) or not _is_num((p as Dictionary).get("yaw", 0.0)):
			return _bad("a prop needs 'pos' (three numbers) and 'yaw' (a number)")
		if (p as Dictionary).has("keys") and not ((p as Dictionary)["keys"] is Array):
			return _bad("a prop's 'keys' must be a list")
		for kk in (p as Dictionary).get("keys", []):
			if not (kk is Dictionary) or not (kk as Dictionary).keys().all(func(x): return x in PROP_KEY_KEYS):
				return _bad("a prop key has a field outside %s" % _join(PROP_KEY_KEYS))
	for k in sd.keys():
		if k in ["cards", "props"]:
			continue
		if not _plain(sd[k], 0):
			return _bad("'%s' must be plain data (numbers, text, lists, tables)" % k)
	var length := float(sd.get("length_s", 0.0))
	return {"ok": true, "why": "", "pack": {}, "path": "", "text": original, "joints": 0, "kept": 0, "dropped": [],
		"retargeted": false, "note": "", "cards": cards.size(), "props": (props as Array).size(), "length_s": length}


## a string-level scan of everything in a pack: banned keys, file paths, script text. Free-text keys may hold prose,
## but no path or script inside them either
static func _scan(v: Variant, key: String, depth: int) -> String:
	if depth > 14:
		return "the pack nests too deeply (over 14 levels)"
	match typeof(v):
		TYPE_DICTIONARY:
			for k in (v as Dictionary).keys():
				var ks := String(k)
				if ks in BANNED_KEYS:
					return "key '%s' is not accepted in a pack (no file paths, scripts or other scenes)" % ks
				var r := _scan((v as Dictionary)[k], ks, depth + 1)
				if r != "":
					return r
		TYPE_ARRAY:
			for x in v:
				var r := _scan(x, key, depth + 1)
				if r != "":
					return r
		TYPE_STRING:
			var s: String = v
			if s.contains("res://") or s.contains("user://") or s.begins_with("/") or s.begins_with("\\") \
					or (s.length() > 1 and s[1] == ":") or s.contains("../") or s.contains("..\\"):
				return "'%s' looks like a file path: a pack carries no file paths" % s.left(40)
			if s.contains("extends ") or s.contains("func ") or s.contains("class_name") or s.contains("OS.") or s.contains("func("):
				return "'%s' is script text: a pack carries no scripts" % s.left(40)
			if not key in FREE_TEXT:
				var low := s.to_lower()
				for e in FILE_EXT:
					if low.ends_with(e):
						return "'%s' names a file (%s): a pack carries no file names" % [s.left(40), e]
	return ""


static func _bone_name(s: String) -> bool:
	if s == "":
		return false
	for c in s:
		if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_"):
			return false
	return true


## plain data only: numbers, text, booleans, lists and tables of those (no objects, no code), nested at most 8 deep
static func _plain(v: Variant, depth: int) -> bool:
	if depth > 8:
		return false
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return true
		TYPE_INT, TYPE_FLOAT:
			return is_finite(float(v))
		TYPE_ARRAY:
			for x in v:
				if not _plain(x, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for k in v.keys():
				if typeof(k) != TYPE_STRING or not _plain(v[k], depth + 1):
					return false
			return true
	return false


static func _nums(v: Variant, n: int) -> bool:
	if not (v is Array) or (v as Array).size() != n:
		return false
	for x in v:
		if not _is_num(x):
			return false
	return true


## IMPORT: the payload written into <root>/imported as <name>.json (the file's bytes) and, for a pose, <name>.png.
## A name taken (in the imported folder or the pose folders) gets " (2)", " (3)"...: nothing is overwritten
static func import_pack(pack: Dictionary, root := "user://library") -> Dictionary:
	var dir := root.path_join(IMPORTED)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var base: String = pack["name"]
	var nm := base
	var k := 2
	while _taken(nm, root):
		nm = "%s (%d)" % [base, k]
		k += 1
	var json_path := dir.path_join(nm + ".json")
	var png_path := dir.path_join(nm + ".png")
	var fj := FileAccess.open(json_path, FileAccess.WRITE)
	if fj == null:
		return _bad("could not write %s (error %d)" % [json_path.get_file(), FileAccess.get_open_error()])
	fj.store_buffer((pack["pose_text"] as String).to_utf8_buffer())
	fj.close()
	var files := [json_path]
	if String(pack.get("kind", "pose")) == "pose":   # a pose's picture sits beside it (the pose library shows it)
		var fp := FileAccess.open(png_path, FileAccess.WRITE)
		if fp == null:
			return _bad("could not write %s (error %d)" % [png_path.get_file(), FileAccess.get_open_error()])
		fp.store_buffer(pack["thumb"])
		fp.close()
		files.append(png_path)
	return {"ok": true, "why": "", "pack": {}, "path": json_path, "name": nm, "renamed": nm != base,
		"files": files, "note": String(pack.get("note", ""))}


static func _taken(nm: String, root: String) -> bool:
	for d in [root.path_join(IMPORTED)] + LIB_DIRS:
		if FileAccess.file_exists(d.path_join(nm + ".json")):
			return true
	return false


## the import as ONE undo step: the files move to <root>/trash on Ctrl+Z and back on redo (never deleted)
static func lib_move(files: Array, to_trash: bool, root := "user://library") -> int:
	var trash := root.path_join("trash")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(trash))
	var moved := 0
	for p in files:
		var s := String(p)
		var src := s if to_trash else trash.path_join(s.get_file())
		var dst := trash.path_join(s.get_file()) if to_trash else s
		if not FileAccess.file_exists(src) or FileAccess.file_exists(dst):
			continue
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(dst)) == OK:
			moved += 1
	return moved


## the import, checked and written, with its ONE undo step and the status line. Returns the import's answer
static func commit(m: Node, pack: Dictionary) -> Dictionary:
	var r := import_pack(pack, m.library)
	if not r["ok"]:
		m._say("could not import '%s': %s" % [pack.get("name", "?"), r["why"]])
		return r
	m._push_undo_lib(r["files"])
	var what := "scene" if String(pack.get("kind", "pose")) == "scene" else "pose"
	var msg := "imported %s '%s' into Library > Imported" % [what, r["name"]]
	if r["renamed"]:
		msg += " as '%s': one of that name was already there, so nothing was overwritten" % r["name"]
	if pack.get("retargeted", false):
		msg += ". " + String(pack.get("note", ""))
	m._say(msg + ".  Ctrl+Z takes it back out")
	return r


# ------------------------------------------------------------------ the dialogs

## Import pack...: a file picked, read and checked, then the import dialog (picture, name, author, licence)
static func import_ask(m: Node, done := Callable()) -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.kinepack ; Kine packs (poses and scenes)"])
	fd.use_native_dialog = true
	fd.title = "Import a Kine pack (.kinepack)"
	fd.file_selected.connect(func(p):
		fd.queue_free()
		import_pick(m, p, done))
	fd.canceled.connect(fd.queue_free)
	m.add_child(fd)
	fd.popup_centered(Vector2i(800, 500))


## a picked file: refused with its reason and the next step, or shown in the import dialog
static func import_pick(m: Node, path: String, done := Callable()) -> void:
	var r := read(path)
	if not r["ok"]:
		m._say("could not import %s: %s. Ask for the pack again, or share it once more (pose library: right-click, Share as a pack...)" % [path.get_file(), r["why"]])
		return
	pack_dialog(m, r["pack"], func():
		commit(m, r["pack"])
		if done.is_valid():
			done.call())


## the import dialog: the picture, name, author, licence, what it holds, Import or Cancel
static func pack_dialog(m: Node, pack: Dictionary, on_ok: Callable) -> AcceptDialog:
	var dlg := AcceptDialog.new()
	dlg.name = "pack_import_dialog"
	dlg.title = "Import a Kine pack"
	dlg.ok_button_text = "Import to Library > Imported"
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	dlg.add_child(h)
	var img := Image.new()
	img.load_png_from_buffer(pack["thumb"])
	var tr := TextureRect.new()
	tr.name = "pack_thumb"
	tr.texture = ImageTexture.create_from_image(img)
	tr.custom_minimum_size = Vector2(150, 188)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(tr)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.custom_minimum_size = Vector2(330, 0)
	h.add_child(v)
	var lic: String = pack["licence"]
	var is_scene := String(pack.get("kind", "pose")) == "scene"
	var what := ("Scene: %d cards, %s s, %d props" % [int(pack["cards"]), "%.1f" % float(pack["length_s"]), int(pack["props"])]) if is_scene \
		else ("Joints: %d" % int(pack["joints"]))
	var lines := [
		["pack_name", "Name: %s" % pack["name"], 18],
		["pack_author", "Author: %s" % (pack["author"] if pack["author"] != "" else "(not given)"), 14],
		["pack_licence", "Licence: %s  (%s)" % [lic, LICENCE_SAY.get(lic, "")], 14],
		["pack_kind", "Kind: %s" % ("scene" if is_scene else "pose"), 13],
		["pack_skeleton", ("Skeleton: %s, matches this rig" % pack["skeleton"]) if String(pack.get("note", "")) == "" else "Skeleton: %s. %s" % [pack["skeleton"], pack["note"]], 13],
		["pack_joints", "%s.  Made with Kine %s" % [what, pack["app_version"]], 13],
	]
	for l in lines:
		var lb := Label.new()
		lb.name = l[0]
		lb.text = l[1]
		lb.custom_minimum_size = Vector2(330, 0)
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lb.add_theme_font_size_override("font_size", l[2])
		if l[0] == "pack_name":
			lb.add_theme_color_override("font_color", Tok.c("heading"))
		v.add_child(lb)
	dlg.confirmed.connect(func():
		dlg.queue_free()
		on_ok.call())
	dlg.canceled.connect(dlg.queue_free)
	m.add_child(dlg)
	dlg.min_size = Vector2i(640, 300)
	dlg.popup_centered(Vector2i(640, 300))
	return dlg


## Share as a pack...: name, author (optional) and licence typed or picked, then the save dialog
static func share_ask(m: Node, pose_path: String, thumb: PackedByteArray) -> void:
	_share_dialog(m, pose_path, "pose", thumb)


## Share scene as a pack...: the same form for a scene file (Scene files, from the scenes folder)
static func share_scene_ask(m: Node, scene_path: String) -> void:
	_share_dialog(m, scene_path, "scene", PackedByteArray())


static func _share_dialog(m: Node, path: String, kind: String, thumb: PackedByteArray) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.name = "pack_share_dialog"
	dlg.title = "Share as a %s pack" % kind
	dlg.ok_button_text = "Save pack..."
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	dlg.add_child(v)
	var nm := LineEdit.new()
	nm.name = "pack_name_edit"
	nm.text = path.get_file().get_basename().replace("_", " ")
	nm.placeholder_text = "name of the %s" % kind
	v.add_child(nm)
	var au := LineEdit.new()
	au.name = "pack_author_edit"
	au.placeholder_text = "your name (optional)"
	v.add_child(au)
	var opt := OptionButton.new()
	opt.name = "pack_licence_pick"
	for l in LICENCES:
		opt.add_item(l)
	v.add_child(opt)
	var say := Label.new()
	say.text = "CC0: anyone may use it for anything.  CC-BY: anyone may use it if they credit you.  All rights reserved: not for reuse without your permission."
	say.custom_minimum_size = Vector2(480, 0)
	say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	say.add_theme_font_size_override("font_size", 12)
	say.add_theme_color_override("font_color", Tok.dim(0.6))
	v.add_child(say)
	dlg.confirmed.connect(func():
		var n := nm.text
		var a := au.text
		var l: String = LICENCES[opt.selected]
		dlg.queue_free()
		_save_pack(m, path, kind, n, a, l, thumb))
	dlg.canceled.connect(dlg.queue_free)
	m.add_child(dlg)
	dlg.popup_centered(Vector2i(520, 300))


static func _save_pack(m: Node, path: String, kind: String, name: String, author: String, licence: String, thumb: PackedByteArray) -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.kinepack ; Kine pack"])
	fd.current_file = clean_name(name) + ".kinepack"
	fd.use_native_dialog = true
	fd.title = "Save the Kine pack"
	fd.file_selected.connect(func(p):
		fd.queue_free()
		var dest: String = p if p.ends_with(".kinepack") else p + ".kinepack"
		var r := share_file(kind, path, dest, name, author, licence, thumb, "")
		if r["ok"]:
			m._say("shared %s '%s' as %s (licence %s). Send that file; Import pack... reads it" % [kind, clean_name(name), dest.get_file(), licence])
		else:
			m._say("not shared: %s. Try again, or pick another folder" % r["why"]))
	fd.canceled.connect(fd.queue_free)
	m.add_child(fd)
	fd.popup_centered(Vector2i(800, 500))
