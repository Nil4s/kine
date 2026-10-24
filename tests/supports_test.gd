## godot --headless --path . -s tests/supports_test.gd     (INNOVATIONS N015: pose from supports, scripts/support_pose.gd)
## BARS, written before the numbers (the task's bars; the thresholds are the app's own where it has one):
##  For each of 6 phrases ("kneeling on the right knee, left foot flat", "left hand on the floor, both feet", "on both
##  knees", "sitting on the floor", "lunge, back knee 5 cm off the floor", "push-up plank"), solved from the stand pose:
##   (1) every named contact within 1 cm of the floor (Balance.TOUCH), read here by the test's OWN formulas (sole points
##       over rest height for a foot, capsule undersides for a knee / hand, for the butt also the pelvis as Body.floor_shift
##       reads it), not by the module's report;
##   (2) every part outside the named contacts' groups at least 2 cm above the floor;
##   (3) nothing more than 1 cm into the floor (Body.floor_shift, the app's own snap-to-floor reading, and the fingers);
##   (4) the COM inside the support polygon of all contacts by >= 2 cm (Balance.MARGIN_RES);
##   (5) every joint inside its limits (data/body_limits.json via Body.clamp_ang);
##   (6) no self-penetration: Body.contacts()' deepest pair under Feasible.PEN_FIX (2 cm, feasible.gd's own bar);
##   (7) the weight shares are each >= 0 and sum to 100 % (+-0.1);
##   (8) the lunge's back knee 5 cm +- 1 cm off the floor.
##  (9) the instrument can move: on the STAND pose the same readings say the knees are > 40 cm off the floor and the
##      plank's hands > 60 cm, so the bars above are not passing by construction.
##  (10) "standing on the head with both hands in the air" is refused, the reason names the head and that it would be the
##       only support, and the body is exactly as it was.
##  (11) a body turned 90 deg first keeps its heading through a solve ("on both knees"), bars (1)-(6) still hold.
##  (12) the hook: main._pose_words takes a supports phrase as ONE undo step (Ctrl+Z puts the body back exactly), serve's
##       `pose` returns the supports, the S search offers the phrase as its top row; plain pose words still work ("bend the
##       left elbow 45" reaches 55) and are not claimed; a refused phrase changes nothing and adds no undo step.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func stand(B: Body) -> void:
	B.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	B.props = []
	B.fk()


func bot(B: Body, part: String) -> float:
	var c: Array = B.cap(part)
	return minf((c[0] as Vector3).y, (c[1] as Vector3).y) - float(B.rad[part])


func fingers(sd: String) -> Array:
	return Body.FINGERS.filter(func(f): return (f as String).ends_with(sd))


## the test's own reading of a contact's gap (m): see bar (1)
func gap(B: Body, e: Dictionary) -> float:
	var sd: String = e["side"]
	match String(e["part"]):
		"foot":
			return maxf(absf((B.P["foot" + sd] as Vector3).y - (B.p0["foot" + sd] as Vector3).y), absf((B.P["ball" + sd] as Vector3).y - (B.p0["ball" + sd] as Vector3).y))
		"toes":
			var tip: float = (B.E["ball" + sd] as Vector3).y - (B.e0["ball" + sd] as Vector3).y
			var joint: float = (B.P["ball" + sd] as Vector3).y - (B.p0["ball" + sd] as Vector3).y
			return maxf(absf(tip), absf((tip + joint) * 0.5))
		"knee":
			# the knee: the thigh capsule's knee end and the calf capsule's knee end, whichever is lower
			return absf(minf((B.cap("thigh" + sd)[1] as Vector3).y - float(B.rad["thigh" + sd]), (B.cap("calf" + sd)[0] as Vector3).y - float(B.rad["calf" + sd])))
		"hand":
			var lo := bot(B, "hand" + sd)
			for f in fingers(sd):
				lo = minf(lo, bot(B, f))
			return absf(lo)
		"butt":   # the hips' capsules, and the pelvis as Body.floor_shift reads it (its joint to its end, minus its radius)
			var seg: float = minf((B.P["pelvis"] as Vector3).y, (B.E["pelvis"] as Vector3).y) - float(B.rad["pelvis"])
			return absf(minf(minf(bot(B, "hips_wide"), bot(B, "pelvis")), seg))
	return INF


