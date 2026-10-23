## clip_lint.gd - LINT ANY CLIP (docs/INNOVATIONS.md N018). A clip made ANYWHERE (Blender, Mixamo, an agent's own code) as
## .bvh / .glb / .gltf / .fbx is read, put on Kine's body and judged by the judges Kine already has; the answer is ONE
## JSON object an agent's pipeline can gate on. Nothing is re-implemented here:
##   READ + RETARGET  scripts/anim_import.gd: a .bvh with Kine's joint names through BvhImport (exact), anything else through
##                    AnimImport.load_source / map_bones / retarget (FBX through Godot 4.7's FBXDocument = ufbx, already in
##                    anim_import). The DENSE scene is judged (one card per file frame, linear): the file's own motion, not
##                    MocapClean's foot lock (that would hide the very slide we judge); the judges play it thinned within 1 deg / 5 mm.
##   JOINT RANGE      the file's angles BEFORE the body clamps them (Scene.put clamps to data/body_limits.json on playback, so
##                    Check never sees a hyperextended elbow): a run of frames where a joint is past Kine's range.
##   CHECK            Rulebook.check with the human-limit rules on, exactly as the realism score asks it (RealismUI.gather):
##                    foot slide, balance, tipping, joint speed caps (HumanLimits), Feasible (KungfuBot balance, free fall,
##                    slide per contact, self-penetration), the strike rules ...
##   SCORE            RealismScore.compute over the same answers + the I45 judges (JudgeSuite through gather). The timing coach
##                    runs on its cited ranges only (no move database: building it reads every scene, ~20 s).
## RETARGET QUALITY is reported (mapped): which Kine joints came from a bone found by NAME, which were GUESSED from the
## skeleton's structure (the spine between the hips and the neck), which stayed at REST (no bone), and the file's bones not
## used. A finding on a guessed or missing joint says so in its trust field: a bad mapping must not be blamed on the animator.
## Each finding: {rule, sev ("must fix" / "look"), frames [first, last] in the FILE's frames, value, unit, bar, trust, msg}
## where value > bar is what made it a finding.
class_name ClipLint
extends RefCounted

const EXTS := ["bvh", "glb", "gltf", "fbx"]
## JOINT RANGE: degrees past Kine's range before a run of frames is a finding / a must-fix. HEURISTIC (ours): a retarget from
## another rig leaves a few degrees of rest-pose mismatch (anim_import's FBX fixture: arms 40 deg A-pose corrected to 0.5),
## and the range itself is Kine's table (data/body_limits.json), not a measured population limit.
const RANGE_TOL := 3.0
const RANGE_FAIL := 10.0
## a planted foot's step must be over this per 60 fps frame (0.5 mm = 3 cm/s) to count as WHERE it slides (see _moving).
## HEURISTIC (ours): Rulebook.FOOT_STILL (5 mm/frame) is the ceiling for "planted"; a still foot moves 0.
const SLIDE_STEP := 0.0005

## rule -> [unit, multiplier on Rulebook's v, bar in that unit, trust]. Rules not listed keep v as it is (unit "").
## MEASURED = a number read from a cited source (Rulebook.SRC has it); HEURISTIC = Kine's own bar.
const RULES := {
	"FOOT SLIDE": ["cm", 100.0, Rulebook.FOOT_SKATE * 100.0, "MEASURED: Karunratanakul et al. 2023 (arXiv:2310.08580)"],
	"FEASIBLE SLIDE": ["cm", 100.0, Feasible.SLIDE_FIX * 100.0, "MEASURED: Karunratanakul et al. 2023 (arXiv:2310.08580)"],
	"FEASIBLE PENETRATION": ["cm", 100.0, Feasible.PEN_FIX * 100.0, "HEURISTIC: Kine's bar (Body.contacts capsules)"],
	"FEASIBLE BALANCE": ["cm", 100.0, Feasible.EPS_STAB * 100.0, "MEASURED: KungfuBot, Xie et al. 2025 (arXiv:2506.12851) Table 3; the unit is assumed"],
	"FEASIBLE FLIGHT": ["cm", 100.0, Feasible.BALLISTIC_TOL * 100.0, "HEURISTIC: Kine's bar around free fall (g = 9.81)"],
	"BALANCE": ["cm", 100.0, Rulebook.BAL_OUT * 100.0, "HEURISTIC: Kine's bar; masses from de Leva 1996"],
	"TIPPING": ["s", 1.0, null, "HEURISTIC: the free-fall time sqrt(2h/g) of the centre of mass"],
	"JOINT SPEED": ["deg/s", 1.0, null, "MEASURED: in-sport peaks (docs/research/HUMAN_LIMITS.md)"],
	"JOINT TORQUE": ["Nm", 1.0, null, "MEASURED: Fleisig 1995, scaled by mass (docs/research/HUMAN_LIMITS.md)"],
	"FIST SPEED": ["m/s", 1.0, Rulebook.FIST_WARN, "MEASURED: Stanley et al. 2018"],
	"HEAD QUIET": ["cm", 100.0, Rulebook.HEAD_WARN * 100.0, "MEASURED + HEURISTIC: hitters' heads ~9 cm (Inkster et al.) + Kine's 6 cm grace"],
}


