class_name NatureUI
extends RefCounted
## nature_ui.gd - FRIDAY 225: the NATURE tool of the BUILD page. A picker of cards on the left (trees, hedges, shrubs, grass, flowers, a path, rocks), a season row
## and two numbers (height / size in metres, density 1-10). Pick a card, click the ground: a tree, shrub or flower bed stands there; a hedge or path takes two clicks
## (start, end). Every placement is ONE undo step. The items are the building record's "nature" list, drawn by scripts/build/nature_view.gd.

const SKY := Color("#73BFFF")
const CARDS := [
	["Trees", [["ginkgo", "Ginkgo"], ["oak", "Oak"], ["pine", "Pine"], ["palm", "Palm"], ["birch", "Birch"], ["bare", "Winter tree"]]],
	["Hedges and shrubs", [["hedge", "Box hedge"], ["hedge_round", "Round hedge"], ["shrub", "Round shrub"], ["shrub_cone", "Cone shrub"]]],
	["Ground", [["grass", "Grass"], ["flowers", "Flowers"], ["path", "Path"], ["rocks", "Rocks"]]],
]
const SEASON_NAMES := [["spring", "Spring"], ["summer", "Summer"], ["autumn", "Gold"], ["red", "Red"]]

var ui: BuildUI
var m: Node
var panel: PanelContainer
var hint: Label
var card_btns := {}
var season_btns := {}
var h_edit: LineEdit
var d_edit: LineEdit
var kind := ""           # the card in hand
var season := "summer"
var first := Vector3.ZERO
var has_first := false
var last_id := ""


func setup(owner: BuildUI) -> void:
	ui = owner
	m = owner.m
	panel = PanelContainer.new()
	panel.name = "build_nature_picker"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.14, 0.94)
	sb.border_color = SKY
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "Nature"
	title.add_theme_font_size_override("font_size", 16)
	vb.add_child(title)
	hint = Label.new()
	hint.name = "build_nature_hint"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 3.0 * 96.0 + 12.0
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(1, 1, 1, 0.75)
	vb.add_child(hint)
	var group := ButtonGroup.new()
	group.allow_unpress = true
	for cat in CARDS:
		var cl := Label.new()
		cl.text = String(cat[0])
		cl.add_theme_font_size_override("font_size", 12)
		cl.modulate = Color(SKY, 0.95)
		vb.add_child(cl)
		var gc := GridContainer.new()
		gc.columns = 3
		gc.add_theme_constant_override("h_separation", 4)
		gc.add_theme_constant_override("v_separation", 4)
		for c in cat[1]:
			var btn := Button.new()
			btn.name = "nature_card_" + String(c[0])
			btn.toggle_mode = true
			btn.button_group = group
			btn.custom_minimum_size = Vector2(96.0, 30.0)
			btn.text = String(c[1])
			btn.add_theme_font_size_override("font_size", 13)
			btn.focus_mode = Control.FOCUS_NONE
			btn.tooltip_text = _help(String(c[0]))
			btn.toggled.connect(_card_toggled.bind(String(c[0])))
			card_btns[String(c[0])] = btn
			gc.add_child(btn)
		vb.add_child(gc)
	var sl := Label.new()
	sl.text = "Leaves"
	sl.add_theme_font_size_override("font_size", 12)
	sl.modulate = Color(SKY, 0.95)
	vb.add_child(sl)
	var sr := HBoxContainer.new()
	sr.add_theme_constant_override("separation", 3)
	var sg := ButtonGroup.new()
	for s in SEASON_NAMES:
		var b := Button.new()
		b.name = "nature_season_" + String(s[0])
		b.text = String(s[1])
		b.toggle_mode = true
		b.button_group = sg
		b.button_pressed = s[0] == season
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 12)
		b.custom_minimum_size.x = 46.0
		b.pressed.connect(func(): season = String(s[0]))
		season_btns[String(s[0])] = b
		sr.add_child(b)
	vb.add_child(sr)
	var nr := HBoxContainer.new()
	nr.add_theme_constant_override("separation", 4)
	h_edit = _num_edit(nr, "Height m", "6")
	d_edit = _num_edit(nr, "Density", "5")
	vb.add_child(nr)
	panel.visible = false
	m.ui_root.add_child(panel)


func _num_edit(row: HBoxContainer, lab: String, dv: String) -> LineEdit:
	var l := Label.new()
	l.text = lab
	l.add_theme_font_size_override("font_size", 12)
	row.add_child(l)
	var le := LineEdit.new()
	le.name = "nature_" + lab.to_lower().replace(" ", "_")
	le.text = dv
	le.custom_minimum_size.x = 44.0
	le.add_theme_font_size_override("font_size", 12)
	row.add_child(le)
	return le


