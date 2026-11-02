## The camera navigation panel (triage W01): a small window with the preset, the three gestures, what the orbit turns around,
## zoom to cursor and trackpad-safe. Every change is applied and saved at once (scripts/cam_nav.gd).
class_name CamNavUI
extends RefCounted

const CHOICES := ["Right", "Middle", "Left", "Alt+Left", "Alt+Middle", "Alt+Right", "Shift+Middle", "Shift+Right", "Ctrl+Middle", "Ctrl+Right", ""]
var m: Node
var cn: CamNav
var win: Window
var _rows := {}


func _init(main: Node, nav: CamNav) -> void:
	m = main
	cn = nav


func _label_of(b: String) -> String:
	return "off" if b == "" else b + " drag"


func open() -> void:
	if win == null or not is_instance_valid(win):
		_build()
	_sync()
	win.popup_centered()


func _opt(id: String, title: String, items: Array, vb: VBoxContainer, cb: Callable) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = title
	l.custom_minimum_size.x = 150
	h.add_child(l)
	var o := OptionButton.new()
	o.name = id
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for it in items:
		o.add_item(it[1])
	o.item_selected.connect(func(i: int): cb.call(items[i][0]))
	h.add_child(o)
	vb.add_child(h)
	_rows[id] = [o, items]


func _build() -> void:
	win = Window.new()
	win.title = "Camera navigation"
	win.size = Vector2i(460, 330)
	win.exclusive = false
	win.close_requested.connect(func(): win.hide())
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_FULL_RECT)
	win.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	pc.add_child(vb)
	var pr: Array = []
	for nm in CamNav.PRESETS:
		pr.append([nm, nm])
	pr.append(["Custom", "Custom"])
	_opt("preset", "Preset", pr, vb, func(v): _set_preset(v))
	var ch: Array = []
	for c in CHOICES:
		ch.append([c, _label_of(c)])
	_opt("orbit", "Orbit", ch, vb, func(v): cn.orbit = v; _changed())
	_opt("pan", "Pan", ch, vb, func(v): cn.pan = v; _changed())
	_opt("zoom_drag", "Zoom drag (wheel always zooms)", ch, vb, func(v): cn.zoom_drag = v; _changed())
	_opt("pivot", "Orbit around", [["target", "the view centre"], ["cursor", "the point under the cursor"], ["selection", "the selection"]], vb, func(v): cn.pivot = v; _changed())
	var z := CheckBox.new()
	z.name = "zoom_cursor"
	z.text = "Zoom to cursor"
	z.toggled.connect(func(on: bool): cn.zoom_cursor = on; _changed())
	vb.add_child(z)
	var t := CheckBox.new()
	t.name = "trackpad"
	t.text = "Trackpad-safe: two-finger scroll pans, pinch zooms"
	t.toggled.connect(func(on: bool): cn.trackpad = on; _changed())
	vb.add_child(t)
	m.add_child(win)
	win.hide()


func _set_preset(nm: String) -> void:
	if nm != "Custom":
		cn.apply_preset(nm)
	_changed()


func _changed() -> void:
	cn.save_to(m.settings)
	_sync()


func _sync() -> void:
	if win == null:
		return
	var vals := {"preset": cn.preset_name(), "orbit": cn.orbit, "pan": cn.pan, "zoom_drag": cn.zoom_drag, "pivot": cn.pivot}
	for id in vals:
		var o: OptionButton = _rows[id][0]
		var items: Array = _rows[id][1]
		for i in items.size():
			if items[i][0] == vals[id]:
				o.select(i)
	(win.find_child("zoom_cursor", true, false) as CheckBox).set_pressed_no_signal(cn.zoom_cursor)
	(win.find_child("trackpad", true, false) as CheckBox).set_pressed_no_signal(cn.trackpad)
