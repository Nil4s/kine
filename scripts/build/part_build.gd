## PART BUILD (11-04 AI COST): ONE call puts a whole part on screen from JSON steps, so an outside AI (MCP, serve, the
## CLI) builds a part in a few calls instead of writing a GDScript generator (CH14 wrote 267 lines of one) or clicking.
##   part_build {steps: [...]}            a new part from these steps (the record's "features" format, scripts/build/part.gd)
##   part_build {part: {features: [...]}} the same, from a whole record
##   part_build {steps: [...], append: true}  adds the steps to the part on screen: send only what is new (cheaper than
##                                         sending the whole part again)
##   name, save: true (into My parts), facts: true (the part_facts lines too, capped by cap)
## A step needs only "t" and its own fields: a missing id / name is given (f<seq>, "Prim3"), so hand-written steps are not
## dropped the way Part.from_file drops them. Unknown kinds are refused with the list. ONE undo step.
## -> {"ok", "bodies", "volume_mm3", "box_mm", "steps", "errors": {step id: why}, "saved"?, "facts"?} ; the reply stays short
## on purpose: an AI pays for every byte it reads, on every later turn.
class_name PartBuild
extends RefCounted

const MyParts := preload("res://scripts/build/myparts.gd")
const MM := 0.001


static func serve(m: Node, p: Dictionary) -> Dictionary:
	if not Part.available():
		return {"ok": false, "error": Part.why_not()}
	var steps: Array = []
	if p.get("steps") is Array:
		steps = p["steps"]
	elif p.get("part") is Dictionary and (p["part"] as Dictionary).get("features") is Array:
		steps = p["part"]["features"]
	else:
		return {"ok": false, "error": "part_build needs {\"steps\": [{\"t\": \"prim\", \"kind\": \"box\", \"op\": \"new\", \"x\": 0, \"y\": 0, \"z\": 0, \"w\": 40, \"h\": 10, \"d\": 20}, ...]} or {\"part\": {\"features\": [...]}}"}
	var append := bool(p.get("append", false)) and not (m.S.part as Dictionary).is_empty()
	var nm := String(p.get("name", (p.get("part", {}) as Dictionary).get("name", "Part") if p.get("part") is Dictionary else "Part"))
	var rec: Dictionary = (m.S.part as Dictionary).duplicate(true) if append else Part.make(nm)
	var bad := []
	var added := 0
	for s in steps:
		if not (s is Dictionary) or not Part.KINDS.has(String(s.get("t", ""))):
			bad.append(String(s.get("t", "?")) if s is Dictionary else str(s))
			continue
		var fields: Dictionary = (s as Dictionary).duplicate(true)
		var t := String(fields["t"])
		var want_id := String(fields.get("id", ""))
		if want_id != "" and Part.index_of(rec, want_id) < 0:   # its own id is kept (later steps may name it), seq moves past it
			rec["seq"] = maxi(int(rec.get("seq", 0)), int(want_id.trim_prefix("f")) if want_id.trim_prefix("f").is_valid_int() else 0)
		else:
			fields.erase("id")
		var f := Part.new_feature(rec, t, {})
		if want_id != "" and fields.has("id"):
			f["id"] = want_id
		fields.erase("t")
		f.merge(fields, true)
		(rec["features"] as Array).append(f)
		added += 1
	if not bad.is_empty():
		return {"ok": false, "error": "unknown step kinds %s: the kinds are %s" % [bad, ", ".join(Part.KINDS)]}
	if added == 0:
		return {"ok": false, "error": "no steps to build"}
	var res := Part.replay(rec, -1, {"effects": true})
	var errs: Dictionary = res.get("errors", {})
	m._step_hint = "AI: build %s (%d steps)" % [nm, added] if not append else "AI: add %d steps" % added
	m._push_undo()
	m.S.part = rec
	if m.has_method("_fit_top"):
		m._fit_top.call_deferred()
	var bb: AABB = res.get("aabb", AABB())
	var box := {"min": [snappedf(bb.position.x / MM, 0.1), snappedf(bb.position.y / MM, 0.1), snappedf(bb.position.z / MM, 0.1)],
		"size": [snappedf(bb.size.x / MM, 0.1), snappedf(bb.size.y / MM, 0.1), snappedf(bb.size.z / MM, 0.1)]}
	var out := {"ok": true, "bodies": int(res.get("bodies", 0)), "volume_mm3": snappedf(float(res.get("volume", 0.0)) / (MM * MM * MM), 0.1),
		"box_mm": box, "steps": (rec["features"] as Array).size(), "errors": errs}
	if bool(p.get("save", false)):
		out["saved"] = MyParts.save(rec, MyParts.free_name(nm) if MyParts.exists(nm) and not bool(p.get("overwrite", false)) else nm)
	if bool(p.get("facts", false)):
		var fx := PartFacts.facts(rec, {"cap": int(p.get("cap", 30))})
		out["facts"] = fx.get("lines", []) if fx.get("ok", false) else String(fx.get("error", ""))
	return out
