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
const CHIP_TEXT := {"sword": "Blade"}   # template chips shown before anything is chosen (plain words)
const ROUND_BUDGET_US := 300000   # EROUND: the Round press stops trying edges after this (usec) and keeps the best found
const MAKE_H := 76.0
const REP_WORDS := {"count": ["Fewer", "More"], "gap": ["Closer", "Further apart"]}   # the Repeat it sliders' ends
const STICK_OPS := [["join", "Join", "Make the two pieces one solid"], ["cut", "Cut away", "Cut the second piece out of the first"], ["intersect", "Keep the overlap", "Keep only the part where the two pieces overlap"]]
const SCREW_DS := [3, 4, 5, 6]         # NSCREW2: the Parts category's screw sizes (M3..M6, columns of the grid)
const SCREW_LENS := [10, 16, 20, 30]   # NSCREW2: the screw lengths in mm (rows of the grid)
const LIB_CATS := ["Screws", "Nuts", "Washers", "Gears", "Hinges", "Bearings", "Springs", "Handles", "Wheels", "Brackets"]   # NLIBPAGE: the Parts library page, in this order
const LIB_READY := ["Screws", "Gears"]   # NLIBPAGE: the categories with parts today; the others say coming soon
const COLOUR_PRESETS := ["Glass", "Metal"]   # the two material chips after the five colour chips
const WOOD_COLOUR := Color("#9a6b3f")   # the Wood chip (after Glass and Metal): a wood brown, red > green > blue
const TILT_DEG := 20.0           # Tilt it: the lean of the newest solid (degrees, sideways about its middle)
const HOLLOW_MM := 3.0           # Hollow inside: the wall the shell starts with (the Wall slider moves it: 1 to 10 mm)
const LID_MM := 5.0             # Hollow with a lid (nlid): the top slice that comes off as the lid (a solid plate, the box's footprint)
const LIP_RIDGE_MM := 0.5            # Snap-fit lip (nsnaplip): the ridge sticks out of the lip by this much, and the box wall has a groove this deep
const LID_LIP_MM := 3.0         # the lid's lip: how far it goes down inside the box (1 mm wide ring, 0.2 mm gap to the wall)
const THROTTLE_MS := 100
const CLIP_MM := 6.0             # FBOWL2: a spun curve that dips past the middle line by less than this (a spline overshoot) is clipped onto it
const NARROW_W := 1200.0         # FMOBILE: a window narrower than this (1024 x 600) shrinks the bar's buttons and the title
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
const ROUND_FILTERS := [["all", "All edges", "part_filter_all", "Round every edge of the solid"], ["outside", "Only the outside", "part_filter_outside", "Round only the edges on the outside, not the inside of a hole or a cup"], ["top", "Only the top", "part_filter_top", "Round only the top edges of the solid"]]   # NROUNDFILTER
const BAD_WORDS := ["ctrl", "shift", "alt+", "esc", "enter", "tab ", "delete", "backspace", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "spacebar", "return key"]

var pu: PartUI
var m: Node
var bar: PanelContainer
var title_l: Label
var name_edit: LineEdit   # FNAMECHANGE: the name box that a click on the title opens (hidden otherwise)
var _renaming := false
var undo_btn: Button
var redo_btn: Button
var dup_btn: Button            # FDUP: the top bar's Duplicate (a second copy of the whole part beside it)
var fix_btn: Button            # NFIXIT: the top bar's Fix it (one press = one fix: a failed step, a wall with no thickness, a loose piece)
var use_scene_btn: Button
var size_l: Label              # FMEASURE: "18 x 6 x 2 cm" (wide x deep x high) under the part, plain words, while a solid is there
var whole_l: Label             # "Whole sword: N cm": the shape's biggest size, under the sliders (the blade slider is not the whole length)
var easy_btn: Button
var expert_btn: Button
var bar_home: Button = null   # the bar's Home button (narrowed at 1024 wide, see layout)
var bar_row: HBoxContainer   # the bar's row: Part's "What to build" moves in here while Easy Part is on (part_ui._place_reopen)
var make_box: HBoxContainer
var make_btns := {}
var hint: PanelContainer
var hint_l: Label
var shape_box: PanelContainer
var shape_btns := {}
var repeat_box: PanelContainer   # Repeat it: Row / Ring and the How many and Gap sliders (for the last Repeat it step, rep_id)
var rep_btns := {}
var tilt_box: PanelContainer     # Tilt it: one chip under the newest solid (a Spin or a Pull), leans it 20 degrees once
var tilt_btn: Button
var parts_btn: Button            # NSCREW2: the Parts category chip (opens the screw grid under the template chips)
var screw_box: PanelContainer    # NSCREW2: the screw grid: sixteen size chips, shown while Parts is open or a screw is the part
var screw_btns := {}             # NSCREW2: "d_L" -> the size chip (M<d> x <L>)
var screw_words: Label           # the grid's one-line instruction: hidden while the library page is open (the page and the status line say it)
var nw_btn: Button               # NNUTWASHER: "Add its nut and washer" (in the screw grid): the screw on the floor takes its nut and washer, one click
var parts_open := false          # NSCREW2: the Parts category is open (the grid shows even with no screw on the floor)
var lib_box: PanelContainer      # NLIBPAGE: the Parts library page: ten category chips, under the template chips while Parts is open
var lib_btns := {}               # NLIBPAGE: category -> its chip
var lib_soon: Label              # NLIBPAGE: "Coming soon" line for an empty category (names the next step)
var lib_cat := ""                # NLIBPAGE: the category open on the page ("" = none); Screws opens when Parts opens
var stick_box: PanelContainer    # Stick together: Join / Cut away / Keep the overlap, shown once two pieces are picked
var stick_btns := {}
var stick_picks: Array = []      # the body indices clicked in the view (the first = the target, the second = the tool)
var stick_tris := {}             # body index -> its triangles, for the glow of a picked piece
var stick_edges := {}            # body index -> its crease edges (pairs of points): the glow's outline, no triangle diagonals
const EDGE_PX := 10.0            # NROUNDDRAG: a press this close (screen px) to a solid's edge takes it in hand
const EDGE_MAX_MM := 10.0        # NROUNDDRAG: the radius a drag can reach (mm)
const PICK_PX := 12.0            # a click this close (screen px) to a piece picks it when the ray hits nothing
var rep_id := ""                 # the last Repeat it step's feature id ("" = none)
var rep_rows := []               # the two slider rows of the Repeat it box (see _make_row)
var hole_box: PanelContainer     # Cut a hole: the Through / Hollow inside chips, under the MAKE row, after a Cut a hole press (see _hole_on)
var hole_btns := {}
var snap_btn: Button            # Snap-fit lip (nsnaplip): an on/off chip under Hollow with a lid (the lid gets a ridge, the box a groove)
var hole_base: Dictionary = {}   # the record before the last Cut a hole press: each chip rebuilds the hole from it ({} = no hole chips)
var hole_id := ""                # the feature id of the last hole step (the hole's sketch, or the hollow's shell): its slider's step
var hole_mode := "through"       # "through" | "hollow": the chip that is on
var split_box: PanelContainer   # ECUT2: Cut in two's keep chips (both halves / the lower half / the upper half), after a Cut in two press (see _split_on)
var split_btns := {}
var round_box: PanelContainer   # NROUNDFILTER: the All edges / Only the outside / Only the top chips, beside Round the edges (see _round_box)
var round_btns := {}
var round_mode := "all"          # the filter the next Round the edges press uses: "all" | "outside" | "top"

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
var export_btn: Button          # FEXPORT: Export on the Easy Part bar (the export dialog, the free part picked)
var back_btn: Button
var use_btn: Button
var status: PanelContainer
var status_l: Label
var dots: Control
var armed := ""                # "draw" while the next drag draws a shape
var shape := "box"
var sides := 6                  # NPOLY2: the Sides slider (3 to 12): a regular prism of this many sides (shape "poly"); Hex is the 6 of it
var msg := ""                  # the sentence of the last press, until the next one
var taper_tw := {}             # FPLANTER: the Taper slider of the last Pull it up (its extrude's id; shown while that pull is the newest step)
var taper_row: Dictionary = {}  # FPLANTER: the Taper slider's row ({} = none); kept out of rows so rows[-1] is still How far
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
var _fr_lk := ""               # EPANELVIEW: the left boxes shown when the camera last framed (see _frame_step)
var _near_saved := -1.0         # the camera's near plane before Easy Part (put back when it is left)
const FRAME_NEAR := 0.004
const GRID_TILE_FILL := 0.95         # the empty part's grid tile fills this share of the free view (a flat square seen at a slant is narrow)
const GRID_TILE := AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 0.0, 1.0))   # the 1 m grid square an empty part stands on (metres)
var _bar_press = null           # a draw press that began on the top bar (Vector2), or null: a drag starts the sketch there, a click is the button's
var _press_btn: BaseButton = null # the button under that press (its click when the press is not a drag)
var _off_tried := AABB()         # the box the D2 off-screen check last framed (see _frame_step)
var _ease := {}                 # the camera ease in progress: {"t0", "d0", "t1", "d1", "s"}
var del_btn: Button              # FDELETE: Remove, on the bar while a piece is picked (the click on a piece; see _pick_at)
var del_on := false              # FDELETE: a piece is picked (its step id in del_id, the features count it was picked at in del_n)
var del_id := ""
var del_n := -1
var del_pt := Vector3.ZERO       # the point clicked on the piece (metres, the same units as the faces)
var del_tris := PackedVector3Array()   # the picked piece's triangles: its glow
var _edge := {}                  # NROUNDDRAG: an edge in hand (a press within EDGE_PX of a solid's edge, dragged outward): {"e", "press", "out", "pxmm", "r"}
var edge_num: Label             # NROUNDDRAG: the radius in mm, beside the cursor while an edge is dragged (hidden otherwise)
var _pick_p := Vector2(-1, -1)   # a left press on the grid with nothing armed: a click (no drag) picks the piece under it on release
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
	bar_home = home_b
	title_l = Label.new()
	title_l.name = "easypart_title"
	title_l.add_theme_font_size_override("font_size", 20)
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_l.mouse_filter = Control.MOUSE_FILTER_STOP   # FNAMECHANGE: a click on the title renames the part
	title_l.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	title_l.tooltip_text = "Click to rename the part"
	title_l.gui_input.connect(_title_gui)
	row.add_child(title_l)
	name_edit = LineEdit.new()
	name_edit.name = "easypart_name"
	name_edit.placeholder_text = "Name the part"
	name_edit.max_length = 40
	name_edit.add_theme_font_size_override("font_size", 20)
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.visible = false
	name_edit.text_submitted.connect(func(_t: String): _rename_close(true))
	name_edit.focus_exited.connect(func(): _rename_close(true))
	name_edit.gui_input.connect(_name_edit_gui)
	row.add_child(name_edit)
	undo_btn = _bar_btn("Undo", "Take back the last change", func(): m._undo())
	redo_btn = _bar_btn("Redo", "Put back what Undo took back", func(): m._redo())
	use_scene_btn = _bar_btn("Save and use in a scene", "Save this part to My parts, then put it into the scene as a prop", _use_scene)   # SAVEWORD: a beginner looks for Save; "Use in a scene" stays a substring
	use_scene_btn.custom_minimum_size.x = 230.0
	dup_btn = _bar_btn("Duplicate", "Make a second copy of the whole part, beside it. Undo takes the copy back", func(): _make("duplicate"))   # FDUP: beside Undo and Redo (the MAKE row stays six-plus-six)
	dup_btn.name = "easypart_duplicate"
	dup_btn.custom_minimum_size.x = 120.0
	fix_btn = _bar_btn("Fix it", "Find what is wrong in this part (a step that will not build, a wall with no thickness, a loose piece) and fix it in one press. Undo takes the fix back", _fix_press)   # NFIXIT
	fix_btn.name = "easypart_fix"
	fix_btn.icon = Icons.sized("fix", 22)
	fix_btn.expand_icon = false
	fix_btn.custom_minimum_size.x = 110.0
	row.add_child(undo_btn)
	row.add_child(redo_btn)
	row.add_child(dup_btn)
	row.add_child(fix_btn)
	row.add_child(use_scene_btn)
	give_btn = _bar_btn("Give to a character", "Give it to a character: they hold this shape in one hand, with its size and weight (PartWeapon)", func(): m.give_part_weapon(_rec()))   # one undo step
	give_btn.name = "easypart_give"
	give_btn.custom_minimum_size = Vector2(170, m.TOP_H - 12)
	row.add_child(give_btn)
	export_btn = _bar_btn("Export", "Save this part as an OBJ or a GLB file: the export dialog, with this part picked", func(): m._export_dialog_open())   # FEXPORT
	export_btn.name = "easypart_export"
	export_btn.custom_minimum_size = Vector2(110, m.TOP_H - 12)
	row.add_child(export_btn)
	del_btn = _bar_btn("Remove", "Take out the picked piece: click a piece first. Undo puts it back", func(): _remove_piece())   # FDELETE
	del_btn.name = "easypart_remove"
	del_btn.custom_minimum_size = Vector2(110, m.TOP_H - 12)
	del_btn.visible = false
	row.add_child(del_btn)
	easy_btn = _bar_btn("Easy", "Sliders and big buttons", _easy_on)
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
	for s in [["box", "Box"], ["round", "Round"], ["pointy", "Pointy"], ["oval", "Oval"], ["hex", "Hex"]]:   # FSPOON: Oval = an ellipse fitted to the drag box (a bowl, a pad); FBOLT: Hex = a regular hexagon in the drag box (bolt head, nut)
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
	sh.add_child(_sides_row())   # NPOLY2: Sides, next to Hex: a regular shape with 3 to 12 sides
	root.add_child(shape_box)
	hole_box = _hole_box()
	root.add_child(hole_box)
	split_box = _split_box()
	root.add_child(split_box)
	round_box = _round_box()   # NROUNDFILTER
	root.add_child(round_box)
	colour_box = _colour_box()
	root.add_child(colour_box)
	repeat_box = _repeat_box()
	root.add_child(repeat_box)
	stick_box = _stick_box()
	root.add_child(stick_box)
	tilt_box = _tilt_box()
	root.add_child(tilt_box)
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
	cr.add_theme_constant_override("h_separation", 3)
	cr.add_theme_constant_override("v_separation", 4)
	v.add_child(cr)
	parts_btn = Button.new()   # NSCREW2: Parts: the screw sizes; after the template chips on the same row
	parts_btn.name = "easypart_chip_parts"
	parts_btn.text = "Parts"
	parts_btn.tooltip_text = "Parts: a library of small parts by kind (screws and gears now, more soon)"
	parts_btn.toggle_mode = true
	parts_btn.focus_mode = Control.FOCUS_NONE
	parts_btn.custom_minimum_size = Vector2(0, 34)
	parts_btn.add_theme_font_size_override("font_size", 15)
	parts_btn.pressed.connect(_parts_press)
	for t in PartTemplates.ORDER:
		var b := Button.new()
		b.name = "easypart_chip_" + t
		b.text = CHIP_TEXT.get(t, String(PartTemplates.T[t]["title"]))   # the chip word on the blank part is plain; the part keeps the template title
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 34)
		b.add_theme_font_size_override("font_size", 13)   # NGEAR: 13 (was 15) so six templates (Gear) stay on one row of the panel
		b.pressed.connect(_chip.bind(t))
		cr.add_child(b)
		chips[t] = b
	lib_box = _lib_box()
	v.add_child(lib_box)
	screw_box = _screw_box()
	v.add_child(screw_box)
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
	foot.add_child(parts_btn)   # NSCREW2: Parts sits in the foot (a button in the template row shifted the layout)
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
	edge_num = Label.new()   # NROUNDDRAG: the number beside the cursor (plain words, Tok colours)
	edge_num.name = "EdgeNum"
	edge_num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge_num.add_theme_font_size_override("font_size", 16)
	edge_num.add_theme_color_override("font_color", Color.WHITE)
	edge_num.add_theme_stylebox_override("normal", _style(Color(0.1, 0.11, 0.14, 0.9), 4, 6))
	edge_num.visible = false
	root.add_child(edge_num)
	size_l = Label.new()
	size_l.name = "easypart_size"
	size_l.add_theme_font_size_override("font_size", 14)
	size_l.add_theme_color_override("font_color", Color(0.92, 0.94, 0.97))
	size_l.add_theme_stylebox_override("normal", _style(Color(0.1, 0.11, 0.14, 0.85), 0, 4))
	size_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_l.visible = false
	root.add_child(size_l)


