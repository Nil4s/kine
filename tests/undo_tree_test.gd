## godot --path . -s tests/undo_tree_test.gd     (ROADMAP 15: UNDO AS A TREE; needs a window: the real poser UI is built)
## A new edit after an undo starts a branch and keeps the old one. Edits A, B, C; two undos; edit D (a branch); jumping
## to C gives C back byte for byte; Ctrl+Z from C gives B; the History panel lists the tree with the branch indented and
## the live step marked. A linear history behaves as the old stack did: 20 random edit / undo / redo runs against a
## reference stack, the last of them with the cap at 12 nodes (the prune keeps the current branch). Set
## UNDO_TREE_SHOT=<png path> to save a picture of the panel with a branch.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


## everything an undo step must bring back, as history_test compares it: the body and the cards
func fp() -> String:
	return JSON.stringify(m.B.state()) + JSON.stringify(m.S.cards)


## one edit the way the app makes one: a step pushed, the body moved, the step named (the say text)
func edit(j: String, v: float, what: String) -> void:
	m._push_undo()
	m.B.ang[j] = Vector3(0.0, 0.0, v)
	m.B.fk()
	m._say(what)


## the tree node made by the step that said `what` (-1 when there is none)
func node_named(what: String) -> int:
	for id in m._tree.nodes:
		if String(m._tree.node(id).get("name", "")) == what:
			return id
	return -1


## the lists agree with the tree: Ctrl+Z / Ctrl+Y depth and the redo chain
func tree_agrees() -> bool:
	return m._tree.path().size() - 1 == m.undo.size() and m._tree.forward().size() == m.redo.size()


## the History panel's buttons, as text
func rows() -> Array:
	var out := []
	for c in m.ui_hist_list.get_children():
		if c is Button and c.text != "Close":
			out.append(c.text)
	return out


## a pure tree check (no UI): with a cap of 12, the branch that is left is pruned from its oldest end first, and the
## current branch (the path from the root) is never touched
func prune_check() -> bool:
	var t := UndoTree.new()
	t.cap = 12
	for i in 6:
		t.push({"k": i})   # root .. n6 (the state before each step is kept on its node)
	t.step_back({"k": "b"})
	t.step_back({"k": "b"})   # back to n4: n5 and n6 are a branch now
	for i in 6:
		t.push({"k": "x%d" % i})   # 13 nodes: the cap takes n5 and n6 (the oldest off the path)
	var p := t.path()
	var states_ok := true
	for i in 4:   # the trunk's states above n3 are the branch's (n4 was left by the first branch step)
		if str(t.node(p[i])["state"]["k"]) != str(i):
			states_ok = false
	print("     prune: %d nodes kept of cap %d, path of %d nodes" % [t.nodes.size(), t.cap, p.size()])
	return t.nodes.size() == 11 and p.size() == 11 and states_ok and t.forward().is_empty()


