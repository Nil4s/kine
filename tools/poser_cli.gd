## POSER FROM THE COMMAND LINE (round 8, GATES O5): for agents and scripts. The real poser (main.tscn) is built
## headless, so every command runs the SAME code as its button, key or search entry (main._commands(), the registry).
##   G=.../Godot_v4.7.2-stable_win64_console.exe
##   $G --headless --path . -s tools/poser_cli.gd -- commands
##   $G --headless --path . -s tools/poser_cli.gd -- describe scenes/combo3.json
##   $G --headless --path . -s tools/poser_cli.gd -- check scenes/combo3.json [--json]
##   $G --headless --path . -s tools/poser_cli.gd -- check_all [scenes] --html C:/Temp/check.html   (every scene, one report)
##   $G --headless --path . -s tools/poser_cli.gd -- diff scenes/combo3.json scenes/_wip/combo3_b.json   (cards by name, joints > 0.5 deg)
##   $G --headless --path . -s tools/poser_cli.gd -- validate scenes/combo3.json     (docs/scene.schema.json; tools/validate.gd)
##   $G --headless --path . -s tools/poser_cli.gd -- run scenes/combo3.json card=3 sel=lowerarm_r snap_the_part_to_90 update --out scenes/_wip/x.json
##   $G --headless --path . -s tools/poser_cli.gd -- serve      (a LIVE session: JSON-RPC 2.0 on stdin / stdout, below)
## run's steps, in order (stops at the first that fails):
##   <id>              a registry command (see `commands`); e.g. mirror_the_whole_pose, faster_10, weapon_bo_staff
##   card=N            pick card N (1 = the first, as the poser numbers them): its pose goes on the body
##   sel=<joint>       pick a part (upperarm_r, lowerarm_l, head, pelvis, ...; `describe` lists them)
##   set=<joint>:b,s,t that joint's bend, side, twist in degrees (within its limits; it stops at contact)
##   update | add | delete    the card buttons: put the body on the picked card / add the body as a new card after it /
##                            delete the picked card
##   name=<text>       name the picked card (one undo step)
##   pose="raise the right arm 90, bend the left elbow 45"   words to a pose (scripts/pose_words.gd), one undo step
##   fix=K             run Check, then the K-th finding's Fix (1 = the first listed)
##   retime=A-B:pct    cards A to B (1 = the first) play at pct % (the move into each and its hold; 150 = slower)
##   undo | redo
## Output: readable lines, then ONE JSON line last (it starts with {"ok": ...}). With --json only the JSON line.
## Writes: only `run ... --out <path>` / serve's `save`, and only into scenes/_wip/ or outside the project; never Nick's
## scenes/, poses/ or data/ (a registry command that writes them, save_pose / save_scene, is refused: use --out).
##
## SERVE (round 13, GATES T4, item 88): one request per line in, one response per line out, JSON-RPC 2.0, on ONE live
## session that keeps its scene, body, picked card and undo between requests. It starts EMPTY and prints a "ready"
## notification first. Methods (params by name):
##   commands                      the registry (id, name, keys, edits, desc)
##   open {path} | new             load a scene / start an empty one
##   run {steps: [...]}            run's steps above, in order; stops at the first that fails (that is an error)
##   pose {text}                   words to a pose; the result says what each joint reached
##   measure {t | frame, fps, what}  numbers a blind agent needs, each with its unit (docs/AGENT_MATH.md): what = a list
##                                 of "distance A B", "angle A B C", "height A", "speed A", "clearance", "com",
##                                 "balance"; A = a joint
##                                 name, weapon_tip or weapon_knob
##   state {t | frame, fps}        the body: every joint's bend / side / twist, the offset, the weapon, and where 17 parts
##                                 ARE (points, m); at a moment of the scene if t or frame is given (the same every run)
##   describe                      the scene: cards, times, settings
##   check                         the findings, as `check --json`
##   diff {path} | diff {a, b}     what the live scene changed from a file (file -> live), or a -> b
##   validate {path?}              a file, or the live scene, against docs/scene.schema.json
##   save {out}                    write the live scene (scenes/_wip/ or outside the project only)
##   quit
## Errors are JSON-RPC errors: -32700 not JSON, -32600 not a request, -32601 no such method (lists them), -32602 bad
## params (says what to send), -32000 a step or a save failed (data.steps has what ran). Every message says what to do.
extends SceneTree

