class_name BuildUI
extends Node
## THE BUILD PAGE (docs/BUILD_PLAN.md phase 1b): the page of a "building" project. A 0.5 m grid on the floor, a ghost person for
## scale, and the first tools:
##   ROOM     press on the floor = corner A, drag = a live box with "4.0 m x 3.0 m" labels, let go = the room. While dragging,
##            type the sizes: 4 Tab 3 Enter. Esc cancels. Drags snap to the grid (0.5 m; Alt = free, the Snap chip turns it off)
##   OPENING  click a wall = a door (the Door / Window toggle in the panel picks the kind); press an opening and drag along its
##            wall = slide it (snaps to 0.5 m); Delete (or the panel's Remove) takes it out and the wall fills
## The panel on the right edits the NAMED NUMBERS of the building (Wall height ...): one undo step per committed number.
##   WALL     drag inside a room: an interior wall across it (snaps to 0.5 m; a click splits the room's long side); openings go in it too
##   PULL     drag a room's outer wall face in or out: the room resizes (snaps to 0.5 m, a live label); openings keep their offset
##            from the wall's middle
##   FLOOR    "+ Floor" in the panel adds a storey on top (same footprint, a floor slab between; floor_height 2.8 m); the panel lists them
##   ROOF     gable / flat / shed (the panel; a click in the view adds the gable), overhang a number: a closed solid on the top floor
##   USE IN A SCENE (top right): the house becomes a set on STAGE (BuildStage: collision from the record, the doorway open, a named point
##            per door); STAGE shows its panel with "Walk through the front door" and Edit in BUILD
##   PIECE    a picker of big icon cards on the left (Stairs: straight, L; Furniture; Fight blocks), then a click inside a room places it (centre on
##            the 0.5 m grid, kept inside the room's walls); a click on a piece selects it: its named numbers, the round Rotate arrow (90 deg),
##            Remove (or Delete). Stairs follow floor_height, cut the floor above and are a ramp for the fighter (scripts/build/build_pieces.gd)
## The record (Scene.building, scripts/build/building.gd) is the only truth; the mesh here is regenerated from it after every
## change. WORDS (phase 1e, build_words.gd + build_words_ui.gd) is a tool: a sentence -> a plan -> Build it. Undo: ONE main._push_undo()
## per action, taken BEFORE the record changes (a room: on release; a door: on the click; a slide: on its first move).

const SKY := Color("#73BFFF")
const PANEL_W := 250.0
const ROWS := [["Wall height", "wall_height"], ["Wall thickness", "wall_thickness"], ["Door width", "door_width"],
	["Door height", "door_height"], ["Window sill", "window_sill"]]
const TOOLS := [["Room", "ROOM: drag on the floor. Sizes snap to 0.5 m; type them for exact (4, Tab, 3, Enter). Let go to raise the walls and a floor. Undo takes it back."],
	["Wall", "WALL: drag inside a room to put a wall across it (snaps to 0.5 m); a click splits the long side. Doors and windows go in it like any wall."],
	["Pull", "PULL: drag a room's outer wall in or out to resize the room (snaps to 0.5 m). Doors keep their place from the wall's middle."],
	["Opening", "OPENING: click a wall to add a door. Drag it along the wall (snaps to 0.5 m). The Remove button takes it out and fills the hole."],
	["Floor", "FLOOR: + Floor in the panel adds a floor on top, the same footprint with a floor slab between. Delete takes the top floor off."],
	["Roof", "ROOF: pick gable, flat or shed in the panel (a click in the view adds a gable). The overhang is a number."],
	["Piece", "PIECE: pick a card on the left, then click inside a room to put it there (snaps to 0.5 m). Click a piece to change its numbers, turn it or remove it."]]
const LATER := []
const WORDS_TIP := "WORDS: type a building, check the plan, press Build it. The result is normal rooms and openings. Then say changes: move the door to the left."
const EXTRA_ROWS := [["Floor height", "floor_height"], ["Roof overhang", "roof_overhang"]]
const LABELS := {"wall_height": "Wall height", "wall_thickness": "Wall thickness", "door_width": "Door width", "door_height": "Door height",
	"window_sill": "Window sill", "floor_height": "Floor height", "roof_overhang": "Roof overhang"}
const MIN_SIDE := 0.4   # m: an interior wall keeps at least this much room on each side
const FLOOR_HINT := "Drag on the floor to make a room"
## the house: ONE mesh (walls and the floor slab), two colours by height: the floor (at or below y = 0) is dark graphite and the walls
## are light clay, so the room reads as walls standing on a floor. Lit from above and the side, so every wall face reads
const HOUSE_SHADER := preload("res://scripts/build/house.gdshader")
const VIEW_YAW := 208.0   # the default view: three quarters, from the front-left (the front wall is the near one), a little above
const VIEW_PITCH := -50.0
const VIEW_DIST := 14.0
const VIEW_AT := Vector3(0.9, 0.9, 1.0)
const HALF := 12.0   # the grid reaches this far from the origin

var m: Node
var on := false                # the BUILD page is the page
var tool := "Room"
var kind := "door"             # what the Opening tool adds
var snap_on := true
var sel := ""                  # the selected opening's id
var size_text := ""            # the live label of the drag ("4.0 m x 3.0 m"), "" when not dragging
var area_text := ""
var drag := ""                 # "", "room", "slide", "wall", "pull"
var a := Vector3.ZERO          # the room drag's corner A and the moving corner B (floor, snapped)
var b := Vector3.ZERO
var typed := ["", ""]          # typed width / depth while dragging
var field := 0
var _slide_moved := false
var _hover := {}               # the opening tool's hover: {"room", "wall", "at"} or {}
var _wall_room := ""           # the room a wall drag started in
var _pull := {}                # a pull drag: {"room", "wall", "y", "g0", "orig", "walls", "moved", "text"}
var floor_box: VBoxContainer
var roof_box: VBoxContainer
var wall_box: VBoxContainer
var floors_label: Label
var roof_btns := {}
var stage_panel: PanelContainer
var stage_body: VBoxContainer
var walk_btns := {}
var piece_kind := ""           # the picker's card in hand ("" = none)
var piece_floor := 0           # the floor (index) a piece is placed on
var psel := ""                 # the selected piece's id
var picker: PanelContainer
var card_btns := {}
var floor_chips: HBoxContainer
var piece_box: VBoxContainer
var piece_rows: VBoxContainer
var piece_hint: Label
var piece_info: Label
var piece_rotate_btn: Button
var piece_flip_btn: Button
var piece_remove_btn: Button
var piece_fields := {}         # param key -> LineEdit
var _piece_sig := ""
var num_rows: Array = []       # the building's number rows (hidden while Piece is the tool)

var root3: Node3D              # everything 3D that is BUILD's own (grid, ghost person, the house, its highlights)
var house: MeshInstance3D
var grid: MeshInstance3D
var person: Node3D
var ghost_room: MeshInstance3D
var sel_box: MeshInstance3D
var hover_box: MeshInstance3D
var ov: Control                # the labels over the view
var panel: PanelContainer
var hint_box: PanelContainer
var type_box: PanelContainer
var chip: Button
var tool_btns := {}
var words: BuildWordsUI
var fields := {}               # param -> LineEdit
var kind_btns := {}
var remove_btn: Button
var use_btn: Button            # "Use in a scene", top right (disabled until phase 1d)
var panel_title: Label
var _grid_was := true


func setup(main: Node) -> void:
	m = main
	name = "build_ui"
	root3 = Node3D.new()
	root3.name = "build_root"
	m.stage_root.add_child(root3)
	house = MeshInstance3D.new()
	house.name = "build_house"
	var clay := ShaderMaterial.new()
	clay.shader = HOUSE_SHADER
	house.material_override = clay
	root3.add_child(house)
	ghost_room = MeshInstance3D.new()
	ghost_room.name = "build_ghost_room"
	ghost_room.material_override = _glass(Color(SKY, 0.32))
	ghost_room.visible = false
	root3.add_child(ghost_room)
	sel_box = _box_node("build_sel", Color(SKY, 0.5))
	hover_box = _box_node("build_hover", Color(SKY, 0.28))
	grid = _make_grid()
	root3.add_child(grid)
	person = _make_person()
	root3.add_child(person)
	grid.visible = false
	person.visible = false
	_build_ui()


func _glass(c: Color, unshaded := true) -> StandardMaterial3D:
	var mt := StandardMaterial3D.new()
	mt.albedo_color = c
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mt


func _box_node(nm: String, c: Color) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.name = nm
	n.mesh = BoxMesh.new()
	n.material_override = _glass(c)
	n.visible = false
	root3.add_child(n)
	return n


## the floor grid: a line every 0.5 m (dim), every 2 m brighter; the two axes tinted
func _make_grid() -> MeshInstance3D:
	var v := PackedVector3Array()
	var c := PackedColorArray()
	var n := int(HALF / 0.5)
	for i in range(-n, n + 1):
		var t := i * 0.5
		var major := i % 4 == 0
		var col := Color(0.42, 0.5, 0.62, 0.32) if major else Color(0.3, 0.35, 0.43, 0.16)
		if i == 0:
			col = Color(0.5, 0.62, 0.9, 0.8)
		v.append_array([Vector3(t, 0.002, -HALF), Vector3(t, 0.002, HALF), Vector3(-HALF, 0.002, t), Vector3(HALF, 0.002, t)])
		for k in 4:
			c.append(col)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_COLOR] = c
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.vertex_color_use_as_albedo = true
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var g := MeshInstance3D.new()
	g.name = "build_grid"
	g.mesh = am
	g.material_override = mt
	return g


## a 1.8 m clay person (capsules and a ball), see-through, for scale
func _make_person() -> Node3D:
	var p := Node3D.new()
	p.name = "build_person"
	var mt := _glass(Color(0.74, 0.86, 1.0, 0.78))
	var parts := [[Vector3(-0.1, 0.43, 0), 0.09, 0.86], [Vector3(0.1, 0.43, 0), 0.09, 0.86], [Vector3(0, 1.24, 0), 0.2, 0.76]]
	for e in parts:
		var cm := CapsuleMesh.new()
		cm.radius = e[1]
		cm.height = e[2]
		var n := MeshInstance3D.new()
		n.mesh = cm
		n.material_override = mt
		n.position = e[0]
		p.add_child(n)
	var sm := SphereMesh.new()
	sm.radius = 0.11
	sm.height = 0.22
	var hd := MeshInstance3D.new()
	hd.mesh = sm
	hd.material_override = mt
	hd.position = Vector3(0, 1.69, 0)
	p.add_child(hd)
	var disc := MeshInstance3D.new()   # the dark disc he stands on
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.34
	cyl.bottom_radius = 0.34
	cyl.height = 0.01
	disc.mesh = cyl
	disc.material_override = _glass(Color(0.0, 0.0, 0.02, 0.75))
	disc.position = Vector3(0, 0.005, 0)
	p.add_child(disc)
	p.position = Vector3(3.8, 0, -1.0)
	return p


# ---------------------------------------------------------------- the ribbon, the panel, the labels

