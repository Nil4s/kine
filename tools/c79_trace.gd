extends Node
## C79: prints one line per shutdown phase (engine clock, ms) so the time between quit() and process exit can be split.
## Two of these sit under the root: one first in the child order (exits last) and one last (exits first).
## Lines: C79_PHASE <label> ms=<ticks>.  The test adds the wall-clock arrival time of each line.
var label := ""


static func mark(what: String) -> void:
	print("C79_PHASE ", what, " ms=", Time.get_ticks_msec())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		mark(label + " close_request")
	elif what == NOTIFICATION_PREDELETE:
		mark(label + " predelete")


func _exit_tree() -> void:
	mark(label + " exit_tree")
