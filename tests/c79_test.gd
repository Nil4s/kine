extends SceneTree
## godot --headless --path . -s tests/c79_test.gd     (C79 unit bars; the quit-time bars are tests/c79_test.sh)
## C79: the start-up slicer lookup ran `reg query <key> /s` inside OS.execute on a WorkerThreadPool task; the engine waits for every
## task when the app closes, so a quit in the first minute waited out the query (3 to 60 s). Bars (written before any number was read):
##   1 SAME LIST   the new lookup (a pipe polled by the worker) finds exactly the list the old OS.execute lookup found
##   2 STOPS       shutdown() 300 ms into a lookup on a worker: the task is done within 1500 ms, and no reg.exe it started is left
##   3 CONTROL     the same task WITHOUT shutdown() is still running 400 ms in (so bar 2 measures the stop, not a fast query)
##   4 NO CACHE    a stopped lookup stores nothing: is_ready() is false
##   5 RESTART     after shutdown(), a direct detect_system() runs in full again (a test frees one Main and builds the next)
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func _old_detect() -> Array:   # the lookup as it was before C79 (OS.execute), kept here as the reference
	var roots := []
	for ev in ["ProgramFiles", "ProgramFiles(x86)", "ProgramW6432"]:
		var v := OS.get_environment(ev).replace("\\", "/")
		if v != "" and not roots.has(v):
			roots.append(v)
	var la := OS.get_environment("LOCALAPPDATA").replace("\\", "/")
	if la != "":
		roots.append(la.path_join("Programs"))
	var dirs := []
	for k in SlicerSend.REG_KEYS:
		var o := []
		if OS.execute("reg", ["query", String(k), "/s"], o, true) == 0 and not o.is_empty():
			for d in SlicerSend.reg_dirs_of(String(o[0])):
				if not dirs.has(d):
					dirs.append(d)
	return SlicerSend.detect(roots, dirs)


func _init() -> void:
	var old := _old_detect()
	var neu := SlicerSend.detect_system()
	ok(str(old) == str(neu), "1 same list: old %s new %s" % [str(old), str(neu)])
	# 3 control first: no shutdown, the task keeps going
	var t_ctl := WorkerThreadPool.add_task(SlicerSend.detect_system, false, "c79 control")
	OS.delay_msec(400)
	var running := not WorkerThreadPool.is_task_completed(t_ctl)
	ok(running, "3 control: with no shutdown the lookup is still running at 400 ms")
	SlicerSend.shutdown()   # ends the control too (it must not hold the exit of this test)
	WorkerThreadPool.wait_for_task_completion(t_ctl)
	# 2 stop
	SlicerSend._stop = false
	var t := WorkerThreadPool.add_task(SlicerSend._detect_system, false, "c79 stop")
	OS.delay_msec(300)
	var t0 := Time.get_ticks_msec()
	SlicerSend.shutdown()
	WorkerThreadPool.wait_for_task_completion(t)
	var el := Time.get_ticks_msec() - t0
	ok(el < 1500, "2 shutdown() ended the lookup in %d ms (bar < 1500)" % el)
	SlicerSend._mtx.lock()
	var left: int = SlicerSend._live.size()
	SlicerSend._mtx.unlock()
	ok(left == 0, "2b no reg.exe left registered (%d)" % left)
	# 4 no cache
	SlicerSend._cache_known = false
	SlicerSend._stop = false
	var t4 := WorkerThreadPool.add_task(SlicerSend._job, false, "c79 job")
	OS.delay_msec(300)
	SlicerSend.shutdown()
	WorkerThreadPool.wait_for_task_completion(t4)
	ok(not SlicerSend.is_ready(), "4 a stopped lookup caches nothing")
	# 5 restart
	var again := SlicerSend.detect_system()
	ok(str(again) == str(old), "5 detect_system() after shutdown() runs in full again")
	print("c79: %d fail" % fails)
	quit(1 if fails > 0 else 0)
