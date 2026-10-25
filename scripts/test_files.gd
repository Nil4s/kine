## Test run leftovers (TestFiles): a test run writes files and folders under user:// named with its own process id
## (autosave_test_<pid>_<n>.json, zz_next_tool_<pid>.json, monkey_out_<pid>/ ...) and nothing removed them, so the
## user's data folder filled with thousands of them. cleanup() removes THIS run's ones; every test calls it right
## before its quit(). It removes only:
##   - top-level user:// entries whose name matches one of the anchored patterns below, with THIS process's id;
##   - and only if the entry was written at or after this process started (an older run that had the same id left
##     its files behind, and they are not this run's).
## Nothing else in user:// is touched, and a folder is removed only as a whole, from inside its own top level.
## The same pattern list is in tools/purge_test_files.py (the dry-run / delete tool for the older leftovers).
class_name TestFiles
extends RefCounted

## the name patterns; PID stands for this process's id. Anchored: a real autosave (autosave_<n>.json) never matches.
const PATTERNS := [
	["autosave_test", "^autosave_test_PID(_\\d+|_later)?\\.json$"],
	["zz_next_tool", "^zz_next_tool_PID\\.json$"],
	["zz_suggestion_journal", "^zz_suggestion_journal_PID\\.json$"],
	["zz_style_print", "^zz_style_print_PID\\.json$"],
	["zz_next_pose", "^zz_next_pose_PID\\.json$"],
	["zz_smart_drag", "^zz_smart_drag_PID\\.json$"],
	["zz_best_take", "^zz_best_take_PID\\.json$"],
	["macros_test", "^macros_test_PID\\.json$"],
	["poser_test_cfg", "^poser_test_PID\\.cfg$"],
	["zz_lib", "^zz_lib_PID$"],
	["monkey_out", "^monkey_out_PID$"],
	["walk_out", "^walk\\d+_out_PID$"],
	["i22_out", "^zz_i22_out_PID$"],
	["i_run", "^i\\d+_PID$"],
]


## a driver's output folders (pictures, logs, takes) are read AFTER the run: cleanup() keeps them; only
## tools/purge_test_files.py removes them
const KEEP_AT_QUIT := ["monkey_out", "walk_out", "i22_out", "i_run"]


## the regex of one pattern for this process id
static func regex_for(pattern: String) -> RegEx:
	var rx := RegEx.new()
	rx.compile(pattern.replace("PID", str(OS.get_process_id())))
	return rx


## newest modification time (unix seconds) of an entry; a folder counts the newest thing inside it
static func _newest(path: String) -> float:
	var t := float(FileAccess.get_modified_time(path))
	if DirAccess.dir_exists_absolute(path):
		var d := DirAccess.open(path)
		if d != null:
			d.list_dir_begin()
			var f := d.get_next()
			while f != "":
				if f != "." and f != "..":
					t = maxf(t, _newest(path.path_join(f)))
				f = d.get_next()
			d.list_dir_end()
	return t


## remove a folder and everything in it (only called for an entry this run made)
static func _rm_tree(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f != "." and f != "..":
			if d.current_is_dir():
				_rm_tree(dir.path_join(f))
			else:
				DirAccess.remove_absolute(dir.path_join(f))
		f = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(dir)


## removes this run's leftovers under user://; returns how many top-level entries it removed
static func cleanup() -> int:
	# this process started about Time.get_ticks_msec() ago (ticks count from the engine's start); 2 s of slack
	var started := Time.get_unix_time_from_system() - Time.get_ticks_msec() / 1000.0 - 2.0
	var base := ProjectSettings.globalize_path("user://")
	var d := DirAccess.open("user://")
	if d == null:
		return 0
	var names: Array = []
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f != "." and f != "..":
			names.append(f)
		f = d.get_next()
	d.list_dir_end()
	var removed := 0
	for name in names:
		var hit := false
		for p in PATTERNS:
			if KEEP_AT_QUIT.has(p[0]):
				continue
			if regex_for(p[1]).search(name) != null:
				hit = true
				break
		if not hit:
			continue
		var full := base.path_join(name)
		if _newest(full) < started:
			continue   # not written by this run
		if DirAccess.dir_exists_absolute(full):
			_rm_tree(full)
		else:
			DirAccess.remove_absolute(full)
		removed += 1
	return removed
