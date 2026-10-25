class_name EasyScenes
extends Control
## EASY: "My scenes" (Nick: "Easy mode can't let you open already made scenes easily"). The bar's My scenes button opens this
## panel: the saved scenes as big tiles with their pictures (SceneThumbs, the scene list's own pictures), newest first, and a
## second row "Examples" (the shipped scenes, opened as copies, as Expert's example buttons do). One click opens the scene and
## plays it; a scene with unsaved work asks first (main._ask_save). Esc or Close shuts it. Example scenes are not in "My scenes".
## THE CATALOG (round 1 of the scene browser, scripts/scene_cat.gd): big category chips over the tiles (All, Walk & run, Fight,
## Weapons, Jump & dodge, Dance & other, Drafts, Favourites), each with its count; a quality badge on every tile (Good / OK /
## Weird, from Kine's own Check, graded one scene per frame and cached); "Hide weird ones" and "Best first" / "Newest first";
## a star on each tile for a favourite. The toggles and the stars are kept in the settings file.

const TILE := Vector2(224, 196)
const PIC := Vector2(208, 130)
const CHIPS := [["All", "chip_all"], ["Walk & run", "chip_walk"], ["Fight", "chip_fight"], ["Weapons", "chip_weapons"],
	["Jump & dodge", "chip_jump"], ["Dance & other", "chip_dance"], ["Drafts", "chip_drafts"], ["Favourites", "chip_favs"]]
const BADGE_COL := {"Good": Color(0.55, 0.92, 0.6), "OK": Color(1.0, 0.86, 0.5), "Weird": Color(1.0, 0.55, 0.5)}
const CFG := "easy_scenes"

var m: Node                       # main (untyped: the same pattern as EasyMode)
var extra_dirs: Array = []        # a test's own folders (user://), read with the saved scenes
var draft_dirs: Array = []        # a test's own drafts folders, in place of res://scenes/_wip (empty = the shipped one)
var _mine: HFlowContainer
var _examples: HFlowContainer
var _drafts: HFlowContainer
var _mine_head: Label
var _ex_head: Label
var _drafts_head: Label
var _empty: Label
var _chips: HFlowContainer
var _chip_btns := {}              # chip key -> Button
var _group := ButtonGroup.new()
var _cat := "All"                 # the chip shown: All, a category name, Drafts or Favourites
var _hide_box: CheckBox
var _sort: OptionButton
var _tiles := {}                  # scene path -> {"button", "pic", "name", "example", "group", "cat", "badge", "star"}
var _order_mine: Array = []       # the saved scenes' paths, in the order shown (newest first, or best first)
var _order_ex: Array = []         # the examples' paths, in the order shown
var _order_dr: Array = []         # the drafts' paths, in the order shown
var _base_mine: Array = []        # the same two lists, newest first (what "Newest first" shows)
var _base_dr: Array = []
var _cache := {}                  # SceneCat's cache (path -> entry), read at each open
var _cache_dirty := false
var _grades := {}                 # path -> [fails, warns], for every scene graded (this open or cached)
var _queue: Array = []            # the paths still to grade, in the order the badges fill
var _fav: Array = []              # the starred paths
var _hide_weird := false
var _best := false                # "Best first" (true) or "Newest first"


