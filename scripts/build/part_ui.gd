class_name PartUI
extends Node
## THE PART WORKSPACE (EXPERT, phase 1, Fusion 360 style) on the BUILD page: the "Part" button of the BUILD ribbon swaps the house tools for
##   SKETCH   Line, Rectangle, Circle, Arc, Dimension      CREATE  Extrude, Revolve, Mirror      MODIFY  Fillet, Chamfer      Finish sketch
## a BROWSER on the left (Bodies, Sketches, Planes), a numbers / dialog panel on the right and the TIMELINE strip at the bottom: one icon per
## feature (scripts/build/part.gd holds the record: Scene.part). Rebuild = replay the features through the CAD kernel into a preview mesh.
##   SKETCH   a click on a plane in the browser (or any sketch tool) starts a sketch and turns the view square onto its plane. Lines, rectangles
##            and circles snap to the grid (5 mm, or 1 mm with the Snap button; Alt = free). Dimension: click a line, an edge of a rectangle or a
##            circle, type its size, Enter. The sketch panel lists every dimension as a number to retype.
##   CREATE   Extrude / Revolve take the newest unused sketch: a dialog on the right (distance / angle, both sides, taper angle, join / new body /
##            cut / intersect) with a live preview; Enter or OK makes the feature.   Mirror reflects the body across a plane.
##            Split cuts every body the plane crosses into two (a plane and an offset).
##   MODIFY   Shell hollows the newest body: wall thickness and the face left open (one face, or none).
##   MODIFY   Fillet / Chamfer: click edges (sky blue), type the radius / distance, OK. The edge is remembered by where it sits on the body, so it
##            survives a sketch that is made bigger.
##   TIMELINE a step is selected by a click and EDITED by a double click (a sketch re-opens, a dialog re-opens with its numbers); the later steps
##            replay when you finish. The arrows move the marker: the model shows the steps up to it.
## Every feature (and every sketch, from its start to Finish sketch) is ONE undo step, taken BEFORE the record changes. Without the CAD DLL
## (Part.available() false) the tools are greyed with one line why.

const SKY := Color("#73BFFF")
const PANEL_W := 250.0
const BROWSER_W := 196.0
const TL_H := 84.0
const DOUBLE_MS := 650
const SKETCH_TOOLS := ["Line", "Rectangle", "Circle", "Arc", "Spline", "Dimension"]
const CREATE_TOOLS := ["Extrude", "Revolve", "Mirror", "Loft", "Offset plane", "Split", "Canvas"]
const TOOL_KIND := {"Offset plane": "plane"}   # a tool's feature kind when it is not its lower-case name
const MODIFY_TOOLS := ["Fillet", "Chamfer", "Shell"]
const SHELL_OPEN := ["", "+x", "-x", "+y", "-y", "+z", "-z"]   # the open face of a shell (Part.SHELL_DIRS), in the dialog's order
const SHELL_OPEN_TXT := ["Closed (no face open)", "Right face (+X)", "Left face (-X)", "Top face (+Y, up)", "Bottom face (-Y)", "Front face (+Z)", "Back face (-Z)"]
const HINGE_TOOLS := ["Hinge"]
const HSEC := 25.0   # the frames per second of the hinge's swing check (Part.hinge_sweep)
const TIPS := {
	"Line": "LINE: click the start, click each corner; a typed number sets the length. Esc ends the chain. Snaps to the grid.",
	"Rectangle": "RECTANGLE: drag from one corner to the other (or click both corners). Then Dimension it.",
	"Circle": "CIRCLE: press the centre, drag out the radius.",
	"Arc": "ARC: click the start, click the end, then click a point the arc passes through.",
	"Spline": "SPLINE: click points for a smooth curve. Click the first point (or double-click) to close it; double-click ends an open curve. Drag a point to move it.",
	"Dimension": "DIMENSION: pick a line, an edge of a rectangle or a circle, type its size, press Enter.",
	"Extrude": "EXTRUDE: the newest sketch becomes a solid. Type a distance and press Enter.",
	"Revolve": "REVOLVE: the newest sketch turns round its horizontal or vertical axis. Type the angle and press Enter.",
	"Mirror": "MIRROR: the body and its reflection across a plane become one solid.",
	"Split": "SPLIT: pick a plane and an offset (mm). Every body the plane cuts becomes two bodies. Press Enter.",
	"Shell": "SHELL: the newest body becomes a hollow box with the wall thickness you type. Pick the face left open, press Enter.",
	"Canvas": "CANVAS: put a picture on the Front, Top or Right plane (or an offset plane). Click two points of known size, type the real distance, drag it to line up.",
	"Loft": "LOFT: pick two or more sketches in order (each a closed profile); the solid runs through them. Ruled = straight, Smooth = curved.",
	"Offset plane": "OFFSET PLANE: pick Front, Top or Right and type a distance. The new plane is in the browser: click it to sketch on it.",
	"Fillet": "FILLET: click edges (they turn sky blue), type a radius, press Enter or OK.",
	"Chamfer": "CHAMFER: click edges, type a distance, press Enter or OK.",
	"Hinge": "HINGE: click the part that turns, then the line it turns round (a straight edge, or two points on it). Type the angles and seconds, then OK."}

var bu: BuildUI
var m: Node
var on := false                # the Part workspace is showing (inside BUILD)
var easy := false              # ...with EASY PART's screen (scripts/easy_part.gd) instead of the Expert chrome: the same record
var ep: EasyPart
var easy_open_btn: Button
var tool := ""
var sk := ""                   # the sketch being edited ("" = the model is showing)
var snap_mm := 5.0
var grid_on := true
var show_dims := true
var upto := -1                 # the timeline marker: -1 = every step
var sel_step := -1
var dlg := {}                  # the open feature dialog: {"t", "edit": index or -1, "sketch", ...}
var picked: Array = []         # fillet / chamfer: the picked edges (entries of edge_cache)
var edge_cache: Array = []     # the pickable edges of the model as the dialog sees it
var res := {}                  # the last replay of the record (Part.replay)
var prev := {}                 # the dialog's preview replay
var hover_edge := -1
var spl_drag := {}             # a spline point being dragged: {"ent", "pt"} (sketch Spline tool)
var spl_last_ms := -100000     # the last Spline click (ms) and its screen point: a double-click ends the curve
var spl_last_p := Vector2.ZERO
var hover_ent := {}
var draft := {}                # a shape in progress: {"k", "a", "b", "down", "pts"}
var typed := ""
var dim_target := {}
var hp := {}                   # the hinge dialog's picks: {"body", "faces", "pts", "o", "d" (the line, once picked)}
var hsw := {}                  # the selected hinge's swing check (Part.hinge_sweep), kept while its record is the same
var hsw_sig := ""
var pair_pick := {}            # must not touch: {"id", "first", "faces"} while two parts are being picked
var pose := {}                 # {"f": hinge id, "deg": angle} while the hinge is shown turned (Play / the slider)
var play_on := false
var play_t := 0.0
var play_pct := 0.0
var hinge_box: VBoxContainer
var hinge_title: Label
var hinge_info: Label
var hinge_play_btn: Button
var hinge_slider: HSlider
var hinge_pct_l: Label
var hinge_strip: Control
var hinge_red_l: Label
var hinge_pair_btn: Button
var hinge_pairs_vb: VBoxContainer
var hinge_sig := ""
var f_from: LineEdit
var f_to: LineEdit
var f_dur: LineEdit
var f_dial: Control
var status := ""
var part_btn: Button
var tool_btns := {}
var finish_btn: Button
var house_btns: Array = []     # the BUILD ribbon's own buttons, hidden while the Part workspace is on
var reopen_btn: Button = null  # "What to build" (BuildChoose.reopen_button): kept on the Part ribbon
var my_seps: Array = []
var _was_show := false
var _tag_vis: Array = []       # the floor's axis names as they were (they say "his left": not for a part)
var part_mesh: MeshInstance3D
var prev_mesh: MeshInstance3D
var pov: Control
var browser: PanelContainer
var browser_vb: VBoxContainer
var side: PanelContainer
var side_title: Label
var sketch_box: VBoxContainer
var nums_vb: VBoxContainer
var snap_btn: Button
var part_give: Button   # "Give it to the fighter" (PartWeapon)
var grid_chk: CheckBox
var dims_chk: CheckBox
var dlg_box: VBoxContainer
var dlg_rows: VBoxContainer
var dlg_info: Label
var ok_btn: Button
var cancel_btn: Button
var f_num: LineEdit
var f_ang: LineEdit
var f_both: CheckBox
var f_op: OptionButton
var f_axis: OptionButton
var f_plane: OptionButton
var f_taper: LineEdit
var f_open: OptionButton
var f_edges: Label
var f_prof: OptionButton       # the loft dialog: "Add a sketch..." then each sketch (its picks, in order, are dlg["sketches"])
var f_prof_clear: Button
var f_ruled: OptionButton      # the loft dialog: ruled (straight) or smooth
var dim_edit: LineEdit
var note: PanelContainer
var note_l: Label
var tl: PanelContainer
var tl_row: HBoxContainer
var tl_info: Label
var tl_btns: Array = []
var _sig := ""
var _rec_sig := ""
var _browser_sig := ""
var _tl_sig := ""
var _nums_sig := ""
var _last_step := -1
var _last_ms := 0
var _sk_n := -1                # the undo stack's size when the sketch began
var _sk_before := ""
var _profile_ok := ""          # the sketch's own status line ("closed profile" ...)
var _profile_sig := ""
var _fit_sig := ""
var cv_drag := {}              # a canvas picture being dragged (GAP 3): {"i": record index} or {"dlg": true}, "from" (mm), "moved"
var cv_tex := {}               # picture path -> Texture2D (the canvas view)
var f_cv_pick: Button          # the canvas dialog's controls (built once: _canvas_ctl)
var f_cv_plane: OptionButton
var f_cv_show: CheckBox
var f_cv_op: HSlider
var f_cv_cal: Button
var f_cv_file: FileDialog


func setup(b: BuildUI) -> void:
	bu = b
	m = b.m
	name = "part_ui"
	var row: HBoxContainer = m.ui_ribbon["BUILD"]
	for c in row.get_children():
		house_btns.append(c)
	part_btn = m._button("Part", toggle, "Part: sketch on a plane, extrude, revolve, fillet; a timeline of steps you can edit (Expert)")
	part_btn.name = "build_tool_part"
	part_btn.toggle_mode = true
	_icon(part_btn, "part_part")
	row.add_child(part_btn)
	for t in SKETCH_TOOLS:
		_tool_btn(row, t)
	_sep(row)
	for t in CREATE_TOOLS:
		_tool_btn(row, t)
	_sep(row)
	for t in MODIFY_TOOLS:
		_tool_btn(row, t)
	_sep(row)
	for t in HINGE_TOOLS:
		_tool_btn(row, t)
	_sep(row)
	finish_btn = m._button("Finish sketch", finish_sketch, "Finish sketch: the sketch is done; the steps after it replay (one undo step)")
	finish_btn.name = "part_finish"
	_icon(finish_btn, "part_finish")
	row.add_child(finish_btn)
	easy_open_btn = m._button("Easy", open_easy, "Easy Part: change a sword, axe, shield, chair or crate with sliders and big buttons, mouse only. The same part opens here again")
	easy_open_btn.name = "part_easy_open"
	_icon(easy_open_btn, "part_part")
	row.add_child(easy_open_btn)
	for c in house_btns:
		if c.name == "build_choose_open":
			reopen_btn = c as Button
	_order_row()
	for c in row.get_children():
		if not house_btns.has(c) and c != part_btn:
			c.visible = false
	part_mesh = MeshInstance3D.new()
	part_mesh.name = "part_mesh"
	part_mesh.material_override = _solid_mat(Color(0.74, 0.77, 0.82))
	part_mesh.visible = false
	bu.root3.add_child(part_mesh)
	prev_mesh = MeshInstance3D.new()
	prev_mesh.name = "part_preview"
	prev_mesh.material_override = _solid_mat(Color(0.7, 0.78, 0.9))
	prev_mesh.visible = false
	bu.root3.add_child(prev_mesh)
	pov = Control.new()
	pov.name = "part_overlay"
	pov.set_anchors_preset(Control.PRESET_FULL_RECT)
	pov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pov.draw.connect(_draw)
	pov.visible = false
	m.ui_root.add_child(pov)
	_build_browser()
	_build_side()
	_build_timeline()
	note = PanelContainer.new()
	note.name = "part_note"
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note_l = Label.new()
	note_l.name = "part_note_text"
	note_l.add_theme_font_size_override("font_size", 14)
	note.add_child(note_l)
	note.visible = false
	m.ui_root.add_child(note)
	var play_tmr := Timer.new()   # C3 Play: the hinge turns while it runs (PartUI is not in the tree; the overlay is)
	play_tmr.name = "part_hinge_timer"
	play_tmr.wait_time = 0.05
	play_tmr.timeout.connect(_play_tick)
	pov.add_child(play_tmr)
	play_tmr.start()
	dim_edit = LineEdit.new()
	dim_edit.name = "part_dim_edit"
	dim_edit.custom_minimum_size = Vector2(96, 0)
	dim_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	dim_edit.select_all_on_focus = true
	dim_edit.visible = false
	dim_edit.text_submitted.connect(_dim_submitted)
	m.ui_root.add_child(dim_edit)
	ep = EasyPart.new()
	ep.pu = self
	ep.m = m
	m.ui_root.add_child(ep)   # (PartUI itself is not in the tree: EasyPart needs its own _process)
	ep.build(m.ui_root)


## the Expert chrome (ribbon tools, browser, panel, timeline) shows
func chrome() -> bool:
	return bu.on and on and not easy and not bu.easy_ui()


## the Part workspace has the page, in Expert or in Easy's screen
func shows() -> bool:
	return bu.on and on and (easy or not bu.easy_ui())


## EASY PART: the same record on Easy's screen. A part drawn in Expert stays as it is (the chips start a template over it, as one undo step);
## nothing there yet = a sword to begin with (one undo step)
func open_easy() -> void:
	if sk != "":
		finish_sketch()
	close_dialog()
	tool = ""
	if not on:
		on = true
		part_btn.set_pressed_no_signal(true)
	easy = true
	if m.S.part.is_empty() and Part.available():
		m._step_hint = "Start a sword"
		m._push_undo()
		m.S.part = PartTemplates.make("sword")
	upto = -1
	_rec_sig = ""
	bu.sync()
	ep.entered()
	m._fit_top.call_deferred()


## main._fit_top shows a ribbon row's buttons by this: the BUILD row holds the house tools AND the Part workspace's, and only one set shows
func ribbon_shows(b: Node, tab: String) -> bool:
	if tab != "BUILD":
		return true
	var show := chrome()
	if b == part_btn:
		return bu.on and not bu.easy_ui()
	if b == reopen_btn:   # the way back to the chooser: in the Part ribbon too, with its words
		return true
	if b is VSeparator:
		return show if my_seps.has(b) else not show
	if house_btns.has(b):
		return not show
	return show


func _sep(row: HBoxContainer) -> void:
	var v := VSeparator.new()
	my_seps.append(v)
	row.add_child(v)


func _solid_mat(c: Color) -> StandardMaterial3D:
	var mt := StandardMaterial3D.new()
	mt.albedo_color = c
	mt.roughness = 0.5
	mt.metallic = 0.15
	mt.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mt


func _icon(btn: Button, icon: String) -> void:
	btn.icon = Icons.tex(icon)
	btn.theme_type_variation = "Ribbon"
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.expand_icon = false
	btn.add_theme_constant_override("h_separation", 6)


