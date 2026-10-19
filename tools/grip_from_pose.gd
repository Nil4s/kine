extends SceneTree
## FIT A WEAPON'S GRIP FROM NICK'S POSE (Nick 10-13: "done, 2 hands on the staff ... check the maths of the hand parts").
## Reads a pose where Nick put both hands on the weapon and writes data/grips/<kind>.json: the main hand's place in
## the hand + fingers (as "Save grip as standard"), and "second": the other hand's wrist and turn in the WEAPON's
## frame, measured from the palm's spot on the shaft (u, m from the butt), + its fingers. Body.apply_grip (G) then
## puts the second hand on exactly so, anywhere along the shaft ([ ] slides it).
##   godot --headless --path . -s tools/grip_from_pose.gd -- moves/<pose>.json
func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var f: String = OS.get_cmdline_user_args()[0]
	B.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://" + f)))
	var h := B.wep_hand
	var o := "hand_l" if h == "hand_r" else "hand_r"
	var x := B.wep_xform()
	var q: Quaternion = x[1]
	var k: Vector3 = x[0]
	var palm: Vector3 = B.palm_point(o)
	var pl := q.inverse() * (palm - k)
	var off := Vector2(pl.x, pl.z).length()
	if off > 0.05:
		print("the %s's palm is %.0f cm off the shaft: not holding it" % [o, off * 100.0])
		quit(1)
		return
	var wl := q.inverse() * ((B.P[o] as Vector3) - k)
	var fing := {}
	var fing_main := {}
	for j in Body.FINGERS:
		var v: Vector3 = B.ang[j]
		if j.ends_with(o.right(2)):
			fing[j] = [snappedf(v.x, 0.1), snappedf(v.y, 0.1), snappedf(v.z, 0.1)]
		elif j.ends_with(h.right(2)):
			fing_main[j] = [snappedf(v.x, 0.1), snappedf(v.y, 0.1), snappedf(v.z, 0.1)]
	var d := {"_note": "%s grip fitted from Nick's pose %s (tools/grip_from_pose.gd)" % [B.wep_kind, f], "weapon": B.wep_kind,
		"hand": h, "local_pos": Body._p(B.wep_lpos), "local_rot": Body._q(B.wep_lrot), "fingers": fing_main, "other_hand_m": -1.0,
		"second": {"hand": o, "u": snappedf(pl.y, 0.001), "lpos": Body._p((wl - Vector3(0, pl.y, 0)) / B.hand_s(o)),
			"lrot": Body._q((q.inverse() * (B.G[o] as Quaternion)).normalized()), "fingers": fing}}
	FileAccess.open("res://data/grips/%s.json" % B.wep_kind, FileAccess.WRITE).store_string(JSON.stringify(d, " "))
	print("GRIP %s: main %s, second %s at %.2f m (palm %.1f cm off the axis), main hand at %.2f m" % [B.wep_kind, h, o, pl.y, off * 100.0,
		(q.inverse() * ((B.P[h] as Vector3) - k)).y])
	quit()
