class_name PartReplayCalls
extends RefCounted
## part_replay_calls.gd - ITEM 244 AI EASE 4: CHECKPOINT + REPLAY FROM STEP. An AI edits one step and only the steps from there on run again.
## The replay itself is Part.replay(rec, -1, {"inc": true}) (s168/s233): a hash chain over the steps keys the cached shapes, so a changed step n
## finds the prefix 0..n-1 in Part.inc_cache and runs steps n..end only. This file builds on that cache (no second one); it only edits the record.
## Calls (agent_tools methods, none in METHODS): checkpoint {name} / restore {name} / checkpoints {} / edit_step {n, params} / insert_step {n, feature} /
## delete_step {n}. n is the step's place counted from 1 (as the timeline numbers it) or its id ("f12"). Each call that changes the part is ONE undo step.
## edit_step / insert_step / delete_step answer {"ok", "step", "id", "ran": steps really run, "of": steps in the part, "from": first step run (1-based), "ms",
## "created": [body index], "changed": [body index], "removed": [body index], "bodies", "volume_mm3", "errors": {id: message}, "new_errors", "remapped": [step ids whose body numbers moved]}.
## created / changed / removed are body places in the part after (removed: in the part before), found by comparing each body's volume + name before and after.

const BODY_KEYS := ["body", "bodies", "targets", "tools", "into"]   # the step fields that hold body numbers (a number or a list of them)
static var _cps := {}   # name -> {"part", "building", "light", "camera", "steps", "seq"}
static var _seq := 0


static func _clean(d: Variant) -> Dictionary:
	return (d as Dictionary).duplicate(true) if d is Dictionary else {}


static func light_state() -> Dictionary:
	return {"settings": TempleLight.settings_dict(), "ground": TempleLight.ground, "sun_mult": TempleLight.sun_mult, "sun_gain": TempleLight.sun_gain, "ambient": TempleLight.ambient,
		"contrast": TempleLight.contrast, "saturation": TempleLight.saturation}


static func light_apply(s: Dictionary) -> void:
	if s.is_empty():
		return
	TempleLight.set_from(s["settings"])
	TempleLight.ground = bool(s["ground"])
	TempleLight.sun_mult = float(s["sun_mult"])
	TempleLight.sun_gain = float(s["sun_gain"])
	TempleLight.ambient = float(s["ambient"])
	TempleLight.contrast = float(s["contrast"])
	TempleLight.saturation = float(s["saturation"])


static func serve(m: Node, method: String, p: Dictionary) -> Dictionary:
	match method:
		"checkpoint":
			var name := String(p.get("name", "")).strip_edges()
			if name == "":
				return {"ok": false, "error": "checkpoint needs {\"name\": \"before-roof\"}"}
			_seq += 1
			var cam: Dictionary = {}
			if m.get("cam") != null:
				var g := TempleLight.get_camera(m)
				cam = {"pos": g["pos"], "target": g["target"], "fov": g["fov"], "near": g["near"], "far": g["far"]}
			var part: Dictionary = _clean(m.S.part)
			var bld: Dictionary = _clean(m.S.building)
			_cps[name] = {"part": part, "building": bld, "light": light_state(), "camera": cam, "steps": (part.get("features", []) as Array).size(), "seq": _seq}
			return {"ok": true, "name": name, "steps": int(_cps[name]["steps"]), "nature": (bld.get("nature", []) as Array).size(), "checkpoints": _cps.size()}
		"restore":
			var rn := String(p.get("name", ""))
			if not _cps.has(rn):
				return {"ok": false, "error": "no checkpoint '%s' (have: %s)" % [rn, ", ".join(_cps.keys())]}
			var c: Dictionary = _cps[rn]
			m._step_hint = "Restore " + rn
			m._push_undo()
			m.S.part = (c["part"] as Dictionary).duplicate(true)
			m.S.building = (c["building"] as Dictionary).duplicate(true)
			light_apply(c["light"])
			var cam2: Dictionary = c["camera"]
			if not cam2.is_empty() and m.get("cam") != null:
				TempleLight.set_camera(m, cam2["pos"], cam2["target"], float(cam2["fov"]), float(cam2["near"]), float(cam2["far"]))
			TempleLight.refresh(m)
			if m.has_method("_fit_top"):
				m._fit_top.call_deferred()
			return {"ok": true, "name": rn, "steps": int(c["steps"])}
		"checkpoints":
			var rows: Array = []
			for k in _cps:
				rows.append({"name": k, "steps": int(_cps[k]["steps"]), "nature": ((_cps[k]["building"] as Dictionary).get("nature", []) as Array).size(), "seq": int(_cps[k]["seq"])})
			rows.sort_custom(func(a, b): return int(a["seq"]) < int(b["seq"]))
			return {"ok": true, "checkpoints": rows}
	return _edit(m, method, p)


