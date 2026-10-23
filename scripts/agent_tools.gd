## THE AGENT'S TOOLS (round 46, GATES BB0): what `poser_cli serve` answered (round 13, T4; measure round 15, V2), moved
## here unchanged so the CLI, the MCP server (through serve) and the app's AI box run the SAME code on a live poser (the
## main node: its scene, body, picked card, undo). Methods, params and errors: the head of tools/poser_cli.gd.
## refs/agent/serve_transcript.jsonl is serve's answer to a fixed request script recorded BEFORE the move;
## tests/agent_tools_test.gd replays it byte for byte.
class_name AgentTools
extends RefCounted

const REFUSE := {"save_pose": "writes poses/: use --out for the scene instead", "save_scene": "writes scenes/: use --out <path>",
	"play_pause": "plays in real time: nothing to see headless", "help": "the help panel: nothing to see headless",
	"big_view_hide_the_panels": "a window layout: nothing to see headless"}
## the parts `state` gives the place of
const POINTS := ["head", "pelvis", "spine_03", "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "hand_l", "hand_r",
	"thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r", "ball_l", "ball_r"]
const METHODS := ["commands", "open", "new", "run", "pose", "state", "measure", "describe", "ask", "check", "diff", "validate", "save", "quit"]

var m: Node
var reg := {}


func _init(main: Node) -> void:
	m = main
	for c in m._commands():
		reg[c["id"]] = c


static func res(p: String) -> String:
	if p.begins_with("res://") or p.is_absolute_path():
		return p
	return "res://" + p


func body_json() -> String:
	return JSON.stringify(m.B.state())


func cards_json() -> String:
	return JSON.stringify(m.S.cards)


func findings() -> Array:
	m._check()
	var out := []
	for i in m.findings.size():
		var f: Dictionary = m.findings[i]
		var ci := mini(int(f["card"]), m.S.cards.size() - 1)
		out.append({"n": i + 1, "sev": "MUST FIX" if f["sev"] == "FAIL" else "look", "rule": f["rule"], "t": snappedf(f["t"], 0.01),
			"card": ci + 1, "card_name": m.S.cards[ci]["name"], "msg": f["msg"], "fix": Fixer.label(f, m.S)})
	return out


## "" = may be written here; else why not
func out_refused(out: String) -> String:
	# simplified FIRST (round 18, GATES Y1): "scenes/_wip/../combo3.json" began with scenes/_wip/ and wrote Nick's scene
	var g := ProjectSettings.globalize_path(out).replace("\\", "/").simplify_path()
	var proj := ProjectSettings.globalize_path("res://").replace("\\", "/")
	if g.begins_with(proj) and not g.begins_with(proj + "scenes/_wip/"):
		return "the output must be in scenes/_wip/ or outside the project (Nick's scenes/, poses/, data/ are never written): " + out
	return ""


## the live scene, as its file would be (the body is put back: to_dict samples the scene through it)
func scene_dict() -> Dictionary:
	var keep: Dictionary = m.B.state()
	var sd: Dictionary = m.S.to_dict(m.B)
	m.B.set_state(keep)
	return sd


func write_scene(out: String, plan: String) -> void:
	var sd := scene_dict()
	sd["scene"] = out.get_file().get_basename()
	sd["plan"] = plan
	m._write(out, sd)


func describe() -> Dictionary:
	var S: Scene = m.S
	var ts: Array = S.times()
	var cs := []
	for i in S.cards.size():
		var c: Dictionary = S.cards[i]
		var cd := {"n": i + 1, "name": c["name"], "move_s": snappedf(S.move_time(i), 0.001), "hold_s": float(c["hold"]),
			"arrive_s": snappedf(ts[i][1], 0.001), "leave_s": snappedf(ts[i][2], 0.001)}
		var w: Dictionary = c["pose"].get("weapon", {})
		if not w.is_empty():
			cd["weapon"] = "%s in %s" % [w.get("kind", "?"), w.get("hand", "free") if w.get("hand", "") != "" else "free"]
		cs.append(cd)
	return {"scene": S.name, "length_s": snappedf(S.length(), 0.001), "fps": S.fps,
		"settings": {"natural": S.natural, "spline": S.spline, "on_floor": S.on_floor, "floor_body": S.floor_body, "pin": S.pin, "moving_holds": S.moving_holds},
		"cards": cs, "selected_card": m.sel_card + 1, "selected_part": m.sel}


