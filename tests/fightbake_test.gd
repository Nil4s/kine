## godot --path . -s tests/fightbake_test.gd     (window suite: fightbake:w)   L76: the fight maths of L72 / L74 BAKED onto a real two-body clip.
## Bars, written BEFORE the implementation (scripts/fight_bake.gd, fight_bake_serve.gd, fight_panel.gd; hero = scenes/combo3.json, partner = the stand pose held, 0.25 m past the fist at contact):
##  a. CONTACTS: the two-body clip lists exactly 1 contact, at the frame ImpactAlign.scene_check gives, with a partner, a region and an impulse > 0.
##     PLANTED: a hero who never strikes, a hero with no partner, a partner 5 m away each list 0 contacts (no bake offered; the bake answers an error and changes nothing).
##  b. REACTION (liver, chin, solar plexus, thigh; the region forced by tag): after bake_reaction
##     b1 the partner's pose at t_arrive = contact + max(drop_delay, MIN_RISE) is the pose at contact + region_react's deltas, every joint within 0.5 deg
##        (for liver / chin / solar plexus t_arrive == contact + drop_delay exactly);
##     b2 every partner frame at or before the contact differs by exactly 0.0 (all joints, every 1/30 s from 0);
##     b3 every joint the bake keyed is inside data/body_limits.json;
##     b4 control: a bar-checker that nudges one expected joint by 1.0 deg REJECTS the baked clip.
##  c. UNDO (in the app, agent tool bake_reaction on the opened file): exactly 1 undo step, one undo gives the scene file back byte for byte, a redo-free second undo does not exist.
##  d. FIX IMPACT: a clip whose wrist is bent 28 deg is flagged WRIST BENT by impact_align; after fix_impact (app tool) impact_align gives NO flags at the new contact;
##     joints inside body_limits; frames before the first card the fix touched differ by exactly 0.0; 1 undo step; one undo restores the file byte for byte.
##     PLANTED: the clean clip (wrist <= 15 deg): fix_impact answers an error and adds no undo step.
##  e. MOMENTUM (hero stand and partner stand, both held; a charge at 2.5 m/s, 80 kg into 60 kg, forced masses): both roots are keyed; the partner's and the hero's root
##     displacement at contact + 0.8 s equals the body_collide keys (partner: keys_b minus the no-hit keys, hero: keys_a minus the no-hit keys, in each body's own frame) within 1 mm;
##     momentum before and after within 5 %; frames at or before the contact differ by exactly 0.0; the lighter body moves further.
##  f. TOOLS: bake_reaction, fix_impact, bake_momentum are in AgentTools.MCP_EXTRA and in poser_mcp.py; the FIGHT panel (m.fight_on) lists the contact frame and has Bake reaction
##     and Fix impact buttons; pressing Bake reaction on the panel makes the same 1 undo step; with the planted no-contact clip the panel offers no button.
extends SceneTree

var fails := 0
const FPS := 60   # FrameData.FPS: combo3 only clears the 8 m/s active bar when sampled at 60


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func control(claim: bool, what: String) -> void:
	print(("ok   control caught: " if not claim else "FAIL control NOT caught: ") + what)
	if claim:
		fails += 1


func stand_pose() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json"))


func stand_body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.from_dict(stand_pose())
	b.ground()
	return b


func load_scene(p: String) -> Scene:
	var s := Scene.new()
	s.from_dict(JSON.parse_string(FileAccess.get_file_as_string(p)))
	return s


## combo3 holds a bat in every card (its striker is "weapon"); the fight bake judges the hand / foot, so the fixture is combo3 with the hands empty
func combo_bare() -> Scene:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json"))
	for c in d["cards"]:
		c["pose"]["weapon"] = {}
		c["pose"].erase("weapon2")
	var s := Scene.new()
	s.from_dict(d)
	return s


func held(hold: float) -> Scene:
	var s := Scene.new()
	s.add("stand", stand_pose())
	s.cards[0]["hold"] = hold
	return s


func with_partner(hero: Scene, px: float, pz: float, hold := 4.0) -> Scene:
	var s := hero.clone()
	s.actors = [{"name": "B", "xf": {"pos": [px, pz], "yaw": 180.0}, "scene": held(hold)}]
	return s


