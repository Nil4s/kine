## POSER FROM THE COMMAND LINE (round 8, GATES O5): for agents and scripts. The real poser (main.tscn) is built
## headless, so every command runs the SAME code as its button, key or search entry (main._commands(), the registry).
##   G=.../Godot_v4.7.2-stable_win64_console.exe
##   $G --headless --path . -s tools/poser_cli.gd -- commands
##   $G --headless --path . -s tools/poser_cli.gd -- describe scenes/combo3.json
##   $G --headless --path . -s tools/poser_cli.gd -- describe joint elbow_r      (the joint's frame in words + its limits)
##   $G --headless --path . -s tools/poser_cli.gd -- ask scenes/combo3.json [card=N] "joint=elbow_r axis=flex value=90; joint=upperarm_r axis=bend value=60"
##        (what that would do to the pose on card N (default 1); nothing is changed or written; `ask - "..."` = the default body)
##   $G --headless --path . -s tools/poser_cli.gd -- check scenes/combo3.json [--json]
##   $G --headless --path . -s tools/poser_cli.gd -- check_all [scenes] --html C:/Temp/check.html   (every scene, one report)
##   $G --headless --path . -s tools/poser_cli.gd -- diff scenes/combo3.json scenes/_wip/combo3_b.json   (cards by name, joints > 0.5 deg)
##   $G --headless --path . -s tools/poser_cli.gd -- validate scenes/combo3.json     (docs/scene.schema.json; tools/validate.gd)
##   $G --headless --path . -s tools/poser_cli.gd -- run scenes/combo3.json card=3 sel=lowerarm_r snap_the_part_to_90 update --out scenes/_wip/x.json
##   $G --headless --path . -s tools/poser_cli.gd -- assert scenes/combo3.json "left foot planted 0-0.4 s" "COM inside the feet all clip"
##        (N002 body assertions, scripts/body_assert.gd: pass / fail per line, the worst miss in cm / deg / m/s and its frame;
##        no lines = the scene's saved "asserts"; an unread line gets the grammar back)
##   $G --headless --path . -s tools/poser_cli.gd -- events scenes/combo3.json "when does the left foot leave the floor" [fighter=2] [fps=60]
##   $G --headless --path . -s tools/poser_cli.gd -- explain_conflict scenes/combo3.json "right fist touches fighter 2 chin" "both feet planted" [t=0.6] [card=N]
##        (N006: the smallest set of those wishes that clash at one moment, and the cost to free each; nothing is changed)
##   $G --headless --path . -s tools/poser_cli.gd -- facts "how fast is a real jab?"   (or: facts list; N022, cited numbers)
##   $G --headless --path . -s tools/poser_cli.gd -- brief scenes/combo3.json [--tokens 400]   (N011: the scene for an agent's context)
##   $G --headless --path . -s tools/poser_cli.gd -- run scenes/combo3.json card=3 mirror_the_whole_pose --dry [--no-score]   (N003: what it WOULD do; nothing changed)
##   $G --headless --path . -s tools/poser_cli.gd -- try scenes/combo3.json retime=3-3:{pct} --sweep pct=80,90,100,110,120 [--no-score] [--apply best|N --out <path>]
##        or  try scenes/combo3.json slower_10 --or faster_10 --or ease_linear   (N019: each variant dry-run, scored, ranked)
##   $G --headless --path . -s tools/poser_cli.gd -- lint C:/any/clip.bvh|.glb|.gltf|.fbx [--json]   (N018: judge a clip made anywhere)
##   $G --headless --path . -s tools/poser_cli.gd -- textview scenes/combo3.json [card=N]   (N001: the pose as ASCII + words)
##   $G --headless --path . -s tools/poser_cli.gd -- knobs templates/punch.json card=3 [reach_pct=95 guard_cm=-5 ...] [--out scenes/_wip/x.json]
##        (N025 move knobs: read, or set and re-solve; scripts/move_knobs.gd)
##   $G --headless --path . -s tools/poser_cli.gd -- path_to_pose scenes/combo3.json|- "salute"|"raise the right leg 90" [--max N] [--json]
##        (N008: the run steps from card 1 (or the default body, -) to that pose; nothing is changed; scripts/pose_path.gd)
##   $G --headless --path . -s tools/poser_cli.gd -- recognize scenes/thrust.json [card=N] [t0=S] [t1=S] [fighter=N]   (N016: which strike)
##   $G --headless --path . -s tools/poser_cli.gd -- fixuntil scenes/combo3.json [--bar 70] [--steps 10] --out scenes/_wip/x.json   (N005; --dry: the plan only)
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
##   physics=<file.bvh>  import a tools/physics hit reaction as a NEW scene in scenes/_wip (R15)
##   undo | redo
##   root=x,y,z        the body's root (pelvis offset, m), one undo step (N008: path_to_pose's steps carry it)
##   put=<joint>:b,s,t like set= for any joint (fingers too), limits kept but NOT stopped at a contact (N008)
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
##   pose {text}                   words to a pose; the result says what each joint reached. Or the floor contacts
##                                 ("kneeling on the right knee, left foot flat", "push-up plank"; N015 scripts/support_pose.gd):
##                                 a balanced pose on them, each contact's gap and weight share, or why not
##   measure {t | frame, fps, what}  numbers a blind agent needs, each with its unit (docs/AGENT_MATH.md): what = a list
##                                 of "distance A B", "angle A B C", "height A", "speed A", "clearance", "com",
##                                 "balance"; A = a joint
##                                 name, weapon_tip or weapon_knob; frame: "body" adds each part in the body's words (N007)
##   where {point | joint, who, of}  N007 (scripts/body_frame.gd): a point in words + cm, e.g. "15 cm in front of the
##                                 sternum, 3 cm above chin height, 10 cm toward his left"; of = "opponent": his landmarks
##   place {text, who}             those words back to a point (m, the space state gives); "at the opponent's chin" too
##   state {t | frame, fps}        the body: every joint's bend / side / twist, the offset, the weapon, and where 17 parts
##                                 ARE (points, m); at a moment of the scene if t or frame is given (the same every run)
##   describe                      the scene: cards, times, settings; {joint: "elbow_r"} = that joint's frame in words + limits
##   ask {text}                    WHAT WOULD THIS ANGLE DO (R10), the scene untouched: text = "joint=elbow_r axis=flex value=90"
##                                 (more changes after ;): the hands' / feet's new world positions and reach %, the nearest
##                                 parts and their gap, the limit margin, balance (inside / outside, cm), the weapon tip
##   check                         the findings, as `check --json`
##   assert {lines, save?, clear?}  N002 body assertions ("left foot planted 0-0.4 s"): pass / fail and the worst miss
##                                 per line; save keeps them in the scene (Check re-runs them); no lines = the saved ones
##   check {trust: true} | measure {..., trust: true}   + a "trust" per finding / measure: MEASURED (source), HEURISTIC or
##                                 UNVERIFIED, with the bars behind it (N020, scripts/trust.gd)
##   facts {q} | {list: true} | {registry: true}   cited human numbers ("how fast is a real jab?"): value, unit, range,
##                                 source, trust; "no cited number" + the nearest topics when none (N022, human_facts.gd)
##   diff {path} | diff {a, b}     what the live scene changed from a file (file -> live), or a -> b
##   validate {path?}              a file, or the live scene, against docs/scene.schema.json
##   events {q, fighter?, fps?}    N017: WHEN is it true, measured on the played body: q = "right foot leaves the floor",
##                                 "guard down for at least 0.2 s", "right fist fastest", "fighters touch" -> spans / an instant
##                                 in s and frames (scripts/event_query.gd); an unknown phrase lists the known ones
##   dry {steps, score?}           N003: what run's steps WOULD do, nothing changed (scripts/dry_run.gd): parts moved, findings
##                                 added / removed, realism score change, cards / keys touched; file-writing steps refused
##   frame_data {fps, frames, exchange, hit_clip, block_clip, moves}  N080 (scripts/frame_advantage.gd): startup / active /
##                                 recovery at 60 fps; opt-in "exchange": hitstun, blockstun, on_hit / on_block (+ = attacker
##                                 first), punishable, vs the other fighter on the stage or reaction clips (first card = impact)
##   lint {path}                   N018: a .bvh/.glb/.gltf/.fbx made anywhere, on Kine's body (scripts/clip_lint.gd); live scene kept
##   range {joint, axis, conditions, card? | t?, step?, from?, to?, joint2?, axis2?}   N013: the values of that axis that keep
##                                 EVERY condition true ("balance", "reach right fist to 0.25,1.35,0.45 within 2 cm", "limits 5",
##                                 an N002 line): intervals in deg with what bounds each end; joint2 = a pass / fail map
##                                 (scripts/range_sweep.gd; CLI: range <scene|-> [card=N] [t=S] [step=D] <joint> <axis> "<cond>" ...)
##   limits {joint, other_angles?}  N028: the joint's bend range now (table, healthy adult, trained) given the other leg joints
##                                 ({"calf_r": 0} or {"knee": 0}; missing = the body as it stands), each two-joint muscle with its why + source
##   explain_conflict {lines, t? | card?}  N006 (scripts/conflict_explain.gd): wishes (assert lines + "both feet planted",
##                                 "lean 40 deg forward") at one moment -> "no conflict", or the minimal clashing set and the
##                                 cost to free each ("needs 12 cm more reach: step 12 cm forward, or lean 5 deg, or drop ...")
##   path_to_pose {target, max_steps?, apply?}  N008 (scripts/pose_path.gd): target = a pose name / file, pose words or search
##                                 words; returns steps (run tokens per waypoint, each with why), checks (limits, planted feet,
##                                 floor, self-intersection, target reached), blocked (the joint past its range, ...); a dry plan
##   save {out}                    write the live scene (scenes/_wip/ or outside the project only)
##   quit
##   try {variants: [[steps], ...] | base: [steps with {p}], sweep: {param: p, values: [...]}, score?, asserts?, apply?}
##                                 N019: each variant an N003 dry run, ranked best first (fewest assertions failing, realism
##                                 score, MUST FIX, findings) with its diff (cards changed, joints moved); variants with a bad
##                                 step listed under "failed"; apply: "best" | n runs that one for real as ONE undo step (scripts/try_n.gd)
##   brief {path?, tokens?, facts?}  N011: the scene in under `tokens` (default 400, about 4 characters each): who, cards, beats,
##                                 contacts, realism score, top 3 problems with their fix steps, what to do next (scripts/scene_brief.gd);
##                                 path = open it first (as open)
##   text_view {t | frame, fps | card}  N001: the pose as text: front + side ASCII stick figures and one paragraph
##                                 (stance, weight split, lean, hands in landmarks, feet, facing, balance); scripts/text_view.gd
##   knobs {card, read: true} | {card, set: {strike_height_cm, reach_pct, stance_cm, guard_cm}}  N025 (scripts/move_knobs.gd): a
##                                 strike card's height (cm over his chin), reach (% of the limb), stance (cm between the ankles),
##                                 guard (cm of the guard wrist over the chin); set re-solves the card and its neighbours by IK as
##                                 ONE undo step, planted feet kept; "unreached" names the joint whose limit stopped a knob
##   recognize {card?, t0?, t1?, fighter?}  N016: the strike the body does (jab ... roundhouse, weapon swings, thrust; else
##                                 "unknown" + the nearest) from path, chain, speed and feet, and its form vs the textbook
##                                 ("the elbow drops 25 deg below shoulder height"); scripts/move_recognizer.gd
##   fix_until {bar?, max_steps?, dry?, path?}  N005: Check fixes, the timing coach and the I45 judges' fixes in order of predicted
##                                 gain until every saved assertion passes and realism >= bar (default 70), or no fix helps, or
##                                 max_steps (10); a fix that lowers the score or breaks a passing line is reverted. ONE undo step;
##                                 dry = the plan only, nothing changed. Each step with the score and failing lines before / after
##                                 (scripts/fix_loop.gd)
## Errors are JSON-RPC errors: -32700 not JSON, -32600 not a request, -32601 no such method (lists them), -32602 bad
## params (says what to send), -32000 a step or a save failed (data.steps has what ran). Every message says what to do.
extends SceneTree

