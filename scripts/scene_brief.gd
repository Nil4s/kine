## scene_brief.gd - SCENE BRIEF (INNOVATIONS N011). One short summary of the live scene, sized for an AI agent's context window, so an
## agent picks up a scene without reading its file: who (fighters, body, weapons), length and fps, the cards in order with their kind
## and times, the beats and contacts (who hits whom, when, the impulse), the realism score, the 3 biggest problems each with the
## serve step that fixes it, and what to do next.
## NOTHING IS MEASURED HERE THAT THE APP DOES NOT ALREADY MEASURE; this file only gathers and words it:
##   cards, times     AgentTools.describe (serve `describe`); a card's kind: StylePrint.kind_of (strike / windup / guard / recover / step)
##   score, problems  the I16 realism score exactly as the registry's "Realism score" command makes it (RealismUI.refresh: Check with the
##                    human limits, the timing coach, push limits, Force view, the I45 judges), its 3 reasons (RealismScore.compute)
##   fix steps        a Check reason -> `fix=K`, K its number in serve `check` (main._check = Rulebook.check, the score's own call); a
##                    human-limit finding is listed by Check only once "is_this_clip_physically_possible?" switched those rules on,
##                    so that step goes first. A timing
##                    reason -> `retime=N-N:pct` (Scene.retime scales the card's move, and its hold, by pct). The other judges' fixes
##                    (I45 JudgeSuite.fix, Make it physical) have no serve step yet: the brief says so instead of inventing one.
##   contacts         the dummy's own measurement as main._dummy_measure makes it (Dummy.hits, the scene's fps, a default body), or with
##                    2+ fighters main's fighter_hits (Dummy.fighter_hits). Impulse J = (1 + e) mu v_rel: HitPhysics.measure's formula
##                    (Cross 1999 / Khatib 1987 strike mass, Walilko 2005 fist mass, e = 0.16: the citations are in hit_physics.gd).
##                    The dummy stands still, so v_rel = the landing spot's speed and J points along it.
##   frame data       FrameData.analyze (startup / active / recovery at 60 fps, ROADMAP 12)
## BUDGET: tokens are estimated as characters / 4 (CHARS_PER_TOKEN; a HEURISTIC: about 4 characters a token for English text,
## UNVERIFIED for this tokenizer). The brief is a list of sections, each with variants from the most detailed to the shortest; every
## variant is whole sentences. Sections are given room in PRIORITY order (the scene line first, then the top problem and what to do
## next, then who, contacts, the other problems, the cards, beats, frame data), each taking its longest variant that still fits, so a
## smaller budget drops details and never cuts a sentence. The lines are then printed in reading ORDER.
## DETERMINISTIC: every fact is computed from the scene alone (no clock, no random); numbers are printed at fixed precision.
class_name SceneBrief
extends RefCounted

const DEFAULT_TOKENS := 400
const MIN_TOKENS := 40          # the shortest scene line of a long scene name still fits (about 30 tokens)
const CHARS_PER_TOKEN := 4.0    # HEURISTIC, see the header
const FEASIBLE_STEP := "is_this_clip_physically_possible?"   # the registry id of "Is this clip physically possible?" (main._feasible_check)
const ORDER := ["head", "who", "cards", "beats", "contacts", "frames", "p1", "p2", "p3", "next"]
const PRIORITY := ["head", "p1", "next", "who", "contacts", "p2", "p3", "cards", "beats", "frames"]
const HANDS := {"hand_r": "right hand", "hand_l": "left hand", "": "no hand"}

## facts of the last scenes briefed in this process, by the scene's content (a second budget for the same scene costs nothing)
static var _cache := {}


static func est_tokens(text: String) -> int:
	return int(ceil(float(text.length()) / CHARS_PER_TOKEN))


## the key the facts are kept under: everything they are computed from
static func _key(m: Node) -> String:
	var S: Scene = m.S
	return "|".join([m.scene_path, S.name, var_to_str(S.cards), var_to_str(S.body), var_to_str(S.beats), var_to_str(S.markers), str(S.fps),
		str(m.dummy_on), str(m.T.dist), str(m.T.yaw), str(m.actors_rt.size()), str(HumanLimits.on)])


