## godot --headless --path . -s tests/text_blocking_test.gd      (ROADMAP 22: TYPE A MOVE, GET BLOCKING)
## RETRIEVE AND ADAPT: ten phrases through TextBlocking.build. Each: the chosen source segment printed; 4+ cards with
## the strike among them; on a two-handed weapon BOTH hands on the haft on every card (the free palm within 2 cm of the
## shaft's axis, Lock both hands' own test, and its wrist within 2 cm of its locked spot, Body.grip_miss, both read
## after a reload + apply_grip the way the app plays the card); the tip's peak inside the strike card's move
## and under the weapon's cap (docs/ATTACK_RULES.md); the default Check with no MUST FIX the source segment did not
## have; HumanLimits.findings with no finding the source did not have; unknown words listed back; the scene saved to
## user:// only and read back. Nick's scenes/, poses/, data/ are read, never written.
## STRIKES (StrikeBlocking's generated key poses: no saved scene has a punch or a kick), bars stated before measuring:
## "front kick", "roundhouse", "side kick", "hook", "cross" and "left roundhouse" each built and, for each: MoveRecognizer
## (N016, of_scene on the built scene) names the move asked (the left roundhouse with the LEFT leg); the default Check has
## NO MUST FIX at all (not only none new); HumanLimits.findings has no finding; every card's SAVED joint angles (the card's
## own dict, not the body, whose from_dict clamps) inside data/body_limits.json, with an anti-vacuity copy (a card with the
## knee bent 200 deg) flagged by the same check; the striking point's peak inside the strike's move and under its cap.
extends SceneTree

var fails := 0
const DIR := "user://text_blocking"

## [phrase, Body kind ("" = a fist), the shape asked, unknown words it must report]
const PHRASES := [
	["overhead axe strike, step in", "long_axe", "overhead", []],
	["fast jab", "", "thrust", []],
	["bat swing left", "metal_bat", "sweep", []],
	["dagger thrust lunge", "dagger", "thrust", []],
	["heavy hammer overhead, step back", "long_hammer", "overhead", []],
	["staff sweep right, pivot", "staff", "sweep", []],
	["uppercut", "", "uppercut", []],
	["hook, step in", "", "sweep", []],
	["overhead axe strike, spinning", "long_axe", "overhead", ["spinning"]],
	["slow staff thrust, step in", "staff", "thrust", []],
]


## [phrase, the class MoveRecognizer must name, the side it must name ("" = either)]
const STRIKES := [["front kick", "front kick", ""], ["roundhouse", "roundhouse", ""], ["side kick", "side kick", ""],
	["hook", "hook", ""], ["cross", "cross", ""], ["left roundhouse", "roundhouse", "left"]]


