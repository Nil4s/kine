class_name EasyBuild
extends Node
## EASY BUILDING: Easy mode's own screen for the BUILD page of a 3D BUILDING project (start screen: Building -> Easy).
## A big top bar (Undo, Redo, Words, Switch to Expert, Done), a left column of six big picture buttons (Room, Door, Window,
## + Floor, Roof, Stairs) and "Use in a scene" under them, and one plain sentence for the tool in hand. Mouse only: no key names in
## any text here. Every button runs the code Expert BUILD runs (BuildUI: _pick_tool, _set_kind, _add_floor, _set_roof, _remove_roof,
## use_in_scene, the Words tool): no geometry logic here. Nothing of Expert's ribbon or side panels shows (BuildUI.easy_ui()
## gates them; Easy hides the top strip). Switch to Expert keeps the house: the record (Scene.building) is not touched.

const COL_W := 150.0
const PAD := 8.0
const ROOFS := ["gable", "flat", ""]   # one press of Roof goes to the next: gable, flat, none
const HINTS := {
	"Room": "Drag on the floor to make a room",
	"Door": "Click a wall to put a door in it",
	"Window": "Click a wall to put a window in it",
	"Floor": "Each press adds a floor on top of the house",
	"Roof": "Each press changes the roof: gable, flat, none",
	"Stairs": "Click inside a room to put stairs there",
	"Words": "Type what you want to build, then check the plan",
}

var m: Node
var bar: PanelContainer
var col: PanelContainer
var hint: PanelContainer
var use_btn: Button
var redo_btn: Button
var _hint_l: Label
var _btns := {}      # id -> Button
var _said := "Room"   # the hint's key (a tool or an action)
var _was := false
var _msg := ""       # a refusal's own sentence, shown until the next press


func build(root: Control) -> void:
	bar = PanelContainer.new()
	bar.name = "easybuild_bar"
	bar.theme_type_variation = "TopBar"
	bar.anchor_right = 1.0
	bar.offset_bottom = m.TOP_H
	bar.visible = false
	root.add_child(bar)
	var row := HBoxContainer.new()
	row.name = "easybuild_row"
	row.add_theme_constant_override("separation", 4)
	bar.add_child(row)
	var acts := [
		["Undo", "Take back the last change", func(): m._undo()],
		["Words", "Say what you want to build in words", func(): _words()],
		["Switch to Expert", "Show every tool again. The house stays as it is", func(): m.easy.set_on(false)],
		["Done", "Finish building and go back to the start screen", _done],
	]
	var home_b: Button = m._home_button()   # the same Home button as every bar
	home_b.custom_minimum_size = Vector2(110, m.TOP_H - 12)
	home_b.add_theme_font_size_override("font_size", 15)
	row.add_child(home_b)
	for a in acts:
		row.add_child(_big(a[0], a[1], a[2]))
	redo_btn = _big("Redo", "Put back what Undo took back", func(): m._redo())
	redo_btn.custom_minimum_size = Vector2(150, m.TOP_H - 12)
	redo_btn.size_flags_horizontal = Control.SIZE_FILL
	redo_btn.visible = false
	row.add_child(redo_btn)
	row.move_child(redo_btn, 1)
	col = PanelContainer.new()
	col.name = "easybuild_col"
	col.visible = false
	var st := StyleBoxFlat.new()
	st.bg_color = Tok.c("panel")
	st.set_corner_radius_all(10)
	st.set_content_margin_all(6)
	col.add_theme_stylebox_override("panel", st)
	root.add_child(col)
	var v := VBoxContainer.new()
	v.name = "easybuild_tools"
	v.add_theme_constant_override("separation", 4)
	col.add_child(v)
	var tools := [
		["Room", "Room", "build_room", func(): _tool("Room")],
		["Door", "Door", "build_door", func(): _opening("door")],
		["Window", "Window", "build_window", func(): _opening("window")],
		["Floor", "+ Floor", "build_floor", func(): _floor()],
		["Roof", "Roof", "build_roof", func(): _roof()],
		["Stairs", "Stairs", "piece_stairs", func(): _stairs()],
	]
	for t in tools:
		var b := Button.new()
		b.name = "easybuild_" + String(t[0]).to_lower()
		b.text = String(t[1])
		b.toggle_mode = String(t[0]) in ["Room", "Door", "Window", "Stairs"]
		b.focus_mode = Control.FOCUS_NONE
		b.icon = Icons.sized(String(t[2]), 32)
		b.expand_icon = false
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_constant_override("h_separation", 8)
		b.add_theme_font_size_override("font_size", 15)
		b.custom_minimum_size = Vector2(COL_W, 56)
		b.tooltip_text = HINTS[t[0]]
		b.pressed.connect(t[3])
		v.add_child(b)
		_btns[t[0]] = b
	use_btn = Button.new()
	use_btn.name = "easybuild_use"
	use_btn.text = "Use in a scene"
	use_btn.focus_mode = Control.FOCUS_NONE
	use_btn.theme_type_variation = "Main"
	use_btn.add_theme_font_size_override("font_size", 16)
	use_btn.custom_minimum_size = Vector2(COL_W, 56)
	use_btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	use_btn.tooltip_text = "Put this building in a scene as a set to animate in"
	use_btn.pressed.connect(func(): m.bld._use_pressed())
	v.add_child(use_btn)
	hint = PanelContainer.new()
	hint.name = "easybuild_hint"
	hint.visible = false
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hs := StyleBoxFlat.new()
	hs.bg_color = Color(0.1, 0.11, 0.14, 0.92)
	hs.set_corner_radius_all(10)
	hs.set_content_margin_all(10)
	hint.add_theme_stylebox_override("panel", hs)
	_hint_l = Label.new()
	_hint_l.name = "easybuild_hint_text"
	_hint_l.add_theme_font_size_override("font_size", 20)
	_hint_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_child(_hint_l)
	root.add_child(hint)


