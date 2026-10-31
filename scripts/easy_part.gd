class_name EasyPart
extends "res://scripts/easy_part_pull.gd"
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
	restore_btn = _bar_btn("Bring back your part", "Bring back the part you were making, as it was after your last step (saved as you go)", _restore)   # NAUTOSAVE
	restore_btn.name = "easypart_restore"
	restore_btn.custom_minimum_size.x = 190.0
	restore_btn.visible = false
	row.add_child(restore_btn)
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
	var sh := HFlowContainer.new()   # wraps when the room left of the panel is short (layout clamps its width), so it never runs under the panel
	sh.add_theme_constant_override("h_separation", 6)
	sh.add_theme_constant_override("v_separation", 4)
	shape_box.add_child(sh)
	for s in [["box", "Box"], ["round", "Round"], ["pointy", "Pointy"], ["oval", "Oval"], ["hex", "Hex"], ["line", "Line"]]:   # P040 Line: a drag of straight stretches, a stretch held with Shift is a curve. FSPOON: Oval = an ellipse fitted to the drag box (a bowl, a pad); FBOLT: Hex = a regular hexagon in the drag box (bolt head, nut)
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
	var pic := Button.new()   # P034: Picture: your own picture becomes a raised logo (a press opens the file dialog, not a drag)
	pic.name = "easypart_shape_picture"
	pic.text = "Picture"
	pic.focus_mode = Control.FOCUS_NONE
	pic.custom_minimum_size = Vector2(96, 40)
	pic.add_theme_font_size_override("font_size", 16)
	pic.tooltip_text = "Your own picture: a dark shape on white becomes a raised logo, 4 cm wide and 2 mm high, in one step"
	pic.pressed.connect(_picture_press)
	sh.add_child(pic)
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
	explode_box = _explode_box()
	root.add_child(explode_box)
	size_box = _size_box()   # p052scalepiece: the Size % slider of a picked piece (easy_part_stick.gd)
	root.add_child(size_box)
	tilt_box = _tilt_box()
	root.add_child(tilt_box)
	steps_box = _steps_box()   # NSTEPLIST
	root.add_child(steps_box)
	flat_box = _printing_box()   # p113: under the step list
	root.add_child(flat_box)
	# the panel
	panel = PanelContainer.new()
	panel.name = "easypart_panel"
	panel.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.95), 12, 8))   # 8 (was 12): the Use Expert foot sits in the clear view with a sword open
	panel.visible = false
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.name = "easypart_panel_vb"
	v.add_theme_constant_override("separation", 4)
	panel_vb = v
	var sc := ScrollContainer.new()   # the panel's column scrolls inside the panel when it is taller than the room (a Where-to-cut row adds one)
	sc.name = "easypart_panel_scroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(sc)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	panel_title = Label.new()
	panel_title.name = "easypart_panel_title"
	panel_title.add_theme_font_size_override("font_size", 20)   # 20 (was 22): the title line holds Empty and Examples too, inside the panel's width
	panel_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_title.clip_text = true
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
	view_box = PanelContainer.new()   # P107 FITVIEW: the view row (camera only, no step) sits in the clear view's left column under the make row, not in the side panel (the panel grew over the step list and the grid)
	view_box.name = "easypart_views_box"
	view_box.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.92), 10, 6))
	view_box.visible = false
	root.add_child(view_box)
	var vr := VBoxContainer.new()   # a column: narrow, so it sits beside the panel without reaching the part
	vr.name = "easypart_views"
	vr.add_theme_constant_override("separation", 4)
	view_box.add_child(vr)
	for vb in VIEW_BTNS:
		var vbtn := Button.new()
		vbtn.name = "easypart_view_" + String(vb[0])
		vbtn.text = String(vb[1])
		vbtn.icon = Icons.sized(String(vb[2]), 16)
		vbtn.expand_icon = false
		vbtn.tooltip_text = String(vb[3])
		vbtn.focus_mode = Control.FOCUS_NONE
		vbtn.custom_minimum_size = Vector2(0, 30)
		vbtn.add_theme_font_size_override("font_size", 13)
		vbtn.pressed.connect(_view_press.bind(String(vb[0])))
		vr.add_child(vbtn)
	vr.add_child(_cut_btn())   # P101 SECTION: the Cut view chip, last in the same view column (no new row)
	var cr := HFlowContainer.new()
	cr.name = "easypart_chips"
	cr.add_theme_constant_override("h_separation", 2)
	cr.add_theme_constant_override("v_separation", 4)
	v.add_child(cr)
	parts_btn = Button.new()   # NSCREW2: Parts: the screw sizes; after the template chips on the same row
	parts_btn.name = "easypart_chip_parts"
	parts_btn.text = "Parts"
	parts_btn.tooltip_text = "Parts: a library of small parts by kind (screws, gears and wheels now, more soon)"
	parts_btn.toggle_mode = true
	parts_btn.focus_mode = Control.FOCUS_NONE
	parts_btn.custom_minimum_size = Vector2(0, 34)
	parts_btn.add_theme_font_size_override("font_size", 15)
	parts_btn.pressed.connect(_parts_press)
	var start_l := Label.new()   # FREESTART: a neutral row of simple shapes; nothing is forced, the Empty part is the default
	start_l.name = "easypart_start_label"
	start_l.text = "Start from:"
	start_l.add_theme_font_size_override("font_size", 15)
	start_l.add_theme_color_override("font_color", Color(0.7, 0.73, 0.78))
	start_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	start_l.visible = false   # the row speaks for itself (Box, Cylinder ...): its 80 px let Rack stay on ONE line, so the Parts page fits the panel at 1280 x 720
	cr.add_child(start_l)
	for t in PartTemplates.START + ["gear", "rack"]:   # the simple shapes; gear stays on the row (NGEAR), rack beside it (P066: its pinion); the weapons and props are under More examples
		var b := Button.new()
		b.name = "easypart_chip_" + t
		b.text = CHIP_TEXT.get(t, String(PartTemplates.T[t]["title"]))   # the chip word on the blank part is plain; the part keeps the template title
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 34)
		b.add_theme_font_size_override("font_size", 11)   # NGEAR: 13 (was 15) so six templates (Gear) stay on one row of the panel; P066: 11 so seven (Rack) do too
		b.pressed.connect(_chip.bind(t))
		b.mouse_entered.connect(_tpl_hover.bind(t, true))   # P091: hover a shape chip = see its ghost first
		b.mouse_exited.connect(_tpl_hover.bind(t, false))
		cr.add_child(b)
		for sn in ["normal", "hover", "pressed", "focus", "disabled"]:   # P066: 4 px side margins (the theme's are wider) so seven chips (Rack) stay on one row
			var sb := b.get_theme_stylebox(sn).duplicate() as StyleBox
			sb.content_margin_left = 4.0
			sb.content_margin_right = 4.0
			b.add_theme_stylebox_override(sn, sb)
		chips[t] = b
	var more := Button.new()   # the weapons and props are not gone: What to build (From a template) lists them
	more.name = "easypart_more_examples"
	more.text = "Examples"
	more.tooltip_text = "Open What to build: a sword, an axe, a chair and more"
	more.focus_mode = Control.FOCUS_NONE
	more.custom_minimum_size = Vector2(0, 34)
	more.add_theme_font_size_override("font_size", 13)
	more.pressed.connect(_more_examples)
	th.add_child(more)   # on the title line beside Empty (other ways to start): on the Start row it wrapped to a second line once Rack joined, and the Parts page ran out of the panel
	lib_box = _lib_box()
	v.add_child(lib_box)
	fav_box = _fav_box()   # p083favfix: the Favourites category page (its row and the star), right under the Parts chips: the screw grid of a screw on the floor sits below it, so the star stays in the scroll view
	v.add_child(fav_box)
	screw_box = _screw_box()
	v.add_child(screw_box)
	bear_box = _bear_box()   # P069 BEARINGS: the bearing chips and the seat button, under the Parts page
	v.add_child(bear_box)
	bracket_box = _bracket_box()   # FRIDAY 73
	v.add_child(bracket_box)
	clip_box = _clip_box()
	v.add_child(clip_box)
	handle_box = _handle_box()   # P071 HANDLES: the Handles grid under the library page
	v.add_child(handle_box)
	wheel_box = _wheel_box()   # P072: the Wheels page's chips
	v.add_child(wheel_box)
	board_box = _board_box()   # p078makeacasef: the Boards chips (a case for the board)
	v.add_child(board_box)
	rows_vb = VBoxContainer.new()
	rows_vb.name = "easypart_rows"
	rows_vb.add_theme_constant_override("separation", 2)
	v.add_child(rows_vb)
	v.add_child(_suggest_row())   # P092: the two next-step chips, under the slider rows (the rows above keep their places)
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
	back_btn.custom_minimum_size = Vector2(0, 32)
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
	var h := HFlowContainer.new()   # P076: a flow, so the row wraps to a second line when the What fits here? chip would run past the window's right edge
	h.add_theme_constant_override("h_separation", 6)
	h.add_theme_constant_override("v_separation", 6)
	h.custom_minimum_size = Vector2(720, 0)   # P076: the chips wrap at 720 px (two short rows, clear of Change your part), not one narrow column
	box.add_child(h)
	for hm in [["through", "Through", "A round hole straight through the middle"], ["hollow", "Hollow inside", "Hollow the solid out, open at the top, with a wall (the Wall slider)"], ["lid", "Hollow with a lid", "Hollow the box out with a 3 mm wall; its top 5 mm comes off as a lid with a lip that sits inside the box"], ["fingers", "Finger joints", "Cut a comb of notches along the top edge of the box, for a laser-cut box: each finger is 3 mm, the notch a third of the height"]]:
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
	wall_btn = _big_btn("easypart_hole_wall", "Thicker wall", "Pick one side wall of the hollow: that wall gets its own thickness (the Extra wall slider)", _wall_chip)
	wall_btn.toggle_mode = true
	wall_btn.custom_minimum_size = Vector2(150, 44)
	wall_btn.visible = false
	h.add_child(wall_btn)
	var mb := _big_btn("easypart_hole_magnet", "Magnet", "A round pocket for a 6 mm x 3 mm magnet on the top face: the magnet sits in it, flush. The Magnet size slider sets its width", _hole_mode.bind("magnet"))   # p074magnetsapo
	mb.toggle_mode = true
	mb.custom_minimum_size = Vector2(96, 44)
	h.add_child(mb)
	hole_btns["magnet"] = mb
	for sd in SCREW_CLEAR:   # p030countersun: one chip per screw size: the hole is sized to the screw (M3 3.4 mm ... M6 6.6 mm)
		var sb := _big_btn("easypart_hole_screw%d" % sd, "M%d screw" % sd, "A hole for an M%d socket screw: a clearance hole, and a counterbore on the top face for its head" % sd, _hole_mode.bind("screw%d" % sd))
		sb.toggle_mode = true
		sb.custom_minimum_size = Vector2(96, 44)
		h.add_child(sb)
		hole_btns["screw%d" % sd] = sb
	var fb := _big_btn("easypart_hole_fits", "What fits here?", "Ask which of My Parts go through this hole (the saved parts that fit it). No step: it only tells you", _fits_press)   # P076
	fb.custom_minimum_size = Vector2(150, 44)
	h.add_child(fb)
	return box


## P076 WHAT FITS HERE?: the hole is the newest cut's round sketch (its diameter in mm, _hole_mm). A saved part (MyParts) fits when its two
## smallest sides, corner to corner, are at most the hole less FIT_CLEAR (0.4 mm: 0.2 mm to spare on each side). Words only: no undo step
const FIT_CLEAR := 0.4   # mm: the diagonal of a part's two smallest sides must be this much under the hole's width


func _fits_press() -> void:
	var d := _hole_mm(_rec())
	if d <= 0.0:
		_say("Cut a hole first, then ask what fits it. This answer is for a round hole")
		return
	var saved := MyParts.list()
	if saved.is_empty():
		_say("No saved parts yet. Make a part, use Save to My Parts, then ask again")
		return
	var fits: Array = []
	for it in saved:
		var res := Part.replay(it["record"])
		if int(res["bodies"]) == 0:
			continue
		var sz: Vector3 = (res["aabb"] as AABB).size / Part.MM
		var a := [sz.x, sz.y, sz.z]
		a.sort()
		if sqrt(a[0] * a[0] + a[1] * a[1]) <= d - FIT_CLEAR:
			fits.append(String(it["name"]))
	var mm := _mm_words(d)
	if fits.is_empty():
		_say("Nothing saved fits this %s mm hole. Make the hole bigger, or save a thinner part" % mm)
	else:
		_say("Parts that fit this %s mm hole: %s" % [mm, ", ".join(fits)])


## the diameter in mm of the newest round cut (the hole the chips made), or -1 when the newest cut is not round
func _hole_mm(rec: Dictionary) -> float:
	var feats: Array = rec.get("features", [])
	for i in range(feats.size() - 1, -1, -1):
		var f: Dictionary = feats[i]
		if String(f.get("t", "")) == "extrude" and String(f.get("op", "")) == "cut":
			var sk := Part.feature(rec, String(f.get("sketch", "")))
			for e in sk.get("ents", []):
				if String(e.get("k", "")) == "circle":
					return 2.0 * float(e.get("r", 0.0))
			return -1.0
	return -1.0




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
	# p038makeitstro: a press adds a rib where the solid is thin (no toggle: the press is the step)
	var sb := _big_btn("easypart_stronger", "Make it stronger", "Add a rib where the solid is thin: a strip on its thin side, along its long side", _stronger_press)
	sb.icon = Icons.sized("part_stronger", 22)
	sb.expand_icon = false
	sb.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sb.custom_minimum_size = Vector2(176, 44)
	h.add_child(sb)
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
	# p057 WEIGHT: the whole Part's weight if it were made of each material (volume x density). A readout: it changes nothing in the Part
	for wk in WEIGHT_CHIPS:
		var wb := _colour_btn("weight_" + String(wk[0]), "", Color(0.7, 0.72, 0.76))
		wb.name = "easypart_weight_" + String(wk[0])
		wb.custom_minimum_size.x = 118.0
		wb.tooltip_text = "How heavy the whole part would be if it were solid %s (its volume x the density of %s). Shows only: press it to read it out" % [wk[1], wk[1]]
		wb.pressed.connect(_weight_press.bind(String(wk[0])))
		h.add_child(wb)
		weight_btns[String(wk[0])] = wb
	h.add_child(_hold_chip())   # p131grippoint: Hold here, the last chip of the page
	return box


## WEIGHT (p057): the weight chips show the Part's weight in each material; read again only when the Part's steps change
func _weight_sync() -> void:
	var key: int = _rec().get("features", []).hash()
	if key == weight_key:
		return
	weight_key = key
	weight_kg_by = PartWeapon.weight_kg(_rec())
	for wk in WEIGHT_CHIPS:
		var b := weight_btns[String(wk[0])] as Button
		var kg := float(weight_kg_by.get(String(wk[0]), -1.0))
		if kg < 0.0:
			b.text = "%s: no solid" % wk[1]
		elif kg < 1.0:
			b.text = "%d g %s" % [roundi(kg * 1000.0), wk[1]]
		else:
			b.text = "%.2f kg %s" % [kg, wk[1]]


## WEIGHT press: one sentence in plain words. No step, no undo
func _weight_press(k: String) -> void:
	_weight_sync()
	var word := ""
	for wk in WEIGHT_CHIPS:
		if String(wk[0]) == k:
			word = String(wk[1])
	if weight_kg_by.is_empty():
		_say("No weight yet: Pull it up or Spin it round first, then the weight shows here")
		return
	_say("Solid %s, this whole part would weigh %s" % [word, (weight_btns[k] as Button).text.trim_suffix(" " + word)])


## TILT IT: the newest solid (a Pull it up or a Spin it round, not yet tilted) leans TILT_DEG about X through its middle. One step, once
func _tilt_box() -> PanelContainer:
	var box := PanelContainer.new()
	box.name = "easypart_tilt"
	box.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.92), 10, 6))
	box.visible = false
	var row := VBoxContainer.new()   # p021: Tilt it and Draft angle share the one panel (only one of them shows for a given newest step); stacked, the panel stays narrow so it never covers the solid under it
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	tilt_btn = _big_btn("easypart_tilt_it", "Tilt it 20 degrees", "Lean the newest solid 20 degrees, sideways, about its middle", _tilt_press)
	tilt_btn.custom_minimum_size = Vector2(230, 44)
	row.add_child(tilt_btn)
	draft_btn = _big_btn("easypart_draft_angle", "Draft angle", "Easier to pull from a mould: the side walls lean 2 degrees in, the base stays put", _draft_press)
	# p123driveit: Swing it shares the Draft angle line (one row, so the panel is no taller and never climbs over the grid)
	var draft_row := HBoxContainer.new()
	draft_row.add_theme_constant_override("separation", 6)
	row.add_child(draft_row)
	draft_row.add_child(draft_btn)
	swing_btn = _big_btn("easypart_swing_it", "Swing it", "Drive it: the newest piece swings open on a hinge at its back top edge, 90 degrees in 2 seconds, as a step on the timeline", _swing_press)
	swing_btn.icon = Icons.sized("part_swing", 22)
	swing_btn.expand_icon = false
	swing_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	swing_btn.custom_minimum_size = Vector2(170, 44)
	swing_btn.visible = false
	draft_row.add_child(swing_btn)
	pull_along_btn = _big_btn("easypart_pull_along", "Pull along", "Pull the round shape along the open curve: a pipe in one step", _pull_along_press)
	pull_along_btn.custom_minimum_size = Vector2(230, 44)
	pull_along_btn.visible = false
	row.add_child(pull_along_btn)
	return box


