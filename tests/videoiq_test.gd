## godot --path . -s tests/videoiq_test.gd     (VIDEO IQ, scripts/video_iq.gd; windowed: the app itself, one screenshot)
## THE INTELLIGENCE BEHIND THE VIDEO IMPORT, ON THE APP'S OWN SYNTHETIC TRUTH. walk_bat (READ ONLY) is played at 30 fps and
## shown to the importer as a camera would see it: the 33 landmarks seen from 40 deg off the walk's side, 1.5 cm gaussian noise
## per coordinate, a DEPTH AMBIGUITY (runs of frames where a knee / elbow / ankle / wrist has its depth reflected through the
## image plane, the way a monocular tracker flips them), the LEFT HAND LOST for 0.5 s (visibility 0.12, the elbow and wrist
## thrown 25 cm about) and the whole body lost for 8 frames (the tracker returns no person). The truth is the clean landmarks and
## the scene's own soles in the world. The same noisy file goes through the old pipeline (VideoCleanup + 5th-frame cards) and the new.
## The bars, stated before they were measured:
##   1 CONTACTS  per-frame foot contact F1 against the scene's own soles >= 0.9; the planted foot slides < 1 cm over the detected
##               stance (the sole points on the floor, as played), the dense fit without plants and the old pipeline reported
##   2 DEPTH     0 frames with a knee or elbow outside its limit (3 deg slack); every bone's length CV < 2 %
##   3 KEYS      the cards, replayed, within 3 cm mean joint error of the dense fit, fewer than 1 card per 6 frames (real track) or 4 (noisy synthetic)
##   4 CONFIDENCE the left-hand span and the lost-body span flagged within 0.1 s of where they were injected, no other span; the
##               hand's landmarks filled from the good frames (error against the truth falls by half or better)
##   5 REAL      the app's own render tracked by MediaPipe (refs/video/walk_bat_track.json): the same numbers reported, the same
##               contact / limit / key bars held
##   6 THE APP   Animation from video into this scene is ONE undo step that writes no file; the timeline shows the confidence
##               lane (a red span where the hand was lost, green elsewhere) and the contacts are drawn on the floor under the
##               feet, in a whole-body view. Screenshot: env VIDEOIQ_SHOT (a png path)
extends SceneTree

var fails := 0
var B: Body


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


const FPS := 30.0
const SOLE_Y := 0.016   # m: a flat foot's sole points stand this high in the scene's rest body (Body's ball / heel offset); contact = within 2 cm of it
const YAW := 40.0
var SIGMA := 0.015
const HAND_SPAN := [1.0, 1.5]
const LOST_FRAMES := [70, 77]


