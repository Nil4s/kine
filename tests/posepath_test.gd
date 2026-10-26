## godot --headless --path . -s tests/posepath_test.gd     (N008 PATH TO A POSE; scripts/pose_path.gd)
## BARS, written before measuring (the item's, docs/INNOVATIONS.md N008). Every number below is read by THIS test off the
## live body after it replays the returned steps through AgentTools (serve's `run`, one request per returned step); the
## planner's own "checks" are not trusted for any bar.
##   1 REACH: on 8 start -> target pairs (guard -> kick chamber, stand -> half kneel, half kneel -> stand, stand -> salute,
##     stand -> command_point, stand -> squat, stand -> "guard" (R21 pose search), stand -> "turn the hips left 40"),
##     after the replay every joint of Body.ORDER (52, fingers too) is within 1 deg of the target on bend, side and twist
##     (the target read independently: the pose file's numbers, or the words' named angle on the start pose). For the
##     hips-turn pair, whose words name no leg (the feet stay, the legs follow), the bar is the named joint (pelvis twist
##     40 within 1 deg) and every non-leg joint.
##   2 SAFE: between each two replayed states the straight line (angles and root), sampled so no joint moves more than
##     2 deg between samples: no joint past its limit (by > 0.01 deg); a PLANTED foot (on the floor, sole < 1 cm, at the
##     start, and its ankle and toe base within 1 cm of there at the end) stays within 1 cm (3D, ankle and toe base) of
##     where it began at every sample; no foot creeps more than 1 cm along the floor during a run of samples with its
##     sole on the floor (the toe base / ankle from where the run began); no part more than 1 cm under the floor; no
##     self-penetration deeper than 2 cm (feasible.gd PEN_FIX).
##   3 REFUSED: "bend the right knee to 170" and a pose file with thigh_l bend 150 come back with "blocked" naming
##     calf_r and thigh_l (and the axis), no steps, the body unchanged.
##   4 DETERMINISTIC: each of the 8 plans asked twice gives the identical JSON.
##   5 DRY: a plan leaves var_to_str(B.state()), the cards and the undo size exactly as they were.
##   6 SERVE + CLI: `path_to_pose {apply: true}` puts the live body on the target (within 1 deg, bar 1); the CLI
##     `path_to_pose - salute --json` exits 0 with steps and every check ok.
##   7 CONTROLS (added after the first pass, so bar 2 is known to be able to fail): bar 2's checker, fed by hand, flags
##     the straight guard -> kick chamber with no lift (a foot dragged > 1 cm), a stand whose root moves 3 cm and back
##     (a planted foot slides > 1 cm), and a guard with the fists 2.9 cm into each other (penetration > 2 cm).
extends SceneTree

var fails := 0
var m: Node
var T: AgentTools
var B: Body

const RES := 2.0
const BAR_DEG := 1.0
const BAR_SLIDE := 0.01
const ON := 0.01
const PEN := 0.02
const KNEEL := "user://posepath_kneel.json"
const SQUAT := "user://posepath_squat.json"
const PAST := "user://posepath_past.json"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func write_pose(path: String, set: Dictionary) -> void:
	var d := {"joints": {}, "offset": [0, 0, 0], "contacts": []}
	for j in Body.ORDER:
		var v: Vector3 = set.get(j, Vector3.ZERO)
		d["joints"][j] = {"bend": v.x, "side": v.y, "twist": v.z}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


func file_ang(path: String) -> Dictionary:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var out := {}
	for j in Body.ORDER:
		var x: Dictionary = d["joints"].get(j, {})
		out[j] = Vector3(float(x.get("bend", 0)), float(x.get("side", 0)), float(x.get("twist", 0)))
	return out


const STAND := {"upperarm_l": Vector3(0, -65, 0), "upperarm_r": Vector3(0, -65, 0), "lowerarm_l": Vector3(10, 0, 0), "lowerarm_r": Vector3(10, 0, 0)}


