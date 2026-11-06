## reactable_serve.gd - SERVE `reactable` (agent_tools.gd; the CLI serve, the MCP server and the AI box share it) (L11, N082 wired).
##   {clip?: scene file, frame?: int, latency_ms?: number, fps?: int}. No clip = the live scene (not moved). The result is Reactable.to_json of the verdict,
##   plus "at_frame" ({frame, state: tell | active | idle, run}) when `frame` is given. Maths: scripts/reactable.gd.
class_name ReactableServe
extends RefCounted


static func serve(m: Node, p: Dictionary) -> Dictionary:
	var fps := int(p.get("fps", FrameData.FPS))
	if fps < 1:
		return {"ok": false, "error": "fps must be a whole number of frames a second, e.g. 60"}
	var lat := float(p.get("latency_ms", 0.0))
	if lat < 0.0:
		return {"ok": false, "error": "latency_ms is zero or more (an online game's netcode delay)"}
	var S: Scene = m.S
	if p.has("clip"):
		var path := AgentTools.res(String(p["clip"]))
		if not FileAccess.file_exists(path):
			return {"ok": false, "error": "reactable: no such scene file '%s'" % p["clip"]}
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not d is Dictionary:
			return {"ok": false, "error": "reactable: '%s' is not a scene file" % p["clip"]}
		S = Scene.new()
		S.from_dict(d)
	if S.cards.size() < 2:
		return {"ok": false, "error": "reactable needs a scene of 2+ cards: open one or give {clip}"}
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	B.ground()
	var fd := FrameData.analyze(S, B, fps)
	var r := Reactable.analyze(fd, lat)
	var out := Reactable.to_json(r)
	if p.has("frame"):
		var st := ReactableCells.state_at(fd, r, int(p["frame"]))
		out["at_frame"] = st if not st.is_empty() else {"frame": int(p["frame"]), "state": "outside the clip"}
	return {"ok": true, "result": out}