func _build_ui() -> void:
	var row: HBoxContainer = m.ui_ribbon["BUILD"]
	var group := ButtonGroup.new()
	for t in TOOLS:
		var btn: Button = m._button(t[0], _pick_tool.bind(t[0]), "%s tool. %s" % [t[0], String(t[1]).get_slice(": ", 1)])
		btn.toggle_mode = true
		btn.button_group = group
		btn.button_pressed = t[0] == tool
		btn.name = "build_tool_" + String(t[0]).to_lower()
		_icon_word(btn, String(t[0]))
		tool_btns[t[0]] = btn
		row.add_child(btn)
	for t in LATER:
		var btn: Button = m._button(t, func(): pass, "%s: " % t)
		btn.name = "build_tool_" + t.to_lower()
		_icon_word(btn, t)
		m._grey(btn, "coming next")
		row.add_child(btn)
	var wb: Button = m._button("Words", _pick_tool.bind("Words"), "Words tool. " + WORDS_TIP.get_slice(": ", 1))
	wb.toggle_mode = true
	wb.button_group = group
	wb.name = "build_tool_words"
	_icon_word(wb, "Words")
	tool_btns["Words"] = wb
	row.add_child(wb)
	ov = Control.new()
	ov.name = "build_overlay"
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.draw.connect(_draw_labels)
	ov.visible = false
	m.ui_root.add_child(ov)
	# the empty-state hint
	hint_box = _pill_panel("build_hint", FLOOR_HINT, 18)
	# the typing box (while dragging a room)
	type_box = PanelContainer.new()
	type_box.name = "build_type_box"
	var tl := Label.new()
	tl.name = "build_type_text"
	tl.text = "Type sizes to set them exactly:  width  Tab  depth  Enter"
	type_box.add_child(tl)
	type_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	type_box.visible = false
	m.ui_root.add_child(type_box)
	# the panel
	panel = PanelContainer.new()
	panel.name = "build_panel"
	panel.custom_minimum_size.x = PANEL_W
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.14, 0.94)
	sb.border_color = SKY
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	panel_title = Label.new()
	panel_title.name = "build_panel_title"
	panel_title.add_theme_font_size_override("font_size", 17)
	vb.add_child(panel_title)
	var kr := HBoxContainer.new()
	kr.name = "build_kind_row"
	var kg := ButtonGroup.new()
	for k in ["door", "window"]:
		var kb := Button.new()
		kb.text = k.capitalize()
		kb.name = "build_kind_" + k
		kb.toggle_mode = true
		kb.button_group = kg
		kb.focus_mode = Control.FOCUS_NONE
		kb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		kb.button_pressed = k == kind
		kb.tooltip_text = "the next opening is a %s (an opening you picked changes too)" % k
		kb.pressed.connect(_set_kind.bind(k))
		kind_btns[k] = kb
		kr.add_child(kb)
	vb.add_child(kr)
	for r in ROWS:
		var nr0 := _num_row(r[0], r[1])
		num_rows.append(nr0)
		vb.add_child(nr0)
	piece_box = VBoxContainer.new()
	piece_box.name = "build_piece_box"
	piece_box.add_theme_constant_override("separation", 6)
	piece_hint = Label.new()
	piece_hint.name = "build_piece_hint"
	piece_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	piece_hint.custom_minimum_size.x = PANEL_W - 28.0
	piece_box.add_child(piece_hint)
	piece_info = Label.new()
	piece_info.name = "build_piece_info"
	piece_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	piece_info.custom_minimum_size.x = PANEL_W - 28.0
	piece_info.add_theme_font_size_override("font_size", 13)
	piece_info.modulate = Color(1, 1, 1, 0.75)
	piece_box.add_child(piece_info)
	piece_rows = VBoxContainer.new()
	piece_rows.name = "build_piece_rows"
	piece_box.add_child(piece_rows)
	var prow := HBoxContainer.new()
	piece_rotate_btn = Button.new()
	piece_rotate_btn.name = "build_piece_rotate"
	piece_rotate_btn.text = "Rotate 90"
	piece_rotate_btn.icon = Icons.tex("piece_rotate")
	piece_rotate_btn.focus_mode = Control.FOCUS_NONE
	piece_rotate_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	piece_rotate_btn.tooltip_text = "turn the piece a quarter turn about its middle (one undo step)"
	piece_rotate_btn.pressed.connect(_piece_rotate)
	prow.add_child(piece_rotate_btn)
	piece_flip_btn = Button.new()
	piece_flip_btn.name = "build_piece_flip"
	piece_flip_btn.text = "Flip"
	piece_flip_btn.focus_mode = Control.FOCUS_NONE
	piece_flip_btn.tooltip_text = "the L stairs turn the other way (one undo step)"
	piece_flip_btn.pressed.connect(_piece_flip)
	prow.add_child(piece_flip_btn)
	piece_box.add_child(prow)
	piece_remove_btn = Button.new()
	piece_remove_btn.name = "build_piece_remove"
	piece_remove_btn.text = "Remove this piece"
	piece_remove_btn.focus_mode = Control.FOCUS_NONE
	piece_remove_btn.tooltip_text = "take the piece out (one undo step; Delete does the same)"
	piece_remove_btn.pressed.connect(_piece_remove)
	piece_box.add_child(piece_remove_btn)
	piece_box.visible = false
	vb.add_child(piece_box)
	wall_box = VBoxContainer.new()
	wall_box.name = "build_wall_box"
	var wl := Label.new()
	wl.name = "build_wall_hint"
	wl.text = "Drag inside a room to put a wall across it. A click splits the long side."
	wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wl.custom_minimum_size.x = PANEL_W - 28.0
	wall_box.add_child(wl)
	vb.add_child(wall_box)
	floor_box = VBoxContainer.new()
	floor_box.name = "build_floor_box"
	floors_label = Label.new()
	floors_label.name = "build_floors_list"
	floor_box.add_child(floors_label)
	var fb := HBoxContainer.new()
	var add_f := Button.new()
	add_f.name = "build_add_floor"
	add_f.text = "+ Floor"
	add_f.focus_mode = Control.FOCUS_NONE
	add_f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_f.tooltip_text = "adds a floor on top: the same footprint, a floor slab between (one undo step)"
	add_f.pressed.connect(_add_floor)
	fb.add_child(add_f)
	var rem_f := Button.new()
	rem_f.name = "build_remove_floor"
	rem_f.text = "Remove top floor"
	rem_f.focus_mode = Control.FOCUS_NONE
	rem_f.tooltip_text = "takes the top floor off (its rooms, walls and doors); the last floor stays"
	rem_f.pressed.connect(_remove_floor)
	fb.add_child(rem_f)
	floor_box.add_child(fb)
	floor_box.add_child(_num_row(EXTRA_ROWS[0][0], EXTRA_ROWS[0][1]))
	vb.add_child(floor_box)
	roof_box = VBoxContainer.new()
	roof_box.name = "build_roof_box"
	var rr := HBoxContainer.new()
	var rg := ButtonGroup.new()
	for k in Building.ROOFS:
		var rb := Button.new()
		rb.name = "build_roof_" + k
		rb.text = k.capitalize()
		rb.toggle_mode = true
		rb.button_group = rg
		rb.focus_mode = Control.FOCUS_NONE
		rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rb.tooltip_text = "a %s roof over the top floor (one undo step)" % k
		rb.pressed.connect(_set_roof.bind(k))
		roof_btns[k] = rb
		rr.add_child(rb)
	roof_box.add_child(rr)
	var nr := Button.new()
	nr.name = "build_roof_remove"
	nr.text = "No roof"
	nr.focus_mode = Control.FOCUS_NONE
	nr.pressed.connect(_remove_roof)
	roof_box.add_child(nr)
	roof_box.add_child(_num_row(EXTRA_ROWS[1][0], EXTRA_ROWS[1][1]))
	vb.add_child(roof_box)
	remove_btn = Button.new()
	remove_btn.name = "build_remove"
	remove_btn.text = "Remove this opening"
	remove_btn.focus_mode = Control.FOCUS_NONE
	remove_btn.tooltip_text = "take the picked opening out; the wall fills the hole (one undo step)"
	remove_btn.pressed.connect(_remove_sel)
	vb.add_child(remove_btn)
	var foot := Label.new()
	foot.text = "Numbers snap to 0.1 m.\nChange one and the house follows."
	foot.add_theme_font_size_override("font_size", 12)
	foot.modulate = Color(1, 1, 1, 0.6)
	vb.add_child(foot)
	panel.visible = false
	m.ui_root.add_child(panel)
	# the Snap chip
	chip = Button.new()
	chip.name = "build_snap_chip"
	chip.toggle_mode = true
	chip.button_pressed = true
	chip.focus_mode = Control.FOCUS_NONE
	chip.tooltip_text = "drags snap to the grid; click to turn snapping off (holding Alt frees one drag)"
	chip.toggled.connect(func(v: bool): snap_on = v; _chip_text())
	chip.visible = false
	m.ui_root.add_child(chip)
	_chip_text()
	stage_panel = PanelContainer.new()
	stage_panel.name = "build_stage_panel"
	stage_panel.custom_minimum_size.x = PANEL_W
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = Color(0.1, 0.11, 0.14, 0.94)
	ssb.border_color = SKY
	ssb.set_border_width_all(2)
	ssb.set_corner_radius_all(10)
	ssb.set_content_margin_all(12)
	stage_panel.add_theme_stylebox_override("panel", ssb)
	stage_body = VBoxContainer.new()
	stage_body.add_theme_constant_override("separation", 6)
	stage_panel.add_child(stage_body)
	stage_panel.visible = false
	m.ui_root.add_child(stage_panel)
	_build_picker()
	words = BuildWordsUI.new()
	words.setup(self)


## a ribbon button of this page: its icon (scripts/icons.gd, build_*) and one word
func _icon_word(btn: Button, word: String) -> void:
	btn.icon = Icons.tex("build_" + word.to_lower())
	btn.theme_type_variation = "Ribbon"
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.expand_icon = false
	btn.add_theme_constant_override("h_separation", 6)


## "Use in a scene", top right of the window, amber (the project's one main action; on STAGE it reads "Back to BUILD"). main._ui
## builds the top strip, then calls this with it. Only a building project shows it
func strip_button(strip: Control) -> void:
	use_btn = m._button("Use in a scene", _use_pressed, "put this building into a scene as a set to animate in")
	use_btn.name = "build_use_in_scene"
	var c: Color = Tok.c("accent")
	for st in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = c if st != "disabled" else Color(c, 0.55)
		if st == "hover":
			sb.bg_color = c.lightened(0.15)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
		use_btn.add_theme_stylebox_override(st, sb)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
		use_btn.add_theme_color_override(k, Tok.c("on_accent"))
	m._grey(use_btn, "draw a room first")
	use_btn.visible = false
	strip.add_child(use_btn)
	strip.move_child(use_btn, m.ui_undo_btn.get_index())


func _pill_panel(nm: String, txt: String, fs: int) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.name = nm
	var l := Label.new()
	l.name = nm + "_text"
	l.text = txt
	l.add_theme_font_size_override("font_size", fs)
	pc.add_child(l)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.visible = false
	m.ui_root.add_child(pc)
	return pc


