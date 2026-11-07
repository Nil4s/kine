## blend_matrix_serve.gd - SERVE `blend_matrix` (agent_tools.gd; the CLI serve, the MCP server and the AI box share it) (N084).
##   {clips?: [scene file, ...], blend_s?: number, a?: name, b?: name, full?: bool, top?: int}. No clips = every scene and move of scenes/ and moves/ with motion.
##   The reply: names, blend_s, blend_frames, engine, ms, bars, "grid" (one string per row: B bad, w watch, . ok), "bad" (the ranked bad pairs, each with
##   its numbers), warn; with a and b ALSO "cell" (that pair's numbers); with full the whole "cells" matrix. Maths: scripts/blend_matrix.gd.
class_name BlendMatrixServe
extends RefCounted

const MAX_CLIPS := 40


static func serve(_m: Node, p: Dictionary) -> Dictionary:
	var blend_s := float(p.get("blend_s", 0.2))
	if blend_s <= 0.0 or blend_s > 5.0:
		return {"ok": false, "error": "blend_s is the crossfade time in seconds, e.g. 0.2 (more than 0, at most 5)"}
	var clips: Array
	if p.has("clips"):
		if not (p["clips"] is Array) or (p["clips"] as Array).is_empty():
			return {"ok": false, "error": "clips is a list of scene files, e.g. [\"scenes/idle.json\", \"scenes/walk_bat.json\"]"}
		var paths := []
		for c in p["clips"]:
			var path := AgentTools.res(String(c))
			if not FileAccess.file_exists(path):
				return {"ok": false, "error": "blend_matrix: no such scene file '%s'" % c}
			paths.append(path)
		clips = BlendMatrix.clips_of_files(paths)
	else:
		clips = BlendMatrix.clips_of_dirs(["res://scenes/", "res://moves/"])
	if clips.is_empty():
		return {"ok": false, "error": "blend_matrix: no clip with motion to blend"}
	if clips.size() > MAX_CLIPS:
		return {"ok": false, "error": "blend_matrix: %d clips is over the %d a call takes: give clips" % [clips.size(), MAX_CLIPS]}
	var M := BlendMatrix.matrix(clips, blend_s)
	var out := M.duplicate()
	var grid := []
	for row in M["cells"]:
		var s := ""
		for c in row:
			s += "B" if c["verdict"] == "bad" else ("w" if c["verdict"] == "warn" else ".")
		grid.append(s)
	out["grid"] = grid
	var names: Array = M["names"]
	if p.has("a") or p.has("b"):
		var i := names.find(String(p.get("a", "")))
		var j := names.find(String(p.get("b", "")))
		if i < 0 or j < 0:
			return {"ok": false, "error": "blend_matrix: a and b are two of the clip names %s" % [names]}
		out["cell"] = M["cells"][i][j]
	if not bool(p.get("full", false)):
		out.erase("cells")
	var top := int(p.get("top", 20))
	out["bad"] = (M["bad"] as Array).slice(0, maxi(top, 0))
	out["words"] = BlendMatrix.words(M, 12)
	out["bad_total"] = (M["bad"] as Array).size()
	return {"ok": true, "result": out}
