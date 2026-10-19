## godot --path . -s tests/ik_handles_test.gd     (round 50, GATES IK2 + IK3; a window: real mouse events through the viewport)
## IN-VIEW IK HANDLES: a pinned limb shows a cube at its IK target and a sphere at its pole (a dashed line from the elbow
## / knee); dragging them re-solves the limb each mouse move; release keys at the playhead. combo3 is opened read only.
## Bars, written before measuring (GATES IK2 / IK3):
##   1 handles only for limbs pinned at the playhead, each projected within 1 px of its keyed target / pole
##   2 a target drag (10 mouse steps): the wrist within 3 mm of the target at every step, the target within 1 mm of the
##     mouse ray; a foot's target stays on its floor plane (y within 1 mm), the ankle within 3 mm, on the ray within 1 mm
##   3 a pole drag: the elbow within 2 deg of the shoulder-target-pole plane, on the pole's side; it moved > 1 cm
##   4 one undo step per drag, the key at the playhead holds the dragged point; Ctrl+Z x3 = body + IK keys bit for bit
##   5 20 clicks on body parts away from the handles pick the part 20 / 20; a press on the hand's cube takes the handle
##   6 IK3 (the pin wins, Blender's order: constraints, then the IK pass): a pinned foot over a foot plant and a pinned
##     hand over the two-hand grip stay within 1 mm of the pin every frame (unpinned: > 5 cm off it); the weapon hand
##     pinned, the other hand still on its grip (re-gripping it moves it < 1 mm, as unpinned)
## IKH_SHOT=<path.png>: a picture of the pinned arm with its handles is saved there
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func move(p: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func in_view(p: Vector2) -> bool:
	var vs: Vector2 = root.get_visible_rect().size
	return p.x > m.lw() + 4 and p.x < vs.x - m.rw() - 4 and p.y > m.TOP_H + 4 and p.y < vs.y - m.bottom_h - 4


func proj(p: Vector3) -> Vector2:
	return m.cam.unproject_position(p)


func ray_dist(p: Vector3, mp: Vector2) -> float:
	var o: Vector3 = m.cam.project_ray_origin(mp)
	var d: Vector3 = m.cam.project_ray_normal(mp)
	var v := p - o
	return (v - d * v.dot(d)).length()


func plane_off(R: Vector3, T: Vector3, pole: Vector3, E: Vector3) -> Array:
	var ax := (T - R).normalized()
	var n := ax.cross(pole - R).normalized()
	var e := E - R
	var off := rad_to_deg(asin(clampf(absf(n.dot(e.normalized())), 0.0, 1.0)))
	var pe := e - ax * e.dot(ax)
	var pp := (pole - R) - ax * (pole - R).dot(ax)
	return [off, pe.dot(pp) > 0.0]


## a real drag of a handle at p by d in 10 steps; per step [the live target / pole, the mouse, the tip's position]
func drag_handle(p: Vector2, d: Vector2) -> Array:
	var steps := []
	await mouse(p, true)
	for k in 10:
		var q := p + d * (k + 1) / 10.0
		await move(q, d / 10.0)
		var dr: Dictionary = m._ikh_drag
		if not dr.is_empty():
			steps.append({"target": dr["target"], "pole": dr["pole"], "mouse": q, "tip": m.B.P[dr["tip"]], "kind": dr["kind"], "tipn": dr["tip"]})
	await mouse(p + d, false)
	await idle(2)
	return steps


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func card(B: Body, angs: Dictionary) -> Dictionary:
	for j in Body.ORDER:
		B.ang[j] = Vector3.ZERO
	B.offset = Vector3.ZERO
	for j in angs:
		B.ang[j] = B.clamp_ang(j, angs[j])
	B.fk()
	B.apply_grip()
	return B.to_dict()


func frames_of(S: Scene) -> Array:
	var out := []
	var n := int(ceilf(S.length() * S.fps - 1e-6)) + 1
	for f in n:
		out.append(minf(float(f) / S.fps, S.length()))
	return out


## a key that pins `tip` 10 cm closer to its shoulder / hip than it is on B now (always reachable)
func pin_key(B: Body, tip: String, t: float) -> Dictionary:
	var ch := LimbIK.chain(B, tip)
	var P: Vector3 = B.P[tip]
	var tg: Vector3 = P + ((B.P[ch[0]] as Vector3) - P).normalized() * 0.10
	return {"t": t, "target": tg, "pole": LimbIK.pole_from_pose(B, tip), "w": 1.0, "rot": B.G[tip]}


func ik3() -> void:
	# ---- a pinned foot vs a foot plant: card 2 and 3 plant the left foot (where it stood in card 1), the legs move
	var B := body()
	var S := Scene.new()
	S.fps = 24
	S.add("a", card(B, {}))
	S.add("b", card(B, {"spine_01": Vector3(10, 0, -15), "thigh_l": Vector3(25, 0, 0), "calf_l": Vector3(40, 0, 0)}))
	S.add("c", card(B, {"spine_01": Vector3(15, 5, 10), "thigh_l": Vector3(35, 5, 0), "calf_l": Vector3(55, 0, 0)}))
	S.cards[1]["plant"] = ["_l"]
	S.cards[2]["plant"] = ["_l"]
	var run: float = S.times()[1][0]
	var fr := frames_of(S).filter(func(t): return t >= run + 1e-6)
	S.apply(B, 0.0)
	var plant_at: Vector3 = B.P["foot_l"]
	var pk := pin_key(B, "foot_l", 0.0)
	var plant_err := 0.0
	var free_off := INF
	for t in fr:
		S.apply(B, t)
		plant_err = maxf(plant_err, ((B.P["foot_l"] as Vector3) - plant_at).length())
		free_off = minf(free_off, ((B.P["foot_l"] as Vector3) - (pk["target"] as Vector3)).length())
	S.ik = {"foot_l": [pk]}
	var pin_err := 0.0
	for t in fr:
		S.apply(B, t)
		pin_err = maxf(pin_err, ((B.P["foot_l"] as Vector3) - (pk["target"] as Vector3)).length())
	ok(pin_err <= 0.001 and free_off > 0.05, "6 IK3 foot: plant on (alone the ankle holds its plant spot within %.2f mm over %d frames of the run); pinned 10 cm off it the ankle stays within %.4f mm of the PIN every frame (bar 1 mm); without the pin it is >= %.1f cm from the pin (bar > 5 cm)" % [plant_err * 1000.0, fr.size(), pin_err * 1000.0, free_off * 100.0])

	# ---- a pinned hand vs the two-hand grip: a bat in the right hand, the left on its grip, the trunk turns
	var G := body()
	G.weapon_to_hand("hand_r")
	G.grip = true
	var SG := Scene.new()
	SG.fps = 24
	var arms := {"upperarm_r": Vector3(30, -40, 0), "lowerarm_r": Vector3(60, 0, 0), "upperarm_l": Vector3(30, 40, 0), "lowerarm_l": Vector3(60, 0, 0)}
	var a2 := arms.duplicate()
	a2["spine_02"] = Vector3(10, 0, -25)
	a2["spine_03"] = Vector3(5, 5, -15)
	SG.add("hold", card(G, arms))
	SG.add("turn", card(G, a2))
	var gf := frames_of(SG)
	SG.apply(G, 0.0)
	var on_grip := G.wep_on and G.grip
	var hk := pin_key(G, "hand_l", 0.0)
	var rk := pin_key(G, "hand_r", 0.0)
	var free_gap := INF   # unpinned: the left hand from the pin
	var free_regrip := 0.0   # unpinned: how far re-gripping moves the left hand (it is on its grip)
	for t in gf:
		SG.apply(G, t)
		free_gap = minf(free_gap, ((G.P["hand_l"] as Vector3) - (hk["target"] as Vector3)).length())
		var was: Vector3 = G.P["hand_l"]
		G.apply_grip()
		free_regrip = maxf(free_regrip, ((G.P["hand_l"] as Vector3) - was).length())
	SG.ik = {"hand_l": [hk]}
	var g_err := 0.0
	var off_bat := INF
	for t in gf:
		SG.apply(G, t)
		g_err = maxf(g_err, ((G.P["hand_l"] as Vector3) - (hk["target"] as Vector3)).length())
		var was: Vector3 = G.P["hand_l"]
		G.apply_grip()   # where the grip would put it: the pin keeps it away from there
		off_bat = minf(off_bat, ((G.P["hand_l"] as Vector3) - was).length())
	ok(on_grip and g_err <= 0.001 and free_gap > 0.05, "6 IK3 grip hand: two-hand grip on (%s); the left hand pinned 10 cm off the bat stays within %.4f mm of the PIN every frame of %d (bar 1 mm; the grip would move it >= %.1f cm); unpinned it is >= %.1f cm from the pin (bar > 5 cm)" % [on_grip, g_err * 1000.0, gf.size(), off_bat * 100.0, free_gap * 100.0])
	SG.ik = {"hand_r": [rk]}
	var r_err := 0.0
	var regrip := 0.0
	for t in gf:
		SG.apply(G, t)
		r_err = maxf(r_err, ((G.P["hand_r"] as Vector3) - (rk["target"] as Vector3)).length())
		var was: Vector3 = G.P["hand_l"]
		G.apply_grip()
		regrip = maxf(regrip, ((G.P["hand_l"] as Vector3) - was).length())
	ok(r_err <= 0.001 and regrip <= free_regrip + 0.001, "6 IK3 weapon hand pinned: the right hand within %.4f mm of its pin; the left hand follows the bat: re-gripping moves it %.3f mm at most (unpinned scene %.3f mm; bar within 1 mm of that)" % [r_err * 1000.0, regrip * 1000.0, free_regrip * 1000.0])


func _init() -> void:
	ik3()
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.playing = false
	m.playhead = float(m.S.times()[1][1])
	m._ps().apply(m.B, m.playhead)
	m.sel = "head"
	m.hover_part = ""
	m._refresh()
	m._turn_to(25.0, -8.0, 3.2, Vector3(0, 0.75, 0), false)
	await idle(3)
	var none: bool = m._ikh_root != null and LimbIK.LIMBS.all(func(tip): return not (m._ikh_nodes[tip][0] as Node3D).visible)
	ok(none and m.S.ik.is_empty(), "1 no IK keys: no handle drawn")

	# ---- pin the left hand and the right foot
	for tip in ["hand_l", "foot_r"]:
		m.sel = tip
		m._ik_pin()
	m.sel = "head"
	m._refresh()
	await idle(3)
	var t: float = m.playhead
	var worst_px := 0.0
	var vis_ok := true
	for tip in LimbIK.LIMBS:
		var nd: Array = m._ikh_nodes[tip]
		var pinned: bool = tip in ["hand_l", "foot_r"]
		vis_ok = vis_ok and (nd[0] as Node3D).visible == pinned and (nd[1] as Node3D).visible == pinned
		if pinned:
			var k := LimbIK.sample(m.S.ik[tip], t)
			worst_px = maxf(worst_px, proj((nd[0] as Node3D).global_position).distance_to(proj(k["target"])))
			worst_px = maxf(worst_px, proj((nd[1] as Node3D).global_position).distance_to(proj(k["pole"])))
	var lines: int = (m._ikh_line.mesh as ImmediateMesh).get_surface_count()
	ok(vis_ok and worst_px <= 1.0 and lines == 2, "1 pinned hand_l + foot_r: cubes + spheres drawn for those 2 only (%s), at the keyed target / pole within %.4f px (bar 1), %d dashed pole lines" % [vis_ok, worst_px, lines])
	if OS.get_environment("IKH_SHOT") != "":
		m._turn_to(-60.0, -10.0, 2.8, Vector3(0.1, 1.0, 0), false)
		await idle(6)
		root.get_texture().get_image().save_png(OS.get_environment("IKH_SHOT"))
		print("     shot: %s" % OS.get_environment("IKH_SHOT"))
		m._turn_to(25.0, -8.0, 3.2, Vector3(0, 0.75, 0), false)
		await idle(3)

	var X0: Dictionary = m.B.state()
	var I0 := var_to_str(m.S.ik)
	var u0: int = m.undo.size()

	# ---- 2 the hand's target, dragged 45 px toward the shoulder on screen
	var kh := LimbIK.sample(m.S.ik["hand_l"], t)
	var ph := proj(kh["target"])
	var dh := (proj(m.B.P["upperarm_l"]) - ph).normalized() * 45.0
	var st := await drag_handle(ph, dh)
	var w_tip := 0.0
	var w_ray := 0.0
	for s in st:
		w_tip = maxf(w_tip, ((s["tip"] as Vector3) - (s["target"] as Vector3)).length())
		w_ray = maxf(w_ray, ray_dist(s["target"], s["mouse"]))
	var moved_h: float = ((st[-1]["target"] as Vector3) - (kh["target"] as Vector3)).length() if not st.is_empty() else 0.0
	ok(st.size() == 10 and st[0]["kind"] == "target" and w_tip <= 0.003 and w_ray <= 0.001 and moved_h > 0.02,
		"2 hand target drag, %d mouse steps: the wrist within %.4f mm of the target every step (bar 3 mm), the target within %.4f mm of the mouse ray (bar 1 mm); it moved %.1f cm" % [st.size(), w_tip * 1000.0, w_ray * 1000.0, moved_h * 100.0])
	var u1: int = m.undo.size()
	var key_h: Dictionary = {}
	for k in m.S.ik["hand_l"]:
		if absf(float(k["t"]) - t) < LimbIK.SAME_T:
			key_h = k
	var key_ok := not key_h.is_empty() and not st.is_empty() and ((key_h["target"] as Vector3) - (st[-1]["target"] as Vector3)).length() < 1e-6

	# ---- 2 the foot's target, dragged 35 px sideways toward the body's middle
	var kf := LimbIK.sample(m.S.ik["foot_r"], t)
	var pf := proj(kf["target"])
	var df := Vector2(signf(proj(m.B.P["pelvis"]).x - pf.x) * 35.0, 0.0)
	var sf := await drag_handle(pf, df)
	var f_tip := 0.0
	var f_ray := 0.0
	var f_y := 0.0
	for s in sf:
		f_tip = maxf(f_tip, ((s["tip"] as Vector3) - (s["target"] as Vector3)).length())
		f_ray = maxf(f_ray, ray_dist(s["target"], s["mouse"]))
		f_y = maxf(f_y, absf((s["target"] as Vector3).y - (kf["target"] as Vector3).y))
	var moved_f: float = ((sf[-1]["target"] as Vector3) - (kf["target"] as Vector3)).length() if not sf.is_empty() else 0.0
	ok(sf.size() == 10 and f_y <= 0.001 and f_tip <= 0.003 and f_ray <= 0.001 and moved_f > 0.02,
		"2 foot target drag: on its floor plane (y off by %.4f mm, bar 1), the ankle within %.4f mm of it (bar 3), on the mouse ray within %.4f mm (bar 1); it moved %.1f cm" % [f_y * 1000.0, f_tip * 1000.0, f_ray * 1000.0, moved_f * 100.0])
	var u2: int = m.undo.size()

	# ---- 3 the pole, dragged 70 px square to the arm on screen
	var kp := LimbIK.sample(m.S.ik["hand_l"], t)
	var pp := proj(kp["pole"])
	var arm2 := (proj(kp["target"]) - proj(m.B.P["upperarm_l"])).normalized()
	var e0: Vector3 = m.B.P["lowerarm_l"]
	var sp := await drag_handle(pp, Vector2(-arm2.y, arm2.x) * 70.0)
	var po := plane_off(m.B.P["upperarm_l"], kp["target"], sp[-1]["pole"] if not sp.is_empty() else kp["pole"], m.B.P["lowerarm_l"])
	var e_moved: float = ((m.B.P["lowerarm_l"] as Vector3) - e0).length()
	ok(sp.size() == 10 and sp[0]["kind"] == "pole" and po[0] <= 2.0 and po[1] and e_moved > 0.01,
		"3 pole drag: the elbow within %.4f deg of the shoulder-target-pole plane (bar 2), on the pole's side: %s; the elbow moved %.1f cm" % [po[0], po[1], e_moved * 100.0])
	var u3: int = m.undo.size()

	# ---- 4 release: one undo step each, the key, undo back bit for bit
	m._undo()
	m._undo()
	m._undo()
	await idle(2)
	var back: bool = m.B.state() == X0 and var_to_str(m.S.ik) == I0
	ok(u1 == u0 + 1 and u2 == u1 + 1 and u3 == u2 + 1 and key_ok and back,
		"4 release: undo steps %d -> %d -> %d -> %d (one per drag), the hand key at the playhead holds the dragged target: %s; Ctrl+Z x3: body and IK keys bit for bit: %s" % [u0, u1, u2, u3, key_ok, back])

	# ---- 5 a press on the hand's cube takes the handle; 20 clicks on parts away from the handles pick them
	var ph2 := proj(LimbIK.sample(m.S.ik["hand_l"], t)["target"])
	var under: String = m._pick(ph2)
	await mouse(ph2, true)
	var took: bool = m.dragging == "ik_handle"
	await mouse(ph2, false)
	await idle(2)
	var still: bool = m.B.state() == X0 and m.undo.size() == u0
	var targets := []
	for u in [0.5, 0.3, 0.7]:   # each part's middle first, then points a third along it
		for j in Body.ORDER:
			var c: Array = m.B.cap(j)
			var q := proj((c[0] as Vector3).lerp(c[1], u))
			if in_view(q) and m._pick(q) == j and m._ikh_hit(q).is_empty():
				targets.append([j, q])
	var hits := 0
	var miss := []
	var n5 := mini(20, targets.size())
	for i in n5:
		var j: String = targets[i][0]
		var q: Vector2 = targets[i][1]
		m.sel = "head" if j != "head" else "neck_01"
		await mouse(q, true)
		await mouse(q, false)
		await idle(1)
		if m.sel == j:
			hits += 1
		else:
			miss.append("%s->%s" % [j, m.sel])
		while m.undo.size() > u0:
			m._undo()
	ok(took and still and n5 == 20 and hits == 20, "5 a press on the hand's cube (over the %s) started the handle drag: %s, a click without a move left no undo step and the body unchanged: %s; %d of %d clicks on parts away from the handles picked the part (bar 20 of 20) %s" % [under, took, still, hits, n5, miss])

	# ---- handles hide when not pinned
	m.S.ik = {}
	m._refresh()
	var gone: bool = LimbIK.LIMBS.all(func(tip): return not (m._ikh_nodes[tip][0] as Node3D).visible and not (m._ikh_nodes[tip][1] as Node3D).visible)
	ok(gone, "1 the IK keys gone: every handle hidden")
	print("IK HANDLES TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
