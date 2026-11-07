## teach.gd - docs/INNOVATIONS.md section 7 TEACHING AND EXPLAINING: three items that say WHY, from the clip's own numbers.
##   chain    (N097 pro comparison + N093 what drives what) a strike whose hips do not lead the fist: the frame the fist peaks, the
##            frame the hips' turn peaked, the lead in ms against the proximal-to-distal order (Putnam 1993, J Biomech 26 Suppl 1:125),
##            how far the hips turned, the fist's speed. Fix: a card in which only the hips and trunk have moved, before the strike.
##   landing  (N100 principles as physics) a jump landed on straight knees: the impact speed (g T / 2), how far the centre of mass
##            goes down after the feet land, the average force that stopping takes (constant deceleration: F = m (v^2 / 2d + g)),
##            in N and in body weights. Fix: the landing card with the knees bent to Rulebook.land_bar + 20 deg.
##   stance   (N093 what drives what) a held pose whose centre of mass is past the feet: the frame, how far past which edge, how
##            long, how far the trunk is bent. Fix: the trunk's bend changed on the card, stepwise, until the margin is +2.5 cm.
## NOTHING IS CANNED: every sentence is built from the measured numbers. NOTHING IS JUDGED TWICE: the landing uses Rulebook.jumps and
## Rulebook.land_bar, the stance Balance.read (margin, MARGIN_RES). Read only: the scene and the body are put back as they were; fixed()
## returns a clone. Norms are HEURISTIC (N020 words): LEAD_MIN is ours, the order is the literature's.
class_name Teach
extends RefCounted

const FPS := 30.0            # the frames the text names
const HZ := 60.0             # the sampling of the strike
const LEAD_MIN_MS := 40.0    # HEURISTIC: the hips peak at least this long before the fist
const HIP_TURN_MIN := 10.0   # deg: a hip turn smaller than this is no turn (a different cause)
const HIP_WIN := 30          # samples (0.5 s) before the fist's peak in which the hips' peak is looked for
const FIX_HIP_S := 0.10      # s: the move time of the hip card a fix inserts
const BODY_KG := 75.0        # the mass the force is for (stated; the body-weight multiple does not depend on it)
const STOP_MIN_M := 0.01     # m: a stopping distance under this is under what the model can tell
const LAND_WIN := 0.25       # s after touchdown (Rulebook.jumps' own window)
const RUN_MIN_S := 0.25      # s: a centre of mass past the feet shorter than this is a step, not a stance
const FIX_MARGIN := 0.025    # m: the margin a stance fix aims for
const PROX := ["pelvis", "spine_01", "spine_02", "spine_03"]
const SPINE := ["spine_01", "spine_02", "spine_03"]
const NORM := {
	"chain": {"trust": "HEURISTIC", "src": "proximal-to-distal sequencing: the hips peak before the trunk and the arm (Putnam 1993, J Biomech 26 Suppl 1:125-135); the 40 ms line is ours (Teach.LEAD_MIN_MS)"},
	"landing": {"trust": "MEASURED", "src": "drop landings: soft 117 deg, stiff 77 deg knee flexion from 59 cm (DeVita & Skelly 1992); the force is constant deceleration over the centre of mass's drop"},
	"stance": {"trust": "MEASURED", "src": "the centre of mass over the base of support (Balance.read); the 2 cm line is Balance.MARGIN_RES"},
}


# ---------------------------------------------------------------- helpers

static func _res(kind: String, findings: Array, measure: Dictionary, none_text: String) -> Dictionary:
	var texts := []
	for f in findings:
		texts.append(String(f["text"]))
	return {"ok": true, "kind": kind, "n": findings.size(), "findings": findings, "measure": measure,
		"norm": NORM[kind], "text": " ".join(texts) if not texts.is_empty() else none_text}


static func _r(v: float, d: int) -> float:
	return snappedf(v, pow(10.0, -d))


static func _frame(t: float) -> int:
	return int(round(t * FPS))


