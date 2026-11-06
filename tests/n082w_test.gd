## godot --path . -s tests/n082w_test.gd     (window suite: n082w:w)   L11: N082 "reactable" WIRED (scripts/reactable.gd, reactable_strip.gd are merged in #223).
## Three places: the agent call `reactable {clip?, frame?, latency_ms?, fps?}` (scripts/reactable_serve.gd through scripts/agent_tools.gd: the CLI `serve`,
## the MCP server and the AI box all run it; the one-shot CLI has `reactable <scene>`), and the frame-data strip on the timeline
## (scripts/reactable_cells.gd: one cell per frame, tell green / red, active dark, the rest dim).
## Bars, written BEFORE the implementation (60 fps; the same attacker as reactable_test: guard hold 10 f, cock back over W f, strike in 3 f, back in 12 f):
##  a. AGENT CALL: reactable {clip: slow} returns JSON equal to Reactable.to_json(Reactable.of_scene(...)) called directly on the same file (stringified, parsed
##     back, compared as data); the same for the fast clip; {frame} adds an "at_frame" with state tell / active / idle and the run number.
##     Control: the fast clip's verdict differs from the slow clip's (status and window); a claim "fast == slow" must be false; an unknown clip is a -32602 error.
##  b. LISTS: "reactable" is in AgentTools.MCP_EXTRA (the agent tool list; METHODS is pinned by the byte-for-byte transcript), poser_mcp.py names it in TOOLS and in
##     MATH_TOOLS, and poser_cli.gd has a one-shot `reactable` subcommand. Control: a made-up name is in none of them and the call answers -32601.
##  c. PANEL: ReactableCells.build(fd, verdict) has N cells for the N-frame clip and every cell's colour equals the test's own per-frame state (active -> ACT;
##     tell frames [readable, first_active) -> OK / NO by status; else IDLE). The live timeline, with Frame data on and the slow clip open, owns that strip with
##     N cells. Control: an empty clip (fd {}) gives null and no crash; the slow tell cell is not red and the fast tell cell is not green.
##  d. SIZE: the reply's bytes on combo3 and on the slow fixture are printed and are < 2048.
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


func attacker(w: int) -> Scene:
	var B := stand()
	var a0: Vector3 = B.ang["upperarm_r"]
	var guard := posed("upperarm_r", Vector3(10.0, a0.y, a0.z))
	var cock := posed("upperarm_r", Vector3(-45.0, a0.y, a0.z))
	var hit := posed("upperarm_r", Vector3(70.0, a0.y, a0.z))
	var s := Scene.new()
	s.from_dict({"scene": "zz_n082w", "fps": 30, "natural": false, "on_floor": false, "pin": false, "cards": [
		{"name": "guard", "pose": guard, "move": -1.0, "hold": f(10)}, {"name": "cock", "pose": cock, "move": f(w), "hold": 0.0},
		{"name": "strike", "pose": hit, "move": f(3), "hold": f(17)}, {"name": "back", "pose": guard, "move": f(12), "hold": f(3)}]})
	return s


func save(s: Scene, name: String) -> String:
	DirAccess.make_dir_recursive_absolute("user://n082w")
	var p := ProjectSettings.globalize_path("user://n082w/" + name + ".json")
	var fh := FileAccess.open(p, FileAccess.WRITE)
	fh.store_string(JSON.stringify(s.to_dict(stand(), false)))
	fh.close()
	return p


func load_scene(p: String) -> Scene:
	var s := Scene.new()
	s.from_dict(JSON.parse_string(FileAccess.get_file_as_string(p)))
	return s


## the verdict called directly, the way the module's own test does, on the same file
func direct(p: String, latency := 0.0) -> Dictionary:
	return JSON.parse_string(JSON.stringify(Reactable.to_json(Reactable.of_scene(load_scene(p), stand(), FPS, latency))))


## the test's OWN per-frame colour: active -> ACT; the tell of a run [readable, first_active) -> OK / NO; else IDLE
func own_colour(fd: Dictionary, r: Dictionary, i: int) -> Color:
	if bool(fd["frames"][i]["active"]):
		return ReactableCells.COL_ACT
	for run in r["runs"]:
		if i >= int(run["readable"]) and i < int(run["first_active"]):
			return ReactableStrip.COL_OK if run["status"] == "reactable" else ReactableStrip.COL_NO
	return ReactableCells.COL_IDLE


