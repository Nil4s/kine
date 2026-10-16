## godot --headless --path . -s tests/grip_mirror_test.gd     (GATES JJ2, UPGRADES #59)
## THE WEAPON'S GRIP THROUGH A MIRROR: a metal bat locked in the right hand, moved and turned INSIDE the hand by the
## panel's sliders (the bat selected: the hip-row sliders are its position in the hand, bend / side / twist its turn).
## Mirror pose: the left hand holds it, the mirrored offset, the knob and the tip exactly the mirror image (x -> -x,
## 1 mm). Mirrored twice: the offset and the points back (1 mm). A save and a load keep the offset (the file holds
## 0.1 mm). Ctrl+C then paste mirrored: the bat stays in its hand with its grip (round 10, Q1: a copied pose carries the
## body, not the weapon), on that hand as it moves. Arms posed asymmetric first, so a mirror
## that ignored the weapon could not land on the mirror image by chance.
extends SceneTree

var fails := 0
var m: Node
const OUT := "_wip/zz_grip"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func flip(p: Vector3) -> Vector3:
	return Vector3(-p.x, p.y, p.z)


func pts() -> Array:
	return [m.B.wep_point(0.0), m.B.wep_point(m.B.wep_len)]


## the bat's knob is where the hand's frame and the grip put it (1 mm)
func _on_hand(h: String) -> bool:
	var keep_p := pts()
	m.B.fk()
	return near(pts()[0], keep_p[0]) and near(pts()[1], keep_p[1]) and (m.B.P[h] as Vector3).distance_to(pts()[0]) < 0.3


func near(a: Vector3, b: Vector3, tol := 0.001) -> bool:
	return a.distance_to(b) <= tol


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	m._new_scene()
	m._pick_weapon(1)   # the metal bat, in the right hand
	m.B.ang["upperarm_r"] = Vector3(20, -30, 10)
	m.B.ang["lowerarm_r"] = Vector3(50, 0, 0)
	m.B.ang["upperarm_l"] = Vector3(-10, -60, 0)
	m.B.fk()
	m.sel = "bat_handle"
	m._refresh()
	await idle()
	var hand0: String = m.B.wep_hand
	var lp_before: Vector3 = m.B.wep_lpos
	m.ui_hips[0][0].value += 0.02
	m.ui_hips[1][0].value -= 0.015
	m.ui_hips[2][0].value += 0.01
	m.ui_rows["side"]["slider"].value += 25.0
	m.ui_rows["twist"]["slider"].value -= 40.0
	await idle()
	var lp: Vector3 = m.B.wep_lpos
	var lr: Quaternion = m.B.wep_lrot
	var p0 := pts()
	ok(hand0 == "hand_r" and lp.distance_to(lp_before) > 0.02 and absf(lr.get_angle()) > 0.2, "1 the bat in %s, moved %.3f m and turned %.0f deg inside the hand by the panel's sliders" % [hand0, lp.distance_to(lp_before), rad_to_deg(lr.get_angle())])
	m._tool(0)   # Mirror pose
	await idle()
	var p1 := pts()
	ok(m.B.wep_hand == "hand_l" and near(p1[0], flip(p0[0])) and near(p1[1], flip(p0[1])),
		"2 Mirror pose: in %s; the knob %.4f m and the tip %.4f m from the mirror image of before" % [m.B.wep_hand, p1[0].distance_to(flip(p0[0])), p1[1].distance_to(flip(p0[1]))])
	m._tool(0)
	await idle()
	var p2 := pts()
	ok(m.B.wep_hand == "hand_r" and near(m.B.wep_lpos, lp) and m.B.wep_lrot.is_equal_approx(lr) and near(p2[0], p0[0]) and near(p2[1], p0[1]),
		"3 mirrored twice: %s, the offset back (%.4f m), the turn back %s, the points back (%.4f, %.4f m)" % [m.B.wep_hand, m.B.wep_lpos.distance_to(lp), m.B.wep_lrot.is_equal_approx(lr), p2[0].distance_to(p0[0]), p2[1].distance_to(p0[1])])
	m._card_add()
	m._save_scene_now(OUT)
	m._new_scene()
	m.B.wep_lpos = Vector3.ZERO   # the body keeps its state across scenes: wipe the grip, so only the file can bring it back
	m.B.wep_lrot = Quaternion.IDENTITY
	m.B.fk()
	m._load_scene("res://scenes/%s.json" % OUT)
	await idle()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://scenes/%s.json" % OUT))
	var p3 := pts()
	ok(m.B.wep_hand == "hand_r" and near(m.B.wep_lpos, lp, 0.0002) and near(p3[0], p0[0]) and near(p3[1], p0[1]),
		"4 saved and loaded: in %s, the offset %.5f m off, the points %.4f / %.4f m off" % [m.B.wep_hand, m.B.wep_lpos.distance_to(lp), p3[0].distance_to(p0[0]), p3[1].distance_to(p0[1])])
	# paste mirrored: the round-10 rule (Q1), a copied pose carries the body, not the weapon: it stays in its hand,
	# its grip the same, and goes where that hand goes
	m._copy_pose()
	var hand_p: String = m.B.wep_hand
	var lp_p: Vector3 = m.B.wep_lpos
	var lr_p: Quaternion = m.B.wep_lrot
	var hand_pos0: Vector3 = m.B.P[hand_p]
	m._paste_pose("mirrored")
	await idle()
	var moved_with_hand: float = (m.B.P[hand_p] as Vector3).distance_to(hand_pos0)
	ok(m.B.wep_hand == hand_p and near(m.B.wep_lpos, lp_p, 1e-6) and m.B.wep_lrot.is_equal_approx(lr_p) and moved_with_hand > 0.05 and _on_hand(hand_p),
		"5 Ctrl+C, paste mirrored (the arms swapped: the right hand moved %.3f m): the bat still in %s, its grip the same (%s), and on that hand" % [moved_with_hand, m.B.wep_hand, near(m.B.wep_lpos, lp_p, 1e-6)])
	print("GRIP MIRROR: %d failed" % fails)
	quit(1 if fails > 0 else 0)
