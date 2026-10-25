## godot --headless --path . -s tests/sample_dump.gd -- <out.txt> [scene.json ...]
## Every frame (1/fps) of every scene's sample(): offset + angles + weapon, as text. Two dumps from two versions of
## scene.gd diff to nothing when the in-betweens did not change (GATES A1). No scene arguments = every scene.
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := FileAccess.open(args[0], FileAccess.WRITE)
	var files := args.slice(1)
	if files.is_empty():
		for d in ["res://scenes/", "res://scenes/_wip/"]:
			for f in DirAccess.get_files_at(d):
				if f.ends_with(".json"):
					files.append(d + f)
	files.sort()
	for f in files:
		var S := Scene.new()
		S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(f)))
		var n := int(ceil(S.length() * S.fps)) + 1
		for k in n:
			var s := S.sample(float(k) / S.fps)
			var keys: Array = s["ang"].keys()
			keys.sort()
			var line := "%s %d off %s" % [f.get_file(), k, s["offset"]]
			for j in keys:
				line += " %s %s" % [j, s["ang"][j]]
			line += " w %s" % [s["weapon"]]
			out.store_line(line)
	out.close()
	print("dumped %d scenes" % files.size())
	TestFiles.cleanup()
	quit()