## ONE step on the live session -> {"step", "ok", "body_changed", "cards_changed", "undo_steps", "said", ["error"]}
func step(tok: String) -> Dictionary:
	var b0 := body_json()
	var c0 := cards_json()
	var u0: int = m.undo.size()
	m._say("")
	var err := ""
	if reg.has(tok):
		if REFUSE.has(tok):
			err = "refused: " + REFUSE[tok]
		else:
			await (reg[tok]["run"] as Callable).call()
	elif tok.begins_with("card="):
		var n := int(tok.substr(5))
		if n < 1 or n > m.S.cards.size():
			err = "no card %d (the scene has %d)" % [n, m.S.cards.size()]
		else:
			m._card_pick(n - 1)
	elif tok.begins_with("sel="):
		var j: String = tok.substr(4)
		if not (j in Body.BODY or j in Body.WEAPON):
			err = "no part '%s' (describe lists them)" % j
		else:
			m.sel = j
	elif tok.begins_with("set="):
		var p: PackedStringArray = tok.substr(4).split(":")
		var v: PackedStringArray = p[1].split(",") if p.size() == 2 else PackedStringArray()
		if p.size() != 2 or v.size() != 3 or not p[0] in Body.BODY:
			err = "set=<joint>:bend,side,twist  e.g. set=lowerarm_r:90,0,0"
		else:
			m.sel = p[0]
			m._do(func(): m.B.set_ang_safe(p[0], Vector3(float(v[0]), float(v[1]), float(v[2]))))
	elif tok == "update" or tok == "delete":
		if m.sel_card < 0:
			err = "pick a card first (card=N)"
		elif tok == "update":
			m._card_update(m.sel_card)
		else:
			m._card_del(m.sel_card)
	elif tok.begins_with("name="):
		if m.sel_card < 0 or tok.substr(5).strip_edges() == "":
			err = "name=<text> names the picked card: pick one first (card=N), and give it a name"
		else:
			m._card_rename(m.sel_card, tok.substr(5))
	elif tok.begins_with("pose="):
		var pr: Dictionary = m._pose_words(tok.substr(5))
		if not pr["ok"]:
			err = pr["error"]
	elif tok.begins_with("physics="):
		if m._import_physics(tok.substr(8)) == "":
			err = String(m.ui_status.text)
	elif tok == "add":
		m._card_add()
	elif tok == "undo":
		m._undo()
	elif tok == "redo":
		m._redo()
	elif tok.begins_with("retime="):
		var rp: PackedStringArray = tok.substr(7).split(":")
		var ab: PackedStringArray = rp[0].split("-") if rp.size() == 2 else PackedStringArray()
		if ab.size() != 2 or not ab[0].is_valid_int() or not ab[1].is_valid_int() or not rp[1].is_valid_float():
			err = "retime=A-B:pct  e.g. retime=3-6:150 (cards 3 to 6 at 150 %%, slower)"
		else:
			err = m.retime(int(ab[0]) - 1, int(ab[1]) - 1, float(rp[1]))
	elif tok.begins_with("fix="):
		var fs := findings()
		var k := int(tok.substr(4))
		if k < 1 or k > fs.size():
			err = "no finding %d (Check lists %d)" % [k, fs.size()]
		elif fs[k - 1]["fix"] == "":
			err = "finding %d (%s) has no automatic fix" % [k, fs[k - 1]["rule"]]
		else:
			await m._fix(m.findings[k - 1])
	else:
		err = "unknown step '%s' (commands lists the ids)" % tok
	await m.get_tree().process_frame
	m.playing = false
	var st := {"step": tok, "ok": err == "", "body_changed": body_json() != b0, "cards_changed": cards_json() != c0,
		"undo_steps": m.undo.size() - u0, "said": String(m.ui_status.text) if m.ui_status != null else ""}
	if err != "":
		st["error"] = err
	return st


