## SCENE LINES panel (Friday plan 135 + 136; the words: scripts/scene_script.gd). A line box on the CHECK row's "Scene lines":
## "A punches, then B falls", "while A waves, B jumps", "after 2 seconds, B sits", "close up on A", "wide shot", "follow B", "orbit slowly".
## Do it = ONE undo step. Words it does not know: a plain sentence and nothing changes (no undo step).
class_name SceneScriptUI
extends RefCounted

var m: Node
var panel: PanelContainer
var line: LineEdit


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Scene lines", "", show, "scene line two characters timing then while after seconds camera close up wide shot follow orbit A punches B falls",
		false, "type one line for the scene: 'A punches, then B falls', 'while A waves, B jumps', 'after 2 seconds, B sits', 'close up on A', 'wide shot', 'follow B', 'orbit slowly'")


func show() -> void:
	_build()
	panel.visible = true
	_place.call_deferred()
	m._say_plain("Scene lines: type a line, e.g. 'A punches, then B falls' or 'close up on A', then Do it")


func hide() -> void:
	if panel != null and is_instance_valid(panel):
		panel.visible = false


func _build() -> void:
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
	panel = PanelContainer.new()
	panel.name = "scl_panel"
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
	var title: Label = m._label("SCENE LINES: A and B are the characters", 14, "warn")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", hide, "close the box; the scene is untouched"))
	line = LineEdit.new()
	line.name = "scl_line"
	line.custom_minimum_size = Vector2(440, 28)
	line.placeholder_text = "A punches, then B falls   /   close up on A   /   wide shot"
	line.text_submitted.connect(func(_t): run(line.text))
	box.add_child(line)
	var go: Button = m._button("Do it", func(): run(line.text), "build the cards (then = after the move before ends, while = together, after 2 seconds) or set the camera (close up on A, wide shot, follow B, orbit slowly); one undo step")
	go.name = "scl_go"
	box.add_child(go)


func _place() -> void:
	if panel == null or not is_instance_valid(panel):
		return
	var fr: Rect2 = m._shot_free()
	var sz := panel.get_combined_minimum_size()
	panel.size = sz
	panel.position = Vector2(fr.position.x + (fr.size.x - sz.x) * 0.5, fr.position.y + fr.size.y - sz.y - 4.0)


## one line -> the scene (cards or the camera). Returns "" when it changed the scene, else the plain sentence (nothing changed)
func run(text: String) -> String:
	m._actors_sync()
	var n: int = maxi(m.actors_rt.size(), 1)
	var p := SceneScript.parse(text, n)
	if not p["ok"]:
		m._say_plain(String(p["error"]))
		return String(p["error"])
	var H: Scene = m._hero_scene()
	var fps: int = H.fps
	if p["kind"] == "camera":
		var t0: float = 0.0 if H.shots.is_empty() else snappedf(m.playhead, 1.0 / float(fps))
		var shot := SceneScript.shot_for(p, H, t0, text)
		if shot.is_empty():
			var e := "There is no such character: the scene has %d." % n
			m._say_plain(e)
			return e
		m._step_hint = "Scene line: " + text.strip_edges()
		m._do(func(): SceneScript.write_shot(m._shot_shots(), shot, fps))
		m._refresh()
		m._say_plain("Scene line: the camera is set (%s), one undo step (Ctrl+Z)" % String(p["cam"]))
		return ""
	var scenes: Array = []
	for i in n:
		scenes.append(m.actors_rt[i]["S"] if not m.actors_rt.is_empty() else m.S)
	var pl := SceneScript.plan(p["clauses"], scenes, fps)
	if not pl["ok"]:
		m._say_plain(String(pl["error"]))
		return String(pl["error"])
	m._step_hint = "Scene line: " + text.strip_edges()
	m._do(func():
		for k in pl["cards"]:
			(scenes[k] as Scene).cards = pl["cards"][k])
	m.sel_card = mini(m.sel_card, m.S.cards.size() - 1)
	m.ov.mark_dirty()
	m.wt.mark_dirty()
	m._rebuild_cards()
	m._refresh()
	var parts := []
	for s in pl["spans"]:
		parts.append("%s from %.2f s to %.2f s" % [char(65 + int(s["actor"])), float(s["t0"]), float(s["t1"])])
	m._say_plain("Scene line: " + ", ".join(parts) + ". One undo step (Ctrl+Z)")
	return ""
