extends SceneTree
## godot --path . -s tests/look4d2_test.gd     (LOOK4D2 / L1 AI-COST: the zoomable digest, scripts/build/look4d.gd levels 0-3, delta, character, held; MCP look4d + sweep)
## Bars and planted controls, committed BEFORE the first run. Every bar has a control that must FAIL the check ("CONTROL ..." lines print ok when the check caught the plant).
##  1 TOKENS   level 1 (bytes/4 of its text) is under 442 (a 768 x 432 screenshot) in ALL six scenes; level 0 is under 46 tokens in all six. Each scene's L0, L1, old-D tokens are printed.
##             CONTROL: the old digest D is not under 442 in at least one scene (the bar can fail).
##  2 FIELDS   level 2 equals independent numbers: velocity and acceleration = finite differences of the posed node transforms (3 sf), rotation = the node basis, the engine crank joint
##             = 720 deg / 2 s * t (216 at t0), the engine piston joint = the crank-slider formula (R cos th + sqrt(L2 - R2 sin2 th)) - (R + L), the arm's five joints = N14.state with
##             limits from the design and the distance to the nearest limit, the three nearest gaps = KCad.distance between the placed solids (engine).
##             CONTROLS: an acceleration read with a 10x dt, a crank value 5 deg off, and a gap 5 pct off are each caught.
##  3 HELD     s2_arm at t0: can6 is held_by "gripper" (level 1 and level 2 and level 0 count), cans 1-5 are not held.
##             CONTROLS: can6 moved away until its box gap to every jaw and the gripper body is 5 mm is NOT held; the same scene frozen in time (nothing moves) holds nothing.
##  4 DELTA    in all six scenes the delta from frame n (t0) to frame n+1 (t0 + 1/30), applied to frame n, equals frame n+1 key for key; the frozen null scene's delta is empty; the delta
##             text is smaller than level 1 in the motion scenes (printed). CONTROL: the delta n-1 -> n applied to frame n does NOT give frame n+1 (in at least 3 of the 4 moving scenes).
##  5 SWEEP    McpCad.sweep on CH13's 36 crank angles equals the reduction of the 36 full check_fit results (worst, where, count over 1 mm3, n); its text is under 1024 bytes while the
##             full per-step list is over 10000; a parameter sweep (piston x offset) that DOES overlap equals its full list too (worst > 0, same angle, same count).
##             CONTROL: the same sweep reduced with another threshold gives another count than the list at the first one.
##  6 MCP      through the real MCP server (python tools/mcp/poser_mcp.py --cad, headless): look4d levels 0, 1, 2, 3 and since return the same numbers as the direct GDScript call
##             (Look4D.view_sync on SCN.live of the same assembly, 1e-6 relative), sweep equals the direct sweep, image:true on a headless session says it has no renderer.
##             CONTROL: the direct call at another time is NOT equal to the MCP reply.
##  7 TRACK    level 3 positions equal the posed node centres at each sample (3 sf). CONTROL: the same track read at a shifted start differs.
##  8 CHARACTER s3_walk over 12 samples (0.1 s apart from t0): each foot capsule's "down" = lowest point under 15 mm, and "balanced" = the CoM is inside the support polygon, both
##             recomputed here by a different algorithm (brute-force hull from all point pairs). CONTROL: a CoM moved 1 m away is outside.
##  9 SUPPORT  s2_arm: the stand rests on the table; can6 (held) rests on nothing and is held_by gripper. CONTROL: can6 moved away is held by nothing.
## 10 ERRORS   level 2 without a part, and with an unknown part, return ok false.
const L4 := preload("res://scripts/build/look4d.gd")
const SCN := preload("res://scripts/build/look4d_scenes.gd")
const P13 := preload("res://scripts/build/ch13_parts.gd")
const A14 := preload("res://scripts/build/ch14_arm.gd")
const N14 := preload("res://scripts/build/ch14_anim.gd")
const KCad := preload("res://scripts/kcad.gd")
const DIR := "C:/Temp/claude/look4d2"
const A_TOKENS := 442
var fails := 0
var nok := 0
var ctxs := {}


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1
	nok += 1 if c else 0


func ctl(c: bool, w: String) -> void:
	ok(c, "CONTROL " + w)


func _init() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(DIR)
	await run()
	for k in ctxs:
		L4.close(ctxs[k])
	print("look4d2: %d fail (ok %d)" % [fails, nok])
	quit(1 if fails > 0 else 0)


