## s226 ROOFS (Easy Part, Parts > Roofs): one chip per roof type (Hip, Gable, Chinese hip, Pyramid, Shed, Flat) and a Curved chip (the concave slope and the
## lifted corners of a Chinese roof). A chip puts a thin roof shell on the floor; a roof already there changes type (one undo step either way).
## The geometry is scripts/build/part_roof.gd; this file is only the page.
extends VBoxContainer

const TYPES := [["hip", "Hip"], ["gable", "Gable"], ["xieshan", "Hip and gable"], ["pyramid", "Pyramid"], ["shed", "Shed"], ["flat", "Flat"]]
const SIZE := {"w": 4000.0, "d": 3000.0, "overhang": 400.0, "height": 1200.0, "thick": 40.0}
var ep: Node
var btns := {}
var curve_btn: Button
var words: Label
var curved := false


func setup(easy: Node) -> void:
	ep = easy
	name = "easypart_roofs"
	visible = false
	add_theme_constant_override("separation", 3)
	words = Label.new()
	words.name = "easypart_roof_words"
	words.text = "Roofs, thin shells: pick a type. It drops on the floor. Curved gives it the Chinese sag and raised corners"
	words.add_theme_font_size_override("font_size", 13)
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(words)
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 3)
	fl.add_theme_constant_override("v_separation", 3)
	add_child(fl)
	for t in TYPES:
		var b := _chip("easypart_roof_" + String(t[0]), String(t[1]), "%s roof, %d x %d mm, a %d mm thick shell. One click, one undo step" % [String(t[1]), int(SIZE["w"]), int(SIZE["d"]), int(SIZE["thick"])], _pick.bind(String(t[0])))
		fl.add_child(b)
		btns[t[0]] = b
	curve_btn = _chip("easypart_roof_curved", "Curved", "The slope dips in the middle and the eave corners turn up (a Chinese roof). Press a type after it, or press it with a roof on the floor", _curve_press)
	fl.add_child(curve_btn)


func _chip(nm: String, txt: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = txt
	b.tooltip_text = tip
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 30)
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(cb)
	return b


## the roof step of the part on the floor, or {}
func _cur() -> Dictionary:
	var fs: Array = ep._rec().get("features", [])
	if fs.size() == 1 and String((fs[0] as Dictionary).get("t", "")) == "roof":
		return fs[0]
	return {}


func sync() -> void:
	var cur := _cur()
	visible = (ep.parts_open and ep.lib_cat == "Roofs") or not cur.is_empty()
	for t in btns:
		var b: Button = btns[t]
		b.set_pressed_no_signal(not cur.is_empty() and String(cur.get("type", "")) == String(t))
		ep.m._grey(b, Part.why_not() if not Part.available() else "")
	if not cur.is_empty():
		curved = float(cur.get("sag", 0.0)) > 0.0
	curve_btn.set_pressed_no_signal(curved)


## the numbers of a roof of this type (the Curved chip on or off), sitting on the floor
func fields(type: String) -> Dictionary:
	var f := SIZE.duplicate()
	f["type"] = type
	if type == "flat":
		f.erase("height")
	if curved and type != "flat":
		f["sag"] = 0.12 * float(SIZE["height"])
		f["lift"] = 0.2 * float(SIZE["height"]) if type != "shed" else 0.0
		f["lift_len"] = 900.0
	var low := 1e12
	for v in (PartRoof.meshes(f)[0]["v"] as PackedVector3Array):
		low = minf(low, v.y)
	f["at"] = [0.0, -low, 0.0]
	return f


func _pick(type: String) -> void:
	if not Part.available():
		ep._chips_sync()
		return
	var cur := _cur()
	if not cur.is_empty() and String(cur.get("type", "")) == type:
		ep._say("Already a %s roof on the floor. Pick another type to change it" % type)
		ep._screw_sync()
		return
	_make(type, cur)


func _make(type: String, cur: Dictionary) -> void:
	ep.armed = ""
	ep.hole_base = {}
	ep.split_id = ""
	ep._flush_if_dirty()
	ep.m._step_hint = "Change the roof" if not cur.is_empty() else "Start a roof"
	ep.m._push_undo()
	var f := fields(type)
	if not cur.is_empty():
		var rec: Dictionary = ep._rec()
		var feat: Dictionary = (rec["features"] as Array)[0]
		for k in ["sag", "lift", "lift_len", "height"]:
			feat.erase(k)
		feat.merge(f, true)
	else:
		var rec := Part.make("Roof")
		(rec["features"] as Array).append(Part.new_feature(rec, "roof", f))
		ep.m.S.part = rec
	ep.tweak = {}
	ep.pu.upto = -1
	ep.pu.sync()
	ep.frame()
	if not (ep.pu.res.get("errors", {}) as Dictionary).is_empty():
		ep._say("The roof did not build. Press Reset, then pick a type again")
	else:
		ep._say("A %s roof on the floor%s" % [type, ", curved" if curved else ""])
	ep._screw_sync()


func _curve_press() -> void:
	curved = curve_btn.button_pressed
	var cur := _cur()
	if not cur.is_empty() and Part.available():
		_make(String(cur.get("type", "hip")), cur)
	else:
		ep._say("Curved is %s. Pick a roof type" % ("on" if curved else "off"))
		ep._screw_sync()
