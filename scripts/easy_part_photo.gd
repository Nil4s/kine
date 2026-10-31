class_name EasyPartPhoto
extends RefCounted
## P201 PHYSICAL TO DIGITAL (Friday plan 201, Kine's own idea): measure a real object with a phone photo and a coin for scale.
## The photo shows the object with a coin (or a credit card) lying beside it. Six clicks on the picture: the coin's two edges, the
## object's width edges, its height edges. The coin's known size in mm is the scale (its pixels -> mm), so the object's width and
## height in mm flow into the part: a plate of that size, pulled up THICK_MM (the How far slider changes it), ONE undo step.
## The Photo size chip is in Easy Part's Draw shape row (easy_part.gd, _photo_press). The panel is a centred box, shown only while measuring.

const COINS := [["euro2", "Euro 2 coin", 25.75], ["quarter", "US quarter", 24.26], ["real1", "Brazil 1 real", 27.0], ["card", "Credit card", 85.6]]
const STEPS := ["the coin: click one edge", "the coin: click its other edge", "the object's width: click its left edge", "the object's width: click its right edge", "the object's height: click its top edge", "the object's height: click its bottom edge"]
const THICK_MM := 10.0   # the plate's thickness: a photo shows the outline only, so the How far slider sets the real one
const MIN_MM := 1.0
const MAX_MM := 2000.0
const MIN_PX := 6.0      # the two clicks on one edge of the coin are at least this far apart (picture px, on the panel)
const DOT := 5.0

var ep                  # the Easy Part that owns the chip (easy_part.gd)
var panel: PanelContainer
var pic: TextureRect
var marks: Control
var prompt: Label
var result: Label
var make_btn: Button
var coin := "euro2"
var coin_btns := {}
var pts: Array = []     # the clicks, in the picture's own local px (the picture's shown rect)


func _init(easy) -> void:
	ep = easy


## the Photo size chip: a file dialog for the picture (the same dialog and the same rules as Picture)
func pick() -> void:
	if not Part.available():
		ep._say(Part.why_not())
		return
	ep._flush_if_dirty()
	var fd := FileDialog.new()
	fd.name = "easypart_photo_dialog"
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp ; Pictures"])
	fd.title = "Pick your photo: the object with a coin beside it"
	fd.file_selected.connect(func(p: String): fd.queue_free(); chosen(p))
	fd.canceled.connect(fd.queue_free)
	ep.shape_box.get_parent().add_child(fd)
	fd.popup_centered(Vector2i(640, 480))
	ep._say("Take a photo of the object with a coin beside it, then pick it here")


## the picture is open: the panel shows it at "1 of 6" with no marks yet
func chosen(path: String) -> void:
	var im := Image.load_from_file(path)
	if im == null or im.is_empty():
		ep._say("That file is not a picture we can read. Pick a PNG or JPG, then press Photo size again")
		return
	_build()
	pic.texture = ImageTexture.create_from_image(im)
	pts.clear()
	panel.visible = true
	_sync()
	ep._say("Photo open: click the coin first, then the object")


## the panel, made once (a centred box on the Easy Part screen; shown only while measuring)
func _build() -> void:
	if panel != null:
		return
	panel = PanelContainer.new()
	panel.name = "easypart_photo"
	panel.add_theme_stylebox_override("panel", ep._style(Color(0.1, 0.11, 0.14, 0.97), 10, 10))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.z_index = 40
	panel.visible = false
	ep.shape_box.get_parent().add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	var top := Label.new()
	top.text = "Photo size: a coin for scale, then the object"
	top.add_theme_font_size_override("font_size", 18)
	top.add_theme_color_override("font_color", Tok.c("heading"))
	vb.add_child(top)
	prompt = Label.new()
	prompt.name = "easypart_photo_prompt"
	prompt.add_theme_font_size_override("font_size", 16)
	prompt.add_theme_color_override("font_color", Tok.c("say"))
	vb.add_child(prompt)
	var coins := HBoxContainer.new()
	coins.add_theme_constant_override("separation", 6)
	vb.add_child(coins)
	for c in COINS:
		var b := Button.new()
		b.name = "easypart_photo_coin_" + String(c[0])
		b.text = "%s (%s mm)" % [String(c[1]), str(snappedf(float(c[2]), 0.01))]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.icon = Icons.sized("part_measure", 18)
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(_coin_press.bind(String(c[0])))
		coins.add_child(b)
		coin_btns[String(c[0])] = b
	pic = TextureRect.new()
	pic.name = "easypart_photo_pic"
	pic.custom_minimum_size = Vector2(560, 360)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_STOP
	pic.gui_input.connect(_pic_gui)
	vb.add_child(pic)
	marks = Control.new()   # the six marks, drawn over the picture (clicks pass through it)
	marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marks.draw.connect(_draw_marks)
	pic.add_child(marks)
	result = Label.new()
	result.name = "easypart_photo_result"
	result.add_theme_font_size_override("font_size", 16)
	result.add_theme_color_override("font_color", Tok.c("text"))
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(result)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	make_btn = _btn(row, "easypart_photo_make", "Make the part", "Make a plate of the measured size in the part (one undo step)", make)
	make_btn.disabled = true
	_btn(row, "easypart_photo_again", "Start again", "Clear the six clicks and measure again", start_again)
	_btn(row, "easypart_photo_close", "Close", "Close the photo: nothing is made", close)


