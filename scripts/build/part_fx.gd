class_name PartFx
extends RefCounted
## ITEM 241 WHAT A STEP DID (AI ease 1; temple build log: a pattern added bodies the AI never saw named, so the next name step hit the wrong copy).
## Every Part feature call and agent call that creates or changes bodies returns the SAME shape, taken from the replay's own body list (never from geometry):
##   {"step": n, "feature": "f12", "t": "pattern",
##    "created": [{"id": 5, "key": "f12#0", "name": "Door panel 2"}],
##    "changed": [{"id": 0, "key": "f3#0", "name": "Door panel", "was": "Body1"?}],     # "was": the old name, only when the name changed
##    "removed": [{"id": 2, "key": "f4#0", "name": "Step"}]}
## "step" = the index of the feature in the part's feature list. WHAT "id" MEANS: the body's index in the part's body list AFTER the step (a removed
## body: its index BEFORE it); it is what `body` fields of pattern / bname / appear / combine take (Body<id+1>). It is NOT stable: a join that removes a
## body, a split or a delete shifts every index after it. "key" IS stable: "<id of the feature that made the body>#<k>" (k = its order among the bodies
## that feature made); a body keeps its key through every later join / cut / move / rename / replay, and a record's keys are the same on every replay
## (feature ids are stored in the record). Names are NOT unique (a pattern's copies are "Name 2", "Name 3"; two steps can use one name): use key.
## How a step's before / after body lists are paired (kernel ids: a body no step touched keeps its id, a touched one gets a new id): bodies whose id
## survived are the same body; in each gap between survivors the new ids are paired in order with the vanished ones (those are "changed", they keep
## their key) and the surplus new ones are "created", the surplus vanished ones "removed". A combine is paired by its own target / tools fields.
## Known limit: an intersect that drops a body BETWEEN two it keeps (new ids for both) pairs by position inside the gap, so the dropped body may be
## reported as the last of the gap rather than the middle one; the counts are right.
## replay(rec, -1, {"effects": true}) fills res["effects"] (one entry per step, in order), res["body_keys"], res["body_touch"] (key -> feature ids that
## made / changed it). It does not use the incremental cache (that cache holds no keys).


## S267 CIRCULAR PATTERN ABOUT ANY AXIS (pattern step, "kind": "circular", "count" N, "deg" 360 or the sweep, "body" i). With no axis field it turns about the
## world axis "axis" ("x" | "y" | "z", default "y") through the ORIGIN. To turn about another line give ONE of:
##   "pivot": [x,y,z] mm (a point on the line) AND "adir": [x,y,z] (its direction)   (both, or the pattern is refused with these words)
##   "axis_edge": [[x,y,z],[x,y,z]] mm        (two points of an edge: the line through them)
##   "axis_face": {"o": [x,y,z], "n": [x,y,z]} (a point on a face and its normal: the line through it square to the face)
## Example, 11 blades about a fan at (90, 20, 5) whose axle runs along +Z: {"t":"pattern","kind":"circular","body":3,"count":11,"op":"join","axis_face":{"o":[90,20,5],"n":[0,0,1]}}.

static func begin() -> Dictionary:
	return {"ids": [], "keys": [], "names": [], "looks": [], "steps": [], "touch": {}}


static func _look_str(looks: Array, i: int) -> String:
	return JSON.stringify(Part.look_at(looks, i))


