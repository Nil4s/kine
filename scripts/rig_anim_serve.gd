## rig_anim_serve.gd - SERVE `rig_anim` (agent_tools.gd; CLI, MCP server and AI box share it) (L91 RIGMIRROR).
##   {action: key | breakdown | retime | curve | pairs | mirror, frame?, bones?, factor?, delta?, ripple?, bone?, from?, to?, step?, what? (pose | keys)}
## on the scene's own rig (Scene.own_rig). Every change is one m._push_undo; reads and refused calls push none.
class_name RigAnimServe
extends RefCounted


static func _bad(why: String) -> Dictionary:
	return {"ok": false, "error": why}


static func serve(m: Object, p: Dictionary) -> Dictionary:
	var rig: Dictionary = m.S.own_rig if m != null and m.S != null else {}
	if rig.is_empty() or not bool(rig.get("ok", false)):
		return _bad("this scene has no own rig: import one first (Scene > Import rig)")
	var act := String(p.get("action", ""))
	match act:
		"curve":
			var c := RigAnim.curve(rig, String(p.get("bone", "")), int(p.get("from", 0)), int(p.get("to", 30)), int(p.get("step", 1)))
			return {"ok": true, "result": c} if c["ok"] else _bad(String(c["why"]))
		"pairs":
			var pr := RigMirror.pairs(rig)
			var centre := []
			for b in pr["how"]:
				if pr["how"][b] == "centre":
					centre.append(b)
			return {"ok": true, "result": {"pairs": pr["pairs"], "centre": centre, "unmatched": pr["unmatched"], "plane_x": pr["plane_x"], "report": pr["report"]}}
		"key", "breakdown", "retime", "mirror":
			var name := act
			if act == "mirror":
				name = "mirror_keys" if String(p.get("what", "pose")) == "keys" else "mirror_pose"
			var dry: Dictionary = rig.duplicate(true)
			var r := RigAnim.run(dry, name, p, false)
			if not bool(r["ok"]):
				return _bad(String(r.get("why", "refused")))
			if m.has_method("_push_undo"):
				m._push_undo()
			r = RigAnim.run(rig, name, p, false)
			return {"ok": true, "result": r}
	return _bad("action is one of key, breakdown, retime, curve, pairs, mirror")
