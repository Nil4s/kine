class_name BgSave
extends Node
## L124 ROADMAP_400 P15 Large-file safety: a save of a big scene is serialised and written on a WorkerThreadPool task, so
## the UI never waits for the disk. The caller's dict is snapshotted on the main thread (duplicate(true)); the worker does
## JSON.stringify(snap, " ") (the same text the old _write made), writes <file>.tmp and renames it over the target, so a
## failed write leaves the old file as it was. Requests while a write runs are queued per path (latest wins) and run one at
## a time. wait_all() blocks until everything is on disk (the app calls it before quitting). A chip shows the state.

signal finished(path: String, ok: bool, err: String)

## a scene whose estimated JSON is smaller than this many bytes is still written at once on the main thread (it costs less
## than a frame, and callers that read the file right after the save keep working)
const THRESHOLD := 100000
static var inject_fail := false   # tests: the worker fails half way through the temp file, as a full disk would

var last_ok := true
var last_error := ""
var max_active := 0
var writes := 0
var chip: Label
var _task := -1
var _active := {}   # {path, res, cbs}
var _pending := {}  # path -> {snap, cbs}   (insertion order = start order)
var _chip_until := 0.0


static func is_big(d: Dictionary) -> bool:
	return int((d.get("cards", []) as Array).size()) * 1500 + int((d.get("props", []) as Array).size()) * 400 \
		+ int((d.get("bad_frames", []) as Array).size()) * 12 > THRESHOLD


func _ready() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 90
	add_child(cl)
	chip = Label.new()
	chip.name = "BgSaveChip"
	chip.visible = false
	chip.anchor_left = 1.0
	chip.anchor_right = 1.0
	chip.offset_left = -260
	chip.offset_right = -12
	chip.offset_top = 8
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	chip.add_theme_font_size_override("font_size", 14)
	cl.add_child(chip)


func chip_text() -> String:
	return chip.text if chip != null else ""


func busy() -> bool:
	return _task >= 0 or not _pending.is_empty()


func reset_stats() -> void:
	max_active = 0
	writes = 0


func request(path: String, d: Dictionary, on_done := Callable()) -> void:
	var snap := d.duplicate(true)   # the main-thread part: later edits to d or the scene cannot reach the file
	var cbs := []
	if on_done.is_valid():
		cbs.append(on_done)
	if _pending.has(path):
		cbs = (_pending[path]["cbs"] as Array) + cbs   # latest wins; every caller still hears the result
	_pending[path] = {"snap": snap, "cbs": cbs}
	_say("saving %s ..." % path.get_file())
	_start_next()


func _start_next() -> void:
	if _task >= 0 or _pending.is_empty():
		return
	var path: String = _pending.keys()[0]
	var job: Dictionary = _pending[path]
	_pending.erase(path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var res := {"done": false, "ok": false, "err": ""}
	_active = {"path": path, "res": res, "cbs": job["cbs"]}
	writes += 1
	max_active = maxi(max_active, 1)
	_task = WorkerThreadPool.add_task(_work.bind(ProjectSettings.globalize_path(path), job["snap"], res), false, "bg save")


static func _work(path: String, snap: Dictionary, res: Dictionary) -> void:
	var text := JSON.stringify(snap, " ")
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		res["err"] = "cannot create %s (error %d)" % [tmp.get_file(), FileAccess.get_open_error()]
		res["done"] = true
		return
	if inject_fail:
		f.store_string(text.substr(0, text.length() / 2))
		f.close()
		DirAccess.remove_absolute(tmp)
		res["err"] = "injected write failure (disk full)"
		res["done"] = true
		return
	f.store_string(text)
	var werr := f.get_error()
	f.close()
	if werr != OK:
		DirAccess.remove_absolute(tmp)
		res["err"] = "write failed (error %d)" % werr
		res["done"] = true
		return
	var r := DirAccess.rename_absolute(tmp, path)
	if r != OK:
		DirAccess.remove_absolute(tmp)
		res["err"] = "could not replace %s (error %d)" % [path.get_file(), r]
		res["done"] = true
		return
	res["ok"] = true
	res["done"] = true


func _process(_dt: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		_finish()
	if chip != null and chip.visible and not busy() and Time.get_ticks_msec() / 1000.0 > _chip_until and last_ok:
		chip.visible = false


func _finish() -> void:
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	var res: Dictionary = _active["res"]
	var path: String = _active["path"]
	var cbs: Array = _active["cbs"]
	_active = {}
	last_ok = bool(res["ok"])
	last_error = String(res["err"])
	if last_ok:
		if _pending.is_empty():
			_say("saved %s" % path.get_file())
			_chip_until = Time.get_ticks_msec() / 1000.0 + 3.0
	else:
		_say("not saved, error: %s (the old file is untouched)" % last_error)
	for cb in cbs:
		if (cb as Callable).is_valid():
			(cb as Callable).call(last_ok, last_error)
	finished.emit(path, last_ok, last_error)
	_start_next()


## blocks until every queued write is on disk (quitting)
func wait_all() -> void:
	while busy():
		if _task >= 0:
			WorkerThreadPool.wait_for_task_completion(_task)
			_finish()
		else:
			_start_next()


func _say(t: String) -> void:
	if chip == null:
		return
	chip.text = t
	chip.visible = true
	chip.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4) if t.begins_with("not saved") else Color(0.85, 0.95, 0.85))
