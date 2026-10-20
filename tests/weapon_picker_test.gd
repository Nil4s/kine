## godot --path . -s tests/weapon_picker_test.gd     (GATES FF1, Nick 10-16; a real window, real clicks and keys)
## ONE WEAPON PICKER: the old weapon buttons are gone from both panels (Bat, Bo staff, Hammer, None, Metal bat, Staff
## (bo), Long hammer, Remove bat); each panel has opt_weapon with None / Metal bat / Bo staff / Long hammer / Dagger / 2 daggers (round 33). A REAL click
## opens the Poses one; picking Bo staff = the staff in the hand, ONE undo step, and the right panel's picker shows it
## too; None = the weapon away, one step. Then every other path that changes the weapon, and both pickers must show
## what the body holds after each: the B key, Ctrl+Z, the command search's "Weapon: long hammer", opening combo3 (a
## metal bat). No refresh fires a picker (item_selected counted: 0 outside the two real picks), and picking the row
## already shown adds no step.
extends SceneTree

var fails := 0
var m: Node
var fired := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
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
	await idle(2)


func key(k: Key, ctrl := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.ctrl_pressed = ctrl
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(3)


func pickers() -> Array:
	return m.find_children("opt_weapon*", "OptionButton", true, false)


## what both pickers show, as row names; "" if they disagree
func shown() -> String:
	var ps := pickers()
	var t: String = m.WEAPONS[(ps[0] as OptionButton).selected][0]
	for p in ps:
		if m.WEAPONS[(p as OptionButton).selected][0] != t:
			return ""
	return t


func holds() -> String:
	return "None" if not m.B.wep_on else ("2 daggers" if m.B.wep2_on else {"metal_bat": "Metal bat", "staff": "Bo staff", "long_hammer": "Long hammer", "long_axe": "Long axe", "dagger": "Dagger"}[m.B.wep_kind])


## a real click opens the picker; the pick in its list (the popup is its own window) = select + item_selected
func pick(o: OptionButton, k: int) -> bool:
	await click(o)
	var opened := o.get_popup().visible
	o.get_popup().hide()
	o.select(k)
	o.item_selected.emit(k)
	await idle(3)
	return opened


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._new_scene()
	await idle(2)
	var gone := []
	for t in ["Bat", "Bo staff", "Hammer", "None", "Metal bat", "Staff (bo)", "Long hammer", "Remove bat"]:
		for b in m.find_children("*", "Button", true, false):
			if not (b is OptionButton) and (b as Button).text == t:
				gone.append(t)
	var ps := pickers()
	var items := []
	if not ps.is_empty():
		for i in (ps[0] as OptionButton).item_count:
			items.append((ps[0] as OptionButton).get_item_text(i).get_slice("   ", 0))
	ok(gone.is_empty() and ps.size() == 1 and items == ["None", "Metal bat", "Bo staff", "Long hammer", "Long axe", "Sword", "Longsword", "Katana", "Spear", "Dagger", "2 daggers"],
		"1 the old weapon buttons gone (left: %s); %d pickers, rows %s" % [gone, ps.size(), items])
	for p in ps:
		(p as OptionButton).item_selected.connect(func(_k): fired += 1)
	# round 36 (RR3): the left panel's picker is gone (the browser is a tree); the inspector's WEAPON has the one picker
	m._sec_open("WEAPON", true)
	await idle(3)
	var left: OptionButton = m.find_child("opt_weapon_panel", true, false)
	var u0: int = m.undo.size()
	var opened := await pick(left, 2)
	ok(opened and m.B.wep_on and m.B.wep_kind == "staff" and m.undo.size() == u0 + 1 and shown() == "Bo staff",
		"2 a real click opens the Poses picker (%s); Bo staff picked: in the hand %s, one undo step (%d), both pickers show '%s'" % [opened, holds(), m.undo.size() - u0, shown()])
	await pick(left, 0)
	ok(not m.B.wep_on and m.undo.size() == u0 + 2 and shown() == "None", "3 None picked: the weapon away, one step, both show '%s'" % shown())
	var u1: int = m.undo.size()
	await pick(left, 0)
	ok(m.undo.size() == u1, "4 picking the row already shown (None) adds no step")
	fired = 0
	var paths := {}
	await key(KEY_B)
	paths["B key"] = [holds(), shown()]
	await key(KEY_Z, true)
	paths["Ctrl+Z"] = [holds(), shown()]
	for c in m._commands():
		if c["name"] == "Weapon: long hammer":
			(c["run"] as Callable).call()
	await idle(3)
	paths["search: Weapon: long hammer"] = [holds(), shown()]
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m._refresh()
	await idle(3)
	paths["open combo3"] = [holds(), shown()]
	var want := {"B key": "Bo staff", "Ctrl+Z": "None", "search: Weapon: long hammer": "Long hammer", "open combo3": "Metal bat"}
	var bad := []
	for k in want:
		if paths[k][0] != want[k] or paths[k][1] != want[k]:
			bad.append([k, paths[k]])
	ok(bad.is_empty(), "5 after every other path both pickers show what the body holds: %s (bad: %s)" % [paths, bad])
	ok(fired == 0, "6 no refresh fired a picker (%d item_selected outside the real picks)" % fired)
	print("WEAPON PICKER: %d failed" % fails)
	quit(1 if fails > 0 else 0)