## CUT A HOLE: Through (the round hole, the default) or Hollow inside (the shell: open at the top, a Wall slider). Two toggle chips like Draw shape's
func _hole_box() -> PanelContainer:
	var box := PanelContainer.new()
	box.name = "easypart_hole"
	box.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.92), 10, 6))
	box.visible = false
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	box.add_child(h)
	for hm in [["through", "Through", "A round hole straight through the middle"], ["hollow", "Hollow inside", "Hollow the solid out, open at the top, with a wall (the Wall slider)"], ["lid", "Hollow with a lid", "Hollow the box out with a 3 mm wall; its top 5 mm comes off as a lid with a lip that sits inside the box"]]:
		var b := _big_btn("easypart_hole_" + String(hm[0]), String(hm[1]), String(hm[2]), _hole_mode.bind(String(hm[0])))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(150, 44)
		h.add_child(b)
		hole_btns[hm[0]] = b
	snap_btn = _big_btn("easypart_hole_snap", "Snap-fit lip", "Add a small ridge on the lid's lip and a matching groove in the box wall, so the lid clicks on", _snap_press)
	snap_btn.toggle_mode = true
	snap_btn.custom_minimum_size = Vector2(150, 44)
	snap_btn.visible = false
	h.add_child(snap_btn)
	return box


## NROUNDFILTER: the three filter chips beside Round the edges: All edges (the default), Only the outside, Only the top. Each chip sets the
## filter for the next Round press (no undo step of its own: the press is the one step). Shown while a solid is there and nothing is armed
func _round_box() -> PanelContainer:
	var box := PanelContainer.new()
	box.name = "easypart_round"
	box.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.92), 10, 6))
	box.visible = false
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	box.add_child(h)
	for rf in ROUND_FILTERS:
		var b := _big_btn("easypart_round_" + String(rf[0]), String(rf[1]), String(rf[3]), _round_filter.bind(String(rf[0])))
		b.toggle_mode = true
		b.icon = Icons.sized(String(rf[2]), 22)
		b.expand_icon = false
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(176, 44)
		h.add_child(b)
		round_btns[rf[0]] = b
	return box


func _round_shown() -> bool:
	return armed == "" and int(pu.res.get("bodies", 0)) > 0 and not _hole_on() and not _split_on()


func _round_sync() -> void:
	for k in round_btns:
		(round_btns[k] as Button).set_pressed_no_signal(k == round_mode)
		m._grey(round_btns[k], Part.why_not() if not Part.available() else "")


## a filter chip: the next Round the edges press rounds this kind of edge. Changes no step (nothing is made until Round the edges)
func _round_filter(key: String) -> void:
	round_mode = key
	_round_sync()
	match key:
		"outside":
			_say("Round the edges will now round only the outside edges. Press Round the edges")
		"top":
			_say("Round the edges will now round only the top edges. Press Round the edges")
		_:
			_say("Round the edges will now round every edge. Press Round the edges")


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
	var h := HFlowContainer.new()   # FMOBILE: the chips wrap onto a second row when the room left of the panel is narrow (1024 wide)
	h.add_theme_constant_override("h_separation", 6)
	h.add_theme_constant_override("v_separation", 6)
	box.add_child(h)
	for chip in Part.LOOK_CHIPS:
		var b := _colour_btn(String(chip[0]).to_lower(), String(chip[0]), chip[1] as Color)
		b.pressed.connect(_paint.bind(String(chip[0]), chip[1] as Color, "Paint"))
		h.add_child(b)
	for pr in COLOUR_PRESETS:
		var b := _colour_btn(pr.to_lower(), pr, Color(0.85, 0.88, 0.92, 0.5) if pr == "Glass" else Color(0.7, 0.72, 0.76))
		b.pressed.connect(_paint.bind(pr, Color.WHITE, pr))
		h.add_child(b)
	var wood := _colour_btn("wood", "Wood", WOOD_COLOUR)   # FTABLE2: a wood-brown paint (the Paint numbers), for a table top or a shelf
	wood.pressed.connect(_paint.bind("Wood", WOOD_COLOUR, "Paint"))
	h.add_child(wood)
	return box


## REPEAT IT: Row or Ring, then How many (2..20 copies, the original counts; FCOMB: a comb of 20 teeth) and Gap (cm between the copies). Its sliders write the Part pattern
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
		var tip := "Copies sideways in a straight row" if not md[2] else "Copies round the up axis, in a full turn"
		var b := _big_btn("easypart_rep_" + String(md[0]), String(md[1]), tip, _rep_mode.bind(bool(md[2])))
		b.toggle_mode = true
		h.add_child(b)
		rep_btns[md[0]] = b
		if md[0] == "row":   # EREPEATUP: Up and Forward sit beside Row (the same straight line, another direction)
			for dd in [["up", "Up", "y", "Copies stacked upward, one on top of the other (a shelf stack)"], ["forward", "Forward", "z", "Copies straight forward, one behind the other"]]:
				var ub := _big_btn("easypart_rep_" + String(dd[0]), String(dd[1]), String(dd[3]), _rep_dir.bind(String(dd[2])))
				ub.toggle_mode = true
				h.add_child(ub)
				rep_btns[dd[0]] = ub
	var cb := _big_btn("easypart_rep_corners", "Corners", "Four copies, one at each corner of the piece it sits on (the legs of a chair or table)", _rep_corners)
	cb.toggle_mode = true
	h.add_child(cb)
	rep_btns["corners"] = cb
	rep_rows.append(_make_row("How many", 2.0, 20.0, 1.0, REP_WORDS["count"], "rep", "count", "copies", vb))
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


## TILT IT: the newest solid (a Pull it up or a Spin it round, not yet tilted) leans TILT_DEG about X through its middle. One step, once
func _tilt_box() -> PanelContainer:
	var box := PanelContainer.new()
	box.name = "easypart_tilt"
	box.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.92), 10, 6))
	box.visible = false
	tilt_btn = _big_btn("easypart_tilt_it", "Tilt it 20 degrees", "Lean the newest solid 20 degrees, sideways, about its middle", _tilt_press)
	tilt_btn.custom_minimum_size = Vector2(230, 44)
	box.add_child(tilt_btn)
	return box


## the newest feature is a solid piece with no tilt yet: the Tilt it chip shows for it
func _tilt_ok(rec: Dictionary) -> bool:
	var feats: Array = rec.get("features", [])
	if feats.is_empty():
		return false
	var f: Dictionary = feats[feats.size() - 1]
	return String(f.get("t", "")) in ["extrude", "revolve"] and not bool(f.get("off", false)) and absf(float(f.get("tilt", 0.0))) < 1e-9 and String(f.get("op", "join")) != "cut"


func _tilt_press() -> void:
	if not Part.available():
		_say(Part.why_not())
		return
	_flush_if_dirty()
	armed = ""
	if not _tilt_ok(_rec()):
		return
	var snap := _rec().duplicate(true)
	_begin("Tilt it")
	var f: Dictionary = _rec()["features"][-1]
	f["tilt"] = TILT_DEG
	if _last_error(_rec(), String(f["id"])) != "":
		m.S.part = snap
		m._drop_undo()
		_edit_n = -1
		_say("That piece cannot lean: it would not stay on the model")
		return
	_end()
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_values_sync()
	_say("Tilted 20 degrees: the piece leans about its middle")


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
	b.custom_minimum_size = Vector2(84, 44)   # 84 (was 92): eight chips with Wood still end left of the panel at 1280 x 720
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


## FNAMECHANGE: a click on the title opens the name box with the name in it, all selected
func _title_gui(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_rename_open()


func _rename_open() -> void:
	if _renaming or _rec().is_empty():
		return
	_renaming = true
	name_edit.text = String(_rec().get("name", "Part"))
	title_l.hide()
	name_edit.show()
	name_edit.grab_focus()
	name_edit.select_all()


func _name_edit_gui(ev: InputEvent) -> void:
	if ev is InputEventKey and (ev as InputEventKey).pressed and (ev as InputEventKey).keycode == KEY_ESCAPE:
		_rename_close(false)
		get_viewport().set_input_as_handled()


## the box closes (Enter, a click away: commit; Escape: keep the old name). The title shows again
func _rename_close(commit: bool) -> void:
	if not _renaming:
		return
	_renaming = false
	var txt := name_edit.text
	name_edit.hide()
	title_l.show()
	if commit:
		_rename(txt)
	_chrome_sync()


## one undo step; an empty name keeps the old one; the name is plain text, at most 40 letters
func _rename(txt: String) -> void:
	var nm := txt.strip_edges().substr(0, 40)
	if nm == "" or nm == String(_rec().get("name", "")):
		return
	m._step_hint = "Renamed the part: %s" % nm
	m._push_undo()
	m.S.part["name"] = nm
	_say("Renamed: the part is %s" % nm)
	_chrome_sync()


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
		_pending[row["key"]] = v if bool(row.get("raw", false)) else v * 10.0   # the slider says cm, the record mm (NGEAR: a raw slider says its own number)
		hole_base = {}                    # the template's sizes changed: the hole chips would rebuild on an old shape
	elif row["kind"] == "rep":
		_apply_rep(row, v)
	elif row["kind"] == "taper":
		_apply_taper(v)
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


## FPLANTER: the Taper slider writes the pulled shape's taper (degrees; the kernel narrows the extrude when it is positive)
func _apply_taper(v: float) -> void:
	var f := Part.feature(_rec(), String(taper_tw.get("id", "")))
	if not f.is_empty():
		f["taper"] = v


## the Repeat it sliders: How many = the copies; Gap = cm between the copies (the spacing = the body width + the gap, in the record mm)
func _apply_rep(row: Dictionary, v: float) -> void:
	var f := Part.feature(_rec(), rep_id)
	if f.is_empty():
		return
	if String(row["key"]) == "count":
		f["count"] = int(roundf(v))
	else:
		f["gap"] = v * 10.0
		f["mm"] = _span(f) + v * 10.0


## EREPEATUP: the size of the body along the copy direction (a row: its width, Up: its height, Forward: its depth), in mm
func _span(f: Dictionary) -> float:
	var ax := String(f.get("dir", "x"))
	return float(f.get("h" if ax == "y" else ("d" if ax == "z" else "w"), f.get("w", 10.0)))


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
	if unit == "teeth":   # NGEAR
		return "%d teeth" % int(roundf(v))
	if unit == "size":   # NGEAR: the module 1 / 2 / 3 as Small / Medium / Big teeth
		return ["Small", "Medium", "Big"][clampi(int(roundf(v)) - 1, 0, 2)] + " teeth"
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


func _make_row(label: String, lo: float, hi: float, step: float, words: Array, kind: String, key: String, unit: String, into: Control = null, raw := false) -> Dictionary:
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
	var row := {"key": key, "slider": s, "pill": pill, "kind": kind, "unit": unit, "label": label, "box": v, "words": w, "raw": raw}
	s.value_changed.connect(_on_slider_value.bind(row))
	s.drag_started.connect(_on_slider_start.bind(row))
	s.drag_ended.connect(_on_slider_end.bind(row))
	return row


## the rows follow the record: the template's own numbers (cm) and the last step's slider
func _rows_sync() -> void:
	_tweak_stale()
	var t := _tpl()
	# FKEY: the label is in the signature: after an Undo a new step can take the id of the step it replaced, and its slider must still be rebuilt
	var sig := "%s|%s|%s|%s|%s" % [t, JSON.stringify(tweak.get("id", "")), _compact, String(tweak.get("label", "")), _taper_live()]
	if sig == _rows_sig:
		return
	_rows_sig = sig
	for c in rows_vb.get_children():
		rows_vb.remove_child(c)
		c.queue_free()
	rows = []
	if t != "" and not PartTemplates.T[t].get("parts", false):   # NSCREW2: a screw's numbers are the Parts chips, not sliders
		for d in PartTemplates.T[t]["params"]:
			var raw := bool(d.get("raw", false))   # NGEAR: a raw slider (teeth, a size step) keeps its own numbers and unit
			var r := _make_row(String(d["label"]), float(d["lo"]) if raw else float(d["lo"]) / 10.0, float(d["hi"]) if raw else float(d["hi"]) / 10.0, float(d["step"]) if raw else float(d["step"]) / 10.0, d["words"], "tpl", String(d["k"]), String(d["unit"]) if raw else "cm", null, raw)
			rows.append(r)
	if not tweak.is_empty():
		var tw: Dictionary = tweak
		var r := _make_row(String(tw["label"]), float(tw["lo"]), float(tw["hi"]), float(tw["step"]), tw.get("words", ["Less", "More"]), "tweak", "last", String(tw["unit"]))
		rows.append(r)
	taper_row = {}
	if _taper_live():   # FPLANTER: the Taper row sits UNDER How far; it is not in rows (rows[-1] stays the step's own slider)
		taper_row = _make_row(String(taper_tw["label"]), float(taper_tw["lo"]), float(taper_tw["hi"]), float(taper_tw["step"]), taper_tw["words"], "taper", "taper", String(taper_tw["unit"]))
		(taper_row["words"] as Control).visible = not _compact
	for r in rows:
		(r["words"] as Control).visible = not _compact
	_values_sync()


## FPLANTER: the Taper row shows while its pull is the newest step (any later step hides it; an Undo that brings the pull back shows it again)
func _taper_live() -> bool:
	if taper_tw.is_empty():
		return false
	var fs: Array = _rec().get("features", [])
	return not fs.is_empty() and String((fs[-1] as Dictionary).get("id", "")) == String(taper_tw.get("id", "")) and String((fs[-1] as Dictionary).get("t", "")) == "extrude"


## FROOM: the How far slider on a building project reaches 3 m (a wall is 2 m or more); the other projects keep 40 cm
func _pull_hi() -> float:
	return 300.0 if m != null and m.S != null and m.S.kind == "building" else 40.0


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
	elif t == "fillet" and f.has("r"):   # FSAVE: a reopened part keeps its Round slider (the same one _round_done gives a new round)
		tweak = {"id": f["id"], "field": "r", "label": "How round", "unit": "cm", "lo": 0.1, "hi": 1.0, "step": 0.1, "scale": 10.0, "words": ["Barely", "Very round"]}
	elif t == "extrude" and not bool(f.get("both", false)) and String(f.get("op", "join")) == "join" and f.has("dist"):
		var dist := float(f["dist"])
		tweak = {"id": f["id"], "field": "dist", "label": "How far", "unit": "cm", "lo": 0.2, "hi": _pull_hi(), "step": 0.2, "scale": 10.0, "words": ["Flatter", "Taller"], "sgn": -1.0 if dist < 0.0 else 1.0}
		var pk := Part.feature(_rec(), String(f.get("sketch", "")))
		var pf := Part.feature(_rec(), String(pk.get("plane", "front")))
		var face := String(pf.get("t", "")) == "plane" and pf.has("out")   # a pull off a face or an upright one keeps How far (as _pull does)
		if not pk.is_empty() and not face and not bool(pf.get("through", false)) and _flat_plate(pk, dist):
			tweak = _thickness_tweak(f["id"], -1.0 if dist < 0.0 else 1.0)   # NTHICK: a reopened flat plate keeps its Thickness slider
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
	var all_rows := rows.duplicate()
	if not taper_row.is_empty():
		all_rows.append(taper_row)
	for r in all_rows:
		var s: HSlider = r["slider"]
		var v := 0.0
		if r["kind"] == "tpl":
			v = float(e.get("p", {}).get(r["key"], 0.0)) if bool(r.get("raw", false)) else float(e.get("p", {}).get(r["key"], 0.0)) / 10.0
		elif r["kind"] == "taper":
			v = float(Part.feature(_rec(), String(taper_tw.get("id", ""))).get("taper", 0.0))
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
## FHELP3: Easy is already on: the press says what the screen is and what to press, and the button stays lit
func _easy_on() -> void:
	easy_btn.set_pressed_no_signal(true)
	_say("You are in Easy: big buttons and sliders. Press Expert for every tool and exact numbers")


func _empty() -> void:
	if not Part.available():
		_chips_sync()
		return
	if (_rec().get("features", []) as Array).is_empty():   # FHELP3: an empty part already: say so, not a silent press
		_chips_sync()
		_say("Already empty: press Draw shape, then drag on the grid")
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
	_screw_sync()


## NSCREW2: the screw grid: four columns (M3 M4 M5 M6), one row per length (10 16 20 30 mm), each chip with a small screw icon
func _screw_box() -> PanelContainer:
	var pc := PanelContainer.new()
	pc.name = "easypart_screw_box"
	pc.add_theme_stylebox_override("panel", _style(Color(0.12, 0.125, 0.15), 10, 6))
	pc.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	pc.add_child(vb)
	var hd := Label.new()
	hd.name = "easypart_screw_words"
	hd.text = "Screws, socket head: pick a size. It drops on the floor"
	hd.add_theme_font_size_override("font_size", 14)
	hd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	screw_words = hd
	vb.add_child(hd)
	var g := GridContainer.new()
	g.columns = SCREW_DS.size()
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	vb.add_child(g)
	nw_btn = Button.new()   # NNUTWASHER: the nut (ISO 4032) and washer (ISO 7089) of the screw on the floor, in one click
	nw_btn.name = "easypart_nw_add"
	nw_btn.text = "Add its nut and washer"
	nw_btn.icon = _nw_icon()
	nw_btn.tooltip_text = "Put the nut and the washer of this screw on the floor beside it. One click, one undo step"
	nw_btn.focus_mode = Control.FOCUS_NONE
	nw_btn.custom_minimum_size = Vector2(0, 34)
	nw_btn.add_theme_font_size_override("font_size", 13)
	nw_btn.add_theme_stylebox_override("normal", _style(Color(0.165, 0.176, 0.212), 6, 4))
	nw_btn.add_theme_stylebox_override("hover", _style(Color(0.23, 0.245, 0.29), 6, 4))
	nw_btn.pressed.connect(_nw_add)
	vb.add_child(nw_btn)
	for L in SCREW_LENS:
		for d in SCREW_DS:
			var hw: float = float(PartTemplates.SCREW_HEAD[d][0])
			var hh: float = float(PartTemplates.SCREW_HEAD[d][1])
			var b := Button.new()
			b.name = "easypart_screw_M%d_%d" % [d, L]
			b.text = "M%d x %d" % [d, L]
			b.icon = _screw_icon(d, L)
			b.tooltip_text = "M%d x %d: head %s mm across, %s mm high, plain shank %d mm long" % [d, L, str(hw), str(hh), L]
			b.toggle_mode = true
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(0, 34)
			b.add_theme_font_size_override("font_size", 13)
			b.add_theme_stylebox_override("normal", _style(Color(0.165, 0.176, 0.212), 6, 4))
			b.add_theme_stylebox_override("hover", _style(Color(0.23, 0.245, 0.29), 6, 4))
			b.pressed.connect(_screw_pick.bind(d, L))
			g.add_child(b)
			screw_btns["%d_%d" % [d, L]] = b
	return pc


## NSCREW2: a small screw icon, drawn from the size: head width grows with M, shank length with the length (the same 16 px box)
func _screw_icon(d: int, L: int) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col := Tok.c("text")
	var hw := clampi(int(round(4.0 + 1.2 * float(d))), 6, 14)
	img.fill_rect(Rect2i(8 - hw / 2, 0, hw, 4), col)
	var sw := maxi(2, int(round(0.5 * float(d))))
	var sh := clampi(int(round(0.3 * float(L))), 4, 11)
	img.fill_rect(Rect2i(8 - sw / 2, 4, sw, sh), col)
	return ImageTexture.create_from_image(img)


## NNUTWASHER: a small nut and washer icon (the same 16 px box as the screw icon, Tok colour only)
func _nw_icon() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col := Tok.c("text")
	img.fill_rect(Rect2i(1, 10, 14, 3), col)
	img.fill_rect(Rect2i(4, 3, 8, 6), col)
	img.fill_rect(Rect2i(6, 5, 4, 2), Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


## NNUTWASHER: the nut button. No screw on the floor: it says what to do first. Its nut and washer already there: it says so (no undo step).
## Else one undo step puts them on the floor beside the screw, sized to it.
func _nw_add() -> void:
	if not Part.available():
		_chips_sync()
		return
	var on_floor := _tpl() == "screw" and not (_rec().get("features", []) as Array).is_empty()
	if not on_floor:
		_say("Put a screw on the floor first: pick a size above, then press Add its nut and washer")
		_screw_sync()
		return
	var e: Dictionary = _rec().get("easy", {})
	if int(e.get("nw", -1)) >= 0:
		_say("Its nut and washer are on the floor already. Pick another size to change all three")
		_screw_sync()
		return
	armed = ""
	hole_base = {}
	split_id = ""
	_flush_if_dirty()
	m._step_hint = "Add the nut and washer"
	m._push_undo()
	PartTemplates.nw_add(_rec(), int(e["p"]["d"]))
	tweak = {}
	pu.upto = -1
	pu.sync()
	frame()
	if not (pu.res.get("errors", {}) as Dictionary).is_empty():
		_say("The nut and washer did not build. Press Reset, then pick a size again")
	else:
		_say("Nut and washer on the floor beside the screw. Pick another size to change all three")
	_screw_sync()


## NSCREW2: the Parts chip opens or shuts the screw grid (a screw on the floor keeps it open)
func _parts_press() -> void:
	if not Part.available():
		_chips_sync()
		return
	parts_open = not parts_open
	lib_cat = "Screws" if parts_open else ""   # NLIBPAGE: the page opens on Screws, its sizes showing
	_say("Parts: pick a kind. Screws is open: pick a size. It drops on the floor" if parts_open else "Parts shut. Press Parts to open them again")
	_screw_sync()


## NLIBPAGE: a category chip. Screws shows the sizes, Gears says to press the Gear chip, the others say coming soon with the next step.
## Opening a category is not an action: no undo step.
func _lib_press(cat: String) -> void:
	if not Part.available():
		_chips_sync()
		return
	parts_open = true
	lib_cat = cat
	if cat == "Screws":
		_say("Screws: pick a size. It drops on the floor")
	elif cat == "Gears":
		_say("Gears: press Gear in the chips above. It drops on the floor")
	else:
		_say("%s are coming soon. Next step: press Screws or Gears" % cat)
	_screw_sync()


## NLIBPAGE: the library page: a header line, ten category chips (icon + plain word), and the coming-soon line
func _lib_box() -> PanelContainer:
	var pc := PanelContainer.new()
	pc.name = "easypart_library"
	pc.add_theme_stylebox_override("panel", _style(Color(0.12, 0.125, 0.15), 10, 6))
	pc.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	pc.add_child(vb)
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 4)
	fl.add_theme_constant_override("v_separation", 4)
	vb.add_child(fl)
	for cat in LIB_CATS:
		var b := Button.new()
		b.name = "easypart_lib_" + cat
		b.text = cat
		b.icon = _lib_icon(cat)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 34)
		b.add_theme_font_size_override("font_size", 13)
		b.tooltip_text = ("%s: ready now" % cat) if cat in LIB_READY else ("%s: coming soon" % cat)
		b.add_theme_stylebox_override("normal", _style(Color(0.165, 0.176, 0.212), 6, 4))
		b.add_theme_stylebox_override("hover", _style(Color(0.23, 0.245, 0.29), 6, 4))
		b.pressed.connect(_lib_press.bind(cat))
		fl.add_child(b)
		lib_btns[cat] = b
	lib_soon = Label.new()
	lib_soon.name = "easypart_lib_soon"
	lib_soon.add_theme_font_size_override("font_size", 14)
	lib_soon.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lib_soon.visible = false
	vb.add_child(lib_soon)
	return pc