func _tool_btn(row: HBoxContainer, t: String) -> void:
	var btn: Button = m._button(t, _pick.bind(t), "%s. %s" % [t, String(TIPS[t]).get_slice(": ", 1)])
	btn.name = "part_tool_" + t.to_lower().replace(" ", "_")
	btn.toggle_mode = true
	_icon(btn, "part_" + t.to_lower().replace(" ", "_"))
	tool_btns[t] = btn
	row.add_child(btn)


func _panel_style(border := true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.14, 0.94)
	sb.border_color = SKY
	sb.set_border_width_all(2 if border else 0)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10)
	return sb


func _label(txt: String, fs := 14, dim := false) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", fs)
	if dim:
		l.modulate = Color(1, 1, 1, 0.6)
	return l


func _build_browser() -> void:
	browser = PanelContainer.new()
	browser.name = "part_browser"
	browser.custom_minimum_size.x = BROWSER_W
	browser.add_theme_stylebox_override("panel", _panel_style())
	browser_vb = VBoxContainer.new()
	browser_vb.add_theme_constant_override("separation", 2)
	browser.add_child(browser_vb)
	browser.visible = false
	m.ui_root.add_child(browser)


func _build_side() -> void:
	side = PanelContainer.new()
	side.name = "part_side"
	side.custom_minimum_size.x = PANEL_W
	side.add_theme_stylebox_override("panel", _panel_style())
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	side.add_child(vb)
	side_title = _label("SKETCH PALETTE", 13, true)
	side_title.name = "part_side_title"
	vb.add_child(side_title)
	sketch_box = VBoxContainer.new()
	sketch_box.name = "part_sketch_box"
	sketch_box.add_theme_constant_override("separation", 4)
	vb.add_child(sketch_box)
	grid_chk = CheckBox.new()
	grid_chk.name = "part_grid"
	grid_chk.text = "Grid"
	grid_chk.button_pressed = true
	grid_chk.focus_mode = Control.FOCUS_NONE
	grid_chk.toggled.connect(func(v: bool): grid_on = v; pov.queue_redraw())
	sketch_box.add_child(grid_chk)
	snap_btn = Button.new()
	snap_btn.name = "part_snap"
	snap_btn.focus_mode = Control.FOCUS_NONE
	snap_btn.tooltip_text = "the sketch grid: 5 mm, or 1 mm for fine work (holding Alt frees one click)"
	snap_btn.pressed.connect(func(): snap_mm = 1.0 if snap_mm > 2.0 else 5.0; _snap_text(); pov.queue_redraw())
	sketch_box.add_child(snap_btn)
	dims_chk = CheckBox.new()
	dims_chk.name = "part_show_dims"
	dims_chk.text = "Show dimensions"
	dims_chk.button_pressed = true
	dims_chk.focus_mode = Control.FOCUS_NONE
	dims_chk.toggled.connect(func(v: bool): show_dims = v; pov.queue_redraw())
	sketch_box.add_child(dims_chk)
	sketch_box.add_child(_label("NUMBERS (parameters)", 13, true))
	nums_vb = VBoxContainer.new()
	nums_vb.name = "part_nums"
	nums_vb.add_theme_constant_override("separation", 4)
	sketch_box.add_child(nums_vb)
	hinge_box = VBoxContainer.new()
	hinge_box.name = "part_hinge_box"
	hinge_box.add_theme_constant_override("separation", 6)
	hinge_box.visible = false
	vb.add_child(hinge_box)
	hinge_title = _label("", 13, true)
	hinge_title.name = "part_hinge_title"
	hinge_box.add_child(hinge_title)
	hinge_info = _label("", 12, true)
	hinge_info.name = "part_hinge_info"
	hinge_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hinge_info.custom_minimum_size.x = PANEL_W - 24.0
	hinge_box.add_child(hinge_info)
	var pr := HBoxContainer.new()
	hinge_play_btn = Button.new()
	hinge_play_btn.name = "part_hinge_play"
	hinge_play_btn.text = "Play"
	hinge_play_btn.focus_mode = Control.FOCUS_NONE
	hinge_play_btn.tooltip_text = "Play: the part turns from its first angle to its last, in the seconds you typed"
	hinge_play_btn.pressed.connect(_hinge_play_toggle)
	pr.add_child(hinge_play_btn)
	hinge_pct_l = _label("0 %", 12, true)
	hinge_pct_l.name = "part_hinge_pct"
	pr.add_child(hinge_pct_l)
	hinge_box.add_child(pr)
	hinge_slider = HSlider.new()
	hinge_slider.name = "part_hinge_slider"
	hinge_slider.min_value = 0.0
	hinge_slider.max_value = 100.0
	hinge_slider.step = 1.0
	hinge_slider.focus_mode = Control.FOCUS_NONE
	hinge_slider.custom_minimum_size.x = PANEL_W - 24.0
	hinge_slider.value_changed.connect(hinge_set_pct)
	hinge_box.add_child(hinge_slider)
	hinge_box.add_child(_label("MUST NOT TOUCH", 13, true))
	hinge_pair_btn = Button.new()
	hinge_pair_btn.name = "part_hinge_pair"
	hinge_pair_btn.text = "Add a pair of parts"
	hinge_pair_btn.focus_mode = Control.FOCUS_NONE
	hinge_pair_btn.tooltip_text = "Must not touch: click two parts; the swing shows the frames where they touch"
	hinge_pair_btn.pressed.connect(_pair_start)
	hinge_box.add_child(hinge_pair_btn)
	hinge_pairs_vb = VBoxContainer.new()
	hinge_pairs_vb.name = "part_hinge_pairs"
	hinge_pairs_vb.add_theme_constant_override("separation", 2)
	hinge_box.add_child(hinge_pairs_vb)
	hinge_strip = Control.new()
	hinge_strip.name = "part_hinge_strip"
	hinge_strip.custom_minimum_size = Vector2(PANEL_W - 24.0, 14)
	hinge_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hinge_strip.draw.connect(_draw_strip)
	hinge_box.add_child(hinge_strip)
	hinge_red_l = _label("", 12, true)
	hinge_red_l.name = "part_hinge_red"
	hinge_red_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hinge_red_l.custom_minimum_size.x = PANEL_W - 24.0
	hinge_box.add_child(hinge_red_l)
	f_from = _field("part_from")
	f_to = _field("part_to")
	f_dur = _field("part_seconds")
	f_dial = Control.new()
	f_dial.name = "part_dial"
	f_dial.custom_minimum_size = Vector2(120, 120)
	f_dial.mouse_filter = Control.MOUSE_FILTER_STOP
	f_dial.draw.connect(_draw_dial)
	f_dial.gui_input.connect(_dial_input)
	dlg_box = VBoxContainer.new()
	dlg_box.name = "part_dialog"
	dlg_box.add_theme_constant_override("separation", 6)
	vb.add_child(dlg_box)
	dlg_rows = VBoxContainer.new()
	dlg_rows.add_theme_constant_override("separation", 6)
	dlg_box.add_child(dlg_rows)
	f_num = _field("part_num")
	f_ang = _field("part_angle")
	f_both = CheckBox.new()
	f_both.name = "part_both"
	f_both.text = "Both sides"
	f_both.focus_mode = Control.FOCUS_NONE
	f_both.toggled.connect(func(_v): _preview())
	f_op = OptionButton.new()
	f_op.name = "part_op"
	for o in ["Join", "New body", "Cut", "Intersect"]:
		f_op.add_item(o)
	f_op.item_selected.connect(func(_i): _preview())
	f_axis = OptionButton.new()
	f_axis.name = "part_axis"
	for o in ["Horizontal axis", "Vertical axis"]:
		f_axis.add_item(o)
	f_axis.item_selected.connect(func(_i): _preview())
	f_plane = OptionButton.new()
	f_plane.name = "part_plane"
	for o in ["Front plane", "Top plane", "Right plane"]:
		f_plane.add_item(o)
	f_plane.selected = 2
	f_plane.item_selected.connect(func(_i): _preview())
	f_taper = _field("part_taper")
	f_open = OptionButton.new()
	f_open.name = "part_shell_open"
	for o in SHELL_OPEN_TXT:
		f_open.add_item(o)
	f_open.item_selected.connect(func(_i): _preview())
	f_prof = OptionButton.new()
	f_prof.name = "part_profiles"
	f_prof.focus_mode = Control.FOCUS_NONE
	f_prof.item_selected.connect(_prof_picked)
	f_prof_clear = Button.new()
	f_prof_clear.name = "part_profiles_clear"
	f_prof_clear.text = "Start the profiles again"
	f_prof_clear.focus_mode = Control.FOCUS_NONE
	f_prof_clear.pressed.connect(func(): dlg["sketches"] = []; _prof_sync(); _preview())
	f_ruled = OptionButton.new()
	f_ruled.name = "part_ruled"
	for o in ["Ruled (straight)", "Smooth (curved)"]:
		f_ruled.add_item(o)
	f_ruled.item_selected.connect(func(_i): _preview())
	f_edges = _label("")
	f_edges.name = "part_edges_label"
	dlg_info = _label("", 12, true)
	dlg_info.name = "part_dialog_info"
	dlg_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dlg_info.custom_minimum_size.x = PANEL_W - 24.0
	dlg_box.add_child(dlg_info)
	var hb := HBoxContainer.new()
	cancel_btn = Button.new()
	cancel_btn.name = "part_cancel"
	cancel_btn.text = "Cancel"
	cancel_btn.focus_mode = Control.FOCUS_NONE
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(close_dialog)
	hb.add_child(cancel_btn)
	ok_btn = Button.new()
	ok_btn.name = "part_ok"
	ok_btn.text = "OK"
	ok_btn.focus_mode = Control.FOCUS_NONE
	ok_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok_btn.pressed.connect(ok_pressed)
	hb.add_child(ok_btn)
	dlg_box.add_child(hb)
	side.visible = false
	m.ui_root.add_child(side)
	_snap_text()


func _snap_text() -> void:
	snap_btn.text = "Snap to %d mm" % int(snap_mm)


## a number field: a click takes the whole value, Enter = OK, every change previews
func _field(nm: String) -> LineEdit:
	var le := LineEdit.new()
	le.name = nm
	le.custom_minimum_size.x = 84
	le.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	le.select_all_on_focus = true
	le.text_changed.connect(func(_t): _preview())
	le.text_submitted.connect(func(_t): ok_pressed.call_deferred())   # deferred: OK takes the field out of the tree, and the field is still handling its Enter
	return le


func _build_timeline() -> void:
	tl = PanelContainer.new()
	tl.name = "part_timeline"
	tl.add_theme_stylebox_override("panel", _panel_style(false))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	tl.add_child(hb)
	var nav := VBoxContainer.new()
	nav.add_child(_label("TIMELINE", 11, true))
	var nb := HBoxContainer.new()
	for e in [["<<", "first step", "part_first"], ["<", "one step back", "part_back"], [">", "one step on", "part_next"], [">>", "every step", "part_last"]]:
		var b := Button.new()
		b.name = e[2]
		b.text = e[0]
		b.tooltip_text = "marker: " + e[1]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(28, 0)
		b.pressed.connect(_marker.bind(e[2]))
		nb.add_child(b)
	part_give = Button.new()   # PartWeapon (scripts/build/part_weapon.gd): this part becomes the fighter's weapon, one undo step
	part_give.name = "part_give"
	part_give.text = "Give to fighter"
	part_give.focus_mode = Control.FOCUS_NONE
	part_give.tooltip_text = "Give it to the fighter: he holds this part as his weapon; its size, weight and balance come from the part (steel unless you change the material)"
	part_give.pressed.connect(func(): m.give_part_weapon(_rec()))
	nb.add_child(part_give)
	nav.add_child(nb)
	hb.add_child(nav)
	hb.add_child(VSeparator.new())
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tl_row = HBoxContainer.new()
	tl_row.name = "part_steps"
	tl_row.add_theme_constant_override("separation", 6)
	sc.add_child(tl_row)
	hb.add_child(sc)
	tl_info = _label("", 12, true)
	tl_info.name = "part_timeline_info"
	tl_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tl_info.custom_minimum_size.x = 150
	hb.add_child(tl_info)
	tl.visible = false
	m.ui_root.add_child(tl)


# ---------------------------------------------------------------- state

func _rec() -> Dictionary:
	return m.S.part


func _ensure() -> Dictionary:
	if m.S.part.is_empty():
		m.S.part = Part.make(String(m.S.name) if String(m.S.name) != "" else "Part")
	return m.S.part


func _feats() -> Array:
	return _rec().get("features", [])


func _sk() -> Dictionary:
	return Part.feature(_rec(), sk) if sk != "" else {}


func _say(t: String) -> void:
	status = t
	m._say(t)


func toggle() -> void:
	set_on(part_btn.button_pressed)


func set_on(v: bool) -> void:
	if v == on:
		return
	if not v:
		finish_sketch()
		close_dialog()
		tool = ""
		pair_pick = {}
		play_on = false
		pose = {}
	on = v
	part_btn.set_pressed_no_signal(v)
	if v:
		_view_model()
		_say("PART: sketch on a plane (Line, Rectangle, Circle), then Extrude or Revolve. Every step is on the timeline below.")
	bu.sync()


func _pick(t: String) -> void:
	if not Part.available():
		_tool_sync()
		return
	if t in SKETCH_TOOLS:
		if dlg.size() > 0:
			close_dialog()
		if sk == "":
			begin_sketch("front")
	elif sk != "":
		finish_sketch()
	tool = t
	draft = {}
	typed = ""
	dim_target = {}
	dim_edit.visible = false
	picked = []
	if t in CREATE_TOOLS or t in MODIFY_TOOLS or t in HINGE_TOOLS:
		open_dialog(t, -1)
	else:
		if dlg.size() > 0:
			close_dialog()
	_tool_sync()
	pov.queue_redraw()
	_say(TIPS[t])


# ---------------------------------------------------------------- sketches

func begin_sketch(plane_name: String, edit_id := "") -> void:
	if sk != "":
		finish_sketch()
	close_dialog()
	var rec := _ensure()
	_sk_n = m.undo.size()
	_sk_before = JSON.stringify(rec)
	if edit_id == "":
		m._step_hint = "Sketch"
		m._push_undo()
		var f := Part.new_feature(rec, "sketch", {"plane": plane_name, "ents": [], "dims": []})
		rec["features"].append(f)
		upto = -1
		sk = String(f["id"])
	else:
		m._step_hint = "Edit " + String(Part.feature(rec, edit_id).get("name", "sketch"))
		m._push_undo()
		sk = edit_id
		plane_name = String(Part.feature(rec, edit_id).get("plane", "front"))
	draft = {}
	typed = ""
	_view_plane(plane_name)
	_say("%s on the %s. Draw with Line, Rectangle, Circle or Arc, then Dimension it." % [String(_sk().get("name", "Sketch")), Part.plane_words(rec, plane_name)])
	bu.sync()


func finish_sketch() -> void:
	if sk == "":
		return
	var f := _sk()
	var rec := _rec()
	if f.is_empty():
		sk = ""   # the sketch is gone (a new scene, an undo): nothing of it to finish, and no undo step of ours to take back
		draft = {}
		return
	var nm := String(f.get("name", "Sketch"))
	var empty: bool = f.is_empty() or (f["ents"] as Array).is_empty()
	if empty and not f.is_empty():
		rec["features"].remove_at(Part.index_of(rec, sk))   # an empty sketch is no step
	if m.undo.size() == _sk_n + 1 and (empty or JSON.stringify(rec) == _sk_before):
		m._drop_undo()   # nothing changed: the step it began is taken back out
	if rec.has("features") and (rec["features"] as Array).is_empty():
		m.S.part = {}
	sk = ""
	draft = {}
	typed = ""
	dim_target = {}
	dim_edit.visible = false
	if tool in SKETCH_TOOLS:
		tool = ""
	_say("%s finished%s" % [nm, "" if not empty else " (it was empty, so it is not a step)"])
	_view_model()
	bu.sync()


