## godot --headless --path . -s tests/mcp_test.gd     (GATES V1)
## POSER AS AN MCP SERVER: tests/py/mcp_drive.py connects to tools/mcp/poser_mcp.py with the OFFICIAL python MCP SDK's
## stdio client (not our code), lists the tools and drives a session: open, pose, state at a moment, check, save; two
## refusals come back as tool errors with serve's reason, and the session lives on. This suite runs it.
extends SceneTree


func _init() -> void:
	var out := []
	var code := OS.execute("python", ["-u", ProjectSettings.globalize_path("res://tests/py/mcp_drive.py"), OS.get_executable_path(), ProjectSettings.globalize_path("res://")], out, true)
	var text := String(out[0]) if out.size() > 0 else ""
	var fails := 0
	var oks := 0
	for l in text.split("\n"):
		if l.begins_with("ok ") or l.begins_with("FAIL ") or l.begins_with("     "):
			print(l)
			if l.begins_with("FAIL"):
				fails += 1
			elif l.begins_with("ok"):
				oks += 1
	if oks + fails < 11:
		print("FAIL the driver ran %d of 11 checks (exit %d): %s" % [oks + fails, code, text.right(600)])
		fails += 1
	print("MCP TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