## P092: the next steps after a Pull it up, in plain words (one press each, one undo step). They sit in the right panel's column under
## the slider rows (off the grid, the step list and the timeline), in one row that shows only while the newest step is a Pull it up
func _suggest_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "easypart_suggest"
	row.add_theme_constant_override("separation", 6)
	row.visible = false
	suggest_round_btn = _big_btn("easypart_suggest_round", "Round the edges?", "Next step: soften the sharp edges of this solid", _suggest_round_press)
	suggest_round_btn.icon = Icons.tex("part_fillet")
	suggest_round_btn.custom_minimum_size = Vector2(0, 44)
	suggest_round_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(suggest_round_btn)
	suggest_hollow_btn = _big_btn("easypart_suggest_hollow", "Hollow it?", "Next step: hollow this solid out, open at the top, with a 3 mm wall", _suggest_hollow_press)
	suggest_hollow_btn.icon = Icons.tex("part_circle")
	suggest_hollow_btn.custom_minimum_size = Vector2(0, 44)
	suggest_hollow_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(suggest_hollow_btn)
	suggest_row = row
	return row


## P092: the newest step is a Pull it up (a solid, not a cut, not switched off): the two next-step chips show under it
func _suggest_on() -> bool:
	var feats: Array = _rec().get("features", [])
	if feats.is_empty():
		return false
	var f: Dictionary = feats[feats.size() - 1]
	return String(f.get("t", "")) == "extrude" and not bool(f.get("off", false)) and String(f.get("op", "join")) != "cut"


## P092: "Round the edges?" is the Round the edges press (same rules, same one undo step)
func _suggest_round_press() -> void:
	_make("round")


## P092: "Hollow it?" is Hollow inside on the newest solid, in ONE step (no Cut a hole press first). Its wall and open top are the
## Hollow inside ones, so the Wall slider and the hole chips work after it. A solid that is too thin says so and changes nothing
func _suggest_hollow_press() -> void:
	if not Part.available():
		_say(Part.why_not())
		return
	_flush_if_dirty()
	armed = ""
	wall_pick = false
	var snap := _rec().duplicate(true)
	_begin("Hollow inside")
	var rec := pu._ensure()
	var why := _hollow(rec)
	if why != "":
		m.S.part = snap
		m._drop_undo()
		_edit_n = -1
		_say(why)
	else:
		_end()
		hole_base = snap
		hole_mode = "hollow"
		hole_id = String(tweak.get("id", ""))
		_rows_sig = ""
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_values_sync()


## DRAFT ANGLE (p021, "Easier to pull from a mould"): the newest solid is a pulled-up piece with no draft yet. Its straight side walls lean
## DRAFT_DEG about its bottom (Part's draft step, pulled along Y: the top gets narrower). The walls are found by the replay, so the step follows them
func _draft_ok(rec: Dictionary) -> bool:
	var feats: Array = rec.get("features", [])
	if feats.is_empty():
		return false
	var f: Dictionary = feats[feats.size() - 1]
	return String(f.get("t", "")) == "extrude" and not bool(f.get("off", false)) and String(f.get("op", "join")) != "cut"


func _draft_press() -> void:
	if not Part.available():
		_say(Part.why_not())
		return
	_flush_if_dirty()
	armed = ""
	if not _draft_ok(_rec()):
		_say("Draft angle leans a pulled-up solid: press Pull it up first, then Draft angle")
		return
	var res := Part.replay(_rec(), -1, {"faces": true})
	if int(res["bodies"]) != 1:
		_say("Draft angle works on one solid: press Stick together to make the pieces one solid first")
		return
	var walls: Array = []
	for fc in res.get("faces", []):
		var n: Vector3 = fc["n"]
		if int(fc["body"]) == 0 and absf(n.y) < 0.02:   # a level normal: a side wall, not the top or the base
			walls.append(Part.describe_face(fc))
	if walls.is_empty():
		_say("No straight side walls to lean: draw a box or a round shape, then Pull it up")
		return
	var snap := _rec().duplicate(true)
	_begin("Draft angle")
	var f := Part.new_feature(_rec(), "draft", {"body": 0, "faces": walls, "deg": DRAFT_DEG, "dir": "y"})
	_rec()["features"].append(f)
	if _last_error(_rec(), String(f["id"])) != "":
		m.S.part = snap
		m._drop_undo()
		_edit_n = -1
		_say("Those walls cannot lean: the part would not stay on the model")
		return
	_end()
	_say("Draft angle: the side walls lean 2 degrees, so the part pulls out of a mould easier. Ctrl+Z undoes it")
	pu.upto = -1
	pu.sync()


## SWING IT (p123driveit, Friday plan 123, "Drive it: a lid opens, a gear turns"): with two or more pieces, the newest one swings open on a
## hinge step: its pivot is the back top edge of its own box (lowest Z, highest Y), the axis is X, 90 degrees in SWING_SECS seconds. The hinge
## adds no solid (the timeline shows the rest pose, as in Expert Part); the swing is checked with Part.hinge_sweep and the words say what it hit
const SWING_DEG := 90.0
const SWING_SECS := 2.0


func _swing_ok(rec: Dictionary) -> bool:
	var feats: Array = rec.get("features", [])
	if feats.is_empty() or int(pu.res.get("bodies", 0)) < 2:
		return false
	return String(feats[feats.size() - 1].get("t", "")) != "hinge"


func _swing_press() -> void:
	if not Part.available():
		_say(Part.why_not())
		return
	_flush_if_dirty()
	armed = ""
	if not _swing_ok(_rec()):
		_say("Swing it needs two pieces: make a second piece, then press Swing it")
		return
	var faces: Array = Part.body_faces(_rec(), -1)
	var bi := faces.size() - 1
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in faces[bi]:
		lo = lo.min(v)
		hi = hi.max(v)
	var o := Vector3(lo.x, hi.y, lo.z) / Part.MM
	var snap := _rec().duplicate(true)
	_begin("Swing it")
	var f := Part.new_feature(_rec(), "hinge", {"body": bi, "o": [o.x, o.y, o.z], "axis": [1.0, 0.0, 0.0], "track": [[0.0, 0.0], [SWING_SECS, SWING_DEG]]})
	_rec()["features"].append(f)
	if _last_error(_rec(), String(f["id"])) != "":
		m.S.part = snap
		m._drop_undo()
		_edit_n = -1
		_say("This piece cannot swing from its back top edge: Undo, then try a different piece")
		return
	_end()
	var sw := Part.hinge_sweep(_rec(), String(f["id"]))
	if not bool(sw.get("ok", false)):
		_say("Swing it: the step is made, but the swing cannot be checked: %s" % String(sw.get("why", "")))
	elif int(sw.get("first", -1)) >= 0:
		_say("Swing it: the piece hits the other piece at %s s. Undo, or move the pieces apart" % _plain_num(float(sw.get("first_s", 0.0))))
	else:
		_say("Swing it: the piece swings open %d degrees in %d seconds and clears the other piece. Ctrl+Z undoes it" % [int(SWING_DEG), int(SWING_SECS)])
	pu.upto = -1
	pu.sync()


## P026 PULL ALONG: the open curve (the path: a Curvy line that does not come back to its start) and a closed shape (the round or box
## the pipe is pulled from) are both there, and the newest step is a sketch: the chip shows. Returns the two sketch ids [profile, path] or []
func _along_pick(rec: Dictionary) -> Array:
	var feats: Array = rec.get("features", [])
	var path := ""
	var shape := ""
	var shape_free := ""
	for i in range(feats.size() - 1, -1, -1):
		var f: Dictionary = feats[i]
		if String(f.get("t", "")) != "sketch":
			continue
		var ents: Array = f.get("ents", [])
		var closed := false
		for e in ents:
			var k := String(e.get("k", ""))
			if k == "circle" or k == "rect" or (k == "bspline" and bool(e.get("closed", false))):
				closed = true
		var sid := String(f.get("id", ""))
		if closed and shape == "":
			shape = sid
		if closed and shape_free == "" and not Part.sketch_used(rec, sid):
			shape_free = sid
		elif not closed and not ents.is_empty() and path == "":
			path = sid
	if shape_free != "":
		shape = shape_free
	if path == "" or shape == "":
		return []
	return [shape, path]


## the chip shows when the newest step is a sketch and _along_pick finds both sketches
func _along_ok(rec: Dictionary) -> bool:
	var feats: Array = rec.get("features", [])
	return not feats.is_empty() and String(feats[feats.size() - 1].get("t", "")) == "sketch" and not _along_pick(rec).is_empty()


## P026: Pull along makes one sweep step (the round shape at the curve's start, pulled along it: a pipe). One step, one undo
func _pull_along_press() -> void:
	if not Part.available():
		_say(Part.why_not())
		return
	_flush_if_dirty()
	armed = ""
	var ids := _along_pick(_rec())
	if ids.is_empty():
		_say("Pull along needs a round or box shape and a Curvy line that is open: Draw shape, then Curvy line, and do not drag back to the start")
		return
	var snap := _rec().duplicate(true)
	_begin("Pull along")
	var rec := pu._ensure()
	var f := Part.new_feature(rec, "sweep", {"profile": ids[0], "path": ids[1], "op": "join"})
	rec["features"].append(f)
	var err := _last_error(rec, String(f["id"]))
	if err != "":
		m.S.part = snap
		m._drop_undo()
		_edit_n = -1
		_say("Pull along did not make a pipe: %s. Draw a gentler curve, or a smaller round shape" % err)
		return
	_end()
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_values_sync()
	_say("Pulled along the curve: a pipe. Undo takes it back")


## P034 YOUR OWN PICTURE: Picture (in the Draw shape row) opens a file dialog; the picture's dark shape becomes a raised logo on the
## floor: a closed outline sketch, pulled up 2 mm, ONE undo step. The words say the next step when the picture cannot be used
const PICTURE_MM := 40.0   # the logo's longer side
const PICTURE_H := 2.0     # the raised height


func _picture_press() -> void:
	if not Part.available():
		_say(Part.why_not())
		return
	_flush_if_dirty()
	var fd := FileDialog.new()
	fd.name = "easypart_picture_dialog"
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp ; Pictures"])
	fd.title = "Pick your picture"
	fd.file_selected.connect(func(p: String): fd.queue_free(); _picture_chosen(p))
	fd.canceled.connect(fd.queue_free)
	shape_box.get_parent().add_child(fd)
	fd.popup_centered(Vector2i(640, 480))
	_say("Pick a picture: a dark shape on white works best")


func _picture_chosen(path: String) -> void:
	if not Part.available():
		_say(Part.why_not())
		return
	var got: Dictionary = PictureTrace.outline(path, PICTURE_MM)
	if String(got["why"]) != "":
		_say(String(got["why"]))
		return
	_flush_if_dirty()
	var snap := _rec().duplicate(true)
	_begin("Your picture")
	var rec := pu._ensure()
	var sk := Part.new_feature(rec, "sketch", {"plane": "top", "ents": got["ents"], "dims": []})
	rec["features"].append(sk)
	var f := Part.new_feature(rec, "extrude", {"sketch": String(sk["id"]), "dist": PICTURE_H, "both": false, "op": "join"})
	rec["features"].append(f)
	var err := _last_error(rec, String(f["id"]))
	if err != "":
		m.S.part = snap
		m._drop_undo()
		_edit_n = -1
		_say("Your picture did not make a raised logo: %s. Use a picture with a bigger, plainer dark shape" % err)
		return
	_end()
	armed = ""
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_values_sync()
	_say("Your picture is a raised logo 2 mm high. Undo takes it back")


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


var lay_btn: Button         # p113: Lay it flat, in the printing box under any solid
var paint_btn: Button       # p113: Show overhangs (a toggle chip)
var paint_on := false       # p113: the red overhang faces are on
var _ov_mesh: MeshInstance3D   # p113: the red copy of the overhang faces, over the part
var _ov_key := ""           # p113: the record the red copy was built from

## p113 LAY IT FLAT: the one step turns the part so its best face (the least overhang, see Part.lay_plan) sits on the floor. One undo step
func _lay_press() -> void:
	if not Part.available():
		_say(Part.why_not())
		return
	_flush_if_dirty()
	armed = ""
	var plan := Part.lay_plan(_rec())
	if not bool(plan["ok"]):
		_say(String(plan["why"]))
		return
	var snap := _rec().duplicate(true)
	_begin("Lay it flat")
	var f := Part.new_feature(_rec(), "lay", {"axis": plan["axis"], "deg": plan["deg"]})
	_rec()["features"].append(f)
	if _last_error(_rec(), String(f["id"])) != "":
		m.S.part = snap
		m._drop_undo()
		_edit_n = -1
		_say("That part cannot lie flat on that face")
		return
	_end()
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_values_sync()
	_ov_key = ""
	_say("Laid flat on its best face: %.1f cm2 of support under it (was %.1f). Ctrl+Z undoes it" % [float(plan["now"]) / 100.0, float(plan["was"]) / 100.0])


## p113 SHOW OVERHANGS: the red chip. Red sits on the faces that need support when printed (see Part.overhang_faces_of)
func _paint_press() -> void:
	paint_on = not paint_on
	_ov_key = ""
	if not paint_on:
		_say("")
		return
	var n := Part.overhang_faces_of(_rec()).size()
	_say("Red: %d faces point down more than 45 degrees and need support when printed" % n if n > 0 else "Nothing is red: no face needs support when printed")


## p113: the red copy of the faces that need support, laid over the part (rebuilt when the record changes; hidden when the chip is off)
func _overhang_sync(show_ok: bool) -> void:
	if _ov_mesh == null:
		_ov_mesh = MeshInstance3D.new()
		_ov_mesh.name = "easypart_overhangs"
		var red := StandardMaterial3D.new()   # p113: a flat red with no light, so the mark reads the same on any face
		red.albedo_color = Color(0.9, 0.12, 0.1)
		red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		red.cull_mode = BaseMaterial3D.CULL_DISABLED
		_ov_mesh.material_override = red
		_ov_mesh.visible = false
		pu.bu.root3.add_child(_ov_mesh)
	var on_part: bool = paint_on and show_ok and pu.part_mesh != null and pu.part_mesh.mesh != null and pu.part_mesh.visible
	if not on_part:
		_ov_mesh.visible = false
		return
	var key := JSON.stringify(_rec())
	if key != _ov_key:
		_ov_key = key
		_ov_mesh.mesh = _overhang_mesh()
	_ov_mesh.global_transform = pu.part_mesh.global_transform
	_ov_mesh.visible = _ov_mesh.mesh != null


## the triangles of the shown result that lie in an overhang face (the face's plane and its normal), lifted 0.2 mm off the face
func _overhang_mesh() -> ArrayMesh:
	var faces := Part.overhang_faces_of(_rec())
	if faces.is_empty():
		return null
	var tris := PackedVector3Array()   # _shown_faces: one array of triangle corners per body (or the shown mesh as one)
	for part_tris in _shown_faces():
		tris.append_array(part_tris)
	var verts := PackedVector3Array()
	for k in range(0, tris.size() - 2, 3):
		var a: Vector3 = tris[k]
		var b: Vector3 = tris[k + 1]
		var c: Vector3 = tris[k + 2]
		var tn := (b - a).cross(c - a)
		if tn.length_squared() < 1e-18:
			continue
		tn = tn.normalized()
		var cen := (a + b + c) / 3.0
		for fc in faces:
			var n: Vector3 = fc["n"]
			if absf(tn.dot(n)) > 0.999 and absf((cen - (fc["c"] as Vector3)).dot(n)) < 1e-4:
				for v in [a, b, c]:
					verts.append(v + n * 2e-4)
				break
	if verts.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


# ---------------------------------------------------------------- autosave (NAUTOSAVE)

## every step is saved to auto_path as a Part record (the same file shape as a saved part). An empty part saves nothing, so a
## part that is undone to nothing keeps the last saved steps for "Bring back your part"
func _autosave() -> void:
	var rec := _rec()
	if (rec.get("features", []) as Array).is_empty():
		return
	var txt := JSON.stringify(Part.to_file(rec))
	if txt == _auto_json:
		return
	_auto_json = txt
	DirAccess.make_dir_recursive_absolute(auto_path.get_base_dir())
	var f := FileAccess.open(auto_path, FileAccess.WRITE)
	if f != null:
		f.store_string(txt)
		f.close()


## the button shows only on an empty part while a saved part is there (the next start)
func _restore_sync() -> void:
	if restore_btn == null:
		return
	restore_btn.visible = (_rec().get("features", []) as Array).is_empty() and FileAccess.file_exists(auto_path)


## Bring back your part: the saved steps come back as ONE undo step (Undo takes them back, Redo puts them back)
func _restore() -> void:
	if not FileAccess.file_exists(auto_path):
		_say("Nothing saved yet: draw a shape and pull it up, then it is kept here")
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(auto_path))
	var rec := Part.from_file(d)
	if rec.is_empty() or (rec.get("features", []) as Array).is_empty():
		_say("The saved part cannot be read. Draw a new shape to start again")
		return
	m._push_undo()
	m.S.part = rec
	_auto_json = ""
	pu.upto = -1
	pu.sync()
	_say("Brought back your part. Undo takes it back")
	_restore_sync()


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