func _init() -> void:
	var slow_p := save(attacker(24), "slow")
	var fast_p := save(attacker(4), "fast")
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var T := AgentTools.new(m)
	await T.request(1, "open", {"path": "scenes/combo3.json"})
	var live_before := JSON.stringify(m.S.to_dict(m.B, false))
	# a. the agent call
	var rs: Dictionary = await T.request(2, "reactable", {"clip": slow_p})
	var rf: Dictionary = await T.request(3, "reactable", {"clip": fast_p})
	var ds := direct(slow_p)
	var df := direct(fast_p)
	var ps: Dictionary = JSON.parse_string(JSON.stringify(rs.get("result", {})))
	var pf: Dictionary = JSON.parse_string(JSON.stringify(rf.get("result", {})))
	ok(not ds["runs"].is_empty() and ps == ds, "a slow clip: call == direct module (status %s, window %s f, need %s f)" % [ds["runs"][0]["status"], ds["runs"][0]["window_f"], ds["runs"][0]["need_f"]])
	ok(not df["runs"].is_empty() and pf == df, "a fast clip: call == direct module (status %s, window %s f)" % [df["runs"][0]["status"], df["runs"][0]["window_f"]])
	control(ps == pf, "a1 the fast clip's verdict equals the slow clip's")
	control(ps["runs"][0]["status"] == pf["runs"][0]["status"] or ps["runs"][0]["window_f"] == pf["runs"][0]["window_f"], "a2 slow and fast agree on status or window")
	var run0: Dictionary = ds["runs"][0]
	var ra: Dictionary = (await T.request(4, "reactable", {"clip": slow_p, "frame": int(run0["first_active"])})).get("result", {})
	var rt: Dictionary = (await T.request(5, "reactable", {"clip": slow_p, "frame": int(run0["readable"])})).get("result", {})
	var ri: Dictionary = (await T.request(6, "reactable", {"clip": slow_p, "frame": 0})).get("result", {})
	ok(ra.get("at_frame", {}).get("state") == "active" and rt.get("at_frame", {}).get("state") == "tell" and int(rt.get("at_frame", {}).get("run", 0)) == 1 and ri.get("at_frame", {}).get("state") == "idle",
		"a frame: first_active -> %s, tell start -> %s (run %s), frame 0 -> %s" % [ra.get("at_frame", {}).get("state"), rt.get("at_frame", {}).get("state"), rt.get("at_frame", {}).get("run"), ri.get("at_frame", {}).get("state")])
	var rl: Dictionary = (await T.request(7, "reactable", {"clip": slow_p, "latency_ms": 80.0})).get("result", {})
	ok(JSON.parse_string(JSON.stringify(rl)) == direct(slow_p, 80.0) and float(rl.get("latency_ms", 0)) == 80.0, "a latency_ms 80 echoed and equal to direct")
	var bad: Dictionary = await T.request(8, "reactable", {"clip": "nope/none.json"})
	ok(bad.has("error") and int(bad["error"]["code"]) == -32602, "a missing clip: %s" % JSON.stringify(bad.get("error", {})).left(120))
	var live: Dictionary = await T.request(9, "reactable", {})
	ok(live.has("result") and JSON.stringify(m.S.to_dict(m.B, false)) == live_before, "a no clip = the live scene (combo3), the live scene unchanged")
	# b. lists
	var py := FileAccess.get_file_as_string("res://tools/mcp/poser_mcp.py")
	var cli := FileAccess.get_file_as_string("res://tools/poser_cli.gd")
	ok("reactable" in AgentTools.MCP_EXTRA, "b agent tool list: MCP_EXTRA has reactable")
	ok(py.contains("\"reactable\": (\"reactable\"") and py.contains("MATH_TOOLS = [") and py.split("MATH_TOOLS = [")[1].split("]")[0].contains("\"reactable\""), "b MCP: TOOLS names reactable and MATH_TOOLS lists it")
	ok(cli.contains("\"reactable\":"), "b CLI: a one-shot `reactable` subcommand")
	var made_up := "reactable_nope"
	control(made_up in AgentTools.MCP_EXTRA or py.contains("\"%s\": (" % made_up) or cli.contains("\"%s\":" % made_up), "b1 a made-up tool name is listed somewhere")
	var no_m: Dictionary = await T.request(10, made_up, {})
	ok(no_m.has("error") and int(no_m["error"]["code"]) == -32601, "b the made-up name answers -32601")
	# d. size
	var bs := JSON.stringify(rs.get("result", {})).to_utf8_buffer().size()
	var bc := JSON.stringify(live.get("result", {})).to_utf8_buffer().size()
	print("SIZE reactable reply: slow fixture %d bytes, combo3 (live) %d bytes" % [bs, bc])
	ok(bs < 2048 and bc < 2048, "d reply under 2 KB: slow %d B, combo3 %d B" % [bs, bc])
	# c. the panel
	var fds := FrameData.analyze(load_scene(slow_p), stand(), FPS)
	var fdf := FrameData.analyze(load_scene(fast_p), stand(), FPS)
	var vs := Reactable.analyze(fds)
	var vf := Reactable.analyze(fdf)
	var ns: ReactableCells = ReactableCells.build(fds, vs)
	var nf: ReactableCells = ReactableCells.build(fdf, vf)
	var good := ns != null and ns.cells.size() == (fds["frames"] as Array).size() and (fds["frames"] as Array).size() > 20
	var bad_i := -1
	if good:
		for i in ns.cells.size():
			if not (ns.cells[i] as Color).is_equal_approx(own_colour(fds, vs, i)):
				bad_i = i
				break
	ok(good and bad_i < 0, "c strip: %d cells for the %d-frame clip, every colour equals the test's own state (first mismatch %d)" % [ns.cells.size() if ns else -1, (fds["frames"] as Array).size(), bad_i])
	var tell_s := int(vs["runs"][0]["readable"])
	var tell_f := int(vf["runs"][0]["readable"])
	ok(ns != null and nf != null and (ns.cells[tell_s] as Color).is_equal_approx(ReactableStrip.COL_OK) and (nf.cells[tell_f] as Color).is_equal_approx(ReactableStrip.COL_NO), "c slow tell cell green, fast tell cell red")
	control(ns != null and (ns.cells[tell_s] as Color).is_equal_approx(ReactableStrip.COL_NO), "c1 the slow tell cell is red")
	control(nf != null and (nf.cells[tell_f] as Color).is_equal_approx(ReactableStrip.COL_OK), "c2 the fast tell cell is green")
	var none: Variant = ReactableCells.build({}, Reactable.analyze({}))
	var none2: Variant = ReactableCells.build({"fps": 60, "n": 0, "frames": []}, Reactable.analyze({}))
	ok(none == null and none2 == null, "c empty clip: no strip, no crash")
	# the live timeline
	await T.request(11, "open", {"path": slow_p})
	m.fd_on = true
	m._refresh()
	var tl: Control = m.ui_timeline
	var waited := 0
	while (tl.get("rx") == null or not (tl.get("rx") as Node).visible) and waited < 300:
		await process_frame
		waited += 1
	var rx: Variant = tl.get("rx")
	var n_live := (m.fd_cache.get("fd", {}).get("frames", []) as Array).size()
	ok(rx != null and (rx as ReactableCells).cells.size() == n_live and n_live > 20, "c live timeline strip: %d cells for the %d-frame clip (waited %d frames)" % [(rx as ReactableCells).cells.size() if rx != null else -1, n_live, waited])
	m.fd_on = false
	m._refresh()
	await process_frame
	ok(tl.get("rx") == null or not (tl.get("rx") as Node).visible, "c Frame data off: the strip is hidden")
	m.fd_on = true
	m._refresh()
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://out"))
	img.save_png(ProjectSettings.globalize_path("res://out/n082w_panel.png"))
	print("SHOT out/n082w_panel.png %dx%d" % [img.get_width(), img.get_height()])
	print("N082W TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
