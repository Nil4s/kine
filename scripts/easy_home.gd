class_name EasyHome
extends Node
## EASY HOME (monkey brain easy): what a beginner sees in Easy mode when the scene is empty. A centred panel,
## "What should he do?", with eight picture cards and one text box ("or type it"). A card builds its clip (the
## templates/ files for walk, run, jump, punch, sit down, wave and the kick (roundhouse.json, baked); TextBlocking for typed words), one undo step, then it plays by itself.
## After that the panel is a strip with buttons: Again, Change it (the panel and its text box come back), and four big ones
## that tweak the clip just built (EasyTweak): Faster, Slower (its timing), Bigger, Smaller (its motion). Save video is on the Easy bar.
## Expert never shows it: it is a child of EasyMode and only Easy's bar shows it.
## A card the builders cannot make says so in one plain sentence and leaves the scene as it was.

const CARDS := [   # [the word on the card, what it builds (a templates/ name or the words TextBlocking reads), its icon]
	["Walk", "walk", "walk"],
	["Run", "run", "run"],
	["Jump", "jump", "jump"],
	["Punch", "punch", "punch"],
	["Kick", "roundhouse", "kick"],
	["Sit down", "sit_down", "sit_down"],
	["Wave", "wave", "wave"],
	["Fall", "fall", "fall"],
]
const HINT := "or type a move: 'jab then cross'"
## words Kine has no builder for. TextBlocking would read "down" as an overhead strike, so these are refused first
const NOT_YET := ["sit"]   # typed words Kine cannot build yet (sit down, wave and fall are templates now)

var m: Node                    # main (untyped: the same pattern as EasyMode)
var panel: PanelContainer      # the full panel: the picture cards, the text box, the message
var strip: PanelContainer      # the strip after a clip is built: Again, Change it, Save video
var _edit: LineEdit
var _msg: Label
var _close: Button
var _built := false            # a clip was built from here: the strip shows once the scene has cards
var _open := false             # Change it (or a failed build): the full panel, whatever the scene holds
var _t0 := -1                  # msec at the last click; -1 = nothing being timed
var last_ms := -1              # click -> the first frame the clip plays, msec (the test reads it; -1 = none yet)
var last_build_ms := -1        # the builder alone (the build of the last card or line), msec: reported, not hidden
var video_root := ""           # a TEST's folder (user://...) for Save video; "" = the user's Videos folder (Kine/)
var last_video := {}          # the last Easy save: the playblast's result ({dir, frames, mp4, ffmpeg}); {} = none, or refused
var _toast: PanelContainer
var _toast_text: Label
var _toast_file := ""         # what Show the file opens: the .mp4 (its folder is shown with it)
var _vid_busy := false        # COPY A VIDEO: an import from a video is running (the tracker, then the fit)
var _vid_before := ""         # the scene path when the copy began: a new path when it lands
var _vid_cancel := false      # the fit's own Cancel was pressed
var _vid_said := ""           # the say line's opening words for the landed clip ("Copied clip.mp4" / "Made \"swing...\"")
var _gen_on := false          # MAKE IT WITH AI VIDEO: main's gen_move (scripts/gen_move.gd) is making the clip
var _gen_words := ""          # the typed words Kine could not build: the button under the message makes them as a video
var _make_btn: Button
var _cancel_btn: Button
var _clip_word := "the move"   # the clip's name in the say line of a tweak ("the punch now takes 0.8 s")


