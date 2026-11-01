extends SceneTree
## godot --headless --path . -s tools/gen_start_examples.gd   writes scenes/examples/*.json from the app's own builders (scripts/start_examples.gd)
func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var n := StartExamples.write_all(B)
	var bad := 0
	for e in StartExamples.LIST:
		if e.has("house"):
			continue
		var res := Part.replay(StartExamples.part_record(e), -1, {})
		var ok: bool = int(res["bodies"]) == 1 and float(res["volume"]) > 0.0 and (res["errors"] as Dictionary).is_empty()
		print("%s %-18s bodies %d volume %.1f cm3 errors %s" % ["ok  " if ok else "BAD ", e["id"], int(res["bodies"]), float(res["volume"]) * 1.0e6, res["errors"]])
		if not ok:
			bad += 1
	print("wrote %d example files, %d bad" % [n, bad])
	quit(1 if bad > 0 else 0)