## NLIBPAGE: a 16 px icon per category, drawn in the text colour (Tok): a screw, a gear ring, a nut, a washer, hinge leaves, bearing rings,
## a spring, a handle, a wheel with spokes, a bracket
func _lib_icon(cat: String) -> ImageTexture:
	if cat == "Screws":
		return _screw_icon(4, 16)
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col := Tok.c("text")
	match cat:
		"Gears":
			_lib_ring(img, 7.0, 4.5, col)
			img.fill_rect(Rect2i(7, 0, 2, 2), col)
			img.fill_rect(Rect2i(7, 14, 2, 2), col)
			img.fill_rect(Rect2i(0, 7, 2, 2), col)
			img.fill_rect(Rect2i(14, 7, 2, 2), col)
		"Nuts":
			img.fill_rect(Rect2i(2, 4, 12, 8), col)
			img.fill_rect(Rect2i(6, 6, 4, 4), Color(0, 0, 0, 0))
		"Washers":
			_lib_ring(img, 7.0, 3.5, col)
		"Hinges":
			img.fill_rect(Rect2i(0, 3, 7, 3), col)
			img.fill_rect(Rect2i(9, 3, 7, 3), col)
			img.fill_rect(Rect2i(0, 10, 7, 3), col)
			img.fill_rect(Rect2i(9, 10, 7, 3), col)
			img.fill_rect(Rect2i(7, 1, 2, 14), col)
		"Bearings":
			_lib_ring(img, 7.0, 5.0, col)
			_lib_ring(img, 3.0, 1.0, col)
		"Springs":
			for y in range(16):
				var x := 8 + int(round(4.0 * sin(float(y) * 0.9)))
				img.fill_rect(Rect2i(x - 1, y, 2, 1), col)
		"Handles":
			img.fill_rect(Rect2i(1, 2, 14, 3), col)
			img.fill_rect(Rect2i(1, 2, 3, 12), col)
			img.fill_rect(Rect2i(12, 2, 3, 12), col)
		"Wheels":
			_lib_ring(img, 7.0, 5.0, col)
			img.fill_rect(Rect2i(7, 1, 2, 14), col)
			img.fill_rect(Rect2i(1, 7, 14, 2), col)
		"Brackets":
			img.fill_rect(Rect2i(2, 1, 3, 14), col)
			img.fill_rect(Rect2i(2, 12, 13, 3), col)
	return ImageTexture.create_from_image(img)


## NLIBPAGE: a ring of colour between the two radii, on a 16 px icon
func _lib_ring(img: Image, r_out: float, r_in: float, col: Color) -> void:
	for y in range(16):
		for x in range(16):
			var d := Vector2(x + 0.5 - 8.0, y + 0.5 - 8.0).length()
			if d <= r_out and d >= r_in:
				img.set_pixel(x, y, col)


## NSCREW2: a size chip. No screw on the floor: a new screw of that size (one undo step). A screw already there: its size changes
## (one undo step, the same steps). The same size again does nothing.
func _screw_pick(d: int, L: int) -> void:
	if not Part.available():
		_chips_sync()
		return
	var label := "M%d x %d" % [d, L]
	var on_floor := _tpl() == "screw" and not (_rec().get("features", []) as Array).is_empty()
	if on_floor:
		var cur: Dictionary = (_rec().get("easy", {}) as Dictionary).get("p", {})
		if int(cur.get("d", 0)) == d and int(cur.get("L", 0)) == L:
			_say("Already %s on the floor. Pick another size to change it" % label)
			_screw_sync()
			return
	armed = ""
	hole_base = {}
	split_id = ""
	_flush_if_dirty()
	m._step_hint = "Change the screw size" if on_floor else "Start a screw"
	m._push_undo()
	if on_floor:
		PartTemplates.retemplate(_rec(), {"d": d, "L": L})
		PartTemplates.nw_set(_rec(), d)   # NNUTWASHER: the nut and washer (if on the floor) follow the size
	else:
		m.S.part = PartTemplates.make("screw", {"d": d, "L": L})
	tweak = {}
	pu.upto = -1
	pu.sync()
	frame()
	if not (pu.res.get("errors", {}) as Dictionary).is_empty():
		_say("%s did not build. Press Reset, then pick a size again" % label)
	else:
		_say("%s on the floor. Pick another size to change it" % label)
	_screw_sync()


## NSCREW2: the grid's open state and the pressed size (the screw on the floor); the Parts chip is pressed while the grid shows
func _screw_sync() -> void:
	if lib_box != null:   # NLIBPAGE: the page shows while Parts is open; the open category is pressed; the coming-soon line names it
		lib_box.visible = parts_open
		for cat in lib_btns:
			var lb: Button = lib_btns[cat]
			lb.set_pressed_no_signal(parts_open and cat == lib_cat)
			m._grey(lb, Part.why_not() if not Part.available() else "")
		lib_soon.visible = parts_open and lib_cat != "" and not (lib_cat in LIB_READY)
		if screw_words != null:   # the page is open: its chips and the status line say what to do
			screw_words.visible = not parts_open
		lib_soon.text = "%s are coming soon: not made yet. Next step: press Screws or Gears" % lib_cat if lib_soon.visible else ""
	if screw_box == null or parts_btn == null:
		return
	var cur: Dictionary = {}
	if _tpl() == "screw":
		cur = (_rec().get("easy", {}) as Dictionary).get("p", {})
	screw_box.visible = (parts_open and lib_cat == "Screws") or _tpl() == "screw"
	parts_btn.set_pressed_no_signal(parts_open)
	for d in SCREW_DS:
		for L in SCREW_LENS:
			var b: Button = screw_btns["%d_%d" % [d, L]]
			b.set_pressed_no_signal(not cur.is_empty() and int(cur.get("d", 0)) == d and int(cur.get("L", 0)) == L)
			m._grey(b, Part.why_not() if not Part.available() else "")
	parts_btn.set_pressed_no_signal(parts_open)


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
			_say("Stick together needs two separate pieces: draw a new shape apart from the solid, Pull it up, then press Stick together again")   # FWRENCH: the old words did not say how to get a second piece
			return
		armed = "stick"
		_say(_arm_words("stick"))
		return
	if which == "draw" or which == "curve" or which == "colour":
		_ease_end()   # FBOLT: Draw shape lands a camera ease still running, so the press that follows lands on the shape
		armed = "" if armed == which else which
		if armed == "draw":
			shape = "box"   # every Draw shape press starts on Box: the Round chip of the last shape (a mug) does not carry over (a chair leg is a box)
			_sync_shape()
		_draft = {}
		_say(_arm_words(armed))
		return
	armed = ""
	var snap := _rec().duplicate(true)
	var label := "Duplicate" if which == "duplicate" else String((MAKES.filter(func(x): return x[0] == which)[0])[1])   # FDUP: the top bar's Duplicate is not a MAKE button
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
		"duplicate":
			why = _duplicate(rec)
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
	if snap_btn != null:
		snap_btn.set_pressed_no_signal(_rec_has_lip())   # the record says it (an Undo takes the chip off with the lip)
		snap_btn.visible = hole_mode == "lid"   # the chip only exists for a lid


## a Through / Hollow inside chip: the hole step is REPLACED (one undo step): the record from before the hole press, then the chosen hole.
## A hollow that fails (a body too thin for the wall) says so and changes nothing
func _hole_mode(mode: String, lip := false, rebuild := false) -> void:   # lip: the lid with its Snap-fit lip; rebuild: the same chip again (the Snap-fit lip press)
	if not _hole_on() or not Part.available() or (mode == hole_mode and not rebuild):
		_hole_sync()
		return
	_flush_if_dirty()
	armed = ""
	var snap := _rec().duplicate(true)
	_begin("Hollow with a lid" if mode == "lid" else ("Hollow inside" if mode == "hollow" else "Cut a hole"))
	var rec: Dictionary = hole_base.duplicate(true)
	m.S.part = rec
	var why := _hollow_lid(rec, lip) if mode == "lid" else (_hollow(rec) if mode == "hollow" else _hole(rec))
	if why != "":
		m.S.part = snap
		m._drop_undo()
		_edit_n = -1
		_say(why)
	else:
		_end()
		hole_mode = mode
		hole_id = String(tweak.get("id", "")) if not tweak.is_empty() else String(rec["features"][-1].get("id", ""))   # the lid has no slider: its newest step keeps the chips up
	pu.upto = -1
	pu.sync()
	_rows_sig = ""   # the step's id can repeat the last one (the chips rebuild from an older record): the slider box is rebuilt anyway
	_rows_sync()
	_values_sync()


## NOPENTOP: after Hollow inside, a click on a flat face makes THAT face the open side (one undo step): the shell's "open" is set to the
## face's direction and the Wall slider keeps its step (the same id). A side that cannot open says so and changes nothing. false = not a face click here
const OPEN_WORDS := {"+x": "right", "-x": "left", "+y": "top", "-y": "bottom", "+z": "front", "-z": "back"}


func _open_face(p: Vector2) -> bool:
	if hole_mode != "hollow" or not _hole_on() or _tpl() != "":
		return false
	var sh := Part.feature(_rec(), hole_id)
	if String(sh.get("t", "")) != "shell":
		return false
	var fc := _face_hit(p)
	if fc.is_empty():
		return false
	var ax := ["right", "top", "front"].find(String(fc.get("base", "")))
	if ax < 0:
		return false
	var dir: String = ["+x", "+y", "+z"][ax] if int(fc.get("out", 1)) > 0 else ["-x", "-y", "-z"][ax]
	var side: String = String(OPEN_WORDS[dir])
	if dir == String(sh.get("open", "")):
		_say("The %s is already open. Click another flat face to open that one" % side)
		return true
	_flush_if_dirty()
	armed = ""
	var snap := _rec().duplicate(true)
	_begin("Open the " + side)
	var rec: Dictionary = snap.duplicate(true)
	Part.feature(rec, hole_id)["open"] = dir
	var why := ""
	if _last_error(rec, hole_id) != "":
		why = "The %s cannot be the open side: click another flat face, or Cut a hole again" % side
	if why != "":
		m.S.part = snap
		m._drop_undo()
		_edit_n = -1
		_say(why)
	else:
		m.S.part = rec
		_end()
		_say("Open the %s: the %s is open now. The Wall slider still sets the wall" % [side, side])
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_values_sync()
	return true


## SNAP-FIT LIP (nsnaplip): the on/off chip under Hollow with a lid. On: the lid's ridge and the box's groove are rebuilt from the same
## hole base (one undo step). Only a lid has a snap; the other shapes say what to press first
func _snap_press() -> void:
	if hole_mode != "lid" or not _hole_on() or not Part.available():
		_hole_sync()
		_say("Snap-fit lip needs a lid first: press Cut a hole, then Hollow with a lid, then Snap-fit lip")
		return
	_hole_mode("lid", not _rec_has_lip(), true)   # on: rebuild the lid with the lip; off: rebuild it plain (the same chip, one step)