func _num_row(label: String, key: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.name = "build_row_" + key
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var minus := Button.new()
	minus.text = "-"
	minus.name = "step_%s_minus" % key
	var plus := Button.new()
	plus.text = "+"
	plus.name = "step_%s_plus" % key
	var le := LineEdit.new()
	le.name = "num_" + key
	le.custom_minimum_size.x = 64
	le.alignment = HORIZONTAL_ALIGNMENT_CENTER
	le.select_all_on_focus = true
	var first := [false]   # this click gave the field its focus (the window grabs it before the press reaches the field)
	le.gui_input.connect(func(ev: InputEvent):   # a click in the field takes the whole number (the release would put the caret down and drop a selection made at focus): typing replaces it
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			if not (ev as InputEventMouseButton).pressed and first[0]:
				first[0] = false
				le.select_all.call_deferred())
	le.focus_entered.connect(func(): first[0] = true; le.select_all.call_deferred())
	for bt in [minus, plus]:
		bt.focus_mode = Control.FOCUS_NONE
		bt.custom_minimum_size.x = 28
	minus.pressed.connect(_step.bind(key, -1))
	plus.pressed.connect(_step.bind(key, 1))
	le.text_submitted.connect(_typed_param.bind(key, le))
	le.focus_exited.connect(func(): _typed_param(le.text, key, le))
	fields[key] = le
	h.add_child(minus)
	h.add_child(le)
	h.add_child(plus)
	return h


func _chip_text() -> void:
	if chip != null:
		chip.text = "Grid %s m   Snap %s" % [_g_text(), "on" if snap_on else "off"]


func _g_text() -> String:
	return "%.1f" % _grid()


func _grid() -> float:
	return 0.5


# ---------------------------------------------------------------- state

func _bld() -> Dictionary:
	return m.S.building


## the record to change (made on the first action: a new project starts with none)
func _ensure() -> Dictionary:
	if m.S.building.is_empty():
		m.S.building = Building.make(String(m.S.name) if String(m.S.name) != "" else "Untitled")
	return m.S.building


func _step_name(what: String) -> void:
	m._step_hint = what


## a toast (main._toast) never covers the panel: it sits low in the view, right of the Snap chip, and moves left of the panel (or
## under it) if it would touch it
func place_toast(t: Label) -> void:
	var cl: Rect2 = m.nav_clear_rect()
	t.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE)
	var sz := t.size
	var x := cl.position.x + 236.0
	var y := cl.end.y - sz.y - 6.0
	var side: Control = words.plan_panel if words != null and words.plan_panel.visible else panel
	if side.visible:
		var pr := Rect2(side.position, Vector2(side.size.x, maxf(side.size.y, side.get_combined_minimum_size().y))).grow(8.0)
		if Rect2(Vector2(x, y), sz).intersects(pr):
			x = maxf(cl.position.x + 12.0, pr.position.x - sz.x)
		if Rect2(Vector2(x, y), sz).intersects(pr):
			y = pr.end.y
	if picker != null and picker.visible and Rect2(Vector2(x, y), sz).intersects(Rect2(picker.position, picker.size).grow(8.0)):
		x = picker.position.x + picker.size.x + 8.0   # the Piece picker on the left: the toast goes right of it
	if chip != null and chip.visible and Rect2(Vector2(x, y), sz).intersects(Rect2(chip.position, chip.size)):
		y -= chip.size.y + 8.0   # still over the Snap chip: one line up
	t.position = Vector2(x, y)


## frame a wall: when its outer face looks away from the camera (a door on the far side), the camera turns three quarters onto it,
## room still in the middle. A wall already seen from outside keeps the view
func frame_wall(room: String, wall: String) -> void:
	var r := Building.room_of(_bld(), room)
	if r.is_empty() or not Building.WALLS.has(wall):
		return
	var n := {"front": Vector3(0, 0, -1), "back": Vector3(0, 0, 1), "left": Vector3(-1, 0, 0), "right": Vector3(1, 0, 0)}[wall] as Vector3
	var c := Vector3(float(r["x"]) + float(r["w"]) * 0.5, 0.0, float(r["z"]) + float(r["d"]) * 0.5)
	var wc := c + Vector3(n.x * float(r["w"]) * 0.5, 0.0, n.z * float(r["d"]) * 0.5)
	var to_cam: Vector3 = m.cam.global_position - wc
	to_cam.y = 0.0
	if to_cam.normalized().dot(n) > 0.3:
		return
	m._turn_to(rad_to_deg(atan2(n.x, n.z)) + 28.0, VIEW_PITCH, m.dist, Vector3(c.x, 0.9, c.z), false)


## a NEW project: the default three-quarter view and the Room tool (not where the last house was left)
func reset_view() -> void:
	m._turn_to(VIEW_YAW, VIEW_PITCH, VIEW_DIST, VIEW_AT, false)
	sel = ""
	_pick_tool("Room")


## the page was set (main._page_set): BUILD's grid / person / labels show on BUILD only; the house shows on every page
func page_changed(from: String, to: String) -> void:
	var was := on
	on = to == "BUILD"
	if on and not was:
		_grid_was = m.grid_node.visible if m.grid_node != null else true
		if m.grid_node != null:
			m.grid_node.visible = false
		m._turn_to(VIEW_YAW, VIEW_PITCH, VIEW_DIST, VIEW_AT, false)
	elif was and not on:
		if m.grid_node != null:
			m.grid_node.visible = _grid_was
		drag = ""
	grid.visible = on
	person.visible = on
	ov.visible = on
	sync()


## everything that shows the record follows it: the mesh, the highlights, the panel, the hint, the page tabs
func sync() -> void:
	m._page_tabs_sync()
	var bd := _bld()
	var has_rooms: bool = not bd.is_empty() and not bool(bd.get("readonly", false)) and not bd.get("rooms", []).is_empty()
	if use_btn != null:
		use_btn.visible = m.S.kind == "building"
		m._grey(use_btn, "" if has_rooms else "draw a room first")
		use_btn.text = "Back to BUILD" if m.cur_page == "STAGE" else "Use in a scene"
	if BuildStage.refresh(m.S):
		m._props_show()   # the set follows the house: its collision is the record's again
	_stage_sync()
	if bd.is_empty() or bool(bd.get("readonly", false)) or bd.get("rooms", []).is_empty():
		house.mesh = null
	else:
		house.mesh = Building.to_array_mesh(bd)
	if sel != "" and _opening(sel).is_empty():
		sel = ""
	if psel != "" and Building.piece_of(bd, psel).is_empty():
		psel = ""
	_highlights()
	_layout()
	_fields_sync()
	ov.queue_redraw()


func _opening(id: String) -> Dictionary:
	for o in _bld().get("openings", []):
		if String(o["id"]) == id:
			return o
	return {}


func _highlights() -> void:
	var o := _opening(sel)
	sel_box.visible = on and not o.is_empty()
	if sel_box.visible:
		_fit_box(sel_box, _opening_aabb(o), 0.03)
	hover_box.visible = false
	if on and tool == "Piece" and not Building.piece_of(_bld(), psel).is_empty():
		sel_box.visible = true
		_fit_box(sel_box, _piece_aabb(Building.piece_of(_bld(), psel)), 0.03)
	elif tool == "Piece":
		sel_box.visible = false
	ghost_room.visible = drag == "room" and size_text != ""


func _fit_box(n: MeshInstance3D, bx: AABB, grow: float) -> void:
	(n.mesh as BoxMesh).size = bx.size + Vector3.ONE * grow * 2.0
	n.position = bx.get_center()


func _opening_aabb(o: Dictionary) -> AABB:
	var r := Building.room_of(_bld(), String(o["room"]))
	return Building.opening_box(_bld(), r, o)   # rooms drawn here have yaw 0: the group frame is the world


func _fields_sync() -> void:
	var bd := _bld()
	if bd.is_empty():
		return
	for k in fields:
		var le: LineEdit = fields[k]
		if not le.has_focus():
			le.text = "%.1f m" % float(bd["params"].get(k, Building.PARAMS[k][0]))


func _layout() -> void:
	if m == null or panel == null:
		return
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var cl: Rect2 = m.nav_clear_rect()
	var has: bool = not _bld().is_empty() and not _bld().get("rooms", []).is_empty()
	var o := _opening(sel)
	panel.visible = on and has and tool != "Words"
	var pc := Building.piece_of(_bld(), psel) if tool == "Piece" else {}
	panel_title.text = ("%s" % String(o.get("kind", "")).capitalize() + "   (selected)") if not o.is_empty() else {"Floor": "Floors", "Roof": "Roof", "Wall": "Wall", "Piece": "Piece"}.get(tool, "Building")
	if not pc.is_empty():
		panel_title.text = "%s   (selected)" % String(BuildPieces.DEFS[String(pc["kind"])]["label"])
	piece_box.visible = tool == "Piece"
	for nr in num_rows:
		(nr as Control).visible = tool != "Piece"
	if tool == "Piece":
		_piece_panel_sync(pc)
	picker.visible = on and tool == "Piece"
	if picker.visible:
		_picker_sync(has)
		picker.reset_size()
		picker.position = Vector2(cl.position.x + 8.0, cl.position.y + 6.0)
	(kind_btns["door"].get_parent() as Control).visible = tool == "Opening"
	wall_box.visible = tool == "Wall"
	floor_box.visible = tool == "Floor"
	roof_box.visible = tool == "Roof"
	if floor_box.visible:
		var nf := Building.storey_count(_bld())
		var lines := []
		for i in nf:
			lines.append("Floor %d%s   (%d room%s)" % [i + 1, "  top" if i == nf - 1 else "", _rooms_on(i), "" if _rooms_on(i) == 1 else "s"])
		floors_label.text = "\n".join(lines)
	if roof_box.visible:
		var rk := String(_bld().get("roof", {}).get("kind", ""))
		for k in roof_btns:
			(roof_btns[k] as Button).set_pressed_no_signal(k == rk)
	remove_btn.visible = not o.is_empty()
	hint_box.visible = on and not has and tool == "Room" and drag == ""
	if hint_box.visible:
		hint_box.reset_size()
		hint_box.position = Vector2(cl.position.x + (cl.size.x - hint_box.size.x) * 0.5, cl.position.y + cl.size.y * 0.42)
	panel.reset_size()
	panel.position = Vector2(cl.end.x - PANEL_W - 8.0, cl.position.y + 6.0)   # left of the view cube
	type_box.visible = on and drag == "room"
	if type_box.visible:
		type_box.reset_size()
		type_box.position = Vector2(cl.end.x - type_box.size.x - 8.0, cl.position.y + 6.0)
	if words != null:
		words.layout(cl)
	chip.visible = on
	if on:
		chip.reset_size()
		chip.position = Vector2(cl.position.x + 12.0, cl.end.y - chip.size.y - 6.0)


func _process(_dt: float) -> void:
	if stage_panel != null and stage_panel.visible:
		_layout_stage()
	if on:
		_layout()
		if drag != "":
			ov.queue_redraw()


# ---------------------------------------------------------------- the tools

func _pick_tool(t: String) -> void:
	tool = t
	drag = ""
	if t != "Opening":
		sel = ""   # a picked opening belongs to the Opening tool (the panel would still say "Door (selected)")
	if t != "Piece":
		psel = ""
		piece_kind = ""
	if m.cur_page != "BUILD":
		m._page_set("BUILD")
	for k in tool_btns:
		(tool_btns[k] as Button).set_pressed_no_signal(k == t)
	for tl in TOOLS:
		if tl[0] == t:
			m._say(tl[1])
	if t == "Words":
		m._say(WORDS_TIP)
		words.focus.call_deferred()
	_highlights()
	_layout()
	ov.queue_redraw()


func _set_kind(k: String) -> void:
	kind = k
	var o := _opening(sel)
	if not o.is_empty() and String(o["kind"]) != k:
		m._step_hint = "Opening: %s" % k
		m._push_undo()
		o["kind"] = k
		if k == "window":
			o.merge({"w": "window_width", "h": "window_height", "sill": "window_sill"}, true)
		else:
			o.merge({"w": "door_width", "h": "door_height", "sill": 0.0}, true)
		m._say("Opening: now a %s" % k)
		sync()


func _remove_sel() -> void:
	var o := _opening(sel)
	if o.is_empty():
		return
	m._step_hint = "Opening: remove"
	m._push_undo()
	_bld()["openings"].erase(o)
	sel = ""
	m._say("Opening: removed, the wall is whole again")
	sync()