func _err(id: Variant, code: int, msg: String, data: Variant = null) -> Dictionary:
	var e := {"code": code, "message": msg}
	if data != null:
		e["data"] = data
	return {"jsonrpc": "2.0", "id": id, "error": e}


func _ok(id: Variant, result: Variant) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "result": result}


## a part's place now: a joint, or a point of the weapon
func _at(part: String) -> Variant:
	if part == "weapon_tip" or part == "weapon_knob":
		return m.B.wep_point(m.B.wep_len if part == "weapon_tip" else 0.0) if m.B.wep_on else null
	return m.B.P[part] if m.B.P.has(part) else null


## MEASURE (round 15, GATES V2): the numbers a blind agent would otherwise eyeball, at one moment of what plays.
## Formulas in docs/AGENT_MATH.md; tests/py/measure_check.py checks each against its own computation from `state`
func measure(id: Variant, p: Dictionary) -> Dictionary:
	var what: Variant = p.get("what")
	if not (what is Array) or what.is_empty() or not what.all(func(w): return w is String):
		return _err(id, -32602, "measure needs {\"what\": [\"distance hand_r head\", \"angle upperarm_r lowerarm_r hand_r\", \"height head\", \"speed hand_r\", \"clearance\"], \"t\": seconds}")
	if m.S.cards.size() < 2:
		return _err(id, -32602, "measure needs a scene of 2+ cards: open one or add cards first")
	var fps := float(p.get("fps", m.S.fps))
	var t := float(p["frame"]) / fps if p.has("frame") and not (p["frame"] is String) else float(p.get("t", m.playhead))   # N007: frame "body" is not a frame number
	await m.dummy_settle()
	var ps: Scene = m._ps()
	var L := ps.length()
	var out := []
	for w: String in what:
		var a := w.split(" ", false)
		var kind := a[0] if a.size() > 0 else ""
		var need := {"distance": 3, "angle": 4, "height": 2, "speed": 2, "clearance": 1, "com": 1, "balance": 1}
		if not need.has(kind) or a.size() != need[kind]:
			return _err(id, -32602, "'%s': say one of distance A B / angle A B C / height A / speed A / clearance / com / balance" % w)
		ps.apply(m.B, t)
		var pts := []
		for k in range(1, a.size()):
			var q: Variant = _at(a[k])
			if q == null:
				return _err(id, -32602, "'%s' is not a part (a joint name like hand_r, or weapon_tip / weapon_knob with a weapon on)" % a[k])
			pts.append(q)
		match kind:
			"distance":
				out.append({"what": w, "value": snappedf((pts[0] - pts[1]).length(), 0.0001), "unit": "m"})
			"height":
				out.append({"what": w, "value": snappedf(pts[0].y, 0.0001), "unit": "m"})
			"angle":
				var u: Vector3 = pts[0] - pts[1]
				var v: Vector3 = pts[2] - pts[1]
				out.append({"what": w, "value": snappedf(rad_to_deg(u.angle_to(v)), 0.01), "unit": "deg"})
			"speed":
				var h := 1.0 / fps
				var t0 := maxf(t - h, 0.0)
				var t1 := minf(t + h, L)
				ps.apply(m.B, t0)
				var p0: Vector3 = _at(a[1])
				ps.apply(m.B, t1)
				var p1: Vector3 = _at(a[1])
				out.append({"what": w, "value": snappedf((p1 - p0).length() / maxf(t1 - t0, 1e-9), 0.001), "unit": "m/s",
					"over": [snappedf(t0, 0.0001), snappedf(t1, 0.0001)]})
			"com":
				var c := Balance.com(m.B)
				out.append({"what": w, "value": [snappedf(c.x, 0.0001), snappedf(c.y, 0.0001), snappedf(c.z, 0.0001)], "unit": "m"})
			"balance":
				var b := Balance.read(m.B)
				out.append({"what": w, "value": snappedf(b["margin"], 0.0001) if b["down"].size() > 0 else null, "unit": "m",
					"feet_down": b["down"].map(func(sd): return "left" if sd == "_l" else "right"),
					"note": "the centre of mass's floor point to the edge of the feet: + inside, - past them (null: no foot down)"})
			"clearance":
				if not m.B.wep_on or not m.dummy_on:
					return _err(id, -32602, "clearance needs a weapon in hand and the dummy on (run [\"dummy\"] to turn it on)")
				var best := INF
				var at := ""
				for wc in Body.WEAPON:
					var c: Array = m.B.cap(wc)
					for part in Dummy.ZONES:
						var d: Array = m.T.cap(part)
						var g: float = Body.seg_seg(c[0], c[1], d[0], d[1]) - float(m.B.rad[wc]) - float(m.T.D.rad[part])
						if g < best:
							best = g
							at = part
				out.append({"what": w, "value": snappedf(best, 0.0001), "unit": "m", "part": at, "inside": best < 0.0})
	ps.apply(m.B, t)
	m.playhead = t
	if p.get("frame") is String and p["frame"] == "body":   # N007: each part also in the body's own words (scripts/body_frame.gd)
		BodyFrame.annotate(m, out)
	return _ok(id, {"t": snappedf(t, 0.0001), "plays": "landed on the dummy" if ps != m.S else "the cards as made", "measures": out})


