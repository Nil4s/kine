## undo_tree.gd - UNDO AS A TREE (ROADMAP item 15): a new edit after undoing starts a BRANCH and keeps the old one.
##
## A node is a STATE of the work. The root is the state before the first step of the session (or of the 60 kept).
## A node's "name" / "hint" is the step that made it (the say text, or the command that was pressed), its "time" is
## when it was made, its "state" is main's snapshot of the work at that node (kept when the node is left).
## The live state is node `cur`. "parent" and "kids" are the tree; "last" is the child that Ctrl+Y goes to (the child
## the work came back from, so redo walks the branch the user was on).
##
## main's undo / redo lists stay the mover of Ctrl+Z / Ctrl+Y (the current branch, exactly as before): this class is
## the bookkeeping that keeps the abandoned branches, names them, and lets the History panel jump anywhere in the tree.
## Pruning: at most `cap` nodes. The oldest node that is not on the current branch (the path from the root to `cur`,
## and the redo chain from `cur`) goes first, with the branch below it.
class_name UndoTree
extends RefCounted

const CAP := 500   # nodes kept at most (ROADMAP 15: N = 500)

var cap := CAP
var nodes := {}      # id -> {"parent", "kids", "last", "state", "time", optional "name", "hint"}
var root := 0        # the id of the oldest node kept
var cur := 0         # the live node
var _next := 1


func _init() -> void:
	reset()


## one root, nothing else: the history is forgotten (main resets it when its lists are rebuilt)
func reset() -> void:
	nodes = {}
	root = 0
	cur = 0
	_next = 1
	nodes[0] = {"parent": -1, "kids": [], "last": -1, "state": null, "time": ""}
	_next = 1


func has(id: int) -> bool:
	return nodes.has(id)


func node(id: int) -> Dictionary:
	return nodes[id]


## a child of `parent`, made by a step (its label copied from `label_src`: "name" / "hint" keys). The parent's "last"
## becomes this child, so redo from the parent goes here. The live node does not change
func add(parent: int, state: Variant, label_src: Dictionary) -> int:
	var id := _next
	_next += 1
	var n := {"parent": parent, "kids": [], "last": -1, "state": state, "time": Time.get_time_string_from_system()}
	for k in ["name", "hint"]:
		if label_src.has(k):
			n[k] = label_src[k]
	nodes[id] = n
	(nodes[parent]["kids"] as Array).append(id)
	nodes[parent]["last"] = id
	return id


## a new step is made from the live state: that state is kept on the node it leaves, the step's node is the new live one
func push(state: Dictionary) -> int:
	nodes[cur]["state"] = state
	cur = add(cur, null, state)
	prune()
	return cur


## Ctrl+Z: the live state (`state`, a snapshot) is kept on its node, and the work goes back to the parent
func step_back(state: Dictionary) -> int:
	leave(state)
	var p: int = nodes[cur]["parent"]
	if p == -1:
		return cur
	nodes[p]["last"] = cur
	cur = p
	return cur


## Ctrl+Y: the live state is kept, and the work goes to the child redo follows
func step_forward(state: Dictionary) -> int:
	leave(state)
	var c: int = nodes[cur]["last"]
	if c != -1:
		cur = c
	return cur


## the live state is kept on its node (a jump or a step leaves it)
func leave(state: Dictionary) -> void:
	nodes[cur]["state"] = state


## THE JUMP: the live state is kept, and the work is at `id` (any node). The branch the jump lands on becomes the one
## Ctrl+Y follows, all the way down to the node
func jump(id: int, state: Dictionary) -> void:
	leave(state)
	var c := id
	while nodes[c]["parent"] != -1:
		nodes[nodes[c]["parent"]]["last"] = c
		c = nodes[c]["parent"]
	cur = id


## a step that moved nothing (a drag that was cancelled, a click that became a selection): taken out of the tree
func drop_cur() -> void:
	var id := cur
	var p: int = nodes[id]["parent"]
	if p == -1:
		return
	_erase_subtree(id)
	(nodes[p]["kids"] as Array).erase(id)
	nodes[p]["last"] = -1   # the branch redo followed was cut at the push (the redo list is empty after it)
	cur = p


