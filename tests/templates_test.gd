## godot --path . -s tests/templates_test.gd     (ROADMAP 44; needs a window for the picker picture)
## NEW FROM TEMPLATE: walk, run, jump, punch, sword swing as starting scenes (templates/*.json, built by
## tools/make_templates.gd). Each template is BUILT (read, sampled the way the app's own checks sample) and MEASURED against
## real people. The bars are fixed here before any number is read:
##   WALK   cadence 100-120 steps/min (105.5 +- 5.2, PMID 29775941; 108 +- 7, PMID 41879248); stride (2 steps) 0.75-0.85 x height
##          (step 0.415 +- 0.038 of height, PMID 19502061; Kubo 2004 PMID 15351887); arm swing 14-44 deg peak to peak (25-33 +- 11,
##          PMID 40291287, 23236504) and each arm against the same-side thigh (r < 0)
##   RUN    cadence 160-180 steps/min (preferred step rate ~170, Heiderscheit 2011); a flight phase (both balls of the feet more
##          than 3 cm off the floor) of 0.05-0.15 s (Novacheck 1998: running = a flight phase; ~0.1 s at a jog)
##   JUMP   flight T gives g T^2/8 = 0.29-0.51 m (a recreational CMJ 0.40 +- 0.11 m; Bosco; Asmussen & Bonde-Petersen);
##          countermovement knee bend 70-110 deg (~90, DeVita & Skelly 1992); take-off knee bend at leaving the floor <= 35 deg
##          (the leg is nearly straight at toe-off)
##   PUNCH  cross: peak fist speed 7-11 m/s (straight 9.3 +- 2.1, Piorkowski 2011; Stanley 2018 fastest 11.95 +- 1.84 is the cap)
##   SWORD  from the bat swing data (ISBS 2015: pelvis 389, trunk 601, bat 1953 deg/s): the hips turn >= 97 deg/s (a quarter of 389),
##          the tip tops out at 15-40 m/s (docs/ATTACK_RULES.md pro bat 37-40), the strike lasts <= 6 frames at 30 fps (Aztez)
## EVERY template: the app's own checks (Rulebook.check incl. FOOT SLIDE, HumanLimits.findings) find nothing, Critique has no
## WARN/FAIL (NOTEs are advice); the toe joint never bends past 45 deg (in swing <= 10 deg, except in a run or jump's flight).
## CREATE: Templates.create writes a NEW file (_2, _3), never over one, and never touches templates/. The picker lists seven.
## ROUNDHOUSE (the Easy home's Kick card, baked by tools/make_templates.gd -- roundhouse): the file is the live build, every joint within
## 0.01 deg of it at 60 Hz, and MoveRecognizer names it a roundhouse.
## CONTROL (anti-vacuity): the jump is not read as a walk and the walk has no flight, so those bars have teeth.
##   SIT DOWN (Props "chair", seat top 0.45 m; the cards are scripts/rise.gd's keys played backwards, retimed): the hips' lowest surface
##          reaches the seat top (0.45 m) within 5 cm and stays there at the end; the first contact is at 1.0-1.4 s (the hips lower
##          onto the seat in about 1.0-1.4 s, Schenkman 1990: the seat-off is at 35-40 % of the rise). The seat holds the weight
##          (Balance.seat_pts), so the BALANCE and TIPPING findings are read with the seat under him.
##   WAVE   the right hand's highest point passes the head's top (hand above head height, bar: >= the head's top); the hand swings
##          side to side at least 2 times: 2 reversals of its lateral (x) position at least 5 cm past the last turn.
##   FALL   NOT YET A TEMPLATE (the head-clear and body-ends-lying bars are written when it is): see the report.
extends SceneTree

var fails := 0
var m: Node
const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/templates.png"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func inr(v: float, lo: float, hi: float) -> bool:
	return v >= lo and v <= hi


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	return B


func build(nm: String) -> Scene:
	var S := Scene.new()
	S.from_dict(Templates.read(nm))
	return S


## what the app's checks say, as lines
func findings(S: Scene, B: Body, sm: Dictionary) -> Array:
	var out := []
	for f in Rulebook.check(S, B, sm):
		out.append("%s %s %.2f %s" % [f["sev"], f["rule"], f["t"], f["msg"]])
	for f in Critique.check(S, B, sm):
		if f["sev"] != "NOTE":
			out.append("critique %s %s %.2f" % [f["sev"], f["rule"], f["t"]])
	for f in HumanLimits.findings(S, B):
		out.append("human %s %s %.2f %s" % [f["sev"], f["rule"], f["t"], f["msg"]])
	return out