static func _ang_of(B: Body, pose: Dictionary) -> Dictionary:
	Scene.put(B, Moves._flat(pose))
	return B.ang.duplicate(true)


## the flat 30 fps frame number of a 60 Hz sample
static func _f60(i: int) -> int:
	return int(round(float(i) / 2.0))


# ---------------------------------------------------------------- chain

static func _strike(S: Scene, B: Body) -> Dictionary:
	var n := int(S.length() * HZ) + 1
	var yaw := []
	var hl := []
	var hr := []
	for i in n:
		S.apply(B, float(i) / HZ)
		var d: Vector3 = (B.P["thigh_l"] as Vector3) - (B.P["thigh_r"] as Vector3)
		yaw.append(atan2(d.x, d.z))
		hl.append(B.P["hand_l"])
		hr.append(B.P["hand_r"])
	var best_v := 0.0
	var fi := 0
	var hand := "hand_r"
	for h in [["hand_l", hl], ["hand_r", hr]]:
		var pts: Array = h[1]
		for i in range(1, n - 1):
			var v: float = ((pts[i + 1] as Vector3) - (pts[i - 1] as Vector3)).length() * (HZ / 2.0)
			if v > best_v:
				best_v = v
				fi = i
				hand = h[0]
	var wi := maxi(fi - HIP_WIN, 1)
	var best_w := 0.0
	var lo := INF
	var hi := -INF
	var un := 0.0
	var prev: float = yaw[maxi(fi - HIP_WIN, 0)]
	for i in range(maxi(fi - HIP_WIN, 1), mini(fi + HIP_WIN, n - 1)):
		un += angle_difference(prev, yaw[i])
		prev = yaw[i]
		lo = minf(lo, un)
		hi = maxf(hi, un)
	for i in range(maxi(fi - HIP_WIN, 1), fi + 1):
		var w := absf(angle_difference(yaw[i - 1], yaw[i + 1])) * (HZ / 2.0)
		if w > best_w:
			best_w = w
			wi = i
	return {"fi": fi, "wi": wi, "v": best_v, "hand": hand, "turn": rad_to_deg(hi - lo) if hi >= lo else 0.0}


static func chain(S: Scene, B: Body) -> Dictionary:
	if not S.flights().is_empty() or S.cards.size() < 2:
		return _res("chain", [], {}, "No strike to explain.")
	var keep := B.state()
	var st := _strike(S, B)
	B.set_state(keep)
	if float(st["v"]) < Rulebook.STRIKE_MIN:
		return _res("chain", [], {"fist_ms": _r(float(st["v"]), 1)}, "No strike to explain: the fastest hand reaches only %.1f m/s." % float(st["v"]))
	var lead := (float(st["fi"]) - float(st["wi"])) / HZ * 1000.0
	var nums := {"fist_peak_frame": _f60(int(st["fi"])), "hip_peak_frame": _f60(int(st["wi"])), "lead_ms": _r(lead, 0),
		"hip_turn_deg": _r(float(st["turn"]), 0), "fist_ms": _r(float(st["v"]), 1)}
	var findings := []
	var hand_w := "right hand" if st["hand"] == "hand_r" else "left hand"
	var turn := float(nums["hip_turn_deg"])
	if turn < HIP_TURN_MIN:
		findings.append({"cause": "no_hip_turn", "frame": nums["fist_peak_frame"], "t": float(st["fi"]) / HZ, "numbers": nums,
			"text": "At frame %d: the %s peaks at %.1f m/s, but the hips turn only %.0f deg around it. The arm is punching on its own, with no body behind it; turn the hips at least %.0f deg." % [
				nums["fist_peak_frame"], hand_w, nums["fist_ms"], turn, HIP_TURN_MIN],
			"fix": {"kind": "none", "say": "turn the hips"}})
	elif lead < LEAD_MIN_MS:
		var k := Rulebook.card_at(S, float(st["fi"]) / HZ)
		var fix := {"kind": "hip_card", "card": k, "move_s": FIX_HIP_S}
		fix["say"] = "add a card before '%s' where only the hips and trunk have turned, %.2f s ahead of it" % [S.cards[k].get("name", ""), FIX_HIP_S]
		findings.append({"cause": "no_hip_lead", "frame": nums["fist_peak_frame"], "t": float(st["fi"]) / HZ, "numbers": nums, "fix": fix,
			"text": "At frame %d: the %s peaks at %.1f m/s, but the hips' turn of %.0f deg peaked at frame %d, a lead of %.0f ms (trained strikers start the hips first, by at least %.0f ms). The hips and the arm move together, so the arm throws the punch alone; the power chain starts at the hips and ends at the fist. Try: %s." % [
				nums["fist_peak_frame"], hand_w, nums["fist_ms"], turn, nums["hip_peak_frame"], lead, LEAD_MIN_MS, fix["say"]]})
	return _res("chain", findings, {"lead_ms": nums["lead_ms"], "hip_turn_deg": nums["hip_turn_deg"], "fist_ms": nums["fist_ms"]},
		"The hips lead the fist by %.0f ms: nothing to explain." % lead)


