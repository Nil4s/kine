## proportions.gd - CHARACTER PROPORTIONS (round 51, GATES PR; docs/GAP_ANALYSIS.md row 17). Every number with its
## source: docs/research/PROPORTIONS.md.
##
## A body's proportions are a STATURE (m, floor to the top of the head, standing) plus a scale per SEGMENT (upper arm,
## forearm, hand, thigh, shank, foot, trunk, head). data/skeleton.json is never edited: Body.load_files reads it and
## then scale_rest() maps every rest point. Each joint j belongs to one segment and gets one UNIFORM scale
##     s(j) = g * k[seg(j)]                    (k = the segment's scale, g = solved so the stature comes out exact)
## and the rest skeleton is rebuilt root first:
##     p0'[j] = p0'[parent] + s(parent) * (p0[j] - p0[parent])      (a bone's length scales with the bone's own segment)
##     x'     = p0'[j] + s(j) * (x - p0[j])                            (every point riding j: its end, capsule, skin points)
##     r'     = s(j) * r                                               (capsule radius)
## then moved up/down so the ankle stands s(foot) * its rest height above the floor. Everything is a multiple of g,
## so g = requested stature / the stature at g = 1. The mesh follows by a uniform bone scale (scale_skeleton): the same
## map exactly, so a longer forearm is also a proportionally thicker one (girth is not scaled apart from length: stated).
## A scene keeps its proportions in the optional key "body" (written only when not the default body).
class_name Proportions
extends RefCounted

const SEGS := ["upper_arm", "forearm", "hand", "thigh", "shank", "foot", "trunk", "head"]
## the mannequin as shipped (assets/mannequin.glb, measured by its vertices at rest): highest vertex y 1.82918 (the top
## of the head), lowest 0.00046 (the soles), the left foot's back of the heel z -0.09771 and toe tip z 0.20544
const MESH_TOP := 1.82918
const MESH_SOLE := 0.00046
const HEEL_Z := -0.09771
const TOE_Z := 0.20544
const DEFAULT_STATURE := MESH_TOP - MESH_SOLE   # 1.82872 m
## rest positions in data/skeleton.json the landmarks ride on (read only here; the file is the truth, test checks them)
const HEAD0 := Vector3(0.0, 1.5687, 0.0051)
const FOOT0_Y := 0.1037
const FOOT0_Z := -0.0358
const BALL0_Z := 0.1132

## de Leva 1996 (J. Biomech. 29(9) 1223-1230), Table 4 (read from the page): mass % of body mass, and the COM along the
## segment as a fraction from the FIRST endpoint named. Head and trunk use the table's alternative endpoints (VERT ->
## CERV, CERV -> MIDH) because cervicale is a point this skeleton has (neck_01): head vertex -> cervicale, trunk
## cervicale -> mid hip joints, upper arm shoulder ->
## elbow, forearm elbow -> wrist, hand wrist -> 3rd metacarpale, thigh hip -> knee, shank knee -> lateral malleolus,
## foot heel -> toe tip. (Numbers: docs/research/PROPORTIONS.md, section 3.)
## Each row is [mass %, COM fraction, sagittal r, transverse r, longitudinal r]: the radii of gyration about the segment's own COM,
## as fractions of the segment length (Table 4 columns "Sagittal r", "Transverse r", "Longitudinal r", % / 100), read from the page
## image 2026-10-20 (docs/physics_constants.md). THE ONE TABLE: HitReaction.pieces, SpinCheck, HumanLimits, the Force view, the
## momentum read and the hit physics all take their masses, COM fractions and radii from here (Proportions.rg / kperp / klong).
const DE_LEVA := {
	"male": {"head": [6.94, 0.5002, 0.303, 0.315, 0.261], "trunk": [43.46, 0.5138, 0.328, 0.306, 0.169],
		"upper_arm": [2.71, 0.5772, 0.285, 0.269, 0.158], "forearm": [1.62, 0.4574, 0.276, 0.265, 0.121],
		"hand": [0.61, 0.7900, 0.628, 0.513, 0.401], "thigh": [14.16, 0.4095, 0.329, 0.329, 0.149],
		"shank": [4.33, 0.4459, 0.255, 0.249, 0.103], "foot": [1.37, 0.4415, 0.257, 0.245, 0.124]},
	"female": {"head": [6.68, 0.4841, 0.271, 0.295, 0.261], "trunk": [42.57, 0.4964, 0.307, 0.292, 0.147],
		"upper_arm": [2.55, 0.5754, 0.278, 0.260, 0.148], "forearm": [1.38, 0.4559, 0.261, 0.257, 0.094],
		"hand": [0.56, 0.7474, 0.531, 0.454, 0.335], "thigh": [14.78, 0.3612, 0.369, 0.364, 0.162],
		"shank": [4.81, 0.4416, 0.271, 0.267, 0.093], "foot": [1.29, 0.4014, 0.299, 0.279, 0.139]},
}
## the table's other hand row, wrist (WJC) -> 3rd dactylion (DAC3), for a hand measured to the fingertip: [sagittal, transverse, longitudinal]
const DE_LEVA_HAND_DAC3 := {"male": [0.288, 0.235, 0.184], "female": [0.244, 0.208, 0.154]}