## toes over the scene at 120 Hz: {"toe": most bend, "swing": most |bend| with the foot > 2 cm up}
func feet(S: Scene, B: Body) -> Dictionary:
	var toe := 0.0
	var swing := 0.0
	var k := 0
	while k / 120.0 <= S.length():
		S.apply(B, k / 120.0)
		for sd in ["_l", "_r"]:
			var b: float = (B.ang["ball" + sd] as Vector3).x
			var lift: float = (B.P["ball" + sd] as Vector3).y - (B.p0["ball" + sd] as Vector3).y
			toe = maxf(toe, b)
			if lift > 0.02:
				swing = maxf(swing, absf(b))
		k += 1
	return {"toe": toe, "swing": swing}


## the flights of a scene (Scene.flights: take-off card's leave to the landing card's arrival): {"n", "T" the median, "mid": the
## lowest ball over the floor at the middle of each flight}
func flights(S: Scene, B: Body) -> Dictionary:
	var ts := []
	var low := 9.0
	for f in S.flights():
		ts.append(float(f["t1"]) - float(f["t0"]))
		S.apply(B, (float(f["t0"]) + float(f["t1"])) * 0.5)
		low = minf(low, minf((B.P["ball_l"] as Vector3).y, (B.P["ball_r"] as Vector3).y))
	ts.sort()
	return {"n": ts.size(), "T": 0.0 if ts.is_empty() else float(ts[ts.size() / 2]), "mid": low}


func peak(a: Array) -> float:
	var p := 0.0
	for v in a:
		p = maxf(p, v)
	return p


