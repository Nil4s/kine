## MULTI-OBJECT EDITING (L120, ROADMAP_400 P10): the maths of the Transform panel on several props at once. Pure functions on
## prop records (S.props[i]); main.gd wraps each edit in ONE undo step.
##   fields: "x" "y" "z" (the prop's origin, metres) and "rot" (yaw, degrees)
##   absolute: every selected prop gets the value. relative: every prop is its OWN start plus the same delta.
##   a field whose values differ shows MIXED ("—") until it is set.
class_name MultiEdit
extends RefCounted

const FIELDS := ["x", "y", "z", "rot"]
const MIXED := "—"
const TOL := 0.0005
## label-scrub rates: metres per pixel, degrees per pixel
const RATE := {"x": 0.01, "y": 0.01, "z": 0.01, "rot": 1.0}


static func value(p: Dictionary, f: String) -> float:
	var xf: Transform3D = p["xf"]
	match f:
		"x": return xf.origin.x
		"y": return xf.origin.y
		"z": return xf.origin.z
	return Props.yaw_of(xf)


## the prop's transform with field f moved by d (from `start`, the transform it had when the edit began)
static func moved(start: Transform3D, f: String, d: float) -> Transform3D:
	var xf := start
	match f:
		"x": xf.origin.x += d
		"y": xf.origin.y += d
		"z": xf.origin.z += d
		_: xf.basis = Basis(Vector3.UP, deg_to_rad(d)) * start.basis
	return xf


## absolute: field f of p becomes v
static func set_abs(p: Dictionary, f: String, v: float) -> void:
	var xf: Transform3D = p["xf"]
	match f:
		"x": xf.origin.x = v
		"y": xf.origin.y = v
		"z": xf.origin.z = v
		_: xf = moved(xf, "rot", angle_wrapped(v - Props.yaw_of(xf)))
	p["xf"] = xf


static func angle_wrapped(deg: float) -> float:
	return rad_to_deg(angle_difference(0.0, deg_to_rad(deg)))


## whether the selected props disagree on field f
static func mixed(props: Array, idxs: Array, f: String) -> bool:
	if idxs.size() < 2:
		return false
	var v0 := value(props[idxs[0]], f)
	for k in range(1, idxs.size()):
		var v := value(props[idxs[k]], f)
		var diff := absf(angle_wrapped(v - v0)) if f == "rot" else absf(v - v0)
		if diff > TOL:
			return true
	return false


## what the field shows: the marker when mixed, else the shared value
static func text(props: Array, idxs: Array, f: String) -> String:
	if idxs.is_empty():
		return ""
	if mixed(props, idxs, f):
		return MIXED
	return "%.3f" % (value(props[idxs[0]], f) + 0.0)