const REFUSE := {"save_pose": "writes poses/: use --out for the scene instead", "save_scene": "writes scenes/: use --out <path>",
	"play_pause": "plays in real time: nothing to see headless", "help": "the help panel: nothing to see headless",
	"big_view_hide_the_panels": "a window layout: nothing to see headless"}
## the parts `state` gives the place of
const POINTS := ["head", "pelvis", "spine_03", "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "hand_l", "hand_r",
	"thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r", "ball_l", "ball_r"]
const METHODS := ["commands", "open", "new", "run", "pose", "state", "measure", "describe", "check", "diff", "validate", "save", "quit"]

var m: Node
var quiet := false
var reg := {}


func say(t: String) -> void:
	if not quiet:
		print(t)


func done(d: Dictionary) -> void:
	print(JSON.stringify(d))
	quit(0 if d.get("ok", false) else 1)


func res(p: String) -> String:
	if p.begins_with("res://") or p.is_absolute_path():
		return p
	return "res://" + p


func open_scene(p: String) -> bool:
	var r := res(p)
	if not FileAccess.file_exists(r):
		done({"ok": false, "error": "no such scene: " + p})
		return false
	m._load_scene(r)
	m._rebuild_cards()
	return true


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


func describe_now(talk: bool) -> Dictionary:
	var S: Scene = m.S
	var ts: Array = S.times()
	var cs := []
	if talk:
		say("SCENE %s: %d cards, %.2f s, %d fps%s%s%s" % [S.name, S.cards.size(), S.length(), S.fps, ", spline" if S.spline else "", ", moving holds" if S.moving_holds else "", ", on the floor" if S.on_floor else ""])
	for i in S.cards.size():
		var c: Dictionary = S.cards[i]
		var cd := {"n": i + 1, "name": c["name"], "move_s": snappedf(S.move_time(i), 0.001), "hold_s": float(c["hold"]),
			"arrive_s": snappedf(ts[i][1], 0.001), "leave_s": snappedf(ts[i][2], 0.001)}
		var w: Dictionary = c["pose"].get("weapon", {})
		if not w.is_empty():
			cd["weapon"] = "%s in %s" % [w.get("kind", "?"), w.get("hand", "free") if w.get("hand", "") != "" else "free"]
		cs.append(cd)
		if talk:
			say("  card %2d %-22s arrive %5.2f s  move %4.2f  hold %4.2f  %s" % [i + 1, c["name"], cd["arrive_s"], cd["move_s"], cd["hold_s"], cd.get("weapon", "")])
	return {"scene": S.name, "length_s": snappedf(S.length(), 0.001), "fps": S.fps,
		"settings": {"natural": S.natural, "spline": S.spline, "on_floor": S.on_floor, "floor_body": S.floor_body, "pin": S.pin, "moving_holds": S.moving_holds},
		"cards": cs, "selected_card": m.sel_card + 1, "selected_part": m.sel}


