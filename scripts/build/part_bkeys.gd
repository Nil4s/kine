class_name PartBKeys
extends RefCounted
## W03c / 256 STABLE BODY REFERENCES. A step that points at a body stores the body's item-241 key (<feature id>#<k>) beside its index; replay finds
## the body by KEY, so a step inserted or deleted earlier (that adds / drops bodies) cannot move a later step onto another body.
## Fields: body -> "bkey" (string); bodies / targets / tools -> "bodies_k" / "targets_k" / "tools_k" (arrays); target -> "target_k"; to -> "to_k".
## Beside each key field "<keyfield>_i" holds the index the key was stamped with: if the step's index no longer equals it, someone EDITED the index
## (UI, edit_step) and the index wins (the key is re-stamped from the body now at that index). No key field = index only, as in every older file.
## Replay of a part with any key field tracks keys (part_fx.gd) and calls resolve() at every step; it does not use the incremental cache for it.

const FIELDS := ["body", "bodies", "targets", "tools", "target", "to", "into"]
## W03e: body numbers NESTED in a face descriptor (offset_face "face": {.., "body": N}; draft "faces": [{.., "body": N}, ..]). Key field: "face_bk" (string) / "faces_bk" (array), "<key>_i" beside it.
const NESTED := {"face": "face_bk", "faces": "faces_bk"}


static func kf(field: String) -> String:
	return "bkey" if field == "body" else field + "_k"


static func keyed(feats: Array) -> bool:
	for f in feats:
		for fld in FIELDS:
			if (f as Dictionary).has(kf(fld)):
				return true
		for nf in NESTED:
			if (f as Dictionary).has(NESTED[nf]):
				return true
	return false


## the body numbers held in the descriptors of f[fld] (one descriptor, or a list of them); [] when any descriptor has none
static func nested_ints(f: Dictionary, fld: String) -> Array:
	var v: Variant = f.get(fld, null)
	var out: Array = []
	if v is Dictionary:
		if (v as Dictionary).has("body") and ((v as Dictionary)["body"] is int or (v as Dictionary)["body"] is float):
			out.append(int((v as Dictionary)["body"]))
	elif v is Array:
		for d in v:
			if d is Dictionary and (d as Dictionary).has("body") and ((d as Dictionary)["body"] is int or (d as Dictionary)["body"] is float):
				out.append(int((d as Dictionary)["body"]))
			else:
				return []
	return out


static func nested_set(f: Dictionary, fld: String, idx: Array) -> void:
	var v: Variant = f[fld]
	if v is Dictionary:
		(v as Dictionary)["body"] = idx[0]
	else:
		for j in (v as Array).size():
			v[j]["body"] = idx[j]


## the form of a step that the incremental cache hashes: a reference that still agrees with its key is left out (the key says it), so resolving
## (which rewrites the numbers) does not change the hash. A step with no key field is returned as it is.
static func chain_form(f: Dictionary) -> Dictionary:
	var has := false
	for fld in FIELDS:
		if f.has(kf(fld)):
			has = true
	for nf in NESTED:
		if f.has(NESTED[nf]):
			has = true
	if not has:
		return f
	var g := f.duplicate(true)
	for fld in FIELDS:
		var k := kf(fld)
		if g.has(k) and g.has(fld) and _ints(g[fld]) == _ints(g.get(k + "_i", null)):
			g.erase(fld)
			g.erase(k + "_i")
	for nf in NESTED:
		var k2: String = NESTED[nf]
		if g.has(k2) and g.has(nf) and nested_ints(g, nf) == _ints(g.get(k2 + "_i", null)):
			var v: Variant = g[nf]
			if v is Dictionary:
				(v as Dictionary).erase("body")
			else:
				for d in v:
					(d as Dictionary).erase("body")
			g.erase(k2 + "_i")
	return g


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
	for nf in NESTED:
		var nk: String = NESTED[nf]
		if not f.has(nf) or f.has(nk):
			continue
		var nidx := nested_ints(f, nf)
		if nidx.is_empty() or (f[nf] is Array and nidx.size() != (f[nf] as Array).size()):
			continue
		var nks: Array = []
		for x in nidx:
			if x < 0 or x >= keys.size():
				nks.clear()
				break
			nks.append(String(keys[x]))
		if nks.is_empty():
			continue
		f[nk] = nks if f[nf] is Array else nks[0]
		f[nk + "_i"] = nidx if f[nf] is Array else nidx[0]


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
	for nf in NESTED:
		var nk: String = NESTED[nf]
		if not f.has(nk) or not f.has(nf):
			continue
		var ncur := nested_ints(f, nf)
		if ncur != _ints(f.get(nk + "_i", null)):
			f.erase(nk)
			f.erase(nk + "_i")
			stamp_step(f, keys)
			continue
		var nks: Array = f[nk] if f[nk] is Array else [f[nk]]
		var nidx: Array = []
		for key in nks:
			var at := keys.find(String(key))
			if at < 0:
				return "step %d (%s): the body %s that the face in '%s' pointed at is gone (an earlier step removed it)" % [si + 1, String(f.get("name", f.get("id", ""))), String(key), nf]
			nidx.append(at)
		nested_set(f, nf, nidx)
		f[nk + "_i"] = nidx if f[nk] is Array else nidx[0]
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
		for nf in NESTED:
			var nv: Variant = (feats[i] as Dictionary).get(NESTED[nf], null)
			for key in (nv if nv is Array else [nv]):
				if key is String and (key as String).begins_with(id + "#"):
					hit = true
		if hit:
			out.append("%d (%s)" % [i + 1, String(feats[i].get("id", ""))])
	return "" if out.is_empty() else "steps " + ", ".join(out)
