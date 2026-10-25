## godot --headless --path . -s tests/freename_test.gd     (Easy card clicks with 2000+ clips in scenes/_wip)
## Bars, written before measuring:
##   1 RIGHT NAME: a folder with walk.json and walk_2..walk_300: TextBlocking.unique_path and Templates.new_path return
##     walk_301 (the first free number), then, after walk_301 is written, walk_302
##   2 FAST: the second call checks at most 2 files (the old probe started at walk_2 every time: 300 checks)
##   3 EMPTY FOLDER: a name with no file yet returns name.json in one check, and keeps doing so while it stays free
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _touch(p: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("{}")
	f.close()


func _init() -> void:
	var TB = load("res://scripts/text_blocking.gd")
	var dir := "user://freename_t"
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	_touch(dir + "/walk.json")
	for k in range(2, 301):
		_touch(dir + "/walk_%d.json" % k)
	for pair in [["TextBlocking.unique_path", func(n): return TB.unique_path(dir, n)], ["Templates.new_path", func(n): return Templates.new_path(n, dir)]]:
		var who: String = pair[0]
		var f: Callable = pair[1]
		var p1: String = f.call("walk")
		ok(p1.get_file() == "walk_301.json", "1 %s: the first free name is walk_301 (%s)" % [who, p1.get_file()])
		_touch(p1)
		var n0: int = TB.probes if who.begins_with("Text") else Templates.probes
		var p2: String = f.call("walk")
		var n1: int = TB.probes if who.begins_with("Text") else Templates.probes
		ok(p2.get_file() == "walk_302.json", "1 %s: after walk_301 is written, walk_302 (%s)" % [who, p2.get_file()])
		ok(n1 - n0 <= 2, "2 %s: the second call checks %d files (<= 2)" % [who, n1 - n0])
		DirAccess.remove_absolute(p1)
		var m0: int = TB.probes if who.begins_with("Text") else Templates.probes
		var q1: String = f.call("wave")
		var q2: String = f.call("wave")
		var m1: int = TB.probes if who.begins_with("Text") else Templates.probes
		ok(q1.get_file() == "wave.json" and q2.get_file() == "wave.json" and m1 - m0 == 2, "3 %s: a free name is name.json, one check each (%s, %s, %d checks)" % [who, q1.get_file(), q2.get_file(), m1 - m0])
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	print("FREENAME TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