static func _f2(x: float) -> String:
	return "%.2f" % x


## the 0-based card playing at time t (the last card from its arrival on)
static func _card_at(S: Scene, t: float) -> int:
	var ts: Array = S.times()
	var k := 0
	for i in ts.size():
		if t >= float(ts[i][0]) - 1e-6:
			k = i
	return k


## the first sentence of a text (up to and including its first ". "), or all of it
static func _first_sentence(s: String) -> String:
	var t := s.strip_edges().get_slice("\n", 0)
	var i := t.find(". ")
	return t if i < 0 else t.substr(0, i + 1)


static func _end(s: String) -> String:
	var t := s.strip_edges()
	return t if t.ends_with(".") or t.ends_with("?") or t.ends_with("!") else t + "."


# ---- facts ------------------------------------------------------------------------------------------------------------------------

## every fact the brief is made from, as JSON-able values. Coroutine (the dummy's measurement lands first)
static func facts(m: Node, T: AgentTools) -> Dictionary:
	var k := _key(m)
	if _cache.has(k):
		return _cache[k]
	await m.dummy_settle()
	var S: Scene = m.S
	var d := T.describe()
	var f := {"scene": S.name, "path": m.scene_path.replace("res://", ""), "length_s": d["length_s"], "fps": S.fps,
		"frames": int(round(S.length() * S.fps))}
	# cards, with their kind
	var cs := []
	for cd in d["cards"]:
		var i := int(cd["n"]) - 1
		var kd := StylePrint.kind_of(S, i)
		cs.append({"n": cd["n"], "name": cd["name"], "kind": kd if kd != "" else "pose", "arrive_s": cd["arrive_s"], "move_s": cd["move_s"], "hold_s": cd["hold_s"]})
	f["cards"] = cs
	# who
	var weps := []
	for c in S.cards:
		var w: Dictionary = c["pose"].get("weapon", {})
		if not w.is_empty():
			var s := "%s in the %s" % [String(w.get("kind", "?")).replace("_", " "), HANDS.get(String(w.get("hand", "")), String(w.get("hand", "")))]
			if not s in weps:
				weps.append(s)
	f["weapons"] = weps
	var bd: Dictionary = S.body
	var st := float(bd.get("stature", Proportions.DEFAULT_STATURE))
	var kg := float(bd.get("mass", HumanLimits.REF_MASS))
	var bl := "default body" if bd.is_empty() else (String(Proportions.PRESET_NAMES.get(String(bd.get("preset", "")), "")) if bd.has("preset") else "")
	if bl == "":
		bl = "%s body" % String(bd.get("sex", "custom"))
	f["body"] = {"label": bl, "stature_m": snappedf(st, 0.01), "mass_kg": snappedf(kg, 0.1), "sex": String(bd.get("sex", ""))}
	var fighters := ["the hero"]
	for a in range(1, m.actors_rt.size()):
		fighters.append(String(m.actors_rt[a]["name"]))
	f["fighters"] = fighters
	f["opponent"] = "%d fighters" % fighters.size() if fighters.size() >= 2 else ("the dummy %.2f m in front" % m.T.dist if m.dummy_on else "none (dummy off)")
	f["contacts"] = _contacts(m)
	f["beats"] = S.beats.map(func(b): return {"t": snappedf(float(b.get("t", 0.0)), 0.001), "name": String(b.get("name", "")), "by": String(b.get("by", "")), "on": String(b.get("on", ""))})
	f["markers"] = S.markers.map(func(x): return {"t": snappedf(float(x.get("t", 0.0)), 0.001), "name": String(x.get("name", ""))})
	# frame data (the body is put back: analyze leaves it at the last frame)
	var keep: Dictionary = m.B.state()
	var fd := FrameData.analyze(S, m.B, FrameData.FPS, m.T if m.dummy_on and fighters.size() < 2 else null)
	m.B.set_state(keep)
	m.B.fk()
	f["frame_data"] = {} if fd.is_empty() else {"fps": fd["fps"], "striker": fd["striker"], "startup": fd["startup"], "active": fd["active"], "recovery": fd["recovery"], "gaps": fd["gaps"]}
	# the realism score, as the "Realism score" command makes it (RealismUI.show minus its panel)
	var sc := {"score": null, "raw": null, "reasons": [], "must_fix": 0, "findings": 0}
	if S.cards.size() >= 2:
		if int(m.tc_ui.db.get("n", 0)) == 0:
			m.tc_ui.db = MotionMatch.build()
		var rs: RealismUI = m.rs_ui
		rs.refresh()
		sc["score"] = roundi(float(rs.res["score"]))
		sc["score_exact"] = snappedf(float(rs.res["score"]), 0.0001)
		sc["raw"] = snappedf(float(rs.res["raw"]), 0.01)
		var fnd: Array = rs.inp["findings"]
		sc["findings"] = fnd.size()
		sc["must_fix"] = fnd.filter(func(x): return String(x["sev"]) == "FAIL").size()
		sc["reasons"] = _reasons(m, T, rs)
	f["realism"] = sc
	if _cache.size() >= 16:
		_cache.clear()
	_cache[k] = f
	return f


