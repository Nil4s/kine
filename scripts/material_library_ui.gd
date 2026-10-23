class_name MaterialLibraryPanel
extends PanelContainer
## The material library picker (ROADMAP_400 E02; the presets and their pictures are scripts/material_library.gd). Opened by
## "Library..." on the Materials panel (scripts/kmesh_material_ui.gd); it sits LEFT of that panel, top aligned, inside
## the clear view, and closes with it. Rows:
##   a search box (every word must be in the name or the group: "steel", "skin", "mine")
##   the grid: a rendered sphere per preset and its name (shipped first, then the user's own)
##   Apply (or a double click): the picked slot of the Materials panel takes every field of the preset, ONE undo step
##     (with no slot yet, the slot is added in the same step)
##   Save current slot to library: the picked slot goes to the user's library (user://material_library.json)

const COL_W := 118

var pan: KMeshMaterialPanel
var lib: MaterialLibrary
var grid: ItemList
var search: LineEdit
var entries: Array = []      # the presets the grid shows, in its order
var _gen := 0                # bumps on every refill: a picture pass of an older fill stops


func _init(mat_panel: KMeshMaterialPanel) -> void:
	pan = mat_panel
	name = "matlib_panel"
	visible = false
	var st := StyleBoxFlat.new()
	st.bg_color = Tok.c("float")
	st.set_corner_radius_all(8)
	st.set_content_margin_all(8)
	add_theme_stylebox_override("panel", st)
	lib = MaterialLibrary.new()
	lib.name = "matlib"
	add_child(lib)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	add_child(vb)
	var hb0 := HBoxContainer.new()
	var title := Label.new()
	title.text = "Material library"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb0.add_child(title)
	var x := Button.new()
	x.name = "btn_matlib_close"
	x.text = "x"
	x.tooltip_text = "close the library"
	x.pressed.connect(close)
	hb0.add_child(x)
	vb.add_child(hb0)
	search = LineEdit.new()
	search.name = "matlib_search"
	search.placeholder_text = "search: steel, skin, cloth, mine..."
	search.clear_button_enabled = true
	search.text_changed.connect(func(_t): fill())
	vb.add_child(search)
	grid = ItemList.new()
	grid.name = "matlib_grid"
	grid.icon_mode = ItemList.ICON_MODE_TOP
	grid.fixed_icon_size = MaterialLibrary.SIZE
	grid.max_columns = 0
	grid.same_column_width = true
	grid.fixed_column_width = COL_W
	grid.max_text_lines = 2
	grid.custom_minimum_size = Vector2(COL_W * 3 + 30, 120)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.item_activated.connect(func(i): apply(entries[i]))
	vb.add_child(grid)
	var hb := HBoxContainer.new()
	var ap := Button.new()
	ap.name = "btn_matlib_apply"
	ap.text = "Apply"
	ap.tooltip_text = "the picked material slot takes this preset (one undo step)"
	ap.pressed.connect(func():
		var s := grid.get_selected_items()
		if s.is_empty():
			pan.ui.m._say("Model: pick a material in the library first, then Apply (or double-click it)")
		else:
			apply(entries[s[0]]))
	hb.add_child(ap)
	var sv := Button.new()
	sv.name = "btn_matlib_save"
	sv.text = "Save current slot to library"
	sv.tooltip_text = "keep the picked slot's fields as your own preset (user://material_library.json)"
	sv.pressed.connect(save_current)
	hb.add_child(sv)
	vb.add_child(hb)


func open() -> void:
	visible = true
	fill()
	place()
	search.grab_focus.call_deferred()


func close() -> void:
	visible = false
	_gen += 1


func _process(_dt: float) -> void:
	if visible and not pan.visible:
		close()
	if visible:
		place()


## left of the Materials panel, top aligned with it; as tall as the clear view allows
func place() -> void:
	var cl: Rect2 = pan.ui.m.nav_clear_rect()
	var pr := pan.get_global_rect()
	var w := get_combined_minimum_size().x
	var h := minf(420.0, cl.size.y - 24.0)
	size = Vector2(w, h)
	global_position = Vector2(maxf(cl.position.x + 12.0, pr.position.x - w - 10.0), cl.position.y + 12.0)


## the grid from the presets that match the search; their pictures come in one by one (cached ones at once)
func fill() -> void:
	_gen += 1
	var gen := _gen
	entries = []
	grid.clear()
	for e in MaterialLibrary.all():
		if MaterialLibrary.matches(e, search.text):
			entries.append(e)
			var i := grid.add_item(String(e["name"]) + (" *" if e["user"] else ""))
			grid.set_item_tooltip(i, "%s (%s)%s" % [e["name"], e["group"], "\n" + e["source"] if e["source"] != "" else ""])
			var t := lib.picture(e["slot"])
			if t != null:
				grid.set_item_icon(i, t)
	_pictures(gen)


func _pictures(gen: int) -> void:
	for i in entries.size():
		if gen != _gen or not is_inside_tree():
			return
		if grid.get_item_icon(i) != null:
			continue
		var t := await lib.thumb(entries[i]["slot"])
		if gen != _gen or i >= grid.item_count:
			return
		grid.set_item_icon(i, t)


## the picked slot of the Materials panel takes every field of the preset: ONE undo step (adds a slot first if none)
func apply(e: Dictionary) -> int:
	var m := pan.mesh()
	if m == null:
		return -1
	pan.ui.undo.begin(m)
	if m.materials.is_empty():
		pan.cur = KMeshMaterial.add(m)
	var i := clampi(pan.cur, 0, m.materials.size() - 1)
	m.materials[i] = KMeshMaterial.clean(e["slot"])
	pan.ui.undo.commit("Material preset")
	var fo := get_viewport().gui_get_focus_owner()
	if fo != null and is_ancestor_of(fo):
		fo.release_focus()   # the search box would eat the Ctrl+Z that takes this back
	pan.cur = i
	pan._after("slot %d wears the preset '%s' (Ctrl+Z takes it back)" % [i + 1, e["name"]])
	return i


## the picked slot -> the user's library (by name: a second save of the same name replaces it)
func save_current() -> bool:
	var m := pan.mesh()
	if m == null or m.materials.is_empty():
		pan.ui.m._say("Model: no material slot to save. Add one on the Materials panel first")
		return false
	var s: Dictionary = m.materials[clampi(pan.cur, 0, m.materials.size() - 1)]
	var err := MaterialLibrary.save_user(s)
	if err != OK:
		pan.ui.m._say("Model: could not write %s (%s). Check the disk has room and the folder can be written" % [MaterialLibrary.USER, error_string(err)])
		return false
	fill()
	pan.ui.m._say("Model: '%s' saved to your material library (search 'mine')" % s["name"])
	return true
