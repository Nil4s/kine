## choreo_view.gd - THE EXCHANGE VIEW (ROADMAP 13): its own Window, drawn here, the logic in choreo.gd, the edits in main.gd.
## ONE ROW PER FIGHTER on one time axis: each card is a block (move solid, hold lighter), the playhead is the red line.
## BEATS sit in the lane under the ruler (a flag and its name); the report under the rows gives each beat's reach and
## guard (Choreo.report). Drag a fighter's row left / right to shift its whole timeline by that much (one undo step, the
## shift snaps to frames). The toolbar adds a beat at the playhead (by / on / verb pickers) and deletes the selected one.
## Refreshed from the scene whenever its cards or beats change (a poll, 4 a second: cheap, no signal to forget).
class_name ChoreoView
extends Control

const LABEL_W := 150.0       # px: the fighter's name column
const TOP := 66.0            # px: the toolbar, then the ruler and the beat lane
const ROW_H := 40.0          # px per fighter row
const LANE_H := 46.0         # px: the beat lane under the ruler (two label lines: neighbours in time alternate)
const REPORT_H := 22.0       # px per beat line of the report
const VERBS := ["attacks", "parries", "counters", "moves"]
const COLORS := [Color(0.36, 0.62, 0.92), Color(0.93, 0.56, 0.30), Color(0.52, 0.82, 0.45), Color(0.80, 0.52, 0.85)]

var m: Node                  # main.gd
var win: Window
var report := []             # Choreo.report of the beats now: [check, ...]
var sel_beat := -1           # the beat picked (its flag is drawn bright; Delete removes it)
var sel_by := 0
var sel_on := 1
var sel_verb := 0
var _drag := {}              # {"k", "x0", "dt"}: a row being shifted
var _key := ""              # the scene the report was made from (a change refreshes it)
var _poll := 0.0
var _bar: HBoxContainer
var _b_by: OptionButton
var _b_on: OptionButton
var _b_verb: OptionButton


## the view in its own window, centred (the registry's Exchange view)
static func open(m_: Node) -> ChoreoView:
	var w := Window.new()
	w.title = "Exchange: fighters and beats"
	w.size = Vector2i(1120, 600)
	w.min_size = Vector2i(760, 420)
	var v := ChoreoView.new()
	v.m = m_
	v.win = w
	w.add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	w.close_requested.connect(func(): w.queue_free())
	m_.get_tree().root.add_child(w)
	w.popup_centered()
	return v


func _ready() -> void:
	_bar = HBoxContainer.new()
	_bar.position = Vector2(8, 6)
	add_child(_bar)
	var add := Button.new()
	add.text = "Add beat at playhead"
	add.pressed.connect(_add)
	_bar.add_child(add)
	_b_by = OptionButton.new()
	_b_by.item_selected.connect(func(i): sel_by = i; _names_changed())
	_bar.add_child(_b_by)
	var lab := Label.new()
	lab.text = " "
	_bar.add_child(lab)
	_b_verb = OptionButton.new()
	for v in VERBS:
		_b_verb.add_item(v)
	_b_verb.item_selected.connect(func(i): sel_verb = i)
	_bar.add_child(_b_verb)
	_b_on = OptionButton.new()
	_b_on.item_selected.connect(func(i): sel_on = i; _names_changed())
	_bar.add_child(_b_on)
	var del := Button.new()
	del.text = "Delete selected beat"
	del.pressed.connect(_delete)
	_bar.add_child(del)
	_names_changed()
	mouse_filter = Control.MOUSE_FILTER_PASS
	refresh()


func _process(delta: float) -> void:
	if m == null or not is_instance_valid(m):
		return
	_poll += delta
	if _poll < 0.25:
		return
	_poll = 0.0
	var k := _state_key()
	if k != _key:
		refresh()


## the fighters: [{"name", "S", "xf"}], hero first (the hero's xf is the identity)
func fighters() -> Array:
	var out := []
	for a in m.actors_rt:
		out.append({"name": "hero" if out.is_empty() else String(a["name"]), "S": a["S"], "xf": a["xf"]})
	return out


func beats() -> Array:
	return m._hero_scene().beats


## what the report is made from: every card of every fighter and the beats (a change of any refreshes the view)
func _state_key() -> String:
	var parts := []
	for a in m.actors_rt:
		parts.append(var_to_str((a["S"] as Scene).cards) + str((a["xf"] as Transform3D)))
	parts.append(var_to_str(beats()))
	return "|".join(parts)