## the start poses, put straight on the live body (soles on the floor, as Body.ground)
func start(name: String) -> void:
	var a := STAND.duplicate()
	if name == "guard":   # fists up, elbows in, knees soft
		a.merge({"upperarm_l": Vector3(50, -60, -30), "upperarm_r": Vector3(50, -60, 30), "lowerarm_l": Vector3(120, 0, 0), "lowerarm_r": Vector3(120, 0, 0),
			"thigh_l": Vector3(10, 0, 0), "thigh_r": Vector3(10, 0, 0), "calf_l": Vector3(20, 0, 0), "calf_r": Vector3(20, 0, 0),
			"foot_l": Vector3(10, 0, 0), "foot_r": Vector3(10, 0, 0)}, true)
	if name == "kneel":
		a = file_ang(KNEEL)
	for j in Body.ORDER:
		B.ang[j] = a.get(j, Vector3.ZERO)
	B.offset = Vector3.ZERO
	B.fk()
	if name == "kneel":
		B.offset.y -= B.floor_shift()
		B.fk()
	else:
		B.ground()


func snap() -> Dictionary:
	return {"ang": (B.ang as Dictionary).duplicate(), "off": B.offset}


func put(s: Dictionary) -> void:
	for j in s["ang"]:
		B.ang[j] = s["ang"][j]
	B.offset = s["off"]
	B.fk()


func lerp_s(a: Dictionary, b: Dictionary, f: float) -> Dictionary:
	var o := {}
	for j in a["ang"]:
		o[j] = (a["ang"][j] as Vector3).lerp(b["ang"][j], f)
	return {"ang": o, "off": (a["off"] as Vector3).lerp(b["off"], f)}


func maxd(a: Dictionary, b: Dictionary, only := []) -> Array:
	var d := 0.0
	var at := ""
	for j in a:
		if not only.is_empty() and not j in only:
			continue
		var v: Vector3 = (a[j] as Vector3) - (b[j] as Vector3)
		var e := maxf(absf(v.x), maxf(absf(v.y), absf(v.z)))
		if e > d:
			d = e
			at = j
	return [d, at]


## bar 2 on the replayed states: [limit past, planted slide, drag, under floor, penetration, samples, planted feet]
func safe(states: Array) -> Dictionary:
	put(states[0])
	var p0 := {}
	for sd in ["_l", "_r"]:
		p0[sd] = [B.P["foot" + sd], B.P["ball" + sd], B.foot_sole_low(sd) < ON]
	put(states[-1])
	var planted := []
	for sd in ["_l", "_r"]:
		if p0[sd][2] and ((B.P["foot" + sd] as Vector3) - (p0[sd][0] as Vector3)).length() < BAR_SLIDE and ((B.P["ball" + sd] as Vector3) - (p0[sd][1] as Vector3)).length() < BAR_SLIDE:
			planted.append(sd)
	var w := {"past": 0.0, "slide": 0.0, "drag": 0.0, "under": 0.0, "pen": 0.0, "pair": "", "n": 0, "planted": planted}
	var run := {}
	for i in range(1, states.size()):
		var n := maxi(1, int(ceil(maxd(states[i - 1]["ang"], states[i]["ang"])[0] / RES)))
		for k in range(0 if i == 1 else 1, n + 1):
			put(lerp_s(states[i - 1], states[i], float(k) / n))
			w["n"] += 1
			for j in Body.ORDER:
				var v: Vector3 = B.ang[j]
				for q in 3:
					var r: Vector2 = B.lim[j][["bend", "side", "twist"][q]]
					w["past"] = maxf(w["past"], maxf(r.x - v[q], v[q] - r.y))
			for sd in planted:
				w["slide"] = maxf(w["slide"], maxf(((B.P["foot" + sd] as Vector3) - (p0[sd][0] as Vector3)).length(), ((B.P["ball" + sd] as Vector3) - (p0[sd][1] as Vector3)).length()))
			for sd in ["_l", "_r"]:
				var sole := B.foot_sole_low(sd)
				w["under"] = maxf(w["under"], -sole)
				if sole < ON:
					if not run.has(sd):
						run[sd] = [B.P["foot" + sd], B.P["ball" + sd]]
					for q in 2:
						var dv: Vector3 = (B.P[["foot", "ball"][q] + sd] as Vector3) - (run[sd][q] as Vector3)
						w["drag"] = maxf(w["drag"], Vector2(dv.x, dv.z).length())
				else:
					run.erase(sd)
			for j in Body.BODY:
				if (j as String).begins_with("foot") or (j as String).begins_with("ball"):
					continue
				w["under"] = maxf(w["under"], -(minf((B.P[j] as Vector3).y, (B.E[j] as Vector3).y) - float(B.rad.get(j, 0.03))))
			for c in B.contacts():
				if float(c[2]) > w["pen"]:
					w["pen"] = float(c[2])
					w["pair"] = "%s/%s" % [c[0], c[1]]
	return w