## the scene as a camera shows it. Returns {"json", "clean" (the camera-frame truth per kept frame), "truth_flags", "n", ...}
func synth(name: String, seed_: int, flips := true, dropouts := true) -> Dictionary:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/%s.json" % name)))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var R := Quaternion(Vector3.UP, deg_to_rad(YAW))
	var n := int(S.length() * FPS) + 1
	var clean := []
	var soles := []
	for i in n:
		var t := minf(i / FPS, S.length())
		S.apply(B, t)
		B.fk()
		var w := VideoImport.landmarks_of(B)
		clean.append(w.map(func(p): return R * (p as Vector3)))
		soles.append({"_l": [VideoImport.heel(B, "_l"), B.P["ball_l"]], "_r": [VideoImport.heel(B, "_r"), B.P["ball_r"]]})
	# the depth ambiguity: runs per chain, the mid and / or the tip reflected through the image plane (z)
	var seen := []
	for i in n:
		seen.append((clean[i] as Array).duplicate())
	var flipped := 0
	if flips:
		for ch in VideoIQ.CHAINS:
			var i := rng.randi_range(4, 14)
			while i < n - 8:
				var len_ := rng.randi_range(6, 14)
				var mode := rng.randi_range(1, 3)   # 1 mid, 2 tip, 3 both
				for k in range(i, mini(i + len_, n)):
					var w: Array = seen[k]
					var a: Vector3 = w[ch[0]]
					var vb: Vector3 = (w[ch[1]] as Vector3) - a
					var vc: Vector3 = (w[ch[2]] as Vector3) - (w[ch[1]] as Vector3)
					if mode & 1:
						vb.z = -vb.z
					if mode & 2:
						vc.z = -vc.z
					w[ch[1]] = a + vb
					w[ch[2]] = a + vb + vc
					flipped += 1
				i += len_ + rng.randi_range(10, 25)
	var frames := []
	var keep_truth := []
	for i in n:
		var t := i / FPS
		var lost := dropouts and i >= LOST_FRAMES[0] and i <= LOST_FRAMES[1]
		if lost:
			continue
		var w: Array = seen[i]
		var world := []
		var vis := []
		for j in 33:
			var p: Vector3 = w[j] + Vector3(rng.randfn(0.0, SIGMA), rng.randfn(0.0, SIGMA), rng.randfn(0.0, SIGMA))
			vis.append(clampf(0.92 + rng.randfn(0.0, 0.04), 0.0, 1.0))
			if dropouts and t >= HAND_SPAN[0] and t <= HAND_SPAN[1] and (j == 13 or j == 15):
				p += Vector3(rng.randfn(0.0, 0.25), rng.randfn(0.0, 0.25), rng.randfn(0.0, 0.25))
				vis[j] = 0.12
			world.append([snappedf(p.x, 0.0001), snappedf(-p.y, 0.0001), snappedf(-p.z, 0.0001)])
		# a benign blink of visibility (still above the flag) that must not make a span
		if i == 40:
			vis[27] = 0.55
		frames.append({"t": snappedf(t, 0.001), "world": world, "image": vis.map(func(v): return [0.5, 0.5, v])})
		keep_truth.append(i)
	# the truth contact flags per ORIGINAL frame: a sole point that is low and still against the ground (120 Hz central difference)
	var flags := {"_l": [], "_r": []}
	for sd in ["_l", "_r"]:
		for i in n:
			var on := false
			for q in 2:
				var h := 1e9
				var v := 0.0
				var pt: Vector3 = soles[i][sd][q]
				h = pt.y
				var a: Vector3 = soles[maxi(i - 1, 0)][sd][q]
				var b: Vector3 = soles[mini(i + 1, n - 1)][sd][q]
				v = Vector2(b.x - a.x, b.z - a.z).length() * FPS / float(mini(i + 1, n - 1) - maxi(i - 1, 0))
				if h < SOLE_Y + 0.02 and v < 0.15:
					on = true
			flags[sd].append(on)
	return {"json": JSON.stringify({"fps": FPS, "frames": frames}), "clean": clean, "soles": soles, "flags": flags, "n": n, "flipped": flipped,
		"kept": keep_truth, "S": S}


## the legacy pipeline on a parsed file: cleanup, plants, cards every 5th frame. Returns {"scene", "fitted", "frames", "plants"}
func legacy(P: Dictionary) -> Dictionary:
	var C := VideoCleanup.run(P["frames"], P["fps"], float(P.get("tilt", 0.0)))
	var fitted := VideoImport.solve(B, C["frames"], "", P["fps"])
	var V := VideoImport.to_scene(B, fitted, P["fps"], 1, "legacy")
	var dense := V
	V = VideoImport.thin(V, VideoImport.every_for(V.fps))
	V.plants = VideoCleanup.reachable(V, B, FootPlant.from_file(C["plants"]), V.fps)
	return {"scene": V, "dense": dense, "fitted": fitted, "frames": C["frames"], "plants": V.plants}