## the radius of gyration ACROSS a segment's bone (m per unit of length): the root mean square of the sagittal and transverse radii
static func kperp(sex: String, seg: String) -> float:
	var r: Array = DE_LEVA[sex][seg]
	return sqrt((float(r[2]) * float(r[2]) + float(r[3]) * float(r[3])) * 0.5)


## the radius of gyration ALONG a segment's bone (the twist radius), per unit of length
static func klong(sex: String, seg: String) -> float:
	return float(DE_LEVA[sex][seg][4])


## segment lengths as a fraction of stature H: Drillis & Contini 1966 via Winter, Biomechanics and Motor Control of
## Human Movement (4th ed. 2009) Fig. 4.1. upper arm 0.186, forearm 0.146, hand 0.108, thigh (hip -> knee) 0.245,
## shank (knee -> ankle) 0.246, foot length 0.152, trunk = shoulder height 0.818 - hip height 0.530 = 0.288.
## head = the rest of the stature over the shoulder (0.182 in the table); it is what g leaves, not set.
const DRILLIS := {"upper_arm": 0.186, "forearm": 0.146, "hand": 0.108, "thigh": 0.245, "shank": 0.246, "foot": 0.152,
	"trunk": 0.288, "head": 0.182}

## PRESETS: stature and body mass percentiles from ANSUR II (Gordon et al. 2014, NATICK/TR-15/007, pp. 192-193 and
## 224-225; the same numbers computed from the public data, 4082 men, 1986 women: docs/research/PROPORTIONS.md);
## segment proportions from DRILLIS (one table for all six)
const PRESETS := {
	"female_5": {"stature": 1.525, "mass": 51.3, "sex": "female"},
	"female_50": {"stature": 1.626, "mass": 66.8, "sex": "female"},
	"female_95": {"stature": 1.740, "mass": 87.1, "sex": "female"},
	"male_5": {"stature": 1.648, "mass": 64.4, "sex": "male"},
	"male_50": {"stature": 1.755, "mass": 84.6, "sex": "male"},
	"male_95": {"stature": 1.870, "mass": 110.7, "sex": "male"},
}
const PRESET_NAMES := {"female_5": "5th percentile woman", "female_50": "50th percentile woman", "female_95": "95th percentile woman",
	"male_5": "5th percentile man", "male_50": "50th percentile man", "male_95": "95th percentile man"}


## the segment a joint belongs to (its own capsule, its end, and the bones it starts)
static func seg_of(j: String) -> String:
	if j.begins_with("upperarm"):
		return "upper_arm"
	if j.begins_with("lowerarm"):
		return "forearm"
	if j.begins_with("hand") or j.begins_with("thumb") or j.begins_with("index") or j.begins_with("middle") or j.begins_with("ring") or j.begins_with("pinky"):
		return "hand"
	if j.begins_with("thigh"):
		return "thigh"
	if j.begins_with("calf"):
		return "shank"
	if j.begins_with("foot") or j.begins_with("ball"):
		return "foot"
	if j == "head" or j == "neck_01":
		return "head"
	return "trunk"   # pelvis, spine_01..03, the clavicles (shoulder width) and the hip width (pelvis -> thigh)


