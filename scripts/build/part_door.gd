class_name PartDoor
extends RefCounted
## C18 PART BEHAVIOUR. Three small, opt-in rules (nothing here changes what an unmarked part, or the Join touch tolerance, did before):
##  #334 DOOR MARK   rec["doors"] = {"<body>": {"side": "left"|"right"}}. Swing it on a marked body puts the hinge axis on the door's hinge edge
##                   (the vertical edge at its left or right end) instead of the back top edge. An unmarked body gets the old hinge: swing_hinge() returns it.
##  #291 JOIN NOTE   the first Join says once that it can be undone (Ctrl+Z, or the step list); a flag file in user:// remembers it.
##  #297 TOLERANCE   JOIN_TOUCH_M (0.05 mm, the value Join always used) stays. A part with rec["tol_scaled"] = true uses touch_tol(): never more than
##                   JOIN_TOUCH_M, and never more than 0.2 pct of the smaller piece's smallest side, so a 1 mm piece does not count 0.04 mm apart as touching.
const JOIN_TOUCH_M := 0.00005
const NOTE_FILE := "user://join_undo_note_seen.flag"
const NOTE_TEXT := "Join can be undone: press Ctrl+Z, or click the step before it in the step list."
const SIDES := ["", "left", "right"]


static func side_of(rec: Dictionary, body: int) -> String:
	var d = rec.get("doors")
	if d is Dictionary and (d as Dictionary).get(str(body)) is Dictionary:
		var s := String(((d as Dictionary)[str(body)] as Dictionary).get("side", ""))
		return s if s in ["left", "right"] else ""
	return ""


static func mark(rec: Dictionary, body: int, side: String) -> void:
	if not (rec.get("doors") is Dictionary):
		rec["doors"] = {}
	if side in ["left", "right"]:
		(rec["doors"] as Dictionary)[str(body)] = {"side": side}
	else:
		(rec["doors"] as Dictionary).erase(str(body))
		if (rec["doors"] as Dictionary).is_empty():
			rec.erase("doors")


## the hinge Swing it makes for body `body` whose box (metres) is lo..hi: {"o": mm, "axis": unit}. Unmarked: the back top edge, axis X (as before)
static func swing_hinge(rec: Dictionary, body: int, lo: Vector3, hi: Vector3) -> Dictionary:
	var side := side_of(rec, body)
	if side == "":
		var o := Vector3(lo.x, hi.y, lo.z) / Part.MM
		return {"o": o, "axis": Vector3(1, 0, 0)}
	var x := lo.x if side == "left" else hi.x
	var o2 := Vector3(x, lo.y, hi.z) / Part.MM   # the bottom of the vertical edge on the front face: the axis runs up it
	return {"o": o2, "axis": Vector3(0, -1, 0) if side == "left" else Vector3(0, 1, 0)}   # both leaves swing toward the viewer


## the option under Swing it: Not a door / Door hinged on the left / on the right
static func make_option() -> OptionButton:
	var o := OptionButton.new()
	o.name = "easypart_door_side"
	o.add_item("Not a door")
	o.add_item("Door, hinged on the left")
	o.add_item("Door, hinged on the right")
	o.tooltip_text = "Swing it: a door turns about its own hinge edge (the left or right end) instead of the back top edge"
	o.custom_minimum_size = Vector2(170, 44)
	return o


static func side_from_option(o: OptionButton) -> String:
	return SIDES[clampi(o.selected, 0, 2)] if o != null else ""


## "" the first time a Join happens, then the note; the flag lives in user:// (a test's own APPDATA)
static func join_note() -> String:
	if FileAccess.file_exists(NOTE_FILE):
		return ""
	var f := FileAccess.open(NOTE_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string("1")
		f.close()
	return NOTE_TEXT


## the touch tolerance (metres) for two pieces with smallest sides a_min and b_min (metres)
static func touch_tol(rec: Dictionary, a_min: float, b_min: float) -> float:
	if not bool(rec.get("tol_scaled", false)):
		return JOIN_TOUCH_M
	return minf(JOIN_TOUCH_M, 0.002 * minf(a_min, b_min))


static func min_side(tris: PackedVector3Array) -> float:
	if tris.is_empty():
		return 0.0
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in tris:
		lo = lo.min(v)
		hi = hi.max(v)
	var s := hi - lo
	return minf(s.x, minf(s.y, s.z))
