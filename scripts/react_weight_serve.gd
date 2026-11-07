## react_weight_serve.gd - SERVE `react_time`, `react_place`, `weight_slider` (L89; agent_tools.gd, the MCP server share it).
##  react_time {clip?, attacker?, defender?, rt?}: the defender's block against the attacker's cue: status ok / superhuman / no cue / no block. Reads only.
##  react_place {clip?, attacker?, defender?, rt?}: shifts the block to cue + rt. Live: ONE undo step (nothing is pushed when it refuses); with clip a copy.
##  weight_slider {value, clip?}: the mass slider (log2 of the mass ratio) on the open scene; live: ONE undo step, nothing pushed when it refuses.
## Fighters are numbered 0 = the hero, 1.. = the scene's actors.
class_name ReactWeightServe
extends RefCounted


static func _load(tool: String, m: Node, p: Dictionary) -> Dictionary:
	if not p.has("clip"):
		m._actors_sync()
		return {"ok": true, "S": m._hero_scene(), "live": true}
	var path := AgentTools.res(String(p["clip"]))
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "%s: no such scene file '%s'" % [tool, p["clip"]]}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		return {"ok": false, "error": "%s: '%s' is not a scene file" % [tool, p["clip"]]}
	var S := Scene.new()
	S.from_dict(d)
	return {"ok": true, "S": S, "live": false}


static func _fighter(S: Scene, i: int) -> Scene:
	if i == 0:
		return S
	if i - 1 < S.actors.size():
		return S.actors[i - 1]["scene"]
	return null


static func serve(tool: String, m: Node, p: Dictionary) -> Dictionary:
	var L := _load(tool, m, p)
	if not L["ok"]:
		return L
	var S: Scene = L["S"]
	var live: bool = L["live"]
	if tool == "weight_slider":
		var v := float(p.get("value", 0.0))
		var trial := S.clone()
		var r := WeightFeel.slider(trial, v)
		if not r["ok"]:
			return {"ok": false, "error": String(r["msg"])}
		if live:
			m._step_hint = "weight slider"
			m._push_undo()
			m._markers_hold()
			S.cards = trial.cards
			m._markers_follow()
			m._retimed()
		else:
			S = trial
		return {"ok": true, "result": {"msg": r["msg"], "ratio": r["ratio"], "card": r["card"], "length_s": S.length()}}
	var a := int(p.get("attacker", 0))
	var d := int(p.get("defender", 1))
	var A := _fighter(S, a)
	var D := _fighter(S, d)
	if A == null or D == null or a == d:
		return {"ok": false, "error": "%s: needs two fighters (attacker %d, defender %d): add an actor first" % [tool, a, d]}
	var rt := float(p.get("rt", Counter.REACT))
	if tool == "react_time":
		return {"ok": true, "result": ReactTime.read(A, D, rt)}
	var trial: Dictionary = ReactTime.place(A.clone(), D.clone(), rt)
	if not trial["ok"]:
		return {"ok": false, "error": String(trial["msg"])}
	if live:
		m._step_hint = "react place"
		m._push_undo()
	var r2 := ReactTime.place(A, D, rt)
	if live:
		m._fight_done()
	return {"ok": true, "result": r2}
