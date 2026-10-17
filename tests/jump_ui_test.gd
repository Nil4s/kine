## godot --path . -s tests/jump_ui_test.gd     (GATES VV1; needs a window: ANIMATE > Airborne is clicked)
## A five-card jump (stand, dip, legs reaching, land, stand: the same as jump_test) in the real poser. Card 3 picked:
## Airborne is clicked. Card 3 is marked, one undo step, the button shows on, the status line says the flight time and
## the height it means (0.57 s -> 40 cm), the body is off the floor mid-flight in the poser's own playback. Ctrl+Z takes
## it back (on the floor again). Card 1 picked: refused (no card before it), nothing changed.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func click_ctl(c: Control) -> void:
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
	await idle(3)


func on_animate(t: String) -> BaseButton:
	for b in m.ui_ribbon["ANIMATE"].find_children("*", "BaseButton", true, false):
		if m.label_of(b) == t:
			return b
	return null


func legs(B: Body, thigh: float, calf: float) -> Dictionary:
	var R := Body.new()
	R.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	for sd in ["_l", "_r"]:
		R.set_ang("thigh" + sd, Vector3(thigh, 0, 0))
		R.set_ang("calf" + sd, Vector3(calf, 0, 0))
	R.fk()
	return R.to_dict()


func mid_sole() -> float:
	var fl: Array = m.S.flights()
	if fl.is_empty():
		var ts: Array = m.S.times()
		m.S.apply(m.B, (float(ts[1][2]) + float(ts[3][1])) / 2.0)
	else:
		m.S.apply(m.B, (float(fl[0]["t0"]) + float(fl[0]["t1"])) / 2.0)
	return m.B.sole_low()


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var S := Scene.new()
	S.name = "zz_jump_ui"
	S.add("stand", legs(null, 0, 0))
	S.add("dip", legs(null, 50, 90))
	S.add("air", legs(null, 10, 20))
	S.add("land", legs(null, 50, 90))
	S.add("stand", legs(null, 0, 0))
	var mv := [0.3, 0.3, 0.2855, 0.2855, 0.4]
	var hd := [0.1, 0.05, 0.0, 0.1, 0.2]
	for i in 5:
		S.cards[i]["move"] = mv[i]
		S.cards[i]["hold"] = hd[i]
	m.S = S
	m._rebuild_cards()
	m._ribbon("ANIMATE")
	m.sel_card = 2
	m._refresh()
	await idle(2)
	var before := mid_sole()
	var b := on_animate("Airborne")
	ok(b != null and b.visible, "ANIMATE has an Airborne button")
	if b == null:
		print("JUMP UI TEST FAIL %d" % fails)
		quit(fails)
		return
	var u0: int = m.undo.size()
	await click_ctl(b)
	var said: String = m.ui_status.text
	ok(m.S.cards[2].get("air", false) == true and m.undo.size() == u0 + 1, "clicked on card 3: marked in the air, one undo step")
	ok(said.contains("0.57 s") and said.contains("40 cm"), "  it says the flight and the height: '%s'" % said)
	m._refresh()
	await idle(2)
	ok(b is Button and (b as Button).toggle_mode and (b as Button).button_pressed, "  the button shows it on (toggle %s, pressed %s)" % [(b as Button).toggle_mode, (b as Button).button_pressed])
	var flying := mid_sole()
	ok(before < 0.005 and flying > 0.20, "mid-flight in the poser's own playback the soles are %.3f m up (before the click %.3f)" % [flying, before])
	m._undo()
	await idle(2)
	ok(not m.S.cards[2].has("air") and mid_sole() < 0.005, "Ctrl+Z: on the floor again (%.3f m)" % mid_sole())
	m.sel_card = 0
	m._refresh()
	var u1: int = m.undo.size()
	await click_ctl(b)
	ok(not m.S.cards[0].has("air") and m.undo.size() == u1 and String(m.ui_status.text).contains("card before it"), "card 1: refused, nothing changed ('%s')" % m.ui_status.text)
	print("JUMP UI TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
