## BATCH DIALOG (ROADMAP 80): the Batch... button of the Export dialog. Tick scenes from scenes/, pick one format and one folder,
## Export batch: each scene is exported in turn (scripts/batch_export.gd), a progress line before each, and a summary at the end
## (n done, failures named with a next step). It reads the scene files only; the open scene is never touched.
class_name BatchDialog
extends RefCounted

var host: Node          # main.gd (the dialog's parent, and the tree the progress waits on)
var dlg: AcceptDialog
var picks: Array = []   # [CheckBox, scene path]
var ui_format: OptionButton
var ui_dir: LineEdit
var ui_run: Button
var ui_status: Label
var ui_summary: Label
var running := false


func _init(host_: Node) -> void:
	host = host_


## the scenes the batch lists: scenes/*.json (the files the app opens; _archive and _wip are not listed)
static func scene_paths() -> Array:
	var out := []
	var d := DirAccess.open("res://scenes")
	if d == null:
		return out
	var files := Array(d.get_files())
	files.sort()
	for f in files:
		if String(f).ends_with(".json"):
			out.append("res://scenes/" + String(f))
	return out


func _build() -> void:
	dlg = AcceptDialog.new()
	dlg.name = "batch_dialog"
	dlg.title = "Batch export"
	dlg.ok_button_text = "Close"
	dlg.min_size = Vector2i(640, 0)
	dlg.exclusive = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	var lp := Label.new()
	lp.text = "Scenes in scenes/: tick the ones to export. Each goes to its own file; the open scene is not changed."
	lp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lp.custom_minimum_size = Vector2(600, 0)
	v.add_child(lp)
	var sel := HBoxContainer.new()
	var b_all := Button.new()
	b_all.name = "batch_select_all"
	b_all.text = "Select all"
	b_all.pressed.connect(_set_all.bind(true))
	sel.add_child(b_all)
	var b_none := Button.new()
	b_none.name = "batch_select_none"
	b_none.text = "Select none"
	b_none.pressed.connect(_set_all.bind(false))
	sel.add_child(b_none)
	v.add_child(sel)
	var sc := ScrollContainer.new()
	sc.name = "batch_list"
	sc.custom_minimum_size = Vector2(600, 240)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for p in scene_paths():
		var cb := CheckBox.new()
		cb.name = "pick_" + String(p).get_file().get_basename()
		cb.text = String(p).get_file()
		cb.toggled.connect(_on_pick_changed.unbind(1))
		list.add_child(cb)
		picks.append([cb, p])
	if picks.is_empty():
		var none := Label.new()
		none.text = "No scene files in scenes/."
		list.add_child(none)
	sc.add_child(list)
	v.add_child(sc)
	var rf := HBoxContainer.new()
	var lf := Label.new()
	lf.text = "Format"
	rf.add_child(lf)
	ui_format = OptionButton.new()
	ui_format.name = "opt_batch_format"
	ui_format.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for f in BatchExport.formats():
		ui_format.add_item(String((f as Dictionary)["name"]))
	rf.add_child(ui_format)
	v.add_child(rf)
	var rd := HBoxContainer.new()
	var ld := Label.new()
	ld.text = "Folder"
	rd.add_child(ld)
	ui_dir = LineEdit.new()
	ui_dir.name = "batch_folder"
	ui_dir.text = BatchExport.DEFAULT_DIR
	ui_dir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui_dir.tooltip_text = "res://scenes/_wip/<name>, user://<name> or a full path outside the project. Never scenes/ itself."
	ui_dir.text_changed.connect(_on_pick_changed.unbind(1))   # a refused folder fixed by typing: the old refusal goes too
	rd.add_child(ui_dir)
	v.add_child(rd)
	ui_run = Button.new()
	ui_run.name = "batch_run"
	ui_run.text = "Export batch"
	ui_run.pressed.connect(_on_run)
	v.add_child(ui_run)
	ui_status = Label.new()
	ui_status.name = "batch_status"
	ui_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui_status.custom_minimum_size = Vector2(600, 0)
	ui_status.text = "Tick the scenes, pick the format and folder, then Export batch."
	v.add_child(ui_status)
	ui_summary = Label.new()
	ui_summary.name = "batch_summary"
	ui_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui_summary.custom_minimum_size = Vector2(600, 0)
	v.add_child(ui_summary)
	dlg.add_child(v)
	host.add_child(dlg)


func open() -> void:
	if dlg == null:
		_build()
	dlg.popup_centered()


## Select all / Select none: tick or clear every scene, then the same stale-line reset as a single tick
func _set_all(on: bool) -> void:
	for pk in picks:
		(pk[0] as CheckBox).set_pressed_no_signal(on)
	_on_pick_changed()


## any change of the selection drops the old line (a refusal such as "NOT NOW: tick at least one scene" is no longer true)
func _on_pick_changed() -> void:
	if ui_status == null or running:
		return
	ui_status.text = "%d of %d scenes ticked. Pick the format and folder, then Export batch." % [_picked().size(), picks.size()]


func _picked() -> Array:
	var out := []
	for pk in picks:
		if (pk[0] as CheckBox).button_pressed:
			out.append(pk[1])
	return out


func _fmt() -> String:
	return String((BatchExport.formats()[maxi(ui_format.selected, 0)] as Dictionary)["id"])


## the batch: one scene after another, a progress line before each (the window repaints between them), then the summary
func _on_run() -> void:
	if running:
		return
	var scenes := _picked()
	if scenes.is_empty():
		ui_status.text = "NOT NOW: tick at least one scene in the list first"
		return
	var bad := BatchExport.check_dir(ui_dir.text)
	if bad != "":
		ui_status.text = bad
		return
	running = true
	ui_run.disabled = true
	ui_summary.text = ""
	var n := scenes.size()
	var res := {"done": 0, "files": [], "failed": [], "lines": []}
	var dir := ui_dir.text
	var taken := {}
	var fmt := _fmt()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir.strip_edges().replace("\\", "/").trim_suffix("/")))
	for i in n:
		ui_status.text = "exporting %d of %d: %s ..." % [i + 1, n, String(scenes[i]).get_file()]
		await host.get_tree().process_frame
		var r := BatchExport.export_one(String(scenes[i]), fmt, dir, taken)
		if r["ok"]:
			(res["files"] as Array).append(r["file"])
		else:
			(res["failed"] as Array).append(r)
		ui_status.text = "%d of %d: %s" % [i + 1, n, String(r["msg"])]
	var done := (res["files"] as Array).size()
	ui_summary.text = "\n".join(BatchExport.summary_lines(done, res["failed"]))
	ui_status.text = "Batch finished: %d of %d written to %s" % [done, n, dir]
	running = false
	ui_run.disabled = false
