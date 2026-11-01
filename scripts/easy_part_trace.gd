class_name EasyPartTrace
extends RefCounted
## FRIDAY 43 SHAPE FROM A PHOTO: the Trace chip (Draw shape row). A picture (PNG / JPG) lies on the floor under the grid, centred on the
## middle, as wide as the Width box says (real mm). Trace it: the picture's dark shape becomes a closed sketch on the floor (threshold, the
## biggest outline plus the holes inside it, Douglas-Peucker; outline_tools.gd), pulled up HEIGHT_MM: ONE undo step. A hole in the picture is a
## hole in the part. The sketch stays a sketch in the step list, so its corners can still be edited.

const HEIGHT_MM := 10.0
const WIDTH_DEF := 80.0
const WIDTH_MIN := 5.0
const WIDTH_MAX := 2000.0
const MAX_CORNERS := 600   # more corners than this: the picture has too much detail for one sketch

var ep                       # the Easy Part that owns the chip (easy_part.gd)
var panel: PanelContainer
var width_box: SpinBox
var go_btn: Button
var info: Label
var node: MeshInstance3D = null   # the picture on the floor (a view node, not in the record)
var image: Image = null
var ai = null                # FRIDAY 191: Sketch with sizes (AI), easy_part_sketch_ai.gd
var last: Dictionary = {}    # what the last trace made: {"loops", "corners", "holes"}


func _init(easy) -> void:
	ep = easy


## the Trace chip: a file dialog for the picture
func pick() -> void:
	if not Part.available():
		ep._say(Part.why_not())
		return
	ep._flush_if_dirty()
	var fd := FileDialog.new()
	fd.name = "easypart_trace_dialog"
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp ; Pictures"])
	fd.title = "Pick the picture to trace"
	fd.file_selected.connect(func(p: String): fd.queue_free(); chosen(p))
	fd.canceled.connect(fd.queue_free)
	ep.shape_box.get_parent().add_child(fd)
	fd.popup_centered(Vector2i(640, 480))
	ep._say("Pick a picture: a dark shape on a light background traces best")


func chosen(path: String) -> void:
	var im := Image.load_from_file(path)
	if im == null or im.is_empty():
		ep._say("That file is not a picture we can read. Pick a PNG or JPG, then press Trace again")
		return
	show_image(im)


## the picture lies on the floor; the panel asks for its real width
func show_image(im: Image) -> void:
	image = im
	_build()
	_lay()
	panel.visible = true
	info.text = "Set the picture's real width, then press Trace it"
	go_btn.disabled = false
	ep._say("Your picture lies on the floor. Set its real width in mm, then press Trace it")


func width_mm() -> float:
	return width_box.value if width_box != null else WIDTH_DEF


func _build() -> void:
	if panel != null:
		return
	panel = PanelContainer.new()
	panel.name = "easypart_trace"
	panel.add_theme_stylebox_override("panel", ep._style(Color(0.1, 0.11, 0.14, 0.97), 10, 8))
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)   # left of the step list, clear of the status pills at the left edge
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = 262
	panel.offset_bottom = -64
	panel.z_index = 30
	panel.visible = false
	ep.shape_box.get_parent().add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	var top := Label.new()
	top.text = "Trace a picture"
	top.add_theme_font_size_override("font_size", 18)
	top.add_theme_color_override("font_color", Tok.c("heading"))
	vb.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	var lab := Label.new()
	lab.text = "Real width (mm)"
	lab.add_theme_font_size_override("font_size", 16)
	row.add_child(lab)
	width_box = SpinBox.new()
	width_box.name = "easypart_trace_width"
	width_box.min_value = WIDTH_MIN
	width_box.max_value = WIDTH_MAX
	width_box.step = 0.5
	width_box.value = WIDTH_DEF
	width_box.custom_minimum_size = Vector2(110, 36)
	width_box.value_changed.connect(func(_v: float): _lay())
	row.add_child(width_box)
	go_btn = _btn(row, "easypart_trace_go", "Trace it", "The picture's dark shape becomes a sketch on the floor, pulled up 10 mm (one undo step)", trace)
	_btn(row, "easypart_trace_close", "Close", "Take the picture off the floor: nothing is made", close)
	info = Label.new()
	info.name = "easypart_trace_info"
	info.add_theme_font_size_override("font_size", 15)
	info.add_theme_color_override("font_color", Tok.c("say"))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(330, 0)
	vb.add_child(info)
	ai = EasyPartSketchAI.new(self)   # FRIDAY 191: the AI option sits in this box
	ai.attach(vb)


func _btn(row: HBoxContainer, nm: String, text: String, tip: String, fn: Callable) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(100, 36)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(fn)
	row.add_child(b)
	return b


const SHOW_ALPHA := 0.7


