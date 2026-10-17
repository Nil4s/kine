## godot --path . -s tests/hints_test.gd     (GATES QQ3; needs a window)
## HINTS CAN BE CLOSED: a real click on the (x) of the yellow strip hides the teaching texts (the welcome line, the
## part's "Drag: rotate it..." line, the Poses caption, the Scene caption) and the strip goes; what the app SAYS about
## an action still shows on it; the choice is saved; VIEW > Hints brings them all back.
extends SceneTree

var m: Node
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func click(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e)
		await process_frame


func shown(l: Control) -> bool:
	return l.is_visible_in_tree() and (not (l is Label) or (l as Label).text != "")


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	var texts: Array = m.ui_hint_labels + [m.ui_how, m.ui_status]
	ok(texts.size() == 4 and texts.all(shown) and m.ui_status.text == m.WELCOME, "at the start all 4 teaching texts show (%s)" % [texts.map(shown)])
	var x: Button = m.ui_status.find_child("hints_close", true, false)
	ok(x != null and x.is_visible_in_tree() and m.get_viewport().get_visible_rect().encloses(x.get_global_rect()), "the strip has a close (x) on screen")
	if x != null:
		await click(x)
	await idle()
	ok(not m.hints_on and not texts.any(shown), "a click on the (x): hints off, none of the 4 shows (%s)" % [texts.map(shown)])
	var cf := ConfigFile.new()
	cf.load(m.settings)
	ok(cf.get_value("look", "hints", true) == false, "the choice is saved")
	m.sel = "head"
	m._refresh()
	await idle()
	ok(not shown(m.ui_how), "picking another part does not bring the part's how-to line back")
	m._say("a message about what you did")
	await idle()
	ok(shown(m.ui_status), "a message still shows on the strip with hints off")
	var hb: Array = m.ui_ribbon["VIEW"].find_children("*", "Button", true, false).filter(func(b): return b.text == "Hints")
	ok(hb.size() == 1, "VIEW has a Hints button")
	if hb.size() == 1:
		(m.ui_ribbon["VIEW"].get_parent() as Control).visible = true
		m.ui_ribbon["VIEW"].visible = true
		await idle()
		await click(hb[0])
	await idle()
	cf.load(m.settings)
	ok(m.hints_on and (m.ui_hint_labels + [m.ui_how]).all(shown) and cf.get_value("look", "hints", false) == true, "VIEW > Hints: back on, saved")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
	print("HINTS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
