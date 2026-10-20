## godot --path . -s tests/i40_test.gd     (ROADMAP I40: parry rebound, scripts/weapon_rebound.gd + weapon_rebound_ui.gd; needs a window)
## Two fighters, each holding a metal bat in the right hand, built in memory (no file is written). Fighter 1 (the hero, facing +z) swings its bat
## across its body (axis along x) from z = 0.20 m to z = 0.745 m on an ease-in card; fighter 2 (1.0 m in front, facing it) holds its bat
## upright (axis along y) with the centre at z = 0.75 m. The axes never cross (no pass-through), the surfaces touch 0.066 m before the end of
## the swing: one PARRY (fighter 2 is the guard). Bars, written before measuring:
##  (1) the scan finds exactly one contact, fighter 1 striking at > 1 m/s closing speed
##  (2) NEWTON'S LAW: after the impulse the contact points separate at e x the closing speed (e = 0.5), to 1e-6 relative
##  (3) LIGHT ON LIGHT (both 0.9 kg bats): both weapons turn (> 0.5 rad/s) and are deflected "a little": the largest weapon turn read back from
##      the IK-played scene is between 1 and 30 deg for each, AGREES with the analytic angle to 35 %, and the weapons turn AWAY from each
##      other (fighter 1's tip moves against the contact normal, fighter 2's along it)
##  (4) the inertias are the ones of I30 and the equal levers make |d_omega_1| / |d_omega_2| = I_2 / I_1 (= 1 here) to 2 %
##  (5) HEAVY ON LIGHT (fighter 1's weapon a 5 kg sledge profile): |d_omega_2| / |d_omega_1| = I_1 / I_2 to 2 % (the inertias' ratio), the LIGHT
##      weapon is deflected more than in (3) (measured deflection larger), the heavy one less
##  (6) HEAVY ON HEAVY (both 5 kg): the swing is stopped dead: flagged (>= half of its angular speed taken AND the wrist torque over I30's
##      WRIST_MAX); the light-on-light parry is NOT flagged
##  (7) the keys: the deflection is gone 0.1 s after the window (tips back within 2 mm of the authored motion) and starts from nothing (within 2 mm
##      just before the impact); the analysis changed no scene (cards and IK byte-identical)
##  (8) in the app: the panel lists the contact with a wrist bar per fighter inside the window, drawn arcs under the stage; PLACEMENT: the arcs'
##      points project inside the window and every deflected arc starts on its weapon's real tip; Show and Preview change nothing; Accept is ONE
##      undo step (both fighters' IK keys), Ctrl+Z restores both scenes byte for byte
extends SceneTree

const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/i40.png"
const SLEDGE := {"mass": 5.0, "len": 0.84, "com": 0.85, "k": 0.2}
const D0 := 0.45      # fighter 2's distance (m)
const Y := 1.3        # the bats' height (m)
var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## a pose with the bat in the right hand, its axis along `dir` and its centre at `c` (the fighter's own space)
func pose(c: Vector3, dir: Vector3) -> Dictionary:
	var b := Choreo._body()
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	b.wep_on = true
	b.wep_kind = "metal_bat"
	b.weapon_to_hand("hand_r")
	b.aim_weapon(dir)
	var rot: Quaternion = b.G["hand_r"]
	for it in 6:
		var err := c - b.wep_point(b.wep_len * 0.5)
		LimbIK.solve(b, "hand_r", (b.P["hand_r"] as Vector3) + err, LimbIK.pole_from_pose(b, "hand_r"), rot)
	return b.to_dict()


func scene_of(cards: Array) -> Scene:
	var S := Scene.new()
	S.from_dict({"scene": "i40", "fps": 30, "cards": cards})
	return S


var geo := {}


