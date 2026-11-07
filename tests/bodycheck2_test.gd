## godot --headless --path . -s tests/bodycheck2_test.gd     (L102: N056 stylised proportions with consequences, N058 can this body stand, N060 looks strong enough; scripts/body_check.gd)
## BARS WRITTEN AND COMMITTED BEFORE THE CODE. None was changed after a run.
## SOURCES (ALL QUOTED FROM MEMORY, NOT RE-READ THIS SESSION: reported UNVERIFIED; no web tables were opened)
##  * Muscle specific tension (force per physiological cross-section): about 30-40 N/cm^2, used 35 N/cm^2 as the limit, UNVERIFIED (from memory) (Zatsiorsky & Prilutsky 2012,
##    Biomechanics of Skeletal Muscles, ch. 2; the same range in Maganaris et al. 2001 / Narici 1992 for the quadriceps, 22-40).
##  * Quadriceps physiological cross-section 85.9 cm^2 = sum of the Table 3 means RF 13.5 + VL 35.1 + VI 16.7 + VM 20.6 (Ward et al. 2009, Clin Orthop Relat Res 467:1074, PMID 18972175; CHECKED 11-06; the earlier 87 appears nowhere in the paper).
##  * Knee extensor moment arm about 4.5 cm at 60 deg flexion UNVERIFIED (from memory) (Herzog & Read 1993): scaled with thigh length.
##  * Compact (cortical) bone, ultimate compressive stress along the shaft 170 MPa (Reilly & Burstein 1975, J Biomech 8:393: femur 167-193 MPa; UNVERIFIED (from memory), range not confirmed);
##    flagged at half of it (fatigue/safety, MINE, stated). Tibial mid-shaft cortical area about 3.3 cm^2 (Ruff & Hayes 1983, order of 330 mm^2; UNVERIFIED (from memory), no source found).
##  * Walking loads the tibia at about 4 body weights (Burdett 1982 is a RUNNING ankle-force paper, not walking tibia load; Komi; order of 3-5 BW; UNVERIFIED (no source found)): the bone check uses single-leg stance x 4.
##  * Elbow / shoulder moment arms 4.0 / 5.0 cm (Murray et al. 1995; order of magnitude; UNVERIFIED (from memory)): the default arm's capacity is set equal to ForceView.LIMIT_NM.
## BARS
##  N056  A1 the default body gives no breaks (breaks == []), the hand reaches the face with margin > 0
##        A2 a chibi (head x1.8, same stature): its face margin = (upper arm + forearm) - |wrist target - shoulder| computed here independently from
##           Proportions.lengths within 5 mm; if negative, the IK miss (LimbIK.solve) matches the gap within 5 mm; breaks list "can't touch his face"
##           or "reduced face reach" with numbers; the margin is smaller than the default's
##        A3 jab reach (shoulder -> knuckle at full extension): the change against the default equals the change of (upper arm + forearm + hand) within 1 cm
##           for arms x1.25 and x0.8; the reported delta_cm matches within 0.5 cm
##        A4 head mass share equals de Leva head % x f / sum within 0.3 percentage points (f = (head length / default head length at that stature)^3);
##           the chibi's share is more than 3 points above the default's and the COM moves up; the COM height equals the closed form within 2 mm
##  N058  B1 uniform size x2 with mass x8 (geometric similarity): bone and muscle stress x2 within 3 %
##        B2 legs thinned to 0.5x radius: bone and muscle stress x4 within 3 %; mass x2 doubles both within 3 % (control)
##        B3 cited-limit fixture: the default body (75 kg) is NOT flagged, the 0.5x-radius legs ARE flagged ("too thin"); both against the limits above
##        B4 the stress is the independent F / A computed here from the output's own force and area within 1 %
##  N060  C1 torque capacity is proportional to girth^2 within 3 % (girth x1.3 and x2.0; upperarm_r, lowerarm_r, calf_l)
##        C2 a planted 200 N m at the shoulder: a thin arm (0.6x girth) is flagged "skinny", a bulked arm (1.5x) passes; the needed muscle area is reported
##        C3 on scenes/swing_fore.json the default body's ratio for the peak joint equals ForceView peak / LIMIT_NM within 3 %; arms at 0.6x girth give 1/0.36 of it within 3 %
##  D     all three are read-only: scene dict and body state byte-identical, no undo step, deterministic; the three tools are registered (agent_tools.gd, poser_mcp.py)
extends SceneTree

