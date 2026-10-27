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
## CATEGORY BROWSER (Nick: "monkey-brain easy"): the left column is the category list, Recent on top; the right is a grid of big picture
## cards. The six categories above are the built-in ones (CATS, the inventory); the BUILD ones come after them (EXTRA_CATS: BUILD's
## own pieces, Fight blocks / Stairs / Furniture, as "piece:<kind>" props, BuildPieceKinds; and the house being drawn, placed as a
## set as BUILD's Use in a scene does). catalog() lists all of them: every object is in exactly one category (group_of). The search
## filters the whole catalog. Recent is the last RECENT_MAX objects placed, kept in user://library_recent.json.
## Totals with no models of your own: 11 + 5 + 1 + 13 + 7 = 37 built-in objects (the thin tabs are Sports and Armour).

const CATS := ["Weapons", "Furniture", "Sports", "Everyday", "Armour", "My models"]
const TAB_TIPS := {   # the tab tooltips: what the tab holds and what a click on its tiles does
	"Weapons": "Weapons: swords, bats, staffs, spears, daggers. A click puts one in his right hand",
	"Furniture": "Furniture: chairs, tables, stools and the like. A click puts one on the floor in front of him",
	"Sports": "Sports gear: balls, bats and kit. A click puts one on the floor in front of him",
	"Everyday": "Everyday things: cups, bags, bottles and more. A click puts one on the floor in front of him",
	"Armour": "Armour plates. A click fits one to his body",
	"My models": "Models you have added yourself. A click puts one on the floor in front of him",
}
const PROP_CAT := {"table": "Furniture", "chair": "Furniture", "stool": "Furniture", "bench": "Furniture", "bed": "Furniture",
	"ball": "Sports", "sword": "Weapons"}   # every other prop kind is Everyday
## the tile names of the props whose kind name reads as jargon (step_code, ramp15, door_frame ...); every other kind is its _title
const PROP_NAME := {"ball": "Football", "sword": "Sword (on the floor)", "step": "Step", "step_code": "Box step", "stairs": "Stairs",
	"stairs_code": "Stairs (4 steps)", "ramp": "Ramp", "ramp15": "Gentle ramp", "moving_box": "Box (moves)", "door_frame": "Doorway"}
## [name, region word]: a plate over the body region (KMeshBody.REGIONS); the words are the ones ArmourFromBody.make reads
const ARMOUR := [["Chest plate", "chest"], ["Abdomen plate", "abdomen"], ["Helmet", "head"], ["Upper arm plate (left)", "upperarm_l"],
	["Forearm plate (right)", "forearm_r"], ["Thigh plate (left)", "thigh_l"], ["Shin plate (right)", "shin_r"]]
const EXTRA_CATS := ["Fight blocks", "Build stairs", "Build furniture", "My houses"]   # BUILD's categories (BuildPieces.CATS), after the built-in ones
const EXTRA_TIPS := {
	"Fight blocks": "Fight blocks: pillars, fences, ramps and platforms to fight on and around. A click puts one on the floor in front of him",
	"Build stairs": "Stairs from BUILD, with real steps he can climb. A click puts one on the floor in front of him",
	"Build furniture": "Tables, benches and crates from BUILD. A click puts one on the floor in front of him",
	"My houses": "The houses you saved in BUILD, and the one you are drawing. A click puts one in the set",
}
const PIECE_CAT := {"Stairs": "Build stairs", "Furniture": "Build furniture", "Fight blocks": "Fight blocks"}   # BuildPieces.CATS name -> the column's name
const CAT_PIC := {"Furniture": "prop:chair", "Build furniture": "build:crate"}   # the category tile's picture, where the first object would repeat another category's
const RECENT := "Recent"
const RECENT_MAX := 12
const PIC := 112                   # the picture as shown (the 128 px render, scaled): the tile holds it and its name
const TILE := Vector2(132, PIC + 44)   # the picture and the name under it, two lines at most (B8b: nothing spills)
const COLS := 3
const EASY_PIC := 136              # Easy: bigger cards, same grid
const EASY_TILE := Vector2(156, EASY_PIC + 52)
const SIDE_W := 128.0              # the category column's width
const EASY_SIDE_W := 336.0         # Easy: the category tiles, three across: big pictures (EASY_CAT_W x EASY_CAT_H), all in view without a scroll
const EASY_CAT_W := 108.0
const EASY_CAT_H := 88.0
const CHROME := 150.0             # px of the panel that is not the grid: header, search, tabs, note, margins

var m: Node                       # main (untyped, as the other panels)
var weapons: Array = []           # main's WEAPONS: [name, kind, note]
var items: Array = []             # the inventory: every object, from inventory()
var more: Array = []              # the BUILD objects, from extra_items(): pieces and the house; items + more = catalog()
var view := ""                    # "" = the built-in category tab; RECENT or one of EXTRA_CATS = that column entry is shown
var recent_file := "user://library_recent.json"
var _recent: Array = []           # ids, newest first
var _side_btns := {}              # column entry name (RECENT, EXTRA_CATS) -> its Button
var _cat_btns: Array = []         # every column entry (Recent, the six built-in, the BUILD ones), in column order
var _side_col: VBoxContainer      # Expert: the thin list
var _cat_grid: GridContainer      # Easy: the category tiles, three across (the column's other child is Expert's list)
var _cat_req := {}                # the representative items whose picture was asked for (Easy's category tiles)
var thumbs: LibraryThumbs
var tab := 0                      # the category shown when no search is typed
var query := ""                   # the search box, lower case
var _tabs: Array = []             # Button per category
var _search: LineEdit
var _scroll: ScrollContainer
var _side: ScrollContainer
var _grid: GridContainer
var _note: Label
var _pics := {}                   # item id -> TextureRect of its tile (the tiles on screen)
var _armour_hash := ""            # the hash of its rest vertices, once per open (the spec of every armour tile)
var _fit_key := ""                # the window size and the bottom panel's height the panel was last fitted to
var _tile_cache := {}             # tile key (id, Easy, placeholder caption) -> its built Button: a tab's tiles are kept, not rebuilt
var _tile_sig := ""               # what the cached tiles were built from (every object's id, name, category, picture): a change clears them
var _armour_sb: Array = []        # the fighter body the plates are cut from, read once per open (body_source)
var _armour_built := {}           # the plate words -> its built node's mesh, once per open