## the 0-based index a call's n names (1-based place or id); -1 when there is none
static func index_of(rec: Dictionary, n: Variant) -> int:
	var fs: Array = rec.get("features", [])
	if n is String and not String(n).is_valid_int():
		return Part.index_of(rec, String(n))
	var k := int(n) - 1
	return k if k >= 0 and k < fs.size() else -1


## one signature per body: volume to 9 digits + its name
static func sigs_of(res: Dictionary) -> Array:
	var out: Array = []
	var vs: Array = res["volumes"]
	var nm: Array = res.get("body_names", [])
	for i in vs.size():
		out.append("%s|%s" % [String.num_scientific(float(vs[i])), str(nm[i]) if i < nm.size() else ""])
	return out


## {created, changed, removed} between two signature lists: the common head and tail are unchanged, the middle pairs up in order as changed, the rest created / removed
static func diff(a: Array, b: Array) -> Dictionary:
	var h := 0
	while h < a.size() and h < b.size() and a[h] == b[h]:
		h += 1
	var t := 0
	while t < a.size() - h and t < b.size() - h and a[a.size() - 1 - t] == b[b.size() - 1 - t]:
		t += 1
	var ma := a.size() - h - t
	var mb := b.size() - h - t
	var out := {"created": [], "changed": [], "removed": []}
	for k in maxi(ma, mb):
		if k < ma and k < mb:
			out["changed"].append(h + k)
		elif k < mb:
			out["created"].append(h + k)
		else:
			out["removed"].append(h + k)
	return out


static func _shift_refs(f: Dictionary, a: int, d: int) -> bool:
	var moved := false
	for key in BODY_KEYS:
		if not f.has(key) or f.has(PartBKeys.kf(key)):   # W03c: a field with a body key finds its body by the key at replay
			continue
		var v: Variant = f[key]
		if v is Array:
			for j in (v as Array).size():
				if (v[j] is int or v[j] is float) and int(v[j]) >= a:
					v[j] = int(v[j]) + d
					moved = true
		elif (v is int or v is float) and int(v) >= a:
			f[key] = int(v) + d
			moved = true
	return moved


## the first later step (index >= from) that points at a body in [a, b); "" when none
static func _ref_into(feats: Array, from: int, a: int, b: int) -> String:
	for i in range(from, feats.size()):
		for key in BODY_KEYS:
			var v: Variant = (feats[i] as Dictionary).get(key, null)
			var vs: Array = v if v is Array else [v]
			for x in vs:
				if (x is int or x is float) and int(x) >= a and int(x) < b:
					return "step %d (%s) points at body %d with '%s'" % [i + 1, feats[i].get("id", ""), int(x), key]
	return ""


## step id -> its body numbers as text, for the steps that have any
static func _body_idx(feats: Array) -> Dictionary:
	var out := {}
	for f in feats:
		var parts: Array = []
		for key in BODY_KEYS:
			if f.has(key):
				parts.append(str(f[key]))
		if not parts.is_empty():
			out[String(f["id"])] = ",".join(parts)
	return out


static func _run(rec: Dictionary) -> Dictionary:
	return Part.replay(rec, -1, {"inc": true, "errors_only": true})


static func _user_of(rec: Dictionary, id: String) -> String:
	for f in rec["features"]:
		if String(f.get("sketch", "")) == id or (f.get("sketches", []) as Array).has(id) or String(f.get("profile", "")) == id or String(f.get("path", "")) == id:
			return "%s %s" % [f.get("id", ""), f.get("name", "")]
	return "?"


