class_name BuildChoose
extends Node
## "WHAT DO YOU WANT TO BUILD?" (mockup C:/Temp/claude/partmock/build_choose.png): the chooser over the BUILD page of a 3D BUILDING
## project. Six picture cards: House / Set (today's room tool), Part, Vehicle, Prop pack (the object library, by category),
## From a template, Import STEP (KineCAD). Each live card has Easy and Expert buttons and ONE click starts it (they start, they
## do not toggle). A card that is not ready is greyed and says why on the card and on the status line when clicked: it does nothing else.
## The start screen shows it after a 3D BUILDING project starts (one call); the BUILD ribbon's (and Easy bar's) "What to build"
## button reopens it. Mouse only: no key names in any text here.

const CARDS := [
	{"id": "house", "title": "House / Set", "text": "Rooms, walls, stairs, roofs, and a place to act in.", "easy": "Rooms and walls", "expert": "Plans, stairs, guides"},
	{"id": "part", "title": "Part", "text": "One solid thing: a sword, an axe, a bracket.", "easy": "Shape + sliders", "expert": "Sketch + timeline"},
	{"id": "vehicle", "title": "Vehicle", "text": "Build a car from scratch: set the hard points, then check it against real cars.", "easy": "Set the hard points", "expert": "Type the numbers in mm"},
	{"id": "props", "title": "Prop pack", "text": "Crates, barrels, chairs: many small things, one file.", "easy": "Pick and place", "expert": "Edit each prop"},
	{"id": "template", "title": "From a template", "text": "Start from a finished one, then change it.", "easy": "Change with sliders", "expert": "Open its timeline"},
	{"id": "step", "title": "Import STEP", "text": "Bring in a CAD file. It stays a real solid.", "easy": "Import and tidy", "expert": "Import and edit"},
]
const KCad := preload("res://scripts/kcad.gd")
const BuildStarters := preload("res://scripts/build/build_starters.gd")
const GAP := 14.0
const YEL := Color(1.0, 0.78, 0.22)

var m: Node
var auto := false      # main: a real launch (a test never gets the chooser by itself: it would cover the page it clicks)
var open := false
var root_box: Panel
var cards := {}        # id -> PanelContainer
var btns := {}         # id -> {"easy": Button, "expert": Button}
var whys := {}         # id -> Label (the greyed card's reason; "" when live)
var step_picker: Callable = Callable()   # a test sets this: (cb: Callable) -> calls cb(path); the real one is a file dialog
var _grid: GridContainer
var _col: VBoxContainer
var _title: Label
var _sub: Label
var _arts := []
var _texts := []
var _last := Vector2.ZERO
var _settle := 0
var art: BuildChooseArt   # the six rendered pictures (scripts/build_choose_art.gd), read from the cache or drawn once, a frame at a time
var _solid: MeshInstance3D = null   # the imported STEP solid, shown on BUILD
var _starters: PopupMenu = null     # the Template card's list of starter buildings (built on the first click)
var _starter_easy := false          # the mode the Template card was clicked in
var _car_screen: PackageScreen = null  # the Vehicle card's screen: the package (built on the first click; carpkg)


## why a card cannot start yet ("" = it can): the card says it, a click says it again
func why_not(id: String) -> String:
	match id:
		"part":
			if not KCad.available():
				return "Needs the KineCAD add-on, which is not installed."
		"vehicle":
			if not KCad.available():
				return "Needs the KineCAD add-on, which is not installed."
		"step":
			if not KCad.available():
				return "Needs the KineCAD add-on, which is not installed."
	return ""


## the ribbon / Easy bar button that reopens the chooser
static func reopen_button(main: Node) -> Button:
	var b := Button.new()
	b.name = "build_choose_open"
	b.text = ""   # icon only (the tooltip says it): the BUILD row also holds Part since the Part workspace, and a word pushed it past 1280 px
	b.icon = Icons.tex("build_piece")
	b.theme_type_variation = "Ribbon"
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "Pick what to build: a part, a prop pack, a scene piece or an imported file"
	b.pressed.connect(func(): if main.build_choose != null: main.build_choose.show_chooser())
	return b


func show_chooser() -> void:
	if root_box == null:
		return
	open = true
	root_box.visible = true
	if m.ui_library != null and m.ui_library.visible:   # the object library left open (Prop pack) would sit under the cards and take their clicks
		m.ui_library.hide_panel()
	_settle = 4
	_sync()
	_place()
	art.request_all()   # a no-op once every picture is there; else one per frame, after this one


func close() -> void:
	open = false
	if root_box != null:
		root_box.visible = false


func _process(_dt: float) -> void:
	if not open:
		return
	if m.cur_page != "BUILD" or m.S.kind != "building":
		close()   # left the page: the chooser goes
		return
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	if vs != _last or _settle > 0:
		_settle = maxi(0, _settle - 1)
		_place()