func run() -> void:
	await bars_tokens()
	await bars_fields()
	await bars_held()
	await bars_delta()
	bars_sweep()
	await bars_track()
	await bars_character()
	await bars_errors()
	await bars_mcp()


func ctx_of(nm: String) -> Dictionary:
	if not ctxs.has(nm):
		var sc := SCN.by_name(nm)
		ctxs[nm] = L4.open(root, sc)
		await L4.frames(3)
	return ctxs[nm]


func close_to(a: float, b: float, rel := 0.0051, ab := 1e-9) -> bool:
	return absf(a - b) <= rel * absf(b) + ab


func arr_close(a: Array, b: Vector3, rel := 0.0051, ab := 1e-9) -> bool:
	for i in 3:
		if not close_to(float(a[i]), b[i], rel, ab):
			return false
	return true


func cen(ctx: Dictionary, id: String, t: float) -> Vector3:
	L4.at(ctx, t)
	var n := ctx["sc"]["nodes"][id] as MeshInstance3D
	return n.global_transform * n.mesh.get_aabb().get_center()


# ------------------------------------------------------------------ 1
func bars_tokens() -> void:
	var worst := 0
	var old_over := 0
	var l0max := 0
	for nm in SCN.SCENES:
		var ctx := await ctx_of(nm)
		var t0 := float(ctx["sc"]["t0"])
		var S := await L4.snap(ctx, t0, true)
		var l0 := L4.tokens(L4.level0(ctx, S))
		var l1 := L4.tokens(L4.level1(ctx, S))
		var old := JSON.stringify(L4.digest(ctx, t0, S["kin"], S["meas"], S["contacts"])).length() / 4
		worst = maxi(worst, l1)
		l0max = maxi(l0max, l0)
		old_over += 1 if old >= A_TOKENS else 0
		ok(l1 < A_TOKENS, "1 %s: level 1 = %d tokens (< %d, the screenshot); level 0 = %d; old D = %d" % [nm, l1, A_TOKENS, l0, old])
	ok(l0max <= 45, "1 level 0 is at most 45 tokens in every scene (max %d)" % l0max)
	ctl(old_over >= 1, "1 the old D is %d tokens or more in %d of 6 scenes (the bar can fail)" % [A_TOKENS, old_over])