static func _err(file: String, why: String) -> Dictionary:
	return {"ok": false, "file": file, "error": why}


## a path as given on the command line -> one Godot can open: absolute paths (C:/..., /...) as they are, res:// and user://
## as they are, anything else relative to the project
static func resolve(path: String) -> String:
	var p := path.strip_edges().replace("\\", "/")
	if p.begins_with("res://") or p.begins_with("user://") or p.is_absolute_path():
		return p
	return "res://" + p


static func _frame(t: float, fps: int, last: int) -> int:
	return clampi(roundi(t * fps), 0, last)


## the file -> the lint (see the head). m: a live poser (main); its scene and body are put back.
static func lint(m: Node, path: String) -> Dictionary:
	var t_start := Time.get_ticks_msec()
	if path.strip_edges() == "":
		return _err(path, "lint needs a file: lint <clip.bvh|.glb|.gltf|.fbx>")
	var p := resolve(path)
	var ext := p.get_extension().to_lower()
	if not FileAccess.file_exists(p):
		return _err(path, "no such file: %s" % path)
	if not ext in EXTS:
		return _err(path, "%s is not a clip Kine can read: .bvh, .glb, .gltf or .fbx" % path.get_file())
	var B: Body = m.B
	var keep_state: Dictionary = B.state()
	var keep_body: Dictionary = B.body.duplicate(true)
	if not keep_body.is_empty():
		B.set_proportions({})   # the dense scene has no body of its own: it plays on the mannequin (as AnimImport does)
	var r := _lint(m, B, p, ext)
	if not keep_body.is_empty():
		B.set_proportions(keep_body)
	B.set_state(keep_state)
	B.fk()
	r["file"] = path
	r["ms"] = Time.get_ticks_msec() - t_start
	if not r["ok"]:
		return {"ok": false, "file": path, "error": r["error"]}
	return r


