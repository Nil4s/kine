## light_rig_ui.gd - L25 LIGHT RIG panel (the maths and the data: scripts/light_rig.gd; the state and the actions: main.gd lr_*).
## Opens in the findings panel like the floor plan: one button per look (studio, dramatic, overcast, sunset, night), the sky map
## picker with a rotation slider and an intensity slider, and one check per light "lights the character only" (light linking).
## The palette has the same verbs (commands). The Easy page gets nothing: this is an Expert panel.
class_name LightRigUI
extends RefCounted

var m: Node
var _busy := false   # sync() writes the controls: their signals must not write back


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	for lid in LightRig.EXTRA_IDS:
		add.call(LightRig.NAMES[lid], "", m.lr_preset.bind(lid), "light lighting lights preset shot camera look rig " + lid, true, LightRig.tip(lid))
	add.call("Light: rig panel", "", show, "light lighting rig panel presets studio dramatic overcast sunset night sky map hdri link", false,
		"the light rig panel: five looks, a sky map with rotation and intensity, and a per-light 'character only' switch")
	add.call("Light: sky map...", "", show, "light sky map hdri environment background picker rotation intensity", false,
		"the light rig panel's sky map list: %s; rotation and intensity sliders (a view setting)" % ", ".join(LightRig.SKY_IDS.map(func(i): return LightRig.SKY_NAMES[i])))
	add.call("Light: no sky map", "", m.lr_hdri.bind(""), "light sky map hdri environment off none remove", false, "the world behind the figure is the flat colour again")
	for sid in LightRig.SKY_IDS:
		add.call("Light: sky " + LightRig.SKY_NAMES[sid], "", m.lr_hdri.bind(sid), "light sky map hdri environment background " + sid.replace("_", " "), false,
			"the %s sky behind the figure and as its ambient light (a view setting; rotation and intensity in the rig panel)" % LightRig.SKY_NAMES[sid])
	for role in ["key", "fill", "rim"]:
		add.call("Light: %s lights the character only" % role, "", func(): m.lr_set_link(role, not bool(m.lr_link[role])), "light link linking character floor only layer cull mask " + role, false,
			"switch the %s light between lighting the character only and lighting everything (the floor too)" % role)


func show() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("LIGHT RIG", 14, "heading", true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", m._close_findings))
	L.add_child(m._label("Looks (placed relative to the shot camera; one Ctrl+Z each):", 13, "text:0.6", true))
	var row := HFlowContainer.new()
	L.add_child(row)
	for id in LightRig.ALL_IDS:
		var b: Button = m._button(LightRig.PANEL_NAMES[id], m.lr_preset.bind(id), LightRig.tip(id))
		b.name = "lr_preset_" + id
		row.add_child(b)
	L.add_child(m._label("Sky map (behind the figure and its ambient light):", 13, "text:0.6", true))
	var ob := OptionButton.new()
	ob.name = "lr_hdri"
	ob.add_item("None (flat colour)", 0)
	for i in LightRig.SKY_IDS.size():
		ob.add_item(LightRig.SKY_NAMES[LightRig.SKY_IDS[i]], i + 1)
	ob.item_selected.connect(func(idx: int):
		if not _busy:
			m.lr_hdri("" if idx == 0 else LightRig.SKY_IDS[idx - 1]))
	L.add_child(ob)
	L.add_child(_slider("lr_rot", "Rotation (degrees)", 0.0, 360.0, 1.0, m.lr_rot, func(v): m.lr_hdri_rot(v)))
	L.add_child(_slider("lr_int", "Intensity", 0.0, 4.0, 0.05, m.lr_int, func(v): m.lr_hdri_int(v)))
	L.add_child(m._label("Light linking (checked = lights the character only, the floor ignores it):", 13, "text:0.6", true))
	for role in ["key", "fill", "rim"]:
		var cb := CheckBox.new()
		cb.name = "lr_link_" + role
		cb.text = "%s light: character only" % role.capitalize()
		cb.toggled.connect(func(on: bool):
			if not _busy:
				m.lr_set_link(role, on))
		L.add_child(cb)
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(460, 380)
	m.ui_find.visible = true
	sync()
	m._say("light rig: pick a look, a sky map, and which lights skip the floor")


func _slider(nm: String, text: String, lo: float, hi: float, step: float, val: float, on: Callable) -> Control:
	var box := HBoxContainer.new()
	var lab: Label = m._label(text, 13, "text:0.6", true)
	lab.custom_minimum_size = Vector2(150, 0)
	box.add_child(lab)
	var sl := HSlider.new()
	sl.name = nm
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = val
	sl.custom_minimum_size = Vector2(220, 0)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.value_changed.connect(func(v: float):
		if not _busy:
			on.call(v))
	box.add_child(sl)
	return box


## the controls show the state (called after every change, from main._lr_view_apply)
func sync() -> void:
	var P: Node = m.ui_find
	if P == null or not P.visible:
		return
	_busy = true
	var ob := P.find_child("lr_hdri", true, false) as OptionButton
	if ob != null:
		ob.select(0 if m.lr_hdri_id == "" else LightRig.SKY_IDS.find(m.lr_hdri_id) + 1)
	var sr := P.find_child("lr_rot", true, false) as HSlider
	if sr != null:
		sr.value = m.lr_rot
	var si := P.find_child("lr_int", true, false) as HSlider
	if si != null:
		si.value = m.lr_int
	for role in ["key", "fill", "rim"]:
		var cb := P.find_child("lr_link_" + role, true, false) as CheckBox
		if cb != null:
			cb.button_pressed = bool(m.lr_link[role])
	_busy = false
