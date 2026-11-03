## pose_ikfk.gd - C13 (complaint 469): a saved pose remembers each limb's IK / FK state, and applying it puts the limbs back.
## The pose file gets an optional "ik": {"hand_l": "ik"|"fk", ...} written only when the scene has IK keys on a limb; a file
## with no "ik" field loads and applies exactly as before. State is read at the playhead (blend weight >= 0.5 = IK).
class_name PoseIKFK
extends RefCounted


static func is_ik(S: Scene, tip: String, t: float) -> bool:
	var ks: Array = S.ik.get(tip, [])
	return not ks.is_empty() and LimbIK.weight_at(ks, t) >= 0.5


## {tip: "ik"|"fk"} for the four limbs at t; {} when no limb has any IK key (nothing to remember)
static func state_of(S: Scene, t: float) -> Dictionary:
	var out := {}
	var any := false
	for tip in LimbIK.LIMBS:
		if not (S.ik.get(tip, []) as Array).is_empty():
			any = true
		out[tip] = "ik" if is_ik(S, tip, t) else "fk"
	return out if any else {}


## add the "ik" field to a pose dictionary about to be written (no-op when the scene has no limb IK)
static func stamp(d: Dictionary, S: Scene, t: float) -> void:
	var st := state_of(S, t)
	if not st.is_empty():
		d["ik"] = st


## put the limbs in the saved state at t, B being the body as the pose left it. Returns the tips switched
static func restore(S: Scene, B: Body, want: Variant, t: float) -> Array:
	var done := []
	if not (want is Dictionary):
		return done
	for tip in LimbIK.LIMBS:
		var w: String = (want as Dictionary).get(tip, "")
		if w == "":
			continue
		var now := is_ik(S, tip, t)
		if w == "ik" and not now:
			LimbIK.pin(S, B, tip, t)
			done.append(tip)
		elif w == "fk" and now:
			var key := {"t": t, "target": B.P[tip], "pole": LimbIK.pole_from_pose(B, tip), "w": 0.0, "rot": B.G[tip]}
			LimbIK._hold_before(S, tip, t, S.fps, key)
			LimbIK.put(S.ik, tip, key)
			done.append(tip)
	return done