func _btn(row: HBoxContainer, nm: String, text: String, tip: String, fn: Callable) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(120, 40)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(fn)
	row.add_child(b)
	return b


## a click on the picture: one mark, if it lands on the picture itself (the six are in order, see STEPS)
func _pic_gui(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	if pts.size() >= STEPS.size():
		return
	var p: Vector2 = (ev as InputEventMouseButton).position
	if not _shown().has_point(p):
		ep._say("Click on the picture itself")
		return
	pts.append(p)
	marks.queue_redraw()
	_sync()


## the picture's shown rect inside the picture box (KEEP_ASPECT_CENTERED: one scale, centred)
func _shown() -> Rect2:
	var tex := pic.texture
	if tex == null:
		return Rect2()
	var ts := tex.get_size()
	var s := minf(pic.size.x / ts.x, pic.size.y / ts.y)
	var d := ts * s
	return Rect2((pic.size - d) * 0.5, d)


func _draw_marks() -> void:
	for i in pts.size():
		var col: Color = Tok.c("accent") if i < 2 else Tok.c("say")
		var p: Vector2 = pts[i]
		marks.draw_circle(p, DOT, col)
		if i % 2 == 1:
			marks.draw_line(pts[i - 1], p, col, 2.0)


func _coin_mm() -> float:
	for c in COINS:
		if String(c[0]) == coin:
			return float(c[2])
	return 25.75


## the object's width and height in mm (x, y), from the six clicks and the coin's known size; (-1, -1) while the six are not in or the coin clicks are too close
func _size_mm() -> Vector2:
	if pts.size() < STEPS.size():
		return Vector2(-1.0, -1.0)
	var coin_px: float = (pts[0] as Vector2).distance_to(pts[1])
	if coin_px < MIN_PX:
		return Vector2(-1.0, -1.0)
	var k := _coin_mm() / coin_px
	return Vector2((pts[2] as Vector2).distance_to(pts[3]) * k, (pts[4] as Vector2).distance_to(pts[5]) * k)


func _coin_press(k: String) -> void:
	coin = k
	_sync()
	ep._say("Coin set: the sizes follow it")


## the prompt, the picture's marks, the result in mm and Make the part (on only with six clicks and a usable size)
func _sync() -> void:
	if panel == null:
		return
	for c in COINS:
		(coin_btns[String(c[0])] as Button).set_pressed_no_signal(String(c[0]) == coin)
	marks.queue_redraw()
	var n := pts.size()
	if n < STEPS.size():
		prompt.text = "%d of 6: %s" % [n + 1, STEPS[n]]
		result.text = ""
		make_btn.disabled = true
		return
	var wh := _size_mm()
	if wh.x < 0.0:
		prompt.text = "The two coin clicks are too close together"
		result.text = "Press Start again and click the two edges of the coin, far apart"
		make_btn.disabled = true
		return
	prompt.text = "All six are in. Press Make the part"
	if wh.x < MIN_MM or wh.y < MIN_MM or wh.x > MAX_MM or wh.y > MAX_MM:
		result.text = "That comes to %s x %s mm, out of range (1 mm to 2 m): press Start again" % [str(snappedf(wh.x, 0.1)), str(snappedf(wh.y, 0.1))]
		make_btn.disabled = true
		return
	result.text = "The object: %s mm wide x %s mm tall (the coin is %s mm)" % [str(snappedf(wh.x, 0.1)), str(snappedf(wh.y, 0.1)), str(snappedf(_coin_mm(), 0.01))]
	make_btn.disabled = false


func start_again() -> void:
	pts.clear()
	_sync()
	ep._say("Start again: click the coin first")


func close() -> void:
	if panel != null:
		panel.visible = false
	ep._say("Photo size closed: nothing was made")


## Make the part: a plate of the measured width x height, THICK_MM up, joined to the part. One undo step; a plate that will not build is taken back
func make() -> void:
	var wh := _size_mm()
	if wh.x < MIN_MM or wh.y < MIN_MM or wh.x > MAX_MM or wh.y > MAX_MM:
		ep._say("Press Start again and measure once more: the sizes are out of range")
		return
	ep._flush_if_dirty()
	var snap: Dictionary = ep._rec().duplicate(true)
	ep._begin("Photo part")
	var rec: Dictionary = ep.pu._ensure()
	var w := snappedf(wh.x, 0.1)
	var h := snappedf(wh.y, 0.1)
	var sk := Part.new_feature(rec, "sketch", {"plane": "top", "ents": [{"k": "rect", "a": [0.0, 0.0], "b": [w, h]}], "dims": []})
	rec["features"].append(sk)
	var f := Part.new_feature(rec, "extrude", {"sketch": String(sk["id"]), "dist": THICK_MM, "both": false, "op": "join"})
	rec["features"].append(f)
	var err: String = ep._last_error(rec, String(f["id"]))
	if err != "":
		ep.m.S.part = snap
		ep.m._drop_undo()
		ep._edit_n = -1
		ep._say("Your photo did not make a plate: %s. Press Start again and measure once more" % err)
		return
	ep._end()
	ep.armed = ""
	ep.pu.upto = -1
	ep.pu.sync()
	ep._rows_sync()
	ep._values_sync()
	panel.visible = false
	ep._say("Your object is a plate %s x %s mm, %s mm thick. How far changes the thickness; Undo takes it back" % [str(w), str(h), str(THICK_MM)])
