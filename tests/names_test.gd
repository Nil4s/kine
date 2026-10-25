## godot --path . -s tests/names_test.gd     (GATES U2, item 99; needs a window)
## NAME EVERY WIDGET: an agent or a test finds a control by its name (find_child), not by its place on the screen. Every
## Button / SpinBox / OptionButton / LineEdit / CheckBox / CheckButton / MenuButton / Slider in the window must have
## a name of its own (Godot calls an unnamed node "@Button@123", and that number changes from run to run), and no two
## may share a path. The census is taken with the panels full: cards in the row, CHECK findings, the history.
extends SceneTree

var fails := 0
var m: Node
const KINDS := ["Button", "SpinBox", "OptionButton", "LineEdit", "CheckBox", "CheckButton", "MenuButton", "HSlider", "VSlider", "TextEdit"]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func census(n: Node, out: Array) -> void:
	for c in n.get_children(false):   # not the engine's own parts (a menu's search box): not the window's to name
		if c.get_class() in KINDS or (c is BaseButton) or (c is Range and c is Control and not (c is ScrollBar) and not (c is ProgressBar)):
			out.append(c)
		census(c, out)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle()
	m._load_scene("res://scenes/combo3.json")   # read only
	await idle()
	m._check()
	m._toggle_history()
	m._card_pick(2)
	await m.dummy_settle()
	await idle()
	var all := []
	census(m, all)
	var unnamed := all.filter(func(c): return String(c.name).begins_with("@"))
	var paths := {}
	var dup := []
	for c in all:
		var p := String(m.get_path_to(c))
		if paths.has(p):
			dup.append(p)
		paths[p] = true
	print("     %d controls; unnamed by kind: %s" % [all.size(), _by_kind(unnamed)])
	for c in unnamed.slice(0, 12):
		print("       e.g. %s  '%s'  under %s" % [c.get_class(), _label(c), m.get_path_to(c.get_parent())])
	var dump := FileAccess.open(OS.get_environment("TMP") + "/names_dump.txt", FileAccess.WRITE)
	for c in all:
		dump.store_line("%s	%s	%s" % [c.name, c.get_class(), m.get_path_to(c)])
	dump.close()
	ok(all.size() > 50, "the census found the window's controls (%d)" % all.size())
	ok(unnamed.is_empty(), "every control has a name of its own (%d without)" % unnamed.size())
	var lost := all.filter(func(c): return address(c) == "")
	for c in lost.slice(0, 8):
		print("       not findable: %s  at %s" % [c.name, m.get_path_to(c)])
	ok(lost.is_empty(), "every control is FOUND by name: find_child from the window or from its named scope (%d not)" % lost.size())
	var widest := {}
	for c in all:
		widest[address(c).count("/")] = widest.get(address(c).count("/"), 0) + 1
	print("     addresses by depth (0 = found from the window): %s; e.g. %s, %s, %s" % [widest, address(all[3]), address(lost[0] if not lost.is_empty() else all[-1]), address(m.find_child("card_2", true, false).find_child("b_update", true, false))])
	# found by its ADDRESS alone, pressed (its own signal, as a click sends), does what its label says
	var c2: Node = find("card_2/b_pick")
	c2.pressed.emit()
	ok(m.sel_card == 1, "card_2/b_pick ('%s') -> card 2 is picked" % c2.text)
	var hs: Node = find("card_2/spin_hold")
	var want: float = hs.value + 5 * hs.step   # on its step (0.05 s)
	hs.value = want
	ok(absf(float(m.S.cards[1]["hold"]) - want) < 1e-6, "card_2/spin_hold set to %.2f -> card 2 holds %.2f s" % [want, m.S.cards[1]["hold"]])
	var tr0: bool = m.ov.trail_on
	find("b_trail").pressed.emit()
	ok(m.ov.trail_on != tr0, "b_trail ('Trail (T)') -> the trail turned %s" % ("on" if m.ov.trail_on else "off"))
	var ang0: Vector3 = m.B.ang["upperarm_l"]
	m.B.ang["upperarm_r"] = Vector3(10, 40, 0)
	find("b_mirror_pose").pressed.emit()
	ok(not m.B.ang["upperarm_l"].is_equal_approx(ang0), "b_mirror_pose -> the left arm took the right's pose (%s)" % m.B.ang["upperarm_l"])
	find("check_panel/b_close").pressed.emit()
	ok(not m.ui_find.visible, "check_panel/b_close -> the CHECK panel is put away")
	m._close_findings()
	find("ribbon_check/b_check").pressed.emit()
	await idle()
	ok(m.ui_find.visible and m.check_ran, "ribbon_check/b_check -> CHECK ran, its panel shows (%d findings)" % m.findings.size())
	ok(find("check_panel/finding_1") != null and find("check_panel/finding_1").text.contains(m.findings[0]["rule"]), "  check_panel/finding_1 is the first finding (%s)" % m.findings[0]["rule"])
	print("NAMES: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)


## an address -> its control: each part is found inside the one before (find_child, as an agent would)
func find(addr: String) -> Node:
	var n: Node = m
	for part in addr.split("/"):
		n = n.find_child(part, true, false) if n != null else null
	if n == null:   # stop here: the next line would press nothing, and a test that hangs reports nothing
		ok(false, "'%s' is not found" % addr)
		print("NAMES: %d failed" % fails)
		TestFiles.cleanup()
		quit(1)
	return n


## how an agent finds c: "name" (find_child from the window) or "scope/name" (scope found the same way); "" = cannot
func address(c: Node) -> String:
	var a := c.get_parent()
	while a != null:
		if a == m or not String(a.name).begins_with("@"):
			if a.find_child(c.name, true, false) == c:
				if a == m:
					return String(c.name)
				var up := address(a)
				return "" if up == "" else up + "/" + String(c.name)
		if a == m:
			return ""
		a = a.get_parent()
	return ""


func _by_kind(a: Array) -> Dictionary:
	var d := {}
	for c in a:
		d[c.get_class()] = d.get(c.get_class(), 0) + 1
	return d


func _label(c: Node) -> String:
	for k in ["text", "placeholder_text", "tooltip_text"]:
		if k in c and String(c.get(k)) != "":
			return String(c.get(k)).left(30)
	return ""
