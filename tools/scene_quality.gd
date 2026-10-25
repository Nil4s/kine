extends SceneTree
## THE SCENE QUALITY WORKER (Easy's My scenes badges): runs SceneCat.grade (Kine's own Check on the scene file) for a list of
## scene files in ANOTHER process, so the panel never freezes while the badges fill. Started by scripts/easy_scenes.gd as
##   godot --headless --path <project> -s res://tools/scene_quality.gd -- <list.json>
## list.json = {"cache": "user://...json", "scenes": ["res://...json", ...]}. Each result is merged into the cache file as it
## is made (SceneCat.merge_cache: a temp file renamed over the cache), keyed by path with its modified time and size.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0])) if args.size() > 0 else null
	if not (v is Dictionary):
		push_error("scene_quality: no list file")
		quit(1)
		return
	SceneCat.cache_path = String(v.get("cache", "user://scene_quality.json"))
	for p in v.get("scenes", []):
		var path := String(p)
		if not FileAccess.file_exists(path):
			continue
		var st := SceneCat.stamp(path)
		var sv: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		var cat := SceneCat.category(path, sv if sv is Dictionary else {})
		var g := SceneCat.grade(path)
		SceneCat.merge_cache({path: {"v": SceneCat.CACHE_V, "mtime": st[0], "size": st[1], "cat": cat, "fails": g[0], "warns": g[1]}})
	quit(0)
