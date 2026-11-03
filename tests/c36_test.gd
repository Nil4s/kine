## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/c36_test.gd     (C36, complaint 20, second try after C22; a window)
## BARS (written and committed before the first run of scripts/c36_grip.gd). Env C36_SHOT=<dir> saves 1280x720 screenshots.
## Cases (C22 B1 layout, but the sword lies across the forearm: along it, no wrist posture holds it, the arm misses by 6 cm; the standing bar as in C22)
## (the same layout as C22 B1): sword_r, sword_l (a sword lying in front of the hand, axis x) and bar_r (a 4 cm bar standing, axis y).
##  A  for each case after C36Grip.grip(B, h, prop, pk, 0.0):
##   A1 the wrist is within 1 cm of the target the solver derived from the handle axis and the palm frame (report "place"."target")
##   A2 the palm point is 0 .. 5 mm outside the prop's own surface (signed distance of the FULL prop, not only the handle slab)
##   A3 no finger or thumb segment is inside the prop: AnyGrip.gap (capsule radius included) of all 15 joints >= -0.1 mm (numeric slack only)
##   A4 the palm faces the handle surface: angle between the palm direction (curl direction of the final hand) and the inward normal <= 25 deg
##   A5 the 15 finger joints keyed at the playhead; every fingertip on the surface (<= 3 mm) or at its limit
##   A6 the palm stays within HAND_SPAN/2 (5 cm) of the handle centre along the handle axis
##   A7 (added after the first run showed the fingers parallel to the bar) the knuckle line index->pinky within 25 deg of the handle axis
##  B  finger flexion against a real power grip (Hume MC, Gellman H, McKellop H, Brumfield RH Jr. J Hand Surg Am 1990;15(2):240-243, PMID 2324451, abstract:
##     "functional flexion postures averaged 61 degrees at the MCP joint, 60 at the PIP and 39 at the DIP" (11 ADLs, electrogoniometer);
##     Bain GI et al. J Hand Surg Eur Vol 2015;40(4):406-411, PMID 24859993, abstract: functional range (90% of 20 Sollerman tasks)
##     MCP 19-71, PIP 23-87, DIP 10-64 degrees. Both read from the PubMed abstracts on 11-02. Power grip: Napier 1956, Cutkosky 1989).
##   B3 (added in fix round 1) the mean flexion of each joint also lies inside Bain 2015's functional range (MCP 19-71, PIP 23-87, DIP 10-64)
##   B1 mean over index..pinky of each joint's flexion, from the joint positions (wrist-MCP-PIP-DIP-tip bend angles): each within 25 deg
##      of the reference (MCP 36..86, PIP 35..85, DIP 14..64)
##   B2 no finger joint hyperextended: every flexion >= -5 degrees
##  C  CONTROLS (a bar must be able to fail)
##   C1 the C22 path (C22Hands.grip_handle) on sword_r leaves the wrist > 1 cm from its target or the palm > 5 mm out
##   C2 a point planted 3.3 cm off the surface: the A2 measure reads > 5 mm
##   C3 a point planted 3 mm inside the prop: the A3 measure reads < -0.1 mm
##  D  the command (C36Grip.grip_cmd on the real main scene): one undo step, status line says "palm"; a close screenshot of the hand.
extends SceneTree

var fails := 0
var m: Node
var worst_name := ""
const REF := {"MCP": 61.0, "PIP": 60.0, "DIP": 39.0}
const BAND := 25.0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func shot(name: String) -> void:
	var d := OS.get_environment("C36_SHOT")
	if d == "":
		return
	DirAccess.make_dir_recursive_absolute(d)
	root.get_viewport().get_texture().get_image().save_png(d + "/" + name + ".png")