## the geometry, worked from fighter 2's reachable bat: its centre and axis in the hero's space, the contact normal, and fighter 1's end and start centres
func geometry() -> Dictionary:
	if not geo.is_empty():
		return geo
	var dirl := Vector3(-0.703, 0.586, 0.403)   # a bat axis this arm can hold (found by aim_weapon: 0 deg left)
	var pb := pose(Vector3(-0.1, Y, 0.25), dirl)
	var b := Choreo._body()
	b.from_dict(pb)
	var cb: Vector3 = xf2() * b.wep_point(b.wep_len * 0.5)
	var ab: Vector3 = (xf2().basis * b.wep_axis()).normalized()
	var nn := Vector3.RIGHT.cross(ab).normalized()
	if nn.z < 0.0:
		nn = -nn
	var r2 := 2.0 * float(b.rad["bat_barrel"])
	var end := cb - nn * (r2 - 0.004)
	var bb := Choreo._body()
	bb.from_dict(pb)
	var sb_a: Vector3 = xf2() * bb.wep_point(0.0)
	var sb_b: Vector3 = xf2() * bb.wep_point(bb.wep_len)
	for it in 5:   # the arm cannot hold the bat exactly where asked: move the target along the normal by the gap that is left
		var ba := Choreo._body()
		ba.from_dict(pose(end, Vector3.RIGHT))
		var cp := WeaponClash.closest(ba.wep_point(0.0), ba.wep_point(ba.wep_len), sb_a, sb_b)
		var gap := (cp[0] as Vector3).distance_to(cp[1]) - r2
		end += nn * (gap + 0.004)
	geo = {"pose_b": pb, "cb": cb, "ab": ab, "n": nn, "end": end, "start": end - nn * 0.30}
	print("       geometry: fighter 2 bat centre %s axis %s; normal %s; fighter 1 swings %s -> %s" % [cb, ab, nn, geo["start"], end])
	return geo


func fighter_1() -> Scene:
	var g := geometry()
	return scene_of([{"name": "ready", "pose": pose(g["start"], Vector3.RIGHT), "move": -1.0, "hold": 0.3},
		{"name": "parried", "pose": pose(g["end"], Vector3.RIGHT), "move": 0.2, "hold": 0.8, "ease": "in"}])


func fighter_2() -> Scene:
	return scene_of([{"name": "guard", "pose": geometry()["pose_b"], "move": -1.0, "hold": 1.6}])


func xf2() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, D0))


func fighters(a: Scene, b: Scene) -> Array:
	return [{"name": "hero", "S": a, "xf": Transform3D.IDENTITY}, {"name": "guard", "S": b, "xf": xf2()}]