## who hits whom: [{"t", "frame", "by", "with", "on", "zone", "speed", "J"}]
static func _contacts(m: Node) -> Array:
	var S: Scene = m.S
	var out := []
	if m.actors_rt.size() >= 2:
		for r in m.fighter_hits:
			if String(r["kind"]) != "hit" and String(r["kind"]) != "struck":
				continue
			var vk: int = 0 if r["by"] == "other" else int(r["vs"])
			var sk: int = int(r["vs"]) if r["by"] == "other" else 0
			if vk >= m.actors_rt.size() or sk >= m.actors_rt.size():
				continue
			var row := {"t": snappedf(float(r["t"]), 0.001), "frame": int(round(float(r["t"]) * S.fps)), "by": "the hero" if sk == 0 else String(m.actors_rt[sk]["name"]),
				"with": String(r["part"]).replace("_", " "), "on": ("the hero" if vk == 0 else String(m.actors_rt[vk]["name"])) + "'s " + String(r["on"]).replace("_", " "),
				"zone": String(r.get("zone", "")), "speed": snappedf(float(r.get("speed", 0.0)), 0.1), "J": null}
			if not Body.is_wep(String(r["on"])):
				var blow := HitPhysics.measure(m.actors_rt[vk]["S"], m.actors_rt[vk]["B"], m.actors_rt[vk]["xf"], r, m.actors_rt[sk]["B"], m.actors_rt[sk]["S"])
				if blow["ok"]:
					row["J"] = snappedf(float((blow["J"] as Vector3).length()), 0.1)
			out.append(row)
		return out
	if not m.dummy_on or S.cards.size() < 2:
		return out
	# the dummy's hits as main._dummy_measure finds them: its own body, the scene's fps
	var HB := Body.new()
	HB.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var sc := S.clone()
	for h in m.T.hits(sc, HB, S.fps):
		var t := float(h["t"])
		sc.apply(HB, t)
		var wk := String(HB.wep_kind).replace("_", " ")
		var now: Vector3 = h["at"]
		sc.apply(HB, maxf(0.0, t - 1.0 / S.fps))
		var v: Vector3 = (now - HB.wep_point(float(h["u"]))) * float(S.fps)
		sc.apply(HB, t)
		var me := HitPhysics.strike_mass({"part": "bat_barrel", "u": h["u"]}, HB, v)
		var Mt := HitPhysics.struck_mass(String(h["part"]), m.T.D)
		var mu := me * Mt / (me + Mt)
		out.append({"t": snappedf(t, 0.001), "frame": int(round(t * S.fps)), "by": "the hero", "with": "the " + wk, "on": "the dummy's " + String(h["zone"]).to_lower(),
			"zone": String(h["zone"]), "speed": snappedf(float(h["speed"]), 0.1), "J": snappedf((1.0 + HitPhysics.RESTITUTION) * mu * v.length(), 0.1)})
	return out


