## kine_bench.gd - KINE-BENCH (docs/INNOVATIONS.md N024): 20 graded tasks to compare agents and prompts on the SAME body.
## A task (bench/tasks/<id>.json) is a one-sentence brief, a start scene and the rules it is graded by:
##   "asserts"  N002 body-assertion lines (scripts/body_assert.gd), each with a weight w (default 1): pass / fail per line, the
##              worst miss in cm / deg / m/s and its frame, exactly what serve `assert` answers on the same scene
##   "judges"   bars on the app's own judges: "must_fix" (Check's MUST FIX count <= N: serve `check`, the default Check with the
##              human-limit rules OFF, so the count does not depend on a switch the agent may have flipped), "realism" (the I16
##              score >= X, made as the "Realism score" command makes it: RealismUI.refresh, the same call scene_brief.gd makes),
##              and named I45 judges (JudgeSuite's own reductions): {"judge": "BREAKFALL" | "WEAPON" | "MOMENTUM" | "SPIN",
##              "min_sub": s (default 1 = nothing flagged), "need": true = it must have judged something (a fall, a swing...)}
## NOTHING IS MEASURED HERE: every number comes from BodyAssert.run, Check, RealismUI or JudgeSuite; this file only adds them up.
## THE SCORE (ours, a design choice, not a measured quantity): A = sum(w x pass) / sum(w) over the assertion lines, J = the share of
##   judge bars met (1 with none), score = 100 x A x (0.6 + 0.4 x J), rounded to a whole number. So a scene that does none of the
##   move scores 0 however clean its Check is (a still pose has no must-fix), every assertion met but the judges failed is 60, and
##   100 needs both. "solved" = every line and every bar passes. A scene of under 2 cards cannot be played: every line fails.
## COST: realism is a full judge pass (2-17 s a scene on this PC, measured 2026-10-23: punch template 1.8 s, walk template 16.5 s,
##   plus 6.7 s once per process for the timing coach's clip index); it runs ONLY for a task that has a realism bar.
## WHO IS GRADED: the hero (fighter 1, the scene file itself). With the second fighter active the hero is made active first (a
##   view change like picking a part: no undo step, no card changes), so the grade never depends on which fighter is being posed.
## DETERMINISTIC: no clock, no random; the same scene gives the same table (tests/bench_test.gd runs it twice in two processes).
class_name KineBench
extends RefCounted

const DIR := "res://bench/tasks"
const W_JUDGE := 0.4     # the share of the score the judge bars can take away (see THE SCORE)
const KINDS := ["strike", "kick", "weapon", "fall", "walk", "combo", "two-fighter"]
const JUDGE_FN := ["BREAKFALL", "WEAPON", "MOMENTUM", "SPIN"]

static var _tasks := []


## every task file, sorted by id; a malformed one is listed with its error (never dropped silently)
static func tasks(reload := false) -> Array:
	if not _tasks.is_empty() and not reload:
		return _tasks
	var out := []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	var names := Array(d.get_files()).filter(func(f): return String(f).ends_with(".json"))
	names.sort()
	for f in names:
		var t: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/" + String(f)))
		if not (t is Dictionary):
			out.append({"id": String(f).get_basename(), "error": "not a JSON object"})
			continue
		var why := problem(t)
		if why != "":
			t["error"] = why
		out.append(t)
	_tasks = out
	return out


static func find(id: String) -> Dictionary:
	for t in tasks():
		if String(t.get("id", "")) == id:
			return t
	return {}


## "" = a well-formed task; else what is wrong with it
static func problem(t: Dictionary) -> String:
	for k in ["id", "brief", "kind", "start", "asserts", "judges"]:
		if not t.has(k):
			return "no '%s'" % k
	if not String(t["kind"]) in KINDS:
		return "kind '%s' is not one of %s" % [t["kind"], KINDS]
	if not FileAccess.file_exists(AgentTools.res(String(t["start"]))):
		return "no start scene %s" % t["start"]
	for a in t["asserts"]:
		if not (a is Dictionary) or not a.has("line"):
			return "an assert is {\"line\": \"...\", \"w\": 1}"
		var q := BodyAssert.parse(String(a["line"]))
		if not q["ok"]:
			return "assert '%s' does not read: %s" % [a["line"], q["error"]]
	for j in bars(t):
		if j.has("judge") and not String(j["judge"]) in JUDGE_FN:
			return "judge '%s' is not one of %s" % [j["judge"], JUDGE_FN]
	return ""


