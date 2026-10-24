class_name EasyHome
extends Node
## EASY HOME (monkey brain easy): what a beginner sees in Easy mode when the scene is empty. A centred panel,
## "What should he do?", with eight picture cards and one text box ("or type it"). A card builds its clip (the
## templates/ files for walk, run, jump, punch, sit down, wave and the kick (roundhouse.json, baked); TextBlocking for typed words), one undo step, then it plays by itself.
## After that the panel is a strip with three buttons: Again, Change it (the panel and its text box come back), Save video.
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
	row.add_child(_strip_button("eh_again", "Again", "play the clip from its start", _play))
	row.add_child(_strip_button("eh_change", "Change it", "type another move in the box", _change))
	row.add_child(_strip_button("eh_save", "Save video", "render the scene from the camera to a video in your Videos folder (Kine/), with a button to show it", save_video))
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


func _process(_dt: float) -> void:
	if m == null or panel == null:
		return
	var on: bool = m.easy.on
	var empty: bool = m.S.cards.is_empty()
	panel.visible = on and (empty or _open)
	strip.visible = on and not (empty or _open) and _built
	if not on:
		_toast.visible = false
	_close.visible = not empty
	if _t0 >= 0 and m.playing and m.playhead > 0.0:   # the first frame in which the clip moves
		last_ms = Time.get_ticks_msec() - _t0
		_t0 = -1


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
	var r: Dictionary = await m._export_playblast(video_folder())
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
	_go(t, "Typed: " + t)


func _go(what: String, label: String) -> void:
	var t := Time.get_ticks_msec()
	var err := _build(what, label)
	last_build_ms = Time.get_ticks_msec() - t
	if err != "":
		_fail(err)
		return
	_built = true
	_open = false
	_msg.text = ""
	_play()


## the clip for one card or one typed line: one undo step. "" = built; else the one sentence why not
func _build(what: String, label: String) -> String:
	var nm := what.strip_edges().to_lower()
	var d: Dictionary
	var path := ""
	if Templates.has_file(nm):   # the picker's templates and the baked kick (templates/roundhouse.json: instant)
		d = Templates.read(nm)
		if d.is_empty():
			return "The %s template file is missing: rebuild the templates (tools/make_templates.gd) and try again." % nm
		path = Templates.new_path(nm)
	else:
		var r := _words_dict(nm)
		if not r["ok"]:
			return String(r["error"])
		d = r["dict"]
		path = TextBlocking.unique_path("res://scenes/_wip", TextBlocking.slug(nm))
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
		var r: Dictionary = TextBlocking.build(p, W)
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


func _strip_button(nm: String, text: String, tip: String, f: Callable) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(120, 40)
	b.pressed.connect(f)
	return b


func _label(text: String, size: int, tok: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Tok.c(tok))
	return l