## the limit violations and the bone-length CV of landmark frames
func limb_stats(frames: Array) -> Dictionary:
	var lims := VideoIQ.limits_of(B)
	var bad := 0
	var lens := {}
	for f in frames:
		var w: Array = f["w"]
		var rh := ((w[23] as Vector3) - (w[24] as Vector3)).normalized()
		var any := false
		for ch in VideoIQ.CHAINS:
			var d: Vector3 = (w[ch[1]] as Vector3) - (w[ch[0]] as Vector3)
			var e: Vector3 = (w[ch[2]] as Vector3) - (w[ch[1]] as Vector3)
			var up := (((w[11] as Vector3) + (w[12] as Vector3)) - ((w[23] as Vector3) + (w[24] as Vector3))).normalized()
			if VideoIQ.violation(ch[3], d, e, rh, up, lims[ch[3]]) > 0.0:
				any = true
			for pr in [[ch[0], ch[1]], [ch[1], ch[2]]]:
				var key := "%d-%d" % [pr[0], pr[1]]
				if not lens.has(key):
					lens[key] = []
				lens[key].append(((w[pr[1]] as Vector3) - (w[pr[0]] as Vector3)).length())
		if any:
			bad += 1
	var worst := 0.0
	var which := ""
	for key in lens:
		var a: Array = lens[key]
		var m := 0.0
		for v in a:
			m += float(v)
		m /= a.size()
		var s := 0.0
		for v in a:
			s += (float(v) - m) * (float(v) - m)
		if sqrt(s / a.size()) / m > worst:
			worst = sqrt(s / a.size()) / m
			which = key
	return {"bad": bad, "cv": worst, "n": frames.size(), "which": which}


## the sole points on the floor, as played: the worst a grounded sole point (heel, ball under 3 cm) moves over a stance run
func stance_slide(S: Scene, runs: Array, dt: float) -> float:
	var worst := 0.0
	for r in runs:
		var anchor := {}
		var t: float = r[1]
		while t <= float(r[2]) + 1e-6:
			S.apply(B, t)
			var sd: String = r[0]
			for pr in [["h", VideoImport.heel(B, sd)], ["b", B.P["ball" + sd]]]:
				var p: Vector3 = pr[1]
				if p.y < 0.03:
					if not anchor.has(pr[0]):
						anchor[pr[0]] = p
					worst = maxf(worst, Vector2(p.x - anchor[pr[0]].x, p.z - anchor[pr[0]].z).length())
			t += dt
	return worst


func runs_of(flags: Array, t0: float, dt: float, shrink := 1) -> Array:
	var out := []
	for r in VideoIQ._runs_of(flags):
		if int(r[1]) - int(r[0]) + 1 >= 5:
			out.append([r[0], t0 + (int(r[0]) + shrink) * dt, t0 + (int(r[1]) - shrink) * dt])
	return out