# ------------------------------------------------------------------ 2
func bars_fields() -> void:
	var ctx := await ctx_of("s1_engine")
	var sc: Dictionary = ctx["sc"]
	var t0 := float(sc["t0"])
	var S := await L4.snap(ctx, t0, true)
	var bad_v := 0
	var bad_a := 0
	var bad_r := 0
	var wrong_dt := 0
	var dt := L4.DT
	for id in sc["ids"]:
		var l2 := L4.level2(ctx, S, id)
		var fdv := (cen(ctx, id, t0 + dt) - cen(ctx, id, t0 - dt)) / (2.0 * dt)
		var fda := (cen(ctx, id, t0 + dt) - 2.0 * cen(ctx, id, t0) + cen(ctx, id, t0 - dt)) / (dt * dt)
		var fda_bad := (cen(ctx, id, t0 + 10.0 * dt) - 2.0 * cen(ctx, id, t0) + cen(ctx, id, t0 - 10.0 * dt)) / (100.0 * dt * dt)
		if not arr_close(l2["vel"], fdv, 0.0051, 0.0011):
			bad_v += 1
		if not arr_close(l2["acc"], fda, 0.0051, 0.011):
			bad_a += 1
		if arr_close(l2["acc"], fda_bad, 0.0051, 0.011) and fda.length() > 0.5:
			wrong_dt += 1
		L4.at(ctx, t0)
		var e := ((sc["nodes"][id] as MeshInstance3D).global_transform.basis.orthonormalized()).get_euler()
		for i in 3:
			if absf(float(l2["rot_deg"][i]) - rad_to_deg(e[i])) > 0.0051 * absf(rad_to_deg(e[i])) + 0.011:
				bad_r += 1
	ok(bad_v == 0 and bad_a == 0 and bad_r == 0, "2 engine: velocity, acceleration, rotation of all %d parts = the finite differences / node bases (bad v %d, a %d, rot %d)" % [(sc["ids"] as Array).size(), bad_v, bad_a, bad_r])
	ctl(wrong_dt == 0 and true, "2 an acceleration read with a 10x dt matches the level-2 acceleration for %d parts (must be 0 of the moving ones)" % wrong_dt)
	# joints
	var crank := L4.level2(ctx, S, "crankshaft")
	var cv := float(crank["joint"]["value"])
	ok(close_to(cv, 216.0, 0.0051, 0.01), "2 crank joint = 720 deg / 2 s * %.2f s = 216 (got %s)" % [t0, str(cv)])
	ctl(not close_to(cv, 221.0, 0.0051, 0.01), "2 a crank value 5 deg off is caught (216 vs 221)")
	var th := deg_to_rad(216.0)
	var Rc := P13.R
	var Lr := P13.L
	var yp := ((Rc * cos(th) + sqrt(Lr * Lr - Rc * Rc * sin(th) * sin(th))) - (Rc + Lr)) * 0.001
	var pj := L4.level2(ctx, S, "piston")["joint"]
	ok(close_to(float(pj["value"]), yp, 0.0051, 1e-7), "2 piston joint = the crank-slider formula (%.6f m vs %.6f m), distance to the nearest limit %s m, limits %s" % [float(pj["value"]), yp, str(pj["to_limit"]), str([pj["lo"], pj["hi"]])])
	ok(close_to(float(pj["to_limit"]), minf(yp - float(pj["lo"]), float(pj["hi"]) - yp), 0.0051, 1e-7), "2 piston distance to limit = min(v - lo, hi - v)")
	# the kcad distance of the three nearest gaps
	var asm: Dictionary = sc["asm"]
	var ppose: Dictionary = AssemblyAnim.pose_at(asm, t0)["moves"]
	var xfs := {}
	var pid_of := {}
	for p in asm["parts"]:
		var pid := String(p["id"])
		xfs[pid] = (ppose[pid] as Transform3D) * Assembly.xf_of(p) if ppose.has(pid) else Assembly.xf_of(p)
		pid_of[SCN._id(p)] = pid
	var l2p := L4.level2(ctx, S, "piston")
	var worst_gap := 0.0
	var gaps_n := 0
	var gap_bad := 0
	var ref_for_ctl := 0.0
	for g in l2p["gaps"]:
		var ra: Dictionary = {}
		var rb: Dictionary = {}
		for p in asm["parts"]:
			if SCN._id(p) == "piston":
				ra = p
			if SCN._id(p) == String(g["id"]):
				rb = p
		var sa := P13.solid(ra["rec"])
		var sb := P13.solid(rb["rec"])
		var pa := AssemblyMotion.place(sa, xfs[String(ra["id"])])
		var pb := AssemblyMotion.place(sb, xfs[String(rb["id"])])
		var d := float(KCad.distance(pa, pb).get("d", -1.0)) * 1000.0
		ref_for_ctl = d
		gaps_n += 1
		if not close_to(float(g["gap_mm"]), d, 0.0051, 0.002):
			gap_bad += 1
		worst_gap = maxf(worst_gap, absf(float(g["gap_mm"]) - d))
		KCad.release(pa)
		KCad.release(pb)
		KCad.release(sa)
		KCad.release(sb)
	ok(gaps_n == 3 and gap_bad == 0, "2 piston: the %d nearest gaps = KCad.distance between the placed solids (worst diff %.4f mm), %s" % [gaps_n, worst_gap, str(l2p["gaps"])])
	ctl(not close_to(float(l2p["gaps"][2]["gap_mm"]), ref_for_ctl * 1.05 + 0.01, 0.0051, 0.002) or ref_for_ctl == 0.0, "2 a gap 5 pct off is caught")
	# the arm's joints
	var actx := await ctx_of("s2_arm")
	var at0 := float(actx["sc"]["t0"])
	var AS := await L4.snap(actx, at0, true)
	var d := A14.design()
	var wp := N14.waypoints(d)
	var st := N14.state(d, wp, at0)
	var lim: Dictionary = d["lim"]
	var arm_bad := 0
	for pair in [["turntable", float(st["yaw"]), lim["ba"]], ["upper_arm", float(st["th1"]), lim["sh"]], ["forearm", float(st["th2"]), lim["el"]], ["gripper", float(st["psi"]), lim["wr"]]]:
		var j: Dictionary = L4.level2(actx, AS, pair[0])["joint"]
		var v: float = pair[1]
		var tl := minf(v - float(pair[2][0]), float(pair[2][1]) - v)
		if not (close_to(float(j["value"]), v, 0.0051, 0.01) and close_to(float(j["to_limit"]), tl, 0.0051, 0.02)):
			arm_bad += 1
		print("      %s: %s deg, limits %s, to_limit %s (expected %.3f)" % [pair[0], str(j["value"]), str([j["lo"], j["hi"]]), str(j["to_limit"]), tl])
	ok(arm_bad == 0, "2 arm: turntable, upper_arm, forearm, gripper joints and their distance to the nearest limit = N14.state and the design limits (bad %d)" % arm_bad)
	var gv := (cen(actx, "gripper", at0 + dt) - cen(actx, "gripper", at0 - dt)) / (2.0 * dt)
	var gl := L4.level2(actx, AS, "gripper")
	ok(arr_close(gl["vel"], gv, 0.0051, 0.0011), "2 arm gripper velocity = finite difference")


