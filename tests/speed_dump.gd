## godot --headless --path . -s tests/speed_dump.gd -- <out.csv> scenes/a.json [scenes/b.json ...]
## Per scene, at 120 Hz: the weapon tip's speed (m/s) and the angular speed (deg/s) of the hips, the chest and the bat
## hand's forearm, plus each card's arrival time. Shows where a move STOPS: the old per-card ease drops every joint to 0
## at every card; a spline only where the body really stops.
extends SceneTree


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var out := FileAccess.open(a[0], FileAccess.WRITE)
	out.store_line("scene,t,tip,pelvis,spine_03,lowerarm_r,card")
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	for f in a.slice(1):
		var S := Scene.new()
		S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://" + f)))
		var hz := 120.0
		var n := int(S.length() * hz) + 1
		var ts := S.times()
		var prev := {}
		var ptip := Vector3.ZERO
		for i in n:
			var t := i / hz
			S.apply(B, t)
			var tip := B.wep_point(B.wep_len) if B.wep_on else Vector3.ZERO
			var row := [f.get_file().get_basename(), "%.4f" % t, "%.3f" % (((tip - ptip).length() * hz) if i > 0 else 0.0)]
			for j in ["pelvis", "spine_03", "lowerarm_r"]:
				var v: Vector3 = B.ang[j]
				row.append("%.2f" % ((Scene._d(prev.get(j, v), v, j).length() * hz) if i > 0 else 0.0))
				prev[j] = v
			var card := ""
			for k in S.cards.size():
				if absf(ts[k][1] - t) < 0.5 / hz:
					card = String(S.cards[k]["name"]).replace(",", " ")
			row.append(card)
			out.store_line(",".join(row))
			ptip = tip
	out.close()
	TestFiles.cleanup()
	quit()
