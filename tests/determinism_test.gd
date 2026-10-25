## godot --headless --path . -s tests/determinism_test.gd     (GATES U3, item 98; the shots it starts open windows)
## THE SAME FRAME TWICE: tests/py/determinism.py renders 3 scripted shots twice each (byte-identical PNGs), checks that
## --frame N --fps F IS t = N / F, and asks two `serve` processes for 5 moments, one forward and one in reverse order
## (identical answers: no pose depends on the one before it). This suite runs it and reads its lines.
extends SceneTree


func _init() -> void:
	var tmp := OS.get_environment("TMP").path_join("poser_determinism")
	DirAccess.make_dir_recursive_absolute(tmp)
	var out := []
	var code := OS.execute("python", ["-u", ProjectSettings.globalize_path("res://tests/py/determinism.py"), OS.get_executable_path(), ProjectSettings.globalize_path("res://"), tmp], out, true)
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
	if oks + fails < 8:
		print("FAIL the driver ran %d of 8 checks (exit %d): %s" % [oks + fails, code, text.right(600)])
		fails += 1
	print("DETERMINISM TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