func _init() -> void:
	var a: Array = Array(OS.get_cmdline_user_args())
	quiet = "--json" in a
	a = a.filter(func(x): return x != "--json")
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	for c in m._commands():
		reg[c["id"]] = c
	var verb: String = a[0] if a.size() > 0 else ""
	match verb:
		"commands":
			var cs := []
			for c in m._commands():
				cs.append({"id": c["id"], "name": c["name"], "keys": c["keys"], "edits": c["edits"], "desc": c["desc"]})
				say("%-38s %-8s %s  %s" % [c["id"], c["keys"], "EDIT" if c["edits"] else "    ", c["desc"]])
			done({"ok": true, "commands": cs})
		"describe":
			if a.size() < 2 or not open_scene(a[1]):
				if a.size() < 2:
					done({"ok": false, "error": "describe <scene.json>"})
				return
			var d := describe_now(true)
			d.erase("selected_card")
			d.erase("selected_part")
			var fs := findings()
			say("CHECK: %d findings, %d must fix" % [fs.size(), fs.filter(func(f): return f["sev"] == "MUST FIX").size()])
			d["ok"] = true
			d["findings"] = fs.size()
			d["must_fix"] = fs.filter(func(f): return f["sev"] == "MUST FIX").size()
			d["joints"] = Body.BODY
			done(d)
		"check":
			if a.size() < 2 or not open_scene(a[1]):
				if a.size() < 2:
					done({"ok": false, "error": "check <scene.json> [--json]"})
				return
			var fs := findings()
			for f in fs:
				say("%2d %-8s %-12s %5.2f s  card %d '%s'  %s%s" % [f["n"], f["sev"], f["rule"], f["t"], f["card"], f["card_name"], f["msg"], ("   [fix: %s]" % f["fix"]) if f["fix"] != "" else ""])
			var must := fs.filter(func(f): return f["sev"] == "MUST FIX").size()
			say("CHECK %s: %d findings, %d must fix" % ["clean" if fs.is_empty() else "done", fs.size(), must])
			done({"ok": true, "scene": m.S.name, "clean": fs.is_empty(), "must_fix": must, "findings": fs})
		"check_all":
			check_all(a)
		"diff":
			if a.size() < 3 or not FileAccess.file_exists(res(a[1])) or not FileAccess.file_exists(res(a[2])):
				done({"ok": false, "error": "diff <a.json> <b.json>  (both scene files that exist)"})
				return
			var d := SceneDiff.files(res(a[1]), res(a[2]))
			for l in SceneDiff.lines(d):
				say(l)
			d["ok"] = true
			done(d)
		"validate":
			if a.size() < 2:
				done({"ok": false, "error": "validate <scene-or-pose.json>  (against docs/scene.schema.json)"})
				return
			var es := Validate.file(res(a[1]))
			for e in es:
				say("%s: %s" % [e["path"], e["msg"]])
			say("VALID" if es.is_empty() else "%d problem(s)" % es.size())
			done({"ok": es.is_empty(), "file": a[1], "errors": es})
		"run":
			await run(a)
		"serve":
			await serve()
		_:
			say("verbs: commands | describe <scene> | check <scene> [--json] | diff <a> <b> | validate <file> | run <scene> <step> ... [--out <path>] | serve   (head of tools/poser_cli.gd)")
			done({"ok": false, "error": "unknown verb '%s'" % verb})


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
	await process_frame
	m.playing = false
	var st := {"step": tok, "ok": err == "", "body_changed": body_json() != b0, "cards_changed": cards_json() != c0,
		"undo_steps": m.undo.size() - u0, "said": String(m.ui_status.text) if m.ui_status != null else ""}
	if err != "":
		st["error"] = err
	return st


## CHECK EVERY SCENE (round 18, GATES Y1, UPGRADES #70): Check over every *.json directly in the folder (scenes/ by
## default), one self-contained HTML report (rule totals across the scenes, then each scene's findings) and the JSON
## line {"ok", "scenes": [{"file", "scene", "cards", "findings", "must_fix", "rules": {rule: n}}], "rules": {rule: n}}.
## A scene of under two cards is listed as skipped (Check needs two). Writes only the report, and only where --out may
func check_all(a: Array) -> void:
	var out := ""
	var i := a.find("--html")
	if i >= 0:
		if i + 1 >= a.size():
			done({"ok": false, "error": "--html needs a path"})
			return
		out = res(a[i + 1])
		a = a.slice(0, i) + a.slice(i + 2)
		var why := out_refused(out)
		if why != "":
			done({"ok": false, "error": why.replace("the output", "--html")})
			return
	var folder: String = res(a[1] if a.size() > 1 else "scenes").trim_suffix("/")
	var d := DirAccess.open(folder)
	if d == null:
		done({"ok": false, "error": "no such folder: " + folder})
		return
	var files := Array(d.get_files()).filter(func(f): return String(f).ends_with(".json"))
	files.sort()
	var rows := []
	var tot := {}
	var per := {}   # file -> its findings
	for f in files:
		var path: String = folder + "/" + f
		m._load_scene(path)
		m._rebuild_cards()
		var r := {"file": f, "scene": m.S.name, "cards": m.S.cards.size()}
		if m.S.cards.size() < 2:
			r["skipped"] = "fewer than 2 cards"
			rows.append(r)
			continue
		var fs := findings()
		per[f] = fs
		var by := {}
		for x in fs:
			by[x["rule"]] = int(by.get(x["rule"], 0)) + 1
			tot[x["rule"]] = int(tot.get(x["rule"], 0)) + 1
		r["findings"] = fs.size()
		r["must_fix"] = fs.filter(func(x): return x["sev"] == "MUST FIX").size()
		r["rules"] = by
		rows.append(r)
		say("%-28s %3d cards  %3d findings  %2d must fix  %s" % [f, r["cards"], fs.size(), r["must_fix"], by])
	var n_f := 0
	for r in rows:
		n_f += int(r.get("findings", 0))
	say("CHECK_ALL: %d scenes, %d findings, rules %s" % [rows.size(), n_f, tot])
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f == null:
			done({"ok": false, "error": "cannot write " + out})
			return
		f.store_string(check_html(folder, rows, per, tot))
		f.close()
		say("report: " + ProjectSettings.globalize_path(out))
	done({"ok": true, "folder": folder, "scenes": rows, "findings": n_f, "rules": tot, "html": ProjectSettings.globalize_path(out) if out != "" else ""})


