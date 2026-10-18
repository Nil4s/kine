## godot --headless --path . -s tests/grip_wrap_test.gd     (round 47, GATES CC1; docs/GRIP_RESEARCH.md)
## THE WRAP: fingers closed round a handle segment by segment until each touches (Buchholz & Armstrong 1992).
##   1 every weapon, in its bat hand's standard place: every long finger's tip touches (within 3 mm) or is at its limit,
##     no segment inside the handle by more than 1 mm
##   2 the handle swept 20-80 mm across (Lee & Jung 2015's range), the palm kept on its surface: MCP+PIP flexion falls
##     as the diameter grows (Lee & Rim 1991: "flexion angles at the MCP and PIP joints gradually increase as cylinder
##     diameter decreases"), every finger
##   3 Gulke 2010 (48 people): PIP the largest of the three joints on average ("PIP 43, MCP 28, DIP 26 deg") - REPORTED
##     with our numbers next to theirs, barred on the order: PIP the largest of the three
##   4 against Nick's hand-fitted bat grip (data/grips/metal_bat.json): the mean joint difference under 12 deg (Buchholz &
##     Armstrong's own SD against real hands), joint by joint printed; REPORTED beside it: his own three hands' spread
##     (bat, axe card v0 left and right: 17-23 deg apart) and the held-out axe left hand
##   5 the wrap of one hand takes under 100 ms (an edit, felt as instant: Nielsen, Usability Engineering 1993, ch. 5)
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var B: Body = m.B
	B.fast = true
	# 1
	var bad := []
	var rows := []
	var ms := 0.0
	for k in Body.KINDS:
		B.set_kind(k)
		B.weapon_to_hand("hand_r")
		var hd := GripWrap.handle_of(B)
		var t0 := Time.get_ticks_usec()
		var rep := GripWrap.wrap(B, "hand_r", hd[0], hd[1], hd[2], GripWrap.type_of(k))
		ms = maxf(ms, (Time.get_ticks_usec() - t0) / 1000.0)
		var tips := []
		for f in GripWrap.LONG:
			var tip: Array = rep[f][2]
			tips.append("%s %+.1f%s" % [f, float(tip[1]) * 1000, "L" if tip[2] == "limit" else ""])
			if not (tip[2] == "limit" or float(tip[1]) <= 0.003):
				bad.append("%s %s tip %.1f mm off" % [k, f, float(tip[1]) * 1000])
			for row in rep[f]:
				if float(row[1]) < -0.001:
					bad.append("%s %s inside %.1f mm" % [k, f, float(row[1]) * 1000])
		rows.append("%s (%.0f mm): %s" % [k, hd[2] * 2000, ", ".join(tips)])
	for r in rows:
		print("     " + r)
	ok(bad.is_empty(), "1 every weapon: each fingertip touches (<= 3 mm) or is at its limit, nothing inside > 1 mm (bad: %s)" % [bad])
	# 2 + 3: the bat placement, the handle swept; the palm kept on the surface (the axis moved away from the palm)
	B.set_kind("metal_bat")
	B.weapon_to_hand("hand_r")
	var hd0 := GripWrap.handle_of(B)
	var a0: Vector3 = hd0[0]
	var b0: Vector3 = hd0[1]
	var r0: float = hd0[2]
	var ax := (b0 - a0).normalized()
	var palm: Vector3 = (B.P["hand_r"] as Vector3).lerp(B.E["hand_r"], 0.6)
	var to_palm := (palm - a0) - ax * (palm - a0).dot(ax)
	var out_dir := to_palm.normalized()
	var keep := B.state()
	var sums := {}
	var mean := Vector3.ZERO
	var nmean := 0
	var trend_bad := []
	for dmm in [20, 30, 40, 50, 60, 70, 80]:
		B.set_state(keep)
		var r: float = dmm / 2000.0
		var sh: Vector3 = -out_dir * (r - r0)
		GripWrap.wrap(B, "hand_r", a0 + sh, b0 + sh, r)
		for f in GripWrap.LONG:
			var v1: Vector3 = B.ang[f + "_01_r"]
			var v2: Vector3 = B.ang[f + "_02_r"]
			var v3: Vector3 = B.ang[f + "_03_r"]
			sums[f] = sums.get(f, []) + [v1.x + v2.x]
			mean += Vector3(v1.x, v2.x, v3.x)
			nmean += 1
	for f in sums:
		var s: Array = sums[f]
		for i in s.size() - 1:
			if s[i + 1] > s[i] + 0.5:
				trend_bad.append("%s %d->%d mm" % [f, 20 + 10 * i, 30 + 10 * i])
	print("     MCP+PIP by diameter 20..80 mm: %s" % [sums])
	ok(trend_bad.is_empty(), "2 thinner handle, more MCP+PIP flexion, every finger, 20-80 mm (rises: %s)" % [trend_bad])
	mean /= maxf(1, nmean)
	ok(mean.y > mean.x and mean.y > mean.z, "3 mean flexion over the sweep: MCP %.0f, PIP %.0f, DIP %.0f deg (Gulke 2010: 28 / 43 / 26); PIP the largest" % [mean.x, mean.y, mean.z])
	# 4 against Nick's own hands. His three hand-fitted grips (the bat file; his axe card v0, left and right) differ from
	# EACH OTHER by the spread printed below: he fits by eye against the mesh (the axe left hand's segments sink up to
	# 10 mm into the handle, the right's float 12-23 mm off it). The wrap must sit as close to his bat grip as his own
	# hands sit to it (the bar: the smallest of his own differences), and on the HELD-OUT hand (his axe left, never used
	# to build the wrap) as close as his other hands sit to that one.
	B.set_state(keep)
	var gf: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/grips/metal_bat.json"))
	var bat := {}
	for j in gf["fingers"]:
		if not (j as String).begins_with("thumb_01"):
			bat[(j as String).trim_suffix("_r")] = float(gf["fingers"][j][0])
	var axe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://refs/grip_nick_axe_v0.json"))
	B.from_dict(axe["pose"])
	var ax_l := _hand(B, "_l", bat)
	var ax_r := _hand(B, "_r", bat)
	var own_bat := minf(_mae(ax_l, bat), _mae(ax_r, bat))
	var own_l := minf(_mae(bat, ax_l), _mae(ax_r, ax_l))
	print("     Nick's own spread: bat-axeL %.1f, bat-axeR %.1f, axeL-axeR %.1f deg" % [_mae(ax_l, bat), _mae(ax_r, bat), _mae(ax_r, ax_l)])
	B.set_state(keep)
	GripWrap.wrap(B, "hand_r", a0, b0, r0)
	var w_bat := _hand(B, "_r", bat)
	var line := []
	for k in bat:
		line.append("%s %.0f/%.0f" % [k, w_bat[k], bat[k]])
	print("     wrap / Nick (bat): " + ", ".join(line))
	B.from_dict(axe["pose"])
	var hx := GripWrap.handle_of(B)
	GripWrap.wrap(B, "hand_l", hx[0], hx[1], hx[2])
	var w_l := _hand(B, "_l", bat)
	ok(_mae(w_bat, bat) < 12.0, "4 the wrap vs Nick's bat grip: %.1f deg mean joint difference (bar 12, Buchholz & Armstrong's SD); his own other hands sit %.1f deg from it" % [_mae(w_bat, bat), own_bat])
	print("     REPORTED (not barred), held out: his axe card v0 left hand, wrapped where he put it: %.1f deg from his; his other hands sit %.1f deg from it" % [_mae(w_l, ax_l), own_l])
	ok(ms < 100.0, "5 the slowest wrap of one hand took %.1f ms (bar 100: Nielsen's 0.1 s limit for a response felt as instant; the wrap runs on an edit, not every frame)" % ms)
	m.queue_free()
	print("GRIP WRAP TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)


## a hand's finger bends by joint name (no side suffix), the joints of `like`
func _hand(B: Body, sd: String, like: Dictionary) -> Dictionary:
	var o := {}
	for k in like:
		o[k] = (B.ang[k + sd] as Vector3).x
	return o


func _mae(a: Dictionary, b: Dictionary) -> float:
	var t := 0.0
	for k in b:
		t += absf(float(a[k]) - float(b[k]))
	return t / b.size()
