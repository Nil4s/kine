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
const ROUND_BUDGET_US := 300000   # EROUND: the Round press stops trying edges after this (usec) and keeps the best found
const MAKE_H := 76.0
const REP_WORDS := {"count": ["Fewer", "More"], "gap": ["Closer", "Further apart"]}   # the Repeat it sliders' ends
const STICK_OPS := [["join", "Join", "Make the two pieces one solid"], ["cut", "Cut away", "Cut the second piece out of the first"], ["intersect", "Keep the overlap", "Keep only the part where the two pieces overlap"]]
const COLOUR_PRESETS := ["Glass", "Metal"]   # the two material chips after the five colour chips
const HOLLOW_MM := 3.0           # Hollow inside: the wall the shell starts with (the Wall slider moves it: 1 to 10 mm)
const THROTTLE_MS := 100
const SKY := Color("#73BFFF")
const AMBER := Color("#FFC933")
const MAKES := [
	["draw", "Draw shape", "part_rectangle", "Drag on the grid to draw a box or a round shape"],
	["pull", "Pull it up", "part_extrude", "Make the newest shape into a solid, then say how far"],
	["spin", "Spin it round", "part_revolve", "Turn the newest shape round the middle line into a solid"],
	["round", "Round the edges", "part_fillet", "Soften the sharp edges"],
	["hole", "Cut a hole", "part_circle", "Cut a round hole through the middle, or hollow the solid out (Hollow inside)"],
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
var stick_tris := {}             # body index -> its triangles, for the glow of a picked piece
var stick_edges := {}            # body index -> its crease edges (pairs of points): the glow's outline, no triangle diagonals
const PICK_PX := 12.0            # a click this close (screen px) to a piece picks it when the ray hits nothing
var rep_id := ""                 # the last Repeat it step's feature id ("" = none)
var rep_rows := []               # the two slider rows of the Repeat it box (see _make_row)
var hole_box: PanelContainer     # Cut a hole: the Through / Hollow inside chips, under the MAKE row, after a Cut a hole press (see _hole_on)
var hole_btns := {}
var hole_base: Dictionary = {}   # the record before the last Cut a hole press: each chip rebuilds the hole from it ({} = no hole chips)
var hole_id := ""                # the feature id of the last hole step (the hole's sketch, or the hollow's shell): its slider's step
var hole_mode := "through"       # "through" | "hollow": the chip that is on
var split_box: PanelContainer   # ECUT2: Cut in two's keep chips (both halves / the lower half / the upper half), after a Cut in two press (see _split_on)
var split_btns := {}
var split_id := ""              # the feature id of the last Cut in two step: the keep chips edit its "keep" field
var colour_box: PanelContainer   # Colour: the five colour chips and Glass / Metal, under the MAKE row (armed "colour")
var panel: PanelContainer
var panel_vb: VBoxContainer   # the panel's column: it scrolls inside the panel when the window is short (1280 x 720)
var panel_title: Label
var chips := {}
var empty_chip: Button   # "Empty": start from nothing (not in chips: those are the templates)
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
var _draft_px0 := Vector2.ZERO   # the draft's raw pointer pixels, first press and last move (the sides are read from these when the grid folds them)
var _draft_px1 := Vector2.ZERO
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
var _cl := Rect2()              # the clear view's rectangle of the last layout (free_rect)
const FRAME_FILL := 0.55        # EFRAME: the part's box fills this share of the free view (its bigger side)
const FRAME_EASE := 0.3         # seconds the camera eases to a new framing (never a jump)
const FRAME_CHANGE := 0.25      # the box's diagonal must change this much to frame again (a small nudge moves nothing)
var _fr_ref := AABB()           # the bounds the camera last framed (or the bounds on entry)
var _fr_has := false
var _near_saved := -1.0         # the camera's near plane before Easy Part (put back when it is left)
const FRAME_NEAR := 0.004
const GRID_TILE_FILL := 0.95         # the empty part's grid tile fills this share of the free view (a flat square seen at a slant is narrow)
const GRID_TILE := AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 0.0, 1.0))   # the 1 m grid square an empty part stands on (metres)
var _bar_press = null           # a draw press that began on the top bar (Vector2), or null: a drag starts the sketch there, a click is the button's
var _press_btn: BaseButton = null # the button under that press (its click when the press is not a drag)
var _off_tried := AABB()         # the box the D2 off-screen check last framed (see _frame_step)
var _ease := {}                 # the camera ease in progress: {"t0", "d0", "t1", "d1", "s"}
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
		b.gui_input.connect(_tap_track.bind(String(mk[0])))
		b.pressed.connect(_tap_click.bind(String(mk[0])))
		make_box.add_child(b)
		make_btns[mk[0]] = b
	# the one sentence, and the shape choice that goes with Draw shape
	hint = _pill("easypart_hint", 19)
	hint_l = hint.get_child(0)
	hint_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # long words (Mirror's gap) wrap inside the room left of the panel, not under it (layout)
	root.add_child(hint)
	shape_box = PanelContainer.new()
	shape_box.name = "easypart_shapes"
	shape_box.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.92), 10, 6))
	shape_box.visible = false
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 6)
	shape_box.add_child(sh)
	for s in [["box", "Box"], ["round", "Round"], ["pointy", "Pointy"]]:
		var b := Button.new()
		b.name = "easypart_shape_" + String(s[0])
		b.text = String(s[1])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(76, 40)   # three chips narrow enough that the panel stays clear of a floor drag at the grid edge (efloor)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(func(): shape = String(s[0]); _sync_shape())
		sh.add_child(b)
		shape_btns[s[0]] = b
	root.add_child(shape_box)
	hole_box = _hole_box()
	root.add_child(hole_box)
	split_box = _split_box()
	root.add_child(split_box)
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
	panel_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var th := HBoxContainer.new()   # the title line: "Change your part" and, at its end, Empty (the template chips stay on one line below)
	th.name = "easypart_title_row"
	v.add_child(th)
	th.add_child(panel_title)
	empty_chip = Button.new()   # EMPTY first: Easy Part opens on a sword, and a beginner building their own thing needs a clean floor
	empty_chip.name = "easypart_chip_empty"
	empty_chip.text = "Empty"
	empty_chip.tooltip_text = "Start from nothing: draw your own shape on the grid"
	empty_chip.toggle_mode = true
	empty_chip.focus_mode = Control.FOCUS_NONE
	empty_chip.custom_minimum_size = Vector2(0, 34)
	empty_chip.add_theme_font_size_override("font_size", 15)
	empty_chip.pressed.connect(_empty)
	th.add_child(empty_chip)
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


## CUT A HOLE: Through (the round hole, the default) or Hollow inside (the shell: open at the top, a Wall slider). Two toggle chips like Draw shape's
func _hole_box() -> PanelContainer:
	var box := PanelContainer.new()
	box.name = "easypart_hole"
	box.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.92), 10, 6))
	box.visible = false
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	box.add_child(h)
	for hm in [["through", "Through", "A round hole straight through the middle"], ["hollow", "Hollow inside", "Hollow the solid out, open at the top, with a wall (the Wall slider)"]]:
		var b := _big_btn("easypart_hole_" + String(hm[0]), String(hm[1]), String(hm[2]), _hole_mode.bind(String(hm[0])))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(150, 44)
		h.add_child(b)
		hole_btns[hm[0]] = b
	return box


## ECUT2: Cut in two keeps ONE half: three toggle chips after a Cut in two press. Both halves is the default (two bodies); the lower or upper half
## keeps only that side of the cut (one body). Each chip is one undo step; the slider still moves the cut
func _split_box() -> PanelContainer:
	var box := PanelContainer.new()
	box.name = "easypart_split"
	box.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.92), 10, 6))
	box.visible = false
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	box.add_child(h)
	for sk in [["both", "Keep both halves", "Keep both pieces of the cut (two bodies)"], ["lower", "Keep the lower half", "Keep only the half on the lower side of the cut (one body)"], ["upper", "Keep the upper half", "Keep only the half on the upper side of the cut (one body)"]]:
		var b := _big_btn("easypart_split_" + String(sk[0]), String(sk[1]), String(sk[2]), _split_keep.bind(String(sk[0])))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(190, 44)
		h.add_child(b)
		split_btns[sk[0]] = b
	return box


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
	var cb := _big_btn("easypart_rep_corners", "Corners", "Four copies, one at each corner of the piece it sits on (the legs of a chair or table)", _rep_corners)
	cb.toggle_mode = true
	h.add_child(cb)
	rep_btns["corners"] = cb
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
	hole_base = {}
	split_id = ""
	stick_picks = []
	_draft = {}
	_drag = {}
	_sig = ""
	_rows_sig = ""
	frame()


## the model in the clear part of the view (left of the panel), as Expert's own framing, then moved off the panel
func frame() -> void:
	_fr_has = false   # the bounds on entry are the reference: no framing ease for them
	_ease = {}
	pu._view_model()
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var span := 2.0 * float(m.dist) * tan(deg_to_rad(m.cam.fov * 0.5)) * vs.x / vs.y
	m.dist = float(m.dist) * 1.45
	span *= 1.45
	m.target += m.cam.global_basis.x * (span * (PW * 0.5 + 8.0) / vs.x)
	m._cam()
	if _rec().get("features", []).is_empty() and m.cam != null:
		# FREEWALK D1: an empty part shows the 1 m grid tile framed in the free view (not a corner under the bar)
		var pose := _frame_pose(GRID_TILE, GRID_TILE_FILL)
		if not pose.is_empty():
			m.target = pose[0]
			m.dist = pose[1]
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


## an error the Part tools give, in words a child reads: sketch -> shape, body -> solid, and anything still technical -> a plain line
static func _plain(e: String) -> String:
	var t := e.replace("its sketch is gone", "its shape is gone").replace("sketch", "shape").replace("body", "solid").replace("feature", "step").replace("extrude", "pull").replace("fillet", "round").replace("loft", "blend").replace("boolean", "join").replace("profile", "shape")
	var jargon := RegEx.new()
	jargon.compile("(?i)\\b(kernel|manifold|mesh|primitive|kcad|revolve|shell|plane|offset|dll|cad|wire|f\\d{1,2})\\w*")
	if jargon.search(t) != null:
		return "That step cannot be made here: Undo takes the last step back"
	return t


func _say(t: String) -> void:
	msg = t


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
		hole_base = {}                    # the template's sizes changed: the hole chips would rebuild on an old shape
	elif row["kind"] == "rep":
		_apply_rep(row, v)
	else:
		_apply_tweak(v)
		if final and tweak.has("say"):
			_say(String(tweak["say"]) % _fmt(v, String(tweak.get("unit", "cm"))))
	_dirty = true
	if final:
		_flush()


func _apply_tweak(v: float) -> void:
	if _tweak_stale():
		return
	var f := Part.feature(_rec(), String(tweak["id"]))
	if f.is_empty():
		return
	var val: float = v * float(tweak.get("scale", 1.0)) * float(tweak.get("sgn", 1.0))
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
	if _rec().is_empty():   # no part (the {} record): a slider has nothing to write to; the pending numbers go
		_pending = {}
		return
	if not _pending.is_empty():
		PartTemplates.retemplate(_rec(), _pending)
		_pending = {}
	var note := PartTemplates.fit_rounds(_rec())   # a new size (or the How round slider) can leave a round too big for its edges: it shrinks, and says so
	if note != "":
		_say(note)
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
	if unit == "mm":
		return "%s mm" % str(snappedf(v, 0.1))
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
	_tweak_stale()
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


## ESAVE: a record opened again (My parts, Change the part): the slider of its NEWEST step comes back (a Wall of a hollow, a How far of a
## pull up, a Hole size of a hole); none when the newest step has no slider (the record is shown without one, as a fresh start)
func tweak_last() -> void:
	tweak = {}
	var fs: Array = _rec().get("features", [])
	if fs.is_empty():
		return
	var f: Dictionary = fs[-1]
	var t := String(f.get("t", ""))
	if t == "shell":
		tweak = {"id": f["id"], "field": "thick", "label": "Wall", "unit": "mm", "lo": 1.0, "hi": 10.0, "step": 0.5, "scale": 1.0, "words": ["Thinner", "Thicker"]}
	elif t == "extrude" and not bool(f.get("both", false)) and String(f.get("op", "join")) == "join" and f.has("dist"):
		var dist := float(f["dist"])
		tweak = {"id": f["id"], "field": "dist", "label": "How far", "unit": "cm", "lo": 0.2, "hi": 40.0, "step": 0.2, "scale": 10.0, "words": ["Flatter", "Taller"], "sgn": -1.0 if dist < 0.0 else 1.0}
	elif t == "extrude" and bool(f.get("both", false)) and String(f.get("op", "")) == "cut":
		var sk := Part.feature(_rec(), String(f.get("sketch", "")))
		var ents: Array = sk.get("ents", [])
		if ents.size() == 1 and String(ents[0].get("k", "")) == "circle" and sk.has("plane") and String(sk.get("plane", "")) in ["front", "top"]:
			tweak = {"id": sk["id"], "ent": 0, "field": "r", "label": "Hole size", "unit": "cm", "lo": 0.6, "hi": 16.0, "step": 0.1, "scale": 5.0, "words": ["Smaller", "Bigger"]}