# ---------------------------------------------------------------- sliders and their rows

func _set_value(row: Dictionary, v: float, final: bool) -> void:
	if row["kind"] == "tpl":
		_pending[row["key"]] = v if bool(row.get("raw", false)) else v * 10.0   # the slider says cm, the record mm (NGEAR: a raw slider says its own number)
		hole_base = {}                    # the template's sizes changed: the hole chips would rebuild on an old shape
	elif row["kind"] == "rep":
		_apply_rep(row, v)
	elif row["kind"] == "taper":
		_apply_taper(v)
	elif row["kind"] == "twist":
		_apply_twist(v)
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
	pu.upto = -1   # p089scrubthehi: a change is made on the whole part, not on a scrubbed view
	var f := Part.feature(_rec(), String(tweak["id"]))
	if f.is_empty():
		return
	var val: float = v * float(tweak.get("scale", 1.0)) * float(tweak.get("sgn", 1.0))
	if tweak.has("ent"):
		f["ents"][int(tweak["ent"])][tweak["field"]] = val
	else:
		f[tweak["field"]] = val
	if f.has("raw"):   # p039: a Curvy line's points come back from its raw stroke at the new Smooth
		_rebuild_curve(f)


## FPLANTER: the Taper slider writes the pulled shape's taper (degrees; the kernel narrows the extrude when it is positive)
func _apply_taper(v: float) -> void:
	var f := Part.feature(_rec(), String(taper_tw.get("id", "")))
	if not f.is_empty():
		f["taper"] = v


## P024: the Twist slider writes the pulled shape's twist (degrees, the kernel turns the extrude as it rises)
func _apply_twist(v: float) -> void:
	var f := Part.feature(_rec(), String(twist_tw.get("id", "")))
	if not f.is_empty():
		f["twist"] = v


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
	pu.coarse = true   # NSLIDELOD: the part shows a coarse preview while the slider is in hand
	_begin("Change " + String(row["label"]))


func _on_slider_end(_changed: bool, row: Dictionary) -> void:
	row["held"] = false
	pu.coarse = false   # NSLIDELOD: full detail on release (the final write below rebuilds it)
	_set_value(row, (row["slider"] as HSlider).value, true)
	_end()


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
	pill.add_theme_stylebox_override("normal", _style(Color(0.17, 0.18, 0.22), 14, 4))
	top.add_child(pill)
	v.add_child(top)
	var s := HSlider.new()
	s.name = "easypart_slider_" + key
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.focus_mode = Control.FOCUS_NONE
	s.custom_minimum_size = Vector2(0, 22)
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
	twist_row = {}
	if _taper_live():   # FPLANTER: the Taper row sits UNDER How far; it is not in rows (rows[-1] stays the step's own slider)
		# P024: the Twist slider shares the Taper row's line (side by side), so a pull with a Twist costs no more height than one with a Taper
		# alone: the side panel stays as tall, and the drawing area under it stays as clear (fdelete draws beside a piece there)
		var pair := HBoxContainer.new()
		pair.name = "easypart_taper_pair"
		rows_vb.add_child(pair)
		taper_row = _make_row(String(taper_tw["label"]), float(taper_tw["lo"]), float(taper_tw["hi"]), float(taper_tw["step"]), taper_tw["words"], "taper", "taper", String(taper_tw["unit"]), pair)
		(taper_row["words"] as Control).visible = not _compact
		if not twist_tw.is_empty():
			twist_row = _make_row(String(twist_tw["label"]), float(twist_tw["lo"]), float(twist_tw["hi"]), float(twist_tw["step"]), twist_tw["words"], "twist", "twist", String(twist_tw["unit"]), pair)
			(twist_row["words"] as Control).visible = not _compact
			(twist_row["box"] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(taper_row["box"] as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for r in rows:
		(r["words"] as Control).visible = not _compact
	_values_sync()


## FPLANTER: the Taper row shows while its pull is the newest step (any later step hides it; an Undo that brings the pull back shows it again)
func _taper_live() -> bool:
	if taper_tw.is_empty():
		return false
	var fs: Array = _rec().get("features", [])
	return not fs.is_empty() and String((fs[-1] as Dictionary).get("id", "")) == String(taper_tw.get("id", "")) and String((fs[-1] as Dictionary).get("t", "")) == "extrude"


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
	elif t == "loft" and f.has("twist"):   # P027: a reopened blend keeps its Twist slider
		tweak = _twist_tweak(String(f["id"]))
	elif t == "sketch" and f.has("raw"):   # p039: a reopened Curvy line keeps its Smooth slider
		tweak = _smooth_tweak(String(f["id"]))
	elif t == "fillet" and f.has("r"):   # FSAVE: a reopened part keeps its Round slider (the same one _round_done gives a new round)
		tweak = {"id": f["id"], "field": "r", "label": "How round", "unit": "cm", "lo": 0.1, "hi": 1.0, "step": 0.1, "scale": 10.0, "words": ["Barely", "Very round"]}
	elif t == "revolve" and f.has("onside"):   # P028: a reopened Spin it round keeps its Angle slider
		tweak = _spin_tweak(String(f["id"]))
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
	if not twist_row.is_empty():
		all_rows.append(twist_row)
	for r in all_rows:
		var s: HSlider = r["slider"]
		var v := 0.0
		if r["kind"] == "tpl":
			v = float(e.get("p", {}).get(r["key"], 0.0)) if bool(r.get("raw", false)) else float(e.get("p", {}).get(r["key"], 0.0)) / 10.0
		elif r["kind"] == "taper":
			v = float(Part.feature(_rec(), String(taper_tw.get("id", ""))).get("taper", 0.0))
		elif r["kind"] == "twist":
			v = float(Part.feature(_rec(), String(twist_tw.get("id", ""))).get("twist", 0.0))
		else:
			v = _tweak_value()
		if not bool(r.get("held", false)):
			s.set_value_no_signal(v)
		_pill_text(r, s.value)
		m._grey(s, Part.why_not() if off else "")
	# P024: a twisted shape has no taper (the kernel ignores it): the Taper row goes while the Twist is above 0. It fades in place rather than
	# hiding, so the Twist slider beside it keeps its width (a hidden box would widen the Twist slider mid-drag)
	if not taper_row.is_empty():
		var twisted := not twist_row.is_empty() and float(Part.feature(_rec(), String(twist_tw.get("id", ""))).get("twist", 0.0)) > 0.0
		(taper_row["box"] as Control).modulate.a = 0.0 if twisted else 1.0
		(taper_row["slider"] as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE if twisted else Control.MOUSE_FILTER_STOP
	_rep_sync()
	whole_l.visible = _tpl() != ""
	if whole_l.visible:   # the whole shape's biggest size (the replay's box, m -> cm): the sliders move one part of it
		var bb: AABB = pu.res.get("aabb", AABB())
		var big := maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
		whole_l.text = "Whole %s: %d cm" % [_nm(), roundi(big * 100.0)] if big > 0.0 else "Whole %s: not made yet" % _nm()


# ---------------------------------------------------------------- chips, Back to the first one

func _chip(t: String) -> void:
	_tpl_ghost_hide()
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
	_fav_sync()
	_say("%s %s: move a slider or drag an amber dot" % ["An" if t.substr(0, 1) in "aeiou" else "A", t])


## P091 ghost preview: hovering a shape chip shows the shape it would build, see-through, where the part sits (the record does not change)
var tpl_ghost: MeshInstance3D      # the see-through shape of the hovered chip
var _tpl_mesh := {}                # shape name -> its built mesh (one replay each; null when it does not build)


func _tpl_ghost_ensure() -> void:
	if tpl_ghost != null:
		return
	tpl_ghost = MeshInstance3D.new()
	tpl_ghost.name = "easypart_tpl_ghost"
	tpl_ghost.visible = false
	var mt := StandardMaterial3D.new()
	var c := Tok.c("pick_hover")
	mt.albedo_color = Color(c.r, c.g, c.b, 0.3)   # see-through: the part under it shows through
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.cull_mode = BaseMaterial3D.CULL_DISABLED
	tpl_ghost.material_override = mt
	pu.bu.root3.add_child(tpl_ghost)


func _tpl_ghost_hide() -> void:
	if tpl_ghost != null:
		tpl_ghost.visible = false


## a chip under the pointer (on = true) or left (on = false). The chip of the shape already built shows no ghost
func _tpl_hover(t: String, on: bool) -> void:
	if not on or not active() or not Part.available() or pu == null or t == _tpl():
		_tpl_ghost_hide()
		return
	if not _tpl_mesh.has(t):
		var res := Part.replay(PartTemplates.make(t), -1, {})
		_tpl_mesh[t] = res["mesh"] if int(res["bodies"]) > 0 else null
	var mesh = _tpl_mesh[t]
	if mesh == null:
		_tpl_ghost_hide()   # this shape does not build: a click says why
		return
	_tpl_ghost_ensure()
	tpl_ghost.mesh = mesh
	tpl_ghost.visible = true


## MORE EXAMPLES: What to build opens (its From a template card lists the weapons and props)
func _more_examples() -> void:
	if m.build_choose != null:
		m.build_choose.show_chooser()


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
	var row := HBoxContainer.new()   # FRIDAY 37 BOSS CHIP: the boss and nut buttons side by side, above the sizes (in view, not under the scroll)
	row.add_theme_constant_override("separation", 4)
	vb.add_child(row)
	var g := GridContainer.new()
	g.columns = SCREW_DS.size()
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 3)
	nw_btn = Button.new()   # NNUTWASHER: the nut (ISO 4032) and washer (ISO 7089) of the screw on the floor, in one click
	nw_btn.name = "easypart_nw_add"
	nw_btn.text = "Add its nut and washer"
	nw_btn.icon = _nw_icon()
	nw_btn.tooltip_text = "Put the nut and the washer of this screw on the floor beside it. One click, one undo step"
	nw_btn.focus_mode = Control.FOCUS_NONE
	nw_btn.custom_minimum_size = Vector2(0, 28)
	nw_btn.add_theme_font_size_override("font_size", 13)
	nw_btn.add_theme_stylebox_override("normal", _style(Color(0.165, 0.176, 0.212), 6, 4))
	nw_btn.add_theme_stylebox_override("hover", _style(Color(0.23, 0.245, 0.29), 6, 4))
	nw_btn.pressed.connect(_nw_add)
	nw_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(nw_btn)
	boss_btn = Button.new()   # FRIDAY 37 BOSS CHIP: a round post beside the screw on the floor, sized to it (outside head + 4 mm, hole + 0.5 mm, height = length), one click
	boss_btn.name = "easypart_boss_add"
	boss_btn.text = "Add its boss"
	boss_btn.icon = _boss_icon()
	boss_btn.tooltip_text = "Put a round post beside this screw, sized to it: the screw goes through its hole. One click, one undo step"
	boss_btn.focus_mode = Control.FOCUS_NONE
	boss_btn.custom_minimum_size = Vector2(0, 28)   # 28 as the nut button: the row stays one line high and the sizes stay in the panel
	boss_btn.add_theme_font_size_override("font_size", 13)
	boss_btn.add_theme_stylebox_override("normal", _style(Color(0.165, 0.176, 0.212), 6, 4))
	boss_btn.add_theme_stylebox_override("hover", _style(Color(0.23, 0.245, 0.29), 6, 4))
	boss_btn.pressed.connect(_boss_add)
	boss_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(boss_btn)
	vb.add_child(g)   # the sizes under the nut / boss row (above them it sat below the fold of a short panel)
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
			b.custom_minimum_size = Vector2(0, 28)
			b.add_theme_font_size_override("font_size", 13)
			b.add_theme_stylebox_override("normal", _style(Color(0.165, 0.176, 0.212), 6, 4))
			b.add_theme_stylebox_override("hover", _style(Color(0.23, 0.245, 0.29), 6, 4))
			b.pressed.connect(_screw_pick.bind(d, L))
			g.add_child(b)
			screw_btns["%d_%d" % [d, L]] = b
	return pc


## P075: the three Clips and feet chips: a row of icon + plain word each, one row under the category chips
func _clip_box() -> PanelContainer:
	var pc := PanelContainer.new()
	pc.name = "easypart_clip_box"
	pc.add_theme_stylebox_override("panel", _style(Color(0.12, 0.125, 0.15), 10, 6))
	pc.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	pc.add_child(vb)
	var hd := Label.new()
	hd.name = "easypart_clip_words"
	hd.text = "Clips and feet: pick one. It drops on the floor, then change its size with the sliders"
	hd.add_theme_font_size_override("font_size", 14)
	hd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hd)
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 4)
	fl.add_theme_constant_override("v_separation", 4)
	vb.add_child(fl)
	for kind in CLIP_KINDS:
		var b := Button.new()
		b.name = "easypart_clip_" + kind
		b.text = String(PartTemplates.T[kind]["title"])
		b.icon = _clip_icon(kind)
		b.tooltip_text = "%s: %s" % [b.text, _clip_words(kind)]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 34)
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_stylebox_override("normal", _style(Color(0.165, 0.176, 0.212), 6, 4))
		b.add_theme_stylebox_override("hover", _style(Color(0.23, 0.245, 0.29), 6, 4))
		b.pressed.connect(_clip_pick.bind(kind))
		fl.add_child(b)
		clip_btns[kind] = b
	return pc


## P075: the sizes a part starts with, in words: "Width 16 mm, Height 4 mm"
func _clip_words(kind: String) -> String:
	var p: Dictionary = PartTemplates.defaults(kind)
	var out := []
	for d in PartTemplates.T[kind]["params"]:
		out.append("%s %d mm" % [String(d["label"]), roundi(float(p[d["k"]]))])
	return ", ".join(out)


## P075: a 16 px icon per clip kind, drawn in the text colour (Tok): a flat disc, a ring with its opening, a plate with a slot
func _clip_icon(kind: String) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col := Tok.c("text")
	match kind:
		"foot":
			img.fill_rect(Rect2i(1, 9, 14, 5), col)
			img.fill_rect(Rect2i(4, 6, 8, 3), col)
		"clip":
			_lib_ring(img, 7.0, 4.5, col)
			img.fill_rect(Rect2i(8, 7, 8, 2), Color(0, 0, 0, 0))
		"slot":
			img.fill_rect(Rect2i(1, 4, 14, 8), col)
			img.fill_rect(Rect2i(4, 7, 8, 2), Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


## P075: a clip chip: a new part of that kind on the floor (one undo step). A part already there is replaced, the same as a screw size.
func _clip_pick(kind: String) -> void:
	if not Part.available():
		_chips_sync()
		return
	var title := String(PartTemplates.T[kind]["title"])
	armed = ""
	hole_base = {}
	split_id = ""
	_flush_if_dirty()
	m._step_hint = "Start a " + title.to_lower()
	m._push_undo()
	m.S.part = PartTemplates.make(kind)
	tweak = {}
	pu.upto = -1
	pu.sync()
	frame()
	if not (pu.res.get("errors", {}) as Dictionary).is_empty():
		_say("%s did not build. Press Reset, then pick it again" % title)
	else:
		_say("%s on the floor: %s. Change its size with the sliders" % [title, _clip_words(kind)])
	_screw_sync()   # the clip chips' open state and pressed chip are in _screw_sync


## P072: the Wheels page: two chips, Wheel and Castor. Each is a tyre with an axle hole through its middle; the words give its size
func _wheel_box() -> PanelContainer:
	var pc := PanelContainer.new()
	pc.name = "easypart_wheel_box"
	pc.add_theme_stylebox_override("panel", _style(Color(0.12, 0.125, 0.15), 10, 6))
	pc.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	pc.add_child(vb)
	var hd := Label.new()
	hd.name = "easypart_wheel_words"
	hd.text = "Wheels: pick one. The hole in the middle takes the axle"
	hd.add_theme_font_size_override("font_size", 14)
	hd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hd)
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 4)
	fl.add_theme_constant_override("v_separation", 4)
	vb.add_child(fl)
	for k in ["wheel", "castor"]:
		var d: Dictionary = PartTemplates.defaults("axwheel" if k == "wheel" else "castor")
		var b := Button.new()
		b.name = "easypart_wheel_" + k
		b.text = "Wheel" if k == "wheel" else "Castor"
		b.icon = _lib_icon("Wheels")
		b.tooltip_text = "%s: %d mm across, %d mm wide, an axle hole %d mm through the middle" % [b.text, int(d["radius"]) * 2, int(d["width"]), int(d["hole"])]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 34)
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_stylebox_override("normal", _style(Color(0.165, 0.176, 0.212), 6, 4))
		b.add_theme_stylebox_override("hover", _style(Color(0.23, 0.245, 0.29), 6, 4))
		b.pressed.connect(_wheel_pick.bind(k))
		fl.add_child(b)
		wheel_btns[k] = b
	return pc


## P072: a Wheel or a Castor on the floor (one undo step). It replaces the part on the floor, like a screw does when none is there
func _wheel_pick(k: String) -> void:
	if not Part.available():
		_chips_sync()
		return
	var t := "axwheel" if k == "wheel" else "castor"
	var label := "Wheel" if k == "wheel" else "Castor"
	armed = ""
	hole_base = {}
	split_id = ""
	_flush_if_dirty()
	m._step_hint = "Start a %s" % label.to_lower()
	m._push_undo()
	m.S.part = PartTemplates.make(t)
	tweak = {}
	pu.upto = -1
	pu.sync()
	frame()
	if not (pu.res.get("errors", {}) as Dictionary).is_empty():
		_say("%s did not build. Press Reset, then pick it again" % label)
	else:
		_say("%s on the floor, its axle hole %d mm through the middle. Press Wheel or Castor to change it" % [label, int(PartTemplates.defaults(t)["hole"])])
	_screw_sync()


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


