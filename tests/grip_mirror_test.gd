## godot --headless --path . -s tests/grip_mirror_test.gd     (GATES JJ2, UPGRADES #59)
## THE WEAPON'S GRIP THROUGH A MIRROR: a metal bat locked in the right hand, moved and turned INSIDE the hand by the
## panel's sliders (the bat selected: the hip-row sliders are its position in the hand, bend / side / twist its turn).
## Mirror pose: the left hand holds it, the mirrored offset, the knob and the tip exactly the mirror image (x -> -x,
## 1 mm). Mirrored twice: the offset and the points back (1 mm). A save and a load keep the offset (the file holds
## 0.1 mm). PASTE CARRIES THE WEAPON (round 32, GATES MM1; Nick 10-16 overrides round 10's Q1): Ctrl+C, paste mirrored
## puts the bat in the other hand, the mirror image (1 mm), one undo step, Ctrl+Z puts it back; Ctrl+V after it returns
## it to the copied hand and grip; a paste to one part, or a copied pose with no weapon, leaves it. Arms posed asymmetric first, so a mirror
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
	# PASTE CARRIES THE WEAPON (round 32, MM1; Nick 10-16 overrides round 10's Q1): mirrored = into the other hand, the
	# knob and tip the mirror image (as Mirror pose); plain = back in the copied hand and grip; a part = left alone;
	# a pose with no weapon = left alone; Ctrl+Z puts hand and grip back
	m._copy_pose()
	var pc := pts()
	var hand_p: String = m.B.wep_hand
	var lp_p: Vector3 = m.B.wep_lpos
	var u0: int = m.undo.size()
	m._paste_pose("mirrored")
	await idle()
	var pm := pts()
	var mir_ok: bool = m.B.wep_hand == m.B.twin(hand_p) and near(pm[0], flip(pc[0])) and near(pm[1], flip(pc[1])) and _on_hand(m.B.wep_hand)
	ok(mir_ok and m.undo.size() == u0 + 1, "5 Ctrl+C in %s, paste mirrored: in %s, knob %.4f / tip %.4f m off the mirror image, on that hand %s; +%d undo" % [hand_p, m.B.wep_hand, pm[0].distance_to(flip(pc[0])), pm[1].distance_to(flip(pc[1])), _on_hand(m.B.wep_hand), m.undo.size() - u0])
	m._undo()
	await idle()
	var pu := pts()
	ok(m.B.wep_hand == hand_p and near(m.B.wep_lpos, lp_p, 1e-6) and near(pu[0], pc[0]), "6 Ctrl+Z: back in %s, the grip the same, the knob %.4f m off" % [m.B.wep_hand, pu[0].distance_to(pc[0])])
	m._paste_pose("mirrored")
	m._paste_pose("")
	await idle()
	var pp := pts()
	ok(m.B.wep_hand == hand_p and near(m.B.wep_lpos, lp_p, 1e-6) and near(pp[0], pc[0]) and near(pp[1], pc[1]), "7 then Ctrl+V: back in %s with the copied grip, knob %.4f / tip %.4f m off" % [m.B.wep_hand, pp[0].distance_to(pc[0]), pp[1].distance_to(pc[1])])
	m._paste_pose("mirrored")
	await idle()
	var before: String = m.B.wep_hand
	var lp_b: Vector3 = m.B.wep_lpos
	m.sel = "upperarm_r"
	m._paste_pose("part")
	var nobody := {"ang": m.B.ang.duplicate(), "offset": m.B.offset}
	m.pose_clip = nobody
	m._paste_pose("mirrored")
	await idle()
	ok(m.B.wep_hand == before and near(m.B.wep_lpos, lp_b, 1e-6), "8 'Paste to this part' and a pose copied with no weapon leave it in %s, the grip the same (%s)" % [m.B.wep_hand, near(m.B.wep_lpos, lp_b, 1e-6)])
	print("GRIP MIRROR: %d failed" % fails)
	quit(1 if fails > 0 else 0)