## the record has a snap-fit lip (its groove step is tagged "lip")
func _rec_has_lip() -> bool:
	for f in _rec().get("features", []):
		if bool((f as Dictionary).get("lip", false)):
			return true
	return false


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
	var last: Dictionary = rec["features"][-1] if not rec["features"].is_empty() else {}
	if String(last.get("t", "")) == "loft" and (last.get("sketches", []) as Array).size() == 2:
		return _hollow_loft(rec, last)   # a blended bowl: Part's shell on a loft takes minutes, so the wall is an inner loft cut out instead
	var f := Part.new_feature(rec, "shell", {"body": n - 1, "open": "+y", "thick": HOLLOW_MM})
	rec["features"].append(f)
	if _last_error(rec, String(f["id"])) != "":
		rec["features"].pop_back()   # the kernel's shell refuses a cup standing on a base (it picks the base's ring for the open top): cut the cup's inside instead
		return _hollow_cup(rec, too_thin)
	tweak = {"id": f["id"], "field": "thick", "label": "Wall", "unit": "mm", "lo": 1.0, "hi": 10.0, "step": 0.5, "scale": 1.0, "words": ["Thinner", "Thicker"]}
	_say("Hollowed out, open at the top: use the slider for the wall")
	return ""


## HOLLOW WITH A LID (nlid): a box (one body, a rectangle pulled up) is split at its top LID_MM: the top slice is the LID, a solid plate on
## the box's footprint; the rest is hollowed out (a HOLLOW_MM wall, open at the top). A lip (1 mm ring, LID_LIP_MM tall, 0.2 mm inside the
## walls) hangs under the lid into the box: a plug cut back to a ring. Box-shaped only; no slider (the lip is cut to the walls). "" or why not
func _hollow_lid(rec: Dictionary, snap := false) -> String:
	var res := Part.replay(rec)
	if int(res["bodies"]) == 0:
		return "Nothing solid to hollow out yet. Press Pull it up first"
	var bb: AABB = res["aabb"]
	var sz := bb.size / Part.MM
	var too_small := "That box is too small for a lid: Pull it up at least 12 mm tall and 12 mm wide, then press Cut a hole again"
	if int(res["bodies"]) != 1 or minf(sz.x, minf(sz.y, sz.z)) < 12.0:
		return too_small
	if float(res["volume"]) / (Part.MM * Part.MM * Part.MM) < 0.98 * sz.x * sz.y * sz.z:
		return "A lid needs a box: Pull a rectangle up into a box, then press Cut a hole again"
	var x0 := bb.position.x / Part.MM
	var x1 := bb.end.x / Part.MM
	var z0 := bb.position.z / Part.MM
	var z1 := bb.end.z / Part.MM
	var top := bb.end.y / Part.MM
	var ins_o := HOLLOW_MM + 0.2          # the lip's outer face: 0.2 mm inside the wall
	var ins_i := ins_o + 1.0              # the lip's inner face: a 1 mm ring
	var sp := Part.new_feature(rec, "split", {"plane": "top", "at": top - LID_MM, "keep": 0})   # bodies: [the top slice (the lid), the box]
	rec["features"].append(sp)
	var sh := Part.new_feature(rec, "shell", {"body": 1, "thick": HOLLOW_MM, "open": "+y"})
	rec["features"].append(sh)
	var fids := [sp["id"], sh["id"]]
	var band_y := top - LID_MM - LID_LIP_MM + 1.0   # the snap band: 1 mm tall, the lip's middle third (under the plate, above the lip's floor)
	var gr: Dictionary = {}
	if snap:   # the groove first (the box is alone on its wall here; a cut hits every body): a ring 0.5 mm deep in the wall
		var pg := Part.new_feature(rec, "plane", {"from": "top", "mm": band_y})
		rec["features"].append(pg)
		var sg := Part.new_feature(rec, "sketch", {"plane": String(pg["id"]), "ents": [_rect_ent(x0 + HOLLOW_MM - LIP_RIDGE_MM, z0 + HOLLOW_MM - LIP_RIDGE_MM, x1 - HOLLOW_MM + LIP_RIDGE_MM, z1 - HOLLOW_MM + LIP_RIDGE_MM)], "dims": []})
		rec["features"].append(sg)
		gr = Part.new_feature(rec, "extrude", {"sketch": sg["id"], "dist": 1.0, "both": false, "op": "cut", "lip": true})
		rec["features"].append(gr)
		fids.append(gr["id"])
	var pf := Part.new_feature(rec, "plane", {"from": "top", "mm": top - LID_MM - LID_LIP_MM})
	rec["features"].append(pf)
	var s1 := Part.new_feature(rec, "sketch", {"plane": String(pf["id"]), "ents": [_rect_ent(x0 + ins_o, z0 + ins_o, x1 - ins_o, z1 - ins_o)], "dims": []})
	rec["features"].append(s1)
	var f1 := Part.new_feature(rec, "extrude", {"sketch": s1["id"], "dist": LID_LIP_MM, "both": false, "op": "join", "into": 0})
	rec["features"].append(f1)
	var s2 := Part.new_feature(rec, "sketch", {"plane": String(pf["id"]), "ents": [_rect_ent(x0 + ins_i, z0 + ins_i, x1 - ins_i, z1 - ins_i)], "dims": []})
	rec["features"].append(s2)
	var f2 := Part.new_feature(rec, "extrude", {"sketch": s2["id"], "dist": LID_LIP_MM, "both": false, "op": "cut"})
	rec["features"].append(f2)
	fids.append_array([f1["id"], f2["id"]])
	if snap:   # the ridge: a ring 0.5 mm proud of the lip, joined to the lid (body 0) in the same band as the groove
		var pr := Part.new_feature(rec, "plane", {"from": "top", "mm": band_y})
		rec["features"].append(pr)
		var ro := HOLLOW_MM + 0.2 - LIP_RIDGE_MM   # the ridge's outside: 2.7 mm in (0.5 mm proud of the lip's 3.2 mm face)
		var ri := HOLLOW_MM + 0.2                  # the ridge's inside: the lip's own outer face
		var bars := [[x0 + ro, z0 + ro, x1 - ro, z0 + ri], [x0 + ro, z1 - ri, x1 - ro, z1 - ro], [x0 + ro, z0 + ri, x0 + ri, z1 - ri], [x1 - ri, z0 + ri, x1 - ro, z1 - ri]]
		fids.append(pr["id"])
		for b in bars:   # four bars (front, back, left, right), each joined to the lid (body 0): a ring with no cut
			var sr := Part.new_feature(rec, "sketch", {"plane": String(pr["id"]), "ents": [_rect_ent(b[0], b[1], b[2], b[3])], "dims": []})
			rec["features"].append(sr)
			var fr := Part.new_feature(rec, "extrude", {"sketch": sr["id"], "dist": 1.0, "both": false, "op": "join", "into": 0, "lip": true})
			rec["features"].append(fr)
			fids.append(fr["id"])
	for fid in fids:
		if _last_error(rec, String(fid)) != "":
			return too_small
	if Part.replay(rec)["bodies"] != 2:
		return too_small
	tweak = {}
	_say("Hollowed out with a lid and a snap-fit lip: the lid's ridge clicks into the box's groove. Ctrl+Z undoes it" if snap else "Hollowed out with a lid: the top 5 mm is the lid, sitting on the box. Ctrl+Z undoes it")
	return ""


## a rectangle sketch entity from its two corners in the sketch's plane (top plane: v = -Z), mm
func _rect_ent(xa: float, za: float, xb: float, zb: float) -> Dictionary:
	return {"k": "rect", "a": Part.arr2(Vector2(xa, -za)), "b": Part.arr2(Vector2(xb, -zb))}


## FCANDLE: Hollow inside for a cup on a base (the newest round piece on a solid): a circle HOLLOW_MM inside the cup's own shape, cut down
## from the top of the whole solid to HOLLOW_MM above the cup's floor. The cup keeps its floor and wall and is open at the top. "" or why not
func _hollow_cup(rec: Dictionary, too_thin: String) -> String:
	var sk := _last_sketch(rec)
	if sk.is_empty() or (sk["ents"] as Array).size() != 1 or String((sk["ents"][0] as Dictionary).get("k", "")) != "circle":
		return too_thin
	var ent: Dictionary = sk["ents"][0]
	var pl := Part.resolve_plane(rec, String(sk.get("plane", "top")))
	var floor_mm: float = float(pl["o"].y) / Part.MM   # the cup's floor: the plane it was drawn on (mm)
	var top_mm: float = Part.replay(rec).get("aabb", AABB()).end.y / Part.MM
	var r_in := float(ent.get("r", 0.0)) - HOLLOW_MM
	var depth := top_mm - (floor_mm + HOLLOW_MM)
	if r_in <= 1.0 or depth <= 1.0:
		return too_thin
	var before := float(pu.replay_full(rec)["volume"])
	var pf := Part.new_feature(rec, "plane", {"from": "top", "mm": snappedf(top_mm, 0.1)})
	rec["features"].append(pf)
	var c: Array = ent.get("c", [0.0, 0.0])
	var s := Part.new_feature(rec, "sketch", {"plane": String(pf["id"]), "ents": [{"k": "circle", "c": c.duplicate(), "r": snappedf(r_in, 0.1)}], "dims": []})
	rec["features"].append(s)
	var f := Part.new_feature(rec, "extrude", {"sketch": s["id"], "dist": -snappedf(depth, 0.1), "both": false, "op": "cut"})
	rec["features"].append(f)
	if _last_error(rec, String(f["id"])) != "" or float(pu.replay_full(rec)["volume"]) >= before - 1e-12:
		return too_thin
	tweak = {"id": f["id"], "field": "dist", "label": "How deep", "unit": "cm", "lo": 0.1, "hi": 40.0, "step": 0.1, "scale": 10.0, "words": ["Shallower", "Deeper"], "sgn": -1.0}
	_say("Hollowed out, open at the top: use the slider for how deep")
	return ""


## HOLLOW A BLEND (FSPOON): the inner loft of the blend's two shapes, each pulled in by HOLLOW_MM (the lower one lifted HOLLOW_MM off
## the bottom, the upper one carried past the top), cut out of the solid: open at the top, a 3 mm wall. Part's shell on the same loft
## took about 3 minutes per replay; this cut takes a few seconds. The wall is fixed (no Wall slider)
func _hollow_loft(rec: Dictionary, lf: Dictionary) -> String:
	var a: Dictionary = Part.feature(rec, String(lf["sketches"][0]))
	var b: Dictionary = Part.feature(rec, String(lf["sketches"][1]))
	var ha := _half_mm(a["ents"])
	var hb := _half_mm(b["ents"])
	var height := maxf(absf(_plane_mm(rec, b) - _plane_mm(rec, a)), 1.0)
	var taper := maxf((ha - hb) / height, 0.0)   # the blend narrows by this much per mm of height: the top of the cut follows it
	var ia := _inner_sketch(rec, a, HOLLOW_MM, HOLLOW_MM)
	var ib := _inner_sketch(rec, b, 20.0, HOLLOW_MM + taper * 20.0)
	if (ia["ents"] as Array).is_empty() or (ib["ents"] as Array).is_empty():
		return "Those two shapes are too small to hollow out with a 3 mm wall: draw bigger shapes, then press Blend two shapes again"
	var f := Part.new_feature(rec, "loft", {"sketches": [ia["id"], ib["id"]], "ruled": true, "op": "cut"})
	rec["features"].append(f)
	if _last_error(rec, String(f["id"])) != "":
		return "That blend is too thin to hollow out with a 3 mm wall: draw bigger shapes, then press Blend two shapes again"
	tweak = {}
	_say("Hollowed out, open at the top: the wall is 3 mm")
	return ""


## the offset of a sketch's plane along its normal (mm)
func _plane_mm(rec: Dictionary, sk: Dictionary) -> float:
	var pid := String(sk["plane"])
	return 0.0 if pid in Part.PLANES else float(Part.feature(rec, pid).get("mm", 0.0))


## a sketch on a plane lift mm above its own, its outline pulled in by shrink mm (a new plane and a new sketch; the sketch is returned)
func _inner_sketch(rec: Dictionary, sk: Dictionary, lift: float, shrink: float) -> Dictionary:
	var pid := String(sk["plane"])
	var pl := Part.new_feature(rec, "plane", {"from": _base_plane(rec, pid), "mm": _plane_mm(rec, sk) + lift})
	rec["features"].append(pl)
	var s2 := Part.new_feature(rec, "sketch", {"plane": String(pl["id"]), "ents": _shrunk(sk["ents"], shrink), "dims": []})
	rec["features"].append(s2)
	return s2


## the middle and the half of the smaller side (mm) of a sketch's entities: a circle's half is its radius
func _mid_half(ents: Array) -> Array:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var rad := -1.0
	for e in ents:
		if String((e as Dictionary).get("k", "")) == "circle":
			rad = maxf(rad, float(e["r"]))
			lo = lo.min(Vector2(float(e["c"][0]), float(e["c"][1])))
			hi = hi.max(Vector2(float(e["c"][0]), float(e["c"][1])))
			continue
		for q in _ent_pts(e):
			lo = lo.min(Vector2(float(q[0]), float(q[1])))
			hi = hi.max(Vector2(float(q[0]), float(q[1])))
	if lo.x > hi.x:
		return [Vector2.ZERO, 0.0]
	var half := minf(hi.x - lo.x, hi.y - lo.y) * 0.5
	if rad >= 0.0:
		half = rad
	return [(lo + hi) * 0.5, half]


## the half of a sketch's smaller side (mm): the wall needs room inside it
func _half_mm(ents: Array) -> float:
	return float(_mid_half(ents)[1])


## the outline pulled in by d mm: its points scale about the middle (a circle's radius less d); [] when d leaves nothing
func _shrunk(ents: Array, d: float) -> Array:
	var mh := _mid_half(ents)
	var c: Vector2 = mh[0]
	var half: float = mh[1]
	if half <= d + 1.0:
		return []
	var k := (half - d) / half
	var out := []
	for e in ents:
		var e2: Dictionary = (e as Dictionary).duplicate(true)
		if String(e2.get("k", "")) == "circle":
			e2["r"] = float(e2["r"]) - d
		else:
			for key in ["a", "b"]:
				if e2.has(key) and e2[key] is Array:
					e2[key] = Part.arr2(c + (Vector2(float(e2[key][0]), float(e2[key][1])) - c) * k)
			if e2.has("pts"):
				var np := []
				for q in e2["pts"]:
					np.append(Part.arr2(c + (Vector2(float(q[0]), float(q[1])) - c) * k))
				e2["pts"] = np
		out.append(e2)
	return out


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
	# A ROUND CUP (FMUG3): the first pull of a blank part, of one circle, stands as tall as its radius (a mug, not a 2 cm puck)
	if not through and not on_face and sk["ents"].size() == 1 and String(sk["ents"][0].get("k", "")) == "circle" and not _has_pull(rec):
		dist = maxf(20.0, snappedf(float(sk["ents"][0]["r"]), 1.0))   # sketch units are mm: the radius is the height
	if through and _sits_on_body(rec, sk):
		# A ROOF: pulled out both ways from the middle to the box's depth (the slider changes it from there)
		var bb: AABB = Part.replay(rec).get("aabb", AABB())
		var depth := bb.size.z if String(pf.get("from", "front")) == "front" else bb.size.x
		dist = snappedf(depth / Part.MM, 1.0)
	# FBOX: a LID: a face drawing on the top of a hollow (shelled) body is a separate piece, not joined to the box (it rests on the rim)
	var lid := on_face and _top_face(pf) and _has_shell(rec)
	var slot := not on_face and not through and _slot_cut(rec, sk, dist)   # FWRENCH2: a jaw slot at the end of a solid CUTS it
	var nb0 := int(Part.replay(rec).get("bodies", 0))   # FLAMP: a shape that stands apart from the solid is its own body, not one lump
	var lk0 := _lumps(Part.replay(rec)) if nb0 > 0 else 0
	var f := Part.new_feature(rec, "extrude", {"sketch": sid, "dist": dist, "both": through, "op": "new" if lid else ("cut" if slot else "join")})
	rec["features"].append(f)
	var err := _last_error(rec, String(f["id"]))
	if err == "" and nb0 > 0 and not slot and not lid:   # a slot cut never becomes a new body; FBOX: a lid stays its own body (the join pass below would fold it back into the box)
		f["into"] = Part.touching_body(rec, f)   # FLAMP5: a pull joins the body it sits on (saved on the step), not the last body
		err = _last_error(rec, String(f["id"]))
		var joined := Part.replay(rec)
		if int(joined.get("bodies", 0)) == nb0 and _lumps(joined) > lk0:
			f["op"] = "new"
			err = _last_error(rec, String(f["id"]))
	if err != "":
		return "That shape is not closed, so it cannot be pulled up: drag back to the start to close it"
	tweak = {"id": f["id"], "field": "dist", "label": "How far", "unit": "cm", "lo": 0.2, "hi": _pull_hi(), "step": 0.2, "scale": 10.0, "words": ["Flatter", "Taller"], "sgn": sg}
	if not (lid or slot or through or on_face) and _flat_plate(sk, dist):   # NTHICK: a flat plate's slider is its Thickness: thin plate (2 mm) to thick block (40 cm)
		tweak = _thickness_tweak(f["id"], sg)
	if lid:
		_say("A lid on the rim: a separate piece. Use the slider for how tall it is")
	elif slot:
		tweak["say"] = "Cut a slot %s deep into the solid: use the slider to change it, or press Round the edges or Cut a hole next"
		_say(String(tweak["say"]) % _fmt(2.0, "cm"))
	elif through:
		_say("Pulled out both ways from the middle: use the slider for how thick, or press Mirror that or Cut a hole next")
	elif on_face:
		# FWRENCH2: a beginner does not know the word "face": the top of a solid says "top", a side says "side" (the bottom keeps "face": eface_test pins that text)
		var where := "top" if _top_face(pf) else ("side" if String(pf.get("from", "")) in ["front", "right"] else "face")
		_say("Pulled into the solid: use the slider to change it, or press Cut a hole next" if inward else "Pulled out of the %s: use the slider to change it, or press Mirror that next" % where)
	else:
		tweak["say"] = "Pulled up %s: use the slider to change it, or press Round the edges or Cut a hole next"   # the words follow the slider (a beginner walk: "2 cm" stayed at 8 cm); the next button too (ehelp2)
		_say(String(tweak["say"]) % _fmt(absf(dist) / 10.0, "cm"))
	# FPLANTER: a pot is wider at the top: a floor shape pulled up gets a Taper slider under How far (the extrude's taper, degrees)
	taper_tw = {} if (through or on_face) else {"id": f["id"], "label": "Taper", "unit": "deg", "lo": -15.0, "hi": 15.0, "step": 0.5, "words": ["Wider at the top", "Narrower at the top"]}
	return ""


