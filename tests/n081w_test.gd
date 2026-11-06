## godot --path . -s tests/n081w_test.gd     (window suite n081w:w)   N081 WIRED: cancel windows on the frame-data strip, in the export and as an agent tool.
## Bars, written BEFORE the wiring (the jab fixture of n081_test: guard hold 10 f, extend 3, hold 3, retract 12, hold 30; 60 fps):
##  a. AGENT CALL: cancel_windows {clip} returns JSON equal to CancelWindows.to_json(CancelWindows.analyze(...)) called directly on the same file
##     (windows, thresholds, min_run); {frame} adds "at_frame" {frame, cancelable}; a thresholds override {v_max, h_max} is echoed and applied
##     (x1000 gives a superset). An unknown clip is a -32602 error; the live scene is not moved.
##  b. LISTS: "cancel_windows" is in AgentTools.MCP_EXTRA, poser_mcp.py names it in TOOLS and MATH_TOOLS, poser_cli.gd has a one-shot subcommand.
##     Control: a made-up name is in none of them and answers -32601.
##  c. STRIP: with Frame data on and the jab open, the live frame data (m.fd_cache) carries "cancel" with the module's windows, and the timeline
##     reports one band rect per window (Timeline.cancel_rects), each as wide as the window's frames, and the PNG pixel at each band's centre is the
##     band colour (CancelWindows.COL_BAND) while a pixel in the extension (active frames) at the same height is not.
##  d. EXPORT: the frame-data JSON the app writes (main._fd_export's data -> FrameData.write_json) has the same windows (fd_cache -> file -> parse).
##  Control: a window-less claim: the idle scene's band list is not empty; a band over the active frames does not exist.
extends SceneTree

var fails := 0
const FPS := 60


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func control(claim: bool, what: String) -> void:
	print(("ok   control caught: " if not claim else "FAIL control NOT caught: ") + what)
	if claim:
		fails += 1


func stand() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	return b


func posed(j: String, v: Vector3) -> Dictionary:
	var b := stand()
	b.ang[j] = v
	b.fk()
	return b.to_dict()


func f(n: float) -> float:
	return n / float(FPS)


func jab() -> Scene:
	var B := stand()
	var a0: Vector3 = B.ang["upperarm_r"]
	var guard := posed("upperarm_r", Vector3(10.0, a0.y, a0.z))
	var hit := posed("upperarm_r", Vector3(70.0, a0.y, a0.z))
	var s := Scene.new()
	s.from_dict({"scene": "zz_n081w", "fps": 30, "natural": false, "on_floor": false, "pin": false, "cards": [
		{"name": "guard", "pose": guard, "move": -1.0, "hold": f(10)}, {"name": "extend", "pose": hit, "move": f(3), "hold": f(3)},
		{"name": "retract", "pose": guard, "move": f(12), "hold": f(30)}]})
	return s


func save(s: Scene, name: String) -> String:
	DirAccess.make_dir_recursive_absolute("user://n081w")
	var p := ProjectSettings.globalize_path("user://n081w/" + name + ".json")
	var fh := FileAccess.open(p, FileAccess.WRITE)
	fh.store_string(JSON.stringify(s.to_dict(stand(), false)))
	fh.close()
	return p


func load_scene(p: String) -> Scene:
	var s := Scene.new()
	s.from_dict(JSON.parse_string(FileAccess.get_file_as_string(p)))
	return s


func wins(c: Dictionary) -> Array:
	var out := []
	for w in c["windows"]:
		out.append([int(w["f0"]), int(w["f1"])])
	return out


