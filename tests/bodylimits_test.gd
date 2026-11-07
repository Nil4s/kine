## godot --headless --path . -s tests/bodylimits_test.gd     (L97: N030 jump budget, N032 grip hold check; scripts/body_limits.gd)
## SOURCES (each number below is the one the bars use):
##  * Jump norm: Lin, Goldstein & Schroeder 2025, "Sex- and Sport-Specific Differences in Jump Strategies: Key Qualities for Jump Performance",
##    Sports 13(9):292, doi 10.3390/sports13090292, Table 2, 38 NCAA Division I male basketball / volleyball players, countermovement jump on force
##    plates: relative concentric MEAN power 29.72 +- 4.00 W/kg (peak power 57.11 +- 6.51 W/kg). A push's mean power is what a COM track gives
##    (work over the push time), so the MEAN column is the norm. "Elite" = that mean; the top of the elite range = mean + 2 SD = 37.72 W/kg.
##  * Grip norm: Dodds et al. 2014, "Grip strength across the life course: normative data from twelve British studies", PLoS ONE 9(12):e113637,
##    doi 10.1371/journal.pone.0113637: peak median grip, men 51 kg (ages 29-39), women 31 kg (ages 26-42) = 500.2 N and 304.0 N.
##  * Friction of the hand on a handle MU = 0.8: DisarmTruth.MU (scripts/disarm_truth.gd, its stated assumption: leather on wood).
##  * Weapon force on the hand: Newton, F = m * |a_com| (the centripetal m w^2 r plus the tangential m alpha r, as a vector sum). Gravity is left
##    out, as in I30 (scripts/weapon_torque.gd): this is the force the SWING needs.
## Bars (stated before any implementation; none was changed after a run):
##  1 JUMP MODEL  a planted jump (COM track, 60 Hz, constant push acceleration from the lowest point, then free flight) with known apex h, push
##    rise d and push time t = 0.30 s: the mean push power equals m g (h + d) / t within 3 % (the work is the kinetic energy at take-off,
##    m g h, plus the potential energy gained while pushing, m g d; with d = 0 this is the plain m g h / t). Written here independently.
##    Also: apex within 3 cm of h, t_push within 1 frame, the push frames [lowest point, take-off] within 1 frame of the planted ones.
##  2 NORMS       a 0.5 m CMJ (d 0.470 m) reads inside the elite range (<= 37.72 W/kg, not flagged); a 1.5 m CMJ (d 0.814 m) is flagged and reads
##    more than 1.5x the elite mean (29.72 W/kg); the message says "x an elite vertical jump"
##  3 CONTROL     a COM track with no flight (standing, and a walk-like bob) reports "no jump" with ok true and no flag; a drop (flight with
##    no upward take-off) is no jump either
##  4 GRIP FORCE  a 1.2 kg sword at 20 rad/s, COM 0.9 m from the hand: the required force is m w^2 r = 432 N within 3 %; the grip squeeze
##    needed is that / 0.8, compared with 500.2 N (men)
##  5 SLIP FRAME  a swing that speeds up at 30 rad/s^2 is flagged (slip) at the first frame where m r sqrt(w^4 + alpha^2) / 0.8 reaches 500.2 N
##    (found here by scanning the analytic formula), within 1 frame; a slow swing (6 rad/s^2, 1 s) is not flagged; the women's norm flags
##    earlier than the men's
##  6 READ-ONLY   on scenes/swing_fore.json and walk_bat.json: the scene dictionary and the body state are byte-identical after the checks, the
##    tools add no undo step, and two runs give byte-identical results
##  7 TOOLS       jump_budget and grip_hold are agent tools (AgentTools.MCP_EXTRA, tools/mcp/poser_mcp.py) and answer through BodyLimits.serve;
##    grip_hold with {mass, omega, radius} returns m w^2 r
extends SceneTree

var fails := 0
const F := 60.0
const G := 9.81
const MASS := 75.0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## a planted jump: rest n0 frames at y0, a constant upward push acceleration for t_push, free flight until the COM is back at its take-off
## height, then rest. Returns {"com": [Vector3], "start": frame, "take": frame, "d", "h"}
func jump_track(h: float, t_push: float, n0 := 30) -> Dictionary:
	var v := sqrt(2.0 * G * h)
	var a := v / t_push
	var d := 0.5 * a * t_push * t_push
	var com := []
	for i in n0:
		com.append(Vector3(0, 1.0, 0))
	var np := int(round(t_push * F))
	for k in range(1, np + 1):
		var t := k / F
		com.append(Vector3(0, 1.0 + 0.5 * a * t * t, 0))
	var y1 := 1.0 + d
	var nf := int(ceil(2.0 * v / G * F))
	for k in range(1, nf + 1):
		var t := k / F
		com.append(Vector3(0, maxf(y1 + v * t - 0.5 * G * t * t, y1), 0))
	for i in 30:
		com.append(Vector3(0, y1, 0))
	return {"com": com, "start": n0 - 1 + 0, "take": n0 - 1 + np, "d": d, "h": h}


