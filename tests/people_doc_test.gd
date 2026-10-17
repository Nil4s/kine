## godot --headless --path . -s tests/people_doc_test.gd     (GATES WW9, #332; headless is fine)
## docs/PEOPLE.md names every rule in Rulebook.SRC (a "## RULE" heading with Source / Numbers / Used by / Tested by),
## and every web link in it is a rulebook URL, a link in docs/MOTION_RULES.md, or sits on a line marked [background].
## Fails with the missing names.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	var doc := FileAccess.get_file_as_string("res://docs/PEOPLE.md")
	var rules := FileAccess.get_file_as_string("res://docs/MOTION_RULES.md")
	ok(doc.length() > 1000, "docs/PEOPLE.md is there (%d chars)" % doc.length())
	var heads := []
	for line in doc.split("\n"):
		if line.begins_with("## "):
			heads.append(line.substr(3).strip_edges())
	var missing := Rulebook.SRC.keys().filter(func(r): return not r in heads)
	ok(missing.is_empty(), "every rule has an entry: %d rules, missing %s" % [Rulebook.SRC.size(), missing])
	var extra := heads.filter(func(h): return not Rulebook.SRC.has(h))
	ok(extra.is_empty(), "every entry is a rule in Rulebook.SRC (extra: %s)" % [extra])
	var thin := []
	for r in Rulebook.SRC:
		var i := doc.find("## " + r + "\n")
		if i < 0:
			continue
		var j := doc.find("\n## ", i + 3)
		var body := doc.substr(i, (j if j >= 0 else doc.length()) - i)
		for part in ["- Source", "- Numbers", "- Used by", "- Tested by"]:
			if not body.contains(part):
				thin.append("%s lacks %s" % [r, part])
	ok(thin.is_empty(), "each entry has Source, Numbers, Used by, Tested by (%s)" % [thin])
	var gone := []
	var tre := RegEx.create_from_string("`(tests/[a-z_]+\\.gd)`")
	for m in tre.search_all(doc):
		if not FileAccess.file_exists("res://" + m.get_string(1)):
			gone.append(m.get_string(1))
	ok(gone.is_empty(), "every test file named exists (missing: %s)" % [gone])
	var urls := {}
	for r in Rulebook.URL:
		urls[Rulebook.URL[r]] = true
	var ure := RegEx.create_from_string("https?://[^\\s)\\]`,;]+")
	var bad := []
	var n := 0
	for line in doc.split("\n"):
		for m in ure.search_all(line):
			n += 1
			var u := m.get_string(0)
			if not (urls.has(u) or rules.contains(u) or line.contains("[background]")):
				bad.append(u)
	ok(bad.is_empty(), "%d web links, each a rulebook URL, in MOTION_RULES.md or [background] (stray: %s)" % [n, bad])
	print("PEOPLE DOC TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
