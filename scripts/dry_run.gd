## DRY RUN ANY COMMAND (N003, docs/INNOVATIONS.md): "what would this do?" for any `run` step list, the live scene left
## exactly as it was. A blind agent can't undo by looking, so it asks first and gets:
##   parts_moved   the live body's joints that would turn more than TOL deg (bend / side / twist deltas, largest first)
##   findings      Check before and after: how many, and which are added / removed (rule, card, time, message)
##   score         the realism score (I16 + the I45 judges) before / after and the change, on the shown 0-100 scale
##   cards / keys  SceneDiff (tools/scene_diff.gd) of the scene file before -> after (cards added, removed, renamed, timing,
##                 joints > 0.5 deg) and every other top-level key of the file that would change (part_keys, markers, ...)
## HOW (the R10 `ask` way, scripts/what_if.gd, grown from one body to the whole session; JudgeSuite.fix's "on a copy"):
## the steps run through the SAME code a real `run` runs (AgentTools.step), on the live session, then everything is put
## back: every script variable of the open Scene object (deep copies taken before), the body (B.state), main's undo snapshot
## (_restore: the other fighters, props, ...), the undo / redo LISTS themselves and the undo tree OBJECT (the dry steps were
## pushed onto copies), main's plain variables (picked card, part, playhead, toggles), the findings and the status line.
## While it runs, nothing may reach the disk: the journal is off, the 15 s autosave and the auto-version clock are held.
## PROOF: every dry run compares the scene file's JSON bytes (without its derived bad_frames), var_to_str(B.state()) and the undo / redo sizes before and
## after, and says "restored": true only when all are identical (tests/dryrun_test.gd checks it on 30+ edit commands).
## REFUSED (nothing runs, the reason is given): a step that writes files or opens a dialog. AgentTools.REFUSE first, then
## the registry's own words (name / id / description: "writes", "exports/", "user://", "saved in", "pick a ...", a name
## ending "..." = a dialog). A HEURISTIC list: a command whose description hides a write would slip past; the test hashes
## the project's scenes/ poses/ exports/ data/ around every dry run to catch one.
class_name DryRun
extends RefCounted

const TOL := 0.5   # deg: SceneDiff.TOL (the files round to 0.01; a drag moves whole degrees)

## words in a registry entry's id that mean it writes a file or waits on a person (checked on the id, lower case)
const ID_WORDS := ["save", "export", "pack", "share", "render", "record", "import", "deliver", "template", "restore", "recent",
	"version", "playblast", "cheat_sheet", "macro", "script", "co-edit", "qr", "comfyui", "star_this", "silhouette_sheet", "safety_sheet",
	"floor_plan", "kbody", "video", "plugins"]
## the same in its description (lower case); "saved with the scene" / "never saved" / "nothing is saved" stay allowed
const DESC_WORDS := ["writes ", "exports/", "user://", "scenes/_wip", "saved in", "saved to", "saved as", "save it", "pick a ", "pick an ",
	"pick one of", "a small dialog", "on this computer", "(remembered)", "remembered)", "in your kine folder", "opened in the browser"]


## "" = may run dry; else why it is refused
static func refused(tok: String, reg: Dictionary) -> String:
	if AgentTools.REFUSE.has(tok):
		return AgentTools.REFUSE[tok]
	if tok.begins_with("physics="):
		return "physics= imports a reaction as a NEW scene file in scenes/_wip: a dry run writes nothing"
	if not reg.has(tok):
		return ""   # card= / sel= / set= / pose= / fix= / retime= / update / add / delete / name= / undo / redo: in memory only
	var c: Dictionary = reg[tok]
	var nm := String(c["name"])
	if nm.ends_with("..."):
		return "'%s' opens a dialog that waits for a person's pick: nothing to answer without one" % nm
	for w in ID_WORDS:
		if tok.contains(w):
			return "'%s' writes a file, opens a picker or plays in real time (its id says '%s'): a dry run writes nothing" % [nm, w]
	var d := String(c["desc"]).to_lower()
	for w in DESC_WORDS:
		if d.contains(w):
			return "'%s' writes a file or asks a person (its description says '%s'): a dry run writes nothing" % [nm, w.strip_edges()]
	return ""


## the serve method: {"steps": [...], "score": true} -> JSON-RPC result / error (T's own _ok / _err)
static func request(T: AgentTools, id: Variant, p: Dictionary) -> Dictionary:
	var steps: Variant = p.get("steps")
	if not (steps is Array) or steps.is_empty() or not steps.all(func(s): return s is String):
		return T._err(id, -32602, "dry needs {\"steps\": [\"card=2\", \"mirror_the_whole_pose\", \"update\"]} (run's steps; nothing is changed), optional \"score\": false to skip the realism score")
	var r := await run(T, steps, bool(p.get("score", true)))
	if r.has("refused"):
		return T._err(id, -32602, "refused, nothing ran: " + "; ".join(r["refused"].map(func(x): return "%s: %s" % [x["step"], x["why"]])), r)
	return T._ok(id, r)


