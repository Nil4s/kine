## fight2_serve.gd - SERVE `impact_align`, `hit_region`, `body_collide` (L72: N034, N042, N046; agent_tools.gd, the MCP server and the CLI share it).
##  impact_align {clip?, fps?} judges the contact frame of a scene; or {ang: {joint: [bend, side, twist]}, kind: punch|kick, side: l|r, miss?} judges numbers.
##  hit_region {tag, y?, head_y?, impulse (N s), side?}: the region picked and its reaction. body_collide {m_a, v_a:[x,y,z], m_b, v_b?, sex?, e?}.
class_name Fight2Serve
extends RefCounted


static func _v3(a: Variant) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() >= 3 else Vector3.ZERO


static func serve(tool: String, m: Node, p: Dictionary) -> Dictionary:
	match tool:
		"impact_align":
			if p.has("ang"):
				var ang := {}
				for j in p["ang"]:
					ang[j] = _v3(p["ang"][j])
				return {"ok": true, "result": ImpactAlign.to_json(ImpactAlign.check(ang, String(p.get("kind", "punch")), String(p.get("side", "r")), bool(p.get("miss", false))))}
			var S: Scene = m.S
			if p.has("clip"):
				var path := AgentTools.res(String(p["clip"]))
				if not FileAccess.file_exists(path):
					return {"ok": false, "error": "impact_align: no such scene file '%s'" % p["clip"]}
				var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
				if not d is Dictionary:
					return {"ok": false, "error": "impact_align: '%s' is not a scene file" % p["clip"]}
				S = Scene.new()
				S.from_dict(d)
			var r := ImpactAlign.scene_check(S, int(p.get("fps", 30)))
			return {"ok": bool(r.get("ok", false)), "result": ImpactAlign.to_json(r), "error": String(r.get("error", ""))}
		"hit_region":
			if not p.has("tag"):
				return {"ok": false, "error": "hit_region needs {tag: an anatomy tag such as obliques_r, face, quadriceps_l, abdominals, impulse: N s}"}
			var tag := String(p["tag"])
			var reg := RegionReact.pick(tag, float(p.get("y", 0.5)), float(p.get("head_y", 0.5)))
			var dflt := tag.right(1) if tag.ends_with("_l") or tag.ends_with("_r") else "r"
			return {"ok": true, "result": RegionReact.to_json(RegionReact.react(reg, float(p.get("impulse", 60.0)), String(p.get("side", dflt))))}
		"body_collide":
			if not (p.has("m_a") and p.has("m_b") and p.has("v_a")):
				return {"ok": false, "error": "body_collide needs {m_a, v_a:[x,y,z], m_b, v_b?:[x,y,z], sex?, e?}"}
			return {"ok": true, "result": BodyCollide.to_json(BodyCollide.charge(float(p["m_a"]), _v3(p["v_a"]), float(p["m_b"]), _v3(p.get("v_b", [0, 0, 0])), String(p.get("sex", "male")), float(p.get("e", 0.1))))}
	return {"ok": false, "error": "unknown tool"}