## built once, from EasyMode.build: a full-window panel over the bar, hidden until My scenes is pressed
func build(root: Control) -> void:
	name = "easy_scenes"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.name = "easy_scenes_shade"
	shade.color = Color(0, 0, 0, 0.7)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var box := PanelContainer.new()
	box.name = "easy_scenes_box"
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 40.0
	box.offset_top = 40.0
	box.offset_right = -40.0
	box.offset_bottom = -40.0
	var st := StyleBoxFlat.new()
	st.bg_color = Tok.c("panel")
	st.set_corner_radius_all(12)
	st.set_content_margin_all(16)
	box.add_theme_stylebox_override("panel", st)
	add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	box.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := Label.new()
	title.text = "My scenes"
	title.add_theme_font_size_override("font_size", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.name = "easy_scenes_close"
	close.text = "Close"
	close.tooltip_text = "close this list"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(130, 44)
	close.add_theme_font_size_override("font_size", 18)
	close.pressed.connect(close_panel)
	head.add_child(close)
	_chips = HFlowContainer.new()
	_chips.name = "easy_scenes_chips"
	_chips.add_theme_constant_override("h_separation", 10)
	_chips.add_theme_constant_override("v_separation", 10)
	v.add_child(_chips)
	for c in CHIPS:
		var b := Button.new()
		b.name = c[1]
		b.toggle_mode = true
		b.button_group = _group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 56)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(_set_cat.bind(String(c[0])))
		_chips.add_child(b)
		_chip_btns[String(c[0])] = b
	(_chip_btns["All"] as Button).set_pressed_no_signal(true)
	var opts := HBoxContainer.new()
	opts.add_theme_constant_override("separation", 24)
	v.add_child(opts)
	_hide_box = CheckBox.new()
	_hide_box.name = "easy_scenes_hide_weird"
	_hide_box.text = "Hide weird ones"
	_hide_box.tooltip_text = "hide the scenes marked Weird (a FAIL in Kine's check)"
	_hide_box.focus_mode = Control.FOCUS_NONE
	_hide_box.add_theme_font_size_override("font_size", 18)
	_hide_box.toggled.connect(_on_hide)
	opts.add_child(_hide_box)
	_sort = OptionButton.new()
	_sort.name = "easy_scenes_sort"
	_sort.add_item("Best first", 0)
	_sort.add_item("Newest first", 1)
	_sort.focus_mode = Control.FOCUS_NONE
	_sort.add_theme_font_size_override("font_size", 18)
	_sort.item_selected.connect(_on_sort)
	opts.add_child(_sort)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	scroll.add_child(body)
	_empty = _heading("")
	_empty.name = "easy_scenes_empty"
	_empty.visible = false
	body.add_child(_empty)
	_mine_head = _heading("Your scenes (newest first)")
	body.add_child(_mine_head)
	_mine = _grid("easy_scenes_mine")
	body.add_child(_mine)
	_ex_head = _heading("Examples: a copy to look at and change")
	body.add_child(_ex_head)
	_examples = _grid("easy_scenes_examples")
	body.add_child(_examples)
	_drafts_head = _heading("Drafts: work copies made by Easy and Expert (scenes/_wip, newest first)")
	body.add_child(_drafts_head)
	_drafts = _grid("easy_scenes_drafts")
	body.add_child(_drafts)
	root.add_child(self)
	set_process(false)


func _grid(nm: String) -> HFlowContainer:
	var g := HFlowContainer.new()
	g.name = nm
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 12)
	return g


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	return l


## the panel: the saved scenes and the examples are read now (a scene saved since the last open is listed)
func open_panel() -> void:
	if m == null or m.thumbs == null:
		return
	if not m.thumbs.made.is_connected(_made):
		m.thumbs.made.connect(_made)
	_load_prefs()
	_cache = SceneCat.load_cache()
	_fill()
	visible = true
	move_to_front()


func close_panel() -> void:
	visible = false
	set_process(false)


## the paths of the tiles shown, in order: the saved scenes (example false) or the examples (example true)
func tile_paths(example: bool) -> Array:
	return (_order_ex if example else _order_mine).duplicate()


## the tile's button for a scene path (its press is the click that opens it)
func tile_button(path: String) -> Button:
	return _tiles[path]["button"] if _tiles.has(path) else null


## the tile's picture (null until the picture is drawn)
func tile_picture(path: String) -> Texture2D:
	return (_tiles[path]["pic"] as TextureRect).texture if _tiles.has(path) else null


## the tile's name as shown
func tile_name(path: String) -> String:
	return String(_tiles[path]["name"]) if _tiles.has(path) else ""


## the tile's category chip, its badge text ("…" until graded) and whether it is on screen now
func tile_category(path: String) -> String:
	return String(_tiles[path]["cat"]) if _tiles.has(path) else ""


func tile_badge(path: String) -> String:
	return (_tiles[path]["badge"] as Label).text if _tiles.has(path) else ""


func tile_shown(path: String) -> bool:
	return _tiles.has(path) and (_tiles[path]["button"] as Button).visible


func tile_star(path: String) -> Button:
	return _tiles[path]["star"] if _tiles.has(path) else null