func _step(key: String, dir: int) -> void:
	if _bld().is_empty():
		return
	_commit_param(key, float(_bld()["params"].get(key, 0.0)) + 0.1 * dir)


func _typed_param(txt: String, key: String, le: LineEdit) -> void:
	if _bld().is_empty():
		return
	var s := txt.strip_edges().trim_suffix("m").strip_edges()
	if s.is_valid_float():
		_commit_param(key, float(s))
	le.release_focus()
	_fields_sync()


func _commit_param(key: String, v: float) -> void:
	var def: Array = Building.PARAMS[key]
	v = clampf(snappedf(v, 0.1), def[1], def[2])
	var bd := _bld()
	var old := float(bd["params"].get(key, def[0]))
	if absf(old - v) < 1e-6:
		return
	var label := String(LABELS.get(key, key))
	var what := "%s %.1f -> %.1f m" % [label, old, v]
	m._step_hint = what
	m._push_undo()
	bd["params"][key] = v
	m._say(what)
	sync()


## floor point under a screen position (y = 0), or null
func ground(p: Vector2) -> Variant:
	var o: Vector3 = m.cam.project_ray_origin(p)
	var n: Vector3 = m.cam.project_ray_normal(p)
	if absf(n.y) < 1e-5:
		return null
	var t := -o.y / n.y
	if t <= 0.0:
		return null
	return o + n * t


func _snap(v: Vector3) -> Vector3:
	if not snap_on or Input.is_key_pressed(KEY_ALT):
		return Vector3(snappedf(v.x, 0.05), 0, snappedf(v.z, 0.05))
	return Vector3(snappedf(v.x, _grid()), 0, snappedf(v.z, _grid()))


## ray vs box (slab test): the entry distance, or -1
func _ray_box(o: Vector3, d: Vector3, bx: AABB) -> float:
	var t0 := 0.0
	var t1 := 1e9
	for i in 3:
		var lo: float = bx.position[i]
		var hi: float = bx.end[i]
		if absf(d[i]) < 1e-9:
			if o[i] < lo or o[i] > hi:
				return -1.0
		else:
			var ta := (lo - o[i]) / d[i]
			var tb := (hi - o[i]) / d[i]
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
			if t0 > t1:
				return -1.0
	return t0


## the opening under the mouse, "" if none
func pick_opening(p: Vector2) -> String:
	var o: Vector3 = m.cam.project_ray_origin(p)
	var d: Vector3 = m.cam.project_ray_normal(p)
	var best := ""
	var bt := 1e9
	for op in _bld().get("openings", []):
		var bx := _opening_aabb(op).grow(0.06)
		var t := _ray_box(o, d, bx)
		if t >= 0.0 and t < bt:
			bt = t
			best = String(op["id"])
	return best


## an outer wall's slab (rooms drawn here have yaw 0: the group frame is the world), lifted to its floor
func wall_slab(r: Dictionary, wall: String) -> AABB:
	var x := float(r["x"])
	var z := float(r["z"])
	var w := float(r["w"])
	var dd := float(r["d"])
	var y := Building.base_y(_bld(), r)
	var h := Building.num(_bld(), r.get("height"), 2.7)
	var t := clampf(Building.num(_bld(), r.get("thickness"), 0.2), 0.01, minf(w, dd) * 0.5 - 0.01)
	match wall:
		"front": return AABB(Vector3(x, y, z), Vector3(w, h, t))
		"back": return AABB(Vector3(x, y, z + dd - t), Vector3(w, h, t))
		"left": return AABB(Vector3(x, y, z), Vector3(t, h, dd))
		_: return AABB(Vector3(x + w - t, y, z), Vector3(t, h, dd))


## the wall under the mouse: {"room", "wall" (front / right / back / left, or an interior wall's id), "at" (metres from the
## wall's middle, snapped), "hit" (the point on it)}, or {}
func pick_wall(p: Vector2) -> Dictionary:
	var o: Vector3 = m.cam.project_ray_origin(p)
	var d: Vector3 = m.cam.project_ray_normal(p)
	var best := {}
	var bt := 1e9
	for r in _bld().get("rooms", []):
		var x := float(r["x"])
		var z := float(r["z"])
		var w := float(r["w"])
		var dd := float(r["d"])
		var slabs := {}
		for wall in Building.WALLS:
			slabs[wall] = wall_slab(r, wall)
		for iw in _bld().get("walls", []):
			if String(iw["room"]) == String(r["id"]):
				var ib := Building.inner_box(_bld(), r, iw)
				if ib.size != Vector3.ZERO:
					slabs[String(iw["id"])] = ib
		for wall in slabs:
			var tt := _ray_box(o, d, slabs[wall])
			if tt >= 0.0 and tt < bt:
				bt = tt
				var hit := o + d * tt
				var along_x := _along_x(wall)
				var centre := (x + w * 0.5) if along_x else (z + dd * 0.5)
				var pos := hit.x if along_x else hit.z
				best = {"room": String(r["id"]), "wall": wall, "at": _snap_along(pos) - centre, "hit": hit}
	return best


## does this wall run along X? (front / back; an interior wall by its axis)
func _along_x(wall: String) -> bool:
	if Building.WALLS.has(wall):
		return wall == "front" or wall == "back"
	return String(Building.wall_of(_bld(), wall).get("axis", "z")) == "x"


func _snap_along(v: float) -> float:
	return v if (not snap_on or Input.is_key_pressed(KEY_ALT)) else snappedf(v, _grid())


## the room the drag makes: {x, z, w, d}
func drag_rect() -> Dictionary:
	var w := absf(b.x - a.x)
	var d := absf(b.z - a.z)
	var sx := 1.0 if b.x >= a.x else -1.0
	var sz := 1.0 if b.z >= a.z else -1.0
	if typed[0] != "":
		w = clampf(snappedf(float(typed[0]), 0.1), Building.MIN_SIZE, 100.0)
	if typed[1] != "":
		d = clampf(snappedf(float(typed[1]), 0.1), Building.MIN_SIZE, 100.0)
	return {"x": a.x if sx > 0 else a.x - w, "z": a.z if sz > 0 else a.z - d, "w": w, "d": d}


func _drag_update() -> void:
	var r := drag_rect()
	var valid: bool = float(r["w"]) >= Building.MIN_SIZE and float(r["d"]) >= Building.MIN_SIZE
	size_text = "%.1f m x %.1f m" % [r["w"], r["d"]] if valid else ""
	area_text = "%d m2 floor" % roundi(float(r["w"]) * float(r["d"])) if valid else ""
	if valid:
		var gb := Building.make()
		if not _bld().is_empty():
			gb["params"] = _bld()["params"]
		Building.add_room(gb, r["x"], r["z"], r["w"], r["d"])
		ghost_room.mesh = Building.to_array_mesh(gb)
	ghost_room.visible = valid
	_layout()
	ov.queue_redraw()


func _end_drag() -> void:
	drag = ""
	size_text = ""
	area_text = ""
	typed = ["", ""]
	field = 0
	ghost_room.visible = false
	_slide_moved = false
	_wall_room = ""
	_pull = {}
	_layout()
	ov.queue_redraw()


func _finish_room() -> void:
	var r := drag_rect()
	if float(r["w"]) >= Building.MIN_SIZE and float(r["d"]) >= Building.MIN_SIZE:
		m._step_hint = "Room %.1f x %.1f m" % [r["w"], r["d"]]
		m._push_undo()
		var bd := _ensure()
		Building.add_room(bd, r["x"], r["z"], r["w"], r["d"])
		m._say("Room %.1f m x %.1f m: 4 walls (%.1f m) and a floor" % [r["w"], r["d"], Building.num(bd, "wall_height", 2.7)])
		_end_drag()
		sync()
	else:
		_end_drag()


## main._unhandled_input: true when BUILD took the event
func input(ev: InputEvent) -> bool:
	if not on:
		return false
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := ev as InputEventMouseButton
		if mb.pressed:
			return _press(mb.position)
		return _release()
	if ev is InputEventMouseMotion:
		return _motion((ev as InputEventMouseMotion).position)
	if ev is InputEventKey and (ev as InputEventKey).pressed:
		return _key(ev as InputEventKey)
	return false


func _press(p: Vector2) -> bool:
	if tool == "Wall":
		return _press_wall(p)
	if tool == "Pull":
		return _press_pull(p)
	if tool == "Roof":
		if not _bld().is_empty() and not _bld().get("rooms", []).is_empty() and _bld().get("roof", {}).is_empty():
			_set_roof("gable")
		return true
	if tool == "Floor":
		return true
	if tool == "Piece":
		return _press_piece(p)
	if tool == "Room":
		var g: Variant = ground(p)
		if g == null:
			return true
		a = _snap(g)
		b = a
		drag = "room"
		typed = ["", ""]
		field = 0
		_drag_update()
		m._say(TOOLS[0][1])
		return true
	if tool == "Opening":
		var hit := pick_opening(p)
		if hit != "":
			sel = hit
			drag = "slide"
			_slide_moved = false
			_highlights()
			sync()
			return true
		var w := pick_wall(p)
		if not w.is_empty():
			m._step_hint = "Opening: %s" % kind
			m._push_undo()
			var id := Building.add_opening(_bld(), w["room"], w["wall"], kind, w["at"])
			sel = id
			drag = "slide"
			frame_wall(w["room"], w["wall"])
			_slide_moved = true   # its undo step is this click's
			m._say("Opening: a %s on the %s wall. Drag it along the wall to slide it" % [kind, w["wall"]])
			sync()
			return true
		sel = ""
		sync()
		return true
	return false


func _release() -> bool:
	if drag == "wall":
		_finish_wall()
		return true
	if drag == "pull":
		_finish_pull()
		return true
	if drag == "room":
		_finish_room()   # typed sizes, if any, are taken as they stand
		return true
	if drag == "slide":
		var o := _opening(sel)
		if not o.is_empty() and _slide_moved:
			m._say("Opening: at %.1f m from the wall's middle" % float(o["at"]))
		_end_drag()
		return true
	return false


func _motion(p: Vector2) -> bool:
	if drag == "wall":
		var gw: Variant = ground(p)
		if gw != null:
			b = _snap(gw)
			ov.queue_redraw()
		return true
	if drag == "pull":
		_pull_move(p)
		return true
	if tool == "Pull" and drag == "":
		var pw := pick_wall(p)
		hover_box.visible = not pw.is_empty() and Building.WALLS.has(String(pw["wall"]))
		if hover_box.visible:
			_fit_box(hover_box, wall_slab(Building.room_of(_bld(), String(pw["room"])), String(pw["wall"])), 0.02)
		return false
	if drag == "room":
		var g: Variant = ground(p)
		if g != null:
			b = _snap(g)
			_drag_update()
		return true
	if drag == "slide":
		var o := _opening(sel)
		var w := pick_wall_plane(o, p)
		if not o.is_empty() and w != INF and absf(w - float(o["at"])) > 1e-6:
			if not _slide_moved:
				m._step_hint = "Opening: slide"
				m._push_undo()
				_slide_moved = true
			o["at"] = w
			sync()
		return true
	if tool == "Opening" and drag == "":
		_hover_update(p)
	if tool == "Piece" and drag == "":
		_piece_hover(p)
	return false