func build(root: Control) -> void:
	panel = PanelContainer.new()
	panel.name = "easy_home"
	panel.visible = false
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)   # centred; grows both ways from the middle
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var st := StyleBoxFlat.new()
	st.bg_color = Tok.c("panel")
	st.set_corner_radius_all(10)
	st.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", st)
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var title := _label("What should he do?", 26, "text")
	title.name = "eh_title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var grid := GridContainer.new()
	grid.name = "eh_cards"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	for i in CARDS.size():
		grid.add_child(_card_button(i))
	_edit = LineEdit.new()
	_edit.name = "eh_text"
	_edit.placeholder_text = HINT
	_edit.custom_minimum_size = Vector2(560, 0)
	_edit.text_submitted.connect(func(t: String): _words(t))
	v.add_child(_edit)
	_msg = _label("", 15, "text")
	_msg.name = "eh_msg"
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.custom_minimum_size = Vector2(560, 0)
	v.add_child(_msg)
	_make_btn = Button.new()
	_make_btn.name = "eh_make_ai"
	_make_btn.text = "Make it with AI video (about 10 minutes)"   # measured: ~8.5 min to make a 5 s clip on this 8 GB card, ~1 min to read it (COMFY_E2E, 2026-10-24)
	_make_btn.focus_mode = Control.FOCUS_NONE
	_make_btn.tooltip_text = "make these words as a video on the local AI video maker, then it opens like a copied video"
	_make_btn.visible = false
	_make_btn.pressed.connect(make_ai)
	v.add_child(_make_btn)
	_cancel_btn = Button.new()
	_cancel_btn.name = "eh_gen_cancel"
	_cancel_btn.text = "Cancel"
	_cancel_btn.focus_mode = Control.FOCUS_NONE
	_cancel_btn.tooltip_text = "stop it; the scene stays exactly as it is"
	_cancel_btn.visible = false
	_cancel_btn.pressed.connect(cancel_run)
	v.add_child(_cancel_btn)
	_close = Button.new()
	_close.name = "eh_close"
	_close.text = "Close"
	_close.focus_mode = Control.FOCUS_NONE
	_close.tooltip_text = "back to the strip: the clip stays"
	_close.pressed.connect(func(): _open = false)
	v.add_child(_close)

	strip = PanelContainer.new()
	strip.name = "easy_home_strip"
	strip.visible = false
	strip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	strip.offset_top = 82.0   # under the Easy bar (main's TOP_H is 74)
	strip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	strip.add_theme_stylebox_override("panel", st)
	root.add_child(strip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	strip.add_child(row)
	row.add_child(_strip_button("eh_again", "Again", "play the clip from its start", _play, Vector2(150, 56), 22))   # one size for the six
	row.add_child(_strip_button("eh_change", "Change it", "type another move in the box", _change, Vector2(150, 56), 22))
	for t in [["eh_faster", "Faster", "the clip's timing x 0.8 (one undo step)", "faster"], ["eh_slower", "Slower", "the clip's timing x 1.25 (one undo step)", "slower"],
			["eh_bigger", "Bigger", "the motion 20 % further from the rest pose (one undo step)", "bigger"], ["eh_smaller", "Smaller", "the motion 20 % less from the rest pose (one undo step)", "smaller"]]:
		row.add_child(_strip_button(t[0], t[1], t[2], tweak.bind(t[3]), Vector2(150, 56), 22))
	# no Save video here: the Easy bar has it (two buttons with one label confused the monkey test's beginner)
	_toast = PanelContainer.new()
	_toast.name = "easy_toast"
	_toast.visible = false
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.offset_bottom = -40.0
	var tst := StyleBoxFlat.new()
	tst.bg_color = Tok.c("accent")
	tst.set_corner_radius_all(10)
	tst.set_content_margin_all(18)
	_toast.add_theme_stylebox_override("panel", tst)
	root.add_child(_toast)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 12)
	_toast.add_child(tv)
	_toast_text = _label("", 26, "on_accent")
	_toast_text.name = "eh_toast_text"
	tv.add_child(_toast_text)
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 10)
	tv.add_child(tr)
	tr.add_child(_toast_button("eh_toast_show", "Show the file", "open the folder with the video in it", func(): OS.shell_show_in_file_manager(_toast_file)))
	tr.add_child(_toast_button("eh_toast_ok", "Got it", "hide this message", func(): _toast.visible = false))


func _process(dt: float) -> void:
	if m == null or panel == null:
		return
	var on: bool = m.easy.on
	var empty: bool = m.S.cards.is_empty()
	var lib: bool = m.ui_library != null and m.ui_library.visible   # the open library sits where the panel's left half is: one at a time
	panel.visible = on and (empty or _open or _gen_on) and not (lib and not _gen_on)
	strip.visible = on and not (empty or _open or _gen_on) and _built
	if not on:
		_toast.visible = false
	_close.visible = not empty and not _gen_on
	_make_btn.visible = _gen_words != "" and not _gen_on
	_cancel_btn.visible = _gen_on or m._imp_busy()   # the generator, or the fit's own Cancel
	if _t0 >= 0 and m.playing and m.playhead > 0.0:   # the first frame in which the clip moves
		last_ms = Time.get_ticks_msec() - _t0
		_t0 = -1
	if _gen_on:
		_gen_tick(dt)
	if _vid_busy:
		_video_tick()


