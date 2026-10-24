class_name ObjectLibrary
extends PanelContainer
## OBJECT LIBRARY (Nick, the owner: "an easy way to reach a library of objects in categories, for Easy and Expert users").
## One panel: category tabs (Weapons, Furniture, Sports, Everyday, Armour, My models), a search box that filters by name
## (across every tab while it has words), and a grid of tiles, each a thumbnail and a name. A click places the object the
## way the app already does: a weapon goes into the right hand (main._kind, as the Weapon picker does), a prop goes on the
## floor in front of the body (main._prop_add, as Add prop does), an armour plate goes over its body region (ArmourFromBody.make,
## as Model: armour does). One click is one undo step. Opened from Easy's Library button, the SET row of the STAGE page
## (ribbon "Object library..."), and the command search. The thumbnails: scripts/library_thumbs.gd (cached under user://thumbs/lib).
##
## INVENTORY (what the app could already place, before this panel; counted in inventory()):
##   Weapons: main.gd WEAPONS (line ~9476): metal bat, bo staff, long hammer, long axe, sword, longsword, katana, spear, dagger,
##     2 daggers (main._two_daggers) = 10, plus the prop "sword" (scripts/props.gd KINDS, "drops as a rigid body") = 11.
##     The weapon kinds are scripts/body.gd KINDS (line ~100-130): metal_bat, staff, long_hammer, dagger, long_axe, sword, longsword, katana, spear.
##   Props (scripts/props.gd KINDS, lines 28-110, placed by main._prop_add via the "Add prop" menu, main.gd ~11399):
##     Furniture: table, chair, stool, bench, bed = 5.   Sports: ball = 1.
##     Everyday: box, crate, moving_box, door, door_frame, wall, railing, step, step_code, stairs, stairs_code, ramp, ramp15 = 13.
##   Armour: ArmourFromBody (scripts/armour_from_body.gd, make at line 753) takes body region words; ARMOUR below = 7 plates.
##   Bodies (.kbody, scripts/body_file.gd, drawn by scripts/body_thumbs.gd) and crowd copies are not objects to place here.
##   My models: Props.EXTRA (scripts/props.gd line 114): the .glb models in user://library/props, registered by the importer.
## Totals with no models of your own: 11 + 5 + 1 + 13 + 7 = 37 built-in objects (the thin tabs are Sports and Armour).

const CATS := ["Weapons", "Furniture", "Sports", "Everyday", "Armour", "My models"]
const PROP_CAT := {"table": "Furniture", "chair": "Furniture", "stool": "Furniture", "bench": "Furniture", "bed": "Furniture",
	"ball": "Sports", "sword": "Weapons"}   # every other prop kind is Everyday
const PROP_NAME := {"ball": "Football", "sword": "Sword on the floor"}
## [name, region word]: a plate over the body region (KMeshBody.REGIONS); the words are the ones ArmourFromBody.make reads
const ARMOUR := [["Chest plate", "chest"], ["Abdomen plate", "abdomen"], ["Helmet", "head"], ["Upper arm plate (left)", "upperarm_l"],
	["Forearm plate (right)", "forearm_r"], ["Thigh plate (left)", "thigh_l"], ["Shin plate (right)", "shin_r"]]
const TILE := Vector2(124, 104)   # a 64 px picture and the name under it, two lines at most
const COLS := 4
const CHROME := 150.0             # px of the panel that is not the grid: header, search, tabs, note, margins

var m: Node                       # main (untyped, as the other panels)
var weapons: Array = []           # main's WEAPONS: [name, kind, note]
var items: Array = []             # the inventory: every object, from inventory()
var thumbs: LibraryThumbs
var tab := 0                      # the category shown when no search is typed
var query := ""                   # the search box, lower case
var _tabs: Array = []             # Button per category
var _search: LineEdit
var _scroll: ScrollContainer
var _grid: GridContainer
var _note: Label
var _pics := {}                   # item id -> TextureRect of its tile (the tiles on screen)


