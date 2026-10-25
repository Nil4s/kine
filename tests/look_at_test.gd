## godot --headless --path . -s tests/look_at_test.gd     (GATES XX6; headless is fine)
## LOOK AT. REAL PEOPLE: Freedman & Sparks 1997 (https://pubmed.ncbi.nlm.nih.gov/9163361/, rhesus, head free): no head
## movement for gaze shifts under 20 deg with the eyes centred; from 25 to 90 deg the head's part grows linearly; the
## eye's part saturates near 35 deg. Human numbers: not read (UNVERIFIED). The mannequin has NO eye joint, so by default
## the whole shift goes to the neck and head; with eyes := true the curve above applies and the eye offset is returned.
extends SceneTree

var fails := 0
var n_ok := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if c:
		n_ok += 1
	else:
		fails += 1


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


## a target `deg` away from the current forward, `dist` m from the eye, yaw (to his left, +x) and pitch (up)
func target_at(B: Body, yaw: float, pitch: float, dist := 2.0) -> Vector3:
	var d := Vector3(sin(deg_to_rad(yaw)) * cos(deg_to_rad(pitch)), sin(deg_to_rad(pitch)), cos(deg_to_rad(yaw)) * cos(deg_to_rad(pitch)))
	return LookAt.eye_point(B) + d * dist


func _init() -> void:
	var B := body()
	var f0 := LookAt.head_forward(B)
	print("rest forward %s (should be +Z)" % f0)
	ok(f0.angle_to(Vector3(0, 0, 1)) < 0.01, "rest head forward is +Z: %.4f deg off" % rad_to_deg(f0.angle_to(Vector3(0, 0, 1))))

	# straight ahead: pose unchanged
	var s0 := JSON.stringify(B.state())
	var r := LookAt.solve(B, target_at(B, 0, 0))
	ok(JSON.stringify(B.state()) == s0, "target straight ahead: pose unchanged (amp %.4f deg, error %.4f)" % [r["amp"], r["error"]])

	# reachable shifts hit within 0.5 deg (no eyes: all to neck and head)
	for c in [[20, 0], [-30, 10], [45, -15], [60, 20], [-55, 5], [0, 25], [0, -20]]:
		var Bx := body()
		var t := target_at(Bx, c[0], c[1])
		var rr := LookAt.solve(Bx, t)
		var seen := rad_to_deg(LookAt.head_forward(Bx).angle_to((t - LookAt.eye_point(Bx)).normalized()))
		ok(rr["error"] <= 0.5 and seen <= 0.5 and rr["reachable"], "yaw %d pitch %d: gaze error %.3f deg (bar 0.5), head+neck turned %.1f of %.1f" % [c[0], c[1], seen, rr["head_deg"], rr["amp"]])
		for j in ["neck_01", "head"]:
			var a: Vector3 = Bx.ang[j]
			var L = Bx.lim[j]
			ok(a.x >= L["bend"].x - 0.01 and a.x <= L["bend"].y + 0.01 and a.y >= L["side"].x - 0.01 and a.y <= L["side"].y + 0.01 and a.z >= L["twist"].x - 0.01 and a.z <= L["twist"].y + 0.01, "  %s inside its limits: %s" % [j, a])

	# beyond the joints' reach: the error is REPORTED
	var Bu := body()
	var ru := LookAt.solve(Bu, target_at(Bu, 150, 0))
	ok(ru["error"] > 0.5 and not ru["reachable"], "target 150 deg to the side (neck+head reach ~75): not reachable, error reported %.1f deg" % ru["error"])
	ok(absf(Bu.ang["head"].z) <= 35.01 and absf(Bu.ang["neck_01"].z) <= 40.01, "  and the joints stayed in limits: head twist %.1f neck twist %.1f" % [Bu.ang["head"].z, Bu.ang["neck_01"].z])

	# eyes := true. small shift: the head does not move
	var Be := body()
	var se := JSON.stringify(Be.state())
	var re := LookAt.solve(Be, target_at(Be, 15, 5), true)
	ok(JSON.stringify(Be.state()) == se and re["head_deg"] == 0.0, "eyes, shift %.1f deg (< %.0f eye-only): head moved %.3f deg (bar 0), eye yaw %.1f pitch %.1f" % [re["amp"], LookAt.EYE_ONLY, re["head_deg"], re["eye_yaw"], re["eye_pitch"]])
	ok(re["error"] <= 0.5, "  eye alone reaches it, error %.3f" % re["error"])
	# large shifts: head part vs the source's curve
	for amp in [25, 40, 60, 75, 90]:
		var Bl := body()
		var rl := LookAt.solve(Bl, target_at(Bl, amp, 0), true)
		var want := LookAt.head_part(amp)
		var eye_part: float = rl["amp"] - rl["head_deg"]
		print("     amp %d: head %.1f deg (curve %.1f), share %.0f %%, eye %.1f deg (source: eye saturates ~35)" % [amp, rl["head_deg"], want, rl["share"] * 100.0, eye_part])
		ok(absf(rl["head_deg"] - want) <= 1.0 and eye_part <= 35.5 and rl["error"] <= 0.5, "amp %d: head %.1f vs curve %.1f (+-1), eye %.1f <= 35.5, error %.2f" % [amp, rl["head_deg"], want, eye_part, rl["error"]])
	var B90 := body()
	var r90 := LookAt.solve(B90, target_at(B90, 90, 0), true)
	ok(r90["share"] >= 0.5 and r90["share"] <= 0.7, "head share at 90 deg %.0f %% (source-derived 61 %%, range 50-70)" % (r90["share"] * 100.0))

	# a scene without look-at is untouched: the module is only called from a command, nothing in Body changed
	var Bz := body()
	ok(JSON.stringify(Bz.state()) == JSON.stringify(body().state()), "a body nobody told to look is the same as a fresh one")

	print("LOOK AT TEST %s %d (ok %d)" % ["PASS" if fails == 0 else "FAIL", fails, n_ok])
	TestFiles.cleanup()
	quit(fails)
