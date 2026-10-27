class_name EasyPart
extends Node
## EASY PART: Easy's screen for the Part workspace (BUILD page, scripts/build/part_ui.gd; the record and the kernel are Expert's: scripts/build/part.gd).
## Mouse only: no key names in any text here. A big top bar (Home, the part's name, Undo, Redo, Easy | Expert), six big MAKE buttons, the panel
## "Change your sword" (template chips, 3-4 sliders, "Back to the first one", "Exact sizes? Use Expert"), amber drag dots on the model for the main
## sizes and one plain sentence for what just happened. Templates are parametric feature lists (scripts/build/part_templates.gd): a slider rewrites
## the template's own features, throttled to one rebuild every 100 ms while it is held and a final one on release. One undo step per slider
## release and per button. Expert opens the very same record.
## The six buttons are the simple version of Expert's tools: Draw shape (drag a box or a round shape on the grid), Pull it up (Extrude 2 cm of the
## newest shape, then a "How far" slider for it), Spin it round (Revolve), Round the edges (Fillet every edge it can), Cut a hole (a hole through the
## middle), Mirror (across the middle plane). A step that cannot be made says why in plain words and leaves no undo step.
## No CAD DLL: the buttons and sliders are greyed with the reason.

const PW := 318.0
const MAKE_H := 76.0
const REP_WORDS := {"count": ["Fewer", "More"], "gap": ["Closer", "Further apart"]}   # the Repeat it sliders' ends
const STICK_OPS := [["join", "Join", "Make the two pieces one solid"], ["cut", "Cut away", "Cut the second piece out of the first"], ["intersect", "Keep the overlap", "Keep only the part where the two pieces overlap"]]
const COLOUR_PRESETS := ["Glass", "Metal"]   # the two material chips after the five colour chips
const THROTTLE_MS := 100
const SKY := Color("#73BFFF")
const AMBER := Color("#FFC933")
const MAKES := [
	["draw", "Draw shape", "part_rectangle", "Drag on the grid to draw a box or a round shape"],
	["pull", "Pull it up", "part_extrude", "Make the newest shape into a solid, then say how far"],
	["spin", "Spin it round", "part_revolve", "Turn the newest shape round the middle line into a solid"],
	["round", "Round the edges", "part_fillet", "Soften the sharp edges"],
	["hole", "Cut a hole", "part_circle", "Cut a round hole through the middle"],
	["mirror", "Mirror that", "part_mirror", "Add a mirror copy on the other side of the middle line"],
	["curve", "Curvy line", "part_spline", "Drag a wobbly loop on the grid. Drag back to the start to close it"],
	["blend", "Blend two shapes", "part_loft", "Blend the last two shapes into one solid that runs from one to the other"],
	["split", "Cut in two", "part_split", "Cut the solid in two across its middle. Drag the slider to move the cut"],
	["colour", "Colour", "part_appearance", "Pick a colour for the solid, or Glass or Metal"],
	["repeat", "Repeat it", "part_pattern", "Copy the newest solid in a row, or round in a ring. Then move the sliders"],
	["stick", "Stick together", "part_combine", "Click two solid pieces in the view, then pick Join, Cut away or Keep the overlap"]]
const BAD_WORDS := ["ctrl", "shift", "alt+", "esc", "enter", "tab ", "delete", "backspace", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "spacebar", "return key"]

var pu: PartUI
var m: Node
var bar: PanelContainer
var title_l: Label
var undo_btn: Button
var redo_btn: Button
var use_scene_btn: Button
var whole_l: Label             # "Whole sword: N cm": the shape's biggest size, under the sliders (the blade slider is not the whole length)
var easy_btn: Button
var expert_btn: Button
var bar_row: HBoxContainer   # the bar's row: Part's "What to build" moves in here while Easy Part is on (part_ui._place_reopen)
var make_box: HBoxContainer
var make_btns := {}
var hint: PanelContainer
var hint_l: Label
var shape_box: PanelContainer
var shape_btns := {}
var repeat_box: PanelContainer   # Repeat it: Row / Ring and the How many and Gap sliders (for the last Repeat it step, rep_id)
var rep_btns := {}
var stick_box: PanelContainer    # Stick together: Join / Cut away / Keep the overlap, shown once two pieces are picked
var stick_btns := {}
var stick_picks: Array = []      # the body indices clicked in the view (the first = the target, the second = the tool)
var rep_id := ""                 # the last Repeat it step's feature id ("" = none)
var rep_rows := []               # the two slider rows of the Repeat it box (see _make_row)
var colour_box: PanelContainer   # Colour: the five colour chips and Glass / Metal, under the MAKE row (armed "colour")
var panel: PanelContainer
var panel_vb: VBoxContainer   # the panel's column: it scrolls inside the panel when the window is short (1280 x 720)
var panel_title: Label
var chips := {}
var rows_vb: VBoxContainer
var rows := []                 # [{"key", "slider", "pill", "kind": "tpl" | "tweak", "def": row dict}]
var give_btn: Button
var back_btn: Button
var use_btn: Button
var status: PanelContainer
var status_l: Label
var dots: Control
var armed := ""                # "draw" while the next drag draws a shape
var shape := "box"
var msg := ""                  # the sentence of the last press, until the next one
var tweak := {}                # the last step's own slider: {"id", "ent", "field", "label", "unit", "lo", "hi", "step", "scale"}
var _pending := {}
var _dirty := false
var _last_ms := 0
var _drag := {}                # an amber dot in hand: {"k", "mouse", "val", "dir", "pxmm", "gain"}
var _draft := {}               # a shape being drawn: {"a": Vector2 mm, "b": Vector2 mm}
var _edit_n := -1
var _edit_before := ""
var _sig := ""
var _rows_sig := ""
var _hover := ""
var _was := false
var _compact := false
var flushes := 0                # rebuilds made by sliders and dots (the tests count them against the clock)