## the last step's own slider belongs to ONE entity of its feature. Undo can bring back a record where that id is another sketch
## (a box, with no radius): the slider is then dropped (its rows rebuild) instead of reading a field the entity does not have
func _tweak_stale() -> bool:
	if tweak.is_empty() or not tweak.has("ent"):
		return false
	var f := Part.feature(_rec(), String(tweak["id"]))
	if f.is_empty():
		return false
	var ents: Array = f.get("ents", [])
	var ei := int(tweak["ent"])
	var ok_ent := ei >= 0 and ei < ents.size() and typeof(ents[ei]) == TYPE_DICTIONARY and (ents[ei] as Dictionary).has(String(tweak["field"]))
	if ok_ent:
		return false
	tweak = {}
	_rows_sig = ""
	return true


func _tweak_value() -> float:
	if _tweak_stale() or tweak.is_empty():
		return 0.0
	var f := Part.feature(_rec(), String(tweak["id"]))
	if f.is_empty():
		return float(tweak["lo"])
	var raw: float = float(f["ents"][int(tweak["ent"])][tweak["field"]]) if tweak.has("ent") else float(f.get(tweak["field"], 0.0))
	return raw * float(tweak.get("sgn", 1.0)) / float(tweak.get("scale", 1.0))


func _values_sync() -> void:
	if _tweak_stale():   # the stale slider goes: its row is rebuilt without it, then the values are set
		_rows_sync()
		return
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
	hole_base = {}
	split_id = ""
	_flush_if_dirty()
	m._step_hint = "Start a " + t
	m._push_undo()
	m.S.part = PartTemplates.make(t)
	tweak = {}
	pu.upto = -1
	pu.sync()
	frame()
	_say("%s %s: move a slider or drag an amber dot" % ["An" if t.substr(0, 1) in "aeiou" else "A", t])


## EMPTY: a part with no steps (one undo step); Draw shape on the grid starts it
func _empty() -> void:
	if (_rec().get("features", []) as Array).is_empty() or not Part.available():
		_chips_sync()
		return
	armed = ""
	hole_base = {}
	_flush_if_dirty()
	m._step_hint = "Start an empty part"
	m._push_undo()
	m.S.part = Part.make("Part")
	m.S.part["kept"] = true   # the user chose an empty part: undo and redo keep it (Part.from_file); a feature-less record otherwise means no part
	tweak = {}
	pu.upto = -1
	pu.sync()
	frame()
	_say("Empty: press Draw shape, then drag on the grid")


func _chips_sync() -> void:
	if empty_chip != null:
		empty_chip.set_pressed_no_signal((_rec().get("features", []) as Array).is_empty())
		m._grey(empty_chip, Part.why_not() if not Part.available() else "")
	for t in chips:
		(chips[t] as Button).set_pressed_no_signal(t == _tpl())
		m._grey(chips[t], Part.why_not() if not Part.available() else "")


func _back() -> void:
	var e: Dictionary = _rec().get("easy", {})
	if e.is_empty() or not Part.available():
		return
	hole_base = {}
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

## A MAKE press is a TAP: the button fires on release, so a press that the pointer took off the button and back on (a drag from the far floor
## under the row) would click it. _tap_track notes where the press began and whether the pointer went more than TAP_PX away while held.
const TAP_PX := 6.0
var _tap_at := {}     # button name -> the press point (local to the button)
var _tap_moved := {}  # button name -> true when the held pointer went past TAP_PX


