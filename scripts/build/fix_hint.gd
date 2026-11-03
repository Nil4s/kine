class_name FixHint
extends RefCounted
## C21: every failed-step message ends with a "how to fix" sentence. The message a step gave stays exactly as it was (tests and
## people read its start); this only APPENDS " How to fix: ..." once. A step type has a default; a few wordings get a sharper one.

const MARK := " How to fix: "

const DEFAULTS := {
	"sketch": "open the sketch and close the outline, or remove the lines that cross, then the step runs again",
	"extrude": "check the sketch is one closed outline, give the pull a distance above zero, or Undo the step",
	"revolve": "keep the whole outline on one side of the turning line, or Undo the step",
	"prim": "give every size a number above zero, or Undo the step",
	"plane": "change the plane's numbers so the points are not in a line, or delete the plane",
	"loft": "pick two or more closed profiles in order, with the same number of corners if you can, or Undo the step",
	"sweep": "draw the path as one open line that does not fold on itself, keep the profile closed, or Undo the step",
	"pattern": "pick a body that exists and a smaller count or gap, or Undo the step",
	"instances": "pick a face of a body that still exists, or Undo the step",
	"fillet": "type a smaller radius or pick fewer edges, then try again",
	"chamfer": "type a smaller size or pick fewer edges, then try again",
	"move": "pick a piece that still exists, or Undo the move",
	"offset_face": "move the face by a smaller amount, or pick another face",
	"draft": "use a smaller angle, or pick another face",
	"offset": "use a smaller distance so no wall folds through itself, or Undo the step",
	"bulge": "pick a flat face and use a smaller push, or Undo the step",
	"split": "put the cutting plane through the body, or Undo the step",
	"shell": "use a thinner wall, or pick a face that exists to open, or Undo the step",
	"fitobj": "make the holder bigger than the object, or Undo the step",
	"pipe3d": "place at least two points that are apart, or Undo the step",
	"meshsolid": "close the holes of the sculpt, then sew it again",
	"roof": "use a smaller overhang or a larger footprint, or Undo the step",
	"ornament": "pick another size for the ornament, or Undo the step",
	"lattice": "use thinner bars or a bigger box, or Undo the step",
	"mirror": "pick a body that exists, or Undo the step",
	"lay": "add a body first, or Undo the step",
	"combine": "pick bodies that both exist and touch, or Undo the step",
	"align": "pick two pieces that both exist, or Undo the step",
	"hinge": "pick a body and a curve that exist, or Undo the step",
	"appear": "pick a body that exists, or Undo the step",
	"bname": "pick a body that exists, or Undo the step",
}
const GENERIC := "open this step and change its numbers, or Undo it; the Fix it button in the top bar tries the common repairs"


## the message with the how-to-fix sentence at its end (idempotent: a message that already has one is returned as it is)
static func add(msg: String, step_type := "") -> String:
	if msg == "" or msg.contains(MARK):
		return msg
	var lo := msg.to_lower()
	var how := ""
	if lo.contains("suppressed") or lo.contains("was deleted"):
		how = "bring the step back or delete the one that needs it"
	elif lo.contains("no body") or lo.contains("nothing to"):
		how = "pick a body that exists in the list, or Undo the step that removed it"
	elif lo.contains("no sketch") or lo.contains("no profile") or lo.contains("not closed") or lo.contains("open outline"):
		how = "draw a closed outline in a sketch first, then pull it"
	elif lo.contains("cross"):
		how = "move or delete the lines that cross, so the outline is one clean loop"
	elif lo.contains("too thick") or lo.contains("too large") or lo.contains("too big") or lo.contains("too deep") or lo.contains("too long"):
		how = "type a smaller number in this step"
	elif lo.contains("too thin") or lo.contains("too small") or lo.contains("zero"):
		how = "type a bigger number in this step"
	if how == "":
		how = String(DEFAULTS.get(step_type, GENERIC))
	var sep := "" if msg.ends_with(".") or msg.ends_with("!") or msg.ends_with("?") else "."
	return msg + sep + MARK + how + "."


## every message of a replay's error table, in place
static func apply(errs: Dictionary, feats: Array) -> void:
	if errs.is_empty():
		return
	var types := {}
	for f in feats:
		types[String(f.get("id", ""))] = String(f.get("t", ""))
	for k in errs.keys():
		errs[k] = add(String(errs[k]), String(types.get(String(k), "")))