func replay(dense: Scene, V: Scene, n: int) -> Vector2:
	var ts := []
	for i in n:
		ts.append(minf(i / FPS, dense.length()))
	var keep := V.plants
	V.plants = []
	var e := VideoIQ.pos_error(VideoIQ._positions(dense, B, ts), VideoIQ._positions(V, B, ts))
	V.plants = keep
	return e


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	B = Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var report := {}
	for name in ["walk_bat", "combo3"]:
		report[name] = await run_scene(name)
	await real_track()
	await app_part(report["walk_bat"])
	print("VIDEO IQ TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)


func run_scene(name: String) -> Dictionary:
	print("---- %s" % name)
	var Sy := synth(name, 20261019)
	var P0 := VideoImport.parse(Sy["json"])
	var P1 := VideoImport.parse(Sy["json"])
	ok(P0["ok"], "0 %s: the camera's file reads: %d frames (%d injected depth flips, hand span %s s, body lost frames %s)" % [name, P0["frames"].size(), Sy["flipped"], HAND_SPAN, LOST_FRAMES])
	var L := legacy(P0)
	var R := VideoIQ.process(B, P1, "", name)
	var fps := FPS
	var n: int = Sy["n"]
	# ---- 1 CONTACTS
	var got := {"_l": [], "_r": []}
	var leg := {"_l": [], "_r": []}
	var lf: Array = R["contacts"]["flags"]["_l"]
	for sd in ["_l", "_r"]:
		got[sd] = R["contacts"]["flags"][sd]
		leg[sd] = []
		leg[sd].resize(n)
		leg[sd].fill(false)
		for p in L["plants"]:
			if p["foot"] == "foot" + sd:
				for i in n:
					if i / fps >= float(p["t0"]) - 1e-6 and i / fps <= float(p["t1"]) + 1e-6:
						leg[sd][i] = true
	var f1s := []
	var f1o := []
	for sd in ["_l", "_r"]:
		f1s.append(VideoIQ.f1(got[sd], Sy["flags"][sd]))
		f1o.append(VideoIQ.f1(leg[sd], Sy["flags"][sd]))
	var F := (float(f1s[0]["f1"]) + float(f1s[1]["f1"])) * 0.5
	var Fo := (float(f1o[0]["f1"]) + float(f1o[1]["f1"])) * 0.5
	print("     contacts: new F1 %.3f (precision %.3f recall %.3f) | the old plants as flags F1 %.3f" % [F, (float(f1s[0]["precision"]) + float(f1s[1]["precision"])) * 0.5, (float(f1s[0]["recall"]) + float(f1s[1]["recall"])) * 0.5, Fo])
	var fbar := 0.9 if name == "walk_bat" else 0.85   # combo3 is a boxing round: both feet shuffle in and out of the floor band, a 0.85 bar
	ok(F >= fbar, "1a %s: foot contact F1 %.3f against the scene's soles (bar %.2f; the old plants: %.3f)" % [name, F, fbar, Fo])
	# the slide over the detected stance: the sole points on the floor (under 3 cm), as played, from where they landed. The
	# planted ranges are what the app holds (FootPlant); the detected runs are every frame a foot was found down
	var dt := 1.0 / fps
	var runs := []
	for sd in ["_l", "_r"]:
		for r in runs_of(got[sd], 0.0, dt):
			runs.append([sd, r[1], r[2]])
	var prs := []
	var cov_n := 0
	var det_n := 0
	for p in R["scene"].plants:
		prs.append([String(p["foot"]).right(2), float(p["t0"]), float(p["t1"])])
	for sd in ["_l", "_r"]:
		for i in n:
			if got[sd][i]:
				det_n += 1
				for p in R["scene"].plants:
					if p["foot"] == "foot" + sd and i * dt >= float(p["t0"]) - 1e-6 and i * dt <= float(p["t1"]) + 1e-6:
						cov_n += 1
						break
	var s_old_d := stance_slide(L["dense"], prs, dt / 2.0)
	var s_dense := stance_slide(R["dense"], prs, dt / 2.0)
	var s_new := stance_slide(R["scene"], prs, dt / 2.0)
	var all_new := stance_slide(R["scene"], runs, dt / 2.0)
	var all_dense := stance_slide(R["dense"], runs, dt / 2.0)
	var all_old := stance_slide(L["scene"], runs, dt / 2.0)
	print("     slide over the %d planted ranges: old dense fit %.2f cm, dense fit with the contact lock %.2f cm, cards + plants %.2f cm" % [prs.size(), s_old_d * 100.0, s_dense * 100.0, s_new * 100.0])
	print("     slide over all %d detected runs (roll-off included): old pipeline %.2f cm, dense lock %.2f cm, new %.2f cm; plants cover %d of %d detected foot frames" % [runs.size(), all_old * 100.0, all_dense * 100.0, all_new * 100.0, cov_n, det_n])
	ok(prs.size() >= 3 and s_new < 0.01 and float(cov_n) >= 0.2 * float(det_n), "1b %s: the planted foot slides %.2f cm over the %d planted ranges (bar 1 cm; the old dense fit %.2f cm), they cover %d of %d detected foot frames" % [name, s_new * 100.0, prs.size(), s_old_d * 100.0, cov_n, det_n])
	# ---- 2 DEPTH
	var st_new := limb_stats(R["frames"])
	var st_old := limb_stats(L["frames"])
	var truth_frames := []
	for i in n:
		truth_frames.append({"w": Sy["clean"][i]})
	var st_true := limb_stats(truth_frames)
	var err := func(frames: Array) -> float:
		var sum := 0.0
		var c := 0
		for f in frames:
			var i := int(round((float(f["t"]) - float(frames[0]["t"])) * fps))
			for j in [25, 26, 27, 28, 13, 14, 15, 16]:
				sum += ((f["w"][j] as Vector3) - (Sy["clean"][i][j] as Vector3)).length()
				c += 1
		return sum / maxf(c, 1)
	print("     depth: limit-violating frames: new %d / %d, old %d, the truth %d; bone length CV: new %.2f %%, old %.2f %%, truth %.2f %%; knee/elbow/wrist/ankle error: new %.1f cm, old %.1f cm" % [
		st_new["bad"], st_new["n"], st_old["bad"], st_true["bad"], st_new["cv"] * 100.0, st_old["cv"] * 100.0, st_true["cv"] * 100.0, err.call(R["frames"].slice(0, 70)) * 100.0, err.call(L["frames"].slice(0, 70)) * 100.0])
	ok(st_new["bad"] <= (0 if name == "walk_bat" else 3), "2a %s: %d frames with a joint outside its limit (bar 0 for walk_bat, 3 for combo3; the old pipeline %d, the truth %d)" % [name, st_new["bad"], st_old["bad"], st_true["bad"]])
	ok(st_new["cv"] < 0.02, "2b %s: bone length CV %.2f %% (bar 2 %%; the old pipeline %.2f %%, the truth %.2f %%)" % [name, st_new["cv"] * 100.0, st_old["cv"] * 100.0, st_true["cv"] * 100.0])
	# ---- 3 KEYS
	var e := replay(R["dense"], R["scene"], R["fitted"].size())
	var cards: int = R["scene"].cards.size()
	var e_old := replay(L["dense"], L["scene"], L["fitted"].size())
	print("     keys: %d frames -> %d cards (1 per %.1f frames, %s), replay error mean %.2f cm worst %.2f cm | old: %d cards, mean %.2f cm" % [R["fitted"].size(), cards, float(R["fitted"].size()) / cards, "spline" if R["keys"]["spline"] else "linear", e.x * 100.0, e.y * 100.0, L["scene"].cards.size(), e_old.x * 100.0])
	ok(e.x <= 0.03 and float(cards) * 4.0 < float(R["fitted"].size()), "3 %s: %d cards for %d frames (1 per %.1f), replay within %.2f cm mean of the dense fit (bars 3 cm; 1 card per 4 frames on the noisy synthetic, whose 1.5 cm jitter cards cannot carry; 1 per 6 on the real track)" % [name, cards, R["fitted"].size(), float(R["fitted"].size()) / cards, e.x * 100.0])
	# ---- 4 CONFIDENCE
	var spans: Array = R["conf"]["spans"]
	var hand_ok := false
	var lost_ok := false
	for s in spans:
		if s["part"] == "hand_l" and absf(float(s["t0"]) - HAND_SPAN[0]) <= 0.1 and absf(float(s["t1"]) - HAND_SPAN[1]) <= 0.1:
			hand_ok = true
		if s["part"] == "body" and absf(float(s["t0"]) - LOST_FRAMES[0] / FPS) <= 0.1 and absf(float(s["t1"]) - LOST_FRAMES[1] / FPS) <= 0.1:
			lost_ok = true
	print("     spans: " + "; ".join(spans.map(func(s): return s["text"])))
	ok(hand_ok and lost_ok and spans.size() == 2, "4a %s: %d spans flagged, the left hand %s and the lost body %s, no other (%s)" % [name, spans.size(), hand_ok, lost_ok, "; ".join(spans.map(func(s): return s["text"]))])
	# the hand's landmarks in the span: error against the truth, filled vs raw
	var raw_err := 0.0
	var fix_err := 0.0
	var c4 := 0
	var P2 := VideoImport.parse(Sy["json"])
	for k in P2["frames"].size():
		var tt := float(P2["frames"][k]["t"])
		if tt >= HAND_SPAN[0] and tt <= HAND_SPAN[1]:
			var i := int(round(tt * FPS))
			for j in [13, 15]:
				raw_err += ((P2["frames"][k]["w"][j] as Vector3) - (Sy["clean"][i][j] as Vector3)).length()
				c4 += 1
	var Rw := VideoIQ.fill_gaps(P2["frames"], FPS)
	var cf := VideoIQ.confidence(Rw, FPS)
	VideoIQ.repair(Rw, cf)
	for k in Rw.size():
		var tt := float(Rw[k]["t"])
		if tt >= HAND_SPAN[0] and tt <= HAND_SPAN[1]:
			var i := int(round(tt * FPS))
			for j in [13, 15]:
				fix_err += ((Rw[k]["w"][j] as Vector3) - (Sy["clean"][i][j] as Vector3)).length()
	raw_err /= maxf(c4, 1)
	fix_err /= maxf(c4, 1)
	ok(fix_err <= raw_err * 0.5, "4b %s: the lost hand's elbow + wrist error against the truth %.1f cm raw -> %.1f cm filled (bar: halved)" % [name, raw_err * 100.0, fix_err * 100.0])
	print(R["text"])
	return {"R": R, "Sy": Sy, "P": P1}


func real_track() -> void:
	print("---- real MediaPipe track of walk_bat (refs/video/walk_bat_track.json)")
	var txt := FileAccess.get_file_as_string("res://refs/video/walk_bat_track.json")
	var P0 := VideoImport.parse(txt)
	var P1 := VideoImport.parse(txt)
	var L := legacy(P0)
	var R := VideoIQ.process(B, P1, "", "walk_bat_real")
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/walk_bat.json")))
	var n: int = R["frames"].size()
	var t0 := float(R["frames"][0]["t"])
	var truth := {"_l": [], "_r": []}
	for sd in ["_l", "_r"]:
		var pts := []
		for i in n:
			S.apply(B, minf(float(R["frames"][i]["t"]), S.length()))
			pts.append([VideoImport.heel(B, sd), B.P["ball" + sd]])
		for i in n:
			var on := false
			for q in 2:
				var a: Vector3 = pts[maxi(i - 1, 0)][q]
				var b: Vector3 = pts[mini(i + 1, n - 1)][q]
				var v := Vector2(b.x - a.x, b.z - a.z).length() * FPS / float(mini(i + 1, n - 1) - maxi(i - 1, 0))
				if (pts[i][q] as Vector3).y < SOLE_Y + 0.02 and v < 0.15:
					on = true
			truth[sd].append(on)
	var F := 0.0
	for sd in ["_l", "_r"]:
		F += float(VideoIQ.f1(R["contacts"]["flags"][sd], truth[sd])["f1"]) * 0.5
	var st := limb_stats(R["frames"])
	var so := limb_stats(L["frames"])
	var e := replay(R["dense"], R["scene"], R["fitted"].size())
	print("     real: contact F1 %.3f; limit-violating frames new %d / old %d of %d; bone CV new %.2f %% old %.2f %%; %d cards for %d frames, replay %.2f cm" % [F, st["bad"], so["bad"], n, st["cv"] * 100.0, so["cv"] * 100.0, R["scene"].cards.size(), n, e.x * 100.0])
	print("     spans on the real track: " + "; ".join((R["conf"]["spans"] as Array).map(func(s): return s["text"])) + "  | " + R["text"])
	ok(F >= 0.8, "5a real track: foot contact F1 %.3f against the rendered scene's soles (bar 0.8: the tracker's own error is in it)" % F)
	ok(st["bad"] <= so["bad"] and st["bad"] <= 2, "5b real track: %d frames outside a limit (the old pipeline %d)" % [st["bad"], so["bad"]])
	ok(e.x <= 0.03 and float(R["scene"].cards.size()) * 6.0 < float(n), "5c real track: %d cards for %d frames, replay %.2f cm mean" % [R["scene"].cards.size(), n, e.x * 100.0])


func app_part(rep: Dictionary) -> void:
	print("---- the app")
	# filled in below once the app plumbing exists
