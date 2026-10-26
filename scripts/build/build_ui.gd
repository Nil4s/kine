class_name BuildUI
extends Node
## THE BUILD PAGE (docs/BUILD_PLAN.md phase 1b): the page of a "building" project. A 0.5 m grid on the floor, a ghost person for
## scale, and the first tools:
##   ROOM     press on the floor = corner A, drag = a live box with "4.0 m x 3.0 m" labels, let go = the room. While dragging,
##            type the sizes: 4 Tab 3 Enter. Esc cancels. Drags snap to the grid (0.5 m; Alt = free, the Snap chip turns it off)
##   OPENING  click a wall = a door (the Door / Window toggle in the panel picks the kind); press an opening and drag along its
##            wall = slide it (snaps to 0.5 m); Delete (or the panel's Remove) takes it out and the wall fills
## The panel on the right edits the NAMED NUMBERS of the building (Wall height ...): one undo step per committed number.
## The record (Scene.building, scripts/build/building.gd) is the only truth; the mesh here is regenerated from it after every
## change. Wall / Pull / Floor / Roof / Piece / Words are on the ribbon but greyed ("coming next"). Undo: ONE main._push_undo()
## per action, taken BEFORE the record changes (a room: on release; a door: on the click; a slide: on its first move).

const SKY := Color("#73BFFF")
const PANEL_W := 250.0
const ROWS := [["Wall height", "wall_height"], ["Wall thickness", "wall_thickness"], ["Door width", "door_width"],
	["Door height", "door_height"], ["Window sill", "window_sill"]]
const TOOLS := [["Room", "ROOM: drag on the floor. Sizes snap to 0.5 m; type them for exact (4, Tab, 3, Enter). Let go to raise the walls and a floor. Undo takes it back."],
	["Opening", "OPENING: click a wall to add a door. Drag it along the wall (snaps to 0.5 m). The Remove button takes it out and fills the hole."]]
const LATER := ["Wall", "Pull", "Floor", "Roof", "Piece", "Words"]
const FLOOR_HINT := "Drag on the floor to make a room"
const HALF := 12.0   # the grid reaches this far from the origin

var m: Node
var on := false                # the BUILD page is the page
var tool := "Room"
var kind := "door"             # what the Opening tool adds
var snap_on := true
var sel := ""                  # the selected opening's id
var size_text := ""            # the live label of the drag ("4.0 m x 3.0 m"), "" when not dragging
var area_text := ""
var drag := ""                 # "", "room", "slide"
var a := Vector3.ZERO          # the room drag's corner A and the moving corner B (floor, snapped)
var b := Vector3.ZERO
var typed := ["", ""]          # typed width / depth while dragging
var field := 0
var _slide_moved := false
var _hover := {}               # the opening tool's hover: {"room", "wall", "at"} or {}

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
var fields := {}               # param -> LineEdit
var kind_btns := {}
var remove_btn: Button
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
	var clay := StandardMaterial3D.new()
	clay.albedo_color = Color(0.74, 0.76, 0.8)
	clay.roughness = 0.9
	house.material_override = clay
	root3.add_child(house)
	ghost_room = MeshInstance3D.new()
	ghost_room.name = "build_ghost_room"
	ghost_room.material_override = _glass(Color(SKY, 0.32))
	ghost_room.visible = false
	root3.add_child(ghost_room)
	sel_box = _box_node("build_sel", Color(SKY, 0.55))
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
		var col := Color(0.42, 0.5, 0.62, 0.55) if major else Color(0.3, 0.35, 0.43, 0.32)
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
	var mt := _glass(Color(0.78, 0.82, 0.9, 0.7), false)
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
	p.position = Vector3(-1.2, 0, 1.0)
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
		tool_btns[t[0]] = btn
		row.add_child(btn)
	for t in LATER:
		var btn: Button = m._button(t, func(): pass, "%s: " % t)
		btn.name = "build_tool_" + t.to_lower()
		m._grey(btn, "coming next")
		row.add_child(btn)
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
		vb.add_child(_num_row(r[0], r[1]))
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
	le.focus_entered.connect(le.select_all.call_deferred)   # a click in the field takes the whole number: typing replaces it
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