func _init() -> void:
	# 1 the model
	var J5 := jump_track(0.5, 0.30)
	var r5: Dictionary = BodyLimits.jump_budget(J5["com"], MASS)
	var model5 := MASS * G * (0.5 + float(J5["d"])) / 0.30
	print("     0.5 m jump: ", r5.get("msg", ""), "  model ", snappedf(model5, 0.1), " W")
	ok(r5.get("ok", false) and r5.get("jump", false) and absf(float(r5["power_w"]) - model5) <= 0.03 * model5,
		"1 power %.0f W vs the m g (h+d)/t model %.0f W (%.2f %%, <= 3)" % [float(r5.get("power_w", 0)), model5, 100.0 * absf(float(r5.get("power_w", 0)) - model5) / model5])
	var d0 := MASS * G * 0.5 / 0.30   # the plain m g h / t, printed beside the model so the push-rise term is visible
	print("     (the plain m g h / t would be %.0f W: %.0f %% of the work is the push rise)" % [d0, 100.0 * (1.0 - d0 / model5)])
	ok(absf(float(r5.get("apex_h", 9)) - 0.5) <= 0.03 and absf(float(r5.get("t_push", 9)) - 0.30) <= 1.0 / F + 1e-6
		and absi(int(r5.get("push_start", -9)) - int(J5["start"])) <= 1 and absi(int(r5.get("takeoff", -9)) - int(J5["take"])) <= 1,
		"1 apex %.3f m, t_push %.3f s, push frames %d..%d (planted %d..%d, +-1)" % [r5.get("apex_h", 0), r5.get("t_push", 0), r5.get("push_start", -1), r5.get("takeoff", -1), J5["start"], J5["take"]])
	# 2 norms
	var J15 := jump_track(1.5, 0.30)
	var r15: Dictionary = BodyLimits.jump_budget(J15["com"], MASS)
	var model15 := MASS * G * (1.5 + float(J15["d"])) / 0.30
	print("     1.5 m jump: ", r15.get("msg", ""))
	ok(r5.get("jump", false) and float(r5["w_per_kg"]) <= 37.72 and not r5["flag"],
		"2 the 0.5 m CMJ needs %.1f W/kg = %.2fx the elite mean 29.72: inside the elite range (<= 37.72), not flagged" % [r5.get("w_per_kg", 0), r5.get("ratio", 0)])
	ok(r15.get("flag", false) and float(r15["ratio"]) > 1.5 and absf(float(r15["power_w"]) - model15) <= 0.03 * model15 and String(r15["msg"]).contains("x an elite vertical jump"),
		"2 the 1.5 m CMJ needs %.1f W/kg = %.2fx elite (> 1.5), flagged at frames %d..%d" % [r15.get("w_per_kg", 0), r15.get("ratio", 0), r15.get("push_start", -1), r15.get("takeoff", -1)])
	# 3 control
	var still := []
	for i in 120:
		still.append(Vector3(0, 1.0, 0))
	var bob := []
	for i in 120:
		bob.append(Vector3(0, 1.0 + 0.02 * sin(i / F * TAU * 1.8), 0))
	var drop := []
	for i in 30:
		drop.append(Vector3(0, 2.0, 0))
	for k in 40:
		drop.append(Vector3(0, 2.0 - 0.5 * G * pow(k / F, 2.0), 0))
	var c1: Dictionary = BodyLimits.jump_budget(still, MASS)
	var c2: Dictionary = BodyLimits.jump_budget(bob, MASS)
	var c3: Dictionary = BodyLimits.jump_budget(drop, MASS)
	ok(c1["ok"] and not c1["jump"] and not c1["flag"] and String(c1["msg"]).contains("no jump") and not c2["jump"] and String(c2["msg"]).contains("no jump"),
		"3 CONTROL standing and a 2 cm bob: '%s' / '%s'" % [c1["msg"], c2["msg"]])
	ok(c3["ok"] and not c3["jump"] and not c3["flag"], "3 CONTROL a drop with no take-off is no jump: '%s'" % c3["msg"])
	# 4 grip force
	var m := 1.2
	var rr := 0.9
	var circ := []
	for i in 90:
		var th := 20.0 * i / F
		circ.append(Vector3(rr * cos(th), rr * sin(th), 0))
	var g4: Dictionary = BodyLimits.grip_hold(circ, m)
	var expect := m * 20.0 * 20.0 * rr
	ok(g4["ok"] and absf(float(g4["peak_n"]) - expect) <= 0.03 * expect, "4 the force %.1f N vs m w^2 r = %.1f N (%.2f %%, <= 3)" % [g4.get("peak_n", 0), expect, 100.0 * absf(float(g4.get("peak_n", 0)) - expect) / expect])
	print("     ", g4.get("msg", ""))
	# 5 slip frame
	var alpha := 30.0
	var ramp := ramp_track(alpha, 90, rr)
	var g5: Dictionary = BodyLimits.grip_hold(ramp, m)
	var thr := 51.0 * 9.80665 * 0.8   # the force at which the squeeze needed reaches the male norm
	var want := -1
	for i in 90:
		var t := i / F
		var w := alpha * t
		if m * rr * sqrt(pow(w, 4.0) + alpha * alpha) >= thr:
			want = i
			break
	ok(g5["slip"] and absi(int(g5["slip_frame"]) - want) <= 1, "5 the over-fast swing slips at frame %d, analytic %d (within 1)" % [g5.get("slip_frame", -1), want])
	var g6: Dictionary = BodyLimits.grip_hold(ramp_track(6.0, 60, rr), m)
	ok(g6["ok"] and not g6["slip"] and int(g6["slip_frame"]) == -1, "5 the slow swing is not flagged (peak %.0f N, needs %.0f N squeeze)" % [g6.get("peak_n", 0), g6.get("grip_need_n", 0)])
	var gw: Dictionary = BodyLimits.grip_hold(ramp, m, "female")
	ok(gw["slip"] and int(gw["slip_frame"]) < int(g5["slip_frame"]), "5 the women's norm (304 N) slips earlier: frame %d < %d" % [gw.get("slip_frame", -1), g5.get("slip_frame", -1)])
	# 6 read only, on real scenes
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	var stub := GDScript.new()
	stub.source_code = "extends Node\nvar S\nvar B\nvar undo := []\nfunc _push_undo() -> void:\n\tundo.append(1)\n"
	stub.reload()
	var node: Node = stub.new()
	for path in ["res://scenes/swing_fore.json", "res://scenes/walk_bat.json"]:
		var S := Scene.new()
		S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
		node.S = S
		node.B = B
		var sd0 := JSON.stringify(S.to_dict(B))
		var bs0 := JSON.stringify(B.state())
		var u0: int = node.undo.size()
		var a1: Dictionary = BodyLimits.serve("jump_budget", node, {})
		var a2: Dictionary = BodyLimits.serve("grip_hold", node, {})
		var a1b: Dictionary = BodyLimits.serve("jump_budget", node, {})
		var a2b: Dictionary = BodyLimits.serve("grip_hold", node, {})
		var same: bool = JSON.stringify(S.to_dict(B)) == sd0 and JSON.stringify(B.state()) == bs0 and node.undo.size() == u0
		ok(a1["ok"] and a2["ok"] and same and JSON.stringify(a1) == JSON.stringify(a1b) and JSON.stringify(a2) == JSON.stringify(a2b),
			"6 %s read-only (scene + body byte-identical, %d undo steps) and deterministic" % [path.get_file(), node.undo.size() - u0])
		print("     ", path.get_file(), "  jump: ", a1["result"].get("msg", ""), "  grip: ", a2["result"].get("msg", ""))
		if path.ends_with("walk_bat.json"):
			ok(not a1["result"]["jump"], "3 CONTROL the real walk has no jump")
		else:
			ok(a2["result"].get("has_weapon", false) and float(a2["result"].get("peak_n", 0)) > 0.0, "6 the real swing is read: peak %.0f N at frame %d" % [a2["result"].get("peak_n", 0), a2["result"].get("peak_frame", -1)])
	# 7 tools
	var at := FileAccess.get_file_as_string("res://scripts/agent_tools.gd")
	var py := FileAccess.get_file_as_string("res://tools/mcp/poser_mcp.py")
	var direct: Dictionary = BodyLimits.serve("grip_hold", node, {"mass": 1.2, "omega": 20.0, "radius": 0.9})
	ok(at.contains("\"jump_budget\"") and at.contains("\"grip_hold\"") and py.contains("\"jump_budget\"") and py.contains("\"grip_hold\"")
		and direct["ok"] and absf(float(direct["result"]["force_n"]) - 432.0) <= 0.01, "7 both tools are registered; grip_hold {1.2 kg, 20 rad/s, 0.9 m} = %.1f N" % direct.get("result", {}).get("force_n", 0))
	print("bodylimits_test: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit(0 if fails == 0 else 1)


## the COM of a weapon swung about the origin at radius r with angular speed w = alpha t (theta = alpha t^2 / 2), n frames
func ramp_track(alpha: float, n: int, r: float) -> Array:
	var out := []
	for i in n:
		var t := i / F
		var th := 0.5 * alpha * t * t
		out.append(Vector3(r * cos(th), r * sin(th), 0))
	return out
