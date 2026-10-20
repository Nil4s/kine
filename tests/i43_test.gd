## godot --path . -s tests/i43_test.gd     (ROADMAP I43: airborne spin check, scripts/spin_check.gd + spin_check_ui.gd; needs a window)
## Three jumps built from the jump_physics layout (stand, dip, air, land, stand; flight 0.571 s):
##   OK    a take-off spin: the dip card is already turned 30 deg (the pivot), the air and land cards keep a constant rate (ease linear) to 180 deg
##   BAD   a mid-air 180 deg turn from nothing: dip at 0 deg, air 90 deg, land 180 deg on the default smooth ease (no momentum at take-off)
##   FLOAT a hover (on_floor off): 8 cards whose hips rise and fall as a sine, 0.40 m high over 0.8 s (a = -6.3 m/s^2 against -9.81)
## Bars, written before measuring:
##  (1) OK: one flight, a/g in [0.9, 1.1], not flagged; H0 > 2 kg m^2/s; the body turns 120-200 deg and no more than the limit
##  (2) BAD: flagged as a spin; turns >= 150 deg; the momentum in flight reaches >= 2 x its take-off value (it came from nowhere)
##  (3) FLOAT: flagged as a float, a/g < 0.85 (expected 0.6-0.7)
##  (4) cards byte-identical after the panel, Fix the flights and Preview; Accept = ONE undo step; BAD is then not flagged, H0 > 3 kg m^2/s, its
##      landing facing within 1 deg of before; Ctrl+Z restores the cards exactly
##  (5) FLOAT after Accept: a/g in [0.9, 1.1], not flagged; Ctrl+Z exact
##  (7) STEP 2 (b), written before measuring: a straight 75 kg body: twist inertia 1.0-1.5 kg m^2, somersault inertia 9-16 kg m^2 (de Leva radii);
##      a body rising at a constant 3 m/s in a fixed pose reads |H| < 0.5 (velocities are relative to the COM); a mirror-symmetric limb motion
##      (jumping jack) reads |H| < 1.0 kg m^2/s while the same motion on one side only reads > 2 (the reading is not blind)
##  (8) STEP 2 (c): a 360 deg spin kick on 3 steps of 120 deg, both directions: flagged before the fix; after Accept not flagged, the fix says 360 deg,
##      the flight twist has the AUTHORED sign and |twist| 200-330 deg (the rest is the take-off pivot), the landing facing unchanged
##  (9) STEP 2 (a): in the screenshot the head top and both feet at the playhead are inside the viewport, clear of the top bar, the bottom panel and the findings panel
##  (6) PLACEMENT: the timeline carries a box per flight inside the flight's own span, the arc polyline inside the box; the body is in the air at the playhead
extends SceneTree

var fails := 0
var m: Node
const OUT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/i43b.png"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func pose(thigh: float, calf: float, arm: float, yaw: float, up := 0.0) -> Dictionary:
	var B := body()
	for sd in ["_l", "_r"]:
		B.set_ang("thigh" + sd, Vector3(thigh, 0, 0))
		B.set_ang("calf" + sd, Vector3(calf, 0, 0))
		B.set_ang("upperarm" + sd, Vector3(arm, 0, 0))
	B.fk()
	if yaw != 0.0:
		B.turn_world("pelvis", Quaternion(Vector3.UP, deg_to_rad(yaw)))
		B.fk()
	B.ground()
	B.offset.y += up
	B.fk()
	return B.to_dict()


func jump(yaws: Array, linear: bool) -> Array:
	var cards := []
	var spec := [["stand", 0, 0, 0, 0.3, 0.1], ["dip", 50, 90, 0, 0.3, 0.05], ["air", 10, 20, 0, 0.2855, 0.0], ["land", 50, 90, 0, 0.2855, 0.1], ["stand", 0, 0, 0, 0.4, 0.2]]
	for i in 5:
		var s: Array = spec[i]
		var c := {"name": s[0], "pose": pose(s[1], s[2], s[3], yaws[i]), "move": s[4], "hold": s[5]}
		if i == 2:
			c["air"] = true
		if linear and i >= 2 and i <= 3:
			c["ease"] = "linear"
		cards.append(c)
	return cards


func hover() -> Array:
	var cards := [{"name": "stand", "pose": pose(0, 0, 0, 0), "move": 0.3, "hold": 0.1}, {"name": "go", "pose": pose(0, 0, 0, 0), "move": 0.3, "hold": 0.05}]
	for i in range(1, 8):
		cards.append({"name": "up%d" % i, "pose": pose(0, 0, 0, 0, 0.40 * sin(PI * i / 8.0)), "move": 0.1, "hold": 0.0, "ease": "linear"})
	cards.append({"name": "down", "pose": pose(0, 0, 0, 0), "move": 0.1, "hold": 0.2, "ease": "linear"})
	return cards