var m: Node
var quiet := false
var T: AgentTools   # serve's tools (scripts/agent_tools.gd), on this session's poser


func say(t: String) -> void:
	if not quiet:
		print(t)


func done(d: Dictionary) -> void:
	print(JSON.stringify(d))
	quit(0 if d.get("ok", false) else 1)


func res(p: String) -> String:
	return AgentTools.res(p)


func open_scene(p: String) -> bool:
	var r := res(p)
	if not FileAccess.file_exists(r):
		done({"ok": false, "error": "no such scene: " + p})
		return false
	m._load_scene(r)
	m._rebuild_cards()
	return true


## the scene, as `describe` gives it; talk = also as lines
func describe_now(talk: bool) -> Dictionary:
	var S: Scene = m.S
	var d := T.describe()
	if talk:
		say("SCENE %s: %d cards, %.2f s, %d fps%s%s%s" % [S.name, S.cards.size(), S.length(), S.fps, ", spline" if S.spline else "", ", moving holds" if S.moving_holds else "", ", on the floor" if S.on_floor else ""])
		for cd in d["cards"]:
			say("  card %2d %-22s arrive %5.2f s  move %4.2f  hold %4.2f  %s" % [cd["n"], cd["name"], cd["arrive_s"], cd["move_s"], cd["hold_s"], cd.get("weapon", "")])
	return d