## the chip's button by its name (All, Walk & run, Fight, Weapons, Jump & dodge, Dance & other, Drafts, Favourites)
func chip(key: String) -> Button:
	return _chip_btns.get(key)


func hide_box() -> CheckBox:
	return _hide_box


func sort_box() -> OptionButton:
	return _sort


## the scenes still waiting for their grade (0 once every badge is in)
func pending() -> int:
	return _queue.size()


func _fill() -> void:
	for g in [_mine, _examples, _drafts]:
		for c in g.get_children():
			g.remove_child(c)
			c.queue_free()
	_tiles.clear()
	_order_mine = []
	_order_ex = []
	_order_dr = []
	_base_mine = []
	_base_dr = []
	_queue = []
	_grades = {}
	var examples := []
	for ex in m.EXAMPLES:
		examples.append(String(ex[1]))
	# the saved scenes: the list's own rows (Expert's scene list reads the same folders, newest first), without the examples
	var dirs: Array = ["res://scenes", "res://moves"].reduce(func(a, x): return a + UserPaths.dirs(x), [])
	var wip_dirs: Array = UserPaths.dirs("res://scenes/_wip") if draft_dirs.is_empty() else draft_dirs.duplicate()
	for x in extra_dirs:   # a test's folders: a _wip one is drafts, the rest are saved scenes
		(wip_dirs if String(x).contains("/_wip") else dirs).append(x)
	for f in m._scene_files(dirs):
		var p := String(f[0])
		if examples.has(p) or _tiles.has(p):
			continue
		_order_mine.append(p)
		_base_mine.append(p)
		_add_tile(p, p.get_file().get_basename().replace("_", " "), "mine")
	for p: String in examples:
		var nm: String = p.get_file().get_basename()
		_order_ex.append(p)
		_add_tile(p, nm.replace("_", " ").capitalize(), "ex")
	# the drafts: their own group (scenes/_wip, newest first), graded last
	for f in m._scene_files(wip_dirs):
		var p := String(f[0])
		_order_dr.append(p)
		_base_dr.append(p)
		_add_tile(p, p.get_file().get_basename().replace("_", " "), "dr")
	if _order_mine.is_empty():
		_mine.add_child(_heading("No saved scenes yet: press New scene, then Save the scene, and it is listed here."))
	if _cache_dirty:
		SceneCat.save_cache(_cache)
		_cache_dirty = false
	if m.thumbs != null:
		for p in _order_mine + _order_ex + _order_dr:
			m.thumbs.request(p)
			_made(p)
	_resort()
	_update_chips()
	_apply()
	set_process(not _queue.is_empty())


## one scene's cached facts: its category, and its grade when the cache has it for this file (mtime and size unchanged).
## A file the cache lacks (or changed) is read once for its category and queued for its grade.
func _info(p: String) -> Dictionary:
	var st := SceneCat.stamp(p)
	var e: Dictionary = _cache.get(p, {})
	var fresh := int(e.get("v", 0)) == SceneCat.CACHE_V and int(e.get("mtime", -1)) == int(st[0]) and int(e.get("size", -2)) == int(st[1])
	if not fresh:
		var scene := {}
		if not SceneCat.is_draft(p):
			var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
			scene = v if v is Dictionary else {}
		e = {"v": SceneCat.CACHE_V, "mtime": st[0], "size": st[1], "cat": SceneCat.category(p, scene)}
		_cache[p] = e
		_cache_dirty = true
	return e