func _tap_track(ev: InputEvent, nm: String) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if (ev as InputEventMouseButton).pressed:
			_tap_at[nm] = (ev as InputEventMouseButton).position
			_tap_moved[nm] = false
	elif ev is InputEventMouseMotion and (ev as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT != 0 and _tap_at.has(nm):
		if (ev as InputEventMouseMotion).position.distance_to(_tap_at[nm]) > TAP_PX:
			_tap_moved[nm] = true


func _tap_click(which: String) -> void:
	if bool(_tap_moved.get(which, false)):   # a drag, not a tap: the MAKE button does nothing
		_tap_moved[which] = false
		var b: Button = make_btns[which]
		if b.toggle_mode:   # a toggle button flipped itself on the release: put it back, or it shows lit while nothing is armed
			b.set_pressed_no_signal(not b.button_pressed)
		return
	_make(which)


func _make(which: String) -> void:
	if not Part.available():
		_say(Part.why_not())
		return
	_flush_if_dirty()
	if which != "hole":
		hole_base = {}   # any other press ends the hole choice: its chips go
	if which != "repeat":
		rep_id = ""
	if which != "split":
		split_id = ""
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
		if armed == "draw":
			shape = "box"   # every Draw shape press starts on Box: the Round chip of the last shape (a mug) does not carry over (a chair leg is a box)
			_sync_shape()
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
		if which == "split":
			split_id = String(tweak.get("id", ""))   # the keep chips edit this cut step
		if which == "hole":   # the chips rebuild the hole from the record before this press
			hole_base = snap
			hole_id = String(tweak.get("id", ""))
			hole_mode = "through"
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_values_sync()


## the hole chips show after a Cut a hole press, while its step is the newest hole and nothing is armed
func _hole_on() -> bool:
	return not hole_base.is_empty() and armed == "" and not Part.feature(_rec(), hole_id).is_empty()


func _hole_sync() -> void:
	for k in hole_btns:
		(hole_btns[k] as Button).set_pressed_no_signal(k == hole_mode)


## a Through / Hollow inside chip: the hole step is REPLACED (one undo step): the record from before the hole press, then the chosen hole.
## A hollow that fails (a body too thin for the wall) says so and changes nothing
func _hole_mode(mode: String) -> void:
	if not _hole_on() or not Part.available() or mode == hole_mode:
		_hole_sync()
		return
	_flush_if_dirty()
	armed = ""
	var snap := _rec().duplicate(true)
	_begin("Hollow inside" if mode == "hollow" else "Cut a hole")
	var rec: Dictionary = hole_base.duplicate(true)
	m.S.part = rec
	var why := _hollow(rec) if mode == "hollow" else _hole(rec)
	if why != "":
		m.S.part = snap
		m._drop_undo()
		_edit_n = -1
		_say(why)
	else:
		_end()
		hole_mode = mode
		hole_id = String(tweak.get("id", ""))
	pu.upto = -1
	pu.sync()
	_rows_sig = ""   # the step's id can repeat the last one (the chips rebuild from an older record): the slider box is rebuilt anyway
	_rows_sync()
	_values_sync()


## HOLLOW INSIDE: Part's shell on the newest solid, open at its TOP face ("+y": the planar face with the largest +Y centre),
## a HOLLOW_MM wall. The Wall slider moves the thickness (mm)
func _hollow(rec: Dictionary) -> String:
	var res := Part.replay(rec)
	var n := int(res["bodies"])
	if n == 0:
		return "Nothing solid to hollow out yet. Press Pull it up first"
	var bb: AABB = res["aabb"]
	var thin := minf(bb.size.x, minf(bb.size.y, bb.size.z)) / Part.MM   # the body's smallest size (mm): a wall needs room on both sides
	var too_thin := "That solid is too thin to hollow out with a 3 mm wall: Pull it up taller, then press Cut a hole again"
	if thin <= 2.0 * HOLLOW_MM:
		return too_thin
	var f := Part.new_feature(rec, "shell", {"body": n - 1, "open": "+y", "thick": HOLLOW_MM})
	rec["features"].append(f)
	if _last_error(rec, String(f["id"])) != "":
		return too_thin
	tweak = {"id": f["id"], "field": "thick", "label": "Wall", "unit": "mm", "lo": 1.0, "hi": 10.0, "step": 0.5, "scale": 1.0, "words": ["Thinner", "Thicker"]}
	_say("Hollowed out, open at the top: use the slider for the wall")
	return ""


func _arm_words(a: String) -> String:
	match a:
		"stick":
			if stick_picks.size() == 0:
				return "Click the first solid piece in the view"
			if stick_picks.size() == 1:
				return "Now click the other piece"
			return "Pick Join, Cut away or Keep the overlap"
		"draw":
			return "Drag on the grid to draw a shape"
		"curve":
			return "Drag a wobbly loop on the grid. Drag back to the start to close it"
		"colour":
			return "Pick a colour below, or Glass or Metal"
	return ""


func _last_error(rec: Dictionary, fid: String) -> String:
	return String(pu.replay_full(rec)["errors"].get(fid, ""))


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
	var pf := Part.feature(rec, String(sk.get("plane", "front")))
	var on_face := String(pf.get("t", "")) == "plane" and pf.has("out")   # a sketch on a face: the pull goes OUTWARD from it
	var sg := float(pf["out"]) if on_face else 1.0
	var through := bool(pf.get("through", false))   # an upright sketch (through the middle) pulls BOTH ways
	var inward := on_face and not through and _overhangs(rec, sk) and not _top_face(pf)
	if inward:
		sg = -sg   # a face drawing that hangs past the body (a roof above the walls) pulls back INTO it: it extends the body's outline; one inside the face (a leg) pulls out
	# ETABLE: a top drawn on the TOP of the legs hangs past them, but it stands ON them: a top face pulls up (out), never into the legs
	var dist := 20.0 * sg
	if through and _sits_on_body(rec, sk):
		# A ROOF: pulled out both ways from the middle to the box's depth (the slider changes it from there)
		var bb: AABB = Part.replay(rec).get("aabb", AABB())
		var depth := bb.size.z if String(pf.get("from", "front")) == "front" else bb.size.x
		dist = snappedf(depth / Part.MM, 1.0)
	var f := Part.new_feature(rec, "extrude", {"sketch": sid, "dist": dist, "both": through, "op": "join"})
	rec["features"].append(f)
	var err := _last_error(rec, String(f["id"]))
	if err != "":
		return "That shape is not closed, so it cannot be pulled up: drag back to the start to close it"
	tweak = {"id": f["id"], "field": "dist", "label": "How far", "unit": "cm", "lo": 0.2, "hi": 40.0, "step": 0.2, "scale": 10.0, "words": ["Flatter", "Taller"], "sgn": sg}
	if through:
		_say("Pulled out both ways from the middle: use the slider for how thick, or press Mirror that or Cut a hole next")
	elif on_face:
		_say("Pulled into the solid: use the slider to change it, or press Cut a hole next" if inward else "Pulled out of the face: use the slider to change it, or press Mirror that next")
	else:
		tweak["say"] = "Pulled up %s: use the slider to change it, or press Round the edges or Cut a hole next"   # the words follow the slider (a beginner walk: "2 cm" stayed at 8 cm); the next button too (ehelp2)
		_say(String(tweak["say"]) % _fmt(2.0, "cm"))
	return ""


## an upright sketch whose lowest point is at or above the body's top (a roof on the box)
func _sits_on_body(rec: Dictionary, sk: Dictionary) -> bool:
	var bb: AABB = Part.replay(rec).get("aabb", AABB())
	if bb.size == Vector3.ZERO:
		return false
	var low := INF
	for e in sk["ents"]:
		for q in _ent_pts(e):
			low = minf(low, float(q[1]))
	return low >= bb.end.y / Part.MM - 1.0


## ETABLE: a face plane on the top of a solid (the floor-facing normal is up: out +1 on the Part top plane)
func _top_face(pf: Dictionary) -> bool:
	return String(pf.get("from", "")) == "top" and int(pf.get("out", 0)) > 0


## a face sketch hangs past the body when one of its points lies outside the body's box (by more than 0.5 mm) along the face's own axes
func _overhangs(rec: Dictionary, sk: Dictionary) -> bool:
	var bb: AABB = Part.replay(rec).get("aabb", AABB())
	if bb.size == Vector3.ZERO:
		return false
	var pl := Part.resolve_plane(rec, String(sk.get("plane", "front")))
	var g := bb.grow(0.5 * Part.MM)
	var n: Vector3 = pl["n"]
	for e in sk["ents"]:
		for q in _ent_pts(e):
			var w := Part.to_world(pl, Vector2(float(q[0]), float(q[1])))
			w -= n * n.dot(w - bb.get_center())   # onto the body's middle along the normal: only the in-face position counts
			if not g.has_point(w):
				return true
	return false


func _spin(rec: Dictionary) -> String:
	var sid := Part.profile_sketch(rec)
	if sid == "" or Part.sketch_used(rec, sid):
		return "That shape is solid already. Draw a new one, then Spin it round"
	var axis := "x"
	var sk := Part.feature(rec, sid)
	var before := sk.duplicate(true)   # a refused spin gives the drawing back as it was (it is not used up)
	var pf := Part.feature(rec, String(sk.get("plane", "")))
	var on_piece := false   # ELAMP: a profile drawn ABOVE a solid already in the part (a shade on a lamp stick) keeps the height it was drawn
	if String(sk.get("plane", "")) == "top":
		_stand_up(sk)   # a floor drawing is flat: spun round the up axis it has no volume, so it stands up first (a lathe profile)
		axis = "y"
	elif String(pf.get("t", "")) == "plane" and bool(pf.get("through", false)):
		# an UPRIGHT drawing (side-on, through the middle): the bowl turns round the UP line through the middle (the sketch's
		# vertical axis, x = 0), so the profile must lie on one side of that line. Its lowest point goes down to the floor,
		# unless it starts on a piece already standing (then it stays where it was drawn, joined to that piece).
		on_piece = _starts_on_piece(rec, sk)
		if not on_piece:
			_lift_to_floor(sk)
		axis = "y"
	if axis == "y" and _past_axis(sk) < -3.0 and _on_left(sk):
		_flip_x(sk)   # a drawing wholly on the -X side is the same solid as its mirror image on the +X side (a lathe is symmetric): flip it, then spin
	if axis == "y" and _past_axis(sk) < -3.0:
		sk.clear()
		sk.merge(before, true)
		return "A shape that crosses the middle line cannot be spun: draw it on one side"
	var f := Part.new_feature(rec, "revolve", {"sketch": sid, "axis": axis, "deg": 360.0, "op": "join", "onside": axis == "y"})
	rec["features"].append(f)
	if _last_error(rec, String(f["id"])) != "":
		rec["features"].pop_back()
		sk.clear()
		sk.merge(before, true)
		return "A shape that crosses the middle line cannot be spun: draw it on one side"
	if axis == "y" and not on_piece:
		# a spline dips a little below its points: the solid's real lowest point goes onto the floor (a bowl's foot is on the floor, not in it)
		var low := float(Part.replay(rec)["aabb"].position.y) / Part.MM
		if absf(low) > 0.001:
			_shift_y(sk, low)
	tweak = {"id": f["id"], "field": "deg", "label": "How far round", "unit": "deg", "lo": 10.0, "hi": 360.0, "step": 5.0, "scale": 1.0, "words": ["A bit", "All the way"]}
	_say("Spun all the way round: use the slider for less, or press Cut a hole or Mirror that next")
	return ""



## ELAMP: true when the upright drawing starts ABOVE the floor and on a solid already in the part: its lowest point (mm) lies within
## the solid's height range (a shade whose first point is on a stick top). A drawing on the floor, or in the air over nothing, is not on a piece
func _starts_on_piece(rec: Dictionary, sk: Dictionary) -> bool:
	var res := Part.replay(rec)
	if int(res["bodies"]) == 0:
		return false
	var bb: AABB = res["aabb"]
	var bot := bb.position.y / Part.MM
	var top := bb.end.y / Part.MM
	var low := INF
	for e in sk["ents"]:
		for q in _ent_pts(e):
			low = minf(low, float(q[1]))
	if low == INF:
		return false
	return low > 0.5 and low >= bot - 0.5 and low <= top + 0.5


## SPIN A FLOOR DRAWING: the sketch moves from the floor (top plane) to the front plane, its far edge up, and slides so its nearest point
## sits on the floor: spun round the up axis it is a lathe piece (a ring, a vase) standing on the floor beside the middle line
func _stand_up(sk: Dictionary) -> void:
	_lift_to_floor(sk)
	sk["plane"] = "front"


## the drawing slides up or down (in its own plane) so its lowest point sits on the floor (y = 0)
func _lift_to_floor(sk: Dictionary) -> void:
	var lo := INF
	for e in sk["ents"]:
		for q in _ent_pts(e):
			lo = minf(lo, float(q[1]) - (float(e["r"]) if e.has("r") and String(e["k"]) == "circle" else 0.0))
	if lo == INF:
		lo = 0.0
	_shift_y(sk, lo)


## how far the drawing reaches past the middle line (x < 0, mm; 0 when it stays on the +X side). A spline counts where its curve goes, not only its points
func _past_axis(sk: Dictionary) -> float:
	var lo := 0.0
	for e in sk["ents"]:
		if String(e["k"]) == "bspline":
			for q in Part.spline_curve(e.get("pts", []), bool(e.get("closed", false)), 16):
				lo = minf(lo, q.x)
		elif String(e["k"]) == "circle":
			lo = minf(lo, float(e["c"][0]) - float(e["r"]))
		else:
			for q in _ent_pts(e):
				lo = minf(lo, float(q[0]))
	return lo


## true when no point of the drawing is on the +X side of the middle line (x <= 0.5 mm everywhere)
func _on_left(sk: Dictionary) -> bool:
	for e in sk["ents"]:
		for q in _ent_pts(e):
			if float(q[0]) > 0.5:
				return false
	return true


## every point of the drawing reflects across the middle line (x = -x, mm); a circle's centre moves with it, its radius does not
func _flip_x(sk: Dictionary) -> void:
	for e in sk["ents"]:
		for q in _ent_pts(e):
			q[0] = -float(q[0])


## every point of the drawing moves down by lo (mm) in its own plane
func _shift_y(sk: Dictionary, lo: float) -> void:
	for e in sk["ents"]:
		for q in _ent_pts(e):
			q[1] = snappedf(float(q[1]) - lo, 0.0001)


## the [x, y] points of a sketch entity (the arrays themselves: writing them moves the entity)
func _ent_pts(e: Dictionary) -> Array:
	var out := []
	for k in ["a", "b", "m", "c"]:
		if e.has(k) and e[k] is Array:
			out.append(e[k])
	if e.has("pts"):
		out.append_array(e["pts"])
	return out


func _round(rec: Dictionary) -> String:
	var res := Part.replay(rec, -1, {"edges": true})
	if int(res["bodies"]) == 0:
		return "Nothing solid to round yet. Press Pull it up first"
	var es: Array = res["edges"]
	var aabb: AABB = res["aabb"]
	var small := minf(aabb.size.x, minf(aabb.size.y, aabb.size.z)) / Part.MM
	var longest := 0.0
	for e in es:
		longest = maxf(longest, float(e["len"]))
	# EROUND: the edges are tried on ONE kept replay of the body as it is before the round (a kernel fillet per try), not a replay of the whole
	# record per try: a press on a part of 25+ steps took minutes that way. The search stops at ROUND_BUDGET_US and keeps the best found
	var kept: Array = Part.replay(rec, -1, {"keep": true}).get("ids", [])
	var done := false
	if not kept.is_empty():
		done = _round_on(rec, int(kept[0]), es, small, longest)
	Part.release_kept(kept)
	if done:
		return ""
	return "These edges are too small or too crowded to round: Pull it up taller, then press Round the edges again"


## EROUND: the round on body (a kept solid of the record's end). True when a fillet step was added to rec
func _round_on(rec: Dictionary, body: int, es: Array, small: float, longest: float) -> bool:
	# EBACK: the default never sits below the slider's own low end (1 mm, "Barely"): a thin part's 0.5 mm default looked square
	for attempt in [[1.0, 0.0], [0.5, 0.0], [0.5, 0.2]]:
		var r := clampf(small * 0.01 * float(attempt[0]), 1.0, 6.0)
		var list := []
		for e in es:
			if int(e["body"]) == 0 and float(e["len"]) >= longest * float(attempt[1]) and float(e["len"]) / Part.MM > r * 2.5:
				list.append(Part.describe(e))
		if list.is_empty():
			continue
		if Part.fillet_trial(body, snappedf(r, 0.1), list) != "":
			continue
		var f := Part.new_feature(rec, "fillet", {"body": 0, "r": snappedf(r, 0.1), "edges": list})
		rec["features"].append(f)
		if _last_error(rec, String(f["id"])) == "":
			_round_done(f)
			return true
		rec["features"].pop_back()
	# a thin part (the sword's blade: 7 mm across the spine, edges 0.4 mm) cannot take the 0.5 mm floor on every edge: round the edges that
	# can take a smaller radius and skip the rest. Each edge is tried with the ones already kept, so the feature that is added has no error
	var out_of_time := false
	var t1 := Time.get_ticks_usec()   # the budget is for this search (the three tries above are one kernel fillet each)
	for r0 in [1.0, 0.5, 0.3, 0.1]:   # EBACK: 1 mm first (the slider's low end), then the smaller radii
		var r := snappedf(r0, 0.1)
		var good := []
		for e in es:
			if Time.get_ticks_usec() - t1 > ROUND_BUDGET_US:
				out_of_time = true
				break
			if int(e["body"]) == 0 and float(e["len"]) / Part.MM > r * 2.5:
				var trial := good.duplicate()
				trial.append(Part.describe(e))
				if Part.fillet_trial(body, r, trial) == "":
					good = trial
		if not good.is_empty():
			var f := Part.new_feature(rec, "fillet", {"body": 0, "r": r, "edges": good})
			rec["features"].append(f)
			_round_done(f)
			return true
		if out_of_time:
			break
	return false


func _round_done(f: Dictionary) -> void:
	tweak = {"id": f["id"], "field": "r", "label": "How round", "unit": "cm", "lo": 0.1, "hi": 1.0, "step": 0.1, "scale": 10.0, "words": ["Barely", "Very round"]}
	_say("Edges rounded: use the slider for more or less, or press Cut a hole next")


func _hole(rec: Dictionary) -> String:
	var res := Part.replay(rec)
	if int(res["bodies"]) == 0:
		return "Nothing solid to cut a hole in yet. Press Pull it up first"
	if _face_sketch_last(rec):   # a shape drawn on a face and not pulled yet: the hole IS that shape (a door or a window)
		return _face_hole(rec)
	if _piece_hole(rec):   # the newest piece is an upright or a face sketch: the hole goes through IT
		return ""
	var bb: AABB = res["aabb"]
	var c := bb.get_center() / Part.MM
	var floor_made := _base_plane(rec, _newest_sketch_plane(rec)) == "top"   # a body drawn on the floor is cut DOWN through (its hole runs up/down)
	var r := clampf(minf(bb.size.x, bb.size.z if floor_made else bb.size.y) / Part.MM * 0.12, 10.0, 40.0)   # the radius in mm: a hole 2 to 8 cm across
	var s: Dictionary
	var f: Dictionary
	# "both" splits dist half each way from the sketch plane: twice the body's farthest reach + 1 cm, so a tall body is cut all the way
	if floor_made:
		s = Part.new_feature(rec, "sketch", {"plane": "top", "ents": [{"k": "circle", "c": Part.arr2(Vector2(c.x, -c.z)), "r": snappedf(r, 0.5)}], "dims": []})   # the top plane's v axis is -Z
		rec["features"].append(s)
		f = Part.new_feature(rec, "extrude", {"sketch": s["id"], "dist": snappedf(2.0 * (maxf(absf(bb.position.y), absf(bb.end.y)) / Part.MM + 10.0), 1.0), "both": true, "op": "cut"})
	else:
		s = Part.new_feature(rec, "sketch", {"plane": "front", "ents": [{"k": "circle", "c": Part.arr2(Vector2(c.x, c.y)), "r": snappedf(r, 0.5)}], "dims": []})
		rec["features"].append(s)
		f = Part.new_feature(rec, "extrude", {"sketch": s["id"], "dist": snappedf(2.0 * (maxf(absf(bb.position.z), absf(bb.end.z)) / Part.MM + 10.0), 1.0), "both": true, "op": "cut"})
	rec["features"].append(f)
	var before := float(res["volume"])
	var after := float(pu.replay_full(rec)["volume"])
	if after >= before - 1e-12:
		return "The hole would miss the shape: nothing was cut"
	tweak = {"id": s["id"], "ent": 0, "field": "r", "label": "Hole size", "unit": "cm", "lo": 0.6, "hi": 16.0, "step": 0.1, "scale": 5.0, "words": ["Smaller", "Bigger"]}   # the slider is the hole's WIDTH (cm): radius mm = width cm * 5
	_say("A hole straight through: use the slider for its size, or press Mirror that or Repeat it next")
	return ""


## EDOOR: the newest step is a sketch drawn ON A FACE (a plane feature with "out") that no pull uses yet
func _face_sketch_last(rec: Dictionary) -> bool:
	var feats: Array = rec.get("features", [])
	if feats.is_empty() or String(feats[feats.size() - 1]["t"]) != "sketch":
		return false
	var sk: Dictionary = feats[feats.size() - 1]
	if Part.sketch_used(rec, String(sk["id"])):
		return false
	var pf := Part.feature(rec, String(sk.get("plane", "")))
	return String(pf.get("t", "")) == "plane" and pf.has("out") and not bool(pf.get("through", false))


## EDOOR: CUT A HOLE IN THE DRAWN SHAPE. The shape (a rectangle, circle, or any closed sketch on the face) is cut INWARD from its face,
## as one extrude-cut. Depth = the first inside surface along the shape (3 by 3 points over it): a hollow house stops at the far side of the
## one wall it sits on; a solid body is cut all the way through. The slider is the depth (cm). The old circle is not used for a face shape.
func _face_hole(rec: Dictionary) -> String:
	var sk: Dictionary = rec["features"][rec["features"].size() - 1]
	var pid := String(sk["plane"])
	var out := float(Part.feature(rec, pid)["out"])   # +1 / -1: the face's normal side (a pull goes this way)
	var before := Part.replay(rec)
	var pl := Part.resolve_plane(rec, pid)
	var tris := _tris_local(before, pl)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for e in sk["ents"]:
		var rr := float(e.get("r", 0.0))
		for q in _ent_pts(e):
			var v := Vector2(float(q[0]), float(q[1]))
			lo = lo.min(v - Vector2(rr, rr))
			hi = hi.max(v + Vector2(rr, rr))
	var depth := INF
	for i in 3:
		for j in 3:
			var p := Vector2(lerpf(lo.x, hi.x, i / 2.0), lerpf(lo.y, hi.y, j / 2.0))
			depth = minf(depth, _first_inside(tris, p, out))
	if depth == INF:
		return "The shape is not on the solid: nothing was cut"
	var sgn := -out   # the cut goes INTO the body, against the face's normal side
	var f := Part.new_feature(rec, "extrude", {"sketch": sk["id"], "dist": sgn * snappedf(depth + 0.5, 0.1), "both": false, "op": "cut"})
	rec["features"].append(f)
	if _last_error(rec, String(f["id"])) != "" or float(pu.replay_full(rec)["volume"]) >= float(before["volume"]) - 1e-12:
		return "The hole would miss the shape: nothing was cut"
	tweak = {"id": f["id"], "field": "dist", "label": "How deep", "unit": "cm", "lo": 0.1, "hi": 40.0, "step": 0.1, "scale": 10.0, "words": ["Shallower", "Deeper"], "sgn": sgn}
	_say("A hole in the wall: use the slider for how deep")
	return ""


## EDOOR: the distance (mm) from the local point q (the face's plane, z = 0 at the face) to the first surface of the mesh tris going
## INTO the body (direction -out): the smallest hit beyond the face itself (0.05 mm). INF = no surface under q
func _first_inside(tris: PackedVector3Array, q: Vector2, out: float) -> float:
	var best := INF
	var d := -out
	for i in range(0, tris.size() - 2, 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		var den := (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
		if absf(den) < 1e-12:
			continue
		var l1 := ((b.y - c.y) * (q.x - c.x) + (c.x - b.x) * (q.y - c.y)) / den
		var l2 := ((c.y - a.y) * (q.x - c.x) + (a.x - c.x) * (q.y - c.y)) / den
		var l3 := 1.0 - l1 - l2
		if l1 < -1e-9 or l2 < -1e-9 or l3 < -1e-9:
			continue
		var t := (l1 * a.z + l2 * b.z + l3 * c.z) * d   # the hit's depth along the inward direction
		if t > 0.05 and t < best:
			best = t
	return best


## A HOLE THROUGH THE NEW PIECE: when the last step is a Pull (extrude) of a sketch on a plane feature (an upright through the middle, or a face),
## the hole is a circle on that same plane, cut along the pull, centred on the part of the piece that sticks OUT of the rest of the body,
## radius 0.6 x the half-size of that part (min 3 mm). The cut must take only the piece's own material (checked by volume). false = no such piece
func _piece_hole(rec: Dictionary) -> bool:
	var feats: Array = rec.get("features", [])
	if feats.is_empty() or String(feats[feats.size() - 1]["t"]) != "extrude":
		return false
	var last: Dictionary = feats[feats.size() - 1]
	var sk := Part.feature(rec, String(last.get("sketch", "")))
	if sk.is_empty():
		return false
	var pid := String(sk.get("plane", ""))
	var k := Part.index_of(rec, pid)
	if k < 0 or String(feats[k]["t"]) != "plane":
		return false
	var through := bool(feats[k].get("through", false))
	var sg := -1.0 if float(last.get("dist", 0.0)) < 0.0 else 1.0
	var before := Part.replay(rec)
	if int(before["bodies"]) == 0:
		return false
	var body_before := float(before["volume"])
	var pl := Part.resolve_plane(rec, pid)
	var tail: Array = feats.slice(k)
	var piece_rec := rec.duplicate(true)
	piece_rec["features"] = tail.duplicate(true)
	var pre_rec := rec.duplicate(true)
	pre_rec["features"] = feats.slice(0, k).duplicate(true)
	var ptris := _tris_local(Part.replay(piece_rec), pl)
	if ptris.is_empty():
		return false
	var rtris := _tris_local(Part.replay(pre_rec), pl) if k > 0 else PackedVector3Array()
	var zmin := INF
	var zmax := -INF
	for v in ptris:
		zmin = minf(zmin, v.z)
		zmax = maxf(zmax, v.z)
	# the sticking-out part: the piece's outline points (its mesh vertices) that are NOT inside the rest of the body. The kernel's volume
	# check below keeps the hole out of the rest either way
	var zc := (zmin + zmax) * 0.5   # the rest is read at the piece's middle height
	var smin := Vector2(INF, INF)
	var smax := Vector2(-INF, -INF)
	var nst := 0
	for v in ptris:
		var q := Vector2(v.x, v.y)
		if not _inside(rtris, q, zc):
			smin = smin.min(q)
			smax = smax.max(q)
			nst += 1
	if nst == 0:
		return false
	var c2 := (smin + smax) * 0.5
	var half := minf(smax.x - smin.x, smax.y - smin.y) * 0.5
	var r0 := maxf(3.0, 0.6 * half)
	var reach := maxf(absf(zmin), absf(zmax)) + 1.0
	var rest_before := float(Part.replay(pre_rec)["volume"]) if k > 0 else 0.0
	var n0 := feats.size()
	for scale in [1.0, 0.75, 0.5]:
		var r := snappedf(maxf(3.0, r0 * scale), 0.1)
		var s := Part.new_feature(rec, "sketch", {"plane": pid, "ents": [{"k": "circle", "c": Part.arr2(c2), "r": r}], "dims": []})
		rec["features"].append(s)
		var f: Dictionary
		if through:
			f = Part.new_feature(rec, "extrude", {"sketch": s["id"], "dist": snappedf(2.0 * reach, 0.1), "both": true, "op": "cut"})
		else:
			f = Part.new_feature(rec, "extrude", {"sketch": s["id"], "dist": snappedf(sg * reach, 0.1), "both": false, "op": "cut"})
		rec["features"].append(f)
		var after := float(Part.replay(rec)["volume"])
		var removed := body_before - after
		# the rest of the body (the features before the piece) must lose nothing to the same cut: only the piece is cut
		var pre_after := rest_before
		if k > 0:
			var pr: Dictionary = pre_rec.duplicate(true)
			pr["features"] = (pre_rec["features"] as Array).duplicate(true)
			pr["features"].append(s.duplicate(true))
			pr["features"].append(f.duplicate(true))
			pre_after = float(Part.replay(pr)["volume"])
		var rest_removed := rest_before - pre_after
		if removed > 1e-12 and rest_removed <= 0.005 * body_before and removed - rest_removed > 1e-12:
			tweak = {"id": s["id"], "ent": 0, "field": "r", "label": "Hole size", "unit": "cm", "lo": 0.6, "hi": 16.0, "step": 0.1, "scale": 5.0, "words": ["Smaller", "Bigger"]}
			_say("A hole through the new piece: use the slider for its size")
			return true
		rec["features"].resize(n0)
	return false


## a mesh's triangles in the plane's own axes (mm): x along the plane, y up it, z along its normal
func _tris_local(r: Dictionary, pl: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	var mesh: ArrayMesh = r.get("mesh")
	if mesh == null:
		return out
	var o: Vector3 = pl["o"]
	var px: Vector3 = pl["x"]
	var py: Vector3 = pl["y"]
	var pn: Vector3 = pl["n"]
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix = arr[Mesh.ARRAY_INDEX]
		var idx: PackedInt32Array
		if ix == null:
			idx = PackedInt32Array()
			for i in vs.size():
				idx.append(i)
		else:
			idx = ix
		for i in idx:
			var d := vs[i] - o
			out.append(Vector3(d.dot(px), d.dot(py), d.dot(pn)) / Part.MM)
	return out


## is the point (q, zq) inside the closed mesh t (local tris)? Odd number of crossings of the ray from it up along +z
func _inside(t: PackedVector3Array, q: Vector2, zq: float) -> bool:
	var hits := 0
	for i in range(0, t.size() - 2, 3):
		var a := t[i]
		var b := t[i + 1]
		var c := t[i + 2]
		var d1 := (b.x - a.x) * (q.y - a.y) - (b.y - a.y) * (q.x - a.x)
		var d2 := (c.x - b.x) * (q.y - b.y) - (c.y - b.y) * (q.x - b.x)
		var d3 := (a.x - c.x) * (q.y - c.y) - (a.y - c.y) * (q.x - c.x)
		if (d1 < 0.0 or d2 < 0.0 or d3 < 0.0) and (d1 > 0.0 or d2 > 0.0 or d3 > 0.0):
			continue
		var nrm := (b - a).cross(c - a)
		if absf(nrm.z) < 1e-12:
			continue
		var z := a.z - (nrm.x * (q.x - a.x) + nrm.y * (q.y - a.y)) / nrm.z
		if z > zq:
			hits += 1
	return hits % 2 == 1


## the plane id of the newest sketch (the front plane when there is none)
func _newest_sketch_plane(rec: Dictionary) -> String:
	var pid := "front"
	for f in rec.get("features", []):
		if f["t"] == "sketch":
			pid = String(f.get("plane", "front"))
	return pid


## the Part base plane ("front" | "top" | "right") a sketch's plane id sits on: an offset plane's base is its "from"
func _base_plane(rec: Dictionary, pid: String) -> String:
	if pid in Part.PLANES:
		return pid
	var pf := Part.feature(rec, pid)
	return String(pf.get("from", "front")) if String(pf.get("t", "")) == "plane" else "front"


func _mirror(rec: Dictionary) -> String:
	var res := Part.replay(rec)
	if int(res["bodies"]) == 0:
		return "Nothing solid to mirror yet. Press Pull it up first"
	var bb: AABB = res["aabb"]
	var off := bb.position.x > 0.0005 or bb.end.x < -0.0005   # EMIRROR: the solid does not touch the middle line (x = 0)
	var f := Part.new_feature(rec, "mirror", {"plane": "right", "op": "join"})
	if off:
		f["mid"] = true   # the mirror plane goes through the middle of the part, not the world line
	rec["features"].append(f)
	if _last_error(rec, String(f["id"])) != "":
		return "That shape cannot be mirrored"
	tweak = {}
	var after: Dictionary = pu.replay_full(rec)
	var gap := int(after["bodies"]) == 1 and _lumps(after) > 1   # the mirror left a gap: the same test as the status line
	var where := "across the middle of the part" if off else "across the middle line"
	_say("Mirrored %s" % where + (": the two halves do not touch. Push them together with Stick together" if gap else ": press Repeat it or Cut a hole next"))
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
	var same := String(a["plane"]) == String(b["plane"])
	var pa := Part.resolve_plane(rec, String(a["plane"]))
	var pb := Part.resolve_plane(rec, String(b["plane"]))
	# EBLEND: a loft between two shapes whose planes are at an angle (a round on a face, a box on the side face) makes an EMPTY solid: refuse it in words
	if absf((pa["n"] as Vector3).dot(pb["n"] as Vector3)) < 0.999:
		return "Those two shapes sit at an angle to each other, so they cannot blend. Draw both on the floor, or both on faces that face the same way, then press Blend two shapes again"
	if not same:   # two offset planes (an upright sketch through the middle is one) at the same spot are the same plane
		same = (pa["n"] as Vector3).dot(pb["n"] as Vector3) > 0.999 and ((pa["o"] as Vector3) - (pb["o"] as Vector3)).length() < 0.01 * Part.MM
	if same:
		var base := String(a["plane"]) if String(a["plane"]) in Part.PLANES else _base_plane(rec, String(a["plane"]))
		var mm_a := 0.0 if String(a["plane"]) in Part.PLANES else float(Part.feature(rec, String(a["plane"])).get("mm", 0.0))
		# the offset plane and a copy of the newer shape go at the END: a template owns its first features and rewrites them by index
		# (PartTemplates.retemplate), so a step inserted among them was overwritten by a slider (nfillet, chaos seed 5)
		var pl := Part.new_feature(rec, "plane", {"from": base, "mm": mm_a + 40.0})   # the newer shape 40 mm off the older one, along the normal
		rec["features"].append(pl)
		var nb := Part.new_feature(rec, "sketch", {"plane": String(pl["id"]), "ents": (b["ents"] as Array).duplicate(true), "dims": (b.get("dims", []) as Array).duplicate(true)})
		rec["features"].append(nb)
		b = nb
	var f := Part.new_feature(rec, "loft", {"sketches": [a["id"], b["id"]], "ruled": true, "op": "join"})
	rec["features"].append(f)
	if _last_error(rec, String(f["id"])) != "":
		return "Those two shapes cannot be blended into one solid: draw both as closed shapes, then press Blend two shapes again"
	# EBLEND: the loft alone must be a solid with volume (a loft that comes out empty used to be reported as blended)
	var solo := {"version": 1, "name": "blend", "seq": 0, "features": []}
	for g in rec["features"]:
		if String(g["t"]) == "plane" or String(g["id"]) in [String(a["id"]), String(b["id"]), String(f["id"])]:
			solo["features"].append(g)
	var sr := Part.replay(solo)
	if int(sr["bodies"]) != 1 or float(sr["volume"]) <= 1e-12:
		return "Those two shapes cannot be blended into one solid: draw both as closed shapes that face the same way, then press Blend two shapes again"
	tweak = {}
	_say("Blended the two last shapes into one solid: press Colour or Round the edges next")
	return ""


## CUT IN TWO: a split across the middle of the solid's longest side (Part's "split" feature, the one Expert's Split makes). The slider
## moves the cut along that side: its step is the split, its field the offset in mm (the slider says cm)
func _cut(rec: Dictionary) -> String:
	var res := Part.replay(rec)
	if int(res["bodies"]) == 0:
		return "Nothing solid to cut yet. Press Pull it up first"
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
	if _last_error(rec, String(f["id"])) != "" or int(pu.replay_full(rec)["bodies"]) < 2:
		return "The cut would miss the solid: nothing was cut"
	tweak = {"id": f["id"], "field": "at", "label": "Where to cut", "unit": "cm", "lo": snappedf(lo_mm * 0.1 + 0.2, 0.1), "hi": snappedf(hi_mm * 0.1 - 0.2, 0.1), "step": 0.1, "scale": 10.0, "words": ["Toward one end", "Toward the other end"]}
	_say("Cut in two across the middle: drag the slider to move the cut")
	return ""


## ECUT2: the keep chips are shown while the newest step is the cut (its slider's step) and nothing is armed
func _split_on() -> bool:
	return split_id != "" and armed == "" and String(tweak.get("id", "")) == split_id and not Part.feature(_rec(), split_id).is_empty()


func _split_sync() -> void:
	var keep := _split_keep_of()
	for k in split_btns:
		(split_btns[k] as Button).set_pressed_no_signal(k == keep)


func _split_keep_of() -> String:
	var f := Part.feature(_rec(), split_id)
	var kp := int(f.get("keep", 0))
	return "upper" if kp > 0 else ("lower" if kp < 0 else "both")


## a keep chip: the cut step's "keep" field changes (one undo step). A chip that is already on changes nothing; a refusal changes nothing
func _split_keep(key: String) -> void:
	if not _split_on() or not Part.available() or key == _split_keep_of():
		_split_sync()
		return
	_flush_if_dirty()
	armed = ""
	var snap := _rec().duplicate(true)
	_begin("Keep " + String(split_btns[key].text).trim_prefix("Keep ").to_lower())
	var rec := _rec()
	var kp := 0 if key == "both" else (1 if key == "upper" else -1)
	Part.feature(rec, split_id)["keep"] = kp
	var why := _last_error(rec, split_id)
	if why == "" and kp != 0 and int(Part.replay(rec)["bodies"]) == 0:
		why = "Nothing would be left: keep both halves"
	if why != "":
		m.S.part = snap
		m._drop_undo()
		_edit_n = -1
		_say("That half cannot be kept: " + why)
	else:
		_end()
		_say("Kept the upper half: the other half is gone (Undo brings it back)" if kp > 0 else ("Kept the lower half: the other half is gone (Undo brings it back)" if kp < 0 else "Kept both halves of the cut"))
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_values_sync()
	_split_sync()


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


## Corners (EREPEAT): the newest piece goes to the four corners of the body it touches, one undo step; the four become one body with it
func _rep_corners() -> void:
	if Part.feature(_rec(), rep_id).is_empty():
		return
	_flush_if_dirty()
	_begin("Corners")
	var cur := Part.feature(_rec(), rep_id)
	cur["kind"] = "corners"
	cur["count"] = 4
	_end()
	pu.sync()
	_rep_sync()
	var err: String = pu.replay_full(_rec())["errors"].get(rep_id, "")
	if err != "":
		_say(_plain(err) + ". Move the piece onto a corner of the piece it sits on, then press Corners again, or undo")
	else:
		_say("Corners: four copies, one at each corner of the piece it sits on")


## Row (linear, along X) or Ring (circular, round the up axis Y, a full turn): one undo step; Gap spaces both (in a Ring it sets the circle size)
func _rep_mode(ring: bool) -> void:
	if Part.feature(_rec(), rep_id).is_empty():
		return
	_flush_if_dirty()
	_begin("Ring" if ring else "Row")
	var cur := Part.feature(_rec(), rep_id)
	cur["kind"] = "circular" if ring else "linear"
	cur["beside"] = ring   # round a point beside the piece: a ring round the origin piles copies of a piece AT the origin onto each other
	cur["axis"] = "y"
	cur["deg"] = 360.0
	cur["dir"] = "x"
	cur["mm"] = float(cur.get("w", 10.0)) + float(cur.get("gap", 10.0))
	_end()
	pu.sync()
	_rep_sync()
	_values_sync()
	_say("Ring: the copies go round in a circle beside it" if ring else "Row: the copies go in a straight line")


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
	if why == "" and op == "join":   # JOIN: the two picks must touch (apart pieces would "join" into one body with a gap: refused, nothing changes)
		why = _join_gap(Part.body_faces(snap, -1), stick_picks)
	stick_picks = []
	if why != "":
		m.S.part = snap
		m._drop_undo()
		_edit_n = -1
		_say("Those two pieces cannot do that: " + _plain(why))
	else:
		_end()
		_say("%s: the two pieces are one solid now" % label)
	tweak = {}
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_values_sync()


## JOIN: the two picked pieces must touch (the smallest distance between their triangles is under 0.05 mm). "" or the words for the user
static func _join_gap(before: Array, picked: Array) -> String:
	if picked.size() < 2:
		return ""
	var gap := Part._tri_dist(before[int(picked[0])], before[int(picked[1])])
	if gap > 0.00005:
		return "the two pieces do not touch, so Join cannot make one solid: move one until it touches the other, then press Stick together again"
	return ""


## a click in the view while Stick together is armed: the body under the pointer is picked (a second click takes it off)
func _stick_pick(bi: int, faces: Array) -> void:
	if stick_picks.has(bi):
		stick_picks.erase(bi)
		stick_tris.erase(bi)
		stick_edges.erase(bi)
	elif stick_picks.size() < 2:
		stick_picks.append(bi)
		stick_tris[bi] = faces[bi]
		stick_edges[bi] = _creases(faces[bi])
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
	(rep_btns["row"] as Button).set_pressed_no_signal(String(f.get("kind", "linear")) == "linear")
	(rep_btns["ring"] as Button).set_pressed_no_signal(ring)
	(rep_btns["corners"] as Button).set_pressed_no_signal(String(f.get("kind", "")) == "corners")
	var rows_on := String(f.get("kind", "")) != "corners"   # CORNERS: four copies at the corners, no How many or Gap to set
	for r in rep_rows:
		(r["box"] as Control).visible = rows_on
	for r in rep_rows:
		var s: HSlider = r["slider"]
		var v := float(f.get("count", 3)) if String(r["key"]) == "count" else float(f.get("gap", 10.0)) / 10.0
		if not bool(r.get("held", false)):
			s.set_value_no_signal(v)
		_pill_text(r, v)


## CURVY LINE: the drag's points (sampled to 12) become one spline sketch (Part's "bspline" entity; the kernel gets the curve it draws).
## Closed when the drag comes back to its start
func _finish_curve() -> void:
	var pts: Array = _draft.get("pts", [])
	var fc: Dictionary = _draft.get("face", {})
	_draft = {}
	if pts.size() < 4:
		_say("Drag a bit further to draw a curve: keep the button held and move at least 5 mm")
		return
	var out := []
	for k in _curve_keep(pts, 12):
		out.append(Part.arr2(pts[k]))
	var closed := (pts[pts.size() - 1] as Vector2).distance_to(pts[0] as Vector2) <= 12.0
	_begin("Curvy line")
	var rec := pu._ensure()
	rec["features"].append(Part.new_feature(rec, "sketch", {"plane": _face_plane(rec, fc), "ents": [{"k": "bspline", "pts": out, "closed": closed}], "dims": []}))
	_end()
	armed = ""
	tweak = {}
	pu.upto = -1
	pu.sync()
	_rows_sync()
	# a curve that touches or crosses the middle line (x = 0) is a profile to spin: the words point to Spin it round
	var spin_ok := false
	for q in pts:
		if (q as Vector2).x <= 1.0:
			spin_ok = true
	if spin_ok:
		_say("Curvy line drawn: Spin it round makes a bowl, or Pull it up makes it solid" if closed else "Curvy line drawn: for a pipe, Sweep the round shape along it (Expert: CREATE, Sweep). Or drag back to the start to close it")
	else:
		_say("Curvy line drawn: Pull it up makes it solid" if closed else "Curvy line drawn: for a pipe, Sweep the round shape along it (Expert: CREATE, Sweep). Or drag back to the start to close it")   # FPIPE: an open line's next step names the pipe (a sweep), not only the closing


## the drawn points kept for the spline (at most maxn, first and last always): the points that bend the line most, so a rim or a
## corner the user drew stays a point the spline passes through (an even pick by index rounded the cup's rim down 5 mm)
func _curve_keep(pts: Array, maxn: int) -> Array:
	var n := pts.size()
	if n <= maxn:
		var all := []
		for i in n:
			all.append(i)
		return all
	var keep := [0, n - 1]
	while keep.size() < maxn:
		keep.sort()
		var best := -1
		var best_d := 0.0
		for j in range(keep.size() - 1):
			var a: Vector2 = pts[keep[j]]
			var b: Vector2 = pts[keep[j + 1]]
			for i in range(keep[j] + 1, keep[j + 1]):
				var q: Vector2 = pts[i]
				var ln := a.distance_to(b)
				var d := q.distance_to(a) if ln < 1e-6 else absf((b - a).cross(q - a)) / ln   # a closed line's ends meet: the far point is the bend
				if d > best_d:
					best_d = d
					best = i
		if best < 0 or best_d < 0.3:
			break   # the rest of the line is straight: the points already kept carry it
		keep.append(best)
	keep.sort()
	return keep


# ---------------------------------------------------------------- every frame

func _process(_dt: float) -> void:
	if bar == null or pu == null:
		return
	pu.replay_forget()   # the same-frame replay reuse (PartUI.replay_once) ends with the frame
	var on := active()
	if on != _was:
		_was = on
		if not on:
			armed = ""
			_drag = {}
			_draft = {}
		elif m.cam != null and _side_on():
			m.pitch = ENTRY_PITCH   # Easy Part opens LOOKING DOWN: the app's level start view (-8 deg) would make every first drawing upright
			m._cam()
	if on and _near_saved < 0.0 and m.cam != null:
		_near_saved = m.cam.near
		_grid_framed = false
		_grid_cam = []
		m.cam.near = minf(_near_saved, FRAME_NEAR)   # EFRAME: a small part framed close (the plate's corners stay in front of the lens)
	elif not on and _near_saved >= 0.0 and m.cam != null:
		m.cam.near = _near_saved
		_near_saved = -1.0
	_floor_sync(on)
	_upright_sync(on and (armed == "draw" or armed == "curve") and _side_on())
	bar.visible = on
	make_box.visible = on
	panel.visible = on
	hint.visible = on
	status.visible = on
	dots.visible = on
	shape_box.visible = on and armed == "draw"
	hole_box.visible = on and _hole_on()
	split_box.visible = on and _split_on()
	if split_box.visible:
		_split_sync()
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
	var sig := JSON.stringify(rec.get("easy", {})) + str(rec.get("features", []).size()) + str(m.redo.size()) + str(m.undo.size()) + str(pu.res.get("bodies", 0)) + str(pu.res.get("volume", 0.0)) + str(Part.available()) + str(armed) + msg   # undo depth + the result: a slider edit of a step changes no step count
	if sig != _sig and _drag.is_empty() and not _dirty:
		_sig = sig
		_chrome_sync()
	if dots.visible and (not _drag.is_empty() or not _draft.is_empty()):
		dots.queue_redraw()
	if m.cam != null:
		dots.queue_redraw()
	_frame_step()


## EFRAME: after a step that changes the part's box a lot, the camera eases so the box fills FRAME_FILL of the free view.
## Never while the mouse is held (a drag, an orbit, a pan) and never for a small edit: the reference box moves only when framed.
func _frame_step() -> void:
	if m.cam == null or pu.res.is_empty():
		_frame_grid()   # GRIDFRAME: an empty part has no box: its floor grid is framed instead (once per visit)
		if not _ease.is_empty():
			_ease_step()
		return
	var held := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) or not _drag.is_empty() or not _draft.is_empty()
	if held:
		_ease = {}   # the user has the view: the ease stops where it is
		return
	if not _ease.is_empty():
		_ease_step()
		return
	var bb: AABB = pu.res.get("aabb", AABB())
	var len := bb.size.length()
	if not _fr_has:
		_fr_ref = bb
		_fr_has = true
		return
	var ref_len := _fr_ref.size.length()
	if len < 1e-4:
		_fr_ref = bb   # an empty part: nothing to frame yet
		_frame_grid()  # GRIDFRAME: its floor grid is framed instead (once per visit)
		if not _ease.is_empty():
			_ease_step()
		return
	# FREEWALK D2: a step that keeps the box size (Cut a hole) can still leave the solid off the screen: then frame it again
	var off := bb != _off_tried and not _centre_free(bb)   # one try per box: a view that cannot hold it is not chased every frame
	if off:
		_off_tried = bb
	if not off and ref_len >= 1e-4 and absf(len - ref_len) <= FRAME_CHANGE * ref_len:
		return
	_fr_ref = bb
	var pose := _frame_pose(bb)
	if pose.is_empty():
		return
	_ease = {"t0": m.target, "d0": float(m.dist), "t1": pose[0], "d1": pose[1], "s": 0.0}


## the free view: the clear view minus the MAKE row above and the side panel at the right, minus the status line at the bottom
func free_rect() -> Rect2:
	var top := _cl.position.y + 4.0 + MAKE_H + 8.0
	for c in [hint, hole_box, split_box, shape_box, colour_box, repeat_box, stick_box]:   # the words and the chip rows under the MAKE row: the part sits below them
		if c != null and (c as Control).visible:                               # (ewalk4: the Through / Hollow inside chips covered the mug's rim)
			top = maxf(top, (c as Control).get_global_rect().end.y + 8.0)
	var x1 := _cl.end.x - PW - 16.0
	return Rect2(_cl.position.x + 12.0, top, x1 - _cl.position.x - 12.0, _cl.end.y - 70.0 - top)


## the ease in progress: one step per frame toward its end pose (smoothstep), then it is cleared
func _ease_step() -> void:
	_ease["s"] = minf(float(_ease["s"]) + get_process_delta_time(), FRAME_EASE)
	var k: float = float(_ease["s"]) / FRAME_EASE
	k = k * k * (3.0 - 2.0 * k)
	m.target = (_ease["t0"] as Vector3).lerp(_ease["t1"] as Vector3, k)
	m.dist = lerpf(float(_ease["d0"]), float(_ease["d1"]), k)
	m._cam()
	if float(_ease["s"]) >= FRAME_EASE:
		_ease = {}


## GRIDFRAME (Nick 2026-10-28, Fusion 360 style): an empty Easy Part opens with its 1 m floor grid centred in the free view and filling most of it.
## Framed again when the free view itself changes (the lens shift follows it), but only while the user has not moved the camera since
## the last automatic framing. The view angle is kept (the 3/4 entry view).
const GRID_FILL := 0.85          # the grid's bigger side fills this share of the free view
var _grid_framed := false
var _grid_fr := Rect2()          # the free view the grid was last framed in
var _grid_cam: Array = []        # the camera [target, dist, yaw, pitch] the last automatic framing left
func _frame_grid() -> void:
	if _ease.size() > 0 or m.cam == null:
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) or not _drag.is_empty() or not _draft.is_empty():
		return   # the user has the mouse (a drag, a sketch, an orbit): the view stays where it is
	if m._view_tw != null and m._view_tw.is_valid():
		return   # the view tween that the card click started still moves the look-at point: framed after it ends
	var fr := free_rect()
	if fr.size.x < 40.0 or fr.size.y < 40.0:
		return
	if _grid_framed:
		if fr.is_equal_approx(_grid_fr) or not _grid_auto():
			return   # framed already, or the user has the view
		if armed != "":
			return   # a tool is armed (Draw, Curvy, Pull ...): the free view changes as its panel opens, and the view must not move under the clicks that follow
	var e := 10 * 50.0 * Part.MM   # the floor grid's half side (scripts: _floor_sync, n = 10 lines of 5 cm)
	var pose := _grid_pose(AABB(Vector3(-e, 0.0, -e), Vector3(2.0 * e, 0.0, 2.0 * e)), GRID_FILL)
	if pose.is_empty():
		return   # no pose yet: try again next frame
	_grid_framed = true
	_grid_fr = fr
	_grid_cam = [pose[0], pose[1], float(m.yaw), float(m.pitch)]
	_ease = {"t0": m.target, "d0": float(m.dist), "t1": pose[0], "d1": pose[1], "s": 0.0}


## true while the camera is still where the last automatic grid framing left it (the user has not orbited, panned or zoomed)
func _grid_auto() -> bool:
	if _grid_cam.is_empty():
		return false
	return m.target.is_equal_approx(_grid_cam[0]) and absf(float(m.dist) - float(_grid_cam[1])) < 1e-4 and absf(float(m.yaw) - float(_grid_cam[2])) < 1e-3 and absf(float(m.pitch) - float(_grid_cam[3])) < 1e-3


## GRIDFRAME, closed loop: the look-at point and distance that put the grid's screen box at the free view's centre and GRID_FILL of it.
## Each step measures the box on screen (the camera's lens shift is not trusted) and moves the look-at point by the pixel error
## (one pixel = 2 d tan(fov/2) / view height world units, the view height is kept). Returns [t, d], or [] when no pose is found.
func _grid_pose(bb: AABB, fill: float) -> Array:
	var fr := free_rect()
	if fr.size.x < 40.0 or fr.size.y < 40.0:
		return []
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var t0: Vector3 = m.target
	var d0 := float(m.dist)
	var t := bb.get_center()
	var d := d0
	var ok_pose := false
	for it in 60:
		var b := Basis.from_euler(Vector3(deg_to_rad(float(m.pitch)), deg_to_rad(float(m.yaw)), 0))
		var r := _box_at(bb, t, d)
		if r.size == Vector2.ZERO:
			d *= 1.5   # a corner behind the lens: back off
			continue
		var wpp := 2.0 * d * tan(deg_to_rad(m.cam.fov * 0.5)) / vs.y
		var need := maxf(r.size.x / fr.size.x, r.size.y / fr.size.y) / fill
		var ex := fr.get_center().x - r.get_center().x
		var ey := fr.get_center().y - r.get_center().y
		if absf(ex) < 1.0 and absf(ey) < 1.0 and absf(need - 1.0) < 0.01:
			ok_pose = true
			break
		t += b.x * (-ex) * wpp + b.y * ey * wpp
		if absf(need - 1.0) >= 0.01:
			d = clampf(d * clampf(need, 0.5, 2.0), 0.02, 40.0)
	m.target = t0
	m.dist = d0
	m._cam()
	if not ok_pose:
		return []
	return [t, d]


## true when the box's middle projects on the screen (and is in front of the lens): the solid can be seen and clicked
func _centre_free(bb: AABB) -> bool:
	var c := bb.get_center()
	if m.cam.is_position_behind(c):
		return false
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var p: Vector2 = m.cam.unproject_position(c)
	return p.x >= 0.0 and p.y >= 0.0 and p.x <= vs.x and p.y <= vs.y


## The look-at point is the box's middle, moved so the box sits in the free view's middle (as Easy's frame() moves it); the distance
## is found by a few steps: the box's size on screen goes as 1 / distance, so each step scales the distance by the size ratio.
## the look-at point and distance that put the box (its eight corners) at FRAME_FILL of the free view; the view angle is kept.
## (fill: the share of the free view the box takes; FRAME_FILL unless an empty part's grid tile asks for more)
func _frame_pose(bb: AABB, fill := FRAME_FILL) -> Array:
	var fr := free_rect()
	if fr.size.x < 40.0 or fr.size.y < 40.0:
		return []
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var t0: Vector3 = m.target
	var d0 := float(m.dist)
	var d := d0
	var t := bb.get_center()
	for it in 40:
		var b := Basis.from_euler(Vector3(deg_to_rad(float(m.pitch)), deg_to_rad(float(m.yaw)), 0))
		var span := 2.0 * d * tan(deg_to_rad(m.cam.fov * 0.5)) * vs.x / vs.y
		var tt := bb.get_center() + b.x * (span * (vs.x * 0.5 - fr.get_center().x) / vs.x) + b.y * (span * (fr.get_center().y - vs.y * 0.5) / vs.y)
		var r := _box_at(bb, tt, d)
		if r.size == Vector2.ZERO:
			d *= 1.5   # a corner behind the lens: back off
			continue
		t = tt
		var need := maxf(r.size.x / fr.size.x, r.size.y / fr.size.y) / fill
		if absf(need - 1.0) < 0.01:
			break
		d = clampf(d * clampf(need, 0.5, 2.0), 0.02, 40.0)
	m.target = t0
	m.dist = d0
	m._cam()
	return [t, d]


## the box's screen rectangle seen from look-at point t at distance d (the camera is put back by the caller).
## Zero size when a corner is behind the lens.
func _box_at(bb: AABB, t: Vector3, d: float) -> Rect2:
	m.target = t
	m.dist = d
	m._cam()
	var r := Rect2()
	var first := true
	for i in 8:
		var q := bb.get_endpoint(i)
		if m.cam.is_position_behind(q):
			return Rect2()
		var sp: Vector2 = m.cam.unproject_position(q)
		r = Rect2(sp, Vector2.ZERO) if first else r.expand(sp)
		first = false
	return r


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
	_hole_sync()
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
	elif not res.is_empty() and int(res.get("bodies", 0)) > 0:
		text = "Press a button above to change it, or pick a shape on the right"   # a part of the user's own (no template): not "draw a shape"
	else:
		text = "Pick a shape on the right, or press Draw shape"
	hint_l.text = text
	var errs: Dictionary = res.get("errors", {}) if not res.is_empty() else {}
	var bodies := int(res.get("bodies", 0)) if not res.is_empty() else 0
	if off:
		status_l.text = "Greyed out: this tool is not in this copy of Kine"
	elif rec.is_empty():
		status_l.text = "Nothing here yet"
	elif not errs.is_empty():
		status_l.text = "One step could not follow the new sizes. Undo takes it back"
	elif bodies == 1 and _lumps(res) > 1:
		status_l.text = "%d pieces that do not touch: Stick together joins them" % _lumps(res)   # a join of copies with a gap is one body of apart pieces
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
	_cl = cl
	var w := cl.size.x - 16.0
	var n := float(MAKES.size())   # twelve buttons in one row: each takes its share (the row is as wide as the clear view allows)
	var bw := minf(176.0, (w - (n - 1.0) * 8.0) / n)
	make_box.reset_size()
	for b in make_btns.values():
		(b as Control).custom_minimum_size.x = bw
	make_box.size = Vector2(bw * n + (n - 1.0) * 8.0, MAKE_H)
	make_box.position = Vector2(cl.position.x + 8.0, cl.position.y + 4.0)
	var top := make_box.position.y + maxf(MAKE_H, make_box.size.y) + 8.0
	var fnt: Font = hint_l.get_theme_font("font")   # the words' width on one line (a label that wraps reports no width)
	var one_line := fnt.get_string_size(hint_l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, hint_l.get_theme_font_size("font_size")).x + 40.0
	hint.size.x = minf(one_line, cl.size.x - PW - 40.0)
	hint.size.y = hint.get_combined_minimum_size().y   # the height of the words wrapped to that width
	hint.position = Vector2(cl.position.x + 12.0, top)
	shape_box.reset_size()
	shape_box.position = Vector2(cl.position.x + 12.0, top + hint.size.y + 6.0)
	hole_box.reset_size()
	hole_box.position = shape_box.position
	split_box.reset_size()
	split_box.position = shape_box.position
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


## the body whose projected triangles are nearest the screen point, within PICK_PX; -1 when none is that close
func _near_body(p: Vector2, faces: Array) -> int:
	var best := -1
	var best_d := PICK_PX
	for bi in faces.size():
		var tris: PackedVector3Array = faces[bi]
		for k in range(0, tris.size() - 2, 3):
			var q := _proj3(tris, k)
			if q.is_empty():
				continue
			var d := _tri_px(p, q)
			if d < best_d:
				best_d = d
				best = bi
	return best


## the crease edges of a triangle soup: an edge whose two triangles turn more than ~8 deg (or that has one triangle) is drawn;
## the diagonals inside a flat face are not. Points are matched to 0.01 mm
func _creases(tris: PackedVector3Array) -> PackedVector3Array:
	var seen := {}   # edge key -> [a, b, normal of the first triangle, still to draw]
	var out := PackedVector3Array()
	for k in range(0, tris.size() - 2, 3):
		var n := (tris[k + 1] - tris[k]).cross(tris[k + 2] - tris[k]).normalized()
		for j in 3:
			var a: Vector3 = tris[k + j]
			var b: Vector3 = tris[k + (j + 1) % 3]
			var ka := str((a * 1e5).round())
			var kb := str((b * 1e5).round())
			var key := ka + "|" + kb if ka < kb else kb + "|" + ka
			if seen.has(key):
				seen[key][3] = (seen[key][2] as Vector3).dot(n) < 0.99
			else:
				seen[key] = [a, b, n, true]
	for e in seen.values():
		if e[3]:
			out.append(e[0])
			out.append(e[1])
	return out


## the three corners of triangle k on screen (empty when one is behind the camera)
func _proj3(tris: PackedVector3Array, k: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for j in 3:
		var w: Vector3 = tris[k + j]
		if m.cam.is_position_behind(w):
			return PackedVector2Array()
		out.append(m.cam.unproject_position(w))
	return out


## the screen distance from p to a triangle (0 inside it)
func _tri_px(p: Vector2, q: PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(p, q):
		return 0.0
	var d := INF
	for j in 3:
		d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, q[j], q[(j + 1) % 3])))
	return d


func _draw_dots() -> void:
	var font := ThemeDB.fallback_font
	for bi in stick_picks:   # the picked piece glows: its faces tinted, its edges amber
		var tris: PackedVector3Array = stick_tris.get(bi, PackedVector3Array())
		for k in range(0, tris.size() - 2, 3):
			var q := _proj3(tris, k)
			if q.size() < 3 or absf((q[1] - q[0]).cross(q[2] - q[0])) < 0.5:
				continue   # a face seen edge-on is a line on screen: no polygon to fill (the triangulation refuses it)
			dots.draw_colored_polygon(q, Color(AMBER, 0.28))
		var ed: PackedVector3Array = stick_edges.get(bi, PackedVector3Array())
		for k in range(0, ed.size() - 1, 2):
			if m.cam.is_position_behind(ed[k]) or m.cam.is_position_behind(ed[k + 1]):
				continue
			dots.draw_line(m.cam.unproject_position(ed[k]), m.cam.unproject_position(ed[k + 1]), AMBER, 2.0, true)
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


## THE FLOOR GRID: the Part grid laid on the top plane (y = 0): a line every 5 cm (every 25 cm brighter) across 1 m, the axes tinted.
## Built once (an ImmediateMesh of lines beside the camera), shown only while Easy Part is on
var floor_mi: MeshInstance3D     # THE FLOOR GRID as 3D lines in the world: the part hides it, the buttons sit above it (a 2D overlay drew over both)


func _floor_sync(on: bool) -> void:
	if floor_mi == null:
		if not on or m.cam == null or m.cam.get_parent() == null:
			return
		var n := 10
		var e := n * 50.0 * Part.MM
		var im := ImmediateMesh.new()
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		for i in range(-n, n + 1):
			var v := float(i) * 50.0 * Part.MM
			var col := Color(0.4, 0.48, 0.6, 0.3 if i % 5 == 0 else 0.16)
			if i == 0:
				col = Color(0.85, 0.35, 0.35, 0.5)
			for ln in [[Vector3(-e, 0, v), Vector3(e, 0, v)], [Vector3(v, 0, -e), Vector3(v, 0, e)]]:
				for q in ln:
					im.surface_set_color(col)
					im.surface_add_vertex(q)
		im.surface_end()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		floor_mi = MeshInstance3D.new()
		floor_mi.name = "EasyFloorGrid"
		floor_mi.mesh = im
		floor_mi.material_override = mat
		floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.cam.get_parent().add_child(floor_mi)
	floor_mi.visible = on


## UPRIGHT THROUGH THE MIDDLE (side-on): the camera looks along a horizontal line (|pitch| < SIDE_ON), so a press on empty space draws on
## the upright plane through the part's middle that faces the camera: Front (+Z) or Right (+X), whichever the yaw is nearer to.
const SIDE_ON := 15.0       # deg: the camera within this of level looks side-on (the ViewCube's FRONT / RIGHT); Easy opens at ENTRY_PITCH
const ENTRY_PITCH := -30.0


func _side_on() -> bool:
	return absf(float(m.pitch)) < SIDE_ON


## {"pl": the plane (offset to the part box's middle), "base": "front"|"right", "mm": the offset along its normal, "through": true}
func _upright() -> Dictionary:
	var yr := deg_to_rad(float(m.yaw))
	var base := "right" if absf(sin(yr)) > absf(cos(yr)) else "front"
	var bb: AABB = pu.res.get("aabb", AABB()) if pu != null else AABB()
	var c := bb.position + bb.size * 0.5   # metres
	var mm := snappedf((c.x if base == "right" else c.z) / Part.MM, 0.01)
	var pl := Part.plane(base)
	pl["o"] = (pl["o"] as Vector3) + (pl["n"] as Vector3) * mm * Part.MM
	return {"pl": pl, "base": base, "mm": mm, "through": true}


var upright_mi: MeshInstance3D   # THE UPRIGHT PLANE: a faint grid through the part, 3D lines in the world (shown only while drawing side-on)
var _upright_key := ""


func _upright_sync(on: bool) -> void:
	if not on or m.cam == null or m.cam.get_parent() == null:
		if upright_mi != null:
			upright_mi.visible = false
		return
	var up := _upright()
	var pl: Dictionary = up["pl"]
	var bb: AABB = pu.res.get("aabb", AABB()) if pu != null else AABB()
	var c2 := Part.to_plane(pl, bb.position + bb.size * 0.5)
	var half := maxf(60.0, maxf(bb.size.x, maxf(bb.size.y, bb.size.z)) / Part.MM * 0.6 + 20.0)
	var key := "%s %s %s" % [up["base"], str(up["mm"]), str(snappedf(half, 1.0))]
	if upright_mi == null:
		upright_mi = MeshInstance3D.new()
		upright_mi.name = "EasyUprightGrid"
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		upright_mi.material_override = mat
		upright_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.cam.get_parent().add_child(upright_mi)
	upright_mi.visible = true
	if key == _upright_key:
		return
	_upright_key = key
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var col_g := Color(0.55, 0.75, 1.0, 0.14)
	var col_e := Color(0.55, 0.75, 1.0, 0.45)
	var n := int(roundf(half / 10.0))
	for i in range(-n, n + 1):
		var v := float(i) * 10.0
		var col := col_g if i != -n and i != n else col_e
		for ln in [[Vector2(-half, v), Vector2(half, v)], [Vector2(v, -half), Vector2(v, half)]]:
			for q in ln:
				im.surface_set_color(col)
				im.surface_add_vertex(Part.to_world(pl, c2 + (q as Vector2)))
	im.surface_end()
	upright_mi.mesh = im

func _draft_outline() -> PackedVector2Array:
	var a: Vector2 = _draft["a"]
	var b: Vector2 = _draft["b"]
	var pts := PackedVector2Array()
	if String(_draft["shape"]) == "curve":
		for q in _draft["pts"]:
			pts.append(m.cam.unproject_position(_pw(q as Vector2)))
		return pts
	if String(_draft["shape"]) == "box":
		for q in [a, Vector2(b.x, a.y), b, Vector2(a.x, b.y), a]:
			pts.append(m.cam.unproject_position(_pw(q)))
	elif String(_draft["shape"]) == "pointy":
		for q in _pointy_pts(a, b) + [a]:
			pts.append(m.cam.unproject_position(_pw(q)))
	else:
		var r := a.distance_to(b)
		for i in 33:
			var q := a + Vector2.from_angle(TAU * i / 32.0) * r
			pts.append(m.cam.unproject_position(_pw(q)))
	return pts


## POINTY: the drag's corners a and b make an isoceles triangle: the base is a's side of the box (a to (b.x, a.y)), the point is at the middle of the far edge (b's side: (middle x, b.y))
func _pointy_pts(a: Vector2, b: Vector2) -> Array:
	return [a, Vector2(b.x, a.y), Vector2((a.x + b.x) * 0.5, b.y)]


## the world point of a draft coordinate (the draft plane, else the FLOOR: the Part top plane, y = 0)
func _pw(q: Vector2) -> Vector3:
	return Part.to_world(_draft.get("pl", Part.plane("top")), q)


## DRAW ON A FACE: the flat face under a press, or {} (none, a curved face, or not within 5 deg of +-X, +-Y or +-Z).
## {"pl": the plane through the face, "base": "right"|"top"|"front", "mm": distance along the base normal, "out": +1 or -1 (the face normal side)}
func _face_hit(p: Vector2) -> Dictionary:
	var fc := _face_hit_at(p)
	if fc.is_empty() or String(fc.get("base", "")) == "top":
		return fc
	# a press on a solid's top edge or corner (a chair leg's corner, seen from the side) lands on the side face just below the top:
	# a tip-of-the-top press a few px higher takes the TOP face there, so a seat drawn on the leg tops sits on them
	for off in [Vector2(0.0, -6.0), Vector2(-6.0, -6.0), Vector2(6.0, -6.0)]:
		var up := _face_hit_at(p + off)
		if String(up.get("base", "")) == "top":
			return up
	return fc


func _face_hit_at(p: Vector2) -> Dictionary:
	if not Part.available():
		return {}
	var faces: Array = Part.body_faces(_rec(), -1)
	var ro: Vector3 = m.cam.project_ray_origin(p)
	var rd: Vector3 = m.cam.project_ray_normal(p)
	var best_d := INF
	var bi := -1
	var bk := -1
	var bh := Vector3.ZERO
	for b in faces.size():
		var tris: PackedVector3Array = faces[b]
		for k in range(0, tris.size() - 2, 3):
			var hit: Variant = SkinPick.ray_tri_mm(ro, rd, tris[k], tris[k + 1], tris[k + 2])
			if hit != null and ro.distance_to(hit as Vector3) < best_d:
				best_d = ro.distance_to(hit as Vector3)
				bi = b
				bk = k
				bh = hit
	if bi < 0:
		return {}
	var tris: PackedVector3Array = faces[bi]
	var a: Vector3 = tris[bk]
	var c1: Vector3 = tris[bk + 1]
	var c2: Vector3 = tris[bk + 2]
	var nrm := (c1 - a).cross(c2 - a)
	if nrm.length() < 1e-12:
		return {}
	nrm = nrm.normalized()
	if nrm.dot(rd) > 0.0:
		nrm = -nrm   # the side the camera sees: the outward normal of a front face
	var ax := -1
	for i in 3:
		if absf(nrm.dot(FACE_N[i])) >= cos(deg_to_rad(5.0)):
			ax = i
	if ax < 0:
		return {}
	# flat: a triangle across an edge that bends by 1 to 40 deg means a curved face (a cylinder, a sphere): no face
	for j in range(0, tris.size() - 2, 3):
		if j == bk:
			continue
		var shared := 0
		for v in [tris[j], tris[j + 1], tris[j + 2]]:
			if v.is_equal_approx(a) or v.is_equal_approx(c1) or v.is_equal_approx(c2):
				shared += 1
		if shared != 2:
			continue
		var nj := (tris[j + 1] - tris[j]).cross(tris[j + 2] - tris[j])
		if nj.length() < 1e-12:
			continue
		var ang := nrm.angle_to(nj.normalized())
		if ang > deg_to_rad(1.0) and ang < deg_to_rad(40.0):
			return {}
	var mm := snappedf(bh.dot(FACE_N[ax]) / Part.MM, 0.01)
	var out := 1 if nrm.dot(FACE_N[ax]) > 0.0 else -1
	var pl := Part.plane(FACE_BASE[ax])
	pl["o"] = (pl["o"] as Vector3) + (pl["n"] as Vector3) * mm * Part.MM
	return {"pl": pl, "base": FACE_BASE[ax], "mm": mm, "out": out}


const FACE_BASE := ["right", "top", "front"]   # the Part plane each axis is drawn on (+X, +Y, +Z)
const FACE_N := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]