## FRIDAY 37 BOSS CHIP: a small ring icon (a post seen from above: a ring, Tok colour only), same 16 px box as the others
func _boss_icon() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col := Tok.c("text")
	for y in 16:
		for x in 16:
			var r := Vector2(x + 0.5 - 8.0, y + 0.5 - 8.0).length()
			if r <= 7.0 and r >= 4.0:
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


## FRIDAY 37 BOSS CHIP: the boss button. No screw on the floor: it says what to do first. Its post already there: it says so (no undo step).
## Else one undo step puts the post on the floor beside the screw, sized to it.
func _boss_add() -> void:
	if not Part.available():
		_chips_sync()
		return
	var on_floor := _tpl() == "screw" and not (_rec().get("features", []) as Array).is_empty()
	if not on_floor:
		_say("Put a screw on the floor first: pick a size above, then press Add its boss")
		_screw_sync()
		return
	var e: Dictionary = _rec().get("easy", {})
	if int(e.get("bo", -1)) >= 0:
		_say("Its boss is on the floor already. Pick another size to change it")
		_screw_sync()
		return
	armed = ""
	hole_base = {}
	split_id = ""
	_flush_if_dirty()
	m._step_hint = "Add the boss"
	m._push_undo()
	var cur: Dictionary = e["p"]
	PartTemplates.bo_add(_rec(), int(cur["d"]), int(cur["L"]))
	tweak = {}
	pu.upto = -1
	pu.sync()
	frame()
	if not (pu.res.get("errors", {}) as Dictionary).is_empty():
		_say("The boss did not build. Press Reset, then pick a size again")
	else:
		_say("Boss on the floor beside the screw. Pick another size to change it")
	_screw_sync()


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


## FRIDAY 73: the bracket chips: an L, a T and a corner brace, each a click. The shape drops on the floor; a bracket on the floor changes shape
## (one undo step, the same steps), the same shape again does nothing. Words and icons only: no key name.
func _bracket_box() -> PanelContainer:
	var pc := PanelContainer.new()
	pc.name = "easypart_bracket_box"
	pc.add_theme_stylebox_override("panel", _style(Color(0.12, 0.125, 0.15), 10, 6))
	pc.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	pc.add_child(vb)
	var hd := Label.new()
	hd.name = "easypart_bracket_words"
	hd.text = "Brackets: pick a shape. It drops on the floor"
	hd.add_theme_font_size_override("font_size", 14)
	hd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hd)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	vb.add_child(row)
	for bc in BRACKET_CHIPS:
		var b := Button.new()
		b.name = "easypart_bracket_" + String(bc[0])
		b.text = String(bc[1])
		b.icon = _bracket_icon(int(bc[2]))
		b.tooltip_text = String(bc[3])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 34)
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_stylebox_override("normal", _style(Color(0.165, 0.176, 0.212), 6, 4))
		b.add_theme_stylebox_override("hover", _style(Color(0.23, 0.245, 0.29), 6, 4))
		b.pressed.connect(_bracket_pick.bind(int(bc[2])))
		row.add_child(b)
		bracket_btns[bc[0]] = b
	return pc


## FRIDAY 73: a 16 px icon per shape, in the text colour (Tok): an L, a T, an L with a corner gusset
func _bracket_icon(kind: int) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col := Tok.c("text")
	match kind:
		1:
			img.fill_rect(Rect2i(2, 1, 3, 14), col)
			img.fill_rect(Rect2i(2, 12, 13, 3), col)
		2:
			img.fill_rect(Rect2i(1, 1, 14, 3), col)
			img.fill_rect(Rect2i(7, 4, 3, 11), col)
		3:
			img.fill_rect(Rect2i(2, 1, 3, 14), col)
			img.fill_rect(Rect2i(2, 12, 13, 3), col)
			for i in 6:
				img.fill_rect(Rect2i(5 + i, 11 - i, 2, 2), col)
	return ImageTexture.create_from_image(img)


## FRIDAY 73: a bracket shape chip (kind 1 / 2 / 3). No bracket on the floor: a new one. A bracket on the floor: its shape changes
## (one undo step). The same shape again does nothing.
func _bracket_pick(kind: int) -> void:
	if not Part.available():
		_chips_sync()
		return
	var label := ""
	for bc in BRACKET_CHIPS:
		if int(bc[2]) == kind:
			label = String(bc[1])
	var on_floor := _tpl() == "bracket" and not (_rec().get("features", []) as Array).is_empty()
	if on_floor:
		var cur: Dictionary = (_rec().get("easy", {}) as Dictionary).get("p", {})
		if int(cur.get("kind", 0)) == kind:
			_say("Already a %s on the floor. Pick another shape to change it" % label)
			_screw_sync()
			return
	armed = ""
	hole_base = {}
	split_id = ""
	_flush_if_dirty()
	m._step_hint = "Change the shape" if on_floor else "Start a bracket"
	m._push_undo()
	if on_floor:
		PartTemplates.retemplate(_rec(), {"kind": kind})
	else:
		m.S.part = PartTemplates.make("bracket", {"kind": kind})
	tweak = {}
	pu.upto = -1
	pu.sync()
	frame()
	if not (pu.res.get("errors", {}) as Dictionary).is_empty():
		_say("%s did not build. Press Reset, then pick a shape again" % label)
	else:
		_say("%s on the floor. Pick another shape to change it" % label)
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
	elif cat == "Bearings":   # P069 BEARINGS: three sizes; the seat button under them cuts the seat for the one on the floor
		_say("Bearings: pick a size. It drops on the floor. Then Make a seat for it")
	elif cat == "Brackets":   # FRIDAY 73: three shapes, each a click
		_say("Brackets: pick a shape. It drops on the floor")
	elif cat == "Clips and feet":
		_say("Clips and feet: pick one. It drops on the floor")
	elif cat == "Handles":
		_say("Handles: pick a kind and a size. It drops on the floor")
	elif cat == "Wheels":
		_say("Wheels: press Wheel or Castor. It drops on the floor, with its axle hole")
	elif cat == "Boards":   # p078makeacasef
		_say("Boards: press your board. A case for it drops on the floor")
	elif cat == "Hinges":
		_say("Hinges: press Hinge below. It drops on the floor, sized to the door")
	elif cat == "Springs":   # p070springfix: the page shows the Spring button (opening a category builds nothing)
		_say("Springs: press Spring below. It drops on the floor")
	elif cat == "Favourites":   # p083favfix: a chip puts that part back on the floor; the star keeps a favourite
		_say("Favourites: press a chip to put that part on the floor again. Press the star to keep one")
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
	var fl := HFlowContainer.new()   # compact: eleven chips in three rows, so the screw grid under the page stays inside the panel at 1280 x 720
	fl.add_theme_constant_override("h_separation", 3)
	fl.add_theme_constant_override("v_separation", 3)
	vb.add_child(fl)
	for cat in LIB_CATS:
		var b := Button.new()
		b.name = "easypart_lib_" + cat
		b.text = cat
		b.icon = _lib_icon(cat)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 34)
		b.add_theme_font_size_override("font_size", 12)
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
	hinges_btn = Button.new()   # p067hinges: a Hinges page button (shown only on Hinges): one click, a Butt hinge at the door's height
	hinges_btn.name = "easypart_hinge_pick"
	hinges_btn.text = "Hinge"
	hinges_btn.toggle_mode = true
	hinges_btn.focus_mode = Control.FOCUS_NONE
	hinges_btn.custom_minimum_size = Vector2(0, 34)
	hinges_btn.add_theme_font_size_override("font_size", 13)
	hinges_btn.visible = false
	hinges_btn.pressed.connect(_hinges_btn_press)
	vb.add_child(hinges_btn)
	spring_pick = Button.new()   # p070springfix: the Springs page button (shown only on Springs): one click, a spring on the floor
	spring_pick.name = "easypart_spring_pick"
	spring_pick.text = "Spring"
	spring_pick.toggle_mode = true
	spring_pick.focus_mode = Control.FOCUS_NONE
	spring_pick.custom_minimum_size = Vector2(0, 34)
	spring_pick.add_theme_font_size_override("font_size", 13)
	spring_pick.visible = false
	spring_pick.pressed.connect(_spring_pick_press)
	vb.add_child(spring_pick)
	vb.add_child(lib_soon)
	return pc


## NLIBPAGE: a 16 px icon per category, drawn in the text colour (Tok): a screw, a gear ring, a nut, a washer, hinge leaves, bearing rings,
## a spring, a handle, a wheel with spokes, a bracket
func _lib_icon(cat: String) -> ImageTexture:
	if cat == "Screws":
		return _screw_icon(4, 16)
	if cat == "Clips and feet":
		return _clip_icon("clip")
	if cat == "Boards":   # p078makeacasef
		return _board_icon(1)
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


## p078makeacasef: the Boards page's chips: a box with standoffs, port holes and a lid for the board. A case on the floor: its board changes
## (one undo step, the same features). The same board again does nothing.
func _board_pick(bd: int) -> void:
	if not Part.available():
		_chips_sync()
		return
	var label := String(PartTemplates.CASE_BOARDS[bd]["name"])
	var on_floor := _tpl() == "case" and not (_rec().get("features", []) as Array).is_empty()
	if on_floor:
		var cur: Dictionary = (_rec().get("easy", {}) as Dictionary).get("p", {})
		if int(cur.get("board", 0)) == bd:
			_say("Already a case for the %s. Pick the other board to change it" % label)
			_screw_sync()
			return
	armed = ""
	hole_base = {}
	split_id = ""
	_flush_if_dirty()
	m._step_hint = "Change the board" if on_floor else "Start a board case"
	m._push_undo()
	if on_floor:
		PartTemplates.retemplate(_rec(), {"board": bd})
	else:
		m.S.part = PartTemplates.make("case", {"board": bd})
	tweak = {}
	pu.upto = -1
	pu.sync()
	frame()
	if not (pu.res.get("errors", {}) as Dictionary).is_empty():
		_say("The %s case did not build. Press Reset, then pick a board again" % label)
	else:
		_say("A case for the %s: standoffs, port holes and a lid. Pick the other board to change it" % label)
	_screw_sync()


## p078makeacasef: the Boards page: a line of words and the two board chips (a 5 mm standoff case each, with its lid)
func _board_box() -> PanelContainer:
	var pc := PanelContainer.new()
	pc.name = "easypart_board_box"
	pc.add_theme_stylebox_override("panel", _style(Color(0.12, 0.125, 0.15), 10, 6))
	pc.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	pc.add_child(vb)
	var hd := Label.new()
	hd.name = "easypart_board_words"
	hd.text = "Boards: pick yours. You get a box for it with standoffs, port holes and a lid"
	hd.add_theme_font_size_override("font_size", 14)
	hd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hd)
	var g := HFlowContainer.new()
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	vb.add_child(g)
	for bd in [1, 2]:
		var b := Button.new()
		b.name = "easypart_board_" + ("pi" if bd == 1 else "uno")
		b.text = String(PartTemplates.CASE_BOARDS[bd]["name"])
		b.icon = _board_icon(bd)
		b.tooltip_text = "%s: a box with four standoffs, port holes on one side and a lid. One click, one undo step" % b.text
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 34)
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_stylebox_override("normal", _style(Color(0.165, 0.176, 0.212), 6, 4))
		b.add_theme_stylebox_override("hover", _style(Color(0.23, 0.245, 0.29), 6, 4))
		b.pressed.connect(_board_pick.bind(bd))
		g.add_child(b)
		board_btns[bd] = b
	return pc


## p078makeacasef: a 16 px board icon in the text colour (Tok): a square outline with four mounting holes
func _board_icon(_bd: int) -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col := Tok.c("text")
	img.fill_rect(Rect2i(1, 1, 14, 2), col)
	img.fill_rect(Rect2i(1, 13, 14, 2), col)
	img.fill_rect(Rect2i(1, 1, 2, 14), col)
	img.fill_rect(Rect2i(13, 1, 2, 14), col)
	for hp in [Vector2i(5, 5), Vector2i(10, 5), Vector2i(5, 10), Vector2i(10, 10)]:
		img.fill_rect(Rect2i(hp, Vector2i(2, 2)), col)
	return ImageTexture.create_from_image(img)


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
		PartTemplates.bo_set(_rec(), d, L)   # FRIDAY 37 BOSS CHIP: the post (if on the floor) follows the size too
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


## P071 HANDLES: a size chip. No handle of that kind on the floor: a new one (one undo step). A handle of that kind already there: its size
## changes (one undo step). The same size again does nothing. The words give the built size in mm, from the built part.
func _handle_pick(kind: String, size: int) -> void:
	if not Part.available():
		_chips_sync()
		return
	var key: String = PartTemplates.HANDLE_KEY[kind]
	var name_l := String(PartTemplates.HANDLE_NAME[kind]).to_lower()
	var on_floor := _tpl() == kind
	if on_floor:
		var cur: Dictionary = (_rec().get("easy", {}) as Dictionary).get("p", {})
		if int(roundf(float(cur.get(key, 0)))) == size:
			_say("Already the %s on the floor. Pick another size to change it" % name_l)
			_screw_sync()
			return
	armed = ""
	hole_base = {}
	split_id = ""
	_flush_if_dirty()
	m._step_hint = "Change the handle size" if on_floor else "Start a handle"
	m._push_undo()
	if on_floor:
		PartTemplates.retemplate(_rec(), {key: size})
	else:
		m.S.part = PartTemplates.make(kind, {key: size})
	tweak = {}
	pu.upto = -1
	pu.sync()
	frame()
	if not (pu.res.get("errors", {}) as Dictionary).is_empty():
		_say("The %s did not build. Press Reset, then pick a size again" % name_l)
	else:
		var bb: AABB = pu.res.get("aabb", AABB())
		var big := roundi(maxf(bb.size.x, maxf(bb.size.y, bb.size.z)) * 1000.0)
		var hole := ". Its two holes take an M4 screw from Parts" if kind == "drawer_pull" else ""
		_say("A %s on the floor, %d mm across%s. Move a slider, or pick another size" % [name_l, big, hole])
	_screw_sync()


## P071 HANDLES: the Handles grid: a row per kind (its name, then its three sizes in mm). One click puts that handle on the floor.
func _handle_box() -> PanelContainer:
	var pc := PanelContainer.new()
	pc.name = "easypart_handle_box"
	pc.add_theme_stylebox_override("panel", _style(Color(0.12, 0.125, 0.15), 10, 6))
	pc.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	pc.add_child(vb)
	var hd := Label.new()
	hd.name = "easypart_handle_words"
	hd.text = "Handles: pick a kind and a size. It drops on the floor"
	hd.add_theme_font_size_override("font_size", 14)
	hd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	handle_words = hd
	vb.add_child(hd)
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	vb.add_child(g)
	for kind in PartTemplates.HANDLE_SIZES:
		var nm := Label.new()
		nm.text = String(PartTemplates.HANDLE_NAME[kind])
		nm.add_theme_font_size_override("font_size", 13)
		nm.custom_minimum_size = Vector2(96, 34)
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		g.add_child(nm)
		for size in PartTemplates.HANDLE_SIZES[kind]:
			var b := Button.new()
			b.name = "easypart_handle_%s_%d" % [kind, size]
			b.text = "%d mm" % size
			b.toggle_mode = true
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(0, 34)
			b.add_theme_font_size_override("font_size", 13)
			b.add_theme_stylebox_override("normal", _style(Color(0.165, 0.176, 0.212), 6, 4))
			b.add_theme_stylebox_override("hover", _style(Color(0.23, 0.245, 0.29), 6, 4))
			b.tooltip_text = "%s, %d mm: one click puts it on the floor" % [nm.text, size]
			b.pressed.connect(_handle_pick.bind(kind, size))
			g.add_child(b)
			handle_btns["%s_%d" % [kind, size]] = b
	return pc


