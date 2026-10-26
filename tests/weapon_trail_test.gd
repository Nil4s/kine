## WEAPON TRAILS (ROADMAP 35): godot --headless --path . -s tests/weapon_trail_test.gd
## READ ONLY on scenes/combo3.json; the export goes to user://zz_wtrail (never scenes/, poses/, data/). Checks:
##  (1) RIBBON GATING: at every frame f, the ribbon quad for frame f is drawn iff the bat is held and the tip's speed
##      there is above 8 m/s. The speeds are printed (frame, t, m/s) for the frames above the threshold.
##  (2) THE MESH: at every playhead the ribbon mesh holds exactly the quads drawn (and no surface when none).
##  (3) SPEEDS: the sampled speeds equal a fresh body's tip finite difference (within 1e-3 m/s).
##  (4) EXPORT: the sidecar's base and tip equal a fresh body's wep_point per frame, within 0.1 mm.
##  (5) SMEAR: the smear shows exactly on the frames where the tip moved more than 20 cm; off, nothing is visible and the
##      posed body is unchanged by the draw. (Headless: no rendering, so "bit-identical playblast" is checked as state:
##      no node made visible, no pose touched; the pixel check is the screenshot run.)
extends SceneTree

var fails := 0
const SCENE := "combo3"
const DIR := "user://zz_wtrail"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	return b


func _init() -> void:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/%s.json" % SCENE)))
	var fps := float(S.fps)
	var B := _body()
	var sm := WeaponTrail.sample(S, B)
	var n := (sm["t"] as Array).size()
	var sp: Array = sm["speed"]
	var armed: Array = sm["armed"]
	ok(n > 2 and armed.has(true), "combo3 has %d frames at %d fps, and a bat in hand on %d of them" % [n, S.fps, armed.count(true)])

	# (3) the speeds against a fresh body's finite difference
	var B2 := _body()
	if B2.body != S.body:
		B2.set_proportions(S.body)
	var worst := 0.0
	S.apply(B2, 0.0)
	var prev := B2.wep_point(B2.wep_len) if B2.wep_on else Vector3.ZERO
	for i in range(1, n):
		S.apply(B2, minf(i / fps, S.length()))
		var tip := B2.wep_point(B2.wep_len) if B2.wep_on else Vector3.ZERO
		if B2.wep_on and armed[i] and armed[i - 1]:
			worst = maxf(worst, absf((tip - prev).length() * fps - float(sp[i])))
		prev = tip
	ok(worst < 1e-3, "sampled tip speeds equal a fresh body's finite difference (worst %.6f m/s)" % worst)

	# (1)+(2) the ribbon: gating per frame and its mesh
	var W := WeaponTrail.new()
	W.setup()
	W.ribbon_on = true
	W.samples = sm   # the same samples the view draws from
	var bad := 0
	var drawn := []
	var listed := []
	for f in n:
		var want: bool = f >= 1 and armed[f] and armed[f - 1] and float(sp[f]) > W.speed_min
		if f >= 1 and want:
			listed.append("  frame %3d  t %.3f s  tip %.2f m/s" % [f, float(sm["t"][f]), float(sp[f])])
		if (f in W.ribbon_frames(f)) != want:
			bad += 1
		for k in W.ribbon_frames(f):
			if float(sp[k]) <= W.speed_min:
				bad += 1
		W.draw(S, minf(f / fps, S.length()))
		var im := W._ribbon.mesh as ImmediateMesh
		var quads: int = W.ribbon_frames(f).size()
		if W.quads != quads or (quads == 0) != (im.get_surface_count() == 0):
			bad += 1
		drawn.append(quads)
	print("ribbon frames (tip above %.1f m/s, bat in hand):" % W.speed_min)
	for l in listed:
		print(l)
	ok(bad == 0, "ribbon exists only on frames where the tip is faster than %.1f m/s (%d of %d frames; %d bad)" % [W.speed_min, listed.size(), n, bad])
	ok(W.ribbon_frames(0).is_empty() and drawn.max() >= 1, "ribbon: none at frame 0, and drawn on %d frames at most N=%d" % [int(drawn.max()), W.n_frames])

	# (5) smear on: exact frames; off: nothing visible
	W.ribbon_on = false
	W.smear_on = true
	var sbad := 0
	var smear_frames := []
	for f in range(1, n):
		W.draw(S, minf(f / fps, S.length()))
		var want: bool = float(sp[f]) > W.smear_min and armed[f] and armed[f - 1]
		if want:
			smear_frames.append(f)
		if W._smear.visible != want:
			sbad += 1
	ok(sbad == 0, "smear frames are exactly those with the tip moving > %.0f cm in a frame (%d frames: %s)" % [W.smear_min * 100.0, smear_frames.size(), str(smear_frames.slice(0, 12))])
	W.smear_on = false
	var before := B.state()
	var seen := 0
	for f in n:
		W.draw(S, minf(f / fps, S.length()))
		seen += 1 if W._ribbon.visible or W._smear.visible else 0
	ok(seen == 0 and B.state() == before, "both off: no trail node visible on any frame, and the posed body is untouched")

	# (4) the export: sidecar points against a fresh body, per frame
	var B3 := _body()
	var res := EngineExport.export(S, B3, "godot", DIR, Callable())
	ok(res["err"] == OK and res["trail"] != "", "engine export wrote the glb and the weapon trail sidecar: %s" % res["trail"])
	var j = JSON.parse_string(FileAccess.get_file_as_string(res["trail"]))
	var fr: Array = j["frames"] if j is Dictionary else []
	ok(fr.size() == n, "sidecar lists %d frames, one per sampled frame" % fr.size())
	var P := _body()
	if P.body != S.body:
		P.set_proportions(S.body)
	var dmax := 0.0
	for i in mini(fr.size(), n):
		var f: Dictionary = fr[i]
		if not f["held"]:
			continue
		S.apply(P, minf(i / fps, S.length()))
		var want_b := P.wep_point(0.0)
		var want_t := P.wep_point(P.wep_len)
		var gb := Vector3(f["base"][0], f["base"][1], f["base"][2])
		var gt := Vector3(f["tip"][0], f["tip"][1], f["tip"][2])
		dmax = maxf(dmax, maxf((gb - want_b).length(), (gt - want_t).length()))
	ok(dmax < 1e-4, "exported base and tip equal the body's weapon points on every held frame (worst %.4f mm)" % (dmax * 1000.0))
	W.free()
	print("weapon_trail: %d FAILS" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
