extends SceneTree
## godot --path . -s tools/look4d2_export.gd -- scan            scan.json: the arm's held can / joints, the walk's feet and CoM, over time (to choose instants)
## godot --path . -s tools/look4d2_export.gd -- export          reads out/look4d2/instants.json [{name, scene, t}] and writes out/look4d2/<name>/ :
##   L0.txt L1.txt D1.txt (the old digest), L2/<part>.txt for every named part, meta.json, scene_truth.json (shapes and centres every 1/30 s from t to t + 0.6, masses,
##   and scene-sourced facts: the arm's held can and joint values from N14.state, the engine's crank angle). tools/look4d_truth.py gen2 computes the questions' truth from scene_truth.json.
const L4 := preload("res://scripts/build/look4d.gd")
const SCN := preload("res://scripts/build/look4d_scenes.gd")
const A14 := preload("res://scripts/build/ch14_arm.gd")
const N14 := preload("res://scripts/build/ch14_anim.gd")
const OUT := "res://out/look4d2"


func _init() -> void:
	await process_frame
	var mode := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "export"
	if mode == "scan":
		await scan()
	else:
		await export()
	quit(0)


func put(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func scan() -> void:
	var out := {"arm": [], "walk": [], "fall": []}
	var sc := SCN.arm()
	var ctx := L4.open(root, sc)
	await L4.frames(3)
	var d := A14.design()
	var wp := N14.waypoints(d)
	var tend := float(wp[wp.size() - 1]["t"])
	var t := 0.0
	while t < tend:
		var st := N14.state(d, wp, t)
		var lim: Dictionary = d["lim"]
		var row := {"t": t, "held": int(st["held"]), "g": float(st["g"]), "label": String(st["label"]), "yaw": float(st["yaw"])}
		if st.has("th1"):
			row["th1"] = float(st["th1"])
			row["th2"] = float(st["th2"])
			row["psi"] = float(st["psi"])
		out["arm"].append(row)
		t += 0.25
	L4.close(ctx)
	var w := SCN.walk()
	var wctx := L4.open(root, w)
	await L4.frames(3)
	var wt := 0.3
	while wt < 3.0:
		var S := L4.snap_ray(wctx, wt)
		var ch := L4.character(wctx, S)
		out["walk"].append({"t": wt, "balanced": ch["balanced"], "airborne": ch["airborne"], "margin_mm": ch["margin_mm"], "feet": {"foot_l": ch["feet"]["foot_l"]["down"], "foot_r": ch["feet"]["foot_r"]["down"]}})
		wt += 0.1
	L4.close(wctx)
	put(ProjectSettings.globalize_path(OUT + "/scan.json"), JSON.stringify(out, "  "))
	print("scan written")


func export() -> void:
	var specs: Array = JSON.parse_string(FileAccess.get_file_as_string(OUT + "/instants.json"))
	var d := A14.design()
	var wp := N14.waypoints(d)
	for sp in specs:
		var sc := SCN.by_name(String(sp["scene"]))
		var ctx := L4.open(root, sc)
		await L4.frames(3)
		var t := float(sp["t"])
		var dir := ProjectSettings.globalize_path(OUT + "/" + String(sp["name"]))
		var S := await L4.snap(ctx, t, true)
		put(dir + "/L0.txt", L4.txt(L4.level0(ctx, S)))
		put(dir + "/L1.txt", L4.txt(L4.level1(ctx, S)))
		put(dir + "/D1.txt", JSON.stringify(L4.digest(ctx, t, S["kin"], S["meas"], S["contacts"]), "", false))
		var nm: Array = L4.named(ctx)
		if String(sp["scene"]) == "s3_walk":
			put(dir + "/char.txt", L4.txt(L4.character(ctx, S)))
		for id in nm:
			put(dir + "/L2/" + id + ".txt", L4.txt(L4.level2(ctx, S, id)))
		# scene truth: shapes and centres every 1/30 s from t to t + 0.6
		var samples: Array = []
		for k in 19:
			var tk := t + k / 30.0
			L4.at(ctx, tk)
			var shapes := L4.shapes_now(ctx)
			var st := L4.state(ctx, tk)
			var row := {}
			for id in nm:
				row[id] = {"shape": shapes[id], "c": [st[id]["c"].x, st[id]["c"].y, st[id]["c"].z]}
			samples.append({"t": tk, "k": k, "objs": row})
		L4.at(ctx, t)
		var truth := {"scene": sp["scene"], "t": t, "ids": nm, "samples": samples, "mass": sc["mass"], "kin_speed": {}}
		for id in nm:
			truth["kin_speed"][id] = S["kin"][id]["speed"]
		if String(sp["scene"]) == "s2_arm":
			var st2 := N14.state(d, wp, t)
			truth["arm"] = {"held_index": int(st2["held"]), "yaw": float(st2["yaw"]), "th1": st2.get("th1", null), "th2": st2.get("th2", null), "psi": st2.get("psi", null), "g": float(st2["g"]), "lim": d["lim"]}
		if String(sp["scene"]) == "s1_engine":
			truth["engine"] = {"crank_deg": 720.0 * t / 2.0, "R_mm": 20.7, "L_mm": float(load("res://scripts/build/ch13_parts.gd").L)}
		put(dir + "/scene_truth.json", JSON.stringify(truth))
		put(dir + "/meta.json", JSON.stringify({"name": sp["name"], "scene": sp["scene"], "t": t, "ids": nm, "camera": {"pos": [ctx["cam"].global_position.x, ctx["cam"].global_position.y, ctx["cam"].global_position.z]}}))
		L4.close(ctx)
		print("exported ", sp["name"])
