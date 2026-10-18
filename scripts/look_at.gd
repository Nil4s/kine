class_name LookAt
extends RefCounted
## LOOK AT (round 42, GATES XX6, UPGRADES_300 #271): turn the neck and head so the gaze points at a world point.
##
## REAL PEOPLE (read, PubMed 9163361: Freedman & Sparks 1997, J Neurophysiol 77(5):2328-48, https://pubmed.ncbi.nlm.nih.gov/9163361/):
## "Head movements did not contribute to the change in gaze position during small gaze shifts (<20 degrees) ...
## when the eyes were initially centered in the orbits. For larger gaze shifts (25-90 degrees), the head contribution
## to the gaze shift increased linearly with increasing gaze shift amplitude, and eye movement amplitude saturated at
## an asymptotic amplitude of approximately 35 degrees." CAVEAT: those are rhesus monkeys, head unrestrained; no
## human number was read, so the human curve is UNVERIFIED and the monkey one is used as the best read source.
## The curve here fits those three read numbers: head = 0 up to EYE_ONLY (20), then HEAD_SLOPE (0.786) per degree,
## which puts the eye at 35 degrees when the gaze shift is 90 (head 55 of 90 = 61 %). The neck takes NECK_SHARE of the
## head-and-neck turn first (the split between neck and head is NOT in the source: a modelling choice).
##
## THIS BODY HAS NO EYES (data/skeleton.json has no eye joint, no face rig): by default the WHOLE gaze shift goes to the
## neck and head, whatever its size, and the gaze is the head's forward. With eyes := true the eye-in-orbit offset is
## computed (and returned, as eye_yaw / eye_pitch) so a renderer with eyes can use it; the joints then follow the curve.
## The eye sits at EYE_LOCAL in the head's frame (an estimate: half the head's length up, 9 cm forward).

const EYE_ONLY := 20.0
const EYE_MAX := 35.0
const HEAD_SLOPE := 0.786   # (90 - 35) / (90 - 20): the head's degrees per degree of gaze shift above EYE_ONLY
const NECK_SHARE := 0.4
const FWD := Vector3(0, 0, 1)


## the head's contribution (deg) to a gaze shift of amp degrees (eyes available)
static func head_part(amp: float) -> float:
	return maxf(0.0, amp - EYE_ONLY) * HEAD_SLOPE


static func eye_point(B: Body) -> Vector3:
	var g: Quaternion = B.G["head"]
	var up: Vector3 = ((B.e0["head"] as Vector3) - (B.p0["head"] as Vector3)) * 0.5
	return (B.P["head"] as Vector3) + g * (up + FWD * 0.09)


static func head_forward(B: Body) -> Vector3:
	return ((B.G["head"] as Quaternion) * FWD).normalized()


## the angle (deg) between the head's forward and the line from the eye to the target
static func amplitude(B: Body, target: Vector3) -> float:
	var d := target - eye_point(B)
	if d.length() < 1e-6:
		return 0.0
	return rad_to_deg(head_forward(B).angle_to(d.normalized()))


## turn joint j by deg degrees about the axis taking the head's forward toward dir (character space)
static func _swing(B: Body, j: String, dir: Vector3, deg: float) -> void:
	var f := head_forward(B)
	var ax := f.cross(dir)
	if ax.length() < 1e-7 or absf(deg) < 1e-9:
		return
	B.turn_world(j, Quaternion(ax.normalized(), deg_to_rad(deg)))


## Point the gaze at target (world). Returns {error (deg, gaze vs target), amp (deg, the shift asked), head_deg, share
## (head's part of amp, 0..1), eye_yaw, eye_pitch (deg, 0 without eyes), reachable (error <= 0.5), eyes}.
## Pose unchanged when already looking at the target. A target at the eye itself changes nothing.
static func solve(B: Body, target: Vector3, eyes := false) -> Dictionary:
	B.fk()
	var amp := amplitude(B, target)
	var out := {"amp": amp, "head_deg": 0.0, "share": 0.0, "eye_yaw": 0.0, "eye_pitch": 0.0, "eyes": eyes}
	if amp < 1e-4:
		out["error"] = 0.0
		out["reachable"] = true
		return out
	var want := amp if not eyes else head_part(amp)   # what the neck and head are to turn
	var f0 := head_forward(B)
	if want > 1e-6:
		var goal_f := f0
		# the forward the head is to reach: f0 swung toward the target by `want`
		var d0 := (target - eye_point(B)).normalized()
		goal_f = Quaternion(f0.cross(d0).normalized(), deg_to_rad(want)) * f0
		_swing(B, "neck_01", goal_f, want * NECK_SHARE)
		B.fk()
		for it in 12:   # the turn moved the eye; aim again at where the target is NOW (no eyes) or at the goal (eyes)
			var aim := goal_f if eyes else (target - eye_point(B)).normalized()
			var rem := rad_to_deg(head_forward(B).angle_to(aim))
			if rem < 0.02:
				break
			var before := head_forward(B)
			_swing(B, "head", aim, rem)
			B.fk()
			rem = rad_to_deg(head_forward(B).angle_to(aim if eyes else (target - eye_point(B)).normalized()))
			if rem < 0.02:
				break
			_swing(B, "neck_01", aim if eyes else (target - eye_point(B)).normalized(), rem)
			B.fk()
			if rad_to_deg(before.angle_to(head_forward(B))) < 1e-4:
				break   # both joints are at a stop: what is left is the reported error
	var f1 := head_forward(B)
	out["head_deg"] = rad_to_deg(f0.angle_to(f1))
	var d := (target - eye_point(B)).normalized()
	if eyes:
		var off := rad_to_deg(f1.angle_to(d))
		var k := minf(off, EYE_MAX)
		# eye-in-head yaw / pitch: the offset d seen in the head's frame
		var loc := (B.G["head"] as Quaternion).inverse() * d
		out["eye_yaw"] = rad_to_deg(atan2(loc.x, loc.z))
		out["eye_pitch"] = rad_to_deg(asin(clampf(loc.y, -1.0, 1.0)))
		out["error"] = maxf(0.0, off - EYE_MAX) if off > EYE_MAX else 0.0
		out["eye_deg"] = k
	else:
		out["error"] = rad_to_deg(f1.angle_to(d))
	out["share"] = float(out["head_deg"]) / amp
	out["reachable"] = float(out["error"]) <= 0.5
	return out