func _ground(p: Vector2, pl: Dictionary = {}, snap := true) -> Variant:
	var o: Vector3 = m.cam.project_ray_origin(p)
	var d: Vector3 = m.cam.project_ray_normal(p)
	if pl.is_empty():   # an empty-space press draws on the FLOOR (the Part top plane, y = 0; monkey-brain direction)
		pl = Part.plane("top")
	var pn: Vector3 = pl["n"]   # the ray hit on that plane, in its own mm (a face's plane, or the floor)
	var den := d.dot(pn)
	if absf(den) < 1e-5:
		return null
	var t := ((pl["o"] as Vector3) - o).dot(pn) / den
	if t < 0.0:
		return null
	var q := Part.to_plane(pl, o + d * t)
	if not snap:
		return Vector2(q.x, q.y)
	return Vector2(snappedf(q.x, 5.0), snappedf(q.y, 5.0))


## EKEYS: a key press on the Easy screen. Escape cancels a half-drawn shape or a drag in hand (nothing is written, no step is left);
## Delete takes out the newest piece as one undo step. Ctrl+Z / Ctrl+Y are main's (_undo / _redo) and need nothing here
func _key(k: InputEventKey) -> void:
	if not k.pressed or k.echo or not active() or not Part.available():
		return
	var fo := get_viewport().gui_get_focus_owner()
	if fo is LineEdit or fo is SpinBox:
		return   # a typed number keeps its keys
	if k.keycode == KEY_ESCAPE:
		if not _draft.is_empty():
			_draft = {}
			_bar_press = null
			_press_btn = null
			dots.queue_redraw()
			_say("Drawing cancelled. Draw it again")
			get_viewport().set_input_as_handled()
		elif not _drag.is_empty():
			_cancel_drag()
			get_viewport().set_input_as_handled()
	elif k.keycode == KEY_DELETE and not k.ctrl_pressed and not k.alt_pressed:
		_delete_newest()
		get_viewport().set_input_as_handled()


