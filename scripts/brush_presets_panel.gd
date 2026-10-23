class_name BrushPresetsPanel
extends PanelContainer
## The brush presets panel (ROADMAP_400 C14; the presets, files and thumbnails are scripts/brush_presets.gd). In sculpt,
## B (or "Presets (B)" on the matcap strip) opens and closes it. It sits at the left of the clear view, under the matcap
## strip, so the sphere in the middle stays clear. Rows:
##   one row per preset, the starred ones first: its thumbnail (the stroke on a plane) and name, a click applies it (every
##   field: brush, radius, strength, falloff, spacing, symmetry); the star on the right marks / unmarks a favourite
##   a name box and "Save current brush as preset": the sculpt UI's brush as it is now goes to user://brush_presets.json

const W := 250.0

var ui                       # the KMeshSculptUI
var lib: BrushPresets
var list: VBoxContainer
var name_box: LineEdit
var entries: Array = []      # the presets the list shows, in its order
var rows := {}               # preset name -> {"btn": Button, "star": Button}
var _gen := 0
static var _stars := {}


func _init(sculpt_ui) -> void:
	ui = sculpt_ui
	name = "brush_presets_panel"
	visible = false
	var st := StyleBoxFlat.new()
	st.bg_color = Tok.c("float")
	st.set_corner_radius_all(8)
	st.set_content_margin_all(8)
	add_theme_stylebox_override("panel", st)
	lib = BrushPresets.new()
	lib.name = "brush_presets"
	add_child(lib)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	add_child(vb)
	var hb0 := HBoxContainer.new()
	var title := Label.new()
	title.text = "Brush presets"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb0.add_child(title)
	var x := Button.new()
	x.name = "btn_presets_close"
	x.text = "x"
	x.focus_mode = Control.FOCUS_NONE
	x.tooltip_text = "close the presets (B)"
	x.pressed.connect(close)
	hb0.add_child(x)
	vb.add_child(hb0)
	var sc := ScrollContainer.new()
	sc.name = "presets_scroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(W, 120)
	vb.add_child(sc)
	list = VBoxContainer.new()
	list.name = "presets_list"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	sc.add_child(list)
	name_box = LineEdit.new()
	name_box.name = "presets_name"
	name_box.placeholder_text = "name for your brush"
	vb.add_child(name_box)
	var sv := Button.new()
	sv.name = "btn_presets_save"
	sv.text = "Save current brush as preset"
	sv.tooltip_text = "the brush as it is now (type, radius, strength, falloff, spacing, symmetry) becomes a preset of yours"
	sv.pressed.connect(save_current)
	vb.add_child(sv)


## a star picture (filled = a favourite), drawn once
static func star(filled: bool) -> Texture2D:
	if _stars.has(filled):
		return _stars[filled]
	var n := 18
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + i * PI / 5.0
		var r := 8.5 if i % 2 == 0 else 3.6
		pts.append(Vector2(n / 2.0 + r * cos(a), n / 2.0 + 0.6 + r * sin(a)))
	var col := Color(1.0, 0.78, 0.2)
	for py in n:
		for px in n:
			var q := Vector2(px + 0.5, py + 0.5)
			var inside := Geometry2D.is_point_in_polygon(q, pts)
			var edge := INF
			for i in pts.size():
				edge = minf(edge, Geometry2D.get_closest_point_to_segment(q, pts[i], pts[(i + 1) % pts.size()]).distance_to(q))
			if (filled and inside) or edge < 0.8:
				img.set_pixel(px, py, col)
	_stars[filled] = ImageTexture.create_from_image(img)
	return _stars[filled]


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	visible = true
	fill()
	place()
	ui.m._say("Sculpt: brush presets. Click one to use it, the star keeps it at the top; B closes")


func close() -> void:
	visible = false
	_gen += 1


func _process(_dt: float) -> void:
	if visible and not ui.on:
		close()
	if visible:
		place()


