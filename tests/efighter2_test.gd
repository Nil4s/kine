extends SceneTree
## godot --path . --position 4000,4000 -s tests/efighter2_test.gd     (EFIGHTER2: the sword given to the fighter, through the Easy punch: the blade stays in front; needs a window and the CAD DLL)
## Bars (real clicks at 1280 x 720 from the real start screen, as efighter_test: BUILDING, Part, Easy, the sword chip, Give to fighter, then the punch):
##   1 HAND     through the punch (sampled every 0.05 s) the sword stays in hand_r
##   2 REST     at the start of the punch (t = 0) the blade points forward: its tip is at least 0.1 in front (z)
##   3 FRONT    through the whole punch (every 0.05 s) the blade never points back: its tip's lowest z is 0 or more
##   4 CLEAR    through the whole punch (every 0.05 s) the blade is not in the body: no weapon contact deeper than 1 mm
## Shots in C:/Temp/claude/efighter2/. Only user:// is written (and the shots).
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/efighter2"
const DIRT := "user://efighter_test"
const SEED_NAME := "one_hand"


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
	await idle(2)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


## the grip read off the body now: [u (palm, m from the butt), palm off the axis (m), wrist place in the weapon frame (body m, lpos), hand turn vs weapon (quat)]
func grip_now() -> Array:
	var B: Body = m.B
	var h := B.wep_hand
	var x := B.wep_xform()
	var k: Vector3 = x[0]
	var q: Quaternion = (x[1] as Quaternion).normalized()
	var pl := q.inverse() * (B.palm_point(h) - k)
	var wl := q.inverse() * ((B.P[h] as Vector3) - k)
	var lpos := (wl - Vector3(0, pl.y, 0)) / B.hand_s(h)
	var lrot := (q.inverse() * (B.G[h] as Quaternion)).normalized()
	return [pl.y, Vector2(pl.x, pl.z).length(), lpos, lrot]


## the recorded sword grip's right hand: [lpos, lrot, u]
func seed_hand() -> Dictionary:
	var g := GripBook.find("sword", SEED_NAME)
	for hd in g.get("hands", []):
		if String(hd.get("role", "main")) == "main":
			return hd
	return {}


func grip_bars(tag: String) -> void:
	var B: Body = m.B
	var kd: Dictionary = Body.KINDS.get(B.wep_kind, {})
	var g := grip_now()
	var sd := seed_hand()
	var ang := 0.0
	if not sd.is_empty():
		var lr: Array = sd["lrot"]
		ang = rad_to_deg((g[3] as Quaternion).angle_to(Quaternion(lr[0], lr[1], lr[2], lr[3]).normalized()))
	var dpos := (g[2] as Vector3).distance_to(Body._v(sd["lpos"]) * B.hand_s("hand_r")) if not sd.is_empty() else 9.0
	ok(absf(float(g[0]) - float(kd.get("grip_u", 9.0))) <= 0.03 and float(g[1]) <= 0.05,
		"%s GRIP: palm %.1f cm from the butt (grip at %.1f cm), %.1f cm off the shaft (bars: 3 cm, 5 cm)" % [tag, float(g[0]) * 100.0, float(kd.get("grip_u", 0.0)) * 100.0, float(g[1]) * 100.0])
	ok(dpos <= 0.02 and ang <= 15.0,
		"%s SEAT: wrist %.1f cm from the recorded place, hand turned %.0f deg from the recorded turn (bars: 2 cm, 15 deg)" % [tag, dpos * 100.0, ang])


## Nick 2026-10-28 (7089ca07): Easy Part opens EMPTY now; the weapons and props are not chips (only Box .. Plate are). A bar
## that needs one picks it itself, as a beginner does: the chip if it is shown, else More examples -> From a template -> the item.
## The panel scroll goes back to its top (the picked part's sliders sit at the top, as after a chip click)
func pick_part(t: String) -> void:
	var chip := root.find_child("easypart_chip_" + t, true, false) as Button
	if chip != null and chip.is_visible_in_tree():
		await click_ctl(chip)
		await idle(3)
		return
	await click_ctl(root.find_child("easypart_more_examples", true, false) as Control)
	await idle(10)
	var bc: BuildChoose = m.build_choose
	await click_ctl(bc.btns["template"]["easy"])
	await idle(4)
	bc._starters.id_pressed.emit(1000 + PartTemplates.ORDER.find(t))
	await idle(20)
	var sc := root.find_child("easypart_panel_scroll", true, false) as ScrollContainer
	if sc != null:
		sc.scroll_vertical = 0
		await idle(3)

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
	var pu: PartUI = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	if not Part.available():
		print("SKIP: no KineCAD DLL")
		print("efighter2: %d fail (no DLL)" % fails)
		quit(1)
		return
	# Nick 2026-10-28 (free 3D building, #100): the BUILDING card now opens a blank Easy Part itself. Start from the
	# state the card gave before (Part off, no part), so the clicks below drive the same opening they always did
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep: EasyPart = pu.ep
	# Nick 2026-10-28 (7089ca07): the sword is not a chip any more; navigation only, the bar is not about the pick
	await pick_part("sword")
	await idle(3)
	await click_ctl(ep.give_btn)
	await idle(4)
	var B: Body = m.B
	ok(B.wep_on and B.wep_hand == "hand_r", "0 GIVE: the sword is in hand_r (on %s, hand %s)" % [B.wep_on, B.wep_hand])
	var home = m.easy.home if m.easy != null else null
	if home == null:
		ok(false, "1 HAND: no Easy home to throw the punch from")
		print("efighter2: %d fail" % fails)
		quit(1)
		return
	home._build("punch", "punch", "punch", false)
	await idle(4)
	var worst_back := 0.0
	var worst_contact := 0.0
	var in_hand := true
	var tip0 := 0.0
	var t := 0.0
	var n := 0
	while t <= 1.5:
		m._ps().apply(m.B, t)
		m.playhead = t
		await idle(2)
		B = m.B
		if not (B.wep_on and B.wep_hand == "hand_r"):
			in_hand = false
			break
		var tip: Vector3 = (B.wep_xform()[1] as Quaternion) * Vector3.UP
		if n == 0:
			tip0 = tip.z
		worst_back = minf(worst_back, tip.z)
		for c in B.contacts():
			if (String(c[0]) in Body.WEAPON or String(c[1]) in Body.WEAPON):
				worst_contact = maxf(worst_contact, float(c[2]))
		n += 1
		t += 0.05
	ok(in_hand, "1 HAND: through the punch (%d samples, every 0.05 s) the sword stays in hand_r (%s)" % [n, in_hand])
	ok(tip0 >= 0.1, "2 REST: at the start of the punch the blade points forward: its tip is %.2f in front (bar: 0.10 or more)" % tip0)
	ok(worst_back >= 0.0, "3 FRONT: through the punch the blade never points back: its tip's lowest z is %.2f (bar: 0 or more)" % worst_back)
	ok(worst_contact <= 0.001, "4 CLEAR: through the punch the blade is not in the body: the deepest weapon contact is %.1f mm (bar: 1 mm or less)" % (worst_contact * 1000.0))
	await shot("punch")
	print("efighter2: %d fail" % fails)
	quit(1 if fails > 0 else 0)