func _add_tile(path: String, nm: String, group: String) -> void:
	var example := group == "ex"
	var info := _info(path)
	var b := Button.new()
	var idx := (_order_mine if group == "mine" else _order_ex if example else _order_dr).size() - 1
	b.name = "tile_%s_%d" % [group, idx]
	b.custom_minimum_size = TILE
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = ("Open the example '%s' as a copy: Save makes a new file" if example else "Open '%s' and play it") % nm
	b.pressed.connect(_pick.bind(path, example))
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 6)
	b.add_child(col)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	var badge := Label.new()
	badge.name = "badge"
	badge.text = "…"
	badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	badge.add_theme_font_size_override("font_size", 16)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(badge)
	var star := Button.new()
	star.name = "star"
	star.flat = true
	star.focus_mode = Control.FOCUS_NONE
	star.custom_minimum_size = Vector2(38, 30)
	star.add_theme_font_size_override("font_size", 20)
	star.tooltip_text = "Mark this scene as a favourite"
	star.pressed.connect(_toggle_fav.bind(path))
	row.add_child(star)
	var pic := TextureRect.new()
	pic.name = "picture"
	pic.custom_minimum_size = PIC
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(pic)
	var l := Label.new()
	l.name = "name"
	l.text = nm
	l.add_theme_font_size_override("font_size", 17)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(l)
	_tiles[path] = {"button": b, "pic": pic, "name": nm, "example": example, "group": group,
		"cat": String(info["cat"]), "badge": badge, "star": star}
	(_examples if example else _drafts if group == "dr" else _mine).add_child(b)
	star.text = "★" if _fav.has(path) else "☆"
	if info.has("fails") and info.has("warns"):
		_grades[path] = [int(info["fails"]), int(info["warns"])]
	else:
		_queue.append(path)
	_set_badge(path)


## a picture is ready: its tile shows it
func _made(path: String) -> void:
	if not _tiles.has(path) or m.thumbs == null:
		return
	var tex: Texture2D = m.thumbs.picture(path)
	if tex != null:
		(_tiles[path]["pic"] as TextureRect).texture = tex


## a tile's click: the panel shuts, the scene opens (save-first question when the open one has unsaved work), and it plays
func _pick(path: String, example: bool) -> void:
	close_panel()
	var play := func():
		if m.S.cards.size() >= 2 and not m.playing:
			m._toggle_play()
	if example:
		var go := func():
			m._open_example(path)
			play.call()
		if m._unsaved():
			m._ask_save(m._scene_label(), go)
		else:
			go.call()
	else:
		m._open_scene_file(path, play)


# ---------------------------------------------------------------- the badges (SceneCat.grade, one scene per frame)

func _process(_delta: float) -> void:
	if _queue.is_empty():
		set_process(false)
		return
	var p: String = _queue.pop_front()
	if not _tiles.has(p):
		return
	var g: Array = SceneCat.grade(p)
	_grades[p] = g
	var e: Dictionary = _cache.get(p, {})
	e["fails"] = g[0]
	e["warns"] = g[1]
	_cache[p] = e
	SceneCat.save_cache(_cache)
	_set_badge(p)
	if _queue.is_empty():
		_resort()
		_update_chips()
		_apply()


func _grade_name(p: String) -> String:
	if not _grades.has(p):
		return ""
	var g: Array = _grades[p]
	return SceneCat.grade_of(int(g[0]), int(g[1]))


func _set_badge(p: String) -> void:
	var t: Dictionary = _tiles[p]
	var gn := _grade_name(p)
	var lbl: Label = t["badge"]
	lbl.text = gn if gn != "" else "…"
	lbl.add_theme_color_override("font_color", BADGE_COL.get(gn, Color(1, 1, 1, 0.5)))
	lbl.tooltip_text = "" if gn == "" else ("Good: nothing breaks the rulebook" if gn == "Good" else "OK: a few things to look at" if gn == "OK" else "Weird: a must-fix finding in Kine's Check")


# ---------------------------------------------------------------- the chips, the toggles, the stars

func _set_cat(key: String) -> void:
	_cat = key
	_apply()


func _on_hide(on: bool) -> void:
	_hide_weird = on
	_save_pref("hide_weird", on)
	_apply()


func _on_sort(i: int) -> void:
	_best = i == 0
	_save_pref("best_first", _best)
	_resort()
	_apply()


func _toggle_fav(p: String) -> void:
	if _fav.has(p):
		_fav.erase(p)
	else:
		_fav.append(p)
	_save_pref("favourites", _fav)
	if _tiles.has(p):
		(_tiles[p]["star"] as Button).text = "★" if _fav.has(p) else "☆"
	_update_chips()
	_apply()


## a tile passes the chip shown and the Hide weird toggle
func _passes(p: String) -> bool:
	var t: Dictionary = _tiles[p]
	var draft := String(t["group"]) == "dr"
	var ok := true
	if _cat == "All":
		ok = true
	elif _cat == "Drafts":
		ok = draft
	elif _cat == "Favourites":
		ok = _fav.has(p)
	else:
		ok = not draft and String(t["cat"]) == _cat
	return ok and not (_hide_weird and _grade_name(p) == "Weird")


