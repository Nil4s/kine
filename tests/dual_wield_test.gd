## godot --headless --path . -s tests/dual_wield_test.gd     (GATES NN1, NN2; UPGRADES_200 #155a, #155b)
## DUAL WIELD (Nick 10-16: "weapons like double dagger, so mirrored would help in making the scenes easier"). The
## picker's "Two daggers": a 0.30 m dagger in the right hand (the main weapon) and one in the left (the off-hand
## weapon), both drawn. (1) Their shape and hands. (2) The off-hand blade put through the left thigh is a CONTACT
## (and not with it put away). (3) A two-card scene with the off-hand dagger turned in its hand between the cards:
## saved, loaded, its place on each card back to 0.1 mm, and mid-move it is BETWEEN the cards (the blend reaches it).
## (4) Every scene in scenes/ plays with no off-hand weapon. NN2: (5) Mirror pose: each dagger in the other hand, all
## four points (two knobs, two tips) the mirror images of before (1 mm), one undo step; (6) twice = back (1 mm);
## (7) paste mirrored does the same; (8) Mirror the scene: card 1's daggers in the swapped hands, the points mirrored.
## Arms asymmetric and the off-hand grip turned first, so a mirror that ignored it cannot land right by chance.
extends SceneTree

var fails := 0
var m: Node
const OUT := "_wip/zz_dual"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func flip(p: Vector3) -> Vector3:
	return Vector3(-p.x, p.y, p.z)


## [main knob, main tip, off-hand knob, off-hand tip]
func pts() -> Array:
	var B: Body = m.B
	return [B.wep_point(0.0), B.wep_point(B.wep_len), B.wep2_point(0.0), B.wep2_point(B.wep2_len())]


func worst_flip(a: Array, b: Array) -> float:
	var w := 0.0
	for i in a.size():
		w = maxf(w, (b[i] as Vector3).distance_to(flip(a[i])))
	return w


## degrees between two rotations, both normalized first (a file's quaternion is rounded to 1e-5 a component, so its
## length is 1 +- 1e-5, and acos of a dot product a hair under 1 reads that as 0.2 degrees)
func deg(a: Quaternion, b: Quaternion) -> float:
	return rad_to_deg(2.0 * acos(clampf(absf(a.normalized().dot(b.normalized())), 0.0, 1.0)))


