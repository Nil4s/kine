## anim_stack.gd - ANIMATION LAYERS + NLA STRIPS as an agent tool (L79, ROADMAP_400 L02 + L01). SERVE `anim_stack` (agent_tools.gd).
## Builds on Scene.layers (add / over, weight, mute, solo, lock; scripts/scene.gd) and Scene.clips (strips: scripts/clips.gd).
## New fields: a layer's BONE MASK ("mask": a Clips mask name, "bones": an explicit joint list; both off = every bone) and a
## strip's BLEND CURVE ("curve": linear / smooth / ease_in / ease_out for its blend-in and blend-out ramps). Both are written to
## the file only when set, so older scenes load and save as before.
## Ops, {"op": ..., "index"?, ...}; every edit is ONE undo step (Main._do):
##   list
##   layer_add {name?, mode: add|over, v: {joint: [x,y,z] deg, "offset": [x,y,z] m}, w?, mask?, bones?, mute?}
##   layer_set {index, name?, mode?, v?, w?, mask?, bones?, mute?, solo?, lock?}   layer_mute {index, mute?}   layer_remove {index}
##   clip_add {src, start?, scale?, repeat?, bin?, bout?, curve?, type?, mask?, extra?, w?, mute?}
##   clip_set {index, same fields}   clip_mute {index, mute?}   clip_remove {index}
## "scale" is the strip's duration scale (2 = twice as long): speed = 1 / scale.
class_name AnimStack
extends RefCounted

const OPS := ["list", "layer_add", "layer_set", "layer_mute", "layer_remove", "clip_add", "clip_set", "clip_mute", "clip_remove"]


static func _err(s: String) -> Dictionary:
	return {"ok": false, "error": s}


static func _v_of(v) -> Variant:
	if not v is Dictionary:
		return "v is {joint: [bend, side, twist] degrees, ...}"
	var out := {}
	for j in v:
		if String(j) != "offset" and not Body.ORDER.has(String(j)):
			return "no joint '%s' (Body.ORDER lists them)" % j
		var a = v[j]
		if a is Vector3:
			out[String(j)] = a
		elif a is Array and (a as Array).size() == 3:
			out[String(j)] = Vector3(float(a[0]), float(a[1]), float(a[2]))
		else:
			return "'%s' is [x, y, z]" % j
	return out


## the layer fields in p applied to dict L (validated) -> "" or the reason
static func _layer_fields(L: Dictionary, p: Dictionary) -> String:
	if p.has("name"):
		L["name"] = String(p["name"])
	if p.has("mode"):
		if not String(p["mode"]) in ["add", "over"]:
			return "mode is add or over"
		L["mode"] = String(p["mode"])
	if p.has("v"):
		var v = _v_of(p["v"])
		if v is String:
			return v
		L["v"] = v
	if p.has("w"):
		L["w"] = clampf(float(p["w"]), 0.0, 1.0)
	if p.has("mask"):
		if not String(p["mask"]) in Clips.MASK_NAMES:
			return "mask is one of %s" % str(Clips.MASK_NAMES)
		L["mask"] = String(p["mask"])
	if p.has("bones"):
		if not p["bones"] is Array:
			return "bones is a list of joint names"
		for b in p["bones"]:
			if not Body.ORDER.has(String(b)):
				return "no joint '%s' in bones" % b
		L["bones"] = (p["bones"] as Array).map(func(b): return String(b))
	for f in ["mute", "solo", "lock"]:
		if p.has(f):
			L[f] = bool(p[f])
	return ""


static func _clip_fields(c: Dictionary, p: Dictionary) -> String:
	for k in ["start", "repeat", "bin", "bout", "type", "mask", "extra", "w", "mute", "curve", "mirror"]:
		if p.has(k):
			c[k] = p[k]
	if p.has("scale"):
		if float(p["scale"]) <= 0.0:
			return "scale is more than 0 (2 = twice as long)"
		c["speed"] = 1.0 / float(p["scale"])
	if p.has("curve") and not String(p["curve"]) in Clips.CURVES:
		return "curve is one of %s" % str(Clips.CURVES)
	if p.has("type") and not String(p["type"]) in Clips.TYPES:
		return "type is replace or add"
	if p.has("mask") and not String(p["mask"]) in Clips.MASK_NAMES:
		return "mask is one of %s" % str(Clips.MASK_NAMES)
	if p.has("extra") and not String(p["extra"]) in Clips.EXTRA:
		return "extra is one of %s" % str(Clips.EXTRA)
	return ""