## the "at" a slide to screen point p means: the ray against the wall's own plane, snapped (INF when parallel)
func pick_wall_plane(o: Dictionary, p: Vector2) -> float:
	if o.is_empty():
		return INF
	var r := Building.room_of(_bld(), String(o["room"]))
	var wall := String(o["wall"])
	var x := float(r["x"])
	var z := float(r["z"])
	var w := float(r["w"])
	var dd := float(r["d"])
	var t := clampf(Building.num(_bld(), r.get("thickness"), 0.2), 0.01, minf(w, dd) * 0.5 - 0.01)
	var org: Vector3 = m.cam.project_ray_origin(p)
	var dir: Vector3 = m.cam.project_ray_normal(p)
	var along_x := _along_x(wall)
	var plane := 0.0
	match wall:
		"front": plane = z + t * 0.5
		"back": plane = z + dd - t * 0.5
		"left": plane = x + t * 0.5
		"right": plane = x + w - t * 0.5
		_:
			var ib := Building.inner_box(_bld(), r, Building.wall_of(_bld(), wall))
			plane = (ib.get_center().z) if along_x else (ib.get_center().x)
	var ax := 2 if along_x else 0   # the axis the wall's plane is perpendicular to
	if absf(dir[ax]) < 1e-6:
		return INF
	var tt := (plane - org[ax]) / dir[ax]
	var hit := org + dir * tt
	var centre := (x + w * 0.5) if along_x else (z + dd * 0.5)
	return _snap_along(hit.x if along_x else hit.z) - centre


func _hover_update(p: Vector2) -> void:
	var w := pick_wall(p)
	if pick_opening(p) != "" or w.is_empty():
		hover_box.visible = false
		return
	var gb := _bld().duplicate(true)
	var id := Building.add_opening(gb, w["room"], w["wall"], kind, w["at"])
	for o in gb["openings"]:
		if String(o["id"]) == id:
			var r := Building.room_of(gb, String(o["room"]))
			_fit_box(hover_box, Building.opening_box(gb, r, o), 0.02)
			hover_box.visible = true


func _key(k: InputEventKey) -> bool:
	if drag == "room":
		var ch := ""
		if k.keycode >= KEY_0 and k.keycode <= KEY_9:
			ch = str(k.keycode - KEY_0)
		elif k.keycode >= KEY_KP_0 and k.keycode <= KEY_KP_9:
			ch = str(k.keycode - KEY_KP_0)
		elif k.keycode in [KEY_PERIOD, KEY_KP_PERIOD, KEY_COMMA]:
			ch = "."
		if ch != "":
			if ch != "." or not String(typed[field]).contains("."):
				typed[field] = String(typed[field]) + ch
			_drag_update()
			return true
		match k.keycode:
			KEY_TAB:
				field = 1 - field
				return true
			KEY_BACKSPACE:
				if typed[field] == "" and field == 1:
					field = 0
				else:
					typed[field] = String(typed[field]).left(-1)
				_drag_update()
				return true
			KEY_ENTER, KEY_KP_ENTER:
				_finish_room()
				return true
			KEY_ESCAPE:
				_end_drag()
				m._say("Room: cancelled, nothing changed")
				return true
		return false
	if tool == "Opening" and sel != "" and (k.keycode == KEY_DELETE or k.keycode == KEY_BACKSPACE):
		_remove_sel()
		return true
	if tool == "Floor" and k.keycode == KEY_DELETE:
		_remove_floor()
		return true
	if tool == "Piece":
		if psel != "" and (k.keycode == KEY_DELETE or k.keycode == KEY_BACKSPACE) and not (m.get_viewport().gui_get_focus_owner() is LineEdit):
			_piece_remove()
			return true
		if k.keycode == KEY_ESCAPE and (piece_kind != "" or psel != ""):
			piece_kind = ""
			psel = ""
			_sync_cards()
			sync()
			m._say("Piece: nothing in hand")
			return true
	if (drag == "wall" or drag == "pull") and k.keycode == KEY_ESCAPE:
		if drag == "pull":
			_pull_restore()
		_end_drag()
		m._say("cancelled, nothing changed")
		return true
	return false


# ---------------------------------------------------------------- Wall, Pull, Floor, Roof

func _rooms_on(storey: int) -> int:
	var n := 0
	for r in _bld().get("rooms", []):
		if int(r.get("storey", 0)) == storey:
			n += 1
	return n


## the ground-floor room whose outside holds this floor point, "" if none
func _room_at(g: Vector3) -> String:
	for r in _bld().get("rooms", []):
		if int(r.get("storey", 0)) != 0:
			continue
		if g.x > float(r["x"]) and g.x < float(r["x"]) + float(r["w"]) and g.z > float(r["z"]) and g.z < float(r["z"]) + float(r["d"]):
			return String(r["id"])
	return ""


func _press_wall(p: Vector2) -> bool:
	var g: Variant = ground(p)
	if g == null:
		return true
	_wall_room = _room_at(g)
	if _wall_room == "":
		m._say("Wall: start the drag inside a room")
		return true
	a = _snap(g)
	b = a
	drag = "wall"
	m._say(TOOLS[1][1])
	ov.queue_redraw()
	return true


## the wall the drag means: {"ok", "axis", "pos", "why"}. A drag along Z is a wall along Z (axis "z", at x = pos from the room's
## corner); a short drag (a click) splits the room's long side. pos keeps MIN_SIDE of room on each side
func wall_spec() -> Dictionary:
	var r := Building.room_of(_bld(), _wall_room)
	if r.is_empty():
		return {"ok": false, "why": "no room"}
	var dx := absf(b.x - a.x)
	var dz := absf(b.z - a.z)
	var axis := "z" if dz > dx else "x"
	if maxf(dx, dz) < 0.25:
		axis = "z" if float(r["w"]) >= float(r["d"]) else "x"
	var along_z := axis == "z"
	var pos := (a.x - float(r["x"])) if along_z else (a.z - float(r["z"]))
	var across := float(r["w"]) if along_z else float(r["d"])
	var t := clampf(Building.num(_bld(), r.get("thickness"), 0.2), 0.01, minf(float(r["w"]), float(r["d"])) * 0.5 - 0.01)
	var ti := Building.num(_bld(), "inner_wall_thickness", 0.1)
	if pos < t + ti * 0.5 + MIN_SIDE - 1e-6 or pos > across - t - ti * 0.5 - MIN_SIDE + 1e-6:
		return {"ok": false, "axis": axis, "pos": pos, "why": "too close to a wall"}
	for iw in _bld().get("walls", []):
		if String(iw["room"]) == _wall_room and String(iw["axis"]) == axis and absf(float(iw["pos"]) - pos) < 0.05:
			return {"ok": false, "axis": axis, "pos": pos, "why": "there is a wall there already"}
	return {"ok": true, "axis": axis, "pos": pos}


func _finish_wall() -> void:
	var sp := wall_spec()
	var room := _wall_room
	_end_drag()
	if not bool(sp["ok"]):
		m._say("Wall: %s, nothing changed" % sp.get("why", "not a wall"))
		return
	m._step_hint = "Wall at %.1f m" % float(sp["pos"])
	m._push_undo()
	var id := Building.add_wall(_bld(), room, String(sp["axis"]), float(sp["pos"]))
	m._say("Wall: %s across the room at %.1f m (%.1f m thick). Use Opening to put a door in it" % [id, float(sp["pos"]), Building.num(_bld(), "inner_wall_thickness", 0.1)])
	sync()


func _draw_wall_preview() -> void:
	var r := Building.room_of(_bld(), _wall_room)
	if r.is_empty():
		return
	var sp := wall_spec()
	var x := float(r["x"])
	var z := float(r["z"])
	var w := float(r["w"])
	var dd := float(r["d"])
	var t := clampf(Building.num(_bld(), r.get("thickness"), 0.2), 0.01, minf(w, dd) * 0.5 - 0.01)
	var along_z := String(sp.get("axis", "z")) == "z"
	var pos: float = float(sp.get("pos", 0.0))
	var p0 := Vector3(x + pos, 0.0, z + t) if along_z else Vector3(x + t, 0.0, z + pos)
	var p1 := Vector3(x + pos, 0.0, z + dd - t) if along_z else Vector3(x + w - t, 0.0, z + pos)
	var col := SKY if bool(sp.get("ok", false)) else Color("#ff7a59")
	var s0: Vector2 = m.cam.unproject_position(p0)
	var s1: Vector2 = m.cam.unproject_position(p1)
	ov.draw_line(s0, s1, col, 4.0, true)
	ov.draw_circle(s0, 5.0, Color.WHITE)
	ov.draw_circle(s1, 5.0, Color.WHITE)
	var across := w if along_z else dd
	var txt := "%.1f m + %.1f m" % [pos, across - pos] if bool(sp.get("ok", false)) else String(sp.get("why", ""))
	_pill((s0 + s1) * 0.5 + Vector2(0, -20), txt, Color(0.06, 0.07, 0.1, 0.92) if bool(sp.get("ok", false)) else Color("#ff7a59"), Color.WHITE if bool(sp.get("ok", false)) else Color(0.1, 0.03, 0.0), 18)


## the point of the ray through screen point p on the horizontal plane at height y, or null
func plane_hit(p: Vector2, y: float) -> Variant:
	var o: Vector3 = m.cam.project_ray_origin(p)
	var n: Vector3 = m.cam.project_ray_normal(p)
	if absf(n.y) < 1e-5:
		return null
	var t := (y - o.y) / n.y
	if t <= 0.0:
		return null
	return o + n * t


func _press_pull(p: Vector2) -> bool:
	var w := pick_wall(p)
	if w.is_empty() or not Building.WALLS.has(String(w["wall"])):
		m._say("Pull: press on a room's outer wall and drag it in or out")
		return true
	var r := Building.room_of(_bld(), String(w["room"]))
	var y: float = (w["hit"] as Vector3).y
	var g0: Variant = plane_hit(p, y)
	if g0 == null:
		return true
	var pos := {}
	for iw in _bld().get("walls", []):
		if String(iw["room"]) == String(r["id"]):
			pos[String(iw["id"])] = float(iw["pos"])
	_pull = {"room": String(r["id"]), "wall": String(w["wall"]), "y": y, "g0": g0, "moved": false, "text": "",
		"orig": {"x": float(r["x"]), "z": float(r["z"]), "w": float(r["w"]), "d": float(r["d"])}, "walls": pos}
	drag = "pull"
	hover_box.visible = false
	m._say(TOOLS[2][1])
	return true


