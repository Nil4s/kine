## godot --headless --path . -s tools/make_turns.gd   -> templates/turn_around.json, turn_left.json, turn_right.json
## The three turns on the spot, built by scripts/turn_walk.gd (the cards and the numbers are in its header). tests/turn_test.gd
## measures the files.
extends SceneTree
const TW := preload("res://scripts/turn_walk.gd")


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://templates"))
	for spec in [["turn_around", 180.0], ["turn_left", 90.0], ["turn_right", -90.0]]:
		var r: Dictionary = TW.build(String(spec[0]), float(spec[1]))
		var f := FileAccess.open("res://templates/%s.json" % spec[0], FileAccess.WRITE)
		f.store_string(JSON.stringify(r["scene"], " "))
		f.close()
		print("%s: %d cards, %d steps, %.2f s, stance width %.1f cm" % [spec[0], (r["cards"] as Array).size(), int(r["steps"]), float(r["length_s"]), float(r["width"]) * 100.0])
	quit()
