## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/i9_test.gd    (ROADMAP I9: sketch to pose; needs a window)
## The strokes are made the way a user traces a stick figure over a body: the spine from the neck down to the hips along the
## spine's joints, each arm from the top of the spine through the elbow to the wrist, each leg from the bottom of the spine
## through the knee to the ankle (screen projections of a LIBRARY pose's joints through the app's camera, densified to 4 px
## steps with 0.3 px of noise). Bars (stated before the first run):
##   1 FRONT and SIDE views, every pose in poses/ and poses/lib/, starting from that pose with its trunk and limbs knocked
##     off by up to 18 deg (a rough pose to refine): the fit recovers the DIRECTION of the 9 major bones (trunk, both upper
##     arms, forearms, thighs, calves) within 10 deg. (Euler angles are not compared: twist is not in a stick figure.)
##     REPORTED, not barred: the same from the neutral stand (no depth hint: 50/50 on a bone that points at the camera)
##   2 a stroke set missing one arm fits the rest (within 10 deg) and leaves the missing arm's angles BIT-IDENTICAL; the
##     report names it
##   3 one fit = one undo step and Ctrl+Z puts the whole state back exactly; Esc / Enter / Backspace do what they say
##   4 the fit takes < 100 ms (the slowest of all the fits above)
##   5 PLACEMENT: the fitted joints project within 12 px of the strokes' joint points, in a whole-body view; the faint fitted
##     skeleton is on the body (its points are the body's projected joints)
##   6 recognition: a spine shorter than the legs is still the spine; a head circle is a head, not a limb; a straight arm
##     has no corner; a bent one is split at its farthest point
##   7 the screenshot: gold strokes over the view and the fitted body
## STEP 3 (the depth ambiguity as a UI choice; bars stated before the first run):
##   8 FLIPS. An oracle that plays a user: for each of the fits that has a bone over 10 deg, it takes the limbs that carry a flip
##     handle, tries every candidate, and clicks the handle until the limb is on the candidate closest to the truth, the limbs that
##     gain most first, at most 2 clicks per fit. BAR: >= 36 of the 42 fits pass the 10 deg bar after that.
##     REPORTED: how many fits had handles, how many failures no handle can reach.
##   8b a click on a handle (through the mouse path) is ONE undo step; Ctrl+Z puts the body back EXACTLY and brings the handles back;
##     the handles are drawn at the limbs elbows / knees, in the window (placement)
##   8c a SHOULDER LINE on a pose twisted 30 deg (chest) recovers the twist within 8 deg (+30 straight, -30 after the twist handle
##     one flip: +t and -t project alike); a HIP LINE on a pelvis yawed 30 deg likewise
##   8d the screenshot i9c.png: a sketch fit with the flip handles on the ambiguous limbs
extends SceneTree

var fails := 0
var worst_ms := 0.0
var noise := 0.3   # px of hand tremor on every traced point


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _bones() -> Dictionary:
	return {"trunk": ["pelvis", "neck_01"], "ua_l": ["upperarm_l", "lowerarm_l"], "fa_l": ["lowerarm_l", "hand_l"], "ua_r": ["upperarm_r", "lowerarm_r"],
		"fa_r": ["lowerarm_r", "hand_r"], "th_l": ["thigh_l", "calf_l"], "ca_l": ["calf_l", "foot_l"], "th_r": ["thigh_r", "calf_r"], "ca_r": ["calf_r", "foot_r"]}


func _errs(A: Body, R: Body, skip := []) -> Dictionary:
	var out := {}
	var bn := _bones()
	for k in bn:
		if k in skip:
			continue
		var a: Vector3 = (A.P[bn[k][1]] as Vector3) - (A.P[bn[k][0]] as Vector3)
		var r: Vector3 = (R.P[bn[k][1]] as Vector3) - (R.P[bn[k][0]] as Vector3)
		out[k] = rad_to_deg(a.angle_to(r))
	return out