func _pull_move(p: Vector2) -> void:
	if _pull.is_empty():
		return
	var g: Variant = plane_hit(p, float(_pull["y"]))
	if g == null:
		return
	var o: Dictionary = _pull["orig"]
	var d3: Vector3 = (g as Vector3) - (_pull["g0"] as Vector3)
	var nx: float = o["x"]
	var nz: float = o["z"]
	var nw: float = o["w"]
	var nd: float = o["d"]
	var wall := String(_pull["wall"])
	var amount := 0.0
	match wall:
		"right":
			nw = maxf(_snap_along(nx + nw + d3.x) - nx, Building.MIN_SIZE)
			amount = nw - float(o["w"])
		"left":
			var ex := minf(_snap_along(nx + d3.x), float(o["x"]) + float(o["w"]) - Building.MIN_SIZE)
			nw = float(o["x"]) + float(o["w"]) - ex
			nx = ex
			amount = -(nx - float(o["x"]))
		"back":
			nd = maxf(_snap_along(nz + nd + d3.z) - nz, Building.MIN_SIZE)
			amount = nd - float(o["d"])
		_:
			var ez := minf(_snap_along(nz + d3.z), float(o["z"]) + float(o["d"]) - Building.MIN_SIZE)
			nd = float(o["z"]) + float(o["d"]) - ez
			nz = ez
			amount = -(nz - float(o["z"]))
	var r := Building.room_of(_bld(), String(_pull["room"]))
	if absf(float(r["x"]) - nx) < 1e-9 and absf(float(r["z"]) - nz) < 1e-9 and absf(float(r["w"]) - nw) < 1e-9 and absf(float(r["d"]) - nd) < 1e-9:
		return
	if not bool(_pull["moved"]):
		m._step_hint = "Pull: room"
		m._push_undo()   # before the record changes: ONE undo step for the whole drag
		_pull["moved"] = true
	r["x"] = nx
	r["z"] = nz
	r["w"] = nw
	r["d"] = nd
	for iw in _bld().get("walls", []):   # an interior wall stays where it stands in the world when its room grows from the left / front
		if String(iw["room"]) == String(r["id"]) and _pull["walls"].has(String(iw["id"])):
			var op: float = _pull["walls"][String(iw["id"])]
			if String(iw["axis"]) == "z":
				iw["pos"] = op - (nx - float(o["x"]))
			else:
				iw["pos"] = op - (nz - float(o["z"]))
	_pull["text"] = "%s wall %s%.1f m   room %.1f m x %.1f m" % [wall.capitalize(), "+" if amount >= 0.0 else "-", absf(amount), nw, nd]
	sync()
	ov.queue_redraw()


func _pull_restore() -> void:
	if not _pull.is_empty() and bool(_pull.get("moved", false)):
		m._undo()


func _finish_pull() -> void:
	var moved: bool = bool(_pull.get("moved", false))
	var r := Building.room_of(_bld(), String(_pull.get("room", "")))
	_end_drag()
	if moved and not r.is_empty():
		m._say("Pull: the room is %.1f m x %.1f m now. Doors keep their place from the wall's middle" % [float(r["w"]), float(r["d"])])


func _draw_pull_label() -> void:
	if _pull.is_empty() or String(_pull["text"]) == "":
		return
	var r := Building.room_of(_bld(), String(_pull["room"]))
	var slab := wall_slab(r, String(_pull["wall"]))
	var c := slab.get_center()
	var outward := {"front": Vector3(0, 0, -1), "back": Vector3(0, 0, 1), "left": Vector3(-1, 0, 0), "right": Vector3(1, 0, 0)}[String(_pull["wall"])] as Vector3
	var at: Vector2 = m.cam.unproject_position(c + outward * 0.8 + Vector3(0, slab.size.y * 0.5 + 0.3, 0))
	at.x = minf(at.x, panel.position.x - 190.0)   # never under the panel
	_outline_box(slab.grow(0.03))
	_pill(at, String(_pull["text"]), SKY, Color(0.04, 0.06, 0.1), 16)


## frame the whole house: the camera target on its middle, far enough back for its height
func _frame_house() -> void:
	var bd := _bld()
	if bd.is_empty() or bd.get("rooms", []).is_empty():
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for r in bd["rooms"]:
		lo = Vector2(minf(lo.x, float(r["x"])), minf(lo.y, float(r["z"])))
		hi = Vector2(maxf(hi.x, float(r["x"]) + float(r["w"])), maxf(hi.y, float(r["z"]) + float(r["d"])))
	var top := Building.storey_count(bd) * Building.num(bd, "floor_height", 2.8)
	var d := maxf(VIEW_DIST, (hi - lo).length() * 1.9 + top * 1.7)
	var at := Vector3((lo.x + hi.x) * 0.5, top * 0.35, (lo.y + hi.y) * 0.5)
	if tool == "Words":   # the plan's cards cover the right of the view: the house stands in the free part, left of them
		d *= 1.2
		m._turn_to(m.yaw, m.pitch, d, at, false)
		var rx: Vector3 = m.cam.global_transform.basis.x
		at += Vector3(rx.x, 0.0, rx.z).normalized() * d * 0.2
	m._turn_to(m.yaw, m.pitch, d, at, false)


func _add_floor() -> void:
	var bd := _bld()
	if bd.is_empty() or bd.get("rooms", []).is_empty():
		m._say("Floor: draw a room first")
		return
	m._step_hint = "Floor: add"
	m._push_undo()
	var n := Building.add_floor(bd)
	m._say("Floor %d added: the same footprint, a floor slab between (%.1f m up)" % [n + 1, Building.num(bd, "floor_height", 2.8) * n])
	sync()
	_frame_house()


func _remove_floor() -> void:
	var bd := _bld()
	if Building.storey_count(bd) < 2:
		m._say("Floor: the last floor stays")
		return
	m._step_hint = "Floor: remove top"
	m._push_undo()
	Building.remove_top_floor(bd)
	m._say("Floor: the top floor is gone")
	sync()


func _set_roof(k: String) -> void:
	var bd := _bld()
	if bd.is_empty() or bd.get("rooms", []).is_empty():
		m._say("Roof: draw a room first")
		return
	if String(bd.get("roof", {}).get("kind", "")) == k:
		return
	m._step_hint = "Roof: %s" % k
	m._push_undo()
	Building.set_roof(bd, k)
	m._say("Roof: %s, overhang %.2f m. The overhang is a number in the panel" % [k, Building.num(bd, bd["roof"].get("overhang"), 0.45)])
	sync()
	_frame_house()


func _remove_roof() -> void:
	var bd := _bld()
	if bd.get("roof", {}).is_empty():
		return
	m._step_hint = "Roof: none"
	m._push_undo()
	bd.erase("roof")
	m._say("Roof: taken off")
	sync()


# ---------------------------------------------------------------- Use in a scene, and the STAGE panel

func _use_pressed() -> void:
	if m.cur_page == "STAGE":
		m._page_set("BUILD")
		return
	use_in_scene()


## the house becomes a set: its kind is registered from the record, one prop is added (once), the page is STAGE. One undo step
func use_in_scene() -> void:
	var bd := _bld()
	if bd.is_empty() or bd.get("rooms", []).is_empty() or bool(bd.get("readonly", false)):
		m._say("Use in a scene: draw a room first")
		return
	m._step_hint = "Use in a scene: %s" % bd.get("name", "house")
	m._push_undo()
	var kind := BuildStage.use(m.S)
	m.sel_prop = -1
	m._props_show()
	m._page_set("STAGE")
	_stage_sync()
	var doors := BuildStage.door_names(bd)
	frame_door(String(doors[0]) if not doors.is_empty() else "")
	m._say("STAGE: the building is now a set (%s). %s Edit the house in BUILD any time" % [kind.trim_prefix("building:"),
		"The fighter walks through the %s." % doors[0] if not doors.is_empty() else "Put a door in it and the fighter can walk in."])


## the STAGE camera: the door seen from outside, a little above, the fighter's walk in view ("" = the house's middle)
func frame_door(name: String) -> void:
	var a := Building.anchor(_bld(), name) if name != "" else {}
	if a.is_empty():
		_frame_house()
		return
	var pos: Vector3 = a["pos"]
	var out: Vector3 = a["out"]
	var at := pos + out * 0.6 + Vector3(0, 0.9, 0)
	m._turn_to(rad_to_deg(atan2(out.x, out.z)) + 28.0, -24.0, 8.5, at, false)


var _stage_sig := ""


## the STAGE panel (the mockup's "Set added to STAGE"): follows the record, rebuilt only when it changes
func _stage_sync() -> void:
	if stage_panel == null:
		return
	var show: bool = m.cur_page == "STAGE" and m.S.kind == "building" and BuildStage.prop_index(m.S) >= 0
	stage_panel.visible = show
	if not show:
		return
	var sig := JSON.stringify(Building.to_file(_bld()))
	if sig == _stage_sig and stage_body.get_child_count() > 0:
		return
	_stage_sig = sig
	for c in stage_body.get_children():
		stage_body.remove_child(c)
		c.queue_free()
	walk_btns.clear()
	var bd := _bld()
	var title := Label.new()
	title.name = "build_stage_title"
	title.text = "Set added to STAGE"
	title.add_theme_font_size_override("font_size", 17)
	stage_body.add_child(title)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var doors := 0
	var windows := 0
	for r in bd.get("rooms", []):
		lo = Vector2(minf(lo.x, float(r["x"])), minf(lo.y, float(r["z"])))
		hi = Vector2(maxf(hi.x, float(r["x"]) + float(r["w"])), maxf(hi.y, float(r["z"]) + float(r["d"])))
	for o in bd.get("openings", []):
		if String(o["kind"]) == "window":
			windows += 1
		else:
			doors += 1
	var info := Label.new()
	info.name = "build_stage_info"
	var nf := Building.storey_count(bd)
	info.text = "%s\n%.1f x %.1f m, %d floor%s\n%d door%s, %d window%s   linked to BUILD" % [bd.get("name", "House"), hi.x - lo.x, hi.y - lo.y, nf, "" if nf == 1 else "s", doors, "" if doors == 1 else "s", windows, "" if windows == 1 else "s"]
	stage_body.add_child(info)
	var names := BuildStage.door_names(bd)
	var stairs := BuildStage.stairs_list(bd)
	var lines := ["Collision: walls and floor, doorways open", "Door points: %s" % (", ".join(names) if not names.is_empty() else "none yet (put a door in the house)")]
	if not bd.get("pieces", []).is_empty():
		lines.append("Pieces: %d (stairs are ramps the fighter walks up)" % bd["pieces"].size())
	for line in lines:
		var l := Label.new()
		l.text = "[ok]  " + line
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = PANEL_W - 28.0
		l.add_theme_font_size_override("font_size", 13)
		stage_body.add_child(l)
	if not names.is_empty() or not stairs.is_empty():
		var say := Label.new()
		say.text = "ANIMATE can now say:"
		say.add_theme_font_size_override("font_size", 12)
		say.modulate = Color(1, 1, 1, 0.6)
		stage_body.add_child(say)
	for nm in names:
		var wb := Button.new()
		wb.name = "build_walk_" + String(nm).replace(" ", "_")
		wb.text = "Walk through the %s" % nm
		wb.focus_mode = Control.FOCUS_NONE
		wb.tooltip_text = "walk cards from outside, through the %s, to inside (a new scene; Ctrl+Z goes back)" % nm
		wb.pressed.connect(walk_through.bind(String(nm)))
		walk_btns[nm] = wb
		stage_body.add_child(wb)
	for sid in stairs:
		var ub := Button.new()
		ub.name = "build_walk_up_" + String(sid)
		ub.text = "Walk up the stairs" if stairs.size() == 1 else "Walk up the stairs %s" % sid
		ub.focus_mode = Control.FOCUS_NONE
		ub.tooltip_text = "walk cards from outside, up the stairs, to the floor above, feet on the steps (a new scene; Ctrl+Z goes back)"
		ub.pressed.connect(walk_up.bind(String(sid)))
		walk_btns["stairs " + String(sid)] = ub
		stage_body.add_child(ub)
	var eb := Button.new()
	eb.name = "build_edit_in_build"
	eb.text = "Edit in BUILD"
	eb.focus_mode = Control.FOCUS_NONE
	eb.pressed.connect(func(): m._page_set("BUILD"))
	stage_body.add_child(eb)


func _layout_stage() -> void:
	var cl: Rect2 = m.nav_clear_rect()
	stage_panel.reset_size()
	stage_panel.position = Vector2(cl.end.x - PANEL_W - 48.0, cl.position.y + 6.0)   # left of the view cube


