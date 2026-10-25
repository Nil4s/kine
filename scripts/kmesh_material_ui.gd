class_name KMeshMaterialPanel
extends PanelContainer
## The "Materials" panel of the model preview (ROADMAP_400 E01; the data is scripts/kmesh_material.gd). Top right of the
## clear view, shown while the test cube is open (KMeshEditUI.on). Rows:
##   the slot list (name and face count; a click picks the slot the fields edit)
##   Add / Remove / Assign (the selected faces; in vert / edge mode the faces whose corners are all selected) / Select
##     (the slot's faces become the selection, face mode)
##   the fields of the picked slot: name, base colour and emission colour (colour pickers), metallic, roughness, normal
##     strength, AO, emission energy, SSS (sliders), and a map per channel (a file pick; x clears it)
##   Photo: a photo material made by E15 (user://materials/<name>) fills the slot's albedo, roughness and normal maps
## Every change is ONE step of the mesh's undo (KMeshEditUI.undo, Ctrl+Z there): an add, a remove, an assign, a field
## when the slider / colour picker is let go (a drag is one step, not one per frame).

const MAPS := [["albedo_tex", "Base map"], ["metallic_tex", "Metal map"], ["roughness_tex", "Rough map"], ["normal_tex", "Normal map"],
	["ao_tex", "AO map"], ["emission_tex", "Emit map"], ["sss_tex", "SSS map"]]
const SLIDERS := [["metallic", "Metallic"], ["roughness", "Roughness"], ["normal_scale", "Normal"], ["ao", "AO"],
	["emission_energy", "Emission"], ["sss", "Subsurface"]]

var ui: KMeshEditUI
var cur := 0                 # the slot the fields edit
var list: ItemList
var fields := {}             # field key -> its control
var _box: VBoxContainer
var _open := false           # an edit (a drag, a colour pick) is open on the undo
var _sig := ""
var _quiet := false          # filling the fields from the slot: their signals do nothing
var lib_panel: MaterialLibraryPanel   # E02: the material library picker (scripts/material_library_ui.gd), made on first open