## what is on screen: "panel", "strip" or "hidden" (the test reads it)
func shown() -> String:
	if panel == null:
		return "hidden"
	return "panel" if panel.visible else ("strip" if strip.visible else "hidden")


## a card's click: build its clip, then play it
func card(i: int) -> void:
	_t0 = Time.get_ticks_msec()
	last_ms = -1
	_go(String(CARDS[i][1]), String(CARDS[i][0]))


## SAVE VIDEO (Easy's strip and the bar's Export video): the playblast (PNG frames, and an .mp4 when ffmpeg is found) in the
## user's Videos folder, Kine/ (video_folder). A toast names the file and offers Show the file. Expert's export is not changed.
func save_video() -> void:
	last_video = {}
	var r: Dictionary = await m._save_video_playblast(video_folder())   # piped to ffmpeg, with the progress line and Cancel
	last_video = r
	if r.is_empty():   # refused: the playblast's status line says why
		return
	if String(r["mp4"]) != "":
		_show_toast("Video saved: %s" % String(r["mp4"]).get_file(), String(r["mp4"]))
		m._say_plain("Video saved: %s" % String(r["mp4"]).get_file())   # the status line says it short (the playblast's own line is long)
	else:
		_show_toast("No video: ffmpeg was not found. The frames are saved.", String(r["dir"]))
		m._say_plain("No video: no ffmpeg found")


## where Easy's video goes: a test's folder if one is set, else Videos/Kine, else Documents/Kine
func video_folder() -> String:
	if video_root != "":
		return video_root
	for base in [OS.get_system_dir(OS.SYSTEM_DIR_MOVIES), OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)]:
		var dir := String(base).path_join("Kine")
		if String(base) != "" and (DirAccess.dir_exists_absolute(dir) or DirAccess.make_dir_recursive_absolute(dir) == OK):
			return dir
	return "user://Kine"


func _show_toast(text: String, file: String) -> void:
	_toast_text.text = text
	_toast_file = file
	_toast.visible = true


func _toast_button(nm: String, text: String, tip: String, f: Callable) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(200, 52)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(f)
	return b


## the text box: the same build as a card, named by what was typed
func _words(text: String) -> void:
	var t := text.strip_edges()
	if t == "":
		_fail("Type a move first, such as 'jab then cross' or 'roundhouse', or click a picture.")
		return
	_t0 = Time.get_ticks_msec()
	last_ms = -1
	_go(t, "Typed: " + t, true)


func _go(what: String, label: String, typed := false) -> void:
	if _gen_on:
		m._say_plain(GEN_BUSY)
		return
	var t := Time.get_ticks_msec()
	var err := _build(what, label)
	last_build_ms = Time.get_ticks_msec() - t
	if err != "":
		_gen_words = what if typed else ""   # a typed line Kine cannot build: the AI video button makes it
		_fail(err)
		return
	_built = true
	_open = false
	_gen_words = ""
	_msg.text = ""
	_clip_word = "the typed move" if typed else "the " + label.to_lower()
	m._layout_bottom()   # the bottom panel has its clip rows now: the free rect is the real one
	_play()
	m.easy.frame_clip_next()  # EASY CAMERA: framed in the free rect under the bar / strip, one frame AFTER the clip starts (the click-to-motion bar)


## COPY A VIDEO (Easy's More): a video of one person -> the Expert import (main._import_video: the tracker, then the fit: the
## same pipeline, not a second one). One undo step (the scene before the copy: main._import_land pushes it). The status line
## says the progress in one plain sentence; the import's own bar (with its Cancel: during the tracking it stops the tracker, during
## the fit the fit) is shown as it always is.
## The clip plays at once and the camera frames it, as a card does. A video with no person, or one that cannot be read, is
## one sentence saying why and what to try.
const VIDEO_TYPES := "*.mp4, *.mov, *.webm, *.avi, *.mkv ; videos"
const NO_PERSON := "No person found in the video. Try a clip where the whole body is visible."
const NO_READER := "The video reader would not start on this computer, so this video cannot be read."