## the hero's fist at the contact frame of a hero-only scene (the test's own routine: the maths it is compared with are ImpactAlign.scene_check's)
func fist_at_contact(hero: Scene) -> Array:
	var r := ImpactAlign.scene_check(hero, FPS)
	print("     scene_check: ", r.get("frame"), " ", r.get("striker"))
	if int(r.get("frame", -1)) < 0:
		print("FIGHTBAKE FAIL fixture has no strike")
		quit(1)
		return [r, Vector3.ZERO]
	var b := stand_body()
	hero.apply(b, float(r["frame"]) / float(FPS))
	return [r, b.E[r["striker"]]]


func save(s: Scene, name: String) -> String:
	DirAccess.make_dir_recursive_absolute("user://fightbake")
	var p := ProjectSettings.globalize_path("user://fightbake/" + name + ".json")
	var fh := FileAccess.open(p, FileAccess.WRITE)
	fh.store_string(JSON.stringify(s.to_dict(stand_body(), false)))
	fh.close()
	return p


func mx(v: Vector3) -> float:
	var a := v.abs()
	return maxf(a.x, maxf(a.y, a.z))


func ang_at(s: Scene, t: float) -> Dictionary:
	return s.sample(t)["ang"]


## max over joints of the angle difference between two scenes at time t
func pose_diff(a: Scene, b: Scene, t: float) -> float:
	var x := ang_at(a, t)
	var y := ang_at(b, t)
	var worst := 0.0
	for j in x:
		worst = maxf(worst, mx((x[j] as Vector3) - (y.get(j, Vector3.ZERO) as Vector3)))
	return worst


func before_diff(a: Scene, b: Scene, t_end: float) -> float:
	var worst := 0.0
	var n := int(floor(t_end * FPS + 1e-6))
	for f in n + 1:
		worst = maxf(worst, pose_diff(a, b, float(f) / FPS))
	return maxf(worst, pose_diff(a, b, t_end))


func delta_err(orig: Scene, baked: Scene, t_contact: float, t_arrive: float, want: Dictionary) -> float:
	var o := ang_at(orig, t_contact)
	var n := ang_at(baked, t_arrive)
	var worst := 0.0
	for j in want:
		var d: Vector3 = (n[j] as Vector3) - (o[j] as Vector3)
		worst = maxf(worst, mx(d - (want[j] as Vector3)))
	return worst


func inside_limits(s: Scene, joints: Array) -> int:
	var lim: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/body_limits.json"))
	var out := 0
	for c in s.cards:
		for j in joints:
			var key := String(j).replace("_l", "_r") if String(j).ends_with("_l") else String(j)
			var L: Dictionary = lim.get(key, {})
			if L.is_empty() or not (c["pose"]["joints"] as Dictionary).has(j):
				continue
			var x: Dictionary = c["pose"]["joints"][j]
			if float(x["bend"]) < L["bend"][0] - 0.01 or float(x["bend"]) > L["bend"][1] + 0.01 or float(x["side"]) < L["side"][0] - 0.01 or float(x["side"]) > L["side"][1] + 0.01 or float(x["twist"]) < L["twist"][0] - 0.01 or float(x["twist"]) > L["twist"][1] + 0.01:
				out += 1
	return out


