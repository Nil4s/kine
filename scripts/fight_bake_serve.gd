## fight_bake_serve.gd - SERVE `bake_reaction`, `fix_impact`, `bake_momentum` (L76; agent_tools.gd, the MCP server and the CLI share it).
##  bake_reaction {clip?, frame?, tag?, y?, head_y?, region?, impulse?, side?}: the struck partner gets the region's reaction as a card (scripts/fight_bake.gd).
##  fix_impact {clip?, fps?}: the striker's flagged wrist / knee is fixed in the cards around the contact.
##  bake_momentum {clip?, frame?, t?, v_a?:[x,y,z], v_b?, m_a?, m_b?, sex?, e?}: body_collide's velocities keyed on both roots.
## Without clip the live scene is edited as ONE undo step (nothing is pushed when the bake refuses); with clip a copy is baked and only the numbers come back.
class_name FightBakeServe
extends RefCounted


static func _v3(a: Variant) -> Variant:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() >= 3 else null


static func serve(tool: String, m: Node, p: Dictionary) -> Dictionary:
	var live := not p.has("clip")
	var S: Scene
	if live:
		m._actors_sync()
		S = m._hero_scene()
	else:
		var path := AgentTools.res(String(p["clip"]))
		if not FileAccess.file_exists(path):
			return {"ok": false, "error": "%s: no such scene file '%s'" % [tool, p["clip"]]}
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not d is Dictionary:
			return {"ok": false, "error": "%s: '%s' is not a scene file" % [tool, p["clip"]]}
		S = Scene.new()
		S.from_dict(d)
	var fps := int(p.get("fps", FightBake.FPS))
	var c := {}
	var cs := FightBake.contacts(S, fps)
	for q in cs:
		if not p.has("frame") or int(q["frame"]) == int(p["frame"]):
			c = q
			break
	if tool == "bake_momentum" and c.is_empty() and p.has("t") and not S.actors.is_empty():
		c = {"t": float(p["t"]), "frame": int(round(float(p["t"]) * fps)), "partner": 0}
	if tool != "fix_impact" and c.is_empty():
		return {"ok": false, "error": "%s: no contact to bake onto (the hero's strike must land on a partner)" % tool}
	var o := {}
	for k in ["tag", "y", "head_y", "region", "impulse", "side", "m_a", "m_b", "sex", "e"]:
		if p.has(k):
			o[k] = p[k]
	for k in ["v_a", "v_b"]:
		if p.has(k) and _v3(p[k]) != null:
			o[k] = _v3(p[k])
	var run := func(sc: Scene) -> Dictionary:
		match tool:
			"bake_reaction":
				return FightBake.bake_reaction(sc, c, o)
			"fix_impact":
				return FightBake.fix_impact(sc, fps)
			"bake_momentum":
				return FightBake.bake_momentum(sc, c, o)
		return {"ok": false, "error": "unknown tool"}
	var trial: Dictionary = run.call(S.clone())
	if not bool(trial.get("ok", false)):
		return {"ok": false, "error": String(trial.get("error", "the bake refused"))}
	if live:
		m._step_hint = "fight " + tool
		m._push_undo()
	var r: Dictionary = run.call(S)
	if live:
		m._fight_done()
	return {"ok": true, "result": FightBake.to_json(r)}
