## houses_ui.gd - MY HOUSES on the BUILD page (scripts/build/houses.gd holds the files). The top bar gets a name field, "Save house"
## and "Open house". Save writes the house under that name (the picture is drawn once, now); a name that is already a saved house asks
## IN THE PANEL (Replace / Cancel), never a modal. "Open house" shows the saved houses as cards (the library's
## pictures): a click opens one in BUILD (one undo step); each card has Rename and Delete (Delete moves the file to _trash/).
## Mouse only: the name is typed in the field, everything else is a click.
class_name HousesUI
extends Node

const CARD := Vector2(132, 150)
const COLS := 3

var bu: BuildUI
var m: Node
var name_edit: LineEdit
var save_btn: Button
var open_btn: Button
var open_panel: PanelContainer
var grid: GridContainer
var empty_label: Label
var ask_box: PanelContainer
var ask_label: Label
var open_name := ""            # the house the BUILD record was opened from or last saved as (saving it again needs no question)
var pending := ""              # the name waiting for Replace
var renaming := ""             # the card whose name is a text box now
var _lt: LibraryThumbs
var _sig := ""


func setup(b: BuildUI) -> void:
	bu = b
	m = b.m
	name = "houses_ui"
	var row: HBoxContainer = m.ui_ribbon["BUILD"]
	name_edit = LineEdit.new()
	name_edit.name = "build_house_name"
	name_edit.custom_minimum_size.x = 120
	name_edit.placeholder_text = "House name"
	name_edit.tooltip_text = "the name this house is saved under (empty: House 1, House 2, ...)"
	name_edit.text_submitted.connect(func(_t): save_pressed())
	row.add_child(name_edit)
	save_btn = m._button("Save house", save_pressed, "save this house under the name in the box; the library's My houses lists it")
	save_btn.name = "build_house_save"
	row.add_child(save_btn)
	open_btn = m._button("Open house", toggle_open, "the houses you saved: click one to edit it")
	open_btn.name = "build_house_open"
	row.add_child(open_btn)
	open_panel = _panel("build_houses_panel")
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	open_panel.add_child(vb)
	var title := Label.new()
	title.text = "My houses"
	title.add_theme_font_size_override("font_size", 17)
	vb.add_child(title)
	grid = GridContainer.new()
	grid.name = "build_houses_grid"
	grid.columns = COLS
	vb.add_child(grid)
	empty_label = Label.new()
	empty_label.name = "build_houses_empty"
	empty_label.text = "No saved houses yet. Draw one and press Save house."
	vb.add_child(empty_label)
	var close := Button.new()
	close.name = "build_houses_close"
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func(): open_panel.visible = false)
	vb.add_child(close)
	ask_box = _panel("build_house_ask")
	var ab := HBoxContainer.new()
	ask_label = Label.new()
	ask_label.name = "build_house_ask_text"
	ab.add_child(ask_label)
	var yes := Button.new()
	yes.name = "build_house_replace"
	yes.text = "Replace"
	yes.focus_mode = Control.FOCUS_NONE
	yes.pressed.connect(func(): _replace())
	ab.add_child(yes)
	var no := Button.new()
	no.name = "build_house_keep"
	no.text = "Cancel"
	no.focus_mode = Control.FOCUS_NONE
	no.pressed.connect(func(): _cancel())
	ab.add_child(no)
	ask_box.add_child(ab)


func _panel(nm: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = nm
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.14, 0.96)
	sb.border_color = BuildUI.SKY
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	p.visible = false
	m.ui_root.add_child(p)
	return p


func layout(cl: Rect2) -> void:
	if open_panel == null:
		return
	if not bu.on:
		open_panel.visible = false
		ask_box.visible = false
		return
	if open_panel.visible:
		open_panel.reset_size()
		open_panel.position = Vector2(cl.position.x + 8.0, cl.position.y + 6.0)
	if ask_box.visible:
		ask_box.reset_size()
		ask_box.position = Vector2(cl.position.x + (cl.size.x - ask_box.size.x) * 0.5, cl.position.y + 6.0)


## the buttons follow the record: Save needs a house with a room; the name box shows the house's name while it is not being typed in
func sync() -> void:
	if save_btn == null:
		return
	var bd := bu._bld()
	var has: bool = not bd.is_empty() and not bool(bd.get("readonly", false)) and not (bd.get("rooms", []) as Array).is_empty()
	m._grey(save_btn, "" if has else "draw a room first")
	if bd.is_empty() and not name_edit.has_focus():
		open_name = ""   # a scene with no house (a new one, Undo): no name carried over
		name_edit.text = ""
	if not name_edit.has_focus():
		if open_name != "" and name_edit.text.strip_edges() == "":
			name_edit.text = open_name


# ---------------------------------------------------------------- Save

func save_pressed() -> void:
	var bd := bu._bld()
	if bd.is_empty() or bool(bd.get("readonly", false)) or (bd.get("rooms", []) as Array).is_empty():
		m._say("Save house: draw a room first")
		return
	var nm := name_edit.text.strip_edges()
	if nm == "":
		nm = open_name if open_name != "" else Houses.next_name()
		name_edit.text = nm
	if Houses.exists(nm) and Houses.file_stem(nm) != Houses.file_stem(open_name):
		pending = nm
		ask_label.text = "\"%s\" is already saved. Replace it?  " % nm
		ask_box.visible = true
		return
	save_house(nm)


