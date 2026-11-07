extends RefCounted
## P12 (ROADMAP_400): ONE ORDERED UNDO HISTORY ACROSS PAGES. The pose list (Main.undo / redo) and each mesh page's KMeshUndo
## (the sculpt sphere's, the model cube's) stay exactly as they were: this is only the order they were made in. Every step
## any of them keeps is noted here as {"k": "pose" | "sculpt" | "model", "page": the page it was made on, "u": the KMeshUndo};
## Main._undo / _redo take the newest entry, go to its page and let its own list take the step back. A step that list no
## longer has (cleared, trimmed, the mesh replaced) is skipped, so the older ones still work.

var done: Array = []
var redone: Array = []


## a new step was made: it is the newest, and every redo (of any list) is gone
func note(kind: String, page: String, u = null) -> void:
	done.append({"k": kind, "page": page, "u": u})
	redone.clear()
	if done.size() > 400:
		done.pop_front()


## the newest pose entry goes (Main._drop_undo: a click that changed nothing)
func drop_pose() -> void:
	for i in range(done.size() - 1, -1, -1):
		if done[i]["k"] == "pose":
			done.remove_at(i)
			return


## the entry to act on, popped from the undo side (back) or the redo side; checked by `has` (Callable entry -> bool)
func take(back: bool, has: Callable) -> Dictionary:
	var src: Array = done if back else redone
	while not src.is_empty():
		var e: Dictionary = src.pop_back()
		if has.call(e, back):
			return e
	return {}


## the entry moved to the other side after its step was taken
func give(e: Dictionary, back: bool) -> void:
	(redone if back else done).append(e)