# ------------------------------------------------------------------ 3, 9
## the arm with can6 moved off along the first direction (and the least distance) that leaves 5 mm between its box and the jaws / gripper body; also its set_time frozen
func arm_planted(mode: String) -> Dictionary:
	var sc := SCN.arm()
	var inner: Callable = sc["set_time"]
	var t0 := 0.0
	var off := {"v": Vector3.ZERO}
	if mode == "frozen":
		var holder := {"t": -1.0}
		sc["set_time"] = func(_t: float) -> void:
			inner.call(float(holder["t"]) if holder["t"] >= 0.0 else _t)
			holder["t"] = float(holder["t"]) if holder["t"] >= 0.0 else _t
	else:
		sc["set_time"] = func(t: float) -> void:
			inner.call(t)
			((sc["nodes"] as Dictionary)["can6"] as MeshInstance3D).global_position += off["v"]
	var ctx := L4.open(root, sc)
	await L4.frames(3)
	t0 = float(sc["t0"])
	if mode == "away":
		var dirs := [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]
		var found := false
		for m in range(1, 80):
			for dv in dirs:
				off["v"] = dv * 0.005 * m
				L4.at(ctx, t0)
				var g := 1e9
				for o in ["jaw_plus", "jaw_minus", "gripper"]:
					g = minf(g, L4.box_gap_mm(ctx, "can6", o))
				if g >= 5.0:
					found = true
					break
			if found:
				break
		print("      planted: can6 moved %s m, box gap to jaws/gripper >= 5 mm" % str(off["v"]))
	return {"ctx": ctx, "t0": t0, "off": off["v"]}


func bars_held() -> void:
	var ctx := await ctx_of("s2_arm")
	var t0 := float(ctx["sc"]["t0"])
	var S := await L4.snap(ctx, t0, true)
	var held: Dictionary = S["held"]
	ok(held.has("can6") and (held["can6"] as Array).has("gripper"), "3 s2_arm t0 %.2f: can6 is held_by %s" % [t0, str(held.get("can6", []))])
	var others := 0
	for k in ["can1", "can2", "can3", "can4", "can5"]:
		others += 1 if held.has(k) else 0
	ok(others == 0, "3 cans 1-5 (resting on the stack) are not held (%d are)" % others)
	var l1 := L4.level1(ctx, S)
	var l0 := L4.level0(ctx, S)
	var in_l1 := false
	for r in l1.get("held", []):
		in_l1 = in_l1 or (r[0] == "can6" and (r as Array).has("gripper"))
	ok(in_l1 and int(l0["held"]) >= 1, "3 level 1 lists [can6, gripper] under held, level 0 counts %d held" % int(l0["held"]))
	var l2 := L4.level2(ctx, S, "can6")
	ok((l2["support"]["held_by"] as Array).has("gripper") and (l2["support"]["on"] as Array).is_empty(), "3/9 level 2 can6: support %s" % str(l2["support"]))
	var st := L4.level2(ctx, S, "stand")
	ok((st["support"]["on"] as Array).has("table"), "9 the stand rests on %s" % str(st["support"]["on"]))
	# planted
	var pa := await arm_planted("away")
	var Sp := await L4.snap(pa["ctx"], pa["t0"], true)
	ctl(not (Sp["held"] as Dictionary).has("can6"), "3 can6 moved away (%s m) is not held (held map %s)" % [str(pa["off"]), str(Sp["held"])])
	var l2p := L4.level2(pa["ctx"], Sp, "can6")
	ctl((l2p["support"]["held_by"] as Array).is_empty(), "9 the moved can6 is held by nothing: %s" % str(l2p["support"]))
	L4.close(pa["ctx"])
	var pf := await arm_planted("frozen")
	var Sf := await L4.snap(pf["ctx"], pf["t0"], true)
	ctl((Sf["held"] as Dictionary).is_empty(), "3 the scene frozen in time holds nothing (%d held)" % (Sf["held"] as Dictionary).size())
	L4.close(pf["ctx"])