func _worst(e: Dictionary) -> Array:
	var w := 0.0
	var wk := ""
	for k in e:
		if float(e[k]) > w:
			w = float(e[k])
			wk = k
	return [w, wk]


func _dense(rng: RandomNumberGenerator, pts: Array) -> Array:
	var out := []
	for i in range(pts.size() - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var n := maxi(1, int(a.distance_to(b) / 4.0))
		for k in n:
			out.append(a.lerp(b, float(k) / n) + Vector2(rng.randfn(0.0, noise), rng.randfn(0.0, noise)))
	out.append(pts[pts.size() - 1])
	return out


## the strokes of a pose as a user traces it. no = limbs left undrawn ("hand_l", ...)
func _strokes(B: Body, cam: Camera3D, no := [], head := false, seed := 1, lines := "") -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var px := func(j: String) -> Vector2: return cam.unproject_position(B.P[j])
	var neck: Vector2 = px.call("neck_01")
	var pel: Vector2 = px.call("pelvis")
	var out := []
	out.append(_dense(rng, [neck, px.call("spine_03"), px.call("spine_02"), px.call("spine_01"), pel]))
	for sd in ["_l", "_r"]:
		if not ("hand" + sd) in no:
			out.append(_dense(rng, [neck, px.call("lowerarm" + sd), px.call("hand" + sd)]))
		if not ("foot" + sd) in no:
			out.append(_dense(rng, [pel, px.call("calf" + sd), px.call("foot" + sd)]))
	if "s" in lines:
		out.append(_dense(rng, [px.call("upperarm_l"), px.call("upperarm_r")]))
	if "h" in lines:
		out.append(_dense(rng, [px.call("thigh_l"), px.call("thigh_r")]))
	if head:
		var hc := cam.unproject_position(LineOfAction.head_c(B))
		var c := []
		for k in 25:
			var a := TAU * float(k) / 24.0
			c.append(hc + Vector2(cos(a), sin(a)) * 22.0)
		out.append(c)
	return out


## the user who picks the right mirror: every flip entry's candidates are tried (the handle clicked round once), the limbs that gain
## most are put on their best candidate, at most `budget` clicks in all. Returns {"worst", "clicks", "limbs"}
func _oracle(B: Body, R: Body, cam: Camera3D, strokes: Array, rep: Dictionary, budget := 2) -> Dictionary:
	var lb := {"hand_l": ["ua_l", "fa_l"], "hand_r": ["ua_r", "fa_r"], "foot_l": ["th_l", "ca_l"], "foot_r": ["th_r", "ca_r"]}
	var plan := []
	for key in rep["flips"]:
		var f: Dictionary = rep["flips"][key]
		if f["kind"] != "limb":
			continue
		var n: int = (f["cands"] as Array).size()
		var errs := []
		for k in n:
			var e := _errs(B, R)
			var w := 0.0
			for bk in lb[key]:
				w = maxf(w, float(e[bk]))
			errs.append(w)
			SketchPose.flip(B, cam, strokes, rep, key)   # next candidate; n clicks come back round to where it started
		var bi := 0
		for k in n:
			if float(errs[k]) < float(errs[bi]) - 0.01:
				bi = k
		if bi != 0:
			plan.append({"key": key, "clicks": bi, "gain": float(errs[0]) - float(errs[bi])})
	plan.sort_custom(func(a, b): return float(a["gain"]) > float(b["gain"]))
	var used := 0
	var limbs := 0
	for pl in plan:
		if used + int(pl["clicks"]) > budget:
			continue
		for c in int(pl["clicks"]):
			SketchPose.flip(B, cam, strokes, rep, pl["key"])
		used += int(pl["clicks"])
		limbs += 1
	return {"worst": _worst(_errs(B, R))[0], "clicks": used, "limbs": limbs}


func _knock(B: Body, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for j in ["upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "thigh_l", "thigh_r", "calf_l", "calf_r"]:
		var a: Vector3 = B.ang[j]
		a.x += rng.randf_range(-18.0, 18.0)
		a.y += rng.randf_range(-12.0, 12.0)
		B.ang[j] = B.clamp_ang(j, a)
	for j in ["spine_01", "spine_02", "spine_03"]:
		var a: Vector3 = B.ang[j]
		a.x += rng.randf_range(-6.0, 6.0)
		a.y += rng.randf_range(-4.0, 4.0)
		B.ang[j] = B.clamp_ang(j, a)
	B.fk()


func _poses() -> Array:
	var out := []
	for dir in ["res://poses", "res://poses/lib"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".json"):
				out.append(dir + "/" + f)
	out.sort()
	return out


func _load(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _key(ev: int) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = ev
	k.pressed = true
	return k


func _mouse(pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	return e


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("errw="): SketchPose.err_w = float(a.substr(5))
		if a == "noelbow": SketchPose.sw_elbow = false
		if a == "noassign": SketchPose.sw_assign = false
		if a == "assignall": SketchPose.sw_assign_all = true
		if a == "nofifth": SketchPose.sw_fifth = false
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var B: Body = m.B
	var R := Body.new()
	R.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var sk: SketchPose = m.sk
	var stand := _load("res://poses/stand.json")

	# ---- 6 recognition (pure, on hand-made strokes) ------------------------------------------------------------------
	var line := func(a: Vector2, b: Vector2) -> Array: return [a, a.lerp(b, 0.25), a.lerp(b, 0.5), a.lerp(b, 0.75), b]
	var fig: Array = []
	fig.append(line.call(Vector2(300, 100), Vector2(300, 260)))    # spine 160 px
	fig.append(line.call(Vector2(300, 260), Vector2(250, 460)))    # legs 200+ px: longer than the spine
	fig.append(line.call(Vector2(300, 260), Vector2(360, 470)))
	var arm_bent: Array = (line.call(Vector2(300, 100), Vector2(250, 150)) as Array) + (line.call(Vector2(250, 150), Vector2(230, 90)) as Array)
	fig.append(arm_bent)
	fig.append(line.call(Vector2(300, 100), Vector2(380, 180)))   # a straight arm
	var circ := []
	for k in 21:
		circ.append(Vector2(300, 70) + Vector2(cos(TAU * k / 20.0), sin(TAU * k / 20.0)) * 24.0)
	fig.append(circ)
	var rc := SketchPose.recognise(fig)
	ok(rc["ok"] and absf((rc["spine"][0] as Vector2).y - 100.0) < 1.0 and absf((rc["spine"][rc["spine"].size() - 1] as Vector2).y - 260.0) < 1.0,
		"6a the spine is the 160 px line from the neck to the hips although both legs are longer")
	ok(rc["ok"] and (rc["legs"] as Array).size() == 2 and (rc["arms"] as Array).size() == 2 and not (rc["head"] as Dictionary).is_empty(),
		"6b two legs from the bottom, two arms from the top, the circle is the head (%d arms, %d legs)" % [(rc["arms"] as Array).size(), (rc["legs"] as Array).size()])
	var bent = null
	var straight = null
	for a in rc["arms"]:
		if a["corner"] != null:
			bent = a
		else:
			straight = a
	ok(bent != null and ((bent["corner"] as Vector2) - Vector2(250, 150)).length() < 1.0 and straight != null,
		"6c the bent arm is split at its farthest point %s (put at (250,150)); the straight arm has no corner" % [str(bent["corner"]) if bent != null else "none"])

	# ---- 1 the library poses, front and side -------------------------------------------------------------------------
	var views := {"front": 0.0, "side": 90.0}
	var bad := []
	var n_fit := 0
	var neutral_bad := 0
	var neutral_n := 0
	var lines := []
	var all_worst := 0.0
	var with_handles := 0
	var n_fail := 0
	var n_fixed := 0
	var clicks_used := 0
	var still_bad := []
	for path in _poses():
		var d := _load(path)
		SketchPose.lib_exclude = path.get_file()   # leave-one-out: the library prior must not contain the pose being fitted
		for vn in views:
			m.yaw = views[vn]
			m.pitch = 0.0
			m._cam()
			await process_frame
			var cam: Camera3D = m.cam
			R.from_dict(d)
			R.fk()
			var strokes := _strokes(R, cam, [], false, 7)
			# A: from the pose knocked off (barred)
			B.from_dict(d)
			_knock(B, 11 + n_fit)
			sk.strokes = strokes
			var rep := SketchPose.fit(B, cam, strokes)
			worst_ms = maxf(worst_ms, float(rep["ms"]))
			n_fit += 1
			var e := _errs(B, R)
			var w := _worst(e)
			all_worst = maxf(all_worst, w[0])
			if float(w[0]) > 10.0:
				bad.append("%s %s %s %.1f" % [path.get_file(), vn, w[1], w[0]])
			var n_handles := 0
			for fk in rep["flips"]:
				if rep["flips"][fk]["kind"] == "limb":
					n_handles += 1
			if n_handles > 0:
				with_handles += 1
			if float(w[0]) > 10.0:
				n_fail += 1
				var orc := _oracle(B, R, cam, strokes, rep, 2)
				if float(orc["worst"]) <= 10.0:
					n_fixed += 1
					clicks_used += int(orc["clicks"])
				else:
					still_bad.append("%s %s %.1f (%d handles)" % [path.get_file(), vn, orc["worst"], n_handles])
			# B: from the neutral stand (reported)
			B.from_dict(stand)
			var rep2 := SketchPose.fit(B, cam, strokes)
			worst_ms = maxf(worst_ms, float(rep2["ms"]))
			var w2 := _worst(_errs(B, R))
			neutral_n += 1
			if float(w2[0]) > 10.0:
				neutral_bad += 1
			lines.append("%-22s %-5s knocked-start worst %-6s %5.1f   neutral-start worst %-6s %5.1f   %.0f ms" % [path.get_file(), vn, w[1], w[0], w2[1], w2[0], rep["ms"]])
	for l in lines:
		print("     " + l)
	SketchPose.lib_exclude = ""
	ok(bad.is_empty(), "1 %d fits (%d poses x front/side, from the knocked start): the 9 major bones within 10 deg, worst %.1f deg; over: %s" % [n_fit, n_fit / 2, all_worst, str(bad)])
	print("     REPORTED neutral-stand start: %d of %d fits have a bone over 10 deg (a bone pointing at the camera has 2 mirror answers; no old pose to break the tie)" % [neutral_bad, neutral_n])

	ok(n_fit - n_fail + n_fixed >= 36, "8 FLIPS: %d of %d fits pass the 10 deg bar after the oracle's at most 2 clicks (bar 36; %d passed before, %d failing fits fixed with %d clicks, %d of the %d fits had handles)" % [n_fit - n_fail + n_fixed, n_fit, n_fit - n_fail, n_fixed, clicks_used, with_handles, n_fit])
	print("     REPORTED fits no 2 clicks fix: " + str(still_bad))

	# REPORTED: how the error grows with tremor (the pose with the most bones near the picture plane, front view)
	m.yaw = 0.0
	m._cam()
	await process_frame
	var dn := _load("res://poses/lib/guard_bat.json")
	R.from_dict(dn)
	R.fk()
	var sweep := []
	for nz in [0.0, 0.3, 0.8, 2.0, 4.0]:
		noise = nz
		B.from_dict(dn)
		_knock(B, 21)
		SketchPose.fit(B, m.cam, _strokes(R, m.cam, [], false, 5))
		sweep.append("%.1f px -> %.1f deg" % [nz, _worst(_errs(B, R))[0]])
	noise = 0.3
	print("     REPORTED tremor sweep (guard_bat front, worst of the 9 bones): " + ", ".join(sweep))

	# ---- 2 a missing arm ----------------------------------------------------------------------------------------------
	m.yaw = 0.0
	m._cam()
	await process_frame
	var cam2: Camera3D = m.cam
	SketchPose.lib_exclude = "windup_high.json"
	var dd := _load("res://poses/lib/windup_high.json")
	R.from_dict(dd)
	R.fk()
	B.from_dict(dd)
	_knock(B, 5)
	var arm_before := {}
	for j in ["clavicle_l", "upperarm_l", "lowerarm_l", "hand_l"]:
		arm_before[j] = B.ang[j]
	var st := _strokes(R, cam2, ["hand_l"], false, 3)
	var rep3 := SketchPose.fit(B, cam2, st)
	var same := true
	for j in arm_before:
		if B.ang[j] != arm_before[j]:
			same = false
	var e3 := _errs(B, R, ["ua_l", "fa_l"])
	ok(same and "hand_l" in rep3["kept"], "2a the left arm was not drawn: its 4 joints' angles are bit-identical, reported as kept %s" % str(rep3["kept"]))
	ok(float(_worst(e3)[0]) <= 10.0, "2b the rest fits within 10 deg without it: worst %.1f deg (%s)" % [_worst(e3)[0], _worst(e3)[1]])

	SketchPose.lib_exclude = ""
	# ---- 3 undo, and the keys ----------------------------------------------------------------------------------------
	B.from_dict(stand)
	m._refresh()
	var s_start: Dictionary = B.state()
	var n0: int = m.undo.size()
	m._sk_toggle()
	ok(sk.on, "3a the Sketch button turns the mode on")
	var st2 := _strokes(R, cam2, [], true, 9)
	# the strokes come in through the mouse, one drag each
	for s in st2:
		m._unhandled_input(_mouse(s[0], true))
		for p in s:
			var mm := InputEventMouseMotion.new()
			mm.position = p
			m._unhandled_input(mm)
		m._unhandled_input(_mouse(s[s.size() - 1], false))
	var n_strokes := sk.strokes.size()
	ok(n_strokes == st2.size(), "3b %d drags = %d strokes (5 lines + the head circle)" % [st2.size(), n_strokes])
	m._unhandled_input(_key(KEY_BACKSPACE))
	ok(sk.strokes.size() == n_strokes - 1, "3c Backspace removes the last stroke (%d -> %d)" % [n_strokes, sk.strokes.size()])
	# re-draw the head it took off
	var hs: Array = st2[st2.size() - 1]
	m._unhandled_input(_mouse(hs[0], true))
	for p in hs:
		var mm2 := InputEventMouseMotion.new()
		mm2.position = p
		m._unhandled_input(mm2)
	m._unhandled_input(_mouse(hs[hs.size() - 1], false))
	var u0: int = m.undo.size()
	m._unhandled_input(_key(KEY_ENTER))
	var u1: int = m.undo.size()
	var after: Dictionary = B.state()
	var e4 := _errs(B, R)
	ok(u1 - u0 == 1 and n0 <= u0, "3d Enter fits as ONE undo step (undo %d -> %d)" % [u0, u1])
	ok(after != s_start, "3e the stand became the sketched pose (REPORTED: worst bone %.1f deg from the neutral start, no depth hint)" % _worst(e4)[0])
	var rep5: Dictionary = sk.last
	worst_ms = maxf(worst_ms, float(rep5.get("ms", 0.0)))
	# 5 placement while it is here
	var maxpx := 0.0
	for s in st2.slice(0, 5):
		pass
	for tip in ["hand_l", "hand_r", "foot_l", "foot_r"]:
		var q := cam2.unproject_position(B.P[tip])
		var best := INF
		for s in st2:
			best = minf(best, (s[s.size() - 1] as Vector2).distance_to(q))
		maxpx = maxf(maxpx, best)
	var neck_px := cam2.unproject_position(B.P["neck_01"]).distance_to(st2[0][0])
	ok(maxpx <= 12.0 and neck_px <= 12.0, "5a wrists and ankles within %.1f px of the stroke ends (bar 12), the neck %.1f px from the spine's top" % [maxpx, neck_px])
	var skel: Array = sk.fitted
	var on_body := skel.size() >= 5
	for pl in skel:
		for q: Vector2 in pl:
			var near := false
			for j in ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r", "thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r"]:
				if cam2.unproject_position(B.P[j]).distance_to(q) < 0.5:
					near = true
			if not near and q.distance_to(cam2.unproject_position(LineOfAction.head_c(B))) > 0.5:
				on_body = false
	ok(on_body, "5b the faint skeleton (%d polylines) is drawn on the body's projected joints" % skel.size())
	var vs := root.get_visible_rect().size
	var inside := true
	for s in sk.strokes:
		for p: Vector2 in s:
			if p.x < 0 or p.y < 0 or p.x > vs.x or p.y > vs.y:
				inside = false
	ok(inside, "5c the strokes are inside the window (%dx%d)" % [vs.x, vs.y])
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/i9.png")
	# undo
	m._undo()
	var s_undo: Dictionary = B.state()
	ok(s_undo == s_start and m.undo.size() == u0, "3f Ctrl+Z puts the whole state back exactly (state equal: %s, undo size %d)" % [str(s_undo == s_start), m.undo.size()])
	m._input(_key(KEY_ESCAPE))
	ok(not sk.on and sk.strokes.is_empty(), "3g Esc leaves Sketch mode and drops the strokes")

	# ---- 7 the screenshot of the second step: a SIDE view sketch of strike_lunge (library prior left one out) ---------------
	m.yaw = 90.0
	m._cam()
	await process_frame
	var cam3: Camera3D = m.cam
	var dl := _load("res://poses/lib/strike_lunge.json")
	R.from_dict(dl)
	R.fk()
	B.from_dict(dl)
	_knock(B, 3)
	var stl := _strokes(R, cam3, [], true, 4)
	SketchPose.lib_exclude = "strike_lunge.json"
	var repl := SketchPose.fit(B, cam3, stl)
	SketchPose.lib_exclude = ""
	var el := _errs(B, R)
	print("     strike_lunge side (screenshot): worst bone %s %.1f deg, prior used for %s" % [_worst(el)[1], _worst(el)[0], str(repl.get("prior", []))])
	m._refresh()
	sk.on = true
	sk.strokes = stl
	sk.fitted = repl["skeleton"]
	sk.queue_redraw()
	var hc3 := cam3.unproject_position(R.P["pelvis"])
	var drawn_inside := hc3.x > 0 and hc3.y > 0 and hc3.x < root.get_visible_rect().size.x and hc3.y < root.get_visible_rect().size.y
	ok(drawn_inside and not sk.fitted.is_empty(), "7a PLACEMENT: the side sketch of strike_lunge is inside the window and the fitted skeleton (%d polylines) is on the body" % sk.fitted.size())
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/i9b.png")
	sk.on = false
	sk.strokes = []
	sk.fitted = []
	m.yaw = 0.0
	m._cam()
	await process_frame

	# ---- 8b a click on a handle, through the mouse path; 8d the screenshot ---------------------------------------------------------
	m.yaw = 0.0
	m._cam()
	await process_frame
	var cam4: Camera3D = m.cam
	var pick_path := ""
	var pick_n := 0
	for path in _poses():
		var dp := _load(path)
		R.from_dict(dp)
		R.fk()
		B.from_dict(dp)
		_knock(B, 11)
		var rp := SketchPose.fit(B, cam4, _strokes(R, cam4, [], false, 7))
		var cnt := 0
		for fk in rp["flips"]:
			cnt += 1
		if cnt > pick_n:
			pick_n = cnt
			pick_path = path
	print("     the pose with the most handles (front): %s, %d" % [pick_path.get_file(), pick_n])
	var dpk := _load(pick_path)
	R.from_dict(dpk)
	R.fk()
	B.from_dict(dpk)
	_knock(B, 11)
	m._refresh()
	m._sk_toggle()
	sk.strokes = _strokes(R, cam4, [], true, 7)
	var u_a: int = m.undo.size()
	m._sk_fit()
	ok(m.undo.size() == u_a + 1 and not sk.flips.is_empty(), "8b0 the fit left %d flip handle%s (%s)" % [sk.flips.size(), "" if sk.flips.size() == 1 else "s", ", ".join(sk.flips.keys())])
	var placed := true
	for h in sk.hpos:
		var f: Dictionary = sk.flips[h["key"]]
		var want := cam4.unproject_position(B.P[f["at"]])
		if (h["pos"] as Vector2).distance_to(want) > 1.0 or h["pos"].x < 0 or h["pos"].y < 0 or h["pos"].x > vs.x or h["pos"].y > vs.y:
			placed = false
	ok(placed and sk.hpos.size() == sk.flips.size(), "8b1 PLACEMENT: %d handles sit on the elbows / knees, inside the window" % sk.hpos.size())
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/i9c.png")
	var key0: String = sk.hpos[0]["key"]
	var s_pre: Dictionary = B.state()
	var u_pre: int = m.undo.size()
	var pos0: Vector2 = sk.hpos[0]["pos"]
	var idx_pre: int = sk.flips[key0]["i"]
	var t0 := Time.get_ticks_usec()
	m._unhandled_input(_mouse(pos0 + Vector2(3, 2), true))
	m._unhandled_input(_mouse(pos0 + Vector2(3, 2), false))
	var flip_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	ok(m.undo.size() == u_pre + 1 and B.state() != s_pre and sk.strokes.size() > 0, "8b2 clicking the handle of %s flips that limb to its mirror depth in %.1f ms = ONE undo step (undo %d -> %d)" % [key0, flip_ms, u_pre, m.undo.size()])
	m._undo()
	ok(B.state() == s_pre and m.undo.size() == u_pre, "8b3 Ctrl+Z puts the body back EXACTLY (state equal: %s)" % str(B.state() == s_pre))
	ok(sk.flips.has(key0) and sk.flips[key0]["i"] == idx_pre and sk.hpos.size() == sk.flips.size(), "8b4 the handles are back after the undo, %s on candidate %d" % [key0, idx_pre])
	m._input(_key(KEY_ESCAPE))

	# ---- 8c shoulder line / hip line -----------------------------------------------------------------------------------------
	for cs in [["chest +30", "s", 30.0, 0.0], ["chest -30", "s", -30.0, 0.0], ["hips +30", "h", 0.0, 30.0], ["hips -30", "h", 0.0, -30.0]]:
		R.from_dict(stand)
		for j in ["spine_01", "spine_02", "spine_03"]:
			var a: Vector3 = R.ang[j]
			a.z = float(cs[2]) / 3.0
			R.ang[j] = a
		var ap: Vector3 = R.ang["pelvis"]
		ap.z = float(cs[3])
		R.ang["pelvis"] = ap
		R.fk()
		B.from_dict(stand)
		var str_l := _strokes(R, cam4, [], true, 5, cs[1])
		var r8 := SketchPose.fit(B, cam4, str_l)
		worst_ms = maxf(worst_ms, float(r8["ms"]))
		var key := "sh" if cs[1] == "s" else "hip"
		var fld := "chest_twist" if cs[1] == "s" else "hip_yaw"
		var truth := float(cs[2]) if cs[1] == "s" else float(cs[3])
		var e0 := absf(float(r8[fld]) - truth)
		var flipped := false
		if e0 > 8.0 and r8["flips"].has(key):
			r8 = SketchPose.flip(B, cam4, str_l, r8, key)   # the user's one click on the twist handle
			worst_ms = maxf(worst_ms, float(r8["ms"]))
			flipped = true
		var e1 := absf(float(r8[fld]) - truth)
		ok(e1 <= 8.0, "8c %s: the %s line gives %.1f deg (truth %.0f)%s; handle offered: %s; worst bone %.1f deg from the truth" % [cs[0], "shoulder" if cs[1] == "s" else "hip", float(r8[fld]), truth, (" after one flip (first read %.1f deg off)" % e0) if flipped else "", str(r8["flips"].has(key)), _worst(_errs(B, R))[0]])

	ok(worst_ms < 100.0, "4 the slowest fit of all of them: %.1f ms (bar 100)" % worst_ms)
	print("\nI9 %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