static func _edit(m: Node, method: String, p: Dictionary) -> Dictionary:
	if not Part.available():
		return {"ok": false, "error": Part.why_not()}
	if m.S.part.is_empty():
		return {"ok": false, "error": "there is no part on screen"}
	var before: Dictionary = m.S.part
	var rec: Dictionary = before.duplicate(true)
	var feats: Array = rec["features"]
	if method == "insert_step" or method == "delete_step":
		PartBKeys.stamp(rec)   # W03c / 256: every body reference gets its stable key before the steps move
	var idx_before := _body_idx(feats)
	var old := _run(before)
	var old_sigs := sigs_of(old)
	var old_counts: Array = old["counts"]
	var at := -1
	if method != "insert_step":
		at = index_of(rec, p.get("n", p.get("id", -1)))
	var hint := ""
	var first := 0   # 0-based first step the replay has to run
	var remapped: Array = []
	var gone_id := ""
	if method == "insert_step":
		var fd: Variant = p.get("feature", null)
		if not (fd is Dictionary) or String((fd as Dictionary).get("t", "")) == "":
			return {"ok": false, "error": "insert_step needs {\"n\": place, \"feature\": {\"t\": \"box\"|..., fields}}"}
		var pos := clampi(int(p.get("n", feats.size() + 1)) - 1, 0, feats.size())
		var fields: Dictionary = (fd as Dictionary).duplicate(true)
		var t := String(fields["t"])
		fields.erase("t")
		fields.erase("id")
		var nf := Part.new_feature(rec, t, fields)
		feats.insert(pos, nf)
		first = pos
		at = pos
		hint = "Insert " + String(nf["name"])
	elif at < 0:
		return {"ok": false, "error": "%s: there is no step %s in this part (it has %d)" % [method, str(p.get("n", p.get("id", "?"))), feats.size()]}
	elif method == "edit_step":
		var np: Variant = p.get("params", null)
		if not (np is Dictionary) or (np as Dictionary).is_empty():
			return {"ok": false, "error": "edit_step needs {\"n\": place or id, \"params\": {field: value, ...}} (a null value removes the field)"}
		var f: Dictionary = feats[at]
		for k in np:
			if k == "id" or k == "t":
				return {"ok": false, "error": "edit_step cannot change a step's '%s'; delete it and insert another" % k}
			if np[k] == null:
				f.erase(k)
			else:
				f[k] = np[k]
		first = at
		hint = "Edit " + String(f.get("name", f.get("id", "")))
	elif method == "delete_step":
		var a: int = int(old_counts[at - 1]) if at > 0 else 0
		var d: int = int(old_counts[at]) - a
		var gone: Dictionary = feats[at]
		gone_id = String(gone["id"])
		if Part.sketch_used(rec, gone_id):
			return {"ok": false, "error": "delete_step: step %d (%s) is used by a later step (%s); delete that first" % [at + 1, gone_id, _user_of(rec, gone_id)]}
		if d > 0:
			var bad := _ref_into(feats, at + 1, a, a + d)
			if bad != "":
				var users := PartBKeys.users_of(feats, at + 1, gone_id)
				return {"ok": false, "error": "delete_step refused: step %d (%s) makes body %d..%d and %s%s" % [at + 1, gone_id, a, a + d - 1, bad, ("; the steps that use its bodies: " + users) if users != "" else ""]}
		elif d < 0:
			var any := _ref_into(feats, at + 1, 0, 1 << 30)
			if any != "":
				return {"ok": false, "error": "delete_step refused: step %d (%s) removes %d body(ies), so later body numbers would change meaning; %s" % [at + 1, gone_id, -d, any]}
		feats.remove_at(at)
		if d > 0:
			for i in range(at, feats.size()):
				if _shift_refs(feats[i], a + d, -d):
					remapped.append(String(feats[i]["id"]))
		first = at
		hint = "Delete " + String(gone.get("name", gone_id))
	else:
		return {"ok": false, "error": "unknown call " + method}
	var s0 := Part.step_runs
	var t0 := Time.get_ticks_usec()
	var res := _run(rec)
	if method == "insert_step":
		var a2: int = int(res["counts"][at - 1]) if at > 0 else 0
		var d2: int = int(res["counts"][at]) - a2
		if d2 < 0:
			var any2 := _ref_into(feats, at + 1, 0, 1 << 30)
			if any2 != "":
				return {"ok": false, "error": "insert_step refused: the new step removes %d body(ies), so later body numbers would change meaning; %s" % [-d2, any2]}
		elif d2 > 0:
			for i in range(at + 1, feats.size()):
				if _shift_refs(feats[i], a2, d2):
					remapped.append(String(feats[i]["id"]))
			if not remapped.is_empty():
				res = _run(rec)   # the moved steps changed their own keys: they run again (the prefix up to them is still cached)
	var idx_after := _body_idx(feats)   # W03c: the steps whose body numbers the keys moved
	for sid in idx_after:
		if idx_before.has(sid) and idx_before[sid] != idx_after[sid] and not remapped.has(sid):
			remapped.append(sid)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var ran := Part.step_runs - s0
	var errs: Dictionary = res["errors"]
	if method != "delete_step" and errs.has(String(feats[at]["id"])):
		return {"ok": false, "error": "step %d (%s) fails: %s (the part is unchanged)" % [at + 1, feats[at]["id"], errs[String(feats[at]["id"])]]}
	var broke: Dictionary = {}
	for k in errs:
		if not (old["errors"] as Dictionary).has(k):
			broke[k] = errs[k]
	m._step_hint = hint
	m._push_undo()
	m.S.part = rec
	if m.has_method("_fit_top"):
		m._fit_top.call_deferred()
	var df := diff(old_sigs, sigs_of(res))
	return {"ok": true, "step": at + 1, "id": gone_id if method == "delete_step" else String(feats[at]["id"]), "ran": ran, "of": feats.size(), "from": first + 1, "ms": snappedf(ms, 0.1),
		"created": df["created"], "changed": df["changed"], "removed": df["removed"], "bodies": int(res["bodies"]), "volume_mm3": float(res["volume"]) / (Part.MM * Part.MM * Part.MM),
		"errors": errs, "new_errors": broke, "remapped": remapped, "warnings": res.get("warnings", {})}
