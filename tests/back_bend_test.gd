## godot --headless --path . -s tests/back_bend_test.gd     (round 43, GATES YY4)
## THE BACK, ONE BEND: Body.back_bend shares forward / side / twist over spine_01..03, neck_01 and head by each joint's
## range. Bars, on every axis and at asks across the range: the five joints sum to the ask (1e-4) and read back as it
## (back_of); each joint stays inside its limits; at the range's ends EVERY joint is at its own limit (they arrive
## together: no joint kinks first); each joint's share = its limit / the sum (1e-4); the other two axes are untouched;
## asking again for what back_of reads changes nothing (1e-6). Printed beside people (Apti et al. 2023).
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	for axis in ["bend", "side", "twist"]:
		var ai: int = Body.BACK_AXIS[axis]
		var r := B.back_range(axis)
		var sum_ok := true
		var lim_ok := true
		var share_ok := true
		var other_ok := true
		var again_ok := true
		for u in [-1.0, -0.5, -0.1, 0.0, 0.25, 0.7, 1.0]:
			B.from_dict(B.to_dict())   # a fresh copy of nothing: the rest pose
			for j in Body.BACK:
				B.ang[j] = Vector3(1.5, -2.0, 3.0)   # off zero on every axis: the untouched axes must keep these
			var ask: float = r.y * u if u >= 0.0 else -r.x * u
			B.back_bend(axis, ask)
			sum_ok = sum_ok and absf(B.back_of(axis) - ask) < 1e-4
			for j in Body.BACK:
				var v: Vector3 = B.ang[j]
				var l: Vector2 = B.lim[j][axis]
				lim_ok = lim_ok and v[ai] >= l.x - 1e-6 and v[ai] <= l.y + 1e-6
				var want: float = (l.y / r.y if ask >= 0.0 else l.x / r.x) * ask
				share_ok = share_ok and absf(v[ai] - want) < 1e-4
				for o in 3:
					if o != ai:
						other_ok = other_ok and absf(v[o] - [1.5, -2.0, 3.0][o]) < 1e-9
			var before: Dictionary = B.ang.duplicate()
			B.back_bend(axis, B.back_of(axis))
			for j in Body.BACK:
				again_ok = again_ok and ((B.ang[j] as Vector3) - (before[j] as Vector3)).length() < 1e-6
		var ends_ok := true
		for e in [r.x, r.y]:
			B.back_bend(axis, e)
			for j in Body.BACK:
				var l: Vector2 = B.lim[j][axis]
				ends_ok = ends_ok and absf((B.ang[j] as Vector3)[ai] - (l.y if e > 0.0 else l.x)) < 1e-4
		ok(sum_ok and lim_ok and share_ok and other_ok and again_ok and ends_ok,
			"%s: range %.0f..%.0f deg; sum = ask %s, limits %s, share by range %s, ends all at their limits %s, other axes kept %s, idempotent %s" % [axis, r.x, r.y, sum_ok, lim_ok, share_ok, ends_ok, other_ok, again_ok])
	print("     people (Apti 2023): lumbar flex 69.9 / ext 40.0 / lateral 36 / rotation 38; cervical 57.7 / 59.1 / 42 / 71")
	print("BACK BEND TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