func plan(target: String, id: int, extra := {}) -> Dictionary:
	var p := {"target": target}
	p.merge(extra)
	return await T.request(id, "path_to_pose", p)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	T = AgentTools.new(m)
	B = m.B
	write_pose(KNEEL, {"thigh_l": Vector3(96, 0, 0), "calf_l": Vector3(96, 0, 0), "thigh_r": Vector3(5, 0, 0), "calf_r": Vector3(105, 0, 0),
		"ball_r": Vector3(50, 0, 0), "upperarm_l": Vector3(0, -65, 0), "upperarm_r": Vector3(0, -65, 0)})
	write_pose(SQUAT, {"thigh_l": Vector3(95, 0, 0), "thigh_r": Vector3(95, 0, 0), "calf_l": Vector3(115, 0, 0), "calf_r": Vector3(115, 0, 0),
		"foot_l": Vector3(20, 0, 0), "foot_r": Vector3(20, 0, 0), "spine_01": Vector3(15, 0, 0), "spine_02": Vector3(15, 0, 0),
		"upperarm_l": Vector3(70, -30, 0), "upperarm_r": Vector3(70, -30, 0)})
	write_pose(PAST, STAND.merged({"thigh_l": Vector3(150, 0, 0)}))
	var pairs := [["guard", "raise the right leg 90, bend the right knee 100"], ["stand", KNEEL], ["kneel", "stand"], ["stand", "salute"],
		["stand", "command_point"], ["stand", SQUAT], ["stand", "guard"], ["stand", "turn the hips left 40"]]
	var plans := []
	var id := 1
	for pr in pairs:
		start(pr[0])
		var s0 := snap()
		var st0 := var_to_str(B.state())
		var t0 := Time.get_ticks_msec()
		var r1: Dictionary = await plan(pr[1], id)
		var ms := Time.get_ticks_msec() - t0
		var dry1 := var_to_str(B.state()) == st0
		var r2: Dictionary = await plan(pr[1], id)
		plans.append({"pair": pr, "r": r1, "same": JSON.stringify(r1) == JSON.stringify(r2), "dry": dry1 and var_to_str(B.state()) == st0, "s0": s0, "ms": ms})
		id += 1
	# 1 + 2: replay each plan's steps, one `run` request per step, reading the body after each
	var bad1 := []
	var bad2 := []
	for pl in plans:
		var pr: Array = pl["pair"]
		var label := "%s -> %s" % [pr[0], String(pr[1]).get_file()]
		var r: Dictionary = pl["r"]
		if not r.has("result") or r["result"].has("blocked"):
			bad1.append("%s: no plan (%s)" % [label, r.get("error", r.get("result", {}).get("blocked", {}))])
			continue
		var res: Dictionary = r["result"]
		put(pl["s0"])
		var tr0 := Time.get_ticks_msec()
		var states := [snap()]
		var run_ok := true
		for st in res["steps"]:
			var rr: Dictionary = await T.request(100, "run", {"steps": st["run"]})
			if rr.has("error"):
				run_ok = false
				bad1.append("%s: step %d failed: %s" % [label, st["n"], rr["error"]["message"]])
				break
			states.append(snap())
		if not run_ok:
			continue
		# the target, read independently
		var want := {}
		var only := []
		var src := String(res["target"].get("pose", ""))
		if pr[1] == "guard":
			want = file_ang("res://poses/lib/guard_bat.json")
		elif FileAccess.file_exists(pr[1]):
			want = file_ang(pr[1])
		elif FileAccess.file_exists("res://poses/%s.json" % pr[1]):
			want = file_ang("res://poses/%s.json" % pr[1])
		else:
			want = (pl["s0"]["ang"] as Dictionary).duplicate()
			var ops: Array = PoseWords.parse(pr[1])["ops"]
			for op in ops:
				var v: Vector3 = want[op["joint"]]
				v[op["axis"]] = float(op["deg"]) if op["mode"] == "to" else v[op["axis"]] + float(op["deg"])
				want[op["joint"]] = v
			if pr[1].begins_with("turn the hips"):
				for j in Body.ORDER:
					if not (j.begins_with("thigh") or j.begins_with("calf") or j.begins_with("foot") or j.begins_with("ball")):
						only.append(j)
		var miss := maxd(B.ang, want, only)
		var rms := Time.get_ticks_msec() - tr0
		var tc0 := Time.get_ticks_msec()
		var w := safe(states)
		print("     replay %d ms, check %d ms" % [rms, Time.get_ticks_msec() - tc0])
		print("     %-34s %2d steps %4d ms  miss %.3f deg (%s)  past %.3f  planted %s slide %.2f cm  drag %.2f cm  under %.2f cm  pen %.2f cm %s  samples %d%s" % [
			label, res["steps"].size(), pl["ms"], miss[0], miss[1], w["past"], w["planted"], w["slide"] * 100, w["drag"] * 100, w["under"] * 100, w["pen"] * 100, w["pair"], w["n"],
			("   [" + src + "]") if src != "" else ""])
		if miss[0] > BAR_DEG:
			bad1.append("%s: %s %.2f deg off" % [label, miss[1], miss[0]])
		if w["past"] > 0.01 or w["slide"] > BAR_SLIDE or w["drag"] > BAR_SLIDE or w["under"] > BAR_SLIDE or w["pen"] > PEN:
			bad2.append(label)
	ok(bad1.is_empty() and plans.size() >= 6, "1 reach: %d pairs replayed, every joint within %.0f deg of the target%s" % [plans.size(), BAR_DEG, "" if bad1.is_empty() else ": " + str(bad1)])
	ok(bad2.is_empty() and bad1.is_empty(), "2 safe: no limit past, planted feet within 1 cm, no foot dragged > 1 cm, nothing > 1 cm under the floor, no penetration > 2 cm (every %.0f deg)%s" % [RES, "" if bad2.is_empty() else ": " + str(bad2)])

	# 3 refused
	var bad3 := []
	for q in [["bend the right knee to 170", "calf_r", "bend"], [PAST, "thigh_l", "bend"]]:
		start("stand")
		var st0 := var_to_str(B.state())
		var rr: Dictionary = await plan(q[0], 200)
		var res: Dictionary = rr.get("result", {})
		var bl: Dictionary = res.get("blocked", {})
		print("     refused '%s': %s" % [String(q[0]).get_file(), bl.get("why", rr)])
		if bl.get("joint", "") != q[1] or bl.get("axis", "") != q[2] or not (res.get("steps", [1]) as Array).is_empty() or var_to_str(B.state()) != st0 or not String(bl.get("why", "")).contains(q[1]):
			bad3.append(q[0])
	ok(bad3.is_empty(), "3 refused: past-the-range targets name calf_r / thigh_l, no steps, body unchanged%s" % ("" if bad3.is_empty() else ": " + str(bad3)))

	# 4 + 5
	var bad4 := plans.filter(func(p): return not p["same"]).map(func(p): return p["pair"])
	ok(bad4.is_empty(), "4 deterministic: %d plans asked twice, identical JSON%s" % [plans.size(), "" if bad4.is_empty() else ": " + str(bad4)])
	await T.request(300, "open", {"path": "scenes/combo3.json"})
	await T.step("card=2")
	var w0 := [var_to_str(B.state()), JSON.stringify(m.S.cards), m.undo.size()]
	var dr: Dictionary = await plan("salute", 301)
	var w1 := [var_to_str(B.state()), JSON.stringify(m.S.cards), m.undo.size()]
	var bad5 := plans.filter(func(p): return not p["dry"]).map(func(p): return p["pair"])
	ok(bad5.is_empty() and w0 == w1 and dr.has("result"), "5 dry: the body, the cards and the undo list unchanged by every plan (on combo3 card 2 too: %s, cli '%s...')" % [w0 == w1, String(dr.get("result", {}).get("cli", "")).left(40)])

	# 6 serve apply + CLI
	await T.request(401, "new", {})
	await T.step("remove_the_weapon")   # combo3's bat would go through the head in this guard (the planner refuses that)
	start("guard")
	var ar: Dictionary = await plan("raise the right leg 90, bend the right knee 100", 400, {"apply": true})
	var want6 := (B.ang as Dictionary).duplicate()
	var sok: bool = ar.has("result") and ar["result"]["applied"]
	if not sok:
		print("     apply: ", ar.get("result", ar).get("blocked", ar.get("error", "")))
	start("guard")
	var w6 := (B.ang as Dictionary).duplicate()
	w6["thigh_r"] = (w6["thigh_r"] as Vector3) + Vector3(90, 0, 0)
	w6["calf_r"] = (w6["calf_r"] as Vector3) + Vector3(100, 0, 0)
	var miss6 := maxd(want6, w6)
	var out := []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "tools/poser_cli.gd", "--",
		"path_to_pose", "-", "salute", "--json"], out, true)
	var last := ""
	for l in String("".join(out)).split("\n"):
		if l.begins_with("{\""):
			last = l
	var cj: Variant = JSON.parse_string(last) if last != "" else null
	var cok: bool = code == 0 and cj is Dictionary and cj["ok"] and (cj["steps"] as Array).size() > 0 and (cj["checks"] as Array).all(func(c): return c["ok"])
	ok(sok and miss6[0] <= BAR_DEG and cok, "6 serve apply: applied %s, live body %.3f deg from the target (%s); CLI path_to_pose - salute: exit %d, %s steps, checks ok %s" % [
		sok, miss6[0], miss6[1], code, (cj["steps"] as Array).size() if cj is Dictionary and cj.has("steps") else "-", cok])

	# 7 controls
	start("guard")
	var c0 := snap()
	var c1 := snap()
	c1["ang"]["thigh_r"] = (c1["ang"]["thigh_r"] as Vector3) + Vector3(90, 0, 0)
	c1["ang"]["calf_r"] = (c1["ang"]["calf_r"] as Vector3) + Vector3(100, 0, 0)
	var k1 := safe([c0, c1])
	start("stand")
	var d0 := snap()
	var d1 := snap()
	d1["off"] = (d1["off"] as Vector3) + Vector3(0.03, 0, 0)
	var k2 := safe([d0, d1, d0])
	start("stand")
	var e0 := snap()
	var e1 := snap()
	for x in [["upperarm_l", Vector3(45, -70, 0)], ["upperarm_r", Vector3(45, -70, 0)], ["lowerarm_l", Vector3(125, 0, 0)], ["lowerarm_r", Vector3(125, 0, 0)]]:
		e1["ang"][x[0]] = x[1]
	var k3 := safe([e0, e1])
	ok(k1["drag"] > BAR_SLIDE and k2["slide"] > BAR_SLIDE and k3["pen"] > PEN, "7 controls: straight chamber drags %.2f cm, root 3 cm out and back slides %.2f cm (planted %s), fists %.2f cm deep %s" % [
		k1["drag"] * 100, k2["slide"] * 100, k2["planted"], k3["pen"] * 100, k3["pair"]])

	print("POSEPATH: %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
	TestFiles.cleanup()
	quit(0 if fails == 0 else 1)
