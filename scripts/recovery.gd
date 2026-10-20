## recovery.gd - I39 RECOVERY STEP. After a hit reaction or a shove the struck body either keeps its balance where it stands, or has to step,
## or falls. The judge is the EXTRAPOLATED CENTRE OF MASS / CAPTURE POINT of the inverted pendulum:
##   xi = x_com + v / omega0,   omega0 = sqrt(g / l)        (Hof, Gazendam & Sinke 2005, J Biomech 38:1; Pratt et al. 2006 "capture point")
## x_com is the COM's floor point (Balance.com, de Leva masses), v the COM's horizontal speed the push gives it (m/s), g = 9.81 m/s^2 and l the
## pendulum length = the COM's height over the ankles. The body stays where it is while xi is inside the BASE OF SUPPORT (Balance.read's
## hull of the feet on the floor). If xi leaves it the body must put a foot where xi is (Hof 2008, Hum Mov Sci 27:112: a step to the XcoM
## restores the margin of stability), so:
##  STEP: the swing foot (the one with the shorter step) lands with its centre (mid ankle - toe base) at xi + MARGIN along the push, MARGIN = 2 cm
##        = Balance.MARGIN_RES (the model's own resolution of the support edge: the capture point then lies inside the new base by that much).
##        The step takes STEP_T = 0.25 s: the stepping reaction starts ~0.15-0.2 s after the perturbation and the swing lasts ~0.2-0.3 s
##        (Maki & McIlroy 1997, Phys Ther 77:488, change-in-support strategy; quoted from memory, not re-read). Three cards: the struck
##        pose, the swing at half way with the foot CLEAR = 10 cm up, the landing (hips carried toward the step as far as the planted
##        sole of the other foot lets them). The legs are solved with DragBalance's planted-sole IK.
##  FALL: the step is longer than MAX_STEP = 0.8 x leg length (the hip joint's standing height; a recovery step is a maximal step, at most
##        about a leg length in healthy adults: Medell & Alexander 2000, Wojcik et al. 2001; HEURISTIC, quoted from memory) or the legs cannot
##        reach it with the other sole planted: the body is flagged "falls" and the Breakfall check (I25) judges the landing.
## LIMIT: xi is taken at the end of the push and the landing aims at THAT point. During the 0.25 s of the step the real xi runs on
## (xi - p) grows like exp(omega0 t), so a real step must be longer; the plan reports it as "xi at touchdown".
class_name Recovery
extends RefCounted

const G := 9.81
# GROUND TRUTH (gt3): young adults (n=11, leg length 91 +- 4 cm) stepping after a platform translation: first-step latency (onset to foot-off) 0.25 +- 0.04 s backward, 0.36-0.42 s forward; first step length 0.31 +- 0.06 m backward, 0.27-0.33 m forward (Mansfield et al. 2015, Front Aging Neurosci 7:201, Table 3; at the individual step threshold, not maximal). Swing DURATION was not reported there, so STEP_T = 0.25 s stays UNVERIFIED as a swing time.
const STEP_T := 0.25
const MARGIN := 0.02            # m: = Balance.MARGIN_RES
# UNVERIFIED: no opened source gave a maximal recovery step length (Kluft 2017 and Bieryla 2015 measure it but the numbers were not in the open text).
const MAX_STEP_LEG := 0.8       # of the leg length (hip height)
const CLEAR := 0.10             # m: the swing foot's height at half way
const SHOVES := {"small": 0.3, "medium": 1.0, "huge": 3.0}   # m/s the COM gains: a light nudge, a firm shove, a tackle
const DIRS := {"forward": 0.0, "left": 90.0, "back": 180.0, "right": -90.0}   # degrees from the body's facing (forward = pushed from behind)
const SOLE_OK := 0.004          # m: a planted sole may move this much (DragBalance.SOLE_TOL is 2 mm; a long step is allowed a little more)