## the task's judge bars as a flat list: [{"bar": "must_fix", "max"}, {"bar": "realism", "min"}, {"bar": "judge", "judge", "min_sub", "need"}]
static func bars(t: Dictionary) -> Array:
	var j: Dictionary = t.get("judges", {})
	var out := []
	if j.has("must_fix"):
		out.append({"bar": "must_fix", "max": int(j["must_fix"])})
	if j.has("realism"):
		out.append({"bar": "realism", "min": float(j["realism"])})
	for x in j.get("named", []):
		out.append({"bar": "judge", "judge": String(x["judge"]), "min_sub": float(x.get("min_sub", 1.0)), "need": bool(x.get("need", true))})
	return out


## the count of machine-checkable criteria: assertion lines that read + judge bars
static func criteria(t: Dictionary) -> int:
	var n := 0
	for a in t.get("asserts", []):
		if BodyAssert.parse(String(a["line"]))["ok"]:
			n += 1
	return n + bars(t).size()


## what an agent is given for a task: the brief, the start scene and every rule it will be graded by (no reference solution)
static func card(t: Dictionary) -> Dictionary:
	return {"id": t["id"], "kind": t["kind"], "brief": t["brief"], "start": t["start"], "notes": t.get("notes", ""),
		"asserts": t["asserts"].map(func(a): return {"line": a["line"], "w": float(a.get("w", 1.0))}),
		"judges": bars(t), "criteria": criteria(t),
		"scoring": "A = sum(w x pass) / sum(w) over the asserts; J = share of judge bars met; score = round(100 x A x (0.6 + 0.4 x J)); solved = all pass",
		"how": "open {path: start}, build the move (run / pose / ...), then bench {task: id, score: true} grades the live scene"}


## the judges' bars on the live hero scene -> [{"bar", ..., "value", "pass", "say"}]
static func _judge(m: Node, T: AgentTools, t: Dictionary) -> Array:
	var out := []
	var playable: bool = m.S.cards.size() >= 2
	for b in bars(t):
		var r: Dictionary = b.duplicate()
		r["pass"] = false
		if not playable:
			r["value"] = null
			r["say"] = "FAIL  %s: the scene has under 2 cards (nothing plays)" % _bar_name(b)
			out.append(r)
			continue
		match String(b["bar"]):
			"must_fix":
				var keep: bool = HumanLimits.on
				HumanLimits.on = false   # the default Check (see the header)
				var fs := T.findings()
				HumanLimits.on = keep
				var mf := fs.filter(func(f): return f["sev"] == "MUST FIX")
				r["value"] = mf.size()
				r["pass"] = mf.size() <= int(b["max"])
				r["rules"] = mf.map(func(f): return "%s @ %.2f s" % [f["rule"], float(f["t"])])
				r["say"] = "%s  Check: %d must-fix (bar <= %d)%s" % ["PASS" if r["pass"] else "FAIL", mf.size(), int(b["max"]),
					("" if mf.is_empty() else ": " + ", ".join(r["rules"].slice(0, 4)))]
			"realism":
				if int(m.tc_ui.db.get("n", 0)) == 0:
					m.tc_ui.db = MotionMatch.build()   # the timing coach's clip index, as scene_brief.gd builds it
				var rs: RealismUI = m.rs_ui
				rs.refresh()
				var sc := snappedf(float(rs.res["score"]), 0.01)
				r["value"] = sc
				r["pass"] = sc >= float(b["min"]) - 1e-9
				r["say"] = "%s  realism %.2f (bar >= %.0f)" % ["PASS" if r["pass"] else "FAIL", sc, float(b["min"])]
			"judge":
				var jr: Dictionary = _named(m, String(b["judge"]))
				var sub := float(jr["sub"])
				r["value"] = {"sub": snappedf(sub, 0.0001), "n": int(jr["n"]), "bad": int(jr["bad"]), "abstain": bool(jr["abstain"])}
				var judged := not bool(jr["abstain"])
				r["pass"] = (judged or not bool(b["need"])) and sub >= float(b["min_sub"]) - 1e-9
				var why := "nothing to judge (%s)" % jr["why"] if not judged else "%d judged, %d flagged, sub-score %.2f" % [int(jr["n"]), int(jr["bad"]), sub]
				if judged and int(jr["bad"]) > 0:
					why += ": " + String(jr["items"][0]["text"])
				r["say"] = "%s  %s judge: %s (bar: sub >= %.2f%s)" % ["PASS" if r["pass"] else "FAIL", b["judge"], why, float(b["min_sub"]), ", must judge something" if bool(b["need"]) else ""]
		out.append(r)
	return out