## main: the app; weapon_list: main's WEAPONS (the Weapons tab reads the kinds the picker reads)
func setup(main: Node, weapon_list: Array) -> void:
	m = main
	weapons = weapon_list
	items = inventory()
	thumbs = LibraryThumbs.new()
	thumbs.name = "library_thumbs"
	add_child(thumbs)
	thumbs.made.connect(_made)
	name = "object_library"
	mouse_filter = Control.MOUSE_FILTER_STOP   # a click on the panel never reaches the view behind it
	add_theme_stylebox_override("panel", _box_style())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := Label.new()
	title.text = "Object library"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Tok.c("heading"))
	head.add_child(title)
	var close := Button.new()
	close.name = "library_close"
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.tooltip_text = "close the object library (the set stays as it is)"
	close.pressed.connect(hide_panel)
	head.add_child(close)
	_search = LineEdit.new()
	_search.name = "library_search"
	_search.placeholder_text = "Search by name: sw finds the sword"
	_search.clear_button_enabled = true
	_search.tooltip_text = "filters every category by name while it has words; clicking a tab clears it"
	_search.text_changed.connect(_on_search)
	v.add_child(_search)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 2)
	v.add_child(tabs)
	var grp := ButtonGroup.new()
	for i in CATS.size():
		var b := Button.new()
		b.name = "tab_%d" % i
		b.toggle_mode = true
		b.button_group = grp
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = i == tab
		b.pressed.connect(_pick_tab.bind(i))
		tabs.add_child(b)
		_tabs.append(b)
	_scroll = ScrollContainer.new()
	_scroll.name = "library_scroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.name = "library_grid"
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_grid)
	_note = Label.new()
	_note.name = "library_note"
	_note.add_theme_font_size_override("font_size", 13)
	_note.add_theme_color_override("font_color", Tok.of("text:0.6"))
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_note)
	visible = false
	_refresh_tabs()
	_rebuild()


## the inventory: every object the library lists, one entry each (see the header for where each list comes from)
func inventory() -> Array:
	var out: Array = []
	for w in weapons:
		var kind := String(w[1])
		if kind == "":
			continue   # "None" is not an object
		out.append(_item("Weapons", String(w[0]), "weapon", kind, _weapon_shapes(kind), "weapon:" + kind))
	for k in Props.KINDS.keys():
		var cat: String = PROP_CAT.get(k, "Everyday")
		out.append(_item(cat, String(PROP_NAME.get(k, _title(k))), "prop", k, _prop_shapes(k), "prop:" + k))
	for a in ARMOUR:
		out.append(_item("Armour", String(a[0]), "armour", String(a[1]), [["box", Vector3.ZERO, Vector3(0.28, 0.28, 0.02)]], "armour:" + String(a[1])))
	for k in Props.EXTRA.keys():
		out.append(_item("My models", _title(String(k).trim_prefix("my ")), "prop", String(k), _prop_shapes(String(k)), "model:" + String(k)))
	return out


## the objects of one category (the inventory's list for it)
func in_cat(cat: String) -> Array:
	return items.filter(func(it): return it["cat"] == cat)


func item(id: String) -> Dictionary:
	for it in items:
		if it["id"] == id:
			return it
	return {}


## the tile's name, as the search sees it
func names_matching(text: String) -> Array:
	var out := []
	for it in items:
		if String(it["name"]).to_lower().contains(text.to_lower()):
			out.append(String(it["id"]))
	return out


## show the panel (under the strip, beside the left panel) and refresh its tiles
func open() -> void:
	visible = true
	fit(get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720))
	_refresh_tabs()
	_rebuild()


func hide_panel() -> void:
	visible = false


## the panel's size and place for a window of size vp: the grid takes what the strip, the search and the tabs leave
func fit(vp: Vector2) -> void:
	var top := float(m.TOP_H) + 12.0 if m != null else 86.0
	var left := float(m.lw()) + 12.0 if m != null else 12.0
	var h := clampf(vp.y - top - 12.0 - CHROME, 160.0, 460.0)
	_scroll.custom_minimum_size = Vector2(float(COLS) * (TILE.x + 8.0) + 24.0, h)
	reset_size()
	position = Vector2(minf(left, maxf(12.0, vp.x - size.x - 12.0)), top)
	reset_size()


## the tile under the mouse: place its object (one undo step); the picker's own names and undo labels
func place(id: String) -> bool:
	var it := item(id)
	if it.is_empty() or m == null:
		return false
	m._step_hint = "Library: %s" % it["name"]
	var how: String = it["how"]
	if how == "weapon":
		m._do(m._two_daggers if it["key"] == "two_daggers" else m._kind.bind(it["key"]))
		_note.text = "%s in the right hand (Ctrl+Z takes it back)" % it["name"]
		return true
	if how == "prop":
		m._prop_add(String(it["key"]))   # main pushes its own undo step, as the Add prop menu does
		_note.text = "%s on the floor in front of the body (Ctrl+Z takes it back)" % it["name"]
		return true
	# ArmourFromBody.make is ONE undo step by itself (its attach pushes it, after the plate is built): no _do around it,
	# and a plate that fails to build pushes nothing
	var r: Dictionary = ArmourFromBody.make(m, String(it["key"]), {})
	if r.has("said"):
		m._say(String(r["said"]))
	if not bool(r.get("ok", false)):
		_note.text = "%s not placed: %s" % [it["name"], String(r.get("said", ""))]
		return false
	_note.text = "%s placed over the body (Ctrl+Z takes it back)" % it["name"]
	return true