## one big bar button, as Easy's own (a Label child, so the words wrap and centre)
func _big(label: String, tip: String, f: Callable) -> Button:
	var b := Button.new()
	b.name = "easybuild_btn_" + label.to_lower().replace(" ", "_")
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, m.TOP_H - 12)
	var l := Label.new()
	l.name = "label"
	l.text = label
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 15)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(l)
	b.pressed.connect(func(): m._step_hint = label; f.call())
	return b


# ---------------------------------------------------------------- the state

## Easy is on, in a building project, on BUILD
func is_active() -> bool:
	return m != null and m.easy != null and m.easy.on and m.S != null and m.S.kind == "building" and m.cur_page == "BUILD" and m.bld != null and m.bld.on


## the width the column takes from the left of the clear view
func inset() -> float:
	return COL_W + 12.0 + PAD * 2.0 if is_active() else 0.0


## BuildUI's status line in Easy: the sentence of the last press, or the refusal's own (easy_t)
func say(easy_t := "") -> void:
	_msg = easy_t   # "" (an action that worked) takes a refusal down


func _process(_dt: float) -> void:
	if bar == null:
		return
	var on := is_active()
	if on != _was:
		_was = on
		if on:
			_msg = ""
		else:
			m.easy.bar.visible = m.easy.on   # Easy's own bar and view buttons come back off BUILD
			m.easy.views.visible = m.easy.on
	bar.visible = on
	col.visible = on
	if not on:
		hint.visible = false
		return
	m.easy.bar.visible = false
	m.easy.views.visible = false
	var bld: BuildUI = m.bld
	var has: bool = not bld._bld().is_empty() and not bool(bld._bld().get("readonly", false)) and not bld._bld().get("rooms", []).is_empty()
	redo_btn.visible = not m.redo.is_empty()
	# what is in hand shows on its button
	(_btns["Room"] as Button).set_pressed_no_signal(bld.tool == "Room")
	(_btns["Door"] as Button).set_pressed_no_signal(bld.tool == "Opening" and bld.kind == "door")
	(_btns["Window"] as Button).set_pressed_no_signal(bld.tool == "Opening" and bld.kind == "window")
	(_btns["Stairs"] as Button).set_pressed_no_signal(bld.tool == "Piece" and bld.piece_kind == "stairs")
	var rk := String(bld._bld().get("roof", {}).get("kind", ""))
	var rb := _btns["Roof"] as Button
	var rt := "Roof: " + (rk.capitalize() if rk != "" else "none")
	if rb.text != rt:
		rb.text = rt
	m._grey(use_btn, "" if has else "Draw a room first")
	# the column under the bar, as tall as the room above the status line allows; the hint under the bar
	var v: VBoxContainer = col.get_child(0)
	var top := float(m.TOP_H) + PAD
	var low: float = m.ui_status.global_position.y - PAD if m.ui_status != null and m.ui_status.visible else m.get_viewport().get_visible_rect().size.y - 120.0
	var n := v.get_child_count()
	var h := clampf((low - top - 12.0 - float(n - 1) * 4.0) / float(n), 40.0, 64.0)
	for c in v.get_children():
		(c as Control).custom_minimum_size.y = h
	col.reset_size()
	col.position = Vector2(PAD, top)
	if m.ui_status != null and m.ui_status.text != "" and not m.ui_status.text.begins_with("Took back") and not m.ui_status.text.begins_with("Put back"):
		m._say("")   # Easy keeps Expert's key-naming lines off the status strip
	var key := _said if bld.tool != "Words" else "Words"
	var text := _msg if _msg != "" else String(HINTS.get(key, ""))
	if has and key == "Room" and _msg == "":
		text = "Drag on the floor to make another room"
	if _hint_l.text != text:
		_hint_l.text = text
	hint.visible = bld.tool != "Words" and text != ""
	if hint.visible:
		hint.reset_size()
		var vs := m.get_viewport().get_visible_rect().size
		var x0 := PAD * 2.0 + COL_W + 12.0
		hint.position = Vector2(x0 + (vs.x - x0 - hint.size.x) * 0.5, top)


