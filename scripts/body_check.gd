## body_check.gd - L102: N056 STYLISED PROPORTIONS WITH CONSEQUENCES, N058 CAN THIS BODY STAND, N060 LOOKS STRONG ENOUGH. All read-only: they build their
## own Body (or read the open one) and never write the scene, the pose or the undo stack. Bars: tests/bodycheck2_test.gd.
## SOURCES are quoted from memory and UNVERIFIED (listed in the test header): specific tension 35 N/cm^2 (Zatsiorsky & Prilutsky 2012), quadriceps PCSA
## 87 cm^2 (Ward 2009), knee extensor arm 4.5 cm, cortical bone 170 MPa ultimate (Reilly & Burstein 1975), tibial cortical area 3.3 cm^2, gait load 4 BW,
## elbow / shoulder arms 4 / 5 cm. MINE: the face point, the half-squat lever (load line half a thigh behind the knee), the bone flag at half the ultimate stress.
##
## N056 style(body): the face point F = cervicale + (0, 0.5 h, 0.4 h), h = head height (cervicale -> top of head), standing at rest. The fingertips touch it when
##   the WRIST reaches W = F pulled back toward the shoulder by the hand length (wrist -> knuckle). margin = (upper arm + forearm) - |W - shoulder|; below 0 the
##   hand cannot touch the face (LimbIK.solve's miss is reported too). Jab reach = shoulder -> knuckle after LimbIK reaches for a far forward target.
##   Head mass share: de Leva's head % x f, f = (head length / the default head length at this stature)^3 (a bigger head is heavier); the COM is
##   shifted by that extra head mass. Breaks (thresholds mine): no face touch; face margin down > 2 cm; jab reach change >= 5 cm; head share +3 points or COM +/-3 cm.
## N058 stand(B, mass, size, leg_r, limits): BONE = single-leg stance x 4 BW through the tibial cortical area 3.3 cm^2 x (calf radius / default)^2;
##   MUSCLE = a half squat, each leg carries M g / 2 at a lever (half a thigh) over the knee extensor arm (4.5 cm x thigh / default thigh), over the quadriceps
##   area 87 cm^2 x (thigh radius / default)^2. size scales every length and radius (geometric similarity), leg_r only the leg radii.
## N060 muscle(joint, torque, girth): capacity = sigma x PCSA x arm; the PCSA at the default girth is set so the default arm equals ForceView.LIMIT_NM (the
##   strong-young-man cap every judge already uses), and it scales with girth^2. The elbow's muscle lives in the upper arm, the knee's in the thigh.
class_name BodyCheck
extends RefCounted

const SIGMA := 35.0   # N/cm^2
const QUAD_CM2 := 87.0
const KNEE_ARM_M := 0.045
const LEVER_THIGHS := 0.5
const TIBIA_CM2 := 3.3
const GAIT_BW := 4.0
const G := 9.81
const LIMITS := {"bone_mpa": 170.0, "muscle_ncm2": 35.0}
const BONE_SAFE := 0.5
const SHANK_FOOT_PCT := 4.33 + 1.37
const ARM_CM := {"upperarm": 5.0, "lowerarm": 4.0, "thigh": 5.0, "calf": 4.5}
const MUSCLE_SEG := {"lowerarm": "upperarm", "calf": "thigh"}
static var _ref: Body = null


static func _mk(d: Dictionary) -> Body:
	var b := Body.new()
	b.body = Proportions.clean(d)
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	for j in Body.ORDER:
		b.ang[j] = Vector3.ZERO
	b.offset = Vector3.ZERO
	b.fk()
	return b


static func _default() -> Body:
	if _ref == null:
		_ref = _mk({})
	return _ref


static func _face(b: Body) -> Dictionary:
	var cv := Proportions.cervicale(b)
	var hh := Proportions.head_top(b).y - cv.y
	var f := cv + Vector3(0, 0.5 * hh, 0.4 * hh)
	var s: Vector3 = b.P["upperarm_l"]
	var L := Proportions.lengths(b)
	var w := f - (f - s).normalized() * float(L["hand_mcp"])
	var margin := float(L["upper_arm"]) + float(L["forearm"]) - (w - s).length()
	var k := _mk(b.body)
	var sol := LimbIK.solve(k, "hand_l", w, LimbIK.pole_from_pose(k, "hand_l"))
	return {"margin_m": margin, "touch": margin >= 0.0, "ik_miss_m": float(sol["miss"])}


static func _jab(b: Body) -> float:
	var k := _mk(b.body)
	var s: Vector3 = k.P["upperarm_l"]
	LimbIK.solve(k, "hand_l", s + Vector3(0, 0, 2.0), LimbIK.pole_from_pose(k, "hand_l"))
	return ((k.E["hand_l"] as Vector3) - (k.P["upperarm_l"] as Vector3)).length()


