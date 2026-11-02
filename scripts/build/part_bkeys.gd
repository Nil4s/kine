class_name PartBKeys
extends RefCounted
## W03c / 256 STABLE BODY REFERENCES. A step that points at a body stores the body's item-241 key (<feature id>#<k>) beside its index; replay finds
## the body by KEY, so a step inserted or deleted earlier (that adds / drops bodies) cannot move a later step onto another body.
## Fields: body -> "bkey" (string); bodies / targets / tools -> "bodies_k" / "targets_k" / "tools_k" (arrays); target -> "target_k"; to -> "to_k".
## Beside each key field "<keyfield>_i" holds the index the key was stamped with: if the step's index no longer equals it, someone EDITED the index
## (UI, edit_step) and the index wins (the key is re-stamped from the body now at that index). No key field = index only, as in every older file.
## Replay of a part with any key field tracks keys (part_fx.gd) and calls resolve() at every step; it does not use the incremental cache for it.

const FIELDS := ["body", "bodies", "targets", "tools", "target", "to", "into"]


static func kf(field: String) -> String:
	return "bkey" if field == "body" else field + "_k"


static func keyed(feats: Array) -> bool:
	for f in feats:
		for fld in FIELDS:
			if (f as Dictionary).has(kf(fld)):
				return true
	return false


static func _ints(v: Variant) -> Array:
	var out: Array = []
	for x in (v if v is Array else [v]):
		if x is int or x is float:
			out.append(int(x))
	return out


## stamp every body reference of step f that has no key yet, from `keys` (the body keys just before the step); a reference out of range stays index-only
static func stamp_step(f: Dictionary, keys: Array) -> void:
	for fld in FIELDS:
		if not f.has(fld) or f.has(kf(fld)):
			continue
		var v: Variant = f[fld]
		if not (v is Array) and not (v is int or v is float):
			continue
		var idx := _ints(v)
		if idx.is_empty():
			continue
		var ks: Array = []
		for x in idx:
			if x < 0 or x >= keys.size():
				ks.clear()
				break
			ks.append(String(keys[x]))
		if ks.is_empty():
			continue
		f[kf(fld)] = ks if v is Array else ks[0]
		f[kf(fld) + "_i"] = idx if v is Array else idx[0]


## stamps every step of rec (one replay). Returns the number of references newly stamped
static func stamp(rec: Dictionary) -> int:
	var r := Part.replay(rec, -1, {"stepkeys": true, "errors_only": true})
	var sk: Array = r.get("step_keys", [])
	var feats: Array = rec["features"]
	var n := 0
	for i in mini(sk.size(), feats.size()):
		var before := JSON.stringify(feats[i])
		stamp_step(feats[i], sk[i])
		if JSON.stringify(feats[i]) != before:
			n += 1
	return n


## replay, at the top of step f: points f's body fields at the bodies its keys name now. "" or the words of why not (names the step)
static func resolve(f: Dictionary, keys: Array, si: int) -> String:
	for fld in FIELDS:
		var k := kf(fld)
		if not f.has(k) or not f.has(fld):
			continue
		var cur := _ints(f[fld])
		var was := _ints(f.get(k + "_i", null))
		if cur != was:   # the index was edited after the stamp: the index wins, the key follows it
			f.erase(k)
			f.erase(k + "_i")
			stamp_step(f, keys)
			continue
		var ks: Array = f[k] if f[k] is Array else [f[k]]
		var idx: Array = []
		for key in ks:
			var at := keys.find(String(key))
			if at < 0:
				return "step %d (%s): the body %s that '%s' pointed at is gone (an earlier step removed it)" % [si + 1, String(f.get("name", f.get("id", ""))), String(key), fld]
			idx.append(at)
		f[fld] = idx if f[fld] is Array else idx[0]
		f[k + "_i"] = idx if f[fld] is Array else idx[0]
	return ""


## the later steps (1-based places, with ids) that name a body made by step `id`, by key: "steps 7 (f7), 9 (f9)", or ""
static func users_of(feats: Array, from: int, id: String) -> String:
	var out: Array = []
	for i in range(from, feats.size()):
		var hit := false
		for fld in FIELDS:
			var v: Variant = (feats[i] as Dictionary).get(kf(fld), null)
			for key in (v if v is Array else [v]):
				if key is String and (key as String).begins_with(id + "#"):
					hit = true
		if hit:
			out.append("%d (%s)" % [i + 1, String(feats[i].get("id", ""))])
	return "" if out.is_empty() else "steps " + ", ".join(out)
