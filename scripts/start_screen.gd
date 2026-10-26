class_name StartScreen
extends Control
## THE START SCREEN (the owner's approved mockup: C:/Temp/claude/start/start.png). A full window over the app:
##   top      the KINE logo and name, "Animation & modeling", Settings and Help
##   New project  three cards, ANIMATION / MODELING / 3D BUILDING. ANIMATION has an Easy / Expert toggle (default: the
##            mode the app is in now); MODELING has no Easy flow yet: one Start button and "Easy mode coming".
##            A click on a card starts that kind of project: a new empty scene, with the page
##            it is for (POSE, MODEL with the body open, STAGE). The mode the card shows is the one that applies.
##   Open     filter chips (All, Animation, Modeling, Building, Favourites), a search box, Open file..., Examples, and the
##            recent scenes as tiles: the SceneThumbs picture, the kind as a tag, the quality badge of Kine's Check (SceneCat
##            cache), a star. First run (no saved scene yet): the three example scenes, and "No recent work yet".
##   bottom   "Continue where you left off: <scene> (<time> ago) [Resume]" and the version.
## Esc or Resume closes it (back to the last scene). The kind of a project is saved in the scene file as "kind"
## (scene.gd; "animation" for a file without one). Shown at start-up unless a test runs, --kine-no-start is given, or
## "Show start screen" is off (Settings, saved in the settings file under [look] start_screen).

const KINDS := [
	["animation", "ANIMATION", "Pose and animate a fighter: typed moves, cards, AI video."],
	["modeling", "MODELING", "Shape, sculpt and colour the body: MODEL, SCULPT, SURFACE."],
	["building", "3D BUILDING", "Build a set or stage: props, floors, walls and lights."],
]
const KIND_NAME := {"animation": "Animation", "modeling": "Modeling", "building": "Building"}
const KIND_TAG := {"animation": Color(0.45, 0.75, 1.0), "modeling": Color(0.5, 0.88, 0.6), "building": Color(1.0, 0.7, 0.35)}
const CHIPS := [["all", "All"], ["animation", "Animation"], ["modeling", "Modeling"], ["building", "Building"], ["fav", "★ Favourites"]]
const RECENT_MAX := 12
const TILE := Vector2(232, 184)
const PIC := Vector2(216, 122)
const CARD_ART_H := 124.0
const LOGO_H := 40.0
const EASY_KINDS := ["animation", "building"]   # the kinds that have a real Easy flow (the Easy bar has no MODEL / SURFACE pages; BUILD has its own, scripts/easy_build.gd)

var m: Node                      # the app (main.gd)
var art: StartArt
var dirs_override: Array = []    # a test's own folders (user://) in place of the saved-scenes folders
var _cards := {}                 # kind -> PanelContainer
var _card_art := {}              # kind -> TextureRect
var _card_hint := {}             # kind -> Label ("Start ->" on hover)
var _easy_btn := {}              # kind -> Button (Easy)
var _expert_btn := {}            # kind -> Button (Expert)
var _card_easy := {}             # kind -> bool: this card's mode
var _chip_btns := {}             # chip key -> Button
var _chip := "all"
var _search: LineEdit
var _tiles_flow: HFlowContainer
var _tiles := {}                 # path -> {"tile", "pic", "star", "kind", "name", "badge", "tag", "example"}
var _order: Array = []           # the tile paths, newest first (the shown order)
var _empty_note: Label
var _resume_text: Label
var _resume_btn: Button
var _resume_path := ""
var _settings: PanelContainer
var _show_check: CheckBox
var _built := false
var file_dialog_inline := false   # a test: the in-window dialog (a native one cannot be driven)
var last_dialog: FileDialog
var _layout: VBoxContainer     # the window's column (top bar, the scrolled body, the bottom bar)
var _body: VBoxContainer       # the scrolled body


static func setting_on(cf: ConfigFile) -> bool:
	return bool(cf.get_value("look", "start_screen", true))


