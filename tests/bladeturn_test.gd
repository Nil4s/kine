## godot --path . -s tests/bladeturn_test.gd     (BLADE TURN / HEAD TILT, w4-bladeturn; needs a window, pinned 1280x720)
## Bars, written before measuring. On scenes/axe_strike_pose.json: a COPY is loaded (user://), the shipped file is never written.
## Every press is a real mouse event (root.push_input(e, true)) at a control's centre or at a part's screen point.
##  (a) Expert, the axe held: the Blade turn and Head tilt sliders and the "Turn blade 90°" / "Flip blade" buttons are visible
##  (b) "Turn blade 90°" (real click): the weapon's long axis moves < 1 deg, its head direction turns 90 +- 2 deg about the long
##      axis, the holding hand's position moves < 0.5 mm and its turn < 0.1 deg (the hand does not move)
##  (c) that press is one undo step, and Undo restores B.state() exactly (var_to_str equal)
##  (d) only the current card's saved weapon changes: the other cards' pose dicts are byte-equal (var_to_str), the current card's
##      weapon carries the turn
##  (e) "Flip blade" twice = the original weapon rotation (within 0.1 deg) and the knob where it was (within 1 mm)
##  (f) Head tilt +30 (the slider): the long axis tips 30 +- 2 deg about the palm's side axis (the hand's x), the palm still on the
##      shaft: the point of the shaft at the palm before the tilt is still on the shaft after it (within 1 mm), the hand unmoved
##  (g) Easy: the Blade turn slider shows in the side panel when the axe is picked, and a real drag of it turns the blade (> 5 deg),
##      the long axis stays (< 1 deg), the hand unmoved
## Expected on the old code: (a) and (b) FAIL (no sliders, no buttons, nothing turns).
extends SceneTree

