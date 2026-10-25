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
	# ---- DANCE (beginner walk-through round 8): "dance" is a typed move, built from the templates' cards (templates/dance.json)
	# (a) "dance" builds 6+ cards, 3-6 s; (b) the pelvis moves side to side 0.15 m+ (scrubbed at 120 Hz, as the Scene plays);
	# (c) each stance foot slides under 5 mm while it is down (a contact run: the ball within 5 mm of the floor, measured from
	# where the run began) and no ball sinks more than 1 cm; (d) "dance then wave" builds the dance's cards then the wave's.
	var ed := EasyHome.new()
	var dr: Dictionary = ed._words_dict("dance")
	var built: bool = bool(dr.get("ok", false)) and (dr.get("dict", {}) as Dictionary).has("cards")
	if not built:   # every bar below fails by name when there is no clip
		var why := "no clip: %s" % str(dr.get("error", ""))
		ok(false, "(a) 'dance' builds 6+ cards and is 3-6 s (%s)" % why)
		ok(false, "(b) 'dance': the pelvis moves side to side 0.15 m+ (%s)" % why)
		ok(false, "(c) 'dance': the stance feet slide under 5 mm and no ball sinks over 1 cm (%s)" % why)
		ok(false, "(e) 'dance': the app's Check has no FAIL (%s)" % why)
		ok(false, "(h) 'dance': both hands up or together on half the count cards (%s)" % why)
		ok(false, "(i) 'dance': no hand or forearm inside the chest (%s)" % why)
	else:
			var DS := Scene.new()
			DS.from_dict(dr["dict"])
			var dn := DS.cards.size()
			var dlen := DS.length()
			print("-- 'dance' -> %d cards, %.2f s: %s" % [dn, dlen, str(DS.cards.map(func(c): return c["name"]))])
			ok(dn >= 6 and dlen >= 3.0 and dlen <= 6.0, "(a) 'dance': %d cards (6+) and %.2f s long (3-6 s)" % [dn, dlen])
			var xs := []
			var slide := {"_l": 0.0, "_r": 0.0}
			var sink := 0.0
			var run := {"_l": -1.0, "_r": -1.0}   # the contact run's start point per foot (xz), -1 = not down
			var k := 0
			while k / 120.0 <= dlen + 1e-6:
				var t: float = k / 120.0
				DS.apply(B, t)
				xs.append((B.P["pelvis"] as Vector3).x)
				for sd in ["_l", "_r"]:
					var ball: Vector3 = B.P["ball" + sd]
					var rest: Vector3 = B.p0["ball" + sd]
					sink = minf(sink, ball.y - rest.y)
					if ball.y - rest.y < 0.005:
						var at := Vector2(ball.x, ball.z)
						if run[sd] is float:   # not yet down: this frame starts the run
							run[sd] = at
						else:
							slide[sd] = maxf(slide[sd], (at - (run[sd] as Vector2)).length())
					else:
						run[sd] = -1.0
				k += 1
			var side := 0.0
			for x in xs:
				side = maxf(side, float(x))
			var lo := 9.0
			var hi := -9.0
			for x in xs:
				lo = minf(lo, float(x))
				hi = maxf(hi, float(x))
			ok(hi - lo >= 0.15, "(b) 'dance': the pelvis moves side to side %.2f m (bar 0.15: from %.2f to %.2f)" % [hi - lo, lo, hi])
			ok(maxf(slide["_l"], slide["_r"]) < 0.005, "(c) 'dance': the stance feet slide %.1f mm (left %.1f, right %.1f; bar 5)" % [maxf(slide["_l"], slide["_r"]) * 1000.0, slide["_l"] * 1000.0, slide["_r"] * 1000.0])
			ok(sink > -0.01, "(c) 'dance': no ball sinks more than 1 cm (deepest %.1f mm)" % (sink * 1000.0))
			# (e) the app's own Check (balance, gait, feet, joints): no FAIL on the dance; every finding printed
			var dfs: Array = Rulebook.check(DS, B, Rulebook.sample(DS, B))
			var dfail := dfs.filter(func(f): return f["sev"] == "FAIL")
			for f in dfs:
				if f["sev"] != "OK":
					print("   check %s %s %.2f s: %s" % [f["sev"], f["rule"], f["t"], f["msg"]])
			ok(dfail.is_empty(), "(e) 'dance': the app's Check has no FAIL (%d)" % dfail.size())
			# (f) THE ARMS GO UP (a beginner reads a dance by the arms): at each count card's arrival (times()[i][1]) at least one
			# hand is above its shoulder (world y, the upper arm's start) on at least half the cards; (g) the hands travel 1.5 m+
			# in total (both hands' path, summed over the 120 Hz scrub the Scene plays)
			var tms: Array = DS.times()
			var up_cards := 0
			for ci in DS.cards.size():
				DS.apply(B, float(tms[ci][1]))
				var hl0: Vector3 = B.P["hand_l"]
				var hr0: Vector3 = B.P["hand_r"]
				if hl0.y > (B.P["upperarm_l"] as Vector3).y or hr0.y > (B.P["upperarm_r"] as Vector3).y:
					up_cards += 1
			ok(up_cards * 2 >= DS.cards.size(), "(f) 'dance': a hand is above its shoulder on %d of %d count cards (bar: half)" % [up_cards, DS.cards.size()])
			# the hands' own travel: measured from the pelvis (the hands ride the sway of the hips: that is the body moving, not
			# the arms); the room's travel is printed beside it
			var travel := 0.0
			var room := 0.0
			var prev_rel := [Vector3.ZERO, Vector3.ZERO]
			var prev_world := [Vector3.ZERO, Vector3.ZERO]
			k = 0
			while k / 120.0 <= dlen + 1e-6:
				DS.apply(B, k / 120.0)
				var pv: Vector3 = B.P["pelvis"]
				var hw := [B.P["hand_l"] as Vector3, B.P["hand_r"] as Vector3]
				for hh in 2:
					var rel: Vector3 = (hw[hh] as Vector3) - pv
					if k > 0:
						travel += rel.distance_to(prev_rel[hh])
						room += (hw[hh] as Vector3).distance_to(prev_world[hh])
					prev_rel[hh] = rel
					prev_world[hh] = hw[hh]
				k += 1
			print("-- 'dance' hands: %.2f m from the pelvis, %.2f m in the room" % [travel, room])
			ok(travel >= 1.5, "(g) GUARD 'dance': the hands travel %.2f m in total from the pelvis (bar 1.5; in the room %.2f m; passes on the old dance, so a guard, not fail-first)" % [travel, room])
			# (h) THE PARTY READ (round 9): both arms move on the count, as a raise or a clap: on at least half the count cards BOTH
			# hands are above their shoulders (world y), or the two hands are within 15 cm of each other (a clap)
			var both := 0
			var closest := 9.0
			for ci in DS.cards.size():
				DS.apply(B, float(tms[ci][1]))
				var hl1: Vector3 = B.P["hand_l"]
				var hr1: Vector3 = B.P["hand_r"]
				var both_up := hl1.y > (B.P["upperarm_l"] as Vector3).y and hr1.y > (B.P["upperarm_r"] as Vector3).y
				closest = minf(closest, hl1.distance_to(hr1))
				if both_up or hl1.distance_to(hr1) < 0.15:
					both += 1
			print("-- 'dance' closest wrists %.1f cm" % (closest * 100.0))
			ok(both * 2 >= DS.cards.size(), "(h) 'dance': both hands up or together (a clap) on %d of %d count cards (bar: half)" % [both, DS.cards.size()])
			# (i) NO HAND OR FOREARM INSIDE THE CHEST (round 9): the bake's own self-contact check (Scene.check, the bad_frames the
			# file records) has no hand or forearm touching the chest, the collarbones or the spine in any frame. Hand on hand (a clap) is not counted here
			var chest_hits := 0
			for bf in DS.check(B):
				for pr in bf[2]:
					var pa: String = pr[0]
					var pb: String = pr[1]
					if (pa.begins_with("hand") or pa.begins_with("lowerarm")) and (pb.contains("spine") or pb.contains("chest") or pb.contains("clavicle")):
						chest_hits += 1
					elif (pb.begins_with("hand") or pb.begins_with("lowerarm")) and (pa.contains("spine") or pa.contains("chest") or pa.contains("clavicle")):
						chest_hits += 1
			ok(chest_hits == 0, "(i) 'dance': no hand or forearm inside the chest in any frame (%d contacts with the chest, collarbones or spine; the bake's check)" % chest_hits)
	var dw: Dictionary = ed._words_dict("dance then wave")
	ok(bool(dw.get("ok", false)) and dw.has("dict") and (dw["dict"]["cards"] as Array).size() > 12, "(d) 'dance then wave' builds the dance's cards then the wave's (%s cards)" % str((dw.get("dict", {}) as Dictionary).get("cards", []).size()))
	# ---- TYPED GRAMMAR (round 10): repeats, turns and filler in Easy's typed line (section 10 below)
	fails += typed_bars(ed)
	print("TEXT BLOCKING TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)


## ---- 10. TYPED GRAMMAR (round 10, Easy's typed line). Each phrase must build (no "doesn't know"), and what it asks is MEASURED on the
## built scene, scrubbed at 120 Hz as the Scene plays: "jump twice" and "jump twice then turn around" have 2 airborne spans (both feet
## 2 cm+ above the floor, the body's rest; a span = one jump); "walk forward then jump" has 1; "punch 3 times" has 3 punch moves (the
## cards' move tags: one per punch); the turns ("turn around", "spin around", "walk then turn around", "jump twice then turn around")
## end with the hips' yaw 180 deg +- 15 from the start (TextView.yaw); "punch 11 times" caps at 10 with the say (the note). Also: "jump zorp"
## still refused with "doesn't know". Returns the number of FAILs. Static: the bars also run alone (a copy with the old files).
## The turns: templates turn_* (scripts/turn_walk.gd; tests/turn_test.gd measures them alone and joined)
const TYPED_BUILDS := ["jump twice", "jump twice then turn around", "walk forward then jump", "walk then turn around", "punch 3 times", "turn around", "spin around"]


static func _tbar(c: bool, what: String) -> int:
	print(("ok   " if c else "FAIL ") + what)
	return 0 if c else 1


static func _airborne_spans(DS: Scene, B: Body) -> int:
	var n := 0
	var inair := false
	var k := 0
	while k / 120.0 <= DS.length() + 1e-6:
		DS.apply(B, k / 120.0)
		var up := true
		for sd in ["_l", "_r"]:
			up = up and ((B.P["ball" + sd] as Vector3).y - (B.p0["ball" + sd] as Vector3).y) > 0.02
		if up and not inair:
			n += 1
		inair = up
		k += 1
	return n


static func _both_up_frames(DS: Scene, B: Body, bar: float) -> int:
	var n := 0
	var k := 0
	while k / 120.0 <= DS.length() + 1e-6:
		DS.apply(B, k / 120.0)
		var up := true
		for sd in ["_l", "_r"]:
			up = up and ((B.P["ball" + sd] as Vector3).y - (B.p0["ball" + sd] as Vector3).y) > bar
		if up:
			n += 1
		k += 1
	return n


static func _yaw_change(DS: Scene, B: Body) -> float:
	DS.apply(B, 0.0)
	var y0 := TextView.yaw(B)
	DS.apply(B, DS.length())
	var y1 := TextView.yaw(B)
	return wrapf(y1 - y0, -180.0, 180.0)


static func typed_bars(ed: EasyHome) -> int:
	var fails := 0
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	for phrase in TYPED_BUILDS:
		var r: Dictionary = ed._words_dict(phrase)
		var err := String(r.get("error", ""))
		var built: bool = bool(r.get("ok", false)) and not err.begins_with("Kine doesn't know")
		fails += _tbar(built, "'%s' builds a clip, no \"doesn't know\" (%s)" % [phrase, err if not built else "%d cards" % (r["dict"]["cards"] as Array).size()])
		if not built:
			continue
		var DS := Scene.new()
		DS.from_dict(r["dict"])
		var cards: Array = r["dict"]["cards"]
		if phrase.begins_with("jump") or phrase.begins_with("walk forward"):
			var want := 2 if phrase.begins_with("jump twice") else 1
			var spans := _airborne_spans(DS, B)
			fails += _tbar(spans == want, "'%s': %d airborne spans (both feet 2 cm+ up), want %d" % [phrase, spans, want])
		if phrase.begins_with("punch"):
			var moves := {}
			for c in cards:
				moves[String(c.get("from", ""))] = true
			fails += _tbar(moves.size() == 3, "'%s': %d punch moves in the clip (one tag per punch), want 3" % [phrase, moves.size()])
		if phrase == "turn around":   # round 10 (the floor): a turn never lifts both feet off the floor; 0 frames with both feet over 1 cm up
			var both_up := _both_up_frames(DS, B, 0.01)
			fails += _tbar(both_up == 0, "'turn around' alone: %d frames with both feet over 1 cm above the floor (bar 0: a turn is never a hop)" % both_up)
		if phrase.ends_with("turn around") or phrase.begins_with("turn") or phrase.begins_with("spin"):
			var yc := _yaw_change(DS, B)
			fails += _tbar(absf(yc) >= 165.0 and absf(yc) <= 195.0, "'%s': the hips' yaw ends %.1f deg from the start (180 +- 15)" % [phrase, yc])
	var cap: Dictionary = ed._words_dict("punch 11 times")
	var capped_moves := {}
	if bool(cap.get("ok", false)):
		for c in (cap["dict"]["cards"] as Array):
			capped_moves[String(c.get("from", ""))] = true
	fails += _tbar(bool(cap.get("ok", false)) and capped_moves.size() == 10 and String(cap.get("note", "")).contains("10 times"),
		"'punch 11 times' caps at 10 punches with the say '%s' (%d punch moves)" % [String(cap.get("note", "")), capped_moves.size()])
	var nope: Dictionary = ed._words_dict("jump zorp")
	fails += _tbar(not bool(nope.get("ok", true)) and String(nope.get("error", "")).begins_with("Kine doesn't know"),
		"'jump zorp' is still refused: \"doesn't know\" (unknown words stay unknown)")
	return fails
