class_name ArmourUI
extends Node
## B23's panel and its preview copies (the op is scripts/armour_from_body.gd). "Model: armour from the body" (mesh_tools
## op:armour) opens the fighter's body in the model preview (G01) and a small panel at the top left of the free view:
##   the tags / regions to cover (words: "forearm_extensors_r, deltoid_l"; the anatomy brush's tag is the first guess),
##   the gap out from the skin, the thickness, the bevel (mm) and its segments, "Make plate" (one undo step) and "Close".
## Every frame (while it lives) it keeps the parts in step with the preview: each attached part has an unskinned copy under
## the preview's view while the body is open there (the fighter's pieces are hidden then, so are its parts), and no copy
## once a part is taken off (Ctrl+Z).

const NAME := "armour_ui"

var m: Node
var panel: PanelContainer
var words: LineEdit
var fields := {}   # "gap" / "thickness" / "bevel" (mm) / "segments" -> SpinBox


static func of(main: Node) -> ArmourUI:
	var u := main.get_node_or_null(NAME) as ArmourUI
	if u == null:
		u = ArmourUI.new()
		u.name = NAME
		u.m = main
		main.add_child(u)
	return u


## the op: open the body (when the preview holds something else) and the panel; again: the panel closes
static func toggle(main: Node) -> String:
	var u := of(main)
	if u.panel != null and u.panel.visible and BaseBody.is_open(main):
		u.panel.visible = false
		main._say("Model: armour panel closed")
		return "Model: armour panel closed"
	if not BaseBody.is_open(main):
		BaseBody.start(main)
		if not BaseBody.is_open(main):
			return String(main.ui_status.text) if main.get("ui_status") != null else ""
	u._build()
	u.panel.visible = true
	if main.kmed.anat != null and main.kmed.anat.brush != "" and u.words.text == "":
		u.words.text = main.kmed.anat.brush
	u._place()
	var said := "Model: armour from the body: type the anatomy tags or regions to cover (Alt+H shows the tags), then Make plate (one undo step)"
	main._say(said)
	return said


func _build() -> void:
	if panel != null:
		return
	panel = PanelContainer.new()
	panel.name = "armour_panel"
	var st := StyleBoxFlat.new()
	st.bg_color = Tok.c("float")
	st.set_corner_radius_all(8)
	st.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", st)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.custom_minimum_size = Vector2(260, 0)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "Armour from the body"
	vb.add_child(title)
	words = LineEdit.new()
	words.name = "armour_tags"
	words.text = "forearm_extensors_r"
	words.placeholder_text = "tags or regions: forearm_extensors_r, deltoid_l"
	words.tooltip_text = "anatomy tags (Alt+H: deltoid_l, pectoral, forearm_extensors_r ...) or body regions (Shift+H: forearm_r, shin_l ...); a tag without _l / _r takes both sides"
	words.text_submitted.connect(func(_t): make_plate())
	vb.add_child(words)
	var g := GridContainer.new()
	g.columns = 2
	vb.add_child(g)
	for f in [["gap", "Gap from skin (mm)", load("res://scripts/armour_from_body.gd").GAP * 1000.0, 0.0, 50.0, 0.5],
			["thickness", "Thickness (mm)", load("res://scripts/armour_from_body.gd").THICK * 1000.0, 0.5, 50.0, 0.5],
			["bevel", "Bevel (mm)", load("res://scripts/armour_from_body.gd").BEVEL * 1000.0, 0.0, 10.0, 0.25],
			["segments", "Bevel segments", load("res://scripts/armour_from_body.gd").SEGMENTS, 1, 8, 1]]:
		var lb := Label.new()
		lb.text = f[1]
		g.add_child(lb)
		var sb := SpinBox.new()
		sb.name = "armour_" + String(f[0])
		sb.min_value = f[3]
		sb.max_value = f[4]
		sb.step = f[5]
		sb.value = f[2]
		g.add_child(sb)
		fields[f[0]] = sb
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var mk := Button.new()
	mk.name = "btn_armour_make"
	mk.text = "Make plate"
	mk.tooltip_text = "a plate shell over those tags, gapped, thick, bevelled and skinned, added to the fighter (one undo step)"
	mk.pressed.connect(func(): make_plate())
	hb.add_child(mk)
	var cl := Button.new()
	cl.name = "btn_armour_close"
	cl.text = "Close"
	cl.pressed.connect(func(): panel.visible = false)
	hb.add_child(cl)
	m.ui_root.add_child(panel)


func _place() -> void:
	panel.reset_size()
	panel.position = Vector2(float(m.lw()) + 12.0, float(m.TOP_H) + 12.0)


func opts() -> Dictionary:
	return {"gap": fields["gap"].value / 1000.0, "thickness": fields["thickness"].value / 1000.0,
		"bevel": fields["bevel"].value / 1000.0, "segments": int(fields["segments"].value)}


## "Make plate": the op on the panel's words and fields; says what it did
func make_plate() -> Dictionary:
	var r = load("res://scripts/armour_from_body.gd").make(m, words.text, opts())
	m._say(r["said"])
	sync()
	return r


func _process(_dt: float) -> void:
	sync()


## the parts and the preview in step (see the header)
func sync() -> void:
	if m == null:
		return
	var open := BaseBody.is_open(m)
	var on: Array = load("res://scripts/armour_from_body.gd").parts(m)
	for mi in on:   # shown / hidden with the body pieces when the preview opens or closes (else left as they are)
		if is_instance_valid(mi) and (not (mi as Node).has_meta("armour_open") or bool((mi as Node).get_meta("armour_open")) != open):
			(mi as Node).set_meta("armour_open", open)
			(mi as MeshInstance3D).visible = not open
	if panel != null and panel.visible and not open:
		panel.visible = false
	if not open:
		return
	var view: Node3D = m.kmed.view
	var have := {}
	for c in view.get_children():
		if c.has_meta("armour_of"):
			var p = c.get_meta("armour_of")
			if not is_instance_valid(p) or not on.has(p):
				view.remove_child(c)
				c.queue_free()
			else:
				have[p] = true
	for mi in on:
		if is_instance_valid(mi) and not have.has(mi):
			var pv := MeshInstance3D.new()
			pv.name = "armour_preview_" + String((mi as Node).name)
			pv.mesh = load("res://scripts/armour_from_body.gd").array_mesh((mi as Node).get_meta("armour_kmesh"))
			pv.set_meta("armour_of", mi)
			view.add_child(pv)