func build(root: Control) -> void:
	name = "easy_part"
	bar = PanelContainer.new()
	bar.name = "easypart_bar"
	bar.theme_type_variation = "TopBar"
	bar.add_theme_stylebox_override("panel", _style(Color(0.09, 0.1, 0.13), 0, 6))   # opaque: Expert's ribbon must not show through
	bar.anchor_right = 1.0
	bar.offset_bottom = m.TOP_H
	bar.visible = false
	root.add_child(bar)
	var row := HBoxContainer.new()
	row.name = "easypart_row"
	row.add_theme_constant_override("separation", 6)
	bar.add_child(row)
	bar_row = row
	var home_b: Button = m._home_button()
	home_b.custom_minimum_size = Vector2(110, m.TOP_H - 12)
	home_b.add_theme_font_size_override("font_size", 15)
	row.add_child(home_b)
	title_l = Label.new()
	title_l.name = "easypart_title"
	title_l.add_theme_font_size_override("font_size", 20)
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title_l)
	undo_btn = _bar_btn("Undo", "Take back the last change", func(): m._undo())
	redo_btn = _bar_btn("Redo", "Put back what Undo took back", func(): m._redo())
	use_scene_btn = _bar_btn("Use in a scene", "Put this part into the scene as a prop", _use_scene)
	use_scene_btn.custom_minimum_size.x = 150.0
	row.add_child(undo_btn)
	row.add_child(redo_btn)
	row.add_child(use_scene_btn)
	give_btn = _bar_btn("Give to fighter", "Give it to the fighter: the fighter holds this shape as his weapon, with its size and weight (PartWeapon)", func(): m.give_part_weapon(_rec()))   # one undo step
	give_btn.name = "easypart_give"
	give_btn.custom_minimum_size = Vector2(170, m.TOP_H - 12)
	row.add_child(give_btn)
	easy_btn = _bar_btn("Easy", "Sliders and big buttons", func(): pass)
	easy_btn.toggle_mode = true
	easy_btn.button_pressed = true
	expert_btn = _bar_btn("Expert", "The same part with every tool and exact numbers", func(): to_expert())
	expert_btn.toggle_mode = true
	row.add_child(easy_btn)
	row.add_child(expert_btn)
	# the six MAKE buttons
	make_box = HBoxContainer.new()
	make_box.name = "easypart_make"
	make_box.add_theme_constant_override("separation", 8)
	make_box.visible = false
	root.add_child(make_box)
	for mk in MAKES:
		var b := Button.new()
		b.name = "easypart_make_" + String(mk[0])
		b.text = String(mk[1])
		b.focus_mode = Control.FOCUS_NONE
		b.icon = Icons.sized(String(mk[2]), 26)
		b.expand_icon = false
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.add_theme_font_size_override("font_size", 14)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(110, MAKE_H)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = String(mk[3])
		b.toggle_mode = mk[0] in ["draw", "curve", "colour", "stick"]
		b.pressed.connect(_make.bind(String(mk[0])))
		make_box.add_child(b)
		make_btns[mk[0]] = b
	# the one sentence, and the shape choice that goes with Draw shape
	hint = _pill("easypart_hint", 19)
	hint_l = hint.get_child(0)
	root.add_child(hint)
	shape_box = PanelContainer.new()
	shape_box.name = "easypart_shapes"
	shape_box.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.92), 10, 6))
	shape_box.visible = false
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 6)
	shape_box.add_child(sh)
	for s in [["box", "Box"], ["round", "Round"]]:
		var b := Button.new()
		b.name = "easypart_shape_" + String(s[0])
		b.text = String(s[1])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(90, 40)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(func(): shape = String(s[0]); _sync_shape())
		sh.add_child(b)
		shape_btns[s[0]] = b
	root.add_child(shape_box)
	colour_box = _colour_box()
	root.add_child(colour_box)
	repeat_box = _repeat_box()
	root.add_child(repeat_box)
	stick_box = _stick_box()
	root.add_child(stick_box)
	# the panel
	panel = PanelContainer.new()
	panel.name = "easypart_panel"
	panel.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.95), 12, 12))
	panel.visible = false
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.name = "easypart_panel_vb"
	v.add_theme_constant_override("separation", 6)
	panel_vb = v
	var sc := ScrollContainer.new()   # the panel's column scrolls inside the panel when it is taller than the room (a Where-to-cut row adds one)
	sc.name = "easypart_panel_scroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(sc)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	panel_title = Label.new()
	panel_title.name = "easypart_panel_title"
	panel_title.add_theme_font_size_override("font_size", 22)
	v.add_child(panel_title)
	var cr := HFlowContainer.new()
	cr.name = "easypart_chips"
	cr.add_theme_constant_override("h_separation", 4)
	cr.add_theme_constant_override("v_separation", 4)
	v.add_child(cr)
	for t in PartTemplates.ORDER:
		var b := Button.new()
		b.name = "easypart_chip_" + t
		b.text = String(PartTemplates.T[t]["title"])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 34)
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_chip.bind(t))
		cr.add_child(b)
		chips[t] = b
	rows_vb = VBoxContainer.new()
	rows_vb.name = "easypart_rows"
	rows_vb.add_theme_constant_override("separation", 4)
	v.add_child(rows_vb)
	whole_l = Label.new()
	whole_l.name = "easypart_whole"
	whole_l.add_theme_font_size_override("font_size", 16)
	v.add_child(whole_l)
	var foot := HFlowContainer.new()
	foot.name = "easypart_foot"
	foot.add_theme_constant_override("separation", 8)
	v.add_child(foot)
	back_btn = Button.new()
	back_btn.name = "easypart_back"
	back_btn.text = "Reset"   # (was "Back to the first one": the foot wrapped to two rows and the panel ran past the clear view at 1280 x 720)
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.custom_minimum_size = Vector2(0, 34)
	back_btn.add_theme_font_size_override("font_size", 14)
	back_btn.tooltip_text = "Put every size back to how this shape started"
	back_btn.pressed.connect(_back)
	foot.add_child(back_btn)
	use_btn = Button.new()
	use_btn.name = "easypart_use_expert"
	use_btn.text = "Exact sizes? Use Expert"
	use_btn.flat = true
	use_btn.focus_mode = Control.FOCUS_NONE
	use_btn.add_theme_font_size_override("font_size", 14)
	use_btn.add_theme_color_override("font_color", SKY)
	use_btn.tooltip_text = "Open this same part in Expert, where every size can be typed"
	use_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	use_btn.pressed.connect(to_expert)
	foot.add_child(use_btn)
	status = _pill("easypart_status", 15)
	status_l = status.get_child(0)
	root.add_child(status)
	dots = Control.new()
	dots.name = "easypart_dots"
	dots.set_anchors_preset(Control.PRESET_FULL_RECT)
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dots.draw.connect(_draw_dots)
	dots.visible = false
	root.add_child(dots)


## COLOUR: the five colour chips (Part.LOOK_CHIPS) and Glass / Metal: one button each, the same look-numbers Expert's Appearance uses
func _colour_box() -> PanelContainer:
	var box := PanelContainer.new()
	box.name = "easypart_colour"
	box.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.92), 10, 6))
	box.visible = false
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	box.add_child(h)
	for chip in Part.LOOK_CHIPS:
		var b := _colour_btn(String(chip[0]).to_lower(), String(chip[0]), chip[1] as Color)
		b.pressed.connect(_paint.bind(String(chip[0]), chip[1] as Color, "Paint"))
		h.add_child(b)
	for pr in COLOUR_PRESETS:
		var b := _colour_btn(pr.to_lower(), pr, Color(0.85, 0.88, 0.92, 0.5) if pr == "Glass" else Color(0.7, 0.72, 0.76))
		b.pressed.connect(_paint.bind(pr, Color.WHITE, pr))
		h.add_child(b)
	return box


## REPEAT IT: Row or Ring, then How many (2..12 copies, the original counts) and Gap (cm between the copies). Its sliders write the Part pattern
## step fields (count, mm, kind): the same replay as Expert Pattern
func _repeat_box() -> PanelContainer:
	var box := PanelContainer.new()
	box.name = "easypart_repeat"
	box.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.92), 10, 6))
	box.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	box.add_child(vb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	vb.add_child(h)
	for md in [["row", "Row", false], ["ring", "Ring", true]]:
		var tip := "Copies in a straight row" if not md[2] else "Copies round the up axis, in a full turn"
		var b := _big_btn("easypart_rep_" + String(md[0]), String(md[1]), tip, _rep_mode.bind(bool(md[2])))
		b.toggle_mode = true
		h.add_child(b)
		rep_btns[md[0]] = b
	rep_rows.append(_make_row("How many", 2.0, 12.0, 1.0, REP_WORDS["count"], "rep", "count", "copies", vb))
	rep_rows.append(_make_row("Gap", 0.5, 30.0, 0.5, REP_WORDS["gap"], "rep", "gap", "cm", vb))
	return box


## STICK TOGETHER: the three big buttons, shown once two pieces are picked in the view
func _stick_box() -> PanelContainer:
	var box := PanelContainer.new()
	box.name = "easypart_stick"
	box.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.92), 10, 6))
	box.visible = false
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	box.add_child(h)
	for so in STICK_OPS:
		var b := _big_btn("easypart_stick_" + String(so[0]), String(so[1]), String(so[2]), _stick.bind(String(so[0]), String(so[1])))
		b.custom_minimum_size = Vector2(150, 44)
		h.add_child(b)
		stick_btns[so[0]] = b
	return box