## GIRTH FROM MASS (R11). Body mass thickens the skin ACROSS each bone's axis and never lengthens a bone, by the
## elasticity e of that part's circumference to body mass AT A FIXED STATURE: C ~ mass^e. e is the coefficient of ln(mass)
## in  ln C = a + e ln(mass) + c ln(stature)  fitted on the ANSUR II public files (Gordon et al. 2014; 4082 men, 1986
## women; recomputed for this feature, a script, not read from a table). Men / women, the mean is used (the two differ by
## < 0.09, below the survey's own scatter):
##   waist (omphalion) 0.728 / 0.719     chest 0.508 / 0.523     buttock (hips) 0.452 / 0.462     thigh 0.573 / 0.576
##   biceps (flexed) 0.549 / 0.632       forearm (flexed) 0.368 / 0.384     calf 0.416 / 0.411     neck 0.351 / 0.305
##   wrist 0.193 / 0.187                 ankle 0.273 / 0.253                 head 0.075 / 0.063
## so mass P5 -> P95 (x1.72 men, x1.70 women) grows the waist x1.48, the thigh x1.36, the forearm x1.22, the head x1.04.
## A joint takes the elasticity of the circumference measured on its segment (spine_01 holds the omphalion, 0.60 H);
## spine_02 sits between the waist and the chest. Feet and toes: 0 (the sole stays on the floor; foot size follows stature).
## The reference: the MEDIAN person of that stature and sex has factor 1 (the mannequin's shape); expected mass at stature H
## = median mass x (H / median stature)^b with b = 2.00 men / 2.19 women, the slope of ln(mass) on ln(stature) in the
## same files. lambda = ln(mass / expected mass); a part's circumference factor is exp(e lambda).
const GIRTH_E := {"pelvis": 0.457, "spine_01": 0.724, "spine_02": 0.62, "spine_03": 0.516, "clavicle": 0.516, "neck_01": 0.328,
	"head": 0.069, "upperarm": 0.59, "lowerarm": 0.376, "hand": 0.19, "thigh": 0.575, "calf": 0.414, "foot": 0.0, "ball": 0.0}
const MASS_STATURE_B := {"male": 2.00, "female": 2.19}


## a joint's elasticity of circumference to mass (0 for the joints that are not skin: the root, the feet)
static func girth_e(j: String) -> float:
	if GIRTH_E.has(j):
		return float(GIRTH_E[j])
	for k in ["clavicle", "upperarm", "lowerarm", "thigh", "calf", "foot", "ball"]:
		if j.begins_with(k):
			return float(GIRTH_E[k])
	if seg_of(j) == "hand":
		return float(GIRTH_E["hand"])
	return 0.0


## lambda = ln(mass / the median person's mass at this stature and blend); 0 for a body with no mass
static func girth_lambda(body: Dictionary) -> float:
	if not body.has("mass"):
		return 0.0
	var bl := float(body.get("blend", 0.0 if String(body.get("sex", "male")) == "female" else 1.0))
	var st := float(body.get("stature", DEFAULT_STATURE))
	var b := lerpf(float(MASS_STATURE_B["female"]), float(MASS_STATURE_B["male"]), bl)
	var m_exp := BodyModel.mass_at(bl, 50.0) * pow(st / BodyModel.stature_at(bl, 50.0), b)
	return log(float(body["mass"]) / m_exp)


## the part's girth factor (circumference now / circumference of the median person this tall)
static func girth_factor(j: String, lam: float) -> float:
	return exp(girth_e(j) * lam)