## the page was set (main._page_set): BUILD's grid / person / labels show on BUILD only; the house shows on every page
func page_changed(from: String, to: String) -> void:
	var was := on
	on = to == "BUILD"
	if on and not was:
		_grid_was = m.grid_node.visible if m.grid_node != null else true
		if m.grid_node != null:
			m.grid_node.visible = false
		m._turn_to(-28.0, -32.0, 13.0, Vector3(2.0, 0.4, 1.5), false)
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
	if bd.is_empty() or bool(bd.get("readonly", false)) or bd.get("rooms", []).is_empty():
		house.mesh = null
	else:
		house.mesh = Building.to_array_mesh(bd)
	if sel != "" and _opening(sel).is_empty():
		sel = ""
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
	panel.visible = on and has
	panel_title.text = ("%s" % String(o.get("kind", "")).capitalize() + "   (selected)") if not o.is_empty() else "Building"
	(kind_btns["door"].get_parent() as Control).visible = tool == "Opening"
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
	chip.visible = on
	if on:
		chip.reset_size()
		chip.position = Vector2(cl.position.x + 12.0, cl.end.y - chip.size.y - 6.0)


func _process(_dt: float) -> void:
	if on:
		_layout()
		if drag != "":
			ov.queue_redraw()


# ---------------------------------------------------------------- the tools

func _pick_tool(t: String) -> void:
	tool = t
	drag = ""
	if m.cur_page != "BUILD":
		m._page_set("BUILD")
	for k in tool_btns:
		(tool_btns[k] as Button).set_pressed_no_signal(k == t)
	for tl in TOOLS:
		if tl[0] == t:
			m._say(tl[1])
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
	var label := ""
	for r in ROWS:
		if r[1] == key:
			label = r[0]
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


## the wall under the mouse: {"room", "wall", "at"} (at: metres from the wall's centre, snapped), or {}
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
		var h := Building.num(_bld(), r.get("height"), 2.7)
		var t := clampf(Building.num(_bld(), r.get("thickness"), 0.2), 0.01, minf(w, dd) * 0.5 - 0.01)
		var slabs := {"front": AABB(Vector3(x, 0, z), Vector3(w, h, t)), "back": AABB(Vector3(x, 0, z + dd - t), Vector3(w, h, t)),
			"left": AABB(Vector3(x, 0, z), Vector3(t, h, dd)), "right": AABB(Vector3(x + w - t, 0, z), Vector3(t, h, dd))}
		for wall in slabs:
			var tt := _ray_box(o, d, slabs[wall])
			if tt >= 0.0 and tt < bt:
				bt = tt
				var hit := o + d * tt
				var along_x: bool = wall == "front" or wall == "back"
				var centre := (x + w * 0.5) if along_x else (z + dd * 0.5)
				var pos := hit.x if along_x else hit.z
				best = {"room": String(r["id"]), "wall": wall, "at": _snap_along(pos) - centre}
	return best


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
			_slide_moved = true   # its undo step is this click's
			m._say("Opening: a %s on the %s wall. Drag it along the wall to slide it" % [kind, w["wall"]])
			sync()
			return true
		sel = ""
		sync()
		return true
	return false


func _release() -> bool:
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
	var along_x: bool = wall == "front" or wall == "back"
	var plane := 0.0
	match wall:
		"front": plane = z + t * 0.5
		"back": plane = z + dd - t * 0.5
		"left": plane = x + t * 0.5
		_: plane = x + w - t * 0.5
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
	return false


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
	elif tool == "Opening":
		var o := _opening(sel)
		if not o.is_empty():
			var bx := _opening_aabb(o)
			_pill(m.cam.unproject_position(bx.get_center() + Vector3(0, bx.size.y * 0.5 + 0.2, 0)), "%.1f m" % [Building.num(_bld(), o.get("w"), 0.9)], SKY, Color(0.04, 0.06, 0.1), 14)
			if drag == "slide":
				_pill(m.cam.unproject_position(Vector3(bx.get_center().x, 0, bx.position.z)) + Vector2(0, 28), "drag to slide: snaps to 0.5 m", Color(0.06, 0.07, 0.1, 0.85), Color(SKY, 0.95), 12)