static func _bar_name(b: Dictionary) -> String:
	match String(b["bar"]):
		"must_fix": return "Check must-fix <= %d" % int(b["max"])
		"realism": return "realism >= %.0f" % float(b["min"])
	return "%s judge" % b.get("judge", "?")


## one I45 judge through JudgeSuite's own reduction (the body is put back: the judges pose it at other times)
static func _named(m: Node, jd: String) -> Dictionary:
	var keep: Dictionary = m.B.state()
	var r: Dictionary
	match jd:
		"BREAKFALL": r = JudgeSuite._breakfall(m)
		"WEAPON": r = JudgeSuite._weapon(m)
		"MOMENTUM": r = JudgeSuite._momentum(m)
		_: r = JudgeSuite._spin(m)
	m.B.set_state(keep)
	m.B.fk()
	return r


## GRADE the live scene (the hero) against task t -> the row the tables are made of
static func grade(m: Node, T: AgentTools, t: Dictionary) -> Dictionary:
	if m.has_method("_actor_go") and int(m.actor_on) != 0:
		m._actor_set(0)   # the hero is graded (see the header)
	var S: Scene = m.S
	var lines: Array = t["asserts"].map(func(a): return String(a["line"]))
	var ws: Array = t["asserts"].map(func(a): return float(a.get("w", 1.0)))
	var res := []
	if S.cards.size() >= 2:
		res = BodyAssert.run(S, m.B, lines)["results"]
	else:
		for l in lines:
			res.append({"line": l, "pass": false, "say": "FAIL  %s:  the scene has under 2 cards (nothing plays)" % l})
	var wsum := 0.0
	var wpass := 0.0
	var rows := []
	for i in lines.size():
		var x: Dictionary = res[i]
		wsum += float(ws[i])
		if bool(x["pass"]):
			wpass += float(ws[i])
		var row := {"line": lines[i], "w": float(ws[i]), "pass": bool(x["pass"]), "say": String(x.get("say", ""))}
		if x.has("miss"):
			row["miss"] = x["miss"]
		if x.has("time_miss"):
			row["time_miss"] = x["time_miss"]
		rows.append(row)
	var js := _judge(m, T, t)
	var jmet := js.filter(func(b): return b["pass"]).size()
	var A := wpass / wsum if wsum > 0.0 else 0.0
	var J := float(jmet) / float(js.size()) if not js.is_empty() else 1.0
	var exact := 100.0 * A * ((1.0 - W_JUDGE) + W_JUDGE * J)
	return {"task": t["id"], "kind": t["kind"], "score": roundi(exact), "score_exact": snappedf(exact, 0.01),
		"solved": rows.all(func(r): return r["pass"]) and js.all(func(b): return b["pass"]),
		"asserts_passed": rows.filter(func(r): return r["pass"]).size(), "asserts": rows.size(), "judges_passed": jmet, "judges": js.size(),
		"A": snappedf(A, 0.0001), "J": snappedf(J, 0.0001), "lines": rows, "bars": js, "cards": S.cards.size(), "length_s": snappedf(S.length(), 0.001)}


