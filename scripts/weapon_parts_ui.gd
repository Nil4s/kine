class_name WeaponPartsUI
extends RefCounted
## B28 commands of the MODEL page (mesh_tools.gd "op:wpart_*"): tag the selected faces as grip / guard / blade / pommel (one undo
## step each), and "wpart_book" puts the tagged weapon in the grip book with its mass and centre of mass (scripts/weapon_parts.gd).


## the words it said
static func op(name: String, m) -> String:
	var ui = m.kmed
	var mesh: KMesh = ui.mesh
	if name == "wpart_book":
		var r := WeaponParts.join_book(mesh, WeaponParts.model_name, WeaponParts.mats)
		if not r["ok"]:
			return "Model: not in the grip book: " + String(r["why"])
		return "Model: in the grip book as %s: %.3f kg, centre of mass (%.1f, %.1f, %.1f) cm" % [r["kind"], r["mass_kg"], r["com"].x * 100.0, r["com"].y * 100.0, r["com"].z * 100.0]
	var role := name.trim_prefix("wpart_")
	if WeaponParts.id_of(role) <= 0:
		return ""
	panel(m)
	var fs := KMeshFaceSetsUI.selected_faces(ui)
	if fs.is_empty():
		return "Model: select the faces of the %s first" % role
	WeaponParts.ensure(mesh)   # the channel exists before the step, as the diff wants
	ui.undo.begin(mesh)
	var n := WeaponParts.tag(mesh, fs, role)
	ui.undo.commit("Tag weapon part: " + role)
	ui.view.mark_dirty()
	return "Model: %d faces tagged as the %s (one undo step)" % [n, role]


## L135: the panel with the grip-book name and a material per part (KMeshMeasure.MATERIALS); made once, shown by the tag commands.
## Choices go into WeaponParts.model_name / mats and the access prefs.
static func panel(m) -> PanelContainer:
	var old = m.ui_root.get_node_or_null("wpart_panel")
	if old != null:
		old.visible = true
		return old
	var p := PanelContainer.new()
	p.name = "wpart_panel"
	var vb := VBoxContainer.new()
	p.add_child(vb)
	var t := Label.new()
	t.text = "Weapon parts"
	vb.add_child(t)
	var le := LineEdit.new()
	le.name = "wpart_name"
	le.placeholder_text = "grip book name"
	le.tooltip_text = "The name the weapon gets in the grip book (kind model_<name>)."
	le.custom_minimum_size = Vector2(190, 0)
	le.text = WeaponParts.model_name
	var set_name := func(s: String):
		var n := s.strip_edges().to_lower()
		WeaponParts.model_name = n if n != "" else "sword"
		AccessPrefs.save("wp_name", WeaponParts.model_name)
	le.text_changed.connect(set_name)
	le.text_submitted.connect(set_name)
	vb.add_child(le)
	var names: Array = KMeshMeasure.MATERIALS.keys()
	for r in WeaponParts.ROLES:
		var h := HBoxContainer.new()
		var l := Label.new()
		l.text = String(r).capitalize()
		l.custom_minimum_size = Vector2(60, 0)
		h.add_child(l)
		var o := OptionButton.new()
		o.name = "wpart_mat_" + r
		for n in names:
			o.add_item(String(n))
		o.select(maxi(0, names.find(String(WeaponParts.mats.get(r, WeaponParts.DEFAULT_MAT[r])))))
		o.item_selected.connect(func(i: int):
			WeaponParts.mats[r] = String(names[i])
			AccessPrefs.save("wp_mat_" + r, String(names[i])))
		h.add_child(o)
		vb.add_child(h)
	var b := Button.new()
	b.name = "wpart_book_btn"
	b.text = "Add to grip book"
	b.pressed.connect(func(): m._say(op("wpart_book", m)))
	vb.add_child(b)
	m.ui_root.add_child(p)
	p.reset_size()
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	return p
