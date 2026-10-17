## godot --headless --path . -s tests/launcher_test.gd     (GATES PP1)
## THE LAUNCHER ON ANY MACHINE: pose.bat (and pose.sh, through Git's bash when it is here) copied into a scratch
## folder (so nothing of this PC sits beside it), run with POSER_DRY=1 and a PATH of the system folder only:
## POSER_GODOT set -> that exe; a godot\ folder beside it -> the exe in it; on PATH -> that one; godot.path beside it ->
## that one; none -> the words "was not found" and where to get it, exit 1; the arguments arrive. The ORDER holds
## (POSER_GODOT wins over the folder). Anti-vacuity: the round-34 pose.bat (from git) given no Godot: no message.
extends SceneTree

var fails := 0
var dir := ""


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func touch(p: String) -> void:
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string("not really godot")
	f.close()


func run_bat(bat: String, args := "") -> Array:
	var out := []
	var code := OS.execute("cmd.exe", ["/c", "\"%s\" %s" % [bat.replace("/", "\\"), args]], out, true)
	return [code, "\n".join(out)]


func win(p: String) -> String:
	return p.replace("/", "\\")


func clear() -> void:
	for sub in ["godot", "bin"]:
		var d: String = dir + "/" + sub
		if DirAccess.dir_exists_absolute(d):
			for f in DirAccess.get_files_at(d):
				DirAccess.remove_absolute(d + "/" + f)
			DirAccess.remove_absolute(d)
	DirAccess.remove_absolute(dir + "/godot.path")
	OS.set_environment("POSER_GODOT", "")


func _init() -> void:
	dir = OS.get_environment("TEMP").replace("\\", "/") + "/zz_launch_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://pose.bat"), dir + "/pose.bat")
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://pose.sh"), dir + "/pose.sh")
	var path0 := OS.get_environment("PATH")
	var sysdir := OS.get_environment("SystemRoot") + "\\System32"
	OS.set_environment("PATH", sysdir)
	OS.set_environment("POSER_DRY", "1")
	var bat := dir + "/pose.bat"
	var here := win(dir)

	# none
	var r: Array = run_bat(bat)
	ok(r[0] == 1 and "was not found" in r[1] and "godotengine.org" in r[1], "nothing anywhere: says it was not found and where to get it, exit %d" % r[0])
	# POSER_GODOT
	var fake := dir + "/elsewhere/Godot_v4.7.2-stable_win64.exe"
	touch(fake)
	OS.set_environment("POSER_GODOT", win(fake))
	r = run_bat(bat, "--foo bar")
	ok(r[0] == 0 and ("LAUNCH \"%s\"" % win(fake)) in r[1] and r[1].strip_edges().ends_with("--foo bar") and ("--path \"%s\\.\"" % here) in r[1],
		"POSER_GODOT: that exe, --path beside it, the arguments arrive: %s" % r[1].strip_edges())
	# the folder beside it (and POSER_GODOT still wins over it)
	touch(dir + "/godot/Godot_v4.7.3-stable_win64.exe")
	r = run_bat(bat)
	ok(("LAUNCH \"%s\"" % win(fake)) in r[1], "POSER_GODOT comes before the godot folder")
	OS.set_environment("POSER_GODOT", "")
	r = run_bat(bat)
	ok(r[0] == 0 and ("LAUNCH \"%s\\godot\\Godot_v4.7.3-stable_win64.exe\"" % here) in r[1], "a godot folder beside it: %s" % r[1].strip_edges())
	clear()
	# on PATH
	touch(dir + "/bin/Godot_v4.7.2-stable_win64.exe")
	OS.set_environment("PATH", sysdir + ";" + win(dir + "/bin"))
	r = run_bat(bat)
	ok(r[0] == 0 and ("%s\\bin\\Godot_v4.7.2-stable_win64.exe" % here) in r[1], "on PATH: %s" % r[1].strip_edges())
	clear()
	OS.set_environment("PATH", sysdir)
	# godot.path
	var gp := FileAccess.open(dir + "/godot.path", FileAccess.WRITE)
	gp.store_string(win(fake) + "\r\n")
	gp.close()
	r = run_bat(bat)
	ok(r[0] == 0 and ("LAUNCH \"%s\"" % win(fake)) in r[1], "godot.path beside it: %s" % r[1].strip_edges())
	DirAccess.remove_absolute(dir + "/godot.path")
	# the repo's launcher names no path of this PC
	var txt := FileAccess.get_file_as_string("res://pose.bat") + FileAccess.get_file_as_string("res://pose.sh")
	ok(not ("Users\\Nick" in txt) and not ("Users/Nick" in txt), "pose.bat and pose.sh name no folder of this PC")

	# pose.sh through Git's bash (not a bare `bash`: on Windows that can be WSL)
	var gb := "C:/Program Files/Git/bin/bash.exe"
	if FileAccess.file_exists(gb):
		var o := []
		var code := OS.execute(gb, ["-c", "cd '%s' && PATH=/usr/bin POSER_DRY=1 POSER_GODOT= sh ./pose.sh" % dir], o, true)
		ok(code == 1 and "was not found" in "\n".join(o), "pose.sh, nothing anywhere: not found, exit %d" % code)
		touch(dir + "/godot/Godot_v4.7.2-stable_linux.x86_64")
		o = []
		code = OS.execute(gb, ["-c", "cd '%s' && PATH=/usr/bin POSER_DRY=1 POSER_GODOT= sh ./pose.sh --foo bar" % dir], o, true)
		var line := "\n".join(o).strip_edges()
		ok(code == 0 and "godot/Godot_v4.7.2-stable_linux.x86_64" in line and line.ends_with("--foo bar"), "pose.sh, a godot folder: %s" % line)
		clear()
	else:
		print("     (no Git bash here: pose.sh not run)")

	# anti-vacuity: the round-34 launcher, nothing anywhere
	var o2 := []
	OS.set_environment("PATH", path0)   # git lives on the real PATH
	OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "show", "38ce920:pose.bat"], o2, true)
	var old := FileAccess.open(dir + "/old_pose.bat", FileAccess.WRITE)
	old.store_string("\n".join(o2).replace("start \"\" ", "echo START "))   # never start anything
	old.close()
	OS.set_environment("PATH", sysdir)
	r = run_bat(dir + "/old_pose.bat")
	ok("Godot_v4.7.2-stable_win64.exe" in "
".join(o2), "  the round-34 pose.bat read from git (%d chars)" % "
".join(o2).length())
	ok(not ("was not found" in r[1]), "ANTI-VACUITY the round-34 pose.bat, nothing anywhere: no such message (it names Nick's path)")

	OS.set_environment("PATH", path0)
	OS.set_environment("POSER_DRY", "")
	clear()
	for f in ["pose.bat", "pose.sh", "old_pose.bat"]:
		DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(dir + "/elsewhere/Godot_v4.7.2-stable_win64.exe")
	DirAccess.remove_absolute(dir + "/elsewhere")
	DirAccess.remove_absolute(dir)
	print("LAUNCHER TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
