## body_check.gd - KINE RUNTIME BODY CHECK (INNOVATIONS N090). Drop the folder addons/kine_body_check into a game with the clips exported from Kine.
## In play it reads a Skeleton3D every frame and flags each bone whose pose is past the human range Kine used
## (limits.json: bend, side and twist in degrees from the rest, per bone name). It needs nothing else from Kine.
## It flags what a blend of clips, a layer or the game's own IK did to a joint, after the animation system has run.
## FRAME: the bone's own axis is local +Y (twist about it), bend = swing about local X, side = swing about local Z, measured from the bone's rest.
## LIMITS: each axis is tested against the larger of its two limits (|min|, |max|), so a rig whose bend sign is flipped is not flagged wrongly;
## the price is that the small side of a one-sided range (an elbow cannot hyperextend) is not policed. Bones are matched by exact name.
extends Node

signal limit_exceeded(bone: String, axis: String, excess_deg: float)

## degrees past the limit before a bone is flagged (the check reads a decomposition, not a goniometer)
@export var tolerance_deg := 2.0
@export var skeleton: Skeleton3D
@export var enabled := true
@export var print_warnings := true

var limits := {}
var _last := {}


func _ready() -> void:
	load_limits("res://addons/kine_body_check/limits.json")


func load_limits(path: String) -> bool:
	var txt := FileAccess.get_file_as_string(path)
	var d = JSON.parse_string(txt)
	if d is Dictionary:
		limits = d
		return true
	return false


func _process(_dt: float) -> void:
	if not enabled or skeleton == null:
		return
	var now := {}
	for f in check(skeleton):
		now[f["bone"]] = true
		if not _last.has(f["bone"]):
			limit_exceeded.emit(f["bone"], f["axis"], f["excess_deg"])
			if print_warnings:
				push_warning("%s is %.0f deg past its human %s limit (%.0f)" % [f["bone"], f["excess_deg"], f["axis"], f["limit_deg"]])
	_last = now


## [{bone, axis, angle_deg, limit_deg, excess_deg}] one per bone past a limit by more than tolerance_deg (its worst axis); [] when all is well
func check(sk: Skeleton3D) -> Array:
	var out := []
	for i in sk.get_bone_count():
		var nm := sk.get_bone_name(i)
		if not limits.has(nm):
			continue
		var q: Quaternion = sk.get_bone_rest(i).basis.get_rotation_quaternion().inverse() * sk.get_bone_pose_rotation(i)
		var a := angles(q)
		var worst := {}
		var best := tolerance_deg
		for axis in ["bend", "side", "twist"]:
			var r: Array = limits[nm][axis]
			var lim := maxf(absf(float(r[0])), absf(float(r[1])))
			var ex := absf(float(a[axis])) - lim
			if ex > best:
				best = ex
				worst = {"bone": nm, "axis": axis, "angle_deg": float(a[axis]), "limit_deg": lim, "excess_deg": ex}
		if not worst.is_empty():
			out.append(worst)
	return out


## swing-twist about local Y: {bend (about X), side (about Z), twist (about Y)} in degrees
static func angles(q_in: Quaternion) -> Dictionary:
	var q := q_in.normalized()
	if q.w < 0.0:
		q = Quaternion(-q.x, -q.y, -q.z, -q.w)
	var tw := Quaternion(0.0, q.y, 0.0, q.w)
	var twist := 0.0
	if tw.length() > 1e-9:
		tw = tw.normalized()
		twist = rad_to_deg(2.0 * atan2(tw.y, tw.w))
	else:
		tw = Quaternion.IDENTITY
	var sw := q * tw.inverse()
	var ang := 2.0 * acos(clampf(sw.w, -1.0, 1.0))
	var s := sqrt(maxf(1.0 - sw.w * sw.w, 0.0))
	var ax := Vector3(sw.x, sw.y, sw.z) / s if s > 1e-9 else Vector3.ZERO
	return {"bend": rad_to_deg(ang) * ax.x, "side": rad_to_deg(ang) * ax.z, "twist": twist}
