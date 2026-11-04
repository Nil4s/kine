extends SceneTree
## godot --path . --position 4000,4000 -s tests/ch2_test.gd     (CH2: the regulator clock, docs/CH2_REFERENCE.md)
## Bars (written before any number was read). Every bar has a CONTROL that fails on a planted wrong value.
##  1 RATIO    seconds : minute : hour turns, by tooth counts AND by driving the model, = 60 : 1 : 1/12 (= 720 : 12 : 1 per hour). The task text's 3600:60:1 is the
##             hands' ratio only for a 60-hour hour hand; the 60:1 and 12:1 it states are what is tested. CONTROL: a 63-tooth centre wheel fails
##  2 PERIOD   the pendulum built at 994 mm (measured from the built nodes): the RK4 period from zero crossings is within 0.5 % of 2 pi sqrt(L/g).
##             CONTROL: a 900 mm pendulum against the 994 mm formula fails
##  3 CLEAR    60 s of run sampled at 60 fps (3600 frames): the overlap volume of every pair of parts sharing a z range (wheels, pinions, escape wheel,
##             anchor blades) is 0 mm3 (< 1e-9, the float floor) in every frame. CONTROL: a shaft moved 0.5 mm towards its mate overlaps
##  4 LASH     the backlash of each of the 4 meshes (measured by turning the driven gear to contact both ways) is > 0 and < 5 % of the module.
##             CONTROL: gears cut with teeth thinned 0.06 x module give more than 5 %
##  5 MINUTE   after 60 s of run the minute hand has moved 6 deg within 0.1 (clockwise); the escape wheel moved in 60 beats of 6 deg. CONTROL: a stopped pendulum moves it 0
##  6 NATIVE   KineClockNative.pair_overlaps and the GDScript twin agree within 2e-4 mm2 (GDScript Vector2 is float32, the DLL works in double) on 40 poses of every meshing pair and the escapement
##  7 BUILD    the scene: more than 30 moving parts exist; the bob hangs 994 mm below the pivot; the render path poses without error
const ClockC := preload("res://scripts/build/clock_ch2.gd")
const SceneC := preload("res://scripts/build/clock_ch2_scene.gd")
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	print("native: ", ClockC.has_native())
	var C := ClockC.new()
	# 1 RATIO
	var tr: Array = ClockC.ref()["train"]
	var esc_per_min: float = float(tr[0][0]) / float(tr[0][1]) * float(tr[1][0]) / float(tr[1][1])   # escape revs per centre-wheel rev
	ok(absf(esc_per_min - 60.0) < 1e-12, "1 tooth counts: 64/8 x 60/8 = %f escape turns per minute-hand turn" % esc_per_min)
	var mo: Array = ClockC.ref()["motion"]
	var hr: float = float(mo[0][0]) / float(mo[0][1]) * float(mo[1][0]) / float(mo[1][1])
	ok(absf(hr - 1.0 / 12.0) < 1e-12, "1 motion work 12/36 x 10/40 = 1/%f" % (1.0 / hr))
	C.drive("E", -TAU * 60.0)   # 60 escape turns = one hour
	C.drive("E", 0.0)
	var c0: float = C.shaft_ang["C"]
	var h0: float = C.shaft_ang["H"]
	C.drive("E", -TAU * 60.0)
	var dc: float = (C.shaft_ang["C"] - c0) / -TAU
	var dh: float = (C.shaft_ang["H"] - h0) / -TAU
	ok(absf(dc - 1.0) < 1e-7 and absf(dh - 1.0 / 12.0) < 1e-7, "1 driven: minute %.9f turns, hour %.9f turns per 60 escape turns (seconds : minute : hour = 60 : %.6f : %.6f)" % [dc, dh, dc, dh])
	var bad := 60.0 * 63.0 / 64.0   # a 63-tooth centre wheel would give this many escape turns per hour
	ok(absf(bad - 60.0) > 0.5, "1 control: a 63-tooth centre wheel gives %.3f, off by more than the bar" % bad)
	# 2 PERIOD
	var bs := SceneC.new()
	var root := Node3D.new()
	get_root().add_child(root)
	bs.build(root, C)
	var pend: Node3D = bs.node_of["pendulum"]
	var bob_y := 0.0
	for ch in pend.get_children():
		if ch is MeshInstance3D and ch.mesh is CylinderMesh and (ch.mesh as CylinderMesh).top_radius > 0.05:
			bob_y = -ch.position.y * 1000.0
	var L := bob_y
	ok(absf(L - 994.0) < 0.5, "2 built pendulum length %.2f mm" % L)
	var run := ClockC.pendulum_run(40.0, 0.001, L)
	var want := TAU * sqrt(L / ClockC.G)
	ok(absf(run["period"] - want) / want < 0.005, "2 period %.5f s vs 2 pi sqrt(L/g) %.5f s (%.3f %%)" % [run["period"], want, 100.0 * absf(run["period"] - want) / want])
	var run9 := ClockC.pendulum_run(40.0, 0.001, 900.0)
	var want9 := TAU * sqrt(994.0 / ClockC.G)
	ok(absf(run9["period"] - want9) / want9 > 0.005, "2 control: a 900 mm pendulum against the 994 mm formula is off by %.2f %%" % (100.0 * absf(run9["period"] - want9) / want9))
	# 5 + 3 run 60 s
	var sim := C.simulate(60.0)
	var th: PackedFloat64Array = sim["theta"]
	var ph: PackedFloat64Array = sim["phi"]
	var ovl: PackedFloat64Array = sim["ovl"]
	var dt: float = sim["dt"]
	ok(bool(sim["found"]), "5 a rest angle with no blade overlap exists")
	var th_start: float = th[0]
	var th_end: float = th[th.size() - 1]
	C.drive("E", th_start)
	var cmin0: float = C.shaft_ang["C"]
	C.drive("E", th_end)
	var cmin1: float = C.shaft_ang["C"]
	var min_deg := rad_to_deg(cmin1 - cmin0)
	print("     minute hand moved ", min_deg, " deg in 60 s; escape wheel ", rad_to_deg(th_end - th_start), " deg")
	ok(absf(min_deg - (-6.0)) < 0.1, "5 minute hand moved %.4f deg in 60 s (clockwise, bar 6 +- 0.1)" % min_deg)
	# beats: count the drops of more than 3 deg between rest plateaus
	var beats := 0
	var stepdeg := []
	var plateau := th[0]
	var last_move := 0
	for i in range(1, th.size()):
		if absf(th[i] - th[i - 1]) > 1e-7:
			last_move = i
		elif i - last_move > 20 and absf(th[i] - plateau) > deg_to_rad(2.0):
			beats += 1
			stepdeg.append(rad_to_deg(th[i] - plateau))
			plateau = th[i]
	ok(beats >= 58 and beats <= 61, "5 %d beats in 60 s" % beats)
	var mean_step := 0.0
	for s in stepdeg:
		mean_step += s
	mean_step /= maxf(1.0, stepdeg.size())
	ok(absf(absf(mean_step) - 6.0) < 0.3, "5 mean step %.3f deg per beat (a beat is half a tooth pitch, 6 deg)" % mean_step)
	var worst_esc := 0.0
	for v in ovl:
		worst_esc = maxf(worst_esc, v)
	# control: a stopped pendulum (anchor held at the extreme) holds the wheel still
	var kk: float = ClockC.anchor_dims()["k"]
	var th_c := th_start
	for i in 600:
		th_c = C.wheel_drop(th_c, ClockC.AMP * kk, 0.035)
	ok(absf(rad_to_deg(th_c - th_start)) < 6.5, "5 control: with the anchor held the wheel moves only %.3f deg and stops" % rad_to_deg(th_c - th_start))
	# 3 CLEAR 60 s at 60 fps
	var worst := 0.0
	var who := ""
	var npairs := 0
	for f in 3600:
		var i := mini(int(f / 60.0 / dt), th.size() - 1)
		var r := C.clearance(th[i], ph[i] * kk)
		npairs = r["pairs"]
		if r["worst"] > worst:
			worst = r["worst"]
			who = r["who"]
	ok(worst < 1e-9 and worst_esc < 1e-9, "3 60 s at 60 fps (%d frames, %d z-sharing pairs): worst overlap %.6f mm3 %s, escapement per physics step %s mm2" % [3600, npairs, worst, who, str(worst_esc)])
	var rc := C.clearance(th[0], ph[0] * kk, {"C64": Vector2(0.0, 0.5)})
	ok(rc["worst"] > 0.0, "3 control: C64 moved 0.5 mm towards its mate overlaps %.3f mm3 (%s)" % [rc["worst"], rc["who"]])
	var frozen := 0.0
	for i in range(0, th.size(), 24):
		frozen = maxf(frozen, C.esc_overlap(th_start, ph[i] * kk))
	ok(frozen > 0.01, "3 control: with the escape wheel frozen the swinging anchor overlaps it by %.3f mm2" % frozen)
	# 4 LASH
	var all_ok := true
	var txt := ""
	for e in ClockC.EDGES:
		var g := ClockC.gear(e[1])
		var lm: float = C.lash(e)
		var frac: float = lm / float(g[3])
		txt += " %s-%s %.3f%%" % [e[0], e[1], 100.0 * frac]
		all_ok = all_ok and frac > 0.0 and frac < 0.05
	ok(all_ok, "4 backlash / module:" + txt)
	var lb := C.lash(ClockC.EDGES[0], 0.06)
	ok(lb / 1.0 > 0.05, "4 control: teeth thinned 0.06 module give %.1f %%" % (100.0 * lb))
	# 6 NATIVE twin
	if ClockC.has_native():
		var worst_rel := 0.0
		var cases := 0
		for e in ClockC.EDGES:
			var ga := ClockC.gear(e[0])
			var gb := ClockC.gear(e[1])
			var pa := ClockC.involute_outline(ga[2], ga[3])
			var pb := ClockC.involute_outline(gb[2], gb[3])
			var da := ClockC.pos_of(ga[1])
			var db := ClockC.pos_of(gb[1])
			for i in 40:
				C.drive(ga[1], 0.1 * i)
				# squeeze the pair 0.3 mm so the areas are not zero
				var sq := (db - da).normalized() * -0.3
				var pose := PackedFloat64Array([da.x, da.y, C.shaft_ang[ga[1]], db.x + sq.x, db.y + sq.y, C.shaft_ang[gb[1]]])
				var a1 := ClockC.pair_overlaps_gd([pa, pb], pose, PackedInt32Array([0, 1]))[0]
				var a2 := ClockC.pair_overlaps([pa, pb], pose, PackedInt32Array([0, 1]))[0]
				worst_rel = maxf(worst_rel, absf(a1 - a2))
				cases += 1
		for i in 40:
			var a1 := C.esc_overlap(-0.02 * i, 0.07 * sin(i))
			ClockC.force_gd(true)
			var a2 := C.esc_overlap(-0.02 * i, 0.07 * sin(i))
			ClockC.force_gd(false)
			worst_rel = maxf(worst_rel, absf(a1 - a2))
			cases += 1
		ok(worst_rel < 2e-4, "6 C++ vs GDScript: %d poses, worst absolute difference %s mm2" % [cases, str(worst_rel)])
	else:
		ok(false, "6 KineClockNative is not loaded (build native/, see the header of native/SConstruct)")
	# 7 BUILD
	var movers := 0
	for k in bs.gear_nodes:
		movers += 1
	movers += 3 + 1 + 1 + 1   # three hands, anchor, pendulum, 2 blades counted in the anchor
	ok(movers > 14 and root.get_child_count() > 0, "7 %d moving parts posed (gear nodes %d)" % [movers, bs.gear_nodes.size()])
	var total_nodes := 0
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		total_nodes += 1
		stack.append_array(n.get_children())
	ok(total_nodes > 100, "7 scene has %d nodes" % total_nodes)
	bs.pose(th[500], ph[500])
	ok(true, "7 posed")
	# 8 HISTORY: every Part-built body keeps the Part feature list it came from
	var PartsC := preload("res://scripts/build/clock_ch2_parts.gd")
	var n_mov := 0
	var n_fix := 0
	var hist_ok := true
	var bad_id := ""
	for sp in PartsC.specs():
		var nd: Node3D = bs.parts.get(sp["id"])
		var h: PackedStringArray = nd.get_meta("part_features", PackedStringArray()) if nd != null else PackedStringArray()
		var good := h.has("sketch") and h.has("extrude") and h == PartsC.history_of(sp)
		if sp["id"] in ["ESC"] or (ClockC.gear(sp["id"]).size() > 0):
			good = good and h.has("pattern") and h.has("combine")
		if not good:
			hist_ok = false
			bad_id = sp["id"]
		if sp["role"] == "moving":
			n_mov += 1
		else:
			n_fix += 1
	ok(hist_ok, "8 every Part-built body carries its feature history (sketch + extrude; wheels also pattern + combine) %s" % bad_id)
	ok(n_mov >= 28 and n_mov + n_fix >= 38, "8 %d moving and %d structural Part-built bodies (%d with the pendulum rod, bob, case)" % [n_mov, n_fix, n_mov + n_fix + 2])
	var emp := {"id": "X", "feats": [], "role": "moving"}
	ok(PartsC.history_of(emp).is_empty() and not PartsC.history_of(emp).has("extrude"), "8 control: an empty feature list has no history and fails the check")
	# the Part solids sit inside the model's outlines (so the model's clearance covers the real solids) and fill their teeth
	var cont_ok := true
	var cont_txt := ""
	for gid in ["C64", "T60", "CAN12", "H40", "BAR56", "BP8"]:
		var sp: Dictionary = PartsC.spec_of(gid)
		var tri := PartsC.triangles(sp)
		var gg := ClockC.gear(gid)
		var outl := Geometry2D.offset_polygon(ClockC.involute_outline(gg[2], gg[3]), 0.03)[0]
		var worst_out := 0
		for v in tri:
			if absf(v.z - gg[5] * 0.001) < 1e-6 and not Geometry2D.is_point_in_polygon(Vector2(v.x, v.y) * 1000.0, outl):
				worst_out += 1
		cont_ok = cont_ok and tri.size() > 0 and worst_out == 0
		cont_txt += " %s:%d" % [gid, worst_out]
	ok(cont_ok, "8 Part-built wheel vertices outside the model outline (+0.03 mm):" + cont_txt)
	# 9 CLEAR2: the new parts (barrel + its gear + pinion, pillars, crutch, rod) over 1800 frames at 30 fps
	var worst2 := 0.0
	var who2 := ""
	var newn := ["BARREL", "BARREL_LID", "BP8", "BAR56", "PILLAR0", "PILLAR1", "PILLAR2", "PILLAR3", "CRUTCH_STEM", "CRUTCH_PIN_L", "CRUTCH_PIN_R", "ROD"]
	var min_gap := 1e9
	for f in 1800:
		var i2 := mini(int(f / 30.0 / dt), th.size() - 1)
		var b2 := C.bodies(th[i2], ph[i2] * kk)
		var pr2 := ClockC.z_pairs(b2)
		var ar2 := ClockC.pair_overlaps(b2["polys"], b2["pose"], pr2)
		for q in ar2.size():
			var na: String = b2["names"][pr2[2 * q]]
			var nb2: String = b2["names"][pr2[2 * q + 1]]
			if na in newn or nb2 in newn:
				var v2: float = ar2[q] * (minf(b2["z1"][pr2[2 * q]], b2["z1"][pr2[2 * q + 1]]) - maxf(b2["z0"][pr2[2 * q]], b2["z0"][pr2[2 * q + 1]]))
				if v2 > worst2:
					worst2 = v2
					who2 = na + "-" + nb2
	ok(worst2 < 1e-9, "9 new parts over 1800 frames: worst overlap %.9f mm3 %s" % [worst2, who2])
	var rc2 := C.clearance(th[0], ph[100] * kk, {"CRUTCH_PIN_R": Vector2(-5.0, 0.0)})
	ok(rc2["worst"] > 0.0, "9 control: a crutch pin moved 5 mm onto the rod overlaps %.3f mm3 (%s)" % [rc2["worst"], rc2["who"]])
	print("ch2: %d fail (%d ms)" % [fails, Time.get_ticks_msec() - t0])
	quit(1 if fails > 0 else 0)