## NTHICK: a FLAT PLATE is a plain pull of a floor shape whose narrow side is at least 10 cm and whose height is at most half of it (and at most 40 cm):
## a slab, not a wall or a pillar. Its slider reads Thickness, from a thin plate (2 mm) to a thick block (40 cm)
func _flat_plate(sk: Dictionary, dist: float) -> bool:
	if String(sk.get("t", "")) != "sketch":
		return false
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var ents: Array = sk.get("ents", [])
	if ents.is_empty():
		return false
	for e in ents:
		var k := String(e.get("k", ""))
		if k != "rect" and k != "line":   # a circle, an arc or a curve is not a plate: the How far stays
			return false
		for key in ["a", "b"]:
			var p: Array = e[key]
			lo = Vector2(minf(lo.x, float(p[0])), minf(lo.y, float(p[1])))
			hi = Vector2(maxf(hi.x, float(p[0])), maxf(hi.y, float(p[1])))
	var narrow := minf(hi.x - lo.x, hi.y - lo.y)
	return narrow >= 100.0 and absf(dist) <= minf(narrow * 0.5, 400.0)


## NTHICK: the slider of a flat plate: its pull's dist, labelled Thickness (cm, 0.2 = 2 mm to 40 = 40 cm)
func _thickness_tweak(id: String, sg: float) -> Dictionary:
	return {"id": id, "field": "dist", "label": "Thickness", "unit": "cm", "lo": 0.2, "hi": 40.0, "step": 0.2, "scale": 10.0, "words": ["Thin plate", "Thick block"], "sgn": sg}


## FMUG3: a part that already has a pull (an extrude step) in its features
func _has_pull(rec: Dictionary) -> bool:
	for f in rec.get("features", []):
		if String(f.get("t", "")) == "extrude":
			return true
	return false

## FWRENCH2: a JAW SLOT. A floor shape (on the top plane) that lies inside one solid's width and runs past one of its ends (or the other way round)
## cuts that solid when pulled. Only when the trial cut lowers the volume, leaves one solid and no error; else the Pull joins as before
func _slot_cut(rec: Dictionary, sk: Dictionary, dist: float) -> bool:
	var res := Part.replay(rec)
	if int(res["bodies"]) != 1:
		return false
	var bb: AABB = res["aabb"]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var pl := Part.plane("top")
	for e in sk["ents"]:
		for q in _ent_pts(e):
			var w := Part.to_world(pl, Part.v2(q))
			lo = lo.min(Vector2(w.x, w.z))
			hi = hi.max(Vector2(w.x, w.z))
	if lo.x == INF:
		return false
	var eps := 0.5 * Part.MM
	var x0 := bb.position.x - eps
	var x1 := bb.end.x + eps
	var z0 := bb.position.z - eps
	var z1 := bb.end.z + eps
	# FWRENCH3: a slot is INSIDE the solid's width, so it must keep clear of both sides (a strip that spans the floor's full depth is a WALL on the edge, not a jaw: the froom wall B)
	var in_z := lo.y > bb.position.z + eps and hi.y < bb.end.z - eps
	var in_x := lo.x > bb.position.x + eps and hi.x < bb.end.x - eps
	var past_x := (lo.x < x0 or hi.x > x1) and hi.x > x0 and lo.x < x1   # runs past an end along x, and overlaps the solid
	var past_z := (lo.y < z0 or hi.y > z1) and hi.y > z0 and lo.y < z1
	# FWRENCH4: a slot must go DEEP into the solid (a third of its length inside it). A box that mostly sticks OUT past an end and only
	# clips the edge (the glasses arm at the ring's outer edge) is a pull that goes out: it adds, it does not cut
	var reach_x := (minf(hi.x, bb.end.x) - maxf(lo.x, bb.position.x)) / maxf(hi.x - lo.x, 1e-9)
	var reach_z := (minf(hi.y, bb.end.z) - maxf(lo.y, bb.position.z)) / maxf(hi.y - lo.y, 1e-9)
	var deep_x := in_z and past_x and reach_x >= 1.0 / 3.0
	var deep_z := in_x and past_z and reach_z >= 1.0 / 3.0
	if not (deep_x or deep_z):
		return false
	var v0 := float(res["volume"])
	var trial := rec.duplicate(true)
	var f := Part.new_feature(trial, "extrude", {"sketch": sk["id"], "dist": dist, "both": false, "op": "cut"})
	trial["features"].append(f)
	var r2 := Part.replay(trial)
	var v1 := float(r2["volume"])
	return String(r2["errors"].get(f["id"], "")) == "" and int(r2["bodies"]) == 1 and v1 > 0.0 and v1 < v0 - 1e-12


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


## FBOX2: the newest solid step is a LID: a pull with op "new" on a hollow box (the lid is its own piece)
func _lid_last(rec: Dictionary) -> bool:
	if not _has_shell(rec):
		return false
	var last := {}
	for f in rec.get("features", []):
		if String(f.get("t", "")) == "extrude":
			last = f
	return not last.is_empty() and String(last.get("op", "")) == "new"


## FBOX: the record has a shell (Hollow inside) step: a hollow body whose top is open
func _has_shell(rec: Dictionary) -> bool:
	for f in rec.get("features", []):
		if String(f.get("t", "")) == "shell":
			return true
	return false


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
	if axis == "y" and _past_axis(sk) < -3.0 and _past_axis(sk) >= -CLIP_MM:
		_clip_axis(sk)   # FBOWL2: a spline's overshoot past the middle line (a bowl's foot corner) is clipped onto it, not refused
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


## FBOWL2: a curve drawn through corner points (a salad bowl's foot) overshoots the middle line by a few mm between its points: the curve
## is sampled, the part past the middle line is set to x = 0 (a flat piece on the axis), and the sketch keeps the sampled points
func _clip_axis(sk: Dictionary) -> void:
	for e in sk["ents"]:
		if String(e["k"]) != "bspline":
			continue
		var closed := bool(e.get("closed", false))
		var dense := Part.spline_curve(e.get("pts", []), closed, 16)
		var out := []
		for q in dense:
			out.append([maxf(q.x, 0.0), q.y])
		if closed and out.size() > 1:
			out.pop_back()   # the sample ends on the first point again: the closed line keeps one of them
		e["pts"] = out


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
	# FSPOON: the edges and the kept solid come from ONE replay (each replay of a part with a hollow or a blend is seconds)
	var res := Part.replay(rec, -1, {"edges": true, "keep": true})
	var kept: Array = res.get("ids", [])
	if int(res["bodies"]) == 0:
		Part.release_kept(kept)
		return "Nothing solid to round yet. Press Pull it up first"
	var es: Array = res["edges"]
	var aabb: AABB = res["aabb"]
	var flag := "" if round_mode == "all" else round_mode   # NROUNDFILTER: the edge flag of the filter ("outside" / "top")
	if flag != "":
		var any := false
		for e in es:
			if int(e["body"]) == 0 and not bool(e.get("seam", false)) and bool(e.get(flag, false)):
				any = true
		if not any:
			Part.release_kept(kept)
			return "No %s edge to round on this solid: press All edges, then Round the edges again" % ("outside" if flag == "outside" else "top")
	var small := minf(aabb.size.x, minf(aabb.size.y, aabb.size.z)) / Part.MM
	var longest := 0.0
	for e in es:
		longest = maxf(longest, float(e["len"]))
	# EROUND: the edges are tried on ONE kept replay of the body as it is before the round (a kernel fillet per try), not a replay of the whole
	# record per try: a press on a part of 25+ steps took minutes that way. The search stops at ROUND_BUDGET_US and keeps the best found
	var done := false
	if not kept.is_empty():
		done = _round_on(rec, int(kept[0]), es, small, longest, flag)
	Part.release_kept(kept)
	if done:
		return ""
	return "These edges are too small or too crowded to round: Pull it up taller, then press Round the edges again"


## EROUND: the round on body (a kept solid of the record's end). True when a fillet step was added to rec
func _round_on(rec: Dictionary, body: int, es: Array, small: float, longest: float, flag := "") -> bool:
	# EBACK: the default never sits below the slider's own low end (1 mm, "Barely"): a thin part's 0.5 mm default looked square
	for attempt in [[1.0, 0.0], [0.5, 0.0], [0.5, 0.2]]:
		var r := clampf(small * 0.01 * float(attempt[0]), 1.0, 6.0)
		var list := []
		for e in es:
			if int(e["body"]) == 0 and not bool(e.get("seam", false)) and (flag == "" or bool(e.get(flag, false))) and float(e["len"]) >= longest * float(attempt[1]) and float(e["len"]) / Part.MM > r * 2.5:
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
			if int(e["body"]) == 0 and not bool(e.get("seam", false)) and (flag == "" or bool(e.get(flag, false))) and float(e["len"]) / Part.MM > r * 2.5:
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
	if _lid_last(rec):   # FBOX2: a lid on a hollow box: the finger notch at its edge (before the piece hole: the lid is the newest piece)
		return _lid_notch(rec, res["aabb"])
	if _piece_hole(rec):   # the newest piece is an upright or a face sketch: the hole goes through IT
		return ""
	var bb: AABB = res["aabb"]
	var c := bb.get_center() / Part.MM
	var floor_made := _base_plane(rec, _newest_sketch_plane(rec)) == "top"   # a body drawn on the floor is cut DOWN through (its hole runs up/down)
	var r := clampf(minf(bb.size.x, bb.size.z if floor_made else bb.size.y) / Part.MM * 0.12, 10.0, 40.0)   # the radius in mm: a hole 2 to 8 cm across
	var cen := Vector2(c.x, -c.z) if floor_made else Vector2(c.x, c.y)   # the hole's middle on the sketch plane
	if m != null and m.S != null and m.S.kind == "building":   # FROOM: on a building the hole goes through the middle of the newest piece (a wall gets its hole in the wall), not the middle of the whole room
		var ls := _last_sketch(rec)
		var pts := _sketch_pts(ls)
		if not pts.is_empty():
			var lo: Vector2 = pts[0]
			var hi: Vector2 = pts[0]
			for q in pts:
				lo = lo.min(q)
				hi = hi.max(q)
			cen = (lo + hi) * 0.5
	var s: Dictionary
	var f: Dictionary
	# FBRACKET: the middle first; when the middle already has a hole, the next press cuts to the side, along the body's two long
	# sketch axes (30% of the span each way), and the first side spot that takes material wins
	var had_cut := _has_cut(rec)
	var mid := Vector2(c.x, -c.z) if floor_made else Vector2(c.x, c.y)   # the middle of the whole body (the top plane's v axis is -Z)
	var span := Vector2(bb.size.x, bb.size.z if floor_made else bb.size.y) / Part.MM
	var spots: Array = [cen]   # FROOM: the newest piece's middle first; the whole body's middle when that cut takes everything
	if not spots.has(mid):
		spots.append(mid)
	if had_cut:
		spots += [mid + Vector2(0.3 * span.x, 0.0), mid - Vector2(0.3 * span.x, 0.0), mid + Vector2(0.0, 0.3 * span.y), mid - Vector2(0.0, 0.3 * span.y)]
	var before := float(res["volume"])
	var n0: int = rec["features"].size()
	var seq0 := int(rec.get("seq", 0))
	var after := before
	for at in spots:
		rec["features"].resize(n0)   # the spot before this one takes nothing: its sketch and cut go out
		rec["seq"] = seq0
		# "both" splits dist half each way from the sketch plane: twice the body's farthest reach + 1 cm, so a tall body is cut all the way
		if floor_made:
			s = Part.new_feature(rec, "sketch", {"plane": "top", "ents": [{"k": "circle", "c": Part.arr2(at), "r": snappedf(r, 0.5)}], "dims": []})
			rec["features"].append(s)
			f = Part.new_feature(rec, "extrude", {"sketch": s["id"], "dist": snappedf(2.0 * (maxf(absf(bb.position.y), absf(bb.end.y)) / Part.MM + 10.0), 1.0), "both": true, "op": "cut"})
		else:
			s = Part.new_feature(rec, "sketch", {"plane": "front", "ents": [{"k": "circle", "c": Part.arr2(at), "r": snappedf(r, 0.5)}], "dims": []})
			rec["features"].append(s)
			f = Part.new_feature(rec, "extrude", {"sketch": s["id"], "dist": snappedf(2.0 * (maxf(absf(bb.position.z), absf(bb.end.z)) / Part.MM + 10.0), 1.0), "both": true, "op": "cut"})
		rec["features"].append(f)
		after = float(pu.replay_full(rec)["volume"])
		if after < before - 1e-12 and after > 1e-9:   # a cut that takes EVERYTHING is a failed cut (the kernel gave nothing back): try the next spot
			break
	if not (after < before - 1e-12 and after > 1e-9):
		rec["features"].resize(n0)
		rec["seq"] = seq0
		if had_cut:
			return "The middle already has a hole, and Cut a hole always cuts the middle. For a second hole, use Expert: Circle, then Cut"
		return "The hole would miss the shape: nothing was cut"
	tweak = {"id": s["id"], "ent": 0, "field": "r", "label": "Hole size", "unit": "cm", "lo": 0.6, "hi": 16.0, "step": 0.1, "scale": 5.0, "words": ["Smaller", "Bigger"]}   # the slider is the hole's WIDTH (cm): radius mm = width cm * 5
	if had_cut:
		_say("The middle already has a hole, so this one is cut to the side. For exact places, use Expert: Circle, then Cut")
	else:
		_say("A hole straight through: use the slider for its size, or press Mirror that or Repeat it next")
	return ""


## FBOX2: a LID (a separate piece on the rim of a hollow box) gets a FINGER NOTCH: a 16 mm half-circle bite at the middle of its +Z edge,
## cut straight through on the top plane. The lid's corners stay, so its outline is kept, and the notch stays clear of the box wall
func _lid_notch(rec: Dictionary, bb: AABB) -> String:
	var c := bb.get_center() / Part.MM
	var before := float(Part.replay(rec)["volume"])
	var s := Part.new_feature(rec, "sketch", {"plane": "top", "ents": [{"k": "circle", "c": Part.arr2(Vector2(c.x, -bb.end.z / Part.MM)), "r": 8.0}], "dims": []})
	rec["features"].append(s)
	var f := Part.new_feature(rec, "extrude", {"sketch": s["id"], "dist": snappedf(2.0 * (maxf(absf(bb.position.y), absf(bb.end.y)) / Part.MM + 10.0), 1.0), "both": true, "op": "cut"})
	rec["features"].append(f)
	var after := float(pu.replay_full(rec)["volume"])
	if after >= before - 1e-12:
		return "The notch would miss the lid: nothing was cut"
	tweak = {"id": s["id"], "ent": 0, "field": "r", "label": "Notch size", "unit": "cm", "lo": 0.6, "hi": 16.0, "step": 0.1, "scale": 5.0, "words": ["Smaller", "Bigger"]}
	_say("A finger notch at the lid's edge: use the slider for its size, or press Mirror that next")
	return ""


## FROOM: the newest sketch step of a record ({} when none)
func _last_sketch(rec: Dictionary) -> Dictionary:
	var out := {}
	for f in rec.get("features", []):
		if f["t"] == "sketch":
			out = f
	return out


## FROOM: the corner and centre points of a sketch's shapes (sketch units), [] for none
func _sketch_pts(sk: Dictionary) -> Array:
	var out := []
	for e in sk.get("ents", []):
		for k in ["a", "b", "c"]:
			if e.has(k):
				out.append(Vector2(float(e[k][0]), float(e[k][1])))
	return out
