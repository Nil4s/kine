class_name PageSpaces
extends RefCounted
## P07 WORKSPACES PER PAGE. leave(wl, page) remembers the page panel layout (docks, open flags, splits, rail, float rects) from the
## working layout of scripts/work_layouts.gd; enter(wl, page) puts it back, so each page comes back as it was left, whatever
## happened to the working layout in between (another page, a reset, a loaded layout). A page never left is not touched.
## File: {"schema": 1, "pages": {page: page layout}} (user://kine_page_spaces.json). Tests: tests/pagehot_test.gd.

const SCHEMA := 1

var path := "user://kine_page_spaces.json"
var pages := {}   # page id -> the page layout (WorkLayouts shape)


func _init(p := "user://kine_page_spaces.json") -> void:
	path = p
	load_file()


func leave(wl: WorkLayouts, page: String) -> void:
	if wl.cur["pages"].has(page):
		pages[page] = (wl.cur["pages"][page] as Dictionary).duplicate(true)
		save_file()


## true when a remembered layout was put back
func enter(wl: WorkLayouts, page: String) -> bool:
	if not pages.has(page) or not wl.cur["pages"].has(page):
		return false
	var probe := wl.cur.duplicate(true)
	probe["pages"][page] = (pages[page] as Dictionary).duplicate(true)
	wl.cur = WorkLayouts.sanitize(probe)
	return true


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
	var f0 := WorkLayouts.factory()
	for pg in j.data["pages"]:
		if f0["pages"].has(pg) and j.data["pages"][pg] is Dictionary:
			var probe := f0.duplicate(true)
			probe["pages"][pg] = j.data["pages"][pg]
			pages[String(pg)] = WorkLayouts.sanitize(probe)["pages"][pg]