## the steps from state n0 to the live state become ONE step (main's ai_box merges one call's steps): the live node
## hangs off the node at depth n0 and takes the name of the first merged step
func squash(n0: int) -> void:
	var p := path()
	var depth := p.size() - 1
	if n0 < 0 or n0 + 1 >= depth:
		return
	var first: int = p[n0 + 1]
	var keep: int = p[n0]
	var c := cur
	var fl: Dictionary = nodes[first]
	for j in range(n0 + 1, depth):
		var m: int = p[j]
		for k in (nodes[m]["kids"] as Array).duplicate():
			if k != p[j + 1]:
				_erase_subtree(k)
		nodes.erase(m)
	(nodes[keep]["kids"] as Array).erase(first)
	(nodes[keep]["kids"] as Array).append(c)
	nodes[keep]["last"] = c
	nodes[c]["parent"] = keep
	nodes[c].erase("name")
	nodes[c].erase("hint")
	for k in ["name", "hint"]:
		if fl.has(k):
			nodes[c][k] = fl[k]


## the oldest state left the undo list (it keeps 60): the next state on the current branch is the root, and the
## branches that hung off the old root go with it
func trim_root() -> void:
	var p := path()
	if p.size() < 2:
		return
	var new_root: int = p[1]
	var old: int = p[0]
	for k in (nodes[old]["kids"] as Array).duplicate():
		if k != new_root:
			_erase_subtree(k)
	nodes.erase(old)
	nodes[new_root]["parent"] = -1
	root = new_root


## a step's label, set by hand (the say text names the newest step; the ai call names its merged step)
func set_name(id: int, text: String) -> void:
	if nodes.has(id):
		nodes[id]["name"] = text


func set_hint(id: int, text: String) -> void:
	if nodes.has(id):
		nodes[id]["hint"] = text


## the ids from the root down to the live node
func path() -> Array:
	var out := []
	var id := cur
	while id != -1:
		out.push_front(id)
		id = nodes[id]["parent"]
	return out


## the ids Ctrl+Y walks: the live node's "last" child, then its "last" child, ...
func forward() -> Array:
	var out := []
	var id: int = nodes[cur]["last"]
	while id != -1:
		out.append(id)
		id = nodes[id]["last"]
	return out


## the History panel's rows: every step (not the root), newest first, each with its branch column (0 = the trunk;
## a branch that is not the parent's first child starts a column to the right)
func listing() -> Array:
	var cols := {}
	var stack := [[root, 0]]
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var id: int = it[0]
		cols[id] = it[1]
		var kids: Array = nodes[id]["kids"]
		for i in kids.size():
			stack.append([kids[i], it[1] if i == 0 else it[1] + 1])
	var ids := nodes.keys()
	ids.sort()
	ids.reverse()
	var out := []
	for id in ids:
		if id != root:
			out.append({"id": id, "col": cols.get(id, 0)})
	return out


## the nodes that must survive a prune: the current branch and the redo chain
func _protected() -> Dictionary:
	var keep := {}
	for id in path():
		keep[id] = true
	for id in forward():
		keep[id] = true
	return keep


## the cap: while there are more nodes than `cap`, the oldest one off the current branch goes (with its own branch)
func prune() -> void:
	while nodes.size() > cap:
		var keep := _protected()
		var old := -1
		for id in nodes:
			if not keep.has(id) and (old == -1 or id < old):
				old = id
		if old == -1:
			return
		var p: int = nodes[old]["parent"]
		_erase_subtree(old)
		if p != -1 and nodes.has(p):
			(nodes[p]["kids"] as Array).erase(old)
			if nodes[p]["last"] == old:
				var ks: Array = nodes[p]["kids"]
				nodes[p]["last"] = ks[-1] if not ks.is_empty() else -1


func _erase_subtree(id: int) -> void:
	if not nodes.has(id):
		return
	for k in (nodes[id]["kids"] as Array).duplicate():
		_erase_subtree(k)
	nodes.erase(id)