## a cut step (an Extrude with op cut) is already in the record: the middle or a side has a hole
func _has_cut(rec: Dictionary) -> bool:
	for pf in rec.get("features", []):
		if String(pf.get("t", "")) == "extrude" and String(pf.get("op", "")) == "cut":
			return true
	return false


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
	_say("A hole through: use the slider for how deep, then press Mirror that or Repeat it next")
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
	if _hole_last(rec):   # MSIGN: a hole is the newest step: its copy is cut on the other side (a join copy would fill the hole back in)
		var why_h := _mirror_hole(rec, res, off)
		if why_h == "":
			tweak = {}
			_say("Mirrored across the middle line: the hole is copied to the other side")
		return why_h
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


## MSIGN: the newest step is a cut through a shape drawn on a face (a hole, a window): Mirror that copies the hole
func _hole_last(rec: Dictionary) -> bool:
	var feats: Array = rec.get("features", [])
	if feats.is_empty():
		return false
	var cut: Dictionary = feats[feats.size() - 1]
	if String(cut["t"]) != "extrude" or String(cut.get("op", "")) != "cut":
		return false
	var sk := Part.feature(rec, String(cut.get("sketch", "")))
	if sk.is_empty():
		return false
	var pf := Part.feature(rec, String(sk.get("plane", "")))   # only a hole drawn ON A FACE (a plane with "out"): a centre hole keeps the join copy
	if String(pf.get("t", "")) != "plane" or not pf.has("out"):
		return false
	return absf((Part.resolve_plane(rec, String(sk.get("plane", "")))["n"] as Vector3).x) < 0.0001


## MSIGN: the same hole cut again, its sketch reflected across the middle line (x = mid, the same middle the join mirror uses)
func _mirror_hole(rec: Dictionary, res: Dictionary, off: bool) -> String:
	var cut: Dictionary = rec["features"][rec["features"].size() - 1]
	var sk := Part.feature(rec, String(cut["sketch"]))
	var pl := Part.resolve_plane(rec, String(sk["plane"]))
	var bb: AABB = res["aabb"]
	var mid := (bb.position.x + bb.end.x) * 0.5 if off else 0.0
	var o: Vector3 = pl["o"]
	var px: Vector3 = pl["x"]
	var py: Vector3 = pl["y"]
	var ents := []
	for e in sk.get("ents", []):
		var ne: Dictionary = e.duplicate(true)
		for k in ["a", "b", "c"]:
			if e.has(k):
				var w := o + px * float(e[k][0]) * Part.MM + py * float(e[k][1]) * Part.MM
				w.x = 2.0 * mid - w.x
				var d := w - o
				ne[k] = Part.arr2(Vector2(d.dot(px) / Part.MM, d.dot(py) / Part.MM))
		ents.append(ne)
	var fields: Dictionary = sk.duplicate(true)
	for k in ["t", "id", "name"]:
		fields.erase(k)
	fields["ents"] = ents
	var s := Part.new_feature(rec, "sketch", fields)
	rec["features"].append(s)
	var f := Part.new_feature(rec, "extrude", {"sketch": s["id"], "dist": cut["dist"], "both": bool(cut.get("both", false)), "op": "cut"})
	rec["features"].append(f)
	if _last_error(rec, String(f["id"])) != "":
		return "That hole cannot be copied"
	if float(pu.replay_full(rec)["volume"]) >= float(res["volume"]) - 1e-12:
		return "The copy would miss the solid: nothing was cut"
	return ""


## BLEND TWO SHAPES: a loft of the two last sketches (Part's "loft" feature, the same one Expert's Loft makes). Two shapes on the same plane
## cannot be blended, so the newer one moves 40 mm behind the older one (an offset plane, in the same undo step)
## FPHONE: the base plane (front | top | right) a sketch's plane id sits on, a plane feature or a base plane itself
func _plane_base(rec: Dictionary, pid: String) -> String:
	return pid if pid in Part.PLANES else _base_plane(rec, pid)


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
	# FPHONE: a shape on the top of a solid (its plane sits at the top's height) and a shape on the floor of the same base plane: the newer
	# one still goes 40 mm above the older one (the same offset rule), not down to the floor (the back of a phone stand leans up off its plate)
	if not same and (pa["n"] as Vector3).dot(pb["n"] as Vector3) > 0.999 and _plane_base(rec, String(a["plane"])) == _plane_base(rec, String(b["plane"])):
		same = true
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


## COLOUR: one appear step on the newest body (Part's "appear" feature, the look Expert's Appearance writes), in ONE undo step. A material
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
	# FLAMP: a colour chip paints the solids no chip has coloured yet (a new arm or shade; a lamp: base red, arm blue, shade yellow);
	# when all are coloured, the newest one. Glass and Metal paint every solid (each keeps its own colour)
	var chipped := {}
	for of in rec.get("features", []):
		if String(of.get("t", "")) == "appear" and not COLOUR_PRESETS.has(String(of.get("preset", ""))):
			chipped[int(of.get("body", -1))] = true
	var targets: Array = range(nb)
	if not COLOUR_PRESETS.has(preset):
		targets = []
		for i in nb:
			if not chipped.has(i):
				targets.append(i)
		if targets.is_empty():
			targets = [nb - 1]
	for i in targets:
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


## FDUP: Duplicate: a second copy of the WHOLE part beside it (not Repeat's row of the newest solid). One Part pattern step per body, each with
## two copies and op "new": every body is copied by the same move, the whole part's width plus a 10 mm gap, so the copy sits beside all of it
func _duplicate(rec: Dictionary) -> String:
	var res := Part.replay(rec)
	var nb := int(res["bodies"])
	if nb == 0:
		return "Make something solid first, then duplicate it"
	var bb: AABB = res["aabb"]
	var gap := 10.0
	var step_mm := maxf(bb.size.x / Part.MM, 1.0) + gap
	for bi in nb:
		var f := Part.new_feature(rec, "pattern", {"kind": "linear", "body": bi, "count": 2, "dir": "x", "axis": "y", "deg": 360.0,
			"mm": step_mm, "w": bb.size.x / Part.MM, "h": bb.size.y / Part.MM, "d": bb.size.z / Part.MM, "gap": gap, "op": "new"})
		rec["features"].append(f)
		if _last_error(rec, String(f["id"])) != "":
			return "The copy would not fit: nothing was changed"
	tweak = {}
	_say("Duplicated: a second copy of the whole part sits beside it. Undo takes the copy back")
	return ""


## REPEAT IT: Part's pattern step (Expert Pattern) on the newest solid: a row along X, spacing = the body's width + a 1 cm gap
func _repeat(rec: Dictionary) -> String:
	var fs: Array = rec.get("features", [])
	if not fs.is_empty() and String(fs[-1].get("t", "")) == "extrude" and String(fs[-1].get("op", "")) == "cut" and not bool(fs[-1].get("off", false)):
		return _repeat_cut(rec, fs[-1])   # FRULER: the newest step is a cut (a slot or hole): the row copies the cut, not the body
	var res := Part.replay(rec)
	var nb := int(res["bodies"])
	if nb == 0:
		return "Make something solid first, then repeat it"
	var bi := nb - 1
	var w_mm := 10.0
	var h_mm := 10.0   # EREPEATUP: the body's height and depth too, so Up and Forward space the copies by their own size
	var d_mm := 10.0
	var src := Part.pattern_piece(rec)   # REPEAT THE PIECE: the newest piece (its own size) when it is the newest step, else the whole body
	var mrec: Dictionary = Part.pattern_src_rec(rec, src) if src != "" else rec
	var mbi := -1 if src != "" else bi
	var faces := Part.body_faces(mrec, -1)
	if mbi < 0:
		mbi = faces.size() - 1
	if mbi >= 0 and mbi < faces.size() and (faces[mbi] as PackedVector3Array).size() > 0:
		var pts: PackedVector3Array = faces[mbi]
		var bb := AABB(pts[0], Vector3.ZERO)
		for q in pts:
			bb = bb.expand(q)
		w_mm = maxf(bb.size.x / Part.MM, 1.0)
		h_mm = maxf(bb.size.y / Part.MM, 1.0)
		d_mm = maxf(bb.size.z / Part.MM, 1.0)
	var fields := {"kind": "linear", "body": bi, "count": 3, "dir": "x", "axis": "y", "deg": 360.0,
		"mm": w_mm + 10.0, "w": w_mm, "h": h_mm, "d": d_mm, "gap": 10.0, "op": "join"}
	if src != "":
		fields["src"] = src
	var f := Part.new_feature(rec, "pattern", fields)
	rec["features"].append(f)
	if _last_error(rec, String(f["id"])) != "":
		return "The copies would not fit: nothing was changed"
	rep_id = String(f["id"])
	tweak = {}
	_say("Repeated in a row: move the sliders for how many and the gap, or pick Up, Forward or Ring")
	return ""


## FRULER: Repeat it on a newest cut: a Row pattern step over that cut (Part _cut_row replays the copies). The spacing = the cut's width + the gap
func _repeat_cut(rec: Dictionary, ext: Dictionary) -> String:
	var sk := Part.feature(rec, String(ext.get("sketch", "")))
	if sk.is_empty():
		return "Draw the cut first, then repeat it"
	var lo := INF
	var hi := -INF
	for e in sk.get("ents", []):
		for k in ["a", "b"]:
			if e.has(k):
				lo = minf(lo, float(e[k][0]))
				hi = maxf(hi, float(e[k][0]))
		if e.has("c"):
			lo = minf(lo, float(e["c"][0]) - float(e.get("r", 0.0)))
			hi = maxf(hi, float(e["c"][0]) + float(e.get("r", 0.0)))
	if lo == INF or hi - lo < 1e-6:
		return "Draw the cut first, then repeat it"
	var w_mm := hi - lo
	var nb := int(Part.replay(rec)["bodies"])
	var f := Part.new_feature(rec, "pattern", {"kind": "linear", "body": maxi(nb - 1, 0), "count": 3, "dir": "x", "axis": "y", "deg": 360.0,
		"mm": w_mm + 10.0, "w": w_mm, "h": 10.0, "d": 10.0, "gap": 10.0, "op": "cut", "sketch": sk["id"], "dist": float(ext.get("dist", -10.0)), "both": bool(ext.get("both", false))})
	rec["features"].append(f)
	if _last_error(rec, String(f["id"])) != "":
		return "The copies would not fit: nothing was changed"
	rep_id = String(f["id"])
	tweak = {}
	_say("Repeated in a row: move the sliders for how many and the gap")
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
	if not ring and String(cur.get("dir", "x")) != "x":   # FBENCH: back from Forward or Up: the spacing is the piece's width ALONG X
		var wx := _feat_mm(cur, "x")
		if wx > 0.0:
			cur["w"] = wx
	cur["dir"] = "x"
	cur["mm"] = _span(cur) + float(cur.get("gap", 10.0))
	_end()
	pu.sync()
	_rep_sync()
	_values_sync()
	_say("Ring: the copies go round in a circle" if ring else "Row: the copies go in a straight line")   # FWHEEL: "beside it" lied for a spoke (its copies go round the middle)


## EREPEATUP + FBENCH: Up or Forward: the same straight copies, stacked up (y) or put one behind the other (z); spaced by the body's
## height or depth (its real size, measured from the body; the feature's size when the body is not there) plus the gap. One undo step
func _rep_dir(ax: String) -> void:
	if Part.feature(_rec(), rep_id).is_empty():
		return
	_flush_if_dirty()
	_begin("Up" if ax == "y" else ("Forward" if ax == "z" else "Row"))
	var cur := Part.feature(_rec(), rep_id)
	cur["kind"] = "linear"
	cur["beside"] = false
	cur["axis"] = "y"
	cur["deg"] = 360.0
	cur["dir"] = ax
	var sp := _feat_mm(cur, ax)
	cur["mm"] = (sp if sp > 0.0 else _span(cur)) + float(cur.get("gap", 10.0))
	_end()
	pu.sync()
	_rep_sync()
	_values_sync()
	_say("Up: the copies stack upward, one on top of the other" if ax == "y" else ("Forward: the copies go one behind the other" if ax == "z" else "Row: the copies go sideways in a straight line"))


## FBENCH: the size of the copied piece of a Repeat step along one way ("x" | "y" | "z") in mm; -1 when it is not there (the caller falls back)
func _feat_mm(cur: Dictionary, dir: String) -> float:
	var src := String(cur.get("src", ""))
	if src != "":
		var sub := Part.pattern_src_rec(_rec(), src)
		if not sub.is_empty():
			return _piece_mm(sub, -1, dir)
	return _piece_mm(_rec(), int(cur.get("body", -1)), dir)


## FBENCH: the size of body bi along one way ("x" | "y" | "z") in mm (bi -1: the last body); -1 when the body is not there (the caller falls back to the feature's size)
func _piece_mm(rec: Dictionary, bi: int, dir: String) -> float:
	var faces := Part.body_faces(rec, -1)
	if bi < 0:
		bi = faces.size() - 1
	if bi < 0 or bi >= faces.size() or (faces[bi] as PackedVector3Array).size() == 0:
		return -1.0
	var pts: PackedVector3Array = faces[bi]
	var bb := AABB(pts[0], Vector3.ZERO)
	for q in pts:
		bb = bb.expand(q)
	var s := bb.size
	var n := s.x if dir == "x" else (s.y if dir == "y" else s.z)
	return maxf(n / Part.MM, 1.0)


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
	# the same test as the gap under 0.05 mm (tris_touch finds it without the full pair scan: a Join of two big pieces froze the app)
	if not Part.tris_touch(before[int(picked[0])], before[int(picked[1])], 0.00005):
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
	var lin := String(f.get("kind", "linear")) == "linear"
	(rep_btns["row"] as Button).set_pressed_no_signal(lin and String(f.get("dir", "x")) == "x")
	(rep_btns["up"] as Button).set_pressed_no_signal(lin and String(f.get("dir", "x")) == "y")
	(rep_btns["forward"] as Button).set_pressed_no_signal(lin and String(f.get("dir", "x")) == "z")
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
	round_box.visible = on and _round_shown()   # NROUNDFILTER
	if round_box.visible:
		_round_sync()
	if split_box.visible:
		_split_sync()
	colour_box.visible = on and armed == "colour"
	repeat_box.visible = on and armed == "" and rep_id != "" and not Part.feature(_rec(), rep_id).is_empty()
	stick_box.visible = on and armed == "stick" and stick_picks.size() == 2
	if del_on and (armed != "" or (_rec().get("features", []) as Array).size() != del_n):
		_pick_clear()   # FDELETE: a pick ends with the step it was made on
	del_btn.visible = on and del_on
	tilt_box.visible = on and armed == "" and _tilt_ok(_rec())
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
	_size_sync()
	_frame_step()


## FMEASURE: the part's size in cm, W x D x H (wide, deep, high), a small plain label under the part's front bottom edge.
## Shown while a solid is made (Easy Part only); the numbers are the replayed box (metres -> cm, one decimal).
func _size_sync() -> void:
	var res: Dictionary = pu.res if pu != null else {}
	var bb: AABB = res.get("aabb", AABB())
	var solid := active() and int(res.get("bodies", 0)) > 0 and bb.size.x > 0.0 and bb.size.y > 0.0 and bb.size.z > 0.0
	size_l.visible = solid
	if not solid or m.cam == null:
		return
	var w := snappedf(bb.size.x * 100.0, 0.1)
	var d := snappedf(bb.size.z * 100.0, 0.1)
	var h := snappedf(bb.size.y * 100.0, 0.1)
	size_l.text = "Size: %s x %s x %s cm (wide x deep x high)" % [_cm1(w), _cm1(d), _cm1(h)]
	var front := Vector3(bb.get_center().x, bb.position.y, bb.end.z)
	if m.cam.is_position_behind(front):
		size_l.visible = false
		return
	var p: Vector2 = m.cam.unproject_position(front)
	var sz := size_l.get_combined_minimum_size()
	size_l.size = sz
	# FMOBILE: the label stays on the window (a part low on a short window pushed it off the bottom) and hides rather than sit on a box or panel
	var vp := get_viewport().get_visible_rect()
	var pos := Vector2(clampf(p.x - sz.x * 0.5, 4.0, vp.end.x - sz.x - 4.0), minf(p.y + 12.0, vp.end.y - sz.y - 4.0))
	size_l.position = pos
	var r := Rect2(size_l.get_global_position(), sz)
	for bx in [panel, repeat_box, stick_box, colour_box, hint, status]:
		var c := bx as Control
		if c != null and c.is_visible_in_tree() and r.intersects(c.get_global_rect()):
			size_l.visible = false
			return


