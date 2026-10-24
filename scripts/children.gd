## THE CHILD PROGRAMS (one registry for every separate program the app starts: ffmpeg for Save video, the video tracker,
## the multicam tracker, the webcam readers, the AI video maker, the physics judge, the live puppet's tracker).
## Each one is add()ed when it starts and done() when its owner has taken its result. main's _exit_tree calls kill_all(),
## so closing the app ends whatever is still running instead of leaving it on the machine.
class_name Children
extends RefCounted

static var _pids := {}   # pid -> the FileAccess pipe it reads (closed before the kill, so ffmpeg finishes its file), or null


## a child that is running: kill_all ends it at exit. stdin: the pipe the child reads, if any
static func add(pid: int, stdin: FileAccess = null) -> void:
	if pid >= 0:
		_pids[pid] = stdin


## the child has ended or its owner has dealt with it: it is no longer tracked
static func done(pid: int) -> void:
	_pids.erase(pid)


## the pids still tracked and running (for tests)
static func running() -> Array:
	var out := []
	for pid in _pids:
		if OS.is_process_running(pid):
			out.append(pid)
	return out


## at app exit: each pipe is closed, then each child still running is killed
static func kill_all() -> void:
	for pid in _pids:
		var stdin = _pids[pid]
		if stdin is FileAccess:
			(stdin as FileAccess).close()
		if OS.is_process_running(pid):
			OS.kill(pid)
	_pids.clear()
