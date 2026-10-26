extends SceneTree
## playback cost per frame (60 fps needs < 16 ms): godot --headless --path . -s tests/bench_play.gd
func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	S.apply(B, 0.0)
	var n := 120
	var t0 := Time.get_ticks_usec()
	for k in n:
		S.apply(B, S.length() * k / n)
	var per := (Time.get_ticks_usec() - t0) / 1000.0 / n
	print("apply: %.2f ms per frame" % per)
	t0 = Time.get_ticks_usec()
	for k in 30:
		B.contacts()
	print("contacts: %.2f ms" % ((Time.get_ticks_usec() - t0) / 1000.0 / 30))
	TestFiles.cleanup()
	quit()
