class_name EasyScenes
extends Control
## EASY: "My scenes" (Nick: "Easy mode can't let you open already made scenes easily"). The bar's My scenes button opens this
## panel: the saved scenes as big tiles with their pictures (SceneThumbs, the scene list's own pictures), newest first, and a
## second row "Examples" (the shipped scenes, opened as copies, as Expert's example buttons do). One click opens the scene and
## plays it; a scene with unsaved work asks first (main._ask_save). Esc or Close shuts it. Example scenes are not in "My scenes".

const TILE := Vector2(224, 196)
const PIC := Vector2(208, 130)

var m: Node                       # main (untyped: the same pattern as EasyMode)
var _mine: HFlowContainer
var _examples: HFlowContainer
var _tiles := {}                  # scene path -> {"button": Button, "pic": TextureRect, "name": String, "example": bool}
var _order_mine: Array = []       # the saved scenes' paths, in the order shown (newest first)
var _order_ex: Array = []         # the examples' paths, in the order shown


## built once, from EasyMode.build: a full-window panel over the bar, hidden until My scenes is pressed
func build(root: Control) -> void:
	name = "easy_scenes"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.name = "easy_scenes_shade"
	shade.color = Color(0, 0, 0, 0.7)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var box := PanelContainer.new()
	box.name = "easy_scenes_box"
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 40.0
	box.offset_top = 40.0
	box.offset_right = -40.0
	box.offset_bottom = -40.0
	var st := StyleBoxFlat.new()
	st.bg_color = Tok.c("panel")
	st.set_corner_radius_all(12)
	st.set_content_margin_all(16)
	box.add_theme_stylebox_override("panel", st)
	add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	box.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := Label.new()
	title.text = "My scenes"
	title.add_theme_font_size_override("font_size", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.name = "easy_scenes_close"
	close.text = "Close"
	close.tooltip_text = "close this list (Esc)"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(130, 44)
	close.add_theme_font_size_override("font_size", 18)
	close.pressed.connect(close_panel)
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	scroll.add_child(body)
	body.add_child(_heading("Your scenes (newest first)"))
	_mine = HFlowContainer.new()
	_mine.name = "easy_scenes_mine"
	_mine.add_theme_constant_override("h_separation", 12)
	_mine.add_theme_constant_override("v_separation", 12)
	body.add_child(_mine)
	body.add_child(_heading("Examples: a copy to look at and change"))
	_examples = HFlowContainer.new()
	_examples.name = "easy_scenes_examples"
	_examples.add_theme_constant_override("h_separation", 12)
	_examples.add_theme_constant_override("v_separation", 12)
	body.add_child(_examples)
	root.add_child(self)


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	return l


## the panel: the saved scenes and the examples are read now (a scene saved since the last open is listed)
func open_panel() -> void:
	if m == null or m.thumbs == null:
		return
	if not m.thumbs.made.is_connected(_made):
		m.thumbs.made.connect(_made)
	_fill()
	visible = true
	move_to_front()


func close_panel() -> void:
	visible = false


## the paths of the tiles shown, in order: the saved scenes (example false) or the examples (example true)
func tile_paths(example: bool) -> Array:
	return (_order_ex if example else _order_mine).duplicate()


## the tile's button for a scene path (its press is the click that opens it)
func tile_button(path: String) -> Button:
	return _tiles[path]["button"] if _tiles.has(path) else null


## the tile's picture (null until the picture is drawn)
func tile_picture(path: String) -> Texture2D:
	return (_tiles[path]["pic"] as TextureRect).texture if _tiles.has(path) else null


## the tile's name as shown
func tile_name(path: String) -> String:
	return String(_tiles[path]["name"]) if _tiles.has(path) else ""


func _fill() -> void:
	for g in [_mine, _examples]:
		for c in g.get_children():
			g.remove_child(c)
			c.queue_free()
	_tiles.clear()
	_order_mine = []
	_order_ex = []
	var examples := []
	for ex in m.EXAMPLES:
		examples.append(String(ex[1]))
	# the saved scenes: the list's own rows (Expert's scene list reads the same folders, newest first), without the examples
	var dirs: Array = ["res://scenes", "res://moves"].reduce(func(a, x): return a + UserPaths.dirs(x), [])
	for f in m._scene_files(dirs):
		var p := String(f[0])
		if examples.has(p) or _tiles.has(p):
			continue
		_order_mine.append(p)
		_add_tile(p, p.get_file().get_basename().replace("_", " "), false)
	for p: String in examples:
		var nm: String = p.get_file().get_basename()
		_order_ex.append(p)
		_add_tile(p, nm.replace("_", " ").capitalize(), true)
	if _order_mine.is_empty():
		var none := _heading("No saved scenes yet: press New scene, then Save the scene, and it is listed here.")
		_mine.add_child(none)
	if m.thumbs != null:
		for p in _order_mine + _order_ex:
			m.thumbs.request(p)
			_made(p)


func _add_tile(path: String, nm: String, example: bool) -> void:
	var b := Button.new()
	b.name = "tile_%s_%d" % ["ex" if example else "mine", (_order_ex if example else _order_mine).size()]
	b.custom_minimum_size = TILE
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = ("Open the example '%s' as a copy: Save makes a new file" if example else "Open '%s' and play it") % nm
	b.pressed.connect(_pick.bind(path, example))
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 6)
	b.add_child(col)
	var pic := TextureRect.new()
	pic.name = "picture"
	pic.custom_minimum_size = PIC
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(pic)
	var l := Label.new()
	l.name = "name"
	l.text = nm
	l.add_theme_font_size_override("font_size", 17)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(l)
	_tiles[path] = {"button": b, "pic": pic, "name": nm, "example": example}
	(_examples if example else _mine).add_child(b)


## a picture is ready: its tile shows it
func _made(path: String) -> void:
	if not _tiles.has(path) or m.thumbs == null:
		return
	var tex: Texture2D = m.thumbs.picture(path)
	if tex != null:
		(_tiles[path]["pic"] as TextureRect).texture = tex


## a tile's click: the panel shuts, the scene opens (save-first question when the open one has unsaved work), and it plays
func _pick(path: String, example: bool) -> void:
	close_panel()
	var play := func():
		if m.S.cards.size() >= 2 and not m.playing:
			m._toggle_play()
	if example:
		var go := func():
			m._open_example(path)
			play.call()
		if m._unsaved():
			m._ask_save(m._scene_label(), go)
		else:
			go.call()
	else:
		m._open_scene_file(path, play)


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()
