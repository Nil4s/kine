## drivers.gd - USER DRIVERS (docs/GAP_ANALYSIS.md row 15: "'shoulders follow the arm' is one hard-wired driver; no user
## drivers"). A driver makes one joint's angle follow another's, every frame:
##     driven = source * factor + offset        (degrees, per axis: 0 bend, 1 side, 2 twist)
## Blender's driver of the simple expression type; Maya's set driven key with a linear curve. Example: the clavicle
## raises 0.3 deg for every deg the upper arm raises above 90:
##     {"driven": "clavicle_r", "axis": 0, "source": "upperarm_r", "src_axis": 0, "factor": 0.3, "offset": 0, "from": 90}
##
## "from" (optional): the source counts only above it, so the value uses max(source - from, 0) in place of the source.
## Below the threshold the driven angle is the offset alone. Without "from" the source counts all the way down.
##
## WHERE IT RUNS (Scene.apply): after the cards, the layers and the breathing, and BEFORE IK and the constraints. Blender
## evaluates drivers before constraints too: a driven joint is an input to the stack above it, so an IK hand or a Child
## Of reads the driven clavicle, not the card's old value. Drivers run in list order: a driver reads its source as the
## earlier drivers left it, so one driver can feed another.
##
## Every written angle goes through Body.clamp_ang (the joint limits), as LimbIK and the constraints do. A scene with
## no drivers never calls play(): its poses are untouched, byte for byte.
##
## IN THE FILE: "drivers": [{"driven", "axis", "source", "src_axis", "factor", "offset", "from"?}] in list order, written
## only when there is one (Scene.to_dict). Joints are Body.ORDER names; axes 0..2.
class_name Drivers
extends RefCounted


## the driven value from the source's value (deg) and the driver's terms
static func value(d: Dictionary, src: float) -> float:
	var s := src
	if d.has("from"):
		s = maxf(src - float(d["from"]), 0.0)
	return s * float(d["factor"]) + float(d["offset"])


## THE PASS (Scene.apply): each driver in list order, its driven axis set from its source's current angle, clamped.
## Returns [{"driven", "axis", "value", "clamped"}] for the drivers that wrote something ([] = the body was not touched)
static func play(drv: Array, B: Body) -> Array:
	var out := []
	for d in drv:
		var src_j: String = d["source"]
		var dj: String = d["driven"]
		if not B.ang.has(src_j) or not B.ang.has(dj):
			continue
		var src := (B.ang[src_j] as Vector3)[int(d["src_axis"])]
		var v := value(d, src)
		var a := B.ang[dj] as Vector3
		a[int(d["axis"])] = v
		var c := B.clamp_ang(dj, a)
		B.ang[dj] = c
		out.append({"driven": dj, "axis": int(d["axis"]), "value": v, "clamped": absf(c[int(d["axis"])] - v) > 1e-9})
	if not out.is_empty():
		B.fk()
	return out


## the index of the first driver on joint j (as the follower), -1 = none
static func on(drv: Array, j: String) -> int:
	for i in drv.size():
		if String(drv[i]["driven"]) == j:
			return i
	return -1


## a driver for the same driven axis replaces the old one (its place kept); else appended. Returns its index
static func put(drv: Array, d: Dictionary) -> int:
	for i in drv.size():
		if drv[i]["driven"] == d["driven"] and int(drv[i]["axis"]) == int(d["axis"]):
			drv[i] = d
			return i
	drv.append(d)
	return drv.size() - 1


## takes off every driver on joint j; returns how many
static func remove_on(drv: Array, j: String) -> int:
	var n := 0
	for i in range(drv.size() - 1, -1, -1):
		if String(drv[i]["driven"]) == j:
			drv.remove_at(i)
			n += 1
	return n


## IN THE FILE (the scene's own form; from_file reads it back)
static func to_file(drv: Array) -> Array:
	var out := []
	for d in drv:
		var o := {"driven": d["driven"], "axis": int(d["axis"]), "source": d["source"], "src_axis": int(d["src_axis"]),
			"factor": snappedf(float(d["factor"]), 0.0001), "offset": snappedf(float(d["offset"]), 0.0001)}
		if d.has("from"):
			o["from"] = snappedf(float(d["from"]), 0.0001)
		out.append(o)
	return out


static func from_file(a: Variant) -> Array:
	var out := []
	if not a is Array:
		return out
	for d in a:
		if not (d is Dictionary and d.has("driven") and d.has("source") and d.has("factor")):
			continue
		var dj := String(d["driven"])
		var sj := String(d["source"])
		var ax := int(d.get("axis", 0))
		var sa := int(d.get("src_axis", 0))
		if not (dj in Body.ORDER and sj in Body.ORDER) or (dj == sj and ax == sa):
			continue   # a joint's own angle as its source is a loop, not a driver
		if ax < 0 or ax > 2 or sa < 0 or sa > 2:
			continue
		var k := {"driven": dj, "axis": ax, "source": sj, "src_axis": sa,
			"factor": float(d["factor"]), "offset": float(d.get("offset", 0.0))}
		if d.has("from"):
			k["from"] = float(d["from"])
		out.append(k)
	return out


## THE SIGN an axis takes under Mirror (Body.mirror_pose reflects the pose across x = 0): the probe is a 10 deg angle
## put on joint j's axis a and mirrored; its twin's angle on that axis gives +1 or -1. M is a scratch body.
static func _sign(M: Body, j: String, a: int) -> float:
	for k in Body.ORDER:
		M.ang[k] = Vector3.ZERO
	var v := Vector3.ZERO
	v[a] = 10.0
	M.ang[j] = M.clamp_ang(j, v)
	M.mirror_pose()
	var o: Vector3 = M.ang[Body.twin(j)]
	return signf(o[a]) if absf(o[a]) > 1e-3 else 1.0


## MIRRORED (Scene.MIRROR_SCENE "drivers"): driven and source to their twins. The mirrored driven angle is sd x the
## original (sd = the sign of the driven axis), the mirrored source is ss x the original, so the factor becomes
## factor x sd x ss and the offset sd x offset. A threshold ("from") is kept as it is: exact for a source whose sign is
## +1 (a bend, the arm raise), approximate for a sided source (a side or twist) that has one, since the file has no
## "count below" form. The file form is unchanged otherwise.
static func mirror_file(drv: Array, M: Body) -> Array:
	var out := []
	for d in drv:
		var sd := _sign(M, d["driven"], int(d["axis"]))
		var ss := _sign(M, d["source"], int(d["src_axis"]))
		var m := {"driven": Body.twin(d["driven"]), "axis": int(d["axis"]), "source": Body.twin(d["source"]),
			"src_axis": int(d["src_axis"]), "factor": float(d["factor"]) * sd * ss, "offset": float(d["offset"]) * sd}
		if d.has("from"):
			m["from"] = float(d["from"])
		out.append(m)
	return out
