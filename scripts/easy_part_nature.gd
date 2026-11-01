class_name EasyPartNature
extends RefCounted
## FRIDAY 225 NATURE in Easy Parts: a "Nature" chip at the end of the Parts library page opens a small page (trees, hedge, shrub, grass,
## flowers, path and four leaf colours). A chip plants that thing in the house scene next to the part: the same sentence the Words box
## understands (scripts/build/nature_words.gd), so the result is the same as typing it. One chip = one undo step. It is NOT one of the
## LIB_CATS chips (that row is full and its count is measured by older tests): the chip is named easypart_nature_chip.

const THINGS := [
	["ginkgo", "Ginkgo", "a {s}ginkgo tree 6 m tall"],
	["oak", "Oak", "an {s}oak tree 6 m tall"],
	["pine", "Pine", "a pine tree 6 m tall"],
	["palm", "Palm", "a palm tree 5 m tall"],
	["birch", "Birch", "a {s}birch tree 6 m tall"],
	["bare", "Winter tree", "a bare winter tree 6 m tall"],
	["hedge", "Box hedge", "a box hedge 0.8 m high 6 m long"],
	["shrub", "Round shrub", "a round shrub"],
	["grass", "Grass", "grass"],
	["flowers", "Flowers", "flowers"],
	["path", "Path", "a path"],
]
const SEASONS := [["spring", "Spring", "spring "], ["summer", "Summer", ""], ["autumn", "Gold", "golden "], ["red", "Red", "red "]]

var ep
var chip: Button
var box: PanelContainer
var thing_btns := {}
var season_btns := {}
var season := "summer"
var open := false


func _init(easy) -> void:
	ep = easy


func make_chip() -> Button:
	chip = Button.new()
	chip.name = "easypart_nature_chip"
	chip.text = "Nature"
	chip.toggle_mode = true
	chip.focus_mode = Control.FOCUS_NONE
	chip.custom_minimum_size = Vector2(0, 34)
	chip.add_theme_font_size_override("font_size", 12)
	chip.tooltip_text = "Nature: plant trees, a hedge, shrubs, grass, flowers or a path beside your part"
	chip.pressed.connect(toggle)
	return chip


func make_box() -> PanelContainer:
	box = PanelContainer.new()
	box.name = "easypart_nature_box"
	box.add_theme_stylebox_override("panel", ep._style(Color(0.12, 0.125, 0.15), 10, 6))
	box.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	box.add_child(vb)
	var sr := HFlowContainer.new()
	sr.add_theme_constant_override("h_separation", 3)
	vb.add_child(sr)
	var sg := ButtonGroup.new()
	for s in SEASONS:
		var b := Button.new()
		b.name = "easypart_nature_season_" + String(s[0])
		b.text = String(s[1])
		b.toggle_mode = true
		b.button_group = sg
		b.button_pressed = s[0] == season
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 30)
		b.add_theme_font_size_override("font_size", 12)
		b.tooltip_text = "Leaf colour for the next tree"
		b.pressed.connect(func(): season = String(s[0]))
		season_btns[String(s[0])] = b
		sr.add_child(b)
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 4)
	fl.add_theme_constant_override("v_separation", 4)
	vb.add_child(fl)
	for t in THINGS:
		var b := Button.new()
		b.name = "easypart_nature_" + String(t[0])
		b.text = String(t[1])
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 30)
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_stylebox_override("normal", ep._style(Color(0.165, 0.176, 0.212), 6, 4))
		b.add_theme_stylebox_override("hover", ep._style(Color(0.23, 0.245, 0.29), 6, 4))
		b.tooltip_text = "%s: planted in the scene, one undo step" % String(t[1])
		b.pressed.connect(plant.bind(String(t[0])))
		thing_btns[String(t[0])] = b
		fl.add_child(b)
	return box


func toggle() -> void:
	open = chip.button_pressed
	if open:
		ep.parts_open = true
		ep.lib_cat = "Nature"
		ep._say("Nature: pick a tree, hedge, shrub, grass, flowers or a path. It is planted beside your part")
	else:
		ep.lib_cat = ""
		ep._say("Nature closed")
	ep._screw_sync()
	if open:   # the page is under the category chips: once it has its size, scroll it into view, whole
		await ep.panel.get_tree().process_frame
		await ep.panel.get_tree().process_frame
		ep._scroll_into_view(box)


## called from _screw_sync: the page shows while Nature is the open category; the chip follows
func sync() -> void:
	if box == null:
		return
	open = ep.parts_open and ep.lib_cat == "Nature"
	box.visible = open
	if chip != null:
		chip.set_pressed_no_signal(open)


func sentence(key: String) -> String:
	var tpl := ""
	for t in THINGS:
		if t[0] == key:
			tpl = String(t[2])
	var sw := ""
	for s in SEASONS:
		if s[0] == season:
			sw = String(s[2])
	return tpl.replace("{s}", sw)


func plant(key: String) -> void:
	var m = ep.m
	var bu = m.bld
	if bu == null:
		return
	var text := sentence(key)
	var r := NatureWords.parse(text, bu._bld())
	if not bool(r["ok"]):
		ep._say(String(r["error"]))
		return
	m._step_hint = "Nature: " + String(r["say"])
	m._push_undo()
	NatureWords.apply(bu._ensure(), text)
	bu.sync()
	bu._frame_nature()
	ep._say("Planted: %s. Undo takes it back" % String(r["say"]))