func _init() -> void:
	create_timer(240.0).timeout.connect(func():
		print("FIGHTBAKE WATCHDOG: the test did not finish")
		quit(2))
	# ---- the fixture: combo3, the partner 0.25 m past the fist
	var hero := combo_bare()
	var fc := fist_at_contact(hero)
	var r0: Dictionary = fc[0]
	var fist: Vector3 = fc[1]
	var f0 := int(r0["frame"])
	var T0 := float(f0) / FPS
	print("     combo3: contact frame %d (%.3f s) by %s, fist at %s" % [f0, T0, r0["striker"], fist])
	var S2 := with_partner(hero, fist.x, fist.z + 0.25)

	# ---- a. contacts
	var cs := FightBake.contacts(S2, FPS)
	ok(cs.size() == 1 and int(cs[0]["frame"]) == f0 and int(cs[0]["partner"]) == 0 and String(cs[0]["region"]) != "" and float(cs[0]["impulse"]) > 0.0, "a the two-body clip lists 1 contact at frame %d: %s" % [f0, str(cs[0]) if cs.size() > 0 else "none"])
	if cs.is_empty():
		print("FIGHTBAKE TEST FAIL: no contact listed, the later bars cannot run")
		quit(1)
		return
	var idle := held(2.0)
	idle.add("stand2", stand_pose())
	idle.cards[1]["hold"] = 1.0
	ok(FightBake.contacts(with_partner(idle, 0.0, 0.5), FPS).is_empty(), "a1 PLANTED: a hero who never strikes lists 0 contacts")
	ok(FightBake.contacts(hero, FPS).is_empty(), "a2 PLANTED: no partner lists 0 contacts")
	ok(FightBake.contacts(with_partner(hero, fist.x, fist.z + 5.0), FPS).is_empty(), "a3 PLANTED: a partner 5 m away lists 0 contacts")
	var cm := with_partner(idle, 0.0, 0.5)
	var h_cm := JSON.stringify(cm.to_dict(stand_body(), false)).hash()
	var rr_none := FightBake.bake_reaction(cm, {"t": 0.5, "partner": 0, "frame": 15}, {})
	ok(not bool(rr_none.get("ok", true)) and JSON.stringify(cm.to_dict(stand_body(), false)).hash() == h_cm, "a4 PLANTED: bake_reaction on a clip with no contact answers an error and changes nothing")

	# ---- b. reaction, 4 regions forced by tag
	var forced := [
		{"name": "liver", "tag": "obliques_r", "y": 0.5, "impulse": 70.0},
		{"name": "chin", "tag": "face", "y": 0.9, "head_y": 0.2, "impulse": 70.0},
		{"name": "solar_plexus", "tag": "abdominals", "y": 0.7, "impulse": 70.0},
		{"name": "thigh", "tag": "quadriceps_l", "y": 0.3, "impulse": 70.0},
	]
	for fz in forced:
		var Sb := S2.clone()
		var orig := (S2.actors[0]["scene"] as Scene).clone()
		var cl := FightBake.contacts(Sb, FPS)
		if cl.is_empty():
			ok(false, "b %s: no contact to bake onto" % fz["name"])
			continue
		var c: Dictionary = cl[0]
		var rr := FightBake.bake_reaction(Sb, c, fz)
		var baked: Scene = Sb.actors[0]["scene"]
		if not bool(rr.get("ok", false)):
			ok(false, "b %s: bake failed %s" % [fz["name"], str(rr)])
			continue
		var want := RegionReact.react(String(fz["name"]), float(fz["impulse"]), String(rr["side"]))
		var wd: Dictionary = want["joints"]
		var Tc := float(rr["t_contact"])
		var Ta := float(rr["t_arrive"])
		var delay := float(want["drop_delay_s"])
		var err := delta_err(orig, baked, Tc, Ta, wd)
		ok(String(rr["region"]) == fz["name"] and err <= 0.5, "b1 %s: region picked, partner pose at contact+%.2f s = contact pose + region_react deltas within 0.5 deg (worst %.4f deg, %d joints)" % [fz["name"], Ta - Tc, err, wd.size()])
		if delay >= FightBake.MIN_RISE:
			ok(absf((Ta - Tc) - delay) < 1e-6, "b1b %s: the pose lands at contact + drop_delay (%.3f s)" % [fz["name"], delay])
		var pre := before_diff(orig, baked, Tc)
		ok(pre == 0.0, "b2 %s: frames at or before the contact unchanged (max diff %.8f deg)" % [fz["name"], pre])
		var outside := inside_limits(baked, wd.keys())
		ok(outside == 0, "b3 %s: %d keyed joint values outside body_limits" % [fz["name"], outside])
		if fz["name"] == "liver":
			var bad := wd.duplicate()
			var k0: String = wd.keys()[0]
			bad[k0] = (bad[k0] as Vector3) + Vector3(1.0, 0, 0)
			control(delta_err(orig, baked, Tc, Ta, bad) <= 0.5, "b4 a checker with one expected joint nudged 1 deg accepts the baked clip")

	# ---- c. undo in the app, reaction
	var path := save(S2, "pair")
	var path_idle := save(with_partner(idle, 0.0, 0.5), "idle")
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var T := AgentTools.new(m)
	var rid := 1
	await T.request(rid, "open", {"path": path})
	var bytes0 := JSON.stringify(m.S.to_dict(m.B, false))
	var u0: int = m.undo.size()
	rid += 1
	var res: Dictionary = await T.request(rid, "bake_reaction", {})
	var bytes1 := JSON.stringify(m.S.to_dict(m.B, false))
	ok(res.has("result") and bytes1 != bytes0 and m.undo.size() == u0 + 1, "c bake_reaction in the app: scene changed, exactly 1 undo step (%d -> %d) %s" % [u0, m.undo.size(), str(res.get("error", ""))])
	m._undo()
	var bytes2 := JSON.stringify(m.S.to_dict(m.B, false))
	ok(bytes2 == bytes0 and m.undo.size() == u0, "c1 one undo restores the clip byte for byte (%d bytes)" % bytes0.length())

	# ---- f. panel
	m.fight_on = true
	m._refresh()
	for i in 3:
		await process_frame
	var P: FightPanel = m.fight_panel
	ok(P != null and P.visible and P.rows().size() == 1 and int(P.rows()[0]["frame"]) == f0 and P.has_button("bake", 0) and P.has_button("fix", 0), "f the FIGHT panel lists the contact frame %d with Bake reaction / Fix impact" % f0)
	var u1: int = m.undo.size()
	if P != null:
		P.press("bake", 0)
	for i in 3:
		await process_frame
	ok(m.undo.size() == u1 + 1 and JSON.stringify(m.S.to_dict(m.B, false)) != bytes0, "f1 pressing Bake reaction on the panel: 1 undo step")
	m._undo()
	ok(JSON.stringify(m.S.to_dict(m.B, false)) == bytes0, "f2 and its undo restores the clip byte for byte")
	await T.request(rid + 1, "open", {"path": path_idle})
	m._refresh()
	for i in 3:
		await process_frame
	ok(m.fight_panel != null and m.fight_panel.rows().is_empty() and not m.fight_panel.has_button("bake", 0), "f3 PLANTED: the no-contact clip offers no Bake button")
	var mcp := FileAccess.get_file_as_string("res://tools/mcp/poser_mcp.py")
	var all3 := true
	for tn in ["bake_reaction", "fix_impact", "bake_momentum"]:
		if not (tn in AgentTools.MCP_EXTRA) or not mcp.contains("\"" + tn + "\""):
			all3 = false
	ok(all3, "f4 bake_reaction, fix_impact, bake_momentum are in MCP_EXTRA and poser_mcp.py")

	# ---- d. fix impact
	var planted := combo_bare()
	var side := String(r0["striker"]).right(1)
	for card in planted.cards:
		var np: Dictionary = (card["pose"] as Dictionary).duplicate(true)
		np["joints"]["hand_" + side]["bend"] = 28.0
		np["joints"]["hand_" + side]["side"] = 0.0
		card["pose"] = np
	var rb := ImpactAlign.scene_check(planted, FPS)
	var rules := []
	for f in rb["flags"]:
		rules.append(f["rule"])
	ok("WRIST BENT" in rules, "d0 PLANTED bent wrist (28 deg) is flagged by impact_align: %s at frame %d" % [str(rules), int(rb["frame"])])
	var planted2 := with_partner(planted, fist.x, fist.z + 0.25)
	var pp := save(planted2, "bent")
	await T.request(rid + 2, "open", {"path": pp})
	var fb0 := JSON.stringify(m.S.to_dict(m.B, false))
	var fu0: int = m.undo.size()
	var before_scene: Scene = m.S.clone()
	var fres: Dictionary = await T.request(rid + 3, "fix_impact", {})
	var fb1 := JSON.stringify(m.S.to_dict(m.B, false))
	ok(fres.has("result") and fb1 != fb0 and m.undo.size() == fu0 + 1, "d1 fix_impact: scene changed, 1 undo step %s" % str(fres.get("error", "")))
	var rc := ImpactAlign.scene_check(m.S, FPS)
	ok(bool(rc.get("ok", false)) and (rc["flags"] as Array).is_empty(), "d2 the fixed impact re-checks clean (frame %d, flags %d)" % [int(rc.get("frame", -1)), (rc.get("flags", []) as Array).size()])
	var first_t := 0.0
	if fres.has("result"):
		first_t = float(fres["result"].get("first_changed_t", 0.0))
	var pre_fix := 0.0
	var nfix := int(floor(first_t * FPS - 1e-6))
	for f in range(0, nfix + 1):
		pre_fix = maxf(pre_fix, pose_diff(before_scene, m.S, float(f) / FPS))
	ok(pre_fix == 0.0, "d3 frames before the first touched card (t < %.3f s) differ by exactly %.8f deg" % [first_t, pre_fix])
	ok(inside_limits(m.S, ["hand_" + side, "calf_" + side, "lowerarm_" + side]) == 0, "d4 fixed joints inside body_limits")
	m._undo()
	ok(JSON.stringify(m.S.to_dict(m.B, false)) == fb0 and m.undo.size() == fu0, "d5 one undo restores the clip byte for byte")
	var clean := with_partner(combo_bare(), fist.x, fist.z + 0.25)
	await T.request(rid + 4, "open", {"path": save(clean, "clean")})
	var cu0: int = m.undo.size()
	var cres: Dictionary = await T.request(rid + 5, "fix_impact", {})
	ok(cres.has("error") and m.undo.size() == cu0, "d6 PLANTED: the clean clip has nothing to fix: error and no undo step (%s)" % str(cres.get("error", "")))

	# ---- e. momentum
	var Sm := with_partner(held(4.0), 0.0, 1.0)
	var orig_h: Scene = Sm.clone()
	var orig_p: Scene = (Sm.actors[0]["scene"] as Scene).clone()
	var mc := {"t": 0.5, "partner": 0, "frame": 15}
	var mr := FightBake.bake_momentum(Sm, mc, {"v_a": Vector3(0, 0, 2.5), "m_a": 80.0, "m_b": 60.0})
	if not bool(mr.get("ok", false)):
		ok(false, "e bake_momentum failed %s" % str(mr))
	else:
		var xf: Transform3D = Constraints.actor_xf(Sm.actors[0]["xf"])
		var col := BodyCollide.charge(80.0, Vector3(0, 0, 2.5), 60.0, Vector3.ZERO, "male", 0.1)
		var k0b: Array = BodyCollide._keys(Vector3.ZERO)
		var k0a: Array = BodyCollide._keys(Vector3(0, 0, 2.5))
		var want_b: Vector3 = xf.basis.inverse() * ((col["keys_b"][4]["pos"] as Vector3) - (k0b[4]["pos"] as Vector3))
		var want_a: Vector3 = (col["keys_a"][4]["pos"] as Vector3) - (k0a[4]["pos"] as Vector3)
		var tend := 0.5 + 0.8
		var got_b: Vector3 = (Sm.actors[0]["scene"] as Scene).sample(tend)["offset"] - (orig_p.sample(tend)["offset"] as Vector3)
		var got_a: Vector3 = Sm.sample(tend)["offset"] - (orig_h.sample(tend)["offset"] as Vector3)
		ok((got_b - want_b).length() <= 0.001 and want_b.length() > 0.01, "e1 partner root displacement at contact+0.8 s = body_collide keys within 1 mm (got %s want %s)" % [got_b, want_b])
		ok((got_a - want_a).length() <= 0.001 and want_a.length() > 0.01, "e2 hero root displacement at contact+0.8 s = body_collide keys within 1 mm (got %s want %s)" % [got_a, want_a])
		ok(absf(float(col["p_after"]) - float(col["p_before"])) / float(col["p_before"]) < 0.05 and absf(float(mr["p_after"]) - float(mr["p_before"])) / float(mr["p_before"]) < 0.05, "e3 momentum conserved within 5 %% (%.1f -> %.1f)" % [mr["p_before"], mr["p_after"]])
		ok(before_diff(orig_p, Sm.actors[0]["scene"], 0.5) == 0.0 and before_diff(orig_h, Sm, 0.5) == 0.0 and (Sm.actors[0]["scene"] as Scene).sample(0.5)["offset"] == orig_p.sample(0.5)["offset"], "e4 frames at or before the contact unchanged on both bodies (0.0)")
		ok(got_b.length() > got_a.length(), "e5 the lighter body moves further (%.3f vs %.3f m)" % [got_b.length(), got_a.length()])

	print("FIGHTBAKE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
