## godot --headless --path . -s tests/grip_magnet_test.gd     (round 47, GATES CC3)
## THE MAGNET: the staff in the right hand (Nick's grip), the LEFT hand dragged as the app drags it (GripMagnet.drag).
##   1 SNAP: walked in from 30 cm off the shaft in 1 cm steps it stays free until within one hand length, then snaps:
##     its palm on the shaft (palm to the axis surface <= 2 cm), every fingertip wrapped (<= 3 mm or at its limit). Where
##     the arm cannot reach the asked place it takes the nearest one it can (<= 10 cm toward the body, <= 60 deg round)
##   2 SLIDE: the drag moved 10 cm along the shaft (toward the holding hand) in 1 cm steps, the hand follows: its place along the shaft moved
##     10 +- 1.5 cm, held all the way
##   3 ROLL: the drag carried 40 deg round the shaft in 5 deg steps: the hand's roll round the shaft moved >= 25 deg,
##     held all the way
##   4 LET GO: pulled straight off the staff it lets go at 1.5 hand lengths (grip off, grip2 empty); on the bat, snapped
##     where swing_fore's first card holds it and dragged up the handle toward the barrel, it holds to the handle's end and lets go half a hand past it
##   5 LIMITS: after every step of 1-4, every joint of the body inside its limits (ang == clamp_ang(ang))
##   6 the bat: its barrel is not a handle: a drag onto the barrel (past the handle's end) stays free
##   7 the app's own hand drag (main._drag_joint) goes through the magnet and the status line says SNAPPED
extends SceneTree

var fails := 0
var B: Body
var bent := []


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func limits() -> void:
	for j in Body.ORDER:
		var v: Vector3 = B.ang[j]
		if v.distance_to(B.clamp_ang(j, v)) > 0.01:
			bent.append(j)


## a world point at u along the shaft, r off it, `ang` round it (the shaft's own frame)
func at(u: float, r: float, ang: float) -> Vector3:
	var x := B.wep_xform()
	return (x[0] as Vector3) + (x[1] as Quaternion) * Vector3(r * sin(ang), u, r * cos(ang))