## main: the app; weapon_list: main's WEAPONS (the Weapons tab reads the kinds the picker reads)
func setup(main: Node, weapon_list: Array) -> void:
	m = main
	weapons = weapon_list
	items = inventory()
	more = extra_items()
	_recent = _recent_read()
	thumbs = LibraryThumbs.new()
	thumbs.name = "library_thumbs"
	add_child(thumbs)
	thumbs.made.connect(_made)
	thumbs.warm.call_deferred()   # the stage and its first render are paid at start, not in the first open's frames
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
	_search.placeholder_text = "Search: sword, chair, football..."
	_search.clear_button_enabled = true
	_search.tooltip_text = "filters every category by name while it has words; clicking a category button clears it"
	_search.text_changed.connect(_on_search)
	v.add_child(_search)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	_side = ScrollContainer.new()
	_side.name = "library_side"
	_side.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_side.custom_minimum_size = Vector2(SIDE_W, 0)
	body.add_child(_side)
	var col := VBoxContainer.new()
	_side_col = col
	col.add_theme_constant_override("separation", 3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side.add_child(col)
	_cat_grid = GridContainer.new()
	_cat_grid.name = "library_cats"
	_cat_grid.columns = 3
	_cat_grid.add_theme_constant_override("h_separation", 6)
	_cat_grid.add_theme_constant_override("v_separation", 6)
	_cat_grid.visible = false
	_side.add_child(_cat_grid)
	var grp := ButtonGroup.new()
	var rb := _side_button(RECENT, grp)
	rb.pressed.connect(_pick_view.bind(RECENT))
	col.add_child(rb)
	for i in CATS.size():
		var b := _side_button(CATS[i], grp)
		b.name = "tab_%d" % i
		b.pressed.connect(_pick_tab.bind(i))
		col.add_child(b)
		_tabs.append(b)
		if CATS[i] == "Armour":   # the BUILD categories sit between Armour and My models
			for c in EXTRA_CATS:
				var eb := _side_button(c, grp)
				eb.pressed.connect(_pick_view.bind(c))
				col.add_child(eb)
	_scroll = ScrollContainer.new()
	_scroll.name = "library_scroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_scroll)
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
		if bool(Props.EXTRA[k].get("piece", false)) or bool(Props.EXTRA[k].get("building", false)):
			continue   # a BUILD piece or house is listed by extra_items(), not a model of the user's own
		out.append(_item("My models", _title(String(k).trim_prefix("my ")), "prop", String(k), _prop_shapes(String(k)), "model:" + String(k)))
	return out


## the BUILD objects: each BuildPieces piece (a prop kind "piece:<kind>", BuildPieceKinds) in BUILD's own category, and the house being
## drawn (when it has a room) as one set
func extra_items() -> Array:
	var out: Array = []
	for c in BuildPieces.CATS:
		for k in c[1]:
			var kind := BuildPieceKinds.ensure(String(k))
			if kind == "":
				continue
			out.append(_item(String(PIECE_CAT.get(c[0], c[0])), String((BuildPieces.DEFS[k] as Dictionary)["label"]), "piece", kind, _prop_shapes(kind), "build:" + String(k)))
	var saved := {}   # the saved houses (Houses): My houses lists each with its picture; the house open in BUILD is listed once, by its saved name
	for h in Houses.list():
		var rec: Dictionary = h["record"]
		if bool(rec.get("readonly", false)) or (rec.get("rooms", []) as Array).is_empty():
			continue
		saved[String(h["name"])] = true
		var sh: Array = []
		for bx in Building.collision_boxes(rec):
			sh.append(["box", (bx["xf"] as Transform3D).origin, (bx["half"] as Vector3) * 2.0])
		var si := _item("My houses", String(h["name"]), "house", BuildStage.kind_of_building(rec), sh, "house:saved:" + String(h["name"]))
		si["saved"] = String(h["name"])
		si["thumb"] = String(h["thumb"])
		out.append(si)
	if m != null and m.S != null and not (m.S.building as Dictionary).is_empty() and not (m.S.building.get("rooms", []) as Array).is_empty() and not bool(m.S.building.get("readonly", false)) 			and not saved.has(String(m.S.building.get("name", "Untitled"))):
		var b: Dictionary = m.S.building
		var kind := BuildStage.kind_of_building(b)
		var boxes: Array = Building.collision_boxes(b)
		var shapes: Array = []
		for bx in boxes:
			shapes.append(["box", (bx["xf"] as Transform3D).origin, (bx["half"] as Vector3) * 2.0])
		out.append(_item("My houses", "House: %s" % String(b.get("name", "Untitled")), "house", kind, shapes, "house:" + kind))
	return out


## every object the library lists: the inventory and the BUILD objects
func catalog() -> Array:
	return items + more


## the column entry an object is listed under: its category (the six built-in ones, then EXTRA_CATS)
func group_of(it: Dictionary) -> String:
	return String(it["cat"])


func in_group(cat: String) -> Array:
	return catalog().filter(func(it): return group_of(it) == cat)


## the objects placed last, newest first (ids still in the catalog)
func recent_items() -> Array:
	var out: Array = []
	for id in _recent:
		var it := item(String(id))
		if not it.is_empty():
			out.append(it)
	return out


func _recent_read() -> Array:
	if not FileAccess.file_exists(recent_file):
		return []
	var d = JSON.parse_string(FileAccess.get_file_as_string(recent_file))
	var out: Array = []
	if d is Array:
		for x in d:
			if x is String and out.size() < RECENT_MAX:
				out.append(x)
	return out


func _recent_add(id: String) -> void:
	_recent.erase(id)
	_recent.push_front(id)
	while _recent.size() > RECENT_MAX:
		_recent.pop_back()
	var f := FileAccess.open(recent_file, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_recent))
		f.close()