## "Walk through the front door": PathWalk's cards from outside to inside, a new scene that carries the house (ONE undo step: Ctrl+Z
## puts the open scene back whole, as Path walk does)
func walk_through(name: String) -> void:
	var r := BuildStage.walk_scene(m.S, m.B, name)
	if not bool(r["ok"]):
		m._say(String(r["why"]))
		return
	var d: Dictionary = r["scene"]
	var n: int = d["cards"].size()
	m._do(func():
		m._actors_home()
		var old_s: Scene = m.S
		m.S = Scene.new()
		m.S.from_dict(d)
		m.swap_scenes = [old_s, m.S]
		m.scene_path = ""
		if m.ui_scene_name != null:
			m.ui_scene_name.text = m.S.name
		m._actors_sync()
		m.sel_card = 0
		m.ov.mark_dirty()
		m.wt.mark_dirty()
		m._dummy_hits()
		m._rebuild_cards()
		m.playhead = 0.0
		m.S.apply(m.B, 0.0)
		m._bld_scene_changed(false)
		m._props_show())
	if not m.undo.is_empty():
		m.undo[-1]["swap"] = true
	frame_door(name)
	m._say("walking through the %s: %d cards, from outside to inside at %.1f m/s. The open scene is untouched; Ctrl+Z goes back to it in one step" % [name, n, BuildStage.WALK_SPEED])


# ---------------------------------------------------------------- Piece: the picker, placing, the numbers

func _build_picker() -> void:
	picker = PanelContainer.new()
	picker.name = "build_piece_picker"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.14, 0.94)
	sb.border_color = SKY
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10)
	picker.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 5)
	picker.add_child(vb)
	var title := Label.new()
	title.name = "build_picker_title"
	title.text = "Pick a piece"
	title.add_theme_font_size_override("font_size", 17)
	vb.add_child(title)
	var hint := Label.new()
	hint.name = "build_picker_hint"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 4.0 * 104.0 + 18.0
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(1, 1, 1, 0.75)
	vb.add_child(hint)
	floor_chips = HBoxContainer.new()
	floor_chips.name = "build_piece_floors"
	vb.add_child(floor_chips)
	var group := ButtonGroup.new()
	group.allow_unpress = true
	for cat in BuildPieces.CATS:
		var cl := Label.new()
		cl.text = String(cat[0])
		cl.add_theme_font_size_override("font_size", 13)
		cl.modulate = Color(SKY, 0.95)
		vb.add_child(cl)
		var gc := GridContainer.new()
		gc.columns = 4   # four across: the fight blocks fit one row, so the picker fits a 720 px window
		gc.add_theme_constant_override("h_separation", 6)
		gc.add_theme_constant_override("v_separation", 6)
		for kd in cat[1]:
			var btn := Button.new()
			btn.name = "build_card_" + String(kd)
			btn.toggle_mode = true
			btn.button_group = group
			btn.custom_minimum_size = Vector2(104.0, 92.0)
			btn.text = String(BuildPieces.DEFS[kd]["label"])
			btn.icon = Icons.sized("piece_" + String(kd), 44)
			btn.expand_icon = false
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			btn.focus_mode = Control.FOCUS_NONE
			btn.tooltip_text = "%s: %s" % [BuildPieces.DEFS[kd]["label"], BuildPieces.DEFS[kd]["help"]]
			btn.toggled.connect(_card_toggled.bind(String(kd)))
			card_btns[String(kd)] = btn
			gc.add_child(btn)
		vb.add_child(gc)
	picker.visible = false
	m.ui_root.add_child(picker)


func _card_toggled(pressed: bool, kd: String) -> void:
	if pressed:
		piece_kind = kd
		psel = ""
		m._say("Piece: %s in hand. Click inside a room to put it down (snaps to 0.5 m); Esc puts it back" % String(BuildPieces.DEFS[kd]["label"]).to_lower())
	elif piece_kind == kd:
		piece_kind = ""
	sync()


func _sync_cards() -> void:
	for k in card_btns:
		(card_btns[k] as Button).set_pressed_no_signal(k == piece_kind)


## the picker follows the house: the floor chips (only with more than one floor), the one-line hint
func _picker_sync(has: bool) -> void:
	var nf := maxi(Building.storey_count(_bld()), 1)
	piece_floor = clampi(piece_floor, 0, nf - 1)
	var want_chips := nf + 1 if nf > 1 else 0
	if floor_chips.get_child_count() != want_chips:
		for c in floor_chips.get_children():
			floor_chips.remove_child(c)
			c.queue_free()
		if nf > 1:
			var l := Label.new()
			l.text = "On floor  "
			floor_chips.add_child(l)
			var g := ButtonGroup.new()
			for i in nf:
				var cb := Button.new()
				cb.name = "build_piece_floor_%d" % i
				cb.text = str(i + 1)
				cb.toggle_mode = true
				cb.button_group = g
				cb.focus_mode = Control.FOCUS_NONE
				cb.custom_minimum_size.x = 34.0
				cb.tooltip_text = "place pieces on floor %d" % (i + 1)
				cb.pressed.connect(func(): piece_floor = i)
				floor_chips.add_child(cb)
	for i in range(1, floor_chips.get_child_count()):
		(floor_chips.get_child(i) as Button).set_pressed_no_signal(i - 1 == piece_floor)
	var ht: Label = picker.find_child("build_picker_hint", true, false)
	var t := "Draw a room first (Room tool): pieces stand inside rooms." if not has else ("%s in hand: click inside a room." % String(BuildPieces.DEFS[piece_kind]["label"]) if piece_kind != "" else "Pick a card, then click inside a room.")
	if ht.text != t:
		ht.text = t


func _set_text(l: Label, t: String) -> void:
	if l.text != t:
		l.text = t


## the right panel while Piece is the tool: the picked piece's named numbers (rows made when the selection changes)
func _piece_panel_sync(pc: Dictionary) -> void:
	var sig := "%s|%s" % [psel, String(pc.get("kind", ""))]
	if sig != _piece_sig:
		_piece_sig = sig
		for c in piece_rows.get_children():
			piece_rows.remove_child(c)
			c.queue_free()
		piece_fields.clear()
		if not pc.is_empty():
			for key in BuildPieces.DEFS[String(pc["kind"])]["params"]:
				piece_rows.add_child(_piece_row(key, String(BuildPieces.DEFS[String(pc["kind"])]["params"][key][3])))
	var has_pc := not pc.is_empty()
	piece_rotate_btn.visible = has_pc
	piece_flip_btn.visible = has_pc and String(pc.get("kind", "")) == "stairs_l"
	piece_remove_btn.visible = has_pc
	piece_info.visible = has_pc
	if not has_pc:
		_set_text(piece_hint, "Pick a card on the left, then click inside a room. Click a piece to change its numbers." if piece_kind == "" else "%s in hand: click inside a room to put it down." % String(BuildPieces.DEFS[piece_kind]["label"]))
		return
	_set_text(piece_hint, "Numbers snap to 0.1 m. Rotate turns it a quarter. Delete takes it out.")
	var fp := BuildPieces.footprint(_bld(), pc)
	if BuildPieces.is_stairs(pc):
		var sn := BuildPieces.stairs_numbers(_bld(), pc)
		_set_text(piece_info, "%d risers of %.1f cm: the rise follows the floor height (%.2f m). %s" % [sn["n"], float(sn["r"]) * 100.0, sn["rise"], "It cuts the floor above." if Building.storey_count(_bld()) > int(pc.get("storey", 0)) + 1 else "No floor above it yet."])
	else:
		_set_text(piece_info, "Footprint %.1f x %.1f m, on floor %d" % [fp.size.x, fp.size.y, int(pc.get("storey", 0)) + 1])
	for key in piece_fields:
		var le: LineEdit = piece_fields[key]
		if not le.has_focus():
			var t := "%.1f m" % BuildPieces.value(pc, key)
			if le.text != t:
				le.text = t


