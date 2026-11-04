## SEND TO SLICER (Friday plan 119): find the slicers installed on this computer (Cura, PrusaSlicer, Bambu Studio, OrcaSlicer), write the part's 3MF to
## user://exports and start the chosen slicer on that file. The Export dialog's "3D printing" target shows it (scripts/export_dialog.gd).
## detect(roots, reg_dirs) is a pure function of the folders it is given (tests/s119_test.gd feeds it a fake Program Files); detect_system() gathers the real
## folders (ProgramFiles, ProgramFiles(x86), LOCALAPPDATA\Programs, and the install folders in the registry's uninstall keys).
## The launch is an argv array: OS.create_process(exe, [file]). No shell, no string built from anything the user typed.
class_name SlicerSend
extends RefCounted

## name (as shown), the folder-name hints (lower case), the program files to look for (any one)
const SLICERS := [
	{"name": "UltiMaker Cura", "hint": ["cura"], "exes": ["UltiMaker-Cura.exe", "Ultimaker-Cura.exe", "UltiMaker Cura.exe", "Cura.exe"]},
	{"name": "PrusaSlicer", "hint": ["prusa"], "exes": ["prusa-slicer.exe"]},
	{"name": "Bambu Studio", "hint": ["bambu"], "exes": ["bambu-studio.exe"]},
	{"name": "OrcaSlicer", "hint": ["orca"], "exes": ["orca-slicer.exe"]},
]

const REG_KEYS := ["HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall", "HKLM\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall",
	"HKCU\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall"]

const EXPORT_DIR := "user://exports"


## the names of the slicers this looks for, in the order it lists them
static func names() -> Array:
	var out := []
	for s in SLICERS:
		out.append(String((s as Dictionary)["name"]))
	return out


## the sentence the dialog shows when nothing is found
static func none_text() -> String:
	return "No slicer found on this computer. Install one of these (all free): %s. Then open Export again and the Send to slicer button will use it." % ", ".join(names())


## the sentence the dialog shows for what was found
static func found_text(found: Array) -> String:
	if found.is_empty():
		return none_text()
	var parts := PackedStringArray()
	for f in found:
		parts.append("%s (%s)" % [String((f as Dictionary)["name"]), String((f as Dictionary)["path"])])
	return "Slicers found: " + "; ".join(parts)


## the slicer program in one folder, or "" (checked by file name; Windows file names ignore case)
static func _exe_in(dir: String, slicer: Dictionary) -> String:
	for e in slicer["exes"]:
		var p := dir.path_join(String(e))
		if FileAccess.file_exists(p):
			return p
	return ""


## [{"name", "path"}] for the slicers found. PURE: it reads only the folders it is given.
##   roots: folders like C:/Program Files; each is searched one level down for a folder whose name hints a slicer (Prusa3D, UltiMaker Cura 5.7.1, Bambu Studio...),
##          and in that folder and the folders one level below it for the slicer's program
##   dirs: install folders known from elsewhere (the registry): the slicer's program is looked for in each, and one level below
## One entry per slicer, in the order of SLICERS; the first found wins.
static func detect(roots: Array, dirs := []) -> Array:
	var cand := []   # folders to look in
	for r in roots:
		var rd := String(r)
		if rd == "" or not DirAccess.dir_exists_absolute(rd):
			continue
		for sub in DirAccess.get_directories_at(rd):
			var low := String(sub).to_lower()
			for s in SLICERS:
				for h in (s as Dictionary)["hint"]:
					if low.contains(String(h)):
						cand.append(rd.path_join(sub))
	for d in dirs:
		if String(d) != "":
			cand.append(String(d))
	var out := []
	for s in SLICERS:
		var hit := ""
		for c in cand:
			hit = _exe_in(String(c), s)
			if hit == "" and DirAccess.dir_exists_absolute(String(c)):
				for sub in DirAccess.get_directories_at(String(c)):
					hit = _exe_in(String(c).path_join(sub), s)
					if hit != "":
						break
			if hit != "":
				break
		if hit != "":
			out.append({"name": String((s as Dictionary)["name"]), "path": hit})
	return out


## the install folders in `reg query ... /s` text: InstallLocation of every entry whose DisplayName hints a slicer. PURE (text in, folders out).
static func reg_dirs_of(text: String) -> Array:
	var out := []
	var disp := ""
	var loc := ""
	for line in text.split("\n"):
		var l := line.strip_edges()
		if l.begins_with("HKEY"):
			_flush(out, disp, loc)
			disp = ""
			loc = ""
		elif l.begins_with("DisplayName") and l.contains("REG_SZ"):
			disp = l.get_slice("REG_SZ", 1).strip_edges()
		elif l.begins_with("InstallLocation") and l.contains("REG_SZ"):
			loc = l.get_slice("REG_SZ", 1).strip_edges().replace("\\", "/").trim_suffix("/")
	_flush(out, disp, loc)
	return out


static func _flush(out: Array, disp: String, loc: String) -> void:
	if loc == "" or disp == "":
		return
	var low := disp.to_lower()
	for s in SLICERS:
		for h in (s as Dictionary)["hint"]:
			if low.contains(String(h)) and not out.has(loc):
				out.append(loc)