# ------------------------------------------------------------------ 4
func frames_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k) or str(a[k]) != str(b[k]):
			return false
	return true


func bars_delta() -> void:
	var diff_prev := 0
	var moving := 0
	for nm in SCN.SCENES:
		var ctx := await ctx_of(nm)
		var t0 := float(ctx["sc"]["t0"])
		var dt := 1.0 / 30.0
		var Sm := await L4.snap(ctx, t0 - dt, true)
		var Sn := await L4.snap(ctx, t0, true)
		var Sp := await L4.snap(ctx, t0 + dt, true)
		var fm := L4.frame(ctx, Sm)
		var fn := L4.frame(ctx, Sn)
		var fp := L4.frame(ctx, Sp)
		var d := L4.delta(fn, fp)
		var back := L4.apply_delta(fn, d)
		var dv := L4.delta_view(ctx, Sn, Sp)
		var dtok := L4.tokens(dv)
		var l1tok := L4.tokens(L4.level1(ctx, Sp))
		ok(frames_equal(back, fp), "4 %s: delta (%d changed keys of %d, %d tokens vs level 1 %d) applied to frame n gives frame n+1 exactly" % [nm, (d["chg"] as Dictionary).size(), fn.size(), dtok, l1tok])
		if nm == "s6_null":
			ok((d["chg"] as Dictionary).is_empty() and (d["gone"] as Array).is_empty(), "4 s6_null: the delta of a frozen scene is empty (%d tokens)" % dtok)
		else:
			ok(dtok < l1tok, "4 %s: the delta is smaller than level 1 (%d < %d tokens)" % [nm, dtok, l1tok])
		if ["s1_engine", "s2_arm", "s3_walk", "s4_fall"].has(nm):
			moving += 1
			var wrong := L4.apply_delta(fn, L4.delta(fm, fn))
			if not frames_equal(wrong, fp):
				diff_prev += 1
	ctl(diff_prev >= 3, "4 the delta n-1 -> n applied to frame n misses frame n+1 in %d of the %d moving scenes" % [diff_prev, moving])


# ------------------------------------------------------------------ 5
func sweep_list_stats(vals: Array, thr: float) -> Dictionary:
	var worst := -1.0
	var at := 0.0
	var over := 0
	for v in vals:
		if float(v[1]) > worst:
			worst = float(v[1])
			at = float(v[0])
		if float(v[1]) > thr:
			over += 1
	return {"worst": worst, "at": at, "over": over}


