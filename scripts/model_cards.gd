class_name ModelCards
extends Node
## MODEL TASK CARDS (Nick picked mockup B): "What do you want to do?" over the MODEL page, four big cards, each with a Start
## button that runs a tool the page already has: Change his shape (the BODY page's sliders), Edit part of the body (the
## fighter's body mesh opens, then Move / Scale / Smooth on the ribbon), Add armour / clothes (the armour panel on the body),
## Make a prop (a new 3D BUILDING project's BUILD page; a scene with unsaved work gets the test cube to model on instead, so
## nothing is thrown away). "Show all the tools" closes the cards; the ribbon stays above them all the time.
## WHEN: wanted() says it: Easy mode always (Easy has no MODEL page yet: the rule is ready for it), Expert only the first time
## the page opens (modelcards/seen in the settings file, written when the cards are closed). A later Expert open goes straight
## to the tools, as before. Like the page tour, a test never gets the cards by itself: auto is false until main says this is a
## real launch (or the test sets it). Mouse only: no key names in any text here.

const SEC := "modelcards"
const CARDS := [
	{"id": "shape", "title": "Change his shape", "text": "Height, weight, limbs and head size, with sliders."},
	{"id": "part", "title": "Edit part of the body", "text": "Click a body part to select it. Then move, scale or smooth it."},
	{"id": "armour", "title": "Add armour / clothes", "text": "Shoulder pads, chest plates, greaves or a jacket, fitted to the body."},
	{"id": "prop", "title": "Make a prop", "text": "A sword, a shield or a crate, modelled from scratch."},
]
const GAP := 18.0
const MAX_W := 280.0

var m: Node
var auto := false    # main: a real launch (a test turns it on itself)
var open := false
var root_box: Panel   # covers the page under the ribbon (the mesh panels sit behind it); _col is the content, placed in the clear view
var cards := {}      # id -> PanelContainer
var starts := {}     # id -> Button
var show_all: Button
var _row: HBoxContainer
var _arts := []
var _texts := []
var _titles := []
var _title: Label
var _sub: Label
var _col: VBoxContainer
var _last := Rect2()
var _settle := 0     # frames left of re-placing: the wrapped texts find their height a frame after their width is set


## the rule, pure: Easy always; Expert only when this is a real launch and the cards were never closed
static func wanted(easy_on: bool, auto_on: bool, seen_before: bool) -> bool:
	return easy_on or (auto_on and not seen_before)


func seen() -> bool:
	var cf := ConfigFile.new()
	cf.load(m.settings)
	return cf.get_value(SEC, "seen", false) == true


func _mark_seen() -> void:
	var cf := ConfigFile.new()
	cf.load(m.settings)
	if cf.get_value(SEC, "seen", false) != true:
		cf.set_value(SEC, "seen", true)
		cf.save(m.settings)


## main's _page_set, last thing: the cards come with MODEL when wanted
func page_opened(p: String) -> void:
	if p != "MODEL" or root_box == null:
		return
	if wanted(m.easy != null and m.easy.on, auto, seen()):
		show_cards()


func show_cards() -> void:
	open = true
	root_box.visible = true
	_settle = 4
	_place()
	if m.has_method("_mesh_hint_sync"):
		m._mesh_hint_sync()   # the "start with Test cube" hint steps aside while the cards are up


## closes the cards for good (Show all the tools, or a Start): the next MODEL open goes straight to the tools
func close() -> void:
	open = false
	if root_box != null:
		root_box.visible = false
	_mark_seen()


func _process(_dt: float) -> void:
	if not open:
		return
	if m.cur_page != "MODEL":
		open = false   # left the page: the cards go (they are not "seen": they were not answered)
		root_box.visible = false
		return
	var r: Rect2 = m.nav_clear_rect()
	if r != _last or _settle > 0:
		_settle = maxi(0, _settle - 1)
		_place()


