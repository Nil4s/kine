class_name TaskCoach
extends Node
## P19 TASK COACH (ROADMAP_400): "Task coach: make a fighter" walks BODY -> MODEL -> SURFACE -> POSE. A small non-modal panel
## (it never grabs input outside itself) shows the step, what to do, and a live check read from the app's real state; Next is
## enabled only while the check is green and switches to the next step's page. Cancel closes it and touches nothing.
## Checks: BODY  S.body is not the default {} (a proportion moved or a quick body picked)
##         MODEL the mesh editor has run an edit (undo steps > 0)
##         SURFACE the editor's mesh has a material slot
##         POSE  some joint is more than POSE_DEG from rest (0,0,0)
## Starting (or restarting) lands on the first red step. Tests: tests/coach_test.gd.

const PAGES := ["BODY", "MODEL", "SURFACE", "POSE"]
const POSE_DEG := 10.0
const TEXT := [
	["Body", "Pick a quick body (5th / 50th / 95th) or drag a proportion slider."],
	["Model", "Open the test cube (ribbon: Test cube) and make one edit: Extrude (E) a face, or Subdivide."],
	["Surface", "Give the mesh a material: Materials panel, then Library, then Apply."],
	["Pose", "Drag a part of the body (more than 10 degrees from rest) to strike a pose."],
]

var m
var on := false
var step := 0
var panel: PanelContainer
var title: Label
var todo: Label
var state_lbl: Label
var btn_next: Button
var btn_cancel: Button
var check_override := {}   # step -> Callable: tests only (a planted check)


func _init(main = null) -> void:
	m = main
	name = "task_coach"


func build(root: Control) -> void:
	panel = PanelContainer.new()
	panel.name = "task_coach"
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var st := StyleBoxFlat.new()
	st.bg_color = Tok.c("float")
	st.set_corner_radius_all(8)
	st.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", st)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	title = Label.new()
	title.name = "coach_title"
	vb.add_child(title)
	todo = Label.new()
	todo.name = "coach_todo"
	todo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	todo.custom_minimum_size = Vector2(260, 0)
	vb.add_child(todo)
	state_lbl = Label.new()
	state_lbl.name = "coach_state"
	vb.add_child(state_lbl)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	btn_next = Button.new()
	btn_next.name = "coach_next"
	btn_next.text = "Next"
	btn_next.focus_mode = Control.FOCUS_NONE
	btn_next.pressed.connect(next)
	hb.add_child(btn_next)
	btn_cancel = Button.new()
	btn_cancel.name = "coach_cancel"
	btn_cancel.text = "Cancel"
	btn_cancel.focus_mode = Control.FOCUS_NONE
	btn_cancel.pressed.connect(cancel)
	hb.add_child(btn_cancel)
	root.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	panel.position = Vector2(12, 200)


func check(i: int) -> bool:
	if check_override.has(i):
		return bool(check_override[i].call())
	match i:
		0:
			return not m.S.body.is_empty()
		1:
			return m.kmed != null and m.kmed.undo.steps.size() > 0
		2:
			return m.kmed != null and m.kmed.mesh != null and m.kmed.mesh.materials.size() > 0
		_:
			for j in m.B.ang:
				var a: Vector3 = m.B.ang[j]
				if maxf(absf(a.x), maxf(absf(a.y), absf(a.z))) > POSE_DEG:
					return true
			return false


func first_red() -> int:
	for i in PAGES.size():
		if not check(i):
			return i
	return PAGES.size() - 1


func start() -> void:
	on = true
	step = first_red()
	panel.visible = true
	m._page_set(PAGES[step], false)
	refresh()


func cancel() -> void:
	on = false
	panel.visible = false


func next() -> void:
	if not on or not check(step):
		return
	if step >= PAGES.size() - 1:
		cancel()
		return
	step += 1
	m._page_set(PAGES[step], false)
	refresh()


func refresh() -> void:
	if panel == null:
		return
	var g := on and check(step)
	title.text = "Make a fighter: step %d of %d, %s" % [step + 1, PAGES.size(), TEXT[step][0]]
	todo.text = TEXT[step][1]
	state_lbl.text = "Done: ready for the next step" if g else "Waiting: not done yet"
	state_lbl.add_theme_color_override("font_color", Color(0.35, 0.85, 0.4) if g else Color(0.9, 0.55, 0.3))
	btn_next.text = "Done" if step >= PAGES.size() - 1 else "Next"
	btn_next.disabled = not g


func _process(_d: float) -> void:
	if on:
		refresh()   # per frame: Next follows the real state at once (a few dozen angle reads)