func bars_sweep() -> void:
	McpCad.reset({})
	var asm := P13.loop_assembly()
	var r0 := McpCad.cad_asm({"ops": [{"op": "load", "assembly": asm}]})
	ok(bool(r0["ok"]), "5 CH13 loaded into McpCad: %s" % str(r0.get("error", "ok")))
	# the full per-step list
	var list: Array = []
	var list_bytes := 0
	for i in 36:
		var ang := 10.0 * i
		var r := McpCad.check_fit({"drive": "Crank", "value": ang, "detail": true})
		list_bytes += JSON.stringify(McpCad.rnd(r["result"], 3)).length()
		list.append([ang, float(r["result"]["overlap_total_mm3"])])
	McpCad.pose = {}
	var sw := McpCad.sweep({"drive": "Crank", "from": 0.0, "to": 350.0, "steps": 36})
	ok(bool(sw["ok"]), "5 sweep runs: %s" % str(sw.get("error", "ok")))
	var res: Dictionary = sw["result"]
	var sbytes := JSON.stringify(McpCad.rnd(res, 3)).length()
	var ls := sweep_list_stats(list, 1.0)
	ok(int(res["n"]) == 36 and absf(float(res["worst"]["value"]) - float(ls["worst"])) <= 2e-3 and absf(float(res["worst"]["at"]) - float(ls["at"])) < 1e-6 and int(res["over"]) == int(ls["over"]),
		"5 36 crank angles: sweep worst %s at %s, over 1 mm3: %d = the full list (worst %s at %s, over %d)" % [str(res["worst"]["value"]), str(res["worst"]["at"]), int(res["over"]), str(ls["worst"]), str(ls["at"]), int(ls["over"])])
	ok(sbytes < 1024 and list_bytes > 10000, "5 sweep text %d bytes (< 1024) against the full per-step list %d bytes (> 10000)" % [sbytes, list_bytes])
	# a parameter sweep that overlaps: the piston pin moved along x
	var plist: Array = []
	var xs: Array = []
	for i in 9:
		xs.append(0.25 * i)
	McpCad.pose = {}
	var pa: Dictionary
	for q in McpCad.asm["parts"]:
		if String(q["name"]).to_lower() == "piston":
			pa = q
	var pid := String(pa["id"])
	var saved: Array = (pa["pos"] as Array).duplicate()
	for x in xs:
		(pa["pos"] as Array)[0] = float(saved[0]) + float(x)
		var r2 := McpCad.check_fit({"hit_mm3": 1.0})
		plist.append([float(x), float(r2["result"]["overlap_total_mm3"])])
	pa["pos"] = saved
	var sw2 := McpCad.sweep({"param": {"id": pid, "field": "pos", "axis": 0}, "values": xs, "metric": "overlap_mm3"})
	var ls2 := sweep_list_stats(plist, 1.0)
	var res2: Dictionary = sw2["result"] if bool(sw2["ok"]) else {}
	var nondeg := float(ls2["worst"]) > 1.0
	ok(bool(sw2["ok"]) and nondeg and absf(float(res2["worst"]["value"]) - float(ls2["worst"])) <= 2e-3 + 1e-4 * float(ls2["worst"]) and absf(float(res2["worst"]["at"]) - float(ls2["at"])) < 1e-6 and int(res2["over"]) == int(ls2["over"]),
		"5 piston offset sweep (non-degenerate: worst %s mm3 at %s mm, %d of 9 over 1 mm3) = its full list (%s at %s, %d over)" % [str(res2.get("worst", {}).get("value")), str(res2.get("worst", {}).get("at")), int(res2.get("over", -1)), str(ls2["worst"]), str(ls2["at"]), int(ls2["over"])])
	# planted: another threshold gives another count
	var sw3 := McpCad.sweep({"param": {"id": pid, "field": "pos", "axis": 0}, "values": xs, "metric": "overlap_mm3", "threshold": float(ls2["worst"]) * 2.0})
	ctl(bool(sw3["ok"]) and int(sw3["result"]["over"]) != int(ls2["over"]), "5 the same sweep with another threshold counts %d, not the list's %d" % [int(sw3["result"]["over"]) if bool(sw3["ok"]) else -1, int(ls2["over"])])
	McpCad.reset({})


# ------------------------------------------------------------------ 7
func bars_track() -> void:
	var ctx := await ctx_of("s1_engine")
	var t0 := float(ctx["sc"]["t0"])
	var r := L4.view_sync(ctx, {"level": 3, "ids": ["piston", "rod"], "t": t0, "t1": t0 + 0.3, "step": 0.1})
	var tr: Dictionary = r["result"]
	var bad := 0
	for i in 4:
		for id in ["piston", "rod"]:
			if not arr_close(tr["pos"][id][i], cen(ctx, id, t0 + 0.1 * i), 0.0051, 1.1e-4):
				bad += 1
	ok(r["ok"] and (tr["t"] as Array).size() == 4 and bad == 0, "7 track of piston and rod, 4 samples 0.1 s apart = the posed centres (bad %d), %d tokens" % [bad, int(r["tokens"])])
	var bad2 := 0
	for i in 4:
		if not arr_close(tr["pos"]["piston"][i], cen(ctx, "piston", t0 + 0.1 * i + 0.05), 0.0051, 1.1e-4):
			bad2 += 1
	ctl(bad2 > 0, "7 the same track read at +0.05 s differs in %d of 4 samples" % bad2)


# ------------------------------------------------------------------ 8
func hull_brute(pts: Array) -> Array:
	var edges: Array = []
	for i in pts.size():
		for j in pts.size():
			if i == j:
				continue
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[j]
			var left := true
			for k in pts.size():
				var c: Vector2 = pts[k]
				if (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) < -1e-12:
					left = false
					break
			if left and a.distance_to(b) > 1e-9:
				edges.append([a, b])
	return edges


