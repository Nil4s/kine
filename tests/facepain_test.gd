## godot --headless --path . -s tests/facepain_test.gd     (ROADMAP I13 effort face from torque, I14 pain face from hit force; scripts/face_pain.gd)
## BARS WRITTEN BEFORE THE IMPLEMENTATION AND BEFORE ANY MEASURING (a bar that turns out unfit is a flag in the report, not an edit):
##  EFFORT (I13). Torque = ForceView.sample ratio (joint torque / the joint's limit), the worst joint per frame, at 30 fps.
##   E1 PEAK:   on a planted floor lift (stand -> stoop, 0.35 s move) the effort AU4 peak frame is within 4 frames of the torque peak frame.
##   E2 LEAD:   the AU peak comes BEFORE the torque peak by 2 to 4 frames (the onset lead, FacePain.LEAD = 3 frames at 30 fps).
##   E3 IDLE:   two stand cards held: every AU of every frame is exactly 0 and no face key is written.
##   E4 LIFT:   the lift's AU4 peak >= 0.20 (the clip does show effort), AU7 / AU24 / AU38 / clench peaks > 0 and all peak on AU4's frame.
##   E5 RIG:    every keyed channel is inside Face.range_of; at the peak frame Face.at gives brows lowered (brow_l < 0), squint > 0, press > 0.
##   E6 CONTROL: a flat 0.1 torque gives no effort; the torque series shifted by 10 frames moves the AU peak by 10 frames (it follows torque).
##  PAIN (I14). Pain AUs after Prkachin and Solomon 2008 (PSPI = AU4 + max(AU6, AU7) + max(AU9, AU10) + AU43; here AUs are 0..1, the 3 brow/orbit/nose terms x5).
##   P1 ONSET:  first frame with AU4 > 0.02 is 100 to 150 ms after contact, for contact on a frame (1.0 s) and off a frame (1.013 s).
##   P2 MONOTONE: peak PSPI and peak AU4 strictly increase over impulse 5, 20, 60, 150, 400 N s.
##   P3 HARD:   impulse 200 N s: peak PSPI >= 8 (of 16). NONE: impulse 0: PSPI 0 on every frame.
##   P4 RANGE:  every AU in 0..1 and every keyed channel in Face.range_of, impulses -50, 0, 1, 1e3, 1e9.
##   P5 CONTROL: a zero-impulse hit writes no key at all (face dict empty); a negative impulse too.
##   P6 DECAY:  PSPI at contact + 1.5 s <= 25 % of the peak; the peak frame is 110 to 300 ms after contact.
##   P7 LINK:   FacePain.pain_from_react(RegionReact.react("liver", 100)) peak PSPI == the pain curve of impulse 100.
##   P8 RIG:    at the peak frame Face.at gives brow_l < 0, squint >= 0.5, blink >= 0.3.
##  TOOLS: FacePain.serve("pain_face"), ("effort_face") answer; both names are in AgentTools.MCP_EXTRA and in tools/mcp/poser_mcp.py.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func pose(hinge: float, hip: float, knee: float, spine: float, hands: Vector3) -> Dictionary:
	var B := body()
	B.set_ang("pelvis", Vector3(hinge, 0, 0))
	for sd in ["_l", "_r"]:
		B.set_ang("thigh" + sd, Vector3(hip, 0, 0))
		B.set_ang("calf" + sd, Vector3(knee, 0, 0))
	for n in ["spine_01", "spine_02", "spine_03"]:
		B.set_ang(n, Vector3(spine / 3.0, 0, 0))
	B.fk()
	B.ground()
	B.reach("hand_l", hands + Vector3(0.15, 0, 0))
	B.reach("hand_r", hands - Vector3(0.15, 0, 0))
	B.fk()
	return B.to_dict()


func lift_scene() -> Scene:
	var S := Scene.new()
	S.name = "zz_lift"
	S.add("stand", body().to_dict())
	S.add("lift", pose(75, 75, 6, 0, Vector3(0.0, 0.15, 0.35)))
	S.cards[0]["hold"] = 0.3
	S.cards[1]["move"] = 0.35
	S.cards[1]["hold"] = 0.4
	return S


func idle_scene() -> Scene:
	var S := Scene.new()
	S.name = "zz_idle"
	S.add("stand", body().to_dict())
	S.add("stand2", body().to_dict())
	S.cards[0]["hold"] = 1.0
	S.cards[1]["move"] = 0.5
	S.cards[1]["hold"] = 1.0
	return S


func peak_of(a: Array) -> int:
	var bi := 0
	for i in a.size():
		if float(a[i]) > float(a[bi]):
			bi = i
	return bi


func au_series(cv: Dictionary, k: String) -> Array:
	return (cv["au"] as Array).map(func(d): return float(d[k]))