## NSCREW2: the grid's open state and the pressed size (the screw on the floor); the Parts chip is pressed while the grid shows
func _screw_sync() -> void:
	if lib_box != null:   # NLIBPAGE: the page shows while Parts is open; the open category is pressed; the coming-soon line names it
		lib_box.visible = parts_open
		for cat in lib_btns:
			var lb: Button = lib_btns[cat]
			lb.set_pressed_no_signal(parts_open and cat == lib_cat)
			m._grey(lb, Part.why_not() if not Part.available() else "")
		hinges_btn.visible = parts_open and lib_cat == "Hinges"   # p067hinges
		hinges_btn.set_pressed_no_signal(_tpl() == "hinge")
		m._grey(hinges_btn, Part.why_not() if not Part.available() else "")
		spring_pick.visible = parts_open and lib_cat == "Springs"   # p070springfix
		spring_pick.set_pressed_no_signal(_tpl() == "spring")
		m._grey(spring_pick, Part.why_not() if not Part.available() else "")
		lib_soon.visible = parts_open and lib_cat != "" and not (lib_cat in LIB_READY)
		if screw_words != null:   # the page is open: its chips and the status line say what to do
			screw_words.visible = not parts_open
		lib_soon.text = "%s are coming soon: not made yet. Next step: press Screws or Gears" % lib_cat if lib_soon.visible else ""
		if fav_box != null:   # p083favfix: the Favourites page shows while its category is open; the row and the star are drawn here
			fav_box.visible = parts_open and lib_cat == "Favourites"
			_fav_sync()
	if clip_box != null:   # P075: the Clips and feet chips show while that category is open
		clip_box.visible = parts_open and lib_cat == "Clips and feet"
		for kind in CLIP_KINDS:
			var cb: Button = clip_btns[kind]
			cb.set_pressed_no_signal(_tpl() == kind)
			m._grey(cb, Part.why_not() if not Part.available() else "")
		if handle_box != null:   # P071 HANDLES: the grid shows while the Handles category is open, or a handle is the part
			handle_box.visible = parts_open and lib_cat == "Handles" or PartTemplates.HANDLE_NAME.has(_tpl())
			handle_words.visible = not parts_open
			var cur_h: Dictionary = (_rec().get("easy", {}) as Dictionary).get("p", {}) if PartTemplates.HANDLE_NAME.has(_tpl()) else {}
			for kind in PartTemplates.HANDLE_SIZES:
				for size in PartTemplates.HANDLE_SIZES[kind]:
					var hb: Button = handle_btns["%s_%d" % [kind, size]]
					hb.set_pressed_no_signal(not cur_h.is_empty() and kind == _tpl() and int(roundf(float(cur_h.get(PartTemplates.HANDLE_KEY[kind], 0)))) == size)
					m._grey(hb, Part.why_not() if not Part.available() else "")
		if wheel_box != null:   # P072: the Wheels chips show while the Wheels category is open
			wheel_box.visible = parts_open and lib_cat == "Wheels"
			for k in wheel_btns:
				m._grey(wheel_btns[k], Part.why_not() if not Part.available() else "")
	if screw_box == null or parts_btn == null:
		return
	var cur: Dictionary = {}
	if _tpl() == "screw":
		cur = (_rec().get("easy", {}) as Dictionary).get("p", {})
	screw_box.visible = (parts_open and lib_cat == "Screws") or _tpl() == "screw"
	if bear_box != null:   # P069 BEARINGS: the three chips show the bearing on the floor (pressed); the seat button sits under them
		var bk := int((_rec().get("easy", {}) as Dictionary).get("p", {}).get("kind", -1)) if _tpl() in ["bearing", "seat"] else -1
		bear_box.visible = (parts_open and lib_cat == "Bearings") or _tpl() in ["bearing", "seat"]
		for i in BEAR_CODES.size():
			var bb: Button = bear_btns[BEAR_CODES[i]]
			bb.set_pressed_no_signal(i == bk)
			m._grey(bb, Part.why_not() if not Part.available() else "")
		m._grey(seat_btn, Part.why_not() if not Part.available() else "")
	parts_btn.set_pressed_no_signal(parts_open)
	for d in SCREW_DS:
		for L in SCREW_LENS:
			var b: Button = screw_btns["%d_%d" % [d, L]]
			b.set_pressed_no_signal(not cur.is_empty() and int(cur.get("d", 0)) == d and int(cur.get("L", 0)) == L)
			m._grey(b, Part.why_not() if not Part.available() else "")
	parts_btn.set_pressed_no_signal(parts_open)
	# FRIDAY 73: the bracket chips show while Brackets is open or a bracket is the part; the pressed one is the shape on the floor
	var kind := int(cur.get("kind", 0)) if _tpl() == "bracket" else 0
	bracket_box.visible = (parts_open and lib_cat == "Brackets") or _tpl() == "bracket"
	for bc in BRACKET_CHIPS:
		var bb: Button = bracket_btns[bc[0]]
		bb.set_pressed_no_signal(kind == int(bc[2]))
		m._grey(bb, Part.why_not() if not Part.available() else "")
	# p078makeacasef: the Boards chips: the case on the floor shows its board pressed
	var bcur: Dictionary = (_rec().get("easy", {}) as Dictionary).get("p", {}) if _tpl() == "case" else {}
	board_box.visible = (parts_open and lib_cat == "Boards") or _tpl() == "case"
	for bd in board_btns:
		var bo: Button = board_btns[bd]
		bo.set_pressed_no_signal(not bcur.is_empty() and int(bcur.get("board", 0)) == bd)
		m._grey(bo, Part.why_not() if not Part.available() else "")


## P069 BEARINGS: the three bearing sizes, in the order of PartTemplates.BEARING_SIZE (608, 625, 688)
const BEAR_CODES := ["608", "625", "688"]


## P069 BEARINGS: the Bearings page under the Parts chips: a line, three size chips (bore, outside, width in the tip), the seat button
func _bear_box() -> PanelContainer:
	var pc := PanelContainer.new()
	pc.name = "easypart_bear_box"
	pc.add_theme_stylebox_override("panel", _style(Color(0.12, 0.125, 0.15), 10, 6))
	pc.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	pc.add_child(vb)
	var hd := Label.new()
	hd.name = "easypart_bear_words"
	hd.text = "Bearings, ball: pick a size. It drops on the floor"
	hd.add_theme_font_size_override("font_size", 14)
	hd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hd)
	var g := GridContainer.new()
	g.columns = BEAR_CODES.size()
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	vb.add_child(g)
	for i in BEAR_CODES.size():
		var code: String = BEAR_CODES[i]
		var sz: Array = PartTemplates.BEARING_SIZE[i]
		var b := Button.new()
		b.name = "easypart_bear_" + code
		b.text = code
		b.icon = _lib_icon("Bearings")
		b.tooltip_text = "%s: bore %s mm, outside %s mm, %s mm wide" % [code, str(sz[0]), str(sz[1]), str(sz[2])]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 34)
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_stylebox_override("normal", _style(Color(0.165, 0.176, 0.212), 6, 4))
		b.add_theme_stylebox_override("hover", _style(Color(0.23, 0.245, 0.29), 6, 4))
		b.pressed.connect(_bear_pick.bind(i))
		g.add_child(b)
		bear_btns[code] = b
	seat_btn = Button.new()
	seat_btn.name = "easypart_bear_seat"
	seat_btn.text = "Make a seat for it"
	seat_btn.icon = _lib_icon("Bearings")
	seat_btn.tooltip_text = "Cut a seat for the bearing on the floor: a holder block with a pocket the bearing fits (0.2 mm loose), the bearing beside it. One undo step"
	seat_btn.focus_mode = Control.FOCUS_NONE
	seat_btn.custom_minimum_size = Vector2(0, 34)
	seat_btn.add_theme_font_size_override("font_size", 13)
	seat_btn.add_theme_stylebox_override("normal", _style(Color(0.165, 0.176, 0.212), 6, 4))
	seat_btn.add_theme_stylebox_override("hover", _style(Color(0.23, 0.245, 0.29), 6, 4))
	seat_btn.pressed.connect(_seat_press)
	vb.add_child(seat_btn)
	return pc


## P069 BEARINGS: a size chip drops that bearing on the floor (it replaces what is there, as a screw does). One undo step.
func _bear_pick(i: int) -> void:
	if not Part.available():
		_chips_sync()
		return
	var code: String = BEAR_CODES[i]
	if _tpl() == "bearing" and int((_rec().get("easy", {}) as Dictionary).get("p", {}).get("kind", -1)) == i:
		_say("Already a %s bearing on the floor. Pick another size to change it" % code)
		_screw_sync()
		return
	armed = ""
	hole_base = {}
	split_id = ""
	_flush_if_dirty()
	m._step_hint = "Start a bearing"
	m._push_undo()
	m.S.part = PartTemplates.make("bearing", {"kind": i})
	tweak = {}
	pu.upto = -1
	pu.sync()
	frame()
	if not (pu.res.get("errors", {}) as Dictionary).is_empty():
		_say("The %s bearing did not build. Press Reset, then pick a size again" % code)
	else:
		_say("%s bearing on the floor. Make a seat for it cuts its seat" % code)
	_screw_sync()


## P069 BEARINGS: Make a seat for it: the bearing on the floor gets a holder with its seat (one undo step). Refused in words with no bearing.
func _seat_press() -> void:
	if not Part.available():
		_say(Part.why_not())
		return
	if _tpl() == "seat":
		_say("The seat is on the floor already. Pick another bearing to change it")
		return
	if _tpl() != "bearing":
		_say("Make a seat needs a bearing on the floor first. Press Bearings, then 608, 625 or 688")
		return
	var k := int((_rec().get("easy", {}) as Dictionary).get("p", {}).get("kind", 0))
	armed = ""
	hole_base = {}
	split_id = ""
	_flush_if_dirty()
	m._step_hint = "Make a seat"
	m._push_undo()
	m.S.part = PartTemplates.make("seat", {"kind": k})
	tweak = {}
	pu.upto = -1
	pu.sync()
	frame()
	if not (pu.res.get("errors", {}) as Dictionary).is_empty():
		_say("The %s seat did not build. Press Reset, then pick the bearing again" % BEAR_CODES[k])
	else:
		_say("Seat made for the %s bearing: the bearing stands beside it. Undo takes the seat back" % BEAR_CODES[k])
	_screw_sync()


# P107 FITVIEW: the view row at the top of the panel. The camera only: no step, so no undo
const VIEW_BTNS := [
	["fit", "Fit view", "view_fit", "Fit the whole part in the clear view"],
	["front", "Front", "view_front", "Look at the part from the front"],
	["top", "Top", "view_top", "Look down at the part from above"],
	["side", "Side", "view_side", "Look at the part from the right side"],
	["3q", "3/4", "view_3q", "Look at the part from a corner, so its depth shows"],
]
const VIEW_ANGLES := {"front": [0.0, -8.0], "top": [0.0, -89.0], "side": [-90.0, -8.0]}   # yaw, pitch (degrees): the same numbers as Expert's views


func _view_press(k: String) -> void:
	if k == "fit":
		frame()
		_say("Fit view: the whole part is in the clear view")
		return
	var ang: Array = VIEW_ANGLES.get(k, PartTemplates.view_of(String(m.S.part.get("easy", {}).get("t", ""))))   # 3/4: a template's own corner view
	var rs: Dictionary = pu.res   # the built part (part_ui's own result)
	var bb: AABB = rs.get("aabb", AABB()) if not rs.is_empty() else AABB()
	var empty := bb.size.length() < 1e-4
	var c := Vector3(0.1, 0.0, 0.0) if empty else bb.get_center()
	m._turn_to(float(ang[0]), float(ang[1]), 0.9 if empty else clampf(bb.size.length() * 1.5, 0.4, 6.0), c, true)
	_say("Turned the view. Fit view brings the whole part back in")


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
	hinge_pick = {}   # P068: any make press drops a door picked for a hinge
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


## MAKE IT STRONGER (p038makeitstro, Friday plan 38): the solid's thinnest side is its thin side. Under RIB_MIN_MM a rib goes on that side's
## face, along the longer of the other two sides and centred across it: a strip RIB_W_MM wide, RIB_H_MM tall (the Rib height slider).
const RIB_MIN_MM := 25.0
const RIB_W_MM := 4.0
const RIB_H_MM := 10.0


func _stronger_press() -> void:
	if not Part.available():
		_say(Part.why_not())
		return
	_flush_if_dirty()
	armed = ""
	var snap := _rec().duplicate(true)
	_begin("Make it stronger")
	var rec: Dictionary = snap.duplicate(true)
	var why := _stronger(rec)
	if why != "":
		m.S.part = snap
		m._drop_undo()
		_edit_n = -1
		_say(why)
	else:
		m.S.part = rec
		_end()
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_values_sync()


## the rib, added to rec (see above). "" or why not
func _stronger(rec: Dictionary) -> String:
	var res := Part.replay(rec)
	if int(res["bodies"]) != 1:
		return "Make one solid first: Pull it up, then press Make it stronger"
	var bb: AABB = res["aabb"]
	var lo := bb.position / Part.MM
	var hi := bb.end / Part.MM
	var sz := hi - lo
	var thin := 0
	for a in 3:
		if sz[a] < sz[thin]:
			thin = a
	if sz[thin] >= RIB_MIN_MM:
		return "This solid is thick enough already (%d mm at its thinnest): nothing to add" % int(roundf(sz[thin]))
	var others := [0, 1, 2]
	others.erase(thin)
	var along: int = others[0] if sz[others[0]] >= sz[others[1]] else others[1]
	var across: int = others[1] if along == others[0] else others[0]
	var base: String = ["right", "top", "front"][thin]
	var pf := Part.new_feature(rec, "plane", {"from": base, "mm": snappedf(hi[thin], 0.01)})
	rec["features"].append(pf)
	var pl := Part.resolve_plane(rec, String(pf["id"]))
	var mid := (lo[across] + hi[across]) * 0.5
	var w1 := Vector3.ZERO
	var w2 := Vector3.ZERO
	w1[thin] = hi[thin]
	w2[thin] = hi[thin]
	w1[along] = lo[along]
	w2[along] = hi[along]
	w1[across] = mid - RIB_W_MM * 0.5
	w2[across] = mid + RIB_W_MM * 0.5
	var sk := Part.new_feature(rec, "sketch", {"plane": String(pf["id"]), "ents": [{"k": "rect", "a": Part.arr2(Part.to_plane(pl, w1 * Part.MM)), "b": Part.arr2(Part.to_plane(pl, w2 * Part.MM))}], "dims": []})
	rec["features"].append(sk)
	var ex := Part.new_feature(rec, "extrude", {"sketch": sk["id"], "dist": RIB_H_MM, "both": false, "op": "join", "into": 0})
	rec["features"].append(ex)
	if _last_error(rec, String(ex["id"])) != "" or int(Part.replay(rec)["bodies"]) != 1:
		return "A rib does not fit on this solid. Pull it up taller, then press Make it stronger again"
	tweak = {"id": ex["id"], "field": "dist", "label": "Rib height", "unit": "mm", "lo": 2.0, "hi": 30.0, "step": 1.0, "scale": 1.0, "words": ["Shorter", "Taller"]}
	_say("Ribbed the thin side: use the Rib height slider for how tall, or press Round the edges or Cut a hole next")
	return ""


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
	var f := Part.new_feature(rec, "loft", {"sketches": [a["id"], b["id"]], "ruled": true, "op": "join", "twist": 0.0})
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
	tweak = _twist_tweak(String(f["id"]))   # P027: the Twist slider opens with the blend (0 = a straight loft)
	_say("Blended the two last shapes into one solid: move Twist to turn the top shape, or press Colour or Round the edges next")
	return ""


## P027: the Twist slider of a blend: the top shape turns, -90 to +90 degrees (0 = a straight loft)
func _twist_tweak(id: String) -> Dictionary:
	return {"id": id, "field": "twist", "label": "Twist", "unit": "deg", "lo": -90.0, "hi": 90.0, "step": 1.0, "scale": 1.0, "words": ["Twist left", "Twist right"]}


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
	var raw := []   # p039: the whole hand stroke, kept, so the Smooth slider can redo the curve from it
	for p in pts:
		raw.append(Part.arr2(p))
	rec["features"].append(Part.new_feature(rec, "sketch", {"plane": _face_plane(rec, fc), "ents": [{"k": "bspline", "pts": out, "closed": closed}], "dims": [], "raw": raw, "smooth": 0.0}))
	_end()
	armed = ""
	tweak = _smooth_tweak(String(rec["features"][-1]["id"]))   # p039: the Smooth slider opens with the line (0 = as drawn)
	pu.upto = -1
	pu.sync()
	_rows_sync()
	# a curve that touches or crosses the middle line (x = 0) is a profile to spin: the words point to Spin it round
	var spin_ok := false
	for q in pts:
		if (q as Vector2).x <= 1.0:
			spin_ok = true
	if spin_ok:
		_say("Curvy line drawn: Spin it round makes a bowl, or Pull it up makes it solid" if closed else "Curvy line drawn: for a pipe, Pull along (Expert: CREATE, Sweep does the same). Or drag back to the start to close it")
	else:
		_say("Curvy line drawn: Pull it up makes it solid" if closed else "Curvy line drawn: for a pipe, Pull along (Expert: CREATE, Sweep does the same). Or drag back to the start to close it")   # FPIPE: an open line's next step names the pipe (a sweep), not only the closing


## p039 SMOOTH: the Smooth slider of a Curvy line (0 = the line as drawn, 100 = the wobble gone); the ends stay put
func _smooth_tweak(id: String) -> Dictionary:
	return {"id": id, "field": "smooth", "label": "Smooth", "unit": "pct", "lo": 0.0, "hi": 100.0, "step": 5.0, "scale": 1.0, "words": ["Wobbly", "Smooth"]}


## p039: the curve the kernel gets, redone from the raw stroke at the feature's Smooth (the same points _finish_curve keeps)
func _rebuild_curve(f: Dictionary) -> void:
	var raw := []
	for a in f["raw"]:
		raw.append(Vector2(float(a[0]), float(a[1])))
	var sm := smooth_pts(raw, float(f.get("smooth", 0.0)))
	var out := []
	for k in _curve_keep(sm, 12):
		out.append(Part.arr2(sm[k]))
	f["ents"][0]["pts"] = out


