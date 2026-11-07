class_name PenPicker
extends RefCounted
## L135: the tablet pen choices (P09) as controls on a brush page's panel: what pressure scales (strength | radius | both | off) and,
## on the sculpt page, whether the pen tilt turns the stamp. page = "sculpt" | "vpaint" | "wpaint"; the value goes to the page's
## pen_target / pen_tilt and its KMeshPen, and into the access prefs (scripts/access_prefs.gd).
const TARGETS := ["strength", "radius", "both", "off"]


## the page starts from the remembered choice
static func load_into(ui, page: String) -> void:
	ui.set("pen_target", AccessPrefs.pen_target.get(page, "strength"))
	var pen = ui.get("_pen")
	if pen != null:
		pen.target = ui.get("pen_target")
	if page == "sculpt":
		ui.set("pen_tilt", AccessPrefs.pen_tilt_sculpt)
		ui._pen_sync()


static func add(box: Control, ui, page: String) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = "Pen"
	h.add_child(l)
	var o := OptionButton.new()
	o.name = page + "_pen_target"
	o.tooltip_text = "What the pen pressure changes: strength, brush size, both, or nothing (off). A mouse is unaffected."
	o.focus_mode = Control.FOCUS_NONE
	for t in TARGETS:
		o.add_item(t)
	o.select(maxi(0, TARGETS.find(String(ui.get("pen_target")))))
	o.item_selected.connect(func(i: int):
		ui.set("pen_target", TARGETS[i])
		var pen = ui.get("_pen")
		if pen != null:
			pen.target = TARGETS[i]
		AccessPrefs.pen_target[page] = TARGETS[i]
		AccessPrefs.save("pen_target_" + page, TARGETS[i]))
	h.add_child(o)
	box.add_child(h)
	if page == "sculpt":
		var c := CheckBox.new()
		c.name = "sculpt_pen_tilt"
		c.text = "Pen tilt turns the stamp"
		c.focus_mode = Control.FOCUS_NONE
		c.button_pressed = bool(ui.get("pen_tilt"))
		c.toggled.connect(func(v: bool):
			ui.set("pen_tilt", v)
			ui._pen_sync()
			AccessPrefs.pen_tilt_sculpt = v
			AccessPrefs.save("pen_tilt_sculpt", v))
		box.add_child(c)
