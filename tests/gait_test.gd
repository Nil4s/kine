## godot --headless --path . -s tests/gait_test.gd     (GATES XX8, #333; headless is fine)
## GAIT, against real walkers. The rule: on a walk (4+ alternating foot plants travelling 0.5 m or more, no flight) measure
## the step length over body height, the cadence, the arm swing (peak to peak) and the arm-leg counter-phase; WARN GAIT
## only outside the real range, with the measured number and the people number. REAL PEOPLE (all read this round):
## step length 0.415 +- 0.038 of height, 1.33 m/s, 21 young adults (Gait Posture 2009, PMID 19502061); cadence 105.5 +- 5.2
## steps/min at 1.21 m/s (PMID 29775941) and 108 +- 7 at 1.4 m/s (PMID 41879248); arm swing 28.6 / 33.1 +- 11 deg peak to
## peak at 4 km/h (PMID 40291287) and a median 25.3 / 25.7 deg in healthy controls (PMID 23236504); arms out of phase at
## walking speed, 1:1 with the legs (Kubo et al. 2004, PMID 15351887). Checked: a synthetic walk with the people numbers says
## nothing; half the cadence, a double step, no arm swing, arms with the same-side leg each give ONE WARN naming the number;
## a run and a stand are not walks; the shipped non-walk scenes say nothing; walk_bat is printed beside the bars.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## a synthetic sample of a walk: `step` m per step, `cad` steps/min, `arm` deg peak to peak, `phase` +1 = counter-phase
## (people), -1 = the arm with its own leg; `fly` = true lifts both feet off the floor between plants (a run)
func walk(step: float, cad: float, arm: float, phase := 1.0, fly := false, n_steps := 8, armed := false) -> Dictionary:
	var T := 60.0 / cad          # one step
	var stride := 2.0 * T
	var n := int(ceil((n_steps + 1) * T * 60.0)) + 1
	var lead := 2.0 * T          # the first two steps are the start-up: the feet begin in a consistent walk
	var t := []
	var bl := []
	var br := []
	var ga := []
	for i in n:
		var tt := i / 60.0 + lead
		t.append(i / 60.0)
		var pl := _foot(tt, 0.0, step, stride, fly)
		var pr := _foot(tt, T, step, stride, fly)
		bl.append(pl)
		br.append(pr)
		var ph := TAU * tt / stride
		var leg := deg_to_rad(20.0) * cos(ph)
		var a := deg_to_rad(arm / 2.0) * cos(ph) * -phase
		ga.append([Vector3(sin(a), -cos(a), 0), Vector3(sin(-a), -cos(a), 0), Vector3(sin(leg), -cos(leg), 0), Vector3(sin(-leg), -cos(leg), 0), 1.56])
	return {"t": t, "ball_l": bl, "ball_r": br, "gait": ga, "armed": armed}


## one ball: planted at x = k * 2 step (+ offset) for 1.2 T (or 0.7 T flying), then swinging to the next plant
func _foot(tt: float, off: float, step: float, stride: float, fly: bool) -> Vector3:
	var T := stride / 2.0
	var u := tt - off
	var k := floorf(u / stride)
	var local := u - k * stride
	var stance := (0.7 if fly else 1.2) * T
	var x0 := (k * 2.0 + (1.0 if off > 0.0 else 0.0)) * step
	if local < stance:
		return Vector3(x0, 0.0, 0.0)
	var s := (local - stance) / (stride - stance)
	var e := s * s * (3.0 - 2.0 * s)
	return Vector3(x0 + 2.0 * step * e, (0.12 if fly else 0.0) + 0.12 * sin(PI * s), 0.0)


func found(sm: Dictionary) -> Array:
	return Rulebook.rule_gait(sm)


func say(label: String, g: Dictionary) -> void:
	if not g["walk"]:
		print("%s: not a walk (%s)" % [label, g["why"]])
		return
	print("%s: step %.3f x height (%.2f m of %.2f; people 0.415 +- 0.038, bar %.2f-%.2f) | cadence %.0f/min (people 105-108, bar %.0f-%.0f) | arm swing %.0f deg (people 25-33, bar %.0f-%.0f) | arm vs same-side thigh r %.2f (people < 0, bar < %.1f) | %d steps %.2f-%.2f s" % [
		label, g["step"], g["step_m"], g["height"], Rulebook.GAIT_STEP[0], Rulebook.GAIT_STEP[1], g["cad"], Rulebook.GAIT_CAD[0], Rulebook.GAIT_CAD[1],
		g["arm"], Rulebook.GAIT_ARM[0], Rulebook.GAIT_ARM[1], g["phase"], Rulebook.GAIT_PHASE, g["steps"], g["t0"], g["t1"]])


func one(f: Array, word: String) -> bool:
	return f.size() == 1 and f[0]["sev"] == "WARN" and f[0]["rule"] == "GAIT" and (f[0]["msg"] as String).contains(word)