# ---------------------------------------------------------------- landing

static func landing(S: Scene, B: Body) -> Dictionary:
	var fl := S.flights()
	if fl.is_empty():
		return _res("landing", [], {}, "No jump to explain.")
	var keep := B.state()
	var js: Array = Rulebook.jumps(S, B)
	var end: float = S.times()[-1][2]
	S.apply(B, 0.0)
	var c_ref := Balance.com(B).y
	var findings := []
	var measure := {}
	for q in js.size():
		var j: Dictionary = js[q]
		var t1: float = j["t1"]
		var cmin := INF
		var t := t1
		while t <= minf(end, t1 + LAND_WIN) + 1e-9:
			S.apply(B, t)
			cmin = minf(cmin, Balance.com(B).y)
			t += 1.0 / HZ
		var d := maxf(c_ref - cmin, STOP_MIN_M)
		var v := Scene.G * float(j["T"]) / 2.0
		var bw := v * v / (2.0 * d * Scene.G) + 1.0
		var bar := Rulebook.land_bar(float(j["h"]))
		var nums := {"touchdown_frame": _frame(t1), "knee_deg": _r(float(j["land"]), 1), "bar_deg": _r(bar, 0), "fall_cm": _r(float(j["h"]) * 100.0, 0),
			"impact_ms": _r(v, 2), "stop_cm": _r(d * 100.0, 1), "force_n": _r(bw * BODY_KG * Scene.G, 0), "force_bw": _r(bw, 1)}
		if q == 0:
			measure = nums.duplicate()
		if float(j["land"]) < bar:
			var calf := clampf(bar + 20.0, 60.0, 110.0)
			var fix := {"kind": "knees", "card": int(fl[q]["l"]), "calf": calf, "thigh": calf * 0.55}
			fix["say"] = "bend the knees to about %.0f deg on card '%s'" % [calf, S.cards[int(fl[q]["l"])].get("name", "")]
			findings.append({"cause": "stiff_landing", "frame": nums["touchdown_frame"], "t": t1, "numbers": nums, "fix": fix,
				"text": "At frame %d: you land from %.0f cm at %.2f m/s with the knees bent only %.1f deg (a fall this high needs about %.0f deg). The body goes down just %.1f cm after the feet touch, so stopping %.2f m/s in that distance takes an average of %.0f N, %.1f BW (times body weight), through the knees and spine. Bending the knees spreads the same stop over more distance and the force falls with it. Try: %s." % [
					nums["touchdown_frame"], nums["fall_cm"], v, nums["knee_deg"], nums["bar_deg"], nums["stop_cm"], v, nums["force_n"], nums["force_bw"], fix["say"]]})
	B.set_state(keep)
	return _res("landing", findings, measure, "The landing bends the knees enough for its fall: nothing to explain.")


# ---------------------------------------------------------------- stance