func handle(line: String) -> Dictionary:
	var j := JSON.new()
	if j.parse(line) != OK:
		return _err(null, -32700, "not JSON (%s at line %d): send one JSON-RPC request per line, e.g. {\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"describe\"}" % [j.get_error_message(), j.get_error_line()])
	var q: Variant = j.data
	if not (q is Dictionary) or not q.has("method") or not (q["method"] is String):
		return _err(q.get("id") if q is Dictionary else null, -32600, "not a request: send {\"jsonrpc\":\"2.0\",\"id\":N,\"method\":\"...\",\"params\":{...}}")
	var id: Variant = q.get("id")
	var p: Variant = q.get("params", {})
	if not (p is Dictionary):
		return _err(id, -32602, "params must be an object (by name), e.g. {\"path\": \"scenes/combo3.json\"}")
	return await request(id, q["method"], p)


## one request, already parsed: the JSON-RPC response as a Dictionary ({"result"} or {"error"}). The app's AI box calls
## this straight (no JSON text in between); serve and the MCP server reach it through handle
func request(id: Variant, method: String, p: Dictionary) -> Dictionary:
	match method:
		"commands":
			return _ok(id, m._commands().map(func(c): return {"id": c["id"], "name": c["name"], "keys": c["keys"], "edits": c["edits"], "desc": c["desc"]}))
		"new":
			m.S = Scene.new()
			m.scene_path = ""
			m.sel_card = -1
			m._rebuild_cards()
			return _ok(id, describe())
		"open":
			var path: String = p.get("path", "")
			if path == "" or not FileAccess.file_exists(res(path)):
				return _err(id, -32602, "open needs {\"path\": a scene file that exists} (got '%s')" % path)
			var es := Validate.file(res(path))
			if not es.is_empty():
				return _err(id, -32602, "%s is not a valid scene: %s %s (validate lists them all)" % [path, es[0]["path"], es[0]["msg"]], es)
			m._load_scene(res(path))
			m._rebuild_cards()
			m._card_pick(0)
			return _ok(id, describe())
		"run":
			var steps: Variant = p.get("steps")
			if not (steps is Array) or steps.is_empty() or not steps.all(func(s): return s is String):
				return _err(id, -32602, "run needs {\"steps\": [\"card=1\", \"pose=raise the right arm 90\", \"update\", ...]} (the steps at the head of tools/poser_cli.gd)")
			var out := []
			for s: String in steps:
				var st := await step(s)
				out.append(st)
				if not st["ok"]:
					return _err(id, -32000, "step %d of %d failed: %s" % [out.size(), steps.size(), st["error"]], {"steps": out})
			return _ok(id, {"steps": out, "cards": m.S.cards.size(), "length_s": snappedf(m.S.length(), 0.001)})
		"pose":
			var text: String = p.get("text", "")
			if text == "":
				return _err(id, -32602, "pose needs {\"text\": \"raise the right arm 90, bend the left elbow 45\"}")
			var r: Dictionary = m._pose_words(text)
			if not r["ok"]:
				return _err(id, -32602, r["error"])
			return _ok(id, r)
		"state":
			# a moment of the scene (round 14, U3): {"t": s} or {"frame": n, "fps": f} (fps: the scene's own); none = the
			# body as it stands. Waits for the dummy's measurement first: what PLAYS is the answer, the same every run
			var at: Variant = p.get("t")
			if p.has("frame"):
				at = float(p["frame"]) / float(p.get("fps", m.S.fps))
			if at != null:
				if not (at is float or at is int) or m.S.cards.size() < 2:
					return _err(id, -32602, "state {\"t\": seconds} or {\"frame\": n, \"fps\": f} needs a number and a scene of 2+ cards: open one first")
				await m.dummy_settle()
				m.playhead = float(at)
				m._ps().apply(m.B, float(at))
			var js := {}
			for jn in Body.BODY:
				var v: Vector3 = m.B.ang[jn]
				js[jn] = {"bend": snappedf(v.x, 0.01), "side": snappedf(v.y, 0.01), "twist": snappedf(v.z, 0.01)}
			var pd: Dictionary = m.B.to_dict()
			var pts := {}   # where the parts ARE (m, the body's space: y up, +z his front): what a blind agent can't see
			for jn in POINTS:
				var w: Vector3 = m.B.P[jn]
				pts[jn] = [snappedf(w.x, 0.0001), snappedf(w.y, 0.0001), snappedf(w.z, 0.0001)]
			return _ok(id, {"joints": js, "offset": pd["offset"], "weapon": pd["weapon"], "contacts": pd["contacts"], "points": pts,
				"t": snappedf(m.playhead, 0.0001), "plays": "landed on the dummy" if m._ps() != m.S else "the cards as made",
				"selected_part": m.sel, "selected_card": m.sel_card + 1})
		"measure":
			var mr := await measure(id, p)
			return Trust.label("measure", mr) if p.get("trust", false) == true else mr   # N020: trust labels, opt-in
		"describe":
			if p.has("joint"):
				var dj := WhatIf.describe_joint(m, String(p["joint"]))
				return _ok(id, dj) if dj["ok"] else _err(id, -32602, dj["error"])
			return _ok(id, describe())
		"ask":
			# R10: what would this angle do (reach, collisions, balance), the scene untouched: scripts/what_if.gd
			var aq := WhatIf.ask(m, String(p.get("text", "")))
			return _ok(id, aq) if aq["ok"] else _err(id, -32602, aq["error"])
		"check":
			if m.S.cards.size() < 2:
				return _err(id, -32000, "check needs a scene of two cards or more: run {\"steps\": [\"add\", \"add\"]} or open one")
			var fs := findings()
			var cr := _ok(id, {"clean": fs.is_empty(), "must_fix": fs.filter(func(f): return f["sev"] == "MUST FIX").size(), "findings": fs})
			return Trust.label("check", cr) if p.get("trust", false) == true else cr   # N020: trust labels, opt-in
		"diff":
			var b: String = p.get("b", p.get("path", ""))
			if b == "" or not FileAccess.file_exists(res(b)):
				return _err(id, -32602, "diff needs {\"path\": a scene file} (against the live scene) or {\"a\": file, \"b\": file}")
			# {path}: what the live scene changed FROM the file (file -> live); {a, b}: a -> b
			var fb: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(res(b)))
			var d: Dictionary
			if p.has("a"):
				if not FileAccess.file_exists(res(p["a"])):
					return _err(id, -32602, "no such file: %s" % p["a"])
				d = SceneDiff.diff(JSON.parse_string(FileAccess.get_file_as_string(res(p["a"]))), fb)
			else:
				d = SceneDiff.diff(fb, scene_dict())
			d["lines"] = SceneDiff.lines(d)
			return _ok(id, d)
		"validate":
			var es: Array = Validate.file(res(p["path"])) if p.has("path") else Validate.data(scene_dict())
			return _ok(id, {"valid": es.is_empty(), "errors": es})
		"save":
			var o: String = p.get("out", "")
			if o == "":
				return _err(id, -32602, "save needs {\"out\": \"scenes/_wip/name.json\"} (or a path outside the project)")
			o = res(o)
			var why := out_refused(o)
			if why != "":
				return _err(id, -32602, why)
			if m.S.cards.is_empty():
				return _err(id, -32000, "the scene is empty: nothing written. Add cards first: run {\"steps\": [\"add\"]}")
			write_scene(o, "poser_cli serve")
			return _ok(id, {"out": o, "cards": m.S.cards.size(), "length_s": snappedf(m.S.length(), 0.001)})
		"assert":
			# N002 BODY ASSERTIONS (scripts/body_assert.gd): {lines: [...]} checks them on the scene as made; {save: true} also keeps
			# the lines that read in the scene's "asserts" (Check re-runs them); {clear: true} drops the saved ones; no lines = the saved
			if m.S.cards.size() < 2:
				return _err(id, -32602, "assert needs a scene of 2+ cards: open one or add cards first")
			if bool(p.get("clear", false)):
				m.S.asserts = []
			var al: Variant = p.get("lines", m.S.asserts)
			if not (al is Array) or not al.all(func(s): return s is String):
				return _err(id, -32602, "assert needs {\"lines\": [\"left foot planted 0-0.4 s\", ...]}", {"grammar": BodyAssert.GRAMMAR})
			var ar := BodyAssert.run(m.S, m.B, al)
			if bool(p.get("save", false)):
				for x in ar["results"]:
					if x["ok"] and not String(x["line"]).strip_edges() in m.S.asserts:
						m.S.asserts.append(String(x["line"]).strip_edges())
			ar["saved"] = m.S.asserts.duplicate()
			if ar["unread"] > 0:
				ar["grammar"] = BodyAssert.GRAMMAR
			return _ok(id, ar)
		"where", "place":
			# N007 BODY-FRAME NUMBERS (scripts/body_frame.gd): a point in the body's words + numbers / such words to a point.
			# Not in METHODS: its -32601 message is in the byte-for-byte transcript (refs/agent/serve_transcript.jsonl)
			var bf := BodyFrame.serve(m, method, p)
			return _ok(id, bf) if bf["ok"] else _err(id, -32602, bf["error"])
		"facts":
			# N022 HUMAN FACTS: cited human numbers by keywords (scripts/human_facts.gd); not in METHODS (the transcript's ready line)
			var fr := HumanFacts.serve(p)
			return _ok(id, fr) if not fr.is_empty() else _err(id, -32602, "facts needs {\"q\": \"how fast is a real jab?\"}, {\"list\": true} or {\"registry\": true}")
		"quit":
			return _ok(id, {"bye": true})
		"events":
			# N017 EVENT QUERY: when is X true, measured on the played body (scripts/event_query.gd); unknown phrase -> the known list
			var ev: Dictionary = await EventQuery.run(m, p)
			return _ok(id, ev) if ev["ok"] else _err(id, -32602, ev["error"], {"known": ev["known"]} if ev.has("known") else null)
		"brief":   # N011: the scene in under N tokens (scripts/scene_brief.gd)
			return await SceneBrief.serve(self, id, p)
	return _err(id, -32601, "no method '%s': the methods are %s (the head of tools/poser_cli.gd)" % [method, ", ".join(METHODS)])
