## godot --headless --path . -s tests/humanfacts_test.gd     (N020 trust labels + N022 human facts)
## BARS (set before measuring):
##   1 FACTS: at least 25 facts; every one has a trust label in {MEASURED, HEURISTIC, UNVERIFIED}, a unit and a source,
##     and a MEASURED one also a url / doi / doc path (a fact with no source must say UNVERIFIED)
##   2 MATCHING: 5 questions x 10 phrasings each; every question hits its own fact in at least 9 of 10 phrasings
##   3 NO GUESS: 6 questions Kine has no number for all answer found = false, "no cited number", no value, and name
##     at least one nearest topic
##   4 REGISTRY: every name in Trust.REG exists in its file as `const NAME` (grepped in the text) and Trust.value() reads
##     a non-null value from the code; every status is one of the three; every MEASURED row has a source and a url;
##     every bar a rule names (Trust.RULES) and every fact's "code" is a registry row; every rule in Rulebook.SRC has a
##     RULES entry (so Check never serves a finding the registry cannot label)
##   5 SERVE: on a live poser (combo3), check and measure WITHOUT trust carry no "trust" key and are identical to the
##     labelled answer with the labels removed; with trust: true every finding and every measure has a status; facts
##     answers {q}, {list}, {registry}, and an empty {q} is a -32602 error. (The byte-for-byte transcript is
##     tests/agent_tools_test.gd's; run it with this suite.)
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func strip_trust(v: Variant) -> Variant:
	if v is Dictionary:
		var d := {}
		for k in v:
			if k != "trust":
				d[k] = strip_trust(v[k])
		return d
	if v is Array:
		return v.map(func(x): return strip_trust(x))
	return v


