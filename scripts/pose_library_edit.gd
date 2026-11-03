## pose_library_edit.gd - C02: the pose library's EDITS (complaints #491, #487, #500). Opt-in: nothing here runs until the user
## picks a menu item or turns on "Select several".
##   Update from current pose  the picked pose's file takes the body as it is now (same name, same place) and its thumbnail is
##                             remade; ONE undo step (Ctrl+Z puts the old file back)
##   Select several + Delete   click pictures to tick them, Delete moves all of them (and their pictures) to the library's
##                             trash as ONE undo step; Ctrl+Z brings every one back, Ctrl+Y deletes them again
##   Rename...                 the pose (and its picture) under a new name; a name in use is refused, nothing overwritten
## The bundled poses (res://poses) are read-only: every edit refuses them in words.
class_name PoseLibraryEdit
extends RefCounted


static func editable(path: String) -> bool:
	return not path.begins_with("res://poses")


## the body as it is now written over the picked pose. true = done
static func update(lib: PoseLibrary, path: String) -> bool:
	var m: Node = lib.m
	if not editable(path):
		m._say("'%s' is a bundled pose and cannot be changed: save the body as your own pose instead" % lib._nm(path))
		return false
	if not FileAccess.file_exists(path):
		return false
	var old := FileAccess.get_file_as_string(path)
	var d: Dictionary = m.B.to_dict()
	PoseIKFK.stamp(d, m.S, clampf(m.playhead, 0.0, m.S.length()))   # C13
	var prev: Variant = JSON.parse_string(old)
	if prev is Dictionary and (prev as Dictionary).has("note"):
		d["note"] = prev["note"]
	m._push_undo()
	var nu := JSON.stringify(d, " ")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		m._drop_undo()
		return false
	f.store_string(nu)
	f.close()
	m.undo[-1]["libedit"] = {"kind": "upd", "path": path, "old": old, "new": nu}
	lib.made.erase(path)
	if not lib._queue.has(path):
		lib._queue.append(path)
	lib._pump()
	m._say("pose '%s' now holds the body as it is. Ctrl+Z puts the old pose back" % lib._nm(path))
	return true


## the undo (back = true) and redo of a library edit, called by main._undo / _redo after the step is restored
static func step(info: Dictionary, back: bool, m: Node) -> void:
	if info["kind"] == "upd":
		var f := FileAccess.open(String(info["path"]), FileAccess.WRITE)
		if f != null:
			f.store_string(String(info["old"] if back else info["new"]))
			f.close()
	else:
		PosePack.lib_move(info["files"], not back, m.library)
	var lib: PoseLibrary = m.get_meta("pose_library") if m.has_meta("pose_library") else null
	if lib != null:
		if info["kind"] == "upd":
			lib.made.erase(info["path"])
		lib._sig = ""
		lib.refresh()


## the files one pose owns: its .json and its picture
static func files_of(path: String) -> Array:
	var out := [path]
	var png := PoseLibrary.thumb_path(path)
	if FileAccess.file_exists(png):
		out.append(png)
	return out


## delete the ticked poses as ONE undo step. Returns how many poses were deleted
static func delete_many(lib: PoseLibrary, paths: Array) -> int:
	var m: Node = lib.m
	var files := []
	var n := 0
	var skipped := 0
	for p in paths:
		if not editable(String(p)):
			skipped += 1
			continue
		files.append_array(files_of(String(p)))
		n += 1
	if n == 0:
		m._say("nothing deleted: %s" % ("the bundled poses are read-only" if skipped > 0 else "tick poses with Select several first"))
		return 0
	m._step_hint = "Delete %d pose%s from the library" % [n, "" if n == 1 else "s"]
	m._push_undo()
	m.undo[-1]["libedit"] = {"kind": "del", "files": files}
	PosePack.lib_move(files, true, m.library)
	for p in paths:
		lib.tex.erase(p)
		lib.made.erase(p)
	lib.multi.clear()
	lib._sig = ""
	lib.refresh()
	m._say("deleted %d pose%s%s. Ctrl+Z brings %s back" % [n, "" if n == 1 else "s", "" if skipped == 0 else " (%d bundled kept)" % skipped, "it" if n == 1 else "them all"])
	return n


## a safe file stem from what was typed
static func stem_of(m: Node, typed: String) -> String:
	var s := String(m.safe_file(typed)).strip_edges()
	return s.trim_suffix(".json")


## the pose under a new name (its picture follows). Returns the new path, "" when refused
static func rename(lib: PoseLibrary, path: String, typed: String) -> String:
	var m: Node = lib.m
	if not editable(path):
		m._say("'%s' is a bundled pose and cannot be renamed" % lib._nm(path))
		return ""
	var stem := stem_of(m, typed)
	if stem == "" or stem.contains("/"):
		m._say("type a name for the pose first")
		return ""
	var dst := path.get_base_dir().path_join(stem + ".json")
	if dst == path:
		return path
	if FileAccess.file_exists(dst):
		m._say("a pose called '%s' is already there: pick another name, nothing was overwritten" % stem)
		return ""
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(dst)) != OK:
		m._say("could not rename the pose file")
		return ""
	var png := PoseLibrary.thumb_path(path)
	if FileAccess.file_exists(png):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(png), ProjectSettings.globalize_path(PoseLibrary.thumb_path(dst)))
	if lib.tex.has(path):
		lib.tex[dst] = lib.tex[path]
		lib.tex.erase(path)
	lib.made.erase(path)
	lib.picked = dst
	lib._sig = ""
	lib.refresh()
	m._say("renamed '%s' to '%s'" % [lib._nm(path), stem.replace("_", " ")])
	return dst


## the Rename dialog on the library
static func rename_ask(lib: PoseLibrary, path: String) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Rename the pose"
	dlg.ok_button_text = "Rename"
	var le := LineEdit.new()
	le.name = "rename_edit"
	le.text = lib._nm(path)
	le.custom_minimum_size = Vector2(280, 0)
	dlg.add_child(le)
	dlg.register_text_enter(le)
	dlg.confirmed.connect(func():
		rename(lib, path, le.text)
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	lib.add_child(dlg)
	dlg.popup_centered()
	le.grab_focus()
	le.select_all()
