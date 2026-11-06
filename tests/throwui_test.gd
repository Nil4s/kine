## godot --path . -s tests/throwui_test.gd     (window suite: throwui:w)   L34: N040 THROW TRUTH WIRED into the app (scripts/throw_truth.gd is merged, tested by n040).
## Three places, the N082 pattern of #227: the "Throw check" panel (scripts/throw_panel.gd, toggled from the CHECK ribbon, m.throw_on), the agent call
## `throw_check {clip?, fps?, thrower?}` (scripts/throw_serve.gd through scripts/agent_tools.gd; the CLI serve, the MCP server and the AI box share it) and the
## one-shot CLI `throw_check <scene> [fps=N] [thrower=0|1]`.
## Bars, written BEFORE the implementation (the 4 n040 fixtures osoto / no_kuzushi / overcommit / apart, saved as scene files and opened in the app; 30 fps):
##  a. PANEL == DIRECT: for each fixture the panel's verdict, key frame, partner out and thrower margin (parsed from the TEXT the panel shows: its readout and
##     the tooltip of every frame cell) equal the direct ThrowTruth.judge of the same file: verdict equal, numbers within 0.1 mm, on EVERY frame.
##     Controls: the comparator rejects a number off by 0.5 mm; rejects the overcommit panel against the osoto direct call; the no-kuzushi panel is not "throw works".
##  b. AGENT CALL == DIRECT: throw_check {clip} returns JSON equal to ThrowTruth.to_json(judge) (stringified and parsed back), for all 4 fixtures; "throw_check" is
##     in AgentTools.MCP_EXTRA, poser_mcp.py names it in TOOLS and MATH_TOOLS, poser_cli.gd has a one-shot subcommand; an unknown clip and a one-body clip answer -32602.
##     Controls: the osoto reply differs from the overcommit reply; a made-up name is listed nowhere and answers -32601; a reply with one number nudged 0.5 mm is
##     not equal.
##  c. ONE BODY: with a single fighter the panel says WHY it is empty ("needs two bodies") and changes nothing: no undo step, the scene's bytes, the playhead and
##     the selected card unchanged. Control: a real edit (a card renamed) IS caught by the same hash; the panel with two bodies does not say "needs two bodies".
##  d. CLICK: a mouse click on the key frame's cell (through the panel's gui_input) sets the app's playhead to key / fps (within 1e-6 s) and leaves the undo
##     stack alone. Control: a click on a cell 5 frames away does not land on the key frame.
##  e. COST: the panel's per-frame hook costs <= 1 ms per call while hidden (mean of 300 calls, two bodies open, run count of the judge unchanged); once shown and
##     cached it is printed; planted: one uncached judge of osoto is slower than 1 ms (the measurement can see a cost).
extends SceneTree

var fails := 0
const FPS := 30
const KINDS := ["osoto", "no_kuzushi", "overcommit", "apart"]


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


func save(s: Scene, name: String) -> String:
	DirAccess.make_dir_recursive_absolute("user://throwui")
	var p := ProjectSettings.globalize_path("user://throwui/" + name + ".json")
	var fh := FileAccess.open(p, FileAccess.WRITE)
	fh.store_string(JSON.stringify(s.to_dict(stand(), false)))
	fh.close()
	return p


func load_scene(p: String) -> Scene:
	var s := Scene.new()
	s.from_dict(JSON.parse_string(FileAccess.get_file_as_string(p)))
	return s


func direct(p: String) -> Dictionary:
	return ThrowTruth.judge(load_scene(p), FPS)


## the comparator every number goes through: within 0.1 mm
func near(a_m: float, b_m: float) -> bool:
	return absf(a_m - b_m) <= 0.0001


func num(text: String, key: String) -> float:
	var re := RegEx.new()
	re.compile(key + " (-?[0-9]+\\.?[0-9]*) mm")
	var mt := re.search(text)
	return INF if mt == null else float(mt.get_string(1)) / 1000.0


func verdict_in(text: String) -> String:
	for v in ["throw works", "no kuzushi", "thrower falls", "no contact"]:
		if text.to_lower().begins_with(v) or text.to_lower().contains(v + " at") or text.to_lower().contains(": " + v):
			return v
	return ""


## the panel against the direct judge, every frame: returns "" when equal, else the first difference
func panel_vs_direct(P: ThrowPanel, r: Dictionary) -> String:
	var fr: Array = r["frames"]
	var ro := P.readout()
	var k: int = r["frame"]
	if verdict_in(ro) != String(r["verdict"]) or not ("f %d" % k) in ro:
		return "readout '%s' vs %s at f %d" % [ro, r["verdict"], k]
	if r["verdict"] != "no contact":
		if not near(num(ro, "partner out"), float(fr[k]["partner"]["out"])) or not near(num(ro, "thrower margin"), float(fr[k]["thrower"]["margin"])):
			return "readout numbers '%s'" % ro
	for f in fr.size():
		var tip := P.tip_for(f)
		if verdict_in(tip.split(": ", true, 1)[1]) != String(fr[f]["verdict"]):
			return "frame %d verdict '%s' vs %s" % [f, tip, fr[f]["verdict"]]
		if not near(num(tip, "partner out"), float(fr[f]["partner"]["out"])) or not near(num(tip, "thrower margin"), float(fr[f]["thrower"]["margin"])):
			return "frame %d numbers '%s' vs out %.5f margin %.5f" % [f, tip, fr[f]["partner"]["out"], fr[f]["thrower"]["margin"]]
	return ""