static func _head_com(b: Body) -> Dictionary:
	var dl: Dictionary = Proportions.DE_LEVA[String(b.body.get("sex", "male"))]
	var Lc := Proportions.lengths(b)
	var Ld := Proportions.lengths(_default())
	var sat := float(b.body.get("stature", Proportions.DEFAULT_STATURE)) / Proportions.DEFAULT_STATURE
	var fh := pow(float(Lc["head"]) / (float(Ld["head"]) * sat), 3.0)
	var tot := 0.0
	var wtot := 0.0
	for s in Proportions.SEGS:
		var n := 1.0 if s in ["head", "trunk"] else 2.0
		var w := float(dl[s][0]) * n * Proportions.mass_factor(b, s)
		wtot += w
		tot += float(dl[s][0]) * n * (fh if s == "head" else Proportions.mass_factor(b, s))
	var extra := float(dl["head"][0]) * (fh - 1.0)
	var com := Proportions.com(b)
	var hc := Proportions.head_top(b).lerp(Proportions.cervicale(b), float(dl["head"][1]))
	var share := 100.0 * float(dl["head"][0]) * fh / tot
	return {"share_pct": share, "height_m": (com.y * wtot + hc.y * extra) / (wtot + extra), "f_head": fh}


static func style(d: Dictionary) -> Dictionary:
	var b := _mk(d)
	var r := _default()
	var fc := _face(b)
	var fr := _face(r)
	var jb := _jab(b)
	var jr := _jab(r)
	var hc := _head_com(b)
	var hr := _head_com(r)
	var stature := float(b.body.get("stature", Proportions.DEFAULT_STATURE))
	var out := {"ok": true, "face": fc, "jab": {"reach_m": jb, "default_m": jr, "delta_cm": 100.0 * (jb - jr)},
		"com": {"height_m": hc["height_m"], "frac_of_stature": float(hc["height_m"]) / stature, "delta_cm": 100.0 * (float(hc["height_m"]) - float(hr["height_m"]))},
		"head": {"share_pct": hc["share_pct"], "default_pct": hr["share_pct"], "delta_pp": float(hc["share_pct"]) - float(hr["share_pct"])}}
	var br := []
	if not fc["touch"]:
		br.append("can't touch his face: the wrist stops %.0f mm short (IK miss %.0f mm)" % [-1000.0 * float(fc["margin_m"]), 1000.0 * float(fc["ik_miss_m"])])
	elif float(fr["margin_m"]) - float(fc["margin_m"]) > 0.02:
		br.append("reduced face reach: margin %.0f mm against %.0f mm for the default body" % [1000.0 * float(fc["margin_m"]), 1000.0 * float(fr["margin_m"])])
	if absf(float(out["jab"]["delta_cm"])) >= 5.0:
		br.append("jab reach %+.1f cm against the default body (%.0f cm)" % [out["jab"]["delta_cm"], 100.0 * jb])
	if float(out["head"]["delta_pp"]) >= 3.0 or absf(float(out["com"]["delta_cm"])) >= 3.0:
		br.append("top-heavy: the head is %.1f %% of the mass (default %.1f %%), COM %+.1f cm to %.0f %% of the stature" % [hc["share_pct"], hr["share_pct"], out["com"]["delta_cm"], 100.0 * float(out["com"]["frac_of_stature"])])
	out["breaks"] = br
	out["msg"] = "no breaks against the default body" if br.is_empty() else " | ".join(PackedStringArray(br))
	return out


static func stand(B: Body, mass := 75.0, size := 1.0, leg_r := 1.0, limits := {}) -> Dictionary:
	var lim: Dictionary = LIMITS.duplicate()
	lim.merge(limits, true)
	var R := _default()
	var rt := float(B.rad["thigh_l"]) * size * leg_r
	var rc := float(B.rad["calf_l"]) * size * leg_r
	var rt0 := float(R.rad["thigh_l"])
	var rc0 := float(R.rad["calf_l"])
	var thigh := ((B.p0["calf_l"] as Vector3) - (B.p0["thigh_l"] as Vector3)).length() * size
	var thigh0 := ((R.p0["calf_l"] as Vector3) - (R.p0["thigh_l"] as Vector3)).length()
	var bone_a := TIBIA_CM2 * pow(rc / rc0, 2.0)
	var bone_f := GAIT_BW * mass * (1.0 - SHANK_FOOT_PCT / 100.0) * G
	var musc_a := QUAD_CM2 * pow(rt / rt0, 2.0)
	var arm := KNEE_ARM_M * thigh / thigh0
	var musc_f := 0.5 * mass * G * LEVER_THIGHS * thigh / arm
	var bone := bone_f / (bone_a * 100.0)
	var musc := musc_f / musc_a
	var br := bone / (BONE_SAFE * float(lim["bone_mpa"]))
	var mr := musc / float(lim["muscle_ncm2"])
	var flag := br >= 1.0 or mr >= 1.0
	var msg := "legs OK for %.0f kg: bone %.1f MPa (%.0f %% of the safe stress), muscle %.1f N/cm2 (%.0f %% of the limit)" % [mass, bone, 100.0 * br, musc, 100.0 * mr]
	if flag:
		msg = "legs too thin to carry %.0f kg: %s" % [mass, "bone %.1f MPa = %.0f %% of the safe stress" % [bone, 100.0 * br] if br >= 1.0 else "quadriceps %.1f N/cm2 = %.0f %% of the %.0f N/cm2 limit" % [musc, 100.0 * mr, float(lim["muscle_ncm2"])]]
	return {"ok": true, "bone_mpa": bone, "muscle_ncm2": musc, "bone_force_n": bone_f, "bone_area_cm2": bone_a, "muscle_force_n": musc_f,
		"muscle_area_cm2": musc_a, "bone_ratio": br, "muscle_ratio": mr, "flag": flag, "msg": msg}


