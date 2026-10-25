## godot --path . -s tests/pole_test.gd     (GATES Q5; needs a window)
## IK POLE: the elbow / knee swings about the shoulder-to-hand (hip-to-foot) line while the hand / foot stays put.
## Driven three ways: Body.swing_pole, the panel's "points" buttons, and Ctrl+drag on the hand in the view. Measured:
## the end moves < 1 mm, the elbow's direction about that line turns by the angle asked (within 1 deg) when no limit
## is in the way, and every angle stays inside its range.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## the elbow's direction about the root->tip line, as an angle (deg) in a frame fixed to that line
func pole_deg(B: Body, tip: String, ref: Vector3) -> float:
	var mid: String = B.parent[tip]
	var root: String = B.parent[mid]
	var ax: Vector3 = ((B.P[tip] - B.P[root]) as Vector3).normalized()
	var e: Vector3 = (B.P[mid] - B.P[root]) as Vector3
	e = (e - ax * e.dot(ax)).normalized()
	var r := (ref - ax * ref.dot(ax)).normalized()
	return rad_to_deg(r.signed_angle_to(e, ax))


func in_limits(B: Body) -> bool:
	for j in Body.ORDER:
		if not B.lim.has(j):
			continue
		var v: Vector3 = B.ang[j]
		var L: Dictionary = B.lim[j]
		for k in 3:
			var r: Vector2 = L[["bend", "side", "twist"][k]]
			if v[k] < r.x - 1e-3 or v[k] > r.y + 1e-3:
				return false
	return true


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var B: Body = m.B
	# a bent arm out in front (an elbow that can swing both ways)
	B.set_ang_safe("upperarm_r", Vector3(40, -40, 0))
	B.set_ang_safe("lowerarm_r", Vector3(80, 0, 0))
	B.set_ang_safe("thigh_l", Vector3(30, 0, 0))
	B.set_ang_safe("calf_l", Vector3(60, 0, 0))
	B.fk()
	var full := 0
	for tip in ["hand_r", "foot_l"]:
		var ref := Vector3.UP if tip == "hand_r" else Vector3.FORWARD
		for want in [20.0, -20.0]:
			var p0: Vector3 = B.P[tip]
			var a0 := pole_deg(B, tip, ref)
			var keep := B.state()
			var got := B.swing_pole(tip, want)
			var more := B.swing_pole(tip, signf(want) * 5.0)   # blocked = a further swing that way gains nothing
			var moved: float = ((B.P[tip] - p0) as Vector3).length()
			var turned := wrapf(pole_deg(B, tip, ref) - a0, -180.0, 180.0)
			turned -= more   # measure the asked swing alone
			var blocked := absf(more) < 0.1
			ok(moved < 0.001 and in_limits(B) and absf(got - turned) < 0.1 and (absf(turned - want) < 1.0 or blocked), "%s: swing %+.0f -> the %s turned %+.2f deg (reported %+.2f)%s, the %s moved %.3f mm, limits hold" % [tip, want, "elbow" if tip == "hand_r" else "knee", turned, got, "" if absf(turned - want) < 1.0 else ", BLOCKED (5 more deg that way gained %.2f: a contact or a limit)" % more, tip.get_slice("_", 0), moved * 1000.0])
			full += 1 if absf(turned - want) < 1.0 else 0
			B.set_state(keep)
			B.fk()
	ok(full >= 3, "%d of 4 swings got the full angle (the rest were stopped by a limit, and say so)" % full)
	# a limit in the way: the end still stays put
	var p1: Vector3 = B.P["hand_r"]
	B.swing_pole("hand_r", 170.0)
	ok(((B.P["hand_r"] - p1) as Vector3).length() < 0.001 and in_limits(B), "swing 170 (past the shoulder's range): the hand still stays (%.3f mm), limits hold" % (((B.P["hand_r"] - p1) as Vector3).length() * 1000.0))
	# the panel buttons: one undo step each
	m.sel = "hand_r"
	m._panel()
	await process_frame
	var btn: Button = null
	for b in m.ui_pole_row.get_children():
		if b is Button and b.text.begins_with(">"):
			btn = b
	ok(m.ui_pole_row.is_visible_in_tree() and btn != null, "the right panel shows the 'points' row for a hand")
	var u0: int = m.undo.size()
	var a1 := pole_deg(B, "hand_r", Vector3.UP)
	var p2: Vector3 = B.P["hand_r"]
	btn.pressed.emit()
	ok(m.undo.size() == u0 + 1 and absf(wrapf(pole_deg(B, "hand_r", Vector3.UP) - a1, -180, 180)) > 5.0 and ((B.P["hand_r"] - p2) as Vector3).length() < 0.001, "  '>' pressed: the elbow swung %.1f deg, the hand stayed, one undo step" % wrapf(pole_deg(B, "hand_r", Vector3.UP) - a1, -180, 180))
	m.sel = "upperarm_r"
	m._panel()
	await process_frame
	ok(not m.ui_pole_row.is_visible_in_tree(), "  and it is hidden for the upper arm (no end to hold)")
	# Ctrl+drag on the hand in the view
	m.sel = "hand_r"
	var p3: Vector3 = B.P["hand_r"]
	var a3 := pole_deg(B, "hand_r", Vector3.UP)
	m._drag_joint(Vector2(30, 0), false, true, false)
	ok(((B.P["hand_r"] - p3) as Vector3).length() < 0.001 and absf(wrapf(pole_deg(B, "hand_r", Vector3.UP) - a3, -180, 180)) > 5.0, "Ctrl+drag the hand 30 px: the elbow swung %.1f deg, the hand stayed (%.3f mm)" % [wrapf(pole_deg(B, "hand_r", Vector3.UP) - a3, -180, 180), ((B.P["hand_r"] - p3) as Vector3).length() * 1000.0])
	print("POLE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