## the score's 3 reasons, each with its card and the serve steps that fix it
static func _reasons(m: Node, T: AgentTools, rs: RealismUI) -> Array:
	var S: Scene = m.S
	var out := []
	var cur := []
	var got_off := false
	for r in rs.res["reasons"]:
		var fx: Dictionary = r["fix"]
		var row := {"judge": String(r["judge"]), "text": String(r["text"]), "t0": snappedf(float(r["t0"]), 0.01), "t1": snappedf(float(r["t1"]), 0.01),
			"points": snappedf(float(r["pen"]), 0.1), "steps": [], "fix": "", "how": ""}
		var ci := _card_at(S, 0.5 * (float(r["t0"]) + float(r["t1"])))
		match String(fx["kind"]):
			"check":
				var fd: Dictionary = rs.inp["findings"][int(fx["i"])]
				ci = mini(int(fd["card"]), S.cards.size() - 1)
				row["rule"] = String(fd["rule"])
				# the finding's whole message: the score keeps only its first line, and FEASIBLE's reasons are on the next ones
				var ml := PackedStringArray(Array(String(fd["msg"]).split("\n", false)).map(func(x): return String(x).strip_edges().trim_suffix(":")))
				row["text"] = "%s: %s" % [fd["rule"], "; ".join(ml)]
				var lab := Fixer.label(fd, S)
				if lab == "":
					row["how"] = "Check has no automatic fix for it: change the cards by hand"
				else:
					row["fix"] = lab.trim_prefix("Fix: ")
					# serve's `check` is Rulebook.check on Rulebook.sample (main._check), the same call the score made with the human
					# rules on: with them on its list IS the score's, so K is the score's own number; with them off it is the same
					# call on the score's cached sample with the human rules off (no second sampling of the scene)
					var fi := int(fx["i"]) + 1
					if HumanLimits.on:
						row["steps"] = ["fix=%d" % fi]
					else:
						if not got_off:
							got_off = true
							cur = Rulebook.check(S, m.ov.GB, rs._memo["sm"])
						var K := _match(cur, fd)
						row["steps"] = ["fix=%d" % K] if K > 0 else [FEASIBLE_STEP, "fix=%d" % fi]
			"timing":
				var s: Dictionary = rs.inp["tc"][int(fx["i"])]
				ci = int(s["card"])
				row["rule"] = "TIMING"
				var pct := snappedf(100.0 * float(s["to"]) / maxf(float(s["from"]), 0.001), 0.1)
				row["fix"] = "move %.2f s -> %.2f s" % [float(s["from"]), float(s["to"])]
				if pct >= 10.0 and pct <= 1000.0:
					row["steps"] = ["retime=%d-%d:%s" % [ci + 1, ci + 1, str(pct)]]
					if float(S.cards[ci]["hold"]) > 0.0:
						row["how"] = "its hold scales by the same %"
			"judge":
				row["rule"] = String(r["judge"])
				row["fix"] = String(JudgeSuite.LABEL.get(String(r["judge"]), "")).to_lower()
				row["how"] = "no serve step yet: the app's Realism score panel has its Fix"
			"phys":
				row["rule"] = "PHYSICS"
				row["how"] = "no serve step yet: Make it physical's Accept span in the app"
			_:
				row["rule"] = String(r["judge"])
				row["how"] = "no automatic fix: change the cards by hand"
		row["card"] = ci + 1
		row["card_name"] = String(S.cards[ci]["name"])
		out.append(row)
	return out


## the 1-based number of the finding `fd` in a Rulebook.check list (the same rule, card and time), or 0
static func _match(list: Array, fd: Dictionary) -> int:
	for i in list.size():
		var x: Dictionary = list[i]
		if String(x["rule"]) == String(fd["rule"]) and int(x["card"]) == int(fd["card"]) and absf(float(x["t"]) - float(fd["t"])) < 1e-6:
			return i + 1
	return 0


# ---- words ------------------------------------------------------------------------------------------------------------------------

static func _steps_json(steps: Array) -> String:
	return JSON.stringify({"steps": steps})


