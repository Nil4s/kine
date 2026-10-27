extends SceneTree
## godot --headless --path . -s tests/hinge_test.gd     (C3 HINGE: scripts/build/part.gd hinge + hinge_sweep; needs the CAD DLL, else only bar 7 runs)
## A door: a leaf 800 x 40 x 2000 mm hinged on its z edge at the origin (the hinge's body 0), a stop wall 3200 x 10 x 2000 mm across the
## leaf's path at y = c (mm). The swing is linear, 0 -> 90 deg in 3 s, sampled at 25 fps (frame i = 1.2 i deg). Every number in the record is mm.
## Bars, written before measuring (closed forms, computed in the test from the geometry, never read back from the code):
##   1 REPLAY    the door with its hinge replays with no failed step; volume = leaf 0.064 m3 + stop 0.064 m3 within 1e-5 relative
##   2 STOP      the leaf's far corner (800, 20) reaches the stop face y = 400 at theta_s = asin(c / R) - phi, R = hypot(800, 20),
##               phi = atan2(20, 800): theta_s = 28.56 deg. The first frame at or past it is F = ceil(theta_s / 1.2) = 24
##   3 FRAME     the sweep's first interference frame is within 1 frame of F (at 25 fps), and its time is that frame's time
##   4 CLEAR     a stop at y = 810 (the leaf reaches y = 800 at 90 deg): no interference, first = -1, 0 frames hit
##   5 TIME      100 frames (a 3.96 s swing, the stop at 810): the whole sweep (replay included) runs under 2 s
##   6 ERRORS    a hinge naming body 5 (there are 2): the replay names the hinge, hinge_sweep answers ok false with the reason
##   7 NO DLL    Part.force_off: hinge_sweep answers ok false and says KineCAD (runs with or without the DLL)
##   8 RELEASE   the sweep frees every shape it made: KCad.live_count() is the same after it as before
## MUST NOT TOUCH (C3 collision, bars 9-11), the leaf and a box stop 100 mm apart at rest (stop face at y = 120; the leaf's top face is at y = 20):
##   9 PAIR      the pair (0, 1) on the hinge's list: the first touching frame is F2 +- 1, F2 = ceil(theta_c / 1.2) with
##               theta_c = asin(120 / R) - phi (the far corner (800, 20) reaches y = 120; the same geometry as bar 2): F2 = 6
##   10 GAP0     the distance of the pair at frame 0 is 100 mm +- 0.5 (the closed form: 120 - 20)
##   11 NOPAIR   the same door with no pair chosen: no red frames, no pair reported
## Nothing is written to disk.
const KCad := preload("res://scripts/kcad.gd")
const DOOR_W := 800.0
const DOOR_T := 40.0
const DOOR_H := 2000.0
const FPS := 25.0
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


## the door record: the leaf (body 0), the stop wall (body 1) at y = stop_y, and the hinge (f5) on body `body` with the given track
func door(stop_y: float, track: Array, body := 0, clear: Array = []) -> Dictionary:
	var rec := Part.make("Door")
	rec["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [0, -DOOR_T / 2], "b": [DOOR_W, DOOR_T / 2]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": DOOR_H, "both": false, "op": "new"},
		{"t": "sketch", "id": "f3", "name": "Sketch2", "plane": "front", "ents": [{"k": "rect", "a": [-1600, stop_y], "b": [1600, stop_y + 10]}], "dims": []},
		{"t": "extrude", "id": "f4", "name": "Extrude2", "sketch": "f3", "dist": DOOR_H, "both": false, "op": "new"},
		{"t": "hinge", "id": "f5", "name": "Hinge1", "body": body, "o": [0, 0, 0], "axis": [0, 0, 1], "track": track, "clear": clear},
	]
	return rec


