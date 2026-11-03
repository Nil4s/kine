## MIRROR FACING (C47, complaint #273: Cascadeur's mirror is "off" unless the character faces +Z): the facing axis from the GEOMETRY.
## Body.mirror_pose reflects across x = 0, which is right for a body that faces +Z (Kine's frame, +X = the hero's left). A body that
## is turned (its hips and shoulders say it faces +X, -Z ...) mirrors to the wrong place under that rule. This reads the body's
## left axis from the joints themselves (the hips) and takes the heading from it. Opt-in: Body.mirror_pose
## is not touched; "Mirror to facing" calls MirrorFacing.mirror(B).
##   A body whose hips are within 45 deg of Kine's frame (every body in Kine's frame, with the twist of a normal move) mirrors
##   EXACTLY as before (the same Body.mirror_pose call, byte for byte).
##   A turned body: the heading turn is taken out of the pelvis (and out of the hips' offset and the free weapon), the usual mirror
##   runs, and the turn is put back. The body keeps its heading; left and right swap; mirroring twice gives the pose back.
class_name MirrorFacing
extends RefCounted


## the heading in degrees from the hips: 0 = faces +Z (left = +X), 90 = left is -Z (the hero faces +X). The hips are fixed by the
## pelvis alone (a spine twist or a raised arm does not move them). 0 when the geometry gives no left axis.
static func heading(B: Body) -> float:
	var d: Vector3 = (B.P["thigh_l"] as Vector3) - (B.P["thigh_r"] as Vector3)
	d.y = 0.0
	if d.length() < 1e-4:
		return 0.0
	return rad_to_deg(atan2(-d.z, d.x))


## which rule a body takes: {"heading" (the quarter turn nearest the hips: 0, 90, -90, 180), "raw", "turned"}. A pelvis twists up to
## about 45 deg inside a move, so the heading is taken to the nearest quarter turn; a body turned by anything between is read as the
## nearer quarter (stated limit: a body turned 30 deg is mirrored as a front-facing one).
static func detect(B: Body) -> Dictionary:
	var raw := heading(B)
	var q := wrapf(roundf(raw / 90.0) * 90.0, -179.0, 181.0)
	return {"heading": q, "raw": raw, "turned": absf(q) > 1.0}


static func _turn(B: Body, deg: float) -> void:
	var r := Quaternion(Vector3.UP, deg_to_rad(deg))
	B.ang["pelvis"] = B.decompose("pelvis", r * B.compose("pelvis", B.ang["pelvis"]))
	B.offset = r * B.offset
	if B.wep_hand == "":
		B.wep_pos = r * B.wep_pos
		B.wep_rot = r * B.wep_rot


## the whole pose mirrored through the body's own middle plane. Returns the detection.
static func mirror(B: Body) -> Dictionary:
	var d := detect(B)
	if not d["turned"]:
		B.mirror_pose()
		return d
	var h: float = d["heading"]
	_turn(B, -h)
	B.fk()
	B.mirror_pose()
	_turn(B, h)
	B.fk()
	return d
