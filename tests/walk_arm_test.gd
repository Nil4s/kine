## godot --headless --path . -s tests/walk_arm_test.gd [-- res://scenes/other.json]     (round 42, Nick 10-17)
## Nick: "the animation of walking ... has the arm literally rotate to inside body pointing backwards". The bat arm of
## walk_bat had the upper arm raised 72-81 deg with the elbow 21-26 cm ABOVE the wrist and the forearm pointing BACK into
## the chest. REAL PEOPLE resting a bat on the shoulder: the elbow hangs down by the ribs, the hand comes up in front of
## the shoulder, the forearm points forward and up (photos of batters walking to the plate; no paper measures it, so the
## bars are the shape, not a citation). Fixed by Body.ELBOW LOW in the cook (plans/walk_bat.json "elbow_low").
## Bars on every frame at 30 fps: upper arm raised < 35 deg from hanging, elbow below the wrist, forearm pointing forward
## (its forward component > 0.3); and the swing arm (left) never crosses in front of the body's midline.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	# both scenes that rest the bat on the shoulder (idle_bat had the same arm: raised 89 deg, elbow 27 cm over the wrist)
	var paths := ["res://scenes/walk_bat.json", "res://scenes/idle_bat.json"]
	var ua := OS.get_cmdline_user_args()
	if ua.size() > 0:
		paths = [ua[0]]
	for path in paths:
		one(path)
	print("WALK ARM TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)


func one(path: String) -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
	var n := int(S.length() * 30.0)
	var raise := 0.0
	var dh := -INF
	var fa := INF
	var cross := -INF
	for k in range(n + 1):
		S.apply(B, k / 30.0)
		var P: Dictionary = B.P
		var lat: Vector3 = (P["thigh_l"] - P["thigh_r"]).normalized()
		var fwd := lat.cross(Vector3.UP).normalized()
		var s0: Vector3 = P["upperarm_r"]
		var e: Vector3 = P["lowerarm_r"]
		var w: Vector3 = P["hand_r"]
		raise = maxf(raise, rad_to_deg((e - s0).angle_to(Vector3.DOWN)))
		dh = maxf(dh, e.y - w.y)
		fa = minf(fa, (w - e).normalized().dot(fwd))
		# the left hand's side of the midline (pelvis centre): + = still on his left
		var mid: Vector3 = (P["thigh_l"] + P["thigh_r"]) * 0.5
		cross = maxf(cross, -((P["hand_l"] as Vector3) - mid).dot(lat))
	print("     %s, %d frames" % [path, n + 1])
	ok(raise < 35.0, "the bat arm's upper arm is raised at most %.0f deg from hanging (bar < 35)" % raise)
	ok(dh < 0.0, "the bat arm's elbow stays below its wrist: at worst %+.2f m (bar < 0)" % dh)
	ok(fa > 0.3, "the bat arm's forearm points forward: smallest forward component %+.2f (bar > 0.3; < 0 = back into the chest)" % fa)
	ok(cross < 0.0, "the swinging left hand stays on his left of the midline: at worst %+.2f m across (bar < 0)" % cross)
