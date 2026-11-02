class_name FilmUI
extends RefCounted
## ITEM 269 FILM MODE panel (the "Film" button on the Part panel): the part in the dark studio with its film keys (scripts/build/film.gd), a timeline
## slider with a tick at every key, Play / Stop, quick keys on the picked body (Hue cycle, Spin rpm, Move) and Export (PNG sequence, FilmStage.export).
## Edits push one undo step (Main._push_undo) and change m.S.part["film"].

var pu: PartUI
var m: Node
var panel: PanelContainer
var stage: FilmStage
var tex: TextureRect
var body_pick: OptionButton
var slider: HSlider
var ticks: Control
var time_l: Label
var rpm_e: LineEdit
var status: Label
var play_btn: Button
var playing := false
var tmr: Timer
var names: Array = []


static func make_button(pu_: PartUI) -> Button:
	var b := Button.new()
	b.name = "part_film_btn"
	b.text = "Film"
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "Film mode: play the part's look keys, spins and moves in the dark studio, and export the frames"
	var ui := FilmUI.new()
	ui.pu = pu_
	ui.m = pu_.m
	b.pressed.connect(ui.toggle)
	b.set_meta("film_ui", ui)
	return b


func rec() -> Dictionary:
	return m.S.part


func toggle() -> void:
	if panel != null and is_instance_valid(panel) and panel.visible:
		close()
	else:
		open()


func open() -> void:
	if m.S.part.is_empty() or not Part.available():
		return
	close()
	panel = PanelContainer.new()
	panel.name = "film_panel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.04, 0.97)
	panel.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	tex = TextureRect.new()
	tex.name = "film_view"
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tex.custom_minimum_size = Vector2(320, 180)
	vb.add_child(tex)
	ticks = Control.new()
	ticks.custom_minimum_size.y = 10
	ticks.draw.connect(_draw_ticks)
	vb.add_child(ticks)
	slider = HSlider.new()
	slider.name = "film_slider"
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.001
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(_scrub)
	vb.add_child(slider)
	var r1 := HBoxContainer.new()
	vb.add_child(r1)
	play_btn = _btn(r1, "film_play", "Play", _play_toggle)
	time_l = Label.new()
	time_l.name = "film_time"
	r1.add_child(time_l)
	var r2 := HBoxContainer.new()
	vb.add_child(r2)
	body_pick = OptionButton.new()
	body_pick.name = "film_body"
	r2.add_child(body_pick)
	_btn(r2, "film_hue", "Hue cycle", _hue)
	rpm_e = LineEdit.new()
	rpm_e.name = "film_rpm"
	rpm_e.text = "1500"
	rpm_e.custom_minimum_size.x = 70
	r2.add_child(rpm_e)
	_btn(r2, "film_spin", "Spin rpm", _spin)
	_btn(r2, "film_move", "Move +X", _move)
	_btn(r2, "film_clear", "Clear keys", _clear)
	_btn(r2, "film_export", "Export", _export)
	_btn(r2, "film_close", "Close", close)
	status = Label.new()
	status.name = "film_status"
	vb.add_child(status)
	m.ui_root.add_child(panel)
	tmr = Timer.new()
	tmr.wait_time = 1.0 / 25.0
	tmr.timeout.connect(_tick)
	panel.add_child(tmr)
	tmr.start()
	_fill_bodies()
	_make_stage()


func _btn(p: Control, nm: String, txt: String, cb: Callable) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	p.add_child(b)
	return b


func _fill_bodies() -> void:
	var res := Part.replay(rec(), -1, {"errors_only": true})
	body_pick.clear()
	for i in int(res.get("bodies", 0)):
		body_pick.add_item(Part.body_name(res, i))


func _make_stage() -> void:
	var t0 := 0.0
	if stage != null:
		t0 = stage.t
		stage.close()
	stage = FilmStage.new(m.ui_root, rec(), Vector2i(960, 540))
	if stage.ok:
		stage.vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		tex.texture = stage.vp.get_texture()
		stage.set_time(t0)
	slider.max_value = Film.duration(rec())
	ticks.queue_redraw()
	_show_time()


func _draw_ticks() -> void:
	var d := maxf(Film.duration(rec()), 0.001)
	for t in Film.key_times(rec()):
		var x := float(t) / d * ticks.size.x
		ticks.draw_line(Vector2(x, 0), Vector2(x, ticks.size.y), Color(1.0, 0.8, 0.3), 2.0)


func _show_time() -> void:
	time_l.text = "  t = %.3f s of %.2f s" % [stage.t if stage != null else 0.0, Film.duration(rec())]
	slider.set_value_no_signal(stage.t if stage != null else 0.0)


func _scrub(v: float) -> void:
	if stage != null and stage.ok:
		stage.set_time(v)
	_show_time()


func _play_toggle() -> void:
	playing = not playing
	play_btn.text = "Stop" if playing else "Play"


func _tick() -> void:
	if playing and stage != null and stage.ok:
		stage.play_step(tmr.wait_time)
		_show_time()


func _body() -> int:
	return maxi(body_pick.selected, 0)


func _edit(fn: Callable) -> void:
	m._push_undo()
	fn.call()
	_make_stage()


func _hue() -> void:
	var b := _body()
	_edit(func(): Film.hue_cycle(rec(), b, 0.0, 4.0, 2.0, 1.0, 1.0, 4.0, 0.0, "glow"))
	status.text = "Hue cycle: 2 turns of the colour wheel over 4 s on the emission of body %d" % b


func _spin() -> void:
	var b := _body()
	var rpm := float(rpm_e.text) if rpm_e.text.is_valid_float() else 1500.0
	_edit(func(): Film.spin(rec(), b, rpm))
	status.text = "Spin: body %d turns %.0f rpm about Y for ever" % [b, rpm]


func _move() -> void:
	var b := _body()
	_edit(func(): Film.move(rec(), b, [[0.0, Vector3.ZERO], [2.0, Vector3(100, 0, 0)]]))
	status.text = "Move: body %d goes 100 mm along X in 2 s" % b


func _clear() -> void:
	var b := _body()
	_edit(func(): Film.clear_body(rec(), b))
	status.text = "Keys on body %d cleared" % b


func _export() -> void:
	var dir := ProjectSettings.globalize_path("user://film_export")
	var was := playing
	playing = false
	status.text = "Exporting..."
	var n := await FilmStage.export(m.ui_root, rec(), dir, 25)
	status.text = "Exported %d frames to %s" % [n, dir]
	playing = was


func close() -> void:
	playing = false
	if stage != null:
		stage.close()
		stage = null
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
	panel = null