## the row of a task whose result scene is missing (or not a scene): score 0, every line and bar failed with the reason
static func missing(t: Dictionary, why: String) -> Dictionary:
	var rows: Array = t["asserts"].map(func(a): return {"line": String(a["line"]), "w": float(a.get("w", 1.0)), "pass": false,
		"say": "FAIL  %s:  %s" % [String(a["line"]), why]})
	var bs: Array = bars(t).map(func(b): return {"bar": b["bar"], "pass": false, "say": "FAIL  %s: %s" % [_bar_name(b), why]})
	return {"task": t["id"], "kind": t["kind"], "score": 0, "score_exact": 0.0, "solved": false, "asserts_passed": 0, "asserts": rows.size(),
		"judges_passed": 0, "judges": bs.size(), "A": 0.0, "J": 0.0, "lines": rows, "bars": bs, "cards": 0, "length_s": 0.0}


## THE TABLE of a run: markdown (one row a task, then the total) and the same rows as JSON
static func table_md(rows: Array, title: String) -> String:
	var s := "# Kine-Bench: %s\n\n| task | kind | score | asserts | judges | solved |\n|---|---|---:|---:|---:|---|\n" % title
	var tot := 0
	var solved := 0
	for r in rows:
		s += "| %s | %s | %d | %d / %d | %d / %d | %s |\n" % [r["task"], r["kind"], int(r["score"]), int(r["asserts_passed"]), int(r["asserts"]),
			int(r["judges_passed"]), int(r["judges"]), "yes" if r["solved"] else "no"]
		tot += int(r["score"])
		if r["solved"]:
			solved += 1
	s += "\n**%d tasks, mean score %.1f, %d solved.**\n" % [rows.size(), float(tot) / maxf(1.0, rows.size()), solved]
	for r in rows:
		s += "\n## %s (%d)\n" % [r["task"], int(r["score"])]
		for l in r["lines"]:
			s += "- %s\n" % l["say"]
		for b in r["bars"]:
			s += "- %s\n" % b["say"]
	return s


static func table_json(rows: Array, title: String) -> Dictionary:
	var tot := 0
	for r in rows:
		tot += int(r["score"])
	return {"bench": "kine-bench", "title": title, "tasks": rows.size(), "mean": snappedf(float(tot) / maxf(1.0, rows.size()), 0.1),
		"solved": rows.filter(func(r): return r["solved"]).size(), "rows": rows}


## a scene file opened on the app's body the way serve `open` opens it (main._load_scene, the card strip rebuilt, card 1 picked)
## WITHOUT the schema check first: docs/scene.schema.json does not list the "air" card key that the committed jump and run templates
## carry (VV1 flights), so serve `open` refuses those files ("'air' is not a property this file can have"). The bench's runner and
## test open result scenes here so a scene with a jump in it is graded, not refused. -> false when the file is missing or not JSON
static func open_scene(m: Node, path: String) -> bool:
	var probe: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not (probe is Dictionary):
		return false
	m._load_scene(path)
	m._rebuild_cards()
	m._card_pick(0)
	return true


## SERVE: bench {list: true} | {task: id} | {task: id, score: true}
static func serve(T: AgentTools, id: Variant, p: Dictionary) -> Dictionary:
	if bool(p.get("list", false)):
		return T._ok(id, {"tasks": tasks().map(func(t): return {"id": t["id"], "kind": t.get("kind", "?"), "brief": t.get("brief", ""),
			"criteria": criteria(t) if not t.has("error") else 0, "error": t.get("error", "")})})
	var tid := String(p.get("task", ""))
	var t := find(tid)
	if t.is_empty():
		return T._err(id, -32602, "bench needs {\"list\": true}, {\"task\": id} or {\"task\": id, \"score\": true}; no task '%s' (bench {list: true} lists them)" % tid)
	if t.has("error"):
		return T._err(id, -32000, "task %s is malformed: %s" % [tid, t["error"]])
	if not bool(p.get("score", false)):
		return T._ok(id, card(t))
	return T._ok(id, grade(T.m, T, t))
