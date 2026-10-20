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
##  (6) PLACEMENT: the timeline carries a box per flight inside the flight's own span, the arc polyline inside the box; the body is in the air at the playhead
extends SceneTree

var fails := 0
var m: Node
const OUT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/i43.png"


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
	m._view(2)
	m.dist = 7.0
	m.playhead = float(f["t0"]) + float(f["T"]) * 0.5
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	await idle(4)
	root.get_texture().get_image().save_png(OUT)
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
	print("I43 ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
