## strength_curves.gd - N039 STRENGTH CURVES. A joint's torque cap follows its angle: cap(angle) = ForceView.LIMIT_NM (the peak, at 75 kg) x curve(angle).
## The curve is a table of (joint angle deg, fraction of the peak), linear between points. Two joints have curves; every other joint keeps its constant cap.
##  KNEE EXTENSION (the "calf" joint), angle = knee flexion from full extension: peak at 71 deg (Kooistra, de Ruiter & de Haan 2007, Eur J Appl Physiol 100:309,
##   71 +- 1.4 deg), 77.9 % of the peak at 100 deg in men (Marginson & Eston 2001, J Sports Sci 19:875, boys-and-men knee extension), about 40 % at full extension
##   (Kulig, Andrews & Hay 1984, Exerc Sport Sci Rev 12:417; my round number). The points between are drawn by hand through those.
##  ELBOW FLEXION (the "lowerarm" joint), angle = elbow flexion: peak at 90 deg (Kulig 1984; Knapik et al. 1983, Phys Ther 63:938), about 55 % at full extension
##   (round number from the same figures). Points between are by hand.
## ALL quoted from memory (UNVERIFIED). Angles are read from the pose: flexion = 180 deg - the angle at the joint between the two bones (positions of the
## neighbouring joints, so no Euler convention is involved).
class_name StrengthCurves
extends RefCounted

const TABLE := {
	"calf": {"peak": 71.0, "pts": [[0.0, 0.40], [30.0, 0.78], [50.0, 0.94], [71.0, 1.0], [100.0, 0.779], [120.0, 0.62], [140.0, 0.45]], "bones": ["thigh", "calf", "foot"]},
	"lowerarm": {"peak": 90.0, "pts": [[0.0, 0.55], [30.0, 0.80], [60.0, 0.94], [90.0, 1.0], [120.0, 0.88], [140.0, 0.70], [150.0, 0.60]], "bones": ["upperarm", "lowerarm", "hand"]},
}
const WEAK_BELOW := 1.0   # a push the constant cap passes (ratio < 1) and the curve fails (>= 1)


static func has_curve(j: String) -> bool:
	return TABLE.has(ForceView.kind_of(j))


## fraction of the peak at an angle (deg); 1 for a joint with no curve
static func factor(j: String, angle: float) -> float:
	var k := ForceView.kind_of(j)
	if not TABLE.has(k):
		return 1.0
	var pts: Array = TABLE[k]["pts"]
	if angle <= float(pts[0][0]):
		return float(pts[0][1])
	for i in range(1, pts.size()):
		if angle <= float(pts[i][0]):
			var a: Array = pts[i - 1]
			var b: Array = pts[i]
			var u := (angle - float(a[0])) / (float(b[0]) - float(a[0]))
			return lerpf(float(a[1]), float(b[1]), u)
	return float(pts[pts.size() - 1][1])


static func cap_nm(j: String, mass: float, angle: float) -> float:
	return ForceView.limit_nm(j, mass) * factor(j, angle)


## flexion (deg) of a joint with curve from the joint positions {name: Vector3}; -1 when it has none
static func flexion(j: String, pj: Dictionary) -> float:
	var k := ForceView.kind_of(j)
	if not TABLE.has(k):
		return -1.0
	var sd := j.substr(k.length())
	var bn: Array = TABLE[k]["bones"]
	var a: Vector3 = pj[String(bn[0]) + sd]
	var b: Vector3 = pj[String(bn[1]) + sd]
	var c: Vector3 = pj[String(bn[2]) + sd]
	return 180.0 - rad_to_deg((a - b).angle_to(c - b))


## {joint: [flexion deg per sample]} for the joints with curves, from a ForceView capture
static func angles(cap: Dictionary) -> Dictionary:
	var out := {}
	for sd in ["_l", "_r"]:
		for k in TABLE:
			var j: String = k + sd
			var a := []
			for i in int(cap["n"]):
				a.append(flexion(j, cap["ps"][i]))
			out[j] = a
	return out


## the judges on the curve: {tau: {j: [Nm]}} and {j: [deg]} -> {"ratio": {j: [tau / curve cap]}, "ratio_const": {...}, "weak": [{joint, frame, angle, tau, cap_const, cap_curve, ratio_const, ratio_curve}]}
## weak = tau passes the constant cap and fails the curve's at that angle.
static func check(tau: Dictionary, ang: Dictionary, mass: float) -> Dictionary:
	var ratio := {}
	var rconst := {}
	var weak := []
	for j in ang:
		var rr := []
		var rc := []
		var cc := ForceView.limit_nm(j, mass)
		for i in (tau[j] as Array).size():
			var cv := cap_nm(j, mass, float(ang[j][i]))
			var t := float(tau[j][i])
			rr.append(t / cv)
			rc.append(t / cc)
			if t / cc < WEAK_BELOW and t / cv >= WEAK_BELOW:
				weak.append({"joint": j, "frame": i, "angle": float(ang[j][i]), "tau": t, "cap_const": cc, "cap_curve": cv, "ratio_const": t / cc, "ratio_curve": t / cv})
		ratio[j] = rr
		rconst[j] = rc
	weak.sort_custom(func(a, b): return int(a["frame"]) < int(b["frame"]) if int(a["frame"]) != int(b["frame"]) else String(a["joint"]) < String(b["joint"]))
	return {"ratio": ratio, "ratio_const": rconst, "weak": weak}
