## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/n040_test.gd   (INNOVATIONS N040: throw truth, scripts/throw_truth.gd
## + throw_fixtures.gd + throw_truth_strip.gd + throw_truth_pair.gd; a window for the two PNGs)
## The question: a throw works only when the partner's centre of mass is pulled outside his feet (kuzushi) AND the thrower's own balance holds.
## Partner test = extrapolated COM (capture point, I39/Hof 2005) outside his support polygon by more than Balance.MARGIN_RES (2 cm);
## thrower test = his COM margin >= -MARGIN_RES (balance.gd). Verdict taken at the KEY FRAME: of the frames where the bodies touch, the one where the
## partner is most off balance (latest of equals).
## DISCLOSURE (recorded, not hidden): before this file's first run the fixture builder was developed with an exploratory probe (tests/zz_n040_probe*.gd,
## not committed). That probe changed the FIXTURES (the hands pointed at the wrong shoulders; the thrower needed a step in to keep his grip as the
## partner leaned away; the first clip verdict used a SUSTAIN-frames rule that read an overcommitted clip as "throw works" for its first 3 frames,
## replaced by the key-frame rule above). No bar below was changed after seeing a run of THIS file.
## Real reference: Imamura RT, Hreljac A, Escamilla RF, Edwards WB (2006), J Sports Sci Med 5(CSSI):122-131, https://jssm.org/jssm-05-CSSI1-122.xml-Fulltext :
## harai-goshi, uke's COM linear momentum forward in the kuzushi phase 20.6 kg m/s (tsukuri 52.6). Also Rexhepi & Hraski 2011 Sport Mont 9(31-33):249-255
## (osoto-gari tsukuri, uke COM moved 6.10 cm sideways, tori 72 kg; abstract only, cited for context, not used as a bar).
## Bars, written before the first run (scene fps 30; thrower = the hero at the origin; partner 0.8 m in front at yaw 180; Balance/Body are the app's):
##  1 OSOTO (kuzushi works): verdict "throw works"; at the key frame the partner is > 2 cm outside (extrapolated), the thrower's margin >= -2 cm,
##    >= 1 grip, the partner's direction word is "back"; the test's OWN recompute (poses the bodies itself, Balance.read, COM velocity from the
##    previous frame, xi = com + v / sqrt(g/h)) gives the same partner "out" and thrower margin within 1 mm.
##  2 NO KUZUSHI: the same thrower cards (byte-identical hero cards to osoto's), partner not pulled: verdict "no kuzushi"; the partner's out is
##    <= 2 cm on EVERY frame; the bodies touch; the words say "NO KUZUSHI" and "thrower" holds (missing == ["kuzushi"] only).
##  3 OVERCOMMIT: the partner's cards byte-identical to osoto's, the thrower throws himself: verdict "thrower falls"; partner out > 2 cm and thrower
##    margin < -2 cm at the key frame; missing == ["thrower balance"]; the words say "THROWER FALLS".
##  4 APART: osoto with the partner 3 m further: verdict "no contact"; no frame has a contact point; the closest approach > 1 m; words "NO CONTACT".
##  5 REAL NUMBER (Imamura): the partner leans forward so that the mean COM momentum over the 0.5 s move (own recompute from Balance.com
##    positions and HitReaction masses) is 20.6 kg m/s within 10 %; xi at the peak-speed frame = com + v/w0 within 1 mm (own recompute); the grip is
##    kept on >= 1 frame. The verdict at that momentum is PRINTED (no bar on it: it is a finding, not a target).
##  6 WORDS + JSON: every fixture's words carry its verdict term (upper case); the JSON round-trips through JSON.stringify/parse with verdict,
##    frame, frames[key].partner.out_m, frames[key].thrower.margin_m equal to the numbers within 0.1 mm; the points carry thrower_part, partner_part, at.
##  7 ROLE SWAP: osoto judged with the PARTNER as the thrower (thrower=1) is not "throw works" (the hero is not pulled off his feet).
##  8 SWEEPS: pull angle 0 .. -30 in 2.5 deg steps: the verdict flips from "no kuzushi" to "throw works" exactly once and the key-frame out straddles
##    2 cm across the flip (last "no kuzushi" <= 2 cm < first "throw works"); the thrower's feet-behind shift 0 .. 0.30 m in 0.025 m steps flips
##    "throw works" to "thrower falls" exactly once, the margin straddling -2 cm.
##  9 PICTURES (window): the strip's verdict ribbon at each clip's key frame has the colour of its verdict (green, yellow, red, grey); the PNG is not blank
##    (>= 6 colours); the pair render of the osoto key frame has the thrower's plan dot green and a red partner arrow pixel; of the overcommit
##    key frame, the thrower's dot red.
## 10 PLANTED CONTROLS (WRONG claims; the line is ok only when the claim is false): C1 the no-kuzushi clip is "throw works"; C2 the overcommit clip is
##    "throw works"; C3 the apart clip has a contact; C4 the osoto words say "NO KUZUSHI"; C5 osoto with the roles swapped is "throw works";
##    C6 osoto's key-frame out is <= 2 cm; C7 the imamura clip's mean momentum is within 10 % of the TSUKURI value 52.6; C8 the strip ribbon pixel of
##    the overcommit clip is green; C9 a hand-built one-card scene with a single fighter judged as a pair reports ok.
extends SceneTree