static func _ref_r(seg: String) -> float:
	var R := _default()
	return float(R.rad[seg + "_l"])


## capacity of the muscle at `joint` (name with side) for girth x `girth` (of the default girth, or of B's own when B is given)
static func muscle(joint: String, torque: float, girth := 1.0, B: Body = null) -> Dictionary:
	var kind := ForceView.kind_of(joint)
	var seg := String(MUSCLE_SEG.get(kind, kind))
	var sd := "_r" if joint.ends_with("_r") else "_l"
	var r0 := _ref_r(seg)
	var r := (float(B.rad[seg + sd]) if B != null and B.rad.has(seg + sd) else r0) * girth
	var lim: float = float(ForceView.LIMIT_NM.get(kind, 100.0))
	var arm := float(ARM_CM.get(kind, 4.0))
	var k := pow(r / r0, 2.0)
	var cap := lim * k
	var have := lim * 100.0 / (SIGMA * arm) * k
	var need := torque * 100.0 / (SIGMA * arm)
	var pf := have / (PI * r * r * 1.0e4)
	var flag := torque > cap
	var msg := "%s: %.0f N m needs %.0f cm2 of muscle (%.0f N/cm2, arm %.0f cm); this girth (%.1f cm) gives %.0f cm2 = %.0f N m" % [joint, torque, need, SIGMA, arm, 100.0 * r, have, cap]
	if flag:
		msg = "skinny %s: " % joint + msg
	return {"ok": true, "joint": joint, "capacity_nm": cap, "need_pcsa_cm2": need, "have_pcsa_cm2": have, "contractile_fraction": pf,
		"ratio": torque / cap, "flag": flag, "msg": msg}


## the open clip's peak torque per joint against what the muscle girth could make; `arm_girth` scales the arms' girth
static func clip(S: Scene, B: Body, arm_girth := 1.0) -> Dictionary:
	var sm := ForceView.sample(S, B)
	if sm.is_empty() or not sm.has("tau"):
		return {"ok": false, "msg": "needs two cards or more", "joints": {}, "peak_joint": "", "peak_ratio": 0.0, "flags": []}
	var joints := {}
	var flags := []
	var pj := ""
	var pr := -1.0
	for j in ForceView.joints():
		if not (sm["tau"] as Dictionary).has(j):
			continue
		var tau := ForceView.peak_nm(sm, j)
		var kind := ForceView.kind_of(j)
		var cap: float
		if kind in ["upperarm", "lowerarm"]:
			cap = float(muscle(j, tau, arm_girth, B)["capacity_nm"])
		else:
			cap = float(ForceView.LIMIT_NM[kind])
		var ratio := tau / cap
		joints[j] = {"peak_nm": tau, "cap_nm": cap, "ratio": ratio, "flag": ratio > 1.0}
		if ratio > 1.0 and kind in ["upperarm", "lowerarm"]:
			flags.append("skinny %s: the clip needs %.0f N m, this girth gives %.0f N m" % [j, tau, cap])
		if ratio > pr:
			pr = ratio
			pj = j
	return {"ok": true, "joints": joints, "peak_joint": pj, "peak_ratio": pr, "flags": flags,
		"msg": "peak joint %s at %.2f of its cap" % [pj, pr] + ("; " + "; ".join(PackedStringArray(flags)) if not flags.is_empty() else "")}


static func serve(tool: String, m: Variant, p: Dictionary) -> Dictionary:
	var B: Body = m.B
	if tool == "proportion_breaks":
		return {"ok": true, "result": style(p.get("body", B.body))}
	if tool == "can_stand":
		var mass := float(p.get("mass", B.body.get("mass", 75.0)))
		return {"ok": true, "result": stand(_mk(B.body), mass, float(p.get("size", 1.0)), float(p.get("leg_r", 1.0)))}
	if tool == "looks_strong":
		if p.has("joint") and p.has("torque"):
			return {"ok": true, "result": muscle(String(p["joint"]), float(p["torque"]), float(p.get("girth", 1.0)), null)}
		return {"ok": true, "result": clip(m.S, B, float(p.get("girth", 1.0)))}
	return {"ok": false, "error": "unknown tool"}
