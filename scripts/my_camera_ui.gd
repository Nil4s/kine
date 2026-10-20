## MY CAMERA panel (ROADMAP I32; the maths: scripts/my_camera.gd). "My camera" shows the fingerprint of Nick's own shot cameras
## (median, middle half, count per habit); "Frame it my way" writes ONE shot from it (one undo step) and says which habits it used.
## Reads scenes/*.json, writes nothing but its cache in user://.
class_name MyCamUI
extends RefCounted

var m: Node
var fp: Dictionary = {}
var panel: PanelContainer
var last_plan: Dictionary = {}


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("My camera", "", show, "my camera fingerprint habits lens height distance angle line of action thirds cut contact median shots",
		false, "your habits read from the shot cameras in your own scenes: lens, camera height, distance, angle to the line of action, where the subject sits in the frame, and how far before a contact you cut")
	add.call("Frame it my way", "", frame_it, "frame it my way my camera shot habits cut on contact 180 deg rule lens distance angle thirds",
		true, "a shot for the open scene placed with your habits (your lens, distance, angle, thirds), cut before the contact the way you cut; stays on one side of the line; Ctrl+Z takes it back")


func _row(g: GridContainer, a: String, b: String, c: String, d: String, col := "text") -> void:
	for s in [a, b, c, d]:
		var l: Label = m._label(s, 12, col)
		g.add_child(l)


func show() -> void:
	fp = MyCam.compute()
	_build()
	if int(fp["shots"]) == 0:
		m._say("My camera: no shots in your scenes yet (%d scenes read). Key some shots (Shots: add a shot), or run Auto camera to start from film grammar" % int(fp["read"]))
	else:
		m._say("My camera: %d camera keys in %d shots of %d scenes%s. 'Frame it my way' puts a shot in the open scene with these habits" % [int(fp["keys"]), int(fp["shots"]), int(fp["scenes"]), " (cached)" if bool(fp.get("cached", false)) else ""])


func hide() -> void:
	if panel != null and is_instance_valid(panel):
		panel.visible = false


func _build() -> void:
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
	panel = PanelContainer.new()
	panel.name = "mycam_panel"
	var st := StyleBoxFlat.new()
	st.bg_color = Tok.c("float")
	st.set_corner_radius_all(8)
	st.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", st)
	m.ui_root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title: Label = m._label("MY CAMERA  -  %d keys, %d shots, %d scenes" % [int(fp["keys"]), int(fp["shots"]), int(fp["scenes"])], 14, "warn")
	title.name = "mycam_title"
	head.add_child(title)
	var go: Button = m._button("Frame it my way", frame_it, "a shot for the open scene placed with these habits; one undo step")
	go.name = "mycam_go"
	var bar := HBoxContainer.new()
	box.add_child(bar)
	bar.add_child(go)
	bar.add_child(m._button("Close", hide, "close the panel; the scene is untouched"))
	if int(fp["shots"]) == 0:
		box.add_child(m._label("No shots in your scenes yet. 'Frame it my way' will fall back to Auto camera.", 13, "text"))
	else:
		var g := GridContainer.new()
		g.name = "mycam_grid"
		g.columns = 4
		g.add_theme_constant_override("h_separation", 14)
		g.add_theme_constant_override("v_separation", 1)
		box.add_child(g)
		_row(g, "habit", "median", "middle half", "n", "heading")
		var S: Dictionary = fp["stats"]
		_row(g, "lens", "%.0f mm" % S["f"]["med"], "%.0f - %.0f mm" % [S["f"]["q1"], S["f"]["q3"]], str(int(S["f"]["n"])))
		_row(g, "camera height", "%.2f × eye height" % S["h"]["med"], "%.2f - %.2f × eye height" % [S["h"]["q1"], S["h"]["q3"]], str(int(S["h"]["n"])))
		_row(g, "distance", "%.1f × body height" % S["dist"]["med"], "%.1f - %.1f × body height" % [S["dist"]["q1"], S["dist"]["q3"]], str(int(S["dist"]["n"])))
		_row(g, "angle to the line", "%.0f deg" % S["theta"]["med"], "%.0f - %.0f deg" % [S["theta"]["q1"], S["theta"]["q3"]], str(int(S["theta"]["n"])))
		_row(g, "subject across", "%+.2f frame" % S["sx"]["med"], "%+.2f to %+.2f frame" % [S["sx"]["q1"], S["sx"]["q3"]], str(int(S["sx"]["n"])))
		_row(g, "subject up/down", "%+.2f frame" % S["sy"]["med"], "%+.2f to %+.2f frame" % [S["sy"]["q1"], S["sy"]["q3"]], str(int(S["sy"]["n"])))
		var cm := float(S["cut"]["med"])
		_row(g, "cut", "%d f %s" % [absi(roundi(cm)), "before hit" if cm >= 0.0 else "after hit"], "%d to %d f" % [roundi(S["cut"]["q1"]), roundi(S["cut"]["q3"])], str(int(S["cut"]["n"])))
	panel.visible = true
	_place.call_deferred()


func _place() -> void:
	if panel == null or not is_instance_valid(panel):
		return
	var fr: Rect2 = m._shot_free()
	var sz := panel.get_combined_minimum_size()
	panel.size = sz
	panel.position = Vector2(fr.position.x + fr.size.x - sz.x - 8.0, fr.position.y + fr.size.y - sz.y - 8.0)   # bottom right: the fighters stand left of it


## Frame it my way: one shot, one undo step. No shots in his scenes: Auto camera instead (and it says so)
func frame_it() -> void:
	var S: Scene = m._hero_scene()
	fp = MyCam.compute()
	if int(fp["shots"]) == 0 or int(fp["stats"]["f"]["n"]) == 0:
		m._say("My camera: no shots in your scenes to learn from (%d scenes read), so here is Auto camera instead: keep a shot from it, and your habits start from there" % int(fp["read"]))
		if m.ac_ui != null:
			m.ac_ui.show()
		return
	var keep: Dictionary = m.B.state()
	last_plan = MyCam.plan(S, fp, m.playhead)
	m.B.set_state(keep)
	if last_plan.has("why"):
		m._say(String(last_plan["why"]))
		return
	var pl := last_plan
	m._step_hint = "Frame it my way"
	m._do(func(): MyCam.write(m._shot_shots(), pl))
	m._say(String(pl["text"]) + " - Ctrl+Z takes it back")
