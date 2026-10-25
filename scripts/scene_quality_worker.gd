class_name SceneQualityWorker
extends RefCounted
## THE SCENE QUALITY WORKER's body (Easy's "My scenes" badges): grades a list of scene files with SceneCat.grade and merges
## each result into the cache file. Run in ANOTHER process, so the panel never freezes while the badges fill. Two ways in:
##   - the app itself: Kine --headless --kine-quality-worker <list.json>   (main.gd _ready: works in an export too, where
##     -s cannot run a script from the pck: the exported exe ignores -s and runs the app)
##   - the source tree: godot --headless --path <project> -s res://tools/scene_quality.gd -- <list.json>
## list.json = {"cache": "user://...json", "scenes": ["res://...json", ...]}.


static func run(list_path: String) -> int:
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(list_path)) if list_path != "" else null
	if not (v is Dictionary):
		push_error("scene_quality: no list file")
		return 1
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
	return 0
