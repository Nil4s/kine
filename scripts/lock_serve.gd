## lock_serve.gd - SERVE `lock_check` (agent_tools.gd; the CLI serve, the MCP server and the AI box share it) (N041 wired).
##   {clip?: scene file, fps?: int (30), locker?: 0 | 1 (0 = the hero locks the second fighter)}. No clip = the live scene (not moved). The result is
##   LockTruth.to_json of the judge: verdict, key frame, words, joint, axis, side, degrees past, and per frame the verdict and margin_deg.
class_name LockServe
extends RefCounted


static func serve(m: Node, p: Dictionary) -> Dictionary:
	var fps := int(p.get("fps", LockFixtures.FPS))
	if fps < 1:
		return {"ok": false, "error": "fps must be a whole number of frames a second, e.g. 30"}
	var lk := int(p.get("locker", 0))
	if lk != 0 and lk != 1:
		return {"ok": false, "error": "locker is 0 (the hero) or 1 (the second fighter)"}
	var S: Scene = m.S
	if p.has("clip"):
		var path := AgentTools.res(String(p["clip"]))
		if not FileAccess.file_exists(path):
			return {"ok": false, "error": "lock_check: no such scene file '%s'" % p["clip"]}
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not d is Dictionary:
			return {"ok": false, "error": "lock_check: '%s' is not a scene file" % p["clip"]}
		S = Scene.new()
		S.from_dict(d)
	if S.actors.is_empty():
		return {"ok": false, "error": "lock_check needs a scene of two bodies: this scene has one fighter. Open one with a partner or give {clip}"}
	return {"ok": true, "result": LockTruth.to_json(LockTruth.judge(S, fps, lk))}