# ---------------------------------------------------------------- the buttons

func _said_as(key: String) -> void:
	_said = key
	_msg = ""


func _tool(t: String) -> void:
	_said_as(t)
	m.bld._pick_tool(t)


func _opening(k: String) -> void:
	_said_as("Door" if k == "door" else "Window")
	m.bld.sel = ""   # a picked opening would turn into the other kind (Expert's way); Easy's button only chooses what the next click adds
	m.bld._pick_tool("Opening")
	m.bld._set_kind(k)
	m.bld.kind_btns[k].set_pressed_no_signal(true)


func _stairs() -> void:
	_said_as("Stairs")
	m.bld._pick_tool("Piece")
	m.bld.piece_kind = "stairs"
	m.bld.sync()


func _floor() -> void:
	_said_as("Floor")
	m.bld._add_floor()


## gable -> flat -> none -> gable (a roof Words made, shed, goes to gable)
func _roof() -> void:
	_said_as("Roof")
	var bd: Dictionary = m.bld._bld()
	var rk := String(bd.get("roof", {}).get("kind", ""))
	var i := ROOFS.find(rk)
	var nxt: String = ROOFS[(i + 1) % ROOFS.size()] if i >= 0 else ROOFS[0]
	if nxt == "":
		m.bld._remove_roof()
	else:
		m.bld._set_roof(nxt)


func _words() -> void:
	_said_as("Words")
	m.bld._pick_tool("Words")


## Done: the start screen (a question first when the project has unsaved work)
func _done() -> void:
	var go := func(): m.start_screen.show_screen()
	if m._unsaved():
		m._ask_save(m._scene_label(), go)
	else:
		go.call()