func _cm1(v: float) -> String:
	return str(roundi(v)) if absf(v - roundf(v)) < 0.05 else str(v)


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
	var lk := str(repeat_box.visible)   # EPANELVIEW: a Repeat it box opening or closing changes the free view: frame again (not Stick together: its picks need a still view)
	if lk != _fr_lk:
		_fr_lk = lk
		_fr_ref = AABB()
		ref_len = 0.0
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
	var boxes := [hint, hole_box, split_box, round_box, shape_box, colour_box, repeat_box, stick_box]   # the words and the chip rows under the MAKE row: the part sits below them
	var top := _free_top(boxes)                                                              # (ewalk4: the Through / Hollow inside chips covered the mug's rim)
	# FSHELF: the Repeat row sits at the left under the words; open, its bottom left the free view under 0 px high (no framing, the copies
	# of a row stayed off screen). When that happens the row does not push the view down (it floats over the left of the grid)
	if _cl.end.y - 70.0 - top < 120.0:
		top = _free_top(boxes.filter(func(c): return c != repeat_box))
	var x0 := _cl.position.x + 12.0
	var x1 := _cl.end.x - PW - 16.0
	# EPANELVIEW: an open Repeat it box at the lower left takes its columns out of the free view (the part is framed to its right)
	if repeat_box.visible and repeat_box.position.y < _cl.end.y - 70.0 and repeat_box.position.y + repeat_box.size.y > top:
		x0 = maxf(x0, repeat_box.position.x + repeat_box.size.x + 8.0)
	return Rect2(x0, top, x1 - x0, _cl.end.y - 70.0 - top)


## the top edge of the free view: under the MAKE row and under each visible panel in boxes
func _free_top(boxes: Array) -> float:
	var top := _cl.position.y + 4.0 + MAKE_H + 8.0
	for c in boxes:
		if c != null and (c as Control).visible:
			top = maxf(top, (c as Control).get_global_rect().end.y + 8.0)
	return top


## FBOLT: a Draw shape press finishes a camera ease that is still running, so the view is where it lands before the next press
func _ease_end() -> void:
	if _ease.is_empty() or m.cam == null:
		return
	m.target = _ease["t1"]
	m.dist = float(_ease["d1"])
	m._cam()
	_ease = {}


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
		text = "Press Draw shape, then drag on the grid (or pick a template on the right)"   # FKEY: a beginner sees the verb first, not a shape that is not there
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


## FMOBILE: a bottom-left box's top: its usual place, never above the sentence under the hint, and above the one sentence at the bottom when the room allows
static func _low_box_y(want: float, h: float, low_y: float, stat_top: float) -> float:
	return clampf(want, low_y, maxf(low_y, stat_top - h))


## the layout, from PartUI.layout(cl): the clear view's rectangle
func layout(cl: Rect2) -> void:
	if not active():
		return
	_cl = cl
	var w := cl.size.x - 16.0
	var narrow := get_viewport().get_visible_rect().size.x < NARROW_W   # FMOBILE: at 1024 wide the bar row is wider than the window: its buttons shrink, the title shortens
	use_scene_btn.custom_minimum_size.x = 96.0 if narrow else 150.0
	var tight := get_viewport().get_visible_rect().size.x < 1300.0   # FMOBILE5: 1280 wide, the bar row (What to build at its end) needs the short words at 72 px
	for sb in [undo_btn, redo_btn, easy_btn, expert_btn]:
		(sb as Button).custom_minimum_size.x = 72.0 if tight else 96.0
	give_btn.custom_minimum_size.x = 110.0 if narrow else 170.0
	dup_btn.custom_minimum_size.x = 92.0 if narrow else 120.0   # FMOBILE2: 1024 wide, the bar row (with What to build at its end) must fit the window
	if bar_home != null:
		bar_home.custom_minimum_size.x = 88.0 if narrow else 110.0
	if pu != null and pu.reopen_btn != null:
		pu.reopen_btn.add_theme_font_size_override("font_size", 14 if narrow else 16)
	# FMOBILE: at 1024 wide the Repeat it row (Row Up Forward Ring Corners) is narrower, so it fits left of the panel instead of under it
	for rb in rep_btns.values():
		(rb as Button).custom_minimum_size.x = 92.0 if narrow else 110.0
	export_btn.custom_minimum_size.x = 84.0 if narrow else 110.0
	title_l.clip_text = narrow
	title_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if narrow else TextServer.OVERRUN_NO_TRIMMING
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
	round_box.reset_size()   # NROUNDFILTER: the filter chips sit where the other chip rows do
	round_box.position = shape_box.position
	colour_box.reset_size()
	colour_box.position = shape_box.position
	# FMOBILE: the floating boxes stay left of the panel (the colour chips wrap) and below the sentence (the hint)
	var room := cl.end.x - PW - 32.0 - colour_box.position.x
	var nat := 24.0   # the chips in one row (their own widths and the gaps): the box is only as wide as its chips when the room is wide
	for c in (colour_box.get_child(0) as Control).get_children():
		nat += (c as Control).get_combined_minimum_size().x + 6.0
	colour_box.size.x = minf(room, nat)
	colour_box.size.y = colour_box.get_combined_minimum_size().y
	# the Repeat it and Stick together rows sit at the lower left, above the one sentence, off the model's pieces (and never over the sentence)
	var low_y := hint.position.y + hint.size.y + 6.0
	var stat_top := cl.end.y - status.get_combined_minimum_size().y - 12.0   # the one sentence at the bottom-left: the boxes end above it
	# a short window: the Fewer / More words under the Repeat it sliders go first, so the box fits between the sentence and the one line at the bottom
	# (hysteresis: the words toggle only when the box crosses the room, never every frame)
	if not rep_rows.is_empty():
		var room_h := stat_top - low_y - 4.0
		var words_on := bool((rep_rows[0]["words"] as Control).visible)
		var wh := float((rep_rows[0]["words"] as Control).get_combined_minimum_size().y) + 4.0
		repeat_box.reset_size()
		var h_now := repeat_box.get_combined_minimum_size().y
		var want_on := (h_now + wh) <= room_h if not words_on else h_now <= room_h
		if want_on != words_on:
			for r in rep_rows:
				(r["words"] as Control).visible = want_on
	repeat_box.reset_size()
	repeat_box.position = Vector2(cl.position.x + 12.0, _low_box_y(cl.end.y - repeat_box.size.y - 64.0, repeat_box.size.y, low_y, stat_top))
	stick_box.reset_size()
	stick_box.position = Vector2(cl.position.x + 12.0, _low_box_y(cl.end.y - stick_box.size.y - 64.0, stick_box.size.y, low_y, stat_top))
	tilt_box.reset_size()
	var tilt_y := cl.end.y - tilt_box.size.y - 64.0
	if repeat_box.visible:   # FMOBILE5: Tilt it and Repeat it show together (nothing armed): Tilt sits above the Repeat rows, never over their sliders
		tilt_y = repeat_box.position.y - tilt_box.size.y - 6.0
	var tilt_x := cl.position.x + 12.0
	if repeat_box.visible and tilt_y < low_y:   # a short window: no room above the Repeat rows, so Tilt it stands beside them
		tilt_x = repeat_box.position.x + repeat_box.size.x + 8.0
		tilt_y = repeat_box.position.y + repeat_box.size.y - tilt_box.size.y
	tilt_box.position = Vector2(tilt_x, _low_box_y(tilt_y, tilt_box.size.y, low_y, stat_top))
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
	# FMOBILE: a short window: when a Repeat it / Stick together box would cover the one sentence, the sentence goes under the panel on the right
	var sbox := Rect2()
	for bx in [repeat_box, stick_box]:
		if (bx as Control).visible:
			sbox = sbox.merge(Rect2((bx as Control).position, (bx as Control).size))
	if sbox.size != Vector2.ZERO and Rect2(status.position, status.size).intersects(sbox):
		status.size.x = PW
		status.position = Vector2(panel.position.x, panel.position.y + panel.size.y + 8.0)


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
	if del_on:   # FDELETE: the picked piece glows red-amber
		for k in range(0, del_tris.size() - 2, 3):
			var q := _proj3(del_tris, k)
			if q.size() < 3 or absf((q[1] - q[0]).cross(q[2] - q[0])) < 0.5:
				continue
			dots.draw_colored_polygon(q, Color(1.0, 0.35, 0.2, 0.3))
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
	elif String(_draft["shape"]) == "hex" or String(_draft["shape"]) == "poly":
		for q in _poly_pts(a, b, _draft_sides()) + [a]:
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


## NPOLY2: the sides of the draft being drawn: a Sides shape its slider's count, a Hex 6
func _draft_sides() -> int:
	return sides if String(_draft.get("shape", "")) == "poly" else 6


## NPOLY2: the Sides row: the word Sides, a slider 3 to 12 (a click or a drag), and the count in words. Moving it picks the Sides shape
func _sides_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "easypart_sides_row"
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var sl_l := Label.new()
	sl_l.name = "easypart_sides_label"
	sl_l.text = "Sides"
	sl_l.add_theme_font_size_override("font_size", 16)
	row.add_child(sl_l)
	var sl := HSlider.new()
	sl.name = "easypart_sides"
	sl.min_value = 3
	sl.max_value = 12
	sl.step = 1
	sl.value = sides
	sl.focus_mode = Control.FOCUS_NONE
	sl.custom_minimum_size = Vector2(120, 40)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.tooltip_text = "Sides: how many sides the shape has (3 is a triangle, 6 a hexagon, 12 nearly round)"
	var tr := _style(Color(0.2, 0.21, 0.26), 4, 0)
	tr.content_margin_top = 4
	tr.content_margin_bottom = 4
	var fill := _style(AMBER, 4, 0)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	sl.add_theme_stylebox_override("slider", tr)
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill)
	var kn := _knob()
	sl.add_theme_icon_override("grabber", kn)
	sl.add_theme_icon_override("grabber_highlight", kn)
	row.add_child(sl)
	var rd := Label.new()
	rd.name = "easypart_sides_value"
	rd.add_theme_font_size_override("font_size", 16)
	rd.text = "%d sides" % sides
	row.add_child(rd)
	sl.value_changed.connect(func(v: float): sides = int(v); shape = "poly"; rd.text = "%d sides" % sides; _sync_shape())
	return row


## POLY: a regular polygon with `n` sides in the drag box: a vertex on the box's right, the rest round, centred on the box's middle. The box's width and height are the most it can reach (a Hex is the n = 6 case)
func _poly_pts(a: Vector2, b: Vector2, n: int) -> Array:
	if n == 6:
		return _hex_pts(a, b)
	var c := (a + b) * 0.5
	var mx := 0.0
	var my := 0.0
	for i in n:
		mx = maxf(mx, absf(cos(TAU * i / n)))
		my = maxf(my, absf(sin(TAU * i / n)))
	var r := minf(absf(b.x - a.x) * 0.5 / mx, absf(b.y - a.y) * 0.5 / my)
	var out := []
	for i in n:
		out.append(c + Vector2.from_angle(TAU * i / n) * r)
	return out


## HEX: a regular hexagon in the drag box, centred on its middle, flat top and bottom (the box's width is the corner-to-corner, its height the across-flats); the drag takes the smaller of the two sizes
func _hex_pts(a: Vector2, b: Vector2) -> Array:
	var c := (a + b) * 0.5
	var r := minf(absf(b.x - a.x) * 0.5, absf(b.y - a.y) * 0.5 / 0.8660254)
	var out := []
	for i in 6:
		out.append(c + Vector2.from_angle(PI / 3.0 * i) * r)
	return out


## the world point of a draft coordinate (the draft plane, else the FLOOR: the Part top plane, y = 0)
func _pw(q: Vector2) -> Vector3:
	return Part.to_world(_draft.get("pl", Part.plane("top")), q)


## DRAW ON A FACE: the flat face under a press, or {} (none, a curved face, or not within 5 deg of +-X, +-Y or +-Z).
## {"pl": the plane through the face, "base": "right"|"top"|"front", "mm": distance along the base normal, "out": +1 or -1 (the face normal side)}
func _face_hit(p: Vector2) -> Dictionary:
	var fc := _face_hit_at(p)
	if String(fc.get("base", "")) == "top":
		return fc
	# FBOX: a press on a wall's top edge within 2 mm of the solid's top (a rim 3 mm wide, seen from the far side) is the TOP face there (a lid on the rim)
	var top_m: float = (pu.res.get("aabb", AABB()) as AABB).end.y if pu != null else 0.0
	if top_m > 0.0 and fc.has("hit") and absf((fc["hit"] as Vector3).y - top_m) <= 0.002:
		var tp := Part.plane("top")
		tp["o"] = (tp["o"] as Vector3) + (tp["n"] as Vector3) * top_m
		return {"pl": tp, "base": "top", "mm": snappedf(top_m / Part.MM, 0.01), "out": 1}
	# a press on a solid's top edge or corner (a chair leg's corner, seen from the side) lands on the side face just below the top:
	# a tip-of-the-top press a few px higher takes the TOP face there, so a seat drawn on the leg tops sits on them
	for off in [Vector2(0.0, -6.0), Vector2(-6.0, -6.0), Vector2(6.0, -6.0)]:
		var up := _face_hit_at(p + off)
		if String(up.get("base", "")) == "top":
			return up
	# FBRACKET: a press that misses every face (a press on the FAR edge of a top face grazes it) is a press a few px lower,
	# which is inside the top face; without this the flange was drawn on the floor and came out beside the plate
	if fc.is_empty():
		for off in [Vector2(0.0, 6.0), Vector2(-6.0, 6.0), Vector2(6.0, 6.0)]:
			var dn := _face_hit_at(p + off)
			if String(dn.get("base", "")) == "top":
				return dn
	return fc


func _face_hit_at(p: Vector2) -> Dictionary:
	if not Part.available():
		return {}
	var faces: Array = _shown_faces()
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
	return {"pl": pl, "base": FACE_BASE[ax], "mm": mm, "out": out, "hit": bh}


## FSPOON: the triangles a press is tested against: the shown mesh of the last step's replay (a press costs no replay of a part
## with a hollow or a blend: each one is seconds). A step not yet shown (a slider edit still pending) replays the record as before
func _shown_faces() -> Array:
	var mesh: Variant = pu.res.get("mesh") if pu != null else null
	if not (mesh is ArrayMesh) or _dirty or (mesh as ArrayMesh).get_surface_count() == 0:
		return Part.body_faces(_rec(), -1)
	var tris := PackedVector3Array()
	var am := mesh as ArrayMesh
	for sf in am.get_surface_count():
		var arr := am.surface_get_arrays(sf)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx == null:
			tris.append_array(verts)
		else:
			for k in (idx as PackedInt32Array):
				tris.append(verts[k])
	return [tris]


const FACE_BASE := ["right", "top", "front"]   # the Part plane each axis is drawn on (+X, +Y, +Z)
const FACE_N := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]


## FSNAP: the corners of a box or pointy shape snap to the 1 cm grid (SNAP_MM); a curve keeps its 5 mm grid. Holding Alt (_alt) turns the snap off
const SNAP_MM := 10.0
var _alt := false        # Alt is held (the last mouse event said so, or the key is down): corners are free
var _snap_said := false  # the 1 cm snap words were said (once per session: the first drawn shape)


func _alt_held() -> bool:
	return _alt or Input.is_key_pressed(KEY_ALT)


func _snap_step() -> float:
	# a curve (a Curvy line or a Round circle) keeps the 5 mm grid; box, pointy and hex corners snap to 1 cm
	return 5.0 if (armed == "curve" or (armed == "draw" and shape == "round")) else SNAP_MM


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
	if not snap or _alt_held():
		return Vector2(q.x, q.y)
	var st := _snap_step()
	return Vector2(snappedf(q.x, st), snappedf(q.y, st))


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
		elif not _edge.is_empty():
			_edge_cancel()
			get_viewport().set_input_as_handled()
	elif k.keycode == KEY_DELETE and not k.ctrl_pressed and not k.alt_pressed:
		if del_on:
			_remove_piece()   # FDELETE: the picked piece goes (a click picked it)
		else:
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


## FDELETE: a click on a piece picks it (the glow shows it; Remove or the Delete key takes it out). A click on empty grid clears the pick.
## The piece is the step that first put the clicked surface in the solid: the first step whose result has that point on a face
func _pick_at(p: Vector2) -> void:
	_pick_clear()
	if _tpl() != "" or not _drag.is_empty() or not _draft.is_empty():
		return
	var rec := _rec()
	if (rec.get("features", []) as Array).is_empty():
		return
	var faces: Array = Part.body_faces(rec, -1)
	var hit: Dictionary = pu._ray_hit(p, faces)
	if hit.is_empty():
		return
	var pt: Vector3 = hit["at"]
	var fs: Array = rec["features"]
	for k in fs.size():
		var t := String(fs[k].get("t", ""))
		if t == "sketch" or t == "plane":
			continue   # a sketch or a face plane adds no surface
		if _pt_on(Part.body_faces(rec, k), pt):
			del_on = true
			del_id = String(fs[k].get("id", ""))
			del_n = fs.size()
			del_pt = pt
			del_tris = _lump_of(faces[int(hit["body"])], pt)   # the piece: the pieces that touch the point (a join of apart pieces is one body)
			dots.queue_redraw()
			_say("Picked a piece: press Remove to take it out. Undo puts it back")
			return
	_say("That piece has no step to take out")


func _pick_clear() -> void:
	del_on = false
	del_id = ""
	del_n = -1
	del_tris = PackedVector3Array()
	dots.queue_redraw()


