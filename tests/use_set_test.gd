## godot --path . -s tests/use_set_test.gd     (GATES TT3; needs a window; the buttons are clicked)
## SIT HERE, STEP UP. combo3 open. A chair added and picked: SET > Sit here adds ONE card (one undo step) where the body
## faces away from the chair's back, the hips rest on the seat (within 1 cm), both feet are flat on the floor (within
## 1 cm), the knees bend 60-110 deg, and nothing goes into the chair. The same on a stool (higher: the feet are planted
## down to the floor). A table picked: both greyed, with a reason. Step up with the box out of reach: refused in words,
## nothing changed; the box 45 cm in front of a foot: a card with that foot on its top and the other on the floor,
## nothing into the box. Ctrl+Z takes a card back.
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


func sole(sd: String) -> float:
	var B: Body = m.B
	return minf((B.P["ball" + sd] as Vector3).y - (B.p0["ball" + sd] as Vector3).y, (B.P["foot" + sd] as Vector3).y - (B.p0["foot" + sd] as Vector3).y)


## the scene as it plays at the selected card
func at_card() -> void:
	m.S.apply(m.B, float(m.S.times()[m.sel_card][1]))


func knee(sd: String) -> float:
	var B: Body = m.B
	var th: Vector3 = (B.P["calf" + sd] as Vector3) - (B.P["thigh" + sd] as Vector3)
	var sh: Vector3 = (B.P["foot" + sd] as Vector3) - (B.P["calf" + sd] as Vector3)
	return rad_to_deg(th.angle_to(sh))


func sit_on(kind: String) -> void:
	m._prop_add(kind)
	await idle(2)
	var n0: int = m.S.cards.size()
	var u0: int = m.undo.size()
	var b := on_set("Sit here")
	ok(b != null and not b.disabled, "a %s picked: Sit here is live" % kind)
	await click_ctl(b)
	ok(m.S.cards.size() == n0 + 1 and m.undo.size() == u0 + 1 and String(m.S.cards[m.sel_card]["name"]) == "sit on the " + kind, "  clicked: one card '%s', one undo step" % m.S.cards[m.sel_card]["name"])
	at_card()
	var p: Dictionary = m.S.props[m.sel_prop]
	var fwd: Vector3 = ((p["xf"] as Transform3D).basis * Vector3(0, 0, 1))
	var B: Body = m.B
	var face: Vector3 = ((B.P["calf_l"] as Vector3) + (B.P["calf_r"] as Vector3)) / 2.0 - ((B.P["thigh_l"] as Vector3) + (B.P["thigh_r"] as Vector3)) / 2.0
	face.y = 0.0
	var sup: Dictionary = Props.supports(p)[0]
	var top: float = sup["y"]
	var lo := INF   # the hips' and thighs' lowest surface OVER the seat (a thigh tilting down past its edge is not on it)
	for part in Body.SEAT_PARTS:
		var c := B.cap(part)
		for k in 41:
			var q: Vector3 = (c[0] as Vector3).lerp(c[1], k / 40.0)
			if Props._over(sup, q):
				lo = minf(lo, q.y - float(B.rad[part]))
	var hits := Rulebook.prop_hits([p], B)
	ok(face.normalized().dot(fwd) > 0.95, "  facing away from its back (%.2f)" % face.normalized().dot(fwd))
	ok(lo - top > -0.005 and lo - top < 0.01, "  the hips on the seat: lowest over it %.3f m, seat %.3f" % [lo, top])
	ok(absf(sole("_l")) < 0.01 and absf(sole("_r")) < 0.01, "  both feet on the floor (%.3f, %.3f m)" % [sole("_l"), sole("_r")])
	ok(knee("_l") >= 60.0 and knee("_l") <= 110.0 and knee("_r") >= 60.0 and knee("_r") <= 110.0, "  knees bent %.0f / %.0f deg" % [knee("_l"), knee("_r")])
	ok(hits.is_empty(), "  nothing into the %s %s" % [kind, hits])


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.S.name = "zz_use_set"
	m.sel_card = 0
	at_card()
	m._ribbon("SET")
	await idle(3)
	await sit_on("chair")
	var n1: int = m.S.cards.size()
	m._undo()
	await idle(2)
	ok(m.S.cards.size() == n1 - 1, "Ctrl+Z: the sitting card gone (%d cards)" % m.S.cards.size())
	m.sel_card = 0
	at_card()
	await sit_on("stool")
	# a table: both greyed with a reason
	m._prop_add("table")
	await idle(2)
	var sb := on_set("Sit here")
	var tb := on_set("Step up")
	ok(sb.disabled and tb.disabled and sb.tooltip_text.contains("chair") and tb.tooltip_text.contains("box"), "a table picked: Sit here and Step up greyed ('%s')" % sb.tooltip_text.right(60))
	# step up: out of reach, then in reach
	m.sel_card = 0
	at_card()
	m._prop_add("box")
	await idle(2)
	var n2: int = m.S.cards.size()
	var u2: int = m.undo.size()
	var st: Dictionary = m.B.state()
	await click_ctl(on_set("Step up"))
	ok(m.S.cards.size() == n2 and m.undo.size() == u2 and JSON.stringify(m.B.state()) == JSON.stringify(st) and m.ui_status.text.contains("out of the foot's reach"),
		"Step up with the box %.1f m off: refused ('%s'), nothing changed" % [(m.S.props[m.sel_prop]["xf"] as Transform3D).origin.distance_to(m.B.P["pelvis"] * Vector3(1, 0, 1)), m.ui_status.text.left(70)])
	var fr: Vector3 = m.B.P["ball_r"]
	var d := Props.to_dict(m.S.props[m.sel_prop])
	d["pos"] = [fr.x, 0.0, fr.z + 0.45]
	d["yaw"] = 0.0
	m.S.props[m.sel_prop] = Props.from_dict(d)
	m._props_show()
	await idle(2)
	await click_ctl(on_set("Step up"))
	ok(m.S.cards.size() == n2 + 1 and String(m.S.cards[m.sel_card]["name"]) == "step up on the box", "the box 45 cm in front of the right foot: Step up adds '%s'" % m.S.cards[m.sel_card]["name"])
	at_card()
	var B: Body = m.B
	var hi := "_l" if sole("_l") > sole("_r") else "_r"
	var lo_sd := "_r" if hi == "_l" else "_l"
	var hits := Rulebook.prop_hits([m.S.props[m.sel_prop]], B)
	ok(absf(sole(hi) - 0.40) < 0.01 and absf(sole(lo_sd)) < 0.01, "  one foot on its top (%.3f m), the other on the floor (%.3f m)" % [sole(hi), sole(lo_sd)])
	ok(hits.is_empty(), "  nothing into the box %s" % [hits])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
	print("USE SET TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