func _init() -> void:
	ok(prune_check(), "1 the cap (12 nodes): the oldest node off the current branch goes; the current branch stays whole")
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle()
	m._load_scene("res://scenes/combo3.json")   # read only
	await idle()
	m.undo.clear()
	m.redo.clear()
	m._tree_sync()

	# edits A, B, C; two undos; edit D: the branch
	edit("upperarm_l", 10.0, "Step A")
	var sA := fp()
	edit("upperarm_l", 20.0, "Step B")
	var sB := fp()
	edit("upperarm_l", 30.0, "Step C")
	var sC := fp()
	m._undo()
	m._undo()
	ok(fp() == sA and m.undo.size() == 1 and m.redo.size() == 2, "2 edits A B C, two Ctrl+Z: the state after A (undo %d, redo %d)" % [m.undo.size(), m.redo.size()])
	edit("upperarm_r", 45.0, "Step D")
	var sD := fp()
	var idA := node_named("Step A")
	var idB := node_named("Step B")
	var idC := node_named("Step C")
	var idD := node_named("Step D")
	ok(m.redo.is_empty() and m.undo.size() == 2, "3 edit D after the undo: the Ctrl+Z list is A, D (redo cleared, as before)")
	ok(idA != -1 and idB != -1 and idC != -1 and idD != -1 and m._tree.node(idA)["kids"].size() == 2 and m._tree.node(idD)["parent"] == idA,
		"4 the branch: B and C are kept under A, D is a new branch beside B (A has %d kids)" % (m._tree.node(idA)["kids"].size() if idA != -1 else -1))
	var cols := {}
	for r in m._tree.listing():
		cols[r["id"]] = r["col"]
	ok(cols.get(idD, -1) == 1 and cols.get(idB, -1) == 0, "5 the panel's columns: B on the trunk (column 0), D indented under A (column 1)")

	# jump to C: byte-identical, one action (not an undo step); Ctrl+Z from C gives B
	m._tree_go(idC)
	ok(fp() == sC and m._tree.cur == idC, "6 jump to C (from D): C back byte for byte, and the live step is C")
	ok(m.undo.size() == 3 and m.redo.is_empty() and tree_agrees(), "  the jump pushed no step: the lists are the path to C (undo %d, redo %d)" % [m.undo.size(), m.redo.size()])
	m._undo()
	ok(fp() == sB and m._tree.cur == idB, "7 Ctrl+Z from C gives B")
	m._redo()
	ok(fp() == sC and m._tree.cur == idC, "  Ctrl+Y from B gives C again (the branch C is on)")
	m._tree_go(idD)
	ok(fp() == sD, "8 jump to D: the other branch, byte for byte")
	m._tree_go(idA)
	ok(fp() == sA and tree_agrees(), "9 jump to A: the state after A, the lists agree with the tree")
	m._tree_go(idD)

	# the History panel: rows newest first, D marked and indented, C still listed
	m._toggle_history()
	await idle(3)
	var rs := rows()
	ok(rs.size() == 4 and rs[0].contains("Step D") and rs[0].contains("> "), "10 the panel: 4 steps, newest first, the live step D marked '> ' (rows: %s)" % [rs])
	ok(rs.any(func(x): return x.contains("Step C")) and rs.any(func(x): return x.contains(" ") and x.contains("Step D")),
		"  C is listed, and D is indented under its branch point")
	var shot := OS.get_environment("UNDO_TREE_SHOT")
	if shot != "":
		await idle(2)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(shot)
		print("     picture: %s" % shot)
	m._toggle_history()

	# linear histories: 20 random runs against a reference stack (the old model: a new edit clears the redo list)
	var runs_ok := 0
	for run in 20:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7000 + run
		if run == 19:
			m._tree.cap = 12   # the last run with the cap: the prune must keep the current branch
		m.undo.clear()
		m.redo.clear()
		var ref_undo := []
		var ref_redo := []
		var cur := fp()
		var good := true
		var joints := ["upperarm_l", "upperarm_r", "thigh_l"]
		for step in 40:
			var r := rng.randi_range(0, 2)
			if r == 0:
				ref_undo.append(cur)
				ref_redo.clear()
				edit(joints[rng.randi_range(0, 2)], float(rng.randi_range(1, 170)), "Random %d" % step)
				cur = fp()
			elif r == 1:
				if not ref_undo.is_empty():
					ref_redo.append(cur)
					cur = ref_undo.pop_back()
				m._undo()
			else:
				if not ref_redo.is_empty():
					ref_undo.append(cur)
					cur = ref_redo.pop_back()
				m._redo()
			if fp() != cur or m.undo.size() != ref_undo.size() or m.redo.size() != ref_redo.size() or not tree_agrees():
				good = false
				break
		if good:
			runs_ok += 1
	ok(runs_ok == 20, "11 linear history: 20 random runs of 40 edits / undos / redos match the reference stack (%d of 20)" % runs_ok)
	var kept: int = m._tree.path().size() + m._tree.forward().size()
	ok(m._tree.nodes.size() <= 12 or m._tree.nodes.size() == kept,
		"  the cap held (%d nodes; cap 12 unless the current branch and its redo are longer: %d)" % [m._tree.nodes.size(), kept])
	ok(prune_check(), "12 prune check again (pure tree)")
	print("UNDO TREE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