func palm_off() -> float:
	var palm: Vector3 = (B.P["hand_l"] as Vector3).lerp(B.E["hand_l"], 0.6) + (B.G["hand_l"] as Quaternion) * Vector3(0, -0.03, 0)
	return float(GripMagnet.shaft_coords(B, palm)[1]) - B.wep_r_handle


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	B = m.B
	B.fast = false   # an edit, as in the app
	var bo: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/bo_spin.json"))
	B.from_dict(bo["cards"][8]["pose"])
	B.grip = false
	B.grip2 = {}
	var L := GripMagnet.hand_len(B)
	var u0 := 0.95
	var side := float(GripMagnet.shaft_coords(B, B.P["hand_l"])[2])
	# 1 snap
	var states := []
	var first_snap := -1.0
	for i in range(30, -1, -1):
		var st := GripMagnet.drag(B, "hand_l", at(u0, i / 100.0, side))
		limits()
		states.append(st)
		if st == "snap":
			first_snap = i / 100.0
			break
	var rep := GripWrap.wrap(B, "hand_l", B.wep_point(GripMagnet.span(B).x), B.wep_point(GripMagnet.span(B).y), B.wep_r_handle) if first_snap >= 0 else {}
	var tips_ok := first_snap >= 0
	for f in rep:
		if f != "thumb":
			var row: Array = rep[f][2]
			tips_ok = tips_ok and (row[2] == "limit" or float(row[1]) <= 0.003)
	print("     walk-in states: %s" % [states])
	ok(first_snap >= 0 and first_snap <= L + 0.005 and states.count("free") == states.size() - 1 and palm_off() <= 0.02 and tips_ok,
		"1 snap: free until %.0f cm off the shaft (hand length %.1f cm), palm %.1f cm from the shaft's surface, fingertips wrapped (%s)" % [first_snap * 100, L * 100, palm_off() * 100, tips_ok])
	# 2 slide
	var ua: float = B.grip_u
	var held := true
	for i in 10:
		var st := GripMagnet.drag(B, "hand_l", at(ua - (i + 1) / 100.0, 0.04, side))
		limits()
		held = held and st == "held"
	ok(held and absf(ua - B.grip_u - 0.10) <= 0.015, "2 slide: the hand moved %.1f cm along the shaft (toward the holding hand) for a 10 cm drag, held all the way (%s)" % [(ua - B.grip_u) * 100, held])
	# 3 roll
	var r0 := _roll()
	held = true
	for i in 8:
		var st := GripMagnet.drag(B, "hand_l", at(B.grip_u, 0.04, side + deg_to_rad(5.0 * (i + 1))))
		limits()
		held = held and st == "held"
	var dr := rad_to_deg(absf(angle_difference(_roll(), r0)))
	ok(held and dr >= 25.0, "3 roll: the hand rolled %.0f deg round the shaft for a 40 deg drag, held all the way (%s)" % [dr, held])
	# 4 let go: pulled straight off the shaft, then (on the bat, where the knob end is within reach) past an end
	var out2 := ""
	var rr := 0.04
	while rr < 2.0 * L and out2 != "let go":
		rr += 0.01
		out2 = GripMagnet.drag(B, "hand_l", at(B.grip_u, rr, side))
		limits()
	var g2 := B.grip
	# the bat as swing_fore's first card holds it (both hands on it: Nick's standard bat grip, the second hand 0.18 m up)
	var sf: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/swing_fore.json"))
	B.from_dict(sf["cards"][0]["pose"])
	B.grip = true
	B.apply_grip()
	var u_snap: float = B.grip_u
	B.grip = false
	B.grip2 = {}
	var sb := GripMagnet.span(B)
	var bside := float(GripMagnet.shaft_coords(B, B.P["hand_l"])[2])
	for i in range(20, -1, -1):
		if GripMagnet.drag(B, "hand_l", at(u_snap, i / 100.0, bside)) == "snap":
			break
	var snapped := B.grip
	var out1 := ""
	var uu := u_snap
	var held_to := u_snap
	while uu < sb.y + L and out1 != "let go":
		uu += 0.01
		out1 = GripMagnet.drag(B, "hand_l", at(uu, 0.04, bside))
		limits()
		if out1 == "held":
			held_to = B.grip_u
	var past := uu - sb.y
	print("     let go off the shaft at %.0f cm; on the bat, snapped at %.2f m (%s), held up to %.2f m (the handle ends at %.2f), let go %.1f cm past it (the rule: half a hand, %.1f)" % [rr * 100, u_snap, snapped, held_to, sb.y, past * 100, L * 50])
	ok(out2 == "let go" and not g2 and rr >= 1.5 * L - 0.011 and snapped and out1 == "let go" and absf(held_to - sb.y) <= 0.011 and absf(past - 0.5 * L) <= 0.011 and B.grip2.is_empty(),
		"4 let go: %.0f cm off the shaft (rule 1.5 hands = %.0f), and %.1f cm past the bat handle's end (rule half a hand = %.1f); grip %s, grip2 %s" % [rr * 100, 150 * L, past * 100, 50 * L, B.grip, B.grip2.size()])
	ok(bent.is_empty(), "5 every joint inside its limits after every step (%s)" % [bent])
	# 6 the bat's barrel
	B.grip = false
	B.grip2 = {}
	var stb := GripMagnet.drag(B, "hand_l", at(sb.y + 0.15, 0.03, bside))
	ok(stb == "free" and absf(sb.y - B.wep_handle) < 1e-6, "6 the bat: grippable to %.2f m (the handle), a drag onto the barrel stays %s" % [sb.y, stb])
	# 7 the app's own drag (main._drag_joint, a hand pulled with the mouse): the left hand pulled onto the bat handle
	B.grip = false
	B.grip2 = {}
	B.fast = false
	m.sel = "hand_l"
	var goal := at(u_snap, 0.03, bside)
	var mpp: float = 2.0 * m.dist * tan(deg_to_rad(m.cam.fov * 0.5)) / m.get_viewport().get_visible_rect().size.y
	var rel := Vector2(20, 0)
	var dw: Vector3 = m.cam.global_basis.x * rel.x * mpp - m.cam.global_basis.y * rel.y * mpp
	m._grab = goal - dw
	m._drag_joint(rel, false, false, false)
	ok(B.grip and String(B.grip2.get("hand", "")) == "hand_l" and m.ui_status.text.contains("SNAPPED"), "7 a real hand drag in the app snaps it on: grip %s, the line says \"%s\"" % [B.grip, m.ui_status.text.left(60)])
	m.queue_free()
	print("GRIP MAGNET TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)


## the left hand's roll round the shaft: the angle of its wrist round the axis
func _roll() -> float:
	return float(GripMagnet.shaft_coords(B, B.P["hand_l"])[2])
