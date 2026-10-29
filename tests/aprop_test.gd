extends SceneTree
## godot --path . --position 4000,4000 -s tests/aprop_test.gd     (APROP: an easy animation: a cup built in Easy Part, used in a scene, picked up and drunk from; needs a window and the CAD DLL)
## Real clicks at 1280 x 720 from the start screen: BUILDING card, Part, Easy, a round cup (r 40 mm, Pull to 80 mm), Cut a hole > Hollow inside,
## Use in a scene, then the beginner's next steps (the Easy home's cards, a typed "drink").
## Shots in C:/Temp/claude/aprop/. Only user:// is written (and the shots).
const SHOT := "C:/Temp/claude/aprop"
const DIRT := "user://aprop_test"
var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


func drag_slider(s: HSlider, v: float) -> void:
	var r := s.get_global_rect()
	var y := r.get_center().y
	var gw := 24.0
	var p0 := Vector2(r.position.x + gw * 0.5 + (s.value - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw), y)
	var x1 := r.position.x + gw * 0.5 + (v - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw)
	await ev_move(p0, false)
	await ev_mouse(p0, true)
	for i in range(1, 25):
		await ev_move(Vector2(lerpf(p0.x, x1, i / 24.0), y))
	await ev_mouse(Vector2(x1, y), false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func pu() -> PartUI:
	return m.bld.part


func ep():
	return pu().ep


func errors_of(rec: Dictionary) -> int:
	return Part.replay(rec)["errors"].size()


func chip(nm: String) -> Button:
	return root.find_child(nm, true, false) as Button


## a round cup on the floor: a circle r 40 mm, Pulled to h cm
func round_cup(h: float) -> void:
	m.S.part = Part.make("Part")
	pu().upto = -1
	pu().sync()
	m.target = Vector3(0.0, 0.0, 0.0)
	m.pitch = -40.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["round"])
	await drag_screen(scr(Vector3(0.0, 0.0, 0.0)), scr(Vector3(0.04, 0.0, 0.0)))
	await click_ctl(ep().make_btns["pull"])
	for r in ep().rows:
		if String(r["kind"]) == "tweak":
			await drag_slider(r["slider"], h)
	await idle(3)


func labels(n: Node, out: Array) -> void:
	if n is Label and (n as Label).is_visible_in_tree():
		out.append((n as Label).text)
	for c in n.get_children():
		labels(c, out)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu().set_on(false)
	pu().m.S.part = {}
	await process_frame
	await click_ctl(pu().part_btn)
	await click_ctl(pu().easy_open_btn)
	await idle(4)

	# C1 the cup: a round cup, Pulled to 8 cm, Cut a hole > Hollow inside
	await round_cup(8.0)
	await click_ctl(ep().make_btns["hole"])
	var chh := chip("easypart_hole_hollow")
	if chh != null:
		await click_ctl(chh)
	await idle(3)
	var bodies := int(pu().res.get("bodies", 0))
	ok(bodies == 1 and errors_of(m.S.part) == 0, "C1 CUP the cup is one hollow body (bodies %d, errors %d)" % [bodies, errors_of(m.S.part)])
	await shot("cup")

	# C2 the beginner gives the cup to the character (Easy Part's Give to a character): the cup is in the right hand
	await click_ctl(ep().give_btn)
	await idle(6)
	var B: Body = m.B
	ok(B.wep_on and PartWeapon.is_part(B.wep_kind) and B.wep_hand == "hand_r", "C2 HOLD the cup is in the right hand (on %s, kind %s, hand %s)" % [B.wep_on, B.wep_kind, B.wep_hand])

	# C3 Use in a scene: the cup is a prop on STAGE
	var nprops0: int = m.S.props.size()
	await click_ctl(ep().use_scene_btn)
	await idle(20)
	ok(m.S.props.size() == nprops0 + 1 and m.cur_page == "STAGE", "C3 USE the cup is a prop in the scene (props %d -> %d, page %s)" % [nprops0, m.S.props.size(), m.cur_page])
	await shot("stage")

	# C4 Easy on (VIEW > Mode: Easy), then the beginner presses the Walk card
	m.easy.set_on(true)
	await idle(30)
	var wk: Button = m.easy.home.panel.find_child("eh_card_0", true, false)
	await click_ctl(wk)
	await idle(60)
	await shot("walk")

	# C5 FOLLOW the cup stays in the hand through the Walk clip: the distance from the hand to the cup's grip stays within 2 cm
	var dmin := INF
	var dmax := 0.0
	for i in 10:
		await idle(6)
		var x := B.wep_xform()
		var dd: float = ((x[0] as Vector3) - (B.P[B.wep_hand] as Vector3)).length()
		dmin = minf(dmin, dd)
		dmax = maxf(dmax, dd)
	ok(B.wep_on and PartWeapon.is_part(B.wep_kind) and dmax - dmin <= 0.02, "C5 FOLLOW the cup is in the hand through the Walk (on %s, hand-to-grip %.1f..%.1f cm)" % [B.wep_on, dmin * 100.0, dmax * 100.0])

	# C6 CARRY the cup stays in the scene after the Walk card (it was on STAGE)
	ok(m.S.props.size() >= 1 and PartWeapon.is_part(String(m.S.props[0]["kind"])), "C6 CARRY the cup is still in the scene after the Walk card (props %d)" % m.S.props.size())

	# C7 DRINK: a typed "drink" is a move Kine knows (not refused)
	var ed: LineEdit = m.easy.home.panel.find_child("eh_text", true, false)
	ed.text = "drink"
	ed.text_submitted.emit("drink")
	await idle(20)
	var lab := []
	labels(m, lab)
	var refused := lab.filter(func(t): return String(t).find("doesn't know") >= 0)
	ok(refused.is_empty(), "C7 DRINK a typed drink is built, not refused (said: %s)" % str(refused))

	# C8 PICK UP: Easy has a Pick up button for the picked prop
	var pick := []
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree() and String((b as Button).text).to_lower().find("pick up") >= 0:
			pick.append(b)
	ok(not pick.is_empty(), "C8 PICK UP Easy has a Pick up button for the cup (found %d)" % pick.size())
	# C9 HAND the Easy hand panel names the held cup ("In his hand: the part"), not "the none"
	var hand_said := String(m.easy.home._pbar_hand_name.text) if m.easy.home != null and m.easy.home._pbar_hand_name != null else ""
	ok(hand_said.find("none") < 0 and hand_said.find("his hand: the ") >= 0 and hand_said.length() > 17, "C9 HAND the Easy hand panel names what he holds [%s]" % hand_said)
	await shot("drink")
	print("aprop: %d fail" % fails)
	quit(1 if fails > 0 else 0)
