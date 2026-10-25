## godot --headless --path . -s tests/turn_test.gd [-- <folder of turn_*.json>]     (default: res://templates)
## THE TURNS ON THE SPOT (turn around 180, turn left 90, turn right 90): the bars are fixed here before any number is read.
## Each file is read the way the app reads it (Scene.from_dict) and sampled at 120 Hz:
##   (a) 0 frames with both balls more than 1 cm above their rest height (no hop: a turn is on the floor)
##   (b) the moving foot's arc: the highest a ball gets above the floor is at most 8 cm
##   (c) the hips never drop more than 4 cm below standing
##   (d) the final hips yaw is 180 (90 left, -90 right) within 10 deg
##   (e) no foot (heel, ball or toe joint) goes below the floor: 1 cm allowed
##   (f) the feet end where they start: the ball-to-ball stance equals the start's +-2 cm across, under 5 cm along the body
##   (g) JOINED: the typed "jump twice then turn around" and "walk then turn around" (Easy's grammar, EasyHome._words_dict): no frame
##       in the turn's own cards (the last cards of the build, the turn file's count) has both balls over 1 cm up
## Also prints the peak knee bend and the number of frames the feet are on the floor.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	var dir := "res://templates"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		dir = String(args[0])
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	for spec in [["turn_around", 180.0], ["turn_left", 90.0], ["turn_right", -90.0]]:
		var nm := String(spec[0])
		var want := float(spec[1])
		var txt := FileAccess.get_file_as_string("%s/%s.json" % [dir, nm])
		if txt == "":
			ok(false, "%s: no file at %s/%s.json" % [nm, dir, nm])
			continue
		var S := Scene.new()
		S.from_dict(JSON.parse_string(txt))
		var rest_ball := {}
		var rest_pel := 0.0
		var rest_foot := {}
		S.apply(B, 0.0)
		for sd in ["_l", "_r"]:
			rest_ball[sd] = (B.p0["ball" + sd] as Vector3).y
			rest_foot[sd] = (B.p0["foot" + sd] as Vector3).y
		rest_pel = (B.P["pelvis"] as Vector3).y
		var both_up := 0
		var peak := 0.0
		var pel_min := 99.0
		var below := 0.0
		var knee := 0.0
		var k := 0
		var frames := 0
		while k / 120.0 <= S.length():
			S.apply(B, k / 120.0)
			frames += 1
			var up := 0
			for sd in ["_l", "_r"]:
				var lift: float = (B.P["ball" + sd] as Vector3).y - float(rest_ball[sd])
				peak = maxf(peak, lift)
				if lift > 0.01:
					up += 1
				below = minf(below, lift)
				below = minf(below, (B.P["foot" + sd] as Vector3).y - float(rest_foot[sd]))
				knee = maxf(knee, absf(B.ang["calf" + sd].x))
			if up == 2:
				both_up += 1
			pel_min = minf(pel_min, (B.P["pelvis"] as Vector3).y - rest_pel)
			k += 1
		S.apply(B, S.length())
		var fwd: Vector3 = B.G["pelvis"] * Vector3(0, 0, 1)
		var yaw := rad_to_deg(atan2(fwd.x, fwd.z))
		var dyaw := absf(wrapf(yaw - want, -180.0, 180.0))
		S.apply(B, 0.0)
		var w0: float = ((B.P["ball_l"] as Vector3) - (B.P["ball_r"] as Vector3)).length() * 100.0
		S.apply(B, S.length())
		var bl: Vector3 = B.P["ball_l"]
		var br: Vector3 = B.P["ball_r"]
		var d := bl - br
		var lat: Vector3 = B.G["pelvis"] * Vector3(1, 0, 0)
		var width := absf(d.dot(lat)) * 100.0
		var along := absf(d.dot(B.G["pelvis"] * Vector3(0, 0, 1))) * 100.0
		print("     %s: %d frames %.2f s, both balls up %d frames, peak ball rise %.1f cm, hips min %.1f cm, lowest foot %.1f mm, knee bend max %.0f deg, end yaw %.1f, end width %.1f cm (along %.1f)" % [nm, frames, S.length(), both_up, peak * 100.0, pel_min * 100.0, below * 1000.0, knee, yaw, width, along])
		ok(both_up == 0, "%s (a) %d frames with both balls over 1 cm up, want 0" % [nm, both_up])
		ok(peak <= 0.08, "%s (b) the moving foot's arc: peak ball rise %.1f cm, at most 8" % [nm, peak * 100.0])
		ok(pel_min >= -0.04, "%s (c) hips never below standing by 4 cm: lowest %.1f cm" % [nm, pel_min * 100.0])
		ok(dyaw <= 10.0, "%s (d) final hips yaw %.1f, want %.0f +- 10" % [nm, yaw, want])
		ok(below >= -0.01, "%s (e) lowest foot joint %.1f mm under the floor, at most 10" % [nm, -below * 1000.0])
		ok(absf(width - w0) <= 2.0 and along < 5.0, "%s (f) feet end where they start: %.1f cm across, start %.1f (+-2), %.1f cm along (under 5)" % [nm, width, w0, along])
		print("     %s: peak knee bend %.0f deg" % [nm, knee])
	joined(B)
	print("TURN SUITE: %d FAIL" % fails)
	quit(1 if fails > 0 else 0)


## (g): the typed builds that end in a turn, sampled at 120 Hz over the turn's own cards (the last cards of the build)
func joined(B: Body) -> void:
	var ed = EasyHome.new()
	var turn_n := (JSON.parse_string(FileAccess.get_file_as_string("res://templates/turn_around.json"))["cards"] as Array).size()
	for phrase in ["jump twice then turn around", "walk then turn around"]:
		var r: Dictionary = ed._words_dict(phrase)
		if not bool(r.get("ok", false)):
			ok(false, "(g) '%s' builds (%s)" % [phrase, String(r.get("error", ""))])
			continue
		var S := Scene.new()
		S.from_dict(r["dict"])
		var cards: Array = r["dict"]["cards"]
		var first := cards.size() - turn_n
		var tail_ok := first > 0 and String(cards[first]["name"]) == "stand" and String(cards[-1]["name"]) == "square"
		var ts: Array = S.times()
		var t0 := float(ts[first][1])
		var both := 0
		var k := 0
		while t0 + k / 120.0 <= S.length():
			S.apply(B, t0 + k / 120.0)
			var up := 0
			for sd in ["_l", "_r"]:
				if (B.P["ball" + sd] as Vector3).y - (B.p0["ball" + sd] as Vector3).y > 0.01:
					up += 1
			if up == 2:
				both += 1
			k += 1
		ok(tail_ok and both == 0, "%s (g) joined: %d frames with both balls over 1 cm up in the turn's %d cards (from %.2f s), want 0; turn tail %s" % [phrase, both, turn_n, t0, "found" if tail_ok else "NOT found"])


func inr(v: float, lo: float, hi: float) -> bool:
	return v >= lo and v <= hi
