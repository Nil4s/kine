## godot --path . -s tests/c73_test.gd     (C73; needs a window)
## A raw line break inside a GDScript string literal becomes "\r\n" on a Windows CRLF checkout (GREY_TAG in main.gd,
## the hover_hint test). Bars: (1) no .gd under scripts/ or tests/, read at runtime, has a "\r" inside a string literal;
## (2) .gitattributes pins *.gd to LF; (3) GREY_TAG has no "\r" and a greyed button's hint is its tip + GREY_TAG + why.
## Control: the scanner flags a planted literal that holds a CR.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## line numbers where a single-line-quoted string literal is still open at the end of the line and that line ends in CR
func cr_in_literal(src: String) -> Array:
	var out := []
	var tri := ""
	var n_line := 0
	for l in src.split("\n"):
		n_line += 1
		var i := 0
		var n: int = l.length()
		while i < n:
			if tri != "":
				var j: int = l.find(tri, i)
				if j < 0:
					i = n
					break
				tri = ""
				i = j + 3
				continue
			var c: String = l[i]
			if c == "#":
				break
			if c == "\"" or c == "'":
				if l.substr(i, 3) == c.repeat(3):
					tri = c.repeat(3)
					i += 3
					continue
				var j := i + 1
				while j < n and l[j] != c:
					j += 2 if l[j] == "\\" else 1
				if j >= n:
					if l.ends_with("\r"):
						out.append(n_line)
					break
				i = j + 1
				continue
			i += 1
	return out


func gd_files(dir: String, acc: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			acc.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		gd_files(dir.path_join(d), acc)


func _init() -> void:
	ok(cr_in_literal("var a = \"x\r\ny\"\r\n").size() >= 1,"control: the scanner flags a literal that holds a CR")
	ok(cr_in_literal("var a = \"x\\n\"\r\nvar b = 1\r\n").is_empty(), "control: an escaped backslash-n on a CRLF line is not flagged")
	var files := []
	gd_files("res://scripts", files)
	gd_files("res://tests", files)
	var bad := []
	for p in files:
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var hits: Array = cr_in_literal(f.get_buffer(f.get_length()).get_string_from_utf8())
		if not hits.is_empty():
			bad.append("%s:%s" % [p.trim_prefix("res://"), hits.slice(0, 2)])
	ok(files.size() > 500 and bad.is_empty(), "%d .gd files: none has a CR inside a string literal (bad %d: %s)" % [files.size(), bad.size(), bad.slice(0, 6)])
	var ga := FileAccess.get_file_as_string("res://.gitattributes")
	ok(ga.contains("*.gd text eol=lf"), ".gitattributes pins *.gd to LF")
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	ok(not str(m.GREY_TAG).contains("\r") and str(m.GREY_TAG).strip_edges() == "NOT NOW:", "GREY_TAG is NOT NOW: with no CR (%s)" % [str(m.GREY_TAG).c_escape()])
	var b := Button.new()
	b.tooltip_text = "Save the file"
	m._grey(b, "no file is open: open one first")
	ok(b.disabled and b.tooltip_text == "Save the file" + str(m.GREY_TAG) + "no file is open: open one first" and b.tooltip_text.get_slice(m.GREY_TAG, 0) == "Save the file", "greyed: tooltip = tip + GREY_TAG + why, and the tip splits back out")
	m._grey(b, "")
	ok(not b.disabled and b.tooltip_text == "Save the file", "un-greyed: the tip is back unchanged")
	print("C73 TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