func _piece_row(key: String, label: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.name = "build_piece_row_" + key
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var minus := Button.new()
	minus.text = "-"
	minus.name = "step_piece_%s_minus" % key
	var plus := Button.new()
	plus.text = "+"
	plus.name = "step_piece_%s_plus" % key
	var le := LineEdit.new()
	le.name = "num_piece_" + key
	le.custom_minimum_size.x = 64
	le.alignment = HORIZONTAL_ALIGNMENT_CENTER
	le.select_all_on_focus = true
	for bt in [minus, plus]:
		bt.focus_mode = Control.FOCUS_NONE
		bt.custom_minimum_size.x = 28
	minus.pressed.connect(_piece_step.bind(key, -1))
	plus.pressed.connect(_piece_step.bind(key, 1))
	le.text_submitted.connect(_piece_typed.bind(key, le))
	le.focus_exited.connect(func(): _piece_typed(le.text, key, le))
	piece_fields[key] = le
	h.add_child(minus)
	h.add_child(le)
	h.add_child(plus)
	return h


func _piece_step(key: String, dir: int) -> void:
	var pc := Building.piece_of(_bld(), psel)
	if not pc.is_empty():
		_piece_set(key, BuildPieces.value(pc, key) + 0.1 * dir)


func _piece_typed(txt: String, key: String, le: LineEdit) -> void:
	var s := txt.strip_edges().trim_suffix("m").strip_edges()
	if s.is_valid_float() and not Building.piece_of(_bld(), psel).is_empty():
		_piece_set(key, float(s))
	le.release_focus()


## one named number of the picked piece: snapped to 0.1 m, kept in its range, the piece must still fit its room (else nothing changes and the
## status line says why). ONE undo step
func _piece_set(key: String, v: float) -> void:
	var pc := Building.piece_of(_bld(), psel)
	if pc.is_empty():
		return
	var d: Array = BuildPieces.DEFS[String(pc["kind"])]["params"][key]
	v = clampf(snappedf(v, 0.1), d[1], d[2])
	var old := BuildPieces.value(pc, key)
	if absf(old - v) < 1e-6:
		return
	var trial: Dictionary = pc.duplicate()
	trial[key] = v
	var f := BuildPieces.fit(_bld(), trial)
	if not bool(f["ok"]):
		m._say("Piece: %s stays %.1f m: %s" % [String(d[3]).to_lower(), old, f["why"]])
		_piece_sig = ""
		return
	var what := "%s %s %.1f -> %.1f m" % [BuildPieces.DEFS[String(pc["kind"])]["label"], String(d[3]).to_lower(), old, v]
	m._step_hint = what
	m._push_undo()
	pc[key] = v
	pc["x"] = f["x"]
	pc["z"] = f["z"]
	m._say(what)
	sync()


func _piece_rotate() -> void:
	var pc := Building.piece_of(_bld(), psel)
	if pc.is_empty():
		return
	var trial: Dictionary = pc.duplicate()
	trial["yaw"] = fposmod(float(pc.get("yaw", 0.0)) + 90.0, 360.0)
	var f := BuildPieces.fit(_bld(), trial)
	if not bool(f["ok"]):
		m._say("Piece: it stays as it is: %s" % f["why"])
		return
	m._step_hint = "Piece: rotate"
	m._push_undo()
	pc["yaw"] = trial["yaw"]
	pc["x"] = f["x"]
	pc["z"] = f["z"]
	m._say("Piece: turned to %d degrees" % int(pc["yaw"]))
	sync()


func _piece_flip() -> void:
	var pc := Building.piece_of(_bld(), psel)
	if pc.is_empty() or String(pc["kind"]) != "stairs_l":
		return
	m._step_hint = "Piece: flip"
	m._push_undo()
	if bool(pc.get("flip", false)):
		pc.erase("flip")
	else:
		pc["flip"] = true
	m._say("Piece: the L stairs turn the other way")
	sync()


func _piece_remove() -> void:
	var pc := Building.piece_of(_bld(), psel)
	if pc.is_empty():
		return
	m._step_hint = "Piece: remove"
	m._push_undo()
	Building.remove_piece(_bld(), psel)
	psel = ""
	m._say("Piece: removed%s" % (", the floor above is whole again" if BuildPieces.is_stairs(pc) else ""))
	sync()


## the piece's world box (a ramp's too), for the picking ray and the outline
func _piece_aabb(pc: Dictionary) -> AABB:
	return BuildPieces.world_aabb(_bld(), pc)


## the piece under the mouse, "" if none
func pick_piece(p: Vector2) -> String:
	var o: Vector3 = m.cam.project_ray_origin(p)
	var d: Vector3 = m.cam.project_ray_normal(p)
	var best := ""
	var bt := 1e9
	for pc in _bld().get("pieces", []):
		var t := _ray_box(o, d, _piece_aabb(pc))
		if t >= 0.0 and t < bt:
			bt = t
			best = String(pc["id"])
	return best


## where the card in hand would stand for a click at floor point g: {"ok", "piece"} or {"ok": false, "why"}. Stairs and long blocks try both
## ways round (0 then 90 degrees) and take the first that fits the room
func _piece_trial(g: Vector3) -> Dictionary:
	var sn := _snap(g)
	var why := ""
	for yaw in [0.0, 90.0]:
		var pc := BuildPieces.make("p0", piece_kind, sn.x, sn.z, yaw, piece_floor)
		var f := BuildPieces.fit(_bld(), pc)
		if bool(f["ok"]):
			pc["x"] = f["x"]
			pc["z"] = f["z"]
			return {"ok": true, "piece": pc}
		why = String(f["why"])
	return {"ok": false, "why": why}


func _piece_floor_y() -> float:
	return float(piece_floor) * Building.num(_bld(), "floor_height", 2.8)


func _press_piece(p: Vector2) -> bool:
	var hit := pick_piece(p)
	if hit != "":
		psel = hit
		piece_kind = ""
		_sync_cards()
		var pc := Building.piece_of(_bld(), hit)
		m._say("Piece: %s picked. Change its numbers on the right, turn it, or press Delete" % String(BuildPieces.DEFS[String(pc["kind"])]["label"]).to_lower())
		sync()
		return true
	if piece_kind == "":
		psel = ""
		sync()
		return true
	var bd := _bld()
	if bd.is_empty() or bd.get("rooms", []).is_empty():
		m._say("Piece: draw a room first, pieces stand inside rooms")
		return true
	var g: Variant = plane_hit(p, _piece_floor_y())
	if g == null:
		return true
	var tr := _piece_trial(g)
	if not bool(tr["ok"]):
		m._say("Piece: %s" % tr["why"])
		return true
	var pc: Dictionary = tr["piece"]
	m._step_hint = "Piece: %s" % String(BuildPieces.DEFS[piece_kind]["label"])
	m._push_undo()
	var id := Building.add_piece(bd, piece_kind, float(pc["x"]), float(pc["z"]), float(pc["yaw"]), piece_floor)
	psel = id
	var np := Building.piece_of(bd, id)
	if BuildPieces.is_stairs(np):
		m._say("Piece: %s on floor %d, %d risers%s. Change its numbers on the right" % [String(BuildPieces.DEFS[piece_kind]["label"]).to_lower(), piece_floor + 1,
			BuildPieces.stairs_numbers(bd, np)["n"], ", the floor above is open over it" if Building.storey_count(bd) > piece_floor + 1 else ""])
	else:
		m._say("Piece: %s placed. Change its numbers on the right" % String(BuildPieces.DEFS[piece_kind]["label"]).to_lower())
	sync()
	return true


func _piece_hover(p: Vector2) -> void:
	if piece_kind == "" or pick_piece(p) != "":
		hover_box.visible = false
		return
	var g: Variant = plane_hit(p, _piece_floor_y())
	if g == null:
		hover_box.visible = false
		return
	var tr := _piece_trial(g)
	hover_box.visible = bool(tr["ok"])
	if hover_box.visible:
		_fit_box(hover_box, _piece_aabb(tr["piece"]), 0.02)


func _draw_piece_labels() -> void:
	var pc := Building.piece_of(_bld(), psel)
	if pc.is_empty():
		return
	var bx := _piece_aabb(pc)
	_outline_box(bx.grow(0.03))
	var txt := ""
	if BuildPieces.is_stairs(pc):
		var sn := BuildPieces.stairs_numbers(_bld(), pc)
		txt = "%s   %d steps of %.1f cm   rise %.2f m" % [BuildPieces.DEFS[String(pc["kind"])]["label"], int(sn["n"]), float(sn["r"]) * 100.0, sn["rise"]]
	else:
		txt = "%s   %.1f x %.1f x %.1f m" % [BuildPieces.DEFS[String(pc["kind"])]["label"], bx.size.x, bx.size.z, bx.size.y]
	_pill(m.cam.unproject_position(bx.get_center() + Vector3(0, bx.size.y * 0.5 + 0.35, 0)), txt, SKY, Color(0.04, 0.06, 0.1), 14)


## "Walk up the stairs": PathWalk's cards with the feet on the stairs' slope, a new scene that carries the house (ONE undo step)
func walk_up(pid: String) -> void:
	var r := BuildStage.stairs_scene(m.S, m.B, pid)
	if not bool(r["ok"]):
		m._say(String(r["why"]))
		return
	var d: Dictionary = r["scene"]
	var n: int = d["cards"].size()
	m._do(func():
		m._actors_home()
		var old_s: Scene = m.S
		m.S = Scene.new()
		m.S.from_dict(d)
		m.swap_scenes = [old_s, m.S]
		m.scene_path = ""
		if m.ui_scene_name != null:
			m.ui_scene_name.text = m.S.name
		m._actors_sync()
		m.sel_card = 0
		m.ov.mark_dirty()
		m.wt.mark_dirty()
		m._dummy_hits()
		m._rebuild_cards()
		m.playhead = 0.0
		m.S.apply(m.B, 0.0)
		m._bld_scene_changed(false)
		m._props_show())
	if not m.undo.is_empty():
		m.undo[-1]["swap"] = true
	var pc := Building.piece_of(_bld(), pid)
	var xf := BuildPieces.frame(_bld(), pc)
	m._turn_to(rad_to_deg(xf.basis.get_euler().y) + 90.0 + 28.0, -18.0, 8.0, xf.origin + Vector3(0, float(BuildPieces.stairs_numbers(_bld(), pc)["rise"]) * 0.5, 0), false)
	m._say("walking up the stairs: %d cards, feet on the steps, %.1f m/s. The open scene is untouched; Ctrl+Z goes back to it in one step" % [n, BuildStage.WALK_SPEED])


# ---------------------------------------------------------------- the labels over the view

func _pill(c: Vector2, txt: String, fill: Color, fg: Color, fs: int) -> void:
	var f := ThemeDB.fallback_font
	var sz := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var r := Rect2(c - Vector2(sz.x * 0.5 + 10.0, sz.y * 0.5 + 4.0), sz + Vector2(20.0, 8.0))
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(r.size.y * 0.5))
	ov.draw_style_box(sb, r)
	ov.draw_string(f, Vector2(r.position.x + 10.0, r.position.y + 4.0 + f.get_ascent(fs)), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fg)


## the 12 edges of a box, in the sky blue, over the view
func _outline_box(bx: AABB) -> void:
	var pts := []
	for i in 8:
		pts.append(m.cam.unproject_position(bx.position + Vector3(bx.size.x * (i & 1), bx.size.y * ((i >> 1) & 1), bx.size.z * ((i >> 2) & 1))))
	for i in 8:
		for bit in [1, 2, 4]:
			if (i & bit) == 0:
				ov.draw_line(pts[i], pts[i | bit], SKY, 2.0, true)


## a pill with a thin outline (the hint under a picked opening)
func _pill_outline(c: Vector2, txt: String, fill: Color, line: Color, fs: int) -> void:
	var f := ThemeDB.fallback_font
	var sz := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var r := Rect2(c - Vector2(sz.x * 0.5 + 10.0, sz.y * 0.5 + 4.0), sz + Vector2(20.0, 8.0))
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = line
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(r.size.y * 0.5))
	ov.draw_style_box(sb, r)
	ov.draw_string(f, Vector2(r.position.x + 10.0, r.position.y + 4.0 + f.get_ascent(fs)), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(line, 0.95))


func _draw_labels() -> void:
	if not on:
		return
	if drag == "room" and size_text != "":
		var r := drag_rect()
		var x0: float = r["x"]
		var z0: float = r["z"]
		var x1: float = x0 + float(r["w"])
		var z1: float = z0 + float(r["d"])
		var cn := [Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)]
		var sp := []
		for c in cn:
			sp.append(m.cam.unproject_position(c))
		for i in 4:
			ov.draw_line(sp[i], sp[(i + 1) % 4], SKY, 2.0)
			ov.draw_circle(sp[i], 4.5, Color.WHITE)
		ov.draw_circle(m.cam.unproject_position(Vector3(b.x, 0, b.z)), 6.0, Color("#ffc233"))
		var mid: Vector2 = m.cam.unproject_position(Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5))
		_pill(mid, size_text, Color(0.06, 0.07, 0.1, 0.92), Color.WHITE, 22)
		_pill(mid + Vector2(0, 30), area_text, Color(0, 0, 0, 0), Color(SKY, 0.95), 14)
		_pill(m.cam.unproject_position(Vector3((x0 + x1) * 0.5, 0, z1 + 0.4)), "%.1f m" % r["w"], SKY, Color(0.04, 0.06, 0.1), 14)
		_pill(m.cam.unproject_position(Vector3(x1 + 0.4, 0, (z0 + z1) * 0.5)), "%.1f m" % r["d"], SKY, Color(0.04, 0.06, 0.1), 14)
		_pill(m.cam.unproject_position(Vector3(a.x, 0, a.z)) + Vector2(-70, -26), "corner A: start", Color(0.06, 0.07, 0.1, 0.8), Color(SKY, 0.95), 12)
		if typed[0] != "" or typed[1] != "":
			_pill(mid + Vector2(0, -34), "typing:  %s  Tab  %s" % [typed[0] if typed[0] != "" else "-", typed[1] if typed[1] != "" else "-"], Color(SKY, 0.9), Color(0.04, 0.06, 0.1), 14)
	elif drag == "wall":
		_draw_wall_preview()
	elif drag == "pull":
		_draw_pull_label()
	elif tool == "Piece":
		_draw_piece_labels()
	elif tool == "Opening":
		var o := _opening(sel)
		if not o.is_empty():
			var bx := _opening_aabb(o)
			_outline_box(bx.grow(0.03))
			var wall := String(o["wall"])
			var along: Vector3 = Vector3.RIGHT if (wall == "front" or wall == "back") else Vector3.BACK
			ov.draw_circle(m.cam.unproject_position(bx.get_center() + along * (bx.size.dot(along) * 0.5 + 0.22)), 5.0, SKY)
			_pill(m.cam.unproject_position(bx.get_center() + Vector3(0, bx.size.y * 0.5 + 0.2, 0)), "%.1f m" % [Building.num(_bld(), o.get("w"), 0.9)], SKY, Color(0.04, 0.06, 0.1), 14)
			var foot := Vector3(bx.get_center().x, 0, bx.get_center().z)
			_pill_outline(m.cam.unproject_position(foot) + Vector2(0, 30), "drag to slide: snaps to %.1f m" % _grid(), Color(0.06, 0.07, 0.1, 0.85), SKY, 12)
