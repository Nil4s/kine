## FPS + WAVE tool (L92). Agent tool `fps_wave` (agent_tools.gd, the MCP server). Not in METHODS.
##   {action:"convert", fps, snap?}   frame-rate conversion that keeps every key at its exact time (scripts/fps_convert.gd); ONE undo step
##   {action:"wave", on?}             the sound waveform under the graph editor's curves on / off (view only, no undo step); no "on" = toggle
##   {action:"read"}                  fps, key count, sub-frame keys at this rate, the waveform toggle
class_name FpsWave
extends RefCounted


static func _err(s: String) -> Dictionary:
	return {"ok": false, "error": s}


static func serve(m: Node, p: Dictionary) -> Dictionary:
	var a := String(p.get("action", "read"))
	var S: Scene = m.S
	if a == "convert":
		var n := int(p.get("fps", 0))
		var chk := FpsConvert.convert(_probe(S), n, bool(p.get("snap", false)))
		if not chk["ok"]:
			return _err(String(chk["error"]))
		m._push_undo()
		var r := FpsConvert.convert(S, n, bool(p.get("snap", false)))
		if m.has_method("_refresh"):
			m._refresh()
		return {"ok": true, "result": r}
	if a == "wave":
		var on: bool = bool(p["on"]) if p.has("on") else not bool(m.graph_wave)
		m.graph_wave = on
		if m.ui_curve != null:
			m.ui_curve.wave_on = on
			m.ui_curve.queue_redraw()
		return {"ok": true, "result": {"wave": on}}
	if a == "read":
		var keys := 0
		var sub := 0
		for j in S.part_keys:
			for k in S.part_keys[j]:
				keys += 1
				if absf(float(k["t"]) * S.fps - roundf(float(k["t"]) * S.fps)) > 1e-6:
					sub += 1
		return {"ok": true, "result": {"fps": S.fps, "keys": keys, "sub_frame_keys": sub, "wave": bool(m.graph_wave)}}
	return _err("action is one of convert, wave, read")


## a throw-away scene that only carries the rate, so a refused conversion is known before the undo step is pushed
static func _probe(S: Scene) -> Scene:
	var c := Scene.new()
	c.fps = S.fps
	return c
