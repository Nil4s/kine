extends PanelContainer
## P129 LINKAGES (Friday plan 129): a 4-bar linkage panel on Easy Part's Parts > Hinges page. A frame (the pivot at 0,0 to the far pivot),
## a crank, a coupler and a rocker. The knob on the crank's tip is the drag handle: press anywhere on the drawing or drag, and the crank turns
## to that spot (a spot the links cannot reach is refused in words, the crank stays). + and - change one length by 10 mm a press; Reset is the
## first setting. "Full turn" says whether the crank goes all the way round (Grashof: the shortest link is the crank or the frame, and
## shortest + longest <= the other two). The words go to the page's status line (say_fn). The panel changes no part, so it makes no undo step.
## Lengths and joints are in mm, y up; the drawing is in px.

const LEN_MIN := 10.0
const LEN_MAX := 300.0
const STEP_MM := 10.0
const DEFAULT := {"crank": 30.0, "coupler": 80.0, "rocker": 60.0, "frame": 100.0}
const ROWS := [["crank", "Crank"], ["coupler", "Coupler"], ["rocker", "Rocker"], ["frame", "Frame"]]
const ORIGIN := Vector2(10.0, 92.0)   # px inside the drawing: the crank's pivot
const DRAW_MM := 80.0                 # px for the longest reach of the linkage

var L := DEFAULT.duplicate()   # the four lengths, mm
var theta := deg_to_rad(45.0)  # the crank's angle, radians from the frame (counter-clockwise, y up)
var drag := false
var say_fn := Callable()       # the page's status line (set by easy_part.gd): the words of each step
var canvas: Control
var pos_t: Label
var turn_t: Label
var len_t := {}                # key -> the Label that reads its length
var reset_btn: Button


static func _joints(a: float, b: float, c: float, f: float, th: float) -> PackedVector2Array:
	var bpt := Vector2(a * cos(th), a * sin(th))
	var dpt := Vector2(f, 0.0)
	var dv := dpt - bpt
	var d := dv.length()
	if d < 0.000001 or d > b + c or d < absf(b - c):
		return PackedVector2Array()   # the coupler and the rocker cannot both reach
	var u := dv / d
	var x := (b * b - c * c + d * d) / (2.0 * d)
	var h := sqrt(maxf(0.0, b * b - x * x))
	var cpt := bpt + u * x + Vector2(-u.y, u.x) * h   # the elbow above the frame
	return PackedVector2Array([bpt, cpt, dpt])


## the crank goes all the way round: Grashof (shortest + longest <= the other two) and the shortest link is the crank or the frame
static func full_turn(a: float, b: float, c: float, f: float) -> bool:
	var v := [a, b, c, f]
	v.sort()
	if v[0] + v[3] > v[1] + v[2]:
		return false
	return a <= minf(b, minf(c, f)) or f <= minf(a, minf(b, c))


func _init() -> void:
	name = "easypart_linkage"
	add_theme_stylebox_override("panel", _panel_style())
	visible = false
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	add_child(h)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 2)
	h.add_child(left)
	canvas = Control.new()
	canvas.name = "easypart_linkage_canvas"
	canvas.custom_minimum_size = Vector2(120, 100)
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.draw.connect(_on_draw)
	canvas.gui_input.connect(_on_canvas_input)
	left.add_child(canvas)
	turn_t = _label("easypart_linkage_turn", 12)
	left.add_child(turn_t)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 3)
	h.add_child(right)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	right.add_child(top)
	top.add_child(_label("easypart_linkage_title", 12, "Linkage: drag the knob"))
	reset_btn = Button.new()
	reset_btn.name = "easypart_linkage_reset"
	reset_btn.text = "Reset"
	reset_btn.tooltip_text = "Back to the first linkage: crank 30, coupler 80, rocker 60, frame 100 mm"
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.custom_minimum_size = Vector2(0, 26)
	reset_btn.add_theme_font_size_override("font_size", 12)
	reset_btn.pressed.connect(_reset)
	top.add_child(reset_btn)
	for pair in [[ROWS[0], ROWS[1]], [ROWS[2], ROWS[3]]]:
		var pr := HBoxContainer.new()
		pr.add_theme_constant_override("separation", 4)
		right.add_child(pr)
		for row in pair:
			var k: String = row[0]
			var lab := _label("easypart_linkage_" + k, 12)
			lab.custom_minimum_size = Vector2(84, 0)
			pr.add_child(lab)
			len_t[k] = lab
			pr.add_child(_bump_btn("easypart_linkage_%s_minus" % k, "-", "Make the %s 10 mm shorter" % k, k, -STEP_MM))
			pr.add_child(_bump_btn("easypart_linkage_%s_plus" % k, "+", "Make the %s 10 mm longer" % k, k, STEP_MM))
	pos_t = _label("easypart_linkage_pos", 11)
	pos_t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pos_t.custom_minimum_size = Vector2(280, 0)
	right.add_child(pos_t)
	_refresh()


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Tok.c("float")
	s.set_corner_radius_all(10)
	s.set_content_margin_all(6)
	return s