static func _lint(m: Node, B: Body, p: String, ext: String) -> Dictionary:
	var name := p.get_file().get_basename()
	var D: Scene = null
	var mapped := {}
	var how := ""
	if ext == "bvh":
		var bv := BvhImport.load_file(p)
		if not bv["ok"]:
			return _err(p, "not a readable BVH: %s" % bv.get("why", "?"))
		if (bv["frames"] as Array).size() < 2:
			return _err(p, "the BVH has %d frame(s): a clip needs two or more" % (bv["frames"] as Array).size())
		if (bv["joints"] as Array).any(func(j): return j["name"] == "pelvis"):
			var ts := BvhImport.to_scene(bv, B, 1, 1.0, name)
			if not ts["ok"]:
				return _err(p, String(ts["why"]))
			D = ts["scene"]
			how = "kine"
			var exact := []
			for j in Body.ORDER:
				if not j in ts["missing"]:
					exact.append(j)
			mapped = _mapped_kine(exact, ts["missing"], ts["not_mapped"])
	if D == null:
		var src := AnimImport.load_source(p)
		if not src["ok"]:
			return _err(p, "not a readable clip: %s" % src.get("why", "?"))
		if (src["frames"] as Array).size() < 2:
			return _err(p, "the clip has %d frame(s): a clip needs two or more" % (src["frames"] as Array).size())
		var mp := AnimImport.map_bones(src)
		var rt := AnimImport.retarget(src, mp, B, name)
		if not rt["ok"]:
			return _err(p, "could not put it on Kine's body: %s" % rt["why"])
		D = rt["scene"]
		how = "retarget"
		mapped = _mapped_retarget(src, mp, rt)
	var fps: int = D.fps
	var last := D.cards.size() - 1
	var findings := _range(D, B, fps, mapped)
	# CHECK + SCORE through the realism score's own gather (Check with the human limits, force view, push limits, the I45
	# judges); the live scene is put back after. They judge the dense scene THINNED as an import thins it (AnimImport.refine:
	# every file frame still plays within 1 deg per joint angle and 5 mm of hips), because a pose costs time per card: 601
	# poses of a 301-card clip took 1483-1972 ms, of its 83-card thinning 665-748 ms (idle_bat x 10 s, measured), and every
	# judge plays the clip at 60 fps on its own. The JOINT RANGE pass above read every frame of the file itself.
	var every := VideoImport.every_for(D.fps)
	var J := VideoImport.thin(D, every, AnimImport.refine(D, every))
	var keep_S: Scene = m.S
	var keep_path: String = m.scene_path
	var keep_find: Array = m.findings
	m.S = J
	m.scene_path = ""
	var ui := RealismUI.new(m)
	var inp := ui.gather({})
	var sc := RealismScore.compute(J, inp)
	var sm: Dictionary = ui._memo.get("sm", {})
	m.S = keep_S
	m.scene_path = keep_path
	m.findings = keep_find
	for f in inp["findings"]:
		findings.append(_from_check(f, fps, last, sm, mapped))
	findings.sort_custom(func(a, b): return int(a["frames"][0]) < int(b["frames"][0]))
	var must := findings.filter(func(f): return f["sev"] == "must fix").size()
	var reasons := []
	for it in sc["reasons"]:
		reasons.append({"judge": it["judge"], "frames": [_frame(float(it["t0"]), fps, last), _frame(float(it["t1"]), fps, last)],
			"points": snappedf(float(it["pen"]), 0.1), "text": it["text"]})
	return {"ok": true, "format": ext, "how": how, "fps": fps, "frames": D.cards.size(), "length_s": snappedf(D.length(), 0.001), "judged_cards": J.cards.size(),
		"mapped": mapped, "findings": findings, "must_fix": must, "clean": findings.is_empty(),
		"score": roundi(float(sc["score"])), "score_raw": snappedf(float(sc["raw"]), 0.1), "score_reasons": reasons,
		"score_note": "RealismScore (I16 + I45 judges); the timing coach judged on its cited ranges only (no move database)"}


## a Kine .bvh: every joint by its own name
static func _mapped_kine(exact: Array, missing: Array, not_mapped: Array) -> Dictionary:
	var main_missing := missing.filter(func(j): return j in AnimImport.MAIN)
	return {"how": "Kine's own joint names (exact, no retarget)", "main": AnimImport.MAIN.size() - main_missing.size(),
		"of": AnimImport.MAIN.size(), "by_name": exact, "guessed": [], "at_rest": main_missing,
		"fingers_at_rest": missing.size() - main_missing.size(), "unused_bones": not_mapped, "rest_deg": {},
		"quality": "exact" if main_missing.is_empty() else "partial"}


## another skeleton: by name / guessed from structure / at rest, the bones not used, the rest-pose difference per joint
static func _mapped_retarget(src: Dictionary, mp: Dictionary, rt: Dictionary) -> Dictionary:
	var by_name := []
	var guessed := []
	var pairs := {}
	for j in Body.ORDER:
		if not mp["map"].has(j):
			continue
		pairs[j] = src["names"][mp["map"][j]]
		if String(mp["how"].get(j, "name")) == "structure":
			guessed.append(j)
		else:
			by_name.append(j)
	var at_rest: Array = (mp["missing"] as Array).filter(func(j): return j in AnimImport.MAIN)
	var fing := (mp["missing"] as Array).size() - at_rest.size()
	var q := "good"
	if not at_rest.is_empty() or int(mp["main"]) < AnimImport.MAIN.size():
		q = "partial"
	if int(mp["main"]) < 18:
		q = "poor"
	return {"how": "retargeted from %s (%s): %s" % [src.get("format", "?"), src.get("clip", "?"), rt["text"]], "main": mp["main"],
		"of": AnimImport.MAIN.size(), "by_name": by_name, "guessed": guessed, "at_rest": at_rest, "fingers_at_rest": fing,
		"unused_bones": mp["unmapped"], "pairs": pairs, "rest_deg": rt["rest_deg"], "leg_ratio": snappedf(float(rt["ratio"]), 0.0001),
		"quality": q}


