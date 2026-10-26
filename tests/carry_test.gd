## godot --path . -s tests/carry_test.gd     (GATES UU1-UU3; needs a window; Pick up and Put down are clicked)
## SETTLING: a box on a table drops to the floor when the table is deleted; a box left floating rests on the floor.
## CARRY: a four-card scene (on_floor off: the cards are where they are): rest; the body 1 m to the side; 25 cm up;
## put down; a long hold. A 10 cm pillar stands under the right hand. Pick up on card 1 (clicked): the right hand
## holds it (one undo step, the card marked). At card 2 the pillar has moved 1 m with the hand, at card 3 1 m and 25 cm
## up (1 mm). Its top is 1 cm into the hand (a grip): Check does not call a holding hand "through" it. Put down on card 4 (clicked): released 25 cm up, it falls y0 - g t^2 / 2 (1 mm at 0.05, 0.10, 0.20 s)
## and rests on the floor after sqrt(2 h / g) = 0.226 s. The body never stands on it; Check finds nothing through it.
## The marks survive save / load; Mirror swaps the hand; Ctrl+Z takes Put down, then Pick up, back. A box 1 m away:
## Pick up refused with the distance, nothing changed.
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


func on_set(t: String) -> BaseButton:
	for b in m.ui_ribbon["SET"].find_children("*", "BaseButton", true, false):
		if m.label_of(b) == t:
			return b
	return null


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func origin_at(t: float) -> Vector3:
	m.S.apply(m.B, t)
	return (m.S.props_at(t, m.B)[0]["xf"] as Transform3D).origin


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.S.name = "zz_carry"
	m._ribbon("SET")
	await idle(2)
	# UU1 settling
	m._prop_add("table")
	var tx: Vector3 = (m.S.props[0]["xf"] as Transform3D).origin
	m.S.props.append(Props.make("box", Props.xf_at(tx + Vector3(0.2, 0.75, 0), 0.0)))
	m._props_show()
	ok(absf((m.S.props[1]["xf"] as Transform3D).origin.y - 0.75) < 0.001, "a box on the table's top stays there (%.3f m)" % (m.S.props[1]["xf"] as Transform3D).origin.y)
	m.sel_prop = 0
	m._prop_del()
	ok(m.S.props.size() == 1 and (m.S.props[0]["xf"] as Transform3D).origin.y == 0.0, "the table deleted: the box drops to the floor (%.3f m)" % (m.S.props[0]["xf"] as Transform3D).origin.y)
	m._undo()
	await idle(2)
	ok(m.S.props.size() == 2 and absf((m.S.props[1]["xf"] as Transform3D).origin.y - 0.75) < 0.001, "  Ctrl+Z: the table back, the box on it again")
	m.S.props = [Props.make("box", Props.xf_at(Vector3(3, 1.0, 3), 0.0))]
	m._props_show()
	ok((m.S.props[0]["xf"] as Transform3D).origin.y == 0.0, "a box left 1 m in the air with nothing under it: rests on the floor")
	# UU2 / UU3: the carry scene
	var B := body()
	var c := B.cap("hand_r")
	var mid: Vector3 = ((c[0] as Vector3) + (c[1] as Vector3)) / 2.0
	var h: float = mid.y - float(B.rad["hand_r"]) + 0.01   # a grip: the pillar's top 1 cm into the hand
	Props.register("zz pillar", AABB(Vector3(-0.05, 0, -0.05), Vector3(0.1, h, 0.1)), "", 1.0)
	m.S.props = [Props.make("zz pillar", Props.xf_at(Vector3(mid.x, 0, mid.z), 0.0))]
	m.S.on_floor = false
	m.S.cards = []
	m.S.add("rest", B.to_dict())
	B.offset.x += 1.0
	B.fk()
	m.S.add("aside", B.to_dict())
	B.offset.y += 0.25
	B.fk()
	m.S.add("up", B.to_dict())
	m.S.add("let go", B.to_dict())
	m.S.add("after", B.to_dict())
	m.S.cards[4]["hold"] = 1.0
	m._rebuild_cards()
	m.sel_card = 0
	m.sel_prop = 0
	m._props_show()
	m._refresh()
	await idle(2)
	var home: Vector3 = (m.S.props[0]["xf"] as Transform3D).origin
	var u0: int = m.undo.size()
	var pb := on_set("Pick up")
	ok(pb != null and not pb.disabled, "a pillar and card 1 picked: Pick up is live")
	await click_ctl(pb)
	ok(m.S.cards[0].get("take", {}) == {"prop": 0, "hands": ["_r"]} and m.undo.size() == u0 + 1, "clicked: card 1 marks the right hand holding it (%s), one undo step" % [m.S.cards[0].get("take", {})])
	ok(m.S.solid_props().is_empty(), "  the body never stands on it (not in the props it stands on)")
	var ts: Array = m.S.times()
	var d1 := origin_at(ts[1][1]) - home
	var d2 := origin_at(ts[2][1]) - home
	ok(d1.distance_to(Vector3(1, 0, 0)) < 0.001, "at card 2 (the body 1 m aside) the pillar has moved %s" % d1)
	ok(d2.distance_to(Vector3(1, 0.25, 0)) < 0.001, "at card 3 (and 25 cm up) it has moved %s" % d2)
	m.sel_card = 3
	m._props_show()
	await idle(2)
	var qb := on_set("Put down")
	ok(qb != null and not qb.disabled, "card 4 picked while it is held: Put down is live")
	await click_ctl(qb)
	ok(int(m.S.cards[3].get("drop", -1)) == 0 and m.ui_status.text.contains("falls 25 cm"), "clicked: card 4 lets it go ('%s')" % m.ui_status.text.left(80))
	ts = m.S.times()
	var tb: float = ts[3][1]
	var worst := 0.0
	for dt in [0.05, 0.10, 0.20]:
		var y := origin_at(tb + dt).y
		worst = maxf(worst, absf(y - (0.25 - 9.81 * dt * dt / 2.0)))
	ok(worst < 0.001, "it falls by y0 - g t^2 / 2: off by at most %.2f mm at 0.05, 0.10, 0.20 s" % (worst * 1000.0))
	var tf := sqrt(0.5 / 9.81)
	var land := origin_at(tb + tf + 0.02)
	ok(land.y == 0.0 and origin_at(tb + 0.9).y == 0.0 and Vector2(land.x - home.x, land.z - home.z).distance_to(Vector2(1, 0)) < 0.001,
		"  and rests on the floor after %.3f s, where it was let go (1 m aside)" % tf)
	var fs := Rulebook.check(m.S, body())
	var thr := fs.filter(func(f): return f["rule"] == "THROUGH A PROP")
	ok(thr.is_empty(), "Check: nothing through the pillar (%d findings: %s)" % [fs.size(), thr.map(func(f): return String(f["msg"]).left(90))])
	# save / load; mirror
	var S2 := Scene.new()
	S2.from_dict(JSON.parse_string(JSON.stringify(m.S.to_dict(body()))))
	ok(JSON.stringify(S2.carries()) == JSON.stringify(m.S.carries()), "save / load keeps the carry %s" % [S2.carries()])
	var mc := Scene.mirror_card(m.S.cards[0], body())
	ok(mc.get("take", {}).get("hands", []) == ["_l"], "Mirror: the left hand holds it")
	# undo
	m._undo()
	await idle(2)
	ok(not m.S.cards[3].has("drop") and m.S.cards[0].has("take"), "Ctrl+Z: Put down gone, still held")
	m._undo()
	await idle(2)
	ok(not m.S.cards[0].has("take"), "Ctrl+Z: Pick up gone")
	# out of reach
	m.sel_card = 0
	m.S.apply(m.B, 0.0)
	m._prop_add("box")
	await idle(2)
	var u1: int = m.undo.size()
	await click_ctl(on_set("Pick up"))
	ok(not m.S.cards[0].has("take") and m.undo.size() == u1 and m.ui_status.text.contains("the hands are"), "a box out of reach: refused ('%s'), nothing changed" % m.ui_status.text.left(80))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
	print("CARRY TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