func inside_edges(edges: Array, p: Vector2) -> bool:
	if edges.is_empty():
		return false
	for e in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		if (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x) < 0.0:
			return false
	return true


func bars_character() -> void:
	var ctx := await ctx_of("s3_walk")
	var sc: Dictionary = ctx["sc"]
	var t0 := float(sc["t0"])
	var bad_feet := 0
	var bad_bal := 0
	var n_bal := 0
	var n_air := 0
	var last_edges: Array = []
	var last_com := Vector2.ZERO
	for k in 12:
		var t := t0 + 0.1 * k
		var S := await L4.snap(ctx, t, true)
		var ch := L4.character(ctx, S)
		L4.at(ctx, t)
		var sh := L4.shapes_now(ctx)
		var pts: Array = []
		var com := Vector3.ZERO
		var ms := 0.0
		for id in L4.named(ctx):
			if id == "floor" or id == "bat_barrel":
				continue
			var m := float(sc["mass"][id])
			ms += m
			var cap: Dictionary = sh[id]
			com += (((cap["a"] as Array).size() == 3 and true) as bool) and Vector3.ZERO or Vector3.ZERO
			com += L4.kinematics(ctx, t)[id]["c"] * m
			if id.begins_with("foot") or id.begins_with("ball"):
				var a := Vector3(cap["a"][0], cap["a"][1], cap["a"][2])
				var b := Vector3(cap["b"][0], cap["b"][1], cap["b"][2])
				var low := minf(a.y, b.y) - float(cap["r"])
				var down := low <= 0.015
				if bool(ch["feet"][id]["down"]) != down:
					bad_feet += 1
				if down:
					for e in [a, b]:
						for i in 8:
							pts.append(Vector2(e.x + float(cap["r"]) * cos(TAU * i / 8.0), e.z + float(cap["r"]) * sin(TAU * i / 8.0)))
		com /= ms
		var edges := hull_brute(pts)
		var inside := inside_edges(edges, Vector2(com.x, com.z))
		if bool(ch["balanced"]) != inside or bool(ch["airborne"]) != (pts.size() < 3):
			bad_bal += 1
		n_bal += 1 if inside else 0
		n_air += 1 if pts.size() < 3 else 0
		last_edges = edges
		last_com = Vector2(com.x, com.z)
	ok(bad_feet == 0 and bad_bal == 0, "8 s3_walk, 12 samples: foot contact flags and CoM-in-support-polygon = the brute-force recomputation (bad feet %d, bad balance %d); balanced %d, airborne %d of 12" % [bad_feet, bad_bal, n_bal, n_air])
	ctl(not inside_edges(last_edges, last_com + Vector2(1.0, 0.0)) and not last_edges.is_empty(), "8 a CoM moved 1 m away is outside the support polygon")


# ------------------------------------------------------------------ 10
func bars_errors() -> void:
	var ctx := await ctx_of("s1_engine")
	var r1 := L4.view_sync(ctx, {"level": 2})
	var r2 := L4.view_sync(ctx, {"level": 2, "part": "no_such_part"})
	var r3 := L4.view_sync(ctx, {"level": 9})
	ok(not bool(r1["ok"]) and not bool(r2["ok"]) and not bool(r3["ok"]), "10 level 2 without a part, with an unknown part, and level 9 all return ok false")


# ------------------------------------------------------------------ 6
func deep_close(a: Variant, b: Variant, rel := 1e-6) -> bool:
	if a is Dictionary and b is Dictionary:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for k in a:
			if not (b as Dictionary).has(k) or not deep_close(a[k], b[k], rel):
				return false
		return true
	if a is Array and b is Array:
		if (a as Array).size() != (b as Array).size():
			return false
		for i in (a as Array).size():
			if not deep_close(a[i], b[i], rel):
				return false
		return true
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) <= rel * absf(float(b)) + 1e-9
	return a == b