func limits_ok(B: Body) -> Array:
	var bad := []
	for j in Body.ORDER:
		var v: Vector3 = B.ang[j]
		if not v.is_equal_approx(B.clamp_ang(j, v)):
			bad.append(j)
	return bad


func deepest_pair(B: Body) -> float:
	var d := 0.0
	for c in B.contacts():
		d = maxf(d, float(c[2]))
	return d


## bars (1)-(6) on B as it stands; returns [all ok, the line]
func check_bars(B: Body, spec: Dictionary) -> Array:
	var m := SupportPose.measure(B, spec, true)
	var gaps := []
	var g_ok := true
	for e in spec["contacts"]:
		var g := gap(B, e)
		gaps.append("%s %.2f" % [SupportPose._label(e), g * 100.0])
		g_ok = g_ok and g <= 0.01
	var free_ok: bool = float(m["free_low"][1]) >= 0.02
	var fin := INF
	for sd in ["_l", "_r"]:
		for f in fingers(sd):
			fin = minf(fin, bot(B, f))
	var floor_in: float = maxf(-B.floor_shift(), -fin)
	var floor_ok := floor_in <= 0.01
	var mg_ok: float = float(m["margin"]) >= 0.02
	var lim := limits_ok(B)
	var pen := deepest_pair(B)
	var all: bool = g_ok and free_ok and floor_ok and mg_ok and lim.is_empty() and pen < Feasible.PEN_FIX
	return [all, "gaps cm [%s]; lowest other part %s %.1f cm; into floor %.2f cm; COM %.1f cm inside (rise.gd's 4 cm-touch reading: %.1f); limits off %s; deepest pair %.2f cm" % [
		", ".join(gaps), m["free_low"][0], float(m["free_low"][1]) * 100.0, floor_in * 100.0, float(m["margin"]) * 100.0, Rise.support_margin(B) * 100.0, lim, pen * 100.0]]


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var phrases := ["kneeling on the right knee, left foot flat", "left hand on the floor, both feet", "on both knees",
		"sitting on the floor", "lunge, back knee 5 cm off the floor", "push-up plank"]
	# (9) the instrument can move
	stand(B)
	var sk := SupportPose.parse("on both knees")
	var sp := SupportPose.parse("push-up plank")
	var k0 := gap(B, sk["contacts"][0])
	var h0 := gap(B, sp["contacts"][0])
	ok(k0 > 0.40 and h0 > 0.60, "9 instrument: standing, the left knee reads %.1f cm off the floor, the plank's left hand %.1f cm" % [k0 * 100.0, h0 * 100.0])
	for p in phrases:
		stand(B)
		var t0 := Time.get_ticks_msec()
		var r := SupportPose.solve(B, p)
		var ms := Time.get_ticks_msec() - t0
		if not r["ok"]:
			ok(false, "'%s' solved: %s" % [p, r["error"]])
			continue
		var spec := SupportPose.parse(p)
		var cb := check_bars(B, spec)
		ok(cb[0], "1-6 '%s' (%s, %d ms): %s" % [p, r["family"], ms, cb[1]])
		var tot := 0.0
		var neg := false
		var sh := []
		for s in r["supports"]:
			tot += float(s["share_pct"])
			neg = neg or float(s["share_pct"]) < 0.0
			sh.append("%s %.1f%%%s" % [s["part"], s["share_pct"], " (implied)" if s["implied"] else ""])
		ok(absf(tot - 100.0) <= 0.1 and not neg, "7 '%s' weight (HEURISTIC): %s = %.1f %%" % [p, ", ".join(sh), tot])
		if p.begins_with("lunge"):
			var kh: float = r["heights"][0]["cm"]
			var knee_raw: float = minf((B.cap("thigh_r")[1] as Vector3).y - float(B.rad["thigh_r"]), (B.cap("calf_r")[0] as Vector3).y - float(B.rad["calf_r"]))
			ok(absf(knee_raw - 0.05) <= 0.01, "8 the lunge's back (right) knee %.1f cm off the floor (asked 5; report says %.1f)" % [knee_raw * 100.0, kh])
	# (10) the impossible phrase
	stand(B)
	var before := JSON.stringify(B.state())
	var bad := SupportPose.solve(B, "standing on the head with both hands in the air")
	ok(not bad["ok"] and String(bad["error"]).contains("head") and String(bad["error"]).contains("ONLY support") and JSON.stringify(B.state()) == before,
		"10 refused, body unchanged: %s" % String(bad.get("error", "")).left(160))
	# (11) a turned body keeps its heading
	stand(B)
	B.ang["pelvis"] = Vector3(0, 0, 90)
	B.fk()
	var f0: Vector3 = (B.G["pelvis"] as Quaternion) * Vector3(0, 0, 1)
	var rt := SupportPose.solve(B, "on both knees")
	var f1: Vector3 = (B.G["pelvis"] as Quaternion) * Vector3(0, 0, 1)
	var dh := rad_to_deg(absf(Vector2(f0.x, f0.z).angle_to(Vector2(f1.x, f1.z))))
	var cbt := check_bars(B, sk) if rt["ok"] else [false, String(rt.get("error", ""))]
	ok(rt["ok"] and cbt[0] and dh < 2.0, "11 turned 90 deg first: heading kept within %.1f deg; %s" % [dh, cbt[1]])
	# (12) the hook through the real poser
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	stand(m.B)
	var s0 := JSON.stringify(m.B.state())
	var u0: int = m.undo.size()
	var hr: Dictionary = m._pose_words("on both knees")
	var u1: int = m.undo.size()
	var kn: float = gap(m.B, sk["contacts"][0])
	m._undo()
	ok(hr["ok"] and u1 == u0 + 1 and kn <= 0.01 and JSON.stringify(m.B.state()) == s0 and String(m.ui_status.text) != "",
		"12a words box: 'on both knees' is one undo step (knee %.2f cm off the floor), Ctrl+Z puts the body back exactly" % (kn * 100.0))
	stand(m.B)
	var A := AgentTools.new(m)
	var sr: Dictionary = await A.request(7, "pose", {"text": "push-up plank"})
	var res: Dictionary = sr.get("result", {})
	ok(res.get("ok", false) and (res.get("supports", []) as Array).size() == 4 and JSON.stringify(sr) != "",
		"12b serve pose 'push-up plank': %d supports, %s" % [(res.get("supports", []) as Array).size(), ", ".join((res.get("supports", []) as Array).map(func(x): return "%s %.0f%%" % [x["part"], x["share_pct"]]))])
	stand(m.B)
	var u2: int = m.undo.size()
	var b2 := JSON.stringify(m.B.state())
	var nr: Dictionary = m._pose_words("standing on the head with both hands in the air")
	ok(not nr["ok"] and m.undo.size() == u2 and JSON.stringify(m.B.state()) == b2, "12c a refused phrase: no change, no undo step")
	stand(m.B)
	var pw: Dictionary = m._pose_words("bend the left elbow 45")
	ok(pw["ok"] and is_equal_approx(snappedf((m.B.ang["lowerarm_l"] as Vector3).x, 0.01), 55.0) and not SupportPose.claims("bend the left elbow 45")
		and not SupportPose.claims("put the right hand on the left knee") and not SupportPose.claims("bend the left knee 60") and SupportPose.claims("on both knees"),
		"12d pose words untouched: 'bend the left elbow 45' reaches %.0f; not claimed: bend the left elbow 45 / put the right hand on the left knee / bend the left knee 60" % (m.B.ang["lowerarm_l"] as Vector3).x)
	m.ui_cmd.open()
	m.ui_cmd.box.text = "on both knees"
	m.ui_cmd._filter()
	var top: String = m.ui_cmd.shown[0]["name"]
	ok(top == "Pose: on both knees", "12e the S search offers '%s' first" % top)
	m.ui_cmd.hide()
	m.queue_free()
	print("SUPPORTS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