func clear_recent() -> void:
	_recent = []
	if FileAccess.file_exists(recent_file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(recent_file))


## the objects of one category (the inventory's list for it)
func in_cat(cat: String) -> Array:
	return items.filter(func(it): return it["cat"] == cat)


func item(id: String) -> Dictionary:
	for it in catalog():
		if it["id"] == id:
			return it
	return {}


## the tile's name, as the search sees it
func names_matching(text: String) -> Array:
	var out := []
	for it in catalog():
		if String(it["name"]).to_lower().contains(text.to_lower()):
			out.append(String(it["id"]))
	return out


## show the panel (under the strip, beside the left panel) and refresh its tiles
func open() -> void:
	items = inventory()   # the list is read again on every open: a model exported or used as a prop since the last open is listed
	more = extra_items()   # ... and the house as BUILD has it now
	if m != null:
		_recent = _recent_read()
	_armour_sb = []
	_armour_built = {}
	_armour_hash = ""
	visible = true
	fit(get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(1280, 720))
	_cat_req = {}
	_refresh_tabs()
	_rebuild()


func hide_panel() -> void:
	visible = false


## refit when the window or the bottom panel changes size (a resize, Easy's strip coming or going), not only on open
func _process(_dt: float) -> void:
	if not visible or m == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var key := "%s|%s" % [str(vp), str(m.bottom_h)]
	if key != _fit_key:
		_fit_key = key
		fit(vp)


## the panel's size and place for a window of size vp: the grid takes what the strip, the search and the tabs leave
func fit(vp: Vector2) -> void:
	var top := float(m.TOP_H) + 12.0 if m != null else 86.0
	var left := float(m.lw()) + 12.0 if m != null else 12.0
	var low := low_edge(vp, float(m.bottom_h), float(m.LINE_H)) if m != null else vp.y - 120.0
	var h := clampf(low - top - CHROME, 160.0, 460.0)
	_scroll.custom_minimum_size = Vector2(_grid_min_w(), h)
	reset_size()
	var over := top + size.y - low   # the panel's own rows (header, search, tabs, note) are more than CHROME on a short window: the grid gives way
	if over > 0.0 and h > 160.0:
		_scroll.custom_minimum_size.y = maxf(160.0, h - over)
		reset_size()
	position = Vector2(minf(left, maxf(12.0, vp.x - size.x - 12.0)), top)
	reset_size()


## the lowest y a panel beside the body may reach: 8 px above the welcome line, which sits above the status line and the
## scene panel (the bottom panel's height, the status line's band). Easy's picker and the library both stop there
static func low_edge(vp: Vector2, bottom_h: float, line_h: float) -> float:
	return vp.y - bottom_h - 6.0 - line_h - float(MouseHint.H) - 2.0 - 8.0


## the tile under the mouse: place its object (one undo step); the picker's own names and undo labels
func place(id: String) -> bool:
	var it := item(id)
	if it.is_empty() or m == null:
		return false
	m._step_hint = "Library: %s" % it["name"]
	m._step_easy = String(it["name"]) if m.easy.on else ""   # Easy's undo step is the tile's name ("Undo: Sword")
	var ok := _place_item(it)
	m._step_easy = ""
	if ok:
		_recent_add(id)
	return ok


func _place_item(it: Dictionary) -> bool:
	var how: String = it["how"]
	if how == "weapon":
		var pick: Callable = m._two_daggers if it["key"] == "two_daggers" else m._kind.bind(it["key"])
		m._do(func():
			pick.call()
			arm_cards(m.S, m.B)
			if m.easy.on:   # Easy: the live pose at the pick is clear of the body too (see _clear_live)
				_clear_live(m.B))
		if m.easy.on:   # Easy: the plain line (no undo key, no weights)
			_note.text = m.easy_holds(String(it["key"]))
		else:
			_note.text = "%s: right hand%s, Ctrl+Z undoes" % [it["name"], " in every card" if not m.S.cards.is_empty() else ""]
		return true
	if how == "house":
		return _place_house(it)
	if how == "prop" or how == "piece":
		m._prop_add(String(it["key"]))   # main pushes its own undo step, as the Add prop menu does
		_note.text = ("%s is on the floor. Undo takes it away." if m.easy.on else "%s: on the floor, Ctrl+Z undoes") % it["name"]
		return true
	# ArmourFromBody.make is ONE undo step by itself (its attach pushes it, after the plate is built): no _do around it,
	# and a plate that fails to build pushes nothing
	var r: Dictionary = load("res://scripts/armour_from_body.gd").make(m, String(it["key"]), {})
	if r.has("said"):
		m._say(String(r["said"]))
	if not bool(r.get("ok", false)):
		_note.text = "%s not placed: %s" % [it["name"], String(r.get("said", ""))]
		return false
	_note.text = ("%s is on him now. Undo takes it away." if m.easy.on else "%s placed over the body (Ctrl+Z takes it back)") % it["name"]
	return true