static func _help(k: String) -> String:
	match k:
		"hedge", "hedge_round":
			return "Hedge: click where it starts, click where it ends. Height m sets how high."
		"path":
			return "Path: click the start and the end. Lawns and scatters keep off it."
		"grass":
			return "Grass: a lawn patch where you click (size m wide), off the rooms and paths."
		"flowers":
			return "Flowers: a bed where you click."
		"rocks":
			return "Rocks: twelve rocks scattered around where you click."
	return "Click the ground to plant one."


func _card_toggled(pressed: bool, k: String) -> void:
	kind = k if pressed else ("" if kind == k else kind)
	has_first = false
	_say_hint()


func _say_hint() -> void:
	if kind == "":
		hint.text = "Pick a card, then click the ground. Undo takes it back."
	elif kind in ["hedge", "hedge_round", "path"]:
		hint.text = ("Click where it ends." if has_first else "Click where it starts.")
	else:
		hint.text = "Click the ground to put it there."


func shown() -> bool:
	return ui.on and ui.tool == "Nature" and not ui.easy_ui()


func layout(cl: Rect2) -> void:
	panel.visible = shown()
	if panel.visible:
		_say_hint()
		panel.reset_size()
		panel.position = Vector2(cl.position.x + 8.0, cl.position.y + 6.0)


func _val(le: LineEdit, dv: float, lo: float, hi: float) -> float:
	return clampf(le.text.to_float() if le.text.is_valid_float() else dv, lo, hi)


## a click at screen point p with the tool on. Always true (the tool owns the click)
func press(p: Vector2) -> bool:
	if kind == "":
		m._say("Nature: pick a card on the left, then click the ground")
		return true
	var g: Variant = ui.ground(p)
	if g == null:
		return true
	var sn: Vector3 = ui._snap(g)
	if kind in ["hedge", "hedge_round", "path"]:
		if not has_first:
			first = sn
			has_first = true
			_say_hint()
			m._say("Nature: now click where it ends")
			return true
		has_first = false
		if first.distance_to(sn) < 0.5:
			m._say("Nature: that is too short, click further away")
			return true
		_place_line(first, sn)
		return true
	_place_point(sn)
	return true


func _place_line(a: Vector3, b: Vector3) -> void:
	var item: Dictionary
	var hh := _val(h_edit, 1.0, 0.2, 6.0)
	if kind == "path":
		item = {"kind": "path", "path": [[a.x, a.z], [b.x, b.z]], "width": 1.2}
	else:
		item = {"kind": "hedge", "path": [[a.x, a.z], [b.x, b.z]], "shape": "round" if kind == "hedge_round" else "box", "height": minf(hh, 3.0) if hh != 6.0 else 0.9, "width": 0.6, "seed": _next_seed()}
	_commit(item, kind.replace("_", " "))


func _place_point(sn: Vector3) -> void:
	var item := {}
	var hh := _val(h_edit, 6.0, 0.3, 40.0)
	var dn := int(_val(d_edit, 5.0, 1.0, 10.0))
	match kind:
		"ginkgo", "oak", "pine", "palm", "birch", "bare":
			item = {"kind": "tree", "species": kind, "x": sn.x, "z": sn.z, "height": hh, "season": season if kind != "bare" else "winter", "density": dn, "seed": _next_seed()}
		"shrub", "shrub_cone":
			item = {"kind": "shrub", "shape": "cone" if kind == "shrub_cone" else "round", "x": sn.x, "z": sn.z, "size": minf(hh, 4.0) if hh != 6.0 else 1.2, "season": season, "seed": _next_seed()}
		"grass":
			var s := 6.0
			item = {"kind": "grass", "x": sn.x - s * 0.5, "z": sn.z - s * 0.5, "w": s, "d": s, "seed": _next_seed()}
		"flowers":
			item = {"kind": "flowers", "x": sn.x - 1.0, "z": sn.z - 1.0, "w": 2.0, "d": 2.0, "n": 40, "color": ["yellow", "red", "pink", "white", "blue"][_next_seed() % 5], "seed": _next_seed()}
		"rocks":
			item = {"kind": "scatter", "of": "rock", "n": 12, "spacing": 0.8, "size": 0.5, "jitter": 0.8, "seed": _next_seed(), "area": {"shape": "rect", "x": sn.x - 3.0, "z": sn.z - 3.0, "w": 6.0, "d": 6.0}}
	if item.is_empty():
		return
	_commit(item, kind.replace("_", " "))


func _next_seed() -> int:
	return 1 + (ui._bld().get("nature", []) as Array).size() * 7 + int(Time.get_ticks_msec() % 997) if false else 1 + (ui._bld().get("nature", []) as Array).size() * 7


func _commit(item: Dictionary, what: String) -> void:
	m._step_hint = "Nature: " + what
	m._push_undo()
	var id := Nature.add(ui._ensure(), item)
	last_id = id
	ui.sync()
	m._say("Nature: %s placed. Undo takes it back" % what)
