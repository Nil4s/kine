## godot --path . -s tests/why_test.gd     (GATES S1; needs a window)
## WHY + SOURCE: every rule the rulebook can emit has a plain WHY sentence and a source link; every web link is one of
## docs/MOTION_RULES.md's (one truth) and every local one exists; in the CHECK panel each finding shows its why line
## and a source button that opens that rule's link.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	# the rule names the rulebook can emit, read from its source (every _f(...) call)
	var src := FileAccess.get_file_as_string("res://scripts/rulebook.gd")
	var rules := {}
	var caps := RegEx.create_from_string("\"([A-Z][A-Z ]+[A-Z])\"")
	for line in src.split("\n"):
		if line.contains("_f(") or line.contains("\"rule\":"):
			for mt in caps.search_all(line):
				if not mt.get_string(1) in ["WARN", "FAIL"]:
					rules[mt.get_string(1)] = true
	for k in Rulebook.SRC:
		rules[k] = true
	var miss := rules.keys().filter(func(r): return not (Rulebook.WHY.has(r) and Rulebook.URL.has(r) and Rulebook.WHY[r].length() > 30))
	ok(rules.size() >= 8 and miss.is_empty(), "%d rules %s, each with a why sentence and a source (missing: %s)" % [rules.size(), rules.keys(), miss])
	var doc := FileAccess.get_file_as_string("res://docs/MOTION_RULES.md")
	var bad := []
	for r in Rulebook.URL:
		var u: String = Rulebook.URL[r]
		if u.begins_with("res://") and not FileAccess.file_exists(u):
			bad.append(u)
		elif u.begins_with("http") and not doc.contains(u):
			bad.append(u)
	ok(bad.is_empty(), "every web link is in docs/MOTION_RULES.md, every local doc exists (bad: %s)" % [bad])
	# the panel
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m._check()
	await process_frame
	var rows := 0
	var good := 0
	for c in m.ui_find_list.get_children():
		if c is HBoxContainer and c.get_child_count() == 2 and c.get_child(1) is Button and c.get_child(1).text == "source":
			rows += 1
			var why: String = c.get_child(0).text
			if why.begins_with("   why: ") and why.length() > 30:
				good += 1
	var nf: int = m.findings.filter(func(f): return Rulebook.WHY.has(f["rule"])).size()
	ok(nf >= 1 and rows == nf and good == nf, "combo3: %d findings, %d why lines with a source button" % [nf, good])
	var first: Dictionary = m.findings[0]
	for c in m.ui_find_list.get_children():
		if c is HBoxContainer and c.get_child_count() == 2 and c.get_child(1) is Button and c.get_child(1).text == "source":
			c.get_child(1).pressed.emit()
			break
	ok(m.last_source == Rulebook.URL[first["rule"]], "the first source button opens %s's source (%s)" % [first["rule"], m.last_source])
	print("WHY TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
