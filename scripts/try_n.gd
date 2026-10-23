## TRY N WAYS (N019, docs/INNOVATIONS.md): trial and error in ONE call. A blind agent that wants to know which of five
## timings reads best would otherwise run, check, score and undo five times (five round trips, ~6 s each, and five
## chances to leave the scene half-undone). `try` takes the variants, runs each one, scores it and ranks them:
##   {variants: [[steps...], [steps...], ...]}                    each variant a step list, as `run` takes
##   {base: ["retime=3-3:{pct}"], sweep: {param: "pct", values: [80, 90, 100, 110, 120]}}   one change, a parameter swept:
##                                                                 every "{pct}" in the base steps is replaced by each value
##   score: false   rank by the assertions and Check only (the realism score costs ~5 s a read: once for the start and
##                  once per variant)
##   asserts: [...] N002 lines judged on each variant (default: the scene's saved ones, m.S.asserts)
##   apply: "best" | n   then run that variant (n = its "variant" number, 1-based as in the request) for real, as ONE undo step
## HOW: each variant is an N003 dry run (scripts/dry_run.gd): the steps run through the same code a real `run` runs
## (AgentTools.step) and everything is put back, proven byte for byte (its "restored"). Chosen over real undo-tree
## branches: a branch per variant would leave N abandoned branches in Nick's History panel, and walking to each costs a
## full _restore anyway; the dry run already restores, proves it, and refuses file-writing steps. The variant's own
## numbers are read IN its dry state through DryRun.run's probe (the assertions, the realism score), Check's counts and
## the diff (cards changed, joints moved) are the dry run's own report.
## RANK (best first), a variant that failed (a bad step, a refused step) is listed apart under "failed":
##   1 fewer assertions failing (the agent's own spec comes first: a nicer score that breaks "left foot planted" loses)
##   2 higher realism score (when scored)
##   3 fewer MUST FIX findings, 4 fewer findings in all, 5 the order asked (a tie keeps the agent's order)
class_name TryN
extends RefCounted

const MAX_VARIANTS := 20   # HEURISTIC: 20 scored variants is ~2.5 min on combo3 (one ~7 s each); more is a batch job, not a call


## the variants a request asks for: {"variants": [[...], ...]} or {"error": why}
static func variants(p: Dictionary) -> Dictionary:
	var vs := []
	if p.has("variants"):
		var v: Variant = p["variants"]
		if not (v is Array) or v.is_empty():
			return {"error": "variants must be a list of step lists"}
		for x in v:
			if not (x is Array) or x.is_empty() or not x.all(func(s): return s is String):
				return {"error": "each variant is a non-empty list of run's steps, e.g. [\"retime=3-3:90\"]"}
			vs.append(x)
	elif p.has("base") and p.has("sweep"):
		var base: Variant = p["base"]
		var sw: Variant = p["sweep"]
		if not (base is Array) or base.is_empty() or not base.all(func(s): return s is String):
			return {"error": "base is a step list with {param} in it, e.g. [\"retime=3-3:{pct}\"]"}
		if not (sw is Dictionary) or not (sw.get("param") is String) or not (sw.get("values") is Array) or (sw["values"] as Array).is_empty():
			return {"error": "sweep is {\"param\": \"pct\", \"values\": [80, 90, 100]}"}
		var tag := "{%s}" % sw["param"]
		if not base.any(func(s): return String(s).contains(tag)):
			return {"error": "no step of base has %s in it: nothing to sweep" % tag}
		for val in sw["values"]:
			var txt := str(int(val)) if (val is float and val == floorf(val)) else str(val)   # JSON numbers are floats: 80 -> "80"
			vs.append(base.map(func(s): return String(s).replace(tag, txt)))
	else:
		return {"error": "try needs {\"variants\": [[steps], [steps], ...]} or {\"base\": [\"retime=3-3:{pct}\"], \"sweep\": {\"param\": \"pct\", \"values\": [80, 90, 100]}}"}
	if vs.size() > MAX_VARIANTS:
		return {"error": "%d variants: at most %d in one call" % [vs.size(), MAX_VARIANTS]}
	return {"variants": vs}