func _init() -> void:
	# ---------------- EFFORT
	var B := body()
	var L := FacePain.effort_scene(lift_scene(), B, 30)
	ok(bool(L.get("ok", false)), "effort_scene on the lift answers: %s" % L.get("msg", ""))
	var a4 := au_series(L, "AU4")
	var tp: int = int(L["torque_peak_frame"])
	var ap := peak_of(a4)
	print("LIFT: %d frames, torque peak %.3f at frame %d, AU4 peak %.3f at frame %d, lead %d" % [a4.size(), float(L["torque_peak"]), tp, float(a4[ap]), ap, FacePain.LEAD])
	ok(absi(ap - tp) <= 4, "E1 AU4 peak within 4 frames of the torque peak (%d vs %d)" % [ap, tp])
	ok(tp - ap >= 2 and tp - ap <= 4 and FacePain.LEAD >= 2 and FacePain.LEAD <= 4, "E2 the AU leads the torque by 2-4 frames (%d)" % (tp - ap))
	ok(float(a4[ap]) >= 0.20, "E4 lift AU4 peak %.3f >= 0.20" % float(a4[ap]))
	var same := true
	for k in ["AU7", "AU24", "AU38", "clench"]:
		var s := au_series(L, k)
		if not (float(s[ap]) > 0.0 and peak_of(s) == ap):
			same = false
	ok(same, "E4 AU7, AU24, AU38 and clench peak > 0 on the same frame as AU4")
	var face := {}
	FacePain.effort_keys(L, face)
	var inr := true
	for ch in face:
		for kk in face[ch]:
			var r := Face.range_of(ch)
			var v: float = (kk["v"] as Vector3).x
			if v < r.x or v > r.y:
				inr = false
	ok(inr and not face.is_empty(), "E5 every keyed channel is inside Face.range_of (%d channels)" % face.size())
	var pz := Face.at(face, {}, float(ap) / 30.0)
	print("   rig at the peak: brow_l %.2f squint %.2f press %.2f" % [pz["brow_l"], pz["squint"], pz["press"]])
	ok(pz["brow_l"] < 0.0 and pz["squint"] > 0.0 and pz["press"] > 0.0, "E5 at the peak the brows are lowered, lids tight, lips pressed")
	# idle
	var I := FacePain.effort_scene(idle_scene(), body(), 30)
	var idle_max := 0.0
	for d in I["au"]:
		for k in d:
			idle_max = maxf(idle_max, absf(float(d[k])))
	var fi := {}
	FacePain.effort_keys(I, fi)
	print("IDLE: worst torque ratio %.3f (rest threshold %.2f), max AU %.4f" % [float(I["torque_peak"]), FacePain.REST_RATIO, idle_max])
	ok(idle_max == 0.0 and fi.is_empty(), "E3 idle clip: every AU is 0 and no key is written")
	# controls
	var flat := FacePain.effort_from_torque(PackedFloat32Array([0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1]), 30)
	ok(float(au_series(flat, "AU4").max()) == 0.0, "E6 control: a flat 0.1 torque gives no effort")
	var ser: Array = [0.0, 0.1, 0.3, 0.6, 0.9, 1.1, 0.8, 0.4, 0.1, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var pad: Array = []
	pad.resize(10)
	pad.fill(0.0)
	var c1 := FacePain.effort_from_torque(PackedFloat32Array(ser), 30)
	var c2 := FacePain.effort_from_torque(PackedFloat32Array(pad + ser), 30)
	var d1 := peak_of(au_series(c1, "AU4"))
	var d2 := peak_of(au_series(c2, "AU4"))
	ok(d2 - d1 == 10, "E6 control: the torque shifted by 10 frames moves the AU peak by 10 (%d)" % (d2 - d1))
	ok(int(c1["torque_peak_frame"]) == 5 and d1 == 5 - FacePain.LEAD, "E6 control: torque peak at frame 5, AU peak at %d" % d1)

	# ---------------- PAIN
	for c in [1.0, 1.013]:
		var P := FacePain.pain_curve(200.0, c, 4.0, 30)
		var first := -1.0
		for f in P["frames"]:
			if float(f["au"]["AU4"]) > 0.02:
				first = float(f["t"]) - c
				break
		print("ONSET: contact %.3f s, first AU4 frame %.0f ms after contact" % [c, first * 1000.0])
		ok(first >= 0.100 and first <= 0.150, "P1 onset 100-150 ms after contact (%.0f ms)" % (first * 1000.0))
	var prev_p := -1.0
	var prev_a := -1.0
	var mono := true
	var line := "MONO: "
	for J in [5.0, 20.0, 60.0, 150.0, 400.0]:
		var Q := FacePain.pain_curve(J, 1.0, 4.0, 30)
		var pk := float(Q["peak_pspi"])
		var pa := float(Q["peak_au"]["AU4"])
		line += "J%.0f pspi %.2f au4 %.3f | " % [J, pk, pa]
		if not (pk > prev_p and pa > prev_a):
			mono = false
		prev_p = pk
		prev_a = pa
	print(line)
	ok(mono, "P2 peak PSPI and AU4 strictly increase with the impulse")
	var H := FacePain.pain_curve(200.0, 1.0, 4.0, 30)
	var N := FacePain.pain_curve(0.0, 1.0, 4.0, 30)
	var nmax := 0.0
	for f in N["frames"]:
		nmax = maxf(nmax, float(f["pspi"]))
	print("HARD: peak PSPI %.2f of 16 | NONE: max PSPI %.3f" % [float(H["peak_pspi"]), nmax])
	ok(float(H["peak_pspi"]) >= 8.0, "P3 hard hit PSPI >= 8")
	ok(nmax == 0.0, "P3 no hit: PSPI 0 on every frame")
	var rng_ok := true
	for J in [-50.0, 0.0, 1.0, 1e3, 1e9]:
		var Q := FacePain.pain_curve(J, 1.0, 4.0, 30)
		var fc := {}
		FacePain.pain_keys(Q, fc)
		for f in Q["frames"]:
			for k in f["au"]:
				if float(f["au"][k]) < 0.0 or float(f["au"][k]) > 1.0:
					rng_ok = false
		for ch in fc:
			var r := Face.range_of(ch)
			for kk in fc[ch]:
				var v: float = (kk["v"] as Vector3).x
				if v < r.x or v > r.y:
					rng_ok = false
	ok(rng_ok, "P4 every AU in 0..1 and every channel inside the rig range")
	var z := {}
	FacePain.pain_keys(N, z)
	var ng := {}
	FacePain.pain_keys(FacePain.pain_curve(-50.0, 1.0, 4.0, 30), ng)
	ok(z.is_empty() and ng.is_empty(), "P5 control: zero and negative impulse write no key")
	var pkf := 0
	var best := -1.0
	for i in H["frames"].size():
		if float(H["frames"][i]["pspi"]) > best:
			best = float(H["frames"][i]["pspi"])
			pkf = i
	var tpk: float = float(H["frames"][pkf]["t"]) - 1.0
	var late: float = float(H["frames"][int(round(2.5 * 30.0))]["pspi"])
	print("DECAY: peak %.2f at +%.0f ms, at +1.5 s %.2f (%.0f %%)" % [best, tpk * 1000.0, late, 100.0 * late / best])
	ok(tpk >= 0.110 and tpk <= 0.300, "P6 peak %.0f ms after contact" % (tpk * 1000.0))
	ok(late <= 0.25 * best, "P6 PSPI at +1.5 s <= 25 % of the peak")
	var R := RegionReact.react("liver", 100.0, "r")
	var Pl := FacePain.pain_from_react(R, 1.0, 4.0, 30)
	var P100 := FacePain.pain_curve(100.0, 1.0, 4.0, 30)
	ok(absf(float(Pl["peak_pspi"]) - float(P100["peak_pspi"])) < 1e-6 and float(Pl["peak_pspi"]) > 0.0, "P7 pain from RegionReact liver 100 == pain of impulse 100 (%.2f)" % float(Pl["peak_pspi"]))
	var hf := {}
	FacePain.pain_keys(H, hf)
	var pt := 1.0 + tpk
	var pp := Face.at(hf, {}, pt)
	print("   rig at the pain peak: brow_l %.2f squint %.2f blink %.2f" % [pp["brow_l"], pp["squint"], pp["blink"]])
	ok(pp["brow_l"] < 0.0 and pp["squint"] >= 0.5 and pp["blink"] >= 0.3, "P8 pain peak: brows down, lids tight, eyes shutting")

	# ---------------- TOOLS
	var sv := FacePain.serve("pain_face", null, {"impulse": 200.0, "contact": 1.0})
	ok(bool(sv["ok"]) and absf(float(sv["result"]["peak_pspi"]) - float(H["peak_pspi"])) < 1e-6, "TOOL pain_face answers with the module's PSPI")
	var sv0 := FacePain.serve("pain_face", null, {"impulse": 0.0})
	ok(bool(sv0["ok"]) and float(sv0["result"]["peak_pspi"]) == 0.0, "TOOL pain_face: zero impulse = PSPI 0")
	ok(not bool(FacePain.serve("pain_face", null, {})["ok"]), "TOOL pain_face with no impulse is an error that says so")
	var se := FacePain.serve("effort_face", null, {"clip": "scenes/combo3.json"})
	ok(bool(se["ok"]) and se["result"].has("peak_au4") and float(se["result"]["peak_au4"]) >= 0.0 and float(se["result"]["peak_au4"]) <= 1.0, "TOOL effort_face on scenes/combo3.json answers (%s)" % str(se.get("result", {}).get("peak_au4", se.get("error", ""))))
	var src := FileAccess.get_file_as_string("res://scripts/agent_tools.gd")
	var mcp := FileAccess.get_file_as_string("res://tools/mcp/poser_mcp.py")
	ok(src.contains("\"effort_face\"") and src.contains("\"pain_face\"") and mcp.contains("\"effort_face\"") and mcp.contains("\"pain_face\""), "TOOL both names are in agent_tools.gd and poser_mcp.py")
	print("facepain: %d fail" % fails)
	quit(1 if fails > 0 else 0)