func worst(a: Array, b: Array) -> float:
	var w := 0.0
	for i in a.size():
		w = maxf(w, (b[i] as Vector3).distance_to(a[i]))
	return w


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	m._new_scene()
	var B: Body = m.B
	var row := -1
	for k in m.WEAPONS.size():
		if m.WEAPONS[k][1] == "two_daggers":
			row = k
	m._pick_weapon(row)
	await idle()
	var p := pts()
	var l1 := (p[1] as Vector3).distance_to(p[0])
	var l2 := (p[3] as Vector3).distance_to(p[2])
	ok(B.wep_on and B.wep_kind == "dagger" and B.wep_hand == "hand_r" and B.wep2_on and B.wep2_hand == "hand_l"
		and absf(l1 - 0.30) < 0.001 and absf(l2 - 0.30) < 0.001 and m.d2_blade.visible and m.bat_barrel.visible
		and m.weapon_shown() == row and (B.P["hand_l"] as Vector3).distance_to(p[2]) < 0.2,
		"1 Two daggers: main %s in %s (%.3f m), off-hand in %s (%.3f m), both drawn %s, the picker shows its row %s" % [B.wep_kind, B.wep_hand, l1, B.wep2_hand, l2, m.d2_blade.visible, m.weapon_shown() == row])
	# (2) the off-hand dagger through the left thigh
	var keep := B.state()
	var th: Array = B.cap("thigh_l")
	var mid: Vector3 = ((th[0] as Vector3) + (th[1] as Vector3)) * 0.5
	var g: Quaternion = B.G[B.wep2_hand]
	B.wep2_lpos = g.inverse() * (mid - (B.P[B.wep2_hand] as Vector3))
	var hit: Array = B.contacts().filter(func(c): return (c[0] in Body.WEAPON2 or c[1] in Body.WEAPON2) and (c[0] == "thigh_l" or c[1] == "thigh_l"))
	B.wep2_on = false
	var off_hit: Array = B.contacts().filter(func(c): return c[0] in Body.WEAPON2 or c[1] in Body.WEAPON2)
	B.set_state(keep)
	ok(hit.size() >= 1 and off_hit.is_empty(), "2 the off-hand dagger put through the left thigh: %d contact(s) %s; put away: %d" % [hit.size(), hit.map(func(c): return "%s|%s %.3f" % [c[0], c[1], c[2]]), off_hit.size()])
	# (3) a two-card scene: arms asymmetric, the off-hand dagger turned in its hand between the cards
	B.ang["upperarm_r"] = Vector3(20, -30, 10)
	B.ang["lowerarm_r"] = Vector3(50, 0, 0)
	B.ang["upperarm_l"] = Vector3(-10, -60, 0)
	B.wep2_lrot = (B.wep2_lrot * Quaternion(Vector3.RIGHT, 0.5)).normalized()
	B.fk()
	m._card_add()
	var lr_a: Quaternion = B.wep2_lrot
	var lp_a: Vector3 = B.wep2_lpos
	var c1 := pts()
	B.ang["upperarm_l"] = Vector3(30, -20, 20)
	B.wep2_lrot = (B.wep2_lrot * Quaternion(Vector3.FORWARD, 1.2)).normalized()
	B.fk()
	m._card_add()
	var lr_b: Quaternion = B.wep2_lrot
	m._save_scene_now(OUT)
	m._new_scene()
	m._load_scene("res://scenes/%s.json" % OUT)
	m._rebuild_cards()
	await idle()
	var S: Scene = m.S
	var back_ok: bool = S.cards.size() == 2 and S.cards[0]["pose"].has("weapon2") and S.cards[1]["pose"].has("weapon2")
	var w0 := Body.wep2_flat(S.cards[0]["pose"].get("weapon2", {"hand": "-"}))
	var w1 := Body.wep2_flat(S.cards[min(1, S.cards.size() - 1)]["pose"].get("weapon2", {"hand": "-"}))
	var ts := S.times()
	S.apply(B, (float(ts[1][0]) + float(ts[1][1])) * 0.5)
	var a_mid := deg(B.wep2_lrot, lr_a)
	var b_mid := deg(B.wep2_lrot, lr_b)
	var ab := deg(lr_a, lr_b)
	ok(back_ok and (w0["local_pos"] as Vector3).distance_to(lp_a) < 0.0001 and deg(w0["local_rot"], lr_a) < 0.01
		and deg(w1["local_rot"], lr_b) < 0.01 and B.wep2_on and a_mid > 5.0 and b_mid > 5.0 and a_mid + b_mid < ab + 0.5,
		"3 saved + loaded: card 1 off-hand place %.5f m / %.4f deg, card 2 %.4f deg; mid-move the off-hand grip %.1f deg from card 1, %.1f from card 2 (%.1f apart)" % [(w0["local_pos"] as Vector3).distance_to(lp_a), deg(w0["local_rot"], lr_a), deg(w1["local_rot"], lr_b), a_mid, b_mid, ab])
	# (4) every scene in scenes/: no off-hand weapon appears
	var appeared := []
	var n_sc := 0
	for f in DirAccess.get_files_at("res://scenes"):
		if not f.ends_with(".json"):
			continue
		var S0 := Scene.new()
		S0.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/" + f)))
		n_sc += 1
		for k in 30:
			S0.apply(B, S0.length() * k / 29.0)
			if B.wep2_on:
				appeared.append(f)
				break
	ok(n_sc >= 10 and appeared.is_empty(), "4 %d scenes played (30 frames each): an off-hand weapon appeared in %s" % [n_sc, appeared])
	# NN2 (5) Mirror pose on card 1's pose
	m._timeline_pick(0)
	await idle()
	var before := pts()
	var u0: int = m.undo.size()
	m._tool(0)
	await idle()
	var after := pts()
	ok(B.wep_hand == "hand_l" and B.wep2_hand == "hand_r" and worst_flip(before, after) <= 0.001 and m.undo.size() == u0 + 1,
		"5 Mirror pose: main in %s, off-hand in %s; the four points %.4f m from the mirror images; +%d undo" % [B.wep_hand, B.wep2_hand, worst_flip(before, after), m.undo.size() - u0])
	m._tool(0)
	await idle()
	ok(B.wep_hand == "hand_r" and B.wep2_hand == "hand_l" and worst(before, pts()) <= 0.001, "6 twice: main in %s, off-hand in %s, %.4f m from the start" % [B.wep_hand, B.wep2_hand, worst(before, pts())])
	# (7) paste mirrored
	m._copy_pose()
	u0 = m.undo.size()
	m._paste_pose("mirrored")
	await idle()
	ok(B.wep_hand == "hand_l" and B.wep2_hand == "hand_r" and worst_flip(before, pts()) <= 0.001 and m.undo.size() == u0 + 1,
		"7 Ctrl+C, paste mirrored: main in %s, off-hand in %s, %.4f m from the mirror images; +%d undo" % [B.wep_hand, B.wep2_hand, worst_flip(before, pts()), m.undo.size() - u0])
	m._undo()
	await idle()
	# (8) Mirror the scene
	S.apply(B, float(ts[0][1]))
	var s0 := pts()
	m._mirror_scene()
	await idle()
	var mpath: String = "res://scenes/_wip/%s.json" % m.S.name.trim_prefix("_wip/")
	var S2: Scene = m.S
	S2.apply(B, float(S2.times()[0][1]))
	var s1 := pts()
	ok(m.S.name.ends_with("_mirrored") and B.wep_hand == "hand_l" and B.wep2_hand == "hand_r" and worst_flip(s0, s1) <= 0.001,
		"8 Mirror the scene (%s): card 1 main in %s, off-hand in %s, the points %.4f m from the mirror images" % [m.S.name, B.wep_hand, B.wep2_hand, worst_flip(s0, s1)])
	for f in ["res://scenes/%s.json" % OUT, mpath]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	print("DUAL WIELD: %d failed" % fails)
	quit(1 if fails > 0 else 0)
