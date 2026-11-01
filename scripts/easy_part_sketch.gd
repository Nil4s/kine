class_name EasyPartSketch
extends RefCounted
## FRIDAY 166 SEARCH PARTS BY SKETCH: the "Draw to search" chip on the Parts library page opens a drawing box. A scribbled outline (a mouse
## drag; any size, any turn) is compared with the top, front and side silhouette of every library part (part_catalog.gd, cached) and the
## best six come back as chips with their score (0 = same shape). A chip drops that part on the floor (one undo step).

const BOX := 160.0
const RES_W := 250.0
const SHOWN := 6
const MIN_PTS := 8
const MIN_PX := 24.0   # a stroke smaller than this is a tap, not a drawing

var ep
var panel: PanelContainer
var canvas: Control
var words: Label
var res_box: VBoxContainer
var res_btns: Array = []
var chip: Button
var stroke := PackedVector2Array()
var drawing := false
var results: Array = []
var open := false
var warming := false


func _init(easy) -> void:
	ep = easy


## the chip on the library page (a toggle)
func make_chip() -> Button:
	chip = Button.new()
	chip.name = "easypart_lib_sketch"
	chip.text = "Draw to search"
	chip.toggle_mode = true
	chip.focus_mode = Control.FOCUS_NONE
	chip.custom_minimum_size = Vector2(0, 34)
	chip.add_theme_font_size_override("font_size", 12)
	chip.tooltip_text = "Draw a rough outline: Kine finds the library parts that look like it"
	chip.pressed.connect(toggle)
	return chip


func toggle() -> void:
	open = chip.button_pressed
	_build()
	panel.visible = open
	if open:
		warm()
	ep._say("Draw an outline in the box: Kine finds the parts that look like it" if open else "Draw to search closed")


## the silhouettes are made one part per frame while the box is open, so the first search does not stall
func warm() -> void:
	if warming or PartCatalog.ready() or not Part.available():
		return
	warming = true
	for id in PartCatalog.ids():
		PartCatalog.descriptors(String(id))
		if words != null:
			words.text = "Getting the parts ready..." if not PartCatalog.ready() else "Drag in the box to draw an outline"
		await ep.get_tree().process_frame
	warming = false


func _build() -> void:
	if panel != null:
		return
	panel = PanelContainer.new()
	panel.name = "easypart_sketch"
	panel.add_theme_stylebox_override("panel", ep._style(Color(0.1, 0.11, 0.14, 0.97), 10, 8))
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)   # fixed: the box never moves under a drag (the results below it come and go inside a reserved height)
	panel.offset_left = 10
	panel.offset_top = 292   # under the hint line and the round / pull row, left of the view buttons, above the status line
	panel.z_index = 30
	panel.visible = false
	ep.shape_box.get_parent().add_child(panel)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 8)
	panel.add_child(cols)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	cols.add_child(vb)
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 8)
	vb.add_child(trow)
	var top := Label.new()
	top.text = "Draw to search"
	top.add_theme_font_size_override("font_size", 18)
	top.add_theme_color_override("font_color", Tok.c("heading"))
	trow.add_child(top)
	canvas = Control.new()
	canvas.name = "easypart_sketch_canvas"
	canvas.custom_minimum_size = Vector2(BOX, BOX)
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.clip_contents = true
	canvas.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN   # a square box, whatever the title row's width
	canvas.gui_input.connect(_canvas_gui)
	canvas.draw.connect(_draw_canvas)
	vb.add_child(canvas)
	var clr := Button.new()
	clr.name = "easypart_sketch_clear"
	clr.text = "Clear"
	clr.focus_mode = Control.FOCUS_NONE
	clr.custom_minimum_size = Vector2(70, 30)
	clr.add_theme_font_size_override("font_size", 14)
	clr.pressed.connect(clear)
	trow.add_child(clr)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 3)
	cols.add_child(rv)
	words = Label.new()
	words.name = "easypart_sketch_words"
	words.text = "Drag in the box to draw an outline"
	words.add_theme_font_size_override("font_size", 14)
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.custom_minimum_size = Vector2(RES_W, 36)
	rv.add_child(words)
	res_box = VBoxContainer.new()
	res_box.add_theme_constant_override("separation", 3)
	res_box.custom_minimum_size = Vector2(RES_W, SHOWN * 29)
	rv.add_child(res_box)
	for i in SHOWN:
		var b := Button.new()
		b.name = "easypart_sketch_res_%d" % i
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(RES_W, 26)
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_stylebox_override("normal", ep._style(Color(0.165, 0.176, 0.212), 6, 2))
		b.add_theme_stylebox_override("hover", ep._style(Color(0.23, 0.245, 0.29), 6, 2))
		b.add_theme_stylebox_override("pressed", ep._style(Color(0.3, 0.32, 0.38), 6, 2))
		b.visible = false
		b.pressed.connect(place.bind(i))
		res_box.add_child(b)
		res_btns.append(b)


