## IMPORT SIDE / FACING / HAND CHECKS (C08; complaints #274 side from geometry, #273 facing axis, #543 hand bend after BVH import).
## Pure functions that read a source rig's rest (Kine joint name -> position in the file's own axes) and return words for the
## import status line; nothing here changes an import. Kine: +Y up, +Z forward, +X the hero's LEFT (data/body_limits.json).
class_name SideChecks

const FACE_WARN_DEG := 30.0   # facing further than this from Kine's +Z gets a line
const PAIRS := ["upperarm", "thigh", "hand", "foot", "clavicle", "calf", "ball"]
const AXES := {"+X": Vector3.RIGHT, "-X": Vector3.LEFT, "+Z": Vector3.BACK, "-Z": Vector3.FORWARD}   # Godot: BACK = +Z


## {"kind": "geometry" | "names only", "swapped", "face_deg", "axis", "warn_sides", "warn_facing"}
## facing = where the feet point (foot -> ball); the character's true left = up x facing; swapped = the bones NAMED _l sit on the right.
static func sides(pos: Dictionary) -> Dictionary:
	var out := {"kind": "names only", "swapped": false, "face_deg": 0.0, "axis": "?", "warn_sides": "", "warn_facing": ""}
	var up := Vector3.UP
	if pos.has("pelvis") and pos.has("head"):
		up = ((pos["head"] as Vector3) - (pos["pelvis"] as Vector3)).normalized()
	var lat := Vector3.ZERO
	for p in PAIRS:
		if pos.has(p + "_l") and pos.has(p + "_r"):
			lat += (pos[p + "_l"] as Vector3) - (pos[p + "_r"] as Vector3)
	lat -= up * lat.dot(up)
	var fw := Vector3.ZERO
	for sd in ["_l", "_r"]:
		if pos.has("foot" + sd) and pos.has("ball" + sd):
			fw += (pos["ball" + sd] as Vector3) - (pos["foot" + sd] as Vector3)
	fw -= up * fw.dot(up)
	if fw.length() < 1e-6 or lat.length() < 1e-6:
		return out
	fw = fw.normalized()
	out["kind"] = "geometry"
	var left := up.cross(fw)
	out["swapped"] = lat.dot(left) < 0.0
	# facing measured against Kine's +Z, in the plane of the rig's floor (ref = the rig's lateral axis read through its names
	# is no help when swapped, so the world axes are the reference: the file's +Z when up is +Y)
	var ref := Vector3.BACK - up * Vector3.BACK.dot(up)
	ref = ref.normalized() if ref.length() > 1e-6 else Vector3.RIGHT
	out["face_deg"] = rad_to_deg(fw.angle_to(ref))
	var best := 2.0
	var an := "?"
	for k in AXES:
		var d := 1.0 - fw.dot(AXES[k])
		if d < best:
			best = d
			an = k
	out["axis"] = an
	if bool(out["swapped"]):
		out["warn_sides"] = "left and right are crossed in this rig: the bones named _l sit on the character's right (read from where its feet point); Kine goes by the names, so the motion will arrive mirrored. Check the names, or mirror the scene after the import"
	if float(out["face_deg"]) > FACE_WARN_DEG:
		out["warn_facing"] = "this rig faces %s (%.0f deg from Kine's +Z); Kine turns each bone from its own rest so the motion should land right, but a mirror made along the file's own axes would flip the wrong way: check the result" % [an, out["face_deg"]]
	return out


## all the words of sides() as an array (empty when nothing is odd)
static func warnings(pos: Dictionary) -> Array:
	var s := sides(pos)
	var w := []
	for k in ["warn_sides", "warn_facing"]:
		if String(s[k]) != "":
			w.append(s[k])
	return w
