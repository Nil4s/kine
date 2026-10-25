## godot --path . -s tests/handlock_test.gd     (HANDS, w4-handlock; needs a window, pinned 1280x720)
## Bars, written before measuring. On scenes/axe_strike_pose.json: a COPY is loaded (user://), the shipped file is never written.
## Every press is a real mouse event (root.push_input(e, true)) at a control's centre or at a part's screen point.
##  (a) Expert: the hands row (hands_row) and the Only-the-part toggle are visible in the tree; with the axe in a hand the
##      "Let go" buttons are shown
##  (b) Only-the-part ON: a 40 px drag of the right forearm (lowerarm_r) moves NO joint outside the right arm chain
##      (upperarm_r, lowerarm_r, hand_r and its fingers; the weapon is no joint) by more than 0.5 deg; the pelvis offset
##      does not move. The off hand lets go on that drag (B's grip says free) and the status says so
##  (c) press "Let go: left hand": the left hand stays free (B.grip false, free_hand hand_l); a drag of the left hand 60 px
##      away from the handle and 30 px back: still free, and where the mouse left it (within 3 cm of the mouse's target)
##  (d) "Both hands hold it" puts it back on the handle: B.grip true, the palm / wrist within 1 cm of the handle point
##      (the grip's own place: Body._fit_second's target)
##  (e) each of those presses is exactly one undo step, and Undo restores B.state() exactly (var_to_str equal)
##  (f) Only-the-part OFF (smart drag on, as the app starts): the same 40 px forearm drag moves some joint outside the
##      chain by more than 0.5 deg: the old follow is kept
##  (g) Lock this part on the left upper arm (the header's button, a real press): a drag of the left hand leaves
##      upperarm_l's angles unchanged (within 0.01 deg)
## Expected on the old code: (a), (b), (c), (d), (e) FAIL (no row, no toggle, no let-go, no free hand).
extends SceneTree

var fails := 0
var last_grab := Vector3.ZERO
var m: Node
const SRC := "res://scenes/axe_strike_pose.json"
const COPY := "user://zz_handlock_axe.json"
const SHOT := "C:/Temp/claude/hl/handlock.png"
const CHAIN_FIXED := ["upperarm_r", "lowerarm_r", "hand_r"]


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


func spot(j: String) -> Vector2:
	var c: Array = m.B.cap(j)
	return m.cam.unproject_position((c[0] + c[1]) * 0.5)


func hand_spot(h: String) -> Vector2:
	return m.cam.unproject_position(m.B.P[h])


## is the point over a Control that takes the mouse (a press there is the panel's, not the body's)
func over_control(p: Vector2) -> bool:
	return _over(m.ui_root, p)


func _names(n: Node, p: Vector2, out: Array) -> void:
	for c in n.get_children():
		if c is Control and (c as Control).is_visible_in_tree() and (c as Control).get_global_rect().has_point(p):
			out.append("%s/%s" % [c.name, (c as Control).mouse_filter])
		_names(c, p, out)


func _over(n: Node, p: Vector2) -> bool:
	for c in n.get_children():
		if c is Control:
			var k := c as Control
			if k.is_visible_in_tree() and k.mouse_filter == Control.MOUSE_FILTER_STOP and k.get_global_rect().has_point(p):
				return true
		if _over(c, p):
			return true
	return false