## MAKE IT WITH AI VIDEO (the button under a typed line Kine cannot build): the words -> main's gen_move (the same local
## ComfyUI clip as Expert's "Video: make a move from words"), then the copy's landing (main._import_video: one undo step,
## the clip plays, the camera frames it). Cancel stops the generator and the scene stays as it was.
const GEN_NOT_RUNNING := "The AI video maker is not running on this computer, so this move can't be made. Try one of the cards."
const GEN_SHORT := "Say the move in a few more words, such as 'swings a sledgehammer down onto the ground'."
const GEN_BUSY := "A video is already being made or copied: wait for it, or press Cancel."


func make_ai() -> void:
	if _gen_words == "":
		return
	if _gen_on or _vid_busy or m._imp_busy() or m._video_pid >= 0 or m.gen_move.busy():
		m._say_plain(GEN_BUSY)
		return
	if _gen_words.length() < 4:
		_fail(GEN_SHORT)
		return
	m.gen_move.python = m.video_python
	if m.gen_move.start(_gen_words) != "":   # no Python / the maker's script did not start: the same plain sentence
		_fail(GEN_NOT_RUNNING)
		return
	_gen_on = true
	_open = true
	m.gen_easy = true   # main's _gen_poll stays out: this home polls the run, says it and lands it
	_msg.text = ""
	m._say_plain(_gen_line())


func _gen_line() -> String:
	var s := int(m.gen_move.t)
	return "Making the video… %d:%02d" % [int(s / 60.0), s % 60]


## every frame while the generator runs: the progress on the say line; when it is over, the clip lands like a copied video
func _gen_tick(dt: float) -> void:
	var r: String = m.gen_move.poll(dt)
	if r == "":
		m._say_plain(_gen_line())
		return
	_gen_on = false
	m.gen_easy = false
	if r != "done":
		_fail(GEN_NOT_RUNNING)
		return
	_vid_busy = true
	_vid_cancel = false
	_vid_before = String(m.scene_path)
	_vid_said = "Made \"%s\"" % _gen_words
	_t0 = -1
	m._land_undo = "Make it with AI video"
	m._say_plain("Reading the video: 0 %")
	m._import_video(m.gen_move.out)
	if m._video_pid < 0 and not m._imp_busy():
		_vid_busy = false
		m._land_undo = ""
		_fail(NO_READER)


## Cancel: the generator is stopped (its python process killed) and nothing is changed; during the fit the import's own Cancel
func cancel_run() -> void:
	if _gen_on:
		if m.gen_move.pid >= 0:
			OS.kill(m.gen_move.pid)
		Children.done(m.gen_move.pid)
		m.gen_move.pid = -1
		_gen_on = false
		m.gen_easy = false
		_t0 = -1
		m._say_plain("Stopped. Nothing was changed.")
		return
	if m._imp_busy():
		m._imp_cancel()


func copy_video() -> void:
	if _gen_on or _vid_busy or m._imp_busy() or m._video_pid >= 0:
		m._say("A video is already being copied: wait for it, or press Cancel on the bar")
		return
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray([VIDEO_TYPES])
	fd.use_native_dialog = true
	fd.title = "Copy a video of a person"
	fd.current_dir = String(OS.get_system_dir(OS.SYSTEM_DIR_MOVIES))
	fd.file_selected.connect(func(p: String): fd.queue_free(); copy_video_file(p))
	fd.canceled.connect(fd.queue_free)
	m.add_child(fd)
	fd.popup_centered(Vector2i(800, 500))


## the copy of one file (the dialog's pick; a test calls it with its own clip)
func copy_video_file(path: String) -> void:
	if _gen_on or _vid_busy or m._imp_busy() or m._video_pid >= 0:
		m._say("A video is already being copied: wait for it, or press Cancel on the bar")
		return
	if not FileAccess.file_exists(path):
		_fail("That video file could not be found. Pick it again with Copy a video.")
		return
	_vid_busy = true
	_vid_cancel = false
	_vid_before = String(m.scene_path)
	_vid_said = "Copied %s" % path.get_file()
	_t0 = -1
	m._land_undo = "Copy a video"
	m._import_video(path)
	if m._video_pid < 0 and not m._imp_busy():   # the tracker did not start: there is nothing to wait for
		_vid_busy = false
		m._land_undo = ""
		_fail(NO_READER)