func _item(cat: String, nm: String, how: String, key: String, shapes: Array, id: String) -> Dictionary:
	return {"id": id, "cat": cat, "name": nm, "how": how, "key": key, "shapes": shapes}


## a weapon's shaft as one cylinder (Body.KINDS: its length and barrel radius, drawn a little fatter than true to read at 64 px)
static func _weapon_shapes(kind: String) -> Array:
	if kind == "two_daggers":
		return [["cyl", Vector3(-0.05, 0.15, 0.0), 0.30, 0.02], ["cyl", Vector3(0.05, 0.15, 0.0), 0.30, 0.02]]
	var k: Dictionary = Body.KINDS[kind]
	return [["cyl", Vector3(0.0, float(k["len"]) * 0.5, 0.0), float(k["len"]), maxf(float(k["r_barrel"]) * 3.0, 0.012)]]


## a prop's collision solids (Props.kind_of): boxes, balls and wedges as their boxes
static func _prop_shapes(kind: String) -> Array:
	var kd: Dictionary = Props.kind_of(kind)
	var out: Array = []
	for s in kd.get("solids", []):
		out.append(["box", Vector3(s[0]), Vector3(s[1])])
	for sp in kd.get("spheres", []):
		out.append(["ball", Vector3(sp[0]), float(sp[1])])
	for w in kd.get("wedges", []):
		out.append(["box", Vector3(w[0]), Vector3(w[1])])
	return out


static func _title(s: String) -> String:
	var t := s.replace("_", " ")
	return t.substr(0, 1).to_upper() + t.substr(1)


func _box_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Tok.c("panel")
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	return sb


func _pick_tab(i: int) -> void:
	tab = i
	query = ""
	_search.text = ""
	_rebuild()


func _on_search(t: String) -> void:
	query = t.strip_edges().to_lower()
	_rebuild()


func _refresh_tabs() -> void:
	for i in _tabs.size():
		var b: Button = _tabs[i]
		b.text = "%s %d" % [CATS[i], in_cat(CATS[i]).size()]
		b.button_pressed = i == tab and query == ""


## the tiles on screen: the current tab, or every match while the search has words
func _shown() -> Array:
	if query != "":
		return items.filter(func(it): return String(it["name"]).to_lower().contains(query))
	return in_cat(CATS[tab])


func _rebuild() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	_pics.clear()
	_refresh_tabs()
	var shown := _shown()
	for it in shown:
		_grid.add_child(_tile(it))
	if shown.is_empty():
		var empty := Label.new()
		empty.name = "library_empty"
		empty.custom_minimum_size = Vector2(TILE.x * COLS, 60)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.text = ("Nothing matches \"%s\"." % query) if query != "" else \
			"No models of your own yet. Import model... (the SET row) brings a .glb in; it is listed here."
		empty.add_theme_color_override("font_color", Tok.of("text:0.6"))
		_grid.add_child(empty)
	_note.text = "%d shown. Click a tile to place it in the set or the hand." % shown.size()


func _tile(it: Dictionary) -> Control:
	var b := Button.new()
	b.name = "tile_" + String(it["id"]).replace(":", "_")
	b.custom_minimum_size = TILE
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "%s: click to place it (one undo step)" % it["name"]
	b.set_meta("item", it["id"])
	b.pressed.connect(place.bind(String(it["id"])))
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(v)
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(LibraryThumbs.SIZE)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pic.texture = thumbs.picture(String(it["id"]))
	v.add_child(pic)
	var lab := Label.new()
	lab.text = String(it["name"])
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.add_theme_font_size_override("font_size", 12)
	lab.add_theme_color_override("font_color", Tok.of("text"))
	v.add_child(lab)
	_pics[String(it["id"])] = pic
	if pic.texture == null:
		thumbs.request(String(it["id"]), it["shapes"])   # drawn once, then read from user://thumbs/lib
	return b


func _made(id: String) -> void:
	if _pics.has(id) and is_instance_valid(_pics[id]):
		(_pics[id] as TextureRect).texture = thumbs.picture(id)
