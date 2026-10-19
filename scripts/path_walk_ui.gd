## path_walk_ui.gd - the UI of "Walk along a path..." (ROADMAP 92). ANIMATE > MAKE. Click points on the floor (each click adds
## a point; the line is the path), a small panel picks Walk or Run and the speed, Enter builds the cards and replaces the
## open scene as ONE undo step (Ctrl+Z puts the old scene back), Esc cancels. The generators are PathWalk and PathRun; their
## refusals (a bend too tight, a path too short, a speed out of range) come back in the status line with the next step.
## Speed ranges: walk 0.6-1.6 m/s (the walk poses' range, measured at 1.3), run 3.0-4.0 m/s (numbers measured at 3.5; PathRun).
class_name PathWalkUI
extends Node

const RANGE := {"walk": [0.6, 1.6, 1.3], "run": [3.0, 4.0, 3.5]}
var m: Node                      # main
var on := false
var pts: Array = []
var panel: PanelContainer
var mode_pick: OptionButton
var speed_box: SpinBox
var line: MeshInstance3D
var marks: Array = []            # [[position, heading]] of each landing of the last build, drawn as footprints


func setup(main: Node) -> void:
	m = main
	panel = PanelContainer.new()
	panel.visible = false
	panel.name = "path_walk_panel"
	var h := HBoxContainer.new()
	panel.add_child(h)
	var l := Label.new()
	l.text = "Walk along a path:"
	h.add_child(l)
	mode_pick = OptionButton.new()
	mode_pick.add_item("Walk")
	mode_pick.add_item("Run")
	mode_pick.item_selected.connect(func(_i): _mode_changed())
	h.add_child(mode_pick)
	speed_box = SpinBox.new()
	speed_box.step = 0.1
	speed_box.suffix = "m/s"
	h.add_child(speed_box)
	var hint := Label.new()
	hint.name = "hint"
	hint.text = "click the floor to add points, Enter builds it, Esc cancels"
	h.add_child(hint)
	_mode_changed()
	m.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.position.y -= 70.0
	line = MeshInstance3D.new()
	line.name = "path_walk_line"
	line.mesh = ImmediateMesh.new()
	m.add_child(line)


func mode() -> String:
	return "run" if mode_pick.selected == 1 else "walk"


func _mode_changed() -> void:
	var r: Array = RANGE[mode()]
	speed_box.min_value = r[0]
	speed_box.max_value = r[1]
	speed_box.value = r[2]
	panel.tooltip_text = "walk %.1f-%.1f m/s, run %.1f-%.1f m/s (the poses were measured near %.1f / %.1f m/s)" % [RANGE["walk"][0], RANGE["walk"][1], RANGE["run"][0], RANGE["run"][1], RANGE["walk"][2], RANGE["run"][2]]


func start() -> void:
	on = true
	pts = []
	marks = []
	panel.visible = true
	_draw()
	m._say("walk along a path: click points on the floor, Enter builds the walk (pick Walk or Run and the speed in the panel), Esc cancels")


func cancel(say := true) -> void:
	on = false
	pts = []
	marks = []
	panel.visible = false
	_draw()
	if say:
		m._say("walk along a path cancelled; nothing changed")


## returns true when the event was used
func input(ev: InputEvent) -> bool:
	if not on:
		return false
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode == KEY_ESCAPE:
			cancel()
			return true
		if ev.keycode == KEY_ENTER or ev.keycode == KEY_KP_ENTER:
			finish()
			return true
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if panel.get_global_rect().has_point(ev.position):
			return false
		var hit = RootPath.floor_hit(m.cam, ev.position)
		if hit == null:
			m._say("that click is above the horizon: click the floor, below the body's feet in the view")
			return true
		add_point(hit)
		return true
	return false


func add_point(p: Vector3) -> void:
	pts.append(Vector3(p.x, 0.0, p.z))
	_draw()
	m._say("%d point%s on the path (%.1f m so far): click more, Enter builds the %s, Esc cancels" % [pts.size(), "" if pts.size() == 1 else "s", PathWalk.curve(pts)["len"] if pts.size() > 1 else 0.0, mode()])


func finish() -> void:
	if pts.size() < 2:
		m._say("a path needs two points at least: click the floor again, then Enter")
		return
	var r: Dictionary = PathRun.build(pts, speed_box.value) if mode() == "run" else PathWalk.build(pts, speed_box.value)
	if not r["ok"]:
		m._say("%s" % r["why"])   # stays in path mode so the points can be changed
		return
	var d: Dictionary = r["scene"]
	d["scene"] = m.S.name   # the open scene keeps its name (Ctrl+Z restores the cards, not a name)
	var n: int = d["cards"].size()
	var verb := mode()
	var metres: float = float(r["covered"])
	var sp: float = speed_box.value
	on = false
	panel.visible = false
	var keep := pts
	pts = []
	m._do(func():
		m.S.from_dict(d)
		m.actors_rt = []
		m.actor_on = 0
		m._actors_sync()
		m.sel_card = 0
		m.ov.mark_dirty()
		m.wt.mark_dirty()
		m._dummy_hits()
		m._rebuild_cards()
		m.playhead = 0.0
		m.S.apply(m.B, 0.0))
	marks = []
	var c := PathWalk.curve(keep)
	var step: float = r["step"]
	var nl: int = int(r["steps"]) - (1 if verb == "walk" else 0)
	for k in range(1, nl + 1):
		var sd := "_l" if k % 2 == 1 else "_r"
		var s_k := step * 0.5 + (k - 1) * step
		marks.append([PathRun._foot(c, sd, s_k) if verb == "run" else PathWalk.foot(c, sd, s_k), PathWalk.heading(c, s_k)])
	_draw_pts(keep)
	m._say("%s along the path: %d cards, %.1f m at %.1f m/s.  Ctrl+Z puts the old scene back in one step; nothing is saved until you save" % [verb, n, metres, sp])


func _draw() -> void:
	_draw_pts(pts)


func _draw_pts(p: Array) -> void:
	var im := line.mesh as ImmediateMesh
	im.clear_surfaces()
	if p.size() < 1:
		return
	var P: Array = PathWalk.curve(p)["p"] if p.size() > 1 else [p[0], (p[0] as Vector3) + Vector3(0.001, 0, 0)]
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for q in P:
		im.surface_add_vertex((q as Vector3) + Vector3(0, 0.01, 0))
	im.surface_end()
	for q in p:   # a small cross at each clicked point
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		for dv in [Vector3(0.08, 0, 0), Vector3(0, 0, 0.08)]:
			im.surface_add_vertex((q as Vector3) + Vector3(0, 0.012, 0) - dv)
			im.surface_add_vertex((q as Vector3) + Vector3(0, 0.012, 0) + dv)
		im.surface_end()
	for mk in marks:   # a footprint: a thin rectangle on the floor, turned to the path there
		var q: Vector3 = mk[0]
		var R := Basis(Vector3.UP, float(mk[1]))
		var cs := [Vector3(-0.05, 0, -0.12), Vector3(0.05, 0, -0.12), Vector3(0.05, 0, 0.12), Vector3(-0.05, 0, 0.12), Vector3(-0.05, 0, -0.12)]
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for v in cs:
			im.surface_add_vertex(q + R * v + Vector3(0, 0.012, 0))
		im.surface_end()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Tok.c("say")
	mat.no_depth_test = true
	line.material_override = mat
