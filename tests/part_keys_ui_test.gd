## godot --path . -s tests/part_keys_ui_test.gd     (GATES WW1, UPGRADES #239; needs a window: the real poser)
## KEY ONE PART in the poser: combo3 open, the playhead at 0.42 s, the right forearm picked and bent by hand. The K key
## (a real key event through the window's input) keys it: one undo step, the status line says "keyed lowerarm_r at
## 0.42 s", the scene's sample at 0.42 s IS the bent angle, a frame away it follows the key, not the cards. K again at
## the same time replaces the key (still one key). Ctrl+Z takes one press back; a second Ctrl+Z leaves no key.
## The registry has "Key the part here" on K, marked as an edit. With the weapon picked: refused, nothing changed.
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


func key(code: Key, ctrl := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = down
		e.ctrl_pressed = ctrl
		Input.parse_input_event(e)
		await process_frame
	await idle(2)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.playhead = 0.42
	m.S.apply(m.B, 0.42)
	m.sel = "lowerarm_r"
	var cards_v: Vector3 = m.B.ang["lowerarm_r"]
	m.B.set_ang_safe("lowerarm_r", cards_v + Vector3(25, 0, 0))
	var bent: Vector3 = m.B.ang["lowerarm_r"]
	m._refresh()
	await idle(2)
	var reg: Array = m.ui_cmd.commands.filter(func(c): return c["keys"] == "K")
	ok(reg.size() == 1 and reg[0]["edits"] == true and reg[0]["name"] == "Key the part here", "the registry has one command on K, an edit: %s" % str(reg.map(func(c): return c["name"])))
	var u0: int = m.undo.size()
	await key(KEY_K)
	var said: String = m.ui_status.text
	var keys: Array = m.S.part_keys.get("lowerarm_r", [])
	ok(keys.size() == 1 and m.undo.size() == u0 + 1, "K: %d key on lowerarm_r, %d undo step (bar 1 and 1)" % [keys.size(), m.undo.size() - u0])
	ok(said.contains("keyed lowerarm_r at 0.42 s"), "  the status line: '%s'" % said)
	var at: Vector3 = m.S.sample(0.42)["ang"]["lowerarm_r"]
	ok(at.distance_to(bent) < 1e-4 and bent.distance_to(cards_v) > 5.0, "  the scene at 0.42 s has the bent forearm %s (the cards gave %s)" % [at, cards_v])
	var later: Vector3 = m.S.sample(1.5)["ang"]["lowerarm_r"]
	var cards_later: Vector3 = m.S._sample_cards(1.5)["ang"]["lowerarm_r"]
	ok(later.distance_to(bent) < 1e-4, "  one key holds for the whole scene: %s at 1.5 s (the cards there: %s)" % [later, cards_later])
	m.B.set_ang_safe("lowerarm_r", bent + Vector3(10, 0, 0))
	var bent2: Vector3 = m.B.ang["lowerarm_r"]
	await key(KEY_K)
	keys = m.S.part_keys.get("lowerarm_r", [])
	ok(keys.size() == 1 and (keys[0]["v"] as Vector3).distance_to(bent2) < 1e-4 and m.undo.size() == u0 + 2, "K again at the same time replaces it: %d key, %s (bar %s), %d undo steps" % [keys.size(), keys[0]["v"], bent2, m.undo.size() - u0])
	await key(KEY_Z, true)
	keys = m.S.part_keys.get("lowerarm_r", [])
	ok(keys.size() == 1 and (keys[0]["v"] as Vector3).distance_to(bent) < 1e-4 and m.undo.size() == u0 + 1, "Ctrl+Z takes back one press: the key is %s again" % (keys[0]["v"] if not keys.is_empty() else "gone"))
	await key(KEY_Z, true)
	ok(m.S.part_keys.is_empty() and m.undo.size() == u0, "Ctrl+Z again: no part keys (%d keyed joints)" % m.S.part_keys.size())
	m.sel = "bat_handle"
	var u1: int = m.undo.size()
	await key(KEY_K)
	ok(m.S.part_keys.is_empty() and m.undo.size() == u1 and String(m.ui_status.text).contains("BODY part"), "the weapon picked: refused, nothing changed ('%s')" % m.ui_status.text)
	print("PART KEYS UI TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