func build(parent: Control) -> void:
	root_box = Panel.new()
	root_box.name = "model_cards"
	root_box.visible = false
	root_box.mouse_filter = Control.MOUSE_FILTER_STOP
	root_box.z_index = 1   # over the mesh panels (modifiers, materials) that sit behind the cards
	root_box.add_theme_stylebox_override("panel", _sb(Color(0.09, 0.1, 0.12, 0.97), 0, Color(0, 0, 0, 0)))
	parent.add_child(root_box)
	_col = VBoxContainer.new()
	_col.alignment = BoxContainer.ALIGNMENT_CENTER
	_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_col.add_theme_constant_override("separation", 10)
	root_box.add_child(_col)
	_title = _label("What do you want to do?", 30, Color(0.93, 0.94, 0.96))
	_title.name = "cards_title"
	_col.add_child(_title)
	_sub = _label("Pick one. The full tools are still in the ribbon above.", 15, Color(0.7, 0.73, 0.78))
	_col.add_child(_sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	_col.add_child(gap)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", int(GAP))
	_col.add_child(_row)
	for c in CARDS:
		_row.add_child(_card(c))
	show_all = Button.new()
	show_all.name = "cards_show_all"
	show_all.text = "Show all the tools"
	show_all.flat = true
	show_all.focus_mode = Control.FOCUS_NONE
	show_all.add_theme_color_override("font_color", Color(0.45, 0.72, 1.0))
	show_all.add_theme_color_override("font_hover_color", Color(0.7, 0.86, 1.0))
	show_all.add_theme_font_size_override("font_size", 15)
	show_all.tooltip_text = "close these cards and use the ribbon's tools"
	show_all.pressed.connect(close)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(show_all)
	_col.add_child(hb)


func _card(c: Dictionary) -> PanelContainer:
	var id: String = c["id"]
	var pc := PanelContainer.new()
	pc.name = "card_" + id
	pc.add_theme_stylebox_override("panel", _sb(Color(0.15, 0.16, 0.2), 12, Color(0.15, 0.16, 0.2)))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	pc.add_child(v)
	var art := CardArt.new()
	art.kind = id
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(art)
	_arts.append(art)
	var t := _label(String(c["title"]), 19, Color(0.95, 0.96, 0.98))
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_titles.append(t)
	v.add_child(t)
	var d := _label(String(c["text"]), 14, Color(0.74, 0.77, 0.82))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	_texts.append(d)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	var b := Button.new()
	b.name = "start_" + id
	b.text = "Start"
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.5))
	b.add_theme_font_size_override("font_size", 17)
	b.tooltip_text = String(c["text"])
	b.pressed.connect(_start.bind(id))
	v.add_child(b)
	cards[id] = pc
	starts[id] = b
	return pc