func click(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await btn(MOUSE_BUTTON_LEFT, true, p)
	await btn(MOUSE_BUTTON_LEFT, false, p)


## a real drag from p0: the mouse steps, each a Vector2 of px
func drag_from(p0: Vector2, steps: Array) -> Vector2:
	var p := p0
	await move(p, Vector2(1, 0), 0)
	await btn(MOUSE_BUTTON_LEFT, true, p)
	for s in steps:
		p += s
		await move(p, s, MOUSE_BUTTON_MASK_LEFT)
	last_grab = m._grab
	await btn(MOUSE_BUTTON_LEFT, false, p)
	return p


func angles() -> Dictionary:
	var d := {}
	for j in m.B.ang:
		d[j] = m.B.ang[j]
	return d


func chain_joint(j: String) -> bool:
	if j in CHAIN_FIXED:
		return true
	return j.ends_with("_r") and Body.FINGERS.has(j)


## the largest change (deg) of any joint outside the chain, and its name
func outside_moved(a0: Dictionary) -> Array:
	var worst := 0.0
	var who := ""
	for j in a0:
		if chain_joint(j):
			continue
		var d: Vector3 = (m.B.ang[j] as Vector3) - (a0[j] as Vector3)
		var v := maxf(absf(d.x), maxf(absf(d.y), absf(d.z)))
		if v > worst:
			worst = v
			who = j
	return [worst, who]


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


func any_visible(name: String) -> bool:
	for n in m.find_children(name, "", true, false):
		if (n as Control).is_visible_in_tree():
			return true
	return false


func _init() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS   # the layout at 1280x720 (easyhome pins it the same way)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS   # the layout at 1280x720 (easyhome pins it the same way)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	DirAccess.make_dir_recursive_absolute("C:/Temp/claude/hl")

	# ---- (a) the rows are in the tree (fresh copy, Expert)
	await fresh()
	var B = m.B
	print("     start: wep_on %s wep_hand '%s' grip %s grip2 hand '%s' kind '%s'" % [B.wep_on, B.wep_hand, B.grip, B.grip2.get("hand", ""), B.wep_kind])
	ok(not m.easy.on, "Expert mode (easy off)")
	var row: Node = m.find_child("hands_row", true, false)
	var row_vis: bool = row != null and (row as Control).is_visible_in_tree()
	var only_vis: bool = any_visible("btn_only_part")
	var let_vis: bool = hand_btn("btn_let_go_left") != null and hand_btn("btn_let_go_right") != null
	ok(row_vis and only_vis and let_vis,
		"(a) Expert: the hands row visible %s, the Only-the-part toggle visible %s, the two Let go buttons visible %s (held: %s)" % [row_vis, only_vis, let_vis, B.wep_hand != ""])
	var img: Image = m.get_viewport().get_texture().get_image()
	img.resize(1280, 720)   # the window is 1600 x 900; the shot is the 1280 x 720 layout
	img.save_png(SHOT)
	print("     screenshot: %s" % SHOT)

	# ---- (b) only the part I drag: the forearm drag, nothing outside the arm chain moves
	await fresh()
	m.sel = "lowerarm_r"
	m._refresh()
	await idle(2)
	var a0 := angles()
	var off0: Vector3 = m.B.offset
	var p := spot("lowerarm_r")
	ok(not over_control(p), "(b) the forearm's press point is not over a Control (%s)" % p)
	await drag_from(p, [Vector2(10, 0), Vector2(10, 0), Vector2(10, 0), Vector2(10, 0)])
	var mv: Array = outside_moved(a0)
	var forearm_d: float = ((m.B.ang["lowerarm_r"] as Vector3) - (a0["lowerarm_r"] as Vector3)).length()
	var off_d: float = (m.B.offset - off0).length()
	ok(float(mv[0]) <= 0.5 and off_d < 1e-6 and forearm_d > 0.5,
		"(b) Only-the-part ON, a 40 px drag of the right forearm: the most any joint outside the right arm chain moved %.2f deg (%s), pelvis offset moved %.6f m, the forearm moved %.1f deg" % [float(mv[0]), mv[1], off_d, forearm_d])
	ok(m.B.grip == false and m.B.get("free_hand") == "hand_l" and m.ui_status.text.contains("let go"),
		"(b) the off hand let go on that drag: grip %s, free_hand '%s', say '%s'" % [m.B.grip, m.B.get("free_hand"), m.ui_status.text])

	# ---- (c)-(e) the off hand's let go / free / both, on a fresh copy with both hands holding the axe
	await fresh()
	m.sel = "hand_r"
	m._refresh()
	await idle(2)
	ok(m.B.wep_on and m.B.wep_hand != "" and m.B.grip, "(c) start: the axe in a hand and the off hand on the handle (grip %s, hand '%s')" % [m.B.grip, m.B.wep_hand])
	var n0: int = m.undo.size()
	var s0: String = var_to_str(m.B.state())
	var let_btn := hand_btn("btn_let_go_left")
	ok(let_btn != null and not let_btn.disabled, "(c) the 'Let go: left hand' button is shown and enabled")
	if let_btn != null:
		await click(let_btn)
	var grip_after_let: bool = m.B.grip == false and m.B.get("free_hand") == "hand_l"
	var n1: int = m.undo.size()
	ok(grip_after_let and n1 - n0 == 1, "(c) press 'Let go: left hand': grip %s, free_hand '%s', undo steps +%d (say '%s')" % [m.B.grip, m.B.get("free_hand"), n1 - n0, m.ui_status.text])
	m._undo()
	await idle(2)
	ok(var_to_str(m.B.state()) == s0, "(e) Undo after 'Let go' restores B.state() exactly (grip %s, free_hand '%s')" % [m.B.grip, m.B.get("free_hand")])
	if let_btn != null:
		await click(let_btn)
	await idle(2)
	# the free hand is dragged 60 px away from the handle and 30 px back: it stays free and goes where the mouse goes
	var hp := spot("hand_l")
	ok(not over_control(hp), "(c) the left hand's press point is not over a Control (%s)" % hp)
	var sel_before: String = m.sel
	var h0 := hand_spot("hand_l")
	var mouse_end: Vector2 = await drag_from(hp, [Vector2(10, 0), Vector2(10, 0), Vector2(10, 0), Vector2(10, 0), Vector2(10, 0), Vector2(10, 0), Vector2(-10, 0), Vector2(-10, 0), Vector2(-10, 0)])
	# where the mouse left it: the hand's screen point against the mouse, in metres at the hand's depth
	var mpp: float = 2.0 * m.dist * tan(deg_to_rad(m.cam.fov * 0.5)) / 720.0
	# the hand moved with the mouse: its screen move against the mouse's move (the press point is the hand's capsule centre, not its joint)
	var gap: float = ((hand_spot("hand_l") - h0) - (mouse_end - hp)).length() * mpp
	print("     hand moved %.1f cm (mouse %.1f cm), sel %s -> %s" % [(hand_spot("hand_l") - h0).length() * mpp * 100.0, (mouse_end - hp).length() * mpp * 100.0, sel_before, m.sel])
	var pal: float = GripMagnet.palm_off(m.B, "hand_l")
	ok(m.B.grip == false and m.B.get("free_hand") == "hand_l" and gap <= 0.03,
		"(c) the left hand dragged 60 px off the handle and 30 px back: still free (grip %s, free_hand '%s'), %.1f cm from the mouse (bar 3 cm), palm %.1f cm off the shaft" % [m.B.grip, m.B.get("free_hand"), gap * 100.0, pal * 100.0])

	# (d) Both hands hold it: back on the handle, one undo step, undo restores
	var both := hand_btn("btn_both_hands")
	var s1: String = var_to_str(m.B.state())
	var n2: int = m.undo.size()
	if both != null:
		await click(both)
	var n3: int = m.undo.size()
	var x = m.B.wep_xform()
	var lp: Vector3 = Body._v(m.B.grip2["lpos"]) * m.B.hand_s("hand_l") + Vector3(0, m.B.grip_u, 0)
	var handle: Vector3 = (x[0] as Vector3) + (x[1] as Quaternion) * lp
	var dh: float = (m.B.P["hand_l"] as Vector3).distance_to(handle)
	ok(m.B.grip == true and m.B.get("free_hand") == "" and dh <= 0.01 and n3 - n2 == 1,
		"(d) 'Both hands hold it': grip %s, free_hand '%s', %.2f cm from the handle point (bar 1 cm), undo steps +%d" % [m.B.grip, m.B.get("free_hand"), dh * 100.0, n3 - n2])
	m._undo()
	await idle(2)
	ok(var_to_str(m.B.state()) == s1, "(e) Undo after 'Both hands hold it' restores B.state() exactly")
	both = hand_btn("btn_both_hands")
	if both != null:
		await click(both)
	await idle(2)

	# ---- (f) Only the part I drag OFF: the old follow
	await fresh()
	m.smart_drag = true   # the app's start state (the test's default is off)
	var only_btn := hand_btn("btn_only_part")
	if only_btn != null:
		await click(only_btn)
	await idle(2)
	m.sel = "lowerarm_r"
	m._refresh()
	await idle(2)
	var a1 := angles()
	var pf := spot("lowerarm_r")
	ok(not over_control(pf), "(f) the forearm's press point is not over a Control")
	await drag_from(pf, [Vector2(10, 0), Vector2(10, 0), Vector2(10, 0), Vector2(10, 0)])
	var mv2: Array = outside_moved(a1)
	ok(m.get("only_part") == false and float(mv2[0]) > 0.5,
		"(f) Only-the-part OFF, the same 40 px forearm drag: the old follow moves a joint outside the chain: %s by %.2f deg (only_part %s)" % [mv2[1], float(mv2[0]), m.get("only_part")])
	m.smart_drag = false

	# ---- (g) a locked upper arm stays put while the left hand is dragged
	await fresh()
	m.sel = "upperarm_l"
	m._refresh()
	await idle(2)
	var lock_btn: Button = m.ui_lock_btn
	await click(lock_btn)
	await idle(2)
	ok(m.locked_parts.has("upperarm_l"), "(g) 'Lock this part' on the left upper arm: locked %s" % [m.locked_parts.keys()])
	var ua0: Vector3 = m.B.ang["upperarm_l"]
	var hp2 := hand_spot("hand_l")
	await drag_from(hp2, [Vector2(-10, 0), Vector2(-10, 0), Vector2(-10, 0), Vector2(-10, 0)])
	var ua1: Vector3 = m.B.ang["upperarm_l"]
	ok(ua0.distance_to(ua1) < 0.01, "(g) a drag of the left hand: upperarm_l angles %s -> %s (bar: unchanged)" % [ua0, ua1])

	# ---- (h) Easy: the side panel of a picked hand holds the lock and the hands row (a real press on Let go)
	await fresh()
	m.easy.set_on(true, false)
	await idle(6)
	m.sel = "hand_r"
	m.easy.sliders.part_picked("hand_r")
	m._refresh()
	await idle(6)
	var eb: Button = hand_btn("btn_let_go_left")   # the hands row: an overlay under the top bar, in Easy too
	var el: Button = null
	if m.easy.sliders.panel != null:
		for b in m.easy.sliders.panel.find_children("easy_lock_part", "Button", true, false):
			el = b
	ok(eb != null and el != null and el.is_visible_in_tree(),
		"(h) Easy, a hand picked with the axe in it: the hands row shows the Let go button, the side panel shows Lock this part (%s / %s)" % [eb != null, el != null])
	if eb != null:
		var g0: bool = m.B.grip
		await click(eb)
		ok(m.B.grip == false and m.B.get("free_hand") == "hand_l" and g0,
			"(h) Easy: a real press on 'Let go: left hand' lets the off hand go (grip %s -> %s, free_hand '%s')" % [g0, m.B.grip, m.B.get("free_hand")])
	m.easy.set_on(false, false)
	await idle(2)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(COPY))
	print("handlock: %d fail(s)" % fails)
	quit(1 if fails > 0 else 0)