var fails := 0
const FPS := 30


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func control(claim: bool, what: String) -> void:
	print(("ok   control caught: " if not claim else "FAIL control NOT caught: ") + what)
	if claim:
		fails += 1


func hero_cards(S: Scene) -> String:
	return JSON.stringify(S.cards)


func partner_cards(S: Scene) -> String:
	return JSON.stringify((S.actors[0]["scene"] as Scene).cards)


## the test's own read of the partner at frame f (hero space numbers not needed: own space is a rigid move): {out, thr_margin}
func own_read(S: Scene, f: int) -> Dictionary:
	var hb := ThrowTruth.new_body()
	var pb := ThrowTruth.new_body()
	var ps := ThrowTruth.new_body()
	var psc: Scene = S.actors[0]["scene"]
	S.apply(hb, float(f) / FPS)
	hb.fk()
	psc.apply(pb, float(f) / FPS)
	pb.fk()
	var v := Vector3.ZERO
	if f > 0:
		psc.apply(ps, float(f - 1) / FPS)
		ps.fk()
		v = (Balance.com(pb) - Balance.com(ps)) * FPS
	var r := Balance.read(pb)
	var c: Vector3 = r["com"]
	var w0 := sqrt(9.81 / maxf(c.y, 0.3))
	var xi := Vector2(c.x + v.x / w0, c.z + v.z / w0)
	var md := Balance.signed_dist(r["poly"], xi)
	return {"out": maxf(0.0, -md), "thr": float(Balance.read(hb)["margin"]), "xi": xi, "com": c, "w0": w0}


func jround(r: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(ThrowTruth.to_json(r)))