func _plane() -> Dictionary:
	return Part.resolve_plane(_rec(), String(_sk().get("plane", "front")))


## the sketch plane point (mm) under a screen point, or null
func hit(p: Vector2) -> Variant:
	var pl := _plane()
	var ro: Vector3 = m.cam.project_ray_origin(p)
	var rd: Vector3 = m.cam.project_ray_normal(p)
	var n: Vector3 = pl["n"]
	var den := rd.dot(n)
	if absf(den) < 1e-6:
		return null
	var t := ((pl["o"] as Vector3) - ro).dot(n) / den
	if t < 0.0:
		return null
	return Part.to_plane(pl, ro + rd * t)


func snap(v: Vector2) -> Vector2:
	if Input.is_key_pressed(KEY_ALT) or snap_mm <= 0.0:
		return v
	return Vector2(snappedf(v.x, snap_mm), snappedf(v.y, snap_mm))


func scr(v: Vector2) -> Vector2:
	return m.cam.unproject_position(Part.to_world(_plane(), v))


func _add_ent(e: Dictionary) -> void:
	_sk()["ents"].append(e)
	_after_sketch_edit()


func _after_sketch_edit() -> void:
	_nums_sync()
	_note_sync()
	pov.queue_redraw()


func _close_chain() -> void:
	if String(draft.get("k", "")) == "spline" and (draft.get("pts", []) as Array).size() >= 3:
		_spline_add(false)   # an open curve of three or more points is kept
		return
	draft = {}
	typed = ""
	pov.queue_redraw()


# ---------------------------------------------------------------- input (BuildUI.input hands every event here while the workspace is on)

func input(ev: InputEvent) -> bool:
	if easy:
		return ep.input(ev)
	if not Part.available():
		return false
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			return _press(mb.position) if mb.pressed else _release(mb.position)
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and not draft.is_empty():
			_close_chain()
			return true
		return false
	if ev is InputEventMouseMotion:
		return _motion((ev as InputEventMouseMotion).position)
	if ev is InputEventKey and (ev as InputEventKey).pressed:
		return _key(ev as InputEventKey)
	return false


func _press(p: Vector2) -> bool:
	if sk != "":
		return _press_sketch(p)
	if dlg.get("t", "") == "canvas":
		return _canvas_press(p)   # GAP 3: the canvas dialog's clicks (two points) and drags
	if dlg.is_empty() and tool == "" and _canvas_grab(p):
		return true
	if not pair_pick.is_empty():
		return _pair_press(p)
	if tool == "Hinge" and dlg.get("t", "") == "hinge":
		return _hinge_press(p)
	if tool == "Fillet" or tool == "Chamfer":
		var i := _pick_edge(p)
		if i >= 0:
			var e: Dictionary = edge_cache[i]
			var at := -1
			for j in picked.size():
				if (picked[j]["c"] as Vector3).distance_to(e["c"]) < 1e-6:
					at = j
			if at >= 0:
				picked.remove_at(at)
			else:
				picked.append(e)
			_preview()
			pov.queue_redraw()
		return true
	return false


func _press_sketch(p: Vector2) -> bool:
	var h: Variant = hit(p)
	if h == null:
		return true
	var a := snap(h as Vector2)
	if tool == "Spline" and draft.is_empty():
		var hp := _spline_point_at(p)
		if not hp.is_empty():
			spl_drag = hp   # a point of a curve on the sheet: drag it (the release keeps it)
			return true
	match tool:
		"Spline":
			_spline_click(p, a)
		"Line":
			if draft.is_empty():
				draft = {"k": "line", "a": a, "b": a, "start": a}
			else:
				var b: Vector2 = a
				if (draft["a"] as Vector2).distance_to(b) < 0.5:
					return true
				_add_ent({"k": "line", "a": Part.arr2(draft["a"]), "b": Part.arr2(b)})
				if b.distance_to(draft["start"]) < 0.5:
					_close_chain()
				else:
					draft["a"] = b
					draft["b"] = b
					typed = ""
		"Rectangle", "Circle":
			if not draft.is_empty() and not draft.get("down", true):
				draft["b"] = a
				_commit_draft()
			else:
				draft = {"k": "rect" if tool == "Rectangle" else "circle", "a": a, "b": a, "down": true}
		"Arc":
			var pts: Array = draft.get("pts", [])
			pts.append(a)
			if pts.size() == 3:
				_add_ent({"k": "arc", "a": Part.arr2(pts[0]), "b": Part.arr2(pts[1]), "m": Part.arr2(pts[2])})
				draft = {}
			else:
				draft = {"k": "arc", "pts": pts, "b": a}
		"Dimension":
			var pk := pick_ent(p)
			if pk.is_empty() or pk["kind"] == "":
				_say("DIMENSION: click a line, an edge of a rectangle or a circle")
			else:
				dim_target = pk
				_open_dim_edit(pk)
	pov.queue_redraw()
	return true


func _release(p: Vector2) -> bool:
	if not cv_drag.is_empty():
		return _canvas_release()
	if not spl_drag.is_empty():
		spl_drag = {}
		pov.queue_redraw()
		return true
	if sk == "" or draft.is_empty() or not draft.get("down", false):
		return false
	var h: Variant = hit(p)
	if h != null:
		draft["b"] = snap(h as Vector2)
	if (draft["a"] as Vector2).distance_to(draft["b"]) < maxf(snap_mm * 0.9, 0.5):
		draft["down"] = false   # a click, not a drag: the second click is the other corner
	else:
		_commit_draft()
	pov.queue_redraw()
	return true


func _commit_draft() -> void:
	var a: Vector2 = draft["a"]
	var b: Vector2 = draft["b"]
	if draft["k"] == "rect":
		if absf(a.x - b.x) > 0.01 and absf(a.y - b.y) > 0.01:
			_add_ent({"k": "rect", "a": Part.arr2(a), "b": Part.arr2(b)})
	elif a.distance_to(b) > 0.01:
		_add_ent({"k": "circle", "c": Part.arr2(a), "r": snappedf(a.distance_to(b), 0.0001)})
	draft = {}


func _motion(p: Vector2) -> bool:
	if not cv_drag.is_empty():
		_canvas_move(p)
		return false
	if sk != "":
		var h: Variant = hit(p)
		if not spl_drag.is_empty():
			if h != null:
				var pts: Array = _sk()["ents"][int(spl_drag["ent"])]["pts"]
				pts[int(spl_drag["pt"])] = Part.arr2(snap(h as Vector2))
				pov.queue_redraw()
			return false
		if h != null and not draft.is_empty():
			draft["b"] = snap(h as Vector2)
		if tool == "Dimension":
			hover_ent = pick_ent(p)
		pov.queue_redraw()
		return false
	if tool == "Fillet" or tool == "Chamfer":
		var i := _pick_edge(p)
		if i != hover_edge:
			hover_edge = i
			pov.queue_redraw()
	return false


func _key(k: InputEventKey) -> bool:
	if not pair_pick.is_empty() and k.keycode == KEY_ESCAPE:
		pair_pick = {}
		_hinge_sync()
		_say("Must not touch: cancelled.")
		return true
	if sk != "" and tool == "Line" and not draft.is_empty():
		var ch := ""
		if k.keycode >= KEY_0 and k.keycode <= KEY_9:
			ch = str(k.keycode - KEY_0)
		elif k.keycode >= KEY_KP_0 and k.keycode <= KEY_KP_9:
			ch = str(k.keycode - KEY_KP_0)
		elif k.keycode in [KEY_PERIOD, KEY_KP_PERIOD]:
			ch = "."
		if ch != "":
			typed += ch
			pov.queue_redraw()
			return true
		if k.keycode == KEY_BACKSPACE and typed != "":
			typed = typed.left(-1)
			pov.queue_redraw()
			return true
		if k.keycode in [KEY_ENTER, KEY_KP_ENTER] and typed.is_valid_float() and float(typed) > 0.0:
			var a: Vector2 = draft["a"]
			var dir: Vector2 = (draft["b"] as Vector2) - a
			dir = dir.normalized() if dir.length() > 1e-6 else Vector2.RIGHT
			var b := a + dir * float(typed)
			_add_ent({"k": "line", "a": Part.arr2(a), "b": Part.arr2(b)})
			draft["a"] = b
			draft["b"] = b
			typed = ""
			return true
	if k.keycode == KEY_ESCAPE:
		if not draft.is_empty():
			_close_chain()
			return true
		if dim_edit.visible:
			dim_edit.visible = false
			return true
		if dlg.size() > 0:
			close_dialog()
			return true
		if tool != "":
			tool = ""
			_tool_sync()
			return true
	if sk != "" and draft.is_empty() and k.keycode in [KEY_DELETE, KEY_BACKSPACE] and not _sk()["ents"].is_empty():
		var ents: Array = _sk()["ents"]
		ents.pop_back()
		var dims: Array = _sk().get("dims", [])
		_sk()["dims"] = dims.filter(func(d): return int(d["ent"]) < ents.size())
		_after_sketch_edit()
		return true
	return false


# ---------------------------------------------------------------- picking

## the sketch entity edge nearest a screen point: {"ent", "kind", "a", "b"} or {} (within 10 px)
func pick_ent(p: Vector2) -> Dictionary:
	var best := {}
	var best_d := 10.0
	var ents: Array = _sk().get("ents", [])
	for i in ents.size():
		var e: Dictionary = ents[i]
		var segs := []   # [[a mm, b mm, kind]]
		match String(e["k"]):
			"rect":
				var a := Part.v2(e["a"])
				var b := Part.v2(e["b"])
				var c := [a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)]
				for j in 4:
					segs.append([c[j], c[(j + 1) % 4], "w" if j % 2 == 0 else "h"])
			"line":
				segs.append([Part.v2(e["a"]), Part.v2(e["b"]), "len"])
			"circle":
				var c := Part.v2(e["c"])
				var r := float(e["r"])
				for j in 48:
					segs.append([c + Vector2.from_angle(TAU * j / 48.0) * r, c + Vector2.from_angle(TAU * (j + 1) / 48.0) * r, "r"])
			"arc":
				segs.append([Part.v2(e["a"]), Part.v2(e["m"]), ""])
				segs.append([Part.v2(e["m"]), Part.v2(e["b"]), ""])
			"bspline":
				var sp: Array = e["pts"]
				for j in sp.size() - 1 + (1 if bool(e.get("closed", false)) else 0):
					segs.append([Part.v2(sp[j]), Part.v2(sp[(j + 1) % sp.size()]), ""])
		for sg in segs:
			var q := Geometry2D.get_closest_point_to_segment(p, scr(sg[0]), scr(sg[1]))
			var d := p.distance_to(q)
			if d < best_d:
				best_d = d
				best = {"ent": i, "kind": sg[2], "a": sg[0], "b": sg[1]}
	return best


## the index in edge_cache of the model edge nearest a screen point (within 12 px), or -1
func _pick_edge(p: Vector2) -> int:
	var best := -1
	var best_d := 12.0
	for i in edge_cache.size():
		var e: Dictionary = edge_cache[i]
		var a: Vector3 = e["a"]
		var b: Vector3 = e["b"]
		if m.cam.is_position_behind(e["c"]):
			continue
		var pa: Vector2 = m.cam.unproject_position(a)
		var pb: Vector2 = m.cam.unproject_position(b)
		var pc: Vector2 = m.cam.unproject_position(e["c"])
		var d := 1e9
		if a.distance_to(b) > 1e-6:
			d = minf(p.distance_to(Geometry2D.get_closest_point_to_segment(p, pa, pb)), p.distance_to(pc))
		else:
			d = p.distance_to(pc)   # a closed curve: its middle point
		if d < best_d:
			best_d = d
			best = i
	return best


# ---------------------------------------------------------------- dimensions

func _open_dim_edit(pk: Dictionary) -> void:
	var e: Dictionary = _sk()["ents"][int(pk["ent"])]
	dim_edit.text = "%s" % snappedf(Part.measure(e, String(pk["kind"])), 0.001)
	for d in _sk().get("dims", []):
		if int(d["ent"]) == int(pk["ent"]) and d["kind"] == pk["kind"] and d.has("bind"):
			dim_edit.text = Part.bind_text(d["bind"])   # a bound size shows its bind, so Enter keeps it
	dim_edit.visible = true
	var mid: Vector2 = (scr(pk["a"]) + scr(pk["b"])) * 0.5
	dim_edit.reset_size()
	dim_edit.position = mid + Vector2(-48, 14)
	dim_edit.grab_focus()
	dim_edit.select_all()
	_say("Type the size in mm and press Enter")


func _dim_submitted(t: String) -> void:
	dim_edit.visible = false
	if dim_target.is_empty() or sk == "":
		return
	var err := _set_dim_text(int(dim_target["ent"]), String(dim_target["kind"]), t)
	if err != "":
		_say(err)
	elif Part.parse_bind(t).is_empty():
		_say("Dimension set: %s mm" % t.replace("mm", "").strip_edges())
	else:
		_say("Dimension set: %s" % Part.bind_text(Part.parse_bind(t)))
	dim_target = {}
	dim_edit.release_focus()
	_after_sketch_edit()


## C2: the body's segment lengths now (the scene's body; the default body when it is {})
func _body_measures() -> Dictionary:
	return Proportions.measures_of(m.S.body)


## a dimension's typed text: a size in mm (plain: the dimension stops reading the body) or =forearm+4 (reads the body).
## Returns the message to show ("" = set)
func _set_dim_text(ent: int, kind: String, t: String) -> String:
	var v := t.replace("mm", "").strip_edges()
	var bind := Part.parse_bind(v)
	if not bind.is_empty():
		var r := Part.bound_mm(bind, _body_measures())
		if r["err"] != "":
			return String(r["err"])
		Part.set_dim(_sk(), ent, kind, float(r["mm"]), bind)
		return ""
	if v.is_valid_float() and float(v) > 0.0:
		Part.set_dim(_sk(), ent, kind, float(v))
		return ""
	return "type a size in mm, or =forearm+4 to read the body (forearm, upper_arm, thigh, shank, trunk, head ...)"


## the number a row shows: the size now (a bound one: what the body gives)
func _dim_field_text(d: Dictionary) -> String:
	if d.has("bind"):
		var r := Part.bound_mm(d["bind"], _body_measures())
		return Part.bind_text(d["bind"]) if r["err"] != "" else "%s mm" % _fmt(float(r["mm"]))
	return "%s mm" % _fmt(float(d["mm"]))


func _set_dim_value(i: int, v: float) -> void:
	var dims: Array = _sk().get("dims", [])
	if i >= dims.size() or v <= 0.0 or (absf(float(dims[i]["mm"]) - v) < 1e-9 and not dims[i].has("bind")):   # a bound size typed as a plain number stops reading the body
		return
	Part.set_dim(_sk(), int(dims[i]["ent"]), String(dims[i]["kind"]), v)
	_after_sketch_edit()


# ---------------------------------------------------------------- feature dialogs