## the house being drawn goes into the set (BUILD's Use in a scene: one undo step); a house already in the set is not added twice
func _place_house(it: Dictionary) -> bool:
	if it.has("saved"):
		return _place_saved(String(it["saved"]), String(it["name"]))
	if BuildStage.prop_index(m.S) >= 0:
		_note.text = "That house is already in the set."
		return false
	m._push_undo()
	var kind := BuildStage.use(m.S)
	if kind == "":
		m.undo.pop_back()
		_note.text = "Draw a room in BUILD first."
		return false
	m.sel_prop = -1
	m._props_show()
	_note.text = ("%s is in the set. Undo takes it away." if m.easy.on else "%s is in the set (Ctrl+Z takes it back)") % it["name"]
	return true


## a saved house (My houses) goes into the set exactly as Use in a scene does: it becomes the scene's house, one undo step. A scene has
## one house: another house's prop in the set is replaced; the same house twice is refused
func _place_saved(nm: String, label: String) -> bool:
	var rec := Houses.load_house(nm)
	if rec.is_empty() or bool(rec.get("readonly", false)):
		_note.text = "%s cannot be read here." % label
		return false
	if BuildStage.prop_index(m.S) >= 0 and BuildStage.kind_of_building(m.S.building) == BuildStage.kind_of_building(rec):
		_note.text = "That house is already in the set."
		return false
	m._push_undo()
	BuildStage.swap_in(m.S, rec)
	var kind := BuildStage.use(m.S)
	if kind == "":
		m.undo.pop_back()
		_note.text = "%s has no room to put in the set." % label
		return false
	m.sel_prop = -1
	m._props_show()
	m.bld.sync()
	_note.text = ("%s is in the set. Undo takes it away." if m.easy.on else "%s is in the set (Ctrl+Z takes it back)") % label
	return true


## the weapon the body holds now into EVERY card of the scene: a card is the whole pose (Scene.put turns the weapon off on a
## card without one), so a weapon picked on the body alone vanished as soon as the clip played (the monkey test: "give him a
## sword" while the punch plays). Each card keeps its own pose; the weapon rides in its hand. The body is left as it was
## A card's result depends on its pose, the held weapon and the body's sizes only, so it is kept (_arm_memo, found by hash and
## checked with ==): the same clip built again with the same weapon in hand (Run twice, Start over) does not clear each card again
static var _arm_memo := {}


static func arm_cards(S: Scene, B: Body) -> void:
	if S.cards.is_empty():
		return
	var held := PoseBake.held_of(B)
	var keep := B.state()
	for c in S.cards:
		# exactly what the result depends on: Scene.put reads the pose's joints and offset; its own weapon is overwritten by the held
		# one (held_of holds every wep*/grip* key _state0 has), so the pose's old weapon is NOT in the key (a weapon toggle that
		# ends in the same state hits); free_hand is the one state key put and held leave as the body has it
		var key := [c["pose"]["joints"], c["pose"].get("offset", [0, 0, 0]), held, B.rad, B.free_hand]
		var hk := hash(key)
		var hit = _arm_memo.get(hk)
		if hit != null and hit[0] == key:
			c["pose"]["weapon"] = (hit[1] as Dictionary).duplicate(true)
			if hit[2] != null:
				c["pose"]["weapon2"] = (hit[2] as Dictionary).duplicate(true)
			else:
				(c["pose"] as Dictionary).erase("weapon2")
			continue
		var key_copy := key.duplicate(true)
		Scene.put(B, Moves._flat(c["pose"]))
		var s0 := B._state0()
		s0.merge(held, true)
		B._set_state0(s0)
		_clear_body(B)
		var w1 := B.weapon_dict()   # not a whole B.to_dict(): the joints and the contacts were 40 of the 64 ms per Run
		var w2 = B.wep2_dict() if B.wep2_on else null
		c["pose"]["weapon"] = w1
		if w2 != null:
			c["pose"]["weapon2"] = w2
		else:
			(c["pose"] as Dictionary).erase("weapon2")
		if _arm_memo.size() > 600:
			_arm_memo.clear()
		_arm_memo[hk] = [key_copy, w1.duplicate(true), (w2 as Dictionary).duplicate(true) if w2 != null else null]
	B.set_state(keep)
	B.fk()


## EASY, AT THE PICK (walk-through item 5): arm_cards turns the weapon clear of the body in each CARD's pose only, and the live
## pose keeps the weapon as it was picked, so the frozen pick-time pose showed the sword through the head (red = the touch tint).
## The live weapon is turned clear the same way (_clear_body), so the pose at the pick shows no red
static func _clear_live(B: Body) -> void:
	_clear_body(B)
	B.fk()


## the held weapon's contacts with the body in the pose now (Body.contacts, the test that stops a joint at the weapon):
## the number of body parts the weapon's parts sink into
static func _wep_hits(B: Body) -> int:
	# the same count as the weapon rows of B.contacts(), but only the weapon's own pairs are measured (the search below asks
	# this up to hundreds of times per card; the body's other pairs and skin points do not move with the weapon)
	var n := 0
	for pr in B.pairs:
		if not (pr[0] in Body.WEAPON or pr[1] in Body.WEAPON):
			continue
		if not B.wep_on or (not B.wep2_on and (pr[0] in Body.WEAPON2 or pr[1] in Body.WEAPON2)):
			continue
		if B.wep_on and B.grip and pr[0].begins_with("hand") and pr[1].begins_with("hand"):
			continue
		if B.depth(pr[0], pr[1]) - float(B.allow.get(pr[0] + "|" + pr[1], 0.0)) > 0.001:
			n += 1
	var mv := {}
	for w in Body.WEAPON:
		mv[w] = true
	for sc in B.skin_raw(mv):
		if String(sc[1]) in Body.WEAPON and float(sc[2]) - float(B.allow.get("skin:" + sc[0] + "|" + sc[1], 0.0)) > 0.001:
			n += 1
	return n


