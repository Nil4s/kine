## ASSEMBLY SCREEN (Friday plan 213): BUILD's "New assembly" (the chooser's button). Several Parts put together in one 3D view:
##   Add part     a left list: My parts (saved), the Parts library (screws, gears, brackets...), and the saved assemblies; one click puts a part in
##   parts list   right panel: every part by name; one click selects it (a double-click opens it to edit; so does the Edit part button)
##   place        a move / turn gizmo on the selected part (drag an arrow; the Move and Turn buttons choose which) and typed numbers (mm, degrees)
##   edit         Edit part opens the Part workspace on a copy of the record; "Back to the assembly" writes the edits into the assembly
##   file         Save / Open (one .json holds every part record), Export STL, GLB, STEP (one file with every part, placed)
## The engine is scripts/build/assembly.gd. The assembly lives in this screen, not in the scene file; Part.asm_on keeps the Part chrome away.
class_name AssemblyUI
extends Node

const PANEL_W := 300.0
const SRC_W := 250.0
const HANDLE_PX := 90.0
const HIT_PX := 13.0
const AXES := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
const AX_COL := [Color(0.95, 0.35, 0.35), Color(0.4, 0.9, 0.45), Color(0.4, 0.55, 1.0)]
const AX_NAME := ["X", "Y", "Z"]

var bu: BuildUI
var m: Node
var on := false
var asm := {}                  # the assembly record (Assembly.make)
var sel := ""                  # the selected part's id
var mode := "move"             # the gizmo: "move" | "turn"
var editing := ""              # the id of the part opened in the Part workspace ("" = none)
var last_export := {}          # the last export's answer (tests read it)
var status_text := ""
var panel: PanelContainer
var src_panel: PanelContainer
var back_panel: PanelContainer
var ov: Control
var root3: Node3D
var name_edit: LineEdit
var add_btn: Button
var open_btn: Button
var save_btn: Button
var new_btn: Button
var list_vb: VBoxContainer
var part_name: LineEdit
var pos_edits: Array = []      # X Y Z LineEdits
var rot_edits: Array = []
var move_btn: Button
var turn_btn: Button
var edit_btn: Button
var remove_btn: Button
var stl_btn: Button
var glb_btn: Button
var step_btn: Button
var video_btn: Button          # G7TIME: the animation filmed (scripts/build/assembly_render.gd)
var drawing_btn: Button        # G30DRAW: exact-solid drawing and rated-block schematic sheets
var schematic_btn: Button
var sheet_exporting := false
var filming := false
var done_btn: Button
var status_l: Label
var src_tab := "library"
var src_open := false
var src_tabs := {}
var src_vb: VBoxContainer
var back_btn: Button
var meshes := {}               # part id -> MeshInstance3D
var drag := {}                 # a gizmo handle in hand: {"axis", "start", "pos", "rot", "p0", "dir", "pxm"}
var hint_l: Label
var _stash := {}               # the Part record that was open before the assembly took the page
var _had_stash := false
var _sig := ""
var _t := 0.0
var _rec_sig := ""
var _fields_sig := ""
var lock_pos: Array = []       # C15: the six lock checks (slide X Y Z, turn X Y Z)
var lock_rot: Array = []
var dof_l: Label
var fix_btn: Button
var motion_btn: Button         # G1MOTION: Check motion (scripts/build/assembly_motion_ui.gd)
var motion: AssemblyMotionUI
var bom_btn: Button            # G8BOM: the bill of materials (scripts/build/assembly_bom_ui.gd)
var bom: AssemblyBomUI
var stages_btn: Button         # G33STAGE: the build stages (scripts/build/assembly_stage_ui.gd)
var stages: AssemblyStageUI
var asm_undo: Array = []       # G1MOTION: [{"asm", "label"}]: this screen's own steps (the assembly is not in the scene's undo)
var asm_redo: Array = []


func setup(b: BuildUI) -> void:
	bu = b
	m = b.m
	name = "assembly_ui"
	m.ui_root.add_child(self)
	asm = Assembly.make("Assembly")
	root3 = Node3D.new()
	root3.name = "assembly_3d"
	root3.visible = false
	bu.root3.add_child(root3)
	_build_panel()
	_build_src()
	_build_back()
	motion = AssemblyMotionUI.new()
	motion.setup(self)
	bom = AssemblyBomUI.new()
	bom.setup(self)
	stages = AssemblyStageUI.new()
	stages.setup(self)
	ov = Control.new()
	ov.name = "assembly_overlay"
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.visible = false
	ov.draw.connect(_draw)
	m.ui_root.add_child(ov)
	m.ui_root.move_child(panel, m.ui_root.get_child_count() - 1)


func _btn(text: String, nm: String, tip: String, cb: Callable, toggle := false) -> Button:
	var b := Button.new()
	b.text = text
	b.name = nm
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = toggle
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(cb)
	return b


func _lbl(t: String, size := 13, nm := "") -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	if nm != "":
		l.name = nm
	return l


func _edit(nm: String, w: float) -> LineEdit:
	var e := LineEdit.new()
	e.name = nm
	e.custom_minimum_size = Vector2(w, 0)
	e.select_all_on_focus = true
	e.add_theme_font_size_override("font_size", 13)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return e