## is the point on a triangle of the faces (within 0.05 mm; the faces are metres)
static func _pt_on(faces: Array, pt: Vector3) -> bool:
	for tris in faces:
		var t: PackedVector3Array = tris
		for k in range(0, t.size() - 2, 3):
			if _pt_on_tri(t[k], t[k + 1], t[k + 2], pt):
				return true
	return false


static func _pt_on_tri(a: Vector3, b: Vector3, c: Vector3, pt: Vector3) -> bool:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-18:
		return false
	n = n.normalized()
	if absf((pt - a).dot(n)) > 0.00005:
		return false
	var q := pt - n * (pt - a).dot(n)
	return (b - a).cross(q - a).dot(n) >= -0.00005 and (c - b).cross(q - b).dot(n) >= -0.00005 and (a - c).cross(q - c).dot(n) >= -0.00005


## the triangles of the piece that holds pt: the ones joined to the triangle under pt by shared corners (a join of apart pieces is one body)
static func _lump_of(tris: PackedVector3Array, pt: Vector3) -> PackedVector3Array:
	var nt := tris.size() / 3
	var by := {}
	for t in nt:
		for j in 3:
			var kk := Vector3i(roundi(tris[3 * t + j].x * 1e5), roundi(tris[3 * t + j].y * 1e5), roundi(tris[3 * t + j].z * 1e5))
			if not by.has(kk):
				by[kk] = []
			(by[kk] as Array).append(t)
	var start := -1
	for t in nt:
		if _pt_on_tri(tris[3 * t], tris[3 * t + 1], tris[3 * t + 2], pt):
			start = t
			break
	var out := PackedVector3Array()
	if start < 0:
		return out
	var seen := {start: true}
	var todo := [start]
	while not todo.is_empty():
		var t: int = todo.pop_back()
		for j in 3:
			var kk := Vector3i(roundi(tris[3 * t + j].x * 1e5), roundi(tris[3 * t + j].y * 1e5), roundi(tris[3 * t + j].z * 1e5))
			for u in by[kk]:
				if not seen.has(u):
					seen[u] = true
					todo.append(u)
	for t in seen.keys():
		out.append(tris[3 * int(t)])
		out.append(tris[3 * int(t) + 1])
		out.append(tris[3 * int(t) + 2])
	return out


## Remove: the picked piece's step goes out (and its sketch and face plane, if nothing else uses them), one undo step.
## A step after it that needs it keeps it: the part says so and nothing changes
## NFIXIT: Fix it: the first problem in the part is fixed in one press (one undo step); nothing wrong says so in words
func _fix_press() -> void:
	if not Part.available():
		_say(Part.why_not())
		return
	_flush_if_dirty()
	armed = ""
	var p := Part.find_problem(_rec())
	if p.is_empty():
		_say("Nothing to fix: every piece is joined and every step builds")
		return
	var snap := _rec().duplicate(true)
	_begin("Fix it")
	var why := Part.apply_fix(_rec(), p)
	if why != "":
		m.S.part = snap   # nothing changes: the fix is taken back out
		m._drop_undo()
		_edit_n = -1
		_say(why)
	else:
		_end()
		_say(Part.fix_words(p))
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_values_sync()


func _remove_piece() -> void:
	if not del_on:
		_say("Click a piece first, then press Remove")
		return
	if not _drag.is_empty() or not _draft.is_empty():
		return
	_flush_if_dirty()
	var rec := _rec()
	var fs: Array = rec.get("features", [])
	var k := Part.index_of(rec, del_id)
	if k < 0 or fs.size() != del_n:
		_pick_clear()
		_say("The part changed: click the piece again")
		return
	var test: Dictionary = rec.duplicate(true)
	var tfs: Array = test["features"]
	var gone: Dictionary = tfs[k]
	tfs.remove_at(k)
	var extra: Array = []
	for key in ["sketch", "plane"]:
		if gone.has(key):
			extra.append(String(gone[key]))
	for sid in extra:
		if sid == "" or JSON.stringify(tfs).contains("\"%s\"" % sid):
			continue
		for i in tfs.size():
			if String(tfs[i].get("id", "")) == sid:
				tfs.remove_at(i)
				break
	var errs: Dictionary = Part.replay(test).get("errors", {})
	if not errs.is_empty():
		_say("A step after it needs this piece, so it stays. Take those steps out first")
		return
	if _pt_on(Part.body_faces(test, -1), del_pt):
		_say("That face is still there after the step: click the piece on its outside")
		return
	_begin("Remove piece")
	var live := _rec()
	live["features"] = tfs
	armed = ""
	tweak = {}
	pu.upto = -1
	pu.sync()
	_pick_clear()
	_rows_sync()
	_end()
	_say("Took out the piece. Undo puts it back")


## a press on the top bar's BUTTONS never reaches input() (the button takes it in the GUI pass first): this sees it before the GUI,
## notes it, and lets the button have it. A drag that then leaves the bar starts the sketch (input() below, from the noted press)
func _input(ev: InputEvent) -> void:
	if ev is InputEventKey:
		_key(ev as InputEventKey)   # EKEYS: Escape and Delete (Ctrl+Z / Ctrl+Y are main's undo and redo)
		return
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and active():
		_grey_say((ev as InputEventMouseButton).position)   # FHELP3: a greyed button takes no click: its reason goes on the line
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


## FHELP3: a press on a greyed Easy button (bar, MAKE row, panel) says the reason it is greyed, after the grey tag
func _grey_say(p: Vector2) -> void:
	for root_c in [bar, make_box, panel]:
		if root_c == null:
			continue
		for c in (root_c as Node).find_children("*", "BaseButton", true, false):
			var b := c as BaseButton
			if b.is_visible_in_tree() and b.disabled and b.get_global_rect().has_point(p):
				var tip := String(b.tooltip_text)
				if tip.find("
NOT NOW: ") >= 0:
					_say(tip.get_slice("
NOT NOW: ", 1).strip_edges())
				return


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
	if ev is InputEventMouse:
		_alt = (ev as InputEventMouse).alt_pressed
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
			if armed == "" and not _over_ui(p) and _edge_press(p):
				return true
			if armed == "" and not _over_ui(p):
				_pick_p = p   # FDELETE: a click (no drag) on a piece picks it, on the release
			return false
		if not _edge.is_empty():
			_edge_end()
			return true
		if not _drag.is_empty():
			_drag_to(p, true)
			_drag = {}
			_end()
			return true
		_bar_press = null
		if _pick_p.x >= 0.0:
			var pp := _pick_p
			_pick_p = Vector2(-1, -1)
			if pp.distance_to(p) < 6.0 and _drag.is_empty() and _draft.is_empty():
				if not _open_face(p):   # NOPENTOP: after Hollow inside, a flat face click opens that side; any other click picks a piece
					_pick_at(p)
		if not _draft.is_empty():
			_draft_end()
			return true
		return false
	if ev is InputEventMouseMotion:
		var p := (ev as InputEventMouseMotion).position
		if not _edge.is_empty():
			_edge_move(p)
			return true
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
	for c in [bar, make_box, panel, shape_box, colour_box, repeat_box, stick_box, tilt_box]:
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
	if sh == "oval":
		var so := _sides(a, b, pl)
		if so.has("thin"):
			_say("Drag a bit wider: both sides must be at least 2 mm (now %s mm)" % _mm_words(float(so["thin"])))
			return
		b = so["b"]
		var oc := (a + b) * 0.5
		var orx := absf(b.x - a.x) * 0.5
		var ory := absf(b.y - a.y) * 0.5
		var opts: Array = []
		for i in 16:   # 16 points round the ellipse: a closed spline through them is the oval outline
			var t := TAU * float(i) / 16.0
			opts.append(Part.arr2(Vector2(oc.x + orx * cos(t), oc.y + ory * sin(t))))
		ents = [{"k": "bspline", "pts": opts, "closed": true}]
	elif sh == "box" or sh == "pointy" or sh == "hex" or sh == "poly":
		var sd := _sides(a, b, pl)
		if sd.has("thin"):
			_say("Drag a bit wider: both sides must be at least 2 mm (now %s mm)" % _mm_words(float(sd["thin"])))
			return
		b = sd["b"]
		if sh == "box":
			ent = {"k": "rect", "a": Part.arr2(a), "b": Part.arr2(b)}
		elif sh == "hex" or sh == "poly":   # HEX / POLY: straight lines, the closed outline of the polygon (Expert's line tool records the same)
			var hp := _poly_pts(a, b, 6 if sh == "hex" else sides)
			for i in hp.size():
				ents.append({"k": "line", "a": Part.arr2(hp[i]), "b": Part.arr2(hp[(i + 1) % hp.size()])})
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
	rec["features"].append(Part.new_feature(rec, "sketch", {"plane": _face_plane(rec, fc), "ents": ents if not ents.is_empty() else [ent], "dims": []}))
	_end()
	armed = ""
	tweak = {}
	pu.upto = -1
	pu.sync()
	_rows_sync()
	var tip := ""
	if not _snap_said and sh != "curve":
		tip = " Corners snap to 1 cm (hold Alt for a free size)."   # FSNAP: said once, on the first shape
		_snap_said = true
	if _face_sketch_last(rec):   # FFRAME: a shape drawn on a face of the solid: Cut a hole is the next step (the shape IS the hole), the hint says so
		_say("Shape drawn on the face.%s Now press Cut a hole to cut it in, or Pull it up to push it out" % tip)
	else:
		_say("Shape drawn.%s Now press Pull it up or Spin it round" % tip)


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
	var wpos := PackedVector3Array()   # FLAMP5: the welded position of each vertex id (for the touch test below)
	var tris: Array = []               # FLAMP5: each triangle as its three welded ids
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
				wpos.append(v)
			ids.append(int(weld[key]))
		var tri := idx.size() if idx.size() > 0 else vs.size()
		for t in range(0, tri - 2, 3):
			var a: int = ids[idx[t] if idx.size() > 0 else t]
			var b1: int = ids[idx[t + 1] if idx.size() > 0 else t + 1]
			var b2: int = ids[idx[t + 2] if idx.size() > 0 else t + 2]
			tris.append([a, b1, b2])
			for b in [b1, b2]:
				var ra: int = find.call(a)
				var rb: int = find.call(b)
				if ra != rb:
					parent[ra] = rb
	# FLAMP5: a shape pulled up off a face of a solid is a separate shell that sits ON the face: the two meet on a face patch,
	# with no vertex shared, so the welding above sees two pieces. A corner of one shell lying on a triangle of the other joins them.
	var merged := true
	while merged and tris.size() > 0:
		merged = false
		var roots := {}
		for i in parent.size():
			roots[find.call(i)] = true
		if roots.size() < 2:
			break
		var groups := {}   # root -> {"v": vertex ids, "t": triangle indices, "bb": AABB}
		for i in parent.size():
			var rr: int = find.call(i)
			if not groups.has(rr):
				groups[rr] = {"v": PackedInt32Array(), "t": PackedInt32Array(), "bb": AABB(wpos[i], Vector3.ZERO)}
			groups[rr]["v"].append(i)
			groups[rr]["bb"] = (groups[rr]["bb"] as AABB).expand(wpos[i])
		for ti in tris.size():
			var rt: int = find.call(int(tris[ti][0]))
			groups[rt]["t"].append(ti)
		var keys := groups.keys()
		for x in keys.size():
			for y in range(x + 1, keys.size()):
				var ga: Dictionary = groups[keys[x]]
				var gb: Dictionary = groups[keys[y]]
				if not (ga["bb"] as AABB).grow(1e-4).intersects(gb["bb"] as AABB):
					continue
				if Part.touch_patch(_group_pts(ga, wpos), _group_tri_pts(gb, wpos, tris), gb["bb"]) or Part.touch_patch(_group_pts(gb, wpos), _group_tri_pts(ga, wpos, tris), ga["bb"]):
					parent[find.call(int(keys[x]))] = find.call(int(keys[y]))
					merged = true
					break
			if merged:
				break
	var roots := {}
	for i in parent.size():
		roots[find.call(i)] = true
	_lump_n = maxi(roots.size(), 1)
	return _lump_n


## FLAMP5: the points of a welded group, and the flat triangle points of the group's triangles (see Part.touch_patch)
func _group_pts(g: Dictionary, wpos: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for vi in g["v"]:
		out.append(wpos[vi])
	return out


func _group_tri_pts(g: Dictionary, wpos: PackedVector3Array, tris: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for ti in g["t"]:
		var tr: Array = tris[ti]
		out.append(wpos[tr[0]])
		out.append(wpos[tr[1]])
		out.append(wpos[tr[2]])
	return out


## NROUNDDRAG: a press within EDGE_PX (screen px) of an edge of the solid, with nothing armed, takes the edge in hand. Dragging it OUTWARD
## (away from the middle of the solid) rounds it: the drag distance is the radius (mm, 1 mm = pxmm screen px). Release = one undo step
func _edge_press(p: Vector2) -> bool:
	if _tpl() != "" or not _drag.is_empty() or not _draft.is_empty() or not Part.available() or m.cam == null:
		return false
	var bb: AABB = pu.res.get("aabb", AABB()) if pu != null else AABB()
	if bb.size == Vector3.ZERO:
		return false   # no solid yet: nothing to round (a cheap test first: a press on the empty grid never replays the part)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for k in 8:
		var sc: Vector2 = m.cam.unproject_position(bb.position + bb.size * Vector3(k & 1, (k >> 1) & 1, (k >> 2) & 1))
		lo = lo.min(sc)
		hi = hi.max(sc)
	if not Rect2(lo, hi - lo).grow(EDGE_PX).has_point(p):
		return false
	var res := Part.replay(_rec(), -1, {"edges": true, "keep": true})
	Part.release_kept(res.get("ids", []))
	var best := {}
	var best_d := EDGE_PX
	for e in res.get("edges", []):
		if int(e["body"]) != 0 or bool(e.get("seam", false)):
			continue
		var a: Vector3 = e["a"]
		var b: Vector3 = e["b"]
		if m.cam.is_position_behind(a) or m.cam.is_position_behind(b):
			continue
		var d := _seg_px(p, m.cam.unproject_position(a), m.cam.unproject_position(b))
		if d < best_d:
			best_d = d
			best = e
	if best.is_empty():
		return false
	var c: Vector3 = best["c"]
	var ctr: Vector3 = (res["aabb"] as AABB).get_center()
	var dir := (c - ctr).normalized() if (c - ctr).length() > 1e-9 else Vector3.UP
	var s0: Vector2 = m.cam.unproject_position(c)
	var outv: Vector2 = s0 - m.cam.unproject_position(ctr)
	outv = outv.normalized() if outv.length() > 0.5 else Vector2.UP
	var pxmm: float = maxf((m.cam.unproject_position(c + dir * Part.MM) - s0).length(), 0.001)   # screen px per mm at the edge
	_flush_if_dirty()
	_edge = {"e": best, "press": p, "out": outv, "pxmm": pxmm, "r": 0.0}
	_say("Drag outward to round this edge: the drag distance is the radius")
	return true


## the distance in px from p to the screen segment a-b
func _seg_px(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := 0.0 if ab.length_squared() < 1e-9 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _edge_move(p: Vector2) -> void:
	var along := (p - (_edge["press"] as Vector2)).dot(_edge["out"] as Vector2)   # only the outward part of the drag is the radius
	var r := clampf(along / float(_edge["pxmm"]), 0.0, EDGE_MAX_MM)
	_edge["r"] = r
	edge_num.text = "%d mm" % roundi(r)
	edge_num.global_position = p + Vector2(18, 14)
	edge_num.visible = true


func _edge_cancel() -> void:
	_edge = {}
	edge_num.visible = false
	_say("Rounding cancelled")


func _edge_end() -> void:
	var ed := _edge
	_edge = {}
	edge_num.visible = false
	var r := snappedf(float(ed["r"]), 0.1)
	if r < 0.5:
		_say("Drag an edge outward to round it: the drag distance is the radius")
		return
	_edge_round(ed["e"], r)


## NROUNDDRAG: one fillet step on the dragged edge (the radius in mm). An edge that cannot take it says what to do next, and adds nothing
func _edge_round(e: Dictionary, r: float) -> void:
	_flush_if_dirty()
	var rec := _rec()
	var trial := Part.replay(rec, -1, {"edges": true, "keep": true})
	var kept: Array = trial.get("ids", [])
	var err := "Nothing solid to round yet. Pull it up first" if kept.is_empty() else Part.fillet_trial(int(kept[0]), r, [Part.describe(e)])
	Part.release_kept(kept)
	if err != "":
		_say("That edge will not take a %d mm round. Drag it less, or Undo the last step" % roundi(r))
		return
	_begin("Round an edge by drag")
	var f := Part.new_feature(rec, "fillet", {"body": 0, "r": r, "edges": [Part.describe(e)]})
	rec["features"].append(f)
	if _last_error(rec, String(f["id"])) != "":
		rec["features"].pop_back()
		_end()
		_say("That edge will not take a %d mm round. Drag it less, or Undo the last step" % roundi(r))
		return
	_round_done(f)
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_end()
	_say("Edge rounded %d mm: drag another edge, or use the slider for more or less" % roundi(r))