func _big_btn(nm: String, txt: String, tip: String, f: Callable) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = txt
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(110, 44)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(f)
	return b


func _colour_btn(key: String, txt: String, c: Color) -> Button:
	var b := Button.new()
	b.name = "easypart_colour_" + key
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(92, 44)
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", Color(0.08, 0.08, 0.1))
	var st := StyleBoxFlat.new()
	st.bg_color = c
	st.set_corner_radius_all(8)
	for sn in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(sn, st)
	return b


func _style(c: Color, r: int, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(r)
	s.set_content_margin_all(margin)
	return s


func _pill(nm: String, fs: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = nm
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.visible = false
	p.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.92), 10, 10))
	var l := Label.new()
	l.name = nm + "_text"
	l.add_theme_font_size_override("font_size", fs)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


func _bar_btn(t: String, tip: String, f: Callable) -> Button:
	var b := Button.new()
	b.name = "easypart_btn_" + t.to_lower()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(96, m.TOP_H - 12)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(func(): m._step_hint = t; f.call())
	return b


# ---------------------------------------------------------------- the state

func active() -> bool:
	return m != null and pu != null and pu.shows() and pu.easy


func _rec() -> Dictionary:
	return m.S.part


func _tpl() -> String:
	return String(_rec().get("easy", {}).get("t", ""))


func _nm() -> String:
	var t := _tpl()
	return String(PartTemplates.T[t]["title"]).to_lower() if t != "" else "part"


## switch the screen on (from PartUI.open_easy)
func entered() -> void:
	armed = ""
	msg = ""
	tweak = {}
	rep_id = ""
	stick_picks = []
	_draft = {}
	_drag = {}
	_sig = ""
	_rows_sig = ""
	frame()


## the model in the clear part of the view (left of the panel), as Expert's own framing, then moved off the panel
func frame() -> void:
	pu._view_model()
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var span := 2.0 * float(m.dist) * tan(deg_to_rad(m.cam.fov * 0.5)) * vs.x / vs.y
	m.dist = float(m.dist) * 1.45
	span *= 1.45
	m.target += m.cam.global_basis.x * (span * (PW * 0.5 + 8.0) / vs.x)
	m._cam()
	m._say("")


func to_expert() -> void:
	armed = ""
	_flush_if_dirty()
	if m.easy != null and m.easy.on:
		m.easy.set_on(false)
	pu.easy = false
	pu.bu.sync()
	m._fit_top.call_deferred()


func _say(t: String) -> void:
	msg = t


func _refuse_no_dll() -> bool:
	return not Part.available()


# ---------------------------------------------------------------- undo steps

func _begin(label: String) -> void:
	m._step_hint = label
	m._push_undo()
	_edit_n = m.undo.size()
	_edit_before = JSON.stringify(_rec())


## the step ends; a step that changed nothing is taken back out
func _end() -> void:
	if _edit_n >= 0 and m.undo.size() == _edit_n and JSON.stringify(_rec()) == _edit_before:
		m._drop_undo()
	_edit_n = -1


# ---------------------------------------------------------------- sliders and their rows

func _set_value(row: Dictionary, v: float, final: bool) -> void:
	if row["kind"] == "tpl":
		_pending[row["key"]] = v * 10.0   # the slider says cm, the record mm
	elif row["kind"] == "rep":
		_apply_rep(row, v)
	else:
		_apply_tweak(v)
	_dirty = true
	if final:
		_flush()


func _apply_tweak(v: float) -> void:
	var f := Part.feature(_rec(), String(tweak["id"]))
	if f.is_empty():
		return
	var val: float = v * float(tweak.get("scale", 1.0))
	if tweak.has("ent"):
		f["ents"][int(tweak["ent"])][tweak["field"]] = val
	else:
		f[tweak["field"]] = val


## the Repeat it sliders: How many = the copies; Gap = cm between the copies (the spacing = the body width + the gap, in the record mm)
func _apply_rep(row: Dictionary, v: float) -> void:
	var f := Part.feature(_rec(), rep_id)
	if f.is_empty():
		return
	if String(row["key"]) == "count":
		f["count"] = int(roundf(v))
	else:
		f["gap"] = v * 10.0
		f["mm"] = float(f.get("w", 10.0)) + v * 10.0


func _flush_if_dirty() -> void:
	if _dirty:
		_flush()


func _flush() -> void:
	flushes += 1
	_dirty = false
	_last_ms = Time.get_ticks_msec()
	if not _pending.is_empty():
		PartTemplates.retemplate(_rec(), _pending)
		_pending = {}
	pu.sync()
	m.part_weapon_changed(_rec())   # a held Part weapon takes the new numbers and shape
	_values_sync()


func _on_slider_value(v: float, row: Dictionary) -> void:
	var s: HSlider = row["slider"]
	if not bool(row.get("held", false)):
		_begin("Change " + String(row["label"]))   # a click on the track or a nudge: its own step
		_set_value(row, v, true)
		_end()
		return
	_set_value(row, v, false)
	_pill_text(row, v)


func _on_slider_start(row: Dictionary) -> void:
	row["held"] = true
	_begin("Change " + String(row["label"]))


func _on_slider_end(_changed: bool, row: Dictionary) -> void:
	row["held"] = false
	_set_value(row, (row["slider"] as HSlider).value, true)
	_end()


func _fmt(v: float, unit: String) -> String:
	if unit == "deg":
		return "%d degrees" % int(roundf(v))
	if unit == "copies":
		return "%d copies" % int(roundf(v))
	return "%s cm" % str(snappedf(v, 0.1))


func _pill_text(row: Dictionary, v: float) -> void:
	(row["pill"] as Label).text = _fmt(v, String(row["unit"]))


