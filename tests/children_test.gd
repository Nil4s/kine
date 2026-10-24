## godot --path . -s tests/children_test.gd     (round W4: the child programs stop at exit; part 2 renders, so it needs a window)
## THE CHILD PROGRAMS END WITH THE APP (scripts/children.gd; main's _exit_tree calls Children.kill_all()).
## Every check first proves the child IS running, so a check that could never see it cannot pass (instrument can move).
##   1 a harmless python child (time.sleep 60) started through the registry is running; freeing the app ends it within 2 s
##   2 Save video in progress (ffmpeg fed through its pipe, found the way the playblast finds it): ffmpeg is running and in the
##     registry; freeing the app ends it within 2 s, and the registry is empty. Skipped with a printed note when ffmpeg is not found
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func pose(thigh: float, arm: float) -> Dictionary:
	var R := Body.new()
	R.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	R.set_ang("thigh_l", Vector3(thigh, 0, 0))
	R.set_ang("upperarm_r", Vector3(0, 0, arm))
	R.fk()
	return R.to_dict()


## true when the process has ended within secs (polled every 20 ms; no frames run meanwhile)
func gone_within(pid: int, secs: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while OS.is_process_running(pid):
		if Time.get_ticks_msec() - t0 > secs * 1000.0:
			return false
		OS.delay_msec(20)
	return true


func _init() -> void:
	# 1 a long harmless child through the registry, then the app's exit path
	var py := OS.create_process("python", PackedStringArray(["-c", "import time; time.sleep(60)"]))
	ok(py > 0, "1 a python child starts (pid %d)" % py)
	Children.add(py)
	OS.delay_msec(500)   # python needs a moment to start
	ok(OS.is_process_running(py), "1 the child IS running before the app exits")
	ok(py in Children.running(), "1 the registry lists it")
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	root.remove_child(m)
	m.free()   # the exit path: main's _exit_tree -> Children.kill_all()
	ok(gone_within(py, 2.0), "1 freeing the app ends the child within 2 s")
	ok(Children.running().is_empty(), "1 the registry is empty after the exit")

	# 2 Save video: ffmpeg fed through its pipe
	var ff := PlayblastExport.find_ffmpeg()
	if ff == "":
		print("skip 2 Save video: ffmpeg not found (install it, or set POSER_FFMPEG to ffmpeg.exe); nothing to check")
		quit(fails)
		return
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	var S := Scene.new()
	S.name = "zz_children"
	S.fps = 24
	var poses := [pose(0, 0), pose(70, 80), pose(-25, -40)]
	for i in 3:
		S.add("c%d" % i, poses[i])
		S.cards[i]["move"] = 0.4
		S.cards[i]["hold"] = 0.1 if i < 2 else 0.0
	m.S = S
	m._rebuild_cards()
	m.sel_card = 0
	m.playhead = 0.3
	m._refresh()
	await idle(3)
	var dir := "user://zz_children_%d" % OS.get_process_id()
	m._save_video_playblast(dir)   # not awaited: the save runs frame by frame in the background
	var t := 0
	while Children.running().is_empty() and t < 600:
		await process_frame
		t += 1
	var kids := Children.running()
	ok(kids.size() == 1, "2 Save video IS running: ffmpeg is in the registry (%d running)" % kids.size())
	if kids.size() == 1:
		var fp: int = kids[0]
		root.remove_child(m)
		m.free()   # the exit path, mid-save: the pipe is closed, then ffmpeg is killed
		ok(gone_within(fp, 2.0), "2 freeing the app ends ffmpeg (pid %d) within 2 s" % fp)
	ok(Children.running().is_empty(), "2 the registry is empty after the exit")
	PlayblastExport.rm_tree(ProjectSettings.globalize_path(dir))   # the partial folder of the cut save
	quit(fails)