func load_cards(cards: Array, floor_on: bool) -> void:
	m.S.cards = cards
	m.S.on_floor = floor_on
	m.S.natural = false
	m.S.spline = false
	m.S.markers = []
	m._rebuild_cards()
	m._refresh()


func cj() -> String:
	return JSON.stringify(m.S.cards)


## the pelvis's facing (deg about vertical) at time t of the main scene
func yaw_of(t: float) -> float:
	m.S.apply_true(m.B, t)
	m.B.fk()
	var fwd: Vector3 = (m.B.G["pelvis"] as Quaternion) * Vector3.FORWARD
	return rad_to_deg(atan2(fwd.x, -fwd.z))


var place_msg := ""


## the three points that must be seen: the head top and both feet (heels) at the playhead
func must_see() -> Array:
	return [Proportions.head_top(m.B), m.B.P["foot_l"], m.B.P["foot_r"]]


## the rectangle the body may use: the window minus the top bar, the bottom panel and the findings panel
func free_rect() -> Rect2:
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var r := Rect2(Vector2(8.0, float(m.TOP_H) + 8.0), Vector2.ZERO)
	var right := vs.x - 8.0
	if m.ui_find.visible:
		right = minf(right, m.ui_find.get_global_rect().position.x - 8.0)
	r.size = Vector2(right - r.position.x, vs.y - float(m.bottom_h) - 40.0 - r.position.y)
	return r


