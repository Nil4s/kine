## MACROS (ROADMAP 81): a macro is a named list of palette steps, recorded as the user runs palette commands
## (main._macro_note). This file is the storage only: user://macros.json (main.macros_file; a test uses its own path).
## Playing one is main._macro_play: its steps run in order and share ONE undo step.
## A step: {"name": the palette row's name, "words": the typed text of a "Pose: ..." row ("" for a command),
## "part": the part picked when it ran ("" = none), "needs_part": true when it is an edit and a part was picked}
class_name Macros
extends RefCounted

const VERSION := 1
const ROW := "Macro: "   # the S box shows a macro as "Macro: <name>"


static func load_file(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(d) != TYPE_DICTIONARY or typeof(d.get("macros")) != TYPE_ARRAY:
		return []
	return d["macros"]


static func save_file(path: String, list: Array) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"v": VERSION, "macros": list}, "\t"))
	return true


static func find(list: Array, name: String) -> Dictionary:
	for mac in list:
		if mac["name"] == name:
			return mac
	return {}


## the next free "Macro N" name
static func new_name(list: Array) -> String:
	var n := list.size() + 1
	while not find(list, "Macro %d" % n).is_empty():
		n += 1
	return "Macro %d" % n
