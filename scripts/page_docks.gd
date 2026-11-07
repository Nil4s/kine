class_name PageDocks
extends RefCounted
## P07 (L123) A PANEL LAYOUT PER APP PAGE (BODY POSE ANIMATE STAGE CHECK DELIVER MODEL SCULPT SURFACE). What a page really has:
##   the side panels: inspector / browser width ("w": left, right), the folds ("fold": left, right, bottom); the six pages that show the sides;
##   floating panels: "win": id -> {on, x, y}; MODEL the Model checks, SCULPT the Brush presets, SURFACE the UV editor (visibility and, for the UV editor, where it was dragged).
## pages[page] = {"w"?, "fold"?, "win"?}; a key is there only once the user touched it (a page never touched follows the app's own defaults).
## File: {"schema": 1, "pages": {...}} (user://kine_page_docks.json). Tests: tests/pagespaces_test.gd.

const SCHEMA := 1
const W_MIN := {"left": 240.0, "right": 290.0}   # the panels cannot be narrower than the app's own widths (their content is that wide)
const W_MAX := 520.0

var path := "user://kine_page_docks.json"
var pages := {}


func _init(p := "user://kine_page_docks.json") -> void:
	path = p
	load_file()


static func clamp_w(which: String, v: float) -> float:
	return clampf(v, float(W_MIN[which]), W_MAX)


func entry(page: String) -> Dictionary:
	if not pages.has(page):
		pages[page] = {}
	return pages[page]


func forget(page: String) -> void:
	pages.erase(page)


func save_file() -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"schema": SCHEMA, "pages": pages}, "\t", true))
	f.close()
	return true


func load_file() -> void:
	pages = {}
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(txt) != OK or not (j.data is Dictionary) or int(j.data.get("schema", 0)) != SCHEMA or not (j.data.get("pages", null) is Dictionary):
		return
	for pg in j.data["pages"]:
		var s: Variant = j.data["pages"][pg]
		if not (s is Dictionary):
			continue
		var o := {}
		if s.get("w", null) is Dictionary:
			o["w"] = {"left": clamp_w("left", float(s["w"].get("left", 0))), "right": clamp_w("right", float(s["w"].get("right", 0)))}
		if s.get("fold", null) is Dictionary:
			o["fold"] = {"left": bool(s["fold"].get("left", false)), "right": bool(s["fold"].get("right", false)), "bottom": bool(s["fold"].get("bottom", false))}
		if s.get("win", null) is Dictionary:
			var w := {}
			for id in s["win"]:
				if s["win"][id] is Dictionary:
					w[String(id)] = {"on": bool(s["win"][id].get("on", false)), "x": float(s["win"][id].get("x", 0)), "y": float(s["win"][id].get("y", 0))}
			o["win"] = w
		pages[String(pg)] = o
