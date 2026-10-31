class_name AppFeedback
extends RefCounted
## P190 FEEDBACK (Friday plan 190): "Send feedback" (the Help panel, and the palette: Help: send feedback) opens a small window.
## Send appends ONE JSON line to user://feedback/feedback.jsonl on this computer. Nothing is sent anywhere: no network code here.
## Fields: time, version (project.godot config/version), page, mode (Easy / Expert), part ({name, steps} or null when no part
## is open), text, screenshot (the file name of user://feedback/<time>.png when the box is ticked, else null).
## The PNG is the app's view with this window hidden. Test: tests/p190feedback_test.gd (log_dir points it at the test's own folder).

const PROMPT := "What went wrong or what do you wish it did?"
const DONE := "Saved on this computer. Thank you."
const LOG_NAME := "feedback.jsonl"

var m: Node                        # main
var log_dir := "user://feedback"   # the log and the PNGs (tests point it at their own user:// folder)
var win: PanelContainer
var box: TextEdit
var shot_cb: CheckBox
var send_btn: Button
var note: Label


func _init(main: Node) -> void:
	m = main
	win = PanelContainer.new()
	win.name = "feedback_panel"
	win.visible = false
	win.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	win.offset_left = -300
	win.offset_right = 300
	win.offset_top = -190
	win.offset_bottom = 190
	m.ui_root.add_child(win)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	win.add_child(vb)
	vb.add_child(m._label("FEEDBACK", 22, "heading"))
	vb.add_child(m._label(PROMPT, 16, "text", true))
	box = TextEdit.new()
	box.name = "feedback_text"
	box.placeholder_text = PROMPT
	box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.custom_minimum_size = Vector2(560, 150)
	box.text_changed.connect(_changed)
	vb.add_child(box)
	shot_cb = CheckBox.new()
	shot_cb.name = "feedback_shot"
	shot_cb.text = "attach a screenshot"
	shot_cb.button_pressed = true
	vb.add_child(shot_cb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	send_btn = m._button("Send", _send, "saves your words (and the picture) on this computer; nothing is sent")
	send_btn.name = "feedback_send"
	send_btn.disabled = true
	row.add_child(send_btn)
	var close_btn: Button = m._button("Close", func(): win.visible = false)
	close_btn.name = "feedback_close"
	row.add_child(close_btn)
	note = m._label("", 16, "text", true)
	note.name = "feedback_note"
	vb.add_child(note)


func show_window() -> void:
	note.text = ""
	win.visible = true
	box.grab_focus()


func _changed() -> void:
	send_btn.disabled = box.text.strip_edges() == ""


## a file name in the log folder that is not taken yet: stem.ext, then stem_2.ext, ...
func _free_name(stem: String, ext: String) -> String:
	var n := stem + ext
	var k := 2
	while FileAccess.file_exists(log_dir.path_join(n)):
		n = "%s_%d%s" % [stem, k, ext]
		k += 1
	return n


func _send() -> void:
	var text := box.text.strip_edges()
	if text == "":
		return
	var now := Time.get_datetime_string_from_system()   # 2026-10-31T14:02:11
	DirAccess.make_dir_recursive_absolute(log_dir)
	var shot = null
	if shot_cb.button_pressed:
		win.visible = false
		await RenderingServer.frame_post_draw   # the app's view without this window
		var img := m.get_viewport().get_texture().get_image()
		win.visible = true
		var png := _free_name(now.replace(":", "-"), ".png")
		if img != null and img.save_png(log_dir.path_join(png)) == OK:
			shot = png
	var part = null
	var rec_part: Dictionary = m.S.part
	if not rec_part.is_empty():
		part = {"name": String(rec_part.get("name", "")), "steps": (rec_part.get("features", []) as Array).size()}
	var line := {"time": now, "version": str(ProjectSettings.get_setting("application/config/version", "")),
		"page": String(m.cur_page), "mode": "Easy" if m.easy.on else "Expert", "part": part, "text": text, "screenshot": shot}
	var path: String = log_dir.path_join(LOG_NAME)
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f == null:
		note.text = "Could not save (%s). Your words are still in the box." % error_string(FileAccess.get_open_error())
		return
	f.seek_end()
	f.store_line(JSON.stringify(line))
	f.close()
	box.text = ""
	_changed()
	note.text = DONE