func clear() -> void:
	stroke = PackedVector2Array()
	drawing = false
	results = []
	for b in res_btns:
		(b as Button).visible = false
	if words != null:
		words.text = "Drag in the box to draw an outline"
	if canvas != null:
		canvas.queue_redraw()


func _canvas_gui(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var p := (ev as InputEventMouseButton).position
		if (ev as InputEventMouseButton).pressed:
			clear()
			drawing = true
			stroke.append(p)
		elif drawing:
			drawing = false
			stroke.append(p)
			search()
		canvas.queue_redraw()
		canvas.accept_event()
	elif ev is InputEventMouseMotion and drawing:
		var p2 := (ev as InputEventMouseMotion).position
		if stroke.is_empty() or stroke[stroke.size() - 1].distance_to(p2) >= 1.5:
			stroke.append(p2)
		canvas.queue_redraw()
		canvas.accept_event()


func _draw_canvas() -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color(0.07, 0.075, 0.1), true)
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Tok.c("accent"), false, 1.0)
	if stroke.size() >= 2:
		canvas.draw_polyline(stroke, Tok.c("text"), 2.5, true)
		if not drawing:
			canvas.draw_line(stroke[stroke.size() - 1], stroke[0], Tok.c("text"), 1.0)


## the stroke's bounding size in px
func _extent() -> float:
	if stroke.is_empty():
		return 0.0
	var lo := stroke[0]
	var hi := stroke[0]
	for p in stroke:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return maxf(hi.x - lo.x, hi.y - lo.y)


func search() -> void:
	if stroke.size() < MIN_PTS or _extent() < MIN_PX:
		words.text = "Draw a bigger outline: drag across the box"
		return
	if not Part.available():
		words.text = Part.why_not()
		return
	words.text = "Looking..."
	results = PartCatalog.search(stroke, SHOWN)
	for i in SHOWN:
		var b: Button = res_btns[i]
		if i < results.size():
			var r: Dictionary = results[i]
			b.text = "%d. %s   %.3f" % [i + 1, String(r["name"]), float(r["score"])]
			b.tooltip_text = "%s (seen from the %s). Score %.3f: 0 is the same shape. Press to put it on the floor" % [String(r["name"]), String(r["view"]), float(r["score"])]
			b.visible = true
		else:
			b.visible = false
	words.text = "Closest first. Press one to put it on the floor"


## a result chip: that part on the floor (one undo step), like a library pick
func place(i: int) -> void:
	if i >= results.size() or not Part.available():
		return
	var r: Dictionary = results[i]
	var rec := PartCatalog.make(String(r["id"]))
	if rec.is_empty():
		return
	ep.armed = ""
	ep.hole_base = {}
	ep.split_id = ""
	ep._flush_if_dirty()
	ep.m._step_hint = "Start a %s" % String(r["name"]).to_lower()
	ep.m._push_undo()
	ep.m.S.part = rec
	ep.tweak = {}
	ep.pu.upto = -1
	ep.pu.sync()
	ep.frame()
	ep._lib_fit()
	if not (ep.pu.res.get("errors", {}) as Dictionary).is_empty():
		ep._say("%s did not build. Press Reset, then try another" % String(r["name"]))
	else:
		ep._say("%s on the floor. Undo takes it back" % String(r["name"]))
	ep._screw_sync()


func sync(on: bool) -> void:
	if panel != null:
		panel.visible = on and open and ep.parts_open
		if chip != null:
			chip.set_pressed_no_signal(open)


func over(p: Vector2) -> bool:
	return panel != null and panel.visible and panel.get_global_rect().has_point(p)
