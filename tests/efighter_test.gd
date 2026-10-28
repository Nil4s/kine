extends SceneTree
## godot --path . --position 4000,4000 -s tests/efighter_test.gd     (EFIGHTER: Easy Part's "Give to fighter" with the sword template; needs a window and the CAD DLL)
## Bars, written before measuring (real clicks at 1280 x 720 from the real start screen: BUILDING project, Part, Easy, the sword chip, Give to fighter):
##   1 GIVE     the Easy sword is given: the fighter holds it in the RIGHT hand (hand_r), kind part:sword, ONE undo step
##   2 GRIP     the right palm sits on the grip: within 3 cm of the sword's grip (the template's handle centre, grip_u) along the shaft, and
##              within 5 cm of the shaft's axis (the grip book's palm bar)
##   3 SEAT     the hand is the recorded sword grip (data/grips/book/sword.json "one_hand"): the wrist within 2 cm of its recorded place in the
##              weapon's frame and the hand turned within 15 deg of its recorded turn, so the blade runs out the forward side as recorded
##   5 BLADE    through the same punch the blade points forward: its tip never has a backward (-Z) part (sampled every 0.1 s)
##   4 PUNCH    the fighter throws a punch (Easy home's "punch", the Go path): through its clip (sampled every 0.1 s) the sword stays in hand_r
##              with the same palm and seat bars as 2 and 3 (<= 5 cm from the axis, the palm on the grip, the wrist within 2 cm of its place)
## Shots in C:/Temp/claude/efighter/. Only user:// is written (and the shots).
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/efighter"
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
		print("efighter: %d fail (no DLL)" % fails)
		quit(1)
		return
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep: EasyPart = pu.ep
	await click_ctl(ep.chips["sword"])
	await idle(3)
	var n_undo: int = m.undo.size()
	await click_ctl(ep.give_btn)
	await idle(4)
	var B: Body = m.B
	ok(B.wep_on and B.wep_hand == "hand_r" and B.wep_kind.begins_with("part:") and m.undo.size() == n_undo + 1,
		"1 GIVE: the sword in hand_r (on %s, hand %s, kind %s), undo +%d" % [B.wep_on, B.wep_hand, B.wep_kind, m.undo.size() - n_undo])
	await shot("given")
	if B.wep_on:
		grip_bars("2/3 at the give:")
	# 4 PUNCH: the Easy home's punch, built as its Go button builds it
	var home = m.easy.home if m.easy != null else null
	if home == null:
		ok(false, "4 PUNCH: no Easy home to throw the punch from")
	else:
		var before := grip_now()
		home._build("punch", "punch", "punch", false)
		await idle(4)
		var worst_off := 0.0
		var worst_u := 0.0
		var in_hand := true
		var seat_ok := true
		var worst_back := 0.0
		var t := 0.0
		while t <= 1.5:
			m._ps().apply(m.B, t)
			m.playhead = t
			await idle(2)
			B = m.B
			if not (B.wep_on and B.wep_hand == "hand_r"):
				in_hand = false
				break
			var gn := grip_now()
			var tip: Vector3 = (B.wep_xform()[1] as Quaternion) * Vector3.UP
			worst_back = minf(worst_back, tip.z)
			worst_off = maxf(worst_off, float(gn[1]))
			var kd: Dictionary = Body.KINDS.get(B.wep_kind, {})
			worst_u = maxf(worst_u, absf(float(gn[0]) - float(kd.get("grip_u", 0.0))))
			var sd := seed_hand()
			if not sd.is_empty() and (gn[2] as Vector3).distance_to(Body._v(sd["lpos"]) * B.hand_s("hand_r")) > 0.02:
				seat_ok = false
			t += 0.1
		ok(in_hand and worst_off <= 0.05 and worst_u <= 0.03 and seat_ok,
			"4 PUNCH: through the punch the sword stays in hand_r (%s), palm <= %.1f cm off the axis (5), <= %.1f cm from the grip (3), seat kept (%s)" % [in_hand, worst_off * 100.0, worst_u * 100.0, seat_ok])
		ok(in_hand and worst_back >= 0.0, "5 BLADE: through the punch the blade never points back: the lowest forward part of its tip is %.2f (bar: 0 or more)" % worst_back)
		await shot("punch")
	print("efighter: %d fail" % fails)
	quit(1 if fails > 0 else 0)