var fails := 0
const LIM_BONE_MPA := 170.0
const LIM_MUSCLE := 35.0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func mk(d: Dictionary) -> Body:
	var b := Body.new()
	b.body = d
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	for j in Body.ORDER:
		b.ang[j] = Vector3.ZERO
	b.offset = Vector3.ZERO
	b.fk()
	return b


## the face point and the margin, written here from the documented definition
func face_margin(b: Body) -> Dictionary:
	var cv := Proportions.cervicale(b)
	var hh := Proportions.head_top(b).y - cv.y
	var f := cv + Vector3(0, 0.5 * hh, 0.4 * hh)
	var s: Vector3 = b.P["upperarm_l"]
	var L := Proportions.lengths(b)
	var hand := float(L["hand_mcp"])
	var dir := (f - s).normalized()
	var w := f - dir * hand
	var reach := float(L["upper_arm"]) + float(L["forearm"])
	return {"margin": reach - (w - s).length(), "reach": reach, "wrist": w, "f": f}


func jab_len(b: Body) -> float:
	var L := Proportions.lengths(b)
	return float(L["upper_arm"]) + float(L["forearm"]) + float(L["hand_mcp"])


func _init() -> void:
	var CHIBI := {"stature": Proportions.DEFAULT_STATURE, "scale": {"head": 1.8}}
	# N056
	var d0 := BodyCheck.style({})
	var bd := mk({})
	var fd := face_margin(bd)
	ok(d0["ok"] and (d0["breaks"] as Array).is_empty() and d0["face"]["touch"] and float(d0["face"]["margin_m"]) > 0.0,
		"A1 default body: no breaks, face margin %.1f mm" % (1000.0 * float(d0["face"].get("margin_m", 0))))
	var c1 := BodyCheck.style(CHIBI)
	var bc := mk(Proportions.clean(CHIBI))
	var fc := face_margin(bc)
	var mm := float(c1["face"]["margin_m"])
	print("     chibi: ", c1.get("msg", ""))
	ok(absf(mm - float(fc["margin"])) <= 0.005, "A2 chibi face margin %.1f mm vs independent %.1f mm (<= 5)" % [1000.0 * mm, 1000.0 * float(fc["margin"])])
	if float(fc["margin"]) < 0.0:
		ok(absf(float(c1["face"]["ik_miss_m"]) - (-float(fc["margin"]))) <= 0.005, "A2 IK miss %.1f mm vs gap %.1f mm (<= 5)" % [1000.0 * float(c1["face"]["ik_miss_m"]), -1000.0 * float(fc["margin"])])
	var bt := "\n".join(PackedStringArray(c1["breaks"]))
	ok((bt.contains("can't touch his face") or bt.contains("reduced face reach")) and mm < float(d0["face"]["margin_m"]),
		"A2 chibi breaks name the face with numbers: '%s'; margin %.1f < default %.1f mm" % [bt.replace("\n", " | "), 1000.0 * mm, 1000.0 * float(d0["face"]["margin_m"])])
	for k in [1.25, 0.8]:
		var bd2 := {"stature": Proportions.DEFAULT_STATURE, "scale": {"upper_arm": k, "forearm": k}}
		var r := BodyCheck.style(bd2)
		var ba := mk(Proportions.clean(bd2))
		var want := jab_len(ba) - jab_len(bd)
		var got := float(r["jab"]["reach_m"]) - float(d0["jab"]["reach_m"])
		ok(absf(got - want) <= 0.01 and absf(float(r["jab"]["delta_cm"]) - 100.0 * want) <= 0.5,
			"A3 arms x%.2f: jab reach change %.1f cm vs arm-length change %.1f cm (<= 1), reported %.1f" % [k, 100.0 * got, 100.0 * want, r["jab"]["delta_cm"]])
	var Lc := Proportions.lengths(bc)
	var Ld := Proportions.lengths(bd)
	var sat := float(bc.body.get("stature", Proportions.DEFAULT_STATURE)) / Proportions.DEFAULT_STATURE
	var f_head := pow(float(Lc["head"]) / (float(Ld["head"]) * sat), 3.0)
	var sh := 0.0
	var tot := 0.0
	var dl: Dictionary = Proportions.DE_LEVA["male"]
	for s in Proportions.SEGS:
		var n := 1.0 if s in ["head", "trunk"] else 2.0
		var w := float(dl[s][0]) * n * (f_head if s == "head" else Proportions.mass_factor(bc, s))
		tot += w
		if s == "head":
			sh = w
	var share := 100.0 * sh / tot
	ok(absf(float(c1["head"]["share_pct"]) - share) <= 0.3 and float(c1["head"]["share_pct"]) - float(d0["head"]["share_pct"]) > 3.0,
		"A4 head share %.2f %% vs independent %.2f %% (<= 0.3); default %.2f %%, +%.1f points (> 3)" % [c1["head"]["share_pct"], share, d0["head"]["share_pct"], float(c1["head"]["share_pct"]) - float(d0["head"]["share_pct"])])
	var extra := float(dl["head"][0]) * (f_head - 1.0)
	var com0 := Proportions.com(bc)
	var hc := Proportions.head_top(bc).lerp(Proportions.cervicale(bc), float(dl["head"][1]))
	var wtot := 0.0
	for s in Proportions.SEGS:
		var n := 1.0 if s in ["head", "trunk"] else 2.0
		wtot += float(dl[s][0]) * n * Proportions.mass_factor(bc, s)
	var cy := (com0.y * wtot + hc.y * extra) / (wtot + extra)
	ok(absf(float(c1["com"]["height_m"]) - cy) <= 0.002 and float(c1["com"]["height_m"]) > com0.y,
		"A4 COM height %.4f m vs closed form %.4f m (<= 2 mm), above the equal-density COM %.4f" % [c1["com"]["height_m"], cy, com0.y])
	# N058
	var B := mk({})
	var s0 := BodyCheck.stand(B, 75.0)
	var s2 := BodyCheck.stand(B, 600.0, 2.0)
	var rb := float(s2["bone_mpa"]) / float(s0["bone_mpa"])
	var rm := float(s2["muscle_ncm2"]) / float(s0["muscle_ncm2"])
	ok(absf(rb - 2.0) <= 0.06 and absf(rm - 2.0) <= 0.06, "B1 size x2, mass x8: bone stress x%.3f, muscle x%.3f (want 2 +-3 %%); %.1f -> %.1f MPa, %.1f -> %.1f N/cm2" % [rb, rm, s0["bone_mpa"], s2["bone_mpa"], s0["muscle_ncm2"], s2["muscle_ncm2"]])
	var s5 := BodyCheck.stand(B, 75.0, 1.0, 0.5)
	rb = float(s5["bone_mpa"]) / float(s0["bone_mpa"])
	rm = float(s5["muscle_ncm2"]) / float(s0["muscle_ncm2"])
	ok(absf(rb - 4.0) <= 0.12 and absf(rm - 4.0) <= 0.12, "B2 legs 0.5x radius: bone x%.3f, muscle x%.3f (want 4 +-3 %%)" % [rb, rm])
	var sh2 := BodyCheck.stand(B, 150.0)
	ok(absf(float(sh2["bone_mpa"]) / float(s0["bone_mpa"]) - 2.0) <= 0.06 and absf(float(sh2["muscle_ncm2"]) / float(s0["muscle_ncm2"]) - 2.0) <= 0.06, "B2 control: mass x2 doubles both")
	var lim := {"bone_mpa": LIM_BONE_MPA, "muscle_ncm2": LIM_MUSCLE}
	var f0 := BodyCheck.stand(B, 75.0, 1.0, 1.0, lim)
	var f5 := BodyCheck.stand(B, 75.0, 1.0, 0.5, lim)
	print("     default: ", f0.get("msg", ""), "\n     thin: ", f5.get("msg", ""))
	ok(not f0["flag"] and f5["flag"] and String(f5["msg"]).contains("too thin"), "B3 default passes (muscle %.0f %% of the limit, bone %.1f %%), 0.5x legs flagged (%.0f %%, %.1f %%)" % [100.0 * float(f0["muscle_ratio"]), 100.0 * float(f0["bone_ratio"]), 100.0 * float(f5["muscle_ratio"]), 100.0 * float(f5["bone_ratio"])])
	ok(absf(float(s0["muscle_ncm2"]) - float(s0["muscle_force_n"]) / float(s0["muscle_area_cm2"])) <= 0.01 * float(s0["muscle_ncm2"]) and absf(float(s0["bone_mpa"]) - float(s0["bone_force_n"]) / (float(s0["bone_area_cm2"]) * 100.0)) <= 0.01 * float(s0["bone_mpa"]),
		"B4 stress = force / area from the outputs (muscle %.0f N / %.1f cm2, bone %.0f N / %.2f cm2)" % [s0["muscle_force_n"], s0["muscle_area_cm2"], s0["bone_force_n"], s0["bone_area_cm2"]])
	# N060
	for j in ["upperarm_r", "lowerarm_r", "calf_l"]:
		var c10 := BodyCheck.muscle(j, 10.0, 1.0)
		var ok2 := true
		var txt := ""
		for g in [1.3, 2.0]:
			var cg := BodyCheck.muscle(j, 10.0, g)
			var ratio := float(cg["capacity_nm"]) / float(c10["capacity_nm"])
			ok2 = ok2 and absf(ratio - g * g) <= 0.03 * g * g
			txt += " x%.1f -> %.3f" % [g, ratio]
		ok(ok2, "C1 %s capacity %.0f N m; ratio to girth^2:%s" % [j, c10["capacity_nm"], txt])
	var thin := BodyCheck.muscle("upperarm_r", 200.0, 0.6)
	var big := BodyCheck.muscle("upperarm_r", 200.0, 1.5)
	print("     thin: ", thin.get("msg", ""), "\n     bulked: ", big.get("msg", ""))
	ok(thin["flag"] and not big["flag"] and String(thin["msg"]).contains("skinny") and float(thin["need_pcsa_cm2"]) > float(thin["have_pcsa_cm2"]) and float(big["need_pcsa_cm2"]) <= float(big["have_pcsa_cm2"]),
		"C2 200 N m: thin arm capacity %.0f N m flagged, bulked %.0f N m passes" % [thin["capacity_nm"], big["capacity_nm"]])
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/swing_fore.json")))
	var B2 := Body.new()
	B2.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B2.fk()
	var sm := ForceView.sample(S, B2)
	var cl := BodyCheck.clip(S, B2)
	var pj := String(cl["peak_joint"])
	var fv := ForceView.peak_nm(sm, pj) / ForceView.limit_nm(pj, 75.0)
	var cl2 := BodyCheck.clip(S, B2, 0.6)
	ok(absf(float(cl["peak_ratio"]) - fv) <= 0.03 * fv, "C3 swing_fore peak joint %s: ratio %.3f vs ForceView %.3f (<= 3 %%)" % [pj, cl["peak_ratio"], fv])
	var ratio_arm := float(cl2["joints"][pj]["ratio"]) / float(cl["joints"][pj]["ratio"])
	var arm := pj.begins_with("upperarm") or pj.begins_with("lowerarm")
	ok(not arm or absf(ratio_arm - 1.0 / 0.36) <= 0.03 / 0.36, "C3 arms at 0.6x girth: %s ratio x%.3f (want %.3f)" % [pj, ratio_arm, 1.0 / 0.36])
	print("     ", cl2.get("msg", ""))
	# D read-only
	var stub := GDScript.new()
	stub.source_code = "extends Node\nvar S\nvar B\nvar undo := []\nfunc _push_undo() -> void:\n\tundo.append(1)\n"
	stub.reload()
	var node: Node = stub.new()
	node.S = S
	node.B = B2
	var sd0 := JSON.stringify(S.to_dict(B2))
	var bs0 := JSON.stringify(B2.state())
	var u0: int = node.undo.size()
	var outs := []
	for rep in 2:
		var a1: Dictionary = BodyCheck.serve("proportion_breaks", node, {"body": CHIBI})
		var a2: Dictionary = BodyCheck.serve("can_stand", node, {"mass": 75.0})
		var a3: Dictionary = BodyCheck.serve("looks_strong", node, {})
		var a4: Dictionary = BodyCheck.serve("looks_strong", node, {"joint": "upperarm_r", "torque": 200.0, "girth": 0.6})
		outs.append(JSON.stringify([a1, a2, a3, a4]))
		ok(a1["ok"] and a2["ok"] and a3["ok"] and a4["ok"] and a4["result"]["flag"], "D tools answer (run %d)" % rep)
	ok(JSON.stringify(S.to_dict(B2)) == sd0 and JSON.stringify(B2.state()) == bs0 and node.undo.size() == u0 and outs[0] == outs[1],
		"D read-only: scene + body byte-identical, %d undo steps, two runs identical" % (node.undo.size() - u0))
	var at := FileAccess.get_file_as_string("res://scripts/agent_tools.gd")
	var py := FileAccess.get_file_as_string("res://tools/mcp/poser_mcp.py")
	var allr := true
	for t in ["proportion_breaks", "can_stand", "looks_strong"]:
		allr = allr and at.contains("\"%s\"" % t) and py.contains("\"%s\"" % t)
	ok(allr, "D three tools registered in agent_tools.gd and poser_mcp.py")
	print("bodycheck2_test: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit(0 if fails == 0 else 1)