static func _wep_hits_slow(B: Body) -> int:
	var n := 0
	for c in B.contacts():
		if (String(c[0]) in Body.WEAPON or String(c[1]) in Body.WEAPON) and float(c[2]) > 0.001:
			n += 1
	return n


## a weapon that goes into the body in this pose is turned IN THE HAND, about the palm, by the smallest angle that clears
## it: the hand, fingers and body stay where they are (only the weapon's own place in the hand changes). Angles grow by
## 2 degrees; each size is tried in 10-degree steps round the shaft's two cross axes. No clear angle: the weapon stays
## as it was (the blade then stays in the body, and the Check tests show it)
static func _clear_body(B: Body) -> void:
	if not B.wep_on or B.wep_hand == "" or _wep_hits(B) == 0:
		return
	var h := B.wep_hand
	var pivot := B.palm_point(h)
	var x := B.wep_xform()
	var p0: Vector3 = x[0]
	var r0: Quaternion = x[1]
	var e1 := r0 * Vector3.RIGHT
	var e2 := r0 * Vector3.BACK
	var keep := [p0, r0]
	# first the hand's own roll: about the wrist-to-palm line, which keeps the grip where it was against both the wrist and
	# the palm (the knob does not ride along the hand through the clip, as a turn about the palm alone made it: 2 cm)
	var roll: Vector3 = (pivot - B.P[h]).normalized()
	if roll.length() > 0.5:
		for deg in range(5, 181, 5):
			for sgn in [1.0, -1.0]:
				var rr := Quaternion(roll, deg_to_rad(float(deg) * sgn))
				B.wep_hand = ""
				B.wep_pos = pivot + rr * (p0 - pivot)
				B.wep_rot = (rr * r0).normalized()
				B.lock_weapon(h)
				B.fk()
				if _wep_hits(B) == 0:
					return
	var mag := 2.0
	while mag <= 180.0:
		for k in 36:
			var phi := deg_to_rad(10.0 * k)
			var axis := (e1 * cos(phi) + e2 * sin(phi)).normalized()
			var rw := Quaternion(axis, deg_to_rad(mag))
			B.wep_hand = ""
			B.wep_pos = pivot + rw * (p0 - pivot)
			B.wep_rot = (rw * r0).normalized()
			B.lock_weapon(h)
			B.fk()
			if _wep_hits(B) == 0:
				return
		mag += 2.0
	B.wep_hand = ""
	B.wep_pos = keep[0]
	B.wep_rot = keep[1]
	B.lock_weapon(h)
	B.fk()


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


func _side_button(nm: String, grp: ButtonGroup) -> Button:
	var b := Button.new()
	b.name = "cat_" + nm.replace(" ", "_").to_lower()
	b.text = nm   # the name alone: the count is in the tooltip
	b.toggle_mode = true
	b.button_group = grp
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 30)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if nm == RECENT or EXTRA_CATS.has(nm):
		_side_btns[nm] = b
	b.set_meta("cat", nm)
	_cat_btns.append(b)
	return b


## Easy: the category column is the picture tiles (big, the picture on the left); Expert keeps its thin list. The grid is then
## empty until a tile is picked (Easy start shows only the category tiles), and a Back tile returns to that.
func _easy() -> bool:
	return m != null and m.easy != null and m.easy.on


func _layout_mode() -> void:
	var easy := _easy()
	var col: Control = _side_col
	col.visible = not easy
	_cat_grid.visible = easy
	_side.custom_minimum_size = Vector2(EASY_SIDE_W if easy else SIDE_W, 0)
	var to: Node = _cat_grid if easy else _side_col
	for b in _cat_btns:
		var bt := b as Button
		if bt.get_parent() != to:
			bt.get_parent().remove_child(bt)
			to.add_child(bt)
		if easy:
			bt.custom_minimum_size = Vector2(EASY_CAT_W, EASY_CAT_H)
			bt.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			bt.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			bt.expand_icon = true
			bt.add_theme_font_size_override("font_size", 12)
		else:
			bt.custom_minimum_size = Vector2(0, 30)
			bt.icon = null
			bt.expand_icon = false
			bt.remove_theme_font_size_override("font_size")
	_refresh_cat_icons()


func _pick_tab(i: int) -> void:
	tab = i
	view = CATS[i] if _easy() else ""   # Easy: a tile opens its category (the grid is empty until then)
	query = ""
	_search.text = ""
	_rebuild()


func _pick_view(nm: String) -> void:
	view = nm
	query = ""
	_search.text = ""
	_rebuild()


func _on_search(t: String) -> void:
	query = t.strip_edges().to_lower()
	_rebuild()


func _refresh_tabs() -> void:
	for i in _tabs.size():
		var b: Button = _tabs[i]
		b.text = CATS[i]   # the name alone (beginner round 8, friction 8): the count is in the tooltip
		b.tooltip_text = "%d objects. %s" % [in_cat(CATS[i]).size(), TAB_TIPS[CATS[i]]]
		b.button_pressed = (view == "" and i == tab and query == "" and not _easy()) or (view == CATS[i] and query == "")
	for nm in _side_btns:
		var eb: Button = _side_btns[nm]
		if nm == RECENT:
			eb.tooltip_text = "The last things you put in the set, newest first (%d)" % recent_items().size()
		else:
			eb.tooltip_text = "%d objects. %s" % [in_group(nm).size(), EXTRA_TIPS[nm]]
		eb.button_pressed = view == nm and query == ""
		if nm == "My houses":
			eb.visible = view == nm or not in_group(nm).is_empty()   # no house drawn yet: no empty entry in the column


