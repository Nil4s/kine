extends SceneTree
## CH1d: the generated house under each stored site. godot --headless --path . -s tools/ch1_sites_report.gd
func _init() -> void:
	var mj = JSON.parse_string(FileAccess.get_file_as_string("res://out/ch1/members.json"))
	for sid in HouseCheck.SITES:
		var lines := Ch1House.run(mj, sid)
		var nf := 0
		print("== ", sid)
		for l in lines:
			if not l["pass"]:
				nf += 1
			if not l["pass"] or ["uplift", "site", "seismic", "birdsmouth", "anchorage", "header_bearing", "sheathing_nail"].has(l["kind"]):
				print(String(l["text"]).left(400))
		print(sid, " lines ", lines.size(), " FAIL ", nf)
	quit()
