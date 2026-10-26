## crash_report.gd - CRASH REPORT (ROADMAP P25): the last 20 palette commands, each with the page it ran on, in a text file
## the user can read and send by hand. Nothing is uploaded.
##
## While the app runs, every command is one line appended to <dir>/recent_commands.txt and flushed (a crash keeps every line
## written so far). The file is cut back to its last KEEP lines once it passes TRIM, so it never grows long. A session that
## did not quit cleanly leaves that file behind; the next start moves it aside (recent_commands.old) and offers it.
## A clean start deletes both. Every line is scrubbed: a path outside the project (a drive letter, a home folder) becomes
## "<folder>/name", so a report holds no personal folder. res:// and user:// paths stay as they are.
class_name CrashReport
extends RefCounted

const KEEP := 20
const TRIM := 200   # the recent file is cut back to KEEP lines when it grows past this
const RECENT := "recent_commands.txt"
const OLD := "recent_commands.old"


## one list line: local time, the page, the command's name
static func line(unix_t: float, page: String, cmd: String) -> String:
	var local := int(unix_t) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	return "%s  %s  %s" % [Time.get_time_string_from_unix_time(local), page, cmd]


## a path outside the project (a drive letter and everything after it, up to the line's end) becomes "<folder>/name"
static func scrub(s: String) -> String:
	var re := RegEx.new()
	re.compile("(?<![A-Za-z])[A-Za-z]:[\\\\/][^\"'<>|\\r\\n]*")   # not the "s://" inside res:// or the "r://" inside user://
	var out := s
	var found := re.search_all(s)
	for i in range(found.size() - 1, -1, -1):
		var at := found[i]
		var base := at.get_string().replace("\\", "/").get_file()
		out = out.substr(0, at.get_start()) + "<folder>/" + base + out.substr(at.get_end())
	return out


## the folder exists (main makes it at start, so a command's write does not pay for it)
static func ensure(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))


## the recent list while the app runs: one line appended and flushed per command (the journal's way)
class Recent extends RefCounted:
	var path := ""
	var _f: FileAccess = null
	var _n := 0   # the lines in the file

	func open(file_path: String) -> void:
		close()
		path = file_path
		_n = CrashReport.read(path).size()

	func add(line: String) -> void:
		if path == "":
			return
		if _f == null:
			_f = FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else FileAccess.open(path, FileAccess.WRITE)
			if _f == null:
				return
		_f.seek_end()
		_f.store_line(line)
		_f.flush()
		_n += 1
		if _n > CrashReport.TRIM:
			_cut()

	## the file is rewritten to its last KEEP lines
	func _cut() -> void:
		var keep := CrashReport.read(path).slice(-CrashReport.KEEP)
		close()
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			return
		for l in keep:
			f.store_line(l)
		f.close()
		_n = keep.size()

	func close() -> void:
		_f = null   # the file closes when its handle is freed


## the recent list of the session that did not quit cleanly: moved to OLD, its last KEEP lines returned (empty when there is none)
static func move_old(dir: String) -> Array:
	var src := dir.path_join(RECENT)
	if not FileAccess.file_exists(src):
		return []
	var lines := read(src).slice(-KEEP)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(OLD)))
	DirAccess.rename_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(dir.path_join(OLD)))
	return lines


## a clean start: the lists of earlier sessions are no longer needed
static func clear_recent(dir: String) -> void:
	for f in [RECENT, OLD]:
		if FileAccess.file_exists(dir.path_join(f)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(f)))


static func read(file_path: String) -> Array:
	var out := []
	if not FileAccess.file_exists(file_path):
		return out
	for l in FileAccess.get_file_as_string(file_path).split("\n", false):
		out.append(l)
	return out


## writes the report: a header (the page, the note) and the last KEEP lines, every line scrubbed.
## Returns the file's path, "" when it cannot be written
static func write(dir: String, lines: Array, page: String, note: String) -> String:
	ensure(dir)
	var path := dir.path_join("report_%d_%05d.txt" % [int(Time.get_unix_time_from_system()), randi() % 100000])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_line(scrub("Kine crash report. Page when asked: %s. %s" % [page, note]))
	for i in range(maxi(0, lines.size() - KEEP), lines.size()):
		f.store_line(scrub(str(lines[i])))
	f.close()
	return ProjectSettings.globalize_path(path)
