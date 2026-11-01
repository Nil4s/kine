class_name PartOrnamentEasy
extends RefCounted
## s227: Easy Part > Parts > Ornaments: one chip per ornament (a press adds it to the part, ONE undo step; with a roof's ridge in the part, the chiwen
## go on both ends of the ridge and the corner beasts along it), the "Sculpt this into the part" button (part_sculpt.gd), and Type it words
## ("2 chiwen on the ridge ends", "5 corner beasts") read by PartOrnament.parse.

static func make_box(ep) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.name = "easypart_ornament_box"
	pc.add_theme_stylebox_override("panel", ep._style(Color(0.12, 0.125, 0.15), 10, 6))
	pc.visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	pc.add_child(vb)
	var hd := Label.new()
	hd.name = "easypart_ornament_words"
	hd.text = "Ornaments: press one. It is added to the part (on the ridge, if the part has one). Type it also works: 2 chiwen on the ridge ends"
	hd.add_theme_font_size_override("font_size", 14)
	hd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hd)
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 4)
	fl.add_theme_constant_override("v_separation", 4)
	vb.add_child(fl)
	for k in PartOrnament.ORDER:
		var b := Button.new()
		b.name = "easypart_ornament_" + String(k)
		b.text = String(PartOrnament.KINDS[k]["name"]).get_slice(" (", 0)
		var sz := PartOrnament.default_size(String(k))
		b.tooltip_text = "%s: %d x %d x %d mm. One press adds it, one undo step takes it away" % [PartOrnament.KINDS[k]["name"], int(sz.x), int(sz.y), int(sz.z)]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 34)
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_stylebox_override("normal", ep._style(Color(0.165, 0.176, 0.212), 6, 4))
		b.add_theme_stylebox_override("hover", ep._style(Color(0.23, 0.245, 0.29), 6, 4))
		b.pressed.connect(pick.bind(ep, String(k)))
		fl.add_child(b)
	var sb := Button.new()
	sb.name = "easypart_ornament_sculpt"
	sb.text = "Sculpt this into the part"
	sb.tooltip_text = "Open the newest ornament (or the picked body, or a ball of clay) on the Sculpt page. Sculpt it, press Back into the part: it comes back as a solid in the same place, one undo step"
	sb.focus_mode = Control.FOCUS_NONE
	sb.custom_minimum_size = Vector2(0, 34)
	sb.add_theme_font_size_override("font_size", 13)
	sb.add_theme_stylebox_override("normal", ep._style(Color(0.2, 0.17, 0.1), 6, 4))
	sb.add_theme_stylebox_override("hover", ep._style(Color(0.3, 0.25, 0.14), 6, 4))
	sb.pressed.connect(func(): PartSculpt.open(ep.m))
	vb.add_child(sb)
	return pc


## a chip: the words that make this ornament on this part
static func pick(ep, kind: String) -> void:
	if not Part.available():
		ep._chips_sync()
		return
	var w := String(PartOrnament.KINDS[kind]["words"][0])
	var text := "1 " + w
	if kind == "chiwen" and not PartOrnament.ridge_of(ep._rec()).is_empty():
		text = "2 chiwen on the ridge ends"
	elif kind == "corner_row":
		text = "5 corner beasts" + (" on the ridge" if not PartOrnament.ridge_of(ep._rec()).is_empty() else "")
	words(ep, text)


## Type it / a chip: the sentence becomes an ornament step on the part. Says what it did; a refusal changes nothing
static func words(ep, text: String) -> void:
	ep._flush_if_dirty()
	ep.armed = ""
	var rec: Dictionary = (ep._rec() if not ep.m.S.part.is_empty() else Part.make("Part")).duplicate(true)
	var w := PartOrnament.from_words(text, rec)
	if not bool(w["ok"]):
		ep._say(String(w["why"]))
		return
	var feat := Part.new_feature(rec, "ornament", w["fields"])
	rec["features"].append(feat)
	var res := Part.replay(rec)
	if (res["errors"] as Dictionary).has(String(feat["id"])):
		ep._say("The ornament could not be made: %s" % String((res["errors"] as Dictionary)[String(feat["id"])]))
		return
	ep.m._step_hint = "Add " + String(feat["name"])
	ep.m._push_undo()
	ep.m.S.part = rec
	ep.tweak = {}
	ep.pu.upto = -1
	ep.pu.sync()
	ep.frame()
	ep._lib_fit()
	ep._say("%s added (%d piece%s). Undo takes it away. Sculpt this into the part changes its shape" % [String(w["said"]).capitalize(), int(res["bodies"]), "" if int(res["bodies"]) == 1 else "s"])
	ep._screw_sync()