func open_dialog(t: String, edit: int) -> void:
	var rec := _ensure()
	var f: Dictionary = {}
	if edit >= 0:
		f = (rec["features"][edit] as Dictionary).duplicate(true)
	dlg = {"t": String(TOOL_KIND.get(t, t.to_lower())), "edit": edit}
	_clear_rows()
	picked = []
	var kind := String(dlg["t"])
	if kind == "loft":
		dlg["sketches"] = (f.get("sketches", []) as Array).duplicate() if edit >= 0 else []
		dlg["pick"] = _sketch_ids(rec)
		dlg_rows.add_child(f_prof)
		dlg_rows.add_child(f_edges)
		dlg_rows.add_child(f_prof_clear)
		_prof_sync()
		dlg_rows.add_child(f_ruled)
		f_ruled.select(0 if bool(f.get("ruled", true)) else 1)
		_op_row(f)
	elif kind == "plane":
		_row("Distance", f_num, "%s mm" % _fmt(float(f.get("mm", 20.0))))
		dlg_rows.add_child(f_plane)
		f_plane.select(PlanesIdx.find(String(f.get("from", "front"))))
	if kind == "extrude" or kind == "revolve":
		var sid: String = String(f.get("sketch", "")) if edit >= 0 else Part.profile_sketch(rec)
		dlg["sketch"] = sid
		dlg_rows.add_child(_label("Profile:  %s" % String(Part.feature(rec, sid).get("name", "none"))))
	if kind == "extrude":
		_row("Distance", f_num, "%s mm" % _fmt(float(f.get("dist", 10.0))))
		f_both.set_pressed_no_signal(bool(f.get("both", false)))
		dlg_rows.add_child(f_both)
		_row("Taper angle", f_taper, "%s deg" % _fmt(float(f.get("taper", 0.0))))
		_op_row(f)
	elif kind == "revolve":
		dlg_rows.add_child(f_axis)
		f_axis.select(0 if String(f.get("axis", "x")) == "x" else 1)
		_row("Angle", f_ang, "%s deg" % _fmt(float(f.get("deg", 360.0))))
		_op_row(f)
	elif kind == "fillet" or kind == "chamfer":
		_base_edges(edit)
		dlg_rows.add_child(f_edges)
		_row("Radius" if kind == "fillet" else "Distance", f_num, "%s mm" % _fmt(float(f.get("r" if kind == "fillet" else "dist", 2.0 if kind == "fillet" else 1.0))))
		if edit >= 0:
			for d in f.get("edges", []):
				var j := _match_cache(d)
				if j >= 0 and not picked.has(edge_cache[j]):
					picked.append(edge_cache[j])
		if edit < 0 and not _feats().is_empty() and res.get("bodies", 0) == 0:
			dlg_info.text = "Nothing to round yet."
	elif kind == "hinge":
		_hinge_open(f, edit)
	elif kind == "mirror":
		dlg_rows.add_child(f_plane)
		f_plane.select(PlanesIdx.find(String(f.get("plane", "right"))))
		_op_row(f)
	elif kind == "split":
		dlg_rows.add_child(f_plane)
		f_plane.select(PlanesIdx.find(String(f.get("plane", "right"))))
		_row("Offset along its normal", f_num, "%s mm" % _fmt(float(f.get("at", 0.0))))
	elif kind == "canvas":
		pass   # its rows: _canvas_open
	elif kind == "shell":
		_row("Wall thickness", f_num, "%s mm" % _fmt(float(f.get("thick", 5.0))))
		dlg_rows.add_child(f_open)
		f_open.select(maxi(SHELL_OPEN.find(String(f.get("open", "+y"))), 0))
	if kind == "canvas":
		_canvas_open(f, edit)
	f_op.visible = kind in ["extrude", "revolve", "loft"]
	if kind == "hinge":
		_hinge_rows()
	side_title.text = ("EDIT " if edit >= 0 else "") + kind.to_upper()
	_preview()
	_tool_sync()
	bu.sync()
	for fe in [f_num, f_ang]:
		if fe.is_inside_tree() and fe.get_parent() != null:
			fe.grab_focus()
			fe.select_all()
			break


const PlanesIdx := ["front", "top", "right"]


## the sketches a loft can take, by id (the order of the picker's items after its first "Add a sketch..." row)
func _sketch_ids(rec: Dictionary) -> Array:
	var out := []
	for f in rec.get("features", []):
		if f["t"] == "sketch":
			out.append(String(f["id"]))
	return out


## the loft's picker and profile list: "Add a sketch..." then each sketch; the picked ones are named in order
func _prof_sync() -> void:
	var rec := _rec()
	var names := []
	for sid in dlg.get("sketches", []):
		names.append(String(Part.feature(rec, String(sid)).get("name", sid)))
	f_edges.text = "Profiles:  %s" % (" , ".join(names) if not names.is_empty() else "none yet (pick two or more)")
	f_prof.clear()
	f_prof.add_item("Add a sketch...")
	for sid in dlg.get("pick", []):
		f_prof.add_item(String(Part.feature(rec, String(sid)).get("name", sid)))
	f_prof.select(0)


func _prof_picked(i: int) -> void:
	var pick: Array = dlg.get("pick", [])
	if i > 0 and i - 1 < pick.size() and dlg.get("t", "") == "loft":
		var sid := String(pick[i - 1])
		var ids: Array = dlg["sketches"]
		if not ids.has(sid):
			ids.append(sid)
	_prof_sync()
	_preview()


## the dialog's rows go; the field controls are kept (they are re-parented into the next dialog)
func _clear_rows() -> void:
	for c in [f_num, f_ang, f_both, f_op, f_axis, f_plane, f_taper, f_open, f_edges, f_from, f_to, f_dur, f_dial, f_prof, f_prof_clear, f_ruled]:
		if (c as Node).get_parent() != null:
			(c as Node).get_parent().remove_child(c)
	for c in dlg_rows.get_children():
		dlg_rows.remove_child(c)
		c.queue_free()


func _fmt(v: float) -> String:
	return str(snappedf(v, 0.001))


func _row(label: String, le: LineEdit, txt: String) -> void:
	var h := HBoxContainer.new()
	var l := _label(label)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	le.text = txt.get_slice(" ", 0)
	h.add_child(le)
	h.add_child(_label(txt.get_slice(" ", 1), 13, true))
	dlg_rows.add_child(h)


func _op_row(f: Dictionary) -> void:
	if String(dlg["t"]) == "extrude" or String(dlg["t"]) == "revolve" or String(dlg["t"]) == "loft":
		var h := HBoxContainer.new()
		var l := _label("Operation")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		f_op.select(maxi(Part.OPS.find(String(f.get("op", "join" if not _feats().is_empty() and res.get("bodies", 0) > 0 else "new"))), 0))
		h.add_child(f_op)
		dlg_rows.add_child(h)


## the model the dialog works on (the steps before the one being edited): its volume, bodies and edges
func _base_edges(edit: int) -> void:
	var base := Part.replay(_rec(), edit - 1 if edit >= 0 else upto, {"edges": true, "body": _body_measures()})
	edge_cache = base["edges"]


func _match_cache(d: Dictionary) -> int:
	var q := Vector3(float(d["q"][0]), float(d["q"][1]), float(d["q"][2]))
	var dir := Vector3(float(d["d"][0]), float(d["d"][1]), float(d["d"][2]))
	var best := -1
	var best_s := Part.MATCH_MAX
	for i in edge_cache.size():
		var s: float = (edge_cache[i]["q"] as Vector3).distance_to(q) + 0.5 * (1.0 - absf((edge_cache[i]["d"] as Vector3).dot(dir)))
		if s < best_s:
			best_s = s
			best = i
	return best


func _num(le: LineEdit) -> float:
	var t := le.text.replace("mm", "").replace("deg", "").strip_edges()
	return float(t) if t.is_valid_float() else NAN


## the feature the open dialog describes now ({} when its numbers do not make sense)
func dialog_feature() -> Dictionary:
	if dlg.is_empty():
		return {}
	var rec := _ensure()
	var kind := String(dlg["t"])
	var edit := int(dlg["edit"])
	var f := {}
	var op: String = Part.OPS[clampi(f_op.selected, 0, Part.OPS.size() - 1)]
	match kind:
		"extrude":
			var d := _num(f_num)
			if is_nan(d) or absf(d) < 1e-6 or String(dlg.get("sketch", "")) == "":
				return {}
			var tp := _num(f_taper)
			f = {"sketch": dlg["sketch"], "dist": d, "both": f_both.button_pressed, "op": op, "taper": 0.0 if is_nan(tp) else tp}
		"revolve":
			var a := _num(f_ang)
			if is_nan(a) or absf(a) < 1e-6 or String(dlg.get("sketch", "")) == "":
				return {}
			f = {"sketch": dlg["sketch"], "axis": "x" if f_axis.selected == 0 else "y", "deg": a, "op": op}
		"fillet", "chamfer":
			var r := _num(f_num)
			if is_nan(r) or r <= 0.0 or picked.is_empty():
				return {}
			var ds := []
			for e in picked:
				ds.append(Part.describe(e))
			f = {"body": int(ds[0]["body"]), "edges": ds}
			f["r" if kind == "fillet" else "dist"] = r
		"mirror":
			f = {"plane": PlanesIdx[clampi(f_plane.selected, 0, 2)], "op": "join"}
		"split":
			var at := _num(f_num)
			if is_nan(at):
				return {}
			f = {"plane": PlanesIdx[clampi(f_plane.selected, 0, 2)], "at": at}
		"shell":
			var th := _num(f_num)
			if is_nan(th) or th <= 0.0:
				return {}
			f = {"body": maxi(int(res.get("bodies", 0)) - 1, 0), "thick": th, "open": SHELL_OPEN[clampi(f_open.selected, 0, SHELL_OPEN.size() - 1)]}
		"loft":
			var ids: Array = dlg.get("sketches", [])
			if ids.size() < 2:
				return {}
			f = {"sketches": ids.duplicate(), "ruled": f_ruled.selected == 0, "op": op}
		"canvas":
			f = _canvas_feature(true)
			if f.is_empty():
				return {}
		"plane":
			var pd := _num(f_num)
			if is_nan(pd) or absf(pd) < 1e-6:
				return {}
			f = {"from": PlanesIdx[clampi(f_plane.selected, 0, 2)], "mm": pd}
		"hinge":
			var a0 := _num(f_from)
			var a1 := _num(f_to)
			var du := _num(f_dur)
			if int(hp.get("body", -1)) < 0 or not hp.has("d") or is_nan(a0) or is_nan(a1) or is_nan(du) or du <= 0.0 or absf(a1 - a0) < 1e-6:
				return {}
			var o: Vector3 = hp["o"]
			var d: Vector3 = hp["d"]
			var keep: Array = []
			if edit >= 0:
				keep = (rec["features"][edit] as Dictionary).get("clear", [])
			f = {"body": int(hp["body"]), "o": [o.x / Part.MM, o.y / Part.MM, o.z / Part.MM], "axis": [d.x, d.y, d.z], "track": [[0.0, a0], [du, a1]], "clear": keep}
	if edit >= 0:
		var old: Dictionary = rec["features"][edit]
		f["id"] = old["id"]
		f["name"] = old["name"]
		f["t"] = kind
		return f
	var nf := Part.new_feature(rec.duplicate(true), kind, f)
	nf["id"] = "f%d" % (int(rec.get("seq", 0)) + 1)
	return nf


func _preview() -> void:
	if dlg.is_empty():
		return
	var kind := String(dlg["t"])
	if f_edges != null and (kind == "fillet" or kind == "chamfer"):
		f_edges.text = "Edges:  %s" % ("%d picked" % picked.size() if not picked.is_empty() else "click an edge")
	var f := dialog_feature()
	prev = {}
	if f.is_empty():
		dlg_info.text = _dialog_hint(kind)
		ok_btn.disabled = true
		prev_mesh.visible = false
		part_mesh.visible = on and sk == "" and part_mesh.mesh != null
		return
	var rec := (_rec().duplicate(true))
	var edit := int(dlg["edit"])
	if edit >= 0:
		rec["features"][edit] = f
	else:
		rec["features"].append(f)
	prev = Part.replay(rec, -1, {"body": _body_measures()})
	var err: String = prev["errors"].get(String(f["id"]), "")
	dlg_info.text = ("%s. Nothing is changed until it works." % err) if err != "" else "Volume %s cm3" % snappedf(float(prev["volume"]) * 1e6, 0.01)
	ok_btn.disabled = err != ""
	prev_mesh.mesh = prev["mesh"]
	prev_mesh.visible = prev["mesh"] != null
	part_mesh.visible = false
	pov.queue_redraw()


func _dialog_hint(kind: String) -> String:
	if kind == "extrude" or kind == "revolve":
		return "Sketch a closed profile first, then type a number." if String(dlg.get("sketch", "")) == "" else "Type a number."
	if kind == "fillet" or kind == "chamfer":
		return "Click an edge on the model, then type a size."
	if kind == "shell":
		return "Type a wall thickness (mm), then press Enter."
	if kind == "hinge":
		return _hinge_next()
	if kind == "loft":
		return "Pick two or more sketches, in order."
	if kind == "plane":
		return "Type the distance from the plane (mm)."
	if kind == "canvas":
		return _canvas_hint()
	return ""


func ok_pressed() -> void:
	if dlg.is_empty():
		return
	var f := dialog_feature()
	if f.is_empty():
		_say("Nothing to make yet: %s" % _dialog_hint(String(dlg["t"])))
		return
	var err: String = prev.get("errors", {}).get(String(f["id"]), "") if not prev.is_empty() else ""
	if err != "":
		_say("%s: %s" % [String(f["name"]), err])
		return
	var rec := _ensure()
	var edit := int(dlg["edit"])
	m._step_hint = ("Edit " if edit >= 0 else "") + String(f["name"])
	m._push_undo()
	if edit >= 0:
		rec["features"][edit] = f
	else:
		rec["features"].append(f)
		rec["seq"] = int(rec.get("seq", 0)) + 1   # the id dialog_feature() gave it
		upto = -1
	_say("%s made. It is a step on the timeline; double-click it to change it." % String(f["name"]))
	var kind := String(dlg["t"])
	if kind == "hinge" and edit < 0:
		sel_step = _feats().size() - 1   # the new hinge: its panel (Play, must not touch) opens
	close_dialog()
	tool = ""
	_tool_sync()
	bu.sync()
	if kind == "extrude" or kind == "revolve" or kind == "loft":
		_view_model()


func close_dialog() -> void:
	if dlg.is_empty():
		return
	dlg = {}
	picked = []
	prev = {}
	prev_mesh.visible = false
	_clear_rows()
	if tool in CREATE_TOOLS or tool in MODIFY_TOOLS or tool in HINGE_TOOLS:
		tool = ""
	_tool_sync()
	_rec_sig = ""
	bu.sync()


# ---------------------------------------------------------------- timeline and browser

func _marker(which: String) -> void:
	var n := _feats().size()
	if n == 0:
		return
	var cur := n - 1 if upto < 0 else upto
	match which:
		"part_first":
			cur = 0
		"part_back":
			cur = maxi(cur - 1, 0)
		"part_next":
			cur = mini(cur + 1, n - 1)
		"part_last":
			cur = n - 1
	upto = -1 if cur >= n - 1 else cur
	bu.sync()


func step_clicked(i: int) -> void:
	var now := Time.get_ticks_msec()
	if i == _last_step and now - _last_ms < DOUBLE_MS:
		_last_step = -1
		edit_step(i)
		return
	_last_step = i
	_last_ms = now
	sel_step = i
	bu.sync()


func edit_step(i: int) -> void:
	var f: Dictionary = _feats()[i]
	if sk != "":
		finish_sketch()
	close_dialog()
	if f["t"] == "sketch":
		tool = ""
		begin_sketch(String(f["plane"]), String(f["id"]))
	else:
		tool = "Offset plane" if f["t"] == "plane" else String(f["t"]).capitalize()
		open_dialog(tool, i)
	_say("Editing step %d of %d: the later steps update when you finish." % [i + 1, _feats().size()])


func _step_icon(f: Dictionary) -> String:
	return "part_" + String(f["t"]) if String(f["t"]) != "sketch" else "part_sketch"