## the report: plain HTML, its CSS inline, every name and message escaped (a scene called "<b>" is text)
func check_html(folder: String, rows: Array, per: Dictionary, tot: Dictionary) -> String:
	var e := func(x) -> String: return String(str(x)).xml_escape(true)
	var rules: Array = tot.keys()
	rules.sort()
	var h := PackedStringArray()
	h.append("<!doctype html><html><head><meta charset=\"utf-8\"><title>Poser check: %s</title><style>" % e.call(folder.get_file()))
	h.append("body{font:14px system-ui,sans-serif;margin:24px;color:#222;background:#fafafa}table{border-collapse:collapse;margin:8px 0 24px}")
	h.append("td,th{border:1px solid #ccc;padding:3px 8px;text-align:left}th{background:#eee}.must{color:#b00;font-weight:600}.zero{color:#999}")
	h.append("h2{margin-top:32px;font-size:17px}</style></head><body>")
	h.append("<h1>Check: every scene in %s</h1><p>%d scenes, %d findings.</p>" % [e.call(folder), rows.size(), per.values().reduce(func(acc, v): return acc + v.size(), 0)])
	h.append("<table id=\"totals\"><tr><th>scene</th><th>cards</th><th>findings</th><th>must fix</th>")
	for r in rules:
		h.append("<th>%s</th>" % e.call(r))
	h.append("</tr>")
	for r in rows:
		h.append("<tr data-file=\"%s\"><td>%s</td><td>%d</td>" % [e.call(r["file"]), e.call(r["scene"]), r["cards"]])
		if r.has("skipped"):
			h.append("<td colspan=\"%d\" class=\"zero\">skipped: %s</td></tr>" % [2 + rules.size(), e.call(r["skipped"])])
			continue
		h.append("<td class=\"n\">%d</td><td class=\"%s\">%d</td>" % [r["findings"], "must" if r["must_fix"] > 0 else "zero", r["must_fix"]])
		for k in rules:
			var n: int = r["rules"].get(k, 0)
			h.append("<td class=\"%s\">%d</td>" % ["zero" if n == 0 else "", n])
		h.append("</tr>")
	h.append("<tr><th>all</th><th></th><th>%d</th><th></th>" % per.values().reduce(func(acc, v): return acc + v.size(), 0))
	for k in rules:
		h.append("<th class=\"total\" data-rule=\"%s\">%d</th>" % [e.call(k), tot[k]])
	h.append("</tr></table>")
	for r in rows:
		if not per.has(r["file"]) or per[r["file"]].is_empty():
			continue
		h.append("<h2>%s <small>(%s)</small></h2><table class=\"scene\" data-file=\"%s\"><tr><th>#</th><th>sev</th><th>rule</th><th>time</th><th>card</th><th>what</th><th>fix</th></tr>" % [e.call(r["scene"]), e.call(r["file"]), e.call(r["file"])])
		for x in per[r["file"]]:
			h.append("<tr class=\"f\"><td>%d</td><td class=\"%s\">%s</td><td>%s</td><td>%.2f s</td><td>%d %s</td><td>%s</td><td>%s</td></tr>" % [x["n"],
				"must" if x["sev"] == "MUST FIX" else "", e.call(x["sev"]), e.call(x["rule"]), x["t"], x["card"], e.call(x["card_name"]), e.call(x["msg"]), e.call(x["fix"])])
		h.append("</table>")
	h.append("</body></html>
")
	return "".join(h)


func run(a: Array) -> void:
	var out := ""
	var i := a.find("--out")
	if i >= 0:
		if i + 1 >= a.size():
			done({"ok": false, "error": "--out needs a path"})
			return
		out = res(a[i + 1])
		a = a.slice(0, i) + a.slice(i + 2)
		var why := out_refused(out)
		if why != "":
			done({"ok": false, "error": why.replace("the output", "--out")})
			return
	if a.size() < 2 or not open_scene(a[1]):
		if a.size() < 2:
			done({"ok": false, "error": "run <scene.json> <step> ... [--out <path>]"})
		return
	m._card_pick(0)
	m.undo.clear()
	var steps := []
	var ok := true
	for tok: String in a.slice(2):
		var st := await step(tok)
		steps.append(st)
		say("%-4s %-34s body %-5s cards %-5s %s" % ["ok" if st["ok"] else "FAIL", tok, st["body_changed"], st["cards_changed"], st.get("error", st["said"])])
		if not st["ok"]:
			ok = false
			break
	var d := {"ok": ok, "scene": m.S.name, "cards": m.S.cards.size(), "length_s": snappedf(m.S.length(), 0.001), "steps": steps}
	if ok and out != "":
		if m.S.cards.is_empty():
			d["ok"] = false
			d["error"] = "the scene is empty: nothing written"
		else:
			write_scene(out, "poser_cli run %s" % " ".join(a.slice(1)))
			d["out"] = out
			say("wrote %s (%d cards, %.2f s)" % [out, m.S.cards.size(), m.S.length()])
	done(d)


## ---- SERVE: a live session over stdin / stdout ----

func serve() -> void:
	m.S = Scene.new()
	m.scene_path = ""
	m._rebuild_cards()
	m.undo.clear()
	print(JSON.stringify({"jsonrpc": "2.0", "method": "ready", "params": {"methods": METHODS, "cards": 0}}))
	var held := ""   # the end of a chunk that was not a whole line yet
	while true:
		var chunk := OS.read_string_from_stdin(1 << 20)
		if chunk == "":   # stdin closed
			if held.strip_edges() != "":
				print(JSON.stringify(await handle(held)))
			break
		var lines := (held + chunk).split("\n")
		held = ""
		for k in lines.size():
			var line := lines[k].strip_edges()
			if line == "":
				continue
			# Godot hands stdin over in chunks, one per write, with the last newline taken off. Only a chunk as big as a
			# pipe's buffer can end mid-line, so only then does an unparseable last piece wait for the rest (a short bad
			# line is answered at once: holding it would hang the client, which waits for the answer)
			if k == lines.size() - 1 and chunk.length() >= 4096 and JSON.parse_string(line) == null:
				held = line
				continue
			var resp := await handle(line)
			print(JSON.stringify(resp))
			if resp.get("result", {}) is Dictionary and resp.get("result", {}).get("bye", false):
				quit(0)
				return
	quit(0)


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
	var t := float(p["frame"]) / fps if p.has("frame") else float(p.get("t", m.playhead))
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
	match q["method"]:
		"commands":
			return _ok(id, m._commands().map(func(c): return {"id": c["id"], "name": c["name"], "keys": c["keys"], "edits": c["edits"], "desc": c["desc"]}))
		"new":
			m.S = Scene.new()
			m.scene_path = ""
			m.sel_card = -1
			m._rebuild_cards()
			return _ok(id, describe_now(false))
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
			return _ok(id, describe_now(false))
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
			return await measure(id, p)
		"describe":
			return _ok(id, describe_now(false))
		"check":
			if m.S.cards.size() < 2:
				return _err(id, -32000, "check needs a scene of two cards or more: run {\"steps\": [\"add\", \"add\"]} or open one")
			var fs := findings()
			return _ok(id, {"clean": fs.is_empty(), "must_fix": fs.filter(func(f): return f["sev"] == "MUST FIX").size(), "findings": fs})
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
		"quit":
			return _ok(id, {"bye": true})
	return _err(id, -32601, "no method '%s': the methods are %s (the head of tools/poser_cli.gd)" % [q["method"], ", ".join(METHODS)])