## a drag in hand let go with Escape: the amber dot goes back where it was; the drag moved nothing in the record (it writes on the release), so its step goes
func _cancel_drag() -> void:
	_drag = {}
	_pending = {}
	_dirty = false
	_end()
	_rows_sync()
	_say("Drag cancelled")


## Delete: the newest piece goes (its sketch and a face plane made for it, or its pull, spin, round, hole ...), one undo step. A template part keeps its own pieces (its sliders make them): it says so
func _delete_newest() -> void:
	if not _drag.is_empty() or not _draft.is_empty():
		return
	if _tpl() != "":
		_say("A template's pieces come from its sliders: move a slider, or Undo takes a change back")
		return
	var fs: Array = _rec().get("features", [])
	if fs.is_empty():
		_say("Nothing to delete yet")
		return
	_flush_if_dirty()
	var newest: Dictionary = fs.back()
	_begin("Delete " + String(newest.get("name", "piece")))
	var rec := _rec()
	var gone: Dictionary = (rec["features"] as Array).pop_back()
	var fs2: Array = rec["features"]
	var back_f: Dictionary = fs2.back() if not fs2.is_empty() else {}
	if String(gone.get("t", "")) != "plane" and not back_f.is_empty() and String(back_f.get("t", "")) == "plane":
		fs2.pop_back()   # the face plane made for that sketch goes with it
	armed = ""
	tweak = {}
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_end()
	_say("Took out the newest piece. Undo puts it back")


