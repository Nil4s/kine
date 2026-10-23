## godot --path . -s tests/eyelife_test.gd     (ROADMAP I08: living eyes, scripts/eye_life.gd + eye_life_ui.gd; needs a window)
## Everything below is MEASURED FROM THE KEYED TRACK (the face channels sampled every 1 ms through PartKeys.at, the curve the head plays), not
## read off the generator's own lists, except where a measured event is matched to the generator's goal point.
## Scene 1: combo3 (7 cards) with the last card held so the scene lasts 60 s; one fighter looking at a point 2 m in front. The scene already
## has the user's own face keys (brows, jaw, an eye look and a blink key).
## Scene 2: two fighters (the i41 set-up: fighter 2 plays the same clip 0.6 s later, 1.1 m away facing the hero).
## Bars, written before measuring:
##  (1) blinks over the 60 s scene: the measured count gives 15-20 / min
##  (2) every measured blink lasts 100-400 ms and its closing (0 -> shut) is shorter than its opening (shut -> 0)
##  (3) every measured saccade (a run of 1 ms samples where the eye direction moves) lasts the main sequence 2.2 ms/deg x A + 21 ms within
##      10 ms, A = the measured angle between the eye direction before and after; the number of measured saccades equals the generator's
##  (4) at the end of every measured saccade the eye direction is within 1 deg of the direction from the eye to the target, the target
##      worked out by the test at that instant (the point, or the opponent's head / chest / weapon tip from his posed body).
##      AMENDED after the first run (stated, not hidden): combo3's head turns about 45 deg, so some targets lie past the eye's own range
##      (+-45 yaw / +-30 pitch in the head) where no eye can land without a head turn. For those (the test classifies them itself from the
##      target's angles) the bar is: the eye ends within 1 deg of the range's edge (the target's angles clamped), and in scene 1 they are
##      at most 10 % of the saccades.
##  (5) the same seed gives the same track (keys identical); another seed a different one
##  (6) blinks with large gaze shifts: >= 50 % of measured saccades >= 15 deg have a measured blink starting within 5 ms of their onset;
##      with two fighters every incoming strike has a measured blink starting 30-60 ms after it lands; effort on every card raises the rate
##  (7) Accept is ONE undo step and writes the three generated channels exactly; Ctrl+Z restores the face exactly; every other face channel
##      (brows, jaw) is byte-identical after Accept and after Remove; Remove (by tag) leaves no generated key, also after a save + load
##      (Face.to_file / from_file through JSON); Preview changes nothing
##  (8) the instruments can move: the same main-sequence measure on a doctored track (every saccade end key 15 ms late) reports a miss > 10 ms;
##      the same blink counter on a track with the second half's blinks removed reads < 15 / min
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## the eye direction in the head frame (x = the hero's left, y up, z front) from the keyed channel values
func dir_from(yv: float, pv: float) -> Vector3:
	var y := deg_to_rad(clampf(yv, -1, 1) * Face.EYE_YAW_MAX)
	var p := deg_to_rad(clampf(pv, -1, 1) * Face.EYE_PITCH_MAX)
	return Vector3(cos(p) * sin(y), sin(p), cos(p) * cos(y))


## the direction from the eye to world point q, in the head frame, the body posed
func want_dir(B: Body, q: Vector3) -> Vector3:
	var g: Quaternion = B.G["head"]
	var d := (q - LookAt.eye_point(B)).normalized()
	return Vector3(d.dot(g * Vector3(1, 0, 0)), d.dot(g * Vector3(0, 1, 0)), d.dot(g * Vector3(0, 0, 1))).normalized()