## built once, from main's _ready (hidden; the boot or the logo / File menu shows it)
func build() -> void:
	if _built:
		return
	_built = true
	name = "start_screen"
	_fit()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.075, 0.08, 0.095)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	art = StartArt.new()
	add_child(art)
	art.changed.connect(_art_changed)
	var root := VBoxContainer.new()
	root.name = "layout"
	_layout = root
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24
	root.offset_right = -24
	root.offset_top = 12
	root.offset_bottom = -8
	root.add_theme_constant_override("separation", 10)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.add_child(_top_bar())
	var scroll := ScrollContainer.new()
	scroll.name = "content_scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var body := VBoxContainer.new()
	body.name = "content"
	_body = body
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	scroll.add_child(body)
	body.add_child(_new_project_block())
	body.add_child(_open_block())
	root.add_child(_bottom_bar())
	_settings = _settings_box()
	add_child(_settings)
	_settings.visible = false
	visible = false


func _top_bar() -> Control:
	var h := HBoxContainer.new()
	h.name = "top_bar"
	h.add_theme_constant_override("separation", 12)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/brand/kine_logo.svg")
	logo.name = "logo"
	logo.custom_minimum_size = Vector2(LOGO_H * 175.0 / 64.0, LOGO_H)   # the whole mark (the K and "kine", the intro's own K) at its 175 x 64 shape
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(logo)
	h.add_child(_label("Animation & modeling", 13, "info:0.7"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(sp)
	var st := _button("Settings", "settings_btn")
	st.pressed.connect(_toggle_settings)
	h.add_child(st)
	var hp := _button("Help", "help_btn")
	hp.pressed.connect(_show_help)
	h.add_child(hp)
	return h


func _new_project_block() -> Control:
	var v := VBoxContainer.new()
	v.name = "new_project"
	v.add_theme_constant_override("separation", 8)
	var head := HBoxContainer.new()
	head.add_child(_label("New project", 18, "text"))
	head.add_child(_label("   Pick what you want to make", 13, "info:0.6"))
	v.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.name = "cards"
	for k in KINDS:
		row.add_child(_card(k[0], k[1], k[2]))
	v.add_child(row)
	return v


func _card(kind: String, title: String, desc: String) -> PanelContainer:
	var c := PanelContainer.new()
	c.name = "card_" + kind
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.add_theme_stylebox_override("panel", _box(Tok.c("card"), 10, Tok.c("card")))
	c.gui_input.connect(_card_input.bind(kind))
	c.mouse_entered.connect(_hover.bind(kind, true))
	c.mouse_exited.connect(_hover.bind(kind, false))
	_cards[kind] = c
	_card_easy[kind] = EASY_KINDS.has(kind) and (m == null or m.easy == null or m.easy.on)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(v)
	var pic := TextureRect.new()
	pic.name = "art"
	pic.custom_minimum_size = Vector2(0, CARD_ART_H)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pic)
	_card_art[kind] = pic
	var tl := _label(title, 17, "text")
	tl.name = "title"
	v.add_child(tl)
	var dl := _label(desc, 12, "info:0.7")
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.custom_minimum_size = Vector2(0, 32)
	v.add_child(dl)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if EASY_KINDS.has(kind):
		var grp := ButtonGroup.new()
		var easy := _button("Easy", "easy_" + kind)
		easy.toggle_mode = true
		easy.button_group = grp
		easy.custom_minimum_size = Vector2(70, 26)
		var expert := _button("Expert", "expert_" + kind)
		expert.toggle_mode = true
		expert.button_group = grp
		expert.custom_minimum_size = Vector2(70, 26)
		easy.pressed.connect(_set_card_mode.bind(kind, true))
		expert.pressed.connect(_set_card_mode.bind(kind, false))
		_easy_btn[kind] = easy
		_expert_btn[kind] = expert
		foot.add_child(easy)
		foot.add_child(expert)
	else:   # no Easy flow for this kind yet: one honest button, and the note
		var go := _button("Start", "start_" + kind)
		go.custom_minimum_size = Vector2(70, 26)
		go.pressed.connect(_start_kind.bind(kind))
		foot.add_child(go)
		var soon := _label("Easy mode coming", 12, "info:0.5")
		soon.name = "easy_soon_" + kind
		foot.add_child(soon)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(sp)
	var hint := _label("Start →", 14, "heading")
	hint.name = "hint"
	hint.visible = false
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(hint)
	_card_hint[kind] = hint
	v.add_child(foot)
	_sync_modes(kind)
	return c


func _open_block() -> Control:
	var v := VBoxContainer.new()
	v.name = "open"
	v.add_theme_constant_override("separation", 8)
	var head := HFlowContainer.new()
	head.add_theme_constant_override("h_separation", 10)
	head.add_theme_constant_override("v_separation", 8)
	var t := _label("Open", 18, "text")
	head.add_child(t)
	_empty_note = _label("New here? Pick a card above.", 13, "info:0.6")
	head.add_child(_empty_note)
	for c in CHIPS:
		var b := _button(c[1], "chip_" + c[0])
		b.toggle_mode = true
		b.button_pressed = c[0] == "all"
		b.pressed.connect(_pick_chip.bind(c[0]))
		_chip_btns[c[0]] = b
		head.add_child(b)
	_search = LineEdit.new()
	_search.name = "search"
	_search.placeholder_text = "Search projects"
	_search.custom_minimum_size = Vector2(190, 30)
	_search.text_changed.connect(func(_t): _apply())
	head.add_child(_search)
	var file_btn := _button("Open file...", "open_file_btn")
	file_btn.flat = true
	file_btn.pressed.connect(_open_file)
	head.add_child(file_btn)
	var ex_btn := _button("Examples", "examples_btn")
	ex_btn.flat = true
	ex_btn.pressed.connect(_open_examples)
	head.add_child(ex_btn)
	v.add_child(head)
	_tiles_flow = HFlowContainer.new()
	_tiles_flow.name = "tiles"
	_tiles_flow.add_theme_constant_override("h_separation", 12)
	_tiles_flow.add_theme_constant_override("v_separation", 12)
	v.add_child(_tiles_flow)
	return v


func _bottom_bar() -> Control:
	var h := HBoxContainer.new()
	h.name = "bottom_bar"
	h.add_theme_constant_override("separation", 10)
	_resume_text = _label("", 13, "text")
	_resume_text.name = "resume_text"
	h.add_child(_resume_text)
	_resume_btn = _button("Resume", "resume_btn")
	_resume_btn.pressed.connect(_resume)
	h.add_child(_resume_btn)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(sp)
	h.add_child(_label("Kine v%s" % String(ProjectSettings.get_setting("application/config/version", "")), 12, "info:0.6"))
	return h


func _settings_box() -> PanelContainer:
	var p := PanelContainer.new()
	p.name = "settings_box"
	p.set_anchors_preset(Control.PRESET_CENTER_TOP)
	p.offset_top = 56
	p.offset_left = -170
	p.offset_right = 170
	p.add_theme_stylebox_override("panel", _box(Tok.c("panel"), 10, Tok.c("accent")))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(_label("Settings", 16, "text"))
	_show_check = CheckBox.new()
	_show_check.name = "show_start"
	_show_check.text = "Show start screen"
	_show_check.toggled.connect(_show_toggled)
	v.add_child(_show_check)
	var close_btn := _button("Close", "settings_close")
	close_btn.pressed.connect(_close)
	v.add_child(close_btn)
	return p


## ---- showing it

## the screen is shown: pictures asked for, the lists read again, the newest scene on Resume
func show_screen() -> void:
	if not _built:
		build()
	_fit()
	_refresh()
	visible = true
	_relayout()
	move_to_front()
	if art != null:
		art.request_all()


## a container that was built while hidden keeps its children at their minimum sizes until it is sorted again
func _relayout() -> void:
	if _layout != null:
		_layout.queue_sort()
	if _body != null:
		_body.queue_sort()


## the whole window: the anchors and offsets pinned (a preset made while the parent had no size left a bad offset)
func _fit() -> void:
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0


func _close() -> void:
	visible = false
	_settings.visible = false


func _input(ev: InputEvent) -> void:
	if not visible:
		return
	if ev is InputEventKey and (ev as InputEventKey).pressed and not (ev as InputEventKey).echo and (ev as InputEventKey).keycode == KEY_ESCAPE:
		if _settings.visible:
			_settings.visible = false
		else:
			_resume()
		get_viewport().set_input_as_handled()


func _resume() -> void:
	var path := _resume_path
	_close()
	if path != "" and m != null and String(m.scene_path) != path and FileAccess.file_exists(path):
		m._open_scene_file(path)


## ---- starting a kind of project

func _start_kind(kind: String) -> void:
	if m == null:
		return
	if m._unsaved():   # a new project replaces the open one: unsaved work is asked about first (Save / Don't save / Cancel)
		_close()
		m._ask_save(m._scene_label(), func(): _start_kind_now(kind))
		return
	_start_kind_now(kind)


func _start_kind_now(kind: String) -> void:
	# the pages of MODEL and STAGE are Expert's (the Easy bar hides them): those projects open in Expert
	var want_easy: bool = EASY_KINDS.has(kind) and bool(_card_easy.get(kind, true))
	if m.easy != null:
		m.easy.set_on(want_easy)
	_close()
	m._new_scene()
	m.S.kind = kind
	match kind:
		"animation":
			m._page_set("POSE")
		"modeling":
			BaseBody.start(m)
		"building":
			m._page_set("BUILD")
			m.bld.reset_view()   # a new project starts on the default view, not where the last house was left
	if m.has_method("_refresh"):
		m._refresh()


func _sync_modes(kind: String) -> void:
	if not _easy_btn.has(kind):
		return
	var easy := bool(_card_easy.get(kind, true))
	(_easy_btn[kind] as Button).button_pressed = easy
	(_expert_btn[kind] as Button).button_pressed = not easy


func _hover(kind: String, on: bool) -> void:
	(_cards[kind] as PanelContainer).add_theme_stylebox_override("panel", _box(Tok.c("card_sel") if on else Tok.c("card"), 10, Tok.c("accent") if on else Tok.c("card")))
	(_card_hint[kind] as Label).visible = on


func _art_changed(kind: String) -> void:
	if _card_art.has(kind) and art != null:
		(_card_art[kind] as TextureRect).texture = art.get_art(kind)


## ---- the lists

## the saved scenes (newest first, the examples left out), the list the recent grid and the Resume line read
func _saved_paths() -> Array:
	var ds: Array = dirs_override.duplicate()
	if ds.is_empty() and m != null:
		ds = ["res://scenes", "res://moves"].reduce(func(a, x): return a + UserPaths.dirs(x), [])
	var out: Array = []
	if m == null:
		return out
	var ex := []
	for e in m.EXAMPLES:
		ex.append(String(e[1]))
	var files: Array = m._scene_files(ds)
	var rows := []
	for f in files:
		var p := String(f[0])
		if ex.has(p) or p.contains("/_wip/"):
			continue
		rows.append([p, FileAccess.get_modified_time(p)])
	rows.sort_custom(func(a, b): return int(a[1]) > int(b[1]) or (int(a[1]) == int(b[1]) and String(a[0]) < String(b[0])))
	for r in rows:
		out.append(String(r[0]))
		if out.size() >= RECENT_MAX:
			break
	return out


func _example_paths() -> Array:
	var out: Array = []
	if m != null:
		for e in m.EXAMPLES:
			out.append(String(e[1]))
	return out


func _kind_of(path: String) -> String:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if d is Dictionary:
		var k := String((d as Dictionary).get("kind", "animation"))
		if KIND_NAME.has(k):
			return k
	return "animation"


func _grade(path: String) -> String:
	var cache := SceneCat.load_cache()
	var e: Dictionary = cache.get(path, {})
	if e.is_empty() or not SceneCat.fresh(e, path) or not (e.has("fails") and e.has("warns")):
		return ""
	return SceneCat.grade_of(int(e["fails"]), int(e["warns"]))


func _refresh() -> void:
	var saved := _saved_paths()
	var examples := saved.is_empty()
	var paths: Array = _example_paths() if examples else saved
	_order = paths
	for c in _tiles_flow.get_children():
		_tiles_flow.remove_child(c)
		c.queue_free()
	_tiles.clear()
	for p in paths:
		_add_tile(String(p), examples)
	_empty_note.text = "New here? Pick a card above." if examples else "Pick a card above, or open a scene."
	var recents: Array = m._recent_list() if m != null else []
	_resume_path = ""
	if not saved.is_empty() or not recents.is_empty():
		var last := String(recents[0]) if not recents.is_empty() else String(saved[0])
		_resume_path = last
		var t := 0
		if m != null and m.recents != null:
			var meta: Dictionary = (m.recents as Recents).meta_all().get(last, {})
			t = int(meta.get("t", 0))
		var ago := Recents.ago(t, int(Time.get_unix_time_from_system())) if t > 0 else ""
		_resume_text.text = "Continue where you left off:  %s%s" % [last.get_file().get_basename().replace("_", " "), "  (%s)" % ago if ago != "" else ""]
		_resume_btn.visible = true
	else:
		_resume_text.text = "No recent work yet. Your first project shows up here."
		_resume_btn.visible = false
	if m != null and m.thumbs != null:
		for p in paths:
			m.thumbs.request(String(p))
	_apply()


func _add_tile(path: String, example: bool) -> void:
	var tile := PanelContainer.new()
	tile.name = "tile_" + path.get_file().get_basename()
	tile.custom_minimum_size = TILE
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	tile.add_theme_stylebox_override("panel", _box(Tok.c("card"), 8, Tok.c("card")))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(v)
	var pic_bg := PanelContainer.new()
	pic_bg.custom_minimum_size = PIC
	pic_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic_bg.add_theme_stylebox_override("panel", _box(Color(0.1, 0.105, 0.12), 6, Color(0.1, 0.105, 0.12)))
	var pic := TextureRect.new()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.texture = m.thumbs.picture(path) if m != null and m.thumbs != null else null
	pic_bg.add_child(pic)
	v.add_child(pic_bg)
	var nm := String(path.get_file().get_basename()).replace("_", " ")
	if example:
		nm = nm.capitalize()
	var name_l := _label(nm, 14, "text")
	name_l.clip_text = true
	name_l.custom_minimum_size = Vector2(PIC.x, 0)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var kind := _kind_of(path)
	var tag := _label("Example" if example else KIND_NAME[kind], 11, "text")
	tag.name = "tag"
	tag.add_theme_color_override("font_color", KIND_TAG[kind])
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tag)
	var grade := "" if example else _grade(path)
	var badge := _label(grade if grade != "" else ("" if example else "..."), 11, "info:0.7")
	badge.name = "badge"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(badge)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp)
	var star := _button("☆", "star")
	star.flat = true
	star.custom_minimum_size = Vector2(26, 24)
	star.tooltip_text = "Favourite"
	star.visible = not example
	star.pressed.connect(_toggle_fav.bind(path))
	row.add_child(star)
	v.add_child(row)
	tile.gui_input.connect(_tile_input.bind(path, example))
	_tiles_flow.add_child(tile)
	_tiles[path] = {"tile": tile, "pic": pic, "star": star, "kind": kind, "name": nm, "badge": badge, "tag": tag, "example": example}
	if _fav().has(path):
		star.text = "★"
	if m != null and m.thumbs != null and not m.thumbs.made.is_connected(_made):
		m.thumbs.made.connect(_made)