func build(parent: Control) -> void:
	art = BuildChooseArt.new()
	add_child(art)
	art.changed.connect(func(_k): for a in _arts: (a as Control).queue_redraw())
	root_box = Panel.new()
	root_box.name = "build_choose"
	root_box.visible = false
	root_box.mouse_filter = Control.MOUSE_FILTER_STOP
	root_box.z_index = 5   # over Easy BUILD's column and hint
	root_box.add_theme_stylebox_override("panel", _sb(Color(0.09, 0.1, 0.12, 0.98), 0))
	parent.add_child(root_box)
	_col = VBoxContainer.new()
	_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_col.add_theme_constant_override("separation", 6)
	root_box.add_child(_col)
	# a way back: the chooser covers the bar (its Home and Done), so it needs its own (it was a dead end without a card pick)
	var back := Button.new()   # added to the box after the column (below, on top)
	back.name = "build_choose_back"
	back.text = "Back"
	back.tooltip_text = "Close this and go back to the building"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(120, 40)
	back.pressed.connect(close)
	back.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	back.offset_left = -140.0
	back.offset_right = -20.0
	back.offset_top = 14.0
	back.offset_bottom = 54.0
	root_box.add_child(back)
	_title = _label("What do you want to build?", 30, Color(0.93, 0.94, 0.96))
	_title.name = "choose_title"
	_col.add_child(_title)
	_sub = _label("Pick one. Easy gives you big buttons and sliders. Expert gives you the full tools.", 15, Color(0.7, 0.73, 0.78))
	_col.add_child(_sub)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", int(GAP))
	_grid.add_theme_constant_override("v_separation", int(GAP))
	_col.add_child(_grid)
	for c in CARDS:
		_grid.add_child(_card(c))


func _card(c: Dictionary) -> PanelContainer:
	var id: String = c["id"]
	var pc := PanelContainer.new()
	pc.name = "choose_" + id
	pc.add_theme_stylebox_override("panel", _sb(Color(0.14, 0.15, 0.19), 12))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	pc.add_child(v)
	var pic := Art.new()
	pic.kind = id
	pic.src = art
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pic)
	_arts.append(pic)
	v.add_child(_label(String(c["title"]), 19, Color(0.95, 0.96, 0.98)))
	var d := _label(String(c["text"]), 13, Color(0.74, 0.77, 0.82))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	_texts.append(d)
	var w := _label("", 13, Color(1.0, 0.7, 0.35))
	w.name = "why_" + id
	w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	w.visible = false
	v.add_child(w)
	_texts.append(w)
	whys[id] = w
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	btns[id] = {}
	for mode in ["easy", "expert"]:
		var b := Button.new()
		b.name = "%s_%s" % [mode, id]
		b.text = "%s\n%s" % [mode.capitalize(), String(c[mode])]
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 44)
		b.clip_text = true
		b.tooltip_text = String(c[mode])
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(_start.bind(id, mode == "easy"))
		row.add_child(b)
		btns[id][mode] = b
	cards[id] = pc
	return pc


## live cards get the yellow Easy button; a greyed one stays clickable (it says why) but is dimmed and says so on the card
func _sync() -> void:
	for c in CARDS:
		var id: String = c["id"]
		var why := why_not(id)
		var left_out: bool = why != "" and m.easy != null and m.easy.on   # Easy: the not-ready cards are left out (Expert keeps them, greyed, with why)
		(whys[id] as Label).text = why
		(whys[id] as Label).visible = why != "" and not left_out   # a left-out card's reason goes with it
		(cards[id] as PanelContainer).modulate = Color(1, 1, 1, 0.55) if why != "" else Color.WHITE
		(cards[id] as PanelContainer).visible = not left_out
		for mode in ["easy", "expert"]:
			var b: Button = btns[id][mode]
			b.add_theme_stylebox_override("normal", _sb(YEL if (mode == "easy" and why == "") else Color(0.2, 0.21, 0.26), 8))
			b.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1) if (mode == "easy" and why == "") else Color(0.88, 0.9, 0.94))
			b.add_theme_color_override("font_hover_color", b.get_theme_color("font_color"))