## what a finding on these joints can be trusted for, given the mapping ("" = mapped by name)
static func _map_trust(mapped: Dictionary, joints: Array) -> String:
	var g := joints.filter(func(j): return j in mapped["guessed"])
	var r := joints.filter(func(j): return j in mapped["at_rest"])
	var s := []
	if not g.is_empty():
		s.append("%s placed by the skeleton's structure, not by name" % ", ".join(PackedStringArray(g)))
	if not r.is_empty():
		s.append("%s had no bone in the file and stayed at rest" % ", ".join(PackedStringArray(r)))
	return "; ".join(PackedStringArray(s))


## JOINT RANGE over the dense scene's own angles (unclamped): runs of frames past Kine's range, per joint, axis and side
static func _range(D: Scene, B: Body, fps: int, mapped: Dictionary) -> Array:
	var out := []
	var open := {}   # "joint|axis|lo/hi" -> {a, b, worst, at, reached}
	var n := D.cards.size()
	for i in n + 1:
		var seen := {}
		if i < n:
			var js: Dictionary = D.cards[i]["pose"]["joints"]
			for j in js:
				if not B.lim.has(j):
					continue
				for ax in ["bend", "side", "twist"]:
					var v := float(js[j][ax])
					var L: Vector2 = B.lim[j][ax]
					var ex := maxf(L.x - v, v - L.y)
					if ex <= RANGE_TOL:
						continue
					var k := "%s|%s|%s" % [j, ax, "lo" if v < L.x else "hi"]
					seen[k] = true
					if not open.has(k):
						open[k] = {"a": i, "b": i, "worst": ex, "reached": v}
					open[k]["b"] = i
					if ex > float(open[k]["worst"]):
						open[k]["worst"] = ex
						open[k]["reached"] = v
		for k in open.keys():
			if seen.has(k):
				continue
			var o: Dictionary = open[k]
			open.erase(k)
			var pr: PackedStringArray = String(k).split("|")
			var j := pr[0]
			var ax := pr[1]
			var L: Vector2 = B.lim[j][ax]
			var locked := L.y - L.x < 0.5
			var worst := float(o["worst"])
			var trust := "HEURISTIC: Kine's joint range (data/body_limits.json), not a measured population limit"
			if locked:
				trust += "; Kine's %s has no %s at all, so this can be how the source rig spreads the motion (a mapping matter)" % [j, ax]
			var mt := _map_trust(mapped, [j, B.parent[j]] if B.parent[j] != "" else [j])
			if mt != "":
				trust += "; RETARGET: " + mt
			var sev := "must fix" if worst >= RANGE_FAIL and not locked and mt == "" else "look"
			out.append({"rule": "JOINT RANGE", "sev": sev, "frames": [o["a"], o["b"]], "value": snappedf(worst, 0.1), "unit": "deg past the range",
				"bar": RANGE_TOL, "trust": trust, "joint": j, "axis": ax, "reached": snappedf(float(o["reached"]), 0.1), "range": [L.x, L.y],
				"msg": "frames %d-%d: %s %s reaches %.1f deg, %.1f deg past Kine's range %.0f..%.0f" % [o["a"], o["b"], _nice(j), ax,
					float(o["reached"]), worst, L.x, L.y]})
	return out


static func _nice(j: String) -> String:
	var w := j.replace("lowerarm", "elbow").replace("upperarm", "shoulder").replace("calf", "knee").replace("thigh", "hip").replace("foot", "ankle")
	if w.ends_with("_l"):
		return "left " + w.left(-2).replace("_", " ")
	if w.ends_with("_r"):
		return "right " + w.left(-2).replace("_", " ")
	return w.replace("_", " ")


