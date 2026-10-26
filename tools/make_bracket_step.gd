## godot --headless --path . -s tools/make_bracket_step.gd: writes tests/data/bracket.step (the buildchoose fixture: an L bracket with a hole) with KineCAD
extends SceneTree
const KCad := preload("res://scripts/kcad.gd")
func _init() -> void:
	var b: int = KCad.box(0.08, 0.01, 0.04)
	var c: int = KCad.translate(KCad.box(0.01, 0.05, 0.04), Vector3(0, 0.01, 0))
	var u: int = KCad.union(b, c)
	var h: int = KCad.translate(KCad.cylinder(0.006, 0.02), Vector3(0.05, -0.005, 0.02))
	var s: int = KCad.cut(u, h)
	print("vol ", KCad.volume(s), " ok ", KCad.export_step(s, ProjectSettings.globalize_path("res://tests/data/bracket.step")))
	quit()