func _init() -> void:
	var B := body()
	ok(Templates.NAMES.size() == 7, "seven templates listed (was five; sit down and wave added): %s" % [Templates.NAMES])
	for nm in Templates.NAMES:
		var S0 := build(nm)
		var sm0 := Rulebook.sample(S0, B)
		var fl := findings(S0, B, sm0)
		print("     %s: %d cards, %.2f s" % [nm, S0.cards.size(), S0.length()])
		ok(fl.is_empty(), "%s: no Rulebook / Critique / HumanLimits finding (%s)" % [nm, "; ".join(fl).left(300)])
		var ft := feet(S0, B)
		var air_ok: bool = nm == "run" or nm == "jump"
		ok(float(ft["toe"]) <= 45.0 + 1e-3, "%s: toe bend %.1f deg at most (bar <= 45, first MTP peak 40-45 walking, Miana 2021)" % [nm, ft["toe"]])
		ok(air_ok or float(ft["swing"]) <= 10.0 + 1e-3, "%s: toe within %.1f deg of level in swing (bar <= 10, Perry 1992)%s" % [nm, ft["swing"], " (flight: exempt)" if air_ok else ""])
		B = body()

	# WALK
	var S := build("walk")
	var sm := Rulebook.sample(S, B)
	var g := Rulebook.gait(sm)
	print("     walk: cadence %.1f /min, step %.3f of height (stride %.3f), arm %.1f deg, arm/thigh r %.2f" % [g["cad"], g["step"], 2.0 * float(g["step"]), g["arm"], g["phase"]])
	ok(g["walk"] and inr(float(g["cad"]), 100.0, 120.0), "walk: cadence %.1f steps/min inside 100-120" % g["cad"])
	ok(inr(2.0 * float(g["step"]), 0.75, 0.85), "walk: stride %.3f x height inside 0.75-0.85" % (2.0 * float(g["step"])))
	ok(inr(float(g["arm"]), 14.0, 44.0) and float(g["phase"]) < 0.0, "walk: arm swing %.1f deg inside 14-44, counter-phase to the legs (r %.2f)" % [g["arm"], g["phase"]])
	# CONTROL: the jump is not a walk, so the walk bars cannot pass on it by emptiness
	var Sj := build("jump")
	var gj := Rulebook.gait(Rulebook.sample(Sj, B))
	ok(not gj["walk"], "control: the jump template is not read as a walk (%s)" % gj.get("why", ""))

	# RUN
	var Sr := build("run")
	var smr := Rulebook.sample(Sr, B)
	var gr := Rulebook.gait(smr)
	var fr_run := flights(Sr, B)
	var fs: float = fr_run["T"]
	print("     run: cadence %.1f /min, %d flights of %.3f s, lowest ball mid-flight %.3f m" % [gr["cad"], fr_run["n"], fs, fr_run["mid"]])
	ok(inr(float(gr["cad"]), 160.0, 180.0), "run: cadence %.1f steps/min inside 160-180" % gr["cad"])
	ok(Rulebook.has_flight(Sr) and inr(fs, 0.05, 0.15) and float(fr_run["mid"]) > 0.045, "run: a flight phase of %.3f s inside 0.05-0.15, both balls clear of the floor in the middle of it (%.3f m, a flat ball stands at 0.033)" % [fs, fr_run["mid"]])
	ok(not Rulebook.has_flight(S), "control: the walk has no flight phase")

	# JUMP
	var js := Rulebook.jumps(Sj, B)
	ok(js.size() == 1, "jump: one flight (%d)" % js.size())
	if js.size() == 1:
		var j: Dictionary = js[0]
		Sj.apply(B, float(j["t0"]))
		var to_knee: float = maxf((B.ang["calf_l"] as Vector3).x, (B.ang["calf_r"] as Vector3).x)
		print("     jump: T %.3f s -> %.2f m, dip %.0f deg, take-off knee %.0f deg, landing %.0f deg" % [j["T"], j["h"], j["dip"], to_knee, j["land"]])
		ok(inr(float(j["h"]), 0.29, 0.51), "jump: flight %.3f s means a %.2f m jump, inside 0.29-0.51 (CMJ 0.40 +- 0.11)" % [j["T"], j["h"]])
		ok(inr(float(j["dip"]), 70.0, 110.0), "jump: countermovement knee bend %.0f deg inside 70-110 (~90, DeVita & Skelly 1992)" % j["dip"])
		ok(to_knee <= 35.0, "jump: take-off knee bend %.0f deg at most 35 (nearly straight at toe-off)" % to_knee)

	# PUNCH
	var Sp := build("punch")
	var smp := Rulebook.sample(Sp, B)
	var pk := maxf(peak(smp["hand_l"]), peak(smp["hand_r"]))
	var pk_walk := maxf(peak(sm["hand_l"]), peak(sm["hand_r"]))
	print("     punch: peak fist speed %.2f m/s (walk hands %.2f)" % [pk, pk_walk])
	ok(inr(pk, 7.0, 11.0), "punch: peak fist speed %.2f m/s inside 7-11 (Piorkowski 2011 9.3 +- 2.1; Stanley 2018 cap 11.95)" % pk)
	ok(pk > 2.0 * pk_walk, "control: the punch's fist is more than twice the walk's hand speed (%.2f vs %.2f m/s)" % [pk, pk_walk])

	# SWORD SWING
	var Ss := build("sword_swing")
	var sms := Rulebook.sample(Ss, B)
	var sts := Rulebook.strikes(sms["tip"])
	var tip := peak(sms["tip"])
	var hips := peak(sms["w_pelvis"])
	var fr := 99.0
	if not sts.is_empty():
		fr = (sts[0]["b"] - sts[0]["a"] + 1) * 30.0 / Rulebook.FPS
	print("     sword: tip %.1f m/s, hips %.0f deg/s, strike %.0f frames at 30 fps, %d strike(s)" % [tip, hips, fr, sts.size()])
	ok(sts.size() >= 1 and inr(tip, 15.0, 40.0), "sword: blade tip %.1f m/s inside 15-40 (pro bat 37-40, ATTACK_RULES)" % tip)
	ok(hips >= 97.0, "sword: the hips turn %.0f deg/s, at least 97 (a quarter of the bat swing's 389, ISBS 2015)" % hips)
	ok(fr <= 6.0, "sword: the strike lasts %.0f frames at 30 fps, at most 6 (Aztez)" % fr)
	ok(sms["armed"], "sword: the scene carries the blade (a bat stand-in, 1.0 m)")

	# SIT DOWN
	var Sit := build("sit_down")
	var sb := body()
	var seat_top := 0.45
	var lo_end := 0.0
	var first := -1.0
	var kk := 0
	while kk / 60.0 <= Sit.length():
		Sit.apply(sb, kk / 60.0)
		var hc: Array = sb.cap("hips_wide")
		var lo := minf((hc[0] as Vector3).y, (hc[1] as Vector3).y) - float(sb.rad["hips_wide"])
		if first < 0.0 and absf(lo - seat_top) <= 0.01:
			first = kk / 60.0
		lo_end = lo
		kk += 1
	var pelvis_end: float = (sb.P["pelvis"] as Vector3).y
	print("     sit: hips' lowest surface %.3f m at the end (seat top 0.45), pelvis joint %.3f m, first contact %.2f s" % [lo_end, pelvis_end, first])
	ok(absf(lo_end - seat_top) <= 0.05, "sit: the hips' lowest surface ends %.3f m, within 5 cm of the seat top 0.45 m" % lo_end)
	ok(inr(first, 1.0, 1.4), "sit: the hips reach the seat at %.2f s, inside 1.0-1.4 s" % first)

	# WAVE
	var Wv := build("wave")
	var wb := body()
	var head_top := -9.0
	var hand_top := -9.0
	var xs := []
	kk = 0
	while kk / 60.0 <= Wv.length():
		Wv.apply(wb, kk / 60.0)
		var hc2: Array = wb.cap("head")
		head_top = maxf(head_top, maxf((hc2[0] as Vector3).y, (hc2[1] as Vector3).y) + float(wb.rad["head"]))
		hand_top = maxf(hand_top, (wb.P["hand_r"] as Vector3).y)
		xs.append((wb.P["hand_r"] as Vector3).x)
		kk += 1
	var turns := 0
	var last: float = xs[0]
	var dirn := 0
	for x in xs:
		var dx: float = float(x) - last
		if absf(dx) >= 0.05:
			var d := 1 if dx > 0.0 else -1
			if dirn != 0 and d != dirn:
				turns += 1
			dirn = d
			last = x
	print("     wave: hand_r top %.3f m, head top %.3f m, lateral turns %d" % [hand_top, head_top, turns])
	ok(hand_top >= head_top, "wave: the hand's top %.3f m passes the head's top %.3f m" % [hand_top, head_top])
	ok(turns >= 2, "wave: the hand swings side to side %d times, at least 2" % turns)

	# CREATE never overwrites, never writes templates/
	var dir := "user://zz_templates_test"
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	var before := FileAccess.get_file_as_string("res://templates/walk.json")
	var p1 := Templates.create("walk", dir)
	var p2 := Templates.create("walk", dir)
	var p3 := Templates.create("walk", dir)
	ok(p1.get_file() == "walk.json" and p2.get_file() == "walk_2.json" and p3.get_file() == "walk_3.json", "create: walk.json, walk_2.json, walk_3.json (%s %s %s)" % [p1.get_file(), p2.get_file(), p3.get_file()])
	var d2: Variant = JSON.parse_string(FileAccess.get_file_as_string(p2))
	ok(d2 is Dictionary and d2["scene"] == "walk_2" and (d2["cards"] as Array).size() == build("walk").cards.size(), "create: the copy is a whole scene named walk_2")
	ok(FileAccess.get_file_as_string("res://templates/walk.json") == before, "create: templates/walk.json is untouched")
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))

	# THE BAKED KICK (templates/roundhouse.json, the Easy home's Kick card): the file must be the build the card made live
	# (StrikeBlocking through TextBlocking, JSON-written the way main._write writes it), move for move. Bars, fixed before the
	# numbers: every joint's bend, side and twist within 0.01 deg of the live build at 60 Hz; the recognizer names it a roundhouse.
	# Anti-vacuity: a copy with one joint 0.05 deg off must read 0.05 (the comparison can see a difference that size).
	var H := EasyHome.new()
	var rl: Dictionary = H._words_dict("roundhouse")
	ok(rl["ok"], "roundhouse: the live build (TextBlocking, the words 'roundhouse') builds")
	var live: Dictionary = JSON.parse_string(JSON.stringify(rl["dict"], " "))   # what Easy's card wrote and loaded
	var filed: Dictionary = Templates.read("roundhouse")
	ok(not filed.is_empty(), "roundhouse: templates/roundhouse.json is there and reads")
	var filed_cmp: Dictionary = filed.duplicate()
	filed_cmp.erase("plan")   # the file's own note (who baked it); the card writes its plan line over it anyway
	ok(filed_cmp == live, "roundhouse: the file IS the live build (same cards, poses, timing; %d cards; plan note aside)" % (filed.get("cards", []) as Array).size())
	var SL := Scene.new()
	SL.from_dict(live)
	var SF := Scene.new()
	SF.from_dict(filed)
	var BL := body()
	var BF := body()
	var worst := 0.0
	var worst_at := ""
	var samples := 0
	var joints_n := 0
	var same_joints := true
	var L := SL.length()
	var k := 0
	while k / 60.0 <= L + 1e-6:
		var t := k / 60.0
		SL.apply(BL, t)
		SF.apply(BF, t)
		var jl: Array = BL.ang.keys()
		var jf: Array = BF.ang.keys()
		if jl.size() != jf.size():
			same_joints = false
		joints_n = jl.size()
		for j in jl:
			var dv: Vector3 = (BL.ang[j] as Vector3) - (BF.ang[j] as Vector3)
			var dd := maxf(absf(dv.x), maxf(absf(dv.y), absf(dv.z)))
			if dd > worst:
				worst = dd
				worst_at = "%s at %.4f s" % [j, t]
		samples += 1
		k += 1
	ok(same_joints and samples > 60, "roundhouse: %d samples at 60 Hz over %.2f s, %d joints each, the same joint set" % [samples, L, joints_n])
	print("roundhouse 60 Hz: max joint diff %.5f deg (%s)" % [worst, worst_at])
	ok(worst <= 0.01, "roundhouse: every joint within 0.01 deg of the live build at 60 Hz (max %.5f deg)" % worst)
	# anti-vacuity: the same comparison with one joint 0.05 deg off must read 0.05
	var BP := body()
	SF.apply(BP, 0.5)
	BP.ang["thigh_r"] = (BP.ang["thigh_r"] as Vector3) + Vector3(0.05, 0, 0)
	var BQ := body()
	SL.apply(BQ, 0.5)
	var dq: Vector3 = (BQ.ang["thigh_r"] as Vector3) - (BP.ang["thigh_r"] as Vector3)
	ok(absf(dq.x) > 0.049 and absf(dq.x) < 0.051, "roundhouse anti-vacuity: a 0.05 deg joint change reads as %.3f deg" % absf(dq.x))
	# the recognizer names the baked clip
	var BR := body()
	SF.apply(BR, 0.0)
	var rec := MoveRecognizer.of_scene(SF, BR)
	print("roundhouse recognizer: class %s, strike %s, side %s" % [str(rec.get("class")), str(rec.get("strike")), str(rec.get("side"))])
	ok(String(rec.get("class", "")) == "roundhouse" and bool(rec.get("strike", false)), "roundhouse: MoveRecognizer says 'roundhouse' (%s)" % String(rec.get("class", "")))
	H.free()

	# THE PICKER
	m = (load("res://main.tscn") as PackedScene).instantiate()
	m.settings = "user://zz_templates_test.cfg"   # never the real poser.cfg
	root.add_child(m)
	await process_frame
	await process_frame
	m._template_ask()
	await process_frame
	await process_frame
	ok(m.ui_tpl_dlg.visible and m.ui_tpl_list.item_count == 7, "picker: a dialog with seven templates (%d)" % m.ui_tpl_list.item_count)
	m.ui_tpl_list.select(4)
	m._template_blurb(4)
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(SHOT.get_base_dir())
	var img: Image = root.get_viewport().get_texture().get_image()
	ok(img.save_png(SHOT) == OK, "picker: picture saved %s" % SHOT)
	ok(m.ui_tpl_blurb.text.length() > 20, "picker: the blurb of the pick is shown (%s)" % m.ui_tpl_blurb.text.left(60))
	m._template_build()
	await process_frame
	var made := "res://scenes/_wip/%s.json" % m.S.name
	ok(m.S.name.begins_with("sword_swing") and m.S.cards.size() == 5 and FileAccess.file_exists(made), "picker: Make the scene opens a new scene %s (5 cards) in scenes/_wip" % m.S.name)
	if FileAccess.file_exists(made):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(made))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
	print("TEMPLATES: %d failed" % fails)
	quit(1 if fails > 0 else 0)