## the report, the pickers and the drawing, made from the scene now
func refresh() -> void:
	if m == null or not is_instance_valid(m) or m.actors_rt.size() < 2:
		return
	_key = _state_key()
	var fs := fighters()
	report = Choreo.report(fs, beats())
	_names_changed()
	queue_redraw()


## the pickers' items: the fighters by name (when they change), the verbs
func _names_changed() -> void:
	if _b_by == null or m == null or not is_instance_valid(m) or m.actors_rt.size() < 2:
		return
	var fs := fighters()
	var n := fs.size()
	if _b_by.item_count != n:
		_b_by.clear()
		_b_on.clear()
		for f in fs:
			_b_by.add_item(f["name"])
			_b_on.add_item(f["name"])
	sel_by = mini(sel_by, n - 1)
	sel_on = mini(sel_on, n - 1)
	_b_by.select(sel_by)
	_b_on.select(sel_on)
	_b_verb.select(sel_verb)


## a beat at the playhead: by / verb / on, named "<by> <verb> <on>"; the new one is the selected
func _add() -> void:
	var fs := fighters()
	if sel_by == sel_on or sel_by >= fs.size() or sel_on >= fs.size():
		return
	var name := Choreo.auto_name(fs[sel_by]["name"], VERBS[sel_verb], fs[sel_on]["name"])
	m._choreo_beat_add(m.playhead, sel_by, sel_on, name)
	sel_beat = Choreo.near(beats(), m.playhead, 1e-4)
	refresh()


func _delete() -> void:
	if sel_beat < 0:
		return
	m._choreo_beat_del(sel_beat)
	sel_beat = -1
	refresh()


# ---------------------------------------------------------------- the axis

func _pps() -> float:
	var total := 1.0
	for a in m.actors_rt:
		total = maxf(total, (a["S"] as Scene).length() + (_drag["dt"] if (_drag.size() > 0 and m.actors_rt[_drag["k"]]["S"] == a["S"]) else 0.0))
	return maxf(20.0, (size.x - LABEL_W - 24.0) / (total + 0.5))


## x of time t (px in the view)
func x_of(t: float) -> float:
	return LABEL_W + 12.0 + t * _pps()


func row_y(k: int) -> float:
	return TOP + LANE_H + 26.0 + k * ROW_H


func _gui_input(ev: InputEvent) -> void:
	if m == null or not is_instance_valid(m) or m.actors_rt.size() < 2:
		return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_press(ev.position)
		else:
			_release()
		accept_event()
	elif ev is InputEventMouseMotion and not _drag.is_empty():
		var t0 := (_drag["x0"] as float)
		_drag["dt"] = (ev.position.x - t0) / _pps()
		queue_redraw()
		accept_event()


func _press(p: Vector2) -> void:
	if p.y >= TOP and p.y < TOP + LANE_H + 18.0:   # the ruler and the beat lane: the playhead, or a beat
		var bi := _beat_at(p)
		if bi >= 0:
			sel_beat = bi
			_goto(float(beats()[bi]["t"]))
		else:
			_goto(clampf((p.x - LABEL_W - 12.0) / _pps(), 0.0, 1e9))
		return
	for k in m.actors_rt.size():
		var y := row_y(k)
		if p.y >= y and p.y < y + ROW_H - 6.0 and p.x >= LABEL_W:
			_drag = {"k": k, "x0": p.x, "dt": 0.0}
			return


func _release() -> void:
	if _drag.is_empty():
		return
	var k: int = _drag["k"]
	var dt: float = _drag["dt"]
	_drag = {}
	if absf(dt) >= 0.001:
		if not m._choreo_shift(k, dt):
			m._say("the fighter cannot move that far: its timeline would start before 0 s")
	refresh()


func _beat_at(p: Vector2) -> int:
	var bs := beats()
	for i in bs.size():
		if absf(p.x - x_of(float(bs[i]["t"]))) <= 7.0:
			return i
	return -1