func _timeline_sync() -> void:
	var feats := _feats()
	var errs: Dictionary = res.get("errors", {})
	var sig := JSON.stringify([feats.map(func(f): return [f["id"], f["name"]]), upto, sel_step, sk, dlg.get("edit", -2), errs.keys()])
	if sig != _tl_sig:
		_tl_sig = sig
		for c in tl_row.get_children():
			tl_row.remove_child(c)
			c.queue_free()
		tl_btns = []
		for i in feats.size():
			var f: Dictionary = feats[i]
			var vb := VBoxContainer.new()
			vb.add_theme_constant_override("separation", 0)
			var b := Button.new()
			b.name = "part_step_%d" % i
			b.icon = Icons.tex(_step_icon(f))
			b.custom_minimum_size = Vector2(44, 40)
			b.focus_mode = Control.FOCUS_NONE
			b.toggle_mode = true
			b.button_pressed = i == sel_step or (sk != "" and String(f["id"]) == sk) or (int(dlg.get("edit", -1)) == i)
			b.tooltip_text = "%s. Double-click to change it; the steps after it replay." % f["name"]
			b.pressed.connect(step_clicked.bind(i))
			var failed: bool = errs.has(String(f["id"]))
			var beyond: bool = upto >= 0 and i > upto
			b.modulate = Color(1, 0.55, 0.5) if failed else (Color(1, 1, 1, 0.35) if beyond else Color.WHITE)
			if failed:
				b.tooltip_text += " Failed: " + String(errs[String(f["id"])])
			vb.add_child(b)
			var l := _label(String(f["name"]), 11, true)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			vb.add_child(l)
			tl_row.add_child(vb)
			tl_btns.append(b)
	var n := feats.size()
	if int(dlg.get("edit", -1)) >= 0:
		tl_info.text = "Editing step %d of %d\nlater steps update when you finish" % [int(dlg["edit"]) + 1, n]
	elif sk != "":
		var si := Part.index_of(_rec(), sk)
		tl_info.text = "Editing step %d of %d\nlater steps update when you finish" % [si + 1, n] if si < n - 1 else "Sketching (step %d of %d)" % [si + 1, n]
	elif upto >= 0:
		tl_info.text = "Marker at step %d of %d\nnew steps go at the end" % [upto + 1, n]
	else:
		tl_info.text = "%d step%s" % [n, "" if n == 1 else "s"] if n > 0 else "No steps yet"


func _browser_sync() -> void:
	var feats := _feats()
	var sig := JSON.stringify([feats.map(func(f): return [f["id"], f["name"], f["t"], f.get("mm", 0), f.get("from", ""), f.get("show", "")]), sk, res.get("bodies", 0), prev.is_empty()])
	if sig == _browser_sig:
		return
	_browser_sig = sig
	for c in browser_vb.get_children():
		browser_vb.remove_child(c)
		c.queue_free()
	browser_vb.add_child(_label("BROWSER", 11, true))
	var nb: int = res.get("bodies", 0)
	browser_vb.add_child(_label("Bodies (%d)" % nb, 15))
	for i in nb:
		var l := _label("    Body%d" % (i + 1), 14)
		l.name = "part_body_%d" % i
		browser_vb.add_child(l)
	var sketches := feats.filter(func(f): return f["t"] == "sketch")
	browser_vb.add_child(_label("Sketches (%d)" % sketches.size(), 15))
	for f in sketches:
		var b := _row_btn("    " + String(f["name"]), "part_sketch_" + String(f["id"]))
		if String(f["id"]) == sk:
			b.add_theme_color_override("font_color", SKY)
			b.add_theme_color_override("font_hover_color", SKY)
		b.pressed.connect(func(): edit_step(Part.index_of(_rec(), String(f["id"]))))
		browser_vb.add_child(b)
	browser_vb.add_child(_label("Planes (3)", 15))
	for pn in Part.PLANES:
		var b := _row_btn("    %s" % String(pn).capitalize(), "part_plane_" + pn)
		b.tooltip_text = "start a sketch on the %s plane" % pn
		b.pressed.connect(func(): begin_sketch(pn))
		browser_vb.add_child(b)
	for f in feats.filter(func(f): return f["t"] == "plane"):   # E: offset planes, after the three
		var ob := _row_btn("    %s" % String(f["name"]), "part_plane_" + String(f["id"]))
		ob.tooltip_text = "start a sketch on %s" % Part.plane_words(_rec(), String(f["id"]))
		ob.pressed.connect(func(): begin_sketch(String(f["id"])))
		browser_vb.add_child(ob)
	_canvas_browser_rows()   # GAP 3: the pictures (show / hide)


func _row_btn(txt: String, nm: String) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = txt
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	return b


func _nums_sync() -> void:
	if sk == "":
		return
	var dims: Array = _sk().get("dims", [])
	var sig := JSON.stringify([sk, dims])
	if sig == _nums_sig:
		return
	_nums_sig = sig
	for c in nums_vb.get_children():
		nums_vb.remove_child(c)
		c.queue_free()
	if dims.is_empty():
		var l := _label("None yet: pick Dimension\nand click an edge.", 12, true)
		nums_vb.add_child(l)
	for i in dims.size():
		var d: Dictionary = dims[i]
		var h := HBoxContainer.new()
		var l := _label(String(d["name"]) + ("  " + Part.bind_text(d["bind"]) if d.has("bind") else ""))   # C2: a bound size names its source
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var le := LineEdit.new()
		le.name = "part_dim_%d" % i
		le.custom_minimum_size.x = 92
		le.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		le.select_all_on_focus = true
		le.text = _dim_field_text(d)
		le.text_submitted.connect(func(t: String): _num_typed.call_deferred(i, t, le))   # (deferred: the rows are rebuilt by the number)
		le.focus_exited.connect(func(): _num_typed.call_deferred(i, le.text, le))
		h.add_child(le)
		nums_vb.add_child(h)


func _num_typed(i: int, t: String, le: LineEdit) -> void:
	if sk == "" or not is_instance_valid(le) or not le.is_inside_tree():
		return
	var v := t.replace("mm", "").strip_edges()
	var dims: Array = _sk().get("dims", [])
	if i < dims.size() and (not Part.parse_bind(v).is_empty() or v.is_valid_float()):
		if Part.parse_bind(v).is_empty():
			_set_dim_value(i, float(v))
		else:
			var err := _set_dim_text(int(dims[i]["ent"]), String(dims[i]["kind"]), v)
			if err != "":
				_say(err)
			_after_sketch_edit()
	if not le.is_inside_tree():
		return   # the number made the rows again: this field is gone
	dims = _sk().get("dims", [])
	if i < dims.size():
		le.text = _dim_field_text(dims[i])
	le.release_focus()


# ---------------------------------------------------------------- sync, layout, views

func _tool_sync() -> void:
	var ok := Part.available()
	var has_sketch: bool = not _feats().filter(func(f): return f["t"] == "sketch").is_empty()
	var has_body: bool = res.get("bodies", 0) > 0
	var why := "" if ok else Part.why_not()
	for t in tool_btns:
		var b: Button = tool_btns[t]
		var w := why
		if ok and (t == "Extrude" or t == "Revolve") and not has_sketch:
			w = "sketch a closed profile first"
		elif ok and t == "Loft" and _feats().filter(func(f): return f["t"] == "sketch").size() < 2:
			w = "sketch two profiles first (a loft joins them)"
		elif ok and (t == "Mirror" or t == "Fillet" or t == "Chamfer" or t == "Hinge" or t == "Split" or t == "Shell") and not has_body:
			w = "make a solid first (Extrude or Revolve)"
		m._grey(b, w)
		b.set_pressed_no_signal(t == tool and w == "")
	m._grey(finish_btn, why if not ok else ("" if sk != "" else "no sketch is open"))


## Easy Part hides the top ribbon (its own bar stands in for it), so "What to build" moves into that bar while Easy Part is on, and
## back to the ribbon when it is not
func _place_reopen() -> void:
	if reopen_btn == null or ep == null or ep.bar_row == null:
		return
	var home: Node = ep.bar_row if (easy and on and bu.on) else part_btn.get_parent()
	if reopen_btn.get_parent() != home:
		reopen_btn.get_parent().remove_child(reopen_btn)
		home.add_child(reopen_btn)


## the row's order: the way back, Part, Easy, Finish, then the tools. A row too long for the window sends its LAST buttons to More,
## so Easy and Finish stay on the bar and the advanced tools go (the words of "What to build" made the row longer). Set again on every
## sync: the house tools and the Part tools share the row, and something else appends to it after setup
func _order_row() -> void:
	var row := part_btn.get_parent() as HBoxContainer
	if reopen_btn != null and reopen_btn.get_parent() == row and reopen_btn.get_index() != part_btn.get_index() - 1:   # (in Easy Part's bar it is not in this row)
		row.move_child(reopen_btn, part_btn.get_index())
	if easy_open_btn.get_index() != part_btn.get_index() + 1:
		row.move_child(easy_open_btn, part_btn.get_index() + 1)
	if finish_btn.get_index() != easy_open_btn.get_index() + 1:
		row.move_child(finish_btn, easy_open_btn.get_index() + 1)


func sync() -> void:
	var show := chrome()
	var up := shows()
	_place_reopen()
	_order_row()
	part_btn.visible = bu.on and not bu.easy_ui()
	part_btn.set_pressed_no_signal(on)
	for c in house_btns:
		(c as Control).visible = not show or c == reopen_btn
	if reopen_btn != null:
		reopen_btn.text = "What to build" if on else ""   # icon only in the house ribbon (it is crowded there); with words in Part, Expert or Easy
	for t in tool_btns:
		(tool_btns[t] as Control).visible = show and not (t in m.RIBBON_REST.get("BUILD", []))   # the rarer ones live under their captions (main.gd RIBBON_REST)
	finish_btn.visible = show
	easy_open_btn.visible = show
	for c in my_seps:
		(c as Control).visible = show
	if show != _was_show:
		_was_show = show
		if show:
			_tag_vis = m.axis_tags.map(func(l): return (l as Node3D).visible)
		else:
			for i in mini(_tag_vis.size(), m.axis_tags.size()):
				(m.axis_tags[i] as Node3D).visible = _tag_vis[i]
		m._place_caps.call_deferred()
		m._fit_top.call_deferred()
	if show and sk != "" and _sk().is_empty():
		sk = ""   # undo took the sketch away
		draft = {}
		dim_edit.visible = false
	if show and not dlg.is_empty() and int(dlg["edit"]) >= _feats().size():
		close_dialog()
	if show:
		_hinge_sync()
	else:
		pose = {}
	_rebuild(up)
	pov.visible = show
	part_mesh.visible = up and sk == "" and prev.is_empty() and part_mesh.mesh != null
	prev_mesh.visible = show and not prev.is_empty() and prev_mesh.mesh != null
	bu.house.visible = not up
	if up:
		bu.grid.visible = false
		bu.person.visible = false
	browser.visible = show
	side.visible = show and (sk != "" or not dlg.is_empty() or not _sel_hinge().is_empty())
	tl.visible = show
	sketch_box.visible = sk != "" and dlg.is_empty()
	dlg_box.visible = not dlg.is_empty()
	hinge_box.visible = show and dlg.is_empty() and sk == "" and not _sel_hinge().is_empty()
	if sk != "" and dlg.is_empty():
		side_title.text = "SKETCH PALETTE"
	if show:
		_tool_sync()
		_browser_sync()
		_timeline_sync()
		_nums_sync()
		_note_sync()
		pov.queue_redraw()
	else:
		note.visible = false
		dim_edit.visible = false


## the record -> the preview mesh (only when something changed)
func _rebuild(show: bool) -> void:
	if not show:
		return
	Part.refresh_bound(_rec(), _body_measures())   # C2: a dimension bound to the body shows the body's size now
	var sig := "%s|%d|%d|%s|%s" % [JSON.stringify(_rec()), upto, int(dlg.get("edit", -1)) if not dlg.is_empty() else -2, JSON.stringify(_body_measures()), JSON.stringify(pose)]   # the body moving re-solves the bound dimensions
	if sig == _rec_sig:
		return
	_rec_sig = sig
	if not Part.available() or _rec().is_empty():
		res = {"bodies": 0, "volume": 0.0, "errors": {}}
		part_mesh.mesh = null
		edge_cache = []
		return
	var up := upto
	if not dlg.is_empty() and int(dlg["edit"]) >= 0:
		up = int(dlg["edit"]) - 1
	var want := {"edges": not easy, "body": _body_measures()}
	if not pose.is_empty():
		want["pose"] = pose   # a hinge turned by Play / the slider (the record is the same; only the view turns)
	res = Part.replay(_rec(), up, want)
	if sk == "":
		part_mesh.mesh = res["mesh"]
	edge_cache = res["edges"]


func _note_sync() -> void:
	var t := ""
	if not Part.available():
		t = Part.why_not()
	elif sk != "":
		var f := _sk()
		var sig := JSON.stringify(f.get("ents", []))
		if sig != _profile_sig:
			_profile_sig = sig
			_profile_ok = _profile_text(f)
		t = "%s: %s" % [f.get("name", "Sketch"), _profile_ok]
	elif res.get("bodies", 0) > 0:
		var errs: Dictionary = res.get("errors", {})
		t = "%d bod%s, volume %s cm3" % [res["bodies"], "y" if res["bodies"] == 1 else "ies", snappedf(float(res["volume"]) * 1e6, 0.01)]
		if not errs.is_empty():
			t += "   (%d step%s failed: see the red icon)" % [errs.size(), "" if errs.size() == 1 else "s"]
	elif not _feats().is_empty():
		var errs: Dictionary = res.get("errors", {})
		t = "No solid yet" + ("   (%s)" % String(errs.values()[0]) if not errs.is_empty() else "")
	else:
		t = "Press a plane in the browser or a Sketch tool to begin"
	note_l.text = t
	note.visible = on and bu.on and t != ""


func _profile_text(f: Dictionary) -> String:
	if f["ents"].is_empty():
		return "empty: draw something"
	var face := Part.KCad.sketch_face(Part.items_of(f["ents"]), Vector3.ZERO, Vector3.RIGHT, Vector3.BACK)
	if face == 0:
		return "not closed yet (%s)" % String(Part.KCad.last_error()).get_slice("\n", 0).left(60)
	Part.KCad.release(face)
	var d: int = f.get("dims", []).size()
	return "closed profile%s" % ("" if d == 0 else ", %d dimension%s" % [d, "" if d == 1 else "s"])


func layout(cl: Rect2) -> void:
	var show := chrome()
	var up := shows()
	part_btn.visible = bu.on and not bu.easy_ui()   # (a project started from the start screen reaches BUILD without a sync)
	if up:
		for l in m.axis_tags:
			(l as Node3D).visible = false
	if bu.panel != null:
		if up:
			bu.panel.visible = false
			bu.picker.visible = false
			bu.hint_box.visible = false
			bu.chip.visible = false
			bu.type_box.visible = false
			bu.words.plan_panel.visible = false
	if up and easy:
		ep.layout(cl)
	if not show:
		return
	tl.reset_size()
	tl.size = Vector2(cl.size.x - 16.0, TL_H)
	tl.position = Vector2(cl.position.x + 8.0, cl.end.y - TL_H - 4.0)
	var avail := tl.position.y - cl.position.y - 12.0
	browser.reset_size()
	browser.size = Vector2(BROWSER_W, minf(browser.get_combined_minimum_size().y, avail))
	browser.position = Vector2(cl.position.x + 8.0, cl.position.y + 6.0)
	side.reset_size()
	side.size.x = PANEL_W
	side.size.y = minf(side.get_combined_minimum_size().y, avail)
	side.position = Vector2(cl.end.x - PANEL_W - 8.0, cl.position.y + 6.0)
	note.reset_size()
	note.position = Vector2(browser.position.x + BROWSER_W + 12.0, cl.position.y + 6.0)
	if bu.houses != null:
		bu.houses.open_panel.visible = false
		bu.houses.ask_box.visible = false


