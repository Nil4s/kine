extends SceneTree
## THE SCENE QUALITY WORKER, source-tree entry point (see scripts/scene_quality_worker.gd for the body and for the
## exported-build switch --kine-quality-worker, which runs the same code):
##   godot --headless --path <project> -s res://tools/scene_quality.gd -- <list.json>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	quit(SceneQualityWorker.run(args[0] if args.size() > 0 else ""))