## side view of the whole jump: the camera looks at the middle of the body's height range over the flight (floor to the head at the apex) and the
## horizontal middle of the free area; distance from the height range (the COM arc's full height + the body). Returns the placement verdict.
func frame_air(f: Dictionary) -> bool:
	var lo := INF
	var hi := -INF
	var t0 := float(f["t0"])
	for i in 11:
		m.S.apply_true(m.B, t0 + float(f["T"]) * float(i) / 10.0)
		m.B.fk()
		lo = minf(lo, minf((m.B.P["foot_l"] as Vector3).y, (m.B.P["foot_r"] as Vector3).y))
		hi = maxf(hi, Proportions.head_top(m.B).y)
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var fr := free_rect()
	var half_t := tan(deg_to_rad(m.cam.fov * 0.5))
	var com: Vector3 = Balance.com(m.B)
	m._view(2)
	m.target = Vector3(com.x, (lo + hi) * 0.5, com.z)
	m.dist = ((hi - lo) * 1.2) / (2.0 * half_t * (fr.size.y / vs.y))
	m._cam()
	await idle(2)
	for it in 6:   # slide the target sideways until the free area's middle is the body's middle
		var q: Vector2 = m.cam.unproject_position(com)
		var dx := q.x - (fr.position.x + fr.size.x * 0.5)
		m.target += m.cam.global_transform.basis.x * (dx * 2.0 * half_t * m.dist / vs.y)
		var qy: Vector2 = m.cam.unproject_position(Vector3(com.x, (lo + hi) * 0.5, com.z))
		m.target += m.cam.global_transform.basis.y * ((qy.y - (fr.position.y + fr.size.y * 0.5)) * 2.0 * half_t * m.dist / vs.y)
		m._cam()
		await idle(1)
	await idle(3)
	var pts := must_see()
	var bad := []
	for k in 3:
		var q: Vector2 = m.cam.unproject_position(pts[k])
		if not fr.grow(-4.0).has_point(q):
			bad.append("%s at %s" % [["head top", "left foot", "right foot"][k], str(q.round())])
	place_msg = "free area %s, " % str(fr) + ("all three inside" if bad.is_empty() else "OUTSIDE: " + ", ".join(bad))
	return bad.is_empty()


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	var ui = m.sp_ui
	print("constants: ", SpinCheck.constants_text())

	# (1) the correct jump
	load_cards(jump([0, 30, 105, 180, 180], true), true)
	var keep := JSON.stringify(m.B.state())
	ui.show()
	await idle()
	ok(JSON.stringify(m.B.state()) == keep, "the analysis leaves the body exactly as it was")
	var r: Dictionary = ui.rep
	var fl: Array = r["flights"]
	ok(fl.size() == 1, "(1) one flight found (%d)" % fl.size())
	var f: Dictionary = fl[0]
	print("OK jump: ", f["msg"])
	print("  T %.3f s, a %.2f (a/g %.3f), H0 %.2f, Hmax %.2f, drift %.2f kg m^2/s, phi %.0f deg (twist %.0f), allowed %.0f, limit %.0f" % [f["T"], f["a"], f["a_ratio"], f["H0"], f["Hmax"], f["drift"], f["phi"], f["twist"], f["phi_allowed"], f["limit"]])
	ok(float(f["a_ratio"]) >= 0.9 and float(f["a_ratio"]) <= 1.1, "(1) a/g %.3f in 0.9-1.1" % f["a_ratio"])
	ok(not bool(f["flag"]), "(1) not flagged")
	ok(float(f["H0"]) > 2.0, "(1) H0 %.2f kg m^2/s > 2" % f["H0"])
	ok(float(f["phi"]) >= 120.0 and float(f["phi"]) <= 200.0 and float(f["phi"]) <= float(f["limit"]), "(1) turns %.0f deg (120-200), limit %.0f" % [f["phi"], f["limit"]])

	# (2) the mid-air turn from nothing
	load_cards(jump([0, 0, 90, 180, 180], false), true)
	ui.show()
	await idle()
	f = ui.rep["flights"][0]
	print("BAD turn: ", f["msg"])
	print("  T %.3f s, a/g %.3f, H0 %.2f, Hmax %.2f, drift %.2f kg m^2/s, phi %.0f deg (twist %.0f), allowed %.0f, limit %.0f" % [f["T"], f["a_ratio"], f["H0"], f["Hmax"], f["drift"], f["phi"], f["twist"], f["phi_allowed"], f["limit"]])
	ok(bool(f["spin"]), "(2) flagged as an impossible spin")
	ok(float(f["phi"]) >= 150.0, "(2) turns %.0f deg (>= 150)" % f["phi"])
	ok(float(f["Hmax"]) >= 2.0 * float(f["H0"]) and bool(f["grow"]), "(2) the momentum grows from %.2f to %.2f kg m^2/s in flight (>= 2 x)" % [f["H0"], f["Hmax"]])

	# (4) fix: nothing changes until Accept
	var before := cj()
	var u0: int = m.undo.size()
	var landing_yaw0 := yaw_of(1.6)
	ui.offer()
	await idle(3)
	m.playhead = float(f["t0"]) + float(f["T"]) * 0.5
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	await idle(2)
	var pl_ok := await frame_air(f)
	root.get_texture().get_image().save_png(OUT)
	ok(pl_ok, "(9) head top and both feet are inside the viewport and clear of the panels: %s" % place_msg)
	ui.preview()
	for i in 6:
		ui.tick(0.1)
	ok(cj() == before and m.undo.size() == u0, "(4) cards byte-identical after the panel, Fix the flights and Preview; no undo step yet")
	print("plan: ", ui.plan["msg"])
	# (6) placement, checked on the flagged timeline (before Accept clears the flag)
	var tl = m.ui_timeline
	ok(tl.spn.size() == 1, "(6) the timeline carries a box for the flight")
	var ts: Array = m.S.times()
	var x0: float = tl.x_of(float(tl.spn[0]["t0"]))
	var x1: float = tl.x_of(float(tl.spn[0]["t1"]))
	var xa: float = tl.x_of(float(ts[1][2]))
	var xb: float = tl.x_of(float(ts[3][1]))
	ok(x0 >= xa - 1.0 and x1 <= xb + 1.0 and x1 - x0 > 20.0, "(6) the box x %.0f-%.0f sits inside the flight's cards %.0f-%.0f" % [x0, x1, xa, xb])
	ok(bool(tl.spn[0]["flag"]) and (tl.spn[0]["ys"] as Array).size() > 10, "(6) the box is red (flagged) and carries the %d-point arc" % (tl.spn[0]["ys"] as Array).size())
	var ap: Control = m.ui_find_list.get_node_or_null("sp_arc_0")
	ok(ap != null and ap.size.x > 200.0 and ap.size.y > 50.0 and ap.is_visible_in_tree(), "(6) the arc plot is in the panel (%s)" % (str(ap.size) if ap != null else "missing"))
	ok(Balance.com(m.B).y > 0.3, "(6) the body is in the air at the playhead (COM %.2f m)" % Balance.com(m.B).y)
	ui.accept()
	await idle()
	ok(m.undo.size() == u0 + 1 and cj() != before, "(4) Accept is ONE undo step (%d -> %d)" % [u0, m.undo.size()])
	var f2: Dictionary = ui.rep["flights"][0]
	print("fixed: ", f2["msg"])
	print("  H0 %.2f, Hmax %.2f, phi %.0f deg, allowed %.0f, limit %.0f" % [f2["H0"], f2["Hmax"], f2["phi"], f2["phi_allowed"], f2["limit"]])
	ok(not bool(f2["flag"]), "(4) the fixed flight is not flagged")
	ok(float(f2["H0"]) > 3.0, "(4) the take-off now carries H0 %.2f kg m^2/s (> 3)" % f2["H0"])
	var dy := absf(angle_difference(deg_to_rad(yaw_of(1.6)), deg_to_rad(landing_yaw0)))
	ok(rad_to_deg(dy) < 1.0, "(4) the landing facing moved %.2f deg (< 1)" % rad_to_deg(dy))
	m._undo()
	await idle()
	ok(cj() == before and m.undo.size() == u0, "(4) Ctrl+Z restores the cards exactly")

	# (3) + (5) the floaty arc
	load_cards(hover(), false)
	ui.show()
	await idle()
	f = ui.rep["flights"][0] if not (ui.rep["flights"] as Array).is_empty() else {}
	ok(not f.is_empty(), "(3) a flight found in the hover")
	print("FLOAT: ", f.get("msg", ""))
	ok(bool(f.get("float", false)) and float(f.get("a_ratio", 9.0)) < 0.85, "(3) flagged as a float, a/g %.3f (< 0.85)" % float(f.get("a_ratio", 9.0)))
	var b2 := cj()
	var u1: int = m.undo.size()
	ui.offer()
	ui.accept()
	await idle()
	ok(m.undo.size() == u1 + 1, "(5) Accept is ONE undo step")
	var f3: Dictionary = ui.rep["flights"][0] if not (ui.rep["flights"] as Array).is_empty() else {}
	print("fixed arc: ", f3.get("msg", ""))
	ok(not f3.is_empty() and float(f3["a_ratio"]) >= 0.9 and float(f3["a_ratio"]) <= 1.1 and not bool(f3["flag"]), "(5) after the fix a/g %.3f in 0.9-1.1, not flagged" % float(f3.get("a_ratio", 0.0)))
	m._undo()
	await idle()
	ok(cj() == b2 and m.undo.size() == u1, "(5) Ctrl+Z restores the cards exactly")
	# (7) STEP 2 (b): the segment inertias and the momentum reading
	var B0 := body()
	B0.ground()
	B0.fk()
	var mass_kg := 0.0
	for pc in HitReaction.pieces(B0):
		mass_kg += float(pc["m"])
	var I_tw := SpinCheck.body_inertia(B0, Vector3.UP)
	var I_sm := SpinCheck.body_inertia(B0, Vector3.RIGHT)
	var I_ap := SpinCheck.body_inertia(B0, Vector3.FORWARD)
	print("straight body %.1f kg: twist I %.2f, somersault I %.2f, cartwheel I %.2f kg m^2" % [mass_kg, I_tw, I_sm, I_ap])
	ok(absf(mass_kg - 75.0) < 0.5 and I_tw >= 1.0 and I_tw <= 1.5, "(7) twist inertia %.2f kg m^2 in 1.0-1.5 (75 kg: %.1f)" % [I_tw, mass_kg])
	ok(I_sm >= 9.0 and I_sm <= 16.0, "(7) somersault inertia %.2f kg m^2 in 9-16" % I_sm)
	# rising at a constant 3 m/s in a fixed pose
	var rise := [{"name": "a", "pose": pose(0, 0, 0, 0), "move": 0.5, "hold": 0.0, "ease": "linear"}, {"name": "b", "pose": pose(0, 0, 0, 0, 1.5), "move": 0.5, "hold": 0.0, "ease": "linear"}]
	load_cards(rise, false)
	var mr := SpinCheck.momentum(m.S, m.B)
	var hm_rise := 0.0
	for h in mr["H"]:
		hm_rise = maxf(hm_rise, (h as Vector3).length())
	ok(hm_rise < 0.5, "(7) a body rising at 3 m/s in a fixed pose reads |H| max %.3f kg m^2/s (< 0.5)" % hm_rise)
	# jumping jack: both legs and both arms out sideways, mirror-symmetric
	var jack_sign := 1.0
	var Bj := body()
	Bj.set_ang("thigh_l", Vector3(0, 30, 0))
	Bj.set_ang("thigh_r", Vector3(0, 30, 0))
	Bj.fk()
	if absf((Bj.P["foot_l"] as Vector3).x + (Bj.P["foot_r"] as Vector3).x) > 0.01:
		jack_sign = -1.0
	var jack := func(deg_l: float, deg_r: float) -> Dictionary:
		var Bk := body()
		for sd in [["_l", deg_l], ["_r", deg_r * jack_sign]]:
			Bk.set_ang("thigh" + sd[0], Vector3(0, sd[1] * (1.0 if sd[0] == "_l" else 1.0), 0))
			Bk.set_ang("upperarm" + sd[0], Vector3(0, sd[1] * 3.0, 0))
		Bk.fk()
		Bk.ground()
		Bk.fk()
		return Bk.to_dict()
	var sym := [{"name": "a", "pose": jack.call(0.0, 0.0), "move": 0.3, "hold": 0.0}, {"name": "b", "pose": jack.call(25.0, 25.0), "move": 0.3, "hold": 0.0}]
	var Bchk := body()
	Bchk.from_dict(sym[1]["pose"])
	Bchk.fk()
	var asym_x := absf((Bchk.P["foot_l"] as Vector3).x + (Bchk.P["foot_r"] as Vector3).x)
	load_cards(sym, false)
	var hm_sym := 0.0
	for h in SpinCheck.momentum(m.S, m.B)["H"]:
		hm_sym = maxf(hm_sym, (h as Vector3).length())
	load_cards([{"name": "a", "pose": jack.call(0.0, 0.0), "move": 0.3, "hold": 0.0}, {"name": "b", "pose": jack.call(25.0, 0.0), "move": 0.3, "hold": 0.0}], false)
	var hm_one := 0.0
	for h in SpinCheck.momentum(m.S, m.B)["H"]:
		hm_one = maxf(hm_one, (h as Vector3).length())
	print("jumping jack: symmetric |H| max %.3f (feet x-asymmetry %.4f m), one side only %.3f kg m^2/s" % [hm_sym, asym_x, hm_one])
	ok(asym_x < 0.01, "(7) the jumping-jack fixture is mirror-symmetric (feet x sum %.4f m)" % asym_x)
	ok(hm_sym < 1.0, "(7) symmetric limb motion reads |H| max %.3f kg m^2/s (< 1.0)" % hm_sym)
	ok(hm_one > 2.0, "(7) the same motion on one side reads %.2f kg m^2/s (> 2: the reading is not blind)" % hm_one)

	# (8) STEP 2 (c): a 360 deg spin kick, both directions
	for dirn in [1.0, -1.0]:
		var yw := [0.0, 0.0, 120.0 * dirn, 240.0 * dirn, 360.0 * dirn, 360.0 * dirn]
		var spec6 := [["stand", 0, 0, 0, 0.3, 0.1], ["dip", 50, 90, 0, 0.3, 0.05], ["air1", 10, 20, 0, 0.14, 0.0], ["air2", 10, 20, 0, 0.14, 0.0], ["land", 50, 90, 0, 0.2855, 0.1], ["stand", 0, 0, 0, 0.4, 0.2]]
		var c6 := []
		for i in 6:
			var sp: Array = spec6[i]
			var cd := {"name": sp[0], "pose": pose(sp[1], sp[2], sp[3], yw[i]), "move": sp[4], "hold": sp[5]}
			if i == 2 or i == 3:
				cd["air"] = true
			c6.append(cd)
		load_cards(c6, true)
		ui.show()
		await idle()
		var fl6: Array = ui.rep["flights"]
		var tag := "360 deg %s" % ("left" if dirn > 0.0 else "right")
		ok(fl6.size() == 1 and bool(fl6[0]["spin"]), "(8) %s: one flight, flagged as an impossible spin before the fix (%d flights)" % [tag, fl6.size()])
		if fl6.is_empty():
			continue
		var b6 := cj()
		var u6: int = m.undo.size()
		ui.offer()
		ok(not ui.plan.is_empty() and String(ui.plan["msg"]).contains("spin 360 deg"), "(8) %s: the fix reads the authored 360 deg: %s" % [tag, String(ui.plan.get("msg", ""))])
		ui.accept()
		await idle()
		var g6: Dictionary = ui.rep["flights"][0]
		print("  ", tag, " fixed: ", g6["msg"])
		ok(m.undo.size() == u6 + 1, "(8) %s: Accept is ONE undo step" % tag)
		ok(not bool(g6["flag"]), "(8) %s: not flagged after the fix (phi %.0f deg, limit %.0f)" % [tag, g6["phi"], g6["limit"]])
		var tws := float(g6["twist"])
		ok(signf(tws) == signf(dirn) and absf(tws) >= 200.0 and absf(tws) <= 330.0, "(8) %s: the flight twists %.0f deg in the authored direction (200-330)" % [tag, tws])
		m._undo()
		await idle()
		ok(cj() == b6, "(8) %s: Ctrl+Z restores the cards exactly" % tag)

	print("I43 ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
