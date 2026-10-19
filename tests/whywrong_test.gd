## godot --path . -s tests/whywrong_test.gd     (ROADMAP 43; windowed: the app itself)
## WHAT WENT WRONG?: the last refusal, explained in plain words, with the one next step.
##   1 with no refusal yet the panel says "Nothing went wrong yet"; the button is in the top bar with an icon
##   2 five different refusals, each run as the palette runs a command (running, then run): the panel names the
##     right command ("You tried:"), the part picked, and a non-empty "Why:" for each
##   3 the next-step button of the Undo refusal runs "Pick a part" (the picked part changes to the upper arm)
##   4 the table has at least 15 entries, each with a why and a step; a refusal text with no entry still explains
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## every Label under the panel's box, as text
func texts(box: Node) -> Array:
	var out := []
	for c in box.find_children("*", "Label", true, false):
		out.append((c as Label).text)
	return out


func buttons(box: Node) -> Array:
	return box.find_children("*", "Button", true, false)


func open_panel(m: Node) -> void:
	m.ui_why.visible = false
	m._why_toggle()


## a command run the way the palette runs it: announced, then run
func run_cmd(m: Node, name: String) -> void:
	for c in m.ui_cmd.commands:
		if c["name"] == name:
			m.ui_cmd.running.emit(name)
			(c["run"] as Callable).call()
			return
	print("     no command named " + name)


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	# 1
	open_panel(m)
	var t0 := " | ".join(texts(m.ui_why_box))
	ok(m.ui_why.visible and t0.contains("Nothing went wrong yet"), "1 no refusal yet: the panel says \"Nothing went wrong yet\" (%s)" % t0.left(60))
	m.ui_why.visible = false
	var icon := false
	for b in m.ui_top_right:
		if b is Button and m.label_of(b) == "What went wrong?" and b.icon != null:
			icon = true
	ok(icon and m.ICON_OF.get("What went wrong?", "") == "whywrong", "1 the top bar has a What went wrong? button with its icon")
	# 2: five refusals, each a real command
	m.sel = "hand_r"
	var cases := [
		["Undo", "nothing to undo", "Undo"],
		["Check: critique the animation", "needs a scene of two cards", "Check: critique the animation"],
		["Mirror the scene (left-handed copy)", "needs a scene of two cards", "Mirror the scene (left-handed copy)"],
		["Check: weapon clashes", "needs two fighters", "Check: weapon clashes"],
		["Prop: key its place here", "pick a prop first", "Prop: key its place here"],
	]
	var named := 0
	var explained := 0
	var rows := []
	for cs in cases:
		m.ui_status.text = ""
		run_cmd(m, cs[0])
		open_panel(m)
		var tx := texts(m.ui_why_box)
		var said := ""
		var why := ""
		for s in tx:
			if s.begins_with("You tried:"):
				said = s
			if s.begins_with("Why:"):
				why = s
		if said.contains(cs[2]):
			named += 1
		if why.length() > 12:
			explained += 1
		rows.append("%s -> %s / %s" % [cs[0], said.trim_prefix("You tried:  ").left(70), why.left(50)])
		m.ui_why.visible = false
	for r in rows:
		print("     " + r)
	ok(named == 5, "2 five refusals: the panel names the command that refused, each time (%d of 5)" % named)
	ok(explained == 5, "2 five refusals: each has a non-empty plain-words Why (%d of 5)" % explained)
	# 3: the next step of the Undo refusal runs Pick a part
	m.sel = "hand_r"
	run_cmd(m, "Undo")
	open_panel(m)
	var nxt: Button = null
	for b in buttons(m.ui_why_box):
		if (b as Button).text.begins_with("Next:"):
			nxt = b
	var before: String = m.sel
	if nxt != null:
		nxt.pressed.emit()
	ok(nxt != null and before == "hand_r" and m.sel == "upperarm_r" and not m.ui_why.visible,
		"3 the next step button (%s) ran Pick a part: sel %s -> %s, panel closed" % [nxt.text if nxt != null else "none", before, m.sel])
	# 4: the table
	var entries: Array = WhyWrong.TABLE
	var bad := []
	for e in entries:
		if String(e["why"]).length() < 12 or String(e["step"]).length() < 4:
			bad.append(e["pat"])
	ok(entries.size() >= 15 and bad.is_empty(), "4 the table has %d entries, each with a why and a step (bad: %s)" % [entries.size(), bad])
	var odd := WhyWrong.explain("zzz unknown refusal of the thing NOT here")
	ok(WhyWrong.is_problem("NOT PLACED: x") and not WhyWrong.is_problem("posed: body") and String(odd["why"]) != "",
		"4 a NOT message is a problem, a pose report is not, and an unlisted refusal still gets a why")
	m.queue_free()
	print("WHYWRONG TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