func _goto(t: float) -> void:
	m.playing = false
	m.playhead = t
	m._ps().apply(m.B, t)
	m._refresh()
	queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var font := get_theme_default_font()
	var fs := 13
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.14, 0.16))
	if m == null or not is_instance_valid(m) or m.actors_rt.size() < 2:
		draw_string(font, Vector2(16, 60), "The exchange view needs two fighters (Actor: add a second fighter).", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.85, 0.85, 0.85))
		return
	var p := _pps()
	var top := TOP
	# the ruler: a tick every second, labelled
	var total := 0.0
	for a in m.actors_rt:
		total = maxf(total, (a["S"] as Scene).length())
	for s in range(0, int(ceil(total)) + 1):
		var x := x_of(float(s))
		draw_line(Vector2(x, top + 4), Vector2(x, top + 18), Color(0.5, 0.5, 0.5), 1.0)
		draw_string(font, Vector2(x + 3, top + 14), "%d s" % s, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.6, 0.6))
	# the beat lane: a flag per beat, its name beside it
	var bs := beats()
	for i in bs.size():
		var x2 := x_of(float(bs[i]["t"]))
		var col := Color(1.0, 0.85, 0.3) if i == sel_beat else Color(0.9, 0.6, 0.2)
		draw_line(Vector2(x2, top + 18), Vector2(x2, top + LANE_H + 26.0 + m.actors_rt.size() * ROW_H), Color(col, 0.55), 1.0)
		draw_colored_polygon(PackedVector2Array([Vector2(x2, top + 18), Vector2(x2 + 9, top + 22), Vector2(x2, top + 26)]), col)
		draw_string(font, Vector2(x2 + 11, top + 26 + (i % 2) * 13.0), "%.2f  %s" % [float(bs[i]["t"]), String(bs[i]["name"])], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	draw_string(font, Vector2(12, top + 26), "beats", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.6, 0.6, 0.6))
	# one row per fighter, the cards as blocks on the shared axis
	for k in m.actors_rt.size():
		var a: Dictionary = m.actors_rt[k]
		var S: Scene = a["S"]
		var y := row_y(k)
		var shift := 0.0
		if not _drag.is_empty() and _drag["k"] == k:
			shift = _drag["dt"]
		draw_rect(Rect2(0, y, size.x, ROW_H - 6.0), Color(0.17, 0.18, 0.21))
		draw_string(font, Vector2(10, y + 22), String(fighters()[k]["name"]), HORIZONTAL_ALIGNMENT_LEFT, LABEL_W - 16.0, fs, Color(0.9, 0.9, 0.9))
		var col: Color = COLORS[k % COLORS.size()]
		var ts: Array = S.times()
		for i in S.cards.size():
			var t0: float = float(ts[i][0]) + shift
			var t1: float = float(ts[i][1]) + shift
			var t2: float = float(ts[i][2]) + shift
			var x0 := x_of(maxf(0.0, t0))
			var xm := x_of(maxf(0.0, t1))
			var x1 := x_of(maxf(0.0, t2))
			if x1 - x0 < 1.0:
				continue
			draw_rect(Rect2(x0, y + 4, maxf(1.0, xm - x0), ROW_H - 14.0), col)
			draw_rect(Rect2(xm, y + 4, maxf(0.0, x1 - xm), ROW_H - 14.0), Color(col, 0.35))
			if x1 - x0 > 34.0:
				draw_string(font, Vector2(x0 + 3, y + 20), String(S.cards[i]["name"]), HORIZONTAL_ALIGNMENT_LEFT, x1 - x0 - 4.0, 11, Color(0.08, 0.08, 0.08))
		if shift != 0.0:
			draw_string(font, Vector2(LABEL_W + 12, y + 22), "%+.2f s" % shift, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 1.0, 0.6))
	# the playhead
	var xp := x_of(m.playhead)
	draw_line(Vector2(xp, top), Vector2(xp, row_y(m.actors_rt.size()) - 6.0), Color(1.0, 0.25, 0.25), 2.0)
	# the report: each beat's reach and guard
	var ry := row_y(m.actors_rt.size()) + 14.0
	draw_string(font, Vector2(12, ry), "Reach and guard at each beat (tip or fist to the target's body; positive = out of range)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.6, 0.6))
	ry += REPORT_H
	for r in report:
		var line := "%.2f s  %s" % [float(r["t"]), String(r["text"])]
		draw_string(font, Vector2(16, ry), line, HORIZONTAL_ALIGNMENT_LEFT, size.x - 32.0, 13,
			Color(0.6, 1.0, 0.6) if bool(r["parry"]) else (Color(1.0, 0.6, 0.5) if float(r["gap"]) <= 0.0 else Color(0.85, 0.85, 0.85)))
		ry += REPORT_H
	if report.is_empty() and beats().is_empty():
		draw_string(font, Vector2(16, ry), "No beats yet: move the playhead to the moment, pick who strikes whom, press Add beat at playhead.", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.7, 0.7))