func _knob() -> ImageTexture:
	var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	for y in 24:
		for x in 24:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(12, 12))
			img.set_pixel(x, y, Color(1, 0.79, 0.2, clampf(12.0 - d, 0.0, 1.0)) if d > 6.5 else Color(1, 0.79, 0.2, clampf(12.0 - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _make_row(label: String, lo: float, hi: float, step: float, words: Array, kind: String, key: String, unit: String, into: Control = null) -> Dictionary:
	var v := VBoxContainer.new()
	v.name = "easypart_row_" + key
	v.add_theme_constant_override("separation", 0)
	var top := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 18)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(l)
	var pill := Label.new()
	pill.name = "easypart_pill_" + key
	pill.add_theme_font_size_override("font_size", 16)
	pill.add_theme_stylebox_override("normal", _style(Color(0.17, 0.18, 0.22), 14, 6))
	top.add_child(pill)
	v.add_child(top)
	var s := HSlider.new()
	s.name = "easypart_slider_" + key
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size = Vector2(0, 24)
	var tr := _style(Color(0.2, 0.21, 0.26), 4, 0)
	tr.content_margin_top = 4
	tr.content_margin_bottom = 4
	var fill := _style(AMBER, 4, 0)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	s.add_theme_stylebox_override("slider", tr)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var kn := _knob()
	s.add_theme_icon_override("grabber", kn)
	s.add_theme_icon_override("grabber_highlight", kn)
	s.add_theme_icon_override("grabber_disabled", kn)
	v.add_child(s)
	var w := HBoxContainer.new()
	w.name = "easypart_words_" + key
	for i in 2:
		var wl := Label.new()
		wl.text = String(words[i])
		wl.add_theme_font_size_override("font_size", 13)
		wl.modulate = Color(1, 1, 1, 0.6)
		wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		w.add_child(wl)
	v.add_child(w)
	(into if into != null else rows_vb).add_child(v)
	var row := {"key": key, "slider": s, "pill": pill, "kind": kind, "unit": unit, "label": label, "box": v, "words": w}
	s.value_changed.connect(_on_slider_value.bind(row))
	s.drag_started.connect(_on_slider_start.bind(row))
	s.drag_ended.connect(_on_slider_end.bind(row))
	return row


## the rows follow the record: the template's own numbers (cm) and the last step's slider
func _rows_sync() -> void:
	var t := _tpl()
	var sig := "%s|%s|%s" % [t, JSON.stringify(tweak.get("id", "")), _compact]
	if sig == _rows_sig:
		return
	_rows_sig = sig
	for c in rows_vb.get_children():
		rows_vb.remove_child(c)
		c.queue_free()
	rows = []
	if t != "":
		for d in PartTemplates.T[t]["params"]:
			var r := _make_row(String(d["label"]), float(d["lo"]) / 10.0, float(d["hi"]) / 10.0, float(d["step"]) / 10.0, d["words"], "tpl", String(d["k"]), "cm")
			rows.append(r)
	if not tweak.is_empty():
		var tw: Dictionary = tweak
		var r := _make_row(String(tw["label"]), float(tw["lo"]), float(tw["hi"]), float(tw["step"]), tw.get("words", ["Less", "More"]), "tweak", "last", String(tw["unit"]))
		rows.append(r)
	for r in rows:
		(r["words"] as Control).visible = not _compact
	_values_sync()


func _tweak_value() -> float:
	var f := Part.feature(_rec(), String(tweak["id"]))
	if f.is_empty():
		return float(tweak["lo"])
	var raw: float = float(f["ents"][int(tweak["ent"])][tweak["field"]]) if tweak.has("ent") else float(f.get(tweak["field"], 0.0))
	return raw / float(tweak.get("scale", 1.0))


func _values_sync() -> void:
	var e: Dictionary = _rec().get("easy", {})
	var off := not Part.available()
	for r in rows:
		var s: HSlider = r["slider"]
		var v := 0.0
		if r["kind"] == "tpl":
			v = float(e.get("p", {}).get(r["key"], 0.0)) / 10.0
		else:
			v = _tweak_value()
		if not bool(r.get("held", false)):
			s.set_value_no_signal(v)
		_pill_text(r, s.value)
		m._grey(s, Part.why_not() if off else "")
	_rep_sync()
	whole_l.visible = _tpl() != ""
	if whole_l.visible:   # the whole shape's biggest size (the replay's box, m -> cm): the sliders move one part of it
		var bb: AABB = pu.res.get("aabb", AABB())
		var big := maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
		whole_l.text = "Whole %s: %d cm" % [_nm(), roundi(big * 100.0)] if big > 0.0 else "Whole %s: not made yet" % _nm()


# ---------------------------------------------------------------- chips, Back to the first one

func _chip(t: String) -> void:
	if _tpl() == t or not Part.available():
		_chips_sync()
		return
	armed = ""
	_flush_if_dirty()
	m._step_hint = "Start a " + t
	m._push_undo()
	m.S.part = PartTemplates.make(t)
	tweak = {}
	pu.upto = -1
	pu.sync()
	frame()
	_say("%s %s: move a slider or drag an amber dot" % ["An" if t.substr(0, 1) in "aeiou" else "A", t])


func _chips_sync() -> void:
	for t in chips:
		(chips[t] as Button).set_pressed_no_signal(t == _tpl())
		m._grey(chips[t], Part.why_not() if not Part.available() else "")


func _back() -> void:
	var e: Dictionary = _rec().get("easy", {})
	if e.is_empty() or not Part.available():
		return
	_begin("Back to the first one")
	PartTemplates.retemplate(_rec(), PartTemplates.defaults(String(e["t"])))
	_end()
	pu.sync()
	_values_sync()
	_say("Back to the first one")


# ---------------------------------------------------------------- the six buttons

## "Use in a scene": the part becomes a prop of the set (BuildUI.use_part, one undo step); the page goes to STAGE
func _use_scene() -> void:
	armed = ""
	_flush_if_dirty()
	pu.bu.use_part()

func _make(which: String) -> void:
	if not Part.available():
		_say(Part.why_not())
		return
	_flush_if_dirty()
	if which != "repeat":
		rep_id = ""
	if which == "stick":
		stick_picks = []
		if armed == "stick":
			armed = ""
			_say("")
			return
		armed = ""
		if int(pu.res.get("bodies", 0)) < 2:
			_say("Make two solid pieces first, then stick them together")
			return
		armed = "stick"
		_say(_arm_words("stick"))
		return
	if which == "draw" or which == "curve" or which == "colour":
		armed = "" if armed == which else which
		_draft = {}
		_say(_arm_words(armed))
		return
	armed = ""
	var snap := _rec().duplicate(true)
	var label := String((MAKES.filter(func(x): return x[0] == which)[0])[1])
	_begin(label)
	var rec := pu._ensure()
	var why := ""
	match which:
		"pull":
			why = _pull(rec)
		"spin":
			why = _spin(rec)
		"round":
			why = _round(rec)
		"hole":
			why = _hole(rec)
		"mirror":
			why = _mirror(rec)
		"blend":
			why = _blend(rec)
		"split":
			why = _cut(rec)
		"repeat":
			why = _repeat(rec)
	if why != "":
		m.S.part = snap   # nothing changes: the step taken a moment ago goes back out
		m._drop_undo()
		_edit_n = -1
		_say(why)
	else:
		_end()
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_values_sync()


func _arm_words(a: String) -> String:
	match a:
		"stick":
			if stick_picks.size() == 0:
				return "Click the first solid piece in the view"
			if stick_picks.size() == 1:
				return "Now click the second solid piece"
			return "Pick Join, Cut away or Keep the overlap"
		"draw":
			return "Drag on the grid to draw a shape"
		"curve":
			return "Drag a wobbly loop on the grid. Drag back to the start to close it"
		"colour":
			return "Pick a colour below, or Glass or Metal"
	return ""


func _last_error(rec: Dictionary, fid: String) -> String:
	return String(Part.replay(rec)["errors"].get(fid, ""))


func _pull(rec: Dictionary) -> String:
	var sid := Part.profile_sketch(rec)
	if sid == "" or Part.sketch_used(rec, sid):
		return "Draw a shape first, then pull it up"
	var sk := Part.feature(rec, sid)
	var ext := 0.0
	for e in sk["ents"]:
		for k in ["a", "b", "c"]:
			if e.has(k):
				ext = maxf(ext, maxf(absf(float(e[k][0])), absf(float(e[k][1]))))
	var f := Part.new_feature(rec, "extrude", {"sketch": sid, "dist": 20.0, "both": false, "op": "join"})
	rec["features"].append(f)
	var err := _last_error(rec, String(f["id"]))
	if err != "":
		return "That shape is not closed, so it cannot be pulled up"
	tweak = {"id": f["id"], "field": "dist", "label": "How far", "unit": "cm", "lo": 0.2, "hi": 40.0, "step": 0.2, "scale": 10.0, "words": ["Flatter", "Taller"]}
	_say("Pulled up 2 cm: use the slider to change it")
	return ""


func _spin(rec: Dictionary) -> String:
	var sid := Part.profile_sketch(rec)
	if sid == "" or Part.sketch_used(rec, sid):
		return "Draw a shape first, then spin it round"
	var f := Part.new_feature(rec, "revolve", {"sketch": sid, "axis": "x", "deg": 360.0, "op": "join"})
	rec["features"].append(f)
	if _last_error(rec, String(f["id"])) != "":
		return "A shape that crosses the middle line cannot be spun: draw it on one side"
	tweak = {"id": f["id"], "field": "deg", "label": "How far round", "unit": "deg", "lo": 10.0, "hi": 360.0, "step": 5.0, "scale": 1.0, "words": ["A bit", "All the way"]}
	_say("Spun all the way round: use the slider for less")
	return ""


func _round(rec: Dictionary) -> String:
	var res := Part.replay(rec, -1, {"edges": true})
	if int(res["bodies"]) == 0:
		return "Make something solid first"
	var es: Array = res["edges"]
	var aabb: AABB = res["aabb"]
	var small := minf(aabb.size.x, minf(aabb.size.y, aabb.size.z)) / Part.MM
	var longest := 0.0
	for e in es:
		longest = maxf(longest, float(e["len"]))
	for attempt in [[1.0, 0.0], [0.5, 0.0], [0.5, 0.2]]:
		var r := clampf(small * 0.01 * float(attempt[0]), 0.5, 6.0)
		var list := []
		for e in es:
			if int(e["body"]) == 0 and float(e["len"]) >= longest * float(attempt[1]) and float(e["len"]) / Part.MM > r * 2.5:
				list.append(Part.describe(e))
		if list.is_empty():
			continue
		var f := Part.new_feature(rec, "fillet", {"body": 0, "r": snappedf(r, 0.1), "edges": list})
		rec["features"].append(f)
		if _last_error(rec, String(f["id"])) == "":
			tweak = {"id": f["id"], "field": "r", "label": "How round", "unit": "cm", "lo": 0.1, "hi": 1.0, "step": 0.1, "scale": 10.0, "words": ["Barely", "Very round"]}
			_say("Edges rounded: use the slider for more or less")
			return ""
		rec["features"].pop_back()
	# a thin part (the sword's blade: 7 mm across the spine, edges 0.4 mm) cannot take the 0.5 mm floor on every edge: round the edges that
	# can take a smaller radius and skip the rest. Each edge is tried with the ones already kept, so the feature that is added has no error
	for r in [0.5, 0.3, 0.1]:
		var good := []
		for e in es:
			if int(e["body"]) == 0 and float(e["len"]) / Part.MM > r * 2.5:
				var trial := good.duplicate()
				trial.append(Part.describe(e))
				if _try_fillet(rec, r, trial) == "":
					good = trial
		if good.is_empty():
			continue
		var f := Part.new_feature(rec, "fillet", {"body": 0, "r": snappedf(r, 0.1), "edges": good})
		rec["features"].append(f)
		tweak = {"id": f["id"], "field": "r", "label": "How round", "unit": "cm", "lo": 0.1, "hi": 1.0, "step": 0.1, "scale": 10.0, "words": ["Barely", "Very round"]}
		_say("Edges rounded: use the slider for more or less")
		return ""
	return "These edges are too small or too crowded to round"


## the error (or "") of a fillet of these edges, tried on the end of the record without keeping it: the id is one nothing else uses
func _try_fillet(rec: Dictionary, r: float, edges: Array) -> String:
	rec["features"].append({"t": "fillet", "id": "try", "name": "Fillet", "body": 0, "r": snappedf(r, 0.1), "edges": edges})
	var err := String(Part.replay(rec)["errors"].get("try", ""))
	rec["features"].pop_back()
	return err


func _hole(rec: Dictionary) -> String:
	var res := Part.replay(rec)
	if int(res["bodies"]) == 0:
		return "Make something solid first"
	var bb: AABB = res["aabb"]
	var c := bb.get_center() / Part.MM
	var r := clampf(minf(bb.size.x, bb.size.y) / Part.MM * 0.12, 10.0, 40.0)   # the radius in mm: a hole 2 to 8 cm across
	var s := Part.new_feature(rec, "sketch", {"plane": "front", "ents": [{"k": "circle", "c": Part.arr2(Vector2(c.x, c.y)), "r": snappedf(r, 0.5)}], "dims": []})
	rec["features"].append(s)
	var f := Part.new_feature(rec, "extrude", {"sketch": s["id"], "dist": snappedf(bb.size.z / Part.MM + 20.0, 1.0), "both": true, "op": "cut"})
	rec["features"].append(f)
	var before := float(res["volume"])
	var after := float(Part.replay(rec)["volume"])
	if after >= before - 1e-12:
		return "The hole would miss the shape: nothing was cut"
	tweak = {"id": s["id"], "ent": 0, "field": "r", "label": "Hole size", "unit": "cm", "lo": 0.6, "hi": 16.0, "step": 0.1, "scale": 5.0, "words": ["Smaller", "Bigger"]}   # the slider is the hole's WIDTH (cm): radius mm = width cm * 5
	_say("A hole through the middle: use the slider for its size")
	return ""


func _mirror(rec: Dictionary) -> String:
	var res := Part.replay(rec)
	if int(res["bodies"]) == 0:
		return "Make something solid first"
	var f := Part.new_feature(rec, "mirror", {"plane": "right", "op": "join"})
	rec["features"].append(f)
	if _last_error(rec, String(f["id"])) != "":
		return "That shape cannot be mirrored"
	tweak = {}
	_say("Mirrored across the middle line")
	return ""


## BLEND TWO SHAPES: a loft of the two last sketches (Part's "loft" feature, the same one Expert's Loft makes). Two shapes on the same plane
## cannot be blended, so the newer one moves 40 mm behind the older one (an offset plane, in the same undo step)
func _blend(rec: Dictionary) -> String:
	var sks: Array = []
	for f in rec.get("features", []):
		if f["t"] == "sketch":
			sks.append(f)
	if sks.size() < 2:
		return "Draw two shapes first, then blend them"
	var a: Dictionary = sks[sks.size() - 2]
	var b: Dictionary = sks[sks.size() - 1]
	if String(a["plane"]) == String(b["plane"]):
		if not (String(a["plane"]) in Part.PLANES):
			return "Those two shapes sit on the same plane: draw them on different planes"
		var pl := Part.new_feature(rec, "plane", {"from": String(a["plane"]), "mm": 40.0})
		rec["features"].insert(Part.index_of(rec, String(b["id"])), pl)
		b["plane"] = String(pl["id"])
	var f := Part.new_feature(rec, "loft", {"sketches": [a["id"], b["id"]], "ruled": true, "op": "join"})
	rec["features"].append(f)
	if _last_error(rec, String(f["id"])) != "":
		return "Those two shapes cannot be blended into one solid"
	tweak = {}
	_say("Blended the two last shapes into one solid")
	return ""


## CUT IN TWO: a split across the middle of the solid's longest side (Part's "split" feature, the one Expert's Split makes). The slider
## moves the cut along that side: its step is the split, its field the offset in mm (the slider says cm)
func _cut(rec: Dictionary) -> String:
	var res := Part.replay(rec)
	if int(res["bodies"]) == 0:
		return "Make something solid first"
	var bb: AABB = res["aabb"]
	var ax := 0
	if bb.size.y > bb.size.x and bb.size.y >= bb.size.z:
		ax = 1
	elif bb.size.z > bb.size.x and bb.size.z > bb.size.y:
		ax = 2
	var lo_mm: float = bb.position[ax] / Part.MM
	var hi_mm: float = bb.end[ax] / Part.MM
	var mid := snappedf((lo_mm + hi_mm) * 0.5, 1.0)
	var f := Part.new_feature(rec, "split", {"plane": ["right", "top", "front"][ax], "at": mid})
	rec["features"].append(f)
	if _last_error(rec, String(f["id"])) != "" or int(Part.replay(rec)["bodies"]) < 2:
		return "The cut would miss the solid: nothing was cut"
	tweak = {"id": f["id"], "field": "at", "label": "Where to cut", "unit": "cm", "lo": snappedf(lo_mm * 0.1 + 0.2, 0.1), "hi": snappedf(hi_mm * 0.1 - 0.2, 0.1), "step": 0.1, "scale": 10.0, "words": ["Toward one end", "Toward the other end"]}
	_say("Cut in two across the middle: drag the slider to move the cut")
	return ""


## COLOUR: one appear step per body (Part's "appear" feature, the look Expert's Appearance writes), all in ONE undo step. A material
## (Glass, Metal) keeps each body's own colour; a colour chip sets Paint's numbers with that colour
func _paint(label: String, c: Color, preset: String) -> void:
	armed = ""
	if not Part.available():
		_say(Part.why_not())
		return
	_flush_if_dirty()
	var nb := int(pu.res.get("bodies", 0))
	if nb == 0:
		_say("Make something solid first, then pick a colour")
		return
	_begin("Colour")
	var rec := pu._ensure()
	var looks: Array = pu.res.get("body_looks", [])
	var nums: Dictionary = Part.LOOK_PRESETS.get(preset, Part.LOOK_DEFAULT)
	for i in nb:
		var cur := Part.look_at(looks, i)
		var col: Color = cur["c"] if COLOUR_PRESETS.has(preset) else c
		var n := Part.count_of(rec, "appear") + 1
		var f := Part.new_feature(rec, "appear", {"name": "Appearance%d" % n, "body": i, "preset": preset,
			"color": [col.r, col.g, col.b], "rough": float(nums["rough"]), "metal": float(nums["metal"]), "alpha": float(nums["alpha"])})
		(rec["features"] as Array).append(f)
	_end()
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_values_sync()
	_say("Colour: %s%s" % [label, " (you can see through it)" if preset == "Glass" else ""])


## REPEAT IT: Part's pattern step (Expert Pattern) on the newest solid: a row along X, spacing = the body's width + a 1 cm gap
func _repeat(rec: Dictionary) -> String:
	var res := Part.replay(rec)
	var nb := int(res["bodies"])
	if nb == 0:
		return "Make something solid first, then repeat it"
	var bi := nb - 1
	var w_mm := 10.0
	var faces := Part.body_faces(rec, -1)
	if bi < faces.size() and (faces[bi] as PackedVector3Array).size() > 0:
		var pts: PackedVector3Array = faces[bi]
		var bb := AABB(pts[0], Vector3.ZERO)
		for q in pts:
			bb = bb.expand(q)
		w_mm = maxf(bb.size.x / Part.MM, 1.0)
	var f := Part.new_feature(rec, "pattern", {"kind": "linear", "body": bi, "count": 3, "dir": "x", "axis": "y", "deg": 360.0,
		"mm": w_mm + 10.0, "w": w_mm, "gap": 10.0, "op": "join"})
	rec["features"].append(f)
	if _last_error(rec, String(f["id"])) != "":
		return "The copies would not fit: nothing was changed"
	rep_id = String(f["id"])
	tweak = {}
	_say("Repeated in a row: move the sliders for how many and the gap, or pick Ring")
	return ""


## Row (linear, along X) or Ring (circular, round the up axis Y, a full turn): one undo step; Gap is for the row only
func _rep_mode(ring: bool) -> void:
	if Part.feature(_rec(), rep_id).is_empty():
		return
	_flush_if_dirty()
	_begin("Ring" if ring else "Row")
	var cur := Part.feature(_rec(), rep_id)
	cur["kind"] = "circular" if ring else "linear"
	cur["axis"] = "y"
	cur["deg"] = 360.0
	cur["dir"] = "x"
	cur["mm"] = float(cur.get("w", 10.0)) + float(cur.get("gap", 10.0))
	_end()
	pu.sync()
	_values_sync()
	_say("Ring: the copies go round the up axis" if ring else "Row: the copies go in a straight line")


## STICK TOGETHER: Part's combine step (Expert Combine): the first picked piece is the target, the second the tool; one undo step
func _stick(op: String, label: String) -> void:
	if stick_picks.size() < 2:
		_say("Click two solid pieces first")
		return
	_flush_if_dirty()
	var snap := _rec().duplicate(true)
	_begin(label)
	var rec := pu._ensure()
	var f := Part.new_feature(rec, "combine", {"target": int(stick_picks[0]), "tools": [int(stick_picks[1])], "op": op, "keep": false})
	rec["features"].append(f)
	armed = ""
	var why := _last_error(rec, String(f["id"]))
	stick_picks = []
	if why != "":
		m.S.part = snap
		m._drop_undo()
		_edit_n = -1
		_say("Those two pieces cannot do that: " + why)
	else:
		_end()
		_say("%s: the two pieces are one solid now" % label)
	tweak = {}
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_values_sync()


## a click in the view while Stick together is armed: the body under the pointer is picked (a second click takes it off)
func _stick_pick(bi: int) -> void:
	if stick_picks.has(bi):
		stick_picks.erase(bi)
	elif stick_picks.size() < 2:
		stick_picks.append(bi)
	else:
		_say("Two pieces are picked: press Join, Cut away or Keep the overlap, or click one to take it off")
		return
	_say(_arm_words("stick"))


## the repeat box follows the last Repeat it step (its count, its gap, Row or Ring)
func _rep_sync() -> void:
	if repeat_box == null:
		return
	var f := Part.feature(_rec(), rep_id)
	if f.is_empty():
		return
	var ring := String(f.get("kind", "linear")) == "circular"
	(rep_btns["row"] as Button).set_pressed_no_signal(not ring)
	(rep_btns["ring"] as Button).set_pressed_no_signal(ring)
	for r in rep_rows:
		var s: HSlider = r["slider"]
		var v := float(f.get("count", 3)) if String(r["key"]) == "count" else float(f.get("gap", 10.0)) / 10.0
		if not bool(r.get("held", false)):
			s.set_value_no_signal(v)
		_pill_text(r, v)
		s.editable = not (ring and String(r["key"]) == "gap")


## CURVY LINE: the drag's points (sampled to 12) become one spline sketch (Part's "bspline" entity; the kernel gets the curve it draws).
## Closed when the drag comes back to its start
func _finish_curve() -> void:
	var pts: Array = _draft.get("pts", [])
	_draft = {}
	if pts.size() < 4:
		_say("Drag a bit further to draw a curve")
		return
	var n := mini(pts.size(), 12)
	var out := []
	for i in n:
		var k := roundi(float(i) * float(pts.size() - 1) / float(n - 1))
		out.append(Part.arr2(pts[k]))
	var closed := (pts[pts.size() - 1] as Vector2).distance_to(pts[0] as Vector2) <= 12.0
	_begin("Curvy line")
	var rec := pu._ensure()
	rec["features"].append(Part.new_feature(rec, "sketch", {"plane": "front", "ents": [{"k": "bspline", "pts": out, "closed": closed}], "dims": []}))
	_end()
	armed = ""
	tweak = {}
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_say("Curvy line drawn: Pull it up makes it solid" if closed else "Curvy line drawn: drag back to the start to close it")


# ---------------------------------------------------------------- every frame

func _process(_dt: float) -> void:
	if bar == null or pu == null:
		return
	var on := active()
	if on != _was:
		_was = on
		if not on:
			armed = ""
			_drag = {}
			_draft = {}
	bar.visible = on
	make_box.visible = on
	panel.visible = on
	hint.visible = on
	status.visible = on
	dots.visible = on
	shape_box.visible = on and armed == "draw"
	colour_box.visible = on and armed == "colour"
	repeat_box.visible = on and armed == "" and rep_id != "" and not Part.feature(_rec(), rep_id).is_empty()
	stick_box.visible = on and armed == "stick" and stick_picks.size() == 2
	if not on:
		return
	if m.easy != null:
		m.easy.bar.visible = false
		m.easy.views.visible = false
	if _dirty and Time.get_ticks_msec() - _last_ms >= THROTTLE_MS:
		_flush()
	var rec := _rec()
	var sig := JSON.stringify(rec.get("easy", {})) + str(rec.get("features", []).size()) + str(m.redo.size()) + str(Part.available()) + str(armed) + msg
	if sig != _sig and _drag.is_empty() and not _dirty:
		_sig = sig
		_chrome_sync()
	if dots.visible and (not _drag.is_empty() or not _draft.is_empty()):
		dots.queue_redraw()
	if m.cam != null:
		dots.queue_redraw()


func _chrome_sync() -> void:
	var t := _tpl()
	var rec := _rec()
	title_l.text = "Part: %s" % String(rec.get("name", "Part")) if not rec.is_empty() else "Part"
	panel_title.text = "Change your %s" % _nm()
	redo_btn.visible = not m.redo.is_empty()
	var off := not Part.available()
	for k in make_btns:
		m._grey(make_btns[k], Part.why_not() if off else "")
	(make_btns["draw"] as Button).set_pressed_no_signal(armed == "draw" and not off)
	(make_btns["curve"] as Button).set_pressed_no_signal(armed == "curve" and not off)
	(make_btns["colour"] as Button).set_pressed_no_signal(armed == "colour" and not off)
	(make_btns["stick"] as Button).set_pressed_no_signal(armed == "stick" and not off)
	m._grey(back_btn, Part.why_not() if off else ("" if t != "" else "Pick a shape above first"))
	m._grey(use_scene_btn, Part.why_not() if off else ("" if not _rec().get("features", []).is_empty() else "Draw a shape first"))
	easy_btn.set_pressed_no_signal(true)
	expert_btn.set_pressed_no_signal(false)
	_chips_sync()
	_rows_sync()
	_values_sync()
	_sync_shape()
	var res: Dictionary = pu.res
	var text := ""
	if off:
		text = Part.why_not()
	elif msg != "":
		text = msg
	elif armed != "":
		text = _arm_words(armed)
	elif t != "":
		text = "Drag an amber dot, or use the sliders"
	else:
		text = "Pick a shape on the right, or press Draw shape"
	hint_l.text = text
	var errs: Dictionary = res.get("errors", {}) if not res.is_empty() else {}
	var bodies := int(res.get("bodies", 0)) if not res.is_empty() else 0
	if off:
		status_l.text = "Greyed out: the CAD part of Kine is missing"
	elif rec.is_empty():
		status_l.text = "Nothing here yet"
	elif not errs.is_empty():
		status_l.text = "One step could not follow the new sizes. Undo takes it back"
	elif bodies == 1:
		status_l.text = "Looks good: one solid, no gaps"
	elif bodies == 0:
		status_l.text = "No solid yet"
	else:
		status_l.text = "%d separate pieces" % bodies


func _sync_shape() -> void:
	for k in shape_btns:
		(shape_btns[k] as Button).set_pressed_no_signal(k == shape)


## the panel's height if it is not cut short: its column plus its own margins
func _panel_need() -> float:
	return panel_vb.get_combined_minimum_size().y + panel.get_theme_stylebox("panel").get_minimum_size().y


## the layout, from PartUI.layout(cl): the clear view's rectangle
func layout(cl: Rect2) -> void:
	if not active():
		return
	var w := cl.size.x - 16.0
	var n := float(MAKES.size())   # twelve buttons in one row: each takes its share (the row is as wide as the clear view allows)
	var bw := minf(176.0, (w - (n - 1.0) * 8.0) / n)
	make_box.reset_size()
	for b in make_btns.values():
		(b as Control).custom_minimum_size.x = bw
	make_box.size = Vector2(bw * n + (n - 1.0) * 8.0, MAKE_H)
	make_box.position = Vector2(cl.position.x + 8.0, cl.position.y + 4.0)
	var top := make_box.position.y + maxf(MAKE_H, make_box.size.y) + 8.0
	hint.reset_size()
	hint.size.x = minf(hint.get_combined_minimum_size().x, cl.size.x - PW - 40.0)
	hint.position = Vector2(cl.position.x + 12.0, top)
	shape_box.reset_size()
	shape_box.position = Vector2(cl.position.x + 12.0, top + hint.size.y + 6.0)
	colour_box.reset_size()
	colour_box.position = shape_box.position
	# the Repeat it and Stick together rows sit at the lower left, above the one sentence, off the model's pieces
	repeat_box.reset_size()
	repeat_box.position = Vector2(cl.position.x + 12.0, cl.end.y - repeat_box.size.y - 64.0)
	stick_box.reset_size()
	stick_box.position = Vector2(cl.position.x + 12.0, cl.end.y - stick_box.size.y - 64.0)
	# the panel on the right, as tall as it needs; the words under the sliders go first when the room is short
	var avail := cl.end.y - top - 4.0
	panel.reset_size()
	var need := _panel_need()
	if need > avail and not _compact:
		_compact = true
		_rows_sig = ""
		_rows_sync()
		panel.reset_size()
		need = _panel_need()
	elif need < avail - 70.0 and _compact:
		_compact = false
		_rows_sig = ""
		_rows_sync()
		panel.reset_size()
		need = _panel_need()
	panel.size = Vector2(PW, minf(need, avail))
	panel.position = Vector2(cl.end.x - PW - 8.0, top)
	status.reset_size()
	status.size.x = minf(status.get_combined_minimum_size().x, cl.size.x - PW - 40.0)
	status.position = Vector2(cl.position.x + 12.0, cl.end.y - status.size.y - 6.0)


# ---------------------------------------------------------------- amber dots and the shape being drawn

func _dot_list() -> Array:
	var out := []
	var e: Dictionary = _rec().get("easy", {})
	if e.is_empty() or m.cam == null:
		return out
	for d in PartTemplates.T[e["t"]]["params"]:
		var dd := PartTemplates.dot_of(String(e["t"]), String(d["k"]), e["p"])
		if dd.is_empty():
			continue
		var at: Vector3 = dd["at"]
		if m.cam.is_position_behind(at):
			continue
		dd["k"] = d["k"]
		dd["label"] = d["label"]
		dd["scr"] = m.cam.unproject_position(at)
		out.append(dd)
	return out


func dot_screen(k: String) -> Vector2:
	for d in _dot_list():
		if d["k"] == k:
			return d["scr"]
	return Vector2(-1, -1)


func _draw_dots() -> void:
	var font := ThemeDB.fallback_font
	if not _draft.is_empty():
		var pts := _draft_outline()
		if pts.size() > 1:
			dots.draw_polyline(pts, AMBER, 3.0, true)
	var e: Dictionary = _rec().get("easy", {})
	for d in _dot_list():
		var p: Vector2 = d["scr"]
		var hot: bool = _hover == d["k"] or (not _drag.is_empty() and _drag["k"] == d["k"])
		dots.draw_circle(p, 13.0 if hot else 11.0, Color(0.1, 0.11, 0.14))
		dots.draw_arc(p, 12.0 if hot else 10.0, 0.0, TAU, 28, AMBER, 3.0, true)
		dots.draw_circle(p, 4.0, AMBER)
		if not hot:
			continue   # the label of a dot shows while the mouse is on it or holds it (all of them hid the model)
		var v: float = float(e["p"][d["k"]]) / 10.0
		var txt := "%s %s cm" % [d["label"], str(snappedf(v, 0.1))]
		var sz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		var tp := p + Vector2(-sz.x * 0.5, 30.0)
		dots.draw_rect(Rect2(tp + Vector2(-8, -sz.y + 1), sz + Vector2(16, 6)), Color(0.1, 0.11, 0.14, 0.9))
		dots.draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


func _draft_outline() -> PackedVector2Array:
	var a: Vector2 = _draft["a"]
	var b: Vector2 = _draft["b"]
	var pts := PackedVector2Array()
	if String(_draft["shape"]) == "curve":
		for q in _draft["pts"]:
			pts.append(m.cam.unproject_position(Vector3((q as Vector2).x * Part.MM, (q as Vector2).y * Part.MM, 0.0)))
		return pts
	if String(_draft["shape"]) == "box":
		for q in [a, Vector2(b.x, a.y), b, Vector2(a.x, b.y), a]:
			pts.append(m.cam.unproject_position(Vector3(q.x * Part.MM, q.y * Part.MM, 0.0)))
	else:
		var r := a.distance_to(b)
		for i in 33:
			var q := a + Vector2.from_angle(TAU * i / 32.0) * r
			pts.append(m.cam.unproject_position(Vector3(q.x * Part.MM, q.y * Part.MM, 0.0)))
	return pts


func _ground(p: Vector2) -> Variant:
	var o: Vector3 = m.cam.project_ray_origin(p)
	var d: Vector3 = m.cam.project_ray_normal(p)
	if absf(d.z) < 1e-5:
		return null
	var w := o + d * (-o.z / d.z)
	return Vector2(snappedf(w.x / Part.MM, 5.0), snappedf(w.y / Part.MM, 5.0))


## BUILD's input when the Easy screen has the page: true = taken
func input(ev: InputEvent) -> bool:
	if not active() or not Part.available():
		return false
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var p := (ev as InputEventMouseButton).position
		if (ev as InputEventMouseButton).pressed:
			for d in _dot_list():
				if (d["scr"] as Vector2).distance_to(p) <= 16.0:
					_grab(d, p)
					return true
			if armed == "stick" and not _over_ui(p):
				var hit: Dictionary = pu._ray_hit(p, Part.body_faces(_rec(), -1))   # the body under the pointer (Expert's combine picks the same way)
				if hit.is_empty():
					return false   # nothing solid there: the camera keeps the click
				_stick_pick(int(hit["body"]))
				return true
			if (armed == "draw" or armed == "curve") and not _over_ui(p):
				var g: Variant = _ground(p)
				if g != null:
					_draft = {"a": g, "b": g, "shape": "curve" if armed == "curve" else shape, "pts": [g]}
					return true
			return false
		if not _drag.is_empty():
			_drag_to(p, true)
			_drag = {}
			_end()
			return true
		if not _draft.is_empty():
			if String(_draft["shape"]) == "curve":
				_finish_curve()
			else:
				_finish_draw()
			return true
		return false
	if ev is InputEventMouseMotion:
		var p := (ev as InputEventMouseMotion).position
		if not _drag.is_empty():
			_drag_to(p, false)
			return true
		if not _draft.is_empty():
			var g: Variant = _ground(p)
			if g != null:
				_draft["b"] = g
				if String(_draft["shape"]) == "curve" and (g as Vector2).distance_to((_draft["pts"] as Array).back()) >= 5.0:
					(_draft["pts"] as Array).append(g)
			dots.queue_redraw()
			return true
		var h := ""
		for d in _dot_list():
			if (d["scr"] as Vector2).distance_to(p) <= 16.0:
				h = String(d["k"])
		if h != _hover:
			_hover = h
			dots.queue_redraw()
	return false


func _over_ui(p: Vector2) -> bool:
	for c in [bar, make_box, panel, hint, shape_box, colour_box, repeat_box, stick_box, status]:
		if (c as Control).visible and (c as Control).get_global_rect().has_point(p):
			return true
	return false


func _grab(d: Dictionary, p: Vector2) -> void:
	_flush_if_dirty()
	var e: Dictionary = _rec()["easy"]
	var at: Vector3 = d["at"]
	var ax: Vector3 = d["axis"]
	var s0: Vector2 = m.cam.unproject_position(at)
	var s1: Vector2 = m.cam.unproject_position(at + ax * 0.1)
	var seg := s1 - s0
	_drag = {"k": String(d["k"]), "mouse": p, "val": float(e["p"][d["k"]]), "dir": seg.normalized() if seg.length() > 0.5 else Vector2.RIGHT, "pxmm": maxf(seg.length() / 100.0, 0.001), "gain": float(d["gain"]), "label": String(d["label"])}
	_begin("Change " + String(d["label"]))
	_say("")


func _drag_to(p: Vector2, final: bool) -> void:
	var t := _tpl()
	var pd := PartTemplates.param(t, String(_drag["k"]))
	var mm: float = (p - (_drag["mouse"] as Vector2)).dot(_drag["dir"]) / float(_drag["pxmm"]) * float(_drag["gain"])
	var v := clampf(snappedf(float(_drag["val"]) + mm, float(pd["step"])), float(pd["lo"]), float(pd["hi"]))
	_pending[_drag["k"]] = v
	_dirty = true
	if final:
		_flush()
	else:
		for r in rows:
			if r["kind"] == "tpl" and r["key"] == _drag["k"]:
				(r["slider"] as HSlider).set_value_no_signal(v / 10.0)
				_pill_text(r, v / 10.0)


func _finish_draw() -> void:
	var a: Vector2 = _draft["a"]
	var b: Vector2 = _draft["b"]
	var sh := String(_draft["shape"])
	_draft = {}
	var ent := {}
	if sh == "box":
		if absf(b.x - a.x) < 5.0 or absf(b.y - a.y) < 5.0:
			_say("Drag a bit further to draw a shape")
			return
		ent = {"k": "rect", "a": Part.arr2(a), "b": Part.arr2(b)}
	else:
		var r := a.distance_to(b)
		if r < 5.0:
			_say("Drag a bit further to draw a shape")
			return
		ent = {"k": "circle", "c": Part.arr2(a), "r": snappedf(r, 0.5)}
	_begin("Draw shape")
	var rec := pu._ensure()
	rec["features"].append(Part.new_feature(rec, "sketch", {"plane": "front", "ents": [ent], "dims": []}))
	_end()
	armed = ""
	tweak = {}
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_say("Shape drawn. Now press Pull it up or Spin it round")