func _label(nm: String, fs: int, t := "") -> Label:
	var l := Label.new()
	l.name = nm
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", Tok.c("text"))
	return l


func _bump_btn(nm: String, t: String, tip: String, key: String, dv: float) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = t
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(30, 26)
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(_bump.bind(key, dv))
	return b


func _say(t: String) -> void:
	if say_fn.is_valid():
		say_fn.call(t)


func _s() -> float:
	var mx := maxf(maxf(L["crank"] + L["coupler"], L["crank"] + L["rocker"]), maxf(L["frame"] + L["rocker"], L["frame"]))
	return DRAW_MM / maxf(mx, 1.0)


func _px(p: Vector2) -> Vector2:
	return ORIGIN + Vector2(p.x, -p.y) * _s()


func _pts(th: float) -> PackedVector2Array:
	return _joints(L["crank"], L["coupler"], L["rocker"], L["frame"], th)


## the crank's tip knob, in the screen's own pixels (the test and a player press the same place)
func knob_px() -> Vector2:
	return canvas.get_global_rect().position + _px(Vector2(L["crank"] * cos(theta), L["crank"] * sin(theta)))


func pivot_px() -> Vector2:
	return canvas.get_global_rect().position + ORIGIN


## the crank turns to the nearest spot it can reach when a length changes (so a longer crank does not stick)
func _settle() -> void:
	if not _pts(theta).is_empty():
		return
	for k in range(1, 181):
		for sg in [-1.0, 1.0]:
			var t: float = theta + sg * deg_to_rad(float(k))
			if not _pts(t).is_empty():
				theta = wrapf(t, -PI, PI)
				return


func _bump(key: String, dv: float) -> void:
	L[key] = clampf(float(L[key]) + dv, LEN_MIN, LEN_MAX)
	_settle()
	_refresh()


func _reset() -> void:
	L = DEFAULT.duplicate()
	theta = deg_to_rad(45.0)
	_settle()
	_refresh()


func _on_canvas_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	var mm := ev as InputEventMouseMotion
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		drag = mb.pressed
		if mb.pressed:
			_aim(mb.position)
		canvas.accept_event()
	elif mm != null and drag:
		_aim(mm.position)
		canvas.accept_event()


## the crank turns to the spot under the pointer, if the links can reach it; if not, it stays and the words say so
func _aim(p: Vector2) -> void:
	var q := (p - ORIGIN) / _s()
	q.y = -q.y
	if q.length() < 1.0:
		return
	var th := atan2(q.y, q.x)
	if _pts(th).is_empty():
		_say("The links cannot reach that spot, so the crank stays where it was. Try a spot nearer the ring")
		return
	theta = th
	_refresh()


func _refresh() -> void:
	for row in ROWS:
		var k: String = row[0]
		len_t[k].text = "%s %d mm" % [row[1], int(roundf(float(L[k])))]
	var pts := _pts(theta)
	if pts.is_empty():
		pos_t.text = "No pose: the links cannot close"
		turn_t.text = "Full turn: no"
		_say("These four lengths cannot close. Next step: press Reset, or change one length by 10 mm")
	else:
		var tip := pts[0]
		var jt := pts[1]
		var far := pts[2]
		pos_t.text = "Tip %.1f, %.1f | Joint %.1f, %.1f | Far pivot %.1f, %.1f mm" % [tip.x, tip.y, jt.x, jt.y, far.x, far.y]
		var turn := full_turn(L["crank"], L["coupler"], L["rocker"], L["frame"])
		turn_t.text = "Full turn: yes" if turn else "Full turn: no"
		if turn:
			_say("Linkage: drag the knob on the crank. The crank goes all the way round")
		else:
			_say("This linkage cannot turn all the way round. Next step: make the crank shorter or the frame longer, or press Reset")
	canvas.queue_redraw()


func _on_draw() -> void:
	canvas.draw_line(ORIGIN, _px(Vector2(L["frame"], 0.0)), Tok.of("text:0.45"), 3.0)   # the frame
	var pts := _pts(theta)
	if pts.is_empty():
		return
	var bp := _px(pts[0])
	var cp := _px(pts[1])
	var dp := _px(pts[2])
	canvas.draw_line(ORIGIN, bp, Tok.of("accent"), 4.0)   # the crank
	canvas.draw_line(bp, cp, Tok.of("focus"), 3.0)        # the coupler
	canvas.draw_line(cp, dp, Tok.of("ok"), 3.0)           # the rocker
	canvas.draw_circle(ORIGIN, 3.0, Tok.of("text"))
	canvas.draw_circle(dp, 3.0, Tok.of("text"))
	canvas.draw_circle(cp, 3.0, Tok.of("text"))
	canvas.draw_circle(bp, 7.0, Tok.of("warn"))           # the drag handle on the crank's tip