## the card poses' saved joint angles outside the body's limits: ["card: joint axis value"], read off the dicts
static func out_of_limits(B: Body, cards: Array) -> Array:
	var out := []
	for c in cards:
		var js: Dictionary = c["pose"]["joints"]
		for j in js:
			if not B.lim.has(j):
				continue
			for k in ["bend", "side", "twist"]:
				var r: Vector2 = B.lim[j][k]
				var v := float(js[j][k])
				if v < r.x - 0.01 or v > r.y + 0.01:
					out.append("%s: %s %s %.1f (%.0f..%.0f)" % [c["name"], j, k, v, r.x, r.y])
	return out


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var idx := TextBlocking.index(B)
	print("INDEX: %d attack segments in scenes/ (read only)" % idx.size())
	for e in idx:
		print("   " + TextBlocking.describe(e))
	ok(idx.size() >= 6, "the index holds %d segments (6+: the saved bat swings, overheads, thrust and staff sweep)" % idx.size())
	var dirs := {}
	for e in idx:
		dirs[e["dir"]] = true
	ok(dirs.has("overhead") and dirs.has("sweep") and dirs.has("thrust"), "the index classes overhead, sweep and thrust segments (%s)" % str(dirs.keys()))
	for row in PHRASES:
		var phrase: String = row[0]
		var want_kind: String = row[1]
		var r: Dictionary = TextBlocking.build(phrase, B)
		if not r["ok"]:
			ok(false, "'%s' builds: %s" % [phrase, r["error"]])
			continue
		var S: Scene = r["scene"]
		var n := S.cards.size()
		var e: Dictionary = r["source"]
		var fs: Array = r["findings"]
		var warns := fs.filter(func(f): return f["sev"] == "WARN").size()
		print("-- '%s' -> source %s cards %s (%s %s%s), %d cards %s" % [phrase, e["scene"], str([e["ready"]] + e["windup"] + [e["strike"]] + e["ft"] + ([e["recovery"]] if int(e["recovery"]) >= 0 else [])),
			e["kind"] if e["kind"] != "" else "fist", e["dir"], ", mirrored" if r["mirror"] else "", n, str(S.cards.map(func(c): return c["name"]))])
		var slowed: Dictionary = r["slowed"]
		print("   peak %.1f m/s (cap %.0f, %s) at %.2f s, strike window %.2f-%.2f s, slowed %s, retimes %s, must-fix %d (source %d), warns %d, human %d (source %d), grip per card (cm) %s"
			% [r["peak"], r["cap"], r["cap_name"], r["peak_t"], r["window"][0], r["window"][1],
			str(slowed.keys().map(func(k): return "%s x%d" % [k, (slowed[k] as Array).size()])), str(r["retimes"]), r["must_fix"], r["src_must_fix"], warns,
			(r["human"] as Array).size(), r["src_human"], str((r["grip"] as Array).map(func(g): return snappedf(float(g) * 100.0, 0.1)))])
		print("   times: %s" % str(S.times().map(func(t): return [snappedf(t[0], 0.01), snappedf(t[1], 0.01), snappedf(t[2], 0.01)])))
		print("   status: %s" % r["status"])
		for f in fs:
			if f["sev"] == "FAIL":
				print("   MUST FIX %s at %.2f s (card %d): %s" % [f["rule"], f["t"], f["card"], f["msg"]])
		for f in r["human"]:
			print("   human %s %s: %s" % [f["sev"], f["rule"], f["msg"]])
		ok(n >= 4 and r["roles"][r["strike_card"]] == "strike", "'%s': %d cards (4+), the strike is card %d" % [phrase, n, int(r["strike_card"]) + 1])
		ok(r["asked_shape"] == row[2], "'%s': the shape asked is %s (built as %s)" % [phrase, row[2], r["shape"]])
		# the weapon of the phrase is in the hand on every card (a fist has none)
		var hand_ok := true
		for c in S.cards:
			var w: Dictionary = c["pose"]["weapon"]
			if want_kind == "":
				hand_ok = hand_ok and w.is_empty()
			else:
				hand_ok = hand_ok and String(w.get("kind", "")) == want_kind and String(w.get("hand", "")) != ""
		ok(hand_ok, "'%s': %s in hand on every card" % [phrase, want_kind if want_kind != "" else "no weapon (a fist)"])
		if r["two"]:
			var both := true
			for c in S.cards:
				both = both and bool((c["pose"]["weapon"] as Dictionary).get("two_hand_grip", false))
			print("   second hand per card: palm off the axis (cm) %s, wrist off its locked spot (cm) %s, the line turned up to %.0f deg, the bat hand moved up to %.1f cm" % [
				str((r["palm"] as Array).map(func(g): return snappedf(float(g) * 100.0, 0.1))), str((r["grip"] as Array).map(func(g): return snappedf(float(g) * 100.0, 0.1))), r["aim"], float(r["moved"]) * 100.0])
			ok(both and float(r["worst_palm"]) <= 0.02 and float(r["worst_grip"]) <= 0.02, "'%s': both hands on the %s on every card: the free palm at worst %.1f cm off the shaft's axis (Lock both hands' own test; bar 2) and its wrist %.1f cm off its locked spot (grip_miss, _fit_second's target; bar 2), measured after a reload + apply_grip as the app plays it" % [
				phrase, want_kind.replace("_", " "), float(r["worst_palm"]) * 100.0, float(r["worst_grip"]) * 100.0])
		var pk_t: float = r["peak_t"]
		var win: Array = r["window"]
		ok(pk_t >= float(win[0]) - 1e-3 and pk_t <= float(win[1]) + 1e-3,
			"'%s': the tip's peak (%.2f s) is inside the strike's move (%.2f-%.2f s)" % [phrase, pk_t, win[0], win[1]])
		ok(float(r["peak"]) <= float(r["cap"]), "'%s': the tip's peak %.1f m/s is under the %s cap %.0f" % [phrase, r["peak"], r["cap_name"], r["cap"]])
		ok(float(r["peak"]) > 2.0, "'%s': the tip moves (peak %.1f m/s, anti-vacuity: over 2)" % [phrase, r["peak"]])
		ok((r["must_fix_new"] as Array).is_empty(), "'%s': the default Check has no MUST FIX the source segment did not have (%s)" % [phrase, str(r["must_fix_new"])])
		ok((r["human_new"] as Array).is_empty(), "'%s': HumanLimits has no finding the source segment did not have (%s)" % [phrase, str(r["human_new"])])
		var unk: Array = r["unknown"]
		var unk_ok: bool = unk.size() == row[3].size()
		for w in row[3]:
			unk_ok = unk_ok and unk.has(w)
		ok(unk_ok, "'%s': unknown words %s reported as %s" % [phrase, str(unk), str(row[3])])
		# the scene round-trips through the file format (written to user:// only)
		var path := "%s/%s.json" % [DIR, TextBlocking.slug(phrase)]
		var saved: bool = TextBlocking.save(S, B, path, r["status"])
		var back := Scene.new()
		back.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
		ok(saved and back.cards.size() == n, "'%s': saved to user:// and read back with %d cards" % [phrase, back.cards.size()])
	# ---- STRIKES: generated punches and kicks
	for row in STRIKES:
		var phrase: String = row[0]
		var r: Dictionary = TextBlocking.build(phrase, B)
		if not r["ok"]:
			ok(false, "'%s' builds: %s" % [phrase, r["error"]])
			continue
		var S: Scene = r["scene"]
		var rr := MoveRecognizer.of_scene(S, B)
		print("-- '%s' -> %s: %s" % [phrase, r["source"]["scene"], rr["text"]])
		print("   status: %s" % r["status"])
		print("   times: %s" % str(S.times().map(func(t): return [snappedf(t[0], 0.01), snappedf(t[1], 0.01), snappedf(t[2], 0.01)])))
		for f in r["findings"]:
			if f["sev"] == "FAIL":
				print("   MUST FIX %s at %.2f s: %s" % [f["rule"], f["t"], f["msg"]])
		for f in r["human"]:
			print("   human %s %s: %s" % [f["sev"], f["rule"], f["msg"]])
		ok(rr["class"] == row[1] and (row[2] == "" or String(rr.get("side", "")) == row[2]),
			"'%s': MoveRecognizer names it %s%s (wants %s%s)" % [phrase, rr["class"], (" " + String(rr.get("side", ""))) if rr.get("strike", false) else "", row[1], (" " + row[2]) if row[2] != "" else ""])
		ok(int(r["must_fix"]) == 0, "'%s': the default Check has no MUST FIX (%d)" % [phrase, int(r["must_fix"])])
		ok((r["human"] as Array).is_empty(), "'%s': HumanLimits has no finding (%s)" % [phrase, str(r["human_new"])])
		var bad := out_of_limits(B, S.cards)
		ok(bad.is_empty(), "'%s': every card's saved joint angles inside the body's limits (%d cards; out: %s)" % [phrase, S.cards.size(), str(bad)])
		var pk_t: float = r["peak_t"]
		var win: Array = r["window"]
		ok(pk_t >= float(win[0]) - 1e-3 and pk_t <= float(win[1]) + 1e-3 and float(r["peak"]) <= float(r["cap"]),
			"'%s': the %s peaks at %.1f m/s at %.2f s, inside the strike's move (%.2f-%.2f s) and under the %s cap %.1f" % [phrase, r["point"], r["peak"], pk_t, win[0], win[1], r["cap_name"], r["cap"]])
		if phrase == "front kick":   # anti-vacuity: the limit check flags a knee bent past its range
			var bent: Array = S.cards.duplicate(true)
			bent[2]["pose"]["joints"]["calf_r"]["bend"] = 200.0
			var flag := out_of_limits(B, bent)
			ok(flag.size() == 1, "anti-vacuity: a card with the knee bent 200 deg is flagged by the same check (%s)" % str(flag))
	print("TEXT BLOCKING TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
