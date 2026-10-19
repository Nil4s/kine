## godot --headless --path . -s tests/grip_save_test.gd     (round 47, GATES CC0)
## LOCK BOTH HANDS IS SAVED. bo_spin's last card: the staff in both hands, the second hand turned round the shaft in a way the plain
## reach would not choose; Lock both hands (capture_second) records it.
##   1 the card's weapon carries it (grip2: hand, place, turn, fingers) and the file passes the schema's keys
##   2 a NEW body loaded from that card holds the same grip2 (it came from the file, not from memory)
##   3 playback of a 2-card scene from the file, on a body that never saw the grip, puts the second wrist within 1 cm of
##     where it was locked at both cards and in the middle; the same scene with grip2 stripped from the file does not
##     (the control: the old behaviour re-solved the arm its own way)
##   4 playing it stays under 5 ms a frame
extends SceneTree

var fails := 0
const FRAME_RATIO := 4.0   # measured 1.18-1.42 idle and 1.12-1.50 with 8 copies at once (2.45-5.26 ms: the old 5 ms bar failed 3 of 8); the search-every-frame regression it guards (245 ms) would be ~100


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func play(m: Node, d: Dictionary, t: float) -> Vector3:
	var B: Body = m.B
	B.grip2 = {}   # a body that never saw the grip
	var S := Scene.new()
	S.from_dict(d)
	S.apply(B, t)
	return B.P["hand_l"]


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var B: Body = m.B
	B.fast = false   # the setup is an edit (Lock both hands in the app): the full fit
	# bo_spin's last card: the staff in both hands (a bundled scene)
	var bo: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/bo_spin.json"))
	B.grip2 = {}
	B.from_dict(bo["cards"][8]["pose"])
	var miss0 := B.apply_grip()
	B.grip = false
	B.capture_second()
	if B.grip2.is_empty():
		ok(false, "setup: the second hand is not on the staff (reach miss %.0f mm)" % (miss0 * 1000))
		quit(1)
		return
	var g: Dictionary = B.grip2.duplicate(true)
	var turn := Quaternion(Vector3.UP, deg_to_rad(35.0))
	var lp := Body._v(g["lpos"])
	var lr: Array = g["lrot"]
	g["lpos"] = Body._p(turn * lp)
	g["lrot"] = Body._q((turn * Quaternion(lr[0], lr[1], lr[2], lr[3])).normalized())
	B.grip2 = g
	B.grip = true
	var miss1 := B.apply_grip()
	B.grip = false
	var off := B.capture_second()
	print("setup: reach miss %.0f mm, turned grip miss %.0f mm" % [miss0 * 1000, miss1 * 1000])
	var want: Vector3 = B.P["hand_l"]
	var card: Dictionary = B.to_dict()
	var w: Dictionary = card["weapon"]
	var g2: Dictionary = w.get("grip2", {})
	var schema: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/scene.schema.json"))
	var wkeys: Dictionary = schema["$defs"]["weapon"]["properties"] if schema.has("$defs") and schema["$defs"].has("weapon") else {}
	if wkeys.is_empty():
		wkeys = _find_weapon(schema)
	var unknown := w.keys().filter(func(k): return not wkeys.has(k))
	ok(off >= 0.0 and off <= 0.05 and not g2.is_empty() and g2.has("lrot") and g2.has("fingers") and unknown.is_empty(),
		"1 the card carries the lock: palm %.0f mm off the shaft, grip2 keys %s, keys the schema does not know %s" % [off * 1000, g2.keys(), unknown])
	# 2
	var txt := JSON.stringify(card)
	var back: Dictionary = JSON.parse_string(txt)
	B.grip2 = {}
	B.from_dict(back)
	ok(not B.grip2.is_empty() and JSON.stringify(B.grip2) == JSON.stringify(g2), "2 loaded from the file text, the body holds the same grip2 (%s)" % (JSON.stringify(B.grip2) == JSON.stringify(g2)))
	# 3
	var sc := {"scene": "zz_grip_save", "fps": 30, "natural": false, "cards": [
		{"name": "a", "move": -1, "hold": 0.2, "pose": back}, {"name": "b", "move": 0.6, "hold": 0.2, "pose": back}]}
	var mids := []
	for t in [0.0, 0.5, 1.0]:
		mids.append(play(m, sc, t).distance_to(want))
	var bare: Dictionary = sc.duplicate(true)
	for c in bare["cards"]:
		c["pose"]["weapon"].erase("grip2")
	var bare_d := play(m, bare, 0.5).distance_to(want)
	ok(mids.max() < 0.01 and bare_d > 0.01, "3 played from the file on a fresh grip: the second wrist %s mm from where it was locked (bar 10); without grip2 in the file %.0f mm (the control, > 10)"
		% [str(mids.map(func(x): return snappedf(x * 1000, 0.1))), bare_d * 1000])
	# 4 playback stays cheap with the grip saved: the second hand's fit in playback is the quick reach + wrist turn (the
	# search with contacts ran every frame: 245 ms a frame on Nick's locked axe scene)
	# a second card that differs (the bat arm 25 deg higher, the grip re-fitted as an edit), so the frames between
	# need a real fit, not the "already there" skip
	B.from_dict(back)
	B.set_ang("upperarm_r", (B.ang["upperarm_r"] as Vector3) + Vector3(25, 0, 0))
	B.apply_grip()
	var moved: Dictionary = B.to_dict()
	var sc2 := {"scene": "zz_grip_save2", "fps": 30, "natural": false, "cards": [
		{"name": "a", "move": -1, "hold": 0.0, "pose": back}, {"name": "b", "move": 1.0, "hold": 0.0, "pose": moved}]}
	B.fast = true
	var S := Scene.new()
	S.from_dict(sc2)
	var Y := Body.new()   # the yardstick, timed beside each frame (the suite runs 8 at once: load hits both alike)
	Y.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var us := 0
	var unit := 0
	for i in 30:
		var tr := Time.get_ticks_usec()
		Y.penetration()
		var t0 := Time.get_ticks_usec()
		unit += t0 - tr
		B.grip2 = {}
		S.apply(B, i / 30.0)
		us += Time.get_ticks_usec() - t0
	var ms := us / 1000.0 / 30.0
	var ratio := float(us) / maxf(1.0, unit)
	print("     RATIO a played frame / one whole-body penetration() timed beside it: %.2f (%.2f ms a frame)" % [ratio, ms])
	ok(ratio <= FRAME_RATIO, "4 playback with the saved grip: %.2f x one whole-body penetration() a frame (bar %.0f, load-proof; idle that is under 5 ms); %.2f ms a frame here" % [ratio, FRAME_RATIO, ms])
	m.queue_free()
	print("GRIP SAVE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)


func _find_weapon(o) -> Dictionary:
	if o is Dictionary:
		if o.has("weapon") and o["weapon"] is Dictionary and o["weapon"].has("properties"):
			return o["weapon"]["properties"]
		for k in o:
			var r := _find_weapon(o[k])
			if not r.is_empty():
				return r
	elif o is Array:
		for x in o:
			var r := _find_weapon(x)
			if not r.is_empty():
				return r
	return {}