static func _nearest_edge(poly: PackedVector2Array, q: Vector2) -> Vector2:
	var best := INF
	var out := q
	for i in poly.size():
		var c := Geometry2D.get_closest_point_to_segment(q, poly[i], poly[(i + 1) % poly.size()])
		if q.distance_to(c) < best:
			best = q.distance_to(c)
			out = c
	return out


static func _edge_word(rd: Dictionary) -> String:
	var c: Vector3 = rd["com"]
	var q := _nearest_edge(rd["poly"], Vector2(c.x, c.z))
	var d := Vector2(c.x, c.z) - q
	if absf(d.y) >= absf(d.x):
		return "front" if d.y > 0.0 else "back"
	return "left" if d.x > 0.0 else "right"


static func _lean(B: Body) -> float:
	var s := 0.0
	for j in SPINE:
		s += float((B.ang[j] as Vector3).x)
	return s


static func stance(S: Scene, B: Body) -> Dictionary:
	var keep := B.state()
	var n := int(floor(S.length() * FPS + 1e-6)) + 1
	var marg := []
	var worst_all := INF
	for i in n:
		S.apply(B, float(i) / FPS)
		var rd := Balance.read(B)
		marg.append(INF if (rd["down"] as Array).is_empty() else float(rd["margin"]))
		worst_all = minf(worst_all, marg[i])
	var measure := {"margin_cm": _r(worst_all * 100.0, 2)}
	if S.has_meta("teach_frame"):
		var mf := clampi(int(S.get_meta("teach_frame")), 0, n - 1)
		measure = {"margin_cm": _r(float(marg[mf]) * 100.0, 2), "frame": mf}
	var findings := []
	var i := 0
	while i < n:
		if float(marg[i]) >= -Balance.MARGIN_RES:
			i += 1
			continue
		var a := i
		var wi := i
		while i < n and float(marg[i]) < -Balance.MARGIN_RES:
			if float(marg[i]) < float(marg[wi]):
				wi = i
			i += 1
		var run_s := float(i - a) / FPS
		if run_s < RUN_MIN_S:
			continue
		S.apply(B, float(wi) / FPS)
		var rd := Balance.read(B)
		var edge := _edge_word(rd)
		var lean := _lean(B)
		var cm := float(marg[wi]) * 100.0
		var k := Rulebook.card_at(S, float(wi) / FPS)
		var nums := {"frame": wi, "margin_cm": _r(cm, 1), "edge": edge, "lean_deg": _r(lean, 0), "run_s": _r(run_s, 1)}
		var fx := _stance_fix(S, B, k, float(wi) / FPS)
		var fix := {"kind": "lean", "card": k, "delta_deg": fx["delta"], "axis": fx["axis"], "found": fx["found"]}
		fix["say"] = ("change the trunk's %s by %.0f deg on card '%s'" % ["side bend" if int(fx["axis"]) == 1 else "forward bend", fx["delta"], S.cards[k].get("name", "")]) if fx["found"] else "move the feet under the weight"
		findings.append({"cause": "com_outside_feet", "frame": wi, "t": float(wi) / FPS, "numbers": nums, "fix": fix,
			"text": "At frame %d: the centre of mass is %.1f cm past the %s edge of the feet, held for %.1f s. The trunk is bent %.0f deg, which puts the weight of the upper body beyond the base the feet make, so the body would topple that way unless a step or a hand catches it. Try: %s." % [
				wi, absf(cm), edge, run_s, lean, fix["say"]]})
	B.set_state(keep)
	return _res("stance", findings, measure, "The centre of mass stays over the feet: nothing to explain.")