## p039 EDGE LOOP SMOOTH (Kine's own rule): each round moves every hand point onto the average of its neighbours, so a zigzag of
## wobble flattens out. A point where the line turns sharply on purpose (a corner: the turn is 60 degrees or more and its neighbours
## do not swing back the other way) stays where the hand put it, so a drawn corner stays a corner. Up to 8 rounds at 100.
static func smooth_pts(pts: Array, strength: float) -> Array:
	var p := pts.duplicate()
	var n := p.size()
	if strength <= 0.0 or n < 3:
		return p
	for _r in int(roundf(strength / 100.0 * 8.0)):
		var turn := PackedFloat32Array()
		turn.resize(n)
		for i in range(1, n - 1):
			turn[i] = (p[i] - p[i - 1]).angle_to(p[i + 1] - p[i])
		var q := p.duplicate()
		for i in range(1, n - 1):
			if not _is_corner(turn, i):
				q[i] = ((p[i - 1] as Vector2) + (p[i] as Vector2) * 2.0 + (p[i + 1] as Vector2)) * 0.25
		p = q
	return p


static func _is_corner(turn: PackedFloat32Array, i: int) -> bool:
	if absf(turn[i]) < deg_to_rad(60.0):
		return false
	for j in [i - 1, i + 1]:
		if j > 0 and j < turn.size() - 1 and sign(turn[j]) == -sign(turn[i]) and absf(turn[j]) >= deg_to_rad(15.0):
			return false   # the hand swings back on one side: a wobble, not a corner
	return true


## P040 LINE: a drag of stretches. A stretch drawn with Shift held is curvy (a spline through its points), any other stretch is straight.
## Runs of the same kind become one entity each (a straight run a line, a curvy run a bspline), joined end to end. One undo step.
func _finish_line() -> void:
	var pts: Array = _draft.get("pts", [])
	var segs: Array = _draft.get("segs", [false])
	var fc: Dictionary = _draft.get("face", {})
	var cuts: Array = _draft.get("cuts", [])   # P045: the points a typed stretch starts and ends on (each is a run's end)
	_draft = {}
	var total := 0.0
	for i in range(1, pts.size()):
		total += (pts[i] as Vector2).distance_to(pts[i - 1] as Vector2)
	if pts.size() < 2 or total < 5.0:
		_say("Drag a bit further to draw a line: keep the button held and move at least 5 mm")
		return
	var ents := []
	var s := 0
	for i in range(1, pts.size()):
		if i == pts.size() - 1 or bool(segs[i + 1]) != bool(segs[i]) or i in cuts:   # the run ends at point i
			var ps: Array = pts.slice(s, i + 1)
			if bool(segs[i]):
				var keep := []
				for k in _curve_keep(ps, 12):
					keep.append(Part.arr2(ps[k]))
				ents.append({"k": "bspline", "pts": keep, "closed": false})
			else:
				ents.append({"k": "line", "a": Part.arr2(ps[0]), "b": Part.arr2(ps[ps.size() - 1])})
			s = i
	_begin("Line")
	var rec := pu._ensure()
	rec["features"].append(Part.new_feature(rec, "sketch", {"plane": _face_plane(rec, fc), "ents": ents, "dims": []}))
	_end()
	armed = ""
	tweak = {}
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_say("Line drawn. Straight stretches stay straight, stretches drawn with Shift curve. Draw a round or box shape, then Pull along")


## P040: Shift is held (the last mouse event said so, or the key is down): the stretch a Line drag adds now is curvy
var _shift := false
func _shift_held() -> bool:
	return _shift or Input.is_key_pressed(KEY_SHIFT)


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
	_cut_sync()   # P101 SECTION: the Cut view follows the built part, and goes off when Easy is left
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
	view_box.visible = on   # P107 FITVIEW
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
	if colour_box.visible:
		_weight_sync()   # p057: the weight chips follow the Part (only read when its steps change)
	repeat_box.visible = on and armed == "" and rep_id != "" and not Part.feature(_rec(), rep_id).is_empty()
	var smooth := on and _smooth_on()   # P035: after a Join the stick box holds only the Smooth the joints chip
	stick_box.visible = (on and armed == "stick" and stick_picks.size() == 2) or smooth
	smooth_btn.visible = smooth
	for jb in joint_btns:   # p121: the joint words belong to the two-pieces-picked box, not to the chip after a Join
		(jb as Button).visible = not smooth
	for so in stick_btns:
		(stick_btns[so] as Button).visible = not smooth
	explode_box.visible = on and int(pu.res.get("bodies", 0)) >= 2 and armed == "" and not _hole_on() and not _split_on()   # EXPLODE (p103): two or more pieces; not over a hole's or a cut's keep chips
	if not explode_box.visible and pu.explode_mm != 0.0:
		_explode_reset()
	if del_on and (armed != "" or (_rec().get("features", []) as Array).size() != del_n):
		_pick_clear()   # FDELETE: a pick ends with the step it was made on
	del_btn.visible = on and del_on
	_slider_box_sync(on and not _hole_on() and not _split_on())   # p052scalepiece: Size % and Taller only follow the picked piece
	var along := on and _along_ok(_rec())   # P026: Pull along takes the chip's place while a curve and a shape wait
	var tilt_on := not along and _tilt_ok(_rec())
	var draft_on := not along and _draft_ok(_rec())
	pull_along_btn.visible = along
	tilt_btn.visible = tilt_on
	draft_btn.visible = draft_on
	var swing_on := not along and _swing_ok(_rec())   # p123driveit
	swing_btn.visible = swing_on
	var flat_on := on and armed == "" and int(pu.res.get("bodies", 0)) > 0 and Part.available()   # p113: Lay it flat and Show overhangs, under any solid, in the step list
	flat_box.visible = flat_on
	paint_btn.set_pressed_no_signal(paint_on)
	suggest_row.visible = on and _suggest_on()   # P092: after a Pull it up the two next-step chips show in the panel, under the slider rows
	tilt_box.visible = on and armed == "" and (along or tilt_on or draft_on or swing_on)
	_overhang_sync(on)
	steps_box.visible = on and not _rec().get("features", []).is_empty()   # NSTEPLIST
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
		_autosave()
		_restore_sync()
	if dots.visible and (not _drag.is_empty() or not _draft.is_empty()):
		dots.queue_redraw()
	if m.cam != null:
		dots.queue_redraw()
		_draft_dims_sync()   # P044: the sides' lengths follow the held corner (none when no draft)
	_size_sync()
	_frame_step()
const ENTRY_PITCH := -30.0


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
	if _line_typed_key(k):   # P045: a Line being drawn takes a typed length (digits, Backspace, Enter); the digits do not turn the camera
		get_viewport().set_input_as_handled()
		return
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


## a press on the top bar's BUTTONS never reaches input() (the button takes it in the GUI pass first): this sees it before the GUI,
## notes it, and lets the button have it. A drag that then leaves the bar starts the sketch (input() below, from the noted press)
func _input(ev: InputEvent) -> void:
	if ev is InputEventKey:
		_key(ev as InputEventKey)   # EKEYS: Escape and Delete (Ctrl+Z / Ctrl+Y are main's undo and redo)
		return
	if ev is InputEventMouse:
		_shift = (ev as InputEventMouse).shift_pressed   # P040: this event's Shift (the sketch below reads it before input() runs)
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
		_shift = (ev as InputEventMouse).shift_pressed   # P040: Shift held on a Line stretch makes that stretch curvy
	if not active() or not Part.available():
		if edge_chip != null and edge_chip.visible:
			_edge_hide()
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
			if armed == "hold" and not _over_ui(p):
				return _hold_press(p)   # p131grippoint: the press on the part sets the grip point
			if (armed == "draw" or armed == "curve") and not _over_ui(p):
				return _start_draft(p)
			if armed == "" and not _over_ui(p) and _edge_press(p):
				return true
			if armed == "" and not _over_ui(p):
				_pick_p = p   # FDELETE: a click (no drag) on a piece picks it, on the release
			return false
		if not _edge.is_empty():
			if p.distance_to(_edge["press"] as Vector2) >= 6.0:
				_edge_end()
				return true
			# a click (no drag) on an edge is the face or piece press: it falls through to the pick / open-face code below
			_pick_p = _edge["press"] as Vector2
			_edge = {}
			edge_num.visible = false
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
				if wall_pick:   # p022shellwalls: Thicker wall is waiting for a wall: this press picks it (or says why not)
					_wall_press(p)
				elif not _open_face(p):   # NOPENTOP: after Hollow inside, a flat face click opens that side; any other click picks a piece
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
		if armed == "" and h == "":
			_edge_hover(p)   # NEDGECHIP: a built edge under the pointer shows its chip
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
		var sh := String(_draft["shape"])
		if (sh == "curve" or sh == "line") and (g as Vector2).distance_to((_draft["pts"] as Array).back()) >= 5.0:
			(_draft["pts"] as Array).append(g)
			if sh == "line":   # P040: the stretch that ends here is curvy when Shift is held
				var segs: Array = _draft.get("segs", [false])
				segs.append(_shift_held())
				_draft["segs"] = segs
	dots.queue_redraw()


func _draft_end() -> void:
	if String(_draft["shape"]) == "line":
		_finish_line()
	elif String(_draft["shape"]) == "curve":
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
	if edge_chip != null and edge_chip.visible and edge_chip.get_global_rect().has_point(p):
		return true   # NEDGECHIP: the edge chip is a button: its press is not a pick
	# hint and status are WORDS only (a _pill: mouse_filter IGNORE, one Label, no button): a press under them is the grid's, not eaten
	for c in [bar, make_box, view_box, panel, shape_box, colour_box, repeat_box, stick_box, explode_box, tilt_box, size_box]:   # P107 FITVIEW: the view row is a button row, a press on it is not the grid's
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



# ---------------------------------------------------------------- NEDGECHIP: the edge chip and its ghost

var edge_chip: PanelContainer      # the one small chip over a hovered edge: Round / Bevel (only the ones that work)
var hinge_pick := {}               # P068: the door picked by the first Hinge press: {"body", "a", "b"} (metres); {} = none
var edge_chip_row: HBoxContainer
var edge_ghost: MeshInstance3D     # the see-through preview of the Round result, drawn over the solid
var _ehov := {}                    # the hovered edge: {"key", "mid" (px), "opts" {kind: {"err", "mesh", "fields"}}}
var _ecache := {"rec": "", "edges": []}   # the built record edges (one replay per change of the record)


func _edge_chip_ensure() -> void:
	if edge_chip != null:
		return
	edge_chip = PanelContainer.new()
	edge_chip.name = "easypart_edge_chip"
	edge_chip.visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.12, 0.16, 0.92)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(4)
	edge_chip.add_theme_stylebox_override("panel", sb)
	edge_chip_row = HBoxContainer.new()
	edge_chip_row.add_theme_constant_override("separation", 4)
	edge_chip.add_child(edge_chip_row)
	m.ui_root.add_child(edge_chip)
	edge_ghost = MeshInstance3D.new()
	edge_ghost.name = "easypart_edge_ghost"
	edge_ghost.visible = false
	var mt := StandardMaterial3D.new()
	mt.albedo_color = Color(0.45, 0.85, 1.0, 0.3)   # see-through: the solid shows under it
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.cull_mode = BaseMaterial3D.CULL_DISABLED
	edge_ghost.material_override = mt
	pu.bu.root3.add_child(edge_ghost)


## the built record edges (the list Round picks from), one replay per change of the record
func _edge_list() -> Array:
	var rec := _rec()
	var key := JSON.stringify(rec)
	if key != String(_ecache["rec"]):
		var res := Part.replay(rec, -1, {"edges": true})
		_ecache = {"rec": key, "edges": res["edges"] if int(res["bodies"]) > 0 else []}
	return _ecache["edges"]


## the chip and ghost go away (no hover, or a press / draw is under way)
func _edge_hide() -> void:
	if edge_chip != null:
		edge_chip.visible = false
	if edge_ghost != null:
		edge_ghost.visible = false
	_ehov = {}


## a pointer move at p (no press, nothing armed): the built edge under it shows the chip
func _edge_hover(p: Vector2) -> void:
	if not active() or not Part.available() or pu == null or m.cam == null or int(pu.res.get("bodies", 0)) == 0:
		_edge_hide()
		return
	_edge_chip_ensure()
	if edge_chip.visible and edge_chip.get_global_rect().has_point(p):
		return   # the pointer is on the chip itself: it stays up for the click
	var best := -1
	var bd := EDGE_PX
	var es := _edge_list()
	var pieces := int(pu.res.get("bodies", 0)) >= 2   # P068: with two pieces, the edge of either one can take a Hinge
	for i in es.size():
		var e: Dictionary = es[i]
		if (int(e["body"]) != 0 and not pieces) or bool(e.get("seam", false)):
			continue
		if m.cam.is_position_behind(e["a"]) or m.cam.is_position_behind(e["b"]):
			continue
		var a: Vector2 = m.cam.unproject_position(e["a"])
		var b: Vector2 = m.cam.unproject_position(e["b"])
		var d := Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p)
		if d < bd:
			bd = d
			best = i
	if best < 0:
		_edge_hide()
		return
	var e: Dictionary = es[best]
	var c: Vector3 = e["c"]
	var key := "%.6f,%.6f,%.6f" % [c.x, c.y, c.z]
	if key == String(_ehov.get("key", "")):
		return   # the same edge: the chip and ghost are already up
	var mid: Vector2 = m.cam.unproject_position(c)
	_ehov = {"key": key, "mid": mid, "opts": _edge_options(e) if int(e["body"]) == 0 else {}, "e": e}
	_edge_show()


## what each chip would do to this edge: Round and Bevel, each checked by a full replay (the errors name the bad steps)
func _edge_options(e: Dictionary) -> Dictionary:
	var bb: AABB = pu.res.get("aabb", AABB())
	var small := minf(bb.size.x, minf(bb.size.y, bb.size.z)) / Part.MM
	var r := snappedf(clampf(small * 0.01, 1.0, 6.0), 0.1)   # the same default as Round the edges: 1% of the smallest size, 1 to 6 mm
	var out := {}
	for kind in ["fillet", "chamfer"]:
		var fields := {"body": 0, "edges": [Part.describe(e)]}
		if kind == "fillet":
			fields["r"] = r
		else:
			fields["dist"] = r
		var rec := _rec().duplicate(true)
		var f := Part.new_feature(rec, kind, fields)
		rec["features"].append(f)
		var res := Part.replay(rec, -1, {})
		var err := String(res["errors"].get(String(f["id"]), ""))
		out[kind] = {"err": err, "mesh": res["mesh"] if err == "" else null, "fields": fields}
	return out


func _edge_show() -> void:
	var opts: Dictionary = _ehov["opts"]
	for c in edge_chip_row.get_children():
		edge_chip_row.remove_child(c)
		c.queue_free()
	var words := {"fillet": ["Round", "part_fillet", "Soften this edge into a rounded corner"], "chamfer": ["Bevel", "part_chamfer", "Cut this edge flat: a slanted edge"]}
	var shown := 0
	for kind in ["fillet", "chamfer"]:
		if not opts.has(kind) or String(opts[kind]["err"]) != "" or not hinge_pick.is_empty():
			continue
		var b := Button.new()
		b.name = "easypart_edge_" + ("round" if kind == "fillet" else "bevel")
		b.text = words[kind][0]
		b.icon = Icons.tex(words[kind][1])
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = words[kind][2]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(96, 44)
		b.pressed.connect(_edge_do.bind(kind))
		edge_chip_row.add_child(b)
		shown += 1
	if int(pu.res.get("bodies", 0)) >= 2 and _ehov.has("e"):   # P068: the Hinge chip: the door edge, then the frame edge
		var hb := Button.new()
		hb.name = "easypart_edge_hinge"
		hb.text = "Hinge"
		hb.icon = Icons.tex("part_hinge")
		hb.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		hb.tooltip_text = "Hinge: click the door's edge, then the frame's edge on the other piece. The door swings about the frame edge"
		hb.focus_mode = Control.FOCUS_NONE
		hb.custom_minimum_size = Vector2(96, 44)
		hb.pressed.connect(_hinge_chip)
		edge_chip_row.add_child(hb)
		shown += 1
	if shown == 0:
		var l := Label.new()
		l.text = "This edge will not take a round or a bevel: Pull it up taller, or use Round the edges"
		edge_chip_row.add_child(l)
	var ghost_ok: bool = opts.has("fillet") and String(opts["fillet"]["err"]) == "" and opts["fillet"]["mesh"] != null
	edge_ghost.mesh = opts["fillet"]["mesh"] if ghost_ok else null
	edge_ghost.visible = ghost_ok
	edge_chip.visible = true
	var sz := edge_chip.get_combined_minimum_size()
	var vp: Vector2 = m.ui_root.size
	var at: Vector2 = _ehov["mid"] + Vector2(-sz.x * 0.5, -sz.y - 14.0)
	at.x = clampf(at.x, 4.0, maxf(4.0, vp.x - sz.x - 4.0))
	at.y = clampf(at.y, 4.0, maxf(4.0, vp.y - sz.y - 4.0))
	edge_chip.position = at
	edge_chip.size = sz
	pu.pov.queue_redraw()