func flex(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(a.normalized().angle_to(b.normalized()))


## [MCP, PIP, DIP] bend of one finger from the joint positions
func bends(B: Body, f: String, sd: String, h: String) -> Array:
	var w: Vector3 = B.P[h]
	var j1: Vector3 = B.P[f + "_01" + sd]
	var j2: Vector3 = B.P[f + "_02" + sd]
	var j3: Vector3 = B.P[f + "_03" + sd]
	var tip: Vector3 = B.E[f + "_03" + sd]
	return [flex(j1 - w, j2 - j1), flex(j2 - j1, j3 - j2), flex(j3 - j2, tip - j3)]


func worst_gap(B: Body, h: String, fn: Callable) -> float:
	var sd := h.right(2)
	var w := INF
	for f in GripWrap.LONG + ["thumb"]:
		for k in 3:
			var j := "%s_0%d%s" % [f, k + 1, sd]
			var g := AnyGrip.gap(B, fn, j)
			if g < w:
				w = g
				worst_name = j
	return w


func make_prop(case: String, Bg: Body, h: String) -> Dictionary:
	var pc: Vector3 = Bg.palm_point(h) + AnyGrip.curl_dir(Bg, h) * 0.06 + Vector3(0, 0, 0.1)
	if case.begins_with("sword_c22"):   # C22 B1's own layout: the sword lying along the forearm
		return Props.make("sword", Props.xf_at(Vector3(pc.x, pc.y - 0.015, pc.z + 0.1), 0.0))
	if case.begins_with("sword"):   # lying ACROSS the forearm (yaw 90): a power grip holds a bar at ~100 deg to the forearm, not along it
		pc.z -= 0.1
		return Props.make("sword", Props.xf_at(Vector3(pc.x, pc.y - 0.015, pc.z), 90.0))
	Props.register("zz bar", AABB(Vector3(-0.02, 0, -0.02), Vector3(0.04, 0.5, 0.04)), "", 1.0)
	return Props.make("zz bar", Props.xf_at(Vector3(pc.x, pc.y - 0.25, pc.z), 0.0))


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var G = load("res://scripts/c36_grip.gd")
	for case in ["sword_r", "sword_l", "bar_r"]:
		var h := "hand_l" if case.ends_with("_l") else "hand_r"
		var sd := h.right(2)
		var Bg := body()
		var prop := make_prop(case, Bg, h)
		var fn: Callable = AnyGrip.field_of(prop)["sd"]
		var pk := {}
		var t0 := Time.get_ticks_msec()
		var rep: Dictionary = G.grip(Bg, h, prop, pk, 0.0)
		print("     %s solved in %d ms" % [case, Time.get_ticks_msec() - t0])
		ok(not rep.is_empty(), "A0 %s: a grip report came back" % case)
		if rep.is_empty():
			continue
		var place: Dictionary = rep["place"]
		var hd: Dictionary = rep["handle"]
		var wr: float = (Bg.P[h] as Vector3).distance_to(place["target"])
		ok(wr <= 0.01, "A1 %s: the wrist is %.1f mm from the handle-derived target (<= 10 mm)" % [case, wr * 1000.0])
		var palm := Bg.palm_point(h)
		var sdp := float(fn.call(palm))
		ok(sdp >= 0.0 and sdp <= 0.005, "A2 %s: the palm is %.2f mm outside the prop surface (0 .. 5 mm)" % [case, sdp * 1000.0])
		var wg := worst_gap(Bg, h, fn)
		ok(wg >= -0.0001, "A3 %s: the worst finger/thumb segment (%s) is %.2f mm from the prop (>= -0.1 mm)" % [case, worst_name, wg * 1000.0])
		ok(pk.size() == 15, "A5 %s: %d finger joints keyed" % [case, pk.size()])
		var bad := []
		for f in GripWrap.LONG:
			var tip: Array = rep[f][2]
			if not (float(tip[1]) <= 0.003 or tip[2] == "limit"):
				bad.append("%s tip %.1f mm off" % [f, float(tip[1]) * 1000.0])
		ok(bad.is_empty(), "A5 %s: every fingertip on the surface or at its limit %s" % [case, bad])
		var along := absf((palm - (hd["c"] as Vector3)).dot(hd["ax"]))
		ok(along <= C22Hands.HAND_SPAN * 0.5, "A6 %s: the palm is %.1f cm along the axis from the handle centre (<= 5 cm)" % [case, along * 100.0])
		var stack: Vector3 = (Bg.P["pinky_01" + sd] as Vector3) - (Bg.P["index_01" + sd] as Vector3)
		var sa := rad_to_deg(stack.angle_to(hd["ax"]))
		sa = minf(sa, 180.0 - sa)
		ok(sa <= 25.0, "A7 %s: the knuckle line (the fingers' stack) is %.1f degrees off the handle axis (<= 25: the fingers wrap round it)" % [case, sa])
		# B: flexion of the closed hand
		var sum := {"MCP": 0.0, "PIP": 0.0, "DIP": 0.0}
		var lo := INF
		for f in GripWrap.LONG:
			var b := bends(Bg, f, sd, h)
			sum["MCP"] += b[0] / 4.0
			sum["PIP"] += b[1] / 4.0
			sum["DIP"] += b[2] / 4.0
			lo = minf(lo, minf(b[0], minf(b[1], b[2])))
		for k in ["MCP", "PIP", "DIP"]:
			ok(absf(sum[k] - REF[k]) <= BAND, "B1 %s: mean %s flexion %.1f deg vs the power-grip reference %.0f (+-%.0f)" % [case, k, sum[k], REF[k], BAND])
		var BAIN := {"MCP": [19.0, 71.0], "PIP": [23.0, 87.0], "DIP": [10.0, 64.0]}
		for k in ["MCP", "PIP", "DIP"]:
			ok(sum[k] >= BAIN[k][0] and sum[k] <= BAIN[k][1], "B3 %s: mean %s flexion %.1f inside Bain 2015's functional range %s" % [case, k, sum[k], BAIN[k]])
		ok(lo >= -5.0, "B2 %s: smallest joint flexion %.1f deg (>= -5, nothing hyperextended)" % [case, lo])
		# A4 last: curl_dir opens the fingers (the wrist and its turn stay)
		var q := AnyGrip._nearest(fn, palm)
		var ang := rad_to_deg(AnyGrip.curl_dir(Bg, h).angle_to(-AnyGrip._grad(fn, q)))
		ok(ang <= 25.0, "A4 %s: the palm faces the surface within %.1f degrees (<= 25)" % [case, ang])
		if case == "sword_r":
			var B1 := body()
			var p1 := make_prop(case, B1, h)
			var r1 := C22Hands.grip_handle(B1, h, p1, {}, 0.0)
			var f1: Callable = AnyGrip.field_of(p1)["sd"]
			var s1 := float(f1.call(B1.palm_point(h)))
			ok(float(r1["place"]["wrist_m"]) > 0.01 or s1 > 0.005, "C1 CONTROL: the C22 path leaves the wrist %.1f mm off / the palm %.1f mm out (the bars are 10 / 5 mm)" % [float(r1["place"]["wrist_m"]) * 1000.0, s1 * 1000.0])
			var q2 := AnyGrip._nearest(fn, palm)
			var off := q2 + AnyGrip._grad(fn, q2) * 0.033
			ok(float(fn.call(off)) > 0.005, "C2 CONTROL: a point planted 3.3 cm off the surface reads %.1f mm (> 5 mm)" % (float(fn.call(off)) * 1000.0))
			var inside := q2 - AnyGrip._grad(fn, q2) * 0.003
			ok(float(fn.call(inside)) < -0.0001, "C3 CONTROL: a point planted 3 mm inside reads %.1f mm (< -0.1)" % (float(fn.call(inside)) * 1000.0))
	# INFO: C22 B1's default layout, a sword lying ALONG the forearm (axis x, the arm points along x). Not a bar: printed so the numbers are seen.
	for case in ["sword_c22_r", "sword_c22_l"]:
		var h := "hand_l" if case.ends_with("_l") else "hand_r"
		var sd := h.right(2)
		var Bi := body()
		var pi := make_prop(case, Bi, h)
		var fi: Callable = AnyGrip.field_of(pi)["sd"]
		var ri: Dictionary = G.grip(Bi, h, pi, {}, 0.0)
		var ki: Vector3 = (Bi.P["pinky_01" + sd] as Vector3) - (Bi.P["index_01" + sd] as Vector3)
		var ka := rad_to_deg(ki.angle_to(ri["handle"]["ax"]))
		print("INFO %s: wrist %.1f mm from its target, palm %.1f mm from the surface, worst finger/thumb segment %.1f mm (%s), knuckle line %.0f deg off the bar, best of %d candidates, turn %.1f deg  -> the default layout (bar along the forearm) %s" % [case, (Bi.P[h] as Vector3).distance_to(ri["place"]["target"]) * 1000.0, float(fi.call(Bi.palm_point(h))) * 1000.0, worst_gap(Bi, h, fi) * 1000.0, worst_name, minf(ka, 180.0 - ka), int(ri["place"]["tried"]), float(ri["place"]["turn_deg"]), "CANNOT be gripped" if (Bi.P[h] as Vector3).distance_to(ri["place"]["target"]) > 0.01 or minf(ka, 180.0 - ka) > 25.0 else "can be gripped"])
	# D the command on the real scene
	m.S.props = []
	m.S.on_floor = false   # else Props.settle drops the sword to the floor
	var Bm: Body = m.B
	var hh := "hand_r"
	m.S.props.append(make_prop("sword_r", Bm, hh))
	var xf0: Transform3D = m.S.props[0]["xf"]
	m.sel_prop = 0
	m.sel = "hand_r"
	m.playhead = 0.0
	var u0: int = m.undo.size()
	G.grip_cmd(m)
	await idle(4)
	ok(m.undo.size() == u0 + 1 and m.ui_status.text.find("palm") >= 0, "D1 the command: one undo step (%d -> %d), status '%s'" % [u0, m.undo.size(), m.ui_status.text.left(90)])
	m.get_window().size = Vector2i(1280, 720)
	await idle(4)
	print("     sword origin y: before %.3f after the command (Props.settle drops a floating prop to the floor) %.3f" % [xf0.origin.y, (m.S.props[0]["xf"] as Transform3D).origin.y])
	m.S.props[0]["xf"] = xf0   # the picture shows the sword where it was gripped (the grip is solved on the prop as it was)
	m._props_pose()
	var pn: Node3D = m.ui_props_root.get_node_or_null("prop_0")
	if pn != null:
		pn.transform = xf0   # the node back where the prop was gripped (Props.settle had put it on the floor)
	var wr: Vector3 = Bm.P[hh]
	var palmw: Vector3 = Bm.palm_point(hh)
	print("     prop node: %s, set root visible %s, children %d" % [pn, m.ui_props_root.visible, m.ui_props_root.get_child_count()])
	if pn != null:
		var bb := AABB()
		var first := true
		for mi in pn.find_children("*", "MeshInstance3D", true, false):
			var mn := mi as MeshInstance3D
			var wb: AABB = mn.global_transform * mn.get_aabb()
			bb = wb if first else bb.merge(wb)
			first = false
			print("     mesh %s visible %s in tree %s aabb %s layers %d" % [mn.name, mn.is_visible_in_tree(), mn.is_inside_tree(), wb, mn.layers])
		print("     prop world AABB %s; palm %s wrist %s; prop centre in camera frustum: %s" % [bb, palmw, wr, not m.cam.is_position_behind(bb.get_center()) and m.cam.get_viewport().get_visible_rect().has_point(m.cam.unproject_position(bb.get_center()))])
		print("     handle seen at camera %s, palm at %s" % [m.cam.unproject_position(bb.get_center()), m.cam.unproject_position(palmw)])
	m.target = palmw
	for v in [["side", -90.0, -10.0], ["front", 0.0, -10.0], ["top", 40.0, -70.0]]:
		m.yaw = v[1]
		m.pitch = v[2]
		m.dist = 0.6
		await idle(2)
		m._cam()
		await idle(6)
		shot("c36_hand_" + v[0])
	print("c36: %d fail" % fails)
	quit(1 if fails > 0 else 0)