func _init(edit_ui: KMeshEditUI) -> void:
	ui = edit_ui
	name = "mat_panel"
	visible = false
	var st := StyleBoxFlat.new()
	st.bg_color = Tok.c("float")
	st.set_corner_radius_all(8)
	st.set_content_margin_all(8)
	add_theme_stylebox_override("panel", st)
	var sc := ScrollContainer.new()
	sc.name = "scroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.custom_minimum_size = Vector2(250, 0)
	sc.add_child(vb)
	var title := Label.new()
	title.text = "Materials (PBR)"
	vb.add_child(title)
	list = ItemList.new()
	list.name = "slots"
	list.custom_minimum_size = Vector2(240, 72)
	list.auto_height = true
	list.item_selected.connect(func(i): cur = i; _fill())
	vb.add_child(list)
	var hb := HBoxContainer.new()
	for b in [["Add material", "add a material slot: with faces selected it takes exactly those faces (Assign does the same later); with none selected it starts empty, and the first slot covers every face (one undo step)", func(): add_slot()],
			["Remove", "remove the picked slot: its faces go to the first slot", func(): remove_slot(cur)],
			["Assign", "give the SELECTED faces the picked slot (one undo step); the status line says how many moved", func(): assign_selection()],
			["Select", "select the faces of the picked slot", func(): select_by(cur)]]:
		var bt := Button.new()
		bt.name = "btn_mat_" + String(b[0]).get_slice(" ", 0).to_lower()   # btn_mat_add even though it now reads "Add material" (tests and the help find it by name)
		bt.text = b[0]
		bt.tooltip_text = b[1]
		bt.pressed.connect(b[2])
		hb.add_child(bt)
	vb.add_child(hb)
	var lb := Button.new()   # E02
	lb.name = "btn_mat_library"
	lb.text = "Library..."
	lb.tooltip_text = "pick a PBR preset (skin, cloth, leather, metals, wood...) for the picked slot, or save it to your library"
	lb.pressed.connect(func(): open_library())
	vb.add_child(lb)
	_box = VBoxContainer.new()
	_box.name = "fields"
	vb.add_child(_box)
	var g := GridContainer.new()
	g.columns = 2
	_box.add_child(g)
	_row(g, "Name")
	var ne := LineEdit.new()
	ne.name = "mat_name"
	ne.text_submitted.connect(func(t): set_field(cur, "name", t))
	ne.focus_exited.connect(func(): if not _quiet and ne.text != _slot_get("name", ne.text): set_field(cur, "name", ne.text))
	g.add_child(ne)
	fields["name"] = ne
	for ck in [["albedo", "Base colour"], ["emission", "Emission colour"]]:
		_row(g, ck[1])
		var cp := ColorPickerButton.new()
		cp.name = "mat_" + ck[0]
		cp.custom_minimum_size = Vector2(130, 26)   # a labelled swatch: its hex code is the text
		cp.tooltip_text = "click to pick the " + String(ck[1]).to_lower() + " (the hex code is shown)"
		cp.pressed.connect(func(): edit_begin())
		cp.color_changed.connect(func(c): cp.text = _hex(c); edit_set(ck[0], c))
		cp.popup_closed.connect(func(): edit_end("Material " + ck[1].to_lower()))
		g.add_child(cp)
		fields[ck[0]] = cp
	for sk in SLIDERS:
		_row(g, sk[1])
		var r: Array = KMeshMaterial.RANGES[sk[0]]
		var sl := HSlider.new()
		sl.name = "mat_" + sk[0]
		sl.min_value = r[0]
		sl.max_value = r[1]
		sl.step = r[2]
		sl.custom_minimum_size = Vector2(130, 20)
		sl.drag_started.connect(func(): edit_begin())
		sl.value_changed.connect(func(v): _slider(sk[0], v, sl))
		sl.drag_ended.connect(func(_c): edit_end("Material " + sk[1].to_lower()))
		g.add_child(sl)
		fields[sk[0]] = sl
	for mk in MAPS:
		_row(g, mk[1])
		var mh := HBoxContainer.new()
		var bt := Button.new()
		bt.name = "mat_" + mk[0]
		bt.text = "none"
		bt.clip_text = true
		bt.custom_minimum_size = Vector2(100, 0)
		bt.tooltip_text = "pick a picture file for the " + String(mk[1]).to_lower()
		bt.pressed.connect(func(): pick_texture(mk[0]))
		mh.add_child(bt)
		var x := Button.new()
		x.text = "x"
		x.tooltip_text = "no " + String(mk[1]).to_lower()
		x.pressed.connect(func(): set_field(cur, mk[0], ""))
		mh.add_child(x)
		g.add_child(mh)
		fields[mk[0]] = bt
	_row(g, "Photo")
	var ph := MenuButton.new()
	ph.name = "mat_photo"
	ph.text = "from a photo..."
	ph.tooltip_text = "a material made by Surface: material from a photo... fills the albedo, roughness and normal maps"
	ph.about_to_popup.connect(func():
		ph.get_popup().clear()
		for n in KMeshMaterial.photo_names():
			ph.get_popup().add_item(n)
		if ph.get_popup().item_count == 0:
			ph.get_popup().add_item("(none yet: Surface: material from a photo...)")
			ph.get_popup().set_item_disabled(0, true))
	ph.get_popup().index_pressed.connect(func(i): use_photo(ph.get_popup().get_item_text(i)))
	g.add_child(ph)


## under the S search box (and anything opened over the view after it): the panel sits with the docked panels, not on top
func _ready() -> void:
	var cmd = ui.m.get("ui_cmd")
	if cmd is Control and cmd.get_parent() == get_parent() and cmd.get_index() < get_index():
		get_parent().move_child(self, cmd.get_index())


## E02: the material library picker, left of this panel
func open_library() -> MaterialLibraryPanel:
	if lib_panel == null:
		lib_panel = MaterialLibraryPanel.new(self)
		get_parent().add_child(lib_panel)
		get_parent().move_child(lib_panel, get_index() + 1)
	lib_panel.open()
	return lib_panel


func _row(g: GridContainer, t: String) -> void:
	var l := Label.new()
	l.text = t
	g.add_child(l)


func _slot_get(k: String, dflt):
	var ms := mesh().materials if mesh() != null else []
	return ms[cur][k] if cur >= 0 and cur < ms.size() else dflt


func mesh() -> KMesh:
	return ui.mesh