## a chip press: the one edge becomes rounded (or bevelled), one undo step. A refusal says why and changes nothing
func _edge_do(kind: String) -> void:
	if _ehov.is_empty():
		return
	var opts: Dictionary = _ehov["opts"]
	var fields: Dictionary = (opts[kind]["fields"] as Dictionary).duplicate(true)
	_edge_hide()
	_flush_if_dirty()
	armed = ""
	var snap := _rec().duplicate(true)
	_begin("Round the edge" if kind == "fillet" else "Bevel the edge")
	var rec := pu._ensure()
	var f := Part.new_feature(rec, kind, fields)
	rec["features"].append(f)
	var err := String(pu.replay_full(rec)["errors"].get(String(f["id"]), ""))
	if err != "":
		m.S.part = snap   # nothing changes: the step taken a moment ago goes back out
		m._drop_undo()
		_edit_n = -1
		_say("This edge would not take it: pick another edge, or press Round the edges on the whole part")
		return
	_end()
	if kind == "fillet":
		_round_done(f)
	else:
		tweak = {"id": f["id"], "field": "dist", "label": "Bevel size", "unit": "cm", "lo": 0.1, "hi": 1.0, "step": 0.1, "scale": 10.0, "words": ["Smaller", "Bigger"]}
		_say("Edge bevelled: use the slider for more or less, or press Cut a hole next")
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_values_sync()


## P068 HINGE BY CLICK: the first Hinge press takes the door (the edge's piece turns); the second, on an edge of another piece, places the hinge
## on that edge's line (the pin): the door swings about the frame edge. One undo step. A refusal says the next step and changes nothing
func _hinge_chip() -> void:
	var e: Dictionary = _ehov.get("e", {})
	_edge_hide()
	if e.is_empty():
		return
	if hinge_pick.is_empty():
		hinge_pick = {"body": int(e["body"]), "a": e["a"], "b": e["b"]}
		_say("Door picked. Now hover the frame edge on the other piece, and press Hinge")
		return
	if int(e["body"]) == int(hinge_pick["body"]):
		_say("Pick the frame edge on the other piece: a door cannot hinge on its own piece")
		return
	_hinge_place(e)


func _hinge_place(frame: Dictionary) -> void:
	_flush_if_dirty()
	armed = ""
	var snap := _rec().duplicate(true)
	_begin("Hinge the door")
	var rec := pu._ensure()
	var a: Vector3 = frame["a"]
	var d: Vector3 = ((frame["b"] as Vector3) - a).normalized()
	var mm := Part.MM
	var f := Part.new_feature(rec, "hinge", {"body": int(hinge_pick["body"]), "o": [a.x / mm, a.y / mm, a.z / mm], "axis": [d.x, d.y, d.z], "track": [[0.0, 0.0], [2.0, 90.0]], "clear": []})
	rec["features"].append(f)
	var why := _last_error(rec, String(f["id"]))
	if why != "":
		m.S.part = snap   # nothing changes: the step taken a moment ago goes back out
		m._drop_undo()
		_edit_n = -1
		_say("That hinge would not work: pick the door edge again, then another frame edge. " + _plain(why))
		return
	_end()
	hinge_pick = {}
	pu.upto = -1
	pu.sync()
	_rows_sync()
	_values_sync()
	_say("Hinge placed: the door swings about the frame edge. Press Play in Expert Part's Hinge to see it turn")


# ---------------------------------------------------------------- the step list (NSTEPLIST)

## NSTEPLIST: the step list: one row per step of the record, in plain words, with its icon. A click on a row opens that step to change
## (its slider comes back in the panel; the change is one undo step and replays the later steps). The open step's row is pressed
func _steps_box() -> PanelContainer:
	var box := PanelContainer.new()
	box.name = "easypart_steps"
	box.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.92), 10, 6))
	box.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	box.add_child(v)
	var t := Label.new()
	t.name = "easypart_steps_title"
	t.text = "Your steps"
	t.add_theme_font_size_override("font_size", 16)
	t.add_theme_color_override("font_color", Tok.c("heading"))
	# P106: the sheet button sits on the title line, so the box does not grow downward (a taller box covered the grid's right side)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 8)
	v.add_child(th)
	th.add_child(t)
	var sheet := _sheet_button()
	th.add_child(sheet)
	var sr := HBoxContainer.new()   # p089scrubthehi: Scrub the history, a slider that replays the build step by step
	sr.name = "easypart_scrub_row"
	sr.add_theme_constant_override("separation", 6)
	v.add_child(sr)
	var ic := TextureRect.new()
	ic.texture = Icons.sized("part_sketch", 20)
	ic.tooltip_text = "Scrub the history"
	sr.add_child(ic)
	scrub_sl = HSlider.new()
	scrub_sl.name = "easypart_scrub"
	scrub_sl.min_value = 1
	scrub_sl.max_value = 1
	scrub_sl.step = 1
	scrub_sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scrub_sl.tooltip_text = "Drag back to see the part after fewer steps. Drag to the end to see all of it"
	scrub_sl.value_changed.connect(func(x: float): _scrub_to(int(x)))
	sr.add_child(scrub_sl)
	scrub_lbl = Label.new()
	scrub_lbl.name = "easypart_scrub_label"
	scrub_lbl.add_theme_font_size_override("font_size", 13)
	scrub_lbl.add_theme_color_override("font_color", Tok.c("info"))
	v.add_child(scrub_lbl)
	var sc := ScrollContainer.new()
	sc.name = "easypart_steps_scroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(PW - 24.0, 40.0)
	v.add_child(sc)
	steps_vb = VBoxContainer.new()
	steps_vb.name = "easypart_steps_list"
	steps_vb.add_theme_constant_override("separation", 3)
	steps_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(steps_vb)
	var show_b := Button.new()   # P095: plays the steps as a ghost, one at a time (see _demo_start)
	show_b.name = "easypart_show_how"
	show_b.text = "Show me how"
	show_b.icon = Icons.sized("play", 20)
	show_b.expand_icon = false
	show_b.focus_mode = Control.FOCUS_NONE
	show_b.add_theme_font_size_override("font_size", 15)
	show_b.tooltip_text = "Show me how: the steps of this part, one at a time as a see-through ghost, so you can copy each one on your own part. Nothing on the model changes"
	show_b.pressed.connect(_demo_start)
	v.add_child(show_b)
	return box


## P106: the Instruction sheet button (on the step list's title line): one click writes the page (see _sheet_press)
func _sheet_button() -> Button:
	var sheet := Button.new()
	sheet.name = "easypart_sheet"
	sheet.text = "Instruction sheet"
	sheet.icon = Icons.sized("export", 18)
	sheet.expand_icon = false
	sheet.focus_mode = Control.FOCUS_NONE
	sheet.add_theme_font_size_override("font_size", 13)
	sheet.tooltip_text = "Make a printable instruction sheet: the parts list and each step with its picture. It opens in your browser: print it, or Save as PDF"
	sheet.pressed.connect(func(): _sheet_press())
	return sheet


## P106: the Instruction sheet button. Writes the page (PartSheet) and opens it in the browser. No undo step: the part is not changed
func _sheet_press() -> void:
	var rec := _rec()
	var steps: Array = []
	var fs: Array = rec.get("features", [])
	for i in fs.size():
		var w := step_words(fs[i])
		if w != "":
			steps.append({"upto": i, "words": w})
	if steps.is_empty() or Part.replay(rec)["mesh"] == null:
		_say("Make a shape first: the sheet shows each step with its picture")
		return
	var path := await PartSheet.write(m, rec, _nm(), steps)
	if path == "":
		_say("The sheet did not save: press Instruction sheet again")
		return
	m._shell_open(path)
	_say("The instruction sheet is open in your browser: print it, or Save as PDF")

## p113: the two printing chips, one box under the step list (Lay it flat turns the part; Show overhangs paints red where it needs support)
func _printing_box() -> PanelContainer:
	var box := PanelContainer.new()
	box.name = "easypart_printing"
	box.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.92), 10, 6))
	box.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	box.add_child(v)
	lay_btn = _big_btn("easypart_lay_flat", "Lay it flat", "Turn the part so the face that needs the least support under it sits on the floor", _lay_press)
	lay_btn.custom_minimum_size = Vector2(PW - 40.0, 40)
	v.add_child(lay_btn)
	paint_btn = _big_btn("easypart_show_overhangs", "Show overhangs", "Paint red the faces a printer needs support under (they point down more than 45 degrees)", _paint_press)
	paint_btn.toggle_mode = true
	paint_btn.custom_minimum_size = Vector2(PW - 40.0, 40)
	v.add_child(paint_btn)
	return box


## NSTEPLIST: the step's plain words ("" = no row: a helper plane). Pulled up N cm, Rounded N edges R mm, Drew a shape, Hollowed out
func step_words(f: Dictionary) -> String:
	match String(f.get("t", "")):
		"sketch":
			return "Drew a shape"
		"lay":
			return "Laid it flat"
		"loft":
			return "Blended two shapes"
		"extrude":
			var cm := _fmt_cm(absf(float(f.get("dist", 0.0))))
			if String(f.get("op", "")) == "cut":
				return "Cut a slot %s deep" % cm
			if bool(f.get("both", false)):
				return "Pulled out both ways %s" % cm
			return "Pulled up %s" % cm
		"hinge":
			return "Swung it open %d degrees" % int(SWING_DEG)
		"fillet":
			var n := (f.get("edges", []) as Array).size()
			return "Rounded %d %s %s mm" % [n, "edge" if n == 1 else "edges", _plain_num(float(f.get("r", 0.0)))]
		"shell":
			return "Hollowed out, wall %s mm" % _plain_num(float(f.get("thick", 0.0)))
		"appear":
			return "Coloured"
		"mirror":
			return "Mirrored it"
		"pattern":
			return "Repeated it"
		"plane":
			return ""
	return "Changed the shape"


## NSTEPLIST: the step's icon (the MAKES icon of its kind)
static func step_icon(t: String) -> String:
	match t:
		"sketch":
			return "part_rectangle"
		"extrude":
			return "part_extrude"
		"fillet":
			return "part_fillet"
		"shell":
			return "part_circle"
		"mirror":
			return "part_mirror"
		"pattern":
			return "part_pattern"
		"appear":
			return "part_appearance"
	return "part_mirror"


## NSTEPLIST: the slider that opens a step: its own field (How far, How round, Wall); {} when the step has none
func _step_tweak(f: Dictionary) -> Dictionary:
	var id := String(f.get("id", ""))
	match String(f.get("t", "")):
		"extrude":
			var sg := -1.0 if float(f.get("dist", 0.0)) < 0.0 else 1.0
			return {"id": id, "field": "dist", "label": "How far", "unit": "cm", "lo": 0.2, "hi": _pull_hi(), "step": 0.2, "scale": 10.0, "words": ["Flatter", "Taller"], "sgn": sg}
		"fillet":
			return {"id": id, "field": "r", "label": "How round", "unit": "cm", "lo": 0.1, "hi": 1.0, "step": 0.1, "scale": 10.0, "words": ["Barely", "Very round"]}
		"shell":
			return {"id": id, "field": "thick", "label": "Wall", "unit": "mm", "lo": 1.0, "hi": 10.0, "step": 0.5, "scale": 1.0, "words": ["Thinner", "Thicker"]}
		"loft":
			return _twist_tweak(id) if f.has("twist") else {}
	return {}


## NSTEPLIST: a click on a step row: its slider comes back in the panel (no undo step of its own; the slider's change is the step)
func _step_open(id: String) -> void:
	var f := Part.feature(_rec(), id)
	var tw := _step_tweak(f)
	if tw.is_empty():
		_say("%s has no number to change: Undo takes it back" % step_words(f))
		return
	tweak = tw
	taper_tw = {}
	twist_tw = {}
	_rows_sig = ""
	_rows_sync()
	_say("Change the step: %s. The later steps are made again" % String(tw["label"]))
	_steps_sig = ""
	_steps_sync()


## p089scrubthehi: Scrub the history: the part as it stood after its first k steps. A view only: the record and the undo list do not change,
## and the slider's end (all the steps) is the real part. Any other press takes the view back to the end (it sets pu.upto = -1 first)
func _scrub_to(k: int) -> void:
	var n := int(_rec().get("features", []).size())
	k = clampi(k, 1, maxi(n, 1))
	pu.upto = -1 if k >= n else k - 1
	pu.sync()
	_scrub_sync()


## p089scrubthehi: the slider follows the record and the view (a new step moves its end; a press that leaves the view moves it back)
func _scrub_sync() -> void:
	if scrub_sl == null or not is_instance_valid(scrub_sl) or pu == null:
		return
	var n := int(_rec().get("features", []).size())
	scrub_sl.max_value = maxi(n, 1)
	var k := n if pu.upto < 0 else pu.upto + 1
	scrub_sl.set_value_no_signal(k)
	scrub_lbl.text = "Showing all %d steps" % n if k >= n else "Showing step %d of %d. Drag to the end to go on" % [k, n]


func _steps_sync() -> void:
	_scrub_sync()   # p089scrubthehi
	if steps_vb == null or not is_instance_valid(steps_vb):
		return
	var fs: Array = _rec().get("features", [])
	var sig := "%s|%s" % [JSON.stringify(fs), String(tweak.get("id", ""))]
	if sig == _steps_sig:
		return
	_steps_sig = sig
	for c in steps_vb.get_children():
		steps_vb.remove_child(c)
		c.queue_free()
	for f in fs:
		var words := step_words(f)
		if words == "":
			continue
		var b := Button.new()
		b.name = "easypart_step_%s" % String(f.get("id", ""))
		b.text = words
		b.icon = Icons.sized(step_icon(String(f.get("t", ""))), 20)
		b.expand_icon = false
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.set_pressed_no_signal(String(f.get("id", "")) == String(tweak.get("id", "")) and not tweak.is_empty())
		b.add_theme_font_size_override("font_size", 15)
		b.tooltip_text = "Click to change this step"
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var fid := String(f.get("id", ""))
		b.pressed.connect(func(): _step_open(fid))
		steps_vb.add_child(b)

## p083favourites (Friday plan 83) and p083favfix: the Favourites category of the Parts library. Its page is the row. It lists the favourites (starred, first) and then the
## parts used lately (six at most). A chip puts that part on the floor again (one undo step, the same as the Parts chips). The star keeps
## the part on the floor as a favourite: a list, not a model step, so it makes no undo step. The lists live in FAV_FILE (user://).
const FAV_FILE := "user://easy_part_favs.json"
const FAV_RECENT_MAX := 6
var fav_box: PanelContainer          # the Favourites category page (_fav_box)
var fav_row: HFlowContainer          # the row (its chips come and go; the star and the label stay)
var fav_label: Label                 # "Favourites:" or "Favourites: none yet ..."
var fav_star: Button                 # Add to favourites / Remove favourite, for the part on the floor
var fav_btns := {}                   # key ("M4 x 16" or "Gear") -> its chip
var fav_data := {}                   # {"fav": [...], "recent": [...]}, read from FAV_FILE once


## the Favourites page: a panel with the row in it (under the Boards chips; shown by _screw_sync while the category is open)
func _fav_box() -> PanelContainer:
	var pc := PanelContainer.new()
	pc.name = "easypart_fav_box"
	pc.add_theme_stylebox_override("panel", _style(Color(0.12, 0.125, 0.15), 10, 6))
	pc.visible = false
	pc.add_child(_fav_row())
	return pc


## the row: a label, then the chips (added by _fav_sync), and the star last
func _fav_row() -> HFlowContainer:
	fav_row = HFlowContainer.new()
	fav_row.name = "easypart_fav_row"
	fav_row.add_theme_constant_override("h_separation", 4)
	fav_row.add_theme_constant_override("v_separation", 4)
	fav_label = Label.new()
	fav_label.name = "easypart_fav_label"
	fav_label.add_theme_font_size_override("font_size", 13)
	fav_row.add_child(fav_label)
	fav_star = Button.new()
	fav_star.name = "easypart_fav_star"
	fav_star.icon = _fav_icon()
	fav_star.tooltip_text = "Keep the part on the floor as a favourite: it comes first in this row"
	fav_star.focus_mode = Control.FOCUS_NONE
	fav_star.custom_minimum_size = Vector2(0, 34)
	fav_star.add_theme_font_size_override("font_size", 13)
	fav_star.add_theme_stylebox_override("normal", _style(Color(0.165, 0.176, 0.212), 6, 4))
	fav_star.add_theme_stylebox_override("hover", _style(Color(0.23, 0.245, 0.29), 6, 4))
	fav_star.pressed.connect(_fav_star)
	fav_row.add_child(fav_star)
	return fav_row


## a 16 px star in the accent colour (Tok), drawn from ten points
func _fav_icon() -> ImageTexture:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var pts := PackedVector2Array()
	for i in 10:
		var r := 7.0 if i % 2 == 0 else 3.0
		var a := -PI / 2.0 + float(i) * PI / 5.0
		pts.append(Vector2(8.0, 8.5) + Vector2(cos(a), sin(a)) * r)
	var col := Tok.c("accent")
	for y in 16:
		for x in 16:
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pts):
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


## the key of the part on the floor: "Gear", "M4 x 16" (a screw), or "" when the floor has neither
func _fav_key() -> String:
	var t := _tpl()
	if t == "gear":
		return "Gear"
	if t == "screw" and not (_rec().get("features", []) as Array).is_empty():
		var cur: Dictionary = (_rec().get("easy", {}) as Dictionary).get("p", {})
		var k := "M%d x %d" % [int(cur.get("d", 0)), int(cur.get("L", 0))]
		return k if _fav_valid(k) else ""
	return ""