func state_json(fs: Array) -> String:
	var parts := []
	for f in fs:
		parts.append(JSON.stringify((f["S"] as Scene).cards))
		parts.append(var_to_str((f["S"] as Scene).ik))
	return "|".join(parts)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var fs := fighters(fighter_1(), fighter_2())
	var j0 := state_json(fs)

	# (1) the scan
	var evs := WeaponClash.scan(fs, 30.0)
	for e in evs:
		print("       " + String(e["text"]))
	var res := WeaponRebound.scan(fs)
	ok(res.size() == 1 and evs.size() == 1 and float(res[0]["close"]) > 1.0 and int(res[0]["ev"]["guard"]) == 1,
		"(1) one contact, fighter 2 guards; closing speed %.2f m/s at %.3f s" % [res[0]["close"] if res.size() > 0 else -1.0, res[0]["t"] if res.size() > 0 else -1.0])
	if res.size() != 1:
		print("RESULT i40: FAIL (no contact, %d fails)" % fails)
		quit(1)
		return
	var ll: Dictionary = res[0]
	var A: Dictionary = ll["sides"][0]
	var Bs: Dictionary = ll["sides"][1]
	print("       " + WeaponRebound.describe(ll))
	print("       I_1 %.4f  I_2 %.4f kg m2   d_omega %.2f / %.2f rad/s   torque %.1f / %.1f N m   lost %.2f / %.2f" % [A["i"], Bs["i"],
		(A["domega"] as Vector3).length(), (Bs["domega"] as Vector3).length(), A["torque"], Bs["torque"], A["lost"], Bs["lost"]])

	# (2) Newton's law
	var n: Vector3 = ll["n"]
	var va: Vector3 = (A["v"] as Vector3) + (A["domega"] as Vector3).cross(A["r"])
	var vb: Vector3 = (Bs["v"] as Vector3) + (Bs["domega"] as Vector3).cross(Bs["r"])
	var sep := (vb - va).dot(n)
	var want := WeaponRebound.E_REST * float(ll["close"])
	ok(absf(sep - want) <= 1e-6 * maxf(1.0, want), "(2) separation after the impulse %.4f m/s = e x closing %.4f m/s" % [sep, want])

	# (3) light on light, deflections as the IK plays them
	var pl: Array = WeaponRebound.plan(fs, ll)
	ok(pl.size() == 2 and (pl[0]["keys"] as Array).size() == 15, "(3) both hands are keyed: %d hands, %d keys each" % [pl.size(), (pl[0]["keys"] as Array).size()])
	var m1 := WeaponRebound.measured_angle(fs, pl, 0, "weapon", float(ll["t"]))
	var m2 := WeaponRebound.measured_angle(fs, pl, 1, "weapon", float(ll["t"]))
	print("       light-light: analytic %.1f / %.1f deg, played %.1f / %.1f deg (tips move %.1f / %.1f cm)" % [A["angle"], Bs["angle"], m1[0], m2[0], 100.0 * m1[2], 100.0 * m2[2]])
	ok(float((A["domega"] as Vector3).length()) > 0.5 and float((Bs["domega"] as Vector3).length()) > 0.5, "(3) both weapons turn: %.1f and %.1f rad/s" % [(A["domega"] as Vector3).length(), (Bs["domega"] as Vector3).length()])
	ok(m1[0] >= 1.0 and m1[0] <= 30.0 and m2[0] >= 1.0 and m2[0] <= 30.0, "(3) deflected a little: %.1f and %.1f deg (1 to 30)" % [m1[0], m2[0]])
	ok(absf(m1[0] - float(A["angle"])) <= 0.35 * float(A["angle"]) and absf(m2[0] - float(Bs["angle"])) <= 0.35 * float(Bs["angle"]),
		"(3) the played deflection agrees with the analytic one to 35 %%: %.1f vs %.1f, %.1f vs %.1f deg" % [m1[0], A["angle"], m2[0], Bs["angle"]])
	var arcs := WeaponRebound.arcs(fs, ll, pl)
	var tb: float = m1[1]
	var ia := roundi((tb - (float(ll["t"]) - 0.1)) * WeaponRebound.KEY_HZ)
	var d1 := ((arcs[0]["deflected"][ia] as Vector3) - (arcs[0]["authored"][ia] as Vector3))
	var tb2: float = m2[1]
	var ib := roundi((tb2 - (float(ll["t"]) - 0.1)) * WeaponRebound.KEY_HZ)
	var d2 := ((arcs[1]["deflected"][ib] as Vector3) - (arcs[1]["authored"][ib] as Vector3))
	ok(d1.dot(n) < 0.0 and d2.dot(n) > 0.0, "(3) the weapons turn away from each other: fighter 1's tip moves %.1f cm along the normal, fighter 2's %.1f cm" % [100.0 * d1.dot(n), 100.0 * d2.dot(n)])

	# (4) inertias
	var prof_bat := WeaponTorque.profile("metal_bat")
	ok(absf(float(A["i"]) - float(prof_bat["i_grip"])) < 1e-9 and absf(float(Bs["i"]) - float(prof_bat["i_grip"])) < 1e-9,
		"(4) both inertias are I30's bat about the grip: %.4f kg m2" % prof_bat["i_grip"])
	var lv1 := (A["r"] as Vector3).cross(n).length()
	var lv2 := (Bs["r"] as Vector3).cross(n).length()
	var r4 := (A["domega"] as Vector3).length() / (Bs["domega"] as Vector3).length()
	var w4 := (lv1 / lv2) * float(Bs["i"]) / float(A["i"])
	print("       levers about the grips: %.3f / %.3f m" % [lv1, lv2])
	ok(absf(r4 / w4 - 1.0) <= 0.02, "(4) |d_omega_1| / |d_omega_2| = %.3f = (lever_1 / lever_2) I_2 / I_1 = %.3f" % [r4, w4])

	# (5) heavy on light
	var over := {"0:weapon": SLEDGE}
	var hl := WeaponRebound.scan(fs, over)
	var HA: Dictionary = hl[0]["sides"][0]
	var HB: Dictionary = hl[0]["sides"][1]
	var lh := (HA["r"] as Vector3).cross(hl[0]["n"]).length()
	var ll2 := (HB["r"] as Vector3).cross(hl[0]["n"]).length()
	var r5 := (HB["domega"] as Vector3).length() / (HA["domega"] as Vector3).length()
	var w5 := (ll2 / lh) * float(HA["i"]) / float(HB["i"])
	print("       heavy-light: I_1 %.3f I_2 %.3f kg m2; d_omega %.2f / %.2f rad/s; analytic %.1f / %.1f deg" % [HA["i"], HB["i"], (HA["domega"] as Vector3).length(), (HB["domega"] as Vector3).length(), HA["angle"], HB["angle"]])
	ok(absf(r5 / w5 - 1.0) <= 0.02 and r5 > 0.5 * float(HA["i"]) / float(HB["i"]), "(5) |d_omega_light| / |d_omega_heavy| = %.2f = (lever ratio %.2f) x I_heavy / I_light (%.2f)" % [r5, ll2 / lh, float(HA["i"]) / float(HB["i"])])
	var plh: Array = WeaponRebound.plan(fs, hl[0])
	var h1 := WeaponRebound.measured_angle(fs, plh, 0, "weapon", float(hl[0]["t"]))
	var h2 := WeaponRebound.measured_angle(fs, plh, 1, "weapon", float(hl[0]["t"]))
	print("       heavy-light played: %.1f / %.1f deg (light-light %.1f / %.1f)" % [h1[0], h2[0], m1[0], m2[0]])
	ok(h2[0] > m2[0] and h1[0] < m1[0] and h2[0] > h1[0], "(5) the light weapon is deflected more than against a light one (%.1f > %.1f deg), the heavy one less (%.1f < %.1f deg)" % [h2[0], m2[0], h1[0], m1[0]])

	# (6) stopped dead
	var hh := WeaponRebound.scan(fs, {"0:weapon": SLEDGE, "1:weapon": SLEDGE})
	var DA: Dictionary = hh[0]["sides"][0]
	print("       heavy-heavy: omega %.1f rad/s, d_omega %.1f rad/s, lost %.2f, wrist %.0f N m (max %.0f)" % [(DA["omega"] as Vector3).length(), (DA["domega"] as Vector3).length(), DA["lost"], DA["torque"], WeaponTorque.WRIST_MAX])
	ok(bool(DA["dead"]) and float(DA["lost"]) >= WeaponRebound.STOP_FRAC and float(DA["torque"]) > WeaponTorque.WRIST_MAX,
		"(6) a 5 kg swing parried by a 5 kg guard is stopped dead: %.0f %% of its speed, wrist %.0f N m > %.0f" % [100.0 * float(DA["lost"]), DA["torque"], WeaponTorque.WRIST_MAX])
	ok(not bool(A["dead"]) and not bool(Bs["dead"]), "(6) light on light is not flagged (wrist %.1f and %.1f N m)" % [A["torque"], Bs["torque"]])

	# (7) the keys
	var t0: float = ll["t"]
	var after := WeaponRebound.with_plan(fs, pl)
	var Ba := Choreo._body()
	var Bb := Choreo._body()
	var worst_pre := 0.0
	var worst_post := 0.0
	var peak := 0.0
	for k in 2:
		for q in range(-12, 40):
			var tt: float = t0 + q / 60.0
			(fs[k]["S"] as Scene).apply(Ba, tt)
			(after[k]["S"] as Scene).apply(Bb, tt)
			var dd := Ba.wep_point(Ba.wep_len).distance_to(Bb.wep_point(Bb.wep_len))
			if tt < t0 - 1.0 / 60.0:
				worst_pre = maxf(worst_pre, dd)
			if tt > t0 + WeaponRebound.WINDOW + 0.1:
				worst_post = maxf(worst_post, dd)
			peak = maxf(peak, dd)
	ok(worst_pre < 0.002 and worst_post < 0.002 and peak > 0.01, "(7) the deflection starts from nothing (%.2f mm before) and is gone 0.1 s after the window (%.2f mm); its peak tip shift is %.1f cm" % [1000.0 * worst_pre, 1000.0 * worst_post, 100.0 * peak])
	ok(state_json(fs) == j0, "(7) the analysis and the plan changed no scene (cards and IK byte-identical)")

	# (8) in the app
	m._load_scene("res://scenes/combo3.json")   # read only
	m._rebuild_cards()
	await idle()
	var hero := fighter_1()
	m.S.cards = hero.cards.duplicate(true)
	m.S.markers = []
	m.S.ik = {}
	m.S.actors.append({"name": "guard", "xf": {"pos": [0.0, D0], "yaw": 180.0}, "scene": fighter_2()})
	m._actors_sync()
	m._rebuild_cards()
	m._refresh()
	await idle()
	m.playhead = 0.25
	m._turn_to(90.0, -6.0, 4.6, Vector3(0, 0.95, 0.8), false)
	m._refresh()
	await idle(2)
	var ui = m.pr_ui
	var scenes := [m.actors_rt[0]["S"], m.actors_rt[1]["S"]]
	var snap := state_json([{"S": scenes[0]}, {"S": scenes[1]}])
	var u0: int = m.undo.size()
	ui.show()
	await idle(2)
	ok(ui.rows.size() == 1 and m.ui_find.visible, "(8) the panel lists the contact (%d rows)" % ui.rows.size())
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	var b1: Control = m.ui_find_list.find_child("wr_bar_1_1", true, false)
	var b2: Control = m.ui_find_list.find_child("wr_bar_1_2", true, false)
	var inside: bool = b1 != null and b2 != null and Rect2(Vector2.ZERO, vp).encloses(b1.get_global_rect()) and Rect2(Vector2.ZERO, vp).encloses(b2.get_global_rect()) and b1.get_global_rect().size.x > 100.0
	ok(inside, "(8) PLACEMENT: a wrist bar per fighter is drawn inside the window (%s, %s)" % [b1.get_global_rect() if b1 != null else "missing", b2.get_global_rect() if b2 != null else "missing"])
	var arcs_root: Node = m.stage_root.get_node_or_null("rebound_arcs")
	ok(arcs_root != null and arcs_root.get_child_count() >= 2, "(8) the arcs are drawn under the stage (%s)" % [arcs_root.get_child_count() if arcs_root != null else "missing"])
	# placement: every arc point projects inside the 3D view; the deflected arcs start on the weapon tips of the scene
	var all_in := true
	var minp := Vector2(1e9, 1e9)
	var maxp := Vector2(-1e9, -1e9)
	for a in ui.rows[0]["arcs"]:
		for key in ["authored", "deflected"]:
			for p in a[key]:
				var sp: Vector2 = m.cam.unproject_position(m.stage_root.global_transform * (p as Vector3))
				minp = minp.min(sp)
				maxp = maxp.max(sp)
				if not Rect2(Vector2.ZERO, vp).has_point(sp):
					all_in = false
	ok(all_in, "(8) PLACEMENT: all arc points project inside the window (x %.0f-%.0f, y %.0f-%.0f of %.0f x %.0f px)" % [minp.x, maxp.x, minp.y, maxp.y, vp.x, vp.y])
	# PLACEMENT, whole body: both fighters' heads and feet are in the free 3D view (inside the window, outside the panel)
	var panel_r: Rect2 = m.ui_find.get_global_rect()
	var bodies_in := true
	var spots := []
	for k in 2:
		var Bk: Body = m.actors_rt[k]["B"]
		for j in ["head", "foot_r"]:
			var sp: Vector2 = m.cam.unproject_position(m.stage_root.global_transform * ((m.actors_rt[k]["xf"] as Transform3D) * (Bk.P[j] as Vector3)))
			spots.append(sp)
			if not Rect2(Vector2.ZERO, vp).has_point(sp) or panel_r.has_point(sp) or sp.y > vp.y - float(m.bottom_h) - 40.0:
				bodies_in = false
	ok(bodies_in, "(8) PLACEMENT: both fighters (heads and feet) are in the free 3D view, clear of the panel: %s" % [spots])
	var Bt := Choreo._body()
	var start_ok := true
	for si in 2:
		var a: Dictionary = ui.rows[0]["arcs"][si]
		(scenes[si] as Scene).apply(Bt, float(ui.rows[0]["an"]["t"]) - 0.1)
		var tipw: Vector3 = (m.actors_rt[si]["xf"] as Transform3D) * Bt.wep_point(Bt.wep_len)
		if tipw.distance_to(a["deflected"][0]) > 0.002 or tipw.distance_to(a["authored"][0]) > 0.002:
			start_ok = false
	ok(start_ok, "(8) PLACEMENT: both arcs start on their weapon's real tip (within 2 mm)")
	ui.preview(0)
	await idle(3)
	ok(state_json([{"S": scenes[0]}, {"S": scenes[1]}]) == snap and m.undo.size() == u0, "(8) Show and Preview leave both scenes and the undo stack untouched")
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(SHOT.get_base_dir())
	m.get_viewport().get_texture().get_image().save_png(SHOT)
	ui.pv = []
	ui.accept(0)
	await idle(2)
	var changed := state_json([{"S": scenes[0]}, {"S": scenes[1]}]) != snap
	ok(changed and m.undo.size() == u0 + 1 and (scenes[0].ik.get("hand_r", []) as Array).size() == 15 and (scenes[1].ik.get("hand_r", []) as Array).size() == 15,
		"(8) Accept: IK keys on both hands (%d and %d), ONE undo step" % [(scenes[0].ik.get("hand_r", []) as Array).size(), (scenes[1].ik.get("hand_r", []) as Array).size()])
	m._undo()
	await idle(2)
	ok(state_json([{"S": scenes[0]}, {"S": scenes[1]}]) == snap, "(8) Ctrl+Z restores both fighters' scenes byte for byte")

	print("RESULT i40: %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