func _apply() -> void:
	var shown := {"mine": 0, "ex": 0, "dr": 0}
	var hidden := 0
	for p in _tiles:
		var t: Dictionary = _tiles[p]
		var ok := _passes(p)
		(t["button"] as Button).visible = ok
		if ok:
			shown[String(t["group"])] = int(shown[String(t["group"])]) + 1
		elif _hide_weird and _grade_name(p) == "Weird":
			hidden += 1
	_mine_head.visible = int(shown["mine"]) > 0
	_ex_head.visible = int(shown["ex"]) > 0
	_drafts_head.visible = int(shown["dr"]) > 0
	var total := int(shown["mine"]) + int(shown["ex"]) + int(shown["dr"])
	_empty.visible = total == 0
	if total == 0:
		_empty.text = ("Every scene in this group is marked Weird. Turn Hide weird ones off to see them." if hidden > 0
			else "Nothing in this group yet.")
	_hide_box.set_pressed_no_signal(_hide_weird)
	_sort.select(0 if _best else 1)
	_mine_head.text = "Your scenes (best first)" if _best else "Your scenes (newest first)"
	_drafts_head.text = "Drafts: work copies made by Easy and Expert (scenes/_wip, best first)" if _best else "Drafts: work copies made by Easy and Expert (scenes/_wip, newest first)"


## the chips' counts: each category counts the saved scenes in it; Drafts the drafts; Favourites the starred ones shown anywhere
func _update_chips() -> void:
	var n := {}
	for k in CHIPS:
		n[String(k[0])] = 0
	n["All"] = _order_mine.size()
	n["Drafts"] = _order_dr.size()
	for p in _order_mine:
		var c: String = String(_tiles[p]["cat"])
		n[c] = int(n.get(c, 0)) + 1
	var favs := 0
	for p in _fav:
		if _tiles.has(p):
			favs += 1
	n["Favourites"] = favs
	for k in CHIPS:
		var key := String(k[0])
		var b: Button = _chip_btns[key]
		b.text = ("★ " if key == "Favourites" else "") + key + " (%d)" % int(n[key])


## the order of the saved scenes and the drafts: newest first, or best first (Good, OK, Weird, not graded yet; fewer warnings first)
func _resort() -> void:
	if _best:
		_order_mine = _sorted_by_grade(_base_mine)
		_order_dr = _sorted_by_grade(_base_dr)
	else:
		_order_mine = _base_mine.duplicate()
		_order_dr = _base_dr.duplicate()
	for grp in [[_mine, _order_mine], [_drafts, _order_dr]]:
		var box: HFlowContainer = grp[0]
		var i := 0
		for p in grp[1]:
			if _tiles.has(p):
				box.move_child(_tiles[p]["button"], i)
				i += 1


func _sorted_by_grade(paths: Array) -> Array:
	var keyed := []
	for i in paths.size():
		var p: String = paths[i]
		var gn := _grade_name(p)
		var rank: int = {"Good": 0, "OK": 1, "Weird": 2}.get(gn, 3)
		var warns: int = int(_grades[p][1]) if _grades.has(p) else 0
		keyed.append([rank, warns, i, p])
	keyed.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and (a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]))))
	var out := []
	for k in keyed:
		out.append(k[3])
	return out


# ---------------------------------------------------------------- the settings (the same file as the rest of Kine's settings)

func _load_prefs() -> void:
	var cf := ConfigFile.new()
	if m.settings != "":
		cf.load(m.settings)
	_hide_weird = bool(cf.get_value(CFG, "hide_weird", false))
	_best = bool(cf.get_value(CFG, "best_first", false))
	_fav = []
	for p in cf.get_value(CFG, "favourites", []):
		_fav.append(String(p))


func _save_pref(key: String, v: Variant) -> void:
	if m == null or m.settings == "":
		return
	var cf := ConfigFile.new()
	cf.load(m.settings)
	cf.set_value(CFG, key, v)
	cf.save(m.settings)


func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()