func _made(path: String) -> void:
	if _tiles.has(path) and m != null and m.thumbs != null:
		(_tiles[path]["pic"] as TextureRect).texture = m.thumbs.picture(path)


func _open_tile(path: String, example: bool) -> void:
	if m == null:
		return
	var go := func():
		_close()
		if example:
			m._open_example(path)
		else:
			m._open_scene_file(path)
	if not example and m._unsaved():
		_close()
		m._ask_save(m._scene_label(), go)
	else:
		go.call()


func _fav() -> Array:
	var out: Array = []
	for p in _cf().get_value("easy_scenes", "favourites", []):
		out.append(String(p))
	return out


func _toggle_fav(path: String) -> void:
	var f := _fav()
	if f.has(path):
		f.erase(path)
	else:
		f.append(path)
	var cf := _cf()
	cf.set_value("easy_scenes", "favourites", f)
	_save(cf)
	if _tiles.has(path):
		(_tiles[path]["star"] as Button).text = "★" if f.has(path) else "☆"
	_apply()


func _pick_chip(key: String) -> void:
	_chip = key
	for k in _chip_btns:
		(_chip_btns[k] as Button).button_pressed = k == key
	_apply()


## the chip, the search text: which tiles show
func _apply() -> void:
	var q := _search.text.strip_edges().to_lower() if _search != null else ""
	var fav := _fav()
	for p in _tiles:
		var t: Dictionary = _tiles[p]
		var ok := true
		if _chip == "fav":
			ok = fav.has(p)
		elif _chip != "all":
			ok = String(t["kind"]) == _chip
		if q != "":
			ok = ok and String(t["name"]).to_lower().contains(q)
		(t["tile"] as Control).visible = ok
	for k in _chip_btns:
		(_chip_btns[k] as Button).button_pressed = k == _chip