func _init() -> void:
	var a: Array = Array(OS.get_cmdline_user_args())
	quiet = "--json" in a
	a = a.filter(func(x): return x != "--json")
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	T = AgentTools.new(m)
	var verb: String = a[0] if a.size() > 0 else ""
	match verb:
		"commands":
			var cs := []
			for c in m._commands():
				cs.append({"id": c["id"], "name": c["name"], "keys": c["keys"], "edits": c["edits"], "desc": c["desc"]})
				say("%-38s %-8s %s  %s" % [c["id"], c["keys"], "EDIT" if c["edits"] else "    ", c["desc"]])
			done({"ok": true, "commands": cs})
		"facts":   # N022: facts "how fast is a real jab?" | facts list
			var fq := " ".join(a.slice(1))
			var fr := HumanFacts.serve({"list": true} if fq == "list" else {"q": fq})
			say(String(fr.get("answer", "%d facts" % fr.get("count", 0))) if not fr.is_empty() else "facts \"<question>\" | facts list")
			fr["ok"] = not fr.is_empty()
			done(fr)
		"describe":
			if a.size() >= 2 and a[1] == "joint":
				var dj := WhatIf.describe_joint(m, " ".join(a.slice(2)))
				if not dj["ok"]:
					done(dj)
					return
				for l in dj["text"]:
					say(l)
				done(dj)
				return
			if a.size() < 2 or not open_scene(a[1]):
				if a.size() < 2:
					done({"ok": false, "error": "describe <scene.json>"})
				return
			var d := describe_now(true)
			d.erase("selected_card")
			d.erase("selected_part")
			var fs := T.findings()
			say("CHECK: %d findings, %d must fix" % [fs.size(), fs.filter(func(f): return f["sev"] == "MUST FIX").size()])
			d["ok"] = true
			d["findings"] = fs.size()
			d["must_fix"] = fs.filter(func(f): return f["sev"] == "MUST FIX").size()
			d["joints"] = Body.BODY
			done(d)
		"ask":
			if a.size() < 3:
				done({"ok": false, "error": "ask <scene.json|-> [card=N] \"joint=elbow_r axis=flex value=90\"  (nothing is changed)"})
				return
			if a[1] != "-" and not open_scene(a[1]):
				return
			var card := 1
			var rest := []
			for x in a.slice(2):
				if String(x).begins_with("card=") and String(x).substr(5).is_valid_int():
					card = int(String(x).substr(5))
				else:
					rest.append(x)
			if m.S.cards.size() > 0:
				if card < 1 or card > m.S.cards.size():
					done({"ok": false, "error": "no card %d (the scene has %d)" % [card, m.S.cards.size()]})
					return
				m._card_pick(card - 1)
			var q := WhatIf.ask(m, "; ".join(rest))
			if q["ok"]:
				for l in q["text"]:
					say(l)
			done(q)
		"check":
			if a.size() < 2 or not open_scene(a[1]):
				if a.size() < 2:
					done({"ok": false, "error": "check <scene.json> [--json]"})
				return
			var fs := T.findings()
			for f in fs:
				say("%2d %-8s %-12s %5.2f s  card %d '%s'  %s%s" % [f["n"], f["sev"], f["rule"], f["t"], f["card"], f["card_name"], f["msg"], ("   [fix: %s]" % f["fix"]) if f["fix"] != "" else ""])
			var must := fs.filter(func(f): return f["sev"] == "MUST FIX").size()
			say("CHECK %s: %d findings, %d must fix" % ["clean" if fs.is_empty() else "done", fs.size(), must])
			done({"ok": true, "scene": m.S.name, "clean": fs.is_empty(), "must_fix": must, "findings": fs})
		"check_all":
			check_all(a)
		"assert":
			if a.size() < 2 or not open_scene(a[1]):
				if a.size() < 2:
					done({"ok": false, "error": "assert <scene.json> \"<line>\" ...", "grammar": BodyAssert.GRAMMAR})
				return
			var rq: Dictionary = await T.request(1, "assert", {"lines": a.slice(2)} if a.size() > 2 else {})
			if rq.has("error"):
				done({"ok": false, "error": rq["error"]["message"]})
				return
			var ar: Dictionary = rq["result"]
			for x in ar.get("results", []):
				say(x.get("say", "UNREAD  %s:  %s" % [x["line"], x.get("error", "")]))
			if ar.get("unread", 0) > 0:
				for g in BodyAssert.GRAMMAR:
					say(g)
			ar["ok"] = ar.get("pass", false)
			done(ar)
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
		"events":
			if a.size() < 3 or not open_scene(a[1]):
				if a.size() < 3:
					done({"ok": false, "error": "events <scene.json> \"<query>\" [fighter=N] [fps=F]  (N017; scripts/event_query.gd)"})
				return
			var ep := {"q": " ".join(a.slice(2).filter(func(x): return not (String(x).begins_with("fighter=") or String(x).begins_with("fps="))))}
			for x in a.slice(2):
				if String(x).begins_with("fighter="):
					ep["fighter"] = int(String(x).substr(8))
				elif String(x).begins_with("fps="):
					ep["fps"] = float(String(x).substr(4))
			var ev: Dictionary = await EventQuery.run(m, ep)
			say(String(ev.get("text", ev.get("error", ""))))
			done(ev)
		"range":   # N013: range <scene|-> [card=N] [t=S] [step=D] [from=A] [to=B] <joint> <axis> "<condition>" ...
			if a.size() < 5 or (a[1] != "-" and not open_scene(a[1])):
				if a.size() < 5:
					done({"ok": false, "error": "range <scene.json|-> [card=N] [t=S] [step=D] <joint> <axis> \"<condition>\" ...  (N013; scripts/range_sweep.gd)"})
				return
			var rp := {"conditions": []}
			var pos := []
			for x in a.slice(2):
				var kv := String(x).split("=", true, 1)
				if kv.size() == 2 and kv[0] in ["card", "t", "step", "from", "to"] and kv[1].is_valid_float():
					rp[kv[0]] = int(kv[1]) if kv[0] == "card" else float(kv[1])
				else:
					pos.append(x)
			rp["joint"] = pos[0] if pos.size() > 0 else ""
			rp["axis"] = pos[1] if pos.size() > 1 else ""
			rp["conditions"] = pos.slice(2)
			var rr := RangeSweep.run(m, rp)
			for l in rr.get("text", [rr.get("error", "")]):
				say(l)
			done(rr)
		"explain_conflict":   # N006
			if a.size() < 3 or not open_scene(a[1]):
				if a.size() < 3:
					done({"ok": false, "error": "explain_conflict <scene.json> \"<wish>\" ... [t=s] [card=N]  (N006; scripts/conflict_explain.gd)"})
				return
			var cp := {"lines": a.slice(2).filter(func(x): return not (String(x).begins_with("t=") or String(x).begins_with("card=")))}
			for x in a.slice(2):
				if String(x).begins_with("t="):
					cp["t"] = float(String(x).substr(2))
				elif String(x).begins_with("card="):
					cp["card"] = int(String(x).substr(5))
			var cx := ConflictExplain.serve(m, cp)
			say(String(cx.get("say", cx.get("error", ""))))
			done(cx)
		"run":
			await run(a)
		"serve":
			await serve()
		"brief":   # N011 (scripts/scene_brief.gd)
			var ti := a.find("--tokens")
			var tk := int(a[ti + 1]) if ti >= 0 and ti + 1 < a.size() else SceneBrief.DEFAULT_TOKENS
			if a.size() < 2 or tk < SceneBrief.MIN_TOKENS or not open_scene(a[1]):
				if a.size() < 2 or tk < SceneBrief.MIN_TOKENS:
					done({"ok": false, "error": "brief <scene.json> [--tokens N]  (N >= %d)" % SceneBrief.MIN_TOKENS})
				return
			var br := await SceneBrief.brief(m, T, tk)
			say(br["text"])
			done(br)
		"knobs":   # N025: knobs <scene> card=N [knob=value ...] [--out path] (scripts/move_knobs.gd)
			var oi := a.find("--out")
			var kout: String = res(a[oi + 1]) if oi >= 0 and oi + 1 < a.size() else ""
			if a.size() < 2 or not open_scene(a[1]):
				if a.size() < 2:
					done({"ok": false, "error": "knobs <scene.json> card=N [strike_height_cm=.. reach_pct=.. stance_cm=.. guard_cm=..] [--out <path>]"})
				return
			var kp := {"card": m.sel_card + 1}
			var kset := {}
			for x in a.slice(2):
				var kv := String(x).split("=")
				if kv.size() == 2 and kv[0] == "card":
					kp["card"] = int(kv[1])
				elif kv.size() == 2 and kv[0] in MoveKnobs.KNOBS and kv[1].is_valid_float():
					kset[kv[0]] = float(kv[1])
			if not kset.is_empty():
				kp["set"] = kset
			var kr := MoveKnobs.serve(m, kp)
			say(String(kr.get("said", kr.get("error", JSON.stringify(kr.get("values", {}))))))
			if kr["ok"] and kout != "":
				var kwhy := T.out_refused(kout)
				if kwhy != "":
					done({"ok": false, "error": kwhy})
					return
				T.write_scene(kout, "poser_cli knobs")
				kr["out"] = kout
			done(kr)
		"try":   # N019 (scripts/try_n.gd): try <scene> <steps> [--or <steps>]... | <steps with {p}> --sweep p=v1,v2 [--no-score] [--apply best|N --out path]
			var tp := {"score": not "--no-score" in a}
			var tq := a.filter(func(x): return x != "--no-score" and x != "--json")
			for flag in ["--apply", "--out", "--sweep"]:
				var fi := tq.find(flag)
				if fi >= 0 and fi + 1 < tq.size():
					tp[flag] = tq[fi + 1]
					tq = tq.slice(0, fi) + tq.slice(fi + 2)
			if tp.has("--apply"):
				tp["apply"] = "best" if tp["--apply"] == "best" else int(tp["--apply"])
			if tp.has("--sweep"):
				var sw: PackedStringArray = String(tp["--sweep"]).split("=")
				tp["base"] = tq.slice(2)
				tp["sweep"] = {"param": sw[0], "values": Array(sw[1].split(",")) if sw.size() == 2 else []}
			else:
				tp["variants"] = [[]]
				for x in tq.slice(2):
					if x == "--or":
						tp["variants"].append([])
					else:
						tp["variants"][-1].append(x)
			var tout: String = res(tp.get("--out", "")) if tp.has("--out") else ""
			if tout != "" and T.out_refused(tout) != "":
				done({"ok": false, "error": T.out_refused(tout)})
				return
			if tq.size() < 3 or not open_scene(tq[1]):
				if tq.size() < 3:
					done({"ok": false, "error": "try <scene.json> <steps> --or <steps> ... | try <scene.json> retime=3-3:{pct} --sweep pct=80,90,100 [--no-score] [--apply best|N --out <path>]"})
				return
			m._card_pick(0)
			var tr: Dictionary = await T.request(1, "try", tp)
			var trr: Dictionary = tr.get("result", tr.get("error", {}).get("data", {}))
			for l in TryN.lines(trr):
				say(l)
			trr["ok"] = tr.has("result")
			if tr.has("error"):
				trr["error"] = tr["error"]["message"]
			if trr["ok"] and tout != "" and trr.has("applied"):
				T.write_scene(tout, "poser_cli try")
				trr["out"] = tout
			done(trr)
		"path_to_pose":   # N008: scripts/pose_path.gd
			var mi := a.find("--max")
			var mx := int(a[mi + 1]) if mi >= 0 and mi + 1 < a.size() else PosePath.MAX_STEPS
			if a.size() < 3:
				done({"ok": false, "error": "path_to_pose <scene.json|-> \"<pose name | pose words>\" [--max N]"})
				return
			if a[1] != "-":
				if not open_scene(a[1]):
					return
				m._card_pick(0)
			var pr := PosePath.plan(m.B, String(a[2]), mx)
			if a[1] != "-" and pr.has("run"):
				pr["cli"] = "run %s %s" % [a[1], " ".join(pr["run"]["params"]["steps"])]
			for l in PosePath.lines(pr):
				say(l)
			pr["ok"] = pr.get("ok", false) and not pr.has("blocked")
			done(pr)
		"lint":   # N018: scripts/clip_lint.gd
			var lr := ClipLint.lint(m, a[1] if a.size() > 1 else "")
			for l in ClipLint.lines(lr):
				say(l)
			done(lr)
		"textview":
			if a.size() < 2 or not open_scene(a[1]):
				if a.size() < 2:
					done({"ok": false, "error": "textview <scene.json> [card=N]"})
				return
			var tc := 1
			for x in a.slice(2):
				if String(x).begins_with("card=") and String(x).substr(5).is_valid_int():
					tc = int(String(x).substr(5))
			var tv: Dictionary = await TextView.on_main(m, {"card": tc})
			if tv["ok"]:
				say(tv["text"])
			done(tv)
		"recognize":   # N016 (scripts/move_recognizer.gd)
			if a.size() < 2 or not open_scene(a[1]):
				if a.size() < 2:
					done({"ok": false, "error": "recognize <scene.json> [card=N] [t0=S] [t1=S] [fighter=N]  (N016)"})
				return
			var rp := {}
			for x in a.slice(2):
				var kv := String(x).split("=")
				if kv.size() == 2 and kv[0] in ["card", "fighter"]:
					rp[kv[0]] = int(kv[1])
				elif kv.size() == 2 and kv[0] in ["t0", "t1"]:
					rp[kv[0]] = float(kv[1])
			var rr: Dictionary = await MoveRecognizer.serve(m, rp)
			say(String(rr.get("text", rr.get("error", ""))))
			done(rr)
		"fixuntil":   # N005 (scripts/fix_loop.gd)
			var dry := "--dry" in a
			var fo := a.find("--out")
			var fb := a.find("--bar")
			var fn := a.find("--steps")
			var outp: String = res(a[fo + 1]) if fo >= 0 and fo + 1 < a.size() else ""
			var why_out := T.out_refused(outp) if outp != "" else ""
			if a.size() < 2 or (outp == "" and not dry) or why_out != "" or not open_scene(a[1]):
				if a.size() < 2 or (outp == "" and not dry) or why_out != "":
					done({"ok": false, "error": why_out if why_out != "" else "fixuntil <scene.json> [--bar N] [--steps N] --out <path>  (or --dry: the plan only)"})
				return
			var fr: Dictionary = await FixLoop.run(m, T, float(a[fb + 1]) if fb >= 0 and fb + 1 < a.size() else FixLoop.DEFAULT_BAR,
				int(a[fn + 1]) if fn >= 0 and fn + 1 < a.size() else FixLoop.DEFAULT_STEPS, dry)
			if fr["ok"]:
				for st in fr["steps"]:
					say("%2d %-8s card %d  %s  predicted %+.2f  score %.2f -> %.2f  %s" % [st["n"], st["rule"], st["card"], st["fix"], st["predicted_gain"],
						st["before"]["score"], st["after"]["score"], "kept" if st["kept"] else "REVERTED: " + String(st["reverted"])])
				say("STOPPED (%s): %s" % [fr["stopped"], fr["why"]])
				if outp != "" and not dry:
					T.write_scene(outp, "fixuntil (N005)")
					fr["out"] = outp
			done(fr)
		_:
			say("verbs: commands | describe <scene> | describe joint <name> | ask <scene> \"joint=.. axis=.. value=..\" | check <scene> [--json] | events <scene> \"<query>\" | diff <a> <b> | validate <file> | run <scene> <step> ... [--out <path>] | serve   (head of tools/poser_cli.gd)")
			done({"ok": false, "error": "unknown verb '%s'" % verb})


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
		var why := T.out_refused(out)
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
		var fs := T.findings()
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
	h.append("<!doctype html><html><head><meta charset=\"utf-8\"><title>Kine check: %s</title><style>" % e.call(folder.get_file()))
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
	var dry := "--dry" in a   # N003: report what the steps would do, put everything back (scripts/dry_run.gd)
	var no_score := "--no-score" in a   # the realism score costs ~5 s a read (twice when the cards change)
	a = a.filter(func(x): return x != "--dry" and x != "--no-score")
	if dry and "--out" in a:
		done({"ok": false, "error": "--dry writes nothing: drop --out"})
		return
	var out := ""
	var i := a.find("--out")
	if i >= 0:
		if i + 1 >= a.size():
			done({"ok": false, "error": "--out needs a path"})
			return
		out = res(a[i + 1])
		a = a.slice(0, i) + a.slice(i + 2)
		var why := T.out_refused(out)
		if why != "":
			done({"ok": false, "error": why.replace("the output", "--out")})
			return
	if a.size() < 2 or not open_scene(a[1]):
		if a.size() < 2:
			done({"ok": false, "error": "run <scene.json> <step> ... [--out <path>]"})
		return
	m._card_pick(0)
	m.undo.clear()
	if dry:
		var dr := await DryRun.run(T, a.slice(2), not no_score)
		for l in dr.get("cards", {}).get("lines", []):
			say(l)
		say("DRY %s: %d parts moved, findings %s -> %s, score %s, restored %s" % ["refused" if dr.has("refused") else ("ok" if dr["ok"] else "FAIL"),
			dr.get("parts_moved", []).size(), dr.get("findings", {}).get("before", "-"), dr.get("findings", {}).get("after", "-"), dr.get("score", {}).get("delta", "-"), dr.get("restored", "-")])
		done(dr)
		return
	var steps := []
	var ok := true
	for tok: String in a.slice(2):
		var st := await T.step(tok)
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
			T.write_scene(out, "poser_cli run %s" % " ".join(a.slice(1)))
			d["out"] = out
			say("wrote %s (%d cards, %.2f s)" % [out, m.S.cards.size(), m.S.length()])
	done(d)


## ---- SERVE: a live session over stdin / stdout ----

func serve() -> void:
	m.S = Scene.new()
	m.scene_path = ""
	m._rebuild_cards()
	m.undo.clear()
	print(JSON.stringify({"jsonrpc": "2.0", "method": "ready", "params": {"methods": AgentTools.METHODS, "cards": 0}}))
	var held := ""   # the end of a chunk that was not a whole line yet
	while true:
		var chunk := OS.read_string_from_stdin(1 << 20)
		if chunk == "":   # stdin closed
			if held.strip_edges() != "":
				print(JSON.stringify(await T.handle(held)))
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
			var resp := await T.handle(line)
			print(JSON.stringify(resp))
			if resp.get("result", {}) is Dictionary and resp.get("result", {}).get("bye", false):
				quit(0)
				return
	quit(0)


