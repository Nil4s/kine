class_name MaterialPicker
extends RefCounted
## MATERIAL PICKER (Friday plan 223): the "Material" chips with swatches and the words box, one widget for Expert's Appearance panel and
## Easy Part's Colour page. build() adds to `parent`: a flow of one swatch chip per library material (names <prefix>mat_<id>), a line edit
## (<prefix>mat_words) and a one-line answer label (<prefix>mat_say). on_pick(spec: Dictionary, label: String) is called by a chip or by a
## words line that named a material; the answer label lists the words it did not know.

## s231: on_kind(kind, spec, label) is called instead of on_pick when a PIECE is aimed (a chip of PieceLook.CHIPS, or a piece noun in the words:
## "red lacquer columns"); on_style(style) by the "Temple look" button. Without them the widget is what 223 made.
static func build(parent: Control, prefix: String, on_pick: Callable, chip_px := 34, on_kind := Callable(), on_style := Callable()) -> Dictionary:
	var w := {"kind": ""}
	if on_kind.is_valid():
		var aim := HFlowContainer.new()
		aim.name = prefix + "mat_aim"
		aim.add_theme_constant_override("h_separation", 3)
		aim.add_theme_constant_override("v_separation", 3)
		parent.add_child(aim)
		var lab := Label.new()
		lab.text = "Aim at:"
		lab.add_theme_font_size_override("font_size", 12)
		aim.add_child(lab)
		var group := ButtonGroup.new()
		var aims := {}
		var first := Button.new()
		first.text = "this solid"
		first.name = prefix + "aim_"
		first.toggle_mode = true
		first.button_group = group
		first.button_pressed = true
		first.focus_mode = Control.FOCUS_NONE
		first.pressed.connect(func(): w["kind"] = "")
		aim.add_child(first)
		aims[""] = first
		for c in PieceLook.CHIPS:
			var ab := Button.new()
			ab.text = String(c[1])
			ab.name = prefix + "aim_" + String(c[0])
			ab.toggle_mode = true
			ab.button_group = group
			ab.focus_mode = Control.FOCUS_NONE
			ab.tooltip_text = "Every %s piece of the building gets the next material you pick" % String(c[1]).to_lower()
			var kd := String(c[0])
			ab.pressed.connect(func(): w["kind"] = kd)
			aim.add_child(ab)
			aims[kd] = ab
		w["aims"] = aims
		if on_style.is_valid():
			var tb := Button.new()
			tb.text = "Temple look"
			tb.name = prefix + "temple_look"
			tb.focus_mode = Control.FOCUS_NONE
			tb.tooltip_text = "Every piece that is not painted wears its kind's material: tile roof, red lacquer columns, teal and gold beams, marble, stone slabs"
			tb.pressed.connect(func(): on_style.call("temple"))
			aim.add_child(tb)
			var pb := Button.new()
			pb.text = "Plain"
			pb.name = prefix + "plain_look"
			pb.focus_mode = Control.FOCUS_NONE
			pb.tooltip_text = "Back to the plain colours of the building"
			pb.pressed.connect(func(): on_style.call("none"))
			aim.add_child(pb)
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
		b.pressed.connect(func():
			if String(w["kind"]) != "" and on_kind.is_valid():
				on_kind.call(String(w["kind"]), spec, MaterialMaker.label_of(id))
			else:
				on_pick.call(spec, MaterialMaker.label_of(id)))
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
		if on_kind.is_valid():
			var pr := PieceLook.parse(t)   # a piece noun ("columns", "roof tiles") aims the words at every piece of that kind
			if String(pr["kind"]) != "" and bool(pr["ok"]):
				say.text = "%s: %s%s" % [String(PieceLook.LABELS.get(pr["kind"], pr["kind"])), MaterialWords.describe(pr["spec"]), ("; not known: %s" % ", ".join(pr["unknown"])) if not (pr["unknown"] as Array).is_empty() else ""]
				say.visible = true
				on_kind.call(String(pr["kind"]), pr["spec"], t.strip_edges())
				return
		var unk: Array = r["unknown"]
		if not bool(r["ok"]):
			say.text = "No material in that. I know oak, pine, steel, copper, lacquer, tile, marble, brick, leather... and colours" + (" (not known: %s)" % ", ".join(unk) if not unk.is_empty() else "")
			say.visible = true
			return
		say.text = "Understood: %s%s" % [MaterialWords.describe(r["spec"]), ("; not known: %s" % ", ".join(unk)) if not unk.is_empty() else ""]
		say.visible = true
		on_pick.call(r["spec"], t.strip_edges()))
	w.merge({"chips": chips, "edit": ed, "say": say, "flow": flow, "filled": false}, true)
	return w


## the swatch pictures, drawn once the panel is first shown (a 64 px render of each recipe: a fraction of a second in all)
static func fill(w: Dictionary) -> void:
	if bool(w.get("filled", false)):
		return
	w["filled"] = true
	for id in w["chips"]:
		var im := MaterialMaker.swatch(MaterialMaker.library_spec(id), 28)
		if im != null:
			(w["chips"][id] as Button).icon = ImageTexture.create_from_image(im)
