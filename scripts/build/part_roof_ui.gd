class_name PartRoofUI
extends RefCounted
## s226: the Expert Part "Roof" tool's dialog rows (the fields of scripts/build/part_roof.gd). part_ui.gd calls open_rows() when the dialog opens,
## feature() for the numbers typed (the live preview and OK use it) and hint() for the line under the rows.
## Each row: a label, a LineEdit named part_roof_<field>, the unit. The type is a pick (OptionButton part_roof_type); trims are check boxes.

const ROWS := [
	["w", "Width X", "mm", 8000.0], ["d", "Depth Z", "mm", 6000.0], ["overhang", "Overhang", "mm", 600.0],
	["height", "Ridge (0 = pitch)", "mm", 2500.0], ["pitch", "Pitch", "deg", 30.0], ["thick", "Thickness", "mm", 60.0],
	["sag", "Sag (curve)", "mm", 0.0], ["lift", "Corner lift", "mm", 0.0], ["lift_len", "Lift length (0 = auto)", "mm", 0.0],
	["gable_in", "Gable in (0 = auto)", "mm", 0.0], ["hole_w", "Open top W (0 = shut)", "mm", 0.0], ["hole_d", "Open top D", "mm", 0.0],
	["y", "Eave height", "mm", 0.0]]
const TRIMS := [["ridge", "Ridge body"], ["hips", "Hip bodies"], ["eave", "Eave body"]]


static func open_rows(pu: Node, f: Dictionary, edit: int) -> void:
	var ctl := {}
	var tp := OptionButton.new()
	tp.name = "part_roof_type"
	for t in PartRoof.TYPES:
		tp.add_item(String(t))
	tp.select(maxi(PartRoof.TYPES.find(String(f.get("type", "hip"))), 0))
	tp.item_selected.connect(func(_i): pu._preview())
	var h := HBoxContainer.new()
	var l: Label = pu._label("Roof type")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(tp)
	pu.dlg_rows.add_child(h)
	ctl["type"] = tp
	var half: HBoxContainer = null   # two fields to a row: the window is 720 high and the dialog has 13 numbers
	for r in ROWS:
		var key := String(r[0])
		var v := float(r[3])
		if key == "y":
			v = float((f.get("at", [0, 0, 0]) as Array)[1]) if f.has("at") else 0.0
		elif key == "hole_w":
			v = float((f.get("hole", [0, 0]) as Array)[0]) if f.has("hole") else 0.0
		elif key == "hole_d":
			v = float((f.get("hole", [0, 0]) as Array)[1]) if f.has("hole") else 0.0
		elif f.has(key):
			v = float(f[key])
		var le := LineEdit.new()
		le.name = "part_roof_" + key
		le.custom_minimum_size = Vector2(64, 0)
		le.size_flags_horizontal = Control.SIZE_SHRINK_END
		le.text_changed.connect(func(_t): pu._preview())
		le.text_submitted.connect(func(_t): pu.ok_pressed())
		le.text = pu._fmt(v)
		le.tooltip_text = "%s (%s)" % [String(r[1]), String(r[2])]
		if half == null:
			half = HBoxContainer.new()
			pu.dlg_rows.add_child(half)
		var lb: Label = pu._label(String(r[1]), 13)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		half.add_child(lb)
		half.add_child(le)
		if half.get_child_count() >= 4 or key == "y":
			half = null
		ctl[key] = le
	var trow := HBoxContainer.new()
	pu.dlg_rows.add_child(trow)
	for tr in TRIMS:
		var cb := CheckBox.new()
		cb.name = "part_roof_" + String(tr[0])
		cb.text = String(tr[1])
		cb.button_pressed = bool(f.get(String(tr[0]), false))
		cb.toggled.connect(func(_b): pu._preview())
		trow.add_child(cb)
		ctl[String(tr[0])] = cb
	pu.dlg["roof"] = ctl


static func feature(pu: Node) -> Dictionary:
	var ctl: Dictionary = pu.dlg.get("roof", {})
	if ctl.is_empty():
		return {}
	var num := func(k: String) -> float:
		var s := (ctl[k] as LineEdit).text.strip_edges()
		return s.to_float() if s.is_valid_float() else NAN
	var out := {"type": PartRoof.TYPES[clampi((ctl["type"] as OptionButton).selected, 0, PartRoof.TYPES.size() - 1)]}
	for k in ["w", "d", "overhang", "height", "pitch", "thick", "sag", "lift", "lift_len", "gable_in"]:
		var v: float = num.call(k)
		if is_nan(v):
			return {}
		out[k] = v
	var hw: float = num.call("hole_w")
	var hd: float = num.call("hole_d")
	var y: float = num.call("y")
	if is_nan(hw) or is_nan(hd) or is_nan(y):
		return {}
	if out["w"] < 100.0 or out["d"] < 100.0 or out["thick"] < 1.0 or out["pitch"] <= 0.0:
		return {}
	if hw > 0.0 and hd > 0.0:
		out["hole"] = [hw, hd]
	out["at"] = [0.0, y, 0.0]
	for tr in TRIMS:
		if (ctl[String(tr[0])] as CheckBox).button_pressed:
			out[String(tr[0])] = true
	return out


static func hint() -> String:
	return "Type the plan size, the ridge height and the shell thickness. Sag curves the slope, Corner lift turns the eave corners up."
