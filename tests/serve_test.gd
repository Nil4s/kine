## godot --headless --path . -s tests/serve_test.gd     (GATES T4)
## LIVE SESSION OVER STDIN: tests/py/serve_drive.py starts `poser_cli serve` as a real subprocess and drives it with 14
## JSON-RPC requests, one line each, waiting for each answer (incl. 4 bad ones: no such method, a failing step, not
## JSON, a save onto Nick's scene). The session keeps its state between requests. This suite runs it and reads its lines.
extends SceneTree


func _init() -> void:
	var out := []
	var code := OS.execute("python", ["-u", ProjectSettings.globalize_path("res://tests/py/serve_drive.py"), OS.get_executable_path(), ProjectSettings.globalize_path("res://")], out, true)
	var text := String(out[0]) if out.size() > 0 else ""
	var fails := 0
	var oks := 0
	for l in text.split("\n"):
		if l.begins_with("ok ") or l.begins_with("FAIL "):
			print(l)
			if l.begins_with("FAIL"):
				fails += 1
			else:
				oks += 1
	if oks < 14:
		print("FAIL the driver ran %d of 14 checks (exit %d): %s" % [oks + fails, code, text.right(600)])
		fails += 1
	print("SERVE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