## the tiles on screen: the search's matches across the whole catalog, else Recent, a BUILD category, or the current built-in tab
func _shown() -> Array:
	if query != "":
		return catalog().filter(func(it): return String(it["name"]).to_lower().contains(query))
	if view == RECENT:
		return recent_items()
	if view != "":
		return in_group(view)
	if _easy():
		return []   # Easy's start: the category tiles only
	return in_cat(CATS[tab])


## the grid's width: three cards across, or nothing at Easy's start (only the category tiles show, so the panel is as wide as they are)
func _grid_min_w() -> float:
	if _easy() and view == "" and query == "":
		return 0.0
	return float(COLS) * (_tile_size().x + 8.0) + 24.0


## the card's size and picture: Easy's are bigger
func _tile_size() -> Vector2:
	return EASY_TILE if m != null and m.easy != null and m.easy.on else TILE


func _pic_size() -> int:
	return EASY_PIC if m != null and m.easy != null and m.easy.on else PIC


func _rebuild() -> void:
	_check_tile_cache()
	for c in _grid.get_children():
		_grid.remove_child(c)   # a tile is kept (cached) and shown again; the Back tile and the empty note are made each time
		if not c.has_meta("item"):
			c.queue_free()
	_pics.clear()
	_layout_mode()
	_refresh_tabs()
	var shown := _shown()
	var one := _one_category(shown)
	if _easy() and (view != "" or query != ""):
		_grid.add_child(_back_tile())
	for it in shown:
		_grid.add_child(_tile(it, one))
	if shown.is_empty() and _easy() and view == "" and query == "":
		pass   # Easy's start: the note says to pick a picture; the grid stays empty
	elif shown.is_empty():
		var empty := Label.new()
		empty.name = "library_empty"
		empty.custom_minimum_size = Vector2(_tile_size().x * COLS, 60)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.text = ("Nothing matches \"%s\"." % query) if query != "" else \
			("Nothing yet. Click a picture in any list and it shows up here." if view == RECENT else "Nothing here yet. Draw a room in BUILD, press Save house, and it is listed here." if view == "My houses" else "No models of your own yet. Drop a .glb file on the window to bring it in; it is listed here." if m.easy.on else "No models of your own yet. Import model... (the SET row) brings a .glb in; it is listed here.")
		empty.add_theme_color_override("font_color", Tok.of("text:0.6"))
		_grid.add_child(empty)
	if _easy() and view == "" and query == "":
		_note.text = "Pick a picture on the left to see what is in it."
	else:
		_note.text = ("%d shown. Click a picture to give it to him." if m.easy.on else "%d shown. Click a tile to place it in the set or the hand.") % shown.size()
	if _scroll != null and _scroll.custom_minimum_size.x != _grid_min_w() and is_inside_tree():
		_scroll.custom_minimum_size.x = _grid_min_w()   # the panel shrinks or widens with the grid (Easy's start: the category tiles' width)
		fit(get_viewport().get_visible_rect().size)
	reset_size.call_deferred()   # the panel is as tall as what it shows now (a taller tab, or a wrapping label measured before its width, left it 1572 px over a 900 px window)


## Easy's Back tile: returns to the category tiles (view and search cleared; no key, a plain click)
func _back_tile() -> Button:
	var b := Button.new()
	b.name = "library_back"
	b.text = "Back"
	b.custom_minimum_size = _tile_size()
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "Back to the categories"
	b.pressed.connect(_back)
	return b


func _back() -> void:
	view = ""
	query = ""
	_search.text = ""
	_rebuild()


## true when every tile shown is one category: the tiles then need no category caption (the tab's name is the header)
func _one_category(shown: Array) -> bool:
	for it in shown:
		if String(it["cat"]) != String(shown[0]["cat"]):
			return false
	return not shown.is_empty()


## EASY DRAG (the mouse only): a press on a tile and a move of DRAG_PX or more carries the object under a preview; the release over
## the 3D view puts a prop on the floor under the mouse (one undo step). A release over this panel, or a press without a move, is
## the click as before (place). Expert keeps the click only.
const DRAG_PX := 8.0
var _pd: Dictionary = {}          # the press in progress: {"id", "p"} (Easy only; empty = no press)
var _pd_on := false               # the press has become a drag
var _drag_frame := -1             # the frame a drag ended on: the release's own Button press is not a second placement
var _ghost_layer: CanvasLayer = null
var _ghost: PanelContainer = null


func _input(ev: InputEvent) -> void:
	if _pd.is_empty():
		return
	if ev is InputEventMouseMotion:
		var mp: Vector2 = (ev as InputEventMouseMotion).global_position
		if not _pd_on:
			if mp.distance_to(_pd["p"]) < DRAG_PX:
				return
			_pd_on = true
			_ghost_start(String(_pd["id"]))
		_ghost_move(mp)
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and not (ev as InputEventMouseButton).pressed:
		var id := String(_pd["id"])
		var was := _pd_on
		_pd = {}
		_pd_on = false
		if was:
			_drag_frame = Engine.get_process_frames()
			_ghost_stop()
			_drop(id, (ev as InputEventMouseButton).global_position)


func _tile_input(ev: InputEvent, id: String) -> void:
	if m == null or not m.easy.on:
		return
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and (ev as InputEventMouseButton).pressed:
		_pd = {"id": id, "p": (ev as InputEventMouseButton).global_position}
		_pd_on = false