func _init() -> void:
	var jab_p := save(jab(), "jab")
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var T := AgentTools.new(m)
	await T.request(1, "open", {"path": "scenes/combo3.json"})
	var live_before := JSON.stringify(m.S.to_dict(m.B, false))
	# a
	var direct: Dictionary = JSON.parse_string(JSON.stringify(CancelWindows.to_json(CancelWindows.analyze(load_scene(jab_p), stand(), FPS))))
	var r: Dictionary = await T.request(2, "cancel_windows", {"clip": jab_p})
	var got: Dictionary = JSON.parse_string(JSON.stringify(r.get("result", {})))
	ok(not direct["windows"].is_empty() and got.get("windows") == direct["windows"] and got.get("thresholds") == direct["thresholds"] and got.get("min_run") == direct["min_run"],
		"a call == direct module: windows %s" % JSON.stringify(got.get("windows")))
	var r2: Dictionary = await T.request(3, "cancel_windows", {"clip": jab_p, "frame": 0})
	var r3: Dictionary = await T.request(4, "cancel_windows", {"clip": jab_p, "frame": 12})
	ok(r2.get("result", {}).get("at_frame", {}).get("cancelable") == true and r3.get("result", {}).get("at_frame", {}).get("cancelable") == false,
		"a at_frame: 0 -> %s, 12 (extension) -> %s" % [r2.get("result", {}).get("at_frame"), r3.get("result", {}).get("at_frame")])
	var r4: Dictionary = await T.request(5, "cancel_windows", {"clip": jab_p, "v_max": 250.0, "h_max": 45.0})
	var w4 := wins(r4.get("result", {"windows": []}))
	var w0 := wins(direct)
	var sup := true
	for x in w0:
		var inside := false
		for y in w4:
			if int(x[0]) >= int(y[0]) and int(x[1]) <= int(y[1]):
				inside = true
		sup = sup and inside
	ok(sup and float(r4.get("result", {}).get("thresholds", {}).get("v_max", 0)) == 250.0, "a threshold override echoed, windows a superset: %s" % [w4])
	var bad: Dictionary = await T.request(6, "cancel_windows", {"clip": "nope/none.json"})
	ok(bad.has("error") and int(bad["error"]["code"]) == -32602, "a missing clip is -32602")
	var live: Dictionary = await T.request(7, "cancel_windows", {})
	ok(live.has("result") and JSON.stringify(m.S.to_dict(m.B, false)) == live_before, "a no clip = the live scene, unchanged")
	# b
	var py := FileAccess.get_file_as_string("res://tools/mcp/poser_mcp.py")
	var cli := FileAccess.get_file_as_string("res://tools/poser_cli.gd")
	ok("cancel_windows" in AgentTools.MCP_EXTRA, "b MCP_EXTRA has cancel_windows")
	ok(py.contains("\"cancel_windows\": (\"cancel_windows\"") and py.split("MATH_TOOLS = [")[1].split("]")[0].contains("\"cancel_windows\""), "b poser_mcp.py TOOLS and MATH_TOOLS")
	ok(cli.contains("\"cancel_windows\":"), "b CLI subcommand")
	var nm := "cancel_windows_nope"
	control(nm in AgentTools.MCP_EXTRA or py.contains("\"%s\": (" % nm) or cli.contains("\"%s\":" % nm), "b1 a made-up name is listed")
	var rn: Dictionary = await T.request(8, nm, {})
	ok(rn.has("error") and int(rn["error"]["code"]) == -32601, "b made-up name answers -32601")
	# c strip
	await T.request(9, "open", {"path": jab_p})
	root.size = Vector2i(1600, 900)
	m.fd_on = true
	m._refresh()
	var tl: Control = m.ui_timeline
	var waited := 0
	while (m.fd_cache.get("fd", {}).get("cancel", null) == null) and waited < 300:
		await process_frame
		waited += 1
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	var fdl: Dictionary = m.fd_cache.get("fd", {})
	var lw := wins(fdl.get("cancel", {"windows": []}))
	ok(lw == w0 and not lw.is_empty(), "c live frame data carries the module's windows %s (waited %d frames)" % [lw, waited])
	var rects: Array = tl.cancel_rects()
	ok(rects.size() == lw.size(), "c one band rect per window (%d)" % rects.size())
	var img := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("C:/Temp/claude/w4-cancel")
	img.save_png("C:/Temp/claude/w4-cancel/n081w_strip.png")
	print("SHOT C:/Temp/claude/w4-cancel/n081w_strip.png %dx%d" % [img.get_width(), img.get_height()])
	var o: Vector2 = tl.get_global_rect().position
	var all_band := rects.size() > 0
	for rc in rects:
		var c := img.get_pixel(int(o.x + (rc as Rect2).get_center().x), int(o.y + (rc as Rect2).get_center().y))
		if not c.is_equal_approx(CancelWindows.COL_BAND):
			all_band = false
			print("     band centre pixel %s vs %s" % [c, CancelWindows.COL_BAND])
	ok(all_band, "c the pixel at every band's centre is the band colour")
	var fps_d := float(fdl.get("fps", 60))
	var fa := int(fdl.get("first", 0))
	var rc0: Rect2 = rects[0] if rects.size() > 0 else Rect2()
	var xa: float = tl.x_of((float(fa) + 0.5) / fps_d)
	var ca := img.get_pixel(int(o.x + xa), int(o.y + rc0.get_center().y))
	ok(not ca.is_equal_approx(CancelWindows.COL_BAND), "c the same row over the first active frame is not the band colour")
	var over_active := false
	for rc in rects:
		var x0: float = (rc as Rect2).position.x
		var x1: float = x0 + (rc as Rect2).size.x
		if xa >= x0 and xa <= x1:
			over_active = true
	control(over_active, "c1 a band lies over the first active frame")
	# d export
	var path := ProjectSettings.globalize_path("user://n081w/export.json")
	FrameData.write_json(fdl, path)
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	ok(wins(disk.get("cancel", {"windows": []})) == lw, "d exported frame-data JSON carries the same windows")
	print("N081W TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