## THE DRY RUN. score = also the realism score before / after (the timing coach's move database is read once, ~20 s)
static func run(T: AgentTools, steps: Array, score := true) -> Dictionary:
	var m: Node = T.m
	var no := []
	for s: String in steps:
		var why := refused(s, T.reg)
		if why != "":
			no.append({"step": s, "why": why})
	if not no.is_empty():
		return {"ok": false, "dry": true, "refused": no}
	# ---- before
	var S0: Scene = m.S
	var sd0 := _file(m)
	var js0 := JSON.stringify(sd0)
	var b0: Dictionary = m.B.state()
	var bs0 := var_to_str(b0)
	var nu0: int = m.undo.size()
	var nr0: int = m.redo.size()
	var f0: Array = T.findings() if S0.cards.size() >= 2 else []
	var sc0: Variant = cold_score(m) if score else null
	var keep_findings: Array = m.findings
	var keepS := _vars(S0)
	var u0: Dictionary = m._snapshot()
	var undo0: Array = m.undo
	var redo0: Array = m.redo
	var tree0: UndoTree = m._tree
	var prim0 := _prims(m)
	var status0 := String(m.ui_status.text) if m.ui_status != null else ""
	# ---- the run, on copies of the lists; nothing to disk
	m.undo = undo0.duplicate()
	m.redo = redo0.duplicate()
	m._tree = UndoTree.new()
	m.journal_on = false
	m._as_wait = -1e12
	m.autover_min = 0
	var out := []
	var err := ""
	for s: String in steps:
		var st: Dictionary = await T.step(s)
		out.append(st)
		if not st["ok"]:
			err = "step %d of %d failed: %s" % [out.size(), steps.size(), st["error"]]
			break
	# ---- after (measured in the dry state)
	var swapped: bool = m.S != S0
	var sd1 := _file(m)
	var ang1: Dictionary = (m.B.ang as Dictionary).duplicate()
	# Check and the score judge the FILE (cards, settings, keys, proportions), not the live body: a body-only step leaves
	# the file's bytes as they were, and their answers are the ones before (Check costs ~1.1 s on combo3)
	var same_file := not swapped and JSON.stringify(sd1) == js0
	var f1: Array = f0 if same_file else (T.findings() if m.S.cards.size() >= 2 else [])
	var sc1: Variant = sc0 if same_file else (cold_score(m) if score else null)
	# the steps it would push: entries that are not the original ones (by identity; a size difference reads 0 at the 60 cap)
	var would_undo: int = m.undo.filter(func(e): return not undo0.any(func(x): return is_same(x, e))).size()
	# ---- put back
	if swapped:
		m.S = S0
	for k in keepS:
		S0.set(k, keepS[k])
	m._restore(u0)
	m.B.set_state(b0)
	m.undo = undo0
	m.redo = redo0
	m._tree = tree0
	_prims_back(m, prim0)
	m._rebuild_cards()
	m._refresh()
	_prims_back(m, prim0)
	m.findings = keep_findings
	if m.ui_status != null:
		m.ui_status.text = status0
	# ---- the proof, and the report
	var js2 := JSON.stringify(_file(m))
	var bs2 := var_to_str(m.B.state())
	var proof := {"scene_json": js2 == js0, "body_state": bs2 == bs0, "undo": m.undo.size() == nu0 and m.redo.size() == nr0}
	var d := SceneDiff.diff(sd0, sd1)
	var keys := []
	for k in _union(sd0.keys(), sd1.keys()):
		if k != "cards" and k != "scene" and JSON.stringify(sd0.get(k)) != JSON.stringify(sd1.get(k)):
			keys.append(k)
	var r := {"ok": err == "", "dry": true, "steps": out, "restored": proof.values().all(func(x): return x), "proof": proof,
		"parts_moved": body_moved(b0["ang"], ang1),
		"findings": findings_delta(f0, f1),
		"cards": {"same": d["same"], "added": d["added"], "removed": d["removed"], "renamed": d["renamed"], "changed": d["cards"], "settings": d["settings"],
			"lines": SceneDiff.lines(d)},
		"keys_touched": keys, "undo_steps": would_undo, "scene_swapped": swapped}
	if score:
		r["score"] = {"before": sc0, "after": sc1, "delta": snappedf(float(sc1) - float(sc0), 0.01) if sc0 != null and sc1 != null else null,
			"note": "the shown realism score 0-100 (RealismScore.shown of the raw total), every judge asked cold" if sc0 != null else "needs a scene of two cards or more"}
	if err != "":
		r["error"] = err
	return r