## a tile's Button press: a drag's release is not a click (the drop already did it or was refused)
func _tile_pressed(id: String) -> void:
	if _drag_frame == Engine.get_process_frames():
		return
	place(id)


## the release of a drag at mouse position mp: a prop goes on the floor point under it (the camera's ray meets y = 0); other
## kinds (weapons, armour) are placed as a click places them. Over this panel nothing is placed.
func _drop(id: String, mp: Vector2) -> void:
	if get_global_rect().has_point(mp):
		return
	var it := item(id)
	if it.is_empty() or m == null:
		return
	if not (String(it["how"]) in ["prop", "piece"]):
		place(id)
		return
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(m.cam.project_ray_origin(mp), m.cam.project_ray_normal(mp))
	if hit == null:
		_note.text = "Drop it on the floor in the view (the ground), not in the sky."
		return
	m._step_hint = "Library: %s" % it["name"]
	m._step_easy = String(it["name"])
	m._prop_add(String(it["key"]), hit)
	m._step_easy = ""
	_note.text = "%s is on the floor. Undo takes it away." % it["name"]


## the preview that follows the mouse: the tile's picture and its name (on a layer over the whole window)
func _ghost_start(id: String) -> void:
	_ghost_stop()
	_ghost_layer = CanvasLayer.new()
	_ghost_layer.layer = 128
	get_tree().root.add_child(_ghost_layer)
	_ghost = PanelContainer.new()
	_ghost.name = "library_drag_ghost"
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.modulate = Color(1, 1, 1, 0.85)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.add_child(v)
	var pic := _pics.get(id) as TextureRect
	if pic != null and pic.texture != null:
		var tr := TextureRect.new()
		tr.texture = pic.texture
		tr.custom_minimum_size = Vector2(90, 90)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(tr)
	var lab := Label.new()
	var it := item(id)
	lab.text = String(it["name"]) if not it.is_empty() else id
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(lab)
	_ghost_layer.add_child(_ghost)


func _ghost_move(mp: Vector2) -> void:
	if _ghost != null:
		_ghost.position = mp + Vector2(14, 14)


func _ghost_stop() -> void:
	if _ghost_layer != null:
		_ghost_layer.queue_free()
	_ghost_layer = null
	_ghost = null


## the tiles are built once per list: when the objects (or their pictures) change, the cache is cleared
func _check_tile_cache() -> void:
	var parts := PackedStringArray()
	for it in catalog():
		parts.append("%s|%s|%s|%s" % [it["id"], it["name"], it["cat"], it.get("thumb", "")])
	var sig := "
".join(parts)
	if sig == _tile_sig:
		return
	_tile_sig = sig
	for k in _tile_cache:
		var old: Button = _tile_cache[k]
		if is_instance_valid(old):
			if old.get_parent() != null:
				old.get_parent().remove_child(old)
			old.queue_free()
	_tile_cache = {}


func _tile(it: Dictionary, one := false) -> Control:
	var key := "%s|%s|%s" % [it["id"], _easy(), one]
	if _tile_cache.has(key) and is_instance_valid(_tile_cache[key]):
		var kept := _tile_cache[key] as Button
		_refresh_tile(kept, it, one)
		return kept
	var b := _make_tile(it, one)
	_tile_cache[key] = b
	return b


## a kept tile shows the picture that is ready now (its own placeholder until then)
func _refresh_tile(b: Button, it: Dictionary, one: bool) -> void:
	var tr: TextureRect = null
	for c in b.get_children():
		if c is VBoxContainer:
			for d in c.get_children():
				if d is TextureRect:
					tr = d
	if tr == null:
		return
	var id := String(it["id"])
	var tex := thumbs.picture(id)
	if tex == null and it.has("thumb"):
		tex = HousesUI.picture_of(String(it["thumb"]))
	tr.texture = tex
	var ph := tr.get_node_or_null("placeholder")
	if ph != null:
		ph.visible = tex == null
		(ph as Label).text = "" if one else String(it["cat"])
	_pics[id] = tr
	if tex == null and not thumbs.has_asked(id):
		thumbs.request(id, thumb_source(it))


func _make_tile(it: Dictionary, one := false) -> Control:
	var b := Button.new()
	b.name = "tile_" + String(it["id"]).replace(":", "_")
	b.custom_minimum_size = _tile_size()
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = ("%s: click it, or drag it onto the floor, to give it to him" if m.easy.on else "%s: click to place it (one undo step)") % it["name"]
	b.set_meta("item", it["id"])
	b.pressed.connect(_tile_pressed.bind(String(it["id"])))
	b.gui_input.connect(_tile_input.bind(String(it["id"])))
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(v)
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(_pic_size(), _pic_size())
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pic.texture = thumbs.picture(String(it["id"]))
	if pic.texture == null and it.has("thumb"):
		pic.texture = HousesUI.picture_of(String(it["thumb"]))   # a saved house: the picture drawn when it was saved
	v.add_child(pic)
	if pic.texture == null:
		# until the picture is ready: the category, in the picture's place (never an empty box; the name is the label under it).
		# A list of one category (round 7): the caption would repeat on every tile, so the placeholder stays blank
		var ph := Label.new()
		ph.name = "placeholder"
		ph.text = "" if one else String(it["cat"])
		ph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ph.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ph.add_theme_font_size_override("font_size", 11)
		ph.add_theme_color_override("font_color", Tok.of("text:0.6"))
		pic.add_child(ph)
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
		thumbs.request(String(it["id"]), thumb_source(it))   # the schematic until the real mesh is drawn once, then user://thumbs/lib
	return b