## a body dict as the file keeps it: {} for the default body; else stature (m), the scales that are not 1, sex, mass,
## preset. Unknown keys are dropped (the schema rejects them in a file).
static func clean(d: Dictionary) -> Dictionary:
	if d.is_empty():
		return {}
	var out := {}
	var st := snappedf(clampf(float(d.get("stature", DEFAULT_STATURE)), 0.5, 2.5), 0.0001)
	var sc := {}
	var din: Dictionary = d.get("scale", {}) if d.get("scale") is Dictionary else {}
	for s in SEGS:
		var v := snappedf(clampf(float(din.get(s, 1.0)), 0.5, 2.0), 0.0001)
		if v != 1.0:
			sc[s] = v
	if absf(st - snappedf(DEFAULT_STATURE, 0.0001)) > 1e-9 or not sc.is_empty() or d.has("sex") or d.has("mass"):
		out["stature"] = st
	else:
		return {}
	if not sc.is_empty():
		out["scale"] = sc
	if String(d.get("sex", "")) in ["male", "female"]:
		out["sex"] = String(d["sex"])
	if d.has("blend") and out.has("sex"):   # R12: the man/woman blend (0..1) the BODY page made this body from; only a true blend is kept (0 and 1 are the sexes)
		var bl := snappedf(clampf(float(d["blend"]), 0.0, 1.0), 0.001)
		if bl > 0.0 and bl < 1.0 and (bl >= 0.5) == (String(out["sex"]) == "male"):
			out["blend"] = bl
	if d.has("mass"):
		out["mass"] = snappedf(clampf(float(d["mass"]), 20.0, 250.0), 0.1)
	if d.has("preset") and PRESETS.has(String(d["preset"])):
		out["preset"] = String(d["preset"])
	return out


## the default body's segment lengths (m), measured on the rest skeleton/mesh as the source table measures them
static func default_lengths() -> Dictionary:
	return {"upper_arm": 0.27444, "forearm": 0.27264, "hand": 0.9711 - 0.7389, "thigh": 0.40031, "shank": 0.42948,
		"foot": TOE_Z - HEEL_Z, "trunk": 1.4408 - 0.9321, "head": MESH_TOP - 1.4408}


## a preset's body dict: its stature, mass and sex, and the segment scales that make seven segments Drillis &
## Contini's fractions of THAT stature exactly. This mannequin's ankle stands higher than the table's 0.039 H, so one
## segment must give: the TRUNK takes what is left (then the shoulder and the head, the reach's root, stand at the
## table's heights and the hip ~1 % of H high), reported by tests/proportions_test.gd
const TRUNK_RISE := 1.4876 - 0.9321   # the stature the trunk's scale multiplies (hip joint -> neck_01, m)
static func preset(name: String) -> Dictionary:
	var p: Dictionary = PRESETS[name]
	var st := float(p["stature"])
	var L := default_lengths()
	var sc := {}
	for s in SEGS:
		sc[s] = float(DRILLIS[s]) * st / float(L[s])
	var tmp := Body.new()
	tmp.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	tmp.body = {"stature": st, "scale": sc}
	tmp.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var g: float = float(tmp.seg_s["pelvis"]) / float(sc["trunk"])
	sc["trunk"] = float(sc["trunk"]) + (st - st / g) / TRUNK_RISE   # st / g = the stature these scales give at g = 1
	return {"stature": st, "scale": sc, "sex": p["sex"], "mass": p["mass"], "preset": name}