## every frame while a copy runs: the say line shows the progress; when both steps are over, the result
func _video_tick() -> void:
	if m._video_pid >= 0:   # the tracker reads the video
		var f := _tracker_progress()
		m._say_plain("Reading the video: %d %%" % roundi(f * 100.0) if f >= 0.0 else "Reading the video...")
		return
	if m._imp_busy():   # the fit: the import's own bar and Cancel show it too
		if bool(m._imp.get("cancel", false)):
			_vid_cancel = true
		m._say_plain("Fitting the moves to the body: %d %%" % roundi(VideoIQ.progress * 100.0))
		return
	_vid_busy = false
	m._land_undo = ""
	if String(m.scene_path) != _vid_before and not m.S.cards.is_empty():
		_copied()
	elif m._video_cancelled:   # stopped while the tracker read the video: nothing landed
		m._say_plain("Stopped. Nothing was changed.")
	elif _vid_cancel:
		m._say_plain("Cancelled. The scene is as it was.")
	else:
		_fail(NO_PERSON)


## the tracker's fraction read (tools/see_video.py --progress), or -1 when none is written yet
func _tracker_progress() -> float:
	var pf := String(m._video_prog)
	if pf == "" or not FileAccess.file_exists(pf):
		return -1.0
	var t := FileAccess.get_file_as_string(pf).strip_edges()
	return t.to_float() if t.is_valid_float() else -1.0


## the copied clip: built and playing, framed like a card's (the same steps as _go)
func _copied() -> void:
	_built = true
	_open = false
	_gen_words = ""
	_msg.text = ""
	_clip_word = "the copied clip"
	m._layout_bottom()
	_play()
	m.easy.frame_clip_next()
	m._say_plain("%s: %d cards. Again plays it from the start; Undo takes it back." % [_vid_said, m.S.cards.size()])


## the clip for one card or one typed line: one undo step. "" = built; else the one sentence why not
func _build(what: String, label: String) -> String:
	var nm := what.strip_edges().to_lower()
	var d: Dictionary
	var path := ""
	if Templates.has_file(nm):   # the picker's templates and the baked kick (templates/roundhouse.json: instant)
		d = Templates.read(nm)
		if d.is_empty():
			return "The %s template file is missing: rebuild the templates (tools/make_templates.gd) and try again." % nm
		path = UserPaths.w(Templates.new_path(nm))
	else:
		var r := _words_dict(nm)
		if not r["ok"]:
			return String(r["error"])
		d = r["dict"]
		path = load("res://scripts/text_blocking.gd").unique_path(UserPaths.w("res://scenes/_wip"), load("res://scripts/text_blocking.gd").slug(nm))
	d["scene"] = path.get_file().get_basename()
	d["plan"] = "Easy home: %s" % label
	m._step_hint = label   # the undo step is named after the card (main's undo list shows it)
	m._push_undo()
	m.undo[-1]["swap"] = true   # the card makes a NEW Scene object: Ctrl+Z puts the empty one back whole (main._restore; path_walk_ui does the same)
	m._write(path, d)
	m._load_scene(path)
	m._rebuild_cards()
	m._refresh()
	return ""