func _label(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _sb(bg: Color, r: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(r)
	s.content_margin_left = 12.0 if r > 8 else 6.0
	s.content_margin_right = 12.0 if r > 8 else 6.0
	s.content_margin_top = 10.0 if r > 8 else 4.0
	s.content_margin_bottom = 10.0 if r > 8 else 4.0
	return s


## the cover takes the page under the top bar; three columns, two rows; the pictures take the height that is left
func _place() -> void:
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	_last = vs
	var top := float(m.TOP_H)
	if m.ui_top_bar != null and (m.ui_top_bar as Control).visible:
		top = maxf(top, (m.ui_top_bar as Control).get_global_rect().end.y)
	var low: float = vs.y - float(m.bottom_h) - 88.0   # above the say-line's band
	if m.ui_status != null and (m.ui_status as Control).visible:
		low = minf(low, (m.ui_status as Control).get_global_rect().position.y - 4.0)   # and above the status text itself
	root_box.position = Vector2(0, top)
	root_box.size = Vector2(vs.x, maxf(120.0, low - top))
	var room := root_box.size.y - 16.0
	var small := room < 520.0
	_title.add_theme_font_size_override("font_size", 22 if small else 30)
	_sub.visible = room >= 400.0
	var wide := vs.x - 32.0
	var cw := floorf((wide - GAP * 2.0) / 3.0)
	# per card: art + title 26 + text (1-2 lines) + why (0-3 lines) + buttons 44 + margins 20 + gaps
	var head := (_title.get_combined_minimum_size().y + 6.0) + (_sub.get_combined_minimum_size().y + 6.0 if _sub.visible else 0.0)
	var card_room := (room - head - GAP) * 0.5
	var art_h := clampf(card_room - 150.0, 0.0, 130.0)
	for t in _texts:
		(t as Label).custom_minimum_size = Vector2(cw - 24.0, 0)
		(t as Label).add_theme_font_size_override("font_size", 12 if small else 13)
	for a in _arts:
		(a as Control).custom_minimum_size = Vector2(cw - 24.0, art_h)
		(a as Control).visible = art_h >= 30.0
	for c in cards.values():
		(c as Control).custom_minimum_size = Vector2(cw, 0)
	_col.position = Vector2(16.0, 8.0)
	_col.size = Vector2(wide, room)


# ---------------------------------------------------------------- the Starts

func _start(id: String, easy_on: bool) -> void:
	var why := why_not(id)
	if why != "":
		m._say(why)
		return
	if id != "part" and m.bld.part.on:   # a card that is not the Part one leaves the Part workspace (Expert's way back to the house)
		m.bld.part.set_on(false)
	match id:
		"house":
			_mode(easy_on)
			close()
			m.bld._pick_tool("Room")
			m._say("House / Set: drag on the floor to make a room")
		"props":
			_mode(easy_on)
			close()
			m._page_set("BUILD")
			if m.ui_library == null or not m.ui_library.visible:
				m._library_toggle()
			var lib: ObjectLibrary = m.ui_library
			lib._pick_view("Build furniture")
			if lib._side_btns.has("Build furniture"):
				(lib._side_btns["Build furniture"] as Button).set_pressed_no_signal(true)
		"step":
			_mode(easy_on)
			_ask_step(easy_on)
		"template":
			_pick_starter(easy_on)
		"vehicle":
			_vehicle(easy_on)
		"part":
			_mode(easy_on)
			close()
			m._page_set("BUILD")
			if easy_on:   # Easy Part: shape + sliders (easy_part.gd); the same record Expert opens
				m.bld.part.open_easy()
			else:
				m.bld.part.set_on(true)


## the Vehicle card (carpkg): the PACKAGE step (scripts/package_screen.gd, made on the first click): hard points with sliders (Easy) or
## typed mm (Expert), the side / top layout, the 3D preview, and Yours vs real cars. The ready-made car body is no longer opened here
func _vehicle(easy_on: bool) -> void:
	if _car_screen == null:
		_car_screen = PackageScreen.new()
		_car_screen.m = m
		_car_screen.build(m.ui_root)   # adds itself to the UI root
	close()
	m._page_set("BUILD")
	_car_screen.open(easy_on)


## the Template card: a small list of the three starter buildings (a click picks one; the list is a PopupMenu, so it is mouse-only too)
func _pick_starter(easy_on: bool) -> void:
	_starter_easy = easy_on
	if _starters == null:
		_starters = PopupMenu.new()
		_starters.name = "build_starters"
		for i in BuildStarters.LIST.size():
			var s: Dictionary = BuildStarters.LIST[i]
			_starters.add_item("%s: %s" % [s["name"], s["say"]], i)
		_starters.id_pressed.connect(func(i: int): _load_starter(i))
		add_child(_starters)
	_starters.popup_centered()


## a starter on BUILD, as the current building (one undo step, like a words build); the chooser closes
func _load_starter(i: int) -> void:
	var s: Dictionary = BuildStarters.LIST[i]
	var rec := BuildStarters.build(String(s["id"]))
	if rec.is_empty():
		m._say("That starter did not build. Pick another, or start a House")
		return
	_mode(_starter_easy)
	close()
	m._page_set("BUILD")
	m._step_hint = "Starter: %s" % s["name"]
	m._push_undo()
	m.S.building = rec
	m.bld.sync()
	m.bld._frame_house()
	m._say("Starter: %s. Use in a scene puts it on STAGE; Save house keeps it in My houses" % s["name"])


func _mode(easy_on: bool) -> void:
	if m.easy != null and m.easy.on != easy_on:
		m.easy.set_on(easy_on)


func _ask_step(easy_on: bool) -> void:
	var cb := func(p: String): _import_step(p, easy_on)
	if step_picker.is_valid():
		step_picker.call(cb)
		return
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.step, *.stp ; STEP files"])
	fd.use_native_dialog = true
	fd.title = "A STEP file to bring in"
	fd.file_selected.connect(func(p): cb.call(p); fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	m.add_child(fd)
	fd.popup_centered(Vector2i(800, 500))


## KCad.import_step -> tessellate -> a solid in BUILD's own root (one at a time; the next import replaces it)
func _import_step(path: String, _easy_on: bool) -> bool:
	var id := KCad.import_step(path)
	if id == 0:
		m._say("Could not read that STEP file: %s" % KCad.last_error())
		return false
	var mesh := KCad.tessellate(id)
	if mesh == null:
		m._say("The STEP file was read but could not be drawn: %s" % KCad.last_error())
		return false
	if _solid == null:
		_solid = MeshInstance3D.new()
		_solid.name = "build_step_solid"
		m.bld.root3.add_child(_solid)
	_solid.mesh = mesh
	close()
	m._say("Imported %s as a solid" % path.get_file())
	return true


## a card's picture: drawn, no files
class Art extends Control:
	var kind := ""
	var src: BuildChooseArt

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h), BuildChooseArt.BG, true)
		var tex: Texture2D = src.get_art(kind) if src != null else null
		if tex != null:   # the render, whole, centred (the strip is short: cropping would cut the subject)
			var ts := tex.get_size()
			var sc := minf(w / ts.x, h / ts.y)
			var r := Rect2((Vector2(w, h) - ts * sc) * 0.5, ts * sc)
			draw_texture_rect(tex, r, false)
			return
		var grey := Color(0.74, 0.76, 0.8)
		var dark := Color(0.5, 0.52, 0.57)
		var s := minf(w * 0.4, h * 0.8)
		var o := Vector2(w * 0.5 - s * 0.5, h * 0.5 - s * 0.45)
		match kind:
			"house":
				draw_rect(Rect2(o.x, o.y + s * 0.4, s, s * 0.6), grey, true)
				draw_colored_polygon(PackedVector2Array([o + Vector2(-s * 0.1, s * 0.4), o + Vector2(s * 0.5, 0), o + Vector2(s * 1.1, s * 0.4)]), dark)
				draw_rect(Rect2(o.x + s * 0.4, o.y + s * 0.62, s * 0.2, s * 0.38), Color(0.4, 0.42, 0.47), true)
			"part":
				draw_line(Vector2(w * 0.2, h * 0.75), Vector2(w * 0.8, h * 0.25), grey, 5.0)
				draw_line(Vector2(w * 0.62, h * 0.38), Vector2(w * 0.7, h * 0.52), dark, 4.0)
			"vehicle":
				draw_rect(Rect2(w * 0.25, h * 0.45, w * 0.5, h * 0.22), grey, true)
				draw_rect(Rect2(w * 0.35, h * 0.3, w * 0.3, h * 0.17), dark, true)
				draw_circle(Vector2(w * 0.35, h * 0.7), h * 0.1, Color(0.3, 0.3, 0.34))
				draw_circle(Vector2(w * 0.65, h * 0.7), h * 0.1, Color(0.3, 0.3, 0.34))
			"props":
				draw_rect(Rect2(w * 0.3, h * 0.35, s * 0.5, s * 0.5), grey, true)
				draw_circle(Vector2(w * 0.6, h * 0.6), s * 0.28, dark)
				draw_rect(Rect2(w * 0.7, h * 0.3, s * 0.18, s * 0.6), grey, true)
			"template":
				for i in 6:
					var r := Rect2(w * (0.28 + 0.15 * (i % 3)), h * (0.25 + 0.28 * (i / 3)), w * 0.12, h * 0.22)
					draw_rect(r, Color(0.2, 0.22, 0.28), true)
					draw_rect(r, YEL if i == 0 else dark, false, 1.5)
			"step":
				draw_rect(Rect2(w * 0.2, h * 0.2, w * 0.18, h * 0.6), Color(0.9, 0.9, 0.92), true)
				draw_rect(Rect2(w * 0.2, h * 0.42, w * 0.18, h * 0.16), YEL, true)
				draw_line(Vector2(w * 0.44, h * 0.5), Vector2(w * 0.58, h * 0.5), YEL, 3.0)
				draw_rect(Rect2(w * 0.64, h * 0.3, s * 0.45, s * 0.5), grey, true)
