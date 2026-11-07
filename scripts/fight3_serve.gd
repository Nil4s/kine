## fight3_serve.gd - SERVE `disarm_check` and `group_fight` (L74: N045, N048; agent_tools.gd, the MCP server and the CLI share it).
##  disarm_check {kind?, grip? (book name) | hands + lever_m, force_n?, grip_n?}: verdict grip holds / works / wrist breaks first, with the torques.
##  group_fight {attackers: [{id, x, z, reach?}]}: a timed attack schedule, a wait position each, and the check numbers.
class_name Fight3Serve
extends RefCounted


static func serve(tool: String, _m: Variant, p: Dictionary) -> Dictionary:
	match tool:
		"disarm_check":
			var r := DisarmTruth.judge(p)
			return {"ok": bool(r.get("ok", false)), "result": r, "error": String(r.get("msg", ""))}
		"group_fight":
			var atk := []
			var src: Array = p.get("attackers", [])
			for i in src.size():
				var a: Dictionary = src[i]
				atk.append({"id": String(a.get("id", "a%d" % i)), "pos": Vector2(float(a.get("x", 0.0)), float(a.get("z", 0.0))), "reach": float(a.get("reach", 1.0))})
			if atk.is_empty():
				return {"ok": false, "error": "group_fight needs {attackers: [{id, x, z, reach?}]} (metres from the hero, who faces +z)"}
			var sch := GroupFight.plan(atk)
			var res := GroupFight.to_json(sch)
			res["checks"] = GroupFight.check(sch, atk)
			return {"ok": true, "result": res}
	return {"ok": false, "error": "unknown tool"}