static func heading(B: Body) -> float:
	var f: Vector3 = (B.G["pelvis"] as Quaternion) * Vector3(0, 0, 1)
	return atan2(f.x, f.z)


static func centre(B: Body, sd: String) -> Vector2:
	var a: Vector3 = B.P["foot" + sd]
	var b: Vector3 = B.P["ball" + sd]
	return Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)


## the read of a posed body for a push: {"ok", "why", "com", "poly", "w0", "l", "v" (Vector2), "xi" (Vector2), "margin" (+ inside), "verdict": "hold" / "step" / "fall",
## "swing" ("_l"/"_r"), "target" (Vector2), "step" (m), "max" (m)}
static func read(B: Body, dir_deg: float, speed: float) -> Dictionary:
	var r := Balance.read(B)
	var down: Array = r["down"]
	if down.size() < 2:
		return {"ok": false, "why": "both feet must be on the floor to judge a push: pick a pose card with the fighter standing"}
	var c: Vector3 = r["com"]
	var ay := 0.0
	for sd in down:
		ay += (B.P["foot" + String(sd)] as Vector3).y
	ay /= down.size()
	var l := maxf(c.y - ay, 0.3)
	var w0 := sqrt(G / l)
	var h := heading(B) + deg_to_rad(dir_deg)
	var d := Vector2(sin(h), cos(h))
	var v := d * speed
	var xi := Vector2(c.x, c.z) + v / w0
	var poly: PackedVector2Array = r["poly"]
	var mg := Balance.signed_dist(poly, xi)
	var out := {"ok": true, "why": "", "com": c, "poly": poly, "w0": w0, "l": l, "v": v, "d": d, "speed": speed, "xi": xi, "margin": mg, "verdict": "hold",
		"swing": "", "target": xi, "step": 0.0, "max": MAX_STEP_LEG * float((B.p0["thigh_l"] as Vector3).y), "com0": Vector2(c.x, c.z)}
	if mg >= 0.0:
		return out
	var tg := xi + d * MARGIN
	var best := ""
	var bd := INF
	for sd in ["_l", "_r"]:
		var e := centre(B, sd).distance_to(tg)
		if e < bd:
			bd = e
			best = sd
	out["swing"] = best
	out["target"] = tg
	out["step"] = bd
	out["verdict"] = "fall" if bd > float(out["max"]) else "step"
	return out


static func _ref_shift(st: Dictionary, foot: String, delta: Vector3, pole_by: Vector3) -> void:
	var rf: Dictionary = st["refs"][foot]
	rf["P"] = (rf["P"] as Vector3) + delta
	rf["Pb"] = (rf["Pb"] as Vector3) + delta
	rf["Eb"] = (rf["Eb"] as Vector3) + delta
	rf["pole"] = (rf["pole"] as Vector3) + pole_by


## the pose of one stage of the step: the swing foot shifted by `delta`, the hips by `hip` (x, z) -> {"ok", "sole", "dict"}
static func _stage(B: Body, st0: Dictionary, swing: String, delta: Vector3, hip: Vector2) -> Dictionary:
	var st := st0.duplicate(true)
	_ref_shift(st, "foot" + swing, delta, delta * 0.5 + Vector3(hip.x, 0, hip.y) * 0.5)
	var rise := minf(0.0, DragBalance._rise_cap(st, hip.x, hip.y))
	var r := DragBalance.pose(B, st, [hip.x, hip.y, rise, 0.0, 0.0, 0.0, 0.0])
	return {"ok": float(r["sole"]) <= SOLE_OK, "sole": float(r["sole"]), "dict": B.to_dict()}