func _label(t: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if size >= 30:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	elif size == 15:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _sb(bg: Color, r: int, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(r)
	s.border_color = border
	s.set_border_width_all(1 if r > 0 else 0)
	s.content_margin_left = 14.0 if r > 0 else 0.0
	s.content_margin_right = 14.0 if r > 0 else 0.0
	s.content_margin_top = 12.0 if r > 0 else 0.0
	s.content_margin_bottom = 10.0 if r > 0 else 0.0
	return s


## the cover takes the page under the ribbon; the content sits in the clear view under the "Editing:" line, the row's width
## and the pictures' height following the room
func _place() -> void:
	var r: Rect2 = m.nav_clear_rect()
	_last = r
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var top := maxf(r.position.y, (m.ui_top_bar as Control).get_global_rect().end.y)   # under the ribbon's captions, never over them
	root_box.position = Vector2(0, top)
	root_box.size = Vector2(vs.x, maxf(120.0, r.end.y - top))
	var room := maxf(120.0, r.end.y - top - 44.0)
	var wide := vs.x - 48.0   # the whole width: the mesh page's side panels are behind the cover, so the clear view's own narrow width is not used
	var cw := clampf((wide - GAP * 3.0) / 4.0, 120.0, MAX_W)
	var small := room < 460.0
	var art_h := clampf(room - 330.0, 36.0, 150.0)
	_title.add_theme_font_size_override("font_size", 24 if small else 30)
	_sub.visible = room >= 330.0
	for c in cards.values():
		(c as PanelContainer).custom_minimum_size = Vector2(cw, 0)
	for a in _arts:
		(a as Control).custom_minimum_size = Vector2(cw - 28.0, art_h)
	for t in _texts + _titles:
		(t as Label).custom_minimum_size = Vector2(cw - 28.0, 0)
	for t in _texts:
		(t as Label).add_theme_font_size_override("font_size", 13 if small else 14)
	_col.position = Vector2(24.0, 44.0)
	_col.size = Vector2(wide, room)


# ---------------------------------------------------------------- the Starts: each reaches a tool that exists

func _start(id: String) -> void:
	close()
	match id:
		"shape":
			m._page_set("BODY")   # the BODY page's sliders (height, weight, limbs, head size); leaving MODEL applies any body edit
			m._say("Change his shape: drag the sliders on the left")
		"part":
			if not BaseBody.is_open(m):
				BaseBody.start(m)
			m._say("Edit part of the body: click a body part on the model, then pick Move, Scale or Smooth in the ribbon")
		"armour":
			var u := ArmourUI.of(m)
			if not (BaseBody.is_open(m) and u.panel != null and u.panel.visible):
				ArmourUI.toggle(m)
		"prop":
			_prop()


## Make a prop: no Part flow exists in BUILD yet, so BUILD itself: a new 3D BUILDING project (the start screen's own steps).
## A scene with unsaved work is never replaced from here: the test cube opens to model on, and Use in scene puts it in the set.
func _prop() -> void:
	if m.S.kind == "building":
		m._page_set("BUILD")
		return
	if m._clean == m._doc_key():
		m._new_scene()
		m.S.kind = "building"
		m._page_set("BUILD")
		m.bld.reset_view()
		m._refresh()
		return
	m._kmesh_edit_start()
	m._say("Make a prop: model it on the cube, then press Use in scene in the ribbon (your scene is kept)")


## a card's picture: drawn, no files (the sliders, the body with a part lit, the body with plates, a crate)
class CardArt extends Control:
	var kind := ""

	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h), Color(0.11, 0.12, 0.15), true)
		var cx := w * 0.5
		var grey := Color(0.78, 0.8, 0.84)
		match kind:
			"shape":
				var fills := [0.55, 0.4, 0.7, 0.3, 0.6]
				for i in 5:
					var y := h * (0.14 + 0.18 * i)
					draw_rect(Rect2(w * 0.12, y - 2, w * 0.76, 4), Color(0.25, 0.27, 0.32), true)
					draw_rect(Rect2(w * 0.12, y - 2, w * 0.76 * fills[i], 4), Color(1.0, 0.8, 0.2), true)
					draw_circle(Vector2(w * 0.12 + w * 0.76 * fills[i], y), 5.0, Color.WHITE)
			"part", "armour":
				var u := h / 100.0
				draw_circle(Vector2(cx, 14 * u), 8 * u, Color(0.45, 0.47, 0.52) if kind == "armour" else grey)
				draw_rect(Rect2(cx - 14 * u, 24 * u, 28 * u, 34 * u), Color(1.0, 0.8, 0.2) if kind == "armour" else grey, true)
				draw_rect(Rect2(cx - 14 * u, 58 * u, 28 * u, 14 * u), Color(0.45, 0.47, 0.52) if kind == "armour" else grey, true)
				draw_rect(Rect2(cx - 14 * u, 72 * u, 10 * u, 26 * u), grey, true)
				draw_rect(Rect2(cx + 4 * u, 72 * u, 10 * u, 26 * u), grey, true)
				var arm := Color(1.0, 0.8, 0.2) if kind == "armour" else grey
				draw_rect(Rect2(cx - 22 * u, 24 * u, 7 * u, 32 * u), Color(0.4, 0.7, 1.0) if kind == "part" else arm, true)
				draw_rect(Rect2(cx + 15 * u, 24 * u, 7 * u, 32 * u), arm, true)
			"prop":
				var s := minf(w, h) * 0.5
				var o := Vector2(cx - s * 0.5, h * 0.5 - s * 0.35)
				draw_rect(Rect2(o.x, o.y + s * 0.25, s, s * 0.75), Color(0.45, 0.33, 0.2), true)
				draw_colored_polygon(PackedVector2Array([o + Vector2(0, s * 0.25), o + Vector2(s * 0.3, 0), o + Vector2(s * 1.3, 0), o + Vector2(s, s * 0.25)]), Color(0.62, 0.46, 0.28))
				draw_colored_polygon(PackedVector2Array([o + Vector2(s, s * 0.25), o + Vector2(s * 1.3, 0), o + Vector2(s * 1.3, s * 0.75), o + Vector2(s, s)]), Color(0.36, 0.26, 0.16))