static func _fav_valid(k: String) -> bool:
	if k == "Gear":
		return true
	for d in SCREW_DS:
		for L in SCREW_LENS:
			if k == "M%d x %d" % [d, L]:
				return true
	return false


## the favourites file, read once; a missing or broken file is an empty list
func _fav_load() -> void:
	if not fav_data.is_empty():
		return
	fav_data = {"fav": [], "recent": []}
	if not FileAccess.file_exists(FAV_FILE):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(FAV_FILE))
	if not (d is Dictionary):
		return
	for list_name in ["fav", "recent"]:
		for n in (d as Dictionary).get(list_name, []):
			if _fav_valid(String(n)) and not (fav_data[list_name] as Array).has(String(n)):
				(fav_data[list_name] as Array).append(String(n))


func _fav_save() -> void:
	var f := FileAccess.open(FAV_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(fav_data))
		f.close()


## the part on the floor goes to the front of the recent list (six at most); then the row is drawn again
func _fav_sync() -> void:
	if fav_row == null:
		return
	_fav_load()
	var key := _fav_key()
	var rec: Array = fav_data["recent"]
	if key != "" and (rec.is_empty() or rec[0] != key):
		rec.erase(key)
		rec.push_front(key)
		while rec.size() > FAV_RECENT_MAX:
			rec.pop_back()
		_fav_save()
	var favs: Array = fav_data["fav"]
	var shown: Array = favs.duplicate()
	for k in rec:
		if not shown.has(k):
			shown.append(k)
	for k in fav_btns:
		fav_row.remove_child(fav_btns[k])
		(fav_btns[k] as Button).queue_free()
	fav_btns = {}
	for k in shown:
		var b := Button.new()
		b.name = "easypart_fav_" + String(k).replace(" ", "_")
		b.text = String(k)
		b.icon = _fav_icon() if favs.has(k) else null
		b.tooltip_text = "Put %s on the floor again. One undo step" % String(k)
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 34)
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_stylebox_override("normal", _style(Color(0.165, 0.176, 0.212), 6, 4))
		b.add_theme_stylebox_override("hover", _style(Color(0.23, 0.245, 0.29), 6, 4))
		b.pressed.connect(_fav_use.bind(String(k)))
		fav_row.add_child(b)
		fav_btns[k] = b
	fav_row.move_child(fav_star, -1)
	fav_label.text = "Favourites:" if not shown.is_empty() else "Favourites: none yet"
	fav_star.text = "Remove favourite" if key != "" and favs.has(key) else "Add to favourites"
	var why := Part.why_not() if not Part.available() else ("" if key != "" else "Put a screw or a gear on the floor first")
	m._grey(fav_star, why)


## a favourite or recent chip: Gear puts the gear on the floor; a screw size is picked as on the Screws page (one undo step)
func _fav_use(k: String) -> void:
	if not Part.available():
		_chips_sync()
		return
	if k == "Gear":
		if _tpl() == "gear":
			_say("The gear is on the floor already. Pick another part to change it")
			return
		_chip("gear")
		return
	_screw_pick(int(k.substr(1, k.find(" x ") - 1)), int(k.substr(k.find(" x ") + 3)))


## the star: the part on the floor becomes a favourite or stops being one. A list change, so no undo step
func _fav_star() -> void:
	var key := _fav_key()
	if key == "":
		_say("Put a screw or a gear on the floor first, then press the star")
		_fav_sync()
		return
	_fav_load()
	var favs: Array = fav_data["fav"]
	var on := not favs.has(key)
	if on:
		favs.append(key)
	else:
		favs.erase(key)
	_fav_save()
	_say("%s is a favourite. It comes first in Favourites" % key if on else "%s is no longer a favourite" % key)
	_fav_sync()


# ---------------------------------------------------------------- P095 SHOW ME HOW: the steps as a ghost, one at a time
## P095 (Friday plan 95, Kine's own idea): Show me how plays the part's solid steps one at a time as a see-through ghost. The user copies
## each step on their own part; the ghost changes nothing on the model (no undo step, the record is untouched).
var demo_box: PanelContainer      # the ghost panel: its words, Back, Next, Done (bottom left)
var demo_words: Label
var demo_back: Button
var demo_next: Button
var demo_ghost: MeshInstance3D    # the see-through solid of the step shown, in the part's own space
var demo_steps: Array = []        # the record's feature indices that make a solid step (a sketch only draws a line; a plane is a helper)
var demo_k := -1                  # the step shown (0-based); -1 = none yet


## P095: the record's solid steps, in order
func _demo_steps_of(rec: Dictionary) -> Array:
	var out := []
	var fs: Array = rec.get("features", [])
	for i in fs.size():
		var t := String(fs[i].get("t", ""))
		if t != "sketch" and t != "plane" and step_words(fs[i]) != "":
			out.append(i)
	return out


## P095: the ghost panel and the ghost mesh, made once
func _demo_ensure() -> void:
	if demo_box != null:
		return
	demo_box = PanelContainer.new()
	demo_box.name = "easypart_demo"
	demo_box.visible = false
	demo_box.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.92), 10, 8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	demo_box.add_child(v)
	demo_words = Label.new()
	demo_words.name = "easypart_demo_words"
	demo_words.add_theme_font_size_override("font_size", 15)
	demo_words.add_theme_color_override("font_color", Tok.c("heading"))
	demo_words.custom_minimum_size = Vector2(340, 0)
	demo_words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(demo_words)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	demo_back = _demo_btn("Back", "back", "Show the step before, as a ghost (nothing on the model changes)", _demo_step.bind(-1), "easypart_demo_back")
	row.add_child(demo_back)
	demo_next = _demo_btn("Next", "", "Show the next step, as a ghost (nothing on the model changes)", _demo_step.bind(1), "easypart_demo_next")
	row.add_child(demo_next)
	row.add_child(_demo_btn("Done", "", "Close the ghost: the model is as it was", _demo_close, "easypart_demo_done"))
	m.ui_root.add_child(demo_box)
	demo_ghost = MeshInstance3D.new()
	demo_ghost.name = "easypart_demo_ghost"
	demo_ghost.visible = false
	var mt := StandardMaterial3D.new()
	mt.albedo_color = Color(0.45, 0.85, 1.0, 0.3)   # see-through, like the Round preview: the copy is drawn under it
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.cull_mode = BaseMaterial3D.CULL_DISABLED
	demo_ghost.material_override = mt
	pu.bu.root3.add_child(demo_ghost)


func _demo_btn(text: String, icon: String, tip: String, cb: Callable, nm: String) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = text
	if icon != "":
		b.icon = Icons.sized(icon, 20)
		b.expand_icon = false
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(cb)
	return b


## P095: Show me how (the steps box button): opens the ghost panel before step 1; nothing on the model changes
func _demo_start() -> void:
	_demo_ensure()
	demo_steps = _demo_steps_of(_rec())
	if demo_steps.is_empty():
		_say("Nothing to show yet: draw a shape and pull it up first")
		return
	demo_k = -1
	demo_ghost.visible = false
	demo_box.visible = true
	var sz := demo_box.get_combined_minimum_size()
	var vp: Vector2 = m.ui_root.size
	demo_box.size = sz
	demo_box.position = Vector2(12.0, maxf(4.0, vp.y - sz.y - 12.0))
	_demo_text()
	_say("Show me how: press Next to see step 1, then copy it on your own part")


## P095: Back / Next: the ghost moves one solid step (Back from step 1 stays on step 1; Next past the last stays on it)
func _demo_step(d: int) -> void:
	if demo_steps.is_empty() or (demo_k < 0 and d < 0):
		return
	demo_k = clampi(demo_k + d, 0, demo_steps.size() - 1)
	var mesh: Mesh = Part.replay(_rec(), int(demo_steps[demo_k]), {})["mesh"]
	demo_ghost.mesh = mesh
	demo_ghost.visible = mesh != null
	_demo_text()
	pu.pov.queue_redraw()


## P095: the panel's words: the step's plain words from the record, and what to do next
func _demo_text() -> void:
	var n := demo_steps.size()
	if demo_k < 0:
		demo_words.text = "Press Next to see step 1 of %d, then copy it on your own part." % n
		return
	var f: Dictionary = _rec()["features"][int(demo_steps[demo_k])]
	var head := "Step %d of %d: %s." % [demo_k + 1, n, step_words(f)]
	var tail := "Copy it on your own part, then press Next." if demo_k < n - 1 else "That is the last step. Done closes this."
	demo_words.text = head + "\n" + tail
	if demo_ghost.mesh == null:
		demo_words.text = head + "\nThis step makes no solid to show. Press Next to go on."


## P095: Done: the ghost and its panel go away; the model was never changed
func _demo_close() -> void:
	demo_k = -1
	demo_steps = []
	if demo_box != null:
		demo_box.visible = false
	if demo_ghost != null:
		demo_ghost.visible = false
		demo_ghost.mesh = null


## p067hinges: the Hinges page's Hinge button: the page closes (the hinge's Kind and Door height sliders take its room), then a Butt
## hinge drops on the floor at the door's height. One undo step (the chip's).
func _hinges_btn_press() -> void:
	parts_open = false
	_chip("hinge")
	_screw_sync()


## p070springfix: the Springs page's Spring button: the page closes (the spring's Turns, Wire and Coil size sliders take its room),
## then the spring drops on the floor. One undo step (the chip's).
func _spring_pick_press() -> void:
	parts_open = false
	_chip("spring")
	_screw_sync()


## P045 TYPED LINE: while a Line is drawn (the button held), digits and "." type a length (the say line shows it), Backspace takes one back.
## Enter draws a straight stretch of that length from the last point, in the way the pointer is going (a new run, so it stays its own line).
## true = the key was the typed length's; any other key (Escape, Delete, Ctrl) is left to the rest of the screen
func _line_typed_key(k: InputEventKey) -> bool:
	if _draft.is_empty() or String(_draft.get("shape", "")) != "line" or not _draft.has("pts"):
		return false
	var typed := String(_draft.get("typed", ""))
	var ch := ""
	if k.keycode >= KEY_0 and k.keycode <= KEY_9:
		ch = str(k.keycode - KEY_0)
	elif k.keycode >= KEY_KP_0 and k.keycode <= KEY_KP_9:
		ch = str(k.keycode - KEY_KP_0)
	elif k.keycode in [KEY_PERIOD, KEY_KP_PERIOD]:
		ch = "."
	if ch != "":
		if ch == "." and typed.contains("."):
			return true
		_draft["typed"] = typed + ch
		_say("Length %s mm: Enter draws it, Backspace takes a digit back" % (typed + ch))
		return true
	if k.keycode == KEY_BACKSPACE and typed != "":
		_draft["typed"] = typed.left(-1)
		_say("Length %s mm: Enter draws it, Backspace takes a digit back" % typed.left(-1) if typed.length() > 1 else "Length typed: type a number, then Enter")
		return true
	if k.keycode in [KEY_ENTER, KEY_KP_ENTER] and typed != "":
		return _typed_stretch(typed)
	return false


## P045: the typed stretch: from the last point, along the way the pointer is going (RIGHT when the pointer has not moved since)
func _typed_stretch(typed: String) -> bool:
	var pts: Array = _draft["pts"]
	var last: Vector2 = pts.back()
	var cur: Vector2 = _draft.get("b", last)
	var dir := Vector2.RIGHT
	if cur.distance_to(last) >= 0.5:
		dir = (cur - last).normalized()
	elif pts.size() >= 2:
		dir = (last - (pts[pts.size() - 2] as Vector2)).normalized()
	var len := float(typed)
	if len <= 0.0:
		_say("A length must be above 0 mm: type a number, then Enter, or Backspace to clear it")
		return true
	pts.append(last + dir * len)
	var segs: Array = _draft.get("segs", [false])
	segs.append(false)
	_draft["segs"] = segs
	var cuts: Array = _draft.get("cuts", [])
	cuts.append(pts.size() - 2)
	cuts.append(pts.size() - 1)
	_draft["cuts"] = cuts
	_draft["typed"] = ""
	_say("Stretch of %s mm drawn. Keep holding to draw on, or let go to finish" % typed)
	dots.queue_redraw()
	return true


# ---------------------------------------------------------------- P101 SECTION: Cut view (view only: no record step, no undo)
# The Cut view chip (last in the view column) cuts the built part in half across the Front normal, through its middle,
# and shows the inside in orange (PartUI's section shader). The camera turns to the cut side. Nothing goes in the record.

var cut_on := false   # P101: the Cut view chip is on
var cut_btn: Button
var cut_mat: ShaderMaterial


func _cut_btn() -> Button:
	cut_btn = Button.new()
	cut_btn.name = "easypart_view_cut"
	cut_btn.text = "Cut view"
	cut_btn.icon = Icons.sized("part_section", 16)
	cut_btn.expand_icon = false
	cut_btn.toggle_mode = true
	cut_btn.tooltip_text = "Cut the part in half to look inside. View only: no undo step"
	cut_btn.focus_mode = Control.FOCUS_NONE
	cut_btn.custom_minimum_size = Vector2(0, 30)
	cut_btn.add_theme_font_size_override("font_size", 13)
	cut_btn.toggled.connect(_cut_press)
	return cut_btn


func _cut_press(on: bool) -> void:
	if on and not _cut_ready():
		cut_btn.set_pressed_no_signal(false)
		_say("Nothing to cut yet: pull a shape up first, then press Cut view")
		return
	cut_on = on
	if on:
		_cut_look()
		_say("Cut view on: the part is cut in half and the inside shows in orange. Press Cut view again to see all of it (no undo step)")
	else:
		_say("Cut view off: the whole part shows again (no undo step)")
	_cut_sync()


func _cut_ready() -> bool:
	return pu != null and pu.part_mesh != null and pu.part_mesh.mesh != null and pu.part_mesh.mesh.get_surface_count() > 0


## the built solid in world space (from its mesh), and the Front normal: the cut goes through its middle
func _cut_plane() -> Dictionary:
	var wb: AABB = pu.part_mesh.global_transform * pu.part_mesh.mesh.get_aabb()
	var n: Vector3 = Part.resolve_plane(_rec(), "front")["n"]
	return {"n": n, "w": n.dot(wb.get_center()), "box": wb}


## the camera turns to the side the cut removes (the cap faces the eye), as Expert's section does
func _cut_look() -> void:
	var d := _cut_plane()
	var n: Vector3 = d["n"]
	var wb: AABB = d["box"]
	m._turn_to(rad_to_deg(atan2(n.x, n.z)), 0.0, clampf(wb.size.length() * 1.5, 0.4, 6.0), wb.get_center(), true)


## the material: the cut shader while the chip is on and Easy is on screen; the plain look otherwise (Expert's own cut is never touched)
func _cut_sync() -> void:
	if pu == null or pu.part_mesh == null:
		return
	if not (cut_on and active() and _cut_ready()):
		if cut_mat != null and pu.part_mesh.material_override == cut_mat:
			pu.part_mesh.material_override = null
		return
	if cut_mat == null:
		cut_mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = PartUI.SECTION_SHADER
		cut_mat.shader = sh
		cut_mat.set_shader_parameter("cap", PartUI.CAP_COL)
		cut_mat.set_shader_parameter("solid", PartUI.SOLID_COL)
	var d := _cut_plane()
	var n: Vector3 = d["n"]
	cut_mat.set_shader_parameter("cut", Vector4(n.x, n.y, n.z, float(d["w"])))
	cut_mat.set_shader_parameter("on", 1.0)
	pu.part_mesh.material_override = cut_mat


## HOLD HERE (p131grippoint): the Colour page's Hold here chip arms one click. The next press on the part sets the grip point there: the
## spot is stored in the record ("grip", mm in the Part's own frame) and Give to a character holds the shape by it (PartTemplates.handle_of).
## One undo step per click; a press off the part says so and waits for another press
func _hold_chip() -> Button:
	var b := _colour_btn("hold", "Hold here", Color(0.85, 0.8, 0.6))
	b.name = "easypart_hold"
	b.tooltip_text = "Pick where the hand holds it: press here, then click the spot on the part. Give to a character then holds it there"
	b.pressed.connect(_hold_arm)
	return b


func _hold_arm() -> void:
	armed = ""
	if not Part.available():
		_say(Part.why_not())
		return
	if int(pu.res.get("bodies", 0)) == 0:
		_say("Make something solid first, then pick where the hand holds it")
		return
	armed = "hold"
	_say("Click the spot on the part where the hand holds it")


func _hold_press(p: Vector2) -> bool:
	var faces: Array = Part.body_faces(_rec(), -1)
	var hit: Dictionary = pu._ray_hit(p, faces)
	if hit.is_empty():
		_say("Click on the part itself: the hand holds a spot on its solid")
		return true
	_flush_if_dirty()
	armed = ""
	var at: Vector3 = hit["at"]
	var knob := INF   # the butt: the lowest x of the solid (metres), as PartWeapon measures it
	for f in faces:
		for v in f:
			knob = minf(knob, (v as Vector3).x)
	_begin("Hold here")
	_rec()["grip"] = [snappedf(at.x / PartTemplates.MM, 0.1), snappedf(at.y / PartTemplates.MM, 0.1), snappedf(at.z / PartTemplates.MM, 0.1)]
	_end()
	m.part_weapon_changed(_rec())   # a held Part weapon takes the new grip at once
	_say("The hand holds it here, %.1f cm from the butt" % ((at.x - knob) * 100.0))
	return true
