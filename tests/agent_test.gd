## godot --headless --path . -s tests/agent_test.gd     (GATES T5)
## runs tests/agent_e2e.py: an agent builds a named 30-card bat fight from an empty scene through `poser_cli serve`
## only, CHECK -> fix -> CHECK to 0 MUST FIX, saves it and validates the file. Its transcript is printed here.
extends SceneTree


func _init() -> void:
	var out := []
	var code := OS.execute("python", ["-u", ProjectSettings.globalize_path("res://tests/agent_e2e.py"), OS.get_executable_path(), ProjectSettings.globalize_path("res://")], out, true)
	var text := String(out[0]) if out.size() > 0 else ""
	print(text)
	var last := text.strip_edges().get_slice("\n", text.strip_edges().get_slice_count("\n") - 1)
	var passed := last.begins_with("AGENT E2E PASS") and code == 0
	print(("ok   " if passed else "FAIL ") + "the agent built the fight: %s (exit %d)" % [last, code])
	print("AGENT TEST %s" % ("PASS" if passed else "FAIL 1"))
	TestFiles.cleanup()
	quit(0 if passed else 1)