## THE MAP (called by Body.load_files after it has read the files, before the contact calibration)
static func scale_rest(B: Body) -> void:
	var k := {}
	var din: Dictionary = B.body.get("scale", {})
	for s in SEGS:
		k[s] = float(din.get(s, 1.0))
	var s1 := {}
	for j in Body.ORDER:
		s1[j] = float(k[seg_of(j)])
	# g = 1: root first, then stand the ankle on its scaled height
	var np := {}
	for j in Body.ORDER:
		var pj: String = B.parent[j]
		np[j] = B.p0[j] if pj == "" else (np[pj] as Vector3) + float(s1[pj]) * ((B.p0[j] as Vector3) - (B.p0[pj] as Vector3))
	var dy: float = float(s1["foot_l"]) * FOOT0_Y - (np["foot_l"] as Vector3).y
	for j in np:
		np[j] = (np[j] as Vector3) + Vector3(0, dy, 0)
	var top1: float = (np["head"] as Vector3).y + float(s1["head"]) * (MESH_TOP - HEAD0.y)
	var sole1: float = float(s1["foot_l"]) * MESH_SOLE
	var g: float = float(B.body.get("stature", DEFAULT_STATURE)) / (top1 - sole1)
	var s := {}
	var p1 := {}
	for j in Body.ORDER:
		s[j] = g * float(s1[j])
		p1[j] = (np[j] as Vector3) * g
	var mp := func(j: String, x: Vector3) -> Vector3: return (p1[j] as Vector3) + float(s[j]) * (x - (B.p0[j] as Vector3))
	# R11: girth. The skin points move out across the bone's axis (never along it), the collision radii grow in step
	var lam := girth_lambda(B.body)
	var fg := {}
	for j in Body.ORDER:
		fg[j] = girth_factor(j, lam)
	var axis0 := {}   # the unscaled axis (a, direction) of the parts that carry skin points
	for part in B.skin:
		axis0[part] = [B.p0[part], ((B.e0[part] as Vector3) - (B.p0[part] as Vector3)).normalized()]
	for j in Body.ORDER:
		B.e0[j] = mp.call(j, B.e0[j])
		B.cap0[j] = [mp.call(j, B.cap0[j][0]), mp.call(j, B.cap0[j][1])]
		B.rad[j] = float(B.rad[j]) * float(s[j]) * float(fg[j])
	for w in Body.WIDE:
		var jw: String = Body.WIDE[w][0]
		B.cap0[w] = [mp.call(jw, B.cap0[w][0]), mp.call(jw, B.cap0[w][1])]
		B.rad[w] = float(B.rad[w]) * float(s[jw]) * float(fg[jw])
	for part in B.skin:
		var ax: Array = axis0[part]
		var fp: float = fg[part]
		B.skin[part] = (B.skin[part] as Array).map(func(q):
			var rel: Vector3 = (q as Vector3) - (ax[0] as Vector3)
			var radial: Vector3 = rel - (ax[1] as Vector3) * rel.dot(ax[1])
			return mp.call(part, (q as Vector3) + radial * (fp - 1.0)))
		B.skin_c[part] = [mp.call(part, B.skin_c[part][0]), float(B.skin_c[part][1]) * float(s[part]) * fp]
	for j in Body.ORDER:
		B.p0[j] = p1[j]
	B._fk_a = {}   # ROADMAP 99: the rest points moved, every joint is computed again
	B.seg_s = s


## the scale each segment really has (g * k): what a bone of that segment is multiplied by
static func seg_scale(B: Body, seg: String) -> float:
	for j in Body.ORDER:
		if seg_of(j) == seg:
			return float(B.seg_s.get(j, 1.0))
	return 1.0


## LANDMARKS on the mesh, where they are now (any pose): the top of the head, the back of a heel, a toe tip
static func head_top(B: Body) -> Vector3:
	var s: float = B.seg_s.get("head", 1.0)
	return (B.P["head"] as Vector3) + (B.G["head"] as Quaternion) * (Vector3(0, MESH_TOP, HEAD0.z) - HEAD0) * s


static func heel(B: Body, sd: String) -> Vector3:
	var s: float = B.seg_s.get("foot" + sd, 1.0)
	var x := 0.089 if sd == "_l" else -0.089
	return (B.P["foot" + sd] as Vector3) + (B.G["foot" + sd] as Quaternion) * (Vector3(x, MESH_SOLE, HEEL_Z) - Vector3(x, FOOT0_Y, FOOT0_Z)) * s


static func toe(B: Body, sd: String) -> Vector3:
	var s: float = B.seg_s.get("ball" + sd, 1.0)
	var x := 0.089 if sd == "_l" else -0.089
	return (B.P["ball" + sd] as Vector3) + (B.G["ball" + sd] as Quaternion) * (Vector3(x, 0.0152, TOE_Z) - Vector3(x, 0.0152, BALL0_Z)) * s