## joints of the live body that turn more than TOL: [{joint, d: [bend, side, twist], max}] largest first (SceneDiff._joints' form)
static func body_moved(a0: Dictionary, a1: Dictionary) -> Array:
	var out := []
	for j in Body.ORDER:
		if not a0.has(j) or not a1.has(j):
			continue
		var dv: Vector3 = (a1[j] as Vector3) - (a0[j] as Vector3)
		var mx := maxf(absf(dv.x), maxf(absf(dv.y), absf(dv.z)))
		if mx > TOL:
			out.append({"joint": j, "d": [snappedf(dv.x, 0.01), snappedf(dv.y, 0.01), snappedf(dv.z, 0.01)], "max": snappedf(mx, 0.01)})
	out.sort_custom(func(p, q): return p["max"] > q["max"])
	return out


## Check's findings before -> after, matched by rule + card + time + message
static func findings_delta(f0: Array, f1: Array) -> Dictionary:
	var key := func(f: Dictionary) -> String: return "%s|%s|%.2f|%s" % [f["rule"], f["card_name"], float(f["t"]), f["msg"]]
	var k0 := {}
	for f in f0:
		k0[key.call(f)] = f
	var k1 := {}
	for f in f1:
		k1[key.call(f)] = f
	var strip := func(f: Dictionary) -> Dictionary: return {"sev": f["sev"], "rule": f["rule"], "t": f["t"], "card": f["card"], "card_name": f["card_name"], "msg": f["msg"]}
	return {"before": f0.size(), "after": f1.size(),
		"must_fix_before": f0.filter(func(f): return f["sev"] == "MUST FIX").size(), "must_fix_after": f1.filter(func(f): return f["sev"] == "MUST FIX").size(),
		"added": k1.keys().filter(func(k): return not k0.has(k)).map(func(k): return strip.call(k1[k])),
		"removed": k0.keys().filter(func(k): return not k1.has(k)).map(func(k): return strip.call(k0[k]))}


## the realism score as the panel shows it, every judge asked fresh (tests/i16_test.gd's _cold_score): null under two cards.
## The caches the panel keeps are put back, so asking changes nothing it shows
static func cold_score(m: Node) -> Variant:
	if m.S.cards.size() < 2 or m.rs_ui == null:
		return null
	if int(m.tc_ui.db.get("n", 0)) == 0:
		m.tc_ui.db = MotionMatch.build()   # the timing coach's move database: read once a session, as the panel does
	var rs: RealismUI = m.rs_ui
	var keep := [rs._memo, rs.jcache, rs.lap, rs.jlap, m.force_cache, m._sm, FrameMemo._mem]
	rs._memo = {}
	rs.jcache = {}
	m.force_cache = {}
	FrameMemo._mem = {}
	FrameMemo.probe = true
	var g := rs.gather(m.tc_ui.db)
	FrameMemo.probe = false
	var raw := float(RealismScore.compute(m.S, g)["raw"])
	rs._memo = keep[0]
	rs.jcache = keep[1]
	rs.lap = keep[2]
	rs.jlap = keep[3]
	m.force_cache = keep[4]
	m._sm = keep[5]
	FrameMemo._mem = keep[6]
	return snappedf(RealismScore.shown(raw), 0.01)


## the scene file as Save would write it, without "bad_frames" (Check's sampling of the whole clip, ~1 s on combo3, and a
## function of the rest of the file): what the diff and the proof compare
static func _file(m: Node) -> Dictionary:
	var keep: Dictionary = m.B.state()
	var sd: Dictionary = m.S.to_dict(m.B, false)
	m.B.set_state(keep)
	return sd


## every script variable of a Scene, deep-copied (objects kept by reference: the baker, a weakref)
static func _vars(o: Object) -> Dictionary:
	var out := {}
	for p in o.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var v: Variant = o.get(p["name"])
			out[p["name"]] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	return out


## main's plain script variables (bool, int, float, String, vectors): the picked card / part, the playhead, the toggles,
## the autosave / journal clocks
static func _prims(m: Node) -> Dictionary:
	var out := {}
	for p in m.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE and int(p["type"]) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR2I]:
			out[p["name"]] = m.get(p["name"])
	return out


static func _prims_back(m: Node, keep: Dictionary) -> void:
	for k in keep:
		var v: Variant = m.get(k)
		if typeof(v) != typeof(keep[k]) or v != keep[k]:
			m.set(k, keep[k])


static func _union(a: Array, b: Array) -> Array:
	var out := a.duplicate()
	for x in b:
		if not out.has(x):
			out.append(x)
	return out