## Expert's toast ("Undid: Change Blade length") goes at the top of the view, right of the browser and under the model note:
## never over the timeline (bottom), the browser (left) or the side panel (right)
func place_toast(t: Label) -> void:
	var cl: Rect2 = m.nav_clear_rect()
	t.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE)
	var sz := t.size
	var nh := maxf(note.size.y, note.get_combined_minimum_size().y) if note.visible else 0.0
	var x := cl.position.x + 8.0 + BROWSER_W + 12.0
	var y := cl.position.y + 6.0 + (nh + 8.0 if nh > 0.0 else 0.0)
	var sr := Rect2(side.position, Vector2(side.size.x, maxf(side.size.y, side.get_combined_minimum_size().y))).grow(8.0)
	if side.visible and Rect2(Vector2(x, y), sz).intersects(sr):
		x = maxf(cl.position.x + 8.0, sr.position.x - sz.x)
	t.position = Vector2(x, y)


func _view_plane(pn: String) -> void:
	var pl := Part.resolve_plane(_rec(), pn)
	var n: Vector3 = pl["n"]
	var yaw_deg := rad_to_deg(atan2(n.x, n.z))
	var pitch_deg := -89.0 if pn == "top" else 0.0
	var at: Vector3 = pl["o"]
	var ents: Array = _sk().get("ents", [])
	var lo := Vector2(0, 0)
	var hi := Vector2(160, 100)
	if not ents.is_empty():
		lo = Vector2(INF, INF)
		hi = Vector2(-INF, -INF)
		for e in ents:
			for k in ["a", "b", "c", "m"]:
				if e.has(k):
					lo = lo.min(Part.v2(e[k]))
					hi = hi.max(Part.v2(e[k]))
	var mid := (lo + hi) * 0.5
	var ext := maxf(maxf(hi.x - lo.x, hi.y - lo.y), 120.0) * Part.MM
	m._turn_to(yaw_deg, pitch_deg, clampf(ext * 1.9, 0.5, 4.0), Part.to_world(pl, mid), false)


func _view_model() -> void:
	var bb: AABB = res.get("aabb", AABB()) if not res.is_empty() else AABB()
	var vw: Array = PartTemplates.view_of(String(m.S.part.get("easy", {}).get("t", "")))   # a template's own 3/4 view; Expert's own parts: 30 / -22
	if bb.size.length() < 1e-4:
		m._turn_to(30.0, -22.0, 0.9, Vector3(0.1, 0.0, 0.0), false)
	else:
		m._turn_to(vw[0], vw[1], clampf(bb.size.length() * 1.5, 0.4, 6.0), bb.get_center(), false)


func page_changed() -> void:
	sync()


# ---------------------------------------------------------------- drawing (the sketch, the dimensions, the picked edges)

func _pill(c: Vector2, txt: String, fill: Color, fg: Color, fs: int) -> void:
	var f := ThemeDB.fallback_font
	var sz := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var r := Rect2(c - Vector2(sz.x * 0.5 + 8.0, sz.y * 0.5 + 3.0), sz + Vector2(16.0, 6.0))
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(r.size.y * 0.5))
	pov.draw_style_box(sb, r)
	pov.draw_string(f, Vector2(r.position.x + 8.0, r.position.y + 3.0 + f.get_ascent(fs)), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fg)


func _draw() -> void:
	if not (bu.on and on):
		return
	if sk != "":
		_draw_sketch()
	else:
		_draw_model()


func _draw_axes(o: Vector3, len: float) -> void:
	for e in [[Vector3.RIGHT, Color(0.95, 0.35, 0.35, 0.9)], [Vector3.UP, Color(0.4, 0.9, 0.45, 0.9)], [Vector3.BACK, Color(0.4, 0.55, 1.0, 0.9)]]:
		var a: Vector3 = o
		var b: Vector3 = o + (e[0] as Vector3) * len
		if not m.cam.is_position_behind(a) and not m.cam.is_position_behind(b):
			pov.draw_line(m.cam.unproject_position(a), m.cam.unproject_position(b), e[1], 2.0)


func _draw_model() -> void:
	_canvas_draw("")
	_draw_axes(Vector3.ZERO, 0.08)
	_draw_hinge_marks()
	for i in edge_cache.size():
		var picked_now := false
		for pe in picked:
			if (pe["c"] as Vector3).distance_to(edge_cache[i]["c"]) < 1e-6:
				picked_now = true
		if picked_now or i == hover_edge:
			_edge_line(edge_cache[i], SKY if picked_now else Color(SKY, 0.6), 5.0 if picked_now else 3.0)
	if not dlg.is_empty() and picked.size() > 0 and String(dlg["t"]) in ["fillet", "chamfer"]:
		var e: Dictionary = picked[0]
		var lab := "%s %s mm" % ["Radius" if dlg["t"] == "fillet" else "Distance", f_num.text]
		_pill(m.cam.unproject_position(e["c"]) + Vector2(60, -40), lab, Color(0.06, 0.07, 0.1, 0.92), Color.WHITE, 14)
		pov.draw_line(m.cam.unproject_position(e["c"]), m.cam.unproject_position(e["c"]) + Vector2(40, -30), Color("#ffc233"), 1.5)
		pov.draw_circle(m.cam.unproject_position(e["c"]), 5.0, Color("#ffc233"))


func _edge_line(e: Dictionary, c: Color, w: float) -> void:
	var a: Vector3 = e["a"]
	var b: Vector3 = e["b"]
	var mid: Vector3 = e["c"]
	if m.cam.is_position_behind(a) or m.cam.is_position_behind(b) or m.cam.is_position_behind(mid):
		return
	if a.distance_to(b) > 1e-6:
		pov.draw_polyline(PackedVector2Array([m.cam.unproject_position(a), m.cam.unproject_position(mid), m.cam.unproject_position(b)]), c, w)
	else:
		pov.draw_circle(m.cam.unproject_position(mid), 5.0, c)


func _draw_sketch() -> void:
	var f := _sk()
	if f.is_empty():
		return
	var pl := _plane()
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	_canvas_draw(String(f.get("plane", "front")))   # GAP 3: the picture is behind the sketch
	if grid_on:
		_draw_grid(pl, vs)
	_draw_axes(Vector3.ZERO, 0.0)
	var ents: Array = f["ents"]
	var line_c := SKY
	for i in ents.size():
		var e: Dictionary = ents[i]
		var hot: bool = not hover_ent.is_empty() and int(hover_ent.get("ent", -1)) == i and tool == "Dimension"
		var c := Color("#ffc233") if hot else line_c
		match String(e["k"]):
			"rect":
				var a := Part.v2(e["a"])
				var b := Part.v2(e["b"])
				var pts := PackedVector2Array([scr(a), scr(Vector2(b.x, a.y)), scr(b), scr(Vector2(a.x, b.y)), scr(a)])
				pov.draw_colored_polygon(pts.slice(0, 4), Color(SKY, 0.12))
				pov.draw_polyline(pts, c, 2.5)
				for q in pts.slice(0, 4):
					pov.draw_circle(q, 4.0, Color.WHITE)
			"line":
				var a := scr(Part.v2(e["a"]))
				var b := scr(Part.v2(e["b"]))
				pov.draw_line(a, b, c, 2.5)
				pov.draw_circle(a, 4.0, Color.WHITE)
				pov.draw_circle(b, 4.0, Color.WHITE)
			"circle":
				var cc := Part.v2(e["c"])
				var r := float(e["r"])
				var pts := PackedVector2Array()
				for j in 65:
					pts.append(scr(cc + Vector2.from_angle(TAU * j / 64.0) * r))
				pov.draw_colored_polygon(pts.slice(0, 64), Color(SKY, 0.12))
				pov.draw_polyline(pts, c, 2.5)
				pov.draw_circle(scr(cc), 3.5, Color.WHITE)
			"arc":
				_draw_arc_ent(Part.v2(e["a"]), Part.v2(e["m"]), Part.v2(e["b"]), c)
			"bspline":
				var closed := bool(e.get("closed", false))
				var curve := PackedVector2Array()
				for q in _spline_curve(e["pts"], closed):
					curve.append(scr(q))
				if closed:
					pov.draw_colored_polygon(curve, Color(SKY, 0.12))
				pov.draw_polyline(curve, c, 2.5)
				for q in e["pts"]:
					pov.draw_circle(scr(Part.v2(q)), 4.0, Color.WHITE)
	if show_dims:
		for d in f.get("dims", []):
			_draw_dim(ents, d)
	_draw_draft()


func _draw_arc_ent(a: Vector2, mid: Vector2, b: Vector2, c: Color) -> void:
	var cen := _circum(a, mid, b)
	if cen.is_empty():
		pov.draw_polyline(PackedVector2Array([scr(a), scr(mid), scr(b)]), c, 2.5)
		return
	var o: Vector2 = cen["c"]
	var r: float = cen["r"]
	var a0 := (a - o).angle()
	var a1 := (b - o).angle()
	var am := (mid - o).angle()
	var d := wrapf(a1 - a0, -PI, PI)
	var dm := wrapf(am - a0, -PI, PI)
	var sweep := d
	if (d > 0.0) != (dm > 0.0) or absf(dm) > absf(d):
		sweep = d - TAU if d > 0.0 else d + TAU
	var pts := PackedVector2Array()
	for j in 33:
		pts.append(scr(o + Vector2.from_angle(a0 + sweep * j / 32.0) * r))
	pov.draw_polyline(pts, c, 2.5)
	pov.draw_circle(scr(a), 4.0, Color.WHITE)
	pov.draw_circle(scr(b), 4.0, Color.WHITE)


func _circum(a: Vector2, b: Vector2, c: Vector2) -> Dictionary:
	var d := 2.0 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
	if absf(d) < 1e-9:
		return {}
	var ux := ((a.length_squared()) * (b.y - c.y) + b.length_squared() * (c.y - a.y) + c.length_squared() * (a.y - b.y)) / d
	var uy := ((a.length_squared()) * (c.x - b.x) + b.length_squared() * (a.x - c.x) + c.length_squared() * (b.x - a.x)) / d
	var o := Vector2(ux, uy)
	return {"c": o, "r": o.distance_to(a)}


func _draw_grid(pl: Dictionary, vs: Vector2) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for cpt in [Vector2(0, 0), Vector2(vs.x, 0), Vector2(vs.x, vs.y), Vector2(0, vs.y)]:
		var h: Variant = hit(cpt)
		if h == null:
			return
		lo = lo.min(h as Vector2)
		hi = hi.max(h as Vector2)
	var step := snap_mm
	var px_per_mm: float = (scr(Vector2(100, 0)) - scr(Vector2(0, 0))).length() / 100.0
	while step * px_per_mm < 7.0:
		step *= 2.0
	if (hi.x - lo.x) / step > 400.0 or (hi.y - lo.y) / step > 400.0:
		return
	var minor := Color(0.4, 0.48, 0.6, 0.16)
	var major := Color(0.5, 0.6, 0.75, 0.3)
	var x0 := floorf(lo.x / step) * step
	var y0 := floorf(lo.y / step) * step
	var x := x0
	while x <= hi.x:
		var maj := is_zero_approx(fposmod(x, step * 10.0))
		pov.draw_line(scr(Vector2(x, lo.y)), scr(Vector2(x, hi.y)), major if maj else minor, 1.0)
		x += step
	var y := y0
	while y <= hi.y:
		var maj := is_zero_approx(fposmod(y, step * 10.0))
		pov.draw_line(scr(Vector2(lo.x, y)), scr(Vector2(hi.x, y)), major if maj else minor, 1.0)
		y += step
	pov.draw_line(scr(Vector2(lo.x, 0)), scr(Vector2(hi.x, 0)), Color(0.95, 0.4, 0.4, 0.8), 1.5)
	pov.draw_line(scr(Vector2(0, lo.y)), scr(Vector2(0, hi.y)), Color(0.4, 0.9, 0.5, 0.8), 1.5)


func _draw_dim(ents: Array, d: Dictionary) -> void:
	var i := int(d["ent"])
	if i >= ents.size():
		return
	var e: Dictionary = ents[i]
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var off := Vector2(0, 26)
	var txt := "%s" % _fmt(float(d["mm"]))
	match String(d["kind"]):
		"w":
			a = Part.v2(e["a"])
			b = Vector2(Part.v2(e["b"]).x, a.y)
			off = Vector2(0, 26)
		"h":
			a = Part.v2(e["a"])
			b = Vector2(a.x, Part.v2(e["b"]).y)
			off = Vector2(-30, 0)
		"len":
			a = Part.v2(e["a"])
			b = Part.v2(e["b"])
			var dir := (scr(b) - scr(a)).normalized()
			off = Vector2(-dir.y, dir.x) * 26.0
		"r":
			a = Part.v2(e["c"])
			b = a + Vector2(float(e["r"]), 0)
			txt = "R" + txt
			off = Vector2.ZERO
	var pa := scr(a) + off
	var pb := scr(b) + off
	var ink := Color(1, 1, 1, 0.8)
	if off != Vector2.ZERO:
		pov.draw_line(scr(a), pa, Color(1, 1, 1, 0.3), 1.0)
		pov.draw_line(scr(b), pb, Color(1, 1, 1, 0.3), 1.0)
	pov.draw_line(pa, pb, ink, 1.5)
	_pill((pa + pb) * 0.5, txt, Color(0.06, 0.07, 0.1, 0.94), Color.WHITE, 14)


func _draw_draft() -> void:
	if draft.is_empty():
		return
	var a: Vector2 = draft.get("a", Vector2.ZERO)
	var b: Vector2 = draft.get("b", a)
	var c := Color("#ffc233")
	match String(draft["k"]):
		"line":
			pov.draw_line(scr(a), scr(b), c, 2.0)
			var len := a.distance_to(b)
			_pill((scr(a) + scr(b)) * 0.5 + Vector2(0, -18), (typed + " mm") if typed != "" else "%s mm" % _fmt(len), Color(0.06, 0.07, 0.1, 0.94), Color.WHITE, 14)
		"rect":
			pov.draw_polyline(PackedVector2Array([scr(a), scr(Vector2(b.x, a.y)), scr(b), scr(Vector2(a.x, b.y)), scr(a)]), c, 2.0)
			_pill(scr(b) + Vector2(40, 18), "%s x %s mm" % [_fmt(absf(b.x - a.x)), _fmt(absf(b.y - a.y))], Color(0.06, 0.07, 0.1, 0.94), Color.WHITE, 14)
		"circle":
			var pts := PackedVector2Array()
			for j in 65:
				pts.append(scr(a + Vector2.from_angle(TAU * j / 64.0) * a.distance_to(b)))
			pov.draw_polyline(pts, c, 2.0)
			_pill(scr(b) + Vector2(40, 18), "R %s mm" % _fmt(a.distance_to(b)), Color(0.06, 0.07, 0.1, 0.94), Color.WHITE, 14)
		"arc":
			var pts: Array = draft.get("pts", [])
			for q in pts:
				pov.draw_circle(scr(q), 5.0, c)
			if pts.size() == 1:
				pov.draw_line(scr(pts[0]), scr(b), c, 1.5)
			elif pts.size() == 2:
				_draw_arc_ent(pts[0], b, pts[1], c)
		"spline":
			var sp: Array = (draft.get("pts", []) as Array).duplicate()
			for q in sp:
				pov.draw_circle(scr(q), 5.0, c)
			sp.append(b)
			var curve := PackedVector2Array()
			for q in _spline_curve(sp, false):
				curve.append(scr(q))
			pov.draw_polyline(curve, c, 2.0)


# ---------------------------------------------------------------- sketch splines (Spline tool)

