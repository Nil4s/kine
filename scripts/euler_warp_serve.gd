class_name EulerWarpServe
extends RefCounted
## L86 SERVE `euler_warp` (agent_tools.gd, the MCP server and the AI box share it). ROADMAP_400 L04 + L05:
##   {action:"euler", joints:[..]}                  Euler filter (scripts/quat_curve.gd) on those parts' keys; ONE undo step
##   {action:"quat", joint, t0?, t1?, fps?}         [t, w, x, y, z] per frame of the part's world rotation; read-only
##   {action:"slerp", joints:[..], on?:true}        keys leave toward the next along the shortest quaternion arc (on) or bezier (off); ONE undo step
##   {action:"warp", clip, knots:[[x, y]..]}        the clip's time warp (strip progress -> source progress); refused unless monotone; ONE undo step
##   {action:"warp_clear", clip} / {action:"warp_read", clip}
## Not in METHODS. Maths: Curves.euler_filter, QuatCurve, Clips.warp_*.


static func _err(s: String) -> Dictionary:
	return {"ok": false, "error": s}


static func _joints(m: Node, p: Dictionary) -> Variant:
	var js: Array = p.get("joints", [])
	if js.is_empty():
		return "joints needs a list of parts that have part keys"
	for j in js:
		if not m.S.part_keys.has(j) or (m.S.part_keys[j] as Array).is_empty():
			return "joints needs parts that have part keys (got '%s')" % j
	return js


static func _clip(m: Node, p: Dictionary) -> Variant:
	var i := int(p.get("clip", -1))
	if i < 0 or i >= m.S.clips.size():
		return "clip needs an existing clip index (0..%d)" % (m.S.clips.size() - 1)
	return i


static func serve(m: Node, p: Dictionary) -> Dictionary:
	var a := String(p.get("action", ""))
	match a:
		"euler":
			var js = _joints(m, p)
			if js is String:
				return _err(js)
			m._push_undo()
			var r := QuatCurve.euler_filter_parts(m.S.part_keys, js)
			r["world_note"] = "exact for twist and for a swing angle while the other swing angle is 0"
			return {"ok": true, "result": r}
		"slerp":
			var js2 = _joints(m, p)
			if js2 is String:
				return _err(js2)
			m._push_undo()
			var n := QuatCurve.set_slerp(m.S.part_keys, js2, bool(p.get("on", true)))
			return {"ok": true, "result": {"segments": n, "on": bool(p.get("on", true))}}
		"quat":
			var j := String(p.get("joint", ""))
			if not j in Body.ORDER:
				return _err("joint needs a body part name")
			var fps := float(p.get("fps", m.S.fps))
			var t0 := float(p.get("t0", 0.0))
			var t1 := float(p.get("t1", m.S.length()))
			if t1 < t0 or fps <= 0.0 or (t1 - t0) * fps > 20000.0:
				return _err("t0 <= t1, fps > 0 and at most 20000 frames")
			return {"ok": true, "result": {"joint": j, "fps": fps, "columns": ["t", "w", "x", "y", "z"], "frames": QuatCurve.view(m.S, j, t0, t1, fps)}}
		"warp", "warp_clear", "warp_read":
			var ci = _clip(m, p)
			if ci is String:
				return _err(ci)
			var c: Dictionary = m.S.clips[ci]
			if a == "warp_read":
				return {"ok": true, "result": {"knots": c.get("warp", [])}}
			var knots: Array = []
			if a == "warp":
				var why := Clips.warp_check(p.get("knots"))
				if why != "":
					return _err("warp refused: " + why)
				knots = p["knots"]
			m._push_undo()
			var nc := c.duplicate(true)
			nc["warp"] = knots
			m.S.clips[ci] = Clips.clean(nc)
			return {"ok": true, "result": {"knots": m.S.clips[ci].get("warp", []), "identity": not m.S.clips[ci].has("warp")}}
	return _err("action is one of euler, quat, slerp, warp, warp_clear, warp_read")
