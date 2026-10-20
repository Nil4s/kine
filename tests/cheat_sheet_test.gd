extends SceneTree
## P22 printable cheat sheet. Bars: (1) every command with a key in the registry is on the Keys page, (2) every command
## is in exactly one group, (3) the HTML has print styles (A4) and nothing unescaped (<, & from names), (4) written only
## to the test's own user:// file
var fails := 0
func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1
func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 4:
		await process_frame
	var cmds: Array = m._commands()
	var nk := 0
	for c in cmds:
		nk += 1 if String(c["keys"]) != "" else 0
	var p := "user://cheat_sheet_test_%d.html" % OS.get_process_id()
	var r := CheatSheet.write(cmds + [{"name": "Test: a <b> & c", "keys": "", "desc": "x<y"}], p)
	var h := FileAccess.get_file_as_string(p)
	ok(int(r["keyed"]) == nk and nk > 20, "(1) %d keyed commands on the Keys page (registry has %d)" % [r["keyed"], nk])
	var total := 0
	for g in r["groups"]:
		total += h.count("<h2>%s (" % CheatSheet._esc(g))
	ok(total == (r["groups"] as Array).size() and h.count("class='n'") == nk + cmds.size() + 1, "(2) %d groups, each once; %d command rows" % [total, h.count("class='n'")])
	ok(h.contains("size:A4") and h.contains("a &lt;b&gt; &amp; c") and not h.contains("<b>"), "(3) print styles; names escaped")
	ok(src_has_cmd(), "(4) palette has Help: printable cheat sheet")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("CHEAT SHEET ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails else 0)
func src_has_cmd() -> bool:
	return FileAccess.get_file_as_string("res://scripts/main.gd").contains('add.call("Help: printable cheat sheet"')
