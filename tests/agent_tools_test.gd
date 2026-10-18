## godot --headless --path . -s tests/agent_tools_test.gd     (round 46, GATES BB0)
## ONE TOOL SET: serve's handler lives in scripts/agent_tools.gd (AgentTools), and the CLI only reads and writes lines.
##   1 the same request script through `poser_cli serve` gives a transcript BYTE-IDENTICAL to the one recorded before the
##     move (refs/agent/serve_transcript.jsonl: 19 lines; every method, 3 refusals, a save onto Nick's scene refused)
##   2 one source: tools/poser_cli.gd defines none of handle / request / step / measure / findings, agent_tools.gd all
##   3 in the app's own process: AgentTools on a live poser answers request() as handle() answers the same JSON line,
##     and a step it runs is an undo step on THAT poser (what the AI box will rely on)
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	# 1
	var tmp := OS.get_user_data_dir().path_join("agent_tools_test.jsonl")
	var out := []
	OS.execute("python", ["-u", ProjectSettings.globalize_path("res://tests/py/serve_transcript.py"), OS.get_executable_path(),
		ProjectSettings.globalize_path("res://"), tmp], out, true)
	var got := FileAccess.get_file_as_string(tmp)
	var want := FileAccess.get_file_as_string("res://refs/agent/serve_transcript.jsonl")
	var gl := got.split("\n")
	var wl := want.split("\n")
	var first := -1
	for i in maxi(gl.size(), wl.size()):
		if i >= gl.size() or i >= wl.size() or gl[i] != wl[i]:
			first = i
			break
	ok(got == want and wl.size() >= 19, "1 the transcript is byte-identical: %d of %d bytes, %d lines%s" % [got.length(), want.length(), gl.size(),
		"" if first < 0 else "; first different line %d: %s" % [first, (gl[first] if first < gl.size() else "<none>").left(160)]])
	DirAccess.remove_absolute(tmp)
	# 2
	var cli := FileAccess.get_file_as_string("res://tools/poser_cli.gd")
	var at := FileAccess.get_file_as_string("res://scripts/agent_tools.gd")
	var defs := ["func handle(", "func request(", "func step(", "func measure(", "func findings("]
	var in_cli := defs.filter(func(d): return cli.contains(d))
	var in_at := defs.filter(func(d): return at.contains(d))
	ok(in_cli.is_empty() and in_at.size() == defs.size(), "2 one source: the CLI defines %s, agent_tools %d of %d" % [in_cli, in_at.size(), defs.size()])
	# 3
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var A := AgentTools.new(m)
	await A.request(1, "open", {"path": "scenes/combo3.json"})
	var r1: Dictionary = await A.request(2, "describe", {})
	var r2: Dictionary = await A.handle('{"jsonrpc":"2.0","id":2,"method":"describe"}')
	var c0 := JSON.stringify(m.S.cards)
	var u0: int = m.undo.size()
	var r3: Dictionary = await A.request(3, "run", {"steps": ["card=2", "pose=raise the right arm 90", "update"]})
	var u1: int = m.undo.size()
	var c1 := JSON.stringify(m.S.cards)
	for k in u1 - u0:
		m._undo()
	var c2 := JSON.stringify(m.S.cards)
	var r4: Dictionary = await A.request(4, "nope", {})
	ok(JSON.stringify(r1.get("result")) == JSON.stringify(r2.get("result")) and r1.has("result") and r3.has("result") and u1 > u0 and c1 != c0 and c2 == c0
		and r4.has("error") and int(r4["error"]["code"]) == -32601,
		"3 in-process: request() == handle() (%d chars), a run made %d undo step(s) on this poser (cards changed %s) and undoing them put the cards back exactly (%s), an unknown method -> %s"
		% [JSON.stringify(r1).length(), u1 - u0, c1 != c0, c2 == c0, r4.get("error", {}).get("code", "-")])
	m.queue_free()
	print("AGENT TOOLS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
