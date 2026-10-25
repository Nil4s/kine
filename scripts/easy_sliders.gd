class_name EasySliders
extends Node
## EASY SIDE SLIDERS (Nick: "most people don't know keyboard commands"): a click on a body part opens a panel at the RIGHT of
## the window with the part's name in plain words and 2-3 big sliders in the joint's natural range. Dragging a slider moves the
## body live; one drag is ONE undo step and keys into the picked card the way a body drag does (EasyMode.card_follows_drag).
## Reset this part puts the part back to its card's pose (the picked card, else the card at the playhead, else straight).
## The panel shows only while a part is picked (part_picked); it sits left of the view buttons, under the Easy bar.
## It does not change the body's framing (a framing change moved the drag points of easy_mode 10e).

const W := 250.0            # the panel's width (px)
const TOP := 8.0            # px under the Easy bar (main's TOP_H) for the panel's top edge
const ROWS := 3             # the most sliders a part has

var m: Node                 # main (untyped, as EasyMode does)
var part := ""              # the picked part's joint ("" = nothing picked: the panel is hidden)
var panel: PanelContainer
var _title: Label
var _rows: Array = []       # per slider: {"label", "slider", "axis", "on"}
var _reset: Button
var _shown_part := ""       # the part the rows were set up for
var _scene: Object = null    # the scene the pick was made in


## the panel's words and sliders for a joint: [title, [[label, axis], ...]], or [] for a part without sliders
## (fingers, toes, a held weapon). axis: bend / side / twist, as Body.ang and Body.lim name them.
static func spec_of(j: String) -> Array:
	var side := ""
	if j.ends_with("_l"):
		side = "Left "
	elif j.ends_with("_r"):
		side = "Right "
	var base := j.trim_suffix("_l").trim_suffix("_r")
	var neck := [["Nod", "bend"], ["Turn", "twist"], ["Tilt", "side"]]
	match base:
		"upperarm":
			return [side + "arm", [["Raise", "side"], ["Forward / back", "bend"], ["Twist", "twist"]]]
		"lowerarm":
			return [side + "elbow", [["Bend", "bend"]]]
		"hand":
			return [side + "hand", [["Bend", "bend"], ["Turn", "twist"]]]
		"clavicle":
			return [side + "shoulder", [["Raise", "side"], ["Forward / back", "bend"]]]
		"thigh":
			return [side + "leg", [["Forward / back", "bend"], ["Out to the side", "side"], ["Twist", "twist"]]]
		"calf":
			return [side + "knee", [["Bend", "bend"]]]
		"foot":
			return [side + "foot", [["Point / flex", "bend"], ["Turn", "twist"]]]
		"head":
			return ["Head", neck]
		"neck_01":
			return ["Neck", neck]
		"spine_01":
			return ["Lower back", [["Lean", "bend"], ["Turn", "twist"], ["Tilt", "side"]]]
		"spine_02":
			return ["Middle back", [["Lean", "bend"], ["Turn", "twist"], ["Tilt", "side"]]]
		"spine_03":
			return ["Upper back", [["Lean", "bend"], ["Turn", "twist"], ["Tilt", "side"]]]
		"pelvis":
			return ["Hips", [["Turn around", "twist"], ["Lean", "bend"], ["Tilt", "side"]]]
	return []


func build(root: Control) -> void:
	panel = PanelContainer.new()
	panel.name = "easy_sliders"
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.custom_minimum_size = Vector2(W, 0)
	var st := StyleBoxFlat.new()
	st.bg_color = Tok.c("panel")
	st.set_corner_radius_all(10)
	st.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", st)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	_title = Label.new()
	_title.name = "easy_slider_title"
	_title.add_theme_font_size_override("font_size", 22)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(W - 20.0, 0)
	col.add_child(_title)
	for i in ROWS:
		var lb := Label.new()
		lb.name = "easy_slider_label_%d" % i
		lb.add_theme_font_size_override("font_size", 17)
		col.add_child(lb)
		var sl := HSlider.new()
		sl.name = "easy_slider_%d" % i
		sl.step = 0.5
		sl.focus_mode = Control.FOCUS_NONE
		sl.custom_minimum_size = Vector2(W - 20.0, 30)   # a big grab area: the mouse, not the keyboard
		sl.drag_started.connect(_drag_start.bind(i))
		sl.drag_ended.connect(_drag_end.bind(i))
		sl.value_changed.connect(_moved.bind(i))
		col.add_child(sl)
		_rows.append({"label": lb, "slider": sl, "axis": "", "on": false})
	_reset = Button.new()
	_reset.name = "easy_reset_part"
	_reset.text = "Reset this part"
	_reset.focus_mode = Control.FOCUS_NONE
	_reset.tooltip_text = "put this part back to its card's pose (the picked card, else the card at the playhead, else straight)"
	_reset.add_theme_font_size_override("font_size", 18)
	_reset.custom_minimum_size = Vector2(W - 20.0, 40)
	_reset.pressed.connect(_reset_part)
	col.add_child(_reset)
	root.add_child(panel)


## a press on the body part at px p (main's press, Easy): "" = nothing there, the panel shuts
func part_picked(j: String) -> void:
	part = j if not spec_of(j).is_empty() else ""


## a press inside the panel is the panel's (main's body press ignores it)
## only its sliders and its button take a press: the panel's background passes it on to the body under it
func hit(p: Vector2) -> bool:
	if panel == null or not panel.visible:
		return false
	for sl in sliders():
		if (sl as Control).get_global_rect().has_point(p):
			return true
	return _reset.get_global_rect().has_point(p)