## each section's variants, the most detailed first (every one whole sentences)
static func sections(f: Dictionary) -> Dictionary:
	var v := {}
	var sc: Dictionary = f["realism"]
	var nc: int = (f["cards"] as Array).size()
	var score_s := "realism %d/100" % int(sc["score"]) if sc["score"] != null else "realism not scored (under 2 cards)"
	v["head"] = [
		"SCENE %s: %d cards, %s s at %d fps (%d frames); %s, %d must-fix of %d findings." % [f["scene"], nc, _f2(f["length_s"]), f["fps"], f["frames"], score_s, sc["must_fix"], sc["findings"]],
		"SCENE %s: %d cards, %s s at %d fps; %s." % [f["scene"], nc, _f2(f["length_s"]), f["fps"], score_s]]
	# who
	var b: Dictionary = f["body"]
	var bs := "%s (%s m, %s kg)" % [b["label"], _f2(b["stature_m"]), "%.0f" % float(b["mass_kg"])]
	var ws := "no weapon" if (f["weapons"] as Array).is_empty() else ", ".join(f["weapons"])
	var fs := ", ".join(f["fighters"])
	v["who"] = ["WHO: %s; %s; %s; opponent: %s." % [fs, bs, ws, f["opponent"]], "WHO: %s with %s." % [fs, ws]]
	# cards
	var full := PackedStringArray()
	var mid := PackedStringArray()
	var strikes := PackedStringArray()
	for c in f["cards"]:
		full.append("%d %s (%s) at %s s, move %s, hold %s" % [c["n"], c["name"], c["kind"], _f2(c["arrive_s"]), _f2(c["move_s"]), _f2(c["hold_s"])])
		mid.append("%d %s (%s) %s s" % [c["n"], c["name"], c["kind"], _f2(c["arrive_s"])])
		if c["kind"] == "strike":
			strikes.append("%d %s at %s s" % [c["n"], c["name"], _f2(c["arrive_s"])])
	v["cards"] = ["CARDS: " + "; ".join(full) + ".", "CARDS: " + "; ".join(mid) + "."]
	v["cards"].append("STRIKE CARDS: none." if strikes.is_empty() else "STRIKE CARDS: " + "; ".join(strikes) + ".")
	# beats
	var bt := PackedStringArray()
	for x in f["beats"]:
		bt.append("%s at %s s%s" % [x["name"], _f2(x["t"]), (" (%s on %s)" % [x["by"], x["on"]]) if x["by"] != "" else ""])
	for x in f["markers"]:
		bt.append("marker %s at %s s" % [x["name"], _f2(x["t"])])
	v["beats"] = ["BEATS: none marked."] if bt.is_empty() else ["BEATS: " + "; ".join(bt) + ".", "BEATS: %d marked, the first %s." % [bt.size(), bt[0]]]
	# contacts
	var ct: Array = f["contacts"]
	if ct.is_empty():
		v["contacts"] = ["CONTACTS: none; %s is never touched." % f["opponent"] if String(f["opponent"]).begins_with("the dummy") else "CONTACTS: none.", "CONTACTS: none."]
	else:
		var cl := PackedStringArray()
		for x in ct:
			cl.append("%s s (frame %d) %s's %s hits %s at %s m/s%s" % [_f2(x["t"]), x["frame"], x["by"], String(x["with"]).trim_prefix("the "), x["on"],
				"%.1f" % float(x["speed"]), (", impulse %.1f N s" % float(x["J"])) if x["J"] != null else ""])
		v["contacts"] = ["CONTACTS: " + "; ".join(cl) + ".", "CONTACTS: %d, the first %s." % [ct.size(), cl[0]]]
	# frame data
	var fd: Dictionary = f["frame_data"]
	v["frames"] = [] if fd.is_empty() else ["FRAME DATA at %d fps (%s): startup %d, active %d (%d inactive inside), recovery %d." % [fd["fps"], fd["striker"], fd["startup"], fd["active"], fd["gaps"], fd["recovery"]]]
	# problems
	var rs: Array = sc["reasons"]
	for i in 3:
		var key := "p%d" % (i + 1)
		if i >= rs.size():
			v[key] = ["PROBLEMS: none; every judge passes."] if i == 0 else []
			continue
		var r: Dictionary = rs[i]
		var fixs := ""
		if not (r["steps"] as Array).is_empty():
			fixs = "Fix (%s): run %s." % [r["fix"], _steps_json(r["steps"])]
		elif r["fix"] != "":
			fixs = "Fix (%s): %s." % [r["fix"], r["how"]]
		else:
			fixs = _end(r["how"])
		var where := "card %d %s, %s-%s s, -%s points" % [r["card"], r["card_name"], _f2(r["t0"]), _f2(r["t1"]), "%.1f" % float(r["points"])]
		var body := String(r["text"]).trim_prefix(String(r["rule"]) + ": ")
		v[key] = [
			"PROBLEM %d [%s, %s]: %s %s" % [i + 1, r["rule"], where, _end(body.get_slice("\n", 0)), fixs],
			"PROBLEM %d [%s, %s]: %s %s" % [i + 1, r["rule"], where, _end(_first_sentence(body)), fixs],
			"PROBLEM %d: %s at card %d. %s" % [i + 1, r["rule"], r["card"], fixs]]
	# next
	if rs.is_empty():
		v["next"] = ["NEXT: nothing is flagged; save it (serve save) or move on to the next scene.", "NEXT: nothing to fix."]
	else:
		var r0: Dictionary = rs[0]
		if not (r0["steps"] as Array).is_empty():
			v["next"] = ["NEXT: run %s (problem 1), then ask for the brief again: the score and the problem list change after every fix." % _steps_json(r0["steps"]),
				"NEXT: run %s, then brief again." % _steps_json(r0["steps"])]
		else:
			v["next"] = ["NEXT: problem 1 (%s at card %d) has no serve step; change card %d by hand (run set= / pose= steps, then update), then brief again." % [r0["rule"], r0["card"], r0["card"]],
				"NEXT: fix %s at card %d by hand, then brief again." % [r0["rule"], r0["card"]]]
	return v


