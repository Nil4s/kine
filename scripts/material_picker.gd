class_name MaterialPicker
extends RefCounted
## MATERIAL PICKER (Friday plan 223): the "Material" chips with swatches and the words box, one widget for Expert's Appearance panel and
## Easy Part's Colour page. build() adds to `parent`: a flow of one swatch chip per library material (names <prefix>mat_<id>), a line edit
## (<prefix>mat_words) and a one-line answer label (<prefix>mat_say). on_pick(spec: Dictionary, label: String) is called by a chip or by a
## words line that named a material; the answer label lists the words it did not know.

static func build(parent: Control, prefix: String, on_pick: Callable, chip_px := 34) -> Dictionary:
	var flow := HFlowContainer.new()
	flow.name = prefix + "mat_chips"
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 4)
	parent.add_child(flow)
	var chips := {}
	for id in MaterialMaker.library_ids():
		var b := Button.new()
		b.name = prefix + "mat_" + String(id)
		b.custom_minimum_size = Vector2(chip_px, chip_px)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = MaterialMaker.label_of(id)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chips[id] = b
		var spec := MaterialMaker.library_spec(id)
		b.pressed.connect(func(): on_pick.call(spec, MaterialMaker.label_of(id)))
		flow.add_child(b)
	var ed := LineEdit.new()
	ed.name = prefix + "mat_words"
	ed.placeholder_text = "or say it: dark oak, red lacquer a bit worn"
	ed.clear_button_enabled = true
	ed.custom_minimum_size.x = 230.0
	parent.add_child(ed)
	var say := Label.new()
	say.name = prefix + "mat_say"
	say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	say.custom_minimum_size.x = 230.0
	say.add_theme_font_size_override("font_size", 12)
	say.visible = false
	parent.add_child(say)
	ed.text_submitted.connect(func(t: String):
		var r := MaterialWords.parse(t)
		var unk: Array = r["unknown"]
		if not bool(r["ok"]):
			say.text = "No material in that. I know oak, pine, steel, copper, lacquer, tile, marble, brick, leather... and colours" + (" (not known: %s)" % ", ".join(unk) if not unk.is_empty() else "")
			say.visible = true
			return
		say.text = "Understood: %s%s" % [MaterialWords.describe(r["spec"]), ("; not known: %s" % ", ".join(unk)) if not unk.is_empty() else ""]
		say.visible = true
		on_pick.call(r["spec"], t.strip_edges()))
	return {"chips": chips, "edit": ed, "say": say, "flow": flow, "filled": false}


## the swatch pictures, drawn once the panel is first shown (a 64 px render of each recipe: a fraction of a second in all)
static func fill(w: Dictionary) -> void:
	if bool(w.get("filled", false)):
		return
	w["filled"] = true
	for id in w["chips"]:
		var im := MaterialMaker.swatch(MaterialMaker.library_spec(id), 28)
		if im != null:
			(w["chips"][id] as Button).icon = ImageTexture.create_from_image(im)
