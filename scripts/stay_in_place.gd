class_name StayInPlace
extends RefCounted
## StayInPlace (C42, complaint S #7): an opt-in export switch. ON: the pelvis's HORIZONTAL travel (forward / sideways, since frame 0) is
## taken off the animation, so the clip plays on the spot. The height stays, every joint's rotation stays, and the bones are all
## children of the pelvis, so each foot keeps its place relative to the body. OFF (the default): the exporter does nothing here.
## `last` holds the numbers of the most recent build: {"before": m of travel frame 0 -> last frame, "after": the same read from
## the keys that were written}. words() is the sentence for the status line.

static var on := false
static var last := {}


static func reset() -> void:
	last = {"before": 0.0, "after": 0.0, "peak_before": 0.0, "peak_after": 0.0, "frames": 0}


## the horizontal part of a travel vector (Y is the height)
static func flat(d: Vector3) -> Vector3:
	return Vector3(d.x, 0.0, d.z)


## one frame: D = the pelvis's world offset from frame 0. Returns the vector to subtract from the pelvis's local key (and from
## weapon positions): D flattened when on, zero when off. Records the numbers.
static func frame(D: Vector3, k: int, last_frame: bool) -> Vector3:
	if k == 0:
		reset()
	var T := flat(D)
	last["frames"] = int(last.get("frames", 0)) + 1
	last["peak_before"] = maxf(float(last["peak_before"]), T.length())
	if last_frame:
		last["before"] = T.length()
	var rem := Vector3.ZERO if not on else T
	var left := T - rem
	last["peak_after"] = maxf(float(last["peak_after"]), left.length())
	if last_frame:
		last["after"] = left.length()
	return rem


static func words() -> String:
	if not on or last.is_empty():
		return ""
	return "; stays in place: travel %.2f m -> %.2f m (peak %.2f -> %.2f m)" % [last["before"], last["after"], last["peak_before"], last["peak_after"]]