## a press on the top bar's BUTTONS never reaches input() (the button takes it in the GUI pass first): this sees it before the GUI,
## notes it, and lets the button have it. A drag that then leaves the bar starts the sketch (input() below, from the noted press)
func _input(ev: InputEvent) -> void:
	if ev is InputEventKey:
		_key(ev as InputEventKey)   # EKEYS: Escape and Delete (Ctrl+Z / Ctrl+Y are main's undo and redo)
		return
	# a sketch in progress follows the pointer and ends on the release even over a control (a chip row, the bar): the controls
	# take those events before the unhandled pass, so a roof's apex under the chips would stop the drag
	if ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if _bar_press != null and mm.button_mask & MOUSE_BUTTON_MASK_LEFT != 0 and _draft.is_empty() and _drag.is_empty() and mm.position.distance_to(_bar_press) >= 6.0:
			var bp: Vector2 = _bar_press
			_bar_press = null
			_press_btn = null
			if _start_draft(bp):   # the drag started on the bar: a sketch from where the press was (the button never got it)
				_draft_move(mm.position)
		elif not _draft.is_empty() and _drag.is_empty() and mm.button_mask & MOUSE_BUTTON_MASK_LEFT != 0:
			_draft_move(mm.position)
		return
	if not (ev is InputEventMouseButton) or (ev as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	var mb := ev as InputEventMouseButton
	if not mb.pressed:
		if not _draft.is_empty() and _drag.is_empty():
			_bar_press = null
			_draft_end()
			get_viewport().set_input_as_handled()
		elif _bar_press != null:
			# a press on a bar button that did not turn into a sketch: the click the button would have had
			var btn: BaseButton = _press_btn
			_bar_press = null
			_press_btn = null
			if btn != null and is_instance_valid(btn) and btn.is_visible_in_tree() and not btn.disabled:
				btn.pressed.emit()
			get_viewport().set_input_as_handled()
		return
	var p := mb.position
	if active() and Part.available() and (armed == "draw" or armed == "curve") and _drag.is_empty() and _draft.is_empty() and _on_bar(p):
		# a press on the top bar (a far leg under the Mirror button): the sketch takes it if the drag leaves it on the grid, a click is the button's
		_bar_press = p
		_press_btn = _bar_button_at(p)
		get_viewport().set_input_as_handled()


## the visible button under p on the top bar or its MAKE row, or null
func _bar_button_at(p: Vector2) -> BaseButton:
	for root_c in [bar, make_box]:
		if root_c == null:
			continue
		for c in (root_c as Node).find_children("*", "BaseButton", true, false):
			var b := c as BaseButton
			if b.is_visible_in_tree() and b.get_global_rect().has_point(p):
				return b
	return null


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
				var faces: Array = Part.body_faces(_rec(), -1)
				var hit: Dictionary = pu._ray_hit(p, faces)   # the body under the pointer (Expert's combine picks the same way)
				var bi := int(hit["body"]) if not hit.is_empty() else _near_body(p, faces)   # a miss within 12 px of a piece still picks it (thin plates)
				if bi < 0:
					return false   # nothing solid there: the camera keeps the click
				_stick_pick(bi, faces)
				return true
			if (armed == "draw" or armed == "curve") and not _over_ui(p):
				return _start_draft(p)
			return false
		if not _drag.is_empty():
			_drag_to(p, true)
			_drag = {}
			_end()
			return true
		_bar_press = null
		if not _draft.is_empty():
			_draft_end()
			return true
		return false
	if ev is InputEventMouseMotion:
		var p := (ev as InputEventMouseMotion).position
		if not _drag.is_empty():
			_drag_to(p, false)
			return true
		if not _draft.is_empty():
			_draft_move(p)
			return true
		var h := ""
		for d in _dot_list():
			if (d["scr"] as Vector2).distance_to(p) <= 16.0:
				h = String(d["k"])
		if h != _hover:
			_hover = h
			dots.queue_redraw()
	return false


## a press on the top bar only (not the side panel or the chip rows)
func _on_bar(p: Vector2) -> bool:
	for c in [bar, make_box]:   # the bar and its MAKE row (the buttons sit in the row)
		if c != null and (c as Control).visible and (c as Control).get_global_rect().has_point(p):
			return true
	return false


## the sketch in progress follows the pointer p (the draft's second corner, or the curve's next point)
func _draft_move(p: Vector2) -> void:
	_draft_px1 = p
	var g: Variant = _ground(p, _draft.get("pl", {}))
	if g != null:
		_draft["b"] = g
		if String(_draft["shape"]) == "curve" and (g as Vector2).distance_to((_draft["pts"] as Array).back()) >= 5.0:
			(_draft["pts"] as Array).append(g)
	dots.queue_redraw()


func _draft_end() -> void:
	if String(_draft["shape"]) == "curve":
		_finish_curve()
	else:
		_finish_draw()


## a press on the upright plane through the middle at or above the body's top (within 1 cm of it), between the body's two side walls
func _above_body(p: Vector2) -> bool:
	var bb: AABB = pu.res.get("aabb", AABB()) if pu != null else AABB()
	if bb.size == Vector3.ZERO:
		return false
	var up := _upright()
	var g: Variant = _ground(p, up["pl"])
	if g == null:
		return false
	var q: Vector2 = g
	var xr := Vector2(bb.position.x, bb.end.x) / Part.MM if String(up["base"]) == "front" else Vector2(-bb.end.z, -bb.position.z) / Part.MM   # the right plane's 2D x runs along -Z
	return q.y >= bb.end.y / Part.MM - 10.0 and q.x >= xr.x - 1.0 and q.x <= xr.y + 1.0


## a draw / curve press on the grid at p: a sketch on the face under it, the upright plane, or the floor. true = taken
func _start_draft(p: Vector2) -> bool:
	_draft_px0 = p
	_draft_px1 = p
	# A POINTY UPRIGHT ABOVE A BOX TOP is a roof: the side-on upright plane through the middle (not the box's front face), so it pulls both ways to the box depth
	if shape == "pointy" and armed != "curve" and _side_on() and _above_body(p):
		var ur := _upright()
		var gr: Variant = _ground(p, ur["pl"])
		if gr != null:
			_draft = {"a": gr, "b": gr, "shape": "pointy", "pts": [gr], "pl": ur["pl"], "face": ur}
			_say("Drawing a roof on the box top, through the middle")
			return true
	var fc := _face_hit(p)   # DRAW ON A FACE: a press on a flat face of a solid puts the sketch on that face
	if not fc.is_empty():
		var fg: Variant = _ground(p, fc["pl"])
		if fg != null:
			_draft = {"a": fg, "b": fg, "shape": "curve" if armed == "curve" else shape, "pts": [fg], "pl": fc["pl"], "face": fc}
			_say("Drawing on that face")
			return true
	if _side_on():
		var up := _upright()
		var gu: Variant = _ground(p, up["pl"])
		if gu != null:
			_draft = {"a": gu, "b": gu, "shape": "curve" if armed == "curve" else shape, "pts": [gu], "pl": up["pl"], "face": up}
			_say("Drawing upright, through the middle")
			return true
	var g: Variant = _ground(p)
	if g != null:
		_draft = {"a": g, "b": g, "shape": "curve" if armed == "curve" else shape, "pts": [g], "pl": Part.plane("top")}
		return true
	return false


func _over_ui(p: Vector2) -> bool:
	# hint and status are WORDS only (a _pill: mouse_filter IGNORE, one Label, no button): a press under them is the grid's, not eaten
	for c in [bar, make_box, panel, shape_box, colour_box, repeat_box, stick_box]:
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


## the least side a drawn shape may have (mm): a long thin blade draws when BOTH sides are at least this
const MIN_SIDE := 2.0


## the two corners of a box or pointy draft. Each side is the 5 mm grid's, unless the grid folds it under MIN_SIDE: then the raw pointer side is kept (a 5 mm blade is not refused for snapping to one grid line). {} = a side under MIN_SIDE, refused (the words say how wide)
func _sides(a: Vector2, b: Vector2, pl: Dictionary) -> Dictionary:
	var ra: Variant = _ground(_draft_px0, pl, false)
	var rb: Variant = _ground(_draft_px1, pl, false)
	var raw_a: Vector2 = ra if ra != null else a
	var raw_b: Vector2 = rb if rb != null else b
	var out := b
	for ax in 2:
		if absf(b[ax] - a[ax]) < MIN_SIDE:
			var rs: float = raw_b[ax] - raw_a[ax]
			if absf(rs) < MIN_SIDE:
				return {"thin": absf(rs)}
			out[ax] = a[ax] + rs
	return {"b": out}


## a length in mm for the words: 0 -> "0", 2.5 -> "2.5"
static func _mm_words(x: float) -> String:
	return ("%.1f" % x).trim_suffix(".0")


func _finish_draw() -> void:
	var a: Vector2 = _draft["a"]
	var b: Vector2 = _draft["b"]
	var sh := String(_draft["shape"])
	var fc: Dictionary = _draft.get("face", {})
	var pl: Dictionary = _draft.get("pl", Part.plane("top"))
	_draft = {}
	var ent := {}
	var ents: Array = []
	if sh == "box" or sh == "pointy":
		var sd := _sides(a, b, pl)
		if sd.has("thin"):
			_say("Drag a bit wider: both sides must be at least 2 mm (now %s mm)" % _mm_words(float(sd["thin"])))
			return
		b = sd["b"]
		if sh == "box":
			ent = {"k": "rect", "a": Part.arr2(a), "b": Part.arr2(b)}
		else:   # POINTY: three lines, the closed outline of the triangle (Expert's line tool records the same)
			var tp := _pointy_pts(a, b)
			ents = [{"k": "line", "a": Part.arr2(tp[0]), "b": Part.arr2(tp[1])}, {"k": "line", "a": Part.arr2(tp[1]), "b": Part.arr2(tp[2])}, {"k": "line", "a": Part.arr2(tp[2]), "b": Part.arr2(tp[0])}]
	else:
		var r := a.distance_to(b)
		if r < 5.0:
			_say("Drag a bit further from the centre: a circle needs a radius of at least 5 mm (now %s mm)" % _mm_words(r))
			return
		ent = {"k": "circle", "c": Part.arr2(a), "r": snappedf(r, 0.5)}
	_begin("Draw shape")
	var rec := pu._ensure()
	rec["features"].append(Part.new_feature(rec, "sketch", {"plane": _face_plane(rec, fc), "ents": ents if sh == "pointy" else [ent], "dims": []}))
	_end()
	armed = ""
	tweak = {}
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_say("Shape drawn. Now press Pull it up or Spin it round")


## DRAW ON A FACE: the sketch's plane id. A face press adds ONE Part "plane" feature (from the base plane, mm = the face distance, out = the face side) to rec; no face = "top" (the floor)
func _face_plane(rec: Dictionary, fc: Dictionary) -> String:
	if fc.is_empty():
		return "top"
	if bool(fc.get("through", false)):   # UPRIGHT THROUGH THE MIDDLE: a plane with no "out" (the pull goes both ways)
		var tf := Part.new_feature(rec, "plane", {"from": String(fc["base"]), "mm": float(fc["mm"]), "through": true})
		rec["features"].append(tf)
		return String(tf["id"])
	var pf := Part.new_feature(rec, "plane", {"from": String(fc["base"]), "mm": float(fc["mm"]), "out": int(fc["out"])})
	rec["features"].append(pf)
	return String(pf["id"])


## the pieces of the replay's mesh that do not touch (vertices welded at 0.01 mm, then joined by triangles), counted once per replay mesh
var _lump_mesh: Object = null   # the mesh it was counted on (the replay result dictionary is reused; each replay makes a new mesh)
var _lump_n := 1


func _lumps(r: Dictionary) -> int:
	var mesh: ArrayMesh = r.get("mesh")
	if is_same(mesh, _lump_mesh):
		return _lump_n
	_lump_mesh = mesh
	_lump_n = 1
	if mesh == null or mesh.get_surface_count() == 0:
		return _lump_n
	var weld := {}
	var parent := PackedInt32Array()
	var find := func(i: int) -> int:
		while parent[i] != i:
			parent[i] = parent[parent[i]]
			i = parent[i]
		return i
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var ids := PackedInt32Array()
		for v in vs:
			var key := Vector3i(roundi(v.x * 1e5), roundi(v.y * 1e5), roundi(v.z * 1e5))
			if not weld.has(key):
				weld[key] = parent.size()
				parent.append(parent.size())
			ids.append(int(weld[key]))
		var tri := idx.size() if idx.size() > 0 else vs.size()
		for t in range(0, tri - 2, 3):
			var a: int = ids[idx[t] if idx.size() > 0 else t]
			for k in [1, 2]:
				var b: int = ids[idx[t + k] if idx.size() > 0 else t + k]
				var ra: int = find.call(a)
				var rb: int = find.call(b)
				if ra != rb:
					parent[ra] = rb
	var roots := {}
	for i in parent.size():
		roots[find.call(i)] = true
	_lump_n = maxi(roots.size(), 1)
	return _lump_n
