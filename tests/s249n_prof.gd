extends SceneTree
## s249n profile + signature of the temple build. godot --headless --path . -s tests/s249n_prof.gd -- out.json
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/s257_temple.json"))
	var rec: Dictionary = d["part"]
	Part.step_log = []
	var t0 := Time.get_ticks_msec()
	var res := Part.replay(rec.duplicate(true), -1, {"keep": true})
	var tot := (Time.get_ticks_msec() - t0) / 1000.0
	var by := {}
	for s in Part.step_log:
		var k: String = s[1]
		by[k] = float(by.get(k, 0.0)) + float(s[2]) / 1000.0
	var top: Array = Part.step_log.duplicate()
	top.sort_custom(func(a, b): return a[2] > b[2])
	print("TOTAL s ", tot)
	for k in by: print("  type ", k, " ", snapped(by[k], 0.01))
	for i in 8: print("  slow ", top[i])
	var sig := []
	var vols: Array = res["volumes"]
	for i in res["ids"].size():
		var b := PartFacts.box_of(PartFacts.tess_mm(int(res["ids"][i]), 0.002, 0.8))
		sig.append([vols[i], [b.position.x, b.position.y, b.position.z, b.end.x, b.end.y, b.end.z]])
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		var f := FileAccess.open(args[0], FileAccess.WRITE)
		f.store_string(JSON.stringify({"total": tot, "sig": sig, "by": by}))
		f.close()
	pass
	print("bodies ", sig.size())
	print("s249n_prof: 0 fail")
	quit(0)