func _replace() -> void:
	var nm := pending
	_cancel()
	if nm != "":
		save_house(nm)


func _cancel() -> void:
	pending = ""
	ask_box.visible = false


## write the house under nm, the picture drawn once (the old picture stays when there is no renderer). Awaitable
func save_house(nm: String) -> void:
	ask_box.visible = false
	pending = ""
	var bd := bu._bld()
	var img: Image = await picture(bd)
	if Houses.save(bd, nm, img) == "":
		m._say("Save house: the folder could not be written")
		return
	open_name = nm
	if BuildStage.prop_index(m.S) < 0:
		bd["name"] = nm   # a house that is not in the set takes its saved name; one in the set keeps its kind (the set names it)
	bu.sync()
	if open_panel.visible:
		refresh()
	m._say("House saved: %s" % nm)


## the house's picture, drawn now (null when there is no renderer)
func picture(bd: Dictionary) -> Image:
	var node := Houses.picture_node(bd)
	if node == null:
		return null
	if _lt == null:
		_lt = LibraryThumbs.new()
		_lt.name = "houses_thumbs"
		m.ui_root.add_child(_lt)
	return await _lt.draw_node(node, LibraryThumbs.SIZE)


# ---------------------------------------------------------------- Open, Rename, Delete

func toggle_open() -> void:
	open_panel.visible = not open_panel.visible
	if open_panel.visible:
		refresh()


## the cards: one per saved house (the same picture and name the library shows)
func refresh() -> void:
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	var all := Houses.list()
	for h in all:
		grid.add_child(_card(h))
	empty_label.visible = all.is_empty()


func _card(h: Dictionary) -> Control:
	var nm := String(h["name"])
	var stem := Houses.file_stem(nm)
	var box := VBoxContainer.new()
	box.name = "house_box_" + stem
	var b := Button.new()
	b.name = "house_card_" + stem
	b.custom_minimum_size = CARD
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "%s: click to open it in BUILD (one undo step)" % nm
	b.pressed.connect(open_house.bind(nm))
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(v)
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(96, 96)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pic.texture = picture_of(String(h["thumb"]))
	v.add_child(pic)
	if renaming == nm:
		var le := LineEdit.new()
		le.name = "house_rename_edit"
		le.text = nm
		le.text_submitted.connect(func(t: String): _rename_to(nm, t))
		v.add_child(le)
		le.call_deferred("grab_focus")
	else:
		var lab := Label.new()
		lab.text = nm
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lab.add_theme_font_size_override("font_size", 12)
		v.add_child(lab)
	box.add_child(b)
	var r := HBoxContainer.new()
	var rn := Button.new()
	rn.name = "house_rename_" + stem
	rn.text = "Rename"
	rn.focus_mode = Control.FOCUS_NONE
	rn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rn.tooltip_text = "type a new name for %s, then Enter" % nm
	rn.pressed.connect(func(): renaming = nm; refresh())
	r.add_child(rn)
	var del := Button.new()
	del.name = "house_delete_" + stem
	del.text = "Delete"
	del.focus_mode = Control.FOCUS_NONE
	del.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	del.tooltip_text = "takes %s out of the list; the file moves to the _trash folder, never erased" % nm
	del.pressed.connect(delete_house.bind(nm))
	r.add_child(del)
	box.add_child(r)
	return box


## a picture file as a texture (null when there is none: the card shows its name alone)
static func picture_of(path: String) -> Texture2D:
	if path == "" or not FileAccess.file_exists(ProjectSettings.globalize_path(path)):
		return null
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	return ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null


## a saved house becomes the record BUILD edits (one undo step: the one it replaces is back with Undo)
func open_house(nm: String) -> bool:
	var rec := Houses.load_house(nm)
	if rec.is_empty() or bool(rec.get("readonly", false)):
		m._say("Open house: %s cannot be read here (made by a newer Kine?)" % nm)
		return false
	m._step_hint = "Open house: %s" % nm
	m._push_undo()
	BuildStage.swap_in(m.S, rec)
	open_name = nm
	name_edit.text = nm
	m.sel_prop = -1
	m._props_show()
	bu.sel = ""
	bu.psel = ""
	bu.sync()
	bu._frame_house()
	open_panel.visible = false
	m._say("Opened %s. Edit it, then Save house" % nm)
	return true


func _rename_to(old: String, nw: String) -> void:
	renaming = ""
	nw = nw.strip_edges()
	if nw != "" and nw != old:
		if Houses.rename(old, nw):
			if open_name == old:
				open_name = nw
				name_edit.text = nw
			m._say("%s is now %s" % [old, nw])
		else:
			m._say("Rename: \"%s\" is already a house" % nw)
	refresh()


func delete_house(nm: String) -> void:
	if Houses.trash(nm) != "":
		if open_name == nm:
			open_name = ""
		m._say("%s moved to the _trash folder" % nm)
	refresh()