func _process(_dt: float) -> void:
	var want: bool = ui.on and ui.mesh != null and ui.showing   # the Materials panel goes with the cube off its page
	if visible != want:
		visible = want
		_sig = ""
	if not visible:
		return
	if ui.uved != null and ui.uved.visible:
		ui.uved.place()   # the UV panel sits left of this one, level with its top: it follows this panel's size
	var sig := "%d %d %d %d" % [ui.undo.steps.size(), ui.undo.redos.size(), mesh().face_count(), mesh().materials.size()]
	if sig != _sig and not _open:
		_sig = sig
		refresh()
	place()


## top right of the clear view, below its top edge; never past its bottom (the list scrolls instead)
func place() -> void:
	var cl: Rect2 = ui.m.nav_clear_rect()
	var ms := get_combined_minimum_size()
	var h := minf((get_child(0).get_child(0) as Control).get_combined_minimum_size().y + 16.0, cl.size.y - 24.0)
	size = Vector2(ms.x + 14.0, h)
	if ui.m._mesh_page():   # a mesh page: the browser is off, so the left column keeps the Add primitive / model check panels; Materials takes the right edge of the window (the body and its head stay clear)
		position = Vector2(ui.m.get_viewport().get_visible_rect().size.x - size.x - 12.0, cl.position.y + 12.0)
	else:
		position = Vector2(cl.end.x - size.x - 12.0, cl.position.y + 12.0)


## the list and the fields from the mesh as it is now (after an undo too)
func refresh() -> void:
	var m := mesh()
	if m == null:
		return
	cur = clampi(cur, 0, maxi(m.materials.size() - 1, 0))
	var c := KMeshMaterial.counts(m)
	list.clear()
	for i in m.materials.size():
		list.add_item("%s  (%d faces)" % [m.materials[i]["name"], c[i]])
		list.set_item_icon(i, _swatch(m.materials[i]["albedo"]))
	if m.materials.size() > 0:
		list.select(cur)
	_box.visible = not m.materials.is_empty()
	_fill()


func _hex(c: Color) -> String:
	return "#" + c.to_html(false)


func _swatch(c: Color) -> ImageTexture:
	var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)


func _fill() -> void:
	var m := mesh()
	if m == null or cur >= m.materials.size():
		return
	var s: Dictionary = m.materials[cur]
	_quiet = true
	(fields["name"] as LineEdit).text = s["name"]
	for k in KMeshMaterial.COL_KEYS:
		(fields[k] as ColorPickerButton).color = s[k]
		(fields[k] as ColorPickerButton).text = _hex(s[k])
	for sk in SLIDERS:
		(fields[sk[0]] as HSlider).value = s[sk[0]]
	for mk in MAPS:
		var p: String = s[mk[0]]
		(fields[mk[0]] as Button).text = "none" if p == "" else p.get_file()
		(fields[mk[0]] as Button).tooltip_text = p if p != "" else "pick a picture file for the " + String(mk[1]).to_lower()
	_quiet = false


func _after(say: String) -> void:
	ui.view.mark_dirty()
	_sig = ""
	refresh()
	if say != "":
		ui.m._say("Model: " + say)


# ---------------------------------------------------------------- the edits (one undo step each)

## Add material: the new slot takes the SELECTED faces (one undo step). With no slot yet and only some faces selected, the
## rest go to a base slot made first, so the selection is not the whole mesh. Nothing selected: an empty slot.
func add_slot(over := {}) -> int:
	var fs := selected_faces()
	ui.undo.begin(mesh())
	var base := false
	if mesh().materials.is_empty() and not fs.is_empty() and fs.size() < mesh().face_count():
		KMeshMaterial.add(mesh())
		base = true
	var i := KMeshMaterial.add(mesh(), over)
	var n := KMeshMaterial.assign(mesh(), fs, i) if not fs.is_empty() else 0
	ui.undo.commit("Add material")
	cur = i
	var nm: String = mesh().materials[i]["name"]
	if not fs.is_empty():
		_after("material '%s' added and given the %d selected faces%s (Ctrl+Z takes it back; its colour is the swatch under Base colour)" % [nm, n, "; the other faces went to a new '%s' slot" % mesh().materials[0]["name"] if base else ""])
	else:
		_after("material '%s' added, empty: select faces and press Assign to give it faces (Ctrl+Z takes it back)" % nm)
	return i


