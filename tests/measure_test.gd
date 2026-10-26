## godot --headless --path . -s tests/measure_test.gd     (GATES V2)
## MEASURE: tests/py/measure_check.py recomputes every measure in python from `state` points, holds the clearance to
## the landing on the solid dummy, bars the bat tip speed to a human range, and checks docs/AGENT_MATH.md is current.
extends SceneTree


func _init() -> void:
	var out := []
	var code := OS.execute("python", ["-u", ProjectSettings.globalize_path("res://tests/py/measure_check.py"), OS.get_executable_path(), ProjectSettings.globalize_path("res://")], out, true)
	var text := String(out[0]) if out.size() > 0 else ""
	var fails := 0
	var oks := 0
	for l in text.split("\n"):
		if l.begins_with("ok ") or l.begins_with("FAIL ") or l.begins_with("     "):
			print(l)
			if l.begins_with("FAIL"):
				fails += 1
			elif l.begins_with("ok"):
				oks += 1
	if oks + fails < 11:
		print("FAIL the driver ran %d of 11 checks (exit %d): %s" % [oks + fails, code, text.right(600)])
		fails += 1
	print("MEASURE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