## a Spline click: a point is added; a click on the first point (3 or more points) closes the curve; a double-click ends an open one
func _spline_click(p: Vector2, a: Vector2) -> void:
	var pts: Array = draft.get("pts", [])
	var now := Time.get_ticks_msec()
	var dbl := now - spl_last_ms < DOUBLE_MS and p.distance_to(spl_last_p) < 8.0
	spl_last_ms = now
	spl_last_p = p
	if not pts.is_empty() and scr(pts[0]).distance_to(p) < 12.0:
		if pts.size() >= 3:
			_spline_add(true)
		return
	if dbl and pts.size() >= 3:
		_spline_add(false)
		return
	if not pts.is_empty() and (pts.back() as Vector2).distance_to(a) < 0.5:
		return
	pts.append(a)
	draft = {"k": "spline", "pts": pts, "b": a}


func _spline_add(closed: bool) -> void:
	var out := []
	for q in draft.get("pts", []):
		out.append(Part.arr2(q))
	_add_ent({"k": "bspline", "pts": out, "closed": closed})
	draft = {}
	typed = ""


## the point of a curve on the sheet under a screen point (within 10 px): {"ent", "pt"} or {}
func _spline_point_at(p: Vector2) -> Dictionary:
	var ents: Array = _sk().get("ents", [])
	for i in ents.size():
		if String(ents[i]["k"]) != "bspline":
			continue
		var sp: Array = ents[i]["pts"]
		for j in sp.size():
			if scr(Part.v2(sp[j])).distance_to(p) < 10.0:
				return {"ent": i, "pt": j}
	return {}


## the curve drawn for a spline: the same one the kernel is given (Part.spline_curve)
func _spline_curve(pts: Array, closed: bool) -> PackedVector2Array:
	return Part.spline_curve(pts, closed)


# ---------------------------------------------------------------- C3 hinge: a part turns about a line; must not touch

## the hinge the side panel shows: the selected step when it is a hinge and nothing else is open, else {}
func _sel_hinge() -> Dictionary:
	if not chrome() or sk != "" or not dlg.is_empty() or sel_step < 0 or sel_step >= _feats().size():
		return {}
	var f: Dictionary = _feats()[sel_step]
	return f if String(f["t"]) == "hinge" else {}


func _part_name(i: int) -> String:
	return "Body%d" % (i + 1)   # the browser's name for the same body (Bodies: Body1, Body2)


## the panel's words for a hinge: turns Part 1 from 0 deg to 90 deg in 3 s
func _hinge_words(f: Dictionary) -> String:
	var tr: Array = f.get("track", [])
	if tr.size() < 2:
		return "Its angles are not set yet."
	return "Turns %s from %s deg to %s deg in %s s, round the line it was given." % [_part_name(int(f["body"])), _fmt(float(tr[0][1])), _fmt(float(tr[-1][1])), _fmt(float(tr[-1][0]))]


## the dialog's next step, in words
func _hinge_next() -> String:
	if int(hp.get("body", -1)) < 0:
		return "Click the part that turns."
	if not hp.has("d"):
		return "Click a straight edge of it (the line it turns round), or two points on it." if (hp.get("pts", []) as Array).is_empty() else "Click a second point on that line."
	return "Type the start and end angles and the seconds, then click OK."


func _hinge_open(f: Dictionary, edit: int) -> void:
	hp = {"body": -1, "faces": Part.body_faces(_rec(), -1), "pts": []}
	if edit >= 0:
		hp["body"] = int(f.get("body", -1))
		hp["o"] = Part._pivot(f)
		hp["d"] = Part._axis(f)
		var tr: Array = f.get("track", [])
		if tr.size() >= 2:
			f_from.text = _fmt(float(tr[0][1]))
			f_to.text = _fmt(float(tr[-1][1]))
			f_dur.text = _fmt(float(tr[-1][0]))
	else:
		f_from.text = "0"
		f_to.text = "90"
		f_dur.text = "3"
	_hinge_rows()


## the hinge dialog's rows: the part, the line, then (once there is a line) the angles, the dial and the seconds
func _hinge_rows() -> void:
	_clear_rows()
	var bi := int(hp.get("body", -1))
	dlg_rows.add_child(_label("Turning part:  %s" % _part_name(bi) if bi >= 0 else "Turning part:  not yet"))
	dlg_rows.add_child(_label("Line:  picked" if hp.has("d") else "Line:  not yet"))
	if hp.has("d"):
		_hrow("From", f_from, "deg")
		_hrow("To", f_to, "deg")
		_hrow("Seconds", f_dur, "s")
		dlg_rows.add_child(f_dial)
		f_dial.queue_redraw()


func _hrow(label: String, le: LineEdit, unit: String) -> void:
	var h := HBoxContainer.new()
	var l := _label(label)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(le)
	h.add_child(_label(unit, 13, true))
	dlg_rows.add_child(h)


## a screen point over the parts: the nearest part hit and the hit point ({} = none)
func _ray_hit(p: Vector2, faces: Array) -> Dictionary:
	var ro: Vector3 = m.cam.project_ray_origin(p)
	var rd: Vector3 = m.cam.project_ray_normal(p)
	var best := {}
	var best_d := INF
	for bi in faces.size():
		var tris: PackedVector3Array = faces[bi]
		for k in range(0, tris.size() - 2, 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(ro, rd, tris[k], tris[k + 1], tris[k + 2])
			if hit != null:
				var dd := ro.distance_to(hit as Vector3)
				if dd < best_d:
					best_d = dd
					best = {"body": bi, "at": hit}
	return best


## the straight edge of part bi nearest a screen point (within 12 px), an index of edge_cache or -1
func _pick_edge_of(p: Vector2, bi: int) -> int:
	var best := -1
	var best_d := 12.0
	for i in edge_cache.size():
		var e: Dictionary = edge_cache[i]
		if int(e["body"]) != bi or (e["a"] as Vector3).distance_to(e["b"] as Vector3) < 1e-6:
			continue
		if m.cam.is_position_behind(e["a"]) or m.cam.is_position_behind(e["b"]):
			continue
		var pa: Vector2 = m.cam.unproject_position(e["a"])
		var pb: Vector2 = m.cam.unproject_position(e["b"])
		var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, pa, pb))
		if d < best_d:
			best_d = d
			best = i
	return best


func _hinge_press(p: Vector2) -> bool:
	var h := _ray_hit(p, hp.get("faces", []))
	var bi := int(h.get("body", -1))
	if bi >= 0 and bi != int(hp["body"]):   # another part: it is the one that turns (its line is picked again)
		hp["body"] = bi
		hp.erase("d")
		hp["pts"] = []
	elif int(hp["body"]) < 0:
		return true
	else:
		var i := _pick_edge_of(p, int(hp["body"]))
		if i >= 0:
			var e: Dictionary = edge_cache[i]
			hp["o"] = e["a"]
			hp["d"] = ((e["b"] as Vector3) - (e["a"] as Vector3)).normalized()
			hp["pts"] = []
		elif bi == int(hp["body"]):
			var pts: Array = hp.get("pts", [])
			pts.append(h["at"])
			if pts.size() >= 2:
				var dv: Vector3 = (pts[1] as Vector3) - (pts[0] as Vector3)
				if dv.length() > 1e-6:
					hp["o"] = pts[0]
					hp["d"] = dv.normalized()
					pts = []
				else:
					pts = [pts[0]]
			hp["pts"] = pts
		else:
			return true
	_hinge_rows()
	_preview()
	pov.queue_redraw()
	_say(_hinge_next())
	return true


## MUST NOT TOUCH: the pair picking begins (the selected hinge's list gets the pair)
func _pair_start() -> void:
	var f := _sel_hinge()
	if f.is_empty() or not Part.available():
		return
	pair_pick = {"id": String(f["id"]), "first": -1, "faces": Part.body_faces(_rec(), -1)}
	_say("Must not touch: click the first part (Esc cancels).")
	_hinge_sync()
	pov.queue_redraw()


func _pair_press(p: Vector2) -> bool:
	var h := _ray_hit(p, pair_pick["faces"])
	var bi := int(h.get("body", -1))
	if bi < 0:
		return true
	var a := int(pair_pick["first"])
	if a < 0:
		pair_pick["first"] = bi
		_say("Must not touch: now click the part it must not touch (%s is picked)." % _part_name(bi))
		pov.queue_redraw()
		return true
	if bi == a:
		return true
	m._push_undo()
	var err := Part.clear_pair_set(_rec(), String(pair_pick["id"]), a, bi, true)
	pair_pick = {}
	_say(err if err != "" else "Must not touch: %s and %s." % [_part_name(a), _part_name(bi)])
	bu.sync()
	return true


func _pair_remove(a: int, b: int) -> void:
	var f := _sel_hinge()
	if f.is_empty():
		return
	m._push_undo()
	var err := Part.clear_pair_set(_rec(), String(f["id"]), a, b, false)
	_say(err if err != "" else "Removed: %s and %s may touch." % [_part_name(a), _part_name(b)])
	bu.sync()


## the side panel of a selected hinge: its words, Play and the slider, the pairs, the swing's frame strip and its words
func _hinge_sync() -> void:
	var f := _sel_hinge()
	if f.is_empty():
		play_on = false
		pose = {}
		hinge_sig = ""
		return
	var id := String(f["id"])
	if not pose.is_empty() and String(pose["f"]) != id:
		pose = {}
		play_on = false
	if not pair_pick.is_empty() and String(pair_pick["id"]) != id:
		pair_pick = {}
	side_title.text = "HINGE"
	var sig := JSON.stringify(f)
	if sig != hinge_sig:
		hinge_sig = sig
		hinge_title.text = String(f["name"])
		hinge_info.text = _hinge_words(f)
		_pairs_rows(f)
		hsw = Part.hinge_sweep(_rec(), id, HSEC) if Part.available() else {"ok": false, "why": Part.why_not()}
	var pairs := Part.clear_pairs(_rec(), id)
	if pairs.is_empty():
		hinge_red_l.text = "Add a pair to see where the parts touch while it turns."
	elif not bool(hsw.get("ok", false)):
		hinge_red_l.text = "Cannot check the turn: %s" % String(hsw.get("why", ""))
	elif (hsw["red"] as Array).is_empty():
		hinge_red_l.text = "Never touching while it turns."
	else:
		hinge_red_l.text = "Touching at %s" % String(hsw["red_text"])
	hinge_play_btn.text = "Stop" if play_on else "Play"
	hinge_pair_btn.disabled = not Part.available()
	hinge_slider.set_value_no_signal(play_pct)
	hinge_strip.queue_redraw()


func _pairs_rows(f: Dictionary) -> void:
	for c in hinge_pairs_vb.get_children():
		hinge_pairs_vb.remove_child(c)
		c.queue_free()
	for pr in Part.clear_pairs(_rec(), String(f["id"])):
		var h := HBoxContainer.new()
		var l := _label("%s and %s" % [_part_name(int(pr[0])), _part_name(int(pr[1]))], 12)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		var x := Button.new()
		x.name = "part_pair_x_%d_%d" % [int(pr[0]), int(pr[1])]
		x.text = "x"
		x.focus_mode = Control.FOCUS_NONE
		x.tooltip_text = "Remove this pair"
		x.pressed.connect(_pair_remove.bind(int(pr[0]), int(pr[1])))
		h.add_child(x)
		hinge_pairs_vb.add_child(h)


func _draw_strip() -> void:
	var r := hinge_strip.size
	hinge_strip.draw_rect(Rect2(Vector2.ZERO, r), Color(0.2, 0.22, 0.27))
	if not bool(hsw.get("ok", false)):
		return
	var n := int(hsw["frames"])
	if n <= 0:
		return
	var red := {}
	for i in hsw["red"]:
		red[int(i)] = true
	var cw := r.x / float(n)
	for i in n:
		hinge_strip.draw_rect(Rect2(i * cw, 0.0, cw + 0.5, r.y), Color("#ff5a4e") if red.has(i) else Color("#7f8a99"))
	var f := _sel_hinge()
	if not pose.is_empty() and not f.is_empty():
		var cur := play_pct / 100.0 * float(f["track"][-1][0]) * HSEC
		hinge_strip.draw_line(Vector2(cur * cw, 0.0), Vector2(cur * cw, r.y), Color.WHITE, 2.0)


## Play: the slider's share of the swing, in real time
func _hinge_play_toggle() -> void:
	var f := _sel_hinge()
	if f.is_empty():
		return
	if play_on:
		play_on = false
	else:
		if play_pct >= 100.0:
			play_pct = 0.0
		play_t = play_pct / 100.0 * float(f["track"][-1][0])
		play_on = true
	hinge_play_btn.text = "Stop" if play_on else "Play"


func _play_tick() -> void:
	if not play_on:
		return
	var f := _sel_hinge()
	if f.is_empty():
		play_on = false
		return
	var dur := maxf(float(f["track"][-1][0]), 1e-6)
	play_t += 0.05
	var pct := minf(play_t / dur * 100.0, 100.0)
	hinge_set_pct(pct)
	if pct >= 100.0:
		play_on = false
		hinge_play_btn.text = "Play"


## the hinge shows at pct % of its swing (0 = its first angle, 100 = its last): the body turns in the view
func hinge_set_pct(v: float) -> void:
	var f := _sel_hinge()
	if f.is_empty():
		return
	play_pct = clampf(v, 0.0, 100.0)
	var tr: Array = f["track"]
	var deg := float(Curves.eval(tr, play_pct / 100.0 * float(tr[-1][0])))
	pose = {"f": String(f["id"]), "deg": deg}
	hinge_pct_l.text = "%d %%   %s deg" % [roundi(play_pct), _fmt(deg)]
	hinge_slider.set_value_no_signal(play_pct)
	_rebuild(true)
	hinge_strip.queue_redraw()
	pov.queue_redraw()


func _draw_dial() -> void:
	var c := f_dial.size * 0.5
	var r := minf(c.x, c.y) - 8.0
	f_dial.draw_arc(c, r, 0.0, TAU, 48, Color(0.5, 0.55, 0.62), 2.0)
	var fr := _num(f_from)
	var to := _num(f_to)
	if not is_nan(fr):
		var v := Vector2(cos(deg_to_rad(fr)), -sin(deg_to_rad(fr)))
		f_dial.draw_line(c, c + v * r, Color(0.6, 0.6, 0.6), 2.0)
	if not is_nan(to):
		var w := Vector2(cos(deg_to_rad(to)), -sin(deg_to_rad(to)))
		f_dial.draw_line(c, c + w * r, SKY, 3.0)
		f_dial.draw_circle(c + w * r, 5.0, SKY)
	f_dial.draw_circle(c, 3.0, Color.WHITE)


