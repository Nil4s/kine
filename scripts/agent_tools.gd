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
const METHODS := ["commands", "open", "new", "run", "pose", "state", "measure", "describe", "ask", "check", "diff", "validate", "save", "quit", "assert", "events", "where", "place", "facts", "brief", "dry", "text_view", "lint", "frame_data"]
## C06: the methods the MCP server advertises on top of METHODS. They are NOT in METHODS: its list is the "ready" line and the -32601 text of the
## byte-for-byte transcript (refs/agent/serve_transcript.jsonl), which tests/agent_tools_test.gd replays. tools/mcp/poser_mcp.py names each of these (advertised with --math / POSER_MCP_MATH=1)
const MCP_EXTRA := ["cancel_windows", "reactable", "throw_check", "lock_check", "impact_align", "hit_region", "body_collide", "disarm_check", "group_fight", "frame_facts", "look_facts", "nature", "part_warn", "part_facts", "part_assert", "part_build", "fits", "lightrig", "final_render", "blend_matrix", "texture_paint", "dyntopo", "effort_face", "pain_face", "anim_stack", "bake_reaction", "fix_impact", "bake_momentum", "curve_graph", "teach_chain", "teach_landing", "teach_stance", "sockets", "animtools"]
## MCPFAST: the CAD tools (scripts/build/mcp_cad.gd); advertised with --cad
const MCP_CAD := ["cad_part", "cad_asm", "check_fit", "bom", "eval_gd", "cad_reset"]

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
	# an exported build: the scenes/_wip that write_scene writes to is the user's folder (UserPaths.w), and the same rule holds there
	if UserPaths.exported():
		var mg := ProjectSettings.globalize_path(UserPaths.w(out)).replace("\\", "/").simplify_path().to_lower()
		var us := ProjectSettings.globalize_path(UserPaths.user_root()).replace("\\", "/").trim_suffix("/").to_lower() + "/scenes"
		if (mg == us or mg.begins_with(us + "/")) and not (mg == us + "/_wip" or mg.begins_with(us + "/_wip/")):
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
	elif tok.begins_with("root=") or tok.begins_with("put="):   # N008: the root (pelvis offset, m) / a joint with no contact stop
		err = PosePath.step_token(m, tok)   # (scripts/pose_path.gd); path_to_pose's steps carry them
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
			var all: Array = m._commands().map(func(c): return {"id": c["id"], "name": c["name"], "keys": c["keys"], "edits": c["edits"], "desc": c["desc"]})
			var fw := String(p.get("find", "")).strip_edges()
			return _ok(id, all if fw == "" else find_commands(all, fw))
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
		"part_roof":   # ITEM 226: a thin curved roof step (hip / gable / xieshan / pyramid / shed / flat, sag, corner lift, open top) on the part on screen; ONE undo step (scripts/build/part_roof.gd). Not in METHODS
			var prf := PartRoof.serve(m, p)
			return _ok(id, prf) if prf["ok"] else _err(id, -32602, String(prf["error"]))
		"part_build":   # 11-04 AI COST: a whole part from JSON steps in ONE call, or {append} only the new steps (scripts/build/part_build.gd). Not in METHODS
			var pb := PartBuild.serve(m, p)
			return _ok(id, pb) if pb["ok"] else _err(id, -32602, String(pb["error"]))
		"part_facts", "part_assert":
			# ITEM 220 MODELING VIEW WITH MATHS (scripts/part_facts.gd, scripts/part_assert.gd): the part as text, and one-line checks on it, the
			# way assert / state give the body. {part | path} or the part on screen. Not in METHODS (the transcript's ready line)
			var pt := PartAssert.serve(self, method, p)
			return _ok(id, pt["result"]) if pt["ok"] else _err(id, -32602, String(pt["error"]), {"grammar": pt["grammar"]} if pt.has("grammar") else null)
		"fits":   # G3: ISO 286 fits of the mating pairs and the stack-ups (nominal, worst case, RSS) as data: the numbers the Fits panel shows (scripts/build/dim_fit.gd). Not in METHODS
			if not p.has("assembly") and not p.has("path") and not McpCad.asm.is_empty():   # MCPFAST: the assembly built through cad_asm
				p = p.duplicate()
				p["assembly"] = McpCad.asm
			var fr := DimFit.serve(m, p)
			return _ok(id, fr["result"]) if fr["ok"] else _err(id, -32602, String(fr["error"]))
		"part_warn":
			# ITEM 221 WARNING LEVELS (scripts/build/part_warn.gd): the part's warnings at its level (off / look / print / engineering), the same list the
			# Part panel shows; {level}, {mute}, {unmute} edit the record in one undo step. Not in METHODS (the transcript's ready line)
			var pw := PartWarn.serve(self, p)
			return _ok(id, pw["result"]) if pw["ok"] else _err(id, -32602, String(pw["error"]))
		"dry":
			# N003: what run's steps WOULD do (parts moved, findings added / removed, score change, cards / keys touched), the
			# scene, body and undo put back byte for byte; file-writing steps refused: scripts/dry_run.gd
			return await DryRun.request(self, id, p)
		"frame_data":   # N080: frame data + opt-in hitstun / blockstun / advantage (scripts/frame_advantage.gd). Not in METHODS:
			# its -32601 message is in the byte-for-byte transcript (refs/agent/serve_transcript.jsonl)
			var fa := FrameAdvantage.serve(m, p)
			return _ok(id, fa["result"]) if fa["ok"] else _err(id, -32602, String(fa["error"]))
		"curve_graph":   # L84: tangent weights, buffer curves (snapshot / swap / compare) and curve modifiers on a joint's part keys (scripts/curve_graph_serve.gd). Not in METHODS
			var cgr := CurveGraphServe.serve(m, p)
			return _ok(id, cgr["result"]) if cgr["ok"] else _err(id, -32602, String(cgr["error"]))
		"sockets":   # N089: the five engine sockets (weapon_r, weapon_l, back_sheath, hip_holster_r, head_fx) placed from the anatomy of a preset body {preset?, mass?} (scripts/sockets_serve.gd). Not in METHODS
			var skr := SocketsServe.serve(m, p)
			return _ok(id, skr["result"]) if skr["ok"] else _err(id, -32602, String(skr["error"]))
		"animtools":   # L87: onion frames, breakdown, ripple retime, keying set {op, ...} (scripts/anim_tools.gd). Not in METHODS
			var atr := AnimTools.serve(m, p)
			return _ok(id, atr["result"]) if atr["ok"] else _err(id, -32602, String(atr["error"]))
		"dyntopo":   # L52: one dynamic-topology step (split long / collapse short edges under the brush) on a test sphere, with the band numbers {radius?, detail?, levels?} (scripts/dyntopo_serve.gd). Not in METHODS
			var dtr := DyntopoServe.serve(m, p)
			return _ok(id, dtr["result"]) if dtr["ok"] else _err(id, -32602, String(dtr["error"]))
		"texture_paint":   # L53 TPAINT: a screen-space brush stamp onto a UV-mapped shape {shape?, x?, y?, radius?, size?, color?, strength?, hardness?, pad?, w?, h?} (scripts/tpaint_serve.gd). Not in METHODS
			var tpr := TPaintServe.serve(m, p)
			return _ok(id, tpr) if tpr["ok"] else _err(id, -32602, String(tpr["error"]))
		"anim_stack":   # L79: animation layers (bone masks, add / over, weight, mute) and NLA strips (scale, repeat, blend curves, mute) {op, index?, ...}; each edit ONE undo step (scripts/anim_stack.gd). Not in METHODS
			var asr := AnimStack.serve(m, p)
			return _ok(id, asr["result"]) if asr["ok"] else _err(id, -32602, String(asr["error"]))
		"blend_matrix":   # N084: every clip-to-clip crossfade of a moveset checked for limit breaks, self-clash and foot skate {clips?, blend_s?, a?, b?, full?, top?} (scripts/blend_matrix_serve.gd). Not in METHODS
			var bmr := BlendMatrixServe.serve(m, p)
			return _ok(id, bmr["result"]) if bmr["ok"] else _err(id, -32602, String(bmr["error"]))
		"reactable":   # N082 wired (L11): can a viewer SEE each strike coming in time to react? {clip?, frame?, latency_ms?, fps?} (scripts/reactable_serve.gd). Not in METHODS
			var rxr := ReactableServe.serve(m, p)
			return _ok(id, rxr["result"]) if rxr["ok"] else _err(id, -32602, String(rxr["error"]))
		"cancel_windows":   # N081: the frames where the body is balanced and slow enough to start another move {clip?, frame?, fps?, v_max?, h_max?} (scripts/cancel_windows.gd). Not in METHODS
			var cwr := CancelWindows.serve(m, p)
			return _ok(id, cwr["result"]) if cwr["ok"] else _err(id, -32602, String(cwr["error"]))
		"throw_check":   # N040 wired (L34): does the throw work? {clip?, fps?, thrower?} (scripts/throw_serve.gd). Not in METHODS
			var tcr := ThrowServe.serve(m, p)
			return _ok(id, tcr["result"]) if tcr["ok"] else _err(id, -32602, String(tcr["error"]))
		"impact_align", "hit_region", "body_collide":   # L72: N034 impact alignment, N042 hit reaction by region, N046 body collision (scripts/fight2_serve.gd). Not in METHODS
			var f2r := Fight2Serve.serve(String(method), m, p)
			return _ok(id, f2r["result"]) if f2r["ok"] else _err(id, -32602, String(f2r["error"]))
		"disarm_check", "group_fight":   # L74: N045 disarm truth, N048 one vs many (scripts/fight3_serve.gd). Not in METHODS
			var f3r := Fight3Serve.serve(String(method), m, p)
			return _ok(id, f3r["result"]) if f3r["ok"] else _err(id, -32602, String(f3r["error"]))
		"effort_face", "pain_face":   # L75: I13 effort face from torque {clip?, fps?}, I14 pain face from hit force {impulse, contact?, length?, fps?} (scripts/face_pain.gd). Not in METHODS
			var fpr := FacePain.serve(String(method), m, p)
			return _ok(id, fpr["result"]) if fpr["ok"] else _err(id, -32602, String(fpr["error"]))
		"bake_reaction", "fix_impact", "bake_momentum":   # L76: the fight maths baked as cards, one undo step (scripts/fight_bake_serve.gd). Not in METHODS
			var fbr := FightBakeServe.serve(String(method), m, p)
			return _ok(id, fbr["result"]) if fbr["ok"] else _err(id, -32602, String(fbr["error"]))
		"lock_check":   # N041 wired: does the lock reach his limit, or go past it? {clip?, fps?, locker?} (scripts/lock_serve.gd). Not in METHODS
			var lcr := LockServe.serve(m, p)
			return _ok(id, lcr["result"]) if lcr["ok"] else _err(id, -32602, String(lcr["error"]))
		"lint":   # N018: a clip made anywhere, judged on Kine's body (scripts/clip_lint.gd); the live scene is put back
			var lr := ClipLint.lint(m, String(p.get("path", "")))
			return _ok(id, lr) if lr["ok"] else _err(id, -32602, String(lr["error"]), lr)
		"explain_conflict":
			# N006 CONFLICT EXPLAINER (scripts/conflict_explain.gd): the smallest clashing set of wishes + the cost to free each; scene untouched
			var cx := ConflictExplain.serve(m, p)
			return _ok(id, cx) if cx["ok"] else _err(id, -32602, cx["error"], {"grammar": cx["grammar"]} if cx.has("grammar") else null)
		"ornament":   # s227: an ornament step on the part (scripts/build/part_ornament.gd). Not in METHODS (the transcript ready line)
			var orr := PartOrnament.serve(m, p)
			return _ok(id, orr["result"]) if orr["ok"] else _err(id, -32602, String(orr["error"]))


		"temple_light":   # item 232: sky, sun by time of day, haze, GI, exposure, camera by numbers (scripts/build/temple_light.gd). Not in METHODS
			var tl := TempleLight.serve(m, p)
			return _ok(id, tl) if bool(tl["ok"]) else _err(id, -32602, String(tl["error"]))
		"frame_facts":   # item 243: the silhouette's px box, share, cut, centre, top/bottom rows per piece (scripts/build/frame_facts.gd). Not in METHODS
			var ffr := FrameFacts.serve(m, p)
			return _ok(id, ffr) if bool(ffr["ok"]) else _err(id, -32602, String(ffr["error"]))
		"frame_to":   # item 243: the camera that puts the pieces' silhouette at the asked share / rows; applied only with apply: true
			var ftr := FrameFacts.serve_to(m, p)
			return _ok(id, ftr) if bool(ftr["ok"]) else _err(id, -32602, String(ftr["error"]))
		"final_shot":   # item 232: the camera as a PNG with no UI, at a size ({out, w, h, camera?}). Not in METHODS
			var fs: Dictionary = await TempleLight.serve_final(m, p)
			return _ok(id, fs) if bool(fs["ok"]) else _err(id, -32000, String(fs["text"]))
		"checkpoint", "restore", "checkpoints", "edit_step", "insert_step", "delete_step":   # item 244: named checkpoints + replay from one step (scripts/build/part_replay_calls.gd). Not in METHODS
			var prc := PartReplayCalls.serve(m, method, p)
			return _ok(id, prc) if bool(prc["ok"]) else _err(id, -32602, String(prc["error"]))


		"look_facts":   # item 242: numbers for how the final picture LOOKS per piece / kind / nature item (scripts/build/look_facts.gd). Not in METHODS
			var lf: Dictionary = await LookFacts.serve(m, p)
			return _ok(id, lf) if bool(lf["ok"]) else _err(id, -32602, String(lf["error"]))
		"lightrig":   # L48: light-rig look, sky map (rotation, intensity), character-only lights; {} = the facts (scripts/light_rig.gd serve). Not in METHODS
			var lr := LightRig.serve(m, p)
			return _ok(id, lr["result"]) if bool(lr["ok"]) else _err(id, -32602, String(lr["error"]))
		"final_render":   # L49 RENDER1: the render preset draft | final | final_hq (GI, DOF, sub-frame motion blur, accumulation) from the shot camera: {preset, w, h, first, count, out, subframes, accum, shutter}. Not in METHODS
			var frp := String(p.get("preset", "final_hq"))
			if not FinalRender.PRESETS.has(frp):
				return _err(id, -32602, "final_render preset must be one of %s (got '%s')" % [FinalRender.PRESETS.keys(), frp])
			var fro := {"preset": frp, "w": int(p.get("w", 1920)), "h": int(p.get("h", 1080)), "first": int(p.get("first", 0))}
			for k in ["count", "subframes", "accum"]:
				if p.has(k):
					fro[k] = int(p[k])
			if p.has("shutter"):
				fro["shutter"] = float(p["shutter"])
			var frr: Dictionary = await m._render_shots(String(p.get("out", ShotRender.ROOT)), "", fro)
			if frr.is_empty():
				return _err(id, -32000, "final_render refused: the scene needs shots and at least 2 cards")
			return _ok(id, {"dir": frr["dir"], "frames": frr["frames"], "mp4": frr["mp4"], "preset": frp, "w": fro["w"], "h": fro["h"]})
		"nature":   # FRIDAY 225: trees, hedges, shrubs, grass, flowers, paths, scatter (scripts/build/nature_agent.gd); not in METHODS (the transcript's ready line)
			var na := NatureAgent.serve(m, p)
			return _ok(id, na) if bool(na["ok"]) else _err(id, -32602, String(na["error"]))
		"cad_part", "cad_asm", "check_fit", "bom", "eval_gd", "cad_reset":   # MCPFAST: not in METHODS (the transcript's ready line)
			var mc := McpCad.serve(m, method, p)
			return _ok(id, mc["result"]) if bool(mc["ok"]) else _err(id, -32602, String(mc["error"]))
		"look4d", "sweep":   # L1 AI-COST: the zoomable digest and the one-summary sweep (scripts/build/mcp_cad.gd); not in METHODS
			var lm: Dictionary = await McpCad.serve_async(m, method, p)
			return _ok(id, lm["result"]) if bool(lm["ok"]) else _err(id, -32602, String(lm["error"]))
		"quit":
			return _ok(id, {"bye": true})
		"events":
			# N017 EVENT QUERY: when is X true, measured on the played body (scripts/event_query.gd); unknown phrase -> the known list
			var ev: Dictionary = await EventQuery.run(m, p)
			return _ok(id, ev) if ev["ok"] else _err(id, -32602, ev["error"], {"known": ev["known"]} if ev.has("known") else null)
		"explain":   # N091 EXPLAIN THIS MOTION (scripts/explain_motion.gd): phases, power, read, one thing to try; scene untouched. Not in METHODS
			var xm := ExplainMotion.serve(m, p)
			return _ok(id, xm) if xm["ok"] else _err(id, -32602, String(xm["error"]))
		"teach_chain", "teach_landing", "teach_stance":   # TEACHING (scripts/teach.gd): why the strike / landing / stance fails, from the clip's own numbers; {apply?: true} = the first fix as one undo step. Not in METHODS
			var th := Teach.serve(m, method.trim_prefix("teach_"), p)
			return _ok(id, th) if th["ok"] else _err(id, -32602, String(th["error"]))
		"brief":   # N011: the scene in under N tokens (scripts/scene_brief.gd)
			return await SceneBrief.serve(self, id, p)
		"text_view":
			# N001: front + side ASCII stick figures and one paragraph (scripts/text_view.gd); {t | frame, fps | card}
			var tv: Dictionary = await TextView.on_main(m, p)
			return _ok(id, tv) if tv["ok"] else _err(id, -32602, tv["error"])
		"spec":
			# N004 SPEC TO MOTION: a structured move spec -> a clip that passes its assertions, or what it could not meet and why
			# (scripts/spec_motion.gd); a dry plan unless apply: true (then ONE undo step). Not in METHODS (the transcript's ready line)
			var sm := SpecMotion.serve(m, p)
			return _ok(id, sm["result"]) if sm["ok"] else _err(id, -32602, String(sm.get("error", "bad spec")), {"grammar": sm["grammar"]} if sm.has("grammar") else null)
		"range":
			# N013 SAFE RANGE SWEEP: the values of one joint axis that keep EVERY condition true (scripts/range_sweep.gd); not in METHODS
			var rs := RangeSweep.run(m, p)
			return _ok(id, rs) if rs["ok"] else _err(id, -32602, rs["error"], {"grammar": rs["grammar"]} if rs.has("grammar") else null)
		"knobs":   # N025 MOVE KNOBS (scripts/move_knobs.gd): {card, read: true} the values; {card, set: {...}} one undo step
			var kn := MoveKnobs.serve(m, p)
			return _ok(id, kn) if kn["ok"] else _err(id, -32602, String(kn["error"]))
		"try":   # N019 TRY N WAYS: variants (or one change swept) each dry-run, scored, ranked; apply = the pick as one undo step (scripts/try_n.gd)
			return await TryN.request(self, id, p)
		"path_to_pose":   # N008: from the body now to a named / described pose, as `run` steps that keep limits, planted feet and
			# the body whole on the way (scripts/pose_path.gd); a dry plan unless apply: true. Not in METHODS (the transcript's ready line)
			return await PosePath.serve(self, id, p)
		"recognize":   # N016: which strike the body does and how far from the textbook form (scripts/move_recognizer.gd)
			var rr: Dictionary = await MoveRecognizer.serve(m, p)
			return _ok(id, rr) if rr["ok"] else _err(id, -32602, rr["error"])
		"limits":
			# N028 COUPLED LIMITS: a joint's effective bend range given the other leg joints (two-joint muscles), with the why and
			# the source (scripts/coupled_limits.gd); not in METHODS (the transcript's ready line)
			var cl := CoupledLimits.serve(m, p)
			return _ok(id, cl) if cl["ok"] else _err(id, -32602, cl["error"])
		"material":   # s223 MATERIAL WORDS (scripts/material_words.gd): {words, base?} -> the spec ("dark oak", "red lacquer, a bit worn"), unknown words listed; {library: true} lists the library. Not in METHODS
			if p.get("library", false) == true:
				return _ok(id, {"library": MaterialMaker.library_ids(), "colours": MaterialWords.colour_names().size()})
			var mw := MaterialWords.parse(String(p.get("words", "")), p.get("base", {}) if p.get("base") is Dictionary else {})
			if not bool(mw["ok"]):
				return _err(id, -32602, "material needs {\"words\": \"dark oak\"}: a material or a colour (not known: %s)" % ", ".join(mw["unknown"]), mw)
			mw["describe"] = MaterialWords.describe(mw["spec"])
			return _ok(id, mw)
		"who_could":   # N027: the minimum body that could do the clip / card / span, per capacity (scripts/who_could.gd); not in METHODS
			var wc := WhoCould.serve(m, p)
			return _ok(id, wc) if wc["ok"] else _err(id, -32602, wc["error"])
		"fix_until":   # N005: the fixes in order of predicted gain until the saved assertions pass and the score clears a bar (scripts/fix_loop.gd)
			return await FixLoop.serve(self, id, p)
		"hit_harder":   # N065 HIT HARDER (scripts/hit_harder.gd): {card, dry?, allow_retime?}; one undo step; not in METHODS (the transcript)
			var hh := HitHarder.serve(m, p)
			return _ok(id, hh) if hh["ok"] else _err(id, -32602, String(hh["error"]))
		"bench":   # N024 KINE-BENCH: {list} | {task} (brief, start, rules) | {task, score} grades the live scene (scripts/kine_bench.gd).
			# Not in METHODS: its -32601 message is in the byte-for-byte transcript (refs/agent/serve_transcript.jsonl)
			return KineBench.serve(self, id, p)
	return _err(id, -32601, "no method '%s': the methods are %s (the head of tools/poser_cli.gd)" % [method, ", ".join(METHODS)])


const FIND_MAX := 25

## AI COST (11-04): commands {"find": "mirror pose"}: only the commands whose id / name / keys / desc hold EVERY word
## (or, when none does, ANY word), best first, at most FIND_MAX. The whole list is 500+ commands (70-100 KB of JSON,
## 20-30k tokens) that a model pays for again on every later turn; one search is usually a few hundred tokens.
static func find_commands(all: Array, words: String) -> Array:
	var ws := words.to_lower().split(" ", false)
	var scored := []
	for c in all:
		var idn := (String(c["id"]) + " " + String(c["name"])).to_lower()
		var hay := idn + " " + (String(c.get("keys", "")) + " " + String(c.get("desc", ""))).to_lower()
		var hit := 0
		var in_name := 0
		for w in ws:
			if hay.contains(w):
				hit += 1
				if idn.contains(w):
					in_name += 1
		if hit > 0:
			scored.append([hit, in_name, c])
	var full := scored.filter(func(s): return s[0] == ws.size())
	var pick := full if not full.is_empty() else scored
	pick.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] > b[1]))
	return pick.slice(0, FIND_MAX).map(func(s): return s[2])
