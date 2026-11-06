## throw_serve.gd - SERVE `throw_check` (agent_tools.gd; the CLI serve, the MCP server and the AI box share it) (L34, N040 wired).
##   {clip?: scene file, fps?: int (30), thrower?: 0 | 1 (0 = the hero)}. No clip = the live scene (not moved). The result is ThrowTruth.to_json of the judge:
##   verdict, key frame, words, and per frame the verdict, partner out_m and thrower margin_m. Maths: scripts/throw_truth.gd.
class_name ThrowServe
extends RefCounted


static func serve(m: Node, p: Dictionary) -> Dictionary:
	var fps := int(p.get("fps", ThrowFixtures.FPS))
	if fps < 1:
		return {"ok": false, "error": "fps must be a whole number of frames a second, e.g. 30"}
	var th := int(p.get("thrower", 0))
	if th != 0 and th != 1:
		return {"ok": false, "error": "thrower is 0 (the hero) or 1 (the second fighter)"}
	var S: Scene = m.S
	if p.has("clip"):
		var path := AgentTools.res(String(p["clip"]))
		if not FileAccess.file_exists(path):
			return {"ok": false, "error": "throw_check: no such scene file '%s'" % p["clip"]}
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not d is Dictionary:
			return {"ok": false, "error": "throw_check: '%s' is not a scene file" % p["clip"]}
		S = Scene.new()
		S.from_dict(d)
	if S.actors.is_empty():
		return {"ok": false, "error": "throw_check needs a scene of two bodies: this scene has one fighter. Open one with a partner or give {clip}"}
	var full := ThrowTruth.to_json(ThrowTruth.judge(S, fps, th))
	if bool(p.get("brief", false)):   # L45: the verdict, the key frame, and that frame's partner out and thrower margin (the same numbers as the full reply)
		var out := {"ok": full["ok"], "verdict": full["verdict"], "frame": full["frame"]}
		var kf := int(full["frame"])
		if kf >= 0 and kf < (full["frames"] as Array).size():
			var fk: Dictionary = full["frames"][kf]
			out["partner_out_m"] = fk["partner"]["out_m"]
			out["thrower_margin_m"] = fk["thrower"]["margin_m"]
		return {"ok": true, "result": out}
	return {"ok": true, "result": full}