## the change of the trunk's bend or side bend (the same delta on the three spine joints) on card k that puts the margin at t at
## FIX_MARGIN or more: the axis and direction that raise the margin most on a first 2 deg, then 2 deg steps up to 60 deg
static func _stance_fix(S: Scene, B: Body, k: int, t: float) -> Dictionary:
	var C := S.clone()
	var base_pose: Dictionary = (S.cards[k]["pose"] as Dictionary).duplicate(true)
	var B2 := Body.new()
	B2.load_files(PoseBake.SKEL, PoseBake.LIMS)
	var ang0 := _ang_of(B2, base_pose)
	var sgn := 1.0
	var axis := 0
	var best_m := -INF
	for ax in [0, 1]:
		for sg in [-1.0, 1.0]:
			C.cards[k]["pose"] = _lean_pose(B2, ang0, base_pose, sg * 6.0, ax)
			C.apply(B, t)
			var mg := float(Balance.read(B)["margin"])
			if mg > best_m + 1e-6:
				best_m = mg
				sgn = sg
				axis = ax
	var d := 2.0
	while d <= 60.0:
		C.cards[k]["pose"] = _lean_pose(B2, ang0, base_pose, sgn * d, axis)
		C.apply(B, t)
		if float(Balance.read(B)["margin"]) >= FIX_MARGIN:
			return {"found": true, "delta": sgn * d, "axis": axis}
		d += 2.0
	return {"found": false, "delta": 0.0, "axis": axis}


static func _lean_pose(B2: Body, ang0: Dictionary, base_pose: Dictionary, delta: float, axis := 0) -> Dictionary:
	Scene.put(B2, Moves._flat(base_pose))
	for j in SPINE:
		var a: Vector3 = ang0[j]
		B2.set_ang(j, Vector3(a.x + (delta if axis == 0 else 0.0), a.y + (delta if axis == 1 else 0.0), a.z))
	B2.fk()
	return B2.to_dict()


# ---------------------------------------------------------------- fixed

## a CLONE of S with the finding's fix applied (S itself is not changed)
static func fixed(S: Scene, _B: Body, f: Dictionary) -> Scene:
	var C := S.clone()
	var fix: Dictionary = f.get("fix", {})
	var B2 := Body.new()
	B2.load_files(PoseBake.SKEL, PoseBake.LIMS)
	var k := int(fix.get("card", -1))
	match String(fix.get("kind", "")):
		"hip_card":
			if k >= 1 and k < C.cards.size():
				var cur := _ang_of(B2, C.cards[k]["pose"])
				Scene.put(B2, Moves._flat(C.cards[k - 1]["pose"]))
				for j in PROX:
					B2.set_ang(j, cur[j])
				B2.fk()
				var card := {"name": "hips", "pose": B2.to_dict(), "move": float(fix["move_s"]), "hold": 0.0}
				C.cards.insert(k, card)
		"knees":
			if k >= 0 and k < C.cards.size():
				Scene.put(B2, Moves._flat(C.cards[k]["pose"]))
				for sd in ["_l", "_r"]:
					B2.set_ang("thigh" + sd, Vector3(float(fix["thigh"]), 0, 0))
					B2.set_ang("calf" + sd, Vector3(float(fix["calf"]), 0, 0))
				B2.fk()
				C.cards[k]["pose"] = B2.to_dict()
		"lean":
			if k >= 0 and k < C.cards.size() and bool(fix.get("found", false)):
				var ang0 := _ang_of(B2, C.cards[k]["pose"])
				C.cards[k]["pose"] = _lean_pose(B2, ang0, C.cards[k]["pose"], float(fix["delta_deg"]), int(fix.get("axis", 0)))
				C.set_meta("teach_frame", int(f.get("frame", -1)))
	return C


# ---------------------------------------------------------------- serve

static func serve(m: Node, kind: String, p: Dictionary) -> Dictionary:
	if p.has("apply") and not (p["apply"] is bool):
		return {"ok": false, "error": "teach_%s {apply: true} applies the first fix as one undo step; apply must be true or false" % kind}
	var B: Body = m.ov.GB   # Check's own grading body: the live body is not touched
	var r: Dictionary = Callable(Teach, kind).call(m.S, B)
	r["applied"] = false
	if p.get("apply", false) == true and int(r["n"]) > 0:
		var fs: Scene = fixed(m.S, B, r["findings"][0])
		if var_to_str(fs.cards) != var_to_str(m.S.cards):
			m._push_undo()
			m.S.cards = (fs.cards as Array).duplicate(true)
			r["applied"] = true
	return r
