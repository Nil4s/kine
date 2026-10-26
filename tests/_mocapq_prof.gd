## godot --headless --path . -s tests/_mocapq_prof.gd -- [flip] [noflipfix] [smooth] [dump:out.json] pose1.json ...   (MOCAP QUALITY: the before / after table; not a suite)
## prints one line per clip: stage times of VideoIQ.process and the MocapMetrics numbers
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var rt := not ("geo" in args)
	VideoIQ.stance_fix = not ("nostance" in args)
	VideoIQ.toe_fix = not ("notoe" in args)
	
	VideoIQ.angle_smooth = ("smooth" in args)
	VideoIQ.flip_fix = not ("noflipfix" in args)
	for a in args:
		if a.begins_with("off:"):
			VideoIQ.smooth_off = a.substr(4).split(",")
	for path in args:
		if path in ["noflipfix", "flip", "geo", "nostance", "notoe", "ik", "smooth"] or path.begins_with("off:") or path.begins_with("dump:"):
			continue
		var t0 := Time.get_ticks_usec()
		var P := VideoImport.load_file(path)
		var parse_ms := (Time.get_ticks_usec() - t0) / 1000.0
		if not P["ok"]:
			print("%s: %s" % [path, P["why"]])
			continue
		if "flip" in args:
			for i in range(20, 24):
				var w: Array = P["frames"][i]["w"]
				for pr in [[25, 26], [27, 28], [29, 30], [31, 32]]:
					var tmp: Vector3 = w[pr[0]]
					w[pr[0]] = w[pr[1]]
					w[pr[1]] = tmp
		var raw: Array = P["frames"].duplicate(true)
		var dump_to := ""
		for a in args:
			if a.begins_with("dump:"):
				dump_to = a.substr(5)
		var R := VideoIQ.process(B, P, "", "prof", rt)
		var times := []
		for fr in R["fitted"]:
			times.append(fr["t"])
		if dump_to != "":
			var rows := []
			for fr in R["frames"]:
				rows.append((fr["w"] as Array).map(func(v): return [v.x, v.y, v.z]))
			var fh := FileAccess.open(dump_to, FileAccess.WRITE)
			fh.store_string(JSON.stringify(rows))
			fh.close()
		var F := MocapMetrics.play(B, R["scene"], times)
		var Dn := MocapMetrics.play(B, R["dense"], times)
		var sd0 := MocapMetrics.skate(Dn)
		print("  DENSE skate_worst=%.2f skate_mean=%.2f n=%d pen_deep=%.2f" % [sd0["worst"], sd0["mean"], sd0["n"], MocapMetrics.penetration(Dn)["deepest"]])
		var sk := MocapMetrics.skate(F)
		var pen := MocapMetrics.penetration(F)
		print("  JOINTS ", MocapMetrics.jitter_by_joint(F["frames"]).slice(0, 8))
		for e in sk["list"]:
			print("  skate ", e)
		var st: Dictionary = VideoIQ.stage_ms
		print(R["text"].left(90))
		for p in R["scene"].plants:
			print("  plant ", p)
		print("  limb flip frames repaired: ", R.get("limb_flips", 0))
		print("CLIP %s frames=%d fps=%.1f" % [path.get_file(), raw.size(), float(P["fps"])])
		print("  TIME parse=%.0f prep=%.0f cleanup=%.0f contacts=%.0f fit=%.0f cards=%.0f plants=%.0f locate=%.0f ms; Scene.apply calls %d" % [parse_ms, st.get("prep", 0), st.get("cleanup", 0), st.get("contacts", 0), st.get("fit", 0), st.get("cards", 0), st.get("plants", 0), st.get("locate", 0), VideoIQ.reach_applies])
		print("  QUAL skate_worst=%.2f skate_mean=%.2f contacts=%d jitter=%.2f flips_raw=%d flips_clean=%d foot_flips=%d bones_raw=%.2f bones_clean=%.2f pen_deep=%.2f pen_share=%.3f" % [sk["worst"], sk["mean"], sk["n"], MocapMetrics.jitter(F["frames"]), MocapMetrics.flips(raw), MocapMetrics.flips(R["frames"]), MocapMetrics.foot_flips(F), MocapMetrics.bones(raw), MocapMetrics.bones(R["frames"]), pen["deepest"], pen["share"]])
	TestFiles.cleanup()
	quit(0)