func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.name = "asm_panel"
	panel.visible = false
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.1, 0.11, 0.14, 0.97)
	psb.set_corner_radius_all(8)
	psb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", psb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	vb.add_child(_lbl("ASSEMBLY", 16, "asm_title"))
	name_edit = _edit("asm_name", 0)
	name_edit.placeholder_text = "Name of the assembly"
	name_edit.text_submitted.connect(func(t): _rename_asm(t))
	name_edit.focus_exited.connect(func(): _rename_asm(name_edit.text))
	vb.add_child(name_edit)
	var r1 := HBoxContainer.new()
	add_btn = _btn("Add part", "asm_add", "Put a saved part or a library part in the assembly", _toggle_src, true)
	open_btn = _btn("Open", "asm_open", "Open a saved assembly", _open_list)
	save_btn = _btn("Save", "asm_save", "Save the assembly as one file (every part inside it)", _save)
	new_btn = _btn("New", "asm_new", "Start an empty assembly", _new)
	for b in [add_btn, open_btn, save_btn, new_btn]:
		(b as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r1.add_child(b)
	vb.add_child(r1)
	var hp := HBoxContainer.new()
	var pl := _lbl("Parts", 12)   # G8BOM: was "Parts (double-click to edit one)"; the BOM button needed the room, the hint is on each row's hover now
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pl.tooltip_text = "Double-click a part to edit it"
	pl.mouse_filter = Control.MOUSE_FILTER_PASS
	hp.add_child(pl)
	motion_btn = _btn("Check motion", "asm_motion", "Move a part through its range (a hinge, a slide) and list every pair of parts that passes through another", func(): bom.close(); stages.close(); motion.open())
	hp.add_child(motion_btn)
	bom_btn = _btn("BOM", "asm_bom", "Bill of materials: every part with its material, mass (from the solid) and price, the total, a CSV, and the cheaper choices", func(): stages.close(); bom.open())
	hp.add_child(bom_btn)
	stages_btn = _btn("Stages", "asm_stages", "Build stages: the order the parts go in, a check that each rests on what is built before it, and a video of the build", func(): stages.open())
	hp.add_child(stages_btn)
	vb.add_child(hp)
	var sc := ScrollContainer.new()
	sc.name = "asm_list_scroll"
	sc.custom_minimum_size = Vector2(0, 58)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_vb = VBoxContainer.new()
	list_vb.name = "asm_list"
	list_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list_vb)
	vb.add_child(sc)
	part_name = _edit("asm_part_name", 0)
	part_name.placeholder_text = "Name of the selected part"
	part_name.text_submitted.connect(func(t): _rename_part(t))
	part_name.focus_exited.connect(func(): _rename_part(part_name.text))
	vb.add_child(part_name)
	vb.add_child(_row_fields("Move (mm)", ["X", "Y", "Z"], pos_edits, "asm_pos_"))
	vb.add_child(_row_fields("Turn (degrees)", ["X", "Y", "Z"], rot_edits, "asm_rot_"))
	var r2 := HBoxContainer.new()
	move_btn = _btn("Move", "asm_mode_move", "The arrows on the part slide it", func(): _set_mode("move"), true)
	turn_btn = _btn("Turn", "asm_mode_turn", "The arrows on the part turn it", func(): _set_mode("turn"), true)
	edit_btn = _btn("Edit part", "asm_edit", "Open this part to change it; Back to the assembly brings the change here", func(): edit_part(sel))
	remove_btn = _btn("Remove", "asm_remove", "Take this part out of the assembly", func(): remove_sel())
	for b in [move_btn, turn_btn, edit_btn, remove_btn]:
		(b as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r2.add_child(b)
	vb.add_child(r2)
	vb.add_child(_lbl("Freedom left (tick = locked)", 12, "asm_dof_title"))
	for kind in ["pos", "rot"]:
		var rr := HBoxContainer.new()
		rr.add_child(_lbl("Slide" if kind == "pos" else "Turn", 12))
		for i in 3:
			var cb := CheckBox.new()
			cb.name = "asm_lock_%s_%d" % [kind, i]
			cb.text = AssemblyDof.PN[i]
			cb.focus_mode = Control.FOCUS_NONE
			cb.tooltip_text = "Lock this one: typing and dragging cannot change it"
			cb.toggled.connect(func(v: bool): _lock_changed(kind, i, v))
			(lock_pos if kind == "pos" else lock_rot).append(cb)
			rr.add_child(cb)
		if kind == "rot":
			fix_btn = _btn("Fix", "asm_fix", "Lock all six, or free them all again", func(): _fix_toggle())
			rr.add_child(fix_btn)
		vb.add_child(rr)
	dof_l = _lbl("", 12, "asm_dof")
	dof_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dof_l.custom_minimum_size = Vector2(PANEL_W - 24.0, 0)
	vb.add_child(dof_l)
	var r3 := HBoxContainer.new()
	stl_btn = _btn("STL", "asm_export_stl", "One .stl with every part, in place", func(): export("stl"))
	glb_btn = _btn("GLB", "asm_export_glb", "One .glb, a node for each part", func(): export("glb"))
	step_btn = _btn("STEP", "asm_export_step", "One .step with the exact solids of every part", func(): export("step"))
	video_btn = _btn("Video", "asm_export_video", "Film the animation (Check motion > Timeline): PNG frames, a contact sheet and an .mp4, seen from the way you look at it now", export_video)
	done_btn = _btn("Done", "asm_done", "Leave the assembly (save it first)", close)
	r3.add_child(_lbl("Export", 13))
	for b in [stl_btn, glb_btn, step_btn, video_btn, done_btn]:
		(b as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r3.add_child(b)
	vb.add_child(r3)
	var r4 := HBoxContainer.new()
	drawing_btn = _btn("Drawing", "asm_export_drawing", "Plan / front / SectionLook section from the exact CAD solids, with model dimensions, part labels, SVG and PNG", func(): export_sheet("drawing"))
	schematic_btn = _btn("Schematic", "asm_export_schematic", "Rated blocks and power / signal wires from this Assembly record, with connection and rating checks, SVG and PNG", func(): export_sheet("schematic"))
	r4.add_child(_lbl("Sheets", 13))
	for b in [drawing_btn, schematic_btn]:
		(b as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r4.add_child(b)
	vb.add_child(r4)
	status_l = _lbl("", 12, "asm_status")
	status_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_l.custom_minimum_size = Vector2(PANEL_W - 24.0, 0)
	vb.add_child(status_l)
	m.ui_root.add_child(panel)


func _row_fields(title: String, names: Array, store: Array, prefix: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.add_child(_lbl(title, 12))
	var h := HBoxContainer.new()
	for i in names.size():
		var l := _lbl(String(names[i]), 13)
		h.add_child(l)
		var e := _edit(prefix + String(names[i]).to_lower(), 50)
		e.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		e.text_submitted.connect(func(_t): e.release_focus(); _apply_fields())
		e.focus_exited.connect(_apply_fields)
		h.add_child(e)
		store.append(e)
	v.add_child(h)
	return v


## the three source tabs' hover hints (C71: the tab had none, so hovering "Library" said nothing; s213 722cdf50)
const SRC_TIPS := {"library": "Library: ready-made parts (screws, boards, pipes, gears and more); click one to put it in", "mine": "My parts: the parts you built and saved; click one to put it in", "asm": "Assemblies: the assemblies you saved; click one to put it in as one piece"}


func _build_src() -> void:
	src_panel = PanelContainer.new()
	src_panel.name = "asm_src_panel"
	src_panel.visible = false
	src_panel.add_theme_stylebox_override("panel", psb_of())
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	src_panel.add_child(vb)
	vb.add_child(_lbl("PUT A PART IN", 15, "asm_src_title"))
	var h := HBoxContainer.new()
	for t in [["library", "Library"], ["mine", "My parts"], ["asm", "Assemblies"]]:
		var b := _btn(String(t[1]), "asm_tab_" + String(t[0]), String(SRC_TIPS[String(t[0])]), func(): _set_tab(String(t[0])), true)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(b)
		src_tabs[String(t[0])] = b
	vb.add_child(h)
	var sc := ScrollContainer.new()
	sc.name = "asm_src_scroll"
	sc.custom_minimum_size = Vector2(SRC_W - 12.0, 330)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	src_vb = VBoxContainer.new()
	src_vb.name = "asm_src_list"
	src_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(src_vb)
	vb.add_child(sc)
	m.ui_root.add_child(src_panel)


func _build_back() -> void:
	back_panel = PanelContainer.new()
	back_panel.name = "asm_back_panel"
	back_panel.visible = false
	var h := HBoxContainer.new()
	back_panel.add_child(h)
	back_btn = _btn("Back to the
assembly", "asm_back", "Bring the changes into the assembly", back_to_assembly)
	h.add_child(back_btn)
	m.ui_root.add_child(back_panel)


# ---------------------------------------------------------------- open / close

## "New assembly": the BUILD page shows the empty assembly
func open_new() -> void:
	asm = Assembly.make(Assembly.free_file_name("Assembly"))
	sel = ""
	_begin()


## the assembly on screen is this record (Open)
func open_record(rec: Dictionary) -> void:
	asm = rec.duplicate(true)
	sel = ""
	if not (asm["parts"] as Array).is_empty():
		sel = String((asm["parts"][0] as Dictionary)["id"])
	_begin()


func _begin() -> void:
	asm_undo.clear()
	asm_redo.clear()
	motion.reset(true)
	bom.close()
	stages.close()
	var pu: PartUI = bu.part
	if not _had_stash and editing == "":
		_stash = m.S.part
		_had_stash = true
	pu.asm_on = true
	on = true
	if not pu.on:
		pu.set_on(true)
	else:
		bu.sync()
	panel.visible = true
	ov.visible = true
	root3.visible = true
	back_panel.visible = false
	editing = ""
	mode = "move"
	src_open = false
	_refresh(true)
	_layout()
	_frame()
	m._fit_top.call_deferred()
	_say("ASSEMBLY: Add part puts a part in; drag the arrows or type numbers to place it")


func close() -> void:
	if not on and editing == "":
		return
	var pu: PartUI = bu.part
	on = false
	editing = ""
	pu.asm_on = false
	motion.reset(true)
	bom.close()
	stages.close()
	panel.visible = false
	src_panel.visible = false
	back_panel.visible = false
	ov.visible = false
	root3.visible = false
	src_open = false
	if _had_stash:
		m.S.part = _stash
		_had_stash = false
		_stash = {}
	pu._rec_sig = ""
	if pu.on:
		pu.set_on(false)
	bu.sync()
	m._fit_top.call_deferred()


func _say(t: String) -> void:
	status_text = t
	if status_l != null:
		status_l.text = t
	m._say(t)


func _process(dt: float) -> void:
	if on and not bu.part.on:
		close()
		return
	if editing != "":
		_t += dt
		if _t > 0.3:
			_t = 0.0
			_pull_edits()
	if on:
		motion.tick(dt)   # G7TIME: Play
		stages.tick(dt)   # G33STAGE: Play the build
		_layout()
		ov.queue_redraw()


func _layout() -> void:
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var cl: Rect2 = m.nav_clear_rect()
	panel.reset_size()
	panel.position = Vector2(cl.end.x - PANEL_W - 48.0, cl.position.y + 4.0)
	panel.custom_minimum_size.x = PANEL_W
	panel.size.x = PANEL_W
	src_panel.reset_size()
	src_panel.position = Vector2(cl.position.x + 8.0, cl.position.y + 4.0)
	src_panel.size.x = SRC_W
	motion.layout(Vector2(cl.position.x + 8.0, cl.position.y + 4.0))
	bom.layout(Vector2(cl.position.x + 8.0, cl.position.y + 4.0))
	stages.layout(Vector2(cl.position.x + 8.0, cl.position.y + 4.0))
	var bw := back_panel.get_combined_minimum_size().x
	back_panel.reset_size()
	back_panel.position = Vector2(vs.x - bw - 4.0, vs.y * 0.42)   # the right edge under the view cube: the one strip both Easy Part and Expert leave free


# ---------------------------------------------------------------- the parts

func _sel_part() -> Dictionary:
	var i := Assembly.index_of(asm, sel)
	return asm["parts"][i] if i >= 0 else {}


func _toggle_src() -> void:
	src_open = add_btn.button_pressed
	if src_open:
		bom.close()
		stages.close()
		_set_tab(src_tab)
	_sync_src()


func _open_list() -> void:
	src_open = true
	add_btn.set_pressed_no_signal(true)
	_set_tab("asm")


func _set_tab(t: String) -> void:
	src_tab = t
	for k in src_tabs:
		(src_tabs[k] as Button).set_pressed_no_signal(k == t)
	_fill_src()
	_sync_src()


func _sync_src() -> void:
	src_panel.visible = on and src_open
	add_btn.set_pressed_no_signal(src_open)


func _fill_src() -> void:
	for c in src_vb.get_children():
		src_vb.remove_child(c)
		c.queue_free()
	if src_tab == "library":
		var cat := ""
		for e in PartCatalog.ENTRIES:
			if String(e[2]) != cat:
				cat = String(e[2])
				src_vb.add_child(_lbl(cat, 12))
			var b := _btn(String(e[1]), "asm_src_lib_" + String(e[0]), "Put %s in the assembly" % String(e[1]), add_library.bind(String(e[0])))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			src_vb.add_child(b)
	elif src_tab == "mine":
		var mine := MyParts.list()
		if mine.is_empty():
			var l := _lbl("No saved parts yet. Make a part, press Use in a scene, and it is listed here.", 12, "asm_src_empty")
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = SRC_W - 30.0
			src_vb.add_child(l)
		for e in mine:
			var b := _btn(String(e["name"]), "asm_src_mine_" + MyParts.file_stem(String(e["name"])), "Put your part %s in the assembly" % String(e["name"]), add_mine.bind(String(e["name"])))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			src_vb.add_child(b)
	else:
		var sv := Assembly.list()
		if sv.is_empty():
			var l := _lbl("No saved assemblies yet. Save one and it is listed here.", 12, "asm_src_empty")
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = SRC_W - 30.0
			src_vb.add_child(l)
		for e in sv:
			var b := _btn("%s  (%d parts)" % [String(e["name"]), int(e["parts"])], "asm_src_asm_" + MyParts.file_stem(String(e["name"])), "Open the assembly %s" % String(e["name"]), open_saved.bind(String(e["path"])))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			src_vb.add_child(b)


func add_library(id: String) -> void:
	var rec := PartCatalog.make(id)
	var e := PartCatalog.entry(id)
	_add(rec, String(e[1]) if not e.is_empty() else "Part", "library:" + id)


func add_mine(nm: String) -> void:
	var rec := MyParts.load_part(nm)
	_add(rec, nm, "mine:" + nm)


func _add(rec: Dictionary, nm: String, src: String) -> void:
	if rec.is_empty():
		_say("That part could not be opened")
		return
	var id := Assembly.add_part(asm, rec, nm, src)
	if id == "":
		_say("%s has no solid yet, so it cannot be put in. Finish the part first" % nm)
		return
	sel = id
	_refresh(true)
	_frame()
	_say("%s is in the assembly (%d parts). Drag its arrows or type numbers to place it" % [String(_sel_part()["name"]), (asm["parts"] as Array).size()])


func open_saved(path: String) -> void:
	var rec := Assembly.read(path)
	if rec.is_empty():
		_say("That assembly file could not be read")
		return
	open_record(rec)
	src_open = false
	_sync_src()
	_say("Opened %s: %d parts" % [String(asm["name"]), (asm["parts"] as Array).size()])


func select(id: String) -> void:
	sel = id
	_refresh(false)
	stages.refresh()
	var p := _sel_part()
	if not p.is_empty():
		_say("%s is at %s mm" % [String(p["name"]), _pos_words(p)])


func remove_sel() -> void:
	if sel == "":
		return
	var nm := String(_sel_part().get("name", ""))
	Assembly.remove_part(asm, sel)
	if AssemblyStage.stage_of(asm, sel) >= 0:   # G33STAGE: a part taken out leaves its stage too
		AssemblyStage.remove_part(asm, sel)
	sel = ""
	var ps: Array = asm["parts"]
	if not ps.is_empty():
		sel = String((ps[ps.size() - 1] as Dictionary)["id"])
	_refresh(true)
	_say("%s is out of the assembly" % nm)


func _rename_asm(t: String) -> void:
	if t.strip_edges() != "" and t.strip_edges() != String(asm["name"]):
		asm["name"] = t.strip_edges()


func _rename_part(t: String) -> void:
	var p := _sel_part()
	if p.is_empty() or t.strip_edges() == "" or t.strip_edges() == String(p["name"]):
		return
	p["name"] = t.strip_edges()
	_refresh(false)


func _set_mode(md: String) -> void:
	mode = md
	move_btn.set_pressed_no_signal(md == "move")
	turn_btn.set_pressed_no_signal(md == "turn")
	ov.queue_redraw()


func _apply_fields() -> void:
	var p := _sel_part()
	if p.is_empty():
		return
	var pos := Vector3.ZERO
	var rot := Vector3.ZERO
	for i in 3:
		pos[i] = _num((pos_edits[i] as LineEdit).text, float(p["pos"][i]))
		rot[i] = _num((rot_edits[i] as LineEdit).text, float(p["rot"][i]))
	var pos0: Array = p["pos"].duplicate()
	var rot0: Array = p["rot"].duplicate()
	Assembly.set_pose(p, pos, rot)
	AssemblyDof.enforce(p, pos0, rot0)   # C15: a locked axis keeps its value
	_refresh(false)
	_say("%s is at %s mm" % [String(p["name"]), _pos_words(p)])


func _num(t: String, fallback: float) -> float:
	var s := t.strip_edges()
	return float(s) if s.is_valid_float() else fallback


# ---------------------------------------------------------------- the view

func _refresh(reframe: bool) -> void:
	var ps: Array = asm["parts"]
	var keep := {}
	for p in ps:
		var id := String(p["id"])
		keep[id] = true
		var mi: MeshInstance3D = meshes.get(id)
		if mi == null:
			mi = MeshInstance3D.new()
			mi.name = "asm_mesh_" + id
			root3.add_child(mi)
			meshes[id] = mi
		mi.mesh = Assembly.built(p["rec"])["mesh"]
		mi.transform = motion.xf_of(p)   # G1MOTION: the scrubbed drive's pose (the record's pose when no drive is scrubbed)
		mi.visible = true
		var ovl := motion.overlay_of(id)
		mi.material_overlay = ovl if ovl != null else stages.overlay_of(id)   # G33STAGE: red over the parts the stage Check flagged
	for id in meshes.keys():
		if not keep.has(id):
			(meshes[id] as Node).queue_free()
			meshes.erase(id)
	stages.apply(meshes)   # G33STAGE: the build at the stage panel's time
	_list_sync()
	_fields_sync()
	_dof_sync()
	name_edit.text = String(asm["name"]) if not name_edit.has_focus() else name_edit.text
	edit_btn.disabled = sel == ""
	remove_btn.disabled = sel == ""
	_set_mode(mode)
	if ov != null:
		ov.queue_redraw()


func _list_sync() -> void:
	for c in list_vb.get_children():
		list_vb.remove_child(c)
		c.queue_free()
	var ps: Array = asm["parts"]
	if ps.is_empty():
		var l := _lbl("Nothing yet: press Add part.", 12, "asm_empty")
		list_vb.add_child(l)
	for i in ps.size():
		var p: Dictionary = ps[i]
		var b := Button.new()
		b.name = "asm_row_%d" % i
		b.text = String(p["name"])
		b.tooltip_text = AssemblyDof.words(p) + "\nDouble-click to edit this part"
		b.add_theme_color_override("font_color", AssemblyDof.colour(p))
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 13)
		b.set_pressed_no_signal(String(p["id"]) == sel)
		var id := String(p["id"])
		b.pressed.connect(select.bind(id))
		b.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).double_click and (ev as InputEventMouseButton).pressed:
				sel = id
				edit_part(id))
		list_vb.add_child(b)


func _lock_changed(kind: String, i: int, v: bool) -> void:
	var p := _sel_part()
	if p.is_empty() or AssemblyDof.is_locked(p, kind, i) == v:
		return
	AssemblyDof.set_lock(p, kind, i, v)
	_refresh(false)


func _fix_toggle() -> void:
	var p := _sel_part()
	if p.is_empty():
		return
	AssemblyDof.lock_all(p, AssemblyDof.free_count(p) > 0)
	_refresh(false)


func _dof_sync() -> void:
	var p := _sel_part()
	for kind in ["pos", "rot"]:
		for i in 3:
			var cb: CheckBox = (lock_pos if kind == "pos" else lock_rot)[i]
			cb.disabled = p.is_empty()
			cb.set_pressed_no_signal(not p.is_empty() and AssemblyDof.is_locked(p, kind, i))
	fix_btn.disabled = p.is_empty()
	dof_l.text = "" if p.is_empty() else AssemblyDof.words(p)
	if not p.is_empty():
		dof_l.add_theme_color_override("font_color", AssemblyDof.colour(p))


func _fields_sync() -> void:
	var p := _sel_part()
	part_name.editable = not p.is_empty()
	for i in 3:
		(pos_edits[i] as LineEdit).editable = not p.is_empty()
		(rot_edits[i] as LineEdit).editable = not p.is_empty()
		if p.is_empty():
			(pos_edits[i] as LineEdit).text = ""
			(rot_edits[i] as LineEdit).text = ""
		else:
			if not (pos_edits[i] as LineEdit).has_focus():
				(pos_edits[i] as LineEdit).text = _fmt(float(p["pos"][i]))
			if not (rot_edits[i] as LineEdit).has_focus():
				(rot_edits[i] as LineEdit).text = _fmt(float(p["rot"][i]))
	if not part_name.has_focus():
		part_name.text = String(p.get("name", ""))


func _fmt(v: float) -> String:
	return String.num(v, 2).rstrip("0").rstrip(".") if absf(v - roundf(v)) > 1e-6 else str(int(roundf(v)))


func _frame() -> void:
	var bb := Assembly.total_aabb(asm)
	if bb.size.length() < 1e-4:
		m._turn_to(30.0, -22.0, 0.9, Vector3(0.1, 0.0, 0.0), false)
	else:
		var dist := clampf(bb.size.length() * 1.6, 0.4, 6.0)
		m._turn_to(30.0, -22.0, dist, bb.get_center(), false)
		if m.cam != null:   # the right panel covers a third of the view: the assembly sits in the free part, left of it (Check motion's panel covers the left too: nearer the middle)
			var right: Vector3 = m.cam.global_transform.basis.x
			m._turn_to(30.0, -22.0, dist, bb.get_center() + right * dist * (0.08 if (motion.is_open() or stages.is_open() or bom.is_open()) else 0.24), false)


# ---------------------------------------------------------------- the gizmo

func _px_per_m(c: Vector3) -> float:
	var right: Vector3 = m.cam.global_transform.basis.x
	return (m.cam.unproject_position(c + right * 0.1) - m.cam.unproject_position(c)).length() / 0.1


## the three handles of the selected part: [{"axis", "p0", "p1" (screen), "dir" (unit, screen), "len" (m)}]
func handles() -> Array:
	var p := _sel_part()
	var out: Array = []
	if p.is_empty() or m.cam == null or motion.scrubbing():
		return out
	var c: Vector3 = Assembly.xf_of(p).origin
	if m.cam.is_position_behind(c):
		return out
	var pxm := _px_per_m(c)
	if pxm < 1e-3:
		return out
	var L := HANDLE_PX / pxm
	var p0: Vector2 = m.cam.unproject_position(c)
	for i in 3:
		var tip: Vector3 = c + (AXES[i] as Vector3) * L
		var p1: Vector2 = m.cam.unproject_position(tip)
		var d := p1 - p0
		out.append({"axis": i, "p0": p0, "p1": p1, "dir": d.normalized() if d.length() > 1e-3 else Vector2.RIGHT, "len": L, "pxm": pxm})
	return out


func _draw() -> void:
	if not on:
		return
	var f := ThemeDB.fallback_font
	var placed: Array = []       # label declutter: boxes always draw, overlapping names are skipped (the selected part's name always draws)
	var sel_label := {}
	var pending: Array = []
	for p in asm["parts"]:
		var id := String(p["id"])
		var bb := Assembly.world_aabb(p)
		if motion.scrubbing():
			bb = motion.xf_of(p) * (Assembly.built(p["rec"])["aabb"] as AABB)
		if bb.size == Vector3.ZERO:
			continue
		var mn := Vector2(1e9, 1e9)
		var mx := Vector2(-1e9, -1e9)
		var okp := true
		for k in 8:
			var corner := bb.get_endpoint(k)
			if m.cam.is_position_behind(corner):
				okp = false
				break
			var s: Vector2 = m.cam.unproject_position(corner)
			mn = mn.min(s)
			mx = mx.max(s)
		if not okp:
			continue
		var is_sel := id == sel
		ov.draw_rect(Rect2(mn - Vector2(3, 3), mx - mn + Vector2(6, 6)), Color(1.0, 0.78, 0.22, 0.95) if is_sel else Color(1, 1, 1, 0.25), false, 2.0 if is_sel else 1.0)
		var lp := Vector2(mn.x, mn.y - 7.0)
		if is_sel:
			sel_label = {"p": lp, "name": String(p["name"])}
			placed.append(Rect2(lp - Vector2(0, 13), Vector2(f.get_string_size(String(p["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, 16)))
			continue
		var lr := Rect2(lp - Vector2(0, 13), Vector2(f.get_string_size(String(p["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, 16))
		pending.append({"p": lp, "name": String(p["name"]), "r": lr})
	if not sel_label.is_empty():
		ov.draw_string(f, sel_label["p"], String(sel_label["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.85, 0.4))
	for c in pending:
		var clash := false
		for r in placed:
			if (r as Rect2).intersects(c["r"] as Rect2):
				clash = true
				break
		if not clash:
			ov.draw_string(f, c["p"], String(c["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.6))
			placed.append(c["r"])
	for h in handles():
		var i := int(h["axis"])
		var col: Color = AX_COL[i]
		ov.draw_line(h["p0"], h["p1"], col, 3.0)
		var tip: Vector2 = h["p1"]
		if mode == "move":
			var d: Vector2 = h["dir"]
			var n := Vector2(-d.y, d.x)
			ov.draw_colored_polygon(PackedVector2Array([tip + d * 12.0, tip - d * 4.0 + n * 7.0, tip - d * 4.0 - n * 7.0]), col)
		else:
			ov.draw_circle(tip, 8.0, col)
			ov.draw_arc(tip, 12.0, 0.0, TAU, 20, col, 2.0)
		ov.draw_string(f, tip + Vector2(8, -8), AX_NAME[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)


func _over_ui() -> bool:
	var hov: Control = m.get_viewport().gui_get_hovered_control()
	return hov != null and hov != ov and not (hov.name == "ui_root")


func _input(ev: InputEvent) -> void:
	if not on:
		return
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var e := ev as InputEventMouseButton
		if e.pressed:
			if _over_ui():
				return
			for h in handles():
				if e.position.distance_to(h["p1"]) <= HIT_PX:
					var p := _sel_part()
					drag = {"axis": int(h["axis"]), "start": e.position, "pos": Vector3(float(p["pos"][0]), float(p["pos"][1]), float(p["pos"][2])), "rot": p["rot"].duplicate(),
						"p0": h["p0"], "dir": h["dir"], "len": float(h["len"]), "pxm": float(h["pxm"]), "dist": (h["p1"] as Vector2).distance_to(h["p0"])}
					m.get_viewport().set_input_as_handled()
					return
			var hit := _pick(e.position)
			if hit != "":
				sel = hit
				_refresh(false)
				if e.double_click:
					edit_part(hit)
				m.get_viewport().set_input_as_handled()
		elif not drag.is_empty():
			drag = {}
			_say("%s is at %s mm" % [String(_sel_part().get("name", "")), _pos_words(_sel_part())])
			m.get_viewport().set_input_as_handled()
	elif ev is InputEventMouseMotion and not drag.is_empty():
		var mv := ev as InputEventMouseMotion
		var p := _sel_part()
		if p.is_empty():
			drag = {}
			return
		var delta: Vector2 = mv.position - (drag["start"] as Vector2)
		var ax: int = int(drag["axis"])
		var pos0: Array = p["pos"].duplicate()
		var rot0: Array = p["rot"].duplicate()
		if mode == "move":
			var along := delta.dot(drag["dir"] as Vector2)
			var mm := snappedf(along / maxf(float(drag["dist"]), 1.0) * float(drag["len"]) * 1000.0, 0.5)
			var np: Vector3 = (drag["pos"] as Vector3) + (AXES[ax] as Vector3) * mm
			Assembly.set_pose(p, np, Vector3(float(p["rot"][0]), float(p["rot"][1]), float(p["rot"][2])))
		else:
			var dir: Vector2 = drag["dir"]
			var deg := snappedf(delta.dot(Vector2(-dir.y, dir.x)) * 0.5, 1.0)
			p["rot"] = (drag["rot"] as Array).duplicate()
			Assembly.turn_about(p, AXES[ax], deg)
			rot0 = (drag["rot"] as Array).duplicate()
		AssemblyDof.enforce(p, pos0, rot0)   # C15: locked axes stay
		_refresh(false)
		m.get_viewport().set_input_as_handled()


func _pos_words(p: Dictionary) -> String:
	if p.is_empty():
		return ""
	return "%s, %s, %s" % [_fmt(float(p["pos"][0])), _fmt(float(p["pos"][1])), _fmt(float(p["pos"][2]))]


## the part under the pointer (the nearest box the ray goes through), "" for none
func _pick(at: Vector2) -> String:
	if m.cam == null:
		return ""
	var from: Vector3 = m.cam.project_ray_origin(at)
	var dir: Vector3 = m.cam.project_ray_normal(at)
	var best := ""
	var bd := INF
	for p in asm["parts"]:
		var hit = Assembly.world_aabb(p).intersects_ray(from, dir)
		if hit != null:
			var d := from.distance_to(hit)
			if d < bd:
				bd = d
				best = String(p["id"])
	return best


# ---------------------------------------------------------------- editing a part

func edit_part(id: String) -> void:
	var i := Assembly.index_of(asm, id)
	if i < 0 or editing != "":
		return
	var pu: PartUI = bu.part
	editing = id
	on = false
	pu.asm_on = false
	bom.close()
	stages.close()
	panel.visible = false
	src_panel.visible = false
	ov.visible = false
	root3.visible = false
	m.S.part = (asm["parts"][i]["rec"] as Dictionary).duplicate(true)
	pu.upto = -1
	pu._rec_sig = ""
	pu.sync()
	pu._view_model()
	_rec_sig = JSON.stringify(m.S.part)
	back_panel.visible = true
	_layout()
	_say("Editing %s. Back to the assembly brings your changes into it" % String(asm["parts"][i]["name"]))


## the open part's edits go into the assembly's copy
func _pull_edits() -> void:
	var i := Assembly.index_of(asm, editing)
	if i < 0:
		return
	var s := JSON.stringify(m.S.part)
	if s != _rec_sig and not (m.S.part as Dictionary).is_empty():
		_rec_sig = s
		asm["parts"][i]["rec"] = (m.S.part as Dictionary).duplicate(true)


func back_to_assembly() -> void:
	if editing == "":
		return
	var pu: PartUI = bu.part
	if pu.sk != "":
		pu.finish_sketch()
	if pu.ep != null and pu.easy:
		pu.easy = false
	_pull_edits()
	var nm := String(_sel_part().get("name", ""))
	editing = ""
	back_panel.visible = false
	pu.asm_on = true
	on = true
	pu.easy = false
	panel.visible = true
	ov.visible = true
	root3.visible = true
	pu._rec_sig = ""
	pu.sync()
	bu.sync()
	m._fit_top.call_deferred()
	_refresh(false)
	_sync_src()
	_say("Back in the assembly: %s has your changes" % nm)


# ---------------------------------------------------------------- files

func _save() -> void:
	if (asm["parts"] as Array).is_empty():
		_say("Put a part in first, then save")
		return
	_rename_asm(name_edit.text)
	if editing != "":
		_pull_edits()
	var path := Assembly.save(asm)
	_say("Saved %s" % path.get_file() if path != "" else "NOT DONE: the file could not be written. Check the disk has room")


func _new() -> void:
	open_new()


func export(fmt: String) -> Dictionary:
	if editing != "":
		_pull_edits()
	var r: Dictionary
	match fmt:
		"stl":
			r = Assembly.export_mesh(asm, "stl")
		"glb":
			r = Assembly.export_glb(asm)
		_:
			r = Assembly.export_step(asm)
	last_export = r
	_say(String(r["text"]))
	return r


## G30/G31: the Assembly itself as a titled SVG + PNG sheet. Drawing dimensions come from exact solids; schematic ratings/wires
## are optional record fields, so exporting never changes an old record.
func export_sheet(kind := "drawing", opts := {}) -> Dictionary:
	if sheet_exporting:
		return {}
	if editing != "":
		_pull_edits()
	sheet_exporting = true
	drawing_btn.disabled = true
	schematic_btn.disabled = true
	_say("Making the %s sheet..." % kind)
	var r: Dictionary = await AssemblyDraw.write(m, asm, kind, opts)
	sheet_exporting = false
	drawing_btn.disabled = false
	schematic_btn.disabled = false
	last_export = r
	_say(String(r["text"]))
	return r


## G7TIME: the animation filmed into <exports>/<name>_motion_<stamp>/: frame_0000.png ..., sheet.png and <name>.mp4 (when ffmpeg is found).
## The camera looks the way the view does now, framed on the box the parts sweep through. opts go to AssemblyRender.render
func export_video(opts := {}) -> Dictionary:
	if filming:
		return {}
	if editing != "":
		_pull_edits()
	if not AssemblyAnim.has_anim(asm):
		_say("Nothing to film: key a drive first (Check motion > Timeline: set the drive, pick a time, press Key)")
		return {}
	var o := {"width": 1280, "height": 720}
	if m.cam != null:
		o["view_dir"] = (m.cam.global_transform.basis.z as Vector3)
	o.merge(opts, true)
	filming = true
	video_btn.disabled = true
	_say("Filming %d frames..." % AssemblyAnim.frame_count(asm))
	var r: Dictionary = await AssemblyRender.render(m, asm, o)
	filming = false
	video_btn.disabled = false
	r["text"] = ("Filmed %d frames to %s: sheet.png%s" % [int(r["n"]), String(r["dir"]).get_file(), ", " + String(r["mp4"]).get_file() if String(r["mp4"]) != "" else " (no .mp4: ffmpeg was not found; install it with winget install Gyan.FFmpeg)"]) if bool(r["ok"]) else "NOT DONE: " + String(r["why"])
	last_export = r
	_say(String(r["text"]))
	return r


# ---------------------------------------------------------------- undo (G1MOTION)

## before a change to the record: ONE step that Ctrl+Z takes back (main._mesh_undo asks undo_redo first while the screen is on)
func push_undo(label: String) -> void:
	asm_undo.append({"asm": asm.duplicate(true), "label": label})
	asm_redo.clear()


## Ctrl+Z (back) / Ctrl+Y: false when this screen has no step, so the scene's own undo runs as before
func undo_redo(back: bool) -> bool:
	var from: Array = asm_undo if back else asm_redo
	if not on or from.is_empty():
		return false
	var s: Dictionary = from.pop_back()
	(asm_redo if back else asm_undo).append({"asm": asm.duplicate(true), "label": s["label"]})
	asm = s["asm"]
	if Assembly.index_of(asm, sel) < 0:
		sel = String((asm["parts"][0] as Dictionary)["id"]) if not (asm["parts"] as Array).is_empty() else ""
	motion.reset(false)
	stages._clear_check()
	_refresh(false)
	bom.refresh()
	stages.refresh()
	_say("%s: %s" % ["Undone" if back else "Redone", String(s["label"])])
	return true


func psb_of() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.14, 0.97)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	return sb