## a Rulebook finding -> the lint's shape, in the file's frames
static func _from_check(f: Dictionary, fps: int, last: int, sm: Dictionary, mapped: Dictionary) -> Dictionary:
	var rule := String(f["rule"])
	var t0 := float(f["t"])
	var t1 := float(f.get("t1", t0))
	var spec: Array = RULES.get(rule, ["", 1.0, null, "see source"])
	var v := float(f.get("v", 0.0)) * float(spec[1])
	var bar = spec[2]
	if rule == "JOINT SPEED" and f.has("joint"):
		var kind := String(f["joint"]).split("_")[0]
		if HumanLimits.SPEED.has(kind):
			bar = HumanLimits.SPEED[kind]
	var o := {"rule": rule, "sev": "must fix" if f["sev"] == "FAIL" else "look", "frames": [_frame(t0, fps, last), _frame(t1, fps, last)],
		"value": snappedf(v, 0.01), "unit": spec[0], "bar": bar, "trust": spec[3], "msg": String(f["msg"]).get_slice("\n", 0),
		"source": Rulebook.SRC.get(rule, "")}
	if rule == "FOOT SLIDE" or rule == "FEASIBLE SLIDE":
		var sd := String(f.get("foot", ""))
		if sd == "":
			sd = "_l" if String(f["msg"]).contains("left foot") else "_r"
		o["foot"] = "left" if sd == "_l" else "right"
		o["planted"] = o["frames"].duplicate()
		var mv := _moving(sm, "ball" + sd, t0, t1)
		if not mv.is_empty():
			o["frames"] = [_frame(mv[0], fps, last), _frame(mv[1], fps, last)]
		var mt := _map_trust(mapped, ["thigh" + sd, "calf" + sd, "foot" + sd, "ball" + sd, "pelvis"])
		if mt != "":
			o["trust"] = String(o["trust"]) + "; RETARGET: " + mt
	elif mapped["quality"] == "poor":
		o["trust"] = String(o["trust"]) + "; RETARGET: only %d of %d main joints mapped, the whole body is in doubt" % [mapped["main"], mapped["of"]]
	return o


## inside a planted stretch [t0, t1], WHERE the foot slides: the first and last 60 fps step of at least half the stretch's
## fastest step (and over SLIDE_STEP). The stretch itself starts when the foot came down, often long before the slide; a
## standing idle sways its planted feet up to 0.76 mm a frame (scenes/idle_bat.json, measured), so a fixed small step would
## start the slide at the first sway. [] = no such step
static func _moving(sm: Dictionary, key: String, t0: float, t1: float) -> Array:
	if not sm.has(key):
		return []
	var s: Array = sm[key]
	var ts: Array = sm["t"]
	var steps := {}
	var top := 0.0
	for i in range(1, s.size()):
		var t := float(ts[i])
		if t < t0 - 1e-6 or t > t1 + 1e-6:
			continue
		var d: Vector3 = (s[i] as Vector3) - (s[i - 1] as Vector3)
		steps[i] = Vector2(d.x, d.z).length()
		top = maxf(top, steps[i])
	var a := -1.0
	var b := -1.0
	for i in steps:
		if float(steps[i]) >= maxf(SLIDE_STEP, 0.5 * top):
			if a < 0.0:
				a = float(ts[i - 1])
			b = float(ts[i])
	return [] if a < 0.0 else [a, b]


## the lint as lines a person reads
static func lines(r: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if not r["ok"]:
		out.append("LINT %s: ERROR %s" % [r["file"], r["error"]])
		return out
	var mp: Dictionary = r["mapped"]
	out.append("LINT %s: %s, %d frames at %d fps (%.2f s), %d ms" % [r["file"], r["format"], r["frames"], r["fps"], r["length_s"], r["ms"]])
	out.append("  mapping (%s): %d of %d main joints; %s" % [mp["quality"], mp["main"], mp["of"], mp["how"]])
	if not (mp["guessed"] as Array).is_empty():
		out.append("    guessed from structure: " + ", ".join(PackedStringArray(mp["guessed"])))
	if not (mp["at_rest"] as Array).is_empty():
		out.append("    no bone, at rest: " + ", ".join(PackedStringArray(mp["at_rest"])))
	if not (mp["unused_bones"] as Array).is_empty():
		out.append("    file bones not used: %s%s" % [", ".join(PackedStringArray((mp["unused_bones"] as Array).slice(0, 12))),
			" and %d more" % ((mp["unused_bones"] as Array).size() - 12) if (mp["unused_bones"] as Array).size() > 12 else ""])
	for f in r["findings"]:
		out.append("  %-8s %-20s frames %4d-%-4d %8s %-18s bar %s   %s" % [f["sev"].to_upper(), f["rule"], f["frames"][0], f["frames"][1],
			str(f["value"]), f["unit"], str(f["bar"]) if f["bar"] != null else "-", f["msg"]])
	out.append("LINT %s: %d findings, %d must fix, realism score %d" % ["clean" if r["clean"] else "done", r["findings"].size(), r["must_fix"], r["score"]])
	return out