func _init() -> void:
	# a people walk: step 0.415 x (1.56 + 0.14 = 1.70 m) = 0.71 m, 108/min, 30 deg of arm swing against the legs
	var good := walk(0.415 * 1.70, 108.0, 30.0)
	var g := Rulebook.gait(good)
	say("PEOPLE WALK", g)
	print("   plants [frame, foot, x]: ", g["seq"].map(func(p): return [p[0], p[1], snappedf((p[2] as Vector3).x, 0.01)]))
	ok(g["walk"] and absf(g["step"] - 0.415) < 0.03 and absf(g["cad"] - 108.0) < 4.0 and absf(g["arm"] - 30.0) < 2.0 and g["phase"] < -0.8, "the synthetic people walk measures back its own numbers (step, cadence, arm, phase)")
	ok(found(good).is_empty(), "  no GAIT on a walk inside the real range %s" % [found(good).map(func(x): return x["msg"])])
	# half the cadence
	var slow := walk(0.415 * 1.70, 54.0, 30.0)
	say("HALF CADENCE", Rulebook.gait(slow))
	var f := found(slow)
	ok(one(f, "cadence 5") and absf(Rulebook.gait(slow)["cad"] - 54.0) < 3.0, "  half the cadence: ONE WARN naming the cadence (54) %s" % [f.map(func(x): return x["msg"])])
	if f.size() == 1:
		print("   ", f[0]["msg"])
		ok((f[0]["msg"] as String).contains("105-108"), "  and the people number")
	# a double step
	var big := walk(2.0 * 0.415 * 1.70, 108.0, 30.0)
	say("DOUBLE STEP", Rulebook.gait(big))
	f = found(big)
	ok(one(f, "steps 83%") and absf(Rulebook.gait(big)["step"] - 0.83) < 0.05, "  a 2x step: ONE WARN naming the step (0.83 of height) %s" % [f.map(func(x): return x["msg"])])
	if f.size() == 1:
		print("   ", f[0]["msg"])
		ok((f[0]["msg"] as String).contains("41.5%"), "  and the people number")
	# no arm swing, and arms with their own leg
	f = found(walk(0.415 * 1.70, 108.0, 2.0))
	ok(one(f, "arm swing 2°"), "  no arm swing (2 deg): ONE WARN naming it")
	var march := walk(0.415 * 1.70, 108.0, 30.0, -1.0)
	say("MARCH", Rulebook.gait(march))
	f = found(march)
	ok(one(f, "WITH its own leg"), "  each arm with its own leg: ONE WARN (r %.2f)" % Rulebook.gait(march)["phase"])
	# arms are not judged with a weapon in the hands
	ok(found(walk(0.415 * 1.70, 108.0, 2.0, 1.0, false, 8, true)).is_empty(), "  armed: a still arm says nothing")
	# a run, a stand, too few steps
	var run := walk(0.9 * 1.70, 170.0, 60.0, 1.0, true)
	var gr := Rulebook.gait(run)
	say("RUN", gr)
	ok(not gr["walk"] and found(run).is_empty(), "a run (both feet in the air) is not judged as a walk")
	var still := []
	for i in 120:
		still.append(Vector3.ZERO)
	var stand := {"t": good["t"].slice(0, 120), "ball_l": still, "ball_r": still, "gait": good["gait"].slice(0, 120)}
	ok(found(stand).is_empty(), "a sample with no steps: nothing")
	ok(found(walk(0.415 * 1.70, 108.0, 30.0, 1.0, false, 2)).is_empty(), "two steps are not a walk")
	ok(Rulebook.rule_gait({"t": [0.0]}).is_empty(), "a sample without the series: nothing")
	# the shipped scenes
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	var n := 0
	for fn in ["bo_spin.json", "combo3.json", "dodge_side.json", "hit_react.json", "idle_bat.json", "strike_legs.json", "swing_back.json", "swing_fore.json", "thrust.json"]:
		var Sc := Scene.new()
		Sc.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/" + fn)))
		var sm := Rulebook.sample(Sc, B)
		var gg := Rulebook.gait(sm)
		var c := Rulebook.check(Sc, B, sm).filter(func(x): return x["rule"] == "GAIT").size()
		n += c
		print("  %s: %s" % [fn, ("WALK step %.2f cad %.0f" % [gg["step"], gg["cad"]]) if gg["walk"] else "not a walk (" + gg["why"] + ")"])
	ok(n == 0, "shipped non-walk scenes (9): %d GAIT findings" % n)
	# walk_bat, read only, beside the bars
	var W := Scene.new()
	W.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/walk_bat.json")))
	var sw := Rulebook.sample(W, B)
	var gw := Rulebook.gait(sw)
	say("WALK_BAT", gw)
	if gw["walk"]:
		print("   plants [frame, foot, z]: ", gw["seq"].map(func(p): return [p[0], p[1], snappedf((p[2] as Vector3).z, 0.01)]))
	var fw := Rulebook.check(W, B, sw).filter(func(x): return x["rule"] == "GAIT")
	print("WALK_BAT findings: %s" % [fw.map(func(x): return x["msg"])])
	ok(gw["walk"], "walk_bat is read as a walk (%s)" % gw.get("why", "yes"))
	ok(Rulebook.SRC.has("GAIT") and Rulebook.WHY.has("GAIT") and Rulebook.URL.has("GAIT"), "GAIT has its SRC, WHY and URL")
	print("GAIT TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