## the serve method
static func request(T: AgentTools, id: Variant, p: Dictionary) -> Dictionary:
	var vr := variants(p)
	if vr.has("error"):
		return T._err(id, -32602, String(vr["error"]) + "; optional score: false, asserts: [...], apply: \"best\" | n")
	if T.m.S.cards.size() < 2:
		return T._err(id, -32602, "try needs a scene of 2+ cards: open one first")
	var al: Variant = p.get("asserts", T.m.S.asserts)
	if not (al is Array) or not al.all(func(s): return s is String):
		return T._err(id, -32602, "asserts is a list of N002 lines, e.g. [\"left foot planted 0-0.4 s\"]")
	var ap: Variant = p.get("apply")
	if ap != null and not (ap is String and ap == "best") and not ((ap is float or ap is int) and int(ap) >= 1 and int(ap) <= vr["variants"].size()):
		return T._err(id, -32602, "apply is \"best\" or a variant number 1-%d" % vr["variants"].size())
	var r := await run(T, vr["variants"], bool(p.get("score", true)), al, ap)
	if r.has("error"):
		return T._err(id, -32000, String(r["error"]), r)
	return T._ok(id, r)


## {"pass", "passed", "failed", "failing": [lines]} of N002 lines on the live scene; null with none
static func _asserts(m: Node, al: Array) -> Variant:
	if al.is_empty():
		return null
	var a := BodyAssert.run(m.S, m.B, al)
	return {"passed": a["passed"], "failed": int(a["failed"]) + int(a["unread"]),
		"failing": a["results"].filter(func(x): return not x.get("pass", false)).map(func(x): return x["line"])}


## THE TRY. score: read the realism score; al: N002 lines; ap: null, "best" or a variant number
static func run(T: AgentTools, vs: Array, score := true, al: Array = [], ap: Variant = null) -> Dictionary:
	var m: Node = T.m
	var t0 := Time.get_ticks_msec()
	var sc0: Variant = DryRun.cold_score(m) if score else null
	var as0: Variant = _asserts(m, al)
	var probe := func() -> Dictionary: return {"score": DryRun.cold_score(m) if score else null, "asserts": _asserts(m, al)}
	var ok_rows := []
	var bad := []
	var restored := true
	var f_before := -1
	for i in vs.size():
		var steps: Array = vs[i]
		var d: Dictionary = await DryRun.run(T, steps, false, probe)
		if d.has("refused"):
			bad.append({"variant": i + 1, "steps": steps, "ok": false, "error": "refused, nothing ran: " + "; ".join(d["refused"].map(func(x): return "%s: %s" % [x["step"], x["why"]]))})
			continue
		restored = restored and bool(d["restored"])
		if not d["ok"]:
			bad.append({"variant": i + 1, "steps": steps, "ok": false, "error": d.get("error", "failed")})
			continue
		var pr: Dictionary = d["probe"]
		var fd: Dictionary = d["findings"]
		f_before = int(fd["before"])
		var row := {"variant": i + 1, "steps": steps, "ok": true,
			"score": pr["score"], "score_delta": snappedf(float(pr["score"]) - float(sc0), 0.01) if score and pr["score"] != null and sc0 != null else null,
			"asserts": pr["asserts"],
			"findings": fd["after"], "must_fix": fd["must_fix_after"], "findings_added": fd["added"], "findings_removed": fd["removed"],
			"diff": {"cards": d["cards"]["changed"], "added": d["cards"]["added"], "removed": d["cards"]["removed"], "lines": d["cards"]["lines"],
				"settings": d["cards"]["settings"], "keys_touched": d["keys_touched"], "parts_moved": d["parts_moved"]},
			"undo_steps": d["undo_steps"]}
		ok_rows.append(row)
	ok_rows.sort_custom(better)
	for k in ok_rows.size():
		ok_rows[k]["rank"] = k + 1
	var r := {"ok": true, "how": "each variant an N003 dry run (scripts/dry_run.gd), the scene put back after each",
		"scored": score, "start": {"score": sc0, "asserts": as0, "findings": f_before if f_before >= 0 else null},
		"ranked": ok_rows, "failed": bad, "best": ok_rows[0]["variant"] if not ok_rows.is_empty() else null,
		"restored": restored, "ms": Time.get_ticks_msec() - t0,
		"rank_by": "fewest assertions failing, then highest realism score%s, then fewest MUST FIX, then fewest findings, then the order asked" % ("" if score else " (not read: score false)")}
	if ap != null:
		var want: int = int(r["best"]) if ap is String else int(ap)
		var pick: Array = ok_rows.filter(func(x): return x["variant"] == want) if r["best"] != null else []
		if pick.is_empty():
			r["ok"] = false
			r["error"] = "nothing applied: %s" % ("every variant failed" if r["best"] == null else "variant %d failed" % want)
			return r
		r["applied"] = await apply(T, pick[0]["steps"], "try: variant %d of %d" % [want, vs.size()])
		r["applied"]["variant"] = want
		if not r["applied"]["ok"]:
			r["ok"] = false
			r["error"] = "the apply's step failed: " + String(r["applied"]["error"])
	return r