## words -> one scene dict. "jab then cross" is two strikes (split on "then", "," and ";"); each strike is built by
## TextBlocking on a fresh body and the cards are joined in order. {ok, dict} or {ok: false, error}
func _words_dict(text: String) -> Dictionary:
	var parts: Array = []
	for p in text.replace(",", " then ").replace(";", " then ").split(" then ", false):
		var s := String(p).strip_edges()
		if s != "":
			parts.append(s)
	if parts.is_empty():
		return {"ok": false, "error": "Type a move first, such as 'jab then cross' or 'roundhouse'."}
	var out := {}
	for p in parts:
		for w in String(p).split(" ", false):
			if w in NOT_YET:
				return {"ok": false, "error": "Kine can't build '%s' yet: it knows strikes, walks, runs, jumps and punches so far." % p}
		var W := Body.new()   # a scratch body: TextBlocking poses it card by card (main's words box does the same)
		W.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		var r: Dictionary = load("res://scripts/text_blocking.gd").build(p, W)
		if not r["ok"]:
			if String(r["error"]).begins_with("no attack"):
				return {"ok": false, "error": "Kine can't build '%s' yet: it knows strikes, walks, runs, jumps and punches so far." % p}
			return {"ok": false, "error": "Kine can't build '%s': %s." % [p, String(r["error"])]}
		var d: Dictionary = (r["scene"] as Scene).to_dict(W)
		if out.is_empty():
			out = d
		else:
			(out["cards"] as Array).append_array(d["cards"])
	return {"ok": true, "dict": out, "strikes": parts.size()}


## play from the start: a playing clip is stopped first, so Again and a new build both start at 0
func _play() -> void:
	if m.playing:
		m._toggle_play()
	m.playhead = 0.0
	m._toggle_play()


## FASTER / SLOWER / BIGGER / SMALLER on the clip just built: one press = one undo step, the clip plays again from its start,
## the camera frames it, and the say line names what happened. A press at a limit changes nothing and says why.
func tweak(how: String) -> void:
	if _gen_on or _vid_busy or m._imp_busy():
		m._say_plain(GEN_BUSY)
		return
	var S: Scene = m.S
	if S.cards.size() < 2:
		m._say_plain("Nothing to change yet: build a move first.")
		return
	var before := S.length()
	var said := ""
	if how == "faster" or how == "slower":
		var k: float = EasyTweak.FASTER if how == "faster" else EasyTweak.SLOWER
		var stop := EasyTweak.timing_stop(S, k)
		if stop != "":
			m._say_plain(stop)
			return
		var err: String = m.retime(0, S.cards.size() - 1, k * 100.0)   # main.retime: one undo step, the holds and moves x k
		if err != "":
			m._say_plain(err)
			return
		said = "%s: %s now takes %.1f s." % [how.capitalize(), _clip_word, S.length()]
	else:
		var k: float = EasyTweak.BIGGER if how == "bigger" else EasyTweak.SMALLER
		var poses := EasyTweak.exaggerated(S, m.B, k)
		if poses.is_empty():
			m._say_plain("Nothing to make %s: the clip has no pose to move from." % ("bigger" if k > 1.0 else "smaller"))
			return
		m._push_undo()
		for i in poses:
			S.cards[i]["pose"] = poses[i]
		m._retimed()
		var pct := roundi(absf(k - 1.0) * 100.0)
		said = "%s: %s now moves %d %% %s." % [how.capitalize(), _clip_word, pct, "further" if k > 1.0 else "less"]
	m._say_plain(said)
	_play()
	m.easy.frame_clip_next()


func _change() -> void:
	_open = true
	_msg.text = ""
	_edit.grab_focus.call_deferred()


func _fail(sentence: String) -> void:
	_msg.text = sentence
	_msg.add_theme_color_override("font_color", Tok.c("warn"))
	_open = true   # the panel comes back with the sentence, even from the strip
	_t0 = -1
	m._say(sentence)


func _card_button(i: int) -> Button:
	var b := Button.new()
	b.name = "eh_card_%d" % i
	b.set_meta("label", CARDS[i][0])
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(150, 124)
	b.tooltip_text = "build %s and play it (one undo step)" % String(CARDS[i][0]).to_lower()
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var pic := TextureRect.new()
	pic.name = "icon"
	pic.texture = Icons.big(String(CARDS[i][2]))
	pic.custom_minimum_size = Vector2(64, 64)
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pic)
	var word := _label(String(CARDS[i][0]), 18, "text")
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(word)
	b.pressed.connect(card.bind(i))
	return b


func _strip_button(nm: String, text: String, tip: String, f: Callable, size := Vector2(120, 40), font := 0) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = size
	if font > 0:
		b.add_theme_font_size_override("font_size", font)
	b.pressed.connect(f)
	return b


func _label(text: String, size: int, tok: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Tok.c(tok))
	return l