## the segment lengths as measured now (rest pose: as the table measures them), m
static func lengths(B: Body) -> Dictionary:
	var keep := B.state()
	for j in Body.ORDER:
		B.ang[j] = Vector3.ZERO
	B.offset = Vector3.ZERO
	B.fk()
	var hl: float = ((B.P["hand_l"] as Vector3) - (B.P["middle_01_l"] as Vector3)).length()
	var tip: Vector3 = (B.P["middle_03_l"] as Vector3) + (B.G["middle_03_l"] as Quaternion) * ((B.e0["middle_03_l"] as Vector3) - (B.p0["middle_03_l"] as Vector3))
	var out := {"upper_arm": ((B.P["lowerarm_l"] - B.P["upperarm_l"]) as Vector3).length(),
		"forearm": ((B.P["hand_l"] - B.P["lowerarm_l"]) as Vector3).length(),
		"hand": (tip - (B.P["hand_l"] as Vector3)).x,
		"thigh": ((B.P["calf_l"] - B.P["thigh_l"]) as Vector3).length(),
		"shank": ((B.P["foot_l"] - B.P["calf_l"]) as Vector3).length(),
		"foot": toe(B, "_l").z - heel(B, "_l").z,
		"trunk": (B.P["upperarm_l"] as Vector3).y - (B.P["thigh_l"] as Vector3).y,
		"head": head_top(B).y - (B.P["upperarm_l"] as Vector3).y,
		"stature": head_top(B).y - heel(B, "_l").y}
	out["hand_mcp"] = hl
	B.set_state(keep)
	return out


## CERVICALE (C7), the end de Leva's head and trunk share: on the neck bone (neck_01 -> head) at the height ANSUR II's
## median cervicale height has as a fraction of stature (men 1517 / 1755 mm, women 1393 / 1626 mm), carried by the
## neck in any pose
const CERV_FRAC := {"male": 1517.0 / 1755.0, "female": 1393.0 / 1626.0}


static func cervicale(B: Body) -> Vector3:
	var st: float = float(B.body.get("stature", DEFAULT_STATURE))
	var floor_y: float = float(B.seg_s.get("foot_l", 1.0)) * MESH_SOLE
	var a: Vector3 = B.p0["neck_01"]
	var b: Vector3 = B.p0["head"]
	var u := (floor_y + float(CERV_FRAC[String(B.body.get("sex", "male"))]) * st - a.y) / maxf(1e-6, b.y - a.y)
	return (B.P["neck_01"] as Vector3) + (B.G["neck_01"] as Quaternion) * ((b - a) * u)


## how much heavier a LIMB segment is than de Leva's person of this stature: (its length / Drillis' length)^3 (a
## uniformly scaled part's volume). A preset's limbs are Drillis' exactly, so its masses are de Leva's own table; the
## trunk and head keep de Leva's share (their lengths here are what the stature leaves, not a choice: stated).
static func mass_factor(B: Body, seg: String) -> float:
	if seg == "trunk" or seg == "head":
		return 1.0
	var st: float = float(B.body.get("stature", DEFAULT_STATURE))
	var r: float = float(default_lengths()[seg]) * seg_scale(B, seg) / (float(DRILLIS[seg]) * st)
	return r * r * r


## THE CENTRE OF MASS of a body with proportions (Balance.com sends a scaled body here): de Leva's masses for its sex,
## each times mass_factor, at de Leva's COM fraction between its two endpoints in the pose: head = top of head ->
## cervicale, trunk = cervicale -> the hip joints' middle.
static func com(B: Body) -> Vector3:
	var t: Dictionary = DE_LEVA[String(B.body.get("sex", "male"))]
	var mid_hip: Vector3 = ((B.P["thigh_l"] as Vector3) + (B.P["thigh_r"] as Vector3)) * 0.5
	var cv := cervicale(B)
	var segs := [["head", head_top(B), cv, "head"], ["trunk", cv, mid_hip, "spine_02"]]
	for sd in ["_l", "_r"]:
		var tip: Vector3 = B.E["hand" + sd]   # the hand bone's end = the middle finger's knuckle (3rd metacarpale)
		segs.append_array([["upper_arm", B.P["upperarm" + sd], B.P["lowerarm" + sd], "upperarm" + sd],
			["forearm", B.P["lowerarm" + sd], B.P["hand" + sd], "lowerarm" + sd], ["hand", B.P["hand" + sd], tip, "hand" + sd],
			["thigh", B.P["thigh" + sd], B.P["calf" + sd], "thigh" + sd], ["shank", B.P["calf" + sd], B.P["foot" + sd], "calf" + sd],
			["foot", heel(B, sd), toe(B, sd), "foot" + sd]])
	var sum := Vector3.ZERO
	var w := 0.0
	var mf := {}
	for s in SEGS:
		mf[s] = mass_factor(B, s)
	for q in segs:
		var m: float = float(t[q[0]][0]) * float(mf[q[0]])
		sum += ((q[1] as Vector3).lerp(q[2], float(t[q[0]][1]))) * m
		w += m
	return sum / w