## the step f (index si) just ran: compare the body list to the snapshot taken after the step before, record the entry, take a new snapshot
static func close(fx: Dictionary, bodies: Array, looks: Array, f: Dictionary, si: int, errs: Dictionary) -> void:
	var B: Array = fx["ids"]
	var Bk: Array = fx["keys"]
	var Bn: Array = fx["names"]
	var Bl: Array = fx["looks"]
	var fid := String(f.get("id", ""))
	var amap: Array = []   # per after-body: the before index it is, or -1 (made by this step)
	amap.resize(bodies.size())
	amap.fill(-1)
	if String(f.get("t", "")) == "combine" and not errs.has(fid) and not bool(f.get("off", false)):
		var tg := int(f.get("target", -1))
		var tools: Array = []
		for t in f.get("tools", []):
			tools.append(int(t))
		var keep := bool(f.get("keep", false))
		var j := 0
		for i in B.size():
			if i != tg and tools.has(i) and not keep:
				continue
			if j < amap.size():
				amap[j] = i
			j += 1
	else:
		var posb := {}
		for i in B.size():
			posb[int(B[i])] = i
		var anchors: Array = []   # [after index, before index], both increasing
		var last := -1
		for j in bodies.size():
			var q = posb.get(int(bodies[j]), -1)
			if int(q) > last:
				anchors.append([j, int(q)])
				last = int(q)
		anchors.append([bodies.size(), B.size()])
		var ja := 0
		var jb := 0
		for a in anchors:
			var na: int = int(a[0]) - ja
			var nb: int = int(a[1]) - jb
			for k in mini(na, nb):
				amap[ja + k] = jb + k
			if int(a[0]) < bodies.size():
				amap[int(a[0])] = int(a[1])
			ja = int(a[0]) + 1
			jb = int(a[1]) + 1
	var made: Array = []
	var changed: Array = []
	var removed: Array = []
	var keys: Array = []
	var names: Array = []
	var lstr: Array = []
	var used := {}
	var kmade := 0
	for j in bodies.size():
		var nm := Part.name_at(looks, j)
		var ls := _look_str(looks, j)
		names.append(nm)
		lstr.append(ls)
		var bi: int = int(amap[j])
		if bi < 0:
			var key := "%s#%d" % [fid, kmade]
			kmade += 1
			keys.append(key)
			made.append({"id": j, "key": key, "name": nm})
			fx["touch"][key] = [fid]
		else:
			used[bi] = true
			var key2 := String(Bk[bi])
			keys.append(key2)
			var moved := int(bodies[j]) != int(B[bi]) if String(f.get("t", "")) != "combine" or errs.has(fid) else true
			if String(f.get("t", "")) == "combine" and not errs.has(fid):
				moved = int(bodies[j]) != int(B[bi])
			if moved or ls != String(Bl[bi]) or nm != String(Bn[bi]):
				var e := {"id": j, "key": key2, "name": nm}
				if nm != String(Bn[bi]):
					e["was"] = String(Bn[bi])
				changed.append(e)
				(fx["touch"][key2] as Array).append(fid)
	for i in B.size():
		if not used.has(i):
			removed.append({"id": i, "key": String(Bk[i]), "name": String(Bn[i])})
	(fx["steps"] as Array).append({"step": si, "feature": fid, "t": String(f.get("t", "")), "created": made, "changed": changed, "removed": removed})
	fx["ids"] = bodies.duplicate()
	fx["keys"] = keys
	fx["names"] = names
	fx["looks"] = lstr


# ---------------------------------------------------------------- readers over a replay result

## the entry of step si of a replay made with {"effects": true} ({} when that step did not run)
static func of_step(res: Dictionary, si: int) -> Dictionary:
	for e in res.get("effects", []):
		if int(e["step"]) == si:
			return (e as Dictionary).duplicate(true)
	return {}


## the entry of the feature with this id
static func of_feature(res: Dictionary, fid: String) -> Dictionary:
	for e in res.get("effects", []):
		if String(e["feature"]) == fid:
			return (e as Dictionary).duplicate(true)
	return {}


## the same entry as a result for a call: adds "ok", "error" (the step's own message when it did not build) and the body count
static func result_of(res: Dictionary, fid: String) -> Dictionary:
	var e := of_feature(res, fid)
	if e.is_empty():
		e = {"step": -1, "feature": fid, "t": "", "created": [], "changed": [], "removed": []}
	var errs: Dictionary = res.get("errors", {})
	e["ok"] = not errs.has(fid)
	if errs.has(fid):
		e["error"] = String(errs[fid])
	e["bodies"] = int(res.get("bodies", 0))
	return e


## add the entry to an existing call result (old fields kept): "step", "created", "changed", "removed" at the top, the whole entry under "fx"
static func merge_into(out: Dictionary, res: Dictionary, fid: String) -> Dictionary:
	var r := result_of(res, fid)
	out["fx"] = r
	for k in ["step", "created", "changed", "removed"]:
		out[k] = r[k]
	return out