func _init() -> void:
	var ST := [Trust.M, Trust.H, Trust.U]
	# 1
	var bad := []
	for f in HumanFacts.FACTS:
		var src := String(f.get("source", ""))
		if not f["trust"] in ST or String(f["unit"]) == "" or src == "" or (f["trust"] == Trust.M and String(f.get("url", "")) == ""):
			bad.append(f["id"])
	var counts := {}
	for s in ST:
		counts[s] = HumanFacts.FACTS.filter(func(f): return f["trust"] == s).size()
	ok(HumanFacts.FACTS.size() >= 25 and bad.is_empty(), "1 %d facts (bar 25), labels %s; without a label/unit/source/url: %s" % [HumanFacts.FACTS.size(), counts, bad])
	# 2
	var Q := {
		"jab_speed": ["how fast is a real jab?", "jab speed", "what's the velocity of a jab", "How quick is a jab punch?",
			"fist speed of a straight punch", "how fast does a cross travel", "typical jab velocity in m/s", "speed of a boxer's jab",
			"how quickly does a jab move", "how fast are jabs"],
		"punch_duration": ["how long does a hook take?", "duration of a hook", "how many seconds is a hook punch", "hook punch time",
			"how long does a punch last", "how much time does a jab take", "how many frames does a hook take", "time for a cross to land",
			"how long is a hook", "how long does it take to throw a hook"],
		"step_length": ["how far does a man step?", "step length", "how long is a step", "stride length when walking",
			"how big is a walking step", "distance of one step", "how far apart are steps in a walk", "length of a person's stride",
			"how wide is a normal step", "average step size"],
		"elbow_flex_max": ["max elbow flexion", "how far can an elbow bend?", "elbow range of motion", "maximum elbow bend",
			"how much can the elbow flex", "elbow flexion limit", "what is the elbow's full flexion", "how bent can an elbow get",
			"most an elbow can fold", "elbow ROM"],
		"reaction_time": ["reaction time", "how fast can a person react?", "how quickly does a fighter respond", "human reflex speed",
			"what is the reaction time of a boxer", "how long to react to a punch", "simple visual reaction time", "how fast are reflexes",
			"response time of an athlete", "reaction speed"],
	}
	for want in Q:
		var hit := 0
		var miss := []
		for q in Q[want]:
			var a := HumanFacts.ask(q)
			if a["found"] and a["id"] == want:
				hit += 1
			else:
				miss.append("'%s' -> %s" % [q, a.get("id", "none")])
		ok(hit >= 9, "2 %s: %d of 10 phrasings hit it (bar 9)%s" % [want, hit, "" if miss.is_empty() else "; missed " + ", ".join(miss)])
	# 3
	var none := ["what is the speed of light", "how heavy is a horse", "how tall is the eiffel tower", "what colour is the sky",
		"how fast can a cheetah run", "what is the boiling point of water"]
	var guessed := []
	for q in none:
		var a := HumanFacts.ask(q)
		if a["found"] or a["answer"] != "no cited number" or a.has("value") or a["nearest"].is_empty():
			guessed.append("'%s' -> %s" % [q, a.get("id", a["answer"])])
	ok(guessed.is_empty(), "3 %d questions with no fact all say 'no cited number' with nearest topics; guessed: %s" % [none.size(), guessed])
	# 4
	var missing := []
	var noval := []
	var badrow := []
	var texts := {}
	for n: String in Trust.REG:
		var p := n.split(".")
		var file: String = Trust.FILES.get(p[0], "")
		if not texts.has(file):
			texts[file] = FileAccess.get_file_as_string(file) if file != "" else ""
		if file == "" or not String(texts[file]).contains("const " + p[1] + " "):
			missing.append(n)
		if Trust.value(n) == null:
			noval.append(n)
		var r: Dictionary = Trust.REG[n]
		if not r["s"] in ST or (r["s"] == Trust.M and (String(r["src"]) == "" or String(r["url"]) == "")):
			badrow.append(n)
	var orphan := []
	for rule in Trust.RULES:
		for n in Trust.RULES[rule]:
			if not Trust.REG.has(n):
				orphan.append(n)
	for f in HumanFacts.FACTS:
		for n in f["code"]:
			if not Trust.REG.has(n):
				orphan.append(n)
	var unruled := Rulebook.SRC.keys().filter(func(r): return not Trust.RULES.has(r))
	ok(missing.is_empty() and noval.is_empty() and badrow.is_empty() and orphan.is_empty() and unruled.is_empty(),
		"4 %d registry rows: not `const` in their file %s, no value %s, bad status/source %s, names outside the registry %s, Check rules without a row %s"
		% [Trust.REG.size(), missing, noval, badrow, orphan, unruled])
	# 5
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var A := AgentTools.new(m)
	await A.request(1, "open", {"path": "scenes/combo3.json"})
	var c0: Dictionary = await A.request(2, "check", {})
	var c1: Dictionary = await A.request(3, "check", {"trust": true})
	var what := ["distance hand_r head", "angle upperarm_r lowerarm_r hand_r", "height head", "speed hand_r", "com", "balance"]
	var m0: Dictionary = await A.request(4, "measure", {"t": 0.5, "what": what})
	var m1: Dictionary = await A.request(5, "measure", {"t": 0.5, "what": what, "trust": true})
	var fs: Array = c1["result"]["findings"]
	var ms: Array = m1["result"]["measures"]
	var labelled := fs.filter(func(f): return f.has("trust") and f["trust"]["status"] in ST).size()
	var mlab := ms.filter(func(x): return x.has("trust") and x["trust"]["status"] in ST).size()
	var plain := not JSON.stringify(c0).contains("\"trust\"") and not JSON.stringify(m0).contains("\"trust\"")
	var same := JSON.stringify(strip_trust(c1)["result"]) == JSON.stringify(c0["result"]) and JSON.stringify(strip_trust(m1)["result"]) == JSON.stringify(m0["result"])
	var by := {}
	for f in fs:
		by[f["rule"]] = f["trust"]["status"]
	ok(plain and same and fs.size() > 0 and labelled == fs.size() and mlab == ms.size(),
		"5a trust off = no labels (%s), on = the same answer + labels (%s): %d of %d findings, %d of %d measures labelled; rules %s"
		% [plain, same, labelled, fs.size(), mlab, ms.size(), by])
	var f1: Dictionary = await A.request(6, "facts", {"q": "how fast is a real jab?"})
	var f2: Dictionary = await A.request(7, "facts", {"list": true})
	var f3: Dictionary = await A.request(8, "facts", {"registry": true})
	var f4: Dictionary = await A.request(9, "facts", {})
	ok(f1.has("result") and f1["result"]["id"] == "jab_speed" and f2.has("result") and int(f2["result"]["count"]) == HumanFacts.FACTS.size()
		and f3.has("result") and f3["result"]["registry"].size() == Trust.REG.size() and f4.has("error") and int(f4["error"]["code"]) == -32602,
		"5b serve facts: jab -> %s %s %s [%s]; list %s; registry %s rows; empty q -> %s"
		% [f1.get("result", {}).get("id"), f1.get("result", {}).get("value"), f1.get("result", {}).get("unit"), f1.get("result", {}).get("trust"),
			f2.get("result", {}).get("count"), f3.get("result", {}).get("registry", []).size(), f4.get("error", {}).get("code", "-")])
	m.queue_free()
	print("HUMANFACTS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