func _init() -> void:
	var A := ThrowFixtures.build("osoto")
	var N := ThrowFixtures.build("no_kuzushi")
	var O := ThrowFixtures.build("overcommit")
	var X := ThrowFixtures.build("apart")
	var I := ThrowFixtures.build("imamura")
	var rA := ThrowTruth.judge(A, FPS)
	var rN := ThrowTruth.judge(N, FPS)
	var rO := ThrowTruth.judge(O, FPS)
	var rX := ThrowTruth.judge(X, FPS)
	var rI := ThrowTruth.judge(I, FPS)
	for p in [["osoto", rA], ["no_kuzushi", rN], ["overcommit", rO], ["apart", rX], ["imamura", rI]]:
		print("-- ", p[0], ": ", (p[1] as Dictionary)["text"])
	var res := Balance.MARGIN_RES

	# 1 osoto
	var kA: int = rA["frame"]
	var fA: Dictionary = rA["frames"][kA]
	var oA := own_read(A, kA)
	ok(rA["verdict"] == "throw works" and float(fA["partner"]["out"]) > res and float(fA["thrower"]["margin"]) >= -res and int(fA["grips"]) >= 1 and fA["partner"]["dir_own"] == "back",
		"1 osoto: throw works at f %d; partner out %.1f cm, thrower margin %.1f cm, %d grips, direction %s" % [kA, float(fA["partner"]["out"]) * 100, float(fA["thrower"]["margin"]) * 100, fA["grips"], fA["partner"]["dir_own"]])
	ok(absf(float(oA["out"]) - float(fA["partner"]["out"])) <= 0.001 and absf(float(oA["thr"]) - float(fA["thrower"]["margin"])) <= 0.001,
		"1 osoto: own recompute out %.4f vs %.4f, thrower %.4f vs %.4f (1 mm)" % [oA["out"], fA["partner"]["out"], oA["thr"], fA["thrower"]["margin"]])
	# 2 no kuzushi
	var maxout := 0.0
	var touch := false
	for fr in rN["frames"]:
		maxout = maxf(maxout, float(fr["partner"]["out"]))
		touch = touch or bool(fr["contact"])
	ok(rN["verdict"] == "no kuzushi" and maxout <= res and touch and hero_cards(N) == hero_cards(A) and (rN["missing"] as Array) == ["kuzushi"] and String(rN["text"]).contains("NO KUZUSHI"),
		"2 no kuzushi: verdict %s, partner out max %.1f cm on every frame, touch %s, hero cards identical to osoto's %s, missing %s" % [rN["verdict"], maxout * 100, touch, hero_cards(N) == hero_cards(A), rN["missing"]])
	# 3 overcommit
	var kO: int = rO["frame"]
	var fO: Dictionary = rO["frames"][kO]
	ok(rO["verdict"] == "thrower falls" and float(fO["partner"]["out"]) > res and float(fO["thrower"]["margin"]) < -res and (rO["missing"] as Array) == ["thrower balance"] and partner_cards(O) == partner_cards(A) and String(rO["text"]).contains("THROWER FALLS"),
		"3 overcommit: verdict %s at f %d; partner out %.1f cm, thrower margin %.1f cm, partner cards identical to osoto's %s, missing %s" % [rO["verdict"], kO, float(fO["partner"]["out"]) * 100, float(fO["thrower"]["margin"]) * 100, partner_cards(O) == partner_cards(A), rO["missing"]])
	# 4 apart
	var anyc := false
	for fr in rX["frames"]:
		anyc = anyc or bool(fr["contact"]) or (fr["points"] as Array).size() > 0
	ok(rX["verdict"] == "no contact" and not anyc and float(rX["min_gap"]) > 1.0 and String(rX["text"]).contains("NO CONTACT"),
		"4 apart: verdict %s, any contact %s, closest %.2f m" % [rX["verdict"], anyc, rX["min_gap"]])
	# 5 Imamura
	var Mp := ThrowFixtures.mass_of(ThrowFixtures.stand())
	var T := ThrowFixtures.MOVE_T
	var psc: Scene = I.actors[0]["scene"]
	var b0 := ThrowTruth.new_body()
	var b1 := ThrowTruth.new_body()
	var t0 := 0.0
	var tm := psc.times()
	t0 = float(tm[1][0])   # the move into card 2 starts here
	psc.apply(b0, t0)
	b0.fk()
	psc.apply(b1, t0 + T)
	b1.fk()
	var dcom := Balance.com(b1) - Balance.com(b0)
	var mean_p := Mp * Vector2(dcom.x, dcom.z).length() / T
	# the peak-speed frame (own scan) and xi there
	var best := 0
	var bv := -1.0
	for f in range(1, rI["frames"].size()):
		var sp := Vector2((rI["frames"][f]["partner"]["v"] as Vector3).x, (rI["frames"][f]["partner"]["v"] as Vector3).z).length()
		if sp > bv:
			bv = sp
			best = f
	var oI := own_read(I, best)
	var fI: Dictionary = rI["frames"][best]
	var grips_kept := false
	for fr in rI["frames"]:
		grips_kept = grips_kept or int(fr["grips"]) >= 1
	ok(absf(mean_p - ThrowFixtures.IMAMURA_KUZUSHI) <= 0.10 * ThrowFixtures.IMAMURA_KUZUSHI,
		"5 imamura: mean COM momentum over the %.1f s move %.1f kg m/s (mass %.1f kg, COM travel %.1f cm) vs 20.6 +-10 %%" % [T, mean_p, Mp, Vector2(dcom.x, dcom.z).length() * 100])
	var xi_chk := Vector2(oI["com"].x + (fI["partner"]["v"] as Vector3).x / oI["w0"], oI["com"].z + (fI["partner"]["v"] as Vector3).z / oI["w0"])
	ok(xi_chk.distance_to(oI["xi"]) <= 0.001 and absf(float(oI["out"]) - float(fI["partner"]["out"])) <= 0.001 and grips_kept,
		"5 imamura: peak speed %.2f m/s at f %d; xi recompute within 1 mm, out %.1f cm (judge %.1f cm); grips kept %s" % [bv, best, float(oI["out"]) * 100, float(fI["partner"]["out"]) * 100, grips_kept])
	print("   FINDING (imamura kuzushi-phase momentum, partner leaning forward): verdict %s; %s" % [rI["verdict"], rI["text"]])
	# 6 words + json
	var terms := {"osoto": "THROW WORKS", "no_kuzushi": "NO KUZUSHI", "overcommit": "THROWER FALLS", "apart": "NO CONTACT"}
	var okw := true
	for p in [["osoto", rA], ["no_kuzushi", rN], ["overcommit", rO], ["apart", rX]]:
		okw = okw and String((p[1] as Dictionary)["text"]).begins_with(String(terms[p[0]]))
	ok(okw, "6 words: each sentence starts with its verdict term")
	var okj := true
	for r in [rA, rN, rO, rX]:
		var j := jround(r)
		var k: int = r["frame"]
		var fr: Dictionary = r["frames"][k]
		var jf: Dictionary = j["frames"][k]
		okj = okj and j["verdict"] == r["verdict"] and int(j["frame"]) == k and absf(float(jf["partner"]["out_m"]) - float(fr["partner"]["out"])) <= 0.0001 \
			and absf(float(jf["thrower"]["margin_m"]) - float(fr["thrower"]["margin"])) <= 0.0001
	var jA := jround(rA)
	var pts: Array = jA["frames"][kA]["points"]
	okj = okj and pts.size() > 0 and (pts[0] as Dictionary).has("thrower_part") and (pts[0] as Dictionary).has("partner_part") and (pts[0] as Dictionary).has("at")
	ok(okj, "6 json: round trip keeps verdict, frame, partner out, thrower margin (0.1 mm); contact points carry parts and positions")
	# 7 role swap
	var rS := ThrowTruth.judge(A, FPS, 1)
	ok(rS["verdict"] != "throw works", "7 role swap: osoto with the partner as the thrower reads %s" % rS["verdict"])
	# 8 sweeps
	var flips := 0
	var last_no := -1.0
	var first_yes := -1.0
	var prev := ""
	var seen_yes := false
	var mono := true
	var pull := 0.0
	while pull >= -30.0 - 1e-6:
		var r := ThrowTruth.judge(ThrowFixtures.build("osoto", {"pull": pull}), FPS)
		var v: String = r["verdict"]
		var out := float((r["frames"][r["frame"]] as Dictionary)["partner"]["out"])
		if v == "throw works":
			if not seen_yes:
				first_yes = out
			seen_yes = true
		elif v == "no kuzushi":
			if seen_yes:
				mono = false
			last_no = out
		if prev != "" and prev != v:
			flips += 1
		prev = v
		pull -= 2.5
	ok(flips == 1 and mono and last_no <= res and first_yes > res, "8 sweep pull: %d flip(s), last no-kuzushi out %.2f cm <= 2 < first throw works %.2f cm" % [flips, last_no * 100, first_yes * 100])
	flips = 0
	prev = ""
	var last_ok := 1.0
	var first_fall := 1.0
	var seen_fall := false
	mono = true
	var sh := 0.0
	while sh <= 0.30 + 1e-6:
		var r := ThrowTruth.judge(ThrowFixtures.build("overcommit", {"shift": sh}), FPS)
		var v: String = r["verdict"]
		var m := float((r["frames"][r["frame"]] as Dictionary)["thrower"]["margin"])
		if v == "thrower falls":
			if not seen_fall:
				first_fall = m
			seen_fall = true
		elif v == "throw works":
			if seen_fall:
				mono = false
			last_ok = m
		if prev != "" and prev != v:
			flips += 1
		prev = v
		sh += 0.025
	ok(flips == 1 and mono and last_ok >= -res and first_fall < -res, "8 sweep thrower shift: %d flip(s), last holding margin %.2f cm >= -2 > first falling %.2f cm" % [flips, last_ok * 100, first_fall * 100])
	# 10 planted controls
	control(rN["verdict"] == "throw works", "C1 the no-kuzushi clip is a throw")
	control(rO["verdict"] == "throw works", "C2 the overcommitted clip is a throw")
	control(anyc, "C3 the apart clip has a contact")
	control(String(rA["text"]).contains("NO KUZUSHI"), "C4 the osoto words say NO KUZUSHI")
	control(rS["verdict"] == "throw works", "C5 osoto with the roles swapped is a throw")
	control(float(fA["partner"]["out"]) <= res, "C6 osoto's key-frame out is <= 2 cm")
	control(absf(mean_p - 52.6) <= 0.10 * 52.6, "C7 the imamura clip's mean momentum is the TSUKURI value 52.6")
	var solo := Scene.new()
	solo.from_dict({"scene": "zz_solo", "fps": 30, "natural": false, "on_floor": false, "pin": false, "cards": [ThrowFixtures.card("a", ThrowFixtures.stand().to_dict(), -1.0, 0.3)]})
	control(bool(ThrowTruth.judge(solo, FPS).get("ok", false)), "C9 a one-fighter scene judged as a pair reports ok")
	# 9 pictures
	await _pictures([["osoto (kuzushi works)", rA, A], ["no kuzushi (same thrower, partner not pulled)", rN, N], ["overcommitted thrower", rO, O], ["apart", rX, X]], rA, A, rO, O)
	print("N040 TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)


func _pictures(clips: Array, rA: Dictionary, A: Scene, rO: Dictionary, O: Scene) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1000, 30 + 210 * clips.size())
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var st := ThrowTruthStrip.new()
	st.size = Vector2(vp.size)
	vp.add_child(st)
	var rows := []
	for c in clips:
		rows.append({"name": c[0], "r": c[1]})
	st.set_rows(rows)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://out"))
	img.save_png(ProjectSettings.globalize_path("res://out/zz_n040_strip.png"))
	var want := [ThrowTruthStrip.COL_WORKS, ThrowTruthStrip.COL_NOKZ, ThrowTruthStrip.COL_FALLS, ThrowTruthStrip.COL_NONE]
	var okc := true
	var got := []
	for i in clips.size():
		var px := img.get_pixelv(st.verdict_pixel(i, int((clips[i][1] as Dictionary)["frame"])))
		got.append(px.to_html(false))
		okc = okc and px.is_equal_approx(want[i])
	var seen := {}
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			seen[img.get_pixel(x, y).to_html(false)] = true
	ok(okc and seen.size() >= 6, "9 strip: key-frame ribbon pixels %s are green / yellow / red / grey; %d distinct colours" % [got, seen.size()])
	var pxo := img.get_pixelv(st.verdict_pixel(2, int(rO["frame"])))
	control(pxo.is_equal_approx(ThrowTruthStrip.COL_WORKS), "C8 the overcommit ribbon pixel at its key frame is green")
	# pair renders
	for case in [["osoto", rA, A, "zz_n040_pair_osoto.png"], ["overcommit", rO, O, "zz_n040_pair_overcommit.png"]]:
		var vp2 := SubViewport.new()
		vp2.size = Vector2i(900, 580)
		vp2.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp2)
		var pr := ThrowTruthPair.new()
		pr.size = Vector2(vp2.size)
		vp2.add_child(pr)
		pr.show_case(case[2], case[1], int((case[1] as Dictionary)["frame"]))
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var im := vp2.get_texture().get_image()
		im.save_png(ProjectSettings.globalize_path("res://out/" + String(case[3])))
		var ti := int((case[1] as Dictionary)["thrower"])
		var pc := im.get_pixelv(pr.plan_com_pixel(ti))
		var want_c := ThrowTruthStrip.COL_WORKS if case[0] == "osoto" else ThrowTruthStrip.COL_FALLS
		var redn := 0
		for y in range(0, im.get_height(), 1):
			for x in range(int(ThrowTruthPair.PLAN.position.x), 890):
				if im.get_pixel(x, y).is_equal_approx(ThrowTruthStrip.COL_FALLS):
					redn += 1
		ok(pc.is_equal_approx(want_c) and (case[0] != "osoto" or redn > 20),
			"9 pair %s: thrower's plan dot %s (want %s); red pixels in the plan %d" % [case[0], pc.to_html(false), want_c.to_html(false), redn])