var fails := 0
var m: Node
const SRC := "res://scenes/axe_strike_pose.json"
const COPY := "user://zz_bladeturn_axe.json"
const SHOT := "C:/Temp/claude/bt/bladeturn.png"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func btn(b: MouseButton, down: bool, p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = b
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await idle(2)


func move(p: Vector2, rel: Vector2, mask: int) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = rel
	e.button_mask = mask
	root.push_input(e, true)
	await idle(2)


func click(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await btn(MOUSE_BUTTON_LEFT, true, p)
	await btn(MOUSE_BUTTON_LEFT, false, p)


func click_at(p: Vector2) -> void:
	await btn(MOUSE_BUTTON_LEFT, true, p)
	await btn(MOUSE_BUTTON_LEFT, false, p)


## a real drag of a slider from its centre, by the given px steps
func drag_from(p0: Vector2, steps: Array) -> void:
	var p := p0
	await move(p, Vector2(1, 0), 0)
	await btn(MOUSE_BUTTON_LEFT, true, p)
	for s in steps:
		p += s
		await move(p, s, MOUSE_BUTTON_MASK_LEFT)
	await btn(MOUSE_BUTTON_LEFT, false, p)


func spot(j: String) -> Vector2:
	var c: Array = m.B.cap(j)
	return m.cam.unproject_position((c[0] + c[1]) * 0.5)


func fresh() -> void:
	DirAccess.copy_absolute(ProjectSettings.globalize_path(SRC), ProjectSettings.globalize_path(COPY))
	m._load_scene(COPY)
	m._refresh()
	await idle(4)


func hand_btn(name: String) -> Button:
	for b in m.find_children(name, "Button", true, false):
		if (b as Button).is_visible_in_tree():
			return b as Button
	return null


func vis(name: String) -> Control:
	for n in m.find_children(name, "", true, false):
		if (n as Control).is_visible_in_tree():
			return n as Control
	return null


## the weapon's long axis, head direction (across the blade: local x) and knob, now
func wep_frame() -> Array:
	var x: Array = m.B.wep_xform()
	var q: Quaternion = x[1]
	return [q * Vector3.UP, q * Vector3.RIGHT, x[0], q]


func deg(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(a.normalized().angle_to(b.normalized()))


func card_dump() -> Array:
	var out := []
	for c in m.S.cards:
		out.append(var_to_str(c["pose"]))
	return out


func _init() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS   # the layout at 1280x720
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	DirAccess.make_dir_recursive_absolute("C:/Temp/claude/bt")

	# ---- (a) the controls, the axe held (Expert); the weapon picked by a real press so its section opens
	await fresh()
	var B = m.B
	ok(B.wep_on and B.wep_hand != "", "start: the axe is in a hand (on %s, hand '%s', kind '%s')" % [B.wep_on, B.wep_hand, B.wep_kind])
	await click_at(spot("bat_handle"))
	await idle(4)
	var h: String = B.wep_hand
	var sl_turn := vis("slider_blade_turn")
	var sl_tilt := vis("slider_blade_tilt")
	var b_turn := hand_btn("btn_turn_blade")
	var b_flip := hand_btn("btn_flip_blade")
	ok(sl_turn != null and sl_tilt != null and b_turn != null and b_flip != null,
		"(a) Expert, axe held: Blade turn slider %s, Head tilt slider %s, 'Turn blade 90°' %s, 'Flip blade' %s visible" % [sl_turn != null, sl_tilt != null, b_turn != null, b_flip != null])
	if b_turn == null or b_flip == null or sl_turn == null:
		print("FAIL no controls: the rest of the bars need them")
		quit(1)
		return
	var img: Image = m.get_viewport().get_texture().get_image()
	img.resize(1280, 720)
	img.save_png(SHOT)
	print("     screenshot: %s" % SHOT)

	# ---- (b) real click: Turn blade 90 degrees
	await fresh()
	await click_at(spot("bat_handle"))
	await idle(3)
	B = m.B
	h = B.wep_hand
	m.sel_card = 1 if m.S.cards.size() > 1 else -1
	m._refresh()
	await idle(2)
	var f0 := wep_frame()
	var hand0: Vector3 = B.P[h]
	var g0: Quaternion = B.G[h]
	var cards0 := card_dump()
	var st0 := var_to_str(B.state())
	var undo0: int = m.undo.size()
	b_turn = hand_btn("btn_turn_blade")
	await click(b_turn)
	await idle(3)
	var f1 := wep_frame()
	var axis_d: float = deg(f0[0], f1[0])
	var head_d: float = deg(f0[1], f1[1])
	var hand_mv: float = (B.P[h] as Vector3).distance_to(hand0) * 1000.0
	var hand_rot: float = rad_to_deg((B.G[h] as Quaternion).angle_to(g0))
	print("     (b) two-hand grip on: %s (other hand %s)" % [B.grip, B.grip2.get("hand", "")])
	print("     (b) long axis moved %.3f deg, head turned %.2f deg, hand moved %.3f mm, hand turned %.4f deg, turn %.1f deg" % [axis_d, head_d, hand_mv, hand_rot, rad_to_deg(B.wep_turn)])
	ok(axis_d < 1.0 and absf(head_d - 90.0) <= 2.0 and hand_mv < 0.5 and hand_rot < 0.1,
		"(b) Turn blade 90 (real click): long axis %.2f deg (< 1), head %.2f deg (90 +- 2), hand %.3f mm (< 0.5), hand turn %.3f deg (< 0.1)" % [axis_d, head_d, hand_mv, hand_rot])

	# ---- (c) one undo step, Undo restores B.state() exactly
	var step_ok: bool = m.undo.size() == undo0 + 1
	ok(step_ok, "(c) one undo step for the press (undo steps %d -> %d)" % [undo0, m.undo.size()])
	# (d) the card: the current card's weapon changed, the others byte-equal
	var cards1 := card_dump()
	var others_equal := true
	for i in cards0.size():
		if i != 1 and cards0[i] != cards1[i]:
			others_equal = false
	var cur_turn := false
	if m.S.cards.size() > 1:
		var wp: Dictionary = m.S.cards[1]["pose"].get("weapon", {})
		cur_turn = absf(float(wp.get("turn", 0.0)) - PI * 0.5) < 1e-3
	ok(others_equal and cur_turn and cards0[1] != cards1[1],
		"(d) only the current card (card 2) keeps the turn (its weapon turn %s), the other %d cards byte-equal: %s" % [cur_turn, cards0.size() - 1, others_equal])
	m._undo()
	await idle(3)
	var same: bool = var_to_str(B.state()) == st0
	ok(same, "(c) Undo restores B.state() exactly")

	# ---- (e) Flip blade twice = the original
	await fresh()
	await click_at(spot("bat_handle"))
	await idle(3)
	B = m.B
	h = B.wep_hand
	var q0: Quaternion = (B.wep_xform()[1] as Quaternion)
	var k0: Vector3 = B.wep_xform()[0]
	for i in 2:
		b_flip = hand_btn("btn_flip_blade")
		await click(b_flip)
		await idle(2)
	var q2: Quaternion = (B.wep_xform()[1] as Quaternion)
	var k2: Vector3 = B.wep_xform()[0]
	var back_deg := rad_to_deg(q0.angle_to(q2))
	var knob_mm := k0.distance_to(k2) * 1000.0
	ok(back_deg < 0.1 and knob_mm < 1.0, "(e) Flip blade twice = the original: rotation %.4f deg (< 0.1), knob %.3f mm (< 1)" % [back_deg, knob_mm])

	# ---- (f) Head tilt +30 about the palm's side axis, the palm still on the shaft
	await fresh()
	await click_at(spot("bat_handle"))
	await idle(3)
	B = m.B
	h = B.wep_hand
	var fa := wep_frame()
	var palm: Vector3 = B.palm_point(h)
	var pv0: Vector3 = fa[2] + (fa[0] as Vector3) * (palm - (fa[2] as Vector3)).dot(fa[0])   # the shaft point at the palm
	var hand_p0: Vector3 = B.P[h]
	var g_f0: Quaternion = B.G[h]
	var tilt_sl := vis("slider_blade_tilt") as HSlider
	tilt_sl.value = 30.0   # the slider's value changed: the body follows (as a drag does)
	await idle(3)
	var fb := wep_frame()
	var tip_d: float = deg(fa[0], fb[0])
	var side_axis: Vector3 = (B.G[h] as Quaternion) * Vector3.RIGHT
	var ax: Vector3 = (fa[0] as Vector3).cross(fb[0] as Vector3).normalized()
	var axis_fit: float = absf(ax.dot(side_axis.normalized()))
	var pv_line: float = ((pv0 - (fb[2] as Vector3)) - (fb[0] as Vector3) * (pv0 - (fb[2] as Vector3)).dot(fb[0])).length() * 1000.0
	var palm_d0: float = palm.distance_to(pv0) * 1000.0
	var palm_d1: float = (B.palm_point(h) as Vector3).distance_to(pv0) * 1000.0
	var hand_mv_f: float = (B.P[h] as Vector3).distance_to(hand_p0) * 1000.0
	print("     (f) tip %.2f deg, axis fit %.4f, shaft point at the palm off the new shaft %.3f mm, palm-to-handle %.2f -> %.2f mm, hand moved %.3f mm" % [tip_d, axis_fit, pv_line, palm_d0, palm_d1, hand_mv_f])
	ok(absf(tip_d - 30.0) <= 2.0 and axis_fit > 0.98 and pv_line < 1.0 and absf(palm_d1 - palm_d0) < 1.0 and hand_mv_f < 0.5,
		"(f) Head tilt +30: long axis tips %.2f deg (30 +- 2) about the palm side axis (fit %.4f), the handle still in the palm (off %.3f mm < 1, distance %.2f -> %.2f mm), hand moved %.3f mm" % [tip_d, axis_fit, pv_line, palm_d0, palm_d1, hand_mv_f])

	# ---- (g) Easy: the Blade turn slider in the side panel, a real drag turns the blade
	await fresh()
	m.easy.set_on(true, false)
	await idle(6)
	await click_at(spot("bat_handle"))
	await idle(8)
	B = m.B
	var panel: Control = m.easy.sliders.panel
	var s0: HSlider = m.easy.sliders._rows[0]["slider"]
	var shown: bool = panel.is_visible_in_tree() and s0.is_visible_in_tree() and String(m.easy.sliders._title.text) == "Weapon in hand"
	ok(shown, "(g) Easy: the axe picked, the side panel shows the Blade turn slider (panel %s, slider %s)" % [panel.visible, s0.visible])
	var ga := wep_frame()
	var turn0 := rad_to_deg(B.wep_turn)
	var gh0: Vector3 = B.P[B.wep_hand]
	var c := s0.get_global_rect().get_center()
	await drag_from(c, [Vector2(20, 0), Vector2(20, 0), Vector2(10, 0)])
	await idle(4)
	var gb := wep_frame()
	var turned := rad_to_deg(B.wep_turn) - turn0
	var axis_g := deg(ga[0], gb[0])
	var hand_g := (B.P[B.wep_hand] as Vector3).distance_to(gh0) * 1000.0
	print("     (g) real drag: turn %.1f deg, long axis %.3f deg, hand %.3f mm, slider %.1f" % [turned, axis_g, hand_g, s0.value])
	ok(turned > 5.0 and axis_g < 1.0 and hand_g < 0.5, "(g) a real drag of the Blade turn slider turns the blade %.1f deg (> 5), the long axis %.3f deg (< 1), the hand %.3f mm (< 0.5)" % [turned, axis_g, hand_g])

	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)