## each segment's mass, kg (both sides summed), for the readout: de Leva % x scale^3, renormalised to the body's mass
static func masses(B: Body) -> Dictionary:
	var t: Dictionary = DE_LEVA[String(B.body.get("sex", "male"))]
	var raw := {}
	var tot := 0.0
	for s in SEGS:
		var n := 1.0 if s in ["head", "trunk"] else 2.0
		raw[s] = float(t[s][0]) * n * mass_factor(B, s)
		tot += raw[s]
	var kg: float = float(B.body.get("mass", 0.0))
	var out := {}
	for s in raw:
		out[s] = raw[s] / tot * kg if kg > 0.0 else raw[s] / tot
	return out


## THE MESH: every bone of a mannequin skeleton gets the uniform scale that makes its global scale s(j) (its parent's
## global scale divided out), so the skinned mesh is the same map as the capsules. Bones that are not ours (the root,
## finger leaves) keep scale 1 locally and ride their parent. A default body puts every scale back to 1 once.
static func scale_skeleton(sk: Skeleton3D, idx: Dictionary, b: Body) -> void:
	if b.seg_s.is_empty():
		if sk.has_meta("pr_scaled"):
			for i in sk.get_bone_count():
				sk.set_bone_pose_scale(i, Vector3.ONE)
			sk.remove_meta("pr_scaled")
		return
	if sk.has_meta("pr_scaled") and sk.get_meta("pr_scaled") == b.seg_s.hash():
		return
	var of := {}
	for j in idx:
		if idx[j] >= 0:
			of[idx[j]] = j
	var gs := {}
	for i in sk.get_bone_count():   # Skeleton3D lists parents before children
		var p := sk.get_bone_parent(i)
		var pg: float = gs.get(p, 1.0)
		var want: float = float(b.seg_s[of[i]]) if of.has(i) else pg
		gs[i] = want
		sk.set_bone_pose_scale(i, Vector3.ONE * (want / pg))
	sk.set_meta("pr_scaled", b.seg_s.hash())


## RETARGET (PR3): the scene's cards onto new proportions. Each card keeps every joint angle; its hips move up or down
## by what the new legs need so the lowest sole is as high above the floor as it was (on the floor stays on the floor,
## a card in the air stays as high in the air). The world-space IK keys are left as they are: they are reached by the
## new limbs where they can be. B is the scene's body (any proportions); it is put back as it was.
static func retarget(S: Scene, B: Body, nbody: Dictionary) -> void:
	var nb := clean(nbody)
	var old := Body.new()
	old.load_files(B._files[0], B._files[1])
	old.set_proportions(S.body)
	var nw := Body.new()
	nw.load_files(B._files[0], B._files[1])
	nw.set_proportions(nb)
	for c in S.cards:
		var f := Moves._flat(c["pose"])
		Scene.put(old, f)
		var lo0 := old.sole_low()
		Scene.put(nw, f)
		nw.offset.y += lo0 - nw.sole_low()
		nw.fk()
		var keep_w: Dictionary = c["pose"].get("weapon", {})
		var pd := nw.to_dict()
		pd.erase("contacts")
		var o: Dictionary = (c["pose"] as Dictionary).duplicate(true)
		o["offset"] = pd["offset"]
		for j in o.get("joints", {}):
			if pd["joints"].has(j):
				o["joints"][j]["pos"] = pd["joints"][j]["pos"]
				o["joints"][j]["end"] = pd["joints"][j]["end"]
		o["weapon"] = keep_w
		c["pose"] = o
	S.body = nb
	S._times_memo = []
	S._flat_memo = {}