## the rank order: true when a goes before b
static func better(a: Dictionary, b: Dictionary) -> bool:
	var fa := int(a["asserts"]["failed"]) if a["asserts"] != null else 0
	var fb := int(b["asserts"]["failed"]) if b["asserts"] != null else 0
	if fa != fb:
		return fa < fb
	if a["score"] != null and b["score"] != null and float(a["score"]) != float(b["score"]):
		return float(a["score"]) > float(b["score"])
	if int(a["must_fix"]) != int(b["must_fix"]):
		return int(a["must_fix"]) < int(b["must_fix"])
	if int(a["findings"]) != int(b["findings"]):
		return int(a["findings"]) < int(b["findings"])
	return int(a["variant"]) < int(b["variant"])


## the steps for real, their undo entries squashed into ONE step (main._squash_undo, the AI box's way): one Ctrl+Z
## takes the whole variant back. Entries counted by identity (DryRun's way): at the 60-entry cap a size difference reads 0
static func apply(T: AgentTools, steps: Array, name: String) -> Dictionary:
	var m: Node = T.m
	var undo0: Array = (m.undo as Array).duplicate()
	var out := []
	for s: String in steps:
		var st: Dictionary = await T.step(s)
		out.append(st)
		if not st["ok"]:
			return {"ok": false, "steps": out, "error": st["error"]}
	var pushed: int = m.undo.filter(func(e): return not undo0.any(func(x): return is_same(x, e))).size()
	if pushed >= 2:
		m._squash_undo(m.undo.size() - pushed, name)
	return {"ok": true, "steps": out, "undo_steps": mini(pushed, 1)}


## the report as lines (the CLI's)
static func lines(r: Dictionary) -> Array:
	var out := []
	for x in r.get("ranked", []):
		out.append("#%d  variant %d  %s  score %s  asserts failing %s  findings %d (must fix %d)  joints moved %d  cards changed %d" % [x["rank"], x["variant"],
			" ".join(x["steps"]), x["score"] if x["score"] != null else "-", x["asserts"]["failed"] if x["asserts"] != null else "-", x["findings"], x["must_fix"],
			x["diff"]["parts_moved"].size(), x["diff"]["cards"].size()])
	for x in r.get("failed", []):
		out.append("FAILED variant %d  %s: %s" % [x["variant"], " ".join(x["steps"]), x["error"]])
	if r.has("applied"):
		out.append("applied variant %d as one undo step" % r["applied"]["variant"])
	return out