static func _idx(arr: Array, p: Dictionary, what: String) -> int:
	var i := int(p.get("index", -1))
	return i if i >= 0 and i < arr.size() else -1


static func _view(S: Scene) -> Dictionary:
	return {"layers": S.layers.map(func(L): return Scene.layer_to_file(L)), "clips": Clips.to_file(S.clips),
		"strip_seconds": S.clips.map(func(c): return snappedf(Clips.length_of(c, float(Clips.source(String(c["src"])).get("len", 0.0))), 0.0001))}


static func serve(m: Node, p: Dictionary) -> Dictionary:
	var op := String(p.get("op", "list"))
	var S: Scene = m.S
	if not op in OPS:
		return _err("anim_stack op is one of %s" % str(OPS))
	if op == "list":
		return {"ok": true, "result": _view(S)}
	if op == "layer_add":
		var L := {"name": "layer %d" % (S.layers.size() + 1), "mode": "add", "w": 1.0, "wk": [], "mute": false, "solo": false, "lock": false, "v": {}}
		var e := _layer_fields(L, p)
		if e != "":
			return _err(e)
		m._do(func(): S.layers.append(L))
		return {"ok": true, "result": _result(S, S.layers.size() - 1)}
	if op.begins_with("layer_"):
		var i := _idx(S.layers, p, "layer")
		if i < 0:
			return _err("no layer at index %s (the scene has %d)" % [str(p.get("index")), S.layers.size()])
		if op == "layer_remove":
			if bool(S.layers[i].get("lock", false)):
				return _err("layer %d is locked" % i)
			m._do(func(): S.layers.remove_at(i))
			return {"ok": true, "result": _result(S, -1)}
		var q := p.duplicate()
		if op == "layer_mute":
			q = {"mute": bool(p.get("mute", not bool(S.layers[i].get("mute", false))))}
		elif bool(S.layers[i].get("lock", false)) and not (p.size() == 3 and p.has("lock")):
			return _err("layer %d is locked: unlock it first (lock: false)" % i)
		var L: Dictionary = (S.layers[i] as Dictionary).duplicate(true)
		var e := _layer_fields(L, q)
		if e != "":
			return _err(e)
		m._do(func(): S.layers[i] = L)
		return {"ok": true, "result": _result(S, i)}
	if op == "clip_add":
		var src := String(p.get("src", "")).trim_prefix("res://")
		if Clips.source(src).is_empty():
			return _err("no scene, pose or move file '%s' to place as a strip" % src)
		var c := Clips.make(src, float(p.get("start", 0.0)))
		var e := _clip_fields(c, p)
		if e != "":
			return _err(e)
		c = Clips.clean(c)
		m._do(func(): S.clips.append(c))
		return {"ok": true, "result": _result(S, S.clips.size() - 1)}
	var k := _idx(S.clips, p, "clip")
	if k < 0:
		return _err("no strip at index %s (the scene has %d)" % [str(p.get("index")), S.clips.size()])
	if op == "clip_remove":
		m._do(func(): S.clips.remove_at(k))
		return {"ok": true, "result": _result(S, -1)}
	var c2: Dictionary = (S.clips[k] as Dictionary).duplicate(true)
	var q2 := p if op == "clip_set" else {"mute": bool(p.get("mute", not bool(c2.get("mute", false))))}
	var e2 := _clip_fields(c2, q2)
	if e2 != "":
		return _err(e2)
	c2 = Clips.clean(c2)
	m._do(func(): S.clips[k] = c2)
	return {"ok": true, "result": _result(S, k)}


static func _result(S: Scene, index: int) -> Dictionary:
	var r := _view(S)
	r["index"] = index
	return r