## the visible sliders (the test and the layout read them)
func sliders() -> Array:
	var out := []
	for r in _rows:
		if r["on"]:
			out.append(r["slider"])
	return out


func _process(_dt: float) -> void:
	if panel == null or m == null:
		return
	if m.easy == null or not m.easy.on or m.S != _scene:
		part = ""   # a pick does not outlive Easy, nor the scene it was made in (a new or opened scene starts with nothing picked)
	_scene = m.S
	var on: bool = m.easy != null and m.easy.on and part != "" and m.B != null and m.B.ang.has(part)
	panel.visible = on
	if not on:
		return
	if part != _shown_part:
		_setup()
	_place()
	_sync()


func _left_x() -> float:
	var x := get_viewport().get_visible_rect().size.x - 12.0 - W
	if m.easy.views != null and m.easy.views.is_visible_in_tree():
		x = m.easy.views.get_global_rect().position.x - 10.0 - W
	return x


## the title and the sliders of the picked part, each in the joint's range (a locked axis gets no slider)
func _setup() -> void:
	_shown_part = part
	var sp := spec_of(part)
	_title.text = String(sp[0])
	var L: Dictionary = m.B.lim[part]
	for i in ROWS:
		var r: Dictionary = _rows[i]
		var sl: HSlider = r["slider"]
		if i < (sp[1] as Array).size():
			var axis: String = sp[1][i][1]
			var rg: Vector2 = L[axis]
			r["axis"] = axis
			r["on"] = rg.y - rg.x > 0.5
			sl.min_value = rg.x
			sl.max_value = rg.y
			(r["label"] as Label).text = String(sp[1][i][0])
		else:
			r["on"] = false
		(r["label"] as Control).visible = r["on"]
		sl.visible = r["on"]
	_reset.visible = true


## the panel sits left of the view buttons (or at the right edge when they are not there), under the Easy bar
func _place() -> void:
	panel.global_position = Vector2(_left_x(), float(m.TOP_H) + TOP)


## the sliders show the body's angles (a drag of the body, an undo, a card's pose): the row being dragged keeps the pointer's value
func _sync() -> void:
	var a: Vector3 = m.B.ang[part]
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		if not r["on"]:
			continue
		var v := _axis_value(a, r["axis"])
		var sl: HSlider = r["slider"]
		if not bool(r.get("dragging", false)):
			sl.set_value_no_signal(v)
		(r["label"] as Label).text = "%s   %d°" % [String(spec_of(part)[1][i][0]), roundi(v)]


static func _axis_value(a: Vector3, axis: String) -> float:
	match axis:
		"bend":
			return a.x
		"side":
			return a.y
	return a.z


## a drag of one slider: ONE undo step for the whole drag, named for the part (Easy's drag rules: the step can take a card)
func _drag_start(i: int) -> void:
	_rows[i]["dragging"] = true
	m.playing = false
	m._push_undo()
	var u: Dictionary = m.undo[-1]
	var name := "Move " + String(spec_of(part)[0]).to_lower()
	u["name"] = name
	u["easy"] = name
	u["drag"] = true   # a + Add pose straight after this drag joins its step (easy_mode.add_pose), as a body drag does
	m._tree.set_name(m._tree.cur, name)
	m._undo_tips()


func _moved(v: float, i: int) -> void:
	if part == "" or not m.B.ang.has(part):
		return
	var a: Vector3 = m.B.ang[part]
	match String(_rows[i]["axis"]):
		"bend":
			a.x = v
		"side":
			a.y = v
		_:
			a.z = v
	m.sel = part
	if part.begins_with("upperarm"):
		m._arm_edit = part   # a raised upper arm brings its collarbone (main's shoulder follow)
	m.B.set_ang_safe(part, a)
	m._after_edit()


## the release: Easy's drag rule, so a picked card takes the pose (EasyMode.card_follows_drag); nothing picked: the body only
func _drag_end(_changed: bool, i: int) -> void:
	_rows[i]["dragging"] = false
	if m.easy != null and m.easy.on and m.sel_card >= 0 and not m.auto_key:
		m.easy.card_follows_drag()
	_sync()


## the picked part's card pose: the picked card, else the card at the playhead, else straight (zero)
func ref_angles() -> Vector3:
	var ci: int = m.sel_card if m.sel_card >= 0 else LimbIK.card_at(m.S, m.playhead)
	if ci < 0 or ci >= m.S.cards.size():
		return Vector3.ZERO
	return (Moves._flat(m.S.cards[ci]["pose"])["ang"] as Dictionary).get(part, Vector3.ZERO)


func _reset_part() -> void:
	if part == "" or not m.B.ang.has(part):
		return
	var want := ref_angles()
	var now: Vector3 = m.B.ang[part]
	if now.is_equal_approx(want):
		m._say("the %s is already at its card's pose" % String(spec_of(part)[0]).to_lower())
		return
	m.playing = false
	m._push_undo()
	var name := "Reset " + String(spec_of(part)[0]).to_lower()
	m.undo[-1]["name"] = name
	m.undo[-1]["easy"] = name
	m._tree.set_name(m._tree.cur, name)
	m._undo_tips()
	m.sel = part
	m.B.set_ang_safe(part, want)
	m._after_edit()
	m._say("%s back to its card's pose (Ctrl+Z takes it back)" % String(spec_of(part)[0]).to_lower())
