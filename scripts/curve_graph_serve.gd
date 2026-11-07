class_name CurveGraphServe
extends RefCounted
## L84 SERVE `curve_graph` (agent_tools.gd, the MCP server and the AI box share it). One joint's part-key curve in the graph editor:
##   {action:"read", joint}                                 keys, weights per handle, modifiers, buffers
##   {action:"weight", joint, key, side:"in"|"out", weight}   tangent weight (1.0 = default, up to 3.0); ONE undo step
##   {action:"snapshot", joint, name?}                      a buffer curve (no undo step: the scene does not change) -> slot
##   {action:"swap", joint, slot}                           live <-> buffer, exactly; ONE undo step
##   {action:"compare", joint, slot, n?}                    max / rms / per-channel deviation between live and buffer (deg)
##   {action:"mod", joint, type: noise|stepped|limits|cycles, ...fields}   add a modifier (defaults filled); ONE undo step
##   {action:"unmod", joint, index}                         remove one; ONE undo step
##   {action:"drop", slot}                                  forget a buffer
## Not in METHODS. Maths: scripts/part_keys.gd (weights, modifiers), scripts/curve_buffer.gd.

const DEFAULTS := {
	"noise": {"ch": -1, "strength": 4.0, "scale": 0.3, "phase": 0.0, "seed": 1, "mix": 1.0},
	"stepped": {"ch": -1, "step": 0.1, "offset": 0.0, "mix": 1.0},
	"limits": {"ch": -1, "min": -180.0, "max": 180.0, "mix": 1.0},
	"cycles": {"ch": -1, "before": "repeat", "after": "repeat", "before_n": 0, "after_n": 0, "mix": 1.0},
}


static func _err(s: String) -> Dictionary:
	return {"ok": false, "error": s}


static func serve(m: Node, p: Dictionary) -> Dictionary:
	var a := String(p.get("action", ""))
	if a == "drop":
		var sl := int(p.get("slot", -1))
		if sl < 0 or sl >= CurveBuffer.slots.size():
			return _err("no such buffer slot")
		CurveBuffer.slots[sl]["keys"] = []
		return {"ok": true, "result": {"dropped": sl}}
	if not a in ["read", "weight", "snapshot", "swap", "compare", "mod", "unmod"]:
		return _err("action is one of read, weight, snapshot, swap, compare, mod, unmod, drop")
	var pk: Dictionary = m.S.part_keys
	var j := String(p.get("joint", ""))
	if p.has("au"):   # L94: a face AU channel (Scene.face) instead of a joint; same tools, value clamped to the channel's range
		pk = m.S.face
		j = String(p["au"])
		if not pk.has(j) or (pk[j] as Array).is_empty():
			return _err("au needs a face channel that has keys (got '%s')" % j)
	elif not pk.has(j) or (pk[j] as Array).is_empty():
		return _err("joint needs a joint that has part keys (got '%s')" % j)
	var keys: Array = pk[j]
	match a:
		"read":
			var ws := []
			for i in keys.size():
				ws.append({"t": keys[i]["t"], "v": keys[i]["v"], "w_in": snappedf(PartKeys.weight_of(keys, i, "in"), 0.0001), "w_out": snappedf(PartKeys.weight_of(keys, i, "out"), 0.0001)})
			var bufs := []
			for i in CurveBuffer.slots.size():
				if CurveBuffer.slots[i]["joint"] == j:
					bufs.append({"slot": i, "name": CurveBuffer.slots[i]["name"], "keys": (CurveBuffer.slots[i]["keys"] as Array).size()})
			return {"ok": true, "result": {"joint": j, "range": AuCurves.range_of(j) if p.has("au") else null, "keys": ws, "mods": PartKeys.mods_of(keys), "buffers": bufs}}
		"snapshot":
			var sn := CurveBuffer.snapshot(pk, j, String(p.get("name", "")))
			return {"ok": true, "result": {"slot": sn, "keys": keys.size()}}
		"compare":
			var s2 := int(p.get("slot", -1))
			if CurveBuffer.keys_of(s2, j).is_empty():
				return _err("slot needs a buffer taken from this joint")
			var r := CurveBuffer.compare(pk, j, s2, int(p.get("n", 300)))
			return {"ok": true, "result": {"max_deg": r["max"], "rms_deg": r["rms"], "max_ch": r["max_ch"], "t_at_max": r["t_at_max"], "keys_live": r["keys_live"], "keys_buffer": r["keys_buffer"]}}
		"weight":
			var ki := int(p.get("key", -1))
			var side := String(p.get("side", "out"))
			var cur := PartKeys.weight_of(keys, ki, side)
			if cur < 0.0:
				return _err("key / side need an existing key and a side with a segment (the first key has no in handle, the last no out)")
			m._push_undo()
			PartKeys.set_weight(pk, j, ki, side, float(p.get("weight", 1.0)))
			return {"ok": true, "result": {"weight_before": cur, "weight_after": PartKeys.weight_of(pk[j], ki, side)}}
		"swap":
			var s3 := int(p.get("slot", -1))
			if CurveBuffer.keys_of(s3, j).is_empty():
				return _err("slot needs a buffer taken from this joint")
			m._push_undo()
			CurveBuffer.swap(pk, j, s3)
			return {"ok": true, "result": {"keys": (pk[j] as Array).size()}}
		"mod":
			var ty := String(p.get("type", ""))
			if not DEFAULTS.has(ty):
				return _err("type is noise, stepped, limits or cycles")
			if ty == "cycles" and PartKeys.mods_of(keys).any(func(x): return String(x.get("type", "")) == "cycles"):
				return _err("this curve already has a cycles modifier")
			var md: Dictionary = (DEFAULTS[ty] as Dictionary).duplicate()
			if p.has("au"):
				md["ch"] = 0   # the AU lives in x
				if ty == "limits":
					var rg := AuCurves.range_of(j)
					md["min"] = rg.x
					md["max"] = rg.y
			for f in md.keys():
				if p.has(f):
					md[f] = p[f]
			for f in ["range_start", "range_end", "blend_in", "blend_out", "offset", "depth"]:
				if p.has(f):
					md[f] = p[f]
			md["type"] = ty
			m._push_undo()
			var idx := PartKeys.add_mod(pk, j, md)
			if idx < 0:
				return _err("could not add")
			return {"ok": true, "result": {"index": idx, "mods": PartKeys.mods_of(pk[j]).size()}}
		"unmod":
			var ix := int(p.get("index", -1))
			if ix < 0 or ix >= PartKeys.mods_of(keys).size():
				return _err("index needs an existing modifier")
			m._push_undo()
			PartKeys.remove_mod(pk, j, ix)
			return {"ok": true, "result": {"mods": PartKeys.mods_of(pk[j]).size()}}
	return _err("unreachable")