## sample a channel's curve every 1 ms over [0, L]
func sample(keys: Array, L: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := int(floor(L * 1000.0)) + 1
	out.resize(n)
	if keys.is_empty():
		return out
	# the cursor keeps the walk short: PartKeys.at on the keys around t (two neighbours each side keep the PCHIP slopes exact)
	var i := 0
	for s in n:
		var t := s * 0.001
		while i < keys.size() - 1 and float(keys[i + 1]["t"]) <= t:
			i += 1
		var a := maxi(0, i - 2)
		var b := mini(keys.size(), i + 4)
		var sub := keys.slice(a, b)
		var v: float = PartKeys.at(sub, t).x if (a == 0 and b == keys.size()) or (t > float(keys[0]["t"]) and t < float(keys[-1]["t"])) else PartKeys.at(keys, t).x
		out[s] = v
	return out


## the measured saccades: [{"t0", "t1", "dur", "amp", "d1"}] from 1 ms samples of yaw / pitch
func saccades(face: Dictionary, L: float) -> Array:
	var ys := sample(face.get("eye_yaw", []), L)
	var ps := sample(face.get("eye_pitch", []), L)
	var out := []
	var s0 := -1
	for s in range(1, ys.size()):
		var mv := rad_to_deg(dir_from(ys[s - 1], ps[s - 1]).angle_to(dir_from(ys[s], ps[s]))) > 1e-4
		if mv and s0 < 0:
			s0 = s - 1
		elif not mv and s0 >= 0:
			var a := dir_from(ys[s0], ps[s0])
			var b := dir_from(ys[s - 1], ps[s - 1])
			out.append({"t0": s0 * 0.001, "t1": (s - 1) * 0.001, "dur": (s - 1 - s0) * 0.001, "amp": rad_to_deg(a.angle_to(b)), "d1": b})
			s0 = -1
	return out


## the measured blinks: [{"t0", "dur", "close", "open"}] from 1 ms samples of the blink channel
func blinks(face: Dictionary, L: float) -> Array:
	var bs := sample(face.get("blink", []), L)
	var out := []
	var s0 := -1
	var f0 := -1
	var f1 := -1
	for s in bs.size():
		var v := bs[s]
		if v > 0.002 and s0 < 0:
			s0 = s
			f0 = -1
		if s0 >= 0 and v >= 0.998:
			if f0 < 0:
				f0 = s
			f1 = s
		if s0 >= 0 and v <= 0.002 and s > s0:
			out.append({"t0": s0 * 0.001, "dur": (s - s0) * 0.001, "close": (f0 - s0) * 0.001 if f0 >= 0 else -1.0, "open": (s - f1) * 0.001 if f0 >= 0 else -1.0})
			s0 = -1
	return out


## the worst main-sequence miss (s) over measured saccades
func ms_worst(sac: Array) -> float:
	var w := 0.0
	for sc in sac:
		w = maxf(w, absf(float(sc["dur"]) - (0.0022 * float(sc["amp"]) + 0.021)))
	return w


## the landing of measured saccades against the generator's goal kinds, the goal recomputed here: [worst error (deg) on the targets the eye can
## reach, worst error (deg) against the range's edge on those it cannot (the target's angles clamped to +-45 / +-30), how many it cannot]
func land_worst(sac: Array, plan: Dictionary, A: Scene, D: Scene, xf: Transform3D) -> Array:
	var BA := DistanceKeeper.new_body()
	var BD := DistanceKeeper.new_body()
	var w := 0.0
	var wc := 0.0
	var nc := 0
	for k in sac.size():
		var gsc: Dictionary = plan["sacc"][k]
		var t := float(sac[k]["t1"])
		A.apply(BA, t)
		BA.fk()
		var q: Vector3 = gsc["pt"]
		if D != null:
			D.apply(BD, t)
			BD.fk()
			match String(gsc["kind"]):
				"head":
					q = xf * LookAt.eye_point(BD)
				"chest":
					q = Gaze.chest(BD, xf)
		var wd := want_dir(BA, q)
		var yd := rad_to_deg(atan2(wd.x, wd.z))
		var pd := rad_to_deg(atan2(wd.y, Vector2(wd.x, wd.z).length()))
		if absf(yd) > Face.EYE_YAW_MAX or absf(pd) > Face.EYE_PITCH_MAX:
			nc += 1
			wc = maxf(wc, rad_to_deg((sac[k]["d1"] as Vector3).angle_to(dir_from(yd / Face.EYE_YAW_MAX, pd / Face.EYE_PITCH_MAX))))
		else:
			w = maxf(w, rad_to_deg((sac[k]["d1"] as Vector3).angle_to(wd)))
	return [w, wc, nc]


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	m.S.cards = m.S.cards.slice(0, 7)
	m.S.cards[-1]["hold"] = float(m.S.cards[-1].get("hold", 0.0)) + 60.0 - m.S.length()
	m._rebuild_cards()
	m._commands()
	await idle()
	var S: Scene = m.S
	var L := S.length()
	ok(absf(L - 60.0) < 0.01, "scene 1 lasts %.3f s" % L)
	# the user's own face keys
	Face.key(S.face, 1.0, {"brow_l": 0.4, "brow_r": -0.2, "jaw": 0.3})
	Face.key(S.face, 5.0, {"brow_l": -0.5, "eye_yaw": 0.3, "blink": 0.5})
	var BA := DistanceKeeper.new_body()
	S.apply(BA, 0.0)
	BA.fk()
	var pt := LookAt.eye_point(BA) + LookAt.head_forward(BA) * 2.0 + Vector3(0.15, -0.1, 0.0)
	var plan := EyeLife.compute(S, {"seed": 7, "point": pt})
	print("       " + String(plan["msg"]))
	var face := EyeLife.applied(S.face, plan)
	# the sampler's short walk equals the full curve (PartKeys.at on all the keys) at 600 instants
	var sw := 0.0
	for ch in EyeLife.CHANNELS:
		var full: Array = face[ch]
		var smp := sample(full, L)
		for k in 200:
			var s := (k * 7919) % smp.size()
			sw = maxf(sw, absf(smp[s] - PartKeys.at(full, s * 0.001).x))
	ok(sw <= 1e-6, "the 1 ms sampler equals the full curve (worst %.9f)" % sw)

	# (1) (2) blinks
	var bl := blinks(face, L)
	var rate := float(bl.size()) / L * 60.0
	ok(rate >= 15.0 and rate <= 20.0, "(1) %d measured blinks in %.1f s = %.1f / min (bar 15-20)" % [bl.size(), L, rate])
	var dmin := INF
	var dmax := 0.0
	var shape_ok := true
	var ratio := 0.0
	for b in bl:
		dmin = minf(dmin, float(b["dur"]))
		dmax = maxf(dmax, float(b["dur"]))
		shape_ok = shape_ok and float(b["close"]) > 0.0 and float(b["close"]) < float(b["open"])
		ratio += float(b["open"]) / maxf(1e-6, float(b["close"]))
	ok(not bl.is_empty() and dmin >= 0.1 and dmax <= 0.4 and shape_ok, "(2) every blink lasts %.0f-%.0f ms (bar 100-400) and closes faster than it opens (open / close %.2f on average)" % [dmin * 1000.0, dmax * 1000.0, ratio / maxf(1, bl.size())])

	# (3) (4) saccades
	var sac := saccades(face, L)
	var wms := ms_worst(sac)
	var amin := INF
	var amax := 0.0
	for sc in sac:
		amin = minf(amin, float(sc["amp"]))
		amax = maxf(amax, float(sc["amp"]))
	ok(sac.size() == plan["sacc"].size() and sac.size() > 100 and wms <= 0.010, "(3) %d measured saccades (generator %d), amplitude %.1f-%.1f deg, worst main-sequence miss %.1f ms (bar 10)" % [sac.size(), plan["sacc"].size(), amin, amax, wms * 1000.0])
	var fmin := INF
	var fmax := 0.0
	for k in range(1, sac.size()):
		var f := float(sac[k]["t0"]) - float(sac[k - 1]["t1"])
		fmin = minf(fmin, f)
		fmax = maxf(fmax, f)
	print("       fixations between saccades %.0f-%.0f ms (several fixations merge when a re-fixation is under %.1f deg)" % [fmin * 1000.0, fmax * 1000.0, EyeLife.MIN_AMP])
	ok(fmin >= 0.198, "(3) no fixation is shorter than 200 ms (shortest %.0f ms)" % (fmin * 1000.0))
	var lw: Array = land_worst(sac, plan, S, null, Transform3D.IDENTITY) if sac.size() == plan["sacc"].size() else [INF, INF, 0]
	ok(float(lw[0]) <= 1.0 and float(lw[1]) <= 1.0 and int(lw[2]) * 10 <= sac.size(), "(4) %d saccades land within %.3f deg of their target (bar 1 deg); %d whose target is past the eye's range (bar <= 10 %%) end within %.3f deg of the range's edge" % [sac.size() - int(lw[2]), lw[0], lw[2], lw[1]])

	# (5) determinism
	var p2 := EyeLife.compute(S, {"seed": 7, "point": pt})
	var p3 := EyeLife.compute(S, {"seed": 8, "point": pt})
	ok(var_to_str(p2["keys"]) == var_to_str(plan["keys"]) and var_to_str(p3["keys"]) != var_to_str(plan["keys"]), "(5) seed 7 twice: identical tracks (%d keys); seed 8: a different track" % (plan["keys"]["eye_yaw"].size() + plan["keys"]["blink"].size()))

	# (6) gaze-coupled blinks and effort
	var big := 0
	var with_b := 0
	for sc in sac:
		if float(sc["amp"]) < EyeLife.LARGE_DEG:
			continue
		big += 1
		for b in bl:
			if absf(float(b["t0"]) - float(sc["t0"])) <= 0.005:
				with_b += 1
				break
	ok(big >= 2 and with_b * 2 >= big, "(6) %d of %d large gaze shifts (>= %.0f deg) carry a blink starting within 5 ms of their onset (bar >= 50 %%)" % [with_b, big, EyeLife.LARGE_DEG])
	var Se := S.clone()
	for c in Se.cards:
		c["expr"] = "effort"
	var pe := EyeLife.compute(Se, {"seed": 7, "point": pt})
	var be := blinks(EyeLife.applied(Se.face, pe), L)
	var rate_e := float(be.size()) / L * 60.0
	ok(rate_e > rate + 3.0, "(6) effort on every card: %.1f blinks / min against %.1f at rest" % [rate_e, rate])

	# (8) the instruments can move
	var doc := (plan["keys"] as Dictionary).duplicate(true)
	for ch in ["eye_yaw", "eye_pitch"]:
		for k in range(2, (doc[ch] as Array).size(), 2):
			doc[ch][k]["t"] = float(doc[ch][k]["t"]) + 0.015
	var dsac := saccades(doc, L)
	var bdoc := (plan["keys"] as Dictionary).duplicate(true)
	var half := []
	for k in bdoc["blink"]:
		if float(k["t"]) < L * 0.5:
			half.append(k)
	bdoc["blink"] = half
	var brate := float(blinks(bdoc, L).size()) / L * 60.0
	ok(ms_worst(dsac) > 0.010 and brate < 15.0, "(8) the measures move: end keys 15 ms late -> main-sequence miss %.1f ms; half the blinks -> %.1f / min" % [ms_worst(dsac) * 1000.0, brate])

	# (7) preview, accept, undo, remove
	var ui = m.el_ui
	var f0 := var_to_str(S.face)
	var u0: int = m.undo.size()
	ui.plan = plan
	ui.preview()
	for i in 5:
		await process_frame
	var pv_on: bool = ui.pv
	var pz: Dictionary = ui.pose_now()
	ui.halt()
	ok(pv_on and var_to_str(S.face) == f0 and m.undo.size() == u0 and pz.has("eye_yaw_deg"), "(7) Preview plays the new eyes on the head and changes nothing (face and undo stack identical)")
	var others := func(fc: Dictionary) -> String:
		var o := {}
		for ch in fc:
			if not EyeLife.CHANNELS.has(ch):
				o[ch] = fc[ch]
		return var_to_str(o)
	var oth0: String = others.call(S.face)
	ui.accept()
	await idle()
	S = m.S
	var gen_ok := true
	for ch in EyeLife.CHANNELS:
		gen_ok = gen_ok and var_to_str(S.face[ch]) == var_to_str(plan["keys"][ch])
	ok(m.undo.size() == u0 + 1 and gen_ok and others.call(S.face) == oth0 and S.face.has("brow_l") and S.face.has("jaw"),
		"(7) Accept is one undo step (%d -> %d), the three channels are the plan, brows and jaw byte-identical" % [u0, m.undo.size()])
	m._undo()
	await idle()
	ok(var_to_str(m.S.face) == f0 and m.undo.size() == u0, "(7) Ctrl+Z restores the face exactly")
	ui.accept()
	await idle()
	S = m.S
	var disk: Dictionary = Face.from_file(JSON.parse_string(JSON.stringify(Face.to_file(S.face))))
	var on_disk := EyeLife.count(disk)
	var n_rm := EyeLife.remove(disk)
	var u1: int = m.undo.size()
	ui.remove()
	await idle()
	S = m.S
	ok(EyeLife.count(S.face) == 0 and m.undo.size() == u1 + 1 and others.call(S.face) == oth0 and not S.face.has("eye_yaw") and not S.face.has("blink"),
		"(7) Remove is one undo step and takes every generated key out; brows and jaw byte-identical")
	ok(on_disk == EyeLife.count(plan["keys"]) and n_rm == on_disk and EyeLife.count(disk) == 0 and others.call(disk) == others.call(Face.from_file(JSON.parse_string(JSON.stringify(Face.to_file(S.face))))),
		"(7) after save + load the %d tags are still there and Remove takes them all out" % on_disk)

	# scene 2: two fighters
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	m.S.cards = m.S.cards.slice(0, 7)
	m._rebuild_cards()
	var d2: Scene = m.S.clone()
	d2.cards[0]["hold"] = float(d2.cards[0].get("hold", 0.0)) + 0.6
	d2.part_keys = {}
	m.S.actors.append({"name": "fighter 2", "xf": {"pos": [0.0, 1.1], "yaw": 180.0}, "scene": d2})
	m._actors_sync()
	m._refresh()
	await idle()
	ui.show()
	await idle()
	var A: Scene = m.actors_rt[0]["S"]
	var D: Scene = m.actors_rt[1]["S"]
	var X: Transform3D = (m.actors_rt[0]["xf"] as Transform3D).affine_inverse() * (m.actors_rt[1]["xf"] as Transform3D)
	var p2f: Dictionary = ui.plan
	print("       two fighters: " + String(p2f["msg"]))
	ok(p2f.get("two", false), "two fighters: the panel targets the opponent")
	var L2 := float(p2f["L"])
	var f2 := EyeLife.applied(A.face, p2f)
	var sac2 := saccades(f2, L2)
	var kinds := {}
	for g in p2f["sacc"]:
		kinds[g["kind"]] = int(kinds.get(g["kind"], 0)) + 1
	var lw2: Array = land_worst(sac2, p2f, A, D, X) if sac2.size() == p2f["sacc"].size() else [INF, INF, 0]
	ok(sac2.size() == p2f["sacc"].size() and ms_worst(sac2) <= 0.010 and float(lw2[0]) <= 1.0 and float(lw2[1]) <= 1.0,
		"(3)(4) two fighters: %d measured saccades %s, worst main-sequence miss %.1f ms, worst landing %.3f deg on the opponent (head / chest recomputed here); %d past the eye's range end within %.3f deg of its edge" % [sac2.size(), str(kinds), ms_worst(sac2) * 1000.0, lw2[0], lw2[2], lw2[1]])
	var bl2 := blinks(f2, L2)
	var td := D.times()
	var hit_ok := true
	var nh := 0
	for i in BeatFight.contacts(D):
		nh += 1
		var h := float(td[i][1])
		var got := false
		for b in bl2:
			got = got or (float(b["t0"]) - h >= 0.03 and float(b["t0"]) - h <= 0.06)
		hit_ok = hit_ok and got
	ok(nh >= 2 and hit_ok, "(6) each of the %d incoming strikes has a blink starting 30-60 ms after it lands" % nh)

	print("I08 LIVING EYES %s" % ("FAIL" if fails > 0 else "PASS") + (" (%d failed)" % fails if fails > 0 else ""))
	quit(1 if fails > 0 else 0)