## what a tile's picture is drawn from: the schematic shapes, the spec the real picture's cache name is made of, and the
## Callable that builds the real mesh on the main thread (see LibraryThumbs.request)
func thumb_source(it: Dictionary) -> Dictionary:
	var how := String(it["how"])
	var key := String(it["key"])
	var src := {"shapes": it["shapes"], "spec": "", "build": Callable()}
	if how == "weapon":
		src["spec"] = var_to_str(["weapon", key, Body.KINDS["dagger" if key == "two_daggers" else key], LibraryThumbs.SAME_SCALE])   # the scale is in the cache name
		src["build"] = func() -> Node3D: return LibraryThumbs.weapon_node(key)
	elif how == "prop" or how == "piece":
		src["spec"] = var_to_str(["prop", key, Props.kind_of(key)])
		src["build"] = func() -> Node3D: return Props.mesh(Props.make(key))
	if how == "weapon" or how == "prop":   # (a BUILD piece is drawn once and cached under user://thumbs/lib; nothing of it ships)
		src["shipped"] = LibraryThumbs.shipped_path(String(it["id"]), String(src["spec"]))   # the pictures shipped with the app (tools/make_lib_thumbs.gd)
	elif how == "armour" and m != null and not m.pieces.is_empty() and BaseBody.skin_of(m) != null:
		# an armour plate: the plate is built on the fighter's body, so its key holds the body's vertex count too
		if _armour_hash == "":
			_armour_hash = body_hash(m)
		# the body's rest vertices (their bytes, so a change of proportion is a change of spec), the builder's version and constants
		src["spec"] = var_to_str(["armour", key, load("res://scripts/armour_from_body.gd").BUILDER, load("res://scripts/armour_from_body.gd").GAP, load("res://scripts/armour_from_body.gd").THICK, load("res://scripts/armour_from_body.gd").BEVEL,
			load("res://scripts/armour_from_body.gd").SEGMENTS, _armour_hash])
		src["shipped"] = LibraryThumbs.shipped_path(String(it["id"]), String(src["spec"]))
		src["build"] = func() -> Node3D: return _armour_node(key)
	return src


## a plate built on the fighter's body (ArmourFromBody.build, the same call make() makes), unskinned, for its picture
## the hash of the fighter body the plates are cut from. The default body (as loaded: base-body generation 0, no proportions, its
## pieces' mesh paths: empty for the built-in body, so in effect their count) reads it from DEFAULT_BODY, written by tools/make_lib_thumbs.gd with the pictures, so the Armour tab
## does not read the whole body (~170 ms) to name pictures that are shipped; library_test checks the file is not stale.
## Any other body (edited, re-proportioned, another fighter) is read and hashed.
const DEFAULT_BODY := "res://data/thumbs/lib/default_body.txt"
static func body_sig(m: Node) -> String:
	return ",".join(m.pieces.values().map(func(p): return String((p as MeshInstance3D).mesh.resource_path) if (p as MeshInstance3D).mesh != null else "-"))


static func body_hash(m: Node, read_file := true) -> String:
	if read_file and BaseBody.gen(m) == 0 and not BaseBody.is_open(m) and (m.B.body as Dictionary).is_empty() and FileAccess.file_exists(DEFAULT_BODY):
		var parts := FileAccess.get_file_as_string(DEFAULT_BODY).strip_edges().split("|")
		if parts.size() == 2 and parts[0] == body_sig(m):
			return parts[1]
	return var_to_str((load("res://scripts/armour_from_body.gd").body_source(m)[0] as KMesh).verts).sha256_text()


## a plate's mesh on the fighter, built once per open: the body is read once (_armour_sb), and each plate's mesh is kept (_armour_built)
func _armour_node(words: String) -> Node3D:
	if m == null or m.pieces.is_empty() or BaseBody.skin_of(m) == null:
		return null
	if not _armour_built.has(words):
		if _armour_sb.is_empty():
			_armour_sb = load("res://scripts/armour_from_body.gd").body_source(m)
		var r: Dictionary = load("res://scripts/armour_from_body.gd").build(_armour_sb[0], m.skel, _armour_sb[1], words, {})
		if not bool(r.get("ok", false)):
			_armour_built[words] = null
		else:
			_armour_built[words] = load("res://scripts/armour_from_body.gd").array_mesh(r["mesh"])
	var am = _armour_built[words]
	if am == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = am
	var root := Node3D.new()
	root.add_child(mi)
	return root


## Easy's category tiles: each shows a picture of one of its objects (the first; Recent its newest), asked for once
func _refresh_cat_icons() -> void:
	for b in _cat_btns:
		var bt := b as Button
		bt.icon = null
		if not _easy() or thumbs == null:
			continue
		var nm := String(bt.get_meta("cat"))
		var li: Array = recent_items() if nm == RECENT else in_group(nm)
		if li.is_empty():
			continue
		var it: Dictionary = li[0]
		if CAT_PIC.has(nm):   # two categories whose first object looks alike (a table in both) show different pictures
			var rep := item(String(CAT_PIC[nm]))
			if not rep.is_empty() and group_of(rep) == nm:
				it = rep
		var id := String(it["id"])
		var tex := thumbs.picture(id)
		if tex == null and it.has("thumb"):
			tex = HousesUI.picture_of(String(it["thumb"]))
		if tex == null and not _cat_req.has(id):
			_cat_req[id] = true
			thumbs.request(id, thumb_source(it))
		bt.icon = tex


func _made(id: String) -> void:
	_refresh_cat_icons()
	if _pics.has(id) and is_instance_valid(_pics[id]):
		var pic := _pics[id] as TextureRect
		pic.texture = thumbs.picture(id)
		var ph := pic.get_node_or_null("placeholder")
		if ph != null:
			ph.queue_free()