## the real computer's folders: Program Files (both), Local Programs, and the registry's install folders (Windows only)
static func detect_system() -> Array:
	_stop = false   # a direct call after an earlier shutdown() (a test frees one Main and builds the next) looks again in full
	return _detect_system()


static func _detect_system() -> Array:
	var roots := []
	for ev in ["ProgramFiles", "ProgramFiles(x86)", "ProgramW6432"]:
		var v := OS.get_environment(ev).replace("\\", "/")
		if v != "" and not roots.has(v):
			roots.append(v)
	var la := OS.get_environment("LOCALAPPDATA").replace("\\", "/")
	if la != "":
		roots.append(la.path_join("Programs"))
	var dirs := []
	if OS.get_name() == "Windows":
		for k in REG_KEYS:
			var txt := _reg_query(String(k))
			if txt != "":
				for d in reg_dirs_of(txt):
					if not dirs.has(d):
						dirs.append(d)
	return detect(roots, dirs)


## detect_system(), looked up ONCE per app run (it is ~2 s of folder scans and `reg query` processes). The Export dialog used to re-run it on every
## open. prewarm() starts the lookup on a worker thread at start-up; detect_cached() waits for it if it is still running. forget() = "Look again".
static var _cache: Array = []
static var _cache_known := false
static var _task := -1
static var _mtx := Mutex.new()


## C79: `reg query <key> /s` takes 3 to 60 s on a loaded machine and ran inside OS.execute on this worker thread, which the engine waits for
## when the app closes: a quit in the first minute hung for as long as the query had left (found by C78: ~90 s after a clean quit()).
## The query now runs through a pipe that this thread polls; shutdown() (main._exit_tree) stops the poll and kills the reg.exe it started.
static var _stop := false
static var _live: Array = []


static func _reg_query(key: String) -> String:
	if _stop:
		return ""
	var p := OS.execute_with_pipe("reg", ["query", key, "/s"])
	if p.is_empty():
		return ""
	var pid := int(p["pid"])
	var io: FileAccess = p["stdio"]
	_mtx.lock()
	_live.append(pid)
	_mtx.unlock()
	var buf := PackedByteArray()
	while not _stop:
		var chunk := io.get_buffer(65536)
		if chunk.is_empty():
			if not OS.is_process_running(pid):
				break
			OS.delay_msec(5)
			continue
		buf.append_array(chunk)
	_mtx.lock()
	_live.erase(pid)
	_mtx.unlock()
	if _stop:
		return ""
	return buf.get_string_from_utf8()


## the app is closing: the lookup in flight ends now, nothing half-read is cached
static func shutdown() -> void:
	_stop = true
	_mtx.lock()
	var pids := _live.duplicate()
	_mtx.unlock()
	for pid in pids:
		OS.kill(int(pid))


static func _job() -> void:
	var r := _detect_system()
	if _stop:
		return
	_mtx.lock()
	_cache = r
	_cache_known = true
	_mtx.unlock()


static func prewarm() -> void:
	if _cache_known or _task >= 0:
		return
	_stop = false
	_task = WorkerThreadPool.add_task(_job, false, "slicer lookup")


static func is_ready() -> bool:
	return _cache_known


## the slicers (the same list detect_system() gives), from the lookup of this app run; a copy, so a caller cannot change the cache
static func detect_cached() -> Array:
	if not _cache_known:
		if _task >= 0:
			WorkerThreadPool.wait_for_task_completion(_task)
			_task = -1
		if not _cache_known:
			_stop = false
			_job()
	return _cache.duplicate(true)


## "Look again for slicers": the next detect_cached() looks at the computer again
static func forget() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	_cache_known = false
	_cache = []


## the argv to start a slicer on a file: [file]. The program is the first argument of OS.create_process, never part of a string.
static func argv(file_path: String) -> Array:
	return [file_path]


## the real launcher: OS.create_process; the pid, or -1
static func launch(exe: String, args: Array) -> int:
	return OS.create_process(exe, PackedStringArray(args))


## write the 3MF and start the slicer on it. Answers {"ok", "path": the 3MF, "exe", "argv", "pid", "text"}.
## launcher(exe: String, args: Array) -> int (a pid, or <= 0 for failed); tests pass a stub, so no real slicer is started.
static func send(rec: Dictionary, slicer: Dictionary, launcher: Callable, dir := EXPORT_DIR) -> Dictionary:
	if slicer.is_empty():
		return {"ok": false, "path": "", "exe": "", "argv": [], "pid": -1, "text": none_text()}
	var r := MeshExport.export_part(rec, "3mf", dir)
	if not bool(r["ok"]):
		return {"ok": false, "path": String(r["path"]), "exe": "", "argv": [], "pid": -1, "text": String(r["text"])}
	var exe := String(slicer["path"])
	var a := argv(String(r["path"]))
	var pid := int(launcher.call(exe, a))
	if pid <= 0:
		return {"ok": false, "path": String(r["path"]), "exe": exe, "argv": a, "pid": pid,
			"text": "NOT DONE: %s could not be started. The 3MF is saved as %s: open it in the slicer yourself." % [String(slicer["name"]), String(r["path"])]}
	return {"ok": true, "path": String(r["path"]), "exe": exe, "argv": a, "pid": pid,
		"text": "sent to %s: %s (%s)" % [String(slicer["name"]), String(r["path"]).get_file(), String(r["text"])]}