## ---- helpers

func _is_click(ev: InputEvent) -> bool:
	return ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT


func _cf() -> ConfigFile:
	var cf := ConfigFile.new()
	if m != null and m.settings != "":
		cf.load(m.settings)
	return cf


func _save(cf: ConfigFile) -> void:
	if m != null and m.settings != "":
		cf.save(m.settings)


func _label(text: String, size: int, tok: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Tok.of(tok))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, nm: String) -> Button:
	var b := Button.new()
	b.text = text
	b.name = nm
	b.add_theme_stylebox_override("normal", _box(Tok.c("btn"), 8, Tok.c("btn")))
	b.add_theme_stylebox_override("hover", _box(Tok.c("btn_hover"), 8, Tok.c("btn_hover")))
	b.add_theme_stylebox_override("pressed", _box(Tok.c("accent"), 8, Tok.c("accent")))
	b.add_theme_color_override("font_color", Tok.c("btn_text"))
	b.add_theme_color_override("font_pressed_color", Tok.c("on_accent"))
	return b


func _box(bg: Color, r: int, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(r)
	s.set_content_margin_all(10)
	return s


func _toggle_settings() -> void:
	_settings.visible = not _settings.visible
	_show_check.button_pressed = setting_on(_cf())


func _show_help() -> void:
	if m != null and m.ui_help != null:
		m.ui_help.visible = true


func _card_input(ev: InputEvent, kind: String) -> void:
	if _is_click(ev):
		_start_kind(kind)


func _tile_input(ev: InputEvent, path: String, example: bool) -> void:
	if _is_click(ev):
		_open_tile(path, example)


func _set_card_mode(kind: String, easy: bool) -> void:
	_card_easy[kind] = easy
	_sync_modes(kind)


## a real file picker for a .json scene (the native dialog); the screen stays until a file is picked
func _open_file() -> void:
	if m == null:
		return
	var fd := FileDialog.new()
	fd.name = "open_file_dialog"
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.json ; Kine scenes"])
	fd.use_native_dialog = not file_dialog_inline
	fd.title = "Open a scene (.json)"
	fd.file_selected.connect(func(p): _file_picked(p); fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	m.add_child(fd)
	fd.popup_centered(Vector2i(800, 500))
	last_dialog = fd


func _file_picked(path: String) -> void:
	_close()
	if m != null and FileAccess.file_exists(path):
		m._open_scene_file(path)


func _open_examples() -> void:
	_close()
	if m != null and m.easy != null and m.easy.scenes != null:
		m.easy.scenes.open_panel(false)


func _show_toggled(on: bool) -> void:
	var cf := _cf()
	cf.set_value("look", "start_screen", on)
	_save(cf)
