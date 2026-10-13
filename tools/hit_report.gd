extends SceneTree
## WHERE DO THE HITS LAND? (Nick 10-13: a dummy for combat scenes). Plays each scene against the target dummy (Dummy)
## standing --dist m in front (default: every 0.25 m from 1.0 to 2.0, the hit at the closest range that lands) and
## prints every hit: time, zone, the spot on the weapon (m from the butt), how fast it moves, how deep it goes.
##   godot --headless --path . -s tools/hit_report.gd -- scenes/a.json [...] [--dist 1.5] [--around]
## --around: the dummy also stands every 45 deg round him (+ = to his left), for side and back sweeps
func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var T := Dummy.new()
	var args: Array = OS.get_cmdline_user_args()
	var dists := [1.0, 1.25, 1.5, 1.75, 2.0]
	var k := args.find("--dist")
	if k >= 0:
		dists = [float(args[k + 1])]
		args.remove_at(k + 1)
		args.remove_at(k)
	var yaws := [0.0]
	k = args.find("--around")
	if k >= 0:
		yaws = [0.0, 45.0, 90.0, 135.0, 180.0, -135.0, -90.0, -45.0]
		args.remove_at(k)
	for f in args:
		var S := Scene.new()
		S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://" + f)))
		print("%s  (%.2f s)" % [f, S.length()])
		for d in dists:
			for a in yaws:
				T.place(d, a)
				var hs: Array = T.hits(S, B)
				var row := []
				for h in hs:
					row.append("%.2fs %s (%s) at %.2f m up the weapon, %.1f m/s, %.0f mm in" % [h["t"], h["zone"], h["part"], h["u"], h["speed"], float(h["depth"]) * 1000.0])
				if row.is_empty() and yaws.size() > 1:
					continue
				print("   dummy at %.2f m, %+.0f deg: %s" % [d, a, "no hit" if row.is_empty() else "; ".join(row)])
				if not hs.is_empty():
					var L: Array = T.landed(S, B)
					var again: Array = T.hits(L[0], B)
					print("      solid: stops at %.3fs on the %s, rebounds, %.2f s long; touches after the rebound: %d" % [L[1]["t"], L[1]["zone"], (L[0] as Scene).length(), again.size() - 1])
	quit()