func _init() -> void:
	var swing := [[0.0, 0.0], [3.0, 90.0]]
	var clear := door(810.0, swing)
	var stop := door(400.0, swing)

	# 7 NO DLL: the Part tools say why, whatever the kernel does
	var was_off := Part.force_off
	Part.force_off = true
	var nd := Part.hinge_sweep(stop, "f5", FPS)
	Part.force_off = was_off
	ok(not bool(nd["ok"]) and "KineCAD" in String(nd["why"]), "7 NO DLL: hinge_sweep ok false, says KineCAD: %s" % nd.get("why", ""))

	if not Part.available():
		print("SKIP 1-6, 8: the CAD kernel is not available (" + KCad.last_error() + ")")
		print("HINGE ", "PASS" if fails == 0 else "FAIL %d" % fails)
		quit(1 if fails > 0 else 0)
		return

	# 1 REPLAY: the timeline with the hinge is the rest pose, no failed step
	var rp := Part.replay(stop)
	var vol_want := DOOR_W * DOOR_T * DOOR_H * 1e-9 + 3200.0 * 10.0 * DOOR_H * 1e-9
	ok((rp["errors"] as Dictionary).is_empty() and absf(float(rp["volume"]) - vol_want) <= 1e-5 * vol_want,
			"1 REPLAY: no failed step, volume %.6f m3 (closed form %.6f)" % [float(rp["volume"]), vol_want])

	# 2 STOP: the analytic contact angle and frame
	var R := sqrt(DOOR_W * DOOR_W + (DOOR_T / 2) * (DOOR_T / 2))
	var phi := atan2(DOOR_T / 2, DOOR_W)
	var theta_s := rad_to_deg(asin(400.0 / R) - phi)
	var F := int(ceil(theta_s / 1.2 - 1e-9))
	ok(absf(theta_s - 28.56) < 0.01 and F == 24, "2 STOP: theta_s %.3f deg, first frame at or past it F = %d" % [theta_s, F])

	# 3 FRAME: the sweep finds the contact frame
	var sw := Part.hinge_sweep(stop, "f5", FPS)
	ok(bool(sw["ok"]) and absi(int(sw["first"]) - F) <= 1, "3 FRAME: first interference frame %d at %.2f s, %.2f deg (F = %d, within 1)" % [int(sw["first"]), float(sw["first_s"]), float(sw["deg_first"]), F])
	ok(absf(float(sw["first_s"]) - float(sw["first"]) / FPS) < 1e-9 and int(sw["frames"]) == 76 and int(sw["hit_frames"]) >= 1,
			"3 FRAME: %d frames sampled, %d overlap, first_s is that frame's time" % [int(sw["frames"]), int(sw["hit_frames"])])

	# 4 CLEAR: a stop the leaf never reaches
	var cl := Part.hinge_sweep(clear, "f5", FPS)
	ok(bool(cl["ok"]) and int(cl["first"]) == -1 and int(cl["hit_frames"]) == 0, "4 CLEAR: stop at 810 mm: first %d, %d frames hit" % [int(cl["first"]), int(cl["hit_frames"])])

	# 5 TIME: 100 frames, no contact
	var live0 := KCad.live_count()
	var long := door(810.0, [[0.0, 0.0], [3.96, 90.0]])
	var tm := Part.hinge_sweep(long, "f5", FPS)
	print("TIME 100 frames: %.3f s (%d frames)" % [float(tm["secs"]), int(tm["frames"])])
	ok(bool(tm["ok"]) and int(tm["frames"]) == 100 and float(tm["secs"]) < 2.0, "5 TIME: %d frames in %.3f s (bar < 2 s)" % [int(tm["frames"]), float(tm["secs"])])

	# 6 ERRORS: a hinge on a body the door does not have
	var bad := door(400.0, swing, 5)
	var be := Part.replay(bad)
	var bs := Part.hinge_sweep(bad, "f5", FPS)
	ok((be["errors"] as Dictionary).has("f5") and not bool(bs["ok"]) and "body 5" in String(bs["why"]),
			"6 ERRORS: replay: %s / sweep: %s" % [be["errors"], bs.get("why", "")])

	# 9-11 MUST NOT TOUCH: a box stop 100 mm off the leaf's rest face; the pair (0, 1) on the list
	var gap := door(120.0, swing, 0, [[0, 1]])
	var gs := Part.hinge_sweep(gap, "f5", FPS)
	var theta_c := rad_to_deg(asin(120.0 / R) - phi)
	var F2 := int(ceil(theta_c / 1.2 - 1e-9))
	var touch: Array = []
	var d0 := -1.0
	if bool(gs["ok"]) and (gs["pairs"] as Array).size() == 1:
		touch = (gs["pairs"][0] as Dictionary)["touch"]
		d0 = float((gs["pairs"][0] as Dictionary)["dist"][0])
	var first_touch := int(touch[0]) if not touch.is_empty() else -1
	ok(first_touch >= 0 and absi(first_touch - F2) <= 1, "9 PAIR: first touching frame %d (hand F2 = %d, theta_c %.3f deg, within 1); red: %s" % [first_touch, F2, theta_c, gs.get("red_text", "")])
	ok(absf(d0 - 100.0) <= 0.5, "10 GAP0: distance at frame 0 = %.3f mm (100 within 0.5)" % d0)
	var np := Part.hinge_sweep(door(120.0, swing), "f5", FPS)
	ok(bool(np["ok"]) and (np["red"] as Array).is_empty() and (np["pairs"] as Array).is_empty() and int(np["hit_frames"]) >= 1,
			"11 NOPAIR: no pair chosen: %d red frames, %d pairs (the stop is still hit: %d frames)" % [(np["red"] as Array).size(), (np["pairs"] as Array).size(), int(np["hit_frames"])])

	# 8 RELEASE: the sweeps freed everything they made
	ok(KCad.live_count() == live0, "8 RELEASE: live shapes %d before, %d after" % [live0, KCad.live_count()])
	KCad.release_all()

	print("HINGE ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