## the dial: drag to set the end angle (counter-clockwise from the right, -180..180)
func _dial_input(ev: InputEvent) -> void:
	var pos := Vector2.ZERO
	var on_it := false
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and (ev as InputEventMouseButton).pressed:
		pos = (ev as InputEventMouseButton).position
		on_it = true
	elif ev is InputEventMouseMotion and ((ev as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		pos = (ev as InputEventMouseMotion).position
		on_it = true
	if not on_it:
		return
	var v := pos - f_dial.size * 0.5
	f_to.text = "%d" % roundi(rad_to_deg(atan2(-v.y, v.x)))
	f_dial.queue_redraw()
	_preview()
	f_dial.accept_event()


func _draw_line3(o: Vector3, d: Vector3, c: Color) -> void:
	var a := o - d * 0.6
	var b := o + d * 0.6
	if m.cam.is_position_behind(a) or m.cam.is_position_behind(b):
		return
	pov.draw_line(m.cam.unproject_position(a), m.cam.unproject_position(b), c, 2.0)


## the line being picked (gold), the selected hinge's line (sky blue), and the parts of its must-not-touch pairs (red)
func _draw_hinge_marks() -> void:
	if not dlg.is_empty() and String(dlg.get("t", "")) == "hinge":
		for q in hp.get("pts", []):
			pov.draw_circle(m.cam.unproject_position(q), 5.0, Color("#ffc233"))
		if hp.has("d"):
			_draw_line3(hp["o"], hp["d"], Color("#ffc233"))
	var f := _sel_hinge()
	if f.is_empty():
		return
	_draw_line3(Part._pivot(f), Part._axis(f), SKY)
	for pr in Part.clear_pairs(_rec(), String(f["id"])):
		for e in edge_cache:
			if int(e["body"]) == int(pr[0]) or int(e["body"]) == int(pr[1]):
				_edge_line(e, Color("#ff5a4e"), 4.0)


# ---------------------------------------------------------------- canvas (GAP 3, Fusion Canvas): a picture on a plane behind the sketch

## the canvas dialog controls, made once (their rows are put in the dialog by _canvas_open)
func _canvas_ctl() -> void:
	f_cv_pick = Button.new()   # (new controls each time: the dialog's rows are freed when it closes)
	f_cv_pick.name = "part_canvas_pick"
	f_cv_pick.text = "Choose picture..."
	f_cv_pick.pressed.connect(_canvas_choose)
	f_cv_plane = OptionButton.new()
	f_cv_plane.name = "part_canvas_plane"
	f_cv_plane.item_selected.connect(func(_i): _canvas_edited())
	f_cv_show = CheckBox.new()
	f_cv_show.name = "part_canvas_show"
	f_cv_show.text = "Show picture"
	f_cv_show.toggled.connect(func(_v): _canvas_edited())
	f_cv_op = HSlider.new()
	f_cv_op.name = "part_canvas_opacity"
	f_cv_op.min_value = 0.0
	f_cv_op.max_value = 1.0
	f_cv_op.step = 0.05
	f_cv_op.custom_minimum_size = Vector2(140, 0)
	f_cv_op.value_changed.connect(func(_v): _canvas_edited())
	f_cv_cal = Button.new()
	f_cv_cal.name = "part_canvas_recal"
	f_cv_cal.text = "Pick the two points again"
	f_cv_cal.pressed.connect(_canvas_recal)
	if f_cv_file == null:   # the file chooser is made once (it lives in the UI root)
		f_cv_file = FileDialog.new()
		f_cv_file.name = "part_canvas_file"
		f_cv_file.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		f_cv_file.access = FileDialog.ACCESS_FILESYSTEM
		f_cv_file.filters = PackedStringArray(["*.png, *.jpg, *.jpeg ; Pictures"])
		f_cv_file.file_selected.connect(_canvas_picked)
		m.ui_root.add_child(f_cv_file)


## the Canvas dialog opens: its working picture (dlg["cv"]) is the saved one (Edit) or a new one on the chosen plane
func _canvas_open(f: Dictionary, edit: int) -> void:
	_canvas_ctl()
	var rec := _rec()
	var ids: Array = Part.PLANES.duplicate()
	var names: Array = ["Front plane", "Top plane", "Right plane"]
	for o in rec.get("features", []):
		if o["t"] == "plane":
			ids.append(String(o["id"]))
			names.append(Part.plane_words(rec, String(o["id"])).capitalize())
	dlg["plane_ids"] = ids
	f_cv_plane.clear()
	for n in names:
		f_cv_plane.add_item(String(n))
	var cv := {"plane": "front", "path": "", "w": 1, "h": 1, "pts": [], "dist": 0.0, "at": [0.0, 0.0], "opacity": 0.8, "show": true}
	if edit >= 0:
		cv.merge(f.duplicate(true), true)
	dlg["cv"] = cv
	dlg["anchor"] = Part.canvas_px_to_mm(cv, Part.v2(cv["pts"][0])) if (cv["pts"] as Array).size() == 2 else Vector2(cv["at"][0], cv["at"][1])
	f_cv_plane.select(maxi(ids.find(String(cv["plane"])), 0))
	f_cv_op.set_value_no_signal(float(cv["opacity"]))
	f_cv_show.set_pressed_no_signal(bool(cv["show"]))
	var dist := float(cv["dist"])
	_row("Real distance", f_num, "%s mm" % _fmt(dist) if dist > 0.0 else "")
	dlg_rows.add_child(f_cv_pick)
	dlg_rows.move_child(f_cv_pick, 0)
	var plr := HBoxContainer.new()
	plr.add_child(_label("Plane"))
	plr.add_child(f_cv_plane)
	dlg_rows.add_child(plr)
	dlg_rows.add_child(f_cv_show)
	var opr := HBoxContainer.new()
	opr.add_child(_label("Opacity"))
	opr.add_child(f_cv_op)
	dlg_rows.add_child(opr)
	dlg_rows.add_child(f_cv_cal)
	_view_plane(String(cv["plane"]))


func _cv_plane_id() -> String:
	var ids: Array = dlg.get("plane_ids", Part.PLANES)
	return String(ids[clampi(f_cv_plane.selected, 0, ids.size() - 1)])


## the working picture as a record feature. need: only a calibrated picture (two points, a distance) is returned, else {}
func _canvas_feature(need: bool) -> Dictionary:
	if dlg.get("t", "") != "canvas":
		return {}
	var cv: Dictionary = dlg["cv"]
	var f := cv.duplicate(true)
	f["plane"] = _cv_plane_id()
	f["opacity"] = snappedf(f_cv_op.value, 0.01)
	f["show"] = f_cv_show.button_pressed
	var d := _num(f_num)
	var dist := d if (not is_nan(d) and d > 0.0) else 0.0
	f["dist"] = dist
	var at := Vector2(cv["at"][0], cv["at"][1])
	var pts: Array = cv["pts"]
	if pts.size() == 2:
		var s := Part.canvas_scale({"pts": pts, "dist": dist})
		var p0 := Part.v2(pts[0])
		at = (dlg["anchor"] as Vector2) - Vector2(p0.x * s, -p0.y * s)   # the first point stays where it was clicked
	f["at"] = Part.arr2(at)
	if need and (String(cv["path"]) == "" or pts.size() != 2 or dist <= 0.0):
		return {}
	return f


func _canvas_hint() -> String:
	var cv: Dictionary = dlg["cv"]
	var n := (cv["pts"] as Array).size()
	if String(cv["path"]) == "":
		return "Choose a picture (png or jpg) to put on the plane."
	if n == 0:
		return "Click the first point on the picture (a mark whose real size you know)."
	if n == 1:
		return "Now click the second point."
	var d := _num(f_num)
	if is_nan(d) or d <= 0.0:
		return "Type the real distance between the two points (mm). The picture follows as you type; OK keeps it."
	return "Drag the picture to line it up. OK keeps it."


func _canvas_choose() -> void:
	f_cv_file.popup_centered_ratio(0.6)


## a picture file was chosen: it shows on the plane at 1 mm per pixel until its two points are calibrated
func _canvas_picked(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		_say("Could not read %s: choose a png or jpg picture" % path)
		return
	var cv: Dictionary = dlg["cv"]
	cv["path"] = path
	cv["w"] = img.get_width()
	cv["h"] = img.get_height()
	cv["pts"] = []
	cv_tex[path] = ImageTexture.create_from_image(img)
	_view_plane(_cv_plane_id())
	_say(_canvas_hint())
	_preview()
	pov.queue_redraw()


func _canvas_edited() -> void:
	if dlg.get("t", "") == "canvas":
		_preview()
		pov.queue_redraw()


## pick the two points again: the picture stays where it is, the clicks start over
func _canvas_recal() -> void:
	var cvf := _canvas_feature(false)
	var cv: Dictionary = dlg["cv"]
	cv["at"] = cvf["at"]
	cv["pts"] = []
	_say(_canvas_hint())
	_preview()
	pov.queue_redraw()


func _canvas_press(p: Vector2) -> bool:
	var cvf := _canvas_feature(false)
	if String(cvf["path"]) == "":
		_say("Choose a picture first")
		return true
	var cv: Dictionary = dlg["cv"]
	var pl := Part.resolve_plane(_rec(), String(cvf["plane"]))
	if (cv["pts"] as Array).size() >= 2:
		return _canvas_grab(p)   # calibrated: a press on the picture drags it
	var h: Variant = _canvas_hit(p, pl)
	if h == null:
		return false
	var mm: Vector2 = h
	var px := Part.canvas_mm_to_px(cvf, mm)
	if px.x < 0.0 or px.y < 0.0 or px.x > float(cv["w"]) or px.y > float(cv["h"]):
		_say("Click on the picture")
		return true
	var pts: Array = cv["pts"]
	pts.append(Part.arr2(px))
	if pts.size() == 1:
		dlg["c1"] = mm
	else:
		dlg["anchor"] = dlg["c1"]
		f_num.grab_focus()
	_say(_canvas_hint())
	_preview()
	pov.queue_redraw()
	return true


func _canvas_hit(p: Vector2, pl: Dictionary) -> Variant:
	var ro: Vector3 = m.cam.project_ray_origin(p)
	var rd: Vector3 = m.cam.project_ray_normal(p)
	var n: Vector3 = pl["n"]
	var den := rd.dot(n)
	if absf(den) < 1e-6:
		return null
	var t := ((pl["o"] as Vector3) - ro).dot(n) / den
	if t < 0.0:
		return null
	return Part.to_plane(pl, ro + rd * t)


func _canvas_inside(f: Dictionary, p: Vector2) -> Variant:
	var h: Variant = _canvas_hit(p, Part.resolve_plane(_rec(), String(f["plane"])))
	if h == null:
		return null
	var px := Part.canvas_mm_to_px(f, h)
	if px.x < 0.0 or px.y < 0.0 or px.x > float(f["w"]) or px.y > float(f["h"]):
		return null
	return h


## a press on a picture (the dialog one, or a saved one with no dialog open): a drag. A saved picture move is one undo step
func _canvas_grab(p: Vector2) -> bool:
	if dlg.get("t", "") == "canvas":
		var cvf := _canvas_feature(false)
		if String(cvf["path"]) == "" or not bool(cvf["show"]):
			return false
		var h: Variant = _canvas_inside(cvf, p)
		if h == null:
			return false
		cv_drag = {"dlg": true, "from": h, "moved": false}
		return true
	var fs := _feats()
	for i in fs.size():
		var f: Dictionary = fs[i]
		if String(f["t"]) != "canvas" or not bool(f.get("show", true)):
			continue
		var h: Variant = _canvas_inside(f, p)
		if h != null:
			m._step_hint = "Move picture"
			m._push_undo()
			cv_drag = {"i": i, "from": h, "moved": false}
			return true
	return false


func _canvas_move(p: Vector2) -> void:
	var pid := ""
	if cv_drag.get("dlg", false):
		pid = _cv_plane_id()
	else:
		pid = String(_feats()[int(cv_drag["i"])]["plane"])
	var h: Variant = _canvas_hit(p, Part.resolve_plane(_rec(), pid))
	if h == null:
		return
	var d: Vector2 = (h as Vector2) - (cv_drag["from"] as Vector2)
	cv_drag["from"] = h
	if d.length() < 1e-9:
		return
	cv_drag["moved"] = true
	if cv_drag.get("dlg", false):
		var cv: Dictionary = dlg["cv"]
		if (cv["pts"] as Array).size() == 2:
			dlg["anchor"] = (dlg["anchor"] as Vector2) + d
		else:
			cv["at"] = Part.arr2(Vector2(cv["at"][0], cv["at"][1]) + d)
		_preview()
	else:
		var f: Dictionary = _feats()[int(cv_drag["i"])]
		f["at"] = Part.arr2(Vector2(f["at"][0], f["at"][1]) + d)
		bu.sync()
	pov.queue_redraw()


func _canvas_release() -> bool:
	if not cv_drag.get("dlg", false) and not bool(cv_drag.get("moved", false)):
		m._drop_undo()   # a press that moved nothing is no step
	cv_drag = {}
	pov.queue_redraw()
	return true


## the pictures on the view: the saved ones shown (on this plane only, in a sketch), and the dialog one
func _canvas_draw(only: String) -> void:
	var list: Array = []
	var edit := int(dlg.get("edit", -1)) if dlg.get("t", "") == "canvas" else -1
	var fs := _feats()
	for i in fs.size():
		var f: Dictionary = fs[i]
		if String(f["t"]) == "canvas" and i != edit and bool(f.get("show", true)) and (only == "" or String(f["plane"]) == only):
			list.append(f)
	for f in list:
		_canvas_paint(f)
	if dlg.get("t", "") == "canvas" and bool(_canvas_feature(false).get("show", false)) and (only == "" or String(_canvas_feature(false)["plane"]) == only):
		_canvas_paint(_canvas_feature(false), true)   # the dialog's picture: its two calibration points on top


func _canvas_paint(f: Dictionary, working := false) -> void:
	if String(f.get("path", "")) == "":
		return
	var pl := Part.resolve_plane(_rec(), String(f["plane"]))
	var sp := PackedVector2Array()
	for v in Part.canvas_corners(f):
		var w: Vector3 = Part.to_world(pl, v)
		if m.cam.is_position_behind(w):
			return
		sp.append(m.cam.unproject_position(w))
	var a := clampf(float(f.get("opacity", 0.5)), 0.0, 1.0)
	var col := Color(1, 1, 1, a)
	var tex := _canvas_tex(String(f["path"]))
	if tex == null:
		pov.draw_colored_polygon(sp, Color(0.55, 0.6, 0.7, a * 0.5))
	else:
		var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		pov.draw_primitive(PackedVector2Array([sp[0], sp[1], sp[2]]), PackedColorArray([col, col, col]), PackedVector2Array([uv[0], uv[1], uv[2]]), tex)
		pov.draw_primitive(PackedVector2Array([sp[0], sp[2], sp[3]]), PackedColorArray([col, col, col]), PackedVector2Array([uv[0], uv[2], uv[3]]), tex)
	pov.draw_polyline(PackedVector2Array([sp[0], sp[1], sp[2], sp[3], sp[0]]), Color(1.0, 0.76, 0.2, 0.9), 1.5)
	if dlg.get("t", "") == "canvas" and f.has("pts") and not (f["pts"] as Array).is_empty() and working:
		var k := 0
		for pt in f["pts"]:
			k += 1
			var sc: Vector2 = m.cam.unproject_position(Part.to_world(pl, Part.canvas_px_to_mm(f, Part.v2(pt))))
			pov.draw_circle(sc, 6.0, Color("#ffc233"))
			pov.draw_string(ThemeDB.fallback_font, sc + Vector2(8, -8), str(k), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)


func _canvas_tex(path: String) -> Texture2D:
	if path == "":
		return null
	if not cv_tex.has(path):
		var img := Image.load_from_file(path)
		cv_tex[path] = ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null
	return cv_tex[path]


## the browser Pictures: one row each, a click shows or hides it (one undo step)
func _canvas_browser_rows() -> void:
	var cvs := _feats().filter(func(f): return f["t"] == "canvas")
	if cvs.is_empty():
		return
	browser_vb.add_child(_label("Pictures (%d)" % cvs.size(), 15))
	for f in cvs:
		var b := _row_btn("    %s%s" % [String(f["name"]), "" if bool(f.get("show", true)) else "  (hidden)"], "part_canvas_" + String(f["id"]))
		b.tooltip_text = "click to %s the picture" % ("hide" if bool(f.get("show", true)) else "show")
		b.pressed.connect(_canvas_toggle.bind(String(f["id"])))
		browser_vb.add_child(b)


func _canvas_toggle(id: String) -> void:
	var rec := _rec()
	var i := Part.index_of(rec, id)
	if i < 0:
		return
	var f: Dictionary = rec["features"][i]
	m._step_hint = "Show picture" if not bool(f.get("show", true)) else "Hide picture"
	m._push_undo()
	f["show"] = not bool(f.get("show", true))
	_say("%s %s" % [String(f["name"]), "is shown" if f["show"] else "is hidden"])
	bu.sync()