## the NET difference of two replays (both made with effects): created / removed by key, changed = same key with another history, name or volume.
## Use it for a call that edits a step already in the record (rename, delete): the entry has "step": -1 and "feature": "".
static func net(ra: Dictionary, rb: Dictionary) -> Dictionary:
	var ka: Array = ra.get("body_keys", [])
	var kb: Array = rb.get("body_keys", [])
	var na: Array = ra.get("body_names", [])
	var nb: Array = rb.get("body_names", [])
	var va: Array = ra.get("volumes", [])
	var vb: Array = rb.get("volumes", [])
	var ta: Dictionary = ra.get("body_touch", {})
	var tb: Dictionary = rb.get("body_touch", {})
	var pa := {}
	for i in ka.size():
		pa[String(ka[i])] = i
	var pb := {}
	for j in kb.size():
		pb[String(kb[j])] = j
	var made: Array = []
	var changed: Array = []
	var removed: Array = []
	for j in kb.size():
		var k := String(kb[j])
		var nmb := String(nb[j]) if j < nb.size() else "Body%d" % (j + 1)
		if not pa.has(k):
			made.append({"id": j, "key": k, "name": nmb})
			continue
		var i: int = pa[k]
		var nma := String(na[i]) if i < na.size() else "Body%d" % (i + 1)
		var dv := absf(float(vb[j]) - float(va[i])) if j < vb.size() and i < va.size() else 0.0
		var scale := maxf(absf(float(va[i])) if i < va.size() else 0.0, 1e-12)
		if nma != nmb or str(ta.get(k, [])) != str(tb.get(k, [])) or dv > 1e-9 * scale:
			var e := {"id": j, "key": k, "name": nmb}
			if nma != nmb:
				e["was"] = nma
			changed.append(e)
	for i in ka.size():
		if not pb.has(String(ka[i])):
			removed.append({"id": i, "key": String(ka[i]), "name": String(na[i]) if i < na.size() else "Body%d" % (i + 1)})
	return {"step": -1, "feature": "", "t": "", "created": made, "changed": changed, "removed": removed, "ok": true, "bodies": int(rb.get("bodies", 0))}


# ---------------------------------------------------------------- calls that return what they did

## append a feature (type t, fields) to rec and answer what it did. rec is changed (the caller owns the undo step). {"id": the feature id} is added.
static func append(rec: Dictionary, t: String, fields := {}) -> Dictionary:
	var nf := Part.new_feature(rec, t, fields)
	(rec["features"] as Array).append(nf)
	return after(rec, nf)


## the answer for a feature already appended last (or anywhere) in rec
static func after(rec: Dictionary, nf: Dictionary) -> Dictionary:
	var res := Part.replay(rec, -1, {"effects": true})
	var r := result_of(res, String(nf["id"]))
	r["id"] = String(nf["id"])
	return r


## Part.prim and what it did
static func prim(rec: Dictionary, kind: String, fields := {}) -> Dictionary:
	var fid := Part.prim(rec, kind, fields)
	return after(rec, Part.feature(rec, fid))


## rename body bi (Part.set_body_name) and answer what changed: the renamed body in "changed" (with "was"), nothing else; "ok": false when the name is the same
static func rename(rec: Dictionary, bi: int, text: String) -> Dictionary:
	var ra := Part.replay(rec, -1, {"effects": true})
	var cur := Part.body_name(ra, bi)
	if bi < 0 or bi >= int(ra.get("bodies", 0)):
		return {"ok": false, "error": "there is no body %d" % bi, "step": -1, "feature": "", "t": "bname", "created": [], "changed": [], "removed": [], "bodies": int(ra.get("bodies", 0))}
	var st := Part.set_body_name(rec, bi, text, cur)
	var rb := Part.replay(rec, -1, {"effects": true})
	var r := net(ra, rb)
	r["t"] = "bname"
	if st.is_empty():
		r["ok"] = false
		r["error"] = "the body is already called that"
	else:
		r["feature"] = String(st["id"])
		r["step"] = Part.index_of(rec, String(st["id"]))
	return r


## delete feature fid from rec and answer what went (net: bodies gone, bodies that changed because a step under them is gone)
static func delete(rec: Dictionary, fid: String) -> Dictionary:
	var ix := Part.index_of(rec, fid)
	if ix < 0:
		return {"ok": false, "error": "there is no step %s" % fid, "step": -1, "feature": fid, "t": "", "created": [], "changed": [], "removed": []}
	var ra := Part.replay(rec, -1, {"effects": true})
	var t := String((rec["features"] as Array)[ix].get("t", ""))
	(rec["features"] as Array).remove_at(ix)
	var rb := Part.replay(rec, -1, {"effects": true})
	var r := net(ra, rb)
	r["feature"] = fid
	r["step"] = ix
	r["t"] = t
	return r