func bars_mcp() -> void:
	var sc0 := SCN.engine(false)
	var asm: Dictionary = sc0["asm"]
	var f := FileAccess.open(DIR + "/asm.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(asm))
	f.close()
	var cam: Dictionary = sc0["camera"]
	var camj := {"pos": [cam["pos"].x, cam["pos"].y, cam["pos"].z], "look": [cam["look"].x, cam["look"].y, cam["look"].z], "fov": cam["fov"]}
	var f2 := FileAccess.open(DIR + "/cam.json", FileAccess.WRITE)
	f2.store_string(JSON.stringify(camj))
	f2.close()
	var rf := DIR + "/mcp_out.json"
	DirAccess.remove_absolute(rf)
	var out := []
	var code := OS.execute("python", ["-u", ProjectSettings.globalize_path("res://tests/py/look4d2_drive.py"), OS.get_executable_path(), DIR], out, true)
	var f3 := FileAccess.open(rf, FileAccess.READ)
	if f3 == null:
		ok(false, "6 the MCP driver wrote nothing (exit %d): %s" % [code, String(out[0]).right(800) if out.size() > 0 else ""])
		return
	var R: Dictionary = JSON.parse_string(f3.get_as_text())
	var asm2: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/asm.json"))
	var calls: Dictionary = R["calls"]
	var bad: Array = []
	var ctxs2 := {}
	var tmax := maxf(float(asm2.get("anim", {}).get("length", 2.0)), 2.0)
	var cam2 := {"pos": Vector3(camj["pos"][0], camj["pos"][1], camj["pos"][2]), "look": Vector3(camj["look"][0], camj["look"][1], camj["look"][2]), "fov": float(camj["fov"])}
	var dsc := SCN.live(asm2, cam2, 0.6, 0.06, "live", tmax)
	var dctx := L4.open(root, dsc)
	await L4.frames(2)
	var tok_l0 := 0
	var tok_l1 := 0
	var other: Dictionary = {}
	for key in calls:
		var c: Dictionary = calls[key]
		if not c.has("args") or not c["args"].has("level") and not c["args"].has("since"):
			continue
		var pp: Dictionary = (c["args"] as Dictionary).duplicate()
		pp.erase("cam")
		pp["render"] = false
		var direct := L4.view_sync(dctx, pp)
		if not bool(direct["ok"]) or c.get("err", true):
			bad.append(key + ":err")
			continue
		var dj: Variant = JSON.parse_string(L4.txt(direct["result"]))
		if not deep_close(dj, c["v"]):
			bad.append(key)
		if key == "l0":
			tok_l0 = int(direct["tokens"])
			other = c["v"]
		if key == "l1":
			tok_l1 = int(direct["tokens"])
	ok(bad.is_empty() and calls.size() >= 5, "6 MCP look4d levels 0, 1, 2, 3 and since = the direct GDScript call (%d calls compared; bad %s); level 0 %d tokens, level 1 %d tokens" % [calls.size(), str(bad), tok_l0, tok_l1])
	var pp2: Dictionary = (calls["l0"]["args"] as Dictionary).duplicate()
	pp2.erase("cam")
	pp2["t"] = 0.9
	pp2["render"] = false
	var d2 := L4.view_sync(dctx, pp2)
	ctl(not deep_close(JSON.parse_string(L4.txt(d2["result"])), calls["l0"]["v"]), "6 the direct call at t = 0.9 is not equal to the MCP reply at t = 0.6")
	L4.close(dctx)
	# sweep through MCP = the direct sweep
	McpCad.reset({})
	McpCad.cad_asm({"ops": [{"op": "load", "assembly": asm2}]})
	McpCad.pose = {}
	var ds := McpCad.sweep({"drive": "Crank", "from": 0.0, "to": 350.0, "steps": 36})
	var mv: Dictionary = calls["sweep"]["v"]
	ok(bool(ds["ok"]) and deep_close(JSON.parse_string(JSON.stringify(McpCad.rnd(ds["result"], 3))), mv, 1e-6) and int(calls["sweep"]["bytes"]) < 1024, "6 MCP sweep = the direct sweep (%s) and its reply is %d bytes" % [str(mv.get("worst")), int(calls["sweep"]["bytes"])])
	McpCad.reset({})
	var im: Dictionary = calls["image"]["v"]
	ok(im.has("image") and im["image"] == null and String(im.get("image_note", "")).contains("no renderer"), "6 image:true on the headless session says it has no renderer (%s)" % str(im.get("image_note", "")).left(60))
	print("      tools: default %d, --cad %d (%s)" % [int(R["tools_default"]), int(R["tools_cad"]), str(R["cad_new"])])
	ok(R["cad_new"].has("look4d") and R["cad_new"].has("sweep") and not R["default_has"], "6 look4d and sweep are advertised with --cad and not in the default list")