func remove_slot(i: int) -> bool:
	if i < 0 or i >= mesh().materials.size():
		ui.m._say("Model: no material slot to remove. Add one first")
		return false
	var nm: String = mesh().materials[i]["name"]
	ui.undo.begin(mesh())
	KMeshMaterial.remove(mesh(), i)
	ui.undo.commit("Remove material")
	_after("material '%s' removed; its faces went to the first slot (Ctrl+Z puts it back)" % nm)
	return true


## the faces the selection covers: face mode its faces, vert / edge mode the faces whose corners are all selected
func selected_faces() -> Array:
	var sel: KMeshSelect = ui.sel
	if sel.mode == KMeshSelect.FACE:
		return sel.faces.keys()
	var vs := {}
	if sel.mode == KMeshSelect.VERT:
		vs = sel.verts
	else:
		for e in sel.edges:
			vs[e.x] = true
			vs[e.y] = true
	var out := []
	for fi in mesh().face_count():
		if sel._all_in(mesh().faces[fi], vs):
			out.append(fi)
	return out


func assign_selection(slot := -1) -> int:
	var i := cur if slot < 0 else slot
	if i < 0 or i >= mesh().materials.size():
		ui.m._say("Model: add a material slot first (Add), then Assign gives it the selected faces")
		return 0
	var fs := selected_faces()
	if fs.is_empty():
		ui.m._say("Model: nothing selected to assign. Select faces (3, then click or B), then Assign")
		return 0
	ui.undo.begin(mesh())
	var n := KMeshMaterial.assign(mesh(), fs, i)
	ui.undo.commit("Assign material")
	_after("%d faces now wear '%s' (%d were already); Ctrl+Z takes it back" % [n, mesh().materials[i]["name"], fs.size() - n])
	return n


func select_by(i: int) -> int:
	if i < 0 or i >= mesh().materials.size():
		return 0
	var sel: KMeshSelect = ui.sel
	sel.set_mode(KMeshSelect.FACE)
	sel.clear()
	for fi in KMeshMaterial.faces_of(mesh(), i):
		sel.faces[fi] = true
	ui.view.mark_dirty()
	ui.m._say("Model: %d faces of '%s' selected (face mode)" % [sel.faces.size(), mesh().materials[i]["name"]])
	return sel.faces.size()


## a whole field change, one step
func set_field(i: int, key: String, value) -> void:
	if i < 0 or i >= mesh().materials.size():
		return
	ui.undo.begin(mesh())
	KMeshMaterial.set_field(mesh(), i, key, value)
	ui.undo.commit("Material " + key.replace("_", " "))
	_after("")


## a drag: begin, any number of edit_set, end = ONE step
func edit_begin() -> void:
	if _open or mesh() == null or cur >= mesh().materials.size():
		return
	ui.undo.begin(mesh())
	_open = true


func edit_set(key: String, value) -> void:
	if _quiet or cur >= mesh().materials.size():
		return
	if not _open:   # no drag open (a typed value in the picker): its own step
		set_field(cur, key, value)
		return
	KMeshMaterial.set_field(mesh(), cur, key, value)
	ui.view.mark_dirty()


func edit_end(label: String) -> void:
	if not _open:
		return
	_open = false
	ui.undo.commit(label)
	_after("")


func _slider(key: String, v: float, sl: HSlider) -> void:
	if _quiet:
		return
	if _open:
		edit_set(key, v)
	else:   # a click on the bar or a key: no drag, so the change is its own step
		set_field(cur, key, v)


func pick_texture(key: String) -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp, *.tga, *.exr ; pictures"])
	fd.use_native_dialog = true
	fd.title = "Material map: a picture file"
	fd.file_selected.connect(func(p): set_field(cur, key, p); fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	ui.m.add_child(fd)
	fd.popup_centered(Vector2i(800, 500))


## E15: the picked slot takes a photo material's maps, one step
func use_photo(name: String) -> void:
	if cur >= mesh().materials.size():
		return
	ui.undo.begin(mesh())
	mesh().materials[cur] = KMeshMaterial.from_photo(mesh().materials[cur], name)
	ui.undo.commit("Material from a photo")
	_after("'%s' wears the photo material %s (albedo, roughness, normal maps)" % [mesh().materials[cur]["name"], name])
