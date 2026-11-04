extends SceneTree
## godot --headless --path . -s tools/ch12_export.gd : writes data/challenges/ch12_bridge.json (the Kine Part of the CH12 footbridge)
func _init() -> void:
	var f := FileAccess.open("res://data/challenges/ch12_bridge.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(preload("res://scripts/build/ch12_bridge.gd").part_json(), " "))
	f.close()
	quit(0)