func _init() -> void:
	var paths := {}
	var fixture_verdict := {}
	for k in KINDS:
		var S := ThrowFixtures.build(k)
		paths[k] = save(S, k)
		fixture_verdict[k] = ThrowTruth.judge(S, FPS)["verdict"]
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var T := AgentTools.new(m)
	var D := {}
	for k in KINDS:
		D[k] = direct(paths[k])
		print("-- ", k, ": ", D[k]["text"])
		ok(D[k]["verdict"] == fixture_verdict[k], "0 %s: the saved file judges as the in-memory fixture (%s)" % [k, D[k]["verdict"]])
	ok(D["osoto"]["verdict"] == "throw works" and D["no_kuzushi"]["verdict"] == "no kuzushi" and D["overcommit"]["verdict"] == "thrower falls" and D["apart"]["verdict"] == "no contact", "0 the four fixtures give the four verdicts")

	# a. the panel
	var panels := {}
	var rid := 0
	for k in KINDS:
		rid += 1
		await T.request(rid, "open", {"path": paths[k]})
		m.throw_on = true
		m._refresh()
		for i in 3:
			await process_frame
		while m._throw_busy():   # L42: the judge runs on a worker now: wait for the result to land
			await process_frame
		var P: ThrowPanel = m.throw_panel
		panels[k] = P
		var diff := "no panel" if P == null or not P.visible else panel_vs_direct(P, D[k])
		ok(diff == "", "a %s: the panel's readout and all %d frame tooltips equal the direct judge within 0.1 mm  %s" % [k, (D[k]["frames"] as Array).size(), diff])
		print("     readout: ", P.readout() if P != null else "-")
		if k == "osoto":
			var kk: int = D[k]["frame"]
			control(near(num(P.tip_for(kk), "partner out") + 0.0005, float(D[k]["frames"][kk]["partner"]["out"])), "a1 the comparator accepts a partner out 0.5 mm too big")
			control(panel_vs_direct(P, D["overcommit"]) == "", "a2 the osoto panel equals the overcommit direct call")
		if k == "no_kuzushi":
			control(verdict_in(P.readout()) == "throw works", "a3 the no-kuzushi panel says throw works")
		m.throw_on = false
		m._refresh()
	# b. the agent call
	var replies := {}
	for k in KINDS:
		rid += 1
		var rp: Dictionary = await T.request(rid, "throw_check", {"clip": paths[k]})
		replies[k] = JSON.parse_string(JSON.stringify(rp.get("result", {})))
		var want: Dictionary = JSON.parse_string(JSON.stringify(ThrowTruth.to_json(D[k])))
		ok(replies[k] == want and not (want["frames"] as Array).is_empty(), "b %s: throw_check == ThrowTruth.to_json(judge), %s, key f %s, %d frames, %d bytes" % [k, want["verdict"], want["frame"], (want["frames"] as Array).size(), JSON.stringify(want).length()])
	control(replies["osoto"] == replies["overcommit"], "b1 the osoto reply equals the overcommit reply")
	var nudged: Dictionary = JSON.parse_string(JSON.stringify(replies["osoto"]))
	nudged["frames"][int(nudged["frame"])]["partner"]["out_m"] = float(nudged["frames"][int(nudged["frame"])]["partner"]["out_m"]) + 0.0005
	control(nudged == JSON.parse_string(JSON.stringify(ThrowTruth.to_json(D["osoto"]))), "b2 a reply with the key frame's out nudged 0.5 mm equals the direct call")
	var bad: Dictionary = await T.request(90, "throw_check", {"clip": "nope/none.json"})
	ok(bad.has("error") and int(bad["error"]["code"]) == -32602, "b a missing clip: %s" % JSON.stringify(bad.get("error", {})).left(110))
	await T.request(91, "open", {"path": "scenes/combo3.json"})
	var one: Dictionary = await T.request(92, "throw_check", {})
	ok(one.has("error") and int(one["error"]["code"]) == -32602 and String(one["error"]["message"]).contains("two bodies"), "b one body (live combo3): %s" % JSON.stringify(one.get("error", {})).left(120))
	var py := FileAccess.get_file_as_string("res://tools/mcp/poser_mcp.py")
	var cli := FileAccess.get_file_as_string("res://tools/poser_cli.gd")
	ok("throw_check" in AgentTools.MCP_EXTRA, "b agent tool list: MCP_EXTRA has throw_check")
	ok(py.contains("\"throw_check\": (\"throw_check\"") and py.split("MATH_TOOLS = [")[1].split("]")[0].contains("\"throw_check\""), "b MCP: TOOLS names throw_check and MATH_TOOLS lists it")
	ok(cli.contains("\"throw_check\":"), "b CLI: a one-shot `throw_check` subcommand")
	var made_up := "throw_check_nope"
	control("throw_check_nope" in AgentTools.MCP_EXTRA or py.contains("\"%s\": (" % made_up) or cli.contains("\"%s\":" % made_up), "b3 a made-up tool name is listed somewhere")
	var no_m: Dictionary = await T.request(93, made_up, {})
	ok(no_m.has("error") and int(no_m["error"]["code"]) == -32601, "b the made-up name answers -32601")

	# c. one body: the panel says why, changes nothing
	await T.request(94, "open", {"path": "scenes/combo3.json"})
	m.throw_on = false
	m._refresh()
	var h0 := JSON.stringify(m.S.to_dict(m.B, false)).hash()
	var u0: int = m.undo.size()
	var ph0: float = m.playhead
	var sc0: int = m.sel_card
	m.throw_on = true
	m._refresh()
	for i in 3:
		await process_frame
	while m._throw_busy():   # L42: the judge runs on a worker now: wait for the result to land
		await process_frame
	var P1: ThrowPanel = m.throw_panel
	var txt := P1.readout() if P1 != null else ""
	print("     one-body panel: ", txt)
	ok(P1 != null and P1.visible and txt.to_lower().contains("needs two bodies"), "c one body: the panel is shown and says why it is empty")
	ok(m.undo.size() == u0 and JSON.stringify(m.S.to_dict(m.B, false)).hash() == h0 and is_equal_approx(m.playhead, ph0) and m.sel_card == sc0, "c one body: no undo step (%d), scene hash, playhead and selected card unchanged" % m.undo.size())
	var edited: Scene = m.S.clone()
	(edited.cards[0] as Dictionary)["name"] = String(edited.cards[0]["name"]) + "_x"
	control(JSON.stringify(edited.to_dict(m.B, false)).hash() == h0, "c1 a renamed card leaves the scene hash unchanged")
	control(not txt.to_lower().contains("needs two bodies"), "c2 the one-body panel does not explain itself")
	m.throw_on = false
	m._refresh()

	# d. click the key frame
	await T.request(95, "open", {"path": paths["osoto"]})
	m.throw_on = true
	m._refresh()
	for i in 3:
		await process_frame
	while m._throw_busy():   # L42: the judge runs on a worker now: wait for the result to land
		await process_frame
	var P2: ThrowPanel = m.throw_panel
	var kf: int = D["osoto"]["frame"]
	var u1: int = m.undo.size()
	var click := func(f: int) -> void:
		var x: float = P2.x_of_frame(f)
		var y: float = P2.cell_y()
		for pressed in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = pressed
			ev.position = Vector2(x, y)
			P2._gui_input(ev)
	m.playhead = 0.0
	click.call(kf + 5)
	var other: float = m.playhead
	m.playhead = 0.0
	click.call(kf)
	ok(absf(float(m.playhead) - float(kf) / float(FPS)) <= 1e-6 and kf > 0, "d clicking the key frame's cell sets the playhead to %.4f s (f %d): now %.4f" % [float(kf) / FPS, kf, m.playhead])
	ok(m.undo.size() == u1, "d the click is not an undo step")
	control(absf(other - float(kf) / float(FPS)) <= 1e-6, "d1 a click on the cell 5 frames away (%.4f s) lands on the key frame" % other)

	# e. cost
	m.throw_on = false
	m._refresh()
	var runs0: int = m.throw_judge_runs
	var t0 := Time.get_ticks_usec()
	for i in 300:
		m._throw_refresh()
	var hidden_ms := float(Time.get_ticks_usec() - t0) / 300.0 / 1000.0
	ok(hidden_ms <= 1.0 and m.throw_judge_runs == runs0, "e hidden: %.4f ms per call (<= 1 ms), the judge ran %d times meanwhile" % [hidden_ms, m.throw_judge_runs - runs0])
	m.throw_on = true
	m._throw_refresh()
	var t1 := Time.get_ticks_usec()
	for i in 300:
		m._throw_refresh()
	print("     shown and cached: %.4f ms per call" % (float(Time.get_ticks_usec() - t1) / 300.0 / 1000.0))
	var t2 := Time.get_ticks_usec()
	ThrowTruth.judge(load_scene(paths["osoto"]), FPS)
	var judge_ms := float(Time.get_ticks_usec() - t2) / 1000.0
	print("     one uncached judge of osoto: %.1f ms" % judge_ms)
	control(judge_ms <= 1.0, "e1 an uncached judge costs <= 1 ms")

	# the picture
	m.throw_on = true
	m._refresh()
	for i in 20:
		await process_frame
	while m._throw_busy():
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("C:/Temp/claude/L34")
	img.save_png("C:/Temp/claude/L34/throwui_osoto.png")
	print("SHOT C:/Temp/claude/L34/throwui_osoto.png %dx%d" % [img.get_width(), img.get_height()])
	print("THROWUI TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