## THE EXPORTED MANNEQUIN (PR2, glb): the proportions baked into the file's rest skeleton and mesh, so an importer reads
## the scaled bone lengths as plain node translations (no bone scale, which importers treat unevenly). Each bone's rest
## translation times its parent's global scale; each vertex by the same map as the capsules, blended by its skin
## weights:  v' = sum_i w_i (P'_i + s_i (v - P_i));  each bind pose = the new global rest's inverse.
static func bake_mannequin(man: Node3D, sk: Skeleton3D, b: Body) -> void:
	if b.seg_s.is_empty():
		return
	var of := {}
	for j in Body.ORDER:
		var bi := sk.find_bone("Head" if j == "head" else j)
		if bi >= 0:
			of[bi] = j
	var n := sk.get_bone_count()
	var lam := girth_lambda(b.body)   # R11: the girth is in the exported skin too (shapes from the file's own rest pose)
	var gsh := {}
	if lam != 0.0:
		for mi in man.find_children("*", "MeshInstance3D", true, false):
			var gm := mi as MeshInstance3D
			if gm.skin != null and gm.mesh is ArrayMesh:
				gsh[gm] = Corrective.girth_shapes(sk, gm.skin, gm.mesh as ArrayMesh)
	var gs := {}
	var p_old := {}
	var rest_old := {}
	for i in n:
		rest_old[i] = sk.get_bone_global_rest(i)
		var p := sk.get_bone_parent(i)
		gs[i] = float(b.seg_s[of[i]]) if of.has(i) else float(gs.get(p, 1.0))
		p_old[i] = sk.get_bone_global_rest(i).origin
	for i in n:
		var p := sk.get_bone_parent(i)
		var r := sk.get_bone_rest(i)
		if p >= 0:
			r.origin *= float(gs[p])
		sk.set_bone_rest(i, r)
		sk.set_bone_pose_scale(i, Vector3.ONE)
	# the pelvis's rest: where the scaled body's pelvis stands (its parent, the root, is not scaled)
	var pi := sk.find_bone("pelvis")
	if pi >= 0:
		var r := sk.get_bone_rest(pi)
		r.origin = b.root_rot.inverse() * ((b.p0["pelvis"] as Vector3) - b.root_pos)
		sk.set_bone_rest(pi, r)
	sk.reset_bone_poses()   # the exporter writes the bones' poses: they start at the new rests
	var p_new := {}
	for i in n:
		p_new[i] = sk.get_bone_global_rest(i).origin
	for mi in man.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var skin := m.skin
		if skin == null or not (m.mesh is ArrayMesh):
			continue
		var bone_of_bind := []
		for k in skin.get_bind_count():
			var bb := skin.get_bind_bone(k)
			if bb < 0:
				bb = sk.find_bone(skin.get_bind_name(k))
			bone_of_bind.append(bb)
		var am := ArrayMesh.new()
		var src := m.mesh as ArrayMesh
		for si in src.get_surface_count():
			var arr := src.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if gsh.has(m):
				vs = Corrective.girthed(vs, gsh[m][si], lam)
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / maxi(1, vs.size())
			for v in vs.size():
				var acc := Vector3.ZERO
				var wsum := 0.0
				for q in per:
					var w: float = wts[v * per + q]
					if w <= 0.0:
						continue
					var bi: int = bone_of_bind[bones[v * per + q]]
					acc += ((p_new[bi] as Vector3) + float(gs[bi]) * (vs[v] - (p_old[bi] as Vector3))) * w
					wsum += w
				if wsum > 0.0:
					vs[v] = acc / wsum
			arr[Mesh.ARRAY_VERTEX] = vs
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, src.surface_get_format(si) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
			am.surface_set_material(si, src.surface_get_material(si))
		m.mesh = am
		var ns := skin.duplicate() as Skin
		for k in ns.get_bind_count():
			var bb: int = bone_of_bind[k]
			ns.set_bind_pose(k, sk.get_bone_global_rest(bb).affine_inverse() * (rest_old[bb] as Transform3D) * skin.get_bind_pose(k))
		m.skin = ns