## the brief of facts `f` within `tokens`: {"text", "tokens", "budget", "kept", "dropped"}
static func render(f: Dictionary, tokens: int) -> Dictionary:
	var room := int(floor(float(tokens) * CHARS_PER_TOKEN))
	var v := sections(f)
	var pick := {}
	var used := 0
	for s in PRIORITY:
		var vs: Array = v.get(s, [])
		if vs.is_empty():
			continue
		for line: String in vs:
			var need := line.length() + (1 if used > 0 else 0)   # the newline before it
			if used + need <= room:
				pick[s] = line
				used += need
				break
		if s == "head" and not pick.has(s):   # below MIN_TOKENS only: the shortest scene line, whole
			pick[s] = vs[-1]
			used += (vs[-1] as String).length()
	var lines := PackedStringArray()
	var kept := []
	var dropped := []
	for s in ORDER:
		if pick.has(s):
			lines.append(pick[s])
			kept.append(s)
		elif not (v.get(s, []) as Array).is_empty():
			dropped.append(s)
	var text := "\n".join(lines)
	return {"text": text, "tokens": est_tokens(text), "budget": tokens, "kept": kept, "dropped": dropped}


## the brief of the live scene. Coroutine. {"ok", "scene", "path", "text", "tokens", "budget", "kept", "dropped", ["facts"]}
static func brief(m: Node, T: AgentTools, tokens := DEFAULT_TOKENS, with_facts := false) -> Dictionary:
	var f: Dictionary = await facts(m, T)
	var r := render(f, tokens)
	var out := {"ok": true, "scene": f["scene"], "path": f["path"]}
	out.merge(r)
	if with_facts:
		out["facts"] = f
	return out


## serve `brief {path?, tokens?, facts?}`: path = open that file first (as `open`: the live scene is replaced); none = the live scene
static func serve(T: AgentTools, id: Variant, p: Dictionary) -> Dictionary:
	var m: Node = T.m
	var tk: Variant = p.get("tokens", DEFAULT_TOKENS)
	if not (tk is int or tk is float) or int(tk) < MIN_TOKENS or int(tk) > 100000:
		return T._err(id, -32602, "brief {\"tokens\": N} needs a whole number from %d to 100000 (default %d; a token is about 4 characters)" % [MIN_TOKENS, DEFAULT_TOKENS])
	if p.has("path"):
		var o: Dictionary = await T.request(id, "open", {"path": p["path"]})
		if o.has("error"):
			return o
	if m.S.cards.is_empty():
		return T._err(id, -32000, "brief needs a scene: send {\"path\": \"scenes/combo3.json\"} or open one first")
	return T._ok(id, await brief(m, T, int(tk), bool(p.get("facts", false))))