## the left of the clear view, under the matcap strip; as tall as the clear view allows
func place() -> void:
	var cl: Rect2 = ui.m.nav_clear_rect()
	var top := cl.position.y + 12.0
	if ui.matcap != null and ui.matcap.strip.visible:
		top = ui.matcap.strip.get_global_rect().end.y + 8.0
	var w := get_combined_minimum_size().x
	size = Vector2(w, minf(520.0, cl.end.y - top - 12.0))
	global_position = Vector2(cl.position.x + 12.0, top)


## the presets, favourites first (each group in its own order), and their thumbnails as they come
func fill() -> void:
	_gen += 1
	var gen := _gen
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	rows.clear()
	var fav := BrushPresets.favourites()
	var a := []
	var b := []
	for e in BrushPresets.all():
		(a if fav.has(e["name"]) else b).append(e)
	entries = a + b
	for e in entries:
		var hb := HBoxContainer.new()
		var bt := Button.new()
		bt.name = "preset_" + String(e["name"]).validate_node_name()
		bt.text = e["name"]
		bt.alignment = HORIZONTAL_ALIGNMENT_LEFT
		bt.expand_icon = false
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bt.focus_mode = Control.FOCUS_NONE
		bt.tooltip_text = "%s: radius %d mm, strength %.1f mm, %s falloff, spacing %d %%%s" % [e["brush"], roundi(float(e["radius"]) * 1000.0),
			float(e["strength"]) * 1000.0, e["falloff"], roundi(float(e["spacing"]) * 100.0), " (yours)" if e["user"] else ""]
		var pic := lib.picture(e)
		bt.icon = pic if pic != null else null
		bt.add_theme_constant_override("icon_max_width", 40)
		bt.pressed.connect(pick.bind(e))
		hb.add_child(bt)
		var sb := Button.new()
		sb.name = "star_" + String(e["name"]).validate_node_name()
		sb.flat = true
		sb.focus_mode = Control.FOCUS_NONE
		sb.icon = star(fav.has(e["name"]))
		sb.tooltip_text = "favourite: starred presets come first"
		sb.pressed.connect(set_star.bind(e["name"]))
		hb.add_child(sb)
		list.add_child(hb)
		rows[e["name"]] = {"btn": bt, "star": sb}
	_pictures(gen)


func _pictures(gen: int) -> void:
	for e in entries.duplicate():
		if gen != _gen or not is_inside_tree():
			return
		var t: Texture2D = await lib.thumb(e)
		if gen != _gen:
			return
		if t != null and rows.has(e["name"]):
			(rows[e["name"]]["btn"] as Button).icon = t


## every field of the preset onto the sculpt brush
func pick(e: Dictionary) -> void:
	BrushPresets.apply(ui, e)
	ui._ov.queue_redraw()
	ui.m._say("Sculpt: preset %s: %s, radius %d mm, strength %.1f mm, %s falloff, symmetry %s" % [e["name"], ui.brush, roundi(ui.radius * 1000.0),
		ui.strength * 1000.0, ui.falloff, ui.sym_words()])


func set_star(nm: String) -> void:
	var on := not BrushPresets.is_favourite(nm)
	BrushPresets.set_favourite(nm, on)
	fill()
	ui.m._say("Sculpt: %s %s the favourites" % [nm, "is in" if on else "left"])


## the sculpt brush as it is now -> a user preset (the name box, else "My brush N"); true when saved
func save_current(nm := "") -> bool:
	if nm == "":
		nm = name_box.text.strip_edges()
	if nm == "":
		nm = "My brush %d" % (BrushPresets.user_presets().size() + 1)
	var err := BrushPresets.save_user(BrushPresets.of_ui(ui, nm))
	if err != OK:
		ui.m._say("Sculpt: could not save the preset (%s)" % error_string(err))
		return false
	name_box.text = ""
	fill()
	ui.m._say("Sculpt: saved your brush as \"%s\" (in the presets list)" % nm)
	return true


## B toggles the panel. true = used
func input(ev: InputEvent) -> bool:
	if not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return false
	var ke := ev as InputEventKey
	if ke.keycode == KEY_B and not ke.shift_pressed and not ke.ctrl_pressed and not ke.alt_pressed and not ke.meta_pressed:
		toggle()
		return true
	return false