## lay1: what is drawn on the floor (the traced pixels are the picture's own, untouched). The floor is dark, so a black shape was black on black: the dark
## shape is drawn light (white), the light background nearly clear, so the picture reads as a pale silhouette. At most 256 px on a side
static func display_image(src: Image) -> Image:
	var im := src.duplicate() as Image
	im.convert(Image.FORMAT_RGBA8)
	var big := maxi(im.get_width(), im.get_height())
	if big > 256:
		var k := 256.0 / float(big)
		im.resize(maxi(1, int(im.get_width() * k)), maxi(1, int(im.get_height() * k)), Image.INTERPOLATE_BILINEAR)
	for y in im.get_height():
		for x in im.get_width():
			var c := im.get_pixel(x, y)
			var dark := 1.0 - (c.r * 0.299 + c.g * 0.587 + c.b * 0.114)   # 1 = black, 0 = white
			im.set_pixel(x, y, Color(0.95, 0.96, 0.98, c.a * clampf(0.12 + 0.88 * dark, 0.0, 1.0)))
	return im


## (re)lay the picture flat on the floor, centred on the origin, width_mm wide (the height follows its shape)
func _lay() -> void:
	if image == null:
		return
	var w := width_mm()
	var h := w * float(image.get_height()) / float(image.get_width())
	if node != null and is_instance_valid(node):
		node.queue_free()
	var q := QuadMesh.new()
	q.size = Vector2(w * Part.MM, h * Part.MM)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = ImageTexture.create_from_image(display_image(image))
	mat.albedo_color = Color(1, 1, 1, SHOW_ALPHA)   # lay1: 70 % opaque, so the floor grid shows through
	q.material = mat
	node = MeshInstance3D.new()
	node.name = "easypart_trace_backdrop"
	node.mesh = q
	ep.m.cam.get_parent().add_child(node)
	# flat on the floor a hair under the grid; the picture's top edge points to -Z (the Top plane's +y)
	node.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, -0.0002, 0.0))


## Trace it: one undo step, a closed sketch (outline + holes) pulled up HEIGHT_MM
func trace() -> void:
	if image == null:
		ep._say("Pick a picture first: press Trace")
		return
	if not Part.available():
		ep._say(Part.why_not())
		return
	var got := OutlineTools.trace_image(image, width_mm())
	if String(got["why"]) != "":
		info.text = String(got["why"])
		ep._say(String(got["why"]))
		return
	var loops: Array = got["loops"]
	var corners := 0
	for lp in loops:
		corners += (lp as PackedVector2Array).size()
	if corners > MAX_CORNERS:
		var msg := "That picture has too much fine detail (%d corners). Use a plainer picture with bigger shapes" % corners
		info.text = msg
		ep._say(msg)
		return
	ep._flush_if_dirty()
	var snap: Dictionary = ep._rec().duplicate(true)
	ep._begin("Your traced shape")
	var rec: Dictionary = ep.pu._ensure()
	# the kernel takes a shape inside another one only a level at a time: the outsides are joined, the holes in them cut, an island in a hole joined again ...
	var depth := OutlineTools.depths(loops)
	var top := 0
	for d in depth:
		top = maxi(top, d)
	var fid := ""
	for lv in top + 1:
		var group: Array = []
		for i in loops.size():
			if depth[i] == lv:
				group.append(loops[i])
		if group.is_empty():
			continue
		var sk := Part.new_feature(rec, "sketch", {"plane": "top", "ents": OutlineTools.line_ents(group), "dims": []})
		rec["features"].append(sk)
		var cut := lv % 2 == 1
		var f := Part.new_feature(rec, "extrude", {"sketch": String(sk["id"]), "dist": HEIGHT_MM + (2.0 if cut else 0.0), "both": false, "op": "cut" if cut else "join"})
		rec["features"].append(f)
		fid = String(f["id"])
	var err: String = ep._last_error(rec, fid)
	if err != "":
		ep.m.S.part = snap
		ep.m._drop_undo()
		ep._edit_n = -1
		var msg2 := "Your picture did not make a solid: %s. Use a plainer picture" % err
		info.text = msg2
		ep._say(msg2)
		return
	ep._end()
	ep.armed = ""
	ep.pu.upto = -1
	ep.pu.sync()
	ep._rows_sync()
	ep._values_sync()
	var holes := 0
	for d in depth:
		holes += 1 if d % 2 == 1 else 0
	last = {"loops": loops, "corners": corners, "holes": holes}
	info.text = "Traced: %d corners, %d hole%s. Undo takes it back" % [corners, holes, "" if holes == 1 else "s"]
	ep._say("Your picture is a sketch %s mm wide, pulled up %s mm. Undo takes it back" % [str(snappedf(width_mm(), 0.1)), str(HEIGHT_MM)])


func close() -> void:
	if panel != null:
		panel.visible = false
	if go_btn != null:
		go_btn.modulate = Color.WHITE
	if node != null and is_instance_valid(node):
		node.queue_free()
	node = null
	image = null
	ep._say("Trace closed")


## the picture and its panel show only on the Easy screen
func sync(on: bool) -> void:
	if panel != null and not on:
		panel.visible = false
	if node != null and is_instance_valid(node):
		node.visible = on and image != null
	if panel != null and on and image != null and node != null:
		panel.visible = true
