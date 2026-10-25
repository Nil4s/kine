## REVIEW WITH FRAME COMMENTS (ROADMAP 29; scripts/review.gd). Checked by numbers: the review page is written to a user://
## path, is one valid HTML file with one JPEG per playblast frame and no external URL (no "http" anywhere); a second page
## for the same scene is <name>_2.html, never an overwrite; a comments JSON with 3 comments imports as 3 notes at their
## frames (one undo step, a second import adds nothing new); clicking a note's mark on the timeline moves the playhead to
## its frame; notes survive a save and a reload; a scene without notes saves with no "notes" key (old scenes unchanged).
## Writes only under user:// (never scenes/, poses/, data/).
## godot --headless --path . -s tests/review_test.gd     (ROADMAP 29: review:w)
extends SceneTree

var fails := 0
var m: Node
var n_ok := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	n_ok += 1 if c else 0
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle(2)
	var S: Scene = m.S
	var fps: int = S.fps
	var tmp := "user://review_test"
	var abs_tmp := ProjectSettings.globalize_path(tmp)
	DirAccess.make_dir_recursive_absolute(abs_tmp)
	for f in DirAccess.get_files_at(tmp):   # this test's own folder only: pages of an earlier run would move the _2 names
		DirAccess.remove_absolute(abs_tmp + "/" + f)

	# 1 the page: a 1 s preview range, so the frame count is known; one JPEG per frame, one file, no external URL
	m.pv_in = 0.0
	m.pv_out = 1.0
	var n := PlayblastExport.frame_count(0.0, 1.0, fps)
	var frames_before := DirAccess.get_directories_at("user://review_frames")
	var page: String = await m._export_review(tmp)
	ok(page != "" and FileAccess.file_exists(page), "1 the review page is written: %s" % page)
	var txt := FileAccess.get_file_as_string(page)
	var jpgs := txt.count("data:image/jpeg;base64,")
	ok(jpgs == n, "2 the page holds %d frames (one JPEG per playblast frame, %d expected)" % [jpgs, n])
	ok(txt.begins_with("<!doctype html>") and txt.count("<html") == 1 and txt.count("</html>") == 1 and txt.count("<script>") == 1 and txt.count("</script>") == 1,
		"3 valid single document: doctype, one html, one script block")
	# the JPEG frames are base64: "http" can occur in them by chance (any 4 letters do), so the URL check strips the
	# data: payloads first (a new render of the frames made "HttP" appear in one; the page text has none)
	var b64 := RegEx.create_from_string("base64,[A-Za-z0-9+/=]*")
	var txt_nob64 := b64.sub(txt, "base64,", true)
	ok(not txt_nob64.to_lower().contains("http") and not txt.contains("<script src") and not txt.contains("<link") and not txt.contains("@import"),
		"4 no external URL or script or stylesheet (grep http outside the image data: %s)" % txt_nob64.to_lower().contains("http"))
	ok(page.get_file().begins_with(S.name) and page.get_file().ends_with(".html") and page.begins_with(tmp),
		"5 named for the scene, under the root: %s" % page.get_file())
	var left := []
	for d in DirAccess.get_directories_at("user://review_frames"):
		if not frames_before.has(d):
			left.append(d)
	ok(left.is_empty(), "6 this export's playblast folder was removed after the page (left: %s)" % [left])

	# 2 a second page for the same scene and day never overwrites: _2
	var page2: String = await m._export_review(tmp)
	ok(page2 != page and page2.ends_with("_2.html") and FileAccess.file_exists(page), "7 a second page is _2, the first kept: %s" % page2.get_file())

	# 3 comments JSON: 3 comments import as 3 notes at their frames, one undo step, a second import adds none
	m.undo.clear()
	var frames := [5, 12, 20]
	var cj := {"format": "poser-review-comments", "version": 1, "scene": S.name, "fps": fps,
		"comments": [{"frame": 12, "text": "wrist too late"}, {"frame": 5, "text": "  a hitch here  "}, {"frame": 20, "text": "hold longer"}]}
	var cpath := tmp + "/comments.json"
	var cf := FileAccess.open(cpath, FileAccess.WRITE)
	cf.store_string(JSON.stringify(cj, "\t"))
	cf.close()
	var added: int = m._review_import(cpath)
	var got: Array = S.notes
	ok(added == 3 and got.size() == 3, "8 3 comments import as 3 notes (%d added, %d held)" % [added, got.size()])
	ok(got.size() == 3 and int(got[0]["frame"]) == 5 and int(got[1]["frame"]) == 12 and int(got[2]["frame"]) == 20 and got[0]["text"] == "a hitch here",
		"9 at the right frames 5, 12, 20 (text trimmed, by frame): %s" % [got])
	ok(m.undo.size() == 1, "10 the import is one undo step (%d)" % m.undo.size())
	m._undo()
	ok(S.notes.is_empty(), "11 Ctrl+Z takes the notes back")
	m._review_import(cpath)
	ok(S.notes.size() == 3 and m._review_import(cpath) == 0 and S.notes.size() == 3, "12 imported again; importing the same file once more adds nothing")

	# 4 the timeline: the note's mark on the ruler, a click moves the playhead to its frame
	var tl = m.ui_timeline
	m.playhead = 0.0
	var t12 := Review.time_of(12, fps)
	var p := Vector2(tl.x_of(t12), 3.0)
	var hit_t: float = tl.note_t_at(p)
	ok(absf(hit_t - t12) < 1e-4, "14 the mark for frame 12 is found on the ruler (%.4f, want %.4f)" % [hit_t, t12])
	ok(tl.note_t_at(Vector2(tl.x_of(Review.time_of(13, fps)) + 400.0, 3.0)) < 0.0 and tl.note_t_at(p + Vector2(0, 40)) < 0.0,
		"15 away from a mark, or below the ruler, there is none")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = p
	tl._gui_input(ev)
	await idle(2)
	ok(absf(m.playhead - t12) < 1e-3, "16 a click on the mark moves the playhead to frame 12: %.4f s" % m.playhead)

	# 5 save and reload: the notes come back; a scene without notes writes no key
	var d1: Dictionary = S.to_dict(m.B, false)
	ok(d1.has("notes") and d1["notes"].size() == 3 and int(d1["notes"][0]["frame"]) == 5, "17 the file holds the 3 notes")
	var S2 := Scene.new()
	S2.from_dict(JSON.parse_string(JSON.stringify(d1)))
	ok(JSON.stringify(S2.notes) == JSON.stringify(S.notes), "18 the notes survive a save and a reload")
	var m_mir := Scene.mirror_file(d1, m.B)
	ok(m_mir.has("notes") and JSON.stringify(m_mir["notes"]) == JSON.stringify(d1["notes"]), "19 mirror keeps the notes (free: frames and text)")

	# 6 old scenes: no notes, no key, and a save-load-save is a fixed point
	var old_ok := true
	var names := ["res://scenes/combo3.json", "res://scenes/bo_sweep.json", "res://scenes/axe_strike_pose.json"]
	for path in names:
		if not FileAccess.file_exists(path):
			continue
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		if raw.has("notes"):
			old_ok = false
		m._load_scene(path)
		await idle(1)
		var a := JSON.stringify(m.S.to_dict(m.B, false))
		if m.S.notes.size() != 0 or a.contains("\"notes\""):
			old_ok = false
		var S3 := Scene.new()
		S3.from_dict(JSON.parse_string(a))
		if JSON.stringify(S3.to_dict(m.B, false)) != a:
			old_ok = false
	ok(old_ok, "20 old scenes load with no notes, and save bit-identical again (%d files)" % names.size())

	m._load_scene("res://scenes/combo3.json")
	await idle(1)
	print("REVIEW TEST %s %d  (%d ok)" % ["PASS" if fails == 0 else "FAIL", fails, n_ok])
	TestFiles.cleanup()
	quit(fails)