## the plan on the card k (its arrival pose is the struck pose): {"ok", "why", "fall", "rd" (the read), "scene", "cards" (the new cards' indices), "t0", "t1", landing numbers...}
static func plan(S: Scene, k: int, dir_deg: float, speed: float) -> Dictionary:
	var sc := S.clone()
	sc.baker = null
	if k < 0 or k >= sc.cards.size():
		return {"ok": false, "why": "the scene has no pose card: add one with the fighter standing, then try again"}
	var B := DistanceKeeper.new_body()
	var ta: float = float(sc.times()[k][1])
	sc.apply(B, ta)
	var rd := read(B, dir_deg, speed)
	if not bool(rd["ok"]):
		return {"ok": false, "why": String(rd["why"]), "rd": rd, "fall": false}
	if String(rd["verdict"]) == "hold":
		return {"ok": false, "why": "the capture point stays inside the feet (by %.1f cm): no step is needed, the fighter keeps his stance. Try a stronger shove to see a step" % (float(rd["margin"]) * 100.0), "rd": rd, "fall": false}
	if String(rd["verdict"]) == "fall":
		return {"ok": false, "fall": true, "rd": rd, "why": "falls: the step to the capture point is %.0f cm, longer than a person can step (%.0f cm). Run the Breakfall check to judge the landing" % [float(rd["step"]) * 100.0, float(rd["max"]) * 100.0]}
	var sw := String(rd["swing"])
	var tg: Vector2 = rd["target"]
	var c0 := centre(B, sw)
	var delta := Vector3(tg.x - c0.x, 0.0, tg.y - c0.y)
	var st0 := DragBalance.begin(B)
	var d: Vector2 = rd["d"]
	var s_len := (tg - Vector2((rd["com"] as Vector3).x, (rd["com"] as Vector3).z)).length()
	var land := {}
	var hipv := Vector2.ZERO
	for f in [0.5, 0.4, 0.3, 0.2, 0.1, 0.0]:
		hipv = d * (s_len * f)
		land = _stage(B, st0, sw, delta, hipv)
		if bool(land["ok"]):
			break
	if not bool(land["ok"]):
		return {"ok": false, "fall": true, "rd": rd, "why": "falls: the legs cannot reach the capture point %.0f cm away with the other foot planted. Run the Breakfall check to judge the landing" % (float(rd["step"]) * 100.0)}
	var mid := _stage(B, st0, sw, delta * 0.5 + Vector3(0, CLEAR, 0), hipv * 0.5)
	var nS := S.clone()
	nS.cards.insert(k + 1, {"name": "recovery swing", "pose": mid["dict"], "move": STEP_T * 0.5, "hold": 0.0})
	nS.cards.insert(k + 2, {"name": "recovery step", "pose": land["dict"], "move": STEP_T * 0.5, "hold": 0.3})
	var out := {"ok": true, "fall": false, "why": "", "rd": rd, "scene": nS, "k": k, "t0": ta, "hip": hipv.length(), "sole": float(land["sole"])}
	var m := measure(nS, k + 2, rd)
	for q in m:
		out[q] = m[q]
	out["t1"] = float(nS.times()[k + 2][2])
	out["msg"] = "step with the %s foot to the capture point: %.0f cm in %.2f s (landing %.1f cm from it)" % ["left" if sw == "_l" else "right", float(rd["step"]) * 100.0, STEP_T, float(out["land_err"]) * 100.0]
	return out


## read the finished plan from the scene itself: where the swing foot's centre lands against xi and where xi stands in the new base
static func measure(S: Scene, k: int, rd: Dictionary) -> Dictionary:
	var sc := S.clone()
	sc.baker = null
	var B := DistanceKeeper.new_body()
	sc.apply(B, float(sc.times()[k][1]))
	var xi: Vector2 = rd["xi"]
	var sw := String(rd["swing"])
	var ctr := centre(B, sw)
	var r := Balance.read(B)
	var c0: Vector2 = rd["com0"]
	return {"land_err": ctr.distance_to(xi), "land_at": ctr, "margin_after": Balance.signed_dist(r["poly"], xi), "poly_after": r["poly"], "com_after": r["com"],
		"foot_y": (B.P["foot" + sw] as Vector3).y, "xi_td": c0 + (xi - c0) * exp(float(rd["w0"]) * STEP_T)}
